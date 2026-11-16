// e.algo.stat.labramp against ggsci's rgb_gsea, rgb_material and rgb_tw3. tests/oracle/labramp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R labramp`; the layout is at the top of scripts/r_oracle/groups/labramp.R.

use e.algo.stat.labramp as lr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/labramp.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        var got = 0.0f64
        if c.name.len == 3usize {
            got = f64(lr.palette_colour(a, usize(x[3usize]) - 1usize, usize(x[0usize]), usize(x[1usize]), x[2usize]))
        } else {
        let m = usize(x[3usize])
        let (raw, re) = mem.alloc[u64](a, m)
        if re != ok { os.exit(4) }
        var i = 0usize
        while i < m {
            raw[i] = u64(x[4usize + i])
            i += 1usize
        }
        got = f64(lr.lab_ramp(a, raw, usize(x[0usize]), usize(x[1usize]), x[2usize]))
        }
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
