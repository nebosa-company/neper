// `e.net.cookie` against an independent Python model of RFC 6265's storage and retrieval (scripts/gen_cookie_test.py):
// a scripted sequence of Set-Cookie responses and request headers. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.net.cookie as cookie

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [16]cookie.Cookie = zero
    var text: [1024]u8 = zero
    var jar = cookie.jar_new(storage[0..], text[0..])
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
    var small_storage: [4]cookie.Cookie = zero
    var small_text: [40]u8 = zero
    var small = cookie.jar_new(small_storage[0..], small_text[0..])
    let (cc0, ce0) = cookie.parse(a, "k=v00", "h.test", "/", false, 100i64)
    if ce0 != ok || cookie.store(&small, cc0, 100i64) != ok { os.exit(100) }
    let (cc1, ce1) = cookie.parse(a, "k=v01", "h.test", "/", false, 100i64)
    if ce1 != ok || cookie.store(&small, cc1, 100i64) != ok { os.exit(101) }
    let (cc2, ce2) = cookie.parse(a, "k=v02", "h.test", "/", false, 100i64)
    if ce2 != ok || cookie.store(&small, cc2, 100i64) != ok { os.exit(102) }
    let (cc3, ce3) = cookie.parse(a, "k=v03", "h.test", "/", false, 100i64)
    if ce3 != ok || cookie.store(&small, cc3, 100i64) != ok { os.exit(103) }
    let (cc4, ce4) = cookie.parse(a, "k=v04", "h.test", "/", false, 100i64)
    if ce4 != ok || cookie.store(&small, cc4, 100i64) != ok { os.exit(104) }
    let (cc5, ce5) = cookie.parse(a, "k=v05", "h.test", "/", false, 100i64)
    if ce5 != ok || cookie.store(&small, cc5, 100i64) != ok { os.exit(105) }
    let (cc6, ce6) = cookie.parse(a, "k=v06", "h.test", "/", false, 100i64)
    if ce6 != ok || cookie.store(&small, cc6, 100i64) != ok { os.exit(106) }
    let (cc7, ce7) = cookie.parse(a, "k=v07", "h.test", "/", false, 100i64)
    if ce7 != ok || cookie.store(&small, cc7, 100i64) != ok { os.exit(107) }
    let (cc8, ce8) = cookie.parse(a, "k=v08", "h.test", "/", false, 100i64)
    if ce8 != ok || cookie.store(&small, cc8, 100i64) != ok { os.exit(108) }
    let (cc9, ce9) = cookie.parse(a, "k=v09", "h.test", "/", false, 100i64)
    if ce9 != ok || cookie.store(&small, cc9, 100i64) != ok { os.exit(109) }
    let (cc10, ce10) = cookie.parse(a, "k=v10", "h.test", "/", false, 100i64)
    if ce10 != ok || cookie.store(&small, cc10, 100i64) != ok { os.exit(110) }
    let (cc11, ce11) = cookie.parse(a, "k=v11", "h.test", "/", false, 100i64)
    if ce11 != ok || cookie.store(&small, cc11, 100i64) != ok { os.exit(111) }
    let (cc12, ce12) = cookie.parse(a, "k=v12", "h.test", "/", false, 100i64)
    if ce12 != ok || cookie.store(&small, cc12, 100i64) != ok { os.exit(112) }
    let (cc13, ce13) = cookie.parse(a, "k=v13", "h.test", "/", false, 100i64)
    if ce13 != ok || cookie.store(&small, cc13, 100i64) != ok { os.exit(113) }
    let (cc14, ce14) = cookie.parse(a, "k=v14", "h.test", "/", false, 100i64)
    if ce14 != ok || cookie.store(&small, cc14, 100i64) != ok { os.exit(114) }
    let (cc15, ce15) = cookie.parse(a, "k=v15", "h.test", "/", false, 100i64)
    if ce15 != ok || cookie.store(&small, cc15, 100i64) != ok { os.exit(115) }
    let (cc16, ce16) = cookie.parse(a, "k=v16", "h.test", "/", false, 100i64)
    if ce16 != ok || cookie.store(&small, cc16, 100i64) != ok { os.exit(116) }
    let (cc17, ce17) = cookie.parse(a, "k=v17", "h.test", "/", false, 100i64)
    if ce17 != ok || cookie.store(&small, cc17, 100i64) != ok { os.exit(117) }
    let (cc18, ce18) = cookie.parse(a, "k=v18", "h.test", "/", false, 100i64)
    if ce18 != ok || cookie.store(&small, cc18, 100i64) != ok { os.exit(118) }
    let (cc19, ce19) = cookie.parse(a, "k=v19", "h.test", "/", false, 100i64)
    if ce19 != ok || cookie.store(&small, cc19, 100i64) != ok { os.exit(119) }
    let (cc20, ce20) = cookie.parse(a, "k=v20", "h.test", "/", false, 100i64)
    if ce20 != ok || cookie.store(&small, cc20, 100i64) != ok { os.exit(120) }
    let (cc21, ce21) = cookie.parse(a, "k=v21", "h.test", "/", false, 100i64)
    if ce21 != ok || cookie.store(&small, cc21, 100i64) != ok { os.exit(121) }
    let (cc22, ce22) = cookie.parse(a, "k=v22", "h.test", "/", false, 100i64)
    if ce22 != ok || cookie.store(&small, cc22, 100i64) != ok { os.exit(122) }
    let (cc23, ce23) = cookie.parse(a, "k=v23", "h.test", "/", false, 100i64)
    if ce23 != ok || cookie.store(&small, cc23, 100i64) != ok { os.exit(123) }
    let (cc24, ce24) = cookie.parse(a, "k=v24", "h.test", "/", false, 100i64)
    if ce24 != ok || cookie.store(&small, cc24, 100i64) != ok { os.exit(124) }
    let (cc25, ce25) = cookie.parse(a, "k=v25", "h.test", "/", false, 100i64)
    if ce25 != ok || cookie.store(&small, cc25, 100i64) != ok { os.exit(125) }
    let (cc26, ce26) = cookie.parse(a, "k=v26", "h.test", "/", false, 100i64)
    if ce26 != ok || cookie.store(&small, cc26, 100i64) != ok { os.exit(126) }
    let (cc27, ce27) = cookie.parse(a, "k=v27", "h.test", "/", false, 100i64)
    if ce27 != ok || cookie.store(&small, cc27, 100i64) != ok { os.exit(127) }
    let (cc28, ce28) = cookie.parse(a, "k=v28", "h.test", "/", false, 100i64)
    if ce28 != ok || cookie.store(&small, cc28, 100i64) != ok { os.exit(128) }
    let (cc29, ce29) = cookie.parse(a, "k=v29", "h.test", "/", false, 100i64)
    if ce29 != ok || cookie.store(&small, cc29, 100i64) != ok { os.exit(129) }
    let (sh, she) = cookie.header(a, &small, "h.test", "/", false, 100i64)
    if she != ok || !str.eq(sh, "k=v29") { os.exit(250) }
    // A failed store in a jar too large for compact's stack scratch must not charge
    // the partially copied name, value, and path against the next cookie.
    var leak_storage: [2]cookie.Cookie = zero
    var leak_text: [5000]u8 = zero
    var leak = cookie.jar_new(leak_storage[..], leak_text[..])
    var huge_value: [4994]u8 = zero
    var huge_at = 0usize
    while huge_at < huge_value.len {
        huge_value[huge_at] = 120u8
        huge_at += 1usize
    }
    var oversized: cookie.Cookie = zero
    oversized.name = "x"
    oversized.value = huge_value[..]
    oversized.domain = "h.test"
    oversized.host_only = true
    oversized.path = "/"
    if cookie.store(&leak, oversized, 100i64) != cookie.JarFull || leak.count != 0usize || leak.used != 0usize { os.exit(251) }
    var after_failure: cookie.Cookie = zero
    after_failure.name = "k"
    after_failure.value = "v"
    after_failure.domain = "h.test"
    after_failure.host_only = true
    after_failure.path = "/"
    if cookie.store(&leak, after_failure, 100i64) != ok || leak.count != 1usize || leak.used != 9usize { os.exit(252) }
    let (after_header, after_header_error) = cookie.header(a, &leak, "h.test", "/", false, 100i64)
    if after_header_error != ok || !str.eq(after_header, "k=v") { os.exit(253) }

    // Replacing a cookie must reuse its allocation, and a replacement that
    // really cannot fit must keep the old cookie live.
    var tight_storage: [1]cookie.Cookie = zero
    var tight_text: [14]u8 = zero
    var tight = cookie.jar_new(tight_storage[..], tight_text[..])
    let (tight_first, tight_first_error) = cookie.parse(a, "a=1; Path=/", "example.com", "/", false, 100i64)
    if tight_first_error != ok || cookie.store(&tight, tight_first, 100i64) != ok { os.exit(254) }
    let (tight_second, tight_second_error) = cookie.parse(a, "a=2; Path=/", "example.com", "/", false, 101i64)
    if tight_second_error != ok || cookie.store(&tight, tight_second, 101i64) != ok || tight.count != 1usize || tight.used != 14usize { os.exit(254) }
    let (tight_header, tight_header_error) = cookie.header(a, &tight, "example.com", "/", false, 101i64)
    if tight_header_error != ok || !str.eq(tight_header, "a=2") { os.exit(254) }
    let (too_wide, too_wide_error) = cookie.parse(a, "a=123; Path=/", "example.com", "/", false, 102i64)
    if too_wide_error != ok || cookie.store(&tight, too_wide, 102i64) != cookie.JarFull { os.exit(255) }
    let (preserved_header, preserved_header_error) = cookie.header(a, &tight, "example.com", "/", false, 102i64)
    if preserved_header_error != ok || !str.eq(preserved_header, "a=2") || tight.count != 1usize || tight.used != 14usize { os.exit(255) }
    ret ok
}
