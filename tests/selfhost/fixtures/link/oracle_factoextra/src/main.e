// e.algo.stat.factoextrapkg against factoextra (get_eigenvalue, get_pca_var, get_pca_ind, hcut, fviz_nbclust over hcut) and NbClust.
// tests/oracle/factoextra.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factoextra`; the argument layout is at the top of scripts/r_oracle/groups/factoextra.R.

use e.algo.stat.factominepkg as fm
use e.algo.stat.factoextrapkg as fx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn weighted(src: []const f64, lo: usize, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += src[lo + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn kind_pca(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let blk = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let scale = z[4usize] != 0.0f64
    let x = z[5usize..5usize + n * p]
    let nd = fm.pca_axes(n, p, p)
    let (cw, e0) = mem.alloc[f64](a, p)
    let (rw, e1) = mem.alloc[f64](a, n)
    let (pout, e2) = mem.alloc[f64](a, fm.pca_len(n, p, nd, 0usize, 0usize))
    let (ge, e3) = mem.alloc[f64](a, 3usize * nd)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < p {
        cw[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        rw[i] = 1.0f64
        i += 1usize
    }
    let xs0 = x[0usize..0usize]
    if fm.pca(a, x, n, p, rw, cw, scale, p, xs0, 0usize, xs0, 0usize, pout) != ok { ret nan }
    if blk == 0usize {
        fx.get_eigenvalue(pout[0usize..nd], pout[nd..2usize * nd], nd, ge)
        // R returns a matrix with one row per component: rows by 3, read row-major
        var s = 0.0f64
        i = 0usize
        while i < nd {
            s += ge[i] * f64(3usize * i + 1usize)
            s += ge[nd + i] * f64(3usize * i + 2usize)
            s += ge[2usize * nd + i] * f64(3usize * i + 3usize)
            i += 1usize
        }
        ret s
    }
    if blk <= 4usize { ret weighted(pout, 2usize * nd + (blk - 1usize) * p * nd, p * nd) }
    ret weighted(pout, 2usize * nd + 4usize * p * nd + (blk - 5usize) * n * nd, n * nd)
}

fn kind_hcut(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let blk = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let k = usize(z[4usize])
    let method = usize(z[5usize])
    let metric = usize(z[6usize])
    let stand = z[7usize] != 0.0f64
    let x = z[8usize..8usize + n * p]
    let (out, e1) = mem.alloc[f64](a, 8usize * n + 2usize * k + 64usize)
    if e1 != ok { ret nan }
    if fx.hcut(a, x, n, p, k, method, metric, stand, out) != ok { ret nan }
    let m = n - 1usize
    let o_size = n
    let o_si = o_size + k
    let o_nb = o_si + n
    let o_cav = o_nb + n
    let o_avg = o_cav + k
    let o_ma = o_avg + 1usize
    let o_mb = o_ma + m
    let o_ht = o_mb + m
    let o_ord = o_ht + m
    if blk == 0usize { ret weighted(out, 0usize, n) }
    if blk == 1usize { ret weighted(out, o_size, k) }
    if blk == 2usize { ret weighted(out, o_si, n) }
    if blk == 3usize { ret weighted(out, o_nb, n) }
    if blk == 4usize { ret weighted(out, o_cav, k) }
    if blk == 5usize { ret out[o_avg] }
    if blk == 6usize { ret weighted(out, o_ma, m) }
    if blk == 7usize { ret weighted(out, o_mb, m) }
    if blk == 8usize { ret weighted(out, o_ht, m) }
    ret weighted(out, o_ord, n)
}

fn kind_curve(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let blk = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let kmax = usize(z[4usize])
    let method = usize(z[5usize])
    let x = z[6usize..6usize + n * p]
    let (d, e1) = mem.alloc[f64](a, n * n)
    let (out, e2) = mem.alloc[f64](a, 2usize * kmax)
    if e1 != ok || e2 != ok { ret nan }
    if fx.get_dist(a, x, n, p, 0usize, d) != ok { ret nan }
    if fx.nbclust_curves(a, d, n, kmax, method, out) != ok { ret nan }
    if blk == 0usize { ret weighted(out, 0usize, kmax) }
    ret weighted(out, kmax + 1usize, kmax - 1usize)
}

fn kind_nbclust(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let blk = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let method = usize(z[4usize])
    let metric = usize(z[5usize])
    let minc = usize(z[6usize])
    let maxc = usize(z[7usize])
    let x = z[8usize..8usize + n * p]
    let rows = maxc - minc + 1usize
    let (out, e1) = mem.alloc[f64](a, rows * 34usize + 30usize)
    if e1 != ok { ret nan }
    if fx.nbclust(a, x, n, p, method, metric, minc, maxc, out) != ok { ret nan }
    if blk >= 100usize { ret out[rows * 30usize + blk - 100usize] }
    var s = 0.0f64
    var r = 0usize
    while r < rows {
        s += out[r * 30usize + blk] * f64(r + 1usize)
        r += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    if kind == 0usize { ret kind_pca(a, z) }
    if kind == 1usize { ret kind_hcut(a, z) }
    if kind == 2usize { ret kind_curve(a, z) }
    ret kind_nbclust(a, z)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factoextra.json")
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
            if failures <= 40usize {
                let (b0, be) = str.builder(a, 160usize)
                var b = b0
                if be == ok {
                    let _ = str.push(&b, "case ")
                    let _ = str.push_f64(&b, f64(at))
                    let _ = str.push(&b, " kind ")
                    let _ = str.push_f64(&b, c.args[0usize])
                    let _ = str.push(&b, " blk ")
                    let _ = str.push_f64(&b, c.args[1usize])
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
