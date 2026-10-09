// LDAPv3 client (RFC 4511, string filters RFC 4515, StartTLS RFC 4513, SASL PLAIN RFC 4616) over any
// `io.Reader` / `io.Writer` pair, with the BER the protocol uses written and read here (the generic
// e.fmt.asn1 is strict DER; LDAP servers send plain BER, so booleans may be any non-zero byte, and a
// message uses single-byte tags and definite lengths only). `connect` wraps the connection, `starttls`
// upgrades it through e.net.tls, `bind_simple`, `bind_anonymous` and `bind_plain` authenticate, and `search`,
// `compare`, `add`, `modify`, `delete` and `unbind` are the operations. `encode_filter` turns an RFC 4515
// filter string (`(&(objectClass=person)(|(cn=Ann*)(uid=a\2ab)))`, substring, presence, approximate, greater or
// less, extensible match) into the Filter BER. Every request carries a fresh message id and the client waits
// for the response with that id, collecting SearchResultEntry messages until SearchResultDone; references are
// counted but not followed. A result code other than success is `Rejected` with the whole result in
// `Session.last` (a compare answers true or false instead; sizeLimitExceeded, 4, still returns the entries
// found, with `Rejected`). A message larger than the limit given to `connect` is `TooLarge`. No SASL beyond
// PLAIN, no controls, no paged results, no referral chasing, no ModifyDN, no abandon.

use e.io
use e.mem
use e.net.tls as tls
use e.str

type Result = struct { code: u32, matched_dn: str, message: str, referrals: []const str }
type Attribute = struct { name: str, values: []const str }
type Entry = struct { dn: str, attributes: []const Attribute }
type Change = struct { operation: u8, attribute: str, values: []const str }
type Session = struct {
    a: *mem.Arena, source: io.Reader, sink: io.Writer, stream: *tls.Stream, secured: bool, next_id: u32,
    last: Result, limit: usize, buf: []u8, at: usize, len: usize, msg: []u8, out: []u8, references: usize,
}
type Writer = struct { buf: []u8, at: usize, failed: bool }
type Cursor = struct { data: []const u8, at: usize }

const SCOPE_BASE: u8 = 0u8
const SCOPE_ONE: u8 = 1u8
const SCOPE_SUBTREE: u8 = 2u8
const MODIFY_ADD: u8 = 0u8
const MODIFY_DELETE: u8 = 1u8
const MODIFY_REPLACE: u8 = 2u8

const T_SEQUENCE: u8 = 48u8
const T_SET: u8 = 49u8
const T_INTEGER: u8 = 2u8
const T_OCTETS: u8 = 4u8
const T_BOOLEAN: u8 = 1u8
const T_ENUMERATED: u8 = 10u8
const OP_BIND: u8 = 96u8
const OP_BIND_RESPONSE: u8 = 97u8
const OP_UNBIND: u8 = 66u8
const OP_SEARCH: u8 = 99u8
const OP_ENTRY: u8 = 100u8
const OP_DONE: u8 = 101u8
const OP_MODIFY: u8 = 102u8
const OP_MODIFY_RESPONSE: u8 = 103u8
const OP_ADD: u8 = 104u8
const OP_ADD_RESPONSE: u8 = 105u8
const OP_DELETE: u8 = 74u8
const OP_DELETE_RESPONSE: u8 = 107u8
const OP_COMPARE: u8 = 110u8
const OP_COMPARE_RESPONSE: u8 = 111u8
const OP_REFERENCE: u8 = 115u8
const OP_EXTENDED: u8 = 119u8
const OP_EXTENDED_RESPONSE: u8 = 120u8
const OP_INTERMEDIATE: u8 = 121u8

error Protocol
error Rejected
error Closed
error TooLarge
error Invalid
error Unsupported

// ---- the BER writer -----------------------------------------------------------------------------------

fn w_byte(w: *Writer, b: u8) {
    if w.at >= w.buf.len {
        w.failed = true
        ret
    }
    w.buf[w.at] = b
    w.at += 1usize
}

fn w_bytes(w: *Writer, bytes: []const u8) {
    if w.at + bytes.len > w.buf.len {
        w.failed = true
        ret
    }
    mem.copy[u8](w.buf[w.at..], bytes)
    w.at += bytes.len
}

fn w_length(w: *Writer, n: usize) {
    if n < 128usize {
        w_byte(w, u8(n))
        ret
    }
    var count = 1usize
    var rest = n >> 8u32
    while rest > 0usize {
        count += 1usize
        rest = rest >> 8u32
    }
    w_byte(w, 128u8 | u8(count))
    var shift = count
    while shift > 0usize {
        shift -= 1usize
        w_byte(w, u8((n >> u32(shift * 8usize)) & 255usize))
    }
}

