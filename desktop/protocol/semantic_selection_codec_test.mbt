///|
test "semantic selection codecs omit absent metadata and ignore unknown fields" {
  let wire_match : Json = {
    "rule_id": "rule",
    "file": "main.mbt",
    "start_line": 1,
    "start_column": 1,
    "end_line": 1,
    "end_column": 8,
    "matched_source": "inspect",
  }
  guard wire_match is Object(fields) else { fail("expected object") }
  let with_metadata = fields.copy()
  with_metadata["description"] = Json::null()
  with_metadata["future"] = Json(true)
  let hit : @protocol.SemanticSelectionMatch = @json.from_json(
    Json(with_metadata),
  )
  @debug.assert_eq(hit.to_json(), wire_match)
  let missing : @protocol.SemanticSelectionMatch = @json.from_json(wire_match)
  assert_eq(missing, hit)
  with_metadata["description"] = Json("description")
  let present : @protocol.SemanticSelectionMatch = @json.from_json(
    Json(with_metadata),
  )
  assert_eq(present.description, Some("description"))
  let payload : @protocol.MaterializeSemanticSelectionPayload = @json.from_json({
      "root": "/workspace",
      "artifact_id": "selection",
      "patterns": ["rule"],
      "include_glob": "",
      "exclude_glob": "",
      "matches": [present.to_json()],
      "future": true,
    },
  )
  assert_eq(
    (
      @json.from_json(payload.to_json()) :
      @protocol.MaterializeSemanticSelectionPayload),
    payload,
  )
  let reply : @protocol.MaterializeSemanticSelectionReply = @json.from_json({
    "path": "selection.jsonl",
    "match_count": 1,
    "file_count": 1,
    "future": true,
  })
  @debug.assert_eq(reply.to_json(), {
    "path": "selection.jsonl",
    "match_count": 1,
    "file_count": 1,
  })
}

///|
test "semantic selection codecs reject missing null and malformed required fields" {
  let match_fields : Map[String, Json] = {
    "rule_id": Json("rule"),
    "file": Json("main.mbt"),
    "start_line": Json(1),
    "start_column": Json(1),
    "end_line": Json(1),
    "end_column": Json(8),
    "matched_source": Json("inspect"),
  }
  let payload_fields : Map[String, Json] = {
    "root": Json("/workspace"),
    "artifact_id": Json("selection"),
    "patterns": Json([Json("rule")]),
    "include_glob": Json(""),
    "exclude_glob": Json(""),
    "matches": Json([Json(match_fields)]),
  }
  let reply_fields : Map[String, Json] = {
    "path": Json("selection.jsonl"),
    "match_count": Json(1),
    "file_count": Json(1),
  }
  for fields in [match_fields, payload_fields, reply_fields] {
    for key in fields.keys() {
      for
        replacement in (
          [None, Some(Json::null()), Some(Json(true))] : Array[Json?]) {
        let invalid = fields.copy()
        match replacement {
          None => invalid.remove(key)
          Some(value) => invalid[key] = value
        }
        let accepted = try {
          if fields.contains("file") {
            ignore(
              (@json.from_json(Json(invalid)) : @protocol.SemanticSelectionMatch),
            )
          } else if fields.contains("root") {
            ignore(
              (
                @json.from_json(Json(invalid)) :
                @protocol.MaterializeSemanticSelectionPayload),
            )
          } else {
            ignore(
              (
                @json.from_json(Json(invalid)) :
                @protocol.MaterializeSemanticSelectionReply),
            )
          }
          true
        } catch {
          _ => false
        }
        assert_false(accepted)
      }
    }
  }
  let invalid = match_fields.copy()
  invalid["description"] = Json(7)
  let decoded : @protocol.SemanticSelectionMatch? = Some(
    @json.from_json(Json(invalid)),
  ) catch {
    _ => None
  }
  assert_eq(decoded, None)
}
