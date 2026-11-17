// e.algo.stat.compositions_miss against compositions. tests/oracle/compositions_miss.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R compositions_miss`; the layout of every case is at the top of scripts/r_oracle/groups/compositions_miss.R.

use e.algo.rand.r as rng
use e.algo.stat.compositions_miss as cm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pick(v: []const f64, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if j == 0usize { s += v[i] }
        if j == 1usize { s += v[i] * f64(i + 1usize) }
        if j == 2usize { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let last = usize(z[z.len - 1usize])
    if str.eq(c.name, "miss") {
        let kind = usize(z[0usize])
        let n = usize(z[1usize])
        let d = usize(z[2usize])
        let x = z[3usize..3usize + n * d]
        let (o, e) = mem.alloc[f64](a, n * d + d * d)
        if e != ok { ret nan() }
        if kind == 0usize {
            if cm.mean_missing(a, x, n, d, o) != ok { ret nan() }
            ret pick(o[0usize..d], last)
        }
        if kind == 1usize {
            let m = cm.var_complete(a, x, n, d, o)
            if m < 2usize { ret nan() }
            ret pick(o[0usize..d * d], last)
        }
        cm.cdt_missing(x, n, d, o)
        ret pick(o[0usize..n * d], last)
    }
    if str.eq(c.name, "rn") {
        let kind = usize(z[0usize])
        let n = usize(z[1usize])
        let d = usize(z[2usize])
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(z[3usize]))
        let mean = z[4usize..4usize + d]
        let vr = z[4usize + d..4usize + d + d * d]
        let alpha = z[4usize + d + d * d..4usize + 2usize * d + d * d]
        let (o, e) = mem.alloc[f64](a, n * d)
        if e != ok { ret nan() }
        if kind == 0usize { if cm.rnorm_acomp(a, &rg, n, mean, vr, d, o) != ok { ret nan() } }
        if kind == 1usize { if cm.rnorm_rcomp(a, &rg, n, mean, vr, d, o) != ok { ret nan() } }
        if kind == 2usize { cm.rdirichlet(&rg, n, alpha, o) }
        ret pick(o, last)
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/compositions_miss.json")
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
