// Terminal output kit: a tqdm-style progress meter line, rich-style markup rendered to
// ANSI SGR, and boxed text tables. Everything is a pure function from values to a
// string, so a caller decides where it goes (stderr, a log, a golden file) and when
// the clock is read: `render_meter` takes the elapsed seconds, never a time source.
// Widths count Unicode scalars; wide (East Asian) and combining characters are one
// column each.
use e.mem
use e.str

type Align = enum u8 { Left, Right, Center }
type BoxStyle = enum u8 { Ascii, Square, Rounded, HeavyHead }
type Column = struct { header: str, align: Align }
error BadShape
error BadMarkup

fn display_width(s: str) -> usize {
    var count = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 { count += 1usize }
        i += 1usize
    }
    ret count
}

fn push_spaces(b: *str.Builder, n: usize) -> err {
    var i = 0usize
    while i < n {
        try str.push_byte(b, 32u8)
        i += 1usize
    }
    ret ok
}

fn push_two_digits(b: *str.Builder, v: u64) -> err {
    if v < 10u64 { try str.push_byte(b, 48u8) }
    ret str.push_u64(b, v)
}

fn digits(v: u64) -> usize {
    var n = 1usize
    var rest = v / 10u64
    while rest > 0u64 {
        n += 1usize
        rest = rest / 10u64
    }
    ret n
}

// Python's `round` and `'%.0f'` take the even neighbour of an exact half.
fn round_half_even(x: f64) -> u64 {
    let whole = u64(x)
    let frac = x - f64(whole)
    if frac > 0.5f64 { ret whole + 1u64 }
    if frac < 0.5f64 { ret whole }
    if whole % 2u64 == 0u64 { ret whole }
    ret whole + 1u64
}

// `[H:]MM:SS` from whole seconds, as tqdm's `format_interval`.
fn push_interval(b: *str.Builder, seconds: f64) -> err {
    let total = u64(seconds)
    let s = total % 60u64
    let mins = total / 60u64
    let m = mins % 60u64
    let h = mins / 60u64
    if h > 0u64 {
        try str.push_u64(b, h)
        try str.push_byte(b, 58u8)
    }
    if h > 0u64 {
        try push_two_digits(b, m)
    } else {
        try push_two_digits(b, mins)
    }
    try str.push_byte(b, 58u8)
    ret push_two_digits(b, s)
}

fn threshold(k: usize) -> f64 {
    if k == 1usize { ret 9.995f64 }
    if k == 2usize { ret 99.995f64 }
    if k == 3usize { ret 999.995f64 }
    if k == 4usize { ret 9999.995f64 }
    if k == 5usize { ret 99999.995f64 }
    if k == 6usize { ret 999999.995f64 }
    ret 9999999.995f64
}

// `{v:5.2f}`: two decimals, right-aligned in five columns.
fn push_fixed2(b: *str.Builder, v: f64) -> err {
    var k = 1usize
    var int_digits = 1usize
    while k <= 7usize && v > threshold(k) {
        int_digits += 1usize
        k += 1usize
    }
    if int_digits == 1usize { try str.push_byte(b, 32u8) }
    ret str.push_f64_fixed(b, v, 2u8)
}

fn push_rate(b: *str.Builder, n: u64, elapsed: f64, unit: str) -> err {
    if elapsed > 0.0f64 && n > 0u64 {
        let rate = f64(n) / elapsed
        let inv = 1.0f64 / rate
        if inv > 1.0f64 {
            try push_fixed2(b, inv)
            try str.push(b, "s/")
            ret str.push(b, unit)
        }
        try push_fixed2(b, rate)
        try str.push(b, unit)
        ret str.push(b, "/s")
    }
    try str.push_byte(b, 63u8)
    try str.push(b, unit)
    ret str.push(b, "/s")
}

fn push_bar(b: *str.Builder, frac_in: f64, columns: usize, ascii: bool) -> err {
    var frac = frac_in
    if frac > 1.0f64 { frac = 1.0f64 }
    if frac < 0.0f64 { frac = 0.0f64 }
    var steps = 8u64
    if ascii { steps = 10u64 }
    let k = u64(frac * f64(columns) * f64(steps))
    let full = usize(k / steps)
    let part = usize(k % steps)
    var i = 0usize
    while i < full {
        try str.push(b, bar_char(ascii, steps))
        i += 1usize
    }
    if full < columns {
        try str.push(b, bar_char(ascii, u64(part)))
        try push_spaces(b, columns - full - 1usize)
    }
    ret ok
}

