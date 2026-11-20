// Bit-exactness of the primitives under the optimiser-driven MASS fits (exp, log, pow, pnorm, plogis, dt, df, dnbinom, dbeta, lgamma, dchisq,
// dgamma) against R, every case compared exactly. tests/oracle/mass_probe.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_probe`; the layout is at the top of scripts/r_oracle/groups/mass_probe.R.

use e.io
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.special as sp
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let k = usize(z[0usize])
    let x = z[1usize]
    let p = z[2usize]
    let q = z[3usize]
    var r = 0.0f64 / 0.0f64
    if k == 0usize { r = math.exp[f64](0.0f64 - x) }
    if k == 1usize { r = math.log[f64](x) }
    if k == 2usize { r = math.pow[f64](x, p / 7.0f64) }
    if k == 3usize { r = dist.pnorm(x - 3.0f64, 0.0f64, 1.0f64, true, false) }
    if k == 4usize { r = dist.plogis(x - 3.0f64, 0.0f64, 1.0f64, true, false) }
    if k == 5usize { r = nb.dt(x - 3.0f64, p, true) }
    if k == 6usize { r = nb.df(x, p, q, true) }
    if k == 7usize { r = nb.dnbinom(x, p, q, true) }
    if k == 8usize { r = nb.dbeta(x / 6.0f64, p, q, true) }
    if k == 9usize { r = sp.lgamma(x) }
    if k == 10usize { r = dist.log1p(x) }
    if k == 11usize { r = nm.dchisq(x, p, true) }
    if k == 12usize { r = math.sqrt[f64](x) }
    if k == 13usize { r = nm.dgamma(x, p, 0.7f64, true) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_probe.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var far = 0usize
    var bad: [14]usize = zero
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            bad[usize(c.args[0usize])] += 1usize
            var d = got - c.want
            if d < 0.0f64 { d = 0.0f64 - d }
            var w = c.want
            if w < 0.0f64 { w = 0.0f64 - w }
            if !(d <= 1.0e-11f64 * w + 1.0e-13f64) { far += 1usize }
        }
        at += 1usize
    }
    var k = 0usize
    while k < 14usize {
        let (sb, se) = str.builder(a, 64usize)
        if se == ok {
            var b = sb
            let _ = str.push(&b, "kind ")
            let _ = str.push_f64(&b, f64(k))
            let _ = str.push(&b, " mismatches ")
            let _ = str.push_f64(&b, f64(bad[k]))
            let _ = str.push(&b, "\n")
            let _ = io.print(str.done(&b))
        }
        k += 1usize
    }
    // The mismatch counts are the measurement (see the ceiling note in mass_probe.R); only the correctly rounded sqrt must be exact.
    if bad[12usize] > 0usize { os.exit(1) }
    // every primitive stays within 1e-11 relative (1e-13 absolute) of R, so a wrong constant or guard cannot pass
    if far > 0usize { os.exit(4) }
    ret ok
}
