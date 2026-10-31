///|
test "scene JSON enforces shape, finite bounds and lexical integer controls" {
  let s = "{\"room\":[5,4,3],\"source\":[1,1,1],\"receivers\":[[3,2,1.5]],\"absorption\":[0.1,0.2,0.3,0.4,0.5,0.6],\"sample_rate\":16000,\"max_order\":2,\"duration_ms\":100}"
  assert_true(parse_scene(s) is Ok(_))
  assert_true(
    parse_scene(s.replace(old="16000", new="16000.00000000001")) is Err(_),
  )
  assert_true(parse_scene(s.replace(old="16000", new="1e300")) is Err(_))
  assert_true(parse_scene(s.replace(old="[5,4,3]", new="[5,4]")) is Err(_))
  assert_true(parse_scene(s.replace(old="\"room\"", new="\"rooms\"")) is Err(_))
  assert_true(describe_json(s).contains("\"images\""))
}
