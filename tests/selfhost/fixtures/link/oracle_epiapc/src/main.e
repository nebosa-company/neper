// e.algo.stat.epiapc against Epi::apc.fit (model = "factor", Poisson). tests/oracle/epiapc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R epiapc`; the argument layout is at the top of scripts/r_oracle/groups/epiapc.R.

use e.algo.stat.epiapc as ea
use e.mem
use e.io
use e.os
use e.test.oracle as oracle

fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let b = 1usize + 4usize * n
    let (out, e) = mem.alloc[f64](ar, 8usize * n + 400usize)
    if e != ok { os.exit(4) }
    let er = ea.apc_fit(ar, x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n], x[1usize + 2usize * n..1usize + 3usize * n], x[1usize + 3usize * n..b], n, usize(x[b]), usize(x[b + 1usize]), x[b + 2usize], x[b + 3usize] > 0.5f64, x[b + 4usize], x[b + 5usize] > 0.5f64, x[b + 6usize], x[b + 7usize], x[b + 8usize], usize(x[b + 9usize]), usize(x[b + 10usize]), usize(x[b + 11usize]), usize(x[b + 12usize]), out)
    if er != ok { os.exit(5) }
    let kind = usize(x[b + 13usize])
    let i = usize(x[b + 14usize])
    let j = usize(x[b + 15usize])
    let na = usize(out[2usize])
    let np = usize(out[3usize])
    let nc = usize(out[4usize])
    let nd = usize(out[5usize])
    let oa = 6usize
    let op = oa + 4usize * na
    let oc = op + 4usize * np
    let od = oc + 4usize * nc
    let om = od + 3usize * nd
    if kind == 0usize { ret out[oa + 4usize * i + j] }
    if kind == 1usize { ret out[op + 4usize * i + j] }
    if kind == 2usize { ret out[oc + 4usize * i + j] }
    if kind == 3usize { ret out[od + 3usize * i + j] }
    if kind == 4usize { ret out[om + 5usize * i + j] }
    var s = 0.0f64
    var r = 0usize
    if kind == 5usize {
        while r < na {
            s += out[oa + 4usize * r + j]
            r += 1usize
        }
        ret s
    }
    if kind == 6usize {
        while r < np {
            s += out[op + 4usize * r + j]
            r += 1usize
        }
        ret s
    }
    if kind == 7usize {
        while r < nc {
            s += out[oc + 4usize * r + j]
            r += 1usize
        }
        ret s
    }
    if kind == 8usize {
        r = 1usize
        while r < 6usize {
            s += out[om + 5usize * r + j]
            r += 1usize
        }
        ret s
    }
    ret out[j]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/epiapc.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
