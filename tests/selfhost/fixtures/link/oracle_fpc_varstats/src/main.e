// e.algo.stat.fpc_misc's cluster.varstats numbers against fpc. tests/oracle/fpc_varstats.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_varstats`; the layout is at the top of scripts/r_oracle/groups/fpc_varstats.R.

use e.algo.stat.fpc_misc as fm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let ncl = usize(z[1usize])
    let cats = usize(z[2usize])
    let prop = z[3usize] > 0.5f64
    let ci = usize(z[4usize])
    let what = usize(z[5usize])
    let (cl, e1) = mem.alloc[usize](a, n)
    let (out, e2) = mem.alloc[f64](a, (ncl + 2usize) * n)
    let (st, e3) = mem.alloc[f64](a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        cl[i] = usize(z[6usize + i])
        i += 1usize
    }
    let x = z[6usize + n..6usize + 2usize * n]
    var tot = 0.0f64
    if what == 0usize {
        let (nc, e4) = fm.varwise_table(a, x, cl, n, ncl, cats, prop, out)
        if e4 != ok { os.exit(6) }
        i = 0usize
        while i < (ncl + 1usize) * nc {
            tot += f64(i + 1usize) * out[i]
            i += 1usize
        }
        ret tot
    }
    if what == 1usize {
        let (nr, nc, e4) = fm.table_in_cluster(a, x, cl, n, ci, prop, out)
        if e4 != ok { os.exit(6) }
        i = 0usize
        while i < nr * nc {
            tot += f64(i + 1usize) * out[i]
            i += 1usize
        }
        ret tot
    }
    var grp = 0usize
    var k = what - 2usize
    if k >= 8usize {
        grp = 1usize
        k -= 8usize
    }
    var who = ci
    if grp == 1usize { who = 0usize }
    if fm.clusterwise(a, x, cl, n, who, st) != ok { os.exit(7) }
    ret st[k]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_varstats.json")
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
            if failures <= 10usize {
                var c2 = *c
                c2.args = c.args[0usize..6usize]
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
