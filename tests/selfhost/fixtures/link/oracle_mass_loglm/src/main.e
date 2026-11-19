// e.algo.stat.massloglm against MASS loglm. The layout of every case is at the top of scripts/r_oracle/groups/mass_loglm.R.

use e.algo.stat.massloglm as ml
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nv = usize(z[0usize])
    let nt = usize(z[1usize])
    let mode = usize(z[4usize])
    var n = 1usize
    let (dims, e0) = mem.alloc[usize](a, nv)
    let (tm, e1) = mem.alloc[u64](a, nt + 1usize)
    if e0 != ok || e1 != ok { ret nan() }
    var i = 0usize
    while i < nv {
        dims[i] = usize(z[5usize + i])
        n *= dims[i]
        i += 1usize
    }
    i = 0usize
    while i < nt {
        tm[i] = u64(z[5usize + nv + i])
        i += 1usize
    }
    let at = 5usize + nv + nt
    let (r, e) = ml.loglm(a, dims, tm[0usize..nt], z[at..at + n], z[at + n..at + 2usize * n], z[2usize], usize(z[3usize]), mode >= 5usize)
    if e != ok { ret nan() }
    if mode == 0usize { ret r.lrt }
    if mode == 1usize { ret r.pearson }
    if mode == 2usize { ret r.df }
    if mode == 3usize { ret wsum(r.fit) }
    if mode == 4usize {
        var s = 0.0f64
        i = 0usize
        while i < r.nmarg {
            s += f64(i + 1usize) * f64(r.margins[i])
            i += 1usize
        }
        ret s
    }
    if mode == 5usize { ret wsum(r.param) }
    ret f64(r.nparam)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_loglm.json")
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
                var shown = *c
                if shown.args.len > 14usize { shown.args = c.args[0usize..14usize] }
                let _ = io.print(oracle.describe(a, &shown, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
