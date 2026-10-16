// test262 parse conformance runner for e.js.parse (browser tracker 5.2, 5.14).
//
//   tests/browser/js/parse.sh TEST262_DIR MANIFEST [--floor N] [--show] [--only TEXT]
//
// MANIFEST is made by scripts/gen_test262_manifest.py. A test expecting `ok` passes when the file parses; one expecting `parse`
// (a negative parse test) passes when parsing fails; `runtime:*` tests are parse-only here and expected to parse. `--show` lists
// the failures, `--floor N` fails the run below N passes.

use e.fs
use e.io
use e.js.parser as jsparse
use e.mem
use e.os
use e.str

fn trim(s: str) -> str { ret str.trim(s) }

fn field(line: str, index: usize) -> str {
    var start = 0usize
    var n = 0usize
    var i = 0usize
    while i <= line.len {
        if i == line.len || line[i] == 124u8 {
            if n == index { ret trim(line[start..i]) }
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ""
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 3usize { os.exit(2i32) }
    let root = args[1]
    let manifest = args[2]
    var floor = 0usize
    var show = false
    var only = ""
    var i = 3usize
    while i < args.len {
        if str.eq(args[i], "--floor") {
            i += 1usize
            let (n, ne) = str.parse_i64(args[i])
            if ne == ok { floor = usize(n) }
        } else if str.eq(args[i], "--show") {
            show = true
        } else if str.eq(args[i], "--only") {
            i += 1usize
            only = args[i]
        }
        i += 1usize
    }
    let (text, fe) = fs.read_file(a, manifest, 33554432usize)
    if fe != ok { os.exit(3i32) }
    let mark = mem.mark(a)
    var total = 0usize
    var passed = 0usize
    var pos = 0usize
    while pos < text.len {
        var end = pos
        while end < text.len && text[end] != 10u8 { end += 1usize }
        let line = trim(text[pos..end])
        pos = end + 1usize
        if line.len == 0usize { continue }
        let rel = field(line, 0usize)
        let expect = field(line, 1usize)
        let strict = str.eq(field(line, 2usize), "1")
        if only.len > 0usize {
            let (at, found) = str.find(rel, only)
            if !found { continue }
        }
        total += 1usize
        let work = mem.mark(a)
        let (path, pe) = str.concat(a, root, "/")
        let (path2, pe2) = str.concat(a, path, rel)
        let (src, re) = fs.read_file(a, path2, 8388608usize)
        var good = false
        if re == ok {
            var text_in: str = src
            if strict {
                let (strict_src, sre) = str.concat(a, "\"use strict\";\n", src)
                if sre == ok { text_in = strict_src }
            }
            let (parsed, perr) = jsparse.parse_program(a, text_in)
            let parses = perr == ok
            if str.eq(expect, "parse") { good = !parses } else { good = parses }
            if !good && show {
                let printed = io.printf["FAIL {} (expect {}) {} line {}\n"](rel, expect, parsed.message, i64(parsed.line))
            }
        }
        if good { passed += 1usize }
        mem.reset(a, work)
    }
    mem.reset(a, mark)
    try io.printf["js parse tests {} pass {}\n"](total, passed)
    if passed < floor { os.exit(1i32) }
    ret ok
}
