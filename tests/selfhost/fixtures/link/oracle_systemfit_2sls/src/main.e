// e.algo.stat.systemfitpkg's twosls against systemfit method = "2SLS". tests/oracle/systemfit_2sls.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R systemfit_2sls`; the layout is at the top of scripts/r_oracle/groups/systemfit_2sls.R.

use e.algo.stat.systemfitpkg as sf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "s3i") {
        let n3 = usize(z[0usize])
        let m3 = usize(z[1usize])
        let q3 = usize(z[2usize])
        let mi = usize(z[3usize])
        let tl = z[4usize]
        let (ks, ek) = mem.alloc[usize](a, m3)
        let (qs, eq) = mem.alloc[usize](a, m3)
        if ek != ok || eq != ok { ret nan }
        var kt = 0usize
        var e = 0usize
        while e < m3 {
            ks[e] = usize(z[5usize + e])
            qs[e] = q3
            kt += ks[e]
            e += 1usize
        }
        let xo = 5usize + m3
        let zo = xo + n3 * kt
        let yo = zo + n3 * q3
        let (zs, ez) = mem.alloc[f64](a, m3 * n3 * q3)
        let (cf3, e1) = mem.alloc[f64](a, kt)
        let (se3, e2) = mem.alloc[f64](a, kt)
        var itn: [1]usize = zero
        if ez != ok || e1 != ok || e2 != ok { ret nan }
        e = 0usize
        while e < m3 {
            var i = 0usize
            while i < n3 * q3 {
                zs[e * n3 * q3 + i] = z[zo + i]
                i += 1usize
            }
            e += 1usize
        }
        if sf.threesls_it(a, z[xo..zo], ks, zs, qs, z[yo..yo + n3 * m3], n3, m3, mi, tl, itn[0usize..1usize], cf3, se3) != ok { ret nan }
        let w3 = usize(z[yo + n3 * m3])
        if w3 < kt { ret cf3[w3] }
        if w3 < 2usize * kt { ret se3[w3 - kt] }
        ret f64(itn[0usize])
    }
    if str.eq(c.name, "s3z") {
        let nz = usize(z[0usize])
        let mz = usize(z[1usize])
        let (kz, ekz) = mem.alloc[usize](a, mz)
        let (qz, eqz) = mem.alloc[usize](a, mz)
        if ekz != ok || eqz != ok { ret nan }
        var ktz = 0usize
        var qtz = 0usize
        var e = 0usize
        while e < mz {
            kz[e] = usize(z[2usize + e])
            qz[e] = usize(z[2usize + mz + e])
            ktz += kz[e]
            qtz += qz[e]
            e += 1usize
        }
        let xo = 2usize + 2usize * mz
        let zo = xo + nz * ktz
        let yo = zo + nz * qtz
        let (cfz, e1) = mem.alloc[f64](a, ktz)
        let (sez, e2) = mem.alloc[f64](a, ktz)
        if e1 != ok || e2 != ok { ret nan }
        if sf.threesls_z(a, z[xo..zo], kz, z[zo..yo], qz, z[yo..yo + nz * mz], nz, mz, cfz, sez) != ok { ret nan }
        let wz = usize(z[yo + nz * mz])
        if wz < ktz { ret cfz[wz] }
        ret sez[wz - ktz]
    }
    if str.eq(c.name, "s3") {
        let n3 = usize(z[0usize])
        let m3 = usize(z[1usize])
        let q3 = usize(z[2usize])
        let (ks, ek) = mem.alloc[usize](a, m3)
        if ek != ok { ret nan }
        var kt = 0usize
        var e = 0usize
        while e < m3 {
            ks[e] = usize(z[3usize + e])
            kt += ks[e]
            e += 1usize
        }
        let xo = 3usize + m3
        let zo = xo + n3 * kt
        let yo = zo + n3 * q3
        let (cf3, e1) = mem.alloc[f64](a, kt)
        let (se3, e2) = mem.alloc[f64](a, kt)
        if e1 != ok || e2 != ok { ret nan }
        if sf.threesls(a, z[xo..zo], ks, z[zo..yo], q3, z[yo..yo + n3 * m3], n3, m3, cf3, se3) != ok { ret nan }
        let w3 = usize(z[yo + n3 * m3])
        if w3 < kt { ret cf3[w3] }
        ret se3[w3 - kt]
    }
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let q = usize(z[2usize])
    let (cf, e0) = mem.alloc[f64](a, k)
    let (se, e1) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok { ret nan }
    let (s2, e) = sf.twosls(a, z[3usize..3usize + n * k], z[3usize + n * k..3usize + n * k + n * q], z[3usize + n * k + n * q..3usize + n * k + n * q + n], n, k, q, cf, se)
    if e != ok { ret nan }
    let w = usize(z[3usize + n * k + n * q + n])
    if w < k { ret cf[w] }
    if w < 2usize * k { ret se[w - k] }
    ret s2
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/systemfit_2sls.json")
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
