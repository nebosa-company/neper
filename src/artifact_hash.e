// Deterministic hashes used by .em serialization and content folding.
use e.algo.hash as algo_hash
use e.mem
use e.os
use lex
use source

error InvalidByte
error Capacity

fn prime1() -> usize { ret 11400714785074694791usize }
fn prime2() -> usize { ret 14029467366897019727usize }

fn rotate_left(value: usize, count: usize) -> usize {
    let high = value << count
    let low = value >> ((64usize - count) & 63usize)
    ret high + low
}

// Once a bit loop from before `^` existed, and the CRC over every artifact read or
// written went through it three hundred times a byte: minutes per module (D213).
fn xor(a: usize, b: usize) -> usize { ret a ^ b }

fn round(accumulator: usize, lane: usize) -> usize {
    var result = accumulator +% lane *% prime2()
    result = rotate_left(result, 31usize)
    ret result *% prime1()
}

// xxHash64 and FNV-1a from `e.algo.hash` (D747): the tuned inline-load form this
// file carried moved into the library, and what was a second copy of each is the call.
fn xxhash64(bytes: []const u8) -> (usize, err) {
    ret (usize(algo_hash.xxhash64(bytes, 0u64)), ok)
}

// Table-driven (D224): the table is built per call, two thousand steps, against a
// byte loop that ran eight per byte over every artifact loaded.
// CRC-32C eight bytes at a time (D320): the byte loop, with its branch for the zeroed
// field, walked every artifact byte a load takes, and a two-million-line program's
// artifacts are hundreds of megabytes. Slicing-by-eight: eight tables, the k-th the
// first applied to the (k-1)-th's entries, and one lookup per byte with no dependence
// between the eight of a word. The bytes before the zeroed field's end and the tail
// go a byte at a time.
fn crc32c(bytes: []const u8, zero_at: usize, zero_count: usize) -> (usize, err) {
    var table: [2048]usize = zero
    var entry = 0usize
    while entry < 256usize {
        var crc = entry
        var bit = 0usize
        while bit < 8usize {
            if crc % 2usize == 1usize {
                crc = (crc >> 1usize) ^ 2197175160usize
            } else {
                crc = crc >> 1usize
            }
            bit += 1usize
        }
        table[entry] = crc
        entry += 1usize
    }
    var slice = 1usize
    while slice < 8usize {
        entry = 0usize
        while entry < 256usize {
            let prior = table[(slice - 1usize) * 256usize + entry]
            table[slice * 256usize + entry] = (prior >> 8usize) ^ table[prior & 255usize]
            entry += 1usize
        }
        slice += 1usize
    }
    var crc = 4294967295usize
    var at = 0usize
    var head = zero_at + zero_count
    if zero_count == 0usize { head = 0usize }
    if head > bytes.len { head = bytes.len }
    while at < head {
        var value = usize(bytes[at])
        if at >= zero_at && at - zero_at < zero_count { value = 0usize }
        crc = table[(crc ^ value) & 255usize] ^ (crc >> 8usize)
        at += 1usize
    }
    // The rest with the CRC32 instruction when the CPU has it (D332); the loops below
    // then see nothing left, and do every byte on a CPU without.
    var crc_slot: [1]usize = zero
    crc_slot[0usize] = crc
    at += os.crc32c_bytes(crc_slot[..], bytes[at..bytes.len])
    crc = crc_slot[0usize]
    while at + 8usize <= bytes.len {
        let low = crc ^ (usize(bytes[at]) | (usize(bytes[at + 1usize]) << 8usize) | (usize(bytes[at + 2usize]) << 16usize) | (usize(bytes[at + 3usize]) << 24usize))
        crc = table[1792usize + (low & 255usize)] ^ table[1536usize + ((low >> 8usize) & 255usize)] ^ table[1280usize + ((low >> 16usize) & 255usize)] ^ table[1024usize + ((low >> 24usize) & 255usize)] ^ table[768usize + usize(bytes[at + 4usize])] ^ table[512usize + usize(bytes[at + 5usize])] ^ table[256usize + usize(bytes[at + 6usize])] ^ table[usize(bytes[at + 7usize])]
        at += 8usize
    }
    while at < bytes.len {
        crc = table[(crc ^ usize(bytes[at])) & 255usize] ^ (crc >> 8usize)
        at += 1usize
    }
    ret (crc ^ 4294967295usize, ok)
}

