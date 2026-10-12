// MongoDB wire protocol, OP_MSG (L114), over caller buffers: message framing with document sequences and the optional
// CRC-32C checksum, command documents built through `e.fmt.bson` with `$db`, reply status, and the SCRAM-SHA-256
// client exchange (RFC 5802/7677 as MongoDB runs it). No sockets and no topology monitoring: the caller moves the
// bytes. Only OP_MSG is spoken (every server since 3.6); compressed messages (OP_COMPRESSED) and the legacy opcodes
// answer `Unsupported`. SCRAM works on ASCII passwords (SASLprep of non-ASCII is not implemented and says so).
//
// Memory: `parse` borrows the input; command and status helpers allocate from the arena they are given.
use e.bytes
use e.crypto.hash as hash
use e.crypto.kdf as kdf
use e.crypto.mac as mac
use e.fmt.bson as bson
use e.io
use e.mem
use e.str

error Truncated
error Invalid
error TooLarge
error Unsupported
error BadChecksum
error TooSmall
error AuthFailed

const OP_MSG: u32 = 2013u32
const OP_COMPRESSED: u32 = 2012u32
const CHECKSUM_PRESENT: u32 = 1u32
const MORE_TO_COME: u32 = 2u32
const EXHAUST_ALLOWED: u32 = 65536u32
const MAX_MESSAGE: usize = 48000000usize

// A document sequence (a kind 1 section): its identifier and the BSON documents back to back.
type Sequence = struct { identifier: str, documents: []const u8 }
type Message = struct { length: u32, request_id: i32, response_to: i32, opcode: u32, flags: u32, body: []const u8, sequences: usize, has_checksum: bool, more_to_come: bool, exhaust_allowed: bool }
type Status = struct { good: bool, code: i64, code_name: str, message: str }

fn le32(b: []const u8, at: usize) -> u32 {
    ret u32(b[at]) | (u32(b[at + 1usize]) << 8u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 3usize]) << 24u32)
}

fn put_le32(b: []u8, at: usize, v: u32) {
    b[at] = u8(v & 255u32)
    b[at + 1usize] = u8((v >> 8u32) & 255u32)
    b[at + 2usize] = u8((v >> 16u32) & 255u32)
    b[at + 3usize] = u8((v >> 24u32) & 255u32)
}

// CRC-32C (Castagnoli), reflected, as the OP_MSG checksum uses.
fn crc32c(data: []const u8) -> u32 {
    var crc = 4294967295u32
    var i = 0usize
    while i < data.len {
        crc = crc ^ u32(data[i])
        var bit = 0u8
        while bit < 8u8 {
            if (crc & 1u32) != 0u32 {
                crc = (crc >> 1u32) ^ 2197175160u32
            } else {
                crc = crc >> 1u32
            }
            bit += 1u8
        }
        i += 1usize
    }
    ret ~crc
}

// An OP_MSG: header, flag bits, the body document as a kind 0 section, each sequence as a kind 1 section, and a
// CRC-32C when `flags` carries `CHECKSUM_PRESENT`. Answers the bytes written.
fn encode_op_msg(dst: []u8, request_id: i32, response_to: i32, flags: u32, body: []const u8, sequences: []const Sequence) -> (usize, err) {
    var total = 16usize + 4usize + 1usize + body.len
    var i = 0usize
    while i < sequences.len {
        total += 1usize + 4usize + sequences[i].identifier.len + 1usize + sequences[i].documents.len
        i += 1usize
    }
    let checksum = (flags & CHECKSUM_PRESENT) != 0u32
    if checksum { total += 4usize }
    if total > MAX_MESSAGE { ret (0usize, TooLarge) }
    if total > dst.len { ret (0usize, TooSmall) }
    put_le32(dst, 0usize, u32(total))
    put_le32(dst, 4usize, u32(request_id))
    put_le32(dst, 8usize, u32(response_to))
    put_le32(dst, 12usize, OP_MSG)
    put_le32(dst, 16usize, flags)
    var at = 20usize
    dst[at] = 0u8
    at += 1usize
    mem.copy[u8](dst[at..at + body.len], body)
    at += body.len
    i = 0usize
    while i < sequences.len {
        let s = sequences[i]
        dst[at] = 1u8
        put_le32(dst, at + 1usize, u32(4usize + s.identifier.len + 1usize + s.documents.len))
        at += 5usize
        mem.copy[u8](dst[at..at + s.identifier.len], s.identifier)
        at += s.identifier.len
        dst[at] = 0u8
        at += 1usize
        mem.copy[u8](dst[at..at + s.documents.len], s.documents)
        at += s.documents.len
        i += 1usize
    }
    if checksum {
        put_le32(dst, at, crc32c(dst[0usize..at]))
        at += 4usize
    }
    ret (at, ok)
}

