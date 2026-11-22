// R uwot::umap (0.2.5) with its defaults: exact nearest neighbours (nn_method "fnn"), smooth-kNN fuzzy graph, random or spectral start, and the single-threaded Adam-free SGD of
// uwot's C++ core (batch = FALSE, rng "pcg", single precision arithmetic throughout the optimizer, one runif draw per epoch for the PCG seed). x is n by d row-major; the embedding
// is n by nd row-major. a and b are the curve parameters (what find_ab_params returns); the draws from g follow uwot's order: the start, then one for the optimizer and one per epoch.
//
// Not here: other metrics, approximate neighbours, supervised and umap_transform, the connected-components fallback of the spectral start, tumap / largevis, batch and Adam.

use e.algo.rand.r as rng
use e.algo.stat.rspectra as rs
use e.math
use e.mem

error Bad

fn eps32() -> f32 { ret 1.1920929e-7f32 }

// the PCG32 (setseq, default stream) of pcg_random.hpp seeded with one 64-bit value
type Pcg = struct { state: u64 }

fn pcg_bump(s: u64) -> u64 { ret s *% 6364136223846793005u64 +% 1442695040888963407u64 }

fn pcg_seed(p: *Pcg, seed: u64) { p.state = pcg_bump(seed +% 1442695040888963407u64) }

fn pcg_next(p: *Pcg) -> u32 {
    let old = p.state
    p.state = pcg_bump(old)
    var x = old ^ (old >> 18u64)
    let rot = u32(old >> 59u64)
    let r = u32((x >> 27u64) & 4294967295u64)

    if rot == 0u32 { ret r }
    ret (r >> rot) | (r << (32u32 - rot))
}

// pcg32::operator()(upper): bounded_rand
fn pcg_bounded(p: *Pcg, upper: u32) -> u32 {
    let up = u64(upper)
    let threshold = (4294967296u64 - up) % up
    var done = false
    var res = 0u32
    while !done {
        let r = pcg_next(p)
        if u64(r) >= threshold {
            res = u32(u64(r) % up)
            done = true
        }
    }
    ret res
}

// the n_neighbors nearest rows including the row itself first (FNN::get.knn then the self column), ascending by distance, ties by index
fn knn_exact(x: []const f64, n: usize, d: usize, k: usize, idx: []usize, dist: []f64) {
    var i = 0usize
    while i < n {
        idx[i * k] = i
        dist[i * k] = 0.0f64
        var cnt = 1usize
        var m = 0usize
        while m < n {
            if m != i {
                var s = 0.0f64
                var c = 0usize
                while c < d {
                    let t = x[i * d + c] - x[m * d + c]
                    s += t * t
                    c += 1usize
                }
                let dm = math.sqrt[f64](s)
                if cnt < k || dm < dist[i * k + cnt - 1usize] {
                    var p = cnt
                    if cnt == k { p = k - 1usize }
                    while p > 1usize && dist[i * k + p - 1usize] > dm {
                        dist[i * k + p] = dist[i * k + p - 1usize]
                        idx[i * k + p] = idx[i * k + p - 1usize]
                        p -= 1usize
                    }
                    dist[i * k + p] = dm
                    idx[i * k + p] = m
                    if cnt < k { cnt += 1usize }
                }
            }
            m += 1usize
        }
        i += 1usize
    }
}

