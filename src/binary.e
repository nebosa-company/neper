// Target-independent bounded binary encoding for artifacts and object formats.

use e.os

error Capacity
error InvalidByte
error InvalidEncoding

// One byte per byte (D320): the buffer held one byte per `usize`, and so did every
// artifact read back, which made a two-million-line program's artifacts eight times
// their size in memory.
type Buffer = struct {
    bytes: []u8,
    count: usize,
}

fn init(buffer: *Buffer, bytes: []u8) -> err {
    if bytes.len == 0usize { ret Capacity }
    buffer.bytes = bytes
    buffer.count = 0usize
    ret ok
}

fn byte(buffer: *Buffer, value: usize) -> err {
    if value > 255usize { ret InvalidByte }
    if buffer.count == buffer.bytes.len { ret Capacity }
    buffer.bytes[buffer.count] = u8(value)
    buffer.count += 1usize
    ret ok
}

// The runs check the capacity once and store in a plain loop (D320): a byte at a time
// through `byte`, an artifact's megabytes of code paid a call and an error check each.
fn zeroes(buffer: *Buffer, count: usize) -> err {
    if count > buffer.bytes.len - buffer.count { ret Capacity }
    var at = buffer.count
    let end = at + count
    while at < end {
        buffer.bytes[at] = 0u8
        at += 1usize
    }
    buffer.count = end
    ret ok
}

// One runtime copy (D329) where a byte loop stood: the artifact writer copies every
// module's code twice and packs the whole artifact once.
fn copy(buffer: *Buffer, bytes: []const u8) -> err {
    if bytes.len > buffer.bytes.len - buffer.count { ret Capacity }
    let start = buffer.count
    os.copy_bytes(buffer.bytes[start..start + bytes.len], bytes)
    buffer.count = start + bytes.len
    ret ok
}

// The same over machine code, which is bytes (D307).
fn copy_bytes(buffer: *Buffer, bytes: []const u8) -> err {
    ret copy(buffer, bytes)
}

fn text(buffer: *Buffer, value: str) -> err {
    if value.len > buffer.bytes.len - buffer.count { ret Capacity }
    let start = buffer.count
    var at = 0usize
    while at < value.len {
        buffer.bytes[start + at] = value[at]
        at += 1usize
    }
    buffer.count = start + value.len
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
    if 4usize > buffer.bytes.len - buffer.count { ret Capacity }
    let at = buffer.count
    buffer.bytes[at] = u8(value & 255usize)
    buffer.bytes[at + 1usize] = u8((value >> 8usize) & 255usize)
    buffer.bytes[at + 2usize] = u8((value >> 16usize) & 255usize)
    buffer.bytes[at + 3usize] = u8((value >> 24usize) & 255usize)
    buffer.count = at + 4usize
    ret ok
}

fn little_u64(buffer: *Buffer, value: usize) -> err {
    if 8usize > buffer.bytes.len - buffer.count { ret Capacity }
    let at = buffer.count
    var remaining = value
    var offset = 0usize
    while offset < 8usize {
        buffer.bytes[at + offset] = u8(remaining & 255usize)
        remaining = remaining >> 8usize
        offset += 1usize
    }
    buffer.count = at + 8usize
    ret ok
}

fn patch_little_u32(buffer: *Buffer, offset: usize, value: usize) -> err {
    if value > 4294967295usize || offset + 4usize > buffer.count { ret InvalidEncoding }
    var remaining = value
    var at = 0usize
    while at < 4usize {
        buffer.bytes[offset + at] = u8(remaining % 256usize)
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
        buffer.bytes[offset + at] = u8(remaining % 256usize)
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn read_u16(bytes: []const u8, offset: usize) -> (usize, err) {
    if offset + 2usize > bytes.len { ret (0usize, InvalidEncoding) }
    ret (usize(bytes[offset]) + usize(bytes[offset + 1usize]) * 256usize, ok)
}

// The word at an offset the caller has bounded (D324): one value, no error, for the
// readers that take a record's words in a row.
// The guard is the proof (D388): the four loads under `offset + 4 > len` carry no
// check of their own, where they carried four.
fn read_u32_at(bytes: []const u8, offset: usize) -> usize {
    if offset + 4usize > bytes.len { ret 0usize }
    ret usize(bytes[offset]) | (usize(bytes[offset + 1usize]) << 8usize) | (usize(bytes[offset + 2usize]) << 16usize) | (usize(bytes[offset + 3usize]) << 24usize)
}

fn read_u32(bytes: []const u8, offset: usize) -> (usize, err) {
    if offset + 4usize > bytes.len { ret (0usize, InvalidEncoding) }
    ret (usize(bytes[offset]) | (usize(bytes[offset + 1usize]) << 8usize) | (usize(bytes[offset + 2usize]) << 16usize) | (usize(bytes[offset + 3usize]) << 24usize), ok)
}

fn read_u64(bytes: []const u8, offset: usize) -> (usize, err) {
    if offset + 8usize > bytes.len { ret (0usize, InvalidEncoding) }
    // Written out (D332): the loop with its multiplier was the artifact readers' most
    // called function.
    let low = usize(bytes[offset]) | (usize(bytes[offset + 1usize]) << 8usize) | (usize(bytes[offset + 2usize]) << 16usize) | (usize(bytes[offset + 3usize]) << 24usize)
    let high = usize(bytes[offset + 4usize]) | (usize(bytes[offset + 5usize]) << 8usize) | (usize(bytes[offset + 6usize]) << 16usize) | (usize(bytes[offset + 7usize]) << 24usize)
    ret (low | (high << 32usize), ok)
}

fn pack(buffer: *Buffer, destination: []u8) -> err {
    if buffer.count > destination.len { ret Capacity }
    os.copy_bytes(destination[0usize..buffer.count], buffer.bytes[0usize..buffer.count])
    ret ok
}

fn self_test() -> err {
    var storage: [32]u8 = zero
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
