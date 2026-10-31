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
    if rules4.domains.len != 3usize || rules4.typed.len != 3usize { os.exit(15i32) }
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
    // `$domain=` limits a rule to pages on the listed domains; `~` excludes one.
    var cfg5 = fetch.default_config(zero)
    let rules5 = policy.parse_filter_list(a, "||ads.test^$domain=news.test|~live.news.test\n")
    cfg5.block_hosts = rules5.domains
    cfg5.typed_hosts = rules5.typed
    cfg5.typed_types = rules5.types
    let (c5, ce5) = fetch.client(a, cfg5, 8usize)
    if ce5 != ok { os.exit(22i32) }
    var t5 = c5
    let (r16, e16) = fetch.fetch(&t5, request("http://ads.test/a.js", "http://www.news.test/"))
    if e16 != fetch.BlockedByFilter || t5.blocked != 1usize { os.exit(23i32) }
    let (r17, e17) = fetch.fetch(&t5, request("http://ads.test/a.js", "http://other.test/"))
    if e17 == fetch.BlockedByFilter || t5.blocked != 1usize { os.exit(24i32) }
    let (r18, e18) = fetch.fetch(&t5, request("http://ads.test/a.js", "http://live.news.test/"))
    if e18 == fetch.BlockedByFilter || t5.blocked != 1usize { os.exit(25i32) }
    // `||host/path^` blocks only URLs under that path.
    var cfg6 = fetch.default_config(zero)
    let rules6 = policy.parse_filter_list(a, "||pathy.test/ads/^\n")
    cfg6.block_hosts = rules6.domains
    cfg6.typed_hosts = rules6.typed
    cfg6.typed_types = rules6.types
    if rules6.domains.len != 1usize || rules6.typed.len != 1usize { os.exit(26i32) }
    let (c6, ce6) = fetch.client(a, cfg6, 8usize)
    if ce6 != ok { os.exit(27i32) }
    var t6 = c6
    let (r19, e19) = fetch.fetch(&t6, request("http://pathy.test/ads/a.js", "http://site.test/"))
    if e19 != fetch.BlockedByFilter || t6.blocked != 1usize { os.exit(28i32) }
    let (r20, e20) = fetch.fetch(&t6, request("http://pathy.test/app.js", "http://site.test/"))
    if e20 == fetch.BlockedByFilter || t6.blocked != 1usize { os.exit(29i32) }
    // Several rules for one host: a request is blocked when any of them covers it.
    var cfg7 = fetch.default_config(zero)
    let rules7 = policy.parse_filter_list(a, "||multi.test^$image\n||multi.test/track.js^$script\n||both.test/a^\n||both.test^$image\n")
    cfg7.block_hosts = rules7.domains
    cfg7.typed_hosts = rules7.typed
    cfg7.typed_types = rules7.types
    if rules7.typed.len != 4usize { os.exit(40i32) }
    let (c7, ce7) = fetch.client(a, cfg7, 8usize)
    if ce7 != ok { os.exit(41i32) }
    var t7 = c7
    let (r21, e21) = fetch.fetch(&t7, request_as("http://multi.test/track.js", "http://site.test/", "script"))
    if e21 != fetch.BlockedByFilter || t7.blocked != 1usize { os.exit(42i32) }
    let (r22, e22) = fetch.fetch(&t7, request_as("http://multi.test/a.png", "http://site.test/", "image"))
    if e22 != fetch.BlockedByFilter || t7.blocked != 2usize { os.exit(43i32) }
    let (r23, e23) = fetch.fetch(&t7, request_as("http://multi.test/other.js", "http://site.test/", "script"))
    if e23 == fetch.BlockedByFilter || t7.blocked != 2usize { os.exit(44i32) }
    let (r24, e24) = fetch.fetch(&t7, request_as("http://both.test/a.js", "http://site.test/", "script"))
    if e24 != fetch.BlockedByFilter || t7.blocked != 3usize { os.exit(45i32) }
    let (r25, e25) = fetch.fetch(&t7, request_as("http://both.test/b.js", "http://site.test/", "script"))
    if e25 == fetch.BlockedByFilter || t7.blocked != 3usize { os.exit(46i32) }
    let (r26, e26) = fetch.fetch(&t7, request_as("http://both.test/b.png", "http://site.test/", "image"))
    if e26 != fetch.BlockedByFilter || t7.blocked != 4usize { os.exit(47i32) }
    // A subresource with a destination but no referrer is still filtered; a document request (neither) is not.
    let (r27, e27) = fetch.fetch(&t7, request_as("http://multi.test/a.png", "", "image"))
    if e27 != fetch.BlockedByFilter || t7.blocked != 5usize { os.exit(48i32) }
    let (r28, e28) = fetch.fetch(&t7, request_as("http://multi.test/a.png", "", ""))
    if e28 == fetch.BlockedByFilter || t7.blocked != 5usize { os.exit(49i32) }
    // With no list there is no blocking.
    let (c1, ce1) = fetch.client(a, fetch.default_config(zero), 8usize)
    if ce1 != ok { os.exit(9i32) }
    var off = c1
    let (r8, e8) = fetch.fetch(&off, request("http://tracker.test/a.js", "http://site.test/"))
    if e8 == fetch.BlockedByFilter || off.blocked != 0usize { os.exit(10i32) }
    ret ok
}
