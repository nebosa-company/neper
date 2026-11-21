// e.algo.stat.gss spfix: the ssanova fit at R's converged nlambda and theta (no search) against R gss ssanova. tests/oracle/gssfix.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gssfix`; the layout is at the top of scripts/r_oracle/groups/gssfix.R.

use e.algo.stat.gss as gss
use e.algo.stat.gssse as sse
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Res = struct { f: gss.Ss1, pred: []f64, se: []f64, n0: usize, m: usize }

fn nq_of(model: usize) -> usize {
    if model == 3usize || model == 6usize { ret 5usize }
    if model == 2usize || model == 5usize { ret 2usize }
    ret 1usize
}

fn solve(a: *mem.Arena, z: []const f64, r: *Res) -> err {
    let model = usize(z[0usize])
    let method = usize(z[1usize])
    let alpha = z[2usize]
    let n = usize(z[3usize])
    let nb = usize(z[4usize])
    let m = usize(z[5usize])
    var dim = 2usize
    if model == 1usize || model == 4usize { dim = 1usize }
    let nq = nq_of(model)
    let x = z[7usize..7usize + n * dim]
    let y = z[7usize + n * dim..7usize + n * dim + n]
    let idz = z[7usize + n * dim + n..7usize + n * dim + n + nb]
    let xo = z[7usize + n * dim + n + nb..7usize + n * dim + n + nb + m * dim]
    let fx = z[7usize + n * dim + n + nb + m * dim..z.len]
    let (id, ie) = mem.alloc[usize](a, nb + 1usize)
    let (xb, xe) = mem.alloc[f64](a, nb * dim + 1usize)
    if ie != ok { ret ie }
    if xe != ok { ret xe }
    var i = 0usize
    while i < nb {
        id[i] = usize(idz[i]) - 1usize
        var v = 0usize
        while v < dim {
            xb[i + v * nb] = x[id[i] + v * n]
            v += 1usize
        }
        i += 1usize
    }
    var d: gss.Design = zero
    try gss.design(a, model, x, n, x, n, xb, nb, &d)
    var d1: gss.Design = zero
    try gss.design(a, model, x, n, xo, m, xb, nb, &d1)
    var f: gss.Ss1 = zero
    try gss.spfix(a, d.s, d.q, id, d.nq, y, n, d.n0, nb, method, alpha, 0.09f64, fx[1usize..1usize + nq], fx[0usize], &f)
    let (pred, pe) = mem.alloc[f64](a, m + 1usize)
    if pe != ok { ret pe }
    gss.predict1(&f, d1.s, d1.q, d.nq, d.n0, nb, m, pred)
    let (sev, sve) = mem.alloc[f64](a, m + 1usize)
    if sve != ok { ret sve }
    try sse.fit_se(a, &f, n, d.n0, nb)
    try sse.predict1_se(a, &f, d1.s, d1.q, d.nq, d.n0, nb, m, sev)
    r.f = f
    r.pred = pred
    r.se = sev
    r.n0 = d.n0
    r.m = m
    ret ok
}

fn answer(r: *const Res, idx: usize) -> f64 {
    if idx == 0usize { ret r.f.score }
    if idx == 1usize { ret r.f.varht }
    let j = idx - 2usize
    if j < r.n0 { ret r.f.d[j] }
    if j - r.n0 < r.m { ret r.pred[j - r.n0] }
    ret r.se[j - r.n0 - r.m]
}

fn short(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let z = c.args
    let _ = str.push(&b, "model ")
    let _ = str.push_f64(&b, z[0usize])
    let _ = str.push(&b, " method ")
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/gssfix.json")
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
            if failures <= 80usize {
                let _ = io.print(short(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
