// The ECMAScript regular expression engine (browser tracker 5.10): a backtracking matcher over UTF-16 code units with
// backreferences, lookahead and lookbehind, named groups, lazy and greedy quantifiers, the `i m s u y g d` flags and the legacy
// (Annex B) syntax of non-unicode patterns. `\p{..}` property escapes are not implemented yet.
//
// The pattern parses into flat nodes; matching recurses over them with an explicit continuation chain (`Cont`) so a sequence,
// a group end or a loop iteration continues exactly where backtracking needs it. Lookbehind matches backwards.

use e.data.list as list
use e.js.lex as lex
use e.mem
use e.str
use e.text.unicode as unicode

const NONE: u32 = 4294967295u32

// Node kinds.
const R_EMPTY: u8 = 0u8
const R_CHAR: u8 = 1u8
const R_ANY: u8 = 2u8
const R_CLASS: u8 = 3u8
const R_SEQ: u8 = 4u8
const R_ALT: u8 = 5u8
const R_GROUP: u8 = 6u8
const R_REPEAT: u8 = 7u8
const R_BOL: u8 = 8u8
const R_EOL: u8 = 9u8
const R_WORDB: u8 = 10u8
const R_NWORDB: u8 = 11u8
const R_BACKREF: u8 = 12u8
const R_LOOK: u8 = 13u8
const R_NAMEDREF: u8 = 14u8

// `mods`: bit 0 set when a modifier group `(?ims-ims:...)` governs the node, then bit 1 ignore-case, bit 2 multiline, bit 3 dot-all.
type Node = struct { kind: u8, a: u32, b: u32, c: u32, d: u32, greedy: bool, neg: bool, back: bool, mods: u8 }

type Range = struct { lo: u32, hi: u32 }

// A character class: ranges plus negation.
type Class = struct { first: u32, count: u32, neg: bool }

type Regex = struct {
    nodes: []const Node, kids: []const u32, ranges: []const Range, classes: []const Class, root: u32,
    groups: u32, names: []const str, ignore_case: bool, multiline: bool, dot_all: bool, unicode: bool, sticky: bool, global: bool,
    has_indices: bool, unicode_sets: bool
}

type Parse = struct {
    a: *mem.Arena, src: []const u16, i: usize, nodes: list.List[Node], kids: list.List[u32], ranges: list.List[Range],
    classes: list.List[Class], names: list.List[str], refs: list.List[str], groups: u32, unicode: bool, named: bool, message: str, ignore_case: bool,
    total_groups: u32, multiline: bool, dot_all: bool, mods: u8
}

error SyntaxErr

fn fail(p: *Parse, m: str) -> err {
    p.message = m
    ret SyntaxErr
}

fn mk(p: *Parse, kind: u8) -> (u32, err) {
    let n = Node { kind: kind, a: 0u32, b: 0u32, c: 0u32, d: 0u32, greedy: true, neg: false, back: false, mods: p.mods }
    let id = u32(p.nodes.len)
    try list.push[Node](&p.nodes, n)
    ret (id, ok)
}

fn nd(p: *Parse, id: u32) -> *Node { ret &p.nodes.items[usize(id)] }

fn peek(p: *const Parse) -> i64 {
    if p.i < p.src.len { ret i64(p.src[p.i]) }
    ret -1i64
}

fn peek_at(p: *const Parse, k: usize) -> i64 {
    if p.i + k < p.src.len { ret i64(p.src[p.i + k]) }
    ret -1i64
}

fn eat(p: *Parse, c: u8) -> bool {
    if p.i < p.src.len && p.src[p.i] == u16(c) {
        p.i += 1usize
        ret true
    }
    ret false
}

// The code point at the cursor (a surrogate pair joins in unicode mode) and its unit length.
fn next_cp(p: *Parse) -> (u32, usize) {
    let u = u32(p.src[p.i])
    if p.unicode && u >= 55296u32 && u <= 56319u32 && p.i + 1usize < p.src.len {
        let lo = u32(p.src[p.i + 1usize])
        if lo >= 56320u32 && lo <= 57343u32 { ret (65536u32 + ((u - 55296u32) << 10u32) + (lo - 56320u32), 2usize) }
    }
    ret (u, 1usize)
}

fn is_digit(c: i64) -> bool { ret c >= 48i64 && c <= 57i64 }

fn hex_val(c: i64) -> i64 {
    if c >= 48i64 && c <= 57i64 { ret c - 48i64 }
    if c >= 97i64 && c <= 102i64 { ret c - 87i64 }
    if c >= 65i64 && c <= 70i64 { ret c - 55i64 }
    ret -1i64
}

fn add_range(p: *Parse, lo: u32, hi: u32) -> err {
    ret list.push[Range](&p.ranges, Range { lo: lo, hi: hi })
}

fn add_class_escape(p: *Parse, c: u8) -> err {
    // d D w W s S as ranges (negated forms are complements within the code point space).
    var neg = false
    var kind = c
    if c == 68u8 || c == 87u8 || c == 83u8 {
        neg = true
        kind = c + 32u8
    }
    var lows: [16]u32 = zero
    var highs: [16]u32 = zero
    var n = 0usize
    if kind == 100u8 {
        lows[0usize] = 48u32
        highs[0usize] = 57u32
        n = 1usize
    } else if kind == 119u8 {
        lows[0usize] = 48u32
        highs[0usize] = 57u32
        lows[1usize] = 65u32
        highs[1usize] = 90u32
        lows[2usize] = 95u32
        highs[2usize] = 95u32
        lows[3usize] = 97u32
        highs[3usize] = 122u32
        n = 4usize
    } else {
        lows[0usize] = 9u32
        highs[0usize] = 13u32
        lows[1usize] = 32u32
        highs[1usize] = 32u32
        lows[2usize] = 160u32
        highs[2usize] = 160u32
        lows[3usize] = 5760u32
        highs[3usize] = 5760u32
        lows[4usize] = 8192u32
        highs[4usize] = 8202u32
        lows[5usize] = 8232u32
        highs[5usize] = 8233u32
        lows[6usize] = 8239u32
        highs[6usize] = 8239u32
        lows[7usize] = 8287u32
        highs[7usize] = 8287u32
        lows[8usize] = 12288u32
        highs[8usize] = 12288u32
        lows[9usize] = 65279u32
        highs[9usize] = 65279u32
        n = 10usize
    }
    if !neg {
        var i = 0usize
        while i < n {
            try add_range(p, lows[i], highs[i])
            i += 1usize
        }
        ret ok
    }
    // Complement.
    var prev = 0u32
    var i2 = 0usize
    while i2 < n {
        if lows[i2] > prev { try add_range(p, prev, lows[i2] - 1u32) }
        prev = highs[i2] + 1u32
        i2 += 1usize
    }
    try add_range(p, prev, 1114111u32)
    ret ok
}

