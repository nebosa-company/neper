// Error-correcting codes over caller storage: systematic Reed-Solomon over
// GF(2^8) (polynomial 0x11d, generator 2, roots from alpha^0, the reedsolo
// conventions) with errors and erasures, and K + M erasure coding of chunks
// on top of it; binary BCH of length 15 over GF(2^4) with a caller generator;
// the rate-1/2 K=3 convolutional code (7, 5) with hard-decision Viterbi;
// min-sum belief propagation over a caller parity-check matrix; and
// Hamming(7,4) with its SECDED (8,4) extension.
//
// Polynomials inside the decoders are lowest degree first; a codeword's
// first symbol is its highest degree, so `code[n - 1 - i]` carries x^i.
// `Field` holds the exponent and logarithm tables of a field whose
// multiplicative order is 255 (Reed-Solomon) or 15 (BCH).

use e.math.gf

type Field = struct { exp: [512]u8, log: [256]u8, order: usize }
error Invalid
error TooSmall

// GF(2^8) as Reed-Solomon uses it.
fn field() -> Field {
    var f: Field = zero
    f.order = 255usize
    let _ = gf.tables(2u8, 0x1du8, f.exp[..], f.log[..])
    ret f
}

// GF(2^4) modulo x^4 + x + 1, generator 2.
fn field16() -> Field {
    var f: Field = zero
    f.order = 15usize
    var x = 1u32
    var i = 0usize
    while i < 15usize {
        f.exp[i] = u8(x)
        f.exp[i + 15usize] = u8(x)
        f.log[usize(x)] = u8(i)
        x = x << 1u32
        if (x & 16u32) != 0u32 { x ^= 19u32 }
        i += 1usize
    }
    ret f
}

fn mul(f: *const Field, a: u8, b: u8) -> u8 {
    if a == 0u8 || b == 0u8 { ret 0u8 }
    ret f.exp[usize(f.log[usize(a)]) + usize(f.log[usize(b)])]
}

fn inverse(f: *const Field, a: u8) -> u8 { ret f.exp[f.order - usize(f.log[usize(a)])] }

// alpha^e, any e.
fn alpha_pow(f: *const Field, e: usize) -> u8 { ret f.exp[e % f.order] }

// alpha^-e.
fn alpha_neg(f: *const Field, e: usize) -> u8 { ret f.exp[(f.order - e % f.order) % f.order] }

// p(x) for `p` lowest degree first.
fn poly_eval(f: *const Field, p: []const u8, x: u8) -> u8 {
    var y = 0u8
    var i = p.len
    while i > 0usize {
        i -= 1usize
        y = mul(f, y, x) ^ p[i]
    }
    ret y
}

// c(x) for a codeword `c` highest degree first.
fn code_eval(f: *const Field, c: []const u8, x: u8) -> u8 {
    var y = 0u8
    var i = 0usize
    while i < c.len {
        y = mul(f, y, x) ^ c[i]
        i += 1usize
    }
    ret y
}

