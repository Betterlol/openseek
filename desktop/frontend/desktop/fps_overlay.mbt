// Desktop frame cadence diagnostic. Own its DOM outside Rabbita so sampling does
// not rerender the application. These are rAF intervals, not GPU timings.

///|
fn mount_fps_overlay() -> Unit {
  let document = @dom.document()
  guard document.get_body() is Some(body) else { return }
  let overlay = document.create_element("output")
  overlay.set_attribute("id", "fps-overlay")
  overlay.set_attribute("aria-live", "off")
  overlay.set_attribute(
    "style", "position:fixed;left:50%;top:12px;transform:translateX(-50%);z-index:2147483647;pointer-events:none;app-region:no-drag;padding:6px 10px;border-radius:6px;background:#111e;color:#fff;font:12px/18px monospace;white-space:nowrap;font-variant-numeric:tabular-nums",
  )
  let text = document.create_text_node("rAF · sampling…")
  overlay.append_child(text.as_node())
  body.append_child(overlay.as_node())
  let times : Array[Double] = []
  let mut last_display = @dom.window().get_performance().now()
  // Background tabs pause rAF; do not count that pause as a slow frame.
  document.add_event_listener("visibilitychange", _ => times.clear())
  fn frame(timestamp : Double) -> Unit {
    guard overlay.get_is_connected() else { return }
    times.push(timestamp)
    while times.length() > 2 && times[1] < timestamp - 1000.0 {
      times.remove(0) |> ignore
    }
    if times.length() > 1 && timestamp - last_display >= 250.0 {
      let intervals = [ for i in 1..<times.length() => times[i] - times[i - 1] ]
      intervals.sort()
      let elapsed = timestamp - times[0]
      if elapsed > 0.0 {
        let fps = (intervals.length().to_double() * 1000.0 / elapsed + 0.5).to_int()
        let p95 = intervals[(intervals.length() * 95 + 99) / 100 - 1]
        let longest = intervals[intervals.length() - 1]
        text.set_node_value(
          @js.Nullable::from_option(
            Some(
              "rAF · FPS \{fps} · P95 \{frame_ms(p95)}ms · Max \{frame_ms(longest)}ms · 1s",
            ),
          ),
        )
      }
      last_display = timestamp
    }
    @dom.window().request_animation_frame(frame) |> ignore
  }
  @dom.window().request_animation_frame(frame) |> ignore
}

///|
fn frame_ms(value : Double) -> String {
  let tenths = (value * 10.0 + 0.5).to_int()
  "\{tenths / 10}.\{tenths % 10}"
}
