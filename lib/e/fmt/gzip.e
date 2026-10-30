// gzip framing (RFC 1952) around `e.algo.deflate`: a pull reader that validates the
// header -- magic, method 8, FEXTRA, FNAME, FCOMMENT and FHCRC -- as it comes,
// inflates through a 4 KiB input buffer and a 32 KiB window, and
// compares the CRC-32 and ISIZE trailer before answering `io.End`; a writer that puts
// a minimal header first (no name, unknown OS, zero mtime), deflates through a 4 KiB
// staging buffer and writes the trailer on `finish`. Output past `output_limit` is
// `deflate.TooLarge`. One member only: `remaining` hands post-trailer bytes to a
// caller that chains another member or parses an enclosing suffix.
use e.io
use e.mem
use e.algo.deflate as deflate
use e.algo.hash as hash

type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid
error Checksum

const BUFFER: usize = 4096usize
const WINDOW: usize = 32768usize

type ReaderState = struct {
    source: io.Reader,
    decoder: deflate.Decoder,
    input: []u8,
    in_at: usize,
    in_len: usize,
    stage: u32,
    crc: hash.Crc32,
    produced: u64,
    output_limit: u64,
    source_ended: bool,
    pending_error: err,
}

type WriterState = struct {
    sink: io.Writer,
    encoder: deflate.Encoder,
    staging: []u8,
    started: bool,
    finished: bool,
    crc: hash.Crc32,
    total: u64,
}

fn storage_required(level: deflate.Level) -> usize {
    let (window_size, window_error) = deflate.decoder_storage(WINDOW)
    let reader_size = mem_round(mem.size_of[ReaderState]()) + BUFFER + window_size
    let writer_size = mem_round(mem.size_of[WriterState]()) + BUFFER + deflate.encoder_storage(level)
    if writer_size > reader_size { ret writer_size }
    ret reader_size
}

