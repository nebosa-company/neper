// e.algo.stat.mcmcpackmh against MCMCmetrop1R. tests/oracle/mcmcpackmh.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackmh`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackmh.R.


use e.algo.stat.mcmcpackmh as mh
use e.algo.stat.mcmcpacksamp as ms
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Target = struct { kind: usize, np: usize, mu1: []const f64, mu2: []const f64, p: []const f64 }

fn quad(t: *Target, th: []const f64, mu: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.np {
        var r = 0.0f64
        var j = 0usize
        while j < t.np {
            r += t.p[i * t.np + j] * (th[j] - mu[j])
            j += 1usize
        }
        s += (th[i] - mu[i]) * r
        i += 1usize
    }
    ret s
}

fn logdens(t: *Target, th: []const f64) -> f64 {
    if t.kind == 0usize { ret -0.5f64 * quad(t, th, t.mu1) }
    ret math.exp[f64](-0.5f64 * quad(t, th, t.mu1)) + 0.6f64 * math.exp[f64](-0.5f64 * quad(t, th, t.mu2))
}

// maxfun of R is the log of the density; the minimiser takes its negative
fn negobj(t: *Target, th: []const f64) -> f64 {
    if t.kind == 0usize { ret -1.0f64 * logdens(t, th) }
    ret -1.0f64 * math.log[f64](logdens(t, th))
}

fn neggrad(t: *Target, th: []const f64, g: []f64) {
    var x: [8]f64 = zero
    var i = 0usize
    while i < t.np {
        x[i] = th[i]
        i += 1usize
    }
    mh.num_grad[Target](t, negobj, x[0usize..t.np], g)
}

fn wsum(m: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m.len {
        s += f64(i + 1usize) * m[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    var g: ms.Sc = zero
    ms.sc_seed(&g, u64(z[0usize]))
    let kind = usize(z[1usize])
    let np = usize(z[2usize])
    let burn = usize(z[3usize])
    let mc = usize(z[4usize])
    let thin = usize(z[5usize])
    var o = 6usize
    let tune = z[o..o + np]
    o += np
    let v = z[o..o + np * np]
    o += np * np
    let th0 = z[o..o + np]
    o += np
    var t: Target = zero
    t.kind = kind
    t.np = np
    t.mu1 = z[o..o + np]
    t.mu2 = z[o + np..o + 2usize * np]
    t.p = z[o + 2usize * np..o + 2usize * np + np * np]
    let (out, e1) = mem.alloc[f64](a, (mc / thin) * np)
    if e1 != ok { ret nan }
    if str.eq(c.name, "mhdef") {
        let (vd, e2) = mem.alloc[f64](a, np * np)
        if e2 != ok { ret nan }
        if mh.default_v[Target](a, &t, negobj, neggrad, th0, vd) != ok { ret nan }
        if mh.metrop1r[Target](a, &g, &t, logdens, th0, vd, tune, kind == 0usize, burn, mc, thin, out) != ok { ret nan }
        ret wsum(out)
    }
    if mh.metrop1r[Target](a, &g, &t, logdens, th0, v, tune, kind == 0usize, burn, mc, thin, out) != ok { ret nan }
    ret wsum(out)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackmh.json")
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
