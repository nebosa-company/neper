// Web Platform Tests runner for scripts (browser tracker 6): `web-run ROOT LIST [--show] [--floor N]`.
//
// LIST names test files (one path per line, relative to ROOT, a checkout of web-platform-tests). Each file runs in a fresh
// browsing context: `.html`/`.htm` files are parsed as they are, `.any.js` / `.window.js` files are wrapped in the page the WPT
// server would generate (testharness.js, the META scripts, the test script). The page's scripts run in document order, then
// DOMContentLoaded and load fire and the event loop runs on a virtual clock until idle. `testharnessreport.js` is replaced by a
// reporter that prints one line per subtest; a file passes a subtest when testharness reports PASS for it. The summary line is
// `wpt FILES files SUBTESTS subtests PASS pass`.

use e.fmt.dom as dom
use e.fmt.html as html
use e.fs
use e.io
use e.js.interp as js
use e.mem
use e.os
use e.str
use e.thread
use e.web.script as script

type Ctx = struct { a: *mem.Arena, args: []str, status: i32 }

fn reporter() -> str {
    ret "function __s(x) { return String(x).replace(/[\\t\\n\\r]/g, ' '); }\nadd_result_callback(function (t) { console.log('@@wpt\\ttest\\t' + t.status + '\\t' + __s(t.name) + '\\t' + __s(t.message || '')); });\nadd_completion_callback(function (tests, status) { console.log('@@wpt\\tdone\\t' + status.status + '\\t' + __s(status.message || '')); });\n"
}

fn cat3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    let (xy, e1) = str.concat(a, x, y)
    let (xyz, e2) = str.concat(a, xy, z)
    if e1 != ok || e2 != ok { ret "" }
    ret xyz
}

fn parse_options() -> html.Options {
    ret html.Options { max_bytes: 67108864usize, max_nodes: 1000000usize, max_attributes: 256usize, max_depth: 512u16, preserve_comments: true }
}

// The directory part of a path, with a trailing slash ("" when there is none).
fn dir_of(path: str) -> str {
    var i = path.len
    while i > 0usize && path[i - 1usize] != 47u8 { i -= 1usize }
    ret path[0usize..i]
}

// Joins and normalises "a/b/../c" style paths.
fn normalize(a: *mem.Arena, path: str) -> str {
    var out = ""
    var segs: [64]str = zero
    var n = 0usize
    var pos = 0usize
    while pos <= path.len {
        var end = pos
        while end < path.len && path[end] != 47u8 { end += 1usize }
        let seg = path[pos..end]
        if str.eq(seg, "..") {
            if n > 0usize { n -= 1usize }
        } else if seg.len > 0usize && !str.eq(seg, ".") {
            if n < 64usize {
                segs[n] = seg
                n += 1usize
            }
        }
        pos = end + 1usize
    }
    var i = 0usize
    while i < n {
        out = cat3(a, out, "/", segs[i])
        i += 1usize
    }
    ret out
}

fn resolve_src(a: *mem.Arena, test_dir: str, src: str) -> str {
    var p = src
    var hash_at = p.len
    var k = 0usize
    while k < p.len {
        if p[k] == 63u8 || p[k] == 35u8 {
            hash_at = k
            break
        }
        k += 1usize
    }
    p = p[0usize..hash_at]
    if p.len > 0usize && p[0usize] == 47u8 { ret normalize(a, p) }
    ret normalize(a, cat3(a, "/", test_dir, p))
}

// The generated page of an `.any.js` / `.window.js` test: the harness, the META scripts and the test script.
fn wrapper_page(a: *mem.Arena, test_path: str, source: str) -> str {
    var page = "<!doctype html>\n<meta charset=utf-8>\n<script src=\"/resources/testharness.js\"></script>\n<script src=\"/resources/testharnessreport.js\"></script>\n"
    var lines = str.lines(source)
    var go = true
    while go {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        let t = str.trim(line)
        if str.starts_with(t, "// META: script=") {
            let name = str.trim(t[16usize..])
            page = cat3(a, page, cat3(a, "<script src=\"", name, "\"></script>\n"), "")
        } else if !str.starts_with(t, "//") && t.len > 0usize {
            go = false
        }
    }
    let base = test_path[dir_of(test_path).len..]
    page = cat3(a, page, cat3(a, "<div id=log></div>\n<script src=\"", base, "\"></script>\n"), "")
    ret page
}

type FetchCtx = struct { a: *mem.Arena, root: str }

// The WPT server's files: urls map onto the checkout; testharnessreport.js is the reporter above.
fn fetch_file(ctx: *void, u: str, referrer: str) -> (str, u16, bool) {
    let fc = mem.cast[*FetchCtx](ctx)
    var path: str = u
    let (sch, has_scheme) = str.find(u, "://")
    if has_scheme {
        let rest: str = u[sch + 3usize..]
        let (sl, has_slash) = str.find(rest, "/")
        if has_slash { path = rest[sl..] } else { path = "/" }
    }
    var cut = path.len
    var k = 0usize
    while k < path.len {
        if path[k] == 63u8 || path[k] == 35u8 {
            cut = k
            break
        }
        k += 1usize
    }
    path = path[0usize..cut]
    if str.eq(path, "/resources/testharnessreport.js") { ret (reporter(), 200u16, true) }
    let (txt, fe) = fs.read_file(fc.a, cat3(fc.a, fc.root, path, ""), 16777216usize)
    if fe != ok { ret ("", 404u16, true) }
    let body: str = txt
    ret (body, 200u16, true)
}

