///|
test "review navigation skips unavailable rows and stops at queue edges" {
  let first = test_modified_change(@pathx.Relative("first.mbt"))
  let unavailable = {
    ..test_modified_change(@pathx.Relative("link.mbt")),
    kind: ChangeSymlink,
  }
  let last = test_modified_change(@pathx.Relative("last.mbt"))
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[first, unavailable, last],
      refreshing=false,
      refresh_again=false,
    ),
  }
  assert_true(review_neighbor(state, first, -1) is None)
  assert_true(review_neighbor(state, first, 1) == Some(last))
  assert_true(review_neighbor(state, last, -1) == Some(first))
  assert_true(review_neighbor(state, last, 1) is None)
  assert_true(review_edge(state, first, first=true) is None)
  assert_true(review_edge(state, first, first=false) == Some(last))
  assert_true(review_edge(state, last, first=true) == Some(first))
  assert_true(review_edge(state, last, first=false) is None)
  assert_true(change_row_index(state, first) == Some(0))
  assert_true(change_row_index(state, last) == Some(2))
}

///|
test "review navigation distinguishes duplicate same-path Git rows" {
  let path = @pathx.Relative("same.mbt")
  let deleted = {
    ..test_modified_change(path),
    index_status: "D",
    worktree_status: " ",
    kind: ChangeDeleted,
  }
  let untracked = {
    ..test_modified_change(path),
    index_status: "?",
    worktree_status: "?",
    kind: ChangeUntracked,
  }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[deleted, untracked],
      refreshing=false,
      refresh_again=false,
    ),
  }
  assert_true(review_neighbor(state, deleted, 1) == Some(untracked))
  assert_true(review_neighbor(state, untracked, -1) == Some(deleted))
}

///|
test "continuous review navigation wraps the selectable queue even with an empty diff" {
  let first = test_modified_change(@pathx.Relative("first.mbt"))
  let last = test_modified_change(@pathx.Relative("last.mbt"))
  let unavailable = {
    ..first,
    path: @pathx.Relative("link.mbt"),
    kind: ChangeSymlink,
  }
  let docs = owned_state().docs.copy()
  docs[first.path] = reviewed_doc(first.path, first)
  docs[last.path] = reviewed_doc(last.path, last)
  let state = {
    ..owned_state(),
    docs,
    changes: ChangeListReady(
      repository=true,
      files=[first, unavailable, last],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let first_ctx = { ..test_ctx(), active_file: Some(first.path), }
  let last_ctx = { ..test_ctx(), active_file: Some(last.path), }
  assert_true(review_diff_navigation_enabled(state, first_ctx))
  assert_true(review_navigation_neighbor(state, first_ctx, true) == Some(last))
  assert_true(review_navigation_neighbor(state, first_ctx, false) == Some(last))
  assert_true(review_navigation_neighbor(state, last_ctx, false) == Some(first))
  assert_true(review_navigation_neighbor(state, last_ctx, true) == Some(first))
}

///|
test "cross-file reveal waits for content and cancels when its review is superseded" {
  let path = @pathx.Relative("last.mbt")
  let change = test_modified_change(path)
  let doc = reviewed_doc(path, change)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..doc,
    review: doc.review.map(review => { ..review, baseline: ReviewLoading, }),
  }
  let state = { ..owned_state(), docs, }.with_review_navigation_destination(
    change, true,
  )
  let ctx = { ..test_ctx(), active_file: Some(path), }
  let (_, waiting) = sync_review_navigation_destination(test_emit(), state, ctx)
  assert_true(waiting.review_navigation_destination is Some((_, 1, true)))
  let (_, cancelled) = sync_review_navigation_destination(
    test_emit(),
    waiting,
    { ..ctx, active_file: None, },
  )
  assert_true(cancelled.review_navigation_destination is None)
  let replaced_docs = docs.copy()
  replaced_docs[path] = {
    ..doc,
    review: doc.review.map(review => { ..review, generation: 2, }),
  }
  let (_, replaced) = sync_review_navigation_destination(
    test_emit(),
    { ..waiting, docs: replaced_docs, },
    ctx,
  )
  assert_true(replaced.review_navigation_destination is None)
  let ready_docs = docs.copy()
  ready_docs[path] = doc
  let (_, completed) = sync_review_navigation_destination(
    test_emit(),
    { ..waiting, docs: ready_docs, },
    ctx,
  )
  assert_true(completed.review_navigation_destination is None)
}
