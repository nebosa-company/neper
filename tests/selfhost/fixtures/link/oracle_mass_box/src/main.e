// e.algo.stat.massbox against MASS boxcox and logtrans. tests/oracle/mass_box.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_box`; the layout is at the top of scripts/r_oracle/groups/mass_box.R.

use e.algo.stat.massbox as mb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[4usize])
    let mode = usize(z[5usize + m])
    let off = 6usize + m
    let y = z[off..off + n]
    let x = z[off + n..off + n + n * p]
    let (ox, e1) = mem.alloc[f64](a, 100usize + m)
    let (oy, e2) = mem.alloc[f64](a, 100usize + m)
    if e1 != ok || e2 != ok { ret nan() }
    var len = 0usize
    var best = 0.0f64
    var e = ok
    if str.eq(c.name, "bc") {
        let (l, b, ee) = mb.boxcox(a, y, x, p, z[5usize..5usize + m], z[2usize] != 0.0f64, z[3usize], ox, oy)
        len = l
        best = b
        e = ee
    } else {
        let (l, b, ee) = mb.logtrans(a, y, x, p, z[5usize..5usize + m], z[2usize] != 0.0f64, ox, oy)
        len = l
        best = b
        e = ee
    }
    if e != ok { ret nan() }
    if mode == 1usize { ret best }
    if mode == 2usize { ret f64(len) }
    if mode == 3usize { ret oy[0usize] }
    if mode == 5usize { ret oy[len - 1usize] }
    var s = 0.0f64
    var i = 0usize
    if mode == 6usize {
        s = oy[0usize]
        while i < len {
            if oy[i] > s { s = oy[i] }
            i += 1usize
        }
        ret s
    }
    while i < len {
        if mode == 4usize { s += f64(i + 1usize) * ox[i] } else if mode == 7usize { s += oy[i] * oy[i] } else { s += f64(i + 1usize) * oy[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_box.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
