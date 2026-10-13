// The text of a PDF document (C123, C142): its pages in order, each page's text as the content stream paints it,
// read from a byte slice. A reader for what a viewer's text layer shows, not a renderer: the objects are found
// by scanning the file for `N G obj` (so a file written in one pass or rewritten by an incremental update both
// read, and one that keeps its objects in object streams or its cross-reference in an xref stream does not --
// `NoPages`); the page order is the catalog's page tree; a page's content streams are joined, decoded when they
// are `/FlateDecode` (through e.fmt.zlib) and read for the text operators `Tj`, `TJ`, `'`, `"`, `T*`, `Td`, `TD`,
// `Tm` and `ET`. Strings are taken byte for byte as Latin-1 (the standard encodings), written as UTF-8; an
// embedded font with its own encoding gives its codes, not its letters.
//
// Memory: every result lives in the arena passed in.
use e.mem
use e.io
use e.os
use e.str
use e.fmt.zlib as zlib
use e.fmt.jpeg as jpeg
use e.gfx.image

error NotPdf
error NoPages

type Object = struct { number: usize, start: usize, end: usize }

const MAX_OBJECTS: usize = 4096usize
const MAX_PAGES: usize = 512usize
const MAX_STREAM: u64 = 8388608u64

fn is_space(c: u8) -> bool {
    ret c == 32u8 || c == 10u8 || c == 13u8 || c == 9u8 || c == 12u8 || c == 0u8
}

fn is_delim(c: u8) -> bool {
    ret c == 40u8 || c == 41u8 || c == 60u8 || c == 62u8 || c == 91u8 || c == 93u8 || c == 123u8 || c == 125u8 || c == 47u8 || c == 37u8
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

fn at_word(data: []const u8, at: usize, word: str) -> bool {
    if at + word.len > data.len { ret false }
    var i = 0usize
    while i < word.len {
        if data[at + i] != word[i] { ret false }
        i += 1usize
    }
    ret true
}

// The first position of `word` in data[from..until] or `until` when there is none.
fn find(data: []const u8, word: str, from: usize, until: usize) -> usize {
    var at = from
    while at + word.len <= until {
        if at_word(data, at, word) { ret at }
        at += 1usize
    }
    ret until
}

// The decimal number at `at` (after spaces): its value, the position after it, and whether there was one.
fn number_at(data: []const u8, from: usize, until: usize) -> (usize, usize, bool) {
    var at = from
    while at < until && is_space(data[at]) { at += 1usize }
    if at >= until || !is_digit(data[at]) { ret (0usize, from, false) }
    var n = 0usize
    while at < until && is_digit(data[at]) {
        n = n * 10usize + usize(data[at] - 48u8)
        at += 1usize
    }
    ret (n, at, true)
}

// Every `N G obj ... endobj` of the file in order: its number and the span between `obj` and `endobj`.
fn objects(a: *mem.Arena, data: []const u8) -> ([]Object, usize, err) {
    let (table, table_error) = mem.alloc[Object](a, MAX_OBJECTS)
    if table_error != ok { ret (table, 0usize, table_error) }
    var count = 0usize
    var at = 0usize
    while at + 3usize <= data.len && count < MAX_OBJECTS {
        if at_word(data, at, "obj") && at > 0usize && (is_space(data[at - 1usize]) || is_digit(data[at - 1usize])) {
            // Walk back over the generation, a space and the number.
            var back = at
            while back > 0usize && is_space(data[back - 1usize]) { back -= 1usize }
            var gen_start = back
            while gen_start > 0usize && is_digit(data[gen_start - 1usize]) { gen_start -= 1usize }
            if gen_start < back && gen_start > 0usize && is_space(data[gen_start - 1usize]) {
                var num_end = gen_start
                while num_end > 0usize && is_space(data[num_end - 1usize]) { num_end -= 1usize }
                var num_start = num_end
                while num_start > 0usize && is_digit(data[num_start - 1usize]) { num_start -= 1usize }
                if num_start < num_end && (num_start == 0usize || is_space(data[num_start - 1usize])) {
                    let (number, after, got) = number_at(data, num_start, num_end)
                    let finish = find(data, "endobj", at + 3usize, data.len)
                    table[count] = Object { number: number, start: at + 3usize, end: finish }
                    count += 1usize
                    at = finish
                }
            }
        }
        at += 1usize
    }
    ret (table, count, ok)
}

fn object_span(table: []const Object, count: usize, number: usize) -> (usize, usize, bool) {
    var i = 0usize
    var found = false
    var s = 0usize
    var e = 0usize
    // The last definition of an object number wins (an incremental update).
    while i < count {
        if table[i].number == number {
            s = table[i].start
            e = table[i].end
            found = true
        }
        i += 1usize
    }
    ret (s, e, found)
}

// Whether the dictionary text in data[from..until] has `/Key` as a name with `/Value` after it (as in
// `/Type /Page`), both ended by a delimiter.
fn has_pair(data: []const u8, from: usize, until: usize, key: str, value: str) -> bool {
    var at = from
    while at < until {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            var k = at + 1usize + key.len
            if k < until && !is_space(data[k]) && !is_delim(data[k]) { at += 1usize } else {
                while k < until && is_space(data[k]) { k += 1usize }
                if k < until && data[k] == 47u8 && at_word(data, k + 1usize, value) {
                    let end = k + 1usize + value.len
                    if end >= until || is_space(data[end]) || is_delim(data[end]) { ret true }
                }
                at += 1usize
            }
        } else {
            at += 1usize
        }
    }
    ret false
}

// The indirect reference `N G R` after `/Key` in data[from..until]: the number, and whether there is one.
fn ref_after(data: []const u8, from: usize, until: usize, key: str) -> (usize, bool) {
    var at = from
    while at < until {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            let k = at + 1usize + key.len
            if k >= until || is_space(data[k]) || is_delim(data[k]) {
                let (number, after_number, got_number) = number_at(data, k, until)
                if got_number {
                    let (gen, after_gen, got_gen) = number_at(data, after_number, until)
                    if got_gen {
                        var r = after_gen
                        while r < until && is_space(data[r]) { r += 1usize }
                        if r < until && data[r] == 82u8 { ret (number, true) }
                    }
                }
                ret (0usize, false)
            }
        }
        at += 1usize
    }
    ret (0usize, false)
}

// The references `N G R` inside the `[` ... `]` after `/Key`, in order, into `out`; the count.
fn refs_in_array(data: []const u8, from: usize, until: usize, key: str, out: []usize) -> usize {
    var at = from
    while at < until {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            var k = at + 1usize + key.len
            while k < until && is_space(data[k]) { k += 1usize }
            if k < until && data[k] == 91u8 {
                k += 1usize
                var n = 0usize
                while k < until && data[k] != 93u8 && n < out.len {
                    let (number, after_number, got_number) = number_at(data, k, until)
                    if !got_number { k += 1usize } else {
                        let (gen, after_gen, got_gen) = number_at(data, after_number, until)
                        var r = after_gen
                        while r < until && is_space(data[r]) { r += 1usize }
                        if got_gen && r < until && data[r] == 82u8 {
                            out[n] = number
                            n += 1usize
                            k = r + 1usize
                        } else {
                            k = after_number
                        }
                    }
                }
                ret n
            }
        }
        at += 1usize
    }
    ret 0usize
}

// Add the page objects under `node` to `pages` in tree order, depth first, with an explicit stack.
fn walk(a: *mem.Arena, data: []const u8, table: []const Object, count: usize, root: usize, found_pages: []usize) -> (usize, err) {
    let (stack, stack_error) = mem.alloc[usize](a, 2048usize)
    if stack_error != ok { ret (0usize, stack_error) }
    var top = 0usize
    var n = 0usize
    stack[0usize] = root
    top = 1usize
    var steps = 0usize
    while top > 0usize && steps < 8192usize {
        steps += 1usize
        top -= 1usize
        let node = stack[top]
        let (s, e, found) = object_span(table, count, node)
        if found {
            if has_pair(data, s, e, "Type", "Pages") {
                var kids: [256]usize = zero
                let kid_count = refs_in_array(data, s, e, "Kids", kids[0usize..])
                // Pushed in reverse so the first kid is popped first.
                var k = kid_count
                while k > 0usize && top < 2048usize {
                    k -= 1usize
                    stack[top] = kids[k]
                    top += 1usize
                }
            } else if n < found_pages.len {
                found_pages[n] = node
                n += 1usize
            }
        }
    }
    ret (n, ok)
}

// ASCII85 (Adobe): optional `<~`, groups of five characters `!`..`u` into four bytes, `z` for four zero bytes,
// white space ignored, `~>` ends; a final partial group of n characters gives n - 1 bytes.
fn ascii85(a: *mem.Arena, raw: []const u8) -> ([]const u8, err) {
    let (out, out_error) = mem.alloc[u8](a, raw.len + 8usize)
    if out_error != ok { ret (raw[0usize..0usize], out_error) }
    var at = 0usize
    var n = 0usize
    var i = 0usize
    if raw.len >= 2usize && raw[0usize] == 60u8 && raw[1usize] == 126u8 { i = 2usize }
    var group: [5]u32 = zero
    var count = 0usize
    var done = false
    while i < raw.len && !done {
        let c = raw[i]
        i += 1usize
        if c == 126u8 {
            done = true
        } else if c == 122u8 && count == 0usize {
            out[n] = 0u8
            out[n + 1usize] = 0u8
            out[n + 2usize] = 0u8
            out[n + 3usize] = 0u8
            n += 4usize
        } else if c >= 33u8 && c <= 117u8 {
            group[count] = u32(c) - 33u32
            count += 1usize
            if count == 5usize {
                let v = group[0usize] * 52200625u32 + group[1usize] * 614125u32 + group[2usize] * 7225u32 + group[3usize] * 85u32 + group[4usize]
                out[n] = u8(v >> 24u32)
                out[n + 1usize] = u8((v >> 16u32) & 255u32)
                out[n + 2usize] = u8((v >> 8u32) & 255u32)
                out[n + 3usize] = u8(v & 255u32)
                n += 4usize
                count = 0usize
            }
        }
    }
    if count > 1usize {
        var k = count
        while k < 5usize {
            group[k] = 84u32
            k += 1usize
        }
        let v = group[0usize] * 52200625u32 + group[1usize] * 614125u32 + group[2usize] * 7225u32 + group[3usize] * 85u32 + group[4usize]
        let bytes: [4]u8 = [4]u8{ u8(v >> 24u32), u8((v >> 16u32) & 255u32), u8((v >> 8u32) & 255u32), u8(v & 255u32) }
        var j = 0usize
        while j + 1usize < count {
            out[n + j] = bytes[j]
            j += 1usize
        }
        n += count - 1usize
    }
    ret (out[0usize..n], ok)
}

