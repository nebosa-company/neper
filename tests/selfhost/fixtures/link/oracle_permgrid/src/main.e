// e.algo.stat.permute shuffle with grid restrictions against permute 0.10.0. tests/oracle/permgrid.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R permgrid`; the layout is at the top of scripts/r_oracle/groups/permgrid.R.

use e.algo.rand.r as rng
use e.algo.stat.permset as ps
use e.algo.stat.permute as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(x[1usize])
    if str.eq(c.name, "gnp") {
        // (0, n, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, has_plots, plots[n])
        let (tab, te) = mem.alloc[usize](a, n)
        if te != ok { ret nan }
        var ntab = 0usize
        if x[13usize] != 0.0f64 {
            var i = 0usize
            while i < n {
                var j = 0usize
                var found = false
                while j < ntab {
                    // the plots are contiguous runs of one label here
                    j += 1usize
                }
                i += 1usize
            }
            // sizes by label in ascending label order
            var lab = 1i64
            var maxl = 0i64
            i = 0usize
            while i < n {
                if i64(x[14usize + i]) > maxl { maxl = i64(x[14usize + i]) }
                i += 1usize
            }
            while lab <= maxl {
                var cnt = 0usize
                i = 0usize
                while i < n {
                    if i64(x[14usize + i]) == lab { cnt += 1usize }
                    i += 1usize
                }
                if cnt > 0usize {
                    tab[ntab] = cnt
                    ntab += 1usize
                }
                lab += 1i64
            }
        }
        let mw = f64(ps.norient(true, x[11usize] != 0.0f64, usize(x[9usize]), usize(x[10usize])))
        let mp = f64(ps.norient(true, x[6usize] != 0.0f64, usize(x[4usize]), usize(x[5usize])))
        ret pm.block_perms(n, tab[0usize..ntab], u8(x[2usize]), x[3usize] != 0.0f64, u8(x[7usize]), x[8usize] != 0.0f64, x[12usize] != 0.0f64, mw, mp)
    }
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let (pl, e1) = mem.alloc[i64](a, n)
    if e1 != ok { ret nan }
    var i = 0usize
    while i < n {
        pl[i] = i64(x[14usize + i])
        i += 1usize
    }
    var plots: []const i64 = zero
    let blocks: []const i64 = zero
    if x[13usize] != 0.0f64 { plots = pl }
    let d = pm.Design { plots: plots, blocks: blocks, plot_type: u8(x[2usize]), plot_mirror: x[3usize] != 0.0f64, within_type: u8(x[7usize]), within_mirror: x[8usize] != 0.0f64, constant: x[12usize] != 0.0f64, within_nrow: usize(x[9usize]), within_ncol: usize(x[10usize]), within_sym: x[11usize] != 0.0f64, plot_nrow: usize(x[4usize]), plot_ncol: usize(x[5usize]), plot_sym: x[6usize] != 0.0f64 }
    let (r, e) = pm.shuffle(a, &g, n, &d)
    if e != ok { ret nan }
    ret f64(r[usize(x[x.len - 1usize])])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/permgrid.json")
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
