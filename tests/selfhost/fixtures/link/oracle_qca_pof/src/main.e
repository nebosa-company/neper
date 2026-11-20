// e.algo.stat.qcapkg's pof_term against QCA::pof. tests/oracle/qca_pof.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qca_pof`; the layout is at the top of scripts/r_oracle/groups/qca_pof.R.

use e.algo.stat.qcapkg as qc
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qca_pof.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[4usize])
        let nv = usize(x[5usize])
        let sl = usize(x[6usize])
        let base = 7usize + sl
        let got = qc.pof_term(x[base..base + n * nv], x[base + n * nv..base + n * nv + n], n, nv, x[7usize..base], usize(x[2usize]), usize(x[0usize]), usize(x[1usize]), x[3usize] == 1.0f64)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
