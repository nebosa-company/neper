// e.algo.stat.irr against irr. tests/oracle/irr.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R irr`; the layout of
// every case is at the top of scripts/r_oracle/groups/irr.R.

use e.algo.stat.irr as ir
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pick(t: ir.Test, j: usize) -> f64 {
    if j == 0usize { ret t.value }
    if j == 1usize { ret t.stat }
    ret t.p
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.eq(nm, "agree") {
        let ns = usize(x[0usize])
        let nr = usize(x[1usize])
        ret ir.agree(x[3usize..3usize + ns * nr], ns, nr, x[2usize])
    }
    if str.eq(nm, "kappa2") {
        let ns = usize(x[0usize])
        let nw = usize(x[2usize])
        let (t, e) = ir.kappa2(a, x[3usize + nw..3usize + nw + 2usize * ns], ns, u8(x[1usize]), x[3usize..3usize + nw])
        if e != ok { os.exit(6) }
        ret pick(t, usize(x[x.len - 1usize]))
    }
    if str.eq(nm, "maxwell") { ret ir.maxwell(x[1usize..1usize + 2usize * usize(x[0usize])], usize(x[0usize])) }
    let ns = usize(x[0usize])
    let nr = usize(x[1usize])
    if str.eq(nm, "iota") {
        let nvar = usize(x[2usize])
        let (v, e) = ir.iota(a, x[5usize..5usize + nvar * ns * nr], ns, nr, nvar, x[3usize] == 1.0f64, x[4usize] == 1.0f64)
        if e != ok { os.exit(6) }
        ret v
    }
    if str.eq(nm, "robinson") { ret ir.robinson(a, x[2usize..2usize + ns * nr], ns, nr) }
    if str.eq(nm, "fleiss") {
        let (t, e) = ir.kappam_fleiss(a, x[3usize..3usize + ns * nr], ns, nr, x[2usize] == 1.0f64)
        if e != ok { os.exit(6) }
        ret pick(t, usize(x[x.len - 1usize]))
    }
    if str.eq(nm, "light") {
        let (t, e) = ir.kappam_light(a, x[2usize..2usize + ns * nr], ns, nr)
        if e != ok { os.exit(6) }
        ret pick(t, usize(x[x.len - 1usize]))
    }
    if str.eq(nm, "kendall") {
        let (t, e) = ir.kendall(a, x[3usize..3usize + ns * nr], ns, nr, x[2usize] == 1.0f64)
        if e != ok { os.exit(6) }
        ret pick(t, usize(x[x.len - 1usize]))
    }
    if str.eq(nm, "meancor") {
        let (t, e) = ir.meancor(a, x[3usize..3usize + ns * nr], ns, nr, x[2usize] == 1.0f64)
        if e != ok { os.exit(6) }
        ret pick(t, usize(x[x.len - 1usize]))
    }
    if str.eq(nm, "finn") {
        let (t, e) = ir.finn(a, x[4usize..4usize + ns * nr], ns, nr, x[2usize], x[3usize] == 1.0f64)
        if e != ok { os.exit(6) }
        ret pick(t, usize(x[x.len - 1usize]))
    }
    if str.eq(nm, "icc") {
        let (r, e) = ir.icc(a, x[7usize..7usize + ns * nr], ns, nr, u8(x[2usize]), u8(x[3usize]), u8(x[4usize]), x[5usize], x[6usize])
        if e != ok { os.exit(6) }
        if usize(x[x.len - 1usize]) == 0usize { ret r.value }
        if usize(x[x.len - 1usize]) == 1usize { ret r.f }
        if usize(x[x.len - 1usize]) == 2usize { ret r.df1 }
        if usize(x[x.len - 1usize]) == 3usize { ret r.df2 }
        if usize(x[x.len - 1usize]) == 4usize { ret r.p }
        if usize(x[x.len - 1usize]) == 5usize { ret r.lbound }
        ret r.ubound
    }
    // kripp: (nrat, nobj, method, X)
    let nobj = nr
    let (m, me) = mem.alloc[f64](a, ns * nobj)
    if me != ok { os.exit(5) }
    var i = 0usize
    while i < ns * nobj {
        m[i] = x[3usize + i]
        if m[i] == 0.0f64 - 999.0f64 { m[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    let (v, ke) = ir.kripp_alpha(a, m, ns, nobj, u8(x[2usize]))
    if ke != ok { os.exit(6) }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/irr.json")
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
