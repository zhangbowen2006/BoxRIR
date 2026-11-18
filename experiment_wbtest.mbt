///|
test "probe preserves its explicit lead and tail and repeatable noise" {
  let impulse = generate_probe({
    sample_rate: 48000,
    active_frames: 1,
    lead_frames: 2,
    tail_frames: 2,
    fade_frames: 0,
    amplitude: 0.5,
    excitation: Impulse,
  }).unwrap()
  assert_eq(impulse.channel(0).unwrap(), [0.0, 0.0, 0.5, 0.0, 0.0])
  let noise : ProbeSpec = {
    sample_rate: 16000,
    active_frames: 512,
    lead_frames: 1,
    tail_frames: 1,
    fade_frames: 8,
    amplitude: 0.25,
    excitation: WhiteNoise(4294967295U),
  }
  let first = generate_probe(noise).unwrap().channel(0).unwrap()
  assert_eq(first, generate_probe(noise).unwrap().channel(0).unwrap())
  assert_true(
    first !=
    generate_probe({ ..noise, excitation: WhiteNoise(5U), })
    .unwrap()
    .channel(0)
    .unwrap(),
  )
  assert_eq(first[1], 0.0)
  assert_eq(first[512], 0.0)
  assert_true(
    generate_probe({ ..noise, excitation: WhiteNoise(0U), }) is Err(_),
  )
  assert_true(generate_probe({ ..noise, tail_frames: 2147483647, }) is Err(_))
  assert_eq(default_probe(44100).unwrap().frames(), 44100)
}

///|
test "energy windows use explicit onset and put the split frame in late energy" {
  let samples = Array::make(1000, 0.0)
  samples[16] = 2.0
  samples[16 + 400] = 1.0
  samples[16 + 720] = -1.0
  let row = analyze_decay([samples], 8000, onset_frames=[16], curve_points=5).unwrap().channels[0]
  assert_eq(row.onset_frame, Some(16))
  assert_eq(row.power_sum, 6.0)
  assert_true((row.d50.unwrap() - 2.0 / 3.0).abs() < 1.0e-12)
  assert_true((row.c50_db.unwrap() - 3.010299956639812).abs() < 1.0e-10)
  assert_true((row.c80_db.unwrap() - 6.989700043360188).abs() < 1.0e-10)
  assert_true((row.center_time_ms.unwrap() - 23.3333333333333).abs() < 1.0e-10)
  assert_eq(row.t30.seconds_for_60db, None)
  let short = analyze_decay([samples], 8000, end_exclusive=Some(100)).unwrap().channels[0]
  assert_eq(short.c50_db, None)
  assert_eq(short.d50, None)
}

///|
test "a known exponential decay gives the expected extrapolated times" {
  let rate = 16000
  let expected = 0.42
  let samples = Array::makei(24000, i => {
    @math.exp(-@math.ln(1000.0) * i.to_double() / (expected * rate.to_double()))
  })
  let row = analyze_decay([samples], rate, onset_frames=[0], curve_points=16).unwrap().channels[0]
  for fit in [row.edt, row.t20, row.t30] {
    assert_eq(fit.status, "estimated")
    assert_true((fit.seconds_for_60db.unwrap() - expected).abs() < 1.0e-8)
    assert_true(fit.r_squared.unwrap() > 0.9999)
  }
  assert_eq(row.curve.length(), 16)
  let silent = analyze_decay([Array::make(500, 0.0)], rate).unwrap().channels[0]
  assert_eq(silent.onset_frame, None)
  assert_eq(silent.t20.status, "no_energy")
  assert_true(analyze_decay([samples], rate, onset_frames=[24000]) is Err(_))
}

///|
test "recover a known delayed multichannel impulse from linear convolution" {
  let probe = [0.8, 0.2, -0.1]
  let known = [[0.0, 0.0, 0.5, 0.2, 0.0, -0.1], [0.0, -0.3, 0.0, 0.1, 0.0, 0.0]]
  let measured = known.map(fn(channel) {
    let recording = Array::make(channel.length() + probe.length() - 1, 0.0)
    for i, x in probe {
      for j, h in channel {
        recording[i + j] += x * h
      }
    }
    recording
  })
  let estimate = estimate_transfer(
    probe,
    measured,
    16000,
    6,
    regularization_db=-120.0,
  ).unwrap()
  assert_eq(estimate.audio.channel_count(), 2)
  for channel, expected in known {
    let actual = estimate.audio.channel(channel).unwrap()
    for i, value in expected {
      assert_true((actual[i] - value).abs() < 1.0e-10)
    }
    assert_true(
      estimate.channels[channel].reconstruction_error_fraction.unwrap() <
      1.0e-18,
    )
  }
  assert_true(estimate_transfer([0.0], measured, 16000, 6) is Err(_))
  assert_true(estimate_transfer(probe, measured, 16000, 7) is Err(_))
}

///|
test "comparison distinguishes raw amplitude error from explicit time and gain fit" {
  let r = [[0.5, 0.0, -0.25, 0.1, 0.0, 0.0]]
  let o = [[0.0, 0.0, -1.0, 0.0, 0.5, -0.2, 0.0, 0.0]]
  let result = compare_responses(r, o, 16000, frames=Some(6), lag_radius=2).unwrap().channels[0]
  assert_eq(result.observed_lag_frames, 2)
  assert_eq(result.observed_start, 2)
  assert_eq(result.signed_correlation, Some(-1.0))
  assert_eq(result.reference_to_observed_gain, Some(-2.0))
  assert_true((result.raw_error_ratio.unwrap() - 1.5).abs() < 1.0e-12)
  assert_true(result.adjusted_error_ratio.unwrap() < 1.0e-7)
  assert_true(compare_responses(r, o, 16000, lag_radius=1) is Err(_))
  let absent = compare_responses([[0.0]], [[1.0e-280]], 16000).unwrap().channels[0]
  assert_eq(absent.status, "reference_silent")
  assert_eq(absent.raw_error_ratio, Some(1.0))
}

///|
test "48k to 16k resample preserves passband and suppresses an aliased tone" {
  let fs = 48000
  let low = Array::makei(4800, i => {
    @math.sin(2.0 * PI * 1000.0 * i.to_double() / fs.to_double())
  })
  let high = Array::makei(4800, i => {
    @math.sin(2.0 * PI * 12000.0 * i.to_double() / fs.to_double())
  })
  let result = resample_audio([low, high], fs, 16000).unwrap()
  assert_eq(result.audio.frames(), 1600)
  assert_eq(result.audio.latency_samples, 0)
  let low_out = result.audio.channel(0).unwrap()
  let high_out = result.audio.channel(1).unwrap()
  for i in 100..<1500 {
    assert_true((low_out[i] - low[i * 3]).abs() < 0.0005)
    assert_true(high_out[i].abs() < 0.0005)
  }
  let dc = resample_audio([[0.5, 0.5, 0.5]], 16000, 44100).unwrap()
  assert_eq(dc.audio.frames(), 9)
  for sample in dc.audio.channel(0).unwrap() {
    assert_true((sample - 0.5).abs() < 1.0e-12)
  }
  assert_true(resample_audio([Array::make(24000, 0.0)], 8000, 96000) is Err(_))
}
