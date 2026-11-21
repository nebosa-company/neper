// R grf 2.6.1 (generalized random forests, the C++ core the package runs): the same draws from the 64-bit Mersenne-Twister in the same order, so a forest
// trained from an integer seed is the forest R trains. The tree seed of group g is seed + g (legacy.seed = FALSE).
//
// Regression forests: honest splitting with leaf pruning, ci groups (little bags), sample weights, out-of-bag and test-set predictions, the variance
// estimate (bootstrap of little bags with the objective-Bayes debiasing), debiased.error and excess.error, and variable_importance.
//
// Opts.kind picks the forest: 0 regression, 1 instrumental (also the causal forest: the treatment is its own instrument; nuisance() grows Y.hat, W.hat,
// Z.hat, and dr_scores/ate_all give average_treatment_effect), 2 quantile (predict_quantile), 3 local linear splitting (predict_ll for the local linear
// predictions, ll_lambda_min for the tuned lambda), 4 survival (predict_survival), 5 probability (predict_prob; nclass classes). Each is checked against R in
// tests/oracle/grf.json. Opts.cluster and equalize give cluster sampling; ate_target and ate_all_c give average_treatment_effect for every target.sample (TMLE
// without clusters or sample weights, as in R) with the cluster-robust standard errors.
//
// Boosted forests are boosted() and probability forests kind 5. Kinds 6 and 7 are multi_arm_causal_forest and multi_regression_forest (Data.ym outcomes, Data.tm
// centred treatment columns; predict_multi): multi_arm_causal_forest (nuisance forests: kind 7 for Y.hat, kind 5 for W.hat) with stabilize.splits is checked against R
// for one and several outcomes and with variance estimates for one outcome. Without stabilize.splits the rule has no minimum node size on the treatment, tiny nodes tie
// exactly between isolating one sample from either side, and R breaks the tie by an ulp of Eigen's summation order in the relabelling, which this port does not reproduce.
//
// Not here: missing values in X, tune.parameters, fast.logrank, causal survival, merge_forests. TMLE with clusters is an error in R. The overall-beta branch of the
// local linear split (ll.split.cutoff above 0) equals R in three oracle cases; a weight-penalty split (ridge on each column) with lambda 0.3 or more diverges in a few trees (cause open).

use e.math
use e.math.special as special
use e.mem

type Mt64 = struct { s: [312]u64, i: usize }

// train options; fraction fields are the R arguments. `honesty` false skips the honest split of each tree's sample.
type Opts = struct {
    num_trees: usize, mtry: usize, min_node_size: usize, sample_fraction: f64, honesty: bool, honesty_fraction: f64, honesty_prune: bool,
    ci_group_size: usize, alpha: f64, imbalance_penalty: f64, seed: u64,
    kind: usize, stabilize: bool, rfw: f64, quantiles: []const f64,
    ll_lambda: f64, ll_wpen: bool, ll_cutoff: usize, ll_beta: []const f64, ll_vars: []const usize,
    cluster: []const usize, equalize: bool, cl_start: []const usize, cl_rows: []const usize, spc: usize,
    nclass: usize
}

// x is n by p row-major; w has length n, or length 0 for unit weights
// kind 1 (instrumental, which is also the causal forest): t is the treatment and z the instrument; zsep false means z is the treatment column itself.
type Data = struct { n: usize, p: usize, x: []const f64, y: []const f64, w: []const f64, t: []const f64, z: []const f64, zsep: bool, cens: []const f64, ym: []const f64, tm: []const f64, nout: usize, ntr: usize }

type Tree = struct {
    nn: usize, root: usize,
    left: []usize, right: []usize, svar: []usize, sval: []f64,
    ls_start: []usize, ls_len: []usize, ls: []usize,
    pv: []f64, pv_ok: []bool, pc: []f64, pcn: usize,
    nd: usize, drawn: []usize
}

type Forest = struct { trees: []Tree, ntree: usize, ci: usize, p: usize, n: usize }

// per-sample answers; `var_est` and `exc` are filled when asked for
type Pred = struct { pred: []f64, var_est: []f64, err: []f64, exc: []f64 }

const MT_UPPER: u64 = 18446744071562067968u64
const MT_LOWER: u64 = 2147483647u64
const MT_MATRIX: u64 = 13043109905998158313u64

fn mt64_seed(g: *Mt64, seed: u64) {
    g.s[0usize] = seed
    var k = 1usize
    while k < 312usize {
        let prev = g.s[k - 1usize]
        g.s[k] = 6364136223846793005u64 *% (prev ^ (prev >> 62u64)) +% u64(k)
        k += 1usize
    }
    g.i = 312usize
}

fn mt64_next(g: *Mt64) -> u64 {
    if g.i >= 312usize {
        var k = 0usize
        while k < 312usize {
            let nxt = g.s[(k + 1usize) % 312usize]
            let x = (g.s[k] & MT_UPPER) | (nxt & MT_LOWER)
            var xa = x >> 1u64
            if (x & 1u64) != 0u64 { xa = xa ^ MT_MATRIX }
            g.s[k] = g.s[(k + 156usize) % 312usize] ^ xa
            k += 1usize
        }
        g.i = 0usize
    }
    var y = g.s[g.i]
    g.i += 1usize
    y = y ^ ((y >> 29u64) & 6148914691236517205u64)
    y = y ^ ((y << 17u64) & 8202884508482404352u64)
    y = y ^ ((y << 37u64) & 18444473444759240704u64)
    ret y ^ (y >> 43u64)
}

// uniform_int_distribution<size_t>(0, rp - 1): the bits of one draw, masked, retried until below rp
fn uint_below(g: *Mt64, rp: u64) -> u64 {
    if rp == 1u64 { ret 0u64 }
    var w = 0u64
    var t = rp
    while t > 1u64 {
        t = t >> 1u64
        w += 1u64
    }
    if (rp & (18446744073709551615u64 >> (64u64 - w))) != 0u64 { w += 1u64 }
    let mask = 18446744073709551615u64 >> (64u64 - w)
    var u = mt64_next(g) & mask
    while u >= rp { u = mt64_next(g) & mask }
    ret u
}

// generate_canonical<double, 53> over a 64-bit engine: one draw over 2^64
fn canonical(g: *Mt64) -> f64 { ret f64(mt64_next(g)) / 18446744073709551616.0f64 }

fn shuffle(g: *Mt64, items: []usize, n: usize) {
    if n < 2usize { ret }
    var first = 0usize
    while first + 1usize < n {
        let i = usize(uint_below(g, u64(n - first)))
        if i != 0usize {
            let t = items[first]
            items[first] = items[first + i]
            items[first + i] = t
        }
        first += 1usize
    }
}

fn normal_unit(g: *Mt64) -> f64 {
    var u = 0.0f64
    var v = 0.0f64
    var s = 2.0f64
    while s > 1.0f64 || s == 0.0f64 {
        u = 2.0f64 * canonical(g) - 1.0f64
        v = 2.0f64 * canonical(g) - 1.0f64
        s = u * u + v * v
    }
    let fp = math.sqrt[f64](-2.0f64 * math.log[f64](s) / s)
    ret u * fp
}

fn poisson(g: *Mt64, mean: f64) -> usize {
    if mean < 10.0f64 {
        let l = math.exp[f64](0.0f64 - mean)
        var x = 0usize
        var p = canonical(g)
        while p > l {
            p *= canonical(g)
            x += 1usize
        }
        ret x
    }
    let s = math.sqrt[f64](mean)
    let d = 6.0f64 * mean * mean
    let l = f64(usize(mean - 1.1484f64))
    let omega = 0.3989423f64 / s
    let b1 = 0.04166667f64 / mean
    let b2 = 0.3f64 * b1 * b1
    let c3 = 0.1428571f64 * b1 * b2
    let c2 = b2 - 15.0f64 * c3
    let c1 = b1 - 6.0f64 * b2 + 45.0f64 * c3
    let c0 = 1.0f64 - b1 + 3.0f64 * b2 - 15.0f64 * c3
    let c = 0.1069f64 / mean
    var x = 0usize
    var difmuk = 0.0f64
    var u = 0.0f64
    let gg = mean + s * normal_unit(g)
    if gg > 0.0f64 {
        x = usize(gg)
        if f64(x) >= l { ret x }
        difmuk = mean - f64(x)
        u = canonical(g)
        if d * u >= difmuk * difmuk * difmuk { ret x }
    }
    var using_exp = false
    while true {
        var e = 0.0f64
        if using_exp || gg < 0.0f64 {
            var t = 0.0f64
            var again = true
            while again {
                e = 0.0f64 - math.log[f64](1.0f64 - canonical(g))
                u = canonical(g)
                u += u - 1.0f64
                if u < 0.0f64 { t = 1.8f64 - e } else { t = 1.8f64 + e }
                again = t <= -0.6744f64
            }
            x = usize(mean + s * t)
            difmuk = mean - f64(x)
            using_exp = true
        }
        var px = 0.0f64
        var py = 0.0f64
        if x < 10usize {
            var fac = 1.0f64
            var q = 2usize
            while q <= x {
                fac *= f64(q)
                q += 1usize
            }
            px = 0.0f64 - mean
            py = math.pow[f64](mean, f64(x)) / fac
        } else {
            var del = 0.08333333f64 / f64(x)
            del -= 4.8f64 * del * del * del
            let v = difmuk / f64(x)
            if math.abs[f64](v) > 0.25f64 {
                px = f64(x) * math.log[f64](1.0f64 + v) - difmuk - del
            } else {
                px = f64(x) * v * v * (((((((0.125006f64 * v + -0.1384794f64) * v + 0.1421878f64) * v + -0.1661269f64) * v + 0.2000118f64) * v + -0.2500068f64) * v + 0.3333333f64) * v + -0.5f64) - del
            }
            py = 0.3989423f64 / math.sqrt[f64](f64(x))
        }
        let r = (0.5f64 - difmuk) / s
        let r2 = r * r
        let fx = -0.5f64 * r2
        let fy = omega * (((c3 * r2 + c2) * r2 + c1) * r2 + c0)
        if using_exp {
            if c * math.abs[f64](u) <= py * math.exp[f64](px + e) - fy * math.exp[f64](fx + e) { break }
        } else {
            if fy - u * fy <= py * math.exp[f64](px - fx) { break }
        }
        using_exp = true
    }
    ret x
}

fn gz_f64(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i <= n {
        s[i] = 0.0f64
        i += 1usize
    }
    ret (s, ok)
}

