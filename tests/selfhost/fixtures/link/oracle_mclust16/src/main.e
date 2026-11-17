// e.algo.stat.mclustorient (orientation matrices of EEV, VEV, EVV through the dgesvd port) and sim() from them against mclust.
// tests/oracle/mclust16.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust16`; the layout is at the top of scripts/r_oracle/groups/mclust16.R.

use e.algo.stat.mclustorient as mo
use e.algo.stat.mclustsim as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let model = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let g = usize(z[3usize])
    let nsim = usize(z[4usize])
    let seed = i64(z[5usize])
    let id = usize(z[6usize])
    let x = z[7usize..7usize + n * p]
    let zz = z[7usize + n * p..7usize + n * p + n * g]
    let (pro, e1) = mem.alloc[f64](a, g)
    let (mu, e2) = mem.alloc[f64](a, g * p)
    let (scale, e3) = mem.alloc[f64](a, g)
    let (shape, e4) = mem.alloc[f64](a, g * p)
    let (orient, e5) = mem.alloc[f64](a, g * p * p)
    let (grp, e6) = mem.alloc[f64](a, nsim)
    let (xs, e7) = mem.alloc[f64](a, nsim * p)
    let (none, e8) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret nan }
    if mo.orient_params(a, model, x, zz, n, p, g, pro, mu, scale, shape, orient) != ok { ret nan }
    var s = 0.0f64
    var q = 0usize
    if id == 2usize {
        // R's orientation of the first group only is not enough: the whole array
        while q < g * p * p {
            s += f64(q + 1usize) * orient[q]
            q += 1usize
        }
        ret s
    }
    if ms.sim_model(a, model, p, g, nsim, seed, pro, mu, scale, shape, orient, none, grp, xs) != ok { ret nan }
    if id == 0usize {
        while q < nsim {
            s += f64(q + 1usize) * grp[q]
            q += 1usize
        }
        ret s
    }
    while q < nsim * p {
        s += f64(q + 1usize) * xs[q]
        q += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust16.json")
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
                let (initial, be) = str.builder(a, 120usize)
                var b = initial
                let _ = str.push(&b, "ori model ")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " p ")
                let _ = str.push_f64(&b, c.args[2usize])
                let _ = str.push(&b, " id ")
                let _ = str.push_f64(&b, c.args[6usize])
                let _ = str.push(&b, ": got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, ", R says ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