// The first `columns` scalars of `s`.
fn trim_columns(s: str, columns: usize) -> str {
    var seen = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 {
            if seen == columns { ret s[0usize..i] }
            seen += 1usize
        }
        i += 1usize
    }
    ret s
}

// One progress line in tqdm's default layout, `prefix: PPP%|bar| n/total [elapsed<left,
// rate]` -- or, with `total == 0`, `prefix: n unit [elapsed, rate]`. `ncols` is the
// whole line's width and trims it; 0 gives a ten-column bar and no trim. `ascii` picks the ` 123456789#` bar.
fn meter_line(a: *mem.Arena, n: u64, total: u64, elapsed: f64, ncols: usize, prefix: str, unit: str, ascii: bool) -> (str, err) {
    let (b0, e0) = str.builder(a, 256usize)
    if e0 != ok { ret ("", e0) }
    var b = b0
    if prefix.len > 0usize {
        try str.push(&b, prefix)
        try str.push(&b, ": ")
    }
    // tqdm drops the bar once the count passes the total, as it does with no total.
    if total == 0u64 || n > total {
        try str.push_u64(&b, n)
        try str.push(&b, unit)
        try str.push(&b, " [")
        try push_interval(&b, elapsed)
        try str.push(&b, ", ")
        try push_rate(&b, n, elapsed, unit)
        try str.push(&b, "]")
        ret (str.done(&b), ok)
    }
    let left = str.done(&b)
    // The right-hand side first, so the bar knows how much room it has.
    let (r0, e1) = str.builder(a, 128usize)
    if e1 != ok { ret ("", e1) }
    var r = r0
    try str.push(&r, "| ")
    try str.push_u64(&r, n)
    try str.push_byte(&r, 47u8)
    try str.push_u64(&r, total)
    try str.push(&r, " [")
    try push_interval(&r, elapsed)
    try str.push_byte(&r, 60u8)
    if elapsed > 0.0f64 && n > 0u64 {
        let rate = f64(n) / elapsed
        var remaining = 0.0f64
        if total > n { remaining = f64(total - n) / rate }
        try push_interval(&r, remaining)
    } else {
        try str.push_byte(&r, 63u8)
    }
    try str.push(&r, ", ")
    try push_rate(&r, n, elapsed, unit)
    try str.push_byte(&r, 93u8)
    let right = str.done(&r)
    let frac = f64(n) / f64(total)
    let pct = round_half_even(frac * 100.0f64)
    let (o0, e2) = str.builder(a, left.len + right.len + ncols * 4usize + 32usize)
    if e2 != ok { ret ("", e2) }
    var o = o0
    try str.push(&o, left)
    var pct_digits = digits(pct)
    while pct_digits < 3usize {
        try str.push_byte(&o, 32u8)
        pct_digits += 1usize
    }
    try str.push_u64(&o, pct)
    try str.push(&o, "%|")
    var pct_width = 3usize
    if digits(pct) > pct_width { pct_width = digits(pct) }
    let used = display_width(left) + pct_width + 2usize + display_width(right)
    var room = 10usize
    if ncols > 0usize {
        room = 1usize
        if ncols > used { room = ncols - used }
    }
    try push_bar(&o, frac, room, ascii)
    try str.push(&o, right)
    ret (str.done(&o), ok)
}

fn render_meter(a: *mem.Arena, n: u64, total: u64, elapsed: f64, ncols: usize, prefix: str, unit: str, ascii: bool) -> (str, err) {
    let (line, e) = meter_line(a, n, total, elapsed, ncols, prefix, unit, ascii)
    if e != ok { ret ("", e) }
    if ncols == 0usize { ret (line, ok) }
    ret (trim_columns(line, ncols), ok)
}

// ---- tables -------------------------------------------------------------------------

fn push_cell(b: *str.Builder, s: str, w: usize, align: Align) -> err {
    let gap = w - display_width(s)
    var before = 0usize
    if align == .Right { before = gap }
    if align == .Center { before = gap / 2usize }
    try push_spaces(b, before)
    try str.push(b, s)
    ret push_spaces(b, gap - before)
}

