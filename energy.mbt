///|
pub(all) struct DecayPoint {
  frame_from_onset : Int32
  energy_db : Double
}

///|
/// A null time in the JSON API is accompanied by the reason for withholding it.
pub(all) struct DecayFit {
  status : String
  seconds_for_60db : Double?
  slope_db_per_second : Double?
  r_squared : Double?
  samples_used : Int32
  start_frame : Int32?
  end_frame : Int32?
}

///|
pub(all) struct ChannelDecay {
  onset_frame : Int32?
  window_end_exclusive : Int32
  peak : Double
  power_sum : Double
  d50 : Double?
  c50_db : Double?
  c80_db : Double?
  center_time_ms : Double?
  edt : DecayFit
  t20 : DecayFit
  t30 : DecayFit
  curve : Array[DecayPoint]
}

///|
pub(all) struct DecayAnalysis {
  sample_rate : Int32
  frames : Int32
  onset_mode : String
  channels : Array[ChannelDecay]
}

///|
// Use one pass for validation; bound frame arithmetic before allocation.
fn checked_audio_frames(
  channels : Array[Array[Double]],
  sample_rate : Int32,
  max_frames : Int32,
  max_samples : Int32,
  max_amplitude : Double,
) -> Result[Int32, String] {
  if !valid_audio_rate(sample_rate) ||
    channels.is_empty() ||
    channels.length() > 8 {
    return Err("audio requires 1..8 channels and a sample rate of 8000..96000")
  }
  let frames = channels[0].length()
  if frames == 0 ||
    frames > max_frames ||
    frames.to_int64() * channels.length().to_int64() > max_samples.to_int64() {
    return Err("audio frame or aggregate sample budget exceeded")
  }
  for channel in channels {
    if channel.length() != frames {
      return Err("audio channel lengths differ")
    }
    if !channel.all(value => value >= -max_amplitude && value <= max_amplitude) {
      return Err("audio contains nonfinite or out-of-range samples")
    }
  }
  Ok(frames)
}

///|
fn decline_decay_fit(status : String) -> DecayFit {
  {
    status,
    seconds_for_60db: None,
    slope_db_per_second: None,
    r_squared: None,
    samples_used: 0,
    start_frame: None,
    end_frame: None,
  }
}

///|
/// Integrate squared samples in reverse after scaling to keep the range
/// finite even for very quiet inputs. Curve ref is the energy at onset.
fn reverse_energy(
  samples : Array[Double],
  onset : Int32,
  end : Int32,
  scale : Double,
) -> Array[Double] {
  let integrated = Array::make(end - onset, 0.0)
  let mut sum = 0.0
  let mut correction = 0.0
  for i = end - 1; i >= onset; i = i - 1 {
    let normalized = samples[i] / scale
    let term = normalized * normalized - correction
    let total = sum + term
    correction = total - sum - term
    sum = total
    // The exact series is monotonic. Suppress at most a round-off reversal.
    integrated[i - onset] = if i + 1 < end {
      sum.max(integrated[i + 1 - onset])
    } else {
      sum
    }
  }
  integrated
}

///|
fn decay_energy_db(value : Double, total : Double) -> Double {
  10.0 /
  // Subtraction of logs avoids an underflowing ratio for extremely small tails.
  @math.ln(10.0) *
  (@math.ln(value) - @math.ln(total))
}

///|
fn decay_fit(
  integrated : Array[Double],
  rate : Int32,
  start_db : Double,
  stop_db : Double,
) -> DecayFit {
  let total = integrated[0]
  let mut count = 0
  let mut first = -1
  let mut last = -1
  let mut covers_stop = false
  let mut mean_x = 0.0
  let mut mean_y = 0.0
  let mut variance_x = 0.0
  let mut variance_y = 0.0
  let mut covariance = 0.0
  for i, energy in integrated {
    if energy <= 0.0 {
      break
    }
    let db = decay_energy_db(energy, total)
    if db > start_db {
      continue
    }
    if db <= stop_db {
      covers_stop = true
    }
    if db < stop_db {
      break
    }
    if first < 0 {
      first = i
    }
    last = i
    let x = i.to_double() / rate.to_double()
    count += 1
    let dx = x - mean_x
    let dy = db - mean_y
    mean_x += dx / count.to_double()
    mean_y += dy / count.to_double()
    variance_x += dx * (x - mean_x)
    variance_y += dy * (db - mean_y)
    covariance += dx * (db - mean_y)
  }
  if !covers_stop {
    return decline_decay_fit("insufficient_decay_range")
  }
  let window_frames = last - first
  if count < 8 ||
    window_frames.to_double() < 0.005 * rate.to_double() ||
    variance_x <= 0.0 ||
    variance_y <= 0.0 {
    return {
      ..decline_decay_fit("insufficient_fit_samples"),
      samples_used: count,
    }
  }
  let slope = covariance / variance_x
  let fit = (covariance / variance_x * (covariance / variance_y))
    .max(0.0)
    .min(1.0)
  let status = if slope >= 0.0 || fit < 0.9 { "weak_fit" } else { "estimated" }
  {
    status,
    seconds_for_60db: if status == "estimated" {
      Some(-60.0 / slope)
    } else {
      None
    },
    slope_db_per_second: Some(slope),
    r_squared: Some(fit),
    samples_used: count,
    start_frame: Some(first),
    end_frame: Some(last),
  }
}

