// e.algo.stat.arulespkg against arules apriori. tests/oracle/arules.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R arules`; the layout is at the top of scripts/r_oracle/groups/arules.R.

use e.algo.stat.arulespkg as ar
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nt = usize(z[0usize])
    let ni = usize(z[1usize])
    let (tr, e1) = mem.alloc[u64](a, nt)
    let (out, e2) = mem.alloc[f64](a, 6usize)
    if e1 != ok || e2 != ok { ret nan }
    var t = 0usize
    while t < nt {
        var m = 0u64
        var j = 0usize
        while j < ni {
            if z[5usize + t * ni + j] > 0.5f64 { m = m | (1u64 << u64(j)) }
            j += 1usize
        }
        tr[t] = m
        t += 1usize
    }
    if str.starts_with(c.name, "h") && c.name.len == 2usize {
        let (ho, he) = mem.alloc[f64](a, 6usize)
        if he != ok { ret nan }
        if ar.apriori_hyper(a, tr, ni, z[2usize], z[3usize], usize(z[4usize]), ho) != ok { ret nan }
        ret ho[usize(c.name[1usize]) - 48usize]
    }
    if str.starts_with(c.name, "b") && c.name.len >= 2usize {
        let (bo, be) = mem.alloc[f64](a, 39usize)
        if be != ok { ret nan }
        if ar.apriori_basic(a, tr, ni, z[2usize], z[3usize], usize(z[4usize]), bo) != ok { ret nan }
        var idx = 0usize
        var pos = 1usize
        while pos < c.name.len {
            idx = idx * 10usize + (usize(c.name[pos]) - 48usize)
            pos += 1usize
        }
        ret bo[idx]
    }
    if str.starts_with(c.name, "c") && !str.eq(c.name, "") && c.name.len == 2usize {
        let (co, ce) = mem.alloc[f64](a, 4usize)
        if ce != ok { ret nan }
        if ar.closed_maximal(a, tr, ni, z[2usize], co) != ok { ret nan }
        ret co[usize(c.name[1usize]) - 48usize]
    }
    if str.starts_with(c.name, "m") && !str.eq(c.name, "nrule") {
        let (mo, me) = mem.alloc[f64](a, 10usize)
        if me != ok { ret nan }
        if ar.apriori_measures(a, tr, ni, z[2usize], z[3usize], usize(z[4usize]), mo) != ok { ret nan }
        ret mo[usize(c.name[1usize]) - 48usize]
    }
    if ar.apriori(a, tr, ni, z[2usize], z[3usize], usize(z[4usize]), out) != ok { ret nan }
    if str.eq(c.name, "nfreq") { ret out[0usize] }
    if str.eq(c.name, "sfreq") { ret out[1usize] }
    if str.eq(c.name, "nrule") { ret out[2usize] }
    if str.eq(c.name, "srule") { ret out[3usize] }
    if str.eq(c.name, "sconf") { ret out[4usize] }
    ret out[5usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/arules.json")
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