type Counts = struct { subtests: usize, passed: usize, harness_ok: bool, done: bool }

// Reads the reporter's lines out of the host log.
fn tally(it: *js.Interp, show: bool, test_path: str) -> Counts {
    var c = Counts { subtests: 0usize, passed: 0usize, harness_ok: false, done: false }
    let h = script.host_of(it)
    var i = 0usize
    while i < h.log.len {
        let line = h.log.items[i]
        i += 1usize
        if !str.starts_with(line, "log: @@wpt\t") { continue }
        let rest: str = line[11usize..]
        if str.starts_with(rest, "test\t") {
            let body: str = rest[5usize..]
            c.subtests += 1usize
            if str.starts_with(body, "0\t") {
                c.passed += 1usize
            } else if show {
                let p = io.printf["  FAIL {}: {}\n"](test_path, body)
            }
        } else if str.starts_with(rest, "done\t") {
            c.done = true
            c.harness_ok = str.starts_with(rest[5usize..], "0")
            if show && !c.harness_ok {
                let p2 = io.printf["  HARNESS {}: {}\n"](test_path, rest[5usize..])
            }
        } else if show {
            let p3 = io.printf["  LOG {}\n"](rest)
        }
    }
    ret c
}

fn run_page(a: *mem.Arena, root: str, test_path: str, page_src: str, show: bool) -> (Counts, bool) {
    let none = Counts { subtests: 0usize, passed: 0usize, harness_ok: false, done: false }
    let (d, de) = dom.parse_with(a, page_src, parse_options(), 400000usize, true)
    if de != ok { ret (none, false) }
    var tree = d
    if show { let pp = io.printf["  stage parsed {}\n"](test_path) }
    let (it, ie) = script.new_context(a, &tree, cat3(a, "http://web-platform.test:8000", test_path, ""))
    if ie != ok {
        let p = io.printf["  CONTEXT {}: failed to build the page environment ({})\n"](test_path, script.describe_thrown(it))
        ret (none, false)
    }
    it.quiet = true
    it.step_limit = 400000000u64
    it.mem_limit = mem.mark(a) + 2400000000usize
    if show { let pq = io.printf["  stage context {}\n"](test_path) }
    var fc = FetchCtx { a: a, root: root }
    script.set_fetch(it, mem.cast[*void](&fc), fetch_file)
    script.lifecycle(it, "run")
    script.pump(it, 120000.0f64)
    let counts = tally(it, show, test_path)
    ret (counts, true)
}

fn run_all(ctx: *Ctx) {
    let a = ctx.a
    let args = ctx.args
    var root = ""
    var list_path = ""
    var show = false
    var floor = 0usize
    var i = 0usize
    while i < args.len {
        if i == 0usize {
            // the program name
        } else if str.eq(args[i], "--show") {
            show = true
        } else if str.eq(args[i], "--floor") {
            i += 1usize
            let (n, ne) = str.parse_i64(args[i])
            if ne == ok { floor = usize(n) }
        } else if root.len == 0usize {
            root = args[i]
        } else {
            list_path = args[i]
        }
        i += 1usize
    }
    if root.len == 0usize || list_path.len == 0usize {
        ctx.status = 2i32
        ret
    }
    let (list_text, le) = fs.read_file(a, list_path, 67108864usize)
    if le != ok {
        ctx.status = 3i32
        ret
    }
    let base = mem.mark(a)
    var files = 0usize
    var subtests = 0usize
    var passed = 0usize
    var pos = 0usize
    while pos < list_text.len {
        var end = pos
        while end < list_text.len && list_text[end] != 10u8 { end += 1usize }
        let path = str.trim(list_text[pos..end])
        pos = end + 1usize
        if path.len == 0usize { continue }
        let work = mem.mark(a)
        let (src, fe) = fs.read_file(a, cat3(a, root, cat3(a, "/", path, ""), ""), 8388608usize)
        if fe != ok {
            mem.reset(a, work)
            continue
        }
        var page: str = src
        var test_path = cat3(a, "/", path, "")
        if str.ends_with(path, ".any.js") || str.ends_with(path, ".window.js") { page = wrapper_page(a, test_path, src) }
        if str.ends_with(path, ".any.js") || str.ends_with(path, ".window.js") || str.ends_with(path, ".html") || str.ends_with(path, ".htm") || str.ends_with(path, ".xhtml") {
            let (counts, ran) = run_page(a, root, test_path, page, show)
            files += 1usize
            subtests += counts.subtests
            passed += counts.passed
            var note = ""
            if !counts.done { note = " (no result)" }
            let used = (mem.mark(a) - work) / 1048576usize
            let p = io.printf["FILE {} {}/{}{} {}MB\n"](path, counts.passed, counts.subtests, note, used)
        }
        mem.reset(a, work)
    }
    mem.reset(a, base)
    let summary = io.printf["wpt {} files {} subtests {} pass\n"](files, subtests, passed)
    if passed < floor { ctx.status = 1i32 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The interpreter recurses deeply, so it runs on a thread with a large stack.
    var ctx = Ctx { a: a, args: args, status: 0i32 }
    let (th, te) = thread.spawn[Ctx](run_all, &ctx, 536870912usize)
    if te != ok { os.exit(5i32) }
    let je = thread.join(th)
    if ctx.status != 0i32 { os.exit(ctx.status) }
    ret ok
}
