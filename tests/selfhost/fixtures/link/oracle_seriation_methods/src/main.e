// e.algo.stat.seriationeig against seriation: the eigenvector methods. tests/oracle/seriation_methods.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R seriation_methods`; the layout is at the top of
// scripts/r_oracle/groups/seriation_methods.R. A spectral or MDS order is compared up to reversal (LAPACK's
// eigenvector sign); the share of orders that also have R's orientation is printed.

use e.algo.stat.seriationeig as se
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Tally = struct { exact: usize, total: usize }

fn same_or_reversed(o: []const usize, z: []const f64, at: usize, n: usize, t: *Tally) -> f64 {
    var fwd = true
    var rev = true
    var i = 0usize
    while i < n {
        let want = usize(z[at + i]) - 1usize
        if o[i] != want { fwd = false }
        if o[n - 1usize - i] != want { rev = false }
        i += 1usize
    }
    t.total += 1usize
    if fwd { t.exact += 1usize }
    if fwd || rev { ret 1.0f64 }
    ret 0.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case, t: *Tally) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let code = usize(z[0usize])
    let n = usize(z[1usize])
    let d = z[2usize..2usize + n * n]
    let at = 2usize + n * n
    let (o, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret nan }
    var r = ok
    if code == 1usize { r = se.spectral_order(a, d, n, o) }
    if code == 2usize { r = se.spectral_norm_order(a, d, n, o) }
    if code == 3usize { r = se.mds_order(a, d, n, o) }
    if code == 4usize { r = se.mds_angle_order(a, d, n, o) }
    if r != ok { ret nan }
    ret same_or_reversed(o, z, at, n, t)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/seriation_methods.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var tally = Tally{ exact: 0usize, total: 0usize }
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c, &tally)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    let (initial, be) = str.builder(a, 120usize)
    if be == ok {
        var b = initial
        let _ = str.push_i64(&b, i64(tally.exact))
        let _ = str.push(&b, " of ")
        let _ = str.push_i64(&b, i64(tally.total))
        let _ = str.push(&b, " orders with R's orientation\n")
        let _ = io.print(str.done(&b))
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
