// R arules::apriori by exhaustive subset counting for up to 20 items: the frequent itemsets (support >= supp) and the association rules (confidence >= conf) with a non-empty antecedent and a single-item consequent, up to maxlen items in all. Transactions are bit masks of items.
//
// Not here: the candidate-pruning search for many items, other targets (closed, maximal), measures beyond support, confidence and lift, and rule subsetting.

use e.math
use e.mem

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
