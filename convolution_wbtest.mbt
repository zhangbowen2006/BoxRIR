///|
test "FFT output equals independent linear convolution and preserves full tail" {
  let s = scene(
    { x: 1.0, y: 1.0, z: 1.0, },
    { x: 0.1, y: 0.5, z: 0.5, },
    [{ x: 0.2, y: 0.5, z: 0.5, }],
    [0.2, 0.2, 0.2, 0.2, 0.2, 0.2],
    8000,
    2,
    5,
  ).unwrap()
  let r = render(s)
  let h = r.channel(0).unwrap()
  let dry = [0.3, -0.2, 0.0, 0.7, -0.1]
  let actual = convolve(r, dry).unwrap()
  let expected = Array::make(dry.length() + h.length() - 1, 0.0)
  for i = 0; i < dry.length(); i = i + 1 {
    for j = 0; j < h.length(); j = j + 1 {
      expected[i + j] = expected[i + j] + dry[i] * h[j]
    }
  }
  let a = actual.channel(0).unwrap()
  assert_eq(actual.frames(), expected.length())
  assert_eq(actual.latency_samples, 16)
  for i = 0; i < a.length(); i = i + 1 {
    assert_true((a[i] - expected[i]).abs() < 1.0e-10)
  }
  let impulse = convolve(r, [1.0]).unwrap().channel(0).unwrap()
  for i = 0; i < h.length(); i = i + 1 {
    assert_true((impulse[i] - h[i]).abs() < 1.0e-10)
  }
  assert_true(convolve(r, []) is Err(_))
  assert_true(convolve(r, [1.0e7]) is Err(_))
  assert_true(convolve(r, Array::make(262144, 0.0)) is Err(_))
}

///|
test "shared source FFT preserves all receiver channels and signed tails" {
  let responses = [
    [0.0, 0.5, -0.25, 0.1, 0.0],
    [-0.3, 0.0, 0.2, 0.0, -0.4],
    [0.0, 0.0, 0.0, 0.0, 0.7],
  ]
  let dry = Array::makei(131, fn(i) {
    @math.sin(i.to_double() * 0.19) - 0.3 * @math.cos(i.to_double() * 0.7)
  })
  let actual = convolve_channels(responses, 16000, 0, dry).unwrap()
  assert_eq(actual.frames(), 135)
  for channel in 0..<responses.length() {
    let expected = Array::make(135, 0.0)
    for i in 0..<dry.length() {
      for j in 0..<responses[channel].length() {
        expected[i + j] = expected[i + j] + dry[i] * responses[channel][j]
      }
    }
    let samples = actual.channel(channel).unwrap()
    for i in 0..<expected.length() {
      assert_true((samples[i] - expected[i]).abs() < 1.0e-10)
    }
  }
}
