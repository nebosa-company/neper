// e.algo.stat.polcapkg against poLCA. tests/oracle/polca.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polca`; the layout is at the top of scripts/r_oracle/groups/polca.R.

use e.algo.stat.polcapkg as pl
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "rs") {
        // args (n, J, R, ncat[J], nrep, seed, data[n*J] row-major 1-based, q)
        let rn = usize(z[0usize])
        let rj = usize(z[1usize])
        let rr = usize(z[2usize])
        let (rc, re1) = mem.alloc[usize](a, rj)
        if re1 != ok { ret nan }
        var rtc = 0usize
        var ri = 0usize
        while ri < rj {
            rc[ri] = usize(z[3usize + ri])
            rtc += rc[ri]
            ri += 1usize
        }
        let nrep = usize(z[3usize + rj])
        let seed = i64(z[4usize + rj])
        let (rd, re2) = mem.alloc[f64](a, rn * rj)
        let (rp, re3) = mem.alloc[f64](a, rr * rtc)
        let (rpr, re4) = mem.alloc[f64](a, rr)
        if re2 != ok || re3 != ok || re4 != ok { ret nan }
        ri = 0usize
        while ri < rn * rj {
            rd[ri] = z[5usize + rj + ri] - 1.0f64
            ri += 1usize
        }
        let rll = pl.em_restarts(a, rd, rn, rj, rc, rr, nrep, seed, 1.0e-10f64, 1000usize, rp, rpr)
        let rq = usize(z[5usize + rj + rn * rj])
        if rq == 0usize { ret rll }
        if rq == 1usize {
            var sp = 0.0f64
            ri = 0usize
            while ri < rr {
                sp += rpr[ri] * rpr[ri]
                ri += 1usize
            }
            ret sp
        }
        var sq = 0.0f64
        var idx = 0usize
        var roff = 0usize
        var rv = 0usize
        while rv < rj {
            var rcl = 0usize
            while rcl < rr {
                var rk = 0usize
                while rk < rc[rv] {
                    idx += 1usize
                    sq += rp[rcl * rtc + roff + rk] * rp[rcl * rtc + roff + rk]
                    rk += 1usize
                }
                rcl += 1usize
            }
            roff += rc[rv]
            rv += 1usize
        }
        ret sq
    }
    let n = usize(z[0usize])
    let nj = usize(z[1usize])
    let nr = usize(z[2usize])
    let (ncat, e1) = mem.alloc[usize](a, nj)
    if e1 != ok { ret nan }
    var tc = 0usize
    var i = 0usize
    while i < nj {
        ncat[i] = usize(z[3usize + i])
        tc += ncat[i]
        i += 1usize
    }
    let (probs, e2) = mem.alloc[f64](a, nr * tc)
    let (prior, e3) = mem.alloc[f64](a, nr)
    let (data, e4) = mem.alloc[f64](a, n * nj)
    if e2 != ok || e3 != ok || e4 != ok { ret nan }
    var o = 3usize + nj
    // the start probabilities arrive as variable blocks of R rows: variable v, class r, category k
    var off = 0usize
    var v = 0usize
    while v < nj {
        var r = 0usize
        while r < nr {
            var k = 0usize
            while k < ncat[v] {
                probs[r * tc + off + k] = z[o]
                o += 1usize
                k += 1usize
            }
            r += 1usize
        }
        off += ncat[v]
        v += 1usize
    }
    i = 0usize
    while i < n * nj {
        data[i] = z[o + i] - 1.0f64
        i += 1usize
    }
    let ll = pl.em(a, data, n, nj, ncat, nr, probs, prior, 1.0e-13f64, 20000usize)
    if str.eq(c.name, "ll") { ret ll }
    if str.eq(c.name, "npar") { ret pl.fit_stats(a, data, n, nj, ncat, nr, probs, prior, ll, 0usize) }
    if str.eq(c.name, "aic") { ret pl.fit_stats(a, data, n, nj, ncat, nr, probs, prior, ll, 1usize) }
    if str.eq(c.name, "gsq") { ret pl.fit_stats(a, data, n, nj, ncat, nr, probs, prior, ll, 2usize) }
    if str.eq(c.name, "chisq") { ret pl.fit_stats(a, data, n, nj, ncat, nr, probs, prior, ll, 3usize) }
    if str.eq(c.name, "rdf") { ret pl.fit_stats(a, data, n, nj, ncat, nr, probs, prior, ll, 4usize) }
    if str.eq(c.name, "pred") { ret pl.fit_stats(a, data, n, nj, ncat, nr, probs, prior, ll, 5usize) }
    var s = 0.0f64
    if str.eq(c.name, "prior") {
        i = 0usize
        while i < nr {
            s += prior[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "bic") {
        var npar = f64(nr - 1usize)
        i = 0usize
        while i < nj {
            npar += f64(nr * (ncat[i] - 1usize))
            i += 1usize
        }
        ret 0.0f64 - 2.0f64 * ll + npar * math.log[f64](f64(n))
    }
    // R lists the probabilities variable by variable, then class, then category
    var pos = 1usize
    off = 0usize
    v = 0usize
    while v < nj {
        var r = 0usize
        while r < nr {
            var k = 0usize
            while k < ncat[v] {
                s += probs[r * tc + off + k] * f64(pos)
                pos += 1usize
                k += 1usize
            }
            r += 1usize
        }
        off += ncat[v]
        v += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polca.json")
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
