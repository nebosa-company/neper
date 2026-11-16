// e.algo.stat.dfree.auglag against nloptr COBYLA on three constrained problems (HS071 among them).
// tests/oracle/auglag.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R auglag`.

use e.algo.stat.dfree as df
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pw(v: f64) -> f64 { ret v * v }

fn obj(ctx: *u8, x: []const f64) -> f64 {
    let id = usize(*ctx)
    if id == 0usize { ret x[0usize] * x[3usize] * (x[0usize] + x[1usize] + x[2usize]) + x[2usize] }
    if id == 1usize { ret pw(x[0usize] - 2.0f64) + pw(x[1usize] - 1.0f64) }
    ret x[0usize] * x[0usize] + x[1usize] * x[1usize]
}

// equalities first, then inequalities (<= 0)
fn cons(ctx: *u8, x: []const f64, out: []f64) {
    let id = usize(*ctx)
    if id == 0usize {
        out[0usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] + x[2usize] * x[2usize] + x[3usize] * x[3usize] - 40.0f64
        out[1usize] = 25.0f64 - x[0usize] * x[1usize] * x[2usize] * x[3usize]
        ret
    }
    if id == 1usize {
        out[0usize] = x[0usize] - 2.0f64 * x[1usize] + 1.0f64
        out[1usize] = x[0usize] * x[0usize] / 4.0f64 + x[1usize] * x[1usize] - 1.0f64
        ret
    }
    out[0usize] = x[0usize] + x[1usize] - 1.0f64
    out[1usize] = 0.0f64 - 1.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var id = u8(x[0usize])
    let n = usize(x[1usize])
    let (x0, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        x0[i] = x[2usize + i]
        i += 1usize
    }
    let (v, fe) = df.auglag[u8](a, obj, cons, &id, 1usize, 1usize, x0, x[2usize + n..2usize + 2usize * n], x[2usize + 2usize * n..2usize + 3usize * n], 1.0e-9f64)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "val") { ret v }
    ret x0[usize(x[2usize + 3usize * n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/auglag.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
