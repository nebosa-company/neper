// Fixed-width record mapping in the manner of FileHelpers' `FixedLengthRecord`: a layout is a
// list of fields, each a byte width with an alignment, a pad byte and a trim rule; a record is
// the fields back to back with no separator. `read` cuts a line into field values (slices of
// the line, trimmed), `write` pads and aligns values into a line.
//
// Reading. A line must be exactly the layout's width under `Exact`; `AllowMore` accepts and
// ignores trailing extra bytes; `AllowLess` accepts a short line (missing trailing fields
// read as empty); `AllowVariable` accepts both. A field that is not `optional` and is entirely
// missing under `AllowLess` is `Short`. Trimming removes the field's pad byte (and, for `Both`,
// either side) from the cut value: `None` keeps the padding, `Left`/`Right` trim that side only.
//
// Writing. A value shorter than the width is padded on its alignment's opposite side with the
// pad byte; a longer one is `Overflow` (never silently truncated). The width is in bytes, so
// multi-byte characters count as their UTF-8 length, as FileHelpers' byte-oriented files do.

type Align = enum u8 { Left, Right }
type Trim = enum u8 { None, Both, Left, Right }
type Mode = enum u8 { Exact, AllowMore, AllowLess, AllowVariable }
type Field = struct { name: str, width: u32, align: Align, pad: u8, trim: Trim, optional: bool }
error Short
error Long
error Overflow
error TooSmall
error Mismatch

fn record_width(fields: []const Field) -> usize {
    var total = 0usize
    var i = 0usize
    while i < fields.len {
        total += usize(fields[i].width)
        i += 1usize
    }
    ret total
}

fn trimmed(f: Field, cut: str) -> str {
    var a = 0usize
    var b = cut.len
    if f.trim == .Both || f.trim == .Left {
        while a < b && cut[a] == f.pad { a += 1usize }
    }
    if f.trim == .Both || f.trim == .Right {
        while b > a && cut[b - 1usize] == f.pad { b -= 1usize }
    }
    ret cut[a..b]
}

// Cuts `line` into `out` (one value per field). `out` must hold `fields.len` values.
fn read(fields: []const Field, mode: Mode, line: str, out: []str) -> err {
    if out.len < fields.len { ret TooSmall }
    let width = record_width(fields)
    if line.len > width && (mode == .Exact || mode == .AllowLess) { ret Long }
    if line.len < width && (mode == .Exact || mode == .AllowMore) { ret Short }
    var at = 0usize
    var i = 0usize
    while i < fields.len {
        let w = usize(fields[i].width)
        if at >= line.len {
            if !fields[i].optional && w > 0usize { ret Short }
            out[i] = ""
        } else {
            var end = at + w
            if end > line.len { end = line.len }
            out[i] = trimmed(fields[i], line[at..end])
        }
        at += w
        i += 1usize
    }
    ret ok
}

// Pads and aligns `values` into `dst`; returns the record.
fn write(fields: []const Field, values: []const str, dst: []u8) -> (str, err) {
    if values.len != fields.len { ret ("", Mismatch) }
    let width = record_width(fields)
    if dst.len < width { ret ("", TooSmall) }
    var at = 0usize
    var i = 0usize
    while i < fields.len {
        let w = usize(fields[i].width)
        let v = values[i]
        if v.len > w { ret ("", Overflow) }
        let gap = w - v.len
        var k = 0usize
        if fields[i].align == .Left {
            while k < v.len {
                dst[at + k] = v[k]
                k += 1usize
            }
            while k < w {
                dst[at + k] = fields[i].pad
                k += 1usize
            }
        } else {
            while k < gap {
                dst[at + k] = fields[i].pad
                k += 1usize
            }
            var j = 0usize
            while j < v.len {
                dst[at + gap + j] = v[j]
                j += 1usize
            }
        }
        at += w
        i += 1usize
    }
    ret (dst[..width], ok)
}
