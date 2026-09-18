// Bounded HTTP message codecs and SSE parsing over one-byte sources, so framing, UTF-8
// sequences and CRLF boundaries are split across reads rather than accidentally relying
// on a whole input buffer.

use e.io
use e.mem
use e.net.http
use e.str

error Failed

type OneByte = struct { data: str, off: usize }
type Repeating = struct { events: usize, emitted: usize, off: usize }

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

fn repeating_read(ctx: *void, dst: []u8) -> (usize, err) {
    let source = mem.cast[*Repeating](ctx)
    if source.emitted == source.events { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    let pattern = "data: x\n\n"
    dst[0usize] = pattern[source.off]
    source.off += 1usize
    if source.off == pattern.len {
        source.off = 0usize
        source.emitted += 1usize
    }
    ret (1usize, ok)
}

fn repeating_reader(value: *Repeating, events: usize) -> io.Reader {
    value.events = events
    value.emitted = 0usize
    value.off = 0usize
    ret io.Reader { ctx: mem.cast[*void](value), read: repeating_read }
}

fn limits(line: usize, event: usize) -> http.SseLimits {
    ret http.SseLimits { line_bytes: line, event_bytes: event }
}

fn message_limits(start: usize, headers: usize, count: usize, body: usize) -> http.Limits {
    ret http.Limits { start_line: start, header_bytes: headers, header_count: count, body_bytes: body }
}

fn main(a: *mem.Arena) -> err {
    // Pipelined requests prove the reader preserves bytes fetched past the first body.
    var request_source: OneByte = zero
    let request_input = "POST /one HTTP/1.1\r\nHost: example.test\r\nContent-Length: 3\r\nX-Mode: one\r\n\r\nabcGET /two HTTP/1.0\r\n\r\n"
    let (request_handle, request_reader_error) = http.reader(a, one_reader(&request_source, request_input), message_limits(64usize, 128usize, 8usize, 16usize))
    if request_reader_error != ok { ret request_reader_error }
    var requests = request_handle
    let (first_request, first_request_error) = http.read_request(a, &requests)
    if first_request_error != ok { ret first_request_error }
    if first_request.method != .Post || first_request.version != .Http11 || !str.eq(first_request.target, "/one") || !str.eq(first_request.body, "abc") { ret Failed }
    let (host, host_found) = http.header(first_request.headers, "host")
    if !host_found || !str.eq(host, "example.test") { ret Failed }
    let (second_request, second_request_error) = http.read_request(a, &requests)
    if second_request_error != ok { ret second_request_error }
    if second_request.method != .Get || second_request.version != .Http10 || !str.eq(second_request.target, "/two") || second_request.body.len != 0usize { ret Failed }
    // Chunk sizes and their CRLFs are all split. Trailers are bounded and consumed.
    var chunk_source: OneByte = zero
    let chunk_input = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Test: yes\r\n\r\n4\r\nWiki\r\n5;note=x\r\npedia\r\n0\r\nX-End: yes\r\n\r\n"
    let (chunk_handle, chunk_reader_error) = http.reader(a, one_reader(&chunk_source, chunk_input), message_limits(64usize, 128usize, 8usize, 16usize))
    if chunk_reader_error != ok { ret chunk_reader_error }
    var chunks = chunk_handle
    let (chunk_response, chunk_response_error) = http.read_response(a, &chunks)
    if chunk_response_error != ok { ret chunk_response_error }
    if chunk_response.version != .Http11 || chunk_response.status != 200u16 || !str.eq(chunk_response.reason, "OK") || !str.eq(chunk_response.body, "Wikipedia") { ret Failed }
    // A close-delimited HTTP/1.0 response remains bounded by body_bytes.
    var close_source: OneByte = zero
    let (close_handle, close_reader_error) = http.reader(a, one_reader(&close_source, "HTTP/1.0 404 Missing\r\n\r\nnope"), message_limits(64usize, 64usize, 4usize, 4usize))
    if close_reader_error != ok { ret close_reader_error }
    var close_reader = close_handle
    let (close_response, close_response_error) = http.read_response(a, &close_reader)
    if close_response_error != ok || close_response.status != 404u16 || !str.eq(close_response.body, "nope") { ret Failed }
    // Independent line, header-count and body bounds fail at their own limits.
    var start_source: OneByte = zero
    let (start_handle, start_reader_error) = http.reader(a, one_reader(&start_source, "GET /long HTTP/1.1\r\n\r\n"), message_limits(8usize, 64usize, 4usize, 0usize))
    if start_reader_error != ok { ret start_reader_error }
    var short_start = start_handle
    let (start_request, start_error) = http.read_request(a, &short_start)
    if start_error != http.TooLarge { ret Failed }

    var count_source: OneByte = zero
    let (count_handle, count_reader_error) = http.reader(a, one_reader(&count_source, "GET / HTTP/1.1\r\nA: 1\r\nB: 2\r\n\r\n"), message_limits(64usize, 64usize, 1usize, 0usize))
    if count_reader_error != ok { ret count_reader_error }
    var short_count = count_handle
    let (count_request, count_error) = http.read_request(a, &short_count)
    if count_error != http.TooLarge { ret Failed }

    var header_source: OneByte = zero
    let (header_handle, header_reader_error) = http.reader(a, one_reader(&header_source, "GET / HTTP/1.1\r\nLong: value\r\n\r\n"), message_limits(64usize, 8usize, 4usize, 0usize))
    if header_reader_error != ok { ret header_reader_error }
    var short_headers = header_handle
    let (header_request, header_error) = http.read_request(a, &short_headers)
    if header_error != http.TooLarge { ret Failed }

    var body_source: OneByte = zero
    let (body_handle, body_reader_error) = http.reader(a, one_reader(&body_source, "POST / HTTP/1.1\r\nContent-Length: 2\r\n\r\nxx"), message_limits(64usize, 64usize, 4usize, 1usize))
    if body_reader_error != ok { ret body_reader_error }
    var short_body = body_handle
    let (body_request, body_error) = http.read_request(a, &short_body)
    if body_error != http.TooLarge { ret Failed }

    // Conflicting length/chunk framing is rejected instead of becoming a smuggling
    // ambiguity, and methods remain case-sensitive tokens.
    var conflict_source: OneByte = zero
    let conflict_input = "POST / HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
    let (conflict_handle, conflict_reader_error) = http.reader(a, one_reader(&conflict_source, conflict_input), message_limits(64usize, 128usize, 4usize, 8usize))
    if conflict_reader_error != ok { ret conflict_reader_error }
    var conflict_reader = conflict_handle
    let (conflict_request, conflict_error) = http.read_request(a, &conflict_reader)
    if conflict_error != http.Invalid { ret Failed }

    var method_source: OneByte = zero
    let (method_handle, method_reader_error) = http.reader(a, one_reader(&method_source, "get / HTTP/1.1\r\n\r\n"), message_limits(64usize, 64usize, 4usize, 0usize))
    if method_reader_error != ok { ret method_reader_error }
    var method_reader = method_handle
    let (method_request, method_error) = http.read_request(a, &method_reader)
    if method_error != http.Unsupported { ret Failed }
    // Writers validate framing and emit deterministic Content-Length/chunk syntax.
    var request_headers: [1]http.Header = zero
    request_headers[0usize] = http.Header { name: "Content-Length", value: "3" }
    var outgoing_request = http.Request { method: .Put, target: "/item", version: .Http11, headers: request_headers[0..], body: "new" }
    let (request_memory, unused_request_sink, request_memory_error) = io.memory_writer(a, 256usize)
    if request_memory_error != ok { ret request_memory_error }
    var request_capture = request_memory
    let request_sink = io.writer(mem.cast[*void](&request_capture), io.memory_write)
    var request_writer = http.writer(request_sink)
    let request_write_error = http.write_request(&request_writer, &outgoing_request)
    if request_write_error != ok || !str.eq(io.memory_bytes(&request_capture), "PUT /item HTTP/1.1\r\nContent-Length: 3\r\n\r\nnew") { ret Failed }

    var response_headers: [1]http.Header = zero
    response_headers[0usize] = http.Header { name: "Transfer-Encoding", value: "chunked" }
    var outgoing_response = http.Response { version: .Http11, status: 200u16, reason: "", headers: response_headers[0..], body: "hello" }
    let (response_memory, unused_response_sink, response_memory_error) = io.memory_writer(a, 256usize)
    if response_memory_error != ok { ret response_memory_error }
    var response_capture = response_memory
    let response_sink = io.writer(mem.cast[*void](&response_capture), io.memory_write)
    var response_writer = http.writer(response_sink)
    let response_write_error = http.write_response(&response_writer, &outgoing_response)
    if response_write_error != ok || !str.eq(io.memory_bytes(&response_capture), "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n") { ret Failed }
    if !str.eq(http.reason(503u16), "Service Unavailable") || http.reason(799u16).len != 0usize { ret Failed }

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

    // Ten thousand events are generated rather than stored. Construction is the only
    // allocation: every event reuses the same buffers and leaves the arena mark fixed.
    var repeated_source: Repeating = zero
    let (repeated, repeated_error) = http.sse_reader(a, repeating_reader(&repeated_source, 10000usize), limits(16usize, 16usize))
    if repeated_error != ok { ret repeated_error }
    var repeated_reader = repeated
    let steady = mem.mark(a)
    var count = 0usize
    while count < 10000usize {
        let (repeated_event, repeated_present, repeated_next_error) = http.sse_next_err(&repeated_reader)
        if repeated_next_error != ok || !repeated_present || !str.eq(repeated_event.data, "x") { ret Failed }
        if mem.mark(a) != steady { ret Failed }
        count += 1usize
    }
    let (repeated_end, repeated_more, repeated_end_error) = http.sse_next_err(&repeated_reader)
    if repeated_end_error != ok || repeated_more || mem.mark(a) != steady { ret Failed }
    ret ok
}
