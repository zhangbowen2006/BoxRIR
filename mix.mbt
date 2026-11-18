///|
/// A mono dry signal placed at an integer sample offset on a shared scene timeline.
/// Every scene has the same room, receivers, rate and rendering settings.
/// Source positions may differ. Gain is a signed linear multiplier.
pub(all) struct RecordingTrack {
  scene : Scene
  dry : Array[Double]
  sample_rate : Int32
  start_frame : Int32
  gain : Double
}

///|
/// Shared six-band materials and air attenuation for a multitrack render.
pub(all) struct RecordingOctaves {
  band_absorption : Array[Array[Double]]
  air_db_per_m : Array[Double]
  filter_half_width : Int32
}

///|
/// `end_frame` is the exclusive end of the complete shifted convolution.
/// Timing includes the model's common FIR latency but no resampling or padding
/// beyond the full convolution lengths and requested track start offsets.
pub struct RecordingTrackReport {
  start_frame : Int32
  gain : Double
  dry_frames : Int32
  rir_frames : Int32
  wet_frames : Int32
  end_frame : Int32
  latency_samples : Int32
  contributing_paths : Array[Int32]
  omitted_late_paths : Array[Int32]
  zero_gain_paths : Array[Int32]
}

///|
pub struct RecordingMix {
  audio : Audio
  tracks : Array[RecordingTrackReport]
}

///|
fn same_xyz(a : Vec3, b : Vec3) -> Bool {
  a.x == b.x && a.y == b.y && a.z == b.z
}

