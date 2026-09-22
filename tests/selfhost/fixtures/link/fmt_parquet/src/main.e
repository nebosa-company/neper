// `e.fmt.parquet`: a pyarrow 23 file (9 rows: int32 with nulls, int64,
// double, bool, dictionary-encoded strings with a null, DELTA_BINARY_PACKED
// int32) reads back to pyarrow's footer, schema, chunk metadata, values and
// nulls; the same table Snappy-compressed decodes to the same values; the
// RLE/bit-packing hybrid, bit unpacking and levels agree with a Python
// encoder replica; a truncated file and a wrong magic answer `Malformed`.
// Each check exits with its own code.

use e.fmt.parquet as parquet
use e.io
use e.mem
use e.os

fn same_i64(xs: []const i64, ys: []const i64) -> bool {
    if xs.len != ys.len { ret false }
    var i = 0usize
    while i < xs.len {
        if xs[i] != ys[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_u32(xs: []const u32, ys: []const u32) -> bool {
    if xs.len != ys.len { ret false }
    var i = 0usize
    while i < xs.len {
        if xs[i] != ys[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_bits(xs: []const f64, ys: []const u64) -> bool {
    if xs.len != ys.len { ret false }
    var i = 0usize
    while i < xs.len {
        if mem.bitcast[u64](xs[i]) != ys[i] { ret false }
        i += 1usize
    }
    ret true
}

// Decode every column of `file` and compare with pyarrow's table; `code` is the
// exit code base for this file.
fn check_table(file: []const u8, code: i32) {
    var schema: [8]parquet.SchemaElement = zero
    var chunks: [8]parquet.ColumnChunk = zero
    var m = parquet.FileMetaData { version: 0i32, num_rows: 0i64, schema: schema[..], schema_count: 0usize, columns: chunks[..], column_count: 0usize, row_group_count: 0usize }
    if parquet.metadata(file, &m) != ok { os.exit(code) }
    if m.version != 2i32 || m.num_rows != 9i64 || m.schema_count != 7usize || m.column_count != 6usize || m.row_group_count != 1usize { os.exit(code) }
    var ints: [9]i64 = zero
    var floats: [9]f64 = zero
    var offsets: [10]u32 = zero
    var data: [32]u8 = zero
    var valid: [9]u8 = zero
    var scratch: [256]u8 = zero
    var v = parquet.Values { ints: ints[..], floats: floats[..], offsets: offsets[..], data: data[..], valid: valid[..], count: 0usize, data_len: 0usize }
    let all_valid: [9]u8 = [9]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1 }

    // +1: int32 with nulls, PLAIN.
    let (n0, e0) = parquet.decode(file, &m, 0usize, &v, scratch[..])
    if e0 != ok || n0 != 9usize || v.count != 9usize { os.exit(code + 1i32) }
    let i32_valid: [9]u8 = [9]u8{ 1, 0, 1, 1, 0, 1, 1, 1, 1 }
    let i32_values: [9]i64 = [9]i64{ 5, 0, -7, 100, 0, 0, 2147483647, -2147483648, 42 }
    if !mem.eq[u8](valid[..], i32_valid[..]) || !same_i64(ints[..], i32_values[..]) { os.exit(code + 1i32) }

    // +2: int64 PLAIN.
    let (n1, e1) = parquet.decode(file, &m, 1usize, &v, scratch[..])
    var i64_values: [9]i64 = [9]i64{ 1, -2, 3000000000, 4, 5, 6, 7, 0, 9223372036854775807 }
    i64_values[7] = 0i64 - 9223372036854775807i64 - 1i64
    if e1 != ok || n1 != 9usize || !mem.eq[u8](valid[..], all_valid[..]) || !same_i64(ints[..], i64_values[..]) { os.exit(code + 2i32) }

    // +3: double PLAIN, compared bit for bit (-0.0 included).
    let (n2, e2) = parquet.decode(file, &m, 2usize, &v, scratch[..])
    let f64_bits: [9]u64 = [9]u64{ 4602678819172646912, 13831680355561635840, 4613937818241073152, 9094988921128908188, 9223372036854775808, 4612811918334230528, 4619285842798575616, 4607182418800017408, 13844065254536904704 }
    if e2 != ok || n2 != 9usize || !mem.eq[u8](valid[..], all_valid[..]) || !same_bits(floats[..], f64_bits[..]) { os.exit(code + 3i32) }

    // +4: bool PLAIN (bit-packed).
    let (n3, e3) = parquet.decode(file, &m, 3usize, &v, scratch[..])
    let bool_values: [9]i64 = [9]i64{ 1, 0, 1, 1, 0, 0, 1, 0, 1 }
    if e3 != ok || n3 != 9usize || !mem.eq[u8](valid[..], all_valid[..]) || !same_i64(ints[..], bool_values[..]) { os.exit(code + 4i32) }

    // +5: strings through the dictionary page and RLE_DICTIONARY indices, one null.
    let (n4, e4) = parquet.decode(file, &m, 4usize, &v, scratch[..])
    let str_valid: [9]u8 = [9]u8{ 1, 1, 1, 1, 0, 1, 1, 1, 1 }
    let str_offsets: [10]u32 = [10]u32{ 0, 2, 4, 6, 8, 8, 11, 13, 15, 18 }
    if e4 != ok || n4 != 9usize || v.data_len != 18usize || !mem.eq[u8](valid[..], str_valid[..]) || !same_u32(offsets[..], str_offsets[..]) { os.exit(code + 5i32) }
    if !mem.eq[u8](data[..18usize], "abcdababxyzcdabxyz") { os.exit(code + 5i32) }

    // +6: int32 DELTA_BINARY_PACKED.
    let (n5, e5) = parquet.decode(file, &m, 5usize, &v, scratch[..])
    let delta_values: [9]i64 = [9]i64{ 100, 105, 103, 200, 1, -50, 7, 7, 7 }
    if e5 != ok || n5 != 9usize || !mem.eq[u8](valid[..], all_valid[..]) || !same_i64(ints[..], delta_values[..]) { os.exit(code + 6i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let plain: [883]u8 = [883]u8{ 80, 65, 82, 49, 21, 0, 21, 70, 21, 70, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 3, 0, 0, 0, 5, 237, 1, 5, 0, 0, 0, 249, 255, 255, 255, 100, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 127, 0, 0, 0, 128, 42, 0, 0, 0, 21, 0, 21, 156, 1, 21, 156, 1, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 2, 0, 0, 0, 18, 1, 1, 0, 0, 0, 0, 0, 0, 0, 254, 255, 255, 255, 255, 255, 255, 255, 0, 94, 208, 178, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 255, 255, 255, 255, 255, 255, 255, 127, 21, 0, 21, 156, 1, 21, 156, 1, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 2, 0, 0, 0, 18, 1, 0, 0, 0, 0, 0, 0, 224, 63, 0, 0, 0, 0, 0, 0, 244, 191, 0, 0, 0, 0, 0, 0, 8, 64, 156, 117, 0, 136, 60, 228, 55, 126, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 4, 64, 0, 0, 0, 0, 0, 0, 27, 64, 0, 0, 0, 0, 0, 0, 240, 63, 0, 0, 0, 0, 0, 0, 32, 192, 21, 0, 21, 16, 21, 16, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 2, 0, 0, 0, 18, 1, 77, 1, 21, 4, 21, 38, 21, 38, 76, 21, 6, 21, 0, 18, 0, 0, 2, 0, 0, 0, 97, 98, 2, 0, 0, 0, 99, 100, 3, 0, 0, 0, 120, 121, 122, 21, 0, 21, 22, 21, 22, 44, 21, 18, 21, 16, 21, 6, 21, 6, 28, 0, 0, 0, 3, 0, 0, 0, 5, 239, 1, 2, 3, 4, 134, 21, 0, 21, 108, 21, 108, 44, 21, 18, 21, 10, 21, 6, 21, 6, 28, 0, 0, 0, 2, 0, 0, 0, 18, 1, 128, 1, 4, 9, 200, 1, 141, 3, 9, 0, 0, 0, 204, 138, 161, 4, 64, 9, 224, 177, 99, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 4, 25, 124, 53, 0, 24, 6, 115, 99, 104, 101, 109, 97, 21, 12, 0, 21, 2, 37, 2, 24, 4, 105, 51, 50, 99, 0, 21, 4, 37, 2, 24, 4, 105, 54, 52, 99, 0, 21, 10, 37, 2, 24, 4, 102, 54, 52, 99, 0, 21, 0, 37, 2, 24, 5, 98, 111, 111, 108, 99, 0, 21, 12, 37, 2, 24, 4, 115, 116, 114, 99, 37, 0, 76, 28, 0, 0, 0, 21, 2, 37, 2, 24, 4, 100, 108, 116, 99, 0, 22, 18, 25, 28, 25, 108, 38, 0, 28, 21, 2, 25, 37, 6, 0, 25, 24, 4, 105, 51, 50, 99, 21, 0, 22, 18, 22, 108, 22, 108, 38, 8, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 4, 14, 0, 0, 0, 38, 0, 28, 21, 4, 25, 37, 6, 0, 25, 24, 4, 105, 54, 52, 99, 21, 0, 22, 18, 22, 198, 1, 22, 198, 1, 38, 116, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 38, 0, 28, 21, 10, 25, 37, 6, 0, 25, 24, 4, 102, 54, 52, 99, 21, 0, 22, 18, 22, 198, 1, 22, 198, 1, 38, 186, 2, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 38, 0, 28, 21, 0, 25, 37, 6, 0, 25, 24, 5, 98, 111, 111, 108, 99, 21, 0, 22, 18, 22, 54, 22, 54, 38, 128, 4, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 38, 0, 28, 21, 12, 25, 53, 0, 6, 16, 25, 24, 4, 115, 116, 114, 99, 21, 0, 22, 18, 22, 126, 22, 126, 38, 248, 4, 38, 182, 4, 41, 44, 21, 4, 21, 0, 21, 2, 0, 21, 0, 21, 16, 21, 2, 0, 60, 22, 36, 25, 6, 25, 38, 2, 16, 0, 0, 0, 38, 0, 28, 21, 2, 25, 37, 6, 10, 25, 24, 4, 100, 108, 116, 99, 21, 0, 22, 18, 22, 146, 1, 22, 146, 1, 38, 180, 5, 73, 28, 21, 0, 21, 10, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 22, 190, 6, 22, 18, 38, 8, 22, 190, 6, 0, 40, 32, 112, 97, 114, 113, 117, 101, 116, 45, 99, 112, 112, 45, 97, 114, 114, 111, 119, 32, 118, 101, 114, 115, 105, 111, 110, 32, 50, 51, 46, 48, 46, 48, 25, 108, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 0, 200, 1, 0, 0, 80, 65, 82, 49 }
    let snappy: [828]u8 = [828]u8{ 80, 65, 82, 49, 21, 0, 21, 70, 21, 68, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 35, 64, 3, 0, 0, 0, 5, 237, 1, 5, 0, 0, 0, 249, 255, 255, 255, 100, 0, 9, 1, 44, 255, 255, 255, 127, 0, 0, 0, 128, 42, 0, 0, 0, 21, 0, 21, 156, 1, 21, 118, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 78, 28, 2, 0, 0, 0, 18, 1, 1, 0, 9, 1, 4, 254, 255, 9, 1, 12, 0, 94, 208, 178, 1, 18, 0, 4, 1, 5, 12, 0, 0, 0, 5, 1, 5, 16, 0, 0, 0, 6, 0, 9, 1, 0, 7, 9, 7, 17, 1, 32, 128, 255, 255, 255, 255, 255, 255, 255, 127, 21, 0, 21, 156, 1, 21, 120, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 78, 24, 2, 0, 0, 0, 18, 1, 0, 5, 1, 4, 224, 63, 5, 7, 8, 0, 244, 191, 9, 8, 36, 8, 64, 156, 117, 0, 136, 60, 228, 55, 126, 9, 16, 4, 0, 128, 9, 8, 4, 4, 64, 9, 8, 0, 27, 13, 8, 36, 240, 63, 0, 0, 0, 0, 0, 0, 32, 192, 21, 0, 21, 16, 21, 20, 44, 21, 18, 21, 0, 21, 6, 21, 6, 28, 0, 0, 0, 8, 28, 2, 0, 0, 0, 18, 1, 77, 1, 21, 4, 21, 38, 21, 42, 76, 21, 6, 21, 0, 18, 0, 0, 19, 72, 2, 0, 0, 0, 97, 98, 2, 0, 0, 0, 99, 100, 3, 0, 0, 0, 120, 121, 122, 21, 0, 21, 22, 21, 26, 44, 21, 18, 21, 16, 21, 6, 21, 6, 28, 0, 0, 0, 11, 40, 3, 0, 0, 0, 5, 239, 1, 2, 3, 4, 134, 21, 0, 21, 108, 21, 66, 44, 21, 18, 21, 10, 21, 6, 21, 6, 28, 0, 0, 0, 54, 108, 2, 0, 0, 0, 18, 1, 128, 1, 4, 9, 200, 1, 141, 3, 9, 0, 0, 0, 204, 138, 161, 4, 64, 9, 224, 177, 99, 0, 102, 1, 0, 21, 4, 25, 124, 53, 0, 24, 6, 115, 99, 104, 101, 109, 97, 21, 12, 0, 21, 2, 37, 2, 24, 4, 105, 51, 50, 99, 0, 21, 4, 37, 2, 24, 4, 105, 54, 52, 99, 0, 21, 10, 37, 2, 24, 4, 102, 54, 52, 99, 0, 21, 0, 37, 2, 24, 5, 98, 111, 111, 108, 99, 0, 21, 12, 37, 2, 24, 4, 115, 116, 114, 99, 37, 0, 76, 28, 0, 0, 0, 21, 2, 37, 2, 24, 4, 100, 108, 116, 99, 0, 22, 18, 25, 28, 25, 108, 38, 0, 28, 21, 2, 25, 37, 6, 0, 25, 24, 4, 105, 51, 50, 99, 21, 2, 22, 18, 22, 108, 22, 106, 38, 8, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 4, 14, 0, 0, 0, 38, 0, 28, 21, 4, 25, 37, 6, 0, 25, 24, 4, 105, 54, 52, 99, 21, 2, 22, 18, 22, 196, 1, 22, 158, 1, 38, 114, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 38, 0, 28, 21, 10, 25, 37, 6, 0, 25, 24, 4, 102, 54, 52, 99, 21, 2, 22, 18, 22, 196, 1, 22, 160, 1, 38, 144, 2, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 38, 0, 28, 21, 0, 25, 37, 6, 0, 25, 24, 5, 98, 111, 111, 108, 99, 21, 2, 22, 18, 22, 54, 22, 58, 38, 176, 3, 73, 28, 21, 0, 21, 0, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 38, 0, 28, 21, 12, 25, 53, 0, 6, 16, 25, 24, 4, 115, 116, 114, 99, 21, 2, 22, 18, 22, 126, 22, 134, 1, 38, 176, 4, 38, 234, 3, 41, 44, 21, 4, 21, 0, 21, 2, 0, 21, 0, 21, 16, 21, 2, 0, 60, 22, 36, 25, 6, 25, 38, 2, 16, 0, 0, 0, 38, 0, 28, 21, 2, 25, 37, 6, 10, 25, 24, 4, 100, 108, 116, 99, 21, 2, 22, 18, 22, 146, 1, 22, 104, 38, 240, 4, 73, 28, 21, 0, 21, 10, 21, 2, 0, 60, 41, 6, 25, 38, 0, 18, 0, 0, 0, 22, 186, 6, 22, 18, 38, 8, 22, 208, 5, 0, 40, 32, 112, 97, 114, 113, 117, 101, 116, 45, 99, 112, 112, 45, 97, 114, 114, 111, 119, 32, 118, 101, 114, 115, 105, 111, 110, 32, 50, 51, 46, 48, 46, 48, 25, 108, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 28, 0, 0, 0, 200, 1, 0, 0, 80, 65, 82, 49 }

    // 1: footer.
    let (meta_start, meta_len, footer_error) = parquet.footer(plain[..])
    if footer_error != ok || meta_start != 419usize || meta_len != 456usize { os.exit(1i32) }

    // 2: schema.
    var schema: [8]parquet.SchemaElement = zero
    var chunks: [8]parquet.ColumnChunk = zero
    var m = parquet.FileMetaData { version: 0i32, num_rows: 0i64, schema: schema[..], schema_count: 0usize, columns: chunks[..], column_count: 0usize, row_group_count: 0usize }
    if parquet.metadata(plain[..], &m) != ok { os.exit(2i32) }
    if m.schema_count != 7usize || m.schema[0].num_children != 6i32 || !mem.eq[u8](m.schema[0].name, "schema") { os.exit(2i32) }
    let kinds: [6]i32 = [6]i32{ 1, 2, 5, 0, 6, 1 }
    var i = 0usize
    while i < 6usize {
        let s = m.schema[1usize + i]
        if s.kind != kinds[i] || s.repetition != 1i32 || s.num_children != 0i32 { os.exit(2i32) }
        i += 1usize
    }
    if !mem.eq[u8](m.schema[1].name, "i32c") || !mem.eq[u8](m.schema[5].name, "strc") || !mem.eq[u8](m.schema[6].name, "dltc") { os.exit(2i32) }
    if m.schema[5].converted_type != 0i32 || parquet.column_count(&m) != 6usize { os.exit(2i32) }

    // 3: chunk metadata (offsets, encodings, codec, counts).
    let (c0, c0_error) = parquet.column_chunk(&m, 0usize, 0usize)
    if c0_error != ok || c0.kind != 1i32 || c0.codec != 0i32 || c0.num_values != 9i64 || c0.data_page_offset != 4i64 || c0.dictionary_page_offset != 0i64 || c0.total_compressed_size != 54i64 || c0.total_uncompressed_size != 54i64 { os.exit(3i32) }
    if c0.encodings != 9u32 || !mem.eq[u8](c0.path, "i32c") { os.exit(3i32) }
    let (c4, c4_error) = parquet.column_chunk(&m, 0usize, 4usize)
    if c4_error != ok || c4.kind != 6i32 || c4.dictionary_page_offset != 283i64 || c4.data_page_offset != 316i64 || c4.encodings != 265u32 || c4.total_compressed_size != 63i64 || !mem.eq[u8](c4.path, "strc") { os.exit(3i32) }
    let (c5, c5_error) = parquet.column_chunk(&m, 0usize, 5usize)
    if c5_error != ok || c5.encodings != 40u32 || c5.data_page_offset != 346i64 || c5.total_compressed_size != 73i64 { os.exit(3i32) }
    let (_, bad_chunk) = parquet.column_chunk(&m, 1usize, 0usize)
    if bad_chunk != parquet.Invalid { os.exit(3i32) }

    // 4: the first page header.
    let (h, h_error) = parquet.page_header(plain[..], 4usize)
    if h_error != ok || h.kind != 0i32 || h.header_size != 19usize || h.uncompressed_page_size != 35i32 || h.compressed_page_size != 35i32 || h.num_values != 9i32 || h.encoding != 0i32 || h.definition_level_encoding != 3i32 { os.exit(4i32) }
    let (hd, hd_error) = parquet.page_header(plain[..], 283usize)
    if hd_error != ok || hd.kind != 2i32 || hd.header_size != 14usize || hd.num_values != 3i32 || hd.encoding != 0i32 || hd.uncompressed_page_size != 19i32 { os.exit(4i32) }

    // 5: definition levels of the first data page.
    var level_out: [16]u32 = zero
    let (level_bytes, level_error) = parquet.levels(plain[23usize..58usize], 1u32, 9usize, level_out[..])
    let level_expected: [9]u32 = [9]u32{ 1, 0, 1, 1, 0, 1, 1, 1, 1 }
    if level_error != ok || level_bytes != 7usize || !same_u32(level_out[..9usize], level_expected[..]) { os.exit(5i32) }

    // 10..16: every column of the uncompressed file.
    check_table(plain[..], 10i32)

    // 20..26: the Snappy file.
    let (snappy_start, snappy_len, snappy_footer_error) = parquet.footer(snappy[..])
    if snappy_footer_error != ok || snappy_start != 364usize || snappy_len != 456usize { os.exit(20i32) }
    check_table(snappy[..], 20i32)

    // 30: the hybrid on hand-made vectors (Python encoder replica).
    let hybrid3: [11]u8 = [11]u8{ 10, 6, 5, 136, 198, 250, 71, 21, 206, 8, 1 }
    let hybrid3_expected: [25]u32 = [25]u32{ 6, 6, 6, 6, 6, 0, 1, 2, 3, 4, 5, 6, 7, 7, 0, 5, 2, 1, 4, 3, 6, 1, 1, 1, 1 }
    var hybrid_out: [32]u32 = zero
    let (used3, used3_error) = parquet.decode_page(hybrid3[..], 3u32, 25usize, hybrid_out[..])
    if used3_error != ok || used3 != 11usize || !same_u32(hybrid_out[..25usize], hybrid3_expected[..]) { os.exit(30i32) }
    let hybrid10: [24]u8 = [24]u8{ 5, 232, 3, 240, 63, 128, 7, 176, 116, 126, 0, 2, 12, 64, 64, 1, 6, 32, 144, 128, 2, 6, 9, 3 }
    let hybrid10_expected: [19]u32 = [19]u32{ 1000, 0, 1023, 512, 7, 300, 999, 1, 2, 3, 4, 5, 6, 8, 9, 10, 777, 777, 777 }
    let (used10, used10_error) = parquet.rle_bitpack_hybrid(hybrid10[..], 10u32, 19usize, hybrid_out[..])
    if used10_error != ok || used10 != 24usize || !same_u32(hybrid_out[..19usize], hybrid10_expected[..]) { os.exit(30i32) }

    // 31: raw bit unpacking, width 5.
    let packed5: [7]u8 = [7]u8{ 31, 68, 146, 124, 16, 195, 54 }
    let packed5_expected: [11]u32 = [11]u32{ 31, 0, 17, 4, 9, 30, 1, 2, 3, 22, 13 }
    let (used5, used5_error) = parquet.bit_unpack(packed5[..], 5u32, 11usize, hybrid_out[..])
    if used5_error != ok || used5 != 7usize || !same_u32(hybrid_out[..11usize], packed5_expected[..]) { os.exit(31i32) }

    // 32: the strc dictionary indices through `dictionary` over decoded dictionary values.
    let dict_values: [3]u32 = [3]u32{ 10, 20, 30 }
    let (used_dict, dict_error) = parquet.dictionary[u32](plain[342usize..346usize], 8usize, dict_values[..], hybrid_out[..])
    let dict_expected: [8]u32 = [8]u32{ 10, 20, 10, 10, 30, 20, 10, 30 }
    if dict_error != ok || used_dict != 4usize || !same_u32(hybrid_out[..8usize], dict_expected[..]) { os.exit(32i32) }

    // 33: a truncated file and a wrong magic are Malformed.
    let (_, _, truncated_error) = parquet.footer(plain[..500usize])
    if truncated_error != parquet.Malformed { os.exit(33i32) }
    var wrong: [883]u8 = zero
    mem.copy[u8](wrong[..], plain[..])
    wrong[1] = 66u8
    if parquet.metadata(wrong[..], &m) != parquet.Malformed { os.exit(33i32) }
    let (_, _, short_error) = parquet.footer(plain[..8usize])
    if short_error != parquet.Malformed { os.exit(33i32) }
    // a footer length past the file start
    mem.copy[u8](wrong[..], plain[..])
    wrong[877] = 255u8
    if parquet.metadata(wrong[..], &m) != parquet.Malformed { os.exit(33i32) }

    try io.print("fmt parquet ok\n")
    ret ok
}
