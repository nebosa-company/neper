// HTTP/1.1 and its event-stream body format. The network-facing half remains planned;
// this first delivered slice is the bounded incremental SSE decoder, which depends only
// on a byte reader and therefore works unchanged over a response stream, a file or a test
// source.

use e.io
use e.mem
use e.text.utf8

type SseEvent = struct {
    event: str,
    data: str,
    id: str,
    has_id: bool,
    retry_ms: u64,
    has_retry: bool,
}

type SseState = struct {
    id: str,
    has_id: bool,
    retry_ms: u64,
    has_retry: bool,
}

type SseReader = struct { state: *void }
type SseLimits = struct { line_bytes: usize, event_bytes: usize }

error Invalid
error TooLarge
error Unsupported

const INPUT_CAPACITY: usize = 4096usize
const CR: u8 = 13u8
const LF: u8 = 10u8

type SseReaderState = struct {
    source: io.Reader,
    input: []u8,
    input_at: usize,
    input_len: usize,
    line: []u8,
    data: []u8,
    event: []u8,
    id: []u8,
    data_len: usize,
    event_len: usize,
    id_len: usize,
    event_used: usize,
    retry_ms: u64,
    has_id: bool,
    has_retry: bool,
    ended: bool,
    line_terminated: bool,
    first_line: bool,
}

fn take(s: *SseReaderState) -> (u8, bool, err) {
    if s.input_at == s.input_len {
        let (count, read_error) = io.read(&s.source, s.input)
        if read_error == io.End { ret (0u8, false, ok) }
        if read_error != ok { ret (0u8, false, read_error) }
        s.input_at = 0usize
        s.input_len = count
    }
    let byte = s.input[s.input_at]
    s.input_at += 1usize
    ret (byte, true, ok)
}

fn unread(s: *SseReaderState) {
    s.input_at -= 1usize
}

// A CR, LF or CRLF ends a line. A final unterminated line is still parsed so an id or
// retry update is retained, but the caller can distinguish it and never dispatch it.
fn read_line(s: *SseReaderState) -> (str, bool, err) {
    if s.ended { ret ("", false, ok) }
    var used = 0usize
    s.line_terminated = false
    while true {
        let (byte, more, read_error) = take(s)
        if read_error != ok { ret ("", false, read_error) }
        if !more {
            s.ended = true
            if used == 0usize { ret ("", false, ok) }
            ret (s.line[..used], true, ok)
        }
        if byte == LF {
            s.line_terminated = true
            ret (s.line[..used], true, ok)
        }
        if byte == CR {
            let (next, next_more, next_error) = take(s)
            if next_error != ok { ret ("", false, next_error) }
            if next_more {
                if next != LF { unread(s) }
            } else {
                s.ended = true
            }
            s.line_terminated = true
            ret (s.line[..used], true, ok)
        }
        if used == s.line.len { ret ("", false, TooLarge) }
        s.line[used] = byte
        used += 1usize
    }
    ret ("", false, Invalid)
}

fn same(value: str, expected: str) -> bool {
    if value.len != expected.len { ret false }
    var at = 0usize
    while at < value.len {
        if value[at] != expected[at] { ret false }
        at += 1usize
    }
    ret true
}

fn has_nul(value: str) -> bool {
    var at = 0usize
    while at < value.len {
        if value[at] == 0u8 { ret true }
        at += 1usize
    }
    ret false
}

// Copy valid sequences unchanged. Each malformed byte is one U+FFFD, exactly as the
// lossy UTF-8 iterator specifies, so a split or corrupt sequence never swallows what follows.
fn copy_lossy(dst: []u8, source: str) -> (usize, err) {
    var out = 0usize
    var at = 0usize
    while at < source.len {
        let (decoded, decode_error) = utf8.decode(source, at)
        if decode_error != ok {
            if out + 3usize > dst.len { ret (out, TooLarge) }
            dst[out] = 239u8
            dst[out + 1usize] = 191u8
            dst[out + 2usize] = 189u8
            out += 3usize
            at += 1usize
        } else {
            let width = usize(decoded.width)
            if out + width > dst.len { ret (out, TooLarge) }
            var copied = 0usize
            while copied < width {
                dst[out + copied] = source[at + copied]
                copied += 1usize
            }
            out += width
            at += width
        }
    }
    ret (out, ok)
}

fn add_used(s: *SseReaderState, count: usize) -> err {
    if count > s.data.len - s.event_used { ret TooLarge }
    s.event_used += count
    ret ok
}

fn reset_event(s: *SseReaderState) {
    s.data_len = 0usize
    s.event_len = 0usize
    s.event_used = 0usize
}

fn parse_retry(value: str) -> (u64, bool, err) {
    if value.len == 0usize { ret (0u64, false, ok) }
    var parsed = 0u64
    var at = 0usize
    while at < value.len {
        let byte = value[at]
        if byte < 48u8 || byte > 57u8 { ret (0u64, false, ok) }
        let digit = u64(byte - 48u8)
        if parsed > 1844674407370955161u64 { ret (0u64, false, TooLarge) }
        if parsed == 1844674407370955161u64 && digit > 5u64 { ret (0u64, false, TooLarge) }
        parsed = parsed * 10u64 + digit
        at += 1usize
    }
    ret (parsed, true, ok)
}