fn push_line(b: *str.Builder, style: BoxStyle, row: usize, widths: []const usize) -> err {
    try str.push(b, box_part(style, row, 0usize))
    var i = 0usize
    while i < widths.len {
        if i > 0usize { try str.push(b, box_part(style, row, 2usize)) }
        var k = 0usize
        while k < widths[i] + 2usize {
            try str.push(b, box_part(style, row, 1usize))
            k += 1usize
        }
        i += 1usize
    }
    try str.push(b, box_part(style, row, 3usize))
    ret str.push_byte(b, 10u8)
}

fn push_row(b: *str.Builder, style: BoxStyle, row: usize, cols: []const Column, cells: []const str, first: usize, widths: []const usize, header: bool) -> err {
    try str.push(b, box_part(style, row, 0usize))
    var i = 0usize
    while i < widths.len {
        if i > 0usize { try str.push(b, box_part(style, row, 2usize)) }
        try str.push_byte(b, 32u8)
        if header {
            try push_cell(b, cols[i].header, widths[i], cols[i].align)
        } else {
            try push_cell(b, cells[first + i], widths[i], cols[i].align)
        }
        try str.push_byte(b, 32u8)
        i += 1usize
    }
    try str.push(b, box_part(style, row, 3usize))
    ret str.push_byte(b, 10u8)
}

// A header row, a rule and the cells row-major (`cells.len` a multiple of the column
// count), each column as wide as its widest entry plus one space either side.
fn render_table(a: *mem.Arena, cols: []const Column, cells: []const str, style: BoxStyle) -> (str, err) {
    let n = cols.len
    if n == 0usize { ret ("", BadShape) }
    if cells.len % n != 0usize { ret ("", BadShape) }
    let (widths, we) = mem.alloc[usize](a, n)
    if we != ok { ret ("", we) }
    var i = 0usize
    while i < n {
        widths[i] = display_width(cols[i].header)
        i += 1usize
    }
    i = 0usize
    while i < cells.len {
        let w = display_width(cells[i])
        if w > widths[i % n] { widths[i % n] = w }
        i += 1usize
    }
    var cap = 256usize
    i = 0usize
    while i < n {
        cap += widths[i] * 4usize + 16usize
        i += 1usize
    }
    cap = cap * (cells.len / n + 4usize)
    let (b0, be) = str.builder(a, cap)
    if be != ok { ret ("", be) }
    var b = b0
    try push_line(&b, style, 0usize, widths)
    try push_row(&b, style, 1usize, cols, cells, 0usize, widths, true)
    try push_line(&b, style, 2usize, widths)
    var r = 0usize
    while r < cells.len / n {
        try push_row(&b, style, 3usize, cols, cells, r * n, widths, false)
        r += 1usize
    }
    try push_line(&b, style, 4usize, widths)
    ret (str.done(&b), ok)
}

// ---- markup -------------------------------------------------------------------------

const ATTR_BOLD: u16 = 1u16
const ATTR_DIM: u16 = 2u16
const ATTR_ITALIC: u16 = 4u16
const ATTR_UNDERLINE: u16 = 8u16
const ATTR_BLINK: u16 = 16u16
const ATTR_REVERSE: u16 = 64u16
const ATTR_CONCEAL: u16 = 128u16
const ATTR_STRIKE: u16 = 256u16
const MARKUP_DEPTH: usize = 16usize

// An attribute word's bit, 0 when it is not one.
fn attribute_bit(w: str) -> u16 {
    if str.eq(w, "bold") || str.eq(w, "b") { ret 1u16 }
    if str.eq(w, "dim") || str.eq(w, "d") { ret 2u16 }
    if str.eq(w, "italic") || str.eq(w, "i") { ret 4u16 }
    if str.eq(w, "underline") || str.eq(w, "u") { ret 8u16 }
    if str.eq(w, "blink") { ret 16u16 }
    if str.eq(w, "blink2") { ret 32u16 }
    if str.eq(w, "reverse") || str.eq(w, "r") { ret 64u16 }
    if str.eq(w, "conceal") || str.eq(w, "c") { ret 128u16 }
    if str.eq(w, "strike") || str.eq(w, "s") { ret 256u16 }
    ret 0u16
}

fn base_color(w: str) -> i32 {
    if str.eq(w, "black") { ret 0i32 }
    if str.eq(w, "red") { ret 1i32 }
    if str.eq(w, "green") { ret 2i32 }
    if str.eq(w, "yellow") { ret 3i32 }
    if str.eq(w, "blue") { ret 4i32 }
    if str.eq(w, "magenta") { ret 5i32 }
    if str.eq(w, "cyan") { ret 6i32 }
    if str.eq(w, "white") { ret 7i32 }
    ret -1i32
}

