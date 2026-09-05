// First self-hosted compiler component. Token names mirror grammar revision 1.

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

fn is_base_digit(c: u8, base: u8) -> bool {
    if base == 2u8 { ret c == 48u8 || c == 49u8 }
    if base == 8u8 { ret c >= 48u8 && c <= 55u8 }
    if base == 10u8 { ret is_digit(c) }
    ret is_hex(c)
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
                ret token(s, .Invalid, start, line, column)
            }
            ret token(s, kind, start, line, column)
        }
        let integer_start = start
        while s.off < s.source.len && (is_digit(s.source[s.off]) || s.source[s.off] == 95u8) {
            take(s, 1usize)
        }
        let integer_end = s.off
        if !digits_are_valid(s.source, integer_start, integer_end, 10u8) {
            while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) { take(s, 1usize) }
            ret token(s, .Invalid, start, line, column)
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
                ret token(s, .Invalid, start, line, column)
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
                ret token(s, .Invalid, start, line, column)
            }
        }
        let suffix_start = s.off
        while s.off < s.source.len && (is_alnum(s.source[s.off]) || s.source[s.off] == 95u8) { take(s, 1usize) }
        if kind == .Float {
            if !float_suffix_is_valid(s.source, suffix_start, s.off) { ret token(s, .Invalid, start, line, column) }
        } else {
            if !integer_suffix_is_valid(s.source, suffix_start, s.off) { ret token(s, .Invalid, start, line, column) }
        }
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
