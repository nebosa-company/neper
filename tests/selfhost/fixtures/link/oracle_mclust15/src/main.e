// e.algo.stat.mclusthcrp (hcRandomPairs) against mclust. tests/oracle/mclust15.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust15`; the layout is at the top of scripts/r_oracle/groups/mclust15.R.

use e.algo.stat.mclusthcrp as rp
use e.algo.stat.mclusthce as he
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let seed = i64(z[1usize])
    let id = z[2usize]
    var m = n
    if n % 2usize == 1usize { m = n - 1usize }
    let (pairs, e1) = mem.alloc[usize](a, 2usize * (m - 1usize))
    if e1 != ok { ret nan }
    if rp.hc_random_pairs(a, n, seed, pairs) != ok { ret nan }
    var s = 0.0f64
    if id < 0.0f64 {
        var q = 0usize
        while q < 2usize * (m - 1usize) {
            s += f64(q + 1usize) * f64(pairs[q])
            q += 1usize
        }
        ret s
    }
    let g = usize(id) - 100usize
    let (init, e2) = mem.alloc[usize](a, n)
    let (lab, e3) = mem.alloc[usize](a, n)
    if e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < n {
        init[i] = i + 1usize
        i += 1usize
    }
    if he.hclass_init(a, pairs, init, n, n, g, lab) != ok { ret nan }
    i = 0usize
    while i < n {
        s += f64(i + 1usize) * f64(lab[i])
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust15.json")
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
                let _ = str.push(&b, "hrp n ")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " id ")
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
