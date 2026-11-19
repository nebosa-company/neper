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
        if str.eq(c.name, "hnoe") || str.eq(c.name, "hlin") || str.eq(c.name, "hqn") || str.eq(c.name, "hql") {
            var kd2 = 0usize
            if str.eq(c.name, "hlin") || str.eq(c.name, "hql") { kd2 = 1usize }
            var wh = 0usize
            if str.eq(c.name, "hqn") || str.eq(c.name, "hql") { wh = 1usize }
            let (tv, et) = sm.regression_test(a, c.args[2usize..2usize + n], c.args[2usize + n..2usize + 2usize * n], c.args[1usize], kd2, wh)
            if et != ok { os.exit(4) }
            if !oracle.agrees(tv, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, tv))
                let _ = io.print("\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hc2s") {
            let hv4 = sm.hselect_cv_2d_separate(a, c.args[2usize..2usize + n], c.args[2usize + n..2usize + 2usize * n], usize(c.args[1usize]))
            if !oracle.agrees(hv4, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, hv4))
                let _ = io.print("\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hc2c") {
            let hv3 = sm.hselect_cv_2d_common(c.args[2usize..2usize + n], c.args[2usize + n..2usize + 2usize * n])
            if !oracle.agrees(hv3, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, hv3))
                let _ = io.print("\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hc2") {
            let hv2 = sm.hselect_cv_2d(c.args[2usize..2usize + n], c.args[2usize + n..2usize + 2usize * n], usize(c.args[1usize]))
            if !oracle.agrees(hv2, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, hv2))
                let _ = io.print("\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hsv") {
            let (sv, es) = sm.survival_at(a, c.args[5usize..5usize + n], c.args[5usize + n..5usize + 2usize * n], c.args[5usize + 2usize * n..5usize + 3usize * n], 1.0f64, c.args[1usize], c.args[2usize], c.args[3usize], c.args[4usize])
            if es != ok { os.exit(4) }
            if !oracle.agrees(sv, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, sv))
                let _ = io.print("\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hanc") || str.eq(c.name, "hanp") {
            let (pv, ep) = sm.ancova_equal(a, c.args[2usize..2usize + n], c.args[2usize + n..2usize + 2usize * n], c.args[2usize + 2usize * n..2usize + 3usize * n], c.args[1usize], str.eq(c.name, "hanp"))
            if ep != ok { os.exit(4) }
            if !oracle.agrees(pv, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, pv))
                let _ = io.print("\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hbrcv") || str.eq(c.name, "hbrdf") || str.eq(c.name, "hbraicc") {
            let nbn = usize(c.args[1usize])
            let (bx, f0) = mem.alloc[f64](a, nbn)
            let (bf, f1) = mem.alloc[f64](a, nbn)
            let (bm, f2) = mem.alloc[f64](a, nbn)
            let (bd, f3) = mem.alloc[f64](a, nbn)
            if f0 != ok || f1 != ok || f2 != ok || f3 != ok { os.exit(4) }
            let xs = c.args[2usize..2usize + n]
            let (m, eb) = sm.binning1d(a, xs, c.args[2usize + n..2usize + 2usize * n], nbn, bx, bf, bm, bd)
            if eb != ok { os.exit(4) }
            var kd = 0usize
            if str.eq(c.name, "hbrdf") { kd = 1usize }
            if str.eq(c.name, "hbraicc") { kd = 2usize }
            let est = sm.hselect_bin_reg(bx[0usize..m], bm[0usize..m], bf[0usize..m], bd[0usize..m], kd, 5.0f64, sm.sd_of(xs) / 2.0f64)
            if !oracle.agrees(est, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, est))
                let _ = io.print(" mismatch\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hbsel") {
            let nbn = usize(c.args[1usize])
            let (bx, f0) = mem.alloc[f64](a, nbn)
            let (bf, f1) = mem.alloc[f64](a, nbn)
            let (bm, f2) = mem.alloc[f64](a, nbn)
            let (bd, f3) = mem.alloc[f64](a, nbn)
            if f0 != ok || f1 != ok || f2 != ok || f3 != ok { os.exit(4) }
            let xs = c.args[2usize..2usize + n]
            let (m, eb) = sm.binning1d(a, xs, xs, nbn, bx, bf, bm, bd)
            if eb != ok { os.exit(4) }
            let est = sm.hselect_cv_binned(bx[0usize..m], bf[0usize..m], sm.sd_of(xs) / 2.0f64)
            if !oracle.agrees(est, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, est))
                let _ = io.print(" mismatch\n")
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "hbden") {
            let nbn = usize(c.args[1usize])
            let (bx, f0) = mem.alloc[f64](a, nbn)
            let (bf, f1) = mem.alloc[f64](a, nbn)
            let (bm, f2) = mem.alloc[f64](a, nbn)
            let (bd, f3) = mem.alloc[f64](a, nbn)
            if f0 != ok || f1 != ok || f2 != ok || f3 != ok { os.exit(4) }
            let xs = c.args[4usize..4usize + n]
            let (m, eb) = sm.binning1d(a, xs, xs, nbn, bx, bf, bm, bd)
            if eb != ok { os.exit(4) }
            let est = sm.density_w(bx[0usize..m], bf[0usize..m], c.args[2usize], c.args[3usize])
            if !oracle.agrees(est, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, est))
                let _ = io.print(" mismatch\n")
            }
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
            if !oracle.agrees(est, c) {
                failures += 1usize
                let _ = io.print(oracle.describe(a, c, est))
                let _ = io.print(" mismatch\n")
            }
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
