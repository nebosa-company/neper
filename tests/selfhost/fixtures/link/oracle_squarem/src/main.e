// e.algo.stat.squarem against SQUAREM: squarem (methods 1 to 3), squarem1 and cyclem1 with an objective, cyclem2 and fpiter on four
// fixed-point maps. tests/oracle/squarem.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R squarem`; the layout
// and the maps are at the top of scripts/r_oracle/groups/squarem.R.

use e.algo.stat.squarem as sq
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type MapCtx = struct { id: u8, tmp: []f64 }

fn th(x: f64) -> f64 {
    let e = math.exp[f64](2.0f64 * x)
    ret (e - 1.0f64) / (e + 1.0f64)
}

fn map_fn(c: *MapCtx, p: []const f64, out: []f64) {
    let m = c.id
    if m == 0u8 { out[0usize] = math.cos[f64](p[0usize]) }
    if m == 1u8 {
        out[0usize] = 0.5f64 * math.cos[f64](p[1usize]) + 0.2f64
        out[1usize] = 0.3f64 * math.sin[f64](p[0usize]) + 0.1f64 * p[1usize]
    }
    if m == 2u8 {
        out[0usize] = 0.5f64 * (p[0usize] + 2.0f64 / p[0usize])
        out[1usize] = 0.5f64 * (p[1usize] + 5.0f64 / p[1usize])
        out[2usize] = 0.5f64 * (p[2usize] + 11.0f64 / p[2usize])
    }
    if m == 3u8 {
        out[0usize] = 0.5f64 * th(p[1usize]) + 0.3f64
        out[1usize] = 0.4f64 * th(p[0usize] + p[2usize])
        out[2usize] = 0.6f64 * math.cos[f64](p[0usize] - p[1usize])
    }
}

fn obj_fn(c: *MapCtx, p: []const f64) -> f64 {
    map_fn(c, p, c.tmp)
    var s = 0.0f64
    var i = 0usize
    while i < p.len {
        s += (p[i] - c.tmp[i]) * (p[i] - c.tmp[i])
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[4usize])
    let (tmp, te) = mem.alloc[f64](a, n)
    if te != ok { os.exit(6) }
    var ctx = MapCtx { id: u8(x[0usize]), tmp: tmp }
    let par0 = x[5usize..5usize + n]
    let kind = u8(x[5usize + n])
    var r: sq.Result1 = zero
    var e = ok
    if kind == 0u8 {
        let (rr, re) = sq.squarem2[MapCtx](a, &ctx, map_fn, par0, u8(x[1usize]), x[2usize], i64(x[3usize]))
        r.par = rr.par
        r.iter = rr.iter
        r.fpevals = rr.fpevals
        r.converged = rr.converged
        e = re
    } else if kind == 1u8 {
        let (rr, re) = sq.fpiter[MapCtx](a, &ctx, map_fn, par0, x[2usize], i64(x[3usize]))
        r.par = rr.par
        r.iter = rr.iter
        r.fpevals = rr.fpevals
        r.converged = rr.converged
        e = re
    } else {
        var ctl = sq.ctl_default()
        ctl.tol = x[2usize]
        ctl.maxiter = i64(x[3usize])
        if kind == 2u8 {
            ctl.method = u8(x[1usize])
            let (rr, re) = sq.squarem1[MapCtx](a, &ctx, map_fn, obj_fn, par0, ctl)
            r = rr
            e = re
        } else {
            ctl.k = usize(x[5usize + n + 1usize])
            ctl.rre = x[5usize + n + 2usize] == 1.0f64
            ctl.square = x[5usize + n + 3usize] == 1.0f64
            let (rr, re) = sq.cyclem[MapCtx](a, &ctx, map_fn, obj_fn, kind == 3u8, par0, ctl)
            r = rr
            e = re
        }
    }
    if e != ok { os.exit(6) }
    if str.eq(c.name, "par") { ret r.par[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "iter") { ret f64(r.iter) }
    if str.eq(c.name, "fpevals") { ret f64(r.fpevals) }
    if str.eq(c.name, "objf") { ret f64(r.objfevals) }
    if str.eq(c.name, "value") { ret r.value }
    if r.converged { ret 1.0f64 }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/squarem.json")
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
