///|
test "Tree retains ignored documentation alignment outside the visible hunk" {
  let original =
    #|/// original docs
    #|fn f() -> Int {
    #|  let x0 = 0
    #|  let x1 = 1
    #|  let x2 = 2
    #|  let x3 = 3
    #|  let x4 = 4
    #|  let x5 = 5
    #|  let x6 = 6
    #|  let x7 = 7
    #|  1
    #|}
  let modified = original
    .replace(
      old="/// original docs",
      new="/// original docs\n/// added docs 1\n/// added docs 2",
    )
    .replace(old="  1\n}", new="  2\n}")
  for
    (old, new, old_line, new_line) in [
      (original, modified, 11, 13),
      (modified, original, 13, 11),
    ] {
    guard @moondiff.compute_sectioned_semantic_review_plan(old, new, Tree)
      is Some({ main_sections: [section], .. }) else {
      fail(
        "expected Tree to accept a changed function with distant ignored docs",
      )
    }
    assert_eq(section.original_source, old)
    assert_eq(section.modified_source, new)
    guard section.diff is Fragment(document) else {
      fail("expected a semantic fragment")
    }
    guard document.changes
      is [{ kind: Ignored, mapping: docs, }, { kind: Visible, mapping: code, }] else {
      fail("expected ignored docs followed by the code change")
    }
    assert_eq(docs.original.start_line_number, 2)
    assert_eq(docs.modified.start_line_number, 2)
    assert_eq(docs.original.length(), old_line - 11)
    assert_eq(docs.modified.length(), new_line - 11)
    assert_eq(code.original.start_line_number, old_line)
    assert_eq(code.modified.start_line_number, new_line)
    guard code.inner_changes is Some([inner]) else {
      fail("expected only the changed return value to be highlighted")
    }
    assert_eq(inner.original.start_column, 3)
    assert_eq(inner.original.end_column, 4)
    assert_eq(inner.modified.start_column, 3)
    assert_eq(inner.modified.end_column, 4)
  }
}
