// `e.net.ssrf` against Appdor's own src/io/ssrf-guard.js: scripts/ssrf_vectors.mjs writes one JSON line per case
// (`{"op", ..., "e": answer}`) over URL spellings (integer, hex and octal IPv4, mapped IPv6), literal addresses and resolver
// answers; the fixture computes the same verdict and compares canonical JSON.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.net.ssrf as ssrf
use e.os
use e.str

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn flag_of(v: json.Value, key: str) -> bool {
    let x = ir.value_of(v, key)
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
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

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let (xs, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < xs.len {
        let (s, is_text) = ir.string_of(xs[i])
        out[i] = s
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn verdict_json(a: *mem.Arena, v: ssrf.Verdict) -> json.Value {
    var o = obj(a)
    put(&o, "ok", json.Value{ Bool: v.valid })
    if !v.valid {
        put(&o, "error", sv(v.message))
        ret ir.obj_value(&o)
    }
    var shown = v.host
    if str.contains(v.host, ":") { shown = f.join(a, f.join(a, "[", v.host), "]") }
    put(&o, "hostname", sv(shown))
    if v.resolved {
        let (out, e) = mem.alloc[json.Value](a, v.addresses.len + 1usize)
        if e != ok { os.exit(86i32) }
        var i = 0usize
        while i < v.addresses.len {
            out[i] = sv(v.addresses[i])
            i += 1usize
        }
        put(&o, "addresses", json.Value{ Array: out[0usize..v.addresses.len] })
    } else {
        put(&o, "addresses", .Null)
    }
    put(&o, "resolved", json.Value{ Bool: v.resolved })
    ret ir.obj_value(&o)
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "sync") { ret verdict_json(a, ssrf.check_url_sync(a, text_of(c, "url"))) }
    if str.eq(op, "full") {
        let lookup = ir.value_of(c, "lookup")
        ret verdict_json(a, ssrf.check_url(a, text_of(c, "url"), flag_of(lookup, "present"), flag_of(lookup, "failed"), strings_of(a, ir.value_of(lookup, "answers"))))
    }
    let ip = text_of(c, "ip")
    var o = obj(a)
    put(&o, "blocked", json.Value{ Bool: ssrf.is_blocked_address(a, ip) })
    put(&o, "reason", sv(ssrf.block_reason(a, ip)))
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let (got, ge) = chain.canonical_json(a, answer(a, c))
    let (want, we) = chain.canonical_json(a, ir.value_of(c, "e"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got, want) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", got), f.join(a, "\nWANT ", want)))
        ret false
    }
    ret true
}

fn vectors_0() -> str {
    ret "{\"op\":\"sync\",\"url\":\"http://127.0.0.1/\",\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://2130706433/\",\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://0x7f.1/\",\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://0177.0.0.1\",\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://[::1]:8080/\",\"e\":{\"ok\":false,\"error\":\"refused: ::1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://[::ffff:127.0.0.1]/\",\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://[::ffff:7f00:1]/\",\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://[fe80::1]\",\"e\":{\"ok\":false,\"error\":\"refused: fe80::1 is link-local — cloud metadata lives here\"}}\n{\"op\":\"sync\",\"url\":\"http://[fd00::1]/\",\"e\":{\"ok\":false,\"error\":\"refused: fd00::1 is a unique-local address\"}}\n{\"op\":\"sync\",\"url\":\"http://[2001:db8::1]/\",\"e\":{\"ok\":true,\"hostname\":\"[2001:db8::1]\",\"addresses\":[\"2001:db8::1\"],\"resolved\":true}}\n"
}

fn vectors_1() -> str {
    ret "{\"op\":\"sync\",\"url\":\"http://10.0.0.5\",\"e\":{\"ok\":false,\"error\":\"refused: 10.0.0.5 is private\"}}\n{\"op\":\"sync\",\"url\":\"http://100.64.0.1\",\"e\":{\"ok\":false,\"error\":\"refused: 100.64.0.1 is carrier-grade NAT\"}}\n{\"op\":\"sync\",\"url\":\"http://100.128.0.1\",\"e\":{\"ok\":true,\"hostname\":\"100.128.0.1\",\"addresses\":[\"100.128.0.1\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://172.15.0.1\",\"e\":{\"ok\":true,\"hostname\":\"172.15.0.1\",\"addresses\":[\"172.15.0.1\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://172.16.5.5\",\"e\":{\"ok\":false,\"error\":\"refused: 172.16.5.5 is private — the compose network\"}}\n{\"op\":\"sync\",\"url\":\"http://172.32.0.1\",\"e\":{\"ok\":true,\"hostname\":\"172.32.0.1\",\"addresses\":[\"172.32.0.1\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://192.0.0.9\",\"e\":{\"ok\":false,\"error\":\"refused: 192.0.0.9 is IETF protocol assignments\"}}\n{\"op\":\"sync\",\"url\":\"http://198.18.1.1\",\"e\":{\"ok\":false,\"error\":\"refused: 198.18.1.1 is benchmarking\"}}\n{\"op\":\"sync\",\"url\":\"http://198.19.255.255\",\"e\":{\"ok\":false,\"error\":\"refused: 198.19.255.255 is benchmarking\"}}\n{\"op\":\"sync\",\"url\":\"http://198.20.1.1\",\"e\":{\"ok\":true,\"hostname\":\"198.20.1.1\",\"addresses\":[\"198.20.1.1\"],\"resolved\":true}}\n"
}

fn vectors_2() -> str {
    ret "{\"op\":\"sync\",\"url\":\"http://224.0.0.1\",\"e\":{\"ok\":false,\"error\":\"refused: 224.0.0.1 is multicast\"}}\n{\"op\":\"sync\",\"url\":\"http://240.0.0.1\",\"e\":{\"ok\":false,\"error\":\"refused: 240.0.0.1 is reserved\"}}\n{\"op\":\"sync\",\"url\":\"http://8.8.8.8\",\"e\":{\"ok\":true,\"hostname\":\"8.8.8.8\",\"addresses\":[\"8.8.8.8\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"https://example.com\",\"e\":{\"ok\":true,\"hostname\":\"example.com\",\"addresses\":null,\"resolved\":false}}\n{\"op\":\"sync\",\"url\":\"http://meta:8080/query\",\"e\":{\"ok\":false,\"error\":\"refused: \\\"meta\\\" is an internal hostname\"}}\n{\"op\":\"sync\",\"url\":\"http://db\",\"e\":{\"ok\":false,\"error\":\"refused: \\\"db\\\" is an internal hostname\"}}\n{\"op\":\"sync\",\"url\":\"http://metadata.google.internal/\",\"e\":{\"ok\":false,\"error\":\"refused: metadata.google.internal is the cloud metadata endpoint\"}}\n{\"op\":\"sync\",\"url\":\"http://a.metadata.google.internal\",\"e\":{\"ok\":false,\"error\":\"refused: a.metadata.google.internal is the cloud metadata endpoint\"}}\n{\"op\":\"sync\",\"url\":\"http://localhost\",\"e\":{\"ok\":false,\"error\":\"refused: \\\"localhost\\\" is an internal hostname\"}}\n{\"op\":\"sync\",\"url\":\"http://x.localhost\",\"e\":{\"ok\":false,\"error\":\"refused: x.localhost is loopback\"}}\n"
}

fn vectors_3() -> str {
    ret "{\"op\":\"sync\",\"url\":\"http://LOCALHOST:80\",\"e\":{\"ok\":false,\"error\":\"refused: \\\"localhost\\\" is an internal hostname\"}}\n{\"op\":\"sync\",\"url\":\"ftp://example.com\",\"e\":{\"ok\":false,\"error\":\"refused: ftp: is not http or https\"}}\n{\"op\":\"sync\",\"url\":\"file:///etc/passwd\",\"e\":{\"ok\":false,\"error\":\"refused: file: is not http or https\"}}\n{\"op\":\"sync\",\"url\":\"javascript:alert(1)\",\"e\":{\"ok\":false,\"error\":\"refused: javascript: is not http or https\"}}\n{\"op\":\"sync\",\"url\":\"not a url\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://user:pw@example.com:8080/p\",\"e\":{\"ok\":true,\"hostname\":\"example.com\",\"addresses\":null,\"resolved\":false}}\n{\"op\":\"sync\",\"url\":\"http://example.com:99999\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://exa mple.com\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n"
}

fn vectors_4() -> str {
    ret "{\"op\":\"sync\",\"url\":\"HTTP://EXAMPLE.COM\",\"e\":{\"ok\":true,\"hostname\":\"example.com\",\"addresses\":null,\"resolved\":false}}\n{\"op\":\"sync\",\"url\":\"http://1.2.3\",\"e\":{\"ok\":true,\"hostname\":\"1.2.0.3\",\"addresses\":[\"1.2.0.3\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://1.2.3.4.5\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://999.1.1.1\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://[::]\",\"e\":{\"ok\":false,\"error\":\"refused: :: is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://0.0.0.0\",\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.0 is this network\"}}\n{\"op\":\"sync\",\"url\":\"http://[0:0:0:0:0:ffff:7f00:1]\",\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://example.com./\",\"e\":{\"ok\":true,\"hostname\":\"example.com.\",\"addresses\":null,\"resolved\":false}}\n{\"op\":\"sync\",\"url\":\"http://1.2.3.4.\",\"e\":{\"ok\":true,\"hostname\":\"1.2.3.4\",\"addresses\":[\"1.2.3.4\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://0x10\",\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.16 is this network\"}}\n"
}

fn vectors_5() -> str {
    ret "{\"op\":\"sync\",\"url\":\"http://%31%32%37.0.0.1\",\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"sync\",\"url\":\"http://[2001:0db8:0000:0000:0000:0000:0000:0001]\",\"e\":{\"ok\":true,\"hostname\":\"[2001:db8::1]\",\"addresses\":[\"2001:db8::1\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://[1:0:0:2:0:0:0:3]\",\"e\":{\"ok\":true,\"hostname\":\"[1:0:0:2::3]\",\"addresses\":[\"1:0:0:2::3\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://[::ffff:10.1.2.3]\",\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:a01:203 is private\"}}\n{\"op\":\"sync\",\"url\":\"http://[::ffff:8.8.8.8]\",\"e\":{\"ok\":true,\"hostname\":\"[::ffff:808:808]\",\"addresses\":[\"::ffff:808:808\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://[fe80::1%25eth0]\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://169.254.169.254/latest/meta-data\",\"e\":{\"ok\":false,\"error\":\"refused: 169.254.169.254 is link-local — cloud metadata lives here\"}}\n{\"op\":\"sync\",\"url\":\"http://[fec0::1]\",\"e\":{\"ok\":true,\"hostname\":\"[fec0::1]\",\"addresses\":[\"fec0::1\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"https://api.example.org/v1?x=1#f\",\"e\":{\"ok\":true,\"hostname\":\"api.example.org\",\"addresses\":null,\"resolved\":false}}\n{\"op\":\"sync\",\"url\":\"http://0\",\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.0 is this network\"}}\n"
}

fn vectors_6() -> str {
    ret "{\"op\":\"sync\",\"url\":\"http://4294967295\",\"e\":{\"ok\":false,\"error\":\"refused: 255.255.255.255 is reserved\"}}\n{\"op\":\"sync\",\"url\":\"http://4294967296\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://1.1.1.256\",\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"sync\",\"url\":\"http://[::ffff:1:2]\",\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:1:2 is this network\"}}\n{\"op\":\"sync\",\"url\":\"http://[1::]\",\"e\":{\"ok\":true,\"hostname\":\"[1::]\",\"addresses\":[\"1::\"],\"resolved\":true}}\n{\"op\":\"sync\",\"url\":\"http://[::1.2.3.4]\",\"e\":{\"ok\":true,\"hostname\":\"[::102:304]\",\"addresses\":[\"::102:304\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://127.0.0.1/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://127.0.0.1/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://2130706433/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://2130706433/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n"
}

fn vectors_7() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://0x7f.1/\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://0x7f.1/\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://0177.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://0177.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::1]:8080/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::1]:8080/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:127.0.0.1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:127.0.0.1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:7f00:1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:7f00:1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n"
}

fn vectors_8() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://[fe80::1]\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: fe80::1 is link-local — cloud metadata lives here\"}}\n{\"op\":\"full\",\"url\":\"http://[fe80::1]\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: fe80::1 is link-local — cloud metadata lives here\"}}\n{\"op\":\"full\",\"url\":\"http://[fd00::1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: fd00::1 is a unique-local address\"}}\n{\"op\":\"full\",\"url\":\"http://[fd00::1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: fd00::1 is a unique-local address\"}}\n{\"op\":\"full\",\"url\":\"http://[2001:db8::1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"[2001:db8::1]\",\"addresses\":[\"2001:db8::1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[2001:db8::1]/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"[2001:db8::1]\",\"addresses\":[\"2001:db8::1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://10.0.0.5\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 10.0.0.5 is private\"}}\n{\"op\":\"full\",\"url\":\"http://10.0.0.5\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 10.0.0.5 is private\"}}\n{\"op\":\"full\",\"url\":\"http://100.64.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 100.64.0.1 is carrier-grade NAT\"}}\n{\"op\":\"full\",\"url\":\"http://100.64.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 100.64.0.1 is carrier-grade NAT\"}}\n"
}

