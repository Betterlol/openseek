///|
fn pattern_repair_task(pattern : String, instruction : String) -> String {
  (
    $|Current pattern:
    $|\{pattern}
    $|
    $|Requested repair:
    $|\{instruction}
    $|
    $|Apply the smallest repair that satisfies the request. Preserve fixed
    $|callees, operators, labels, argument order and arity. If the current
    $|pattern is an incomplete fragment, complete its surrounding MoonBit
    $|expression first. If a metavariable is needed, choose its legal kind
    $|explicitly. Never submit an ellipsis as a substitute for a missing match
    $|arm or expression body. Call submit_pattern_repair now with the complete
    $|candidate pattern and one short explanation.
  )
}
