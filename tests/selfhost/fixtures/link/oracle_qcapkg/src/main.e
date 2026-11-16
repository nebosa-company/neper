// e.algo.stat.qcapkg against QCA. tests/oracle/qcapkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qcapkg`; the layout is at the top of scripts/r_oracle/groups/qcapkg.R.

use e.algo.logic as lg
use e.algo.stat.qcapkg as qc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qcapkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        if str.eq(c.name, "pof") {
            let pn = usize(x[2usize])
            let pnv = usize(x[3usize])
            let sl = usize(x[4usize])
            let got2 = qc.pof(x[5usize + sl..5usize + sl + pn * pnv], x[5usize + sl + pn * pnv..5usize + sl + pn * pnv + pn], pn, pnv, x[5usize..5usize + sl], usize(x[0usize]), usize(x[1usize]))
            if !oracle.agrees(got2, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, got2))
                    let _ = io.print("\n")
                }
            }
            at += 1usize
            continue
        }
        let n = usize(x[2usize])
        let non = usize(x[3usize])
        let ndc = usize(x[4usize])
        let (mt, e1) = mem.alloc[u32](a, non)
        if e1 != ok { os.exit(5) }
        let (dc, e2) = mem.alloc[u32](a, ndc + 1usize)
        if e2 != ok { os.exit(6) }
        var i = 0usize
        while i < non {
            mt[i] = u32(x[5usize + i])
            i += 1usize
        }
        i = 0usize
        while i < ndc {
            dc[i] = u32(x[5usize + non + i])
            i += 1usize
        }
        let cap = 3usize * (1usize << n) + 64usize
        let (primes, e3) = mem.alloc[lg.Implicant](a, cap)
        if e3 != ok { os.exit(7) }
        let (work, e4) = mem.alloc[lg.Implicant](a, cap)
        if e4 != ok { os.exit(8) }
        let (merged, e5) = mem.alloc[u8](a, cap)
        if e5 != ok { os.exit(9) }
        let (np, e6) = lg.prime_implicants(n, mt, dc[0usize..ndc], primes, work, merged)
        if e6 != ok { os.exit(10) }
        let (best, cnt, e7) = qc.min_covers(a, mt, primes[0usize..np])
        if e7 != ok { os.exit(11) }
        var got = 0.0f64
        let what = usize(x[0usize])
        if what == 0usize {
            // the primes QCA keeps: those covering at least one outcome-1 configuration
            var kept = 0usize
            var p = 0usize
            while p < np {
                var any = false
                var m = 0usize
                while m < non {
                    if lg.covers(primes[p], mt[m]) { any = true }
                    m += 1usize
                }
                if any { kept += 1usize }
                p += 1usize
            }
            got = f64(kept)
        }
        if what == 1usize { got = f64(best) }
        if what == 2usize { got = f64(cnt) }
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
