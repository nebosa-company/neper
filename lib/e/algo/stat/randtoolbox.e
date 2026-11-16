// R randtoolbox: the torus sequence, frac(k * sqrt(p_j)) over the first primes. The Halton and Sobol points are e.algo.rand.quasi.

fn prime_at(j: usize) -> f64 {
    var count = 0usize
    var c = 1u64
    while count <= j {
        c += 1u64
        var isp = true
        var d = 2u64
        while d * d <= c {
            if c % d == 0u64 {
                isp = false
                break
            }
            d += 1u64
        }
        if isp { count += 1usize }
    }
    ret f64(c)
}

fn sqrt_of(v: f64) -> f64 {
    var g = v
    var i = 0usize
    while i < 80usize {
        g = 0.5f64 * (g + v / g)
        i += 1usize
    }
    ret g
}

// the k-th point (k >= 1) of dimension j (0-based)
fn torus(k: u64, j: usize) -> f64 {
    let t = f64(k) * sqrt_of(prime_at(j))
    var f = t - f64(i64(t))
    if f < 0.0f64 { f = f + 1.0f64 }
    ret f
}

// the Bratley-Fox direction numbers of the first eight Sobol dimensions that randtoolbox uses (e.algo.rand.quasi has the Joe-Kuo set)
fn bf_direction(d: usize, bit: u32) -> u64 {
    if d == 0usize { ret 1u64 << (31u32 - bit) }
    var m: [40]u64 = zero
    var poly = 0u64
    if d == 1usize {
        poly = 3u64
        m[0usize] = 1u64
    } else if d == 2usize {
        poly = 7u64
        m[0usize] = 1u64
        m[1usize] = 1u64
    } else if d == 3usize {
        poly = 11u64
        m[0usize] = 1u64
        m[1usize] = 3u64
        m[2usize] = 7u64
    } else if d == 4usize {
        poly = 13u64
        m[0usize] = 1u64
        m[1usize] = 1u64
        m[2usize] = 5u64
    } else if d == 5usize {
        poly = 19u64
        m[0usize] = 1u64
        m[1usize] = 3u64
        m[2usize] = 1u64
        m[3usize] = 1u64
    } else if d == 6usize {
        poly = 25u64
        m[0usize] = 1u64
        m[1usize] = 1u64
        m[2usize] = 3u64
        m[3usize] = 7u64
    } else {
        poly = 37u64
        m[0usize] = 1u64
        m[1usize] = 3u64
        m[2usize] = 3u64
        m[3usize] = 9u64
        m[4usize] = 9u64
    }
    var degree = 0u32
    while (poly >> (degree + 1u32)) != 0u64 { degree += 1u32 }
    var i = usize(degree)
    while i <= usize(bit) {
        var value = m[i - usize(degree)] ^ (m[i - usize(degree)] << degree)
        var k = 1u32
        while k < degree {
            if ((poly >> (degree - k)) & 1u64) == 1u64 { value ^= m[i - usize(k)] << k }
            k += 1u32
        }
        m[i] = value
        i += 1usize
    }
    ret m[usize(bit)] << (31u32 - bit)
}

// the index-th unscrambled Sobol point of randtoolbox in dimension d (0-based, below 8)
fn sobol(index: u64, d: usize) -> f64 {
    let gray = index ^ (index >> 1u32)
    var x = 0u64
    var bit = 0u32
    while bit < 32u32 {
        if ((gray >> bit) & 1u64) == 1u64 { x ^= bf_direction(d, bit) }
        bit += 1u32
    }
    ret f64(x) / 4294967296.0f64
}
