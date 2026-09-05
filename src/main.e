// First self-hosted compiler component. Token names mirror grammar revision 1.

use e.io
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

type Token = struct {
    kind: Kind,
    start: usize,
    end: usize,
    line: usize,
    column: usize,
}

type Scanner = struct {
    source: str,
    off: usize,
    line: usize,
    column: usize,
}

error InvalidSource

fn init(source: str) -> Scanner {
    var off = 0usize
    if source.len >= 3usize && source[0usize] == 239u8 && source[1usize] == 187u8 && source[2usize] == 191u8 {
        off = 3usize
    }
    ret Scanner{ source: source, off: off, line: 1usize, column: 1usize }
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

fn is_alnum(c: u8) -> bool {
    ret is_alpha(c) || is_digit(c)
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

fn keyword(source: str, start: usize, end: usize) -> Kind {
    if text_is(source, start, end, "use") { ret .KwUse }
    if text_is(source, start, end, "type") { ret .KwType }
    if text_is(source, start, end, "const") { ret .KwConst }
    if text_is(source, start, end, "var") { ret .KwVar }
    if text_is(source, start, end, "let") { ret .KwLet }
    if text_is(source, start, end, "fn") { ret .KwFn }
    if text_is(source, start, end, "ret") { ret .KwRet }
    if text_is(source, start, end, "if") { ret .KwIf }
    if text_is(source, start, end, "else") { ret .KwElse }
    if text_is(source, start, end, "while") { ret .KwWhile }
    if text_is(source, start, end, "for") { ret .KwFor }
    if text_is(source, start, end, "in") { ret .KwIn }
    if text_is(source, start, end, "switch") { ret .KwSwitch }
    if text_is(source, start, end, "case") { ret .KwCase }
    if text_is(source, start, end, "default") { ret .KwDefault }
    if text_is(source, start, end, "break") { ret .KwBreak }
    if text_is(source, start, end, "continue") { ret .KwContinue }
    if text_is(source, start, end, "defer") { ret .KwDefer }
    if text_is(source, start, end, "try") { ret .KwTry }
    if text_is(source, start, end, "struct") { ret .KwStruct }
    if text_is(source, start, end, "union") { ret .KwUnion }
    if text_is(source, start, end, "enum") { ret .KwEnum }
    if text_is(source, start, end, "error") { ret .KwError }
    if text_is(source, start, end, "when") { ret .KwWhen }
    if text_is(source, start, end, "true") { ret .KwTrue }
    if text_is(source, start, end, "false") { ret .KwFalse }
    if text_is(source, start, end, "nil") { ret .KwNil }
    if text_is(source, start, end, "ok") { ret .KwOk }
    if text_is(source, start, end, "as") { ret .KwAs }
    if text_is(source, start, end, "zero") { ret .KwZero }
    if text_is(source, start, end, "undef") { ret .KwUndef }
    if text_is(source, start, end, "extern") { ret .KwExtern }
    if text_is(source, start, end, "unreachable") { ret .KwUnreachable }
    if text_is(source, start, end, "shared") { ret .KwShared }
    if end - start == 1usize && source[start] == 95u8 { ret .PunctUnderscore }
    ret .Identifier
}

fn token(s: *Scanner, kind: Kind, start: usize, line: usize, column: usize) -> Token {
    ret Token{ kind: kind, start: start, end: s.off, line: line, column: column }
}

fn has(s: *Scanner, a: u8, b: u8) -> bool {
    ret s.off + 1usize < s.source.len && s.source[s.off] == a && s.source[s.off + 1usize] == b
}

fn has3(s: *Scanner, a: u8, b: u8, c: u8) -> bool {
    ret s.off + 2usize < s.source.len && s.source[s.off] == a && s.source[s.off + 1usize] == b && s.source[s.off + 2usize] == c
}

fn take(s: *Scanner, n: usize) {
    s.off += n
    s.column += n
}

fn next(s: *Scanner) -> Token {
    while s.off < s.source.len {
        let c = s.source[s.off]
        if c == 32u8 {
            take(s, 1usize)
            continue
        }
        if has(s, 47u8, 47u8) {
            take(s, 2usize)
            while s.off < s.source.len && s.source[s.off] != 10u8 && s.source[s.off] != 13u8 {
                take(s, 1usize)
            }
            continue
        }
        break
    }

    let start = s.off
    let line = s.line
    let column = s.column
    if s.off == s.source.len { ret token(s, .Eof, start, line, column) }
    let c = s.source[s.off]

    if c == 10u8 || c == 13u8 {
        if c == 13u8 && s.off + 1usize < s.source.len && s.source[s.off + 1usize] == 10u8 {
            s.off += 2usize
        } else {
            s.off += 1usize
        }
        s.line += 1usize
        s.column = 1usize
        ret token(s, .Newline, start, line, column)
    }

    if c == 114u8 && s.off + 1usize < s.source.len && (s.source[s.off + 1usize] == 34u8 || s.source[s.off + 1usize] == 35u8) {
        var delimiter = s.off + 1usize
        var hashes = 0usize
        while delimiter < s.source.len && s.source[delimiter] == 35u8 && hashes < 9usize {
            delimiter += 1usize
            hashes += 1usize
        }
        if hashes <= 8usize && delimiter < s.source.len && s.source[delimiter] == 34u8 {
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
                        ret token(s, .RawString, start, line, column)
                    }
                }
                if s.source[s.off] == 10u8 || s.source[s.off] == 13u8 {
                    if s.source[s.off] == 13u8 && s.off + 1usize < s.source.len && s.source[s.off + 1usize] == 10u8 {
                        s.off += 2usize
                    } else {
                        s.off += 1usize
                    }
                    s.line += 1usize
                    s.column = 1usize
                } else {
                    take(s, 1usize)
                }
            }
            ret token(s, .Invalid, start, line, column)
        }
    }

    if is_alpha(c) {
        take(s, 1usize)
        while s.off < s.source.len && is_alnum(s.source[s.off]) { take(s, 1usize) }
        ret token(s, keyword(s.source, start, s.off), start, line, column)
    }

    if is_digit(c) {
        var kind = Kind.Integer
        take(s, 1usize)
        if c == 48u8 && s.off < s.source.len && (s.source[s.off] == 120u8 || s.source[s.off] == 111u8 || s.source[s.off] == 98u8) {
            take(s, 1usize)
            while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
            ret token(s, kind, start, line, column)
        }
        while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
            take(s, 1usize)
        }
        if s.off + 1usize < s.source.len && s.source[s.off] == 46u8 && s.source[s.off + 1usize] != 46u8 && is_digit(s.source[s.off + 1usize]) {
            kind = .Float
            take(s, 1usize)
            while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
        }
        if s.off < s.source.len && (s.source[s.off] == 101u8 || s.source[s.off] == 69u8) {
            kind = .Float
            take(s, 1usize)
            if s.off < s.source.len && (s.source[s.off] == 43u8 || s.source[s.off] == 45u8) { take(s, 1usize) }
            while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
                take(s, 1usize)
            }
        }
        while s.off < s.source.len && is_alnum(s.source[s.off]) { take(s, 1usize) }
        ret token(s, kind, start, line, column)
    }

    if c == 34u8 || c == 39u8 {
        let quote = c
        var kind = Kind.Character
        if quote == 34u8 { kind = .String }
        take(s, 1usize)
        while s.off < s.source.len && s.source[s.off] != quote && s.source[s.off] != 10u8 && s.source[s.off] != 13u8 {
            if s.source[s.off] == 92u8 {
                take(s, 1usize)
                if s.off == s.source.len { ret token(s, .Invalid, start, line, column) }
                let escaped = s.source[s.off]
                if escaped != 110u8 && escaped != 116u8 && escaped != 114u8 && escaped != 92u8 && escaped != 34u8 && escaped != 39u8 && escaped != 48u8 && escaped != 120u8 {
                    take(s, 1usize)
                    ret token(s, .Invalid, start, line, column)
                }
                if escaped == 120u8 {
                    if s.off + 2usize >= s.source.len || !is_hex(s.source[s.off + 1usize]) || !is_hex(s.source[s.off + 2usize]) {
                        take(s, 1usize)
                        ret token(s, .Invalid, start, line, column)
                    }
                    take(s, 2usize)
                }
            }
            take(s, 1usize)
        }
        if s.off == s.source.len || s.source[s.off] != quote { ret token(s, .Invalid, start, line, column) }
        take(s, 1usize)
        ret token(s, kind, start, line, column)
    }

    if has3(s, 46u8, 46u8, 46u8) {
        take(s, 3usize)
        ret token(s, .PunctEllipsis, start, line, column)
    }
    if has3(s, 43u8, 37u8, 61u8) {
        take(s, 3usize)
        ret token(s, .PunctAddWrapAssign, start, line, column)
    }
    if has3(s, 45u8, 37u8, 61u8) {
        take(s, 3usize)
        ret token(s, .PunctSubWrapAssign, start, line, column)
    }
    if has3(s, 42u8, 37u8, 61u8) {
        take(s, 3usize)
        ret token(s, .PunctMulWrapAssign, start, line, column)
    }
    if has3(s, 60u8, 60u8, 61u8) {
        take(s, 3usize)
        ret token(s, .PunctShiftLeftAssign, start, line, column)
    }
    if has3(s, 62u8, 62u8, 61u8) {
        take(s, 3usize)
        ret token(s, .PunctShiftRightAssign, start, line, column)
    }
    if has(s, 46u8, 46u8) {
        take(s, 2usize)
        ret token(s, .PunctRange, start, line, column)
    }
    if has(s, 45u8, 62u8) {
        take(s, 2usize)
        ret token(s, .PunctArrow, start, line, column)
    }
    if has(s, 61u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctEqEq, start, line, column)
    }
    if has(s, 33u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctBangEq, start, line, column)
    }
    if has(s, 60u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctLtEq, start, line, column)
    }
    if has(s, 62u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctGtEq, start, line, column)
    }
    if has(s, 60u8, 60u8) {
        take(s, 2usize)
        ret token(s, .PunctShiftLeft, start, line, column)
    }
    if has(s, 62u8, 62u8) {
        take(s, 2usize)
        ret token(s, .PunctShiftRight, start, line, column)
    }
    if has(s, 43u8, 37u8) {
        take(s, 2usize)
        ret token(s, .PunctAddWrap, start, line, column)
    }
    if has(s, 45u8, 37u8) {
        take(s, 2usize)
        ret token(s, .PunctSubWrap, start, line, column)
    }
    if has(s, 42u8, 37u8) {
        take(s, 2usize)
        ret token(s, .PunctMulWrap, start, line, column)
    }
    if has(s, 43u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctAddAssign, start, line, column)
    }
    if has(s, 45u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctSubAssign, start, line, column)
    }
    if has(s, 42u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctMulAssign, start, line, column)
    }
    if has(s, 47u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctDivAssign, start, line, column)
    }
    if has(s, 37u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctRemAssign, start, line, column)
    }
    if has(s, 38u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctBitAndAssign, start, line, column)
    }
    if has(s, 94u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctBitXorAssign, start, line, column)
    }
    if has(s, 124u8, 61u8) {
        take(s, 2usize)
        ret token(s, .PunctBitOrAssign, start, line, column)
    }
    if has(s, 38u8, 38u8) {
        take(s, 2usize)
        ret token(s, .PunctAndAnd, start, line, column)
    }
    if has(s, 124u8, 124u8) {
        take(s, 2usize)
        ret token(s, .PunctOrOr, start, line, column)
    }

    take(s, 1usize)
    if c == 64u8 { ret token(s, .PunctAt, start, line, column) }
    if c == 46u8 { ret token(s, .PunctDot, start, line, column) }
    if c == 44u8 { ret token(s, .PunctComma, start, line, column) }
    if c == 58u8 { ret token(s, .PunctColon, start, line, column) }
    if c == 61u8 { ret token(s, .PunctAssign, start, line, column) }
    if c == 40u8 { ret token(s, .PunctLParen, start, line, column) }
    if c == 41u8 { ret token(s, .PunctRParen, start, line, column) }
    if c == 91u8 { ret token(s, .PunctLBracket, start, line, column) }
    if c == 93u8 { ret token(s, .PunctRBracket, start, line, column) }
    if c == 123u8 { ret token(s, .PunctLBrace, start, line, column) }
    if c == 125u8 { ret token(s, .PunctRBrace, start, line, column) }
    if c == 42u8 { ret token(s, .PunctStar, start, line, column) }
    if c == 47u8 { ret token(s, .PunctSlash, start, line, column) }
    if c == 37u8 { ret token(s, .PunctPercent, start, line, column) }
    if c == 43u8 { ret token(s, .PunctPlus, start, line, column) }
    if c == 45u8 { ret token(s, .PunctMinus, start, line, column) }
    if c == 60u8 { ret token(s, .PunctLt, start, line, column) }
    if c == 62u8 { ret token(s, .PunctGt, start, line, column) }
    if c == 38u8 { ret token(s, .PunctAmp, start, line, column) }
    if c == 94u8 { ret token(s, .PunctCaret, start, line, column) }
    if c == 124u8 { ret token(s, .PunctPipe, start, line, column) }
    if c == 33u8 { ret token(s, .PunctBang, start, line, column) }
    if c == 126u8 { ret token(s, .PunctTilde, start, line, column) }
    ret token(s, .Invalid, start, line, column)
}

