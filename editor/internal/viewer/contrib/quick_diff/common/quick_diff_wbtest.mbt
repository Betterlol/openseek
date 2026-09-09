///|
fn test_change(
  original : Array[String],
  modified : Array[String],
) -> @diff.DetailedLineRangeMapping raise {
  let changes = @diff.LineDocumentDiffProvider().compute_diff(
    TextSnapshot(original.join("\n")),
    TextSnapshot(modified.join("\n")),
    { ignore_trim_whitespace: false, },
  ).changes.map(change => change.mapping)
  assert_eq(changes.length(), 1)
  changes[0]
}

///|
test "get_change_type mirrors quickDiff.ts:121" {
  assert_eq(get_change_type(test_change(["a", "c"], ["a", "b", "c"])), Add)
  assert_eq(get_change_type(test_change(["a", "b", "c"], ["a", "c"])), Delete)
  assert_eq(
    get_change_type(test_change(["a", "old", "c"], ["a", "new", "c"])),
    Modify,
  )
}

///|
test "quick diff service stores, clears, and reports originals per resource" {
  let service = QuickDiffService()
  let a = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/a.txt",
  )
  let b = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/b.txt",
  )
  let fired : Array[String] = []
  let listener = service.on_did_change_original(resource => {
    fired.push(resource.to_string())
  })
  assert_true(service.get_original_content(a) is None)
  service.set_original_content(a, Some("one\ntwo"))
  assert_eq(service.get_original_content(a).unwrap(), "one\ntwo")
  assert_true(service.get_original_content(b) is None)
  service.set_original_content(a, Some("three"))
  assert_eq(service.get_original_content(a).unwrap(), "three")
  service.set_original_content(a, None)
  assert_true(service.get_original_content(a) is None)
  assert_eq(fired.length(), 3)
  assert_eq(fired[0], a.to_string())
  listener.dispose()
  service.set_original_content(b, Some("x"))
  assert_eq(fired.length(), 3)
}

///|
test "quick_diff_handle adapts the concrete baseline store" {
  let service = QuickDiffService()
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/handle.txt",
  )
  let handle = service.quick_diff_handle()
  let mut change_count = 0
  let changed_resources : Array[String] = []
  let subscription = handle.on_did_change_original(changed => {
    changed_resources.push(changed.to_string())
    change_count += 1
  })
  assert_true(handle.get_original_content(resource) is None)
  service.set_original_content(resource, Some("baseline"))
  assert_true(handle.get_original_content(resource) is Some("baseline"))
  assert_eq(change_count, 1)
  assert_eq(changed_resources.join(","), resource.to_string())
  subscription.dispose()
}
