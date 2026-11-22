// e.algo.stat.factominepkg against FactoMineR PCA and CA. tests/oracle/factominer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factominer`; the argument layout is at the top of scripts/r_oracle/groups/factominer.R.

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

// start of block b within lens (running sum)
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
    let blk = usize(z[1usize])
    let (out, e1) = mem.alloc[f64](a, 1usize << 16usize)
    let (lens, e2) = mem.alloc[usize](a, 16usize)
    if e1 != ok || e2 != ok { ret nan }
    if usize(z[0usize]) == 0usize {
        let n = usize(z[2usize])
        let p = usize(z[3usize])
        let ncp = usize(z[4usize])
        let scale = z[5usize] != 0.0f64
        let ns = usize(z[6usize])
        let nq = usize(z[7usize])
        let rw = z[8usize..8usize + n]
        let cw = z[8usize + n..8usize + n + p]
        let x0 = 8usize + n + p
        let x = z[x0..x0 + n * p]
        let xs = z[x0 + n * p..x0 + n * p + ns * p]
        let q0 = x0 + n * p + ns * p
        let q = z[q0..q0 + n * nq]
        if fm.pca(a, x, n, p, rw, cw, scale, ncp, xs, ns, q, nq, out) != ok { ret nan }
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
        lens[13usize] = nq * nd
        lens[14usize] = nq * nd
        lens[15usize] = nq * nd
        ret weighted(out, block_start(lens, blk), lens[blk])
    }
    let nr = usize(z[2usize])
    let nc = usize(z[3usize])
    let ncp = usize(z[4usize])
    let nrs = usize(z[5usize])
    let ncs = usize(z[6usize])
    let rw = z[7usize..7usize + nr]
    let t0 = 7usize + nr
    let tb = z[t0..t0 + nr * nc]
    let rs = z[t0 + nr * nc..t0 + nr * nc + nrs * nc]
    let c0 = t0 + nr * nc + nrs * nc
    let cs = z[c0..c0 + nr * ncs]
    if fm.ca(a, tb, nr, nc, rw, ncp, rs, nrs, cs, ncs, out) != ok { ret nan }
    let nd = fm.ca_axes(nr, nc, ncp)
    lens[0usize] = nd
    lens[1usize] = nd
    lens[2usize] = nr * nd
    lens[3usize] = nr * nd
    lens[4usize] = nr * nd
    lens[5usize] = nr
    lens[6usize] = nc * nd
    lens[7usize] = nc * nd
    lens[8usize] = nc * nd
    lens[9usize] = nc
    lens[10usize] = nrs * nd
    lens[11usize] = nrs * nd
    lens[12usize] = ncs * nd
    lens[13usize] = ncs * nd
    ret weighted(out, block_start(lens, blk), lens[blk])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factominer.json")
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
            if failures <= 60usize {
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
