// R leaps::regsubsets with nbest = 1: the best subset of each size by residual sum of squares, by exhaustive search,
// forward selection or backward elimination, and the summary statistics (rsq, adjusted r squared, Mallows Cp, BIC) as
// summary.regsubsets defines them, all with an intercept.
//
// Not here: seqrep, nbest > 1, force.in and force.out, weights, the branch-and-bound of the package (an exhaustive
// enumeration returns the same subsets; it is exponential in the number of variables).

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

// the residual sum of squares of y on an intercept and the columns of x selected by `mask` (bit j = column j)
fn subset_rss(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, mask: u32) -> f64 {
    var k = 0usize
    var j = 0usize
    while j < p {
        if (mask >> u32(j)) & 1u32 == 1u32 { k += 1usize }
        j += 1usize
    }
    let (d, e1) = mem.alloc[f64](a, n * (k + 1usize))
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    var c = 1usize
    j = 0usize
    while j < p {
        if (mask >> u32(j)) & 1u32 == 1u32 {
            i = 0usize
            while i < n {
                d[c * n + i] = x[j * n + i]
                i += 1usize
            }
            c += 1usize
        }
        j += 1usize
    }
    let (fit, fe) = decomp.lm_fit(a, d, n, k + 1usize, y, 1.0e-11f64)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret s
}

// the weighted residual sum of squares, sum w (y - fit)^2, for observation weights given as their square roots
fn subset_rss_w(a: *mem.Arena, x: []const f64, y: []const f64, sw: []const f64, n: usize, p: usize, mask: u32) -> f64 {
    var k = 0usize
    var j = 0usize
    while j < p {
        if (mask >> u32(j)) & 1u32 == 1u32 { k += 1usize }
        j += 1usize
    }
    let (d, e1) = mem.alloc[f64](a, n * (k + 1usize))
    let (yw, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = sw[i]
        yw[i] = y[i] * sw[i]
        i += 1usize
    }
    var c = 1usize
    j = 0usize
    while j < p {
        if (mask >> u32(j)) & 1u32 == 1u32 {
            i = 0usize
            while i < n {
                d[c * n + i] = x[j * n + i] * sw[i]
                i += 1usize
            }
            c += 1usize
        }
        j += 1usize
    }
    let (fit, fe) = decomp.lm_fit(a, d, n, k + 1usize, yw, 1.0e-11f64)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret t
}

fn popcount(m: u32) -> usize {
    var c = 0usize
    var t = m
    while t > 0u32 {
        c += usize(t & 1u32)
        t = t >> 1u32
    }
    ret c
}

// method 0 exhaustive, 1 forward, 2 backward; masks[k - 1] and rss[k - 1] receive the best subset of k variables
fn regsubsets(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nvmax: usize, method: u8, masks: []u32, rss: []f64) {
    let total = u32(1usize << p)
    if method == 0u8 {
        var k = 1usize
        while k <= nvmax {
            var best = 1.0e300f64
            var bm = 0u32
            var m = 1u32
            while m < total {
                if popcount(m) == k {
                    let r = subset_rss(a, x, y, n, p, m)
                    if r < best {
                        best = r
                        bm = m
                    }
                }
                m += 1u32
            }
            masks[k - 1usize] = bm
            rss[k - 1usize] = best
            k += 1usize
        }
        ret
    }
    if method == 1u8 {
        var cur = 0u32
        var k = 1usize
        while k <= nvmax {
            var best = 1.0e300f64
            var bm = cur
            var j = 0usize
            while j < p {
                if (cur >> u32(j)) & 1u32 == 0u32 {
                    let cand = cur | (1u32 << u32(j))
                    let r = subset_rss(a, x, y, n, p, cand)
                    if r < best {
                        best = r
                        bm = cand
                    }
                }
                j += 1usize
            }
            cur = bm
            masks[k - 1usize] = cur
            rss[k - 1usize] = best
            k += 1usize
        }
        ret
    }
    // backward: start from all variables and drop the one whose removal costs the least
    var cur = total - 1u32
    var k = p
    while k >= 1usize {
        if k <= nvmax {
            masks[k - 1usize] = cur
            rss[k - 1usize] = subset_rss(a, x, y, n, p, cur)
        }
        if k == 1usize { break }
        var best = 1.0e300f64
        var bm = cur
        var j = 0usize
        while j < p {
            if (cur >> u32(j)) & 1u32 == 1u32 {
                let cand = cur & ~(1u32 << u32(j))
                let r = subset_rss(a, x, y, n, p, cand)
                if r < best {
                    best = r
                    bm = cand
                }
            }
            j += 1usize
        }
        cur = bm
        k -= 1usize
    }
}

// summary.regsubsets for a model of k variables with residual sum of squares rss: (rsq, adjr2, cp, bic);
// nullrss the centred total sum of squares and fullrss the residual sum of squares of the model with all p variables
fn summarise(n: usize, p: usize, k: usize, rss: f64, nullrss: f64, fullrss: f64) -> (f64, f64, f64, f64) {
    let n1 = f64(n - 1usize)
    let i = f64(k + 1usize)
    let vr = rss / nullrss
    let sigma2 = fullrss / (n1 + 1.0f64 - f64(p + 1usize))
    let adj = 1.0f64 - vr * n1 / (n1 + 1.0f64 - i)
    let cp = rss / sigma2 - (n1 + 1.0f64 - 2.0f64 * i)
    let bic = (n1 + 1.0f64) * math.log[f64](vr) + i * math.log[f64](n1 + 1.0f64)
    ret (1.0f64 - vr, adj, cp, bic)
}

