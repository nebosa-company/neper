// e.algo.stat.squarem against SQUAREM: squarem (methods 1 to 3) and fpiter on four fixed-point maps.
// tests/oracle/squarem.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R squarem`;
// the layout and the maps are at the top of scripts/r_oracle/groups/squarem.R.

use e.algo.stat.squarem as sq
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn th(x: f64) -> f64 {
    let e = math.exp[f64](2.0f64 * x)
    ret (e - 1.0f64) / (e + 1.0f64)
}

fn map_fn(id: *u8, p: []const f64, out: []f64) {
    let m = *id
    if m == 0u8 { out[0usize] = math.cos[f64](p[0usize]) }
    if m == 1u8 {
        out[0usize] = 0.5f64 * math.cos[f64](p[1usize]) + 0.2f64
        out[1usize] = 0.3f64 * math.sin[f64](p[0usize]) + 0.1f64 * p[1usize]
    }
    if m == 2u8 {
        out[0usize] = 0.5f64 * (p[0usize] + 2.0f64 / p[0usize])
        out[1usize] = 0.5f64 * (p[1usize] + 5.0f64 / p[1usize])
        out[2usize] = 0.5f64 * (p[2usize] + 11.0f64 / p[2usize])
    }
    if m == 3u8 {
        out[0usize] = 0.5f64 * th(p[1usize]) + 0.3f64
        out[1usize] = 0.4f64 * th(p[0usize] + p[2usize])
        out[2usize] = 0.6f64 * math.cos[f64](p[0usize] - p[1usize])
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var id = u8(x[0usize])
    let n = usize(x[4usize])
    let par0 = x[5usize..5usize + n]
    let kind = u8(x[5usize + n])
    var r: sq.Result = zero
    var e = ok
    if kind == 0u8 {
        let (rr, re) = sq.squarem2[u8](a, &id, map_fn, par0, u8(x[1usize]), x[2usize], i64(x[3usize]))
        r = rr
        e = re
    } else {
        let (rr, re) = sq.fpiter[u8](a, &id, map_fn, par0, x[2usize], i64(x[3usize]))
        r = rr
        e = re
    }
    if e != ok { os.exit(6) }
    if str.eq(c.name, "par") { ret r.par[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "iter") { ret f64(r.iter) }
    if str.eq(c.name, "fpevals") { ret f64(r.fpevals) }
    if r.converged { ret 1.0f64 }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/squarem.json")
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
