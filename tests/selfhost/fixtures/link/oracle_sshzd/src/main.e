// e.algo.stat.gsshzd sshzd against R gss sshzd. tests/oracle/sshzd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sshzd`; the layout is at the top of scripts/r_oracle/groups/sshzd.R.

use e.algo.stat.gsshzd as hz
use e.algo.stat.gssden as den
use e.io
use e.math
use e.mem
use e.algo.rand.r as rr
use e.os
use e.str
use e.test.oracle as oracle

type Res = struct { f: hz.HzFit, rate: []f64, nq: usize, nnull: usize, nxi: usize, m: usize, ids: []i64 }

fn solve(a: *mem.Arena, z: []const f64, r: *Res) -> err {
    let model = usize(z[0usize])
    let n = usize(z[1usize])
    let nb = usize(z[2usize])
    let seed = i64(z[3usize])
    let skip = z[4usize] > 0.5f64 && z[4usize] < 1.5f64
    let fixed = z[4usize] > 1.5f64
    let m = usize(z[5usize])
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    let tm = z[6usize..6usize + n]
    let st = z[6usize + n..6usize + 2usize * n]
    var xc: []const f64 = zero
    var o = 6usize + 2usize * n
    if dim == 2usize {
        xc = z[o..o + n]
        o += n
    }
    let (xn, e0) = den.zeros(a, m * dim)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < m {
        xn[i] = z[o + i]
        if dim == 2usize { xn[m + i] = z[o + m + i] }
        i += 1usize
    }
    var nt = 0usize
    i = 0usize
    while i < n {
        if st[i] > 0.5f64 { nt += 1usize }
        i += 1usize
    }
    // sample((1:n)[status], nb): the draws index the failures
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    let (pos, se) = rr.sample_int(a, &rng, i64(nt), i64(nb), false)
    if se != ok { ret se }
    let (idp, ie) = mem.alloc[usize](a, nb + 1usize)
    let (ids, ie2) = mem.alloc[i64](a, nb + 1usize)
    if ie != ok { ret ie }
    if ie2 != ok { ret ie2 }
    i = 0usize
    while i < nb {
        idp[i] = usize(pos[i]) - 1usize
        i += 1usize
    }
    var at = 0usize
    var k = 0usize
    i = 0usize
    while i < n {
        if st[i] > 0.5f64 {
            k = 0usize
            while k < nb {
                if idp[k] == at { ids[k] = i64(i + 1usize) }
                k += 1usize
            }
            at += 1usize
        }
        i += 1usize
    }
    var f: hz.HzFit = zero
    var fx = z[0usize..0usize]
    if fixed { fx = z[o + m * dim..z.len] }
    try hz.sshzd(a, model, n, tm, st, xc, idp, nb, 1.4f64, 0.0000001f64, 30usize, skip, fx, &f)
    let (rate, pe) = den.zeros(a, m)
    if pe != ok { ret pe }
    try hz.hzd_rate(a, &f, xn, m, rate)
    r.f = f
    r.rate = rate
    r.nq = f.nq
    r.nnull = f.nnull
    r.nxi = f.nxi
    r.m = m
    r.ids = ids[0usize..nb]
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
    if j == 0usize { ret r.f.cv }
    j = j - 1usize
    if j < r.m { ret r.rate[j] }
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/sshzd.json")
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
