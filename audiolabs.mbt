// Numerical kernel ported from AudioLabs rir-generator v0.3.0, core version
// 2.2.20201022, commit 052790faade19074c6921e007fb8972c60e8f0a6.
// Copyright (C) 2003-2020 E.A.P. Habets. MIT license retained in
// docs/licenses/audiolabs-rir-generator-MIT.txt. BoxRIR validation, resource
// limits, typed output and diagnostic collection are additions to that port.

///|
/// Pressure coefficients, NOT energy absorption. Sample timeline has no added
/// latency; the upstream 8 ms interpolation kernel is clipped to nsample.
pub struct ReferenceRir {
  audio : Audio
  beta : Array[Double]
  reverberation_time : Double?
  microphone : String
  orientation : Array[Double]
  dimension : Int32
  high_pass : Bool
  kernel_frames : Int32
  evaluated_candidates : Int32
  contributing : Array[Int32]
  late : Array[Int32]
  zero : Array[Int32]
  paths : Array[Path]
  direct_paths : Array[Path]
  paths_truncated : Bool
}

///|
fn microphone_pattern(name : String) -> (String, Double)? {
  match name {
    "o" | "omnidirectional" => Some(("o", 1.0))
    "b" | "bidirectional" => Some(("b", 0.0))
    "c" | "cardioid" => Some(("c", 0.5))
    "s" | "subcardioid" => Some(("s", 0.75))
    "h" | "hypercardioid" => Some(("h", 0.25))
    _ => None
  }
}

///|
fn directional_gain(
  x : Double,
  y : Double,
  z : Double,
  angles : Array[Double],
  rho : Double,
) -> Double {
  if rho == 1.0 {
    return 1.0
  }
  // Preserve the upstream spherical-angle convention, including signed rear
  // lobes. x/y/z point from the microphone toward the unfolded source image.
  let polar = @math.acos(z / (x * x + y * y + z * z).sqrt())
  let azimuth = @math.atan2(y, x)
  let alignment = @math.sin(PI / 2.0 - angles[1]) *
    @math.sin(polar) *
    @math.cos(angles[0] - azimuth) +
    @math.cos(PI / 2.0 - angles[1]) * @math.cos(polar)
  rho + (1.0 - rho) * alignment
}

