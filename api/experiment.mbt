///|
fn experiment_fields(
  text : String,
  allowed : Array[String],
) -> Result[Map[String, Json], String] {
  if text.length() > 4096 {
    return Err("experiment options exceed 4096 characters")
  }
  let raw = @json.parse(
    text,
    reject_duplicate_keys=true,
    max_nesting_depth=4,
    preserve_number_repr=true,
  ) catch {
    _ => return Err("invalid experiment JSON")
  }
  guard raw is Object(fields) else {
    return Err("experiment options must be a JSON object")
  }
  for key in fields.keys() {
    if !allowed.contains(key) {
      return Err("unknown experiment option: " + key)
    }
  }
  Ok(fields)
}

///|
fn experiment_int(
  fields : Map[String, Json],
  key : String,
  fallback : Int32,
) -> Result[Int32, String] {
  match fields.get(key) {
    None => Ok(fallback)
    Some(Number(value, ..) as field) =>
      if integer_literal(field) && bounded_int(value, -2147483648, 2147483647) {
        Ok(value.to_int())
      } else {
        Err("integer literal required: " + key)
      }
    Some(_) => Err("integer literal required: " + key)
  }
}

///|
fn experiment_number(
  fields : Map[String, Json],
  key : String,
  fallback : Double,
) -> Result[Double, String] {
  match fields.get(key) {
    None => Ok(fallback)
    Some(Number(value, ..)) => Ok(value)
    Some(_) => Err("number required: " + key)
  }
}

///|
fn read_excitation(
  fields : Map[String, Json],
) -> Result[@core.Excitation, String] {
  let required = match fields.get("kind") {
    Some(String("impulse")) => []
    Some(String("sine")) => ["frequency_hz"]
    Some(String("log_sweep")) => ["start_hz", "end_hz"]
    Some(String("white_noise")) => ["seed"]
    _ => return Err("kind must be impulse, sine, log_sweep or white_noise")
  }
  for key in ["frequency_hz", "start_hz", "end_hz", "seed"] {
    if fields.contains(key) != required.contains(key) {
      return Err("probe parameters do not match the selected excitation")
    }
  }
  match fields.get("kind") {
    Some(String("impulse")) => Ok(@core.Impulse)
    Some(String("sine")) =>
      experiment_number(fields, "frequency_hz", 0.0).map(hz => @core.Sine(hz))
    Some(String("log_sweep")) => {
      let start = match experiment_number(fields, "start_hz", 0.0) {
        Err(reason) => return Err(reason)
        Ok(value) => value
      }
      experiment_number(fields, "end_hz", 0.0).map(end => {
        @core.LogSweep(start, end)
      })
    }
    Some(String("white_noise")) =>
      match fields.get("seed") {
        Some(Number(value, ..) as raw) if integer_literal(raw) &&
          value >= 1.0 &&
          value <= 4294967295.0 =>
          Ok(
            @core.WhiteNoise(value.to_int64().reinterpret_as_uint64().to_uint()),
          )
        _ => Err("noise seed must be an integer in 1..4294967295")
      }
    _ => Err("invalid excitation kind")
  }
}

///|
fn read_probe(text : String) -> Result[@core.ProbeSpec, String] {
  let fields = match
    experiment_fields(text, [
      "kind", "sample_rate", "active_frames", "lead_frames", "tail_frames", "fade_frames",
      "amplitude", "frequency_hz", "start_hz", "end_hz", "seed",
    ]) {
    Err(reason) => return Err(reason)
    Ok(value) => value
  }
  let counts : Array[Int32] = []
  for
    (key, fallback) in [
      ("sample_rate", 0),
      ("active_frames", 0),
      ("lead_frames", 0),
      ("tail_frames", 0),
      ("fade_frames", 0),
    ] {
    match experiment_int(fields, key, fallback) {
      Err(reason) => return Err(reason)
      Ok(value) => counts.push(value)
    }
  }
  let amplitude = match experiment_number(fields, "amplitude", 0.7) {
    Err(reason) => return Err(reason)
    Ok(value) => value
  }
  read_excitation(fields).map(excitation => {
    sample_rate: counts[0],
    active_frames: counts[1],
    lead_frames: counts[2],
    tail_frames: counts[3],
    fade_frames: counts[4],
    amplitude,
    excitation,
  })
}

///|
fn audio_wav(audio : @core.Audio) -> Result[Bytes, String] {
  @audio.write_float32(
    Array::makei(audio.channel_count(), fn(i) { audio.channel(i).unwrap() }),
    audio.sample_rate,
  )
}

///|
fn probe_result(audio : @core.Audio) -> String {
  let wav = match audio_wav(audio) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  (
    {
      "ok": true,
      "sample_rate": Json(audio.sample_rate),
      "frames": Json(audio.frames()),
      "probe_wav": encode_audio(wav, true),
    } : Json).stringify()
}