// A colour word's index 0..15 (`bright_` adds 8), or -1.
fn color_index(w: str) -> i32 {
    if str.starts_with(w, "bright_") {
        let c = base_color(w[7usize..])
        if c < 0i32 { ret -1i32 }
        ret c + 8i32
    }
    ret base_color(w)
}

type Entry = struct { attrs: u16, fg: u8, bg: u8, name: str }

fn is_tag_start(c: u8) -> bool {
    ret (c >= 97u8 && c <= 122u8) || c == 47u8 || c == 35u8 || c == 64u8
}

// One tag's words into an entry: attributes, a colour, `on` and a background colour.
fn parse_tag(body: str, e: *Entry) -> err {
    e.attrs = 0u16
    e.fg = 0u8
    e.bg = 0u8
    var i = 0usize
    var want_bg = false
    var seen = false
    while i < body.len {
        while i < body.len && body[i] == 32u8 { i += 1usize }
        if i >= body.len { break }
        let start = i
        while i < body.len && body[i] != 32u8 { i += 1usize }
        let w = body[start..i]
        seen = true
        if str.eq(w, "on") {
            want_bg = true
            continue
        }
        let bit = attribute_bit(w)
        if bit != 0u16 && !want_bg {
            e.attrs = e.attrs | bit
            continue
        }
        let ci = color_index(w)
        if ci < 0i32 { ret BadMarkup }
        var code = 0u8
        if want_bg {
            if ci < 8i32 { code = u8(40i32 + ci) } else { code = u8(92i32 + ci) }
            e.bg = code
            want_bg = false
        } else {
            if ci < 8i32 { code = u8(30i32 + ci) } else { code = u8(82i32 + ci) }
            e.fg = code
        }
    }
    if want_bg || !seen { ret BadMarkup }
    ret ok
}

fn push_sgr(b: *str.Builder, attrs: u16, fg: u8, bg: u8) -> err {
    try str.push_byte(b, 27u8)
    try str.push_byte(b, 91u8)
    var first = true
    var bit = 0u16
    while bit < 9u16 {
        if (attrs & (1u16 << bit)) != 0u16 {
            if !first { try str.push_byte(b, 59u8) }
            try str.push_u16(b, bit + 1u16)
            first = false
        }
        bit += 1u16
    }
    if fg != 0u8 {
        if !first { try str.push_byte(b, 59u8) }
        try str.push_u8(b, fg)
        first = false
    }
    if bg != 0u8 {
        if !first { try str.push_byte(b, 59u8) }
        try str.push_u8(b, bg)
    }
    ret str.push_byte(b, 109u8)
}

