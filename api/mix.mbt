///|
priv struct MixTrackInput {
  id : String
  source : Array[Double]
  start_frame : Double
  gain : Double
} derive(FromJson)

///|
priv struct MixInput {
  scene : Json
  tracks : Array[MixTrackInput]
  spectral : Bool
}

///|
fn mix_id_valid(id : String) -> Bool {
  if id.is_empty() || id.length() > 64 {
    return false
  }
  let mut first = true
  for c in id.iter() {
    let alnum = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9')
    if !alnum && (first || (c != '-' && c != '_')) {
      return false
    }
    first = false
  }
  true
}

///|
fn read_mix(text : String) -> Result[MixInput, String] {
  if text.length() > 65536 {
    return Err("recording JSON limit: 65536 characters")
  }
  let raw = @json.parse(
    text,
    reject_duplicate_keys=true,
    max_nesting_depth=10,
    preserve_number_repr=true,
  ) catch {
    _ => return Err("invalid recording JSON")
  }
  guard raw is Object(fields) else { return Err("recording must be an object") }
  for key, _ in fields {
    if !["version", "scene", "tracks"].contains(key) {
      return Err("unknown recording field: " + key)
    }
  }
  if !(fields.get("version") is Some(Number(v, repr=Some(s))) &&
    v == 1.0 &&
    s == "1") {
    return Err("recording version must be integer 1")
  }
  guard fields.get("scene") is Some(Object(scene_fields)) else {
    return Err("recording needs a shared scene object")
  }
  if scene_fields.contains("source") {
    return Err("recording source belongs in each track, not the shared scene")
  }
  let spectral = scene_fields.get("model") == Some(Json("octave_bands"))
  if !spectral && scene_fields.contains("model") {
    return Err(
      "recording supports ordinary or octave_bands scenes; omit model for ordinary scenes",
    )
  }
  // Check the input spelling before any stringify/parse round trip.
  for
    key in [
      "sample_rate", "max_order", "duration_ms", "half_width", "band_filter_half_width",
    ] {
    if scene_fields.get(key) is Some(value) && !integer_literal(value) {
      return Err("integer literal required: " + key)
    }
  }
  guard fields.get("tracks") is Some(Array(entries)) else {
    return Err("recording tracks must be an array")
  }
  if entries.is_empty() || entries.length() > 4 {
    return Err("recording requires 1..4 tracks")
  }
  let tracks : Array[MixTrackInput] = []
  for entry in entries {
    guard entry is Object(track) else {
      return Err("recording track must be an object")
    }
    for key, _ in track {
      if !["id", "source", "start_frame", "gain"].contains(key) {
        return Err("unknown recording track field: " + key)
      }
    }
    if !(track.get("start_frame") is Some(value) && integer_literal(value)) {
      return Err("integer literal required: start_frame")
    }
    let input : MixTrackInput = @json.from_json(entry) catch {
      _ => return Err("invalid recording track schema")
    }
    if !mix_id_valid(input.id) || tracks.any(fn(t) { t.id == input.id }) {
      return Err(
        "recording track IDs must be unique, 1..64 ASCII letters, digits, hyphens or underscores, beginning with a letter or digit",
      )
    }
    if !bounded_int(input.start_frame, 0, 262143) ||
      !(input.gain >= -100.0 && input.gain <= 100.0) {
      return Err(
        "recording track " +
        input.id +
        " needs start_frame in 0..262143 and gain in -100..100",
      )
    }
    tracks.push(input)
  }
  Ok({ scene: Json(scene_fields), tracks, spectral, })
}

///|
fn read_mix_scene(
  input : MixInput,
  track : MixTrackInput,
) -> Result[(@core.Scene, @core.RecordingOctaves?), String] {
  let fields : Map[String, Json] = Map([])
  if input.scene is Object(shared) {
    for key, value in shared {
      fields.set(key, value)
    }
  }
  fields.set("source", Json(track.source))
  let text = Json(fields).stringify()
  if input.spectral {
    match read_spectral(text) {
      Err(e) => Err(e)
      Ok(s) =>
        Ok(
          (
            s.scene,
            Some({
              band_absorption: s.materials,
              air_db_per_m: s.air,
              filter_half_width: s.filter_half_width,
            }),
          ),
        )
    }
  } else {
    parse_scene(text).map(fn(s) { (s, None) })
  }
}

///|
fn mix_track_json(
  input : MixTrackInput,
  track : @core.RecordingTrackReport,
) -> Json {
  {
    "id": Json(input.id),
    "source": Json(input.source),
    "start_frame": Json(track.start_frame),
    "gain": Json(track.gain),
    "dry_frames": Json(track.dry_frames),
    "rir_frames": Json(track.rir_frames),
    "wet_frames": Json(track.wet_frames),
    "end_frame": Json(track.end_frame),
    "latency_samples": Json(track.latency_samples),
    "contributing_paths": Json(track.contributing_paths),
    "omitted_late_paths": Json(track.omitted_late_paths),
    "zero_gain_paths": Json(track.zero_gain_paths),
  }
}

///|
/// The track order binds the dry inputs. All supplied files must be mono WAV
/// with the same rate as the shared scene. `wet_wav` is a Float32 WAV base64.
pub fn mix_base64_json(text : String, dry_wavs : Array[Bytes]) -> String {
  let input = match read_mix(text) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  if dry_wavs.length() != input.tracks.length() {
    return error("recording requires one WAV per track in track order")
  }
  let mut byte_count = 0
  for wav in dry_wavs {
    if wav.is_empty() || wav.length() > 4194304 {
      return error("each recording WAV needs 1..4194304 bytes")
    }
    byte_count = byte_count + wav.length()
    if byte_count > 8388608 {
      return error("recording WAV byte budget: 8388608")
    }
  }
  let tracks : Array[@core.RecordingTrack] = []
  let mut octaves : @core.RecordingOctaves? = None
  for i in 0..<input.tracks.length() {
    let part = input.tracks[i]
    let prefix = "recording track " + part.id + ": "
    let (scene, profile) = match read_mix_scene(input, part) {
      Err(e) => return error(prefix + e)
      Ok(v) => v
    }
    if i == 0 {
      octaves = profile
    }
    let dry = match @audio.read_mono(dry_wavs[i]) {
      Err(e) => return error(prefix + e)
      Ok(v) => v
    }
    if dry.sample_rate != scene.rate() {
      return error(prefix + "WAV sample rate does not match the shared scene")
    }
    tracks.push({
      scene,
      dry: dry.samples,
      sample_rate: dry.sample_rate,
      start_frame: part.start_frame.to_int(),
      gain: part.gain,
    })
  }
  let mix = match @core.mix_recordings(tracks, octaves~) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let channels = Array::makei(mix.audio.channel_count(), fn(i) {
    mix.audio.channel(i).unwrap()
  })
  let wet = match @audio.write_float32(channels, mix.audio.sample_rate) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let report : Json = {
    "version": 1,
    "sample_rate": Json(mix.audio.sample_rate),
    "channels": Json(channels.length()),
    "frames": Json(mix.audio.frames()),
    "latency_samples": Json(mix.audio.latency_samples),
    "peaks": peaks(channels),
    "scene": input.scene,
    "tracks": Json(
      Array::makei(mix.tracks.length(), fn(i) {
        mix_track_json(input.tracks[i], mix.tracks[i])
      }),
    ),
  }
  ({ "ok": true, "report": report, "wet_wav": encode_audio(wet, true) } : Json).stringify()
}
