///|
test "microphone patterns retain signed rear lobes and elevation" {
  let patterns = [
    ("o", 1.0, 1.0),
    ("b", 0.0, -1.0),
    ("c", 0.5, 0.0),
    ("s", 0.75, 0.5),
    ("h", 0.25, -0.5),
  ]
  for pair in patterns {
    let (name, rho, rear) = pair
    assert_true(microphone_pattern(name) is Some(_))
    assert_true(
      (directional_gain(1.0, 0.0, 0.0, [0.0, 0.0], rho) - 1.0).abs() < 1.0e-12,
    )
    assert_true(
      (directional_gain(-1.0, 0.0, 0.0, [0.0, 0.0], rho) - rear).abs() < 1.0e-12,
    )
    assert_true(
      (directional_gain(0.0, 0.0, 1.0, [0.0, PI / 2.0], rho) - 1.0).abs() <
      1.0e-12,
    )
  }
}

///|
test "reference profile separates pressure reflection and energy absorption" {
  let beta = [-0.9, 0.8, 0.7, 0.6, 0.5, 0.4]
  let r = audiolabs_rir(
    { x: 6.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 2.0, z: 1.5, }],
    8000,
    beta=Some(beta),
    nsample=Some(512),
    order=1,
    dimension=2,
  ).unwrap()
  assert_eq(beta[4], 0.5)
  assert_eq(r.beta[4], 0.0)
  assert_true(r.paths.any(fn(p) { p.reflection < 0.0 }))
  assert_eq(r.audio.latency_samples, 0)
  assert_eq(r.audio.frames(), 512)
  assert_eq(r.kernel_frames, 64)
}

///|
test "reference defaults and invalid parameter combinations are explicit" {
  let room = { x: 6.0, y: 4.0, z: 3.0, }
  let source = { x: 1.0, y: 1.0, z: 1.0, }
  let receivers = [{ x: 3.0, y: 2.0, z: 1.5, }]
  assert_true(audiolabs_rir(room, source, receivers, 8000) is Err(_))
  assert_true(
    audiolabs_rir(
      room,
      source,
      receivers,
      8000,
      beta=Some(Array::make(6, 0.5)),
      reverberation_time=Some(0.3),
    )
    is Err(_),
  )
  assert_true(
    audiolabs_rir(room, source, receivers, 8000, beta=Some(Array::make(6, 1.0)))
    is Err(_),
  )
  assert_true(
    audiolabs_rir(room, source, receivers, 8000, reverberation_time=Some(0.001))
    is Err(_),
  )
  let r = audiolabs_rir(
    room,
    source,
    receivers,
    8000,
    reverberation_time=Some(0.2),
    order=0,
  ).unwrap()
  assert_eq(r.audio.frames(), 1600)
  assert_true(r.high_pass)
}

///|
test "reference rejects unbounded work before numerical rendering" {
  let result = audiolabs_rir(
    { x: 0.1, y: 0.1, z: 0.1, },
    { x: 0.02, y: 0.02, z: 0.02, },
    [{ x: 0.07, y: 0.07, z: 0.07, }],
    8000,
    beta=Some(Array::make(6, 0.9)),
    nsample=Some(192000),
  )
  assert_true(result is Err(_))
}

///|
test "reference RIR convolution retains its exact window and complete tail" {
  let response = audiolabs_rir(
    { x: 4.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 1.02, y: 1.0, z: 1.0, }],
    8000,
    beta=Some(Array::make(6, 0.0)),
    nsample=Some(32),
    high_pass=false,
  ).unwrap()
  let h = response.audio.channel(0).unwrap()
  let output = response.audio.convolve([1.0, 0.0, -1.0]).unwrap()
  assert_eq(output.frames(), 34)
  assert_eq(output.latency_samples, 0)
  let values = output.channel(0).unwrap()
  for i in 0..<34 {
    let expected = (if i < 32 { h[i] } else { 0.0 }) -
      (if i >= 2 { h[i - 2] } else { 0.0 })
    assert_true((values[i] - expected).abs() < 1.0e-9)
  }
}
