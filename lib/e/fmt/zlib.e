// zlib framing (RFC 1950) around `e.algo.deflate`: a pull reader that checks the two
// header bytes, inflates through a 4 KiB input buffer and a 32 KiB window, and
// compares the big-endian Adler-32 trailer before answering `io.End`; a writer that
// puts the 0x78 0x9c header first, deflates through a 4 KiB staging buffer and
// writes the trailer on `finish`. A preset dictionary (FDICT) is `Invalid`; output
// past `output_limit` is `deflate.TooLarge`.
use e.io
use e.mem
use e.algo.deflate as deflate

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
    adler_a: u32,
    adler_b: u32,
    produced: u64,
    output_limit: u64,
    source_ended: bool,
}

type WriterState = struct {
    sink: io.Writer,
    encoder: deflate.Encoder,
    staging: []u8,
    started: bool,
    finished: bool,
    adler_a: u32,
    adler_b: u32,
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
    s.adler_a = 1u32
    s.adler_b = 0u32
    s.produced = 0u64
    s.output_limit = output_limit
    s.source_ended = false
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// Refills the input buffer from the source; false at its end.
fn fill(s: *ReaderState) -> (bool, err) {
    let (count, read_error) = io.read(&s.source, s.input)
    if read_error == io.End { ret (false, ok) }
    if read_error != ok { ret (false, read_error) }
    s.in_at = 0usize
    s.in_len = count
    ret (count > 0usize, ok)
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

fn adler_update(a_in: u32, b_in: u32, data: []const u8) -> (u32, u32) {
    var a = a_in
    var b = b_in
    var i = 0usize
    while i < data.len {
        a = (a + u32(data[i])) % 65521u32
        b = (b + a) % 65521u32
        i += 1usize
    }
    ret (a, b)
}

fn read(source_reader: *Reader, dst: []u8) -> (usize, err) {
    let s = mem.cast[*ReaderState](source_reader.state)
    if s.stage == 0u32 {
        let (cmf, cmf_error) = next_byte(s)
        if cmf_error != ok { ret (0usize, cmf_error) }
        let (flg, flg_error) = next_byte(s)
        if flg_error != ok { ret (0usize, flg_error) }
        if cmf & 15u8 != 8u8 || cmf >> 4u8 > 7u8 { ret (0usize, Invalid) }
        if (u32(cmf) * 256u32 + u32(flg)) % 31u32 != 0u32 { ret (0usize, Invalid) }
        if flg & 32u8 != 0u8 { ret (0usize, Invalid) }
        s.stage = 1u32
    }
    if s.stage == 3u32 { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    while s.stage == 1u32 {
        if s.in_at == s.in_len && !s.source_ended {
            let (more, fill_error) = fill(s)
            if fill_error != ok { ret (0usize, fill_error) }
            if !more { s.source_ended = true }
        }
        // With the source gone the decoder is told so, and a truncated stream is its Invalid.
        let (consumed, written, status, decode_error) = deflate.decode(&s.decoder, s.input[s.in_at..s.in_len], dst, s.source_ended)
        if decode_error != ok { ret (0usize, Invalid) }
        s.in_at += consumed
        if written > 0usize {
            s.produced += u64(written)
            if s.produced > s.output_limit { ret (0usize, deflate.TooLarge) }
            let (a, b) = adler_update(s.adler_a, s.adler_b, dst[..written])
            s.adler_a = a
            s.adler_b = b
        }
        if status == .Finished { s.stage = 2u32 }
        if written > 0usize { ret (written, ok) }
    }
    // The trailer: whatever the decoder over-read comes first.
    var trailer: [8]u8 = zero
    let held = deflate.leftover(&s.decoder, trailer[0..])
    var i = held
    while i < 4usize {
        let (byte, byte_error) = next_byte(s)
        if byte_error != ok { ret (0usize, byte_error) }
        trailer[i] = byte
        i += 1usize
    }
    let expected = (u32(trailer[0]) << 24u32) | (u32(trailer[1]) << 16u32) | (u32(trailer[2]) << 8u32) | u32(trailer[3])
    s.stage = 3u32
    if expected != ((s.adler_b << 16u32) | s.adler_a) { ret (0usize, Checksum) }
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
    s.adler_a = 1u32
    s.adler_b = 0u32
    var w: Writer = zero
    w.state = mem.cast[*void](s)
    ret (w, ok)
}

fn start(s: *WriterState) -> err {
    if s.started { ret ok }
    s.started = true
    var header: [2]u8 = zero
    header[0] = 120u8
    header[1] = 156u8
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
    let (a, b) = adler_update(s.adler_a, s.adler_b, src)
    s.adler_a = a
    s.adler_b = b
    ret (src.len, ok)
}

fn finish(sink_writer: *Writer) -> err {
    let s = mem.cast[*WriterState](sink_writer.state)
    if s.finished { ret ok }
    try start(s)
    var none: [1]u8 = zero
    try pump(s, none[0..0], true)
    let checksum = (s.adler_b << 16u32) | s.adler_a
    var trailer: [4]u8 = zero
    trailer[0] = u8(checksum >> 24u32)
    trailer[1] = u8((checksum >> 16u32) & 255u32)
    trailer[2] = u8((checksum >> 8u32) & 255u32)
    trailer[3] = u8(checksum & 255u32)
    try io.write_all(&s.sink, trailer[0..])
    s.finished = true
    ret io.flush(&s.sink)
}
