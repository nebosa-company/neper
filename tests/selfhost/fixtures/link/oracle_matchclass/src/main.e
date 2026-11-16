// e.algo.stat.matchclass against e1071::matchClasses. tests/oracle/matchclass.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matchclass`; the layout is at the top of
// scripts/r_oracle/groups/matchclass.R.

use e.algo.rand.r as rng
use e.algo.stat.matchclass as mc
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let method = u8(z[1usize])
    let iter = usize(z[2usize])
    let maxexact = usize(z[3usize])
    let nr = usize(z[4usize])
    let nc = usize(z[5usize])
    let (out, e1) = mem.alloc[usize](a, nr)
    if e1 != ok { ret nan }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    if mc.match_classes(a, &g, z[6usize..6usize + nr * nc], nr, nc, method, iter, maxexact, out) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    while i < nr {
        s += f64(i + 1usize) * f64(out[i] + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matchclass.json")
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
