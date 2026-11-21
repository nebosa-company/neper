// e.algo.stat.partykitmob.lmtree against partykit lmtree with case weights, an offset, clusters and the vcov settings opg, info and sandwich.
// tests/oracle/partykitmobopt.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partykitmobopt`; the argument layout is at the top of scripts/r_oracle/groups/partykitmobopt.R.

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
    let usew = z[10usize] > 0.5f64
    let useoff = z[11usize] > 0.5f64
    let usecl = z[12usize] > 0.5f64
    let (nl, e1) = mem.alloc[usize](a, pz)
    let (cl, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < pz {
        nl[j] = usize(z[13usize + j])
        j += 1usize
    }
    let b0 = 13usize + pz
    let wv = z[b0..b0 + n]
    let ov = z[b0 + n..b0 + 2usize * n]
    var i = 0usize
    while i < n {
        cl[i] = usize(z[b0 + 2usize * n + i])
        i += 1usize
    }
    let xr = z[b0 + 3usize * n..b0 + 3usize * n + n * kx]
    let zz = z[b0 + 3usize * n + n * kx..b0 + 3usize * n + n * kx + n * pz]
    let y = z[b0 + 3usize * n + n * kx + n * pz..b0 + 4usize * n + n * kx + n * pz]
    var none: []const f64 = zero
    var nonu: []const usize = zero
    var wa = none
    var oa = none
    var ca = nonu
    if usew { wa = wv }
    if useoff { oa = ov }
    if usecl { ca = cl }
    let (o, e3) = mb.lmtree(a, xr, kx, y, n, zz, pz, nl, 0usize, alpha, bonf, minsize, maxdepth, trim, false, 0usize, wa, oa, ca, vc)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    if sel == 1usize { ret f64(o.count) }
    var s = 0.0f64
    var id = 1usize
    while id <= o.count {
        let k = id - 1usize
        let inner = o.vr[k] != 0i64
        if sel == 2usize { s += f64(id) * f64(o.vr[k]) }
        if sel == 3usize && inner {
            let v = usize(o.vr[k] - 1i64)
            if nl[v] == 0usize {
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
    if sel == 9usize || sel == 14usize {
        i = 0usize
        while i < n {
            let nd = mb.predict_node(&o, nl, zz, n, i)
            s += f64(i + 1usize) * f64(nd)
            // as.constparty keeps the training response next to the fitted node ids
            if sel == 14usize { s += y[i] }
            i += 1usize
        }
        // as.party and as.constparty of the tree keep its nodes: the golden adds the node sums of both
        
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partykitmobopt.json")
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
