// e.algo.stat.glasso and the EBICglasso half of e.algo.stat.qgraphpkg against glasso::glasso, glasso::glassopath and
// qgraph::EBICglasso. tests/oracle/glasso.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glasso`;
// the argument layouts are at the top of scripts/r_oracle/groups/glasso.R.

use e.algo.stat.armx87 as xe
use e.algo.stat.glasso as gl
use e.algo.stat.qgraphpkg as qg
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn run_gl(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let p = usize(z[0usize])
    let ia = z[1usize] != 0.0f64
    let ipen = z[2usize] != 0.0f64
    let thr = z[3usize]
    let maxit = usize(z[4usize])
    let nobs = z[5usize]
    let nrho = usize(z[6usize])
    let rv = z[7usize..7usize + nrho]
    let nz = usize(z[7usize + nrho])
    let zr = z[8usize + nrho..8usize + nrho + 2usize * nz]
    let s = z[8usize + nrho + 2usize * nz..8usize + nrho + 2usize * nz + p * p]
    let (rho, e1) = gl.zalloc(a, p * p)
    let (ww, e2) = gl.zalloc(a, p * p)
    let (wwi, e3) = gl.zalloc(a, p * p)
    let (info, e4) = gl.zalloc(a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            if nrho == 1usize {
                rho[j * p + i] = rv[0usize]
            } else {
                rho[j * p + i] = math.sqrt[f64](rv[i]) * math.sqrt[f64](rv[j])
            }
            i += 1usize
        }
        j += 1usize
    }
    var k = 0usize
    while k < nz {
        let i = usize(zr[2usize * k]) - 1usize
        let jj = usize(zr[2usize * k + 1usize]) - 1usize
        rho[jj * p + i] = 10.0e9f64
        rho[i * p + jj] = 10.0e9f64
        k += 1usize
    }
    if gl.fit(a, p, s, rho, ia, false, ipen, thr, maxit, ww, wwi, info) != ok { ret nan }
    if str.eq(c.name, "gl_w") { ret wsum(ww) }
    if str.eq(c.name, "gl_wi") { ret wsum(wwi) }
    if str.eq(c.name, "gl_niter") { ret info[0usize] }
    if str.eq(c.name, "gl_del") { ret info[1usize] }
    ret qg.glasso_loglik(a, s, rho, wwi, p, nobs, ipen)
}

fn run_path(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let p = usize(z[0usize])
    let nr = usize(z[1usize])
    let ia = z[2usize] != 0.0f64
    let ipen = z[3usize] != 0.0f64
    let rl = z[4usize..4usize + nr]
    let s = z[4usize + nr..4usize + nr + p * p]
    let (beta, e1) = gl.zalloc(a, p * p * nr)
    let (what, e2) = gl.zalloc(a, p * p * nr)
    if e1 != ok || e2 != ok { ret nan }
    if gl.path(a, p, s, rl, ia, ipen, 1.0e-4f64, 10000usize, beta, what) != ok { ret nan }
    if str.eq(c.name, "path_w") { ret wsum(what) }
    ret wsum(beta)
}

fn run_ebic(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let p = usize(z[0usize])
    let nl = usize(z[4usize])
    let s = z[9usize..9usize + p * p]
    let (net, e1) = gl.zalloc(a, p * p)
    let (eb, e2) = gl.zalloc(a, nl)
    let (lam, e3) = gl.zalloc(a, nl)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    let (opt, e) = qg.ebic_glasso(a, s, p, z[1usize], z[2usize], z[3usize] != 0.0f64, nl, z[5usize], z[6usize] != 0.0f64, z[7usize] != 0.0f64, z[8usize] != 0.0f64, z[0usize..0usize], net, eb, lam)
    if e != ok { ret nan }
    if str.eq(c.name, "lam_at") { ret lam[usize(z[9usize + p * p]) - 1usize] }
    if str.eq(c.name, "ebic_at") { ret eb[usize(z[9usize + p * p]) - 1usize] }
    if str.eq(c.name, "ebic_net") { ret wsum(net) }
    if str.eq(c.name, "ebic_val") { ret wsum(eb) }
    ret lam[opt]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "lg") { ret xe.log_r(c.args[0usize]) }
    if str.eq(c.name, "ex") { ret xe.exp_r(c.args[0usize]) }
    if str.eq(c.name, "explog") { ret xe.exp_r(xe.log_r(c.args[0usize])) }
    if str.starts_with(c.name, "gl_") { ret run_gl(a, c) }
    if str.starts_with(c.name, "path_") { ret run_path(a, c) }
    ret run_ebic(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/glasso.json")
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
                let (initial, be) = str.builder(a, 160usize)
                var b = initial
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " #")
                let _ = str.push_f64(&b, f64(at))
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " R ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
