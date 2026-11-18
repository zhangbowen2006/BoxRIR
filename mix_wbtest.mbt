///|
fn dry_mix_test_scene(source_x : Double, rate~ : Int32 = 8000) -> Scene {
  scene(
    { x: 8.0, y: 4.0, z: 3.0, },
    { x: source_x, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 1.0, z: 1.0, }, { x: 4.0, y: 1.0, z: 1.0, }],
    Array::make(6, 0.0),
    rate,
    0,
    10,
    speed=400.0,
  ).unwrap()
}

///|
test "recording matches standalone convolution for a single unchanged track" {
  let s = dry_mix_test_scene(2.0)
  let dry = [0.3, -0.2, 0.0, 0.7, -0.1]
  let ordinary = convolve(render(s), dry).unwrap()
  let mix = mix_recordings([
    { scene: s, dry, sample_rate: 8000, start_frame: 0, gain: 1.0, },
  ]).unwrap()
  assert_eq(mix.audio.frames(), ordinary.frames())
  assert_eq(mix.audio.latency_samples, 16)
  for ch in 0..<2 {
    let a = mix.audio.channel(ch).unwrap()
    let b = ordinary.channel(ch).unwrap()
    for i in 0..<a.length() {
      assert_true((a[i] - b[i]).abs() < 1.0e-14)
    }
  }
}

///|
test "recording shifted direct-path impulses match an independent timeline" {
  let a = dry_mix_test_scene(2.0)
  let b = dry_mix_test_scene(1.0)
  let first = [1.0, -0.25, 0.2]
  let second = [1.0, -2.0, 1.0]
  let mix = mix_recordings([
    { scene: a, dry: first, sample_rate: 8000, start_frame: 31, gain: 2.0, },
    { scene: b, dry: second, sample_rate: 8000, start_frame: 13, gain: -0.5, },
  ]).unwrap()
  // 8 kHz at 400 m/s yields exactly 20 frames per metre. Receivers are one
  // metre apart. Positive and negative tracks overlap for one sample.
  assert_eq(mix.audio.frames(), 145)
  assert_eq(mix.tracks[0].end_frame, 145)
  assert_eq(mix.tracks[1].end_frame, 127)
  for ch in 0..<2 {
    let expected = Array::make(145, 0.0)
    for i in 0..<3 {
      let index_a = 31 + 16 + 20 * (1 + ch) + i
      let index_b = 13 + 16 + 20 * (2 + ch) + i
      expected[index_a] = expected[index_a] +
        first[i] * 2.0 / (4.0 * PI * (1 + ch).to_double())
      expected[index_b] = expected[index_b] -
        second[i] * 0.5 / (4.0 * PI * (2 + ch).to_double())
    }
    let actual = mix.audio.channel(ch).unwrap()
    for i in 0..<actual.length() {
      assert_true((actual[i] - expected[i]).abs() < 1.0e-12)
    }
  }
}

///|
test "recording validates geometry, WAV rate and preflight resource limits" {
  let s = dry_mix_test_scene(2.0)
  let t : RecordingTrack = {
    scene: s,
    dry: [1.0],
    sample_rate: 8000,
    start_frame: 7,
    gain: 1.0,
  }
  assert_true(mix_recordings([]) is Err(_))
  assert_true(mix_recordings(Array::make(5, t)) is Err(_))
  assert_true(mix_recordings([{ ..t, sample_rate: 16000, }]) is Err(_))
  assert_true(mix_recordings([{ ..t, dry: [], }]) is Err(_))
  assert_true(mix_recordings([{ ..t, start_frame: 2147483647, }]) is Err(_))
  assert_true(mix_recordings([{ ..t, gain: 101.0, }]) is Err(_))
  assert_true(
    mix_recordings([t, { ..t, scene: { ..s, half_width: 8, }, }]) is Err(_),
  )
  assert_true(
    mix_recordings([
      t,
      { ..t, scene: { ..s, receivers: [s.receivers[1], s.receivers[0]], }, },
    ])
    is Err(_),
  )
  let large = { ..t, dry: Array::make(131073, 0.0), }
  assert_true(mix_recordings([large, large]) is Err(_))
  let cancelled = mix_recordings([
    t,
    { ..t, gain: -1.0, },
    { ..t, gain: 0.0, start_frame: 100, },
  ]).unwrap()
  assert_true(cancelled.audio.channel(0).unwrap().all(fn(v) { v == 0.0 }))
  assert_eq(cancelled.audio.frames(), 100 + s.output_frames())
}

///|
test "octave recording retains common filter latency and full shifted tails" {
  let s = dry_mix_test_scene(2.0, rate=16000)
  let materials = Array::makei(6, fn(_) { Array::make(6, 0.2) })
  let losses = [0.0, 0.0, 0.01, 0.02, 0.04, 0.08]
  let profile : RecordingOctaves = {
    band_absorption: materials,
    air_db_per_m: losses,
    filter_half_width: 0,
  }
  let dry = [1.0, -0.5]
  let track : RecordingTrack = {
    scene: s,
    dry,
    sample_rate: 16000,
    start_frame: 19,
    gain: 0.25,
  }
  let expected = spectral_rir(s, materials, air_db_per_m=losses).unwrap().audio
    .convolve(dry)
    .unwrap()
  let mixed = mix_recordings([track], octaves=Some(profile)).unwrap()
  assert_eq(mixed.audio.latency_samples, 272)
  assert_eq(mixed.audio.frames(), expected.frames() + 19)
  assert_eq(mixed.tracks[0].rir_frames, expected.frames() - 1)
  for ch in 0..<2 {
    let a = mixed.audio.channel(ch).unwrap()
    let b = expected.channel(ch).unwrap()
    assert_true(a[:19].iter().all(fn(v) { v == 0.0 }))
    for i in 0..<b.length() {
      assert_true((a[i + 19] - b[i] * 0.25).abs() < 1.0e-12)
    }
  }
  let invalid = { ..profile, band_absorption: [], }
  assert_true(mix_recordings([track], octaves=Some(invalid)) is Err(_))
}
