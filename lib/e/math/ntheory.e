// Elementary number theory over `u64`: gcd and modular arithmetic, primality,
// sieves and factoring, the Chinese remainder theorem, discrete logarithms,
// modular square roots and the Stern-Brocot and Farey sequences.
//
// Every routine is exact over the full 64-bit range: products are reduced with
// `mul_mod`, which never overflows, and `is_prime` is the deterministic
// Miller-Rabin test with the twelve bases that decide every 64-bit integer. Tables
// are caller storage sized as each declaration states.

error TooSmall
error Invalid

// Stein's binary gcd; `gcd(0, 0)` is 0.
fn gcd(a: u64, b: u64) -> u64 {
    if a == 0u64 { ret b }
    if b == 0u64 { ret a }
    var x = a
    var y = b
    var shift = 0u64
    while ((x | y) & 1u64) == 0u64 {
        x = x >> 1u64
        y = y >> 1u64
        shift += 1u64
    }
    while (x & 1u64) == 0u64 { x = x >> 1u64 }
    while y != 0u64 {
        while (y & 1u64) == 0u64 { y = y >> 1u64 }
        if x > y {
            let swap = x
            x = y
            y = swap
        }
        y = y - x
    }
    ret x << shift
}

// Overflows past `2^64` are the caller's to avoid; `lcm(0, n)` is 0.
fn lcm(a: u64, b: u64) -> u64 {
    if a == 0u64 || b == 0u64 { ret 0u64 }
    ret a / gcd(a, b) * b
}

// `g`, `x`, `y` with `a * x + b * y == g == gcd(a, b)`.
fn extended_gcd(a: i64, b: i64) -> (i64, i64, i64) {
    var old_r = a
    var r = b
    var old_s = 1i64
    var s = 0i64
    var old_t = 0i64
    var t = 1i64
    while r != 0i64 {
        let q = old_r / r
        let next_r = old_r - q * r
        old_r = r
        r = next_r
        let next_s = old_s - q * s
        old_s = s
        s = next_s
        let next_t = old_t - q * t
        old_t = t
        t = next_t
    }
    if old_r < 0i64 { ret (0i64 - old_r, 0i64 - old_s, 0i64 - old_t) }
    ret (old_r, old_s, old_t)
}

// `(a + b) mod m` without overflow; `a` and `b` must already be below `m`.
fn add_mod(a: u64, b: u64, m: u64) -> u64 {
    if a >= m - b { ret a - (m - b) }
    ret a + b
}

// `(a * b) mod m` without overflow, for any `m > 0`.
fn mul_mod(a: u64, b: u64, m: u64) -> u64 {
    var x = a % m
    var y = b % m
    if m <= 4294967296u64 { ret x * y % m }
    var result = 0u64
    while y != 0u64 {
        if (y & 1u64) == 1u64 { result = add_mod(result, x, m) }
        x = add_mod(x, x, m)
        y = y >> 1u64
    }
    ret result
}

// `base^exponent mod m`; `m` must be positive, and `pow_mod(_, 0, 1)` is 0.
fn pow_mod(base: u64, exponent: u64, m: u64) -> u64 {
    if m == 1u64 { ret 0u64 }
    var result = 1u64
    var b = base % m
    var e = exponent
    while e != 0u64 {
        if (e & 1u64) == 1u64 { result = mul_mod(result, b, m) }
        b = mul_mod(b, b, m)
        e = e >> 1u64
    }
    ret result
}

// The inverse of `a` modulo `m`, when `gcd(a, m) == 1`.
fn inverse_mod(a: u64, m: u64) -> (u64, bool) {
    if m == 0u64 { ret (0u64, false) }
    if m == 1u64 { ret (0u64, true) }
    // Euclid over unsigned values, tracking only the coefficient of `a`.
    var old_r = a % m
    var r = m
    var old_s = 1u64
    var s = 0u64
    while r != 0u64 {
        let q = old_r / r
        let next_r = old_r - q * r
        old_r = r
        r = next_r
        // `s` values are kept modulo `m` so they never go negative.
        let next_s = add_mod(old_s, m - mul_mod(q, s, m), m)
        old_s = s
        s = next_s
    }
    if old_r != 1u64 { ret (0u64, false) }
    ret (old_s % m, true)
}

