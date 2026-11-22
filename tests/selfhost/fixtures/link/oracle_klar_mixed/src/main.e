// e.algo.stat.klar.nb_fit_mixed / nb_predict_mixed against klaR. tests/oracle/klar_mixed.json comes from
// `Rscript scripts/r_oracle/generate.R klar_mixed`; the layout is at the top of
// scripts/r_oracle/groups/klar_mixed.R.

use e.algo.stat.klar as kl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let m = usize(z[3usize])
    let (fac, e0) = mem.alloc[bool](a, p)
    let (lab, e1) = mem.alloc[usize](a, n)
    let (prior, e2) = mem.alloc[f64](a, k)
    let (mean, e3) = mem.alloc[f64](a, k * p)
    let (sd, e4) = mem.alloc[f64](a, k * p)
    let (post, e5) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(5) }
    let maxlev = usize(z[4usize + p])
    let base = 5usize + p
    let data = z[base..base + n * p]
    let (fprob, e6) = mem.alloc[f64](a, p * k * maxlev)
    if e6 != ok { os.exit(6) }
    var i = 0usize
    while i < p {
        fac[i] = z[4usize + i] > 0.5f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        lab[i] = usize(z[base + n * p + i])
        i += 1usize
    }
    let test = z[base + n * p + n..base + n * p + n + m * p]
    kl.nb_fit_mixed(data, n, p, lab, k, fac, maxlev, prior, mean, sd, fprob)
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
        var col = 0usize
        var idx = 0usize
        while col < p {
            if !fac[col] {
                var j = 0usize
                while j < k {
                    if str.eq(kind, "mean") {
                        s += mean[j * p + col] * f64(idx + 1usize)
                    } else {
                        s += sd[j * p + col] * f64(idx + 1usize)
                    }
                    idx += 1usize
                    j += 1usize
                }
            }
            col += 1usize
        }
        ret s
    }
    if str.eq(kind, "fprob") {
        var col = 0usize
        var idx = 0usize
        while col < p {
            if fac[col] {
                var j = 0usize
                while j < k {
                    var lev = 0usize
                    while lev < maxlev {
                        s += fprob[col * k * maxlev + j * maxlev + lev] * f64(idx + 1usize)
                        idx += 1usize
                        lev += 1usize
                    }
                    j += 1usize
                }
            }
            col += 1usize
        }
        ret s
    }
    var r = 0usize
    while r < m {
        let cls = kl.nb_predict_mixed(test[r * p..r * p + p], p, k, prior, mean, sd, fprob, fac, maxlev, 0.001f64, post)
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/klar_mixed.json")
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