// Decode the stream of object span [s, e): its bytes, `/ASCII85Decode` and `/FlateDecode` undone. (The raw span when it has no
// filter, an empty result when the stream is missing or does not inflate.)
fn stream_of(a: *mem.Arena, data: []const u8, s: usize, e: usize) -> ([]const u8, err) {
    let (decoded, decode_error) = stream_capped(a, data, s, e, 262144usize)
    ret (decoded, decode_error)
}

// `stream_of` with the inflated size limit a parameter (an image's samples are larger than a page's text).
fn stream_capped(a: *mem.Arena, data: []const u8, s: usize, e: usize, cap: usize) -> ([]const u8, err) {
    let keyword = find(data, "stream", s, e)
    if keyword >= e { ret (data[s..s], ok) }
    var from = keyword + 6usize
    if from < e && data[from] == 13u8 { from += 1usize }
    if from < e && data[from] == 10u8 { from += 1usize }
    var until = find(data, "endstream", from, e)
    // Trim the end-of-line before `endstream`.
    if until > from && data[until - 1usize] == 10u8 { until -= 1usize }
    if until > from && data[until - 1usize] == 13u8 { until -= 1usize }
    var raw = data[from..until]
    // `/ASCII85Decode` first when the filter list has it (reportlab writes ASCII85 then Flate).
    let a85 = find(data, "ASCII85Decode", s, keyword)
    if a85 < keyword {
        let (decoded, decode_error) = ascii85(a, raw)
        if decode_error != ok { ret (raw[0usize..0usize], ok) }
        raw = decoded
    }
    let flate = find(data, "FlateDecode", s, keyword)
    if flate >= keyword { ret (raw, ok) }
    let (storage, storage_error) = mem.alloc[u8](a, zlib.storage_required(.Fast))
    if storage_error != ok { ret (raw, storage_error) }
    var cell = Mem { data: raw, off: 0usize }
    let reader = io.Reader { ctx: mem.cast[*void](&cell), read: mem_read }
    let (z, z_error) = zlib.reader(storage, reader, MAX_STREAM)
    if z_error != ok { ret (raw[0usize..0usize], ok) }
    var zr = z
    let (out, out_error) = mem.alloc[u8](a, cap)
    if out_error != ok { ret (raw[0usize..0usize], out_error) }
    var filled = 0usize
    var running = true
    while running && filled < out.len {
        let (n, read_error) = zlib.read(&zr, out[filled..])
        if read_error != ok { running = false } else { filled += n }
        if read_error == ok && n == 0usize { running = false }
    }
    ret (out[0usize..filled], ok)
}

type Mem = struct { data: []const u8, off: usize }

fn mem_read(ctx: *void, dst: []u8) -> (usize, err) {
    var s = mem.cast[*Mem](ctx)
    if s.off >= s.data.len { ret (0usize, io.End) }
    var take = dst.len
    if s.data.len - s.off < take { take = s.data.len - s.off }
    mem.copy[u8](dst[..take], s.data[s.off..s.off + take])
    s.off += take
    ret (take, ok)
}

// Append byte `c` (Latin-1) as UTF-8 to out at `at`; the new position.
fn put_latin1(out: []u8, at: usize, c: u8) -> usize {
    if at + 2usize > out.len { ret at }
    if c < 128u8 {
        out[at] = c
        ret at + 1usize
    }
    out[at] = 192u8 | (c >> 6u32)
    out[at + 1usize] = 128u8 | (c & 63u8)
    ret at + 2usize
}

// Append the raw byte `c` to out at `at`; the new position.
fn put_raw(out: []u8, at: usize, c: u8) -> usize {
    if at >= out.len { ret at }
    out[at] = c
    ret at + 1usize
}

fn newline(out: []u8, at: usize) -> usize {
    if at == 0usize || at + 1usize > out.len { ret at }
    if out[at - 1usize] == 10u8 { ret at }
    out[at] = 10u8
    ret at + 1usize
}

// The text a content stream paints, as lines, with strings read as Latin-1 (no resources to find fonts in).
fn text_of(a: *mem.Arena, content: []const u8) -> (str, err) {
    var none: [1]Shape = zero
    var ctx = paint_start(none[0usize..0usize])
    let (text, text_error) = text_run(a, content, &ctx)
    ret (text, text_error)
}

// One code of a string through the painter's current font: the Unicode its /ToUnicode map gives (else Latin-1) as
// UTF-8; a two-byte font's first byte waits in `half` for the second.
fn put_code(out: []u8, at: usize, p: *Painter, c: u8, half: *usize) -> usize {
    if p.cur_font >= p.font_n { ret put_latin1(out, at, c) }
    let f = &p.fonts[p.cur_font]
    if f.two_byte {
        if *half == MAX_CMAP {
            *half = usize(c)
            ret at
        }
        let code = *half * 256usize + usize(c)
        *half = MAX_CMAP
        ret put_utf8(out, at, font_unicode(f, code))
    }
    ret put_utf8(out, at, font_unicode(f, usize(c)))
}

// `text_of` with the fonts of the painter's resources: `Tf` selects the font the strings after it are read through.
fn text_run(a: *mem.Arena, content: []const u8, p: *Painter) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, content.len * 4usize + 16usize)
    if out_error != ok { ret ("", out_error) }
    var half = MAX_CMAP
    var name_s = 0usize
    var name_e = 0usize
    var at = 0usize
    var i = 0usize
    var last_number = 0usize
    var last_was_zero = true
    var prev_zero = true
    var in_array = false
    while i < content.len {
        let c = content[i]
        if c == 40u8 {
            // A literal string, with its escapes and nested parentheses.
            half = MAX_CMAP
            var depth = 1usize
            i += 1usize
            while i < content.len && depth > 0usize {
                let d = content[i]
                if d == 92u8 && i + 1usize < content.len {
                    let e = content[i + 1usize]
                    i += 2usize
                    if e == 110u8 { at = newline(out, at) } else if e == 114u8 || e == 98u8 || e == 102u8 { at += 0usize } else if e == 116u8 { at = put_latin1(out, at, 9u8) } else if e >= 48u8 && e <= 55u8 {
                        var code = usize(e - 48u8)
                        var digits = 1usize
                        while digits < 3usize && i < content.len && content[i] >= 48u8 && content[i] <= 55u8 {
                            code = code * 8usize + usize(content[i] - 48u8)
                            i += 1usize
                            digits += 1usize
                        }
                        at = put_code(out, at, p, u8(code & 255usize), &half)
                    } else if e == 10u8 || e == 13u8 {
                        at += 0usize
                    } else {
                        at = put_code(out, at, p, e, &half)
                    }
                } else {
                    if d == 40u8 { depth += 1usize }
                    if d == 41u8 { depth -= 1usize }
                    if depth > 0usize {
                        at = put_code(out, at, p, d, &half)
                    }
                    i += 1usize
                }
            }
        } else if c == 60u8 && i + 1usize < content.len && content[i + 1usize] != 60u8 {
            // A hex string.
            half = MAX_CMAP
            i += 1usize
            var high = 0usize
            var have_high = false
            while i < content.len && content[i] != 62u8 {
                let h = content[i]
                var v = 99usize
                if h >= 48u8 && h <= 57u8 { v = usize(h - 48u8) }
                if h >= 65u8 && h <= 70u8 { v = usize(h - 55u8) }
                if h >= 97u8 && h <= 102u8 { v = usize(h - 87u8) }
                if v != 99usize {
                    if have_high {
                        at = put_code(out, at, p, u8(high * 16usize + v), &half)
                        have_high = false
                    } else {
                        high = v
                        have_high = true
                    }
                }
                i += 1usize
            }
            if have_high { at = put_code(out, at, p, u8(high * 16usize), &half) }
            i += 1usize
        } else if c == 91u8 {
            in_array = true
            i += 1usize
        } else if c == 93u8 {
            in_array = false
            i += 1usize
        } else if c == 47u8 {
            // A name: the last one is the operand of Tf.
            i += 1usize
            name_s = i
            while i < content.len && !is_space(content[i]) && !is_delim(content[i]) { i += 1usize }
            name_e = i
        } else if is_digit(c) || c == 45u8 || c == 43u8 || c == 46u8 {
            // A number: a big negative kern inside TJ is a word space; keep the last operand for Td/TD.
            var neg = false
            if c == 45u8 { neg = true }
            var value = 0usize
            var j = i
            if c == 45u8 || c == 43u8 { j += 1usize }
            var zero_number = true
            while j < content.len && (is_digit(content[j]) || content[j] == 46u8) {
                if is_digit(content[j]) {
                    value = value * 10usize + usize(content[j] - 48u8)
                    if content[j] != 48u8 { zero_number = false }
                }
                j += 1usize
            }
            if in_array && neg && value >= 200usize && at > 0usize && out[at - 1usize] != 32u8 && out[at - 1usize] != 10u8 {
                at = put_latin1(out, at, 32u8)
            }
            prev_zero = last_was_zero
            last_was_zero = zero_number
            last_number = value
            i = j
        } else if (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 39u8 || c == 34u8 || c == 42u8 {
            // An operator.
            var j = i
            while j < content.len && !is_space(content[j]) && !is_delim(content[j]) && !(is_digit(content[j]) && j > i && false) { j += 1usize }
            let op = content[i..j]
            if str.eq(op, "Tf") {
                p.cur_font = MAX_FONTS
                if name_e > name_s {
                    let (font_object, has_font) = named_ref(p.data, p.table, p.count, p.res_s, p.res_e, "Font", content[name_s..name_e])
                    if has_font { p.cur_font = load_font(a, p, font_object) }
                }
            }
            if str.eq(op, "T*") || str.eq(op, "ET") || str.eq(op, "'") || str.eq(op, "\"") { at = newline(out, at) }
            if str.eq(op, "Td") || str.eq(op, "TD") {
                // The last operand is ty: a move down starts a new line.
                if !last_was_zero { at = newline(out, at) }
            }
            if str.eq(op, "Tm") { at = newline(out, at) }
            i = j
        } else {
            i += 1usize
        }
    }
    // Drop a trailing newline.
    while at > 0usize && out[at - 1usize] == 10u8 { at -= 1usize }
    ret (out[0usize..at], ok)
}

