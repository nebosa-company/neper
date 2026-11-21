// e.algo.stat.stlf against forecast::stlf. The layout is at the top of scripts/r_oracle/groups/stlf.R; consecutive cases of
// one series and setting share a fit.

use e.algo.stat.stlf as sf
use e.io
use e.mem
use e.math
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: []f64, res: sf.Stlf, have: bool, good: bool }

fn same_key(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let x = c.args
    let q = usize(x[0usize])
    let key = x[1usize..x.len]
    if !(cache.have && same_key(cache.key, key)) {
        cache.have = true
        cache.key = key
        let n = usize(key[2usize])
        let m = usize(key[1usize])
        let (r, good) = sf.stlf(a, key[4usize..4usize + n], m, 2usize * m, key[3usize], usize(key[0usize]))
        cache.res = r
        cache.good = good
    }
    if !cache.good { ret 0.0f64 / 0.0f64 }
    let r = &cache.res
    if q < 200usize { ret r.fitted[usize(x[3usize]) + 100usize - q] }
    if q < 300usize { ret r.mean[q - 201usize] }
    if q < 400usize { ret r.up80[q - 301usize] }
    if q < 500usize { ret r.lo80[q - 401usize] }
    if q < 600usize { ret r.up95[q - 501usize] }
    ret r.lo95[q - 601usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/stlf.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var cache: Cache = zero
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c, &cache)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 300usize {
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    var k = 0usize
                    while k < 5usize && k < c.args.len {
                        let _ = str.push(&b, " ")
                        let _ = str.push_f64(&b, c.args[k])
                        k += 1usize
                    }
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
