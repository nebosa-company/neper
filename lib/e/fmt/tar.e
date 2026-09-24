// A tar reader: POSIX ustar headers, with the PAX extended records `path`, `linkpath`
// and `size` applied to the entry that follows them. Each entry's content is an
// `io.Reader` limited to its size; the reader must be drained or `skip`ped before
// `next`, which also steps over the padding to the next 512-byte block. Absolute names,
// Windows paths and `..` segments are `Invalid` for entries and links; every entry type
// but a file, a directory and the
// two links is `Unsupported`; `entry_limit` and `byte_limit` bound what a hostile
// archive can make the reader do.

use e.io
use e.mem

type Reader = struct { state: *void }
type Entry = struct { name: str, size: u64, kind: u8, mode: u32, modified: i64, link: str }
error Invalid
error Unsupported
error TooLarge

type State = struct {
    arena: *mem.Arena,
    source: io.Reader,
    entry_limit: usize,
    byte_limit: u64,
    entries: usize,
    bytes: u64,
    remaining: u64,
    padding: u64,
    content: io.LimitedReader,
    pax_path: str,
    pax_link: str,
    pax_size: u64,
    has_pax_size: bool,
    finished: bool,
}

fn reader(a: *mem.Arena, source: io.Reader, entry_limit: usize, byte_limit: u64) -> (Reader, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    var s = &storage[0]
    s.arena = a
    s.source = source
    s.entry_limit = entry_limit
    s.byte_limit = byte_limit
    s.entries = 0usize
    s.bytes = 0u64
    s.remaining = 0u64
    s.padding = 0u64
    s.pax_path = ""
    s.pax_link = ""
    s.pax_size = 0u64
    s.has_pax_size = false
    s.finished = false
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// An octal field, space- or NUL-terminated; a leading 0x80 marks the base-256 form
// of large sizes, read big-endian from the rest.
fn octal(field: []const u8) -> (u64, bool) {
    if field.len > 0usize && field[0] == 128u8 {
        var value = 0u64
        var at = 1usize
        while at < field.len {
            value = (value << 8u32) | u64(field[at])
            at += 1usize
        }
        ret (value, true)
    }
    var value = 0u64
    var at = 0usize
    var digits = 0usize
    while at < field.len && (field[at] == 32u8 || field[at] == 0u8) { at += 1usize }
    while at < field.len {
        let c = field[at]
        if c == 32u8 || c == 0u8 { break }
        if c < 48u8 || c > 55u8 { ret (0u64, false) }
        value = value * 8u64 + u64(c - 48u8)
        digits += 1usize
        at += 1usize
    }
    ret (value, digits > 0usize)
}

fn text_field(field: []const u8) -> str {
    var end = 0usize
    while end < field.len && field[end] != 0u8 { end += 1usize }
    ret field[..end]
}

fn is_empty_block(block: []const u8) -> bool {
    var at = 0usize
    while at < block.len {
        if block[at] != 0u8 { ret false }
        at += 1usize
    }
    ret true
}

fn drain(s: *State, count: u64) -> err {
    var left = count
    var sink: [512]u8 = zero
    while left > 0u64 {
        var take = 512usize
        if u64(take) > left { take = usize(left) }
        let read_error = io.read_exact(&s.source, sink[..take])
        if read_error != ok { ret read_error }
        left -= u64(take)
    }
    ret ok
}

fn name_allowed(name: str) -> bool {
    if name.len == 0usize { ret true }
    if name[0] == 47u8 || name[0] == 92u8 { ret false }
    var at = 0usize
    while at <= name.len {
        var end = at
        while end < name.len && name[end] != 47u8 && name[end] != 92u8 { end += 1usize }
        if end - at > 1usize && name[at + 1usize] == 58u8 { ret false }
        if end - at == 2usize && name[at] == 46u8 && name[at + 1usize] == 46u8 { ret false }
        at = end + 1usize
    }
    ret true
}

fn copy_text(a: *mem.Arena, text: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, text.len)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    while at < text.len {
        out[at] = text[at]
        at += 1usize
    }
    ret (out[0..], ok)
}

