///|
test "overview rulers keep original and modified model coordinates separate" {
  let insert = @diff.DetailedLineRangeMapping(
    LineRange(1, 1),
    LineRange(1, 2),
    None,
  )
  let modify = @diff.DetailedLineRangeMapping(
    LineRange(2, 3),
    LineRange(2, 3),
    None,
  )
  let delete = @diff.DetailedLineRangeMapping(
    LineRange(4, 5),
    LineRange(4, 4),
    None,
  )
  let diff_state = DiffState::from_diff_result({
    changes: [
      DocumentDiffChange(insert),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 2), LineRange(2, 2), None),
        kind=Ignored,
      ),
      DocumentDiffChange(modify),
      DocumentDiffChange(delete),
    ],
  })

  assert_eq(original_diff_overview_ruler_entries(diff_state), [
    {
      id: 1,
      range: LineRange(2, 3),
      color: diff_overview_removed_color,
      lane: Full,
    },
    {
      id: 2,
      range: LineRange(4, 5),
      color: diff_overview_removed_color,
      lane: Full,
    },
  ])
  assert_eq(modified_diff_overview_ruler_entries(diff_state), [
    {
      id: 0,
      range: LineRange(1, 2),
      color: diff_overview_inserted_color,
      lane: Full,
    },
    {
      id: 1,
      range: LineRange(2, 3),
      color: diff_overview_inserted_color,
      lane: Full,
    },
  ])
}

///|
// Pinned oracle: vscode@07c20d96cf3f2cbc8142ac7079ba9048cf7f6134,
// src/vs/editor/browser/widget/diffEditor/features/overviewRulerFeature.ts.
test "diff overview viewport uses the modified scrollbar thumb geometry" {
  let no_overflow = diff_overview_viewport_geometry(420.0, 420.0, 0.0, 14.0)
  assert_eq(no_overflow.top, 0.0)
  assert_eq(no_overflow.height, 420.0)
  let middle = diff_overview_viewport_geometry(420.0, 1000.0, 290.0, 14.0)
  assert_eq(middle.top, 122.0)
  assert_eq(middle.height, 176.0)
  let end = diff_overview_viewport_geometry(420.0, 1000.0, 580.0, 14.0)
  assert_eq(end.top, 244.0)
  assert_eq(end.height, 176.0)
}
