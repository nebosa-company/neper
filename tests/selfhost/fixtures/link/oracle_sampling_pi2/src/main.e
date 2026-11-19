// e.algo.stat.sampling's UPtillepi2, UPsystematicpi2 and varHT against sampling. tests/oracle/sampling_pi2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_pi2`; the layout is at the top of scripts/r_oracle/groups/sampling_pi2.R.

use e.algo.stat.sampling as sm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let size = z[2usize]
    let ii = usize(z[3usize])
    let jj = usize(z[4usize])
    let av = z[5usize..5usize + n]
    let y = z[5usize + n..5usize + 2usize * n]
    let (pik, e0) = mem.alloc[f64](a, n)
    let (pi2, e1) = mem.alloc[f64](a, n * n)
    if e0 != ok || e1 != ok { os.exit(4) }
    sm.inclusion(av, size, pik)
    var e = ok
    if kind == 0usize || kind == 2usize || kind == 3usize { e = sm.up_tille_pi2(a, pik, pi2) }
    if kind == 1usize || kind == 4usize || kind == 5usize { e = sm.up_systematic_pi2(a, pik, pi2) }
    if kind >= 6usize && kind <= 8usize { e = sm.up_midzuno_pi2(a, pik, pi2) }
    if kind >= 9usize { e = sm.up_sampford_pi2(a, pik, pi2) }
    if e != ok { os.exit(5) }
    if kind < 2usize || kind == 6usize || kind == 9usize { ret pi2[ii * n + jj] }
    var method = 1usize
    if kind == 3usize || kind == 5usize || kind == 8usize || kind == 11usize { method = 2usize }
    ret sm.var_ht(y, pi2, method)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_pi2.json")
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
