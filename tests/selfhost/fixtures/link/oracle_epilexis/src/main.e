// e.algo.stat.epilexis against Epi: splitLexis, cutLexis, the Poisson person-years cells and ci.lin. tests/oracle/epilexis.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R epilexis`; the argument layout is at the top of scripts/r_oracle/groups/epilexis.R.

use e.algo.stat.epilexis as el
use e.mem
use e.io
use e.os
use e.str
use e.test.oracle as oracle

// the data block (per, age, dur, cst, xst, id per row) as table rows (id, per, age, dur, cst, xst)
fn table(a: *mem.Arena, x: []const f64, n: usize) -> []f64 {
    let (t, e) = mem.alloc[f64](a, n * 6usize + 1usize)
    if e != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        t[i * 6usize] = x[1usize + i * 6usize + 5usize]
        t[i * 6usize + 1usize] = x[1usize + i * 6usize]
        t[i * 6usize + 2usize] = x[1usize + i * 6usize + 1usize]
        t[i * 6usize + 3usize] = x[1usize + i * 6usize + 2usize]
        t[i * 6usize + 4usize] = x[1usize + i * 6usize + 3usize]
        t[i * 6usize + 5usize] = x[1usize + i * 6usize + 4usize]
        i += 1usize
    }
    ret t
}

fn pick(rows: []const f64, nrows: usize, w: usize, kind: usize, idx: usize) -> f64 {
    if kind == 0usize { ret f64(nrows) }
    if kind == 1usize { ret rows[idx] }
    var s = 0.0f64
    var r = 0usize
    while r < nrows {
        if kind == 2usize { s += rows[r * w + idx] }
        if kind == 3usize { s += rows[r * w + 6usize] }
        r += 1usize
    }
    ret s
}

fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let tab = table(ar, x, n)
    let o = 1usize + 6usize * n
    if str.eq(c.name, "split") {
        let kind = usize(x[o])
        let idx = usize(x[o + 1usize])
        let s1 = usize(x[o + 2usize])
        let nb1 = usize(x[o + 3usize])
        let b1 = x[o + 4usize..o + 4usize + nb1]
        let s2 = usize(x[o + 4usize + nb1])
        let nb2 = usize(x[o + 5usize + nb1])
        let b2 = x[o + 6usize + nb1..o + 6usize + nb1 + nb2]
        let (n1, t1, e1) = el.split1(ar, tab, n, s1, b1)
        if e1 != ok { os.exit(5) }
        var rows = t1[0usize..n1 * 6usize]
        var nr = n1
        if nb2 > 0usize {
            let (n2, t2, e2) = el.split1(ar, rows, n1, s2, b2)
            if e2 != ok { os.exit(5) }
            rows = t2[0usize..n2 * 6usize]
            nr = n2
        }
        ret pick(rows, nr, 6usize, kind, idx)
    }
    if str.eq(c.name, "cut") {
        let kind = usize(x[o])
        let idx = usize(x[o + 1usize])
        let sc = usize(x[o + 2usize])
        let prog = x[o + 4usize] > 0.5f64
        let np = x[o + 5usize]
        var nprec = 0usize
        var defp = false
        if np < 0.0f64 { defp = true }
        if np > 0.0f64 { nprec = usize(np) }
        let pr = x[o + 6usize..o + 6usize + nprec]
        let cut = x[o + 6usize + nprec..o + 6usize + nprec + n]
        let ns = x[o + 6usize + nprec + n..o + 6usize + nprec + 2usize * n]
        let (nr, rows, e) = el.cut1(ar, tab, n, sc, prog, pr, defp, cut, ns)
        if e != ok { os.exit(6) }
        ret pick(rows, nr, 7usize, kind, idx)
    }
    let na = usize(x[o])
    let ba = x[o + 1usize..o + 1usize + na]
    let npp = usize(x[o + 1usize + na])
    let bp = x[o + 2usize + na..o + 2usize + na + npp]
    let q = o + 2usize + na + npp
    let kind = usize(x[q])
    let r = usize(x[q + 1usize])
    let cc = usize(x[q + 2usize])
    let nctr = usize(x[q + 3usize])
    let (cells, e) = el.rate_cells(ar, tab, n, ba, bp)
    if e != ok { os.exit(7) }
    if kind == 0usize { ret cells.y[r] }
    if kind == 1usize { ret cells.d[r] }
    let (out, e2) = mem.alloc[f64](ar, 7usize)
    let (unit, e3) = mem.alloc[f64](ar, cells.p)
    if e2 != ok || e3 != ok { os.exit(8) }
    var i = 0usize
    while i < cells.p {
        unit[i] = 0.0f64
        i += 1usize
    }
    if kind == 2usize {
        unit[r] = 1.0f64
        el.ci_lin(cells.coef, cells.cov, cells.p, unit, 0.05f64, out)
    } else {
        if nctr != cells.p { os.exit(9) }
        el.ci_lin(cells.coef, cells.cov, cells.p, x[q + 4usize..q + 4usize + nctr], 0.05f64, out)
    }
    ret out[cc]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/epilexis.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