fn vectors_9() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://100.128.0.1\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"100.128.0.1\",\"addresses\":[\"100.128.0.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://100.128.0.1\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"100.128.0.1\",\"addresses\":[\"100.128.0.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://172.15.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":true,\"hostname\":\"172.15.0.1\",\"addresses\":[\"172.15.0.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://172.15.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":true,\"hostname\":\"172.15.0.1\",\"addresses\":[\"172.15.0.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://172.16.5.5\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 172.16.5.5 is private — the compose network\"}}\n{\"op\":\"full\",\"url\":\"http://172.16.5.5\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 172.16.5.5 is private — the compose network\"}}\n{\"op\":\"full\",\"url\":\"http://172.32.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"172.32.0.1\",\"addresses\":[\"172.32.0.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://172.32.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"172.32.0.1\",\"addresses\":[\"172.32.0.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://192.0.0.9\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 192.0.0.9 is IETF protocol assignments\"}}\n{\"op\":\"full\",\"url\":\"http://192.0.0.9\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 192.0.0.9 is IETF protocol assignments\"}}\n"
}

fn vectors_10() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://198.18.1.1\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: 198.18.1.1 is benchmarking\"}}\n{\"op\":\"full\",\"url\":\"http://198.18.1.1\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: 198.18.1.1 is benchmarking\"}}\n{\"op\":\"full\",\"url\":\"http://198.19.255.255\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: 198.19.255.255 is benchmarking\"}}\n{\"op\":\"full\",\"url\":\"http://198.19.255.255\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: 198.19.255.255 is benchmarking\"}}\n{\"op\":\"full\",\"url\":\"http://198.20.1.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"198.20.1.1\",\"addresses\":[\"198.20.1.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://198.20.1.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"198.20.1.1\",\"addresses\":[\"198.20.1.1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://224.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 224.0.0.1 is multicast\"}}\n{\"op\":\"full\",\"url\":\"http://224.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 224.0.0.1 is multicast\"}}\n{\"op\":\"full\",\"url\":\"http://240.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 240.0.0.1 is reserved\"}}\n{\"op\":\"full\",\"url\":\"http://240.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 240.0.0.1 is reserved\"}}\n"
}

