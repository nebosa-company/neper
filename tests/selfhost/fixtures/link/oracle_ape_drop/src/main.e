// e.algo.stat.apepkg.drop_tips against ape::drop.tip. tests/oracle/ape_drop.json comes from
// `Rscript scripts/r_oracle/generate.R ape_drop`; the layout is at the top of
// scripts/r_oracle/groups/ape_drop.R.

use e.algo.stat.apepkg as ape
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n_after = usize(z[0usize])
    let nd = usize(z[1usize])
    let text = c.inputs[0usize]
    let cap = 2usize * text.len + 1usize
    let (par, e0) = mem.alloc[i64](a, cap)
    let (edg, e1) = mem.alloc[f64](a, cap)
    let (dep, e2) = mem.alloc[usize](a, cap)
    let (lab, e3) = mem.alloc[str](a, cap)
    let (tip, e4) = mem.alloc[bool](a, cap)
    let (o_par, e5) = mem.alloc[i64](a, cap)
    let (o_edg, e6) = mem.alloc[f64](a, cap)
    let (o_dep, e7) = mem.alloc[usize](a, cap)
    let (o_lab, e8) = mem.alloc[str](a, cap)
    let (o_tip, e9) = mem.alloc[bool](a, cap)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret nan }
    var t: ape.Tree = ape.Tree { nn: 0usize, parent: par, edge: edg, depth: dep, label: lab, tip: tip }
    let (nt, e10) = ape.read_tree(text, &t)
    if e10 != ok { ret nan }
    let (drop, e11) = mem.alloc[bool](a, nt)
    if e11 != ok { ret nan }
    var i = 0usize
    while i < nt {
        drop[i] = false
        i += 1usize
    }
    i = 0usize
    while i < nd {
        drop[usize(z[2usize + i]) - 1usize] = true
        i += 1usize
    }
    var o: ape.Tree = ape.Tree { nn: 0usize, parent: o_par, edge: o_edg, depth: o_dep, label: o_lab, tip: o_tip }
    let (got_tips, e12) = ape.drop_tips(&t, drop, &o)
    if e12 != ok || got_tips != n_after { ret nan }
    let (out, e13) = mem.alloc[f64](a, n_after * n_after)
    if e13 != ok { ret nan }
    let (n, e14) = ape.cophenetic(&o, out)
    if e14 != ok || n != n_after { ret nan }
    var s = 0.0f64
    i = 0usize
    while i < n_after * n_after {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ape_drop.json")
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