fn w_octets(w: *Writer, tag: u8, bytes: []const u8) {
    w_byte(w, tag)
    w_length(w, bytes.len)
    w_bytes(w, bytes)
}

// An INTEGER or ENUMERATED in the shortest two's complement.
fn w_integer(w: *Writer, tag: u8, value: i64) {
    var bytes: [8]u8 = zero
    var count = 8usize
    var v = mem.bitcast[u64](value)
    var i = 0usize
    while i < 8usize {
        bytes[7usize - i] = u8(v & 255u64)
        v = v >> 8u32
        i += 1usize
    }
    var first = 0usize
    while first < 7usize {
        if bytes[first] == 0u8 && bytes[first + 1usize] & 128u8 == 0u8 {
            first += 1usize
        } else if bytes[first] == 255u8 && bytes[first + 1usize] & 128u8 != 0u8 {
            first += 1usize
        } else {
            break
        }
    }
    count = 8usize - first
    w_byte(w, tag)
    w_length(w, count)
    w_bytes(w, bytes[first..])
}

// Open a constructed value: the tag and a one-byte length slot. `end` fixes the length, widening the slot.
fn begin(w: *Writer, tag: u8) -> usize {
    w_byte(w, tag)
    let mark = w.at
    w_byte(w, 0u8)
    ret mark
}

fn end(w: *Writer, mark: usize) {
    if w.failed { ret }
    let content = w.at - mark - 1usize
    if content < 128usize {
        w.buf[mark] = u8(content)
        ret
    }
    var extra = 1usize
    var rest = content >> 8u32
    while rest > 0usize {
        extra += 1usize
        rest = rest >> 8u32
    }
    if w.at + extra > w.buf.len {
        w.failed = true
        ret
    }
    // shift the content right by `extra`, last byte first
    var i = w.at
    while i > mark + 1usize {
        i -= 1usize
        w.buf[i + extra] = w.buf[i]
    }
    w.buf[mark] = 128u8 | u8(extra)
    var k = 0usize
    while k < extra {
        w.buf[mark + 1usize + k] = u8((content >> u32((extra - 1usize - k) * 8usize)) & 255usize)
        k += 1usize
    }
    w.at += extra
}

// ---- filters (RFC 4515) -------------------------------------------------------------------------------

fn hex_value(b: u8) -> (u8, bool) {
    if b >= 48u8 && b <= 57u8 { ret (b - 48u8, true) }
    if b >= 97u8 && b <= 102u8 { ret (b - 87u8, true) }
    if b >= 65u8 && b <= 70u8 { ret (b - 55u8, true) }
    ret (0u8, false)
}

// Unescape `\hh` in `text[from..to]` into `out`; the count is answered. A bare ( ) or NUL is refused.
fn unescape(text: str, from: usize, to: usize, out: []u8) -> (usize, bool) {
    var n = 0usize
    var i = from
    while i < to {
        let b = text[i]
        if b == 40u8 || b == 41u8 || b == 0u8 { ret (0usize, false) }
        if b == 92u8 {
            if i + 2usize >= to { ret (0usize, false) }
            let (hi, hi_ok) = hex_value(text[i + 1usize])
            let (lo, lo_ok) = hex_value(text[i + 2usize])
            if !hi_ok || !lo_ok { ret (0usize, false) }
            if n >= out.len { ret (0usize, false) }
            out[n] = hi * 16u8 + lo
            n += 1usize
            i += 3usize
            continue
        }
        if n >= out.len { ret (0usize, false) }
        out[n] = b
        n += 1usize
        i += 1usize
    }
    ret (n, true)
}

// The end of the filter that starts at `at` (which holds a `(`): the index just past its closing `)`.
fn filter_end(text: str, at: usize) -> (usize, bool) {
    var depth = 0usize
    var i = at
    while i < text.len {
        let b = text[i]
        if b == 92u8 {
            i += 3usize
            continue
        }
        if b == 40u8 { depth += 1usize }
        if b == 41u8 {
            if depth == 0usize { ret (0usize, false) }
            depth -= 1usize
            if depth == 0usize { ret (i + 1usize, true) }
        }
        i += 1usize
    }
    ret (0usize, false)
}

fn is_attr_char(b: u8) -> bool {
    ret (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) || b == 45u8 || b == 46u8 || b == 59u8 || b == 95u8
}