// The objects of a PDF and its page objects in page-tree order (every page object in file order when there is no usable
// tree): shared by `pages` and `page_painting`.
type Tree = struct { table: []Object, count: usize, page_objects: []usize, page_count: usize }

fn page_tree(a: *mem.Arena, data: []const u8) -> (Tree, err) {
    if !at_word(data, 0usize, "%PDF-") && find(data, "%PDF-", 0usize, 1024usize) >= 1024usize { ret (zero, NotPdf) }
    let (table, count, objects_error) = objects(a, data)
    if objects_error != ok { ret (zero, objects_error) }
    let (page_objects, po_error) = mem.alloc[usize](a, MAX_PAGES)
    if po_error != ok { ret (zero, po_error) }
    var page_count = 0usize
    var i = 0usize
    while i < count && page_count == 0usize {
        if has_pair(data, table[i].start, table[i].end, "Type", "Catalog") {
            let (root, has_root) = ref_after(data, table[i].start, table[i].end, "Pages")
            if has_root {
                let (found, walk_error) = walk(a, data, table, count, root, page_objects)
                if walk_error != ok { ret (zero, walk_error) }
                page_count = found
            }
        }
        i += 1usize
    }
    if page_count == 0usize {
        i = 0usize
        while i < count && page_count < MAX_PAGES {
            if has_pair(data, table[i].start, table[i].end, "Type", "Page") {
                page_objects[page_count] = table[i].number
                page_count += 1usize
            }
            i += 1usize
        }
    }
    if page_count == 0usize { ret (zero, NoPages) }
    ret (Tree { table: table, count: count, page_objects: page_objects, page_count: page_count }, ok)
}

// The text of each page of a PDF held in `data`, in page-tree order.
fn pages(a: *mem.Arena, data: []const u8) -> ([]str, err) {
    let (tree, tree_error) = page_tree(a, data)
    if tree_error != ok { ret (zero, tree_error) }
    let table = tree.table
    let count = tree.count
    let page_objects = tree.page_objects
    let page_count = tree.page_count
    let (out, out_error) = mem.alloc[str](a, page_count)
    if out_error != ok { ret (zero, out_error) }
    // The painter context only carries the fonts: strings are read through each page's font resources.
    var no_shapes: [1]Shape = zero
    var ctx = paint_start(no_shapes[0usize..0usize])
    ctx.data = data
    ctx.table = table
    ctx.count = count
    var p = 0usize
    while p < page_count {
        let (ps, pe, has_page) = object_span(table, count, page_objects[p])
        var combined = ""
        if has_page {
            let (page_rs, page_re, page_has_res) = resources_span(data, table, count, ps, pe)
            ctx.res_s = 0usize
            ctx.res_e = 0usize
            if page_has_res {
                ctx.res_s = page_rs
                ctx.res_e = page_re
            }
            ctx.cur_font = MAX_FONTS
            // /Contents N 0 R, or /Contents [N 0 R M 0 R ...].
            var streams: [64]usize = zero
            var stream_count = refs_in_array(data, ps, pe, "Contents", streams[0usize..])
            if stream_count == 0usize {
                let (single, has_single) = ref_after(data, ps, pe, "Contents")
                if has_single {
                    streams[0usize] = single
                    stream_count = 1usize
                }
            }
            var k = 0usize
            while k < stream_count {
                let (ss, se, has_stream) = object_span(table, count, streams[k])
                if has_stream {
                    let (content, stream_error) = stream_of(a, data, ss, se)
                    if stream_error != ok { ret (zero, stream_error) }
                    let (text, text_error) = text_run(a, content, &ctx)
                    if text_error != ok { ret (zero, text_error) }
                    if combined.len == 0usize { combined = text } else if text.len > 0usize {
                        let (joined, joined_error) = mem.alloc[u8](a, combined.len + 1usize + text.len)
                        if joined_error != ok { ret (zero, joined_error) }
                        var m = 0usize
                        while m < combined.len {
                            joined[m] = combined[m]
                            m += 1usize
                        }
                        joined[combined.len] = 10u8
                        m = 0usize
                        while m < text.len {
                            joined[combined.len + 1usize + m] = text[m]
                            m += 1usize
                        }
                        combined = joined[0usize..combined.len + 1usize + text.len]
                    }
                }
                k += 1usize
            }
        }
        out[p] = combined
        p += 1usize
    }
    ret (out, ok)
}

// ---- A page painted (C152, C172): what a content stream draws as shapes a viewer can lay out itself.
//
// `Shape.kind` is SHAPE_FILL (a filled rectangle from (x0, y0) to (x1, y1)), SHAPE_LINE (a stroked segment of
// `width`) or SHAPE_TEXT (the string `text` with its baseline start at (x0, y0), `size` high). Coordinates are the
// page's user space after the content's `cm` scales and offsets (origin bottom left, y up). Colours are the fill (or
// stroke) colour in force, 0..1. Not a full renderer: only a scale and a translation of `cm` are followed, a
// curve is drawn as its chord, a filled path that is not a rectangle is not filled, a clip does nothing, and text
// is placed from the standard fonts' Latin-1 codes at a size with no glyph metrics (a string's advance is half its
// size a character).
type Shape = struct { kind: u8, x0: f64, y0: f64, x1: f64, y1: f64, width: f64, red: f64, green: f64, blue: f64, size: f64, text: str }
type Image = struct { width: u32, height: u32, pixels: []u8 }
type Painting = struct { width: f64, height: f64, shapes: []Shape, images: []Image }
// A font resource as the painter reads it (D4800): the advance of each code from /Widths (or /W for a Type0 font), the
// code-to-Unicode pairs of its /ToUnicode CMap, and whether its strings are two-byte codes.
type FontInfo = struct { object: usize, first: usize, widths: []u16, codes: []u16, unis: []u32, mapped: usize, two_byte: bool, default_width: usize }
type Segment = struct { x0: f64, y0: f64, x1: f64, y1: f64 }

const SHAPE_FILL: u8 = 0u8
const SHAPE_LINE: u8 = 1u8
const SHAPE_TEXT: u8 = 2u8
// An image: the unit square under the current matrix, `x0`,`y0` to `x1`,`y1`; `size` is the index into `Painting.images`
// (-1 when the image was not decoded: an unsupported colour space, a size over MAX_IMAGE_PIXELS, a soft mask only).
const SHAPE_IMAGE: u8 = 3u8
const MAX_IMAGES: usize = 6usize
const MAX_IMAGE_PIXELS: usize = 1048576usize
const MAX_FONTS: usize = 8usize
const MAX_CMAP: usize = 1024usize
const MAX_WIDTHS: usize = 4096usize
const MAX_SHAPES: usize = 4000usize
const MAX_SEGMENTS: usize = 256usize
const STATE_DEPTH: usize = 8usize

// The painter: the shapes so far, the graphics state, the path under construction and the text state.
type Painter = struct { out: []Shape, n: usize, fill_r: f64, fill_g: f64, fill_b: f64, stroke_r: f64, stroke_g: f64, stroke_b: f64, line_width: f64, scale_x: f64, scale_y: f64, shift_x: f64, shift_y: f64, saved: [88]f64, depth: usize, segs: [256]Segment, seg_n: usize, rects: [64]Segment, rect_n: usize, cur_x: f64, cur_y: f64, start_x: f64, start_y: f64, tm_x: f64, tm_y: f64, line_x: f64, line_y: f64, leading: f64, font_size: f64, text_scale: f64, data: []const u8, table: []Object, count: usize, res_s: usize, res_e: usize, images: []Image, image_n: usize, image_objs: [6]usize, fonts: [8]FontInfo, font_n: usize, cur_font: usize, form_depth: usize }

fn paint_start(out: []Shape) -> Painter {
    var p: Painter = zero
    p.out = out
    p.scale_x = 1.0f64
    p.scale_y = 1.0f64
    p.line_width = 1.0f64
    p.text_scale = 1.0f64
    p.font_size = 12.0f64
    p.cur_font = MAX_FONTS
    ret p
}

fn paint_push(p: *Painter, kind: u8, x0: f64, y0: f64, x1: f64, y1: f64, width: f64, red: f64, green: f64, blue: f64, size: f64, text: str) {
    if p.n >= p.out.len { ret }
    p.out[p.n] = Shape { kind: kind, x0: p.scale_x * x0 + p.shift_x, y0: p.scale_y * y0 + p.shift_y, x1: p.scale_x * x1 + p.shift_x, y1: p.scale_y * y1 + p.shift_y, width: width, red: red, green: green, blue: blue, size: size, text: text }
    p.n += 1usize
}

// Paint the pending rectangles filled and/or the pending segments stroked, then forget the path.
fn paint_path(p: *Painter, fill: bool, stroke: bool) {
    var i = 0usize
    if fill {
        while i < p.rect_n {
            paint_push(p, SHAPE_FILL, p.rects[i].x0, p.rects[i].y0, p.rects[i].x1, p.rects[i].y1, 0.0f64, p.fill_r, p.fill_g, p.fill_b, 0.0f64, "")
            i += 1usize
        }
    }
    if stroke {
        let w = p.line_width * p.scale_x
        i = 0usize
        while i < p.rect_n {
            let r = p.rects[i]
            paint_push(p, SHAPE_LINE, r.x0, r.y0, r.x1, r.y0, w, p.stroke_r, p.stroke_g, p.stroke_b, 0.0f64, "")
            paint_push(p, SHAPE_LINE, r.x1, r.y0, r.x1, r.y1, w, p.stroke_r, p.stroke_g, p.stroke_b, 0.0f64, "")
            paint_push(p, SHAPE_LINE, r.x1, r.y1, r.x0, r.y1, w, p.stroke_r, p.stroke_g, p.stroke_b, 0.0f64, "")
            paint_push(p, SHAPE_LINE, r.x0, r.y1, r.x0, r.y0, w, p.stroke_r, p.stroke_g, p.stroke_b, 0.0f64, "")
            i += 1usize
        }
        i = 0usize
        while i < p.seg_n {
            let g = p.segs[i]
            paint_push(p, SHAPE_LINE, g.x0, g.y0, g.x1, g.y1, w, p.stroke_r, p.stroke_g, p.stroke_b, 0.0f64, "")
            i += 1usize
        }
    }
    p.rect_n = 0usize
    p.seg_n = 0usize
}

fn paint_line_to(p: *Painter, x: f64, y: f64) {
    if p.seg_n < MAX_SEGMENTS {
        p.segs[p.seg_n] = Segment { x0: p.cur_x, y0: p.cur_y, x1: x, y1: y }
        p.seg_n += 1usize
    }
    p.cur_x = x
    p.cur_y = y
}

