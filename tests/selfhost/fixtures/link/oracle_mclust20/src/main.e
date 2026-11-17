// e.algo.stat.mclustem.estep_vinv (predict of a fit with a noise component) against mclust. tests/oracle/mclust20.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust20`; the layout is at the top of scripts/r_oracle/groups/mclust20.R.

use e.algo.stat.mclustem as em
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let id = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let g = usize(z[3usize])
    let vinv = z[4usize]
    let pro = z[5usize..5usize + g + 1usize]
    let mu = z[6usize + g..6usize + g + g * p]
    let sg = z[6usize + g + g * p..6usize + g + g * p + g * p * p]
    let x = z[6usize + g + g * p + g * p * p..6usize + g + g * p + g * p * p + n * p]
    let (zz, e1) = mem.alloc[f64](a, n * (g + 1usize))
    if e1 != ok { ret nan }
    let h = em.estep_vinv(a, x, n, p, g, mu, sg, pro, vinv, zz)
    if h != h { ret nan }
    var s = 0.0f64
    if id == 0usize {
        var q = 0usize
        while q < n * (g + 1usize) {
            s += f64(q + 1usize) * zz[q]
            q += 1usize
        }
        ret s
    }
    var i = 0usize
    while i < n {
        var best = 0usize
        var k = 1usize
        while k <= g {
            if zz[k * n + i] > zz[best * n + i] { best = k }
            k += 1usize
        }
        var lab = best + 1usize
        if best == g { lab = 0usize }
        s += f64(i + 1usize) * f64(lab)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust20.json")
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
                let _ = str.push(&b, "pnz id ")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " p ")
                let _ = str.push_f64(&b, c.args[2usize])
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
