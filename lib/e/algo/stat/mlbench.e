// R mlbench data generators, drawing from the Mersenne-Twister stream in the order R fills its matrices
// (by column): friedman1, friedman2, friedman3, 2dnormals, circle, xor, twonorm and ringnorm. A data set
// is x (n rows by d columns, row-major) and y (the response) or the class codes (1-based).
//
// And cassini, hypercube, peak, shapes, simplex, smiley, spirals, threenorm and waveform.

use e.algo.rand.r as rng
use e.math
use e.mem

type Data = struct { x: []f64, y: []f64, d: usize }

fn pi() -> f64 { ret 3.141592653589793f64 }

fn alloc_data(a: *mem.Arena, n: usize, d: usize) -> (Data, err) {
    var none: Data = zero
    let (x, xe) = mem.alloc[f64](a, n * d)
    if xe != ok { ret (none, xe) }
    let (y, ye) = mem.alloc[f64](a, n)
    if ye != ok { ret (none, ye) }
    ret (Data { x: x, y: y, d: d }, ok)
}

fn friedman1(a: *mem.Arena, g: *rng.Rng, n: usize, sd: f64) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 10usize)
    if e != ok { ret (dt, e) }
    var c = 0usize
    while c < 10usize {
        var r = 0usize
        while r < n {
            dt.x[r * 10usize + c] = rng.runif(g, 0.0f64, 1.0f64)
            r += 1usize
        }
        c += 1usize
    }
    var r = 0usize
    while r < n {
        let x1 = dt.x[r * 10usize]
        let x2 = dt.x[r * 10usize + 1usize]
        let x3 = dt.x[r * 10usize + 2usize]
        let x4 = dt.x[r * 10usize + 3usize]
        let x5 = dt.x[r * 10usize + 4usize]
        dt.y[r] = 10.0f64 * math.sin[f64](pi() * x1 * x2) + 20.0f64 * (x3 - 0.5f64) * (x3 - 0.5f64) + 10.0f64 * x4 + 5.0f64 * x5
        r += 1usize
    }
    if sd > 0.0f64 {
        r = 0usize
        while r < n {
            dt.y[r] += rng.rnorm(g, 0.0f64, sd)
            r += 1usize
        }
    }
    ret (dt, ok)
}

// friedman2 (kind 2) and friedman3 (kind 3)
fn friedman23(a: *mem.Arena, g: *rng.Rng, n: usize, sd: f64, kind: u8) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 4usize)
    if e != ok { ret (dt, e) }
    var lo: [4]f64 = zero
    var hi: [4]f64 = zero
    lo[0usize] = 0.0f64
    hi[0usize] = 100.0f64
    lo[1usize] = 40.0f64 * pi()
    hi[1usize] = 560.0f64 * pi()
    lo[2usize] = 0.0f64
    hi[2usize] = 1.0f64
    lo[3usize] = 1.0f64
    hi[3usize] = 11.0f64
    var c = 0usize
    while c < 4usize {
        var r = 0usize
        while r < n {
            dt.x[r * 4usize + c] = rng.runif(g, lo[c], hi[c])
            r += 1usize
        }
        c += 1usize
    }
    var r = 0usize
    while r < n {
        let x1 = dt.x[r * 4usize]
        let x2 = dt.x[r * 4usize + 1usize]
        let x3 = dt.x[r * 4usize + 2usize]
        let x4 = dt.x[r * 4usize + 3usize]
        let q = x2 * x3 - 1.0f64 / (x2 * x4)
        if kind == 2u8 { dt.y[r] = math.sqrt[f64](x1 * x1 + q * q) } else { dt.y[r] = math.atan[f64](q / x1) }
        r += 1usize
    }
    if sd > 0.0f64 {
        r = 0usize
        while r < n {
            dt.y[r] += rng.rnorm(g, 0.0f64, sd)
            r += 1usize
        }
    }
    ret (dt, ok)
}

