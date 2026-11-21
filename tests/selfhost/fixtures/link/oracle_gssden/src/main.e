// e.algo.stat.gssden ssden against R gss ssden. tests/oracle/gssden.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gssden`; the layout is at the top of scripts/r_oracle/groups/gssden.R.

use e.algo.stat.gss as gss
use e.algo.stat.gssden as den
use e.algo.stat.cubaturepkg as cub
use e.io
use e.math
use e.mem
use e.algo.rand.r as rr
use e.os
use e.str
use e.test.oracle as oracle

type Res = struct { f: den.DenFit, dens: []f64, nq: usize, nnull: usize, nxi: usize, m: usize, ids: []i64 }

fn solve(a: *mem.Arena, z: []const f64, r: *Res) -> err {
    let model = usize(z[0usize])
    let n = usize(z[1usize])
    let nb = usize(z[2usize])
    let seed = i64(z[3usize])
    let skip = z[4usize] > 0.5f64
    let ng = usize(z[5usize])
    let m = usize(z[6usize])
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    let x = z[7usize..7usize + n * dim]
    let xo = z[7usize + n * dim..7usize + n * dim + m * dim]
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    let (ids, se) = rr.sample_int(a, &rng, i64(n), i64(nb), false)
    if se != ok { ret se }
    let (idb, ie) = mem.alloc[usize](a, nb + 1usize)
    if ie != ok { ret ie }
    var i = 0usize
    while i < nb {
        idb[i] = usize(ids[i]) - 1usize
        i += 1usize
    }
    let (lo, e1) = den.zeros(a, 2usize)
    let (hi, e2) = den.zeros(a, 2usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var v = 0usize
    while v < dim {
        let mn = gss.dmin(x, v * n, n)
        let mx = gss.dmax(x, v * n, n)
        lo[v] = mn - 0.05f64 * (mx - mn)
        hi[v] = mx + 0.05f64 * (mx - mn)
        v += 1usize
    }
    // the quadrature: Gauss-Legendre 200 in one dimension, the ng by ng tensor grid in two
    var g = ng
    if dim == 1usize { g = 200usize }
    let (gx, e3) = den.zeros(a, g)
    let (gw, e4) = den.zeros(a, g)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    cub.gauss_legendre(g, gx, gw)
    var nqd = g
    if dim == 2usize { nqd = g * g }
    let (qx, e5) = den.zeros(a, nqd * dim)
    let (qw, e6) = den.zeros(a, nqd)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if dim == 1usize {
        i = 0usize
        while i < g {
            qx[i] = lo[0usize] + (hi[0usize] - lo[0usize]) * (gx[i] + 1.0f64) / 2.0f64
            qw[i] = (hi[0usize] - lo[0usize]) * gw[i] / 2.0f64
            i += 1usize
        }
    } else {
        var j = 0usize
        while j < g {
            i = 0usize
            while i < g {
                let at = i + j * g
                qx[at] = lo[0usize] + (hi[0usize] - lo[0usize]) * (gx[i] + 1.0f64) / 2.0f64
                qx[nqd + at] = lo[1usize] + (hi[1usize] - lo[1usize]) * (gx[j] + 1.0f64) / 2.0f64
                qw[at] = ((hi[0usize] - lo[0usize]) * gw[i] / 2.0f64) * ((hi[1usize] - lo[1usize]) * gw[j] / 2.0f64)
                i += 1usize
            }
            j += 1usize
        }
    }
    var f: den.DenFit = zero
    try den.ssden(a, model, x, n, idb, nb, lo, hi, qx, qw, nqd, 1.4f64, 0.0000001f64, 30usize, skip, &f)
    let (dens, pe) = den.zeros(a, m)
    if pe != ok { ret pe }
    try den.den_eval(a, model, &f, x, n, idb, lo, hi, xo, m, dens)
    r.f = f
    r.dens = dens
    r.nq = f.nq
    r.nnull = f.nnull
    r.nxi = f.nxi
    r.m = m
    r.ids = ids
    ret ok
}

fn answer(r: *const Res, idx: usize) -> f64 {
    if idx == 0usize { ret r.f.lambda }
    if idx < 1usize + r.nq { ret r.f.theta[idx - 1usize] }
    var j = idx - 1usize - r.nq
    if j < r.nxi { ret r.f.c[j] }
    j = j - r.nxi
    if j < r.nnull { ret r.f.d[j] }
    j = j - r.nnull
    if j == 0usize { ret r.f.int }
    if j == 1usize { ret r.f.cv }
    j = j - 2usize
    if j < r.m { ret r.dens[j] }
    let k = j - r.m
    if k == 0usize { ret f64(r.nxi) }
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
    let _ = str.push(&b, "model ")
    let _ = str.push_f64(&b, z[0usize])
    let _ = str.push(&b, " n ")
    let _ = str.push_f64(&b, z[1usize])
    let _ = str.push(&b, " skip ")
    let _ = str.push_f64(&b, z[4usize])
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/gssden.json")
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
