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
