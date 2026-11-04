///|
/// Counterclockwise floor-plan vertex in metres, without a repeated last vertex.
pub(all) struct Point2 {
  x : Double
  y : Double
}

///|
priv struct Plane {
  normal : Vec3
  offset : Double
}

///|
priv struct PrismImage {
  model : ImageSource
  sequence : Array[Int32]
  history : Array[Vec3]
}

///|
/// A physical path, with source-to-receiver ordered wall indices and hit points.
pub struct SpecularPath {
  path : Path
  walls : Array[Int32]
  hits : Array[Vec3]
}

///|
const GEOMETRY_EPS : Double = 1.0e-7

///|
fn dot(a : Vec3, b : Vec3) -> Double {
  a.x * b.x + a.y * b.y + a.z * b.z
}

///|
fn subtract(a : Vec3, b : Vec3) -> Vec3 {
  { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z, }
}

///|
fn interpolate(a : Vec3, b : Vec3, t : Double) -> Vec3 {
  {
    x: a.x + t * (b.x - a.x),
    y: a.y + t * (b.y - a.y),
    z: a.z + t * (b.z - a.z),
  }
}

///|
fn mirror(point : Vec3, plane : Plane) -> Vec3 {
  let scale = 2.0 * (dot(plane.normal, point) - plane.offset)
  {
    x: point.x - scale * plane.normal.x,
    y: point.y - scale * plane.normal.y,
    z: point.z - scale * plane.normal.z,
  }
}

///|
fn prism_planes(vertices : Array[Point2], height : Double) -> Array[Plane] {
  let planes : Array[Plane] = []
  for i in 0..<vertices.length() {
    let a = vertices[i]
    let b = vertices[(i + 1) % vertices.length()]
    let dx = b.x - a.x
    let dy = b.y - a.y
    let length = (dx * dx + dy * dy).sqrt()
    let normal = { x: dy / length, y: -dx / length, z: 0.0, }
    planes.push({ normal, offset: normal.x * a.x + normal.y * a.y, })
  }
  planes.push({ normal: { x: 0.0, y: 0.0, z: -1.0, }, offset: 0.0, })
  planes.push({ normal: { x: 0.0, y: 0.0, z: 1.0, }, offset: height, })
  planes
}

///|
fn strictly_inside(point : Vec3, planes : Array[Plane]) -> Bool {
  planes.all(fn(p) { dot(p.normal, point) < p.offset - GEOMETRY_EPS })
}

