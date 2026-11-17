// e.algo.stat.varsstab (the processes of vars::stability) against strucchange as vars calls it. tests/oracle/vars_stab.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vars_stab`; the case layout is at the top of scripts/r_oracle/groups/vars_stab.R.

use e.algo.rand.r as rng
use e.algo.stat.vars2 as vr
use e.algo.stat.varsstab as sb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn gen(a: *mem.Arena, seed: i64, t0: usize, k: usize, nexo: usize, slope: f64, y: []f64, exo: []f64) {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let am = vr.zeros(a, k * k)
    var i = 0usize
    while i < k * k {
        am[i] = rng.runif(&rg, 0.0f64 - 0.3f64, 0.3f64)
        i += 1usize
    }
    i = 0usize
    while i < t0 * k {
        y[i] = 0.0f64
        i += 1usize
    }
    var t = 1usize
    while t < t0 {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += am[l * k + j] * y[(t - 1usize) * k + l]
                l += 1usize
            }
            y[t * k + j] = s
            j += 1usize
        }
        j = 0usize
        while j < k {
            y[t * k + j] = y[t * k + j] + rng.norm(&rg)
            j += 1usize
        }
        j = 0usize
        while j < k {
            y[t * k + j] = y[t * k + j] + slope * f64(t + 1usize)
            j += 1usize
        }
        t += 1usize
    }
    var c = 0usize
    while c < nexo {
        t = 0usize
        while t < t0 {
            exo[t * nexo + c] = rng.norm(&rg)
            t += 1usize
        }
        c += 1usize
    }
}

// the weighted sum with R's column-major positions of a rows by cols row-major matrix
fn wsum_cm(x: []const f64, rows: usize, cols: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < cols {
        var i = 0usize
        while i < rows {
            s += x[i * cols + j] * f64(j * rows + i + 1usize)
            i += 1usize
        }
        j += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let seed = i64(x[0usize])
    let t0 = usize(x[1usize])
    let k = usize(x[2usize])
    let p = usize(x[3usize])
    let det = usize(x[4usize])
    let season = usize(x[5usize])
    let nexo = usize(x[6usize])
    let slope = x[7usize]
    var ty = usize(x[8usize])
    if ty == 8usize { ty = 4usize }
    let eq = usize(x[9usize]) - 1usize
    let h = x[10usize]
    let resc = x[11usize] == 1.0f64
    let fu = usize(x[12usize])
    let y = vr.zeros(a, t0 * k)
    let exo = vr.zeros(a, t0 * nexo)
    gen(a, seed, t0, k, nexo, slope, y, exo)
    let (v, ve) = vr.var_new(a, y, t0, k, p, det, season, exo, nexo)
    if ve != ok { os.exit(31) }
    let yy = vr.zeros(a, v.obs)
    var t = 0usize
    while t < v.obs {
        yy[t] = v.yend[t * k + eq]
        t += 1usize
    }
    let proc = vr.zeros(a, (v.obs + 2usize) * (v.nz + 1usize))
    let (rows, cols, pe) = sb.efp_process(a, v.z, yy, v.obs, v.nz, ty, h, resc, proc)
    if pe != ok { os.exit(32) }
    let nm = c.name
    if str.eq(nm, "proc") { ret wsum_cm(proc, rows, cols) }
    let st = sb.sctest_stat(a, proc, rows, cols, ty, fu)
    if str.eq(nm, "stat") { ret st }
    if fu == 0usize { ret sb.sctest_p(st, ty, cols) }
    // the range functional of the bridge limits
    ret sb.p_bridge_range(st, cols)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vars_stab.json")
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
