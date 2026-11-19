// e.algo.stat.unmarkedpkg's occupancy model against unmarked::occu. tests/oracle/unmarked.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R unmarked`; the layout is at the top of scripts/r_oracle/groups/unmarked.R.

use e.algo.stat.unmarkedpkg as um
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

// every case of one fit repeats its data and asks for another number, so the fit is kept and reused while the name and all arguments but the last (the index into its output) are unchanged
fn fit_case(a: *mem.Arena, c: *const oracle.Case, cached: []f64) -> bool {
    let z = c.args
    if c.name.len == 6usize {
        let mm = usize(z[0usize])
        let jj = usize(z[1usize])
        let p1 = usize(z[2usize])
        let p2 = usize(z[3usize])
        let kk = usize(z[4usize])
        let y0 = 5usize
        let x0 = y0 + mm * jj
        let z0 = x0 + mm * p1
        let out = cached[0usize..2usize * (p1 + p2) + 1usize]
        if !um.pcount(a, z[x0..x0 + mm * p1], z[z0..z0 + mm * p2], z[y0..y0 + mm * jj], mm, jj, p1, p2, kk, out[0usize..p1 + p2 + 1usize]) { ret false }
        ret um.pcount_se(a, z[x0..x0 + mm * p1], z[z0..z0 + mm * p2], z[y0..y0 + mm * jj], mm, jj, p1, p2, kk, out[0usize..p1 + p2], out[p1 + p2 + 1usize..2usize * (p1 + p2) + 1usize])
    }
    let mm = usize(z[0usize])
    let jj = usize(z[1usize])
    let p1 = usize(z[2usize])
    let p2 = usize(z[3usize])
    let y0 = 4usize
    let x0 = y0 + mm * jj
    let z0 = x0 + mm * p1
    let out = cached[0usize..2usize * (p1 + p2) + 1usize]
    if !um.occu(a, z[x0..x0 + mm * p1], z[z0..z0 + mm * p2], z[y0..y0 + mm * jj], mm, jj, p1, p2, out[0usize..p1 + p2 + 1usize]) { ret false }
    ret um.occu_se(a, z[x0..x0 + mm * p1], z[z0..z0 + mm * p2], z[y0..y0 + mm * jj], mm, jj, p1, p2, out[0usize..p1 + p2], out[p1 + p2 + 1usize..2usize * (p1 + p2) + 1usize])
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/unmarked.json")
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
