// First self-hosted compiler component. Token names mirror grammar revision 1.

use e.mem

type Kind = enum u8 {
    Invalid,
    Eof,
    Newline,
    Identifier,
    Integer,
    Float,
    String,
    RawString,
    Character,
    KwUse,
    KwType,
    KwConst,
    KwVar,
    KwLet,
    KwFn,
    KwRet,
    KwIf,
    KwElse,
    KwWhile,
    KwFor,
    KwIn,
    KwSwitch,
    KwCase,
    KwDefault,
    KwBreak,
    KwContinue,
    KwDefer,
    KwTry,
    KwStruct,
    KwUnion,
    KwEnum,
    KwError,
    KwWhen,
    KwTrue,
    KwFalse,
    KwNil,
    KwOk,
    KwAs,
    KwZero,
    KwUndef,
    KwExtern,
    KwUnreachable,
    KwShared,
    PunctEllipsis,
    PunctRange,
    PunctArrow,
    PunctEqEq,
    PunctBangEq,
    PunctLtEq,
    PunctGtEq,
    PunctShiftLeft,
    PunctShiftRight,
    PunctAddWrap,
    PunctSubWrap,
    PunctMulWrap,
    PunctAddAssign,
    PunctSubAssign,
    PunctMulAssign,
    PunctDivAssign,
    PunctRemAssign,
    PunctAddWrapAssign,
    PunctSubWrapAssign,
    PunctMulWrapAssign,
    PunctShiftLeftAssign,
    PunctShiftRightAssign,
    PunctBitAndAssign,
    PunctBitXorAssign,
    PunctBitOrAssign,
    PunctAndAnd,
    PunctOrOr,
    PunctAt,
    PunctDot,
    PunctComma,
    PunctColon,
    PunctAssign,
    PunctLParen,
    PunctRParen,
    PunctLBracket,
    PunctRBracket,
    PunctLBrace,
    PunctRBrace,
    PunctStar,
    PunctSlash,
    PunctPercent,
    PunctPlus,
    PunctMinus,
    PunctLt,
    PunctGt,
    PunctAmp,
    PunctCaret,
    PunctPipe,
    PunctBang,
    PunctTilde,
    PunctUnderscore,
}

type TriviaKind = enum u8 {
    End,
    Bom,
    Space,
    Comment,
}

type Trivia = struct {
    kind: TriviaKind,
    start: usize,
    end: usize,
    line: usize,
    column: usize,
    end_line: usize,
    end_column: usize,
    column_utf16: usize,
    end_column_utf16: usize,
}

// What every pass reads of a token (D315): its kind, bytes and where it starts. It
// was 120 bytes with the end position, both UTF-16 columns and where its leading
// trivia began -- read by diagnostics and tooling alone, so those are derived by
// `span_of` and `leading_start` when asked for, from the source the token came from.
type Token = struct {
    kind: Kind,
    // Whether the trivia before this token continues a comment: what the formatter's
    // trivia scanner starts from, and one byte.
    leading_comment: bool,
    start: usize,
    end: usize,
}

// Where each line of a source begins (D315): line 1 at byte 0, the rest after each
// newline, so a line and a column are a binary search and a short scan from an offset.
// An empty table stands for "not built": the search then counts newlines from the
// start, which a diagnostic can afford.
fn line_starts(a: *mem.Arena, source: str) -> ([]usize, err) {
    var count = 1usize
    var at = 0usize
    while at < source.len {
        if source[at] == 10u8 { count += 1usize }
        if source[at] == 13u8 && !(at + 1usize < source.len && source[at + 1usize] == 10u8) { count += 1usize }
        at += 1usize
    }
    let (lines, lines_error) = mem.alloc[usize](a, count)
    if lines_error != ok { ret (lines, lines_error) }
    lines[0usize] = 0usize
    var filled = 1usize
    at = 0usize
    while at < source.len {
        let c = source[at]
        at += 1usize
        if c == 13u8 && at < source.len && source[at] == 10u8 { at += 1usize }
        if c == 10u8 || c == 13u8 {
            lines[filled] = at
            filled += 1usize
        }
    }
    ret (lines, ok)
}

// The 1-based line `offset` is on.
fn line_of(source: str, lines: []const usize, offset: usize) -> usize {
    if lines.len == 0usize {
        var line = 1usize
        var at = 0usize
        while at < offset && at < source.len {
            let c = source[at]
            at += 1usize
            if c == 13u8 && at < source.len && source[at] == 10u8 { at += 1usize }
            if c == 10u8 || c == 13u8 { line += 1usize }
        }
        ret line
    }
    var low = 0usize
    var high = lines.len
    while low + 1usize < high {
        let mid = (low + high) / 2usize
        if lines[mid] <= offset { low = mid } else { high = mid }
    }
    ret low + 1usize
}

