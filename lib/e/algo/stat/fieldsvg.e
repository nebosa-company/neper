// R fields: vgram (empirical variogram, covariogram and correlogram of all pairs, Euclidean or great-circle distance in miles) and its stats.bin summaries.
// answer() decodes one oracle case: args = [op, idx, type, lonlat, n, nbins, dmax, nbreaks, x (n*2 row major), y (n), breaks]; type 0 variogram, 1 covariogram,
// 2 correlogram; nbins is stats.bin's N (equal breaks over the range of d), nbreaks > 0 gives the breaks; dmax 0 means none. op 0 d[idx]  1 vgram[idx]  2 number of
// pairs kept  3 bin centre[idx]  4..11 stats of bin idx: N, mean, sd, min, Q1, median, Q3, max.
//
// Not here: id and d supplied by the caller, prettyBins, vgram.matrix and the plots.

use e.math
use e.mem

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

fn pi_value() -> f64 { ret 3.14159265358979323846264338327950288f64 }

// rdist.earth.vec: haversine in miles, R = 3963.34
fn earth(lon1: f64, lat1: f64, lon2: f64, lat2: f64) -> f64 {
    let k = pi_value() / 180.0f64
    let a1 = lon1 * k
    let b1 = lat1 * k
    let a2 = lon2 * k
    let b2 = lat2 * k
    let lo = (a2 - a1) * 0.5f64
    let la = (b2 - b1) * 0.5f64
    let s = math.sin[f64](la) * math.sin[f64](la) + math.cos[f64](b1) * math.cos[f64](b2) * math.sin[f64](lo) * math.sin[f64](lo)
    ret 2.0f64 * math.atan2[f64](math.sqrt[f64](s), math.sqrt[f64](1.0f64 - s)) * 3963.34f64
}

fn quant7(v: []const f64, n: usize, p: f64) -> f64 {
    let index = f64(n - 1usize) * p
    let lo = usize(math.floor[f64](index))
    var hi = lo
    if lo + 1usize < n { hi = lo + 1usize }
    let h = index - f64(lo)
    if h == 0.0f64 || v[hi] == v[lo] { ret v[lo] }
    ret (1.0f64 - h) * v[lo] + h * v[hi]
}