// `<length> <keyword>=<value>\n` records; only the three keywords a reader needs.
fn apply_pax(s: *State, block: []const u8) -> err {
    var at = 0usize
    while at < block.len {
        var length = 0usize
        var digits = 0usize
        while at < block.len && block[at] >= 48u8 && block[at] <= 57u8 {
            length = length * 10usize + usize(block[at] - 48u8)
            digits += 1usize
            at += 1usize
        }
        if digits == 0usize || at >= block.len || block[at] != 32u8 { ret Invalid }
        let record_start = at - digits
        if length < digits + 2usize || record_start + length > block.len { ret Invalid }
        let record_end = record_start + length
        if block[record_end - 1usize] != 10u8 { ret Invalid }
        let body = block[at + 1usize..record_end - 1usize]
        var eq = 0usize
        while eq < body.len && body[eq] != 61u8 { eq += 1usize }
        if eq >= body.len { ret Invalid }
        let keyword = body[..eq]
        let value = body[eq + 1usize..]
        if same(keyword, "path") {
            let (copied, copy_error) = copy_text(s.arena, value)
            if copy_error != ok { ret copy_error }
            s.pax_path = copied
        }
        if same(keyword, "linkpath") {
            let (copied, copy_error) = copy_text(s.arena, value)
            if copy_error != ok { ret copy_error }
            s.pax_link = copied
        }
        if same(keyword, "size") {
            var size = 0u64
            var v = 0usize
            if value.len == 0usize { ret Invalid }
            while v < value.len {
                if value[v] < 48u8 || value[v] > 57u8 { ret Invalid }
                size = size * 10u64 + u64(value[v] - 48u8)
                v += 1usize
            }
            s.pax_size = size
            s.has_pax_size = true
        }
        at = record_end
    }
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

// The next entry: `false` at the end-of-archive marker or a clean end of the source.
fn next(r: *Reader) -> (Entry, bool, err) {
    let s = mem.cast[*State](r.state)
    if s.finished { ret (zero, false, ok) }
    // Whatever of the last entry was not read, and its padding.
    let leftover = s.remaining + s.padding
    if leftover > 0u64 {
        let drain_error = drain(s, leftover)
        if drain_error != ok { ret (zero, false, drain_error) }
        s.remaining = 0u64
        s.padding = 0u64
    }
    var header: [512]u8 = zero
    while true {
        let (first, first_error) = io.read(&s.source, header[0..])
        if first_error == io.End {
            s.finished = true
            ret (zero, false, ok)
        }
        if first_error != ok { ret (zero, false, first_error) }
        if first < 512usize {
            let rest_error = io.read_exact(&s.source, header[first..])
            if rest_error != ok { ret (zero, false, Invalid) }
        }
        if is_empty_block(header[0..]) {
            s.finished = true
            ret (zero, false, ok)
        }
        // Checksum: the field itself counts as eight spaces.
        var total = 0u64
        var at = 0usize
        while at < 512usize {
            if at >= 148usize && at < 156usize { total += 32u64 } else { total += u64(header[at]) }
            at += 1usize
        }
        let (stated, checksum_valid) = octal(header[148..156])
        if !checksum_valid || stated != total { ret (zero, false, Invalid) }
        let (size, size_valid) = octal(header[124..136])
        if !size_valid { ret (zero, false, Invalid) }
        let kind = header[156]
        let padding = (512u64 - size % 512u64) % 512u64
        // A PAX header applies to the next entry; a global one is skipped.
        if kind == 120u8 || kind == 103u8 {
            if size > 65536u64 { ret (zero, false, TooLarge) }
            let (block, block_error) = mem.alloc[u8](s.arena, usize(size))
            if block_error != ok { ret (zero, false, block_error) }
            let read_error = io.read_exact(&s.source, block)
            if read_error != ok { ret (zero, false, Invalid) }
            let drain_error = drain(s, padding)
            if drain_error != ok { ret (zero, false, drain_error) }
            if kind == 120u8 {
                let pax_error = apply_pax(s, block)
                if pax_error != ok { ret (zero, false, pax_error) }
            }
        } else {
            s.entries += 1usize
            if s.entries > s.entry_limit { ret (zero, false, TooLarge) }
            var e: Entry = zero
            e.kind = kind
            if kind == 0u8 { e.kind = 48u8 }
            if e.kind != 48u8 && e.kind != 53u8 && e.kind != 49u8 && e.kind != 50u8 { ret (zero, false, Unsupported) }
            var name = text_field(header[0..100])
            let prefix = text_field(header[345..500])
            let is_ustar = header[257] == 117u8 && header[258] == 115u8 && header[259] == 116u8 && header[260] == 97u8 && header[261] == 114u8
            if is_ustar && prefix.len > 0usize && s.pax_path.len == 0usize {
                let (joined, joined_error) = mem.alloc[u8](s.arena, prefix.len + 1usize + name.len)
                if joined_error != ok { ret (zero, false, joined_error) }
                var copy = 0usize
                while copy < prefix.len {
                    joined[copy] = prefix[copy]
                    copy += 1usize
                }
                joined[prefix.len] = 47u8
                copy = 0usize
                while copy < name.len {
                    joined[prefix.len + 1usize + copy] = name[copy]
                    copy += 1usize
                }
                name = joined[0..]
            } else {
                let (copied, copy_error) = copy_text(s.arena, name)
                if copy_error != ok { ret (zero, false, copy_error) }
                name = copied
            }
            if s.pax_path.len > 0usize { name = s.pax_path }
            var link = text_field(header[157..257])
            let (copied_link, link_error) = copy_text(s.arena, link)
            if link_error != ok { ret (zero, false, link_error) }
            link = copied_link
            if s.pax_link.len > 0usize { link = s.pax_link }
            if !name_allowed(name) { ret (zero, false, Invalid) }
            if (e.kind == 49u8 || e.kind == 50u8) && !name_allowed(link) { ret (zero, false, Invalid) }
            e.name = name
            e.link = link
            e.size = size
            if s.has_pax_size { e.size = s.pax_size }
            let (mode, mode_valid) = octal(header[100..108])
            let (modified, modified_valid) = octal(header[136..148])
            if !mode_valid || !modified_valid { ret (zero, false, Invalid) }
            e.mode = u32(mode)
            e.modified = i64(modified)
            if e.kind != 48u8 { e.size = 0u64 }
            s.bytes += e.size
            if s.bytes > s.byte_limit { ret (zero, false, TooLarge) }
            s.remaining = e.size
            s.padding = (512u64 - e.size % 512u64) % 512u64
            s.pax_path = ""
            s.pax_link = ""
            s.has_pax_size = false
            ret (e, true, ok)
        }
    }
    ret (zero, false, Invalid)
}

// The current entry's content, limited to its size; reading it advances the archive.
fn content(r: *Reader) -> io.Reader {
    let s = mem.cast[*State](r.state)
    ret io.limited_reader(&s.content, io.Reader { ctx: mem.cast[*void](s), read: content_read }, s.remaining)
}

fn content_read(ctx: *void, dst: []u8) -> (usize, err) {
    let s = mem.cast[*State](ctx)
    if s.remaining == 0u64 { ret (0usize, io.End) }
    var take = dst.len
    if u64(take) > s.remaining { take = usize(s.remaining) }
    let (count, read_error) = io.read(&s.source, dst[..take])
    if read_error != ok { ret (count, read_error) }
    s.remaining -= u64(count)
    ret (count, ok)
}

fn skip(r: *Reader) -> err {
    let s = mem.cast[*State](r.state)
    let drain_error = drain(s, s.remaining + s.padding)
    s.remaining = 0u64
    s.padding = 0u64
    ret drain_error
}