// `[bold red]text[/]`, `[/bold red]` and `\[` for a literal bracket become one SGR
// run per text segment (`ESC[1;31m text ESC[0m`), as rich writes them; `color` false
// strips the tags and keeps the text. A word that is not an attribute or a colour, an
// unclosed stack or a close with nothing open is `BadMarkup`.
fn render_markup(a: *mem.Arena, src: str, color: bool) -> (str, err) {
    let (b0, be) = str.builder(a, src.len * 3usize + 64usize)
    if be != ok { ret ("", be) }
    var b = b0
    var stack: [16]Entry = zero
    var depth = 0usize
    var open = false
    var i = 0usize
    while i < src.len {
        let c = src[i]
        var tag_end = 0usize
        var is_tag = false
        var escaped = false
        var from = i
        if c == 92u8 && i + 1usize < src.len && src[i + 1usize] == 91u8 {
            escaped = true
            from = i + 1usize
        }
        if (c == 91u8 || escaped) && from + 1usize < src.len && is_tag_start(src[from + 1usize]) {
            let (close, found) = str.find_from(src, "]", from + 1usize)
            if found {
                is_tag = true
                tag_end = close
            }
        }
        if is_tag && escaped {
            // the backslash goes, the bracketed text stays as text
            if color && !open && depth > 0usize {
                var attrs = 0u16
                var fg = 0u8
                var bg = 0u8
                var d = 0usize
                while d < depth {
                    attrs = attrs | stack[d].attrs
                    if stack[d].fg != 0u8 { fg = stack[d].fg }
                    if stack[d].bg != 0u8 { bg = stack[d].bg }
                    d += 1usize
                }
                if attrs != 0u16 || fg != 0u8 || bg != 0u8 {
                    try push_sgr(&b, attrs, fg, bg)
                    open = true
                }
            }
            var k = from
            while k <= tag_end {
                try str.push_byte(&b, src[k])
                k += 1usize
            }
            i = tag_end + 1usize
            continue
        }
        if is_tag {
            let body = src[i + 1usize..tag_end]
            if open {
                if color { try str.push(&b, "\x1b[0m") }
                open = false
            }
            if body[0] == 47u8 {
                if depth == 0usize { ret ("", BadMarkup) }
                let want = body[1usize..]
                if want.len == 0usize {
                    depth -= 1usize
                } else {
                    var found_at = depth
                    var d = depth
                    while d > 0usize {
                        d -= 1usize
                        if str.eq(stack[d].name, want) {
                            found_at = d
                            break
                        }
                    }
                    if found_at == depth { ret ("", BadMarkup) }
                    var m = found_at
                    while m + 1usize < depth {
                        stack[m] = stack[m + 1usize]
                        m += 1usize
                    }
                    depth -= 1usize
                }
            } else {
                if depth >= MARKUP_DEPTH { ret ("", BadMarkup) }
                var entry: Entry = zero
                try parse_tag(body, &entry)
                entry.name = body
                stack[depth] = entry
                depth += 1usize
            }
            i = tag_end + 1usize
            continue
        }
        if color && !open && depth > 0usize {
            var attrs = 0u16
            var fg = 0u8
            var bg = 0u8
            var d = 0usize
            while d < depth {
                attrs = attrs | stack[d].attrs
                if stack[d].fg != 0u8 { fg = stack[d].fg }
                if stack[d].bg != 0u8 { bg = stack[d].bg }
                d += 1usize
            }
            if attrs != 0u16 || fg != 0u8 || bg != 0u8 {
                try push_sgr(&b, attrs, fg, bg)
                open = true
            }
        }
        try str.push_byte(&b, c)
        i += 1usize
    }
    if open && color { try str.push(&b, "\x1b[0m") }
    if depth > 0usize { ret ("", BadMarkup) }
    ret (str.done(&b), ok)
}

// BEGIN generated tables (scripts/gen_termkit_test.py)
fn box_ascii(row: usize, part: usize) -> str {
    let k = row * 4usize + part
    if k == 0usize { ret "+" }
    if k == 1usize { ret "-" }
    if k == 2usize { ret "-" }
    if k == 3usize { ret "+" }
    if k == 4usize { ret "|" }
    if k == 5usize { ret " " }
    if k == 6usize { ret "|" }
    if k == 7usize { ret "|" }
    if k == 8usize { ret "|" }
    if k == 9usize { ret "-" }
    if k == 10usize { ret "+" }
    if k == 11usize { ret "|" }
    if k == 12usize { ret "|" }
    if k == 13usize { ret " " }
    if k == 14usize { ret "|" }
    if k == 15usize { ret "|" }
    if k == 16usize { ret "+" }
    if k == 17usize { ret "-" }
    if k == 18usize { ret "-" }
    if k == 19usize { ret "+" }
    ret ""
}

fn box_square(row: usize, part: usize) -> str {
    let k = row * 4usize + part
    if k == 0usize { ret "\xe2\x94\x8c" }
    if k == 1usize { ret "\xe2\x94\x80" }
    if k == 2usize { ret "\xe2\x94\xac" }
    if k == 3usize { ret "\xe2\x94\x90" }
    if k == 4usize { ret "\xe2\x94\x82" }
    if k == 5usize { ret " " }
    if k == 6usize { ret "\xe2\x94\x82" }
    if k == 7usize { ret "\xe2\x94\x82" }
    if k == 8usize { ret "\xe2\x94\x9c" }
    if k == 9usize { ret "\xe2\x94\x80" }
    if k == 10usize { ret "\xe2\x94\xbc" }
    if k == 11usize { ret "\xe2\x94\xa4" }
    if k == 12usize { ret "\xe2\x94\x82" }
    if k == 13usize { ret " " }
    if k == 14usize { ret "\xe2\x94\x82" }
    if k == 15usize { ret "\xe2\x94\x82" }
    if k == 16usize { ret "\xe2\x94\x94" }
    if k == 17usize { ret "\xe2\x94\x80" }
    if k == 18usize { ret "\xe2\x94\xb4" }
    if k == 19usize { ret "\xe2\x94\x98" }
    ret ""
}

