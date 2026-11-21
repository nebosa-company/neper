// e.algo.stat.gss ssanova (approximate basis) against R gss ssanova. tests/oracle/gssapx.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gssapx`; the layout is at the top of scripts/r_oracle/groups/gssapx.R.

use e.algo.stat.gss as gss
use e.algo.stat.gssse as sse
use e.io
use e.math
use e.mem
use e.algo.rand.r as rr
use e.os
use e.str
use e.test.oracle as oracle

type Res = struct { f: gss.Ss1, pred: []f64, se: []f64, nq: usize, n0: usize, m: usize, nbf: f64, ids: []i64 }

fn solve(a: *mem.Arena, z: []const f64, r: *Res) -> err {
    let model = usize(z[0usize])
    let method = usize(z[1usize])
    let alpha = z[2usize]
    let n = usize(z[3usize])
    let nb = usize(z[4usize])
    let m = usize(z[5usize])
    var dim = 2usize
    if model == 1usize || model == 4usize { dim = 1usize }
    let x = z[7usize..7usize + n * dim]
    let y = z[7usize + n * dim..7usize + n * dim + n]
    let idz = z[7usize + n * dim + n..7usize + n * dim + n + nb]
    let xo = z[7usize + n * dim + n + nb..7usize + n * dim + n + nb + m * dim]
    let (id, ie) = mem.alloc[usize](a, nb + 1usize)
    let (xb, xe) = mem.alloc[f64](a, nb * dim + 1usize)
    if ie != ok { ret ie }
    if xe != ok { ret xe }
    var i = 0usize
    var drawn: []i64 = zero
    if z[6usize] >= 2.0f64 {
        // the basis ssanova draws itself: set.seed(seed); sample(n, nbasis)
        var rng: rr.Rng = zero
        rr.seed(&rng, i64(z[6usize]))
        let (ids, se) = rr.sample_int(a, &rng, i64(n), i64(nb), false)
        if se != ok { ret se }
        drawn = ids
    }
    while i < nb {
        id[i] = usize(idz[i]) - 1usize
        if z[6usize] >= 2.0f64 { id[i] = usize(drawn[i]) - 1usize }
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
    if d.nq == 1usize {
        let (q, qe) = mem.alloc[f64](a, nb * nb + 1usize)
        if qe != ok { ret qe }
        var j = 0usize
        while j < nb {
            i = 0usize
            while i < nb {
                q[i + j * nb] = d.q[id[i] + j * n]
                i += 1usize
            }
            j += 1usize
        }
        try gss.sspreg1(a, d.s, d.q, q, y, n, d.n0, nb, method, alpha, 0.09f64, &f)
    } else {
        try gss.mspreg1(a, d.s, d.q, id, d.nq, y, n, d.n0, nb, method, alpha, 0.09f64, z[6usize] > 0.5f64, &f)
    }
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
    r.nq = d.nq
    r.n0 = d.n0
    r.m = m
    var nbf = math.ceil[f64](10.0f64 * math.pow[f64](f64(n), 2.0f64 / 9.0f64))
    if nbf < 30.0f64 { nbf = 30.0f64 }
    if nbf >= f64(n) { nbf = f64(n) }
    r.nbf = nbf
    r.ids = drawn
    ret ok
}

fn answer(r: *const Res, idx: usize) -> f64 {
    if idx == 0usize { ret r.f.nlambda }
    if idx == 1usize { ret r.f.score }
    if idx == 2usize { ret r.f.varht }
    if idx < 3usize + r.nq { ret r.f.theta[idx - 3usize] }
    let j = idx - 3usize - r.nq
    if j < r.n0 { ret r.f.d[j] }
    if j - r.n0 < r.m { ret r.pred[j - r.n0] }
    if j - r.n0 - r.m < r.m { ret r.se[j - r.n0 - r.m] }
    let k = j - r.n0 - 2usize * r.m
    if k == 0usize { ret r.nbf }
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
    let _ = str.push(&b, " method ")
    let _ = str.push_f64(&b, z[1usize])
    let _ = str.push_f64(&b, z[6usize])
    let _ = str.push(&b, " alpha ")
    let _ = str.push_f64(&b, z[2usize])
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

fn check_file(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
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
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    let f1 = check_file(a, "tests/oracle/gssapx.json")
    let f2 = check_file(a, "tests/oracle/gssskip.json")
    if f1 + f2 > 0usize { os.exit(1) }
    ret ok
}
