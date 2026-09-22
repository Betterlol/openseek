///|
#cfg(all(target="native", not(platform="windows")))
async test "validator receives EOF and preserves parser diagnostics" {
  let validator : PatternRepairValidator = {
    command: "/bin/sh",
    prefix_args: ["-c", "if read -r line; then exit 99; fi", "validator"],
  }
  run_pattern_repair_validator(validator, pattern="foo()", workspace_root=".")
  let invalid = {
    ..validator,
    prefix_args: [
      "-c",
      (
        #|[ "$1" = dump ] && [ "$2" = --expr ] && [ "$3" = 'foo()' ] && [ "$4" = --strict-check ] && [ "$5" = --exit-code ] || { printf 'wrong arguments' >&2; exit 8; }
        #|printf 'ignored stdout'
        #|printf '  expected expression  ' >&2
        #|exit 7
      ),
      "validator",
    ],
  }
  try
    run_pattern_repair_validator(invalid, pattern="foo()", workspace_root=".")
  catch {
    Invalid(diagnostic) => assert_eq(diagnostic, "expected expression")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("invalid pattern should be rejected")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "validator preserves cancellation" {
  let result = @async.with_timeout_opt(50, () => {
    run_pattern_repair_validator(
      { command: "/bin/sh", prefix_args: ["-c", "exec sleep 30"], },
      pattern="foo()",
      workspace_root=".",
    )
  })
  assert_true(result is None)
}
