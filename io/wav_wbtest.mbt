///|
test "float WAV preserves amplitude and rejects nonfinite data" {
  let bytes = write_float32([[0.0, 2.5, -3.0, 0.125]], 16000).unwrap()
  assert_eq(bytes.length(), 74)
  let decoded = read_mono(bytes)
  let read = decoded.unwrap()
  assert_eq(read.sample_rate, 16000)
  assert_eq(read.samples, [0.0, 2.5, -3.0, 0.125])
  let bad = bytes.to_array()
  bad[58] = 0
  bad[59] = 0
  bad[60] = 128
  bad[61] = 127
  assert_true(read_mono(Bytes::from_array(bad)) is Err(_))
  assert_true(
    read_mono(write_float32([[0.0], [1.0]], 16000).unwrap()) is Err(_),
  )
  assert_true(write_float32([[0.0], [0.0, 1.0]], 16000) is Err(_))
}

///|
test "RIFF framing rejects out-of-bounds lengths before decoding metadata" {
  let valid = write_float32([[0.25, -0.5]], 16000).unwrap()
  let bad = valid.to_array()
  // fmt chunk claims more bytes than remain; no codec call should occur.
  bad[16] = 255
  bad[17] = 255
  bad[18] = 255
  bad[19] = 255
  assert_true(read_mono(Bytes::from_array(bad)) is Err(_))
  let truncated = valid[:valid.length() - 1].to_owned()
  assert_true(read_mono(truncated) is Err(_))
  // An opaque metadata chunk is bounded and skipped, even if its bytes are not
  // meaningful metadata. It must not change the audio samples.
  let extra = valid.to_array()
  for v in [99, 117, 101, 32, 4, 0, 0, 0, 255, 255, 255, 255] {
    extra.push(v.to_byte())
  }
  for i = 0; i < 4; i = i + 1 {
    extra[4 + i] = (((extra.length() - 8) >> (8 * i)) & 255).to_byte()
  }
  assert_eq(read_mono(Bytes::from_array(extra)).unwrap().samples, [0.25, -0.5])
}
