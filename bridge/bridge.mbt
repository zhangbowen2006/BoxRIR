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
