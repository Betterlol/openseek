// Selection snapshots share the semantic-search wire conventions: required
// fields reject missing/null/wrong types, optional metadata accepts missing or
// null and is omitted when absent, and unknown fields are ignored.

///|
pub impl FromJson for SemanticSelectionMatch with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "semantic selection match")
  {
    rule_id: object.required_string("rule_id"),
    description: object.optional_string("description"),
    file: object.required_string("file"),
    start_line: object.required_int("start_line"),
    start_column: object.required_int("start_column"),
    end_line: object.required_int("end_line"),
    end_column: object.required_int("end_column"),
    matched_source: object.required_string("matched_source"),
  }
}

///|
pub impl ToJson for SemanticSelectionMatch with fn to_json(self) {
  let fields : Map[String, Json] = {
    "rule_id": Json(self.rule_id),
    "file": Json(self.file),
    "start_line": Json(self.start_line),
    "start_column": Json(self.start_column),
    "end_line": Json(self.end_line),
    "end_column": Json(self.end_column),
    "matched_source": Json(self.matched_source),
  }
  if self.description is Some(value) {
    fields["description"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for MaterializeSemanticSelectionPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "semantic selection payload")
  {
    root: object.required_string("root"),
    artifact_id: object.required_string("artifact_id"),
    patterns: object.required_string_array("patterns"),
    include_glob: object.required_string("include_glob"),
    exclude_glob: object.required_string("exclude_glob"),
    matches: object.required_array_of("matches"),
  }
}

///|
pub impl ToJson for MaterializeSemanticSelectionPayload with fn to_json(self) {
  {
    "root": self.root,
    "artifact_id": self.artifact_id,
    "patterns": self.patterns,
    "include_glob": self.include_glob,
    "exclude_glob": self.exclude_glob,
    "matches": self.matches,
  }
}

///|
pub impl FromJson for MaterializeSemanticSelectionReply with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "semantic selection reply")
  {
    path: object.required_string("path"),
    match_count: object.required_int("match_count"),
    file_count: object.required_int("file_count"),
  }
}

///|
pub impl ToJson for MaterializeSemanticSelectionReply with fn to_json(self) {
  {
    "path": self.path,
    "match_count": self.match_count,
    "file_count": self.file_count,
  }
}
