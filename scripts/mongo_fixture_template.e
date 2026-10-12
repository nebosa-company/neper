// `x.mongodb.wire` against pymongo and bson (L114): scripts/mongo_vectors.py frames OP_MSG messages with pymongo's
// builder (flag bits, document sequences, the CRC-32C checksum from the `crc32c` package), encodes command and reply
// documents with `bson`, and runs pymongo's own SCRAM-SHA-256 client against a scripted server (the RFC 7677 exchange
// is asserted among them). This fixture builds and parses the same inputs and compares bytes and text.
// Generated from scripts/mongo_fixture_template.e; do not edit.
use e.fmt.bson as bson
use e.io
use e.mem
use e.os
use e.str
use x.mongodb.wire as wire

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = (nibble(h[i]) << 4u8) | nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

fn hex(a: *mem.Arena, b: []const u8) -> str {
    let digits = "0123456789abcdef"
    let (out, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { os.exit(91i32) }
    var i = 0usize
    while i < b.len {
        out[i * 2usize] = digits[usize(b[i] >> 4u8)]
        out[i * 2usize + 1usize] = digits[usize(b[i] & 15u8)]
        i += 1usize
    }
    ret out[0usize..b.len * 2usize]
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(92i32) }
    ret out
}

fn parse_i64(s: str) -> i64 {
    var negative = false
    var i = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        i = 1usize
    }
    var magnitude = 0u64
    while i < s.len {
        magnitude = magnitude * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    if negative { ret 0i64 - i64(magnitude) }
    ret i64(magnitude)
}

fn dec(a: *mem.Arena, n: u64) -> str {
    var buf: [24]u8 = zero
    var at = 24usize
    var v = n
    if v == 0u64 {
        at -= 1usize
        buf[at] = 48u8
    }
    while v > 0u64 {
        at -= 1usize
        buf[at] = 48u8 + u8(v % 10u64)
        v = v / 10u64
    }
    let (out, e) = mem.alloc[u8](a, 24usize - at)
    if e != ok { os.exit(93i32) }
    mem.copy[u8](out, buf[at..24usize])
    ret out
}

fn field(rest: *str) -> str {
    let (head, tail, found) = str.split_once(*rest, "\t")
    if !found {
        let all = *rest
        *rest = ""
        ret all
    }
    *rest = tail
    ret head
}

fn err_name(e: err) -> str {
    if e == wire.Truncated { ret "Truncated" }
    if e == wire.Invalid { ret "Invalid" }
    if e == wire.BadChecksum { ret "BadChecksum" }
    if e == wire.Unsupported { ret "Unsupported" }
    if e == wire.TooLarge { ret "TooLarge" }
    if e == wire.TooSmall { ret "TooSmall" }
    if e == ok { ret "ok" }
    ret "other"
}

// `id:hexdocs;id:hexdocs` into sequences (identifiers are hex in the text).
fn parse_sequences(a: *mem.Arena, text: str, out: []wire.Sequence) -> usize {
    var count = 0usize
    var cursor = text
    while cursor.len > 0usize {
        let (item, tail, more) = str.split_once(cursor, ";")
        var current = cursor
        if more {
            current = item
            cursor = tail
        } else {
            cursor = ""
        }
        let (id_hex, docs_hex, colon) = str.split_once(current, ":")
        if !colon { os.exit(96i32) }
        out[count] = wire.Sequence { identifier: unhex(a, id_hex), documents: unhex(a, docs_hex) }
        count += 1usize
    }
    ret count
}

fn render_sequences(a: *mem.Arena, seqs: []const wire.Sequence) -> str {
    var s = ""
    var i = 0usize
    while i < seqs.len {
        if i > 0usize { s = cat(a, s, ";") }
        s = cat(a, s, hex(a, seqs[i].identifier))
        s = cat(a, s, ":")
        s = cat(a, s, hex(a, seqs[i].documents))
        i += 1usize
    }
    ret s
}

fn double_of(a: *mem.Arena, bits_hex: str) -> f64 {
    let raw = unhex(a, bits_hex)
    var bits = 0u64
    var i = 0usize
    while i < 8usize {
        bits = (bits << 8u64) | u64(raw[i])
        i += 1usize
    }
    ret mem.bitcast[f64](bits)
}

