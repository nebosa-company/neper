// e.text.ansiwrap against R: base::strwrap and cli's ansi_strwrap, ansi_strsplit and
// ansi_strtrim. tests/oracle/ansiwrap.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ansiwrap`. A case holds the strings
// ("in") and the options (args); the answer is the lines or pieces joined by U+0001, strsplit with
// a leading count.

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.ansiwrap as w

fn join(a: *mem.Arena, parts: []const str, counted: bool) -> str {
    var total = 24usize
    var i = 0usize
    while i < parts.len {
        total += parts[i].len + 1usize
        i += 1usize
    }
    let (initial, e) = str.builder(a, total)
    if e != ok { os.exit(5) }
    var b = initial
    if counted {
        let _ = str.push_u64(&b, u64(parts.len))
        let _ = str.push(&b, ":")
    }
    i = 0usize
    while i < parts.len {
        if i > 0usize { let _ = str.push_byte(&b, 1u8) }
        let _ = str.push(&b, parts[i])
        i += 1usize
    }
    ret str.done(&b)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let x = c.args
    if str.eq(c.name, "strwrap") {
        let (r, e) = w.strwrap(a, c.inputs, i64(x[0usize]), i64(x[1usize]), i64(x[2usize]))
        if e != ok { os.exit(7) }
        ret join(a, r, false)
    }
    if str.eq(c.name, "ansi_strwrap") {
        let (r, e) = w.ansi_strwrap(a, c.inputs, i64(x[0usize]), i64(x[1usize]), i64(x[2usize]))
        if e != ok { os.exit(8) }
        ret join(a, r, false)
    }
    if str.eq(c.name, "ansi_strsplit") {
        let (r, e) = w.ansi_strsplit(a, c.inputs[0usize], c.inputs[1usize], x[0usize] != 0.0f64)
        if e != ok { os.exit(9) }
        ret join(a, r, true)
    }
    let (r, e) = w.ansi_strtrim(a, c.inputs[1usize..c.inputs.len], i64(x[0usize]), c.inputs[0usize])
    if e != ok { os.exit(10) }
    ret join(a, r, false)
}

fn vis(a: *mem.Arena, s: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c == 1u8 { c = 47u8 }
        if c == 10u8 { c = 94u8 }
        if c == 27u8 { c = 126u8 }
        buf[i] = c
        i += 1usize
    }
    ret buf[0usize..s.len]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ansiwrap.json")
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
                var k = 0usize
                while k < c.args.len {
                    let (initial, be) = str.builder(a, 24usize)
                    if be != ok { os.exit(5) }
                    var nb = initial
                    let _ = str.push_i64(&nb, i64(c.args[k]))
                    let _ = io.print(str.done(&nb))
                    let _ = io.print(",")
                    k += 1usize
                }
                let _ = io.print(" [")
                k = 0usize
                while k < c.inputs.len {
                    let _ = io.print(vis(a, c.inputs[k]))
                    let _ = io.print("|")
                    k += 1usize
                }
                let _ = io.print("]\n want ")
                let _ = io.print(vis(a, c.text))
                let _ = io.print("\n  got ")
                let _ = io.print(vis(a, text))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
