// R arules::apriori by exhaustive subset counting for up to 20 items: the frequent itemsets (support >= supp) and the association rules (confidence >= conf) with a non-empty antecedent and a single-item consequent, up to maxlen items in all. Transactions are bit masks of items.
//
// Not here: the candidate-pruning search for many items, other targets (closed, maximal), measures beyond support, confidence and lift, and rule subsetting.

use e.math
use e.mem
use e.math.nmath_beta as nbh

// out: [number of frequent itemsets (size 1 .. maxlen), sum of their supports, number of rules (size 2 .. maxlen), sum of rule supports, sum of confidences, sum of lifts]
fn apriori(a: *mem.Arena, trans: []const u64, nitems: usize, supp: f64, conf: f64, maxlen: usize, out: []f64) -> err {
    let nt = f64(trans.len)
    let total = 1usize << nitems
    let (cnt, e1) = mem.alloc[u32](a, total)
    if e1 != ok { ret e1 }
    var m = 1usize
    while m < total {
        var c = 0u32
        var t = 0usize
        while t < trans.len {
            if (trans[t] & u64(m)) == u64(m) { c += 1u32 }
            t += 1usize
        }
        cnt[m] = c
        m += 1usize
    }
    cnt[0usize] = u32(trans.len)
    let need = math.ceil[f64](supp * nt - 1.0e-9f64)
    var nfreq = 0.0f64
    var sfreq = 0.0f64
    var nrule = 0.0f64
    var srule = 0.0f64
    var sconf = 0.0f64
    var slift = 0.0f64
    m = 1usize
    while m < total {
        var sz = 0usize
        var q = m
        while q > 0usize {
            sz += q & 1usize
            q = q >> 1usize
        }
        if sz <= maxlen && f64(cnt[m]) >= need {
            nfreq += 1.0f64
            sfreq += f64(cnt[m]) / nt
            if sz >= 2usize {
                // every proper non-empty subset as antecedent, the consequent a single item as in Borgelt apriori
                var l = (m - 1usize) & m
                while l > 0usize {
                    let r = m ^ l
                    if (r & (r - 1usize)) != 0usize {
                        l = (l - 1usize) & m
                        continue
                    }
                    let cf = f64(cnt[m]) / f64(cnt[l])
                    if cf >= conf - 1.0e-12f64 {
                        nrule += 1.0f64
                        srule += f64(cnt[m]) / nt
                        sconf += cf
                        slift += cf / (f64(cnt[r]) / nt)
                    }
                    l = (l - 1usize) & m
                }
            }
        }
        m += 1usize
    }
    out[0usize] = nfreq
    out[1usize] = sfreq
    out[2usize] = nrule
    out[3usize] = srule
    out[4usize] = sconf
    out[5usize] = slift
    ret ok
}

