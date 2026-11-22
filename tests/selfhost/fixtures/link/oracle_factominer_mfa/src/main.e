// e.algo.stat.factominepkg.mfa against FactoMineR MFA. tests/oracle/factominer_mfa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factominer_mfa`; the argument layout is at the top of scripts/r_oracle/groups/factominer_mfa.R.

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

fn block_start(lens: []const usize, b: usize) -> usize {
    var s = 0usize
    var i = 0usize
    while i < b {
        s += lens[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let blk = usize(z[0usize])
    let n = usize(z[1usize])
    let ns = usize(z[2usize])
    let pp = usize(z[3usize])
    let ng = usize(z[4usize])
    let ncp = usize(z[5usize])
    let rw = z[6usize..6usize + n]
    let g0 = 6usize + n
    let gsz = z[g0..g0 + ng]
    let gty = z[g0 + ng..g0 + 2usize * ng]
    let x0 = g0 + 2usize * ng
    let x = z[x0..x0 + n * pp]
    let xs = z[x0 + n * pp..x0 + n * pp + ns * pp]
    let (out, e1) = mem.alloc[f64](a, 1usize << 17usize)
    let (lens, e2) = mem.alloc[usize](a, 24usize)
    if e1 != ok || e2 != ok { ret nan }
    if fm.mfa(a, x, xs, n, ns, gsz, gty, ng, rw, ncp, out) != ok { ret nan }
    let nd = fm.pca_axes(n, pp, ncp)
    let ng1 = ng + 1usize
    lens[0usize] = nd
    lens[1usize] = nd
    lens[2usize] = pp * nd
    lens[3usize] = pp * nd
    lens[4usize] = pp * nd
    lens[5usize] = pp * nd
    lens[6usize] = n * nd
    lens[7usize] = n * nd
    lens[8usize] = n * nd
    lens[9usize] = n
    lens[10usize] = ns * nd
    lens[11usize] = ns * nd
    lens[12usize] = ns
    lens[13usize] = ng1 * ng1
    lens[14usize] = ng1 * ng1
    lens[15usize] = ng * nd
    lens[16usize] = ng * nd
    lens[17usize] = ng * nd
    lens[18usize] = ng
    lens[19usize] = ng * nd
    ret weighted(out, block_start(lens, blk), lens[blk])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factominer_mfa.json")
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
