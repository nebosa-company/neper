// R stats::density (old.coords = FALSE, R >= 4.4) with the Gaussian kernel: bw.nrd0 or a given bandwidth, cut = 3, linear binning of the data on a 2 * 512 grid, circular convolution with
// the kernel, and linear interpolation to n.user points. The convolution is the direct sum, not an FFT, so it agrees with R to about 1e-14 relative.
//
// Not here: weights, the other kernels and bandwidth rules, adjust, the from and to arguments and the binned-density object.

use e.math
use e.mem

// the FFT grid size density picks for n.user points: 512, or the next power of two above it
fn grid_for(nout: usize) -> usize {
    var g = 512usize
    while g < nout { g *= 2usize }
    ret g
}

// bw.nrd0: 0.9 min(sd, IQR / 1.34) n^(-1/5), the IQR from the type-7 quantiles of the sorted x
fn bw_nrd0(x: []const f64, s: []const f64) -> f64 {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        ss += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (n - 1.0f64))
    let q1 = quant7(s, 0.25f64)
    let q3 = quant7(s, 0.75f64)
    var lo = sd
    let h = (q3 - q1) / 1.34f64
    if h < lo { lo = h }
    if lo == 0.0f64 { lo = sd }
    if lo == 0.0f64 { lo = math.abs[f64](x[0usize]) }
    if lo == 0.0f64 { lo = 1.0f64 }
    ret 0.9f64 * lo * math.pow[f64](n, 0.0f64 - 0.2f64)
}

fn quant7(s: []const f64, p: f64) -> f64 {
    let fuzz = 4.0f64 * 2.220446049250313e-16f64
    let idx = f64(s.len - 1usize) * p
    let lo = math.floor[f64](idx + fuzz)
    var h = idx - lo
    if math.abs[f64](h) < fuzz { h = 0.0f64 }
    let l = usize(lo)
    if h == 0.0f64 || l + 1usize >= s.len { ret s[l] }
    ret (1.0f64 - h) * s[l] + h * s[l + 1usize]
}

// density(x, bw, n = nout)$y at the nout evenly spaced points from min - 3 bw to max + 3 bw into out; sorted is x sorted ascending; scratch holds 5 * grid_for(nout) values
fn density_gauss(x: []const f64, sorted: []const f64, bw: f64, nout: usize, out: []f64, scratch: []f64) {
    let n = grid_for(nout)
    let n2 = 2usize * n
    let from = sorted[0usize] - 3.0f64 * bw
    let to = sorted[sorted.len - 1usize] + 3.0f64 * bw
    let lo = from - 4.0f64 * bw
    let up = to + 4.0f64 * bw
    let y = scratch[0usize..n2]
    let kern = scratch[n2..2usize * n2]
    var i = 0usize
    while i < n2 {
        y[i] = 0.0f64
        i += 1usize
    }
    let xdelta = (up - lo) / f64(n - 1usize)
    let ixmax = n - 2usize
    i = 0usize
    while i < x.len {
        let xpos = (x[i] - lo) / xdelta
        let ixf = math.floor[f64](xpos)
        let fx = xpos - ixf
        if ixf >= 0.0f64 && ixf <= f64(ixmax) {
            let ix = usize(ixf)
            y[ix] += 1.0f64 - fx
            y[ix + 1usize] += fx
        } else if ixf == 0.0f64 - 1.0f64 {
            y[0usize] += fx
        } else if ixf == f64(ixmax + 1usize) {
            y[ixmax + 1usize] += 1.0f64 - fx
        }
        i += 1usize
    }
    let total = f64(x.len)
    // the kernel at the circular offsets, symmetric about zero
    let step = xdelta
    i = 0usize
    while i < n2 {
        var off = f64(i)
        if i > n { off = f64(n2 - i) }
        let d = off * step
        kern[i] = math.exp[f64](0.0f64 - d * d / (2.0f64 * bw * bw)) / (bw * math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64))
        i += 1usize
    }
    // the first n circular convolution values at the grid, scaled like R (1 / total mass in y is 1)
    let dens = scratch[2usize * n2..2usize * n2 + n]
    var j = 0usize
    while j < n {
        var s = 0.0f64
        var k = 0usize
        while k < n2 {
            var idx = k + n2 - j
            if idx >= n2 { idx -= n2 }
            s += y[k] * kern[idx]
            k += 1usize
        }
        var v = s / f64(total)
        if v < 0.0f64 { v = 0.0f64 }
        dens[j] = v
        j += 1usize
    }
    var q = 0usize
    while q < nout {
        let xv = from + (to - from) * f64(q) / f64(nout - 1usize)
        let pos = (xv - lo) / xdelta
        var il = usize(math.floor[f64](pos))
        if il >= n - 1usize { il = n - 2usize }
        let t = pos - f64(il)
        out[q] = (1.0f64 - t) * dens[il] + t * dens[il + 1usize]
        q += 1usize
    }
}