// Draw `text` at the text position, advancing it by half the size a character.
fn paint_text(p: *Painter, text: str) {
    if text.len == 0usize { ret }
    let size = p.font_size * p.text_scale
    let advance = f64(text.len) * size * 0.5f64
    paint_push(p, SHAPE_TEXT, p.tm_x, p.tm_y, p.tm_x + advance, p.tm_y, 0.0f64, p.fill_r, p.fill_g, p.fill_b, size * p.scale_y, text)
    p.tm_x += advance
}

// Append code point `cp` to `out` at `at` as UTF-8; the new position (unchanged when it does not fit).
fn put_utf8(out: []u8, at: usize, cp: u32) -> usize {
    if cp < 128u32 {
        if at + 1usize > out.len { ret at }
        out[at] = u8(cp)
        ret at + 1usize
    }
    if cp < 2048u32 {
        if at + 2usize > out.len { ret at }
        out[at] = 192u8 | u8(cp >> 6u32)
        out[at + 1usize] = 128u8 | u8(cp & 63u32)
        ret at + 2usize
    }
    if cp < 65536u32 {
        if at + 3usize > out.len { ret at }
        out[at] = 224u8 | u8(cp >> 12u32)
        out[at + 1usize] = 128u8 | u8((cp >> 6u32) & 63u32)
        out[at + 2usize] = 128u8 | u8(cp & 63u32)
        ret at + 3usize
    }
    if at + 4usize > out.len { ret at }
    out[at] = 240u8 | u8((cp >> 18u32) & 7u32)
    out[at + 1usize] = 128u8 | u8((cp >> 12u32) & 63u32)
    out[at + 2usize] = 128u8 | u8((cp >> 6u32) & 63u32)
    out[at + 3usize] = 128u8 | u8(cp & 63u32)
    ret at + 4usize
}

// The code point font `f` maps `code` to (its /ToUnicode CMap), or `code` itself when the font has no entry (Latin-1).
fn font_unicode(f: *const FontInfo, code: usize) -> u32 {
    var i = 0usize
    while i < f.mapped {
        if usize(f.codes[i]) == code { ret f.unis[i] }
        i += 1usize
    }
    ret u32(code)
}

// The advance of `code` in 1/1000 of the font size: /Widths (or /W), else the default (500, or the CID font's /DW).
fn font_width(f: *const FontInfo, code: usize) -> usize {
    if code >= f.first && code - f.first < f.widths.len { ret usize(f.widths[code - f.first]) }
    ret f.default_width
}

// Draw the string of raw codes `raw` at the text position through the current font: each code becomes its Unicode
// (the ToUnicode map, else Latin-1) written as UTF-8 and advances the position by the font's width for it. A string
// with no font known is Latin-1 at half the size a character, as before fonts were read.
fn paint_run(a: *mem.Arena, p: *Painter, raw: []const u8) {
    if raw.len == 0usize { ret }
    let size = p.font_size * p.text_scale
    if p.cur_font >= p.font_n {
        let (utf, utf_error) = mem.alloc[u8](a, raw.len * 2usize + 2usize)
        if utf_error != ok { ret }
        var at = 0usize
        var i = 0usize
        while i < raw.len {
            at = put_latin1(utf, at, raw[i])
            i += 1usize
        }
        paint_text(p, utf[0usize..at])
        ret
    }
    let f = &p.fonts[p.cur_font]
    let (utf, utf_error) = mem.alloc[u8](a, raw.len * 4usize + 4usize)
    if utf_error != ok { ret }
    var at = 0usize
    var units = 0usize
    var i = 0usize
    while i < raw.len {
        var code = usize(raw[i])
        i += 1usize
        if f.two_byte {
            if i < raw.len {
                code = code * 256usize + usize(raw[i])
                i += 1usize
            }
        }
        at = put_utf8(utf, at, font_unicode(f, code))
        units += font_width(f, code)
    }
    if at == 0usize { ret }
    let advance = f64(units) * size / 1000.0f64
    paint_push(p, SHAPE_TEXT, p.tm_x, p.tm_y, p.tm_x + advance, p.tm_y, 0.0f64, p.fill_r, p.fill_g, p.fill_b, size * p.scale_y, utf[0usize..at])
    p.tm_x += advance
}

fn paint_move_text(p: *Painter, tx: f64, ty: f64) {
    p.line_x += tx * p.text_scale
    p.line_y += ty * p.text_scale
    p.tm_x = p.line_x
    p.tm_y = p.line_y
}

fn operand_number(text: str) -> f64 {
    let (value, parse_error) = str.parse_f64(text)
    if parse_error != ok { ret 0.0f64 }
    ret value
}

// ---- Resources, fonts and images (D4800).

// The position after the `>>` matching the `<<` at `k` (or `until`).
fn dict_end(data: []const u8, k: usize, until: usize) -> usize {
    var depth = 0usize
    var at = k
    while at + 1usize < until {
        if data[at] == 60u8 && data[at + 1usize] == 60u8 {
            depth += 1usize
            at += 2usize
        } else if data[at] == 62u8 && data[at + 1usize] == 62u8 {
            if depth <= 1usize { ret at + 2usize }
            depth -= 1usize
            at += 2usize
        } else {
            at += 1usize
        }
    }
    ret until
}

// The value of `/key` in data[from..until] when it is a dictionary or an indirect reference to an object: the span of
// the dictionary text (from its `<<`), or of the object it points at.
fn region_after(data: []const u8, table: []const Object, count: usize, from: usize, until: usize, key: str) -> (usize, usize, bool) {
    var at = from
    while at < until {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            var k = at + 1usize + key.len
            if k >= until || is_space(data[k]) || is_delim(data[k]) {
                while k < until && is_space(data[k]) { k += 1usize }
                if k + 1usize < until && data[k] == 60u8 && data[k + 1usize] == 60u8 { ret (k, dict_end(data, k, until), true) }
                let (number, after_number, got_number) = number_at(data, k, until)
                if got_number {
                    let (gen, after_gen, got_gen) = number_at(data, after_number, until)
                    var r = after_gen
                    while r < until && is_space(data[r]) { r += 1usize }
                    if got_gen && r < until && data[r] == 82u8 {
                        let (s, e, found) = object_span(table, count, number)
                        if found { ret (s, e, true) }
                    }
                }
                ret (0usize, 0usize, false)
            }
        }
        at += 1usize
    }
    ret (0usize, 0usize, false)
}

// The span of the page's resource dictionary: its own `/Resources`, else the first page tree node's.
fn resources_span(data: []const u8, table: []const Object, count: usize, ps: usize, pe: usize) -> (usize, usize, bool) {
    let (s, e, found) = region_after(data, table, count, ps, pe, "Resources")
    if found { ret (s, e, true) }
    var o = 0usize
    while o < count {
        if has_pair(data, table[o].start, table[o].end, "Type", "Pages") {
            let (s2, e2, found2) = region_after(data, table, count, table[o].start, table[o].end, "Resources")
            if found2 { ret (s2, e2, true) }
        }
        o += 1usize
    }
    ret (0usize, 0usize, false)
}

// The object number `name` stands for in the resource group `group` (`Font`, `XObject`) of the resources in
// data[rs..re]: `/Font << /F1 7 0 R >>` or `/Font 9 0 R` with the dictionary in object 9.
fn named_ref(data: []const u8, table: []const Object, count: usize, rs: usize, re: usize, group: str, name: str) -> (usize, bool) {
    let (gs, ge, has_group) = region_after(data, table, count, rs, re, group)
    if !has_group { ret (0usize, false) }
    var at = gs
    while at < ge {
        if data[at] == 47u8 && at_word(data, at + 1usize, name) {
            let k = at + 1usize + name.len
            if k >= ge || is_space(data[k]) || is_delim(data[k]) {
                let (number, after_number, got_number) = number_at(data, k, ge)
                if got_number {
                    let (gen, after_gen, got_gen) = number_at(data, after_number, ge)
                    var r = after_gen
                    while r < ge && is_space(data[r]) { r += 1usize }
                    if got_gen && r < ge && data[r] == 82u8 { ret (number, true) }
                }
                ret (0usize, false)
            }
        }
        at += 1usize
    }
    ret (0usize, false)
}

// The integer after `/key` in data[from..until], `fallback` when there is none.
fn int_after(data: []const u8, from: usize, until: usize, key: str, fallback: usize) -> usize {
    var at = from
    while at < until {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            let k = at + 1usize + key.len
            if k >= until || is_space(data[k]) || is_delim(data[k]) {
                let (n, after, got) = number_at(data, k, until)
                if got { ret n }
                ret fallback
            }
        }
        at += 1usize
    }
    ret fallback
}

// The span of the array value of `/key` (`[` ... its matching `]`, nested arrays allowed), directly or through a
// reference: (position of `[`, position of the matching `]`, found).
fn array_after(data: []const u8, table: []const Object, count: usize, from: usize, until: usize, key: str) -> (usize, usize, bool) {
    var at = from
    while at < until {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            var k = at + 1usize + key.len
            if k >= until || is_space(data[k]) || is_delim(data[k]) {
                while k < until && is_space(data[k]) { k += 1usize }
                var from_s = k
                var from_e = until
                if k < until && data[k] != 91u8 {
                    let (number, after_number, got_number) = number_at(data, k, until)
                    if !got_number { ret (0usize, 0usize, false) }
                    let (s, e, found) = object_span(table, count, number)
                    if !found { ret (0usize, 0usize, false) }
                    from_s = s
                    from_e = e
                    while from_s < from_e && data[from_s] != 91u8 { from_s += 1usize }
                }
                if from_s >= from_e || data[from_s] != 91u8 { ret (0usize, 0usize, false) }
                var depth = 0usize
                var j = from_s
                while j < from_e {
                    if data[j] == 91u8 { depth += 1usize }
                    if data[j] == 93u8 {
                        depth -= 1usize
                        if depth == 0usize { ret (from_s, j, true) }
                    }
                    j += 1usize
                }
                ret (0usize, 0usize, false)
            }
        }
        at += 1usize
    }
    ret (0usize, 0usize, false)
}