fn fnv1a32_step(hash: usize, value: usize) -> (usize, err) {
    if value > 255usize { ret (0usize, InvalidByte) }
    ret (xor(hash, value) *% 16777619usize % 4294967296usize, ok)
}

fn fnv1a32(bytes: []const u8) -> (usize, err) {
    ret (usize(algo_hash.fnv1a32(bytes)), ok)
}

fn qualified_error_value(module_name: str, error_name: str) -> (usize, err) {
    var hash = 2166136261usize
    var at = 0usize
    while at < module_name.len {
        let (next, step_error) = fnv1a32_step(hash, usize(module_name[at]))
        if step_error != ok { ret (0usize, step_error) }
        hash = next
        at += 1usize
    }
    let (with_separator, separator_error) = fnv1a32_step(hash, 46usize)
    if separator_error != ok { ret (0usize, separator_error) }
    hash = with_separator
    at = 0usize
    while at < error_name.len {
        let (next, step_error) = fnv1a32_step(hash, usize(error_name[at]))
        if step_error != ok { ret (0usize, step_error) }
        hash = next
        at += 1usize
    }
    ret (hash, ok)
}

// SHA-256 (D236) over the byte-per-slot input the other hashes take, so a build
// manifest can name each input by its RFC 6234 digest. All arithmetic is on usize
// masked to 32 bits, which the bootstrap compiles without a `u32` type or wrapping op.
fn mask32() -> usize { ret 4294967295usize }

fn sha_rotr(x: usize, n: usize) -> usize {
    let rotated = (x >> n) | (x << (32usize - n))
    let masked = rotated & mask32()
    ret masked
}

// The round constants, built once per compression rather than once per round (D306):
// as a literal inside `sha_k` the table was rebuilt on the stack sixty-four times per
// block, and the manifest hashes every source file of every build.
fn sha_table() -> [64]usize {
    ret [64]usize{
        1116352408usize, 1899447441usize, 3049323471usize, 3921009573usize, 961987163usize, 1508970993usize, 2453635748usize, 2870763221usize,
        3624381080usize, 310598401usize, 607225278usize, 1426881987usize, 1925078388usize, 2162078206usize, 2614888103usize, 3248222580usize,
        3835390401usize, 4022224774usize, 264347078usize, 604807628usize, 770255983usize, 1249150122usize, 1555081692usize, 1996064986usize,
        2554220882usize, 2821834349usize, 2952996808usize, 3210313671usize, 3336571891usize, 3584528711usize, 113926993usize, 338241895usize,
        666307205usize, 773529912usize, 1294757372usize, 1396182291usize, 1695183700usize, 1986661051usize, 2177026350usize, 2456956037usize,
        2730485921usize, 2820302411usize, 3259730800usize, 3345764771usize, 3516065817usize, 3600352804usize, 4094571909usize, 275423344usize,
        430227734usize, 506948616usize, 659060556usize, 883997877usize, 958139571usize, 1322822218usize, 1537002063usize, 1747873779usize,
        1955562222usize, 2024104815usize, 2227730452usize, 2361852424usize, 2428436474usize, 2756734187usize, 3204031479usize, 3329325298usize }
}

