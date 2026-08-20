// The semantic model types live in tui/core; re-export them so the tui package
// remains the single public facade for consumers (e.g. cmd/tui) that construct
// inputs and transcript items.

///|
pub using @core {type Input, type Event, type ToolStatus, type TranscriptItem}

///|
pub using @completion {type CompletionItem}

///|
pub using @slash {type SlashCommandSpec}

///|
/// Set or clear the transient activity label and redraw.
#deprecated("use Ui::set_live_view — it sets the whole live view with a single redraw")
pub async fn Ui::set_activity(self : Self, activity : @doc.Text?) -> Unit {
  self.commands.wait(() => {
    self.activity = activity
    self.redraw()
  })
}

///|
/// Replace the entire transcript with `items`, clearing the scrollback and
/// re-rendering from scratch. Used by the `/undo` command to rebuild the
/// transcript after the engine rolls back session events: the caller renders
/// the remaining session events into `TranscriptItem`s and passes them here.
pub async fn Ui::replace_transcript(
  self : Self,
  items : Array[TranscriptItem],
) -> Unit {
  self.commands.wait(() => {
    self.transcript.clear()
    for item in items {
      self.transcript.push(@doc.ToDoc::to_doc(item))
    }
    guard self.viewport is Some(viewport) else {
      abort("replace_transcript without an entered UI")
    }
    viewport.refresh_size(self.tty)
    viewport.replay_scrollback(
      self.tty,
      scrollback=self.transcript_rows(cols=viewport.cols()),
      surface=self.composer_surface(cols=viewport.cols(), rows=viewport.rows()),
    )
  })
}

///|
/// Replace the queued-inputs preview (copied defensively) and redraw.
#deprecated("use Ui::set_live_view — it sets the whole live view with a single redraw")
pub async fn Ui::set_queued_inputs(self : Self, inputs : Array[Input]) -> Unit {
  self.commands.wait(() => {
    self.queued_inputs = inputs.copy()
    self.redraw()
  })
}

///|
/// Set the persistent status line and redraw.
#deprecated("use Ui::set_live_view — it sets the whole live view with a single redraw")
pub async fn Ui::set_status(self : Self, status : @doc.Text) -> Unit {
  self.commands.wait(() => {
    self.status = status
    self.redraw()
  })
}