fn vectors_11() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://8.8.8.8\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"8.8.8.8\",\"addresses\":[\"8.8.8.8\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://8.8.8.8\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"8.8.8.8\",\"addresses\":[\"8.8.8.8\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"https://example.com\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: example.com did not resolve\"}}\n{\"op\":\"full\",\"url\":\"https://example.com\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: example.com did not resolve\"}}\n{\"op\":\"full\",\"url\":\"http://meta:8080/query\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"meta\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://meta:8080/query\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"meta\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://db\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"db\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://db\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"db\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://metadata.google.internal/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: metadata.google.internal is the cloud metadata endpoint\"}}\n{\"op\":\"full\",\"url\":\"http://metadata.google.internal/\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: metadata.google.internal is the cloud metadata endpoint\"}}\n"
}

fn vectors_12() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://a.metadata.google.internal\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: a.metadata.google.internal is the cloud metadata endpoint\"}}\n{\"op\":\"full\",\"url\":\"http://a.metadata.google.internal\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: a.metadata.google.internal is the cloud metadata endpoint\"}}\n{\"op\":\"full\",\"url\":\"http://localhost\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"localhost\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://localhost\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"localhost\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://x.localhost\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: x.localhost is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://x.localhost\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: x.localhost is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://LOCALHOST:80\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"localhost\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"http://LOCALHOST:80\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: \\\"localhost\\\" is an internal hostname\"}}\n{\"op\":\"full\",\"url\":\"ftp://example.com\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ftp: is not http or https\"}}\n{\"op\":\"full\",\"url\":\"ftp://example.com\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ftp: is not http or https\"}}\n"
}

