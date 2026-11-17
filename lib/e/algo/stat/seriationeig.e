// R seriation, the eigenvector methods: Spectral, Spectral_norm, MDS (cmdscale, k = 1) and MDS_angle (k = 2).
// An order from an eigenvector is only as oriented as the eigenvector is, and LAPACK's dsyevr fixes the sign in its
// own way: the matrix is reduced to a tridiagonal one by Householder reflectors (dsytd2, lower), the eigenvector of
// the tridiagonal matrix gets a positive component at its largest entry (the twist index of dstemr), and the
// reflectors carry it back. That is reproduced here; where two entries of the tridiagonal vector are close in size
// LAPACK's choice depends on rounding in dlarrv, so the orientation can differ from R's on a few percent of the
// vectors, and an order can then come out reversed. Orders are compared up to reversal by the fixture.
//
// Dissimilarities are a full symmetric n by n row-major matrix d; an order is a permutation of 0..n-1.

use e.math
use e.mem
use e.ml.reduce as reduce

// R's order(): ascending, ties by index
fn order_of(v: []const f64, n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = i
        i += 1usize
    }
    // insertion sort is stable
    i = 1usize
    while i < n {
        let cur = out[i]
        var j = i
        while j > 0usize && v[out[j - 1usize]] > v[cur] {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
}

fn sign_of(x: f64, y: f64) -> f64 {
    if y < 0.0f64 { ret 0.0f64 - math.abs[f64](x) }
    ret math.abs[f64](x)
}

// eigen(m, symmetric = TRUE) of R: values falling, vecs[k * n + i] the i-th entry of the k-th vector, signs as LAPACK's
fn eigen_lapack(a: *mem.Arena, m: []const f64, n: usize, vals: []f64, vecs: []f64) -> err {
    if n == 1usize {
        vals[0usize] = m[0usize]
        vecs[0usize] = 1.0f64
        ret ok
    }
    let (w, e1) = mem.alloc[f64](a, n * n)
    let (vv, e2) = mem.alloc[f64](a, n * n)
    let (tau, e3) = mem.alloc[f64](a, n)
    let (dd, e4) = mem.alloc[f64](a, n)
    let (ee, e5) = mem.alloc[f64](a, n)
    let (tm, e6) = mem.alloc[f64](a, n * n)
    let (pv, e7) = mem.alloc[f64](a, n)
    let (qv, e8) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        w[i] = m[i]
        vv[i] = 0.0f64
        i += 1usize
    }
    // dsytd2, uplo = L
    i = 0usize
    while i + 1usize < n {
        let alpha = w[(i + 1usize) * n + i]
        var xs = 0.0f64
        var k = i + 2usize
        while k < n {
            xs += w[k * n + i] * w[k * n + i]
            k += 1usize
        }
        let xnorm = math.sqrt[f64](xs)
        var taui = 0.0f64
        var beta = alpha
        vv[i * n + i + 1usize] = 1.0f64
        if xnorm != 0.0f64 {
            beta = sign_of(math.sqrt[f64](alpha * alpha + xnorm * xnorm), alpha)
            beta = 0.0f64 - beta
            taui = (beta - alpha) / beta
            k = i + 2usize
            while k < n {
                vv[i * n + k] = w[k * n + i] / (alpha - beta)
                k += 1usize
            }
        }
        ee[i] = beta
        tau[i] = taui
        if taui != 0.0f64 {
            // p = taui * A v over the trailing block, then A -= v w' + w v'
            var dot = 0.0f64
            var r = i + 1usize
            while r < n {
                var s = 0.0f64
                var c = i + 1usize
                while c < n {
                    s += w[r * n + c] * vv[i * n + c]
                    c += 1usize
                }
                pv[r] = taui * s
                dot += pv[r] * vv[i * n + r]
                r += 1usize
            }
            let alw = 0.0f64 - 0.5f64 * taui * dot
            r = i + 1usize
            while r < n {
                qv[r] = pv[r] + alw * vv[i * n + r]
                r += 1usize
            }
            r = i + 1usize
            while r < n {
                var c = i + 1usize
                while c < n {
                    w[r * n + c] = w[r * n + c] - vv[i * n + r] * qv[c] - qv[r] * vv[i * n + c]
                    c += 1usize
                }
                r += 1usize
            }
        }
        dd[i] = w[i * n + i]
        i += 1usize
    }
    dd[n - 1usize] = w[(n - 1usize) * n + n - 1usize]
    i = 0usize
    while i < n * n {
        tm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        tm[i * n + i] = dd[i]
        if i + 1usize < n {
            tm[(i + 1usize) * n + i] = ee[i]
            tm[i * n + i + 1usize] = ee[i]
        }
        i += 1usize
    }
    if n == 2usize {
        // dstemr, n = 2: dlaev2 of (d1, e1, d2); the vector of the smaller-magnitude root is (-sn, cs), the other (cs, sn)
        let a1 = dd[0usize]
        let b1 = ee[0usize]
        let c1 = dd[1usize]
        let sm = a1 + c1
        let df = a1 - c1
        let adf = math.abs[f64](df)
        let tb = b1 + b1
        let ab = math.abs[f64](tb)
        var acmx = c1
        var acmn = a1
        if math.abs[f64](a1) > math.abs[f64](c1) {
            acmx = a1
            acmn = c1
        }
        var rt = ab * math.sqrt[f64](2.0f64)
        if adf > ab { rt = adf * math.sqrt[f64](1.0f64 + (ab / adf) * (ab / adf)) }
        if adf < ab { rt = ab * math.sqrt[f64](1.0f64 + (adf / ab) * (adf / ab)) }
        var rt1 = 0.5f64 * rt
        var rt2 = 0.0f64 - 0.5f64 * rt
        var sgn1 = 1.0f64
        if sm < 0.0f64 {
            rt1 = 0.5f64 * (sm - rt)
            sgn1 = 0.0f64 - 1.0f64
            rt2 = (acmx / rt1) * acmn - (b1 / rt1) * b1
        }
        if sm > 0.0f64 {
            rt1 = 0.5f64 * (sm + rt)
            rt2 = (acmx / rt1) * acmn - (b1 / rt1) * b1
        }
        var cs = 0.0f64
        var sgn2 = 1.0f64
        if df >= 0.0f64 { cs = df + rt } else {
            cs = df - rt
            sgn2 = 0.0f64 - 1.0f64
        }
        let acs = math.abs[f64](cs)
        var cs1 = 1.0f64
        var sn1 = 0.0f64
        if acs > ab {
            let ct = (0.0f64 - tb) / cs
            sn1 = 1.0f64 / math.sqrt[f64](1.0f64 + ct * ct)
            cs1 = ct * sn1
        } else {
            if ab != 0.0f64 {
                let tn = (0.0f64 - cs) / tb
                cs1 = 1.0f64 / math.sqrt[f64](1.0f64 + tn * tn)
                sn1 = tn * cs1
            }
        }
        if sgn1 == sgn2 {
            let tn = cs1
            cs1 = 0.0f64 - sn1
            sn1 = tn
        }
        // rt1 has cs1, sn1; rt2 has -sn1, cs1; falling order
        if rt1 >= rt2 {
            vals[0usize] = rt1
            vecs[0usize] = cs1
            vecs[1usize] = sn1
            vals[1usize] = rt2
            vecs[2usize] = 0.0f64 - sn1
            vecs[3usize] = cs1
        } else {
            vals[0usize] = rt2
            vecs[0usize] = 0.0f64 - sn1
            vecs[1usize] = cs1
            vals[1usize] = rt1
            vecs[2usize] = cs1
            vecs[3usize] = sn1
        }
        ret ok
    }
    let er = reduce.symmetric_eigen(tm, n, vals, vecs, 1.0e-32f64, 200u32)
    if er != ok { ret er }
    var kk = 0usize
    while kk < n {
        var r = 0usize
        var mx = 0.0f64
        var q = 0usize
        while q < n {
            if math.abs[f64](vecs[kk * n + q]) > mx {
                mx = math.abs[f64](vecs[kk * n + q])
                r = q
            }
            q += 1usize
        }
        if vecs[kk * n + r] < 0.0f64 {
            q = 0usize
            while q < n {
                vecs[kk * n + q] = 0.0f64 - vecs[kk * n + q]
                q += 1usize
            }
        }
        // carry back: z = H(0) H(1) ... H(n-2) z
        var h = n - 1usize
        while h > 0usize {
            let ih = h - 1usize
            if tau[ih] != 0.0f64 {
                var dot = 0.0f64
                q = ih + 1usize
                while q < n {
                    dot += vv[ih * n + q] * vecs[kk * n + q]
                    q += 1usize
                }
                q = ih + 1usize
                while q < n {
                    vecs[kk * n + q] = vecs[kk * n + q] - tau[ih] * dot * vv[ih * n + q]
                    q += 1usize
                }
            }
            h -= 1usize
        }
        kk += 1usize
    }
    ret ok
}

