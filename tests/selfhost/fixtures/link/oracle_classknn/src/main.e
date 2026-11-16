// e.algo.stat.classknn against class: knn, knn1 and knn.cv under set.seed, ties and all.
// tests/oracle/classknn.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// classknn`; the layout is at the top of scripts/r_oracle/groups/classknn.R.

use e.algo.rand.r as rr
use e.algo.stat.classknn as ck
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[1usize]))
    let kind = u8(x[0usize])
    let k = usize(x[2usize])
    let l = i64(x[3usize])
    let use_all = x[4usize] != 0.0f64
    let p = usize(x[5usize])
    let ntr = usize(x[6usize])
    let nte = usize(x[7usize])
    let nc = usize(x[8usize])
    let (cl, ce) = mem.alloc[i64](a, ntr)
    if ce != ok { os.exit(5) }
    var i = 0usize
    while i < ntr {
        cl[i] = i64(x[9usize + i])
        i += 1usize
    }
    let train = x[9usize + ntr..9usize + ntr + ntr * p]
    let test = x[9usize + ntr + ntr * p..9usize + ntr + ntr * p + nte * p]
    if kind == 1u8 {
        let (r, e) = ck.knn1(a, &g, train, cl, test, p, nc)
        if e != ok { os.exit(6) }
        ret f64(r[usize(x[x.len - 1usize])])
    }
    let (r, pr, e) = ck.knn(a, &g, train, cl, test, p, nc, k, l, kind == 2u8, use_all)
    if e != ok { os.exit(7) }
    if str.eq(c.name, "cvsum") || str.eq(c.name, "cvprob") {
        var s = 0.0f64
        i = 0usize
        while i < r.len {
            if str.eq(c.name, "cvsum") {
                if r[i] == 0i64 { s += 0.0f64 / 0.0f64 } else { s += f64(r[i]) * f64(i + 1usize) }
            } else { s += pr[i] * f64(i + 1usize) }
            i += 1usize
        }
        ret s
    }
    let at = usize(x[x.len - 1usize])
    if str.eq(c.name, "cls") {
        if r[at] == 0i64 { ret 0.0f64 / 0.0f64 }
        ret f64(r[at])
    }
    ret pr[at]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/classknn.json")
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
