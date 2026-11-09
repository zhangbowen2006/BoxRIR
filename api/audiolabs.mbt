///|
priv struct ReferenceInput {
  model : String
  room : Array[Double]
  source : Array[Double]
  receivers : Array[Array[Double]]
  sample_rate : Double
  beta : Json?
  reverberation_time : Double?
  nsample : Double?
  max_order : Double?
  dimension : Double?
  microphone : String?
  orientation : Array[Double]?
  high_pass : Bool?
  speed : Double?
} derive(FromJson)

///|
fn reference_requested(text : String) -> Bool {
  if text.length() > 65536 {
    return false
  }
  let raw = @json.parse(text, reject_duplicate_keys=true, max_nesting_depth=8) catch {
    _ => return false
  }
  if raw is Object(fields) {
    fields.get("model") == Some(Json("audiolabs_v030"))
  } else {
    false
  }
}

///|
fn read_reference(text : String) -> Result[ReferenceInput, String] {
  if text.length() > 65536 {
    return Err("scene JSON limit: 65536 characters")
  }
  let raw = @json.parse(
    text,
    reject_duplicate_keys=true,
    max_nesting_depth=8,
    preserve_number_repr=true,
  ) catch {
    _ => return Err("invalid JSON")
  }
  if raw is Object(fields) {
    for key, value in fields {
      if ![
          "model", "room", "source", "receivers", "sample_rate", "beta", "reverberation_time",
          "nsample", "max_order", "dimension", "microphone", "orientation", "high_pass",
          "speed",
        ].contains(key) {
        return Err("unknown reference scene field: " + key)
      }
      if ["sample_rate", "nsample", "max_order", "dimension"].contains(key) &&
        !integer_literal(value) {
        return Err("integer literal required: " + key)
      }
    }
  } else {
    return Err("scene must be an object")
  }
  let input : ReferenceInput = @json.from_json(raw) catch {
    _ => return Err("invalid reference scene schema")
  }
  if input.model != "audiolabs_v030" {
    return Err("model must be audiolabs_v030")
  }
  if !bounded_int(input.sample_rate, 8000, 96000) ||
    !bounded_int(input.max_order.unwrap_or(-1.0), -1, 12) ||
    !bounded_int(input.dimension.unwrap_or(3.0), 2, 3) {
    return Err("reference sample_rate, max_order or dimension out of range")
  }
  if input.nsample is Some(n) && !bounded_int(n, 1, 192000) {
    return Err("reference nsample out of range")
  }
  Ok(input)
}

///|
fn run_reference(input : ReferenceInput) -> Result[@core.ReferenceRir, String] {
  let room = match point(input.room) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let source = match point(input.source) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let receivers : Array[@core.Vec3] = []
  for r in input.receivers {
    receivers.push(
      match point(r) {
        Ok(v) => v
        Err(e) => return Err(e)
      },
    )
  }
  let beta : Array[Double]? = match input.beta {
    None => None
    Some(j) => {
      let flat : Array[Double] = @json.from_json(j) catch {
        _ => {
          let pairs : Array[Array[Double]] = @json.from_json(j) catch {
            _ => return Err("beta needs six numbers or three wall pairs")
          }
          if pairs.length() != 3 || !pairs.all(fn(p) { p.length() == 2 }) {
            return Err("beta pairs must have shape 3 by 2")
          }
          [
            pairs[0][0],
            pairs[0][1],
            pairs[1][0],
            pairs[1][1],
            pairs[2][0],
            pairs[2][1],
          ]
        }
      }
      Some(flat)
    }
  }
  @core.audiolabs_rir(
    room,
    source,
    receivers,
    input.sample_rate.to_int(),
    speed=input.speed.unwrap_or(343.0),
    beta~,
    reverberation_time=input.reverberation_time,
    nsample=input.nsample.map(fn(n) { n.to_int() }),
    order=input.max_order.unwrap_or(-1.0).to_int(),
    dimension=input.dimension.unwrap_or(3.0).to_int(),
    microphone=input.microphone.unwrap_or("o"),
    orientation=input.orientation.unwrap_or([]),
    high_pass=input.high_pass.unwrap_or(true),
  )
}

