// e.algo.stat.fnn get_knn and knn.reg against FNN. tests/oracle/fnn2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fnn2`; the layout is at the top of scripts/r_oracle/groups/fnn2.R.

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
    let p = usize(z[2usize])
    let m = usize(z[3usize])
    let k = usize(z[4usize])
    let x = z[5usize..5usize + n * p]
    let ym = z[5usize + n * p..5usize + n * p + m * p]
    let y = z[5usize + n * p + m * p..5usize + n * p + m * p + n]
    let q = usize(z[5usize + n * p + m * p + n])
    if kind == 0usize {
        let (idx, e1) = mem.alloc[i64](a, n * k)
        let (dist, e2) = mem.alloc[f64](a, n * k)
        if e1 != ok || e2 != ok { ret nan }
        if fnn.knn_index(a, x, n, x, n, p, k, true, idx, dist) != ok { ret nan }
        var s = 0.0f64
        var i = 0usize
        while i < n * k {
            if q == 0usize { s += f64(idx[i]) }
            if q == 1usize { s += f64(i + 1usize) * f64(idx[i]) }
            if q == 2usize { s += dist[i] }
            if q == 3usize { s += f64(i + 1usize) * dist[i] }
            i += 1usize
        }
        ret s
    }
    var mm = n
    var qs = x
    var same = true
    if kind == 2usize {
        mm = m
        qs = ym
        same = false
    }
    let (pred, e3) = mem.alloc[f64](a, mm)
    if e3 != ok { ret nan }
    if fnn.knn_reg(a, x, n, qs, mm, p, y, k, same, pred) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if q <= 1usize {
        while i < mm {
            if q == 0usize { s += pred[i] } else { s += f64(i + 1usize) * pred[i] }
            i += 1usize
        }
        ret s
    }
    var press = 0.0f64
    var ym2 = 0.0f64
    i = 0usize
    while i < n {
        press += (y[i] - pred[i]) * (y[i] - pred[i])
        ym2 += y[i]
        i += 1usize
    }
    ym2 = ym2 / f64(n)
    var tot = 0.0f64
    i = 0usize
    while i < n {
        tot += (y[i] - ym2) * (y[i] - ym2)
        i += 1usize
    }
    if q == 2usize { ret press }
    ret 1.0f64 - press / tot
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fnn2.json")
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
