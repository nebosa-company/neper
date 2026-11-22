// e.algo.stat.kslocal against ks kde.local.test. tests/oracle/kslocal.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kslocal`; the layouts are at the top of scripts/r_oracle/groups/kslocal.R.

use e.algo.stat.kslocal as kl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let d = usize(x[0usize])
    let n1 = usize(x[1usize])
    let n2 = usize(x[2usize])
    let m = usize(x[3usize])
    let which = usize(x[5usize])
    let cell = usize(x[6usize])
    var total = 1usize
    var j = 0usize
    while j < d {
        total = total * m
        j += 1usize
    }
    let dd = d * d
    let h1 = x[7usize..7usize + dd]
    let h2 = x[7usize + dd..7usize + 2usize * dd]
    let s = 7usize + 2usize * dd
    let (df, e1) = mem.alloc[f64](a, total)
    let (vr, e2) = mem.alloc[f64](a, total)
    let (x2, e3) = mem.alloc[f64](a, total)
    let (pv, e4) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(5) }
    var cnt: [3]f64 = zero
    if kl.local_test(a, x[s..s + n1 * d], n1, x[s + n1 * d..s + n1 * d + n2 * d], n2, d, h1, h2, m, x[4usize] != 0.0f64, 0.05f64, df, vr, x2, pv, cnt[0usize..3usize]) != ok { os.exit(6) }
    if which == 0usize { ret cnt[0usize] }
    if which == 1usize { ret cnt[1usize] }
    if which == 2usize { ret df[cell] }
    if which == 3usize { ret vr[cell] }
    if which == 4usize { ret x2[cell] }
    ret pv[cell]
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, "(")
    var at = 0usize
    while at < c.args.len && at < 7usize {
        if at > 0usize { let _ = str.push(&b, ", ") }
        let _ = str.push_f64(&b, c.args[at])
        at += 1usize
    }
    let _ = str.push(&b, "..): got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kslocal.json")
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
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
