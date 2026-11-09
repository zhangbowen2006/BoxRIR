///|
pub struct Response {
  priv scene : Scene
  priv samples : Array[Array[Double]]
  priv contributing : Array[Int32]
  priv late : Array[Int32]
  priv zero : Array[Int32]
  priv path_details : Array[Path]
}

///|
/// Finite windowed sinc, normalized before placement. Integer delay is exact.
fn delay_taps(fraction : Double, half : Int32) -> Array[Double] {
  if fraction == 0.0 {
    return Array::makei(2 * half + 1, fn(i) {
      if i == half {
        1.0
      } else {
        0.0
      }
    })
  }
  let taps = Array::makei(2 * half + 1, fn(i) {
    let t = (i - half).to_double() - fraction
    if t.abs() > half.to_double() {
      0.0
    } else if t.abs() < 1.0e-14 {
      1.0
    } else {
      @math.sin(PI * t) /
      (PI * t) *
      0.5 *
      (1.0 + @math.cos(PI * t / half.to_double()))
    }
  })
  let sum = taps.fold(init=0.0, fn(a, b) { a + b })
  taps.map(fn(v) { v / sum })
}

///|
/// Every retained path gets its complete kernel in a globally delayed output.
pub fn render(s : Scene) -> Response {
  let channels = Array::makei(s.receivers.length(), fn(_) {
    Array::make(s.output_frames(), 0.0)
  })
  let contributing = Array::make(s.receivers.length(), 0)
  let late = Array::make(s.receivers.length(), 0)
  let zero = Array::make(s.receivers.length(), 0)
  let paths = trace(s)
  for p in paths {
    let r = p.receiver
    if p.delay_samples >= s.frames.to_double() {
      late[r] = late[r] + 1
      continue
    }
    if p.gain == 0.0 {
      zero[r] = zero[r] + 1
      continue
    }
    let base = @math.floor(p.delay_samples).to_int()
    let taps = delay_taps(p.delay_samples - base.to_double(), s.half_width)
    for i = 0; i < taps.length(); i = i + 1 {
      channels[r][base + i] = channels[r][base + i] + p.gain * taps[i]
    }
    contributing[r] = contributing[r] + 1
  }
  {
    scene: s,
    samples: channels,
    contributing,
    late,
    zero,
    path_details: paths,
  }
}

///|
pub fn Response::channel(
  self : Response,
  index : Int32,
) -> Result[Array[Double], String] {
  if index < 0 || index >= self.samples.length() {
    Err("receiver index out of range")
  } else {
    Ok(self.samples[index].copy())
  }
}

///|
pub fn Response::channel_count(self : Response) -> Int32 {
  self.samples.length()
}

///|
pub fn Response::settings(self : Response) -> Scene {
  self.scene
}

///|
pub fn Response::contributing_paths(self : Response) -> Array[Int32] {
  self.contributing.copy()
}

///|
pub fn Response::omitted_late_paths(self : Response) -> Array[Int32] {
  self.late.copy()
}

///|
pub fn Response::zero_gain_paths(self : Response) -> Array[Int32] {
  self.zero.copy()
}

///|
/// Reuse the paths used for this render; isolate mutable bounce-count arrays.
pub fn Response::paths(self : Response) -> Array[Path] {
  self.path_details.map(fn(p) { { ..p, bounces: p.bounces.copy(), } })
}
