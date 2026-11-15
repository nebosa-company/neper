// viridis (Lab spline ramp over the 256-colour maps) and brewer.pal against R's viridisLite and
// RColorBrewer, string for string. tests/oracle/palette.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R palette`.

use e.gfx.palette as palette
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn join(a: *mem.Arena, parts: []str) -> []u8 {
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
            buf[at] = 44u8
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> []u8 {
    if str.eq(c.name, "viridis") {
        let x = c.args
        let letter = u8(64u64 + u64(x[5]))
        let (colors, e) = palette.viridis(a, usize(x[0]), x[1], x[2], x[3], i64(x[4]), letter)
        if e != ok { os.exit(7) }
        ret join(a, colors)
    }
    let name = c.name[7usize..c.name.len]
    let (colors, e) = palette.brewer_pal(a, usize(c.args[0]), name)
    if e != ok { os.exit(8) }
    ret join(a, colors)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/palette.json")
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
            if failures <= 6usize {
                let _ = io.print(c.name)
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
