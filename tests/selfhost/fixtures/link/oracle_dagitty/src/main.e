// e.algo.stat.dagitty against dagitty. tests/oracle/dagitty.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dagitty`; the layout is at the top of scripts/r_oracle/groups/dagitty.R.

use e.algo.stat.dagitty as dg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let xi = usize(x[1usize])
    let yi = usize(x[2usize])
    let z = u32(x[3usize])
    let (adj, e) = mem.alloc[bool](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n * n {
        adj[i] = x[4usize + i] > 0.5f64
        i += 1usize
    }
    let k = c.name
    if k.len == 3usize && k[0usize] == 108u8 && k[1usize] == 116u8 {
        var lx: [512]usize = zero
        var ly: [512]usize = zero
        var lz: [512]u32 = zero
        let cnt = dg.implied_list(adj, n, lx[0usize..512usize], ly[0usize..512usize], lz[0usize..512usize])
        if k[2usize] == 110u8 { ret f64(cnt) }
        var tot = 0.0f64
        var q = 0usize
        while q < cnt {
            var res: [4]f64 = zero
            let le = dg.local_test(a, x[4usize + n * n..4usize + 2usize * n * n], n, lx[q], ly[q], lz[q], x[1usize], 0.95f64, res[0usize..4usize])
            if le != ok { os.exit(7) }
            if k[2usize] == 101u8 { tot += res[0usize] }
            if k[2usize] == 112u8 { tot += res[1usize] }
            if k[2usize] == 108u8 { tot += res[2usize] }
            if k[2usize] == 117u8 { tot += res[3usize] }
            q += 1usize
        }
        ret tot
    }
    if str.eq(k, "dsep") {
        if dg.dseparated(adj, n, dg.bit(xi), dg.bit(yi), z) { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(k, "anc") { ret f64(dg.ancestors(adj, n, dg.bit(yi))) }
    if str.eq(k, "nci") || str.eq(k, "sci") {
        let (ni, si) = dg.implied_independencies(adj, n)
        if str.eq(k, "nci") { ret f64(ni) }
        ret si
    }
    if str.eq(k, "neq") { ret f64(dg.equivalent_dag_count(a, adj, n)) }
    if str.eq(k, "canon") {
        let (cm, cv) = dg.canonical_adjustment_set(a, adj, n, xi, yi)
        if !cv { ret 0.0f64 - 1.0f64 }
        ret f64(cm)
    }
    if str.eq(k, "npaths") || str.eq(k, "nopen") {
        let (tp, op) = dg.count_paths(adj, n, xi, yi, z)
        if str.eq(k, "npaths") { ret f64(tp) }
        ret f64(op)
    }
    if str.eq(k, "nall") || str.eq(k, "sall") {
        let (allsets, e3) = mem.alloc[u32](a, usize(1u32 << u32(n)))
        if e3 != ok { os.exit(7) }
        let ca = dg.all_adjustment_sets(a, adj, n, xi, yi, allsets)
        if str.eq(k, "nall") { ret f64(ca) }
        var sa = 0.0f64
        var q = 0usize
        while q < ca {
            sa += f64(allsets[q])
            q += 1usize
        }
        ret sa
    }
    let (sets, e2) = mem.alloc[u32](a, usize(1u32 << u32(n)))
    if e2 != ok { os.exit(6) }
    let cnt = dg.minimal_adjustment_sets(a, adj, n, xi, yi, sets)
    if str.eq(k, "nadj") { ret f64(cnt) }
    var s = 0.0f64
    i = 0usize
    while i < cnt {
        s += f64(sets[i])
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dagitty.json")
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