///|
pub fn probe_base64_json(text : String) -> String {
  let spec = match read_probe(text) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  match @core.generate_probe(spec) {
    Err(reason) => error(reason)
    Ok(audio) => probe_result(audio)
  }
}

///|
pub fn default_probe_base64_json(rate : Double) -> String {
  if !bounded_int(rate, 8000, 96000) {
    return error("probe sample rate must be an integer in 8000..96000")
  }
  match @core.default_probe(rate.to_int()) {
    Err(reason) => error(reason)
    Ok(audio) => probe_result(audio)
  }
}

///|
fn optional_int_json(value : Int32?) -> Json {
  match value {
    Some(number) => Json(number)
    None => Json::null()
  }
}

///|
fn optional_number_json(value : Double?) -> Json {
  match value {
    Some(number) => Json(number)
    None => Json::null()
  }
}

///|
fn decay_fit_json(fit : @core.DecayFit) -> Json {
  {
    "status": Json(fit.status),
    "seconds_for_60db": optional_number_json(fit.seconds_for_60db),
    "slope_db_per_second": optional_number_json(fit.slope_db_per_second),
    "r_squared": optional_number_json(fit.r_squared),
    "samples_used": Json(fit.samples_used),
    "start_frame": optional_int_json(fit.start_frame),
    "end_frame": optional_int_json(fit.end_frame),
  }
}

///|
fn decay_channel_json(channel : @core.ChannelDecay) -> Json {
  {
    "onset_frame": optional_int_json(channel.onset_frame),
    "window_end_exclusive": Json(channel.window_end_exclusive),
    "peak": Json(channel.peak),
    "power_sum": Json(channel.power_sum),
    "d50": optional_number_json(channel.d50),
    "c50_db": optional_number_json(channel.c50_db),
    "c80_db": optional_number_json(channel.c80_db),
    "center_time_ms": optional_number_json(channel.center_time_ms),
    "edt": decay_fit_json(channel.edt),
    "t20": decay_fit_json(channel.t20),
    "t30": decay_fit_json(channel.t30),
    "curve": Json(
      channel.curve.map(fn(point) {
        (
          {
            "frame_from_onset": Json(point.frame_from_onset),
            "energy_db": Json(point.energy_db),
          } : Json)
      }),
    ),
  }
}

///|
fn decay_json(analysis : @core.DecayAnalysis) -> Json {
  {
    "schema_version": 1,
    "sample_rate": Json(analysis.sample_rate),
    "frames": Json(analysis.frames),
    "onset_mode": Json(analysis.onset_mode),
    "channels": Json(analysis.channels.map(decay_channel_json)),
  }
}

///|
fn read_frame_list(
  fields : Map[String, Json],
  key : String,
) -> Result[Array[Int32], String] {
  match fields.get(key) {
    None => Ok([])
    Some(Array(values)) => {
      if values.length() > 8 {
        return Err("too many frame positions: " + key)
      }
      let frames : Array[Int32] = []
      for value in values {
        guard value is Number(number, ..) &&
          integer_literal(value) &&
          bounded_int(number, 0, 262143) else {
          return Err(key + " requires integers from 0 to 262143")
        }
        frames.push(number.to_int())
      }
      Ok(frames)
    }
    _ => Err(key + " must be an array")
  }
}

