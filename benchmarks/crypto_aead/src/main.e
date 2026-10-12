// C098: AES-128-GCM and AES-256-GCM sealing one record, hardware (AES-NI + PCLMULQDQ through
// os.aes_ctr / os.ghash_blocks) against the portable bitsliced path (D1645). Prints
// `<name> <bytes> <ns per record> <MB per second>` lines. Compare with OpenSSL through
// benchmarks/crypto_aead/openssl.py.
use e.mem
use e.io
use e.str
use e.time
use e.crypto.aead as aead

fn line(a: *mem.Arena, name: str, size: usize, ns: i64, runs: i64) -> err {
    let (b0, b0_error) = str.builder(a, 96usize)
    if b0_error != ok { ret b0_error }
    var b = b0
    try str.push(&b, name)
    try str.push(&b, " ")
    try str.push_i64(&b, i64(size))
    try str.push(&b, " ")
    let per = ns / runs
    try str.push_i64(&b, per)
    try str.push(&b, " ")
    // bytes per ns * 1000 = MB/s
    if per > 0i64 { try str.push_i64(&b, (i64(size) * 1000i64) / per) }
    try str.push(&b, "\n")
    try io.print(str.done(&b))
    ret ok
}

fn bench(a: *mem.Arena, name: str, key: []const u8, size: usize, runs: i64, portable: bool) -> err {
    let (plain, plain_error) = mem.alloc[u8](a, size)
    let (sealed, sealed_error) = mem.alloc[u8](a, size + 16usize)
    if plain_error != ok || sealed_error != ok { ret plain_error }
    var i = 0usize
    while i < size {
        plain[i] = u8((i * 7usize + 3usize) % 256usize)
        i += 1usize
    }
    var nonce: [12]u8 = zero
    var aad: [13]u8 = zero
    let (started, clock_error) = time.monotonic()
    if clock_error != ok { ret clock_error }
    var n = 0i64
    while n < runs {
        nonce[0] = u8(n & 255i64)
        if portable {
            let (_, e) = aead.gcm_seal_portable(sealed, key, nonce, aad[0..], plain)
            if e != ok { ret e }
        } else {
            let (_, e) = aead.aes_gcm_seal(sealed, key, nonce, aad[0..], plain)
            if e != ok { ret e }
        }
        n += 1i64
    }
    let ns = time.as_nanos(time.since(started))
    try line(a, name, size, ns, runs)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var key128: [16]u8 = zero
    var key256: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        key256[i] = u8((i * 29usize + 1usize) % 256usize)
        if i < 16usize { key128[i] = u8((i * 29usize + 1usize) % 256usize) }
        i += 1usize
    }
    try bench(a, "hw-aes128", key128[0..], 100usize, 200000i64, false)
    try bench(a, "hw-aes128", key128[0..], 16384usize, 20000i64, false)
    try bench(a, "hw-aes256", key256[0..], 16384usize, 20000i64, false)
    try bench(a, "portable-aes128", key128[0..], 100usize, 20000i64, true)
    try bench(a, "portable-aes128", key128[0..], 16384usize, 200i64, true)
    ret ok
}
