// e.algo.stat.fnn against FNN: entropy, KL.divergence, mutinfo. tests/oracle/fnn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fnn`; the layout is at the top of
// scripts/r_oracle/groups/fnn.R.

use e.algo.stat.fnn as fnn
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let p1 = usize(z[2usize])
    let p2 = usize(z[3usize])
    let m = usize(z[4usize])
    let kk = usize(z[5usize])
    let x = z[6usize..6usize + n * p1]
    let idx = usize(z[z.len - 1usize])
    let (out, e) = mem.alloc[f64](a, kk)
    if e != ok { ret nan }
    if kind == 0usize {
        if fnn.entropy(a, x, n, p1, kk, out) != ok { ret nan }
        ret out[idx]
    }
    if kind == 1usize {
        let y = z[6usize + n * p1..6usize + n * p1 + m * p1]
        if fnn.kl_divergence(a, x, n, y, m, p1, kk, out) != ok { ret nan }
        ret out[idx]
    }
    let y = z[6usize + n * p1..6usize + n * p1 + n * p2]
    if kind == 2usize {
        let (v, me) = fnn.mutinfo_direct(a, x, p1, y, p2, n, kk)
        if me != ok { ret nan }
        ret v
    }
    // indirect: Hx + Hy - H(x, y), each the k = K entropy
    let (hx, e1) = mem.alloc[f64](a, kk)
    let (hy, e2) = mem.alloc[f64](a, kk)
    let (hj, e3) = mem.alloc[f64](a, kk)
    let (xy, e4) = mem.alloc[f64](a, n * (p1 + p2))
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < n * p1 {
        xy[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n * p2 {
        xy[n * p1 + i] = y[i]
        i += 1usize
    }
    if fnn.entropy(a, x, n, p1, kk, hx) != ok { ret nan }
    if fnn.entropy(a, y, n, p2, kk, hy) != ok { ret nan }
    if fnn.entropy(a, xy, n, p1 + p2, kk, hj) != ok { ret nan }
    ret hx[kk - 1usize] + hy[kk - 1usize] - hj[kk - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fnn.json")
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
