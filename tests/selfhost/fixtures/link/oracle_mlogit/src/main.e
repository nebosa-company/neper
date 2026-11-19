// e.algo.stat.mlogitpkg against mlogit conditional logit. tests/oracle/mlogit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mlogit`; the layout is at the top of scripts/r_oracle/groups/mlogit.R.

use e.algo.stat.mlogitpkg as ml
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.starts_with(c.name, "mnl_") {
        let mn = usize(z[0usize])
        let mj = usize(z[1usize])
        let mq = usize(z[2usize])
        let kk = (mj - 1usize) * mq
        let (dx, de) = mem.alloc[f64](a, mn * mj * kk)
        let (mo, me) = mem.alloc[f64](a, 2usize * (mj - 1usize + kk) + 1usize)
        if de != ok || me != ok { ret nan }
        var i = 0usize
        while i < mn * mj * kk {
            dx[i] = 0.0f64
            i += 1usize
        }
        // X[i][j][(j - 1) q + l] = z[i][l] for alternatives j >= 1
        i = 0usize
        while i < mn {
            var jj = 1usize
            while jj < mj {
                var l = 0usize
                while l < mq {
                    dx[(i * mj + jj) * kk + (jj - 1usize) * mq + l] = z[3usize + mn + i * mq + l]
                    l += 1usize
                }
                jj += 1usize
            }
            i += 1usize
        }
        if ml.clogit(a, dx, z[3usize..3usize + mn], mn, mj, kk, true, mo) != ok { ret nan }
        let qn = mj - 1usize + kk
        if str.eq(c.name, "mnl_ll") { ret mo[2usize * qn] }
        var lo2 = 0usize
        if str.eq(c.name, "mnl_se") { lo2 = qn }
        var s2 = 0.0f64
        var t = 0usize
        while t < qn {
            s2 += mo[lo2 + t] * f64(t + 1usize)
            t += 1usize
        }
        ret s2
    }
    let n = usize(z[0usize])
    let j = usize(z[1usize])
    let k = usize(z[2usize])
    let asc = z[3usize] > 0.5f64
    var q = k
    if asc { q = j - 1usize + k }
    let (out, e1) = mem.alloc[f64](a, 2usize * q + 1usize)
    if e1 != ok { ret nan }
    if ml.clogit(a, z[4usize + n..4usize + n + n * j * k], z[4usize..4usize + n], n, j, k, asc, out) != ok { ret nan }
    if str.eq(c.name, "shares") || str.eq(c.name, "effects") {
        let xs = z[4usize + n..4usize + n + n * j * k]
        let (mo, me) = mem.alloc[f64](a, j * j)
        if me != ok { ret nan }
        var ws = 0.0f64
        if str.eq(c.name, "shares") {
            ml.clogit_shares(xs, n, j, k, asc, out[0usize..q], mo[0usize..j])
            var t = 0usize
            while t < j {
                ws += mo[t] * f64(t + 1usize)
                t += 1usize
            }
            ret ws
        }
        ml.clogit_effects(xs, n, j, k, asc, out[0usize..q], 0usize, mo)
        var t2 = 0usize
        while t2 < j * j {
            ws += mo[t2] * f64(t2 + 1usize)
            t2 += 1usize
        }
        ret ws
    }
    if str.eq(c.name, "ll") { ret out[2usize * q] }
    var lo = 0usize
    if str.eq(c.name, "se") { lo = q }
    var s = 0.0f64
    var i = 0usize
    while i < q {
        s += out[lo + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mlogit.json")
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
