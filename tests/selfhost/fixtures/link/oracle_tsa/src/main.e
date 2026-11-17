// e.algo.stat.tsa against TSA. tests/oracle/tsa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsa`; the layout is at the top of scripts/r_oracle/groups/tsa.R.

use e.algo.stat.tsa as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn mcl_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let gl = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, gl)
    if e != ok { os.exit(5) }
    if ts.mcleod_li(a, x[2usize..2usize + n], gl, o) != ok { os.exit(6) }
    var s = 0.0f64
    var i = 0usize
    while i < gl {
        s += o[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "mcl") { ret mcl_case(a, c) }
    if str.eq(c.name, "eacf") {
        let ex = c.args
        let en = usize(ex[0usize])
        let ar = usize(ex[1usize])
        let ma = usize(ex[2usize])
        let (eo, ee) = mem.alloc[f64](a, (ar + 1usize) * (ma + 1usize))
        if ee != ok { ret 0.0f64 / 0.0f64 }
        if ts.eacf(a, ex[4usize..4usize + en], ar, ma, eo) != ok { ret 0.0f64 / 0.0f64 }
        ret eo[usize(ex[3usize])]
    }
    let x = c.args
    let n = usize(x[0usize])
    let (o, e) = mem.alloc[f64](a, ts.nextn(n) / 2usize + 1usize)
    if e != ok { os.exit(5) }
    let cnt = ts.periodogram(x[1usize..1usize + n], o)
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += o[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsa.json")
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
