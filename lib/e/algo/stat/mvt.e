// R mvtnorm's Genz-Bretz algorithm (`mvtdst` of mvt.f): multivariate normal and (non-central) t probabilities over
// a box by the randomised Korobov lattice rule on R's uniform stream, with the variable reordering, the Cholesky
// factor, the one- and two-dimensional special cases (Drezner-Wesolowsky bivariate normal, Dunnett-Sobel bivariate t)
// and the lattice parameters of the paper, line for line. Fortran's 1-based arrays are kept: slot 0 is unused.
//
// Not here: the Miwa and TVPACK algorithms, qmvnorm and qmvt, the sigma and mean pre-scaling of `pmvnorm` and `pmvt`
// (done by the callers: standardise to a correlation matrix and shift by the mean).

use e.algo.rand.r as rng
use e.algo.stat.mvt_tables as tables
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem
use e.str

fn mvphi(z: f64) -> f64 { ret dist.pnorm(z, 0.0f64, 1.0f64, true, false) }

fn mvphnv(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

fn pi() -> f64 { ret 3.141592653589793f64 }

fn sgn(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

// the bivariate normal upper tail P(X > sh, Y > sk) by Drezner-Wesolowsky with Genz's modifications
fn mvbvu(sh: f64, sk: f64, r: f64) -> f64 {
    let twopi = 6.283185307179586f64
    var x: [10]f64 = zero
    var w: [10]f64 = zero
    var ng = 3usize
    var lg = 10usize
    if math.abs[f64](r) < 0.3f64 {
        ng = 1usize
        lg = 3usize
    } else if math.abs[f64](r) < 0.75f64 {
        ng = 2usize
        lg = 6usize
    }
    if ng == 1usize {
        w[0usize] = 0.1713244923791705f64
        x[0usize] = 0.0f64 - 0.9324695142031522f64
        w[1usize] = 0.3607615730481384f64
        x[1usize] = 0.0f64 - 0.6612093864662647f64
        w[2usize] = 0.4679139345726904f64
        x[2usize] = 0.0f64 - 0.2386191860831970f64
    } else if ng == 2usize {
        w[0usize] = 0.4717533638651177e-01f64
        x[0usize] = 0.0f64 - 0.9815606342467191f64
        w[1usize] = 0.1069393259953183f64
        x[1usize] = 0.0f64 - 0.9041172563704750f64
        w[2usize] = 0.1600783285433464f64
        x[2usize] = 0.0f64 - 0.7699026741943050f64
        w[3usize] = 0.2031674267230659f64
        x[3usize] = 0.0f64 - 0.5873179542866171f64
        w[4usize] = 0.2334925365383547f64
        x[4usize] = 0.0f64 - 0.3678314989981802f64
        w[5usize] = 0.2491470458134029f64
        x[5usize] = 0.0f64 - 0.1252334085114692f64
    } else {
        w[0usize] = 0.1761400713915212e-01f64
        x[0usize] = 0.0f64 - 0.9931285991850949f64
        w[1usize] = 0.4060142980038694e-01f64
        x[1usize] = 0.0f64 - 0.9639719272779138f64
        w[2usize] = 0.6267204833410906e-01f64
        x[2usize] = 0.0f64 - 0.9122344282513259f64
        w[3usize] = 0.8327674157670475e-01f64
        x[3usize] = 0.0f64 - 0.8391169718222188f64
        w[4usize] = 0.1019301198172404f64
        x[4usize] = 0.0f64 - 0.7463319064601508f64
        w[5usize] = 0.1181945319615184f64
        x[5usize] = 0.0f64 - 0.6360536807265150f64
        w[6usize] = 0.1316886384491766f64
        x[6usize] = 0.0f64 - 0.5108670019508271f64
        w[7usize] = 0.1420961093183821f64
        x[7usize] = 0.0f64 - 0.3737060887154196f64
        w[8usize] = 0.1491729864726037f64
        x[8usize] = 0.0f64 - 0.2277858511416451f64
        w[9usize] = 0.1527533871307259f64
        x[9usize] = 0.0f64 - 0.7652652113349733e-01f64
    }
    var h = sh
    var k = sk
    var hk = h * k
    var bvn = 0.0f64
    if math.abs[f64](r) < 0.925f64 {
        let hs = (h * h + k * k) / 2.0f64
        let asr = math.asin[f64](r)
        var i = 0usize
        while i < lg {
            var sn = math.sin[f64](asr * (x[i] + 1.0f64) / 2.0f64)
            bvn = bvn + w[i] * math.exp[f64]((sn * hk - hs) / (1.0f64 - sn * sn))
            sn = math.sin[f64](asr * (0.0f64 - x[i] + 1.0f64) / 2.0f64)
            bvn = bvn + w[i] * math.exp[f64]((sn * hk - hs) / (1.0f64 - sn * sn))
            i += 1usize
        }
        bvn = bvn * asr / (2.0f64 * twopi) + mvphi(0.0f64 - h) * mvphi(0.0f64 - k)
    } else {
        if r < 0.0f64 {
            k = 0.0f64 - k
            hk = 0.0f64 - hk
        }
        if math.abs[f64](r) < 1.0f64 {
            let as_ = (1.0f64 - r) * (1.0f64 + r)
            var a = math.sqrt[f64](as_)
            let bs = (h - k) * (h - k)
            let c = (4.0f64 - hk) / 8.0f64
            let d = (12.0f64 - hk) / 16.0f64
            bvn = a * math.exp[f64](0.0f64 - (bs / as_ + hk) / 2.0f64) * (1.0f64 - c * (bs - as_) * (1.0f64 - d * bs / 5.0f64) / 3.0f64 + c * d * as_ * as_ / 5.0f64)
            if hk > 0.0f64 - 160.0f64 {
                let b = math.sqrt[f64](bs)
                bvn = bvn - math.exp[f64](0.0f64 - hk / 2.0f64) * math.sqrt[f64](twopi) * mvphi(0.0f64 - b / a) * b * (1.0f64 - c * bs * (1.0f64 - d * bs / 5.0f64) / 3.0f64)
            }
            a = a / 2.0f64
            var i = 0usize
            while i < lg {
                var xs = (a * (x[i] + 1.0f64)) * (a * (x[i] + 1.0f64))
                var rs = math.sqrt[f64](1.0f64 - xs)
                bvn = bvn + a * w[i] * (math.exp[f64](0.0f64 - bs / (2.0f64 * xs) - hk / (1.0f64 + rs)) / rs - math.exp[f64](0.0f64 - (bs / xs + hk) / 2.0f64) * (1.0f64 + c * xs * (1.0f64 + d * xs)))
                let q = 0.0f64 - x[i] + 1.0f64
                xs = as_ * (q * q) / 4.0f64
                rs = math.sqrt[f64](1.0f64 - xs)
                bvn = bvn + a * w[i] * math.exp[f64](0.0f64 - (bs / xs + hk) / 2.0f64) * (math.exp[f64](0.0f64 - hk * xs / (2.0f64 * (1.0f64 + rs) * (1.0f64 + rs))) / rs - (1.0f64 + c * xs * (1.0f64 + d * xs)))
                i += 1usize
            }
            bvn = 0.0f64 - bvn / twopi
        }
        if r > 0.0f64 {
            var m = h
            if k > m { m = k }
            bvn = bvn + mvphi(0.0f64 - m)
        } else {
            bvn = 0.0f64 - bvn
            if k > h {
                if h < 0.0f64 { bvn = bvn + mvphi(k) - mvphi(h) } else { bvn = bvn + mvphi(0.0f64 - h) - mvphi(0.0f64 - k) }
            }
        }
    }
    ret bvn
}

// bivariate normal probability over a box (infin 0 upper only, 1 lower only, 2 both)
fn mvbvn(l1: f64, l2: f64, u1: f64, u2: f64, in1: i64, in2: i64, rho: f64) -> f64 {
    if in1 == 2i64 && in2 == 2i64 { ret mvbvu(l1, l2, rho) - mvbvu(u1, l2, rho) - mvbvu(l1, u2, rho) + mvbvu(u1, u2, rho) }
    if in1 == 2i64 && in2 == 1i64 { ret mvbvu(l1, l2, rho) - mvbvu(u1, l2, rho) }
    if in1 == 1i64 && in2 == 2i64 { ret mvbvu(l1, l2, rho) - mvbvu(l1, u2, rho) }
    if in1 == 2i64 && in2 == 0i64 { ret mvbvu(0.0f64 - u1, 0.0f64 - u2, rho) - mvbvu(0.0f64 - l1, 0.0f64 - u2, rho) }
    if in1 == 0i64 && in2 == 2i64 { ret mvbvu(0.0f64 - u1, 0.0f64 - u2, rho) - mvbvu(0.0f64 - u1, 0.0f64 - l2, rho) }
    if in1 == 1i64 && in2 == 0i64 { ret mvbvu(l1, 0.0f64 - u2, 0.0f64 - rho) }
    if in1 == 0i64 && in2 == 1i64 { ret mvbvu(0.0f64 - u1, l2, 0.0f64 - rho) }
    if in1 == 1i64 && in2 == 1i64 { ret mvbvu(l1, l2, rho) }
    if in1 == 0i64 && in2 == 0i64 { ret mvbvu(0.0f64 - u1, 0.0f64 - u2, rho) }
    ret 1.0f64
}

// the Student t distribution function with nu degrees of freedom
fn mvstdt(nu: i64, t: f64) -> f64 {
    if nu < 1i64 { ret mvphi(t) }
    if nu == 1i64 { ret (1.0f64 + 2.0f64 * math.atan[f64](t) / pi()) / 2.0f64 }
    if nu == 2i64 { ret (1.0f64 + t / math.sqrt[f64](2.0f64 + t * t)) / 2.0f64 }
    let tt = t * t
    let csthe = f64(nu) / (f64(nu) + tt)
    var polyn = 1.0f64
    var j = nu - 2i64
    while j >= 2i64 {
        polyn = 1.0f64 + f64(j - 1i64) * csthe * polyn / f64(j)
        j -= 2i64
    }
    var r = 0.0f64
    if nu % 2i64 == 1i64 {
        let ts = t / math.sqrt[f64](f64(nu))
        r = (1.0f64 + 2.0f64 * (math.atan[f64](ts) + ts * csthe * polyn) / pi()) / 2.0f64
    } else {
        let snthe = t / math.sqrt[f64](f64(nu) + tt)
        r = (1.0f64 + snthe * polyn) / 2.0f64
    }
    if r < 0.0f64 { r = 0.0f64 }
    ret r
}

// the bivariate t lower tail P(X < dh, Y < dk) of Dunnett and Sobel
fn mvbvtl(nu: i64, dh: f64, dk: f64, r: f64) -> f64 {
    let pii = 3.14159265358979323844f64
    let tpi = 2.0f64 * pii
    let dnu = f64(nu)
    let snu = math.sqrt[f64](dnu)
    let ors = 1.0f64 - r * r
    let hrk = dh - r * dk
    let krh = dk - r * dh
    var xnhk = 0.0f64
    var xnkh = 0.0f64
    if math.abs[f64](hrk) + ors > 0.0f64 {
        xnhk = hrk * hrk / (hrk * hrk + ors * (dnu + dk * dk))
        xnkh = krh * krh / (krh * krh + ors * (dnu + dh * dh))
    }
    let hs = sgn(dh - r * dk)
    let ks = sgn(dk - r * dh)
    var bvt = 0.0f64
    var gmph = 0.0f64
    var gmpk = 0.0f64
    var btnckh = 0.0f64
    var btpdkh = 0.0f64
    var btnchk = 0.0f64
    var btpdhk = 0.0f64
    if nu % 2i64 == 0i64 {
        bvt = math.atan2[f64](math.sqrt[f64](ors), 0.0f64 - r) / tpi
        gmph = dh / math.sqrt[f64](16.0f64 * (dnu + dh * dh))
        gmpk = dk / math.sqrt[f64](16.0f64 * (dnu + dk * dk))
        btnckh = 2.0f64 * math.atan2[f64](math.sqrt[f64](xnkh), math.sqrt[f64](1.0f64 - xnkh)) / pii
        btpdkh = 2.0f64 * math.sqrt[f64](xnkh * (1.0f64 - xnkh)) / pii
        btnchk = 2.0f64 * math.atan2[f64](math.sqrt[f64](xnhk), math.sqrt[f64](1.0f64 - xnhk)) / pii
        btpdhk = 2.0f64 * math.sqrt[f64](xnhk * (1.0f64 - xnhk)) / pii
        var j = 1i64
        while j <= nu / 2i64 {
            bvt = bvt + gmph * (1.0f64 + ks * btnckh)
            bvt = bvt + gmpk * (1.0f64 + hs * btnchk)
            btnckh = btnckh + btpdkh
            btpdkh = 2.0f64 * f64(j) * btpdkh * (1.0f64 - xnkh) / (2.0f64 * f64(j) + 1.0f64)
            btnchk = btnchk + btpdhk
            btpdhk = 2.0f64 * f64(j) * btpdhk * (1.0f64 - xnhk) / (2.0f64 * f64(j) + 1.0f64)
            gmph = gmph * (2.0f64 * f64(j) - 1.0f64) / (2.0f64 * f64(j) * (1.0f64 + dh * dh / dnu))
            gmpk = gmpk * (2.0f64 * f64(j) - 1.0f64) / (2.0f64 * f64(j) * (1.0f64 + dk * dk / dnu))
            j += 1i64
        }
    } else {
        let qhrk = math.sqrt[f64](dh * dh + dk * dk - 2.0f64 * r * dh * dk + dnu * ors)
        let hkrn = dh * dk + r * dnu
        let hkn = dh * dk - dnu
        let hpk = dh + dk
        bvt = math.atan2[f64](0.0f64 - snu * (hkn * qhrk + hpk * hkrn), hkn * hkrn - dnu * hpk * qhrk) / tpi
        if bvt < 0.0f64 - 1.0e-15f64 { bvt = bvt + 1.0f64 }
        gmph = dh / (tpi * snu * (1.0f64 + dh * dh / dnu))
        gmpk = dk / (tpi * snu * (1.0f64 + dk * dk / dnu))
        btnckh = math.sqrt[f64](xnkh)
        btpdkh = btnckh
        btnchk = math.sqrt[f64](xnhk)
        btpdhk = btnchk
        var j = 1i64
        while j <= (nu - 1i64) / 2i64 {
            bvt = bvt + gmph * (1.0f64 + ks * btnckh)
            bvt = bvt + gmpk * (1.0f64 + hs * btnchk)
            btpdkh = f64(2i64 * j - 1i64) * btpdkh * (1.0f64 - xnkh) / f64(2i64 * j)
            btnckh = btnckh + btpdkh
            btpdhk = f64(2i64 * j - 1i64) * btpdhk * (1.0f64 - xnhk) / f64(2i64 * j)
            btnchk = btnchk + btpdhk
            gmph = 2.0f64 * f64(j) * gmph / (f64(2i64 * j + 1i64) * (1.0f64 + dh * dh / dnu))
            gmpk = 2.0f64 * f64(j) * gmpk / (f64(2i64 * j + 1i64) * (1.0f64 + dk * dk / dnu))
            j += 1i64
        }
    }
    ret bvt
}

// bivariate normal (nu < 1) or t probability over a box
fn mvbvt(nu: i64, l1: f64, l2: f64, u1: f64, u2: f64, in1: i64, in2: i64, rho: f64) -> f64 {
    if nu < 1i64 { ret mvbvn(l1, l2, u1, u2, in1, in2, rho) }
    if in1 == 2i64 && in2 == 2i64 { ret mvbvtl(nu, u1, u2, rho) - mvbvtl(nu, u1, l2, rho) - mvbvtl(nu, l1, u2, rho) + mvbvtl(nu, l1, l2, rho) }
    if in1 == 2i64 && in2 == 1i64 { ret mvbvtl(nu, 0.0f64 - l1, 0.0f64 - l2, rho) - mvbvtl(nu, 0.0f64 - u1, 0.0f64 - l2, rho) }
    if in1 == 1i64 && in2 == 2i64 { ret mvbvtl(nu, 0.0f64 - l1, 0.0f64 - l2, rho) - mvbvtl(nu, 0.0f64 - l1, 0.0f64 - u2, rho) }
    if in1 == 2i64 && in2 == 0i64 { ret mvbvtl(nu, u1, u2, rho) - mvbvtl(nu, l1, u2, rho) }
    if in1 == 0i64 && in2 == 2i64 { ret mvbvtl(nu, u1, u2, rho) - mvbvtl(nu, u1, l2, rho) }
    if in1 == 1i64 && in2 == 0i64 { ret mvbvtl(nu, 0.0f64 - l1, u2, 0.0f64 - rho) }
    if in1 == 0i64 && in2 == 1i64 { ret mvbvtl(nu, u1, 0.0f64 - l2, 0.0f64 - rho) }
    if in1 == 1i64 && in2 == 1i64 { ret mvbvtl(nu, 0.0f64 - l1, 0.0f64 - l2, rho) }
    if in1 == 0i64 && in2 == 0i64 { ret mvbvtl(nu, u1, u2, rho) }
    ret 1.0f64
}

fn mvtdns0(x: f64) -> f64 {
    if math.abs[f64](x) < 10.0f64 { ret math.exp[f64](0.0f64 - x * x / 2.0f64) / 2.506628274631001f64 }
    ret 0.0f64
}

fn mvlims(a: f64, b: f64, infin: i64) -> (f64, f64) {
    var lower = 0.0f64
    var upper = 1.0f64
    if infin >= 0i64 {
        if infin != 0i64 { lower = mvphi(a) }
        if infin != 1i64 { upper = mvphi(b) }
    }
    if upper < lower { upper = lower }
    ret (lower, upper)
}

fn swp(v: []f64, i: usize, j: usize) {
    let t = v[i]
    v[i] = v[j]
    v[j] = t
}

fn mvswap(p: usize, q: usize, a: []f64, b: []f64, d: []f64, infin: []i64, n: usize, c: []f64) {
    swp(a, p, q)
    swp(b, p, q)
    swp(d, p, q)
    let ji = infin[p]
    infin[p] = infin[q]
    infin[q] = ji
    var jj = (p * (p - 1usize)) / 2usize
    var ii = (q * (q - 1usize)) / 2usize
    swp(c, jj + p, ii + q)
    var j = 1usize
    while j < p {
        swp(c, jj + j, ii + j)
        j += 1usize
    }
    jj = jj + p
    var i = p + 1usize
    while i < q {
        swp(c, jj + p, ii + i)
        jj = jj + i
        i += 1usize
    }
    ii = ii + q
    i = q + 1usize
    while i <= n {
        swp(c, ii + p, ii + q)
        ii = ii + i
        i += 1usize
    }
}

type Mv = struct { nu: i64, snu: f64, nd: usize, infi: []i64, a: []f64, b: []f64, dl: []f64, cov: []f64, y: []f64, inform: i64 }

// the limits sorted, the Cholesky factor in cov, expected values in y; pivot always true here
fn mvsort(m: *Mv, n: usize, lower: []const f64, upper: []const f64, delta: []const f64, correl: []const f64, infin: []const i64) {
    let eps = 1.0e-10f64
    m.inform = 0i64
    var ij = 0usize
    var ii = 0usize
    var nd = n
    var i = 1usize
    while i <= n {
        m.a[i] = 0.0f64
        m.b[i] = 0.0f64
        m.dl[i] = 0.0f64
        m.infi[i] = infin[i - 1usize]
        if m.infi[i] < 0i64 { nd -= 1usize } else {
            if m.infi[i] != 0i64 { m.a[i] = lower[i - 1usize] }
            if m.infi[i] != 1i64 { m.b[i] = upper[i - 1usize] }
            m.dl[i] = delta[i - 1usize]
        }
        var j = 1usize
        while j < i {
            ij += 1usize
            ii += 1usize
            m.cov[ij] = correl[ii - 1usize]
            j += 1usize
        }
        ij += 1usize
        m.cov[ij] = 1.0f64
        i += 1usize
    }
    if nd > 0usize {
        i = n
        while i >= nd + 1usize {
            if m.infi[i] >= 0i64 {
                var j = 1usize
                while j < i {
                    if m.infi[j] < 0i64 {
                        mvswap(j, i, m.a, m.b, m.dl, m.infi, n, m.cov)
                        break
                    }
                    j += 1usize
                }
            }
            i -= 1usize
        }
        ii = 0usize
        let jl = nd
        i = 1usize
        while i <= nd {
            var demin = 1.0f64
            var jmin = i
            var cvdiag = 0.0f64
            var amin = 0.0f64
            var bmin = 0.0f64
            ij = ii
            let epsi = eps * f64(i)
            var j = i
            while j <= jl {
                if m.cov[ij + j] > epsi {
                    let sumsq = math.sqrt[f64](m.cov[ij + j])
                    var sum = m.dl[j]
                    var k = 1usize
                    while k < i {
                        sum = sum + m.cov[ij + k] * m.y[k]
                        k += 1usize
                    }
                    let aj = (m.a[j] - sum) / sumsq
                    let bj = (m.b[j] - sum) / sumsq
                    let (d, e) = mvlims(aj, bj, m.infi[j])
                    if demin >= e - d {
                        jmin = j
                        amin = aj
                        bmin = bj
                        demin = e - d
                        cvdiag = sumsq
                    }
                }
                ij = ij + j
                j += 1usize
            }
            if jmin > i { mvswap(i, jmin, m.a, m.b, m.dl, m.infi, n, m.cov) }
            if m.cov[ii + i] < 0.0f64 - epsi { m.inform = 3i64 }
            m.cov[ii + i] = cvdiag
            if cvdiag > 0.0f64 {
                var il = ii + i
                var l = i + 1usize
                while l <= nd {
                    m.cov[il + i] = m.cov[il + i] / cvdiag
                    ij = ii + i
                    j = i + 1usize
                    while j <= l {
                        m.cov[il + j] = m.cov[il + j] - m.cov[il + i] * m.cov[ij + i]
                        ij = ij + j
                        j += 1usize
                    }
                    il = il + l
                    l += 1usize
                }
                if demin > epsi {
                    m.y[i] = 0.0f64
                    if m.infi[i] != 0i64 { m.y[i] = mvtdns0(amin) }
                    if m.infi[i] != 1i64 { m.y[i] = m.y[i] - mvtdns0(bmin) }
                    m.y[i] = m.y[i] / demin
                } else {
                    if m.infi[i] == 0i64 { m.y[i] = bmin }
                    if m.infi[i] == 1i64 { m.y[i] = amin }
                    if m.infi[i] == 2i64 { m.y[i] = (amin + bmin) / 2.0f64 }
                }
                j = 1usize
                while j <= i {
                    ii += 1usize
                    m.cov[ii] = m.cov[ii] / cvdiag
                    j += 1usize
                }
                m.a[i] = m.a[i] / cvdiag
                m.b[i] = m.b[i] / cvdiag
                m.dl[i] = m.dl[i] / cvdiag
            } else {
                var il = ii + i
                var l = i + 1usize
                while l <= nd {
                    m.cov[il + i] = 0.0f64
                    il = il + l
                    l += 1usize
                }
                var jj = i - 1usize
                var done = false
                while jj >= 1usize && !done {
                    if math.abs[f64](m.cov[ii + jj]) > epsi {
                        m.a[i] = m.a[i] / m.cov[ii + jj]
                        m.b[i] = m.b[i] / m.cov[ii + jj]
                        m.dl[i] = m.dl[i] / m.cov[ii + jj]
                        if m.cov[ii + jj] < 0.0f64 {
                            let t = m.a[i]
                            m.a[i] = m.b[i]
                            m.b[i] = t
                            if m.infi[i] != 2i64 { m.infi[i] = 1i64 - m.infi[i] }
                        }
                        l = 1usize
                        while l <= jj {
                            m.cov[ii + l] = m.cov[ii + l] / m.cov[ii + jj]
                            l += 1usize
                        }
                        l = jj + 1usize
                        var swapped = false
                        while l <= i - 1usize && !swapped {
                            if m.cov[(l - 1usize) * l / 2usize + jj + 1usize] > 0.0f64 {
                                ij = ii
                                var k = i - 1usize
                                while k >= l {
                                    var mm = 1usize
                                    while mm <= k {
                                        swp(m.cov, ij - k + mm, ij + mm)
                                        mm += 1usize
                                    }
                                    swp(m.a, k, k + 1usize)
                                    swp(m.b, k, k + 1usize)
                                    swp(m.dl, k, k + 1usize)
                                    let tm = m.infi[k]
                                    m.infi[k] = m.infi[k + 1usize]
                                    m.infi[k + 1usize] = tm
                                    ij = ij - k
                                    k -= 1usize
                                }
                                swapped = true
                            }
                            l += 1usize
                        }
                        done = true
                    } else {
                        m.cov[ii + jj] = 0.0f64
                        jj -= 1usize
                    }
                }
                ii = ii + i
                m.y[i] = 0.0f64
            }
            i += 1usize
        }
    }
    m.nd = nd
}

// the integrand: w holds the nd quasi-random numbers (1-based), answers the value
fn mvvlsb(m: *Mv, n: usize, w: []const f64, r: f64) -> (f64, usize) {
    var value = 1.0f64
    var infa = 0i64
    var infb = 0i64
    var nd = 0usize
    var ij = 0usize
    var ai = 0.0f64
    var bi = 0.0f64
    var i = 1usize
    while i <= n {
        var sum = m.dl[i]
        var j = 1usize
        while j < i {
            ij += 1usize
            if j <= nd { sum = sum + m.cov[ij] * m.y[j] }
            j += 1usize
        }
        if m.infi[i] != 0i64 {
            if infa == 1i64 {
                let t = r * m.a[i] - sum
                if t > ai { ai = t }
            } else {
                ai = r * m.a[i] - sum
                infa = 1i64
            }
        }
        if m.infi[i] != 1i64 {
            if infb == 1i64 {
                let t = r * m.b[i] - sum
                if t < bi { bi = t }
            } else {
                bi = r * m.b[i] - sum
                infb = 1i64
            }
        }
        ij += 1usize
        var go = i == n
        if !go { go = m.cov[ij + nd + 2usize] > 0.0f64 }
        if go {
            let (di, ei) = mvlims(ai, bi, infa + infa + infb - 1i64)
            if di >= ei { ret (0.0f64, nd) }
            value = value * (ei - di)
            nd += 1usize
            if i < n { m.y[nd] = mvphnv(di + w[nd] * (ei - di)) }
            infa = 0i64
            infb = 0i64
        }
        i += 1usize
    }
    ret (value, nd)
}

fn mvchnv(n: i64, p: f64) -> f64 { ret math.sqrt[f64](nm.qchisq(p, f64(n), false, false)) }

// MVSUBR: x holds 1-based quasi-random numbers
fn mvsubr(m: *Mv, n: usize, w: []const f64) -> f64 {
    if m.nu <= 0i64 {
        let (v, nd) = mvvlsb(m, n + 1usize, w, 1.0f64)
        ret v
    }
    let r = mvchnv(m.nu, w[n]) / m.snu
    let (v, nd) = mvvlsb(m, n, w, r)
    ret v
}

// the special cases; answers (value, error, handled)
fn mvspcl(m: *Mv) -> (f64, f64, bool) {
    var vl = 0.0f64
    var er = 1.0f64
    if m.inform > 0i64 { ret (vl, er, true) }
    if m.nd == 0usize { ret (1.0f64, 0.0f64, true) }
    if m.nd == 1usize && (m.nu < 1i64 || math.abs[f64](m.dl[1usize]) == 0.0f64) {
        vl = 1.0f64
        if m.infi[1usize] != 1i64 { vl = mvstdt(m.nu, m.b[1usize] - m.dl[1usize]) }
        if m.infi[1usize] != 0i64 { vl = vl - mvstdt(m.nu, m.a[1usize] - m.dl[1usize]) }
        if vl < 0.0f64 { vl = 0.0f64 }
        m.nd = 0usize
        ret (vl, 2.0e-16f64, true)
    }
    if m.nd == 2usize && (m.nu < 1i64 || math.abs[f64](m.dl[1usize]) + math.abs[f64](m.dl[2usize]) == 0.0f64) {
        if m.infi[1usize] != 0i64 { m.a[1usize] = m.a[1usize] - m.dl[1usize] }
        if m.infi[1usize] != 1i64 { m.b[1usize] = m.b[1usize] - m.dl[1usize] }
        if m.infi[2usize] != 0i64 { m.a[2usize] = m.a[2usize] - m.dl[2usize] }
        if m.infi[2usize] != 1i64 { m.b[2usize] = m.b[2usize] - m.dl[2usize] }
        if math.abs[f64](m.cov[3usize]) > 0.0f64 {
            let r = math.sqrt[f64](1.0f64 + m.cov[2usize] * m.cov[2usize])
            if m.infi[2usize] != 0i64 { m.a[2usize] = m.a[2usize] / r }
            if m.infi[2usize] != 1i64 { m.b[2usize] = m.b[2usize] / r }
            m.cov[2usize] = m.cov[2usize] / r
            vl = mvbvt(m.nu, m.a[1usize], m.a[2usize], m.b[1usize], m.b[2usize], m.infi[1usize], m.infi[2usize], m.cov[2usize])
            er = 1.0e-15f64
        } else {
            if m.infi[1usize] != 0i64 {
                if m.infi[2usize] != 0i64 {
                    if m.a[2usize] > m.a[1usize] { m.a[1usize] = m.a[2usize] }
                }
            } else {
                if m.infi[2usize] != 0i64 { m.a[1usize] = m.a[2usize] }
            }
            if m.infi[1usize] != 1i64 {
                if m.infi[2usize] != 1i64 {
                    if m.b[2usize] < m.b[1usize] { m.b[1usize] = m.b[2usize] }
                }
            } else {
                if m.infi[2usize] != 1i64 { m.b[1usize] = m.b[2usize] }
            }
            if m.infi[1usize] != m.infi[2usize] { m.infi[1usize] = 2i64 }
            vl = 1.0f64
            if m.infi[1usize] != 1i64 { vl = mvstdt(m.nu, m.b[1usize]) }
            if m.infi[1usize] != 0i64 { vl = vl - mvstdt(m.nu, m.a[1usize]) }
            if vl < 0.0f64 { vl = 0.0f64 }
            er = 2.0e-16f64
        }
        m.nd = 0usize
        ret (vl, er, true)
    }
    if m.nu > 0i64 { m.snu = math.sqrt[f64](f64(m.nu)) } else { m.nd -= 1usize }
    ret (vl, er, false)
}

type Lat = struct { p: [28]i64, c: [2800]i64, loaded: bool }

// the lattice parameters: p[i] prime of row i, c[i * 100 + k] the generator k (1-based)
fn load_lattice(lat: *Lat) {
    let text = tables.lattice()
    var row = 0usize
    var col = 0usize
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 32u8 || text[i] == 124u8 {
            if i > start {
                let (v, e) = str.parse_i64(text[start..i])
                if col == 0usize { lat.p[row] = v } else { lat.c[row * 100usize + col] = v }
                col += 1usize
            }
            if i == text.len || text[i] == 124u8 {
                row += 1usize
                col = 0usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    lat.loaded = true
}

type Res = struct { value: f64, abserr: f64, inform: i64, used: i64 }

// MVKBRV with one integrand: the randomised Korobov rule on ndim variables
fn mvkbrv(a: *mem.Arena, g: *rng.Rng, lat: *const Lat, m: *Mv, ndim: usize, maxvls: i64, abseps: f64, releps: f64) -> (Res, err) {
    var res: Res = zero
    let (x, e1) = mem.alloc[f64](a, ndim + 2usize)
    let (r, e2) = mem.alloc[f64](a, ndim + 2usize)
    let (vk, e3) = mem.alloc[f64](a, ndim + 2usize)
    let (pr, e4) = mem.alloc[usize](a, ndim + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (res, e1) }
    let minsmp = 8i64
    let plim = 28usize
    let klim = 100usize
    var inform = 1i64
    var intvls = 0i64
    var varprd = 0.0f64
    var finest = 0.0f64
    var varest = 0.0f64
    var abserr = 0.0f64
    // MINVLS = 0: the first rule
    var samps = minsmp
    var np = 1usize
    var i = 0usize
    var found = false
    var lo = ndim
    if lo > 10usize { lo = 10usize }
    i = lo
    while i <= plim {
        np = i
        if 0i64 < 2i64 * samps * lat.p[i - 1usize] {
            found = true
            break
        }
        i += 1usize
    }
    if !found {
        samps = 0i64 / (2i64 * lat.p[np - 1usize])
        if samps < minsmp { samps = minsmp }
    }
    while true {
        let prime = lat.p[np - 1usize]
        vk[1usize] = 1.0f64 / f64(prime)
        var k = 1i64
        i = 2usize
        while i <= ndim {
            if i <= klim {
                var cc = ndim - 1usize
                if cc > klim - 1usize { cc = klim - 1usize }
                let prod = f64(lat.c[(np - 1usize) * 100usize + cc]) * f64(k)
                k = i64(prod - math.floor[f64](prod / f64(prime)) * f64(prime))
                vk[i] = f64(k) * vk[1usize]
            } else {
                var t = f64(i64(f64(prime) * math.pow[f64](2.0f64, f64(i - klim) / f64(ndim - klim + 1usize))))
                t = t / f64(prime)
                vk[i] = t - math.floor[f64](t)
            }
            i += 1usize
        }
        var finval = 0.0f64
        var varsqr = 0.0f64
        var s = 1i64
        while s <= samps {
            // MVKRSV
            var values = 0.0f64
            var j = 1usize
            while j <= ndim {
                r[j] = rng.unif(g)
                if j < klim {
                    let jp = usize(1.0f64 + f64(j) * r[j])
                    if jp < j { pr[j] = pr[jp] }
                    pr[jp] = j
                } else { pr[j] = j }
                j += 1usize
            }
            var kk = 1i64
            while kk <= prime {
                j = 1usize
                while j <= ndim {
                    r[j] = r[j] + vk[pr[j]]
                    if r[j] > 1.0f64 { r[j] = r[j] - 1.0f64 }
                    x[j] = math.abs[f64](2.0f64 * r[j] - 1.0f64)
                    j += 1usize
                }
                let f1 = mvsubr(m, ndim, x)
                values = values + (f1 - values) / f64(2i64 * kk - 1i64)
                j = 1usize
                while j <= ndim {
                    x[j] = 1.0f64 - x[j]
                    j += 1usize
                }
                let f2 = mvsubr(m, ndim, x)
                values = values + (f2 - values) / f64(2i64 * kk)
                kk += 1i64
            }
            let difint = (values - finval) / f64(s)
            finval = finval + difint
            varsqr = f64(s - 2i64) * varsqr / f64(s) + difint * difint
            s += 1i64
        }
        intvls = intvls + 2i64 * samps * prime
        varprd = varest * varsqr
        finest = finest + (finval - finest) / (1.0f64 + varprd)
        if varsqr > 0.0f64 { varest = (1.0f64 + varprd) / varsqr }
        abserr = 7.0f64 * math.sqrt[f64](varsqr / (1.0f64 + varprd)) / 2.0f64
        var tol = math.abs[f64](finest) * releps
        if abseps > tol { tol = abseps }
        if abserr > tol {
            if np < plim { np += 1usize } else {
                samps = 3i64 * samps / 2i64
                let rest = (maxvls - intvls) / (2i64 * lat.p[np - 1usize])
                if rest < samps { samps = rest }
                if samps < minsmp { samps = minsmp }
            }
            if intvls + 2i64 * samps * lat.p[np - 1usize] <= maxvls { continue }
        } else { inform = 0i64 }
        break
    }
    res.value = finest
    res.abserr = abserr
    res.inform = inform
    res.used = intvls
    ret (res, ok)
}

// mvtdst: lower, upper, delta (n), infin (n: -1 none, 0 upper only, 1 lower only, 2 both), correl (n (n - 1) / 2, row by row), nu < 1 for the normal
fn mvtdst(a: *mem.Arena, g: *rng.Rng, lat: *const Lat, n: usize, nu: i64, lower: []const f64, upper: []const f64, infin: []const i64, correl: []const f64, delta: []const f64, maxpts: i64, abseps: f64, releps: f64) -> (Res, err) {
    var res: Res = zero
    if n > 1000usize || n < 1usize {
        res.value = 0.0f64
        res.abserr = 1.0f64
        res.inform = 2i64
        ret (res, ok)
    }
    let (infi, e1) = mem.alloc[i64](a, n + 2usize)
    let (aa, e2) = mem.alloc[f64](a, n + 2usize)
    let (bb, e3) = mem.alloc[f64](a, n + 2usize)
    let (dl, e4) = mem.alloc[f64](a, n + 2usize)
    let (y, e5) = mem.alloc[f64](a, n + 2usize)
    let (cov, e6) = mem.alloc[f64](a, n * (n + 1usize) / 2usize + n + 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (res, e1) }
    var i = 0usize
    while i < n + 2usize {
        infi[i] = 0i64
        aa[i] = 0.0f64
        bb[i] = 0.0f64
        dl[i] = 0.0f64
        y[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * (n + 1usize) / 2usize + n + 8usize {
        cov[i] = 0.0f64
        i += 1usize
    }
    var m = Mv { nu: nu, snu: 0.0f64, nd: 0usize, infi: infi, a: aa, b: bb, dl: dl, cov: cov, y: y, inform: 0i64 }
    mvsort(&m, n, lower, upper, delta, correl, infin)
    let (vl, er, handled) = mvspcl(&m)
    if m.inform != 0i64 || handled {
        res.value = vl
        res.abserr = er
        res.inform = m.inform
        ret (res, ok)
    }
    let (r2, ke) = mvkbrv(a, g, lat, &m, m.nd, maxpts, abseps, releps)
    ret (r2, ke)
}
