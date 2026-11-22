// e.algo.stat.fixestpkg against fixest. tests/oracle/fixest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fixest`; the argument layout is at the top of scripts/r_oracle/groups/fixest.R.

use e.algo.stat.fixestpkg as fx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn ws(v: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn codes(a: *mem.Arena, z: []const f64, at: usize, len: usize) -> ([]usize, err) {
    let (u, e1) = mem.alloc[usize](a, len + 1usize)
    var i = 0usize
    while i < len {
        u[i] = usize(z[at + i])
        i += 1usize
    }
    ret (u, e1)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let fam = usize(z[0usize])
    let n = usize(z[1usize])
    let nx = usize(z[2usize])
    let ne = usize(z[3usize])
    let nz = usize(z[4usize])
    let nf = usize(z[5usize])
    let vk = usize(z[6usize])
    let ncl = usize(z[7usize])
    let lag = usize(z[8usize])
    let h9 = z[9usize]
    let h10 = z[10usize]
    let p = nx + ne
    let yv = z[11usize..11usize + n]
    let xv = z[11usize + n..11usize + n + n * nx]
    var at = 11usize + n + n * nx
    let sunab = str.eq(c.name, "sunab_coef") || str.eq(c.name, "sunab_se")
    var cohv = z[0usize..0usize]
    var perv = z[0usize..0usize]
    var env = z[0usize..0usize]
    var ziv = z[0usize..0usize]
    if sunab {
        cohv = z[at..at + n]
        perv = z[at + n..at + 2usize * n]
        at += 2usize * n
    } else {
        env = z[at..at + n * ne]
        ziv = z[at + n * ne..at + n * ne + n * nz]
        at += n * ne + n * nz
    }
    let (fe, e1) = codes(a, z, at, n * nf)
    let (cl, e2) = codes(a, z, at + n * nf, n * ncl)
    if e1 != ok || e2 != ok { ret nan }
    at += n * nf + n * ncl
    var tg = 0usize
    var j = 0usize
    let (sizes, e0) = mem.alloc[usize](a, nf + 1usize)
    if e0 != ok { ret nan }
    while j < nf {
        var mx = 0usize
        var i = 0usize
        while i < n {
            if fe[i * nf + j] + 1usize > mx { mx = fe[i * nf + j] + 1usize }
            i += 1usize
        }
        sizes[j] = mx
        tg += mx
        j += 1usize
    }
    if sunab {
        let (so, e3) = mem.alloc[f64](a, 81usize)
        if e3 != ok { ret nan }
        if fx.sunab(a, yv, xv, nx, cohv, perv, h9, fe, nf, vk, cl, ncl, lag, so) != ok { ret nan }
        let m = usize(so[0usize])
        if str.eq(c.name, "sunab_coef") { ret ws(so[1usize..1usize + m], m) }
        ret ws(so[1usize + m..1usize + 2usize * m], m)
    }
    let (out, e4) = mem.alloc[f64](a, fx.out_len(p, tg))
    if e4 != ok { ret nan }
    if fx.fit(a, fam, yv, xv, nx, env, ne, ziv, nz, fe, nf, vk, cl, ncl, lag, out) != ok { ret nan }
    if str.eq(c.name, "coef") { ret ws(out, p) }
    if str.eq(c.name, "se") { ret ws(out[p..2usize * p], p) }
    if str.eq(c.name, "t") { ret ws(out[2usize * p..3usize * p], p) }
    if str.eq(c.name, "p") { ret ws(out[3usize * p..4usize * p], p) }
    if str.eq(c.name, "df") { ret out[4usize * p] }
    if str.eq(c.name, "kfull") { ret out[4usize * p + 1usize] }
    if str.eq(c.name, "kcl") { ret out[4usize * p + 2usize] }
    if str.eq(c.name, "dev") { ret out[4usize * p + 3usize] }
    if str.eq(c.name, "wald_stat") || str.eq(c.name, "wald_p") {
        let (wo, e8) = mem.alloc[f64](a, 4usize)
        if e8 != ok { ret nan }
        if fx.wald(a, out, p, usize(h9), usize(h10), wo) != ok { ret nan }
        if str.eq(c.name, "wald_stat") { ret wo[0usize] }
        ret wo[1usize]
    }
    if str.eq(c.name, "pred") {
        let m = usize(h9)
        let (xn, e5) = mem.alloc[f64](a, m * p + 1usize)
        let (fen, e6) = codes(a, z, at + m * p, m * nf)
        let (po, e7) = mem.alloc[f64](a, m)
        if e5 != ok || e6 != ok || e7 != ok { ret nan }
        var i2 = 0usize
        while i2 < m * p {
            xn[i2] = z[at + i2]
            i2 += 1usize
        }
        fx.predict(out, p, nf, sizes[0usize..nf], xn, fen, m, fam, h10 > 0.5f64, po)
        ret ws(po, m)
    }
    ret nan
}

fn describe(a: *mem.Arena, c: *const oracle.Case, got: f64, at: usize) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push_f64(&b, f64(at))
    let _ = str.push(&b, " ")
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, " h=")
    var k = 0usize
    while k < 11usize {
        let _ = str.push_f64(&b, c.args[k])
        let _ = str.push(&b, ",")
        k += 1usize
    }
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " R ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fixest.json")
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
            if failures <= 40usize {
                let _ = io.print(describe(a, c, got, at))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
