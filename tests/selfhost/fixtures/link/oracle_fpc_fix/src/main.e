// e.algo.stat.fpc_fix against fpc. tests/oracle/fpc_fix.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_fix`; the layout is at the top of scripts/r_oracle/groups/fpc_fix.R.

use e.algo.stat.fpc_fix as ff
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn is(c: *const oracle.Case, s: str) -> bool {
    if c.name.len != s.len { ret false }
    var i = 0usize
    while i < s.len {
        if c.name[i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn weighted(v: []const f64, m: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < m {
        t += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret t
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if is(c, "wf") { ret ff.wfu1(z[0usize], z[1usize], z[2usize]) }
    if is(c, "mc") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (gv, e1) = mem.alloc[f64](a, n)
        let (cv, e2) = mem.alloc[f64](a, p * p)
        let (cl, e3) = mem.alloc[usize](a, n)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
        var i = 0usize
        while i < n {
            cl[i] = 1usize
            i += 1usize
        }
        let x = z[4usize..4usize + n * p]
        let (kk, e4) = ff.cov_all(a, x, n, p, cv)
        if e4 != ok { os.exit(5) }
        let e5 = ff.mahalconf(a, x, n, p, usize(z[2usize]), usize(z[3usize]), cv, gv)
        if e5 != ok { os.exit(6) }
        ret gv[usize(z[4usize + n * p])]
    }
    let what = usize(z[0usize])
    let k = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let mode = usize(z[4usize])
    let startn = usize(z[5usize])
    let mnc = usize(z[6usize])
    let mer = z[7usize]
    let distcut = z[8usize]
    let ca = z[9usize]
    let ca2 = z[10usize]
    let ind = z[11usize] > 0.5f64
    let ninit = usize(z[12usize])
    let ncmax = usize(z[13usize])
    let x = z[14usize..14usize + n * p]
    let init = z[14usize + n * p..14usize + n * p + ninit * n]
    let (out, e1) = mem.alloc[f64](a, ff.fx_len(ncmax, n, p, ninit))
    if e1 != ok { os.exit(4) }
    let e = ff.fixmahal(a, x, n, p, mode, ca, ca2, true, startn, mnc, mer, distcut, 5usize * n, f64(n) * 1.0e-5f64, init, ninit, ind, ncmax, out)
    if e != ok { os.exit(6) }
    let nc = usize(out[0usize])
    if what == 0usize { ret out[k] }
    let np = ncmax * (ncmax + 1usize) / 2usize
    let b0 = 5usize
    let grb = 5usize + 7usize * ncmax + ncmax * (ncmax + 1usize)
    let mb = grb + ninit
    if k == 0usize { ret weighted(out[b0..b0 + ncmax], ncmax) }
    if k == 1usize { ret weighted(out[b0 + ncmax..b0 + 2usize * ncmax], ncmax) }
    if k == 2usize { ret weighted(out[b0 + 2usize * ncmax..b0 + 2usize * ncmax + np], np) }
    if k == 3usize { ret weighted(out[b0 + 2usize * ncmax + np..b0 + 2usize * ncmax + 2usize * np], np) }
    let sb = b0 + 2usize * ncmax + 2usize * np
    if k >= 4usize && k <= 8usize { ret weighted(out[sb + (k - 4usize) * ncmax..sb + (k - 3usize) * ncmax], ncmax) }
    if k == 9usize { ret weighted(out[grb..grb + ninit], ninit) }
    if k == 10usize { ret weighted(out[mb..mb + nc * p], nc * p) }
    if k == 11usize { ret weighted(out[mb + ncmax * p..mb + ncmax * p + nc * p * p], nc * p * p) }
    let gb = mb + ncmax * p + ncmax * p * p
    if k == 12usize { ret weighted(out[gb..gb + nc * n], nc * n) }
    let stn = usize(out[4usize])
    if k == 14usize {
        // simmatrix: the packed matrix of imatrix[sfpc[sto[i]], sfpc[sto[j]]], i <= j
        var ts = 0.0f64
        var si = 0usize
        while si < stn {
            var sj = si
            while sj < stn {
                let ci = usize(out[sb + 3usize * ncmax + usize(out[sb + 4usize * ncmax + si]) - 1usize]) - 1usize
                let cj = usize(out[sb + 3usize * ncmax + usize(out[sb + 4usize * ncmax + sj]) - 1usize]) - 1usize
                ts += f64(ff.sseg0(si, sj) + 1usize) * out[b0 + 2usize * ncmax + ff.sseg0(ci, cj)]
                sj += 1usize
            }
            si += 1usize
        }
        ret ts
    }
    // 13: fpclusters, the weights of the stn clusters sfpc[sto[i]]
    var t = 0.0f64
    var pos = 0usize
    var i = 0usize
    while i < stn {
        let cl = usize(out[sb + 4usize * ncmax + i]) - 1usize
        let g = usize(out[sb + 3usize * ncmax + cl]) - 1usize
        var r = 0usize
        while r < n {
            pos += 1usize
            t += f64(pos) * out[gb + g * n + r]
            r += 1usize
        }
        i += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_fix.json")
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
                if c.args.len > 14usize { c2.args = c.args[0usize..14usize] }
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
