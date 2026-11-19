// e.algo.stat.massmds against MASS sammon, isoMDS and Shepard. tests/oracle/mass_mds.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_mds`; the layout is at the top of scripts/r_oracle/groups/mass_mds.R.

use e.algo.stat.massmds as mm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "shepard") {
        let n = usize(z[0usize])
        let k = usize(z[1usize])
        let nd = n * (n - 1usize) / 2usize
        let (ys, e1) = mem.alloc[f64](a, nd)
        let (yf, e2) = mem.alloc[f64](a, nd)
        if e1 != ok || e2 != ok { ret nan }
        let (_, e) = mm.shepard(a, z[4usize..4usize + nd], z[4usize + nd..4usize + nd + n * k], n, k, z[2usize], ys, yf)
        if e != ok { ret nan }
        if usize(z[3usize]) == 1usize { ret wsum(yf) }
        ret wsum(ys)
    }
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let mode = usize(z[5usize])
    let (y, e0) = mem.alloc[f64](a, n * k)
    if e0 != ok { ret nan }
    let dm = z[6usize..6usize + n * n]
    let y0 = z[6usize + n * n..6usize + n * n + n * k]
    var stress = 0.0f64
    var e = ok
    if str.eq(c.name, "sammon") {
        var i = 0usize
        while i < n * k {
            y[i] = y0[i]
            i += 1usize
        }
        let (s, e1) = mm.sammon(a, dm, n, k, y, usize(z[2usize]), z[3usize], z[4usize])
        stress = s
        e = e1
    } else {
        let (s, e1) = mm.isomds(a, dm, n, k, y0, z[2usize], usize(z[3usize]), z[4usize], y)
        stress = s
        e = e1
    }
    if e != ok { ret nan }
    if mode == 0usize { ret stress }
    ret wsum(y)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_mds.json")
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
