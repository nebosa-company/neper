// The self-organising maps and learning vector quantisation of the R package class: `somgrid`, `SOM` (the online
// algorithm as VR_onlineSOM runs it), `batchSOM`, `lvqinit`, `lvq1`, `lvq2`, `lvq3` and `olvq1`, drawing from the
// Mersenne-Twister stream of e.algo.rand.r the way the package does. Data and codebooks are row-major, classes 1-based.
//
// VR_onlineSOM as shipped has its update loop inside the search loop over the codes and reuses the loop variable, so the search
// stops after the first code: the winner is always code 0, and each step draws one uniform for the data point. The port keeps that.

use e.algo.rand.r as rng
use e.algo.stat.classknn as knn
use e.math
use e.mem

// somgrid(xdim, ydim, topo): the ng = xdim * ydim points, x varying fastest, row-major ng by 2
fn somgrid(xdim: usize, ydim: usize, hex: bool, pts: []f64) {
    var yy = 0usize
    while yy < ydim {
        var xx = 0usize
        while xx < xdim {
            let at = yy * xdim + xx
            var px = f64(xx + 1usize)
            var py = f64(yy + 1usize)
            if hex {
                let par = (yy + 1usize) % 2usize
                px = px + 0.5f64 * f64(par)
                py = math.sqrt[f64](3.0f64) / 2.0f64 * py
            }
            pts[at * 2usize] = px
            pts[at * 2usize + 1usize] = py
            xx += 1usize
        }
        yy += 1usize
    }
}

