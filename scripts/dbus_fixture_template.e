// `e.dbus` against dbus-next (L126): scripts/dbus_vectors.py marshals random typed bodies and whole messages with
// dbus-next's `Marshaller` and `Message._marshall` (little-endian, its header-field order), reads them back with its
// `Unmarshaller`, and builds the big-endian twins with a reference marshaller asserted byte-equal to the library's on
// every little-endian vector. This fixture decodes each input, compares the rendered values, and re-encodes the
// decoded values (same byte order) to compare bytes, which exercises alignment, array padding and length patching.
// Authentication, match rules and addresses follow the specification. Generated from scripts/dbus_fixture_template.e.
use e.dbus
use e.io
use e.mem
use e.os
use e.str

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

fn dec_u(a: *mem.Arena, n: u64) -> str {
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

fn dec_i(a: *mem.Arena, n: i64) -> str {
    if n >= 0i64 { ret dec_u(a, u64(n)) }
    let magnitude = u64(0i64 - (n + 1i64)) + 1u64
    ret cat(a, "-", dec_u(a, magnitude))
}

fn num(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret v
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

fn item_at(text: str, sep: u8, index: usize) -> (str, bool) {
    var start = 0usize
    var n = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == sep {
            if n == index { ret (text[start..i], true) }
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ("", false)
}

fn item_count(text: str, sep: u8) -> usize {
    if text.len == 0usize { ret 0usize }
    var n = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == sep { n += 1usize }
        i += 1usize
    }
    ret n
}

fn err_name(e: err) -> str {
    if e == dbus.Truncated { ret "Truncated" }
    if e == dbus.Invalid { ret "Invalid" }
    if e == dbus.Unsupported { ret "Unsupported" }
    if e == dbus.TooLarge { ret "TooLarge" }
    if e == dbus.Rejected { ret "Rejected" }
    if e == ok { ret "ok" }
    ret "other"
}

fn bits_hex(a: *mem.Arena, bits: u64) -> str {
    var raw: [8]u8 = zero
    var i = 0usize
    while i < 8usize {
        raw[i] = u8((bits >> u64(56usize - i * 8usize)) & 255u64)
        i += 1usize
    }
    ret hex(a, raw[0usize..8usize])
}

fn render(a: *mem.Arena, v: dbus.Value) -> str {
    switch v {
    case .Byte as n:
        ret cat(a, "y", dec_u(a, u64(n)))
    case .Bool as b:
        if b { ret "b1" }
        ret "b0"
    case .I16 as n:
        ret cat(a, "n", dec_i(a, i64(n)))
    case .U16 as n:
        ret cat(a, "q", dec_u(a, u64(n)))
    case .I32 as n:
        ret cat(a, "i", dec_i(a, i64(n)))
    case .U32 as n:
        ret cat(a, "u", dec_u(a, u64(n)))
    case .I64 as n:
        ret cat(a, "x", dec_i(a, n))
    case .U64 as n:
        ret cat(a, "t", dec_u(a, n))
    case .Fd as n:
        ret cat(a, "h", dec_u(a, u64(n)))
    case .Double as d:
        ret cat(a, "d", bits_hex(a, mem.bitcast[u64](d)))
    case .Str as s:
        ret cat(a, "s", hex(a, s))
    case .Path as s:
        ret cat(a, "o", hex(a, s))
    case .Sig as s:
        ret cat(a, "g", hex(a, s))
    case .Variant as inner:
        ret cat(a, cat(a, cat(a, cat(a, "V", hex(a, inner.signature)), "("), render(a, inner.value[0usize])), ")")
    case .Struct as members:
        var s = "("
        var i = 0usize
        while i < members.len {
            if i > 0usize { s = cat(a, s, ",") }
            s = cat(a, s, render(a, members[i]))
            i += 1usize
        }
        ret cat(a, s, ")")
    case .Entry as pair:
        ret cat(a, cat(a, cat(a, cat(a, "{", render(a, pair[0usize])), "="), render(a, pair[1usize])), "}")
    case .Array as arr:
        var s = cat(a, cat(a, "A", hex(a, arr.element)), "[")
        var i = 0usize
        while i < arr.items.len {
            if i > 0usize { s = cat(a, s, ",") }
            s = cat(a, s, render(a, arr.items[i]))
            i += 1usize
        }
        ret cat(a, s, "]")
    }
    ret "?"
}

fn render_body(a: *mem.Arena, body: []const dbus.Value) -> str {
    var s = ""
    var i = 0usize
    while i < body.len {
        if i > 0usize { s = cat(a, s, ";") }
        s = cat(a, s, render(a, body[i]))
        i += 1usize
    }
    ret s
}

fn render_message(a: *mem.Arena, m: dbus.Message) -> str {
    var s = dec_u(a, u64(m.kind))
    s = cat(a, cat(a, s, "|"), dec_u(a, u64(m.flags)))
    s = cat(a, cat(a, s, "|"), dec_u(a, u64(m.serial)))
    s = cat(a, cat(a, s, "|"), m.path)
    s = cat(a, cat(a, s, "|"), m.interface)
    s = cat(a, cat(a, s, "|"), m.member)
    s = cat(a, cat(a, s, "|"), m.error_name)
    s = cat(a, cat(a, s, "|"), dec_u(a, u64(m.reply_serial)))
    s = cat(a, cat(a, s, "|"), m.destination)
    s = cat(a, cat(a, s, "|"), m.sender)
    s = cat(a, cat(a, s, "|"), m.signature)
    s = cat(a, cat(a, s, "|"), dec_u(a, u64(m.unix_fds)))
    s = cat(a, cat(a, s, "|"), render_body(a, m.body))
    ret s
}

// Decode the values of `sig` from `raw`, appending to `out`; the count.
fn decode_body(a: *mem.Arena, raw: []const u8, little: bool, sig: str, out: []dbus.Value) -> (usize, err) {
    var at = 0usize
    var count = 0usize
    var i = 0usize
    while i < sig.len {
        let n = dbus.complete_len(sig, i, 0u32, 0u32)
        if n == 0usize { ret (0usize, dbus.Invalid) }
        let (v, e) = dbus.get_value(a, raw, &at, little, sig[i..i + n], 0u32)
        if e != ok { ret (0usize, e) }
        out[count] = v
        count += 1usize
        i += n
    }
    if at != raw.len { ret (0usize, dbus.Invalid) }
    ret (count, ok)
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    if str.eq(kind, "B") {
        let little = str.eq(field(&rest), "1")
        let sig = unhex(a, field(&rest))
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        var values: [8]dbus.Value = zero
        let (count, e) = decode_body(a, raw, little, sig, values[0usize..])
        if e != ok { ret false }
        if !str.eq(render_body(a, values[0usize..count]), want) { ret false }
        // Re-encode and compare bytes.
        let (buf, buf_error) = mem.alloc[u8](a, raw.len + 64usize)
        if buf_error != ok { os.exit(94i32) }
        var at = 0usize
        var i = 0usize
        var v = 0usize
        while i < sig.len {
            let n = dbus.complete_len(sig, i, 0u32, 0u32)
            let pe = dbus.put_value(buf, &at, little, sig[i..i + n], values[v])
            if pe != ok { ret false }
            i += n
            v += 1usize
        }
        ret str.eq(buf[0usize..at], raw)
    }
    if str.eq(kind, "Bx") {
        let little = str.eq(field(&rest), "1")
        let sig = unhex(a, field(&rest))
        let raw = unhex(a, field(&rest))
        var values: [8]dbus.Value = zero
        let (count, e) = decode_body(a, raw, little, sig, values[0usize..])
        ret e != ok
    }
    if str.eq(kind, "M") {
        let little = str.eq(field(&rest), "1")
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        let (m, used, e) = dbus.message_decode(a, raw)
        if e != ok || used != raw.len || m.little != little { ret false }
        if !str.eq(render_message(a, m), cat(a, cat(a, cat(a, cat(a, dec_u(a, u64(m.kind)), "|"), cat(a, dec_u(a, u64(m.flags)), "|")), dec_u(a, u64(m.serial))), "")) && false { ret false }
        // The expected text has the nine field slots then the body; rebuild it the same way from the message.
        var text = dec_u(a, u64(m.kind))
        text = cat(a, cat(a, text, "|"), dec_u(a, u64(m.flags)))
        text = cat(a, cat(a, text, "|"), dec_u(a, u64(m.serial)))
        text = cat(a, cat(a, text, "|"), m.path)
        text = cat(a, cat(a, text, "|"), m.interface)
        text = cat(a, cat(a, text, "|"), m.member)
        text = cat(a, cat(a, text, "|"), m.error_name)
        text = cat(a, cat(a, text, "|"), dec_u(a, u64(m.reply_serial)))
        text = cat(a, cat(a, text, "|"), m.destination)
        text = cat(a, cat(a, text, "|"), m.sender)
        text = cat(a, cat(a, text, "|"), m.signature)
        text = cat(a, cat(a, text, "|"), dec_u(a, u64(m.unix_fds)))
        text = cat(a, cat(a, text, "|"), render_body(a, m.body))
        if !str.eq(text, want) { ret false }
        let (buf, buf_error) = mem.alloc[u8](a, raw.len + 64usize)
        if buf_error != ok { os.exit(95i32) }
        let (n, ee) = dbus.message_encode(buf, &m)
        ret ee == ok && str.eq(buf[0usize..n], raw)
    }
    if str.eq(kind, "Mx") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        let (m, used, e) = dbus.message_decode(a, raw)
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "H") {
        let which = field(&rest)
        let want = field(&rest)
        var calls: [8]dbus.Pending = zero
        var bus = dbus.bus_new(calls[0usize..])
        var out: [512]u8 = zero
        if str.eq(which, "hello") {
            let (m, e) = dbus.hello(&bus)
            if e != ok { ret false }
            let (n, ee) = dbus.message_encode(out[0usize..], &m)
            ret ee == ok && str.eq(hex(a, out[0usize..n]), want)
        }
        // RequestName and AddMatch are calls 2 and 3 of a connection that said Hello first.
        let (h, he) = dbus.hello(&bus)
        if he != ok { ret false }
        if str.eq(which, "request") {
            var body: [2]dbus.Value = zero
            body[0usize] = dbus.Value { Str: "org.example.App" }
            body[1usize] = dbus.Value { U32: 4u32 }
            let (m, e) = dbus.call(&bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", "su", body[0usize..], 0u8)
            if e != ok { ret false }
            let (n, ee) = dbus.message_encode(out[0usize..], &m)
            ret ee == ok && str.eq(hex(a, out[0usize..n]), want)
        }
        var body: [1]dbus.Value = zero
        body[0usize] = dbus.Value { Str: "type='signal',interface='org.example.Iface'" }
        let (m, e) = dbus.call(&bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch", "s", body[0usize..], 0u8)
        if e != ok { ret false }
        let (n, ee) = dbus.message_encode(out[0usize..], &m)
        ret ee == ok && str.eq(hex(a, out[0usize..n]), want)
    }
    if str.eq(kind, "A") {
        let uid = field(&rest)
        let want = unhex(a, field(&rest))
        var buf: [128]u8 = zero
        let (n, e) = dbus.auth_external(buf[0usize..], uid)
        ret e == ok && str.eq(buf[0usize..n], want)
    }
    if str.eq(kind, "Aa") {
        let want = unhex(a, field(&rest))
        var buf: [64]u8 = zero
        let (n, e) = dbus.auth_anonymous(buf[0usize..])
        ret e == ok && str.eq(buf[0usize..n], want)
    }
    if str.eq(kind, "Ar") {
        let text = unhex(a, field(&rest))
        let want = field(&rest)
        var buf: [64]u8 = zero
        let (n, begun, e) = dbus.auth_reply(text, buf[0usize..])
        if str.eq(want, "begin") { ret e == ok && begun && str.eq(buf[0usize..n], "BEGIN\r\n") }
        if str.eq(want, "continue") { ret e == ok && !begun && n == 0usize }
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "R") {
        let rule = unhex(a, field(&rest))
        var m = dbus.message(dbus.SIGNAL, 1u32)
        let type_name = unhex(a, field(&rest))
        if str.eq(type_name, "method_call") { m.kind = dbus.METHOD_CALL }
        if str.eq(type_name, "method_return") { m.kind = dbus.METHOD_RETURN }
        if str.eq(type_name, "error") { m.kind = dbus.ERROR }
        m.sender = unhex(a, field(&rest))
        m.interface = unhex(a, field(&rest))
        m.member = unhex(a, field(&rest))
        m.path = unhex(a, field(&rest))
        m.destination = unhex(a, field(&rest))
        let args = field(&rest)
        let want = str.eq(field(&rest), "1")
        var body: [8]dbus.Value = zero
        var n = 0usize
        if !str.eq(args, "-") {
            n = item_count(args, 44u8)
            var i = 0usize
            while i < n {
                let (item, found) = item_at(args, 44u8, i)
                body[i] = dbus.Value { Str: unhex(a, item) }
                i += 1usize
            }
        }
        m.body = body[0usize..n]
        ret dbus.rule_matches(rule, &m) == want
    }
    if str.eq(kind, "D") {
        let text = unhex(a, field(&rest))
        let want = field(&rest)
        var buf: [256]u8 = zero
        let (addr, e) = dbus.parse_address(text, buf[0usize..])
        if str.eq(want, "Invalid") { ret e == dbus.Invalid }
        if e != ok { ret false }
        var s = cat(a, addr.transport, "|")
        s = cat(a, cat(a, s, hex(a, addr.path)), "|")
        s = cat(a, cat(a, s, hex(a, addr.abstract_name)), "|")
        s = cat(a, cat(a, s, hex(a, addr.host)), "|")
        s = cat(a, cat(a, s, dec_u(a, u64(addr.port))), "|")
        s = cat(a, cat(a, s, hex(a, addr.guid)), "|")
        var rt = "0"
        if addr.runtime { rt = "1" }
        ret str.eq(cat(a, s, rt), want)
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
    try io.print("dbus ok")
    ret ok
}
