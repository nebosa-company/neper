// R's tgp package, first slice: the randomkit Mersenne-Twister that tgp's C++ draws from (seeded by
// three2lstate of three integers, not by R's RNG) and lhs(), the Latin hypercube sampler, both the
// uniform and the beta-quantile form. Not here yet: the treed-GP MCMC (btgp, btlm, bcart, bgp, blm,
// bgpllm, btgpllm), its predictions and the design routines.

use e.algo.rand.r as rr
use e.math.nmath_beta as nb
use e.mem

type Rk = struct { key: [624]u64, pos: usize }

const MASK32: u64 = 4294967295u64

error BadInput

// rk_seed(three2lstate(a, b, c)): Knuth's initialisation of the reference Mersenne Twister
fn rk_seed(rk: *Rk, s0: u64) {
    var seed = s0 & MASK32
    var pos = 0usize
    while pos < 624usize {
        rk.key[pos] = seed
        seed = (1812433253u64 * (seed ^ (seed >> 30u64)) + u64(pos) + 1u64) & MASK32
        pos += 1usize
    }
    rk.pos = 624usize
}

fn rk_state(a: i64, b: i64, c: i64) -> Rk {
    var rk: Rk = zero
    rk_seed(&rk, u64(a * 1000000i64 + b * 1000i64 + c))
    ret rk
}

fn rk_random(rk: *Rk) -> u64 {
    if rk.pos == 624usize {
        var i = 0usize
        while i < 227usize {
            let y = (rk.key[i] & 2147483648u64) | (rk.key[i + 1usize] & 2147483647u64)
            var mag = 0u64
            if (y & 1u64) != 0u64 { mag = 2567483615u64 }
            rk.key[i] = rk.key[i + 397usize] ^ (y >> 1u64) ^ mag
            i += 1usize
        }
        while i < 623usize {
            let y = (rk.key[i] & 2147483648u64) | (rk.key[i + 1usize] & 2147483647u64)
            var mag = 0u64
            if (y & 1u64) != 0u64 { mag = 2567483615u64 }
            rk.key[i] = rk.key[i - 227usize] ^ (y >> 1u64) ^ mag
            i += 1usize
        }
        let y = (rk.key[623usize] & 2147483648u64) | (rk.key[0usize] & 2147483647u64)
        var mag = 0u64
        if (y & 1u64) != 0u64 { mag = 2567483615u64 }
        rk.key[623usize] = rk.key[396usize] ^ (y >> 1u64) ^ mag
        rk.pos = 0usize
    }
    var y = rk.key[rk.pos]
    rk.pos += 1usize
    y = y ^ (y >> 11u64)
    y = y ^ (((y << 7u64) & MASK32) & 2636928640u64)
    y = y ^ (((y << 15u64) & MASK32) & 4022730752u64)
    y = y ^ (y >> 18u64)
    ret y
}

// runi(): one from uniform(0,1), in [0,1] inclusive of both ends
fn runi(rk: *Rk) -> f64 { ret f64(rk_random(rk)) / 4294967295.0f64 }

// rect_sample: dim rows of n uniforms, row-major
fn rect_sample(a: *mem.Arena, rk: *Rk, dim: usize, n: usize) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, dim * n)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < dim * n {
        s[i] = runi(rk)
        i += 1usize
    }
    ret (s, ok)
}

