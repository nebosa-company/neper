// e.ml.cluster.density's optics_cut against dbscan extractDBSCAN. tests/oracle/dbscan_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dbscan_ext`; the layout is at the top of scripts/r_oracle/groups/dbscan_ext.R.

use e.io
use e.ml.cluster as cl
use e.ml.cluster.density as dn
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (order, e1) = mem.alloc[usize](a, n)
    let (labels, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < n {
        order[i] = usize(z[2usize + i]) - 1usize
        i += 1usize
    }
    let (k, e) = cl.optics_cut(order, z[2usize + n..2usize + 2usize * n], z[2usize + 2usize * n..2usize + 3usize * n], n, z[1usize], labels)
    if e != ok { ret nan }
    if usize(z[2usize + 3usize * n]) == 1usize { ret f64(k) }
    var s = 0.0f64
    i = 0usize
    while i < n {
        var id = 0.0f64
        if labels[i] != dn.NOISE { id = f64(labels[i] + 1usize) }
        s += f64(i + 1usize) * id
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dbscan_ext.json")
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
