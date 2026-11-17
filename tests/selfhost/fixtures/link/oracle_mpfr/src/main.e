// e.algo.mpfr against Rmpfr (MPFR). tests/oracle/mpfr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mpfr`; the layout is at the top of scripts/r_oracle/groups/mpfr.R.

use e.algo.mpfr as mp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let op = usize(z[0usize])
    let prec = usize(z[1usize])
    let (x, e1) = mp.from_parts(a, i64(z[2usize]), i64(z[3usize]), prec)
    let (y, e2) = mp.from_parts(a, i64(z[4usize]), i64(z[5usize]), prec)
    if e1 != ok || e2 != ok { ret nan }
    var r: mp.Mp = zero
    var er = ok
    if op == 0usize {
        let (t, e) = mp.add(a, x, y, prec)
        r = t
        er = e
    } else if op == 1usize {
        let (t, e) = mp.sub(a, x, y, prec)
        r = t
        er = e
    } else if op == 2usize {
        let (t, e) = mp.mul(a, x, y, prec)
        r = t
        er = e
    } else if op == 3usize {
        let (t, e) = mp.div(a, x, y, prec)
        r = t
        er = e
    } else if op == 4usize {
        let (t, e) = mp.sqrt(a, x, prec)
        r = t
        er = e
    } else if op == 5usize {
        let (t, e) = mp.exp(a, x, prec)
        r = t
        er = e
    } else if op == 6usize {
        let (t, e) = mp.log(a, x, prec)
        r = t
        er = e
    } else if op == 7usize || op == 8usize {
        let (sn, cs, e) = mp.sin_cos(a, x, prec)
        r = sn
        if op == 8usize { r = cs }
        er = e
    } else if op == 9usize {
        let (t, e) = mp.pow(a, x, y, prec)
        r = t
        er = e
    } else if op == 10usize {
        let (t, e) = mp.pi(a, prec)
        r = t
        er = e
    } else if op == 11usize {
        let (t, e) = mp.tan(a, x, prec)
        r = t
        er = e
    } else if op >= 12usize && op <= 14usize {
        let (t, e) = mp.hyper(a, op - 12usize, x, prec)
        r = t
        er = e
    } else if op == 15usize {
        let (t, e) = mp.atan(a, x, prec)
        r = t
        er = e
    } else {
        let (t, e) = mp.inverse(a, op - 16usize, x, prec)
        r = t
        er = e
    }
    if er != ok { ret nan }
    let (hi, lo) = mp.to_pair(a, r)
    if z[6usize] == 0.0f64 { ret hi }
    ret lo
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mpfr.json")
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
