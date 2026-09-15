// Deterministic hashes used by .em serialization and content folding.
use e.mem
use lex

error InvalidByte
error Capacity

fn prime1() -> usize { ret 11400714785074694791usize }
fn prime2() -> usize { ret 14029467366897019727usize }
fn prime3() -> usize { ret 1609587929392839161usize }
fn prime4() -> usize { ret 9650029242287828579usize }
fn prime5() -> usize { ret 2870177450012600261usize }

fn rotate_left(value: usize, count: usize) -> usize {
    let high = value << count
    let low = value >> ((64usize - count) & 63usize)
    ret high + low
}

// Once a bit loop from before `^` existed, and the CRC over every artifact read or
// written went through it three hundred times a byte: minutes per module (D213).
fn xor(a: usize, b: usize) -> usize { ret a ^ b }

fn read_u32(bytes: []const u8, at: usize) -> (usize, err) {
    if at + 4usize > bytes.len { ret (0usize, InvalidByte) }
    var result = 0usize
    var offset = 0usize
    var multiplier = 1usize
    while offset < 4usize {
        result += usize(bytes[at + offset]) * multiplier
        multiplier = multiplier * 256usize
        offset += 1usize
    }
    ret (result, ok)
}

fn read_u64(bytes: []const u8, at: usize) -> (usize, err) {
    if at + 8usize > bytes.len { ret (0usize, InvalidByte) }
    var result = 0usize
    var offset = 0usize
    var multiplier = 1usize
    while offset < 8usize {
        result = result +% usize(bytes[at + offset]) *% multiplier
        multiplier = multiplier *% 256usize
        offset += 1usize
    }
    ret (result, ok)
}

fn round(accumulator: usize, lane: usize) -> usize {
    var result = accumulator +% lane *% prime2()
    result = rotate_left(result, 31usize)
    ret result *% prime1()
}

fn merge_round(accumulator: usize, lane: usize) -> usize {
    var result = xor(accumulator, round(0usize, lane))
    ret result *% prime1() +% prime4()
}