fn vectors_13() -> str {
    ret "{\"op\":\"full\",\"url\":\"file:///etc/passwd\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: file: is not http or https\"}}\n{\"op\":\"full\",\"url\":\"file:///etc/passwd\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: file: is not http or https\"}}\n{\"op\":\"full\",\"url\":\"javascript:alert(1)\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: javascript: is not http or https\"}}\n{\"op\":\"full\",\"url\":\"javascript:alert(1)\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: javascript: is not http or https\"}}\n{\"op\":\"full\",\"url\":\"not a url\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"not a url\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n"
}

fn vectors_14() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://user:pw@example.com:8080/p\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: cannot resolve host to check it\"}}\n{\"op\":\"full\",\"url\":\"http://user:pw@example.com:8080/p\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: cannot resolve host to check it\"}}\n{\"op\":\"full\",\"url\":\"http://example.com:99999\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://example.com:99999\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://exa mple.com\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://exa mple.com\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"HTTP://EXAMPLE.COM\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: example.com resolves to 10.0.0.1, which is private\"}}\n{\"op\":\"full\",\"url\":\"HTTP://EXAMPLE.COM\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: example.com resolves to 10.0.0.1, which is private\"}}\n{\"op\":\"full\",\"url\":\"http://1.2.3\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"1.2.0.3\",\"addresses\":[\"1.2.0.3\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://1.2.3\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"1.2.0.3\",\"addresses\":[\"1.2.0.3\"],\"resolved\":true}}\n"
}

