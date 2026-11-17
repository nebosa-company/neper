// R geosphere: the spherical and ellipsoidal distances that need no geodesic series, and the rhumb-line (loxodrome) formulas.
// Degrees in, metres out. Karney's distGeo, bearing, destPoint, midPoint, areas and gcIntermediate are not here.

use e.math

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn rad(x: f64) -> f64 { ret x * pi() / 180.0f64 }
fn eps() -> f64 { ret 1.4901161193847656e-8f64 }

fn fmod(x: f64, m: f64) -> f64 { ret x - m * math.floor[f64](x / m) }

fn dist_haversine(lon1: f64, lat1: f64, lon2: f64, lat2: f64, r: f64) -> f64 {
    let p1 = rad(lat1)
    let p2 = rad(lat2)
    let sa = math.sin[f64]((p2 - p1) / 2.0f64)
    let sb = math.sin[f64]((rad(lon2) - rad(lon1)) / 2.0f64)
    var a = sa * sa + math.cos[f64](p1) * math.cos[f64](p2) * sb * sb
    if a > 1.0f64 { a = 1.0f64 }
    ret 2.0f64 * math.atan2[f64](math.sqrt[f64](a), math.sqrt[f64](1.0f64 - a)) * r
}

fn dist_vincenty_sphere(lon1: f64, lat1: f64, lon2: f64, lat2: f64, r: f64) -> f64 {
    let a1 = rad(lat1)
    let a2 = rad(lat2)
    let dn = rad(lon1) - rad(lon2)
    let t1 = math.cos[f64](a2) * math.sin[f64](dn)
    let t2 = math.cos[f64](a1) * math.sin[f64](a2) - math.sin[f64](a1) * math.cos[f64](a2) * math.cos[f64](dn)
    let x = math.sqrt[f64](t1 * t1 + t2 * t2)
    let y = math.sin[f64](a1) * math.sin[f64](a2) + math.cos[f64](a1) * math.cos[f64](a2) * math.cos[f64](dn)
    ret r * math.atan2[f64](x, y)
}

fn dist_cosine(lon1: f64, lat1: f64, lon2: f64, lat2: f64, r: f64) -> f64 {
    if math.abs[f64](lon1 - lon2) < eps() && math.abs[f64](lat1 - lat2) < eps() { ret 0.0f64 }
    ret math.acos[f64](math.sin[f64](rad(lat1)) * math.sin[f64](rad(lat2)) + math.cos[f64](rad(lat1)) * math.cos[f64](rad(lat2)) * math.cos[f64](rad(lon1) - rad(lon2))) * r
}

fn dist_meeus(lon1: f64, lat1: f64, lon2: f64, lat2: f64, a: f64, f: f64) -> f64 {
    let ff = (rad(lat1) + rad(lat2)) / 2.0f64
    let g = (rad(lat1) - rad(lat2)) / 2.0f64
    let l = (rad(lon1) - rad(lon2)) / 2.0f64
    let sg = math.sin[f64](g) * math.sin[f64](g)
    let cg = math.cos[f64](g) * math.cos[f64](g)
    let sf = math.sin[f64](ff) * math.sin[f64](ff)
    let cf = math.cos[f64](ff) * math.cos[f64](ff)
    let sl = math.sin[f64](l) * math.sin[f64](l)
    let cl = math.cos[f64](l) * math.cos[f64](l)
    let s = sg * cl + cf * sl
    let c = cg * cl + sf * sl
    let w = math.atan[f64](math.sqrt[f64](s / c))
    if w == 0.0f64 { ret 0.0f64 }
    let rr = math.sqrt[f64](s * c) / w
    let d = 2.0f64 * w * a
    let h1 = (3.0f64 * rr - 1.0f64) / (2.0f64 * c)
    let h2 = (3.0f64 * rr + 1.0f64) / (2.0f64 * s)
    ret d * (1.0f64 + f * h1 * sf * cg - f * h2 * cf * sg)
}

