// e.algo.stat.nlmenest against nlme::lme with nested random intercepts (random = ~ 1 | g1 / g2).
// tests/oracle/nlmenest.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nlmenest`; the case layout is at the top of
// scripts/r_oracle/groups/nlmenest.R. Cases of one fit differ only in the output index (args[0]), so a fit is cached while consecutive cases share the rest.

use e.algo.stat.nlmenest as ne
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn same_fit(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    var i = 1usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// the fit vector of the case; length 0 on failure
fn fit_vec(a: *mem.Arena, x: []const f64, out: []f64) -> usize {
    let reml = x[1usize] != 0.0f64
    let n = usize(x[2usize])
    let p = usize(x[3usize])
    let n1 = usize(x[4usize])
    var o = 5usize
    let g1 = x[o..o + n1]
    o += n1
    let n2 = usize(x[o])
    o += 1usize
    let g2 = x[o..o + n2]
    o += n2
    let y = x[o..o + n]
    o += n
    let xm = x[o..o + n * p]
    let len = ne.nest_len(p, n1, n2)
    if len > out.len { ret 0usize }
    if ne.nest_fit(a, reml, n, p, g1, g2, y, xm, out[0usize..len]) != ok { ret 0usize }
    ret len
}

fn brief(a: *mem.Arena, at: usize, c: *const oracle.Case, got: f64) -> str {
    let (initial, be) = str.builder(a, 96usize)
    if be != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, "case ")
    let _ = str.push_f64(&b, f64(at))
    let _ = str.push(&b, " output ")
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nlmenest.json")
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
        let q = usize(c.args[0usize])
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
