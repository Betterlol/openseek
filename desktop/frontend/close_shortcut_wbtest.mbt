///|
test "Close in the dock closes only its active tab" {
  let dispatch = test_dispatch()
  let (_, browser) = update(dispatch, BrowserTabRequested, desktop_model())
  let (_, mixed) = update(dispatch, ExplorerRequested(ExplorerFiles), browser)
  let (_, closed) = update(dispatch, AppCloseFocused(Dock), mixed)
  assert_eq(closed.dock.tabs.length(), 1)
  assert_true(closed.dock.active is Some(@dock.Browser(id=1)))
  assert_true(@preview.page(closed.preview, 1) is Some(_))
  assert_true(closed.selected_conversation == mixed.selected_conversation)
  let (_, empty) = update(dispatch, AppCloseFocused(Dock), closed)
  assert_true(empty.dock.tabs.is_empty())
  assert_true(@preview.page(empty.preview, 1) is None)
  let (_, unchanged) = update(dispatch, AppCloseFocused(Dock), empty)
  assert_true(unchanged.dock == empty.dock)
}

///|
test "Close in the window leaves the conversation and dock untouched" {
  let dispatch = test_dispatch()
  let (_, browser) = update(dispatch, BrowserTabRequested, desktop_model())
  let (_, unchanged) = update(dispatch, AppCloseFocused(Window), browser)
  assert_true(unchanged.dock == browser.dock)
  assert_true(unchanged.selected_conversation == browser.selected_conversation)
  assert_true(@preview.page(unchanged.preview, 1) is Some(_))
}
