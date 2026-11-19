// phangorn::parsimony(tree, data, method = "fitch") for a binary tree and a DNA alignment: the Fitch small-parsimony score summed over the sites, with the ambiguity codes as sets of states (bit 1 A, 2 C, 4 G, 8 T; N is 15, R is 5).
// The tree is ape's edge list (parent and child columns, 0-based, tips 0 .. nt - 1, the root nt) in cladewise order, which puts every parent before its children.
//
// Not here: the other cost matrices (sankoff), non-binary trees, pratchet and the search, pml and the likelihood models, model selection, bootstrap.

use e.math
use e.math.nmath as nm
use e.math.opt as opt
use e.mem

fn fitch(a: *mem.Arena, par: []const f64, chd: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize) -> f64 {
    let nn = ne + 1usize
    let (c1, e1) = mem.alloc[usize](a, nn)
    let (c2, e2) = mem.alloc[usize](a, nn)
    let (set, e3) = mem.alloc[u32](a, nn)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < nn {
        c1[i] = nn
        c2[i] = nn
        i += 1usize
    }
    i = 0usize
    while i < ne {
        let p = usize(par[i])
        if c1[p] == nn {
            c1[p] = usize(chd[i])
        } else {
            c2[p] = usize(chd[i])
        }
        i += 1usize
    }
    var total = 0usize
    var s = 0usize
    while s < ns {
        i = 0usize
        while i < nt {
            set[i] = u32(data[i * ns + s])
            i += 1usize
        }
        // children after parents in the edge list: walking it backwards reaches the first child edge of a node after every edge below it
        var k = ne
        while k > 0usize {
            k -= 1usize
            let p = usize(par[k])
            if usize(chd[k]) == c1[p] {
                let l = set[c1[p]]
                let r = set[c2[p]]
                if (l & r) != 0u32 {
                    set[p] = l & r
                } else {
                    set[p] = l | r
                    total += 1usize
                }
            }
        }
        s += 1usize
    }
    ret f64(total)
}

// phangorn::upgma (weighted false) and wpgma (true) from a full n by n distance matrix d: out receives the n - 1 merge heights in merge order (half the merged distance), then the total edge length of the tree
fn upgma(a: *mem.Arena, d: []const f64, n: usize, weighted: bool, out: []f64) -> err {
    let (dm, e1) = mem.alloc[f64](a, n * n)
    let (sz, e2) = mem.alloc[f64](a, n)
    let (ht, e3) = mem.alloc[f64](a, n)
    let (alive, e4) = mem.alloc[bool](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var i = 0usize
    while i < n * n {
        dm[i] = d[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        sz[i] = 1.0f64
        ht[i] = 0.0f64
        alive[i] = true
        i += 1usize
    }
    var len = 0.0f64
    var m = 0usize
    while m + 1usize < n {
        var bi = n
        var bj = n
        var best = 0.0f64
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                if alive[i] && alive[j] && (bi == n || dm[i * n + j] < best) {
                    bi = i
                    bj = j
                    best = dm[i * n + j]
                }
                j += 1usize
            }
            i += 1usize
        }
        let h = best / 2.0f64
        out[m] = h
        len += (h - ht[bi]) + (h - ht[bj])
        var k = 0usize
        while k < n {
            if alive[k] && k != bi && k != bj {
                var nd = (dm[bi * n + k] + dm[bj * n + k]) / 2.0f64
                if !weighted { nd = (dm[bi * n + k] * sz[bi] + dm[bj * n + k] * sz[bj]) / (sz[bi] + sz[bj]) }
                dm[bi * n + k] = nd
                dm[k * n + bi] = nd
            }
            k += 1usize
        }
        sz[bi] = sz[bi] + sz[bj]
        ht[bi] = h
        alive[bj] = false
        m += 1usize
    }
    out[n - 1usize] = len
    ret ok
}

