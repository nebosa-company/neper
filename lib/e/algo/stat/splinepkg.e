// R stats::spline and splinefun for the "fmm" and "natural" methods: the C routines fmm_spline and natural_spline line for line, and spline_eval inside the data range.
//
// Not here: the periodic and monotone methods, extrapolation beyond the data, ties in x and the derivative argument.

// the cubic coefficients b, c, d of n knots (x ascending) by Forsythe, Malcolm and Moler's end conditions
fn fmm_spline(n: usize, x: []const f64, y: []const f64, b: []f64, c: []f64, d: []f64) {
    if n < 2usize { ret }
    if n < 3usize {
        let t = y[1usize] - y[0usize]
        b[0usize] = t / (x[1usize] - x[0usize])
        b[1usize] = b[0usize]
        c[0usize] = 0.0f64
        c[1usize] = 0.0f64
        d[0usize] = 0.0f64
        d[1usize] = 0.0f64
        ret
    }
    let nm1 = n - 1usize
    d[0usize] = x[1usize] - x[0usize]
    c[1usize] = (y[1usize] - y[0usize]) / d[0usize]
    var i = 1usize
    while i < nm1 {
        d[i] = x[i + 1usize] - x[i]
        b[i] = 2.0f64 * (d[i - 1usize] + d[i])
        c[i + 1usize] = (y[i + 1usize] - y[i]) / d[i]
        c[i] = c[i + 1usize] - c[i]
        i += 1usize
    }
    b[0usize] = 0.0f64 - d[0usize]
    b[nm1] = 0.0f64 - d[nm1 - 1usize]
    c[0usize] = 0.0f64
    c[nm1] = 0.0f64
    if n > 3usize {
        c[0usize] = c[2usize] / (x[3usize] - x[1usize]) - c[1usize] / (x[2usize] - x[0usize])
        c[nm1] = c[nm1 - 1usize] / (x[nm1] - x[n - 3usize]) - c[n - 3usize] / (x[nm1 - 1usize] - x[n - 4usize])
        c[0usize] = c[0usize] * d[0usize] * d[0usize] / (x[3usize] - x[0usize])
        c[nm1] = 0.0f64 - c[nm1] * d[nm1 - 1usize] * d[nm1 - 1usize] / (x[nm1] - x[n - 4usize])
    }
    i = 1usize
    while i <= nm1 {
        let t = d[i - 1usize] / b[i - 1usize]
        b[i] = b[i] - t * d[i - 1usize]
        c[i] = c[i] - t * c[i - 1usize]
        i += 1usize
    }
    c[nm1] = c[nm1] / b[nm1]
    i = nm1
    while i > 0usize {
        let k = i - 1usize
        c[k] = (c[k] - d[k] * c[k + 1usize]) / b[k]
        i -= 1usize
    }
    b[nm1] = (y[nm1] - y[n - 2usize]) / d[n - 2usize] + d[n - 2usize] * (c[n - 2usize] + 2.0f64 * c[nm1])
    i = 0usize
    while i < nm1 {
        b[i] = (y[i + 1usize] - y[i]) / d[i] - d[i] * (c[i + 1usize] + 2.0f64 * c[i])
        d[i] = (c[i + 1usize] - c[i]) / d[i]
        c[i] = 3.0f64 * c[i]
        i += 1usize
    }
    c[nm1] = 3.0f64 * c[nm1]
    d[nm1] = d[n - 2usize]
}

// the natural cubic spline coefficients (zero second derivative at both ends)
fn natural_spline(n: usize, x: []const f64, y: []const f64, b: []f64, c: []f64, d: []f64) {
    if n < 2usize { ret }
    if n < 3usize {
        let t = y[1usize] - y[0usize]
        b[0usize] = t / (x[1usize] - x[0usize])
        b[1usize] = b[0usize]
        c[0usize] = 0.0f64
        c[1usize] = 0.0f64
        d[0usize] = 0.0f64
        d[1usize] = 0.0f64
        ret
    }
    let nm1 = n - 1usize
    d[0usize] = x[1usize] - x[0usize]
    c[1usize] = (y[1usize] - y[0usize]) / d[0usize]
    var i = 1usize
    while i < nm1 {
        d[i] = x[i + 1usize] - x[i]
        b[i] = 2.0f64 * (d[i - 1usize] + d[i])
        c[i + 1usize] = (y[i + 1usize] - y[i]) / d[i]
        c[i] = c[i + 1usize] - c[i]
        i += 1usize
    }
    i = 2usize
    while i < nm1 {
        let t = d[i - 1usize] / b[i - 1usize]
        b[i] = b[i] - t * d[i - 1usize]
        c[i] = c[i] - t * c[i - 1usize]
        i += 1usize
    }
    c[nm1 - 1usize] = c[nm1 - 1usize] / b[nm1 - 1usize]
    i = nm1 - 1usize
    while i > 1usize {
        let k = i - 1usize
        c[k] = (c[k] - d[k] * c[k + 1usize]) / b[k]
        i -= 1usize
    }
    c[0usize] = 0.0f64
    c[nm1] = 0.0f64
    b[0usize] = (y[1usize] - y[0usize]) / d[0usize] - d[0usize] * c[1usize]
    c[0usize] = 0.0f64
    d[0usize] = c[1usize] / d[0usize]
    b[nm1] = (y[nm1] - y[nm1 - 1usize]) / d[nm1 - 1usize] + d[nm1 - 1usize] * c[nm1 - 1usize]
    i = 1usize
    while i < nm1 {
        b[i] = (y[i + 1usize] - y[i]) / d[i] - d[i] * (c[i + 1usize] + 2.0f64 * c[i])
        d[i] = (c[i + 1usize] - c[i]) / d[i]
        c[i] = 3.0f64 * c[i]
        i += 1usize
    }
    c[nm1] = 0.0f64
    d[nm1] = 0.0f64
}

// spline_eval at u inside [x[0], x[n - 1]]
fn spline_eval(n: usize, x: []const f64, y: []const f64, b: []const f64, c: []const f64, d: []const f64, u: f64) -> f64 {
    var i = 0usize
    var j = n
    while i + 1usize < j {
        let k = (i + j) / 2usize
        if u < x[k] { j = k } else { i = k }
    }
    let dx = u - x[i]
    ret y[i] + dx * (b[i] + dx * (c[i] + dx * d[i]))
}
