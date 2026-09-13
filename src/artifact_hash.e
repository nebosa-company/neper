// Deterministic hashes used by .em serialization and content folding.

error InvalidByte

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

fn read_u32(bytes: []const usize, at: usize) -> (usize, err) {
    if at + 4usize > bytes.len { ret (0usize, InvalidByte) }
    var result = 0usize
    var offset = 0usize
    var multiplier = 1usize
    while offset < 4usize {
        if bytes[at + offset] > 255usize { ret (0usize, InvalidByte) }
        result += bytes[at + offset] * multiplier
        multiplier = multiplier * 256usize
        offset += 1usize
    }
    ret (result, ok)
}

fn read_u64(bytes: []const usize, at: usize) -> (usize, err) {
    if at + 8usize > bytes.len { ret (0usize, InvalidByte) }
    var result = 0usize
    var offset = 0usize
    var multiplier = 1usize
    while offset < 8usize {
        if bytes[at + offset] > 255usize { ret (0usize, InvalidByte) }
        result = result +% bytes[at + offset] *% multiplier
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

fn xxhash64(bytes: []const usize) -> (usize, err) {
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
        if bytes[at] > 255usize { ret (0usize, InvalidByte) }
        hash = xor(hash, bytes[at] *% prime5())
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

fn crc32c(bytes: []const usize, zero_at: usize, zero_count: usize) -> (usize, err) {
    var crc = 4294967295usize
    var at = 0usize
    while at < bytes.len {
        var value = bytes[at]
        if at >= zero_at && at - zero_at < zero_count { value = 0usize }
        if value > 255usize { ret (0usize, InvalidByte) }
        crc = xor(crc, value)
        var bit = 0usize
        while bit < 8usize {
            if crc % 2usize == 1usize {
                crc = xor(crc >> 1usize, 2197175160usize)
            } else {
                crc = crc >> 1usize
            }
            bit += 1usize
        }
        at += 1usize
    }
    ret (xor(crc, 4294967295usize), ok)
}

fn fnv1a32_step(hash: usize, value: usize) -> (usize, err) {
    if value > 255usize { ret (0usize, InvalidByte) }
    ret (xor(hash, value) *% 16777619usize % 4294967296usize, ok)
}

fn fnv1a32(bytes: []const usize) -> (usize, err) {
    var hash = 2166136261usize
    var at = 0usize
    while at < bytes.len {
        let (next, step_error) = fnv1a32_step(hash, bytes[at])
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

fn self_test() -> err {
    var empty: [1]usize = zero
    let (empty_hash, empty_error) = xxhash64(empty[0usize..0usize])
    if empty_error != ok || empty_hash != 17241709254077376921usize { ret InvalidByte }
    let digits = [9]usize{ 49usize, 50usize, 51usize, 52usize, 53usize, 54usize, 55usize, 56usize, 57usize }
    let (checksum, checksum_error) = crc32c(digits[..], 0usize, 0usize)
    if checksum_error != ok || checksum != 3808858755usize { ret InvalidByte }
    let invalid = [1]usize{ 256usize }
    let (invalid_hash, invalid_error) = xxhash64(invalid[..])
    if invalid_error != InvalidByte { ret InvalidByte }
    let hello = [5]usize{ 104usize, 101usize, 108usize, 108usize, 111usize }
    let (fnv, fnv_error) = fnv1a32(hello[..])
    if fnv_error != ok || fnv != 1335831723usize { ret InvalidByte }
    let (qualified, qualified_error) = qualified_error_value("e.os", "NotFound")
    if qualified_error != ok || qualified == 0usize { ret InvalidByte }
    ret ok
}
