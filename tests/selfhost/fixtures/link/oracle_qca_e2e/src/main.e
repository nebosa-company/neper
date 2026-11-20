// QCA truthTable() then minimize() end to end: e.algo.stat.qcapkg.truth_table feeding e.algo.stat.qcamin.minimize_text. tests/oracle/qca_e2e.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qca_e2e`; the layout is at the top of scripts/r_oracle/groups/qca_e2e.R.

use e.algo.stat.qcamin as qm
use e.algo.stat.qcapkg as qc
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[4usize])
    let k = usize(x[5usize])
    let nv = k + 1usize
    let de0 = 6usize
    let data = x[de0 + k..de0 + k + n * nv]
    var y: [64]f64 = zero
    var r = 0usize
    while r < n {
        y[r] = data[r * nv + k]
        r += 1usize
    }
    let rows = usize(1u64 << u64(k))
    let (tt, e1) = mem.alloc[f64](a, rows * 4usize)
    if e1 != ok { os.exit(4) }
    qc.truth_table(data, y[0usize..n], n, nv, k, x[1usize], x[2usize], x[3usize], tt)
    let (on, e2) = mem.alloc[u32](a, rows)
    if e2 != ok { os.exit(5) }
    let (dc, e3) = mem.alloc[u32](a, rows)
    if e3 != ok { os.exit(6) }
    let (de, e4) = mem.alloc[u8](a, k)
    if e4 != ok { os.exit(7) }
    var non = 0usize
    var ndc = 0usize
    var i = 0usize
    while i < rows {
        let o = tt[i * 4usize + 3usize]
        if o == 1.0f64 {
            on[non] = u32(i)
            non += 1usize
        }
        if o == -1.0f64 {
            dc[ndc] = u32(i)
            ndc += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        de[i] = u8(x[de0 + i])
        i += 1usize
    }
    let (text, e5) = qm.minimize_text(a, kind, k, on[0usize..non], dc[0usize..ndc], de)
    if e5 != ok { os.exit(8) }
    ret text
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qca_e2e.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 6usize {
                let _ = io.print("\n got ")
                let _ = io.print(text)
                let _ = io.print("\n  R  ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
