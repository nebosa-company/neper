// e.algo.stat.compositions against compositions. tests/oracle/compositions.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R compositions`; the layout is at the top of scripts/r_oracle/groups/compositions.R.

use e.algo.stat.compositions as cp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn reduce(v: []const f64, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if j == 0usize { s += v[i] }
        if j == 1usize { s += f64(i + 1usize) * v[i] }
        if j == 2usize { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let nm = c.name
    let j = usize(x[x.len - 1usize])
    let (out, oe) = mem.alloc[f64](a, n * d + d * d)
    if oe != ok { os.exit(5) }
    var e = ok
    var len = n * d
    if str.eq(nm, "clo") {
        cp.clo(x[3usize..3usize + n * d], n, d, out)
    } else if str.eq(nm, "clr") {
        e = cp.clr_closed(a, x[3usize..3usize + n * d], n, d, out)
    } else if str.eq(nm, "ilr") {
        e = cp.ilr(a, x[3usize..3usize + n * d], n, d, out)
        len = n * (d - 1usize)
    } else if str.eq(nm, "ilrinv") {
        e = cp.ilr_inv(a, x[3usize..3usize + n * (d - 1usize)], n, d, out)
    } else if str.eq(nm, "alr") {
        e = cp.alr(a, x[3usize..3usize + n * d], n, d, usize(x[2usize]), out)
        len = n * (d - 1usize)
    } else if str.eq(nm, "alrinv") {
        cp.alr_inv(x[3usize..3usize + n * (d - 1usize)], n, d, usize(x[2usize]), out)
    } else if str.eq(nm, "clrinv") {
        cp.clr_inv(x[3usize..3usize + n * d], n, d, out)
    } else if str.eq(nm, "norm") {
        e = cp.norm_rows(a, x[3usize..3usize + n * d], n, d, out)
        len = n
    } else if str.eq(nm, "dist") {
        e = cp.dist_rows(a, x[3usize..3usize + n * d], x[3usize + n * d..3usize + 2usize * n * d], n, d, out)
        len = n
    } else if str.eq(nm, "perturb") {
        cp.perturb(x[3usize..3usize + n * d], x[3usize + n * d..3usize + 2usize * n * d], n, d, out)
    } else if str.eq(nm, "power") {
        cp.power(x[3usize..3usize + n * d], x[2usize], n, d, out)
    } else if str.eq(nm, "mean") {
        e = cp.mean_acomp(a, x[3usize..3usize + n * d], n, d, out)
        len = d
    } else if str.eq(nm, "var") {
        e = cp.var_acomp(a, x[3usize..3usize + n * d], n, d, out)
        len = d * d
    } else {
        e = cp.variation(a, x[3usize..3usize + n * d], n, d, out)
        len = d * d
    }
    if e != ok { os.exit(6) }
    ret reduce(out[0usize..len], j)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/compositions.json")
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