// Compress one 64-byte block, read from the bytes at `at`, into the eight-word state.
// The round table comes in from the caller, built once per digest (D323): a copy of
// it per block, and a slot per byte filled before each, were most of a manifest's
// time, and the manifest hashes every source and the image on every build.
fn sha_compress(state: []usize, bytes: []const u8, at: usize, k: []const usize) {
    // The message schedule as a rolling window of sixteen words (D330): `w[t]` needs
    // `w[t-2]`, `w[t-7]`, `w[t-15]` and `w[t-16]` alone, so a word overwrites the one
    // sixteen rounds older and the sixty-four-word block, zeroed per compression, is
    // gone. The rotations are spelled out: a call per rotation is what a debug build
    // paid, nine times a round.
    var w: [16]usize = zero
    var t = 0usize
    while t < 16usize {
        let p = at + t * 4usize
        w[t] = (usize(bytes[p]) << 24usize) | (usize(bytes[p + 1usize]) << 16usize) | (usize(bytes[p + 2usize]) << 8usize) | usize(bytes[p + 3usize])
        t += 1usize
    }
    var a = state[0usize]
    var b = state[1usize]
    var c = state[2usize]
    var d = state[3usize]
    var e = state[4usize]
    var f = state[5usize]
    var g = state[6usize]
    var h = state[7usize]
    t = 0usize
    while t < 64usize {
        var word = w[t & 15usize]
        if t >= 16usize {
            let w15 = w[(t + 1usize) & 15usize]
            let w2 = w[(t + 14usize) & 15usize]
            let s0 = (((w15 >> 7usize) | (w15 << 25usize)) ^ ((w15 >> 18usize) | (w15 << 14usize)) ^ (w15 >> 3usize)) & 4294967295usize
            let s1 = (((w2 >> 17usize) | (w2 << 15usize)) ^ ((w2 >> 19usize) | (w2 << 13usize)) ^ (w2 >> 10usize)) & 4294967295usize
            word = (word + s0 + w[(t + 9usize) & 15usize] + s1) & 4294967295usize
            w[t & 15usize] = word
        }
        let big1 = (((e >> 6usize) | (e << 26usize)) ^ ((e >> 11usize) | (e << 21usize)) ^ ((e >> 25usize) | (e << 7usize))) & 4294967295usize
        let choose = (e & f) ^ ((e ^ 4294967295usize) & g)
        let t1 = (h + big1 + choose + k[t] + word) & 4294967295usize
        let big0 = (((a >> 2usize) | (a << 30usize)) ^ ((a >> 13usize) | (a << 19usize)) ^ ((a >> 22usize) | (a << 10usize))) & 4294967295usize
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let t2 = (big0 + majority) & 4294967295usize
        h = g
        g = f
        f = e
        e = (d + t1) & 4294967295usize
        d = c
        c = b
        b = a
        a = (t1 + t2) & 4294967295usize
        t += 1usize
    }
    state[0usize] = (state[0usize] + a) & 4294967295usize
    state[1usize] = (state[1usize] + b) & 4294967295usize
    state[2usize] = (state[2usize] + c) & 4294967295usize
    state[3usize] = (state[3usize] + d) & 4294967295usize
    state[4usize] = (state[4usize] + e) & 4294967295usize
    state[5usize] = (state[5usize] + f) & 4294967295usize
    state[6usize] = (state[6usize] + g) & 4294967295usize
    state[7usize] = (state[7usize] + h) & 4294967295usize
}

fn sha_hex_digit(value: usize) -> u8 {
    if value < 10usize { ret u8(48usize + value) }
    ret u8(97usize + value - 10usize)
}

// The lowercase hex SHA-256 of the bytes, into the arena. The message is walked a
// 64-byte block at a time through one block buffer -- no copy of it is made, since an
// executable of some megabytes widened to a slot per byte, twice, is what the
// self-hosted compiler ran out of arena on (D254).
fn sha256_hex(a: *mem.Arena, bytes: []const u8) -> (str, err) {
    let (hex, hex_error) = mem.alloc[u8](a, 64usize)
    if hex_error != ok { ret ("", hex_error) }
    sha256_hex_into(bytes, hex)
    ret (hex[..], ok)
}

// The digest as sixty-four hex digits into `hex` (D432): what `sha256_hex` writes,
// for a caller with a buffer of its own and no arena.
fn sha256_hex_into(bytes: []const u8, hex: []u8) {
    if hex.len < 64usize { ret }
    var state = [8]usize{ 1779033703usize, 3144134277usize, 1013904242usize, 2773480762usize, 1359893119usize, 2600822924usize, 528734635usize, 1541459225usize }
    let k = sha_table()
    var block: [128]u8 = zero
    let total = bytes.len
    // The whole blocks with the SHA extensions when the CPU has them (D332), the rest
    // -- every block, on one without -- a round at a time here.
    var at = os.sha256_blocks(state[..], bytes) * 64usize
    while at + 64usize <= total {
        sha_compress(state[..], bytes, at, k[..])
        at += 64usize
    }
    // The tail: what remains, the 0x80 byte, zeros to 56 mod 64, and the bit length --
    // one block when the tail fits before the length, two otherwise.
    var fill = 0usize
    while at + fill < total {
        block[fill] = bytes[at + fill]
        fill += 1usize
    }
    block[fill] = 128u8
    fill += 1usize
    var padded = 64usize
    if fill > 56usize { padded = 128usize }
    while fill < padded {
        block[fill] = 0u8
        fill += 1usize
    }
    let bits = total * 8usize
    var byte_index = 0usize
    while byte_index < 8usize {
        block[padded - 1usize - byte_index] = u8((bits >> (byte_index * 8usize)) & 255usize)
        byte_index += 1usize
    }
    sha_compress(state[..], block[..], 0usize, k[..])
    if padded == 128usize { sha_compress(state[..], block[..], 64usize, k[..]) }
    var word = 0usize
    while word < 8usize {
        var shift = 0usize
        while shift < 4usize {
            let value = (state[word] >> ((3usize - shift) * 8usize)) & 255usize
            hex[word * 8usize + shift * 2usize] = sha_hex_digit(value >> 4usize)
            hex[word * 8usize + shift * 2usize + 1usize] = sha_hex_digit(value & 15usize)
            shift += 1usize
        }
        word += 1usize
    }
}

