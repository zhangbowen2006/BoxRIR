///|
priv struct Input {
  room : Array[Double]?
  footprint : Array[Array[Double]]?
  height : Double?
  source : Array[Double]
  receivers : Array[Array[Double]]
  absorption : Array[Double]
  sample_rate : Double
  max_order : Double
  duration_ms : Double
  speed : Double?
  half_width : Double?
} derive(FromJson)

///|
fn integer_literal(j : Json) -> Bool {
  if j is Number(_, repr=Some(s)) {
    let mut first = true
    let mut count = 0
    for c in s.iter() {
      if first && c == '-' {
        first = false
        continue
      }
      if c < '0' || c > '9' {
        return false
      }
      first = false
      count = count + 1
    }
    count > 0
  } else {
    false
  }
}

///|
fn bounded_int(v : Double, low : Int32, high : Int32) -> Bool {
  v >= low.to_double() && v <= high.to_double() && v.to_int().to_double() == v
}

///|
fn point(v : Array[Double]) -> Result[@core.Vec3, String] {
  if v.length() != 3 {
    Err("coordinates require exactly three numbers")
  } else {
    Ok({ x: v[0], y: v[1], z: v[2], })
  }
}

///|
pub fn parse_scene(text : String) -> Result[@core.Scene, String] {
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
          "room", "source", "receivers", "absorption", "sample_rate", "max_order",
          "duration_ms", "speed", "half_width", "footprint", "height",
        ].contains(key) {
        return Err("unknown scene field: " + key)
      }
      if ["sample_rate", "max_order", "duration_ms", "half_width"].contains(key) &&
        !integer_literal(value) {
        return Err("integer literal required: " + key)
      }
    }
  } else {
    return Err("scene must be a JSON object")
  }
  let input : Input = @json.from_json(raw) catch {
    _ => return Err("invalid scene schema")
  }
  let half = match input.half_width {
    None => 16.0
    Some(v) => v
  }
  if !bounded_int(input.sample_rate, 8000, 96000) ||
    !bounded_int(input.max_order, 0, 12) ||
    !bounded_int(input.duration_ms, 1, 2000) ||
    !bounded_int(half, 4, 32) {
    return Err("rate/order/duration/kernel out of range")
  }
  let source = match point(input.source) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if input.receivers.is_empty() || input.receivers.length() > 8 {
    return Err("receiver count must be 1..8")
  }
  let receivers : Array[@core.Vec3] = []
  for r in input.receivers {
    receivers.push(
      match point(r) {
        Err(e) => return Err(e)
        Ok(v) => v
      },
    )
  }
  let speed = input.speed.unwrap_or(343.0)
  match (input.room, input.footprint, input.height) {
    (None, Some(vertices), Some(height)) => {
      let footprint : Array[@core.Point2] = []
      for p in vertices {
        if p.length() != 2 {
          return Err("footprint vertices require exactly two numbers")
        }
        footprint.push({ x: p[0], y: p[1], })
      }
      @core.prism_scene(
        footprint,
        height,
        source,
        receivers,
        input.absorption,
        input.sample_rate.to_int(),
        input.max_order.to_int(),
        input.duration_ms.to_int(),
        speed~,
        half_width=half.to_int(),
      )
    }
    (Some(dimensions), None, None) => {
      let room = match point(dimensions) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      @core.scene(
        room,
        source,
        receivers,
        input.absorption,
        input.sample_rate.to_int(),
        input.max_order.to_int(),
        input.duration_ms.to_int(),
        speed~,
        half_width=half.to_int(),
      )
    }
    _ =>
      Err(
        "specify either room, or footprint and height; do not mix geometry models",
      )
  }
}

///|
fn vector(v : @core.Vec3) -> Json {
  Json([v.x, v.y, v.z])
}

///|
fn error(message : String) -> String {
  ({ "ok": false, "error": Json(message) } : Json).stringify()
}

///|
fn image_json(im : @core.ImageSource) -> Json {
  {
    "image": vector(im.image),
    "order": Json(im.order),
    "bounces": Json(im.bounces),
    "reflection": Json(im.reflection),
  }
}

///|
fn path_json(p : @core.Path) -> Json {
  {
    "receiver": Json(p.receiver),
    "image": vector(p.image),
    "bounces": Json(p.bounces),
    "order": Json(p.order),
    "reflection": Json(p.reflection),
    "distance": Json(p.distance),
    "delay_samples": Json(p.delay_samples),
    "gain": Json(p.gain),
  }
}

