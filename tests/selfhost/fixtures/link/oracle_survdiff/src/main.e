// e.algo.stat.survival's Fleming-Harrington test against survival::survdiff. tests/oracle/survdiff.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R survdiff`; the layout is at the top of scripts/r_oracle/groups/survdiff.R.

use e.algo.stat.survival as sv
use e.algo.stat.survfitpkg as sf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "sd_k") {
        let kk = usize(x[1usize])
        let nn = usize(x[2usize])
        let (gp, ge) = mem.alloc[usize](a, nn)
        let (ou, oe2) = mem.alloc[f64](a, 2usize)
        if ge != ok || oe2 != ok { os.exit(6) }
        var q = 0usize
        while q < nn {
            gp[q] = usize(x[3usize + 2usize * nn + q])
            q += 1usize
        }
        if sf.survdiff_k(a, x[3usize..3usize + nn], x[3usize + nn..3usize + 2usize * nn], gp, kk, x[0usize], ou) != ok { os.exit(7) }
        ret ou[0usize]
    }
    let na = usize(x[1usize])
    let nb = usize(x[2usize])
    let ta = x[3usize..3usize + na]
    let tb = x[3usize + na..3usize + na + nb]
    let (ea, e1) = mem.alloc[u8](a, na)
    let (eb, e2) = mem.alloc[u8](a, nb)
    if e1 != ok || e2 != ok { os.exit(4) }
    var i = 0usize
    while i < na {
        ea[i] = u8(x[3usize + na + nb + i])
        i += 1usize
    }
    i = 0usize
    while i < nb {
        eb[i] = u8(x[3usize + 2usize * na + nb + i])
        i += 1usize
    }
    let (r, e) = sv.fleming_harrington(ta, ea, na, tb, eb, nb, x[0usize], 0.0f64)
    if e != ok { os.exit(5) }
    if str.eq(c.name, "sd_chisq") { ret r.statistic }
    ret r.p_value
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/survdiff.json")
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
