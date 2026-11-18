// e.algo.stat.clue's partition measures against clue::cl_agreement (Rand) and clue::cl_dissimilarity (euclidean). tests/oracle/clue_partition.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_partition`; the layout of every case is at the top of
// scripts/r_oracle/groups/clue_partition.R.

use e.algo.stat.clue as cl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let kx = usize(z[1usize])
    let ky = usize(z[2usize])
    let (cx, e0) = mem.alloc[usize](a, n)
    let (cy, e1) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok { os.exit(10) }
    var i = 0usize
    while i < n {
        cx[i] = usize(z[3usize + i])
        cy[i] = usize(z[3usize + n + i])
        i += 1usize
    }
    var k = kx
    if ky > k { k = ky }
    let which = usize(z[z.len - 1usize])
    if which == 0usize {
        let (v, e) = cl.rand_agreement(a, cx, cy, n, k)
        if e != ok { os.exit(11) }
        ret v
    }
    let (d, de) = cl.euclid_partition(a, cx, cy, n, k)
    if de != ok { os.exit(12) }
    ret d
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_partition.json")
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
