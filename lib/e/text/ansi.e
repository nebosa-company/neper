// ANSI-aware string operations, as R's cli package does them: `strip`, `has_any`, `nchar`
// (graphemes, bytes, display width, code points), `substr`, `simplify`, `html`, `trimws`,
// `align` and `convert_case`. An escape is an SGR sequence (ESC [ .. m), another CSI sequence
// (ESC [ .. final) or an OSC 8 hyperlink; everything between escapes is text. Graphemes and
// widths are counted with cli's own tables (ansi_tables.e, generated from its headers), one text
// piece at a time, so a count equals cli's whatever Unicode version e.text.segment carries.
//
// `substr`, `simplify` and `html` track the SGR state and write it back the way cli does: when
// text is emitted, the tags that close first (background, foreground, then the attributes, then
// a link), then the tags that open (a link, the attributes in a fixed order, foreground,
// background); everything still open is closed at the end of the string.
//
// Not here: `strwrap`, `strsplit`, `strtrim` (they rest on R's strwrap and regular
// expressions), and `convert_case` maps ASCII letters only. A truncated escape sequence is
// not handled. The hyperlink terminator is BEL, as cli writes it unless R_CLI_HYPERLINK_MODE
// is "posix".

use e.mem
use e.str
use e.text.ansi_tables as tables

error TooLarge

// --- cli's tables.

fn table_byte(which: usize, i: usize) -> u8 {
    let chunk = tables.CHUNK
    var text = ""
    if which == 0usize { text = tables.graph_stage1(i / chunk) }
    if which == 1usize { text = tables.graph_stage2(i / chunk) }
    if which == 2usize { text = tables.width_stage1(i / chunk) }
    if which == 3usize { text = tables.width_stage2(i / chunk) }
    ret text[i % chunk]
}

fn digit36(c: u8) -> i64 {
    if c >= 97u8 { ret i64(c) - 87i64 }
    ret i64(c) - 48i64
}

fn lookup(stage1: usize, stage2: usize, code: i64) -> i64 {
    let block = usize(code / 128i64)
    let hi = digit36(table_byte(stage1, 2usize * block))
    let lo = digit36(table_byte(stage1, 2usize * block + 1usize))
    let index = usize(hi * 16i64 + lo)
    ret digit36(table_byte(stage2, index * 128usize + usize(code % 128i64)))
}

fn graph_break(code: i64) -> i64 { ret lookup(0usize, 1usize, code) }

fn char_width(code: i64) -> i64 { ret lookup(2usize, 3usize, code) }

// --- The grapheme iterator (utf8.c's graphscan, with `width` tracking).

const OTHER: i64 = 0i64
const CR: i64 = 1i64
const CONTROL: i64 = 2i64
const EXTEND_INCB_EXTEND: i64 = 3i64
const EXTEND_INCB_LINKER: i64 = 4i64
const EXTEND_OTHER: i64 = 5i64
const EXTENDED_PICTOGRAPHIC: i64 = 6i64
const INCB_CONSONANT: i64 = 7i64
const L: i64 = 8i64
const LF: i64 = 9i64
const LV: i64 = 10i64
const LVT: i64 = 11i64
const PREPEND: i64 = 12i64
const REGIONAL_INDICATOR: i64 = 13i64
const SPACINGMARK: i64 = 14i64
const T: i64 = 15i64
const V: i64 = 16i64
const ZWJ: i64 = 17i64

type Iter = struct { s: str, nxt: usize, cnd: usize, prop: i64, code: i64, cw: i64, cnd_width: i64, done: i64 }

fn width_of_class(cw: i64) -> i64 {
    if cw == 5i64 || cw == 6i64 { ret 2i64 }
    if cw == 3i64 || cw == 4i64 { ret 1i64 }
    ret 0i64
}

fn decode(it: *Iter) {
    let s = it.s
    let c = i64(s[it.nxt])
    var code = c
    var extra = 0usize
    if c >= 128i64 {
        if c < 224i64 {
            code = c & 31i64
            extra = 1usize
        } else if c < 240i64 {
            code = c & 15i64
            extra = 2usize
        } else {
            code = c & 7i64
            extra = 3usize
        }
    }
    it.nxt += 1usize
    var k = 0usize
    while k < extra && it.nxt < s.len {
        code = code * 64i64 + (i64(s[it.nxt]) & 63i64)
        it.nxt += 1usize
        k += 1usize
    }
    it.code = code
}

