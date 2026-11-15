// `e.math.special` against R. The goldens in tests/oracle/special.json come from
// `Rscript scripts/r_oracle/generate.R special`; this fixture is also the proof that the
// oracle harness can fail, so a case that does not agree is printed and fails the run.

use e.io
use e.math.special as special
use e.mem
use e.os
use e.test.oracle as oracle

fn is(name: str, want: str) -> bool {
    if name.len != want.len { ret false }
    var at = 0usize
    while at < name.len {
        if name[at] != want[at] { ret false }
        at += 1usize
    }
    ret true
}

fn evaluate(c: *const oracle.Case) -> (f64, bool) {
    let x = c.args
    if is(c.name, "pnorm") { ret (special.normal_cdf(x[0]), true) }
    if is(c.name, "qnorm") { ret (special.normal_quantile(x[0]), true) }
    if is(c.name, "lgamma") { ret (special.lgamma(x[0]), true) }
    if is(c.name, "gamma") { ret (special.gamma(x[0]), true) }
    if is(c.name, "pt") { ret (special.t_cdf(x[0], x[1]), true) }
    if is(c.name, "pchisq") { ret (special.chi_squared_cdf(x[0], x[1]), true) }
    if is(c.name, "pf") { ret (special.f_cdf(x[0], x[1], x[2]), true) }
    if is(c.name, "choose") { ret (special.choose(x[0], x[1]), true) }
    ret (0.0f64, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/special.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let (got, known) = evaluate(c)
        if !known { os.exit(4) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 40usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
