///|
/// Coordinates in metres. The room origin is its low-x/low-y/low-z corner.
pub(all) struct Vec3 {
  x : Double
  y : Double
  z : Double
}

///|
pub struct Scene {
  priv room : Vec3
  priv source : Vec3
  priv receivers : Array[Vec3]
  priv absorption : Array[Double]
  priv sample_rate : Int32
  priv max_order : Int32
  priv frames : Int32
  priv speed : Double
  priv half_width : Int32
  priv footprint : Array[Point2]?
}

///|
fn inside(p : Vec3, room : Vec3) -> Bool {
  p.x > 0.0 &&
  p.x < room.x &&
  p.y > 0.0 &&
  p.y < room.y &&
  p.z > 0.0 &&
  p.z < room.z
}

///|
fn distance(a : Vec3, b : Vec3) -> Double {
  let x = a.x - b.x
  let y = a.y - b.y
  let z = a.z - b.z
  (x * x + y * y + z * z).sqrt()
}

///|
/// Validates before allocating. Arrays are copied to isolate caller mutation.
pub fn scene(
  room : Vec3,
  source : Vec3,
  receivers : Array[Vec3],
  absorption : Array[Double],
  sample_rate : Int32,
  max_order : Int32,
  duration_ms : Int32,
  speed~ : Double = 343.0,
  half_width~ : Int32 = 16,
) -> Result[Scene, String] {
  for v in [room.x, room.y, room.z] {
    if !(v >= 0.1 && v <= 1000.0) {
      return Err("room dimensions must be finite in 0.1..1000 metres")
    }
  }
  if !inside(source, room) {
    return Err("source must be strictly inside the room")
  }
  if receivers.is_empty() || receivers.length() > 8 {
    return Err("receiver count must be 1..8")
  }
  for r in receivers {
    if !inside(r, room) {
      return Err("receiver must be strictly inside the room")
    }
    if distance(source, r) < 0.01 {
      return Err("source-receiver distance must be at least 0.01 metres")
    }
  }
  if absorption.length() != 6 {
    return Err("six wall absorption coefficients are required")
  }
  for a in absorption {
    if !(a >= 0.0 && a <= 1.0) {
      return Err("energy absorption must be finite in 0..1")
    }
  }
  if sample_rate < 8000 ||
    sample_rate > 96000 ||
    max_order < 0 ||
    max_order > 12 ||
    duration_ms < 1 ||
    duration_ms > 2000 ||
    half_width < 4 ||
    half_width > 32 ||
    !(speed >= 100.0 && speed <= 1000.0) {
    return Err("invalid rate, order, duration, kernel width or sound speed")
  }
  let frames = (sample_rate * duration_ms + 999) / 1000
  if (frames + 2 * half_width) * receivers.length() > 1000000 {
    return Err("RIR sample budget exceeded: 1000000")
  }
  Ok({
    room,
    source,
    receivers: receivers.copy(),
    absorption: absorption.copy(),
    sample_rate,
    max_order,
    frames,
    speed,
    half_width,
    footprint: None,
  })
}

///|
pub fn Scene::physical_frames(self : Scene) -> Int32 {
  self.frames
}

///|
pub fn Scene::output_frames(self : Scene) -> Int32 {
  self.frames + 2 * self.half_width
}

///|
pub fn Scene::latency_samples(self : Scene) -> Int32 {
  self.half_width
}

///|
pub fn Scene::rate(self : Scene) -> Int32 {
  self.sample_rate
}

///|
pub fn Scene::order(self : Scene) -> Int32 {
  self.max_order
}

///|
pub fn Scene::sound_speed(self : Scene) -> Double {
  self.speed
}

///|
pub fn Scene::dimensions(self : Scene) -> Vec3 {
  self.room
}

///|
pub fn Scene::source_position(self : Scene) -> Vec3 {
  self.source
}

///|
pub fn Scene::receiver_positions(self : Scene) -> Array[Vec3] {
  self.receivers.copy()
}

///|
pub fn Scene::wall_absorption(self : Scene) -> Array[Double] {
  self.absorption.copy()
}
