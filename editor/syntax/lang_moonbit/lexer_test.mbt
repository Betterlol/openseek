///|
/// Golden token-stream rendering: one `start-end tag text` line per token in
/// document offsets — lines split on `\n`, lexer state threaded line to line
/// exactly as the tokenization part's whole-document sweep does.
fn render_tokens(source : String) -> String {
  let tokenizer : &@syntax.LineTokenizer = @lang_moonbit.MoonBitTokenizer()
  let rendered : Array[String] = []
  for
    line in split_lines(source)
    state = tokenizer.initial_state(), line_start = 0 {
    let (tokens, next_state) = tokenizer.tokenize_line(line, state)
    for token in tokens {
      let text = line[token.start:token.end]
      rendered.push(
        "\{line_start + token.start}-\{line_start + token.end} \{token.tag} \{text}",
      )
    }
    continue next_state, line_start + line.length() + 1
  }
  rendered.join("\n")
}

///|
/// Splits on `\n` only, matching the snapshot line table the part consumes.
fn split_lines(source : String) -> Array[String] {
  [
    for line in source.split("\n") => line.to_owned()
  ]
}

///|
fn assert_line_tokens(
  line : String,
  expected : Array[(String, @syntax.HighlightTag)],
) -> Unit raise {
  let lexer = @lang_moonbit.MoonBitTokenizer()
  let (tokens, state) = lexer.tokenize_line(line, lexer.initial_state())
  assert_eq(tokens.map(t => (line[t.start:t.end].to_owned(), t.tag)), expected)
  assert_eq(state, lexer.initial_state())
}

///|
test "compiler keywords and ordinary spellings" {
  for
    word in [
      "extenum", "enumview", "readonly", "throw", "letrec", "and", "proof_assert",
      "proof_let", "nocancel", "package", "_",
    ] {
    assert_line_tokens(word, [(word, Keyword)])
    let identifier = "\{word}_value"
    assert_line_tokens(identifier, [(identifier, Identifier)])
  }
  // Reserved words still lex as identifiers; removed aliases are not keywords.
  for word in ["not", "typealias", "traitalias", "fnalias", "await", "module"] {
    assert_line_tokens(word, [(word, Identifier)])
  }
}

///|
test "numeric literals and their boundaries follow the compiler lexer" {
  for
    literal in [
      "0", "123_456", "42U", "42L", "42UL", "42N", "0xFFN", "0o77UL", "0b101N", "1.",
      "1.F", "3.14e-2F", "1.0e1_0", "0x1.fp+3", "0x1.p-2F", "0XAB.CDp1_2", "0x1.",
    ] {
    assert_line_tokens(literal, [(literal, Number)])
  }
  for operator in ["..", "..=", "..<", "..<=", "...", ">..", ">=.."] {
    assert_line_tokens("1\{operator}2", [
      ("1", Number),
      (operator, Operator),
      ("2", Number),
    ])
  }
  assert_line_tokens("0x1..=2", [
    ("0x1", Number),
    ("..=", Operator),
    ("2", Number),
  ])
  assert_line_tokens("tuple.0.1", [
    ("tuple", Identifier),
    (".", Delimiter),
    ("0", Number),
    (".", Delimiter),
    ("1", Number),
  ])
  assert_line_tokens("1ULL 0x_FF 1e3", [
    ("1UL", Number),
    ("L", Type),
    ("0", Number),
    ("x_FF", Identifier),
    ("1", Number),
    ("e3", Identifier),
  ])
}

///|
test "regex text resumes after nested string interpolation" {
  let source =
    #|re"^\{f("x")}\w+$"
  assert_line_tokens(source, [
    ("re\"^", Regexp),
    ("\\{", StringEscape),
    ("f", Function),
    ("(", Delimiter),
    ("\"x\"", String),
    (")", Delimiter),
    ("}\\w", StringEscape),
    ("+$\"", Regexp),
  ])
  assert_line_tokens("re\"unfinished", [("re\"unfinished", Regexp)])
}

///|
test "literal escapes consume their full spelling" {
  for prefix in ["\"", "b\"", "$|"] {
    assert_line_tokens("\{prefix}\\x41\\u0042\\u{1F31F}\\o101", [
      (prefix, String),
      ("\\x41\\u0042\\u{1F31F}\\o101", StringEscape),
    ])
  }
  assert_line_tokens("#|\\u{41}\\{x}", [("#|\\u{41}\\{x}", String)])
  assert_line_tokens("'\\u{1F31F}' b'\\x41'", [
    ("'\\u{1F31F}'", String),
    ("b'\\x41'", String),
  ])
}

