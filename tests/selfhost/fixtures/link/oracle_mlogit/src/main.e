// e.algo.stat.mlogitpkg against mlogit. tests/oracle/mlogit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mlogit`; the layout is at the top of scripts/r_oracle/groups/mlogit.R.

use e.algo.rand.r as rr
use e.algo.stat.mlogitpkg as ml
use e.io
use e.math
use e.mem
use e.math.nmath as nm
use e.os
use e.str
use e.test.oracle as oracle

// R's model.matrix of the data gen(s, n, J, kx, kz) of the oracle: n rows of j alternatives of the constants (asc), x1..xkx, then for each z the alternatives 2..j
fn design(a: *mem.Arena, s: f64, n: usize, j: usize, kx: usize, kz: usize, asc: bool) -> ([]f64, usize) {
    var na = 0usize
    if asc { na = j - 1usize }
    let kk = na + kx + kz * (j - 1usize)
    let (xv, e1) = mem.alloc[f64](a, n * j * kx + n * kz + n * j * kk)
    if e1 != ok { ret (xv, 0usize) }
    var r: rr.Rng = zero
    rr.seed(&r, i64(s))
    var t = 0usize
    while t < n * j * kx + n * kz {
        xv[t] = rr.rnorm(&r, 0.0f64, 1.0f64)
        t += 1usize
    }
    let zv = xv[n * j * kx..n * j * kx + n * kz]
    let d = xv[n * j * kx + n * kz..n * j * kx + n * kz + n * j * kk]
    var i = 0usize
    while i < n {
        var jj = 0usize
        while jj < j {
            let row = d[(i * j + jj) * kk..(i * j + jj + 1usize) * kk]
            var c = 0usize
            while c < kk {
                row[c] = 0.0f64
                c += 1usize
            }
            if jj > 0usize && asc { row[jj - 1usize] = 1.0f64 }
            c = 0usize
            while c < kx {
                row[na + c] = xv[(i * j + jj) * kx + c]
                c += 1usize
            }
            if jj > 0usize {
                var l = 0usize
                while l < kz {
                    row[na + kx + l * (j - 1usize) + jj - 1usize] = zv[i * kz + l]
                    l += 1usize
                }
            }
            jj += 1usize
        }
        i += 1usize
    }
    ret (d, kk)
}

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var t = 0usize
    while t < v.len {
        s += v[t] * f64(t + 1usize)
        t += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.starts_with(c.name, "gl_") {
        var u: [40]f64 = zero
        var w: [40]f64 = zero
        ml.gauss_laguerre(40usize, u[0usize..40usize], w[0usize..40usize])
        if str.eq(c.name, "gl_node") { ret wsum(u[0usize..40usize]) }
        var t = 0usize
        while t < 40usize {
            w[t] = math.log[f64](w[t])
            t += 1usize
        }
        ret wsum(w[0usize..40usize])
    }
    let n = usize(z[1usize])
    let j = usize(z[2usize])
    let kx = usize(z[3usize])
    let kz = usize(z[4usize])
    let asc = z[5usize] > 0.5f64
    let ne = usize(z[6usize])
    let ex = z[7usize..7usize + ne]
    let chs = z[7usize + ne..7usize + ne + n]
    let (x, k) = design(a, z[0usize], n, j, kx, kz, asc)
    if k == 0usize { ret nan }
    var na = 0usize
    if asc { na = j - 1usize }
    if str.starts_with(c.name, "nl_") || str.starts_with(c.name, "hl_") || str.starts_with(c.name, "mx_") {
        var m: ml.Model = zero
        if str.starts_with(c.name, "nl_") {
            let nn = usize(ex[2usize])
            let (nest, ne2) = mem.alloc[usize](a, j)
            if ne2 != ok { ret nan }
            var t = 0usize
            while t < j {
                nest[t] = usize(ex[3usize + t])
                t += 1usize
            }
            let (m1, me) = ml.nested_model(a, x, chs, n, j, k, nest, nn)
            if me != ok { ret nan }
            m = m1
        } else if str.starts_with(c.name, "hl_") {
            let (m2, me) = ml.hetero_model(a, x, chs, n, j, k)
            if me != ok { ret nan }
            m = m2
        } else {
            let nr = usize(ex[2usize])
            let (ridx, re) = mem.alloc[usize](a, nr)
            if re != ok { ret nan }
            var t = 0usize
            while t < nr {
                ridx[t] = usize(ex[3usize + t])
                t += 1usize
            }
            let (m3, me) = ml.mixed_model(a, x, chs, n, j, k, usize(ex[0usize]), usize(ex[1usize]), ridx)
            if me != ok { ret nan }
            m = m3
        }
        let dim = ml.model_dim(&m)
        let (par, pe) = mem.alloc[f64](a, dim + n * j)
        if pe != ok { ret nan }
        let (ll, fe) = ml.fit_model(a, &m, par[0usize..dim])
        if fe != ok { ret nan }
        if str.ends_with(c.name, "_coef") { ret wsum(par[0usize..dim]) }
        if str.ends_with(c.name, "_ll") { ret ll }
        if str.ends_with(c.name, "_se") {
            if !ml.model_se(a, &m, par[0usize..dim], par[dim..dim + dim]) { ret nan }
            ret wsum(par[dim..dim + dim])
        }
        let prob = par[dim..dim + n * j]
        if str.ends_with(c.name, "_prob") {
            let _ = ml.model_ll(&m, par[0usize..dim], prob[0usize..0usize], prob)
            ret wsum(prob)
        }
        // nl_pred: the probabilities on the data gen(s2, n2, ...) at the estimates
        let n2 = usize(ex[1usize])
        let (x2, k2) = design(a, ex[0usize], n2, j, kx, kz, asc)
        let (c2, ce) = mem.alloc[f64](a, n2 + n2 * j)
        if k2 != k || ce != ok { ret nan }
        var t = 0usize
        while t < n2 {
            c2[t] = 0.0f64
            t += 1usize
        }
        let (mp, mpe) = ml.nested_model(a, x2, c2[0usize..n2], n2, j, k, m.nest, m.nn)
        if mpe != ok { ret nan }
        var mm = mp
        let _ = ml.model_ll(&mm, par[0usize..dim], c2[0usize..0usize], c2[n2..n2 + n2 * j])
        ret wsum(c2[n2..n2 + n2 * j])
    }
    let (out, e1) = mem.alloc[f64](a, 2usize * k + 1usize + j * j)
    if e1 != ok { ret nan }
    if ml.clogit(a, x, chs, n, j, k, false, out) != ok { ret nan }
    let cf = out[0usize..k]
    let mo = out[2usize * k + 1usize..2usize * k + 1usize + j * j]
    if str.eq(c.name, "coef") { ret wsum(cf) }
    if str.eq(c.name, "se") { ret wsum(out[k..2usize * k]) }
    if str.eq(c.name, "ll") { ret out[2usize * k] }
    if str.eq(c.name, "wald") || str.eq(c.name, "wald_p") {
        // the last coefficient (k = 1) or the last two
        let (wv, wve) = mem.alloc[f64](a, k * k)
        if wve != ok { ret nan }
        if !ml.clogit_vcov(a, x, n, j, k, false, cf, wv) { ret nan }
        var sel: [2]usize = zero
        var ns = 1usize
        sel[0usize] = k - 1usize
        if k >= 2usize {
            sel[0usize] = k - 2usize
            sel[1usize] = k - 1usize
            ns = 2usize
        }
        var wo: [2]f64 = zero
        if !ml.wald_test(a, cf, wv, k, sel[0usize..ns], wo[0usize..2usize]) { ret nan }
        if str.eq(c.name, "wald") { ret wo[0usize] }
        ret wo[1usize]
    }
    if str.eq(c.name, "shares") {
        ml.clogit_shares(x, n, j, k, false, cf, mo[0usize..j])
        ret wsum(mo[0usize..j])
    }
    if str.eq(c.name, "effects") {
        ml.clogit_effects(x, n, j, k, false, cf, na, mo)
        var s = 0.0f64
        var t = 0usize
        while t < j * j {
            s += mo[t] * f64(t + 1usize) * f64(t + 1usize)
            t += 1usize
        }
        ret s
    }
    if str.eq(c.name, "pred") {
        let n2 = usize(ex[1usize])
        let (x2, k2) = design(a, ex[0usize], n2, j, kx, kz, asc)
        let (p2, pe) = mem.alloc[f64](a, n2 * j)
        if k2 != k || pe != ok { ret nan }
        var i = 0usize
        while i < n2 {
            ml.clogit_probs(x2, i, j, k, false, cf, p2[i * j..i * j + j])
            i += 1usize
        }
        ret wsum(p2)
    }
    // lrt, lrt_p, score, score_p: the restricted model drops x_kx, design column na + kx - 1
    let drop = na + kx - 1usize
    let (xr, xe) = mem.alloc[f64](a, n * j * (k - 1usize) + 2usize * k + 1usize)
    if xe != ok { ret nan }
    var r = 0usize
    while r < n * j {
        var cc = 0usize
        var o = 0usize
        while cc < k {
            if cc != drop {
                xr[r * (k - 1usize) + o] = x[r * k + cc]
                o += 1usize
            }
            cc += 1usize
        }
        r += 1usize
    }
    let o0 = xr[n * j * (k - 1usize)..n * j * (k - 1usize) + 2usize * k + 1usize]
    if ml.clogit(a, xr[0usize..n * j * (k - 1usize)], chs, n, j, k - 1usize, false, o0) != ok { ret nan }
    if str.starts_with(c.name, "lrt") {
        let stat = 2.0f64 * (out[2usize * k] - o0[2usize * (k - 1usize)])
        if str.eq(c.name, "lrt") { ret stat }
        ret nm.pchisq(stat, 1.0f64, false, false)
    }
    // the restricted estimates with a zero for x_kx
    var t = 0usize
    var o = 0usize
    while t < k {
        mo[t] = 0.0f64
        if t != drop {
            mo[t] = o0[o]
            o += 1usize
        }
        t += 1usize
    }
    var so: [2]f64 = zero
    if !ml.clogit_score(a, x, chs, n, j, k, mo[0usize..k], 1usize, so[0usize..2usize]) { ret nan }
    if str.eq(c.name, "score") { ret so[0usize] }
    ret so[1usize]
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
                // the seed stands in for the arguments, which run to hundreds of choices
                let (initial, be) = str.builder(a, 96usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    let _ = str.push(&b, " seed ")
                    let _ = str.push_f64(&b, c.args[0usize])
                    let _ = str.push(&b, ": got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, ", R says ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
