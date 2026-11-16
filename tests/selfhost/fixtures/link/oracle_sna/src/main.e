// e.algo.stat.snapkg against sna centrality indices. tests/oracle/sna.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sna`; the layout is at the top of scripts/r_oracle/groups/sna.R.

use e.algo.stat.snapkg as sn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn block(out: []const f64, n: usize, b: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += out[b * n + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (out, e1) = mem.alloc[f64](a, 8usize * n + 1usize)
    if e1 != ok { ret nan }
    if sn.centrality(a, z[1usize..1usize + n * n], n, out) != ok { ret nan }
    let nf = f64(n)
    if str.eq(c.name, "outdeg") { ret block(out, n, 0usize) }
    if str.eq(c.name, "indeg") { ret block(out, n, 1usize) }
    if str.eq(c.name, "degree") { ret block(out, n, 2usize) }
    if str.eq(c.name, "between") { ret block(out, n, 3usize) }
    if str.eq(c.name, "stress") { ret block(out, n, 4usize) }
    if str.eq(c.name, "closeness") { ret block(out, n, 5usize) }
    if str.eq(c.name, "graphcent") { ret block(out, n, 6usize) }
    if str.eq(c.name, "evcent") { ret block(out, n, 7usize) }
    if str.eq(c.name, "gden") { ret out[8usize * n] }
    if str.eq(c.name, "cent_degree") { ret sn.centralization(out[2usize * n..3usize * n], (nf - 1.0f64) * (2.0f64 * nf - 4.0f64)) }
    if str.eq(c.name, "cent_between") { ret sn.centralization(out[3usize * n..4usize * n], (nf - 1.0f64) * (nf - 1.0f64) * (nf - 2.0f64)) }
    ret sn.centralization(out[5usize * n..6usize * n], (nf - 1.0f64) * (nf - 1.0f64) / nf)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sna.json")
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
