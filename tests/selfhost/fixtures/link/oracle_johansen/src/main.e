// e.algo.stat.johansen against urca::ca.jo. tests/oracle/johansen.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R johansen`; the layout is at the top of scripts/r_oracle/groups/johansen.R.

use e.algo.stat.johansen as jo
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let qtype = u8(z[0usize])
    let ec = u8(z[1usize])
    let k = usize(z[2usize])
    let sp = u8(z[3usize])
    let se = usize(z[4usize])
    let n = usize(z[5usize])
    let p = usize(z[6usize])
    let x = z[7usize..7usize + n * p]
    let what = usize(z[7usize + n * p])
    let i = usize(z[8usize + n * p])
    let (r, e) = jo.ca_jo(a, x, n, p, qtype, ec, k, sp, se)
    if e != ok { ret nan }
    var v: []const f64 = r.lambda
    var len = r.lambda.len
    if what == 1usize {
        v = r.teststat
        len = p
    }
    if what == 3usize {
        v = r.v
        len = r.kdim * r.kdim
    }
    if what == 4usize {
        v = r.w
        len = p * r.kdim
    }
    if what == 5usize {
        v = r.pi
        len = p * r.kdim
    }
    if what == 6usize {
        v = r.gamma
        len = r.gamma.len
    }
    var s = 0.0f64
    var t = 0usize
    if what == 2usize {
        // the critical values of rows 1 .. p, three levels each
        var row = 0usize
        while row < p {
            var lv = 0usize
            while lv < 3usize {
                let cv = jo.jo_cval(a, qtype, ec, row, lv)
                if i == 0usize { s += cv } else { s += f64(row * 3usize + lv + 1usize) * cv }
                lv += 1usize
            }
            row += 1usize
        }
        ret s
    }
    while t < len {
        if i == 0usize { s += v[t] } else { s += f64(t + 1usize) * v[t] }
        t += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/johansen.json")
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
