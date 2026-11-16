// e.algo.stat.klar against klaR. tests/oracle/klar.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R klar`; the layout is at the top of scripts/r_oracle/groups/klar.R.

use e.algo.stat.klar as kl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let k = usize(x[2usize])
    let m = usize(x[3usize])
    let data = x[4usize..4usize + n * p]
    let (lab, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        lab[i] = usize(x[4usize + n * p + i])
        i += 1usize
    }
    let test = x[4usize + n * p + n..4usize + n * p + n + m * p]
    let (prior, e2) = mem.alloc[f64](a, k)
    if e2 != ok { os.exit(6) }
    let (mean, e3) = mem.alloc[f64](a, k * p)
    if e3 != ok { os.exit(7) }
    let (sd, e4) = mem.alloc[f64](a, k * p)
    if e4 != ok { os.exit(8) }
    kl.nb_fit(data, n, p, lab, k, prior, mean, sd)
    let kind = c.name
    var s = 0.0f64
    if str.eq(kind, "prior") {
        i = 0usize
        while i < k {
            s += prior[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "mean") || str.eq(kind, "sd") {
        i = 0usize
        while i < k * p {
            if str.eq(kind, "mean") { s += mean[i] * f64(i + 1usize) } else { s += sd[i] * f64(i + 1usize) }
            i += 1usize
        }
        ret s
    }
    let (post, e5) = mem.alloc[f64](a, k)
    if e5 != ok { os.exit(9) }
    var r = 0usize
    while r < m {
        let cls = kl.nb_predict(test[r * p..r * p + p], p, k, prior, mean, sd, 0.001f64, post)
        if str.eq(kind, "cls") { s += f64(cls) * f64(r + 1usize) }
        if str.eq(kind, "post") {
            var j = 0usize
            while j < k {
                s += post[j] * f64(r * k + j + 1usize)
                j += 1usize
            }
        }
        r += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/klar.json")
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
