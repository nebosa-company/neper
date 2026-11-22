// The shared runtime's exp, log and pow against R's platform libm, bit for bit.
// tests/oracle/math_libm.json comes from `Rscript scripts/r_oracle/generate.R math_libm`; the layout is at the
// top of scripts/r_oracle/groups/math_libm.R. Any disagreement is a last-bit difference between this
// repository's fdlibm-derived implementations and the C runtime R links against, so the case count printed
// here is the measurement the libm work starts from.

use e.io
use e.math
use e.mem
use e.os
use e.str as s
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    if s.eq(c.name, "exp") { ret math.exp[f64](z[0usize]) }
    if s.eq(c.name, "log") { ret math.log[f64](z[0usize]) }
    ret math.pow[f64](z[0usize], z[1usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/math_libm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var fe = 0usize
    var fl = 0usize
    var fp = 0usize
    var shown = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if s.eq(c.name, "exp") { fe += 1usize }
            if s.eq(c.name, "log") { fl += 1usize }
            if s.eq(c.name, "pow") { fp += 1usize }
            if shown < 8usize {
                shown += 1usize
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
    let _ = s.push_usize(&b, failures)
    let _ = s.push(&b, " of ")
    let _ = s.push_usize(&b, golden.cases.len)
    let _ = s.push(&b, " cases disagree with R (exp ")
    let _ = s.push_usize(&b, fe)
    let _ = s.push(&b, ", log ")
    let _ = s.push_usize(&b, fl)
    let _ = s.push(&b, ", pow ")
    let _ = s.push_usize(&b, fp)
    let _ = s.push(&b, ")\n")
    let _ = io.print(s.done(&b))
    if failures > 0usize { os.exit(1) }
    ret ok
}
