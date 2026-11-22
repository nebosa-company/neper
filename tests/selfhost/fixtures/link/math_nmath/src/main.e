// R's nmath functions against this runtime, bit for bit: lgamma, gamma, erf, erfc, pnorm, qnorm.
// tests/oracle/math_nmath.json comes from `Rscript scripts/r_oracle/generate.R math_nmath`; the layout is at
// the top of scripts/r_oracle/groups/math_nmath.R. These are R's portable C implementations, so they can and
// should match exactly on every host - any disagreement is this port's error, not the platform's.

use e.io
use e.math.dist as di
use e.math.nmath as nm
use e.math.special as sp
use e.mem
use e.os
use e.str as s
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    if s.eq(c.name, "lgamma") { ret nm.lgammafn(z[0usize]) }
    if s.eq(c.name, "gamma") { ret nm.gammafn(z[0usize]) }
    if s.eq(c.name, "erf") { ret sp.erf(z[0usize]) }
    if s.eq(c.name, "erfc") { ret sp.erfc(z[0usize]) }
    if s.eq(c.name, "pnorm") { ret di.pnorm(z[0usize], 0.0f64, 1.0f64, true, false) }
    ret di.qnorm(z[0usize], 0.0f64, 1.0f64, true, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/math_nmath.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var at = 0usize
    var shown = 0usize
    var flg = 0usize
    var fga = 0usize
    var fe = 0usize
    var fec = 0usize
    var fpn = 0usize
    var fqn = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            shown += 1usize
            if s.eq(c.name, "lgamma") { flg += 1usize }
            if s.eq(c.name, "gamma") { fga += 1usize }
            if s.eq(c.name, "erf") { fe += 1usize }
            if s.eq(c.name, "erfc") { fec += 1usize }
            if s.eq(c.name, "pnorm") { fpn += 1usize }
            if s.eq(c.name, "qnorm") { fqn += 1usize }
            if shown <= 10usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    let (bb, be) = s.builder(a, 128usize)
    if be != ok { ret be }
    var b = bb
    let _ = s.push_usize(&b, shown)
    let _ = s.push(&b, " of ")
    let _ = s.push_usize(&b, golden.cases.len)
    let _ = s.push(&b, " cases disagree with R (lgamma ")
    let _ = s.push_usize(&b, flg)
    let _ = s.push(&b, ", gamma ")
    let _ = s.push_usize(&b, fga)
    let _ = s.push(&b, ", erf ")
    let _ = s.push_usize(&b, fe)
    let _ = s.push(&b, ", erfc ")
    let _ = s.push_usize(&b, fec)
    let _ = s.push(&b, ", pnorm ")
    let _ = s.push_usize(&b, fpn)
    let _ = s.push(&b, ", qnorm ")
    let _ = s.push_usize(&b, fqn)
    let _ = s.push(&b, ")\n")
    let _ = io.print(s.done(&b))
    if shown > 0usize { os.exit(1) }
    ret ok
}
