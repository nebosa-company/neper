// e.algo.stat.emmeans' contrast coefficients against emmeans::*.emmc. tests/oracle/emmeanscontr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R emmeanscontr`; the layout is at the top of scripts/r_oracle/groups/emmeanscontr.R.

use e.algo.stat.emmeans as em
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let k = usize(z[1usize])
    if c.name.len == 7usize {
        let n = usize(z[2usize])
        let (o, e1) = mem.alloc[f64](a, 8usize * k * k)
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let mm = em.contrast_glm_oneway(a, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], n, k, kind, 1usize, o)
        if mm == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[8usize * usize(z[3usize + 2usize * n]) + usize(z[4usize + 2usize * n])]
    }
    if c.name.len == 8usize {
        let n = usize(z[2usize])
        let (o, e1) = mem.alloc[f64](a, 8usize * k * k)
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let mm = em.contrast_logit_oneway(a, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], n, k, kind, o)
        if mm == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[8usize * usize(z[3usize + 2usize * n]) + usize(z[4usize + 2usize * n])]
    }
    if c.name.len == 11usize {
        let n = usize(z[2usize])
        let nh = usize(z[3usize])
        let (o, e1) = mem.alloc[f64](a, 10usize * k * k)
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let mm = em.contrast_twoway_int(a, z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[4usize + 2usize * n..4usize + 3usize * n], n, k, nh, kind, o)
        if mm == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[10usize * usize(z[4usize + 3usize * n]) + usize(z[5usize + 3usize * n])]
    }
    if c.name.len == 12usize {
        let n = usize(z[2usize])
        let nh = usize(z[3usize])
        let (o, e1) = mem.alloc[f64](a, 10usize * k * k)
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let hd0 = 4usize + 2usize * n
        let mm = em.contrast_oneway(a, z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[hd0..hd0 + n * (nh - 1usize)], n, k, kind, o)
        if mm == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[10usize * usize(z[hd0 + n * (nh - 1usize)]) + usize(z[hd0 + n * (nh - 1usize) + 1usize])]
    }
    if c.name.len == 10usize {
        let n = usize(z[2usize])
        let (o, e1) = mem.alloc[f64](a, 10usize * k * k)
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let mm = em.contrast_oneway(a, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], z[3usize + 2usize * n..3usize + 3usize * n], n, k, kind, o)
        if mm == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[10usize * usize(z[3usize + 3usize * n]) + usize(z[4usize + 3usize * n])]
    }
    if c.name.len == 9usize {
        let n = usize(z[2usize])
        let (o, e1) = mem.alloc[f64](a, 10usize * k * k)
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let mm = em.contrast_oneway(a, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], z[0usize..0usize], n, k, kind, o)
        if mm == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[10usize * usize(z[3usize + 2usize * n]) + usize(z[4usize + 2usize * n])]
    }
    var out: [160]f64 = zero
    let mm = em.contrast_coefs(kind, k, out[0usize..160usize])
    if mm == 0usize { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[2usize]) * mm + usize(z[3usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/emmeanscontr.json")
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
