// e.algo.stat.lspec against polspline: lspec fits, dlspec, plspec, clspec and the periodogram.
// tests/oracle/polspline_lspec.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polspline_lspec`.

use e.algo.stat.lspec as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: []f64, fit: sp.LSpec, valid: bool }

fn same(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let z = c.args
    if str.eq(c.name, "pgram") {
        let n = usize(z[0usize])
        let (pg, e) = sp.periodogram(a, z[1usize..1usize + n])
        if e != ok { ret nan }
        ret pg[usize(z[1usize + n])]
    }
    let key = z[0usize..z.len - 2usize]
    if !cache.valid || !same(cache.key, key) {
        let nin = usize(z[8usize])
        let nat = usize(z[9usize])
        let kin = z[10usize..10usize + nin]
        let ain = z[10usize + nin..10usize + nin + nat]
        let nxo = 10usize + nin + nat
        let nx = usize(z[nxo])
        let per = z[nxo + 1usize..nxo + 1usize + nx]
        let (fit, e) = sp.lspec(a, per, usize(z[0usize]), z[1usize] > 0.5f64, z[2usize], z[3usize], kin, ain, i64(z[4usize]), i64(z[5usize]), i64(z[6usize]), i64(z[7usize]))
        if e != ok { ret nan }
        cache.key = key
        cache.fit = fit
        cache.valid = true
    }
    let what = usize(z[z.len - 2usize])
    let x = z[z.len - 1usize]
    let m = &cache.fit
    if what == 0usize { ret f64(m.nknots) }
    if what == 1usize { ret f64(m.natoms) }
    if what == 2usize { ret m.logl }
    if what == 3usize { ret m.thetap[usize(x)] }
    if what == 4usize {
        if usize(x) >= m.nknots { ret nan }
        ret m.knots[usize(x)]
    }
    if what == 5usize {
        if usize(x) >= m.nknots { ret nan }
        ret m.thetak[usize(x)]
    }
    if what == 6usize {
        if usize(x) >= m.natoms { ret nan }
        ret m.atoms[usize(x)]
    }
    if what == 7usize {
        if usize(x) >= m.natoms { ret nan }
        ret m.mass[usize(x)]
    }
    if what == 8usize { ret m.minmass }
    if what == 9usize { ret m.penalty }
    if what == 11usize { ret sp.dlspec(m, x) }
    if what == 12usize { ret sp.dlspec_mass(m, x) }
    if what == 13usize {
        let mm = sp.plspec_default_mm(m)
        let (ss, e) = sp.plspec_table(a, m, mm)
        if e != ok { ret nan }
        ret sp.plspec(m, ss, mm, x)
    }
    var lags: [7]f64 = zero
    var out: [7]f64 = zero
    var i = 0usize
    while i < 7usize {
        lags[i] = f64(i)
        i += 1usize
    }
    let e = sp.clspec(a, m, lags[0usize..7usize], what == 14usize, 0usize, out[0usize..7usize])
    if e != ok { ret nan }
    ret out[usize(x)]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polspline_lspec.json")
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
            if failures <= 8usize {
                var tail: [3]f64 = zero
                tail[0usize] = f64(at)
                tail[1usize] = c.args[c.args.len - 2usize]
                tail[2usize] = c.args[c.args.len - 1usize]
                let short = oracle.Case{ name: c.name, args: tail[0usize..3usize], want: c.want, rel: c.rel, abs: c.abs, text: c.text, inputs: c.inputs }
                let _ = io.print(oracle.describe(a, &short, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
