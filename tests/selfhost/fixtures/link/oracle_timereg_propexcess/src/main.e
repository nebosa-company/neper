// e.algo.stat.timeregpkg.prop_excess against timereg prop.excess. tests/oracle/timereg_propexcess.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R timereg_propexcess`; the case layout is at the top of scripts/r_oracle/groups/timereg_propexcess.R.

use e.algo.stat.timeregpkg as tr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let q = usize(z[2usize])
    let j = usize(c.name[1usize] - 48u8) * 10usize + usize(c.name[2usize] - 48u8)
    let (out, e1) = mem.alloc[f64](a, 2usize * n * (p + 2usize) + 12usize * (p + 1usize) + 4usize * q * q + 2usize * q + 16usize)
    let (lens, e2) = mem.alloc[usize](a, 12usize)
    if e1 != ok || e2 != ok { ret nan }
    let y0 = 7usize
    let x0 = y0 + 2usize * n
    let z0 = x0 + n * p
    let e0 = z0 + n * q
    let b0 = e0 + n
    let e = tr.prop_excess(a, z[y0..y0 + n], z[y0 + n..y0 + 2usize * n], z[x0..x0 + n * p], z[z0..z0 + n * q], z[e0..e0 + n], n, p, q, z[b0..b0 + q], z[5usize], z[6usize], usize(z[3usize]), i64(z[4usize]), out, lens)
    if e != ok { ret nan }
    var at = 0usize
    var s = 0usize
    while s < j {
        at += lens[s]
        s += 1usize
    }
    var sum = 0.0f64
    var i = 0usize
    while i < lens[j] {
        sum += out[at + i] * f64(i + 1usize)
        i += 1usize
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/timereg_propexcess.json")
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
