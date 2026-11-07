///|
/// Parsed mono source. No hidden downmix, sample-rate conversion or normalization.
pub struct DryAudio {
  samples : Array[Double]
  sample_rate : Int32
}

///|
/// Bounds-check chunk framing in a wider integer before invoking the codec.
/// Metadata is discarded, not recursively interpreted. Only fmt/data are needed.
fn audio_chunks(bytes : Bytes) -> Result[Bytes, String] {
  if bytes.length() < 12 {
    return Err("WAV header is truncated")
  }
  fn is_tag(bytes : Bytes, offset : Int32, tag : String) -> Bool {
    let mut i = offset
    for c in tag.iter() {
      if bytes[i].to_int() != c.to_int() {
        return false
      }
      i = i + 1
    }
    true
  }
  fn u32(bytes : Bytes, offset : Int32) -> Int64 {
    let mut value = 0L
    for i = 0; i < 4; i = i + 1 {
      value = value | (bytes[offset + i].to_int().to_int64() << (8 * i))
    }
    value
  }
  if !is_tag(bytes, 0, "RIFF") || !is_tag(bytes, 8, "WAVE") {
    return Err("source must be RIFF/WAVE")
  }
  if u32(bytes, 4) != (bytes.length() - 8).to_int64() {
    return Err("RIFF size does not match input length")
  }
  let kept : Array[Byte] = [82, 73, 70, 70, 0, 0, 0, 0, 87, 65, 86, 69].map(fn(
    v,
  ) {
    v.to_byte()
  })
  let mut offset = 12
  let mut has_format = false
  let mut has_data = false
  while offset < bytes.length() {
    if bytes.length() - offset < 8 {
      return Err("truncated RIFF chunk header")
    }
    let size64 = u32(bytes, offset + 4)
    if size64 > (bytes.length() - offset - 8).to_int64() {
      return Err("RIFF chunk exceeds input bounds")
    }
    let size = size64.to_int()
    let end = offset + 8 + size
    let padding = size % 2
    if padding > bytes.length() - end {
      return Err("missing RIFF chunk padding")
    }
    let is_format = is_tag(bytes, offset, "fmt ")
    let is_data = is_tag(bytes, offset, "data")
    if is_format {
      if has_format || size < 16 || size > 64 {
        return Err("invalid or duplicate format chunk")
      }
      has_format = true
    }
    if is_data {
      if has_data {
        return Err("duplicate data chunk")
      }
      has_data = true
    }
    if is_format || is_data {
      for i = offset; i < end + padding; i = i + 1 {
        kept.push(bytes[i])
      }
    }
    offset = end + padding
  }
  if !has_format || !has_data {
    return Err("WAV needs format and data chunks")
  }
  for i = 0; i < 4; i = i + 1 {
    kept[4 + i] = (((kept.length() - 8) >> (8 * i)) & 255).to_byte()
  }
  Ok(Bytes::from_array(kept))
}

///|
/// Reuses MoonWavKit for RIFF/PCM decoding; rejects nonfinite float samples before
/// the upstream decoder can replace them with zero.
pub fn read_mono(bytes : Bytes) -> Result[DryAudio, String] {
  if bytes.length() > 4194304 {
    return Err("source WAV byte limit: 4194304")
  }
  let clean = match audio_chunks(bytes) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let raw = Array::makei(clean.length(), fn(i) { clean[i].to_int() })
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
  // Allocate the final byte buffer once. A growable Array[Byte] for every
  // audio byte is much larger on JS and would then be copied to Bytes again.
  Ok(
    Bytes::makei(58 + data_size, fn(i) {
      if i < 58 {
        out[i]
      } else {
        let offset = i - 58
        let sample = offset / 4
        let channel = sample % channels.length()
        let frame = sample / channels.length()
        let bits = Float::from_double(channels[channel][frame]).reinterpret_as_int()
        ((bits >> (8 * (offset % 4))) & 255).to_byte()
      }
    }),
  )
}
