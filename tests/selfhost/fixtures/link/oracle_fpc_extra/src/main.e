// e.algo.stat.fpc_extra exports against fpc. tests/oracle/fpc_extra.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_extra`; the layouts are at the top of scripts/r_oracle/groups/fpc_extra.R.

use e.algo.rand.r as rg
use e.algo.stat.fpc_extra as fx
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn is(c: *const oracle.Case, s: str) -> bool {
    if c.name.len != s.len { ret false }
    var i = 0usize
    while i < s.len {
        if c.name[i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if is(c, "ce") { ret fx.clusexpect(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if is(c, "it") { ret fx.itnumber(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if is(c, "ms") { ret fx.minsize(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if is(c, "df") {
        let cat = usize(x[0usize])
        let ns = usize(x[5usize])
        ret fx.distancefactor(cat, x[1usize], x[6usize..6usize + ns], x[2usize] > 0.5f64, x[3usize], x[4usize])
    }
    if is(c, "rc") || is(c, "rs") {
        var g: rg.Rng = zero
        rg.seed(&g, i64(x[0usize]))
        let n = usize(x[1usize])
        let cln = usize(x[2usize])
        let (m, e1) = mem.alloc[f64](a, n * cln)
        let (sm, e2) = mem.alloc[usize](a, cln)
        if e1 != ok || e2 != ok { os.exit(5) }
        fx.randcmatrix(&g, n, cln, usize(x[3usize]), m, sm)
        if is(c, "rc") { ret m[usize(x[4usize]) * cln + usize(x[5usize])] }
        var t = 0.0f64
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < cln {
                t += f64(i + 1usize) * f64(j + 1usize) * m[i * cln + j]
                j += 1usize
            }
            i += 1usize
        }
        ret t
    }
    if is(c, "rf") {
        var g: rg.Rng = zero
        rg.seed(&g, i64(x[0usize]))
        let n = usize(x[1usize])
        let (gv, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let e = fx.randconf(a, &g, n, usize(x[2usize]), gv)
        if e != ok { os.exit(6) }
        ret gv[usize(x[3usize])]
    }
    if is(c, "mf") {
        let n = usize(x[3usize])
        let p = usize(x[4usize])
        let (md, e1) = mem.alloc[f64](a, n)
        let (mg, e2) = mem.alloc[f64](a, p)
        let (cv, e3) = mem.alloc[f64](a, p * p)
        let (ci, e4) = mem.alloc[f64](a, p * p)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(5) }
        let e = fx.mahalanofix(a, x[5usize + n..5usize + n + n * p], n, p, x[5usize..5usize + n], x[0usize] > 0.5f64, false, md, mg, cv, ci)
        if e != ok { os.exit(6) }
        let w = usize(x[1usize])
        let idx = usize(x[2usize])
        if w == 4usize {
            var t = 0.0f64
            var i = 0usize
            while i < n {
                t += f64(i + 1usize) * md[i]
                i += 1usize
            }
            ret t
        }
        if w == 0usize { ret md[idx] }
        if w == 1usize { ret mg[idx] }
        if w == 2usize { ret cv[idx] }
        ret ci[idx]
    }
    if is(c, "ls") {
        let n = usize(x[3usize])
        let p = usize(x[4usize])
        let (lc, e1) = mem.alloc[f64](a, p * p)
        if e1 != ok { os.exit(5) }
        let e = fx.localshape(a, x[5usize..5usize + n * p], n, p, x[0usize], usize(x[1usize]), lc)
        if e != ok { os.exit(6) }
        ret lc[usize(x[2usize])]
    }
    if is(c, "rec") {
        let n = usize(x[2usize])
        let (rk, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let cnt = fx.recode_col(x[3usize..3usize + n], n, rk)
        let w = usize(x[0usize])
        let idx = usize(x[1usize])
        if w == 0usize { ret f64(cnt) }
        if w == 1usize { ret rk[idx] }
        var t = 0.0f64
        var i = 0usize
        while i < n {
            if rk[i] == f64(idx + 1usize) { t += f64(i + 1usize) }
            i += 1usize
        }
        ret t
    }
    os.exit(7)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_extra.json")
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
                var c2 = *c
                if c.args.len > 6usize { c2.args = c.args[0usize..6usize] }
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
