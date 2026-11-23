// e.algo.stat.rugarchpkg's sGARCH(1,1) fit against rugarch::ugarchfit. tests/oracle/rugarch.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rugarch`; the layout is at the top of scripts/r_oracle/groups/rugarch.R.

use e.algo.stat.rugarchpkg as rg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

// every case of one fit repeats its series and asks for another number, so the fit is kept and reused while the name and all arguments but the last (the index into its output) are unchanged
fn fit_case(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> bool {
    let z = c.args
    let n = usize(z[0usize])
    if c.name.len == 9usize { ret rg.sgarch_arma(a, z[3usize..3usize + n], n, usize(z[1usize]), usize(z[2usize]), out) }
    if c.name.len == 11usize { ret rg.sgarch_ar(a, z[2usize..2usize + n], n, usize(z[1usize]), out) }
    if c.name.len == 10usize { ret rg.sgarch_pq(a, z[3usize..3usize + n], n, usize(z[1usize]), usize(z[2usize]), out) }
    if c.name.len == 7usize { ret rg.igarch11(a, z[1usize..1usize + n], n, out) }
    if c.name.len == 6usize {
        if !rg.egarch11(a, z[1usize..1usize + n], n, out[0usize..6usize]) { ret false }
        ret rg.garch5_se(a, z[1usize..1usize + n], n, 2usize, out[0usize..5usize], out[6usize..11usize])
    }
    if c.name.len == 4usize {
        if !rg.garch11_t(a, z[1usize..1usize + n], n, out[0usize..6usize]) { ret false }
        ret rg.garch5_se(a, z[1usize..1usize + n], n, 3usize, out[0usize..5usize], out[6usize..11usize])
    }
    if c.name.len == 3usize {
        if !rg.gjrgarch11(a, z[1usize..1usize + n], n, out[0usize..6usize]) { ret false }
        ret rg.garch5_se(a, z[1usize..1usize + n], n, 1usize, out[0usize..5usize], out[6usize..11usize])
    }
    if !rg.garch11(a, z[1usize..1usize + n], n, out[0usize..5usize]) { ret false }
    ret rg.garch11_se(a, z[1usize..1usize + n], n, out[0usize..4usize], out[5usize..9usize])
}

fn same_key(c: *const oracle.Case, key: []const f64, key_len: usize, key_name: usize) -> bool {
    if key_len != c.args.len || key_name != c.name.len { ret false }
    var i = 0usize
    while i + 1usize < key_len {
        if key[i] != c.args[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rugarch.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var longest = 0usize
    var q = 0usize
    while q < golden.cases.len {
        if golden.cases[q].args.len > longest { longest = golden.cases[q].args.len }
        q += 1usize
    }
    let (key, e1) = mem.alloc[f64](a, longest)
    let (cached, e2) = mem.alloc[f64](a, 256usize)
    if e1 != ok || e2 != ok { os.exit(4) }
    var key_len = 0usize
    var key_name = 0usize
    var have_ok = false
    var failures = 0usize
    // this golden is minutes of compute per case, so it may be run in slices: `oracle_rugarch <first> <count>` (D7823)
    let (first, last) = oracle.slice(args, golden.cases.len)
    var at = first
    while at < last {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        if !same_key(c, key, key_len, key_name) {
            have_ok = fit_case(a, c, cached)
            var t = 0usize
            while t < c.args.len {
                key[t] = c.args[t]
                t += 1usize
            }
            key_len = c.args.len
            key_name = c.name.len
        }
        var got = 0.0f64 / 0.0f64
        if have_ok { got = cached[usize(c.args[c.args.len - 1usize])] }
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
