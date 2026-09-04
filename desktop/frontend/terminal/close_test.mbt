///|
test "closing active terminals hides the panel only after the last one" {
  let emit : @cmd.Emit[@terminal.Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(root) else {
    fail("invalid workspace fixture")
  }
  let input = @terminal.Input(
    ctx=@terminal.Ctx(
      channel=@interop.ChannelId::Local,
      session="close-shortcut",
      placement=Some(@interop.WorkspaceRoot(root~)),
      dark_mode=false,
      connected=true,
    ),
    live_channels=[@interop.ChannelId::Local],
    has_devices=true,
  )
  let (_, first) = @terminal.State::empty().handle(emit, ToggleTerminal, input)
  let (_, second) = first.handle(emit, NewTerminal, input)
  let (_, one_left) = second.handle(emit, CloseActiveTerminal, input)
  assert_true(one_left.is_open())
  let (_, closed) = one_left.handle(emit, CloseActiveTerminal, input)
  assert_false(closed.is_open())
  let (_, unchanged) = closed.handle(emit, CloseActiveTerminal, input)
  assert_true(unchanged == closed)
  let (_, hidden) = first.handle(emit, ToggleTerminal, input)
  let (_, unchanged_hidden) = hidden.handle(emit, CloseActiveTerminal, input)
  assert_true(unchanged_hidden == hidden)
}