// 2dnormals(n, cl, r, sd): classes in y
fn normals2d(a: *mem.Arena, g: *rng.Rng, n: usize, cl: usize, r: f64, sd: f64) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 2usize)
    if e != ok { ret (dt, e) }
    let (pick, pe) = rng.sample_int(a, g, i64(cl), i64(n), true)
    if pe != ok { ret (dt, pe) }
    var c = 0usize
    while c < 2usize {
        var i = 0usize
        while i < n {
            dt.x[i * 2usize + c] = rng.rnorm(g, 0.0f64, sd)
            i += 1usize
        }
        c += 1usize
    }
    var i = 0usize
    while i < n {
        let ee = f64(pick[i] - 1i64)
        let ang = pi() / 4.0f64 + ee * 2.0f64 * pi() / f64(cl)
        dt.x[i * 2usize] += r * math.cos[f64](ang)
        dt.x[i * 2usize + 1usize] += r * math.sin[f64](ang)
        dt.y[i] = f64(pick[i])
        i += 1usize
    }
    ret (dt, ok)
}

// circle (kind 0) and xor (kind 1) in d dimensions: classes in y
fn circle_xor(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, kind: u8) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, d)
    if e != ok { ret (dt, e) }
    var c = 0usize
    while c < d {
        var i = 0usize
        while i < n {
            dt.x[i * d + c] = rng.runif(g, 0.0f64 - 1.0f64, 1.0f64)
            i += 1usize
        }
        c += 1usize
    }
    let (out2, oe2) = return_ok(dt, n, d, kind)
    ret (out2, oe2)
}

fn return_ok(dt: Data, n: usize, d: usize, kind: u8) -> (Data, err) {
    var i = 0usize
    if kind == 0u8 {
        // r = (2^(d-1) gamma(1 + d/2) / pi^(d/2))^(1/d)
        let df = f64(d)
        let r = math.pow[f64](math.pow[f64](2.0f64, df - 1.0f64) * gamma_half(d) / math.pow[f64](pi(), df / 2.0f64), 1.0f64 / df)
        while i < n {
            var s = 0.0f64
            var c = 0usize
            while c < d {
                s += dt.x[i * d + c] * dt.x[i * d + c]
                c += 1usize
            }
            dt.y[i] = 1.0f64
            if s > r * r { dt.y[i] = 2.0f64 }
            i += 1usize
        }
    } else {
        while i < n {
            var z = 1.0f64
            var pw = 1.0f64
            var c = 1usize
            var first = dt.x[i * d] >= 0.0f64
            while c < d {
                var bit = dt.x[i * d + c] >= 0.0f64
                if !first { bit = !bit }
                if bit { z += pw }
                pw *= 2.0f64
                c += 1usize
            }
            dt.y[i] = z
            i += 1usize
        }
    }
    var out = dt
    ret (out, ok)
}

// gamma(1 + d / 2) for integer d >= 2
fn gamma_half(d: usize) -> f64 {
    var v = 1.0f64
    var x = f64(d) / 2.0f64
    // gamma(1 + x) = x gamma(x); reduce to 1 or sqrt(pi) / 2
    while x > 1.0f64 {
        v *= x
        x -= 1.0f64
    }
    if x == 1.0f64 { ret v }
    ret v * x * 1.7724538509055159f64
}