// One document's span: its declared length checked against the room left.
fn document_end(buf: []const u8, at: usize, limit: usize) -> (usize, err) {
    if at + 5usize > limit { ret (0usize, Truncated) }
    let n = usize(le32(buf, at))
    if n < 5usize { ret (0usize, Invalid) }
    if at + n > limit { ret (0usize, Truncated) }
    if buf[at + n - 1usize] != 0u8 { ret (0usize, Invalid) }
    ret (at + n, ok)
}

// The next document of a sequence's bytes, and where the one after it begins.
fn next_document(documents: []const u8, at: usize) -> ([]const u8, usize, err) {
    let (end, e) = document_end(documents, at, documents.len)
    if e != ok { ret ("", 0usize, e) }
    ret (documents[at..end], end, ok)
}

// One message at the front of `buf`: the bytes it occupies. The body is the kind 0 document; document sequences go to
// `seq_out` (`Message.sequences` is how many). `Truncated` until the whole message is present, `BadChecksum` when a
// present CRC-32C does not match.
fn parse(buf: []const u8, seq_out: []Sequence) -> (Message, usize, err) {
    var m: Message = zero
    if buf.len < 16usize { ret (m, 0usize, Truncated) }
    let length = usize(le32(buf, 0usize))
    if length < 16usize { ret (m, 0usize, Invalid) }
    if length > MAX_MESSAGE { ret (m, 0usize, TooLarge) }
    if buf.len < length { ret (m, 0usize, Truncated) }
    m.length = u32(length)
    m.request_id = i32(le32(buf, 4usize))
    m.response_to = i32(le32(buf, 8usize))
    m.opcode = le32(buf, 12usize)
    if m.opcode == OP_COMPRESSED { ret (m, 0usize, Unsupported) }
    if m.opcode != OP_MSG { ret (m, 0usize, Unsupported) }
    if length < 21usize { ret (m, 0usize, Invalid) }
    m.flags = le32(buf, 16usize)
    // Bits 0 and 1 are the known required flags besides 16 (exhaustAllowed); any other required bit is an error.
    if (m.flags & 65532u32) != 0u32 { ret (m, 0usize, Unsupported) }
    m.has_checksum = (m.flags & CHECKSUM_PRESENT) != 0u32
    m.more_to_come = (m.flags & MORE_TO_COME) != 0u32
    m.exhaust_allowed = (m.flags & EXHAUST_ALLOWED) != 0u32
    var end = length
    if m.has_checksum {
        if length < 25usize { ret (m, 0usize, Invalid) }
        end = length - 4usize
        if crc32c(buf[0usize..end]) != le32(buf, end) { ret (m, 0usize, BadChecksum) }
    }
    var at = 20usize
    var have_body = false
    var count = 0usize
    while at < end {
        let kind = buf[at]
        at += 1usize
        if kind == 0u8 {
            if have_body { ret (m, 0usize, Invalid) }
            let (doc_end, doc_error) = document_end(buf, at, end)
            if doc_error != ok { ret (m, 0usize, doc_error) }
            m.body = buf[at..doc_end]
            have_body = true
            at = doc_end
        } else if kind == 1u8 {
            if at + 4usize > end { ret (m, 0usize, Invalid) }
            let size = usize(le32(buf, at))
            if size < 5usize || at + size > end { ret (m, 0usize, Invalid) }
            let section_end = at + size
            var p = at + 4usize
            var id_end = p
            while id_end < section_end && buf[id_end] != 0u8 { id_end += 1usize }
            if id_end >= section_end { ret (m, 0usize, Invalid) }
            if count >= seq_out.len { ret (m, 0usize, TooSmall) }
            seq_out[count] = Sequence { identifier: buf[p..id_end], documents: buf[id_end + 1usize..section_end] }
            count += 1usize
            // Every document in the sequence is walked once so a bad length is refused here, not later.
            var d = id_end + 1usize
            while d < section_end {
                let (next_end, next_error) = document_end(buf, d, section_end)
                if next_error != ok { ret (m, 0usize, Invalid) }
                d = next_end
            }
            at = section_end
        } else {
            ret (m, 0usize, Invalid)
        }
    }
    if !have_body { ret (m, 0usize, Invalid) }
    m.sequences = count
    ret (m, length, ok)
}

