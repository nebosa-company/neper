// e.algo.stat.fpc against fpc's cluster.stats. tests/oracle/fpc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc`; the layout is at the top of scripts/r_oracle/groups/fpc.R.

use e.algo.stat.fpc as fp
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if c.name.len == 2usize && c.name[0usize] == 118u8 && c.name[1usize] == 119u8 {
        let vn = usize(x[0usize])
        let vncl = usize(x[1usize])
        let vcats = usize(x[2usize])
        let (vcl, ve1) = mem.alloc[usize](a, vn)
        let (vo, ve2) = mem.alloc[f64](a, vncl * vcats)
        if ve1 != ok || ve2 != ok { os.exit(15) }
        var vi = 0usize
        while vi < vn {
            vcl[vi] = usize(x[3usize + vi])
            vi += 1usize
        }
        if fp.varwise_counts(a, x[3usize + vn..3usize + 2usize * vn], vcl, vncl, vcats, vo) != ok { os.exit(16) }
        ret vo[usize(x[3usize + 2usize * vn])]
    }
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    let k2 = usize(x[3usize])
    let (cl, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(5) }
    let (cl2, e2) = mem.alloc[usize](a, n)
    if e2 != ok { os.exit(6) }
    let (d, e3) = mem.alloc[f64](a, n * n)
    if e3 != ok { os.exit(7) }
    var i = 0usize
    while i < n {
        cl[i] = usize(x[4usize + i])
        cl2[i] = usize(x[4usize + n + i])
        i += 1usize
    }
    let at = 4usize + 2usize * n
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[at + 2usize * i] - x[at + 2usize * j]
            let dy = x[at + 1usize + 2usize * i] - x[at + 1usize + 2usize * j]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    if kind >= 16usize { ret fp.compare(a, cl, k, cl2, k2, kind) }
    ret fp.stat(a, d, n, cl, k, kind)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc.json")
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
