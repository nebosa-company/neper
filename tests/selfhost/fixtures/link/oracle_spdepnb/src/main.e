// e.algo.stat.spdepnb against spdep. tests/oracle/spdepnb.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spdepnb`; the argument layout is at the top of scripts/r_oracle/groups/spdepnb.R.

use e.algo.stat.spdepnb as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn cs(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * (1.0f64 + f64(i) / 7.0f64)
        i += 1usize
    }
    ret s
}

// builds the neighbour matrix and the weight matrix from the header; z[0..5] = kind, p1, p2, style, self, then n and co
fn build(a: *mem.Arena, z: []const f64, adj: []f64, w: []f64) -> err {
    let kind = usize(z[0usize])
    let n = usize(z[5usize])
    let co = z[6usize..6usize + 2usize * n]
    var e: err = ok
    if kind == 0usize || kind == 3usize { e = sp.knn(a, co, n, usize(z[1usize]), adj) }
    if kind == 1usize { sp.dnear(co, n, z[1usize], z[2usize], adj) }
    if kind == 2usize { e = sp.tri(a, co, n, adj) }
    if e != ok { ret e }
    if kind == 3usize {
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if adj[i * n + j] == 1.0f64 { adj[j * n + i] = 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
    }
    if usize(z[4usize]) == 1usize {
        var i = 0usize
        while i < n {
            adj[i * n + i] = 1.0f64
            i += 1usize
        }
    }
    sp.listw(adj, n, usize(z[3usize]), w)
    ret ok
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "poly") {
        let np = usize(z[1usize])
        let (padj, pe) = mem.alloc[f64](a, np * np)
        if pe != ok { ret nan }
        sp.poly(z[3usize + np..z.len], z[3usize..3usize + np], np, z[2usize], usize(z[0usize]), padj)
        var s = 0.0f64
        var i = 0usize
        while i < np * np {
            s += padj[i] * f64((i / np + 1usize) * (i % np + 1usize))
            i += 1usize
        }
        ret s
    }
    let n = usize(z[5usize])
    let (adj, e1) = mem.alloc[f64](a, n * n)
    let (w, e2) = mem.alloc[f64](a, n * n)
    let (out, e3) = mem.alloc[f64](a, 5usize * n + 200usize)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    if build(a, z, adj, w) != ok { ret nan }
    let h = 6usize + 2usize * n
    let nm = c.name
    if str.eq(nm, "nb") {
        var s = 0.0f64
        var i = 0usize
        while i < n * n {
            s += adj[i] * f64((i / n + 1usize) * (i % n + 1usize))
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "lw") {
        var s = 0.0f64
        var i = 0usize
        while i < n * n {
            s += w[i] * (f64(((i / n + 1usize) * (i % n + 1usize)) % 97usize) + 0.5f64)
            i += 1usize
        }
        ret s
    }
    let x = z[h..h + n]
    let p = z[h + n..z.len]
    if str.eq(nm, "moran") {
        sp.moran_test(x, w, n, usize(p[0usize]), usize(p[1usize]), usize(p[2usize]), usize(p[3usize]), out)
        ret out[usize(p[4usize])]
    }
    if str.eq(nm, "geary") {
        sp.geary_test(x, w, n, usize(p[0usize]), usize(p[1usize]), out)
        ret out[usize(p[2usize])]
    }
    if str.eq(nm, "G") {
        sp.global_g(x, w, n, usize(p[0usize]), out)
        ret out[usize(p[1usize])]
    }
    if str.eq(nm, "jc") {
        sp.join_count(x, w, n, usize(p[0usize]), usize(p[1usize]), usize(p[2usize]), out)
        ret out[usize(p[3usize])]
    }
    if str.eq(nm, "lmoran") {
        sp.local_moran(x, w, n, usize(p[0usize]), usize(p[1usize]), usize(p[2usize]), usize(p[3usize]), out)
        var col: [64]f64 = zero
        var i = 0usize
        while i < n {
            col[i] = out[5usize * i + usize(p[4usize])]
            i += 1usize
        }
        ret cs(col[0usize..n])
    }
    if str.eq(nm, "lG") {
        sp.local_g(x, w, n, usize(p[0usize]), usize(p[1usize]), out)
        var col: [64]f64 = zero
        var i = 0usize
        while i < n {
            col[i] = out[5usize * i + usize(p[2usize])]
            i += 1usize
        }
        ret cs(col[0usize..n])
    }
    if str.eq(nm, "mc") {
        let nsim = usize(p[0usize])
        let (sims, e4) = mem.alloc[f64](a, nsim + 3usize)
        if e4 != ok { ret nan }
        if sp.moran_mc(a, x, w, n, nsim, i64(p[1usize]), usize(p[2usize]), sims) != ok { ret nan }
        let k = usize(p[3usize])
        if k == 0usize { ret cs(sims[0usize..nsim + 1usize]) }
        ret sims[nsim + k - 1usize]
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spdepnb.json")
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
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    let _ = str.push(&b, " #")
                    let _ = str.push_f64(&b, f64(at))
                    let _ = str.push(&b, " kind/style/n ")
                    let _ = str.push_f64(&b, c.args[0usize])
                    let _ = str.push(&b, "/")
                    let _ = str.push_f64(&b, c.args[3usize])
                    let _ = str.push(&b, "/")
                    let _ = str.push_f64(&b, c.args[5usize])
                    let _ = str.push(&b, " tail ")
                    let _ = str.push_f64(&b, c.args[c.args.len - 2usize])
                    let _ = str.push(&b, ",")
                    let _ = str.push_f64(&b, c.args[c.args.len - 1usize])
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " R ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