// The first byte of the line `offset` is on.
fn line_start_of(source: str, lines: []const usize, offset: usize) -> usize {
    if lines.len != 0usize { ret lines[line_of(source, lines, offset) - 1usize] }
    var at = offset
    while at > 0usize && source[at - 1usize] != 10u8 && source[at - 1usize] != 13u8 { at = at - 1usize }
    ret at
}

// The 1-based column of `offset`: scalars from the line's start, the byte-order mark
// none of them.
fn column_of(source: str, lines: []const usize, offset: usize) -> usize {
    ret column_from(source, line_start_of(source, lines, offset), offset)
}

// The column of `offset` on the line that begins at `line_start`, already known.
fn column_from(source: str, line_start: usize, offset: usize) -> usize {
    var at = line_start
    if at == 0usize && offset >= 3usize && source[0usize] == 239u8 && source[1usize] == 187u8 && source[2usize] == 191u8 { at = 3usize }
    var column = 1usize
    while at < offset {
        if source[at] >= 128u8 {
            let width = utf8_width(source, at)
            if width == 0usize { at += invalid_utf8_width(source, at) } else { at += width }
        } else {
            at += 1usize
        }
        column += 1usize
    }
    ret column
}

// Whether `offset` begins a line: the parser's column-0 test for a declaration keyword.
fn at_line_start(source: str, offset: usize) -> bool {
    if offset == 0usize { ret true }
    if offset == 3usize && source[0usize] == 239u8 && source[1usize] == 187u8 && source[2usize] == 191u8 { ret true }
    ret source[offset - 1usize] == 10u8 || source[offset - 1usize] == 13u8
}

// A token's full position, for a diagnostic or a tooling record: the end of the token
// and the UTF-16 columns, derived from the source.
type Span = struct {
    start: usize,
    end: usize,
    line: usize,
    column: usize,
    end_line: usize,
    end_column: usize,
    column_utf16: usize,
    end_column_utf16: usize,
}

// UTF-16 units from the start of the line `offset` is on up to it: the scan back to
// the line's first byte, then forward over the scalars.
fn column_utf16_at(source: str, lines: []const usize, offset: usize) -> usize {
    var units = 1usize
    var at = line_start_of(source, lines, offset)
    // The byte-order mark is not a column: the scanner starts past it.
    if at == 0usize && offset >= 3usize && source[0usize] == 239u8 && source[1usize] == 187u8 && source[2usize] == 191u8 { at = 3usize }
    while at < offset {
        if source[at] >= 128u8 {
            let width = utf8_width(source, at)
            if width == 0usize {
                at += invalid_utf8_width(source, at)
                units += 1usize
            } else {
                at += width
                if width == 4usize { units += 2usize } else { units += 1usize }
            }
        } else {
            at += 1usize
            units += 1usize
        }
    }
    ret units
}

fn span_of(source: str, lines: []const usize, of: Token) -> Span {
    var span: Span = zero
    span.start = of.start
    span.end = of.end
    if of.start <= source.len {
        span.line = line_of(source, lines, of.start)
        span.column = column_of(source, lines, of.start)
        span.column_utf16 = column_utf16_at(source, lines, of.start)
    }
    if of.end <= source.len {
        span.end_line = line_of(source, lines, of.end)
        span.end_column = column_of(source, lines, of.end)
        span.end_column_utf16 = column_utf16_at(source, lines, of.end)
    }
    ret span
}

// Where the token at `at` of `tokens`'s leading trivia begins: the previous token's
// end, or the file's first byte -- the byte-order mark is trivia of the first token.
fn leading_start(tokens: []const Token, at: usize) -> usize {
    if at == 0usize { ret 0usize }
    ret tokens[at - 1usize].end
}

// Which of docs/diagnostics.md's lexical codes an `Invalid` token is: by the byte it
// starts at, since the scanner rejects at the first byte it cannot take (D215).
fn invalid_code(source: str, invalid: Token) -> str {
    if invalid.start >= source.len { ret "E-LEX-9999" }
    let first = source[invalid.start]
    if first >= 128u8 { ret "E-LEX-0001" }
    if first < 32u8 || first == 127u8 { ret "E-LEX-0002" }
    if first == 34u8 || first == 39u8 || first == 114u8 || (first >= 48u8 && first <= 57u8) || first == 46u8 { ret "E-LEX-0003" }
    ret "E-LEX-9999"
}

type Scanner = struct {
    source: str,
    off: usize,
    leading_comment: bool,
    in_comment: bool,
    // A scanner over tokens already scanned (D316): `next` hands them out in order,
    // and a copy of the scanner is a lookahead, as before. The lexer runs once per
    // module and every pass reads the list.
    replay: bool,
    tokens: []const Token,
    at: usize,
}

