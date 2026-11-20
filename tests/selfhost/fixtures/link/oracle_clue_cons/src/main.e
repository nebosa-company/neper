// e.algo.stat.cluecons against clue cl_consensus and cl_medoid. tests/oracle/clue_cons.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_cons`; the layout is at the top of scripts/r_oracle/groups/clue_cons.R.

use e.algo.rand.r as rr
use e.algo.stat.cluecons as cc
use e.algo.stat.cluelsap as ls
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

fn labels(a: *mem.Arena, z: []const f64, bn: usize, n: usize) -> []usize {
    let (lab, e) = mem.alloc[usize](a, bn * n)
    if e != ok { os.exit(6) }
    var i = 0usize
    while i < bn * n {
        lab[i] = usize(z[i])
        i += 1usize
    }
    ret lab
}

fn membs(a: *mem.Arena, lab: []const usize, bn: usize, n: usize, k: usize) -> []f64 {
    let (mm, e) = mem.alloc[f64](a, bn * n * k)
    if e != ok { os.exit(7) }
    var b = 0usize
    while b < bn {
        ls.membership_hard(lab[b * n..(b + 1usize) * n], n, k, mm[b * n * k..(b + 1usize) * n * k])
        b += 1usize
    }
    ret mm
}

fn checksum(m: []const f64, n: usize, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            s += m[i * k + j] * f64(10usize * (i + 1usize) + j + 1usize)
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// "ao": see scripts/r_oracle/groups/clue_cons.R
fn ao_case(a: *mem.Arena, z: []const f64) -> f64 {
    let kind = usize(z[0usize])
    let nruns = usize(z[1usize])
    let seed = z[2usize]
    let bn = usize(z[3usize])
    let n = usize(z[4usize])
    let k = usize(z[5usize])
    let w = z[6usize..6usize + bn]
    let mems = z[6usize + bn..6usize + bn + bn * n * k]
    let (starts, e0) = mem.alloc[f64](a, nruns * n * k)
    let (out, e1) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok { os.exit(12) }
    var i = 0usize
    if seed > 0.5f64 {
        var g: rr.Rng = zero
        rr.seed(&g, i64(seed))
        var r = 0usize
        while r < nruns {
            // matrix(runif(n * k), n, k) is filled by column, then every row is scaled to sum one
            var j = 0usize
            while j < k {
                i = 0usize
                while i < n {
                    starts[r * n * k + i * k + j] = rr.unif(&g)
                    i += 1usize
                }
                j += 1usize
            }
            i = 0usize
            while i < n {
                var s = 0.0f64
                j = 0usize
                while j < k {
                    s += starts[r * n * k + i * k + j]
                    j += 1usize
                }
                j = 0usize
                while j < k {
                    starts[r * n * k + i * k + j] = starts[r * n * k + i * k + j] / s
                    j += 1usize
                }
                i += 1usize
            }
            r += 1usize
        }
    } else {
        i = 0usize
        while i < nruns * n * k {
            starts[i] = z[6usize + bn + bn * n * k + i]
            i += 1usize
        }
    }
    let (v, e) = cc.consensus_runs(a, mems, w, bn, n, k, starts, nruns, kind, 100usize, 1.4901161193847656e-8f64, out)
    let _ = v
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret checksum(out, n, k)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "ao") { ret ao_case(a, z) }
    let bn = usize(z[0usize])
    let n = usize(z[1usize])
    if str.eq(c.name, "maj") {
        let w = z[2usize..2usize + bn]
        let (trees, et) = mem.alloc[hc.Tree](a, bn)
        if et != ok { os.exit(8) }
        var b = 0usize
        while b < bn {
            let px = z[2usize + 2usize * bn + b * 2usize * n..2usize + 2usize * bn + (b + 1usize) * 2usize * n]
            let (t, e) = hc.hclust(a, dmat(a, px, n), n, usize(z[2usize + bn + b]))
            if e != ok { os.exit(9) }
            trees[b] = t
            b += 1usize
        }
        let (d, ed) = mem.alloc[f64](a, n * n)
        if ed != ok { os.exit(10) }
        if cc.consensus_majority(a, trees, w, n, d) != ok { ret 0.0f64 / 0.0f64 }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                s += d[i * n + j] * f64(7usize * (i + 1usize) + 3usize * (j + 1usize) + 1usize)
                j += 1usize
            }
            i += 1usize
        }
        ret s
    }
    let k = usize(z[2usize])
    if str.eq(c.name, "medoid") {
        let (best, e) = cc.medoid(a, labels(a, z[3usize..3usize + bn * n], bn, n), bn, n, k)
        if e != ok { ret 0.0f64 / 0.0f64 }
        ret f64(best + 1usize)
    }
    let (out, eo) = mem.alloc[f64](a, n * k)
    if eo != ok { os.exit(11) }
    let w = z[3usize..3usize + bn]
    if str.eq(c.name, "se") {
        let st = z[3usize + bn..3usize + bn + n * k]
        let lab = labels(a, z[3usize + bn + n * k..3usize + bn + n * k + bn * n], bn, n)
        let (v, e) = cc.consensus_se(a, membs(a, lab, bn, n, k), w, bn, n, k, st, 100usize, 1.4901161193847656e-8f64, out)
        let _ = v
        if e != ok { ret 0.0f64 / 0.0f64 }
        ret checksum(out, n, k)
    }
    let lab = labels(a, z[3usize + bn..3usize + bn + bn * n], bn, n)
    if cc.consensus_dwh(a, membs(a, lab, bn, n, k), w, bn, n, k, out) != ok { ret 0.0f64 / 0.0f64 }
    ret checksum(out, n, k)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_cons.json")
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
