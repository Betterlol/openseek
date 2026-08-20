*openseek/agent_tool/edit/edit.mbt*

```mbt
///|
/// The rejected-edit report: the file was not modified, the first parse
/// errors with excerpts synthesized from the would-be content, and how to
/// retry — a corrected re-issue for a small slip, smaller pieces when the
/// errors suggest the replacement broke the file's structure.
///|
/// The rejected-edit report: the file was not modified, the first parse
/// errors with excerpts synthesized from the would-be content, and how to
/// retry — a corrected re-issue for a small slip, smaller pieces when the
/// errors suggest the replacement broke the file's structure.
fn edit_reject_report(
  path : String,
  new_content : String,
  gate : @auto_check.ParseGate,
  introduced~ : Int,
  before_count~ : Int,
) -> String
```
