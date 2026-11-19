// e.algo.stat.mstatepkg's probtrans (forward) against mstate::probtrans. tests/oracle/mstate_probtrans.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mstate_probtrans`; the layout is at the top of scripts/r_oracle/groups/mstate_probtrans.R.

use e.algo.stat.mstatepkg as ms
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let s = usize(z[0usize])
    let nt = usize(z[1usize])
    let nn = usize(z[2usize])
    let predt = z[3usize]
    let i = usize(z[4usize])
    let j = usize(z[5usize])
    let k = usize(z[6usize])
    let (from, e0) = mem.alloc[usize](a, nt)
    let (to, e1) = mem.alloc[usize](a, nt)
    let (out, e2) = mem.alloc[f64](a, (nn + 1usize) * s * s)
    if e0 != ok || e1 != ok || e2 != ok { os.exit(4) }
    var t = 0usize
    while t < nt {
        from[t] = usize(z[7usize + t])
        to[t] = usize(z[7usize + nt + t])
        t += 1usize
    }
    let times = z[7usize + 2usize * nt..7usize + 2usize * nt + nn]
    let cum = z[7usize + 2usize * nt + nn..7usize + 2usize * nt + nn + nt * nn]
    let (rows, e) = ms.probtrans_forward(a, s, nt, from, to, nn, times, cum, predt, out)
    if e != ok { os.exit(5) }
    if i > rows { os.exit(6) }
    ret out[i * s * s + j * s + k]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mstate_probtrans.json")
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
