///|
fn code_copy_button(source : String) -> @html.Html {
  @html.button(
    class="chat-code-copy",
    type_="button",
    title="Copy code",
    attrs=@html.Attrs::build()
      .aria_label("Copy code")
      .on_click(event => {
        // Capture currentTarget while the event is being dispatched: the
        // clipboard command completes after the event has left the button.
        guard event.current_target().to_option() is Some(button) else {
          return @cmd.none
        }
        @clipboard.copy(
          @clipboard.Text(source),
          copied=@cmd.custom_cmd(_ => code_copy_feedback(button, true)),
          failed=_ => @cmd.custom_cmd(_ => code_copy_feedback(button, false)),
        )
      }),
    [
      @html.span(class="chat-code-copy-symbol", @icons.icon(code_copy_icon)),
      @html.span(class="chat-code-copy-check", @icons.icon(@icons.icon_check)),
    ],
  )
}

///|
fn code_copy_icon() -> @html.Html {
  @svg.svg(
    width=20,
    height=20,
    view_box="0 0 24 24",
    attrs=@svg.Attrs::build()
      .fill("none")
      .stroke("currentColor")
      .stroke_width("1.7")
      .stroke_linecap("round")
      .stroke_linejoin("round"),
    [
      @svg.path(d="M9 9V6a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3h-3"),
      @svg.rect(x=3, y=9, width=12, height=12, rx=3),
    ],
  )
}

///|
// Only transient DOM attributes are owned here; Rabbita retains ownership of
// both icon subtrees. A per-element timer survives streaming re-renders and
// restarts on repeated copies, without keeping removed buttons in a registry.
extern "js" fn code_copy_feedback(
  button : @dom.EventTarget,
  copied : Bool,
) -> Unit =
  #| (() => {
  #|   const timers = new WeakMap();
  #|   return (button, copied) => {
  #|     if (!button.isConnected) return;
  #|     const previous = timers.get(button);
  #|     if (previous !== undefined) clearTimeout(previous);
  #|     button.setAttribute("data-copy-state", copied ? "copied" : "failed");
  #|     const label = copied ? "Copied" : "Copy failed. Try again.";
  #|     button.setAttribute("title", label);
  #|     button.setAttribute("aria-label", label);
  #|     timers.set(button, setTimeout(() => {
  #|       button.removeAttribute("data-copy-state");
  #|       button.setAttribute("title", "Copy code");
  #|       button.setAttribute("aria-label", "Copy code");
  #|       timers.delete(button);
  #|     }, 2000));
  #|   };
  #| })()
