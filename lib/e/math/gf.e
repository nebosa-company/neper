// Arithmetic over GF(2^8) with the caller's reducing polynomial (its low
// eight bits, the x^8 term implied: 0x1b for AES, 0x1d for Reed-Solomon),
// and carry-less multiplication of binary polynomials up to 64 bits.
//
// Addition is exclusive-or. `mul` is the shift-and-add product, `tables`
// builds exponent and logarithm tables over a generator for the fast form
// `mul_table`, and `inverse` is the 254th power.

error Invalid
error TooSmall

fn add(a: u8, b: u8) -> u8 { ret a ^ b }

// The product in GF(2^8) modulo x^8 + `polynomial`.
fn mul(a: u8, b: u8, polynomial: u8) -> u8 {
    var x = u32(a)
    var y = u32(b)
    var product = 0u32
    while y != 0u32 {
        if (y & 1u32) != 0u32 { product ^= x }
        y = y >> 1u32
        x = x << 1u32
        if (x & 256u32) != 0u32 { x ^= 256u32 | u32(polynomial) }
    }
    ret u8(product & 255u32)
}

fn pow(a: u8, exponent: u32, polynomial: u8) -> u8 {
    var result = 1u8
    var base = a
    var e = exponent
    while e != 0u32 {
        if (e & 1u32) != 0u32 { result = mul(result, base, polynomial) }
        base = mul(base, base, polynomial)
        e = e >> 1u32
    }
    ret result
}

// The multiplicative inverse; zero answers `Invalid`.
fn inverse(a: u8, polynomial: u8) -> (u8, err) {
    if a == 0u8 { ret (0u8, Invalid) }
    ret (pow(a, 254u32, polynomial), ok)
}

// Exponent and logarithm tables over `generator` (a primitive element such
// as 3 for AES or 2 for Reed-Solomon): `exp[i] = generator^i` for `i < 255`
// with `exp[255..510]` repeating it, and `log[exp[i]] = i`. A generator that
// does not reach every nonzero element answers `Invalid`;
// `exp.len >= 510`, `log.len >= 256`.
fn tables(generator: u8, polynomial: u8, exp: []u8, log: []u8) -> err {
    if exp.len < 510usize || log.len < 256usize { ret TooSmall }
    log[0usize] = 0u8
    var x = 1u8
    var i = 0usize
    while i < 255usize {
        // The powers cycle back through 1 first, so a short order shows there.
        if x == 1u8 && i != 0usize { ret Invalid }
        exp[i] = x
        log[usize(x)] = u8(i)
        x = mul(x, generator, polynomial)
        i += 1usize
    }
    if x != 1u8 { ret Invalid }
    i = 255usize
    while i < 510usize {
        exp[i] = exp[i - 255usize]
        i += 1usize
    }
    ret ok
}

// The product through tables from `tables`.
fn mul_table(a: u8, b: u8, exp: []const u8, log: []const u8) -> u8 {
    if a == 0u8 || b == 0u8 { ret 0u8 }
    ret exp[usize(log[usize(a)]) + usize(log[usize(b)])]
}

// Carry-less multiplication of two 64-bit polynomials: the 128-bit product
// as (high, low).
fn clmul(a: u64, b: u64) -> (u64, u64) {
    var low = 0u64
    var high = 0u64
    var i = 0u32
    while i < 64u32 {
        if ((b >> i) & 1u64) != 0u64 {
            low ^= a << i
            if i != 0u32 { high ^= a >> (64u32 - i) }
        }
        i += 1u32
    }
    ret (high, low)
}

// Reduce a 128-bit polynomial (high, low) modulo x^64 + `polynomial`, the
// low sixty-four bits of the modulus with the x^64 term implied.
fn reduce(high: u64, low: u64, polynomial: u64) -> u64 {
    var h = high
    var l = low
    var bit = 64u32
    while bit > 0u32 {
        bit -= 1u32
        if ((h >> bit) & 1u64) != 0u64 {
            h ^= 1u64 << bit
            // x^(64 + bit) = x^bit * polynomial, split across the two words.
            l ^= polynomial << bit
            if bit != 0u32 { h ^= polynomial >> (64u32 - bit) }
        }
    }
    ret l
}
