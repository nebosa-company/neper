// e.algo.parts against partitions: P, Q, parts, restrictedparts, diffparts. tests/oracle/partitions.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partitions`; the layout is at the top of
// scripts/r_oracle/groups/partitions.R.

use e.algo.parts as pt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if c.name.len == 3usize && c.name[0usize] == 98u8 && c.name[1usize] == 103u8 {
        let (bv, bve) = pt.count_wrap(a, usize(x[0usize]), c.name[2usize] == 113u8)
        if bve != ok { ret 0.0f64 / 0.0f64 }
        ret bv
    }
    if c.name.len == 3usize && c.name[0usize] == 98u8 {
        let bm = usize(x[0usize])
        let (bo, be) = mem.alloc[f64](a, 400000usize)
        if be != ok { ret 0.0f64 / 0.0f64 }
        let (bc, bce) = pt.blockparts(a, x[2usize..2usize + bm], usize(x[1usize]), bo)
        if bce != ok { ret 0.0f64 / 0.0f64 }
        if c.name[2usize] == 99u8 { ret f64(bc) }
        var bs = 0.0f64
        var bi = 0usize
        while bi < bc * bm {
            if c.name[2usize] == 115u8 { bs += bo[bi] } else { bs += f64(bi + 1usize) * bo[bi] }
            bi += 1usize
        }
        ret bs
    }
    if c.name.len == 3usize && c.name[0usize] == 122u8 {
        // setparts: args (m, sizes...) for a block-size vector (m > 0) or (0, n) for setparts(n)
        let (so, soe) = mem.alloc[f64](a, 400000usize)
        if soe != ok { ret 0.0f64 / 0.0f64 }
        var sn = 0usize
        var scols = 0usize
        if usize(x[0usize]) == 0usize {
            sn = usize(x[1usize])
            let (k, ke) = pt.setparts_n(a, sn, so)
            if ke != ok { ret 0.0f64 / 0.0f64 }
            scols = k
        } else {
            let sm = usize(x[0usize])
            let (sz, sze) = mem.alloc[usize](a, sm)
            if sze != ok { ret 0.0f64 / 0.0f64 }
            var si = 0usize
            while si < sm {
                sz[si] = usize(x[1usize + si])
                sn += sz[si]
                si += 1usize
            }
            let (k, ke) = pt.setparts_shape(a, sz, so)
            if ke != ok { ret 0.0f64 / 0.0f64 }
            scols = k
        }
        if c.name[2usize] == 99u8 { ret f64(scols) }
        var ss = 0.0f64
        var sj = 0usize
        while sj < scols * sn {
            if c.name[2usize] == 115u8 { ss += so[sj] } else { ss += f64(sj + 1usize) * so[sj] }
            sj += 1usize
        }
        ret ss
    }
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let m = usize(x[2usize])
    if kind <= 1usize {
        let (v, e) = pt.count(a, n, kind == 1usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        ret v
    }
    let cap = 400000usize
    let (out, oe) = mem.alloc[f64](a, cap)
    if oe != ok { ret 0.0f64 / 0.0f64 }
    var cols = 0usize
    var rows = n
    var ce = ok
    if kind >= 5usize {
        rows = m
        let (cc, e) = pt.compositions(a, n, m, kind == 5usize, out)
        cols = cc
        ce = e
    } else if kind == 2usize {
        let (cc, e) = pt.parts(a, n, out)
        cols = cc
        ce = e
    } else if kind == 3usize {
        rows = m
        let (cc, e) = pt.by_length(a, n, m, m, false, out)
        cols = cc
        ce = e
    } else {
        rows = 0usize
        while (rows + 1usize) * (rows + 2usize) / 2usize <= n { rows += 1usize }
        let (cc, e) = pt.by_length(a, n, rows, rows, true, out)
        cols = cc
        ce = e
    }
    if ce != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "cols") { ret f64(cols) }
    var s = 0.0f64
    var i = 0usize
    while i < cols * rows {
        if str.eq(c.name, "sum") { s += out[i] } else { s += f64(i + 1usize) * out[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partitions.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