// --- command documents -------------------------------------------------------------------------------------------

// A command as BSON: `elements` (the command name first) followed by `$db`.
fn command(a: *mem.Arena, db: str, elements: []const bson.Element) -> ([]const u8, err) {
    let (all, alloc_error) = mem.alloc[bson.Element](a, elements.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var i = 0usize
    while i < elements.len {
        all[i] = elements[i]
        i += 1usize
    }
    all[elements.len] = bson.Element { key: "$db", value: bson.Value { String: db } }
    let value = bson.Value { Document: all }
    let (size, size_error) = bson.size(&value)
    if size_error != ok { ret ("", size_error) }
    let (state, unused_sink, writer_error) = io.memory_writer(a, size + 16usize)
    if writer_error != ok { ret ("", writer_error) }
    var memory = state
    var out = io.writer(mem.cast[*void](&memory), io.memory_write)
    let write_error = bson.write(&out, &value)
    if write_error != ok { ret ("", write_error) }
    ret (io.memory_bytes(&memory), ok)
}

// The status every command reply carries: `ok`, and `code`, `codeName` and `errmsg` on failure.
fn status(a: *mem.Arena, body: []const u8) -> (Status, err) {
    var s: Status = zero
    let (value, parse_error) = bson.parse(a, body, 8u16)
    if parse_error != ok { ret (s, Invalid) }
    switch value {
    case .Document as elements:
        let (ok_value, has_ok) = bson.element_of(elements, "ok")
        if !has_ok { ret (s, Invalid) }
        let (flag, number) = bson.float_of(ok_value)
        if !number { ret (s, Invalid) }
        s.good = flag == 1.0
        let (code_value, has_code) = bson.element_of(elements, "code")
        if has_code {
            let (code, code_ok) = bson.integer_of(code_value)
            if code_ok { s.code = code }
        }
        let (name_value, has_name) = bson.element_of(elements, "codeName")
        if has_name {
            switch name_value {
            case .String as text:
                s.code_name = text
            default:
                s.code_name = ""
            }
        }
        let (message_value, has_message) = bson.element_of(elements, "errmsg")
        if has_message {
            switch message_value {
            case .String as text:
                s.message = text
            default:
                s.message = ""
            }
        }
        ret (s, ok)
    default:
        ret (s, Invalid)
    }
    ret (s, Invalid)
}

// --- SCRAM-SHA-256 -----------------------------------------------------------------------------------------------

fn put_text(dst: []u8, at: *usize, text: str) -> err {
    if *at + text.len > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + text.len], text)
    *at += text.len
    ret ok
}

fn ascii_only(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] >= 128u8 || s[i] < 32u8 { ret false }
        i += 1usize
    }
    ret true
}