// uwot's smooth_knn for one row: weights into w (k values)
fn smooth_row(dist: []const f64, k: usize, goal: f64, local_connectivity: f64, mean_distances: f64, w: []f64) {
    let tol = 1.0e-5f64
    var nz = k
    var j = 0usize
    while j < k {
        if dist[j] > 0.0f64 {
            nz = j
            j = k
        } else {
            j += 1usize
        }
    }
    var rho = 0.0f64
    let nnz = k - nz
    if f64(nnz) >= local_connectivity {
        let index = i64(math.floor[f64](local_connectivity))
        let interp = local_connectivity - f64(index)
        if index > 0i64 {
            rho = dist[nz + usize(index) - 1usize]
            if interp >= tol { rho += interp * (dist[nz + usize(index)] - rho) }
        } else {
            if nnz > 0usize { rho = interp * dist[nz] }
        }
    } else {
        if nnz > 0usize { rho = dist[k - 1usize] }
    }
    let dmax = 1.7976931348623157e308f64
    var sigma = 1.0f64
    var best = sigma
    var adiff_min = dmax
    var lo = 0.0f64
    var hi = dmax
    var conv = false
    var iter = 0usize
    while iter < 64usize && !conv {
        var val = 0.0f64
        j = 1usize
        while j < k {
            let rj = dist[j] - rho
            if rj <= 0.0f64 { val += 1.0f64 } else { val += math.exp[f64](0.0f64 - rj / sigma) }
            j += 1usize
        }
        let ad = math.abs[f64](val - goal)
        if ad < tol {
            conv = true
        } else {
            if ad < adiff_min {
                adiff_min = ad
                best = sigma
            }
            if val > goal {
                hi = sigma
                sigma = 0.5f64 * (lo + hi)
            } else {
                lo = sigma
                if hi == dmax { sigma *= 2.0f64 } else { sigma = 0.5f64 * (lo + hi) }
            }
            iter += 1usize
        }
    }
    if !conv { sigma = best }
    var mean = 0.0f64
    j = 0usize
    while j < k {
        mean += (dist[j] - mean) / f64(j + 1usize)
        j += 1usize
    }
    var floor_s = 1.0e-3f64 * mean_distances
    if rho > 0.0f64 { floor_s = 1.0e-3f64 * mean }
    if floor_s > sigma { sigma = floor_s }
    j = 0usize
    while j < k {
        let rj = dist[j] - rho
        if rj <= 0.0f64 { w[j] = 1.0f64 } else { w[j] = math.exp[f64](0.0f64 - rj / sigma) }
        j += 1usize
    }
}

fn clamp4(v: f32) -> f32 {
    if v < 0.0f32 - 4.0f32 { ret 0.0f32 - 4.0f32 }
    if 4.0f32 < v { ret 4.0f32 }
    ret v
}

fn f32_to_usize(v: f32) -> usize {
    if v < 1.0f32 { ret 0usize }
    ret usize(v)
}

// d2diff: the squared distance between head row px and tail row py floored at float epsilon, the differences into disp
fn d2diff(y: []const f32, px: usize, yt: []const f32, py: usize, nd: usize, disp: []f32) -> f32 {
    var d2 = 0.0f32
    var d = 0usize
    while d < nd {
        let diff = y[px + d] - yt[py + d]
        disp[d] = diff
        d2 += diff * diff
        d += 1usize
    }
    if d2 < eps32() { ret eps32() }
    ret d2
}

