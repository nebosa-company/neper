// e.ml.cluster.density's hdbscan against dbscan::hdbscan. tests/oracle/dbscan_hdbscan.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dbscan_hdbscan`; the checksum each q selects is listed at the top of
// scripts/r_oracle/groups/dbscan_hdbscan.R.

use e.io
use e.ml.cluster.density as dn
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let d = usize(z[1usize])
    let q = usize(z[4usize])
    let (h, e) = dn.hdbscan(a, z[5usize..5usize + n * d], n, d, usize(z[2usize]), z[3usize])
    if e != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if q == 0usize {
        while i < n {
            s += f64(i + 1usize) * f64(h.cluster[i])
            i += 1usize
        }
    }
    if q == 1usize {
        while i < n {
            if f64(h.cluster[i]) > s { s = f64(h.cluster[i]) }
            i += 1usize
        }
    }
    if q == 2usize {
        while i < n {
            s += f64(i + 1usize) * h.prob[i]
            i += 1usize
        }
    }
    if q == 3usize {
        while i < n {
            s += f64(i + 1usize) * h.glosh[i]
            i += 1usize
        }
    }
    if q == 4usize {
        while i < h.nsal {
            s += f64(i + 1usize) * h.cscore[i]
            i += 1usize
        }
    }
    if q == 5usize {
        while i < n {
            s += f64(i + 1usize) * h.coredist[i]
            i += 1usize
        }
    }
    if q >= 6usize && q <= 8usize {
        while i < n - 1usize {
            var v = h.mheight[i]
            if q == 7usize { v = f64(h.mleft[i]) }
            if q == 8usize { v = f64(h.mright[i]) }
            s += f64(i + 1usize) * v
            i += 1usize
        }
    }
    if q == 9usize { s = f64(h.ncl) }
    if q >= 10usize && q <= 13usize {
        while i < h.ncl {
            var v = f64(i) * h.stab[i]
            if q == 11usize { v = f64(i + 1usize) * h.birth[i] }
            if q == 12usize { v = f64(i + 1usize) * h.death[i] }
            if q == 13usize { v = f64(i + 1usize) * f64(h.nch[i]) }
            s += v
            i += 1usize
        }
    }
    if q == 14usize || q == 15usize || q == 18usize {
        while i < n {
            var v = h.seq_eps[i]
            if q == 15usize { v = f64(h.seq_pt[i] + 1usize) }
            if q == 18usize { v = 1.0f64 }
            s += f64(h.seq_cl[i] + 1usize) * v
            i += 1usize
        }
    }
    if q == 16usize {
        while i < h.ncl {
            s += f64(i) * (7.0f64 * f64(h.ch1[i]) + f64(h.ch2[i]))
            i += 1usize
        }
    }
    if q == 17usize {
        while i < h.nsal {
            s += f64(i + 1usize) * f64(h.sal[i])
            i += 1usize
        }
    }
    if q == 19usize {
        while i < n {
            s += f64(i + 1usize) * f64(h.order[i])
            i += 1usize
        }
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dbscan_hdbscan.json")
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
