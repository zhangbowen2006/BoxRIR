///|
/// All frame positions in this report are absolute positions in the input
/// WAVs. A positive lag means the observed waveform occurred later.
pub(all) struct ResponseDifference {
  status : String
  reference_start : Int32
  requested_observed_start : Int32
  observed_start : Int32
  observed_lag_frames : Int32
  lag_trials : Int32
  signed_correlation : Double?
  reference_to_observed_gain : Double?
  observed_energy_delta_db : Double?
  raw_error_ratio : Double?
  adjusted_error_ratio : Double?
}

///|
pub(all) struct ResponseComparison {
  sample_rate : Int32
  reference_frames : Int32
  observed_frames : Int32
  compared_frames : Int32
  channels : Array[ResponseDifference]
}

///|
priv struct ComparisonWindow {
  reference_start : Int32
  observed_start : Int32
  minimum_lag : Int32
  maximum_lag : Int32
}

///|
priv struct WindowEnergy {
  cross : Double
  x_power : Double
  y_power : Double
  x_peak : Double
  y_peak : Double
  raw_residual : Double
}

///|
fn comparison_peak(
  signal : Array[Double],
  start : Int32,
  length : Int32,
) -> Double {
  let mut peak = 0.0
  for i in start..<(start + length) {
    peak = peak.max(signal[i].abs())
  }
  peak
}

///|
fn comparison_energy(
  x : Array[Double],
  y : Array[Double],
  x_origin : Int32,
  y_origin : Int32,
  frames : Int32,
  x_peak : Double,
) -> WindowEnergy {
  let y_peak = comparison_peak(y, y_origin, frames)
  let scale_x = if x_peak > 0.0 { x_peak } else { 1.0 }
  let scale_y = if y_peak > 0.0 { y_peak } else { 1.0 }
  let peak = x_peak.max(y_peak)
  let joint_scale = if peak > 0.0 { peak } else { 1.0 }
  let joint_x = x_peak / joint_scale
  let joint_y = y_peak / joint_scale
  let mut cross = 0.0
  let mut x_power = 0.0
  let mut y_power = 0.0
  let mut raw_residual = 0.0
  for i in 0..<frames {
    let a = x[x_origin + i] / scale_x
    let b = y[y_origin + i] / scale_y
    cross += a * b
    x_power += a * a
    y_power += b * b
    let error = joint_x * a - joint_y * b
    raw_residual += error * error
  }
  {
    cross,
    x_power,
    y_power,
    x_peak,
    y_peak,
    raw_residual: if y_peak == 0.0 {
      0.0
    } else if joint_y < 1.0e-150 {
      // The unscaled ratio is not representable reliably at this contrast.
      -1.0
    } else {
      (raw_residual / y_power).sqrt() / joint_y
    },
  }
}

///|
fn compare_channel(
  x : Array[Double],
  y : Array[Double],
  frames : Int32,
  window : ComparisonWindow,
) -> ResponseDifference {
  let x_peak = comparison_peak(x, window.reference_start, frames)
  let mut offset = 0
  let mut best = comparison_energy(
    x,
    y,
    window.reference_start,
    window.observed_start,
    frames,
    x_peak,
  )
  let mut score = if best.y_power > 0.0 {
    best.cross.abs() / best.y_power.sqrt()
  } else {
    -1.0
  }
  let mut lag_trials = 1
  if x_peak > 0.0 {
    for lag in window.minimum_lag..<(window.maximum_lag + 1) {
      if lag == 0 {
        continue
      }
      lag_trials += 1
      let candidate = comparison_energy(
        x,
        y,
        window.reference_start,
        window.observed_start + lag,
        frames,
        x_peak,
      )
      if candidate.y_power == 0.0 {
        continue
      }
      let candidate_score = candidate.cross.abs() / candidate.y_power.sqrt()
      let tolerance = 1.0e-12 * candidate_score.max(score).max(1.0)
      let tie = (candidate_score - score).abs() <= tolerance
      if candidate_score > score + tolerance ||
        (
          tie &&
          (
            lag.abs() < offset.abs() ||
            (lag.abs() == offset.abs() && lag < offset)
          )
        ) {
        score = candidate_score
        best = candidate
        offset = lag
      }
    }
  }
  let valid = best.x_power > 0.0 && best.y_power > 0.0
  let relative_energy_db = if valid {
    Some(
      2.0 * decay_energy_db(best.y_peak, best.x_peak) +
      decay_energy_db(best.y_power, best.x_power),
    )
  } else {
    None
  }
  let rho = if valid {
    (best.cross / (best.x_power * best.y_power).sqrt()).max(-1.0).min(1.0)
  } else {
    0.0
  }
  let ratio = if valid {
    best.cross / best.x_power * (best.y_peak / best.x_peak)
  } else {
    0.0
  }
  {
    status: if valid {
      "compared"
    } else if best.x_power == 0.0 && best.y_power == 0.0 {
      "both_silent"
    } else if best.x_power == 0.0 {
      "reference_silent"
    } else {
      "observed_silent"
    },
    reference_start: window.reference_start,
    requested_observed_start: window.observed_start,
    observed_start: window.observed_start + offset,
    observed_lag_frames: offset,
    lag_trials,
    signed_correlation: if valid {
      Some(rho)
    } else {
      None
    },
    reference_to_observed_gain: if valid &&
      ratio >= -1.0e300 &&
      ratio <= 1.0e300 {
      Some(ratio)
    } else {
      None
    },
    observed_energy_delta_db: relative_energy_db,
    raw_error_ratio: if best.y_power > 0.0 && best.raw_residual >= 0.0 {
      Some(best.raw_residual)
    } else {
      None
    },
    adjusted_error_ratio: if valid {
      Some((1.0 - rho * rho).max(0.0).sqrt())
    } else {
      None
    },
  }
}