// twonorm (kind 0, mean +- 2 / sqrt(d), sd 1) and ringnorm (kind 1, class 1 sd 2, class 2 mean 1 / sqrt(d))
fn twonorm_ringnorm(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, kind: u8) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, d)
    if e != ok { ret (dt, e) }
    let h = n / 2usize
    let (c2, ce) = rng.sample_int(a, g, i64(n), i64(h), false)
    if ce != ok { ret (dt, ce) }
    let (inc2, ie) = mem.alloc[bool](a, n)
    if ie != ok { ret (dt, ie) }
    var i = 0usize
    while i < n {
        inc2[i] = false
        dt.y[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < h {
        inc2[usize(c2[i]) - 1usize] = true
        dt.y[usize(c2[i]) - 1usize] = 2.0f64
        i += 1usize
    }
    var a1 = 2.0f64 / math.sqrt[f64](f64(d))
    var mean1 = a1
    var sd1 = 1.0f64
    var mean2 = 0.0f64 - a1
    if kind == 1u8 {
        a1 = 1.0f64 / math.sqrt[f64](f64(d))
        mean1 = 0.0f64
        sd1 = 2.0f64
        mean2 = a1
    }
    // x[-c2, ] <- matrix(rnorm(d * (n - h), mean1, sd1), ncol = d): column-major over the remaining rows in order
    let m1 = n - h
    var c = 0usize
    while c < d {
        var k = 0usize
        var r = 0usize
        while r < n {
            if !inc2[r] {
                dt.x[r * d + c] = rng.rnorm(g, mean1, sd1)
                k += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < d {
        i = 0usize
        while i < h {
            dt.x[(usize(c2[i]) - 1usize) * d + c] = rng.rnorm(g, mean2, 1.0f64)
            i += 1usize
        }
        c += 1usize
    }
    ret (dt, ok)
}

// R's round(): half to even
fn round_even(x: f64) -> f64 {
    let r = math.floor[f64](x)
    let d = x - r
    if d < 0.5f64 { ret r }
    if d > 0.5f64 { ret r + 1.0f64 }
    if math.floor[f64](r / 2.0f64) * 2.0f64 == r { ret r }
    ret r + 1.0f64
}

fn cassini_b(x: f64, a: f64, c: f64, upper: bool) -> f64 {
    let v = math.sqrt[f64](0.0f64 - c * c - x * x + math.sqrt[f64](math.pow[f64](a, 4.0f64) + 4.0f64 * c * c * x * x))
    if upper { ret v }
    ret 0.0f64 - v
}

// mlbench.cassini(n, relsize): three pieces by rejection from runif; classes in y
fn cassini(a: *mem.Arena, g: *rng.Rng, n: usize, b1: f64, b2: f64, sm: f64) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 2usize)
    if e != ok { ret (dt, e) }
    let parts = b1 + b2 + sm
    let npiece = f64(n) / parts
    let n1 = usize(round_even(b1 * npiece))
    let n2 = usize(round_even(b2 * npiece))
    var n3 = usize(round_even(sm * npiece))
    if n1 + n2 + n3 != n { n3 += 1usize }
    let aa = 1.0f64
    let cc = 0.97f64
    let cell = math.sqrt[f64]((1.0f64 + cc * cc) / 3.0f64)
    let aell = cell * math.sqrt[f64](2.0f64)
    let transl = 1.1f64
    let r = 0.6f64
    let lim = math.sqrt[f64](aa * aa + cc * cc)
    var found = 0usize
    var row = 0usize
    while found < n1 {
        let x1 = rng.runif(g, 0.0f64 - lim, lim)
        let y1 = rng.runif(g, 0.0f64 - transl - 1.0f64, 0.0f64 - transl + 0.6f64)
        if y1 < cassini_b(x1, aa, cc, true) - transl && y1 > cassini_b(x1, aell, cell, false) - transl {
            dt.x[row * 2usize] = x1
            dt.x[row * 2usize + 1usize] = y1
            dt.y[row] = 1.0f64
            row += 1usize
            found += 1usize
        }
    }
    found = 0usize
    while found < n2 {
        let x2 = rng.runif(g, 0.0f64 - lim, lim)
        let y2 = rng.runif(g, transl - 0.6f64, transl + 1.0f64)
        if y2 > cassini_b(x2, aa, cc, false) + transl && y2 < cassini_b(x2, aell, cell, true) + transl {
            dt.x[row * 2usize] = x2
            dt.x[row * 2usize + 1usize] = y2
            dt.y[row] = 2.0f64
            row += 1usize
            found += 1usize
        }
    }
    found = 0usize
    while found < n3 {
        let x3 = rng.runif(g, 0.0f64 - r, r)
        let y3 = rng.runif(g, 0.0f64 - r, r)
        let cr = math.sqrt[f64](r * r - x3 * x3)
        if y3 > 0.0f64 - cr && y3 < cr {
            dt.x[row * 2usize] = x3
            dt.x[row * 2usize + 1usize] = y3
            dt.y[row] = 3.0f64
            row += 1usize
            found += 1usize
        }
    }
    ret (dt, ok)
}

// mlbench.hypercube (kind 0, corners with the given sides) and mlbench.simplex (kind 1, the d + 1 vertices of a simplex of edge `side`,
// centred when centre is set): n1 = round(n / 2^d) normal points of sd around each vertex
fn corners(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, side: f64, sd: f64, kind: u8, centre: bool) -> (Data, err) {
    var pw = 1usize
    var pi2 = 0usize
    while pi2 < d {
        pw = pw * 2usize
        pi2 += 1usize
    }
    var k = d + 1usize
    if kind == 0u8 { k = pw }
    let n1 = usize(round_even(f64(n) / f64(pw)))
    let (dt, e) = alloc_data(a, n1 * k, d)
    if e != ok { ret (dt, e) }
    let (m, me) = mem.alloc[f64](a, k * d)
    let (cent, ce) = mem.alloc[f64](a, d)
    if me != ok || ce != ok { ret (dt, me) }
    var i = 0usize
    while i < k * d {
        m[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < d {
        cent[i] = 0.0f64
        i += 1usize
    }
    if kind == 0u8 {
        var row = 0usize
        while row < k {
            var c = 0usize
            while c < d {
                // column c+1 of R's hypercube(d): blocks of 2^(d-c-1) zeros then ones, recycled
                var blk = pw
                var bi = 0usize
                while bi <= c {
                    blk = blk / 2usize
                    bi += 1usize
                }
                if (row / blk) % 2usize == 1usize { m[row * d + c] = side }
                c += 1usize
            }
            row += 1usize
        }
    } else {
        m[1usize * d] = side
        cent[0usize] = side / 2.0f64
        var b = side / 2.0f64
        var q = 2usize
        while q <= d {
            var c = 0usize
            while c < d {
                m[q * d + c] = cent[c]
                c += 1usize
            }
            m[q * d + q - 1usize] = math.sqrt[f64](side * side - b * b)
            cent[q - 1usize] = 1.0f64 / f64(q + 1usize) * m[q * d + q - 1usize]
            b = (1.0f64 - 1.0f64 / f64(q + 1usize)) * m[q * d + q - 1usize]
            q += 1usize
        }
        if centre {
            var row = 0usize
            while row < k {
                var c = 0usize
                while c < d {
                    m[row * d + c] = m[row * d + c] - cent[c]
                    c += 1usize
                }
                row += 1usize
            }
        }
    }
    var row = 0usize
    while row < k {
        var c = 0usize
        while c < d {
            var r = 0usize
            while r < n1 {
                dt.x[(row * n1 + r) * d + c] = rng.rnorm(g, 0.0f64, sd) + m[row * d + c]
                r += 1usize
            }
            c += 1usize
        }
        var r = 0usize
        while r < n1 {
            dt.y[row * n1 + r] = f64(row + 1usize)
            r += 1usize
        }
        row += 1usize
    }
    ret (dt, ok)
}

// mlbench.peak(n, d)
fn peak(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, d)
    if e != ok { ret (dt, e) }
    var i = 0usize
    while i < n {
        let radius = rng.runif(g, 0.0f64, 3.0f64)
        var c = 0usize
        var s = 0.0f64
        while c < d {
            dt.x[i * d + c] = rng.rnorm(g, 0.0f64, 1.0f64)
            s += dt.x[i * d + c] * dt.x[i * d + c]
            c += 1usize
        }
        let metro = math.sqrt[f64](s)
        c = 0usize
        while c < d {
            dt.x[i * d + c] = radius * (dt.x[i * d + c] / metro)
            c += 1usize
        }
        dt.y[i] = 25.0f64 * math.exp[f64](0.0f64 - 0.5f64 * radius * radius)
        i += 1usize
    }
    ret (dt, ok)
}

// mlbench.shapes(n) (kind 0) and mlbench.smiley(n, sd1, sd2) (kind 1)
fn shapes_smiley(a: *mem.Arena, g: *rng.Rng, n: usize, sd1: f64, sd2: f64, kind: u8) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 2usize)
    if e != ok { ret (dt, e) }
    var row = 0usize
    if kind == 0u8 {
        let n1 = usize(round_even(f64(n) / 4.0f64))
        let n2 = n - 3usize * n1
        var r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize] = rng.rnorm(g, 0.0f64 - 1.0f64, 0.2f64)
            dt.y[row + r] = 1.0f64
            r += 1usize
        }
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize + 1usize] = rng.rnorm(g, 1.5f64, 0.2f64)
            r += 1usize
        }
        row += n1
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize] = rng.runif(g, 0.0f64 - 1.5f64, 0.0f64 - 0.5f64)
            dt.y[row + r] = 2.0f64
            r += 1usize
        }
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize + 1usize] = rng.runif(g, 0.0f64 - 2.0f64, 0.0f64)
            r += 1usize
        }
        row += n1
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize] = rng.runif(g, 0.0f64 - 1.0f64, 1.0f64)
            dt.y[row + r] = 3.0f64
            r += 1usize
        }
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize + 1usize] = rng.runif(g, 1.0f64, 2.0f64)
            r += 1usize
        }
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize] = dt.x[(row + r) * 2usize] * (2.0f64 - dt.x[(row + r) * 2usize + 1usize]) + 1.0f64
            r += 1usize
        }
        row += n1
        r = 0usize
        while r < n2 {
            dt.x[(row + r) * 2usize] = rng.runif(g, 0.5f64, 2.0f64)
            dt.y[row + r] = 4.0f64
            r += 1usize
        }
        r = 0usize
        while r < n2 {
            let x4 = dt.x[(row + r) * 2usize]
            dt.x[(row + r) * 2usize + 1usize] = math.cos[f64](4.0f64 * x4) - x4 + rng.runif(g, 0.0f64 - 0.2f64, 0.2f64)
            r += 1usize
        }
    } else {
        let n1 = usize(round_even(f64(n) / 6.0f64))
        let n2 = usize(round_even(f64(n) / 4.0f64))
        let n3 = n - 2usize * n1 - n2
        var r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize] = rng.rnorm(g, 0.0f64 - 0.8f64, sd1)
            dt.y[row + r] = 1.0f64
            r += 1usize
        }
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize + 1usize] = rng.rnorm(g, 1.0f64, sd1)
            r += 1usize
        }
        row += n1
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize] = rng.rnorm(g, 0.8f64, sd1)
            dt.y[row + r] = 2.0f64
            r += 1usize
        }
        r = 0usize
        while r < n1 {
            dt.x[(row + r) * 2usize + 1usize] = rng.rnorm(g, 1.0f64, sd1)
            r += 1usize
        }
        row += n1
        r = 0usize
        while r < n2 {
            dt.x[(row + r) * 2usize] = rng.runif(g, 0.0f64 - 0.2f64, 0.2f64)
            dt.y[row + r] = 3.0f64
            r += 1usize
        }
        r = 0usize
        while r < n2 {
            dt.x[(row + r) * 2usize + 1usize] = rng.runif(g, 0.0f64, 0.75f64)
            r += 1usize
        }
        r = 0usize
        while r < n2 {
            dt.x[(row + r) * 2usize] = dt.x[(row + r) * 2usize] * (1.0f64 - dt.x[(row + r) * 2usize + 1usize])
            r += 1usize
        }
        row += n2
        r = 0usize
        while r < n3 {
            dt.x[(row + r) * 2usize] = rng.runif(g, 0.0f64 - 1.0f64, 1.0f64)
            dt.y[row + r] = 4.0f64
            r += 1usize
        }
        r = 0usize
        while r < n3 {
            let x4 = dt.x[(row + r) * 2usize]
            dt.x[(row + r) * 2usize + 1usize] = x4 * x4 - 1.0f64 + rng.rnorm(g, 0.0f64, sd2)
            r += 1usize
        }
    }
    ret (dt, ok)
}

