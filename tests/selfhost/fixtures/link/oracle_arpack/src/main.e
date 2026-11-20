// e.algo.stat.arpack's Krylov-Schur iteration (through spectrapkg's eigs_sym_ks and eigs_gen_ks) against RSpectra's eigs_sym and eigs with the same start vector and Krylov size. tests/oracle/arpack.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R arpack`; the layout is at the top of scripts/r_oracle/groups/arpack.R.

use e.algo.stat.spectrapkg as sp
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

type Op = struct { x: []const f64, n: usize }

fn apply(c: *Op, x: []const f64, y: []f64) {
    var r = 0usize
    while r < c.n {
        var s = 0.0f64
        var q = 0usize
        while q < c.n {
            s += c.x[q * c.n + r] * x[q]
            q += 1usize
        }
        y[r] = s
        r += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let wh = usize(z[3usize])
    let ncv = usize(z[4usize])
    let part = usize(z[5usize])
    var op = Op { x: z[6usize + n..6usize + n + n * n], n: n }
    let v0 = z[6usize..6usize + n]
    let (re, e0) = mem.alloc[f64](a, k)
    let (im, e1) = mem.alloc[f64](a, k)
    let (vr, e2) = mem.alloc[f64](a, n * k)
    let (vi, e3) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var er = ok
    if kind == 0usize {
        er = sp.eigs_sym_ks[Op](a, &op, apply, n, k, wh, ncv, 1.0e-14f64, v0, re, vr)
        var i = 0usize
        while i < k {
            im[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n * k {
            vi[i] = 0.0f64
            i += 1usize
        }
    } else {
        er = sp.eigs_gen_ks[Op](a, &op, apply, n, k, wh, ncv, 1.0e-14f64, v0, re, im, vr, vi)
    }
    if er != ok { os.exit(5) }
    var s = 0.0f64
    var j = 0usize
    while j < k {
        if part < 2usize {
            var q = re[j]
            if part == 1usize { q = im[j] }
            s += q * f64(j + 1usize)
        } else {
            // the phase that makes the largest-modulus component real positive
            var best = 0.0f64
            var br = 1.0f64
            var bi = 0.0f64
            var i = 0usize
            while i < n {
                let md = math.sqrt[f64](vr[i * k + j] * vr[i * k + j] + vi[i * k + j] * vi[i * k + j])
                if md > best {
                    best = md
                    br = vr[i * k + j] / md
                    bi = 0.0f64 - vi[i * k + j] / md
                }
                i += 1usize
            }
            i = 0usize
            while i < n {
                let xr = vr[i * k + j] * br - vi[i * k + j] * bi
                let xi = vr[i * k + j] * bi + vi[i * k + j] * br
                var q = xr
                if part == 3usize { q = xi }
                s += q * f64(j * n + i + 1usize)
                i += 1usize
            }
        }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/arpack.json")
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