// ranks[i * n + j]: 1-based rank of s[i * n + j] within row i (qsort by value, no ties)
fn ranks(a: *mem.Arena, s: []const f64, dim: usize, n: usize) -> ([]usize, err) {
    let (r, e) = mem.alloc[usize](a, dim * n)
    if e != ok { ret (r, e) }
    let (ord, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (r, e2) }
    var i = 0usize
    while i < dim {
        var j = 0usize
        while j < n {
            var k = j
            while k > 0usize && s[i * n + ord[k - 1usize]] > s[i * n + j] {
                ord[k] = ord[k - 1usize]
                k -= 1usize
            }
            ord[k] = j
            j += 1usize
        }
        j = 0usize
        while j < n {
            r[i * n + ord[j]] = j + 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret (r, ok)
}

// transpose the dim x n draws into the n x dim row-major block lh_sample hands back, scaling into rect
// (rect[j] = low, rect[dim + j] = high)
fn finish(a: *mem.Arena, z: []const f64, dim: usize, n: usize, rect: []const f64) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, dim * n)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < dim {
        let scale = rect[dim + i] - rect[i]
        let shift = rect[i]
        var j = 0usize
        while j < n {
            out[j * dim + i] = z[i * n + j] * scale + shift
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// rect_sample_lh(dim, n, rect, er = 1): uniform Latin hypercube, n x dim row-major
fn lh_uniform(a: *mem.Arena, rk: *Rk, dim: usize, n: usize, rect: []const f64) -> ([]f64, err) {
    let (s, e) = rect_sample(a, rk, dim, n)
    if e != ok { ret (s, e) }
    let (r, e2) = ranks(a, s, dim, n)
    if e2 != ok { ret (s, e2) }
    let (ee, e3) = rect_sample(a, rk, dim, n)
    if e3 != ok { ret (s, e3) }
    let (z, e4) = mem.alloc[f64](a, dim * n)
    if e4 != ok { ret (z, e4) }
    var i = 0usize
    while i < dim * n {
        z[i] = (f64(r[i]) - ee[i]) / f64(n)
        i += 1usize
    }
    let (out, e5) = finish(a, z, dim, n, rect)
    ret (out, e5)
}

// beta_sample_lh: shape (0 = binary dimension) and mode, one per dimension; shape below 1 is raised to 1
fn lh_beta(a: *mem.Arena, rk: *Rk, dim: usize, n: usize, rect: []const f64, shape: []f64, mode: []const f64) -> ([]f64, err) {
    let (s, e) = rect_sample(a, rk, dim, n)
    if e != ok { ret (s, e) }
    let (r, e2) = ranks(a, s, dim, n)
    if e2 != ok { ret (s, e2) }
    let (ee, e3) = rect_sample(a, rk, dim, n)
    if e3 != ok { ret (s, e3) }
    let (z, e4) = mem.alloc[f64](a, dim * n)
    if e4 != ok { ret (z, e4) }
    var i = 0usize
    while i < dim {
        var j = 0usize
        if shape[i] == 0.0f64 {
            var ms = 0.5f64
            if !(mode[i] > 1.0f64 || mode[i] < 0.0f64) { ms = mode[i] }
            while j < n {
                z[i * n + j] = 0.0f64
                if runi(rk) < ms { z[i * n + j] = 1.0f64 }
                j += 1usize
            }
            i += 1usize
            continue
        }
        var mscaled = (mode[i] - rect[i]) / (rect[dim + i] - rect[i])
        if 0.0f64 > mscaled || 1.0f64 < mscaled { mscaled = 0.5f64 }
        if shape[i] < 1.0f64 { shape[i] = 1.0f64 }
        let alpha = (1.0f64 + mscaled * (shape[i] - 2.0f64)) / (1.0f64 - mscaled)
        while j < n {
            z[i * n + j] = nb.qbeta((f64(r[i * n + j]) - ee[i * n + j]) / f64(n), alpha, shape[i], true, false)
            j += 1usize
        }
        i += 1usize
    }
    let (out, e5) = finish(a, z, dim, n, rect)
    ret (out, e5)
}

// .C("lh_sample") for the integer state (a, b, c); shape[0] < 0 selects the uniform form
fn lh_sample(a: *mem.Arena, st: []const i64, n: usize, dim: usize, rect: []const f64, shape: []f64, mode: []const f64) -> ([]f64, err) {
    var rk = rk_state(st[0usize], st[1usize], st[2usize])
    if shape[0usize] < 0.0f64 {
        let (u, e) = lh_uniform(a, &rk, dim, n, rect)
        ret (u, e)
    }
    let (b, e2) = lh_beta(a, &rk, dim, n, rect, shape, mode)
    ret (b, e2)
}

// lhs(n, rect, shape, mode) under a seeded R generator: the state is sample(seq(0, 999), 3)
fn lhs(a: *mem.Arena, r: *rr.Rng, n: usize, dim: usize, rect: []const f64, shape: []f64, mode: []const f64) -> ([]f64, err) {
    let (idx, e) = rr.sample_int(a, r, 1000i64, 3i64, false)
    var none: []f64 = zero
    if e != ok { ret (none, e) }
    idx[0usize] -= 1i64
    idx[1usize] -= 1i64
    idx[2usize] -= 1i64
    let (out, e2) = lh_sample(a, idx, n, dim, rect, shape, mode)
    ret (out, e2)
}
