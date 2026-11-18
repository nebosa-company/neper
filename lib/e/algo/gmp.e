// R gmp over e.algo.bignum: lcm, modular inverse, a Miller-Rabin primality test, next prime, binomial, factorial, Fibonacci and Lucas numbers, factorize
// and the digit count in a base. The arithmetic itself (add, sub, mul, divmod, gcd, powm, parse, format) is e.algo.bignum.
//
// factorize (trial division, then factor_ecm for what is left) is here too. Not here: bigq beyond e.algo.bignum.Rat, the vectorised
// and matrix forms, and the random generators.

use e.algo.bignum as bn
use e.mem
use e.str

error Invalid

fn small(a: *mem.Arena, v: u64) -> (bn.Int, err) {
    let (r, e) = bn.int_from_i64(a, i64(v))
    ret (r, e)
}

fn is_one(v: bn.Int) -> bool { ret v.sign == .Positive && v.limbs.len == 1usize && v.limbs[0usize] == 1u32 }

fn lcm(a: *mem.Arena, x: bn.Int, y: bn.Int) -> (bn.Int, err) {
    let (g, e1) = bn.int_gcd(a, x, y)
    if e1 != ok { ret (zero, e1) }
    let (p, e2) = bn.int_mul(a, x, y)
    if e2 != ok { ret (zero, e2) }
    let (q, _, e3) = bn.int_divmod(a, p, g)
    if e3 != ok { ret (zero, e3) }
    if q.sign == .Negative {
        let (z, e4) = small(a, 0u64)
        if e4 != ok { ret (zero, e4) }
        let (n, e5) = bn.int_sub(a, z, q)
        ret (n, e5)
    }
    ret (q, ok)
}

// the inverse of x modulo m (m > 1), or Invalid when they share a factor
fn inverse(a: *mem.Arena, x: bn.Int, m: bn.Int) -> (bn.Int, err) {
    let (_, red, e0) = bn.int_divmod(a, x, m)
    if e0 != ok { ret (zero, e0) }
    var r0 = m
    var r1 = red
    if r1.sign == .Negative {
        let (f, ef) = bn.int_add(a, r1, m)
        if ef != ok { ret (zero, ef) }
        r1 = f
    }
    var t0 = bn.int_zero(a)
    let (one, e1) = small(a, 1u64)
    if e1 != ok { ret (zero, e1) }
    var t1 = one
    while r1.sign != .Zero {
        let (q, r2, e2) = bn.int_divmod(a, r0, r1)
        if e2 != ok { ret (zero, e2) }
        let (qt, e3) = bn.int_mul(a, q, t1)
        if e3 != ok { ret (zero, e3) }
        let (t2, e4) = bn.int_sub(a, t0, qt)
        if e4 != ok { ret (zero, e4) }
        r0 = r1
        r1 = r2
        t0 = t1
        t1 = t2
    }
    if !is_one(r0) { ret (zero, Invalid) }
    if t0.sign == .Negative {
        let (f, ef) = bn.int_add(a, t0, m)
        ret (f, ef)
    }
    ret (t0, ok)
}

fn small_prime(i: usize) -> u64 {
    if i == 0usize { ret 2u64 }
    if i == 1usize { ret 3u64 }
    if i == 2usize { ret 5u64 }
    if i == 3usize { ret 7u64 }
    if i == 4usize { ret 11u64 }
    if i == 5usize { ret 13u64 }
    if i == 6usize { ret 17u64 }
    if i == 7usize { ret 19u64 }
    if i == 8usize { ret 23u64 }
    if i == 9usize { ret 29u64 }
    if i == 10usize { ret 31u64 }
    ret 37u64
}

