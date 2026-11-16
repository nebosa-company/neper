// e.algo.stat.pamcluster against cluster::pam. tests/oracle/pamcluster.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pamcluster`; the layout is at the top of scripts/r_oracle/groups/pamcluster.R.

use e.algo.stat.pamcluster as pc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn daisy_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (kind, e1) = mem.alloc[usize](a, p)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < p {
        kind[i] = usize(x[3usize + i])
        i += 1usize
    }
    let (m, e2) = mem.alloc[f64](a, n * p)
    if e2 != ok { os.exit(6) }
    i = 0usize
    while i < n * p {
        m[i] = x[3usize + p + i]
        if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    let (d, e3) = mem.alloc[f64](a, n * n)
    if e3 != ok { os.exit(7) }
    if pc.daisy_gower(a, m, n, p, kind, d) != ok { os.exit(8) }
    var s = 0.0f64
    var pos = 1usize
    var col = 0usize
    while col < n {
        var row = col + 1usize
        while row < n {
            s += d[row * n + col] * f64(pos)
            pos += 1usize
            row += 1usize
        }
        col += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "daisy") { ret daisy_case(a, c) }
    let x = c.args
    let n = usize(x[0usize])
    let k = usize(x[1usize])
    let (d, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[2usize + 2usize * i] - x[2usize + 2usize * j]
            let dy = x[3usize + 2usize * i] - x[3usize + 2usize * j]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    let (med, e2) = mem.alloc[usize](a, k)
    if e2 != ok { os.exit(6) }
    let (lab, e3) = mem.alloc[usize](a, n)
    if e3 != ok { os.exit(7) }
    let (r, e4) = pc.pam(a, d, n, k, med, lab)
    if e4 != ok { os.exit(8) }
    // the package's order of medoids after several swaps can differ from the greedy order here, so compare the sorted set and the partition numbered by first appearance
    i = 1usize
    while i < k {
        let t = med[i]
        var j = i
        while j > 0usize && med[j - 1usize] > t {
            med[j] = med[j - 1usize]
            j -= 1usize
        }
        med[j] = t
        i += 1usize
    }
    let (seen, e5) = mem.alloc[usize](a, k + 1usize)
    if e5 != ok { os.exit(9) }
    i = 0usize
    while i <= k {
        seen[i] = 0usize
        i += 1usize
    }
    var next = 1usize
    i = 0usize
    while i < n {
        if seen[lab[i]] == 0usize {
            seen[lab[i]] = next
            next += 1usize
        }
        lab[i] = seen[lab[i]]
        i += 1usize
    }
    let kind = c.name
    if str.eq(kind, "build") { ret r.build }
    if str.eq(kind, "swap") { ret r.swap }
    var s = 0.0f64
    if str.eq(kind, "med") {
        i = 0usize
        while i < k {
            s += f64(med[i] + 1usize) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    i = 0usize
    while i < n {
        s += f64(lab[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pamcluster.json")
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
