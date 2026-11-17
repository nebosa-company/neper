// e.algo.stat.mclustem against mclust. tests/oracle/mclust2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust2`; the layout is at the top of scripts/r_oracle/groups/mclust2.R.

use e.algo.stat.mclustem as me
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "me2") {
        let mi = usize(z[0usize])
        let eqp = z[1usize] != 0.0f64
        let n = usize(z[2usize])
        let p = usize(z[3usize])
        let g = usize(z[4usize])
        let id = usize(z[5usize])
        let (zz, e1) = mem.alloc[f64](a, n * g)
        let (pro, e2) = mem.alloc[f64](a, g)
        let (mu, e3) = mem.alloc[f64](a, g * p)
        let (sg, e4) = mem.alloc[f64](a, g * p * p)
        let (inf, e5) = mem.alloc[f64](a, 4usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
        var q = 0usize
        while q < n * g {
            zz[q] = z[6usize + n * p + q]
            q += 1usize
        }
        let ll = me.me_any(a, mi, eqp, z[6usize..6usize + n * p], zz, n, p, g, pro, mu, sg, inf)
        if id == 0usize { ret ll }
        if id == 1usize { ret inf[0usize] }
        var s = 0.0f64
        if id == 2usize {
            q = 0usize
            while q < g {
                s += f64(q + 1usize) * pro[q]
                q += 1usize
            }
            q = 0usize
            while q < g * p {
                s += f64(q + 1usize) * mu[q]
                q += 1usize
            }
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust2.json")
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