///|
test "call lookahead respects keywords constructors and member names" {
  assert_line_tokens("fn parse(x : Int) { parse ? (x) }", [
    ("fn", Keyword),
    ("parse", Function),
    ("(", Delimiter),
    ("x", Identifier),
    (":", Delimiter),
    ("Int", Type),
    (")", Delimiter),
    ("{", Delimiter),
    ("parse", Function),
    ("?", Operator),
    ("(", Delimiter),
    ("x", Identifier),
    (")", Delimiter),
    ("}", Delimiter),
  ])
  assert_line_tokens("@pkg.match!() extend () Some(1) if (ok)", [
    ("@pkg", Type),
    (".", Delimiter),
    ("match", Function),
    ("!", Operator),
    ("()", Delimiter),
    ("extend", Function),
    ("()", Delimiter),
    ("Some", Type),
    ("(", Delimiter),
    ("1", Number),
    (")", Delimiter),
    ("if", Keyword),
    ("(", Delimiter),
    ("ok", Identifier),
    (")", Delimiter),
  ])
  assert_line_tokens("obj.let value~ value~~ fn_name // call()", [
    ("obj", Identifier),
    (".", Delimiter),
    ("let", Identifier),
    ("value", Identifier),
    ("~", Operator),
    ("value", Identifier),
    ("~~", Operator),
    ("fn_name", Identifier),
    ("// call()", Comment),
  ])
  assert_line_tokens("1..match", [
    ("1", Number),
    ("..", Operator),
    ("match", Keyword),
  ])
}

///|
test "package paths attributes and Unicode identifiers keep token boundaries" {
  assert_line_tokens("@my-org/core-utils.run() @pkg/", [
    ("@my-org/core-utils", Type),
    (".", Delimiter),
    ("run", Function),
    ("()", Delimiter),
    ("@pkg", Type),
    ("/", Operator),
  ])
  assert_line_tokens("#doc.ui(value)", [
    ("#doc.ui", Attribute),
    ("(", Delimiter),
    ("value", Identifier),
    (")", Delimiter),
  ])
  assert_line_tokens("let\u{3000}值🌟 = A值 + 🌟x2; ∀ ∃ → $", [
    ("let", Keyword),
    ("值🌟", Identifier),
    ("=", Operator),
    ("A值", Type),
    ("+", Operator),
    ("🌟x2", Identifier),
    (";", Delimiter),
    ("∀", Operator),
    ("∃", Operator),
    ("→", Operator),
    ("$", Punctuation),
  ])
}

///|
test "fixture errors.mbt token stream" {
  // tests/fixtures/workspace/src/errors.mbt
  let source =
    #|///|
    #|suberror FixtureError String
    #|
    #|///|
    #|fn risky_step(flag : Bool) -> Int raise FixtureError {
    #|  if flag {
    #|    raise FixtureError("fixture failure")
    #|  }
    #|  1
    #|}
  inspect(
    render_tokens(source),
    content=(
      #|0-4 CommentDoc ///|
      #|5-13 Keyword suberror
      #|14-26 Type FixtureError
      #|27-33 Type String
      #|35-39 CommentDoc ///|
      #|40-42 Keyword fn
      #|43-53 Function risky_step
      #|53-54 Delimiter (
      #|54-58 Identifier flag
      #|59-60 Delimiter :
      #|61-65 Type Bool
      #|65-66 Delimiter )
      #|67-69 Operator ->
      #|70-73 Type Int
      #|74-79 Keyword raise
      #|80-92 Type FixtureError
      #|93-94 Delimiter {
      #|97-99 Keyword if
      #|100-104 Identifier flag
      #|105-106 Delimiter {
      #|111-116 Keyword raise
      #|117-129 Type FixtureError
      #|129-130 Delimiter (
      #|130-147 String "fixture failure"
      #|147-148 Delimiter )
      #|151-152 Delimiter }
      #|155-156 Number 1
      #|157-158 Delimiter }
    ),
  )
}

///|
test "string interpolation and escapes" {
  let source =
    #|let s = "count \{n + 1} done\n"
  inspect(
    render_tokens(source),
    content=(
      #|0-3 Keyword let
      #|4-5 Identifier s
      #|6-7 Operator =
      #|8-15 String "count 
      #|15-17 StringEscape \{
      #|17-18 Identifier n
      #|19-20 Operator +
      #|21-22 Number 1
      #|22-23 StringEscape }
      #|23-28 String  done
      #|28-30 StringEscape \n
      #|30-31 String "
    ),
  )
}

///|
test "line-local modes track nested interpolation braces" {
  let source =
    #|let s = "\{{ "x": 1 }}"
  inspect(
    render_tokens(source),
    content=(
      #|0-3 Keyword let
      #|4-5 Identifier s
      #|6-7 Operator =
      #|8-9 String "
      #|9-11 StringEscape \{
      #|11-12 Delimiter {
      #|13-16 String "x"
      #|16-17 Delimiter :
      #|18-19 Number 1
      #|20-21 Delimiter }
      #|21-22 StringEscape }
      #|22-23 String "
    ),
  )
}

