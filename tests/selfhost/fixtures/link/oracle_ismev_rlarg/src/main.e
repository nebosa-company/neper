// e.algo.stat.ismev rlarg.fit against ismev. tests/oracle/ismev_rlarg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ismev_rlarg`; the layout is at the top of scripts/r_oracle/groups/ismev_rlarg.R.

use e.algo.stat.ismev as im
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "cr") {
        let n = usize(x[0usize])
        let r = usize(x[1usize])
        let qm = usize(x[2usize])
        let qs = usize(x[3usize])
        let qx = usize(x[4usize])
        let nd = n * (qm + qs + qx)
        let (g, ge) = im.fit_rlarg_cov(a, x[9usize + nd..9usize + nd + n * r], n, r, x[9usize..9usize + nd], qm, qs, qx, usize(x[5usize]), usize(x[6usize]), usize(x[7usize]))
        if ge != ok { os.exit(10) }
        let w = usize(x[8usize])
        if w == 999usize { ret g.nllh }
        if w >= 100usize { ret g.se[w - 100usize] }
        ret g.par[w]
    }
    if str.eq(c.name, "cp") {
        let n = usize(x[0usize])
        let qm = usize(x[3usize])
        let qs = usize(x[4usize])
        let qx = usize(x[5usize])
        let nd = n * (qm + qs + qx)
        let (g, ge) = im.fit_pp_cov(a, x[10usize + nd..10usize + nd + n], x[2usize], usize(x[1usize]), x[10usize..10usize + nd], qm, qs, qx, usize(x[6usize]), usize(x[7usize]), usize(x[8usize]))
        if ge != ok { os.exit(11) }
        let w = usize(x[9usize])
        if w == 999usize { ret g.nllh }
        if w >= 100usize { ret g.se[w - 100usize] }
        ret g.par[w]
    }
    if str.eq(c.name, "cv") {
        let n = usize(x[0usize])
        let qm = usize(x[1usize])
        let qs = usize(x[2usize])
        let qx = usize(x[3usize])
        let nd = n * (qm + qs + qx)
        let (g, ge) = im.fit_cov(a, x[8usize + nd..8usize + nd + n], x[8usize..8usize + nd], qm, qs, qx, usize(x[4usize]), usize(x[5usize]), usize(x[6usize]))
        if ge != ok { os.exit(9) }
        let w = usize(x[7usize])
        if w == 999usize { ret g.nllh }
        if w >= 100usize { ret g.se[w - 100usize] }
        ret g.par[w]
    }
    if str.eq(c.name, "pr") {
        let kind = usize(x[0usize])
        let n = usize(x[1usize])
        let nint = usize(x[5usize])
        let (out, oe) = mem.alloc[f64](a, nint)
        if oe != ok { os.exit(7) }
        var pe = ok
        if kind == 0usize {
            pe = im.gev_profile(a, x[9usize..9usize + n], x[2usize], x[3usize], x[4usize], nint, out)
        } else {
            pe = im.gpd_profile(a, x[9usize..9usize + n], x[6usize], x[2usize], x[7usize], x[3usize], x[4usize], nint, out)
        }
        if pe != ok { os.exit(8) }
        ret out[usize(x[8usize])]
    }
    if str.eq(c.name, "pp") {
        let n = usize(x[0usize])
        let (g, ge) = im.fit_pp(a, x[4usize..4usize + n], x[2usize], usize(x[1usize]))
        if ge != ok { os.exit(6) }
        let w = usize(x[3usize])
        if w == 99usize { ret g.nllh }
        if w >= 10usize { ret g.se[w - 10usize] }
        ret g.par[w]
    }
    let rows = usize(x[0usize])
    let r = usize(x[1usize])
    let which = usize(x[2usize])
    let (f, e) = im.fit_rlarg(a, x[3usize..3usize + rows * r], rows, r)
    if e != ok { os.exit(5) }
    if which == 99usize { ret f.nllh }
    if which >= 10usize { ret f.se[which - 10usize] }
    ret f.par[which]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ismev_rlarg.json")
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