// The next token of an array: kind 0 end, 1 number (value, rounded down), 2 `[`, 3 `]`; and the position after it.
fn array_token(data: []const u8, at: usize, until: usize) -> (u8, f64, usize) {
    var i = at
    while i < until && (is_space(data[i]) || (!is_digit(data[i]) && data[i] != 91u8 && data[i] != 93u8 && data[i] != 45u8 && data[i] != 46u8)) { i += 1usize }
    if i >= until { ret (0u8, 0.0f64, until) }
    if data[i] == 91u8 { ret (2u8, 0.0f64, i + 1usize) }
    if data[i] == 93u8 { ret (3u8, 0.0f64, i + 1usize) }
    var j = i + 1usize
    while j < until && (is_digit(data[j]) || data[j] == 46u8) { j += 1usize }
    ret (1u8, operand_number(data[i..j]), j)
}

// The widths of a simple font: the numbers of its /Widths array in order.
fn read_widths(data: []const u8, s: usize, e: usize, out: []u16) -> usize {
    var at = s + 1usize
    var n = 0usize
    var running = true
    while running && n < out.len {
        let (kind, value, after) = array_token(data, at, e)
        at = after
        if kind == 0u8 || kind == 3u8 { running = false } else if kind == 1u8 {
            var w = value + 0.5f64
            if w < 0.0f64 { w = 0.0f64 }
            if w > 65000.0f64 { w = 65000.0f64 }
            out[n] = u16(usize(w))
            n += 1usize
        }
    }
    ret n
}

// A CID font's /W array: `c [w1 w2 ...]` and `c1 c2 w` entries into `out` indexed by code; the number of entries
// the array reaches (up to out.len).
fn read_cid_widths(data: []const u8, s: usize, e: usize, out: []u16) -> usize {
    var at = s + 1usize
    var top = 0usize
    var running = true
    while running {
        let (kind, first_value, after) = array_token(data, at, e)
        at = after
        if kind != 1u8 { running = false } else {
            let c1 = usize(first_value)
            let (kind2, value2, after2) = array_token(data, at, e)
            at = after2
            if kind2 == 2u8 {
                var c = c1
                var inside = true
                while inside {
                    let (kind3, value3, after3) = array_token(data, at, e)
                    at = after3
                    if kind3 != 1u8 { inside = false } else {
                        if c < out.len {
                            out[c] = u16(usize(value3 + 0.5f64))
                            if c + 1usize > top { top = c + 1usize }
                        }
                        c += 1usize
                    }
                }
            } else if kind2 == 1u8 {
                let c2 = usize(value2)
                let (kind3, value3, after3) = array_token(data, at, e)
                at = after3
                if kind3 != 1u8 { running = false } else {
                    var c = c1
                    while c <= c2 && c < out.len {
                        out[c] = u16(usize(value3 + 0.5f64))
                        c += 1usize
                    }
                    if c > top { top = c }
                }
            } else {
                running = false
            }
        }
    }
    ret top
}

// The `<hex>` at `at` (which is the `<`): its value (the first UTF-16 unit, or the code point a surrogate pair
// makes), how many bytes it spelled, the position after the `>`, and whether there was one.
fn hex_value(data: []const u8, at: usize, until: usize) -> (u32, usize, usize, bool) {
    if at >= until || data[at] != 60u8 { ret (0u32, 0usize, at, false) }
    var i = at + 1usize
    var digits = 0usize
    var value = 0u32
    var low = 0u32
    while i < until && data[i] != 62u8 {
        let h = data[i]
        var v = 99u32
        if h >= 48u8 && h <= 57u8 { v = u32(h - 48u8) }
        if h >= 65u8 && h <= 70u8 { v = u32(h - 55u8) }
        if h >= 97u8 && h <= 102u8 { v = u32(h - 87u8) }
        if v != 99u32 {
            if digits < 4usize { value = value * 16u32 + v }
            if digits >= 4usize && digits < 8usize { low = low * 16u32 + v }
            digits += 1usize
        }
        i += 1usize
    }
    if value >= 55296u32 && value < 56320u32 && digits >= 8usize { value = 65536u32 + ((value - 55296u32) << 10u32) + (low - 56320u32) }
    ret (value, (digits + 1usize) / 2usize, i + 1usize, true)
}

// Read the `bfchar` and `bfrange` blocks of a ToUnicode CMap into the font's code and Unicode lists; marks a font
// with two-byte source codes. The entry count (at most MAX_CMAP).
fn read_cmap(data: []const u8, f: *FontInfo, codes: []u16, unis: []u32) -> usize {
    var n = 0usize
    var mode = 0usize
    var at = 0usize
    while at < data.len {
        if at_word(data, at, "beginbfchar") {
            mode = 1usize
            at += 11usize
        } else if at_word(data, at, "beginbfrange") {
            mode = 2usize
            at += 12usize
        } else if at_word(data, at, "endbf") {
            mode = 0usize
            at += 5usize
        } else if data[at] == 60u8 && mode == 1usize {
            let (src, src_bytes, after_src, got_src) = hex_value(data, at, data.len)
            var j = after_src
            while j < data.len && data[j] != 60u8 { j += 1usize }
            let (dst, dst_bytes, after_dst, got_dst) = hex_value(data, j, data.len)
            if got_src && got_dst && n < codes.len {
                codes[n] = u16(src & 65535u32)
                unis[n] = dst
                n += 1usize
                if src_bytes == 2usize { f.two_byte = true }
            }
            at = after_dst
        } else if data[at] == 60u8 && mode == 2usize {
            let (lo, lo_bytes, after_lo, got_lo) = hex_value(data, at, data.len)
            var j = after_lo
            while j < data.len && data[j] != 60u8 { j += 1usize }
            let (hi, hi_bytes, after_hi, got_hi) = hex_value(data, j, data.len)
            j = after_hi
            while j < data.len && is_space(data[j]) { j += 1usize }
            if lo_bytes == 2usize { f.two_byte = true }
            if j < data.len && data[j] == 91u8 {
                j += 1usize
                var c = lo
                var inside = true
                while inside && j < data.len {
                    while j < data.len && is_space(data[j]) { j += 1usize }
                    if j < data.len && data[j] == 60u8 {
                        let (d, d_bytes, after_d, got_d) = hex_value(data, j, data.len)
                        if n < codes.len && c <= 65535u32 {
                            codes[n] = u16(c)
                            unis[n] = d
                            n += 1usize
                        }
                        c += 1u32
                        j = after_d
                    } else {
                        inside = false
                    }
                }
                at = j + 1usize
            } else {
                let (dst, dst_bytes, after_dst, got_dst) = hex_value(data, j, data.len)
                if got_lo && got_hi && got_dst {
                    var c = lo
                    while c <= hi && c <= 65535u32 && n < codes.len {
                        codes[n] = u16(c)
                        unis[n] = dst + (c - lo)
                        n += 1usize
                        c += 1u32
                    }
                }
                at = after_dst
            }
        } else {
            at += 1usize
        }
    }
    ret n
}

// Load the font dictionary of object `object` into the painter's table; its index, or MAX_FONTS when it cannot be.
fn load_font(a: *mem.Arena, p: *Painter, object: usize) -> usize {
    var i = 0usize
    while i < p.font_n {
        if p.fonts[i].object == object { ret i }
        i += 1usize
    }
    if p.font_n >= MAX_FONTS { ret MAX_FONTS }
    let data = p.data
    let (s, e, found) = object_span(p.table, p.count, object)
    if !found { ret MAX_FONTS }
    var f: FontInfo = zero
    f.object = object
    f.default_width = 500usize
    f.two_byte = has_pair(data, s, e, "Subtype", "Type0")
    if f.two_byte {
        var d: [4]usize = zero
        let d_count = refs_in_array(data, s, e, "DescendantFonts", d[0usize..])
        if d_count > 0usize {
            let (ds, de, has_d) = object_span(p.table, p.count, d[0usize])
            if has_d {
                f.default_width = int_after(data, ds, de, "DW", 1000usize)
                let (ws, we, has_w) = array_after(data, p.table, p.count, ds, de, "W")
                if has_w {
                    let (widths, widths_error) = mem.alloc[u16](a, MAX_WIDTHS)
                    if widths_error == ok {
                        var z = 0usize
                        while z < widths.len {
                            widths[z] = u16(f.default_width)
                            z += 1usize
                        }
                        let top = read_cid_widths(data, ws, we, widths)
                        f.widths = widths[0usize..top]
                    }
                }
            }
        }
    } else {
        f.first = int_after(data, s, e, "FirstChar", 0usize)
        let (ws, we, has_w) = array_after(data, p.table, p.count, s, e, "Widths")
        if has_w {
            let (widths, widths_error) = mem.alloc[u16](a, 256usize)
            if widths_error == ok {
                let n = read_widths(data, ws, we, widths)
                f.widths = widths[0usize..n]
            }
        }
    }
    let (tu, has_tu) = ref_after(data, s, e, "ToUnicode")
    if has_tu {
        let (ts, te, has_stream) = object_span(p.table, p.count, tu)
        if has_stream {
            let (cmap, cmap_error) = stream_capped(a, data, ts, te, 65536usize)
            let (codes, codes_error) = mem.alloc[u16](a, MAX_CMAP)
            let (unis, unis_error) = mem.alloc[u32](a, MAX_CMAP)
            if cmap_error == ok && codes_error == ok && unis_error == ok {
                let n = read_cmap(cmap, &f, codes, unis)
                f.codes = codes[0usize..n]
                f.unis = unis[0usize..n]
                f.mapped = n
            }
        }
    }
    p.fonts[p.font_n] = f
    p.font_n += 1usize
    ret p.font_n - 1usize
}

// Undo the PNG row predictors (10 to 15) of `raw` in place: rows of `row_bytes` after a filter byte, `bpp` bytes a
// pixel; the length of the plain rows, written from the start.
fn unpredict(raw: []u8, row_bytes: usize, bpp: usize) -> usize {
    let stride = row_bytes + 1usize
    var rows = raw.len / stride
    var y = 0usize
    while y < rows {
        let kind = raw[y * stride]
        let src = y * stride + 1usize
        let dst = y * row_bytes
        var x = 0usize
        while x < row_bytes {
            var left = 0usize
            var up = 0usize
            var up_left = 0usize
            if x >= bpp { left = usize(raw[dst + x - bpp]) }
            if y > 0usize { up = usize(raw[dst - row_bytes + x]) }
            if x >= bpp && y > 0usize { up_left = usize(raw[dst - row_bytes + x - bpp]) }
            var v = usize(raw[src + x])
            if kind == 1u8 { v = v + left } else if kind == 2u8 { v = v + up } else if kind == 3u8 { v = v + (left + up) / 2usize } else if kind == 4u8 {
                // Paeth: the neighbour nearest left + up - up_left, in signed arithmetic (the estimate can be below zero).
                let guess = i64(left) + i64(up) - i64(up_left)
                var da = guess - i64(left)
                if da < 0i64 { da = 0i64 - da }
                var db = guess - i64(up)
                if db < 0i64 { db = 0i64 - db }
                var dc = guess - i64(up_left)
                if dc < 0i64 { dc = 0i64 - dc }
                var pred = up_left
                if da <= db && da <= dc { pred = left } else if db <= dc { pred = up }
                v = v + pred
            }
            raw[dst + x] = u8(v & 255usize)
            x += 1usize
        }
        y += 1usize
    }
    ret rows * row_bytes
}