///|
/// AudioLabs-compatible numerical profile on a bounded, finite physical domain.
/// Exactly one of beta / reverberation_time is required. dim=2 suppresses
/// floor/ceiling reflections; it does not discard the supplied z coordinates.
pub fn audiolabs_rir(
  room : Vec3,
  source : Vec3,
  receivers : Array[Vec3],
  sample_rate : Int32,
  speed~ : Double = 343.0,
  beta~ : Array[Double]? = None,
  reverberation_time~ : Double? = None,
  nsample~ : Int32? = None,
  order~ : Int32 = -1,
  dimension~ : Int32 = 3,
  microphone~ : String = "o",
  orientation~ : Array[Double] = [],
  high_pass~ : Bool = true,
) -> Result[ReferenceRir, String] {
  // Common geometry checks, with no legacy absorption or latency conversion.
  let checked = scene(
    room,
    source,
    receivers,
    Array::make(6, 0.0),
    sample_rate,
    0,
    1,
    speed~,
  )
  if checked is Err(e) {
    return Err(e)
  }
  if order < -1 || order > 12 || (dimension != 2 && dimension != 3) {
    return Err("reference order must be -1..12 and dimension must be 2 or 3")
  }
  let (mtype, rho) = match microphone_pattern(microphone) {
    None => return Err("microphone must be o/b/c/s/h or its full pattern name")
    Some(v) => v
  }
  if orientation.length() > 2 ||
    !orientation.all(fn(v) { v >= -1.0e6 && v <= 1.0e6 }) {
    return Err(
      "orientation needs 0..2 finite radian angles with abs <= 1000000",
    )
  }
  let angles = match orientation.length() {
    0 => [0.0, 0.0]
    1 => [orientation[0], 0.0]
    _ => orientation.copy()
  }
  let speed = checked.unwrap().sound_speed()
  let area_sum = room.z * room.x + room.y * room.z + room.x * room.y
  let volume = room.x * room.y * room.z
  let (coefficients, rt) : (Array[Double], Double?) = match
    (beta, reverberation_time) {
    (Some(values), None) => {
      if values.length() != 6 || !values.all(fn(v) { v >= -1.0 && v <= 1.0 }) {
        return Err(
          "beta needs six finite pressure reflection coefficients in -1..1",
        )
      }
      // Intentionally match the v0.3.0 Python wrapper's auto-length formula,
      // not a claim of physically measured RT60 or an improved Sabine formula.
      let mut alpha = 0.0
      for axis in 0..<3 {
        let low = values[2 * axis]
        let high = values[2 * axis + 1]
        alpha = alpha + (1.0 - low * low + (1.0 - high * high)) * area_sum
      }
      let estimate = if alpha == 0.0 {
        None
      } else {
        let t = 24.0 * 2.302585092994046 * volume / (speed * alpha)
        Some(if t > 0.128 { t } else { 0.128 })
      }
      (values.copy(), estimate)
    }
    (None, Some(t)) => {
      if !(t >= 0.0 && t <= 30.0) {
        return Err("reverberation_time must be finite in 0..30 seconds")
      }
      let alpha = if t == 0.0 {
        1.0
      } else {
        24.0 * 2.302585092994046 * volume / (speed * 2.0 * area_sum * t)
      }
      if alpha > 1.0 {
        return Err(
          "room and reverberation_time require impossible energy absorption",
        )
      }
      (Array::make(6, (1.0 - alpha).sqrt()), Some(t))
    }
    _ => return Err("specify exactly one of beta and reverberation_time")
  }
  let frames = match nsample {
    Some(n) => n
    None =>
      match rt {
        None => return Err("explicit nsample is required for lossless beta")
        Some(t) => {
          if t * sample_rate.to_double() > 192000.0 {
            return Err("reference output frame budget exceeded")
          }
          (t * sample_rate.to_double()).to_int()
        }
      }
  }
  if frames < 1 || frames > 192000 || frames * receivers.length() > 1000000 {
    return Err(
      "reference output needs 1..192000 frames and at most 1000000 total samples",
    )
  }
  if dimension == 2 {
    coefficients[4] = 0.0
    coefficients[5] = 0.0
  }
  let scale = speed / sample_rate.to_double()
  let lengths = [room.x / scale, room.y / scale, room.z / scale]
  let position = [source.x / scale, source.y / scale, source.z / scale]
  let limits = Array::makei(3, fn(axis) {
    let bound = @math.ceil(frames.to_double() / (2.0 * lengths[axis])).to_int()
    if coefficients[2 * axis] == 0.0 && coefficients[2 * axis + 1] == 0.0 {
      0
    } else if order >= 0 {
      Int32::min(bound, (order + 1) / 2)
    } else {
      bound
    }
  })
  let mut budget = 8.0 * receivers.length().to_double()
  for limit in limits {
    budget = budget * (2 * limit + 1).to_double()
  }
  if budget > 2000000.0 {
    return Err("reference image candidate budget exceeded: 2000000")
  }
  let width = 2 * @math.floor(0.004 * sample_rate.to_double() + 0.5).to_int()
  let channels : Array[Array[Double]] = []
  let contributing = Array::make(receivers.length(), 0)
  let late = Array::make(receivers.length(), 0)
  let zero = Array::make(receivers.length(), 0)
  let paths : Array[Path] = []
  let direct_paths : Array[Path] = []
  let mut evaluated = 0
  let mut taps_used = 0
  let mut truncated = false
  for receiver in 0..<receivers.length() {
    let r = receivers[receiver]
    let microphone_position = [r.x / scale, r.y / scale, r.z / scale]
    let samples = Array::make(frames, 0.0)
    // Loop order follows the reference accumulation order. Pruning impossible
    // finite-order / zero-coefficient images only removes exact zero terms.
    for mx = -limits[0]; mx <= limits[0]; mx = mx + 1 {
      for my = -limits[1]; my <= limits[1]; my = my + 1 {
        for mz = -limits[2]; mz <= limits[2]; mz = mz + 1 {
          for q in 0..<2 {
            let x = (1 - 2 * q).to_double() * position[0] -
              microphone_position[0] +
              2.0 * mx.to_double() * lengths[0]
            let rx = power(coefficients[0], (mx - q).abs()) *
              power(coefficients[1], mx.abs())
            for j in 0..<2 {
              let y = (1 - 2 * j).to_double() * position[1] -
                microphone_position[1] +
                2.0 * my.to_double() * lengths[1]
              let ry = power(coefficients[2], (my - j).abs()) *
                power(coefficients[3], my.abs())
              for k in 0..<2 {
                evaluated = evaluated + 1
                let total_order = (2 * mx - q).abs() +
                  (2 * my - j).abs() +
                  (2 * mz - k).abs()
                if order >= 0 && total_order > order {
                  continue
                }
                let z = (1 - 2 * k).to_double() * position[2] -
                  microphone_position[2] +
                  2.0 * mz.to_double() * lengths[2]
                let rz = power(coefficients[4], (mz - k).abs()) *
                  power(coefficients[5], mz.abs())
                let d = (x * x + y * y + z * z).sqrt()
                let integer = @math.floor(d).to_int()
                let reflection = rx * ry * rz
                let gain = directional_gain(x, y, z, angles, rho) *
                  rx *
                  ry *
                  rz /
                  (4.0 * PI * d * scale)
                let path : Path = {
                  receiver,
                  image: {
                    x: (1 - 2 * q).to_double() * source.x +
                    2.0 * mx.to_double() * room.x,
                    y: (1 - 2 * j).to_double() * source.y +
                    2.0 * my.to_double() * room.y,
                    z: (1 - 2 * k).to_double() * source.z +
                    2.0 * mz.to_double() * room.z,
                  },
                  bounces: [
                    (mx - q).abs(),
                    mx.abs(),
                    (my - j).abs(),
                    my.abs(),
                    (mz - k).abs(),
                    mz.abs(),
                  ],
                  order: total_order,
                  distance: d * scale,
                  delay_samples: d,
                  reflection,
                  gain,
                }
                if total_order == 0 {
                  direct_paths.push(path)
                }
                if paths.length() < 10000 {
                  paths.push(path)
                } else {
                  truncated = true
                }
                if integer >= frames {
                  late[receiver] = late[receiver] + 1
                  continue
                }
                if gain == 0.0 {
                  zero[receiver] = zero[receiver] + 1
                  continue
                }
                if taps_used > 64000000 - width {
                  return Err(
                    "reference interpolation budget exceeded: 64000000 taps",
                  )
                }
                taps_used = taps_used + width
                let start = integer - width / 2 + 1
                for n in 0..<width {
                  let output = start + n
                  if output < 0 || output >= frames {
                    continue
                  }
                  let t = (n - width / 2 + 1).to_double() -
                    (d - integer.to_double())
                  let sinc = if t == 0.0 {
                    1.0
                  } else {
                    @math.sin(PI * t) / (PI * t)
                  }
                  let kernel = 0.5 *
                    (1.0 + @math.cos(2.0 * PI * t / width.to_double())) *
                    sinc
                  samples[output] = samples[output] + gain * kernel
                }
                contributing[receiver] = contributing[receiver] + 1
              }
            }
          }
        }
      }
    }
    if high_pass {
      let w = 2.0 * PI * 100.0 / sample_rate.to_double()
      let r1 = @math.exp(-w)
      let b1 = 2.0 * r1 * @math.cos(w)
      let b2 = -r1 * r1
      let a1 = -(1.0 + r1)
      let mut y0 = 0.0
      let mut y1 = 0.0
      for i in 0..<frames {
        let y2 = y1
        y1 = y0
        y0 = b1 * y1 + b2 * y2 + samples[i]
        samples[i] = y0 + a1 * y1 + r1 * y2
      }
    }
    channels.push(samples)
  }
  Ok({
    audio: { samples: channels, sample_rate, latency_samples: 0, },
    beta: coefficients,
    reverberation_time: rt,
    microphone: mtype,
    orientation: angles,
    dimension,
    high_pass,
    kernel_frames: width,
    evaluated_candidates: evaluated,
    contributing,
    late,
    zero,
    paths,
    direct_paths,
    paths_truncated: truncated,
  })
}
