// Shamir's secret sharing byte-wise over GF(2^8) with the AES polynomial
// x^8 + x^4 + x^3 + x + 1 (0x11b), the libgfshare/ssss convention: each secret
// byte is the constant term of its own random degree-(k-1) polynomial, and
// share i (1 <= i <= n) holds every polynomial evaluated at x = i. `split` is
// deterministic over caller-supplied coefficients so a fixture can replay it;
// `split_random` draws them from the system CSPRNG (`os.random`). `combine` interpolates at 0
// from any k shares (Lagrange); fewer than k shares answer garbage, not an error.

use e.algo.rand
use e.os

error Invalid
error TooSmall

// GF(2^8) product by shift-and-reduce.
fn gf_mul(a: u8, b: u8) -> u8 {
    var x = u32(a)
    var y = u32(b)
    var r = 0u32
    while y != 0u32 {
        if (y & 1u32) == 1u32 { r = r ^ x }
        x = x << 1u32
        if (x & 256u32) != 0u32 { x = x ^ 283u32 }
        y = y >> 1u32
    }
    ret u8(r & 255u32)
}

// The inverse as a^254 (a^255 = 1 for every nonzero a); `gf_inv(0)` is 0.
fn gf_inv(a: u8) -> u8 {
    var r = 1u8
    var i = 0usize
    while i < 254usize {
        r = gf_mul(r, a)
        i += 1usize
    }
    ret r
}

// Bytes `shares` needs for `n` shares of a `len`-byte secret.
fn share_size(len: usize, n: u8) -> usize { ret len * usize(n) }

// `coefficients` holds (k-1) * secret.len bytes: for secret byte j the
// coefficients of x^1 .. x^(k-1) sit at j*(k-1) .. (j+1)*(k-1). `shares`
// receives n rows of secret.len bytes; row i-1 is share x = i.
fn split(secret: []const u8, n: u8, k: u8, coefficients: []const u8, shares: []u8) -> err {
    if k < 2u8 || k > n { ret Invalid }
    let degree = usize(k) - 1usize
    if coefficients.len != degree * secret.len { ret Invalid }
    if shares.len < share_size(secret.len, n) { ret TooSmall }
    var i = 0usize
    while i < usize(n) {
        let x = u8(i + 1usize)
        var j = 0usize
        while j < secret.len {
            // Horner from the top coefficient down to the constant term.
            var acc = 0u8
            var d = degree
            while d > 0usize {
                acc = gf_mul(acc, x) ^ coefficients[j * degree + d - 1usize]
                d -= 1usize
            }
            shares[i * secret.len + j] = gf_mul(acc, x) ^ secret[j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// `split` with the coefficients drawn from the system CSPRNG (`os.random`),
// secret byte by secret byte, so every share sees the same polynomial.
fn split_random(secret: []const u8, n: u8, k: u8, shares: []u8) -> err {
    if k < 2u8 || k > n { ret Invalid }
    let degree = usize(k) - 1usize
    if shares.len < share_size(secret.len, n) { ret TooSmall }
    var terms: [254]u8 = zero
    var j = 0usize
    while j < secret.len {
        let random_error = os.random(terms[0usize..degree])
        if random_error != ok { ret random_error }
        var i = 0usize
        while i < usize(n) {
            let x = u8(i + 1usize)
            var acc = 0u8
            var d = degree
            while d > 0usize {
                acc = gf_mul(acc, x) ^ terms[d - 1usize]
                d -= 1usize
            }
            shares[i * secret.len + j] = gf_mul(acc, x) ^ secret[j]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// The deterministic test-only variant: coefficients drawn from `rng` (the low
// byte of each draw), so a fixture can replay the exact shares.
fn split_random_seeded(secret: []const u8, n: u8, k: u8, rng: *rand.Pcg64, shares: []u8) -> err {
    if k < 2u8 || k > n { ret Invalid }
    let degree = usize(k) - 1usize
    if shares.len < share_size(secret.len, n) { ret TooSmall }
    var terms: [254]u8 = zero
    var j = 0usize
    while j < secret.len {
        var d = 0usize
        while d < degree {
            terms[d] = u8(rand.pcg64_next(rng) & 255u64)
            d += 1usize
        }
        var i = 0usize
        while i < usize(n) {
            let x = u8(i + 1usize)
            var acc = 0u8
            d = degree
            while d > 0usize {
                acc = gf_mul(acc, x) ^ terms[d - 1usize]
                d -= 1usize
            }
            shares[i * secret.len + j] = gf_mul(acc, x) ^ secret[j]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// Reconstruct `len` secret bytes from k shares: `xs[i]` is share i's x (1..n),
// `shares` its k rows of `len` bytes in the same order. Any duplicate x or a
// zero x is `Invalid`.
fn combine(xs: []const u8, shares: []const u8, len: usize, out: []u8) -> err {
    let k = xs.len
    if k < 1usize || shares.len != k * len { ret Invalid }
    if out.len < len { ret TooSmall }
    // Lagrange basis at 0: l_i = prod_{m != i} x_m / (x_i ^ x_m).
    var basis: [255]u8 = zero
    if k > 255usize { ret Invalid }
    var i = 0usize
    while i < k {
        if xs[i] == 0u8 { ret Invalid }
        var num = 1u8
        var den = 1u8
        var m = 0usize
        while m < k {
            if m != i {
                if xs[m] == xs[i] { ret Invalid }
                num = gf_mul(num, xs[m])
                den = gf_mul(den, xs[i] ^ xs[m])
            }
            m += 1usize
        }
        basis[i] = gf_mul(num, gf_inv(den))
        i += 1usize
    }
    var j = 0usize
    while j < len {
        var acc = 0u8
        i = 0usize
        while i < k {
            acc = acc ^ gf_mul(shares[i * len + j], basis[i])
            i += 1usize
        }
        out[j] = acc
        j += 1usize
    }
    ret ok
}