// Decode the image XObject of object span [s, e) into RGBA: DCT through e.fmt.jpeg, or Flate samples of 8-bit gray, RGB
// or CMYK (guessed from the sample count when the colour space is an ICC or calibrated one), with the PNG predictors,
// 1-bit gray and stencil masks. False for what it does not read (Indexed, 16 bits, a size over MAX_IMAGE_PIXELS).
fn decode_image(a: *mem.Arena, p: *Painter, s: usize, e: usize) -> (Image, bool) {
    let data = p.data
    let keyword = find(data, "stream", s, e)
    let width = int_after(data, s, keyword, "Width", 0usize)
    let height = int_after(data, s, keyword, "Height", 0usize)
    let bits = int_after(data, s, keyword, "BitsPerComponent", 8usize)
    if width == 0usize || height == 0usize || width * height > MAX_IMAGE_PIXELS { ret (zero, false) }
    var is_mask = false
    let mask_key = find(data, "/ImageMask", s, keyword)
    if mask_key < keyword {
        var m = mask_key + 10usize
        while m < keyword && is_space(data[m]) { m += 1usize }
        is_mask = at_word(data, m, "true")
    }
    let is_dct = find(data, "DCTDecode", s, keyword) < keyword
    let (pixels, pixels_error) = mem.alloc[u8](a, width * height * 4usize)
    if pixels_error != ok { ret (zero, false) }
    let (raw, raw_error) = stream_capped(a, data, s, e, width * height * 4usize + height + 64usize)
    if raw_error != ok || raw.len == 0usize { ret (zero, false) }
    if is_dct {
        var reader_state: io.SliceReader = zero
        reader_state.data = raw
        reader_state.off = 0usize
        let (decoded, decode_error) = jpeg.decode(a, io.slice_reader(&reader_state), jpeg.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: u64(MAX_IMAGE_PIXELS) })
        if decode_error != ok { ret (zero, false) }
        var y = 0usize
        while y < usize(decoded.height) && y < height {
            var x = 0usize
            while x < usize(decoded.width) && x < width {
                var r = 0u8
                var g = 0u8
                var b = 0u8
                if decoded.format == .R8 {
                    r = decoded.pixels[y * decoded.stride + x]
                    g = r
                    b = r
                } else {
                    let at = y * decoded.stride + x * 4usize
                    r = decoded.pixels[at]
                    g = decoded.pixels[at + 1usize]
                    b = decoded.pixels[at + 2usize]
                }
                let o = (y * width + x) * 4usize
                pixels[o] = r
                pixels[o + 1usize] = g
                pixels[o + 2usize] = b
                pixels[o + 3usize] = 255u8
                x += 1usize
            }
            y += 1usize
        }
        ret (Image { width: u32(width), height: u32(height), pixels: pixels }, true)
    }
    var samples = raw
    var work = raw
    let predictor = int_after(data, s, keyword, "Predictor", 1usize)
    var components = 0usize
    if has_pair(data, s, keyword, "ColorSpace", "DeviceGray") || has_pair(data, s, keyword, "ColorSpace", "CalGray") || is_mask { components = 1usize }
    if has_pair(data, s, keyword, "ColorSpace", "DeviceRGB") || has_pair(data, s, keyword, "ColorSpace", "CalRGB") { components = 3usize }
    if has_pair(data, s, keyword, "ColorSpace", "DeviceCMYK") { components = 4usize }
    if has_pair(data, s, keyword, "ColorSpace", "Indexed") || find(data, "Indexed", s, keyword) < keyword { ret (zero, false) }
    if components == 0usize && bits == 8usize {
        // ICCBased and the like: the sample count says how many components a pixel has.
        let per = work.len / (width * height)
        if per >= 4usize { components = 4usize } else if per >= 3usize { components = 3usize } else { components = 1usize }
    }
    if components == 0usize { components = 1usize }
    if predictor >= 10usize {
        let (copy, copy_error) = mem.alloc[u8](a, work.len)
        if copy_error != ok { ret (zero, false) }
        mem.copy[u8](copy, work)
        let colors = int_after(data, s, keyword, "Colors", 1usize)
        let columns = int_after(data, s, keyword, "Columns", 1usize)
        let row_bytes = (colors * bits * columns + 7usize) / 8usize
        var bpp = (colors * bits + 7usize) / 8usize
        if bpp == 0usize { bpp = 1usize }
        let kept = unpredict(copy, row_bytes, bpp)
        samples = copy[0usize..kept]
    }
    if bits == 8usize {
        let need = width * height * components
        if samples.len < need { ret (zero, false) }
        var i = 0usize
        while i < width * height {
            var r = 0u8
            var g = 0u8
            var b = 0u8
            var alpha = 255u8
            if components == 1usize {
                r = samples[i]
                g = r
                b = r
            } else if components == 3usize {
                r = samples[i * 3usize]
                g = samples[i * 3usize + 1usize]
                b = samples[i * 3usize + 2usize]
            } else {
                let k = 255usize - usize(samples[i * 4usize + 3usize])
                r = u8((255usize - usize(samples[i * 4usize])) * k / 255usize)
                g = u8((255usize - usize(samples[i * 4usize + 1usize])) * k / 255usize)
                b = u8((255usize - usize(samples[i * 4usize + 2usize])) * k / 255usize)
            }
            pixels[i * 4usize] = r
            pixels[i * 4usize + 1usize] = g
            pixels[i * 4usize + 2usize] = b
            pixels[i * 4usize + 3usize] = alpha
            i += 1usize
        }
        ret (Image { width: u32(width), height: u32(height), pixels: pixels }, true)
    }
    if bits == 1usize && components == 1usize {
        let row = (width + 7usize) / 8usize
        if samples.len < row * height { ret (zero, false) }
        // A stencil paints where the sample is 0 (unless /Decode [1 0]); gray 1 bit is black at 0, white at 1.
        let inverted = find(data, "Decode", s, keyword) < keyword && find(data, "[1 0]", s, keyword) < keyword
        var y = 0usize
        while y < height {
            var x = 0usize
            while x < width {
                var bit = (samples[y * row + x / 8usize] >> u32(7usize - x % 8usize)) & 1u8
                if inverted { bit = 1u8 - bit }
                let o = (y * width + x) * 4usize
                var v = 0u8
                if bit != 0u8 { v = 255u8 }
                pixels[o] = v
                pixels[o + 1usize] = v
                pixels[o + 2usize] = v
                pixels[o + 3usize] = 255u8
                if is_mask {
                    pixels[o] = 0u8
                    pixels[o + 1usize] = 0u8
                    pixels[o + 2usize] = 0u8
                    if bit == 0u8 { pixels[o + 3usize] = 255u8 } else { pixels[o + 3usize] = 0u8 }
                }
                x += 1usize
            }
            y += 1usize
        }
        ret (Image { width: u32(width), height: u32(height), pixels: pixels }, true)
    }
    ret (zero, false)
}

// `Do` for the XObject called `name`: an image becomes a SHAPE_IMAGE over the unit square under the current matrix; a
// form's content stream is run in place (two deep).
fn paint_xobject(a: *mem.Arena, p: *Painter, name: []const u8) {
    let (object, found) = named_ref(p.data, p.table, p.count, p.res_s, p.res_e, "XObject", name)
    if !found { ret }
    let (s, e, has_span) = object_span(p.table, p.count, object)
    if !has_span { ret }
    let keyword = find(p.data, "stream", s, e)
    if has_pair(p.data, s, keyword, "Subtype", "Form") {
        if p.form_depth < 2usize {
            let (content, content_error) = stream_of(a, p.data, s, e)
            if content_error == ok {
                p.form_depth += 1usize
                let run_error = paint_content(a, p, content)
                p.form_depth -= 1usize
            }
        }
        ret
    }
    if !has_pair(p.data, s, keyword, "Subtype", "Image") { ret }
    if p.images.len == 0usize {
        let (list, list_error) = mem.alloc[Image](a, MAX_IMAGES)
        if list_error != ok { ret }
        p.images = list
    }
    var index = MAX_IMAGES
    var k = 0usize
    while k < p.image_n {
        if p.image_objs[k] == object { index = k }
        k += 1usize
    }
    if index == MAX_IMAGES && p.image_n < MAX_IMAGES {
        let (decoded, decoded_ok) = decode_image(a, p, s, e)
        if decoded_ok {
            p.images[p.image_n] = decoded
            p.image_objs[p.image_n] = object
            index = p.image_n
            p.image_n += 1usize
        }
    }
    var shown = -1.0f64
    if index < MAX_IMAGES { shown = f64(index) }
    paint_push(p, SHAPE_IMAGE, 0.0f64, 0.0f64, 1.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, shown, "")
}

