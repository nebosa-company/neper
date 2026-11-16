// e.algo.stat.permute against permute: shuffle under set.seed for free and series restrictions with
// plots and blocks, and numPerms. tests/oracle/permute.json comes from `R_ORACLE_LIB=<dir> Rscript
// scripts/r_oracle/generate.R permute`; the layout is at the top of scripts/r_oracle/groups/permute.R.

use e.algo.rand.r as rr
use e.algo.stat.permute as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "nperms") {
        let n = usize(x[0usize])
        let has = x[6usize] != 0.0f64
        var tab: []usize = zero
        if has {
            let (t, te) = mem.alloc[usize](a, n)
            if te != ok { os.exit(5) }
            var nt = 0usize
            var lab = 1i64
            while lab <= 9i64 {
                var cnt = 0usize
                var i = 0usize
                while i < n {
                    if i64(x[7usize + i]) == lab { cnt += 1usize }
                    i += 1usize
                }
                if cnt > 0usize {
                    t[nt] = cnt
                    nt += 1usize
                }
                lab += 1i64
            }
            tab = t[0usize..nt]
        }
        ret pm.block_perms(n, tab, u8(x[1usize]), x[2usize] != 0.0f64, u8(x[3usize]), x[4usize] != 0.0f64, x[5usize] != 0.0f64, 1.0f64, 1.0f64)
    }
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[0usize]))
    let n = usize(x[1usize])
    let (pl, ple) = mem.alloc[i64](a, n)
    let (bl, ble) = mem.alloc[i64](a, n)
    if ple != ok { os.exit(5) }
    if ble != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        pl[i] = i64(x[9usize + i])
        bl[i] = i64(x[9usize + n + i])
        i += 1usize
    }
    var plots: []const i64 = zero
    var blocks: []const i64 = zero
    if x[7usize] != 0.0f64 { plots = pl }
    if x[8usize] != 0.0f64 { blocks = bl }
    let d = pm.Design { plots: plots, blocks: blocks, plot_type: u8(x[2usize]), plot_mirror: x[3usize] != 0.0f64, within_type: u8(x[4usize]), within_mirror: x[5usize] != 0.0f64, constant: x[6usize] != 0.0f64, within_nrow: 0usize, within_ncol: 0usize, within_sym: false, plot_nrow: 0usize, plot_ncol: 0usize, plot_sym: false }
    let (r, e) = pm.shuffle(a, &g, n, &d)
    if e != ok { os.exit(6) }
    ret f64(r[usize(x[x.len - 1usize])])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/permute.json")
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
