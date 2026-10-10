// `e.net.packet` and `e.net.pcap` against an independent implementation written from the specs: scripts/packet_vectors.py
// builds frames, checksums, built packets and capture files with `struct` and gives the expected decode; the fixture runs
// the codecs over the same bytes (a decoded frame as the chain of layers, fields as numbers and hex) and compares.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.net.packet as packet
use e.net.pcap as pcap
use e.os
use e.str

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn number_of(v: json.Value, key: str) -> f64 {
    let x = ir.value_of(v, key)
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret 0.0f64
    }
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn bv(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn nv(a: *mem.Arena, n: f64) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, n) } } }

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

fn hex_fixed(a: *mem.Arena, b: []const u8) -> str { ret hex(a, b) }

fn fail(a: *mem.Arena, e: err) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(false))
    if e == packet.Truncated {
        put(&o, "error", sv("truncated"))
    } else {
        put(&o, "error", sv("invalid"))
    }
    ret ir.obj_value(&o)
}

fn parse_chain(a: *mem.Arena, frame: []const u8) -> json.Value {
    let (eth, ee) = packet.parse_ethernet(frame)
    if ee != ok { ret fail(a, ee) }
    var out = obj(a)
    var layer = obj(a)
    put(&layer, "dst", sv(hex_fixed(a, eth.dst[0usize..6usize])))
    put(&layer, "src", sv(hex_fixed(a, eth.src[0usize..6usize])))
    put(&layer, "type", nv(a, f64(eth.ethertype)))
    put(&layer, "vlans", nv(a, f64(eth.vlan_count)))
    put(&layer, "vid", nv(a, f64(eth.vlan_id)))
    put(&layer, "pcp", nv(a, f64(eth.vlan_pcp)))
    put(&out, "eth", ir.obj_value(&layer))
    var proto = 0u8
    var segment: []const u8 = zero
    var v6 = false
    var src4: [4]u8 = zero
    var dst4: [4]u8 = zero
    var src6: [16]u8 = zero
    var dst6: [16]u8 = zero
    var has_l4 = false
    if eth.ethertype == 2054u16 {
        let (ar, ae) = packet.parse_arp(eth.payload)
        if ae != ok { ret fail(a, ae) }
        var al = obj(a)
        put(&al, "op", nv(a, f64(ar.operation)))
        put(&al, "smac", sv(hex_fixed(a, ar.sender_mac[0usize..6usize])))
        put(&al, "sip", sv(hex_fixed(a, ar.sender_ip[0usize..4usize])))
        put(&al, "tmac", sv(hex_fixed(a, ar.target_mac[0usize..6usize])))
        put(&al, "tip", sv(hex_fixed(a, ar.target_ip[0usize..4usize])))
        put(&out, "arp", ir.obj_value(&al))
    } else if eth.ethertype == 2048u16 {
        let (ip, ie) = packet.parse_ipv4(eth.payload)
        if ie != ok { ret fail(a, ie) }
        var il = obj(a)
        put(&il, "v", nv(a, 4.0f64))
        put(&il, "ihl", nv(a, f64(ip.ihl)))
        put(&il, "dscp", nv(a, f64(ip.dscp)))
        put(&il, "ecn", nv(a, f64(ip.ecn)))
        put(&il, "total", nv(a, f64(ip.total_length)))
        put(&il, "id", nv(a, f64(ip.id)))
        put(&il, "flags", nv(a, f64(ip.flags)))
        put(&il, "frag", nv(a, f64(ip.fragment_offset)))
        put(&il, "ttl", nv(a, f64(ip.ttl)))
        put(&il, "proto", nv(a, f64(ip.protocol)))
        put(&il, "ck", nv(a, f64(ip.checksum)))
        put(&il, "ckok", bv(ip.checksum_ok))
        put(&il, "src", sv(hex_fixed(a, ip.src[0usize..4usize])))
        put(&il, "dst", sv(hex_fixed(a, ip.dst[0usize..4usize])))
        put(&il, "options", sv(hex(a, ip.options)))
        put(&out, "ip", ir.obj_value(&il))
        proto = ip.protocol
        segment = ip.payload
        src4 = ip.src
        dst4 = ip.dst
        has_l4 = true
    } else if eth.ethertype == 34525u16 {
        let (ip, ie) = packet.parse_ipv6(eth.payload)
        if ie != ok { ret fail(a, ie) }
        var il = obj(a)
        put(&il, "v", nv(a, 6.0f64))
        put(&il, "tc", nv(a, f64(ip.traffic_class)))
        put(&il, "flow", nv(a, f64(ip.flow_label)))
        put(&il, "plen", nv(a, f64(ip.payload_length)))
        put(&il, "nh", nv(a, f64(ip.next_header)))
        put(&il, "hop", nv(a, f64(ip.hop_limit)))
        put(&il, "src", sv(hex_fixed(a, ip.src[0usize..16usize])))
        put(&il, "dst", sv(hex_fixed(a, ip.dst[0usize..16usize])))
        put(&il, "proto", nv(a, f64(ip.protocol)))
        put(&il, "frag", bv(ip.fragment))
        put(&il, "fo", nv(a, f64(ip.fragment_offset)))
        put(&il, "mf", bv(ip.more_fragments))
        put(&out, "ip", ir.obj_value(&il))
        proto = ip.protocol
        segment = ip.payload
        src6 = ip.src
        dst6 = ip.dst
        v6 = true
        has_l4 = true
    }
    if has_l4 && proto == 6u8 {
        let (t, te) = packet.parse_tcp(segment)
        if te != ok { ret fail(a, te) }
        var tl = obj(a)
        put(&tl, "sp", nv(a, f64(t.src_port)))
        put(&tl, "dp", nv(a, f64(t.dst_port)))
        put(&tl, "seq", nv(a, f64(t.seq)))
        put(&tl, "ack", nv(a, f64(t.ack)))
        put(&tl, "off", nv(a, f64(t.data_offset)))
        put(&tl, "flags", nv(a, f64(t.flags)))
        put(&tl, "win", nv(a, f64(t.window)))
        put(&tl, "ck", nv(a, f64(t.checksum)))
        put(&tl, "urg", nv(a, f64(t.urgent)))
        var good = false
        if v6 {
            good = packet.transport_ok_v6(src6, dst6, 6u8, segment)
        } else {
            good = packet.transport_ok_v4(src4, dst4, 6u8, segment)
        }
        put(&tl, "ckok", bv(good))
        put(&tl, "options", sv(hex(a, t.options)))
        put(&tl, "payload", sv(hex(a, t.payload)))
        put(&out, "tcp", ir.obj_value(&tl))
    } else if has_l4 && proto == 17u8 {
        let (u, ue) = packet.parse_udp(segment)
        if ue != ok { ret fail(a, ue) }
        var ul = obj(a)
        put(&ul, "sp", nv(a, f64(u.src_port)))
        put(&ul, "dp", nv(a, f64(u.dst_port)))
        put(&ul, "len", nv(a, f64(u.length)))
        put(&ul, "ck", nv(a, f64(u.checksum)))
        put(&ul, "payload", sv(hex(a, u.payload)))
        put(&out, "udp", ir.obj_value(&ul))
    } else if has_l4 && (proto == 1u8 || proto == 58u8) {
        let (m, me) = packet.parse_icmp(segment)
        if me != ok { ret fail(a, me) }
        var ml = obj(a)
        put(&ml, "type", nv(a, f64(m.kind)))
        put(&ml, "code", nv(a, f64(m.code)))
        put(&ml, "ck", nv(a, f64(m.checksum)))
        put(&ml, "rest", nv(a, f64(m.rest)))
        put(&ml, "payload", sv(hex(a, m.payload)))
        put(&out, "icmp", ir.obj_value(&ml))
    }
    var o = obj(a)
    put(&o, "ok", bv(true))
    put(&o, "v", ir.obj_value(&out))
    ret ir.obj_value(&o)
}