// Run a content stream over the painter.
fn paint_content(a: *mem.Arena, p: *Painter, content: []const u8) -> err {
    var operands: [8]f64 = zero
    var count = 0usize
    let (buffer, buffer_error) = mem.alloc[u8](a, content.len * 2usize + 16usize)
    if buffer_error != ok { ret buffer_error }
    var used = 0usize
    var pending_start = 0usize
    var has_text = false
    var in_array = false
    var name_s = 0usize
    var name_e = 0usize
    var i = 0usize
    while i < content.len {
        let c = content[i]
        if is_space(c) {
            i += 1usize
        } else if c == 37u8 {
            while i < content.len && content[i] != 10u8 && content[i] != 13u8 { i += 1usize }
        } else if c == 40u8 {
            // A literal string into the buffer: appended to the pending text.
            if !has_text {
                pending_start = used
                has_text = true
            }
            var depth = 1usize
            i += 1usize
            while i < content.len && depth > 0usize {
                let d = content[i]
                if d == 92u8 && i + 1usize < content.len {
                    let e = content[i + 1usize]
                    i += 2usize
                    if e == 110u8 || e == 114u8 || e == 116u8 || e == 98u8 || e == 102u8 {
                        used = put_raw(buffer, used, 32u8)
                    } else if e >= 48u8 && e <= 55u8 {
                        var code = usize(e - 48u8)
                        var digits = 1usize
                        while digits < 3usize && i < content.len && content[i] >= 48u8 && content[i] <= 55u8 {
                            code = code * 8usize + usize(content[i] - 48u8)
                            i += 1usize
                            digits += 1usize
                        }
                        used = put_raw(buffer, used, u8(code & 255usize))
                    } else if e != 10u8 && e != 13u8 {
                        used = put_raw(buffer, used, e)
                    }
                } else {
                    if d == 40u8 { depth += 1usize }
                    if d == 41u8 { depth -= 1usize }
                    if depth > 0usize { used = put_raw(buffer, used, d) }
                    i += 1usize
                }
            }
        } else if c == 60u8 && i + 1usize < content.len && content[i + 1usize] == 60u8 {
            i += 2usize
        } else if c == 62u8 && i + 1usize < content.len && content[i + 1usize] == 62u8 {
            i += 2usize
        } else if c == 60u8 {
            if !has_text {
                pending_start = used
                has_text = true
            }
            i += 1usize
            var high = 0usize
            var have_high = false
            while i < content.len && content[i] != 62u8 {
                let h = content[i]
                var v = 99usize
                if h >= 48u8 && h <= 57u8 { v = usize(h - 48u8) }
                if h >= 65u8 && h <= 70u8 { v = usize(h - 55u8) }
                if h >= 97u8 && h <= 102u8 { v = usize(h - 87u8) }
                if v != 99usize {
                    if have_high {
                        used = put_raw(buffer, used, u8(high * 16usize + v))
                        have_high = false
                    } else {
                        high = v
                        have_high = true
                    }
                }
                i += 1usize
            }
            if have_high { used = put_raw(buffer, used, u8(high * 16usize)) }
            i += 1usize
        } else if c == 91u8 {
            in_array = true
            i += 1usize
        } else if c == 93u8 {
            in_array = false
            i += 1usize
        } else if c == 47u8 {
            // A name: kept as the last one (the operand of Tf and Do).
            i += 1usize
            name_s = i
            while i < content.len && !is_space(content[i]) && !is_delim(content[i]) { i += 1usize }
            name_e = i
        } else if is_digit(c) || c == 45u8 || c == 43u8 || c == 46u8 {
            var j = i + 1usize
            while j < content.len && (is_digit(content[j]) || content[j] == 46u8) { j += 1usize }
            let value = operand_number(content[i..j])
            if in_array {
                // A kern inside TJ: a big pull back is a word space.
                if value <= -200.0f64 && has_text && used > pending_start && buffer[used - 1usize] != 32u8 {
                    // A word space: a two-byte font's space is the code 0x0020.
                    if p.cur_font < p.font_n && p.fonts[p.cur_font].two_byte { used = put_raw(buffer, used, 0u8) }
                    used = put_raw(buffer, used, 32u8)
                }
            } else {
                if count < 8usize {
                    operands[count] = value
                    count += 1usize
                } else {
                    // Keep the last eight.
                    var k = 0usize
                    while k + 1usize < 8usize {
                        operands[k] = operands[k + 1usize]
                        k += 1usize
                    }
                    operands[7usize] = value
                }
            }
            i = j
        } else if (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 39u8 || c == 34u8 || c == 42u8 {
            var j = i
            while j < content.len && !is_space(content[j]) && !is_delim(content[j]) { j += 1usize }
            let op = content[i..j]
            // The operands: the last n of what was read, in order.
            var o0 = 0.0f64
            var o1 = 0.0f64
            var o2 = 0.0f64
            var o3 = 0.0f64
            var o4 = 0.0f64
            var o5 = 0.0f64
            if count >= 6usize {
                o0 = operands[count - 6usize]
                o1 = operands[count - 5usize]
                o2 = operands[count - 4usize]
                o3 = operands[count - 3usize]
                o4 = operands[count - 2usize]
                o5 = operands[count - 1usize]
            } else if count == 5usize {
                o1 = operands[0usize]
                o2 = operands[1usize]
                o3 = operands[2usize]
                o4 = operands[3usize]
                o5 = operands[4usize]
            } else if count == 4usize {
                o2 = operands[0usize]
                o3 = operands[1usize]
                o4 = operands[2usize]
                o5 = operands[3usize]
            } else if count == 3usize {
                o3 = operands[0usize]
                o4 = operands[1usize]
                o5 = operands[2usize]
            } else if count == 2usize {
                o4 = operands[0usize]
                o5 = operands[1usize]
            } else if count == 1usize {
                o5 = operands[0usize]
            }
            let pending = buffer[pending_start..used]
            if str.eq(op, "re") {
                if p.rect_n < 64usize {
                    p.rects[p.rect_n] = Segment { x0: o2, y0: o3, x1: o2 + o4, y1: o3 + o5 }
                    p.rect_n += 1usize
                }
            } else if str.eq(op, "m") {
                p.cur_x = o4
                p.cur_y = o5
                p.start_x = o4
                p.start_y = o5
            } else if str.eq(op, "l") {
                paint_line_to(p, o4, o5)
            } else if str.eq(op, "c") {
                paint_line_to(p, o4, o5)
            } else if str.eq(op, "v") || str.eq(op, "y") {
                paint_line_to(p, o4, o5)
            } else if str.eq(op, "h") {
                paint_line_to(p, p.start_x, p.start_y)
            } else if str.eq(op, "f") || str.eq(op, "F") || str.eq(op, "f*") {
                paint_path(p, true, false)
            } else if str.eq(op, "S") || str.eq(op, "s") {
                paint_path(p, false, true)
            } else if str.eq(op, "B") || str.eq(op, "B*") || str.eq(op, "b") || str.eq(op, "b*") {
                paint_path(p, true, true)
            } else if str.eq(op, "n") {
                paint_path(p, false, false)
            } else if str.eq(op, "rg") {
                p.fill_r = o3
                p.fill_g = o4
                p.fill_b = o5
            } else if str.eq(op, "RG") {
                p.stroke_r = o3
                p.stroke_g = o4
                p.stroke_b = o5
            } else if str.eq(op, "g") {
                p.fill_r = o5
                p.fill_g = o5
                p.fill_b = o5
            } else if str.eq(op, "G") {
                p.stroke_r = o5
                p.stroke_g = o5
                p.stroke_b = o5
            } else if str.eq(op, "k") {
                p.fill_r = (1.0f64 - o2) * (1.0f64 - o5)
                p.fill_g = (1.0f64 - o3) * (1.0f64 - o5)
                p.fill_b = (1.0f64 - o4) * (1.0f64 - o5)
            } else if str.eq(op, "K") {
                p.stroke_r = (1.0f64 - o2) * (1.0f64 - o5)
                p.stroke_g = (1.0f64 - o3) * (1.0f64 - o5)
                p.stroke_b = (1.0f64 - o4) * (1.0f64 - o5)
            } else if str.eq(op, "w") {
                p.line_width = o5
            } else if str.eq(op, "q") {
                if p.depth < STATE_DEPTH {
                    let at = p.depth * 11usize
                    p.saved[at] = p.fill_r
                    p.saved[at + 1usize] = p.fill_g
                    p.saved[at + 2usize] = p.fill_b
                    p.saved[at + 3usize] = p.stroke_r
                    p.saved[at + 4usize] = p.stroke_g
                    p.saved[at + 5usize] = p.stroke_b
                    p.saved[at + 6usize] = p.line_width
                    p.saved[at + 7usize] = p.scale_x
                    p.saved[at + 8usize] = p.scale_y
                    p.saved[at + 9usize] = p.shift_x
                    p.saved[at + 10usize] = p.shift_y
                    p.depth += 1usize
                }
            } else if str.eq(op, "Q") {
                if p.depth > 0usize {
                    p.depth -= 1usize
                    let at = p.depth * 11usize
                    p.fill_r = p.saved[at]
                    p.fill_g = p.saved[at + 1usize]
                    p.fill_b = p.saved[at + 2usize]
                    p.stroke_r = p.saved[at + 3usize]
                    p.stroke_g = p.saved[at + 4usize]
                    p.stroke_b = p.saved[at + 5usize]
                    p.line_width = p.saved[at + 6usize]
                    p.scale_x = p.saved[at + 7usize]
                    p.scale_y = p.saved[at + 8usize]
                    p.shift_x = p.saved[at + 9usize]
                    p.shift_y = p.saved[at + 10usize]
                }
            } else if str.eq(op, "cm") {
                // A scale and an offset: the new matrix applied before the one in force (b and c are not followed).
                p.shift_x = p.shift_x + o4 * p.scale_x
                p.shift_y = p.shift_y + o5 * p.scale_y
                p.scale_x = p.scale_x * o0
                p.scale_y = p.scale_y * o3
            } else if str.eq(op, "BT") {
                p.tm_x = 0.0f64
                p.tm_y = 0.0f64
                p.line_x = 0.0f64
                p.line_y = 0.0f64
                p.text_scale = 1.0f64
            } else if str.eq(op, "Tf") {
                if o5 > 0.0f64 { p.font_size = o5 }
                p.cur_font = MAX_FONTS
                if name_e > name_s {
                    let (font_object, has_font) = named_ref(p.data, p.table, p.count, p.res_s, p.res_e, "Font", content[name_s..name_e])
                    if has_font { p.cur_font = load_font(a, p, font_object) }
                }
            } else if str.eq(op, "Do") {
                if name_e > name_s { paint_xobject(a, p, content[name_s..name_e]) }
            } else if str.eq(op, "TL") {
                p.leading = o5
            } else if str.eq(op, "Td") {
                paint_move_text(p, o4, o5)
            } else if str.eq(op, "TD") {
                p.leading = -o5
                paint_move_text(p, o4, o5)
            } else if str.eq(op, "T*") {
                paint_move_text(p, 0.0f64, -p.leading)
            } else if str.eq(op, "Tm") {
                p.text_scale = o0
                if p.text_scale <= 0.0f64 { p.text_scale = 1.0f64 }
                p.line_x = o4
                p.line_y = o5
                p.tm_x = o4
                p.tm_y = o5
            } else if str.eq(op, "Tj") || str.eq(op, "TJ") {
                if has_text { paint_run(a, p, pending) }
            } else if str.eq(op, "'") || str.eq(op, "\"") {
                paint_move_text(p, 0.0f64, -p.leading)
                if has_text { paint_run(a, p, pending) }
            }
            // An operator ends its operands and its string.
            count = 0usize
            has_text = false
            pending_start = used
            i = j
        } else {
            i += 1usize
        }
    }
    ret ok
}

// The number list after `/MediaBox [` in data[from..until]: width and height, false when the page has none.
fn media_box(data: []const u8, from: usize, until: usize) -> (f64, f64, bool) {
    let key = find(data, "MediaBox", from, until)
    if key >= until { ret (0.0f64, 0.0f64, false) }
    var at = key + 8usize
    while at < until && data[at] != 91u8 { at += 1usize }
    if at >= until { ret (0.0f64, 0.0f64, false) }
    at += 1usize
    var numbers: [4]f64 = zero
    var k = 0usize
    while k < 4usize && at < until {
        while at < until && is_space(data[at]) { at += 1usize }
        var j = at
        while j < until && !is_space(data[j]) && data[j] != 93u8 { j += 1usize }
        if j == at { ret (0.0f64, 0.0f64, false) }
        numbers[k] = operand_number(data[at..j])
        at = j
        k += 1usize
    }
    if k < 4usize { ret (0.0f64, 0.0f64, false) }
    ret (numbers[2usize] - numbers[0usize], numbers[3usize] - numbers[1usize], true)
}

// Page `page` (from 0) painted: its size (the page's, or any page tree node's, MediaBox, else 612 by 792) and its
// shapes in paint order (up to MAX_SHAPES).
fn page_painting(a: *mem.Arena, data: []const u8, page: usize) -> (Painting, err) {
    let (tree, tree_error) = page_tree(a, data)
    if tree_error != ok { ret (zero, tree_error) }
    if page >= tree.page_count { ret (zero, NoPages) }
    let (ps, pe, has_page) = object_span(tree.table, tree.count, tree.page_objects[page])
    if !has_page { ret (zero, NoPages) }
    var width = 612.0f64
    var height = 792.0f64
    let (own_w, own_h, has_own) = media_box(data, ps, pe)
    if has_own {
        width = own_w
        height = own_h
    } else {
        // Inherited: the first MediaBox of any object.
        var o = 0usize
        var found = false
        while o < tree.count && !found {
            let (inherited_w, inherited_h, has_inherited) = media_box(data, tree.table[o].start, tree.table[o].end)
            if has_inherited {
                width = inherited_w
                height = inherited_h
                found = true
            }
            o += 1usize
        }
    }
    let (shapes, shapes_error) = mem.alloc[Shape](a, MAX_SHAPES)
    if shapes_error != ok { ret (zero, shapes_error) }
    var painter = paint_start(shapes)
    painter.data = data
    painter.table = tree.table
    painter.count = tree.count
    let (res_s, res_e, has_res) = resources_span(data, tree.table, tree.count, ps, pe)
    if has_res {
        painter.res_s = res_s
        painter.res_e = res_e
    }
    var streams: [64]usize = zero
    var stream_count = refs_in_array(data, ps, pe, "Contents", streams[0usize..])
    if stream_count == 0usize {
        let (single, has_single) = ref_after(data, ps, pe, "Contents")
        if has_single {
            streams[0usize] = single
            stream_count = 1usize
        }
    }
    var k = 0usize
    while k < stream_count {
        let (ss, se, has_stream) = object_span(tree.table, tree.count, streams[k])
        if has_stream {
            let (content, stream_error) = stream_of(a, data, ss, se)
            if stream_error != ok { ret (zero, stream_error) }
            let run_error = paint_content(a, &painter, content)
            if run_error != ok { ret (zero, run_error) }
        }
        k += 1usize
    }
    ret (Painting { width: width, height: height, shapes: shapes[0usize..painter.n], images: painter.images[0usize..painter.image_n] }, ok)
}

// ---- The outline (D4800): the bookmarks of a document in order, each with its depth and the page it points at.
type OutlineItem = struct { title: str, page: usize, level: usize }
const MAX_OUTLINE: usize = 64usize
// `OutlineItem.page` for a bookmark whose destination is a name or is not a page of the tree.
const NO_PAGE: usize = 4294967295usize

// The string value of `/key` in data[s..e] as UTF-8: a literal (escapes and balanced parentheses) or a hex string,
// PDFDocEncoding read as Latin-1 and UTF-16BE (a leading FE FF) converted. Empty when there is none.
fn string_after(a: *mem.Arena, data: []const u8, s: usize, e: usize, key: str) -> str {
    var at = s
    while at < e {
        if data[at] == 47u8 && at_word(data, at + 1usize, key) {
            var k = at + 1usize + key.len
            if k >= e || is_space(data[k]) || is_delim(data[k]) {
                while k < e && is_space(data[k]) { k += 1usize }
                if k >= e { ret "" }
                let (raw, raw_error) = mem.alloc[u8](a, 512usize)
                if raw_error != ok { ret "" }
                var n = 0usize
                if data[k] == 40u8 {
                    var depth = 1usize
                    k += 1usize
                    while k < e && depth > 0usize && n < 510usize {
                        let d = data[k]
                        if d == 92u8 && k + 1usize < e {
                            let c = data[k + 1usize]
                            k += 2usize
                            if c == 110u8 || c == 114u8 || c == 116u8 {
                                raw[n] = 32u8
                                n += 1usize
                            } else if c >= 48u8 && c <= 55u8 {
                                var code = usize(c - 48u8)
                                var digits = 1usize
                                while digits < 3usize && k < e && data[k] >= 48u8 && data[k] <= 55u8 {
                                    code = code * 8usize + usize(data[k] - 48u8)
                                    k += 1usize
                                    digits += 1usize
                                }
                                raw[n] = u8(code & 255usize)
                                n += 1usize
                            } else if c != 10u8 && c != 13u8 {
                                raw[n] = c
                                n += 1usize
                            }
                        } else {
                            if d == 40u8 { depth += 1usize }
                            if d == 41u8 { depth -= 1usize }
                            if depth > 0usize {
                                raw[n] = d
                                n += 1usize
                            }
                            k += 1usize
                        }
                    }
                } else if data[k] == 60u8 && !(k + 1usize < e && data[k + 1usize] == 60u8) {
                    k += 1usize
                    var high = 0usize
                    var have_high = false
                    while k < e && data[k] != 62u8 && n < 510usize {
                        let h = data[k]
                        var v = 99usize
                        if h >= 48u8 && h <= 57u8 { v = usize(h - 48u8) }
                        if h >= 65u8 && h <= 70u8 { v = usize(h - 55u8) }
                        if h >= 97u8 && h <= 102u8 { v = usize(h - 87u8) }
                        if v != 99usize {
                            if have_high {
                                raw[n] = u8(high * 16usize + v)
                                n += 1usize
                                have_high = false
                            } else {
                                high = v
                                have_high = true
                            }
                        }
                        k += 1usize
                    }
                } else {
                    ret ""
                }
                let (out, out_error) = mem.alloc[u8](a, n * 3usize + 4usize)
                if out_error != ok { ret "" }
                var o = 0usize
                var i = 0usize
                if n >= 2usize && raw[0usize] == 254u8 && raw[1usize] == 255u8 {
                    i = 2usize
                    while i + 1usize < n {
                        var unit = u32(raw[i]) * 256u32 + u32(raw[i + 1usize])
                        i += 2usize
                        if unit >= 55296u32 && unit < 56320u32 && i + 1usize < n {
                            let low = u32(raw[i]) * 256u32 + u32(raw[i + 1usize])
                            i += 2usize
                            unit = 65536u32 + ((unit - 55296u32) << 10u32) + (low - 56320u32)
                        }
                        o = put_utf8(out, o, unit)
                    }
                } else {
                    while i < n {
                        o = put_latin1(out, o, raw[i])
                        i += 1usize
                    }
                }
                ret out[0usize..o]
            }
        }
        at += 1usize
    }
    ret ""
}

// The bookmarks of the document in outline order (depth first): title, the page index it points at (NO_PAGE when its
// destination is a name or does not resolve) and its depth. Empty when the document has no outline.
fn outline(a: *mem.Arena, data: []const u8) -> ([]OutlineItem, err) {
    let (tree, tree_error) = page_tree(a, data)
    if tree_error != ok { ret (zero, tree_error) }
    let (items, items_error) = mem.alloc[OutlineItem](a, MAX_OUTLINE)
    if items_error != ok { ret (zero, items_error) }
    var root = 0usize
    var i = 0usize
    while i < tree.count && root == 0usize {
        if has_pair(data, tree.table[i].start, tree.table[i].end, "Type", "Catalog") {
            let (found_root, has_root) = ref_after(data, tree.table[i].start, tree.table[i].end, "Outlines")
            if has_root { root = found_root }
        }
        i += 1usize
    }
    if root == 0usize { ret (items[0usize..0usize], ok) }
    let (rs, re, has_span) = object_span(tree.table, tree.count, root)
    if !has_span { ret (items[0usize..0usize], ok) }
    let (first, has_first) = ref_after(data, rs, re, "First")
    if !has_first { ret (items[0usize..0usize], ok) }
    var n = 0usize
    var current = first
    var level = 0usize
    var pending: [16]usize = zero
    var running = true
    var steps = 0usize
    while running && n < MAX_OUTLINE && steps < 512usize {
        steps += 1usize
        let (s, e, found) = object_span(tree.table, tree.count, current)
        if !found {
            running = false
        } else {
            var page = NO_PAGE
            var targets: [4]usize = zero
            var t = refs_in_array(data, s, e, "Dest", targets[0usize..])
            if t == 0usize { t = refs_in_array(data, s, e, "D", targets[0usize..]) }
            if t > 0usize {
                var p = 0usize
                while p < tree.page_count {
                    if tree.page_objects[p] == targets[0usize] { page = p }
                    p += 1usize
                }
            }
            items[n] = OutlineItem { title: string_after(a, data, s, e, "Title"), page: page, level: level }
            n += 1usize
            let (child, has_child) = ref_after(data, s, e, "First")
            let (next, has_next) = ref_after(data, s, e, "Next")
            if has_child && level < 15usize {
                pending[level] = 0usize
                if has_next { pending[level] = next }
                level += 1usize
                current = child
            } else if has_next {
                current = next
            } else {
                var climbing = true
                while climbing {
                    if level == 0usize {
                        climbing = false
                        running = false
                    } else {
                        level -= 1usize
                        if pending[level] != 0usize {
                            current = pending[level]
                            climbing = false
                        }
                    }
                }
            }
        }
    }
    ret (items[0usize..n], ok)
}
