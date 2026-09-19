// Deterministic non-cryptographic hashes and checksums.

type XxHash64 = struct {
    seed: u64,
    total: u64,
    v1: u64,
    v2: u64,
    v3: u64,
    v4: u64,
    buffer: [32]u8,
    buffered: u8,
}

type Crc32 = struct { value: u32 }

fn fnv1a32(data: []const u8) -> u32 {
    var hash = 2166136261u32
    var at = 0usize
    while at < data.len {
        hash = (hash ^ u32(data[at])) *% 16777619u32
        at += 1usize
    }
    ret hash
}

fn fnv1a64(data: []const u8) -> u64 {
    var hash = 14695981039346656037u64
    var at = 0usize
    while at < data.len {
        hash = (hash ^ u64(data[at])) *% 1099511628211u64
        at += 1usize
    }
    ret hash
}

// The whole thirty-two-byte blocks read straight from `data` (D747), rather than
// driving the streaming form, which copies every byte through its buffer first. The
// compiler hashes every artifact it reads and writes with this, and tuned its own copy
// to these inline loads (D388) before that copy became this call.
fn xxhash64(data: []const u8, seed: u64) -> u64 {
    let prime1 = 11400714785074694791u64
    let prime2 = 14029467366897019727u64
    let prime3 = 1609587929392839161u64
    let prime4 = 9650029242287828579u64
    let prime5 = 2870177450012600261u64
    var hash = 0u64
    var at = 0usize
    if data.len >= 32usize {
        var lane1 = seed +% prime1 +% prime2
        var lane2 = seed +% prime2
        var lane3 = seed
        var lane4 = seed -% prime1
        while at + 32usize <= data.len {
            let word1 = u64(data[at]) | (u64(data[at + 1usize]) << 8u64) | (u64(data[at + 2usize]) << 16u64) | (u64(data[at + 3usize]) << 24u64) | (u64(data[at + 4usize]) << 32u64) | (u64(data[at + 5usize]) << 40u64) | (u64(data[at + 6usize]) << 48u64) | (u64(data[at + 7usize]) << 56u64)
            let word2 = u64(data[at + 8usize]) | (u64(data[at + 9usize]) << 8u64) | (u64(data[at + 10usize]) << 16u64) | (u64(data[at + 11usize]) << 24u64) | (u64(data[at + 12usize]) << 32u64) | (u64(data[at + 13usize]) << 40u64) | (u64(data[at + 14usize]) << 48u64) | (u64(data[at + 15usize]) << 56u64)
            let word3 = u64(data[at + 16usize]) | (u64(data[at + 17usize]) << 8u64) | (u64(data[at + 18usize]) << 16u64) | (u64(data[at + 19usize]) << 24u64) | (u64(data[at + 20usize]) << 32u64) | (u64(data[at + 21usize]) << 40u64) | (u64(data[at + 22usize]) << 48u64) | (u64(data[at + 23usize]) << 56u64)
            let word4 = u64(data[at + 24usize]) | (u64(data[at + 25usize]) << 8u64) | (u64(data[at + 26usize]) << 16u64) | (u64(data[at + 27usize]) << 24u64) | (u64(data[at + 28usize]) << 32u64) | (u64(data[at + 29usize]) << 40u64) | (u64(data[at + 30usize]) << 48u64) | (u64(data[at + 31usize]) << 56u64)
            lane1 = lane1 +% word1 *% prime2
            lane1 = ((lane1 << 31u64) | (lane1 >> 33u64)) *% prime1
            lane2 = lane2 +% word2 *% prime2
            lane2 = ((lane2 << 31u64) | (lane2 >> 33u64)) *% prime1
            lane3 = lane3 +% word3 *% prime2
            lane3 = ((lane3 << 31u64) | (lane3 >> 33u64)) *% prime1
            lane4 = lane4 +% word4 *% prime2
            lane4 = ((lane4 << 31u64) | (lane4 >> 33u64)) *% prime1
            at += 32usize
        }
        hash = ((lane1 << 1u64) | (lane1 >> 63u64)) +% ((lane2 << 7u64) | (lane2 >> 57u64))
        hash = hash +% ((lane3 << 12u64) | (lane3 >> 52u64)) +% ((lane4 << 18u64) | (lane4 >> 46u64))
        var merged = lane1 *% prime2
        merged = ((merged << 31u64) | (merged >> 33u64)) *% prime1
        hash = (hash ^ merged) *% prime1 +% prime4
        merged = lane2 *% prime2
        merged = ((merged << 31u64) | (merged >> 33u64)) *% prime1
        hash = (hash ^ merged) *% prime1 +% prime4
        merged = lane3 *% prime2
        merged = ((merged << 31u64) | (merged >> 33u64)) *% prime1
        hash = (hash ^ merged) *% prime1 +% prime4
        merged = lane4 *% prime2
        merged = ((merged << 31u64) | (merged >> 33u64)) *% prime1
        hash = (hash ^ merged) *% prime1 +% prime4
    } else {
        hash = seed +% prime5
    }
    hash = hash +% u64(data.len)
    while at + 8usize <= data.len {
        let word = u64(data[at]) | (u64(data[at + 1usize]) << 8u64) | (u64(data[at + 2usize]) << 16u64) | (u64(data[at + 3usize]) << 24u64) | (u64(data[at + 4usize]) << 32u64) | (u64(data[at + 5usize]) << 40u64) | (u64(data[at + 6usize]) << 48u64) | (u64(data[at + 7usize]) << 56u64)
        var lane = word *% prime2
        lane = ((lane << 31u64) | (lane >> 33u64)) *% prime1
        hash = hash ^ lane
        hash = ((hash << 27u64) | (hash >> 37u64)) *% prime1 +% prime4
        at += 8usize
    }
    if at + 4usize <= data.len {
        let tail = u64(data[at]) | (u64(data[at + 1usize]) << 8u64) | (u64(data[at + 2usize]) << 16u64) | (u64(data[at + 3usize]) << 24u64)
        hash = hash ^ (tail *% prime1)
        hash = ((hash << 23u64) | (hash >> 41u64)) *% prime2 +% prime3
        at += 4usize
    }
    while at < data.len {
        hash = hash ^ (u64(data[at]) *% prime5)
        hash = ((hash << 11u64) | (hash >> 53u64)) *% prime1
        at += 1usize
    }
    hash = hash ^ (hash >> 33u64)
    hash = hash *% prime2
    hash = hash ^ (hash >> 29u64)
    hash = hash *% prime3
    hash = hash ^ (hash >> 32u64)
    ret hash
}

