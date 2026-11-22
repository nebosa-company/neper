// e.algo.stat.veganpkg against vegan diversity, rarefy, estimateR and vegdist. tests/oracle/vegan.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vegan`; the layout is at the top of scripts/r_oracle/groups/vegan.R.

use e.algo.stat.veganpkg as vg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nr = usize(z[0usize])
    let nc = usize(z[1usize])
    let m = z[3usize..3usize + nr * nc]
    let (out, e1) = mem.alloc[f64](a, 6usize)
    if e1 != ok { ret nan }
    var s = 0.0f64
    var slot = 7usize
    if str.eq(c.name, "shannon") { slot = 0usize }
    if str.eq(c.name, "simpson") { slot = 1usize }
    if str.eq(c.name, "invsimpson") { slot = 2usize }
    if str.eq(c.name, "pielou") { slot = 3usize }
    if str.eq(c.name, "richness") { slot = 4usize }
    if str.eq(c.name, "chao1") { slot = 5usize }
    var r = 0usize
    if slot < 6usize {
        while r < nr {
            vg.diversity(m, nr, nc, r, out)
            s += out[slot] * f64(r + 1usize)
            r += 1usize
        }
        ret s
    }
    if str.eq(c.name, "man_0") || str.eq(c.name, "man_1") {
        // args: (n, kind), then the two n by n distance matrices row-major
        let kind = usize(z[1usize])
        let xm = z[2usize..2usize + nr * nr]
        let ym = z[2usize + nr * nr..2usize + 2usize * nr * nr]
        let (rr, eman) = vg.mantel_r(a, xm, ym, nr, kind)
        if eman != ok { ret nan }
        ret rr
    }
    if str.eq(c.name, "proc_0") || str.eq(c.name, "proc_1") {
        // args: (n, k, kind), then x[n*k] centred-free input and y[n*k]
        let kk = usize(z[1usize])
        let kind = usize(z[2usize])
        let xm = z[3usize..3usize + nr * kk]
        let ym = z[3usize + nr * kk..3usize + 2usize * nr * kk]
        var scale = 0.0f64
        let (ss, epr) = vg.procrustes_fit(a, xm, ym, nr, kk, &scale)
        if epr != ok { ret nan }
        if kind == 0usize { ret scale }
        ret ss
    }
    if str.eq(c.name, "fa") {
        var r2 = 0usize
        while r2 < nr {
            s += vg.fisher_alpha(m, nc, r2) * f64(r2 + 1usize)
            r2 += 1usize
        }
        ret s
    }
    if str.eq(c.name, "er_0") || str.eq(c.name, "er_1") || str.eq(c.name, "er_2") || str.eq(c.name, "er_3") {
        var slot2 = 0usize
        if str.eq(c.name, "er_1") { slot2 = 1usize }
        if str.eq(c.name, "er_2") { slot2 = 2usize }
        if str.eq(c.name, "er_3") { slot2 = 3usize }
        let (er, eer) = mem.alloc[f64](a, 4usize)
        if eer != ok { ret nan }
        while r < nr {
            vg.estimate_r(m, nc, r, er)
            s += er[slot2] * f64(r + 1usize)
            r += 1usize
        }
        ret s
    }
    if str.eq(c.name, "acc_0") || str.eq(c.name, "acc_1") || str.eq(c.name, "acc_2") {
        var method = 0usize
        if str.eq(c.name, "acc_1") { method = 1usize }
        if str.eq(c.name, "acc_2") { method = 2usize }
        let (acc, eacc) = mem.alloc[f64](a, nr)
        if eacc != ok { ret nan }
        if vg.specaccum(m, nr, nc, method, acc) != ok { ret nan }
        while r < nr {
            s += acc[r] * f64(r + 1usize)
            r += 1usize
        }
        ret s
    }
    if str.eq(c.name, "rarefy") {
        while r < nr {
            s += vg.rarefy(m, nc, r, z[2usize]) * f64(r + 1usize)
            r += 1usize
        }
        ret s
    }
    var method = 0usize
    if str.eq(c.name, "d_1") { method = 1usize }
    if str.eq(c.name, "d_2") { method = 2usize }
    if str.eq(c.name, "d_3") { method = 3usize }
    if str.eq(c.name, "d_4") { method = 4usize }
    if str.eq(c.name, "d_5") { method = 5usize }
    if str.eq(c.name, "d_6") { method = 6usize }
    if str.eq(c.name, "d_7") { method = 7usize }
    if str.eq(c.name, "d_8") { method = 8usize }
    if str.eq(c.name, "d_9") { method = 9usize }
    if str.eq(c.name, "d_10") { method = 10usize }
    if str.eq(c.name, "d_11") { method = 11usize }
    if str.eq(c.name, "d_12") { method = 12usize }
    if str.eq(c.name, "d_13") { method = 13usize }
    if str.eq(c.name, "d_14") { method = 14usize }
    if str.eq(c.name, "d_15") { method = 15usize }
    if str.eq(c.name, "d_16") { method = 16usize }
    if str.eq(c.name, "d_17") { method = 17usize }
    if method == 17usize {
        // mahalanobis whitens the whole matrix, so the distance matrix is built once
        let (md, e17) = mem.alloc[f64](a, nr * nr)
        if e17 != ok { ret nan }
        if vg.mahalanobis_dist(a, m, nr, nc, md) != ok { ret nan }
        var pos = 1usize
        var cb = 0usize
        while cb < nr {
            var ra = cb + 1usize
            while ra < nr {
                s += md[ra * nr + cb] * f64(pos)
                pos += 1usize
                ra += 1usize
            }
            cb += 1usize
        }
        ret s
    }
    // R lists the lower triangle by columns
    var pos = 1usize
    var cb = 0usize
    while cb < nr {
        var ra = cb + 1usize
        while ra < nr {
            s += vg.vegdist(m, nr, nc, ra, cb, method) * f64(pos)
            pos += 1usize
            ra += 1usize
        }
        cb += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vegan.json")
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