// Parse one line and answer whether its blank delimiter has an event to dispatch.
fn process_line(s: *SseReaderState, raw: str) -> (bool, err) {
    var start = 0usize
    if s.first_line {
        s.first_line = false
        if raw.len >= 3usize && raw[0usize] == 239u8 && raw[1usize] == 187u8 && raw[2usize] == 191u8 {
            start = 3usize
        }
    }
    let line = raw[start..raw.len]
    if line.len == 0usize {
        if s.data_len == 0usize {
            reset_event(s)
            ret (false, ok)
        }
        ret (true, ok)
    }
    if line[0usize] == 58u8 { ret (false, ok) }

    var colon = line.len
    var at = 0usize
    while at < line.len {
        if line[at] == 58u8 {
            colon = at
            break
        }
        at += 1usize
    }
    var value_start = colon
    if colon < line.len {
        value_start = colon + 1usize
        if value_start < line.len && line[value_start] == 32u8 { value_start += 1usize }
    }
    let field = line[..colon]
    let value = line[value_start..line.len]

    if same(field, "data") {
        let (written, write_error) = copy_lossy(s.data[s.data_len..], value)
        if write_error != ok { ret (false, write_error) }
        let used_error = add_used(s, written + 1usize)
        if used_error != ok { ret (false, used_error) }
        s.data_len += written
        if s.data_len == s.data.len { ret (false, TooLarge) }
        s.data[s.data_len] = LF
        s.data_len += 1usize
        ret (false, ok)
    }
    if same(field, "event") {
        let (written, write_error) = copy_lossy(s.event, value)
        if write_error != ok { ret (false, write_error) }
        let used_error = add_used(s, written)
        if used_error != ok { ret (false, used_error) }
        s.event_len = written
        ret (false, ok)
    }
    if same(field, "id") {
        if has_nul(value) { ret (false, ok) }
        let (written, write_error) = copy_lossy(s.id, value)
        if write_error != ok { ret (false, write_error) }
        let used_error = add_used(s, written)
        if used_error != ok { ret (false, used_error) }
        s.id_len = written
        s.has_id = true
        ret (false, ok)
    }
    if same(field, "retry") {
        let (retry, valid, retry_error) = parse_retry(value)
        if retry_error != ok { ret (false, retry_error) }
        if valid {
            s.retry_ms = retry
            s.has_retry = true
        }
    }
    ret (false, ok)
}

fn sse_reader(a: *mem.Arena, source: io.Reader, limits: SseLimits) -> (SseReader, err) {
    var reader: SseReader = zero
    let (storage, storage_error) = mem.alloc[SseReaderState](a, 1usize)
    if storage_error != ok { ret (reader, storage_error) }
    let (input, input_error) = mem.alloc[u8](a, INPUT_CAPACITY)
    if input_error != ok { ret (reader, input_error) }
    let (line, line_error) = mem.alloc[u8](a, limits.line_bytes)
    if line_error != ok { ret (reader, line_error) }
    let (data, data_error) = mem.alloc[u8](a, limits.event_bytes)
    if data_error != ok { ret (reader, data_error) }
    let (event, event_error) = mem.alloc[u8](a, limits.event_bytes)
    if event_error != ok { ret (reader, event_error) }
    let (id, id_error) = mem.alloc[u8](a, limits.event_bytes)
    if id_error != ok { ret (reader, id_error) }
    storage[0usize].source = source
    storage[0usize].input = input
    storage[0usize].input_at = 0usize
    storage[0usize].input_len = 0usize
    storage[0usize].line = line
    storage[0usize].data = data
    storage[0usize].event = event
    storage[0usize].id = id
    storage[0usize].data_len = 0usize
    storage[0usize].event_len = 0usize
    storage[0usize].id_len = 0usize
    storage[0usize].event_used = 0usize
    storage[0usize].retry_ms = 0u64
    storage[0usize].has_id = false
    storage[0usize].has_retry = false
    storage[0usize].ended = false
    storage[0usize].line_terminated = false
    storage[0usize].first_line = true
    reader.state = mem.cast[*void](&storage[0usize])
    ret (reader, ok)
}

fn sse_next_err(it: *SseReader) -> (SseEvent, bool, err) {
    var empty: SseEvent = zero
    let s = mem.cast[*SseReaderState](it.state)
    while true {
        let (line, more, line_error) = read_line(s)
        if line_error != ok { ret (empty, false, line_error) }
        if !more { ret (empty, false, ok) }
        let terminated = s.line_terminated
        let (dispatch, parse_error) = process_line(s, line)
        if parse_error != ok { ret (empty, false, parse_error) }
        if !terminated {
            reset_event(s)
            ret (empty, false, ok)
        }
        if dispatch {
            var answer: SseEvent = zero
            answer.event = s.event[..s.event_len]
            answer.data = s.data[..s.data_len - 1usize]
            answer.id = s.id[..s.id_len]
            answer.has_id = s.has_id
            answer.retry_ms = s.retry_ms
            answer.has_retry = s.has_retry
            reset_event(s)
            ret (answer, true, ok)
        }
    }
    ret (empty, false, Invalid)
}

fn sse_state(it: *const SseReader) -> SseState {
    let s = mem.cast[*SseReaderState](it.state)
    ret SseState { id: s.id[..s.id_len], has_id: s.has_id, retry_ms: s.retry_ms, has_retry: s.has_retry }
}