fn xxhash64_init(seed: u64) -> XxHash64 {
    let prime1 = 11400714785074694791u64
    let prime2 = 14029467366897019727u64
    ret XxHash64 {
        seed: seed,
        total: 0u64,
        v1: seed +% prime1 +% prime2,
        v2: seed +% prime2,
        v3: seed,
        v4: seed -% prime1,
        buffer: zero,
        buffered: 0u8,
    }
}

fn xxhash64_update(h: *XxHash64, data: []const u8) {
    let prime1 = 11400714785074694791u64
    let prime2 = 14029467366897019727u64
    h.total = h.total +% u64(data.len)
    var at = 0usize
    var buffered = usize(h.buffered)
    while at < data.len {
        h.buffer[buffered] = data[at]
        buffered += 1usize
        at += 1usize
        if buffered == 32usize {
            var lane1 = u64(h.buffer[0usize])
            lane1 = lane1 | (u64(h.buffer[1usize]) << 8u64)
            lane1 = lane1 | (u64(h.buffer[2usize]) << 16u64)
            lane1 = lane1 | (u64(h.buffer[3usize]) << 24u64)
            lane1 = lane1 | (u64(h.buffer[4usize]) << 32u64)
            lane1 = lane1 | (u64(h.buffer[5usize]) << 40u64)
            lane1 = lane1 | (u64(h.buffer[6usize]) << 48u64)
            lane1 = lane1 | (u64(h.buffer[7usize]) << 56u64)
            h.v1 = h.v1 +% lane1 *% prime2
            let v1_high = h.v1 << 31u64
            let v1_low = h.v1 >> 33u64
            h.v1 = v1_high | v1_low
            h.v1 = h.v1 *% prime1
            var lane2 = u64(h.buffer[8usize])
            lane2 = lane2 | (u64(h.buffer[9usize]) << 8u64)
            lane2 = lane2 | (u64(h.buffer[10usize]) << 16u64)
            lane2 = lane2 | (u64(h.buffer[11usize]) << 24u64)
            lane2 = lane2 | (u64(h.buffer[12usize]) << 32u64)
            lane2 = lane2 | (u64(h.buffer[13usize]) << 40u64)
            lane2 = lane2 | (u64(h.buffer[14usize]) << 48u64)
            lane2 = lane2 | (u64(h.buffer[15usize]) << 56u64)
            h.v2 = h.v2 +% lane2 *% prime2
            let v2_high = h.v2 << 31u64
            let v2_low = h.v2 >> 33u64
            h.v2 = v2_high | v2_low
            h.v2 = h.v2 *% prime1
            var lane3 = u64(h.buffer[16usize])
            lane3 = lane3 | (u64(h.buffer[17usize]) << 8u64)
            lane3 = lane3 | (u64(h.buffer[18usize]) << 16u64)
            lane3 = lane3 | (u64(h.buffer[19usize]) << 24u64)
            lane3 = lane3 | (u64(h.buffer[20usize]) << 32u64)
            lane3 = lane3 | (u64(h.buffer[21usize]) << 40u64)
            lane3 = lane3 | (u64(h.buffer[22usize]) << 48u64)
            lane3 = lane3 | (u64(h.buffer[23usize]) << 56u64)
            h.v3 = h.v3 +% lane3 *% prime2
            let v3_high = h.v3 << 31u64
            let v3_low = h.v3 >> 33u64
            h.v3 = v3_high | v3_low
            h.v3 = h.v3 *% prime1
            var lane4 = u64(h.buffer[24usize])
            lane4 = lane4 | (u64(h.buffer[25usize]) << 8u64)
            lane4 = lane4 | (u64(h.buffer[26usize]) << 16u64)
            lane4 = lane4 | (u64(h.buffer[27usize]) << 24u64)
            lane4 = lane4 | (u64(h.buffer[28usize]) << 32u64)
            lane4 = lane4 | (u64(h.buffer[29usize]) << 40u64)
            lane4 = lane4 | (u64(h.buffer[30usize]) << 48u64)
            lane4 = lane4 | (u64(h.buffer[31usize]) << 56u64)
            h.v4 = h.v4 +% lane4 *% prime2
            let v4_high = h.v4 << 31u64
            let v4_low = h.v4 >> 33u64
            h.v4 = v4_high | v4_low
            h.v4 = h.v4 *% prime1
            buffered = 0usize
        }
    }
    h.buffered = u8(buffered)
}

