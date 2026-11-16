// e.algo.stat.tsp against the TSP package. tests/oracle/tsp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsp`; the layout is at the top of scripts/r_oracle/groups/tsp.R.

use e.algo.rand.r as rng
use e.algo.stat.tsp as tsp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn checksum(t: []const usize, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += f64(i + 1usize) * f64(t[i] + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let q = usize(z[1usize])
    let seed = i64(z[2usize])
    let n = usize(z[3usize])
    let p = usize(z[4usize])
    let m = z[5usize..5usize + n * n]
    let (tour, e1) = mem.alloc[usize](a, n)
    let (path, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    if kind == 0usize { tsp.nn(a, &g, m, n, p - 1usize, tour) }
    if kind == 1usize { tsp.repetitive_nn(a, &g, m, n, tour) }
    if kind == 2usize {
        // the package builds its defaults first, which draws the start city
        let (st, se) = rng.sample_int(a, &g, i64(n), 1i64, false)
        if se != ok { ret nan }
        tsp.insertion(a, &g, m, n, u8(p), usize(seed) % n, false, tour)
    }
    if kind == 3usize {
        let (perm, pe) = rng.sample_int(a, &g, i64(n), i64(n), false)
        if pe != ok { ret nan }
        var i = 0usize
        while i < n {
            tour[i] = usize(perm[i] - 1i64)
            i += 1usize
        }
        tsp.two_opt(m, n, tour)
    }
    if kind == 4usize {
        let (out, oe) = mem.alloc[f64](a, 4usize * n * n)
        if oe != ok { ret nan }
        tsp.atsp_to_tsp(m, n, 500.0f64, -500.0f64, out)
        var s = 0.0f64
        var i = 0usize
        while i < 2usize * n {
            var j = 0usize
            while j < 2usize * n {
                if q == 0usize { s += out[i * 2usize * n + j] } else { s += f64(i + 1usize) * f64(j + 1usize) * out[i * 2usize * n + j] }
                j += 1usize
            }
            i += 1usize
        }
        ret s
    }
    if kind == 5usize {
        var i = 0usize
        while i < n {
            tour[i] = usize(z[5usize + n * n + i]) - 1usize
            i += 1usize
        }
        let k = tsp.cut_tour(tour, n, p - 1usize, q == 1usize, path)
        ret checksum(path, k)
    }
    if q == 1usize { ret tsp.tour_length(m, n, tour) }
    ret checksum(tour, n)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsp.json")
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
