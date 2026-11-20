// e.algo.stat.nlopt against nloptr (nlopt 2.10.0) on nine small problems: value, return code, evaluation count and
// every coordinate. tests/oracle/nloptr.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nloptr`;
// the problem table is the one in scripts/r_oracle/groups/nloptr.R.

use e.algo.stat.nlopt as nl
use e.algo.stat.nlopt_luksan as lk
use e.algo.stat.nlopt_auglag as ag
use e.algo.stat.nlopt_slsqp as sl
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn cube(t: f64) -> f64 { ret t * t * t }

fn quart(t: f64) -> f64 {
    let s = t * t
    ret s * s
}

fn dims(id: usize) -> usize {
    if id == 0usize || id == 1usize || id == 3usize || id == 4usize || id == 6usize { ret 2usize }
    if id == 5usize { ret 4usize }
    if id == 10usize { ret 6usize }
    ret 3usize
}

fn n_ineq(id: usize) -> usize {
    if id == 0usize || id == 2usize { ret 2usize }
    if id == 1usize || id == 4usize || id == 5usize || id == 6usize { ret 1usize }
    ret 0usize
}

fn n_eq(id: usize) -> usize {
    if id == 5usize || id == 6usize { ret 1usize }
    if id == 7usize { ret 2usize }
    ret 0usize
}

fn x0_of(id: usize, i: usize) -> f64 {
    if id == 0usize {
        if i == 0usize { ret 1.234f64 }
        ret 5.678f64
    }
    if id == 1usize || id == 6usize { ret 0.0f64 }
    if id == 2usize { ret 0.0f64 }
    if id == 3usize {
        if i == 0usize { ret 0.0f64 - 1.2f64 }
        ret 1.0f64
    }
    if id == 4usize { ret 0.2f64 }
    if id == 9usize { ret 0.0f64 }
    if id == 10usize {
        if i % 2usize == 0usize { ret 0.0f64 - 1.2f64 }
        ret 1.0f64
    }
    if id == 5usize {
        if i == 0usize || i == 3usize { ret 1.0f64 }
        ret 5.0f64
    }
    if id == 7usize {
        if i == 0usize { ret 2.0f64 }
        if i == 1usize { ret 0.0f64 - 1.0f64 }
        ret 3.0f64
    }
    if i == 0usize { ret 3.0f64 }
    if i == 1usize { ret 0.0f64 - 2.0f64 }
    ret 1.0f64
}

fn lb_of(id: usize, i: usize) -> f64 {
    if id == 0usize {
        if i == 0usize { ret 0.0f64 - nl.inf() }
        ret 0.0f64
    }
    if id == 1usize || id == 6usize { ret 0.0f64 - 5.0f64 }
    if id == 2usize { ret 0.0f64 - 5.0f64 }
    if id == 3usize { ret 0.0f64 - 2.0f64 }
    if id == 4usize { ret 0.1f64 }
    if id == 5usize { ret 1.0f64 }
    if id == 7usize { ret 0.0f64 - 10.0f64 }
    if id == 9usize { ret 0.0f64 - 1.0f64 }
    ret 0.0f64 - nl.inf()
}

fn ub_of(id: usize, i: usize) -> f64 {
    if id == 0usize { ret nl.inf() }
    if id == 1usize || id == 6usize || id == 2usize { ret 5.0f64 }
    if id == 3usize { ret 2.0f64 }
    if id == 4usize { ret 10.0f64 }
    if id == 5usize { ret 5.0f64 }
    if id == 7usize { ret 10.0f64 }
    if id == 9usize { ret 2.0f64 }
    ret nl.inf()
}