fn vectors_15() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://1.2.3.4.5\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://1.2.3.4.5\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://999.1.1.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://999.1.1.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://[::]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: :: is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[::]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: :: is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://0.0.0.0\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.0 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://0.0.0.0\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.0 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://[0:0:0:0:0:ffff:7f00:1]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[0:0:0:0:0:ffff:7f00:1]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:7f00:1 is loopback\"}}\n"
}

fn vectors_16() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://example.com./\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: cannot resolve host to check it\"}}\n{\"op\":\"full\",\"url\":\"http://example.com./\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"refused: cannot resolve host to check it\"}}\n{\"op\":\"full\",\"url\":\"http://1.2.3.4.\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":true,\"hostname\":\"1.2.3.4\",\"addresses\":[\"1.2.3.4\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://1.2.3.4.\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":true,\"hostname\":\"1.2.3.4\",\"addresses\":[\"1.2.3.4\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://0x10\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.16 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://0x10\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.16 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://%31%32%37.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://%31%32%37.0.0.1\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 127.0.0.1 is loopback\"}}\n{\"op\":\"full\",\"url\":\"http://[2001:0db8:0000:0000:0000:0000:0000:0001]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"[2001:db8::1]\",\"addresses\":[\"2001:db8::1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[2001:0db8:0000:0000:0000:0000:0000:0001]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"[2001:db8::1]\",\"addresses\":[\"2001:db8::1\"],\"resolved\":true}}\n"
}

