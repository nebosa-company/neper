// e.algo.stat.clueultra against clue cl_consensus of hclust trees, methods "euclidean" and "manhattan". tests/oracle/clue_ultra.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_ultra`; the layout is at the top of scripts/r_oracle/groups/clue_ultra.R.

use e.algo.rand.r as rr
use e.algo.stat.clueultra as cu
use e.algo.stat.hclust as hc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn dmat(a: *mem.Arena, x: []const f64, n: usize) -> []f64 {
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[2usize * i] - x[2usize * j]
            let dy = x[2usize * i + 1usize] - x[2usize * j + 1usize]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    ret d
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let nruns = usize(z[1usize])
    let seed = i64(z[2usize])
    let bn = usize(z[3usize])
    let n = usize(z[4usize])
    let w = z[5usize..5usize + bn]
    let np = n * (n - 1usize) / 2usize
    let (us, e0) = mem.alloc[f64](a, bn * np)
    let (out, e1) = mem.alloc[f64](a, n * n)
    if e0 != ok || e1 != ok { os.exit(6) }
    var b = 0usize
    while b < bn {
        let px = z[5usize + 2usize * bn + b * 2usize * n..5usize + 2usize * bn + (b + 1usize) * 2usize * n]
        var (t, e) = hc.hclust(a, dmat(a, px, n), n, usize(z[5usize + bn + b]))
        if e != ok { os.exit(9) }
        var q = 0usize
        var cc = 0usize
        while cc < n {
            var r = cc + 1usize
            while r < n {
                us[b * np + q] = hc.cophenetic(a, &t, n, r, cc)
                q += 1usize
                r += 1usize
            }
            cc += 1usize
        }
        b += 1usize
    }
    if str.eq(c.name, "coph") {
        var t2 = 0.0f64
        var b2 = 0usize
        while b2 < bn {
            var q2 = 0usize
            while q2 < np {
                t2 += us[b2 * np + q2] * f64(q2 + 1usize) * f64(b2 + 1usize)
                q2 += 1usize
            }
            b2 += 1usize
        }
        ret t2
    }
    if str.eq(c.name, "cophbits") {
        var t3 = 0.0f64
        var q3 = 0usize
        while q3 < bn * np {
            t3 += f64(mem.bitcast[u64](us[q3]) & 16777215u64)
            q3 += 1usize
        }
        ret t3
    }
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    if str.eq(c.name, "medbits") || str.eq(c.name, "sdbits") {
        let (v0, e5) = cu.consensus_ultra(a, &g, us, w, bn, n, kind, nruns, 1usize, out)
        let _ = v0
        if e5 != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "sdbits") { ret f64(mem.bitcast[u64](out[np]) & 16777215u64) }
        var t4 = 0.0f64
        var q4 = 0usize
        while q4 < np {
            t4 += f64(mem.bitcast[u64](out[q4]) & 16777215u64)
            q4 += 1usize
        }
        ret t4
    }
    if str.eq(c.name, "fbits") {
        let (v1, e6) = cu.consensus_ultra(a, &g, us, w, bn, n, kind, nruns, 100usize, out)
        let _ = v1
        if e6 != ok { ret 0.0f64 / 0.0f64 }
        let which = usize(z[z.len - 1usize])
        if which == 0usize {
            var t6 = 0.0f64
            var q6 = 0usize
            while q6 < np {
                t6 += f64(mem.bitcast[u64](out[q6]) & 16777215u64)
                q6 += 1usize
            }
            ret t6
        }
        ret f64(mem.bitcast[u64](out[np + which - 1usize]) & 16777215u64)
    }
    if str.eq(c.name, "cgx") {
        let (v1, e6) = cu.consensus_ultra(a, &g, us, w, bn, n, kind, nruns, 1usize + usize(z[z.len - 1usize]), out)
        let _ = v1
        if e6 != ok { ret 0.0f64 / 0.0f64 }
        var t5 = 0.0f64
        var q5 = 0usize
        while q5 < np {
            t5 += out[q5] * f64(q5 + 1usize)
            q5 += 1usize
        }
        ret t5
    }
    let (v, e2) = cu.consensus_ultra(a, &g, us, w, bn, n, kind, nruns, 0usize, out)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "ultv") { ret v }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            s += out[i * n + j] * f64(7usize * (i + 1usize) + 3usize * (j + 1usize) + 1usize)
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_ultra.json")
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
