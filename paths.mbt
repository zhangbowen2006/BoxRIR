///|
/// One geometrical propagation path to one receiver. No arrival-time deduplication.
pub struct Path {
  receiver : Int32
  image : Vec3
  bounces : Array[Int32]
  order : Int32
  distance : Double
  delay_samples : Double
  reflection : Double
  gain : Double
}

///|
const PI : Double = 3.141592653589793

///|
/// Includes all finite-order geometric paths, even beyond the recording window.
/// Receiver-major, then reflection order / image coordinate order.
pub fn trace(s : Scene) -> Array[Path] {
  if s.footprint is Some(_) {
    return trace_prism(s).map(fn(p) { p.path })
  }
  let sources = images(s)
  let out : Array[Path] = []
  for receiver = 0; receiver < s.receivers.length(); receiver = receiver + 1 {
    for im in sources {
      let d = distance(im.image, s.receivers[receiver])
      out.push({
        receiver,
        image: im.image,
        bounces: im.bounces.copy(),
        order: im.order,
        distance: d,
        delay_samples: d / s.speed * s.sample_rate.to_double(),
        reflection: im.reflection,
        gain: im.reflection / (4.0 * PI * d),
      })
    }
  }
  out
}
