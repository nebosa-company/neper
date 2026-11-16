// e.algo.stat.algdesign against AlgDesign: gen.factorial and eval.design. tests/oracle/algdesign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R algdesign`; the layout is at the top of
// scripts/r_oracle/groups/algdesign.R.

use e.algo.stat.algdesign as ad
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.starts_with(c.name, "gen_") {
        let nf = usize(z[0usize])
        let (lv, e1) = mem.alloc[usize](a, nf)
        if e1 != ok { ret nan }
        var runs = 1usize
        var f = 0usize
        while f < nf {
            lv[f] = usize(z[1usize + f])
            runs *= lv[f]
            f += 1usize
        }
        let (out, e2) = mem.alloc[f64](a, runs * nf)
        if e2 != ok { ret nan }
        let r = ad.gen_factorial(lv, z[1usize + nf] != 0.0f64, out)
        var s = 0.0f64
        var i = 0usize
        while i < r * nf {
            if str.eq(c.name, "gen_sum") { s += out[i] } else { s += f64(i + 1usize) * out[i] }
            i += 1usize
        }
        ret s
    }
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let nc = usize(z[2usize])
    let x = z[3usize..3usize + n * k]
    let cand = z[3usize + n * k..3usize + n * k + nc * k]
    let q = usize(z[3usize + n * k + nc * k])
    let (r, e) = ad.eval_design(a, x, n, k, cand, nc)
    if e != ok { ret nan }
    if q == 0usize { ret r.determinant }
    if q == 1usize { ret r.a }
    if q == 2usize { ret r.i }
    if q == 3usize { ret r.geff }
    if q == 4usize { ret r.deff }
    if q == 5usize { ret r.diagonality }
    ret r.gmean_var
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/algdesign.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
