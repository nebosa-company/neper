// ZIP reading: the end-of-central-directory record found from the tail of the
// source (through its ZIP64 locator when the counts are saturated), the central
// directory read once into the arena and checked against `Limits` before any entry is
// exposed, then entries read through a seek to their local header -- stored ones
// straight from the source, DEFLATE ones through `e.algo.deflate` -- with the CRC-32
// and size compared at the end. Encryption and any method but 0 and 8 are
// `Unsupported`; an absolute name, a `..` segment, a backslash or a bad signature is
// `Invalid`. Names are taken as UTF-8 as written.
//
// One entry reader at a time: it seeks the shared source. `entry_reader` needs
// `entry_storage()` bytes of 8-aligned storage; `extract` takes them from the arena.
use e.io
use e.mem
use e.str
use e.algo.deflate as deflate
use e.algo.hash as hash

type Archive = struct { state: *void }
type Entry = struct { name: str, compressed_size: u64, size: u64, method: u16, crc32: u32, directory: bool }
type Limits = struct { entries: usize, name_bytes: usize, entry_bytes: u64, total_bytes: u64 }
error Invalid
error Unsupported
error Checksum
error TooLarge

const BUFFER: usize = 4096usize
const WINDOW: usize = 32768usize
// The central directory is read whole; past this it is refused rather than streamed.
const DIRECTORY_LIMIT: u64 = 67108864u64

type State = struct { source: io.Reader, seeker: io.Seeker, entries: []Entry, offsets: []u64 }

type EntryState = struct {
    source: io.Reader,
    decoder: deflate.Decoder,
    input: []u8,
    in_at: usize,
    in_len: usize,
    compressed_left: u64,
    stored: bool,
    crc: hash.Crc32,
    expected_crc: u32,
    expected_size: u64,
    produced: u64,
    finished: bool,
    source_ended: bool,
}

fn le16(data: []const u8, at: usize) -> u32 {
    ret u32(data[at]) | (u32(data[at + 1usize]) << 8u32)
}

fn le32(data: []const u8, at: usize) -> u32 {
    ret le16(data, at) | (le16(data, at + 2usize) << 16u32)
}

fn le64(data: []const u8, at: usize) -> u64 {
    ret u64(le32(data, at)) | (u64(le32(data, at + 4usize)) << 32u32)
}

fn read_at(s: *State, offset: u64, dst: []u8) -> err {
    let (position, seek_error) = io.seek(&s.seeker, i64(offset), .Start)
    if seek_error != ok { ret seek_error }
    let exact_error = io.read_exact(&s.source, dst)
    if exact_error != ok { ret Invalid }
    ret ok
}

fn name_legal(name: str) -> bool {
    if name.len == 0usize { ret false }
    if name[0] == 47u8 { ret false }
    if name.len >= 2usize && name[1] == 58u8 { ret false }
    var at = 0usize
    while at < name.len {
        if name[at] == 92u8 { ret false }
        at += 1usize
    }
    // A `..` segment anywhere.
    at = 0usize
    while at < name.len {
        var end = at
        while end < name.len && name[end] != 47u8 { end += 1usize }
        if end - at == 2usize && name[at] == 46u8 && name[at + 1usize] == 46u8 { ret false }
        at = end + 1usize
    }
    ret true
}

