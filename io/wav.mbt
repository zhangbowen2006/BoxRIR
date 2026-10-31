///|
/// Parsed mono source. No hidden downmix, sample-rate conversion or normalization.
pub struct DryAudio {
  samples : Array[Double]
  sample_rate : Int32
}

///|
/// Reuses MoonWavKit for RIFF/PCM decoding; rejects nonfinite float samples before
/// the upstream decoder can replace them with zero.
pub fn read_mono(bytes : Bytes) -> Result[DryAudio, String] {
  if bytes.length() > 4194304 {
    return Err("source WAV byte limit: 4194304")
  }
  let raw = Array::makei(bytes.length(), fn(i) { bytes[i].to_int() })
  let parsed = @wav.parse_wav(raw)
  if !parsed.ok {
    return Err(parsed.error.message)
  }
  let w = parsed.wav
  if w.format.channels != 1 {
    return Err("source WAV must be mono")
  }
  if w.format.sample_rate < 8000 || w.format.sample_rate > 96000 {
    return Err("source WAV sample rate must be 8000..96000")
  }
  if w.format.block_align <= 0 || w.data_size / w.format.block_align > 262144 {
    return Err("source WAV frame limit: 262144")
  }
  if w.format.is_float() {
    if w.format.bits_per_sample != 32 {
      return Err("only IEEE Float32 WAV is supported")
    }
    if w.data_offset < 0 ||
      w.data_size < 0 ||
      w.data_offset + w.data_size > raw.length() ||
      w.data_size % 4 != 0 {
      return Err("invalid float data bounds")
    }
    for i = w.data_offset; i < w.data_offset + w.data_size; i = i + 4 {
      let bits = raw[i] |
        (raw[i + 1] << 8) |
        (raw[i + 2] << 16) |
        (raw[i + 3] << 24)
      if (bits & 0x7f800000) == 0x7f800000 {
        return Err("source WAV contains NaN or infinity")
      }
    }
  }
  let decoded = @wav.decode_pcm(
    raw,
    w,
    options=@wav.DecodeOptions::new(normalize=true, clamp=false),
  )
  if !decoded.ok {
    return Err(decoded.error.message)
  }
  let samples = decoded.float_buffer.samples
  if samples.is_empty() {
    return Err("source WAV has no frames")
  }
  for v in samples {
    if !(v >= -1.0e6 && v <= 1.0e6) {
      return Err("source sample magnitude exceeds 1000000")
    }
  }
  Ok({ samples: samples.copy(), sample_rate: w.format.sample_rate, })
}

///|
fn le(out : Array[Byte], value : Int32, width : Int32) -> Unit {
  for i = 0; i < width; i = i + 1 {
    out.push(((value >> (8 * i)) & 255).to_byte())
  }
}

///|
fn ascii(out : Array[Byte], text : String) -> Unit {
  for c in text.iter() {
    out.push(c.to_int().to_byte())
  }
}

///|
/// Narrow IEEE Float32 writer: fmt+fact+data. Unlike PCM16 export, amplitudes
/// outside [-1,1] are preserved. Float32 rounding is the only conversion.
pub fn write_float32(
  channels : Array[Array[Double]],
  sample_rate : Int32,
) -> Result[Bytes, String] {
  if channels.is_empty() ||
    channels.length() > 8 ||
    sample_rate < 8000 ||
    sample_rate > 96000 {
    return Err("invalid WAV channels or sample rate")
  }
  let frames = channels[0].length()
  if frames == 0 || frames > 262144 || frames * channels.length() > 2000000 {
    return Err("WAV frame budget exceeded")
  }
  for channel in channels {
    if channel.length() != frames {
      return Err("WAV channel lengths differ")
    }
    for v in channel {
      if !(v >= -1.0e20 && v <= 1.0e20) {
        return Err("WAV samples must be finite and abs <= 1e20")
      }
    }
  }
  let data_size = frames * channels.length() * 4
  let out : Array[Byte] = []
  ascii(out, "RIFF")
  le(out, 50 + data_size, 4)
  ascii(out, "WAVEfmt ")
  le(out, 18, 4)
  le(out, 3, 2)
  le(out, channels.length(), 2)
  le(out, sample_rate, 4)
  le(out, sample_rate * channels.length() * 4, 4)
  le(out, channels.length() * 4, 2)
  le(out, 32, 2)
  le(out, 0, 2)
  ascii(out, "fact")
  le(out, 4, 4)
  le(out, frames, 4)
  ascii(out, "data")
  le(out, data_size, 4)
  for frame = 0; frame < frames; frame = frame + 1 {
    for channel in channels {
      let bits = Float::from_double(channel[frame]).reinterpret_as_int()
      le(out, bits, 4)
    }
  }
  Ok(Bytes::from_array(out))
}
