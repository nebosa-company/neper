// e.algo.stat.fdabase against fda. tests/oracle/fda5.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda5`; the layout is at the top of scripts/r_oracle/groups/fda5.R.

use e.algo.stat.fdabase as fb
use e.algo.stat.fdapkg as fa
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let k = c.name[0usize]
    if k == 109u8 {
        // m: (nbasis, lo, hi, deriv, x, j, exponents[nbasis])
        ret fa.eval_monomial(z[6usize + usize(z[5usize])], z[4usize], usize(z[3usize]))
    }
    if k == 120u8 {
        // x: (nbasis, lo, hi, deriv, x, j, rates[nbasis])
        ret fa.eval_exponential(z[6usize + usize(z[5usize])], z[4usize], usize(z[3usize]))
    }
    if k == 121u8 {
        // y: (n, deriv, x, j, argvals[n])
        let n = usize(z[0usize])
        let (o, e) = mem.alloc[f64](a, n + 2usize)
        if e != ok { ret nan }
        if fa.eval_polygonal(a, z[4usize..4usize + n], z[2usize], o) != ok { ret nan }
        ret o[usize(z[3usize])]
    }
    if k == 107u8 {
        // k: (deriv, x) the constant basis: fda's eval.basis answers 1 for every derivative order
        ret 1.0f64
    }
    if k == 115u8 {
        // s: (nbasis, period, m, lambda, q, nd, x[nd], y[nd])
        let nbs = usize(z[0usize])
        let nd = usize(z[5usize])
        let (co, ce) = mem.alloc[f64](a, nbs)
        if ce != ok { ret nan }
        if fb.smooth_fourier(a, nbs, z[1usize], z[6usize..6usize + nd], z[6usize + nd..6usize + 2usize * nd], usize(z[2usize]), z[3usize], co) != ok { ret nan }
        ret co[usize(z[4usize])]
    }
    if k == 119u8 {
        // w: (nbasis, period, deriv, x, coefs[nbasis])
        let nbs = usize(z[0usize])
        ret fb.eval_fd_fourier(a, nbs, z[1usize], z[4usize..4usize + nbs], z[3usize], usize(z[2usize]))
    }
    let norder = usize(z[0usize])
    let nb = usize(z[1usize])
    let nbas = nb + norder - 2usize
    if k == 81u8 {
        // Q: (norder, nb, nrep, m, lambda, index, which, breaks[nb], coefs[nbasis nrep])
        let nrep = usize(z[2usize])
        let (vo, ve) = mem.alloc[f64](a, nbas)
        let (po, pe) = mem.alloc[f64](a, nbas)
        if ve != ok || pe != ok { ret nan }
        if fb.pca_fd_smooth(a, norder, z[7usize..7usize + nb], usize(z[3usize]), z[4usize], z[7usize + nb..7usize + nb + nbas * nrep], nrep, vo, po) != ok { ret nan }
        if z[6usize] == 0.0f64 { ret vo[usize(z[5usize])] }
        ret po[usize(z[5usize])]
    }
    // M: (norder, nb, N, nf, nz, index, lambdas[nf], breaks[nb], xcoefs[nf nbasis N], zs[nz N], y[N])
    let nobs = usize(z[2usize])
    let nf = usize(z[3usize])
    let nz = usize(z[4usize])
    let b0 = 6usize + nf
    let x0 = b0 + nb
    let z0 = x0 + nf * nbas * nobs
    let y0 = z0 + nz * nobs
    let (ro, re) = mem.alloc[f64](a, 1usize + nz + nf * nbas)
    if re != ok { ret nan }
    if fb.fregress_multi(a, norder, z[b0..b0 + nb], nf, nz, z[x0..z0], z[z0..y0], nobs, z[y0..y0 + nobs], z[6usize..6usize + nf], ro) != ok { ret nan }
    ret ro[usize(z[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda5.json")
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
