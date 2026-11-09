///|
priv struct AtmosphereInput {
  temperature_c : Double
  relative_humidity_percent : Double
  pressure_kpa : Double?
} derive(FromJson)

///|
priv struct SpectralInput {
  band_absorption : Array[Array[Double]]
  air_db_per_m : Array[Double]?
  atmosphere : AtmosphereInput?
  band_filter_half_width : Double?
} derive(FromJson)

///|
priv struct SpectralSettings {
  scene : @core.Scene
  materials : Array[Array[Double]]
  air : Array[Double]
  filter_half_width : Int32
  atmosphere : Json
}

///|
fn spectral_requested(text : String) -> Bool {
  if text.length() > 65536 {
    return false
  }
  let raw = @json.parse(text, reject_duplicate_keys=true, max_nesting_depth=8) catch {
    _ => return false
  }
  raw is Object(fields) && fields.get("model") == Some(Json("octave_bands"))
}

///|
fn read_spectral(text : String) -> Result[SpectralSettings, String] {
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
  let fields = match raw {
    Object(fields) => fields
    _ => return Err("spectral scene must be an object")
  }
  if fields.get("model") != Some(Json("octave_bands")) {
    return Err("model must be octave_bands")
  }
  let geometry_keys = [
    "room", "footprint", "height", "source", "receivers", "sample_rate", "max_order",
    "duration_ms", "speed", "half_width",
  ]
  let geometry : Map[String, Json] = Map([])
  for key, value in fields {
    if !geometry_keys.contains(key) &&
      ![
        "model", "band_absorption", "air_db_per_m", "atmosphere", "band_filter_half_width",
      ].contains(key) {
      return Err("unknown spectral scene field: " + key)
    }
    if geometry_keys.contains(key) {
      geometry.set(key, value)
    }
    if key == "band_filter_half_width" && !integer_literal(value) {
      return Err("integer literal required: " + key)
    }
    if key == "atmosphere" {
      if value is Object(conditions) {
        for name, _ in conditions {
          if !["temperature_c", "relative_humidity_percent", "pressure_kpa"].contains(
              name,
            ) {
            return Err("unknown atmosphere field: " + name)
          }
        }
      } else {
        return Err("atmosphere must be an object")
      }
    }
  }
  let input : SpectralInput = @json.from_json(raw) catch {
    _ => return Err("invalid spectral scene schema")
  }
  geometry.set(
    "absorption",
    Json(Array::make(input.band_absorption.length(), 0.0)),
  )
  let scene = match parse_scene(Json(geometry).stringify()) {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  let half = input.band_filter_half_width.unwrap_or(256.0)
  if !bounded_int(half, 64, 512) {
    return Err("band_filter_half_width must be 64..512")
  }
  if input.air_db_per_m is Some(_) && input.atmosphere is Some(_) {
    return Err("specify air_db_per_m OR atmosphere, not both")
  }
  let air = match input.atmosphere {
    Some(a) =>
      match
        @core.atmospheric_air_loss(
          a.temperature_c,
          a.relative_humidity_percent,
          pressure_kpa=a.pressure_kpa.unwrap_or(101.325),
        ) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
    None => input.air_db_per_m.unwrap_or([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
  }
  Ok({
    scene,
    materials: input.band_absorption,
    air,
    filter_half_width: half.to_int(),
    atmosphere: fields.get("atmosphere").unwrap_or(Json::null()),
  })
}

///|
fn run_spectral(input : SpectralSettings) -> Result[@core.SpectralRir, String] {
  @core.spectral_rir(
    input.scene,
    input.materials,
    air_db_per_m=input.air,
    filter_half_width=input.filter_half_width,
  )
}

///|
fn spectral_report(
  input : SpectralSettings,
  response : @core.SpectralRir,
) -> Json {
  let cfg = config(input.scene)
  if cfg is Object(fields) {
    fields.remove("absorption")
    fields.set("model", Json("octave_bands"))
    fields.set("band_centers_hz", Json(@core.octave_centers()))
    fields.set("band_absorption", Json(response.band_absorption))
    fields.set("air_db_per_m", Json(response.air_db_per_m))
    fields.set("atmosphere", input.atmosphere)
    fields.set("band_filter_half_width", Json(response.filter_half_width))
    fields.set("output_frames", Json(response.audio.frames()))
    fields.set("latency_samples", Json(response.audio.latency_samples))
    fields.set(
      "kernel",
      Json("normalized_fractional_delay_then_complementary_hamming_fir_bank"),
    )
    fields.set(
      "gain_semantics",
      Json("path_gain_is_geometric_only; band_gains_include_material_and_air"),
    )
  }
  let channels = Array::makei(response.audio.channel_count(), fn(i) {
    response.audio.channel(i).unwrap()
  })
  {
    "config": cfg,
    "geometric_images": Json(response.geometric_images),
    "contributing_paths": Json(response.contributing),
    "omitted_late_paths": Json(response.late),
    "zero_gain_paths": Json(response.zero),
    "rir_peaks": peaks(channels),
    "paths": Json(response.paths.map(fn(p) { path_json(p.path) })),
    "band_paths": Json(
      response.paths.map(fn(p) {
        ({ "path": path_json(p.path), "band_gains": Json(p.band_gains) } : Json)
      }),
    ),
    "paths_truncated": Json(response.paths_truncated),
    "direct_paths": Json(response.direct_paths.map(path_json)),
  }
}

///|
pub fn spectral_samples_json(text : String) -> String {
  let input = match read_spectral(text) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  if (input.scene.output_frames() + 2 * input.filter_half_width) *
    input.scene.receiver_positions().length() >
    65536 {
    return error("raw JSON sample budget exceeded: 65536")
  }
  let response = match run_spectral(input) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  (
    {
      "ok": true,
      "report": spectral_report(input, response),
      "channels": Json(
        Array::makei(response.audio.channel_count(), fn(i) {
          response.audio.channel(i).unwrap()
        }),
      ),
    } : Json).stringify()
}

///|
fn spectral_description(text : String) -> String {
  let input = match read_spectral(text) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let response = match run_spectral(input) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  ({ "ok": true, "report": spectral_report(input, response) } : Json).stringify()
}

///|
fn spectral_generate(text : String, dry_wav : Bytes, base64 : Bool) -> String {
  let input = match read_spectral(text) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let dry = if dry_wav.is_empty() {
    None
  } else {
    let d = match @audio.read_mono(dry_wav) {
      Err(e) => return error(e)
      Ok(v) => v
    }
    if d.sample_rate != input.scene.rate() {
      return error(
        "source and scene sample rates must match; no implicit resampling",
      )
    }
    Some(d.samples)
  }
  let response = match run_spectral(input) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let rir = match
    @audio.write_float32(
      Array::makei(response.audio.channel_count(), fn(i) {
        response.audio.channel(i).unwrap()
      }),
      input.scene.rate(),
    ) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let (wet, info) : (Json, Json) = match dry {
    None => (Json::null(), Json::null())
    Some(samples) => {
      let audio = match response.audio.convolve(samples) {
        Err(e) => return error(e)
        Ok(v) => v
      }
      let channels = Array::makei(audio.channel_count(), fn(i) {
        audio.channel(i).unwrap()
      })
      let bytes = match @audio.write_float32(channels, audio.sample_rate) {
        Err(e) => return error(e)
        Ok(v) => v
      }
      (
        encode_audio(bytes, base64),
        {
          "frames": Json(audio.frames()),
          "peaks": peaks(channels),
          "dry_frames": Json(samples.length()),
        },
      )
    }
  }
  let report = spectral_report(input, response)
  if report is Object(fields) {
    fields.set("wet", info)
  }
  (
    {
      "ok": true,
      "report": report,
      "rir_wav": encode_audio(rir, base64),
      "wet_wav": wet,
    } : Json).stringify()
}