fn arr4(b: []const u8) -> [4]u8 {
    var out: [4]u8 = zero
    var i = 0usize
    while i < 4usize {
        out[i] = b[i]
        i += 1usize
    }
    ret out
}

fn arr16(b: []const u8) -> [16]u8 {
    var out: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        out[i] = b[i]
        i += 1usize
    }
    ret out
}

fn pcap_result(a: *mem.Arena, data: []const u8) -> json.Value {
    var o = obj(a)
    var r: pcap.Reader = zero
    let (opened, oe) = pcap.open(data)
    var list: [64]json.Value = zero
    var n = 0usize
    var error_name = ""
    var failed = false
    if oe != ok {
        failed = true
        if oe == pcap.Truncated {
            error_name = "truncated"
        } else {
            error_name = "invalid"
        }
    } else {
        r = opened
        while true {
            let (rec, has, e) = pcap.next(&r)
            if e != ok {
                failed = true
                if e == pcap.Truncated {
                    error_name = "truncated"
                } else {
                    error_name = "invalid"
                }
                break
            }
            if !has { break }
            var ro = obj(a)
            put(&ro, "sec", nv(a, f64(rec.ts_sec)))
            put(&ro, "ns", nv(a, f64(rec.ts_nsec)))
            put(&ro, "cap", nv(a, f64(rec.caplen)))
            put(&ro, "orig", nv(a, f64(rec.origlen)))
            put(&ro, "h", sv(hex(a, rec.data)))
            if n < 64usize {
                list[n] = ir.obj_value(&ro)
                n += 1usize
            }
        }
    }
    let (out, e) = mem.alloc[json.Value](a, n + 1usize)
    var i = 0usize
    while i < n {
        out[i] = list[i]
        i += 1usize
    }
    put(&o, "ok", bv(!failed))
    put(&o, "v", json.Value{ Array: out[0usize..n] })
    if failed { put(&o, "error", sv(error_name)) }
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let op = text_of(c, "op")
    let want = ir.value_of(c, "e")
    var got: json.Value = .Null
    if str.eq(op, "frame") {
        got = parse_chain(a, unhex(a, text_of(c, "h")))
    } else if str.eq(op, "checksum") {
        got = nv(a, f64(packet.internet_checksum(unhex(a, text_of(c, "h")))))
    } else if str.eq(op, "pcap") {
        let r = pcap_result(a, unhex(a, text_of(c, "h")))
        // compare ok, error, records (and the link type is not reported here)
        var w = obj(a)
        let (wo, has_wo) = ir.get(want, "ok")
        put(&w, "ok", wo)
        put(&w, "v", ir.value_of(want, "v"))
        if !ir.truthy(wo) { put(&w, "error", ir.value_of(want, "error")) }
        got = r
        let (g, ge) = chain.canonical_json(a, got)
        let (x, we) = chain.canonical_json(a, ir.obj_value(&w))
        if ge != ok || we != ok { ret false }
        if !str.eq(g, x) {
            let shown = io.print(f.join(a, f.join(a, "\nGOT  ", g), f.join(a, "\nWANT ", x)))
            ret false
        }
        ret true
    } else if str.eq(op, "writePcap") {
        let recs = ir.value_of(c, "records")
        let (items, is_array) = ir.items_of(recs)
        let (buf, e) = mem.alloc[u8](a, 24usize + items.len * 256usize + 64usize)
        var at = pcap.write_header(buf, u32(number_of(c, "linktype")), u32(number_of(c, "snaplen")))
        var i = 0usize
        while i < items.len {
            let data = unhex(a, text_of(items[i], "h"))
            at += pcap.write_record(buf[at..], u32(number_of(items[i], "sec")), u32(number_of(items[i], "usec")), data, u32(number_of(items[i], "orig")))
            i += 1usize
        }
        got = sv(hex(a, buf[0usize..at]))
    } else if str.eq(op, "buildIpv4") {
        let (buf, e) = mem.alloc[u8](a, 64usize)
        let n = packet.build_ipv4(buf, u8(number_of(c, "tos")), u16(number_of(c, "id")), u8(number_of(c, "flags")), u16(number_of(c, "frag")), u8(number_of(c, "ttl")), u8(number_of(c, "proto")), arr4(unhex(a, text_of(c, "src"))), arr4(unhex(a, text_of(c, "dst"))), usize(number_of(c, "payload")))
        got = sv(hex(a, buf[0usize..n]))
    } else if str.eq(op, "buildUdp4") {
        let payload = unhex(a, text_of(c, "payload"))
        let (buf, e) = mem.alloc[u8](a, payload.len + 16usize)
        let n = packet.build_udp_v4(buf, u16(number_of(c, "sp")), u16(number_of(c, "dp")), payload, arr4(unhex(a, text_of(c, "src"))), arr4(unhex(a, text_of(c, "dst"))))
        got = sv(hex(a, buf[0usize..n]))
    } else if str.eq(op, "buildTcp4") {
        let payload = unhex(a, text_of(c, "payload"))
        let options = unhex(a, text_of(c, "options"))
        let (buf, e) = mem.alloc[u8](a, payload.len + options.len + 32usize)
        let n = packet.build_tcp_v4(buf, u16(number_of(c, "sp")), u16(number_of(c, "dp")), u32(number_of(c, "seq")), u32(number_of(c, "ack")), u16(number_of(c, "flags")), u16(number_of(c, "win")), u16(number_of(c, "urg")), options, payload, arr4(unhex(a, text_of(c, "src"))), arr4(unhex(a, text_of(c, "dst"))))
        got = sv(hex(a, buf[0usize..n]))
    } else if str.eq(op, "buildIcmp") {
        let payload = unhex(a, text_of(c, "payload"))
        let (buf, e) = mem.alloc[u8](a, payload.len + 16usize)
        let n = packet.build_icmp(buf, u8(number_of(c, "kind")), u8(number_of(c, "code")), u32(number_of(c, "rest")), payload)
        got = sv(hex(a, buf[0usize..n]))
    } else if str.eq(op, "buildIcmp6") {
        let payload = unhex(a, text_of(c, "payload"))
        let (buf, e) = mem.alloc[u8](a, payload.len + 16usize)
        let n = packet.build_icmp_v6(buf, u8(number_of(c, "kind")), u8(number_of(c, "code")), u32(number_of(c, "rest")), payload, arr16(unhex(a, text_of(c, "src"))), arr16(unhex(a, text_of(c, "dst"))))
        got = sv(hex(a, buf[0usize..n]))
    } else {
        // buildIpv6
        let (buf, e) = mem.alloc[u8](a, 64usize)
        let n = packet.build_ipv6(buf, u8(number_of(c, "tc")), u32(number_of(c, "flow")), u8(number_of(c, "nh")), u8(number_of(c, "hop")), arr16(unhex(a, text_of(c, "src"))), arr16(unhex(a, text_of(c, "dst"))), usize(number_of(c, "payload")))
        got = sv(hex(a, buf[0usize..n]))
    }
    let (g, ge) = chain.canonical_json(a, got)
    let (w, we) = chain.canonical_json(a, want)
    if ge != ok || we != ok { ret false }
    if !str.eq(g, w) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", g), f.join(a, "\nWANT ", w)))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(line)
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
    try io.print("net packet ok")
    ret ok
}