fn vectors_17() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://[1:0:0:2:0:0:0:3]\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"[1:0:0:2::3]\",\"addresses\":[\"1:0:0:2::3\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[1:0:0:2:0:0:0:3]\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"[1:0:0:2::3]\",\"addresses\":[\"1:0:0:2::3\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:10.1.2.3]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:a01:203 is private\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:10.1.2.3]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:a01:203 is private\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:8.8.8.8]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"[::ffff:808:808]\",\"addresses\":[\"::ffff:808:808\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:8.8.8.8]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"[::ffff:808:808]\",\"addresses\":[\"::ffff:808:808\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[fe80::1%25eth0]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://[fe80::1%25eth0]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://169.254.169.254/latest/meta-data\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 169.254.169.254 is link-local — cloud metadata lives here\"}}\n{\"op\":\"full\",\"url\":\"http://169.254.169.254/latest/meta-data\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 169.254.169.254 is link-local — cloud metadata lives here\"}}\n"
}

fn vectors_18() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://[fec0::1]\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"[fec0::1]\",\"addresses\":[\"fec0::1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[fec0::1]\",\"lookup\":{\"present\":false},\"e\":{\"ok\":true,\"hostname\":\"[fec0::1]\",\"addresses\":[\"fec0::1\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"https://api.example.org/v1?x=1#f\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: api.example.org did not resolve\"}}\n{\"op\":\"full\",\"url\":\"https://api.example.org/v1?x=1#f\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: api.example.org did not resolve\"}}\n{\"op\":\"full\",\"url\":\"http://0\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.0 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://0\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 0.0.0.0 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://4294967295\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 255.255.255.255 is reserved\"}}\n{\"op\":\"full\",\"url\":\"http://4294967295\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"refused: 255.255.255.255 is reserved\"}}\n{\"op\":\"full\",\"url\":\"http://4294967296\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://4294967296\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"::ffff:10.0.0.1\"]},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n"
}

fn vectors_19() -> str {
    ret "{\"op\":\"full\",\"url\":\"http://1.1.1.256\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://1.1.1.256\",\"lookup\":{\"present\":false},\"e\":{\"ok\":false,\"error\":\"not a valid URL\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:1:2]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:1:2 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://[::ffff:1:2]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[]},\"e\":{\"ok\":false,\"error\":\"refused: ::ffff:1:2 is this network\"}}\n{\"op\":\"full\",\"url\":\"http://[1::]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"[1::]\",\"addresses\":[\"1::\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[1::]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"fe80::1\"]},\"e\":{\"ok\":true,\"hostname\":\"[1::]\",\"addresses\":[\"1::\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[::1.2.3.4]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"[::102:304]\",\"addresses\":[\"::102:304\"],\"resolved\":true}}\n{\"op\":\"full\",\"url\":\"http://[::1.2.3.4]\",\"lookup\":{\"present\":true,\"failed\":false,\"answers\":[\"10.0.0.1\"]},\"e\":{\"ok\":true,\"hostname\":\"[::102:304]\",\"addresses\":[\"::102:304\"],\"resolved\":true}}\n{\"op\":\"addr\",\"ip\":\"127.0.0.1\",\"e\":{\"blocked\":true,\"reason\":\"loopback\"}}\n{\"op\":\"addr\",\"ip\":\"10.1.2.3\",\"e\":{\"blocked\":true,\"reason\":\"private\"}}\n"
}

fn vectors_20() -> str {
    ret "{\"op\":\"addr\",\"ip\":\"8.8.8.8\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"1.1.1.1\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"::1\",\"e\":{\"blocked\":true,\"reason\":\"loopback\"}}\n{\"op\":\"addr\",\"ip\":\"::\",\"e\":{\"blocked\":true,\"reason\":\"loopback\"}}\n{\"op\":\"addr\",\"ip\":\"fe80::1\",\"e\":{\"blocked\":true,\"reason\":\"link-local — cloud metadata lives here\"}}\n{\"op\":\"addr\",\"ip\":\"FD00::1\",\"e\":{\"blocked\":true,\"reason\":\"a unique-local address\"}}\n{\"op\":\"addr\",\"ip\":\"[::1]\",\"e\":{\"blocked\":true,\"reason\":\"loopback\"}}\n{\"op\":\"addr\",\"ip\":\" 8.8.8.8 \",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"::ffff:127.0.0.1\",\"e\":{\"blocked\":true,\"reason\":\"loopback\"}}\n{\"op\":\"addr\",\"ip\":\"::ffff:7f00:1\",\"e\":{\"blocked\":true,\"reason\":\"loopback\"}}\n"
}

