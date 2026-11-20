// e.algo.stat.cluelsap against clue and lpSolve. tests/oracle/clue_lsap.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_lsap`; the layout is at the top of scripts/r_oracle/groups/clue_lsap.R.

use e.algo.stat.cluelsap as cl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "member") {
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        let (lab, e0) = mem.alloc[usize](a, n)
        let (out, e1) = mem.alloc[f64](a, n * k)
        if e0 != ok || e1 != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            lab[i] = usize(x[2usize + i])
            i += 1usize
        }
        cl.membership_hard(lab, n, k, out)
        var s = 0.0f64
        i = 0usize
        while i < n {
            var j = 0usize
            while j < k {
                s += out[i * k + j] * f64(10usize * (i + 1usize) + j + 1usize)
                j += 1usize
            }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "memrow") || str.eq(c.name, "memcol") {
        let n = usize(x[0usize])
        let kc = usize(x[1usize])
        let k = usize(x[2usize])
        let (lab, e0) = mem.alloc[usize](a, n)
        let (out, e1) = mem.alloc[f64](a, n * k)
        if e0 != ok || e1 != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            lab[i] = usize(x[3usize + i])
            i += 1usize
        }
        cl.membership_hard(lab, n, k, out)
        let at = usize(x[3usize + n]) - 1usize
        var s = 0.0f64
        if str.eq(c.name, "memrow") {
            var j = 0usize
            while j < k {
                s += out[at * k + j] * f64(j + 1usize)
                j += 1usize
            }
        } else {
            i = 0usize
            while i < n {
                s += out[i * k + at]
                i += 1usize
            }
        }
        ret s
    }
    if str.eq(c.name, "softat") {
        let n = usize(x[0usize])
        let k0 = usize(x[1usize])
        let k = usize(x[2usize])
        let (out, e1) = mem.alloc[f64](a, n * k)
        if e1 != ok { os.exit(5) }
        cl.membership_soft(x[3usize..(3usize + n * k0)], n, k0, k, out)
        let i = usize(x[3usize + n * k0]) - 1usize
        let j = usize(x[4usize + n * k0]) - 1usize
        ret out[i * k + j]
    }
    var nr = 0usize
    var nc = 0usize
    var mx = false
    var at = 0usize
    if str.eq(c.name, "lpmax") {
        nr = usize(x[0usize])
        nc = nr
        mx = true
        at = 1usize
    } else {
        nr = usize(x[0usize])
        nc = usize(x[1usize])
        mx = x[2usize] > 0.5f64
        at = 3usize
    }
    let (asg, e2) = mem.alloc[usize](a, nr)
    if e2 != ok { os.exit(6) }
    let (total, e3) = cl.solve_lsap(a, x[at..(at + nr * nc)], nr, nc, mx, asg)
    if e3 != ok { os.exit(7) }
    if str.eq(c.name, "lsapat") {
        ret f64(asg[usize(x[at + nr * nc]) - 1usize] + 1usize)
    }
    if str.eq(c.name, "lsapcols") {
        var s = 0.0f64
        var i = 0usize
        while i < nr {
            s += f64(asg[i] + 1usize) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    ret total
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_lsap.json")
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
