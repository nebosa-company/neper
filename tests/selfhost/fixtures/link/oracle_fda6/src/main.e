// e.algo.stat.fdaregfd register.fd with crit 1 against fda. tests/oracle/fda6.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda6`; the layout is at the top of scripts/r_oracle/groups/fda6.R.
// Consecutive cases of one registration share their arguments (all but which and index), so it is run once per setup.

use e.algo.stat.fdaregfd as rg
use e.algo.stat.fdareg as fr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn same_setup(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if i != 4usize && i != 5usize && x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn run(a: *mem.Arena, z: []const f64, r1: []f64, r2: []f64, r3: []f64) -> bool {
    let ynb = usize(z[0usize])
    let nw = usize(z[1usize])
    let ncurve = usize(z[3usize])
    let (yb, e1) = mem.alloc[f64](a, ynb - 2usize)
    let (wb, e2) = mem.alloc[f64](a, nw - 2usize)
    let (wc0, e3) = mem.alloc[f64](a, nw * ncurve)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var i = 0usize
    while i < ynb - 2usize {
        yb[i] = fr.seq_at(0.0f64, 1.0f64, ynb - 2usize, i)
        i += 1usize
    }
    i = 0usize
    while i < nw - 2usize {
        wb[i] = fr.seq_at(0.0f64, 1.0f64, nw - 2usize, i)
        i += 1usize
    }
    i = 0usize
    while i < nw * ncurve {
        wc0[i] = 0.0f64
        i += 1usize
    }
    ret rg.register_fd_crit(a, 4usize, yb, 4usize, wb, 2usize, z[2usize], usize(z[6usize]), ncurve, z[7usize..7usize + ynb * ncurve], z[7usize + ynb * ncurve..7usize + ynb * ncurve + ynb], wc0, r1, r2, r3) == ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda6.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (r1, e1) = mem.alloc[f64](a, 256usize)
    let (r2, e2) = mem.alloc[f64](a, 64usize)
    let (r3, e3) = mem.alloc[f64](a, 64usize)
    let (seen, e4) = mem.alloc[usize](a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    var s0 = 0usize
    while s0 < 8usize {
        seen[s0] = 0usize
        s0 += 1usize
    }
    var failures = 0usize
    var at = 0usize
    var have = false
    var prev = golden.cases[0usize].args
    var good = false
    while at < golden.cases.len {
        let c = &golden.cases[at]
        if !have || !same_setup(prev, c.args) {
            good = run(a, c.args, r1, r2, r3)
            prev = c.args
            have = true
        }
        var got = 0.0f64 / 0.0f64
        if good {
            let w = usize(c.args[4usize])
            let q = usize(c.args[5usize])
            if w == 0usize { got = r1[q] }
            if w == 1usize { got = r2[q] }
            if w == 2usize { got = r3[q] }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            let key = usize(c.args[4usize])
            seen[key] += 1usize
            if seen[key] <= 3usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
