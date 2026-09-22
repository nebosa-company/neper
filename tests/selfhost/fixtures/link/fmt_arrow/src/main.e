// `e.fmt.arrow`: a pyarrow 23 IPC stream of one 7-row batch (int32 with
// nulls, int64, float64, bool with nulls, utf8 with nulls, list<int32>,
// struct<a: int16, b: utf8>) reads back to pyarrow's schema, kinds, lengths,
// null counts, values, list ranges and struct children; a dictionary-encoded
// stream answers `Unsupported` and a truncated one `Malformed`. Each check
// exits with its own code.

use e.fmt.arrow as arrow
use e.io
use e.mem
use e.os

fn expect_kind(c: *const arrow.Column, kind: arrow.Kind, len: usize, nulls: usize, code: i32) {
    if c.kind != kind || c.len != len || c.null_count != nulls || arrow.count_nulls(c) != nulls { os.exit(code) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let stream: [1512]u8 = [1512]u8{ 255, 255, 255, 255, 24, 2, 0, 0, 16, 0, 0, 0, 0, 0, 10, 0, 12, 0, 6, 0, 5, 0, 8, 0, 10, 0, 0, 0, 0, 1, 4, 0, 12, 0, 0, 0, 8, 0, 8, 0, 0, 0, 4, 0, 8, 0, 0, 0, 4, 0, 0, 0, 7, 0, 0, 0, 172, 1, 0, 0, 104, 1, 0, 0, 52, 1, 0, 0, 8, 1, 0, 0, 224, 0, 0, 0, 132, 0, 0, 0, 4, 0, 0, 0, 128, 254, 255, 255, 0, 0, 1, 13, 24, 0, 0, 0, 28, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 56, 0, 0, 0, 16, 0, 0, 0, 2, 0, 0, 0, 115, 116, 0, 0, 16, 255, 255, 255, 172, 254, 255, 255, 0, 0, 1, 5, 16, 0, 0, 0, 20, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 98, 0, 0, 0, 52, 255, 255, 255, 208, 254, 255, 255, 0, 0, 1, 2, 16, 0, 0, 0, 20, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 97, 0, 0, 0, 188, 254, 255, 255, 0, 0, 0, 1, 16, 0, 0, 0, 252, 254, 255, 255, 0, 0, 1, 12, 20, 0, 0, 0, 24, 0, 0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 16, 0, 0, 0, 2, 0, 0, 0, 108, 105, 0, 0, 136, 255, 255, 255, 36, 255, 255, 255, 0, 0, 1, 2, 16, 0, 0, 0, 24, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 105, 116, 101, 109, 0, 0, 0, 0, 20, 255, 255, 255, 0, 0, 0, 1, 32, 0, 0, 0, 84, 255, 255, 255, 0, 0, 1, 5, 16, 0, 0, 0, 20, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 115, 0, 0, 0, 220, 255, 255, 255, 120, 255, 255, 255, 0, 0, 1, 6, 16, 0, 0, 0, 24, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 98, 99, 0, 0, 4, 0, 4, 0, 4, 0, 0, 0, 160, 255, 255, 255, 0, 0, 1, 3, 16, 0, 0, 0, 28, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 102, 54, 52, 99, 0, 0, 6, 0, 8, 0, 6, 0, 6, 0, 0, 0, 0, 0, 2, 0, 208, 255, 255, 255, 0, 0, 1, 2, 16, 0, 0, 0, 24, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 105, 54, 52, 99, 0, 0, 0, 0, 192, 255, 255, 255, 0, 0, 0, 1, 64, 0, 0, 0, 16, 0, 20, 0, 8, 0, 6, 0, 7, 0, 12, 0, 0, 0, 16, 0, 16, 0, 0, 0, 0, 0, 1, 2, 16, 0, 0, 0, 32, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 105, 51, 50, 99, 0, 0, 0, 0, 8, 0, 12, 0, 8, 0, 7, 0, 8, 0, 0, 0, 0, 0, 0, 1, 32, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 72, 2, 0, 0, 20, 0, 0, 0, 0, 0, 0, 0, 12, 0, 22, 0, 6, 0, 5, 0, 8, 0, 12, 0, 12, 0, 0, 0, 0, 3, 4, 0, 24, 0, 0, 0, 112, 1, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 24, 0, 12, 0, 4, 0, 8, 0, 10, 0, 0, 0, 108, 1, 0, 0, 16, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 56, 0, 0, 0, 0, 0, 0, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 96, 0, 0, 0, 0, 0, 0, 0, 56, 0, 0, 0, 0, 0, 0, 0, 152, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 160, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 168, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 176, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 208, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 0, 0, 0, 0, 224, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 232, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 8, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 1, 0, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 40, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 48, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 1, 0, 0, 0, 0, 0, 0, 14, 0, 0, 0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 96, 1, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 109, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 249, 255, 255, 255, 100, 0, 0, 0, 0, 0, 0, 0, 42, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 68, 95, 154, 254, 255, 255, 255, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 224, 63, 0, 0, 0, 0, 0, 0, 244, 63, 0, 0, 0, 0, 0, 0, 0, 192, 0, 0, 0, 0, 0, 0, 8, 64, 0, 0, 0, 0, 0, 0, 18, 64, 0, 0, 0, 0, 0, 0, 23, 64, 0, 0, 0, 0, 0, 128, 24, 64, 77, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 109, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 7, 0, 0, 0, 7, 0, 0, 0, 10, 0, 0, 0, 11, 0, 0, 0, 97, 98, 104, 101, 108, 108, 111, 120, 121, 122, 113, 0, 0, 0, 0, 0, 123, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 6, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 119, 0, 0, 0, 0, 0, 0, 0, 1, 0, 254, 255, 3, 0, 0, 0, 5, 0, 6, 0, 7, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 9, 0, 0, 0, 112, 113, 113, 114, 114, 114, 115, 116, 116, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0 }
    let dict_stream: [512]u8 = [512]u8{ 255, 255, 255, 255, 144, 0, 0, 0, 16, 0, 0, 0, 0, 0, 10, 0, 12, 0, 6, 0, 5, 0, 8, 0, 10, 0, 0, 0, 0, 1, 4, 0, 4, 0, 0, 0, 188, 255, 255, 255, 4, 0, 0, 0, 1, 0, 0, 0, 20, 0, 0, 0, 16, 0, 24, 0, 8, 0, 6, 0, 7, 0, 12, 0, 16, 0, 20, 0, 16, 0, 0, 0, 0, 0, 1, 5, 20, 0, 0, 0, 64, 0, 0, 0, 28, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 100, 0, 0, 0, 8, 0, 8, 0, 0, 0, 4, 0, 8, 0, 0, 0, 12, 0, 0, 0, 8, 0, 12, 0, 8, 0, 7, 0, 8, 0, 0, 0, 0, 0, 0, 1, 8, 0, 0, 0, 4, 0, 4, 0, 4, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 168, 0, 0, 0, 20, 0, 0, 0, 0, 0, 0, 0, 12, 0, 20, 0, 6, 0, 5, 0, 8, 0, 12, 0, 12, 0, 0, 0, 0, 2, 4, 0, 20, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 8, 0, 10, 0, 0, 0, 4, 0, 8, 0, 0, 0, 16, 0, 0, 0, 0, 0, 10, 0, 24, 0, 12, 0, 4, 0, 8, 0, 10, 0, 0, 0, 76, 0, 0, 0, 16, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 97, 98, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 136, 0, 0, 0, 20, 0, 0, 0, 0, 0, 0, 0, 12, 0, 22, 0, 6, 0, 5, 0, 8, 0, 12, 0, 12, 0, 0, 0, 0, 3, 4, 0, 24, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 24, 0, 12, 0, 4, 0, 8, 0, 10, 0, 0, 0, 60, 0, 0, 0, 16, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0 }
    var cols: [16]arrow.Column = zero
    var names: [16]str = zero

    // 1: schema count and names (pre-order, children included).
    let (count, e) = arrow.columns(stream[..], cols[..], names[..])
    if e != ok || count != 10usize { os.exit(1i32) }
    let expected_names: [10]str = [10]str{ "i32c", "i64c", "f64c", "bc", "s", "li", "item", "st", "a", "b" }
    var i = 0usize
    while i < 10usize {
        if !mem.eq[u8](names[i], expected_names[i]) { os.exit(1i32) }
        i += 1usize
    }

    // 2: kinds, lengths and null counts.
    expect_kind(&cols[0usize], .Int32, 7usize, 2usize, 2i32)
    expect_kind(&cols[1usize], .Int64, 7usize, 0usize, 2i32)
    expect_kind(&cols[2usize], .Float64, 7usize, 0usize, 2i32)
    expect_kind(&cols[3usize], .Bool, 7usize, 3usize, 2i32)
    expect_kind(&cols[4usize], .Utf8, 7usize, 2usize, 2i32)
    expect_kind(&cols[5usize], .List, 7usize, 1usize, 2i32)
    expect_kind(&cols[6usize], .Int32, 7usize, 0usize, 2i32)
    expect_kind(&cols[7usize], .Struct, 7usize, 1usize, 2i32)
    expect_kind(&cols[8usize], .Int16, 7usize, 0usize, 2i32)
    expect_kind(&cols[9usize], .Utf8, 7usize, 0usize, 2i32)

    // 3: int32 with nulls.
    let i32_values: [7]i32 = [7]i32{ 5, 0, -7, 100, 0, 42, -1 }
    let i32_valid: [7]bool = [7]bool{ true, false, true, true, false, true, true }
    i = 0usize
    while i < 7usize {
        let (v, valid, v_error) = arrow.get_i32(&cols[0usize], i)
        if v_error != ok || valid != i32_valid[i] || v != i32_values[i] { os.exit(3i32) }
        if arrow.is_valid(&cols[0usize], i) != i32_valid[i] { os.exit(3i32) }
        let (w, w_valid, w_error) = arrow.get_i64(&cols[0usize], i)
        if w_error != ok || w_valid != i32_valid[i] || w != i64(i32_values[i]) { os.exit(3i32) }
        i += 1usize
    }
    let (_, _, beyond) = arrow.get_i32(&cols[0usize], 7usize)
    if beyond != arrow.Invalid { os.exit(3i32) }

    // 4: int64 and float64.
    let i64_values: [7]i64 = [7]i64{ 1, 2, 3, 4, 5, -6000000000, 7 }
    let f64_values: [7]f64 = [7]f64{ 0.5, 1.25, -2.0, 3.0, 4.5, 5.75, 6.125 }
    i = 0usize
    while i < 7usize {
        let (v, valid, v_error) = arrow.get_i64(&cols[1usize], i)
        if v_error != ok || !valid || v != i64_values[i] { os.exit(4i32) }
        let (f, f_valid, f_error) = arrow.get_f64(&cols[2usize], i)
        if f_error != ok || !f_valid || f != f64_values[i] { os.exit(4i32) }
        i += 1usize
    }
    let (_, _, narrow) = arrow.get_i32(&cols[1usize], 0usize)
    if narrow != arrow.Invalid { os.exit(4i32) }

    // 5: bool with nulls.
    let bool_values: [7]bool = [7]bool{ true, false, false, true, false, false, false }
    let bool_valid: [7]bool = [7]bool{ true, false, true, true, false, false, true }
    i = 0usize
    while i < 7usize {
        let (v, valid, v_error) = arrow.get_bool(&cols[3usize], i)
        if v_error != ok || valid != bool_valid[i] || v != bool_values[i] { os.exit(5i32) }
        i += 1usize
    }

    // 6: utf8 with nulls (an empty valid string is not a null).
    let s_values: [7]str = [7]str{ "ab", "", "", "hello", "", "xyz", "q" }
    let s_valid: [7]bool = [7]bool{ true, false, true, true, false, true, true }
    i = 0usize
    while i < 7usize {
        let (v, valid, v_error) = arrow.get_utf8(&cols[4usize], i)
        if v_error != ok || valid != s_valid[i] || !mem.eq[u8](v, s_values[i]) { os.exit(6i32) }
        i += 1usize
    }
    let (start, end, range_error) = arrow.list_range(&cols[4usize], 3usize)
    if range_error != ok || start != 2usize || end != 7usize { os.exit(6i32) }

    // 7: list ranges and child values.
    let li_offsets: [8]usize = [8]usize{ 0, 2, 2, 2, 3, 6, 6, 7 }
    let li_valid: [7]bool = [7]bool{ true, true, false, true, true, true, true }
    let (item, item_error) = arrow.struct_child(cols[..count], 5usize, 0usize)
    if item_error != ok || item != 6usize || usize(cols[5usize].child) != 6usize { os.exit(7i32) }
    i = 0usize
    while i < 7usize {
        let (lo, hi, lo_error) = arrow.list_range(&cols[5usize], i)
        if lo_error != ok { os.exit(7i32) }
        if li_valid[i] {
            if lo != li_offsets[i] || hi != li_offsets[i + 1usize] { os.exit(7i32) }
        } else if lo != 0usize || hi != 0usize {
            os.exit(7i32)
        }
        var k = lo
        while k < hi {
            let (v, valid, v_error) = arrow.get_i32(&cols[item], k)
            if v_error != ok || !valid || v != i32(k + 1usize) { os.exit(7i32) }
            k += 1usize
        }
        i += 1usize
    }
    let (_, _, not_a_list) = arrow.list_range(&cols[1usize], 0usize)
    if not_a_list != arrow.Invalid { os.exit(7i32) }

    // 8: struct children.
    let (child_a, a_error) = arrow.struct_child(cols[..count], 7usize, 0usize)
    let (child_b, b_error) = arrow.struct_child(cols[..count], 7usize, 1usize)
    if a_error != ok || b_error != ok || child_a != 8usize || child_b != 9usize { os.exit(8i32) }
    let (_, none_error) = arrow.struct_child(cols[..count], 7usize, 2usize)
    if none_error != arrow.Invalid { os.exit(8i32) }
    let a_values: [7]i64 = [7]i64{ 1, -2, 3, 0, 5, 6, 7 }
    let b_values: [7]str = [7]str{ "p", "qq", "", "", "rrr", "s", "tt" }
    let st_valid: [7]bool = [7]bool{ true, true, true, false, true, true, true }
    i = 0usize
    while i < 7usize {
        if arrow.is_valid(&cols[7usize], i) != st_valid[i] { os.exit(8i32) }
        let (v, valid, v_error) = arrow.get_i64(&cols[child_a], i)
        if v_error != ok || !valid || v != a_values[i] { os.exit(8i32) }
        let (s, s_ok, s_error) = arrow.get_utf8(&cols[child_b], i)
        if s_error != ok || !s_ok || !mem.eq[u8](s, b_values[i]) { os.exit(8i32) }
        i += 1usize
    }

    // 9: a dictionary-encoded column is unsupported.
    let (_, dict_error) = arrow.columns(dict_stream[..], cols[..], names[..])
    if dict_error != arrow.Unsupported { os.exit(9i32) }

    // 10: truncated streams are malformed (inside the body, inside the
    // metadata, and inside the framing), and too few column slots is TooSmall.
    let (_, body_error) = arrow.columns(stream[..1400usize], cols[..], names[..])
    if body_error != arrow.Malformed { os.exit(10i32) }
    let (_, meta_error) = arrow.columns(stream[..700usize], cols[..], names[..])
    if meta_error != arrow.Malformed { os.exit(10i32) }
    let (_, frame_error) = arrow.columns(stream[..6usize], cols[..], names[..])
    if frame_error != arrow.Malformed { os.exit(10i32) }
    let (_, room_error) = arrow.columns(stream[..], cols[..4usize], names[..])
    if room_error != arrow.TooSmall { os.exit(10i32) }
    let (again, again_error) = arrow.columns(stream[..], cols[..], names[..])
    if again_error != ok || again != 10usize { os.exit(10i32) }

    try io.print("fmt arrow ok\n")
    ret ok
}
