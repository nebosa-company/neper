// e.math.numderiv against R's numDeriv: grad, jacobian, hessian and genD with the Richardson,
// simple and complex-step methods. tests/oracle/numderiv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R numderiv`. A case is
// (op, function, method, element, point...) and answers one element of the row-major result.

use e.algo.complex as cx
use e.io
use e.math
use e.math.numderiv as nd
use e.mem
use e.os
use e.test.oracle as oracle

type Fn = struct { id: i64 }

fn outputs(id: i64) -> usize {
    if id == 6i64 { ret 2usize }
    if id == 7i64 { ret 3usize }
    ret 1usize
}

fn real(c: *Fn, x: []const f64, out: []f64) {
    if c.id == 1i64 { out[0usize] = math.sin[f64](x[0usize]) }
    if c.id == 2i64 { out[0usize] = math.exp[f64](x[0usize]) + x[0usize] * (x[1usize] * x[1usize]) }
    if c.id == 3i64 {
        let t = x[1usize] - x[0usize] * x[0usize]
        out[0usize] = 100.0f64 * (t * t) + (1.0f64 - x[0usize]) * (1.0f64 - x[0usize])
    }
    if c.id == 4i64 { out[0usize] = x[0usize] * x[1usize] * x[2usize] + x[0usize] * x[0usize] * x[0usize] }
    if c.id == 5i64 { out[0usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] + x[2usize] * x[2usize] + x[3usize] * x[3usize] }
    if c.id == 6i64 {
        out[0usize] = x[0usize] * x[0usize] + x[1usize]
        out[1usize] = math.sin[f64](x[0usize]) * x[1usize]
    }
    if c.id == 7i64 {
        var i = 0usize
        while i < 3usize {
            out[i] = x[i] * x[i] * x[i] - 2.0f64 * x[i]
            i += 1usize
        }
    }
}

fn real_c(re: f64) -> cx.Complex[f64] { ret cx.make[f64](re, 0.0f64) }

fn complex(c: *Fn, x: []const cx.Complex[f64], out: []cx.Complex[f64]) {
    if c.id == 1i64 { out[0usize] = cx.sin[f64](x[0usize]) }
    if c.id == 2i64 { out[0usize] = cx.add[f64](cx.exp[f64](x[0usize]), cx.mul[f64](x[0usize], cx.mul[f64](x[1usize], x[1usize]))) }
    if c.id == 3i64 {
        let t = cx.sub[f64](x[1usize], cx.mul[f64](x[0usize], x[0usize]))
        let u = cx.sub[f64](real_c(1.0f64), x[0usize])
        out[0usize] = cx.add[f64](cx.mul[f64](real_c(100.0f64), cx.mul[f64](t, t)), cx.mul[f64](u, u))
    }
    if c.id == 4i64 { out[0usize] = cx.add[f64](cx.mul[f64](cx.mul[f64](x[0usize], x[1usize]), x[2usize]), cx.mul[f64](cx.mul[f64](x[0usize], x[0usize]), x[0usize])) }
    if c.id == 5i64 {
        var s = cx.mul[f64](x[0usize], x[0usize])
        var i = 1usize
        while i < 4usize {
            s = cx.add[f64](s, cx.mul[f64](x[i], x[i]))
            i += 1usize
        }
        out[0usize] = s
    }
    if c.id == 6i64 {
        out[0usize] = cx.add[f64](cx.mul[f64](x[0usize], x[0usize]), x[1usize])
        out[1usize] = cx.mul[f64](cx.sin[f64](x[0usize]), x[1usize])
    }
    if c.id == 7i64 {
        var i = 0usize
        while i < 3usize {
            out[i] = cx.sub[f64](cx.mul[f64](cx.mul[f64](x[i], x[i]), x[i]), cx.mul[f64](real_c(2.0f64), x[i]))
            i += 1usize
        }
    }
}

