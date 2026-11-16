// e.algo.rand.dqrng against dqrng: dqrunif of the xoroshiro128 and xoshiro256 generators after
// dqset.seed. tests/oracle/dqrng.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// dqrng`; the layout is at the top of scripts/r_oracle/groups/dqrng.R.

use e.algo.rand.dqrng as dq
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case, z: *const dq.Zig) -> f64 {
    let x = c.args
    if str.eq(c.name, "dqstate") {
        var g = dq.seed(u8(x[0usize]), u64(x[1usize]))
        var i = 0usize
        while i < usize(x[2usize]) {
            let _ = dq.unif(&g, 0.0f64, 1.0f64)
            i += 1usize
        }
        let (d, e) = dq.get_state(a, &g, usize(x[3usize]))
        if e != ok { ret 0.0f64 / 0.0f64 }
        if x[4usize] == 0.0f64 { ret f64(d.len) }
        var s = 0usize
        i = 0usize
        while i < d.len {
            s += usize(d[i]) - 48usize
            i += 1usize
        }
        ret f64(s)
    }
    if str.eq(c.name, "dqstream") {
        var g = dq.seed_stream(u8(x[0usize]), u64(x[1usize]), u64(x[2usize]))
        let n = usize(x[3usize])
        var v = 0.0f64
        var i = 0usize
        while i <= n {
            v = dq.unif(&g, 0.0f64, 1.0f64)
            i += 1usize
        }
        ret v
    }
    if str.eq(c.name, "dqsample") {
        var g = dq.seed(u8(x[0usize]), u64(x[1usize]))
        let (v, e) = dq.sample_int(a, &g, u32(x[2usize]), usize(x[3usize]), x[4usize] == 1.0f64)
        if e != ok { ret 0.0f64 / 0.0f64 }
        let pick = i64(x[5usize])
        if pick >= 0i64 { ret f64(v[usize(pick)]) }
        var s = 0.0f64
        var w = 0.0f64
        var i = 0usize
        while i < v.len {
            s += f64(v[i])
            w += f64(i + 1usize) * f64(v[i])
            i += 1usize
        }
        if pick == 0i64 - 1i64 { ret s }
        ret w
    }
    if str.eq(c.name, "dqrnorm") || str.eq(c.name, "dqrexp") {
        var g = dq.seed(u8(x[0usize]), u64(x[1usize]))
        let norm = str.eq(c.name, "dqrnorm")
        let pick = i64(x[4usize])
        var sum = 0.0f64
        var hi = 0.0f64 - 1.0e308f64
        var lo = 1.0e308f64
        var v = 0.0f64
        var i = 0i64
        while i < 1000i64 {
            if norm { v = dq.rnorm(&g, z, x[2usize], x[3usize]) } else { v = dq.rexp(&g, z, x[2usize]) }
            sum += v
            if v > hi { hi = v }
            if v < lo { lo = v }
            if i == pick { ret v }
            i += 1i64
        }
        if pick == 0i64 - 1i64 { ret sum }
        if pick == 0i64 - 2i64 { ret hi }
        ret lo
    }
    var g = dq.seed(u8(x[0usize]), u64(x[1usize]))
    let n = usize(x[4usize])
    var v = 0.0f64
    var i = 0usize
    while i <= n {
        v = dq.unif(&g, x[2usize], x[3usize])
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dqrng.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var zg: dq.Zig = zero
    dq.zig_init(&zg)
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let start = mem.mark(a)
        let got = answer(a, c, &zg)
        mem.reset(a, start)
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