fn open(a: *mem.Arena, source: io.Reader, seeker: io.Seeker, limits: Limits) -> (Archive, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let s = &storage[0]
    s.source = source
    s.seeker = seeker
    // The tail: the record, at most 65535 bytes of comment, and the ZIP64 locator.
    let (size, size_error) = io.seek(&s.seeker, 0i64, .End)
    if size_error != ok { ret (zero, size_error) }
    if size < 22u64 { ret (zero, Invalid) }
    var tail_len = 65557u64 + 20u64
    if tail_len > size { tail_len = size }
    let (tail, tail_error) = mem.alloc[u8](a, usize(tail_len))
    if tail_error != ok { ret (zero, tail_error) }
    let read_error_102 = read_at(s, size - tail_len, tail)
    if read_error_102 != ok { ret (zero, read_error_102) }
    var at = tail.len - 22usize
    var found = false
    while true {
        if le32(tail, at) == 101010256u32 {
            let comment_len = usize(le16(tail, at + 20usize))
            if at + 22usize + comment_len == tail.len {
                found = true
                break
            }
        }
        if at == 0usize { break }
        at -= 1usize
    }
    if !found { ret (zero, Invalid) }
    var count = u64(le16(tail, at + 10usize))
    var directory_size = u64(le32(tail, at + 12usize))
    var directory_offset = u64(le32(tail, at + 16usize))
    if count == 65535u64 || directory_size == 4294967295u64 || directory_offset == 4294967295u64 {
        if at < 20usize || le32(tail, at - 20usize) != 117853008u32 { ret (zero, Invalid) }
        let record_offset = le64(tail, at - 12usize)
        var record: [56]u8 = zero
        let read_error_125 = read_at(s, record_offset, record[0..])
        if read_error_125 != ok { ret (zero, read_error_125) }
        if le32(record[0..], 0usize) != 101075792u32 { ret (zero, Invalid) }
        count = le64(record[0..], 32usize)
        directory_size = le64(record[0..], 40usize)
        directory_offset = le64(record[0..], 48usize)
    }
    if count > u64(limits.entries) { ret (zero, TooLarge) }
    if directory_size > DIRECTORY_LIMIT || directory_offset + directory_size > size { ret (zero, TooLarge) }
    let (directory, directory_error) = mem.alloc[u8](a, usize(directory_size))
    if directory_error != ok { ret (zero, directory_error) }
    let read_error_136 = read_at(s, directory_offset, directory)
    if read_error_136 != ok { ret (zero, read_error_136) }
    let (table, table_error) = mem.alloc[Entry](a, usize(count))
    if table_error != ok { ret (zero, table_error) }
    let (offsets, offsets_error) = mem.alloc[u64](a, usize(count))
    if offsets_error != ok { ret (zero, offsets_error) }
    var total = 0u64
    var index = 0usize
    at = 0usize
    while index < usize(count) {
        if at + 46usize > directory.len { ret (zero, Invalid) }
        if le32(directory, at) != 33639248u32 { ret (zero, Invalid) }
        let flags = le16(directory, at + 8usize)
        let method = le16(directory, at + 10usize)
        var entry: Entry = zero
        entry.crc32 = le32(directory, at + 16usize)
        entry.compressed_size = u64(le32(directory, at + 20usize))
        entry.size = u64(le32(directory, at + 24usize))
        let name_len = usize(le16(directory, at + 28usize))
        let extra_len = usize(le16(directory, at + 30usize))
        let comment_len = usize(le16(directory, at + 32usize))
        var offset = u64(le32(directory, at + 42usize))
        if at + 46usize + name_len + extra_len + comment_len > directory.len { ret (zero, Invalid) }
        if flags & 1u32 != 0u32 { ret (zero, Unsupported) }
        if method != 0u32 && method != 8u32 { ret (zero, Unsupported) }
        entry.method = u16(method)
        if name_len > limits.name_bytes { ret (zero, TooLarge) }
        entry.name = directory[at + 46usize..at + 46usize + name_len]
        if !name_legal(entry.name) { ret (zero, Invalid) }
        entry.directory = entry.name[entry.name.len - 1usize] == 47u8
        // The ZIP64 extra field carries whichever of the three were saturated, in order.
        var extra_at = at + 46usize + name_len
        let extra_end = extra_at + extra_len
        while extra_at + 4usize <= extra_end {
            let id = le16(directory, extra_at)
            let field_len = usize(le16(directory, extra_at + 2usize))
            if extra_at + 4usize + field_len > extra_end { ret (zero, Invalid) }
            if id == 1u32 {
                var field_at = extra_at + 4usize
                let field_end = field_at + field_len
                if entry.size == 4294967295u64 {
                    if field_at + 8usize > field_end { ret (zero, Invalid) }
                    entry.size = le64(directory, field_at)
                    field_at += 8usize
                }
                if entry.compressed_size == 4294967295u64 {
                    if field_at + 8usize > field_end { ret (zero, Invalid) }
                    entry.compressed_size = le64(directory, field_at)
                    field_at += 8usize
                }
                if offset == 4294967295u64 {
                    if field_at + 8usize > field_end { ret (zero, Invalid) }
                    offset = le64(directory, field_at)
                }
            }
            extra_at += 4usize + field_len
        }
        if entry.size > limits.entry_bytes { ret (zero, TooLarge) }
        total += entry.size
        if total > limits.total_bytes { ret (zero, TooLarge) }
        if offset >= size { ret (zero, Invalid) }
        table[index] = entry
        offsets[index] = offset
        at += 46usize + name_len + extra_len + comment_len
        index += 1usize
    }
    s.entries = table
    s.offsets = offsets
    var archive: Archive = zero
    archive.state = mem.cast[*void](s)
    ret (archive, ok)
}

fn entries(archive: *const Archive) -> []const Entry {
    let s = mem.cast[*State](archive.state)
    ret s.entries[0..]
}

fn entry_storage() -> usize {
    let (window_size, window_error) = deflate.decoder_storage(WINDOW)
    let head = mem.size_of[EntryState]() + 7usize
    ret head / 8usize * 8usize + BUFFER + window_size
}

