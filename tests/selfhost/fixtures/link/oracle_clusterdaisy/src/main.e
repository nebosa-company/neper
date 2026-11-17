// e.algo.stat.clusterdiss (daisy, silhouette) against cluster::daisy and cluster::silhouette. tests/oracle/clusterdaisy.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clusterdaisy`; the argument layouts are at the top of
// scripts/r_oracle/groups/clusterdaisy.R.

use e.algo.stat.clusterdiss as cd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn daisy_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let metric = usize(x[2usize])
    let stand = x[3usize] != 0.0f64
    let (vt, e1) = mem.alloc[usize](a, p)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < p {
        vt[i] = usize(x[4usize + i])
        i += 1usize
    }
    let wbase = 4usize + p
    let dbase = 4usize + 2usize * p
    let (m, e2) = mem.alloc[f64](a, n * p)
    if e2 != ok { os.exit(6) }
    i = 0usize
    while i < n * p {
        m[i] = x[dbase + i]
        if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    let np = n * (n - 1usize) / 2usize
    let (d, e3) = mem.alloc[f64](a, np)
    if e3 != ok { os.exit(7) }
    if cd.daisy(a, m, n, p, metric, stand, vt, x[wbase..wbase + p], d) != ok { os.exit(8) }
    var s = 0.0f64
    var na = 0.0f64
    i = 0usize
    while i < np {
        if d[i] != d[i] {
            na += f64(i + 1usize)
        } else {
            s += d[i] * f64(i + 1usize)
        }
        i += 1usize
    }
    if str.eq(c.name, "dna") { ret na }
    ret s
}

fn sil_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let ismat = x[1usize] != 0.0f64
    let ncl = usize(x[2usize])
    let (cl, e1) = mem.alloc[i64](a, n)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        cl[i] = i64(x[3usize + i])
        i += 1usize
    }
    let dbase = 3usize + n
    var dn = n * (n - 1usize) / 2usize
    if ismat { dn = n * n }
    let (w, e2) = mem.alloc[f64](a, n)
    if e2 != ok { os.exit(6) }
    let (nb, e3) = mem.alloc[i64](a, n)
    if e3 != ok { os.exit(7) }
    let (na, e4) = cd.silhouette_widths(a, cl, n, x[dbase..dbase + dn], ismat, w, nb)
    if e4 != ok { os.exit(8) }
    let nm = c.name
    if str.eq(nm, "silna") { ret f64(na) }
    if na != 0usize { os.exit(9) }
    var s = 0.0f64
    if str.eq(nm, "sw") {
        i = 0usize
        while i < n {
            s += w[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "sn") {
        i = 0usize
        while i < n {
            s += f64(nb[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "sorder") {
        let (o, e5) = cd.silhouette_order(a, cl, w, n)
        if e5 != ok { os.exit(10) }
        i = 0usize
        while i < n {
            s += f64(o[i] + 1usize) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "savg") {
        i = 0usize
        while i < n {
            s += w[i]
            i += 1usize
        }
        ret s / f64(n)
    }
    // per cluster, in sorted code order
    var done = 0usize
    var lo = 0i64
    var first = true
    var pos = 0usize
    while done < n {
        var cur = 0i64
        var have = false
        i = 0usize
        while i < n {
            if first || cl[i] > lo {
                if !have || cl[i] < cur {
                    cur = cl[i]
                    have = true
                }
            }
            i += 1usize
        }
        var cnt = 0usize
        var tot = 0.0f64
        i = 0usize
        while i < n {
            if cl[i] == cur {
                cnt += 1usize
                tot += w[i]
            }
            i += 1usize
        }
        pos += 1usize
        if str.eq(nm, "sclus") { s += tot / f64(cnt) * f64(pos) }
        if str.eq(nm, "ssize") { s += f64(cnt) * f64(pos) }
        done += cnt
        lo = cur
        first = false
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "dsum") || str.eq(c.name, "dna") { ret daisy_case(a, c) }
    ret sil_case(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clusterdaisy.json")
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
