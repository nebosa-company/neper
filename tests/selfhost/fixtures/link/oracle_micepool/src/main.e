// e.algo.stat.micefull's mice, with(lm) and pool against mice 3.19: the imputed values, Rubin's and Reiter's pooling of the coefficients (estimate, ubar, b, t,
// df with the Barnard-Rubin adjustment, riv, lambda, fmi, std.error, statistic, p.value, confidence limits) and pool.r.squared.
// tests/oracle/micepool.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R micepool`; the layout is at the top of
// scripts/r_oracle/groups/micepool.R.

use e.algo.stat.micefull as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the four answers of one run: 0 the imputed values, 1 and 2 the pooled coefficient checksums, 3 pool.r.squared
fn pooled(a: *mem.Arena, z: []const f64, what: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let (imp, e1) = mem.alloc[f64](a, n * p * m + 4usize)
    let (comp, e2) = mem.alloc[f64](a, n * p * m + 4usize)
    if e1 != ok || e2 != ok { ret nan }
    let (tot, at, me) = mf.mice_run_flat(a, z, imp, comp)
    if me != ok { ret nan }
    if what == 0usize {
        var s = 0.0f64
        var q = 0usize
        while q < tot {
            s += f64(q + 1usize) * imp[q]
            q += 1usize
        }
        ret s
    }
    let ycol = usize(z[at])
    let nx = usize(z[at + 1usize])
    let (xcols, e3) = mem.alloc[usize](a, nx + 1usize)
    if e3 != ok { ret nan }
    var i = 0usize
    while i < nx {
        xcols[i] = usize(z[at + 2usize + i])
        i += 1usize
    }
    let dfcom = z[at + 2usize + nx]
    let rule = usize(z[at + 3usize + nx])
    let (out, e4) = mem.alloc[f64](a, 13usize * (nx + 1usize))
    let (r2, e5) = mem.alloc[f64](a, 4usize)
    if e4 != ok || e5 != ok { ret nan }
    let pe = mf.pool_lm(a, comp, n, p, m, ycol, xcols[0usize..nx], dfcom, rule, out, r2)
    if pe != ok { ret nan }
    var s = 0.0f64
    if what == 3usize {
        i = 0usize
        while i < 4usize {
            s += f64(i + 1usize) * r2[i]
            i += 1usize
        }
        ret s
    }
    var c = 0usize
    var k = 0usize
    while c < nx + 1usize {
        var f = 0usize
        if what == 2usize { f = 8usize }
        var top = 8usize
        if what == 2usize { top = 13usize }
        while f < top {
            k += 1usize
            var v = out[c * 13usize + f]
            if v != v { v = 0.0f64 }
            s += f64(k) * v
            f += 1usize
        }
        c += 1usize
    }
    ret s
}

fn report(a: *mem.Arena, c: *const oracle.Case, at: usize, got: f64) {
    let (b0, be) = str.builder(a, 200usize)
    if be != ok { os.exit(4) }
    var b = b0
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, " case ")
    let _ = str.push_f64(&b, f64(at))
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " want ")
    let _ = str.push_f64(&b, c.want)
    let _ = str.push(&b, "\n")
    let _ = io.print(str.done(&b))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/micepool.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64 / 0.0f64
        if str.eq(c.name, "pool_imp") { got = pooled(a, c.args, 0usize) }
        if str.eq(c.name, "pool_a") { got = pooled(a, c.args, 1usize) }
        if str.eq(c.name, "pool_b") { got = pooled(a, c.args, 2usize) }
        if str.eq(c.name, "pool_r2") { got = pooled(a, c.args, 3usize) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize { report(a, c, at, got) }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
