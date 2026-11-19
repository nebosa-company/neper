// e.algo.stat.sm's hselect_cv (h.select cv) against sm. tests/oracle/sm_hsel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sm_hsel`; the layout is at the top of scripts/r_oracle/groups/sm_hsel.R.

use e.algo.stat.sm as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sm_hsel.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let n = usize(c.args[0usize])
        var got = 0.0f64
        if str.eq(c.name, "hbm") || str.eq(c.name, "hbx") || str.eq(c.name, "hbf") || str.eq(c.name, "hbmean") || str.eq(c.name, "hbdev") {
            let nbn = usize(c.args[1usize])
            let (bx, f0) = mem.alloc[f64](a, nbn)
            let (bf, f1) = mem.alloc[f64](a, nbn)
            let (bm, f2) = mem.alloc[f64](a, nbn)
            let (bd, f3) = mem.alloc[f64](a, nbn)
            if f0 != ok || f1 != ok || f2 != ok || f3 != ok { os.exit(4) }
            let (m, eb) = sm.binning1d(a, c.args[2usize..2usize + n], c.args[2usize + n..2usize + 2usize * n], nbn, bx, bf, bm, bd)
            if eb != ok { os.exit(4) }
            var tot = f64(m)
            if !str.eq(c.name, "hbm") {
                var pick = bx
                if str.eq(c.name, "hbf") { pick = bf }
                if str.eq(c.name, "hbmean") { pick = bm }
                if str.eq(c.name, "hbdev") { pick = bd }
                tot = 0.0f64
                var q = 0usize
                while q < m {
                    tot += pick[q] * f64(q + 1usize)
                    q += 1usize
                }
            }
            if !oracle.agrees(tot, c) { failures += 1usize }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hbreg") {
            let nbn = usize(c.args[1usize])
            let (bx, f0) = mem.alloc[f64](a, nbn)
            let (bf, f1) = mem.alloc[f64](a, nbn)
            let (bm, f2) = mem.alloc[f64](a, nbn)
            let (bd, f3) = mem.alloc[f64](a, nbn)
            if f0 != ok || f1 != ok || f2 != ok || f3 != ok { os.exit(4) }
            let (m, eb) = sm.binning1d(a, c.args[4usize..4usize + n], c.args[4usize + n..4usize + 2usize * n], nbn, bx, bf, bm, bd)
            if eb != ok { os.exit(4) }
            let est = sm.regression_w(bx[0usize..m], bm[0usize..m], bf[0usize..m], c.args[2usize], c.args[3usize])
            if !oracle.agrees(est, c) { failures += 1usize }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hse") {
            let hh = c.args[1usize]
            let pp = c.args[2usize]
            let (sv, es) = sm.regression_se(a, c.args[3usize..3usize + n], c.args[3usize + n..3usize + 2usize * n], hh, pp)
            if es != ok { os.exit(4) }
            if !oracle.agrees(sv, c) { failures += 1usize }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "haicc") { got = sm.hselect_crit(c.args[1usize..1usize + n], c.args[1usize + n..1usize + 2usize * n], 1usize, 0.0f64) } else if str.eq(c.name, "hdf") { got = sm.hselect_crit(c.args[1usize..1usize + n], c.args[1usize + n..1usize + 2usize * n], 0usize, 5.0f64) } else if str.eq(c.name, "hcvreg") { got = sm.hselect_cv_reg(c.args[1usize..1usize + n], c.args[1usize + n..1usize + 2usize * n]) } else { got = sm.hselect_cv(c.args[1usize..1usize + n]) }
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