// The client-first message: `n,,n=<user>,r=<nonce>` (`=` and `,` in a user name written `=3D`, `=2C`). The "bare"
// part, which the proof covers, is everything after the `n,,` gs2 header.
fn scram_first(dst: []u8, user: str, nonce: str) -> (usize, err) {
    if !ascii_only(user) || nonce.len == 0usize { ret (0usize, Unsupported) }
    var at = 0usize
    var e = put_text(dst, &at, "n,,n=")
    if e != ok { ret (0usize, e) }
    var i = 0usize
    while i < user.len {
        if user[i] == 61u8 {
            e = put_text(dst, &at, "=3D")
        } else if user[i] == 44u8 {
            e = put_text(dst, &at, "=2C")
        } else {
            e = put_text(dst, &at, user[i..i + 1usize])
        }
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    e = put_text(dst, &at, ",r=")
    if e != ok { ret (0usize, e) }
    e = put_text(dst, &at, nonce)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// The value of `<key>=` in a comma-separated SCRAM message.
fn scram_field(message: str, key: u8) -> (str, bool) {
    var start = 0usize
    var i = 0usize
    while i <= message.len {
        if i == message.len || message[i] == 44u8 {
            if i - start >= 2usize && message[start] == key && message[start + 1usize] == 61u8 {
                ret (message[start + 2usize..i], true)
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret ("", false)
}

fn parse_u32(s: str) -> (u32, bool) {
    if s.len == 0usize || s.len > 9usize { ret (0u32, false) }
    var v = 0u32
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0u32, false) }
        v = v * 10u32 + u32(s[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

// The client-final message for a server-first one, and the server signature (`v=` value) to expect back.
// `first_bare` is the client-first message without its `n,,`; `nonce` the client nonce it carried.
fn scram_final(dst: []u8, first_bare: str, server_first: str, password: str, nonce: str, expected: []u8) -> (usize, usize, err) {
    if !ascii_only(password) { ret (0usize, 0usize, Unsupported) }
    let (rnonce, has_r) = scram_field(server_first, 114u8)
    let (salt_text, has_s) = scram_field(server_first, 115u8)
    let (count_text, has_i) = scram_field(server_first, 105u8)
    if !has_r || !has_s || !has_i { ret (0usize, 0usize, AuthFailed) }
    if rnonce.len <= nonce.len || !str.eq(rnonce[0usize..nonce.len], nonce) { ret (0usize, 0usize, AuthFailed) }
    let (iterations, iterations_ok) = parse_u32(count_text)
    if !iterations_ok || iterations < 4096u32 { ret (0usize, 0usize, AuthFailed) }
    var salt: [64]u8 = zero
    let (salt_bytes, salt_error) = bytes.base64_decode(salt[0usize..], salt_text, .Standard)
    if salt_error != ok { ret (0usize, 0usize, AuthFailed) }
    var salted: [32]u8 = zero
    let kdf_error = kdf.pbkdf2_sha256(password, salt_bytes, iterations, salted[0usize..])
    if kdf_error != ok { ret (0usize, 0usize, AuthFailed) }
    let client_key = mac.hmac_sha256(salted[0usize..], "Client Key")
    let server_key = mac.hmac_sha256(salted[0usize..], "Server Key")
    let stored_key = hash.sha256(client_key[0usize..])
    // AuthMessage = client-first-bare "," server-first "," client-final-without-proof
    var message: [1024]u8 = zero
    var m = 0usize
    var e = put_text(message[0usize..], &m, first_bare)
    if e != ok { ret (0usize, 0usize, e) }
    e = put_text(message[0usize..], &m, ",")
    if e != ok { ret (0usize, 0usize, e) }
    e = put_text(message[0usize..], &m, server_first)
    if e != ok { ret (0usize, 0usize, e) }
    e = put_text(message[0usize..], &m, ",c=biws,r=")
    if e != ok { ret (0usize, 0usize, e) }
    e = put_text(message[0usize..], &m, rnonce)
    if e != ok { ret (0usize, 0usize, e) }
    let client_signature = mac.hmac_sha256(stored_key[0usize..], message[0usize..m])
    var proof: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        proof[i] = client_key[i] ^ client_signature[i]
        i += 1usize
    }
    var at = 0usize
    e = put_text(dst, &at, "c=biws,r=")
    if e != ok { ret (0usize, 0usize, e) }
    e = put_text(dst, &at, rnonce)
    if e != ok { ret (0usize, 0usize, e) }
    e = put_text(dst, &at, ",p=")
    if e != ok { ret (0usize, 0usize, e) }
    if at + 44usize > dst.len { ret (0usize, 0usize, TooSmall) }
    let (proof_text, proof_error) = bytes.base64_encode(dst[at..], proof[0usize..], .Standard, true)
    if proof_error != ok { ret (0usize, 0usize, TooSmall) }
    at += proof_text.len
    let server_signature = mac.hmac_sha256(server_key[0usize..], message[0usize..m])
    if expected.len < 44usize { ret (0usize, 0usize, TooSmall) }
    let (sig_text, sig_error) = bytes.base64_encode(expected, server_signature[0usize..], .Standard, true)
    if sig_error != ok { ret (0usize, 0usize, TooSmall) }
    ret (at, sig_text.len, ok)
}

// Whether the server-final message is `v=<expected signature>` (an `e=` answer is a failure).
fn scram_verify(server_final: str, expected: str) -> bool {
    let (v, found) = scram_field(server_final, 118u8)
    if !found || v.len != expected.len { ret false }
    var diff = 0u8
    var i = 0usize
    while i < v.len {
        diff = diff | (v[i] ^ expected[i])
        i += 1usize
    }
    ret diff == 0u8
}
