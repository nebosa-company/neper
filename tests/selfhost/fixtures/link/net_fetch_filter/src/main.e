// `e.net.fetch` with a filter list: a subresource (one with a referrer) to a listed host or any of its subdomains fails as
// blocked before a connection is made and is counted; an unlisted host and the document itself are not filtered.
use e.mem
use e.net.fetch as fetch
use e.net.http as http
use e.net.policy as policy
use e.os
use e.str

fn request(u: str, referrer: str) -> fetch.Request { ret request_as(u, referrer, "") }

fn request_as(u: str, referrer: str, dest: str) -> fetch.Request {
    ret fetch.Request { url: u, method: http.Method.Get, headers: zero, body: zero, redirect: fetch.Redirect.Follow, credentials: fetch.Credentials.Omit, referrer: referrer, dest: dest }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var cfg = fetch.default_config(zero)
    let rules = policy.parse_filter_list(a, "! list\n||tracker.test^\n||127.0.0.1^\n@@||good.tracker.test^\n")
    cfg.block_hosts = rules.domains
    cfg.allow_hosts = rules.allow
    let (c0, ce) = fetch.client(a, cfg, 8usize)
    if ce != ok { os.exit(1i32) }
    var c = c0
    let (r1, e1) = fetch.fetch(&c, request("http://tracker.test/a.js", "http://site.test/"))
    if e1 != fetch.BlockedByFilter || c.blocked != 1usize { os.exit(2i32) }
    let (r2, e2) = fetch.fetch(&c, request("http://cdn.tracker.test/a.js", "http://site.test/"))
    if e2 != fetch.BlockedByFilter || c.blocked != 2usize { os.exit(3i32) }
    let (r3, e3) = fetch.fetch(&c, request("http://nottracker.test/a.js", "http://site.test/"))
    if e3 == fetch.BlockedByFilter || c.blocked != 2usize { os.exit(4i32) }
    let (r4, e4) = fetch.fetch(&c, request("http://127.0.0.1:65000/", ""))
    if e4 == fetch.BlockedByFilter || c.blocked != 2usize { os.exit(5i32) }
    let (r5, e5) = fetch.fetch(&c, request("http://127.0.0.1:65000/", "http://site.test/"))
    if e5 != fetch.BlockedByFilter || c.blocked != 3usize { os.exit(6i32) }
    // An exception rule lets its host through while the rest of the domain stays blocked.
    let (r6, e6) = fetch.fetch(&c, request("http://good.tracker.test/a.js", "http://site.test/"))
    if e6 == fetch.BlockedByFilter || c.blocked != 3usize { os.exit(7i32) }
    let (r7, e7) = fetch.fetch(&c, request("http://other.tracker.test/a.js", "http://site.test/"))
    if e7 != fetch.BlockedByFilter || c.blocked != 4usize { os.exit(8i32) }
    // A `$third-party` rule blocks only requests from another site.
    var cfg3 = fetch.default_config(zero)
    let rules3 = policy.parse_filter_list(a, "||thirdp.test^$third-party\n")
    cfg3.block_hosts = rules3.domains
    cfg3.third_hosts = rules3.third
    if rules3.domains.len != 1usize || rules3.third.len != 1usize { os.exit(11i32) }
    let (c3, ce3) = fetch.client(a, cfg3, 8usize)
    if ce3 != ok { os.exit(12i32) }
    var t3 = c3
    let (r9, e9) = fetch.fetch(&t3, request("http://thirdp.test/a.js", "http://site.test/"))
    if e9 != fetch.BlockedByFilter || t3.blocked != 1usize { os.exit(13i32) }
    let (r10, e10) = fetch.fetch(&t3, request("http://thirdp.test/a.js", "http://www.thirdp.test/"))
    if e10 == fetch.BlockedByFilter || t3.blocked != 1usize { os.exit(14i32) }
    // Request-type options: `$script` blocks only scripts, `~image` everything but images.
    var cfg4 = fetch.default_config(zero)
    let rules4 = policy.parse_filter_list(a, "||onlyscript.test^$script\n||notimage.test^$~image\n||plain.test^\n")
    cfg4.block_hosts = rules4.domains
    cfg4.typed_hosts = rules4.typed
    cfg4.typed_types = rules4.types
    if rules4.domains.len != 3usize || rules4.typed.len != 2usize { os.exit(15i32) }
    let (c4, ce4) = fetch.client(a, cfg4, 8usize)
    if ce4 != ok { os.exit(16i32) }
    var t4 = c4
    let (r11, e11) = fetch.fetch(&t4, request_as("http://onlyscript.test/a.js", "http://site.test/", "script"))
    if e11 != fetch.BlockedByFilter || t4.blocked != 1usize { os.exit(17i32) }
    let (r12, e12) = fetch.fetch(&t4, request_as("http://onlyscript.test/a.png", "http://site.test/", "image"))
    if e12 == fetch.BlockedByFilter || t4.blocked != 1usize { os.exit(18i32) }
    let (r13, e13) = fetch.fetch(&t4, request_as("http://notimage.test/a.png", "http://site.test/", "image"))
    if e13 == fetch.BlockedByFilter || t4.blocked != 1usize { os.exit(19i32) }
    let (r14, e14) = fetch.fetch(&t4, request_as("http://notimage.test/a.js", "http://site.test/", "script"))
    if e14 != fetch.BlockedByFilter || t4.blocked != 2usize { os.exit(20i32) }
    let (r15, e15) = fetch.fetch(&t4, request_as("http://plain.test/a.png", "http://site.test/", "image"))
    if e15 != fetch.BlockedByFilter || t4.blocked != 3usize { os.exit(21i32) }
    // With no list there is no blocking.
    let (c1, ce1) = fetch.client(a, fetch.default_config(zero), 8usize)
    if ce1 != ok { os.exit(9i32) }
    var off = c1
    let (r8, e8) = fetch.fetch(&off, request("http://tracker.test/a.js", "http://site.test/"))
    if e8 == fetch.BlockedByFilter || off.blocked != 0usize { os.exit(10i32) }
    ret ok
}
