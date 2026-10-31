///|
test "fractional kernels preserve gain and integer placement" {
  for f in [0.0, 0.125, 0.5, 0.999999] {
    let taps = delay_taps(f, 16)
    assert_true((taps.fold(init=0.0, fn(a, b) { a + b }) - 1.0).abs() < 1.0e-12)
  }
  let s = scene(
    { x: 5.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 1.0, z: 1.0, }],
    [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    16000,
    4,
    100,
    speed=320.0,
  ).unwrap()
  let response = render(s)
  let channel = response.channel(0).unwrap()
  assert_eq(channel.length(), 1632)
  assert_true((channel[116] - 1.0 / (8.0 * PI)).abs() < 1.0e-12)
  for i = 0; i < channel.length(); i = i + 1 {
    if i != 116 {
      assert_eq(channel[i], 0.0)
    }
  }
  assert_eq(response.contributing_paths(), [1])
  assert_eq(response.zero_gain_paths(), [128])
}

///|
test "window omission is explicit and complete retained kernels preserve summed gain" {
  let s = base_scene(3)
  let expected = trace(s)
    .filter(fn(p) { p.delay_samples < s.frames.to_double() })
    .fold(init=0.0, fn(sum, p) { sum + p.gain })
  assert_true(
    (render(s).channel(0).unwrap().fold(init=0.0, fn(a, b) { a + b }) - expected).abs() <
    1.0e-10,
  )
  let far = scene(
    { x: 100.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 99.0, y: 1.0, z: 1.0, }],
    [0.2, 0.2, 0.2, 0.2, 0.2, 0.2],
    8000,
    1,
    1,
  ).unwrap()
  let r = render(far)
  assert_eq(r.omitted_late_paths(), [7])
  assert_true(r.channel(0).unwrap().all(fn(x) { x == 0.0 }))
}

///|
test "reciprocity and common receiver timing survive asymmetric walls" {
  let s = base_scene(4)
  let inverse = scene(
    s.room,
    s.receivers[0],
    [s.source],
    s.absorption,
    s.sample_rate,
    s.max_order,
    200,
  ).unwrap()
  let a = render(s).channel(0).unwrap()
  let b = render(inverse).channel(0).unwrap()
  for i = 0; i < a.length(); i = i + 1 {
    assert_true((a[i] - b[i]).abs() < 1.0e-11)
  }
  let array = scene(
    s.room,
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 1.0, z: 1.0, }, { x: 4.0, y: 1.0, z: 1.0, }],
    [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    16000,
    0,
    200,
    speed=320.0,
  ).unwrap()
  let r = render(array)
  assert_true(r.channel(0).unwrap()[116] > 0.0)
  assert_true(r.channel(1).unwrap()[166] > 0.0)
  assert_eq(r.settings().latency_samples(), 16)
}