// Deterministic Miller-Rabin over the bases that decide every 64-bit integer.
fn is_prime(n: u64) -> bool {
    if n < 2u64 { ret false }
    var small: [12]u64 = zero
    small[0usize] = 2u64
    small[1usize] = 3u64
    small[2usize] = 5u64
    small[3usize] = 7u64
    small[4usize] = 11u64
    small[5usize] = 13u64
    small[6usize] = 17u64
    small[7usize] = 19u64
    small[8usize] = 23u64
    small[9usize] = 29u64
    small[10usize] = 31u64
    small[11usize] = 37u64
    var i = 0usize
    while i < 12usize {
        if n == small[i] { ret true }
        if n % small[i] == 0u64 { ret false }
        i += 1usize
    }
    var d = n - 1u64
    var s = 0u64
    while (d & 1u64) == 0u64 {
        d = d >> 1u64
        s += 1u64
    }
    i = 0usize
    while i < 12usize {
        var x = pow_mod(small[i], d, n)
        if x != 1u64 && x != n - 1u64 {
            var r = 1u64
            var witness = true
            while r < s {
                x = mul_mod(x, x, n)
                if x == n - 1u64 {
                    witness = false
                    break
                }
                r += 1u64
            }
            if witness { ret false }
        }
        i += 1usize
    }
    ret true
}

// Marks `flags[i]` 1 for every prime `i <= limit`; `flags.len > limit`.
fn sieve(limit: usize, flags: []u8) -> err {
    if flags.len <= limit { ret TooSmall }
    var i = 0usize
    while i <= limit {
        flags[i] = 1u8
        i += 1usize
    }
    flags[0usize] = 0u8
    if limit >= 1usize { flags[1usize] = 0u8 }
    i = 2usize
    while i * i <= limit {
        if flags[i] == 1u8 {
            var j = i * i
            while j <= limit {
                flags[j] = 0u8
                j += i
            }
        }
        i += 1usize
    }
    ret ok
}

// Marks `flags[i]` 1 when `low + i` is prime, for `low + i <= high`;
// `flags.len > high - low` and `scratch.len > sqrt(high)`.
fn sieve_segmented(low: u64, high: u64, flags: []u8, scratch: []u8) -> err {
    if high < low { ret Invalid }
    let span = usize(high - low)
    if flags.len <= span { ret TooSmall }
    var root = 0usize
    while u64(root + 1usize) * u64(root + 1usize) <= high { root += 1usize }
    if scratch.len <= root { ret TooSmall }
    if sieve(root, scratch) != ok { ret TooSmall }
    var i = 0usize
    while i <= span {
        flags[i] = 1u8
        i += 1usize
    }
    var p = 2usize
    while p <= root {
        if scratch[p] == 1u8 {
            var start = u64(p) * u64(p)
            if start < low {
                start = (low + u64(p) - 1u64) / u64(p) * u64(p)
            }
            var j = start
            while j <= high {
                flags[usize(j - low)] = 0u8
                j += u64(p)
            }
        }
        p += 1usize
    }
    if low == 0u64 {
        flags[0usize] = 0u8
        if span >= 1usize { flags[1usize] = 0u8 }
    } else if low == 1u64 {
        flags[0usize] = 0u8
    }
    ret ok
}

