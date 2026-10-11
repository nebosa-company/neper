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

// Decode the stream of object span [s, e): its bytes, `/FlateDecode` undone. (The raw span when it has no
// filter, an empty result when the stream is missing or does not inflate.)
fn stream_of(a: *mem.Arena, data: []const u8, s: usize, e: usize) -> ([]const u8, err) {
    let keyword = find(data, "stream", s, e)
    if keyword >= e { ret (data[s..s], ok) }
    var from = keyword + 6usize
    if from < e && data[from] == 13u8 { from += 1usize }
    if from < e && data[from] == 10u8 { from += 1usize }
    var until = find(data, "endstream", from, e)
    // Trim the end-of-line before `endstream`.
    if until > from && data[until - 1usize] == 10u8 { until -= 1usize }
    if until > from && data[until - 1usize] == 13u8 { until -= 1usize }
    let raw = data[from..until]
    let flate = find(data, "FlateDecode", s, keyword)
    if flate >= keyword { ret (raw, ok) }
    let (storage, storage_error) = mem.alloc[u8](a, zlib.storage_required(.Fast))
    if storage_error != ok { ret (raw, storage_error) }
    var cell = Mem { data: raw, off: 0usize }
    let reader = io.Reader { ctx: mem.cast[*void](&cell), read: mem_read }
    let (z, z_error) = zlib.reader(storage, reader, MAX_STREAM)
    if z_error != ok { ret (raw[0usize..0usize], ok) }
    var zr = z
    let (out, out_error) = mem.alloc[u8](a, 262144usize)
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

fn newline(out: []u8, at: usize) -> usize {
    if at == 0usize || at + 1usize > out.len { ret at }
    if out[at - 1usize] == 10u8 { ret at }
    out[at] = 10u8
    ret at + 1usize
}

// The text a content stream paints, as lines.
fn text_of(a: *mem.Arena, content: []const u8) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, content.len * 2usize + 16usize)
    if out_error != ok { ret ("", out_error) }
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
                        at = put_latin1(out, at, u8(code & 255usize))
                    } else if e == 10u8 || e == 13u8 {
                        at += 0usize
                    } else {
                        at = put_latin1(out, at, e)
                    }
                } else {
                    if d == 40u8 { depth += 1usize }
                    if d == 41u8 { depth -= 1usize }
                    if depth > 0usize {
                        at = put_latin1(out, at, d)
                    }
                    i += 1usize
                }
            }
        } else if c == 60u8 && i + 1usize < content.len && content[i + 1usize] != 60u8 {
            // A hex string.
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
                        at = put_latin1(out, at, u8(high * 16usize + v))
                        have_high = false
                    } else {
                        high = v
                        have_high = true
                    }
                }
                i += 1usize
            }
            if have_high { at = put_latin1(out, at, u8(high * 16usize)) }
            i += 1usize
        } else if c == 91u8 {
            in_array = true
            i += 1usize
        } else if c == 93u8 {
            in_array = false
            i += 1usize
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

// The text of each page of a PDF held in `data`, in page-tree order.
fn pages(a: *mem.Arena, data: []const u8) -> ([]str, err) {
    if !at_word(data, 0usize, "%PDF-") && find(data, "%PDF-", 0usize, 1024usize) >= 1024usize { ret (zero, NotPdf) }
    let (table, count, objects_error) = objects(a, data)
    if objects_error != ok { ret (zero, objects_error) }
    let (page_objects, po_error) = mem.alloc[usize](a, MAX_PAGES)
    if po_error != ok { ret (zero, po_error) }
    var page_count = 0usize
    // The catalog's page tree.
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
    // No usable tree: every page object in file order.
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
    let (out, out_error) = mem.alloc[str](a, page_count)
    if out_error != ok { ret (zero, out_error) }
    var p = 0usize
    while p < page_count {
        let (ps, pe, has_page) = object_span(table, count, page_objects[p])
        var combined = ""
        if has_page {
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
                    let (text, text_error) = text_of(a, content)
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
