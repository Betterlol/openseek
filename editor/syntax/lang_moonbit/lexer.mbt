///|
/// Hand-written MoonBit lexer behind the `syntax.LineTokenizer` contract.
///
/// The carried `TokenizerState` is empty because no MoonBit string construct
/// survives a line end. A per-line persistent list records lexical modes,
/// top first: normal expression code, string text, `$|` multiline-string text,
/// string interpolation, and nested interpolation braces.
/// No MoonBit string construct survives a line end, so every line both
/// enters and leaves in normal mode; the mode list only drives within-line lexing.
struct MoonBitTokenizer {
  _unit : Unit
}

///|
/// Lexical modes used only by one `tokenize_line` invocation.
priv enum MoonBitMode {
  Normal
  StringText(@syntax.HighlightTag)
  MultilineStringText
  Interpolation
  InterpolationBrace
}

///|
/// Classifies one identifier lexeme by spelling only. This is lexical
/// classification: it does not inspect surrounding tokens or source text.
fn classify_word(word : StringView) -> @syntax.HighlightTag {
  match word {
    "fn"
    | "let"
    | "letrec"
    | "and"
    | "mut"
    | "var"
    | "const"
    | "pub"
    | "priv"
    | "readonly"
    | "proof_assert"
    | "proof_let"
    | "struct"
    | "enum"
    | "extenum"
    | "enumview"
    | "extend"
    | "trait"
    | "impl"
    | "with"
    | "derive"
    | "type"
    | "suberror"
    | "raise"
    | "throw"
    | "try"
    | "catch"
    | "noraise"
    | "nocancel"
    | "defer"
    | "errdefer"
    | "async"
    | "test"
    | "if"
    | "else"
    | "match"
    | "guard"
    | "while"
    | "for"
    | "in"
    | "loop"
    | "break"
    | "continue"
    | "return"
    | "as"
    | "is"
    | "using"
    | "import"
    | "extern"
    | "declare"
    | "where"
    | "nobreak"
    | "lexscan"
    | "lexmatch"
    | "package"
    | "_" => Keyword
    "true" | "false" => Constant
    _ => if @syntax.is_capitalized(word) { Type } else { Identifier }
  }
}

///|
/// Keep constructors/types capitalized. Lowercase names followed by a call
/// (including `f!()` and `f?()`) get function color without resolving symbols.
fn classify_reference(
  word : StringView,
  after : StringView,
) -> @syntax.HighlightTag {
  if @syntax.is_capitalized(word) {
    return Type
  }
  lexmatch after {
    (
      re"^[ \t\v\f\u{a0}\u{feff}\u{1680}\u{2000}-\u{200a}\u{202f}\u{205f}\u{3000}]*[!?]?[ \t\v\f\u{a0}\u{feff}\u{1680}\u{2000}-\u{200a}\u{202f}\u{205f}\u{3000}]*\(",
      after=_,
    ) => Function
    _ => Identifier
  }
}

///|
/// Shared immutable normal state; MoonBit's lexer always returns to it at the
/// end of a line.
let moonbit_normal_state : @syntax.TokenizerState = TokenizerState()

///|
/// Creates the MoonBit tokenizer.
pub fn MoonBitTokenizer::MoonBitTokenizer() -> MoonBitTokenizer {
  { _unit: (), }
}

///|
/// Initial MoonBit lexer state.
pub impl @syntax.LineTokenizer for MoonBitTokenizer with fn initial_state(_) {
  moonbit_normal_state
}

