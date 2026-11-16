// e.algo.stat.permset shuffle_set against permute 0.10.0 shuffleSet. tests/oracle/permset.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R permset`; the layout is at the top of scripts/r_oracle/groups/permset.R.

use e.algo.rand.r as rng
use e.algo.stat.permset as ps
use e.algo.stat.permute as pm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(x[1usize])
    let nset = usize(x[2usize])
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let (pl, e1) = mem.alloc[i64](a, n)
    let (bl, e2) = mem.alloc[i64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < n {
        pl[i] = i64(x[16usize + i])
        bl[i] = i64(x[16usize + n + i])
        i += 1usize
    }
    var plots: []const i64 = zero
    var blocks: []const i64 = zero
    if x[14usize] != 0.0f64 { plots = pl }
    if x[15usize] != 0.0f64 { blocks = bl }
    let d = pm.Design { plots: plots, blocks: blocks, plot_type: u8(x[3usize]), plot_mirror: x[4usize] != 0.0f64, within_type: u8(x[8usize]), within_mirror: x[9usize] != 0.0f64, constant: x[13usize] != 0.0f64, within_nrow: usize(x[10usize]), within_ncol: usize(x[11usize]), within_sym: x[12usize] != 0.0f64, plot_nrow: usize(x[5usize]), plot_ncol: usize(x[6usize]), plot_sym: x[7usize] != 0.0f64 }
    let (r, e) = ps.shuffle_set(a, &g, n, nset, &d)
    if e != ok { ret nan }
    ret f64(r[usize(x[x.len - 1usize])])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/permset.json")
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
