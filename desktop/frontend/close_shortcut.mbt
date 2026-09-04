// macOS owns Command+W as a menu key equivalent. Replacing its native Close
// action with a menu command gives the shell and native Browser views one
// entry point without competing keydown handlers.

///|
priv enum CloseRegion {
  Window
  Dock
  Terminal
}

///|
fn focused_close_region() -> CloseRegion? {
  guard @dom.document().get_active_element() is Some(element) else {
    return None
  }
  // Transient controls keep Close from reaching the content beneath them.
  if element.closest("[role=menu], [role=dialog], [role=listbox], .dock-menu")
    is Some(_) {
    None
  } else if element.closest(".terminal-panel") is Some(_) {
    Some(Terminal)
  } else if element.closest(".editor") is Some(_) {
    Some(Dock)
  } else {
    Some(Window)
  }
}

///|
fn close_focused(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  if @interop.page_has_focus() {
    return match focused_close_region() {
      Some(region) => dispatch(AppCloseFocused(region))
      None => @cmd.none
    }
  }
  // A native page has its own document: the shell's activeElement still
  // names its previous focus owner. Ask Proton instead of using that stale
  // element, and close the returned tab identity rather than a later active tab.
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let focused = @interop.bridge_request(
        @interop.ChannelId::Local,
        @commands.app_focused_browser,
        @protocol.NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(HostActionFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      if focused.id is Some(id) {
        scheduler.add(
          @cmd.batch([
            dispatch(Dock(TabClosed(@dock.Browser(id~)))),
            focus_dock_after_close(),
          ]),
        )
      }
    })
  })
}

///|
/// A removed tab button must not turn the next Command+W into a window close.
fn focus_dock_after_close() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .query_selector(".content.panel-open > .editor")
        .to_option()
        is Some(panel) &&
        panel.to_html_element() is Some(element) {
        element.focus()
      }
    },
    kind=@cmd.after_render,
  )
}