// NEXT(): the lookahead becomes the candidate; read the one after it.
fn advance(it: *Iter) {
    it.cnd = it.nxt
    if it.nxt >= it.s.len {
        it.prop = -1i64
    } else {
        decode(it)
        it.prop = graph_break(it.code)
    }
    if it.done >= 0i64 {
        if it.cw >= 0i64 {
            if it.done == 0i64 {
                it.cnd_width = it.cnd_width + width_of_class(it.cw)
                if it.cw == 6i64 { it.done = 1i64 }
            }
        }
        if it.prop != -1i64 { it.cw = char_width(it.code) }
    }
}

fn iter_make(s: str, with_width: bool) -> Iter {
    var it: Iter = zero
    it.s = s
    it.nxt = 0usize
    it.cw = -1i64
    it.cnd_width = 0i64
    it.done = 0i64
    if !with_width { it.done = -1i64 }
    advance(&it)
    ret it
}

// One grapheme: consume its characters and answer its display width. `it.cnd` is then the
// offset of the next grapheme.
fn iter_next(it: *Iter) -> i64 {
    // States: 0 start, 1 CR, 2 L, 3 V, 4 T, 5 Prepend, 6 InCB consonant, 7 InCB linker,
    // 8 Extended_Pictographic, 9 Regional_Indicator, 10 maybe break, 11 break.
    var state = 0i64
    while state != 11i64 {
        let p = it.prop
        if state == 0i64 {
            if p < 0i64 {
                state = 11i64
            } else if p == CR {
                advance(it)
                state = 1i64
            } else if p == CONTROL || p == LF {
                advance(it)
                state = 11i64
            } else if p == L {
                advance(it)
                state = 2i64
            } else if p == LV || p == V {
                advance(it)
                state = 3i64
            } else if p == LVT || p == T {
                advance(it)
                state = 4i64
            } else if p == PREPEND {
                advance(it)
                state = 5i64
            } else if p == INCB_CONSONANT {
                advance(it)
                state = 6i64
            } else if p == EXTENDED_PICTOGRAPHIC {
                advance(it)
                state = 8i64
            } else if p == REGIONAL_INDICATOR {
                advance(it)
                state = 9i64
            } else {
                advance(it)
                state = 10i64
            }
        } else if state == 1i64 {
            if p == LF { advance(it) }
            state = 11i64
        } else if state == 2i64 {
            if p == L {
                advance(it)
            } else if p == V || p == LV {
                advance(it)
                state = 3i64
            } else if p == LVT {
                advance(it)
                state = 4i64
            } else {
                state = 10i64
            }
        } else if state == 3i64 {
            if p == V {
                advance(it)
            } else if p == T {
                advance(it)
                state = 4i64
            } else {
                state = 10i64
            }
        } else if state == 4i64 {
            if p == T { advance(it) } else { state = 10i64 }
        } else if state == 5i64 {
            if p == CONTROL || p == CR || p == LF { state = 11i64 } else { state = 0i64 }
        } else if state == 6i64 {
            while it.prop == EXTEND_INCB_EXTEND || it.prop == ZWJ { advance(it) }
            if it.prop == EXTEND_INCB_LINKER {
                advance(it)
                state = 7i64
            } else {
                state = 10i64
            }
        } else if state == 7i64 {
            while it.prop == EXTEND_INCB_EXTEND || it.prop == EXTEND_INCB_LINKER || it.prop == ZWJ { advance(it) }
            if it.prop == INCB_CONSONANT {
                advance(it)
                state = 6i64
            } else {
                state = 10i64
            }
        } else if state == 8i64 {
            while it.prop == EXTEND_OTHER || it.prop == EXTEND_INCB_EXTEND || it.prop == EXTEND_INCB_LINKER { advance(it) }
            state = 10i64
            if it.prop == ZWJ {
                advance(it)
                if it.prop == EXTENDED_PICTOGRAPHIC {
                    advance(it)
                    state = 8i64
                }
            }
        } else if state == 9i64 {
            if it.prop == REGIONAL_INDICATOR { advance(it) }
            state = 10i64
        } else {
            if p == EXTEND_OTHER || p == EXTEND_INCB_EXTEND || p == EXTEND_INCB_LINKER || p == SPACINGMARK || p == ZWJ {
                advance(it)
            } else {
                state = 11i64
            }
        }
    }
    let w = it.cnd_width
    it.cnd_width = 0i64
    if it.done > 0i64 { it.done = 0i64 }
    ret w
}

fn count_graphemes(piece: str) -> i64 {
    var it = iter_make(piece, false)
    var n = 0i64
    while it.prop != -1i64 {
        let _ = iter_next(&it)
        n += 1i64
    }
    ret n
}

fn display_width(piece: str) -> i64 {
    var it = iter_make(piece, true)
    var total = 0i64
    while it.prop != -1i64 { total = total + iter_next(&it) }
    ret total
}

