// e.algo.stat.codapkg (heidel.diag, multivariate gelman.diag, crosscorr, multivariate autocorr, pcramer) against coda; layout at the top of scripts/r_oracle/groups/coda2.R.

use e.algo.stat.codapkg as cd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "pc") { ret cd.pcramer(x[0usize]) }
    if str.starts_with(c.name, "hw_") {
        let n = usize(x[0usize])
        var o: [6]f64 = zero
        if cd.heidel(a, x[1usize..1usize + n], x[1usize + n], 0.05f64, o[0usize..6usize]) != ok { os.exit(4) }
        if str.eq(c.name, "hw_stest") { ret o[0usize] }
        if str.eq(c.name, "hw_start") { ret o[1usize] }
        if str.eq(c.name, "hw_p") { ret o[2usize] }
        if str.eq(c.name, "hw_htest") { ret o[3usize] }
        if str.eq(c.name, "hw_mean") { ret o[4usize] }
        ret o[5usize]
    }
    if str.starts_with(c.name, "mp") {
        let nc = usize(x[0usize])
        let ni = usize(x[1usize])
        let nv = usize(x[2usize])
        if str.eq(c.name, "mp") { ret cd.gelman_mpsrf(a, x[3usize..3usize + nc * ni * nv], nc, ni, nv) }
        let (ch, e) = mem.alloc[f64](a, nc * ni)
        if e != ok { os.exit(5) }
        var k = 0usize
        while k < nc {
            var r = 0usize
            while r < ni {
                ch[k * ni + r] = x[3usize + k * ni * nv + r * nv]
                r += 1usize
            }
            k += 1usize
        }
        let (gp, gu) = cd.gelman_psrf(a, ch, nc, ni, 0.95f64)
        if str.eq(c.name, "mp_p") { ret gp }
        ret gu
    }
    let n = usize(x[0usize])
    let nv = usize(x[1usize])
    let d = x[2usize..2usize + n * nv]
    let u = usize(x[2usize + n * nv])
    let v = usize(x[3usize + n * nv])
    if str.eq(c.name, "cc") { ret cd.crosscorr(d, n, nv, u, v) }
    ret cd.acf_cross(d, n, nv, u, v, usize(x[4usize + n * nv]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coda2.json")
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