///|
fn decay_preview(
  integrated : Array[Double],
  max_points : Int32,
) -> Array[DecayPoint] {
  let curve : Array[DecayPoint] = []
  if max_points == 0 {
    return curve
  }
  let mut last_positive = integrated.length() - 1
  while integrated[last_positive] == 0.0 {
    last_positive -= 1
  }
  let count = max_points.min(last_positive + 1)
  for i in 0..<count {
    let index = if count == 1 { 0 } else { i * last_positive / (count - 1) }
    curve.push({
      frame_from_onset: index,
      energy_db: decay_energy_db(integrated[index], integrated[0]),
    })
  }
  curve
}

///|
fn late_start(rate : Int32, ms : Int32) -> Int32 {
  (rate * ms + 999) / 1000
}

///|
fn clarity(early : Double, late : Double) -> Double? {
  if early <= 0.0 || late <= 0.0 {
    None
  } else {
    Some(decay_energy_db(early, late))
  }
}

///|
fn channel_decay(
  samples : Array[Double],
  rate : Int32,
  specified_onset : Int32?,
  window_end : Int32,
  max_points : Int32,
) -> ChannelDecay {
  let mut peak = 0.0
  for i in specified_onset.unwrap_or(0)..<window_end {
    peak = peak.max(samples[i].abs())
  }
  if peak == 0.0 {
    let missing = decline_decay_fit("no_energy")
    return {
      onset_frame: specified_onset,
      window_end_exclusive: window_end,
      peak: 0.0,
      power_sum: 0.0,
      d50: None,
      c50_db: None,
      c80_db: None,
      center_time_ms: None,
      edt: missing,
      t20: missing,
      t30: missing,
      curve: [],
    }
  }
  let onset = match specified_onset {
    Some(frame) => frame
    None => {
      let mut first = 0
      while samples[first].abs() / peak < 0.01 {
        first += 1
      }
      first
    }
  }
  let integrated = reverse_energy(samples, onset, window_end, peak)
  let total = integrated[0]
  let threshold_50 = late_start(rate, 50)
  let threshold_80 = late_start(rate, 80)
  let mut early_50 = 0.0
  let mut early_80 = 0.0
  let mut time_weighted = 0.0
  for i in onset..<window_end {
    let scaled = samples[i] / peak
    let energy = scaled * scaled
    let relative = i - onset
    if relative < threshold_50 {
      early_50 += energy
    }
    if relative < threshold_80 {
      early_80 += energy
    }
    time_weighted += relative.to_double() * energy
  }
  let covers_50 = integrated.length() > threshold_50
  let covers_80 = integrated.length() > threshold_80
  {
    onset_frame: Some(onset),
    window_end_exclusive: window_end,
    peak,
    power_sum: total * peak * peak,
    d50: if covers_50 {
      Some((early_50 / total).min(1.0))
    } else {
      None
    },
    c50_db: if covers_50 {
      clarity(early_50, integrated[threshold_50])
    } else {
      None
    },
    c80_db: if covers_80 {
      clarity(early_80, integrated[threshold_80])
    } else {
      None
    },
    center_time_ms: Some(time_weighted * 1000.0 / (total * rate.to_double())),
    edt: decay_fit(integrated, rate, 0.0, -10.0),
    t20: decay_fit(integrated, rate, -5.0, -25.0),
    t30: decay_fit(integrated, rate, -5.0, -35.0),
    curve: decay_preview(integrated, max_points),
  }
}

///|
/// Finite-window, wideband Schroeder analysis. By default the onset is the
/// first sample within -40 dB of each channel's peak. An explicit per-channel
/// onset is appropriate for known simulation arrivals or aligned measurements.
pub fn analyze_decay(
  channels : Array[Array[Double]],
  sample_rate : Int32,
  onset_frames~ : Array[Int32] = [],
  end_exclusive~ : Int32? = None,
  curve_points~ : Int32 = 161,
) -> Result[DecayAnalysis, String] {
  let frames = match
    checked_audio_frames(channels, sample_rate, 262144, 2000000, 1.0e20) {
    Err(reason) => return Err(reason)
    Ok(count) => count
  }
  let end = end_exclusive.unwrap_or(frames)
  if end <= 0 || end > frames || curve_points < 0 || curve_points > 256 {
    return Err("invalid analysis end frame or curve point budget")
  }
  let automatic = onset_frames.is_empty()
  if !automatic &&
    (
      onset_frames.length() != channels.length() ||
      !onset_frames.all(frame => frame >= 0 && frame < end)
    ) {
    return Err("explicit onsets must contain one in-window frame per channel")
  }
  Ok({
    sample_rate,
    frames,
    onset_mode: if automatic {
      "threshold_minus_40db"
    } else {
      "explicit"
    },
    channels: Array::makei(channels.length(), fn(channel) {
      let onset = if automatic { None } else { Some(onset_frames[channel]) }
      channel_decay(channels[channel], sample_rate, onset, end, curve_points)
    }),
  })
}