fn put_filter(w: *Writer, text: str, from: usize, to: usize, depth: usize) -> bool {
    if depth > 32usize || to - from < 3usize || text[from] != 40u8 || text[to - 1usize] != 41u8 { ret false }
    let inner_from = from + 1usize
    let inner_to = to - 1usize
    let c = text[inner_from]
    if c == 38u8 || c == 124u8 {
        var tag = 160u8
        if c == 124u8 { tag = 161u8 }
        let mark = begin(w, tag)
        var at = inner_from + 1usize
        var count = 0usize
        while at < inner_to {
            let (stop, stop_ok) = filter_end(text, at)
            if !stop_ok || text[at] != 40u8 || stop > inner_to { ret false }
            if !put_filter(w, text, at, stop, depth + 1usize) { ret false }
            at = stop
            count += 1usize
        }
        if count == 0usize { ret false }
        end(w, mark)
        ret true
    }
    if c == 33u8 {
        let (stop, stop_ok) = filter_end(text, inner_from + 1usize)
        if !stop_ok || text[inner_from + 1usize] != 40u8 || stop != inner_to { ret false }
        let mark = begin(w, 162u8)
        if !put_filter(w, text, inner_from + 1usize, stop, depth + 1usize) { ret false }
        end(w, mark)
        ret true
    }
    // an item: attribute (or extensible prefix) then the operator and the value
    var i = inner_from
    while i < inner_to && is_attr_char(text[i]) { i += 1usize }
    let attr_end = i
    if i >= inner_to { ret false }
    if text[i] == 58u8 {
        // extensible match: attr[:dn][:rule]:=value
        var dn_attributes = false
        var rule_from = 0usize
        var rule_to = 0usize
        var j = i
        while j < inner_to {
            if text[j] == 58u8 && j + 1usize < inner_to && text[j + 1usize] == 61u8 { break }
            if text[j] != 58u8 { ret false }
            var k = j + 1usize
            while k < inner_to && text[k] != 58u8 { k += 1usize }
            if k > inner_to { ret false }
            let word = text[j + 1usize..k]
            if str.compare_ascii_fold(word, "dn") == 0i32 && !dn_attributes && rule_from == 0usize {
                dn_attributes = true
            } else {
                if rule_from != 0usize || word.len == 0usize { ret false }
                rule_from = j + 1usize
                rule_to = k
            }
            j = k
        }
        if j + 1usize >= inner_to || text[j] != 58u8 || text[j + 1usize] != 61u8 { ret false }
        if attr_end == inner_from && rule_from == 0usize { ret false }
        var value: [1024]u8 = zero
        let (n, n_ok) = unescape(text, j + 2usize, inner_to, value[0..])
        if !n_ok { ret false }
        let mark = begin(w, 169u8)
        if rule_from != 0usize { w_octets(w, 129u8, text[rule_from..rule_to]) }
        if attr_end > inner_from { w_octets(w, 130u8, text[inner_from..attr_end]) }
        w_octets(w, 131u8, value[..n])
        if dn_attributes {
            w_byte(w, 132u8)
            w_byte(w, 1u8)
            w_byte(w, 255u8)
        }
        end(w, mark)
        ret true
    }
    if attr_end == inner_from { ret false }
    var tag = 163u8
    var value_from = 0usize
    if text[i] == 61u8 {
        value_from = i + 1usize
    } else if i + 1usize < inner_to && text[i + 1usize] == 61u8 {
        if text[i] == 126u8 { tag = 168u8 } else if text[i] == 62u8 { tag = 165u8 } else if text[i] == 60u8 { tag = 166u8 } else { ret false }
        value_from = i + 2usize
    } else {
        ret false
    }
    let attr = text[inner_from..attr_end]
    // presence: attr=*
    if tag == 163u8 && inner_to - value_from == 1usize && text[value_from] == 42u8 {
        w_octets(w, 135u8, attr)
        ret true
    }
    // substrings: an equality with an unescaped *
    if tag == 163u8 {
        var star = false
        var s = value_from
        while s < inner_to {
            if text[s] == 92u8 {
                s += 3usize
                continue
            }
            if text[s] == 42u8 { star = true }
            s += 1usize
        }
        if star {
            let mark = begin(w, 164u8)
            w_octets(w, T_OCTETS, attr)
            let list = begin(w, T_SEQUENCE)
            var piece = value_from
            var index = 0usize
            var cursor = value_from
            while true {
                let at_end = cursor == inner_to
                if !at_end && text[cursor] == 92u8 {
                    cursor += 3usize
                    continue
                }
                if at_end || text[cursor] == 42u8 {
                    if cursor > piece {
                        var tag_part = 129u8
                        if index == 0usize { tag_part = 128u8 }
                        if at_end { tag_part = 130u8 }
                        var part: [1024]u8 = zero
                        let (n, n_ok) = unescape(text, piece, cursor, part[0..])
                        if !n_ok { ret false }
                        w_octets(w, tag_part, part[..n])
                    }
                    index += 1usize
                    piece = cursor + 1usize
                    if at_end { break }
                }
                cursor += 1usize
            }
            end(w, list)
            end(w, mark)
            ret true
        }
    }
    var value: [1024]u8 = zero
    let (n, n_ok) = unescape(text, value_from, inner_to, value[0..])
    if !n_ok { ret false }
    let mark = begin(w, tag)
    w_octets(w, T_OCTETS, attr)
    w_octets(w, T_OCTETS, value[..n])
    end(w, mark)
    ret true
}