fn xxhash64(bytes: []const u8) -> (usize, err) {
    var hash = 0usize
    var at = 0usize
    if bytes.len >= 32usize {
        var lane1: usize = prime1() +% prime2()
        var lane2: usize = prime2()
        var lane3: usize = 0usize
        var lane4: usize = 0usize -% prime1()
        let limit = bytes.len - 32usize
        while at <= limit {
            let (word1, word1_error) = read_u64(bytes, at)
            if word1_error != ok { ret (0usize, word1_error) }
            let (word2, word2_error) = read_u64(bytes, at + 8usize)
            if word2_error != ok { ret (0usize, word2_error) }
            let (word3, word3_error) = read_u64(bytes, at + 16usize)
            if word3_error != ok { ret (0usize, word3_error) }
            let (word4, word4_error) = read_u64(bytes, at + 24usize)
            if word4_error != ok { ret (0usize, word4_error) }
            lane1 = round(lane1, word1)
            lane2 = round(lane2, word2)
            lane3 = round(lane3, word3)
            lane4 = round(lane4, word4)
            at += 32usize
        }
        hash = rotate_left(lane1, 1usize) +% rotate_left(lane2, 7usize) +% rotate_left(lane3, 12usize) +% rotate_left(lane4, 18usize)
        hash = merge_round(hash, lane1)
        hash = merge_round(hash, lane2)
        hash = merge_round(hash, lane3)
        hash = merge_round(hash, lane4)
    } else {
        hash = prime5()
    }
    hash = hash +% bytes.len
    while at + 8usize <= bytes.len {
        let (word, word_error) = read_u64(bytes, at)
        if word_error != ok { ret (0usize, word_error) }
        hash = xor(hash, round(0usize, word))
        hash = rotate_left(hash, 27usize) *% prime1() +% prime4()
        at += 8usize
    }
    if at + 4usize <= bytes.len {
        let (word, word_error) = read_u32(bytes, at)
        if word_error != ok { ret (0usize, word_error) }
        hash = xor(hash, word *% prime1())
        hash = rotate_left(hash, 23usize) *% prime2() +% prime3()
        at += 4usize
    }
    while at < bytes.len {
        hash = xor(hash, usize(bytes[at]) *% prime5())
        hash = rotate_left(hash, 11usize) *% prime1()
        at += 1usize
    }
    hash = xor(hash, hash >> 33usize)
    hash = hash *% prime2()
    hash = xor(hash, hash >> 29usize)
    hash = hash *% prime3()
    hash = xor(hash, hash >> 32usize)
    ret (hash, ok)
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
    var hash = 2166136261usize
    var at = 0usize
    while at < bytes.len {
        let (next, step_error) = fnv1a32_step(hash, usize(bytes[at]))
        if step_error != ok { ret (0usize, step_error) }
        hash = next
        at += 1usize
    }
    ret (hash, ok)
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
    var w: [64]usize = zero
    var t = 0usize
    while t < 16usize {
        let p = at + t * 4usize
        w[t] = (usize(bytes[p]) << 24usize) | (usize(bytes[p + 1usize]) << 16usize) | (usize(bytes[p + 2usize]) << 8usize) | usize(bytes[p + 3usize])
        t += 1usize
    }
    while t < 64usize {
        let s0 = sha_rotr(w[t - 15usize], 7usize) ^ sha_rotr(w[t - 15usize], 18usize) ^ (w[t - 15usize] >> 3usize)
        let s1 = sha_rotr(w[t - 2usize], 17usize) ^ sha_rotr(w[t - 2usize], 19usize) ^ (w[t - 2usize] >> 10usize)
        w[t] = (w[t - 16usize] + s0 + w[t - 7usize] + s1) & mask32()
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
        let big1 = sha_rotr(e, 6usize) ^ sha_rotr(e, 11usize) ^ sha_rotr(e, 25usize)
        let choose = (e & f) ^ ((e ^ mask32()) & g)
        let t1 = (h + big1 + choose + k[t] + w[t]) & mask32()
        let big0 = sha_rotr(a, 2usize) ^ sha_rotr(a, 13usize) ^ sha_rotr(a, 22usize)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let t2 = (big0 + majority) & mask32()
        h = g
        g = f
        f = e
        e = (d + t1) & mask32()
        d = c
        c = b
        b = a
        a = (t1 + t2) & mask32()
        t += 1usize
    }
    state[0usize] = (state[0usize] + a) & mask32()
    state[1usize] = (state[1usize] + b) & mask32()
    state[2usize] = (state[2usize] + c) & mask32()
    state[3usize] = (state[3usize] + d) & mask32()
    state[4usize] = (state[4usize] + e) & mask32()
    state[5usize] = (state[5usize] + f) & mask32()
    state[6usize] = (state[6usize] + g) & mask32()
    state[7usize] = (state[7usize] + h) & mask32()
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
    var state = [8]usize{ 1779033703usize, 3144134277usize, 1013904242usize, 2773480762usize, 1359893119usize, 2600822924usize, 528734635usize, 1541459225usize }
    let k = sha_table()
    var block: [128]u8 = zero
    let total = bytes.len
    var at = 0usize
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
    let (hex, hex_error) = mem.alloc[u8](a, 64usize)
    if hex_error != ok { ret ("", hex_error) }
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
    ret (hex[..], ok)
}

fn self_test() -> err {
    var empty: [1]u8 = zero
    let (empty_hash, empty_error) = xxhash64(empty[0usize..0usize])
    if empty_error != ok || empty_hash != 17241709254077376921usize { ret InvalidByte }
    let digits = [9]u8{ 49u8, 50u8, 51u8, 52u8, 53u8, 54u8, 55u8, 56u8, 57u8 }
    let (checksum, checksum_error) = crc32c(digits[..], 0usize, 0usize)
    if checksum_error != ok || checksum != 3808858755usize { ret InvalidByte }
    let hello = [5]u8{ 104u8, 101u8, 108u8, 108u8, 111u8 }
    let (fnv, fnv_error) = fnv1a32(hello[..])
    if fnv_error != ok || fnv != 1335831723usize { ret InvalidByte }
    let (qualified, qualified_error) = qualified_error_value("e.os", "NotFound")
    if qualified_error != ok || qualified == 0usize { ret InvalidByte }
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
