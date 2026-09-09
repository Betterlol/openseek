///|
priv enum ReviewHunkBridgeSurface {
  ReviewLineSurface
  ReviewSemanticSurface
} derive(Eq)

///|
/// The active review identity is shared by the permanent Line editor and the
/// currently visible semantic editors. Keeping only the visible surface here
/// prevents the parked Line editor from replacing a Token/Tree selection.
priv struct ReviewHunkBridgeTarget {
  change : ChangedFile
  review_generation : Int
  surface_generation : Int
  surface : ReviewHunkBridgeSurface
  semantic_input : SemanticReviewInput?
  active_hunk : ReviewHunk?
  file_changes : ReviewHunk?
  position : ReviewHunkPosition?
  dispatch : (Msg) -> Unit
}

///|
let review_hunk_bridge_target : Ref[ReviewHunkBridgeTarget?] = Ref(None)

///|
fn current_review_hunk_bridge_target(
  state : State,
  active_file : @pathx.Relative?,
  dispatch : (Msg) -> Unit,
) -> ReviewHunkBridgeTarget? {
  guard active_file is Some(path) &&
    state.docs.get(path) is Some({ review: Some(review), .. }) &&
    state.current_review_generation(review.selected, active_file)
    is Some(review_generation) else {
    return None
  }
  let (active_hunk, file_changes, position) = match
    state.active_review_hunk(active_file) {
    Some(active) => (Some(active.hunk), active.file_changes, active.position)
    None => (None, None, None)
  }
  Some({
    change: review.selected,
    review_generation,
    surface_generation: state.review_hunk_surface_generation,
    surface: if state.semantic_review_input is Some(_) {
      ReviewSemanticSurface
    } else {
      ReviewLineSurface
    },
    semantic_input: state.semantic_review_input,
    active_hunk,
    file_changes,
    position,
    dispatch,
  })
}

///|
fn sync_review_hunk_bridge_target(
  state : State,
  active_file : @pathx.Relative?,
  dispatch : (Msg) -> Unit,
) -> Unit {
  review_hunk_bridge_target.val = current_review_hunk_bridge_target(
    state, active_file, dispatch,
  )
  if mounted_diff_editor() is Some(editor) {
    publish_line_review_hunk_context(editor)
  }
}

///|
fn projected_review_hunk(
  hunks : Array[@viewer.DiffHunk],
  active_index : Int?,
  old_offset : Int?,
  new_offset : Int?,
) -> ReviewHunk? {
  guard active_index is Some(index) else { return None }
  guard index >= 0 && index < hunks.length() else { return None }
  let hunk = ReviewHunk::from_diff_hunk(hunks[index], old_offset, new_offset)
  if hunk.is_empty() {
    None
  } else {
    Some(hunk)
  }
}

///|
fn projected_review_file_changes(editor : @viewer.DiffEditor) -> ReviewHunk? {
  // The parked Line editor may never have been laid out for this file, so its
  // visual hunks can be empty even after the logical diff is ready. Only use
  // the current model pair's changes, excluding geometry-only alignments.
  guard editor.is_diff_up_to_date() && editor.get_diff() is Some(diff) else {
    return None
  }
  let old_ranges : Array[@common.LineRange] = []
  let new_ranges : Array[@common.LineRange] = []
  for change in diff.changes {
    guard change.kind is Visible else { continue }
    old_ranges.push(change.mapping.original)
    new_ranges.push(change.mapping.modified)
  }
  let file_changes = ReviewHunk(old_ranges~, new_ranges~)
  if file_changes.is_empty() {
    None
  } else {
    Some(file_changes)
  }
}

///|
fn publish_review_active_hunk(
  surface : ReviewHunkBridgeSurface,
  hunk : ReviewHunk?,
  file_changes : ReviewHunk?,
  position : ReviewHunkPosition?,
) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface == surface &&
    (
      target.active_hunk != hunk ||
      (
        hunk is Some(_) &&
        (target.file_changes != file_changes || target.position != position)
      )
    ) else {
    return
  }
  review_hunk_bridge_target.val = Some({
    ..target,
    active_hunk: hunk,
    file_changes,
    position,
  })
  (target.dispatch)(
    ReviewActiveHunkChanged(
      change=target.change,
      review_generation=target.review_generation,
      surface_generation=target.surface_generation,
      hunk~,
      file_changes~,
      position~,
    ),
  )
}

///|
fn publish_line_review_hunk_context(editor : @viewer.DiffEditor) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) else { return }
  let hunks = editor.get_hunks()
  let file_changes = projected_review_file_changes(editor)
  match target.surface {
    ReviewLineSurface => {
      let active_index = editor.get_active_hunk_index()
      publish_review_active_hunk(
        ReviewLineSurface,
        projected_review_hunk(hunks, active_index, Some(0), Some(0)),
        file_changes,
        ReviewHunkPosition::from_zero_based(active_index, hunks.length()),
      )
    }
    ReviewSemanticSurface =>
      publish_review_active_hunk(
        ReviewSemanticSurface,
        target.active_hunk,
        file_changes,
        target.position,
      )
  }
}

///|
fn publish_semantic_review_active_hunk(
  input : SemanticReviewInput,
  key : String,
  editor : @viewer.DiffEditor,
  section : @moon_diff_provider.SemanticReviewSection,
  active_index : Int?,
) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface == ReviewSemanticSurface &&
    target.semantic_input == Some(input) &&
    semantic_review_active_key.val == Some(key) else {
    return
  }
  let hunks = editor.get_hunks()
  let file_changes = mounted_diff_editor().bind(projected_review_file_changes)
  publish_review_active_hunk(
    ReviewSemanticSurface,
    projected_review_hunk(
      hunks,
      active_index,
      semantic_feedback_line_offset(section, SemanticReviewOriginal),
      semantic_feedback_line_offset(section, SemanticReviewModified),
    ),
    file_changes,
    semantic_review_hunk_position(key, active_index),
  )
}
