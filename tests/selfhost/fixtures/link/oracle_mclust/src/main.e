// e.algo.stat.mclustpkg against mclust. tests/oracle/mclust.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust`; the layout is at the top of scripts/r_oracle/groups/mclust.R.

use e.algo.stat.mclustpkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "npar") { ret mc.n_mclust_params(mc.model_name(usize(z[0usize])), z[1usize], z[2usize], z[3usize] != 0.0f64, z[4usize] != 0.0f64) }
    if str.eq(c.name, "bic") { ret mc.bic(mc.model_name(usize(z[0usize])), z[1usize], z[2usize], z[3usize], z[4usize], z[5usize] != 0.0f64, z[6usize] != 0.0f64) }
    if str.eq(c.name, "ari") {
        let n = usize(z[0usize])
        let (x, e1) = mem.alloc[usize](a, n)
        let (y, e2) = mem.alloc[usize](a, n)
        if e1 != ok || e2 != ok { ret nan }
        var i = 0usize
        while i < n {
            x[i] = usize(z[1usize + i])
            y[i] = usize(z[1usize + n + i])
            i += 1usize
        }
        ret mc.adjusted_rand_index(a, x, y)
    }
    if str.eq(c.name, "map") {
        let n = usize(z[0usize])
        let k = usize(z[1usize])
        let (o, e) = mem.alloc[usize](a, n)
        if e != ok { ret nan }
        mc.map(z[2usize..2usize + n * k], n, k, o)
        ret f64(o[usize(z[2usize + n * k])])
    }
    if str.eq(c.name, "mbic") {
        // (n, p, g, model code, X[n p] column-major)
        let bn = usize(z[0usize])
        let bp = usize(z[1usize])
        ret mc.bic_hc_eii(a, z[4usize..4usize + bn * bp], bn, bp, usize(z[2usize]), usize(z[3usize]))
    }
    if str.eq(c.name, "hc") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (o, e) = mem.alloc[usize](a, 2usize * n)
        if e != ok { ret nan }
        if mc.hc_eii(a, z[3usize..3usize + n * p], n, p, o) != ok { ret nan }
        ret f64(o[usize(z[2usize])])
    }
    if str.eq(c.name, "me") {
        let mc2 = usize(z[0usize])
        let n = usize(z[1usize])
        let p = usize(z[2usize])
        let g = usize(z[3usize])
        let id = usize(z[4usize])
        let (zz, e1) = mem.alloc[f64](a, n * g)
        let (pro, e2) = mem.alloc[f64](a, g)
        let (mu, e3) = mem.alloc[f64](a, g * p)
        let (sg, e4) = mem.alloc[f64](a, g * p * p)
        let (inf, e5) = mem.alloc[f64](a, 2usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
        var q = 0usize
        while q < n * g {
            zz[q] = z[5usize + n * p + q]
            q += 1usize
        }
        let ll = mc.me_em(a, mc2 % 10usize, mc2 >= 10usize, z[5usize..5usize + n * p], zz, n, p, g, pro, mu, sg, inf)
        if id == 0usize { ret ll }
        if id == 1usize { ret inf[0usize] }
        var s = 0.0f64
        if id == 2usize {
            q = 0usize
            while q < g {
                s += f64(q + 1usize) * pro[q]
                q += 1usize
            }
        } else if id == 3usize {
            // R stores the means as a p by G matrix
            var k = 0usize
            while k < g {
                var j = 0usize
                while j < p {
                    s += f64(k * p + j + 1usize) * mu[j * g + k]
                    j += 1usize
                }
                k += 1usize
            }
        } else if id == 4usize {
            q = 0usize
            while q < g * p * p {
                s += f64(q + 1usize) * sg[q]
                q += 1usize
            }
        } else {
            q = 0usize
            while q < n * g {
                s += f64(q + 1usize) * zz[q]
                q += 1usize
            }
        }
        ret s
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust.json")
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
