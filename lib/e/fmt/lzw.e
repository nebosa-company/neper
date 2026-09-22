// LZW with variable-width codes, as GIF (least-significant bit first) and TIFF
// (most-significant bit first) use it: a clear code and an end code after the
// literals, codes widening at each power of two up to 12 bits, and a clear emitted
// when the table is full. The bit order and the literal width are both explicit, so a
// stream of one kind cannot be read as the other.
//
// ponytail: the writer's dictionary is a hash of (prefix, byte) probed linearly and
// cleared with the table; the reader's is a prefix chain walked backwards into a
// stack. Both live in the caller's storage after a state record, which is why
// `storage_required` exists. TIFF's off-by-one early change is not applied: this is
// the GIF discipline for both orders, and a TIFF reader that needs the early change
// is a parameter away.

use e.io
use e.mem

type Order = enum u8 { LeastSignificant, MostSignificant }
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid
error TooLarge

const MAX_WIDTH: u32 = 12u32
const TABLE: usize = 4096usize
// The writer's hash table: enough for 4096 entries at a load below one half.
const HASH: usize = 8192usize

type ReaderState = struct { source: io.Reader, order: Order, literal_width: u32, width: u32, clear: u32, end: u32, next: u32, previous: u32, has_previous: bool, bits: u64, bit_count: u32, output_limit: u64, produced: u64, finished: bool, prefix: []u8, suffix: []u8, stack: []u8, stack_len: usize, first_of: []u8 }

type WriterState = struct { sink: io.Writer, order: Order, literal_width: u32, width: u32, clear: u32, end: u32, next: u32, current: u32, has_current: bool, bits: u64, bit_count: u32, started: bool, keys: []u8, values: []u8 }

// The tables live in byte storage, two or four bytes an entry, little-endian.
fn get16(table: []const u8, index: usize) -> u32 {
    ret u32(table[index * 2usize]) | (u32(table[index * 2usize + 1usize]) << 8u32)
}

fn set16(table: []u8, index: usize, value: u32) {
    table[index * 2usize] = u8(value & 255u32)
    table[index * 2usize + 1usize] = u8((value >> 8u32) & 255u32)
}

fn get32(table: []const u8, index: usize) -> u32 {
    let low = u32(table[index * 4usize]) | (u32(table[index * 4usize + 1usize]) << 8u32)
    let high = u32(table[index * 4usize + 2usize]) | (u32(table[index * 4usize + 3usize]) << 8u32)
    ret low | (high << 16u32)
}

fn set32(table: []u8, index: usize, value: u32) {
    table[index * 4usize] = u8(value & 255u32)
    table[index * 4usize + 1usize] = u8((value >> 8u32) & 255u32)
    table[index * 4usize + 2usize] = u8((value >> 16u32) & 255u32)
    table[index * 4usize + 3usize] = u8(value >> 24u32)
}

fn storage_required(literal_width: u8) -> (usize, err) {
    if literal_width < 1u8 || literal_width > 8u8 { ret (0usize, Invalid) }
    // The larger of the two states, plus every table either needs.
    var reader_size = mem.size_of[ReaderState]() + TABLE * 2usize + TABLE + TABLE + TABLE
    var writer_size = mem.size_of[WriterState]() + HASH * 4usize + HASH * 2usize
    if writer_size > reader_size { ret (writer_size, ok) }
    ret (reader_size, ok)
}