///|
fn config(s : @core.Scene) -> Json {
  if s.floor_plan() is Some(vertices) {
    return {
      "geometry": "convex_prism",
      "footprint": Json(vertices.map(fn(p) { [p.x, p.y] })),
      "height": Json(s.dimensions().z),
      "source": vector(s.source_position()),
      "receivers": Json(s.receiver_positions().map(vector)),
      "absorption": Json(s.wall_absorption()),
      "sample_rate": Json(s.rate()),
      "max_order": Json(s.order()),
      "speed": Json(s.sound_speed()),
      "physical_frames": Json(s.physical_frames()),
      "output_frames": Json(s.output_frames()),
      "latency_samples": Json(s.latency_samples()),
      "wall_order": "polygon_edges_then_floor_then_ceiling",
      "image_semantics": "reflection_words_before_visibility",
      "path_semantics": "finite_face_hits_excluding_edges_and_corners",
      "kernel": "normalized_hann_sinc",
      "sample_unit": "linear_model_amplitude",
    }
  }
  {
    "room": vector(s.dimensions()),
    "source": vector(s.source_position()),
    "receivers": Json(s.receiver_positions().map(vector)),
    "absorption": Json(s.wall_absorption()),
    "sample_rate": Json(s.rate()),
    "max_order": Json(s.order()),
    "speed": Json(s.sound_speed()),
    "physical_frames": Json(s.physical_frames()),
    "output_frames": Json(s.output_frames()),
    "latency_samples": Json(s.latency_samples()),
    "wall_order": Json(["x_low", "x_high", "y_low", "y_high", "z_low", "z_high"]),
    "kernel": "normalized_hann_sinc",
    "sample_unit": "linear_model_amplitude",
  }
}

///|
/// Geometry-only inspection useful for independent model comparisons.
pub fn describe_json(text : String) -> String {
  let s = match parse_scene(text) {
    Err(e) => return error(e)
    Ok(s) => s
  }
  if s.floor_plan() is Some(_) {
    return (
      {
        "ok": true,
        "config": config(s),
        "images": Json(@core.images(s).map(image_json)),
        "paths": Json(@core.trace(s).map(path_json)),
        "specular_paths": Json(
          @core.trace_prism(s).map(fn(p) {
            {
              "path": path_json(p.path),
              "walls": Json(p.walls),
              "hits": Json(p.hits.map(vector)),
            }
          }),
        ),
      } : Json).stringify()
  }
  (
    {
      "ok": true,
      "config": config(s),
      "images": Json(@core.images(s).map(image_json)),
      "paths": Json(@core.trace(s).map(path_json)),
    } : Json).stringify()
}

///|
fn byte_array(bytes : Bytes) -> Json {
  Json(Array::makei(bytes.length(), fn(i) { bytes[i].to_int() }))
}

///|
fn peaks(channels : Array[Array[Double]]) -> Json {
  Json(
    channels.map(fn(c) {
      c.fold(init=0.0, fn(a, b) { if b.abs() > a { b.abs() } else { a } })
    }),
  )
}

///|
/// RIR export and optional source WAV simulation. Empty bytes request RIR only.
pub fn generate_json(text : String, dry_wav : Bytes) -> String {
  let s = match parse_scene(text) {
    Err(e) => return error(e)
    Ok(s) => s
  }
  // Decode and validate before the more expensive room rendering.
  let dry = if dry_wav.is_empty() {
    None
  } else {
    let d = match @audio.read_mono(dry_wav) {
      Err(e) => return error(e)
      Ok(d) => d
    }
    if d.sample_rate != s.rate() {
      return error(
        "source and scene sample rates must match; no implicit resampling",
      )
    }
    Some(d.samples)
  }
  let r = @core.render(s)
  let channels = Array::makei(r.channel_count(), fn(i) { r.channel(i).unwrap() })
  let rir = match @audio.write_float32(channels, s.rate()) {
    Err(e) => return error(e)
    Ok(v) => v
  }
  let (wet, wet_info) : (Json, Json) = match dry {
    None => (Json::null(), Json::null())
    Some(d) => {
      let a = match @core.convolve(r, d) {
        Err(e) => return error(e)
        Ok(v) => v
      }
      let c = Array::makei(a.channel_count(), fn(i) { a.channel(i).unwrap() })
      let bytes = match @audio.write_float32(c, a.sample_rate) {
        Err(e) => return error(e)
        Ok(v) => v
      }
      (
        byte_array(bytes),
        {
          "frames": Json(a.frames()),
          "peaks": peaks(c),
          "dry_frames": Json(d.length()),
        },
      )
    }
  }
  let report : Json = {
    "config": config(s),
    "geometric_images": Json(@core.images(s).length()),
    "contributing_paths": Json(r.contributing_paths()),
    "omitted_late_paths": Json(r.omitted_late_paths()),
    "zero_gain_paths": Json(r.zero_gain_paths()),
    "rir_peaks": peaks(channels),
    "wet": wet_info,
    "paths": Json(@core.trace(s).map(path_json)),
  }
  (
    { "ok": true, "report": report, "rir_wav": byte_array(rir), "wet_wav": wet } :
    Json).stringify()
}
