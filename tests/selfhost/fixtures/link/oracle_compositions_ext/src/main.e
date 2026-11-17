// e.algo.stat.compositions_ext against compositions (and energy for the normality test). tests/oracle/compositions_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R compositions_ext`; the layout of every case is at the top of scripts/r_oracle/groups/compositions_ext.R.

use e.algo.rand.r as rng
use e.algo.stat.compositions as cm
use e.algo.stat.compositions_ext as cx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pick(v: []const f64, q: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if q == 0usize { s += v[i] }
        if q == 1usize { s += v[i] * f64(i + 1usize) }
        if q == 2usize { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "rc") {
        let kind = usize(z[0usize])
        let n = usize(z[1usize])
        let d = usize(z[2usize])
        let p = z[3usize]
        let q = usize(z[4usize])
        let x = z[5usize..5usize + n * d]
        let y = z[5usize + n * d..5usize + 2usize * n * d]
        let (o, e) = mem.alloc[f64](a, n * d + n * n)
        if e != ok { ret nan() }
        var len = n * d
        if kind == 0usize { cx.rcomp_cdt(x, n, d, o) }
        if kind == 1usize {
            len = n
            if cx.rcomp_norm(a, x, n, d, o) != ok { ret nan() }
        }
        if kind == 2usize { if cx.rcomp_minus(a, x, y, n, d, o) != ok { ret nan() } }
        if kind == 3usize { cx.rcomp_times(x, p, n, d, o) }
        if kind == 4usize {
            len = d
            if cx.rcomp_mean(a, x, n, d, o) != ok { ret nan() }
        }
        if kind == 5usize {
            len = d * d
            if cx.rcomp_var(a, x, n, d, o) != ok { ret nan() }
        }
        if kind == 6usize {
            len = n * (n - 1usize) / 2usize
            if cx.rcomp_dist(a, x, n, d, o) != ok { ret nan() }
        }
        if kind == 7usize {
            len = n * (d - 1usize)
            if cx.rcomp_idt(a, x, n, d, o) != ok { ret nan() }
        }
        ret pick(o[0usize..len], q)
    }
    if str.eq(c.name, "base") {
        let kind = usize(z[0usize])
        let d = usize(z[1usize])
        let nc = usize(z[2usize])
        let q = usize(z[3usize])
        let (o, e) = mem.alloc[f64](a, d * nc + 4usize * d + 100usize)
        if e != ok { ret nan() }
        if kind == 0usize {
            cx.signary_base(z[4usize..4usize + d * nc], d, nc, o)
            ret pick(o[0usize..d * nc], q)
        }
        if kind == 1usize {
            if cx.balanced_base(a, d, o) != ok { ret nan() }
            ret pick(o[0usize..d * nc], q)
        }
        if kind == 2usize {
            cx.balance_col(z[4usize..4usize + d], z[4usize + d..4usize + 2usize * d], o)
            ret pick(o[0usize..d], q)
        }
        let n = usize(z[4usize])
        let (r, e2) = mem.alloc[f64](a, n * nc)
        if e2 != ok { ret nan() }
        if cx.ilr_base(a, z[5usize + d * nc..5usize + d * nc + n * d], n, d, z[5usize..5usize + d * nc], nc, r) != ok { ret nan() }
        ret pick(r, q)
    }
    if str.eq(c.name, "zr") {
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        let (o, e) = mem.alloc[f64](a, n * d)
        if e != ok { ret nan() }
        cx.zero_replace(z[4usize..4usize + n * d], n, d, z[4usize + n * d..4usize + n * d + d], z[2usize], o)
        ret pick(o, usize(z[3usize]))
    }
    if str.eq(c.name, "nl") {
        let kind = usize(z[0usize])
        let nrep = usize(z[1usize])
        let seed = i64(z[2usize])
        let d = usize(z[3usize])
        let g = usize(z[4usize])
        let q = usize(z[5usize])
        let (sz, e1) = mem.alloc[usize](a, g)
        if e1 != ok { ret nan() }
        var n = 0usize
        var i = 0usize
        while i < g {
            sz[i] = usize(z[6usize + i])
            n += sz[i]
            i += 1usize
        }
        let m = d - 1usize
        let (co, e2) = mem.alloc[f64](a, n * m)
        if e2 != ok { ret nan() }
        if cm.ilr(a, z[6usize + g..6usize + g + n * d], n, d, co) != ok { ret nan() }
        var rg: rng.Rng = zero
        rng.seed(&rg, seed)
        var res: [3]f64 = zero
        if cx.normal_location(a, &rg, kind, co, sz, m, nrep, res[0usize..3usize]) != ok { ret nan() }
        ret res[q]
    }
    if str.eq(c.name, "gauss") {
        let n = usize(z[3usize])
        var res: [2]f64 = zero
        cx.gauss_test(z[5usize..5usize + n], z[1usize], z[2usize], usize(z[0usize]), res[0usize..2usize])
        ret res[usize(z[4usize])]
    }
    if str.eq(c.name, "etest") {
        let nrep = usize(z[0usize])
        let seed = i64(z[1usize])
        let n = usize(z[2usize])
        let d = usize(z[3usize])
        let q = usize(z[4usize])
        let m = d - 1usize
        let (co, e) = mem.alloc[f64](a, n * m)
        if e != ok { ret nan() }
        if cm.ilr(a, z[5usize..5usize + n * d], n, d, co) != ok { ret nan() }
        var rg: rng.Rng = zero
        rng.seed(&rg, seed)
        var res: [2]f64 = zero
        if cx.energy_normal(a, &rg, co, n, m, nrep, res[0usize..2usize]) != ok { ret nan() }
        ret res[q]
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/compositions_ext.json")
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