///|
test "multiline string lines" {
  let source =
    #|let text =
    #|  #|plain "line"
    #|  $|sum \{1 + 2} tail
  inspect(
    render_tokens(source),
    content=(
      #|0-3 Keyword let
      #|4-8 Identifier text
      #|9-10 Operator =
      #|13-27 String #|plain "line"
      #|30-36 String $|sum 
      #|36-38 StringEscape \{
      #|38-39 Number 1
      #|40-41 Operator +
      #|42-43 Number 2
      #|43-44 StringEscape }
      #|44-49 String  tail
    ),
  )
}

///|
test "doc comments attributes numbers and package refs" {
  let source =
    #|///| Doc heading
    #|#external("js", "x")
    #|// plain comment
    #|let mask = 0xFF_a0 + 0b1010 + 3.14e-2 + 42U
    #|let v = @core.Range(1, 2)
  inspect(
    render_tokens(source),
    content=(
      #|0-16 CommentDoc ///| Doc heading
      #|17-26 Attribute #external
      #|26-27 Delimiter (
      #|27-31 String "js"
      #|31-32 Delimiter ,
      #|33-36 String "x"
      #|36-37 Delimiter )
      #|38-54 Comment // plain comment
      #|55-58 Keyword let
      #|59-63 Identifier mask
      #|64-65 Operator =
      #|66-73 Number 0xFF_a0
      #|74-75 Operator +
      #|76-82 Number 0b1010
      #|83-84 Operator +
      #|85-92 Number 3.14e-2
      #|93-94 Operator +
      #|95-98 Number 42U
      #|99-102 Keyword let
      #|103-104 Identifier v
      #|105-106 Operator =
      #|107-112 Type @core
      #|112-113 Delimiter .
      #|113-118 Type Range
      #|118-119 Delimiter (
      #|119-120 Number 1
      #|120-121 Delimiter ,
      #|122-123 Number 2
      #|123-124 Delimiter )
    ),
  )
}

///|
test "tokenization ignores incoming state and resets at line end" {
  let lexer : &@syntax.LineTokenizer = @lang_moonbit.MoonBitTokenizer()
  // Unterminated string: the line still tokenizes and the carried state
  // returns to normal because MoonBit strings never span lines.
  let foreign_state = lexer.initial_state().push_mode(b's')
  let (_, after_unterminated) = lexer.tokenize_line(
    "let s = \"open", foreign_state,
  )
  assert_true(after_unterminated == lexer.initial_state())
}

///|
test "word classification distinguishes keywords from identifiers" {
  inspect(
    render_tokens(
      "let letter = true; let trueish = self selfless; typealias Type",
    ),
    content=(
      #|0-3 Keyword let
      #|4-10 Identifier letter
      #|11-12 Operator =
      #|13-17 Constant true
      #|17-18 Delimiter ;
      #|19-22 Keyword let
      #|23-30 Identifier trueish
      #|31-32 Operator =
      #|33-37 Identifier self
      #|38-46 Identifier selfless
      #|46-47 Delimiter ;
      #|48-57 Identifier typealias
      #|58-62 Type Type
    ),
  )
}

///|
test "defer and errdefer classify as keywords" {
  inspect(
    render_tokens("defer close(); errdefer rollback(); let deferred = 1"),
    content=(
      #|0-5 Keyword defer
      #|6-11 Function close
      #|11-14 Delimiter ();
      #|15-23 Keyword errdefer
      #|24-32 Function rollback
      #|32-35 Delimiter ();
      #|36-39 Keyword let
      #|40-48 Identifier deferred
      #|49-50 Operator =
      #|51-52 Number 1
    ),
  )
}

///|
test "emoji identifiers preserve UTF-16 offsets" {
  inspect(
    render_tokens("🌟"),
    content=(
      #|0-2 Identifier 🌟
    ),
  )
}

///|
test "extend and var classify as keywords" {
  inspect(
    render_tokens("extend trait Show for Int; var total = 0"),
    content=(
      #|0-6 Keyword extend
      #|7-12 Keyword trait
      #|13-17 Type Show
      #|18-21 Keyword for
      #|22-25 Type Int
      #|25-26 Delimiter ;
      #|27-30 Keyword var
      #|31-36 Identifier total
      #|37-38 Operator =
      #|39-40 Number 0
    ),
  )
}

///|
test "import classifies as a keyword in script import blocks" {
  inspect(
    render_tokens("import { \"moonbitlang/async\" }"),
    content=(
      #|0-6 Keyword import
      #|7-8 Delimiter {
      #|9-28 String "moonbitlang/async"
      #|29-30 Delimiter }
    ),
  )
}

///|
test "lexscan and lexmatch classify as keywords" {
  inspect(
    render_tokens("lexscan lexmatch; let lexer = 0"),
    content=(
      #|0-7 Keyword lexscan
      #|8-16 Keyword lexmatch
      #|16-17 Delimiter ;
      #|18-21 Keyword let
      #|22-27 Identifier lexer
      #|28-29 Operator =
      #|30-31 Number 0
    ),
  )
}
