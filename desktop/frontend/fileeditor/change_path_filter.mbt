///|
fn change_path_matches(
  path : @pathx.Relative,
  original : @pathx.Relative?,
  query : String,
) -> Bool {
  let query = query.to_lower()
  path.0.to_lower().contains(query) ||
  (original is Some(original) && original.0.to_lower().contains(query))
}

///|
fn filtered_changes(state : State) -> Array[ChangedFile] {
  match state.changes {
    ChangeListReady(files~, ..) =>
      files.filter(change => {
        change_path_matches(
          change.path,
          change.original_path,
          state.change_path_filter,
        ) &&
        (
          state.change_extensions is None ||
          (
            state.change_extensions is Some(selected) &&
            selected.contains(change_extension(change.path))
          )
        )
      })
    _ => []
  }
}

///|
test "path filters match literal paths and rename sources without case sensitivity" {
  assert_true(change_path_matches(Relative("src/Main.mbt"), None, "SRC/"))
  assert_true(change_path_matches(Relative("src/Main.mbt"), None, ".mbt"))
  assert_true(
    change_path_matches(
      Relative("src/Main.mbt"),
      Some(Relative("old/entry.mbt")),
      "old/",
    ),
  )
  assert_true(change_path_matches(Relative("src/Main.mbt"), None, ""))
  assert_false(change_path_matches(Relative("src/Main.mbt"), None, "docs/"))
  assert_false(change_path_matches(Relative("src/Main.mbt"), None, "*.mbt"))
  assert_true(change_path_matches(Relative("docs/my file.md"), None, "my file"))
}

///|
/// A leading dot alone does not give a dotfile an extension.
fn change_extension(path : @pathx.Relative) -> String? {
  let name = basename(path)
  let parts = name.split(".").to_array()
  if parts.length() < 2 || (parts.length() == 2 && parts[0].is_empty()) {
    return None
  }
  let suffix = parts[parts.length() - 1]
  if suffix.is_empty() {
    None
  } else {
    Some("." + suffix.to_owned().to_lower())
  }
}

///|
fn extension_label(extension : String?) -> String {
  match extension {
    Some(value) => value
    None => "No extension"
  }
}

///|
fn change_extension_options(state : State) -> Array[(String?, Int)] {
  let counts : Map[String?, Int] = Map([])
  if state.changes is ChangeListReady(files~, ..) {
    for change in files {
      let extension = change_extension(change.path)
      counts[extension] = counts.get(extension).unwrap_or(0) + 1
    }
  }
  // Keep a selected type visible if a refresh removes its last file.
  if state.change_extensions is Some(selected) {
    for extension in selected {
      if !counts.contains(extension) {
        counts[extension] = 0
      }
    }
  }
  let options = counts.iter().to_array()
  options.sort_by((a, b) => {
    extension_label(a.0).lexical_compare(extension_label(b.0))
  })
  options
}

///|
test "file extensions use the final suffix and distinguish extensionless files" {
  assert_eq(change_extension(Relative("dir.name/README")), None)
  assert_eq(change_extension(Relative(".gitignore")), None)
  assert_eq(change_extension(Relative(".config.JSON")), Some(".json"))
  assert_eq(change_extension(Relative("src/Main.MBT")), Some(".mbt"))
  assert_eq(change_extension(Relative("archive.tar.gz")), Some(".gz"))
  assert_eq(change_extension(Relative("file.")), None)
}
