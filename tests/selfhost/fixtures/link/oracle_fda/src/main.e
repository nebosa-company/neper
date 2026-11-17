// e.algo.stat.fdapkg against fda. tests/oracle/fda.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda`; the layout is at the top of scripts/r_oracle/groups/fda.R.

use e.algo.stat.fdapkg as fa
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if c.name[0usize] == 102u8 {
        // f: (nbasis, period, deriv, x, j)
        let (fo, fe) = mem.alloc[f64](a, usize(z[0usize]))
        if fe != ok { ret nan }
        fa.eval_fourier(usize(z[0usize]), z[1usize], z[3usize], usize(z[2usize]), fo)
        ret fo[usize(z[4usize])]
    }
    let norder = usize(z[0usize])
    let nb = usize(z[1usize])
    if c.name[0usize] == 113u8 {
        // q (pca.fd): (norder, nb, nrep, index, which (0 value, 1 varprop), breaks[nb], coefs[nbasis nrep])
        let nbas = nb + norder - 2usize
        let nrep = usize(z[2usize])
        let (gm, ge) = mem.alloc[f64](a, nbas * nbas)
        let (vo, ve) = mem.alloc[f64](a, nbas)
        let (po, pe) = mem.alloc[f64](a, nbas)
        if ge != ok || ve != ok || pe != ok { ret nan }
        if fa.penalty_matrix(a, norder, z[5usize..5usize + nb], 0usize, gm) != ok { ret nan }
        let (jm, je) = mem.alloc[f64](a, nbas * nbas)
        if je != ok { ret nan }
        if fa.inprod_romberg(a, norder, z[5usize..5usize + nb], jm) != ok { ret nan }
        if fa.pca_fd_values(a, gm, jm, z[5usize + nb..5usize + nb + nbas * nrep], nbas, nrep, vo, po) != ok { ret nan }
        if z[4usize] == 0.0f64 { ret vo[usize(z[3usize])] }
        ret po[usize(z[3usize])]
    }
    if c.name[0usize] == 103u8 {
        // g: (norder, nb, m, lambda, which (0 df, 1 sse, 2 gcv, 3 + q coefficient q), hasw, nd, breaks[nb], argvals[nd], y[nd], w[nd])
        let nbas = nb + norder - 2usize
        let nd = usize(z[6usize])
        let (co, ce) = mem.alloc[f64](a, nbas)
        let (so, se) = mem.alloc[f64](a, 3usize)
        if ce != ok || se != ok { ret nan }
        var wv = z[7usize + nb + 2usize * nd..7usize + nb + 2usize * nd]
        if z[5usize] != 0.0f64 { wv = z[7usize + nb + 2usize * nd..7usize + nb + 3usize * nd] }
        if fa.smooth_basis_stats(a, norder, z[7usize..7usize + nb], z[7usize + nb..7usize + nb + nd], z[7usize + nb + nd..7usize + nb + 2usize * nd], wv, usize(z[2usize]), z[3usize], co, so) != ok { ret nan }
        let w = usize(z[4usize])
        if w < 3usize { ret so[w] }
        ret co[w - 3usize]
    }
    if c.name[0usize] == 112u8 {
        // pen: (norder, nb, m, index, breaks)
        let nbas = nb + norder - 2usize
        let (po, pe) = mem.alloc[f64](a, nbas * nbas)
        if pe != ok { ret nan }
        if fa.penalty_matrix(a, norder, z[4usize..4usize + nb], usize(z[2usize]), po) != ok { ret nan }
        ret po[usize(z[3usize])]
    }
    if c.name[0usize] == 115u8 {
        // sm: (norder, nb, m, lambda, index, nd, breaks[nb], argvals[nd], y[nd])
        let nbas = nb + norder - 2usize
        let nd = usize(z[5usize])
        let (co, ce) = mem.alloc[f64](a, nbas)
        if ce != ok { ret nan }
        if fa.smooth_basis(a, norder, z[6usize..6usize + nb], z[6usize + nb..6usize + nb + nd], z[6usize + nb + nd..6usize + nb + 2usize * nd], usize(z[2usize]), z[3usize], co) != ok { ret nan }
        ret co[usize(z[4usize])]
    }
    let (o, e) = mem.alloc[f64](a, nb + norder)
    if e != ok { ret nan }
    if fa.eval_bspline(a, norder, z[5usize..5usize + nb], z[3usize], usize(z[2usize]), o) != ok { ret nan }
    ret o[usize(z[4usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda.json")
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
