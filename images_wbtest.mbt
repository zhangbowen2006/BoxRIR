///|
test "image counts use total reflection order" {
  let expected = [1, 7, 25, 63, 129]
  for order = 0; order <= 4; order = order + 1 {
    let im = images(base_scene(order))
    assert_eq(im.length(), expected[order])
    assert_eq(im[0].order, 0)
    assert_eq(im[0].reflection, 1.0)
    for p in im {
      assert_eq(p.order, p.bounces.fold(init=0, fn(a, b) { a + b }))
      assert_true(p.order <= order)
    }
  }
}

///|
test "six asymmetric walls map to the correct first reflections" {
  let s = base_scene(1)
  let expected = [
    { x: -1.0, y: 1.0, z: 1.0, },
    { x: 9.0, y: 1.0, z: 1.0, },
    { x: 1.0, y: -1.0, z: 1.0, },
    { x: 1.0, y: 7.0, z: 1.0, },
    { x: 1.0, y: 1.0, z: -1.0, },
    { x: 1.0, y: 1.0, z: 5.0, },
  ]
  let seen = Array::make(6, false)
  for im in images(s) {
    if im.order == 1 {
      for i = 0; i < 6; i = i + 1 {
        if im.bounces[i] == 1 {
          seen[i] = true
          assert_eq(im.image.x, expected[i].x)
          assert_eq(im.image.y, expected[i].y)
          assert_eq(im.image.z, expected[i].z)
          assert_true(
            (im.reflection - (1.0 - s.absorption[i]).sqrt()).abs() < 1.0e-12,
          )
        }
      }
    }
  }
  assert_true(seen.all(fn(v) { v }))
  let dead = scene(
    s.room,
    s.source,
    s.receivers,
    [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    16000,
    2,
    200,
  ).unwrap()
  for im in images(dead) {
    assert_eq(im.reflection, if im.order == 0 { 1.0 } else { 0.0 })
  }
}
