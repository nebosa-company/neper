// e.algo.stat.fitdistx.fitdistr_user against MASS fitdistr with a user densfun function (start, bounds, forced methods).
// tests/oracle/mass_fdu.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_fdu`; the layout is at the top of scripts/r_oracle/groups/mass_fdu.R.

use e.algo.stat.fitdistx as fx
use e.io
use e.math
use e.math.nmath_beta as nb
use e.mem
use e.os
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn dgum(x: f64, p: []const f64) -> f64 {
    let z = (x - p[0usize]) / p[1usize]
    ret math.exp[f64](0.0f64 - (z + math.exp[f64](0.0f64 - z))) / p[1usize]
}

// the log density: the function has a log argument, so MASS sums dens(log = TRUE)
fn dig_log(x: f64, p: []const f64) -> f64 {
    let mu = p[0usize]
    let l = p[1usize]
    ret 0.5f64 * math.log[f64](l / (2.0f64 * 3.141592653589793f64 * x * x * x)) - l * (x - mu) * (x - mu) / (2.0f64 * mu * mu * x)
}

fn dray(x: f64, p: []const f64) -> f64 {
    let s = p[0usize]
    ret x / (s * s) * math.exp[f64](0.0f64 - x * x / (2.0f64 * s * s))
}

fn dtls_log(x: f64, p: []const f64) -> f64 { ret nb.dt((x - p[0usize]) / p[1usize], p[2usize], true) - math.log[f64](p[1usize]) }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let id = usize(z[0usize])
    let bounded = z[1usize] != 0.0f64
    let method = usize(z[2usize])
    let np = usize(z[3usize])
    let start = z[4usize..7usize]
    let lo3 = z[7usize..10usize]
    let up3 = z[10usize..13usize]
    let which = usize(z[13usize])
    let x = z[14usize..z.len]
    if which == 100usize { ret f64(x.len) }
    let (out, e0) = mem.alloc[f64](a, 16usize)
    if e0 != ok { ret nan() }
    var e = ok
    if id == 0usize { e = fx.fitdistr_user(a, x, dgum, false, np, start, bounded, lo3, up3, method, out) }
    if id == 1usize { e = fx.fitdistr_user(a, x, dig_log, true, np, start, bounded, lo3, up3, method, out) }
    if id == 2usize { e = fx.fitdistr_user(a, x, dray, false, np, start, bounded, lo3, up3, method, out) }
    if id == 3usize { e = fx.fitdistr_user(a, x, dtls_log, true, np, start, bounded, lo3, up3, method, out) }
    if e != ok { ret nan() }
    if which == 50usize {
        var t = 0.0f64
        var j = 0usize
        while j < np * np {
            t += f64(j + 1usize) * out[2usize * np + 1usize + j]
            j += 1usize
        }
        ret t
    }
    if which == 51usize { ret out[2usize * np + 2usize] }
    ret out[which]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_fdu.json")
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