// NaN where R answers NA (no convergence in 100 iterations)
fn dist_vincenty_ellipsoid(lon1d: f64, lat1d: f64, lon2d: f64, lat2d: f64, a: f64, b: f64, f: f64) -> f64 {
    let lon1 = rad(lon1d)
    let lat1 = rad(lat1d)
    let lon2 = rad(lon2d)
    let lat2 = rad(lat2d)
    if math.abs[f64](lon1 - lon2) < eps() && math.abs[f64](lat1 - lat2) < eps() { ret 0.0f64 }
    let l = lon2 - lon1
    let u1 = math.atan[f64]((1.0f64 - f) * math.tan[f64](lat1))
    let u2 = math.atan[f64]((1.0f64 - f) * math.tan[f64](lat2))
    let su1 = math.sin[f64](u1)
    let cu1 = math.cos[f64](u1)
    let su2 = math.sin[f64](u2)
    let cu2 = math.cos[f64](u2)
    var lambda = l
    var left = 100i32
    var sin_sigma = 0.0f64
    var cos_sigma = 0.0f64
    var sigma = 0.0f64
    var cos_sq = 0.0f64
    var c2 = 0.0f64
    var go = true
    while go {
        let sl = math.sin[f64](lambda)
        let cl = math.cos[f64](lambda)
        let t = cu1 * su2 - su1 * cu2 * cl
        sin_sigma = math.sqrt[f64]((cu2 * sl) * (cu2 * sl) + t * t)
        cos_sigma = su1 * su2 + cu1 * cu2 * cl
        sigma = math.atan2[f64](sin_sigma, cos_sigma)
        let sin_alpha = cu1 * cu2 * sl / sin_sigma
        cos_sq = 1.0f64 - sin_alpha * sin_alpha
        c2 = cos_sigma - 2.0f64 * su1 * su2 / cos_sq
        if c2 != c2 { c2 = 0.0f64 }
        let cc = f / 16.0f64 * cos_sq * (4.0f64 + f * (4.0f64 - 3.0f64 * cos_sq))
        let prev = lambda
        lambda = l + (1.0f64 - cc) * f * sin_alpha * (sigma + cc * sin_sigma * (c2 + cc * cos_sigma * (0.0f64 - 1.0f64 + 2.0f64 * c2 * c2)))
        left -= 1i32
        go = math.abs[f64](lambda - prev) > 1.0e-12f64 && left > 0i32
    }
    if left == 0i32 { ret 0.0f64 / 0.0f64 }
    let usq = cos_sq * (a * a - b * b) / (b * b)
    let aa = 1.0f64 + usq / 16384.0f64 * (4096.0f64 + usq * (0.0f64 - 768.0f64 + usq * (320.0f64 - 175.0f64 * usq)))
    let bb = usq / 1024.0f64 * (256.0f64 + usq * (0.0f64 - 128.0f64 + usq * (74.0f64 - 47.0f64 * usq)))
    let ds = bb * sin_sigma * (c2 + bb / 4.0f64 * (cos_sigma * (0.0f64 - 1.0f64 + 2.0f64 * c2 * c2) - bb / 6.0f64 * c2 * (0.0f64 - 3.0f64 + 4.0f64 * sin_sigma * sin_sigma) * (0.0f64 - 3.0f64 + 4.0f64 * c2 * c2)))
    ret b * aa * (sigma - ds)
}

fn bearing_rhumb(lon1d: f64, lat1d: f64, lon2d: f64, lat2d: f64) -> f64 {
    if lon1d == lon2d && lat1d == lat2d { ret 0.0f64 / 0.0f64 }
    let lat1 = rad(lat1d)
    let lat2 = rad(lat2d)
    var dlon = rad(lon2d) - rad(lon1d)
    let dphi = math.log[f64](math.tan[f64](lat2 / 2.0f64 + pi() / 4.0f64) / math.tan[f64](lat1 / 2.0f64 + pi() / 4.0f64))
    if math.abs[f64](dlon) > pi() {
        // the package re-tests the sign after the first shift, so a positive difference ends unchanged
        if dlon <= 0.0f64 { dlon = 2.0f64 * pi() + dlon }
    }
    let b = math.atan2[f64](dlon, dphi) / (pi() / 180.0f64)
    ret fmod(b + 360.0f64, 360.0f64)
}

fn dist_rhumb(lon1d: f64, lat1d: f64, lon2d: f64, lat2d: f64, r: f64) -> f64 {
    let lat1 = rad(lat1d)
    let lat2 = rad(lat2d)
    let dlat = lat2 - lat1
    var dlon = math.abs[f64](rad(lon2d) - rad(lon1d))
    let dphi = math.log[f64](math.tan[f64](lat2 / 2.0f64 + pi() / 4.0f64) / math.tan[f64](lat1 / 2.0f64 + pi() / 4.0f64))
    var q = math.cos[f64](lat1)
    if math.abs[f64](dlat) > 1.0e-10f64 { q = dlat / dphi }
    if dlon > pi() { dlon = 2.0f64 * pi() - dlon }
    ret math.sqrt[f64](dlat * dlat + q * q * dlon * dlon) * r
}

