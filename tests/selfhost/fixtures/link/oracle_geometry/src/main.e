// e.algo.stat.geometrypkg against the geometry package. tests/oracle/geometry.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R geometry`; the layout is at the top of scripts/r_oracle/groups/geometry.R.

use e.algo.stat.geometrypkg as gm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nm = c.name
    var out: [5]f64 = zero
    if str.eq(nm, "facets") || str.eq(nm, "boundary") || str.eq(nm, "enclosed") {
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        gm.convhull(a, z[2usize..2usize + n * d], n, d, out[0usize..5usize])
        if str.eq(nm, "facets") { ret out[0usize] }
        if str.eq(nm, "boundary") { ret out[1usize] }
        ret out[2usize]
    }
    if str.eq(nm, "dcount") || str.eq(nm, "dvol") || str.eq(nm, "dhash") || str.eq(nm, "dvorsum") || str.eq(nm, "dvorsq") {
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        gm.delaunay(a, z[2usize..2usize + n * d], n, d, out[0usize..5usize])
        if str.eq(nm, "dcount") { ret out[0usize] }
        if str.eq(nm, "dvol") { ret out[1usize] }
        if str.eq(nm, "dhash") { ret out[2usize] }
        if str.eq(nm, "dvorsum") { ret out[3usize] }
        ret out[4usize]
    }
    if str.eq(nm, "tsidx") || str.eq(nm, "tsbary") {
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        let nt = usize(z[2usize + n * d])
        let tt = 3usize + n * d
        let nq = usize(z[tt + nt * (d + 1usize)])
        let qq = tt + nt * (d + 1usize) + 1usize
        var bb: [8]f64 = zero
        var sidx = 0.0f64
        var sb = 0.0f64
        var i = 0usize
        while i < nq {
            let start = mem.mark(a)
            let idx = gm.tsearchn(a, z[2usize..2usize + n * d], d, z[tt..tt + nt * (d + 1usize)], nt, z[qq + i * d..qq + i * d + d], bb[0usize..8usize])
            mem.reset(a, start)
            sidx += f64(i + 1usize) * f64(idx)
            if idx > 0usize {
                var k = 0usize
                while k <= d {
                    sb += f64(i + 1usize) * f64(k + 1usize) * bb[k]
                    k += 1usize
                }
            }
            i += 1usize
        }
        if str.eq(nm, "tsidx") { ret sidx }
        ret sb
    }
    if str.eq(nm, "cbsum") {
        let d = usize(z[0usize])
        let nq = usize(z[1usize + (d + 1usize) * d])
        var mat: [64]f64 = zero
        var rhs: [8]f64 = zero
        var bb: [8]f64 = zero
        var s = 0.0f64
        var i = 0usize
        while i < nq {
            let at = 2usize + (d + 1usize) * d + i * d
            if gm.bary(z[1usize..1usize + (d + 1usize) * d], d, z[at..at + d], mat[0usize..64usize], rhs[0usize..8usize], bb[0usize..8usize]) {
                var k = 0usize
                while k <= d {
                    s += f64(i + 1usize) * f64(k + 1usize) * bb[k]
                    k += 1usize
                }
            }
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "insum") {
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        let nq = usize(z[2usize + n * d])
        let qq = 3usize + n * d
        var s = 0.0f64
        var i = 0usize
        while i < nq {
            let start = mem.mark(a)
            s += f64(i + 1usize) * gm.inhulln(a, z[2usize..2usize + n * d], n, d, z[qq + i * d..qq + i * d + d])
            mem.reset(a, start)
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "ivert") || str.eq(nm, "ivol") || str.eq(nm, "iarea") {
        let n1 = usize(z[0usize])
        let n2 = usize(z[1usize])
        let d = usize(z[2usize])
        let p1 = 3usize
        let p2 = p1 + n1 * d
        let fp = p2 + n2 * d
        gm.intersect(a, z[p1..p1 + n1 * d], n1, z[p2..p2 + n2 * d], n2, d, z[fp..fp + d], out[0usize..5usize])
        if str.eq(nm, "ivert") { ret out[0usize] }
        if str.eq(nm, "ivol") { ret out[1usize] }
        ret out[2usize]
    }
    if str.eq(nm, "sfcount") || str.eq(nm, "sfhash") {
        let n = usize(z[0usize])
        let nt = usize(z[1usize + n * 3usize])
        gm.surf_tri(a, z[1usize..1usize + n * 3usize], z[2usize + n * 3usize..2usize + n * 3usize + nt * 4usize], nt, out[0usize..5usize])
        if str.eq(nm, "sfcount") { ret out[0usize] }
        ret out[1usize]
    }
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let dsel = usize(z[2usize])
    var len = m
    if dsel == 1usize { len = n }
    var s = 0.0f64
    var k = 0usize
    while k < len {
        s += f64(k + 1usize) * gm.dot(z[3usize..3usize + m * n], z[3usize + m * n..3usize + 2usize * m * n], m, n, dsel, k)
        k += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/geometry.json")
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