fn count_codepoints(piece: str) -> i64 {
    var n = 0i64
    var i = 0usize
    while i < piece.len {
        if (piece[i] & 192u8) != 128u8 { n += 1i64 }
        i += 1usize
    }
    ret n
}

// --- The scanner (ansi.c's iterator): text pieces and escape sequences, in order.

const TEXT: i64 = 0i64
const SGR: i64 = 1i64
const CSI: i64 = 2i64
const LINK: i64 = 3i64

// For a text piece, `a`..`b`; for SGR and CSI, `a` the first parameter byte, `b` where the
// intermediate bytes begin and `c` the final byte; for a link, `a` the parameters, `b` the URI
// and `c` the terminator.
type Token = struct { kind: i64, a: usize, b: usize, c: usize }

type Scanner = struct { s: str, x: usize, shaft: usize, held: bool, tag: Token }

fn at(s: str, i: usize) -> u8 {
    if i < s.len { ret s[i] }
    ret 0u8
}

fn scanner(s: str) -> Scanner {
    var sc: Scanner = zero
    sc.s = s
    ret sc
}

fn put(tok: *Token, kind: i64, a: usize, b: usize, c: usize) {
    tok.kind = kind
    tok.a = a
    tok.b = b
    tok.c = c
}

// The next token, or false at the end of the string.
fn scan_next(sc: *Scanner, tok: *Token) -> bool {
    let s = sc.s
    if sc.held {
        sc.held = false
        put(tok, sc.tag.kind, sc.tag.a, sc.tag.b, sc.tag.c)
        ret true
    }
    while at(s, sc.x) != 0u8 && sc.x < s.len {
        let c = at(s, sc.x)
        if c == 27u8 && at(s, sc.x + 1usize) == 91u8 {
            let start = sc.x
            let param = start + 2usize
            var intermed = param
            while at(s, intermed) >= 48u8 && at(s, intermed) <= 63u8 { intermed += 1usize }
            var end = intermed
            while at(s, end) >= 32u8 && at(s, end) <= 47u8 { end += 1usize }
            var kind = CSI
            if at(s, end) == 109u8 { kind = SGR }
            sc.tag = Token { kind: kind, a: param, b: intermed, c: end }
            var next = end
            if at(s, end) != 0u8 { next = end + 1usize }
            let had_text = start > sc.shaft
            let text_from = sc.shaft
            sc.shaft = end + 1usize
            sc.x = next
            if had_text {
                sc.held = true
                put(tok, TEXT, text_from, start, 0usize)
                ret true
            }
            put(tok, sc.tag.kind, sc.tag.a, sc.tag.b, sc.tag.c)
            ret true
        } else if c == 27u8 && at(s, sc.x + 1usize) == 93u8 && at(s, sc.x + 2usize) == 56u8 && at(s, sc.x + 3usize) == 59u8 {
            let start = sc.x
            let param = start + 4usize
            var uri = param
            while at(s, uri) != 59u8 && at(s, uri) != 0u8 { uri += 1usize }
            uri += 1usize
            var end = uri
            while true {
                if at(s, end) == 0u8 { break }
                if at(s, end) == 7u8 { break }
                if at(s, end) == 92u8 && end > 0usize && at(s, end - 1usize) == 27u8 { break }
                end += 1usize
            }
            sc.tag = Token { kind: LINK, a: param, b: uri, c: end }
            var next = end
            if at(s, end) != 0u8 { next = end + 1usize }
            let had_text = start > sc.shaft
            let text_from = sc.shaft
            sc.shaft = end + 1usize
            sc.x = next
            if had_text {
                sc.held = true
                put(tok, TEXT, text_from, start, 0usize)
                ret true
            }
            put(tok, sc.tag.kind, sc.tag.a, sc.tag.b, sc.tag.c)
            ret true
        } else {
            sc.x += 1usize
        }
        while sc.x < s.len && at(s, sc.x) != 27u8 { sc.x += 1usize }
    }
    if sc.x > sc.shaft {
        let from = sc.shaft
        sc.shaft = sc.x
        put(tok, TEXT, from, sc.x, 0usize)
        ret true
    }
    ret false
}

// --- SGR state, and how it is written back.

type Color = struct { col: u8, r: u8, g: u8, b: u8 }

// `link` is the offset of the URI plus one (0 is no link), `link_param` and `link_end` the
// offsets of the parameters and of the terminator.
type Sgr = struct { fg: Color, bg: Color, bold: u8, faint: u8, italic: u8, underline: u8, blink: u8, inverse: u8, hide: u8, crossedout: u8, link: usize, link_param: usize, link_end: usize }

type State = struct { old: Sgr, new: Sgr, unknown: bool, off: bool }