fn dest_point_rhumb(lon1d: f64, lat1d: f64, brg: f64, dist: f64, r: f64) -> (f64, f64) {
    let d = dist / r
    let b = rad(brg)
    let lon1 = rad(lon1d)
    let lat1 = rad(lat1d)
    var lat2 = lat1 + d * math.cos[f64](b)
    let dlat = lat2 - lat1
    let dphi = math.log[f64](math.tan[f64](lat2 / 2.0f64 + pi() / 4.0f64) / math.tan[f64](lat1 / 2.0f64 + pi() / 4.0f64))
    var q = math.cos[f64](lat1)
    if math.abs[f64](dlat) > 1.0e-10f64 { q = dlat / dphi }
    let dlon = d * math.sin[f64](b) / q
    if math.abs[f64](lat2) > pi() / 2.0f64 { lat2 = pi() - lat2 }
    let lon2 = fmod(lon1 + dlon + pi(), 2.0f64 * pi()) - pi()
    ret (lon2 / (pi() / 180.0f64), lat2 / (pi() / 180.0f64))
}

// destPoint(p, b, d, r = r): the spherical destination from (lon1, lat1) in degrees along bearing b degrees for distance d on a sphere of radius r
fn dest_point_sphere(lon1d: f64, lat1d: f64, bd: f64, d: f64, r: f64) -> (f64, f64) {
    let lon1 = rad(lon1d)
    let lat1 = rad(lat1d)
    let b = rad(bd)
    let lat2 = math.asin(math.sin(lat1) * math.cos(d / r) + math.cos(lat1) * math.sin(d / r) * math.cos(b))
    var lon2 = lon1 + math.atan2[f64](math.sin(b) * math.sin(d / r) * math.cos(lat1), math.cos(d / r) - math.sin(lat1) * math.sin(lat2))
    lon2 = fmod(lon2 + pi(), 2.0f64 * pi()) - pi()
    ret (lon2 * 180.0f64 / pi(), lat2 * 180.0f64 / pi())
}

// gcIntermediate(p1, p2, n): the k-th (0-based) of the n equally spaced points on the great circle between the two points (not antipodal, not equal), in degrees
fn gc_intermediate(lon1d: f64, lat1d: f64, lon2d: f64, lat2d: f64, n: usize, k: usize) -> (f64, f64) {
    let lon1 = rad(lon1d)
    let lat1 = rad(lat1d)
    let lon2 = rad(lon2d)
    let lat2 = rad(lat2d)
    let d = dist_cosine(lon1d, lat1d, lon2d, lat2d, 1.0f64)
    let f = f64(k + 1usize) / (f64(n) + 1.0f64)
    let aa = math.sin((1.0f64 - f) * d) / math.sin(d)
    let bb = math.sin(f * d) / math.sin(d)
    let x = aa * math.cos(lat1) * math.cos(lon1) + bb * math.cos(lat2) * math.cos(lon2)
    let y = aa * math.cos(lat1) * math.sin(lon1) + bb * math.cos(lat2) * math.sin(lon2)
    let z = aa * math.sin(lat1) + bb * math.sin(lat2)
    let lat = math.atan2[f64](z, math.sqrt[f64](x * x + y * y))
    let lon = math.atan2[f64](y, x)
    ret (lon * 180.0f64 / pi(), lat * 180.0f64 / pi())
}

// geomean(xy, w): the weighted mean point of the longitudes and latitudes (each averaged as a circular quantity); the weights are normalised to sum one
fn geomean(lon: []const f64, lat: []const f64, w: []const f64) -> (f64, f64) {
    let n = lon.len
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += w[i]
        i += 1usize
    }
    var sx = 0.0f64
    var cx = 0.0f64
    var sy = 0.0f64
    var cy = 0.0f64
    i = 0usize
    while i < n {
        let wi = w[i] / sw
        let x = rad(lon[i] + 180.0f64)
        let y = rad(lat[i])
        sx += math.sin(x) * wi
        cx += math.cos(x) * wi
        sy += math.sin(y) * wi
        cy += math.cos(y) * wi
        i += 1usize
    }
    let nn = f64(n)
    var x = math.atan2[f64](sx / nn, cx / nn)
    x = fmod(x, 2.0f64 * pi()) - pi()
    let y = math.atan2[f64](sy / nn, cy / nn)
    ret (x * 180.0f64 / pi(), y * 180.0f64 / pi())
}
