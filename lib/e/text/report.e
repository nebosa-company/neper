// Diagnostic reports for applications, in the manner of miette and rustc: a severity, a
// code and a message, then the source lines the labels point into with underlines and
// messages beneath them, then notes. Output is plain text of fixed columns (a terminal
// grid, not a shaped layout): tabs expand to `tab_width` spaces, a code point is one
// column except East Asian wide and emoji (two) and combining marks (zero), and notes
// wrap with `e.text.wrap`.
//
//   error[E0001]: unexpected token
//    --> main.e:3:13
//     |
//   2 | fn main() {
//   3 |     let x = ;
//     |             ^ expected an expression
//     |
//     = help: write a value after `=`
//
// A label is a byte range of the source with a message. The primary label marks `^`,
// others `-`; the location row is the first primary label (else the first label). Labels
// on one line share an underline row: the rightmost message sits after its marks and the
// rest hang below on `|` connectors, right to left. A label over several lines marks the
// rest of its first line and the start of its last, with the message there. Lines beside
// a label (`context` of them) are shown and gaps between shown groups become `...`.
// Offsets must be on UTF-8 boundaries inside the source. With `color`, the header and
// marks are wrapped in ANSI SGR (error red, warning yellow, advice cyan, secondary marks
// blue, gutter blue).

use e.mem
use e.str
use e.text.wrap as wrap

type Severity = enum u8 { Error, Warning, Advice }
type Label = struct { start: usize, end: usize, message: str, primary: bool }
type Note = struct { kind: str, text: str }
type Report = struct { severity: Severity, code: str, message: str, source_name: str, source: str, labels: []const Label, notes: []const Note }
type Options = struct { context: usize, tab_width: usize, wrap: usize, color: bool }
type Segment = struct { line: usize, from: usize, to: usize, primary: bool, message: str }
error Invalid
error TooSmall

fn options_default() -> Options {
    ret Options { context: 1usize, tab_width: 4usize, wrap: 80usize, color: false }
}

fn is_continuation(b: u8) -> bool { ret b >= 128u8 && b < 192u8 }

// The scalar at `at` and its byte length (a stray byte is its own length-1 scalar).
fn decode_at(s: str, at: usize) -> (u32, usize) {
    let b = s[at]
    if b < 128u8 { ret (u32(b), 1usize) }
    var need = 0usize
    var cp = 0u32
    if b >= 240u8 {
        need = 3usize
        cp = u32(b & 7u8)
    } else if b >= 224u8 {
        need = 2usize
        cp = u32(b & 15u8)
    } else if b >= 192u8 {
        need = 1usize
        cp = u32(b & 31u8)
    } else {
        ret (u32(b), 1usize)
    }
    if at + need >= s.len { ret (u32(b), 1usize) }
    var i = 1usize
    while i <= need {
        cp = (cp << 6u32) | u32(s[at + i] & 63u8)
        i += 1usize
    }
    ret (cp, need + 1usize)
}

// Terminal columns of a scalar: 0 for combining marks and joiners, 2 for East Asian wide
// and emoji, else 1.
fn char_width(cp: u32) -> usize {
    if cp < 768u32 { ret 1usize }
    if cp >= 768u32 && cp <= 879u32 { ret 0usize }
    if cp == 8203u32 || cp == 8204u32 || cp == 8205u32 || cp == 65279u32 { ret 0usize }
    if cp >= 65024u32 && cp <= 65039u32 { ret 0usize }
    if cp >= 4352u32 && cp <= 4447u32 { ret 2usize }
    if cp >= 11904u32 && cp <= 42191u32 && cp != 12351u32 { ret 2usize }
    if cp >= 44032u32 && cp <= 55203u32 { ret 2usize }
    if cp >= 63744u32 && cp <= 64255u32 { ret 2usize }
    if cp >= 65072u32 && cp <= 65135u32 { ret 2usize }
    if cp >= 65281u32 && cp <= 65376u32 { ret 2usize }
    if cp >= 65504u32 && cp <= 65510u32 { ret 2usize }
    if cp >= 126976u32 && cp <= 129791u32 { ret 2usize }
    if cp >= 131072u32 && cp <= 262141u32 { ret 2usize }
    ret 1usize
}

