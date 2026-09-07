// Deterministic pseudorandom generators. None of these is cryptographic: the state
// is fully recoverable from the output and is meant to be, because reproducing a run
// exactly is the point.
//
// Each generator is a named published algorithm rather than a variation on one, so a
// stream produced here matches the reference implementation bit for bit and a seed
// carries between languages. D91 records which variant each name is.

type Pcg64 = struct {
    state: u64,
    stream: u64,
}

type Xoshiro256 = struct {
    s0: u64,
    s1: u64,
    s2: u64,
    s3: u64,
}

type Mt19937 = struct {
    state: [624]u32,
    index: u32,
}

// PCG, `setseq_64_rxs_m_xs_64`: 64 bits of state, 64 bits out, and a stream selector
// that picks one of 2**63 distinct sequences. `stream` holds the odd increment the
// selector becomes, which is what makes two streams from one seed independent.
fn pcg64(seed: u64, stream: u64) -> Pcg64 {
    var r: Pcg64 = zero
    r.state = 0u64
    r.stream = (stream << 1u64) | 1u64
    r.state = r.state *% 6364136223846793005u64 +% r.stream
    r.state = r.state +% seed
    r.state = r.state *% 6364136223846793005u64 +% r.stream
    ret r
}

fn pcg64_next(r: *Pcg64) -> u64 {
    // The output function reads the state the step started from, so the value handed
    // out is never the state the generator is left in.
    let previous = r.state
    r.state = r.state *% 6364136223846793005u64 +% r.stream
    let shift = (previous >> 59u64) + 5u64
    let mixed = (previous >> shift) ^ previous
    let word = mixed *% 12605985483714917081u64
    let folded = word >> 43u64
    ret folded ^ word
}

// Unbiased by rejection: `2**64 % upper` low values would otherwise have one more
// representative than the rest, so a draw below that many is thrown away.
fn pcg64_bounded(r: *Pcg64, upper: u64) -> u64 {
    if upper == 0u64 { ret 0u64 }
    let threshold = (0u64 -% upper) % upper
    while true {
        let draw = pcg64_next(r)
        if draw >= threshold { ret draw % upper }
    }
    ret 0u64
}

// The top 53 bits over 2**53, which is every double in [0, 1) with the same spacing
// and no rounding.
fn pcg64_f64(r: *Pcg64) -> f64 {
    let draw = pcg64_next(r)
    ret f64(draw >> 11u64) / 9007199254740992.0f64
}

// xoshiro256**, the general-purpose member of the family. The four words are the
// state itself; an all-zero state is the one the generator cannot leave, so it is
// replaced rather than accepted.
fn xoshiro256(seed: [4]u64) -> Xoshiro256 {
    var r: Xoshiro256 = zero
    r.s0 = seed[0usize]
    r.s1 = seed[1usize]
    r.s2 = seed[2usize]
    r.s3 = seed[3usize]
    if r.s0 == 0u64 && r.s1 == 0u64 && r.s2 == 0u64 && r.s3 == 0u64 {
        r.s0 = 11400714819323198485u64
        r.s1 = 14029467366897019727u64
        r.s2 = 1609587929392839161u64
        r.s3 = 9650029242287828579u64
    }
    ret r
}

fn xoshiro256_next(r: *Xoshiro256) -> u64 {
    let scaled = r.s1 *% 5u64
    let rotated = (scaled << 7u64) | (scaled >> 57u64)
    let result = rotated *% 9u64
    let lifted = r.s1 << 17u64
    r.s2 = r.s2 ^ r.s0
    r.s3 = r.s3 ^ r.s1
    r.s1 = r.s1 ^ r.s2
    r.s0 = r.s0 ^ r.s3
    r.s2 = r.s2 ^ lifted
    r.s3 = (r.s3 << 45u64) | (r.s3 >> 19u64)
    ret result
}

fn xoshiro256_bounded(r: *Xoshiro256, upper: u64) -> u64 {
    if upper == 0u64 { ret 0u64 }
    let threshold = (0u64 -% upper) % upper
    while true {
        let draw = xoshiro256_next(r)
        if draw >= threshold { ret draw % upper }
    }
    ret 0u64
}

fn xoshiro256_f64(r: *Xoshiro256) -> f64 {
    let draw = xoshiro256_next(r)
    ret f64(draw >> 11u64) / 9007199254740992.0f64
}

// MT19937, seeded the way the reference `init_genrand` does. `index` counts words
// consumed from the current block; starting it at the block size means the first
// call twists before it reads.
fn mt19937(seed: u32) -> Mt19937 {
    var r: Mt19937 = zero
    r.state[0usize] = seed
    var at = 1usize
    while at < 624usize {
        let previous = r.state[at - 1usize]
        let mixed = previous ^ (previous >> 30u32)
        r.state[at] = 1812433253u32 *% mixed +% u32(at)
        at += 1usize
    }
    r.index = 624u32
    ret r
}

fn mt19937_next(r: *Mt19937) -> u32 {
    if r.index >= 624u32 {
        // The twist, over the whole block at once.
        var at = 0usize
        while at < 624usize {
            var following = at + 1usize
            if following == 624usize { following = 0usize }
            var offset = at + 397usize
            if offset >= 624usize { offset = offset - 624usize }
            let joined = (r.state[at] & 2147483648u32) | (r.state[following] & 2147483647u32)
            var twisted = r.state[offset] ^ (joined >> 1u32)
            if joined % 2u32 == 1u32 { twisted = twisted ^ 2567483615u32 }
            r.state[at] = twisted
            at += 1usize
        }
        r.index = 0u32
    }
    var word = r.state[usize(r.index)]
    r.index += 1u32
    // The tempering, which is what makes the output equidistributed.
    word = word ^ (word >> 11u32)
    word = word ^ ((word << 7u32) & 2636928640u32)
    word = word ^ ((word << 15u32) & 4022730752u32)
    ret word ^ (word >> 18u32)
}
