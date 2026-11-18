// e.algo.stat.vcdeffect against vcd and effectsize. tests/oracle/vcdeffect.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vcdeffect`; the layout is at the top of
// scripts/r_oracle/groups/vcdeffect.R.

use e.algo.stat.vcdeffect as ve
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nm = c.name
    if str.eq(nm, "as") {
        let r = usize(z[0usize])
        let cc = usize(z[1usize])
        let (s, e) = ve.assocstats(a, z[2usize..2usize + r * cc], r, cc)
        if e != ok { ret nan }
        let q = usize(z[2usize + r * cc])
        if q == 0usize { ret s.lr }
        if q == 1usize { ret s.pearson }
        if q == 2usize { ret s.df }
        if q == 3usize { ret s.p_lr }
        if q == 4usize { ret s.p_pearson }
        if q == 5usize { ret s.phi }
        if q == 6usize { ret s.contingency }
        ret s.cramer
    }
    if str.eq(nm, "kp") {
        let k = usize(z[0usize])
        let (out, e) = mem.alloc[f64](a, 4usize)
        if e != ok { ret nan }
        if ve.kappa(a, z[2usize..2usize + k * k], k, u8(z[1usize]), out) != ok { ret nan }
        ret out[usize(z[2usize + k * k])]
    }
    if str.eq(nm, "rbsci") {
        let n1 = usize(z[0usize])
        let n2 = usize(z[1usize])
        var o: [2]f64 = zero
        ve.rbs_ci(z[2usize..2usize + n1], z[2usize + n1..2usize + n1 + n2], z[2usize + n1 + n2], o[0usize..2usize])
        ret o[usize(z[3usize + n1 + n2])]
    }
    if str.eq(nm, "smdci") {
        let n1 = usize(z[0usize])
        let n2 = usize(z[1usize])
        let x = z[2usize..2usize + n1]
        let y = z[2usize + n1..2usize + n1 + n2]
        var o: [6]f64 = zero
        ve.smd_ci(x, y, z[2usize + n1 + n2], o[0usize..6usize])
        ret o[usize(z[3usize + n1 + n2])]
    }
    if str.eq(nm, "smd") {
        let n1 = usize(z[0usize])
        let n2 = usize(z[1usize])
        let x = z[2usize..2usize + n1]
        let y = z[2usize + n1..2usize + n1 + n2]
        let q = usize(z[2usize + n1 + n2])
        if q == 3usize { ret ve.cliffs(x, y) }
        var o: [3]f64 = zero
        ve.smd(x, y, o[0usize..3usize])
        ret o[q]
    }
    let g = usize(z[0usize])
    let (sizes, e1) = mem.alloc[usize](a, g)
    if e1 != ok { ret nan }
    var n = 0usize
    var i = 0usize
    while i < g {
        sizes[i] = usize(z[1usize + i])
        n += sizes[i]
        i += 1usize
    }
    var o: [3]f64 = zero
    ve.anova_effects(z[1usize + g..1usize + g + n], sizes, o[0usize..3usize])
    if str.eq(nm, "aovci") {
        // args end (..., q: effect 0 eta2 1 omega2 2 epsilon2, level, 1 greater 0 two sided, side 0 low 1 high)
        let at = 1usize + g + n
        var ci: [2]f64 = zero
        ve.pve_ci(o[usize(z[at])], f64(g - 1usize), f64(n - g), z[at + 1usize], z[at + 2usize] > 0.5f64, ci[0usize..2usize])
        ret ci[usize(z[at + 3usize])]
    }
    ret o[usize(z[1usize + g + n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vcdeffect.json")
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
