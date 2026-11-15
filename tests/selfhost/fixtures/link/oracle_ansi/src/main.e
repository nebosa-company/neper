// e.text.ansi against R's cli: strip, has_any, nchar (graphemes, bytes, width, code points),
// substr, simplify, html, trimws, align and ASCII case conversion, on strings with SGR
// attributes, colours, hyperlinks and other CSI sequences over ASCII, accented, wide, emoji and
// Hangul text. tests/oracle/ansi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ansi`. A case holds the input strings
// ("in"), the operation and its options; the answer is the results joined by U+0001.

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.ansi as ansi

fn join(a: *mem.Arena, parts: []const str) -> []u8 {
    var total = 0usize
    var i = 0usize
    while i < parts.len {
        total += parts[i].len + 1usize
        i += 1usize
    }
    let (buf, e) = mem.alloc[u8](a, total + 1usize)
    if e != ok { os.exit(5) }
    var at = 0usize
    i = 0usize
    while i < parts.len {
        if i > 0usize {
            buf[at] = 1u8
            at += 1usize
        }
        var k = 0usize
        while k < parts[i].len {
            buf[at + k] = parts[i][k]
            k += 1usize
        }
        at += parts[i].len
        i += 1usize
    }
    ret buf[0usize..at]
}

fn numbers(a: *mem.Arena, values: []const i64) -> []u8 {
    let (parts, pe) = mem.alloc[str](a, values.len)
    if pe != ok { os.exit(5) }
    var i = 0usize
    while i < values.len {
        let (initial, be) = str.builder(a, 24usize)
        if be != ok { os.exit(5) }
        var b = initial
        let _ = str.push_i64(&b, values[i])
        parts[i] = str.done(&b)
        i += 1usize
    }
    ret join(a, parts)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> []u8 {
    let x = c.inputs
    let args = c.args
    if str.eq(c.name, "strip") {
        let (r, e) = ansi.strip(a, x, args[0usize] != 0.0f64, args[1usize] != 0.0f64, args[2usize] != 0.0f64)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "has_any") {
        let (r, e) = ansi.has_any(a, x, args[0usize] != 0.0f64, args[1usize] != 0.0f64, args[2usize] != 0.0f64)
        if e != ok { os.exit(7) }
        let (parts, pe) = mem.alloc[str](a, r.len)
        if pe != ok { os.exit(5) }
        var i = 0usize
        while i < r.len {
            if r[i] { parts[i] = "TRUE" } else { parts[i] = "FALSE" }
            i += 1usize
        }
        ret join(a, parts)
    }
    if str.eq(c.name, "nchar") {
        let (r, e) = ansi.nchar(a, x, u8(args[0usize]))
        if e != ok { os.exit(7) }
        ret numbers(a, r)
    }
    if str.eq(c.name, "substr") {
        let (s0, e0) = mem.alloc[i64](a, 1usize)
        let (s1, e1) = mem.alloc[i64](a, 1usize)
        if e0 != ok || e1 != ok { os.exit(5) }
        s0[0usize] = i64(args[0usize])
        s1[0usize] = i64(args[1usize])
        let (r, e) = ansi.substr(a, x, s0, s1)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "simplify") {
        let (r, e) = ansi.simplify(a, x, args[0usize] != 0.0f64)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "html") {
        let (r, e) = ansi.html(a, x, args[0usize] != 0.0f64, args[1usize] != 0.0f64)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "trimws") {
        let (r, e) = ansi.trimws(a, x, u8(args[0usize]))
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "align") {
        let (r, e) = ansi.align(a, x, i64(args[0usize]), u8(args[1usize]), u8(args[2usize]))
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    let (r, e) = ansi.convert_case(a, x, args[0usize] != 0.0f64)
    if e != ok { os.exit(7) }
    ret join(a, r)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ansi.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(c.name)
                let _ = io.print(" ")
                if c.inputs.len > 0usize { let _ = io.print(c.inputs[0usize]) }
                let _ = io.print("\n got ")
                let _ = io.print(text)
                let _ = io.print("\n  R  ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
