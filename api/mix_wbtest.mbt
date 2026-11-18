///|
fn simple_mix_request() -> String {
  "{\"version\":1,\"scene\":{\"room\":[6,4,3],\"receivers\":[[3,1,1]],\"absorption\":[0,0,0,0,0,0],\"sample_rate\":8000,\"max_order\":0,\"duration_ms\":10,\"speed\":400},\"tracks\":[{\"id\":\"one\",\"source\":[2,1,1],\"start_frame\":3,\"gain\":2}]}"
}

///|
test "mix JSON WAV endpoint respects ordered inputs, offsets and original amplitudes" {
  let input = @audio.write_float32([[1.0, -0.5]], 8000).unwrap()
  let raw = @json.parse(mix_base64_json(simple_mix_request(), [input]))
  guard raw is Object(result) else { fail("expected recording result object") }
  assert_eq(result.get("ok"), Some(Json(true)))
  guard result.get("report") is Some(Object(report)) else {
    fail("recording report missing")
  }
  let frames : Int32 = @json.from_json(report.get("frames").unwrap())
  assert_eq(frames, 116)
  let encoded : String = @json.from_json(result.get("wet_wav").unwrap())
  let wet = @audio.read_mono(@base64.decode(encoded)).unwrap()
  assert_eq(wet.sample_rate, 8000)
  assert_eq(wet.samples.length(), frames)
  assert_true((wet.samples[39] - 0.15915494309189535).abs() < 1.0e-8)
  assert_true((wet.samples[40] + 0.07957747154594767).abs() < 1.0e-8)
}

///|
test "mix JSON rejects inconsistent tracks, invalid schema and unsupported model" {
  let req = simple_mix_request()
  let valid = @audio.write_float32([[1.0]], 8000).unwrap()
  let wrong_rate = @audio.write_float32([[1.0]], 16000).unwrap()
  assert_true(
    mix_base64_json(req, [wrong_rate]).contains("sample rate does not match"),
  )
  assert_true(mix_base64_json(req, []).contains("one WAV per track"))
  assert_true(
    mix_base64_json(req, [Bytes::new(0)]).contains("each recording WAV"),
  )
  let decimal = req.replace(old="\"start_frame\":3", new="\"start_frame\":3.0")
  assert_true(
    mix_base64_json(decimal, [valid]).contains("integer literal required"),
  )
  let unsupported = req.replace(
    old="\"room\":",
    new="\"model\":\"audiolabs_v030\",\"room\":",
  )
  assert_true(
    mix_base64_json(unsupported, [valid]).contains(
      "supports ordinary or octave_bands",
    ),
  )
  let stale = req.replace(old="\"room\":", new="\"source\":[2,1,1],\"room\":")
  assert_true(mix_base64_json(stale, [valid]).contains("belongs in each track"))
  let repeated = req.replace(
    old="\"version\":1",
    new="\"version\":1,\"version\":1",
  )
  assert_true(
    mix_base64_json(repeated, [valid]).contains("invalid recording JSON"),
  )
}

///|
test "mix JSON octave prism matches a shifted and scaled standalone render" {
  let common = "\"model\":\"octave_bands\",\"footprint\":[[0,0],[6,0],[0,4]],\"height\":3,\"receivers\":[[2,1,1]],\"sample_rate\":16000,\"max_order\":1,\"duration_ms\":10,\"speed\":400,\"band_absorption\":[[0.1,0.2,0.3,0.4,0.5,0.6],[0.2,0.2,0.2,0.2,0.2,0.2],[0,0,0,0,0,0],[0,0,0,0,0,0],[0,0,0,0,0,0]]"
  let shared = "{" + common + "}"
  let single = "{" + common + ",\"source\":[1,1,1]}"
  let recording = "{\"version\":1,\"scene\":" +
    shared +
    ",\"tracks\":[{\"id\":\"voice\",\"source\":[1,1,1],\"start_frame\":4,\"gain\":0.5}]}"
  let source = @audio.write_float32([[1.0, 0.2, -0.3]], 16000).unwrap()
  let actual = @json.parse(mix_base64_json(recording, [source]))
  let expected = @json.parse(generate_base64_json(single, source))
  guard actual is Object(mix) && expected is Object(solo) else {
    fail("expected recording and standalone result objects")
  }
  assert_eq(mix.get("ok"), Some(Json(true)))
  assert_eq(solo.get("ok"), Some(Json(true)))
  let mix64 : String = @json.from_json(mix.get("wet_wav").unwrap())
  let solo64 : String = @json.from_json(solo.get("wet_wav").unwrap())
  let a = @audio.read_mono(@base64.decode(mix64)).unwrap().samples
  let b = @audio.read_mono(@base64.decode(solo64)).unwrap().samples
  assert_eq(a.length(), b.length() + 4)
  assert_true(a[:4].iter().all(fn(v) { v == 0.0 }))
  for i in 0..<b.length() {
    assert_true((a[i + 4] - 0.5 * b[i]).abs() < 1.0e-10)
  }
}
