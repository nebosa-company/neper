// The delivered e.net.http slice: bounded SSE parsing over a one-byte source, so every
// UTF-8 sequence and CRLF boundary is split across reads rather than accidentally relying
// on a whole input buffer.

use e.io
use e.mem
use e.net.http
use e.str

error Failed

type OneByte = struct { data: str, off: usize }

fn one_read(ctx: *void, dst: []u8) -> (usize, err) {
    let source = mem.cast[*OneByte](ctx)
    if source.off == source.data.len { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    dst[0usize] = source.data[source.off]
    source.off += 1usize
    ret (1usize, ok)
}

fn one_reader(value: *OneByte, text: str) -> io.Reader {
    value.data = text
    value.off = 0usize
    ret io.Reader { ctx: mem.cast[*void](value), read: one_read }
}

fn limits(line: usize, event: usize) -> http.SseLimits {
    ret http.SseLimits { line_bytes: line, event_bytes: event }
}

fn main(a: *mem.Arena) -> err {
    // BOM, comment, all three line endings, repeated data and retained id/retry state.
    var first_source: OneByte = zero
    let first_input = "\xEF\xBB\xBF: ignored\rdata: first\r\ndata: second\nevent: update\rid: 7\nretry: 1500\n\n"
    let (first, first_error) = http.sse_reader(a, one_reader(&first_source, first_input), limits(64usize, 64usize))
    if first_error != ok { ret first_error }
    var first_reader = first
    let (event, present, event_error) = http.sse_next_err(&first_reader)
    if event_error != ok || !present { ret Failed }
    if !str.eq(event.event, "update") || !str.eq(event.data, "first\nsecond") { ret Failed }
    if !event.has_id || !str.eq(event.id, "7") { ret Failed }
    if !event.has_retry || event.retry_ms != 1500u64 { ret Failed }
    let state = http.sse_state(&first_reader)
    if !state.has_id || !str.eq(state.id, "7") || !state.has_retry || state.retry_ms != 1500u64 { ret Failed }
    let (done_event, done, done_error) = http.sse_next_err(&first_reader)
    if done_error != ok || done { ret Failed }

    // Empty id resets the retained value. Invalid retry and an id containing NUL are
    // ignored; malformed UTF-8 becomes U+FFFD without swallowing the following byte.
    var lossy_source: OneByte = zero
    let lossy_input = "id:\nretry: nope\nid: bad\x00id\ndata: x\xFFy\n\n"
    let (lossy, lossy_error) = http.sse_reader(a, one_reader(&lossy_source, lossy_input), limits(64usize, 64usize))
    if lossy_error != ok { ret lossy_error }
    var lossy_reader = lossy
    let (lossy_event, lossy_present, lossy_next_error) = http.sse_next_err(&lossy_reader)
    if lossy_next_error != ok || !lossy_present { ret Failed }
    if !str.eq(lossy_event.data, "x\xEF\xBF\xBDy") { ret Failed }
    if !lossy_event.has_id || lossy_event.id.len != 0usize || lossy_event.has_retry { ret Failed }

    // A block without data still updates state; EOF never dispatches an unterminated event.
    var state_source: OneByte = zero
    let (stateful, stateful_error) = http.sse_reader(a, one_reader(&state_source, "id: kept\nretry: 25\n\ndata: lost"), limits(64usize, 64usize))
    if stateful_error != ok { ret stateful_error }
    var stateful_reader = stateful
    let (state_event, state_present, state_error) = http.sse_next_err(&stateful_reader)
    if state_error != ok || state_present { ret Failed }
    let retained = http.sse_state(&stateful_reader)
    if !retained.has_id || !str.eq(retained.id, "kept") || !retained.has_retry || retained.retry_ms != 25u64 { ret Failed }

    // Both independent bounds fail where they are crossed. Decimal overflow is a size
    // failure too; a non-decimal retry above was merely ignored.
    var line_source: OneByte = zero
    let (line_reader, line_reader_error) = http.sse_reader(a, one_reader(&line_source, "data: x\n\n"), limits(4usize, 64usize))
    if line_reader_error != ok { ret line_reader_error }
    var short_line_reader = line_reader
    let (line_event, line_present, line_error) = http.sse_next_err(&short_line_reader)
    if line_error != http.TooLarge || line_present { ret Failed }

    var event_source: OneByte = zero
    let (event_reader, event_reader_error) = http.sse_reader(a, one_reader(&event_source, "data: four\n\n"), limits(64usize, 4usize))
    if event_reader_error != ok { ret event_reader_error }
    var small_event_reader = event_reader
    let (large_event, large_present, large_error) = http.sse_next_err(&small_event_reader)
    if large_error != http.TooLarge || large_present { ret Failed }

    var retry_source: OneByte = zero
    let (retry_reader, retry_reader_error) = http.sse_reader(a, one_reader(&retry_source, "retry: 18446744073709551616\n"), limits(64usize, 64usize))
    if retry_reader_error != ok { ret retry_reader_error }
    var overflow_reader = retry_reader
    let (retry_event, retry_present, retry_error) = http.sse_next_err(&overflow_reader)
    if retry_error != http.TooLarge || retry_present { ret Failed }
    ret ok
}
