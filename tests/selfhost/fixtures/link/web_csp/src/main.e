// `e.web.csp`: header parsing, the fallback chain, source-expression matching, nonces and hashes for inline content, eval, and
// the rule that `'unsafe-inline'` is ignored once a nonce or hash is present.
use e.mem
use e.os
use e.str
use e.web.csp as csp

fn set_of(a: *mem.Arena, text: str) -> csp.PolicySet {
    let (s, e) = csp.parse_set(a, text, false)
    if e != ok { os.exit(100i32) }
    ret s
}

fn allow(a: *mem.Arena, set: csp.PolicySet, dir: str, u: str) -> bool {
    ret csp.url_allowed(a, set, dir, u, "https://page.test/app/", false, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1. default-src 'self' covers everything without a more specific directive.
    let s1 = set_of(a, "default-src 'self'")
    if !allow(a, s1, "img-src", "https://page.test/x.png") { os.exit(1i32) }
    if allow(a, s1, "img-src", "https://other.test/x.png") { os.exit(2i32) }
    if allow(a, s1, "script-src-elem", "https://cdn.test/a.js") { os.exit(3i32) }
    // 2. A specific directive overrides default-src.
    let s2 = set_of(a, "default-src 'none'; img-src https://img.test data:")
    if !allow(a, s2, "img-src", "https://img.test/a.png") { os.exit(4i32) }
    if !allow(a, s2, "img-src", "data:image/png;base64,AAAA") { os.exit(5i32) }
    if allow(a, s2, "connect-src", "https://img.test/api") { os.exit(6i32) }
    // 3. Wildcard hosts, ports and paths.
    let s3 = set_of(a, "script-src *.cdn.test https://exact.test:8443/lib/ https://file.test/only.js")
    if !allow(a, s3, "script-src-elem", "https://a.cdn.test/x.js") { os.exit(7i32) }
    if allow(a, s3, "script-src-elem", "https://cdn.test/x.js") { os.exit(8i32) }
    if !allow(a, s3, "script-src-elem", "https://exact.test:8443/lib/x.js") { os.exit(9i32) }
    if allow(a, s3, "script-src-elem", "https://exact.test:8443/other/x.js") { os.exit(10i32) }
    if allow(a, s3, "script-src-elem", "https://exact.test/lib/x.js") { os.exit(11i32) }
    if !allow(a, s3, "script-src-elem", "https://file.test/only.js") { os.exit(12i32) }
    if allow(a, s3, "script-src-elem", "https://file.test/other.js") { os.exit(13i32) }
    // 4. Scheme sources and `*`.
    let s4 = set_of(a, "img-src https: ; connect-src *")
    if !allow(a, s4, "img-src", "https://anything.test/a.png") { os.exit(14i32) }
    if allow(a, s4, "img-src", "http://anything.test/a.png") { os.exit(15i32) }
    if !allow(a, s4, "connect-src", "https://x.test/") { os.exit(16i32) }
    if allow(a, s4, "connect-src", "data:text/plain,hi") { os.exit(17i32) }
    // 5. Inline scripts: blocked without a source, allowed by 'unsafe-inline', by nonce, by hash.
    let s5 = set_of(a, "script-src 'self'")
    if csp.inline_allowed(a, s5, "script-src-elem", "", "alert(1)") { os.exit(18i32) }
    let s6 = set_of(a, "script-src 'unsafe-inline'")
    if !csp.inline_allowed(a, s6, "script-src-elem", "", "alert(1)") { os.exit(19i32) }
    let s7 = set_of(a, "script-src 'nonce-abc123' 'unsafe-inline'")
    if !csp.inline_allowed(a, s7, "script-src-elem", "abc123", "alert(1)") { os.exit(20i32) }
    if csp.inline_allowed(a, s7, "script-src-elem", "wrong", "alert(1)") { os.exit(21i32) }
    if csp.inline_allowed(a, s7, "script-src-elem", "", "alert(1)") { os.exit(22i32) }
    // sha256("alert(1)") in base64.
    let s8 = set_of(a, "script-src 'sha256-bhHHL3z2vDgxUt0W3dWQOrprscmda2Y5pLsLg4GF+pI='")
    if !csp.inline_allowed(a, s8, "script-src-elem", "", "alert(1)") { os.exit(23i32) }
    if csp.inline_allowed(a, s8, "script-src-elem", "", "alert(2)") { os.exit(24i32) }
    // 6. eval.
    if csp.eval_allowed(s5) { os.exit(25i32) }
    let s9 = set_of(a, "script-src 'self' 'unsafe-eval'")
    if !csp.eval_allowed(s9) { os.exit(26i32) }
    if !csp.eval_allowed(set_of(a, "img-src *")) { os.exit(27i32) }
    // 7. Several policies must all allow; report-only never blocks.
    let s10 = set_of(a, "img-src https://a.test, img-src https://a.test https://b.test")
    if allow(a, s10, "img-src", "https://b.test/x.png") { os.exit(28i32) }
    let (ro, roe) = csp.parse_set(a, "img-src 'none'", true)
    if roe != ok || !allow(a, ro, "img-src", "https://b.test/x.png") { os.exit(29i32) }
    // 8. Style fallback and attributes.
    let s11 = set_of(a, "style-src 'self'; style-src-attr 'unsafe-inline'")
    if csp.inline_allowed(a, s11, "style-src-elem", "", "a{}") { os.exit(30i32) }
    if !csp.inline_allowed(a, s11, "style-src-attr", "", "color:red") { os.exit(31i32) }
    // 9. Directive syntax: case, repeats, empty parts.
    let s12 = set_of(a, "IMG-SRC https://one.test;; img-src https://two.test ; ")
    if !allow(a, s12, "img-src", "https://one.test/a") { os.exit(32i32) }
    if allow(a, s12, "img-src", "https://two.test/a") { os.exit(33i32) }
    // 10. base-uri has no default-src fallback.
    let s13 = set_of(a, "default-src 'none'")
    if !allow(a, s13, "base-uri", "https://anything.test/") { os.exit(34i32) }
    ret ok
}
