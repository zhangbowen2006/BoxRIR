///|
/// Six analysis/material bands. End bands are shelves down to DC/up to Nyquist.
pub fn octave_centers() -> Array[Double] {
  [125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0]
}

///|
fn spectral_width(
  sample_rate : Int32,
  requested : Int32,
) -> Result[Int32, String] {
  if sample_rate < 16000 || sample_rate > 96000 {
    return Err("spectral sample rate must be 16000..96000 Hz")
  }
  let minimum = (256 * sample_rate + 15999) / 16000
  let half = if requested == 0 { minimum } else { requested }
  if half < minimum || half > 4096 {
    return Err(
      "spectral FIR half-width must resolve the lowest bands: ceil(256*fs/16000)..4096",
    )
  }
  Ok(half)
}

///|
/// Complementary linear-phase FIR bank, using the existing MoonSpectrum
/// normalized Hamming lowpasses. Sum of filters is a unit delayed impulse.
/// This is a finite engineering filter bank, not IEC 61260 certification.
pub fn octave_filters(
  sample_rate : Int32,
  half_width~ : Int32 = 0,
) -> Result[Array[Array[Double]], String] {
  let half_width = match spectral_width(sample_rate, half_width) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let centers = octave_centers()
  let length = 2 * half_width + 1
  let low : Array[Array[Double]] = []
  for i in 0..<5 {
    let taps = @spectrum.lowpass_taps(
      length~,
      cutoff_hz=(centers[i] * centers[i + 1]).sqrt(),
      sample_rate=sample_rate.to_double(),
    ) catch {
      _ => return Err("spectral lowpass design failed")
    }
    low.push(taps)
  }
  Ok(
    Array::makei(6, fn(band) {
      Array::makei(length, fn(i) {
        let upper = if band == 5 {
          if i == half_width {
            1.0
          } else {
            0.0
          }
        } else {
          low[band][i]
        }
        let lower = if band == 0 { 0.0 } else { low[band - 1][i] }
        upper - lower
      })
    }),
  )
}

///|
pub struct SpectralPath {
  path : Path
  band_gains : Array[Double]
}

///|
pub struct SpectralRir {
  audio : Audio
  paths : Array[SpectralPath]
  direct_paths : Array[Path]
  paths_truncated : Bool
  geometric_images : Int32
  contributing : Array[Int32]
  late : Array[Int32]
  zero : Array[Int32]
  band_absorption : Array[Array[Double]]
  air_db_per_m : Array[Double]
  filter_half_width : Int32
}

///|
/// Each wall owns six ENERGY absorption values. This replaces the legacy
/// scene's scalar absorption; geometry/timing/order remain the same.
/// Air loss is PRESSURE attenuation 10^(-dB_per_m * path_metres / 20).
/// Subband RIRs are formed PER PATH before complementary FIR synthesis.
pub fn spectral_rir(
  s : Scene,
  band_absorption : Array[Array[Double]],
  air_db_per_m~ : Array[Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  filter_half_width~ : Int32 = 0,
) -> Result[SpectralRir, String] {
  let filter_half_width = match
    spectral_width(s.sample_rate, filter_half_width) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let wall_count = s.absorption.length()
  if band_absorption.length() != wall_count ||
    !band_absorption.all(fn(wall) {
      wall.length() == 6 && wall.all(fn(a) { a >= 0.0 && a <= 1.0 })
    }) {
    return Err(
      "band_absorption needs one six-band energy absorption row per wall, values 0..1",
    )
  }
  if air_db_per_m.length() != 6 ||
    !air_db_per_m.all(fn(a) { a >= 0.0 && a <= 10.0 }) {
    return Err("air_db_per_m needs six finite pressure losses in 0..10 dB/m")
  }
  let filters = match
    octave_filters(s.sample_rate, half_width=filter_half_width) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let frames = s.output_frames() + 2 * filter_half_width
  let count = s.receivers.length()
  // Bound the six intermediate RIRs as well as final and convolution buffers.
  if frames > 262144 || frames * count * 6 > 1000000 {
    return Err("spectral six-band intermediate sample budget exceeded: 1000000")
  }
  let bands = Array::makei(6, fn(_) {
    Array::makei(count, fn(_) { Array::make(s.output_frames(), 0.0) })
  })
  let contributing = Array::make(count, 0)
  let late = Array::make(count, 0)
  let zero = Array::make(count, 0)
  let paths : Array[SpectralPath] = []
  let direct_paths : Array[Path] = []
  let mut truncated = false
  let traced = trace(s)
  for original in traced {
    let geometric = 1.0 / (4.0 * PI * original.distance)
    let gains = Array::makei(6, fn(band) {
      let mut gain = geometric *
        @math.exp(
          -2.302585092994046 * air_db_per_m[band] * original.distance / 20.0,
        )
      for wall in 0..<wall_count {
        gain = gain *
          power(
            (1.0 - band_absorption[wall][band]).sqrt(),
            original.bounces[wall],
          )
      }
      gain
    })
    let path : Path = { ..original, reflection: 1.0, gain: geometric, }
    if original.order == 0 {
      direct_paths.push(path)
    }
    if paths.length() < 10000 {
      paths.push({ path, band_gains: gains, })
    } else {
      truncated = true
    }
    let r = original.receiver
    if original.delay_samples >= s.frames.to_double() {
      late[r] = late[r] + 1
      continue
    }
    if gains.all(fn(g) { g == 0.0 }) {
      zero[r] = zero[r] + 1
      continue
    }
    let base = @math.floor(original.delay_samples).to_int()
    let taps = delay_taps(
      original.delay_samples - base.to_double(),
      s.half_width,
    )
    for band in 0..<6 {
      if gains[band] == 0.0 {
        continue
      }
      for i in 0..<taps.length() {
        bands[band][r][base + i] = bands[band][r][base + i] +
          gains[band] * taps[i]
      }
    }
    contributing[r] = contributing[r] + 1
  }
  let channels = Array::makei(count, fn(_) { Array::make(frames, 0.0) })
  for band in 0..<6 {
    for receiver in 0..<count {
      let filtered = @spectrum.fft_convolve(
        bands[band][receiver][:],
        filters[band][:],
      ) catch {
        _ => return Err("spectral synthesis convolution failed")
      }
      for i in 0..<frames {
        channels[receiver][i] = channels[receiver][i] + filtered[i]
      }
    }
  }
  Ok({
    audio: {
      samples: channels,
      sample_rate: s.sample_rate,
      latency_samples: s.half_width + filter_half_width,
    },
    paths,
    direct_paths,
    paths_truncated: truncated,
    geometric_images: s.candidate_image_count(),
    contributing,
    late,
    zero,
    band_absorption: band_absorption.map(fn(w) { w.copy() }),
    air_db_per_m: air_db_per_m.copy(),
    filter_half_width,
  })
}