fn vectors_21() -> str {
    ret "{\"op\":\"addr\",\"ip\":\"::ffff:808:808\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"2001:db8::1\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"\",\"e\":{\"blocked\":true,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"1.2.3\",\"e\":{\"blocked\":true,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"abc\",\"e\":{\"blocked\":true,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"256.1.1.1\",\"e\":{\"blocked\":true,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"100.100.100.100\",\"e\":{\"blocked\":true,\"reason\":\"carrier-grade NAT\"}}\n{\"op\":\"addr\",\"ip\":\"198.51.100.7\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"203.0.113.9\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"239.255.255.255\",\"e\":{\"blocked\":true,\"reason\":\"multicast\"}}\n"
}

fn vectors_22() -> str {
    ret "{\"op\":\"addr\",\"ip\":\"255.255.255.255\",\"e\":{\"blocked\":true,\"reason\":\"reserved\"}}\n{\"op\":\"addr\",\"ip\":\"fc00::\",\"e\":{\"blocked\":true,\"reason\":\"a unique-local address\"}}\n{\"op\":\"addr\",\"ip\":\"fe00::1\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"febf::1\",\"e\":{\"blocked\":true,\"reason\":\"link-local — cloud metadata lives here\"}}\n{\"op\":\"addr\",\"ip\":\"fec0::1\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n{\"op\":\"addr\",\"ip\":\"::ffff:1:2:3\",\"e\":{\"blocked\":false,\"reason\":\"not a public address\"}}\n"
}

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
    if run_chunk(a, vectors_0()) != 0u8 { os.exit(1i32) }
    if run_chunk(a, vectors_1()) != 0u8 { os.exit(2i32) }
    if run_chunk(a, vectors_2()) != 0u8 { os.exit(3i32) }
    if run_chunk(a, vectors_3()) != 0u8 { os.exit(4i32) }
    if run_chunk(a, vectors_4()) != 0u8 { os.exit(5i32) }
    if run_chunk(a, vectors_5()) != 0u8 { os.exit(6i32) }
    if run_chunk(a, vectors_6()) != 0u8 { os.exit(7i32) }
    if run_chunk(a, vectors_7()) != 0u8 { os.exit(8i32) }
    if run_chunk(a, vectors_8()) != 0u8 { os.exit(9i32) }
    if run_chunk(a, vectors_9()) != 0u8 { os.exit(10i32) }
    if run_chunk(a, vectors_10()) != 0u8 { os.exit(11i32) }
    if run_chunk(a, vectors_11()) != 0u8 { os.exit(12i32) }
    if run_chunk(a, vectors_12()) != 0u8 { os.exit(13i32) }
    if run_chunk(a, vectors_13()) != 0u8 { os.exit(14i32) }
    if run_chunk(a, vectors_14()) != 0u8 { os.exit(15i32) }
    if run_chunk(a, vectors_15()) != 0u8 { os.exit(16i32) }
    if run_chunk(a, vectors_16()) != 0u8 { os.exit(17i32) }
    if run_chunk(a, vectors_17()) != 0u8 { os.exit(18i32) }
    if run_chunk(a, vectors_18()) != 0u8 { os.exit(19i32) }
    if run_chunk(a, vectors_19()) != 0u8 { os.exit(20i32) }
    if run_chunk(a, vectors_20()) != 0u8 { os.exit(21i32) }
    if run_chunk(a, vectors_21()) != 0u8 { os.exit(22i32) }
    if run_chunk(a, vectors_22()) != 0u8 { os.exit(23i32) }
    try io.print("net ssrf ok")
    ret ok
}