///|
fn same_recording_geometry(a : Scene, b : Scene) -> Bool {
  if !same_xyz(a.room, b.room) || a.receivers.length() != b.receivers.length() {
    return false
  }
  for i in 0..<a.receivers.length() {
    if !same_xyz(a.receivers[i], b.receivers[i]) {
      return false
    }
  }
  match (a.footprint, b.footprint) {
    (None, None) => true
    (Some(left), Some(right)) => {
      if left.length() != right.length() {
        return false
      }
      for i in 0..<left.length() {
        if left[i].x != right[i].x || left[i].y != right[i].y {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn same_recording_scene(a : Scene, b : Scene) -> Bool {
  a.sample_rate == b.sample_rate &&
  a.speed == b.speed &&
  a.half_width == b.half_width &&
  a.frames == b.frames &&
  a.max_order == b.max_order &&
  a.absorption == b.absorption &&
  same_recording_geometry(a, b)
}

///|
fn mix_filter_width(
  s : Scene,
  octaves : RecordingOctaves?,
) -> Result[Int32, String] {
  match octaves {
    None => Ok(0)
    Some(p) => {
      if p.band_absorption.length() != s.absorption.length() ||
        !p.band_absorption.all(fn(wall) {
          wall.length() == 6 && wall.all(fn(a) { a >= 0.0 && a <= 1.0 })
        }) {
        return Err(
          "recording octave materials need one six-band row per wall, values 0..1",
        )
      }
      if p.air_db_per_m.length() != 6 ||
        !p.air_db_per_m.all(fn(loss) { loss >= 0.0 && loss <= 10.0 }) {
        return Err("recording octave air loss needs six values in 0..10 dB/m")
      }
      spectral_width(s.sample_rate, p.filter_half_width)
    }
  }
}

///|
priv struct MixSizing {
  frames : Int32
  rir_frames : Int32
  latency : Int32
  filter_half_width : Int32
}

///|
/// Check all tracks and aggregate work before tracing or allocating output.
fn preflight_mix(
  tracks : Array[RecordingTrack],
  octaves : RecordingOctaves?,
) -> Result[MixSizing, String] {
  if tracks.is_empty() || tracks.length() > 4 {
    return Err("recording requires 1..4 tracks")
  }
  let shared = tracks[0].scene
  let count = shared.receivers.length()
  let half = match mix_filter_width(shared, octaves) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let rir_frames = shared.output_frames() + 2 * half
  let band_count = if half > 0 { 6 } else { 1 }
  let band_samples = rir_frames * count * band_count
  if half > 0 && band_samples > 1000000 {
    return Err("recording octave intermediate sample budget per track: 1000000")
  }
  if band_samples.to_int64() * tracks.length().to_int64() > 3000000L {
    return Err("recording intermediate RIR sample budget: 3000000")
  }
  let path_count = shared.candidate_image_count().to_int64() *
    count.to_int64() *
    tracks.length().to_int64()
  let tap_budget = path_count *
    (2 * shared.half_width + 1).to_int64() *
    band_count.to_int64()
  if path_count > 200000L || tap_budget > 64000000L {
    return Err("recording geometry or interpolation work budget exceeded")
  }
  let mut total_dry = 0
  let mut total_wet = 0L
  let mut frames = 0L
  for i in 0..<tracks.length() {
    let t = tracks[i]
    if !same_recording_scene(shared, t.scene) {
      return Err(
        "recording track \{i + 1} must share the room, receivers and rendering settings",
      )
    }
    if t.sample_rate != shared.sample_rate {
      return Err(
        "recording track \{i + 1} sample rate does not match the scene",
      )
    }
    if t.dry.is_empty() || t.dry.length() > 262144 {
      return Err("recording track \{i + 1} needs 1..262144 dry frames")
    }
    total_dry = total_dry + t.dry.length()
    if total_dry > 262144 {
      return Err("recording total dry frame budget: 262144")
    }
    if !t.dry.all(fn(v) { v >= -1.0e6 && v <= 1.0e6 }) {
      return Err(
        "recording track \{i + 1} dry samples must be finite and abs <= 1000000",
      )
    }
    if t.start_frame < 0 || !(t.gain >= -100.0 && t.gain <= 100.0) {
      return Err(
        "recording track \{i + 1} requires a nonnegative offset and gain in -100..100",
      )
    }
    let wet_frames = (t.dry.length() + rir_frames - 1).to_int64()
    let end_frame = t.start_frame.to_int64() + wet_frames
    total_wet = total_wet + wet_frames * count.to_int64()
    frames = Int64::max(frames, end_frame)
    if end_frame > 262144L || frames * count.to_int64() > 2000000L {
      return Err(
        "recording output budget exceeded: 262144 frames or 2000000 samples",
      )
    }
    if total_wet > 4000000L {
      return Err("recording total convolution sample budget: 4000000")
    }
  }
  Ok({
    frames: frames.to_int(),
    rir_frames,
    latency: shared.half_width + half,
    filter_half_width: half,
  })
}

///|
priv struct TrackRender {
  wet : Audio
  contributing : Array[Int32]
  late : Array[Int32]
  zero : Array[Int32]
}

///|
fn render_recording_track(
  track : RecordingTrack,
  octaves : RecordingOctaves?,
  half_width : Int32,
) -> Result[TrackRender, String] {
  match octaves {
    None => {
      let r = render(track.scene)
      match convolve(r, track.dry) {
        Err(e) => Err(e)
        Ok(wet) =>
          Ok({ wet, contributing: r.contributing, late: r.late, zero: r.zero, })
      }
    }
    Some(p) => {
      let r = match
        spectral_rir(
          track.scene,
          p.band_absorption,
          air_db_per_m=p.air_db_per_m,
          filter_half_width=half_width,
        ) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match r.audio.convolve(track.dry) {
        Err(e) => Err(e)
        Ok(wet) =>
          Ok({ wet, contributing: r.contributing, late: r.late, zero: r.zero, })
      }
    }
  }
}

///|
/// Render static sources in the same room and sum their fully convolved tracks.
/// All channels preserve the original receiver ordering, signed amplitudes and
/// the common kernel delay. This is an offline render with no clipping,
/// normalization, hidden sample-rate conversion or per-source alignment.
pub fn mix_recordings(
  tracks : Array[RecordingTrack],
  octaves~ : RecordingOctaves? = None,
) -> Result[RecordingMix, String] {
  let sizes = match preflight_mix(tracks, octaves) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let shared = tracks[0].scene
  let samples = Array::makei(shared.receivers.length(), fn(_) {
    Array::make(sizes.frames, 0.0)
  })
  let reports : Array[RecordingTrackReport] = []
  for i in 0..<tracks.length() {
    let track = tracks[i]
    let rendered = match
      render_recording_track(track, octaves, sizes.filter_half_width) {
      Err(e) => return Err("recording track \{i + 1}: " + e)
      Ok(v) => v
    }
    let frames = rendered.wet.frames()
    for ch in 0..<samples.length() {
      let target = samples[ch]
      let source = rendered.wet.samples[ch]
      for frame in 0..<frames {
        let dst = track.start_frame + frame
        target[dst] = target[dst] + track.gain * source[frame]
      }
    }
    reports.push({
      start_frame: track.start_frame,
      gain: track.gain,
      dry_frames: track.dry.length(),
      rir_frames: sizes.rir_frames,
      wet_frames: frames,
      end_frame: track.start_frame + frames,
      latency_samples: sizes.latency,
      contributing_paths: rendered.contributing,
      omitted_late_paths: rendered.late,
      zero_gain_paths: rendered.zero,
    })
  }
  Ok({
    audio: {
      samples,
      sample_rate: shared.sample_rate,
      latency_samples: sizes.latency,
    },
    tracks: reports,
  })
}
