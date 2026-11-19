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
    var kind = 0u8
    if c.name[1usize] == 100u8 { kind = 1u8 }
    var aw = 1.0f64
    var bw = 1.0f64
    // the second letter picks the solver: q quantile, a asymmetric LS, e L1 with eps, h Huber, i SILF, o Lp; each carries (aw, bw) after the statistic
    let sc = c.name[1usize]
    if sc == 113u8 { kind = 2u8 }
    if sc == 97u8 { kind = 3u8 }
    if sc == 101u8 { kind = 4u8 }
    if sc == 104u8 { kind = 5u8 }
    if sc == 105u8 { kind = 6u8 }
    if sc == 111u8 { kind = 7u8 }
    if sc == 112u8 { kind = 8u8 }
    if sc == 99u8 { kind = 9u8 }
    if kind >= 2u8 {
        aw = z[2usize + 2usize * n + 2usize * m + 1usize]
        bw = z[2usize + 2usize * n + 2usize * m + 2usize]
    }
    if iso.active_set(a, y, w, p1, p2, kind, aw, bw, out) != ok { ret nan }
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
    if c.name.len == 4usize && c.name[3usize] == 108u8 {
        let svl = u8(z[0usize])
        let nl = usize(z[2usize])
        var tl = 0usize
        let (lens, le) = mem.alloc[usize](a, nl)
        if le != ok { ret nan }
        var q = 0usize
        while q < nl {
            lens[q] = usize(z[3usize + q])
            tl += lens[q]
            q += 1usize
        }
        let (ol, ole) = mem.alloc[f64](a, nl)
        if ole != ok { ret nan }
        let xl = z[3usize + nl..3usize + 2usize * nl]
        if iso.gpava_list(a, xl, z[3usize + 2usize * nl..3usize + 2usize * nl + tl], z[3usize + 2usize * nl + tl..3usize + 2usize * nl + 2usize * tl], lens, svl, z[1usize], ol) != ok { ret nan }
        let stl = usize(z[3usize + 2usize * nl + 2usize * tl])
        if stl == 0usize { ret f64(nl) }
        if stl == 3usize { ret ol[0usize] }
        if stl == 4usize { ret ol[nl - 1usize] }
        var sl = 0.0f64
        q = 0usize
        while q < nl {
            if stl == 1usize { sl += ol[q] } else { sl += f64(q + 1usize) * ol[q] }
            q += 1usize
        }
        ret sl
    }
    if c.name.len == 4usize && c.name[0usize] == 114u8 {
        let sv2 = u8(z[0usize])
        let n2 = usize(z[3usize])
        let k2 = usize(z[4usize])
        let (o2, oe) = mem.alloc[f64](a, n2)
        if oe != ok { ret nan }
        if iso.gpava_rows(a, z[5usize..5usize + n2], z[5usize + n2..5usize + n2 + n2 * k2], z[5usize + n2 + n2 * k2..5usize + n2 + 2usize * n2 * k2], n2, k2, sv2, z[1usize], u8(z[2usize]), o2) != ok { ret nan }
        let st2 = usize(z[5usize + n2 + 2usize * n2 * k2])
        if st2 == 0usize { ret f64(n2) }
        if st2 == 3usize { ret o2[0usize] }
        if st2 == 4usize { ret o2[n2 - 1usize] }
        var s2 = 0.0f64
        var i2 = 0usize
        while i2 < n2 {
            if st2 == 1usize { s2 += o2[i2] } else { s2 += f64(i2 + 1usize) * o2[i2] }
            i2 += 1usize
        }
        ret s2
    }
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
