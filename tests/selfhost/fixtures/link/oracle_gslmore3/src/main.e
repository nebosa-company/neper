// e.algo.stat.gslwrap and the real sn_cn_dn against gsl. tests/oracle/gslmore3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslmore3`; the layout of each case is at the top of scripts/r_oracle/groups/gslmore3.R.

use e.algo.stat.gslfns as gs
use e.algo.stat.gslwrap as gw
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn grab(a: *mem.Arena, n: usize) -> []f64 {
    let (p, g) = mem.alloc[f64](a, n)
    if g != ok { os.exit(4) }
    ret p
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let code = usize(x[0usize])
    if code <= 2usize {
        let out = grab(a, 3usize)
        let em = grab(a, 40usize)
        let en = grab(a, 40usize)
        gs.elljac(x[1usize], x[2usize], out, em, en)
        ret out[code]
    }
    if code == 3usize {
        let r = gw.strictify(x[1usize], i64(x[2usize]))
        if r != r { ret -999.0f64 }
        ret r
    }
    if code == 4usize {
        if gw.legendre_check_args(x[1usize], x[2usize], x[3usize]) { ret 1.0f64 }
        ret 0.0f64
    }
    if code == 5usize { ret gw.text_checksum(gw.deprecated_legendre()) }
    ret f64(gw.deprecated_legendre().len)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslmore3.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
