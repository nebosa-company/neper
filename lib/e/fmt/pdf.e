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
type Painting = struct { width: f64, height: f64, shapes: []Shape }
type Segment = struct { x0: f64, y0: f64, x1: f64, y1: f64 }

const SHAPE_FILL: u8 = 0u8
const SHAPE_LINE: u8 = 1u8
const SHAPE_TEXT: u8 = 2u8
const MAX_SHAPES: usize = 4000usize
const MAX_SEGMENTS: usize = 256usize
const STATE_DEPTH: usize = 8usize

// The painter: the shapes so far, the graphics state, the path under construction and the text state.
type Painter = struct { out: []Shape, n: usize, fill_r: f64, fill_g: f64, fill_b: f64, stroke_r: f64, stroke_g: f64, stroke_b: f64, line_width: f64, scale_x: f64, scale_y: f64, shift_x: f64, shift_y: f64, saved: [88]f64, depth: usize, segs: [256]Segment, seg_n: usize, rects: [64]Segment, rect_n: usize, cur_x: f64, cur_y: f64, start_x: f64, start_y: f64, tm_x: f64, tm_y: f64, line_x: f64, line_y: f64, leading: f64, font_size: f64, text_scale: f64 }

fn paint_start(out: []Shape) -> Painter {
    var p: Painter = zero
    p.out = out
    p.scale_x = 1.0f64
    p.scale_y = 1.0f64
    p.line_width = 1.0f64
    p.text_scale = 1.0f64
    p.font_size = 12.0f64
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
    paint_push(p, SHAPE_TEXT, p.tm_x, p.tm_y, p.tm_x, p.tm_y, 0.0f64, p.fill_r, p.fill_g, p.fill_b, size * p.scale_y, text)
    p.tm_x += f64(text.len) * size * 0.5f64
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
                        used = put_latin1(buffer, used, 32u8)
                    } else if e >= 48u8 && e <= 55u8 {
                        var code = usize(e - 48u8)
                        var digits = 1usize
                        while digits < 3usize && i < content.len && content[i] >= 48u8 && content[i] <= 55u8 {
                            code = code * 8usize + usize(content[i] - 48u8)
                            i += 1usize
                            digits += 1usize
                        }
                        used = put_latin1(buffer, used, u8(code & 255usize))
                    } else if e != 10u8 && e != 13u8 {
                        used = put_latin1(buffer, used, e)
                    }
                } else {
                    if d == 40u8 { depth += 1usize }
                    if d == 41u8 { depth -= 1usize }
                    if depth > 0usize { used = put_latin1(buffer, used, d) }
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
                        used = put_latin1(buffer, used, u8(high * 16usize + v))
                        have_high = false
                    } else {
                        high = v
                        have_high = true
                    }
                }
                i += 1usize
            }
            if have_high { used = put_latin1(buffer, used, u8(high * 16usize)) }
            i += 1usize
        } else if c == 91u8 {
            in_array = true
            i += 1usize
        } else if c == 93u8 {
            in_array = false
            i += 1usize
        } else if c == 47u8 {
            // A name: skipped.
            i += 1usize
            while i < content.len && !is_space(content[i]) && !is_delim(content[i]) { i += 1usize }
        } else if is_digit(c) || c == 45u8 || c == 43u8 || c == 46u8 {
            var j = i + 1usize
            while j < content.len && (is_digit(content[j]) || content[j] == 46u8) { j += 1usize }
            let value = operand_number(content[i..j])
            if in_array {
                // A kern inside TJ: a big pull back is a word space.
                if value <= -200.0f64 && has_text && used > pending_start && buffer[used - 1usize] != 32u8 { used = put_latin1(buffer, used, 32u8) }
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
                if has_text { paint_text(p, pending) }
            } else if str.eq(op, "'") || str.eq(op, "\"") {
                paint_move_text(p, 0.0f64, -p.leading)
                if has_text { paint_text(p, pending) }
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
    ret (Painting { width: width, height: height, shapes: shapes[0usize..painter.n] }, ok)
}