fn obj(ctx: *u8, x: []const f64, g: []f64) -> f64 {
    let id = usize(*ctx)
    if id == 0usize {
        if g.len > 0usize {
            g[0usize] = 0.0f64
            g[1usize] = 0.5f64 / math.sqrt[f64](x[1usize])
        }
        ret math.sqrt[f64](x[1usize])
    }
    if id == 1usize || id == 6usize {
        if g.len > 0usize {
            g[0usize] = 2.0f64 * (x[0usize] - 2.0f64)
            g[1usize] = 2.0f64 * (x[1usize] - 1.0f64)
        }
        ret (x[0usize] - 2.0f64) * (x[0usize] - 2.0f64) + (x[1usize] - 1.0f64) * (x[1usize] - 1.0f64)
    }
    if id == 2usize {
        if g.len > 0usize {
            g[0usize] = 2.0f64 * (x[0usize] - 1.0f64)
            g[1usize] = 2.0f64 * (x[1usize] - 2.0f64)
            g[2usize] = 2.0f64 * (x[2usize] - 3.0f64)
        }
        ret (x[0usize] - 1.0f64) * (x[0usize] - 1.0f64) + (x[1usize] - 2.0f64) * (x[1usize] - 2.0f64) + (x[2usize] - 3.0f64) * (x[2usize] - 3.0f64)
    }
    if id == 3usize {
        let t = x[1usize] - x[0usize] * x[0usize]
        if g.len > 0usize {
            g[0usize] = 0.0f64 - 400.0f64 * x[0usize] * t - 2.0f64 * (1.0f64 - x[0usize])
            g[1usize] = 200.0f64 * t
        }
        ret 100.0f64 * (t * t) + (1.0f64 - x[0usize]) * (1.0f64 - x[0usize])
    }
    if id == 4usize {
        if g.len > 0usize {
            g[0usize] = 1.0f64
            g[1usize] = 1.0f64
        }
        ret x[0usize] + x[1usize]
    }
    if id == 5usize {
        let s = x[0usize] + x[1usize] + x[2usize]
        if g.len > 0usize {
            g[0usize] = x[0usize] * x[3usize] + x[3usize] * s
            g[1usize] = x[0usize] * x[3usize]
            g[2usize] = x[0usize] * x[3usize] + 1.0f64
            g[3usize] = x[0usize] * s
        }
        ret x[0usize] * x[3usize] * s + x[2usize]
    }
    if id == 7usize {
        if g.len > 0usize {
            g[0usize] = 2.0f64 * x[0usize] + x[1usize]
            g[1usize] = 4.0f64 * x[1usize] + x[0usize]
            g[2usize] = 6.0f64 * x[2usize]
        }
        ret x[0usize] * x[0usize] + 2.0f64 * (x[1usize] * x[1usize]) + 3.0f64 * (x[2usize] * x[2usize]) + x[0usize] * x[1usize]
    }
    if id == 9usize {
        if g.len > 0usize {
            g[0usize] = 2.0f64 * (x[0usize] - 3.0f64) + 0.5f64 * x[1usize]
            g[1usize] = 4.0f64 * (x[1usize] + 1.0f64) + 0.5f64 * x[0usize]
            g[2usize] = 6.0f64 * (x[2usize] - 0.5f64)
        }
        ret (x[0usize] - 3.0f64) * (x[0usize] - 3.0f64) + 2.0f64 * ((x[1usize] + 1.0f64) * (x[1usize] + 1.0f64)) + 3.0f64 * ((x[2usize] - 0.5f64) * (x[2usize] - 0.5f64)) + 0.5f64 * x[0usize] * x[1usize]
    }
    if id == 10usize {
        var s = 0.0f64
        var i = 0usize
        if g.len > 0usize {
            while i < 6usize {
                g[i] = 0.0f64
                i += 1usize
            }
        }
        i = 0usize
        while i < 5usize {
            let t = x[i + 1usize] - x[i] * x[i]
            s = s + (100.0f64 * (t * t) + (1.0f64 - x[i]) * (1.0f64 - x[i]))
            if g.len > 0usize {
                g[i] = g[i] + (0.0f64 - 400.0f64 * x[i] * t - 2.0f64 * (1.0f64 - x[i]))
                g[i + 1usize] = g[i + 1usize] + 200.0f64 * t
            }
            i += 1usize
        }
        ret s
    }
    if g.len > 0usize {
        g[0usize] = 4.0f64 * cube(x[0usize] - 1.0f64) + 2.0f64 * x[0usize]
        g[1usize] = 4.0f64 * cube(x[1usize] - 2.0f64) + 2.0f64 * x[1usize]
        g[2usize] = 4.0f64 * cube(x[2usize] - 3.0f64) + 2.0f64 * x[2usize]
    }
    ret quart(x[0usize] - 1.0f64) + quart(x[1usize] - 2.0f64) + quart(x[2usize] - 3.0f64) + x[0usize] * x[0usize] + x[1usize] * x[1usize] + x[2usize] * x[2usize]
}