///|
/// Tokenizes one MoonBit source line and resets to normal mode at line end.
pub impl @syntax.LineTokenizer for MoonBitTokenizer with fn tokenize_line(
  _,
  line_text,
  _state,
) {
  let tokens : Array[@syntax.LineToken] = []
  for at = 0, view = line_text, modes = @list.singleton(Normal) {
    match modes {
      More(StringText(tag), tail~) =>
        lexmatch view with longest {
          re"^$" => break
          (
            re"^\\(?:u[{][0-9a-fA-F]+[}]|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|o[0-3][0-7]{2})" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes
          }
          (re"^\\[{]", after=rest) => {
            let end = at + 2
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes.prepend(Interpolation)
          }
          (re"^\\." as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes
          }
          (re"^\"", after=rest) => {
            let end = at + 1
            @syntax.push_token(tokens, at, end, tag)
            continue end, rest, tail
          }
          (re"^[^\"\\]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, tag)
            continue end, rest, modes
          }
          (re"^." as c, after=rest) => {
            let end = at + c.utf16_len()
            @syntax.push_token(tokens, at, end, tag)
            continue end, rest, modes
          }
        }
      More(MultilineStringText, tail=_) =>
        lexmatch view with longest {
          re"^$" => break
          (re"^\\[{]", after=rest) => {
            let end = at + 2
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes.prepend(Interpolation)
          }
          (
            re"^\\(?:u[{][0-9a-fA-F]+[}]|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|o[0-3][0-7]{2}|.)" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes
          }
          (re"^[^\\]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (re"^." as c, after=rest) => {
            let end = at + c.utf16_len()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
        }
      More(top, tail~) =>
        lexmatch view with longest {
          re"^$" => break
          (
            re"^[ \t\v\f\u{a0}\u{feff}\u{1680}\u{2000}-\u{200a}\u{202f}\u{205f}\u{3000}]+" as s,
            after=rest,
          ) => continue at + s.length(), rest, modes
          (re"^///.*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, CommentDoc)
            continue end, rest, modes
          }
          (re"^//.*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Comment)
            continue end, rest, modes
          }
          (re"^#\|.*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (re"^\$\|", after=rest) => {
            let end = at + 2
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes.prepend(MultilineStringText)
          }
          (
            re"^#[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)?" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Attribute)
            continue end, rest, modes
          }
          (re"^(?:b|re)?\"" as s, after=rest) => {
            let end = at + s.length()
            let tag : @syntax.HighlightTag = if s == "re\"" {
              Regexp
            } else {
              String
            }
            @syntax.push_token(tokens, at, end, tag)
            continue end, rest, modes.prepend(StringText(tag))
          }
          (re"^b?'(?:\\.|[^'\\])+'" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (
            re"^(?:0[xX][0-9a-fA-F][0-9a-fA-F_]*|0[oO][0-7][0-7_]*|0[bB][01][01_]*|[0-9][0-9_]*)(?:UL|[ULN])?" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Number)
            continue end, rest, modes
          }
          (
            re"^(?:[0-9][0-9_]*\.[0-9_]*(?:[eE][+\-]?[0-9][0-9_]*)?F?|0[xX][0-9a-fA-F][0-9a-fA-F_]*\.[0-9a-fA-F_]*(?:[pP][+\-]?[0-9][0-9_]*F?)?)" as s,
            after=rest,
          ) => {
            // The compiler backs off before `..`: `1..=3` is not `1.`.
            if s.has_suffix(".") && rest.has_prefix(".") {
              let size = s.length() - 1
              @syntax.push_token(tokens, at, at + size, Number)
              continue at + size, view[size:], modes
            }
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Number)
            continue end, rest, modes
          }
          (
            re"^@[a-zA-Z_][a-zA-Z0-9_\-]*(?:/[a-zA-Z_][a-zA-Z0-9_\-]*)*" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Type)
            continue end, rest, modes
          }
          (re"^\.[0-9]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, at + 1, Delimiter)
            @syntax.push_token(tokens, at + 1, end, Number)
            continue end, rest, modes
          }
          (
            re"^[a-zA-Z_\u{a1}-\u{ac}\u{ae}-\u{2af}\u{1100}-\u{11ff}\u{1e00}-\u{1eff}\u{2070}-\u{209f}\u{2150}-\u{218f}\u{2e80}-\u{2eff}\u{2ff0}-\u{2fff}\u{3001}-\u{30ff}\u{31c0}-\u{9fff}\u{ac00}-\u{d7ff}\u{f900}-\u{faff}\u{fe00}-\u{fe0f}\u{fe30}-\u{fe4f}\u{1f000}-\u{1fbff}\u{20000}-\u{2a6df}\u{2a700}-\u{2ebef}\u{2f800}-\u{2fa1f}\u{30000}-\u{323af}\u{e0100}-\u{e01ef}][a-zA-Z0-9_\u{a1}-\u{ac}\u{ae}-\u{2af}\u{1100}-\u{11ff}\u{1e00}-\u{1eff}\u{2070}-\u{209f}\u{2150}-\u{218f}\u{2e80}-\u{2eff}\u{2ff0}-\u{2fff}\u{3001}-\u{30ff}\u{31c0}-\u{9fff}\u{ac00}-\u{d7ff}\u{f900}-\u{faff}\u{fe00}-\u{fe0f}\u{fe30}-\u{fe4f}\u{1f000}-\u{1fbff}\u{20000}-\u{2a6df}\u{2a700}-\u{2ebef}\u{2f800}-\u{2fa1f}\u{30000}-\u{323af}\u{e0100}-\u{e01ef}]*" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            // Dot identifiers bypass the keyword table in the compiler lexer.
            let tag = if at > 0 &&
              line_text[at - 1] == '.' &&
              (at < 2 || line_text[at - 2] != '.') {
              classify_reference(s, rest)
            } else {
              let lexical = classify_word(s)
              let reference = classify_reference(s, rest)
              if lexical == Identifier ||
                (s == "extend" && reference == Function) {
                reference
              } else {
                lexical
              }
            }
            @syntax.push_token(tokens, at, end, tag)
            continue end, rest, modes
          }
          (re"^(?:\.\.(?:\.|<=?|=)?|>=?\.\.|[∀∃→])" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Operator)
            continue end, rest, modes
          }
          (re"^[+\-*/%=<>!&^~?\|]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Operator)
            continue end, rest, modes
          }
          (re"^[()\[\],;:.]", after=rest) => {
            let end = at + 1
            @syntax.push_token(tokens, at, end, Delimiter)
            continue end, rest, modes
          }
          (re"^[{]", after=rest) => {
            let end = at + 1
            @syntax.push_token(tokens, at, end, Delimiter)
            if top is (Interpolation | InterpolationBrace) {
              continue end, rest, modes.prepend(InterpolationBrace)
            }
            continue end, rest, modes
          }
          (re"^[}]", after=rest) => {
            let end = at + 1
            if top is Interpolation {
              @syntax.push_token(tokens, at, end, StringEscape)
              continue end, rest, tail
            } else {
              @syntax.push_token(tokens, at, end, Delimiter)
              if top is InterpolationBrace {
                continue end, rest, tail
              }
              continue end, rest, modes
            }
          }
          (re"^." as c, after=rest) => {
            let end = at + c.utf16_len()
            @syntax.push_token(tokens, at, end, Punctuation)
            continue end, rest, modes
          }
        }
      Empty => break
    }
  }
  (tokens, moonbit_normal_state)
}

///|
pub extend MoonBitTokenizer with @syntax.LineTokenizer::{
  initial_state,
  tokenize_line,
}