fn hex_nibble(value: u8) -> (u8, bool) {
    if value >= 48u8 && value <= 57u8 { ret (value - 48u8, true) }
    if value >= 97u8 && value <= 102u8 { ret (value - 87u8, true) }
    ret (0u8, false)
}

// HMAC-SHA-256 over the SHA implementation above. Cache keys are 32 bytes, so the
// long-key case RFC 2104 hashes first is deliberately outside this private surface.
fn hmac_sha256_hex(a: *mem.Arena, key: []const u8, message: []const u8) -> (str, err) {
    if key.len > 64usize { ret ("", InvalidByte) }
    let (inner, inner_error) = mem.alloc[u8](a, 64usize + message.len)
    if inner_error != ok { ret ("", inner_error) }
    var at = 0usize
    while at < 64usize {
        var value = 0u8
        if at < key.len { value = key[at] }
        inner[at] = value ^ 54u8
        at += 1usize
    }
    at = 0usize
    while at < message.len {
        inner[64usize + at] = message[at]
        at += 1usize
    }
    var inner_hex: [64]u8 = zero
    sha256_hex_into(inner, inner_hex[..])
    var outer: [96]u8 = zero
    at = 0usize
    while at < 64usize {
        var value = 0u8
        if at < key.len { value = key[at] }
        outer[at] = value ^ 92u8
        at += 1usize
    }
    at = 0usize
    while at < 32usize {
        let (high, high_ok) = hex_nibble(inner_hex[at * 2usize])
        let (low, low_ok) = hex_nibble(inner_hex[at * 2usize + 1usize])
        if !high_ok || !low_ok { ret ("", InvalidByte) }
        outer[64usize + at] = (high << 4u8) | low
        at += 1usize
    }
    let (tag, tag_error) = sha256_hex(a, outer[..])
    ret (tag, tag_error)
}

fn cache_key_from_hex(a: *mem.Arena, encoded: str) -> ([]const u8, err) {
    var empty: []const u8 = zero
    if encoded.len != 64usize { ret (empty, InvalidByte) }
    let (key, key_error) = mem.alloc[u8](a, 32usize)
    if key_error != ok { ret (empty, key_error) }
    var at = 0usize
    while at < 32usize {
        let (high, high_ok) = hex_nibble(encoded[at * 2usize])
        let (low, low_ok) = hex_nibble(encoded[at * 2usize + 1usize])
        if !high_ok || !low_ok { ret (empty, InvalidByte) }
        key[at] = (high << 4u8) | low
        at += 1usize
    }
    ret (key, ok)
}

fn cache_key_path(a: *mem.Arena) -> (str, err) {
    let (named, named_error) = os.env(a, "NEPER_CACHE_KEY_FILE")
    if named_error == ok && named.len != 0usize { ret (named, ok) }
    var (home, home_error) = os.env(a, "USERPROFILE")
    if home_error != ok || home.len == 0usize { (home, home_error) = os.env(a, "HOME") }
    if home_error != ok || home.len == 0usize { ret ("", os.NotFound) }
    let suffix = "/.neper-cache-key"
    let (path, path_error) = mem.alloc[u8](a, home.len + suffix.len)
    if path_error != ok { ret ("", path_error) }
    var path_at = 0usize
    while path_at < home.len {
        path[path_at] = home[path_at]
        path_at += 1usize
    }
    var suffix_at = 0usize
    while suffix_at < suffix.len {
        path[home.len + suffix_at] = suffix[suffix_at]
        suffix_at += 1usize
    }
    ret (path, ok)
}