fn init_tokens(source: str, tokens: []const Token) -> Scanner {
    var s = init(source)
    s.replay = true
    s.tokens = tokens
    ret s
}

type TriviaScanner = struct {
    source: str,
    off: usize,
    end: usize,
    line: usize,
    column: usize,
    column_utf16: usize,
    comment_continuation: bool,
}

error InvalidSource

fn init(source: str) -> Scanner {
    var off = 0usize
    if source.len >= 3usize && source[0usize] == 239u8 && source[1usize] == 187u8 && source[2usize] == 191u8 {
        off = 3usize
    }
    var s: Scanner = zero
    s.source = source
    s.off = off
    ret s
}

fn is_alpha(c: u8) -> bool {
    if c >= 65u8 && c <= 90u8 { ret true }
    if c >= 97u8 && c <= 122u8 { ret true }
    ret c == 95u8
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

fn is_hex(c: u8) -> bool {
    if is_digit(c) { ret true }
    if c >= 65u8 && c <= 70u8 { ret true }
    ret c >= 97u8 && c <= 102u8
}

fn is_base_digit(c: u8, base: u8) -> bool {
    if base == 2u8 { ret c == 48u8 || c == 49u8 }
    if base == 8u8 { ret c >= 48u8 && c <= 55u8 }
    if base == 10u8 { ret is_digit(c) }
    ret is_hex(c)
}

fn is_alnum(c: u8) -> bool {
    ret is_alpha(c) || is_digit(c)
}

fn is_continuation(c: u8) -> bool {
    ret c >= 128u8 && c <= 191u8
}

fn utf8_width(source: str, off: usize) -> usize {
    let first = source[off]
    if first < 128u8 { ret 1usize }
    if first >= 194u8 && first <= 223u8 {
        if off + 1usize < source.len && is_continuation(source[off + 1usize]) { ret 2usize }
        ret 0usize
    }
    if first >= 224u8 && first <= 239u8 {
        if off + 2usize >= source.len { ret 0usize }
        let second = source[off + 1usize]
        let third = source[off + 2usize]
        if !is_continuation(third) { ret 0usize }
        if first == 224u8 { if second < 160u8 || second > 191u8 { ret 0usize } }
        if first == 237u8 { if second < 128u8 || second > 159u8 { ret 0usize } }
        if first != 224u8 && first != 237u8 && !is_continuation(second) { ret 0usize }
        ret 3usize
    }
    if first >= 240u8 && first <= 244u8 {
        if off + 3usize >= source.len { ret 0usize }
        let second = source[off + 1usize]
        if first == 240u8 { if second < 144u8 || second > 191u8 { ret 0usize } }
        if first == 244u8 { if second < 128u8 || second > 143u8 { ret 0usize } }
        if first != 240u8 && first != 244u8 && !is_continuation(second) { ret 0usize }
        if !is_continuation(source[off + 2usize]) || !is_continuation(source[off + 3usize]) { ret 0usize }
        ret 4usize
    }
    ret 0usize
}

fn invalid_utf8_width(source: str, off: usize) -> usize {
    let first = source[off]
    if first >= 194u8 && first <= 223u8 {
        if off + 1usize < source.len && is_continuation(source[off + 1usize]) { ret 2usize }
        ret 1usize
    }
    if first >= 224u8 && first <= 239u8 {
        if off + 1usize >= source.len { ret 1usize }
        let second = source[off + 1usize]
        var second_ok = is_continuation(second)
        if first == 224u8 { second_ok = second >= 160u8 && second <= 191u8 }
        if first == 237u8 { second_ok = second >= 128u8 && second <= 159u8 }
        if !second_ok { ret 1usize }
        if off + 2usize < source.len && is_continuation(source[off + 2usize]) { ret 3usize }
        ret 2usize
    }
    if first >= 240u8 && first <= 244u8 {
        if off + 1usize >= source.len { ret 1usize }
        let second = source[off + 1usize]
        var second_ok = is_continuation(second)
        if first == 240u8 { second_ok = second >= 144u8 && second <= 191u8 }
        if first == 244u8 { second_ok = second >= 128u8 && second <= 143u8 }
        if !second_ok { ret 1usize }
        if off + 2usize >= source.len || !is_continuation(source[off + 2usize]) { ret 2usize }
        if off + 3usize < source.len && is_continuation(source[off + 3usize]) { ret 4usize }
        ret 3usize
    }
    ret 1usize
}

fn text_is(source: str, start: usize, end: usize, expected: str) -> bool {
    if end - start != expected.len { ret false }
    var i = 0usize
    while i < expected.len {
        if source[start + i] != expected[i] { ret false }
        i += 1usize
    }
    ret true
}

fn digits_are_valid(source: str, start: usize, end: usize, base: u8) -> bool {
    if start == end { ret false }
    var i = start
    var need_digit = true
    while i < end {
        let c = source[i]
        if is_base_digit(c, base) {
            need_digit = false
        } else {
            if c != 95u8 || need_digit { ret false }
            need_digit = true
        }
        i += 1usize
    }
    ret !need_digit
}

fn integer_suffix_is_valid(source: str, start: usize, end: usize) -> bool {
    if start == end { ret true }
    let length = end - start
    if source[start] != 105u8 && source[start] != 117u8 { ret false }
    if length == 2usize { ret source[start + 1usize] == 56u8 }
    if length == 3usize {
        if source[start + 1usize] == 49u8 && source[start + 2usize] == 54u8 { ret true }
        if source[start + 1usize] == 51u8 && source[start + 2usize] == 50u8 { ret true }
        ret source[start + 1usize] == 54u8 && source[start + 2usize] == 52u8
    }
    if length != 5usize { ret false }
    ret source[start + 1usize] == 115u8 && source[start + 2usize] == 105u8 && source[start + 3usize] == 122u8 && source[start + 4usize] == 101u8
}

fn float_suffix_is_valid(source: str, start: usize, end: usize) -> bool {
    if start == end { ret true }
    let length = end - start
    var offset = start
    if length == 4usize {
        if source[start] != 98u8 { ret false }
        offset += 1usize
        ret source[offset] == 102u8 && source[offset + 1usize] == 49u8 && source[offset + 2usize] == 54u8
    } else {
        if length != 3usize { ret false }
    }
    if source[offset] != 102u8 { ret false }
    if source[offset + 1usize] == 49u8 && source[offset + 2usize] == 54u8 { ret true }
    if source[offset + 1usize] == 51u8 && source[offset + 2usize] == 50u8 { ret true }
    ret source[offset + 1usize] == 54u8 && source[offset + 2usize] == 52u8
}

// Keywords by first byte (D306): every identifier compared itself against all
// thirty-four keywords; now against the few sharing its first letter.
fn keyword(source: str, start: usize, end: usize) -> Kind {
    if end - start == 1usize && source[start] == 95u8 { ret .PunctUnderscore }
    if end - start < 2usize || end - start > 11usize { ret .Identifier }
    let first = source[start]
    if first == 97u8 {
        if text_is(source, start, end, "as") { ret .KwAs }
        ret .Identifier
    }
    if first == 98u8 {
        if text_is(source, start, end, "break") { ret .KwBreak }
        ret .Identifier
    }
    if first == 99u8 {
        if text_is(source, start, end, "const") { ret .KwConst }
        if text_is(source, start, end, "case") { ret .KwCase }
        if text_is(source, start, end, "continue") { ret .KwContinue }
        ret .Identifier
    }
    if first == 100u8 {
        if text_is(source, start, end, "default") { ret .KwDefault }
        if text_is(source, start, end, "defer") { ret .KwDefer }
        ret .Identifier
    }
    if first == 101u8 {
        if text_is(source, start, end, "else") { ret .KwElse }
        if text_is(source, start, end, "enum") { ret .KwEnum }
        if text_is(source, start, end, "error") { ret .KwError }
        if text_is(source, start, end, "extern") { ret .KwExtern }
        ret .Identifier
    }
    if first == 102u8 {
        if text_is(source, start, end, "fn") { ret .KwFn }
        if text_is(source, start, end, "for") { ret .KwFor }
        if text_is(source, start, end, "false") { ret .KwFalse }
        ret .Identifier
    }
    if first == 105u8 {
        if text_is(source, start, end, "if") { ret .KwIf }
        if text_is(source, start, end, "in") { ret .KwIn }
        ret .Identifier
    }
    if first == 108u8 {
        if text_is(source, start, end, "let") { ret .KwLet }
        ret .Identifier
    }
    if first == 110u8 {
        if text_is(source, start, end, "nil") { ret .KwNil }
        ret .Identifier
    }
    if first == 111u8 {
        if text_is(source, start, end, "ok") { ret .KwOk }
        ret .Identifier
    }
    if first == 114u8 {
        if text_is(source, start, end, "ret") { ret .KwRet }
        ret .Identifier
    }
    if first == 115u8 {
        if text_is(source, start, end, "switch") { ret .KwSwitch }
        if text_is(source, start, end, "struct") { ret .KwStruct }
        if text_is(source, start, end, "shared") { ret .KwShared }
        ret .Identifier
    }
    if first == 116u8 {
        if text_is(source, start, end, "type") { ret .KwType }
        if text_is(source, start, end, "try") { ret .KwTry }
        if text_is(source, start, end, "true") { ret .KwTrue }
        ret .Identifier
    }
    if first == 117u8 {
        if text_is(source, start, end, "use") { ret .KwUse }
        if text_is(source, start, end, "union") { ret .KwUnion }
        if text_is(source, start, end, "undef") { ret .KwUndef }
        if text_is(source, start, end, "unreachable") { ret .KwUnreachable }
        ret .Identifier
    }
    if first == 118u8 {
        if text_is(source, start, end, "var") { ret .KwVar }
        ret .Identifier
    }
    if first == 119u8 {
        if text_is(source, start, end, "while") { ret .KwWhile }
        if text_is(source, start, end, "when") { ret .KwWhen }
        ret .Identifier
    }
    if first == 122u8 {
        if text_is(source, start, end, "zero") { ret .KwZero }
        ret .Identifier
    }
    ret .Identifier
}

// A keyword is exactly an identifier-shaped span that `keyword` maps away from
// `.Identifier`, so this stays in step with the keyword table by construction
// rather than by a second list that has to be kept in sync.
fn is_keyword(source: str, span: Token) -> bool {
    if span.end <= span.start || span.end > source.len { ret false }
    let kind = keyword(source, span.start, span.end)
    ret kind != .Identifier && kind != .PunctUnderscore
}

fn token(s: *Scanner, kind: Kind, start: usize) -> Token {
    let result = Token{
        kind: kind,
        leading_comment: s.leading_comment,
        start: start,
        end: s.off,
    }
    s.leading_comment = s.in_comment
    ret result
}

fn has(s: *Scanner, a: u8, b: u8) -> bool {
    ret s.off + 1usize < s.source.len && s.source[s.off] == a && s.source[s.off + 1usize] == b
}

fn has3(s: *Scanner, a: u8, b: u8, c: u8) -> bool {
    ret s.off + 2usize < s.source.len && s.source[s.off] == a && s.source[s.off + 1usize] == b && s.source[s.off + 2usize] == c
}

fn take(s: *Scanner, n: usize) {
    s.off += n
}

fn take_scalar(s: *Scanner, width: usize) {
    s.off += width
}

fn take_invalid_utf8(s: *Scanner) {
    s.off += invalid_utf8_width(s.source, s.off)
}

// The trivia before `owner`, from the previous token's end (D315): its position is
// where that token ended, and the file's first line and column when there is none.
fn trivia_of(source: str, lines: []const usize, tokens: []const Token, at: usize) -> TriviaScanner {
    ret trivia_init(source, lines, leading_start(tokens, at), tokens[at])
}

// The trivia before a token for a reader of kinds and bytes alone: no positions, so
// no line lookup per token, which the formatter's passes over every newline need.
fn trivia_kinds_of(source: str, tokens: []const Token, at: usize) -> TriviaScanner {
    let owner = tokens[at]
    ret TriviaScanner{
        source: source,
        off: leading_start(tokens, at),
        end: owner.start,
        line: 0usize,
        column: 0usize,
        column_utf16: 0usize,
        comment_continuation: owner.leading_comment,
    }
}

fn trivia_init(source: str, lines: []const usize, leading: usize, owner: Token) -> TriviaScanner {
    ret TriviaScanner{
        source: source,
        off: leading,
        end: owner.start,
        line: line_of(source, lines, leading),
        column: column_of(source, lines, leading),
        column_utf16: column_utf16_at(source, lines, leading),
        comment_continuation: owner.leading_comment,
    }
}

fn trivia_token(t: *TriviaScanner, kind: TriviaKind, start: usize, line: usize, column: usize, column_utf16: usize) -> Trivia {
    ret Trivia{
        kind: kind,
        start: start,
        end: t.off,
        line: line,
        column: column,
        end_line: t.line,
        end_column: t.column,
        column_utf16: column_utf16,
        end_column_utf16: t.column_utf16,
    }
}

fn trivia_take(t: *TriviaScanner, n: usize) {
    t.off += n
    t.column += n
    t.column_utf16 += n
}

fn trivia_take_scalar(t: *TriviaScanner, width: usize) {
    t.off += width
    t.column += 1usize
    if width == 4usize {
        t.column_utf16 += 2usize
    } else {
        t.column_utf16 += 1usize
    }
}

fn next_trivia(t: *TriviaScanner) -> Trivia {
    let start = t.off
    let line = t.line
    let column = t.column
    let column_utf16 = t.column_utf16
    if t.off == t.end { ret trivia_token(t, .End, start, line, column, column_utf16) }
    if t.off == 0usize && t.end >= 3usize && t.source[0usize] == 239u8 && t.source[1usize] == 187u8 && t.source[2usize] == 191u8 {
        t.off += 3usize
        ret trivia_token(t, .Bom, start, line, column, column_utf16)
    }
    if !t.comment_continuation && t.source[t.off] == 32u8 {
        while t.off < t.end && t.source[t.off] == 32u8 { trivia_take(t, 1usize) }
        ret trivia_token(t, .Space, start, line, column, column_utf16)
    }
    t.comment_continuation = false
    while t.off < t.end {
        let c = t.source[t.off]
        if c >= 128u8 {
            trivia_take_scalar(t, utf8_width(t.source, t.off))
        } else {
            trivia_take(t, 1usize)
        }
    }
    ret trivia_token(t, .Comment, start, line, column, column_utf16)
}

fn next(s: *Scanner) -> Token {
    if s.replay {
        if s.at < s.tokens.len {
            let replayed = s.tokens[s.at]
            s.at += 1usize
            ret replayed
        }
        var eof: Token = zero
        eof.kind = .Eof
        eof.start = s.source.len
        eof.end = s.source.len
        ret eof
    }
    while s.off < s.source.len {
        if !s.in_comment {
            let c = s.source[s.off]
            if c == 32u8 {
                take(s, 1usize)
                continue
            }
            if !has(s, 47u8, 47u8) { break }
            take(s, 2usize)
            s.in_comment = true
        }
        while s.off < s.source.len && s.source[s.off] != 10u8 && s.source[s.off] != 13u8 {
            let comment_byte = s.source[s.off]
            if comment_byte == 0u8 || (comment_byte < 32u8 && comment_byte != 9u8) {
                let invalid_start = s.off
                take(s, 1usize)
                ret token(s, .Invalid, invalid_start)
            }
            if comment_byte >= 128u8 {
                let width = utf8_width(s.source, s.off)
                if width == 0usize {
                    let invalid_start = s.off
                        take_invalid_utf8(s)
                    ret token(s, .Invalid, invalid_start)
                }
                take_scalar(s, width)
            } else {
                take(s, 1usize)
            }
        }
        if s.off < s.source.len {
            s.in_comment = false
        } else {
            if s.in_comment {
                s.in_comment = false
                continue
            }
        }
    }

    let start = s.off
    if s.off == s.source.len { ret token(s, .Eof, start) }
    let c = s.source[s.off]

    if c == 10u8 || c == 13u8 {
        if c == 13u8 && s.off + 1usize < s.source.len && s.source[s.off + 1usize] == 10u8 {
            s.off += 2usize
        } else {
            s.off += 1usize
        }
        ret token(s, .Newline, start)
    }

    if c >= 128u8 {
        let width = utf8_width(s.source, s.off)
        if width == 0usize {
            take_invalid_utf8(s)
        } else {
            take_scalar(s, width)
        }
        ret token(s, .Invalid, start)
    }

    if c == 114u8 && s.off + 1usize < s.source.len && (s.source[s.off + 1usize] == 34u8 || s.source[s.off + 1usize] == 35u8) {
        var delimiter = s.off + 1usize
        var hashes = 0usize
        while delimiter < s.source.len && s.source[delimiter] == 35u8 && hashes < 9usize {
            delimiter += 1usize
            hashes += 1usize
        }
        if hashes <= 8usize && delimiter < s.source.len && s.source[delimiter] == 34u8 {
            var valid = true
            take(s, delimiter - s.off + 1usize)
            while s.off < s.source.len {
                if s.source[s.off] == 34u8 {
                    var closes = s.off + 1usize + hashes <= s.source.len
                    var hash_index = 0usize
                    while closes && hash_index < hashes {
                        if s.source[s.off + 1usize + hash_index] != 35u8 { closes = false }
                        hash_index += 1usize
                    }
                    if closes {
                        take(s, 1usize + hashes)
                        if !valid { ret token(s, .Invalid, start) }
                        ret token(s, .RawString, start)
                    }
                }
                if s.source[s.off] == 10u8 || s.source[s.off] == 13u8 {
                    if s.source[s.off] == 13u8 && s.off + 1usize < s.source.len && s.source[s.off + 1usize] == 10u8 {
                        s.off += 2usize
                    } else {
                        s.off += 1usize
                    }
                            } else {
                    let raw_byte = s.source[s.off]
                    if raw_byte == 0u8 || (raw_byte < 32u8 && raw_byte != 9u8) {
                        valid = false
                        take(s, 1usize)
                    } else {
                        if raw_byte >= 128u8 {
                            let width = utf8_width(s.source, s.off)
                            if width == 0usize {
                                valid = false
                                take_invalid_utf8(s)
                            } else {
                                take_scalar(s, width)
                            }
                        } else {
                            take(s, 1usize)
                        }
                    }
                }
            }
            ret token(s, .Invalid, start)
        }
    }

    if is_alpha(c) {
        take(s, 1usize)
        while s.off < s.source.len && is_alnum(s.source[s.off]) { take(s, 1usize) }
        ret token(s, keyword(s.source, start, s.off), start)
    }

    if is_digit(c) {
        var kind = Kind.Integer
        take(s, 1usize)
        if c == 48u8 && s.off < s.source.len && (s.source[s.off] == 120u8 || s.source[s.off] == 111u8 || s.source[s.off] == 98u8) {
            let prefix = s.source[s.off]
            take(s, 1usize)
            let digits_start = s.off
            var base = 2u8
            if prefix == 111u8 { base = 8u8 }
            if prefix == 120u8 { base = 16u8 }
            while s.off < s.source.len && (is_base_digit(s.source[s.off], base) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
            let digits_end = s.off
            while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
            if !digits_are_valid(s.source, digits_start, digits_end, base) || !integer_suffix_is_valid(s.source, digits_end, s.off) {
                ret token(s, .Invalid, start)
            }
            ret token(s, kind, start)
        }
        let integer_start = start
        while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
            take(s, 1usize)
        }
        let integer_end = s.off
        if !digits_are_valid(s.source, integer_start, integer_end, 10u8) {
            while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) { take(s, 1usize) }
            ret token(s, .Invalid, start)
        }
        if s.off + 1usize < s.source.len && s.source[s.off] == 46u8 && s.source[s.off + 1usize] != 46u8 && is_digit(s.source[s.off + 1usize]) {
            kind = .Float
            take(s, 1usize)
            let fraction_start = s.off
            while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
            if !digits_are_valid(s.source, fraction_start, s.off, 10u8) {
                while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) { take(s, 1usize) }
                ret token(s, .Invalid, start)
            }
        }
        if s.off < s.source.len && (s.source[s.off] == 101u8 || s.source[s.off] == 69u8) {
            kind = .Float
            take(s, 1usize)
            if s.off < s.source.len && (s.source[s.off] == 43u8 || s.source[s.off] == 45u8) { take(s, 1usize) }
            let exponent_start = s.off
            while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
            if !digits_are_valid(s.source, exponent_start, s.off, 10u8) {
                while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) { take(s, 1usize) }
                ret token(s, .Invalid, start)
            }
        }
        let suffix_start = s.off
        while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) { take(s, 1usize) }
        if kind == .Float {
            if !float_suffix_is_valid(s.source, suffix_start, s.off) { ret token(s, .Invalid, start) }
        } else {
            if !integer_suffix_is_valid(s.source, suffix_start, s.off) { ret token(s, .Invalid, start) }
        }
        ret token(s, kind, start)
    }

    if c == 34u8 || c == 39u8 {
        let quote = c
        var kind = Kind.Character
        var character_bytes = 0usize
        var valid = true
        if quote == 34u8 { kind = .String }
        take(s, 1usize)
        while s.off < s.source.len && s.source[s.off] != quote && s.source[s.off] != 10u8 && s.source[s.off] != 13u8 {
            let quoted_byte = s.source[s.off]
            if quoted_byte == 0u8 || quoted_byte < 32u8 {
                valid = false
                take(s, 1usize)
                continue
            }
            if s.source[s.off] == 92u8 {
                take(s, 1usize)
                if s.off == s.source.len { ret token(s, .Invalid, start) }
                let escaped = s.source[s.off]
                if escaped != 110u8 && escaped != 116u8 && escaped != 114u8 && escaped != 92u8 && escaped != 34u8 && escaped != 39u8 && escaped != 48u8 && escaped != 120u8 {
                    valid = false
                }
                if escaped == 120u8 {
                    if s.off + 2usize >= s.source.len || !is_hex(s.source[s.off + 1usize]) || !is_hex(s.source[s.off + 2usize]) {
                        valid = false
                    } else {
                        take(s, 2usize)
                    }
                }
                if kind == .Character { character_bytes += 1usize }
            } else {
                if quoted_byte >= 128u8 {
                    let width = utf8_width(s.source, s.off)
                    if width == 0usize {
                        valid = false
                        take_invalid_utf8(s)
                        continue
                    }
                    if kind == .Character { character_bytes += width }
                    take_scalar(s, width)
                    continue
                }
                if kind == .Character { character_bytes += 1usize }
            }
            take(s, 1usize)
        }
        if s.off == s.source.len || s.source[s.off] != quote { ret token(s, .Invalid, start) }
        take(s, 1usize)
        if !valid || (kind == .Character && character_bytes != 1usize) { ret token(s, .Invalid, start) }
        ret token(s, kind, start)
    }

    // The next two bytes, read once (D306): every punctuation token probed up to
    // twenty-eight two- and three-byte operators through a call and a bounds check each.
    var d = 0u8
    var e = 0u8
    if s.off + 1usize < s.source.len { d = s.source[s.off + 1usize] }
    if s.off + 2usize < s.source.len { e = s.source[s.off + 2usize] }
    if c == 46u8 && d == 46u8 && e == 46u8 {
        take(s, 3usize)
        ret token(s, .PunctEllipsis, start)
    }
    if c == 43u8 && d == 37u8 && e == 61u8 {
        take(s, 3usize)
        ret token(s, .PunctAddWrapAssign, start)
    }
    if c == 45u8 && d == 37u8 && e == 61u8 {
        take(s, 3usize)
        ret token(s, .PunctSubWrapAssign, start)
    }
    if c == 42u8 && d == 37u8 && e == 61u8 {
        take(s, 3usize)
        ret token(s, .PunctMulWrapAssign, start)
    }
    if c == 60u8 && d == 60u8 && e == 61u8 {
        take(s, 3usize)
        ret token(s, .PunctShiftLeftAssign, start)
    }
    if c == 62u8 && d == 62u8 && e == 61u8 {
        take(s, 3usize)
        ret token(s, .PunctShiftRightAssign, start)
    }
    if c == 46u8 && d == 46u8 {
        take(s, 2usize)
        ret token(s, .PunctRange, start)
    }
    if c == 45u8 && d == 62u8 {
        take(s, 2usize)
        ret token(s, .PunctArrow, start)
    }
    if c == 61u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctEqEq, start)
    }
    if c == 33u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctBangEq, start)
    }
    if c == 60u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctLtEq, start)
    }
    if c == 62u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctGtEq, start)
    }
    if c == 60u8 && d == 60u8 {
        take(s, 2usize)
        ret token(s, .PunctShiftLeft, start)
    }
    if c == 62u8 && d == 62u8 {
        take(s, 2usize)
        ret token(s, .PunctShiftRight, start)
    }
    if c == 43u8 && d == 37u8 {
        take(s, 2usize)
        ret token(s, .PunctAddWrap, start)
    }
    if c == 45u8 && d == 37u8 {
        take(s, 2usize)
        ret token(s, .PunctSubWrap, start)
    }
    if c == 42u8 && d == 37u8 {
        take(s, 2usize)
        ret token(s, .PunctMulWrap, start)
    }
    if c == 43u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctAddAssign, start)
    }
    if c == 45u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctSubAssign, start)
    }
    if c == 42u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctMulAssign, start)
    }
    if c == 47u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctDivAssign, start)
    }
    if c == 37u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctRemAssign, start)
    }
    if c == 38u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctBitAndAssign, start)
    }
    if c == 94u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctBitXorAssign, start)
    }
    if c == 124u8 && d == 61u8 {
        take(s, 2usize)
        ret token(s, .PunctBitOrAssign, start)
    }
    if c == 38u8 && d == 38u8 {
        take(s, 2usize)
        ret token(s, .PunctAndAnd, start)
    }
    if c == 124u8 && d == 124u8 {
        take(s, 2usize)
        ret token(s, .PunctOrOr, start)
    }

    take(s, 1usize)
    if c == 64u8 { ret token(s, .PunctAt, start) }
    if c == 46u8 { ret token(s, .PunctDot, start) }
    if c == 44u8 { ret token(s, .PunctComma, start) }
    if c == 58u8 { ret token(s, .PunctColon, start) }
    if c == 61u8 { ret token(s, .PunctAssign, start) }
    if c == 40u8 { ret token(s, .PunctLParen, start) }
    if c == 41u8 { ret token(s, .PunctRParen, start) }
    if c == 91u8 { ret token(s, .PunctLBracket, start) }
    if c == 93u8 { ret token(s, .PunctRBracket, start) }
    if c == 123u8 { ret token(s, .PunctLBrace, start) }
    if c == 125u8 { ret token(s, .PunctRBrace, start) }
    if c == 42u8 { ret token(s, .PunctStar, start) }
    if c == 47u8 { ret token(s, .PunctSlash, start) }
    if c == 37u8 { ret token(s, .PunctPercent, start) }
    if c == 43u8 { ret token(s, .PunctPlus, start) }
    if c == 45u8 { ret token(s, .PunctMinus, start) }
    if c == 60u8 { ret token(s, .PunctLt, start) }
    if c == 62u8 { ret token(s, .PunctGt, start) }
    if c == 38u8 { ret token(s, .PunctAmp, start) }
    if c == 94u8 { ret token(s, .PunctCaret, start) }
    if c == 124u8 { ret token(s, .PunctPipe, start) }
    if c == 33u8 { ret token(s, .PunctBang, start) }
    if c == 126u8 { ret token(s, .PunctTilde, start) }
    ret token(s, .Invalid, start)
}

fn validate(source: str) -> err {
    var scanner = init(source)
    while true {
        let current = next(&scanner)
        if current.kind == .Invalid { ret InvalidSource }
        if current.kind == .Eof { ret ok }
    }
}
