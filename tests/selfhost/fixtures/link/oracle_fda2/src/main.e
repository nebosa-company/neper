// e.algo.stat.fdareg against fda. tests/oracle/fda2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda2`; the layout is at the top of scripts/r_oracle/groups/fda2.R.

use e.algo.stat.fdapkg as fa
use e.algo.stat.fdareg as fr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = c.name[0usize]
    if kind == 122u8 {
        // z: (k, row, col)
        let k = usize(z[0usize])
        let (o, e) = mem.alloc[f64](a, k * k)
        if e != ok { ret nan }
        if fr.zero_basis(a, k, o) != ok { ret nan }
        ret o[usize(z[2usize]) * k + usize(z[1usize])]
    }
    if kind == 110u8 {
        // n: (norder, m, index, lo, hi): the penalty of a basis with no interior knots
        let norder = usize(z[0usize])
        let (o, e) = mem.alloc[f64](a, norder * norder)
        if e != ok { ret nan }
        if fa.penalty_matrix(a, norder, z[3usize..5usize], usize(z[1usize]), o) != ok { ret nan }
        ret o[usize(z[2usize])]
    }
    if kind == 98u8 {
        // b: (norder, deriv, x, j, lo, hi): a basis with no interior knots
        let norder = usize(z[0usize])
        let (o, e) = mem.alloc[f64](a, norder + 2usize)
        if e != ok { ret nan }
        if fa.eval_bspline(a, norder, z[4usize..6usize], z[2usize], usize(z[1usize]), o) != ok { ret nan }
        ret o[usize(z[3usize])]
    }
    let norder = usize(z[0usize])
    let nb = usize(z[1usize])
    let nbas = nb + norder - 2usize
    if kind == 100u8 {
        // d: (norder, nb, m, index, breaks[nb], coefs[nbasis])
        let (o, e) = mem.alloc[f64](a, nbas)
        if e != ok { ret nan }
        if fr.deriv_fd(a, norder, z[4usize..4usize + nb], z[4usize + nb..4usize + nb + nbas], usize(z[2usize]), o) != ok { ret nan }
        ret o[usize(z[3usize])]
    }
    if kind == 115u8 {
        // s: (norder, nb, m, lambda, nrep, index, breaks[nb], coefs[nbasis nrep])
        let nrep = usize(z[4usize])
        let (o, e) = mem.alloc[f64](a, nbas * nrep)
        if e != ok { ret nan }
        if fr.smooth_fd(a, norder, z[6usize..6usize + nb], z[6usize + nb..6usize + nb + nbas * nrep], nrep, usize(z[2usize]), z[3usize], o) != ok { ret nan }
        ret o[usize(z[5usize])]
    }
    if kind == 102u8 {
        // f: (norder, nb, x, breaks[nb], coefs[nbasis])
        ret fr.eval_monfd(a, norder, z[3usize..3usize + nb], z[3usize + nb..3usize + nb + nbas], z[2usize], 0usize)
    }
    if kind == 101u8 {
        // e: (norder, nb, x, deriv, breaks[nb], coefs[nbasis])
        ret fr.eval_monfd(a, norder, z[4usize..4usize + nb], z[4usize + nb..4usize + nb + nbas], z[2usize], usize(z[3usize]))
    }
    // g: (norder, nb, x, k, breaks[nb], coefs[nbasis])
    let (xs, e1) = mem.alloc[f64](a, 1usize)
    let (o, e2) = mem.alloc[f64](a, nbas)
    if e1 != ok || e2 != ok { ret nan }
    xs[0usize] = z[2usize]
    if fr.mon_eval(a, norder, z[4usize..4usize + nb], z[4usize + nb..4usize + nb + nbas], xs, true, o) != ok { ret nan }
    ret o[usize(z[3usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let (seen, se) = mem.alloc[usize](a, 256usize)
    if se != ok { os.exit(4) }
    var s0 = 0usize
    while s0 < 256usize {
        seen[s0] = 0usize
        s0 += 1usize
    }
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            let kind = usize(c.name[0usize])
            seen[kind] += 1usize
            if seen[kind] <= 2usize {
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
