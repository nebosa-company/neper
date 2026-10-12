// `x.modbus.wire` against pymodbus (L151): scripts/modbus_vectors.py builds request and response PDUs with pymodbus's
// classes, frames them with its socket, RTU and ASCII framers, computes CRC-16 and LRC with its framer helpers and
// typed register values with `convert_to_registers`; the slave scenarios are judged by an independent reference
// slave written from the specification. This fixture encodes, parses, frames and executes the same inputs and
// compares bytes and text. Generated from scripts/modbus_fixture_template.e; do not edit.
use e.io
use e.mem
use e.os
use e.str
use x.modbus.wire as modbus

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
    if e == modbus.Truncated { ret "Truncated" }
    if e == modbus.Invalid { ret "Invalid" }
    if e == modbus.BadChecksum { ret "BadChecksum" }
    if e == modbus.TooSmall { ret "TooSmall" }
    if e == ok { ret "ok" }
    ret "other"
}

// A comma list of decimals into `out`; the count.
fn numbers(text: str, out: []u16) -> usize {
    let n = item_count(text, 44u8)
    var i = 0usize
    while i < n {
        let (item, found) = item_at(text, 44u8, i)
        out[i] = u16(num(item))
        i += 1usize
    }
    ret n
}

fn render_request(a: *mem.Arena, r: modbus.Request) -> str {
    var s = dec(a, u64(r.function))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.address)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.count)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.value)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.and_mask)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.or_mask)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.read_address)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.read_count)))
    s = cat(a, cat(a, s, ":"), hex(a, r.data))
    ret s
}

fn render_response(a: *mem.Arena, r: modbus.Response) -> str {
    var s = dec(a, u64(r.function))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.exception)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.address)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.count)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.value)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.and_mask)))
    s = cat(a, cat(a, s, ":"), dec(a, u64(r.or_mask)))
    s = cat(a, cat(a, s, ":"), hex(a, r.data))
    ret s
}