fn ineq(ctx: *u8, x: []const f64, r: []f64, j: []f64) {
    let id = usize(*ctx)
    if id == 0usize {
        r[0usize] = cube(2.0f64 * x[0usize]) - x[1usize]
        r[1usize] = cube(1.0f64 - x[0usize]) - x[1usize]
        if j.len > 0usize {
            j[0usize] = 3.0f64 * ((2.0f64 * x[0usize]) * (2.0f64 * x[0usize])) * 2.0f64
            j[1usize] = 0.0f64 - 1.0f64
            j[2usize] = (0.0f64 - 3.0f64) * ((1.0f64 - x[0usize]) * (1.0f64 - x[0usize]))
            j[3usize] = 0.0f64 - 1.0f64
        }
        ret
    }
    if id == 1usize || id == 6usize {
        r[0usize] = x[0usize] * x[0usize] / 4.0f64 + x[1usize] * x[1usize] - 1.0f64
        if j.len > 0usize {
            j[0usize] = x[0usize] / 2.0f64
            j[1usize] = 2.0f64 * x[1usize]
        }
        ret
    }
    if id == 2usize {
        r[0usize] = x[0usize] + x[1usize] + x[2usize] - 4.0f64
        r[1usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] - 2.0f64
        if j.len > 0usize {
            j[0usize] = 1.0f64
            j[1usize] = 1.0f64
            j[2usize] = 1.0f64
            j[3usize] = 2.0f64 * x[0usize]
            j[4usize] = 2.0f64 * x[1usize]
            j[5usize] = 0.0f64
        }
        ret
    }
    if id == 4usize {
        r[0usize] = 1.0f64 - x[0usize] * x[1usize]
        if j.len > 0usize {
            j[0usize] = 0.0f64 - x[1usize]
            j[1usize] = 0.0f64 - x[0usize]
        }
        ret
    }
    // id 5
    r[0usize] = 25.0f64 - x[0usize] * x[1usize] * x[2usize] * x[3usize]
    if j.len > 0usize {
        j[0usize] = 0.0f64 - x[1usize] * x[2usize] * x[3usize]
        j[1usize] = 0.0f64 - x[0usize] * x[2usize] * x[3usize]
        j[2usize] = 0.0f64 - x[0usize] * x[1usize] * x[3usize]
        j[3usize] = 0.0f64 - x[0usize] * x[1usize] * x[2usize]
    }
}

fn eqc(ctx: *u8, x: []const f64, r: []f64, j: []f64) {
    let id = usize(*ctx)
    if id == 5usize {
        r[0usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] + x[2usize] * x[2usize] + x[3usize] * x[3usize] - 40.0f64
        if j.len > 0usize {
            j[0usize] = 2.0f64 * x[0usize]
            j[1usize] = 2.0f64 * x[1usize]
            j[2usize] = 2.0f64 * x[2usize]
            j[3usize] = 2.0f64 * x[3usize]
        }
        ret
    }
    if id == 6usize {
        r[0usize] = x[0usize] - 2.0f64 * x[1usize] + 1.0f64
        if j.len > 0usize {
            j[0usize] = 1.0f64
            j[1usize] = 0.0f64 - 2.0f64
        }
        ret
    }
    r[0usize] = x[0usize] + x[1usize] + x[2usize] - 1.0f64
    r[1usize] = x[0usize] - x[2usize]
    if j.len > 0usize {
        j[0usize] = 1.0f64
        j[1usize] = 1.0f64
        j[2usize] = 1.0f64
        j[3usize] = 1.0f64
        j[4usize] = 0.0f64
        j[5usize] = 0.0f64 - 1.0f64
    }
}

