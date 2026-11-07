///|
#export_name("describe_json")
pub fn describe_json(text : String) -> String {
  @api.describe_json(text)
}

///|
#export_name("generate_json")
pub fn generate_json(text : String, dry : Bytes) -> String {
  @api.generate_json(text, dry)
}

///|
#export_name("reference_samples_json")
pub fn reference_samples_json(text : String) -> String {
  @api.reference_samples_json(text)
}

///|
#export_name("render_base64_json")
pub fn render_base64_json(text : String, dry_base64 : String) -> String {
  if dry_base64.length() > 5592408 {
    return "{\"ok\":false,\"error\":\"source WAV exceeds 4 MiB\"}"
  }
  let dry = @base64.decode(dry_base64) catch {
    _ => return "{\"ok\":false,\"error\":\"invalid source WAV base64\"}"
  }
  @api.generate_base64_json(text, dry)
}
