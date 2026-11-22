// e.algo.stat.factominepkg.condes against FactoMineR dimdesc. tests/oracle/factominer_dimdesc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factominer_dimdesc`; the argument layout is at the top of scripts/r_oracle/groups/factominer_dimdesc.R.

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
    let nq = usize(z[2usize])
    let jf = usize(z[3usize])
    let rw = z[4usize..4usize + n]
    let l0 = 4usize + n
    let lev = z[l0..l0 + jf]
    let y0 = l0 + jf
    let y = z[y0..y0 + n]
    let x = z[y0 + n..y0 + n + n * nq]
    let c0 = y0 + n + n * nq
    let codes = z[c0..c0 + n * jf]
    let (out, e1) = mem.alloc[f64](a, 4096usize)
    if e1 != ok { ret nan }
    if fm.condes(a, y, rw, x, n, nq, codes, jf, lev, out) != ok { ret nan }
    var k = 0usize
    var v = 0usize
    while v < jf {
        k += usize(lev[v])
        v += 1usize
    }
    if blk == 0usize { ret weighted(out, 0usize, nq) }
    if blk == 1usize { ret weighted(out, nq, nq) }
    if blk == 2usize { ret weighted(out, 2usize * nq, jf) }
    if blk == 3usize { ret weighted(out, 2usize * nq + jf, jf) }
    if blk == 4usize { ret weighted(out, 2usize * nq + 2usize * jf, k) }
    ret weighted(out, 2usize * nq + 2usize * jf + k, k)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factominer_dimdesc.json")
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
