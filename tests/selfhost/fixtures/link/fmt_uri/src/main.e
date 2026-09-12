// `e.fmt.uri`: RFC 3986 parsing into borrowed parts, normalisation, the reference
// resolution examples of section 5.4, percent-encoding per component, decoding, and
// query lookup. Every check has its own exit code.
use e.os
use e.mem
use e.fmt.uri as uri

fn text_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (u, e1) = uri.parse("https://user:pw@Example.COM:8080/a/./b/../c%7edir/x?q=1&r=%20#frag")
    if e1 != ok { os.exit(1) }
    if !text_equal(u.scheme, "https") || !text_equal(u.userinfo, "user:pw") || !text_equal(u.host, "Example.COM") || !text_equal(u.port, "8080") { os.exit(2) }
    if !text_equal(u.path, "/a/./b/../c%7edir/x") || !text_equal(u.query, "q=1&r=%20") || !text_equal(u.fragment, "frag") { os.exit(3) }
    let (n, e2) = uri.normalize(a, u)
    if e2 != ok { os.exit(4) }
    if !text_equal(n.host, "example.com") || !text_equal(n.path, "/a/c~dir/x") || !text_equal(n.authority, "user:pw@example.com:8080") { os.exit(5) }
    let (f, e3) = uri.format(a, n)
    if e3 != ok || !text_equal(f, "https://user:pw@example.com:8080/a/c~dir/x?q=1&r=%20#frag") { os.exit(6) }
    // RFC 3986 5.4 examples against base http://a/b/c/d;p?q
    let (base, _) = uri.parse("http://a/b/c/d;p?q")
    let (r1, _) = uri.parse("g")
    let (t1, _) = uri.resolve(a, base, r1)
    let (s1, _) = uri.format(a, t1)
    if !text_equal(s1, "http://a/b/c/g") { os.exit(7) }
    let (r2, _) = uri.parse("../../g")
    let (t2, _) = uri.resolve(a, base, r2)
    let (s2, _) = uri.format(a, t2)
    if !text_equal(s2, "http://a/g") { os.exit(8) }
    let (r3, _) = uri.parse("?y")
    let (t3, _) = uri.resolve(a, base, r3)
    let (s3, _) = uri.format(a, t3)
    if !text_equal(s3, "http://a/b/c/d;p?y") { os.exit(9) }
    let (r4, _) = uri.parse("//g")
    let (t4, _) = uri.resolve(a, base, r4)
    let (s4, _) = uri.format(a, t4)
    if !text_equal(s4, "http://g") { os.exit(10) }
    let (r5, _) = uri.parse("#s")
    let (t5, _) = uri.resolve(a, base, r5)
    let (s5, _) = uri.format(a, t5)
    if !text_equal(s5, "http://a/b/c/d;p?q#s") { os.exit(11) }
    let (r6, _) = uri.parse("../../../g")
    let (t6, _) = uri.resolve(a, base, r6)
    let (s6, _) = uri.format(a, t6)
    if !text_equal(s6, "http://a/g") { os.exit(12) }
    let (r7, _) = uri.parse("g;x=1/../y")
    let (t7, _) = uri.resolve(a, base, r7)
    let (s7, _) = uri.format(a, t7)
    if !text_equal(s7, "http://a/b/c/y") { os.exit(13) }
    let raw: [7]u8 = [7]u8{ 97, 32, 47, 63, 38, 195, 169 }
    let (enc_query, e4) = uri.percent_encode(a, raw[0..], .QueryComponent)
    if e4 != ok || !text_equal(enc_query, "a%20/?%26%C3%A9") { os.exit(14) }
    let (enc_seg, e5) = uri.percent_encode(a, raw[0..], .PathSegment)
    if e5 != ok || !text_equal(enc_seg, "a%20%2F%3F&%C3%A9") { os.exit(15) }
    let (dec, e6) = uri.percent_decode(a, "a%20b+c%C3%A9")
    if e6 != ok || dec.len != 7usize || dec[1] != 32u8 || dec[3] != 43u8 || dec[5] != 195u8 { os.exit(16) }
    let (_, bad) = uri.percent_decode(a, "abc%2")
    let (_, bad_parse) = uri.parse("http://x/%zz")
    if bad != uri.Invalid || bad_parse != uri.Invalid { os.exit(17) }
    let (v1, has1, _) = uri.query_get("a=1&bb=two&c", "bb")
    let (v2, has2, _) = uri.query_get("a=1&bb=two&c", "c")
    let (_, has3, _) = uri.query_get("a=1&bb=two&c", "b")
    if !has1 || !text_equal(v1, "two") || !has2 || v2.len != 0usize || has3 { os.exit(18) }
    let (ip, e7) = uri.parse("http://[::1]:80/")
    if e7 != ok || !text_equal(ip.host, "[::1]") || !text_equal(ip.port, "80") { os.exit(19) }
    let (rel, e8) = uri.parse("a/b?c")
    if e8 != ok || rel.scheme.len != 0usize || !text_equal(rel.path, "a/b") || !text_equal(rel.query, "c") { os.exit(20) }
    os.exit(0)
    ret ok
}
