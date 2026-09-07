// UUIDs are 16 bytes in RFC 9562's field order. The fixture pins the two constructors
// against text built from that layout independently, the round trip through `parse`
// and `format`, and the grammar `parse` accepts -- which is exactly what `format`
// writes, in either case, and nothing else.

use e.algo.hash
use e.algo.uuid
use e.mem
use e.str

error Failed

fn rendered(u: uuid.Uuid, expected: str) -> err {
    var text: [36]u8 = zero
    let (written, format_error) = uuid.format(u, text[0usize..36usize])
    if format_error != ok { ret format_error }
    if !str.eq(written, expected) { ret Failed }
    // Whatever `format` writes, `parse` reads back as the same sixteen bytes.
    let (back, parse_error) = uuid.parse(written)
    if parse_error != ok { ret parse_error }
    if !uuid.uuid_eq(back, u) { ret Failed }
    ret ok
}

fn bad(text: str) -> err {
    let (_, parse_error) = uuid.parse(text)
    if parse_error != uuid.Invalid { ret Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r16: [16]u8 = zero
    var r10: [10]u8 = zero

    // Version 4 sets six bits and copies the rest of the entropy through.
    r16[0usize] = 0u8
    r16[1usize] = 17u8
    r16[2usize] = 34u8
    r16[3usize] = 51u8
    r16[4usize] = 68u8
    r16[5usize] = 85u8
    r16[6usize] = 102u8
    r16[7usize] = 119u8
    r16[8usize] = 136u8
    r16[9usize] = 153u8
    r16[10usize] = 170u8
    r16[11usize] = 187u8
    r16[12usize] = 204u8
    r16[13usize] = 221u8
    r16[14usize] = 238u8
    r16[15usize] = 255u8
    let first = uuid.v4(r16)
    try rendered(first, "00112233-4455-4677-8899-aabbccddeeff")
    if uuid.version(first) != 4u8 { ret Failed }
    if uuid.variant(first) != 1u8 { ret Failed }

    // All ones and all zeros still come out as version 4, variant 1.
    r16[0usize] = 255u8
    r16[1usize] = 255u8
    r16[2usize] = 255u8
    r16[3usize] = 255u8
    r16[4usize] = 255u8
    r16[5usize] = 255u8
    r16[6usize] = 255u8
    r16[7usize] = 255u8
    r16[8usize] = 255u8
    r16[9usize] = 255u8
    r16[10usize] = 255u8
    r16[11usize] = 255u8
    r16[12usize] = 255u8
    r16[13usize] = 255u8
    r16[14usize] = 255u8
    r16[15usize] = 255u8
    let ones = uuid.v4(r16)
    try rendered(ones, "ffffffff-ffff-4fff-bfff-ffffffffffff")
    if uuid.version(ones) != 4u8 || uuid.variant(ones) != 1u8 { ret Failed }
    r16[0usize] = 0u8
    r16[1usize] = 0u8
    r16[2usize] = 0u8
    r16[3usize] = 0u8
    r16[4usize] = 0u8
    r16[5usize] = 0u8
    r16[6usize] = 0u8
    r16[7usize] = 0u8
    r16[8usize] = 0u8
    r16[9usize] = 0u8
    r16[10usize] = 0u8
    r16[11usize] = 0u8
    r16[12usize] = 0u8
    r16[13usize] = 0u8
    r16[14usize] = 0u8
    r16[15usize] = 0u8
    let zeros = uuid.v4(r16)
    try rendered(zeros, "00000000-0000-4000-8000-000000000000")
    if uuid.version(zeros) != 4u8 || uuid.variant(zeros) != 1u8 { ret Failed }

    // Version 7 puts a 48-bit big-endian millisecond count in front, so byte
    // order is time order.
    r10[0usize] = 10u8
    r10[1usize] = 27u8
    r10[2usize] = 44u8
    r10[3usize] = 61u8
    r10[4usize] = 78u8
    r10[5usize] = 95u8
    r10[6usize] = 96u8
    r10[7usize] = 113u8
    r10[8usize] = 130u8
    r10[9usize] = 147u8
    let (stamped, stamped_error) = uuid.v7(1705608428107u64, r10)
    if stamped_error != ok { ret stamped_error }
    try rendered(stamped, "018d1e2f-3a4b-7a1b-ac3d-4e5f60718293")
    if uuid.version(stamped) != 7u8 || uuid.variant(stamped) != 1u8 { ret Failed }
    let (epoch, epoch_error) = uuid.v7(0u64, r10)
    if epoch_error != ok { ret epoch_error }
    try rendered(epoch, "00000000-0000-7a1b-ac3d-4e5f60718293")
    let (latest, latest_error) = uuid.v7(281474976710655u64, r10)
    if latest_error != ok { ret latest_error }
    try rendered(latest, "ffffffff-ffff-7a1b-ac3d-4e5f60718293")
    // One millisecond past what 48 bits hold is rejected rather than truncated:
    // a truncated stamp would sort before UUIDs made earlier.
    let (overflowed, overflowed_error) = uuid.v7(281474976710656u64, r10)
    if overflowed_error != uuid.Invalid { ret Failed }
    // A later stamp orders after an earlier one, which is the whole point of v7.
    if uuid.uuid_cmp(epoch, stamped) >= 0i32 { ret Failed }
    if uuid.uuid_cmp(stamped, latest) >= 0i32 { ret Failed }
    if uuid.uuid_cmp(stamped, stamped) != 0i32 { ret Failed }
    if !uuid.uuid_eq(stamped, stamped) || uuid.uuid_eq(stamped, epoch) { ret Failed }

    // The hash is over the bytes, so equal UUIDs hash equally and the protocol
    // hook is the plain one.
    if uuid.uuid_hash(stamped) != hash.xxhash64(stamped.bytes[0usize..16usize], 0u64) { ret Failed }
    if uuid.uuid_hash(stamped) == uuid.uuid_hash(epoch) { ret Failed }

    // `uuid_format` is section 9 rule 4's declared `format`, and writes what
    // `format` does.
    var (builder, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    try uuid.uuid_format(stamped, &builder)
    if !str.eq(str.done(&builder), "018d1e2f-3a4b-7a1b-ac3d-4e5f60718293") { ret Failed }

    // Parsing accepts either case and nothing else.
    let (upper, upper_error) = uuid.parse("018D1E2F-3A4B-7A1B-AC3D-4E5F60718293")
    if upper_error != ok { ret upper_error }
    if !uuid.uuid_eq(upper, stamped) { ret Failed }
    let (mixed, mixed_error) = uuid.parse("018D1e2f-3a4B-7A1b-ac3d-4e5F60718293")
    if mixed_error != ok { ret mixed_error }
    if !uuid.uuid_eq(mixed, stamped) { ret Failed }
    try bad("")
    try bad("   ")
    try bad("018d1e2f-3a4b-7a1b-ac3d-4e5f6071829")
    try bad("018d1e2f-3a4b-7a1b-ac3d-4e5f607182930")
    try bad("018d1e2f3a4b7a1bac3d4e5f60718293")
    try bad("018d1e2f_3a4b-7a1b-ac3d-4e5f60718293")
    try bad("018d1e2f3a4b-7a1b-ac3d-4e5f607182930")
    try bad("{018d1e2f-3a4b-7a1b-ac3d-4e5f60718293}")
    try bad("urn:uuid:018d1e2f-3a4b-7a1b-ac3d-4e5f60718293")
    try bad("018d1e2f-3a4b-7a1b-ac3d-4e5f6071829g")
    try bad("z18d1e2f-3a4b-7a1b-ac3d-4e5f60718293")
    try bad("018d1e2f--3a4b-7a1b-ac3d-4e5f6071829")

    // A destination shorter than the 36 bytes the form needs is rejected rather
    // than written past.
    var small: [35]u8 = zero
    let (_, small_error) = uuid.format(stamped, small[0usize..35usize])
    if small_error != uuid.Invalid { ret Failed }
    ret ok
}