// the same rules as `apriori`, with the sums over the rules (finite values only) of the interest measures: out[0] leverage, 1 coverage, 2 cosine, 3 jaccard, 4 kulczynski, 5 phi, 6 addedValue,
// 7 conviction, 8 oddsRatio; out[9] the number of rules
fn apriori_measures(a: *mem.Arena, trans: []const u64, nitems: usize, supp: f64, conf: f64, maxlen: usize, out: []f64) -> err {
    let nt = f64(trans.len)
    let total = 1usize << nitems
    let (cnt, e1) = mem.alloc[u32](a, total)
    if e1 != ok { ret e1 }
    var m = 1usize
    while m < total {
        var c = 0u32
        var t = 0usize
        while t < trans.len {
            if (trans[t] & u64(m)) == u64(m) { c += 1u32 }
            t += 1usize
        }
        cnt[m] = c
        m += 1usize
    }
    cnt[0usize] = u32(trans.len)
    let need = math.ceil[f64](supp * nt - 1.0e-9f64)
    var k = 0usize
    while k < 10usize {
        out[k] = 0.0f64
        k += 1usize
    }
    m = 1usize
    while m < total {
        var sz = 0usize
        var q = m
        while q > 0usize {
            sz += q & 1usize
            q = q >> 1usize
        }
        if sz <= maxlen && sz >= 2usize && f64(cnt[m]) >= need {
            var l = (m - 1usize) & m
            while l > 0usize {
                let r = m ^ l
                if (r & (r - 1usize)) != 0usize {
                    l = (l - 1usize) & m
                    continue
                }
                let cf = f64(cnt[m]) / f64(cnt[l])
                if cf >= conf - 1.0e-12f64 {
                    let sx = f64(cnt[l]) / nt
                    let sy = f64(cnt[r]) / nt
                    let sxy = f64(cnt[m]) / nt
                    out[0usize] += sxy - sx * sy
                    out[1usize] += sx
                    out[2usize] += sxy / math.sqrt[f64](sx * sy)
                    out[3usize] += sxy / (sx + sy - sxy)
                    out[4usize] += 0.5f64 * (sxy / sx + sxy / sy)
                    let ph = (sxy - sx * sy) / math.sqrt[f64](sx * sy * (1.0f64 - sx) * (1.0f64 - sy))
                    if ph == ph && ph - ph == 0.0f64 { out[5usize] += ph }
                    out[6usize] += cf - sy
                    let cv = (1.0f64 - sy) / (1.0f64 - cf)
                    if cv - cv == 0.0f64 { out[7usize] += cv }
                    let n11 = sxy
                    let n10 = sx - sxy
                    let n01 = sy - sxy
                    let n00 = 1.0f64 - sx - sy + sxy
                    let orr = (n11 * n00) / (n10 * n01)
                    if orr - orr == 0.0f64 { out[8usize] += orr }
                    out[9usize] += 1.0f64
                }
                l = (l - 1usize) & m
            }
        }
        m += 1usize
    }
    ret ok
}

// the closed (no proper superset with the same support) and maximal (no frequent proper superset) frequent itemsets of any size: out[0] closed count, 1 sum of closed supports, 2 maximal count, 3 sum of
// maximal supports
fn closed_maximal(a: *mem.Arena, trans: []const u64, nitems: usize, supp: f64, out: []f64) -> err {
    let nt = f64(trans.len)
    let total = 1usize << nitems
    let (cnt, e1) = mem.alloc[u32](a, total)
    if e1 != ok { ret e1 }
    var m = 1usize
    while m < total {
        var c = 0u32
        var t = 0usize
        while t < trans.len {
            if (trans[t] & u64(m)) == u64(m) { c += 1u32 }
            t += 1usize
        }
        cnt[m] = c
        m += 1usize
    }
    let need = math.ceil[f64](supp * nt - 1.0e-9f64)
    var k = 0usize
    while k < 4usize {
        out[k] = 0.0f64
        k += 1usize
    }
    m = 1usize
    while m < total {
        if f64(cnt[m]) >= need {
            var closed = true
            var maximal = true
            var j = 0usize
            while j < nitems {
                if (m & (1usize << j)) == 0usize {
                    let sup = m | (1usize << j)
                    if cnt[sup] == cnt[m] { closed = false }
                    if f64(cnt[sup]) >= need { maximal = false }
                }
                j += 1usize
            }
            if closed {
                out[0usize] += 1.0f64
                out[1usize] += f64(cnt[m]) / nt
            }
            if maximal {
                out[2usize] += 1.0f64
                out[3usize] += f64(cnt[m]) / nt
            }
        }
        m += 1usize
    }
    ret ok
}

