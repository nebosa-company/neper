// Internet message headers (RFC 5322) without transport: `parse_address` takes
// `Name <local@domain>`, `"Quoted Name" <addr>`, `(comment) addr` and a bare
// `local@domain`; `parse_address_list` splits on commas outside quotes, brackets and
// comments; `format_address` writes the display name quoted when it needs to be;
// `parse_date` reads the `[Day, ]DD Mon YYYY HH:MM[:SS] +HHMM` form with the
// obsolete zone names; `read_message` takes the header block through `e.fmt.mime`
// and hands back the source at the body; `decode_header` decodes RFC 2047 encoded
// words -- `=?charset?B|Q?text?=` in UTF-8, ISO-8859-1 and US-ASCII, whitespace
// between two encoded words dropped as the RFC says -- into UTF-8.
use e.bytes
use e.io
use e.mem
use e.str
use e.time
use e.fmt.mime as mime

type Address = struct { name: str, address: str }
type Message = struct { headers: []const mime.Header, body: io.Reader }
type Date = struct { instant: i64, offset_minutes: i16 }
error InvalidAddress
error InvalidDate
error InvalidMessage
error TooLarge

// --- Addresses.

// Splits `source` at commas that sit outside quotes, angle brackets and comments.
fn split_addresses(source: str, out: []usize) -> usize {
    var count = 0usize
    var quote = false
    var depth = 0usize
    var angle = false
    var i = 0usize
    while i < source.len {
        let c = source[i]
        if quote {
            if c == 92u8 { i += 1usize } else { if c == 34u8 { quote = false } }
        } else {
        if c == 34u8 { quote = true } else {
        if c == 40u8 { depth += 1usize } else {
        if c == 41u8 && depth > 0usize { depth -= 1usize } else {
        if c == 60u8 { angle = true } else {
        if c == 62u8 { angle = false } else {
        if c == 44u8 && depth == 0usize && !angle {
            if count < out.len { out[count] = i }
            count += 1usize
        }
        }
        }
        }
        }
        }
        }
        i += 1usize
    }
    ret count
}

// The text with comments removed and the outside trimmed.
fn strip_comments(a: *mem.Arena, source: str) -> (str, err) {
    let (open, has_open) = str.find(source, "(")
    if !has_open { ret (str.trim(source), ok) }
    let (out, out_error) = mem.alloc[u8](a, source.len)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var depth = 0usize
    var quote = false
    var i = 0usize
    while i < source.len {
        let c = source[i]
        if quote {
            out[used] = c
            used += 1usize
            if c == 92u8 && i + 1usize < source.len {
                i += 1usize
                out[used] = source[i]
                used += 1usize
            } else {
                if c == 34u8 { quote = false }
            }
        } else {
        if c == 40u8 { depth += 1usize } else {
        if c == 41u8 && depth > 0usize { depth -= 1usize } else {
        if depth == 0usize {
            if c == 34u8 { quote = true }
            out[used] = c
            used += 1usize
        }
        }
        }
        }
        i += 1usize
    }
    ret (str.trim(out[..used]), ok)
}

fn unquote(a: *mem.Arena, text: str) -> (str, err) {
    if text.len < 2usize || text[0] != 34u8 || text[text.len - 1usize] != 34u8 { ret (text, ok) }
    let body = text[1usize..text.len - 1usize]
    let (slash, has_slash) = str.find(body, "\\")
    if !has_slash { ret (body, ok) }
    let (out, out_error) = mem.alloc[u8](a, body.len)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 92u8 && i + 1usize < body.len { i += 1usize }
        out[used] = body[i]
        used += 1usize
        i += 1usize
    }
    ret (out[..used], ok)
}

fn address_legal(address: str) -> bool {
    let (at, has_at) = str.rfind(address, "@")
    if !has_at || at == 0usize || at + 1usize == address.len { ret false }
    var i = 0usize
    while i < address.len {
        let c = address[i]
        if c <= 32u8 || c == 60u8 || c == 62u8 || c == 44u8 || c == 34u8 || c == 40u8 || c == 41u8 { ret false }
        i += 1usize
    }
    ret true
}

