// e.algo.linalg.decomp and e.algo.linalg.matrix against R's base: qr (LINPACK, limited pivoting),
// lm.fit, svd, eigen of a general matrix, chol, det, solve and an LDL' from chol.
// tests/oracle/decomp.json comes from `Rscript scripts/r_oracle/generate.R decomp`; the layouts are
// at the top of scripts/r_oracle/groups/decomp.R. A vector answer is one case per element (the last
// argument is the position) plus a "len:" case. Singular and eigen vectors are compared in absolute
// value (svd) or by their residual (eigen), a computed eigenvalue by its distance to R's.

use e.algo.linalg.decomp as dc
use e.algo.linalg.matrix as mx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pick(r: []const f64, c: *const oracle.Case, wants_len: bool) -> f64 {
    if wants_len { ret f64(r.len) }
    let i = usize(c.args[c.args.len - 1usize])
    if i < r.len { ret r[i] }
    ret nan()
}

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn pos_to_f64(a: *mem.Arena, p: []const usize) -> []f64 {
    let (r, e) = mem.alloc[f64](a, p.len + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < p.len {
        r[i] = f64(p[i])
        i += 1usize
    }
    ret r[0usize..p.len]
}

fn abs_all(a: *mem.Arena, x: []const f64) -> []f64 {
    let (r, e) = mem.alloc[f64](a, x.len + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < x.len {
        r[i] = abs_of(x[i])
        i += 1usize
    }
    ret r[0usize..x.len]
}

// A row-major copy of a column-major n by n matrix, for e.algo.linalg.matrix.
fn row_major(a: *mem.Arena, x: []const f64, n: usize) -> []f64 {
    let (r, e) = mem.alloc[f64](a, n * n + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            r[i * n + j] = x[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    ret r[0usize..n * n]
}

// The largest residual |A v - lambda v| over the computed eigenpairs, scaled by 1 + |lambda|.
fn eigen_residual(a: *mem.Arena, x: []const f64, n: usize) -> f64 {
    let (ev, e) = dc.eigen(a, x, n)
    if e != ok { os.exit(72) }
    var worst = 0.0f64
    var k = 0usize
    while k < n {
        var i = 0usize
        while i < n {
            var sr = 0.0f64
            var si = 0.0f64
            var j = 0usize
            while j < n {
                sr = sr + x[j * n + i] * ev.vre[k * n + j]
                si = si + x[j * n + i] * ev.vim[k * n + j]
                j += 1usize
            }
            let dr = sr - (ev.re[k] * ev.vre[k * n + i] - ev.im[k] * ev.vim[k * n + i])
            let di = si - (ev.re[k] * ev.vim[k * n + i] + ev.im[k] * ev.vre[k * n + i])
            let res = dc.cabs(dr, di) / (1.0f64 + dc.cabs(ev.re[k], ev.im[k]))
            if res > worst { worst = res }
            i += 1usize
        }
        k += 1usize
    }
    ret worst
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    var name = c.name
    var wants_len = false
    if name.len > 4usize && name[0usize] == 108u8 && name[1usize] == 101u8 && name[2usize] == 110u8 && name[3usize] == 58u8 {
        name = name[4usize..name.len]
        wants_len = true
    } else if name.len > 2usize && name[1usize] == 58u8 {
        name = name[2usize..name.len]
    }
    let x = c.args
    if str.starts_with(name, "qr_") || str.starts_with(name, "lmfit_") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let m = x[2usize..2usize + n * p]
        if str.starts_with(name, "qr_") {
            let (f, e) = dc.qr(a, m, n, p, 0.0000001f64)
            if e != ok { os.exit(7) }
            if str.eq(name, "qr_qr") { ret pick(f.qr[0usize..n * f.rank], c, wants_len) }
            if str.eq(name, "qr_aux") { ret pick(f.qraux[0usize..f.rank], c, wants_len) }
            if str.eq(name, "qr_pivot") { ret pick(pos_to_f64(a, f.pivot[0usize..p]), c, wants_len) }
            ret f64(f.rank)
        }
        let (fit, e) = dc.lm_fit(a, m, n, p, x[2usize + n * p..2usize + n * p + n], 0.0000001f64)
        if e != ok { os.exit(74) }
        if str.eq(name, "lmfit_coef") { ret pick(fit.coef, c, wants_len) }
        if str.eq(name, "lmfit_res") { ret pick(fit.residuals, c, wants_len) }
        ret pick(fit.effects, c, wants_len)
    }
    if str.starts_with(name, "svd_") {
        let m = usize(x[0usize])
        let n = usize(x[1usize])
        let (s, e) = dc.svd(a, x[2usize..2usize + m * n], m, n)
        if e != ok { os.exit(71) }
        if str.eq(name, "svd_d") { ret pick(s.d, c, wants_len) }
        if str.eq(name, "svd_u") { ret pick(abs_all(a, s.u), c, wants_len) }
        ret pick(abs_all(a, s.v), c, wants_len)
    }
    if str.eq(name, "eig_resid") {
        let n = usize(x[0usize])
        ret eigen_residual(a, x[1usize..1usize + n * n], n)
    }
    if str.eq(name, "eig_match") {
        let n = usize(x[0usize])
        let (ev, e) = dc.eigen(a, x[1usize..1usize + n * n], n)
        if e != ok {
            var q = 0usize
            while q < x.len {
                let (b0, be) = str.builder(a, 32usize)
                var bb = b0
                let _ = str.push_f64(&bb, x[q])
                let _ = io.print(str.done(&bb))
                let _ = io.print(" ")
                q += 1usize
            }
            os.exit(75)
        }
        let re = x[x.len - 2usize]
        let im = x[x.len - 1usize]
        var best = 1.0e300f64
        var k = 0usize
        while k < n {
            let d = dc.cabs(ev.re[k] - re, ev.im[k] - im) / (1.0f64 + dc.cabs(re, im))
            if d < best { best = d }
            k += 1usize
        }
        ret best
    }
    // linear algebra on (n, matrix, b..., [position])
    let n = usize(x[0usize])
    let m = x[1usize..1usize + n * n]
    let b = x[1usize + n * n..1usize + n * n + n]
    if str.eq(name, "ldlt_l") || str.eq(name, "ldlt_d") {
        let (f, e) = dc.ldlt(a, m, n)
        if e != ok { os.exit(73) }
        if str.eq(name, "ldlt_l") { ret pick(f.l, c, wants_len) }
        ret pick(f.d, c, wants_len)
    }
    let rm = row_major(a, m, n)
    let (cm, ce) = mx.view_const[f64](rm, n, n, n)
    if ce != ok { os.exit(8) }
    if str.eq(name, "det") || str.eq(name, "det_gen") {
        let (d, e) = mx.determinant_f64(a, cm)
        if e != ok { os.exit(9) }
        ret d
    }
    if str.eq(name, "chol") {
        let (lbuf, le) = mem.alloc[f64](a, n * n + 1usize)
        if le != ok { os.exit(5) }
        let (lm, lme) = mx.view[f64](lbuf[0usize..n * n], n, n, n)
        if lme != ok { os.exit(8) }
        let e = mx.cholesky(lm, cm)
        if e != ok { os.exit(9) }
        // R's upper factor, column-major: R[i, j] = L[j, i]
        let (r, re) = mem.alloc[f64](a, n * n + 1usize)
        if re != ok { os.exit(5) }
        var j = 0usize
        while j < n {
            var i = 0usize
            while i < n {
                if i <= j { r[j * n + i] = lbuf[j * n + i] } else { r[j * n + i] = 0.0f64 }
                i += 1usize
            }
            j += 1usize
        }
        ret pick(r[0usize..n * n], c, wants_len)
    }
    // solve(A, b) through the inverse
    let (ibuf, ie) = mem.alloc[f64](a, n * n + 1usize)
    if ie != ok { os.exit(5) }
    let (im, ime) = mx.view[f64](ibuf[0usize..n * n], n, n, n)
    if ime != ok { os.exit(8) }
    let e = mx.inverse_f64(a, im, cm)
    if e != ok { os.exit(9) }
    let (sol, se) = mem.alloc[f64](a, n + 1usize)
    if se != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s = s + ibuf[i * n + j] * b[j]
            j += 1usize
        }
        sol[i] = s
        i += 1usize
    }
    ret pick(sol[0usize..n], c, wants_len)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/decomp.json")
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
            if failures <= 20usize {
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