// The cache authentication key lives in an explicit environment override or the
// user's profile, never in a project's disposable `.neper` tree. Exclusive creation
// makes concurrent first builds converge on one 0600 key on Linux.
fn cache_auth_key(a: *mem.Arena) -> ([]const u8, err) {
    let (encoded, encoded_error) = os.env(a, "NEPER_CACHE_KEY")
    if encoded_error == ok {
        let (decoded, decoded_error) = cache_key_from_hex(a, encoded)
        ret (decoded, decoded_error)
    }
    var empty: []const u8 = zero
    let (path, path_error) = cache_key_path(a)
    if path_error != ok { ret (empty, path_error) }
    let (existing, existing_error) = source.load(a, path)
    if existing_error == ok {
        if existing.len != 32usize { ret (empty, InvalidByte) }
        ret (existing, ok)
    }
    if existing_error != os.NotFound { ret (empty, existing_error) }
    var generated: [32]u8 = zero
    let random_error = os.random(generated[..])
    if random_error != ok { ret (empty, random_error) }
    let (file, create_error) = os.create_new(a, path)
    if create_error == os.Exists {
        let (raced, raced_error) = source.load(a, path)
        if raced_error != ok || raced.len != 32usize { ret (empty, InvalidByte) }
        ret (raced, ok)
    }
    if create_error != ok { ret (empty, create_error) }
    var written = 0usize
    var write_error = ok
    while written < 32usize && write_error == ok {
        let (count, one_error) = os.write(file, generated[written..])
        write_error = one_error
        if count == 0usize && one_error == ok { write_error = Capacity }
        written += count
    }
    let close_error = os.close(file)
    if write_error != ok { ret (empty, write_error) }
    if close_error != ok { ret (empty, close_error) }
    let (held, held_error) = mem.alloc[u8](a, 32usize)
    if held_error != ok { ret (empty, held_error) }
    var held_at = 0usize
    while held_at < 32usize {
        held[held_at] = generated[held_at]
        held_at += 1usize
    }
    ret (held, ok)
}

fn cache_auth_tag(a: *mem.Arena, message: []const u8) -> (str, err) {
    let (key, key_error) = cache_auth_key(a)
    if key_error != ok { ret ("", key_error) }
    let (tag, tag_error) = hmac_sha256_hex(a, key, message)
    ret (tag, tag_error)
}

// A generated manifest ends with this field. Its tag authenticates every preceding
// byte, including every artifact checksum; trailing or rearranged data is rejected.
fn cache_auth_verify(a: *mem.Arena, manifest: str) -> bool {
    let marker = ",\"cache_hmac_sha256\":\""
    var end = manifest.len
    if end != 0usize && manifest[end - 1usize] == 10u8 { end = end - 1usize }
    if end < marker.len + 66usize { ret false }
    let marker_at = end - marker.len - 66usize
    var at = 0usize
    while at < marker.len {
        if manifest[marker_at + at] != marker[at] { ret false }
        at += 1usize
    }
    let tag_at = marker_at + marker.len
    if manifest[tag_at + 64usize] != 34u8 || manifest[tag_at + 65usize] != 125u8 { ret false }
    let (expected, expected_error) = cache_auth_tag(a, manifest[..marker_at])
    if expected_error != ok || expected.len != 64usize { ret false }
    var different = 0u8
    at = 0usize
    while at < 64usize {
        different = different | (expected[at] ^ manifest[tag_at + at])
        at += 1usize
    }
    ret different == 0u8
}

fn self_test() -> err {
    var empty: [1]u8 = zero
    let (empty_hash, empty_error) = xxhash64(empty[0usize..0usize])
    if empty_error != ok || empty_hash != 17241709254077376921usize { ret InvalidByte }
    // Seventy-seven bytes is two whole blocks, then an eight, a four and a one: every
    // branch of the form that moved into `e.algo.hash` (D747), against the reference.
    var spread: [77]u8 = zero
    var spread_at = 0usize
    while spread_at < 77usize {
        spread[spread_at] = u8((spread_at * 7usize + 3usize) % 251usize)
        spread_at += 1usize
    }
    let (spread_hash, spread_error) = xxhash64(spread[..])
    if spread_error != ok || spread_hash != 18007575595249738181usize { ret InvalidByte }
    let digits = [9]u8{ 49u8, 50u8, 51u8, 52u8, 53u8, 54u8, 55u8, 56u8, 57u8 }
    let (checksum, checksum_error) = crc32c(digits[..], 0usize, 0usize)
    if checksum_error != ok || checksum != 3808858755usize { ret InvalidByte }
    let hello = [5]u8{ 104u8, 101u8, 108u8, 108u8, 111u8 }
    let (fnv, fnv_error) = fnv1a32(hello[..])
    if fnv_error != ok || fnv != 1335831723usize { ret InvalidByte }
    let (qualified, qualified_error) = qualified_error_value("e.os", "NotFound")
    if qualified_error != ok || qualified == 0usize { ret InvalidByte }
    var hmac_key: [20]u8 = zero
    var key_at = 0usize
    while key_at < 20usize {
        hmac_key[key_at] = 11u8
        key_at += 1usize
    }
    var hmac_arena_bytes: [4096]u8 = zero
    var hmac_arena = mem.arena_from(hmac_arena_bytes[..])
    let (hmac, hmac_error) = hmac_sha256_hex(&hmac_arena, hmac_key[..], "Hi There")
    let hmac_want = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
    if hmac_error != ok || hmac.len != hmac_want.len { ret InvalidByte }
    var hmac_at = 0usize
    while hmac_at < hmac.len {
        if hmac[hmac_at] != hmac_want[hmac_at] { ret InvalidByte }
        hmac_at += 1usize
    }
    ret ok
}

