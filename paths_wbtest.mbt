///|
test "direct paths preserve receiver delay and spreading differences" {
  let s = scene(
    { x: 5.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 1.0, z: 1.0, }, { x: 4.0, y: 1.0, z: 1.0, }],
    [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    16000,
    1,
    200,
    speed=320.0,
  ).unwrap()
  let paths = trace(s)
  assert_eq(paths.length(), 14)
  let direct = paths.filter(fn(p) { p.order == 0 })
  assert_eq(direct[0].delay_samples, 100.0)
  assert_eq(direct[1].delay_samples, 150.0)
  assert_true((direct[0].gain / direct[1].gain - 1.5).abs() < 1.0e-12)
  for p in paths {
    if p.order > 0 {
      assert_eq(p.gain, 0.0)
    }
  }
}

///|
test "equal arrival paths remain separate contributions" {
  let s = scene(
    { x: 4.0, y: 4.0, z: 3.0, },
    { x: 2.0, y: 2.0, z: 1.0, },
    [{ x: 2.0, y: 2.0, z: 2.0, }],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    16000,
    1,
    200,
  ).unwrap()
  let p = trace(s).filter(fn(p) { p.order == 1 && p.distance > 4.0 })
  assert_eq(p.length(), 4)
  for path in p {
    assert_true((path.distance - 17.0.sqrt()).abs() < 1.0e-12)
  }
}
