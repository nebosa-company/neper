// e.algo.stat.lpsolvepkg (lp min, status codes, transport shipments, assignment min) against lpSolve. tests/oracle/lpsolve_more.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolve_more`; the layout is at the top of scripts/r_oracle/groups/lpsolve_more.R.

use e.algo.stat.cluelsap as cl
use e.algo.stat.lpsolvepkg as lp
use e.io
use e.math.opt as opt
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn transport_case(a: *mem.Arena, x: []const f64, status: bool) -> f64 {
    let tm = usize(x[0usize])
    let tn = usize(x[1usize])
    let mx = x[2usize] > 0.5f64
    let co = 3usize
    let rso = co + tm * tn
    let rro = rso + tm
    let cso = rro + tm
    let cro = cso + tn
    let (rsg, g1) = mem.alloc[usize](a, tm)
    let (csg, g2) = mem.alloc[usize](a, tn)
    let (shp, g3) = mem.alloc[f64](a, tm * tn)
    if g1 != ok || g2 != ok || g3 != ok { os.exit(7) }
    var q = 0usize
    while q < tm {
        rsg[q] = usize(x[rso + q])
        q += 1usize
    }
    q = 0usize
    while q < tn {
        csg[q] = usize(x[cso + q])
        q += 1usize
    }
    let (tv, te) = lp.transport(a, x[co..co + tm * tn], tm, tn, mx, rsg, x[rro..rro + tm], csg, x[cro..cro + tn], shp)
    if status {
        if te == ok { ret 0.0f64 }
        if te == opt.Infeasible { ret 2.0f64 }
        ret 3.0f64
    }
    if te != ok { os.exit(8) }
    var s = 0.0f64
    var i = 0usize
    while i < tm {
        var j = 0usize
        while j < tn {
            s += shp[i * tn + j] * f64(10usize * (i + 1usize) + j + 1usize)
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn assign_case(a: *mem.Arena, x: []const f64, cols: bool) -> f64 {
    let n = usize(x[0usize])
    let (asg, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(9) }
    let (tot, e1) = cl.solve_lsap(a, x[1usize..1usize + n * n], n, n, false, asg)
    if e1 != ok { os.exit(10) }
    if !cols { ret tot }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(10usize * (i + 1usize) + asg[i] + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "trsol") { ret transport_case(a, x, false) }
    if str.eq(c.name, "trstat") { ret transport_case(a, x, true) }
    if str.eq(c.name, "asmin") { ret assign_case(a, x, false) }
    if str.eq(c.name, "asmincols") { ret assign_case(a, x, true) }
    let m = usize(x[0usize])
    let n = usize(x[1usize])
    let ra = 2usize + n
    let rr = ra + m * n
    let rb = rr + m
    let ri = rb + m
    let (cc, e1) = mem.alloc[f64](a, n)
    let (rel, e2) = mem.alloc[usize](a, m)
    let (isint, e4) = mem.alloc[bool](a, n)
    let (sol, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e4 != ok || e5 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        cc[i] = x[2usize + i]
        isint[i] = x[ri + i] > 0.5f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        rel[i] = usize(x[rr + i])
        i += 1usize
    }
    var maximise = false
    if str.eq(c.name, "lpstat") { maximise = x[ri + n] > 0.5f64 }
    let (obj, st) = lp.lp_general(a, maximise, cc, x[ra..ra + m * n], rel, x[rb..rb + m], m, n, isint, sol)
    if str.eq(c.name, "lpstat") { ret f64(st) }
    if st != 0usize { os.exit(6) }
    if str.eq(c.name, "lpx") {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += sol[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    ret obj
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolve_more.json")
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
