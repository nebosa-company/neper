// e.algo.stat.spdepreg against spatialreg and spdep. tests/oracle/spdepreg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spdepreg`; the argument layout is at the top of scripts/r_oracle/groups/spdepreg.R.

use e.algo.stat.spdepreg as sr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let w = z[3usize..3usize + n * n]
    let x = z[3usize + n * n..3usize + n * n + n * m]
    let y = z[3usize + n * n + n * m..3usize + n * n + n * m + n]
    let p = z[3usize + n * n + n * m + n..z.len]
    let (out, e1) = mem.alloc[f64](a, 64usize)
    if e1 != ok { ret nan }
    let nm = c.name
    if str.eq(nm, "lag") {
        if sr.lag_ml(a, y, x, n, m, w, 1usize, out) != ok { ret nan }
        ret out[usize(p[0usize])]
    }
    if str.eq(nm, "err") {
        if sr.err_ml(a, y, x, n, m, w, 1usize, out) != ok { ret nan }
        ret out[usize(p[0usize])]
    }
    if str.eq(nm, "sac") {
        if sr.sac_ml(a, y, x, n, m, w, 1usize, out) != ok { ret nan }
        ret out[usize(p[0usize])]
    }
    if str.eq(nm, "imp_e") || str.eq(nm, "imp_t") {
        if sr.lag_ml(a, y, x, n, m, w, 1usize, out) != ok { ret nan }
        let (re, e2) = mem.alloc[f64](a, n)
        let (im, e3) = mem.alloc[f64](a, n)
        let (res, e4) = mem.alloc[f64](a, 3usize * m)
        if e2 != ok || e3 != ok || e4 != ok { ret nan }
        let rho = out[0usize]
        var beta: [8]f64 = zero
        var i = 0usize
        while i < m {
            beta[i] = out[7usize + i]
            i += 1usize
        }
        if str.eq(nm, "imp_e") {
            if sr.weig(a, w, n, 1usize, re, im) != ok { ret nan }
            sr.impacts_eig(re, im, n, rho, beta[0usize..m], m, res)
            ret res[usize(p[0usize])]
        }
        if sr.impacts_trace(a, w, n, usize(p[0usize]), rho, beta[0usize..m], m, res) != ok { ret nan }
        ret res[usize(p[1usize])]
    }
    if str.eq(nm, "rs") {
        if sr.rs_tests(a, y, x, n, m, w, out) != ok { ret nan }
        ret out[usize(p[0usize])]
    }
    if str.eq(nm, "mor") {
        if sr.lm_moran(a, y, x, n, m, w, usize(p[0usize]), out) != ok { ret nan }
        ret out[usize(p[1usize])]
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spdepreg.json")
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
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    let _ = str.push(&b, " #")
                    let _ = str.push_f64(&b, f64(at))
                    let _ = str.push(&b, " n/sty ")
                    let _ = str.push_f64(&b, c.args[0usize])
                    let _ = str.push(&b, "/")
                    let _ = str.push_f64(&b, c.args[2usize])
                    let _ = str.push(&b, " tail ")
                    let _ = str.push_f64(&b, c.args[c.args.len - 1usize])
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " R ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
