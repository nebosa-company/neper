// e.algo.stat.fpc_boot against fpc::clusterboot. tests/oracle/fpc_boot.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_boot`; the layout of every case is at the top of scripts/r_oracle/groups/fpc_boot.R.

use e.algo.stat.fpc_boot as fb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let what = usize(z[0usize])
    let meth = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let distances = z[4usize] > 0.5f64
    let bcount = usize(z[5usize])
    let nmeth = usize(z[6usize])
    let methods = z[7usize..7usize + nmeth]
    let at = 7usize + nmeth
    let multipleboot = z[at] > 0.5f64
    let bscompare = z[at + 1usize] > 0.5f64
    let jt = z[at + 2usize]
    let nt1 = z[at + 3usize]
    let nt2 = z[at + 4usize]
    let subtuning = usize(z[at + 5usize])
    let cm = usize(z[at + 6usize])
    let cp = z[at + 7usize..at + 11usize]
    let noisemethod = z[at + 11usize] > 0.5f64
    let seedv = i64(z[at + 12usize])
    let dissolution = z[at + 13usize]
    let recover = z[at + 14usize]
    var dlen = n * p
    if distances { dlen = n * n }
    let data = z[at + 15usize..at + 15usize + dlen]
    let (res, e0) = mem.alloc[f64](a, 5usize * (2usize * n + 1usize) * bcount)
    if e0 != ok { os.exit(4) }
    let (nc, e1) = fb.clusterboot(a, data, n, p, distances, bcount, methods, multipleboot, bscompare, jt, nt1, nt2, subtuning, cm, cp, noisemethod, seedv, res)
    if e1 != ok { os.exit(5) }
    let base = (meth - 1usize) * nc * bcount
    var tot = 0.0f64
    if what == 0usize {
        var i = 0usize
        while i < nc * bcount {
            tot += f64(i + 1usize) * res[base + i]
            i += 1usize
        }
        ret tot
    }
    var j = 0usize
    while j < nc {
        var s = 0.0f64
        var brd = 0.0f64
        var rec = 0.0f64
        var i = 0usize
        while i < bcount {
            let v = res[base + j * bcount + i]
            s += v
            if v <= dissolution { brd += 1.0f64 }
            if v > recover { rec += 1.0f64 }
            i += 1usize
        }
        tot += f64(j + 1usize) * (s / f64(bcount) + 1000.0f64 * brd + 1000000.0f64 * rec)
        j += 1usize
    }
    ret tot
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_boot.json")
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
            if failures <= 10usize {
                var c2 = *c
                c2.args = c.args[0usize..7usize]
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