// The deflate state is cast from storage too, so it starts on an 8-byte boundary.
fn mem_round(n: usize) -> usize {
    let up = n + 7usize
    ret up / 8usize * 8usize
}

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err) {
    if storage.len < storage_required(.Fast) { ret (zero, io.TooSmall) }
    let s = mem.cast[*ReaderState](&storage[0])
    let blank: ReaderState = zero
    *s = blank
    var at = mem_round(mem.size_of[ReaderState]())
    s.input = storage[at..at + BUFFER]
    at += BUFFER
    let (d, d_error) = deflate.decoder(storage[at..], WINDOW)
    if d_error != ok { ret (zero, d_error) }
    s.decoder = d
    s.source = source
    s.in_at = 0usize
    s.in_len = 0usize
    s.stage = 0u32
    s.crc = hash.crc32_init()
    s.produced = 0u64
    s.output_limit = output_limit
    s.source_ended = false
    s.pending_error = ok
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// Refills the input buffer from the source; false at its end.
fn fill(s: *ReaderState) -> (bool, err) {
    if s.pending_error != ok {
        let pending = s.pending_error
        s.pending_error = ok
        if pending == io.End { ret (false, ok) }
        ret (false, pending)
    }
    let (count, read_error) = io.read(&s.source, s.input)
    s.in_at = 0usize
    s.in_len = count
    if read_error == io.End { s.source_ended = true }
    if count > 0usize {
        if read_error != ok { s.pending_error = read_error }
        ret (true, ok)
    }
    if read_error == io.End { ret (false, ok) }
    if read_error != ok { ret (false, read_error) }
    ret (false, io.NoProgress)
}

fn next_byte(s: *ReaderState) -> (u8, err) {
    if s.in_at == s.in_len {
        let (more, fill_error) = fill(s)
        if fill_error != ok { ret (0u8, fill_error) }
        if !more { ret (0u8, Invalid) }
    }
    let byte = s.input[s.in_at]
    s.in_at += 1usize
    ret (byte, ok)
}

// The unread bytes after a complete member. The returned reader borrows this
// reader's storage, so it must be drained before that storage is reused.
fn remaining(source_reader: *Reader) -> (io.Reader, err) {
    let s = mem.cast[*ReaderState](source_reader.state)
    if s.stage != 3u32 { ret (zero, Invalid) }
    ret (io.Reader { ctx: mem.cast[*void](s), read: remaining_read }, ok)
}

fn remaining_read(ctx: *void, dst: []u8) -> (usize, err) {
    let s = mem.cast[*ReaderState](ctx)
    if dst.len == 0usize { ret (0usize, ok) }
    let held = deflate.leftover(&s.decoder, dst)
    if held > 0usize { ret (held, ok) }
    if s.in_at < s.in_len {
        var take = s.in_len - s.in_at
        if take > dst.len { take = dst.len }
        mem.copy[u8](dst[..take], s.input[s.in_at..s.in_at + take])
        s.in_at += take
        ret (take, ok)
    }
    if s.pending_error != ok { ret (0usize, s.pending_error) }
    let (count, read_error) = io.read(&s.source, dst)
    ret (count, read_error)
}

// Reads one optional-header byte and includes it in the FHCRC calculation.
fn header_byte(s: *ReaderState, header_crc: *hash.Crc32) -> (u8, err) {
    let (byte, byte_error) = next_byte(s)
    if byte_error != ok { ret (0u8, byte_error) }
    var one: [1]u8 = zero
    one[0usize] = byte
    hash.crc32_update(header_crc, one[..])
    ret (byte, ok)
}

fn read(source_reader: *Reader, dst: []u8) -> (usize, err) {
    let s = mem.cast[*ReaderState](source_reader.state)
    if s.stage == 0u32 {
        var header: [10]u8 = zero
        var i = 0usize
        while i < 10usize {
            let (byte, byte_error) = next_byte(s)
            if byte_error != ok { ret (0usize, byte_error) }
            header[i] = byte
            i += 1usize
        }
        if header[0] != 31u8 || header[1] != 139u8 || header[2] != 8u8 { ret (0usize, Invalid) }
        let flags = header[3]
        if flags & 224u8 != 0u8 { ret (0usize, Invalid) }
        var header_crc = hash.crc32_init()
        hash.crc32_update(&header_crc, header[..])
        if flags & 4u8 != 0u8 {
            let (low, low_error) = header_byte(s, &header_crc)
            if low_error != ok { ret (0usize, low_error) }
            let (high, high_error) = header_byte(s, &header_crc)
            if high_error != ok { ret (0usize, high_error) }
            var extra = usize(low) | (usize(high) << 8u32)
            while extra > 0usize {
                let (skipped, skip_error) = header_byte(s, &header_crc)
                if skip_error != ok { ret (0usize, skip_error) }
                extra -= 1usize
            }
        }
        var field = 8u8
        while field <= 16u8 {
            if flags & field != 0u8 {
                while true {
                    let (byte, byte_error) = header_byte(s, &header_crc)
                    if byte_error != ok { ret (0usize, byte_error) }
                    if byte == 0u8 { break }
                }
            }
            field = field * 2u8
        }
        if flags & 2u8 != 0u8 {
            let (c0, c0_error) = next_byte(s)
            if c0_error != ok { ret (0usize, c0_error) }
            let (c1, c1_error) = next_byte(s)
            if c1_error != ok { ret (0usize, c1_error) }
            let expected_header_crc = u32(c0) | (u32(c1) << 8u32)
            if expected_header_crc != (hash.crc32_done(&header_crc) & 65535u32) { ret (0usize, Checksum) }
        }
        s.stage = 1u32
    }
    if s.stage == 4u32 { ret (0usize, deflate.TooLarge) }
    if s.stage == 3u32 { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    while s.stage == 1u32 {
        if s.in_at == s.in_len && !s.source_ended {
            let (more, fill_error) = fill(s)
            if fill_error != ok { ret (0usize, fill_error) }
            if !more { s.source_ended = true }
        }
        // With the source gone the decoder is told so, and a truncated stream is its Invalid.
        // Keep a private byte for the exact-limit probe: a completed stream
        // must still reach its trailer, while a further decoded byte is TooLarge
        // without ever being exposed through the caller's destination.
        var destination = dst
        var overflow_probe: [1]u8 = zero
        var probing = false
        if s.produced >= s.output_limit {
            destination = overflow_probe[..]
            probing = true
        } else {
            let budget_left = s.output_limit - s.produced
            if u64(destination.len) > budget_left { destination = destination[..usize(budget_left)] }
        }
        let (consumed, written, status, decode_error) = deflate.decode(&s.decoder, s.input[s.in_at..s.in_len], destination, s.source_ended)
        if decode_error != ok { ret (0usize, Invalid) }
        s.in_at += consumed
        if written > 0usize {
            if probing {
                s.stage = 4u32
                ret (0usize, deflate.TooLarge)
            }
            s.produced += u64(written)
            hash.crc32_update(&s.crc, destination[..written])
        }
        if status == .Finished { s.stage = 2u32 }
        if written > 0usize { ret (written, ok) }
    }
    // The trailer: whatever the decoder over-read comes first.
    var trailer: [8]u8 = zero
    let held = deflate.leftover(&s.decoder, trailer[0..])
    var i = held
    while i < 8usize {
        let (byte, byte_error) = next_byte(s)
        if byte_error != ok { ret (0usize, byte_error) }
        trailer[i] = byte
        i += 1usize
    }
    let expected_crc = u32(trailer[0]) | (u32(trailer[1]) << 8u32) | (u32(trailer[2]) << 16u32) | (u32(trailer[3]) << 24u32)
    let expected_size = u32(trailer[4]) | (u32(trailer[5]) << 8u32) | (u32(trailer[6]) << 16u32) | (u32(trailer[7]) << 24u32)
    s.stage = 3u32
    if expected_crc != hash.crc32_done(&s.crc) { ret (0usize, Checksum) }
    if expected_size != u32(s.produced & 4294967295u64) { ret (0usize, Checksum) }
    ret (0usize, io.End)
}

fn writer(storage: []u8, sink: io.Writer, level: deflate.Level) -> (Writer, err) {
    if storage.len < storage_required(level) { ret (zero, io.TooSmall) }
    let s = mem.cast[*WriterState](&storage[0])
    let blank: WriterState = zero
    *s = blank
    var at = mem_round(mem.size_of[WriterState]())
    s.staging = storage[at..at + BUFFER]
    at += BUFFER
    let (e, e_error) = deflate.encoder(storage[at..], level)
    if e_error != ok { ret (zero, e_error) }
    s.encoder = e
    s.sink = sink
    s.started = false
    s.finished = false
    s.crc = hash.crc32_init()
    s.total = 0u64
    var w: Writer = zero
    w.state = mem.cast[*void](s)
    ret (w, ok)
}

fn start(s: *WriterState) -> err {
    if s.started { ret ok }
    s.started = true
    var header: [10]u8 = zero
    header[0] = 31u8
    header[1] = 139u8
    header[2] = 8u8
    header[9] = 255u8
    ret io.write_all(&s.sink, header[0..])
}

// Runs the encoder over `src` until it asks for input, draining the staging buffer.
fn pump(s: *WriterState, src: []const u8, last: bool) -> err {
    var at = 0usize
    while true {
        let (consumed, written, status, encode_error) = deflate.encode(&s.encoder, src[at..], s.staging, last)
        if encode_error != ok { ret encode_error }
        at += consumed
        if written > 0usize { try io.write_all(&s.sink, s.staging[..written]) }
        if status == .Finished { ret ok }
        if status == .NeedInput && at == src.len { ret ok }
    }
}

fn write(sink_writer: *Writer, src: []const u8) -> (usize, err) {
    let s = mem.cast[*WriterState](sink_writer.state)
    if s.finished { ret (0usize, Invalid) }
    let start_error = start(s)
    if start_error != ok { ret (0usize, start_error) }
    let pump_error = pump(s, src, false)
    if pump_error != ok { ret (0usize, pump_error) }
    hash.crc32_update(&s.crc, src)
    s.total += u64(src.len)
    ret (src.len, ok)
}

fn finish(sink_writer: *Writer) -> err {
    let s = mem.cast[*WriterState](sink_writer.state)
    if s.finished { ret ok }
    try start(s)
    var none: [1]u8 = zero
    try pump(s, none[0..0], true)
    let checksum = hash.crc32_done(&s.crc)
    let size = u32(s.total & 4294967295u64)
    var trailer: [8]u8 = zero
    var i = 0usize
    while i < 4usize {
        trailer[i] = u8((checksum >> u32(i * 8usize)) & 255u32)
        trailer[4usize + i] = u8((size >> u32(i * 8usize)) & 255u32)
        i += 1usize
    }
    try io.write_all(&s.sink, trailer[0..])
    s.finished = true
    ret io.flush(&s.sink)
}