// Miller-Rabin over the first twelve primes (deterministic below 3.3e24, a strong probable-prime test beyond)
fn is_prime(a: *mem.Arena, n: bn.Int) -> (bool, err) {
    if n.sign != .Positive { ret (false, ok) }
    let (one, e1) = small(a, 1u64)
    if e1 != ok { ret (false, e1) }
    if bn.int_cmp(n, one) <= 0i32 { ret (false, ok) }
    var i = 0usize
    while i < 12usize {
        let (p, e2) = small(a, small_prime(i))
        if e2 != ok { ret (false, e2) }
        if bn.int_cmp(n, p) == 0i32 { ret (true, ok) }
        let (_, r, e3) = bn.int_divmod(a, n, p)
        if e3 != ok { ret (false, e3) }
        if r.sign == .Zero { ret (false, ok) }
        i += 1usize
    }
    let (nm1, e4) = bn.int_sub(a, n, one)
    if e4 != ok { ret (false, e4) }
    let (two, e5) = small(a, 2u64)
    if e5 != ok { ret (false, e5) }
    var d = nm1
    var s = 0usize
    while (d.limbs[0usize] & 1u32) == 0u32 {
        let (q, _, e6) = bn.int_divmod(a, d, two)
        if e6 != ok { ret (false, e6) }
        d = q
        s += 1usize
    }
    i = 0usize
    while i < 12usize {
        let (base, e7) = small(a, small_prime(i))
        if e7 != ok { ret (false, e7) }
        var (x, e8) = bn.int_mod_pow(a, base, d, n)
        if e8 != ok { ret (false, e8) }
        if !(is_one(x) || bn.int_cmp(x, nm1) == 0i32) {
            var composite = true
            var r = 1usize
            while r < s && composite {
                let (sq, e9) = bn.int_mul(a, x, x)
                if e9 != ok { ret (false, e9) }
                let (_, red, e10) = bn.int_divmod(a, sq, n)
                if e10 != ok { ret (false, e10) }
                x = red
                if bn.int_cmp(x, nm1) == 0i32 { composite = false }
                r += 1usize
            }
            if composite { ret (false, ok) }
        }
        i += 1usize
    }
    ret (true, ok)
}

fn next_prime(a: *mem.Arena, n: bn.Int) -> (bn.Int, err) {
    let (one, e1) = small(a, 1u64)
    if e1 != ok { ret (zero, e1) }
    var c = n
    while true {
        let (nx, e2) = bn.int_add(a, c, one)
        if e2 != ok { ret (zero, e2) }
        c = nx
        let (p, e3) = is_prime(a, c)
        if e3 != ok { ret (zero, e3) }
        if p { ret (c, ok) }
    }
    ret (c, ok)
}

fn fib_luc(a: *mem.Arena, n: u64, lucas: bool) -> (bn.Int, err) {
    var x = bn.int_zero(a)
    let (one, e1) = small(a, 1u64)
    if e1 != ok { ret (zero, e1) }
    var y = one
    if lucas {
        let (two, e2) = small(a, 2u64)
        if e2 != ok { ret (zero, e2) }
        x = two
    }
    var i = 0u64
    while i < n {
        let (s, e3) = bn.int_add(a, x, y)
        if e3 != ok { ret (zero, e3) }
        x = y
        y = s
        i += 1u64
    }
    ret (x, ok)
}

fn factorial(a: *mem.Arena, n: u64) -> (bn.Int, err) {
    let (one, e1) = small(a, 1u64)
    if e1 != ok { ret (zero, e1) }
    var r = one
    var i = 2u64
    while i <= n {
        let (f, e2) = small(a, i)
        if e2 != ok { ret (zero, e2) }
        let (p, e3) = bn.int_mul(a, r, f)
        if e3 != ok { ret (zero, e3) }
        r = p
        i += 1u64
    }
    ret (r, ok)
}

fn binomial(a: *mem.Arena, n: u64, k: u64) -> (bn.Int, err) {
    let (one, e1) = small(a, 1u64)
    if e1 != ok { ret (zero, e1) }
    var r = one
    var kk = k
    if n - k < kk { kk = n - k }
    var i = 1u64
    while i <= kk {
        let (f, e2) = small(a, n - kk + i)
        if e2 != ok { ret (zero, e2) }
        let (g, e3) = small(a, i)
        if e3 != ok { ret (zero, e3) }
        let (p, e4) = bn.int_mul(a, r, f)
        if e4 != ok { ret (zero, e4) }
        let (q, _, e5) = bn.int_divmod(a, p, g)
        if e5 != ok { ret (zero, e5) }
        r = q
        i += 1u64
    }
    ret (r, ok)
}

