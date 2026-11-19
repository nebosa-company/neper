// e.algo.stat.energy.kgroups against energy::kgroups from a given start. tests/oracle/energy_kgroups.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R energy_kgroups`; the layout is at the top of scripts/r_oracle/groups/energy_kgroups.R.

use e.algo.rand.r as rr
use e.algo.stat.energy as en
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let d = usize(z[1usize])
    let k = usize(z[2usize])
    let (cl, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(4) }
    var i = 0usize
    let seeded = c.name[0usize] == 115u8
    var xs: []const f64 = z[0usize..0usize]
    if seeded {
        var g: rr.Rng = zero
        rr.seed(&g, i64(z[4usize]))
        let (draw, de) = rr.sample_int(a, &g, i64(k), i64(n), true)
        if de != ok { os.exit(6) }
        while i < n {
            cl[i] = usize(draw[i] - 1i64)
            i += 1usize
        }
        xs = z[5usize..5usize + n * d]
    } else {
        while i < n {
            cl[i] = usize(z[4usize + i])
            i += 1usize
        }
        xs = z[4usize + n..4usize + n + n * d]
    }
    let (it, ct, w, ke) = en.kgroups(a, xs, n, d, k, usize(z[3usize]), cl)
    if ke != ok { os.exit(5) }
    if str.eq(c.name, "it") || str.eq(c.name, "sit") { ret f64(it) }
    if str.eq(c.name, "ct") { ret f64(ct) }
    if str.eq(c.name, "w") || str.eq(c.name, "sw") { ret w }
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += f64(cl[i] + 1usize) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/energy_kgroups.json")
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
