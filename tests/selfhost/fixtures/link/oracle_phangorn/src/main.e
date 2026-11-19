// e.algo.stat.phangornpkg's Fitch parsimony against phangorn::parsimony. tests/oracle/phangorn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R phangorn`; the layout is at the top of scripts/r_oracle/groups/phangorn.R.

use e.algo.stat.phangornpkg as pg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if c.name.len == 4usize {
        let nt = usize(z[1usize])
        let ns = usize(z[2usize])
        ret pg.hamming(z[5usize..5usize + nt * ns], ns, usize(z[3usize]), usize(z[4usize]), z[0usize] > 0.5f64)
    }
    if c.name.len == 3usize {
        let nn = usize(z[1usize])
        let (o, oe) = mem.alloc[f64](a, nn)
        if oe != ok { ret 0.0f64 / 0.0f64 }
        if pg.upgma(a, z[3usize..3usize + nn * nn], nn, z[0usize] > 0.5f64, o) != ok { ret 0.0f64 / 0.0f64 }
        ret o[usize(z[2usize])]
    }
    let nt = usize(z[0usize])
    let ns = usize(z[1usize])
    let ne = usize(z[2usize])
    if c.name.len == 10usize {
        let o = 3usize + 3usize * ne
        ret pg.gtr_loglik_gamma(a, z[3usize..3usize + ne], z[3usize + ne..3usize + 2usize * ne], z[3usize + 2usize * ne..o], ne, nt, z[o + 12usize..o + 12usize + nt * ns], ns, z[o..o + 4usize], z[o + 4usize..o + 10usize], z[o + 10usize], usize(z[o + 11usize]))
    }
    if c.name.len == 9usize {
        let o = 3usize + 3usize * ne
        ret pg.gtr_loglik(a, z[3usize..3usize + ne], z[3usize + ne..3usize + 2usize * ne], z[3usize + 2usize * ne..o], ne, nt, z[o + 10usize..o + 10usize + nt * ns], ns, z[o..o + 4usize], z[o + 4usize..o + 10usize])
    }
    if c.name.len == 8usize {
        ret pg.jc_loglik(a, z[3usize..3usize + ne], z[3usize + ne..3usize + 2usize * ne], z[3usize + 2usize * ne..3usize + 3usize * ne], ne, nt, z[3usize + 3usize * ne..3usize + 3usize * ne + nt * ns], ns)
    }
    if c.name.len == 7usize {
        ret pg.sankoff(a, z[3usize..3usize + ne], z[3usize + ne..3usize + 2usize * ne], ne, nt, z[3usize + 2usize * ne + 16usize..3usize + 2usize * ne + 16usize + nt * ns], ns, z[3usize + 2usize * ne..3usize + 2usize * ne + 16usize])
    }
    ret pg.fitch(a, z[3usize..3usize + ne], z[3usize + ne..3usize + 2usize * ne], ne, nt, z[3usize + 2usize * ne..3usize + 2usize * ne + nt * ns], ns)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/phangorn.json")
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
