// Quoted-printable, RFC 2045 section 6.7, over `e.io` streams and caller storage.
// The reader decodes strictly: an `=` must be followed by two upper-case hex digits or
// a CRLF (a soft break), and a bare CR or a byte above 126 in the input is `Invalid`.
// The writer escapes everything outside the printable ASCII range and `=`, keeps a
// trailing space or tab before a line end escaped, and breaks lines with `=\r\n` at
// the caller's limit (at most 76, RFC's maximum).
//
// Both keep a `State` in the first bytes of their storage; the rest of the storage is
// the reader's input buffer or the writer's pending line.

use e.io
use e.mem

type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid

type ReaderState = struct { source: io.Reader, buffer: []u8, start: usize, end: usize, ended: bool }
type WriterState = struct { sink: io.Writer, line: []u8, used: usize, limit: usize }

fn is_hex_upper(c: u8) -> bool {
    let digit = c >= 48u8 && c <= 57u8
    ret digit || (c >= 65u8 && c <= 70u8)
}

fn hex_value(c: u8) -> u8 {
    if c <= 57u8 { ret c - 48u8 }
    ret c - 55u8
}

fn hex_digit(nibble: u8) -> u8 {
    if nibble < 10u8 { ret nibble + 48u8 }
    ret nibble + 55u8
}

// `storage` must hold the state and at least three more bytes; the rest buffers input.
fn reader(storage: []u8, source: io.Reader) -> Reader {
    var r: Reader = zero
    let state_size = mem.size_of[ReaderState]()
    if storage.len < state_size + 3usize { ret r }
    let state = mem.cast[*ReaderState](&storage[0])
    state.source = source
    state.buffer = storage[state_size..]
    state.start = 0usize
    state.end = 0usize
    state.ended = false
    r.state = mem.cast[*void](state)
    ret r
}

// Tops the buffer up from the source; `false` when nothing more will come.
fn refill(s: *ReaderState) -> err {
    if s.ended { ret ok }
    if s.start > 0usize {
        var at = 0usize
        while s.start + at < s.end {
            s.buffer[at] = s.buffer[s.start + at]
            at += 1usize
        }
        s.end -= s.start
        s.start = 0usize
    }
    if s.end == s.buffer.len { ret ok }
    let (count, read_error) = io.read(&s.source, s.buffer[s.end..])
    if read_error == io.End {
        s.ended = true
        ret ok
    }
    if read_error != ok { ret read_error }
    s.end += count
    ret ok
}

fn read(source_reader: *Reader, dst: []u8) -> (usize, err) {
    if source_reader.state == nil { ret (0usize, Invalid) }
    let s = mem.cast[*ReaderState](source_reader.state)
    var written = 0usize
    while written < dst.len {
        // Three bytes in hand decide every case; fewer only at the very end.
        if s.end - s.start < 3usize && !s.ended {
            let refill_error = refill(s)
            if refill_error != ok { ret (written, refill_error) }
        }
        if s.start >= s.end {
            if written == 0usize { ret (0usize, io.End) }
            ret (written, ok)
        }
        let c = s.buffer[s.start]
        if c == 61u8 {
            if s.end - s.start < 2usize { ret (written, Invalid) }
            let next = s.buffer[s.start + 1usize]
            if next == 13u8 {
                // A soft line break: `=` CR LF is nothing.
                if s.end - s.start < 3usize || s.buffer[s.start + 2usize] != 10u8 { ret (written, Invalid) }
                s.start += 3usize
            } else {
                if s.end - s.start < 3usize { ret (written, Invalid) }
                let second = s.buffer[s.start + 2usize]
                if !is_hex_upper(next) || !is_hex_upper(second) { ret (written, Invalid) }
                dst[written] = hex_value(next) * 16u8 + hex_value(second)
                written += 1usize
                s.start += 3usize
            }
        } else {
            if c == 13u8 {
                // A hard line break must be CR LF.
                if s.end - s.start < 2usize || s.buffer[s.start + 1usize] != 10u8 { ret (written, Invalid) }
                dst[written] = 13u8
                written += 1usize
                s.start += 1usize
            } else {
                if c > 126u8 || (c < 32u8 && c != 9u8 && c != 10u8) { ret (written, Invalid) }
                dst[written] = c
                written += 1usize
                s.start += 1usize
            }
        }
    }
    ret (written, ok)
}