///|
pub fn analyze_wav_json(text : String, wav : Bytes) -> String {
  let fields = match
    experiment_fields(text, ["onset_frames", "end_exclusive", "curve_points"]) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let onset_frames = match read_frame_list(fields, "onset_frames") {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let end_exclusive = match experiment_int(fields, "end_exclusive", 0) {
    Err(reason) => return error(reason)
    Ok(value) =>
      if fields.contains("end_exclusive") {
        Some(value)
      } else {
        None
      }
  }
  let curve_points = match experiment_int(fields, "curve_points", 161) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let wav = match @audio.read_multichannel(wav) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  match
    @core.analyze_decay(
      wav.channels,
      wav.sample_rate,
      onset_frames~,
      end_exclusive~,
      curve_points~,
    ) {
    Err(reason) => error(reason)
    Ok(analysis) =>
      ({ "ok": true, "report": decay_json(analysis) } : Json).stringify()
  }
}

///|
fn transfer_json(estimate : @core.TransferEstimate) -> Json {
  {
    "schema_version": 1,
    "sample_rate": Json(estimate.audio.sample_rate),
    "frames": Json(estimate.audio.frames()),
    "transform_frames": Json(estimate.transform_frames),
    "recording_frames": Json(estimate.recording_frames),
    "probe_frames": Json(estimate.probe_frames),
    "regularization_db": Json(estimate.regularization_db),
    "reliable_bins": Json(estimate.reliable_bins),
    "unique_bins": Json(estimate.unique_bins),
    "channels": Json(
      estimate.channels.map(fn(channel) {
        (
          {
            "peak": Json(channel.peak),
            "outside_window_energy_fraction": optional_number_json(
              channel.outside_window_energy_fraction,
            ),
            "reconstruction_error_fraction": optional_number_json(
              channel.reconstruction_error_fraction,
            ),
          } : Json)
      }),
    ),
  }
}

///|
pub fn estimate_wav_json(
  text : String,
  probe_wav : Bytes,
  recording_wav : Bytes,
) -> String {
  let fields = match
    experiment_fields(text, ["response_frames", "regularization_db"]) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let frames = match experiment_int(fields, "response_frames", 0) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let regularization_db = match
    experiment_number(fields, "regularization_db", -80.0) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let probe = match @audio.read_mono(probe_wav) {
    Err(reason) => return error("probe: " + reason)
    Ok(value) => value
  }
  let recording = match @audio.read_multichannel(recording_wav) {
    Err(reason) => return error("recording: " + reason)
    Ok(value) => value
  }
  if probe.sample_rate != recording.sample_rate {
    return error("probe and recording sample rates must match")
  }
  let estimate = match
    @core.estimate_transfer(
      probe.samples,
      recording.channels,
      probe.sample_rate,
      frames,
      regularization_db~,
    ) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let wav = match audio_wav(estimate.audio) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  (
    {
      "ok": true,
      "report": transfer_json(estimate),
      "rir_wav": encode_audio(wav, true),
    } : Json).stringify()
}

///|
fn differences_json(comparison : @core.ResponseComparison) -> Json {
  {
    "schema_version": 1,
    "sample_rate": Json(comparison.sample_rate),
    "reference_frames": Json(comparison.reference_frames),
    "observed_frames": Json(comparison.observed_frames),
    "compared_frames": Json(comparison.compared_frames),
    "channels": Json(
      comparison.channels.map(fn(channel) {
        (
          {
            "status": Json(channel.status),
            "reference_start": Json(channel.reference_start),
            "requested_observed_start": Json(channel.requested_observed_start),
            "observed_start": Json(channel.observed_start),
            "observed_lag_frames": Json(channel.observed_lag_frames),
            "lag_trials": Json(channel.lag_trials),
            "signed_correlation": optional_number_json(
              channel.signed_correlation,
            ),
            "reference_to_observed_gain": optional_number_json(
              channel.reference_to_observed_gain,
            ),
            "observed_energy_delta_db": optional_number_json(
              channel.observed_energy_delta_db,
            ),
            "raw_error_ratio": optional_number_json(channel.raw_error_ratio),
            "adjusted_error_ratio": optional_number_json(
              channel.adjusted_error_ratio,
            ),
          } : Json)
      }),
    ),
  }
}

///|
pub fn compare_wav_json(
  text : String,
  reference_wav : Bytes,
  observed_wav : Bytes,
) -> String {
  let fields = match
    experiment_fields(text, [
      "frames", "reference_starts", "observed_starts", "lag_radius",
    ]) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let frames = match experiment_int(fields, "frames", 0) {
    Err(reason) => return error(reason)
    Ok(value) => if fields.contains("frames") { Some(value) } else { None }
  }
  let lag_radius = match experiment_int(fields, "lag_radius", 0) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let reference_starts = match read_frame_list(fields, "reference_starts") {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let observed_starts = match read_frame_list(fields, "observed_starts") {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let reference = match @audio.read_multichannel(reference_wav) {
    Err(reason) => return error("reference: " + reason)
    Ok(value) => value
  }
  let observed = match @audio.read_multichannel(observed_wav) {
    Err(reason) => return error("observed: " + reason)
    Ok(value) => value
  }
  if reference.sample_rate != observed.sample_rate {
    return error("reference and observed sample rates must match")
  }
  match
    @core.compare_responses(
      reference.channels,
      observed.channels,
      reference.sample_rate,
      frames~,
      reference_starts~,
      observed_starts~,
      lag_radius~,
    ) {
    Err(reason) => error(reason)
    Ok(comparison) =>
      ({ "ok": true, "report": differences_json(comparison) } : Json).stringify()
  }
}

///|
pub fn resample_wav_json(text : String, wav : Bytes) -> String {
  let fields = match experiment_fields(text, ["sample_rate"]) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let rate = match experiment_int(fields, "sample_rate", 0) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let decoded = match @audio.read_multichannel(wav) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let result = match
    @core.resample_audio(decoded.channels, decoded.sample_rate, rate) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  let output = match audio_wav(result.audio) {
    Err(reason) => return error(reason)
    Ok(value) => value
  }
  (
    {
      "ok": true,
      "report": {
        "schema_version": 1,
        "sample_rate": Json(result.audio.sample_rate),
        "frames": Json(result.audio.frames()),
        "channels": Json(result.audio.channel_count()),
        "input_rate": Json(result.input_rate),
        "input_frames": Json(result.input_frames),
        "tap_radius": Json(result.tap_radius),
        "cached_phases": Json(result.cached_phases),
        "latency_samples": Json(0),
      },
      "wav": encode_audio(output, true),
    } : Json).stringify()
}
