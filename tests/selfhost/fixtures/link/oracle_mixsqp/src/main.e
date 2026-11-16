// e.algo.stat.mixsqp against mixsqp: the mixture proportions and objective value. tests/oracle/mixsqp.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixsqp`; the layout is at the top of
// scripts/r_oracle/groups/mixsqp.R.

use e.algo.stat.mixsqp as mq
use e.algo.stat.mixsqp_sqp as sq
use e.str
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn vsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "val") {
        let vn = usize(z[0usize])
        let vm = usize(z[1usize])
        let vl = z[2usize..2usize + vn * vm]
        let vw = z[2usize + vn * vm..2usize + vn * vm + vn]
        let vx = z[2usize + vn * vm + vn..2usize + vn * vm + vn + vm]
        let b = 2usize + vn * vm + vn + vm
        var ctl = sq.sqp_default()
        ctl.convtol_sqp = z[b]
        ctl.convtol_activeset = z[b + 1usize]
        ctl.zero_solution = z[b + 2usize]
        ctl.zero_searchdir = z[b + 3usize]
        ctl.suffdecr = z[b + 4usize]
        ctl.stepreduce = z[b + 5usize]
        ctl.minstep = z[b + 6usize]
        ctl.identity_increase = z[b + 7usize]
        ctl.eps = z[b + 8usize]
        ctl.numiter_em = i64(z[b + 11usize])
        ret f64(sq.sqp_validate(vl, vw, vx, vn, vm, ctl, z[b + 9usize], z[b + 10usize]))
    }
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let l = z[2usize..2usize + n * m]
    let w = z[2usize + n * m..2usize + n * m + n]
    let q = usize(z[2usize + n * m + n])
    let (x, e) = mem.alloc[f64](a, m)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "sqp") || str.eq(c.name, "sqplog") {
        var j = 0usize
        while j < m {
            x[j] = 1.0f64
            j += 1usize
        }
        let (gv, ge) = mem.alloc[f64](a, m)
        let (hv, he) = mem.alloc[f64](a, m * m)
        if ge != ok || he != ok { ret 0.0f64 / 0.0f64 }
        var zi = 0usize
        while zi < m {
            gv[zi] = 0.0f64
            zi += 1usize
        }
        zi = 0usize
        while zi < m * m {
            hv[zi] = 0.0f64
            zi += 1usize
        }
        let (r, se) = sq.mixsqp_run(a, l, w, n, m, x, sq.sqp_default(), str.eq(c.name, "sqplog"), gv, hv)
        if se != ok { ret 0.0f64 / 0.0f64 }
        if q < m { ret x[q] }
        if q == m { ret r.value }
        if q == m + 1usize { ret f64(r.status) }
        if q == m + 2usize { ret f64(r.iterations) }
        if q == m + 3usize { ret f64(r.nqp) }
        if q == m + 4usize { ret f64(r.nls) }
        if q == m + 5usize { ret f64(r.nnz) }
        let gsum = vsum(gv)
        if q == m + 6usize { ret gsum }
        ret vsum(hv)
    }
    let (v, me) = mq.mixsqp(a, l, w, n, m, x)
    if me != ok { ret 0.0f64 / 0.0f64 }
    if q < m { ret x[q] }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixsqp.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
