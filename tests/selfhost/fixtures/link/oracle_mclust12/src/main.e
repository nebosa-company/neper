// e.algo.stat.mclusthce (hc for EEE) against mclust. tests/oracle/mclust12.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust12`; the layout is at the top of scripts/r_oracle/groups/mclust12.R.

use e.algo.stat.mclusthce as he
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle


fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let mode = usize(z[2usize])
    let id = z[3usize]
    let x = z[4usize..4usize + n * p]
    let (init, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret nan }
    // dupPartition: identical rows share a group, numbered by first appearance
    var ng = 0usize
    var i = 0usize
    while i < n {
        var found = false
        var jj = 0usize
        while jj < i && !found && mode == 1usize {
            var same = true
            var q = 0usize
            while q < p {
                if x[q * n + i] != x[q * n + jj] { same = false }
                q += 1usize
            }
            if same {
                init[i] = init[jj]
                found = true
            }
            jj += 1usize
        }
        if !found {
            ng += 1usize
            init[i] = ng
        }
        i += 1usize
    }
    if ng < 2usize { ret nan }
    let (pairs, e2) = mem.alloc[usize](a, 2usize * (ng - 1usize))
    if e2 != ok { ret nan }
    if he.hc_eee(a, x, n, p, init, ng, pairs) != ok { ret nan }
    var s = 0.0f64
    if id < 0.0f64 {
        var q = 0usize
        while q < 2usize * (ng - 1usize) {
            s += f64(q + 1usize) * f64(pairs[q])
            q += 1usize
        }
        ret s
    }
    if id < 3.0f64 {
        let t = usize(id)
        ret 1000.0f64 * f64(pairs[2usize * t]) + f64(pairs[2usize * t + 1usize])
    }
    let g = usize(id) - 100usize
    let (lab, e3) = mem.alloc[usize](a, n)
    if e3 != ok { ret nan }
    if he.hclass_init(a, pairs, init, n, ng, g, lab) != ok { ret nan }
    i = 0usize
    while i < n {
        s += f64(i + 1usize) * f64(lab[i])
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust12.json")
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
                let (initial, be) = str.builder(a, 120usize)
                var b = initial
                let _ = str.push(&b, "hce n ")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " p ")
                let _ = str.push_f64(&b, c.args[1usize])
                let _ = str.push(&b, " id ")
                let _ = str.push_f64(&b, c.args[3usize])
                let _ = str.push(&b, ": got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, ", R says ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
