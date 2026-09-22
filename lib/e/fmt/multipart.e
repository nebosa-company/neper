// MIME multipart (RFC 2046) over streams. The reader keeps an 8 KiB window on the
// source: `reader_next_err` finds the next `--boundary` line, parses the part's header
// block through `e.fmt.mime` into an arena carved from the storage, and hands out a
// body reader that yields bytes up to the `CRLF--boundary` delimiter, holding back
// only as many trailing bytes as could begin one. One part is live at a time; asking
// for the next drains the current body. The writer puts each part's delimiter and
// headers on the sink and returns the sink itself for the body, so nothing is
// buffered; `finish` writes the closing delimiter. A boundary longer than 70 bytes,
// empty, ending in a space or holding a byte outside RFC 2046's set is
// `InvalidBoundary`. Storage is `storage_required()` bytes, 8-aligned.
use e.io
use e.mem
use e.str
use e.fmt.mime as mime

type Part = struct { headers: []const mime.Header, body: io.Reader }
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error InvalidBoundary
error Invalid
error TooLarge

const WINDOW: usize = 8192usize
const HEADER_ARENA: usize = 4096usize

type ReaderState = struct {
    source: io.Reader,
    boundary: str,
    window: []u8,
    at: usize,
    len: usize,
    header_storage: []u8,
    source_ended: bool,
    started: bool,
    closed: bool,
    in_body: bool,
    body_done: bool,
    parts: u32,
    part_limit: u32,
    consumed: u64,
    byte_limit: u64,
}

type WriterState = struct { sink: io.Writer, boundary: str, started: bool, finished: bool }

fn boundary_legal(boundary: str) -> bool {
    if boundary.len == 0usize || boundary.len > 70usize { ret false }
    if boundary[boundary.len - 1usize] == 32u8 { ret false }
    var i = 0usize
    while i < boundary.len {
        let c = boundary[i]
        let special = c == 39u8 || c == 40u8 || c == 41u8 || c == 43u8 || c == 95u8 || c == 44u8 || c == 45u8 || c == 46u8 || c == 47u8 || c == 58u8 || c == 61u8 || c == 63u8 || c == 32u8
        if !str.is_ascii_alnum(c) && !special { ret false }
        i += 1usize
    }
    ret true
}

fn storage_required() -> usize {
    ret mem.size_of[ReaderState]() + 8usize + WINDOW + HEADER_ARENA
}