///|
/// Convex polygon extruded vertically. No holes, concave walls or obstacles.
/// Wall slots follow polygon edges, then floor, then ceiling. Orders 0..4.
pub fn prism_scene(
  footprint : Array[Point2],
  height : Double,
  source : Vec3,
  receivers : Array[Vec3],
  absorption : Array[Double],
  sample_rate : Int32,
  max_order : Int32,
  duration_ms : Int32,
  speed~ : Double = 343.0,
  half_width~ : Int32 = 16,
) -> Result[Scene, String] {
  if footprint.length() < 3 || footprint.length() > 8 {
    return Err("convex footprint needs 3..8 counterclockwise vertices")
  }
  if max_order < 0 || max_order > 4 {
    return Err("convex-prism reflection order must be 0..4")
  }
  if !(height >= 0.1 && height <= 1000.0) {
    return Err("height must be finite in 0.1..1000 metres")
  }
  let mut xmax = 0.0
  let mut ymax = 0.0
  for v in footprint {
    if !(v.x >= 0.0 && v.x <= 1000.0 && v.y >= 0.0 && v.y <= 1000.0) {
      return Err("footprint coordinates must be finite in 0..1000 metres")
    }
    xmax = if v.x > xmax { v.x } else { xmax }
    ymax = if v.y > ymax { v.y } else { ymax }
  }
  for i in 0..<footprint.length() {
    let a = footprint[i]
    let b = footprint[(i + 1) % footprint.length()]
    let dx = b.x - a.x
    let dy = b.y - a.y
    let length = (dx * dx + dy * dy).sqrt()
    if length < 0.1 {
      return Err("each footprint edge must be at least 0.1 metres")
    }
    for j in 0..<footprint.length() {
      if j == i || j == (i + 1) % footprint.length() {
        continue
      }
      let v = footprint[j]
      if (dx * (v.y - a.y) - dy * (v.x - a.x)) / length <= GEOMETRY_EPS {
        return Err(
          "footprint must be strictly convex, counterclockwise and without duplicate vertices",
        )
      }
    }
  }
  if absorption.length() != footprint.length() + 2 {
    return Err(
      "one energy absorption per polygon edge, then floor and ceiling, is required",
    )
  }
  for a in absorption {
    if !(a >= 0.0 && a <= 1.0) {
      return Err("energy absorption must be finite in 0..1")
    }
  }
  let planes = prism_planes(footprint, height)
  if !strictly_inside(source, planes) ||
    !receivers.all(fn(p) { strictly_inside(p, planes) }) {
    return Err("source and receivers must be strictly inside the convex prism")
  }
  // Reuse the unchanged timing, allocation and source-distance checks.
  let s = match
    scene(
      { x: xmax, y: ymax, z: height, },
      source,
      receivers,
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      sample_rate,
      max_order,
      duration_ms,
      speed~,
      half_width~,
    ) {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  Ok({
    room: s.room,
    source: s.source,
    receivers: s.receivers,
    absorption: absorption.copy(),
    sample_rate: s.sample_rate,
    max_order: s.max_order,
    frames: s.frames,
    speed: s.speed,
    half_width: s.half_width,
    footprint: Some(footprint.copy()),
  })
}

///|
/// None means the original six-wall shoebox model.
pub fn Scene::floor_plan(self : Scene) -> Array[Point2]? {
  self.footprint.map(fn(vertices) { vertices.copy() })
}

///|
// Generate words, not deduplicated infinite planes. Consecutive equal walls
// cannot yield a physical reflection, so omit those words before tracing.
fn prism_images(s : Scene) -> Array[PrismImage] {
  let planes = prism_planes(s.footprint.unwrap(), s.room.z)
  let direct : PrismImage = {
    model: {
      image: s.source,
      bounces: Array::make(planes.length(), 0),
      order: 0,
      reflection: 1.0,
    },
    sequence: [],
    history: [s.source],
  }
  let out = [direct]
  let mut frontier = [direct]
  for order = 1; order <= s.max_order; order = order + 1 {
    let next : Array[PrismImage] = []
    for previous in frontier {
      for wall in 0..<planes.length() {
        if !previous.sequence.is_empty() &&
          previous.sequence[previous.sequence.length() - 1] == wall {
          continue
        }
        let image = mirror(previous.model.image, planes[wall])
        let bounces = previous.model.bounces.copy()
        bounces[wall] = bounces[wall] + 1
        let sequence = previous.sequence.copy()
        sequence.push(wall)
        let history = previous.history.copy()
        history.push(image)
        let im : PrismImage = {
          model: {
            image,
            bounces,
            order,
            reflection: previous.model.reflection *
            (1.0 - s.absorption[wall]).sqrt(),
          },
          sequence,
          history,
        }
        next.push(im)
        out.push(im)
      }
    }
    frontier = next
  }
  out
}

///|
fn backtrace(
  im : PrismImage,
  receiver : Vec3,
  planes : Array[Plane],
) -> Array[Vec3]? {
  let reversed : Array[Vec3] = []
  let mut current = receiver
  for k = im.sequence.length() - 1; k >= 0; k = k - 1 {
    let wall = im.sequence[k]
    let plane = planes[wall]
    let direction = subtract(im.history[k + 1], current)
    let denominator = dot(plane.normal, direction)
    if denominator.abs() < GEOMETRY_EPS {
      return None
    }
    let t = (plane.offset - dot(plane.normal, current)) / denominator
    if !(t > 0.0 && t < 1.0) {
      return None
    }
    let hit = interpolate(current, im.history[k + 1], t)
    // A face hit must lie strictly inside that finite face. Edge/corner hits
    // have ambiguous multiple-wall normals; exclude them, never double count.
    for j in 0..<planes.length() {
      if j != wall &&
        dot(planes[j].normal, hit) >= planes[j].offset - GEOMETRY_EPS {
        return None
      }
    }
    if distance(current, hit) < GEOMETRY_EPS {
      return None
    }
    reversed.push(hit)
    current = hit
  }
  Some(
    Array::makei(reversed.length(), fn(i) {
      reversed[reversed.length() - 1 - i]
    }),
  )
}

///|
/// Enumerate and validate each finite-wall specular path. Convexity guarantees
/// the physical segments between validated hits lie inside the room.
pub fn trace_prism(s : Scene) -> Array[SpecularPath] {
  if s.footprint is None {
    return []
  }
  let planes = prism_planes(s.footprint.unwrap(), s.room.z)
  let candidates = prism_images(s)
  let out : Array[SpecularPath] = []
  for receiver in 0..<s.receivers.length() {
    for im in candidates {
      let hits = match backtrace(im, s.receivers[receiver], planes) {
        None => continue
        Some(hits) => hits
      }
      let d = distance(im.model.image, s.receivers[receiver])
      if d < GEOMETRY_EPS {
        continue
      }
      let path : Path = {
        receiver,
        image: im.model.image,
        bounces: im.model.bounces.copy(),
        order: im.model.order,
        distance: d,
        delay_samples: d / s.speed * s.sample_rate.to_double(),
        reflection: im.model.reflection,
        gain: im.model.reflection / (4.0 * PI * d),
      }
      out.push({ path, walls: im.sequence.copy(), hits, })
    }
  }
  out
}