fn same_color(a: Color, b: Color) -> bool { ret a.col == b.col && a.r == b.r && a.g == b.g && a.b == b.b }

fn emit_num(b: *str.Builder, prefix: str, v: u64, suffix: str) {
    let _ = str.push(b, prefix)
    let _ = str.push_u64(b, v)
    let _ = str.push(b, suffix)
}

fn emit_color(b: *str.Builder, c: Color, background: bool) {
    var base = 38u64
    if background { base = 48u64 }
    if c.col == 254u8 {
        let _ = str.push(b, "\x1b[")
        let _ = str.push_u64(b, base)
        let _ = str.push(b, ";5;")
        let _ = str.push_u64(b, u64(c.r))
        let _ = str.push(b, "m")
    } else if c.col == 255u8 {
        let _ = str.push(b, "\x1b[")
        let _ = str.push_u64(b, base)
        let _ = str.push(b, ";2;")
        let _ = str.push_u64(b, u64(c.r))
        let _ = str.push(b, ";")
        let _ = str.push_u64(b, u64(c.g))
        let _ = str.push(b, ";")
        let _ = str.push_u64(b, u64(c.b))
        let _ = str.push(b, "m")
    } else {
        emit_num(b, "\x1b[", u64(c.col), "m")
    }
}

fn link_text_end(s: str, st: *const Sgr) -> usize {
    let end = st.link_end
    if at(s, end) == 7u8 { ret end }
    if at(s, end) == 92u8 && end > 0usize && at(s, end - 1usize) == 27u8 { ret end - 1usize }
    ret end - 1usize
}

// clic__state_update_buffer: write what changes from `old` to `new`, then `old = new`.
fn flush(b: *str.Builder, s: str, st: *State) {
    if st.unknown && st.off {
        st.unknown = false
        st.off = false
        let _ = str.push(b, "\x1b[0m")
    }
    if st.old.bg.col != 0u8 && st.new.bg.col != st.old.bg.col { let _ = str.push(b, "\x1b[49m") }
    if st.old.fg.col != 0u8 && st.new.fg.col != st.old.fg.col { let _ = str.push(b, "\x1b[39m") }
    if st.new.crossedout < st.old.crossedout { let _ = str.push(b, "\x1b[29m") }
    if st.new.hide < st.old.hide { let _ = str.push(b, "\x1b[28m") }
    if st.new.inverse < st.old.inverse { let _ = str.push(b, "\x1b[27m") }
    if st.new.blink < st.old.blink { let _ = str.push(b, "\x1b[25m") }
    if st.new.underline < st.old.underline { let _ = str.push(b, "\x1b[24m") }
    if st.new.italic < st.old.italic { let _ = str.push(b, "\x1b[23m") }
    if st.new.faint < st.old.faint { let _ = str.push(b, "\x1b[22m") }
    if st.new.bold < st.old.bold { let _ = str.push(b, "\x1b[22m") }
    if st.old.link != 0usize && st.new.link != st.old.link { let _ = str.push(b, "\x1b]8;;\x07") }
    if st.new.link != 0usize && st.new.link != st.old.link {
        let _ = str.push(b, "\x1b]8;")
        let uri = st.new.link - 1usize
        let _ = str.push(b, s[st.new.link_param..uri])
        let _ = str.push(b, s[uri..link_text_end(s, &st.new)])
        let _ = str.push(b, "\x07")
    }
    if st.new.bold > st.old.bold { let _ = str.push(b, "\x1b[1m") }
    if st.new.faint > st.old.faint { let _ = str.push(b, "\x1b[2m") }
    if st.new.italic > st.old.italic { let _ = str.push(b, "\x1b[3m") }
    if st.new.underline > st.old.underline { let _ = str.push(b, "\x1b[4m") }
    if st.new.blink > st.old.blink { let _ = str.push(b, "\x1b[5m") }
    if st.new.inverse > st.old.inverse { let _ = str.push(b, "\x1b[7m") }
    if st.new.hide > st.old.hide { let _ = str.push(b, "\x1b[8m") }
    if st.new.crossedout > st.old.crossedout { let _ = str.push(b, "\x1b[9m") }
    if st.new.fg.col != 0u8 && !same_color(st.new.fg, st.old.fg) { emit_color(b, st.new.fg, false) }
    if st.new.bg.col != 0u8 && !same_color(st.new.bg, st.old.bg) { emit_color(b, st.new.bg, true) }
    st.old = st.new
}

// strtol on the parameter bytes: the digits at `p`, and where they end.
fn read_int(s: str, p: usize, limit: usize) -> (i64, usize) {
    var v = 0i64
    var q = p
    while q < limit && at(s, q) >= 48u8 && at(s, q) <= 57u8 {
        v = v * 10i64 + (i64(at(s, q)) - 48i64)
        q += 1usize
    }
    ret (v, q)
}