fn gz_usize(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (s, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i <= n {
        s[i] = 0usize
        i += 1usize
    }
    ret (s, ok)
}

fn gz_bool(a: *mem.Arena, n: usize) -> ([]bool, err) {
    let (s, e) = mem.alloc[bool](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i <= n {
        s[i] = false
        i += 1usize
    }
    ret (s, ok)
}

fn weight_of(d: *const Data, s: usize) -> f64 {
    if d.w.len == 0usize { ret 1.0f64 }
    ret d.w[s]
}

// stable bottom-up merge sort of ids by keys (both permuted together)
fn msort(keys: []f64, ids: []usize, tk: []f64, ti: []usize, n: usize) {
    var width = 1usize
    while width < n {
        var lo = 0usize
        while lo < n {
            var mid = lo + width
            if mid > n { mid = n }
            var hi = lo + 2usize * width
            if hi > n { hi = n }
            var i = lo
            var j = mid
            var k = lo
            while i < mid && j < hi {
                if keys[j] < keys[i] {
                    tk[k] = keys[j]
                    ti[k] = ids[j]
                    j += 1usize
                } else {
                    tk[k] = keys[i]
                    ti[k] = ids[i]
                    i += 1usize
                }
                k += 1usize
            }
            while i < mid {
                tk[k] = keys[i]
                ti[k] = ids[i]
                i += 1usize
                k += 1usize
            }
            while j < hi {
                tk[k] = keys[j]
                ti[k] = ids[j]
                j += 1usize
                k += 1usize
            }
            lo += 2usize * width
        }
        var c = 0usize
        while c < n {
            keys[c] = tk[c]
            ids[c] = ti[c]
            c += 1usize
        }
        width *= 2usize
    }
}

// RandomSampler::draw: num distinct columns of 0..max-1 outside the sorted skip list
fn draw_vars(g: *Mt64, out: []usize, flags: []bool, pool: []usize, max: usize, skip: []const usize, num: usize) {
    if num < max / 10usize {
        var i = 0usize
        while i < max {
            flags[i] = false
            i += 1usize
        }
        i = 0usize
        while i < num {
            var dr = usize(uint_below(g, u64(max - skip.len)))
            var j = 0usize
            while j < skip.len {
                if dr >= skip[j] { dr += 1usize }
                j += 1usize
            }
            while flags[dr] {
                dr = usize(uint_below(g, u64(max - skip.len)))
                j = 0usize
                while j < skip.len {
                    if dr >= skip[j] { dr += 1usize }
                    j += 1usize
                }
            }
            flags[dr] = true
            out[i] = dr
            i += 1usize
        }
        ret
    }
    var m = 0usize
    var c = 0usize
    while c < max {
        var skipped = false
        var j = 0usize
        while j < skip.len {
            if skip[j] == c { skipped = true }
            j += 1usize
        }
        if !skipped {
            pool[m] = c
            m += 1usize
        }
        c += 1usize
    }
    var i = 0usize
    while i < num {
        let jj = usize(f64(i) + canonical(g) * f64(max - skip.len - i))
        let t = pool[i]
        pool[i] = pool[jj]
        pool[jj] = t
        out[i] = pool[i]
        i += 1usize
    }
}

fn ceil_size(n: usize, frac: f64) -> usize { ret usize(math.ceil[f64](f64(n) * frac)) }

type Scratch = struct {
    keys: []f64, ids: []usize, tk: []f64, ti: []usize, uniq: []f64, counter: []usize, sums: []f64, wsums: []f64,
    vars: []usize, flags: []bool, pool: []usize,
    resp: []f64, nsm: []usize, sz: []f64, szz: []f64, cut: []f64, cls: []f64, cc: []f64, llx: []f64, llm: []f64, llb: []f64, llz: []f64, rel: []usize, sv: []f64,
    rm: []f64, bs: []f64, bw: []f64, bq: []f64, bm: []usize, nv: []f64, nvi: []usize
}

// leaf value slots of the optimized strategies
const V_OUT: usize = 0usize
const V_TR: usize = 1usize
const V_INST: usize = 2usize
const V_OI: usize = 3usize
const V_TI: usize = 4usize
const V_II: usize = 5usize
const V_WT: usize = 6usize
const NV: usize = 7usize

fn inst_of(d: *const Data, s: usize) -> f64 {
    if d.zsep { ret d.z[s] }
    ret d.t[s]
}

// InstrumentalRelabelingStrategy::relabel; true means the node cannot be split
fn relabel_iv(d: *const Data, sc: *Scratch, node: []const usize, rfw: f64) -> bool {
    var sw = 0.0f64
    var to = 0.0f64
    var tt = 0.0f64
    var ti = 0.0f64
    var i = 0usize
    while i < node.len {
        let s = node[i]
        let w = weight_of(d, s)
        to += w * d.y[s]
        tt += w * d.t[s]
        ti += w * inst_of(d, s)
        sw += w
        i += 1usize
    }
    if math.abs[f64](sw) <= 1.0e-16f64 { ret true }
    let ao = to / sw
    let at = tt / sw
    let ai = ti / sw
    let ar = (1.0f64 - rfw) * ai + rfw * at
    var num = 0.0f64
    var den = 0.0f64
    i = 0usize
    while i < node.len {
        let s = node[i]
        let w = weight_of(d, s)
        let r = (1.0f64 - rfw) * inst_of(d, s) + rfw * d.t[s]
        num += w * (r - ar) * (d.y[s] - ao)
        den += w * (r - ar) * (d.t[s] - at)
        i += 1usize
    }
    if math.abs[f64](den) <= 1.0e-10f64 { ret true }
    let late = num / den
    i = 0usize
    while i < node.len {
        let s = node[i]
        let r = (1.0f64 - rfw) * inst_of(d, s) + rfw * d.t[s]
        let resid = (d.y[s] - ao) - late * (d.t[s] - at)
        sc.resp[s] = (r - ar) * resid
        i += 1usize
    }
    ret false
}

type Best = struct { sv: usize, val: f64, dec: f64 }

fn split_value(d: *const Data, sc: *Scratch, node: []const usize, v: usize, wsum_node: f64, sum_node: f64, min_child: usize, imb: f64, best: *Best) {
    let size = node.len
    var i = 0usize
    while i < size {
        sc.keys[i] = d.x[node[i] * d.p + v]
        sc.ids[i] = node[i]
        i += 1usize
    }
    msort(sc.keys, sc.ids, sc.tk, sc.ti, size)
    var nu = 0usize
    i = 0usize
    while i < size {
        if i == 0usize || sc.keys[i] != sc.keys[i - 1usize] {
            sc.uniq[nu] = sc.keys[i]
            nu += 1usize
        }
        i += 1usize
    }
    if nu < 2usize { ret }
    let nsplit = nu - 1usize
    i = 0usize
    while i < nsplit {
        sc.counter[i] = 0usize
        sc.sums[i] = 0.0f64
        sc.wsums[i] = 0.0f64
        i += 1usize
    }
    var si = 0usize
    i = 0usize
    while i + 1usize < size {
        let s = sc.ids[i]
        let w = weight_of(d, s)
        sc.wsums[si] += w
        sc.sums[si] += w * sc.resp[s]
        sc.counter[si] += 1usize
        if sc.keys[i] != sc.keys[i + 1usize] { si += 1usize }
        i += 1usize
    }
    var n_left = 0usize
    var wsum_left = 0.0f64
    var sum_left = 0.0f64
    i = 0usize
    while i < nsplit {
        n_left += sc.counter[i]
        wsum_left += sc.wsums[i]
        sum_left += sc.sums[i]
        if n_left < min_child {
            i += 1usize
            continue
        }
        let n_right = size - n_left
        if n_right < min_child { break }
        let wsum_right = wsum_node - wsum_left
        let sum_right = sum_node - sum_left
        var dec = sum_left * sum_left / wsum_left + sum_right * sum_right / wsum_right
        dec -= imb * (1.0f64 / f64(n_left) + 1.0f64 / f64(n_right))
        if dec > best.dec {
            best.val = sc.uniq[i]
            best.sv = v
            best.dec = dec
        }
        i += 1usize
    }
}

// InstrumentalSplittingRule::find_best_split_value (no missing values); the node sums are passed in
type IvNode = struct { wsum: f64, sum: f64, mean_z: f64, nsmall: usize, sum_z: f64, sum_zz: f64, min_child: f64 }

fn split_value_iv(d: *const Data, sc: *Scratch, node: []const usize, v: usize, nd: *const IvNode, min_node_size: usize, imb: f64, best: *Best) {
    let size = node.len
    var i = 0usize
    while i < size {
        sc.keys[i] = d.x[node[i] * d.p + v]
        sc.ids[i] = node[i]
        i += 1usize
    }
    msort(sc.keys, sc.ids, sc.tk, sc.ti, size)
    var nu = 0usize
    i = 0usize
    while i < size {
        if i == 0usize || sc.keys[i] != sc.keys[i - 1usize] {
            sc.uniq[nu] = sc.keys[i]
            nu += 1usize
        }
        i += 1usize
    }
    if nu < 2usize { ret }
    let nsplit = nu - 1usize
    i = 0usize
    while i < nsplit {
        sc.counter[i] = 0usize
        sc.sums[i] = 0.0f64
        sc.wsums[i] = 0.0f64
        sc.nsm[i] = 0usize
        sc.sz[i] = 0.0f64
        sc.szz[i] = 0.0f64
        i += 1usize
    }
    var si = 0usize
    i = 0usize
    while i + 1usize < size {
        let s = sc.ids[i]
        let w = weight_of(d, s)
        let z = inst_of(d, s)
        sc.wsums[si] += w
        sc.sums[si] += w * sc.resp[s]
        sc.counter[si] += 1usize
        sc.sz[si] += w * z
        sc.szz[si] += w * z * z
        if z < nd.mean_z { sc.nsm[si] += 1usize }
        if sc.keys[i] != sc.keys[i + 1usize] { si += 1usize }
        i += 1usize
    }
    var n_left = 0usize
    var wsum_left = 0.0f64
    var sum_left = 0.0f64
    var sz_left = 0.0f64
    var szz_left = 0.0f64
    var small_left = 0usize
    i = 0usize
    while i < nsplit {
        n_left += sc.counter[i]
        small_left += sc.nsm[i]
        wsum_left += sc.wsums[i]
        sum_left += sc.sums[i]
        sz_left += sc.sz[i]
        szz_left += sc.szz[i]
        let large_left = n_left - small_left
        if small_left < min_node_size || large_left < min_node_size {
            i += 1usize
            continue
        }
        let n_right = size - n_left
        let small_right = nd.nsmall - small_left
        let large_right = n_right - small_right
        if small_right < min_node_size || large_right < min_node_size { break }
        let size_left = szz_left - sz_left * sz_left / wsum_left
        if size_left < nd.min_child || (imb > 0.0f64 && size_left == 0.0f64) {
            i += 1usize
            continue
        }
        let wsum_right = nd.wsum - wsum_left
        let sum_right = nd.sum - sum_left
        let szz_right = nd.sum_zz - szz_left
        let sz_right = nd.sum_z - sz_left
        let size_right = szz_right - sz_right * sz_right / wsum_right
        if size_right < nd.min_child || (imb > 0.0f64 && size_right == 0.0f64) {
            i += 1usize
            continue
        }
        var dec = sum_left * sum_left / wsum_left + sum_right * sum_right / wsum_right
        dec -= imb * (1.0f64 / size_left + 1.0f64 / size_right)
        if dec > best.dec {
            best.val = sc.uniq[i]
            best.sv = v
            best.dec = dec
        }
        i += 1usize
    }
}

// QuantileRelabelingStrategy::relabel: each sample's class is the number of distinct node quantile cutoffs below its outcome
fn relabel_quantile(d: *const Data, sc: *Scratch, node: []const usize, qs: []const f64) {
    let n = node.len
    var i = 0usize
    while i < n {
        sc.keys[i] = d.y[node[i]]
        sc.ids[i] = node[i]
        i += 1usize
    }
    msort(sc.keys, sc.ids, sc.tk, sc.ti, n)
    var nc = 0usize
    var k = 0usize
    while k < qs.len {
        let idx = usize(math.ceil[f64](f64(n) * qs[k])) - 1usize
        let v = sc.keys[idx]
        if nc == 0usize || sc.cut[nc - 1usize] != v {
            sc.cut[nc] = v
            nc += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        let s = node[i]
        let y = d.y[s]
        var lo = 0usize
        var hi = nc
        while lo < hi {
            let mid = (lo + hi) / 2usize
            if sc.cut[mid] < y { lo = mid + 1usize } else { hi = mid }
        }
        sc.resp[s] = f64(lo)
        i += 1usize
    }
}

// ProbabilitySplittingRule::find_best_split_value over the classes in sc.resp (no missing values); cc holds the node's class counts
fn split_value_prob(d: *const Data, sc: *Scratch, node: []const usize, v: usize, ncls: usize, min_child: usize, imb: f64, best: *Best) {
    let size = node.len
    var i = 0usize
    while i < size {
        sc.keys[i] = d.x[node[i] * d.p + v]
        sc.ids[i] = node[i]
        i += 1usize
    }
    msort(sc.keys, sc.ids, sc.tk, sc.ti, size)
    var nu = 0usize
    i = 0usize
    while i < size {
        if i == 0usize || sc.keys[i] != sc.keys[i - 1usize] {
            sc.uniq[nu] = sc.keys[i]
            nu += 1usize
        }
        i += 1usize
    }
    if nu < 2usize { ret }
    let nsplit = nu - 1usize
    i = 0usize
    while i < nsplit {
        sc.counter[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < nsplit * ncls {
        sc.cls[i] = 0.0f64
        i += 1usize
    }
    var si = 0usize
    i = 0usize
    while i + 1usize < size {
        let s = sc.ids[i]
        sc.counter[si] += 1usize
        sc.cls[si * ncls + usize(sc.resp[s])] += weight_of(d, s)
        if sc.keys[i] != sc.keys[i + 1usize] { si += 1usize }
        i += 1usize
    }
    var left: [64]f64 = zero
    var n_left = 0usize
    i = 0usize
    while i < nsplit {
        n_left += sc.counter[i]
        let n_right = size - n_left
        if n_right < min_child { break }
        var sum_left = 0.0f64
        var sum_right = 0.0f64
        var c = 0usize
        while c < ncls {
            left[c] += sc.cls[i * ncls + c]
            let right = sc.cc[c] - left[c]
            sum_left += left[c] * left[c]
            sum_right += right * right
            c += 1usize
        }
        if n_left < min_child {
            i += 1usize
            continue
        }
        var dec = sum_right / f64(n_right) + sum_left / f64(n_left)
        dec -= imb * (1.0f64 / f64(n_left) + 1.0f64 / f64(n_right))
        if dec > best.dec {
            best.val = sc.uniq[i]
            best.sv = v
            best.dec = dec
        }
        i += 1usize
    }
}

// the determinant and inverse of the k by k row-major matrix m by Gauss-Jordan elimination with partial pivoting (Eigen's PartialPivLU)
fn lu_inverse(m: []const f64, k: usize, inv: []f64, work: []f64) -> f64 {
    var det = 1.0f64
    var i = 0usize
    while i < k * k {
        work[i] = m[i]
        inv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        inv[i * k + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var piv = c
        var r = c + 1usize
        while r < k {
            if math.abs[f64](work[r * k + c]) > math.abs[f64](work[piv * k + c]) { piv = r }
            r += 1usize
        }
        if piv != c {
            det = 0.0f64 - det
            var j = 0usize
            while j < k {
                let t1 = work[c * k + j]
                work[c * k + j] = work[piv * k + j]
                work[piv * k + j] = t1
                let t2 = inv[c * k + j]
                inv[c * k + j] = inv[piv * k + j]
                inv[piv * k + j] = t2
                j += 1usize
            }
        }
        let pv = work[c * k + c]
        det *= pv
        if pv == 0.0f64 { ret 0.0f64 }
        r = c + 1usize
        while r < k {
            let fct = work[r * k + c] / pv
            var j = 0usize
            while j < k {
                work[r * k + j] -= fct * work[c * k + j]
                inv[r * k + j] -= fct * inv[c * k + j]
                j += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    c = k
    while c > 0usize {
        c -= 1usize
        let pv = work[c * k + c]
        var j = 0usize
        while j < k {
            inv[c * k + j] = inv[c * k + j] / pv
            j += 1usize
        }
        var r = 0usize
        while r < c {
            let fct = work[r * k + c]
            j = 0usize
            while j < k {
                inv[r * k + j] -= fct * inv[c * k + j]
                j += 1usize
            }
            r += 1usize
        }
    }
    ret det
}

// MultiCausalRelabelingStrategy::relabel: responses sc.rm[s * rl + o * K + t] = rho_weight(s, t) * residual(s, o); true means the node cannot be split
fn relabel_multi(d: *const Data, sc: *Scratch, node: []const usize) -> bool {
    let kk = d.ntr
    let no = d.nout
    let rl = kk * no
    let m = node.len
    if m <= kk { ret true }
    var sw = 0.0f64
    var ybar: [8]f64 = zero
    var wbar: [8]f64 = zero
    var i = 0usize
    while i < m {
        let s = node[i]
        let w = weight_of(d, s)
        var j = 0usize
        while j < no {
            ybar[j] += w * d.ym[s * no + j]
            j += 1usize
        }
        j = 0usize
        while j < kk {
            wbar[j] += w * d.tm[s * kk + j]
            j += 1usize
        }
        sw += w
        i += 1usize
    }
    var j = 0usize
    while j < no {
        ybar[j] = ybar[j] / sw
        j += 1usize
    }
    j = 0usize
    while j < kk {
        wbar[j] = wbar[j] / sw
        j += 1usize
    }
    if math.abs[f64](sw) <= 1.0e-16f64 { ret true }
    var ww: [64]f64 = zero
    i = 0usize
    while i < m {
        let s = node[i]
        let w = weight_of(d, s)
        var a1 = 0usize
        while a1 < kk {
            var b1 = 0usize
            while b1 < kk {
                ww[a1 * kk + b1] += (d.tm[s * kk + a1] - wbar[a1]) * w * (d.tm[s * kk + b1] - wbar[b1])
                b1 += 1usize
            }
            a1 += 1usize
        }
        i += 1usize
    }
    var inv: [64]f64 = zero
    var work: [64]f64 = zero
    let det = lu_inverse(ww[0usize..64usize], kk, inv[0usize..64usize], work[0usize..64usize])
    if math.abs[f64](det) < 1.0e-10f64 { ret true }
    var wy: [32]f64 = zero
    i = 0usize
    while i < m {
        let s = node[i]
        let w = weight_of(d, s)
        var a1 = 0usize
        while a1 < kk {
            var o1 = 0usize
            while o1 < no {
                wy[a1 * no + o1] += (d.tm[s * kk + a1] - wbar[a1]) * w * (d.ym[s * no + o1] - ybar[o1])
                o1 += 1usize
            }
            a1 += 1usize
        }
        i += 1usize
    }
    var beta: [32]f64 = zero
    var a2 = 0usize
    while a2 < kk {
        var o2 = 0usize
        while o2 < no {
            var acc = 0.0f64
            var b2 = 0usize
            while b2 < kk {
                acc += inv[a2 * kk + b2] * wy[b2 * no + o2]
                b2 += 1usize
            }
            beta[a2 * no + o2] = acc
            o2 += 1usize
        }
        a2 += 1usize
    }
    i = 0usize
    while i < m {
        let s = node[i]
        var o3 = 0usize
        while o3 < no {
            var fit = 0.0f64
            var b3 = 0usize
            while b3 < kk {
                fit += (d.tm[s * kk + b3] - wbar[b3]) * beta[b3 * no + o3]
                b3 += 1usize
            }
            let resid = (d.ym[s * no + o3] - ybar[o3]) - fit
            var t3 = 0usize
            while t3 < kk {
                var rw = 0.0f64
                var b4 = 0usize
                while b4 < kk {
                    rw += (d.tm[s * kk + b4] - wbar[b4]) * inv[t3 * kk + b4]
                    b4 += 1usize
                }
                sc.rm[s * rl + o3 * kk + t3] = rw * resid
                t3 += 1usize
            }
            o3 += 1usize
        }
        i += 1usize
    }
    ret false
}

// MultiCausalSplittingRule (stab) and MultiRegressionSplittingRule (not stab) for one variable; kk is the number of treatment columns (0 for the regression
// rule), rl the response length. sc.nv holds the node sums: [0, rl) responses, then kk each of sum w, sum w^2, mean w, min child size, [rl + 4 kk, 2 rl + 6 kk)
// scratch for the left side, and the node weight and minimum child size at the end.
fn split_multi(d: *const Data, sc: *Scratch, node: []const usize, v: usize, stab: bool, kk: usize, rl: usize, mns: usize, imb: f64, best: *Best) {
    let size = node.len
    var i = 0usize
    while i < size {
        sc.keys[i] = d.x[node[i] * d.p + v]
        sc.ids[i] = node[i]
        i += 1usize
    }
    msort(sc.keys, sc.ids, sc.tk, sc.ti, size)
    var nu = 0usize
    i = 0usize
    while i < size {
        if i == 0usize || sc.keys[i] != sc.keys[i - 1usize] {
            sc.uniq[nu] = sc.keys[i]
            nu += 1usize
        }
        i += 1usize
    }
    if nu < 2usize { ret }
    let nsplit = nu - 1usize
    let o_w = rl
    let o_q = rl + kk
    let o_mean = rl + 2usize * kk
    let o_min = rl + 3usize * kk
    let o_ls = rl + 4usize * kk
    let o_lw = 2usize * rl + 4usize * kk
    let o_lq = 2usize * rl + 5usize * kk
    let wnode = sc.nv[2usize * rl + 6usize * kk]
    let mc = usize(sc.nv[2usize * rl + 6usize * kk + 1usize])
    i = 0usize
    while i < nsplit {
        sc.counter[i] = 0usize
        sc.wsums[i] = 0.0f64
        var r = 0usize
        while r < rl {
            sc.bs[i * rl + r] = 0.0f64
            r += 1usize
        }
        r = 0usize
        while r < kk {
            sc.bw[i * kk + r] = 0.0f64
            sc.bq[i * kk + r] = 0.0f64
            sc.bm[i * kk + r] = 0usize
            r += 1usize
        }
        i += 1usize
    }
    var si = 0usize
    i = 0usize
    while i + 1usize < size {
        let s = sc.ids[i]
        let w = weight_of(d, s)
        sc.wsums[si] += w
        var r = 0usize
        while r < rl {
            sc.bs[si * rl + r] += w * sc.rm[s * rl + r]
            r += 1usize
        }
        sc.counter[si] += 1usize
        r = 0usize
        while r < kk {
            let tv = d.tm[s * kk + r]
            sc.bw[si * kk + r] += w * tv
            sc.bq[si * kk + r] += w * (tv * tv)
            if tv < sc.nv[o_mean + r] { sc.bm[si * kk + r] += 1usize }
            r += 1usize
        }
        if sc.keys[i] != sc.keys[i + 1usize] { si += 1usize }
        i += 1usize
    }
    var n_left = 0usize
    var wl = 0.0f64
    i = 0usize
    while i < rl + 2usize * kk {
        sc.nv[o_ls + i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < kk {
        sc.nvi[kk + i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < nsplit {
        n_left += sc.counter[i]
        wl += sc.wsums[i]
        var r = 0usize
        while r < rl {
            sc.nv[o_ls + r] += sc.bs[i * rl + r]
            r += 1usize
        }
        r = 0usize
        while r < kk {
            sc.nvi[kk + r] += sc.bm[i * kk + r]
            sc.nv[o_lw + r] += sc.bw[i * kk + r]
            sc.nv[o_lq + r] += sc.bq[i * kk + r]
            r += 1usize
        }
        let n_right = size - n_left
        var skip = false
        var stop = false
        if stab {
            r = 0usize
            while r < kk {
                if sc.nvi[kk + r] < mns || n_left - sc.nvi[kk + r] < mns { skip = true }
                r += 1usize
            }
            if !skip {
                r = 0usize
                while r < kk {
                    let small_r = i64(sc.nvi[r]) - i64(sc.nvi[kk + r])
                    let large_r = i64(n_right) - small_r
                    if small_r < i64(mns) || large_r < i64(mns) { stop = true }
                    r += 1usize
                }
            }
            if !skip && !stop {
                let wr = wnode - wl
                var any_l = false
                var all_l0 = true
                var any_r = false
                var all_r0 = true
                r = 0usize
                while r < kk {
                    let sl = sc.nv[o_lq + r] - sc.nv[o_lw + r] * sc.nv[o_lw + r] / wl
                    let swr = sc.nv[o_w + r] - sc.nv[o_lw + r]
                    let sr = sc.nv[o_q + r] - sc.nv[o_lq + r] - swr * swr / wr
                    if sl < sc.nv[o_min + r] { any_l = true }
                    if sl != 0.0f64 { all_l0 = false }
                    if sr < sc.nv[o_min + r] { any_r = true }
                    if sr != 0.0f64 { all_r0 = false }
                    r += 1usize
                }
                if any_l || (imb > 0.0f64 && all_l0) { skip = true }
                if any_r || (imb > 0.0f64 && all_r0) { skip = true }
            }
        } else {
            if n_left < mc { skip = true }
            if !skip && n_right < mc { stop = true }
        }
        if stop { break }
        if skip {
            i += 1usize
            continue
        }
        let wr2 = wnode - wl
        var s1 = 0.0f64
        var s2 = 0.0f64
        var r2 = 0usize
        while r2 < rl {
            let l = sc.nv[o_ls + r2]
            let rr = sc.nv[r2] - l
            s1 += l * l
            s2 += rr * rr
            r2 += 1usize
        }
        var dec = s1 / wl + s2 / wr2
        dec -= imb * (1.0f64 / f64(n_left) + 1.0f64 / f64(n_right))
        if dec > best.dec {
            best.val = sc.uniq[i]
            best.sv = v
            best.dec = dec
        }
        i += 1usize
    }
}

// column j of the training matrix: the covariates, then the outcome (ll.split.variables count from 1 in the R wrapper but index from 0 in the core,
// so the default 1..p reaches the outcome column; the same here)
fn colval(d: *const Data, s: usize, j: usize) -> f64 {
    if j == d.p { ret d.y[s] }
    ret d.x[s * d.p + j]
}

// LLRegressionRelabelingStrategy::relabel: the residual of a ridge regression on ll_vars within the node (or of the overall fit for a small node)
fn relabel_ll(d: *const Data, sc: *Scratch, node: []const usize, o: *const Opts) {
    let k = o.ll_vars.len + 1usize
    let n = node.len
    var i = 0usize
    while i < n {
        sc.llx[i * k] = 1.0f64
        var j = 0usize
        while j < o.ll_vars.len {
            sc.llx[i * k + j + 1usize] = colval(d, node[i], o.ll_vars[j])
            j += 1usize
        }
        i += 1usize
    }
    if n < o.ll_cutoff {
        i = 0usize
        while i < n {
            var acc = 0.0f64
            var j = 0usize
            while j < k {
                acc += sc.llx[i * k + j] * o.ll_beta[j]
                j += 1usize
            }
            sc.resp[node[i]] = acc - d.y[node[i]]
            i += 1usize
        }
        ret
    }
    var r = 0usize
    while r < k {
        var c = 0usize
        while c < k {
            var acc = 0.0f64
            i = 0usize
            while i < n {
                acc += sc.llx[i * k + r] * sc.llx[i * k + c]
                i += 1usize
            }
            sc.llm[r * k + c] = acc
            c += 1usize
        }
        var bacc = 0.0f64
        i = 0usize
        while i < n {
            bacc += sc.llx[i * k + r] * d.y[node[i]]
            i += 1usize
        }
        sc.llb[r] = bacc
        r += 1usize
    }
    ridge_penalty(sc.llm, k, o.ll_lambda, o.ll_wpen)
    solve_sym(sc.llm, sc.llb, sc.llz, k)
    i = 0usize
    while i < n {
        var acc = 0.0f64
        var j = 0usize
        while j < k {
            acc += sc.llx[i * k + j] * sc.llz[j]
            j += 1usize
        }
        sc.resp[node[i]] = acc - d.y[node[i]]
        i += 1usize
    }
}

fn is_failure(d: *const Data, s: usize) -> bool { ret d.cens[s] > 0.0f64 }

// SurvivalSplittingRule::find_best_split_internal for one node: the log-rank statistic over every variable in vars[0..nv], best.dec the statistic.
// sc.sv holds eight arrays of nsub + 2 slots (count_failure, count_censor, at_risk, numerator and denominator weights, left failures, left censored, cum sums).
fn split_node_surv(d: *const Data, sc: *Scratch, node: []const usize, nvars: usize, alpha: f64, stride: usize, best: *Best) {
    let size = node.len
    var min_child = usize(math.ceil[f64](f64(size) * alpha))
    if min_child < 1usize { min_child = 1usize }
    var nfn = 0usize
    var i = 0usize
    while i < size {
        if is_failure(d, node[i]) {
            sc.keys[nfn] = d.y[node[i]]
            sc.ids[nfn] = node[i]
            nfn += 1usize
        }
        i += 1usize
    }
    msort(sc.keys, sc.ids, sc.tk, sc.ti, nfn)
    var nf = 0usize
    i = 0usize
    while i < nfn {
        if i == 0usize || sc.keys[i] != sc.keys[i - 1usize] {
            sc.uniq[nf] = sc.keys[i]
            nf += 1usize
        }
        i += 1usize
    }
    if nf <= 1usize { ret }
    let cf = sc.sv[0usize..stride]
    let cc = sc.sv[stride..2usize * stride]
    let ar = sc.sv[2usize * stride..3usize * stride]
    let nw = sc.sv[3usize * stride..4usize * stride]
    let dw = sc.sv[4usize * stride..5usize * stride]
    let lcf = sc.sv[5usize * stride..6usize * stride]
    let lcc = sc.sv[6usize * stride..7usize * stride]
    let cum = sc.sv[7usize * stride..8usize * stride]
    i = 0usize
    while i <= nf {
        cf[i] = 0.0f64
        cc[i] = 0.0f64
        ar[i] = 0.0f64
        nw[i] = 0.0f64
        dw[i] = 0.0f64
        i += 1usize
    }
    ar[0usize] = f64(size)
    i = 0usize
    while i < size {
        let s = node[i]
        let y = d.y[s]
        var lo = 0usize
        var hi = nf
        while lo < hi {
            let mid = (lo + hi) / 2usize
            if sc.uniq[mid] <= y { lo = mid + 1usize } else { hi = mid }
        }
        sc.rel[s] = lo
        if is_failure(d, s) { cf[lo] += 1.0f64 } else { cc[lo] += 1.0f64 }
        i += 1usize
    }
    var tm = 1usize
    while tm <= nf {
        ar[tm] = ar[tm - 1usize] - cf[tm - 1usize] - cc[tm - 1usize]
        let yk = ar[tm]
        let dk = cf[tm]
        nw[tm] = dk / yk
        dw[tm] = (yk - dk) / (yk - 1.0f64) * dk / (yk * yk)
        tm += 1usize
    }
    var vi = 0usize
    while vi < nvars {
        let v = sc.vars[vi]
        i = 0usize
        while i < size {
            sc.keys[i] = d.x[node[i] * d.p + v]
            sc.ids[i] = node[i]
            i += 1usize
        }
        msort(sc.keys, sc.ids, sc.tk, sc.ti, size)
        var nu = 0usize
        i = 0usize
        while i < size {
            if i == 0usize || sc.keys[i] != sc.keys[i - 1usize] { nu += 1usize }
            i += 1usize
        }
        if nu < 2usize {
            vi += 1usize
            continue
        }
        let nsplit = nu - 1usize
        i = 0usize
        while i <= nf {
            lcf[i] = 0.0f64
            lcc[i] = 0.0f64
            cum[i] = 0.0f64
            i += 1usize
        }
        var n_left = 0usize
        var nfl = 0usize
        var si = 0usize
        i = 0usize
        while i + 1usize < size {
            let s = sc.ids[i]
            let t = sc.rel[s]
            n_left += 1usize
            if is_failure(d, s) {
                lcf[t] += 1.0f64
                nfl += 1usize
            } else {
                lcc[t] += 1.0f64
            }
            let changed = sc.keys[i] != sc.keys[i + 1usize]
            if nfl < min_child {
                if changed { si += 1usize }
                i += 1usize
                continue
            }
            let nfr = nfn - nfl
            if nfr < min_child { break }
            if changed {
                var numer = 0.0f64
                var denom = 0.0f64
                var tt = 1usize
                while tt <= nf {
                    cum[tt] = cum[tt - 1usize] + lcf[tt - 1usize] + lcc[tt - 1usize]
                    let yl = f64(n_left) - cum[tt]
                    if yl == 0.0f64 { break }
                    let y = ar[tt]
                    if y < 2.0f64 { break }
                    numer = numer + lcf[tt] - yl * nw[tt]
                    denom = denom + yl * (y - yl) * dw[tt]
                    tt += 1usize
                }
                var lr = 0.0f64
                if denom > 0.0f64 { lr = numer * numer / denom }
                if lr > best.dec {
                    best.val = sc.keys[i]
                    best.sv = v
                    best.dec = lr
                }
                si += 1usize
            }
            if si == nsplit { break }
            i += 1usize
        }
        vi += 1usize
    }
}

fn find_leaf(t: *const Tree, x: []const f64, p: usize, row: usize) -> usize {
    var node = t.root
    while !(t.left[node] == 0usize && t.right[node] == 0usize) {
        if x[row * p + t.svar[node]] <= t.sval[node] {
            node = t.left[node]
        } else {
            node = t.right[node]
        }
    }
    ret node
}

fn is_leaf(t: *const Tree, node: usize) -> bool { ret t.left[node] == 0usize && t.right[node] == 0usize }

fn is_empty_leaf(t: *const Tree, node: usize) -> bool { ret is_leaf(t, node) && t.ls_len[node] == 0usize }

// Tree::prune_node: returns the node that stands in this one's place
fn prune_node(t: *Tree, node: usize) -> usize {
    let l = t.left[node]
    let r = t.right[node]
    if is_empty_leaf(t, l) || is_empty_leaf(t, r) {
        t.left[node] = 0usize
        t.right[node] = 0usize
        if !is_empty_leaf(t, l) { ret l }
        if !is_empty_leaf(t, r) { ret r }
    }
    ret node
}

fn honesty_prune(t: *Tree) {
    var n = t.nn
    while n > 0usize {
        let node = n - 1usize
        n -= 1usize
        if is_leaf(t, node) { continue }
        let lc = t.left[node]
        if !is_leaf(t, lc) { t.left[node] = prune_node(t, lc) }
        let rc = t.right[node]
        if !is_leaf(t, rc) { t.right[node] = prune_node(t, rc) }
    }
    t.root = prune_node(t, t.root)
}

// RandomSampler::sample_from_clusters: every row of a cluster no bigger than samples_per_cluster, else a random samples_per_cluster of its rows
fn expand_clusters(g: *Mt64, o: *const Opts, ids: []const usize, out: []usize, tmp: []usize) -> usize {
    var m = 0usize
    var i = 0usize
    while i < ids.len {
        let cs = o.cl_start[ids[i]]
        let ln = o.cl_start[ids[i] + 1usize] - cs
        var r = 0usize
        if ln <= o.spc {
            while r < ln {
                out[m + r] = o.cl_rows[cs + r]
                r += 1usize
            }
            m += ln
        } else {
            while r < ln {
                tmp[r] = o.cl_rows[cs + r]
                r += 1usize
            }
            shuffle(g, tmp, ln)
            r = 0usize
            while r < o.spc {
                out[m + r] = tmp[r]
                r += 1usize
            }
            m += o.spc
        }
        i += 1usize
    }
    ret m
}

fn train_tree(a: *mem.Arena, d: *const Data, g: *Mt64, clusters: []const usize, o: *const Opts) -> (Tree, err) {
    var t: Tree = zero
    let nc = clusters.len
    var nsub = nc
    var nnew = 0usize
    if o.honesty {
        nsub = ceil_size(nc, o.honesty_fraction)
        nnew = nc - nsub
    }
    let nsubc = nsub
    let clustered = o.cl_start.len > 0usize
    var nbound = nsub
    var lsbound = nsub + nnew
    var drawbound = nc
    if clustered {
        nbound = d.n
        lsbound = d.n
        drawbound = d.n
    }
    let cap = 2usize * nbound + 2usize
    let (left, e1) = gz_usize(a, cap)
    let (right, e2) = gz_usize(a, cap)
    let (svar, e3) = gz_usize(a, cap)
    let (sval, e4) = gz_f64(a, cap)
    let (ls_start, e5) = gz_usize(a, cap)
    let (ls_len, e6) = gz_usize(a, cap)
    let (ls, e7) = gz_usize(a, lsbound)
    let (pv, e8) = gz_f64(a, cap * NV)
    let (e9v, e9) = gz_f64(a, 1usize)
    let (pv_ok, e10) = gz_bool(a, cap)
    var pcn = 1usize
    if o.kind == 5usize { pcn = o.nclass + 1usize }
    var mrl = 0usize
    var mkk = 0usize
    if o.kind == 6usize {
        mkk = d.ntr
        mrl = d.ntr * d.nout
        pcn = d.ntr * (d.ntr + d.nout + 1usize) + d.nout + 1usize
    }
    if o.kind == 7usize {
        mrl = d.nout
        pcn = d.nout + 1usize
    }
    let (pcv, e12) = gz_f64(a, cap * pcn)
    if e12 != ok { ret (t, e12) }
    let (drawn, e11) = gz_usize(a, drawbound)
    if e1 != ok { ret (t, e1) }
    if e2 != ok { ret (t, e2) }
    if e3 != ok { ret (t, e3) }
    if e4 != ok { ret (t, e4) }
    if e5 != ok { ret (t, e5) }
    if e6 != ok { ret (t, e6) }
    if e7 != ok { ret (t, e7) }
    if e8 != ok { ret (t, e8) }
    if e9 != ok { ret (t, e9) }
    if e10 != ok { ret (t, e10) }
    if e11 != ok { ret (t, e11) }
    var i = 0usize
    var ndrawn = nc
    if clustered {
        ndrawn = 0usize
        while i < nc {
            let cs = o.cl_start[clusters[i]]
            let ce = o.cl_start[clusters[i] + 1usize]
            var r = cs
            while r < ce {
                drawn[ndrawn] = o.cl_rows[r]
                ndrawn += 1usize
                r += 1usize
            }
            i += 1usize
        }
    } else {
        while i < nc {
            drawn[i] = clusters[i]
            i += 1usize
        }
    }
    t.left = left
    t.right = right
    t.svar = svar
    t.sval = sval
    t.ls_start = ls_start
    t.ls_len = ls_len
    t.ls = ls
    t.pv = pv
    t.pv_ok = pv_ok
    t.pc = pcv
    t.pcn = pcn
    t.nd = ndrawn
    t.drawn = drawn
    t.root = 0usize
    let mark = mem.mark(a)
    let (shuf, h1) = gz_usize(a, nc)
    let (perm, h2) = gz_usize(a, nbound)
    let (newr, h17) = gz_usize(a, lsbound)
    let (nstart, h3) = gz_usize(a, cap)
    let (nlen, h4) = gz_usize(a, cap)
    let (tmp, h5) = gz_usize(a, nbound)
    let (keys, h6) = gz_f64(a, nbound)
    let (ids, h7) = gz_usize(a, nbound)
    let (tk, h8) = gz_f64(a, nbound)
    let (ti, h9) = gz_usize(a, nbound)
    let (uniq, h10) = gz_f64(a, nbound)
    let (counter, h11) = gz_usize(a, nbound)
    let (sums, h12) = gz_f64(a, nbound)
    let (wsums, h13) = gz_f64(a, nbound)
    var nskip = 1usize
    if o.kind == 4usize { nskip = 2usize }
    if o.kind == 1usize {
        nskip = 2usize
        if d.zsep { nskip = 3usize }
    }
    if o.kind == 6usize { nskip = d.nout + d.ntr }
    if o.kind == 7usize { nskip = d.nout }
    if d.w.len > 0usize { nskip += 1usize }
    let ncol = d.p + nskip
    let (rmv, m1) = gz_f64(a, d.n * mrl)
    let (bsv, m2) = gz_f64(a, nbound * mrl)
    let (bwv, m3) = gz_f64(a, nbound * mkk)
    let (bqv, m4) = gz_f64(a, nbound * mkk)
    let (bmv, m5) = gz_usize(a, nbound * mkk)
    let (nvv, m6) = gz_f64(a, 2usize * mrl + 6usize * mkk + 2usize)
    let (nviv, m7) = gz_usize(a, 2usize * mkk)
    if m1 != ok { ret (t, m1) }
    if m2 != ok { ret (t, m2) }
    if m3 != ok { ret (t, m3) }
    if m4 != ok { ret (t, m4) }
    if m5 != ok { ret (t, m5) }
    if m6 != ok { ret (t, m6) }
    if m7 != ok { ret (t, m7) }
    let (resp, g1) = gz_f64(a, d.n)
    let (nsm, g2) = gz_usize(a, nbound)
    let (szv, g3) = gz_f64(a, nbound)
    let (szzv, g4) = gz_f64(a, nbound)
    if g1 != ok { ret (t, g1) }
    if g2 != ok { ret (t, g2) }
    if g3 != ok { ret (t, g3) }
    if g4 != ok { ret (t, g4) }
    var ncls = o.quantiles.len + 1usize
    if o.kind == 5usize { ncls = o.nclass }
    let (cutv, g5) = gz_f64(a, o.quantiles.len)
    let (clsv, g6) = gz_f64(a, nbound * ncls)
    let (ccv, g7) = gz_f64(a, ncls)
    if g5 != ok { ret (t, g5) }
    if g6 != ok { ret (t, g6) }
    if g7 != ok { ret (t, g7) }
    let lk = o.ll_vars.len + 1usize
    let (llxv, g8) = gz_f64(a, nbound * lk)
    let (llmv, g9) = gz_f64(a, lk * lk)
    let (llbv, g10) = gz_f64(a, lk)
    let (llzv, g11) = gz_f64(a, lk)
    if g8 != ok { ret (t, g8) }
    if g9 != ok { ret (t, g9) }
    if g10 != ok { ret (t, g10) }
    if g11 != ok { ret (t, g11) }
    let (relv, g12) = gz_usize(a, d.n)
    var svn = 1usize
    if o.kind == 4usize { svn = 8usize * (nbound + 2usize) }
    let (svv, g13) = gz_f64(a, svn)
    if g12 != ok { ret (t, g12) }
    if g13 != ok { ret (t, g13) }
    let (vars, h14) = gz_usize(a, ncol)
    let (flags, h15) = gz_bool(a, ncol)
    let (pool, h16) = gz_usize(a, ncol)
    if h1 != ok { ret (t, h1) }
    if h2 != ok { ret (t, h2) }
    if h17 != ok { ret (t, h17) }
    if h3 != ok { ret (t, h3) }
    if h4 != ok { ret (t, h4) }
    if h5 != ok { ret (t, h5) }
    if h6 != ok { ret (t, h6) }
    if h7 != ok { ret (t, h7) }
    if h8 != ok { ret (t, h8) }
    if h9 != ok { ret (t, h9) }
    if h10 != ok { ret (t, h10) }
    if h11 != ok { ret (t, h11) }
    if h12 != ok { ret (t, h12) }
    if h13 != ok { ret (t, h13) }
    if h14 != ok { ret (t, h14) }
    if h15 != ok { ret (t, h15) }
    if h16 != ok { ret (t, h16) }
    var sc: Scratch = zero
    sc.keys = keys
    sc.ids = ids
    sc.tk = tk
    sc.ti = ti
    sc.uniq = uniq
    sc.counter = counter
    sc.sums = sums
    sc.wsums = wsums
    sc.vars = vars
    sc.flags = flags
    sc.pool = pool
    sc.resp = resp
    sc.nsm = nsm
    sc.sz = szv
    sc.szz = szzv
    sc.cut = cutv
    sc.cls = clsv
    sc.cc = ccv
    sc.llx = llxv
    sc.llm = llmv
    sc.llb = llbv
    sc.llz = llzv
    sc.rel = relv
    sc.sv = svv
    sc.rm = rmv
    sc.bs = bsv
    sc.bw = bwv
    sc.bq = bqv
    sc.bm = bmv
    sc.nv = nvv
    sc.nvi = nviv
    i = 0usize
    while i < d.n {
        resp[i] = 0.0f64
        if o.kind == 0usize { resp[i] = d.y[i] }
        i += 1usize
    }
    i = 0usize
    while i < nc {
        shuf[i] = clusters[i]
        i += 1usize
    }
    if o.honesty { shuffle(g, shuf, nc) }
    if clustered {
        // RandomSampler::sample_from_clusters: the growing clusters' rows first, then the honest half's
        nsub = expand_clusters(g, o, shuf[0usize..nsubc], perm, tmp)
        nnew = expand_clusters(g, o, shuf[nsubc..nc], newr, tmp)
    } else {
        i = 0usize
        while i < nsub {
            perm[i] = shuf[i]
            i += 1usize
        }
        i = 0usize
        while i < nnew {
            newr[i] = shuf[nsub + i]
            i += 1usize
        }
    }
    var skip: [16]usize = zero
    var sk = 0usize
    while sk < 16usize {
        skip[sk] = d.p + sk
        sk += 1usize
    }
    let nindep = ncol - nskip
    nstart[0usize] = 0usize
    nlen[0usize] = nsub
    var nn = 1usize
    var open = 1usize
    var nodei = 0usize
    while open > 0usize {
        var mtry_s = poisson(g, f64(o.mtry))
        if mtry_s > nindep { mtry_s = nindep }
        if mtry_s < 1usize { mtry_s = 1usize }
        draw_vars(g, sc.vars, sc.flags, sc.pool, ncol, skip[0usize..nskip], mtry_s)
        let st = nstart[nodei]
        let ln = nlen[nodei]
        var found = false
        var best: Best = zero
        if ln > o.min_node_size {
            let node = perm[st..st + ln]
            let min_child = usize(math.max[f64](math.ceil[f64](f64(ln) * o.alpha), 1.0f64))
            var stop = false
            if o.kind == 1usize { stop = relabel_iv(d, &sc, node, o.rfw) }
            if o.kind == 3usize { relabel_ll(d, &sc, node, o) }
            if o.kind == 4usize {
                split_node_surv(d, &sc, node, mtry_s, o.alpha, nbound + 2usize, &best)
                if best.dec > 0.0f64 { found = true }
                stop = true
            }
            if o.kind == 6usize || o.kind == 7usize {
                stop = true
                var rstop = false
                if o.kind == 6usize {
                    rstop = relabel_multi(d, &sc, node)
                } else {
                    var rq = 0usize
                    while rq < ln {
                        var ro = 0usize
                        while ro < mrl {
                            sc.rm[node[rq] * mrl + ro] = d.ym[node[rq] * mrl + ro]
                            ro += 1usize
                        }
                        rq += 1usize
                    }
                }
                if !rstop {
                    // node sums: responses, then per treatment the weighted sum and sum of squares, the mean and the minimum child size
                    var wnode = 0.0f64
                    var q = 0usize
                    while q < 2usize * mrl + 6usize * mkk + 2usize {
                        sc.nv[q] = 0.0f64
                        q += 1usize
                    }
                    q = 0usize
                    while q < ln {
                        let s = node[q]
                        let w = weight_of(d, s)
                        wnode += w
                        var r = 0usize
                        while r < mrl {
                            sc.nv[r] += w * sc.rm[s * mrl + r]
                            r += 1usize
                        }
                        r = 0usize
                        while r < mkk {
                            let tv = d.tm[s * mkk + r]
                            sc.nv[mrl + r] += w * tv
                            sc.nv[mrl + mkk + r] += w * (tv * tv)
                            r += 1usize
                        }
                        q += 1usize
                    }
                    var u = 0usize
                    while u < mkk {
                        let sw1 = sc.nv[mrl + u]
                        let size_node = sc.nv[mrl + mkk + u] - sw1 * sw1 / wnode
                        sc.nv[mrl + 2usize * mkk + u] = sw1 / wnode
                        sc.nv[mrl + 3usize * mkk + u] = size_node * o.alpha
                        sc.nvi[u] = 0usize
                        u += 1usize
                    }
                    q = 0usize
                    while q < ln {
                        u = 0usize
                        while u < mkk {
                            if d.tm[node[q] * mkk + u] < sc.nv[mrl + 2usize * mkk + u] { sc.nvi[u] += 1usize }
                            u += 1usize
                        }
                        q += 1usize
                    }
                    sc.nv[2usize * mrl + 6usize * mkk] = wnode
                    sc.nv[2usize * mrl + 6usize * mkk + 1usize] = f64(min_child)
                    q = 0usize
                    while q < mtry_s {
                        split_multi(d, &sc, node, sc.vars[q], o.kind == 6usize && o.stabilize, mkk, mrl, o.min_node_size, o.imbalance_penalty, &best)
                        q += 1usize
                    }
                    if best.dec > 0.0f64 { found = true }
                }
            }
            if o.kind == 2usize || o.kind == 5usize {
                if o.kind == 2usize { relabel_quantile(d, &sc, node, o.quantiles) }
                if o.kind == 5usize {
                    var rq = 0usize
                    while rq < ln {
                        sc.resp[node[rq]] = d.y[node[rq]]
                        rq += 1usize
                    }
                }
                var c = 0usize
                while c < ncls {
                    sc.cc[c] = 0.0f64
                    c += 1usize
                }
                var q = 0usize
                while q < ln {
                    sc.cc[usize(sc.resp[node[q]])] += weight_of(d, node[q])
                    q += 1usize
                }
                q = 0usize
                while q < mtry_s {
                    split_value_prob(d, &sc, node, sc.vars[q], ncls, min_child, o.imbalance_penalty, &best)
                    q += 1usize
                }
                if best.dec > 0.0f64 { found = true }
                stop = true
            }
            if !stop {
                var wsum_node = 0.0f64
                var sum_node = 0.0f64
                var sum_z = 0.0f64
                var sum_zz = 0.0f64
                var q = 0usize
                while q < ln {
                    let w = weight_of(d, node[q])
                    wsum_node += w
                    sum_node += w * sc.resp[node[q]]
                    if o.kind == 1usize {
                        let z = inst_of(d, node[q])
                        sum_z += w * z
                        sum_zz += w * z * z
                    }
                    q += 1usize
                }
                if o.kind == 1usize && o.stabilize {
                    var nd: IvNode = zero
                    nd.wsum = wsum_node
                    nd.sum = sum_node
                    nd.sum_z = sum_z
                    nd.sum_zz = sum_zz
                    nd.mean_z = sum_z / wsum_node
                    nd.min_child = (sum_zz - sum_z * sum_z / wsum_node) * o.alpha
                    q = 0usize
                    while q < ln {
                        if inst_of(d, node[q]) < nd.mean_z { nd.nsmall += 1usize }
                        q += 1usize
                    }
                    q = 0usize
                    while q < mtry_s {
                        split_value_iv(d, &sc, node, sc.vars[q], &nd, o.min_node_size, o.imbalance_penalty, &best)
                        q += 1usize
                    }
                } else {
                    q = 0usize
                    while q < mtry_s {
                        split_value(d, &sc, node, sc.vars[q], wsum_node, sum_node, min_child, o.imbalance_penalty, &best)
                        q += 1usize
                    }
                }
                if best.dec > 0.0f64 { found = true }
            }
        }
        if !found {
            open -= 1usize
        } else {
            svar[nodei] = best.sv
            sval[nodei] = best.val
            let lc = nn
            let rc = nn + 1usize
            left[nodei] = lc
            right[nodei] = rc
            nn += 2usize
            var nl = 0usize
            var nr = 0usize
            var q = 0usize
            while q < ln {
                let s = perm[st + q]
                if d.x[s * d.p + best.sv] <= best.val {
                    perm[st + nl] = s
                    nl += 1usize
                } else {
                    tmp[nr] = s
                    nr += 1usize
                }
                q += 1usize
            }
            q = 0usize
            while q < nr {
                perm[st + nl + q] = tmp[q]
                q += 1usize
            }
            nstart[lc] = st
            nlen[lc] = nl
            nstart[rc] = st + nl
            nlen[rc] = nr
            open += 1usize
        }
        nodei += 1usize
    }
    t.nn = nn
    // leaf samples: the honest half routed through the grown tree, or the growing samples themselves
    var total = 0usize
    if o.honesty && nnew > 0usize {
        var q = 0usize
        while q < nn {
            ls_len[q] = 0usize
            q += 1usize
        }
        q = 0usize
        while q < nnew {
            let s = newr[q]
            let lf = find_leaf(&t, d.x, d.p, s)
            ls_len[lf] += 1usize
            q += 1usize
        }
        q = 0usize
        while q < nn {
            ls_start[q] = total
            total += ls_len[q]
            ls_len[q] = 0usize
            q += 1usize
        }
        q = 0usize
        while q < nnew {
            let s = newr[q]
            let lf = find_leaf(&t, d.x, d.p, s)
            ls[ls_start[lf] + ls_len[lf]] = s
            ls_len[lf] += 1usize
            q += 1usize
        }
        if o.honesty_prune { honesty_prune(&t) }
    } else {
        var q = 0usize
        while q < nsub {
            ls[q] = perm[q]
            q += 1usize
        }
        q = 0usize
        while q < nn {
            ls_start[q] = nstart[q]
            ls_len[q] = nlen[q]
            if !is_leaf(&t, q) { ls_len[q] = 0usize }
            q += 1usize
        }
    }
    if o.kind == 6usize || o.kind == 7usize {
        let kk = d.ntr
        let no = d.nout
        var lq = 0usize
        while lq < nn {
            let cnt = ls_len[lq]
            if cnt > 0usize {
                var sw = 0.0f64
                var sy: [8]f64 = zero
                var swt: [8]f64 = zero
                var syw: [64]f64 = zero
                var sww: [64]f64 = zero
                var r = 0usize
                while r < cnt {
                    let s = ls[ls_start[lq] + r]
                    let w = weight_of(d, s)
                    var j = 0usize
                    if o.kind == 7usize {
                        while j < no {
                            sy[j] += w * d.ym[s * no + j]
                            j += 1usize
                        }
                    } else {
                        while j < no {
                            sy[j] += w * d.ym[s * no + j]
                            j += 1usize
                        }
                        j = 0usize
                        while j < kk {
                            swt[j] += w * d.tm[s * kk + j]
                            var jo = 0usize
                            while jo < no {
                                syw[jo * kk + j] += (w * d.tm[s * kk + j]) * d.ym[s * no + jo]
                                jo += 1usize
                            }
                            var jk = 0usize
                            while jk < kk {
                                sww[jk * kk + j] += (w * d.tm[s * kk + j]) * d.tm[s * kk + jk]
                                jk += 1usize
                            }
                            j += 1usize
                        }
                    }
                    sw += w
                    r += 1usize
                }
                if math.abs[f64](sw) > 1.0e-16f64 {
                    pv_ok[lq] = true
                    let b = lq * pcn
                    let c = f64(cnt)
                    if o.kind == 7usize {
                        var j = 0usize
                        while j < no {
                            pcv[b + j] = sy[j] / c
                            j += 1usize
                        }
                        pcv[b + no] = sw / c
                    } else {
                        var at = 0usize
                        pcv[b] = sw / c
                        at = 1usize
                        var j = 0usize
                        while j < no {
                            pcv[b + at] = sy[j] / c
                            at += 1usize
                            j += 1usize
                        }
                        j = 0usize
                        while j < kk {
                            pcv[b + at] = swt[j] / c
                            at += 1usize
                            j += 1usize
                        }
                        j = 0usize
                        while j < kk * no {
                            pcv[b + at] = syw[j] / c
                            at += 1usize
                            j += 1usize
                        }
                        j = 0usize
                        while j < kk * kk {
                            pcv[b + at] = sww[j] / c
                            at += 1usize
                            j += 1usize
                        }
                    }
                }
            }
            lq += 1usize
        }
        mem.reset(a, mark)
        ret (t, ok)
    }
    var q = 0usize
    while q < nn {
        let cnt = ls_len[q]
        if cnt > 0usize {
            var sy = 0.0f64
            var sw = 0.0f64
            var st2 = 0.0f64
            var si2 = 0.0f64
            var syz = 0.0f64
            var swz = 0.0f64
            var szz = 0.0f64
            var wt = 0.0f64
            var r = 0usize
            while r < cnt {
                let s = ls[ls_start[q] + r]
                let w = weight_of(d, s)
                sy += w * d.y[s]
                wt += w
                if o.kind == 1usize {
                    let z = inst_of(d, s)
                    sw += w * d.t[s]
                    si2 += w * z
                    syz += w * d.y[s] * z
                    swz += w * d.t[s] * z
                    szz += w * z * z
                }
                r += 1usize
            }
            if o.kind == 5usize && math.abs[f64](wt) > 1.0e-16f64 {
                r = 0usize
                while r < cnt {
                    let s = ls[ls_start[q] + r]
                    pcv[q * pcn + usize(d.y[s])] += weight_of(d, s)
                    r += 1usize
                }
                var kc = 0usize
                while kc < o.nclass {
                    pcv[q * pcn + kc] = pcv[q * pcn + kc] / f64(cnt)
                    kc += 1usize
                }
                pcv[q * pcn + o.nclass] = wt / f64(cnt)
            }
            if math.abs[f64](wt) > 1.0e-16f64 {
                pv_ok[q] = true
                let b = q * NV
                let c = f64(cnt)
                pv[b + V_OUT] = sy / c
                pv[b + V_WT] = wt / c
                pv[b + V_TR] = sw / c
                pv[b + V_INST] = si2 / c
                pv[b + V_OI] = syz / c
                pv[b + V_TI] = swz / c
                pv[b + V_II] = szz / c
            }
        }
        q += 1usize
    }
    mem.reset(a, mark)
    ret (t, ok)
}

// RandomSampler::sample: 0..n-1 shuffled whole; the caller keeps the first `take`
fn sample_rows(g: *Mt64, out: []usize, n: usize) {
    var i = 0usize
    while i < n {
        out[i] = i
        i += 1usize
    }
    shuffle(g, out, n)
}

fn train(a: *mem.Arena, d: *const Data, o0: *const Opts) -> (Forest, err) {
    var f: Forest = zero
    var oc = *o0
    let o = &oc
    // SamplingOptions: cluster labels become ids in order of first appearance; rows keep their order inside a cluster
    var nu = d.n
    if o0.cluster.len > 0usize {
        let (cid, c1) = gz_usize(a, d.n)
        let (cstart, c2) = gz_usize(a, d.n + 2usize)
        let (crows, c3) = gz_usize(a, d.n)
        let (cnt, c4) = gz_usize(a, d.n + 1usize)
        let (lab, c5) = gz_usize(a, d.n)
        if c1 != ok { ret (f, c1) }
        if c2 != ok { ret (f, c2) }
        if c3 != ok { ret (f, c3) }
        if c4 != ok { ret (f, c4) }
        if c5 != ok { ret (f, c5) }
        var kk = 0usize
        var s = 0usize
        while s < d.n {
            var found = false
            var q = 0usize
            while q < kk {
                if lab[q] == o0.cluster[s] {
                    cid[s] = q
                    found = true
                    q = kk
                }
                q += 1usize
            }
            if !found {
                lab[kk] = o0.cluster[s]
                cid[s] = kk
                kk += 1usize
            }
            cnt[cid[s]] += 1usize
            s += 1usize
        }
        var run = 0usize
        var cq = 0usize
        var smin = d.n
        var smax = 0usize
        while cq < kk {
            cstart[cq] = run
            run += cnt[cq]
            if cnt[cq] < smin { smin = cnt[cq] }
            if cnt[cq] > smax { smax = cnt[cq] }
            cnt[cq] = 0usize
            cq += 1usize
        }
        cstart[kk] = run
        s = 0usize
        while s < d.n {
            crows[cstart[cid[s]] + cnt[cid[s]]] = s
            cnt[cid[s]] += 1usize
            s += 1usize
        }
        oc.cl_start = cstart[0usize..kk + 1usize]
        oc.cl_rows = crows
        oc.spc = smax
        if o0.equalize { oc.spc = smin }
        nu = kk
    }
    let ci = o.ci_group_size
    let groups = o.num_trees / ci
    let ntree = groups * ci
    let (trees, te) = mem.alloc[Tree](a, ntree + 1usize)
    let (pool, pe) = gz_usize(a, nu)
    let (sub, se) = gz_usize(a, nu)
    if te != ok { ret (f, te) }
    if pe != ok { ret (f, pe) }
    if se != ok { ret (f, se) }
    f.trees = trees
    f.ntree = ntree
    f.ci = ci
    f.p = d.p
    f.n = d.n
    var g: Mt64 = zero
    var gi = 0usize
    var ti = 0usize
    while gi < groups {
        mt64_seed(&g, (o.seed + u64(gi)) & 4294967295u64)
        if ci == 1usize {
            let take = usize(f64(nu) * o.sample_fraction)
            sample_rows(&g, pool, nu)
            let (t, e) = train_tree(a, d, &g, pool[0usize..take], o)
            if e != ok { ret (f, e) }
            trees[ti] = t
            ti += 1usize
        } else {
            let half = usize(f64(nu) * 0.5f64)
            sample_rows(&g, pool, nu)
            var j = 0usize
            while j < ci {
                let sz = ceil_size(half, o.sample_fraction * 2.0f64)
                var q = 0usize
                while q < half {
                    sub[q] = pool[q]
                    q += 1usize
                }
                shuffle(&g, sub, half)
                let (t, e) = train_tree(a, d, &g, sub[0usize..sz], o)
                if e != ok { ret (f, e) }
                trees[ti] = t
                ti += 1usize
                j += 1usize
            }
        }
        gi += 1usize
    }
    ret (f, ok)
}

// ObjectiveBayesDebiaser::debias
fn debias(var_between: f64, group_noise: f64, num_good: f64) -> f64 {
    let initial = var_between - group_noise
    let se = math.max[f64](var_between, group_noise) * math.sqrt[f64](2.0f64 / num_good)
    if se == se && math.abs[f64](se) < 1.0e-10f64 { ret 0.0f64 }
    let ratio = initial / se
    let numerator = math.exp[f64](0.0f64 - ratio * ratio / 2.0f64) * 0.3989422804f64
    let denominator = 0.5f64 * special.erfc(0.0f64 - ratio * 0.70710678118f64)
    ret initial + se * numerator / denominator
}

// the forest-averaged estimate from the averaged leaf values
fn point_est(kind: usize, avg: []const f64) -> f64 {
    if kind == 1usize {
        let num = avg[V_OI] * avg[V_WT] - avg[V_OUT] * avg[V_INST]
        let den = avg[V_TI] * avg[V_WT] - avg[V_TR] * avg[V_INST]
        ret num / den
    }
    ret avg[V_OUT] / avg[V_WT]
}

// the pseudo-outcome of one leaf for the bootstrap of little bags
fn rho_of(kind: usize, avg: []const f64, pv: []const f64, b: usize, est: f64) -> f64 {
    if kind == 1usize {
        let den = avg[V_TI] * avg[V_WT] - avg[V_TR] * avg[V_INST]
        let main = (avg[V_OUT] - avg[V_TR] * est) / avg[V_WT]
        let psi1 = pv[b + V_OI] - pv[b + V_TI] * est - pv[b + V_INST] * main
        let psi2 = pv[b + V_OUT] - pv[b + V_TR] * est - pv[b + V_WT] * main
        ret (avg[V_WT] * psi1 - avg[V_INST] * psi2) / den
    }
    ret (pv[b + V_OUT] - est * pv[b + V_WT]) / avg[V_WT]
}

// InstrumentalPredictionStrategy::compute_error: (debiased, excess), NaN with five trees or fewer
fn error_iv(avg: []const f64, f: *const Forest, lnode: []const usize, lok: []const bool, y: f64, z: f64, ntr: usize, out: []f64) {
    let rf_num = avg[V_OI] * avg[V_WT] - avg[V_OUT] * avg[V_INST]
    let rf_den = avg[V_II] * avg[V_WT] - avg[V_INST] * avg[V_INST]
    let rf = rf_num / rf_den
    let resid = y - (z - avg[V_INST] / avg[V_WT]) * rf - avg[V_OUT] / avg[V_WT]
    let raw = resid * resid
    if ntr <= 5usize {
        out[0usize] = special.nan()
        out[1usize] = special.nan()
        ret
    }
    let nt = f64(ntr)
    var bias = 0.0f64
    var t = 0usize
    while t < f.ntree {
        if lok[t] {
            let pv = f.trees[t].pv
            let b = lnode[t] * NV
            let wl = (nt * avg[V_WT] - pv[b + V_WT]) / (nt - 1.0f64)
            let ol = (nt * avg[V_OUT] - pv[b + V_OUT]) / (nt - 1.0f64)
            let il = (nt * avg[V_INST] - pv[b + V_INST]) / (nt - 1.0f64)
            let oil = (nt * avg[V_OI] - pv[b + V_OI]) / (nt - 1.0f64)
            let iil = (nt * avg[V_II] - pv[b + V_II]) / (nt - 1.0f64)
            let rfl = (oil * wl - ol * il) / (iil * wl - il * il)
            let rl = y - (z - il / wl) * rfl - ol / wl
            bias += (rl - resid) * (rl - resid)
        }
        t += 1usize
    }
    bias *= (nt - 1.0f64) / nt
    out[0usize] = raw - bias
    out[1usize] = bias
}

// Predictions at the rows of xnew (nnew by p, row-major), or the out-of-bag predictions at the training rows when oob. `want_var` needs ci_group_size > 1.
// Error estimates (debiased.error, excess.error) are produced for oob only, as in R.
fn predict(a: *mem.Arena, f: *const Forest, d: *const Data, xnew: []const f64, nnew: usize, oob: bool, want_var: bool, kind: usize) -> (Pred, err) {
    var r: Pred = zero
    let (pred, e1) = gz_f64(a, nnew)
    let (vest, e2) = gz_f64(a, nnew)
    let (derr, e3) = gz_f64(a, nnew)
    let (exc, e4) = gz_f64(a, nnew)
    let (avg, e5) = gz_f64(a, NV)
    let (lnode, e6) = gz_usize(a, f.ntree)
    let (lok, e7) = gz_bool(a, f.ntree)
    let (inbag, e8) = gz_bool(a, f.ntree * f.n)
    let (eo, e9) = gz_f64(a, 2usize)
    if e1 != ok { ret (r, e1) }
    if e2 != ok { ret (r, e2) }
    if e3 != ok { ret (r, e3) }
    if e4 != ok { ret (r, e4) }
    if e5 != ok { ret (r, e5) }
    if e6 != ok { ret (r, e6) }
    if e7 != ok { ret (r, e7) }
    if e8 != ok { ret (r, e8) }
    if e9 != ok { ret (r, e9) }
    r.pred = pred
    r.var_est = vest
    r.err = derr
    r.exc = exc
    let nan = special.nan()
    if oob {
        var t = 0usize
        while t < f.ntree {
            var q = 0usize
            while q < f.trees[t].nd {
                inbag[t * f.n + f.trees[t].drawn[q]] = true
                q += 1usize
            }
            t += 1usize
        }
    }
    var s = 0usize
    while s < nnew {
        var k = 0usize
        while k < NV {
            avg[k] = 0.0f64
            k += 1usize
        }
        var nleaves = 0usize
        var t = 0usize
        while t < f.ntree {
            lok[t] = false
            if oob && inbag[t * f.n + s] {
                t += 1usize
                continue
            }
            let tr = &f.trees[t]
            let node = find_leaf(tr, xnew, f.p, s)
            if tr.pv_ok[node] {
                nleaves += 1usize
                lnode[t] = node
                lok[t] = true
                k = 0usize
                while k < NV {
                    avg[k] += tr.pv[node * NV + k]
                    k += 1usize
                }
            }
            t += 1usize
        }
        if nleaves == 0usize {
            pred[s] = nan
            vest[s] = nan
            derr[s] = nan
            exc[s] = nan
            s += 1usize
            continue
        }
        k = 0usize
        while k < NV {
            avg[k] = avg[k] / f64(nleaves)
            k += 1usize
        }
        let mu = point_est(kind, avg)
        pred[s] = mu
        if want_var {
            var good = 0.0f64
            var rho_sq = 0.0f64
            var rho_grp_sq = 0.0f64
            var grp = 0usize
            while grp < f.ntree / f.ci {
                var all_ok = true
                var j = 0usize
                while j < f.ci {
                    if !lok[grp * f.ci + j] { all_ok = false }
                    j += 1usize
                }
                if all_ok {
                    good += 1.0f64
                    var group_rho = 0.0f64
                    j = 0usize
                    while j < f.ci {
                        let ti = grp * f.ci + j
                        let rho = rho_of(kind, avg, f.trees[ti].pv, lnode[ti] * NV, mu)
                        rho_sq += rho * rho
                        group_rho += rho
                        j += 1usize
                    }
                    group_rho /= f64(f.ci)
                    rho_grp_sq += group_rho * group_rho
                }
                grp += 1usize
            }
            let var_between = rho_grp_sq / good
            let var_total = rho_sq / (good * f64(f.ci))
            let group_noise = (var_total - var_between) / f64(f.ci - 1usize)
            vest[s] = debias(var_between, group_noise, good)
        }
        if oob && kind == 1usize {
            error_iv(avg, f, lnode, lok, d.y[s], inst_of(d, s), nleaves, eo)
            derr[s] = eo[0usize]
            exc[s] = eo[1usize]
        } else if oob {
            let er = mu - d.y[s]
            let mse = er * er
            var bias = 0.0f64
            var cnt = 0usize
            t = 0usize
            while t < f.ntree {
                if lok[t] {
                    let tv = rho_of(kind, avg, f.trees[t].pv, lnode[t] * NV, mu)
                    bias += tv * tv
                    cnt += 1usize
                }
                t += 1usize
            }
            if cnt <= 1usize {
                derr[s] = nan
                exc[s] = nan
            } else {
                bias /= f64(cnt * (cnt - 1usize))
                derr[s] = mse - bias
                exc[s] = bias
            }
        }
        s += 1usize
    }
    ret (r, ok)
}

// probability_forest predictions: pred and vest are nnew by nclass row-major (vest only when want_var); a row with no usable tree is NaN
fn predict_prob(a: *mem.Arena, f: *const Forest, xnew: []const f64, nnew: usize, oob: bool, want_var: bool, nclass: usize, pred: []f64, vest: []f64) -> err {
    let pcn = nclass + 1usize
    let (avg, e5) = gz_f64(a, pcn)
    let (lnode, e6) = gz_usize(a, f.ntree)
    let (lok, e7) = gz_bool(a, f.ntree)
    let (inbag, e8) = gz_bool(a, f.ntree * f.n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    let nan = special.nan()
    if oob {
        var t = 0usize
        while t < f.ntree {
            var q = 0usize
            while q < f.trees[t].nd {
                inbag[t * f.n + f.trees[t].drawn[q]] = true
                q += 1usize
            }
            t += 1usize
        }
    }
    var s = 0usize
    while s < nnew {
        var k = 0usize
        while k < pcn {
            avg[k] = 0.0f64
            k += 1usize
        }
        var nleaves = 0usize
        var t = 0usize
        while t < f.ntree {
            lok[t] = false
            if oob && inbag[t * f.n + s] {
                t += 1usize
                continue
            }
            let tr = &f.trees[t]
            let node = find_leaf(tr, xnew, f.p, s)
            if tr.pv_ok[node] {
                nleaves += 1usize
                lnode[t] = node
                lok[t] = true
                k = 0usize
                while k < pcn {
                    avg[k] += tr.pc[node * pcn + k]
                    k += 1usize
                }
            }
            t += 1usize
        }
        if nleaves == 0usize {
            k = 0usize
            while k < nclass {
                pred[s * nclass + k] = nan
                if want_var { vest[s * nclass + k] = nan }
                k += 1usize
            }
            s += 1usize
            continue
        }
        k = 0usize
        while k < pcn {
            avg[k] = avg[k] / f64(nleaves)
            k += 1usize
        }
        let wbar = avg[nclass]
        var c = 0usize
        while c < nclass {
            let mu = avg[c] / wbar
            pred[s * nclass + c] = mu
            if want_var {
                var good = 0.0f64
                var rho_sq = 0.0f64
                var rho_grp_sq = 0.0f64
                var grp = 0usize
                while grp < f.ntree / f.ci {
                    var all_ok = true
                    var j = 0usize
                    while j < f.ci {
                        if !lok[grp * f.ci + j] { all_ok = false }
                        j += 1usize
                    }
                    if all_ok {
                        good += 1.0f64
                        var group_rho = 0.0f64
                        j = 0usize
                        while j < f.ci {
                            let ti = grp * f.ci + j
                            let b = lnode[ti] * pcn
                            let rho = (f.trees[ti].pc[b + c] - mu * f.trees[ti].pc[b + nclass]) / wbar
                            rho_sq += rho * rho
                            group_rho += rho
                            j += 1usize
                        }
                        group_rho /= f64(f.ci)
                        rho_grp_sq += group_rho * group_rho
                    }
                    grp += 1usize
                }
                let var_between = rho_grp_sq / good
                let var_total = rho_sq / (good * f64(f.ci))
                let group_noise = (var_total - var_between) / f64(f.ci - 1usize)
                vest[s * nclass + c] = debias(var_between, group_noise, good)
            }
            c += 1usize
        }
        s += 1usize
    }
    ret ok
}

// multi_arm_causal_forest (kind 6: K treatment columns, nout outcomes; pred[s * K * nout + t + K * o] is the effect of treatment t on outcome o, vest[s * K + t]
// the variance estimate, one outcome only) and multi_regression_forest (kind 7: pred[s * nout + o]); d carries the training counts
fn predict_multi(a: *mem.Arena, f: *const Forest, kind: usize, kk: usize, no: usize, xnew: []const f64, nnew: usize, oob: bool, want_var: bool, pred: []f64, vest: []f64) -> err {
    var pcn = no + 1usize
    var plen = no
    if kind == 6usize {
        pcn = kk * (kk + no + 1usize) + no + 1usize
        plen = kk * no
    }
    let (avg, e5) = gz_f64(a, pcn)
    let (lnode, e6) = gz_usize(a, f.ntree)
    let (lok, e7) = gz_bool(a, f.ntree)
    let (inbag, e8) = gz_bool(a, f.ntree * f.n)
    let (m1, e9) = gz_f64(a, kk * kk)
    let (m2, e10) = gz_f64(a, kk * kk)
    let (m3, e11) = gz_f64(a, kk * kk)
    let (m4, e12) = gz_f64(a, kk * kk)
    let (wk, e13) = gz_f64(a, kk * kk)
    let (v1, e14) = gz_f64(a, kk)
    let (v2, e15) = gz_f64(a, kk)
    let (v3, e16) = gz_f64(a, kk)
    let (v4, e17) = gz_f64(a, kk)
    let (v5, e18) = gz_f64(a, kk)
    let (v6, e19) = gz_f64(a, kk)
    let (v7, e20) = gz_f64(a, kk)
    let (v8, e21) = gz_f64(a, kk)
    let (v9, e22) = gz_f64(a, kk)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    if e19 != ok { ret e19 }
    if e20 != ok { ret e20 }
    if e21 != ok { ret e21 }
    if e22 != ok { ret e22 }
    let nan = special.nan()
    if oob {
        var t = 0usize
        while t < f.ntree {
            var q = 0usize
            while q < f.trees[t].nd {
                inbag[t * f.n + f.trees[t].drawn[q]] = true
                q += 1usize
            }
            t += 1usize
        }
    }
    let i_y = 1usize
    let i_w = 1usize + no
    let i_yw = 1usize + no + kk
    let i_ww = 1usize + no + kk + kk * no
    var s = 0usize
    while s < nnew {
        var k = 0usize
        while k < pcn {
            avg[k] = 0.0f64
            k += 1usize
        }
        var nleaves = 0usize
        var t = 0usize
        while t < f.ntree {
            lok[t] = false
            if oob && inbag[t * f.n + s] {
                t += 1usize
                continue
            }
            let tr = &f.trees[t]
            let node = find_leaf(tr, xnew, f.p, s)
            if tr.pv_ok[node] {
                nleaves += 1usize
                lnode[t] = node
                lok[t] = true
                k = 0usize
                while k < pcn {
                    avg[k] += tr.pc[node * pcn + k]
                    k += 1usize
                }
            }
            t += 1usize
        }
        if nleaves == 0usize {
            k = 0usize
            while k < plen {
                pred[s * plen + k] = nan
                k += 1usize
            }
            if want_var {
                k = 0usize
                while k < kk {
                    vest[s * kk + k] = nan
                    k += 1usize
                }
            }
            s += 1usize
            continue
        }
        k = 0usize
        while k < pcn {
            avg[k] = avg[k] / f64(nleaves)
            k += 1usize
        }
        if kind == 7usize {
            k = 0usize
            while k < no {
                pred[s * plen + k] = avg[k] / avg[no]
                k += 1usize
            }
            s += 1usize
            continue
        }
        let wbar = avg[0usize]
        // theta = (WW wbar - W W') ^ -1 (YW wbar - W Y'), kk by no
        var a1 = 0usize
        while a1 < kk {
            var b1 = 0usize
            while b1 < kk {
                m1[a1 * kk + b1] = avg[i_ww + b1 * kk + a1] * wbar - avg[i_w + a1] * avg[i_w + b1]
                b1 += 1usize
            }
            a1 += 1usize
        }
        let _d1 = lu_inverse(m1, kk, m2, wk)
        var o1 = 0usize
        while o1 < no {
            var a2 = 0usize
            while a2 < kk {
                var acc = 0.0f64
                var b2 = 0usize
                while b2 < kk {
                    acc += m2[a2 * kk + b2] * (avg[i_yw + o1 * kk + b2] * wbar - avg[i_w + b2] * avg[i_y + o1])
                    b2 += 1usize
                }
                pred[s * plen + a2 + kk * o1] = acc
                a2 += 1usize
            }
            o1 += 1usize
        }
        if want_var {
            // one outcome: v1 = theta
            a1 = 0usize
            while a1 < kk {
                v1[a1] = pred[s * plen + a1]
                a1 += 1usize
            }
            var tw = 0.0f64
            a1 = 0usize
            while a1 < kk {
                tw += v1[a1] * avg[i_w + a1]
                a1 += 1usize
            }
            let main_effect = (avg[i_y] - tw) / wbar
            // WW ^ -1
            a1 = 0usize
            while a1 < kk {
                var b1 = 0usize
                while b1 < kk {
                    m3[a1 * kk + b1] = avg[i_ww + b1 * kk + a1]
                    b1 += 1usize
                }
                a1 += 1usize
            }
            let _d2 = lu_inverse(m3, kk, m4, wk)
            // v2 = WWi W
            a1 = 0usize
            while a1 < kk {
                var acc = 0.0f64
                var b1 = 0usize
                while b1 < kk {
                    acc += m4[a1 * kk + b1] * avg[i_w + b1]
                    b1 += 1usize
                }
                v2[a1] = acc
                a1 += 1usize
            }
            var wwiw = 0.0f64
            a1 = 0usize
            while a1 < kk {
                wwiw += avg[i_w + a1] * v2[a1]
                a1 += 1usize
            }
            let kcoef = wbar - wwiw
            // term1 = WWi + (1 / k) (WWi W) (WWi W)' (WWi symmetric); term2 = (1 / k) WWi W
            a1 = 0usize
            while a1 < kk {
                var b1 = 0usize
                while b1 < kk {
                    m1[a1 * kk + b1] = m4[a1 * kk + b1] + 1.0f64 / kcoef * v2[a1] * v2[b1]
                    b1 += 1usize
                }
                v3[a1] = 1.0f64 / kcoef * v2[a1]
                a1 += 1usize
            }
            var good = 0.0f64
            a1 = 0usize
            while a1 < kk {
                v4[a1] = 0.0f64
                v5[a1] = 0.0f64
                a1 += 1usize
            }
            var grp = 0usize
            while grp < f.ntree / f.ci {
                var all_ok = true
                var j = 0usize
                while j < f.ci {
                    if !lok[grp * f.ci + j] { all_ok = false }
                    j += 1usize
                }
                if all_ok {
                    good += 1.0f64
                    a1 = 0usize
                    while a1 < kk {
                        v6[a1] = 0.0f64
                        a1 += 1usize
                    }
                    j = 0usize
                    while j < f.ci {
                        let ti = grp * f.ci + j
                        let b = lnode[ti] * pcn
                        let pcv = f.trees[ti].pc
                        // psi_1 = leaf_YW - leaf_WW theta - leaf_W main_effect, psi_2 = leaf_Y - leaf_W' theta - leaf_weight main_effect
                        a1 = 0usize
                        while a1 < kk {
                            var lw = 0.0f64
                            var b1 = 0usize
                            while b1 < kk {
                                lw += pcv[b + i_ww + b1 * kk + a1] * v1[b1]
                                b1 += 1usize
                            }
                            v7[a1] = pcv[b + i_yw + a1] - lw - pcv[b + i_w + a1] * main_effect
                            a1 += 1usize
                        }
                        var lwt = 0.0f64
                        a1 = 0usize
                        while a1 < kk {
                            lwt += pcv[b + i_w + a1] * v1[a1]
                            a1 += 1usize
                        }
                        let psi2 = pcv[b + i_y] - lwt - pcv[b] * main_effect
                        a1 = 0usize
                        while a1 < kk {
                            var r1 = 0.0f64
                            var b1 = 0usize
                            while b1 < kk {
                                r1 += m1[a1 * kk + b1] * v7[b1]
                                b1 += 1usize
                            }
                            let rho = r1 - v3[a1] * psi2
                            v4[a1] += rho * rho
                            v6[a1] += rho
                            a1 += 1usize
                        }
                        j += 1usize
                    }
                    a1 = 0usize
                    while a1 < kk {
                        let gr = v6[a1] / f64(f.ci)
                        v5[a1] += gr * gr
                        a1 += 1usize
                    }
                }
                grp += 1usize
            }
            a1 = 0usize
            while a1 < kk {
                let var_between = v5[a1] / good
                let var_total = v4[a1] / (good * f64(f.ci))
                let group_noise = (var_total - var_between) / f64(f.ci - 1usize)
                vest[s * kk + a1] = debias(var_between, group_noise, good)
                a1 += 1usize
            }
        }
        s += 1usize
    }
    ret ok
}

// boosted_regression_forest: a regression forest, then forests on the out-of-bag residuals. steps 0 stops by the error-reduction test on a small forest
// (boost.error.reduction, boost.max.steps, boost.trees.tune); otherwise exactly `steps` forests are grown. d.y is the outcome; o the regression options.
type Boosted = struct { forests: []Forest, nf: usize, yhat: []f64, errs: []f64 }

fn mean_na(v: []const f64, n: usize, skip_nan: bool) -> f64 {
    var s = 0.0f64
    var k = 0usize
    var i = 0usize
    while i < n {
        if !(skip_nan && v[i] != v[i]) {
            s += v[i]
            k += 1usize
        }
        i += 1usize
    }
    ret s / f64(k)
}

fn boosted(a: *mem.Arena, d: *const Data, o: *const Opts, steps: usize, reduction: f64, max_steps: usize, tune_trees: usize) -> (Boosted, err) {
    var b: Boosted = zero
    let n = d.n
    var cap = steps
    if steps == 0usize { cap = max_steps }
    let (forests, e1) = mem.alloc[Forest](a, cap + 1usize)
    let (yhat, e2) = gz_f64(a, n)
    let (errs, e3) = gz_f64(a, cap + 1usize)
    let (resid, e4) = gz_f64(a, n)
    if e1 != ok { ret (b, e1) }
    if e2 != ok { ret (b, e2) }
    if e3 != ok { ret (b, e3) }
    if e4 != ok { ret (b, e4) }
    b.forests = forests
    b.yhat = yhat
    b.errs = errs
    var dd = *d
    var oo = *o
    let (f0, fe0) = train(a, &dd, &oo)
    if fe0 != ok { ret (b, fe0) }
    let (p0, pe0) = predict(a, &f0, &dd, dd.x, n, true, false, 0usize)
    if pe0 != ok { ret (b, pe0) }
    forests[0usize] = f0
    var i = 0usize
    while i < n {
        yhat[i] = p0.pred[i]
        i += 1usize
    }
    var cur_err = p0.err
    errs[0usize] = mean_na(cur_err, n, false)
    var nf = 1usize
    var step = 2usize
    while true {
        i = 0usize
        while i < n {
            resid[i] = d.y[i] - yhat[i]
            i += 1usize
        }
        if steps > 0usize {
            if step > steps { break }
        } else if step > max_steps {
            break
        } else {
            var os = *o
            os.num_trees = tune_trees
            var ds = *d
            ds.y = resid
            let (fs, fse) = train(a, &ds, &os)
            if fse != ok { ret (b, fse) }
            let (ps, pse) = predict(a, &fs, &ds, ds.x, n, true, false, 0usize)
            if pse != ok { ret (b, pse) }
            let ms = mean_na(ps.err, n, true)
            let mc = mean_na(cur_err, n, true)
            if !(ms <= reduction * mc) { break }
        }
        var dr = *d
        dr.y = resid
        let (fr, fre) = train(a, &dr, &oo)
        if fre != ok { ret (b, fre) }
        let (pr, pre) = predict(a, &fr, &dr, dr.x, n, true, false, 0usize)
        if pre != ok { ret (b, pre) }
        i = 0usize
        while i < n {
            yhat[i] += pr.pred[i]
            i += 1usize
        }
        cur_err = pr.err
        forests[nf] = fr
        errs[nf] = mean_na(cur_err, n, false)
        nf += 1usize
        step += 1usize
    }
    b.nf = nf
    ret (b, ok)
}

// variable_importance(forest, decay.exponent, max.depth): the depth-weighted share of the splits on each variable
fn variable_importance(a: *mem.Arena, f: *const Forest, decay: f64, max_depth: usize) -> ([]f64, err) {
    let p = f.p
    let (cnt, e1) = gz_usize(a, max_depth * p)
    let (out, e2) = gz_f64(a, p)
    let (cur, e3) = gz_usize(a, 4usize * f.n + 8usize)
    let (nxt, e4) = gz_usize(a, 4usize * f.n + 8usize)
    if e1 != ok { ret (out, e1) }
    if e2 != ok { ret (out, e2) }
    if e3 != ok { ret (out, e3) }
    if e4 != ok { ret (out, e4) }
    var t = 0usize
    while t < f.ntree {
        let tr = &f.trees[t]
        var nc = 1usize
        cur[0usize] = tr.root
        var depth = 0usize
        while nc > 0usize && depth < max_depth {
            var nx = 0usize
            var q = 0usize
            while q < nc {
                let node = cur[q]
                if !is_leaf(tr, node) {
                    cnt[depth * p + tr.svar[node]] += 1usize
                    nxt[nx] = tr.left[node]
                    nxt[nx + 1usize] = tr.right[node]
                    nx += 2usize
                }
                q += 1usize
            }
            q = 0usize
            while q < nx {
                cur[q] = nxt[q]
                q += 1usize
            }
            nc = nx
            depth += 1usize
        }
        t += 1usize
    }
    var wsum = 0.0f64
    var dd = 0usize
    while dd < max_depth {
        wsum += math.pow[f64](f64(dd + 1usize), 0.0f64 - decay)
        dd += 1usize
    }
    dd = 0usize
    while dd < max_depth {
        var rs = 0usize
        var v = 0usize
        while v < p {
            rs += cnt[dd * p + v]
            v += 1usize
        }
        var den = rs
        if den < 1usize { den = 1usize }
        let w = math.pow[f64](f64(dd + 1usize), 0.0f64 - decay)
        v = 0usize
        while v < p {
            out[v] += f64(cnt[dd * p + v]) / f64(den) * w
            v += 1usize
        }
        dd += 1usize
    }
    var v = 0usize
    while v < p {
        out[v] = out[v] / wsum
        v += 1usize
    }
    ret (out, ok)
}

// out-of-bag predictions of the regression forest R grows for a nuisance estimate (causal_forest: Y.hat, W.hat; instrumental_forest: also Z.hat):
// num_trees given, min.node.size 5, honesty 0.5, ci.group.size 1, the rest from `o`; d carries x, w and the target in y
fn nuisance(a: *mem.Arena, d: *const Data, o: *const Opts, num_trees: usize) -> ([]f64, err) {
    var q = *o
    q.num_trees = num_trees
    q.min_node_size = 5usize
    q.honesty = true
    q.honesty_fraction = 0.5f64
    q.ci_group_size = 1usize
    q.kind = 0usize
    let (f, fe) = train(a, d, &q)
    if fe != ok {
        var none: []f64 = zero
        ret (none, fe)
    }
    let (pr, pe) = predict(a, &f, d, d.x, d.n, true, false, 0usize)
    if pe != ok {
        var none: []f64 = zero
        ret (none, pe)
    }
    ret (pr.pred, ok)
}

// average_treatment_effect(forest) for target.sample "all", method "AIPW", one cluster per observation: the doubly robust scores from the
// out-of-bag effects tau and the debiasing weights, then the weighted mean and its standard error. wts has length n or 0 (unit weights).
fn dr_scores(out: []f64, tau: []const f64, y: []const f64, yhat: []const f64, w: []const f64, what: []const f64, deb: []const f64, n: usize) {
    var i = 0usize
    while i < n {
        let resid = y[i] - (yhat[i] + tau[i] * (w[i] - what[i]))
        out[i] = tau[i] + deb[i] * resid
        i += 1usize
    }
}

type Ate = struct { estimate: f64, std_err: f64 }

fn ate_all(scores: []const f64, wts: []const f64, n: usize) -> Ate {
    var sw = 0.0f64
    var sx = 0.0f64
    var i = 0usize
    while i < n {
        var w = 1.0f64
        if wts.len > 0usize { w = wts[i] }
        sw += w
        sx += w * scores[i]
        i += 1usize
    }
    let est = sx / sw
    var ss = 0.0f64
    var nadj = 0.0f64
    i = 0usize
    while i < n {
        var w = 1.0f64
        if wts.len > 0usize { w = wts[i] }
        let c = (scores[i] - est) * w
        ss += c * c
        if w > 0.0f64 { nadj += 1.0f64 }
        i += 1usize
    }
    var r: Ate = zero
    r.estimate = est
    r.std_err = math.sqrt[f64](ss / (sw * sw) * nadj / (nadj - 1.0f64))
    ret r
}

// cluster labels as dense ids 0..k-1 (k 0: every row is its own cluster); acc and cnt are k-long scratch
type Clu = struct { cid: []const usize, k: usize }

type ClSum = struct { sumsq: f64, g: usize }

// the sum over clusters of the squared cluster sums of u[0..m], with the number of clusters seen; cc[i] is the cluster of entry i
fn clust_sum(acc: []f64, cnt: []usize, k: usize, cc: []const usize, u: []const f64, m: usize) -> ClSum {
    var q = 0usize
    while q < k {
        acc[q] = 0.0f64
        cnt[q] = 0usize
        q += 1usize
    }
    var i = 0usize
    while i < m {
        acc[cc[i]] += u[i]
        cnt[cc[i]] += 1usize
        i += 1usize
    }
    var r: ClSum = zero
    q = 0usize
    while q < k {
        r.sumsq += acc[q] * acc[q]
        if cnt[q] > 0usize { r.g += 1usize }
        q += 1usize
    }
    ret r
}

// ate_all with clusters: sigma2 is the clustered sum of the weighted centred scores
fn ate_all_c(a: *mem.Arena, scores: []const f64, wts: []const f64, cl: *const Clu, n: usize) -> (Ate, err) {
    var sw = 0.0f64
    var sx = 0.0f64
    var i = 0usize
    while i < n {
        var w = 1.0f64
        if wts.len > 0usize { w = wts[i] }
        sw += w
        sx += w * scores[i]
        i += 1usize
    }
    let est = sx / sw
    let (acc, e1) = gz_f64(a, cl.k + 1usize)
    let (wacc, e2) = gz_f64(a, cl.k + 1usize)
    var z: Ate = zero
    if e1 != ok { ret (z, e1) }
    if e2 != ok { ret (z, e2) }
    i = 0usize
    while i < n {
        var w = 1.0f64
        if wts.len > 0usize { w = wts[i] }
        acc[cl.cid[i]] += (scores[i] - est) * w
        wacc[cl.cid[i]] += w
        i += 1usize
    }
    var ss = 0.0f64
    var nadj = 0.0f64
    var q = 0usize
    while q < cl.k {
        ss += acc[q] * acc[q]
        if wacc[q] > 0.0f64 { nadj += 1.0f64 }
        q += 1usize
    }
    var r: Ate = zero
    r.estimate = est
    r.std_err = math.sqrt[f64](ss / (sw * sw) * nadj / (nadj - 1.0f64))
    ret (r, ok)
}

// average_treatment_effect(causal forest, target.sample, method). tgt 0 all, 1 treated, 2 control, 3 overlap;
// method 0 AIPW, 1 TMLE (not with sample weights or clusters, where R stops with an error). tau is the out-of-bag effect, yhat/what the nuisance predictions, wt the 0/1 treatment.
type Reg = struct { beta: f64, v: f64 }

// lm(B ~ A + 0) over the m entries, and its HC3 variance (sandwich::vcovHC)
fn reg_origin(aa: []const f64, bb: []const f64, m: usize) -> Reg {
    var saa = 0.0f64
    var sab = 0.0f64
    var i = 0usize
    while i < m {
        saa += aa[i] * aa[i]
        sab += aa[i] * bb[i]
        i += 1usize
    }
    var r: Reg = zero
    r.beta = sab / saa
    var meat = 0.0f64
    i = 0usize
    while i < m {
        let e = bb[i] - aa[i] * r.beta
        let h = aa[i] * aa[i] / saa
        let o = e * e / ((1.0f64 - h) * (1.0f64 - h))
        meat += aa[i] * aa[i] * o
        i += 1usize
    }
    r.v = meat / (saa * saa)
    ret r
}

fn var_of(x: []const f64, m: usize) -> f64 {
    var mu = 0.0f64
    var i = 0usize
    while i < m {
        mu += x[i]
        i += 1usize
    }
    mu /= f64(m)
    var s = 0.0f64
    i = 0usize
    while i < m {
        s += (x[i] - mu) * (x[i] - mu)
        i += 1usize
    }
    ret s / f64(m - 1usize)
}

// lm(yres ~ wres, weights) slope and its HC3 standard error
fn overlap_ols(a: *mem.Arena, yr: []const f64, wr: []const f64, sw: []const f64, cl: *const Clu, n: usize) -> (Ate, err) {
    var res: Ate = zero
    let (acc0, c1) = gz_f64(a, cl.k + 1usize)
    let (acc1, c2) = gz_f64(a, cl.k + 1usize)
    let (seen, c3) = gz_usize(a, cl.k + 1usize)
    if c1 != ok { ret (res, c1) }
    if c2 != ok { ret (res, c2) }
    if c3 != ok { ret (res, c3) }
    var s0 = 0.0f64
    var sx = 0.0f64
    var sy = 0.0f64
    var sxx = 0.0f64
    var sxy = 0.0f64
    var i = 0usize
    while i < n {
        var w = 1.0f64
        if sw.len > 0usize { w = sw[i] }
        s0 += w
        sx += w * wr[i]
        sy += w * yr[i]
        sxx += w * wr[i] * wr[i]
        sxy += w * wr[i] * yr[i]
        i += 1usize
    }
    let det = s0 * sxx - sx * sx
    let b = (s0 * sxy - sx * sy) / det
    let a0 = (sy - b * sx) / s0
    var meat = 0.0f64
    i = 0usize
    while i < n {
        var w = 1.0f64
        if sw.len > 0usize { w = sw[i] }
        let e = yr[i] - a0 - b * wr[i]
        let h = w * (sxx - 2.0f64 * sx * wr[i] + s0 * wr[i] * wr[i]) / det
        let r = w * e
        let o = r * r / ((1.0f64 - h) * (1.0f64 - h))
        let c = (s0 * wr[i] - sx) / det
        meat += o * c * c
        if cl.k > 0usize {
            acc0[cl.cid[i]] += r
            acc1[cl.cid[i]] += r * wr[i]
            seen[cl.cid[i]] += 1usize
        }
        i += 1usize
    }
    if cl.k > 0usize {
        var g = 0usize
        var q = 0usize
        meat = 0.0f64
        while q < cl.k {
            if seen[q] > 0usize {
                g += 1usize
                let c = (s0 * acc1[q] - sx * acc0[q]) / det
                meat += c * c
            }
            q += 1usize
        }
        meat *= f64(g) / f64(g - 1usize) * f64(n - 1usize) / f64(n - 2usize)
    }
    res.estimate = b
    res.std_err = math.sqrt[f64](meat)
    ret (res, ok)
}

fn in_target(tgt: usize, w: f64) -> bool {
    var inn = tgt == 0usize
    if tgt == 1usize && w == 1.0f64 { inn = true }
    if tgt == 2usize && w == 0.0f64 { inn = true }
    ret inn
}

fn ate_target(a: *mem.Arena, tgt: usize, method: usize, tau: []const f64, y: []const f64, yhat: []const f64, wt: []const f64, what: []const f64,
              sw: []const f64, cl: *const Clu, n: usize) -> (Ate, err) {
    var res: Ate = zero
    if tgt == 3usize {
        let (yr, e1) = gz_f64(a, n)
        let (wr, e2) = gz_f64(a, n)
        if e1 != ok { ret (res, e1) }
        if e2 != ok { ret (res, e2) }
        var i = 0usize
        while i < n {
            yr[i] = y[i] - yhat[i]
            wr[i] = wt[i] - what[i]
            i += 1usize
        }
        let (ov, ove) = overlap_ols(a, yr, wr, sw, cl, n)
        ret (ov, ove)
    }
    let (y0, e3) = gz_f64(a, n)
    let (y1, e4) = gz_f64(a, n)
    let (aa, e5) = gz_f64(a, n)
    let (bb, e6) = gz_f64(a, n)
    if e3 != ok { ret (res, e3) }
    if e4 != ok { ret (res, e4) }
    if e5 != ok { ret (res, e5) }
    if e6 != ok { ret (res, e6) }
    let (acc, e8) = gz_f64(a, cl.k + 1usize)
    let (cnt, e9) = gz_usize(a, cl.k + 1usize)
    let (ub, e10) = gz_f64(a, n)
    if e8 != ok { ret (res, e8) }
    if e9 != ok { ret (res, e9) }
    if e10 != ok { ret (res, e10) }
    var i = 0usize
    var sall = 0.0f64
    var sgrp = 0.0f64
    var n1 = 0usize
    var n0 = 0usize
    var raw = 0.0f64
    while i < n {
        var w = 1.0f64
        if sw.len > 0usize { w = sw[i] }
        y0[i] = yhat[i] - what[i] * tau[i]
        y1[i] = yhat[i] + (1.0f64 - what[i]) * tau[i]
        sall += w
        if wt[i] == 1.0f64 { n1 += 1usize }
        if wt[i] == 0.0f64 { n0 += 1usize }
        if in_target(tgt, wt[i]) {
            sgrp += w
            raw += w * tau[i]
        }
        i += 1usize
    }
    raw /= sgrp
    var tvar = 0.0f64
    i = 0usize
    while i < n {
        var w = 1.0f64
        if sw.len > 0usize { w = sw[i] }
        if in_target(tgt, wt[i]) { tvar += w * w * (tau[i] - raw) * (tau[i] - raw) }
        i += 1usize
    }
    tvar /= sgrp * sgrp
    var corr = 0.0f64
    var sig2 = 0.0f64
    if method == 0usize {
        // gamma: reweight the other arm onto the tgt arm, normalised so the weights sum to sum(w) in each arm
        var gc = 0.0f64
        var gt = 0.0f64
        i = 0usize
        while i < n {
            var w = 1.0f64
            if sw.len > 0usize { w = sw[i] }
            if wt[i] == 0.0f64 {
                var g = 1.0f64
                if tgt == 1usize { g = what[i] / (1.0f64 - what[i]) }
                aa[i] = g
                gc += w * g
            } else if wt[i] == 1.0f64 {
                var g = 1.0f64
                if tgt == 2usize { g = (1.0f64 - what[i]) / what[i] }
                aa[i] = g
                gt += w * g
            }
            i += 1usize
        }
        var sdr = 0.0f64
        var ssq = 0.0f64
        var npos = 0usize
        i = 0usize
        while i < n {
            var w = 1.0f64
            if sw.len > 0usize { w = sw[i] }
            var d = 0.0f64
            if wt[i] == 0.0f64 {
                d = -(aa[i] / gc * sall) * (y[i] - y0[i])
            } else if wt[i] == 1.0f64 {
                d = (aa[i] / gt * sall) * (y[i] - y1[i])
            }
            sdr += w * d
            ssq += w * w * d * d
            ub[i] = w * d
            if w > 0.0f64 { npos += 1usize }
            i += 1usize
        }
        corr = sdr / sall
        sig2 = ssq / (sall * sall) * f64(npos) / f64(npos - 1usize)
        if cl.k > 0usize {
            let cs = clust_sum(acc, cnt, cl.k, cl.cid, ub, n)
            // clusters whose weights sum to zero do not count
            var nadj = 0usize
            var q = 0usize
            while q < cl.k {
                cnt[q] = 0usize
                q += 1usize
            }
            i = 0usize
            while i < n {
                var w = 1.0f64
                if sw.len > 0usize { w = sw[i] }
                if w > 0.0f64 { cnt[cl.cid[i]] += 1usize }
                i += 1usize
            }
            q = 0usize
            while q < cl.k {
                if cnt[q] > 0usize { nadj += 1usize }
                q += 1usize
            }
            sig2 = cs.sumsq / (sall * sall) * f64(nadj) / f64(nadj - 1usize)
        }
    } else {
        // TMLE: refit the outcome of one arm on the inverse-propensity covariate and evaluate it at the tgt's mean covariate
        var d0 = 0.0f64
        var d1 = 0.0f64
        var v0 = 0.0f64
        var v1 = 0.0f64
        if tgt != 2usize {
            var m = 0usize
            var cen = 0.0f64
            i = 0usize
            while i < n {
                var a0 = 1.0f64 / (1.0f64 - what[i])
                if tgt == 1usize { a0 = what[i] / (1.0f64 - what[i]) }
                if wt[i] == 0.0f64 {
                    aa[m] = a0
                    bb[m] = y[i] - y0[i]
                    m += 1usize
                }
                if tgt == 0usize { cen += a0 }
                if tgt == 1usize && wt[i] == 1.0f64 { cen += a0 }
                i += 1usize
            }
            if tgt == 0usize { cen /= f64(n) }
            if tgt == 1usize { cen /= f64(n1) }
            let r0 = reg_origin(aa, bb, m)
            d0 = r0.beta * cen
            v0 = r0.v * cen * cen
        }
        if tgt != 1usize {
            var m = 0usize
            var cen = 0.0f64
            i = 0usize
            while i < n {
                var a1 = 1.0f64 / what[i]
                if tgt == 2usize { a1 = (1.0f64 - what[i]) / what[i] }
                if wt[i] == 1.0f64 {
                    aa[m] = a1
                    bb[m] = y[i] - y1[i]
                    m += 1usize
                }
                if tgt == 0usize { cen += a1 }
                if tgt == 2usize && wt[i] == 0.0f64 { cen += a1 }
                i += 1usize
            }
            if tgt == 0usize { cen /= f64(n) }
            if tgt == 2usize { cen /= f64(n0) }
            let r1 = reg_origin(aa, bb, m)
            d1 = r1.beta * cen
            v1 = r1.v * cen * cen
        }
        corr = d1 - d0
        sig2 = v0 + v1
        if tgt != 0usize {
            // the arm the tgt contains contributes its plain residual variance
            var arm = 1.0f64
            if tgt == 2usize { arm = 0.0f64 }
            var m = 0usize
            i = 0usize
            while i < n {
                if wt[i] == arm {
                    var r = y[i] - y1[i]
                    if tgt == 2usize { r = y[i] - y0[i] }
                    bb[m] = r
                    m += 1usize
                }
                i += 1usize
            }
            sig2 += var_of(bb, m) / f64(m)
        }
    }
    res.estimate = raw + corr
    res.std_err = math.sqrt[f64](tvar + sig2)
    ret (res, ok)
}

// the trees whose drawn samples include s: inbag[t * n + s]
fn inbag_flags(a: *mem.Arena, f: *const Forest) -> ([]bool, err) {
    let (inbag, e) = gz_bool(a, f.ntree * f.n)
    if e != ok { ret (inbag, e) }
    var t = 0usize
    while t < f.ntree {
        var q = 0usize
        while q < f.trees[t].nd {
            inbag[t * f.n + f.trees[t].drawn[q]] = true
            q += 1usize
        }
        t += 1usize
    }
    ret (inbag, ok)
}

// the forest weight of every training sample at row s of xnew (SampleWeightComputer): returns how many samples carry weight; list holds them in
// order of first appearance and buf their summed 1 / leaf size, normalized by the caller
fn forest_weights(f: *const Forest, xnew: []const f64, s: usize, oob: bool, inbag: []const bool, buf: []f64, list: []usize) -> usize {
    var nl = 0usize
    var t = 0usize
    while t < f.ntree {
        if oob && inbag[t * f.n + s] {
            t += 1usize
            continue
        }
        let tr = &f.trees[t]
        let node = find_leaf(tr, xnew, f.p, s)
        let cnt = tr.ls_len[node]
        if cnt > 0usize {
            let w = 1.0f64 / f64(cnt)
            var r = 0usize
            while r < cnt {
                let smp = tr.ls[tr.ls_start[node] + r]
                if buf[smp] <= 0.0f64 {
                    list[nl] = smp
                    nl += 1usize
                }
                buf[smp] += w
                r += 1usize
            }
        }
        t += 1usize
    }
    ret nl
}

// QuantilePredictionStrategy over the forest weights: out[q * nnew + row] is the quantile qs[q] at row `row` of xnew (or of the training rows when oob)
fn predict_quantile(a: *mem.Arena, f: *const Forest, d: *const Data, xnew: []const f64, nnew: usize, oob: bool, qs: []const f64, out: []f64) -> err {
    let (buf, e1) = gz_f64(a, f.n)
    let (list, e2) = gz_usize(a, f.n)
    let (ids, e3) = gz_usize(a, f.n)
    let (keys, e4) = gz_f64(a, f.n)
    let (tk, e5) = gz_f64(a, f.n)
    let (ti, e6) = gz_usize(a, f.n)
    var inbag: []bool = zero
    let (ib, e7) = inbag_flags(a, f)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    inbag = ib
    let nan = special.nan()
    var s = 0usize
    while s < nnew {
        let nl = forest_weights(f, xnew, s, oob, inbag, buf, list)
        if nl == 0usize {
            var q = 0usize
            while q < qs.len {
                out[q * nnew + s] = nan
                q += 1usize
            }
            s += 1usize
            continue
        }
        var total = 0.0f64
        var i = 0usize
        while i < nl {
            total += buf[list[i]]
            i += 1usize
        }
        // order by (outcome, sample id): a stable sort by outcome of the list sorted by sample id
        i = 0usize
        while i < nl {
            keys[i] = f64(list[i])
            ids[i] = list[i]
            i += 1usize
        }
        msort(keys, ids, tk, ti, nl)
        i = 0usize
        while i < nl {
            keys[i] = d.y[ids[i]]
            i += 1usize
        }
        msort(keys, ids, tk, ti, nl)
        var qi = 0usize
        var cum = 0.0f64
        i = 0usize
        while i < nl {
            cum += buf[ids[i]] / total
            while qi < qs.len && cum >= qs[qi] {
                out[qi * nnew + s] = keys[i]
                qi += 1usize
            }
            i += 1usize
        }
        while qi < qs.len {
            out[qi * nnew + s] = keys[nl - 1usize]
            qi += 1usize
        }
        i = 0usize
        while i < nl {
            buf[list[i]] = 0.0f64
            i += 1usize
        }
        s += 1usize
    }
    ret ok
}

// solves the symmetric positive definite k by k system m z = b (m row-major, destroyed; b destroyed) by elimination on the largest remaining diagonal,
// the pivoting of Eigen's LDLT; k at most 64
fn solve_sym(m: []f64, b: []f64, z: []f64, k: usize) {
    var perm: [64]usize = zero
    var i = 0usize
    while i < k {
        perm[i] = i
        i += 1usize
    }
    var kk = 0usize
    while kk < k {
        var r = kk
        var mx = math.abs[f64](m[kk * k + kk])
        var q = kk + 1usize
        while q < k {
            if math.abs[f64](m[q * k + q]) > mx {
                mx = math.abs[f64](m[q * k + q])
                r = q
            }
            q += 1usize
        }
        if r != kk {
            var c = 0usize
            while c < k {
                let t = m[r * k + c]
                m[r * k + c] = m[kk * k + c]
                m[kk * k + c] = t
                c += 1usize
            }
            c = 0usize
            while c < k {
                let t = m[c * k + r]
                m[c * k + r] = m[c * k + kk]
                m[c * k + kk] = t
                c += 1usize
            }
            let tb = b[r]
            b[r] = b[kk]
            b[kk] = tb
            let tp = perm[r]
            perm[r] = perm[kk]
            perm[kk] = tp
        }
        let piv = m[kk * k + kk]
        i = kk + 1usize
        while i < k {
            let fct = m[i * k + kk] / piv
            var j = kk
            while j < k {
                m[i * k + j] -= fct * m[kk * k + j]
                j += 1usize
            }
            b[i] -= fct * b[kk]
            i += 1usize
        }
        kk += 1usize
    }
    var w: [64]f64 = zero
    i = k
    while i > 0usize {
        i -= 1usize
        var s = b[i]
        var j = i + 1usize
        while j < k {
            s -= m[i * k + j] * w[j]
            j += 1usize
        }
        w[i] = s / m[i * k + i]
    }
    i = 0usize
    while i < k {
        z[perm[i]] = w[i]
        i += 1usize
    }
}

// the penalized weighted normal matrix: the unpenalized one with the ridge on every diagonal entry but the intercept's
fn ridge_penalty(m: []f64, k: usize, lambda: f64, wpen: bool) {
    var norm = 0.0f64
    var i = 0usize
    while i < k {
        norm += m[i * k + i]
        i += 1usize
    }
    norm = norm / f64(k)
    i = 1usize
    while i < k {
        if wpen {
            m[i * k + i] += lambda * m[i * k + i]
        } else {
            m[i * k + i] += lambda * norm
        }
        i += 1usize
    }
}

// LocalLinearPredictionStrategy at the rows of xnew (or the training rows when oob): out[l * nnew + row] is the local linear prediction under lambdas[l]
// from the forest weights, regressing on the columns `vars` centered at the prediction point; with want_var, vout[row] is the little-bags variance at lambdas[0]
fn predict_ll(a: *mem.Arena, f: *const Forest, d: *const Data, xnew: []const f64, nnew: usize, oob: bool, lambdas: []const f64, wpen: bool, vars: []const usize,
              want_var: bool, out: []f64, vout: []f64) -> err {
    let k = vars.len + 1usize
    let (buf, e1) = gz_f64(a, f.n)
    let (list, e2) = gz_usize(a, f.n)
    let (xs, e3) = gz_f64(a, f.n * k)
    let (wv, e4) = gz_f64(a, f.n)
    let (m0, e5) = gz_f64(a, k * k)
    let (m, e6) = gz_f64(a, k * k)
    let (rhs, e7) = gz_f64(a, k)
    let (co, e8) = gz_f64(a, k)
    let (imap, e9) = gz_usize(a, f.n)
    let (pres, e10) = gz_f64(a, f.n)
    let (ib, e11) = inbag_flags(a, f)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    let nan = special.nan()
    var s = 0usize
    while s < nnew {
        let nl = forest_weights(f, xnew, s, oob, ib, buf, list)
        if nl == 0usize {
            var l = 0usize
            while l < lambdas.len {
                out[l * nnew + s] = nan
                l += 1usize
            }
            if want_var { vout[s] = nan }
            s += 1usize
            continue
        }
        var total = 0.0f64
        var i = 0usize
        while i < nl {
            total += buf[list[i]]
            i += 1usize
        }
        i = 0usize
        while i < nl {
            let smp = list[i]
            wv[i] = buf[smp] / total
            imap[smp] = i
            xs[i * k] = 1.0f64
            var j = 0usize
            while j < vars.len {
                xs[i * k + j + 1usize] = d.x[smp * d.p + vars[j]] - xnew[s * d.p + vars[j]]
                j += 1usize
            }
            i += 1usize
        }
        var r = 0usize
        while r < k {
            var c = 0usize
            while c < k {
                var acc = 0.0f64
                i = 0usize
                while i < nl {
                    acc += xs[i * k + r] * wv[i] * xs[i * k + c]
                    i += 1usize
                }
                m0[r * k + c] = acc
                c += 1usize
            }
            r += 1usize
        }
        var li = 0usize
        while li < lambdas.len {
            r = 0usize
            while r < k * k {
                m[r] = m0[r]
                r += 1usize
            }
            ridge_penalty(m, k, lambdas[li], wpen)
            r = 0usize
            while r < k {
                var acc = 0.0f64
                i = 0usize
                while i < nl {
                    acc += xs[i * k + r] * wv[i] * d.y[list[i]]
                    i += 1usize
                }
                rhs[r] = acc
                r += 1usize
            }
            solve_sym(m, rhs, co, k)
            out[li * nnew + s] = co[0usize]
            if li == 0usize && want_var {
                // the pseudo-residuals at lambda 0 of the path
                r = 0usize
                while r < k * k {
                    m[r] = m0[r]
                    r += 1usize
                }
                ridge_penalty(m, k, lambdas[0usize], wpen)
                var m2: [4096]f64 = zero
                r = 0usize
                while r < k * k {
                    m2[r] = m[r]
                    r += 1usize
                }
                var e1v: [64]f64 = zero
                var zeta: [64]f64 = zero
                e1v[0usize] = 1.0f64
                solve_sym(m2[0usize..k * k], e1v[0usize..k], zeta[0usize..k], k)
                i = 0usize
                while i < nl {
                    var xz = 0.0f64
                    var lp = 0.0f64
                    r = 0usize
                    while r < k {
                        xz += xs[i * k + r] * zeta[r]
                        lp += xs[i * k + r] * co[r]
                        r += 1usize
                    }
                    pres[i] = xz * (d.y[list[i]] - lp)
                    i += 1usize
                }
                // groups of consecutive valid trees, as the C++ collector lays them out
                var nv = 0usize
                var t = 0usize
                while t < f.ntree {
                    if !(oob && ib[t * f.n + s]) { nv += 1usize }
                    t += 1usize
                }
                var good = 0.0f64
                var psi_sq = 0.0f64
                var psi_gsq = 0.0f64
                var avg = 0.0f64
                var pos = 0usize
                var gpsi: [64]f64 = zero
                var gok = true
                var gcnt = 0usize
                t = 0usize
                while t < f.ntree {
                    if oob && ib[t * f.n + s] {
                        t += 1usize
                        continue
                    }
                    if pos / f.ci < nv / f.ci {
                        let tr = &f.trees[t]
                        let node = find_leaf(tr, xnew, f.p, s)
                        let cnt = tr.ls_len[node]
                        var psi1 = 0.0f64
                        if cnt == 0usize {
                            gok = false
                        } else {
                            var q = 0usize
                            while q < cnt {
                                psi1 += pres[imap[tr.ls[tr.ls_start[node] + q]]]
                                q += 1usize
                            }
                            psi1 /= f64(cnt)
                        }
                        gpsi[gcnt] = psi1
                        gcnt += 1usize
                        if gcnt == f.ci {
                            if gok {
                                good += 1.0f64
                                var gs = 0.0f64
                                var jj = 0usize
                                while jj < f.ci {
                                    psi_sq += gpsi[jj] * gpsi[jj]
                                    gs += gpsi[jj]
                                    jj += 1usize
                                }
                                let gp = gs / f64(f.ci)
                                psi_gsq += gp * gp
                                avg += gp
                            }
                            gok = true
                            gcnt = 0usize
                        }
                    }
                    pos += 1usize
                    t += 1usize
                }
                avg /= good
                let vb = psi_gsq / good - avg * avg
                let vt = psi_sq / (good * f64(f.ci)) - avg * avg
                let gn = (vt - vb) / f64(f.ci - 1usize)
                vout[s] = debias(vb, gn, good)
            }
            li += 1usize
        }
        i = 0usize
        while i < nl {
            buf[list[i]] = 0.0f64
            i += 1usize
        }
        s += 1usize
    }
    ret ok
}

// tune_ll_regression_forest: the lambda on the path with the least out-of-bag mean squared error (the first such)
fn ll_lambda_min(preds: []const f64, y: []const f64, n: usize, path: []const f64) -> f64 {
    var best = 0.0f64
    var bi = 0usize
    var li = 0usize
    var have = false
    while li < path.len {
        var e = 0.0f64
        var i = 0usize
        while i < n {
            let r = preds[li * n + i] - y[i]
            e += r * r
            i += 1usize
        }
        e = e / f64(n)
        if e == e {
            if !have || e < best {
                best = e
                bi = li
                have = true
            }
        }
        li += 1usize
    }
    ret path[bi]
}

// SurvivalPredictionStrategy over the forest weights: out[row * nfail + k] is the survival function after the k-th failure time (d.y holds the failure
// times relabeled to 0..nfail). nelson true is the Nelson-Aalen estimate, false Kaplan-Meier.
fn predict_survival(a: *mem.Arena, f: *const Forest, d: *const Data, xnew: []const f64, nnew: usize, oob: bool, nfail: usize, nelson: bool, out: []f64) -> err {
    let (buf, e1) = gz_f64(a, f.n)
    let (list, e2) = gz_usize(a, f.n)
    let (cf, e3) = gz_f64(a, nfail + 1usize)
    let (cc, e4) = gz_f64(a, nfail + 1usize)
    let (ib, e5) = inbag_flags(a, f)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    let nan = special.nan()
    var s = 0usize
    while s < nnew {
        let nl = forest_weights(f, xnew, s, oob, ib, buf, list)
        var empty = nl == 0usize
        var sum = 0.0f64
        var sum_weight = 0.0f64
        if !empty {
            var total = 0.0f64
            var i = 0usize
            while i < nl {
                total += buf[list[i]]
                i += 1usize
            }
            i = 0usize
            while i <= nfail {
                cf[i] = 0.0f64
                cc[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < nl {
                let smp = list[i]
                let fw = buf[smp] / total
                let ft = usize(d.y[smp])
                let sw = weight_of(d, smp)
                if is_failure(d, smp) {
                    cf[ft] += fw * sw
                } else {
                    cc[ft] += fw * sw
                }
                sum += fw * sw
                sum_weight += sw
                buf[smp] = 0.0f64
                i += 1usize
            }
            if math.abs[f64](sum_weight) <= 1.0e-16f64 { empty = true }
        }
        if empty {
            var k = 0usize
            while k < nfail {
                out[s * nfail + k] = nan
                k += 1usize
            }
            s += 1usize
            continue
        }
        var k = 0usize
        while k < nfail {
            out[s * nfail + k] = 0.0f64
            k += 1usize
        }
        sum = sum - cc[0usize]
        var surv = 1.0f64
        if nelson { surv = 0.0f64 }
        var tm = 1usize
        while tm <= nfail {
            if nelson {
                if sum > 0.0f64 { surv = surv - cf[tm] / sum }
                out[s * nfail + tm - 1usize] = math.exp[f64](surv)
            } else {
                if sum > 0.0f64 {
                    surv = surv * (1.0f64 - cf[tm] / sum)
                    if surv <= 0.0f64 { break }
                }
                out[s * nfail + tm - 1usize] = surv
            }
            sum = sum - cf[tm] - cc[tm]
            tm += 1usize
        }
        s += 1usize
    }
    ret ok
}
