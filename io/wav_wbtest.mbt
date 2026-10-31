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
