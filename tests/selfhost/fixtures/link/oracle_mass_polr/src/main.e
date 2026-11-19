// e.algo.stat.masspolr against MASS polr. tests/oracle/mass_polr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_polr`; the layout is at the top of scripts/r_oracle/groups/mass_polr.R.

use e.algo.stat.masspolr as mp
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
    let n = usize(z[0usize])
    let pc = usize(z[1usize])
    let lv = usize(z[2usize])
    let method = usize(z[3usize])
    let has_w = z[4usize] != 0.0f64
    let has_off = z[5usize] != 0.0f64
    let use_start = z[6usize] != 0.0f64
    let mode = usize(z[7usize])
    let y = z[8usize..8usize + n]
    let x = z[8usize + n..8usize + n + n * pc]
    var at = 8usize + n + n * pc
    let (w, e1) = mem.alloc[f64](a, n)
    let (off, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        off[i] = 0.0f64
        i += 1usize
    }
    if has_w {
        i = 0usize
        while i < n {
            w[i] = z[at + i]
            i += 1usize
        }
        at += n
    }
    if has_off {
        i = 0usize
        while i < n {
            off[i] = z[at + i]
            i += 1usize
        }
        at += n
    }
    var st = z[0usize..0usize]
    if use_start { st = z[at..at + pc + lv - 1usize] }
    let (r, e) = mp.polr(a, x, n, pc, y, lv, w, off, method, use_start, st, true)
    if e != ok { ret nan() }
    if mode == 0usize { ret wsum(r.beta) }
    if mode == 1usize { ret wsum(r.zeta) }
    if mode == 2usize { ret r.deviance }
    if mode == 3usize {
        var s = 0.0f64
        i = 0usize
        while i < n {
            var k = 0usize
            while k < lv {
                s += f64(i * lv + k + 1usize) * r.fitted[i + n * k]
                k += 1usize
            }
            i += 1usize
        }
        ret s
    }
    if mode == 4usize { ret wsum(r.hess) }
    var lp = 0.0f64
    i = 0usize
    while i < n {
        var eta = off[i]
        var j = 0usize
        while j < pc {
            eta += x[i + n * j] * r.beta[j]
            j += 1usize
        }
        lp += f64(i + 1usize) * eta
        i += 1usize
    }
    ret lp
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_polr.json")
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
