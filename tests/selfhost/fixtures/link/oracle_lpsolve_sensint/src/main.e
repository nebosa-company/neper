// e.algo.stat.lpsolveint's lp_sens_int against lpSolve's compute.sens duals on integer and binary programs. tests/oracle/lpsolve_sensint.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolve_sensint`; the layout is at the top of scripts/r_oracle/groups/lpsolve_sensint.R.

use e.algo.stat.lpsolveint as lpi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let mx = z[2usize] > 0.5f64
    let oc = 3usize
    let oa = oc + n
    let ob = oa + m * n
    let ocode = ob + m
    let okind = ocode + m
    let of = okind + n
    let (du, e1) = mem.alloc[f64](a, m + n)
    let (df, g1) = mem.alloc[f64](a, m + n)
    let (dt, g2) = mem.alloc[f64](a, m + n)
    let (cf, g3) = mem.alloc[f64](a, n)
    let (ct, g4) = mem.alloc[f64](a, n)
    let (rel, e2) = mem.alloc[usize](a, m)
    let (isint, e3) = mem.alloc[bool](a, n)
    let (isbin, e4) = mem.alloc[bool](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || g1 != ok || g2 != ok || g3 != ok || g4 != ok { ret nan }
    var i = 0usize
    while i < m {
        rel[i] = usize(z[ocode + i])
        i += 1usize
    }
    i = 0usize
    while i < n {
        isint[i] = usize(z[okind + i]) == 1usize
        isbin[i] = usize(z[okind + i]) == 2usize
        i += 1usize
    }
    let (v, e) = lpi.lp_sens_int(a, z[oc..oc + n], z[oa..oa + m * n], z[ob..ob + m], rel, m, n, mx, isint, isbin, du, df, dt, cf, ct)
    if e != ok { ret nan }
    if usize(z[of]) == 1usize { ret v }
    let at = usize(z[of + 1usize]) - 1usize
    let fld = usize(z[of])
    if fld == 2usize { ret df[at] }
    if fld == 3usize { ret dt[at] }
    if fld == 4usize { ret cf[at] }
    if fld == 5usize { ret ct[at] }
    ret du[at]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolve_sensint.json")
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