// n_epochs of uwot's optimizer on the graph v (nh by nt column-major, head rows by tail columns): y is the head embedding (nh by nd) and yt the tail embedding (nt by nd, the same vector as y
// when training); move says whether the tail rows move with the head
fn sgd(a: *mem.Arena, v: []const f64, nh: usize, nt: usize, nd: usize, n_epochs: usize, alpha0: f64, ab_a: f64, ab_b: f64, gamma: f64, neg_rate: f64, g: *rng.Rng, y: []f32, yt: []f32, move: bool) -> err {
    var vmax = 0.0f64
    var i = 0usize
    while i < nh * nt {
        if v[i] > vmax { vmax = v[i] }
        i += 1usize
    }
    var ne = 0usize
    i = 0usize
    while i < nh * nt {
        if v[i] >= vmax / f64(n_epochs) && v[i] != 0.0f64 { ne += 1usize }
        i += 1usize
    }
    let (head, e0) = mem.alloc[usize](a, ne)
    let (tail, e1) = mem.alloc[usize](a, ne)
    let (eps, e2) = mem.alloc[f32](a, ne)
    let (epn, e3) = mem.alloc[f32](a, ne)
    let (nxt, e4) = mem.alloc[f32](a, ne)
    let (nxn, e5) = mem.alloc[f32](a, ne)
    let (disp, e7) = mem.alloc[f32](a, nd)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e7 != ok { ret e0 }
    let nsr = f32(1.0f64 / f64(f32(neg_rate)))
    var at = 0usize
    var jc = 0usize
    while jc < nt {
        var ir = 0usize
        while ir < nh {
            let w = v[ir + nh * jc]
            if w >= vmax / f64(n_epochs) && w != 0.0f64 {
                head[at] = ir
                tail[at] = jc
                let ns = f64(n_epochs) * (w / vmax)
                eps[at] = f32(f64(n_epochs) / ns)
                epn[at] = eps[at] * nsr
                nxt[at] = eps[at]
                nxn[at] = epn[at]
                at += 1usize
            }
            ir += 1usize
        }
        jc += 1usize
    }
    let fa = f32(ab_a)
    let fb = f32(ab_b)
    let a_b_m2 = f32((0.0f64 - 2.0f64) * f64(fa) * f64(fb))
    let gamma_b_2 = f32(2.0f64 * f64(f32(gamma)) * f64(fb))
    let alpha_init = f32(alpha0)
    var alpha = alpha_init
    let umax = 4294967295.0f64
    var seed1 = u32(rng.runif(g, 0.0f64, 1.0f64) * umax)
    var epoch = 0usize
    while epoch < n_epochs {
        seed1 = u32(rng.runif(g, 0.0f64, 1.0f64) * umax)
        var p: Pcg = zero
        pcg_seed(&p, (u64(seed1) << 32u64) | u64(u32(ne)))
        let fe = f32(epoch)
        var ei = 0usize
        while ei < ne {
            if nxt[ei] <= fe {
                let dj = nd * head[ei]
                let dk = nd * tail[ei]
                let d2 = d2diff(y, dj, yt, dk, nd, disp)
                let pd2b = math.pow[f32](d2, fb)
                let num = a_b_m2 * pd2b
                let den = f64(d2) * (f64(fa * pd2b) + 1.0f64)
                let coeff = f32(f64(num) / den)
                var d = 0usize
                while d < nd {
                    let gd = clamp4(coeff * disp[d])
                    let upd = alpha * gd
                    y[dj + d] += upd
                    if move { yt[dk + d] += 0.0f32 - upd }
                    d += 1usize
                }
                let nneg = f32_to_usize((fe - nxn[ei]) / epn[ei])
                var q = 0usize
                while q < nneg {
                    let dkn = usize(pcg_bounded(&p, u32(nt))) * nd
                    if dj != dkn {
                        let r2 = d2diff(y, dj, yt, dkn, nd, disp)
                        let rc = f32(f64(gamma_b_2) / ((0.001f64 + f64(r2)) * (f64(fa * math.pow[f32](r2, fb)) + 1.0f64)))
                        d = 0usize
                        while d < nd {
                            y[dj + d] += alpha * clamp4(rc * disp[d])
                            d += 1usize
                        }
                    }
                    q += 1usize
                }
                nxt[ei] += eps[ei]
                nxn[ei] += f32(nneg) * epn[ei]
            }
            ei += 1usize
        }
        alpha = f32(f64(alpha_init) * (1.0f64 - f64(fe / f32(n_epochs))))
        epoch += 1usize
    }
    ret ok
}