fn chk_x(id: usize, x: []f64) -> usize {
    if id == 3usize {
        x[0usize] = 0.0f64
        x[1usize] = 1.0f64
        x[2usize] = 0.0f64 - 1.0f64
        x[3usize] = 0.5f64
    } else {
        x[0usize] = 1.5f64
        x[1usize] = 0.0f64 - 2.0f64
        x[2usize] = 0.7f64
        x[3usize] = 3.0f64
    }
    if id == 2usize { ret 2usize }
    ret 1usize
}

fn chk_f(ctx: *u8, x: []const f64, out: []f64) {
    if *ctx == 2u8 {
        out[0usize] = x[0usize] + x[1usize] * x[2usize]
        out[1usize] = x[3usize] * x[3usize] + x[0usize] * x[2usize]
        ret
    }
    out[0usize] = x[0usize] * x[1usize] + x[2usize] * x[2usize] * x[2usize] + (x[3usize] * x[3usize]) * x[0usize]
}

fn chk_j(ctx: *u8, x: []const f64, jac: []f64) {
    if *ctx == 2u8 {
        jac[0usize] = 1.0f64 + 0.01f64
        jac[1usize] = x[2usize]
        jac[2usize] = x[1usize]
        jac[3usize] = 0.0f64
        jac[4usize] = x[2usize]
        jac[5usize] = 0.0f64
        jac[6usize] = x[0usize]
        jac[7usize] = 2.0f64 * x[3usize] + 0.5f64
        ret
    }
    jac[0usize] = x[1usize] + x[3usize] * x[3usize]
    jac[1usize] = x[0usize]
    jac[2usize] = 3.0f64 * (x[2usize] * x[2usize])
    jac[3usize] = 2.0f64 * x[3usize] * x[0usize]
    if *ctx == 1u8 { jac[1usize] = jac[1usize] + 0.1f64 }
}

