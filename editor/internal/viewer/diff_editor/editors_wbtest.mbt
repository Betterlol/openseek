///|
test "diff panes reserve controls independently of folding options" {
  assert_eq(
    diff_pane_options(CodeEditorOptions(folding=false), Inherit, true, true),
    CodeEditorOptions(folding=false, line_decorations_width=26),
  )
  assert_eq(
    diff_pane_options(
      CodeEditorOptions(show_folding_controls=Never),
      Inherit,
      true,
      true,
    ),
    CodeEditorOptions(
      folding=false,
      show_folding_controls=Never,
      line_decorations_width=26,
    ),
  )
  assert_eq(
    diff_pane_options(
      CodeEditorOptions(
        soft_wrap=true,
        folding=false,
        line_decorations_width=14,
      ),
      Off,
      true,
      false,
    ),
    CodeEditorOptions(
      folding=false,
      soft_wrap=false,
      handle_mouse_wheel=false,
      line_decorations_width=30,
    ),
  )
}
