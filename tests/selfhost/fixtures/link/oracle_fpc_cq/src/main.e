// e.algo.stat.fpc_cq against fpc cqcluster.stats. tests/oracle/fpc_cq.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_cq`; the layout is at the top of scripts/r_oracle/groups/fpc_cq.R.

use e.algo.stat.fpc_cq as fq
use e.algo.stat.fpc_coord as fc
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let what = usize(z[0usize])
    let kind = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let cn = usize(z[4usize])
    let noise = z[5usize] > 0.5f64
    let flags = usize(z[6usize])
    let stdmode = usize(z[7usize])
    let sepall = z[8usize] > 0.5f64
    let sepwn = z[9usize] > 0.5f64
    let sepprob = z[10usize]
    let dq = z[11usize]
    let nnk = usize(z[12usize])
    let nndist = z[13usize] > 0.5f64
    let k2 = usize(z[14usize])
    let (cl, e0) = mem.alloc[usize](a, n)
    let (alt, e1) = mem.alloc[usize](a, n)
    let (d, e2) = mem.alloc[f64](a, n * n)
    let (out, e3) = mem.alloc[f64](a, fq.cq_len(cn, n))
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        cl[i] = usize(z[15usize + i])
        i += 1usize
    }
    var na = 0usize
    if k2 > 0usize { na = n }
    i = 0usize
    while i < na {
        alt[i] = usize(z[15usize + n + i])
        i += 1usize
    }
    fc.euclid(z[15usize + n + na..15usize + n + na + n * p], n, p, d)
    let e = fq.cq(a, d, n, cl, cn, noise, flags, stdmode, sepall, sepwn, sepprob, dq, nnk, nndist, alt, k2, out)
    if e != ok { os.exit(6) }
    if kind == 0usize { ret out[what] }
    // vector what: offset and length in out
    var off = 40usize
    var len = cn
    if what == 1usize { off = 40usize + cn }
    if what == 2usize { off = 40usize + 2usize * cn }
    if what == 3usize { off = 40usize + 3usize * cn }
    if what >= 4usize && what <= 8usize {
        off = 40usize + 4usize * cn + (what - 4usize) * n
        len = n
    }
    if what == 9usize {
        off = 40usize + 4usize * cn + 5usize * n
        len = usize(out[32usize])
    }
    if what >= 10usize {
        off = 40usize + 4usize * cn + (what - 4usize) * n
        len = 0usize
        i = 0usize
        while i < n {
            if out[off + i] == out[off + i] { len = i + 1usize }
            i += 1usize
        }
        // flat length: the labels of the clusters without noise
        var m = 0usize
        i = 0usize
        while i < n {
            if !noise || cl[i] != cn { m += 1usize }
            i += 1usize
        }
        len = m
    }
    var t = 0.0f64
    i = 0usize
    while i < len {
        let v = out[off + i]
        if v == v && v < 1.0e300f64 && v > -1.0e300f64 { t += f64(i + 1usize) * v }
        i += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_cq.json")
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
                var c2 = *c
                c2.args = c.args[0usize..8usize]
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
