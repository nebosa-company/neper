// e.algo.stat.gslcoulomb against gsl. tests/oracle/gslcoulomb.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslcoulomb`; the layout of each case is at the top of scripts/r_oracle/groups/gslcoulomb.R.

use e.algo.stat.gslcoulomb as gc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn grab(a: *mem.Arena, n: usize) -> []f64 {
    let (p, g) = mem.alloc[f64](a, n)
    if g != ok { os.exit(4) }
    ret p
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "fg") {
        let o = grab(a, 10usize)
        let ser = grab(a, 4usize)
        let st = gc.coulomb_wave_fg(x[1usize], x[2usize], x[3usize], i64(x[4usize]), o, ser)
        let code = usize(x[0usize])
        if code == 9usize { ret f64(st) }
        if code == 7usize { ret o[8usize] }
        if code == 8usize { ret o[9usize] }
        if code == 6usize { ret o[7usize] }
        ret o[code]
    }
    if str.eq(k, "cl") {
        let (v, e, st) = gc.coulomb_cl(x[1usize], x[2usize])
        let code = usize(x[0usize])
        if code == 0usize { ret v }
        if code == 1usize { ret e }
        ret f64(st)
    }
    let kind = usize(x[0usize])
    let kmax = usize(x[3usize])
    let fc = grab(a, kmax + 1usize)
    let fcp = grab(a, kmax + 1usize)
    let gcc = grab(a, kmax + 1usize)
    let gcp = grab(a, kmax + 1usize)
    let o = grab(a, 10usize)
    let ser = grab(a, 4usize)
    var ex = 0.0f64
    if kind == 8usize {
        gc.coulomb_cl_array(x[2usize], kmax, x[4usize], fc)
        ret fc[usize(x[1usize])]
    }
    if kind == 0usize {
        let (e1, _s1) = gc.coulomb_wave_f_array(x[2usize], kmax, x[4usize], x[5usize], fc, o, ser)
        ex = e1
    }
    if kind == 1usize || kind == 2usize {
        let (e1, _e2, _s1) = gc.coulomb_wave_fg_array(x[2usize], kmax, x[4usize], x[5usize], fc, fcp, gcc, gcp, false, o, ser)
        ex = e1
    }
    if kind >= 3usize && kind <= 6usize {
        let (e1, _e2, _s1) = gc.coulomb_wave_fg_array(x[2usize], kmax, x[4usize], x[5usize], fc, fcp, gcc, gcp, true, o, ser)
        ex = e1
    }
    if kind == 7usize {
        let (e1, _s1) = gc.coulomb_wave_sphf_array(x[2usize], kmax, x[4usize], x[5usize], fc, o, ser)
        ex = e1
    }
    if x[1usize] < 0.0f64 { ret ex }
    let j = usize(x[1usize])
    if kind == 0usize || kind == 1usize || kind == 3usize || kind == 7usize { ret fc[j] }
    if kind == 2usize || kind == 5usize { ret gcc[j] }
    if kind == 4usize { ret fcp[j] }
    ret gcp[j]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslcoulomb.json")
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
