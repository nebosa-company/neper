// e.algo.stat.isotone.gpava against isotone::gpava for a vector response. tests/oracle/isotone.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R isotone`; the layout is at the top of
// scripts/r_oracle/groups/isotone.R.

use e.algo.stat.isotone as iso
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn active(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let y = z[2usize..2usize + n]
    let w = z[2usize + n..2usize + 2usize * n]
    let (p1, e1) = mem.alloc[usize](a, m)
    if e1 != ok { ret nan }
    let (p2, e2) = mem.alloc[usize](a, m)
    if e2 != ok { ret nan }
    var i = 0usize
    while i < m {
        p2[i] = usize(z[2usize + 2usize * n + i]) - 1usize
        p1[i] = usize(z[2usize + 2usize * n + m + i]) - 1usize
        i += 1usize
    }
    let st = usize(z[2usize + 2usize * n + 2usize * m])
    let (out, e3) = mem.alloc[f64](a, n + m + 2usize)
    if e3 != ok { ret nan }
    if iso.active_set(a, y, w, p1, p2, out) != ok { ret nan }
    if st == 0usize { ret out[n + m] }
    if st == 1usize { ret out[n + m + 1usize] }
    var s = 0.0f64
    i = 0usize
    while i < n && st == 2usize {
        s += f64(i + 1usize) * out[i]
        i += 1usize
    }
    i = 0usize
    while i < m && st == 3usize {
        s += f64(i + 1usize) * out[n + i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if c.name.len == 2usize { ret active(a, c) }
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let sv = u8(z[0usize])
    let p = z[1usize]
    let ties = u8(z[2usize])
    let n = usize(z[3usize])
    let x = z[4usize..4usize + n]
    let y = z[4usize + n..4usize + 2usize * n]
    let w = z[4usize + 2usize * n..4usize + 3usize * n]
    let st = usize(z[4usize + 3usize * n])
    let (out, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan }
    if iso.gpava(a, x, y, w, sv, p, ties, out) != ok { ret nan }
    if st == 0usize { ret f64(n) }
    if st == 3usize { ret out[0usize] }
    if st == 4usize { ret out[n - 1usize] }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if st == 1usize { s += out[i] } else { s += f64(i + 1usize) * out[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/isotone.json")
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
