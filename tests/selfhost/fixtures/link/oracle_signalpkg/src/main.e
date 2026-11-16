// e.algo.stat.signalpkg against signal. tests/oracle/signalpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R signalpkg`; the layout is at the top of scripts/r_oracle/groups/signalpkg.R.

use e.algo.stat.signalpkg as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "sg") {
        let wn = usize(x[1usize])
        let po = usize(x[2usize])
        let (o, e) = mem.alloc[f64](a, wn)
        if e != ok { os.exit(5) }
        if sp.sgolay_center(a, po, wn, o) != ok { os.exit(6) }
        var q = 0usize
        var tt = 0.0f64
        while q < wn {
            tt += o[q] * f64(q + 1usize)
            q += 1usize
        }
        ret tt
    }
    let n = usize(x[1usize])
    let w = x[2usize]
    var s = 0.0f64
    if str.eq(k, "fir1") {
        let (o, e) = mem.alloc[f64](a, n + 1usize)
        if e != ok { os.exit(5) }
        sp.fir1(n, w, o)
        var i = 0usize
        while i <= n {
            s += o[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    let (b, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { os.exit(6) }
    let (aa, e2) = mem.alloc[f64](a, n + 1usize)
    if e2 != ok { os.exit(7) }
    sp.butter(n, w, x[0usize] > 0.5f64, b, aa)
    var i = 0usize
    if str.eq(k, "b") || str.eq(k, "a") {
        while i <= n {
            if str.eq(k, "b") { s += b[i] * f64(i + 1usize) } else { s += aa[i] * f64(i + 1usize) }
            i += 1usize
        }
        ret s
    }
    if str.eq(k, "ff") {
        let len = usize(x[3usize])
        let (y, e3) = mem.alloc[f64](a, len)
        if e3 != ok { os.exit(8) }
        if sp.filtfilt(a, b, aa, x[4usize..4usize + len], y) != ok { os.exit(9) }
        var q = 0usize
        while q < len {
            s += y[q] * f64(q + 1usize)
            q += 1usize
        }
        ret s
    }
    if str.eq(k, "fre") || str.eq(k, "fim") {
        var fr: [5]f64 = zero
        fr[0usize] = 0.1f64
        fr[1usize] = 0.5f64
        fr[2usize] = 1.2f64
        fr[3usize] = 2.0f64
        fr[4usize] = 3.0f64
        var q = 0usize
        while q < 5usize {
            let (re, im) = sp.freqz_at(b, aa, fr[q])
            if str.eq(k, "fre") { s += re * f64(q + 1usize) } else { s += im * f64(q + 1usize) }
            q += 1usize
        }
        ret s
    }
    let len = usize(x[3usize])
    let (y, e3) = mem.alloc[f64](a, len)
    if e3 != ok { os.exit(8) }
    sp.filter(b, aa, x[4usize..4usize + len], y)
    i = 0usize
    while i < len {
        s += y[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/signalpkg.json")
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
