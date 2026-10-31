///|
/// Multichannel output on the same timeline; no automatic peak normalization.
pub struct Audio {
  priv samples : Array[Array[Double]]
  sample_rate : Int32
  latency_samples : Int32
}

///|
/// Uses the existing MoonSpectrum FFT. Returns the complete linear-convolution tail.
pub fn convolve(
  response : Response,
  dry : Array[Double],
) -> Result[Audio, String] {
  if dry.is_empty() || dry.length() > 262144 {
    return Err("dry signal must contain 1..262144 samples")
  }
  for v in dry {
    if !(v >= -1.0e6 && v <= 1.0e6) {
      return Err("dry samples must be finite and abs <= 1000000")
    }
  }
  let length = dry.length() + response.scene.output_frames() - 1
  if length > 262144 || length * response.samples.length() > 2000000 {
    return Err("convolution output budget exceeded")
  }
  let channels : Array[Array[Double]] = []
  for h in response.samples {
    let wet = @spectrum.fft_convolve(dry[:], h[:]) catch {
      _ => return Err("FFT convolution failed")
    }
    if wet.length() != length {
      return Err("FFT backend returned an unexpected length")
    }
    channels.push(wet)
  }
  Ok({
    samples: channels,
    sample_rate: response.scene.sample_rate,
    latency_samples: response.scene.half_width,
  })
}

///|
pub fn Audio::channel(
  self : Audio,
  index : Int32,
) -> Result[Array[Double], String] {
  if index < 0 || index >= self.samples.length() {
    Err("audio channel index out of range")
  } else {
    Ok(self.samples[index].copy())
  }
}

///|
pub fn Audio::channel_count(self : Audio) -> Int32 {
  self.samples.length()
}

///|
pub fn Audio::frames(self : Audio) -> Int32 {
  self.samples[0].length()
}
