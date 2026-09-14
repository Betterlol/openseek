///|
/// Source coordinates stay separate from the (possibly clipped) preview.
/// Columns use the editor's one-based UTF-16 coordinates, with exclusive ends.
priv struct SearchPreviewLine {
  line : Int
  text : String
  start_column : Int
}

///|
priv struct SearchResultAnnotation {
  label : String
  description : String?
}

///|
/// One visible result can contain several occurrences, or one multiline match.
/// Presentation and navigation consume this model without knowing the engine.
priv struct SearchResultItem {
  path : String
  target : @common.Range
  ranges : Array[@common.Range]
  preview : Array[SearchPreviewLine]
  annotation : SearchResultAnnotation?
}

///|
fn SearchResultItem::from_text(
  result : @protocol.TextSearchMatch,
) -> SearchResultItem? {
  let ranges = result.ranges.map(range => {
    @common.Range(
      result.line_number,
      range.start_column,
      result.line_number,
      range.end_column,
    )
  })
  guard ranges is [target, ..] else { return None }
  Some({
    path: result.path,
    target,
    ranges,
    preview: [
      {
        line: result.line_number,
        text: result.preview,
        start_column: result.preview_start_column,
      },
    ],
    annotation: None,
  })
}

///|
fn SearchResultItem::from_semantic(
  hit : @protocol.SemanticSearchHit,
) -> SearchResultItem {
  let target = @common.Range(
    hit.start_line,
    hit.start_column,
    hit.end_line,
    hit.end_column,
  )
  let preview = hit.source_context.map(line => SearchPreviewLine::{
    line: line.line,
    text: line.text,
    start_column: 1,
  })
  // Context rows may be absent or rejected by the Host. The matched source
  // still provides a useful preview, whose first line starts at the match.
  if preview.is_empty() {
    for index, text in hit.matched_source.split("\n").to_array() {
      preview.push({
        line: hit.start_line + index,
        text: text.to_owned(),
        start_column: if index == 0 {
          hit.start_column
        } else {
          1
        },
      })
    }
  }
  {
    path: hit.path,
    target,
    ranges: [target],
    preview,
    annotation: Some({ label: hit.rule_id, description: hit.description, }),
  }
}

///|
fn Page::result_items(self : Page) -> Array[SearchResultItem] {
  match self.mode {
    Text => self.text.matches.filter_map(SearchResultItem::from_text)
    Semantic => self.semantic.hits.map(SearchResultItem::from_semantic)
  }
}

///|
/// Project a source range onto one preview line; never use preview offsets for
/// navigation. Empty intersections include an exclusive end at column one.
fn SearchPreviewLine::highlight_slices(
  self : SearchPreviewLine,
  ranges : Array[@common.Range],
) -> Array[(Int, Int)] {
  let slices : Array[(Int, Int)] = []
  for range in ranges {
    if self.line < range.start_line_number || self.line > range.end_line_number {
      continue
    }
    let start = if self.line == range.start_line_number {
      range.start_column - self.start_column
    } else {
      0
    }
    let end = if self.line == range.end_line_number {
      range.end_column - self.start_column
    } else {
      self.text.length()
    }
    let start = start.max(0).min(self.text.length())
    let end = end.max(0).min(self.text.length())
    if start < end {
      slices.push((start, end))
    }
  }
  slices
}