// seriate(d, "Spectral"): the order of the Fiedler vector of the Laplacian of 1 / (1 + d)
fn spectral_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (l, e1) = mem.alloc[f64](a, n * n)
    let (vals, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < n {
            rs += 1.0f64 / (1.0f64 + d[i * n + j])
            j += 1usize
        }
        j = 0usize
        while j < n {
            l[i * n + j] = 0.0f64 - 1.0f64 / (1.0f64 + d[i * n + j])
            j += 1usize
        }
        l[i * n + i] = rs - 1.0f64 / (1.0f64 + d[i * n + i])
        i += 1usize
    }
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let er = eigen_lapack(a, l, n, vals, vecs)
    if er != ok { ret er }
    order_of(vecs[(n - 2usize) * n..(n - 1usize) * n], n, out)
    ret ok
}

// seriate(d, "Spectral_norm"): the order of the second eigenvector of the normalised matrix, scaled by the row weights
fn spectral_norm_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (l, e1) = mem.alloc[f64](a, n * n)
    let (vals, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * n)
    let (ds, e4) = mem.alloc[f64](a, n)
    let (key, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < n {
            let wv = 1.0f64 / (1.0f64 + d[i * n + j])
            rs += 1.0f64 / math.sqrt[f64](wv)
            j += 1usize
        }
        ds[i] = rs
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let wv = 1.0f64 / (1.0f64 + d[i * n + j])
            l[i * n + j] = (ds[i] * wv) * ds[j]
            j += 1usize
        }
        i += 1usize
    }
    // LAPACK reads the lower triangle
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            l[i * n + j] = l[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let er = eigen_lapack(a, l, n, vals, vecs)
    if er != ok { ret er }
    i = 0usize
    while i < n {
        key[i] = ds[i] * vecs[n + i]
        i += 1usize
    }
    order_of(key, n, out)
    ret ok
}

