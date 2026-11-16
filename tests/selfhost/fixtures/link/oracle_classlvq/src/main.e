// e.algo.stat.classlvq against class: SOM, batchSOM, lvqinit and the LVQ family. tests/oracle/classlvq.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R classlvq`; the layouts are at the top of scripts/r_oracle/groups/classlvq.R.

use e.algo.rand.r as rng
use e.algo.stat.classlvq as lv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    if str.eq(c.name, "som") {
        let hex = z[1usize] == 1.0f64
        let xd = usize(z[2usize])
        let yd = usize(z[3usize])
        let kind = usize(z[4usize])
        let given = z[5usize] == 1.0f64
        let n = usize(z[6usize])
        let p = usize(z[7usize])
        let rlen = usize(z[8usize])
        let ng = xd * yd
        let data = z[9usize..9usize + n * p]
        var at = 9usize + n * p
        let (codes, e1) = mem.alloc[f64](a, ng * p)
        let (pts, e2) = mem.alloc[f64](a, ng * 2usize)
        let (nh, e3) = mem.alloc[f64](a, ng * ng)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        if given {
            var i = 0usize
            while i < ng * p {
                codes[i] = z[at + i]
                i += 1usize
            }
            at += ng * p
        } else {
            let (smp, se) = rng.sample_int(a, &g, i64(n), i64(ng), false)
            if se != ok { ret nan }
            var i = 0usize
            while i < ng {
                var j = 0usize
                while j < p {
                    codes[i * p + j] = data[(usize(smp[i]) - 1usize) * p + j]
                    j += 1usize
                }
                i += 1usize
            }
        }
        let alpha = z[at..at + rlen]
        let radii = z[at + rlen..at + 2usize * rlen]
        let q = usize(z[at + 2usize * rlen])
        lv.somgrid(xd, yd, hex, pts)
        lv.grid_dist(pts, ng, nh)
        if kind == 0usize { lv.som_online(&g, data, n, p, codes, ng, nh, alpha, radii) } else {
            if lv.batch_som(a, &g, data, n, p, codes, ng, nh, radii) != ok { ret nan }
        }
        var s = 0.0f64
        var i = 0usize
        while i < ng * p {
            if q == 0usize { s += codes[i] } else { s += f64(i + 1usize) * codes[i] }
            i += 1usize
        }
        ret s
    }
    let method = u8(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let nc = usize(z[4usize])
    let size = z[5usize]
    let k = usize(z[6usize])
    let niter = usize(z[7usize])
    let alpha = z[8usize]
    let win = z[9usize]
    let eps = z[10usize]
    let x = z[11usize..11usize + n * p]
    let (cl, e4) = mem.alloc[i64](a, n)
    let (sel, e5) = mem.alloc[usize](a, n)
    if e4 != ok || e5 != ok { ret nan }
    var i = 0usize
    while i < n {
        cl[i] = i64(z[11usize + n * p + i])
        i += 1usize
    }
    let q = usize(z[11usize + n * p + n])
    let (cnt, le) = lv.lvqinit(a, &g, x, n, p, cl, nc, size, k, sel)
    if le != ok { ret nan }
    let (xc, e6) = mem.alloc[f64](a, cnt * p)
    let (clc, e7) = mem.alloc[i64](a, cnt)
    if e6 != ok || e7 != ok { ret nan }
    i = 0usize
    while i < cnt {
        var j = 0usize
        while j < p {
            xc[i * p + j] = x[sel[i] * p + j]
            j += 1usize
        }
        clc[i] = cl[sel[i]]
        i += 1usize
    }
    if method > 0u8 {
        if lv.lvq_train(a, &g, method, x, n, p, cl, xc, clc, cnt, niter, alpha, win, eps) != ok { ret nan }
    }
    if q == 0usize { ret f64(cnt) }
    var s = 0.0f64
    if q == 3usize {
        i = 0usize
        while i < cnt {
            s += f64(clc[i])
            i += 1usize
        }
        ret s
    }
    i = 0usize
    while i < cnt * p {
        if q == 1usize { s += xc[i] } else { s += f64(i + 1usize) * xc[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/classlvq.json")
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
