///|
fn base_scene(order : Int32) -> Scene {
  scene(
    { x: 5.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 2.0, z: 1.5, }],
    [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
    16000,
    order,
    200,
  ).unwrap()
}

///|
test "scene limits and immutable input arrays" {
  let s = base_scene(2)
  assert_eq(s.physical_frames(), 3200)
  assert_eq(s.output_frames(), 3232)
  assert_eq(s.latency_samples(), 16)
  let receivers = s.receiver_positions()
  receivers.clear()
  assert_eq(s.receiver_positions().length(), 1)
  assert_true(
    scene(s.room, s.source, [s.source], s.absorption, 16000, 2, 200) is Err(_),
  )
  assert_true(
    scene(s.room, s.source, s.receivers, [0.0, 0.0], 16000, 2, 200) is Err(_),
  )
  assert_true(
    scene(
      s.room,
      s.source,
      s.receivers,
      [0.0, 0.0, 0.0, 0.0, 0.0, 1.01],
      16000,
      2,
      200,
    )
    is Err(_),
  )
  assert_true(
    scene(s.room, s.source, s.receivers, s.absorption, 16000, 13, 200) is Err(_),
  )
  assert_true(
    scene(
      s.room,
      { x: 0.0, y: 1.0, z: 1.0, },
      s.receivers,
      s.absorption,
      16000,
      2,
      200,
    )
    is Err(_),
  )
}
