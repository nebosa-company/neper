// e.algo.stat.factominepkg.hcpc against FactoMineR HCPC on a weighted PCA. tests/oracle/factominer_hcpc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factominer_hcpc`; the argument layout is at the top of scripts/r_oracle/groups/factominer_hcpc.R.

use e.algo.stat.factominepkg as fm
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let blk = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let ncp = usize(z[3usize])
    let scale = z[4usize] != 0.0f64
    let nb0 = usize(z[5usize])
    let consol = z[6usize] != 0.0f64
    let minc = usize(z[7usize])
    let maxc = usize(z[8usize])
    let rw = z[9usize..9usize + n]
    let x = z[9usize + n..9usize + n + n * p]
    let nd = fm.pca_axes(n, p, ncp)
    let (cw, e0) = mem.alloc[f64](a, p)
    let (pout, e1) = mem.alloc[f64](a, fm.pca_len(n, p, nd, 0usize, 0usize))
    let (out, e2) = mem.alloc[f64](a, 8usize * n + 2usize * n * nd + 64usize)
    if e0 != ok || e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < p {
        cw[i] = 1.0f64
        i += 1usize
    }
    let xs0 = x[0usize..0usize]
    if fm.pca(a, x, n, p, rw, cw, scale, ncp, xs0, 0usize, xs0, 0usize, pout) != ok { ret nan }
    let coord = pout[2usize * nd + 4usize * p * nd..2usize * nd + 4usize * p * nd + n * nd]
    if fm.hcpc(a, coord, n, nd, rw, nb0, consol, minc, maxc, 10usize, out) != ok { ret nan }
    let nb = usize(out[0usize])
    let nq = usize(out[1usize])
    let m = n - 1usize
    let o_perm = 2usize
    let o_ma = o_perm + n
    let o_mb = o_ma + m
    let o_ht = o_mb + m
    let o_ord = o_ht + m
    let o_cl = o_ord + n
    let o_ce = o_cl + n
    let o_q = o_ce + nb * nd
    if blk == 0usize { ret f64(nb) }
    if blk == 1usize { ret weighted(out, o_cl, n) }
    if blk == 2usize { ret weighted(out, o_ht, m) }
    if blk == 3usize { ret weighted(out, o_ma, m) }
    if blk == 4usize { ret weighted(out, o_mb, m) }
    if blk == 5usize { ret weighted(out, o_ord, n) }
    if blk == 6usize { ret weighted(out, o_ce, nb * nd) }
    if blk == 7usize { ret weighted(out, o_q, nq) }
    if blk == 8usize { ret weighted(out, o_q + nq, m) }
    ret weighted(out, o_perm, n)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factominer_hcpc.json")
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
                    let _ = str.push(&b, " blk ")
                    let _ = str.push_f64(&b, c.args[0usize])
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