fn read_num(s: str, ptr: usize, end: usize) -> (u8, usize) {
    var p = ptr
    var value = 0i64
    if at(s, p) != 59u8 || p >= end { ret (0u8, p) }
    p += 1usize
    let (v, q) = read_int(s, p, end)
    value = v
    p = q
    while p < end && at(s, p) != 59u8 { p += 1usize }
    ret (u8(value & 255i64), p)
}

// clic__parse_color: after 38 or 48, `;5;n` or `;2;r;g;b`; anything else skips the tag.
fn parse_color(s: str, ptr: usize, end: usize, col: *Color) -> usize {
    if at(s, ptr) != 59u8 || (at(s, ptr + 1usize) != 53u8 && at(s, ptr + 1usize) != 50u8) || at(s, ptr + 2usize) != 59u8 {
        col.r = 0u8
        col.g = 0u8
        col.b = 0u8
        ret end
    }
    var kind = 255u8
    if at(s, ptr + 1usize) == 53u8 { kind = 254u8 }
    col.col = kind
    var p = ptr + 2usize
    let (r, p1) = read_num(s, p, end)
    p = p1
    var g = 0u8
    var b = 0u8
    if kind == 255u8 {
        let (g1, p2) = read_num(s, p, end)
        g = g1
        p = p2
        let (b1, p3) = read_num(s, p, end)
        b = b1
        p = p3
    }
    col.r = r
    col.g = g
    col.b = b
    ret p
}

// clic__ansi_update_state: apply one SGR sequence to `new`; an attribute this does not know is
// written out at once.
fn update_state(b: *str.Builder, s: str, st: *State, param: usize, intermed: usize, end: usize) {
    var start = param
    var endptr = param
    while true {
        let (num, e1) = read_int(s, start, intermed)
        endptr = e1
        if endptr == start || num == 0i64 {
            st.new = blank()
            st.off = true
        } else if num == 1i64 {
            st.new.bold = 1u8
        } else if num == 2i64 {
            st.new.faint = 1u8
        } else if num == 3i64 {
            st.new.italic = 1u8
        } else if num == 4i64 {
            st.new.underline = 1u8
        } else if num == 5i64 {
            st.new.blink = 1u8
        } else if num == 7i64 {
            st.new.inverse = 1u8
        } else if num == 8i64 {
            st.new.hide = 1u8
        } else if num == 9i64 {
            st.new.crossedout = 1u8
        } else if num == 22i64 {
            st.new.bold = 0u8
            st.new.faint = 0u8
        } else if num == 23i64 {
            st.new.italic = 0u8
        } else if num == 24i64 {
            st.new.underline = 0u8
        } else if num == 25i64 {
            st.new.blink = 0u8
        } else if num == 27i64 {
            st.new.inverse = 0u8
        } else if num == 28i64 {
            st.new.hide = 0u8
        } else if num == 29i64 {
            st.new.crossedout = 0u8
        } else if (num >= 30i64 && num <= 37i64) || (num >= 90i64 && num <= 97i64) {
            st.new.fg.col = u8(num)
        } else if num == 38i64 {
            endptr = parse_color(s, endptr, intermed, &st.new.fg)
        } else if num == 39i64 {
            st.new.fg.col = 0u8
        } else if (num >= 40i64 && num <= 47i64) || (num >= 100i64 && num <= 107i64) {
            st.new.bg.col = u8(num)
        } else if num == 48i64 {
            endptr = parse_color(s, endptr, intermed, &st.new.bg)
        } else if num == 49i64 {
            st.new.bg.col = 0u8
        } else {
            st.unknown = true
            let _ = str.push(b, s[param - 2usize..end + 1usize])
        }
        start = endptr + 1usize
        if !(endptr < intermed && at(s, endptr) == 59u8) { break }
    }
}

fn update_link(s: str, st: *State, param: usize, uri: usize, end: usize) {
    if (at(s, uri) == 27u8 && at(s, uri + 1usize) == 92u8) || at(s, uri) == 7u8 {
        st.new.link = 0usize
        st.new.link_param = 0usize
        st.new.link_end = 0usize
    } else {
        st.new.link = uri + 1usize
        st.new.link_param = param
        st.new.link_end = end
    }
}

// --- Operations.

fn alloc_strs(a: *mem.Arena, n: usize) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, n)
    ret (out, e)
}

