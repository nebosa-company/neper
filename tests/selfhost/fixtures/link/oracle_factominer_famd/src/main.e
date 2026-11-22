// e.algo.stat.factominepkg.famd against FactoMineR FAMD. tests/oracle/factominer_famd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factominer_famd`; the argument layout is at the top of scripts/r_oracle/groups/factominer_famd.R.

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
    let pq = usize(z[3usize])
    let jf = usize(z[4usize])
    let ncp = usize(z[5usize])
    let rw = z[6usize..6usize + n]
    let l0 = 6usize + n
    let lev = z[l0..l0 + jf]
    let x0 = l0 + jf
    let x = z[x0..x0 + (n + ns) * pq]
    let c0 = x0 + (n + ns) * pq
    let codes = z[c0..c0 + (n + ns) * jf]
    let (out, e1) = mem.alloc[f64](a, 1usize << 17usize)
    let (lens, e2) = mem.alloc[usize](a, 24usize)
    if e1 != ok || e2 != ok { ret nan }
    if fm.famd(a, x, codes, n, ns, pq, jf, lev, rw, ncp, out) != ok { ret nan }
    var k = 0usize
    var v = 0usize
    while v < jf {
        k += usize(lev[v])
        v += 1usize
    }
    let p = pq + k
    let nd = fm.pca_axes(n, p, ncp)
    lens[0usize] = nd
    lens[1usize] = nd
    lens[2usize] = p * nd
    lens[3usize] = p * nd
    lens[4usize] = p * nd
    lens[5usize] = p * nd
    lens[6usize] = n * nd
    lens[7usize] = n * nd
    lens[8usize] = n * nd
    lens[9usize] = n
    lens[10usize] = ns * nd
    lens[11usize] = ns * nd
    lens[12usize] = ns
    lens[13usize] = k * nd
    lens[14usize] = k * nd
    lens[15usize] = k * nd
    lens[16usize] = (pq + jf) * nd
    lens[17usize] = (pq + jf) * nd
    lens[18usize] = (pq + jf) * nd
    if blk == 20usize { ret weighted(out, block_start(lens, 2usize), pq * nd) }
    if blk == 21usize { ret weighted(out, block_start(lens, 4usize), pq * nd) }
    if blk == 22usize { ret weighted(out, block_start(lens, 5usize), pq * nd) }
    if blk == 23usize { ret weighted(out, block_start(lens, 5usize) + pq * nd, k * nd) }
    ret weighted(out, block_start(lens, blk), lens[blk])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factominer_famd.json")
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
