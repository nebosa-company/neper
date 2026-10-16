// WPT URL parser runner for e.fmt.url (browser tracker 1.5, 0.6).
//
//   tests/browser/url/run.sh [--show] [--floor N] [urltestdata.json]
//
// Each case of `urltestdata.json` (the Web Platform Tests' url/resources file) is parsed with its base and the components
// compared: href, origin, protocol, username, password, host, hostname, port, pathname, search, hash; a case marked
// `failure` must fail. `--show` prints every failing case; `--floor N` makes the exit status fail below N passes.

use e.fmt.json as json
use e.fmt.url as url
use e.fs
use e.io
use e.mem
use e.os
use e.str

error BelowFloor

type Counts = struct { total: usize, pass: usize, skipped: usize }

fn member(obj: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < obj.len {
        if str.eq(obj[i].key, key) { ret (obj[i].value, true) }
        i += 1usize
    }
    ret (zero, false)
}

fn text_of(obj: []const json.Member, key: str) -> (str, bool) {
    let (v, has) = member(obj, key)
    if !has { ret ("", false) }
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
    ret ("", false)
}

fn bool_of(obj: []const json.Member, key: str) -> bool {
    let (v, has) = member(obj, key)
    if !has { ret false }
    switch v {
    case .Bool as b:
        ret b
    default:
        ret false
    }
    ret false
}

fn check(a: *mem.Arena, obj: []const json.Member, show: bool, c: *Counts) {
    let (input, has_input) = text_of(obj, "input")
    if !has_input { ret }
    c.total += 1usize
    let (base_text, has_base) = text_of(obj, "base")
    let failure = bool_of(obj, "failure")
    var parsed: url.Url = zero
    var ok_parse = false
    if has_base {
        let (b, be) = url.parse(a, base_text, zero, false)
        if be == ok {
            let (u, ue) = url.parse(a, input, &b, true)
            if ue == ok {
                parsed = u
                ok_parse = true
            }
        }
    } else {
        let (u, ue) = url.parse(a, input, zero, false)
        if ue == ok {
            parsed = u
            ok_parse = true
        }
    }
    var good = true
    var why = ""
    if failure {
        if ok_parse {
            good = false
            why = "should have failed"
        }
    } else if !ok_parse {
        good = false
        why = "failed to parse"
    } else {
        let (want_href, h1) = text_of(obj, "href")
        let got_href = url.href(a, &parsed, false)
        if h1 && !str.eq(want_href, got_href) {
            good = false
            why = "href"
        }
        let (want_origin, h2) = text_of(obj, "origin")
        if good && h2 && !str.eq(want_origin, url.origin(a, &parsed)) {
            good = false
            why = "origin"
        }
        let (want_protocol, h3) = text_of(obj, "protocol")
        if good && h3 && !str.eq(want_protocol, url.protocol(a, &parsed)) {
            good = false
            why = "protocol"
        }
        let (want_host, h4) = text_of(obj, "host")
        if good && h4 && !str.eq(want_host, url.host_port(a, &parsed)) {
            good = false
            why = "host"
        }
        let (want_hostname, h5) = text_of(obj, "hostname")
        if good && h5 && !str.eq(want_hostname, parsed.host) {
            good = false
            why = "hostname"
        }
        let (want_port, h6) = text_of(obj, "port")
        if good && h6 && !str.eq(want_port, url.port_text(a, &parsed)) {
            good = false
            why = "port"
        }
        let (want_path, h7) = text_of(obj, "pathname")
        if good && h7 && !str.eq(want_path, parsed.path) {
            good = false
            why = "pathname"
        }
        let (want_search, h8) = text_of(obj, "search")
        if good && h8 && !str.eq(want_search, url.search(a, &parsed)) {
            good = false
            why = "search"
        }
        let (want_hash, h9) = text_of(obj, "hash")
        if good && h9 && !str.eq(want_hash, url.hash(a, &parsed)) {
            good = false
            why = "hash"
        }
        let (want_user, h10) = text_of(obj, "username")
        if good && h10 && !str.eq(want_user, parsed.username) {
            good = false
            why = "username"
        }
        let (want_pass, h11) = text_of(obj, "password")
        if good && h11 && !str.eq(want_pass, parsed.password) {
            good = false
            why = "password"
        }
    }
    if good {
        c.pass += 1usize
    } else if show {
        let printed = io.printf["FAIL {}: {} | base {}\n"](why, input, base_text)
    }
}

