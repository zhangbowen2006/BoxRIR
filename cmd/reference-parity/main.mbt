///|
struct FixtureCase {
  name : String
  scene : Json
  channels : Int32
  frames : Int32
  float64_le : String
} derive(FromJson)

///|
struct Fixtures {
  cases : Array[FixtureCase]
} derive(FromJson)

///|
struct Samples {
  ok : Bool
  channels : Array[Array[Double]]
} derive(FromJson)

///|
fn main {
  let text = reference_fixture_text
  let fixtures : Fixtures = @json.from_json(@json.parse(text)) catch {
    _ => abort("invalid fixture schema")
  }
  let mut maximum_error = 0.0
  let mut samples = 0
  for c in fixtures.cases {
    let response = @api.reference_samples_json(c.scene.stringify())
    let actual : Samples = @json.from_json(@json.parse(response)) catch {
      _ => abort(c.name + ": " + response)
    }
    if !actual.ok || actual.channels.length() != c.channels {
      abort(c.name + ": wrong channel count")
    }
    let raw = @base64.decode(c.float64_le) catch {
      _ => abort("invalid base64 fixture")
    }
    if raw.length() != c.channels * c.frames * 8 {
      abort("invalid fixture byte count")
    }
    for channel in 0..<c.channels {
      if actual.channels[channel].length() != c.frames {
        abort(c.name + ": wrong frame count")
      }
      for frame in 0..<c.frames {
        let offset = (channel * c.frames + frame) * 8
        let mut bits = 0L
        for b in 0..<8 {
          bits = bits | (raw[offset + b].to_int().to_int64() << (8 * b))
        }
        let expected = bits.reinterpret_as_double()
        let error = (expected - actual.channels[channel][frame]).abs()
        if !(error <= 1.0e-10 + 1.0e-9 * expected.abs()) {
          abort(c.name + ": waveform mismatch at " + frame.to_string())
        }
        maximum_error = if error > maximum_error {
          error
        } else {
          maximum_error
        }
        samples = samples + 1
      }
    }
  }
  println(
    (
      {
        "cases": Json(fixtures.cases.length()),
        "samples": Json(samples),
        "maximum_absolute_error": Json(maximum_error),
      } : Json).stringify(),
  )
}
