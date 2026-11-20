// e.algo.stat.mcmcpackordfa against MCMCordfactanal and MCMCirtKd. tests/oracle/mcmcpackordfa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackordfa`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackordfa.R.

use e.algo.stat.mcmcpackordfa as mo
use e.algo.stat.mcmcpacksamp as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(m: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m.len {
        s += f64(i + 1usize) * m[i]
        i += 1usize
    }
    ret s
}

fn moves(out: []const f64, nstore: usize, width: usize, c: usize) -> bool {
    var r = 1usize
    while r < nstore {
        if out[r * width + c] != out[c] { ret true }
        r += 1usize
    }
    ret false
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = u64(z[0usize])
    var g: ms.Sc = zero
    ms.sc_seed(&g, seed)
    let irt = z[1usize] == 1.0f64
    let n = usize(z[2usize])
    let kn = usize(z[3usize])
    let d = usize(z[4usize])
    let maxc = usize(z[5usize])
    let burn = usize(z[6usize])
    let mc = usize(z[7usize])
    let thin = usize(z[8usize])
    let sl = z[9usize] != 0.0f64
    let ss = z[10usize] != 0.0f64
    var o = 11usize
    let tune = z[o..o + kn]
    o += kn
    let ncat = z[o..o + kn]
    o += kn
    let x = z[o..o + n * kn]
    o += n * kn
    let eq = z[o..o + kn * d]
    o += kn * d
    let ineq = z[o..o + kn * d]
    o += kn * d
    let (l0, e1) = mem.alloc[f64](a, kn * d)
    let (lam0, e2) = mem.alloc[f64](a, kn * d)
    let (gm0, e3) = mem.alloc[f64](a, (maxc + 1usize) * kn)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < kn * d {
        l0[i] = z[o + i]
        if irt && i % d == 0usize { l0[i] = -1.0f64 * l0[i] }
        i += 1usize
    }
    let bl0 = z[o + kn * d..o + 2usize * kn * d]
    o += 2usize * kn * d
    if str.eq(c.name, "ordd") {
        if mo.ord_start(a, x, n, kn, d, ncat, maxc, eq, ineq, lam0, gm0) != ok { ret nan }
    } else {
        i = 0usize
        while i < kn * d {
            lam0[i] = z[o + i]
            i += 1usize
        }
        i = 0usize
        while i < (maxc + 1usize) * kn {
            gm0[i] = z[o + kn * d + i]
            i += 1usize
        }
    }
    let nstore = mc / thin
    var width = (maxc + 1usize) * kn
    if sl { width += kn * d }
    if ss { width += n * d }
    let (out, e4) = mem.alloc[f64](a, nstore * width)
    let (cm, e5) = mem.alloc[f64](a, nstore * width)
    if e4 != ok || e5 != ok { ret nan }
    if mo.ordfactanal(a, &g, x, n, kn, d, ncat, maxc, tune, lam0, gm0, eq, ineq, l0, bl0, burn, mc, thin, sl, ss, out) != ok { ret nan }
    if irt && sl {
        var r = 0usize
        while r < nstore {
            i = 0usize
            while i < kn * d {
                if i % d == 0usize { out[r * width + i] = -1.0f64 * out[r * width + i] }
                i += 1usize
            }
            r += 1usize
        }
    }
    var kept = 0usize
    var cidx = 0usize
    while cidx < width {
        if moves(out, nstore, width, cidx) { kept += 1usize }
        cidx += 1usize
    }
    var q = 0usize
    cidx = 0usize
    while cidx < width {
        if moves(out, nstore, width, cidx) {
            var r = 0usize
            while r < nstore {
                cm[r * kept + q] = out[r * width + cidx]
                r += 1usize
            }
            q += 1usize
        }
        cidx += 1usize
    }
    ret wsum(cm[0usize..nstore * kept])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackordfa.json")
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