// umap: sgd on the graph v (n by n column-major, symmetric); emb is the start on entry (n by nd row-major) and the embedding, centred, on exit
fn optimize(a: *mem.Arena, v: []const f64, n: usize, nd: usize, n_epochs: usize, alpha0: f64, ab_a: f64, ab_b: f64, gamma: f64, neg_rate: f64, g: *rng.Rng, emb: []f64) -> err {
    let (y, e0) = mem.alloc[f32](a, n * nd)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < n * nd {
        y[i] = f32(emb[i])
        i += 1usize
    }
    let es = sgd(a, v, n, n, nd, n_epochs, alpha0, ab_a, ab_b, gamma, neg_rate, g, y, y, true)
    if es != ok { ret es }
    i = 0usize
    while i < n * nd {
        emb[i] = f64(y[i])
        i += 1usize
    }
    // scale(embedding, center = TRUE, scale = FALSE)
    var c = 0usize
    while c < nd {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += emb[i * nd + c]
            i += 1usize
        }
        s /= f64(n)
        i = 0usize
        while i < n {
            emb[i * nd + c] -= s
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// the fuzzy graph of the neighbour data: v (n by n column-major) = the fuzzy union of the smooth-kNN weights with set_op_mix_ratio
fn fuzzy_graph(a: *mem.Arena, idx: []const usize, dist: []const f64, n: usize, k: usize, local_connectivity: f64, mix: f64, v: []f64) -> err {
    let (wt, e0) = mem.alloc[f64](a, n * k)
    let (xm, e1) = mem.alloc[f64](a, n * n)
    if e0 != ok || e1 != ok { ret e0 }
    var mean_distances = 0.0f64
    var i = 0usize
    while i < n * k {
        mean_distances += (dist[i] - mean_distances) / f64(i + 1usize)
        i += 1usize
    }
    let goal = math.log2[f64](f64(k))
    i = 0usize
    while i < n {
        smooth_row(dist[i * k..(i + 1usize) * k], k, goal, local_connectivity, mean_distances, wt[i * k..(i + 1usize) * k])
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        xm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            if idx[i * k + j] != i { xm[i + n * idx[i * k + j]] = wt[i * k + j] }
            j += 1usize
        }
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var r = 0usize
        while r < n {
            let p = xm[r + n * c]
            let q = xm[c + n * r]
            let xx = p * q
            if mix == 1.0f64 {
                v[r + n * c] = p + q - xx
            } else {
                if mix == 0.0f64 { v[r + n * c] = xx } else { v[r + n * c] = mix * (p + q - xx) + (1.0f64 - mix) * xx }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret ok
}

// start 0 uniform random in [-10, 10] (rand_init), 1 spectral (the normalized Laplacian's bottom eigenvectors by RSpectra, scaled to 10 and jittered by N(0, 1e-4))
fn start_embedding(a: *mem.Arena, v: []const f64, n: usize, nd: usize, kind: usize, g: *rng.Rng, emb: []f64) -> err {
    if kind == 0usize {
        var c = 0usize
        while c < nd {
            var i = 0usize
            while i < n {
                emb[i * nd + c] = rng.runif(g, 0.0f64 - 10.0f64, 10.0f64)
                i += 1usize
            }
            c += 1usize
        }
        ret ok
    }
    let (dsq, e0) = mem.alloc[f64](a, n)
    let (l, e1) = mem.alloc[f64](a, n * n)
    if e0 != ok || e1 != ok { ret e0 }
    var j = 0usize
    while j < n {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += v[i + n * j]
            i += 1usize
        }
        dsq[j] = math.sqrt[f64](s)
        j += 1usize
    }
    var c = 0usize
    while c < n {
        var r = 0usize
        while r < n {
            // L[r, c] = -((A[c, r] / Dsq[c]) / Dsq[r]), then 1 + diagonal
            var val = 0.0f64 - ((v[c + n * r] / dsq[c]) / dsq[r])
            if r == c { val = 1.0f64 + val }
            l[r + n * c] = val
            r += 1usize
        }
        c += 1usize
    }
    var out: rs.EigsOut = zero
    let ee = rs.eigs_sym(a, l, n, nd + 1usize, 2usize, false, 0.0f64, 0usize, 1.0e-4f64, 0usize, l[0usize..0usize], &out)
    if ee != ok { ret ee }
    if out.nconv < nd + 1usize { ret Bad }
    // the nd largest of the nd + 1 values, ascending (rev(order(values, decreasing = TRUE)[1:nd]))
    let (ord, e2) = mem.alloc[usize](a, nd + 1usize)
    if e2 != ok { ret e2 }
    var t = 0usize
    while t < nd + 1usize {
        ord[t] = t
        t += 1usize
    }
    t = 1usize
    while t < nd + 1usize {
        var m = t
        while m > 0usize && out.vals[ord[m - 1usize]] < out.vals[ord[m]] {
            let sw = ord[m]
            ord[m] = ord[m - 1usize]
            ord[m - 1usize] = sw
            m -= 1usize
        }
        t += 1usize
    }
    var mx = 0.0f64
    c = 0usize
    while c < nd {
        let col = ord[nd - 1usize - c]
        var i = 0usize
        while i < n {
            let val = out.vecs[i + n * col]
            emb[i * nd + c] = val
            if math.abs[f64](val) > mx { mx = math.abs[f64](val) }
            i += 1usize
        }
        c += 1usize
    }
    let expansion = 10.0f64 / mx
    c = 0usize
    while c < nd {
        var i = 0usize
        while i < n {
            emb[i * nd + c] = emb[i * nd + c] * expansion
            i += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < nd {
        var i = 0usize
        while i < n {
            emb[i * nd + c] += rng.rnorm(g, 0.0f64, 0.0001f64)
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// uwot::umap_transform with a precomputed neighbour graph (nn_method = list(idx, dist)): idx and dist are nq by k row-major, the k nearest training rows of each new row (no self);
// train is the model embedding (nt by nd row-major); the model's local_connectivity, a, b, gamma, negative_sample_rate and learning rate come in as arguments, n_epochs is the epoch count
// transform runs (the default max(2, round(model epochs / 3))); weighted selects init = "weighted" over "average"; out is the new embedding (nq by nd row-major, not centred)
fn umap_transform_fit(a: *mem.Arena, idx: []const usize, dist: []const f64, nq: usize, k: usize, train: []const f64, nt: usize, nd: usize, n_epochs: usize, alpha: f64, ab_a: f64, ab_b: f64, gamma: f64, neg_rate: f64, local_connectivity: f64, weighted: bool, g: *rng.Rng, out: []f64) -> err {
    let (wt, e0) = mem.alloc[f64](a, nq * k)
    let (gr, e1) = mem.alloc[f64](a, nq * nt)
    let (yh, e2) = mem.alloc[f32](a, nq * nd)
    let (yt, e3) = mem.alloc[f32](a, nt * nd)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret e0 }
    var mean_distances = 0.0f64
    var i = 0usize
    while i < nq * k {
        mean_distances += (dist[i] - mean_distances) / f64(i + 1usize)
        i += 1usize
    }
    var lc = local_connectivity - 1.0f64
    if lc < 0.0f64 { lc = 0.0f64 }
    let goal = math.log2[f64](f64(k))
    i = 0usize
    while i < nq {
        smooth_row(dist[i * k..(i + 1usize) * k], k, goal, lc, mean_distances, wt[i * k..(i + 1usize) * k])
        i += 1usize
    }
    i = 0usize
    while i < nt * nd {
        yt[i] = f32(train[i])
        i += 1usize
    }
    i = 0usize
    while i < nq * nt {
        gr[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nq {
        var c = 0usize
        while c < nd {
            var s = 0.0f64
            var sw = 0.0f64
            var j = 0usize
            while j < k {
                if weighted {
                    let w = f32(wt[i * k + j])
                    sw += f64(w)
                    s += f64(yt[nd * idx[i * k + j] + c] * w)
                } else {
                    s += f64(yt[nd * idx[i * k + j] + c])
                }
                j += 1usize
            }
            if !weighted { sw = f64(k) }
            yh[nd * i + c] = f32(s / sw)
            c += 1usize
        }
        var j = 0usize
        while j < k {
            gr[i + nq * idx[i * k + j]] = wt[i * k + j]
            j += 1usize
        }
        i += 1usize
    }
    let es = sgd(a, gr, nq, nt, nd, n_epochs, alpha / 4.0f64, ab_a, ab_b, gamma, neg_rate, g, yh, yt, false)
    if es != ok { ret es }
    i = 0usize
    while i < nq * nd {
        out[i] = f64(yh[i])
        i += 1usize
    }
    ret ok
}

// R's `x ^ y` for the scalar exponent of find_ab_params (R_POW: 1 for x == 1 or y == 0, 0 for x == 0 and y > 0, x * x for y == 2, else pow)
fn r_pow(x: f64, y: f64) -> f64 {
    if x == 1.0f64 || y == 0.0f64 { ret 1.0f64 }
    if x == 0.0f64 && y > 0.0f64 { ret 0.0f64 }
    if y == 2.0f64 { ret x * x }
    ret math.pow64(x, y)
}

// the model 1 / (1 + a x^(2 b)) over xv (300 values) into f
fn ab_model(xv: []const f64, p: usize, pa: f64, pb: f64, f: []f64) {
    var i = 0usize
    while i < p {
        f[i] = 1.0f64 / (1.0f64 + pa * r_pow(xv[i], 2.0f64 * pb))
        i += 1usize
    }
}

// LINPACK dqrdc2 without pivoting on an n by 2 column-major matrix (x), qraux into qa
fn qr2(x: []f64, n: usize, qa: []f64) {
    var l = 0usize
    while l < 2usize {
        var nrm = 0.0f64
        var i = l
        while i < n {
            nrm += x[i + n * l] * x[i + n * l]
            i += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        if nrm != 0.0f64 {
            if x[l + n * l] != 0.0f64 && x[l + n * l] < 0.0f64 { nrm = 0.0f64 - nrm }
            i = l
            while i < n {
                x[i + n * l] /= nrm
                i += 1usize
            }
            x[l + n * l] += 1.0f64
            var j = l + 1usize
            while j < 2usize {
                var dot = 0.0f64
                i = l
                while i < n {
                    dot += x[i + n * l] * x[i + n * j]
                    i += 1usize
                }
                let t = 0.0f64 - dot / x[l + n * l]
                i = l
                while i < n {
                    x[i + n * j] += t * x[i + n * l]
                    i += 1usize
                }
                j += 1usize
            }
            qa[l] = x[l + n * l]
            x[l + n * l] = 0.0f64 - nrm
        } else {
            qa[l] = 0.0f64
        }
        l += 1usize
    }
}

// qr.qty: y := Q' y in place
fn qty2(x: []const f64, n: usize, qa: []const f64, y: []f64) {
    var j = 0usize
    while j < 2usize {
        if qa[j] != 0.0f64 {
            var dot = qa[j] * y[j]
            var i = j + 1usize
            while i < n {
                dot += x[i + n * j] * y[i]
                i += 1usize
            }
            let t = 0.0f64 - dot / qa[j]
            y[j] += t * qa[j]
            i = j + 1usize
            while i < n {
                y[i] += t * x[i + n * j]
                i += 1usize
            }
        }
        j += 1usize
    }
}

// stats::nls(yv ~ 1 / (1 + a * xv^(2 * b)), start = list(a = 1, b = 1))$m$getPars() for uwot's find_ab_params(spread, min_dist): the Gauss-Newton of nls.c with the forward-difference
// gradient of numericDeriv, tolerance 1e-5, at most 50 iterations, minFactor 1/1024
fn find_ab(a: *mem.Arena, spread: f64, min_dist: f64, ab: []f64) -> err {
    let p = 300usize
    let (xv, e0) = mem.alloc[f64](a, p)
    let (yv, e1) = mem.alloc[f64](a, p)
    let (f0, e2) = mem.alloc[f64](a, p)
    let (f1, e3) = mem.alloc[f64](a, p)
    let (gr, e4) = mem.alloc[f64](a, 2usize * p)
    let (resv, e5) = mem.alloc[f64](a, p)
    let (rr, e6) = mem.alloc[f64](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e0 }
    var qa: [2]f64 = zero
    var i = 0usize
    let by = (spread * 3.0f64 - 0.0f64) / f64(p - 1usize)
    while i < p {
        xv[i] = 0.0f64 + f64(i) * by
        i += 1usize
    }
    xv[p - 1usize] = spread * 3.0f64
    i = 0usize
    while i < p {
        if xv[i] < min_dist { yv[i] = 1.0f64 } else { yv[i] = math.exp[f64](0.0f64 - (xv[i] - min_dist) / spread) }
        i += 1usize
    }
    var pa = 1.0f64
    var pb = 1.0f64
    let eps = 1.4901161193847656e-8f64
    // setPars: residual, deviance and the QR of the numeric gradient at (pa, pb)
    var dev = 0.0f64
    var fac = 1.0f64
    var iter = 0usize
    var conv = false
    var first = true
    var npa = pa
    var npb = pb
    var incr: [2]f64 = zero
    while iter < 50usize && !conv {
        if first {
            npa = pa
            npb = pb
        }
        // evaluate at the trial point (npa, npb) unless it is the start
        ab_model(xv, p, npa, npb, f0)
        var dd = 0.0f64
        i = 0usize
        while i < p {
            resv[i] = yv[i] - f0[i]
            dd += resv[i] * resv[i]
            i += 1usize
        }
        var da = eps
        if npa != 0.0f64 { da = math.abs[f64](npa) * eps }
        ab_model(xv, p, npa + da, npb, f1)
        i = 0usize
        while i < p {
            gr[i] = (f1[i] - f0[i]) / da
            i += 1usize
        }
        var db = eps
        if npb != 0.0f64 { db = math.abs[f64](npb) * eps }
        ab_model(xv, p, npa, npb + db, f1)
        i = 0usize
        while i < p {
            gr[p + i] = (f1[i] - f0[i]) / db
            i += 1usize
        }
        qr2(gr, p, qa[0usize..2usize])
        if first {
            dev = dd
            first = false
        }
        // conv
        i = 0usize
        while i < p {
            rr[i] = resv[i]
            i += 1usize
        }
        qty2(gr, p, qa[0usize..2usize], rr)
        var top = rr[0usize] * rr[0usize] + rr[1usize] * rr[1usize]
        var bot = 0.0f64
        i = 2usize
        while i < p {
            bot += rr[i] * rr[i]
            i += 1usize
        }
        if math.sqrt[f64](top / bot) <= 1.0e-5f64 {
            conv = true
        } else {
            // incr = qr.coef
            incr[1usize] = rr[1usize] / gr[1usize + p * 1usize]
            incr[0usize] = rr[0usize]
            let t = 0.0f64 - incr[1usize]
            incr[0usize] += t * gr[0usize + p * 1usize]
            incr[0usize] = incr[0usize] / gr[0usize]
            // step halving
            var acc = false
            while fac >= 1.0f64 / 1024.0f64 && !acc {
                npa = pa + fac * incr[0usize]
                npb = pb + fac * incr[1usize]
                ab_model(xv, p, npa, npb, f1)
                var nd = 0.0f64
                i = 0usize
                while i < p {
                    let r = yv[i] - f1[i]
                    nd += r * r
                    i += 1usize
                }
                if nd <= dev {
                    dev = nd
                    pa = npa
                    pb = npb
                    fac = math.min[f64](2.0f64 * fac, 1.0f64)
                    acc = true
                } else {
                    fac /= 2.0f64
                }
            }
            if !acc { ret Bad }
            iter += 1usize
        }
    }
    if !conv { ret Bad }
    ab[0usize] = pa
    ab[1usize] = pb
    ret ok
}

// uwot::umap(x, n_neighbors = k, n_components = nd, n_epochs, learning_rate = alpha, a, b, repulsion_strength = gamma, negative_sample_rate, set_op_mix_ratio, local_connectivity, init, seed)
// with g already seeded (set.seed(seed)); out is n by nd row-major
fn umap_fit(a: *mem.Arena, x: []const f64, n: usize, d: usize, k: usize, nd: usize, n_epochs: usize, alpha: f64, ab_a: f64, ab_b: f64, gamma: f64, neg_rate: f64, mix: f64, local_connectivity: f64, init: usize, g: *rng.Rng, out: []f64) -> err {
    let (idx, e0) = mem.alloc[usize](a, n * k)
    let (dist, e1) = mem.alloc[f64](a, n * k)
    let (v, e2) = mem.alloc[f64](a, n * n)
    if e0 != ok || e1 != ok || e2 != ok { ret e0 }
    knn_exact(x, n, d, k, idx, dist)
    let eg = fuzzy_graph(a, idx, dist, n, k, local_connectivity, mix, v)
    if eg != ok { ret eg }
    let es = start_embedding(a, v, n, nd, init, g, out)
    if es != ok { ret es }
    if n_epochs == 0usize { ret ok }
    ret optimize(a, v, n, nd, n_epochs, alpha, ab_a, ab_b, gamma, neg_rate, g, out)
}
