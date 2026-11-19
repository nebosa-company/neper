// e.algo.stat.fpc cluster.stats in full against fpc. tests/oracle/fpc_stats.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_stats`; the layouts are at the top of scripts/r_oracle/groups/fpc_stats.R.

use e.algo.stat.fpc as fp
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn is(c: *const oracle.Case, s: str) -> bool {
    if c.name.len != s.len { ret false }
    var i = 0usize
    while i < s.len {
        if c.name[i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn labels(a: *mem.Arena, x: []const f64, at: usize, n: usize) -> []usize {
    let (cl, e) = mem.alloc[usize](a, n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        cl[i] = usize(x[at + i])
        i += 1usize
    }
    ret cl
}

fn checksum(out: []const f64, sel: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < sel.len {
        var v = out[usize(sel[i])]
        if !(v > -1.0e300f64 && v < 1.0e300f64) { v = -7777.0f64 }
        s += f64(i + 1usize) * v
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if is(c, "cmp") {
        let n = usize(x[0usize])
        let cn = usize(x[1usize])
        let cn2 = usize(x[2usize])
        let c1 = labels(a, x, 3usize, n)
        let c2 = labels(a, x, 3usize + n, n)
        ret fp.compare(a, c1, cn, c2, cn2, 16usize) + 2.0f64 * fp.compare(a, c1, cn, c2, cn2, 17usize)
    }
    if is(c, "csdb") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let nsel = usize(x[4usize])
        let (cv, e1) = mem.alloc[i64](a, n)
        let (sd, e2) = mem.alloc[bool](a, n)
        let (d, e3) = mem.alloc[f64](a, n * n)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
        let xs = x[5usize + nsel..]
        if fp.dbscan(a, xs, n, p, x[2usize], usize(x[3usize]), cv, sd) != ok { os.exit(6) }
        var cn = 0usize
        var i = 0usize
        while i < n {
            if usize(cv[i]) > cn { cn = usize(cv[i]) }
            i += 1usize
        }
        cn += 1usize
        let (cl, e4) = mem.alloc[usize](a, n)
        if e4 != ok { os.exit(5) }
        i = 0usize
        while i < n {
            cl[i] = usize(cv[i])
            if cv[i] == 0i64 { cl[i] = cn }
            var j = 0usize
            while j < n {
                var s = 0.0f64
                var q = 0usize
                while q < p {
                    let t = xs[i * p + q] - xs[j * p + q]
                    s += t * t
                    q += 1usize
                }
                d[i * n + j] = math.sqrt[f64](s)
                j += 1usize
            }
            i += 1usize
        }
        let (out, e5) = mem.alloc[f64](a, fp.cs_len(cn))
        if e5 != ok { os.exit(5) }
        if fp.cstats(a, d, n, cl, cn, true, 31usize, true, 0.1f64, out) != ok { os.exit(7) }
        ret checksum(out, x[5usize..5usize + nsel])
    }
    let n = usize(x[0usize])
    let cn = usize(x[1usize])
    let cn2 = usize(x[2usize])
    let flags = usize(x[3usize])
    let nsel = usize(x[7usize])
    let at = 8usize + nsel
    let cl = labels(a, x, at, n)
    var next = at + n
    if cn2 > 0usize { next += n }
    let (d, e1) = mem.alloc[f64](a, n * n)
    let (out, e2) = mem.alloc[f64](a, fp.cs_len(cn))
    if e1 != ok || e2 != ok { os.exit(5) }
    var i = 0usize
    while i < n * n {
        d[i] = 0.0f64
        i += 1usize
    }
    var q = next
    var j = 0usize
    while j + 1usize < n {
        i = j + 1usize
        while i < n {
            d[i * n + j] = x[q]
            d[j * n + i] = x[q]
            q += 1usize
            i += 1usize
        }
        j += 1usize
    }
    if fp.cstats(a, d, n, cl, cn, x[4usize] > 0.5f64, flags, x[5usize] > 0.5f64, x[6usize], out) != ok { os.exit(7) }
    if cn2 > 0usize {
        let c2 = labels(a, x, at + n, n)
        out[16usize] = fp.compare(a, cl, cn, c2, cn2, 16usize)
        out[17usize] = fp.compare(a, cl, cn, c2, cn2, 17usize)
    }
    ret checksum(out, x[8usize..8usize + nsel])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_stats.json")
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
            if failures <= 6usize {
                var c2 = *c
                c2.args = c.args[0usize..4usize]
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