// regsubsets(nbest, nvmax, force.in, force.out) by exhaustive search: for each size s (variables including the forced-in ones,
// from the number forced in plus one up to nvmax or the number allowed), the nbest subsets with the smallest residual sum of
// squares, best first. Slot s * nbest + j of masks and rss holds the j-th best of size s; an empty slot has rss 1e35.
fn best_subsets(a: *mem.Arena, x: []const f64, y: []const f64, sw: []const f64, n: usize, p: usize, nvmax: usize, nbest: usize, fin: u32, fout: u32, masks: []u32, rss: []f64) {
    let total = u32(1usize << p)
    var i = 0usize
    while i < (nvmax + 1usize) * nbest {
        masks[i] = 0u32
        rss[i] = 1.0e35f64
        i += 1usize
    }
    let nf = popcount(fin)
    var m = 1u32
    while m < total {
        if (m & fin) == fin && (m & fout) == 0u32 {
            let s = popcount(m)
            if s > nf && s <= nvmax {
                let r = subset_rss_w(a, x, y, sw, n, p, m)
                // insert into the sorted top nbest of size s
                var j = 0usize
                while j < nbest && rss[s * nbest + j] <= r { j += 1usize }
                if j < nbest {
                    var q = nbest - 1usize
                    while q > j {
                        rss[s * nbest + q] = rss[s * nbest + q - 1usize]
                        masks[s * nbest + q] = masks[s * nbest + q - 1usize]
                        q -= 1usize
                    }
                    rss[s * nbest + j] = r
                    masks[s * nbest + j] = m
                }
            }
        }
        m += 1u32
    }
}

fn vmove(ord: []usize, from: usize, to: usize) {
    // positions are 1-based as in leaps; ord[pos - 1] is the variable at that position
    let v = ord[from - 1usize]
    if from > to {
        var q = from
        while q > to {
            ord[q - 1usize] = ord[q - 2usize]
            q -= 1usize
        }
    } else {
        var q = from
        while q < to {
            ord[q - 1usize] = ord[q]
            q += 1usize
        }
    }
    ord[to - 1usize] = v
}

// the model of the variables at positions 2 .. upto (position 1 is the intercept), as a bitmask over the columns of x
fn prefix_mask(ord: []const usize, upto: usize) -> u32 {
    var m = 0u32
    var q = 2usize
    while q <= upto {
        m = m | (1u32 << u32(ord[q - 1usize]))
        q += 1usize
    }
    ret m
}

// regsubsets(method = "seqrep", nbest = 1, force.in, force.out): the initial ordering (intercept, forced in, free, forced out)
// is reported as nested subsets, then the sequential replacement of the package improves each size; best[k - 1] the best
// subset found with k variables (including the forced ones), 1e35 where none was reported
fn seqrep(a: *mem.Arena, x: []const f64, y: []const f64, sw: []const f64, n: usize, p: usize, nvmax: usize, fin: u32, fout: u32, masks: []u32, rss: []f64) {
    let (ord, e1) = mem.alloc[usize](a, p + 2usize)
    if e1 != ok { ret }
    // positions 1 .. last: intercept (variable index unused), forced in, free, then the forced out are left out of the search
    ord[0usize] = 0usize
    var pos = 2usize
    var j = 0usize
    while j < p {
        if (fin >> u32(j)) & 1u32 == 1u32 {
            ord[pos - 1usize] = j
            pos += 1usize
        }
        j += 1usize
    }
    let first = pos
    j = 0usize
    while j < p {
        if (fin >> u32(j)) & 1u32 == 0u32 && (fout >> u32(j)) & 1u32 == 0u32 {
            ord[pos - 1usize] = j
            pos += 1usize
        }
        j += 1usize
    }
    let last = pos - 1usize
    var k = 0usize
    while k < nvmax {
        masks[k] = 0u32
        rss[k] = 1.0e35f64
        k += 1usize
    }
    let nvm = nvmax + 1usize
    // INITR: the nested subsets of the initial order
    var row = first
    while row <= nvm && row <= last {
        let m = prefix_mask(ord, row)
        let r = subset_rss_w(a, x, y, sw, n, p, m)
        if r < rss[row - 2usize] {
            rss[row - 2usize] = r
            masks[row - 2usize] = m
        }
        row += 1usize
    }
    var nv = nvm
    if last - 1usize < nv { nv = last - 1usize }
    var size = first
    while size <= nv {
        var count = 0usize
        var start = first
        while true {
            var ssred = 0.0f64
            var best = 0usize
            var from = 0usize
            var i = start
            while i <= size {
                // ADD1: positions size .. last added to the first size - 1 variables
                let base = prefix_mask(ord, size - 1usize)
                let rss0 = subset_rss_w(a, x, y, sw, n, p, base)
                var smax = 0.0f64
                var jmax = 0usize
                var q = size
                while q <= last {
                    let rq = subset_rss_w(a, x, y, sw, n, p, base | (1u32 << u32(ord[q - 1usize])))
                    let red = rss0 - rq
                    if red > smax {
                        smax = red
                        jmax = q
                    }
                    q += 1usize
                }
                if jmax > size {
                    // EXADD1 reports the best candidate of this size
                    let m = base | (1u32 << u32(ord[jmax - 1usize]))
                    let r = rss0 - smax
                    if r < rss[size - 2usize] {
                        rss[size - 2usize] = r
                        masks[size - 2usize] = m
                    }
                    if smax > ssred {
                        ssred = smax
                        best = jmax
                        if i < size { from = size + start - i - 1usize } else { from = size }
                    }
                }
                if i < size { vmove(ord, size, start) }
                i += 1usize
            }
            if best > size {
                if from < size { vmove(ord, from, size) }
                vmove(ord, best, first)
                count = 0usize
                start = first + 1usize
            } else {
                count += 1usize
            }
            if !(start <= size && count + start <= size) { break }
        }
        size += 1usize
    }
}
