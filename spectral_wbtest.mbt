///|
fn spectral_test_scene() -> Scene {
  scene(
    { x: 6.0, y: 4.0, z: 3.0, },
    { x: 1.3, y: 1.1, z: 1.2, },
    [{ x: 3.2, y: 2.2, z: 1.4, }],
    Array::make(6, 0.36),
    16000,
    2,
    60,
  ).unwrap()
}

///|
test "complementary filter bank reconstructs a delayed impulse exactly" {
  let filters = octave_filters(16000).unwrap()
  for i in 0..<513 {
    let sum = filters.fold(init=0.0, fn(a, b) { a + b[i] })
    let expected = if i == 256 { 1.0 } else { 0.0 }
    assert_true((sum - expected).abs() < 1.0e-15)
    for band in 0..<6 {
      assert_true((filters[band][i] - filters[band][512 - i]).abs() < 1.0e-12)
    }
  }
}

///|
test "flat band materials reduce to the original response with declared FIR latency and full tail" {
  let s = spectral_test_scene()
  let flat = spectral_rir(s, Array::makei(6, fn(_) { Array::make(6, 0.36) })).unwrap()
  let a = flat.audio.channel(0).unwrap()
  let b = render(s).channel(0).unwrap()
  assert_eq(a.length(), b.length() + 512)
  assert_eq(flat.audio.latency_samples, 272)
  for i in 0..<a.length() {
    let expected = if i >= 256 && i < 256 + b.length() {
      b[i - 256]
    } else {
      0.0
    }
    assert_true((a[i] - expected).abs() < 1.0e-11)
  }
}

///|
test "each reflection uses its own wall bands and distance-dependent pressure loss" {
  let s = spectral_test_scene()
  let materials = Array::makei(6, fn(_) { Array::make(6, 0.0) })
  materials[0] = [0.0, 0.19, 0.36, 0.51, 0.64, 0.75]
  let response = spectral_rir(s, materials, air_db_per_m=[
    0.0, 0.1, 0.2, 0.3, 0.4, 0.5,
  ]).unwrap()
  for p in response.paths {
    for band in 0..<6 {
      let expected = p.path.gain *
        power((1.0 - materials[0][band]).sqrt(), p.path.bounces[0]) *
        @math.pow(10.0, -band.to_double() * 0.1 * p.path.distance / 20.0)
      assert_true((p.band_gains[band] - expected).abs() < 1.0e-12)
    }
  }
  assert_true(spectral_rir(s, [[0.2]]) is Err(_))
  assert_true(spectral_rir(s, materials, air_db_per_m=[-1.0]) is Err(_))
  assert_true(octave_filters(8000) is Err(_))
}

///|
test "air equations retain percentage humidity units and pinned reference coefficients" {
  let expected = [
    0.00043978997709849435, 0.0013097497659238589, 0.002728134134938444, 0.004664731873821475,
    0.009887015588697921, 0.02966552842639262,
  ]
  let actual = atmospheric_air_loss(20.0, 50.0).unwrap()
  for band in 0..<6 {
    assert_true((actual[band] - expected[band]).abs() < 1.0e-14)
  }
  assert_true(atmospheric_air_loss(20.0, 0.5) is Err(_))
  assert_true(atmospheric_air_loss(51.0, 50.0) is Err(_))
  assert_true(atmospheric_air_loss(20.0, 50.0, pressure_kpa=0.0) is Err(_))
}

///|
test "spectral intermediate allocation is bounded before building six band buffers" {
  let s = scene(
    { x: 6.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    Array::make(8, { x: 2.0, y: 2.0, z: 1.0, }),
    Array::make(6, 0.2),
    96000,
    0,
    1000,
  ).unwrap()
  assert_true(
    spectral_rir(s, Array::makei(6, fn(_) { Array::make(6, 0.2) })) is Err(_),
  )
}

///|
test "octave centres retain their own material band at high sample rates" {
  let centers = octave_centers()
  for rate in [16000, 44100, 96000] {
    let filters = octave_filters(rate).unwrap()
    let half = (filters[0].length() - 1) / 2
    for frequency_band in 0..<6 {
      for filter_band in 0..<6 {
        let mut amplitude = 0.0
        for i in 0..<filters[filter_band].length() {
          amplitude = amplitude +
            filters[filter_band][i] *
            @math.cos(
              2.0 *
              PI *
              centers[frequency_band] *
              (i - half).to_double() /
              rate.to_double(),
            )
        }
        let expected = if filter_band == frequency_band { 1.0 } else { 0.0 }
        assert_true((amplitude - expected).abs() < 0.02)
      }
    }
  }
  assert_true(octave_filters(96000, half_width=256) is Err(_))
}
