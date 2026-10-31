///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  let s = @lib.scene(
    { x: 5.0, y: 4.0, z: 3.0, },
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 1.0, z: 1.0, }],
    [0.2, 0.2, 0.2, 0.2, 0.2, 0.2],
    16000,
    1,
    100,
  ).unwrap()
  let paths = @lib.trace(s)
  let r = @lib.render(s)
  if paths.length() != 7 || r.channel(0).unwrap().length() != 1632 {
    panic()
  }
  println("7 paths; 1632 response frames; common latency 16 samples")
  println(
    "Direct arrival: \{paths[0].delay_samples} samples; gain: \{paths[0].gain}",
  )
}