fn spec_part(spec: str, index: usize) -> u64 {
    let (item, found) = item_at(spec, 58u8, index)
    ret num(item)
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    var buf: [512]u8 = zero
    if str.eq(kind, "Q") {
        let spec = field(&rest)
        let want_pdu = field(&rest)
        let want_parsed = field(&rest)
        let (op, found) = item_at(spec, 58u8, 0usize)
        var n = 0usize
        var e: err = ok
        if str.eq(op, "rd") {
            let (n0, e0) = modbus.encode_read(buf[0usize..], u8(spec_part(spec, 1usize)), u16(spec_part(spec, 2usize)), u16(spec_part(spec, 3usize)))
            n = n0
            e = e0
        } else if str.eq(op, "ws") {
            let (n0, e0) = modbus.encode_write_single(buf[0usize..], u8(spec_part(spec, 1usize)), u16(spec_part(spec, 2usize)), u16(spec_part(spec, 3usize)))
            n = n0
            e = e0
        } else if str.eq(op, "wc") {
            let (packed_hex, f2) = item_at(spec, 58u8, 3usize)
            let (n0, e0) = modbus.encode_write_coils(buf[0usize..], u16(spec_part(spec, 1usize)), u16(spec_part(spec, 2usize)), unhex(a, packed_hex))
            n = n0
            e = e0
        } else if str.eq(op, "wr") {
            var regs: [64]u16 = zero
            let (list, f2) = item_at(spec, 58u8, 2usize)
            let count = numbers(list, regs[0usize..])
            let (n0, e0) = modbus.encode_write_registers(buf[0usize..], u16(spec_part(spec, 1usize)), regs[0usize..count])
            n = n0
            e = e0
        } else if str.eq(op, "mk") {
            let (n0, e0) = modbus.encode_mask_write(buf[0usize..], u16(spec_part(spec, 1usize)), u16(spec_part(spec, 2usize)), u16(spec_part(spec, 3usize)))
            n = n0
            e = e0
        } else if str.eq(op, "rw") {
            var regs: [64]u16 = zero
            let (list, f2) = item_at(spec, 58u8, 4usize)
            let count = numbers(list, regs[0usize..])
            let (n0, e0) = modbus.encode_read_write(buf[0usize..], u16(spec_part(spec, 1usize)), u16(spec_part(spec, 2usize)), u16(spec_part(spec, 3usize)), regs[0usize..count])
            n = n0
            e = e0
        } else {
            ret false
        }
        if e != ok || !str.eq(hex(a, buf[0usize..n]), want_pdu) { ret false }
        let (r, pe) = modbus.parse_request(buf[0usize..n])
        ret pe == ok && str.eq(render_request(a, r), want_parsed)
    }
    if str.eq(kind, "P") {
        let pdu = unhex(a, field(&rest))
        let want = field(&rest)
        let (r, e) = modbus.parse_response(pdu)
        ret e == ok && str.eq(render_response(a, r), want)
    }
    if str.eq(kind, "Pb") {
        let pdu = unhex(a, field(&rest))
        let (r, e) = modbus.parse_response(pdu)
        ret e != ok
    }
    if str.eq(kind, "Qb") {
        let pdu = unhex(a, field(&rest))
        let (r, e) = modbus.parse_request(pdu)
        ret e != ok
    }
    if str.eq(kind, "T") {
        let unit = u8(num(field(&rest)))
        let tid = u16(num(field(&rest)))
        let pdu = unhex(a, field(&rest))
        let want_tcp = field(&rest)
        let want_rtu = field(&rest)
        let want_ascii = field(&rest)
        let (n, e) = modbus.tcp_frame(buf[0usize..], tid, unit, pdu)
        if e != ok || !str.eq(hex(a, buf[0usize..n]), want_tcp) { ret false }
        let (f, used, pe) = modbus.tcp_parse(buf[0usize..n])
        if pe != ok || used != n || f.transaction != tid || f.unit != unit || !str.eq(f.pdu, pdu) { ret false }
        var rtu: [512]u8 = zero
        let (m, re) = modbus.rtu_frame(rtu[0usize..], unit, pdu)
        if re != ok || !str.eq(hex(a, rtu[0usize..m]), want_rtu) { ret false }
        let (rf, rpe) = modbus.rtu_parse(rtu[0usize..m])
        if rpe != ok || rf.unit != unit || !str.eq(rf.pdu, pdu) { ret false }
        var ascii: [1024]u8 = zero
        let (k, ae) = modbus.ascii_frame(ascii[0usize..], unit, pdu)
        if ae != ok || !str.eq(hex(a, ascii[0usize..k]), want_ascii) { ret false }
        var decoded: [512]u8 = zero
        let (af, ape) = modbus.ascii_parse(ascii[0usize..k], decoded[0usize..])
        ret ape == ok && af.unit == unit && str.eq(af.pdu, pdu)
    }
    if str.eq(kind, "K") {
        let data = unhex(a, field(&rest))
        let want_crc = num(field(&rest))
        let want_lrc = num(field(&rest))
        ret u64(modbus.crc16(data)) == want_crc && u64(modbus.lrc(data)) == want_lrc
    }
    if str.eq(kind, "Fb") {
        let mode = field(&rest)
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        var e: err = ok
        if str.eq(mode, "rtu") {
            let (f, re) = modbus.rtu_parse(raw)
            e = re
        } else if str.eq(mode, "tcp") {
            let (f, used, te) = modbus.tcp_parse(raw)
            e = te
        } else {
            var decoded: [512]u8 = zero
            let (f, ae) = modbus.ascii_parse(raw, decoded[0usize..])
            e = ae
        }
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "V") {
        let name = field(&rest)
        let order = field(&rest)
        let regs_text = field(&rest)
        let want = field(&rest)
        let little = str.eq(order, "little")
        var regs: [8]u16 = zero
        let count = numbers(regs_text, regs[0usize..])
        // The value's bytes, big-endian, as a struct.pack would give them, compared through the typed getters.
        var raw: [8]u8 = zero
        var out_text = ""
        if str.eq(name, "INT16") || str.eq(name, "UINT16") {
            raw[0usize] = u8(regs[0usize] >> 8u16)
            raw[1usize] = u8(regs[0usize] & 255u16)
            out_text = hex(a, raw[0usize..2usize])
        } else if str.eq(name, "INT32") || str.eq(name, "UINT32") {
            let v = modbus.get_u32(regs[0usize..], 0usize, little)
            raw[0usize] = u8(v >> 24u32)
            raw[1usize] = u8((v >> 16u32) & 255u32)
            raw[2usize] = u8((v >> 8u32) & 255u32)
            raw[3usize] = u8(v & 255u32)
            out_text = hex(a, raw[0usize..4usize])
            var back: [2]u16 = zero
            modbus.put_u32(back[0usize..], 0usize, v, little)
            if back[0usize] != regs[0usize] || back[1usize] != regs[1usize] { ret false }
        } else if str.eq(name, "FLOAT32") {
            let v = modbus.get_f32(regs[0usize..], 0usize, little)
            let bits = mem.bitcast[u32](v)
            raw[0usize] = u8(bits >> 24u32)
            raw[1usize] = u8((bits >> 16u32) & 255u32)
            raw[2usize] = u8((bits >> 8u32) & 255u32)
            raw[3usize] = u8(bits & 255u32)
            out_text = hex(a, raw[0usize..4usize])
            var back: [2]u16 = zero
            modbus.put_f32(back[0usize..], 0usize, v, little)
            if back[0usize] != regs[0usize] || back[1usize] != regs[1usize] { ret false }
        } else {
            let v = modbus.get_u64(regs[0usize..], 0usize, little)
            var k = 0usize
            while k < 8usize {
                raw[k] = u8((v >> u64(56usize - k * 8usize)) & 255u64)
                k += 1usize
            }
            out_text = hex(a, raw[0usize..8usize])
            var back: [4]u16 = zero
            if str.eq(name, "FLOAT64") {
                modbus.put_f64(back[0usize..], 0usize, modbus.get_f64(regs[0usize..], 0usize, little), little)
            } else {
                modbus.put_u64(back[0usize..], 0usize, v, little)
            }
            var j = 0usize
            while j < 4usize {
                if back[j] != regs[j] { ret false }
                j += 1usize
            }
        }
        ret str.eq(out_text, want) && count > 0usize
    }
    if str.eq(kind, "S") {
        var coils: [64]u8 = zero
        var discrete: [64]u8 = zero
        var holding: [64]u16 = zero
        var inputs: [64]u16 = zero
        var tmp: [64]u16 = zero
        let n_coils = numbers(field(&rest), tmp[0usize..])
        var i = 0usize
        while i < n_coils {
            coils[i] = u8(tmp[i])
            i += 1usize
        }
        let n_discrete = numbers(field(&rest), tmp[0usize..])
        i = 0usize
        while i < n_discrete {
            discrete[i] = u8(tmp[i])
            i += 1usize
        }
        let n_holding = numbers(field(&rest), holding[0usize..])
        let n_inputs = numbers(field(&rest), inputs[0usize..])
        let requests = field(&rest)
        let responses = field(&rest)
        let want_coils = field(&rest)
        let want_holding = field(&rest)
        var slave = modbus.Slave { coils: coils[0usize..n_coils], discrete: discrete[0usize..n_discrete], holding: holding[0usize..n_holding], input: inputs[0usize..n_inputs] }
        let count = item_count(requests, 59u8)
        var r = 0usize
        while r < count {
            let (req_hex, found) = item_at(requests, 59u8, r)
            let (resp_hex, found2) = item_at(responses, 59u8, r)
            let req = unhex(a, req_hex)
            var out: [512]u8 = zero
            let (n, e) = modbus.slave_handle(&slave, req, out[0usize..])
            if e != ok || !str.eq(hex(a, out[0usize..n]), resp_hex) { ret false }
            r += 1usize
        }
        var text = ""
        i = 0usize
        while i < n_coils {
            if i > 0usize { text = cat(a, text, ",") }
            text = cat(a, text, dec(a, u64(coils[i])))
            i += 1usize
        }
        if !str.eq(text, want_coils) { ret false }
        text = ""
        i = 0usize
        while i < n_holding {
            if i > 0usize { text = cat(a, text, ",") }
            text = cat(a, text, dec(a, u64(holding[i])))
            i += 1usize
        }
        ret str.eq(text, want_holding)
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
    try io.print("x modbus wire ok")
    ret ok
}