// as.matrix(dist(pts)): Euclidean distances between the grid points, ng by ng
fn grid_dist(pts: []const f64, ng: usize, out: []f64) {
    var i = 0usize
    while i < ng {
        var j = 0usize
        while j < ng {
            let dx = pts[i * 2usize] - pts[j * 2usize]
            let dy = pts[i * 2usize + 1usize] - pts[j * 2usize + 1usize]
            out[i * ng + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
}

// SOM(data, grid, rlen, alpha, radii, init): the codes updated in place, one data point per step
fn som_online(g: *rng.Rng, data: []const f64, n: usize, p: usize, codes: []f64, ncodes: usize, nhbr: []const f64, alpha: []const f64, radii: []const f64) {
    var k = 0usize
    while k < alpha.len {
        let i = usize(f64(n) * rng.unif(g))
        // the winner: the loop over the codes ends after code 0 (see above)
        let nearest = 0usize
        var cd = 0usize
        while cd < ncodes {
            if nhbr[cd * ncodes + nearest] <= radii[k] {
                var j = 0usize
                while j < p {
                    codes[cd * p + j] += alpha[k] * (data[i * p + j] - codes[cd * p + j])
                    j += 1usize
                }
            }
            cd += 1usize
        }
        k += 1usize
    }
}

// batchSOM(data, grid, radii, init): codes updated in place
fn batch_som(a: *mem.Arena, g: *rng.Rng, data: []const f64, n: usize, p: usize, codes: []f64, ng: usize, nhbr: []const f64, radii: []const f64) -> err {
    let (cls, ce) = mem.alloc[i64](a, ng)
    let (rsum, re) = mem.alloc[f64](a, ng)
    let (acc, ae) = mem.alloc[f64](a, ng * p)
    if ce != ok { ret ce }
    if re != ok { ret re }
    if ae != ok { ret ae }
    var i = 0usize
    while i < ng {
        cls[i] = i64(i + 1usize)
        i += 1usize
    }
    var ri = 0usize
    while ri < radii.len {
        let r = radii[ri]
        let (cl, ke) = knn.knn1(a, g, codes, cls, data, p, ng)
        if ke != ok { ret ke }
        i = 0usize
        while i < ng {
            rsum[i] = 0.0f64
            var j = 0usize
            while j < p {
                acc[i * p + j] = 0.0f64
                j += 1usize
            }
            i += 1usize
        }
        var d = 0usize
        while d < n {
            let c = usize(cl[d]) - 1usize
            i = 0usize
            while i < ng {
                if nhbr[i * ng + c] <= r {
                    rsum[i] += 1.0f64
                    var j = 0usize
                    while j < p {
                        acc[i * p + j] += data[d * p + j]
                        j += 1usize
                    }
                }
                i += 1usize
            }
            d += 1usize
        }
        i = 0usize
        while i < ng {
            if rsum[i] > 0.0f64 {
                var j = 0usize
                while j < p {
                    codes[i * p + j] = acc[i * p + j] / rsum[i]
                    j += 1usize
                }
            }
            i += 1usize
        }
        ri += 1usize
    }
    ret ok
}

fn round_even(x: f64) -> f64 {
    let fl = math.floor[f64](x)
    let d = x - fl
    if d < 0.5f64 { ret fl }
    if d > 0.5f64 { ret fl + 1.0f64 }
    if fl - 2.0f64 * math.floor[f64](fl / 2.0f64) == 0.0f64 { ret fl }
    ret fl + 1.0f64
}

// lvqinit(x, cl, size, prior, k): the selected row indices (0-based) in order; size < 0 for the default; prior from the class proportions
fn lvqinit(a: *mem.Arena, g: *rng.Rng, x: []const f64, n: usize, p: usize, cl: []const i64, nc: usize, size0: f64, k: usize, sel: []usize) -> (usize, err) {
    let (cnt, e1) = mem.alloc[f64](a, nc)
    let (inside, e2) = mem.alloc[bool](a, n)
    if e1 != ok { ret (0usize, e1) }
    if e2 != ok { ret (0usize, e2) }
    var i = 0usize
    while i < nc {
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        cnt[usize(cl[i]) - 1usize] += 1.0f64
        i += 1usize
    }
    var size = size0
    if size < 0.0f64 {
        size = round_even(0.4f64 * f64(nc) * (f64(nc) - 1.0f64 + f64(p) / 2.0f64))
        if f64(n) < size { size = f64(n) }
    }
    let (res, pr, ke) = knn.knn(a, g, x, cl, x, p, nc, k, 0i64, true, true)
    if ke != ok { ret (0usize, ke) }
    i = 0usize
    while i < n {
        inside[i] = res[i] == cl[i]
        i += 1usize
    }
    var at = 0usize
    var c = 0usize
    while c < nc {
        let prior = cnt[c] / f64(n)
        let (set, se) = mem.alloc[usize](a, n)
        if se != ok { ret (0usize, se) }
        var m = 0usize
        i = 0usize
        while i < n {
            if usize(cl[i]) == c + 1usize && inside[i] {
                set[m] = i
                m += 1usize
            }
            i += 1usize
        }
        if m > 1usize {
            var take = usize(round_even(size * prior))
            if m < take { take = m }
            let (smp, sme) = rng.sample_int(a, g, i64(m), i64(take), false)
            if sme != ok { ret (0usize, sme) }
            i = 0usize
            while i < take {
                sel[at] = set[usize(smp[i]) - 1usize]
                at += 1usize
                i += 1usize
            }
        } else {
            i = 0usize
            while i < m {
                sel[at] = set[i]
                at += 1usize
                i += 1usize
            }
        }
        c += 1usize
    }
    ret (at, ok)
}

fn dsq(x: []const f64, row: usize, xc: []const f64, c: usize, p: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < p {
        let t = x[row * p + k] - xc[c * p + k]
        s += t * t
        k += 1usize
    }
    ret s
}

// method 1 lvq1, 2 lvq2, 3 lvq3, 4 olvq1: the codebook xc (nc by p) trained in place; the data rows are drawn first by sample(n, niter, TRUE)
fn lvq_train(a: *mem.Arena, g: *rng.Rng, method: u8, x: []const f64, n: usize, p: usize, cl: []const i64, xc: []f64, clc: []const i64, nc: usize, niter: usize, alpha: f64, win: f64, epsilon: f64) -> err {
    let (iters, ie) = rng.sample_int(a, g, i64(n), i64(niter), true)
    if ie != ok { ret ie }
    let (al, ae) = mem.alloc[f64](a, nc)
    if ae != ok { ret ae }
    var j = 0usize
    while j < nc {
        al[j] = alpha
        j += 1usize
    }
    let dmax = 1.7976931348623157e308f64
    var iter = 0usize
    while iter < niter {
        let npat = usize(iters[iter] - 1i64)
        let alpha_t = alpha * f64(niter - iter) / f64(niter)
        if method == 1u8 || method == 4u8 {
            var dm = dmax
            var index = 0usize
            j = 0usize
            while j < nc {
                let d = dsq(x, npat, xc, j, p)
                if d < dm {
                    dm = d
                    index = j
                }
                j += 1usize
            }
            var s = 0.0f64 - 1.0f64
            if clc[index] == cl[npat] { s = 1.0f64 }
            var k = 0usize
            while k < p {
                if method == 1u8 { xc[index * p + k] += s * alpha_t * (x[npat * p + k] - xc[index * p + k]) } else { xc[index * p + k] += s * al[index] * (x[npat * p + k] - xc[index * p + k]) }
                k += 1usize
            }
            if method == 4u8 {
                var v = al[index] / (1.0f64 + s * al[index])
                if alpha < v { v = alpha }
                al[index] = v
            }
        } else {
            var dm = dmax
            var ndm = dmax
            var index = 0usize
            var nindex = 0usize
            j = 0usize
            while j < nc {
                let d = dsq(x, npat, xc, j, p)
                if d < dm {
                    ndm = dm
                    nindex = index
                    dm = d
                    index = j
                } else if d < ndm {
                    ndm = d
                    nindex = j
                }
                j += 1usize
            }
            if clc[index] != clc[nindex] {
                if (clc[index] == cl[npat] || clc[nindex] == cl[npat]) && dm / ndm > (1.0f64 - win) / (1.0f64 + win) {
                    if clc[nindex] == cl[npat] {
                        let tmp = index
                        index = nindex
                        nindex = tmp
                    }
                    var k = 0usize
                    while k < p {
                        xc[index * p + k] += alpha_t * (x[npat * p + k] - xc[index * p + k])
                        xc[nindex * p + k] -= alpha_t * (x[npat * p + k] - xc[nindex * p + k])
                        k += 1usize
                    }
                }
            } else if method == 3u8 && clc[index] == cl[npat] {
                var k = 0usize
                while k < p {
                    xc[index * p + k] += epsilon * alpha_t * (x[npat * p + k] - xc[index * p + k])
                    xc[nindex * p + k] += epsilon * alpha_t * (x[npat * p + k] - xc[nindex * p + k])
                    k += 1usize
                }
            }
        }
        iter += 1usize
    }
    ret ok
}
