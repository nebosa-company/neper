// e.algo.stat.partykitmob.lmtree_x against partykit lmtree with ordered partitioning factors, mtry and breakties on set.seed(seed)'s stream.
// tests/oracle/partykitmobx.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partykitmobx`; the argument layout is at the top of scripts/r_oracle/groups/partykitmobx.R.

use e.algo.stat.partykitmob as mb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let sel = usize(z[0usize])
    let n = usize(z[1usize])
    let kx = usize(z[2usize])
    let pz = usize(z[3usize])
    let alpha = z[4usize]
    let bonf = z[5usize] > 0.5f64
    let minsize = usize(z[6usize])
    let maxdepth = usize(z[7usize])
    let trim = z[8usize]
    let vc = usize(z[9usize])
    let mtry = usize(z[10usize])
    let bties = z[11usize] > 0.5f64
    let seed = i64(z[12usize])
    let (nl, e1) = mem.alloc[usize](a, pz)
    let (isord, e2) = mem.alloc[bool](a, pz)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < pz {
        let v = z[13usize + j]
        nl[j] = 0usize
        isord[j] = false
        if v > 0.5f64 { nl[j] = usize(v) }
        // an ordered factor of L levels is coded 1000000 + L with its level indices 1 .. L as the column
        if v < -0.5f64 {
            nl[j] = 1000000usize + usize(0.0f64 - v)
            isord[j] = true
        }
        j += 1usize
    }
    let b0 = 13usize + pz
    let xr = z[b0..b0 + n * kx]
    let (zz, e3) = mem.alloc[f64](a, n * pz)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    j = 0usize
    while j < pz {
        var i = 0usize
        while i < n {
            zz[j * n + i] = z[b0 + n * kx + j * n + i]
            if isord[j] { zz[j * n + i] += 1.0f64 }
            i += 1usize
        }
        j += 1usize
    }
    let y = z[b0 + n * kx + n * pz..b0 + n * kx + n * pz + n]
    var none: []const f64 = zero
    var nonu: []const usize = zero
    let (o, e4) = mb.lmtree_x(a, xr, kx, y, n, zz, pz, nl, 0usize, alpha, bonf, minsize, maxdepth, trim, false, 0usize, none, none, nonu, vc, mtry, bties, seed)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    if sel == 1usize { ret f64(o.count) }
    var s = 0.0f64
    var id = 1usize
    while id <= o.count {
        let k = id - 1usize
        let inner = o.vr[k] != 0i64
        if sel == 2usize { s += f64(id) * f64(o.vr[k]) }
        if sel == 3usize && inner {
            let v = usize(o.vr[k] - 1i64)
            if nl[v] == 0usize || isord[v] {
                s += f64(id) * o.brk[k]
            } else {
                var t = 0.0f64
                var l = 0usize
                while l < nl[v] {
                    let d = o.lmap[k * o.maxlev + l]
                    if d >= 0i64 { t += f64(l + 1usize) * f64(d + 1i64) }
                    l += 1usize
                }
                s += f64(id) * t
            }
        }
        if sel == 4usize { s += f64(id) * o.nobs[k] }
        if sel == 5usize && inner { s += f64(id) * o.pval[k] }
        if sel == 6usize {
            var q = 0usize
            while q < o.k {
                s += f64(id) * f64(q + 1usize) * o.coef[k * o.k + q]
                q += 1usize
            }
        }
        if sel == 7usize { s += f64(id) * o.objfun[k] }
        if sel == 10usize || sel == 11usize {
            var q = 0usize
            while q < pz {
                var v = o.stat[k * pz + q]
                if sel == 11usize { v = o.adjp[k * pz + q] }
                if v == v { s += f64(id) * v }
                q += 1usize
            }
        }
        id += 1usize
    }
    if sel == 9usize {
        var i = 0usize
        while i < n {
            let nd = mb.predict_node(&o, nl, zz, n, i)
            s += f64(i + 1usize) * f64(nd)
            i += 1usize
        }
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partykitmobx.json")
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
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}

// the case selector, seed, mtry, breakties, then both answers
fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, be) = str.builder(a, 120usize)
    if be != ok { ret c.name }
    var b = initial
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[12usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[10usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[11usize])
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " want ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}