// Method ids as scripts/r_oracle/groups/numderiv.R numbers them: 0 Richardson, 1 d = 0.01 r = 3,
// 2 r = 5 eps = 1e-3, 3 simple, 4 simple eps = 1e-6, 5 complex, 6 Richardson forward,
// 7 Richardson mixed sides, 8 simple mixed sides.
fn mixed(side: []f64, n: usize) {
    let pattern = [4]f64 { 1.0f64, -1.0f64, 0.0f64 / 0.0f64, 1.0f64 }
    var i = 0usize
    while i < n {
        side[i] = pattern[i]
        i += 1usize
    }
}

fn compute(a: *mem.Arena, c: *const oracle.Case) -> []f64 {
    let op = i64(c.args[0usize])
    let id = i64(c.args[1usize])
    let method = i64(c.args[2usize])
    let x = c.args[4usize..c.args.len]
    let n = x.len
    let m = outputs(id)
    var ctx = Fn { id: id }
    let (side, side_error) = mem.alloc[f64](a, n)
    if side_error != ok { os.exit(5) }
    var sides: []f64 = zero
    var o = nd.defaults()
    if method == 1i64 {
        o.d = 0.01f64
        o.r = 3usize
    }
    if method == 2i64 {
        o.r = 5usize
        o.eps = 0.001f64
    }
    if method == 6i64 {
        var i = 0usize
        while i < n {
            side[i] = 1.0f64
            i += 1usize
        }
        sides = side
    }
    if method == 7i64 || method == 8i64 {
        mixed(side, n)
        sides = side
    }
    var simple_eps = 0.0001f64
    if method == 4i64 { simple_eps = 0.000001f64 }
    if op == 2i64 {
        var h = nd.hessian_defaults()
        if method == 1i64 || method == 3i64 {
            h.d = 0.05f64
            h.r = 5usize
        }
        if method == 3i64 {
            h.d = 0.2f64
            h.r = 3usize
        }
        if method >= 2i64 {
            let (r, e) = nd.hessian_complex[Fn](a, &ctx, complex, x, &h)
            if e != ok { os.exit(6) }
            ret r
        }
        if method == 1i64 {
            h.d = 0.05f64
            h.r = 5usize
        }
        let (r, e) = nd.hessian_richardson[Fn](a, &ctx, real, x, &h)
        if e != ok { os.exit(6) }
        ret r
    }
    if op == 3i64 {
        var g = nd.hessian_defaults()
        g.eps = 0.0001f64
        if method == 0i64 { g.d = 0.1f64 }
        if method == 1i64 {
            g.d = 0.02f64
            g.r = 3usize
        }
        let (r, e) = nd.gen_d[Fn](a, &ctx, real, m, x, &g)
        if e != ok { os.exit(6) }
        ret r
    }
    if method == 5i64 {
        if op == 0i64 {
            let (r, e) = nd.grad_complex[Fn](a, &ctx, complex, m, x)
            if e != ok { os.exit(6) }
            ret r
        }
        let (r, e) = nd.jacobian_complex[Fn](a, &ctx, complex, m, x)
        if e != ok { os.exit(6) }
        ret r
    }
    if method == 3i64 || method == 4i64 || method == 8i64 {
        if op == 0i64 {
            let (r, e) = nd.grad_simple[Fn](a, &ctx, real, m, x, sides, simple_eps)
            if e != ok { os.exit(6) }
            ret r
        }
        let (r, e) = nd.jacobian_simple[Fn](a, &ctx, real, m, x, sides, simple_eps)
        if e != ok { os.exit(6) }
        ret r
    }
    if op == 0i64 {
        let (r, e) = nd.grad_richardson[Fn](a, &ctx, real, m, x, sides, &o)
        if e != ok { os.exit(6) }
        ret r
    }
    let (r, e) = nd.jacobian_richardson[Fn](a, &ctx, real, m, x, sides, &o)
    if e != ok { os.exit(6) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/numderiv.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let result = compute(a, c)
        let element = usize(c.args[3usize])
        var got = 0.0f64 / 0.0f64
        if element < result.len { got = result[element] }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 25usize {
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
