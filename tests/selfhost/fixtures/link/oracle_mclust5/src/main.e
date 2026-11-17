// e.algo.stat.mclustsim, mclustfit (predict) and mclustem (mstep) against mclust. tests/oracle/mclust5.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust5`; the layout is at the top of scripts/r_oracle/groups/mclust5.R.

use e.algo.stat.mclustem as me
use e.algo.stat.mclustfit as mf
use e.algo.stat.mclustsim as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "sim") {
        let model = usize(z[0usize])
        let d = usize(z[1usize])
        let g = usize(z[2usize])
        let n = usize(z[3usize])
        let seed = i64(z[4usize])
        let id = usize(z[5usize])
        let ls = usize(z[6usize])
        let lh = usize(z[7usize])
        let lo = usize(z[8usize])
        let lg = usize(z[9usize])
        let (grp, e1) = mem.alloc[f64](a, n)
        let (x, e2) = mem.alloc[f64](a, n * d)
        if e1 != ok || e2 != ok { ret nan }
        var at = 10usize
        let pro = z[at..at + g]
        at += g
        let mu = z[at..at + d * g]
        at += d * g
        let scale = z[at..at + ls]
        at += ls
        let shape = z[at..at + lh]
        at += lh
        let orient = z[at..at + lo]
        at += lo
        let sigma = z[at..at + lg]
        if ms.sim_model(a, model, d, g, n, seed, pro, mu, scale, shape, orient, sigma, grp, x) != ok { ret nan }
        var s = 0.0f64
        if id == 0usize {
            var q = 0usize
            while q < n {
                s += f64(q + 1usize) * grp[q]
                q += 1usize
            }
        } else {
            var q = 0usize
            while q < n * d {
                s += f64(q + 1usize) * x[q]
                q += 1usize
            }
        }
        ret s
    }
    if str.eq(c.name, "pred") {
        let n = usize(z[1usize])
        let d = usize(z[2usize])
        let g = usize(z[3usize])
        let id = usize(z[4usize])
        let (res, e1) = mem.alloc[f64](a, 2usize * n * g + 2usize * n + 1usize)
        if e1 != ok { ret nan }
        var at = 5usize
        let pro = z[at..at + g]
        at += g
        let mu = z[at..at + d * g]
        at += d * g
        let sg = z[at..at + g * d * d]
        at += g * d * d
        let x = z[at..at + n * d]
        if mf.predict_run(a, x, n, d, g, pro, mu, sg, res) != ok { ret nan }
        var s = 0.0f64
        var q = 0usize
        if id == 0usize {
            while q < n * g {
                s += f64(q + 1usize) * res[q]
                q += 1usize
            }
        } else if id == 1usize {
            while q < n * g {
                s += f64(q + 1usize) * res[n * g + q]
                q += 1usize
            }
        } else if id == 2usize {
            while q < n {
                s += f64(q + 1usize) * res[2usize * n * g + q]
                q += 1usize
            }
        } else if id == 3usize {
            s = res[2usize * n * g + n]
        } else {
            while q < n {
                s += f64(q + 1usize) * res[2usize * n * g + n + 1usize + q]
                q += 1usize
            }
        }
        ret s
    }
    if str.eq(c.name, "mstp") {
        let model = usize(z[0usize])
        let n = usize(z[1usize])
        let d = usize(z[2usize])
        let g = usize(z[3usize])
        let id = usize(z[4usize])
        let (zz, e1) = mem.alloc[f64](a, n * g)
        let (pro, e2) = mem.alloc[f64](a, g)
        let (mu, e3) = mem.alloc[f64](a, g * d)
        let (sg, e4) = mem.alloc[f64](a, g * d * d)
        let (inf, e5) = mem.alloc[f64](a, 4usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
        var q = 0usize
        while q < n * g {
            zz[q] = z[5usize + n * d + q]
            q += 1usize
        }
        let _ = me.mstep_any(a, model, z[5usize..5usize + n * d], zz, n, d, g, pro, mu, sg, inf)
        var s = 0.0f64
        if id == 0usize {
            q = 0usize
            while q < g {
                s += f64(q + 1usize) * pro[q]
                q += 1usize
            }
        } else if id == 1usize {
            q = 0usize
            while q < g * d {
                s += f64(q + 1usize) * mu[q]
                q += 1usize
            }
        } else {
            q = 0usize
            while q < g * d * d {
                s += f64(q + 1usize) * sg[q]
                q += 1usize
            }
        }
        ret s
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust5.json")
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
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " model ")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " id ")
                if str.eq(c.name, "sim") {
                    let _ = str.push_f64(&b, c.args[5usize])
                } else {
                    let _ = str.push_f64(&b, c.args[4usize])
                }
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
