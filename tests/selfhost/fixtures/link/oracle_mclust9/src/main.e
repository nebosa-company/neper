// e.algo.stat.mclustprior against mclust. tests/oracle/mclust9.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust9`; the layout is at the top of scripts/r_oracle/groups/mclust9.R.

use e.algo.stat.mclustprior as pr
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
    let id = usize(z[4usize])
    let x = z[5usize..5usize + n * p]
    let (pmu, e1) = mem.alloc[f64](a, p)
    let (psc, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret nan }
    let dof = pr.default_prior(x, n, p, g, model, pmu, psc)
    var s = 0.0f64
    var q = 0usize
    if str.eq(c.name, "pdp") {
        if id == 0usize { ret dof }
        if id == 1usize {
            while q < p {
                s += f64(q + 1usize) * pmu[q]
                q += 1usize
            }
            ret s
        }
        var cnt = p * p
        if model < 8usize { cnt = 1usize }
        while q < cnt {
            s += f64(q + 1usize) * psc[q]
            q += 1usize
        }
        ret s
    }
    let (zz, e3) = mem.alloc[f64](a, n * g)
    let (pro, e4) = mem.alloc[f64](a, g)
    let (mu, e5) = mem.alloc[f64](a, g * p)
    let (sg, e6) = mem.alloc[f64](a, g * p * p)
    let (inf, e7) = mem.alloc[f64](a, 2usize)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    q = 0usize
    while q < n * g {
        zz[q] = z[5usize + n * p + q]
        q += 1usize
    }
    var ll = 0.0f64
    if str.eq(c.name, "pme") {
        ll = pr.me_prior(a, model, x, zz, n, p, g, 0.01f64, pmu, psc, dof, pro, mu, sg, inf)
        if id == 0usize { ret ll }
        if id == 1usize { ret inf[0usize] }
    } else {
        if pr.mstep_prior(a, model, x, zz, n, p, g, 0.01f64, pmu, psc, dof, pro, mu, sg) != ok { ret nan }
    }
    if id == 3usize {
        q = 0usize
        while q < n * g {
            s += f64(q + 1usize) * zz[q]
            q += 1usize
        }
        ret s
    }
    if id == 0usize || id == 2usize {
        q = 0usize
        while q < g {
            s += f64(q + 1usize) * pro[q]
            q += 1usize
        }
    }
    if id == 1usize || id == 2usize {
        q = 0usize
        while q < g * p {
            s += f64(q + 1usize) * mu[q]
            q += 1usize
        }
    }
    if id == 2usize {
        // pme id 2 sums everything; pms id 2 is the sigma checksum alone
        if str.eq(c.name, "pms") { s = 0.0f64 }
        q = 0usize
        var cnt = g * p * p
        while q < cnt {
            s += f64(q + 1usize) * sg[q]
            q += 1usize
        }
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust9.json")
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
                let _ = str.push_f64(&b, c.args[4usize])
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
