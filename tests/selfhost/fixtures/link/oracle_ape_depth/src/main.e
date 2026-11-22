// e.algo.stat.apepkg.tips_under / node_edgelengths against ape::node.depth and
// ape::node.depth.edgelength. tests/oracle/ape_depth.json comes from
// `Rscript scripts/r_oracle/generate.R ape_depth`; the layout is at the top of
// scripts/r_oracle/groups/ape_depth.R.

use e.algo.stat.apepkg as ape
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let kind = usize(z[1usize])
    let text = c.inputs[0usize]
    let cap = 2usize * text.len + 1usize
    let (par, e0) = mem.alloc[i64](a, cap)
    let (edg, e1) = mem.alloc[f64](a, cap)
    let (dep, e2) = mem.alloc[usize](a, cap)
    let (lab, e3) = mem.alloc[str](a, cap)
    let (tip, e4) = mem.alloc[bool](a, cap)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var t: ape.Tree = ape.Tree { nn: 0usize, parent: par, edge: edg, depth: dep, label: lab, tip: tip }
    let (nt, e5) = ape.read_tree(text, &t)
    if e5 != ok || nt != n { ret nan }
    var s = 0.0f64
    if kind == 0usize {
        let (v, e6) = mem.alloc[usize](a, t.nn)
        if e6 != ok { ret nan }
        if ape.tips_under(&t, v) != ok { ret nan }
        ape.sort_usize(v)
        var i = 0usize
        while i < t.nn {
            s += f64(v[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    let (d, e7) = mem.alloc[f64](a, t.nn)
    if e7 != ok { ret nan }
    if ape.node_edgelengths(&t, d) != ok { ret nan }
    ape.sort_f64(d)
    var i = 0usize
    while i < t.nn {
        s += d[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ape_depth.json")
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
