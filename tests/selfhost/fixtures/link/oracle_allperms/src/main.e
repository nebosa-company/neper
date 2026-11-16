// e.algo.stat.permute.all_perms against permute::allPerms. tests/oracle/allperms.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R allperms`; the layout is at the top of
// scripts/r_oracle/groups/allperms.R.

use e.algo.stat.permute as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = u8(z[0usize])
    let nb = usize(z[1usize])
    let (sizes, e1) = mem.alloc[usize](a, nb)
    if e1 != ok { ret nan }
    var n = 0usize
    var b = 0usize
    while b < nb {
        sizes[b] = usize(z[2usize + b])
        n += sizes[b]
        b += 1usize
    }
    var cap = 1usize
    var f = 2usize
    while f <= n {
        cap *= f
        f += 1usize
    }
    let (out, e2) = mem.alloc[i64](a, cap * n)
    if e2 != ok { ret nan }
    let (rows, e) = pm.all_perms(a, sizes, kind, out)
    if e != ok { ret nan }
    if str.eq(c.name, "rows") { ret f64(rows) }
    var s = 0.0f64
    var i = 0usize
    while i < rows * n {
        if str.eq(c.name, "sum") { s += f64(out[i]) } else { s += f64(i + 1usize) * f64(out[i]) }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/allperms.json")
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