///|
fn reference_config(
  input : ReferenceInput,
  response : @core.ReferenceRir,
) -> Json {
  {
    "model": "audiolabs_v030",
    "room": Json(input.room),
    "source": Json(input.source),
    "receivers": Json(input.receivers),
    "beta": Json(response.beta),
    "sample_rate": Json(response.audio.sample_rate),
    "max_order": Json(input.max_order.unwrap_or(-1.0)),
    "speed": Json(input.speed.unwrap_or(343.0)),
    "physical_frames": Json(response.audio.frames()),
    "output_frames": Json(response.audio.frames()),
    "latency_samples": 0,
    "dimension": Json(response.dimension),
    "microphone": Json(response.microphone),
    "orientation": Json(response.orientation),
    "high_pass": Json(response.high_pass),
    "estimated_reverberation_time": Json(response.reverberation_time),
    "kernel_frames": Json(response.kernel_frames),
    "kernel": "upstream_8ms_hann_sinc_no_normalization",
    "timeline": "upstream_sample_indices_clipped_to_nsample",
    "sample_unit": "linear_model_amplitude",
    "wall_order": Json(["x_low", "x_high", "y_low", "y_high", "z_low", "z_high"]),
    "image_semantics": "admitted_after_order_filter_and_zero_axis_pruning",
  }
}

///|
fn reference_report(
  input : ReferenceInput,
  response : @core.ReferenceRir,
) -> Json {
  let channels = Array::makei(response.audio.channel_count(), fn(i) {
    response.audio.channel(i).unwrap()
  })
  {
    "config": reference_config(input, response),
    "geometric_images": Json(
      response.contributing[0] + response.late[0] + response.zero[0],
    ),
    "evaluated_candidates": Json(response.evaluated_candidates),
    "contributing_paths": Json(response.contributing),
    "omitted_late_paths": Json(response.late),
    "zero_gain_paths": Json(response.zero),
    "rir_peaks": peaks(channels),
    "paths": Json(response.paths.map(path_json)),
    "paths_truncated": Json(response.paths_truncated),
    "direct_paths": Json(response.direct_paths.map(path_json)),
  }
}

///|
fn reference_description(text : String) -> String {
  let input = match read_reference(text) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  let result = match run_reference(input) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  ({ "ok": true, "report": reference_report(input, result) } : Json).stringify()
}

///|
/// Float64 channel-major samples for scientific parity checks. JSON output is
/// restricted to 65536 samples; the typed API supports the larger WAV budget.
pub fn reference_samples_json(text : String) -> String {
  let input = match read_reference(text) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  if input.nsample is Some(n) &&
    n * input.receivers.length().to_double() > 65536.0 {
    return error("raw JSON sample budget exceeded: 65536")
  }
  let result = match run_reference(input) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  if result.audio.frames() * result.audio.channel_count() > 65536 {
    return error("raw JSON sample budget exceeded: 65536")
  }
  (
    {
      "ok": true,
      "config": reference_config(input, result),
      "channels": Json(
        Array::makei(result.audio.channel_count(), fn(i) {
          result.audio.channel(i).unwrap()
        }),
      ),
    } : Json).stringify()
}

///|
fn reference_generate(text : String, dry_wav : Bytes, base64 : Bool) -> String {
  let input = match read_reference(text) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  let dry = if dry_wav.is_empty() {
    None
  } else {
    let decoded = match @audio.read_mono(dry_wav) {
      Ok(v) => v
      Err(e) => return error(e)
    }
    if decoded.sample_rate.to_double() != input.sample_rate {
      return error(
        "source and scene sample rates must match; no implicit resampling",
      )
    }
    Some(decoded.samples)
  }
  let result = match run_reference(input) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  let channels = Array::makei(result.audio.channel_count(), fn(i) {
    result.audio.channel(i).unwrap()
  })
  let rir = match @audio.write_float32(channels, result.audio.sample_rate) {
    Ok(v) => v
    Err(e) => return error(e)
  }
  let (wet, wet_info) : (Json, Json) = match dry {
    None => (Json::null(), Json::null())
    Some(samples) => {
      let audio = match result.audio.convolve(samples) {
        Ok(v) => v
        Err(e) => return error(e)
      }
      let output = Array::makei(audio.channel_count(), fn(i) {
        audio.channel(i).unwrap()
      })
      let bytes = match @audio.write_float32(output, audio.sample_rate) {
        Ok(v) => v
        Err(e) => return error(e)
      }
      (
        encode_audio(bytes, base64),
        {
          "frames": Json(audio.frames()),
          "peaks": peaks(output),
          "dry_frames": Json(samples.length()),
        },
      )
    }
  }
  let report = reference_report(input, result)
  if report is Object(fields) {
    fields.set("wet", wet_info)
  }
  (
    {
      "ok": true,
      "report": report,
      "rir_wav": encode_audio(rir, base64),
      "wet_wav": wet,
    } : Json).stringify()
}