// out = a * b truncated to `out.len` coefficients; `out` is cleared first and
// must not alias an input.
fn poly_mul(f: *const Field, a: []const u8, b: []const u8, out: []u8) {
    var i = 0usize
    while i < out.len {
        out[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < a.len {
        var j = 0usize
        while j < b.len && i + j < out.len {
            out[i + j] ^= mul(f, a[i], b[j])
            j += 1usize
        }
        i += 1usize
    }
}

// Berlekamp-Massey: the shortest recurrence generating `seq`, its
// connection polynomial in `lambda` (lowest degree first, `lambda[0] = 1`)
// and its length answered. `lambda`, `prior` and `scratch` need
// `seq.len + 1` entries each.
fn berlekamp_massey(f: *const Field, seq: []const u8, lambda: []u8, prior: []u8, scratch: []u8) -> usize {
    let cap = seq.len + 1usize
    var i = 0usize
    while i < cap {
        lambda[i] = 0u8
        prior[i] = 0u8
        i += 1usize
    }
    lambda[0usize] = 1u8
    prior[0usize] = 1u8
    var length = 0usize
    var shift = 1usize
    var last = 1u8
    var r = 0usize
    while r < seq.len {
        var d = seq[r]
        i = 1usize
        while i <= length {
            d ^= mul(f, lambda[i], seq[r - i])
            i += 1usize
        }
        if d == 0u8 {
            shift += 1usize
            r += 1usize
            continue
        }
        let coef = mul(f, d, inverse(f, last))
        i = 0usize
        while i < cap {
            scratch[i] = lambda[i]
            i += 1usize
        }
        i = 0usize
        while i + shift < cap {
            lambda[i + shift] ^= mul(f, coef, prior[i])
            i += 1usize
        }
        if 2usize * length <= r {
            i = 0usize
            while i < cap {
                prior[i] = scratch[i]
                i += 1usize
            }
            last = d
            length = r + 1usize - length
            shift = 1usize
        } else {
            shift += 1usize
        }
        r += 1usize
    }
    ret length
}

// Chien search: the degrees `i < n` with `p(alpha^-i) = 0`, written to
// `roots` (up to its length); answers how many there were.
fn chien(f: *const Field, p: []const u8, n: usize, roots: []usize) -> usize {
    var found = 0usize
    var i = 0usize
    while i < n {
        if poly_eval(f, p, alpha_neg(f, i)) == 0u8 {
            if found < roots.len { roots[found] = i }
            found += 1usize
        }
        i += 1usize
    }
    ret found
}

// Systematic encoding: `data` then `parity` check symbols into `out`;
// `data.len + parity <= 255`. Answers the codeword length.
fn reed_solomon_encode(f: *const Field, data: []const u8, parity: usize, out: []u8) -> (usize, err) {
    let n = data.len + parity
    if parity == 0usize || n > 255usize || data.len == 0usize { ret (0usize, Invalid) }
    if out.len < n { ret (0usize, TooSmall) }
    // g(x) = prod (x + alpha^i), lowest degree first.
    var g: [256]u8 = zero
    g[0usize] = 1u8
    var i = 0usize
    while i < parity {
        let root = alpha_pow(f, i)
        var j = i + 1usize
        while j > 0usize {
            g[j] = g[j - 1usize] ^ mul(f, g[j], root)
            j -= 1usize
        }
        g[0usize] = mul(f, g[0usize], root)
        i += 1usize
    }
    // Long division of data(x) x^parity by g(x); the remainder is the parity.
    i = 0usize
    while i < n {
        if i < data.len { out[i] = data[i] } else { out[i] = 0u8 }
        i += 1usize
    }
    i = 0usize
    while i < data.len {
        let coef = out[i]
        if coef != 0u8 {
            var j = 1usize
            while j <= parity {
                out[i + j] ^= mul(f, coef, g[parity - j])
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < data.len {
        out[i] = data[i]
        i += 1usize
    }
    ret (n, ok)
}

// Correct `code` in place given `parity` check symbols and the positions of
// known `erasures`; `2 * errors + erasures <= parity`. Answers how many
// symbols changed, or `Invalid` when the word is beyond repair.
fn reed_solomon_decode(f: *const Field, code: []u8, parity: usize, erasures: []const usize) -> (usize, err) {
    let n = code.len
    let e = erasures.len
    if parity == 0usize || parity >= n || n > 255usize || e > parity { ret (0usize, Invalid) }
    var syndromes: [256]u8 = zero
    var clean = true
    var i = 0usize
    while i < parity {
        syndromes[i] = code_eval(f, code, alpha_pow(f, i))
        if syndromes[i] != 0u8 { clean = false }
        i += 1usize
    }
    if clean { ret (0usize, ok) }
    // The erasure locator, then the Forney syndromes it leaves.
    var gamma: [256]u8 = zero
    var product: [256]u8 = zero
    gamma[0usize] = 1u8
    var factor: [2]u8 = zero
    factor[0usize] = 1u8
    i = 0usize
    while i < e {
        if erasures[i] >= n { ret (0usize, Invalid) }
        factor[1usize] = alpha_pow(f, n - 1usize - erasures[i])
        poly_mul(f, gamma[..i + 1usize], factor[..], product[..i + 2usize])
        var j = 0usize
        while j < i + 2usize {
            gamma[j] = product[j]
            j += 1usize
        }
        i += 1usize
    }
    var forney: [256]u8 = zero
    poly_mul(f, gamma[..e + 1usize], syndromes[..parity], forney[..parity])
    var lambda: [256]u8 = zero
    var prior: [256]u8 = zero
    var scratch: [256]u8 = zero
    let errors = berlekamp_massey(f, forney[e..parity], lambda[..], prior[..], scratch[..])
    if 2usize * errors + e > parity { ret (0usize, Invalid) }
    // The errata locator psi = lambda * gamma and its roots.
    var psi: [256]u8 = zero
    poly_mul(f, lambda[..errors + 1usize], gamma[..e + 1usize], psi[..errors + e + 1usize])
    var degree = errors + e
    while degree > 0usize && psi[degree] == 0u8 { degree -= 1usize }
    var roots: [256]u8 = zero
    var positions: [256]usize = zero
    let found = chien(f, psi[..degree + 1usize], n, positions[..])
    if found != degree { ret (0usize, Invalid) }
    // Forney: magnitude X omega(X^-1) / psi'(X^-1) at each root.
    var omega: [256]u8 = zero
    poly_mul(f, psi[..degree + 1usize], syndromes[..parity], omega[..parity])
    i = 0usize
    while i < found {
        let x = alpha_pow(f, positions[i])
        let x_inverse = alpha_neg(f, positions[i])
        let numerator = poly_eval(f, omega[..parity], x_inverse)
        var denominator = 0u8
        var k = 1usize
        var power = 1u8
        while k <= degree {
            denominator ^= mul(f, psi[k], power)
            power = mul(f, power, mul(f, x_inverse, x_inverse))
            k += 2usize
        }
        if denominator == 0u8 { ret (0usize, Invalid) }
        roots[i] = mul(f, x, mul(f, numerator, inverse(f, denominator)))
        i += 1usize
    }
    i = 0usize
    while i < found {
        code[n - 1usize - positions[i]] ^= roots[i]
        i += 1usize
    }
    i = 0usize
    while i < parity {
        if code_eval(f, code, alpha_pow(f, i)) != 0u8 { ret (0usize, Invalid) }
        i += 1usize
    }
    ret (found, ok)
}

// K + M erasure coding: `data` is `k` chunks of equal length laid end to
// end; `parity` receives `m` chunks of that length; `k + m <= 255`.
fn reed_solomon_erasure_encode(f: *const Field, data: []const u8, k: usize, parity: []u8, m: usize) -> err {
    if k == 0usize || m == 0usize || k + m > 255usize || data.len % k != 0usize { ret Invalid }
    let chunk = data.len / k
    if parity.len < m * chunk { ret TooSmall }
    var column: [256]u8 = zero
    var code: [256]u8 = zero
    var j = 0usize
    while j < chunk {
        var i = 0usize
        while i < k {
            column[i] = data[i * chunk + j]
            i += 1usize
        }
        let (_, encode_error) = reed_solomon_encode(f, column[..k], m, code[..])
        if encode_error != ok { ret encode_error }
        i = 0usize
        while i < m {
            parity[i * chunk + j] = code[k + i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// Rebuild the `missing` chunks (indexes below `k + m`, at most `m` of them)
// of `chunks`, the `k` data chunks followed by the `m` parity chunks.
fn reed_solomon_erasure_decode(f: *const Field, chunks: []u8, k: usize, m: usize, missing: []const usize) -> err {
    if k == 0usize || m == 0usize || k + m > 255usize || chunks.len % (k + m) != 0usize || missing.len > m { ret Invalid }
    let chunk = chunks.len / (k + m)
    var column: [256]u8 = zero
    var j = 0usize
    while j < chunk {
        var i = 0usize
        while i < k + m {
            column[i] = chunks[i * chunk + j]
            i += 1usize
        }
        i = 0usize
        while i < missing.len {
            if missing[i] >= k + m { ret Invalid }
            column[missing[i]] = 0u8
            i += 1usize
        }
        let (_, decode_error) = reed_solomon_decode(f, column[..k + m], m, missing)
        if decode_error != ok { ret decode_error }
        i = 0usize
        while i < missing.len {
            chunks[missing[i] * chunk + j] = column[missing[i]]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// Systematic BCH of length 15 over `generator` (bit i is x^i, both end bits
// set; 0x1d1 is BCH(15,7) with t = 2, 0x13 is Hamming(15,11)): the data bits
// above the remainder. `data` fits in `15 - degree` bits.
fn bch_encode(generator: u32, data: u32) -> u32 {
    var degree = 0u32
    while (generator >> (degree + 1u32)) != 0u32 { degree += 1u32 }
    var remainder = data << degree
    var i = 14u32
    while i >= degree {
        if ((remainder >> i) & 1u32) != 0u32 { remainder ^= generator << (i - degree) }
        if i == 0u32 { break }
        i -= 1u32
    }
    ret (data << degree) | (remainder & ((1u32 << degree) - 1u32))
}

// Correct up to `t` bit errors in a 15-bit `word`: the corrected word and
// how many bits flipped, or `Invalid` past `t`.
fn bch_decode(word: u32, t: usize) -> (u32, usize, err) {
    if t == 0usize || t > 7usize { ret (word, 0usize, Invalid) }
    let f = field16()
    var syndromes: [14]u8 = zero
    var clean = true
    var j = 0usize
    while j < 2usize * t {
        var y = 0u8
        var i = 0usize
        while i < 15usize {
            if ((word >> u32(i)) & 1u32) != 0u32 { y ^= alpha_pow(&f, i * (j + 1usize)) }
            i += 1usize
        }
        syndromes[j] = y
        if y != 0u8 { clean = false }
        j += 1usize
    }
    if clean { ret (word, 0usize, ok) }
    var lambda: [16]u8 = zero
    var prior: [16]u8 = zero
    var scratch: [16]u8 = zero
    let errors = berlekamp_massey(&f, syndromes[..2usize * t], lambda[..], prior[..], scratch[..])
    if errors > t { ret (word, 0usize, Invalid) }
    var positions: [15]usize = zero
    let found = chien(&f, lambda[..errors + 1usize], 15usize, positions[..])
    if found != errors { ret (word, 0usize, Invalid) }
    var fixed = word
    j = 0usize
    while j < found {
        fixed ^= 1u32 << u32(positions[j])
        j += 1usize
    }
    ret (fixed, found, ok)
}

// The (7, 5) rate-1/2 code, one bit per byte, terminated with two zero
// bits: `out` receives `2 * (bits.len + 2)` bits.
fn convolutional_encode(bits: []const u8, out: []u8) -> (usize, err) {
    let total = 2usize * (bits.len + 2usize)
    if out.len < total { ret (0usize, TooSmall) }
    var s1 = 0u8
    var s0 = 0u8
    var i = 0usize
    while i < bits.len + 2usize {
        var b = 0u8
        if i < bits.len { b = bits[i] & 1u8 }
        out[2usize * i] = b ^ s1 ^ s0
        out[2usize * i + 1usize] = b ^ s0
        s0 = s1
        s1 = b
        i += 1usize
    }
    ret (total, ok)
}

// Hard-decision Viterbi over `received` (pairs of bits, one per byte) to
// `out` (`received.len / 2 - 2` bits); `survivors` needs `2 * received.len`
// bytes. Answers the number of message bits.
fn viterbi_decode(received: []const u8, out: []u8, survivors: []u8) -> (usize, err) {
    if received.len % 2usize != 0usize || received.len < 4usize { ret (0usize, Invalid) }
    let steps = received.len / 2usize
    if out.len < steps - 2usize || survivors.len < 4usize * steps { ret (0usize, TooSmall) }
    // State = (s1 << 1) | s0; an unreachable state carries the sentinel.
    var metric: [4]u32 = zero
    var next_metric: [4]u32 = zero
    metric[1usize] = 1000000000u32
    metric[2usize] = 1000000000u32
    metric[3usize] = 1000000000u32
    var t = 0usize
    while t < steps {
        let r0 = received[2usize * t] & 1u8
        let r1 = received[2usize * t + 1usize] & 1u8
        var s = 0usize
        while s < 4usize {
            next_metric[s] = 1000000000u32
            s += 1usize
        }
        s = 0usize
        while s < 4usize {
            if metric[s] < 1000000000u32 {
                let s1 = u8(s >> 1u32)
                let s0 = u8(s & 1usize)
                var b = 0u8
                while b < 2u8 {
                    var cost = metric[s]
                    if (b ^ s1 ^ s0) != r0 { cost += 1u32 }
                    if (b ^ s0) != r1 { cost += 1u32 }
                    let to = (usize(b) << 1u32) | usize(s1)
                    if cost < next_metric[to] {
                        next_metric[to] = cost
                        survivors[4usize * t + to] = u8(s)
                    }
                    b += 1u8
                }
            }
            s += 1usize
        }
        s = 0usize
        while s < 4usize {
            metric[s] = next_metric[s]
            s += 1usize
        }
        t += 1usize
    }
    // Trace back from the zero state the flush bits force.
    var state = 0usize
    t = steps
    while t > 0usize {
        t -= 1usize
        if t < steps - 2usize { out[t] = u8(state >> 1u32) }
        state = usize(survivors[4usize * t + state])
    }
    ret (steps - 2usize, ok)
}

// Whether `word` satisfies every row of `h` (`rows * cols` entries, 0 or 1).
fn ldpc_check(h: []const u8, rows: usize, cols: usize, word: []const u8) -> bool {
    var i = 0usize
    while i < rows {
        var sum = 0u8
        var j = 0usize
        while j < cols {
            sum ^= h[i * cols + j] & word[j]
            j += 1usize
        }
        if sum != 0u8 { ret false }
        i += 1usize
    }
    ret true
}

// Min-sum belief propagation from hard decisions in `word` (corrected in
// place), rows updated in turn; `messages` needs `rows * cols + cols`
// entries. Answers the iterations taken, or `Invalid` when `iterations`
// pass without every check satisfied.
fn ldpc_decode(h: []const u8, rows: usize, cols: usize, word: []u8, messages: []f64, iterations: usize) -> (usize, err) {
    if h.len < rows * cols || word.len < cols { ret (0usize, Invalid) }
    if messages.len < rows * cols + cols { ret (0usize, TooSmall) }
    var j = 0usize
    while j < rows * cols {
        messages[j] = 0.0f64
        j += 1usize
    }
    var channel: [1024]f64 = zero
    if cols > 1024usize { ret (0usize, Invalid) }
    j = 0usize
    while j < cols {
        if (word[j] & 1u8) == 0u8 { channel[j] = 1.0f64 } else { channel[j] = 0.0f64 - 1.0f64 }
        j += 1usize
    }
    var it = 0usize
    while it < iterations {
        var i = 0usize
        while i < rows {
            // Variable-to-check beliefs for this row, then the min-sum reply.
            j = 0usize
            while j < cols {
                if h[i * cols + j] != 0u8 {
                    var v = channel[j]
                    var i2 = 0usize
                    while i2 < rows {
                        if i2 != i && h[i2 * cols + j] != 0u8 { v += messages[i2 * cols + j] }
                        i2 += 1usize
                    }
                    messages[rows * cols + j] = v
                }
                j += 1usize
            }
            j = 0usize
            while j < cols {
                if h[i * cols + j] != 0u8 {
                    var sign = 1.0f64
                    var smallest = 1000000000.0f64
                    var j2 = 0usize
                    while j2 < cols {
                        if j2 != j && h[i * cols + j2] != 0u8 {
                            let v = messages[rows * cols + j2]
                            if v < 0.0f64 { sign = 0.0f64 - sign }
                            var magnitude = v
                            if magnitude < 0.0f64 { magnitude = 0.0f64 - magnitude }
                            if magnitude < smallest { smallest = magnitude }
                        }
                        j2 += 1usize
                    }
                    messages[i * cols + j] = sign * smallest
                }
                j += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < cols {
            var total = channel[j]
            i = 0usize
            while i < rows {
                if h[i * cols + j] != 0u8 { total += messages[i * cols + j] }
                i += 1usize
            }
            if total >= 0.0f64 { word[j] = 0u8 } else { word[j] = 1u8 }
            j += 1usize
        }
        it += 1usize
        if ldpc_check(h, rows, cols, word) { ret (it, ok) }
    }
    ret (iterations, Invalid)
}

// Hamming(7,4): bit p - 1 of the word is position p; parity at positions 1,
// 2, 4 and the nibble's bits at 3, 5, 6, 7.
fn hamming_encode(nibble: u8) -> u8 {
    let d0 = nibble & 1u8
    let d1 = (nibble >> 1u32) & 1u8
    let d2 = (nibble >> 2u32) & 1u8
    let d3 = (nibble >> 3u32) & 1u8
    let p1 = d0 ^ d1 ^ d3
    let p2 = d0 ^ d2 ^ d3
    let p4 = d1 ^ d2 ^ d3
    ret p1 | (p2 << 1u32) | (d0 << 2u32) | (p4 << 3u32) | (d1 << 4u32) | (d2 << 5u32) | (d3 << 6u32)
}

// The syndrome of the seven code bits: the position of a single error.
fn hamming_syndrome(word: u8) -> u8 {
    var s = 0u8
    var p = 1u8
    while p <= 7u8 {
        if ((word >> u32(p - 1u8)) & 1u8) != 0u8 { s ^= p }
        p += 1u8
    }
    ret s
}

fn hamming_nibble(word: u8) -> u8 {
    ret ((word >> 2u32) & 1u8) | (((word >> 4u32) & 1u8) << 1u32) | (((word >> 5u32) & 1u8) << 2u32) | (((word >> 6u32) & 1u8) << 3u32)
}

// The nibble of a 7-bit word after fixing at most one flipped bit:
// (nibble, corrected, uncorrectable); the last is always false here.
fn hamming_decode(word: u8) -> (u8, bool, bool) {
    let s = hamming_syndrome(word & 127u8)
    var w = word & 127u8
    if s != 0u8 { w ^= 1u8 << u32(s - 1u8) }
    ret (hamming_nibble(w), s != 0u8, false)
}

// SECDED (8,4): Hamming(7,4) plus an overall parity bit at bit 7.
fn secded_encode(nibble: u8) -> u8 {
    let w = hamming_encode(nibble)
    var parity = 0u8
    var i = 0u32
    while i < 7u32 {
        parity ^= (w >> i) & 1u8
        i += 1u32
    }
    ret w | (parity << 7u32)
}

// (nibble, corrected, uncorrectable): a single flipped bit is fixed, two
// are reported.
fn secded_decode(word: u8) -> (u8, bool, bool) {
    let s = hamming_syndrome(word & 127u8)
    var parity = 0u8
    var i = 0u32
    while i < 8u32 {
        parity ^= (word >> i) & 1u8
        i += 1u32
    }
    var w = word & 127u8
    if parity == 0u8 { ret (hamming_nibble(w), false, s != 0u8) }
    if s != 0u8 { w ^= 1u8 << u32(s - 1u8) }
    ret (hamming_nibble(w), true, false)
}
