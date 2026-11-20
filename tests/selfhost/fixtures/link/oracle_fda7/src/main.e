// e.algo.stat.fdabase (Fourier smooth.fd and pca.fd) against fda. tests/oracle/fda7.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda7`; the layout is at the top of scripts/r_oracle/groups/fda7.R.

use e.algo.stat.fdabase as fb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nbs = usize(z[0usize])
    if c.name[0usize] == 68u8 {
        // D: (nbasis, period, m, lambda, nrep, index, coefs[nbasis nrep])
        let nrep = usize(z[4usize])
        let (o, e) = mem.alloc[f64](a, nbs * nrep)
        if e != ok { ret nan }
        if fb.smooth_fd_fourier(a, nbs, z[1usize], z[6usize..6usize + nbs * nrep], nrep, usize(z[2usize]), z[3usize], o) != ok { ret nan }
        ret o[usize(z[5usize])]
    }
    // F: (nbasis, period, nrep, m, lambda, index, which, coefs[nbasis nrep])
    let nrep = usize(z[2usize])
    let (vo, ve) = mem.alloc[f64](a, nbs)
    let (po, pe) = mem.alloc[f64](a, nbs)
    if ve != ok || pe != ok { ret nan }
    if fb.pca_fd_fourier(a, nbs, z[1usize], usize(z[3usize]), z[4usize], z[7usize..7usize + nbs * nrep], nrep, vo, po) != ok { ret nan }
    if z[6usize] == 0.0f64 { ret vo[usize(z[5usize])] }
    ret po[usize(z[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda7.json")
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
