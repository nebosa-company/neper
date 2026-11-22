// e.algo.stat.qgraphpkg.cor_auto against qgraph::cor_auto (lavaan two-step correlations). tests/oracle/qgraphcor.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qgraphcor`; the layout is at the top of scripts/r_oracle/groups/qgraphcor.R.

use e.algo.stat.glasso as gl
use e.algo.stat.qgraphpkg as qg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (out, e1) = gl.zalloc(a, p * p)
    if e1 != ok { ret nan }
    if qg.cor_auto(a, z[4usize + p..4usize + p + n * p], n, p, z[4usize..4usize + p], z[2usize] != 0.0f64, usize(z[3usize]), out) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    while i < p * p {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qgraphcor.json")
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
            if failures <= 40usize {
                let (initial, be) = str.builder(a, 160usize)
                var b = initial
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " #")
                let _ = str.push_f64(&b, f64(at))
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " R ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
