// e.algo.stat.tsutils against tseries bds.test and tsbootstrap. tests/oracle/tsutils.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsutils`; the layout is at the top of scripts/r_oracle/groups/tsutils.R.

use e.algo.rand.r as rng
use e.algo.stat.boot as bt
use e.algo.stat.tsutils as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "bds") {
        let m = usize(z[0usize])
        let n = usize(z[2usize])
        let (out, oe) = mem.alloc[f64](a, m)
        if oe != ok { ret nan }
        if ts.bds_stat(a, z[3usize..3usize + n], m, z[1usize], out) != ok { ret nan }
        ret out[usize(z[3usize + n]) - 2usize]
    }
    if str.eq(c.name, "po") {
        let n = usize(z[0usize])
        let k = usize(z[1usize])
        let (w, we) = mem.alloc[f64](a, k)
        if we != ok { ret nan }
        let lo = z[7usize..7usize + k]
        let hi = z[7usize + k..7usize + 2usize * k]
        let x = z[7usize + 2usize * k..7usize + 2usize * k + n * k]
        if !ts.portfolio_optim(a, x, n, k, z[2usize], z[3usize] == 1.0f64, z[4usize] == 1.0f64, z[5usize], z[6usize] == 1.0f64, lo, hi, w) { ret nan }
        ret w[usize(z[7usize + 2usize * k + n * k])]
    }
    if str.eq(c.name, "nn") {
        let kind = usize(z[0usize])
        var gg: rng.Rng = zero
        rng.seed(&gg, i64(z[1usize]))
        let n = usize(z[2usize])
        let nin = usize(z[3usize])
        let ftype = z[4usize] == 1.0f64
        let sc = z[5usize] == 1.0f64
        let x = z[9usize..9usize + n * nin]
        let y = z[9usize + n * nin..9usize + n * nin + n]
        let w = usize(z[9usize + n * nin + n])
        var st = 0.0f64
        var d1 = 0.0f64
        var d2 = 0.0f64
        if kind == 0usize {
            let (s0, a1, a2, e) = ts.terasvirta(a, x, y, n, nin, ftype, sc)
            if e != ok { ret nan }
            st = s0
            d1 = a1
            d2 = a2
        } else {
            let (s0, a1, a2, e) = ts.white(a, &gg, x, y, n, nin, usize(z[6usize]), usize(z[7usize]), z[8usize], ftype, sc)
            if e != ok { ret nan }
            st = s0
            d1 = a1
            d2 = a2
        }
        if w == 0usize { ret st }
        if w == 1usize { ret d1 }
        ret d2
    }
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let qtype = u8(z[1usize])
    let b = z[2usize]
    let nb = usize(z[3usize])
    let st = u8(z[4usize])
    let n = usize(z[5usize])
    let x = z[6usize..6usize + n]
    let q = usize(z[6usize + n])
    let (buf, e1) = mem.alloc[f64](a, n)
    let (stats, e2) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < nb {
        var pp = b
        if qtype == 0u8 { pp = 1.0f64 / b }
        ts.boot_sample(&g, x, pp, qtype, buf)
        stats[i] = bt.stat_of(a, st, buf)
        i += 1usize
    }
    if q == 2usize { ret stats[0usize] }
    if q == 3usize { ret stats[nb - 1usize] }
    var s = 0.0f64
    i = 0usize
    while i < nb {
        if q == 0usize { s += stats[i] } else { s += f64(i + 1usize) * stats[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsutils.json")
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
