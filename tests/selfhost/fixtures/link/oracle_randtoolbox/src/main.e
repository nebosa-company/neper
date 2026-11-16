// e.algo.rand.quasi and e.algo.stat.randtoolbox against randtoolbox. tests/oracle/randtoolbox.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R randtoolbox`; the layout is at the top of scripts/r_oracle/groups/randtoolbox.R.

use e.algo.rand.quasi as q
use e.algo.stat.randtoolbox as rt
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    if c.name.len == 4usize {
        var st = u64(c.args[0usize])
        let cn = usize(c.args[4usize]) * usize(c.args[5usize])
        var cs = 0.0f64
        var ci = 0usize
        while ci < cn {
            cs += q.congru_next(&st, u64(c.args[1usize]), u64(c.args[2usize]), u64(c.args[3usize])) * f64(ci + 1usize)
            ci += 1usize
        }
        ret cs
    }
    let kind = usize(c.args[0usize])
    let n = usize(c.args[1usize])
    let d = usize(c.args[2usize])
    var pt: [8]f64 = zero
    var s = 0.0f64
    var r = 1usize
    while r <= n {
        if kind == 0usize {
            let e = q.halton_point(u64(r), pt[0usize..d])
            if e != ok { os.exit(5) }
        }
        var j = 0usize
        while j < d {
            var v = pt[j]
            if kind == 1usize { v = rt.sobol(u64(r), j) }
            if kind == 2usize { v = rt.torus(u64(r), j) }
            s += v * f64((r - 1usize) * d + j + 1usize)
            j += 1usize
        }
        r += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/randtoolbox.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
