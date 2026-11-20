// e.algo.stat.fdagen against fda. tests/oracle/fda8.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda8`; the layout is at the top of scripts/r_oracle/groups/fda8.R.

use e.algo.stat.fdagen as fg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let k = c.name[0usize]
    let kind = usize(z[0usize])
    let nb = usize(z[1usize])
    if k == 112u8 {
        // p: (kind, nbasis, nrep, lo, hi, index, which, par[nbasis], coefs[nbasis nrep])
        let nrep = usize(z[2usize])
        let (vo, ve) = mem.alloc[f64](a, nb)
        let (po, pe) = mem.alloc[f64](a, nb)
        if ve != ok || pe != ok { ret nan }
        if fg.pca_fd_gen(a, kind, z[7usize..7usize + nb], nb, z[3usize], z[4usize], z[7usize + nb..7usize + nb + nb * nrep], nrep, vo, po) != ok { ret nan }
        if z[6usize] == 0.0f64 { ret vo[usize(z[5usize])] }
        ret po[usize(z[5usize])]
    }
    let lo = z[2usize]
    let hi = z[3usize]
    let par = z[6usize..6usize + nb]
    let cf = z[6usize + nb..6usize + 2usize * nb]
    if k == 101u8 {
        // e: (kind, nbasis, lo, hi, nd, x, par, coefs)
        ret fg.eval_fd_gen(a, kind, hi - lo, par, nb, cf, z[5usize], usize(z[4usize]))
    }
    // d: (kind, nbasis, lo, hi, nd, index, par, coefs)
    let (o, e) = mem.alloc[f64](a, nb)
    if e != ok { ret nan }
    if fg.deriv_fd_gen(a, kind, hi - lo, par, nb, lo, hi, cf, usize(z[4usize]), o) != ok { ret nan }
    ret o[usize(z[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda8.json")
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
