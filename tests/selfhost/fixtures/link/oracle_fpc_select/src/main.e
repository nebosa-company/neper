// e.algo.stat.fpc_select against fpc::nselectboot and fpc::prediction.strength. tests/oracle/fpc_select.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_select`; the layout of every case is at the top of scripts/r_oracle/groups/fpc_select.R.

use e.algo.stat.fpc_select as fs
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let fn_id = usize(z[0usize])
    let what = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let distances = z[4usize] > 0.5f64
    let bcount = usize(z[5usize])
    let hmeth = z[6usize]
    let hsc = z[7usize]
    let kmin = usize(z[8usize])
    let kmax = usize(z[9usize])
    let cl = usize(z[10usize])
    let cutoff = z[11usize]
    let seedv = i64(z[12usize])
    var dlen = n * p
    if distances { dlen = n * n }
    let data = z[13usize..13usize + dlen]
    let (cp, e0) = mem.alloc[f64](a, 5usize)
    if e0 != ok { os.exit(4) }
    cp[0usize] = hmeth
    cp[1usize] = 2.0f64
    cp[2usize] = hsc
    cp[3usize] = 0.0f64
    cp[4usize] = 0.0f64
    if hmeth < 0.5f64 {
        cp[0usize] = 1.0f64
        cp[4usize] = 4.0f64
    }
    // 11 pamkCBI and 12 claraCBI (pam) on the data
    if hmeth > 10.5f64 {
        cp[0usize] = 1.0f64
        cp[4usize] = 5.0f64
    }
    var tot = 0.0f64
    if fn_id == 1usize {
        let (stab, e1) = mem.alloc[f64](a, bcount * (kmax + 1usize))
        let (stabk, e2) = mem.alloc[f64](a, kmax + 1usize)
        if e1 != ok || e2 != ok { os.exit(5) }
        let (kopt, e3) = fs.nselectboot(a, data, n, p, distances, bcount, cp, cl, kmin, kmax, seedv, stab, stabk)
        if e3 != ok { os.exit(6) }
        if what == 2usize { ret f64(kopt) }
        if what == 1usize {
            var k = kmin
            while k <= kmax {
                tot += f64(k) * stabk[k]
                k += 1usize
            }
            ret tot
        }
        if what == 3usize {
            // largeisgood = TRUE answers 1 - stabk
            var k = kmin
            while k <= kmax {
                tot += f64(k) * (1.0f64 - stabk[k])
                k += 1usize
            }
            ret tot
        }
        var i = 0usize
        while i < bcount {
            var k = kmin
            while k <= kmax {
                tot += f64(i * kmax + k) * stab[i * (kmax + 1usize) + k]
                k += 1usize
            }
            i += 1usize
        }
        ret tot
    }
    let (corr, e4) = mem.alloc[f64](a, (kmax - kmin + 1usize) * bcount)
    let (mp, e5) = mem.alloc[f64](a, kmax + 1usize)
    if e4 != ok || e5 != ok { os.exit(5) }
    let (opt, e6) = fs.predstr(a, data, n, p, distances, kmin, kmax, bcount, cp, cl, cutoff, seedv, corr, mp)
    if e6 != ok { os.exit(7) }
    if what == 2usize { ret f64(opt) }
    if what == 1usize {
        var k = kmin
        while k <= kmax {
            tot += f64(k) * mp[k]
            k += 1usize
        }
        ret tot
    }
    var i = 0usize
    while i < corr.len {
        tot += f64(i + 1usize) * corr[i]
        i += 1usize
    }
    ret tot
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_select.json")
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
                var c2 = *c
                c2.args = c.args[9usize..13usize]
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
