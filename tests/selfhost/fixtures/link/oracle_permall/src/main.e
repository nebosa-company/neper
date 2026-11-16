// e.algo.stat.permset all_perms_design against permute 0.10.0 allPerms. tests/oracle/permall.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R permall`; the layout is at the top of scripts/r_oracle/groups/permall.R.

use e.algo.stat.permset as ps
use e.algo.stat.permute as pm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(x[0usize])
    let (pl, e1) = mem.alloc[i64](a, n)
    let (bl, e2) = mem.alloc[i64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < n {
        pl[i] = i64(x[14usize + i])
        bl[i] = i64(x[14usize + n + i])
        i += 1usize
    }
    var plots: []const i64 = zero
    var blocks: []const i64 = zero
    if x[12usize] != 0.0f64 { plots = pl }
    if x[13usize] != 0.0f64 { blocks = bl }
    let q = usize(x[14usize + 2usize * n])
    let d = pm.Design { plots: plots, blocks: blocks, plot_type: u8(x[1usize]), plot_mirror: x[2usize] != 0.0f64, within_type: u8(x[6usize]), within_mirror: x[7usize] != 0.0f64, constant: x[11usize] != 0.0f64, within_nrow: usize(x[8usize]), within_ncol: usize(x[9usize]), within_sym: x[10usize] != 0.0f64, plot_nrow: usize(x[3usize]), plot_ncol: usize(x[4usize]), plot_sym: x[5usize] != 0.0f64 }
    let (out, oe) = mem.alloc[usize](a, 400000usize)
    if oe != ok { ret nan }
    let (rows, e) = ps.all_perms_design(a, n, &d, out)
    if e != ok { ret nan }
    if q == 0usize { ret f64(rows) }
    var s = 0.0f64
    if q == 3usize {
        i = 0usize
        while i < n {
            s += f64(out[(rows - 1usize) * n + i])
            i += 1usize
        }
        ret s
    }
    if q == 4usize {
        i = 0usize
        while i < n {
            s += f64(i + 1usize) * f64(out[i])
            i += 1usize
        }
        ret s
    }
    i = 0usize
    while i < rows * n {
        if q == 1usize { s += f64(out[i]) } else { s += f64(i + 1usize) * f64(out[i]) }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/permall.json")
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
