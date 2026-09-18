// Bounded HTTP/1.0 and HTTP/1.1 message parsing/writing plus the event-stream body
// format. The plain full-body client owns one connection per request; controlled
// response streaming and TLS remain planned.

use e.io
use e.mem
use e.net
use e.text.utf8

type Method = enum u8 { Get, Head, Post, Put, Patch, Delete, Options, Connect, Trace }
type Version = enum u8 { Http10, Http11 }
type Header = struct { name: str, value: str }
type Request = struct { method: Method, target: str, version: Version, headers: []const Header, body: []const u8 }
type Response = struct { version: Version, status: u16, reason: str, headers: []const Header, body: []const u8 }
type Limits = struct { start_line: usize, header_bytes: usize, header_count: usize, body_bytes: usize }
type Reader = struct { state: *void }
type Writer = struct { sink: io.Writer }

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

type ReaderState = struct {
    source: io.Reader,
    input: []u8,
    input_at: usize,
    input_len: usize,
    line: []u8,
    limits: Limits,
}

fn ascii_lower(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

fn same_ascii(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if ascii_lower(left[at]) != ascii_lower(right[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn copy_text(a: *mem.Arena, value: str) -> (str, err) {
    if value.len == 0usize { ret ("", ok) }
    let (out, allocation_error) = mem.alloc[u8](a, value.len)
    if allocation_error != ok { ret ("", allocation_error) }
    mem.copy[u8](out, value)
    ret (out, ok)
}

fn http_take(s: *ReaderState) -> (u8, bool, err) {
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

fn http_line(s: *ReaderState, limit: usize) -> (str, err) {
    var used = 0usize
    while true {
        let (byte, more, take_error) = http_take(s)
        if take_error != ok { ret ("", take_error) }
        if !more { ret ("", Invalid) }
        if byte == LF { ret ("", Invalid) }
        if byte == CR {
            let (next, next_more, next_error) = http_take(s)
            if next_error != ok { ret ("", next_error) }
            if !next_more || next != LF { ret ("", Invalid) }
            ret (s.line[..used], ok)
        }
        if used == limit || used == s.line.len { ret ("", TooLarge) }
        s.line[used] = byte
        used += 1usize
    }
    ret ("", Invalid)
}

fn token_byte(byte: u8) -> bool {
    if byte >= 48u8 && byte <= 57u8 { ret true }
    if byte >= 65u8 && byte <= 90u8 { ret true }
    if byte >= 97u8 && byte <= 122u8 { ret true }
    ret byte == 33u8 || byte == 35u8 || byte == 36u8 || byte == 37u8 || byte == 38u8 || byte == 39u8 || byte == 42u8 || byte == 43u8 || byte == 45u8 || byte == 46u8 || byte == 94u8 || byte == 95u8 || byte == 96u8 || byte == 124u8 || byte == 126u8
}

fn valid_token(value: str) -> bool {
    if value.len == 0usize { ret false }
    var at = 0usize
    while at < value.len {
        if !token_byte(value[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn valid_header_value(value: str) -> bool {
    var at = 0usize
    while at < value.len {
        let byte = value[at]
        if (byte < 32u8 && byte != 9u8) || byte == 127u8 { ret false }
        at += 1usize
    }
    ret true
}

fn parse_version(value: str) -> (Version, err) {
    if value.len == 8usize && value[7usize] == 48u8 { ret (.Http10, ok) }
    if value.len == 8usize && value[7usize] == 49u8 { ret (.Http11, ok) }
    ret (.Http11, Invalid)
}

fn valid_version_prefix(value: str) -> bool {
    if value.len != 8usize { ret false }
    ret value[0usize] == 72u8 && value[1usize] == 84u8 && value[2usize] == 84u8 && value[3usize] == 80u8 && value[4usize] == 47u8 && value[5usize] == 49u8 && value[6usize] == 46u8
}

fn checked_version(value: str) -> (Version, err) {
    if !valid_version_prefix(value) { ret (.Http11, Invalid) }
    let (version, version_error) = parse_version(value)
    ret (version, version_error)
}

fn parse_method(value: str) -> (Method, err) {
    if same(value, "GET") { ret (.Get, ok) }
    if same(value, "HEAD") { ret (.Head, ok) }
    if same(value, "POST") { ret (.Post, ok) }
    if same(value, "PUT") { ret (.Put, ok) }
    if same(value, "PATCH") { ret (.Patch, ok) }
    if same(value, "DELETE") { ret (.Delete, ok) }
    if same(value, "OPTIONS") { ret (.Options, ok) }
    if same(value, "CONNECT") { ret (.Connect, ok) }
    if same(value, "TRACE") { ret (.Trace, ok) }
    ret (.Get, Unsupported)
}

fn method_text(value: Method) -> str {
    if value == .Get { ret "GET" }
    if value == .Head { ret "HEAD" }
    if value == .Post { ret "POST" }
    if value == .Put { ret "PUT" }
    if value == .Patch { ret "PATCH" }
    if value == .Delete { ret "DELETE" }
    if value == .Options { ret "OPTIONS" }
    if value == .Connect { ret "CONNECT" }
    ret "TRACE"
}

fn version_text(value: Version) -> str {
    if value == .Http10 { ret "HTTP/1.0" }
    ret "HTTP/1.1"
}

fn parse_decimal(value: str) -> (usize, err) {
    if value.len == 0usize { ret (0usize, Invalid) }
    var parsed = 0u64
    var at = 0usize
    while at < value.len {
        let byte = value[at]
        if byte < 48u8 || byte > 57u8 { ret (0usize, Invalid) }
        let digit = u64(byte - 48u8)
        if parsed > 1844674407370955161u64 || (parsed == 1844674407370955161u64 && digit > 5u64) { ret (0usize, TooLarge) }
        parsed = parsed * 10u64 + digit
        at += 1usize
    }
    ret (usize(parsed), ok)
}

fn parse_hex(value: str) -> (usize, err) {
    var end = 0usize
    while end < value.len && value[end] != 59u8 { end += 1usize }
    if end == 0usize { ret (0usize, Invalid) }
    var parsed = 0u64
    var at = 0usize
    while at < end {
        let byte = ascii_lower(value[at])
        var digit = 16u8
        if byte >= 48u8 && byte <= 57u8 { digit = byte - 48u8 }
        if byte >= 97u8 && byte <= 102u8 { digit = byte - 97u8 + 10u8 }
        if digit == 16u8 { ret (0usize, Invalid) }
        if parsed > 1152921504606846975u64 { ret (0usize, TooLarge) }
        parsed = parsed * 16u64 + u64(digit)
        at += 1usize
    }
    ret (usize(parsed), ok)
}

fn read_headers(a: *mem.Arena, s: *ReaderState) -> ([]const Header, usize, bool, err) {
    var empty: []const Header = zero
    let (storage, storage_error) = mem.alloc[Header](a, s.limits.header_count)
    if storage_error != ok { ret (empty, 0usize, false, storage_error) }
    var count = 0usize
    var bytes = 0usize
    var body_length = 0usize
    var has_length = false
    var chunked = false
    while true {
        let (line, line_error) = http_line(s, s.limits.header_bytes)
        if line_error != ok { ret (empty, 0usize, false, line_error) }
        if line.len == 0usize {
            if has_length && chunked { ret (empty, 0usize, false, Invalid) }
            ret (storage[..count], body_length, chunked, ok)
        }
        if line.len + 2usize > s.limits.header_bytes - bytes { ret (empty, 0usize, false, TooLarge) }
        bytes += line.len + 2usize
        if count == s.limits.header_count { ret (empty, 0usize, false, TooLarge) }
        var colon = 0usize
        while colon < line.len && line[colon] != 58u8 { colon += 1usize }
        if colon == line.len || !valid_token(line[..colon]) { ret (empty, 0usize, false, Invalid) }
        var first = colon + 1usize
        while first < line.len && (line[first] == 32u8 || line[first] == 9u8) { first += 1usize }
        var last = line.len
        while last > first && (line[last - 1usize] == 32u8 || line[last - 1usize] == 9u8) { last -= 1usize }
        let raw_value = line[first..last]
        if !valid_header_value(raw_value) { ret (empty, 0usize, false, Invalid) }
        let (name, name_error) = copy_text(a, line[..colon])
        if name_error != ok { ret (empty, 0usize, false, name_error) }
        let (value, value_error) = copy_text(a, raw_value)
        if value_error != ok { ret (empty, 0usize, false, value_error) }
        storage[count] = Header { name: name, value: value }
        count += 1usize
        if same_ascii(name, "Content-Length") {
            let (length, length_error) = parse_decimal(value)
            if length_error != ok { ret (empty, 0usize, false, length_error) }
            if has_length && length != body_length { ret (empty, 0usize, false, Invalid) }
            body_length = length
            has_length = true
        }
        if same_ascii(name, "Transfer-Encoding") {
            if !same_ascii(value, "chunked") || chunked { ret (empty, 0usize, false, Unsupported) }
            chunked = true
        }
    }
    ret (empty, 0usize, false, Invalid)
}

fn exact_bytes(s: *ReaderState, dst: []u8) -> err {
    var at = 0usize
    while at < dst.len {
        let (byte, more, take_error) = http_take(s)
        if take_error != ok { ret take_error }
        if !more { ret Invalid }
        dst[at] = byte
        at += 1usize
    }
    ret ok
}

fn expect_crlf(s: *ReaderState) -> err {
    let (cr, cr_more, cr_error) = http_take(s)
    if cr_error != ok { ret cr_error }
    let (lf, lf_more, lf_error) = http_take(s)
    if lf_error != ok { ret lf_error }
    if !cr_more || !lf_more || cr != CR || lf != LF { ret Invalid }
    ret ok
}

fn read_chunked(a: *mem.Arena, s: *ReaderState) -> ([]const u8, err) {
    var empty: []const u8 = zero
    let (body, allocation_error) = mem.alloc[u8](a, s.limits.body_bytes)
    if allocation_error != ok { ret (empty, allocation_error) }
    var used = 0usize
    while true {
        let (size_line, line_error) = http_line(s, s.limits.start_line)
        if line_error != ok { ret (empty, line_error) }
        let (size, size_error) = parse_hex(size_line)
        if size_error != ok { ret (empty, size_error) }
        if size == 0usize {
            var trailer_bytes = 0usize
            var trailer_count = 0usize
            while true {
                let (trailer, trailer_error) = http_line(s, s.limits.header_bytes)
                if trailer_error != ok { ret (empty, trailer_error) }
                if trailer.len == 0usize { ret (body[..used], ok) }
                if trailer.len + 2usize > s.limits.header_bytes - trailer_bytes { ret (empty, TooLarge) }
                trailer_bytes += trailer.len + 2usize
                trailer_count += 1usize
                if trailer_count > s.limits.header_count { ret (empty, TooLarge) }
                var colon = 0usize
                while colon < trailer.len && trailer[colon] != 58u8 { colon += 1usize }
                if colon == trailer.len || !valid_token(trailer[..colon]) { ret (empty, Invalid) }
            }
        }
        if size > s.limits.body_bytes - used { ret (empty, TooLarge) }
        let copy_error = exact_bytes(s, body[used..used + size])
        if copy_error != ok { ret (empty, copy_error) }
        used += size
        let ending_error = expect_crlf(s)
        if ending_error != ok { ret (empty, ending_error) }
    }
    ret (empty, Invalid)
}

fn read_body(a: *mem.Arena, s: *ReaderState, length: usize, chunked: bool, until_end: bool) -> ([]const u8, err) {
    var empty: []const u8 = zero
    if chunked {
        let (body, body_error) = read_chunked(a, s)
        ret (body, body_error)
    }
    if !until_end {
        if length > s.limits.body_bytes { ret (empty, TooLarge) }
        if length == 0usize { ret (empty, ok) }
        let (body, allocation_error) = mem.alloc[u8](a, length)
        if allocation_error != ok { ret (empty, allocation_error) }
        let read_error = exact_bytes(s, body)
        if read_error != ok { ret (empty, read_error) }
        ret (body, ok)
    }
    let (body, allocation_error) = mem.alloc[u8](a, s.limits.body_bytes)
    if allocation_error != ok { ret (empty, allocation_error) }
    var used = 0usize
    while true {
        let (byte, more, take_error) = http_take(s)
        if take_error != ok { ret (empty, take_error) }
        if !more { ret (body[..used], ok) }
        if used == body.len { ret (empty, TooLarge) }
        body[used] = byte
        used += 1usize
    }
    ret (empty, Invalid)
}

fn reader(a: *mem.Arena, source: io.Reader, limits: Limits) -> (Reader, err) {
    var out: Reader = zero
    let start = mem.mark(a)
    let (storage, storage_error) = mem.alloc[ReaderState](a, 1usize)
    if storage_error != ok { ret (out, storage_error) }
    let (input, input_error) = mem.alloc[u8](a, INPUT_CAPACITY)
    if input_error != ok {
        mem.reset(a, start)
        ret (out, input_error)
    }
    var line_capacity = limits.start_line
    if limits.header_bytes > line_capacity { line_capacity = limits.header_bytes }
    let (line, line_error) = mem.alloc[u8](a, line_capacity)
    if line_error != ok {
        mem.reset(a, start)
        ret (out, line_error)
    }
    storage[0usize].source = source
    storage[0usize].input = input
    storage[0usize].input_at = 0usize
    storage[0usize].input_len = 0usize
    storage[0usize].line = line
    storage[0usize].limits = limits
    out.state = mem.cast[*void](&storage[0usize])
    ret (out, ok)
}

fn writer(sink: io.Writer) -> Writer {
    ret Writer { sink: sink }
}

fn read_request(a: *mem.Arena, r: *Reader) -> (Request, err) {
    var out: Request = zero
    let mark = mem.mark(a)
    let s = mem.cast[*ReaderState](r.state)
    let (line, line_error) = http_line(s, s.limits.start_line)
    if line_error != ok { ret (out, line_error) }
    var first_space = 0usize
    while first_space < line.len && line[first_space] != 32u8 { first_space += 1usize }
    var second_space = first_space + 1usize
    while second_space < line.len && line[second_space] != 32u8 { second_space += 1usize }
    if first_space == 0usize || second_space >= line.len || second_space == first_space + 1usize { ret (out, Invalid) }
    let (method, method_error) = parse_method(line[..first_space])
    if method_error != ok { ret (out, method_error) }
    let (version, version_error) = checked_version(line[second_space + 1usize..])
    if version_error != ok { ret (out, version_error) }
    if !valid_start_value(line[first_space + 1usize..second_space]) { ret (out, Invalid) }
    let (target_text, target_error) = copy_text(a, line[first_space + 1usize..second_space])
    if target_error != ok {
        mem.reset(a, mark)
        ret (out, target_error)
    }
    let (headers, length, chunked, headers_error) = read_headers(a, s)
    if headers_error != ok {
        mem.reset(a, mark)
        ret (out, headers_error)
    }
    let (body, body_error) = read_body(a, s, length, chunked, false)
    if body_error != ok {
        mem.reset(a, mark)
        ret (out, body_error)
    }
    out = Request { method: method, target: target_text, version: version, headers: headers, body: body }
    ret (out, ok)
}

fn no_response_body(status: u16) -> bool {
    ret (status >= 100u16 && status < 200u16) || status == 204u16 || status == 304u16
}

fn read_response_for(a: *mem.Arena, r: *Reader, suppress_body: bool) -> (Response, err) {
    var out: Response = zero
    let mark = mem.mark(a)
    let s = mem.cast[*ReaderState](r.state)
    let (line, line_error) = http_line(s, s.limits.start_line)
    if line_error != ok { ret (out, line_error) }
    if line.len < 13usize || line[8usize] != 32u8 || line[12usize] != 32u8 { ret (out, Invalid) }
    let (version, version_error) = checked_version(line[..8usize])
    if version_error != ok { ret (out, version_error) }
    if line[9usize] < 48u8 || line[9usize] > 57u8 || line[10usize] < 48u8 || line[10usize] > 57u8 || line[11usize] < 48u8 || line[11usize] > 57u8 { ret (out, Invalid) }
    let status = u16(line[9usize] - 48u8) * 100u16 + u16(line[10usize] - 48u8) * 10u16 + u16(line[11usize] - 48u8)
    let (reason_text, reason_error) = copy_text(a, line[13usize..])
    if reason_error != ok {
        mem.reset(a, mark)
        ret (out, reason_error)
    }
    let (headers, length, chunked, headers_error) = read_headers(a, s)
    if headers_error != ok {
        mem.reset(a, mark)
        ret (out, headers_error)
    }
    var body: []const u8 = zero
    if !no_response_body(status) && !suppress_body {
        let (read, body_error) = read_body(a, s, length, chunked, !chunked && !has_header(headers, "Content-Length"))
        if body_error != ok {
            mem.reset(a, mark)
            ret (out, body_error)
        }
        body = read
    }
    out = Response { version: version, status: status, reason: reason_text, headers: headers, body: body }
    ret (out, ok)
}

fn read_response(a: *mem.Arena, r: *Reader) -> (Response, err) {
    let (response, response_error) = read_response_for(a, r, false)
    ret (response, response_error)
}

fn request(a: *mem.Arena, endpoint: net.Endpoint, req: *const Request, limits: Limits) -> (Response, err) {
    var out: Response = zero
    // CONNECT changes a successful connection into a byte tunnel, which a full-body
    // response cannot represent. The later stream surface owns that protocol switch.
    if req.method == .Connect { ret (out, Unsupported) }
    let (opened, connect_error) = net.tcp_connect(endpoint)
    if connect_error != ok { ret (out, connect_error) }
    var connection = opened
    defer let _ = net.close(connection)

    var sink = net.writer(&connection)
    var encoder = writer(sink)
    let write_error = write_request(&encoder, req)
    if write_error != ok { ret (out, write_error) }

    let mark = mem.mark(a)
    var source = net.reader(&connection)
    let (created, reader_error) = reader(a, source, limits)
    if reader_error != ok {
        mem.reset(a, mark)
        ret (out, reader_error)
    }
    var decoder = created
    let (response, response_error) = read_response_for(a, &decoder, req.method == .Head)
    if response_error != ok {
        mem.reset(a, mark)
        ret (out, response_error)
    }
    ret (response, ok)
}

fn has_header(headers: []const Header, name: str) -> bool {
    let (value, found) = header(headers, name)
    ret found
}

fn header(headers: []const Header, name: str) -> (str, bool) {
    var at = 0usize
    while at < headers.len {
        if same_ascii(headers[at].name, name) { ret (headers[at].value, true) }
        at += 1usize
    }
    ret ("", false)
}

fn write_decimal(sink: *io.Writer, value: usize) -> err {
    var digits: [20]u8 = zero
    var at = digits.len
    var rest = value
    while true {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest /= 10usize
        if rest == 0usize { ret io.write_all(sink, digits[at..]) }
    }
    ret Invalid
}

fn write_hex(sink: *io.Writer, value: usize) -> err {
    var digits: [16]u8 = zero
    var at = digits.len
    var rest = value
    while true {
        at -= 1usize
        let digit = u8(rest % 16usize)
        if digit < 10u8 { digits[at] = digit + 48u8 } else { digits[at] = digit - 10u8 + 97u8 }
        rest /= 16usize
        if rest == 0usize { ret io.write_all(sink, digits[at..]) }
    }
    ret Invalid
}

fn framing(headers: []const Header) -> (usize, bool, bool, err) {
    var length = 0usize
    var has_length = false
    var chunked = false
    var at = 0usize
    while at < headers.len {
        let h = headers[at]
        if !valid_token(h.name) || !valid_header_value(h.value) { ret (0usize, false, false, Invalid) }
        if same_ascii(h.name, "Content-Length") {
            let (parsed, parse_error) = parse_decimal(h.value)
            if parse_error != ok { ret (0usize, false, false, parse_error) }
            if has_length && parsed != length { ret (0usize, false, false, Invalid) }
            length = parsed
            has_length = true
        }
        if same_ascii(h.name, "Transfer-Encoding") {
            if !same_ascii(h.value, "chunked") || chunked { ret (0usize, false, false, Unsupported) }
            chunked = true
        }
        at += 1usize
    }
    if has_length && chunked { ret (0usize, false, false, Invalid) }
    ret (length, has_length, chunked, ok)
}

fn write_headers(sink: *io.Writer, headers: []const Header) -> err {
    var at = 0usize
    while at < headers.len {
        try io.write_all(sink, headers[at].name)
        try io.write_all(sink, ": ")
        try io.write_all(sink, headers[at].value)
        try io.write_all(sink, "\r\n")
        at += 1usize
    }
    ret ok
}

fn write_body(sink: *io.Writer, headers: []const Header, body: []const u8) -> err {
    let (length, has_length, chunked, frame_error) = framing(headers)
    if frame_error != ok { ret frame_error }
    if has_length && length != body.len { ret Invalid }
    try write_headers(sink, headers)
    if !has_length && !chunked {
        try io.write_all(sink, "Content-Length: ")
        try write_decimal(sink, body.len)
        try io.write_all(sink, "\r\n")
    }
    try io.write_all(sink, "\r\n")
    if chunked {
        if body.len > 0usize {
            try write_hex(sink, body.len)
            try io.write_all(sink, "\r\n")
            try io.write_all(sink, body)
            try io.write_all(sink, "\r\n")
        }
        ret io.write_all(sink, "0\r\n\r\n")
    }
    ret io.write_all(sink, body)
}

fn valid_start_value(value: str) -> bool {
    if value.len == 0usize { ret false }
    var at = 0usize
    while at < value.len {
        if value[at] <= 32u8 || value[at] == 127u8 { ret false }
        at += 1usize
    }
    ret true
}

fn write_request(w: *Writer, req: *const Request) -> err {
    if !valid_start_value(req.target) { ret Invalid }
    try io.write_all(&w.sink, method_text(req.method))
    try io.write_all(&w.sink, " ")
    try io.write_all(&w.sink, req.target)
    try io.write_all(&w.sink, " ")
    try io.write_all(&w.sink, version_text(req.version))
    try io.write_all(&w.sink, "\r\n")
    ret write_body(&w.sink, req.headers, req.body)
}

fn write_response(w: *Writer, response: *const Response) -> err {
    if response.status < 100u16 || response.status > 999u16 { ret Invalid }
    if no_response_body(response.status) && response.body.len != 0usize { ret Invalid }
    if !valid_header_value(response.reason) { ret Invalid }
    try io.write_all(&w.sink, version_text(response.version))
    try io.write_all(&w.sink, " ")
    try write_decimal(&w.sink, usize(response.status))
    try io.write_all(&w.sink, " ")
    var phrase = response.reason
    if phrase.len == 0usize { phrase = reason(response.status) }
    try io.write_all(&w.sink, phrase)
    try io.write_all(&w.sink, "\r\n")
    if no_response_body(response.status) {
        let (length, has_length, chunked, frame_error) = framing(response.headers)
        if frame_error != ok { ret frame_error }
        if chunked { ret Invalid }
        if response.status != 304u16 && has_length && length != 0usize { ret Invalid }
        try write_headers(&w.sink, response.headers)
        ret io.write_all(&w.sink, "\r\n")
    }
    ret write_body(&w.sink, response.headers, response.body)
}

fn reason(status: u16) -> str {
    if status == 100u16 { ret "Continue" }
    if status == 101u16 { ret "Switching Protocols" }
    if status == 200u16 { ret "OK" }
    if status == 201u16 { ret "Created" }
    if status == 202u16 { ret "Accepted" }
    if status == 204u16 { ret "No Content" }
    if status == 206u16 { ret "Partial Content" }
    if status == 300u16 { ret "Multiple Choices" }
    if status == 301u16 { ret "Moved Permanently" }
    if status == 302u16 { ret "Found" }
    if status == 304u16 { ret "Not Modified" }
    if status == 307u16 { ret "Temporary Redirect" }
    if status == 308u16 { ret "Permanent Redirect" }
    if status == 400u16 { ret "Bad Request" }
    if status == 401u16 { ret "Unauthorized" }
    if status == 403u16 { ret "Forbidden" }
    if status == 404u16 { ret "Not Found" }
    if status == 405u16 { ret "Method Not Allowed" }
    if status == 408u16 { ret "Request Timeout" }
    if status == 409u16 { ret "Conflict" }
    if status == 410u16 { ret "Gone" }
    if status == 411u16 { ret "Length Required" }
    if status == 413u16 { ret "Content Too Large" }
    if status == 414u16 { ret "URI Too Long" }
    if status == 415u16 { ret "Unsupported Media Type" }
    if status == 418u16 { ret "I'm a Teapot" }
    if status == 422u16 { ret "Unprocessable Content" }
    if status == 426u16 { ret "Upgrade Required" }
    if status == 429u16 { ret "Too Many Requests" }
    if status == 500u16 { ret "Internal Server Error" }
    if status == 501u16 { ret "Not Implemented" }
    if status == 502u16 { ret "Bad Gateway" }
    if status == 503u16 { ret "Service Unavailable" }
    if status == 504u16 { ret "Gateway Timeout" }
    ret ""
}

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
    var out: SseReader = zero
    let (storage, storage_error) = mem.alloc[SseReaderState](a, 1usize)
    if storage_error != ok { ret (out, storage_error) }
    let (input, input_error) = mem.alloc[u8](a, INPUT_CAPACITY)
    if input_error != ok { ret (out, input_error) }
    let (line, line_error) = mem.alloc[u8](a, limits.line_bytes)
    if line_error != ok { ret (out, line_error) }
    let (data, data_error) = mem.alloc[u8](a, limits.event_bytes)
    if data_error != ok { ret (out, data_error) }
    let (event, event_error) = mem.alloc[u8](a, limits.event_bytes)
    if event_error != ok { ret (out, event_error) }
    let (id, id_error) = mem.alloc[u8](a, limits.event_bytes)
    if id_error != ok { ret (out, id_error) }
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
    out.state = mem.cast[*void](&storage[0usize])
    ret (out, ok)
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