// the number of digits of v in the base (gmp sizeinbase)
fn size_in_base(a: *mem.Arena, v: bn.Int, radix: u8) -> (usize, err) {
    let (b0, e0) = str.builder(a, 64usize)
    if e0 != ok { ret (0usize, e0) }
    var b = b0
    let e = bn.int_format(v, &b, radix)
    if e != ok { ret (0usize, e) }
    ret (b.len, ok)
}

// v modulo 10^9 as a number
fn mod_1e9(a: *mem.Arena, v: bn.Int) -> (u64, err) {
    let (m, e1) = small(a, 1000000000u64)
    if e1 != ok { ret (0u64, e1) }
    let (_, r, e2) = bn.int_divmod(a, v, m)
    if e2 != ok { ret (0u64, e2) }
    if r.sign == .Zero { ret (0u64, ok) }
    ret (u64(r.limbs[0usize]), ok)
}

// the prime factors of n (n > 1) into out, ascending with multiplicity; returns how many. Trial division by 2 to 999 takes the small ones; what
// is left is split by factor_ecm (several curves and seeds) and each cofactor is decided by is_prime. Fails with Invalid when a split gives up.
fn factorize(a: *mem.Arena, n: bn.Int, out: []bn.Int) -> (usize, err) {
    var count = 0usize
    let (one, e0) = small(a, 1u64)
    if e0 != ok { ret (0usize, e0) }
    var work = n
    var p = 2u64
    while p < 1000u64 {
        let (pi, e1) = small(a, p)
        if e1 != ok { ret (0usize, e1) }
        var more = true
        while more {
            let (q, r, e2) = bn.int_divmod(a, work, pi)
            if e2 != ok { ret (0usize, e2) }
            if r.sign != .Zero || work.sign == .Zero {
                more = false
            } else {
                if count >= out.len { ret (0usize, Invalid) }
                out[count] = pi
                count += 1usize
                work = q
            }
            if bn.int_cmp(work, one) <= 0i32 { more = false }
        }
        p += 1u64
    }
    if bn.int_cmp(work, one) <= 0i32 { ret (count, ok) }
    // the composites still to split, and the primes found among them
    let (pend, e3) = mem.alloc[bn.Int](a, 128usize)
    if e3 != ok { ret (0usize, e3) }
    var np = 1usize
    pend[0usize] = work
    while np > 0usize {
        np -= 1usize
        let x = pend[np]
        let (prime, e4) = is_prime(a, x)
        if e4 != ok { ret (0usize, e4) }
        if prime {
            if count >= out.len { ret (0usize, Invalid) }
            out[count] = x
            count += 1usize
        } else {
            let (d, e5) = split(a, x)
            if e5 != ok { ret (0usize, e5) }
            let (q, _, e6) = bn.int_divmod(a, x, d)
            if e6 != ok { ret (0usize, e6) }
            if np + 2usize > pend.len { ret (0usize, Invalid) }
            pend[np] = d
            pend[np + 1usize] = q
            np += 2usize
        }
    }
    // insertion sort into ascending order
    var i = 1usize
    while i < count {
        var j = i
        while j > 0usize && bn.int_cmp(out[j - 1usize], out[j]) > 0i32 {
            let t = out[j]
            out[j] = out[j - 1usize]
            out[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

// x to the power k (k >= 1)
fn ipow(a: *mem.Arena, x: bn.Int, k: usize) -> (bn.Int, err) {
    var p = x
    var j = 1usize
    while j < k {
        let (t, e) = bn.int_mul(a, p, x)
        if e != ok { ret (x, e) }
        p = t
        j += 1usize
    }
    ret (p, ok)
}

// the floor of the k-th root of x (Newton's iteration from x, which decreases to it)
fn iroot(a: *mem.Arena, x: bn.Int, k: usize) -> (bn.Int, err) {
    let (kk, e0) = small(a, u64(k))
    if e0 != ok { ret (x, e0) }
    let (km1, e1) = small(a, u64(k - 1usize))
    if e1 != ok { ret (x, e1) }
    var s = x
    var it = 0usize
    while it < 4000usize {
        let (p, e2) = ipow(a, s, k - 1usize)
        if e2 != ok { ret (x, e2) }
        let (q, _, e3) = bn.int_divmod(a, x, p)
        if e3 != ok { ret (x, e3) }
        let (m, e4) = bn.int_mul(a, km1, s)
        if e4 != ok { ret (x, e4) }
        let (num, e5) = bn.int_add(a, m, q)
        if e5 != ok { ret (x, e5) }
        let (t, _, e6) = bn.int_divmod(a, num, kk)
        if e6 != ok { ret (x, e6) }
        if bn.int_cmp(t, s) >= 0i32 { break }
        s = t
        it += 1usize
    }
    ret (s, ok)
}

// a proper divisor of the odd composite x: a root when x is a perfect power (factor_ecm does not split p^k), else factor_ecm
// over up to 60 seeds of 16 curves each (a seed that finds nothing reports NotFound and the next one is tried)
fn split(a: *mem.Arena, x: bn.Int) -> (bn.Int, err) {
    let (one, e0) = small(a, 1u64)
    if e0 != ok { ret (x, e0) }
    var k = 2usize
    while k <= 128usize {
        let (r, er) = iroot(a, x, k)
        if er != ok { ret (x, er) }
        if bn.int_cmp(r, one) <= 0i32 { break }
        let (pk, ep) = ipow(a, r, k)
        if ep != ok { ret (x, ep) }
        if bn.int_cmp(pk, x) == 0i32 { ret (r, ok) }
        k += 1usize
    }
    var seed = 1u64
    while seed <= 60u64 {
        let (d, e1) = bn.factor_ecm(a, x, 2000u64, 16usize, seed)
        if e1 == ok && bn.int_cmp(d, one) > 0i32 && bn.int_cmp(d, x) < 0i32 { ret (d, ok) }
        seed += 1u64
    }
    let (rd, er) = rho(a, x)
    if er != ok { ret (x, er) }
    ret (rd, ok)
}

// x -> x * x + c (mod n)
fn rho_step(a: *mem.Arena, x: bn.Int, c: bn.Int, n: bn.Int) -> (bn.Int, err) {
    let (sq, e1) = bn.int_mul(a, x, x)
    if e1 != ok { ret (x, e1) }
    let (_, r1, e2) = bn.int_divmod(a, sq, n)
    if e2 != ok { ret (x, e2) }
    let (t, e3) = bn.int_add(a, r1, c)
    if e3 != ok { ret (x, e3) }
    let (_, r2, e4) = bn.int_divmod(a, t, n)
    ret (r2, e4)
}

// Pollard's rho with Floyd's cycle finding, for the composites ECM does not split (small factors): a proper divisor of x or Invalid
fn rho(a: *mem.Arena, x: bn.Int) -> (bn.Int, err) {
    let (one, e0) = small(a, 1u64)
    if e0 != ok { ret (x, e0) }
    let (two, e1) = small(a, 2u64)
    if e1 != ok { ret (x, e1) }
    var c = 1u64
    while c <= 8u64 {
        let (cc, e2) = small(a, c)
        if e2 != ok { ret (x, e2) }
        var xv = two
        var yv = two
        var d = one
        var it = 0usize
        while bn.int_cmp(d, one) == 0i32 && it < 2000000usize {
            let (x1, f1) = rho_step(a, xv, cc, x)
            if f1 != ok { ret (x, f1) }
            xv = x1
            let (y1, f2) = rho_step(a, yv, cc, x)
            if f2 != ok { ret (x, f2) }
            let (y2, f3) = rho_step(a, y1, cc, x)
            if f3 != ok { ret (x, f3) }
            yv = y2
            var diff = yv
            if bn.int_cmp(xv, yv) >= 0i32 { diff = xv }
            var other = xv
            if bn.int_cmp(xv, yv) >= 0i32 { other = yv } else { other = xv }
            let (df, f4) = bn.int_sub(a, diff, other)
            if f4 != ok { ret (x, f4) }
            let (g, f5) = bn.int_gcd(a, df, x)
            if f5 != ok { ret (x, f5) }
            d = g
            it += 1usize
        }
        if bn.int_cmp(d, one) > 0i32 && bn.int_cmp(d, x) < 0i32 { ret (d, ok) }
        c += 1u64
    }
    ret (x, Invalid)
}