// ansi_strip(x, sgr, csi, link).
fn strip(a: *mem.Arena, x: []const str, sgr: bool, csi: bool, link: bool) -> ([]str, err) {
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        let s = x[i]
        let (initial, be) = str.builder(a, s.len + 1usize)
        if be != ok { ret (out, be) }
        var b = initial
        var sc = scanner(s)
        var tok: Token = zero
        var tags = 0usize
        while scan_next(&sc, &tok) {
            if tok.kind == TEXT {
                let _ = str.push(&b, s[tok.a..tok.b])
            } else if tok.kind == SGR {
                if sgr { tags += 1usize } else { let _ = str.push(&b, s[tok.a - 2usize..tok.c + 1usize]) }
            } else if tok.kind == CSI {
                if csi { tags += 1usize } else { let _ = str.push(&b, s[tok.a - 2usize..tok.c + 1usize]) }
            } else {
                if link { tags += 1usize } else { let _ = str.push(&b, s[tok.a - 4usize..tok.c + 1usize]) }
            }
        }
        let built = str.done(&b)
        if tags == 0usize { out[i] = s } else { out[i] = built }
        i += 1usize
    }
    ret (out, ok)
}

fn has_any(a: *mem.Arena, x: []const str, sgr: bool, csi: bool, link: bool) -> ([]bool, err) {
    let (out, e) = mem.alloc[bool](a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        var sc = scanner(x[i])
        var tok: Token = zero
        var has = false
        while !has && scan_next(&sc, &tok) {
            if tok.kind == SGR && sgr { has = true }
            if tok.kind == CSI && csi { has = true }
            if tok.kind == LINK && link { has = true }
        }
        out[i] = has
        i += 1usize
    }
    ret (out, ok)
}

// ansi_nchar(x, type): 0 graphemes ("chars"), 1 bytes, 2 width, 3 code points.
fn nchar(a: *mem.Arena, x: []const str, typ: u8) -> ([]i64, err) {
    let (out, e) = mem.alloc[i64](a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        let s = x[i]
        var sc = scanner(s)
        var tok: Token = zero
        var total = 0i64
        while scan_next(&sc, &tok) {
            if tok.kind == TEXT {
                let piece = s[tok.a..tok.b]
                if typ == 0u8 { total = total + count_graphemes(piece) }
                if typ == 1u8 { total = total + i64(piece.len) }
                if typ == 2u8 { total = total + display_width(piece) }
                if typ == 3u8 { total = total + count_codepoints(piece) }
            }
        }
        out[i] = total
        i += 1usize
    }
    ret (out, ok)
}

// ansi_simplify(x, csi = keep).
fn simplify(a: *mem.Arena, x: []const str, keep_csi: bool) -> ([]str, err) {
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        let s = x[i]
        let (initial, be) = str.builder(a, s.len + 16usize)
        if be != ok { ret (out, be) }
        var b = initial
        var st: State = zero
        var sc = scanner(s)
        var tok: Token = zero
        var tags = 0usize
        while scan_next(&sc, &tok) {
            if tok.kind == TEXT {
                flush(&b, s, &st)
                let _ = str.push(&b, s[tok.a..tok.b])
            } else if tok.kind == SGR {
                tags += 1usize
                update_state(&b, s, &st, tok.a, tok.b, tok.c)
            } else if tok.kind == CSI {
                if keep_csi { let _ = str.push(&b, s[tok.a - 2usize..tok.c + 1usize]) } else { tags += 1usize }
            } else {
                tags += 1usize
                update_link(s, &st, tok.a, tok.b, tok.c)
            }
        }
        st.new = blank()
        flush(&b, s, &st)
        let built = str.done(&b)
        if tags == 0usize { out[i] = s } else { out[i] = built }
        i += 1usize
    }
    ret (out, ok)
}

// ansi_substr(x, start, stop), in graphemes, 1-based and inclusive, keeping the styling.
fn substr(a: *mem.Arena, x: []const str, start: []const i64, stop: []const i64) -> ([]str, err) {
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        let s = x[i]
        let first = start[i % start.len]
        let last = stop[i % stop.len]
        let (initial, be) = str.builder(a, s.len + 16usize)
        if be != ok { ret (out, be) }
        var b = initial
        var st: State = zero
        var sc = scanner(s)
        var tok: Token = zero
        var pos = 1i64
        var finished = false
        while !finished && scan_next(&sc, &tok) {
            if tok.kind == SGR {
                update_state(&b, s, &st, tok.a, tok.b, tok.c)
            } else if tok.kind == LINK {
                update_link(s, &st, tok.a, tok.b, tok.c)
            } else if tok.kind == TEXT {
                var from = tok.a
                let end = tok.b
                if pos < first {
                    var it = iter_make(s[from..end], false)
                    while pos < first && it.prop != -1i64 {
                        let _ = iter_next(&it)
                        pos += 1i64
                    }
                    from = from + it.cnd
                }
                if pos <= last {
                    let begin = from
                    var it = iter_make(s[from..end], false)
                    while pos <= last && it.prop != -1i64 {
                        let _ = iter_next(&it)
                        pos += 1i64
                    }
                    from = from + it.cnd
                    if begin < from {
                        flush(&b, s, &st)
                        let _ = str.push(&b, s[begin..from])
                    }
                }
                if pos > last {
                    st.new = blank()
                    flush(&b, s, &st)
                    finished = true
                }
            }
        }
        st.new = blank()
        flush(&b, s, &st)
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 13u8 || c == 10u8 }

