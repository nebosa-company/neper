// e.algo.stat.vgampkg's beta-binomial regression against VGAM::vglm(betabinomial). tests/oracle/vgam_bb.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vgam_bb`; the layout is at the top of scripts/r_oracle/groups/vgam_bb.R.

use e.algo.stat.vgampkg as vg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

// every case of one fit repeats its data and asks for another number, so the fit is kept and reused while the name and all arguments but the last (the index into its output) are unchanged
fn fit_case(a: *mem.Arena, c: *const oracle.Case, cached: []f64) -> bool {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (x, e0) = mem.alloc[f64](a, n * (p + 1usize))
    if e0 != ok { ret false }
    let out = cached[0usize..p + 3usize]
    var i = 0usize
    while i < n {
        x[i * (p + 1usize)] = 1.0f64
        var t = 0usize
        while t < p {
            x[i * (p + 1usize) + 1usize + t] = z[2usize + 2usize * n + i * p + t]
            t += 1usize
        }
        i += 1usize
    }
    ret vg.betabinomial(a, x, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], n, p + 1usize, out)
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/vgam_bb.json")
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
