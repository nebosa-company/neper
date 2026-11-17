// e.algo.stat.clustermona against cluster::mona. tests/oracle/clustermona.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clustermona`; the argument layout is at the top of
// scripts/r_oracle/groups/clustermona.R.

use e.algo.stat.clustermona as cm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the sum of v[from + i] * (i + 1) for i in 0..cnt
fn wsum_u(v: []const usize, from: usize, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += f64(v[from + i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (m, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * p {
        m[i] = x[2usize + i]
        if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    let (codes, e2) = mem.alloc[usize](a, n * p)
    if e2 != ok { os.exit(6) }
    if cm.mona_recode(m, n, p, codes) != 0usize { os.exit(7) }
    let (r, e3) = cm.mona_core(a, codes, n, p)
    if e3 != ok { os.exit(8) }
    let nm = c.name
    if str.eq(nm, "jerr") { ret f64(r.jerr) }
    if r.jerr != 0usize { os.exit(9) }
    if str.eq(nm, "order") { ret wsum_u(r.ner, 1usize, n) }
    if str.eq(nm, "step") { ret wsum_u(r.nban, 2usize, n - 1usize) }
    if str.eq(nm, "variable") { ret wsum_u(r.lava, 2usize, n - 1usize) }
    if str.eq(nm, "data") { ret wsum_u(r.x, 0usize, n * p) }
    os.exit(10)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clustermona.json")
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
