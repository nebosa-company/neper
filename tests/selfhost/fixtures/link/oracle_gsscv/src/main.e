// e.algo.stat.gsscv gssanova (cross-validated KL) against R gss gssanova. tests/oracle/gsscv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gsscv`; the layout is at the top of scripts/r_oracle/groups/gsscv.R.

use e.algo.stat.gss as gss
use e.algo.stat.gssglm1 as g1
use e.algo.stat.gsscv as cv
use e.algo.stat.gssse as sse
use e.io
use e.math
use e.mem
use e.algo.rand.r as rr
use e.os
use e.str
use e.test.oracle as oracle

type Res = struct { g: g1.Gs1, pred: []f64, se: []f64, nq: usize, n0: usize, m: usize, nb: usize, ids: []i64 }

fn solve(a: *mem.Arena, z: []const f64, r: *Res) -> err {
    let fam = usize(z[0usize])
    let model = usize(z[1usize])
    let alpha = z[2usize]
    let n = usize(z[3usize])
    let nb = usize(z[4usize])
    let m = usize(z[5usize])
    let seed = i64(z[6usize])
    let skip = z[7usize] > 0.5f64
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    let x = z[8usize..8usize + n * dim]
    let y = z[8usize + n * dim..8usize + n * dim + n]
    let xo = z[8usize + n * dim + n..8usize + n * dim + n + m * dim]
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    let (ids, se) = rr.sample_int(a, &rng, i64(n), i64(nb), false)
    if se != ok { ret se }
    let (id, ie) = mem.alloc[usize](a, nb + 1usize)
    let (xb, xe) = mem.alloc[f64](a, nb * dim + 1usize)
    if ie != ok { ret ie }
    if xe != ok { ret xe }
    var i = 0usize
    while i < nb {
        id[i] = usize(ids[i]) - 1usize
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
    var g: g1.Gs1 = zero
    try cv.gssanova(a, fam, d.s, d.q, id, d.nq, y, n, d.n0, nb, alpha, skip, &g)
    let (pred, pe) = mem.alloc[f64](a, m + 1usize)
    let (sev, se2) = mem.alloc[f64](a, m + 1usize)
    if pe != ok { ret pe }
    if se2 != ok { ret se2 }
    gss.predict1(&g.fit, d1.s, d1.q, d.nq, d.n0, nb, m, pred)
    try sse.fit_se(a, &g.fit, n, d.n0, nb)
    try sse.predict1_se(a, &g.fit, d1.s, d1.q, d.nq, d.n0, nb, m, sev)
    r.g = g
    r.pred = pred
    r.se = sev
    r.nq = d.nq
    r.n0 = d.n0
    r.m = m
    r.nb = nb
    r.ids = ids
    ret ok
}

fn answer(r: *const Res, idx: usize) -> f64 {
    let f = &r.g.fit
    if idx == 0usize { ret f.nlambda }
    if idx == 1usize { ret f.score }
    if idx == 2usize { ret f.varht }
    if idx < 3usize + r.nq { ret f.theta[idx - 3usize] }
    var j = idx - 3usize - r.nq
    if j < r.n0 { ret f.d[j] }
    j = j - r.n0
    if j < 3usize { ret r.g.eta[j] }
    j = j - 3usize
    if j < 3usize { ret r.g.w[j] }
    j = j - 3usize
    if j < r.m { ret r.pred[j] }
    j = j - r.m
    if j < r.m { ret r.se[j] }
    let k = j - r.m
    if k == 0usize { ret f64(r.nb) }
    let cnt = r.ids.len
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < cnt {
        s1 += f64(r.ids[i])
        s2 += f64(r.ids[i]) * f64(i + 1usize)
        i += 1usize
    }
    if k == 1usize { ret s1 }
    if k == 2usize { ret s2 }
    if k == 3usize { ret f64(r.ids[0usize]) }
    ret f64(r.ids[cnt - 1usize])
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
    let _ = str.push(&b, " skip ")
    let _ = str.push_f64(&b, z[7usize])
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/gsscv.json")
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
