// e.algo.stat.mstatepkg's msprep against mstate::msprep. tests/oracle/mstate_msprep.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mstate_msprep`; the layout is at the top of scripts/r_oracle/groups/mstate_msprep.R.

use e.algo.stat.mstatepkg as ms
use e.io
use e.mem
use e.os
use e.test.oracle as oracle


fn answer_msprep(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let k = usize(z[0usize])
    let n = usize(z[1usize])
    let ii = z[2usize]
    let col = usize(z[3usize])
    let (trans, e0) = mem.alloc[usize](a, k * k)
    let (out, e1) = mem.alloc[f64](a, n * k * k * 7usize)
    if e0 != ok || e1 != ok { os.exit(4) }
    var t = 0usize
    while t < k * k {
        trans[t] = usize(z[4usize + t])
        t += 1usize
    }
    let time = z[4usize + k * k..4usize + k * k + n * k]
    let status = z[4usize + k * k + n * k..4usize + k * k + 2usize * n * k]
    let (rows, e) = ms.msprep(a, k, n, trans, time, status, out)
    if e != ok { os.exit(5) }
    if ii < 0.0f64 { ret f64(rows) }
    ret out[usize(ii) * 7usize + col]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mstate_msprep.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer_msprep(a, c)
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