// The linear sieve: `spf[i]` is the smallest prime factor of `i` (0 for 0 and 1),
// and the primes up to `limit` are written to `primes` in order; answers how many.
fn sieve_linear(limit: usize, spf: []u32, primes: []u32) -> (usize, err) {
    if spf.len <= limit || limit > 4294967295usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i <= limit {
        spf[i] = 0u32
        i += 1usize
    }
    var count = 0usize
    i = 2usize
    while i <= limit {
        if spf[i] == 0u32 {
            spf[i] = u32(i)
            if count >= primes.len { ret (0usize, TooSmall) }
            primes[count] = u32(i)
            count += 1usize
        }
        var j = 0usize
        while j < count && usize(primes[j]) <= usize(spf[i]) && i * usize(primes[j]) <= limit {
            spf[i * usize(primes[j])] = primes[j]
            j += 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

// Trial division: the distinct prime factors of `n` and their exponents, in order.
// Fifteen slots hold any 64-bit value. Slow past `2^40` when the second-largest
// factor is large; `factor_rho` is the tool there.
fn factor_trial(n: u64, factors: []u64, exponents: []u32) -> (usize, err) {
    var count = 0usize
    var rest = n
    var p = 2u64
    while p * p <= rest {
        if rest % p == 0u64 {
            if count >= factors.len || count >= exponents.len { ret (0usize, TooSmall) }
            factors[count] = p
            exponents[count] = 0u32
            while rest % p == 0u64 {
                rest = rest / p
                exponents[count] += 1u32
            }
            count += 1usize
        }
        if p == 2u64 { p = 3u64 } else { p += 2u64 }
    }
    if rest > 1u64 {
        if count >= factors.len || count >= exponents.len { ret (0usize, TooSmall) }
        factors[count] = rest
        exponents[count] = 1u32
        count += 1usize
    }
    ret (count, ok)
}

// Pollard's rho with Brent's cycle detection: a non-trivial factor of a composite
// `n`, or `n` itself when `n` is prime or below 4.
fn factor_rho(n: u64) -> u64 {
    if n < 4u64 { ret n }
    if (n & 1u64) == 0u64 { ret 2u64 }
    if is_prime(n) { ret n }
    var c = 1u64
    while c < n {
        var y = 2u64
        var x = 0u64
        var ys = 0u64
        var g = 1u64
        var q = 1u64
        var r = 1u64
        while g == 1u64 {
            x = y
            var i = 0u64
            while i < r {
                y = add_mod(mul_mod(y, y, n), c, n)
                i += 1u64
            }
            var k = 0u64
            while k < r && g == 1u64 {
                ys = y
                var batch = r - k
                if batch > 128u64 { batch = 128u64 }
                i = 0u64
                while i < batch {
                    y = add_mod(mul_mod(y, y, n), c, n)
                    var diff = x
                    if y > diff { diff = y - diff } else { diff = diff - y }
                    q = mul_mod(q, diff, n)
                    i += 1u64
                }
                g = gcd(q, n)
                k += batch
            }
            r = r * 2u64
        }
        if g == n {
            // The batch overshot: replay it one step at a time.
            g = 1u64
            while g == 1u64 {
                ys = add_mod(mul_mod(ys, ys, n), c, n)
                var diff = x
                if ys > diff { diff = ys - diff } else { diff = diff - ys }
                g = gcd(diff, n)
            }
        }
        if g != n && g != 1u64 { ret g }
        c += 1u64
    }
    ret n
}

// Pollard's p - 1 with smoothness bound `bound`: a factor `p` of `n` for which
// `p - 1` is `bound`-smooth, when one exists.
fn factor_p_minus_1(n: u64, bound: u64) -> (u64, bool) {
    if n < 4u64 || (n & 1u64) == 0u64 { ret (0u64, false) }
    var a = 2u64
    var p = 2u64
    while p <= bound {
        if is_prime(p) {
            var power = p
            while power * p <= bound { power = power * p }
            a = pow_mod(a, power, n)
            let g = gcd(a - 1u64, n)
            if g == n { ret (0u64, false) }
            if g > 1u64 { ret (g, true) }
        }
        p += 1u64
    }
    ret (0u64, false)
}

// Garner's algorithm over pairwise coprime moduli: the mixed-radix digits go to
// `mixed` (one per modulus) and the answer is the residue modulo their product,
// which must fit a `u64`. `false` when the moduli are not pairwise coprime.
fn crt_garner(residues: []const u64, moduli: []const u64, mixed: []u64) -> (u64, bool) {
    let k = residues.len
    if moduli.len != k || mixed.len < k || k == 0usize { ret (0u64, false) }
    var i = 0usize
    while i < k {
        if moduli[i] == 0u64 { ret (0u64, false) }
        var digit = residues[i] % moduli[i]
        var j = 0usize
        while j < i {
            // digit = (digit - mixed[j]) * inverse(moduli[j]) mod moduli[i]
            let (inv, ok_inv) = inverse_mod(moduli[j] % moduli[i], moduli[i])
            if !ok_inv { ret (0u64, false) }
            let subtracted = add_mod(digit, moduli[i] - mixed[j] % moduli[i], moduli[i])
            digit = mul_mod(subtracted, inv, moduli[i])
            j += 1usize
        }
        mixed[i] = digit
        i += 1usize
    }
    var result = 0u64
    var scale = 1u64
    i = 0usize
    while i < k {
        result += mixed[i] * scale
        scale = scale * moduli[i]
        i += 1usize
    }
    ret (result, true)
}

// The Chinese remainder theorem for pairwise coprime moduli whose product fits a
// `u64`: the unique residue, and that product.
fn crt(residues: []const u64, moduli: []const u64) -> (u64, u64, bool) {
    var mixed: [64]u64 = zero
    if residues.len > 64usize { ret (0u64, 0u64, false) }
    let (value, fine) = crt_garner(residues, moduli, mixed[..])
    if !fine { ret (0u64, 0u64, false) }
    var product = 1u64
    var i = 0usize
    while i < moduli.len {
        product = product * moduli[i]
        i += 1usize
    }
    ret (value, product, true)
}

// Euler's totient by trial factoring.
fn totient(n: u64) -> u64 {
    if n == 0u64 { ret 0u64 }
    var result = n
    var rest = n
    var p = 2u64
    while p * p <= rest {
        if rest % p == 0u64 {
            while rest % p == 0u64 { rest = rest / p }
            result -= result / p
        }
        if p == 2u64 { p = 3u64 } else { p += 2u64 }
    }
    if rest > 1u64 { result -= result / rest }
    ret result
}

// Baby-step giant-step: the least `x` with `base^x == wanted (mod m)`, searching
// `x < bound`. `scratch.len >= 2 * ceil(sqrt(bound))` holds the baby steps as
// (value, index) pairs.
fn discrete_log_bsgs(base: u64, wanted: u64, m: u64, bound: u64, scratch: []u64) -> (u64, bool) {
    if m == 0u64 { ret (0u64, false) }
    if m == 1u64 { ret (0u64, true) }
    let t = wanted % m
    if t == 1u64 % m { ret (0u64, true) }
    var steps = 1u64
    while steps * steps < bound { steps += 1u64 }
    if scratch.len < 2usize * usize(steps) { ret (0u64, false) }
    // Baby steps: base^j for j in 0..steps, sorted by value for binary search.
    var j = 0u64
    var value = 1u64 % m
    while j < steps {
        scratch[2usize * usize(j)] = value
        scratch[2usize * usize(j) + 1usize] = j
        value = mul_mod(value, base % m, m)
        j += 1u64
    }
    // Insertion-free sort: heap sort of the pairs by value.
    let n = usize(steps)
    var start = n / 2usize
    while start > 0usize {
        start -= 1usize
        pairs_sift(scratch, start, n)
    }
    var end = n
    while end > 1usize {
        end -= 1usize
        pairs_swap(scratch, 0usize, end)
        pairs_sift(scratch, 0usize, end)
    }
    // Giant steps: wanted * base^(-steps * i).
    let (inverse_base, invertible) = inverse_mod(base % m, m)
    if !invertible {
        // A non-invertible base: fall back to the baby steps alone.
        j = 0u64
        while j < steps {
            if scratch[2usize * usize(j)] == t { ret (scratch[2usize * usize(j) + 1usize], true) }
            j += 1u64
        }
        ret (0u64, false)
    }
    let giant = pow_mod(inverse_base, steps, m)
    var gamma = t
    var i = 0u64
    while i < steps {
        // Binary search the baby steps for gamma.
        var low = 0usize
        var high = n
        while low < high {
            let middle = low + (high - low) / 2usize
            if scratch[2usize * middle] < gamma { low = middle + 1usize } else { high = middle }
        }
        if low < n && scratch[2usize * low] == gamma {
            // Among equal values the smallest index was kept adjacent; take the least.
            var best = scratch[2usize * low + 1usize]
            var k = low
            while k < n && scratch[2usize * k] == gamma {
                if scratch[2usize * k + 1usize] < best { best = scratch[2usize * k + 1usize] }
                k += 1usize
            }
            let x = i * steps + best
            if x < bound { ret (x, true) }
        }
        gamma = mul_mod(gamma, giant, m)
        i += 1u64
    }
    ret (0u64, false)
}

fn pairs_swap(pairs: []u64, a: usize, b: usize) {
    let v = pairs[2usize * a]
    let i = pairs[2usize * a + 1usize]
    pairs[2usize * a] = pairs[2usize * b]
    pairs[2usize * a + 1usize] = pairs[2usize * b + 1usize]
    pairs[2usize * b] = v
    pairs[2usize * b + 1usize] = i
}

fn pairs_sift(pairs: []u64, at: usize, end: usize) {
    var here = at
    while true {
        let left = here * 2usize + 1usize
        if left >= end { break }
        var largest = left
        let right = left + 1usize
        if right < end && pairs[2usize * right] > pairs[2usize * left] { largest = right }
        if pairs[2usize * largest] <= pairs[2usize * here] { break }
        pairs_swap(pairs, here, largest)
        here = largest
    }
}

// Pohlig-Hellman for a prime modulus `p`: the logarithm of `wanted` to `base`, a
// generator of the group of order `p - 1`, solved prime power by prime power with
// baby-step giant-step on each. `scratch` as for `discrete_log_bsgs` over the
// largest prime factor of `p - 1`.
fn discrete_log_pohlig_hellman(base: u64, wanted: u64, p: u64, scratch: []u64) -> (u64, bool) {
    if p < 2u64 { ret (0u64, false) }
    let order = p - 1u64
    var factors: [16]u64 = zero
    var exponents: [16]u32 = zero
    let (count, factor_error) = factor_trial(order, factors[..], exponents[..])
    if factor_error != ok { ret (0u64, false) }
    var residues: [16]u64 = zero
    var moduli: [16]u64 = zero
    var i = 0usize
    while i < count {
        let q = factors[i]
        var qe = 1u64
        var e = 0u32
        while e < exponents[i] {
            qe = qe * q
            e += 1u32
        }
        // x mod q^e digit by digit.
        var x = 0u64
        var q_power = 1u64
        let base_q = pow_mod(base, order / q, p)
        var k = 0u32
        while k < exponents[i] {
            // h = (wanted * base^-x)^(order / q^(k+1))
            let (inverse_base, invertible) = inverse_mod(base, p)
            if !invertible { ret (0u64, false) }
            let shifted = mul_mod(wanted, pow_mod(inverse_base, x, p), p)
            let h = pow_mod(shifted, order / (q_power * q), p)
            let (digit, found) = discrete_log_bsgs(base_q, h, p, q, scratch)
            if !found { ret (0u64, false) }
            x += digit * q_power
            q_power = q_power * q
            k += 1u32
        }
        residues[i] = x
        moduli[i] = qe
        i += 1usize
    }
    let (value, _, fine) = crt(residues[..count], moduli[..count])
    ret (value, fine)
}

// Pollard's kangaroo: the `x` in `low..=high` with `base^x == wanted (mod m)`,
// expected `O(sqrt(high - low))` steps; a bounded random walk, so it may miss
// and answer `false` for a solution that exists.
fn discrete_log_kangaroo(base: u64, wanted: u64, m: u64, low: u64, high: u64) -> (u64, bool) {
    if m < 2u64 || high < low { ret (0u64, false) }
    let width = high - low
    var k = 1u64
    while k * k < width + 1u64 { k += 1u64 }
    // Jump sizes are powers of two chosen by the low bits of the position.
    var jumps = 0u64
    while (1u64 << jumps) < k { jumps += 1u64 }
    if jumps == 0u64 { jumps = 1u64 }
    let b = base % m
    // Tame kangaroo from base^high.
    var tame_x = high
    var tame_y = pow_mod(b, high, m)
    var steps = 0u64
    let step_limit = 4u64 * k + 16u64
    while steps < step_limit {
        let jump = 1u64 << (tame_y % jumps)
        tame_x += jump
        tame_y = mul_mod(tame_y, pow_mod(b, jump, m), m)
        steps += 1u64
    }
    // Wild kangaroo from the wanted value; every jump advances, so the walk ends.
    var wild_x = 0u64
    var wild_y = wanted % m
    while wild_x <= tame_x - low {
        if wild_y == tame_y {
            if tame_x >= wild_x {
                let x = tame_x - wild_x
                if x >= low && x <= high && pow_mod(b, x, m) == wanted % m { ret (x, true) }
            }
            ret (0u64, false)
        }
        let jump = 1u64 << (wild_y % jumps)
        wild_x += jump
        wild_y = mul_mod(wild_y, pow_mod(b, jump, m), m)
    }
    ret (0u64, false)
}

// Tonelli-Shanks: a square root of `n` modulo an odd prime `p`, when one exists;
// the other root is `p - r`.
fn sqrt_mod(n: u64, p: u64) -> (u64, bool) {
    let a = n % p
    if p == 2u64 { ret (a, true) }
    if a == 0u64 { ret (0u64, true) }
    if pow_mod(a, (p - 1u64) / 2u64, p) != 1u64 { ret (0u64, false) }
    if p % 4u64 == 3u64 { ret (pow_mod(a, (p + 1u64) / 4u64, p), true) }
    var q = p - 1u64
    var s = 0u64
    while (q & 1u64) == 0u64 {
        q = q >> 1u64
        s += 1u64
    }
    var z = 2u64
    while pow_mod(z, (p - 1u64) / 2u64, p) != p - 1u64 { z += 1u64 }
    var m = s
    var c = pow_mod(z, q, p)
    var t = pow_mod(a, q, p)
    var r = pow_mod(a, (q + 1u64) / 2u64, p)
    while t != 1u64 {
        var i = 0u64
        var t2 = t
        while t2 != 1u64 {
            t2 = mul_mod(t2, t2, p)
            i += 1u64
            if i == m { ret (0u64, false) }
        }
        var b = c
        var j = 0u64
        while j + i + 1u64 < m {
            b = mul_mod(b, b, p)
            j += 1u64
        }
        m = i
        c = mul_mod(b, b, p)
        t = mul_mod(t, c, p)
        r = mul_mod(r, b, p)
    }
    ret (r, true)
}

// The fraction with the smallest denominator not above `max_den` that lies within
// `tolerance` of `x`, found by walking the Stern-Brocot tree; `x >= 0`.
fn stern_brocot_search(x: f64, tolerance: f64, max_den: u64) -> (u64, u64) {
    var left_n = 0u64
    var left_d = 1u64
    var right_n = 1u64
    var right_d = 0u64
    while true {
        let n = left_n + right_n
        let d = left_d + right_d
        if d > max_den { break }
        let value = f64(n) / f64(d)
        var gap = value - x
        if gap < 0.0f64 { gap = 0.0f64 - gap }
        if gap <= tolerance { ret (n, d) }
        if value < x {
            left_n = n
            left_d = d
        } else {
            right_n = n
            right_d = d
        }
    }
    // Nothing within tolerance: the closer of the two bounds.
    if right_d == 0u64 { ret (left_n, left_d) }
    var left_gap = x - f64(left_n) / f64(left_d)
    if left_gap < 0.0f64 { left_gap = 0.0f64 - left_gap }
    var right_gap = f64(right_n) / f64(right_d) - x
    if right_gap < 0.0f64 { right_gap = 0.0f64 - right_gap }
    if left_gap <= right_gap { ret (left_n, left_d) }
    ret (right_n, right_d)
}

// The term after `b / d` in the Farey sequence of order `n`, given its predecessor
// `a / c`; starting from `0/1, 1/n` walks the whole sequence to `1/1`.
fn farey_next(a: u64, c: u64, b: u64, d: u64, n: u64) -> (u64, u64) {
    let k = (n + c) / d
    ret (k * b - a, k * d - c)
}

// Writes the Farey sequence of order `n` as numerator/denominator pairs and answers
// how many; `out.len` must be at least twice the count.
fn farey(n: u64, out: []u64) -> (usize, err) {
    if n == 0u64 { ret (0usize, Invalid) }
    var count = 0usize
    var a = 0u64
    var c = 1u64
    var b = 1u64
    var d = n
    if out.len < 4usize { ret (0usize, TooSmall) }
    out[0usize] = a
    out[1usize] = c
    count = 1usize
    while b <= d {
        if 2usize * (count + 1usize) > out.len { ret (0usize, TooSmall) }
        out[2usize * count] = b
        out[2usize * count + 1usize] = d
        count += 1usize
        if b == d { break }
        let (e, f) = farey_next(a, c, b, d, n)
        a = b
        c = d
        b = e
        d = f
    }
    ret (count, ok)
}
