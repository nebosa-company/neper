// e.algo.stat.gstatfit against gstat's fit.variogram. tests/oracle/gstatfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gstatfit`; the layout is at the top of scripts/r_oracle/groups/gstatfit.R.

use e.algo.stat.gstatfit as gf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let method = usize(x[0usize])
    let nst = usize(x[1usize])
    let nev = usize(x[2usize])
    let kgrid = x[3usize] > 0.5f64
    let ms = x[4usize..4usize + 6usize * nst]
    var at = 4usize + 6usize * nst
    let fs = x[at..at + nst]
    at += nst
    let fr = x[at..at + nst]
    at += nst
    let np = x[at..at + nev]
    at += nev
    let dist = x[at..at + nev]
    at += nev
    let gam = x[at..at + nev]
    at += nev
    let part = usize(x[at])
    let (out, e1) = mem.alloc[f64](a, 2usize * nst + 3usize)
    if e1 != ok { os.exit(5) }
    if kgrid {
        if gf.fit_variogram_kappa(a, ms, nst, np, dist, gam, nev, method, fs, fr, out) != ok { os.exit(6) }
    }
    if !kgrid {
        if gf.fit_variogram(a, ms, nst, np, dist, gam, nev, method, fs, fr, true, out) != ok { os.exit(7) }
    }
    ret out[part]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gstatfit.json")
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
                let (sb, sbe) = str.builder(a, 256usize)
                var b = sb
                let _ = str.push_usize(&b, at)
                let _ = str.push(&b, " m")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " nst")
                let _ = str.push_f64(&b, c.args[1usize])
                let _ = str.push(&b, " k")
                let _ = str.push_f64(&b, c.args[3usize])
                let _ = str.push(&b, " t")
                let _ = str.push_f64(&b, c.args[4usize])
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " want ")
                let _ = str.push_f64(&b, c.want)
                let _ = str.push(&b, "\n")
                let _ = io.print(str.done(&b))
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