// the basic interest measures of arules from the counts of the 2 by 2 table of a rule (n11 both, n10 antecedent only, n01 consequent only, n00 neither); index into the list below
fn mx(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn basic_measure(n11: f64, n10: f64, n01: f64, n00: f64, which: usize) -> f64 {
    let n = n11 + n10 + n01 + n00
    let n1x = n11 + n10
    let nx1 = n11 + n01
    let n0x = n - n1x
    let nx0 = n - nx1
    if which == 0usize { ret n11 / n1x }
    if which == 1usize { ret n11 / nx1 }
    if which == 2usize { ret 2.0f64 * n11 / (n1x + nx1) }
    if which == 3usize { ret (n11 + n00) / n }
    if which == 4usize { ret ((n11 / nx1) + (n00 / nx0)) / 2.0f64 }
    if which == 5usize { ret n1x * nx0 / (n * n10) }
    if which == 6usize { ret n1x / n * ((n11 / n1x) * (n11 / n1x) + (n10 / n1x) * (n10 / n1x)) - (nx1 / n) * (nx1 / n) + n0x / n * ((n01 / n0x) * (n01 / n0x) + (n00 / n0x) * (n00 / n0x)) - (nx0 / n) * (nx0 / n) }
    if which == 7usize { ret n11 * n11 / n1x / n }
    if which == 8usize { ret (n11 / n1x) / (n01 / n0x) }
    let lev = n11 / n - (n1x * nx1 / (n * n))
    if which == 9usize { ret lev / (n1x / n * (1.0f64 - n1x / n)) }
    if which == 10usize { ret lev / mx(n11 / n * (1.0f64 - n1x / n), n1x / n * (nx1 / n - n11 / n)) }
    if which == 11usize { ret (n11 + n00) / ((n1x * nx1 + n0x * nx0) / n) * ((n1x * nx0 + n0x * nx1) / n) / (n10 + n01) }
    if which == 12usize { ret math.log[f64](((n11 + 1.0f64) * (n0x + 2.0f64)) / ((n01 + 1.0f64) * (n1x + 2.0f64))) / math.log[f64](10.0f64) }
    if which == 13usize { ret math.abs[f64](n1x - nx1) / (n1x + nx1 - n11) }
    if which == 14usize { ret (n * n11 + n * n00 - n1x * nx1 - n0x * nx0) / (n * n - n1x * nx1 - n0x * nx0) }
    if which == 15usize {
        let mxx = mx(nx1, nx0)
        ret (mx(n11, n10) + mx(n01, n00) - mxx) / (n - mxx)
    }
    if which == 16usize {
        let h1 = 0.0f64 - 1.0f64 * (n0x / n * math.log[f64](n0x / n) + n1x / n * math.log[f64](n1x / n))
        let h2 = 0.0f64 - 1.0f64 * (nx0 / n * math.log[f64](nx0 / n) + nx1 / n * math.log[f64](nx1 / n))
        var den = h1
        if h2 < h1 { den = h2 }
        ret (n00 / n * math.log[f64](n * n00 / (n0x * nx0)) + n01 / n * math.log[f64](n * n01 / (n0x * nx1)) + n10 / n * math.log[f64](n * n10 / (n1x * nx0)) + n11 / n * math.log[f64](n * n11 / (n1x * nx1))) / den
    }
    if which == 17usize { ret mx(n11 / n1x, n11 / nx1) }
    if which == 18usize { ret n11 / n * math.log[f64](n * n11 / (n1x * nx1)) + n10 / n * math.log[f64](n * n10 / (n1x * nx0)) }
    if which == 19usize { ret (n11 + 1.0f64) / (n1x + 2.0f64) }
    if which == 20usize { ret (n11 / n1x - nx1 / n) / (1.0f64 - nx1 / n) }
    if which == 21usize { ret n10 / n }
    if which == 22usize { ret (n1x - n10) / n10 }
    if which == 23usize { ret (n11 - n10) / n11 }
    if which == 24usize { ret (n11 - n10) / n1x }
    if which == 25usize { ret (n11 + n00) / n }
    if which == 26usize { ret (n11 / n1x + n00 / nx0) / 2.0f64 }
    if which == 27usize { ret (n11 - n10) / nx1 }
    if which == 28usize { ret nx0 / n - n10 / n1x }
    if which == 29usize { ret (n1x - n10) / (n1x * nx1 / n) - 1.0f64 }
    if which == 30usize {
        let orr = n11 * n00 / (n10 * n01)
        ret (orr - 1.0f64) / (orr + 1.0f64)
    }
    if which == 31usize {
        let orr = n11 * n00 / (n10 * n01)
        ret (math.sqrt[f64](orr) - 1.0f64) / (math.sqrt[f64](orr) + 1.0f64)
    }
    if which == 32usize { ret (n11 - n1x * nx1 / n) / math.sqrt[f64](n1x * nx1 / n) }
    if which == 33usize { ret (n10 - n1x * nx0 / n) / math.sqrt[f64](n1x * nx0 / n) }
    if which == 34usize { ret (n11 / n1x) - (n01 / n0x) }
    if which == 35usize { ret n * (n11 * n00 - n10 * n01) * (n11 * n00 - n10 * n01) / (n1x * n0x * nx1 * nx0) }
    if which == 36usize { ret nx1 / n }
    ret n11
}

// the sums over the rules found as in `apriori` of each basic measure's finite values: out[w] for w in 0 .. 37 (the list order of `basic_measure`), out[38] the number of rules
fn apriori_basic(a: *mem.Arena, trans: []const u64, nitems: usize, supp: f64, conf: f64, maxlen: usize, out: []f64) -> err {
    let nt = f64(trans.len)
    let total = 1usize << nitems
    let (cnt, e1) = mem.alloc[u32](a, total)
    if e1 != ok { ret e1 }
    var m = 1usize
    while m < total {
        var c = 0u32
        var t = 0usize
        while t < trans.len {
            if (trans[t] & u64(m)) == u64(m) { c += 1u32 }
            t += 1usize
        }
        cnt[m] = c
        m += 1usize
    }
    cnt[0usize] = u32(trans.len)
    let need = math.ceil[f64](supp * nt - 1.0e-9f64)
    var k = 0usize
    while k < 39usize {
        out[k] = 0.0f64
        k += 1usize
    }
    var zmax = 0.0f64 - 1.0e300f64
    var zlev = 0.0f64
    m = 1usize
    while m < total {
        var sz = 0usize
        var q = m
        while q > 0usize {
            sz += q & 1usize
            q = q >> 1usize
        }
        if sz <= maxlen && sz >= 2usize && f64(cnt[m]) >= need {
            var l = (m - 1usize) & m
            while l > 0usize {
                let r = m ^ l
                if (r & (r - 1usize)) != 0usize {
                    l = (l - 1usize) & m
                    continue
                }
                let cf = f64(cnt[m]) / f64(cnt[l])
                if cf >= conf - 1.0e-12f64 {
                    let n11 = f64(cnt[m])
                    let n10 = f64(cnt[l]) - n11
                    let n01 = f64(cnt[r]) - n11
                    let n00 = nt - n11 - n10 - n01
                    var w = 0usize
                    while w < 38usize {
                        let v = basic_measure(n11, n10, n01, n00, w)
                        if w != 10usize && v - v == 0.0f64 { out[w] += v }
                        w += 1usize
                    }
                    // zhang: arules takes max() over the whole vector of rules, not pairwise, so the denominator is one number for every rule
                    let nz = n11 + n10 + n01 + n00
                    let t1 = n11 / nz * (1.0f64 - (n11 + n10) / nz)
                    let t2 = (n11 + n10) / nz * ((n11 + n01) / nz - n11 / nz)
                    if t1 > zmax { zmax = t1 }
                    if t2 > zmax { zmax = t2 }
                    zlev += n11 / nz - ((n11 + n10) * (n11 + n01) / (nz * nz))
                    out[38usize] += 1.0f64
                }
                l = (l - 1usize) & m
            }
        }
        m += 1usize
    }
    if zmax > 0.0f64 { out[10usize] = zlev / zmax }
    ret ok
}

// the hypergeometric and range measures on the rules of `apriori` (sums over the finite values): out[0] hyperLift (n11 over qhyper(0.99)), 1 hyperConfidence (phyper(n11 - 1) lower), 2 fishersExactTest
// (phyper(n11 - 1) upper), 3 RLD, 4 stdLift with the support and confidence thresholds of the search as arules' info() supplies them; out[5] the number of rules
fn apriori_hyper(a: *mem.Arena, trans: []const u64, nitems: usize, supp: f64, conf: f64, maxlen: usize, out: []f64) -> err {
    let nt = f64(trans.len)
    let total = 1usize << nitems
    let (cnt, e1) = mem.alloc[u32](a, total)
    if e1 != ok { ret e1 }
    var m = 1usize
    while m < total {
        var c = 0u32
        var t = 0usize
        while t < trans.len {
            if (trans[t] & u64(m)) == u64(m) { c += 1u32 }
            t += 1usize
        }
        cnt[m] = c
        m += 1usize
    }
    cnt[0usize] = u32(trans.len)
    let need = math.ceil[f64](supp * nt - 1.0e-9f64)
    var k = 0usize
    while k < 9usize {
        out[k] = 0.0f64
        k += 1usize
    }
    m = 1usize
    while m < total {
        var sz = 0usize
        var q = m
        while q > 0usize {
            sz += q & 1usize
            q = q >> 1usize
        }
        if sz <= maxlen && sz >= 2usize && f64(cnt[m]) >= need {
            var l = (m - 1usize) & m
            while l > 0usize {
                let r = m ^ l
                if (r & (r - 1usize)) != 0usize {
                    l = (l - 1usize) & m
                    continue
                }
                let cf = f64(cnt[m]) / f64(cnt[l])
                if cf >= conf - 1.0e-12f64 {
                    let n11 = f64(cnt[m])
                    let n1x = f64(cnt[l])
                    let nx1 = f64(cnt[r])
                    let n10 = n1x - n11
                    let n01 = nx1 - n11
                    let n00 = nt - n11 - n10 - n01
                    let qh = nbh.qhyper(0.99f64, nx1, nt - nx1, n1x, true, false)
                    let hl = n11 / qh
                    if hl - hl == 0.0f64 { out[0usize] += hl }
                    let hc = nbh.phyper(n11 - 1.0f64, nx1, nt - nx1, n1x, true, false)
                    if hc - hc == 0.0f64 { out[1usize] += hc }
                    let fe = nbh.phyper(n11 - 1.0f64, nx1, nt - nx1, n1x, false, false)
                    if fe - fe == 0.0f64 { out[2usize] += fe }
                    let dd = (n11 * n00 - n10 * n01) / nt
                    var rld = 0.0f64
                    if dd > 0.0f64 {
                        if n01 < n10 { rld = dd / (dd + n01) } else { rld = dd / (dd + n10) }
                    } else if n11 < n00 {
                        rld = dd / (dd - n11)
                    } else {
                        rld = dd / (dd - n00)
                    }
                    if rld - rld == 0.0f64 { out[3usize] += rld }
                    let sa = n1x / nt
                    let sb = nx1 / nt
                    var lam = 0.0f64
                    let l0 = sa + sb - 1.0f64
                    if l0 > 1.0f64 / nt { lam = l0 / (sa * sb) } else { lam = (1.0f64 / nt) / (sa * sb) }
                    let s = supp
                    let cc = conf
                    let c1 = 4.0f64 * s / ((1.0f64 + s) * (1.0f64 + s))
                    let c2 = s / (sa * sb)
                    let c3 = cc / sb
                    if c1 > lam { lam = c1 }
                    if c2 > lam { lam = c2 }
                    if c3 > lam { lam = c3 }
                    var ups = 1.0f64 / sb
                    if sa > sb { ups = 1.0f64 / sa }
                    let lift = (n11 / nt) / (sa * sb)
                    var sl = (lift - lam) / (ups - lam)
                    if sl != sl { sl = 1.0f64 }
                    if sl - sl == 0.0f64 { out[4usize] += sl }
                    var bq = 0.0f64
                    var bl = 0.0f64
                    var sub = (l - 1usize) & l
                    while sub > 0usize {
                        let sr = sub | r
                        if f64(cnt[sr]) >= need && f64(cnt[sr]) / f64(cnt[sub]) >= conf - 1.0e-12f64 {
                            let qc = f64(cnt[sr]) / f64(cnt[sub])
                            let ql = f64(cnt[sr]) * nt / (f64(cnt[sub]) * f64(cnt[r]))
                            if qc > bq { bq = qc }
                            if ql > bl { bl = ql }
                        }
                        sub = (sub - 1usize) & l
                    }
                    let im = cf - bq
                    if im - im == 0.0f64 { out[6usize] += im }
                    let li = lift / bl
                    if li - li == 0.0f64 { out[7usize] += li }
                    let bo = cf / (cf - im)
                    if bo - bo == 0.0f64 { out[8usize] += bo }
                    out[5usize] += 1.0f64
                }
                l = (l - 1usize) & m
            }
        }
        m += 1usize
    }
    ret ok
}
