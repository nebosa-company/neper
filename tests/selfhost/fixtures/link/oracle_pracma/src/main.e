// e.algo.stat.pracma against pracma. tests/oracle/pracma.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pracma`; the layout is at the top of scripts/r_oracle/groups/pracma.R.

use e.algo.stat.pracma as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "trapz") {
        let n = usize(x[0usize])
        ret pm.trapz(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
    }
    if str.eq(k, "cumtrapz") {
        let n = usize(x[0usize])
        let (o, e) = pm.cumtrapz(a, x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
        if e != ok { os.exit(5) }
        var t = 0.0f64
        var i = 0usize
        while i < n {
            t += o[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "polyfit") {
        let deg = usize(x[0usize])
        let idx = usize(x[1usize])
        let n = usize(x[2usize])
        let (p, e) = pm.polyfit(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], deg)
        if e != ok { os.exit(5) }
        ret p[idx]
    }
    if str.eq(k, "polyval") { ret pm.polyval(x[1usize..x.len], x[0usize]) }
    if str.eq(k, "fp_count") || str.eq(k, "fp_sum") {
        let n = usize(x[7usize])
        let (rows, cnt, e) = pm.findpeaks(a, x[8usize..8usize + n], usize(x[0usize]), usize(x[1usize]), x[2usize], usize(x[3usize]), x[4usize], usize(x[5usize]), x[6usize] > 0.5f64)
        if e != ok { os.exit(5) }
        if str.eq(k, "fp_count") { ret f64(cnt) }
        var t = 0.0f64
        var i = 0usize
        while i < cnt * 4usize {
            t += rows[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "rref") {
        let nr = usize(x[0usize])
        let nc = usize(x[1usize])
        let (m, e) = mem.alloc[f64](a, nr * nc)
        if e != ok { os.exit(5) }
        var i = 0usize
        while i < nr * nc {
            m[i] = x[2usize + i]
            i += 1usize
        }
        pm.rref(m, nr, nc)
        var t = 0.0f64
        i = 0usize
        while i < nr * nc {
            t += m[i] * f64(i + 1usize)
            i += 1usize
        }
        ret t
    }
    if str.eq(k, "primes") { ret f64(pm.primes_count(u64(x[0usize]))) }
    if str.eq(k, "fsum") || str.eq(k, "fcnt") {
        let (s, n) = pm.factors(u64(x[0usize]))
        if str.eq(k, "fsum") { ret f64(s) }
        ret f64(n)
    }
    if str.eq(k, "gcd") {
        let (g, cc, d) = pm.gcd_ext(i64(x[0usize]), i64(x[1usize]))
        let w = usize(x[2usize])
        if w == 0usize { ret f64(g) }
        if w == 1usize { ret f64(cc) }
        ret f64(d)
    }
    if str.eq(k, "pchip") {
        let n = usize(x[0usize])
        ret pm.pchip(a, x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n], x[1usize + 2usize * n])
    }
    if str.eq(k, "quadgk") { ret pm.quadgk(usize(x[0usize]), x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "nchoosek") { ret pm.nchoosek(x[0usize], x[1usize]) }
    var o: [3]f64 = zero
    pm.cross(x[0usize..3usize], x[3usize..6usize], o[0usize..3usize])
    ret o[usize(x[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pracma.json")
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
