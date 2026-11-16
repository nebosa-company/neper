// R hdrcde: hdr for a sample with a given bandwidth, on e.algo.stat.rdensity (the default 512-point density): the density height falpha at the alpha-quantile of the
// density at the sample points, and the ends of the highest density regions where the piecewise-linear density crosses that height.
//
// Not here: the bandwidth selector hdrbw and the Box-Cox transform, hdr.den's plotting, cde, hdr.cde, the mode estimates and the all-roots search by uniroot
// (the roots here are refined by bisection where R uses uniroot, which is good to about 1e-4).

use e.algo.stat.rdensity as rd
use e.math
use e.mem

// the density's evaluation grid and heights for the sample x with bandwidth bw into xs and ys (512 values each); sorted is x ascending; scratch holds 2560 values
fn den_grid(x: []const f64, sorted: []const f64, bw: f64, xs: []f64, ys: []f64, scratch: []f64) {
    let from = sorted[0usize] - 3.0f64 * bw
    let to = sorted[sorted.len - 1usize] + 3.0f64 * bw
    rd.density_gauss(x, sorted, bw, 512usize, ys, scratch)
    var i = 0usize
    while i < 512usize {
        xs[i] = from + (to - from) * f64(i) / 511.0f64
        i += 1usize
    }
}

// approx(xs, ys, v, rule = 2)
fn approx2(xs: []const f64, ys: []const f64, v: f64) -> f64 {
    let n = xs.len
    if v <= xs[0usize] { ret ys[0usize] }
    if v >= xs[n - 1usize] { ret ys[n - 1usize] }
    var i = 0usize
    while i + 2usize < n && xs[i + 1usize] <= v { i += 1usize }
    ret ys[i] + (ys[i + 1usize] - ys[i]) * (v - xs[i]) / (xs[i + 1usize] - xs[i])
}

// the alpha-quantile (type 7) of the density heights at the sample points; sorted_fx is scratch of x.len values
fn falpha_of(x: []const f64, xs: []const f64, ys: []const f64, alpha: f64, sorted_fx: []f64) -> f64 {
    var i = 0usize
    while i < x.len {
        sorted_fx[i] = approx2(xs, ys, x[i])
        i += 1usize
    }
    i = 1usize
    while i < x.len {
        let t = sorted_fx[i]
        var j = i
        while j > 0usize && sorted_fx[j - 1usize] > t {
            sorted_fx[j] = sorted_fx[j - 1usize]
            j -= 1usize
        }
        sorted_fx[j] = t
        i += 1usize
    }
    ret rd.quant7(sorted_fx, alpha)
}

// hdr.ends: the roots of the linearly interpolated density minus falpha that all_roots finds (a sign change between neighbours of 101 equally spaced points, refined here
// by bisection where R uses uniroot), plus the grid end when the density is above falpha just inside it; written to out, returns how many
fn hdr_ends(xs: []const f64, ys: []const f64, falpha: f64, out: []f64) -> usize {
    let n = xs.len
    var cnt = 0usize
    let lo = xs[0usize]
    let hi = xs[n - 1usize]
    var prev = approx2(xs, ys, lo) - falpha
    if prev == 0.0f64 {
        out[cnt] = lo
        cnt += 1usize
    }
    var i = 1usize
    while i <= 100usize {
        let x1 = lo + (hi - lo) * f64(i) / 100.0f64
        let cur = approx2(xs, ys, x1) - falpha
        if cur == 0.0f64 && cnt < out.len {
            out[cnt] = x1
            cnt += 1usize
        } else if prev * cur < 0.0f64 && cnt < out.len {
            var a = lo + (hi - lo) * f64(i - 1usize) / 100.0f64
            var b = x1
            var fa = prev
            var it = 0usize
            while it < 200usize {
                let mid = 0.5f64 * (a + b)
                let fm = approx2(xs, ys, mid) - falpha
                if fm == 0.0f64 {
                    a = mid
                    b = mid
                    break
                }
                if fa * fm < 0.0f64 { b = mid } else {
                    a = mid
                    fa = fm
                }
                it += 1usize
            }
            out[cnt] = 0.5f64 * (a + b)
            cnt += 1usize
        }
        prev = cur
        i += 1usize
    }
    // roots from grid points come out in order already, except an exact zero found after a later crossing is impossible
    if cnt == 0usize {
        out[0usize] = lo
        out[1usize] = hi
        ret 2usize
    }
    var total = cnt
    if approx2(xs, ys, 0.5f64 * (out[0usize] + lo)) - falpha > 0.0f64 && total < out.len {
        var j = total
        while j > 0usize {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[0usize] = lo
        total += 1usize
    }
    if approx2(xs, ys, 0.5f64 * (out[total - 1usize] + hi)) - falpha > 0.0f64 && total < out.len {
        out[total] = hi
        total += 1usize
    }
    ret total
}