// `storage` must hold the state and a line of `line_limit` bytes plus three.
fn writer(storage: []u8, sink: io.Writer, line_limit: u8) -> (Writer, err) {
    var w: Writer = zero
    if line_limit < 4u8 || line_limit > 76u8 { ret (w, Invalid) }
    let state_size = mem.size_of[WriterState]()
    if storage.len < state_size + usize(line_limit) + 3usize { ret (w, io.TooSmall) }
    let state = mem.cast[*WriterState](&storage[0])
    state.sink = sink
    state.line = storage[state_size..]
    state.used = 0usize
    state.limit = usize(line_limit)
    w.state = mem.cast[*void](state)
    ret (w, ok)
}

// Flushes the pending line, ending it with a soft break so the next write continues
// the same logical line.
fn soft_break(s: *WriterState) -> err {
    s.line[s.used] = 61u8
    s.line[s.used + 1usize] = 13u8
    s.line[s.used + 2usize] = 10u8
    try io.write_all(&s.sink, s.line[..s.used + 3usize])
    s.used = 0usize
    ret ok
}

fn put(s: *WriterState, bytes: []const u8) -> err {
    // A soft break goes in when the piece would not leave room for the `=` of one.
    if s.used + bytes.len > s.limit - 1usize { try soft_break(s) }
    var at = 0usize
    while at < bytes.len {
        s.line[s.used + at] = bytes[at]
        at += 1usize
    }
    s.used += bytes.len
    ret ok
}

fn write(sink_writer: *Writer, src: []const u8) -> (usize, err) {
    if sink_writer.state == nil { ret (0usize, Invalid) }
    let s = mem.cast[*WriterState](sink_writer.state)
    var at = 0usize
    while at < src.len {
        let c = src[at]
        var escaped: [3]u8 = zero
        if c == 13u8 && at + 1usize < src.len && src[at + 1usize] == 10u8 {
            // A hard break: the line so far, with any trailing white space escaped, then CRLF.
            if s.used > 0usize && (s.line[s.used - 1usize] == 32u8 || s.line[s.used - 1usize] == 9u8) {
                let last = s.line[s.used - 1usize]
                s.used -= 1usize
                escaped[0] = 61u8
                escaped[1] = hex_digit(last >> 4u8)
                escaped[2] = hex_digit(last & 15u8)
                let put_error = put(s, escaped[0..])
                if put_error != ok { ret (at, put_error) }
            }
            s.line[s.used] = 13u8
            s.line[s.used + 1usize] = 10u8
            let write_error = io.write_all(&s.sink, s.line[..s.used + 2usize])
            if write_error != ok { ret (at, write_error) }
            s.used = 0usize
            at += 2usize
        } else {
            let printable = c >= 33u8 && c <= 126u8 && c != 61u8
            let literal = printable || c == 32u8 || c == 9u8
            if literal {
                escaped[0] = c
                let put_error = put(s, escaped[..1])
                if put_error != ok { ret (at, put_error) }
            } else {
                escaped[0] = 61u8
                escaped[1] = hex_digit(c >> 4u8)
                escaped[2] = hex_digit(c & 15u8)
                let put_error = put(s, escaped[0..])
                if put_error != ok { ret (at, put_error) }
            }
            at += 1usize
        }
    }
    ret (src.len, ok)
}

// The last line goes out as it is; a trailing space or tab on it is escaped, since a
// receiver may strip white space at a line end.
fn finish(sink_writer: *Writer) -> err {
    if sink_writer.state == nil { ret Invalid }
    let s = mem.cast[*WriterState](sink_writer.state)
    if s.used > 0usize && (s.line[s.used - 1usize] == 32u8 || s.line[s.used - 1usize] == 9u8) {
        let last = s.line[s.used - 1usize]
        s.used -= 1usize
        var escaped: [3]u8 = zero
        escaped[0] = 61u8
        escaped[1] = hex_digit(last >> 4u8)
        escaped[2] = hex_digit(last & 15u8)
        try put(s, escaped[0..])
    }
    if s.used > 0usize {
        try io.write_all(&s.sink, s.line[..s.used])
        s.used = 0usize
    }
    ret io.flush(&s.sink)
}
