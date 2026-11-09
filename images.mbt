///|
/// Shoebox images are unique; prism candidates are reflection words before
/// finite-face visibility checks. Bounce slots follow the scene geometry.
pub struct ImageSource {
  image : Vec3
  bounces : Array[Int32]
  order : Int32
  reflection : Double
}

///|
/// Count bounded geometric candidates without allocating an image tree.
pub fn Scene::candidate_image_count(self : Scene) -> Int32 {
  if self.footprint is Some(vertices) {
    let walls = vertices.length() + 2
    let mut total = 1
    let mut level = walls
    for _ in 0..<self.max_order {
      total = total + level
      level = level * (walls - 1)
    }
    total
  } else {
    let n = self.max_order
    (4 * n * n * n + 6 * n * n + 8 * n + 3) / 3
  }
}

///|
fn axis_images(
  length : Double,
  source : Double,
  order : Int32,
) -> Array[(Double, Int32, Int32)] {
  let out : Array[(Double, Int32, Int32)] = []
  for n = -order; n <= order; n = n + 1 {
    for p = 0; p < 2; p = p + 1 {
      let low = (n - p).abs()
      let high = n.abs()
      if low + high <= order {
        out.push(
          (
            (1 - 2 * p).to_double() * source + 2.0 * n.to_double() * length,
            low,
            high,
          ),
        )
      }
    }
  }
  out
}

///|
fn power(base : Double, count : Int32) -> Double {
  let mut result = 1.0
  for i = 0; i < count; i = i + 1 {
    result = result * base
  }
  result
}

///|
/// Enumerate geometric candidates, including zero-gain ones. For prisms use
/// trace/trace_prism for physically visible paths, not the raw candidates here.
pub fn images(s : Scene) -> Array[ImageSource] {
  if s.footprint is Some(_) {
    return prism_images(s).map(fn(im) { im.model })
  }
  let xs = axis_images(s.room.x, s.source.x, s.max_order)
  let ys = axis_images(s.room.y, s.source.y, s.max_order)
  let zs = axis_images(s.room.z, s.source.z, s.max_order)
  let beta = s.absorption.map(fn(a) { (1.0 - a).sqrt() })
  let out : Array[ImageSource] = []
  for x in xs {
    for y in ys {
      for z in zs {
        let (xp, xl, xh) = x
        let (yp, yl, yh) = y
        let (zp, zl, zh) = z
        let order = xl + xh + yl + yh + zl + zh
        if order > s.max_order {
          continue
        }
        let bounces = [xl, xh, yl, yh, zl, zh]
        let mut reflection = 1.0
        for i = 0; i < 6; i = i + 1 {
          reflection = reflection * power(beta[i], bounces[i])
        }
        out.push({
          image: { x: xp, y: yp, z: zp, },
          bounces,
          order,
          reflection,
        })
      }
    }
  }
  out.sort_by(fn(a, b) {
    if a.order != b.order {
      a.order - b.order
    } else if a.image.x < b.image.x {
      -1
    } else if a.image.x > b.image.x {
      1
    } else if a.image.y < b.image.y {
      -1
    } else if a.image.y > b.image.y {
      1
    } else if a.image.z < b.image.z {
      -1
    } else if a.image.z > b.image.z {
      1
    } else {
      0
    }
  })
  out
}
