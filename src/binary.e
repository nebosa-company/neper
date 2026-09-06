// Target-independent bounded binary encoding for artifacts and object formats.

error Capacity
error InvalidByte
error InvalidEncoding

type Buffer = struct {
    bytes: []usize,
    count: usize,
}

fn init(buffer: *Buffer, bytes: []usize) -> err {
    if bytes.len == 0usize { ret Capacity }
    buffer.bytes = bytes
    buffer.count = 0usize
    ret ok
}

fn byte(buffer: *Buffer, value: usize) -> err {
    if value > 255usize { ret InvalidByte }
    if buffer.count == buffer.bytes.len { ret Capacity }
    buffer.bytes[buffer.count] = value
    buffer.count += 1usize
    ret ok
}

fn zeroes(buffer: *Buffer, count: usize) -> err {
    var at = 0usize
    while at < count {
        try byte(buffer, 0usize)
        at += 1usize
    }
    ret ok
}

fn copy(buffer: *Buffer, bytes: []const usize) -> err {
    var at = 0usize
    while at < bytes.len {
        try byte(buffer, bytes[at])
        at += 1usize
    }
    ret ok
}

fn text(buffer: *Buffer, value: str) -> err {
    var at = 0usize
    while at < value.len {
        try byte(buffer, usize(value[at]))
        at += 1usize
    }
    ret ok
}

fn align(buffer: *Buffer, alignment: usize) -> err {
    if alignment == 0usize { ret InvalidEncoding }
    while buffer.count % alignment != 0usize { try byte(buffer, 0usize) }
    ret ok
}

fn little_u16(buffer: *Buffer, value: usize) -> err {
    if value > 65535usize { ret InvalidEncoding }
    var remaining = value
    var at = 0usize
    while at < 2usize {
        try byte(buffer, remaining % 256usize)
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn little_u32(buffer: *Buffer, value: usize) -> err {
    if value > 4294967295usize { ret InvalidEncoding }
    var remaining = value
    var at = 0usize
    while at < 4usize {
        try byte(buffer, remaining % 256usize)
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn little_u64(buffer: *Buffer, value: usize) -> err {
    var remaining = value
    var at = 0usize
    while at < 8usize {
        try byte(buffer, remaining % 256usize)
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn patch_little_u32(buffer: *Buffer, offset: usize, value: usize) -> err {
    if value > 4294967295usize || offset + 4usize > buffer.count { ret InvalidEncoding }
    var remaining = value
    var at = 0usize
    while at < 4usize {
        buffer.bytes[offset + at] = remaining % 256usize
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn patch_little_u64(buffer: *Buffer, offset: usize, value: usize) -> err {
    if offset + 8usize > buffer.count { ret InvalidEncoding }
    var remaining = value
    var at = 0usize
    while at < 8usize {
        buffer.bytes[offset + at] = remaining % 256usize
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn read_u16(bytes: []const usize, offset: usize) -> (usize, err) {
    if offset + 2usize > bytes.len { ret (0usize, InvalidEncoding) }
    if bytes[offset] > 255usize || bytes[offset + 1usize] > 255usize { ret (0usize, InvalidByte) }
    ret (bytes[offset] + bytes[offset + 1usize] * 256usize, ok)
}

fn read_u32(bytes: []const usize, offset: usize) -> (usize, err) {
    if offset + 4usize > bytes.len { ret (0usize, InvalidEncoding) }
    var result = 0usize
    var multiplier = 1usize
    var at = 0usize
    while at < 4usize {
        if bytes[offset + at] > 255usize { ret (0usize, InvalidByte) }
        result += bytes[offset + at] * multiplier
        multiplier = multiplier * 256usize
        at += 1usize
    }
    ret (result, ok)
}

fn read_u64(bytes: []const usize, offset: usize) -> (usize, err) {
    if offset + 8usize > bytes.len { ret (0usize, InvalidEncoding) }
    var result = 0usize
    var multiplier = 1usize
    var at = 0usize
    while at < 8usize {
        if bytes[offset + at] > 255usize { ret (0usize, InvalidByte) }
        result = result +% bytes[offset + at] *% multiplier
        multiplier = multiplier *% 256usize
        at += 1usize
    }
    ret (result, ok)
}

fn pack(buffer: *Buffer, destination: []u8) -> err {
    if buffer.count > destination.len { ret Capacity }
    var at = 0usize
    while at < buffer.count {
        if buffer.bytes[at] > 255usize { ret InvalidByte }
        destination[at] = u8(buffer.bytes[at])
        at += 1usize
    }
    ret ok
}

fn self_test() -> err {
    var storage: [32]usize = zero
    var buffer: Buffer = zero
    try init(&buffer, storage[..])
    try little_u16(&buffer, 4660usize)
    try little_u32(&buffer, 2309737967usize)
    try little_u64(&buffer, 81985529216486895usize)
    try align(&buffer, 8usize)
    if buffer.count != 16usize { ret InvalidEncoding }
    let (word16, word16_error) = read_u16(buffer.bytes[0usize..buffer.count], 0usize)
    if word16_error != ok || word16 != 4660usize { ret InvalidEncoding }
    let (word32, word32_error) = read_u32(buffer.bytes[0usize..buffer.count], 2usize)
    if word32_error != ok || word32 != 2309737967usize { ret InvalidEncoding }
    let (word64, word64_error) = read_u64(buffer.bytes[0usize..buffer.count], 6usize)
    if word64_error != ok || word64 != 81985529216486895usize { ret InvalidEncoding }
    try patch_little_u32(&buffer, 2usize, 305419896usize)
    let (patched32, patched32_error) = read_u32(buffer.bytes[0usize..buffer.count], 2usize)
    if patched32_error != ok || patched32 != 305419896usize { ret InvalidEncoding }
    try patch_little_u64(&buffer, 6usize, 18364758544493064720usize)
    let (patched64, patched64_error) = read_u64(buffer.bytes[0usize..buffer.count], 6usize)
    if patched64_error != ok || patched64 != 18364758544493064720usize { ret InvalidEncoding }
    ret ok
}
