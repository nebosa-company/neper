// R mlbench data generators, drawing from the Mersenne-Twister stream in the order R fills its matrices
// (by column): friedman1, friedman2, friedman3, 2dnormals, circle, xor, twonorm and ringnorm. A data set
// is x (n rows by d columns, row-major) and y (the response) or the class codes (1-based).
//
// Not here: cassini, hypercube, peak, shapes, simplex, smiley, spirals, threenorm and waveform.

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
