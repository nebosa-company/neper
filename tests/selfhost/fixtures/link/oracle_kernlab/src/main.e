// e.algo.stat.kernlabpkg against kernlab kernelMatrix and kpca. tests/oracle/kernlab.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlab`; the layout is at the top of scripts/r_oracle/groups/kernlab.R.

use e.algo.stat.kernlabpkg as kl
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kind = usize(z[2usize])
    let k = usize(z[6usize])
    let x = z[7usize..7usize + n * p]
    let (km, e1) = mem.alloc[f64](a, n * n)
    let (eg, e2) = mem.alloc[f64](a, k)
    let (pv, e3) = mem.alloc[f64](a, n * k)
    let (rt, e4) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var par1 = z[3usize]
    var par2 = z[4usize]
    var par3 = z[5usize]
    if kind == 1usize {
        // polydot(degree = par2, scale = par1, offset = par3): kernel(1) takes degree first
        let t = par1
        par1 = par2
        par2 = t
    }
    if kind == 3usize {
        par1 = z[3usize] * 0.3f64
        par2 = z[5usize] - 0.5f64
    }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "kmat") {
        kl.kernel_matrix(kind, x, n, p, par1, par2, par3, km)
        while i < n * n {
            s += km[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    kl.kernel_matrix(0usize, x, n, p, z[3usize], 0.0f64, 0.0f64, km)
    if kl.kpca(a, km, n, k, eg, pv, rt) != ok { ret nan }
    if str.eq(c.name, "eig") {
        while i < k {
            s += eg[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    var src = pv
    if str.eq(c.name, "rotated") { src = rt }
    while i < n * k {
        s += math.abs[f64](src[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlab.json")
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
