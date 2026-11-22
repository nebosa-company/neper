// e.algo.stat.klar.sknn_predict against klaR::sknn. tests/oracle/klar_sknn.json comes from
// `Rscript scripts/r_oracle/generate.R klar_sknn`; the layout is at the top of
// scripts/r_oracle/groups/klar_sknn.R.

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
    let kn = usize(z[3usize])
    let gam = z[4usize]
    let m = usize(z[5usize])
    let base = 6usize
    let learn = z[base..base + n * p]
    let (lab, e0) = mem.alloc[usize](a, n)
    let (dist, e1) = mem.alloc[f64](a, n)
    let (cand, e2) = mem.alloc[usize](a, n)
    let (post, e3) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        lab[i] = usize(z[base + n * p + i])
        i += 1usize
    }
    let test = z[base + n * p + n..base + n * p + n + m * p]
    let kind = c.name
    var s = 0.0f64
    var r = 0usize
    while r < m {
        let cls = kl.sknn_predict(test[r * p..r * p + p], p, learn, n, lab, kn, gam, dist, cand, post)
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/klar_sknn.json")
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
