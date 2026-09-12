// ChaCha20 (RFC 8439) as a deterministic random stream: the block function keyed and
// nonced by the caller, one 64-byte block at a time, the counter never wrapping --
// the request that would need a block past counter 2^32 - 1 is `Exhausted` before any
// block is reused. `bounded` draws by rejection so every value below `upper` is
// equally likely.

type ChaCha20 = struct { key: [32]u8, nonce: [12]u8, counter: u32, block: [64]u8, used: u8 }
error Exhausted

fn chacha20_init(key: [32]u8, nonce: [12]u8, counter: u32) -> ChaCha20 {
    var r: ChaCha20 = zero
    r.key = key
    r.nonce = nonce
    r.counter = counter
    r.used = 64u8
    ret r
}

fn load_le32(bytes: []const u8, at: usize) -> u32 {
    let low = u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32)
    ret low | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn rotl(x: u32, n: u32) -> u32 {
    let high = x << n
    ret high | (x >> (32u32 - n))
}

fn quarter(state: []u32, a: usize, b: usize, c: usize, d: usize) {
    state[a] = state[a] +% state[b]
    state[d] = rotl(state[d] ^ state[a], 16u32)
    state[c] = state[c] +% state[d]
    state[b] = rotl(state[b] ^ state[c], 12u32)
    state[a] = state[a] +% state[b]
    state[d] = rotl(state[d] ^ state[a], 8u32)
    state[c] = state[c] +% state[d]
    state[b] = rotl(state[b] ^ state[c], 7u32)
}

// The block for the current counter into `r.block`. The counter of the last block is
// kept and `finished` marks that nothing more may follow it.
fn next_block(r: *ChaCha20) -> err {
    var state: [16]u32 = zero
    state[0] = 1634760805u32
    state[1] = 857760878u32
    state[2] = 2036477234u32
    state[3] = 1797285236u32
    var i = 0usize
    while i < 8usize {
        state[4usize + i] = load_le32(r.key[0..], i * 4usize)
        i += 1usize
    }
    state[12] = r.counter
    state[13] = load_le32(r.nonce[0..], 0usize)
    state[14] = load_le32(r.nonce[0..], 4usize)
    state[15] = load_le32(r.nonce[0..], 8usize)
    var working = state
    var round = 0usize
    while round < 10usize {
        quarter(working[0..], 0usize, 4usize, 8usize, 12usize)
        quarter(working[0..], 1usize, 5usize, 9usize, 13usize)
        quarter(working[0..], 2usize, 6usize, 10usize, 14usize)
        quarter(working[0..], 3usize, 7usize, 11usize, 15usize)
        quarter(working[0..], 0usize, 5usize, 10usize, 15usize)
        quarter(working[0..], 1usize, 6usize, 11usize, 12usize)
        quarter(working[0..], 2usize, 7usize, 8usize, 13usize)
        quarter(working[0..], 3usize, 4usize, 9usize, 14usize)
        round += 1usize
    }
    i = 0usize
    while i < 16usize {
        let word = working[i] +% state[i]
        r.block[i * 4usize] = u8(word & 255u32)
        r.block[i * 4usize + 1usize] = u8((word >> 8u32) & 255u32)
        r.block[i * 4usize + 2usize] = u8((word >> 16u32) & 255u32)
        r.block[i * 4usize + 3usize] = u8(word >> 24u32)
        i += 1usize
    }
    r.used = 0u8
    ret ok
}

// `used == 64` means the block is spent; `used == 65` means the last block was spent
// and the counter cannot advance.
fn chacha20_fill(r: *ChaCha20, dst: []u8) -> err {
    var at = 0usize
    while at < dst.len {
        if r.used >= 64u8 {
            if r.used == 65u8 { ret Exhausted }
            let block_error = next_block(r)
            if block_error != ok { ret block_error }
        }
        dst[at] = r.block[usize(r.used)]
        r.used += 1u8
        if r.used == 64u8 {
            if r.counter == 4294967295u32 {
                r.used = 65u8
            } else {
                r.counter += 1u32
            }
        }
        at += 1usize
    }
    ret ok
}

fn chacha20_next_u64(r: *ChaCha20) -> (u64, err) {
    var raw: [8]u8 = zero
    let fill_error = chacha20_fill(r, raw[0..])
    if fill_error != ok { ret (0u64, fill_error) }
    var value = 0u64
    var i = 0usize
    while i < 8usize {
        value = value | (u64(raw[i]) << u32(i * 8usize))
        i += 1usize
    }
    ret (value, ok)
}

// Rejection sampling over the largest multiple of `upper` below 2^64.
fn chacha20_bounded(r: *ChaCha20, upper: u64) -> (u64, err) {
    if upper == 0u64 { ret (0u64, ok) }
    let limit = 18446744073709551615u64 - (18446744073709551615u64 % upper)
    while true {
        let (value, next_error) = chacha20_next_u64(r)
        if next_error != ok { ret (0u64, next_error) }
        if value < limit { ret (value % upper, ok) }
    }
    ret (0u64, ok)
}
