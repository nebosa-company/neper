// e.algo.stat.qcapkg's truth_table against QCA::truthTable. tests/oracle/qca_tt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qca_tt`; the layout is at the top of scripts/r_oracle/groups/qca_tt.R.

use e.algo.stat.qcapkg as qc
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let nv = usize(x[1usize])
    let k = usize(x[2usize])
    let cc = usize(x[6usize])
    let what = usize(x[7usize])
    let d = x[8usize..8usize + n * nv]
    var y: [64]f64 = zero
    var r = 0usize
    while r < n {
        y[r] = d[r * nv + k]
        r += 1usize
    }
    let rows = usize(1u64 << u64(k))
    let (out, e1) = mem.alloc[f64](a, rows * 4usize)
    if e1 != ok { os.exit(4) }
    qc.truth_table(d, y[0usize..n], n, nv, k, x[3usize], x[4usize], x[5usize], out)
    ret out[cc * 4usize + what]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qca_tt.json")
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