// `key:type:value;...` into BSON elements.
fn parse_elements(a: *mem.Arena, text: str, out: []bson.Element) -> usize {
    var count = 0usize
    var cursor = text
    while cursor.len > 0usize {
        let (item, tail, more) = str.split_once(cursor, ";")
        var current = cursor
        if more {
            current = item
            cursor = tail
        } else {
            cursor = ""
        }
        let (key, rest, c1) = str.split_once(current, ":")
        let (kind, value_text, c2) = str.split_once(rest, ":")
        if !c1 || !c2 { os.exit(97i32) }
        var value: bson.Value = .Null
        if str.eq(kind, "i32") {
            value = bson.Value { I32: i32(parse_i64(value_text)) }
        } else if str.eq(kind, "i64") {
            value = bson.Value { I64: parse_i64(value_text) }
        } else if str.eq(kind, "str") {
            value = bson.Value { String: unhex(a, value_text) }
        } else if str.eq(kind, "bool") {
            value = bson.Value { Bool: str.eq(value_text, "1") }
        } else if str.eq(kind, "dbl") {
            value = bson.Value { Double: double_of(a, value_text) }
        }
        out[count] = bson.Element { key: key, value: value }
        count += 1usize
    }
    ret count
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    if str.eq(kind, "F") {
        let rid = i32(parse_i64(field(&rest)))
        let rto = i32(parse_i64(field(&rest)))
        let flags = u32(parse_i64(field(&rest)))
        let body = unhex(a, field(&rest))
        var seqs: [4]wire.Sequence = zero
        let n = parse_sequences(a, field(&rest), seqs[0usize..])
        let want = field(&rest)
        let (buf, buf_error) = mem.alloc[u8](a, 65536usize)
        if buf_error != ok { os.exit(98i32) }
        let (used, e) = wire.encode_op_msg(buf, rid, rto, flags, body, seqs[0usize..n])
        ret e == ok && str.eq(hex(a, buf[0usize..used]), want)
    }
    if str.eq(kind, "Q") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        let body = field(&rest)
        let seqs_text = field(&rest)
        let flags = parse_i64(field(&rest))
        let rid = parse_i64(field(&rest))
        let rto = parse_i64(field(&rest))
        var seqs: [4]wire.Sequence = zero
        let (m, used, e) = wire.parse(raw, seqs[0usize..])
        if !str.eq(err_name(e), want) { ret false }
        if e != ok { ret true }
        if used != raw.len { ret false }
        if !str.eq(hex(a, m.body), body) { ret false }
        if !str.eq(render_sequences(a, seqs[0usize..m.sequences]), seqs_text) { ret false }
        ret i64(m.flags) == flags && i64(m.request_id) == rid && i64(m.response_to) == rto
    }
    if str.eq(kind, "W") {
        let db = unhex(a, field(&rest))
        let spec = field(&rest)
        let want = field(&rest)
        var elements: [8]bson.Element = zero
        let n = parse_elements(a, spec, elements[0usize..])
        let (doc, e) = wire.command(a, db, elements[0usize..n])
        ret e == ok && str.eq(hex(a, doc), want)
    }
    if str.eq(kind, "S") {
        let body = unhex(a, field(&rest))
        let good = field(&rest)
        let code = parse_i64(field(&rest))
        let name = unhex(a, field(&rest))
        let message = unhex(a, field(&rest))
        let (s, e) = wire.status(a, body)
        if str.eq(good, "Invalid") { ret e == wire.Invalid }
        if e != ok { ret false }
        ret s.good == str.eq(good, "1") && s.code == code && str.eq(s.code_name, name) && str.eq(s.message, message)
    }
    if str.eq(kind, "A") {
        let user = unhex(a, field(&rest))
        let password = unhex(a, field(&rest))
        let first = unhex(a, field(&rest))
        let server_first = unhex(a, field(&rest))
        let final = unhex(a, field(&rest))
        let server_final = unhex(a, field(&rest))
        // The nonce is whatever the client-first message carries after `r=`.
        let (nonce, found) = wire.scram_field(first[3usize..], 114u8)
        if !found { ret false }
        var buf: [512]u8 = zero
        let (n, e) = wire.scram_first(buf[0usize..], user, nonce)
        if e != ok || !str.eq(buf[0usize..n], first) { ret false }
        var out: [512]u8 = zero
        var expected: [64]u8 = zero
        let (m, sig_len, final_error) = wire.scram_final(out[0usize..], first[3usize..], server_first, password, nonce, expected[0usize..])
        if final_error != ok || !str.eq(out[0usize..m], final) { ret false }
        if !wire.scram_verify(server_final, expected[0usize..sig_len]) { ret false }
        // A wrong signature or an error answer is refused.
        if wire.scram_verify("v=AAAA", expected[0usize..sig_len]) || wire.scram_verify("e=invalid-proof", expected[0usize..sig_len]) { ret false }
        ret true
    }
    if str.eq(kind, "T") {
        let want = field(&rest)
        // saslStart as pymongo builds it: command, mechanism, payload, autoAuthorize, options.
        var options: [1]bson.Element = zero
        options[0usize] = bson.Element { key: "skipEmptyExchange", value: bson.Value { Bool: true } }
        var elements: [5]bson.Element = zero
        elements[0usize] = bson.Element { key: "saslStart", value: bson.Value { I32: 1i32 } }
        elements[1usize] = bson.Element { key: "mechanism", value: bson.Value { String: "SCRAM-SHA-256" } }
        elements[2usize] = bson.Element { key: "payload", value: bson.Value { Binary: bson.Binary { subtype: 0u8, data: "n,,n=user,r=rOprNGfwEbeRWgbNEkqO" } } }
        elements[3usize] = bson.Element { key: "autoAuthorize", value: bson.Value { I32: 1i32 } }
        elements[4usize] = bson.Element { key: "options", value: bson.Value { Document: options[0usize..] } }
        let (doc, e) = wire.command(a, "admin", elements[0usize..])
        ret e == ok && str.eq(hex(a, doc), want)
    }
    if str.eq(kind, "K") {
        let data = unhex(a, field(&rest))
        let want = parse_i64(field(&rest))
        ret i64(wire.crc32c(data)) == want
    }
    ret false
}

//__VECTOR_FUNCTIONS__
fn fail(line: str) {
    let shown = io.print(line)
}

fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            if !run_one(a, line) {
                fail(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("x mongodb wire ok")
    ret ok
}
