// e.algo.stat.sampling's UPbrewer against sampling::UPbrewer under set.seed. tests/oracle/sampling_brewer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_brewer`; the layout of every case is at the top of scripts/r_oracle/groups/sampling_brewer.R.

use e.algo.rand.r as rng
use e.algo.stat.sampling as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let seed = i64(z[0usize])
    let nn = usize(z[1usize])
    let pik = z[2usize..2usize + nn]
    let which = usize(z[z.len - 1usize])
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (s, e) = mem.alloc[f64](a, nn)
    if e != ok { os.exit(10) }
    if sm.up_brewer(a, &g, pik, 0.000001f64, s) != ok { os.exit(11) }
    var acc = 0.0f64
    var i = 0usize
    while i < nn {
        if which == 0usize { acc += s[i] } else { acc += f64(i + 1usize) * s[i] }
        i += 1usize
    }
    ret acc
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_brewer.json")
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
