// e.algo.stat.fpc small exports against fpc. tests/oracle/fpc_small.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_small`; the layouts are at the top of scripts/r_oracle/groups/fpc_small.R.

use e.algo.stat.fpc as fp
use e.io
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if is(c, "cal") || is(c, "neg") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let cn = usize(x[2usize])
        let cl = labels(a, x, 3usize, n)
        var v = 0.0f64
        var e = ok
        if is(c, "cal") {
            let (v1, e1) = fp.calinhara(a, x[3usize + n..], n, p, cl, cn)
            v = v1
            e = e1
        } else {
            let (v1, e1) = fp.neginc(a, x[3usize + n..], n, p, cl, cn)
            v = v1
            e = e1
        }
        if e != ok { os.exit(6) }
        ret v
    }
    if is(c, "cwm") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        ret fp.cov_wml(x[4usize + n..], n, p, x[4usize..4usize + n], usize(x[2usize]), usize(x[3usize]))
    }
    if is(c, "cw") { ret fp.cweight(x[0usize], x[1usize]) }
    if is(c, "clj") {
        let n = usize(x[0usize])
        ret fp.clujaccard(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], n, x[1usize])
    }
    if is(c, "cm") {
        let (v, e) = fp.cmahal(a, usize(x[0usize]), x[1usize], usize(x[2usize]), x[3usize], usize(x[4usize]), x[5usize], x[6usize], usize(x[7usize]))
        if e != ok { os.exit(7) }
        ret v
    }
    if is(c, "cf") {
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        ret fp.confusion(x[4usize + k..], n, k, x[4usize..4usize + k], usize(x[2usize]), usize(x[3usize]))
    }
    os.exit(9)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_small.json")
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