fn entry_reader(storage: []u8, archive: *Archive, index: usize) -> (io.Reader, err) {
    let s = mem.cast[*State](archive.state)
    if index >= s.entries.len { ret (zero, Invalid) }
    if storage.len < entry_storage() { ret (zero, io.TooSmall) }
    let entry = s.entries[index]
    // The local header: its own name and extra lengths, then the data.
    var header: [30]u8 = zero
    let header_error = read_at(s, s.offsets[index], header[0..])
    if header_error != ok { ret (zero, header_error) }
    if le32(header[0..], 0usize) != 67324752u32 { ret (zero, Invalid) }
    let skip = u64(le16(header[0..], 26usize)) + u64(le16(header[0..], 28usize))
    let (position, seek_error) = io.seek(&s.seeker, i64(s.offsets[index] + 30u64 + skip), .Start)
    if seek_error != ok { ret (zero, seek_error) }
    let e = mem.cast[*EntryState](&storage[0])
    let blank: EntryState = zero
    *e = blank
    let head = mem.size_of[EntryState]() + 7usize
    var at = head / 8usize * 8usize
    e.input = storage[at..at + BUFFER]
    at += BUFFER
    let (d, d_error) = deflate.decoder(storage[at..], WINDOW)
    if d_error != ok { ret (zero, d_error) }
    e.decoder = d
    e.source = s.source
    e.in_at = 0usize
    e.in_len = 0usize
    e.compressed_left = entry.compressed_size
    e.stored = entry.method == 0u16
    e.crc = hash.crc32_init()
    e.expected_crc = entry.crc32
    e.expected_size = entry.size
    e.produced = 0u64
    e.finished = false
    e.source_ended = false
    ret (io.Reader { ctx: mem.cast[*void](e), read: entry_read }, ok)
}

// Fills the input buffer with the next compressed bytes, bounded by what the entry has.
fn fill(e: *EntryState) -> err {
    if e.compressed_left == 0u64 {
        e.source_ended = true
        ret ok
    }
    var want = e.input.len
    if u64(want) > e.compressed_left { want = usize(e.compressed_left) }
    let (count, read_error) = io.read(&e.source, e.input[..want])
    if read_error == io.End || (read_error == ok && count == 0usize) { ret Invalid }
    if read_error != ok { ret read_error }
    e.in_at = 0usize
    e.in_len = count
    e.compressed_left -= u64(count)
    ret ok
}

fn entry_finish(e: *EntryState) -> err {
    e.finished = true
    if e.produced != e.expected_size { ret Checksum }
    if hash.crc32_done(&e.crc) != e.expected_crc { ret Checksum }
    ret io.End
}

fn entry_read(ctx: *void, dst: []u8) -> (usize, err) {
    let e = mem.cast[*EntryState](ctx)
    if e.finished { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    if e.stored {
        if e.compressed_left == 0u64 { ret (0usize, entry_finish(e)) }
        var want = dst.len
        if u64(want) > e.compressed_left { want = usize(e.compressed_left) }
        let (count, read_error) = io.read(&e.source, dst[..want])
        if read_error == io.End || (read_error == ok && count == 0usize) { ret (0usize, Invalid) }
        if read_error != ok { ret (0usize, read_error) }
        e.compressed_left -= u64(count)
        e.produced += u64(count)
        hash.crc32_update(&e.crc, dst[..count])
        ret (count, ok)
    }
    while true {
        if e.in_at == e.in_len && !e.source_ended {
            let fill_error = fill(e)
            if fill_error != ok { ret (0usize, fill_error) }
        }
        let (consumed, written, status, decode_error) = deflate.decode(&e.decoder, e.input[e.in_at..e.in_len], dst, e.source_ended)
        if decode_error != ok { ret (0usize, Invalid) }
        e.in_at += consumed
        if written > 0usize {
            e.produced += u64(written)
            if e.produced > e.expected_size { ret (0usize, Checksum) }
            hash.crc32_update(&e.crc, dst[..written])
        }
        if status == .Finished {
            if written > 0usize {
                // The trailer check waits for the next call, which answers End.
                e.compressed_left = 0u64
                e.source_ended = true
                e.finished = e.produced == e.expected_size && hash.crc32_done(&e.crc) == e.expected_crc
                if !e.finished { ret (0usize, Checksum) }
                ret (written, ok)
            }
            ret (0usize, entry_finish(e))
        }
        if written > 0usize { ret (written, ok) }
    }
}

fn extract(a: *mem.Arena, archive: *Archive, index: usize) -> ([]u8, err) {
    let s = mem.cast[*State](archive.state)
    if index >= s.entries.len { ret (zero, Invalid) }
    let entry = s.entries[index]
    // Reader storage as u64s for the alignment the state cast needs, viewed as bytes.
    let words = entry_storage() / 8usize + 1usize
    let (aligned, storage_error) = mem.alloc[u64](a, words)
    if storage_error != ok { ret (zero, storage_error) }
    let storage = mem.view(a, a.off - words * 8usize, words * 8usize)
    let (out, out_error) = mem.alloc[u8](a, usize(entry.size))
    if out_error != ok { ret (zero, out_error) }
    let (r0, reader_error) = entry_reader(storage, archive, index)
    if reader_error != ok { ret (zero, reader_error) }
    var r = r0
    var filled = 0usize
    while true {
        if filled == out.len {
            // Only the end may follow.
            var none: [1]u8 = zero
            let (extra, end_error) = io.read(&r, none[0..])
            if end_error == io.End { break }
            if end_error != ok { ret (zero, end_error) }
            if extra > 0usize { ret (zero, Checksum) }
            continue
        }
        let (count, read_error) = io.read(&r, out[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        filled += count
    }
    if filled != out.len { ret (zero, Checksum) }
    ret (out, ok)
}