fn chk_answer(a: *mem.Arena, id: usize, what: usize) -> f64 {
    let (x, e1) = mem.alloc[f64](a, 4usize)
    let (ana, e2) = mem.alloc[f64](a, 8usize)
    let (fd, e3) = mem.alloc[f64](a, 8usize)
    let (rel, e4) = mem.alloc[f64](a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    let m = chk_x(id, x)
    var ctx = u8(id)
    let flagged = nl.check_derivatives[u8](a, chk_f, chk_j, &ctx, x, m, 1.0e-4f64, ana, fd, rel)
    if what == 0usize { ret f64(flagged) }
    if what >= 100usize { ret fd[what - 100usize] }
    ret rel[what - 1usize]
}

type Res = struct { val: f64, code: i64, iter: i64, x: []f64 }

fn solve(a: *mem.Arena, algo: usize, id: usize, variant: usize) -> Res {
    let n = dims(id)
    let mi = n_ineq(id)
    let (x, e1) = mem.alloc[f64](a, n)
    let (lb, e2) = mem.alloc[f64](a, n)
    let (ub, e3) = mem.alloc[f64](a, n)
    let (tol, e4) = mem.alloc[f64](a, mi + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        x[i] = x0_of(id, i)
        lb[i] = lb_of(id, i)
        ub[i] = ub_of(id, i)
        i += 1usize
    }
    i = 0usize
    while i < mi + 1usize {
        tol[i] = 1.0e-8f64
        i += 1usize
    }
    var ctx = u8(id)
    var stop = nl.Stop { n: n, minf_max: 0.0f64 - nl.inf(), ftol_rel: 1.0e-13f64, ftol_abs: 0.0f64, xtol_rel: 1.0e-10f64, xtol_abs: x[0usize..0usize], maxeval: 200i64, nevals: 0i64 }
    if variant == 1usize { stop.maxeval = 7i64 }
    if variant == 2usize { stop.minf_max = 1.5f64 }
    var val = 0.0f64
    var code = 0i64
    if algo == 0usize || algo == 1usize {
        let (v, c) = nl.mma_minimize[u8](a, i64(algo), obj, ineq, &ctx, mi, tol, lb, ub, x, &stop, nl.dual_default(), 0i64, 1.0f64, x[0usize..0usize])
        val = v
        code = c
    }
    if algo == 2usize {
        let (v, c) = lk.lbfgs[u8](a, obj, &ctx, lb, ub, x, &stop, 20usize, 0.0f64)
        val = v
        code = c
    }
    if algo == 3usize || algo == 4usize {
        let (v, c) = lk.varmetric[u8](a, obj, &ctx, lb, ub, x, &stop, 20usize, i64(algo) - 2i64, 0.0f64)
        val = v
        code = c
    }
    if algo >= 5usize && algo <= 8usize {
        let k = i64(algo) - 5i64
        let (v, c) = lk.tnewton[u8](a, obj, &ctx, lb, ub, x, &stop, 20usize, 1i64 + k % 2i64, 1i64 + k / 2i64, 0.0f64)
        val = v
        code = c
    }
    if algo == 9usize {
        let (htol, e5) = mem.alloc[f64](a, n_eq(id) + 1usize)
        if e5 != ok { os.exit(4) }
        i = 0usize
        while i < n_eq(id) + 1usize {
            htol[i] = 1.0e-8f64
            i += 1usize
        }
        let (v, c) = sl.slsqp_minimize[u8](a, obj, ineq, eqc, &ctx, mi, tol, n_eq(id), htol, lb, ub, x, &stop)
        val = v
        code = c
    }
    if algo >= 20usize {
        let (htol, e5) = mem.alloc[f64](a, n_eq(id) + 1usize)
        if e5 != ok { os.exit(4) }
        i = 0usize
        while i < n_eq(id) + 1usize {
            htol[i] = 1.0e-8f64
            i += 1usize
        }
        let loc = ag.Local { alg: i64(algo % 20usize), ftol_rel: 1.0e-13f64, ftol_abs: 0.0f64, xtol_rel: 1.0e-10f64, maxeval: 300i64, mf: 20usize }
        stop.maxeval = 2000i64
        let (v, c) = ag.auglag[u8](a, obj, ineq, eqc, &ctx, mi, tol, n_eq(id), htol, lb, ub, x, &stop, loc, algo >= 40usize)
        val = v
        code = c
    }
    ret Res { val: val, code: code, iter: stop.nevals, x: x }
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Res, key: *usize) -> f64 {
    let raw = usize(c.args[0usize])
    let algo = raw % 1000usize
    let variant = raw / 1000usize
    let id = usize(c.args[1usize])
    let what = usize(c.args[2usize])
    if algo == 100usize { ret chk_answer(a, id, what) }
    let k = (variant * 1000usize + algo) * 100usize + id + 1usize
    if *key != k {
        *cache = solve(a, algo, id, variant)
        *key = k
    }
    if what == 0usize { ret cache.val }
    if what == 1usize { ret f64(cache.code) }
    if what == 2usize { ret f64(cache.iter) }
    ret cache.x[what - 3usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nloptr.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    let (z, ez) = mem.alloc[f64](a, 1usize)
    if ez != ok { os.exit(4) }
    var cache = Res { val: 0.0f64, code: 0i64, iter: 0i64, x: z[0usize..0usize] }
    var key = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c, &cache, &key)
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
