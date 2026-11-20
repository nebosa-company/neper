// e.algo.stat.mcmcpackord against the MCMCpack ordinal samplers. tests/oracle/mcmcpackord.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackord`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackord.R.

use e.algo.stat.mcmcpackfa as mf
use e.algo.stat.mcmcpackord as mo
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = u64(z[0usize])
    var g: ms.Sc = zero
    ms.sc_seed(&g, seed)
    if str.eq(c.name, "fa") {
        let n = usize(z[1usize])
        let kn = usize(z[2usize])
        let d = usize(z[3usize])
        let sv = z[4usize] != 0.0f64
        let burn = usize(z[5usize])
        let mc = usize(z[6usize])
        let thin = usize(z[7usize])
        let sc = z[8usize] != 0.0f64
        var o = 9usize
        let x = z[o..o + n * kn]
        o += n * kn
        let eq = z[o..o + kn * d]
        o += kn * d
        let ineq = z[o..o + kn * d]
        o += kn * d
        let l0 = z[o..o + kn * d]
        o += kn * d
        let bl0 = z[o..o + kn * d]
        o += kn * d
        let a0 = z[o..o + kn]
        let b0 = z[o + kn..o + 2usize * kn]
        let nstore = mc / thin
        var width = kn * d + kn
        if sc { width += n * d }
        let (out, e1) = mem.alloc[f64](a, nstore * width)
        if e1 != ok { ret nan }
        if mf.factanal(a, &g, x, n, kn, d, sv, eq, ineq, l0, bl0, a0, b0, burn, mc, thin, sc, out) != ok { ret nan }
        // R drops the columns that never move
        let (cm, e2) = mem.alloc[f64](a, nstore * width)
        if e2 != ok { ret nan }
        var kept = 0usize
        var cidx = 0usize
        while cidx < width {
            var moves = false
            var r = 1usize
            while r < nstore {
                if out[r * width + cidx] != out[cidx] { moves = true }
                r += 1usize
            }
            if moves {
                kept += 1usize
            }
            cidx += 1usize
        }
        var q = 0usize
        cidx = 0usize
        while cidx < width {
            var moves = false
            var r = 1usize
            while r < nstore {
                if out[r * width + cidx] != out[cidx] { moves = true }
                r += 1usize
            }
            if moves {
                r = 0usize
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
    if str.eq(c.name, "oprobit_start") {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        let ncat = usize(z[3usize])
        let (gam, e1) = mem.alloc[f64](a, ncat + 1usize)
        let (bet, e2) = mem.alloc[f64](a, k)
        let (v, e3) = mem.alloc[f64](a, k + ncat - 2usize)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        if mo.oprobit_start(a, z[8usize..8usize + n], z[8usize + n..8usize + n + n * k], n, k, ncat, gam, bet) != ok { ret nan }
        var i = 0usize
        while i < k {
            v[i] = bet[i]
            i += 1usize
        }
        i = 2usize
        while i < ncat {
            v[k + i - 2usize] = gam[i]
            i += 1usize
        }
        ret wsum(v)
    }
    if str.eq(c.name, "oprobit") || str.eq(c.name, "oprobitpolr") {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        let ncat = usize(z[3usize])
        let burn = usize(z[4usize])
        let mc = usize(z[5usize])
        let thin = usize(z[6usize])
        let tune = z[7usize]
        let y = z[8usize..8usize + n]
        let x = z[8usize + n..8usize + n + n * k]
        let o = 8usize + n + n * k
        let nstore = mc / thin
        let (out, e1) = mem.alloc[f64](a, nstore * (k + ncat - 2usize))
        if e1 != ok { ret nan }
        let bb = z[o + k..o + k + k * k]
        var e = ok
        if str.eq(c.name, "oprobitpolr") { e = mo.oprobit_cowles_polr(a, &g, y, x, n, k, ncat, tune, z[o..o + k], bb, burn, mc, thin, out) } else {
            let so = o + k + k * k
            e = mo.oprobit_cowles(a, &g, y, x, n, k, ncat, tune, z[so + k..so + k + ncat + 1usize], z[so..so + k], z[o..o + k], bb, burn, mc, thin, out)
        }
        if e != ok { ret nan }
        ret wsum(out)
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackord.json")
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