// Parses a `\` escape inside or outside a class; answers (code point, is_class_escape, class letter).
fn parse_escape_value(p: *Parse, in_class: bool) -> (u32, bool, u8, err) {
    // The `\` is consumed. Returns (value, is_class_escape, letter, err).
    if p.i >= p.src.len { ret (0u32, false, 0u8, fail(p, "\\ at end of pattern")) }
    let c = u32(p.src[p.i])
    p.i += 1usize
    if c == 100u32 || c == 68u32 || c == 119u32 || c == 87u32 || c == 115u32 || c == 83u32 { ret (0u32, true, u8(c), ok) }
    if c == 110u32 { ret (10u32, false, 0u8, ok) }
    if c == 114u32 { ret (13u32, false, 0u8, ok) }
    if c == 116u32 { ret (9u32, false, 0u8, ok) }
    if c == 118u32 { ret (11u32, false, 0u8, ok) }
    if c == 102u32 { ret (12u32, false, 0u8, ok) }
    if c == 48u32 && !is_digit(peek(p)) { ret (0u32, false, 0u8, ok) }
    if c == 99u32 {
        // \cX control letter.
        let l = peek(p)
        if (l >= 65i64 && l <= 90i64) || (l >= 97i64 && l <= 122i64) {
            p.i += 1usize
            ret (u32(l % 32i64), false, 0u8, ok)
        }
        if !p.unicode {
            // Legacy: the backslash stands for itself and `c` is read next.
            p.i -= 1usize
            ret (92u32, false, 0u8, ok)
        }
        ret (0u32, false, 0u8, fail(p, "Invalid unicode escape"))
    }
    if c == 120u32 {
        let h1 = hex_val(peek(p))
        let h2 = hex_val(peek_at(p, 1usize))
        if h1 >= 0i64 && h2 >= 0i64 {
            p.i += 2usize
            ret (u32(h1 * 16i64 + h2), false, 0u8, ok)
        }
        if p.unicode { ret (0u32, false, 0u8, fail(p, "Invalid escape")) }
        ret (120u32, false, 0u8, ok)
    }
    if c == 117u32 {
        // \uXXXX, \u{X..} in unicode mode, and a surrogate pair 😀 joins in unicode mode.
        if p.unicode && peek(p) == 123i64 {
            var j = p.i + 1usize
            var v = 0i64
            var any = false
            while j < p.src.len && p.src[j] != 125u16 {
                let h = hex_val(i64(p.src[j]))
                if h < 0i64 { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
                v = v * 16i64 + h
                if v > 1114111i64 { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
                any = true
                j += 1usize
            }
            if j >= p.src.len || !any { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
            p.i = j + 1usize
            ret (u32(v), false, 0u8, ok)
        }
        var v2 = 0i64
        var k = 0usize
        var good = true
        while k < 4usize {
            let h2 = hex_val(peek_at(p, k))
            if h2 < 0i64 { good = false }
            v2 = v2 * 16i64 + h2
            k += 1usize
        }
        if good {
            p.i += 4usize
            if p.unicode && v2 >= 55296i64 && v2 <= 56319i64 && peek(p) == 92i64 && peek_at(p, 1usize) == 117i64 {
                var lo = 0i64
                var kk = 0usize
                var good2 = true
                while kk < 4usize {
                    let h3 = hex_val(peek_at(p, 2usize + kk))
                    if h3 < 0i64 { good2 = false }
                    lo = lo * 16i64 + h3
                    kk += 1usize
                }
                if good2 && lo >= 56320i64 && lo <= 57343i64 {
                    p.i += 6usize
                    ret (u32(65536i64 + (v2 - 55296i64) * 1024i64 + (lo - 56320i64)), false, 0u8, ok)
                }
            }
            ret (u32(v2), false, 0u8, ok)
        }
        if p.unicode { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
        ret (117u32, false, 0u8, ok)
    }
    if c >= 49u32 && c <= 57u32 {
        if in_class {
            if p.unicode { ret (0u32, false, 0u8, fail(p, "Invalid class escape")) }
            // Legacy octal in a class.
            if c >= 56u32 { ret (c, false, 0u8, ok) }
            var v3 = c - 48u32
            var n = 0usize
            while n < 2usize && peek(p) >= 48i64 && peek(p) <= 55i64 && v3 * 8u32 + u32(peek(p) - 48i64) <= 255u32 {
                v3 = v3 * 8u32 + u32(peek(p) - 48i64)
                p.i += 1usize
                n += 1usize
            }
            ret (v3, false, 0u8, ok)
        }
    }
    if c == 48u32 {
        // \0 followed by a digit: legacy octal.
        if p.unicode { ret (0u32, false, 0u8, fail(p, "Invalid decimal escape")) }
        var v4 = 0u32
        var n2 = 0usize
        while n2 < 2usize && peek(p) >= 48i64 && peek(p) <= 55i64 && v4 * 8u32 + u32(peek(p) - 48i64) <= 255u32 {
            v4 = v4 * 8u32 + u32(peek(p) - 48i64)
            p.i += 1usize
            n2 += 1usize
        }
        ret (v4, false, 0u8, ok)
    }
    if in_class && c == 98u32 { ret (8u32, false, 0u8, ok) }
    if in_class && c == 45u32 && p.unicode { ret (45u32, false, 0u8, ok) }
    if p.unicode {
        // Only syntax characters (and `/`) may be escaped.
        if c == 94u32 || c == 36u32 || c == 92u32 || c == 46u32 || c == 42u32 || c == 43u32 || c == 63u32 || c == 40u32 || c == 41u32 || c == 91u32 || c == 93u32 || c == 123u32 || c == 125u32 || c == 124u32 || c == 47u32 { ret (c, false, 0u8, ok) }
        ret (0u32, false, 0u8, fail(p, "Invalid escape"))
    }
    // Legacy: an unknown escape is the character itself (a surrogate pair stays whole).
    if c >= 55296u32 && c <= 56319u32 && p.i < p.src.len { }
    ret (c, false, 0u8, ok)
}

// --- Unicode property escapes: general categories and a few binary properties (scripts are not available).

fn gc_mask_of(name: str) -> (u32, bool) {
    // Bit i is category i of `unicode.Category` (Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn).
    if str.eq(name, "Lu") || str.eq(name, "Uppercase_Letter") { ret (1u32, true) }
    if str.eq(name, "Ll") || str.eq(name, "Lowercase_Letter") { ret (2u32, true) }
    if str.eq(name, "Lt") || str.eq(name, "Titlecase_Letter") { ret (4u32, true) }
    if str.eq(name, "LC") || str.eq(name, "Cased_Letter") { ret (7u32, true) }
    if str.eq(name, "Lm") || str.eq(name, "Modifier_Letter") { ret (8u32, true) }
    if str.eq(name, "Lo") || str.eq(name, "Other_Letter") { ret (16u32, true) }
    if str.eq(name, "L") || str.eq(name, "Letter") { ret (31u32, true) }
    if str.eq(name, "Mn") || str.eq(name, "Nonspacing_Mark") { ret (32u32, true) }
    if str.eq(name, "Mc") || str.eq(name, "Spacing_Mark") { ret (64u32, true) }
    if str.eq(name, "Me") || str.eq(name, "Enclosing_Mark") { ret (128u32, true) }
    if str.eq(name, "M") || str.eq(name, "Mark") || str.eq(name, "Combining_Mark") { ret (224u32, true) }
    if str.eq(name, "Nd") || str.eq(name, "Decimal_Number") || str.eq(name, "digit") { ret (256u32, true) }
    if str.eq(name, "Nl") || str.eq(name, "Letter_Number") { ret (512u32, true) }
    if str.eq(name, "No") || str.eq(name, "Other_Number") { ret (1024u32, true) }
    if str.eq(name, "N") || str.eq(name, "Number") { ret (1792u32, true) }
    if str.eq(name, "Pc") || str.eq(name, "Connector_Punctuation") { ret (2048u32, true) }
    if str.eq(name, "Pd") || str.eq(name, "Dash_Punctuation") { ret (4096u32, true) }
    if str.eq(name, "Ps") || str.eq(name, "Open_Punctuation") { ret (8192u32, true) }
    if str.eq(name, "Pe") || str.eq(name, "Close_Punctuation") { ret (16384u32, true) }
    if str.eq(name, "Pi") || str.eq(name, "Initial_Punctuation") { ret (32768u32, true) }
    if str.eq(name, "Pf") || str.eq(name, "Final_Punctuation") { ret (65536u32, true) }
    if str.eq(name, "Po") || str.eq(name, "Other_Punctuation") { ret (131072u32, true) }
    if str.eq(name, "P") || str.eq(name, "Punctuation") || str.eq(name, "punct") { ret (260096u32, true) }
    if str.eq(name, "Sm") || str.eq(name, "Math_Symbol") { ret (262144u32, true) }
    if str.eq(name, "Sc") || str.eq(name, "Currency_Symbol") { ret (524288u32, true) }
    if str.eq(name, "Sk") || str.eq(name, "Modifier_Symbol") { ret (1048576u32, true) }
    if str.eq(name, "So") || str.eq(name, "Other_Symbol") { ret (2097152u32, true) }
    if str.eq(name, "S") || str.eq(name, "Symbol") { ret (3932160u32, true) }
    if str.eq(name, "Zs") || str.eq(name, "Space_Separator") { ret (4194304u32, true) }
    if str.eq(name, "Zl") || str.eq(name, "Line_Separator") { ret (8388608u32, true) }
    if str.eq(name, "Zp") || str.eq(name, "Paragraph_Separator") { ret (16777216u32, true) }
    if str.eq(name, "Z") || str.eq(name, "Separator") { ret (29360128u32, true) }
    if str.eq(name, "Cc") || str.eq(name, "Control") || str.eq(name, "cntrl") { ret (33554432u32, true) }
    if str.eq(name, "Cf") || str.eq(name, "Format") { ret (67108864u32, true) }
    if str.eq(name, "Cs") || str.eq(name, "Surrogate") { ret (134217728u32, true) }
    if str.eq(name, "Co") || str.eq(name, "Private_Use") { ret (268435456u32, true) }
    if str.eq(name, "Cn") || str.eq(name, "Unassigned") { ret (536870912u32, true) }
    if str.eq(name, "C") || str.eq(name, "Other") { ret (1040187392u32, true) }
    ret (0u32, false)
}

// Special (binary) properties: 1 Any, 2 ASCII, 3 Assigned, 4 Alphabetic, 5 White_Space, 6 ASCII_Hex_Digit, 7 Uppercase, 8 Lowercase.
fn binary_prop_of(name: str) -> u32 {
    if str.eq(name, "Any") { ret 1u32 }
    if str.eq(name, "ASCII") { ret 2u32 }
    if str.eq(name, "Assigned") { ret 3u32 }
    if str.eq(name, "Alphabetic") || str.eq(name, "Alpha") { ret 4u32 }
    if str.eq(name, "White_Space") || str.eq(name, "space") { ret 5u32 }
    if str.eq(name, "ASCII_Hex_Digit") || str.eq(name, "AHex") { ret 6u32 }
    if str.eq(name, "Uppercase") || str.eq(name, "Upper") { ret 7u32 }
    if str.eq(name, "Lowercase") || str.eq(name, "Lower") { ret 8u32 }
    ret 0u32
}

// Parses `{Name}` or `{Name=Value}` after the property escape letter; answers the encoded (lo, hi) range entry: lo has the top
// bit set, bit 30 negates, bits 24-29 pick a binary property (0 = general category mask in `hi`).
fn parse_property(p: *Parse, negated: bool) -> (u32, u32, err) {
    if !eat(p, 123u8) { ret (0u32, 0u32, fail(p, "Invalid property name")) }
    let start = p.i
    while p.i < p.src.len && p.src[p.i] != 125u16 { p.i += 1usize }
    if p.i >= p.src.len { ret (0u32, 0u32, fail(p, "Invalid property name")) }
    let (b, be) = str.builder(p.a, p.i - start + 2usize)
    if be != ok { ret (0u32, 0u32, be) }
    var out = b
    var k = start
    while k < p.i {
        let c = u32(p.src[k])
        if c >= 128u32 { ret (0u32, 0u32, fail(p, "Invalid property name")) }
        let pe = str.push_byte(&out, u8(c))
        k += 1usize
    }
    let text = str.done(&out)
    p.i += 1usize
    var neg_bit = 0u32
    if negated { neg_bit = 1073741824u32 }
    let (eq_at, has_eq) = str.find(text, "=")
    if has_eq {
        let key = text[0usize..eq_at]
        let val = text[eq_at + 1usize..]
        if str.eq(key, "General_Category") || str.eq(key, "gc") {
            let (mask, good) = gc_mask_of(val)
            if !good { ret (0u32, 0u32, fail(p, "Invalid property name")) }
            ret (2147483648u32 | neg_bit, mask, ok)
        }
        ret (0u32, 0u32, fail(p, "Invalid property name"))
    }
    let (mask2, good2) = gc_mask_of(text)
    if good2 { ret (2147483648u32 | neg_bit, mask2, ok) }
    let bp = binary_prop_of(text)
    if bp == 0u32 { ret (0u32, 0u32, fail(p, "Invalid property name")) }
    ret (2147483648u32 | neg_bit | (bp << 24u32), 0u32, ok)
}

fn property_matches(lo: u32, hi: u32, c: u32) -> bool {
    var result = false
    let kind = (lo >> 24u32) & 63u32
    if kind == 0u32 {
        let idx = category_index(unicode.category(c))
        result = ((hi >> idx) & 1u32) != 0u32
    } else if kind == 1u32 {
        result = true
    } else if kind == 2u32 {
        result = c < 128u32
    } else if kind == 3u32 {
        result = category_index(unicode.category(c)) != 29u32
    } else if kind == 4u32 {
        result = unicode.is_alphabetic(c)
    } else if kind == 5u32 {
        result = unicode.is_whitespace(c)
    } else if kind == 6u32 {
        result = (c >= 48u32 && c <= 57u32) || (c >= 65u32 && c <= 70u32) || (c >= 97u32 && c <= 102u32)
    } else if kind == 7u32 {
        result = category_index(unicode.category(c)) == 0u32
    } else if kind == 8u32 {
        result = category_index(unicode.category(c)) == 1u32
    }
    if (lo & 1073741824u32) != 0u32 { ret !result }
    ret result
}

fn category_index(cat: unicode.Category) -> u32 {
    if cat == .Lu { ret 0u32 }
    if cat == .Ll { ret 1u32 }
    if cat == .Lt { ret 2u32 }
    if cat == .Lm { ret 3u32 }
    if cat == .Lo { ret 4u32 }
    if cat == .Mn { ret 5u32 }
    if cat == .Mc { ret 6u32 }
    if cat == .Me { ret 7u32 }
    if cat == .Nd { ret 8u32 }
    if cat == .Nl { ret 9u32 }
    if cat == .No { ret 10u32 }
    if cat == .Pc { ret 11u32 }
    if cat == .Pd { ret 12u32 }
    if cat == .Ps { ret 13u32 }
    if cat == .Pe { ret 14u32 }
    if cat == .Pi { ret 15u32 }
    if cat == .Pf { ret 16u32 }
    if cat == .Po { ret 17u32 }
    if cat == .Sm { ret 18u32 }
    if cat == .Sc { ret 19u32 }
    if cat == .Sk { ret 20u32 }
    if cat == .So { ret 21u32 }
    if cat == .Zs { ret 22u32 }
    if cat == .Zl { ret 23u32 }
    if cat == .Zp { ret 24u32 }
    if cat == .Cc { ret 25u32 }
    if cat == .Cf { ret 26u32 }
    if cat == .Cs { ret 27u32 }
    if cat == .Co { ret 28u32 }
    ret 29u32
}

fn parse_class(p: *Parse) -> (u32, err) {
    // The `[` is consumed.
    let first = u32(p.ranges.len)
    var neg = false
    if eat(p, 94u8) { neg = true }
    var closed = false
    while p.i < p.src.len && !closed {
        let c = u32(p.src[p.i])
        if c == 93u32 {
            p.i += 1usize
            closed = true
            break
        }
        // One atom: a character or a class escape.
        var lo = 0u32
        var is_set = false
        if c == 92u32 && p.unicode && (peek_at(p, 1usize) == 112i64 || peek_at(p, 1usize) == 80i64) {
            let neg_p = peek_at(p, 1usize) == 80i64
            p.i += 2usize
            let (plo, phi, pe0) = parse_property(p, neg_p)
            if pe0 != ok { ret (NONE, pe0) }
            try add_range(p, plo, phi)
            if peek(p) == 45i64 && peek_at(p, 1usize) != 93i64 && p.i + 1usize < p.src.len { ret (NONE, fail(p, "Invalid character class")) }
            continue
        }
        if c == 92u32 {
            p.i += 1usize
            let (v, cls, letter, ee) = parse_escape_value(p, true)
            if ee != ok { ret (NONE, ee) }
            if cls {
                is_set = true
                if letter == 112u8 || letter == 80u8 { ret (NONE, fail(p, "property escapes are not supported")) }
                try add_class_escape(p, letter)
            }
            lo = v
        } else {
            let (cp, l) = next_cp(p)
            p.i += l
            lo = cp
        }
        if is_set && p.unicode && peek(p) == 45i64 && peek_at(p, 1usize) != 93i64 && p.i + 1usize < p.src.len { ret (NONE, fail(p, "Invalid character class")) }
        // A range `a-z`.
        if !is_set && peek(p) == 45i64 && peek_at(p, 1usize) != 93i64 && p.i + 1usize < p.src.len {
            let save = p.i
            p.i += 1usize
            var hi = 0u32
            var hi_set = false
            if p.src[p.i] == 92u16 {
                p.i += 1usize
                let (v2, cls2, letter2, ee2) = parse_escape_value(p, true)
                if ee2 != ok { ret (NONE, ee2) }
                if cls2 { hi_set = true } else { hi = v2 }
            } else {
                let (cp2, l2) = next_cp(p)
                p.i += l2
                hi = cp2
            }
            if hi_set {
                if p.unicode { ret (NONE, fail(p, "Invalid character class")) }
                // `[a-\d]`: the dash is literal in legacy mode.
                p.i = save
                try add_range(p, lo, lo)
                continue
            }
            if lo > hi { ret (NONE, fail(p, "Range out of order in character class")) }
            try add_range(p, lo, hi)
            continue
        }
        if !is_set { try add_range(p, lo, lo) }
    }
    if !closed { ret (NONE, fail(p, "Unterminated character class")) }
    let id = u32(p.classes.len)
    try list.push[Class](&p.classes, Class { first: first, count: u32(p.ranges.len) - first, neg: neg })
    ret (id, ok)
}

// Parses a group name `<name>` (the `<` is consumed); answers the name as UTF-8.
fn parse_group_name(p: *Parse) -> (str, err) {
    let (b, be) = str.builder(p.a, 16usize)
    if be != ok { ret ("", be) }
    var out = b
    var any = false
    while p.i < p.src.len && p.src[p.i] != 62u16 {
        var c = u32(p.src[p.i])
        var l = 1usize
        if c == 92u32 {
            // \uXXXX in a name.
            if peek_at(p, 1usize) == 117i64 {
                p.i += 2usize
                let (v, cls, letter, ee) = parse_escape_value_after_u(p)
                if ee != ok { ret ("", ee) }
                c = v
                l = 0usize
            } else {
                ret ("", fail(p, "Invalid capture group name"))
            }
        } else if c >= 55296u32 && c <= 56319u32 && p.i + 1usize < p.src.len {
            let lo = u32(p.src[p.i + 1usize])
            if lo >= 56320u32 && lo <= 57343u32 {
                c = 65536u32 + ((c - 55296u32) << 10u32) + (lo - 56320u32)
                l = 2usize
            }
        }
        let ok_start = lex.id_start_cp(c)
        let ok_part = lex.id_part_cp(c)
        if (!any && !ok_start) || !ok_part { ret ("", fail(p, "Invalid capture group name")) }
        any = true
        put_cp(&out, c)
        p.i += l
    }
    if p.i >= p.src.len || !any { ret ("", fail(p, "Invalid capture group name")) }
    p.i += 1usize
    ret (str.done(&out), ok)
}

fn parse_escape_value_after_u(p: *Parse) -> (u32, bool, u8, err) {
    // After "\u" inside a group name: \uXXXX or \u{X..}.
    if peek(p) == 123i64 {
        var j = p.i + 1usize
        var v = 0i64
        var any = false
        while j < p.src.len && p.src[j] != 125u16 {
            let h = hex_val(i64(p.src[j]))
            if h < 0i64 { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
            v = v * 16i64 + h
            any = true
            j += 1usize
        }
        if j >= p.src.len || !any || v > 1114111i64 { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
        p.i = j + 1usize
        ret (u32(v), false, 0u8, ok)
    }
    var v2 = 0i64
    var k = 0usize
    while k < 4usize {
        let h2 = hex_val(peek_at(p, k))
        if h2 < 0i64 { ret (0u32, false, 0u8, fail(p, "Invalid Unicode escape")) }
        v2 = v2 * 16i64 + h2
        k += 1usize
    }
    p.i += 4usize
    if v2 >= 55296i64 && v2 <= 56319i64 && peek(p) == 92i64 && peek_at(p, 1usize) == 117i64 {
        var lo = 0i64
        var kk = 0usize
        var good = true
        while kk < 4usize {
            let h3 = hex_val(peek_at(p, 2usize + kk))
            if h3 < 0i64 { good = false }
            lo = lo * 16i64 + h3
            kk += 1usize
        }
        if good && lo >= 56320i64 && lo <= 57343i64 {
            p.i += 6usize
            ret (u32(65536i64 + (v2 - 55296i64) * 1024i64 + (lo - 56320i64)), false, 0u8, ok)
        }
    }
    ret (u32(v2), false, 0u8, ok)
}

fn put_cp(b: *str.Builder, c: u32) {
    var e: err = ok
    if c < 128u32 {
        e = str.push_byte(b, u8(c))
    } else if c < 2048u32 {
        e = str.push_byte(b, u8(192u32 | (c >> 6u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    } else if c < 65536u32 {
        e = str.push_byte(b, u8(224u32 | (c >> 12u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    } else {
        e = str.push_byte(b, u8(240u32 | (c >> 18u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 12u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    }
}

// A decimal number at the cursor, or -1 when none.
fn parse_int(p: *Parse) -> i64 {
    var v = 0i64
    var any = false
    while p.i < p.src.len && is_digit(i64(p.src[p.i])) {
        v = v * 10i64 + i64(p.src[p.i]) - 48i64
        if v > 4294967295i64 { v = 4294967295i64 }
        any = true
        p.i += 1usize
    }
    if any { ret v }
    ret -1i64
}

fn commit(p: *Parse, ids: *const list.List[u32]) -> (u32, err) {
    let first = u32(p.kids.len)
    var i = 0usize
    while i < ids.len {
        try list.push[u32](&p.kids, ids.items[i])
        i += 1usize
    }
    ret (first, ok)
}

fn parse_disjunction(p: *Parse) -> (u32, err) {
    let (l0, le) = list.init[u32](p.a, 4usize)
    var alts = l0
    if le != ok { ret (NONE, le) }
    while true {
        let alt = try parse_alternative(p)
        try list.push[u32](&alts, alt)
        if !eat(p, 124u8) { break }
    }
    if alts.len == 1usize { ret (alts.items[0usize], ok) }
    let (id, me) = mk(p, R_ALT)
    if me != ok { ret (NONE, me) }
    let (first, ke) = commit(p, &alts)
    if ke != ok { ret (NONE, ke) }
    nd(p, id).a = first
    nd(p, id).b = u32(alts.len)
    ret (id, ok)
}

fn parse_alternative(p: *Parse) -> (u32, err) {
    let (l0, le) = list.init[u32](p.a, 8usize)
    var items = l0
    if le != ok { ret (NONE, le) }
    while p.i < p.src.len && p.src[p.i] != 124u16 && p.src[p.i] != 41u16 {
        let t = try parse_term(p)
        try list.push[u32](&items, t)
    }
    if items.len == 1usize { ret (items.items[0usize], ok) }
    let (id, me) = mk(p, R_SEQ)
    if me != ok { ret (NONE, me) }
    let (first, ke) = commit(p, &items)
    if ke != ok { ret (NONE, ke) }
    nd(p, id).a = first
    nd(p, id).b = u32(items.len)
    ret (id, ok)
}

fn atom_quantifiable(kind: u8, back: bool) -> bool { ret true }

fn parse_term(p: *Parse) -> (u32, err) {
    let c = u32(p.src[p.i])
    // Assertions.
    if c == 94u32 {
        p.i += 1usize
        let (id, me) = mk(p, R_BOL)
        ret (id, me)
    }
    if c == 36u32 {
        p.i += 1usize
        let (id2, me2) = mk(p, R_EOL)
        ret (id2, me2)
    }
    if c == 92u32 && (peek_at(p, 1usize) == 98i64 || peek_at(p, 1usize) == 66i64) {
        var kind = R_WORDB
        if peek_at(p, 1usize) == 66i64 { kind = R_NWORDB }
        p.i += 2usize
        let (id3, me3) = mk(p, kind)
        ret (id3, me3)
    }
    var atom: u32 = NONE
    var quantifiable = true
    if c == 40u32 {
        p.i += 1usize
        if peek(p) == 63i64 {
            let k1 = peek_at(p, 1usize)
            if k1 == 61i64 || k1 == 33i64 {
                // Lookahead.
                p.i += 2usize
                let body = try parse_disjunction(p)
                if !eat(p, 41u8) { ret (NONE, fail(p, "Unterminated group")) }
                let (id4, me4) = mk(p, R_LOOK)
                if me4 != ok { ret (NONE, me4) }
                nd(p, id4).a = body
                nd(p, id4).neg = k1 == 33i64
                nd(p, id4).back = false
                atom = id4
                // Legacy patterns allow quantifiers on lookaheads.
                quantifiable = !p.unicode
            } else if k1 == 60i64 && (peek_at(p, 2usize) == 61i64 || peek_at(p, 2usize) == 33i64) {
                let neg = peek_at(p, 2usize) == 33i64
                p.i += 3usize
                let body2 = try parse_disjunction(p)
                if !eat(p, 41u8) { ret (NONE, fail(p, "Unterminated group")) }
                let (id5, me5) = mk(p, R_LOOK)
                if me5 != ok { ret (NONE, me5) }
                nd(p, id5).a = body2
                nd(p, id5).neg = neg
                nd(p, id5).back = true
                atom = id5
                quantifiable = false
            } else if k1 == 58i64 {
                p.i += 2usize
                let body3 = try parse_disjunction(p)
                if !eat(p, 41u8) { ret (NONE, fail(p, "Unterminated group")) }
                atom = body3
                if p.nodes.items[usize(body3)].kind == R_ALT || p.nodes.items[usize(body3)].kind == R_SEQ || true {
                    // A non-capturing group wraps its body so a quantifier applies to the whole.
                    let (gid, gme) = mk(p, R_GROUP)
                    if gme != ok { ret (NONE, gme) }
                    nd(p, gid).a = NONE
                    nd(p, gid).b = body3
                    atom = gid
                }
            } else if k1 == 105i64 || k1 == 109i64 || k1 == 115i64 || k1 == 45i64 {
                // A modifier group (?ims-ims:...).
                p.i += 1usize
                var add_i = false
                var add_m = false
                var add_s = false
                var del_i = false
                var del_m = false
                var del_s = false
                var removing = false
                var seen_dash = false
                while true {
                    let fc = peek(p)
                    if fc == 58i64 { break }
                    if fc == 45i64 {
                        if seen_dash { ret (NONE, fail(p, "Invalid group")) }
                        seen_dash = true
                        removing = true
                        p.i += 1usize
                        continue
                    }
                    if fc == 105i64 {
                        if add_i || del_i { ret (NONE, fail(p, "Repeated flag in modifiers")) }
                        if removing { del_i = true } else { add_i = true }
                    } else if fc == 109i64 {
                        if add_m || del_m { ret (NONE, fail(p, "Repeated flag in modifiers")) }
                        if removing { del_m = true } else { add_m = true }
                    } else if fc == 115i64 {
                        if add_s || del_s { ret (NONE, fail(p, "Repeated flag in modifiers")) }
                        if removing { del_s = true } else { add_s = true }
                    } else {
                        ret (NONE, fail(p, "Invalid group"))
                    }
                    p.i += 1usize
                }
                p.i += 1usize
                if seen_dash && !(del_i || del_m || del_s) && !(add_i || add_m || add_s) { ret (NONE, fail(p, "Invalid group")) }
                if (add_i && del_i) || (add_m && del_m) || (add_s && del_s) { ret (NONE, fail(p, "Repeated flag in modifiers")) }
                var cur_i = p.ignore_case
                var cur_m = p.multiline
                var cur_s = p.dot_all
                if (p.mods & 1u8) != 0u8 {
                    cur_i = (p.mods & 2u8) != 0u8
                    cur_m = (p.mods & 4u8) != 0u8
                    cur_s = (p.mods & 8u8) != 0u8
                }
                if add_i { cur_i = true }
                if add_m { cur_m = true }
                if add_s { cur_s = true }
                if del_i { cur_i = false }
                if del_m { cur_m = false }
                if del_s { cur_s = false }
                let saved_mods = p.mods
                var nm = 1u8
                if cur_i { nm = nm | 2u8 }
                if cur_m { nm = nm | 4u8 }
                if cur_s { nm = nm | 8u8 }
                p.mods = nm
                let bodym = try parse_disjunction(p)
                p.mods = saved_mods
                if !eat(p, 41u8) { ret (NONE, fail(p, "Unterminated group")) }
                let (gidm, gmem) = mk(p, R_GROUP)
                if gmem != ok { ret (NONE, gmem) }
                nd(p, gidm).a = NONE
                nd(p, gidm).b = bodym
                atom = gidm
            } else if k1 == 60i64 {
                p.i += 2usize
                let (name, ne) = parse_group_name(p)
                if ne != ok { ret (NONE, ne) }
                p.groups += 1u32
                let gi = p.groups
                // Duplicate names are a syntax error.
                var d = 0usize
                while d < p.names.len {
                    if str.eq(p.names.items[d], name) { ret (NONE, fail(p, "Duplicate capture group name")) }
                    d += 1usize
                }
                try list.push[str](&p.names, name)
                let body4 = try parse_disjunction(p)
                if !eat(p, 41u8) { ret (NONE, fail(p, "Unterminated group")) }
                let (gid2, gme2) = mk(p, R_GROUP)
                if gme2 != ok { ret (NONE, gme2) }
                nd(p, gid2).a = gi
                nd(p, gid2).b = body4
                atom = gid2
            } else {
                ret (NONE, fail(p, "Invalid group"))
            }
        } else {
            p.groups += 1u32
            let gi2 = p.groups
            try list.push[str](&p.names, "")
            let body5 = try parse_disjunction(p)
            if !eat(p, 41u8) { ret (NONE, fail(p, "Unterminated group")) }
            let (gid3, gme3) = mk(p, R_GROUP)
            if gme3 != ok { ret (NONE, gme3) }
            nd(p, gid3).a = gi2
            nd(p, gid3).b = body5
            atom = gid3
        }
    } else if c == 46u32 {
        p.i += 1usize
        let (id6, me6) = mk(p, R_ANY)
        if me6 != ok { ret (NONE, me6) }
        atom = id6
    } else if c == 91u32 {
        p.i += 1usize
        let cid = try parse_class(p)
        let (id7, me7) = mk(p, R_CLASS)
        if me7 != ok { ret (NONE, me7) }
        nd(p, id7).a = cid
        atom = id7
    } else if c == 92u32 {
        p.i += 1usize
        // Backreference or escape.
        let d = peek(p)
        if d >= 49i64 && d <= 57i64 {
            // \N: a backreference when N <= group count (legacy: otherwise an octal escape).
            let save = p.i
            let n = parse_int(p)
            if u32(n) <= p.total_groups || p.unicode {
                if p.unicode && u32(n) > p.total_groups { ret (NONE, fail(p, "Invalid escape")) }
                let (id8, me8) = mk(p, R_BACKREF)
                if me8 != ok { ret (NONE, me8) }
                nd(p, id8).a = u32(n)
                atom = id8
            } else {
                p.i = save
                // Legacy octal / identity escape.
                if d >= 56i64 {
                    p.i += 1usize
                    let (id9, me9) = mk(p, R_CHAR)
                    if me9 != ok { ret (NONE, me9) }
                    nd(p, id9).a = u32(d)
                    atom = id9
                } else {
                    var v = 0u32
                    var cnt = 0usize
                    while cnt < 3usize && peek(p) >= 48i64 && peek(p) <= 55i64 && v * 8u32 + u32(peek(p) - 48i64) <= 255u32 {
                        v = v * 8u32 + u32(peek(p) - 48i64)
                        p.i += 1usize
                        cnt += 1usize
                    }
                    let (id10, me10) = mk(p, R_CHAR)
                    if me10 != ok { ret (NONE, me10) }
                    nd(p, id10).a = v
                    atom = id10
                }
            }
        } else if d == 107i64 && (p.named || p.unicode) {
            // \k<name>
            if peek_at(p, 1usize) != 60i64 { ret (NONE, fail(p, "Invalid named reference")) }
            p.i += 2usize
            let (name2, ne2) = parse_group_name(p)
            if ne2 != ok { ret (NONE, ne2) }
            let (id11, me11) = mk(p, R_NAMEDREF)
            if me11 != ok { ret (NONE, me11) }
            // The name resolves after the whole pattern is parsed.
            nd(p, id11).a = u32(p.refs.len)
            try list.push[str](&p.refs, name2)
            atom = id11
        } else if (d == 112i64 || d == 80i64) && p.unicode {
            let neg_t = d == 80i64
            p.i += 1usize
            let (tlo, thi, te0) = parse_property(p, neg_t)
            if te0 != ok { ret (NONE, te0) }
            let first_t = u32(p.ranges.len)
            try add_range(p, tlo, thi)
            let cid_t = u32(p.classes.len)
            try list.push[Class](&p.classes, Class { first: first_t, count: 1u32, neg: false })
            let (id_t, me_t) = mk(p, R_CLASS)
            if me_t != ok { ret (NONE, me_t) }
            nd(p, id_t).a = cid_t
            atom = id_t
        } else {
            let (v2, cls, letter, ee) = parse_escape_value(p, false)
            if ee != ok { ret (NONE, ee) }
            if cls {
                let first = u32(p.ranges.len)
                try add_class_escape(p, letter)
                let cid2 = u32(p.classes.len)
                try list.push[Class](&p.classes, Class { first: first, count: u32(p.ranges.len) - first, neg: false })
                let (id12, me12) = mk(p, R_CLASS)
                if me12 != ok { ret (NONE, me12) }
                nd(p, id12).a = cid2
                atom = id12
            } else {
                let (id13, me13) = mk(p, R_CHAR)
                if me13 != ok { ret (NONE, me13) }
                nd(p, id13).a = v2
                atom = id13
            }
        }
    } else if c == 42u32 || c == 43u32 || c == 63u32 {
        ret (NONE, fail(p, "Nothing to repeat"))
    } else if c == 123u32 {
        // `{`: a quantifier without an atom is an error in unicode mode; legacy treats it as a literal when not a quantifier.
        let save2 = p.i
        p.i += 1usize
        let n2 = parse_int(p)
        var is_quant = false
        if n2 >= 0i64 {
            if eat(p, 125u8) {
                is_quant = true
            } else if eat(p, 44u8) {
                let m2 = parse_int(p)
                if eat(p, 125u8) { is_quant = true }
            }
        }
        p.i = save2
        if p.unicode || is_quant { ret (NONE, fail(p, "Nothing to repeat")) }
        p.i += 1usize
        let (id14, me14) = mk(p, R_CHAR)
        if me14 != ok { ret (NONE, me14) }
        nd(p, id14).a = 123u32
        atom = id14
    } else if (c == 125u32 || c == 93u32) && p.unicode {
        ret (NONE, fail(p, "Lone quantifier brackets"))
    } else {
        let (cp, l) = next_cp(p)
        p.i += l
        let (id15, me15) = mk(p, R_CHAR)
        if me15 != ok { ret (NONE, me15) }
        nd(p, id15).a = cp
        atom = id15
    }
    // Quantifier.
    var min = 1i64
    var max = 1i64
    var has_q = false
    if p.i < p.src.len {
        let q = u32(p.src[p.i])
        if q == 42u32 {
            min = 0i64
            max = -1i64
            has_q = true
            p.i += 1usize
        } else if q == 43u32 {
            min = 1i64
            max = -1i64
            has_q = true
            p.i += 1usize
        } else if q == 63u32 {
            min = 0i64
            max = 1i64
            has_q = true
            p.i += 1usize
        } else if q == 123u32 {
            let save3 = p.i
            p.i += 1usize
            let lo = parse_int(p)
            if lo >= 0i64 {
                if eat(p, 125u8) {
                    min = lo
                    max = lo
                    has_q = true
                } else if eat(p, 44u8) {
                    if eat(p, 125u8) {
                        min = lo
                        max = -1i64
                        has_q = true
                    } else {
                        let hi = parse_int(p)
                        if hi >= 0i64 && eat(p, 125u8) {
                            min = lo
                            max = hi
                            has_q = true
                        }
                    }
                }
            }
            if !has_q {
                p.i = save3
                if p.unicode { ret (NONE, fail(p, "Incomplete quantifier")) }
            } else if max >= 0i64 && min > max {
                ret (NONE, fail(p, "numbers out of order in {} quantifier"))
            }
        }
    }
    if !has_q { ret (atom, ok) }
    if !quantifiable { ret (NONE, fail(p, "Invalid quantifier")) }
    var greedy = true
    if eat(p, 63u8) { greedy = false }
    let (rid, rme) = mk(p, R_REPEAT)
    if rme != ok { ret (NONE, rme) }
    nd(p, rid).a = atom
    nd(p, rid).b = u32(min)
    if max < 0i64 { nd(p, rid).c = NONE } else { nd(p, rid).c = u32(max) }
    nd(p, rid).greedy = greedy
    ret (rid, ok)
}

// Counts capture groups ahead of parsing (needed to tell `\N` backreferences from legacy escapes) and notes named groups.
fn prescan(p: *Parse) {
    var i = 0usize
    var in_class = false
    var n = 0u32
    while i < p.src.len {
        let c = p.src[i]
        if c == 92u16 {
            i += 2usize
            continue
        }
        if in_class {
            if c == 93u16 { in_class = false }
        } else if c == 91u16 {
            in_class = true
        } else if c == 40u16 {
            if i + 1usize < p.src.len && p.src[i + 1usize] == 63u16 {
                if i + 2usize < p.src.len && p.src[i + 2usize] == 60u16 && i + 3usize < p.src.len && p.src[i + 3usize] != 61u16 && p.src[i + 3usize] != 33u16 {
                    n += 1u32
                    p.named = true
                }
            } else {
                n += 1u32
            }
        }
        i += 1usize
    }
    p.total_groups = n
}

// Compiles `pattern` (UTF-16 units) with the flag letters in `flags`; on failure the message is in the second result.
fn compile(a: *mem.Arena, pattern: []const u16, flags: str) -> (Regex, str, err) {
    var re: Regex = zero
    var p: Parse = zero
    p.a = a
    p.src = pattern
    var seen: [16]bool = zero
    var fi = 0usize
    while fi < flags.len {
        let f = flags[fi]
        var idx = 99usize
        if f == 103u8 { idx = 0usize } else if f == 105u8 { idx = 1usize } else if f == 109u8 { idx = 2usize } else if f == 115u8 { idx = 3usize } else if f == 117u8 { idx = 4usize } else if f == 121u8 { idx = 5usize } else if f == 100u8 { idx = 6usize } else if f == 118u8 { idx = 7usize }
        if idx == 99usize || seen[idx] { ret (re, "Invalid regular expression flags", SyntaxErr) }
        seen[idx] = true
        fi += 1usize
    }
    re.global = seen[0usize]
    re.ignore_case = seen[1usize]
    re.multiline = seen[2usize]
    re.dot_all = seen[3usize]
    re.unicode = seen[4usize] || seen[7usize]
    re.sticky = seen[5usize]
    re.has_indices = seen[6usize]
    re.unicode_sets = seen[7usize]
    if seen[4usize] && seen[7usize] { ret (re, "Invalid regular expression flags", SyntaxErr) }
    p.unicode = re.unicode
    p.ignore_case = re.ignore_case
    p.multiline = re.multiline
    p.dot_all = re.dot_all
    p.mods = 0u8
    let (nl, nle) = list.init[Node](a, 16usize)
    p.nodes = nl
    let (kl, kle) = list.init[u32](a, 16usize)
    p.kids = kl
    let (rl, rle) = list.init[Range](a, 16usize)
    p.ranges = rl
    let (cl, cle) = list.init[Class](a, 4usize)
    p.classes = cl
    let (nml, nmle) = list.init[str](a, 4usize)
    p.names = nml
    let (rfl, rfle) = list.init[str](a, 2usize)
    p.refs = rfl
    prescan(&p)
    let (r0, e0) = parse_top(&p)
    if e0 != ok { ret (re, p.message, e0) }
    re.root = r0
    // Resolve \k<name> references and validate them.
    var k = 0usize
    while k < p.nodes.len {
        if p.nodes.items[k].kind == R_NAMEDREF {
            let name = p.refs.items[usize(p.nodes.items[k].a)]
            var found = false
            var g = 0usize
            var gi = 0u32
            // Named groups keep their names at their group index - 1 in the first `groups` entries.
            while g < usize(p.groups) {
                if str.eq(p.names.items[g], name) {
                    found = true
                    gi = u32(g) + 1u32
                }
                g += 1usize
            }
            if !found { ret (re, "Invalid named capture referenced", SyntaxErr) }
            p.nodes.items[k].kind = R_BACKREF
            p.nodes.items[k].a = gi
        }
        k += 1usize
    }
    re.nodes = list.slice_const[Node](&p.nodes)
    re.kids = list.slice_const[u32](&p.kids)
    re.ranges = list.slice_const[Range](&p.ranges)
    re.classes = list.slice_const[Class](&p.classes)
    re.groups = p.groups
    re.names = list.slice_const[str](&p.names)
    ret (re, "", ok)
}

fn parse_top(p: *Parse) -> (u32, err) {
    // Parse again from the start (the first call above only primed the lists); reset state.
    p.i = 0usize
    p.nodes.len = 0usize
    p.kids.len = 0usize
    p.ranges.len = 0usize
    p.classes.len = 0usize
    p.names.len = 0usize
    p.refs.len = 0usize
    p.groups = 0u32
    let r = try parse_disjunction(p)
    if p.i < p.src.len {
        if p.src[p.i] == 41u16 { ret (NONE, fail(p, "Unmatched ')'")) }
        ret (NONE, fail(p, "Unexpected character"))
    }
    ret (r, ok)
}

// --- matching

// Continuation kinds.
const K_TOP: u8 = 0u8
const K_SEQ: u8 = 1u8
const K_GROUP_END: u8 = 2u8
const K_REPEAT: u8 = 3u8
const K_LOOK_END: u8 = 4u8

type Cont = struct { kind: u8, node: u32, index: u32, count: u32, pos: i64, back: bool, next: *Cont, has_next: bool }

type M = struct {
    re: *const Regex, input: []const u16, caps: []i64, a: *mem.Arena, depth: u32, steps: u64, step_limit: u64, aborted: bool,
    end: i64, found: bool
}

// The effective flags of a node: its own modifier group, else the regular expression's.
fn eff_i(m: *const M, n: *const Node) -> bool {
    if (n.mods & 1u8) != 0u8 { ret (n.mods & 2u8) != 0u8 }
    ret m.re.ignore_case
}

fn eff_m(m: *const M, n: *const Node) -> bool {
    if (n.mods & 1u8) != 0u8 { ret (n.mods & 4u8) != 0u8 }
    ret m.re.multiline
}

fn eff_s(m: *const M, n: *const Node) -> bool {
    if (n.mods & 1u8) != 0u8 { ret (n.mods & 8u8) != 0u8 }
    ret m.re.dot_all
}

fn canon(m: *const M, c: u32, ic: bool) -> u32 {
    if !ic { ret c }
    if m.re.unicode {
        // Simple case folding: lowercase of the uppercase form.
        ret unicode.to_lower_simple(unicode.to_upper_simple(c))
    }
    if c < 128u32 {
        if c >= 97u32 && c <= 122u32 { ret c - 32u32 }
        ret c
    }
    let u = unicode.to_upper_simple(c)
    // A non-ASCII character never maps to an ASCII one.
    if u < 128u32 { ret c }
    ret u
}

fn is_word(c: u32) -> bool { ret (c >= 48u32 && c <= 57u32) || (c >= 65u32 && c <= 90u32) || (c >= 97u32 && c <= 122u32) || c == 95u32 }

fn is_line_term(c: u32) -> bool { ret c == 10u32 || c == 13u32 || c == 8232u32 || c == 8233u32 }

// The character before/after `pos` (in code points under the unicode flag) and its unit length; (value, length) or length 0.
fn char_at(m: *const M, pos: i64) -> (u32, i64) {
    if pos < 0i64 || pos >= i64(m.input.len) { ret (0u32, 0i64) }
    let u = u32(m.input[usize(pos)])
    if m.re.unicode && u >= 55296u32 && u <= 56319u32 && pos + 1i64 < i64(m.input.len) {
        let lo = u32(m.input[usize(pos) + 1usize])
        if lo >= 56320u32 && lo <= 57343u32 { ret (65536u32 + ((u - 55296u32) << 10u32) + (lo - 56320u32), 2i64) }
    }
    ret (u, 1i64)
}

fn char_before(m: *const M, pos: i64) -> (u32, i64) {
    if pos <= 0i64 || pos > i64(m.input.len) { ret (0u32, 0i64) }
    let u = u32(m.input[usize(pos) - 1usize])
    if m.re.unicode && u >= 56320u32 && u <= 57343u32 && pos >= 2i64 {
        let hi = u32(m.input[usize(pos) - 2usize])
        if hi >= 55296u32 && hi <= 56319u32 { ret (65536u32 + ((hi - 55296u32) << 10u32) + (u - 56320u32), 2i64) }
    }
    ret (u, 1i64)
}

fn class_has(m: *const M, cid: u32, c: u32, ic: bool) -> bool {
    let cls = m.re.classes[usize(cid)]
    var hit = false
    var i = 0usize
    while i < usize(cls.count) {
        let r = m.re.ranges[usize(cls.first) + i]
        if r.lo >= 2147483648u32 {
            if property_matches(r.lo, r.hi, c) {
                hit = true
                break
            }
        } else if c >= r.lo && c <= r.hi {
            hit = true
            break
        }
        i += 1usize
    }
    if !hit && ic {
        let cc = canon(m, c, ic)
        // Test the canonical form and the other case variants.
        var j = 0usize
        while j < usize(cls.count) && !hit {
            let r2 = m.re.ranges[usize(cls.first) + j]
            if r2.lo >= 2147483648u32 {
                if property_matches(r2.lo, r2.hi, cc) || property_matches(r2.lo, r2.hi, unicode.to_lower_simple(c)) || property_matches(r2.lo, r2.hi, unicode.to_upper_simple(c)) { hit = true }
                j += 1usize
                continue
            }
            if cc >= r2.lo && cc <= r2.hi { hit = true }
            let lo = unicode.to_lower_simple(c)
            let up = unicode.to_upper_simple(c)
            if canon(m, lo, ic) == cc && lo >= r2.lo && lo <= r2.hi { hit = true }
            if canon(m, up, ic) == cc && up >= r2.lo && up <= r2.hi { hit = true }
            // A range may contain a character that canonicalises to cc.
            if !hit && r2.hi - r2.lo < 256u32 {
                var x = r2.lo
                while x <= r2.hi {
                    if canon(m, x, ic) == cc {
                        hit = true
                        break
                    }
                    x += 1u32
                }
            }
            j += 1usize
        }
    }
    ret hit != cls.neg
}

fn new_cont(m: *M, kind: u8, node: u32, index: u32, count: u32, pos: i64, back: bool, next: *Cont, has_next: bool) -> *Cont {
    let (cell, ce) = mem.alloc[Cont](m.a, 1usize)
    if ce != ok {
        m.aborted = true
        var none: *Cont = zero
        ret none
    }
    cell[0usize] = Cont { kind: kind, node: node, index: index, count: count, pos: pos, back: back, next: next, has_next: has_next }
    ret &cell[0usize]
}

fn call_cont(m: *M, k: *Cont, pos: i64) -> bool {
    if m.aborted { ret false }
    if k.kind == K_TOP {
        m.end = pos
        ret true
    }
    if k.kind == K_LOOK_END {
        m.end = pos
        ret true
    }
    if k.kind == K_SEQ {
        let n = m.re.nodes[usize(k.node)]
        let i = k.index
        if i >= n.b {
            ret call_cont(m, k.next, pos)
        }
        // Next child in direction order.
        var child: u32 = 0u32
        if k.back { child = m.re.kids[usize(n.a) + usize(n.b - 1u32 - i)] } else { child = m.re.kids[usize(n.a) + usize(i)] }
        let nk = new_cont(m, K_SEQ, k.node, i + 1u32, 0u32, 0i64, k.back, k.next, true)
        ret step(m, child, pos, nk, k.back)
    }
    if k.kind == K_GROUP_END {
        let n = m.re.nodes[usize(k.node)]
        let gi = usize(n.a)
        let o0 = m.caps[gi * 2usize]
        let o1 = m.caps[gi * 2usize + 1usize]
        if k.back {
            m.caps[gi * 2usize] = pos
            m.caps[gi * 2usize + 1usize] = k.pos
        } else {
            m.caps[gi * 2usize] = k.pos
            m.caps[gi * 2usize + 1usize] = pos
        }
        if call_cont(m, k.next, pos) { ret true }
        m.caps[gi * 2usize] = o0
        m.caps[gi * 2usize + 1usize] = o1
        ret false
    }
    // K_REPEAT: one iteration of the loop finished at `pos`.
    let n2 = m.re.nodes[usize(k.node)]
    // An iteration that consumed nothing ends the loop (after the minimum).
    if pos == k.pos && k.count >= n2.b {
        ret false
    }
    ret repeat_step(m, k.node, k.count, pos, k.next, k.back)
}

// Tries another iteration of the loop `node` having completed `count` iterations at `pos`, else the continuation.
fn repeat_step(m: *M, node: u32, count: u32, pos: i64, next: *Cont, back: bool) -> bool {
    let n = m.re.nodes[usize(node)]
    let max = n.c
    let can_more = max == NONE || count < max
    let must_more = count < n.b
    if must_more {
        let rk = new_cont(m, K_REPEAT, node, 0u32, count + 1u32, pos, back, next, true)
        clear_groups(m, n.a)
        ret step(m, n.a, pos, rk, back)
    }
    if n.greedy {
        if can_more {
            let saved = save_groups(m, n.a)
            let rk2 = new_cont(m, K_REPEAT, node, 0u32, count + 1u32, pos, back, next, true)
            clear_groups(m, n.a)
            if step(m, n.a, pos, rk2, back) { ret true }
            restore_groups(m, n.a, saved)
        }
        ret call_cont(m, next, pos)
    }
    if call_cont(m, next, pos) { ret true }
    if can_more {
        let rk3 = new_cont(m, K_REPEAT, node, 0u32, count + 1u32, pos, back, next, true)
        clear_groups(m, n.a)
        ret step(m, n.a, pos, rk3, back)
    }
    ret false
}

// Capture groups inside `node` reset at the start of each loop iteration.
fn group_range(m: *const M, node: u32) -> (u32, u32) {
    // The capture indices [lo, hi) that appear within the subtree.
    var lo = 4294967295u32
    var hi = 0u32
    var stack: [64]u32 = zero
    var top = 0usize
    stack[0usize] = node
    top = 1usize
    while top > 0usize {
        top -= 1usize
        let id = stack[top]
        let n = m.re.nodes[usize(id)]
        if n.kind == R_GROUP {
            if n.a != NONE {
                if n.a < lo { lo = n.a }
                if n.a + 1u32 > hi { hi = n.a + 1u32 }
            }
            if top < 63usize {
                stack[top] = n.b
                top += 1usize
            }
        } else if n.kind == R_SEQ || n.kind == R_ALT {
            var i = 0usize
            while i < usize(n.b) && top < 63usize {
                stack[top] = m.re.kids[usize(n.a) + i]
                top += 1usize
                i += 1usize
            }
        } else if n.kind == R_REPEAT || n.kind == R_LOOK {
            if top < 63usize {
                stack[top] = n.a
                top += 1usize
            }
        }
    }
    if lo == 4294967295u32 { ret (0u32, 0u32) }
    ret (lo, hi)
}

fn clear_groups(m: *M, node: u32) {
    let (lo, hi) = group_range(m, node)
    var g = lo
    while g < hi {
        m.caps[usize(g) * 2usize] = -1i64
        m.caps[usize(g) * 2usize + 1usize] = -1i64
        g += 1u32
    }
}

fn save_groups(m: *M, node: u32) -> []i64 {
    let (lo, hi) = group_range(m, node)
    let (cell, ce) = mem.alloc[i64](m.a, usize(hi - lo) * 2usize + 2usize)
    if ce != ok {
        m.aborted = true
        var none: []i64 = zero
        ret none
    }
    var g = lo
    while g < hi {
        cell[usize(g - lo) * 2usize] = m.caps[usize(g) * 2usize]
        cell[usize(g - lo) * 2usize + 1usize] = m.caps[usize(g) * 2usize + 1usize]
        g += 1u32
    }
    ret cell
}

fn restore_groups(m: *M, node: u32, saved: []i64) {
    let (lo, hi) = group_range(m, node)
    if saved.len == 0usize { ret }
    var g = lo
    while g < hi {
        m.caps[usize(g) * 2usize] = saved[usize(g - lo) * 2usize]
        m.caps[usize(g) * 2usize + 1usize] = saved[usize(g - lo) * 2usize + 1usize]
        g += 1u32
    }
}

fn step(m: *M, id: u32, pos: i64, k: *Cont, back: bool) -> bool {
    if m.aborted { ret false }
    m.steps += 1u64
    if m.steps > m.step_limit {
        m.aborted = true
        ret false
    }
    m.depth += 1u32
    if m.depth > 20000u32 {
        m.depth -= 1u32
        m.aborted = true
        ret false
    }
    let r = step_inner(m, id, pos, k, back)
    m.depth -= 1u32
    ret r
}

fn step_inner(m: *M, id: u32, pos: i64, k: *Cont, back: bool) -> bool {
    let n = m.re.nodes[usize(id)]
    let kind = n.kind
    if kind == R_EMPTY { ret call_cont(m, k, pos) }
    if kind == R_CHAR {
        var c = 0u32
        var l = 0i64
        if back { let (cb, lb) = char_before(m, pos)
            c = cb
            l = lb } else { let (cf, lf) = char_at(m, pos)
            c = cf
            l = lf }
        if l == 0i64 { ret false }
        let ic1 = eff_i(m, &n)
        if canon(m, c, ic1) != canon(m, n.a, ic1) { ret false }
        if back { ret call_cont(m, k, pos - l) }
        ret call_cont(m, k, pos + l)
    }
    if kind == R_ANY {
        var c2 = 0u32
        var l2 = 0i64
        if back { let (cb2, lb2) = char_before(m, pos)
            c2 = cb2
            l2 = lb2 } else { let (cf2, lf2) = char_at(m, pos)
            c2 = cf2
            l2 = lf2 }
        if l2 == 0i64 { ret false }
        if !eff_s(m, &n) && is_line_term(c2) { ret false }
        if back { ret call_cont(m, k, pos - l2) }
        ret call_cont(m, k, pos + l2)
    }
    if kind == R_CLASS {
        var c3 = 0u32
        var l3 = 0i64
        if back { let (cb3, lb3) = char_before(m, pos)
            c3 = cb3
            l3 = lb3 } else { let (cf3, lf3) = char_at(m, pos)
            c3 = cf3
            l3 = lf3 }
        if l3 == 0i64 { ret false }
        if !class_has(m, n.a, c3, eff_i(m, &n)) { ret false }
        if back { ret call_cont(m, k, pos - l3) }
        ret call_cont(m, k, pos + l3)
    }
    if kind == R_SEQ {
        if n.b == 0u32 { ret call_cont(m, k, pos) }
        let sk = new_cont(m, K_SEQ, id, 0u32, 0u32, 0i64, back, k, true)
        ret call_cont(m, sk, pos)
    }
    if kind == R_ALT {
        var i = 0usize
        while i < usize(n.b) {
            let saved = save_caps(m)
            if step(m, m.re.kids[usize(n.a) + i], pos, k, back) { ret true }
            restore_caps(m, saved)
            i += 1usize
        }
        ret false
    }
    if kind == R_GROUP {
        if n.a == NONE { ret step(m, n.b, pos, k, back) }
        let gk = new_cont(m, K_GROUP_END, id, 0u32, 0u32, pos, back, k, true)
        ret step(m, n.b, pos, gk, back)
    }
    if kind == R_REPEAT { ret repeat_step(m, id, 0u32, pos, k, back) }
    if kind == R_BOL {
        if pos == 0i64 { ret call_cont(m, k, pos) }
        if eff_m(m, &n) {
            let (cb4, lb4) = char_before(m, pos)
            if lb4 > 0i64 && is_line_term(cb4) { ret call_cont(m, k, pos) }
        }
        ret false
    }
    if kind == R_EOL {
        if pos == i64(m.input.len) { ret call_cont(m, k, pos) }
        if eff_m(m, &n) {
            let (cf4, lf4) = char_at(m, pos)
            if lf4 > 0i64 && is_line_term(cf4) { ret call_cont(m, k, pos) }
        }
        ret false
    }
    if kind == R_WORDB || kind == R_NWORDB {
        var before = false
        var after = false
        if pos > 0i64 {
            var cp = u32(m.input[usize(pos) - 1usize])
            if eff_i(m, &n) && m.re.unicode && (cp == 383u32 || cp == 8490u32) { cp = 97u32 }
            before = is_word(cp)
        }
        if pos < i64(m.input.len) {
            var cn = u32(m.input[usize(pos)])
            if eff_i(m, &n) && m.re.unicode && (cn == 383u32 || cn == 8490u32) { cn = 97u32 }
            after = is_word(cn)
        }
        var at_boundary = before != after
        if kind == R_NWORDB { at_boundary = !at_boundary }
        if at_boundary { ret call_cont(m, k, pos) }
        ret false
    }
    if kind == R_BACKREF {
        let gi = usize(n.a)
        let s = m.caps[gi * 2usize]
        let e = m.caps[gi * 2usize + 1usize]
        if s < 0i64 || e < 0i64 { ret call_cont(m, k, pos) }
        let len = e - s
        if back {
            if pos - len < 0i64 { ret false }
            var i2 = 0i64
            while i2 < len {
                if canon(m, u32(m.input[usize(s + i2)]), eff_i(m, &n)) != canon(m, u32(m.input[usize(pos - len + i2)]), eff_i(m, &n)) { ret false }
                i2 += 1i64
            }
            ret call_cont(m, k, pos - len)
        }
        if pos + len > i64(m.input.len) { ret false }
        var i3 = 0i64
        while i3 < len {
            if canon(m, u32(m.input[usize(s + i3)]), eff_i(m, &n)) != canon(m, u32(m.input[usize(pos + i3)]), eff_i(m, &n)) { ret false }
            i3 += 1i64
        }
        ret call_cont(m, k, pos + len)
    }
    if kind == R_LOOK {
        let saved2 = save_caps(m)
        let lk = new_cont(m, K_LOOK_END, 0u32, 0u32, 0u32, 0i64, n.back, k, true)
        let saved_end = m.end
        let matched = step(m, n.a, pos, lk, n.back)
        m.end = saved_end
        if n.neg {
            restore_caps(m, saved2)
            if matched { ret false }
            ret call_cont(m, k, pos)
        }
        if !matched {
            restore_caps(m, saved2)
            ret false
        }
        if call_cont(m, k, pos) { ret true }
        restore_caps(m, saved2)
        ret false
    }
    ret false
}

fn save_caps(m: *M) -> []i64 {
    let (cell, ce) = mem.alloc[i64](m.a, m.caps.len + 1usize)
    if ce != ok {
        m.aborted = true
        var none: []i64 = zero
        ret none
    }
    var i = 0usize
    while i < m.caps.len {
        cell[i] = m.caps[i]
        i += 1usize
    }
    ret cell[0usize..m.caps.len]
}

fn restore_caps(m: *M, saved: []i64) {
    if saved.len == 0usize { ret }
    var i = 0usize
    while i < m.caps.len {
        m.caps[i] = saved[i]
        i += 1usize
    }
}

type Match = struct { caps: []const i64, found: bool, aborted: bool }

fn do_match(m: *M, root: u32, pos: i64) {
    let top = new_cont(m, K_TOP, 0u32, 0u32, 0u32, 0i64, false, zero_cont(), false)
    if m.aborted { ret }
    m.found = step(m, root, pos, top, false)
}

// Matches at exactly `pos`.
fn match_at(a: *mem.Arena, re: *const Regex, input: []const u16, pos: i64) -> Match {
    let ncaps = (usize(re.groups) + 1usize) * 2usize
    let (cell, ce) = mem.alloc[i64](a, ncaps)
    var out: Match = zero
    if ce != ok {
        out.aborted = true
        ret out
    }
    var i = 0usize
    while i < ncaps {
        cell[i] = -1i64
        i += 1usize
    }
    var m = M { re: re, input: input, caps: cell, a: a, depth: 0u32, steps: 0u64, step_limit: 200000000u64, aborted: false, end: 0i64, found: false }
    do_match(&m, re.root, pos)
    if m.aborted {
        out.aborted = true
        ret out
    }
    if m.found {
        cell[0usize] = pos
        cell[1usize] = m.end
        out.found = true
        out.caps = cell
    }
    ret out
}

fn zero_cont() -> *Cont {
    var none: *Cont = zero
    ret none
}

// Searches forward from `start` (or only at `start` when sticky). The arena may be rewound by the caller between attempts.
fn exec(a: *mem.Arena, re: *const Regex, input: []const u16, start: usize, sticky: bool) -> Match {
    var pos = i64(start)
    var out: Match = zero
    while pos <= i64(input.len) {
        let mark = mem.mark(a)
        let r = match_at(a, re, input, pos)
        if r.aborted { ret r }
        if r.found { ret r }
        mem.reset(a, mark)
        if sticky { break }
        pos += 1i64
        // In unicode mode a match never starts inside a surrogate pair.
        if re.unicode && pos < i64(input.len) && pos > 0i64 {
            let prev = u32(input[usize(pos) - 1usize])
            let cur = u32(input[usize(pos)])
            if prev >= 55296u32 && prev <= 56319u32 && cur >= 56320u32 && cur <= 57343u32 { pos += 1i64 }
        }
    }
    ret out
}