fn xxhash64_done(h: *const XxHash64) -> u64 {
    let prime1 = 11400714785074694791u64
    let prime2 = 14029467366897019727u64
    let prime3 = 1609587929392839161u64
    let prime4 = 9650029242287828579u64
    let prime5 = 2870177450012600261u64
    var hash = h.seed +% prime5
    if h.total >= 32u64 {
        let v1_high = h.v1 << 1u64
        let v1_low = h.v1 >> 63u64
        hash = v1_high | v1_low
        let v2_high = h.v2 << 7u64
        let v2_low = h.v2 >> 57u64
        hash = hash +% (v2_high | v2_low)
        let v3_high = h.v3 << 12u64
        let v3_low = h.v3 >> 52u64
        hash = hash +% (v3_high | v3_low)
        let v4_high = h.v4 << 18u64
        let v4_low = h.v4 >> 46u64
        hash = hash +% (v4_high | v4_low)
        var lane = h.v1 *% prime2
        let lane1_high = lane << 31u64
        let lane1_low = lane >> 33u64
        lane = lane1_high | lane1_low
        lane = lane *% prime1
        hash = hash ^ lane
        hash = hash *% prime1 +% prime4
        lane = h.v2 *% prime2
        let lane2_high = lane << 31u64
        let lane2_low = lane >> 33u64
        lane = lane2_high | lane2_low
        lane = lane *% prime1
        hash = hash ^ lane
        hash = hash *% prime1 +% prime4
        lane = h.v3 *% prime2
        let lane3_high = lane << 31u64
        let lane3_low = lane >> 33u64
        lane = lane3_high | lane3_low
        lane = lane *% prime1
        hash = hash ^ lane
        hash = hash *% prime1 +% prime4
        lane = h.v4 *% prime2
        let lane4_high = lane << 31u64
        let lane4_low = lane >> 33u64
        lane = lane4_high | lane4_low
        lane = lane *% prime1
        hash = hash ^ lane
        hash = hash *% prime1 +% prime4
    }
    hash = hash +% h.total
    let buffered = usize(h.buffered)
    var at = 0usize
    while at + 8usize <= buffered {
        var word = u64(h.buffer[at])
        word = word | (u64(h.buffer[at + 1usize]) << 8u64)
        word = word | (u64(h.buffer[at + 2usize]) << 16u64)
        word = word | (u64(h.buffer[at + 3usize]) << 24u64)
        word = word | (u64(h.buffer[at + 4usize]) << 32u64)
        word = word | (u64(h.buffer[at + 5usize]) << 40u64)
        word = word | (u64(h.buffer[at + 6usize]) << 48u64)
        word = word | (u64(h.buffer[at + 7usize]) << 56u64)
        var lane = word *% prime2
        let lane_high = lane << 31u64
        let lane_low = lane >> 33u64
        lane = lane_high | lane_low
        lane = lane *% prime1
        hash = hash ^ lane
        let hash_high = hash << 27u64
        let hash_low = hash >> 37u64
        hash = hash_high | hash_low
        hash = hash *% prime1 +% prime4
        at += 8usize
    }
    if at + 4usize <= buffered {
        var word = u32(h.buffer[at])
        word = word | (u32(h.buffer[at + 1usize]) << 8u32)
        word = word | (u32(h.buffer[at + 2usize]) << 16u32)
        word = word | (u32(h.buffer[at + 3usize]) << 24u32)
        hash = hash ^ (u64(word) *% prime1)
        let hash_high = hash << 23u64
        let hash_low = hash >> 41u64
        hash = hash_high | hash_low
        hash = hash *% prime2 +% prime3
        at += 4usize
    }
    while at < buffered {
        hash = hash ^ (u64(h.buffer[at]) *% prime5)
        let hash_high = hash << 11u64
        let hash_low = hash >> 53u64
        hash = hash_high | hash_low
        hash = hash *% prime1
        at += 1usize
    }
    hash = hash ^ (hash >> 33u64)
    hash = hash *% prime2
    hash = hash ^ (hash >> 29u64)
    hash = hash *% prime3
    ret hash ^ (hash >> 32u64)
}

fn crc32(data: []const u8) -> u32 {
    var state = crc32_init()
    crc32_update(&state, data)
    ret crc32_done(&state)
}

fn crc32_init() -> Crc32 { ret Crc32 { value: 4294967295u32 } }

fn crc32_update(h: *Crc32, data: []const u8) {
    var at = 0usize
    while at < data.len {
        h.value = h.value ^ u32(data[at])
        var bit = 0usize
        while bit < 8usize {
            let low = h.value & 1u32
            let shifted = h.value >> 1u32
            if low != 0u32 {
                h.value = shifted ^ 3988292384u32
            } else {
                h.value = shifted
            }
            bit += 1usize
        }
        at += 1usize
    }
}

fn crc32_done(h: *const Crc32) -> u32 { ret h.value ^ 4294967295u32 }

fn adler32(data: []const u8) -> u32 {
    var a = 1u32
    var b = 0u32
    var at = 0usize
    while at < data.len {
        a = (a + u32(data[at])) % 65521u32
        b = (b + a) % 65521u32
        at += 1usize
    }
    let high = b << 16u32
    ret high | a
}