// Number of lines (a final line without a newline counts; an empty source has one).
fn line_count(source: str) -> usize {
    var n = 1usize
    var i = 0usize
    while i < source.len {
        if source[i] == 10u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// Byte range [start, end) of line `n` (0-based), without its newline and CR.
fn line_bounds(source: str, n: usize) -> (usize, usize) {
    var start = 0usize
    var seen = 0usize
    var i = 0usize
    while i < source.len && seen < n {
        if source[i] == 10u8 {
            seen += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    var end = start
    while end < source.len && source[end] != 10u8 { end += 1usize }
    if end > start && source[end - 1usize] == 13u8 { end -= 1usize }
    ret (start, end)
}

// The 0-based line holding byte `offset` (an offset at the very end is on the last line).
fn line_of(source: str, offset: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < offset && i < source.len {
        if source[i] == 10u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// Display columns of `source[from..to]` with tabs as `tab_width`.
fn span_width(source: str, from: usize, to: usize, tab_width: usize) -> usize {
    var cols = 0usize
    var i = from
    while i < to {
        if source[i] == 9u8 {
            cols += tab_width
            i += 1usize
        } else {
            let (cp, used) = decode_at(source, i)
            cols += char_width(cp)
            i += used
        }
    }
    ret cols
}

fn valid_offset(source: str, offset: usize) -> bool {
    if offset > source.len { ret false }
    if offset == source.len { ret true }
    ret !is_continuation(source[offset])
}

fn validate(r: *const Report) -> err {
    var i = 0usize
    while i < r.labels.len {
        let l = r.labels[i]
        if l.end < l.start || !valid_offset(r.source, l.start) || !valid_offset(r.source, l.end) { ret Invalid }
        i += 1usize
    }
    ret ok
}

fn digits_of(n: usize) -> usize {
    var d = 1usize
    var v = n
    while v >= 10usize {
        v = v / 10usize
        d += 1usize
    }
    ret d
}

// The first non-blank column of `source[start..end]`.
fn indent_cols(source: str, start: usize, end: usize, tab_width: usize) -> usize {
    var i = start
    while i < end && (source[i] == 32u8 || source[i] == 9u8) { i += 1usize }
    ret span_width(source, start, i, tab_width)
}

// The segments a label contributes: one for a single-line label, two for a multi-line one.
fn label_segments(source: str, l: Label, tab_width: usize, out: []Segment, at: usize) -> usize {
    let first = line_of(source, l.start)
    var last_byte = l.start
    if l.end > l.start { last_byte = l.end - 1usize }
    let last = line_of(source, last_byte)
    let (first_start, first_end) = line_bounds(source, first)
    var from = span_width(source, first_start, l.start, tab_width)
    if l.start > first_end { from = span_width(source, first_start, first_end, tab_width) }
    if first == last {
        var stop = l.end
        if stop > first_end { stop = first_end }
        var to = from + 1usize
        if stop > l.start { to = span_width(source, first_start, stop, tab_width) }
        if to <= from { to = from + 1usize }
        out[at] = Segment { line: first, from: from, to: to, primary: l.primary, message: l.message }
        ret 1usize
    }
    var line_end_col = span_width(source, first_start, first_end, tab_width)
    if line_end_col <= from { line_end_col = from + 1usize }
    out[at] = Segment { line: first, from: from, to: line_end_col, primary: l.primary, message: "" }
    let (last_start, last_end) = line_bounds(source, last)
    let indent = indent_cols(source, last_start, last_end, tab_width)
    var stop = l.end
    if stop > last_end { stop = last_end }
    var to = span_width(source, last_start, stop, tab_width)
    if to <= indent { to = indent + 1usize }
    out[at + 1usize] = Segment { line: last, from: indent, to: to, primary: l.primary, message: l.message }
    ret 2usize
}

fn push_spaces(b: *str.Builder, n: usize) -> err {
    var i = 0usize
    while i < n {
        try str.push_byte(b, 32u8)
        i += 1usize
    }
    ret ok
}

fn push_expanded(b: *str.Builder, line: str, tab_width: usize) -> err {
    var i = 0usize
    while i < line.len {
        if line[i] == 9u8 {
            try push_spaces(b, tab_width)
        } else {
            try str.push_byte(b, line[i])
        }
        i += 1usize
    }
    ret ok
}

fn paint(b: *str.Builder, on: bool, code: str) -> err {
    if !on { ret ok }
    try str.push(b, "\x1b[")
    try str.push(b, code)
    ret str.push(b, "m")
}

fn severity_name(s: Severity) -> str {
    if s == .Error { ret "error" }
    if s == .Warning { ret "warning" }
    ret "advice"
}

fn severity_code(s: Severity) -> str {
    if s == .Error { ret "1;31" }
    if s == .Warning { ret "1;33" }
    ret "1;36"
}

// `<gutter spaces> |` and, when `body` is not empty, ` ` and the body with trailing blanks trimmed.
fn push_gutter_row(b: *str.Builder, w: usize, body: str, color: bool) -> err {
    try push_spaces(b, w)
    try str.push(b, " ")
    try paint(b, color, "34")
    try str.push(b, "|")
    try paint(b, color, "0")
    let trimmed = str.trim_end(body)
    if trimmed.len > 0usize {
        try str.push(b, " ")
        try str.push(b, trimmed)
    }
    ret str.push(b, "\n")
}

// One annotation row built in `row` (spaces below `used`) and written without colour
// codes; colour is applied by the caller per mark, so a row with colour is rendered by
// `push_marks`.
fn push_marks(b: *str.Builder, row: []const u8, kinds: []const u8, used: usize, color: bool) -> err {
    var end = used
    while end > 0usize && row[end - 1usize] == 32u8 { end -= 1usize }
    var i = 0usize
    var current = 0u8
    while i < end {
        let k = kinds[i]
        if color && k != current {
            if current != 0u8 { try paint(b, true, "0") }
            if k == 1u8 { try paint(b, true, "1;31") }
            if k == 2u8 { try paint(b, true, "1;34") }
            current = k
        }
        try str.push_byte(b, row[i])
        i += 1usize
    }
    if current != 0u8 { try paint(b, true, "0") }
    ret ok
}

fn put_text(row: []u8, kinds: []u8, at: usize, s: str, kind: u8) -> usize {
    var i = 0usize
    while i < s.len && at + i < row.len {
        row[at + i] = s[i]
        kinds[at + i] = kind
        i += 1usize
    }
    ret at + i
}

fn digits_row(b: *str.Builder, w: usize, number: usize, color: bool) -> err {
    let d = digits_of(number)
    try push_spaces(b, w - d)
    try paint(b, color, "34")
    try str.push_usize(b, number)
    try str.push(b, " |")
    try paint(b, color, "0")
    ret str.push(b, " ")
}

// Everything `emit` needs, allocated before the output builder opens (a builder must be
// the arena's top allocation).
type Work = struct { segments: []Segment, count: usize, order: []usize, shown: []bool, row: []u8, kinds: []u8, bounds: []usize, scratch: []usize, w: usize, total: usize }

fn blank(row: []u8, kinds: []u8, n: usize) {
    var i = 0usize
    while i < n && i < row.len {
        row[i] = 32u8
        kinds[i] = 0u8
        i += 1usize
    }
}

fn kind_of(primary: bool) -> u8 {
    if primary { ret 1u8 }
    ret 2u8
}

// One annotation row: gutter, then the marks and text in `row[0..used]`.
fn push_row(b: *str.Builder, wk: *const Work, used: usize, color: bool) -> err {
    try push_spaces(b, wk.w)
    try str.push(b, " ")
    try paint(b, color, "34")
    try str.push(b, "|")
    try paint(b, color, "0")
    var end = used
    while end > 0usize && wk.row[end - 1usize] == 32u8 { end -= 1usize }
    if end > 0usize {
        try str.push(b, " ")
        try push_marks(b, wk.row, wk.kinds, end, color)
    }
    ret str.push(b, "\n")
}

// The underline row and message rows for the segments on `line`.
fn annotate(b: *str.Builder, wk: *Work, line: usize, color: bool) -> err {
    // Segments on this line ordered by start column, then by label order.
    var n = 0usize
    var s = 0usize
    while s < wk.count {
        if wk.segments[s].line == line {
            var p = n
            while p > 0usize && wk.segments[wk.order[p - 1usize]].from > wk.segments[s].from {
                wk.order[p] = wk.order[p - 1usize]
                p -= 1usize
            }
            wk.order[p] = s
            n += 1usize
        }
        s += 1usize
    }
    if n == 0usize { ret ok }
    var width = 0usize
    var i = 0usize
    while i < n {
        if wk.segments[wk.order[i]].to > width { width = wk.segments[wk.order[i]].to }
        i += 1usize
    }
    blank(wk.row, wk.kinds, wk.row.len)
    // Secondary marks first so a primary mark wins an overlap.
    var pass = 0usize
    while pass < 2usize {
        i = 0usize
        while i < n {
            let sg = wk.segments[wk.order[i]]
            if (pass == 0usize && !sg.primary) || (pass == 1usize && sg.primary) {
                var c = sg.from
                while c < sg.to {
                    if sg.primary { wk.row[c] = 94u8 } else { wk.row[c] = 45u8 }
                    wk.kinds[c] = kind_of(sg.primary)
                    c += 1usize
                }
            }
            i += 1usize
        }
        pass += 1usize
    }
    // The rightmost message-bearing segment is written after the marks.
    var inline_at = n
    i = n
    while i > 0usize {
        i -= 1usize
        if wk.segments[wk.order[i]].message.len > 0usize {
            inline_at = i
            break
        }
    }
    var used = width
    if inline_at < n {
        let sg = wk.segments[wk.order[inline_at]]
        used = put_text(wk.row, wk.kinds, width + 1usize, sg.message, kind_of(sg.primary))
    }
    try push_row(b, wk, used, color)
    // The others, right to left: a connector row, then the message row.
    var j = inline_at
    while j > 0usize {
        j -= 1usize
        if wk.segments[wk.order[j]].message.len == 0usize { continue }
        blank(wk.row, wk.kinds, wk.row.len)
        var q = 0usize
        while q <= j {
            let sq = wk.segments[wk.order[q]]
            if sq.message.len > 0usize {
                wk.row[sq.from] = 124u8
                wk.kinds[sq.from] = kind_of(sq.primary)
            }
            q += 1usize
        }
        try push_row(b, wk, wk.segments[wk.order[j]].from + 1usize, color)
        blank(wk.row, wk.kinds, wk.row.len)
        q = 0usize
        while q < j {
            let sq = wk.segments[wk.order[q]]
            if sq.message.len > 0usize {
                wk.row[sq.from] = 124u8
                wk.kinds[sq.from] = kind_of(sq.primary)
            }
            q += 1usize
        }
        let sj = wk.segments[wk.order[j]]
        let end = put_text(wk.row, wk.kinds, sj.from, sj.message, kind_of(sj.primary))
        try push_row(b, wk, end, color)
    }
    ret ok
}

fn notes_out(b: *str.Builder, r: *const Report, wk: *Work, wrap_width: usize, color: bool) -> err {
    var n = 0usize
    while n < r.notes.len {
        let note = r.notes[n]
        let prefix_len = wk.w + 3usize + note.kind.len + 2usize
        var room = 20usize
        if wrap_width > prefix_len + 20usize { room = wrap_width - prefix_len }
        let (lines, le) = wrap.greedy(note.text, room, wk.bounds, wk.scratch)
        if le != ok { ret le }
        try push_spaces(b, wk.w + 1usize)
        try paint(b, color, "1;36")
        try str.push(b, "=")
        try paint(b, color, "0")
        try str.push(b, " ")
        try str.push(b, note.kind)
        try str.push(b, ": ")
        if lines == 0usize { try str.push(b, "\n") }
        var i = 0usize
        while i < lines {
            if i > 0usize { try push_spaces(b, prefix_len) }
            try str.push(b, note.text[wk.bounds[2usize * i]..wk.bounds[2usize * i + 1usize]])
            try str.push(b, "\n")
            i += 1usize
        }
        n += 1usize
    }
    ret ok
}

fn emit(b: *str.Builder, r: *const Report, o: Options, wk: *Work) -> err {
    try paint(b, o.color, severity_code(r.severity))
    try str.push(b, severity_name(r.severity))
    if r.code.len > 0usize {
        try str.push(b, "[")
        try str.push(b, r.code)
        try str.push(b, "]")
    }
    try str.push(b, ": ")
    try str.push(b, r.message)
    try paint(b, o.color, "0")
    try str.push(b, "\n")
    if r.labels.len > 0usize {
        var anchor = r.labels[0]
        var j = 0usize
        while j < r.labels.len {
            if r.labels[j].primary {
                anchor = r.labels[j]
                break
            }
            j += 1usize
        }
        let aline = line_of(r.source, anchor.start)
        let (astart, aend) = line_bounds(r.source, aline)
        var scan_to = anchor.start
        if scan_to > aend { scan_to = aend }
        let acol = span_width(r.source, astart, scan_to, 1usize)
        try push_spaces(b, wk.w)
        try paint(b, o.color, "34")
        try str.push(b, "--> ")
        try paint(b, o.color, "0")
        try str.push(b, r.source_name)
        try str.push(b, ":")
        try str.push_usize(b, aline + 1usize)
        try str.push(b, ":")
        try str.push_usize(b, acol + 1usize)
        try str.push(b, "\n")
        try push_blank_gutter(b, wk.w, o.color)
    }
    var line = 0usize
    var gap = false
    var printed = false
    while line < wk.total && r.labels.len > 0usize {
        if !wk.shown[line] {
            gap = true
            line += 1usize
            continue
        }
        if gap && printed { try str.push(b, "...\n") }
        gap = false
        printed = true
        let (ls, le) = line_bounds(r.source, line)
        try digits_row(b, wk.w, line + 1usize, o.color)
        try push_expanded(b, r.source[ls..le], o.tab_width)
        try str.push(b, "\n")
        try annotate(b, wk, line, o.color)
        line += 1usize
    }
    if r.labels.len > 0usize { try push_blank_gutter(b, wk.w, o.color) }
    ret notes_out(b, r, wk, o.wrap, o.color)
}

fn push_blank_gutter(b: *str.Builder, w: usize, color: bool) -> err {
    try push_spaces(b, w)
    try str.push(b, " ")
    try paint(b, color, "34")
    try str.push(b, "|")
    try paint(b, color, "0")
    ret str.push(b, "\n")
}

// The whole report as text.
fn render(a: *mem.Arena, r: *const Report, o: Options) -> (str, err) {
    if validate(r) != ok { ret ("", Invalid) }
    let total_lines = line_count(r.source)
    let (segments, ge) = mem.alloc[Segment](a, r.labels.len * 2usize + 1usize)
    if ge != ok { ret ("", ge) }
    var seg_count = 0usize
    var i = 0usize
    while i < r.labels.len {
        seg_count += label_segments(r.source, r.labels[i], o.tab_width, segments, seg_count)
        i += 1usize
    }
    let (shown, he) = mem.alloc[bool](a, total_lines + 1usize)
    if he != ok { ret ("", he) }
    // mem.alloc does not clear.
    i = 0usize
    while i <= total_lines {
        shown[i] = false
        i += 1usize
    }
    i = 0usize
    while i < seg_count {
        var lo = 0usize
        if segments[i].line > o.context { lo = segments[i].line - o.context }
        var hi = segments[i].line + o.context
        if hi >= total_lines { hi = total_lines - 1usize }
        var k = lo
        while k <= hi {
            shown[k] = true
            k += 1usize
        }
        i += 1usize
    }
    var last_shown = 0usize
    var widest = 0usize
    var shown_lines = 0usize
    var li = 0usize
    while li < total_lines {
        if shown[li] {
            last_shown = li
            shown_lines += 1usize
            let (s, e) = line_bounds(r.source, li)
            let cols = span_width(r.source, s, e, o.tab_width)
            if cols > widest { widest = cols }
        }
        li += 1usize
    }
    var longest = 0usize
    i = 0usize
    while i < r.labels.len {
        if r.labels[i].message.len > longest { longest = r.labels[i].message.len }
        i += 1usize
    }
    let w = digits_of(last_shown + 1usize)
    let (row, re) = mem.alloc[u8](a, widest + longest + 8usize)
    if re != ok { ret ("", re) }
    let (kinds, ke) = mem.alloc[u8](a, widest + longest + 8usize)
    if ke != ok { ret ("", ke) }
    let (order, oe) = mem.alloc[usize](a, seg_count + 1usize)
    if oe != ok { ret ("", oe) }
    var longest_note = 0usize
    var note_bytes = 0usize
    i = 0usize
    while i < r.notes.len {
        if r.notes[i].text.len > longest_note { longest_note = r.notes[i].text.len }
        note_bytes += r.notes[i].text.len + r.notes[i].kind.len + 64usize + w
        i += 1usize
    }
    let (bounds, be2) = mem.alloc[usize](a, longest_note + 8usize)
    if be2 != ok { ret ("", be2) }
    let (scratch, se) = mem.alloc[usize](a, longest_note + 8usize)
    if se != ok { ret ("", se) }
    // Output bound: per shown line the line, a mark row and two rows per label message,
    // every row at most gutter + widest + longest + colour codes.
    let per_row = w + widest + longest + 64usize
    let rows = 3usize + shown_lines * 2usize + seg_count * 2usize + r.notes.len * 2usize + 2usize
    let capacity = rows * per_row + note_bytes + r.message.len + r.code.len + r.source_name.len + 512usize
    let (b0, ce) = str.builder(a, capacity)
    if ce != ok { ret ("", ce) }
    var b = b0
    var wk = Work { segments: segments, count: seg_count, order: order, shown: shown, row: row, kinds: kinds, bounds: bounds, scratch: scratch, w: w, total: total_lines }
    let ee = emit(&b, r, o, &wk)
    if ee != ok { ret ("", ee) }
    ret (str.done(&b), ok)
}