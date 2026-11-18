// e.algo.stat.survfitpkg against survival::survfit. tests/oracle/survfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R survfit`; the layout is at the top of scripts/r_oracle/groups/survfit.R.

use e.algo.stat.survfitpkg as sf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle
use e.str

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "ssplit") {
        let sn = usize(x[0usize])
        let sc = usize(x[1usize])
        let (so, se2) = mem.alloc[f64](a, (sn * (sc + 1usize) + 1usize) * 4usize)
        if se2 != ok { os.exit(6) }
        let rows = sf.surv_split(x[2usize..2usize + sn], x[2usize + sn..2usize + 2usize * sn], x[2usize + 2usize * sn..2usize + 2usize * sn + sc], so, sn * (sc + 1usize))
        let rw = x[2usize + 2usize * sn + sc]
        if rw < 0.0f64 { ret f64(rows) }
        ret so[usize(rw) * 4usize + usize(x[3usize + 2usize * sn + sc])]
    }
    if str.eq(c.name, "pyr") {
        let pk = usize(x[0usize])
        let pn = usize(x[1usize])
        let (po, pe) = mem.alloc[f64](a, pk * 3usize)
        let (pg, pge) = mem.alloc[usize](a, pn)
        if pe != ok || pge != ok { os.exit(7) }
        var q4 = 0usize
        while q4 < pn {
            pg[q4] = usize(x[3usize + 2usize * pn + q4])
            q4 += 1usize
        }
        sf.pyears_table(x[3usize..3usize + pn], x[3usize + pn..3usize + 2usize * pn], pg, pk, x[2usize], po)
        ret po[usize(x[3usize + 3usize * pn]) * 3usize + usize(x[4usize + 3usize * pn])]
    }
    if str.eq(c.name, "conc") {
        let cn = usize(x[0usize])
        let (co, ce) = mem.alloc[f64](a, 4usize)
        if ce != ok { os.exit(5) }
        sf.concordance_counts(x[1usize..1usize + cn], x[1usize + cn..1usize + 2usize * cn], x[1usize + 2usize * cn..1usize + 3usize * cn], co)
        ret co[usize(x[1usize + 3usize * cn])]
    }
    let n = usize(x[2usize])
    let t = x[3usize..3usize + n]
    let e = x[3usize + n..3usize + 2usize * n]
    let (o, oe) = mem.alloc[f64](a, (n + 1usize) * 7usize)
    if oe != ok { os.exit(4) }
    var rows = 0usize
    if usize(x[1usize]) >= 10usize {
        rows = sf.na_table(t, e, x[0usize], usize(x[1usize]) == 11usize, o, n)
    } else {
        rows = sf.km_table(a, t, e, x[0usize], usize(x[1usize]), o, n)
    }
    let row = usize(x[3usize + 2usize * n])
    let col = usize(x[4usize + 2usize * n])
    if row >= rows { ret 0.0f64 - 1.0f64 }
    ret o[row * 7usize + col]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/survfit.json")
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
