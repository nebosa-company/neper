// e.algo.stat.polynompkg against polynom and caTools. tests/oracle/polynompkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polynompkg`; the layout is at the top of scripts/r_oracle/groups/polynompkg.R.

use e.algo.stat.polynompkg as pn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "predict") { ret pn.predict(x[2usize..2usize + usize(x[1usize])], x[0usize]) }
    if str.eq(k, "deriv") {
        let n = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { os.exit(5) }
        pn.deriv(x[2usize..2usize + n], o)
        ret o[usize(x[0usize])]
    }
    if str.eq(k, "integral") {
        let n = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n + 1usize)
        if e != ok { os.exit(6) }
        pn.integral(x[2usize..2usize + n], o)
        ret o[usize(x[0usize])]
    }
    if str.eq(k, "polycalc") {
        let n = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n + 1usize)
        if e != ok { os.exit(7) }
        pn.poly_calc(x[2usize..2usize + n], o)
        ret o[usize(x[0usize])]
    }
    if str.eq(k, "polyorth") {
        let dg = usize(x[0usize])
        let np = usize(x[3usize])
        let (o, e) = mem.alloc[f64](a, dg + 2usize)
        if e != ok { os.exit(8) }
        let (w, e2) = mem.alloc[f64](a, 4usize * (dg + 2usize))
        if e2 != ok { os.exit(9) }
        pn.poly_orth(x[4usize..4usize + np], dg, usize(x[1usize]), o, w)
        ret o[usize(x[2usize])]
    }
    let n = usize(x[0usize])
    ret pn.col_auc(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polynompkg.json")
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
