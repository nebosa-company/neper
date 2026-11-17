// e.algo.stat.drdid against DRDID, every estimator with influence function, standard error, limits and bootstrap draws. tests/oracle/drdid_full.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R drdid_full`; the case layout is at the top of scripts/r_oracle/groups/drdid_full.R.

use e.algo.rand.r as rng
use e.algo.stat.drdid as dr
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn close(got: f64, want: f64) -> bool {
    if !(got - got == 0.0f64) { ret false }
    var scale = math.abs[f64](want)
    if scale < 1.0f64 { scale = 1.0f64 }
    ret math.abs[f64](got - want) <= 1.0e-11f64 * scale
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/drdid_full.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let kind = u8(x[0usize])
        let boot = u8(x[1usize])
        let nboot = usize(x[2usize])
        let seed = i64(x[3usize])
        let tl = x[4usize]
        let n = usize(x[5usize])
        let p = usize(x[6usize])
        let ya = x[7usize..7usize + n]
        let yb = x[7usize + n..7usize + 2usize * n]
        let dd = x[7usize + 2usize * n..7usize + 3usize * n]
        let xx = x[7usize + 3usize * n..7usize + 3usize * n + n * p]
        let iw = x[7usize + 3usize * n + n * p..7usize + 4usize * n + n * p]
        let want = x[7usize + 4usize * n + n * p..]
        let (y, post, ok1) = split(a, kind, ya, yb, n)
        if !ok1 { os.exit(4) }
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let r = dr.did(a, &g, kind, boot, nboot, y, post, dd, xx, iw, n, p, tl)
        var bad = 0usize
        if !close(r.att, want[0usize]) { bad += 1usize }
        if !close(r.se, want[1usize]) { bad += 1usize }
        if !close(r.lci, want[2usize]) { bad += 1usize }
        if !close(r.uci, want[3usize]) { bad += 1usize }
        var wsum = 0.0f64
        var i = 0usize
        while i < n {
            wsum += r.inf[i] * f64(i + 1usize)
            i += 1usize
        }
        if !close(r.inf[0usize], want[4usize]) { bad += 1usize }
        if !close(r.inf[(n + 1usize) / 2usize - 1usize], want[5usize]) { bad += 1usize }
        if !close(r.inf[n - 1usize], want[6usize]) { bad += 1usize }
        if !close(wsum / f64(n), want[7usize]) { bad += 1usize }
        if boot > 0u8 {
            var bsum = 0.0f64
            var b = 0usize
            while b < nboot {
                bsum += r.boots[b] * f64(b + 1usize)
                b += 1usize
            }
            if !close(r.boots[0usize], want[8usize]) { bad += 1usize }
            if !close(r.boots[nboot - 1usize], want[9usize]) { bad += 1usize }
            if !close(bsum / f64(nboot), want[10usize]) { bad += 1usize }
        }
        if !oracle.agrees(f64(bad), c) {
            failures += 1usize
            if failures <= 12usize {
                let (b0, be) = str.builder(a, 80usize)
                if be == ok {
                    var sb = b0
                    let _ = str.push(&sb, "case ")
                    let _ = str.push_f64(&sb, f64(at))
                    let _ = str.push(&sb, " kind ")
                    let _ = str.push_f64(&sb, f64(kind))
                    let _ = str.push(&sb, " boot ")
                    let _ = str.push_f64(&sb, f64(boot))
                    let _ = str.push(&sb, " mismatches ")
                    let _ = str.push_f64(&sb, f64(bad))
                    let _ = str.push(&sb, "\n")
                    let _ = io.print(str.done(&sb))
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}

// the panel kinds take y1 - y0 (twfe keeps y1 and y0 apart), the cross-section kinds y and post as they stand
fn split(a: *mem.Arena, kind: u8, ya: []const f64, yb: []const f64, n: usize) -> ([]const f64, []const f64, bool) {
    if kind >= 10u8 || kind == 5u8 { ret (ya, yb, true) }
    let (dy, e) = mem.alloc[f64](a, n)
    if e != ok { ret (ya, yb, false) }
    var i = 0usize
    while i < n {
        dy[i] = ya[i] - yb[i]
        i += 1usize
    }
    ret (dy, dy, true)
}