fn answer(a: *mem.Arena, g: []const f64) -> f64 {
    let op = usize(g[0usize])
    let idx = usize(g[1usize])
    let kind = usize(g[2usize])
    let lonlat = usize(g[3usize])
    let n = usize(g[4usize])
    let nbins = usize(g[5usize])
    let dmax0 = g[6usize]
    let nbr = usize(g[7usize])
    let xb = 8usize
    let yb = xb + 2usize * n
    let bb = yb + n
    let np = n * (n - 1usize) / 2usize
    let (dist, e1) = mem.alloc[f64](a, np + 1usize)
    if e1 != ok { ret nan_value() }
    let (vg, e2) = mem.alloc[f64](a, np + 1usize)
    if e2 != ok { ret nan_value() }
    let (yc, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret nan_value() }
    var mean = 0.0f64
    var sd = 1.0f64
    var i = 0usize
    while i < n {
        yc[i] = g[yb + i]
        i += 1usize
    }
    if kind == 2usize {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += yc[i]
            i += 1usize
        }
        let mu = s / f64(n)
        var ss = 0.0f64
        i = 0usize
        while i < n {
            ss += (yc[i] - mu) * (yc[i] - mu)
            i += 1usize
        }
        sd = math.sqrt[f64](ss / f64(n - 1usize))
        i = 0usize
        while i < n {
            yc[i] = yc[i] * (1.0f64 / sd)
            i += 1usize
        }
    }
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        s2 += yc[i]
        i += 1usize
    }
    mean = s2 / f64(n)
    i = 0usize
    while i < n {
        yc[i] = yc[i] - mean
        i += 1usize
    }
    // pairs (i > j), j outer, i inner
    var k = 0usize
    var j = 0usize
    while j < n {
        i = j + 1usize
        while i < n {
            if lonlat == 1usize {
                dist[k] = earth(g[xb + 2usize * i], g[xb + 2usize * i + 1usize], g[xb + 2usize * j], g[xb + 2usize * j + 1usize])
            } else {
                let dx = g[xb + 2usize * i] - g[xb + 2usize * j]
                let dy = g[xb + 2usize * i + 1usize] - g[xb + 2usize * j + 1usize]
                dist[k] = math.sqrt[f64](dx * dx + dy * dy)
            }
            if kind == 0usize {
                let t = yc[i] - yc[j]
                vg[k] = 0.5f64 * (t * t)
            } else {
                vg[k] = yc[i] * yc[j]
            }
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    // stable insertion sort by distance
    k = 1usize
    while k < np {
        let dv = dist[k]
        let vv = vg[k]
        var q = k
        while q > 0usize && dist[q - 1usize] > dv {
            dist[q] = dist[q - 1usize]
            vg[q] = vg[q - 1usize]
            q -= 1usize
        }
        dist[q] = dv
        vg[q] = vv
        k += 1usize
    }
    var dmax = dmax0
    if dmax0 == 0.0f64 { dmax = dist[np - 1usize] }
    var kept = 0usize
    k = 0usize
    while k < np {
        if dist[k] <= dmax {
            dist[kept] = dist[k]
            vg[kept] = vg[k]
            kept += 1usize
        }
        k += 1usize
    }
    if op == 0usize { ret dist[idx] }
    if op == 1usize { ret vg[idx] }
    if op == 2usize { ret f64(kept) }
    // breaks
    var nb = nbr
    if nbr == 0usize { nb = nbins }
    let (br, e4) = mem.alloc[f64](a, nb + 1usize)
    if e4 != ok { ret nan_value() }
    if nbr > 0usize {
        k = 0usize
        while k < nb {
            br[k] = g[bb + k]
            k += 1usize
        }
    } else {
        let lo = dist[0usize]
        let hi = dist[kept - 1usize]
        let by = (hi - lo) / f64(nb - 1usize)
        br[0usize] = lo
        k = 1usize
        while k + 1usize < nb {
            br[k] = lo + f64(k) * by
            k += 1usize
        }
        br[nb - 1usize] = hi
    }
    if op == 3usize { ret (br[idx] + br[idx + 1usize]) / 2.0f64 }
    // the values of bin idx, sorted
    let (vals, e5) = mem.alloc[f64](a, kept + 1usize)
    if e5 != ok { ret nan_value() }
    var cnt = 0usize
    k = 0usize
    while k < kept {
        var inside = dist[k] <= br[idx + 1usize] && dist[k] > br[idx]
        if idx == 0usize { inside = dist[k] <= br[1usize] && dist[k] >= br[0usize] }
        if inside {
            var q = cnt
            while q > 0usize && vals[q - 1usize] > vg[k] {
                vals[q] = vals[q - 1usize]
                q -= 1usize
            }
            vals[q] = vg[k]
            cnt += 1usize
        }
        k += 1usize
    }
    if op == 4usize { ret f64(cnt) }
    if op == 7usize { ret vals[0usize] }
    if op == 11usize { ret vals[cnt - 1usize] }
    if op == 8usize { ret quant7(vals, cnt, 0.25f64) }
    if op == 9usize { ret quant7(vals, cnt, 0.5f64) }
    if op == 10usize { ret quant7(vals, cnt, 0.75f64) }
    var sm = 0.0f64
    k = 0usize
    while k < cnt {
        sm += vals[k]
        k += 1usize
    }
    let mu = sm / f64(cnt)
    if op == 5usize { ret mu }
    var ss = 0.0f64
    k = 0usize
    while k < cnt {
        ss += (vals[k] - mu) * (vals[k] - mu)
        k += 1usize
    }
    ret math.sqrt[f64](ss / f64(cnt - 1usize))
}