// one spiral of n points (mlbench.1spiral), written into rows rows[0..n) of dt with the sign `sgn`
fn spiral_rows(g: *rng.Rng, dt: Data, rows: []const i64, n: usize, cycles: f64, sd: f64, sgn: f64) {
    var i = 0usize
    while i < n {
        let w = f64(i) * (cycles / f64(n))
        dt.x[usize(rows[i]) * 2usize] = sgn * ((2.0f64 * w + 1.0f64) * math.cos[f64](2.0f64 * pi() * w) / 3.0f64)
        dt.x[usize(rows[i]) * 2usize + 1usize] = sgn * ((2.0f64 * w + 1.0f64) * math.sin[f64](2.0f64 * pi() * w) / 3.0f64)
        i += 1usize
    }
    if sd > 0.0f64 {
        i = 0usize
        while i < n {
            let e = rng.rnorm(g, 0.0f64, sd)
            let w = f64(i) * (cycles / f64(n))
            let xs = math.cos[f64](2.0f64 * pi() * w) - pi() * (2.0f64 * w + 1.0f64) * math.sin[f64](2.0f64 * pi() * w)
            let ys = math.sin[f64](2.0f64 * pi() * w) + pi() * (2.0f64 * w + 1.0f64) * math.cos[f64](2.0f64 * pi() * w)
            let nrm = math.sqrt[f64](xs * xs + ys * ys)
            let r = usize(rows[i])
            // the spiral is computed with the sign applied afterwards in R (x[c2,] <- -mlbench.1spiral(...)), so the noise is negated too
            dt.x[r * 2usize] = sgn * (sgn * dt.x[r * 2usize] + e * ys / nrm)
            dt.x[r * 2usize + 1usize] = sgn * (sgn * dt.x[r * 2usize + 1usize] - e * xs / nrm)
            i += 1usize
        }
    }
}

