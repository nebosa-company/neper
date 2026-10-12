// `e.net.cookie` against an independent Python model of RFC 6265's storage and retrieval (scripts/gen_cookie_test.py):
// a scripted sequence of Set-Cookie responses and request headers. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.net.cookie as cookie

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [16]cookie.Cookie = zero
    var jar = cookie.jar_new(storage[0..])
    let (c1, e1) = cookie.parse(a, "sid=1; Path=/; Secure; HttpOnly", "example.com", "/a/b/page", true, 1790000000i64)
    if e1 == ok {
        let stored1 = cookie.store(&jar, c1, 1790000000i64)
        if stored1 != ok { os.exit(201) }
    }
    let (c2, e2) = cookie.parse(a, "theme=dark; Domain=.example.com; Max-Age=3600", "example.com", "/a/b/page", true, 1790000001i64)
    if e2 == ok {
        let stored2 = cookie.store(&jar, c2, 1790000001i64)
        if stored2 != ok { os.exit(202) }
    }
    let (c3, e3) = cookie.parse(a, "pref=x", "example.com", "/a/b/page", true, 1790000002i64)
    if e3 == ok {
        let stored3 = cookie.store(&jar, c3, 1790000002i64)
        if stored3 != ok { os.exit(203) }
    }
    let (h4, he4) = cookie.header(a, &jar, "example.com", "/a/b/other", true, 1790000003i64)
    if he4 != ok || !str.eq(h4, "theme=dark; pref=x; sid=1") { os.exit(4) }
    let (h5, he5) = cookie.header(a, &jar, "www.example.com", "/", true, 1790000003i64)
    if he5 != ok || !str.eq(h5, "") { os.exit(5) }
    let (h6, he6) = cookie.header(a, &jar, "example.com", "/a/b/other", false, 1790000003i64)
    if he6 != ok || !str.eq(h6, "theme=dark; pref=x") { os.exit(6) }
    let (h7, he7) = cookie.header(a, &jar, "example.com", "/a/c", true, 1790000003i64)
    if he7 != ok || !str.eq(h7, "sid=1") { os.exit(7) }
    let (c8, e8) = cookie.parse(a, "theme=light; Domain=example.com; Max-Age=3600", "example.com", "/a/b/page", true, 1790000004i64)
    if e8 == ok {
        let stored8 = cookie.store(&jar, c8, 1790000004i64)
        if stored8 != ok { os.exit(208) }
    }
    let (h9, he9) = cookie.header(a, &jar, "sub.example.com", "/x", true, 1790000005i64)
    if he9 != ok || !str.eq(h9, "") { os.exit(9) }
    let (c10, e10) = cookie.parse(a, "theme=gone; Domain=example.com; Max-Age=0", "example.com", "/", true, 1790000006i64)
    if e10 == ok {
        let stored10 = cookie.store(&jar, c10, 1790000006i64)
        if stored10 != ok { os.exit(210) }
    }
    let (h11, he11) = cookie.header(a, &jar, "sub.example.com", "/x", true, 1790000007i64)
    if he11 != ok || !str.eq(h11, "") { os.exit(11) }
    let (c12, e12) = cookie.parse(a, "sid=2; Path=/; Secure", "example.com", "/", true, 1790000008i64)
    if e12 == ok {
        let stored12 = cookie.store(&jar, c12, 1790000008i64)
        if stored12 != ok { os.exit(212) }
    }
    let (h13, he13) = cookie.header(a, &jar, "example.com", "/", true, 1790000009i64)
    if he13 != ok || !str.eq(h13, "sid=2") { os.exit(13) }
    let (c14, e14) = cookie.parse(a, "x=1; Domain=example.com", "evil.com", "/", true, 1790000010i64)
    if e14 == ok {
        let stored14 = cookie.store(&jar, c14, 1790000010i64)
        if stored14 != ok { os.exit(214) }
    }
    let (h15, he15) = cookie.header(a, &jar, "example.com", "/", true, 1790000011i64)
    if he15 != ok || !str.eq(h15, "sid=2") { os.exit(15) }
    let (c16, e16) = cookie.parse(a, "__Host-s=1; Secure; Path=/", "example.com", "/login/form", true, 1790000012i64)
    if e16 == ok {
        let stored16 = cookie.store(&jar, c16, 1790000012i64)
        if stored16 != ok { os.exit(216) }
    }
    let (c17, e17) = cookie.parse(a, "__Host-t=1; Secure; Path=/; Domain=example.com", "example.com", "/", true, 1790000013i64)
    if e17 == ok {
        let stored17 = cookie.store(&jar, c17, 1790000013i64)
        if stored17 != ok { os.exit(217) }
    }
    let (c18, e18) = cookie.parse(a, "__Secure-u=1", "example.com", "/", false, 1790000014i64)
    if e18 == ok {
        let stored18 = cookie.store(&jar, c18, 1790000014i64)
        if stored18 != ok { os.exit(218) }
    }
    let (h19, he19) = cookie.header(a, &jar, "example.com", "/anything", true, 1790000015i64)
    if he19 != ok || !str.eq(h19, "sid=2; __Host-s=1") { os.exit(19) }
    let (c20, e20) = cookie.parse(a, "short=1; Max-Age=5", "example.com", "/", true, 1790000016i64)
    if e20 == ok {
        let stored20 = cookie.store(&jar, c20, 1790000016i64)
        if stored20 != ok { os.exit(220) }
    }
    let (h21, he21) = cookie.header(a, &jar, "example.com", "/", true, 1790000017i64)
    if he21 != ok || !str.eq(h21, "sid=2; __Host-s=1; short=1") { os.exit(21) }
    let (h22, he22) = cookie.header(a, &jar, "example.com", "/", true, 1790000030i64)
    if he22 != ok || !str.eq(h22, "sid=2; __Host-s=1") { os.exit(22) }
    let (c23, e23) = cookie.parse(a, "ip=1; Domain=0.1", "192.168.0.1", "/", false, 1790000040i64)
    if e23 == ok {
        let stored23 = cookie.store(&jar, c23, 1790000040i64)
        if stored23 != ok { os.exit(223) }
    }
    let (h24, he24) = cookie.header(a, &jar, "192.168.0.1", "/", false, 1790000041i64)
    if he24 != ok || !str.eq(h24, "") { os.exit(24) }
    let (c25, e25) = cookie.parse(a, "dflt=1", "example.com", "/dir/file", false, 1790000050i64)
    if e25 == ok {
        let stored25 = cookie.store(&jar, c25, 1790000050i64)
        if stored25 != ok { os.exit(225) }
    }
    let (h26, he26) = cookie.header(a, &jar, "example.com", "/dir/other", false, 1790000051i64)
    if he26 != ok || !str.eq(h26, "dflt=1") { os.exit(26) }
    let (h27, he27) = cookie.header(a, &jar, "example.com", "/dirx/other", false, 1790000051i64)
    if he27 != ok || !str.eq(h27, "") { os.exit(27) }
    let (h28, he28) = cookie.header(a, &jar, "example.com", "/dir", false, 1790000051i64)
    if he28 != ok || !str.eq(h28, "dflt=1") { os.exit(28) }
    ret ok
}
