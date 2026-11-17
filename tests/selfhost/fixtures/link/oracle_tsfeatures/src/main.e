// e.algo.stat.tsfeatures against tsfeatures. tests/oracle/tsfeatures.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsfeatures`; the layout is at the top of scripts/r_oracle/groups/tsfeatures.R.

use e.algo.stat.tsfeatures as tf
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let m = usize(x[1usize])
    let w = usize(x[2usize])
    let s = x[3usize..3usize + n]
    let j = usize(x[3usize + n])
    let nm = c.name
    let (out, oe) = mem.alloc[f64](a, 16usize)
    if oe != ok { os.exit(5) }
    if str.eq(nm, "hmode") { ret tf.histogram_mode(a, s, usize(x[2usize])) }
    if str.eq(nm, "acf") {
        let e = tf.acf_features(a, s, m, out)
        if e != ok { os.exit(6) }
        ret out[j]
    }
    if str.eq(nm, "pacf") {
        let e = tf.pacf_features(a, s, m, out)
        if e != ok { os.exit(6) }
        ret out[j]
    }
    if str.eq(nm, "mlshift") || str.eq(nm, "mvshift") {
        var k = 0u8
        if str.eq(nm, "mvshift") { k = 1u8 }
        let (v, i) = tf.max_shift(a, s, w, k)
        if j == 0usize { ret v }
        ret i
    }
    if str.eq(nm, "cross") { ret tf.crossing_points(a, s) }
    if str.eq(nm, "flat") { ret tf.flat_spots(s) }
    if str.eq(nm, "lump") { ret tf.window_stat(a, s, w, 0u8) }
    if str.eq(nm, "stab") { ret tf.window_stat(a, s, w, 1u8) }
    if str.eq(nm, "std1st") { ret tf.std1st_der(a, s) }
    if str.eq(nm, "trev") { ret tf.trev_num(s) }
    if str.eq(nm, "walker") { ret tf.walker_propcross(s) }
    if str.eq(nm, "motif") { ret tf.motiftwo_entro3(s) }
    if str.eq(nm, "stl") {
        let e = tf.stl_features(a, s, m, out)
        if e != ok { os.exit(6) }
        ret out[j]
    }
    if str.eq(nm, "holt") {
        let (ha, hb) = tf.holt_parameters(a, s)
        if j == 0usize { ret ha }
        ret hb
    }
    if str.eq(nm, "hetero") {
        let e = tf.heterogeneity(a, s, out)
        if e != ok { os.exit(6) }
        ret out[j]
    }
    if str.eq(nm, "entropy") { ret tf.entropy(a, s) }
    if str.eq(nm, "pp") { ret tf.unitroot_pp(a, s) }
    if str.eq(nm, "hurst") { ret tf.hurst(a, s) }
    if str.eq(nm, "arch") { ret tf.arch_stat(a, s, 12usize, true) }
    if str.eq(nm, "kpss") { ret tf.unitroot_kpss(s) }
    if str.eq(nm, "zeroprop") {
        let (rd, re) = mem.alloc[f64](a, n)
        if re != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            rd[i] = math.round[f64](s[i])
            i += 1usize
        }
        ret tf.zero_proportion(rd, 1.0e-8f64)
    }
    let (r, e) = tf.acf(a, s, n - 1usize)
    if e != ok { os.exit(6) }
    if str.eq(nm, "firstmin") { ret tf.firstmin_ac(r) }
    if str.eq(nm, "firstzero") { ret tf.firstzero_ac(r) }
    if str.eq(nm, "ac9") { ret r[9usize] }
    if str.eq(nm, "embed1") { ret tf.embed2_incircle(s, r, 1.0f64) }
    ret tf.embed2_incircle(s, r, 2.0f64)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsfeatures.json")
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
