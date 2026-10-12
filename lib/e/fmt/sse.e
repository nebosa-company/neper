// Server-Sent Events (the `text/event-stream` format of the HTML Living Standard, section 9.2), read incrementally:
// `next` takes the bytes received so far and a position and returns the next complete event with the position after
// it, or reports that the stream has not yet delivered a whole event (nothing is consumed then: the caller keeps the
// bytes from `at` and calls again when more arrive). Lines end in LF, CR or CRLF; a line starting with `:` is a
// comment; `event`, `data`, `id` and `retry` are the fields (one optional space after the colon is dropped, other
// field names ignored); several `data` lines are joined with LF; an `id` containing NUL is ignored and `retry` must be
// digits only. An event with no `data` line is not dispatched. A UTF-8 byte order mark at the very start of the
// stream is the caller's to skip (`skip_bom`). An event of more than 128 data lines, or a gathered event of more than
// a megabyte, is `TooLarge`.
//
// Memory: strings of an event point into `data`, except joined data lines, which live in the arena.
use e.mem
use e.str

error TooLarge

const MAX_EVENT: usize = 1048576usize
const MAX_LINES: usize = 128usize

type Event = struct { kind: str, data: str, id: str, has_id: bool, retry: i64, has_retry: bool }

// The position after a UTF-8 byte order mark at the start of `data`, else 0.
fn skip_bom(data: []const u8) -> usize {
    if data.len >= 3usize && data[0usize] == 239u8 && data[1usize] == 187u8 && data[2usize] == 191u8 { ret 3usize }
    ret 0usize
}

// The line starting at `at`: where its text ends, where the next line starts, and whether its terminator is certain
// (a CR at the very end of the data might be the first half of a CRLF).
fn line_end(data: []const u8, at: usize) -> (usize, usize, bool) {
    var i = at
    while i < data.len {
        let c = data[i]
        if c == 10u8 { ret (i, i + 1usize, true) }
        if c == 13u8 {
            if i + 1usize >= data.len { ret (i, i + 1usize, false) }
            if data[i + 1usize] == 10u8 { ret (i, i + 2usize, true) }
            ret (i, i + 1usize, true)
        }
        i += 1usize
    }
    ret (i, i, false)
}

fn has_nul(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] == 0u8 { ret true }
        i += 1usize
    }
    ret false
}

// The next dispatched event of `data` from `at`: the event, the position after it, whether a whole event was there,
// and an error. Comments and events without data are skipped over.
fn next(a: *mem.Arena, data: []const u8, at: usize) -> (Event, usize, bool, err) {
    var ev: Event = zero
    var pos = at
    var starts: [128]usize = zero
    var ends: [128]usize = zero
    var lines = 0usize
    var total = 0usize
    var kind = ""
    var id = ""
    var has_id = false
    var retry = 0i64
    var has_retry = false
    var scanning = true
    while scanning {
        let (stop, after, complete) = line_end(data, pos)
        if !complete { ret (ev, at, false, ok) }
        if after - at > MAX_EVENT { ret (ev, at, false, TooLarge) }
        if stop == pos {
            // A blank line dispatches what has been gathered, when there is data; otherwise it only resets.
            pos = after
            if lines > 0usize {
                scanning = false
            } else {
                kind = ""
                id = ""
                has_id = false
                retry = 0i64
                has_retry = false
            }
        } else {
            let line_start = pos
            let line = data[pos..stop]
            pos = after
            if line[0usize] != 58u8 {
                var colon = line.len
                var k = 0usize
                while k < line.len {
                    if line[k] == 58u8 {
                        colon = k
                        k = line.len
                    } else {
                        k += 1usize
                    }
                }
                let field = line[0usize..colon]
                var value_at = line.len
                if colon < line.len { value_at = colon + 1usize }
                if value_at < line.len && line[value_at] == 32u8 { value_at += 1usize }
                let value = line[value_at..line.len]
                if str.eq(field, "data") {
                    if lines >= MAX_LINES { ret (ev, at, false, TooLarge) }
                    starts[lines] = line_start + value_at
                    ends[lines] = stop
                    total += stop - (line_start + value_at) + 1usize
                    if total > MAX_EVENT { ret (ev, at, false, TooLarge) }
                    lines += 1usize
                } else if str.eq(field, "event") {
                    kind = value
                } else if str.eq(field, "id") {
                    if !has_nul(value) {
                        id = value
                        has_id = true
                    }
                } else if str.eq(field, "retry") {
                    var digits = value.len > 0usize
                    var n = 0i64
                    var j = 0usize
                    while j < value.len {
                        if value[j] < 48u8 || value[j] > 57u8 {
                            digits = false
                        } else if n < 100000000000i64 {
                            n = n * 10i64 + i64(value[j] - 48u8)
                        }
                        j += 1usize
                    }
                    if digits {
                        retry = n
                        has_retry = true
                    }
                }
            }
        }
    }
    if lines == 1usize {
        ev.data = data[starts[0usize]..ends[0usize]]
    } else {
        let (buffer, buffer_error) = mem.alloc[u8](a, total + 1usize)
        if buffer_error != ok { ret (ev, at, false, buffer_error) }
        var n = 0usize
        var l = 0usize
        while l < lines {
            if l > 0usize {
                buffer[n] = 10u8
                n += 1usize
            }
            var i = starts[l]
            while i < ends[l] {
                buffer[n] = data[i]
                n += 1usize
                i += 1usize
            }
            l += 1usize
        }
        ev.data = buffer[0usize..n]
    }
    ev.kind = kind
    ev.id = id
    ev.has_id = has_id
    ev.retry = retry
    ev.has_retry = has_retry
    ret (ev, pos, true, ok)
}
