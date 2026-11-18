// e.math.quadpack (qags, qagi) against R's integrate(). tests/oracle/quadpack.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quadpack`; the layout is at the top of scripts/r_oracle/groups/quadpack.R.

use e.io
use e.math
use e.math.quadpack as qp
use e.mem
use e.os
use e.test.oracle as oracle

type Unit = struct { kind: usize }

fn fn_of(u: *Unit, x: f64) -> f64 {
    let k = u.kind
    if k == 0usize { ret math.exp[f64](0.0f64 - x * x / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) }
    if k == 1usize { ret x * math.log[f64](x) }
    if k == 2usize { ret math.sin[f64](x) / (1.0f64 + x * x) }
    if k == 3usize { ret 1.0f64 / math.sqrt[f64](x) }
    if k == 4usize { ret math.abs[f64](x - 0.3f64) }
    if k == 5usize { ret math.cos[f64](50.0f64 * x) }
    if k == 6usize { ret math.exp[f64](0.0f64 - x) }
    if k == 7usize { ret 1.0f64 / (1.0f64 + x * x) }
    ret math.exp[f64](x)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var u: Unit = zero
    u.kind = usize(z[0usize])
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    var r: qp.Qagi = zero
    var e = ok
    if u.kind <= 5usize {
        let (q, qe) = qp.qags[Unit](a, &u, fn_of, z[1usize], z[2usize], tol, tol, 100usize)
        r = q
        e = qe
    } else if u.kind == 6usize {
        let (q, qe) = qp.qagi[Unit](a, &u, fn_of, 0.0f64, 1i64, tol, tol, 100usize)
        r = q
        e = qe
    } else if u.kind == 7usize {
        let (q, qe) = qp.qagi[Unit](a, &u, fn_of, 0.0f64, 2i64, tol, tol, 100usize)
        r = q
        e = qe
    } else {
        let (q, qe) = qp.qagi[Unit](a, &u, fn_of, 1.0f64, 0i64 - 1i64, tol, tol, 100usize)
        r = q
        e = qe
    }
    if e != ok { os.exit(5) }
    let what = usize(z[3usize])
    if what == 0usize { ret r.result }
    if what == 1usize { ret r.abserr }
    ret f64(r.last)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quadpack.json")
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
