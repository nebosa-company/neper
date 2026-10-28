// `e.fmt.url`: the WHATWG URL parser on a few of the Standard's own cases (the whole WPT corpus runs in
// tests/browser/url/run.sh): relative resolution, special schemes and default ports, IPv4 and IPv6 hosts, IDNA through
// the UTS #46 table, opaque paths, the origin and the setters.

use e.fmt.url as url
use e.mem
use e.os
use e.str

fn href_of(a: *mem.Arena, input: str, base: str) -> str {
    var b: url.Url = zero
    var has_base = false
    if base.len > 0usize {
        let (parsed, e) = url.parse(a, base, zero, false)
        if e != ok { ret "!base" }
        b = parsed
        has_base = true
    }
    let (u, ue) = url.parse(a, input, &b, has_base)
    if ue != ok { ret "!" }
    ret url.href(a, &u, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !str.eq(href_of(a, "http://Example.COM:80/a/./b/../c?q#f", ""), "http://example.com/a/c?q#f") { os.exit(1i32) }
    if !str.eq(href_of(a, "../x?y", "http://h/a/b/c"), "http://h/a/x?y") { os.exit(2i32) }
    if !str.eq(href_of(a, "//other/p", "https://h/a"), "https://other/p") { os.exit(3i32) }
    if !str.eq(href_of(a, "http://0x7f.1/", ""), "http://127.0.0.1/") { os.exit(4i32) }
    if !str.eq(href_of(a, "http://[2001:db8:0:0:0:0:0:1]:8080/", ""), "http://[2001:db8::1]:8080/") { os.exit(5i32) }
    if !str.eq(href_of(a, "http://ｅｘａｍｐｌｅ.com/", ""), "http://example.com/") { os.exit(6i32) }
    if !str.eq(href_of(a, "http://straße.de/", ""), "http://xn--strae-oqa.de/") { os.exit(7i32) }
    if !str.eq(href_of(a, "mailto:a@b.c?subject=x y", ""), "mailto:a@b.c?subject=x%20y") { os.exit(8i32) }
    if !str.eq(href_of(a, "file:///C|/x", ""), "file:///C:/x") { os.exit(9i32) }
    if !str.eq(href_of(a, "http://a b/", ""), "!") { os.exit(10i32) }
    if !str.eq(href_of(a, "http://h/a b?c d#e f", ""), "http://h/a%20b?c%20d#e%20f") { os.exit(11i32) }
    let (u, ue) = url.parse(a, "https://user:pw@sub.example.org:8443/p?x=1#top", zero, false)
    if ue != ok { os.exit(12i32) }
    if !str.eq(url.origin(a, &u), "https://sub.example.org:8443") { os.exit(13i32) }
    if !str.eq(url.host_port(a, &u), "sub.example.org:8443") || !str.eq(u.username, "user") || !str.eq(u.password, "pw") { os.exit(14i32) }
    let v = url.set_port(a, &u, "443")
    if !str.eq(url.href(a, &v, false), "https://user:pw@sub.example.org/p?x=1#top") { os.exit(15i32) }
    let w = url.set_pathname(a, &u, "/new path")
    if !str.eq(w.path, "/new%20path") { os.exit(16i32) }
    let h = url.set_hostname(a, &u, "other.test")
    if !str.eq(h.host, "other.test") || h.port != 8443i32 { os.exit(17i32) }

    // The final path copy used to turn exhaustion into a successful URL with an
    // empty path. Measure a successful parse, then leave exactly one byte short.
    var full_storage: [4096]u8 = zero
    var full_arena = mem.arena_from(full_storage[..])
    let (_, full_error) = url.parse(&full_arena, "https://example.test/kept", zero, false)
    if full_error != ok { os.exit(18i32) }
    let parse_used = mem.mark(&full_arena)
    if parse_used == 0usize || parse_used >= full_storage.len { os.exit(19i32) }
    var tight_storage: [4096]u8 = zero
    var tight_arena = mem.arena_from(tight_storage[0usize..parse_used - 1usize])
    let (_, tight_error) = url.parse(&tight_arena, "https://example.test/kept", zero, false)
    if tight_error != mem.Exhausted { os.exit(20i32) }

    // Setters cannot report an error, so they must keep the prior URL when their
    // parser or reconstructed path runs out of arena space.
    var setter_full_storage: [4096]u8 = zero
    var setter_full_arena = mem.arena_from(setter_full_storage[..])
    let changed = url.set_pathname(&setter_full_arena, &u, "/replacement")
    if !str.eq(changed.path, "/replacement") { os.exit(21i32) }
    let setter_used = mem.mark(&setter_full_arena)
    if setter_used == 0usize || setter_used >= setter_full_storage.len { os.exit(22i32) }
    var setter_tight_storage: [4096]u8 = zero
    var setter_tight_arena = mem.arena_from(setter_tight_storage[0usize..setter_used - 1usize])
    let retained = url.set_pathname(&setter_tight_arena, &u, "/replacement")
    if !str.eq(retained.path, u.path) { os.exit(23i32) }
    ret ok
}
