///|
struct ExternalDocumentDiffProvider {}

///|
impl @diff.DocumentDiffProvider for ExternalDocumentDiffProvider with fn compute_diff(
  _self,
  _original,
  _modified,
  _options,
) {
  let original = @base_common.LineRange(1, 2)
  let modified = @base_common.LineRange(1, 2)
  let inner = @diff.RangeMapping(Range(1, 1, 1, 2), Range(1, 1, 1, 3))
  {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(original, modified, Some([inner])),
      ),
    ],
  }
}

///|
impl @diff.DocumentDiffProvider for ExternalDocumentDiffProvider with fn on_did_change(
  _self,
  _listener,
) {
  @base_common.Disposable::from(() => ())
}

///|
test "an external package can implement the provider and construct mappings" {
  let provider : &@diff.DocumentDiffProvider = ExternalDocumentDiffProvider::{ }
  let result = try! provider.compute_diff(
    TextSnapshot("a"),
    TextSnapshot("bc"),
    { ignore_trim_whitespace: false, },
  )
  assert_eq(result.changes.length(), 1)
  assert_true(result.changes[0].kind is Visible)
  assert_eq(
    result.changes[0].mapping.inner_changes.unwrap()[0].modified.end_column,
    3,
  )
}

///|
test "line provider keeps EOF inner changes inside their line hunks" {
  // Reduced from the ci.yml failure in moonbitlang/openseek#1224: the old
  // document already ends in a newline, and the appended block starts with a
  // blank line. The line and character refinements must use one EOF anchor.
  let before = "          retention-days: 7\n"
  let after = "          retention-days: 7\n\n      # blocks.\n"
  let cases = [
    (
      before,
      after,
      @base_common.LineRange(2, 2),
      @base_common.LineRange(2, 4),
      @base_common.Range(2, 1, 2, 1),
      @base_common.Range(2, 1, 4, 1),
    ),
    (
      after,
      before,
      LineRange(2, 4),
      LineRange(2, 2),
      Range(2, 1, 4, 1),
      Range(2, 1, 2, 1),
    ),
  ]
  let provider = @diff.LineDocumentDiffProvider()
  for case in cases {
    let (
      original,
      modified,
      original_lines,
      modified_lines,
      original_inner,
      modified_inner,
    ) = case
    let result = provider.compute_diff(
      TextSnapshot(original),
      TextSnapshot(modified),
      { ignore_trim_whitespace: false, },
    )
    guard result.changes is [{ mapping: change, .. }] &&
      change.inner_changes is Some([inner]) else {
      fail("expected one refined EOF change")
    }
    assert_eq(change.original, original_lines)
    assert_eq(change.modified, modified_lines)
    assert_eq(inner.original, original_inner)
    assert_eq(inner.modified, modified_inner)
    assert_eq(
      @diff.normalize_and_validate_document_diff(
        result,
        TextSnapshot(original),
        TextSnapshot(modified),
      ),
      Some(result),
    )
  }
}
