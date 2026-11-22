// e.algo.stat.osqppkg against osqp (OSQP 1.0.0) solve_osqp and the osqp model object. tests/oracle/osqp.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R osqp`; the layout is at the top of scripts/r_oracle/groups/osqp.R.

use e.algo.stat.osqppkg as qp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let scenario = usize(z[0usize])
    let n = usize(z[1usize])
    let m = usize(z[2usize])
    var st = qp.default_settings()
    st.eps_abs = z[3usize]
    st.eps_rel = z[4usize]
    st.max_iter = usize(z[5usize])
    st.polishing = usize(z[6usize])
    st.adaptive_rho = usize(z[7usize])
    st.adaptive_rho_interval = usize(z[8usize])
    st.rho = z[9usize]
    st.sigma = z[10usize]
    st.alpha = z[11usize]
    st.scaling = usize(z[12usize])
    st.check_termination = usize(z[13usize])
    var o = 14usize
    let p = z[o..o + n * n]
    o += n * n
    let q = z[o..o + n]
    o += n
    let am = z[o..o + m * n]
    o += m * n
    let l = z[o..o + m]
    o += m
    let u = z[o..o + m]
    o += m
    let (s, e1) = qp.setup(a, n, m, p, q, am, l, u, st)
    if e1 != ok { ret nan }
    if scenario == 3usize {
        qp.warm_start(s, z[o..o + n], z[o + n..o + n + m])
    }
    qp.solve_problem(s)
    if scenario == 1usize {
        let q2 = z[o..o + n]
        let l2 = z[o + n..o + n + m]
        let u2 = z[o + n + m..o + n + m + m]
        let _ = qp.update_vec(s, q2, l2, u2)
        qp.solve_problem(s)
    }
    if scenario == 2usize {
        let p2 = z[o..o + n * n]
        let a2 = z[o + n * n..o + n * n + m * n]
        qp.update_mat(s, p2, a2)
        qp.solve_problem(s)
    }
    let k = c.name
    if str.eq(k, "status") { ret f64(s.info.status) }
    if str.eq(k, "iter") { ret f64(s.info.iter) }
    if str.eq(k, "obj") { ret s.info.obj_val }
    if str.eq(k, "dual_obj") { ret s.info.dual_obj_val }
    if str.eq(k, "prim_res") { ret s.info.prim_res }
    if str.eq(k, "dual_res") { ret s.info.dual_res }
    if str.eq(k, "gap") { ret s.info.duality_gap }
    if str.eq(k, "rho_estimate") { ret s.info.rho_estimate }
    if str.eq(k, "rho_updates") { ret f64(s.info.rho_updates) }
    if str.eq(k, "status_polish") { ret s.info.status_polish }
    var sum = 0.0f64
    var i = 0usize
    if str.eq(k, "x") {
        while i < n {
            sum += s.sol_x[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    if str.eq(k, "y") {
        while i < m {
            sum += s.sol_y[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    if str.eq(k, "pcert") {
        while i < m {
            sum += s.pcert[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    if str.eq(k, "dcert") {
        while i < n {
            sum += s.dcert[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/osqp.json")
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