fn parse_address(a: *mem.Arena, source: str) -> (Address, err) {
    let (clean, clean_error) = strip_comments(a, source)
    if clean_error != ok { ret (zero, clean_error) }
    if clean.len == 0usize { ret (zero, InvalidAddress) }
    let (open, has_open) = str.rfind(clean, "<")
    if has_open {
        if clean[clean.len - 1usize] != 62u8 { ret (zero, InvalidAddress) }
        let mailbox = str.trim(clean[open + 1usize..clean.len - 1usize])
        if !address_legal(mailbox) { ret (zero, InvalidAddress) }
        let (name, name_error) = unquote(a, str.trim(clean[..open]))
        if name_error != ok { ret (zero, name_error) }
        ret (Address { name: name, address: mailbox }, ok)
    }
    if !address_legal(clean) { ret (zero, InvalidAddress) }
    ret (Address { name: "", address: clean }, ok)
}

fn parse_address_list(a: *mem.Arena, source: str) -> ([]const Address, err) {
    var commas: [256]usize = zero
    let count = split_addresses(source, commas[0..])
    if count >= 256usize { ret (zero, TooLarge) }
    let (out, out_error) = mem.alloc[Address](a, count + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var used = 0usize
    var start = 0usize
    var i = 0usize
    while i <= count {
        var stop = source.len
        if i < count { stop = commas[i] }
        let piece = str.trim(source[start..stop])
        if piece.len > 0usize {
            let (parsed, parse_error) = parse_address(a, piece)
            if parse_error != ok { ret (zero, parse_error) }
            out[used] = parsed
            used += 1usize
        }
        start = stop + 1usize
        i += 1usize
    }
    ret (out[..used], ok)
}

fn name_needs_quotes(name: str) -> bool {
    var i = 0usize
    while i < name.len {
        let c = name[i]
        let atom = str.is_ascii_alnum(c) || c == 32u8 || c == 33u8 || c == 35u8 || c == 36u8 || c == 37u8 || c == 38u8 || c == 39u8 || c == 42u8 || c == 43u8 || c == 45u8 || c == 47u8 || c == 61u8 || c == 63u8 || c == 94u8 || c == 95u8 || c == 96u8 || c == 123u8 || c == 124u8 || c == 125u8 || c == 126u8 || c >= 128u8
        if !atom { ret true }
        i += 1usize
    }
    ret false
}

fn format_address(a: *mem.Arena, value: Address) -> (str, err) {
    if !address_legal(value.address) { ret ("", InvalidAddress) }
    if value.name.len == 0usize { ret (value.address, ok) }
    let (b0, builder_error) = str.builder(a, value.name.len * 2usize + value.address.len + 8usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    let quoted = name_needs_quotes(value.name)
    if quoted {
        let open_error = str.push(&b, "\"")
        if open_error != ok { ret ("", open_error) }
        var i = 0usize
        while i < value.name.len {
            let c = value.name[i]
            if c == 34u8 || c == 92u8 {
                let escape_error = str.push_byte(&b, 92u8)
                if escape_error != ok { ret ("", escape_error) }
            }
            let byte_error = str.push_byte(&b, c)
            if byte_error != ok { ret ("", byte_error) }
            i += 1usize
        }
        let close_error = str.push(&b, "\"")
        if close_error != ok { ret ("", close_error) }
    } else {
        let name_error = str.push(&b, value.name)
        if name_error != ok { ret ("", name_error) }
    }
    let angle_error = str.push(&b, " <")
    if angle_error != ok { ret ("", angle_error) }
    let address_error = str.push(&b, value.address)
    if address_error != ok { ret ("", address_error) }
    let end_error = str.push(&b, ">")
    if end_error != ok { ret ("", end_error) }
    ret (str.done(&b), ok)
}

// --- Dates.

fn month_number(name: str) -> (i64, bool) {
    let names: [12]str = [12]str{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }
    var i = 0usize
    while i < 12usize {
        if str.compare_ascii_fold(name, names[i]) == 0 { ret (i64(i) + 1i64, true) }
        i += 1usize
    }
    ret (0i64, false)
}

fn digits_of(text: str) -> (i64, bool) {
    if text.len == 0usize { ret (0i64, false) }
    var value = 0i64
    var i = 0usize
    while i < text.len {
        if !str.is_ascii_digit(text[i]) { ret (0i64, false) }
        value = value * 10i64 + i64(text[i] - 48u8)
        i += 1usize
    }
    ret (value, true)
}

fn zone_minutes(text: str) -> (i16, bool) {
    if text.len == 5usize && (text[0] == 43u8 || text[0] == 45u8) {
        let (hours, hours_ok) = digits_of(text[1usize..3usize])
        let (minutes, minutes_ok) = digits_of(text[3usize..5usize])
        if !hours_ok || !minutes_ok || minutes >= 60i64 { ret (0i16, false) }
        var total = i16(hours * 60i64 + minutes)
        if text[0] == 45u8 { total = 0i16 - total }
        ret (total, true)
    }
    let names: [10]str = [10]str{ "UT", "GMT", "Z", "EST", "EDT", "CST", "CDT", "MST", "MDT", "PST" }
    let offsets: [10]i16 = [10]i16{ 0, 0, 0, -300, -240, -360, -300, -420, -360, -480 }
    var i = 0usize
    while i < 10usize {
        if str.compare_ascii_fold(text, names[i]) == 0 { ret (offsets[i], true) }
        i += 1usize
    }
    if str.compare_ascii_fold(text, "PDT") == 0 { ret (-420i16, true) }
    ret (0i16, false)
}

fn parse_date(source: str) -> (Date, err) {
    var text = str.trim(source)
    // An optional day name and comma.
    let (comma, has_comma) = str.find(text, ",")
    if has_comma { text = str.trim(text[comma + 1usize..]) }
    var fields: [6]str = zero
    var count = 0usize
    let (words0, words_error) = str.split(text, " ")
    if words_error != ok { ret (zero, InvalidDate) }
    var words = words0
    while true {
        let (word, more) = str.split_next(&words)
        if !more { break }
        if word.len == 0usize { continue }
        if count == 6usize { ret (zero, InvalidDate) }
        fields[count] = word
        count += 1usize
    }
    if count < 5usize { ret (zero, InvalidDate) }
    let (day, day_ok) = digits_of(fields[0])
    let (month, month_ok) = month_number(fields[1])
    let (year0, year_ok) = digits_of(fields[2])
    if !day_ok || !month_ok || !year_ok { ret (zero, InvalidDate) }
    var year = year0
    if fields[2].len == 2usize {
        if year < 50i64 { year += 2000i64 } else { year += 1900i64 }
    }
    let clock = fields[3]
    if clock.len != 5usize && clock.len != 8usize { ret (zero, InvalidDate) }
    let (hour, hour_ok) = digits_of(clock[0usize..2usize])
    let (minute, minute_ok) = digits_of(clock[3usize..5usize])
    var second = 0i64
    var second_ok = true
    if clock.len == 8usize {
        let (parsed, parsed_ok) = digits_of(clock[6usize..8usize])
        second = parsed
        second_ok = parsed_ok
    }
    if !hour_ok || !minute_ok || !second_ok || clock[2] != 58u8 { ret (zero, InvalidDate) }
    if hour > 23i64 || minute > 59i64 || second > 60i64 { ret (zero, InvalidDate) }
    let (offset, offset_ok) = zone_minutes(fields[4])
    if !offset_ok { ret (zero, InvalidDate) }
    if month < 1i64 || month > 12i64 || day < 1i64 || day > time.days_in_month(year, month) { ret (zero, InvalidDate) }
    let days = time.days_from_civil(year, month, day)
    let local = days * 86400i64 + hour * 3600i64 + minute * 60i64 + second
    ret (Date { instant: local - i64(offset) * 60i64, offset_minutes: offset }, ok)
}

// --- Messages.

fn read_message(a: *mem.Arena, source: io.Reader, header_limit: usize) -> (Message, err) {
    // The header block is read through mime, which stops at the first empty line; the
    // body is the same reader positioned after it, reached by re-reading the bytes the
    // header parse consumed: mime reads into a buffer, so the message is taken whole
    // up to the limit and the body served from what follows the block.
    let (buffer, buffer_error) = mem.alloc[u8](a, header_limit)
    if buffer_error != ok { ret (zero, buffer_error) }
    var input = source
    var filled = 0usize
    var block_end = 0usize
    var found = false
    while !found {
        if filled == header_limit { ret (zero, TooLarge) }
        let (count, read_error) = io.read(&input, buffer[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        if count == 0usize { break }
        filled += count
        var at = 0usize
        while at + 1usize < filled && !found {
            if buffer[at] == 10u8 {
                if buffer[at + 1usize] == 10u8 {
                    block_end = at + 2usize
                    found = true
                }
                if at + 2usize < filled && buffer[at + 1usize] == 13u8 && buffer[at + 2usize] == 10u8 {
                    block_end = at + 3usize
                    found = true
                }
            }
            at += 1usize
        }
    }
    if !found { block_end = filled }
    // Folded lines are joined before mime sees them: a break followed by space or tab
    // is one space.
    let (unfolded, unfolded_error) = mem.alloc[u8](a, block_end)
    if unfolded_error != ok { ret (zero, unfolded_error) }
    var used = 0usize
    var at = 0usize
    while at < block_end {
        let c = buffer[at]
        if c == 10u8 && at + 1usize < block_end && (buffer[at + 1usize] == 32u8 || buffer[at + 1usize] == 9u8) {
            if used > 0usize && unfolded[used - 1usize] == 13u8 { used -= 1usize }
            unfolded[used] = 32u8
            used += 1usize
            at += 2usize
            while at < block_end && (buffer[at] == 32u8 || buffer[at] == 9u8) { at += 1usize }
            continue
        }
        unfolded[used] = c
        used += 1usize
        at += 1usize
    }
    var block_state = io.SliceReader { data: unfolded[..used], off: 0usize }
    let (headers, headers_error) = mime.parse_headers(a, io.slice_reader(&block_state), header_limit, 256usize)
    if headers_error == mime.TooLarge { ret (zero, TooLarge) }
    if headers_error != ok { ret (zero, InvalidMessage) }
    // The body: the bytes already read past the block, then the rest of the source.
    let (rest_state, rest_error) = mem.alloc[io.SliceReader](a, 1usize)
    if rest_error != ok { ret (zero, rest_error) }
    rest_state[0] = io.SliceReader { data: buffer[block_end..filled], off: 0usize }
    let (chain, chain_error) = mem.alloc[Chain](a, 1usize)
    if chain_error != ok { ret (zero, chain_error) }
    chain[0] = Chain { first: io.slice_reader(&rest_state[0]), second: input, first_done: false }
    ret (Message { headers: headers, body: io.Reader { ctx: mem.cast[*void](&chain[0]), read: chain_read } }, ok)
}

// The body reader: what was buffered past the header block, then the source.
type Chain = struct { first: io.Reader, second: io.Reader, first_done: bool }

fn chain_read(ctx: *void, dst: []u8) -> (usize, err) {
    let c = mem.cast[*Chain](ctx)
    if !c.first_done {
        let (count, read_error) = io.read(&c.first, dst)
        if read_error == ok && count > 0usize { ret (count, ok) }
        if read_error != ok && read_error != io.End { ret (count, read_error) }
        c.first_done = true
    }
    let (count, read_error) = io.read(&c.second, dst)
    ret (count, read_error)
}

// --- Encoded words.

fn hex_nibble(c: u8) -> (u8, bool) {
    if c >= 48u8 && c <= 57u8 { ret (c - 48u8, true) }
    if c >= 65u8 && c <= 70u8 { ret (c - 55u8, true) }
    if c >= 97u8 && c <= 102u8 { ret (c - 87u8, true) }
    ret (0u8, false)
}

// Decodes one encoded word's payload into `out` as UTF-8: (bytes written, ok).
fn decode_word(charset: str, encoding: str, payload: str, out: []u8) -> (usize, bool) {
    var raw: [512]u8 = zero
    var raw_len = 0usize
    if str.compare_ascii_fold(encoding, "B") == 0 {
        let (decoded, decode_error) = bytes.base64_decode(raw[0..], payload, .Standard)
        if decode_error != ok { ret (0usize, false) }
        raw_len = decoded.len
    } else {
        if str.compare_ascii_fold(encoding, "Q") != 0 { ret (0usize, false) }
        var i = 0usize
        while i < payload.len {
            let c = payload[i]
            if raw_len >= raw.len { ret (0usize, false) }
            if c == 95u8 {
                raw[raw_len] = 32u8
            } else {
            if c == 61u8 {
                if i + 2usize >= payload.len { ret (0usize, false) }
                let (high, high_ok) = hex_nibble(payload[i + 1usize])
                let (low, low_ok) = hex_nibble(payload[i + 2usize])
                if !high_ok || !low_ok { ret (0usize, false) }
                raw[raw_len] = (high << 4u8) | low
                i += 2usize
            } else {
                raw[raw_len] = c
            }
            }
            raw_len += 1usize
            i += 1usize
        }
    }
    let utf8 = str.compare_ascii_fold(charset, "utf-8") == 0 || str.compare_ascii_fold(charset, "us-ascii") == 0
    let latin1 = str.compare_ascii_fold(charset, "iso-8859-1") == 0
    if !utf8 && !latin1 { ret (0usize, false) }
    var used = 0usize
    var i = 0usize
    while i < raw_len {
        let c = raw[i]
        if latin1 && c >= 128u8 {
            if used + 2usize > out.len { ret (0usize, false) }
            out[used] = 192u8 | (c >> 6u8)
            out[used + 1usize] = 128u8 | (c & 63u8)
            used += 2usize
        } else {
            if used >= out.len { ret (0usize, false) }
            out[used] = c
            used += 1usize
        }
        i += 1usize
    }
    ret (used, true)
}

fn decode_header(a: *mem.Arena, source: str, output_limit: usize) -> (str, err) {
    let (open, has_open) = str.find(source, "=?")
    if !has_open {
        if source.len > output_limit { ret ("", TooLarge) }
        ret (source, ok)
    }
    let (out, out_error) = mem.alloc[u8](a, output_limit)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var at = 0usize
    var after_word = false
    while at < source.len {
        if str.starts_with(source[at..], "=?") {
            // =?charset?enc?payload?=
            let (q1, has_q1) = str.find_from(source, "?", at + 2usize)
            var good = has_q1
            var q2 = 0usize
            var close = 0usize
            if good {
                let (found_q2, has_q2) = str.find_from(source, "?", q1 + 1usize)
                q2 = found_q2
                good = has_q2 && found_q2 == q1 + 2usize
            }
            if good {
                let (found_close, has_close) = str.find_from(source, "?=", q2 + 1usize)
                close = found_close
                good = has_close
            }
            if good {
                var scratch: [1024]u8 = zero
                let (written, decoded) = decode_word(source[at + 2usize..q1], source[q1 + 1usize..q2], source[q2 + 1usize..close], scratch[0..])
                if decoded {
                    if used + written > output_limit { ret ("", TooLarge) }
                    mem.copy[u8](out[used..used + written], scratch[..written])
                    used += written
                    at = close + 2usize
                    // Whitespace between two encoded words is not content.
                    var probe = at
                    while probe < source.len && (source[probe] == 32u8 || source[probe] == 9u8 || source[probe] == 13u8 || source[probe] == 10u8) { probe += 1usize }
                    if str.starts_with(source[probe..], "=?") { at = probe }
                    after_word = true
                    continue
                }
            }
        }
        if used >= output_limit { ret ("", TooLarge) }
        out[used] = source[at]
        used += 1usize
        at += 1usize
        after_word = false
    }
    ret (out[..used], ok)
}