// The BER of an RFC 4515 filter string, into `dst`; the byte count is answered. A malformed filter is `Invalid`.
fn encode_filter(dst: []u8, text: str) -> (usize, err) {
    var w = Writer { buf: dst, at: 0usize, failed: false }
    if text.len == 0usize || !put_filter(&w, text, 0usize, text.len, 0usize) || w.failed { ret (0usize, Invalid) }
    ret (w.at, ok)
}

// ---- reading -------------------------------------------------------------------------------------------

fn fill(s: *Session) -> err {
    var tries = 0usize
    while tries < 8usize {
        let (n, read_error) = io.read(&s.source, s.buf)
        if read_error == io.End { ret Closed }
        if read_error != ok { ret read_error }
        if n > 0usize {
            s.at = 0usize
            s.len = n
            ret ok
        }
        tries += 1usize
    }
    ret Closed
}

fn next_byte(s: *Session) -> (u8, err) {
    if s.at >= s.len {
        let fill_error = fill(s)
        if fill_error != ok { ret (0u8, fill_error) }
    }
    let b = s.buf[s.at]
    s.at += 1usize
    ret (b, ok)
}

// One LDAPMessage into `s.msg`: its total length is answered.
fn read_message(s: *Session) -> (usize, err) {
    let (tag, tag_error) = next_byte(s)
    if tag_error != ok { ret (0usize, tag_error) }
    if tag != T_SEQUENCE { ret (0usize, Protocol) }
    let (first, first_error) = next_byte(s)
    if first_error != ok { ret (0usize, first_error) }
    var length = usize(first)
    if first >= 128u8 {
        let count = usize(first & 127u8)
        if count == 0usize || count > 4usize { ret (0usize, Protocol) }
        length = 0usize
        var i = 0usize
        while i < count {
            let (b, b_error) = next_byte(s)
            if b_error != ok { ret (0usize, b_error) }
            length = length * 256usize + usize(b)
            i += 1usize
        }
    }
    if length > s.limit || length > s.msg.len { ret (0usize, TooLarge) }
    var got = 0usize
    while got < length {
        if s.at >= s.len {
            let fill_error = fill(s)
            if fill_error != ok { ret (0usize, fill_error) }
        }
        var take = s.len - s.at
        if take > length - got { take = length - got }
        mem.copy[u8](s.msg[got..], s.buf[s.at..s.at + take])
        s.at += take
        got += take
    }
    ret (length, ok)
}

// The next TLV of a cursor: single-byte tag, definite length; the tag and the content are answered.
fn next(c: *Cursor) -> (u8, []const u8, bool) {
    if c.at >= c.data.len { ret (0u8, "", false) }
    let tag = c.data[c.at]
    if tag & 31u8 == 31u8 { ret (0u8, "", false) }
    if c.at + 1usize >= c.data.len { ret (0u8, "", false) }
    var at = c.at + 1usize
    var length = usize(c.data[at])
    at += 1usize
    if length >= 128usize {
        let count = length & 127usize
        if count == 0usize || count > 4usize || at + count > c.data.len { ret (0u8, "", false) }
        length = 0usize
        var i = 0usize
        while i < count {
            length = length * 256usize + usize(c.data[at + i])
            i += 1usize
        }
        at += count
    }
    if at + length > c.data.len { ret (0u8, "", false) }
    let content = c.data[at..at + length]
    c.at = at + length
    ret (tag, content, true)
}

fn int_of(content: []const u8) -> (i64, bool) {
    if content.len == 0usize || content.len > 8usize { ret (0i64, false) }
    var v = 0u64
    if content[0] & 128u8 != 0u8 { v = 18446744073709551615u64 }
    var i = 0usize
    while i < content.len {
        v = (v << 8u32) | u64(content[i])
        i += 1usize
    }
    ret (mem.bitcast[i64](v), true)
}