// A module's interface as the manifest hashes it (D265, D323): the source with every
// function body removed, so an edit inside a body moves `body_sha256` alone. Over
// the module's tokens (D316): it lexed the text again, for every module, on every
// build. The scanner-driven form stays for a text that has no tokens.
fn interface_cut(a: *mem.Arena, source: str, tokens: []const lex.Token) -> (str, err) {
    let (kept, kept_error) = mem.alloc[u8](a, source.len)
    if kept_error != ok { ret ("", kept_error) }
    var written = 0usize
    var copied_to = 0usize
    var braces = 0usize
    // 0: outside; 1: in a header, `brackets` deep; 2: in a body, `body_depth` braces deep.
    var state = 0usize
    var brackets = 0usize
    var body_depth = 0usize
    var previous = lex.Kind.Newline
    var at = 0usize
    while at < tokens.len {
        let token = tokens[at]
        at += 1usize
        if token.kind == .Eof { break }
        if state == 0usize {
            if token.kind == .PunctLBrace { braces += 1usize }
            if token.kind == .PunctRBrace && braces != 0usize { braces = braces - 1usize }
            if token.kind == .KwFn && braces == 0usize {
                state = 1usize
                brackets = 0usize
            }
        } else {
            if state == 1usize {
                if token.kind == .PunctLParen || token.kind == .PunctLBracket { brackets += 1usize }
                if (token.kind == .PunctRParen || token.kind == .PunctRBracket) && brackets != 0usize { brackets = brackets - 1usize }
                if token.kind == .PunctLBrace && brackets == 0usize {
                    // Keep through the `{`; the body starts after it.
                    var from = copied_to
                    while from < token.end {
                        kept[written] = source[from]
                        written += 1usize
                        from += 1usize
                    }
                    copied_to = token.end
                    state = 2usize
                    body_depth = 1usize
                } else {
                    // A header ends at a newline that does not continue one: `extern fn`
                    // has no body, and a function-typed field is not a declaration.
                    if token.kind == .Newline && brackets == 0usize && previous != .PunctArrow && previous != .PunctComma { state = 0usize }
                }
            } else {
                if token.kind == .PunctLBrace { body_depth += 1usize }
                if token.kind == .PunctRBrace {
                    body_depth = body_depth - 1usize
                    if body_depth == 0usize {
                        // The body is dropped; the `}` and what follows are kept.
                        copied_to = token.start
                        state = 0usize
                    }
                }
            }
        }
        previous = token.kind
    }
    while copied_to < source.len {
        kept[written] = source[copied_to]
        written += 1usize
        copied_to += 1usize
    }
    ret (kept[0usize..written], ok)
}

fn interface_sha256_hex(a: *mem.Arena, source: str, tokens: []const lex.Token) -> (str, err) {
    let (kept, cut_error) = interface_cut(a, source, tokens)
    if cut_error != ok { ret ("", cut_error) }
    let (digest, digest_error) = sha256_hex(a, kept)
    ret (digest, digest_error)
}

// The same over a text with no token stream: scanned into a buffer of its own.
fn interface_sha256_hex_scanned(a: *mem.Arena, source: str) -> (str, err) {
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, source.len + 16usize)
    if tokens_error != ok { ret ("", tokens_error) }
    var scanner = lex.init(source)
    var count = 0usize
    while true {
        if count == tokens.len { ret ("", Capacity) }
        let token = lex.next(&scanner)
        tokens[count] = token
        count += 1usize
        if token.kind == .Eof { break }
    }
    let (digest, digest_error) = interface_sha256_hex(a, source, tokens[0usize..count])
    ret (digest, digest_error)
}
