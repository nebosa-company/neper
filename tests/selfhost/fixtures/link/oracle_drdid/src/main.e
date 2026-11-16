// e.algo.stat.drdid against DRDID. tests/oracle/drdid.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R drdid`; the layout is at the top of scripts/r_oracle/groups/drdid.R.

use e.algo.stat.drdid as dr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/drdid.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[1usize])
        let p = usize(x[2usize])
        var got = dr.reg_did_panel(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + n * p], n, p, usize(x[0usize]))
        if str.eq(c.name, "dr") { got = dr.drdid_panel(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + n * p], n, p, usize(x[0usize])) }
        if str.eq(c.name, "ipw") { got = dr.ipw_did_panel(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + n * p], n, p, false, usize(x[0usize])) }
        if str.eq(c.name, "sipw") { got = dr.ipw_did_panel(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + n * p], n, p, true, usize(x[0usize])) }
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
