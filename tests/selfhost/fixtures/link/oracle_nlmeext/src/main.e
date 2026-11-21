// e.algo.stat.nlmeml against nlme::nlme with a user-written model function (Weibull growth curve), pdMat classes and two nested grouping levels.
// tests/oracle/nlmeext.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nlmeext`; the case layout is at the top of
// scripts/r_oracle/groups/nlmeext.R. Cases of one fit differ only in the output index (args[1]), so a fit is cached while consecutive cases share the rest.

use e.algo.stat.nlmeml as nm
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// A - B exp(-exp(lk) x^pw) and its gradient
fn weibull(x: f64, p: []const f64, gr: []f64) -> f64 {
    let u = math.exp[f64](p[2usize]) * math.exp[f64](p[3usize] * math.log[f64](x))
    let e = math.exp[f64](0.0f64 - u)
    gr[0usize] = 1.0f64
    gr[1usize] = 0.0f64 - e
    gr[2usize] = p[1usize] * e * u
    gr[3usize] = p[1usize] * e * u * math.log[f64](x)
    ret p[0usize] - p[1usize] * e
}

fn same_fit(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if i != 1usize && x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// the fit vector of the case; length 0 on failure
fn fit_vec(a: *mem.Arena, x: []const f64, out: []f64) -> usize {
    let kind = i64(x[0usize])
    let n = usize(x[3usize])
    let ng1 = usize(x[4usize])
    let ng2 = usize(x[5usize])
    var o = 6usize
    let gs1 = x[o..o + ng1]
    o += ng1
    let gs2 = x[o..o + ng2]
    o += ng2
    let xs = x[o..o + n]
    o += n
    let y = x[o..o + n]
    o += n
    let nr1 = usize(x[o])
    o += 1usize
    let rs1 = x[o..o + nr1]
    o += nr1
    let pd1 = i64(x[o])
    o += 1usize
    let nr2 = usize(x[o])
    o += 1usize
    let rs2 = x[o..o + nr2]
    o += nr2
    let pd2 = i64(x[o])
    o += 1usize
    var np = 3usize
    if kind == 0i64 { np = 4usize }
    let start = x[o..o + np]
    let len = nm.nlme_multi_len(np, nr1, nr2)
    if len > out.len { ret 0usize }
    if nm.nlme_multi(a, kind, weibull, np, n, gs1, gs2, xs, y, rs1, pd1, rs2, pd2, x[2usize] != 0.0f64, start, out[0usize..len]) != ok { ret 0usize }
    ret len
}

// "case n, output q: got G, R says W": the case arguments are the whole data set, so oracle.describe is too long to read
fn brief(a: *mem.Arena, at: usize, c: *const oracle.Case, got: f64) -> str {
    let (initial, be) = str.builder(a, 96usize)
    if be != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, "case ")
    let _ = str.push_f64(&b, f64(at))
    let _ = str.push(&b, " kind ")
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, " output ")
    let _ = str.push_f64(&b, c.args[1usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nlmeext.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (cache, ce) = mem.alloc[f64](a, 256usize)
    if ce != ok { os.exit(4) }
    var cache_len = 0usize
    var cache_key: []const f64 = golden.cases[0usize].args
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let st = mem.mark(a)
        var got = 0.0f64 / 0.0f64
        if cache_len == 0usize || !same_fit(cache_key, c.args) {
            cache_len = fit_vec(a, c.args, cache)
            cache_key = c.args
        }
        var q = usize(c.args[1usize])
        if q >= 1000usize { q -= 1000usize }
        if cache_len > q { got = cache[q] }
        mem.reset(a, st)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 60usize {
                let _ = io.print(brief(a, at, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