// phangorn::dist.hamming(ratio = TRUE) of tips i and j of an alignment of unambiguous states (bit sets as in fitch): the share of sites that differ; jc turns it into the Jukes-Cantor distance -3/4 log(1 - 4/3 p), the maximum
// likelihood distance of dist.ml(model = "JC69")
fn hamming(data: []const f64, ns: usize, i: usize, j: usize, jc: bool) -> f64 {
    var diff = 0.0f64
    var s = 0usize
    while s < ns {
        if data[i * ns + s] != data[j * ns + s] { diff += 1.0f64 }
        s += 1usize
    }
    let p = diff / f64(ns)
    if !jc { ret p }
    ret 0.0f64 - 0.75f64 * math.log[f64](1.0f64 - 4.0f64 / 3.0f64 * p)
}

// phangorn::parsimony(method = "sankoff", cost) of a tree (any number of children per node) on a DNA alignment: cost is the 4 by 4 row-major matrix of the price of a change from the row state to the column state
fn sankoff(a: *mem.Arena, par: []const f64, chd: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize, cost: []const f64) -> f64 {
    let nn = ne + 1usize
    let (cv, e1) = mem.alloc[f64](a, nn * 4usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var total = 0.0f64
    var s = 0usize
    while s < ns {
        var i = 0usize
        while i < nn {
            var st = 0usize
            while st < 4usize {
                cv[i * 4usize + st] = 0.0f64
                if i < nt {
                    let m = u32(data[i * ns + s])
                    if (m & (1u32 << u32(st))) == 0u32 { cv[i * 4usize + st] = 1.0e300f64 }
                }
                st += 1usize
            }
            i += 1usize
        }
        var k = ne
        while k > 0usize {
            k -= 1usize
            let p = usize(par[k])
            let c = usize(chd[k])
            var st = 0usize
            while st < 4usize {
                var best = 1.0e300f64
                var t = 0usize
                while t < 4usize {
                    let v = cost[st * 4usize + t] + cv[c * 4usize + t]
                    if v < best { best = v }
                    t += 1usize
                }
                cv[p * 4usize + st] += best
                st += 1usize
            }
        }
        var best = cv[nt * 4usize]
        var st = 1usize
        while st < 4usize {
            if cv[nt * 4usize + st] < best { best = cv[nt * 4usize + st] }
            st += 1usize
        }
        total += best
        s += 1usize
    }
    ret total
}

// the log-likelihood phangorn::pml(tree, data) gives for a tree with edge lengths bl under the Jukes-Cantor model (equal base frequencies, one rate), by Felsenstein pruning; ambiguity codes are the states they allow
fn jc_loglik(a: *mem.Arena, par: []const f64, chd: []const f64, bl: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize) -> f64 {
    let nn = ne + 1usize
    let (lv, e1) = mem.alloc[f64](a, nn * 4usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var ll = 0.0f64
    var s = 0usize
    while s < ns {
        var i = 0usize
        while i < nn {
            var st = 0usize
            while st < 4usize {
                lv[i * 4usize + st] = 1.0f64
                if i < nt {
                    let m = u32(data[i * ns + s])
                    if (m & (1u32 << u32(st))) == 0u32 { lv[i * 4usize + st] = 0.0f64 }
                }
                st += 1usize
            }
            i += 1usize
        }
        var k = ne
        while k > 0usize {
            k -= 1usize
            let p = usize(par[k])
            let c = usize(chd[k])
            let ex = math.exp[f64](0.0f64 - 4.0f64 * bl[k] / 3.0f64)
            let same = 0.25f64 + 0.75f64 * ex
            let diff = 0.25f64 - 0.25f64 * ex
            var tot = 0.0f64
            var t = 0usize
            while t < 4usize {
                tot += lv[c * 4usize + t]
                t += 1usize
            }
            var st = 0usize
            while st < 4usize {
                lv[p * 4usize + st] = lv[p * 4usize + st] * (diff * tot + (same - diff) * lv[c * 4usize + st])
                st += 1usize
            }
        }
        var site = 0.0f64
        var st = 0usize
        while st < 4usize {
            site += 0.25f64 * lv[nt * 4usize + st]
            st += 1usize
        }
        ll += math.log[f64](site)
        s += 1usize
    }
    ret ll
}

fn mul4(x: []const f64, y: []const f64, o: []f64) {
    var i = 0usize
    while i < 4usize {
        var j = 0usize
        while j < 4usize {
            var t = 0.0f64
            var k = 0usize
            while k < 4usize {
                t += x[i * 4usize + k] * y[k * 4usize + j]
                k += 1usize
            }
            o[i * 4usize + j] = t
            j += 1usize
        }
        i += 1usize
    }
}

// the 4 by 4 transition matrix exp(Q t) by scaling and squaring of a Taylor series
fn expm4(q: []const f64, t: f64, o: []f64) {
    var m: [16]f64 = zero
    var nrm = 0.0f64
    var i = 0usize
    while i < 16usize {
        m[i] = q[i] * t
        if math.abs[f64](m[i]) > nrm { nrm = math.abs[f64](m[i]) }
        i += 1usize
    }
    var sq = 0usize
    while nrm > 0.25f64 {
        nrm = nrm / 2.0f64
        sq += 1usize
    }
    let sc = 1.0f64 / f64(1usize << sq)
    i = 0usize
    while i < 16usize {
        m[i] = m[i] * sc
        i += 1usize
    }
    var term: [16]f64 = zero
    var nx: [16]f64 = zero
    var sum: [16]f64 = zero
    i = 0usize
    while i < 4usize {
        term[i * 5usize] = 1.0f64
        sum[i * 5usize] = 1.0f64
        i += 1usize
    }
    var k = 1usize
    while k <= 16usize {
        mul4(term[0usize..16usize], m[0usize..16usize], nx[0usize..16usize])
        i = 0usize
        while i < 16usize {
            term[i] = nx[i] / f64(k)
            sum[i] += term[i]
            i += 1usize
        }
        k += 1usize
    }
    var s2 = 0usize
    while s2 < sq {
        mul4(sum[0usize..16usize], sum[0usize..16usize], nx[0usize..16usize])
        i = 0usize
        while i < 16usize {
            sum[i] = nx[i]
            i += 1usize
        }
        s2 += 1usize
    }
    i = 0usize
    while i < 16usize {
        o[i] = sum[i]
        i += 1usize
    }
}

// the log-likelihood phangorn::pml(tree, data, model = "GTR", bf, Q) gives: base frequencies bf (A C G T) and the six exchangeabilities rates (AC AG AT CG CT GT), the rate matrix scaled to one expected change per unit length
fn gtr_site_lik(a: *mem.Arena, par: []const f64, chd: []const f64, bl: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize, bf: []const f64, rates: []const f64, mult: f64, sl: []f64) -> bool {
    var q: [16]f64 = zero
    var r: [16]f64 = zero
    r[1usize] = rates[0usize]
    r[2usize] = rates[1usize]
    r[3usize] = rates[2usize]
    r[6usize] = rates[3usize]
    r[7usize] = rates[4usize]
    r[11usize] = rates[5usize]
    var i = 0usize
    while i < 4usize {
        var j = i + 1usize
        while j < 4usize {
            r[j * 4usize + i] = r[i * 4usize + j]
            j += 1usize
        }
        i += 1usize
    }
    var rate = 0.0f64
    i = 0usize
    while i < 4usize {
        var rs = 0.0f64
        var j = 0usize
        while j < 4usize {
            if j != i {
                q[i * 4usize + j] = r[i * 4usize + j] * bf[j]
                rs += q[i * 4usize + j]
            }
            j += 1usize
        }
        q[i * 5usize] = 0.0f64 - rs
        rate += bf[i] * rs
        i += 1usize
    }
    i = 0usize
    while i < 16usize {
        q[i] = q[i] / rate
        i += 1usize
    }
    let nn = ne + 1usize
    let (lv, e1) = mem.alloc[f64](a, nn * 4usize)
    let (pm, e2) = mem.alloc[f64](a, ne * 16usize)
    if e1 != ok || e2 != ok { ret false }
    var k = 0usize
    while k < ne {
        expm4(q[0usize..16usize], bl[k] * mult, pm[k * 16usize..k * 16usize + 16usize])
        k += 1usize
    }
    var s = 0usize
    while s < ns {
        i = 0usize
        while i < nn {
            var st = 0usize
            while st < 4usize {
                lv[i * 4usize + st] = 1.0f64
                if i < nt {
                    let m = u32(data[i * ns + s])
                    if (m & (1u32 << u32(st))) == 0u32 { lv[i * 4usize + st] = 0.0f64 }
                }
                st += 1usize
            }
            i += 1usize
        }
        k = ne
        while k > 0usize {
            k -= 1usize
            let p = usize(par[k])
            let c = usize(chd[k])
            var st = 0usize
            while st < 4usize {
                var t2 = 0.0f64
                var t = 0usize
                while t < 4usize {
                    t2 += pm[k * 16usize + st * 4usize + t] * lv[c * 4usize + t]
                    t += 1usize
                }
                lv[p * 4usize + st] = lv[p * 4usize + st] * t2
                st += 1usize
            }
        }
        var site = 0.0f64
        var st = 0usize
        while st < 4usize {
            site += bf[st] * lv[nt * 4usize + st]
            st += 1usize
        }
        sl[s] = site
        s += 1usize
    }
    ret true
}

fn gtr_loglik(a: *mem.Arena, par: []const f64, chd: []const f64, bl: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize, bf: []const f64, rates: []const f64) -> f64 {
    ret gtr_loglik_gamma(a, par, chd, bl, ne, nt, data, ns, bf, rates, 1.0f64, 1usize, 0.0f64)
}

// as gtr_loglik with a share inv of invariant sites (rates over the rest rescaled by 1 / (1 - inv)) and the rate over sites discretised gamma(shape) in k categories, each the mean of its bin of the distribution (phangorn's discrete.gamma) and equally likely; k = 1 is a single rate of one
fn gtr_loglik_gamma(a: *mem.Arena, par: []const f64, chd: []const f64, bl: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize, bf: []const f64, rates: []const f64, shape: f64, k: usize, inv: f64) -> f64 {
    let (sl, e1) = mem.alloc[f64](a, ns)
    let (acc, e2) = mem.alloc[f64](a, ns)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var s = 0usize
    while s < ns {
        acc[s] = 0.0f64
        s += 1usize
    }
    var prev = 0.0f64
    var c = 0usize
    while c < k {
        var mult = 1.0f64
        var cur = 1.0f64
        if k > 1usize {
            if c + 1usize < k {
                let qt = nm.qgamma(f64(c + 1usize) / f64(k), shape, 1.0f64 / shape, true, false)
                cur = nm.pgamma(qt * shape, shape + 1.0f64, 1.0f64, true, false)
            }
            mult = (cur - prev) * f64(k)
            prev = cur
        }
        mult = mult / (1.0f64 - inv)
        if !gtr_site_lik(a, par, chd, bl, ne, nt, data, ns, bf, rates, mult, sl) { ret 0.0f64 / 0.0f64 }
        s = 0usize
        while s < ns {
            acc[s] += (1.0f64 - inv) * sl[s] / f64(k)
            s += 1usize
        }
        c += 1usize
    }
    var ll = 0.0f64
    s = 0usize
    while s < ns {
        var share = 0u32
        share = 15u32
        var i = 0usize
        while i < nt {
            share = share & u32(data[i * ns + s])
            i += 1usize
        }
        var cst = 0.0f64
        var st = 0usize
        while st < 4usize {
            if (share & (1u32 << u32(st))) != 0u32 { cst += bf[st] }
            st += 1usize
        }
        acc[s] += inv * cst
        ll += math.log[f64](acc[s])
        s += 1usize
    }
    ret ll
}

// the non-trivial splits of a tree (ape edge list, cladewise, 0-based; tips 0 .. nt - 1 with at most 63 tips): each clade below an internal edge as a bit mask of its tips, complemented when it holds tip 0, without duplicates (the two root edges of a rooted tree give one split);
// returns how many were written to out
fn splits(a: *mem.Arena, par: []const f64, chd: []const f64, ne: usize, nt: usize, out: []u64) -> usize {
    let nn = ne + 1usize
    let (mask, e1) = mem.alloc[u64](a, nn)
    if e1 != ok { ret 0usize }
    var i = 0usize
    while i < nn {
        mask[i] = 0u64
        if i < nt { mask[i] = 1u64 << u64(i) }
        i += 1usize
    }
    let all = (1u64 << u64(nt)) - 1u64
    var cnt = 0usize
    var k = ne
    while k > 0usize {
        k -= 1usize
        let c = usize(chd[k])
        let p = usize(par[k])
        mask[p] = mask[p] | mask[c]
        if c >= nt {
            var m = mask[c]
            if (m & 1u64) != 0u64 { m = all ^ m }
            var sz = 0usize
            var t = 0usize
            while t < nt {
                if (m & (1u64 << u64(t))) != 0u64 { sz += 1usize }
                t += 1usize
            }
            if sz >= 2usize && sz + 2usize <= nt {
                var dup = false
                var u = 0usize
                while u < cnt {
                    if out[u] == m { dup = true }
                    u += 1usize
                }
                if !dup {
                    out[cnt] = m
                    cnt += 1usize
                }
            }
        }
    }
    ret cnt
}

// phangorn::RF.dist (normalize = FALSE) of two trees on the same tips: the number of splits in one and not the other, each way
fn rf_dist(a: *mem.Arena, par1: []const f64, chd1: []const f64, ne1: usize, par2: []const f64, chd2: []const f64, ne2: usize, nt: usize) -> f64 {
    let (s1, e1) = mem.alloc[u64](a, ne1 + 1usize)
    let (s2, e2) = mem.alloc[u64](a, ne2 + 1usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let n1 = splits(a, par1, chd1, ne1, nt, s1)
    let n2 = splits(a, par2, chd2, ne2, nt, s2)
    var common = 0usize
    var i = 0usize
    while i < n1 {
        var j = 0usize
        while j < n2 {
            if s1[i] == s2[j] { common += 1usize }
            j += 1usize
        }
        i += 1usize
    }
    ret f64(n1 + n2 - 2usize * common)
}

type EdgeCtx = struct { a: *mem.Arena, par: []const f64, chd: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize, bl: []f64, q: []f64 }

// minus the Jukes-Cantor log-likelihood at the log edge lengths x
fn edge_f(c: *EdgeCtx, x: []const f64) -> f64 {
    let start = mem.mark(c.a)
    var k = 0usize
    while k < c.ne {
        c.bl[k] = math.exp[f64](x[k])
        k += 1usize
    }
    let ll = jc_loglik(c.a, c.par, c.chd, c.bl, c.ne, c.nt, c.data, c.ns)
    mem.reset(c.a, start)
    ret 0.0f64 - ll
}

fn edge_g(c: *EdgeCtx, x: []const f64, g: []f64) {
    let m = x.len
    var i = 0usize
    while i < m {
        c.q[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        let h = 1.0e-6f64
        c.q[i] = x[i] + h
        let fp = edge_f(c, c.q[0usize..m])
        c.q[i] = x[i] - h
        let fm = edge_f(c, c.q[0usize..m])
        c.q[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// optim.pml(pml(tree, data), optEdge = TRUE) under Jukes-Cantor: the edge lengths bl (starting values on entry, optimised on exit) maximising the likelihood, by BFGS on their logarithms; returns the log-likelihood there
fn optim_edges_jc(a: *mem.Arena, par: []const f64, chd: []const f64, bl: []f64, ne: usize, nt: usize, data: []const f64, ns: usize) -> f64 {
    let (x, e1) = mem.alloc[f64](a, ne)
    let (qq, e2) = mem.alloc[f64](a, ne)
    let (scr, e3) = mem.alloc[f64](a, ne * ne + 6usize * ne + 16usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < ne {
        x[k] = math.log[f64](bl[k])
        k += 1usize
    }
    var c = EdgeCtx { a: a, par: par, chd: chd, ne: ne, nt: nt, data: data, ns: ns, bl: bl, q: qq }
    var round = 0usize
    while round < 2usize {
        let (r, e4) = opt.bfgs[EdgeCtx](&c, edge_f, edge_g, x, 1.0e-10f64, 400u32, scr)
        if e4 != ok { ret 0.0f64 / 0.0f64 }
        k = 0usize
        while k < ne {
            if x[k] < -18.0f64 { x[k] = -18.0f64 }
            k += 1usize
        }
        round += 1usize
    }
    k = 0usize
    while k < ne {
        bl[k] = math.exp[f64](x[k])
        k += 1usize
    }
    ret 0.0f64 - edge_f(&c, x)
}