fn validate(source: str) -> err {
    var scanner = init(source)
    while true {
        let current = next(&scanner)
        if current.kind == .Invalid { ret InvalidSource }
        if current.kind == .Eof { ret ok }
    }
}

fn expect(s: *Scanner, kind: Kind, start: usize, end: usize, line: usize, column: usize) -> err {
    let current = next(s)
    if current.kind != kind || current.start != start || current.end != end || current.line != line || current.column != column {
        ret InvalidSource
    }
    ret ok
}

fn self_test() -> err {
    var basic = init("use e.io\r\nfn main() -> err { // note\n    ret ok\n}\n")
    try expect(&basic, .KwUse, 0usize, 3usize, 1usize, 1usize)
    try expect(&basic, .Identifier, 4usize, 5usize, 1usize, 5usize)
    try expect(&basic, .PunctDot, 5usize, 6usize, 1usize, 6usize)
    try expect(&basic, .Identifier, 6usize, 8usize, 1usize, 7usize)
    try expect(&basic, .Newline, 8usize, 10usize, 1usize, 9usize)
    try expect(&basic, .KwFn, 10usize, 12usize, 2usize, 1usize)
    try expect(&basic, .Identifier, 13usize, 17usize, 2usize, 4usize)
    try expect(&basic, .PunctLParen, 17usize, 18usize, 2usize, 8usize)
    try expect(&basic, .PunctRParen, 18usize, 19usize, 2usize, 9usize)
    try expect(&basic, .PunctArrow, 20usize, 22usize, 2usize, 11usize)
    try expect(&basic, .Identifier, 23usize, 26usize, 2usize, 14usize)
    try expect(&basic, .PunctLBrace, 27usize, 28usize, 2usize, 18usize)
    try expect(&basic, .Newline, 36usize, 37usize, 2usize, 27usize)
    try expect(&basic, .KwRet, 41usize, 44usize, 3usize, 5usize)
    try expect(&basic, .KwOk, 45usize, 47usize, 3usize, 9usize)
    try expect(&basic, .Newline, 47usize, 48usize, 3usize, 11usize)
    try expect(&basic, .PunctRBrace, 48usize, 49usize, 4usize, 1usize)
    try expect(&basic, .Newline, 49usize, 50usize, 4usize, 2usize)
    try expect(&basic, .Eof, 50usize, 50usize, 5usize, 1usize)

    var operators = init("... .. -> == != <= >= << >> +% -% *% += -= *= /= %= +%= -%= *%= <<= >>= &= ^= |= && ||")
    try expect(&operators, .PunctEllipsis, 0usize, 3usize, 1usize, 1usize)
    try expect(&operators, .PunctRange, 4usize, 6usize, 1usize, 5usize)
    try expect(&operators, .PunctArrow, 7usize, 9usize, 1usize, 8usize)
    var count = 3usize
    while true {
        let current = next(&operators)
        if current.kind == .Eof { break }
        if current.kind == .Invalid { ret InvalidSource }
        count += 1usize
    }
    if count != 27usize { ret InvalidSource }

    var literals = init("_ 123u64 1.5f32 \"x\\n\" 'a'")
    try expect(&literals, .PunctUnderscore, 0usize, 1usize, 1usize, 1usize)
    try expect(&literals, .Integer, 2usize, 8usize, 1usize, 3usize)
    try expect(&literals, .Float, 9usize, 15usize, 1usize, 10usize)
    try expect(&literals, .String, 16usize, 21usize, 1usize, 17usize)
    try expect(&literals, .Character, 22usize, 25usize, 1usize, 23usize)
    try expect(&literals, .Eof, 25usize, 25usize, 1usize, 26usize)

    var advanced = init("1e-9f64 r#\"a\n\"#")
    try expect(&advanced, .Float, 0usize, 7usize, 1usize, 1usize)
    try expect(&advanced, .RawString, 8usize, 15usize, 1usize, 9usize)
    try expect(&advanced, .Eof, 15usize, 15usize, 2usize, 3usize)

    let invalid = validate("fn #")
    if invalid != InvalidSource { ret InvalidSource }
    let invalid_escape = validate("\"\\q\"")
    if invalid_escape != InvalidSource { ret InvalidSource }
    let invalid_tab = validate("fn\tmain")
    if invalid_tab != InvalidSource { ret InvalidSource }
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && same(args[1usize], "self-test") {
        try self_test()
        try io.print("selfhost lexer ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "scan") {
        let scan_error = validate(args[2usize])
        if scan_error != ok { ret scan_error }
        try io.print("scan ok\n")
        ret ok
    }
    try io.print("usage: neper-self scan SOURCE\n")
    ret ok
}
