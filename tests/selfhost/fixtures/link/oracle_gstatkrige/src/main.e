// e.algo.stat.gstatkrige against gstat's krige, krige.cv and krige(nsim =). tests/oracle/gstatkrige.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gstatkrige`; the layout is at the top of scripts/r_oracle/groups/gstatkrige.R.

use e.algo.rand.r as rr
use e.algo.stat.gstatkrige as gk
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// splits the data rows (x y z X..) at `at` into coordinates, responses and drift
fn unpack(a: *mem.Arena, x: []const f64, at: usize, n: usize, p: usize, xy: []f64, z: []f64, xd: []f64) {
    var i = 0usize
    while i < n {
        let b = at + i * (3usize + p)
        xy[2usize * i] = x[b]
        xy[2usize * i + 1usize] = x[b + 1usize]
        z[i] = x[b + 2usize]
        var q = 0usize
        while q < p {
            xd[i * p + q] = x[b + 3usize + q]
            q += 1usize
        }
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    let mode = usize(x[0usize])
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nst = usize(x[3usize])
    let nmax = usize(x[4usize])
    let maxdist = x[5usize]
    let nmin = usize(x[6usize])
    let (xy, e1) = mem.alloc[f64](a, 2usize * n)
    if e1 != ok { os.exit(5) }
    let (z, e2) = mem.alloc[f64](a, n)
    if e2 != ok { os.exit(6) }
    let (xd, e3) = mem.alloc[f64](a, n * p)
    if e3 != ok { os.exit(7) }
    if str.eq(k, "krige") {
        let part = usize(x[7usize])
        let px = x[8usize]
        let py = x[9usize]
        let x0 = x[10usize..10usize + p]
        let beta = x[10usize + p..10usize + 2usize * p]
        let ms = x[10usize + 2usize * p..10usize + 2usize * p + 6usize * nst]
        unpack(a, x, 10usize + 2usize * p + 6usize * nst, n, p, xy, z, xd)
        let (o, e4) = mem.alloc[f64](a, 2usize)
        if e4 != ok { os.exit(8) }
        if gk.krige_point(a, xy, z, xd, n, p, x0, px, py, ms, nst, mode, beta, nmax, maxdist, nmin, o) != ok { os.exit(9) }
        ret o[part]
    }
    if str.eq(k, "cv") {
        let part = usize(x[7usize])
        let row = usize(x[8usize])
        let fold = x[11usize..11usize + n]
        let beta = x[11usize + n..11usize + n + p]
        let ms = x[11usize + n + p..11usize + n + p + 6usize * nst]
        unpack(a, x, 11usize + n + p + 6usize * nst, n, p, xy, z, xd)
        let (o, e4) = mem.alloc[f64](a, 2usize * n)
        if e4 != ok { os.exit(8) }
        if gk.krige_cv(a, xy, z, xd, n, p, fold, ms, nst, mode, beta, nmax, maxdist, nmin, o) != ok { os.exit(9) }
        ret o[part * n + row]
    }
    let nsim = usize(x[7usize])
    let nnew = usize(x[8usize])
    let seed = i64(x[9usize])
    let known = x[10usize] > 0.5f64
    let index = usize(x[11usize])
    let beta = x[12usize..12usize + p]
    let ms = x[12usize + p..12usize + p + 6usize * nst]
    let at = 12usize + p + 6usize * nst
    unpack(a, x, at, n, p, xy, z, xd)
    let nat = at + n * (3usize + p)
    let (nxy, e4) = mem.alloc[f64](a, 2usize * nnew)
    if e4 != ok { os.exit(10) }
    let (nxd, e5) = mem.alloc[f64](a, nnew * p)
    if e5 != ok { os.exit(11) }
    var i = 0usize
    while i < nnew {
        nxy[2usize * i] = x[nat + i * (2usize + p)]
        nxy[2usize * i + 1usize] = x[nat + i * (2usize + p) + 1usize]
        var q = 0usize
        while q < p {
            nxd[i * p + q] = x[nat + i * (2usize + p) + 2usize + q]
            q += 1usize
        }
        i += 1usize
    }
    let (out, e6) = mem.alloc[f64](a, nsim * nnew)
    if e6 != ok { os.exit(12) }
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    if gk.sgs_simulate(a, &rng, xy, z, xd, n, p, nxy, nxd, nnew, ms, nst, nsim, known, beta, nmax, maxdist, nmin, out) != ok { os.exit(13) }
    ret out[index]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gstatkrige.json")
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
                let (sb, sbe) = str.builder(a, 256usize)
                var b = sb
                let _ = str.push_usize(&b, at)
                let _ = str.push(&b, " ")
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " mode")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " p")
                let _ = str.push_f64(&b, c.args[2usize])
                let _ = str.push(&b, " nst")
                let _ = str.push_f64(&b, c.args[3usize])
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " want ")
                let _ = str.push_f64(&b, c.want)
                let _ = str.push(&b, "\n")
                let _ = io.print(str.done(&b))
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
