// e.algo.stat.mlogitpkg against mlogit conditional logit. tests/oracle/mlogit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mlogit`; the layout is at the top of scripts/r_oracle/groups/mlogit.R.

use e.algo.stat.mlogitpkg as ml
use e.io
use e.mem
use e.math.nmath as nm
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.starts_with(c.name, "nl_") {
        let n = usize(z[0usize])
        let j = usize(z[1usize])
        let k = usize(z[2usize])
        let asc = z[3usize] > 0.5f64
        let nn = usize(z[4usize])
        let (nest, ne) = mem.alloc[usize](a, j)
        let (out, oe) = mem.alloc[f64](a, 2usize * j + 2usize * k + 4usize)
        if ne != ok || oe != ok { ret nan }
        var t = 0usize
        while t < j {
            nest[t] = usize(z[5usize + t])
            t += 1usize
        }
        let chs = z[5usize + j..5usize + j + n]
        let xs = z[5usize + j + n..5usize + j + n + n * j * k]
        var q = k
        if asc { q = j - 1usize + k }
        if ml.nested_logit(a, xs, chs, n, j, k, asc, nest, nn, out) != ok { ret nan }
        var nl = 0usize
        var m = 0usize
        while m < nn {
            var cnt = 0usize
            t = 0usize
            while t < j {
                if nest[t] == m { cnt += 1usize }
                t += 1usize
            }
            if cnt > 1usize { nl += 1usize }
            m += 1usize
        }
        if str.eq(c.name, "nl_ll") { ret out[q + nl] }
        if str.eq(c.name, "nl_se") {
            let (nse, nee) = mem.alloc[f64](a, q + nl)
            if nee != ok { ret nan }
            if !ml.nested_se(a, xs, chs, n, j, k, asc, nest, nn, out[0usize..q + nl], nse) { ret nan }
            var ss = 0.0f64
            t = 0usize
            while t < q + nl {
                ss += nse[t] * f64(t + 1usize)
                t += 1usize
            }
            ret ss
        }
        var lo = 0usize
        var hi = q
        if str.eq(c.name, "nl_iv") {
            lo = q
            hi = q + nl
        }
        var s = 0.0f64
        t = lo
        while t < hi {
            s += out[t] * f64(t - lo + 1usize)
            t += 1usize
        }
        ret s
    }
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
    if str.eq(c.name, "wald") || str.eq(c.name, "wald_p") {
        // the Wald test of the last covariate (k = 1) or of the last two (k >= 2)
        let wx = z[4usize + n..4usize + n + n * j * k]
        let (wv, wve) = mem.alloc[f64](a, q * q)
        if wve != ok { ret nan }
        if !ml.clogit_vcov(a, wx, n, j, k, asc, out[0usize..q], wv) { ret nan }
        var sel: [2]usize = zero
        var ns = 1usize
        sel[0usize] = q - 1usize
        if k >= 2usize {
            sel[0usize] = q - 2usize
            sel[1usize] = q - 1usize
            ns = 2usize
        }
        var wo: [2]f64 = zero
        if !ml.wald_test(a, out[0usize..q], wv, q, sel[0usize..ns], wo[0usize..2usize]) { ret nan }
        if str.eq(c.name, "wald") { ret wo[0usize] }
        ret wo[1usize]
    }
    if str.eq(c.name, "lrt") || str.eq(c.name, "lrt_p") {
        // drop the last covariate: the model on the first k - 1 columns of x
        let (xr, xe) = mem.alloc[f64](a, n * j * (k - 1usize))
        let (o0, oe) = mem.alloc[f64](a, 2usize * (q - 1usize) + 1usize)
        if xe != ok || oe != ok { ret nan }
        var ii = 0usize
        while ii < n * j {
            var cc = 0usize
            while cc + 1usize < k {
                xr[ii * (k - 1usize) + cc] = z[4usize + n + ii * k + cc]
                cc += 1usize
            }
            ii += 1usize
        }
        if ml.clogit(a, xr, z[4usize..4usize + n], n, j, k - 1usize, asc, o0) != ok { ret nan }
        let stat = 2.0f64 * (out[2usize * q] - o0[2usize * (q - 1usize)])
        if str.eq(c.name, "lrt") { ret stat }
        ret nm.pchisq(stat, 1.0f64, false, false)
    }
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
