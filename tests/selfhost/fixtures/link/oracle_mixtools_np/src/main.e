// e.algo.stat.mixtools_np (npEM, spEMsymloc) against mixtools. tests/oracle/mixtools_np.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixtools_np`; the argument layout is at the top of scripts/r_oracle/groups/mixtools_np.R.

use e.algo.rand.r as rg
use e.algo.stat.mixtools_np as np
use e.algo.stat.modeest as me
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// spEMsymloc: [sel, idx, seed, m, hasc, bw, maxit, stoch, n, x(n), centers(m)]
fn answer_sp(a: *mem.Arena, x: []const f64) -> f64 {
    let sel = usize(x[0usize])
    let idx = usize(x[1usize])
    var g: rg.Rng = zero
    rg.seed(&g, i64(x[2usize]))
    let m = usize(x[3usize])
    let n = usize(x[8usize])
    let data = x[9usize..9usize + n]
    var cen = x[9usize + n..9usize + n]
    if x[4usize] != 0.0f64 { cen = x[9usize + n..9usize + n + m] }
    var bw = x[5usize]
    if bw == 0.0f64 {
        let (b0, eb) = me.bw_nrd0(a, data)
        if eb != ok { os.exit(7) }
        bw = b0
    }
    let (f, e) = np.sp_em_symloc(a, &g, data, m, cen, bw, 1.0e-8f64, usize(x[6usize]), x[7usize] != 0.0f64)
    if e != ok { os.exit(8) }
    if sel == 1usize { ret f64(f.lambda.len / m) }
    let nr = f.lambda.len / m
    if sel == 2usize { ret f.lambdahat[idx - 1usize] }
    if sel == 3usize { ret f.muhat[idx - 1usize] }
    if sel == 4usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f.post[i * m + idx - 1usize] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sel == 5usize { ret f.lambda[idx - 1usize] }
    if sel == 6usize { ret f.mu[(nr - 1usize) * m + idx - 1usize] }
    if sel == 7usize { ret f.lambda[(nr - 1usize) * m + idx - 1usize] }
    ret f.mu[idx - 1usize]
}

// npEM: [sel, idx, seed, m, hasc, samebw, stoch, bw, maxit, n, r, x(n r), blockid(r), centers(m r)]
fn answer_np(a: *mem.Arena, x: []const f64) -> f64 {
    let sel = usize(x[0usize])
    let idx = usize(x[1usize])
    var g: rg.Rng = zero
    rg.seed(&g, i64(x[2usize]))
    let m = usize(x[3usize])
    let n = usize(x[9usize])
    let r = usize(x[10usize])
    let data = x[11usize..11usize + n * r]
    let bl = x[11usize + n * r..11usize + n * r + r]
    var cen = x[11usize + n * r + r..11usize + n * r + r]
    if x[4usize] != 0.0f64 { cen = x[11usize + n * r + r..11usize + n * r + r + m * r] }
    let (blk, eb0) = mem.alloc[usize](a, r + 1usize)
    if eb0 != ok { os.exit(6) }
    var q = 0usize
    while q < r {
        blk[q] = usize(bl[q])
        q += 1usize
    }
    var bw = x[7usize]
    if bw == 0.0f64 {
        let (b0, eb) = me.bw_nrd0(a, data)
        if eb != ok { os.exit(7) }
        bw = b0
    }
    let (f, e) = np.np_em(a, &g, data, n, r, m, cen, blk[0usize..r], bw, x[5usize] != 0.0f64, 1.0e-8f64, usize(x[8usize]), x[6usize] != 0.0f64)
    if e != ok { os.exit(8) }
    if sel == 1usize { ret f64(f.lambda.len / m) }
    if sel == 2usize { ret f.lambdahat[idx - 1usize] }
    if sel == 3usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f.post[i * m + idx - 1usize] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sel == 4usize { ret f.lambda[idx - 1usize] }
    if sel == 5usize { ret f.loglik[idx - 1usize] }
    if sel == 6usize {
        if x[5usize] != 0.0f64 { ret bw }
        ret f.bw[idx - 1usize]
    }
    ret f64(f.loglik.len)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let kind = c.name
    if str.eq(kind, "sp") { ret answer_sp(a, c.args) }
    if str.eq(kind, "np") { ret answer_np(a, c.args) }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixtools_np.json")
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