fn plain_of(a: *mem.Arena, x: []const str) -> ([]str, err) {
    let (r, e) = strip(a, x, true, true, true)
    ret (r, e)
}

// ansi_trimws(x, which): 0 both, 1 left, 2 right.
fn trimws(a: *mem.Arena, x: []const str, which: u8) -> ([]str, err) {
    let (plain, pe) = plain_of(a, x)
    if pe != ok { ret (plain, pe) }
    let (lens, le) = nchar(a, x, 0u8)
    if le != ok { ret (plain, le) }
    let (starts, se) = mem.alloc[i64](a, x.len)
    let (stops, ee) = mem.alloc[i64](a, x.len)
    if se != ok { ret (plain, se) }
    if ee != ok { ret (plain, ee) }
    var any = false
    var i = 0usize
    while i < x.len {
        var sl = 0usize
        var rl = 0usize
        let p = plain[i]
        if which == 0u8 || which == 1u8 {
            while sl < p.len && is_space(p[sl]) { sl += 1usize }
        }
        if which == 0u8 || which == 2u8 {
            while rl < p.len - sl && is_space(p[p.len - 1usize - rl]) { rl += 1usize }
        }
        if sl > 0usize || rl > 0usize { any = true }
        starts[i] = 1i64 + i64(sl)
        stops[i] = lens[i] - i64(rl)
        i += 1usize
    }
    if !any {
        let (same, ce2) = x_copy(a, x)
        ret (same, ce2)
    }
    let (r, e) = substr(a, x, starts, stops)
    ret (r, e)
}

fn x_copy(a: *mem.Arena, x: []const str) -> ([]str, err) {
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        out[i] = x[i]
        i += 1usize
    }
    ret (out, ok)
}