fn reader(storage: []u8, source: io.Reader, order: Order, literal_width: u8, output_limit: u64) -> (Reader, err) {
    if literal_width < 1u8 || literal_width > 8u8 { ret (zero, Invalid) }
    let (needed, needed_error) = storage_required(literal_width)
    if needed_error != ok { ret (zero, needed_error) }
    if storage.len < needed { ret (zero, io.TooSmall) }
    let s = mem.cast[*ReaderState](&storage[0])
    var at = mem.size_of[ReaderState]()
    s.source = source
    s.order = order
    s.literal_width = u32(literal_width)
    s.clear = 1u32 << u32(literal_width)
    s.end = s.clear + 1u32
    s.width = u32(literal_width) + 1u32
    s.next = s.end + 1u32
    s.has_previous = false
    s.bits = 0u64
    s.bit_count = 0u32
    s.output_limit = output_limit
    s.produced = 0u64
    s.finished = false
    s.prefix = storage[at..at + TABLE * 2usize]
    at += TABLE * 2usize
    s.suffix = storage[at..at + TABLE]
    at += TABLE
    s.stack = storage[at..at + TABLE]
    at += TABLE
    s.first_of = storage[at..at + TABLE]
    s.stack_len = 0usize
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// The next code of the current width, or `false` at a clean end of the source.
fn read_code(s: *ReaderState) -> (u32, bool, err) {
    while s.bit_count < s.width {
        var byte: [1]u8 = zero
        let (count, read_error) = io.read(&s.source, byte[0..])
        if read_error == io.End { ret (0u32, false, ok) }
        if read_error != ok { ret (0u32, false, read_error) }
        if count == 0usize { ret (0u32, false, Invalid) }
        if s.order == .LeastSignificant {
            s.bits = s.bits | (u64(byte[0]) << s.bit_count)
        } else {
            s.bits = (s.bits << 8u32) | u64(byte[0])
        }
        s.bit_count += 8u32
    }
    var code = 0u32
    if s.order == .LeastSignificant {
        code = u32(s.bits & ((1u64 << s.width) - 1u64))
        s.bits = s.bits >> s.width
    } else {
        code = u32((s.bits >> (s.bit_count - s.width)) & ((1u64 << s.width) - 1u64))
        s.bits = s.bits & ((1u64 << (s.bit_count - s.width)) - 1u64)
    }
    s.bit_count -= s.width
    ret (code, true, ok)
}

// Pushes a code's string onto the stack, last byte first, and says what its first
// byte is.
fn expand(s: *ReaderState, code: u32) -> u8 {
    var at = code
    s.stack_len = 0usize
    while at >= s.clear {
        s.stack[s.stack_len] = s.suffix[usize(at)]
        s.stack_len += 1usize
        at = get16(s.prefix, usize(at))
    }
    s.stack[s.stack_len] = u8(at)
    s.stack_len += 1usize
    ret u8(at)
}

fn read(source_reader: *Reader, dst: []u8) -> (usize, err) {
    if source_reader.state == nil { ret (0usize, Invalid) }
    let s = mem.cast[*ReaderState](source_reader.state)
    var written = 0usize
    while written < dst.len {
        // Drain the stack first: the string of the last code, in order.
        if s.stack_len > 0usize {
            s.stack_len -= 1usize
            dst[written] = s.stack[s.stack_len]
            written += 1usize
            s.produced += 1u64
            if s.produced > s.output_limit { ret (written, TooLarge) }
        } else {
            if s.finished {
                if written == 0usize { ret (0usize, io.End) }
                ret (written, ok)
            }
            let (code, has_code, code_error) = read_code(s)
            if code_error != ok { ret (written, code_error) }
            if !has_code {
                s.finished = true
                if written == 0usize { ret (0usize, io.End) }
                ret (written, ok)
            }
            if code == s.clear {
                s.width = s.literal_width + 1u32
                s.next = s.end + 1u32
                s.has_previous = false
            } else {
                if code == s.end {
                    s.finished = true
                } else {
                    if code > s.next { ret (written, Invalid) }
                    var first = 0u8
                    if code < s.next {
                        first = expand(s, code)
                    } else {
                        // The KwKwK case: the previous string plus its own first byte.
                        if !s.has_previous { ret (written, Invalid) }
                        let previous_first = s.first_of[usize(s.previous)]
                        first = expand(s, s.previous)
                        // The stack holds previous last-first; the new string ends with previous_first.
                        var shift = s.stack_len
                        while shift > 0usize {
                            s.stack[shift] = s.stack[shift - 1usize]
                            shift -= 1usize
                        }
                        s.stack[0] = previous_first
                        s.stack_len += 1usize
                    }
                    if s.has_previous && s.next < u32(TABLE) {
                        set16(s.prefix, usize(s.next), s.previous)
                        s.suffix[usize(s.next)] = first
                        s.first_of[usize(s.next)] = s.first_of[usize(s.previous)]
                        s.next += 1u32
                        if s.next == (1u32 << s.width) && s.width < MAX_WIDTH { s.width += 1u32 }
                    }
                    if code < s.clear { s.first_of[usize(code)] = u8(code) }
                    s.previous = code
                    s.has_previous = true
                }
            }
        }
    }
    ret (written, ok)
}

fn writer(storage: []u8, sink: io.Writer, order: Order, literal_width: u8) -> (Writer, err) {
    if literal_width < 1u8 || literal_width > 8u8 { ret (zero, Invalid) }
    let (needed, needed_error) = storage_required(literal_width)
    if needed_error != ok { ret (zero, needed_error) }
    if storage.len < needed { ret (zero, io.TooSmall) }
    let s = mem.cast[*WriterState](&storage[0])
    var at = mem.size_of[WriterState]()
    s.sink = sink
    s.order = order
    s.literal_width = u32(literal_width)
    s.clear = 1u32 << u32(literal_width)
    s.end = s.clear + 1u32
    s.width = u32(literal_width) + 1u32
    s.next = s.end + 1u32
    s.has_current = false
    s.bits = 0u64
    s.bit_count = 0u32
    s.started = false
    s.keys = storage[at..at + HASH * 4usize]
    at += HASH * 4usize
    s.values = storage[at..at + HASH * 2usize]
    clear_table(s)
    var w: Writer = zero
    w.state = mem.cast[*void](s)
    ret (w, ok)
}

fn clear_table(s: *WriterState) {
    var at = 0usize
    while at < HASH {
        set32(s.keys, at, 4294967295u32)
        at += 1usize
    }
    s.next = s.end + 1u32
    s.width = s.literal_width + 1u32
}

fn emit(s: *WriterState, code: u32) -> err {
    if s.order == .LeastSignificant {
        s.bits = s.bits | (u64(code) << s.bit_count)
    } else {
        s.bits = (s.bits << s.width) | u64(code)
    }
    s.bit_count += s.width
    while s.bit_count >= 8u32 {
        var byte: [1]u8 = zero
        if s.order == .LeastSignificant {
            byte[0] = u8(s.bits & 255u64)
            s.bits = s.bits >> 8u32
        } else {
            byte[0] = u8((s.bits >> (s.bit_count - 8u32)) & 255u64)
            s.bits = s.bits & ((1u64 << (s.bit_count - 8u32)) - 1u64)
        }
        s.bit_count -= 8u32
        try io.write_all(&s.sink, byte[0..])
    }
    ret ok
}

fn slot_of(s: *WriterState, key: u32) -> usize {
    var at = usize((key *% 2654435761u32) >> 19u32) % HASH
    while get32(s.keys, at) != 4294967295u32 && get32(s.keys, at) != key { at = (at + 1usize) % HASH }
    ret at
}

fn write(sink_writer: *Writer, src: []const u8) -> (usize, err) {
    if sink_writer.state == nil { ret (0usize, Invalid) }
    let s = mem.cast[*WriterState](sink_writer.state)
    if !s.started {
        let clear_error = emit(s, s.clear)
        if clear_error != ok { ret (0usize, clear_error) }
        s.started = true
    }
    var at = 0usize
    while at < src.len {
        let byte = src[at]
        if !s.has_current {
            s.current = u32(byte)
            s.has_current = true
        } else {
            let key = (s.current << 8u32) | u32(byte)
            let slot = slot_of(s, key)
            if get32(s.keys, slot) == key {
                s.current = get16(s.values, slot)
            } else {
                let emit_error = emit(s, s.current)
                if emit_error != ok { ret (at, emit_error) }
                if s.next < u32(TABLE) {
                    set32(s.keys, slot, key)
                    set16(s.values, slot, s.next)
                    s.next += 1u32
                    if s.next > (1u32 << s.width) && s.width < MAX_WIDTH { s.width += 1u32 }
                } else {
                    let clear_error = emit(s, s.clear)
                    if clear_error != ok { ret (at, clear_error) }
                    clear_table(s)
                }
                s.current = u32(byte)
            }
        }
        at += 1usize
    }
    ret (src.len, ok)
}

fn finish(sink_writer: *Writer) -> err {
    if sink_writer.state == nil { ret Invalid }
    let s = mem.cast[*WriterState](sink_writer.state)
    if !s.started {
        try emit(s, s.clear)
        s.started = true
    }
    if s.has_current {
        try emit(s, s.current)
        s.has_current = false
    }
    try emit(s, s.end)
    if s.bit_count > 0u32 {
        var byte: [1]u8 = zero
        if s.order == .LeastSignificant {
            byte[0] = u8(s.bits & 255u64)
        } else {
            byte[0] = u8((s.bits << (8u32 - s.bit_count)) & 255u64)
        }
        s.bits = 0u64
        s.bit_count = 0u32
        try io.write_all(&s.sink, byte[0..])
    }
    ret io.flush(&s.sink)
}

// --- The planned name `encode`, whole-buffer forms over the streaming pair: the
// codes of `src` in the arena (12-bit codes at worst, so at most 1.5 bytes a byte
// plus the clears), and `decode` growing its output up to `output_limit`.

fn encode(a: *mem.Arena, src: []const u8, order: Order, literal_width: u8) -> ([]u8, err) {
    let (needed, needed_error) = storage_required(literal_width)
    if needed_error != ok { ret (zero, needed_error) }
    let (storage, storage_error) = mem.alloc[u8](a, needed)
    if storage_error != ok { ret (zero, storage_error) }
    let (out, out_error) = mem.alloc[u8](a, src.len + src.len / 2usize + src.len / 512usize + 16usize)
    if out_error != ok { ret (zero, out_error) }
    var sink_state = io.SliceWriter { data: out, off: 0usize }
    let (w0, writer_error) = writer(storage, io.slice_writer(&sink_state), order, literal_width)
    if writer_error != ok { ret (zero, writer_error) }
    var w = w0
    let (_, write_error) = write(&w, src)
    if write_error != ok { ret (zero, write_error) }
    let finish_error = finish(&w)
    if finish_error != ok { ret (zero, finish_error) }
    ret (out[..sink_state.off], ok)
}

fn decode(a: *mem.Arena, src: []const u8, order: Order, literal_width: u8, output_limit: u64) -> ([]u8, err) {
    let (needed, needed_error) = storage_required(literal_width)
    if needed_error != ok { ret (zero, needed_error) }
    let (storage, storage_error) = mem.alloc[u8](a, needed)
    if storage_error != ok { ret (zero, storage_error) }
    var source_state = io.SliceReader { data: src, off: 0usize }
    let (r0, reader_error) = reader(storage, io.slice_reader(&source_state), order, literal_width, output_limit)
    if reader_error != ok { ret (zero, reader_error) }
    var r = r0
    var capacity = src.len * 2usize + 64usize
    let (first, first_error) = mem.alloc[u8](a, capacity)
    if first_error != ok { ret (zero, first_error) }
    var out = first
    var filled = 0usize
    while true {
        if filled == capacity {
            let (bigger, bigger_error) = mem.alloc[u8](a, capacity * 2usize)
            if bigger_error != ok { ret (zero, bigger_error) }
            mem.copy[u8](bigger[..filled], out[..filled])
            out = bigger
            capacity = capacity * 2usize
        }
        let (count, read_error) = read(&r, out[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        filled += count
    }
    ret (out[..filled], ok)
}