fn reader(storage: []u8, source: io.Reader, boundary: str, part_limit: u32, byte_limit: u64) -> (Reader, err) {
    if !boundary_legal(boundary) { ret (zero, InvalidBoundary) }
    if storage.len < storage_required() { ret (zero, io.TooSmall) }
    let s = mem.cast[*ReaderState](&storage[0])
    let blank: ReaderState = zero
    *s = blank
    var at = mem.size_of[ReaderState]() + 8usize
    s.window = storage[at..at + WINDOW]
    at += WINDOW
    s.header_storage = storage[at..at + HEADER_ARENA]
    s.source = source
    s.boundary = boundary
    s.at = 0usize
    s.len = 0usize
    s.source_ended = false
    s.started = false
    s.closed = false
    s.in_body = false
    s.body_done = false
    s.parts = 0u32
    s.part_limit = part_limit
    s.consumed = 0u64
    s.byte_limit = byte_limit
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// Moves the unread bytes to the front and reads more; false when nothing more came.
fn refill(s: *ReaderState) -> (bool, err) {
    if s.source_ended { ret (false, ok) }
    if s.at > 0usize {
        var i = 0usize
        while i < s.len - s.at {
            s.window[i] = s.window[s.at + i]
            i += 1usize
        }
        s.len -= s.at
        s.at = 0usize
    }
    if s.len == s.window.len { ret (false, TooLarge) }
    let (count, read_error) = io.read(&s.source, s.window[s.len..])
    if read_error == io.End || (read_error == ok && count == 0usize) {
        s.source_ended = true
        ret (false, ok)
    }
    if read_error != ok { ret (false, read_error) }
    s.len += count
    s.consumed += u64(count)
    if s.consumed > s.byte_limit { ret (false, TooLarge) }
    ret (true, ok)
}

// The position of `needle` in the unread window, filling as needed; (0, false) when
// the source ends without it.
fn find_in_window(s: *ReaderState, needle: str) -> (usize, bool, err) {
    while true {
        let (found_at, found) = str.find(s.window[s.at..s.len], needle)
        if found { ret (s.at + found_at, true, ok) }
        let (more, refill_error) = refill(s)
        if refill_error != ok { ret (0usize, false, refill_error) }
        if !more { ret (0usize, false, ok) }
    }
}

// Ensures `n` unread bytes are in the window when the source has them.
fn ensure(s: *ReaderState, n: usize) -> err {
    while s.len - s.at < n {
        let (more, refill_error) = refill(s)
        if refill_error != ok { ret refill_error }
        if !more { ret ok }
    }
    ret ok
}

// Consumes what follows a boundary line: `--` closes the message, CRLF opens a part.
fn after_boundary(s: *ReaderState) -> err {
    try ensure(s, 2usize)
    if s.len - s.at < 2usize { ret Invalid }
    if s.window[s.at] == 45u8 && s.window[s.at + 1usize] == 45u8 {
        s.closed = true
        s.at += 2usize
        ret ok
    }
    if s.window[s.at] != 13u8 || s.window[s.at + 1usize] != 10u8 { ret Invalid }
    s.at += 2usize
    ret ok
}

fn reader_next_err(source_reader: *Reader) -> (Part, bool, err) {
    let s = mem.cast[*ReaderState](source_reader.state)
    if s.closed { ret (zero, false, ok) }
    if s.in_body {
        // Drain the live body to its delimiter.
        var sink: [256]u8 = zero
        var body = body_reader(s)
        while true {
            let (count, read_error) = io.read(&body, sink[0..])
            if read_error == io.End { break }
            if read_error != ok { ret (zero, false, read_error) }
        }
        if s.closed { ret (zero, false, ok) }
    }
    if !s.started {
        // The first boundary line, after any preamble.
        s.started = true
        var opener: [72]u8 = zero
        opener[0] = 45u8
        opener[1] = 45u8
        mem.copy[u8](opener[2usize..2usize + s.boundary.len], s.boundary)
        let (found_at, found, find_error) = find_in_window(s, opener[..2usize + s.boundary.len])
        if find_error != ok { ret (zero, false, find_error) }
        if !found { ret (zero, false, Invalid) }
        s.at = found_at + 2usize + s.boundary.len
        let after_error = after_boundary(s)
        if after_error != ok { ret (zero, false, after_error) }
        if s.closed { ret (zero, false, ok) }
    }
    if s.parts >= s.part_limit { ret (zero, false, TooLarge) }
    s.parts += 1u32
    // The header block ends at the first empty line; an empty block is CRLF alone.
    let ensure_error = ensure(s, 2usize)
    if ensure_error != ok { ret (zero, false, ensure_error) }
    if s.len - s.at < 2usize { ret (zero, false, Invalid) }
    var headers: []mime.Header = zero
    if s.window[s.at] == 13u8 && s.window[s.at + 1usize] == 10u8 {
        s.at += 2usize
    } else {
        let (blank_at, has_blank, blank_error) = find_in_window(s, "\r\n\r\n")
        if blank_error != ok { ret (zero, false, blank_error) }
        if !has_blank { ret (zero, false, Invalid) }
        var arena = mem.arena_from(s.header_storage)
        var block_state = io.SliceReader { data: s.window[s.at..blank_at + 4usize], off: 0usize }
        let (parsed, parse_error) = mime.parse_headers(&arena, io.slice_reader(&block_state), HEADER_ARENA / 2usize, 64usize)
        if parse_error != ok { ret (zero, false, Invalid) }
        headers = parsed
        s.at = blank_at + 4usize
    }
    s.in_body = true
    s.body_done = false
    var part: Part = zero
    part.headers = headers
    part.body = body_reader(s)
    ret (part, true, ok)
}

fn body_reader(s: *ReaderState) -> io.Reader {
    ret io.Reader { ctx: mem.cast[*void](s), read: body_read }
}

fn body_read(ctx: *void, dst: []u8) -> (usize, err) {
    let s = mem.cast[*ReaderState](ctx)
    if !s.in_body { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    var delimiter: [74]u8 = zero
    delimiter[0] = 13u8
    delimiter[1] = 10u8
    delimiter[2] = 45u8
    delimiter[3] = 45u8
    mem.copy[u8](delimiter[4usize..4usize + s.boundary.len], s.boundary)
    let needle = delimiter[..4usize + s.boundary.len]
    while true {
        let (found_at, found) = str.find(s.window[s.at..s.len], needle)
        if found {
            if found_at > 0usize {
                var take = found_at
                if take > dst.len { take = dst.len }
                mem.copy[u8](dst[..take], s.window[s.at..s.at + take])
                s.at += take
                ret (take, ok)
            }
            s.at += needle.len
            s.in_body = false
            let after_error = after_boundary(s)
            if after_error != ok { ret (0usize, after_error) }
            ret (0usize, io.End)
        }
        // Without a delimiter, all but a possible prefix of one at the end is safe.
        let unread = s.len - s.at
        var safe = 0usize
        if unread >= needle.len { safe = unread - needle.len + 1usize }
        if safe > 0usize {
            var take = safe
            if take > dst.len { take = dst.len }
            mem.copy[u8](dst[..take], s.window[s.at..s.at + take])
            s.at += take
            ret (take, ok)
        }
        let (more, refill_error) = refill(s)
        if refill_error != ok { ret (0usize, refill_error) }
        if !more { ret (0usize, Invalid) }
    }
}

fn writer(storage: []u8, sink: io.Writer, boundary: str) -> (Writer, err) {
    if !boundary_legal(boundary) { ret (zero, InvalidBoundary) }
    if storage.len < mem.size_of[WriterState]() + 8usize { ret (zero, io.TooSmall) }
    let s = mem.cast[*WriterState](&storage[0])
    let blank: WriterState = zero
    *s = blank
    s.sink = sink
    s.boundary = boundary
    s.started = false
    s.finished = false
    var w: Writer = zero
    w.state = mem.cast[*void](s)
    ret (w, ok)
}

fn start_part(sink_writer: *Writer, headers: []const mime.Header) -> (io.Writer, err) {
    let s = mem.cast[*WriterState](sink_writer.state)
    if s.finished { ret (zero, Invalid) }
    if s.started {
        let crlf_error = io.write_all(&s.sink, "\r\n")
        if crlf_error != ok { ret (zero, crlf_error) }
    }
    s.started = true
    let open_error = io.write_all(&s.sink, "--")
    if open_error != ok { ret (zero, open_error) }
    let boundary_error = io.write_all(&s.sink, s.boundary)
    if boundary_error != ok { ret (zero, boundary_error) }
    let line_error = io.write_all(&s.sink, "\r\n")
    if line_error != ok { ret (zero, line_error) }
    var i = 0usize
    while i < headers.len {
        let name_error = io.write_all(&s.sink, headers[i].name)
        if name_error != ok { ret (zero, name_error) }
        let colon_error = io.write_all(&s.sink, ": ")
        if colon_error != ok { ret (zero, colon_error) }
        let value_error = io.write_all(&s.sink, headers[i].value)
        if value_error != ok { ret (zero, value_error) }
        let end_error = io.write_all(&s.sink, "\r\n")
        if end_error != ok { ret (zero, end_error) }
        i += 1usize
    }
    let blank_error = io.write_all(&s.sink, "\r\n")
    if blank_error != ok { ret (zero, blank_error) }
    ret (s.sink, ok)
}

fn finish(sink_writer: *Writer) -> err {
    let s = mem.cast[*WriterState](sink_writer.state)
    if s.finished { ret ok }
    if s.started { try io.write_all(&s.sink, "\r\n") }
    try io.write_all(&s.sink, "--")
    try io.write_all(&s.sink, s.boundary)
    try io.write_all(&s.sink, "--\r\n")
    s.finished = true
    ret io.flush(&s.sink)
}