fn expected_ok(a: *mem.Arena, exp: []const json.Member, u: *const url.Url) -> (bool, str) {
    let (want_href, h1) = text_of(exp, "href")
    if h1 && !str.eq(want_href, url.href(a, u, false)) { ret (false, "href") }
    let (want_protocol, h3) = text_of(exp, "protocol")
    if h3 && !str.eq(want_protocol, url.protocol(a, u)) { ret (false, "protocol") }
    let (want_user, h4) = text_of(exp, "username")
    if h4 && !str.eq(want_user, u.username) { ret (false, "username") }
    let (want_pass, h5) = text_of(exp, "password")
    if h5 && !str.eq(want_pass, u.password) { ret (false, "password") }
    let (want_host, h6) = text_of(exp, "host")
    if h6 && !str.eq(want_host, url.host_port(a, u)) { ret (false, "host") }
    let (want_hostname, h7) = text_of(exp, "hostname")
    if h7 && !str.eq(want_hostname, u.host) { ret (false, "hostname") }
    let (want_port, h8) = text_of(exp, "port")
    if h8 && !str.eq(want_port, url.port_text(a, u)) { ret (false, "port") }
    let (want_path, h9) = text_of(exp, "pathname")
    if h9 && !str.eq(want_path, u.path) { ret (false, "pathname") }
    let (want_search, h10) = text_of(exp, "search")
    if h10 && !str.eq(want_search, url.search(a, u)) { ret (false, "search") }
    let (want_hash, h11) = text_of(exp, "hash")
    if h11 && !str.eq(want_hash, url.hash(a, u)) { ret (false, "hash") }
    ret (true, "")
}

fn apply_setter(a: *mem.Arena, attr: str, u: *const url.Url, value: str) -> url.Url {
    if str.eq(attr, "protocol") { ret url.set_protocol(a, u, value) }
    if str.eq(attr, "username") { ret url.set_username(a, u, value) }
    if str.eq(attr, "password") { ret url.set_password(a, u, value) }
    if str.eq(attr, "host") { ret url.set_host(a, u, value) }
    if str.eq(attr, "hostname") { ret url.set_hostname(a, u, value) }
    if str.eq(attr, "port") { ret url.set_port(a, u, value) }
    if str.eq(attr, "pathname") { ret url.set_pathname(a, u, value) }
    if str.eq(attr, "search") { ret url.set_search(a, u, value) }
    if str.eq(attr, "hash") { ret url.set_hash(a, u, value) }
    if str.eq(attr, "href") {
        let (n, ne) = url.parse(a, value, zero, false)
        if ne == ok { ret n }
    }
    ret *u
}

fn run_setters(a: *mem.Arena, doc: json.Value, show: bool, c: *Counts) {
    switch doc {
    case .Object as groups:
        var g = 0usize
        while g < groups.len {
            let attr = groups[g].key
            switch groups[g].value {
            case .Array as cases:
                var k = 0usize
                while k < cases.len {
                    switch cases[k] {
                    case .Object as obj:
                        let (start, has_start) = text_of(obj, "href")
                        let (new_value, has_value) = text_of(obj, "new_value")
                        let (exp_value, has_exp) = member(obj, "expected")
                        if has_start && has_value && has_exp {
                            c.total += 1usize
                            let (u0, e0) = url.parse(a, start, zero, false)
                            if e0 == ok {
                                let changed = apply_setter(a, attr, &u0, new_value)
                                switch exp_value {
                                case .Object as exp:
                                    let (good, why) = expected_ok(a, exp, &changed)
                                    if good {
                                        c.pass += 1usize
                                    } else if show {
                                        let printed = io.printf["FAIL {} {}: {} <- {} | now {}\n"](attr, why, start, new_value, url.href(a, &changed, false))
                                    }
                                default:
                                    c.skipped += 1usize
                                }
                            } else if show {
                                let printed = io.printf["FAIL {}: bad start {}\n"](attr, start)
                            }
                        }
                    default:
                        c.skipped += 0usize
                    }
                    k += 1usize
                }
            default:
                c.skipped += 0usize
            }
            g += 1usize
        }
    default:
        c.skipped += 0usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var show = false
    var setters = false
    var floor = 0usize
    var path = "tests/browser/url/data/urltestdata.json"
    var i = 1usize
    while i < args.len {
        if str.eq(args[i], "--show") {
            show = true
        } else if str.eq(args[i], "--setters") {
            setters = true
            path = "tests/browser/url/data/setters_tests.json"
        } else if str.eq(args[i], "--floor") {
            i += 1usize
            let (n, ne) = str.parse_i64(args[i])
            if ne == ok { floor = usize(n) }
        } else {
            path = args[i]
        }
        i += 1usize
    }
    let (bytes, fe) = fs.read_file(a, path, 16777216usize)
    if fe != ok {
        let printed = io.printf["cannot read the test data\n"]()
        os.exit(2i32)
    }
    let (doc, je) = json.parse(a, bytes, json.Options { allow_duplicate_keys: true, max_depth: 16u16 })
    if je != ok {
        let printed = io.printf["cannot parse the test data\n"]()
        os.exit(2i32)
    }
    var counts = Counts { total: 0usize, pass: 0usize, skipped: 0usize }
    if setters {
        run_setters(a, doc, show, &counts)
        try io.printf["setter cases {} pass {}\n"](counts.total, counts.pass)
        if counts.pass < floor { os.exit(1i32) }
        ret ok
    }
    switch doc {
    case .Array as items:
        var k = 0usize
        while k < items.len {
            switch items[k] {
            case .Object as obj:
                check(a, obj, show, &counts)
            default:
                counts.skipped += 0usize
            }
            k += 1usize
        }
    default:
        counts.skipped += 0usize
    }
    try io.printf["url cases {} pass {}\n"](counts.total, counts.pass)
    if counts.pass < floor { os.exit(1i32) }
    ret ok
}