// mlbench.spirals(n, cycles, sd)
fn spirals(a: *mem.Arena, g: *rng.Rng, n: usize, cycles: f64, sd: f64) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 2usize)
    if e != ok { ret (dt, e) }
    let h = n / 2usize
    let (c2, ce) = rng.sample_int(a, g, i64(n), i64(h), false)
    if ce != ok { ret (dt, ce) }
    let (c1, e1) = mem.alloc[i64](a, n - h)
    let (mark, e2) = mem.alloc[bool](a, n)
    if e1 != ok || e2 != ok { ret (dt, e1) }
    var i = 0usize
    while i < n {
        mark[i] = false
        dt.y[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < h {
        mark[usize(c2[i] - 1i64)] = true
        dt.y[usize(c2[i] - 1i64)] = 2.0f64
        i += 1usize
    }
    var k = 0usize
    i = 0usize
    while i < n {
        if !mark[i] {
            c1[k] = i64(i)
            k += 1usize
        }
        i += 1usize
    }
    let (r2, e3) = mem.alloc[i64](a, h)
    if e3 != ok { ret (dt, e3) }
    i = 0usize
    while i < h {
        r2[i] = c2[i] - 1i64
        i += 1usize
    }
    spiral_rows(g, dt, c1, n - h, cycles, sd, 1.0f64)
    spiral_rows(g, dt, r2, h, cycles, sd, 0.0f64 - 1.0f64)
    ret (dt, ok)
}

// mlbench.threenorm(n, d)
fn threenorm(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, d)
    if e != ok { ret (dt, e) }
    let h = n / 2usize
    let (c2, ce) = rng.sample_int(a, g, i64(n), i64(h), false)
    if ce != ok { ret (dt, ce) }
    let (mark, e2) = mem.alloc[bool](a, n)
    if e2 != ok { ret (dt, e2) }
    var i = 0usize
    while i < n {
        mark[i] = false
        dt.y[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < h {
        mark[usize(c2[i] - 1i64)] = true
        dt.y[usize(c2[i] - 1i64)] = 2.0f64
        i += 1usize
    }
    let aa = 2.0f64 / math.sqrt[f64](f64(d))
    i = 0usize
    while i < n {
        if !mark[i] {
            let u = rng.runif(g, 0.0f64, 1.0f64)
            let distr = round_even(u) == 1.0f64
            var c = 0usize
            while c < d {
                if distr {
                    dt.x[i * d + c] = rng.rnorm(g, aa, 1.0f64)
                } else {
                    dt.x[i * d + c] = rng.rnorm(g, 0.0f64 - aa, 1.0f64)
                }
                c += 1usize
            }
        }
        i += 1usize
    }
    var j = 0usize
    while j < h {
        let r = usize(c2[j] - 1i64)
        var c = 0usize
        while c < d {
            // m = rep(c(a, -a), d / 2), plus a when d is odd: even positions a, odd positions -a
            var mean = aa
            if c % 2usize == 1usize { mean = 0.0f64 - aa }
            dt.x[r * d + c] = rng.rnorm(g, mean, 1.0f64)
            c += 1usize
        }
        j += 1usize
    }
    ret (dt, ok)
}

// mlbench.waveform(n): the 21-attribute CART waveform problem; classes in y
fn waveform(a: *mem.Arena, g: *rng.Rng, n: usize) -> (Data, err) {
    let (dt, e) = alloc_data(a, n, 21usize)
    if e != ok { ret (dt, e) }
    let (hh, he) = mem.alloc[f64](a, 63usize)
    if he != ok { ret (dt, he) }
    var i = 0usize
    while i < 63usize {
        hh[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i <= 6usize {
        hh[i] = f64(i)
        i += 1usize
    }
    var j = 1usize
    i = 11usize
    while i >= 7usize {
        hh[i] = f64(j)
        j += 1usize
        i -= 1usize
    }
    j = 1usize
    i = 9usize
    while i <= 14usize {
        hh[21usize + i] = f64(j)
        j += 1usize
        i += 1usize
    }
    j = 1usize
    i = 19usize
    while i >= 15usize {
        hh[21usize + i] = f64(j)
        j += 1usize
        i -= 1usize
    }
    j = 1usize
    i = 5usize
    while i <= 10usize {
        hh[42usize + i] = f64(j)
        j += 1usize
        i += 1usize
    }
    j = 1usize
    i = 15usize
    while i >= 11usize {
        hh[42usize + i] = f64(j)
        j += 1usize
        i -= 1usize
    }
    var t = 0usize
    while t < n {
        let wt = usize(math.floor[f64](3.0f64 * rng.unif(g)))
        var c0 = 0usize
        var c1 = 1usize
        if wt == 1usize {
            c0 = 0usize
            c1 = 2usize
        }
        if wt == 2usize {
            c0 = 1usize
            c1 = 2usize
        }
        let m0 = rng.unif(g)
        let m1 = 1.0f64 - m0
        var k = 0usize
        while k < 21usize {
            let rv = rng.norm(g)
            dt.x[t * 21usize + k] = m0 * hh[c0 * 21usize + k] + m1 * hh[c1 * 21usize + k] + rv
            k += 1usize
        }
        dt.y[t] = f64(wt + 1usize)
        t += 1usize
    }
    ret (dt, ok)
}
