///|
#export_name("describe_json")
pub fn describe_json(text : String) -> String {
  @api.describe_json(text)
}

///|
#export_name("generate_json")
pub fn generate_json(text : String, dry : Bytes) -> String {
  @api.generate_json(text, dry)
}

///|
#export_name("reference_samples_json")
pub fn reference_samples_json(text : String) -> String {
  @api.reference_samples_json(text)
}

///|
#export_name("spectral_samples_json")
pub fn spectral_samples_json(text : String) -> String {
  @api.spectral_samples_json(text)
}

///|
#export_name("render_base64_json")
pub fn render_base64_json(text : String, dry_base64 : String) -> String {
  if dry_base64.length() > 5592408 {
    return "{\"ok\":false,\"error\":\"source WAV exceeds 4 MiB\"}"
  }
  let dry = @base64.decode(dry_base64) catch {
    _ => return "{\"ok\":false,\"error\":\"invalid source WAV base64\"}"
  }
  @api.generate_base64_json(text, dry)
}

///|
fn bridge_failure(message : String) -> String {
  ({ "ok": false, "error": Json(message) } : Json).stringify()
}

///|
fn decode_wav_text(value : String, max_bytes : Int32) -> Result[Bytes, String] {
  let max_chars = 4 * ((max_bytes + 2) / 3)
  if value.length() > max_chars {
    return Err("encoded WAV exceeds byte budget")
  }
  let decoded = @base64.decode(value) catch {
    _ => return Err("invalid WAV base64")
  }
  if decoded.is_empty() || decoded.length() > max_bytes {
    return Err("WAV is empty or exceeds byte budget")
  }
  Ok(decoded)
}

///|
#export_name("mix_recordings_json")
pub fn mix_recordings_json(text : String, sources : String) -> String {
  if sources.length() > 11184840 {
    return bridge_failure("encoded track audio exceeds total byte budget")
  }
  let values = @json.parse(sources, max_nesting_depth=1) catch {
    _ => return bridge_failure("invalid track audio JSON")
  }
  guard values is Array(entries) &&
    entries.length() >= 1 &&
    entries.length() <= 4 else {
    return bridge_failure("expected 1..4 encoded track WAV files")
  }
  let tracks : Array[Bytes] = []
  let mut total = 0
  for entry in entries {
    guard entry is String(encoded) else {
      return bridge_failure("invalid encoded track WAV")
    }
    match decode_wav_text(encoded, 4194304) {
      Err(reason) => return bridge_failure(reason)
      Ok(bytes) => {
        total += bytes.length()
        if total > 8388608 {
          return bridge_failure("track WAV total exceeds 8 MiB")
        }
        tracks.push(bytes)
      }
    }
  }
  @api.mix_base64_json(text, tracks)
}

///|
#export_name("probe_json")
pub fn probe_json(text : String) -> String {
  @api.probe_base64_json(text)
}

///|
#export_name("default_probe_json")
pub fn default_probe_json(rate : Double) -> String {
  @api.default_probe_base64_json(rate)
}

///|
#export_name("analyze_response_json")
pub fn analyze_response_json(text : String, wav : String) -> String {
  match decode_wav_text(wav, 8388608) {
    Err(reason) => bridge_failure(reason)
    Ok(bytes) => @api.analyze_wav_json(text, bytes)
  }
}

///|
#export_name("estimate_response_json")
pub fn estimate_response_json(
  text : String,
  probe : String,
  recording : String,
) -> String {
  let source = match decode_wav_text(probe, 4194304) {
    Err(reason) => return bridge_failure(reason)
    Ok(bytes) => bytes
  }
  match decode_wav_text(recording, 8388608) {
    Err(reason) => bridge_failure(reason)
    Ok(bytes) => @api.estimate_wav_json(text, source, bytes)
  }
}

///|
#export_name("compare_responses_json")
pub fn compare_responses_json(
  text : String,
  reference : String,
  observed : String,
) -> String {
  let first = match decode_wav_text(reference, 8388608) {
    Err(reason) => return bridge_failure(reason)
    Ok(bytes) => bytes
  }
  match decode_wav_text(observed, 8388608) {
    Err(reason) => bridge_failure(reason)
    Ok(second) => @api.compare_wav_json(text, first, second)
  }
}

///|
#export_name("resample_audio_json")
pub fn resample_audio_json(text : String, wav : String) -> String {
  match decode_wav_text(wav, 8388608) {
    Err(reason) => bridge_failure(reason)
    Ok(value) => @api.resample_wav_json(text, value)
  }
}
