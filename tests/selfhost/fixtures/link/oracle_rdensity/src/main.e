// e.algo.stat.rdensity against stats::density. tests/oracle/rdensity.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rdensity`; the layout is at the top of scripts/r_oracle/groups/rdensity.R.

use e.algo.stat.desctools as dt
use e.algo.stat.rdensity as rd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rdensity.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[3usize])
        let xs = x[4usize..4usize + n]
        let (s, e1) = dt.sorted_copy(a, xs)
        if e1 != ok { os.exit(5) }
        var bw = x[0usize]
        if bw == 0.0f64 { bw = rd.bw_nrd0(xs, s) }
        var got = bw
        if str.eq(c.name, "dens") {
            let nout = usize(x[1usize])
            let (out, e2) = mem.alloc[f64](a, nout)
            if e2 != ok { os.exit(6) }
            let (sc, e3) = mem.alloc[f64](a, 5usize * rd.grid_for(nout))
            if e3 != ok { os.exit(7) }
            rd.density_gauss(xs, s, bw, nout, out, sc)
            got = out[usize(x[2usize])]
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
