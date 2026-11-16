// R permute: `shuffle` for the free and series (cyclic, optionally mirrored) restrictions within
// observations, over plots (strata, with their own type) and inside blocks, with the constant option
// for the within-plot permutation, and `numperms`. The random stream is that of e.algo.rand.r in the
// order doShuffle takes it (a flip is drawn before the plots are shuffled, even for free plots).
//
// Not here: grid designs, partitions, shuffleSet, allPerms and the validity checks of how().

use e.algo.rand.r as rng
use e.math
use e.mem

error Unsupported
error UnequalPlots

const FREE: u8 = 0u8
const SERIES: u8 = 1u8
const NONE: u8 = 2u8

// the design of one call
type Design = struct {
    plots: []const i64,
    blocks: []const i64,
    plot_type: u8,
    plot_mirror: bool,
    within_type: u8,
    within_mirror: bool,
    constant: bool,
}

// sample.int(n, size, replace = FALSE), 1-based, as shuffleFree draws it
fn free_draw(a: *mem.Arena, g: *rng.Rng, n: usize, size: usize) -> ([]i64, err) {
    let (r, e) = rng.sample_int(a, g, i64(n), i64(size), false)
    ret (r, e)
}

// shuffleSeries over x (length n): a cyclic shift, reversed when mirrored; start and flip are
// supplied (>= 0, flip 0 or 1) or drawn when negative
fn series_order(a: *mem.Arena, g: *rng.Rng, n: usize, mirror: bool, start0: i64, flip0: i64) -> ([]usize, err) {
    var none: []usize = zero
    var start = start0
    if start < 0i64 {
        let (s, se) = free_draw(a, g, n, 1usize)
        if se != ok { ret (none, se) }
        start = s[0usize]
    }
    let (out, oe) = mem.alloc[usize](a, n)
    if oe != ok { ret (none, oe) }
    var i = 0usize
    while i < n {
        // seq(start, length = n) %% n + 1, zero-based here
        out[i] = usize((start + i64(i)) % i64(n))
        i += 1usize
    }
    var rev = false
    if flip0 >= 0i64 && mirror {
        rev = flip0 == 1i64
    } else if mirror {
        if rng.unif(g) < 0.5f64 { rev = true }
    }
    if rev {
        var lo = 0usize
        var hi = n - 1usize
        while lo < hi {
            let t = out[lo]
            out[lo] = out[hi]
            out[hi] = t
            lo += 1usize
            hi -= 1usize
        }
    }
    ret (out, ok)
}