// ansi_align(x, width, align, type): 0 left, 1 center, 2 right; `typ` as in `nchar`.
fn align(a: *mem.Arena, x: []const str, width: i64, how: u8, typ: u8) -> ([]str, err) {
    let (counts, ce) = nchar(a, x, typ)
    if ce != ok {
        let (same, ce2) = x_copy(a, x)
        ret (same, ce2)
    }
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        var gap = width - counts[i]
        if gap < 0i64 { gap = 0i64 }
        var left = 0i64
        var right = 0i64
        if how == 0u8 { right = gap }
        if how == 2u8 { left = gap }
        if how == 1u8 {
            left = (gap + 1i64) / 2i64
            right = gap / 2i64
        }
        let (initial, be) = str.builder(a, x[i].len + usize(gap) + 1usize)
        if be != ok { ret (out, be) }
        var b = initial
        var k = 0i64
        while k < left {
            let _ = str.push_byte(&b, 32u8)
            k += 1i64
        }
        let _ = str.push(&b, x[i])
        k = 0i64
        while k < right {
            let _ = str.push_byte(&b, 32u8)
            k += 1i64
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

// ansi_toupper / ansi_tolower for ASCII letters in the text between escapes.
fn convert_case(a: *mem.Arena, x: []const str, upper: bool) -> ([]str, err) {
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        let s = x[i]
        let (initial, be) = str.builder(a, s.len + 1usize)
        if be != ok { ret (out, be) }
        var b = initial
        var sc = scanner(s)
        var tok: Token = zero
        var cursor = 0usize
        while scan_next(&sc, &tok) {
            if tok.kind == TEXT {
                let _ = str.push(&b, s[cursor..tok.a])
                var k = tok.a
                while k < tok.b {
                    var c = s[k]
                    if upper && c >= 97u8 && c <= 122u8 { c = c - 32u8 }
                    if !upper && c >= 65u8 && c <= 90u8 { c = c + 32u8 }
                    let _ = str.push_byte(&b, c)
                    k += 1usize
                }
                cursor = tok.b
            }
        }
        let _ = str.push(&b, s[cursor..s.len])
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

// --- ansi_html.

fn html_start(b: *str.Builder, s: str, st: *State) -> (bool, bool) {
    var first = true
    var is_link = false
    if st.new.link != 0usize && st.new.link != st.old.link {
        let _ = str.push(b, "<a class=\"ansi-link\" href=\"")
        let uri = st.new.link - 1usize
        let _ = str.push(b, s[uri..link_text_end(s, &st.new)])
        let _ = str.push(b, "\">")
        is_link = true
    }
    if st.new.bold > st.old.bold { first = html_attr(b, first, " ansi-bold") }
    if st.new.faint > st.old.faint { first = html_attr(b, first, " ansi-faint") }
    if st.new.italic > st.old.italic { first = html_attr(b, first, " ansi-italic") }
    if st.new.underline > st.old.underline { first = html_attr(b, first, " ansi-underline") }
    if st.new.blink > st.old.blink { first = html_attr(b, first, " ansi-blink") }
    if st.new.inverse > st.old.inverse { first = html_attr(b, first, " ansi-inverse") }
    if st.new.hide > st.old.hide { first = html_attr(b, first, " ansi-hide") }
    if st.new.crossedout > st.old.crossedout { first = html_attr(b, first, " ansi-crossedout") }
    if st.new.fg.col != 0u8 && !same_color(st.new.fg, st.old.fg) {
        first = html_color(b, first, st.new.fg, " ansi-color-", 30u8)
    }
    if st.new.bg.col != 0u8 && !same_color(st.new.bg, st.old.bg) {
        first = html_color(b, first, st.new.bg, " ansi-bg-color-", 40u8)
    }
    st.old = st.new
    if !first { let _ = str.push(b, "\">") }
    ret (!first, is_link)
}

fn html_attr(b: *str.Builder, first: bool, name: str) -> bool {
    if first { let _ = str.push(b, "<span class=\"ansi") }
    let _ = str.push(b, name)
    ret false
}

fn html_color(b: *str.Builder, first: bool, c: Color, prefix: str, base: u8) -> bool {
    if first { let _ = str.push(b, "<span class=\"ansi") }
    let _ = str.push(b, prefix)
    if c.col == 254u8 {
        let _ = str.push_u64(b, u64(c.r))
    } else if c.col == 255u8 {
        let _ = str.push_u64(b, u64(c.r))
        let _ = str.push(b, "-")
        let _ = str.push_u64(b, u64(c.g))
        let _ = str.push(b, "-")
        let _ = str.push_u64(b, u64(c.b))
    } else {
        var n = c.col - base
        if n > 7u8 { n = n - 60u8 }
        let _ = str.push_u64(b, u64(n))
    }
    ret false
}

fn escape_reserved(a: *mem.Arena, s: str) -> str {
    let (initial, be) = str.builder(a, s.len + 16usize)
    if be != ok { ret s }
    var b = initial
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 38u8 {
            let _ = str.push(&b, "&amp;")
        } else if c == 60u8 {
            let _ = str.push(&b, "&lt;")
        } else if c == 62u8 {
            let _ = str.push(&b, "&gt;")
        } else {
            let _ = str.push_byte(&b, c)
        }
        i += 1usize
    }
    ret str.done(&b)
}

// ansi_html(x, escape_reserved, csi).
fn html(a: *mem.Arena, x: []const str, escape: bool, keep_csi: bool) -> ([]str, err) {
    let (out, e) = alloc_strs(a, x.len)
    if e != ok { ret (out, e) }
    var prepared = x
    var escaped: []str = zero
    if escape {
        let (copy, ce) = alloc_strs(a, x.len)
        if ce != ok { ret (out, ce) }
        var k = 0usize
        while k < x.len {
            copy[k] = escape_reserved(a, x[k])
            k += 1usize
        }
        escaped = copy
    }
    var i = 0usize
    while i < x.len {
        var s = x[i]
        if escape { s = escaped[i] }
        let (initial, be) = str.builder(a, s.len * 2usize + 16usize)
        if be != ok { ret (out, be) }
        var b = initial
        var st: State = zero
        var sc = scanner(s)
        var tok: Token = zero
        while scan_next(&sc, &tok) {
            if tok.kind == SGR {
                update_state(&b, s, &st, tok.a, tok.b, tok.c)
            } else if tok.kind == CSI {
                if keep_csi { let _ = str.push(&b, s[tok.a - 2usize..tok.c + 1usize]) }
            } else if tok.kind == LINK {
                update_link(s, &st, tok.a, tok.b, tok.c)
            } else {
                let (had_tags, is_link) = html_start(&b, s, &st)
                let _ = str.push(&b, s[tok.a..tok.b])
                if had_tags { let _ = str.push(&b, "</span>") }
                if is_link { let _ = str.push(&b, "</a>") }
            }
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

fn blank() -> Sgr {
    var z: Sgr = zero
    ret z
}
