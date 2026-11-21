// e.algo.stat.gss gssanova0 against R gss gssanova0 (binomial, Poisson, Gamma and inverse Gaussian with cubic marginals). tests/oracle/gssglm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gssglm`; the layout is at the top of scripts/r_oracle/groups/gssglm.R.

use e.algo.stat.gss as gss
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Res = struct { g: gss.Gss0, p: gss.Pred, nq: usize, n0: usize, m: usize }

fn solve(a: *mem.Arena, z: []const f64, r: *Res) -> err {
    let fam = usize(z[0usize])
    let model = usize(z[1usize])
    let method = usize(z[2usize])
    let n = usize(z[3usize])
    let m = usize(z[4usize])
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    let x = z[5usize..5usize + n * dim]
    let y = z[5usize + n * dim..5usize + n * dim + n]
    let xo = z[5usize + n * dim + n..5usize + n * dim + n + m * dim]
    var d: gss.Design = zero
    try gss.design(a, model, x, n, x, n, x, n, &d)
    var d1: gss.Design = zero
    try gss.design(a, model, x, n, xo, m, x, n, &d1)
    var d2: gss.Design = zero
    try gss.design(a, model, x, n, xo, m, xo, m, &d2)
    var g: gss.Gss0 = zero
    try gss.gssanova0(a, fam, d.s, d.q, d.nq, y, n, d.n0, method, 1.0f64, 0.0000001f64, 30usize, &g)
    let (rd, re) = mem.alloc[f64](a, d.nq * m + 1usize)
    if re != ok { ret re }
    var k = 0usize
    while k < d.nq {
        var i = 0usize
        while i < m {
            rd[k * m + i] = d2.q[k * m * m + i + i * m]
            i += 1usize
        }
        k += 1usize
    }
    let (wv, we) = mem.alloc[f64](a, n + 1usize)
    if we != ok { ret we }
    var wi = 0usize
    while wi < n {
        wv[wi] = math.sqrt[f64](g.w[wi])
        wi += 1usize
    }
    var p: gss.Pred = zero
    try gss.predict0(a, &g.fit, d.s, d.q, d1.s, d1.q, rd, wv, n, d.n0, d.nq, m, &p)
    r.g = g
    r.p = p
    r.nq = d.nq
    r.n0 = d.n0
    r.m = m
    ret ok
}

fn answer(r: *const Res, idx: usize) -> f64 {
    if idx == 0usize { ret r.g.fit.nlaht }
    if idx == 1usize { ret r.g.fit.score }
    if idx == 2usize { ret r.g.fit.varht }
    if idx < 3usize + r.nq { ret r.g.fit.theta[idx - 3usize] }
    var j = idx - 3usize - r.nq
    if j < r.n0 { ret r.g.fit.d[j] }
    j -= r.n0
    if j == 0usize { ret f64(r.g.iter) }
    j -= 1usize
    if j < 3usize { ret r.g.eta[j] }
    j -= 3usize
    if j < 3usize { ret r.g.w[j] }
    j -= 3usize
    if j < r.m { ret r.p.fit[j] }
    ret r.p.se[j - r.m]
}

fn short(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let z = c.args
    let _ = str.push(&b, "fam ")
    let _ = str.push_f64(&b, z[0usize])
    let _ = str.push(&b, " model ")
    let _ = str.push_f64(&b, z[1usize])
    let _ = str.push(&b, " n ")
    let _ = str.push_f64(&b, z[3usize])
    let _ = str.push(&b, " idx ")
    let _ = str.push_f64(&b, z[z.len - 1usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn same(p: []const f64, q: []const f64) -> bool {
    if p.len != q.len { ret false }
    var i = 0usize
    while i < p.len {
        if p[i] != q[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gssglm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let base = mem.mark(a)
    var failures = 0usize
    var res: Res = zero
    var have = false
    var prev: []const f64 = golden.cases[0usize].args
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let z = c.args
        let key = z[0usize..z.len - 1usize]
        var got = 0.0f64 / 0.0f64
        if !have || !same(prev, key) {
            mem.reset(a, base)
            have = false
            if solve(a, key, &res) == ok { have = true }
            prev = key
        }
        if have { got = answer(&res, usize(z[z.len - 1usize])) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(short(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