fn box_rounded(row: usize, part: usize) -> str {
    let k = row * 4usize + part
    if k == 0usize { ret "\xe2\x95\xad" }
    if k == 1usize { ret "\xe2\x94\x80" }
    if k == 2usize { ret "\xe2\x94\xac" }
    if k == 3usize { ret "\xe2\x95\xae" }
    if k == 4usize { ret "\xe2\x94\x82" }
    if k == 5usize { ret " " }
    if k == 6usize { ret "\xe2\x94\x82" }
    if k == 7usize { ret "\xe2\x94\x82" }
    if k == 8usize { ret "\xe2\x94\x9c" }
    if k == 9usize { ret "\xe2\x94\x80" }
    if k == 10usize { ret "\xe2\x94\xbc" }
    if k == 11usize { ret "\xe2\x94\xa4" }
    if k == 12usize { ret "\xe2\x94\x82" }
    if k == 13usize { ret " " }
    if k == 14usize { ret "\xe2\x94\x82" }
    if k == 15usize { ret "\xe2\x94\x82" }
    if k == 16usize { ret "\xe2\x95\xb0" }
    if k == 17usize { ret "\xe2\x94\x80" }
    if k == 18usize { ret "\xe2\x94\xb4" }
    if k == 19usize { ret "\xe2\x95\xaf" }
    ret ""
}

fn box_heavyhead(row: usize, part: usize) -> str {
    let k = row * 4usize + part
    if k == 0usize { ret "\xe2\x94\x8f" }
    if k == 1usize { ret "\xe2\x94\x81" }
    if k == 2usize { ret "\xe2\x94\xb3" }
    if k == 3usize { ret "\xe2\x94\x93" }
    if k == 4usize { ret "\xe2\x94\x83" }
    if k == 5usize { ret " " }
    if k == 6usize { ret "\xe2\x94\x83" }
    if k == 7usize { ret "\xe2\x94\x83" }
    if k == 8usize { ret "\xe2\x94\xa1" }
    if k == 9usize { ret "\xe2\x94\x81" }
    if k == 10usize { ret "\xe2\x95\x87" }
    if k == 11usize { ret "\xe2\x94\xa9" }
    if k == 12usize { ret "\xe2\x94\x82" }
    if k == 13usize { ret " " }
    if k == 14usize { ret "\xe2\x94\x82" }
    if k == 15usize { ret "\xe2\x94\x82" }
    if k == 16usize { ret "\xe2\x94\x94" }
    if k == 17usize { ret "\xe2\x94\x80" }
    if k == 18usize { ret "\xe2\x94\xb4" }
    if k == 19usize { ret "\xe2\x94\x98" }
    ret ""
}

fn box_part(style: BoxStyle, row: usize, part: usize) -> str {
    if style == .Ascii { ret box_ascii(row, part) }
    if style == .Square { ret box_square(row, part) }
    if style == .Rounded { ret box_rounded(row, part) }
    ret box_heavyhead(row, part)
}

// The bar's cells: index 0 is blank, `steps` is the full cell (tqdm's two charsets).
fn bar_char(ascii: bool, k: u64) -> str {
    if ascii && k == 0u64 { ret " " }
    if ascii && k == 1u64 { ret "1" }
    if ascii && k == 2u64 { ret "2" }
    if ascii && k == 3u64 { ret "3" }
    if ascii && k == 4u64 { ret "4" }
    if ascii && k == 5u64 { ret "5" }
    if ascii && k == 6u64 { ret "6" }
    if ascii && k == 7u64 { ret "7" }
    if ascii && k == 8u64 { ret "8" }
    if ascii && k == 9u64 { ret "9" }
    if ascii && k == 10u64 { ret "#" }
    if !ascii && k == 0u64 { ret " " }
    if !ascii && k == 1u64 { ret "\xe2\x96\x8f" }
    if !ascii && k == 2u64 { ret "\xe2\x96\x8e" }
    if !ascii && k == 3u64 { ret "\xe2\x96\x8d" }
    if !ascii && k == 4u64 { ret "\xe2\x96\x8c" }
    if !ascii && k == 5u64 { ret "\xe2\x96\x8b" }
    if !ascii && k == 6u64 { ret "\xe2\x96\x8a" }
    if !ascii && k == 7u64 { ret "\xe2\x96\x89" }
    if !ascii && k == 8u64 { ret "\xe2\x96\x88" }
    ret " "
}
// END generated tables
