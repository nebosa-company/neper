// e.algo.stat.fpc_misc against fpc. tests/oracle/fpc_misc.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_misc`;
// the layouts are at the top of scripts/r_oracle/groups/fpc_misc.R.

use e.algo.stat.fpc_misc as fm
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
    let z = c.args
    if is(c, "dh") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let cl = labels(a, z, 4usize, n)
        let (out, e1) = mem.alloc[f64](a, 6usize)
        if e1 != ok { os.exit(5) }
        if fm.dudahart2(a, z[4usize + n..], n, p, cl, z[2usize], out) != ok { os.exit(6) }
        let w = usize(z[3usize])
        if w == 4usize { ret out[5usize] }
        ret out[w]
    }
    if is(c, "cc") {
        let nc = usize(z[0usize])
        let (ccn, e1) = mem.alloc[usize](a, nc)
        if e1 != ok { os.exit(5) }
        fm.con_comp(z[1usize..], nc, ccn)
        var s = 0.0f64
        var i = 0usize
        while i < nc {
            s += f64(i + 1usize) * f64(ccn[i])
            i += 1usize
        }
        ret s
    }
    if is(c, "sk") {
        let n = usize(z[1usize])
        let (cl, e1) = mem.alloc[usize](a, n)
        if e1 != ok { os.exit(5) }
        if fm.stupidk(a, z[4usize..], n, usize(z[2usize]), usize(z[0usize]), i64(z[3usize]), cl) != ok { os.exit(6) }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f64(i + 1usize) * f64(cl[i])
            i += 1usize
        }
        ret s
    }
    if is(c, "dcm") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let ns = usize(z[2usize])
        let cl = labels(a, z, 6usize, n)
        let (sub, e1) = mem.alloc[f64](a, ns)
        if e1 != ok { os.exit(5) }
        let (ov, sd, e2) = fm.distcritmulti(a, z[6usize + n..], n, p, cl, ns, usize(z[3usize]), i64(z[4usize]), sub)
        if e2 != ok { os.exit(6) }
        let w = usize(z[5usize])
        if w == 0usize { ret ov }
        if w == 1usize { ret sd }
        var s = 0.0f64
        var i = 0usize
        while i < ns {
            s += f64(i + 1usize) * sub[i]
            i += 1usize
        }
        ret s
    }
    if is(c, "cv") {
        let n = usize(z[0usize])
        let k = usize(z[1usize])
        let lc = usize(z[2usize])
        let cls = labels(a, z, 4usize + n * n, lc * n)
        let (idx, e1) = mem.alloc[f64](a, lc)
        let (sep, e2) = mem.alloc[f64](a, lc)
        let (comp, e3) = mem.alloc[f64](a, lc)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
        if fm.cvnn(a, z[4usize..4usize + n * n], n, cls, lc, k, idx, sep, comp) != ok { os.exit(6) }
        let w = usize(z[3usize])
        var s = 0.0f64
        var i = 0usize
        while i < lc {
            var v = idx[i]
            if w == 1usize { v = sep[i] }
            if w == 2usize { v = comp[i] }
            s += f64(i + 1usize) * v
            i += 1usize
        }
        ret s
    }
    if is(c, "mh") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (out, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        if fm.mahalanodisc(a, z[4usize + p + p * p..], n, p, z[4usize..4usize + p], z[4usize + p..4usize + p + p * p], z[2usize] > 0.5f64, out) != ok { os.exit(6) }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f64(i + 1usize) * out[i]
            i += 1usize
        }
        ret s
    }
    os.exit(9)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_misc.json")
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
            if failures <= 10usize {
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
