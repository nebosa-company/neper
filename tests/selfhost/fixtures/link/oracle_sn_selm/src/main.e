// selm fits of e.algo.stat.sn against sn (one response and matrix response). tests/oracle/sn_selm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sn_selm`. The cases of one fit follow each other, so a fit is
// computed once and reused for its remaining cases.

use e.algo.stat.sn as sn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Memo = struct { key: f64, ll: f64, out: []f64, se: []f64, live: bool }

fn key_of(x: []const f64, which: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        if i != which { s += x[i] * f64(i % 97usize + 1usize) }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, m: *Memo, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    let multi = str.eq(c.name, "mvselm")
    // one response: (fam, pen, n, p, which, fnu, symm, weighted, y, x, w); matrix response: (fam, pen, n, d, p, which, y, x)
    var wi = 4usize
    var base = 8usize
    if multi {
        wi = 5usize
        base = 6usize
    }
    let which = usize(x[wi])
    let key = key_of(x, wi)
    let fam = x[0usize]
    let pen = x[1usize]
    let n = usize(x[2usize])
    var d = 1usize
    var p = usize(x[3usize])
    if multi {
        d = usize(x[3usize])
        p = usize(x[4usize])
    }
    var np = p * d + d * d + d
    if !multi { np = p + 2usize }
    if fam == 1.0f64 { np += 1usize }
    if !m.live || m.key != key {
        let (yy, e1) = mem.alloc[f64](a, n * d)
        let (xx, e2) = mem.alloc[f64](a, n * p)
        let (ww, e3) = mem.alloc[f64](a, n)
        let (o, e4) = mem.alloc[f64](a, p * d + d * d + d + 1usize)
        let (se, e5) = mem.alloc[f64](a, p + 4usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
        var i = 0usize
        while i < n {
            ww[i] = 1.0f64
            i += 1usize
        }
        i = 0usize
        while i < n * d {
            yy[i] = x[base + i]
            i += 1usize
        }
        i = 0usize
        while i < n * p {
            xx[i] = x[base + n * d + i]
            i += 1usize
        }
        var ll = nan
        if multi {
            ll = sn.selm_mv(a, yy, xx, ww, d, p, fam == 1.0f64, pen == 1.0f64, o)
        } else {
            i = 0usize
            while i < n {
                ww[i] = x[base + n + n * p + i]
                i += 1usize
            }
            ll = sn.selm_fit2(a, yy, xx, ww, p, fam == 1.0f64, pen == 1.0f64, x[6usize] == 1.0f64, x[5usize], o, se)
        }
        m.key = key
        m.ll = ll
        m.out = o
        m.se = se
        m.live = true
    }
    if which == np { ret m.ll }
    if which > np { ret m.se[which - np - 1usize] }
    ret m.out[which]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sn_selm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var memo: Memo = zero
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, &memo, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
