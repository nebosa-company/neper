// e.algo.stat.massfam and massnb's family terms against MASS negative.binomial, rnegbin, gamma.shape and gamma.dispersion. The layout of every case is at the top of
// scripts/r_oracle/groups/mass_nbx.R.

use e.algo.rand.r as rng
use e.algo.stat.mass as ms
use e.algo.stat.massfam as mf
use e.algo.stat.massnb as nb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "nblink") {
        let kind = usize(z[0usize])
        let link = usize(z[1usize])
        if kind == 0usize { ret nb.linkfun(link, z[3usize]) }
        if kind == 1usize { ret nb.linkinv(link, z[3usize]) }
        ret nb.mu_eta(link, z[3usize])
    }
    if str.eq(c.name, "nbvalid") {
        let kind = usize(z[0usize])
        let n = usize(z[2usize])
        let v = z[3usize..3usize + n]
        if kind == 0usize {
            if mf.nb_validmu(v) { ret 1.0f64 }
            ret 0.0f64
        }
        if kind == 1usize {
            if mf.nb_valideta(usize(z[1usize]), v) { ret 1.0f64 }
            ret 0.0f64
        }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f64(i + 1usize) * mf.nb_mustart(v[i])
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "rnb") {
        let n = usize(z[1usize])
        let nmu = usize(z[2usize])
        let nth = usize(z[3usize])
        let (out, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan() }
        var g: rng.Rng = zero
        rng.seed(&g, i64(z[0usize]))
        let e2 = mf.rnegbin(a, &g, n, z[4usize..4usize + nmu], z[4usize + nmu..4usize + nmu + nth], out)
        if e2 != ok { ret nan() }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            if usize(z[z.len - 1usize]) == 0usize { s += out[i] } else { s += f64(i + 1usize) * out[i] }
            i += 1usize
        }
        ret s
    }
    let n = usize(z[3usize])
    let y = z[6usize..6usize + n]
    let u = z[6usize + n..6usize + 2usize * n]
    let w = z[6usize + 2usize * n..6usize + 3usize * n]
    let mode = usize(z[2usize])
    if mode == 2usize { ret mf.gamma_dispersion(y, u, w, z[4usize], z[5usize], usize(z[0usize]), z[1usize]) }
    var out: [2]f64 = zero
    ms.gamma_shape_ex(y, u, w, z[4usize], z[5usize], usize(z[0usize]), z[1usize], out[0usize..2usize])
    ret out[mode]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_nbx.json")
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
                var shown = *c
                if shown.args.len > 12usize { shown.args = c.args[0usize..12usize] }
                let _ = io.print(oracle.describe(a, &shown, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