fn copy_text(a: *mem.Arena, text: []const u8) -> (str, err) {
    let (kept, alloc_error) = mem.alloc[u8](a, text.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    mem.copy[u8](kept, text)
    ret (kept[..text.len], ok)
}

// LDAPResult components from the content of a response op (after any leading fields the caller consumed).
fn parse_result(a: *mem.Arena, c: *Cursor) -> (Result, err) {
    var none = Result { code: 0u32, matched_dn: "", message: "", referrals: zero }
    let (t1, code_bytes, ok1) = next(c)
    if !ok1 || t1 != T_ENUMERATED { ret (none, Protocol) }
    let (code, code_ok) = int_of(code_bytes)
    if !code_ok || code < 0i64 { ret (none, Protocol) }
    let (t2, dn_bytes, ok2) = next(c)
    if !ok2 || t2 != T_OCTETS { ret (none, Protocol) }
    let (t3, message_bytes, ok3) = next(c)
    if !ok3 || t3 != T_OCTETS { ret (none, Protocol) }
    let (dn, dn_error) = copy_text(a, dn_bytes)
    if dn_error != ok { ret (none, dn_error) }
    let (message, message_error) = copy_text(a, message_bytes)
    if message_error != ok { ret (none, message_error) }
    var referrals: []str = zero
    var save = c.at
    let (t4, referral_bytes, ok4) = next(c)
    if ok4 && t4 == 163u8 {
        var count = 0usize
        var probe = Cursor { data: referral_bytes, at: 0usize }
        while true {
            let (_, _, more) = next(&probe)
            if !more { break }
            count += 1usize
        }
        let (urls, urls_error) = mem.alloc[str](a, count + 1usize)
        if urls_error != ok { ret (none, urls_error) }
        var inside = Cursor { data: referral_bytes, at: 0usize }
        var k = 0usize
        while k < count {
            let (_, url_bytes, _) = next(&inside)
            let (url, url_error) = copy_text(a, url_bytes)
            if url_error != ok { ret (none, url_error) }
            urls[k] = url
            k += 1usize
        }
        referrals = urls[..count]
    } else {
        c.at = save
    }
    ret (Result { code: u32(code), matched_dn: dn, message: message, referrals: referrals }, ok)
}

// ---- requests ------------------------------------------------------------------------------------------

fn begin_message(s: *Session, w: *Writer) -> (usize, u32) {
    s.next_id += 1u32
    let mark = begin(w, T_SEQUENCE)
    w_integer(w, T_INTEGER, i64(s.next_id))
    ret (mark, s.next_id)
}

fn send_message(s: *Session, w: *Writer, mark: usize) -> err {
    end(w, mark)
    if w.failed { ret TooLarge }
    try io.write_all(&s.sink, w.buf[..w.at])
    ret io.flush(&s.sink)
}

// Wait for the next message with id `id`; messages with other ids (a late reply to an abandoned request) are
// skipped, and the server's unsolicited disconnection notice (id 0) is `Closed`.
fn read_for(s: *Session, id: u32) -> (u8, []const u8, err) {
    while true {
        let (length, read_error) = read_message(s)
        if read_error != ok { ret (0u8, "", read_error) }
        var c = Cursor { data: s.msg[..length], at: 0usize }
        let (id_tag, id_bytes, id_ok) = next(&c)
        if !id_ok || id_tag != T_INTEGER { ret (0u8, "", Protocol) }
        let (got, got_ok) = int_of(id_bytes)
        if !got_ok { ret (0u8, "", Protocol) }
        let (op_tag, op_content, op_ok) = next(&c)
        if !op_ok { ret (0u8, "", Protocol) }
        if got == 0i64 && op_tag == OP_EXTENDED_RESPONSE { ret (0u8, "", Closed) }
        if got != i64(id) { continue }
        let (kept, kept_error) = copy_bytes(s.a, op_content)
        if kept_error != ok { ret (0u8, "", kept_error) }
        ret (op_tag, kept, ok)
    }
    ret (0u8, "", Protocol)
}

fn copy_bytes(a: *mem.Arena, bytes: []const u8) -> ([]const u8, err) {
    let (kept, alloc_error) = mem.alloc[u8](a, bytes.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    mem.copy[u8](kept, bytes)
    ret (kept[..bytes.len], ok)
}

// A response whose op is `want` and whose content starts with an LDAPResult.
fn expect_result(s: *Session, id: u32, want: u8) -> err {
    let (op, content, read_error) = read_for(s, id)
    if read_error != ok { ret read_error }
    if op != want { ret Protocol }
    var c = Cursor { data: content, at: 0usize }
    let (result, result_error) = parse_result(s.a, &c)
    if result_error != ok { ret result_error }
    s.last = result
    if result.code != 0u32 { ret Rejected }
    ret ok
}

fn clean(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        if text[i] == 0u8 { ret false }
        i += 1usize
    }
    ret true
}

// ---- session -------------------------------------------------------------------------------------------

// Wrap an open connection. `limit` bounds one message (a search entry with big attributes must fit).
fn connect(a: *mem.Arena, source: io.Reader, sink: io.Writer, limit: usize) -> (Session, err) {
    var empty: Session = zero
    let (buf, buf_error) = mem.alloc[u8](a, 4096usize)
    if buf_error != ok { ret (empty, buf_error) }
    let (msg, msg_error) = mem.alloc[u8](a, limit)
    if msg_error != ok { ret (empty, msg_error) }
    let (out, out_error) = mem.alloc[u8](a, 65536usize)
    if out_error != ok { ret (empty, out_error) }
    ret (Session {
        a: a, source: source, sink: sink, stream: nil, secured: false, next_id: 0u32,
        last: Result { code: 0u32, matched_dn: "", message: "", referrals: zero }, limit: limit,
        buf: buf, at: 0usize, len: 0usize, msg: msg, out: out, references: 0usize,
    }, ok)
}

// StartTLS: the extended request 1.3.6.1.4.1.1466.20037, then the handshake over the same connection.
fn starttls(s: *Session, config: tls.ClientConfig) -> err {
    if s.secured { ret Unsupported }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    let op = begin(&w, 119u8)
    w_octets(&w, 128u8, "1.3.6.1.4.1.1466.20037")
    end(&w, op)
    try send_message(s, &w, mark)
    let (tag, content, read_error) = read_for(s, id)
    if read_error != ok { ret read_error }
    if tag != OP_EXTENDED_RESPONSE { ret Protocol }
    var c = Cursor { data: content, at: 0usize }
    let (result, result_error) = parse_result(s.a, &c)
    if result_error != ok { ret result_error }
    s.last = result
    if result.code != 0u32 { ret Rejected }
    if s.at < s.len { ret Protocol }
    let (slot, slot_error) = mem.alloc[tls.Stream](s.a, 1usize)
    if slot_error != ok { ret slot_error }
    let (made, make_error) = tls.client(s.a, s.source, s.sink, config)
    if make_error != ok { ret make_error }
    slot[0] = made
    try tls.handshake(&slot[0])
    s.stream = &slot[0]
    s.source = tls.reader(s.stream)
    s.sink = tls.writer(s.stream)
    s.secured = true
    s.at = 0usize
    s.len = 0usize
    ret ok
}

fn bind_op(s: *Session, name: str, sasl: bool, mechanism: str, credentials: []const u8) -> err {
    if !clean(name) { ret Invalid }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    let op = begin(&w, OP_BIND)
    w_integer(&w, T_INTEGER, 3i64)
    w_octets(&w, T_OCTETS, name)
    if sasl {
        let choice = begin(&w, 163u8)
        w_octets(&w, T_OCTETS, mechanism)
        w_octets(&w, T_OCTETS, credentials)
        end(&w, choice)
    } else {
        w_octets(&w, 128u8, credentials)
    }
    end(&w, op)
    try send_message(s, &w, mark)
    wipe(s.out)
    ret expect_result(s, id, OP_BIND_RESPONSE)
}

fn wipe(buf: []u8) {
    var i = 0usize
    while i < buf.len {
        buf[i] = 0u8
        i += 1usize
    }
}

// Simple bind with a DN and a password; an empty password is refused (it would be an unauthenticated bind).
fn bind_simple(s: *Session, dn: str, password: str) -> err {
    if password.len == 0usize { ret Invalid }
    ret bind_op(s, dn, false, "", password)
}

// Anonymous bind (empty name and password).
fn bind_anonymous(s: *Session) -> err { ret bind_op(s, "", false, "", "") }

// SASL PLAIN: authorization id (usually ""), user and password.
fn bind_plain(s: *Session, authzid: str, user: str, password: str) -> err {
    if user.len == 0usize || password.len == 0usize || !clean(authzid) || !clean(user) || !clean(password) { ret Invalid }
    var raw: [1024]u8 = zero
    var w = Writer { buf: raw[0..], at: 0usize, failed: false }
    w_bytes(&w, authzid)
    w_byte(&w, 0u8)
    w_bytes(&w, user)
    w_byte(&w, 0u8)
    w_bytes(&w, password)
    if w.failed { ret TooLarge }
    let status = bind_op(s, "", true, "PLAIN", raw[..w.at])
    wipe(raw[0..])
    ret status
}

fn parse_entry(a: *mem.Arena, content: []const u8) -> (Entry, err) {
    var none = Entry { dn: "", attributes: zero }
    var c = Cursor { data: content, at: 0usize }
    let (t1, dn_bytes, ok1) = next(&c)
    if !ok1 || t1 != T_OCTETS { ret (none, Protocol) }
    let (t2, list, ok2) = next(&c)
    if !ok2 || t2 != T_SEQUENCE { ret (none, Protocol) }
    let (dn, dn_error) = copy_text(a, dn_bytes)
    if dn_error != ok { ret (none, dn_error) }
    var count = 0usize
    var probe = Cursor { data: list, at: 0usize }
    while true {
        let (_, _, more) = next(&probe)
        if !more { break }
        count += 1usize
    }
    let (attributes, attributes_error) = mem.alloc[Attribute](a, count + 1usize)
    if attributes_error != ok { ret (none, attributes_error) }
    var inside = Cursor { data: list, at: 0usize }
    var k = 0usize
    while k < count {
        let (at_tag, at_content, at_ok) = next(&inside)
        if !at_ok || at_tag != T_SEQUENCE { ret (none, Protocol) }
        var ac = Cursor { data: at_content, at: 0usize }
        let (nt, name_bytes, name_ok) = next(&ac)
        let (vt, values_bytes, values_ok) = next(&ac)
        if !name_ok || !values_ok || nt != T_OCTETS || vt != T_SET { ret (none, Protocol) }
        var value_count = 0usize
        var value_probe = Cursor { data: values_bytes, at: 0usize }
        while true {
            let (_, _, more) = next(&value_probe)
            if !more { break }
            value_count += 1usize
        }
        let (values, values_alloc) = mem.alloc[str](a, value_count + 1usize)
        if values_alloc != ok { ret (none, values_alloc) }
        var value_cursor = Cursor { data: values_bytes, at: 0usize }
        var v = 0usize
        while v < value_count {
            let (_, bytes, _) = next(&value_cursor)
            let (text, text_error) = copy_text(a, bytes)
            if text_error != ok { ret (none, text_error) }
            values[v] = text
            v += 1usize
        }
        let (name, name_error) = copy_text(a, name_bytes)
        if name_error != ok { ret (none, name_error) }
        attributes[k] = Attribute { name: name, values: values[..value_count] }
        k += 1usize
    }
    ret (Entry { dn: dn, attributes: attributes[..count] }, ok)
}

// The values of the attribute `name` (ASCII case-insensitive), empty when the entry has none.
fn values_of(entry: Entry, name: str) -> []const str {
    var i = 0usize
    while i < entry.attributes.len {
        if str.compare_ascii_fold(entry.attributes[i].name, name) == 0i32 { ret entry.attributes[i].values }
        i += 1usize
    }
    ret zero
}

// SEARCH: every SearchResultEntry up to SearchResultDone. `attributes` empty means all user attributes.
// A non-success result (including sizeLimitExceeded) is `Rejected` and the entries read so far are still answered.
fn search(s: *Session, base: str, scope: u8, filter: str, attributes: []const str, size_limit: u32, time_limit: u32, types_only: bool) -> ([]const Entry, err) {
    if !clean(base) || scope > 2u8 { ret (zero, Invalid) }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    let op = begin(&w, OP_SEARCH)
    w_octets(&w, T_OCTETS, base)
    w_integer(&w, T_ENUMERATED, i64(scope))
    w_integer(&w, T_ENUMERATED, 0i64)
    w_integer(&w, T_INTEGER, i64(size_limit))
    w_integer(&w, T_INTEGER, i64(time_limit))
    w_byte(&w, T_BOOLEAN)
    w_byte(&w, 1u8)
    if types_only { w_byte(&w, 255u8) } else { w_byte(&w, 0u8) }
    var filter_buf: [4096]u8 = zero
    let (filter_len, filter_error) = encode_filter(filter_buf[0..], filter)
    if filter_error != ok { ret (zero, filter_error) }
    w_bytes(&w, filter_buf[..filter_len])
    let list = begin(&w, T_SEQUENCE)
    var i = 0usize
    while i < attributes.len {
        w_octets(&w, T_OCTETS, attributes[i])
        i += 1usize
    }
    end(&w, list)
    end(&w, op)
    let send_error = send_message(s, &w, mark)
    if send_error != ok { ret (zero, send_error) }
    var entries: []Entry = zero
    var count = 0usize
    s.references = 0usize
    while true {
        let (tag, content, read_error) = read_for(s, id)
        if read_error != ok { ret (entries[..count], read_error) }
        if tag == OP_ENTRY {
            let (entry, entry_error) = parse_entry(s.a, content)
            if entry_error != ok { ret (entries[..count], entry_error) }
            if count >= entries.len {
                var grown = entries.len * 2usize
                if grown < 16usize { grown = 16usize }
                let (bigger, alloc_error) = mem.alloc[Entry](s.a, grown)
                if alloc_error != ok { ret (entries[..count], alloc_error) }
                var k = 0usize
                while k < count {
                    bigger[k] = entries[k]
                    k += 1usize
                }
                entries = bigger
            }
            entries[count] = entry
            count += 1usize
            continue
        }
        if tag == OP_REFERENCE {
            s.references += 1usize
            continue
        }
        if tag == OP_INTERMEDIATE { continue }
        if tag != OP_DONE { ret (entries[..count], Protocol) }
        var c = Cursor { data: content, at: 0usize }
        let (result, result_error) = parse_result(s.a, &c)
        if result_error != ok { ret (entries[..count], result_error) }
        s.last = result
        if result.code != 0u32 { ret (entries[..count], Rejected) }
        ret (entries[..count], ok)
    }
    ret (entries[..count], Protocol)
}

// COMPARE: whether the entry has the attribute value (compareTrue / compareFalse); other codes are `Rejected`.
fn compare(s: *Session, dn: str, attribute: str, value: str) -> (bool, err) {
    if !clean(dn) || !clean(attribute) || attribute.len == 0usize { ret (false, Invalid) }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    let op = begin(&w, OP_COMPARE)
    w_octets(&w, T_OCTETS, dn)
    let ava = begin(&w, T_SEQUENCE)
    w_octets(&w, T_OCTETS, attribute)
    w_octets(&w, T_OCTETS, value)
    end(&w, ava)
    end(&w, op)
    let send_error = send_message(s, &w, mark)
    if send_error != ok { ret (false, send_error) }
    let status = expect_result(s, id, OP_COMPARE_RESPONSE)
    if status == ok { ret (false, Protocol) }
    if status == Rejected && s.last.code == 6u32 { ret (true, ok) }
    if status == Rejected && s.last.code == 5u32 { ret (false, ok) }
    ret (false, status)
}

fn put_values(w: *Writer, values: []const str) {
    let set = begin(w, T_SET)
    var i = 0usize
    while i < values.len {
        w_octets(w, T_OCTETS, values[i])
        i += 1usize
    }
    end(w, set)
}

// ADD an entry with its attributes.
fn add(s: *Session, dn: str, attributes: []const Attribute) -> err {
    if dn.len == 0usize || !clean(dn) { ret Invalid }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    let op = begin(&w, OP_ADD)
    w_octets(&w, T_OCTETS, dn)
    let list = begin(&w, T_SEQUENCE)
    var i = 0usize
    while i < attributes.len {
        let one = begin(&w, T_SEQUENCE)
        w_octets(&w, T_OCTETS, attributes[i].name)
        put_values(&w, attributes[i].values)
        end(&w, one)
        i += 1usize
    }
    end(&w, list)
    end(&w, op)
    try send_message(s, &w, mark)
    ret expect_result(s, id, OP_ADD_RESPONSE)
}

// MODIFY with a list of changes (MODIFY_ADD, MODIFY_DELETE or MODIFY_REPLACE each).
fn modify(s: *Session, dn: str, changes: []const Change) -> err {
    if dn.len == 0usize || !clean(dn) || changes.len == 0usize { ret Invalid }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    let op = begin(&w, OP_MODIFY)
    w_octets(&w, T_OCTETS, dn)
    let list = begin(&w, T_SEQUENCE)
    var i = 0usize
    while i < changes.len {
        if changes[i].operation > 2u8 { ret Invalid }
        let one = begin(&w, T_SEQUENCE)
        w_integer(&w, T_ENUMERATED, i64(changes[i].operation))
        let attribute = begin(&w, T_SEQUENCE)
        w_octets(&w, T_OCTETS, changes[i].attribute)
        put_values(&w, changes[i].values)
        end(&w, attribute)
        end(&w, one)
        i += 1usize
    }
    end(&w, list)
    end(&w, op)
    try send_message(s, &w, mark)
    ret expect_result(s, id, OP_MODIFY_RESPONSE)
}

// DELETE an entry.
fn delete(s: *Session, dn: str) -> err {
    if dn.len == 0usize || !clean(dn) { ret Invalid }
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, id) = begin_message(s, &w)
    w_octets(&w, OP_DELETE, dn)
    try send_message(s, &w, mark)
    ret expect_result(s, id, OP_DELETE_RESPONSE)
}

// UNBIND: no response is sent; the TLS stream is closed when there is one.
fn unbind(s: *Session) -> err {
    var w = Writer { buf: s.out, at: 0usize, failed: false }
    let (mark, _) = begin_message(s, &w)
    w_byte(&w, OP_UNBIND)
    w_byte(&w, 0u8)
    try send_message(s, &w, mark)
    if s.secured { ret tls.close(s.stream) }
    ret ok
}
