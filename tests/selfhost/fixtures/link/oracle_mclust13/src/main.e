// e.algo.stat.mclustdr (MclustDR) against mclust. tests/oracle/mclust13.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust13`; the layout is at the top of scripts/r_oracle/groups/mclust13.R.

use e.algo.stat.mclustdr as dr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let id = usize(z[0usize])
    let lambda = z[1usize]
    let normalized = z[2usize] > 0.5f64
    let n = usize(z[3usize])
    let p = usize(z[4usize])
    let g = usize(z[5usize])
    let f = z[6usize..6usize + g]
    let mu = z[6usize + g..6usize + g + g * p]
    let sg = z[6usize + g + g * p..6usize + g + g * p + g * p * p]
    let x = z[6usize + g + g * p + g * p * p..6usize + g + g * p + g * p * p + n * p]
    let pq = p * p
    let (out, e1) = mem.alloc[f64](a, 5usize * pq + p + 1usize + n * p)
    if e1 != ok { ret nan }
    if dr.mclust_dr(a, x, n, p, g, f, mu, sg, lambda, normalized, out) != ok { ret nan }
    var base = 0usize
    var cnt = pq
    if id == 1usize { base = pq }
    if id == 2usize { base = 2usize * pq }
    if id == 3usize {
        base = 3usize * pq
        cnt = p
    }
    if id == 4usize { ret out[3usize * pq + p] }
    if id == 5usize { base = 3usize * pq + p + 1usize }
    if id == 6usize { base = 4usize * pq + p + 1usize }
    if id == 7usize {
        base = 5usize * pq + p + 1usize
        cnt = n * p
    }
    var s = 0.0f64
    var q = 0usize
    while q < cnt {
        s += f64(q + 1usize) * out[base + q]
        q += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust13.json")
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
                let _ = str.push(&b, "dr id ")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " lambda ")
                let _ = str.push_f64(&b, c.args[1usize])
                let _ = str.push(&b, " p ")
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
