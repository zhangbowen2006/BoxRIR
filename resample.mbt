///|
pub struct ResampleResult {
  audio : Audio
  input_rate : Int32
  input_frames : Int32
  tap_radius : Int32
  cached_phases : Int32
}

///|
fn rate_gcd(a : Int32, b : Int32) -> Int32 {
  let mut larger = a
  let mut smaller = b
  while smaller > 0 {
    let remainder = larger % smaller
    larger = smaller
    smaller = remainder
  }
  larger
}

///|
fn conversion_taps(
  fraction : Double,
  radius : Int32,
  cutoff : Double,
) -> Array[Double] {
  let taps = Array::makei(2 * radius + 1, fn(i) {
    let distance = (i - radius).to_double() - fraction
    let progress = distance / radius.to_double()
    if progress.abs() >= 1.0 {
      0.0
    } else {
      let theta = 2.0 * PI * cutoff * distance
      let sinc = if theta.abs() < 1.0e-12 {
        1.0
      } else {
        @math.sin(theta) / theta
      }
      let window = 0.42 +
        0.5 * @math.cos(PI * progress) +
        0.08 * @math.cos(2.0 * PI * progress)
      2.0 * cutoff * sinc * window
    }
  })
  let sum = taps.fold(init=0.0, fn(a, b) { a + b })
  for i in 0..<taps.length() {
    taps[i] /= sum
  }
  taps
}

///|
/// Convert discrete samples at zero additional timeline offset. The Blackman
/// sinc kernel limits the passband to 0.46 times the lower rate (cycles/s).
/// The first and last values are extended at the respective edges.
///
/// Intended for dry or recorded audio before simulation/analysis. The caller
/// explicitly chooses the new rate; render/mix/estimate still reject mismatches.
pub fn resample_audio(
  channels : Array[Array[Double]],
  input_rate : Int32,
  output_rate : Int32,
) -> Result[ResampleResult, String] {
  let input_frames = match
    checked_audio_frames(channels, input_rate, 262144, 2000000, 1.0e20) {
    Err(reason) => return Err(reason)
    Ok(frames) => frames
  }
  if !valid_audio_rate(output_rate) {
    return Err("resampling output rate must be 8000..96000")
  }
  if input_rate == output_rate {
    return Ok({
      audio: {
        samples: channels.map(channel => channel.copy()),
        sample_rate: output_rate,
        latency_samples: 0,
      },
      input_rate,
      input_frames,
      tap_radius: 0,
      cached_phases: 0,
    })
  }
  let count = channels.length()
  let output_frames = ((
    input_frames.to_int64() * output_rate.to_int64() +
    input_rate.to_int64() -
    1L
  ) /
  input_rate.to_int64()).to_int()
  if output_frames > 262144 || output_frames * count > 2000000 {
    return Err("resampled audio exceeds the frame or channel budget")
  }
  let low_ratio = (output_rate.to_double() / input_rate.to_double()).min(1.0)
  let cutoff = 0.46 * low_ratio
  let radius = @math.ceil(32.0 / low_ratio).to_int()
  let width = 2 * radius + 1
  if output_frames.to_int64() * count.to_int64() * width.to_int64() > 32000000L {
    return Err("resampling work budget exceeded: 32000000 tap applications")
  }
  let gcd = rate_gcd(input_rate, output_rate)
  let phase_count = output_rate / gcd
  let advance = input_rate / gcd
  let cache = if phase_count * width <= 65536 {
    Array::makei(phase_count, fn(phase) {
      conversion_taps(
        phase.to_double() / phase_count.to_double(),
        radius,
        cutoff,
      )
    })
  } else {
    []
  }
  let output = Array::makei(count, _ => Array::make(output_frames, 0.0))
  let mut center = 0
  let mut phase = 0
  for frame in 0..<output_frames {
    let taps = if cache.is_empty() {
      conversion_taps(
        phase.to_double() / phase_count.to_double(),
        radius,
        cutoff,
      )
    } else {
      cache[phase]
    }
    for channel in 0..<count {
      let source = channels[channel]
      let mut value = 0.0
      for i, tap in taps {
        let index = (center + i - radius).max(0).min(input_frames - 1)
        value += source[index] * tap
      }
      if !(value >= -1.0e20 && value <= 1.0e20) {
        return Err("resampled sample exceeds the output amplitude budget")
      }
      output[channel][frame] = value
    }
    let next = phase + advance
    center += next / phase_count
    phase = next % phase_count
  }
  Ok({
    audio: { samples: output, sample_rate: output_rate, latency_samples: 0, },
    input_rate,
    input_frames,
    tap_radius: radius,
    cached_phases: cache.length(),
  })
}