// stats::cmdscale(d, k, eig = TRUE): coords n by k row-major
fn cmdscale_k(a: *mem.Arena, d: []const f64, n: usize, k: usize, coords: []f64) -> err {
    let (b, e1) = mem.alloc[f64](a, n * n)
    let (vals, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        b[i] = d[i] * d[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += b[i * n + j]
            j += 1usize
        }
        let mu = s / f64(n)
        j = 0usize
        while j < n {
            b[i * n + j] -= mu
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < n {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += b[i * n + j]
            i += 1usize
        }
        let mu = s / f64(n)
        i = 0usize
        while i < n {
            b[i * n + j] -= mu
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n * n {
        b[i] = (0.0f64 - b[i]) / 2.0f64
        i += 1usize
    }
    let er = eigen_lapack(a, b, n, vals, vecs)
    if er != ok { ret er }
    var c = 0usize
    while c < k {
        var s = 0.0f64
        if vals[c] > 0.0f64 { s = math.sqrt[f64](vals[c]) }
        i = 0usize
        while i < n {
            coords[i * k + c] = vecs[c * n + i] * s
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// seriate(d, "MDS"): the order of the first cmdscale coordinate
fn mds_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (pt, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let er = cmdscale_k(a, d, n, 1usize, pt)
    if er != ok { ret er }
    order_of(pt, n, out)
    ret ok
}

// seriate(d, "MDS_angle"): the order of the angle in the plane of the first two cmdscale coordinates, cut at the largest gap
fn mds_angle_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (pt, e1) = mem.alloc[f64](a, 2usize * n)
    let (al, e2) = mem.alloc[f64](a, n)
    let (o2, e3) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    if n < 3usize {
        mds_order_small(n, out)
        ret ok
    }
    let er = cmdscale_k(a, d, n, 2usize, pt)
    if er != ok { ret er }
    var i = 0usize
    while i < n {
        al[i] = math.atan2[f64](pt[i * 2usize], pt[i * 2usize + 1usize])
        i += 1usize
    }
    order_of(al, n, o2)
    var cut = 0usize
    var best = -1.0f64
    i = 0usize
    while i < n {
        var nxt = al[o2[0usize]] + 2.0f64 * 3.141592653589793f64
        if i + 1usize < n { nxt = al[o2[i + 1usize]] }
        let g = math.abs[f64](nxt - al[o2[i]])
        if g > best {
            best = g
            cut = i + 1usize
        }
        i += 1usize
    }
    // cut is 1-based as R's which.max; rotate when cut < n
    i = 0usize
    while i < n {
        out[i] = o2[i]
        i += 1usize
    }
    if cut < n {
        var p = 0usize
        while p < n - cut {
            out[p] = o2[cut + p]
            p += 1usize
        }
        p = 0usize
        while p < cut {
            out[n - cut + p] = o2[p]
            p += 1usize
        }
    }
    ret ok
}

fn mds_order_small(n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = i
        i += 1usize
    }
}
