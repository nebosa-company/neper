// e.algo.stat.fpc's dbscan with method raw and dist, scale and predict.dbscan against fpc. tests/oracle/fpc_dbscan2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_dbscan2`; the layouts are at the top of scripts/r_oracle/groups/fpc_dbscan2.R.

use e.algo.stat.fpc as fp
use e.algo.stat.fpc_misc as fm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let eps = z[2usize]
    let mp = usize(z[3usize])
    let (cv, e1) = mem.alloc[i64](a, n)
    let (sd, e2) = mem.alloc[bool](a, n)
    let (xs, e3) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    if c.name[1usize] == 109u8 {
        let sc = z[5usize] > 0.5f64
        let what = usize(z[6usize])
        let x = z[7usize..7usize + n * p]
        if sc {
            if fm.scale_cols(a, x, n, p, xs) != ok { os.exit(6) }
        } else {
            var i = 0usize
            while i < n * p {
                xs[i] = x[i]
                i += 1usize
            }
        }
        if fp.dbscan(a, xs, n, p, eps, mp, cv, sd) != ok { os.exit(7) }
        var s = 0.0f64
        var mx = 0i64
        var i = 0usize
        while i < n {
            if what == 0usize { s += f64(i + 1usize) * f64(cv[i]) }
            if what == 1usize && sd[i] { s += f64(i + 1usize) }
            if cv[i] > mx { mx = cv[i] }
            i += 1usize
        }
        if what == 2usize { ret f64(mx) }
        ret s
    }
    let m = usize(z[4usize])
    let x = z[5usize..5usize + n * p]
    if fp.dbscan(a, x, n, p, eps, mp, cv, sd) != ok { os.exit(7) }
    let (out, e4) = mem.alloc[i64](a, m)
    if e4 != ok { os.exit(5) }
    fm.dbscan_predict(a, x, n, p, cv, sd, eps, z[5usize + n * p..], m, out)
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += f64(i + 1usize) * f64(out[i])
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_dbscan2.json")
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
            if failures <= 10usize {
                var c2 = *c
                c2.args = c.args[0usize..6usize]
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