///|
fn checked_starts(starts : Array[Int32], count : Int32, frames : Int32) -> Bool {
  starts.is_empty() ||
  (
    starts.length() == count &&
    starts.all(frame => frame >= 0 && frame < frames)
  )
}

///|
/// Compare corresponding microphones over a common fixed-length window.
/// No alignment is applied by default. A nonzero lag search is opt-in and
/// requires an explicit window to keep every trial's length identical.
pub fn compare_responses(
  reference : Array[Array[Double]],
  observed : Array[Array[Double]],
  sample_rate : Int32,
  frames~ : Int32? = None,
  reference_starts~ : Array[Int32] = [],
  observed_starts~ : Array[Int32] = [],
  lag_radius~ : Int32 = 0,
) -> Result[ResponseComparison, String] {
  let reference_frames = match
    checked_audio_frames(reference, sample_rate, 262144, 2000000, 1.0e20) {
    Err(reason) => return Err("reference: " + reason)
    Ok(value) => value
  }
  let observed_frames = match
    checked_audio_frames(observed, sample_rate, 262144, 2000000, 1.0e20) {
    Err(reason) => return Err("observed: " + reason)
    Ok(value) => value
  }
  let count = reference.length()
  if count != observed.length() ||
    !checked_starts(reference_starts, count, reference_frames) ||
    !checked_starts(observed_starts, count, observed_frames) {
    return Err("comparison requires matching channels and valid starts")
  }
  if lag_radius < 0 || lag_radius > 2048 || (lag_radius > 0 && frames is None) {
    return Err(
      "lag radius must be 0..2048 with an explicit window for alignment",
    )
  }
  let start_ref = if reference_starts.is_empty() {
    Array::make(count, 0)
  } else {
    reference_starts
  }
  let start_obs = if observed_starts.is_empty() {
    Array::make(count, 0)
  } else {
    observed_starts
  }
  let mut available = reference_frames.min(observed_frames)
  for i in 0..<count {
    available = available
      .min(reference_frames - start_ref[i])
      .min(observed_frames - start_obs[i])
  }
  let compared_frames = frames.unwrap_or(available)
  if compared_frames <= 0 || compared_frames > available {
    return Err("comparison window exceeds at least one recording")
  }
  let windows : Array[ComparisonWindow] = []
  let mut work = 0L
  for i in 0..<count {
    let minimum_lag = (-lag_radius).max(-start_obs[i])
    let maximum_lag = lag_radius.min(
      observed_frames - start_obs[i] - compared_frames,
    )
    work += (maximum_lag - minimum_lag + 1).to_int64() *
      compared_frames.to_int64()
    if work > 4000000L {
      return Err("comparison budget exceeded: 4000000 sample pairs")
    }
    windows.push({
      reference_start: start_ref[i],
      observed_start: start_obs[i],
      minimum_lag,
      maximum_lag,
    })
  }
  Ok({
    sample_rate,
    reference_frames,
    observed_frames,
    compared_frames,
    channels: Array::makei(count, fn(i) {
      compare_channel(reference[i], observed[i], compared_frames, windows[i])
    }),
  })
}
