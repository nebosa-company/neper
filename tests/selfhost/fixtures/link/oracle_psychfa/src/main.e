// e.algo.stat.psych's maximum likelihood factor uniquenesses against psych::fa(fm = "ml"). tests/oracle/psychfa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R psychfa`; the layout is at the top of scripts/r_oracle/groups/psychfa.R.

use e.algo.stat.psych as ps
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

// every case of one fit repeats its data and asks for another number, so the fit is kept and reused while the name and all arguments but the last (the index into its output) are unchanged
fn fit_case(a: *mem.Arena, c: *const oracle.Case, cached: []f64) -> bool {
    let z = c.args
    let p = usize(z[0usize])
    let q = usize(z[1usize])
    if c.name.len == 8usize {
        let rot = usize(z[2usize])
        let o6 = cached[0usize..p + p * q + 2usize * q * q + 4usize]
        if rot == 0usize { ret ps.fa_varimax_fm(a, z[3usize..3usize + p * p], p, q, 0usize, o6) }
        if rot == 1usize { ret ps.fa_promax_fm(a, z[3usize..3usize + p * p], p, q, 0usize, o6) }
        ret ps.fa_oblimin_fm(a, z[3usize..3usize + p * p], p, q, 0usize, o6)
    }
    if c.name.len == 10usize {
        let o5 = cached[0usize..p + 1usize + p * q]
        ret ps.fa_resid(a, z[3usize..3usize + p * p], p, q, usize(z[2usize]), o5)
    }
    if c.name.len == 11usize {
        let o4 = cached[0usize..p + p * q + 2usize * q * q]
        ret ps.fa_ml_oblimin(a, z[2usize..2usize + p * p], p, q, o4)
    }
    if c.name.len == 7usize {
        let o3 = cached[0usize..p + p * q + q * q]
        ret ps.fa_ml_promax(a, z[2usize..2usize + p * p], p, q, o3)
    }
    if c.name.len == 5usize {
        let o2 = cached[0usize..p + p * q + q * q]
        ret ps.fa_ml_varimax(a, z[2usize..2usize + p * p], p, q, o2)
    }
    let out = cached[0usize..p + 1usize + p * q]
    ret ps.fa_ml(a, z[2usize..2usize + p * p], p, q, out)
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/psychfa.json")
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
    var at = 0usize
    while at < golden.cases.len {
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
