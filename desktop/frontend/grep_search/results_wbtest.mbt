///|
test "clipped previews preserve UTF-16 navigation and occurrence counts" {
  let raw : @protocol.TextSearchMatch = {
    path: "src/main.mbt",
    line_number: 7,
    preview: "😀 moon moon",
    preview_start_column: 9,
    ranges: [
      { start_column: 12, end_column: 16, },
      { start_column: 17, end_column: 21, },
      { start_column: 40, end_column: 44, },
    ],
  }
  guard SearchResultItem::from_text(raw) is Some(item) else {
    fail("expected a navigable search result")
  }
  assert_eq(item.target, @common.Range(7, 12, 7, 16))
  assert_eq(item.ranges.length(), 3)
  assert_eq(item.preview[0].highlight_slices(item.ranges), [(3, 7), (8, 12)])
  let groups = visible_file_groups([item, item], 1)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].matches.length(), 1)
  assert_eq(groups[0].count, 6)
}

///|
test "structural previews highlight only the matched multiline extent" {
  let raw : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "example",
    description: Some("Match the whole call"),
    start_line: 3,
    start_column: 3,
    end_line: 5,
    end_column: 1,
    matched_source: "inspect(\n  😀\n",
    source_context: [
      { line: 2, text: "before", is_match: false, },
      { line: 3, text: "  inspect(", is_match: true, },
      { line: 4, text: "  😀", is_match: true, },
      { line: 5, text: "after", is_match: true, },
    ],
  }
  let item = SearchResultItem::from_semantic(raw)
  assert_eq(item.target, @common.Range(3, 3, 5, 1))
  assert_eq(item.preview.map(line => line.highlight_slices(item.ranges)), [
    [],
    [(2, 10)],
    [(0, 4)],
    [],
  ])
  let without_context = SearchResultItem::from_semantic({
    ..raw,
    source_context: [],
  })
  assert_eq(without_context.preview[0].start_column, 3)
  assert_eq(
    without_context.preview.map(line => line.highlight_slices(item.ranges)),
    [[(0, 8)], [(0, 4)], []],
  )
}
