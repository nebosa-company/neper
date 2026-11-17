// e.algo.stat.ksamples against kSamples. tests/oracle/ksamples.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksamples`; the layout is at the top of scripts/r_oracle/groups/ksamples.R.

use e.algo.stat.ksamples as ks
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if c.name[0usize] == 99u8 {
        let tc = usize(x[1usize])
        if x[0usize] == 2.0f64 { ret ks.contingency2xt_exact(a, x[2usize..2usize + tc], x[2usize + tc..2usize + 2usize * tc]) }
        ret ks.contingency2xt(x[2usize..2usize + tc], x[2usize + tc..2usize + 2usize * tc], usize(x[0usize]))
    }
    if c.name[0usize] == 113u8 {
        let kq = usize(x[2usize])
        let (szq, eq) = mem.alloc[usize](a, kq)
        if eq != ok { os.exit(5) }
        var totq = 0usize
        var iq = 0usize
        while iq < kq {
            szq[iq] = usize(x[3usize + iq])
            totq += szq[iq]
            iq += 1usize
        }
        ret ks.qn_test(a, x[3usize + kq..3usize + kq + totq], szq, usize(x[0usize]), usize(x[1usize]))
    }
    if c.name[0usize] == 112u8 { ret ks.ad_pval(a, x[2usize], x[1usize], usize(x[0usize])) }
    let k = usize(x[2usize])
    let (sz, e) = mem.alloc[usize](a, k)
    if e != ok { os.exit(5) }
    var total = 0usize
    var i = 0usize
    while i < k {
        sz[i] = usize(x[3usize + i])
        total += sz[i]
        i += 1usize
    }
    ret ks.ad_test(a, x[3usize + k..3usize + k + total], sz, usize(x[0usize]), usize(x[1usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksamples.json")
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