// one block: ind are the (0-based) observations of the block; answers ind[perm]
fn do_shuffle(a: *mem.Arena, g: *rng.Rng, ind: []const usize, d: *const Design) -> ([]usize, err) {
    var none: []usize = zero
    let n = ind.len
    let (perm, pe) = mem.alloc[usize](a, n)
    if pe != ok { ret (none, pe) }
    var i = 0usize
    while i < n {
        perm[i] = i
        i += 1usize
    }
    if d.plots.len == 0usize {
        if d.within_type == FREE {
            let (p, e) = free_draw(a, g, n, n)
            if e != ok { ret (none, e) }
            i = 0usize
            while i < n {
                perm[i] = usize(p[i]) - 1usize
                i += 1usize
            }
        } else if d.within_type == SERIES {
            let (p, e) = series_order(a, g, n, d.within_mirror, 0i64 - 1i64, 0i64 - 1i64)
            if e != ok { ret (none, e) }
            i = 0usize
            while i < n {
                perm[i] = p[i]
                i += 1usize
            }
        }
    } else {
        // plot labels of this block, in the block's order
        let (lab, le) = mem.alloc[i64](a, n)
        if le != ok { ret (none, le) }
        i = 0usize
        while i < n {
            lab[i] = d.plots[ind[i]]
            i += 1usize
        }
        // the distinct labels in ascending order
        let (levs, lve) = mem.alloc[i64](a, n)
        if lve != ok { ret (none, lve) }
        var nl = 0usize
        i = 0usize
        while i < n {
            var seen = false
            var j = 0usize
            while j < nl {
                if levs[j] == lab[i] { seen = true }
                j += 1usize
            }
            if !seen {
                levs[nl] = lab[i]
                nl += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < nl {
            var j = i
            while j > 0usize && levs[j - 1usize] > levs[j] {
                let t = levs[j]
                levs[j] = levs[j - 1usize]
                levs[j - 1usize] = t
                j -= 1usize
            }
            i += 1usize
        }
        if d.plot_type != NONE {
            let flip = rng.unif(g) < 0.5f64
            // the permutation of the plot levels
            let (pl, ple) = mem.alloc[usize](a, nl)
            if ple != ok { ret (none, ple) }
            if d.plot_type == FREE {
                let (p, e) = free_draw(a, g, nl, nl)
                if e != ok { ret (none, e) }
                i = 0usize
                while i < nl {
                    pl[i] = usize(p[i]) - 1usize
                    i += 1usize
                }
            } else {
                var fl = 0i64
                if flip { fl = 1i64 }
                let (p, e) = series_order(a, g, nl, d.plot_mirror, 0i64 - 1i64, fl)
                if e != ok { ret (none, e) }
                i = 0usize
                while i < nl {
                    pl[i] = p[i]
                    i += 1usize
                }
            }
            // out[positions of level i] = positions of level pl[i]
            let (sizes, se) = mem.alloc[usize](a, nl)
            if se != ok { ret (none, se) }
            i = 0usize
            while i < nl {
                sizes[i] = 0usize
                i += 1usize
            }
            i = 0usize
            while i < n {
                var j = 0usize
                while levs[j] != lab[i] { j += 1usize }
                sizes[j] += 1usize
                i += 1usize
            }
            i = 0usize
            while i < nl {
                if sizes[i] != sizes[pl[i]] { ret (none, UnequalPlots) }
                i += 1usize
            }
            // positions of each level in order
            var lvl = 0usize
            while lvl < nl {
                var from = 0usize
                var cnt = 0usize
                // positions of level pl[lvl]
                var q = 0usize
                while q < n {
                    if lab[q] == levs[pl[lvl]] {
                        // the cnt-th position of target level lvl
                        var w = 0usize
                        var seen = 0usize
                        while w < n {
                            if lab[w] == levs[lvl] {
                                if seen == cnt {
                                    perm[w] = q
                                    break
                                }
                                seen += 1usize
                            }
                            w += 1usize
                        }
                        cnt += 1usize
                    }
                    q += 1usize
                }
                lvl += 1usize
            }
        }
        if d.within_type != NONE {
            // plot labels along perm
            let (pl2, p2e) = mem.alloc[i64](a, n)
            if p2e != ok { ret (none, p2e) }
            i = 0usize
            while i < n {
                pl2[i] = lab[perm[i]]
                i += 1usize
            }
            let (sizes, se) = mem.alloc[usize](a, nl)
            if se != ok { ret (none, se) }
            i = 0usize
            while i < nl {
                sizes[i] = 0usize
                i += 1usize
            }
            i = 0usize
            while i < n {
                var j = 0usize
                while levs[j] != pl2[i] { j += 1usize }
                sizes[j] += 1usize
                i += 1usize
            }
            var same: []i64 = zero
            var start = 0i64 - 1i64
            var flip = 0i64 - 1i64
            if d.constant {
                if d.within_type == FREE {
                    let (s, e) = free_draw(a, g, sizes[0usize], sizes[0usize])
                    if e != ok { ret (none, e) }
                    same = s
                } else {
                    let (s, e) = free_draw(a, g, n / nl, 1usize)
                    if e != ok { ret (none, e) }
                    start = s[0usize]
                    if rng.unif(g) < 0.5f64 { flip = 1i64 } else { flip = 0i64 }
                }
            }
            let (tmp, te) = mem.alloc[usize](a, n)
            if te != ok { ret (none, te) }
            i = 0usize
            while i < n {
                tmp[i] = perm[i]
                i += 1usize
            }
            var lv = 0usize
            while lv < nl {
                let ng = sizes[lv]
                if ng > 1usize {
                    let (gr, gre) = mem.alloc[usize](a, ng)
                    if gre != ok { ret (none, gre) }
                    var m = 0usize
                    i = 0usize
                    while i < n {
                        if pl2[i] == levs[lv] {
                            gr[m] = perm[i]
                            m += 1usize
                        }
                        i += 1usize
                    }
                    let (sel, sele) = mem.alloc[usize](a, ng)
                    if sele != ok { ret (none, sele) }
                    if d.within_type == FREE {
                        if d.constant {
                            i = 0usize
                            while i < ng {
                                sel[i] = usize(same[i]) - 1usize
                                i += 1usize
                            }
                        } else {
                            let (p, e) = free_draw(a, g, ng, ng)
                            if e != ok { ret (none, e) }
                            i = 0usize
                            while i < ng {
                                sel[i] = usize(p[i]) - 1usize
                                i += 1usize
                            }
                        }
                    } else {
                        let (p, e) = series_order(a, g, ng, d.within_mirror, start, flip)
                        if e != ok { ret (none, e) }
                        i = 0usize
                        while i < ng {
                            sel[i] = p[i]
                            i += 1usize
                        }
                    }
                    m = 0usize
                    i = 0usize
                    while i < n {
                        if pl2[i] == levs[lv] {
                            tmp[i] = gr[sel[m]]
                            m += 1usize
                        }
                        i += 1usize
                    }
                }
                lv += 1usize
            }
            i = 0usize
            while i < n {
                perm[i] = tmp[i]
                i += 1usize
            }
        }
    }
    let (out, oe) = mem.alloc[usize](a, n)
    if oe != ok { ret (none, oe) }
    i = 0usize
    while i < n {
        out[i] = ind[perm[i]]
        i += 1usize
    }
    ret (out, ok)
}

// shuffle(n, control): the 1-based permutation of 1..n
fn shuffle(a: *mem.Arena, g: *rng.Rng, n: usize, d: *const Design) -> ([]usize, err) {
    var none: []usize = zero
    let (out, oe) = mem.alloc[usize](a, n)
    if oe != ok { ret (none, oe) }
    if d.blocks.len == 0usize {
        let (ind, ie) = mem.alloc[usize](a, n)
        if ie != ok { ret (none, ie) }
        var i = 0usize
        while i < n {
            ind[i] = i
            i += 1usize
        }
        let (r, re) = do_shuffle(a, g, ind, d)
        if re != ok { ret (none, re) }
        i = 0usize
        while i < n {
            out[i] = r[i] + 1usize
            i += 1usize
        }
        ret (out, ok)
    }
    // blocks in ascending label order
    let (levs, le) = mem.alloc[i64](a, n)
    if le != ok { ret (none, le) }
    var nl = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < nl {
            if levs[j] == d.blocks[i] { seen = true }
            j += 1usize
        }
        if !seen {
            levs[nl] = d.blocks[i]
            nl += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < nl {
        var j = i
        while j > 0usize && levs[j - 1usize] > levs[j] {
            let t = levs[j]
            levs[j] = levs[j - 1usize]
            levs[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
    var b = 0usize
    while b < nl {
        var cnt = 0usize
        i = 0usize
        while i < n {
            if d.blocks[i] == levs[b] { cnt += 1usize }
            i += 1usize
        }
        let (ind, ie) = mem.alloc[usize](a, cnt)
        if ie != ok { ret (none, ie) }
        var m = 0usize
        i = 0usize
        while i < n {
            if d.blocks[i] == levs[b] {
                ind[m] = i
                m += 1usize
            }
            i += 1usize
        }
        let (r, re) = do_shuffle(a, g, ind, d)
        if re != ok { ret (none, re) }
        // unsplit: the r[k] go to the positions of the block in order
        i = 0usize
        while i < cnt {
            out[ind[i]] = r[i] + 1usize
            i += 1usize
        }
        b += 1usize
    }
    ret (out, ok)
}

fn factorial(n: usize) -> f64 {
    var f = 1.0f64
    var i = 2usize
    while i <= n {
        f *= f64(i)
        i += 1usize
    }
    ret f
}

// numPerms for one block of n observations with plot sizes `tab` (empty: no plots)
fn block_perms(n: usize, tab: []const usize, plot_type: u8, plot_mirror: bool, within_type: u8, within_mirror: bool, constant: bool) -> f64 {
    var mult_wi = 1.0f64
    if within_type == SERIES {
        mult_wi = 2.0f64
        if n == 2usize { mult_wi = 1.0f64 }
    }
    var mult_p = 1.0f64
    if plot_type == SERIES {
        mult_p = 2.0f64
        if tab.len == 2usize { mult_p = 1.0f64 }
    }
    var num_p = 1.0f64
    if tab.len > 0usize {
        if plot_type == FREE {
            num_p = factorial(tab.len)
        } else if plot_type == SERIES {
            num_p = f64(tab.len)
            if plot_mirror { num_p = mult_p * f64(tab.len) }
        }
    }
    var num_wi = 1.0f64
    if within_type == NONE {
        num_wi = 1.0f64
    } else if within_type == FREE {
        if tab.len > 0usize {
            var prod = 1.0f64
            var i = 0usize
            var cnt = tab.len
            if constant { cnt = 1usize }
            while i < cnt {
                if tab[i] >= 171usize { ret 1.0f64 / 0.0f64 }
                prod *= factorial(tab[i])
                i += 1usize
            }
            num_wi = prod
        } else {
            num_wi = factorial(n)
        }
    } else {
        if tab.len > 0usize {
            var same = true
            var i = 1usize
            while i < tab.len {
                if tab[i] != tab[0usize] { same = false }
                i += 1usize
            }
            if !same {
                var prod = 1.0f64
                i = 0usize
                while i < tab.len {
                    var multi = 2.0f64
                    if tab[i] == 2usize { multi = 1.0f64 }
                    if within_mirror { prod *= multi * f64(tab[i]) } else { prod *= f64(tab[i]) }
                    i += 1usize
                }
                num_wi = prod
            } else if within_mirror {
                if constant {
                    num_wi = mult_wi * f64(tab[0usize])
                } else {
                    var prod = 1.0f64
                    i = 0usize
                    while i < tab.len {
                        prod *= mult_wi * f64(tab[i])
                        i += 1usize
                    }
                    num_wi = prod
                }
            } else if constant {
                num_wi = f64(tab[0usize])
            } else {
                var prod = 1.0f64
                i = 0usize
                while i < tab.len {
                    prod *= f64(tab[i])
                    i += 1usize
                }
                num_wi = prod
            }
        } else if within_mirror {
            num_wi = mult_wi * f64(n)
        } else {
            num_wi = f64(n)
        }
    }
    ret num_p * num_wi
}

// permute::allPerms, rows written row-major (rows of n entries, 1-based values), the observed ordering omitted.
// kind 0 free (lexicographic), 1 series (cyclic shifts), 2 series with mirroring (shifts, then reversed shifts)
// within each block; `sizes` are the contiguous block sizes (one block = the whole sample), the first block varying
// slowest. Answers the number of rows.
fn all_perms(a: *mem.Arena, sizes: []const usize, kind: u8, out: []i64) -> (usize, err) {
    let nb = sizes.len
    var n = 0usize
    var b = 0usize
    var maxsz = 0usize
    while b < nb {
        n += sizes[b]
        if sizes[b] > maxsz { maxsz = sizes[b] }
        b += 1usize
    }
    // the list of local permutations of each block, as the offsets into `lists`
    let (cnt, e1) = mem.alloc[usize](a, nb)
    let (cur, e2) = mem.alloc[usize](a, nb)
    let (off, e3) = mem.alloc[usize](a, nb)
    let (tmp, e4) = mem.alloc[usize](a, maxsz + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0usize, e1) }
    var total = 0usize
    b = 0usize
    while b < nb {
        let m = sizes[b]
        var c = 1usize
        if kind == 0u8 {
            var f = 2usize
            while f <= m {
                c *= f
                f += 1usize
            }
        } else if kind == 1u8 || m <= 2usize { c = m } else { c = 2usize * m }
        cnt[b] = c
        off[b] = total
        total += c * m
        b += 1usize
    }
    let (lists, e5) = mem.alloc[i64](a, total)
    if e5 != ok { ret (0usize, e5) }
    b = 0usize
    while b < nb {
        let m = sizes[b]
        var r = 0usize
        if kind == 0u8 {
            var i = 0usize
            while i < m {
                tmp[i] = i
                i += 1usize
            }
            while true {
                i = 0usize
                while i < m {
                    lists[off[b] + r * m + i] = i64(tmp[i]) + 1i64
                    i += 1usize
                }
                r += 1usize
                // next lexicographic permutation
                var k = m
                var found = false
                while k >= 2usize {
                    if tmp[k - 2usize] < tmp[k - 1usize] {
                        found = true
                        break
                    }
                    k -= 1usize
                }
                if !found { break }
                var l = m - 1usize
                while tmp[l] < tmp[k - 2usize] { l -= 1usize }
                let t = tmp[k - 2usize]
                tmp[k - 2usize] = tmp[l]
                tmp[l] = t
                var lo = k - 1usize
                var hi = m - 1usize
                while lo < hi {
                    let u = tmp[lo]
                    tmp[lo] = tmp[hi]
                    tmp[hi] = u
                    lo += 1usize
                    hi -= 1usize
                }
            }
        } else {
            var s = 0usize
            while s < m {
                var i = 0usize
                while i < m {
                    lists[off[b] + r * m + i] = i64((i + s) % m) + 1i64
                    i += 1usize
                }
                r += 1usize
                s += 1usize
            }
            if kind == 2u8 && m > 2usize {
                s = 0usize
                while s < m {
                    var i = 0usize
                    while i < m {
                        lists[off[b] + r * m + i] = i64((s + m - i % m) % m) + 1i64
                        i += 1usize
                    }
                    r += 1usize
                    s += 1usize
                }
            }
        }
        cur[b] = 0usize
        b += 1usize
    }
    var rows = 0usize
    var first = true
    var go = true
    while go {
        if first {
            first = false
        } else {
            var col = 0usize
            b = 0usize
            while b < nb {
                var j = 0usize
                while j < sizes[b] {
                    out[rows * n + col + j] = lists[off[b] + cur[b] * sizes[b] + j] + i64(col)
                    j += 1usize
                }
                col += sizes[b]
                b += 1usize
            }
            rows += 1usize
        }
        // odometer: the last block varies fastest
        var k = nb
        var carry = true
        while carry && k > 0usize {
            k -= 1usize
            cur[k] += 1usize
            if cur[k] < cnt[k] { carry = false } else { cur[k] = 0usize }
        }
        if carry { go = false }
    }
    ret (rows, ok)
}
