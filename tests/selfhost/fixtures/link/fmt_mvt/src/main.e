// `e.fmt.mvt` against a tile built by an independent encoder (scripts/gen_mvt_test.py): two layers, point, line and
// polygon features with relative geometry, a key/value table of every value type, and a truncated geometry list
// refused. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.mvt as mvt

fn main(a: *mem.Arena, args: []str) -> err {
    let tile: [234]u8 = [234]u8{ 26, 200, 1, 120, 2, 10, 6, 112, 108, 97, 99, 101, 115, 18, 21, 8, 7, 18, 4, 0, 0, 1, 1, 24, 1, 34, 9, 25, 50, 34, 39, 15, 190, 1, 190, 15, 18, 22, 18, 2, 2, 2, 24, 2, 34, 14, 9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8, 18, 38, 8, 9, 18, 8, 3, 3, 4, 4, 5, 5, 6, 6, 24, 3, 34, 22, 9, 0, 0, 26, 16, 0, 0, 16, 15, 0, 15, 9, 4, 11, 26, 0, 8, 8, 0, 0, 7, 15, 26, 4, 110, 97, 109, 101, 26, 5, 99, 108, 97, 115, 115, 26, 4, 114, 97, 110, 107, 26, 5, 114, 97, 116, 105, 111, 26, 3, 98, 105, 103, 26, 5, 100, 101, 108, 116, 97, 26, 4, 111, 112, 101, 110, 34, 6, 10, 4, 79, 115, 108, 111, 34, 6, 10, 4, 99, 105, 116, 121, 34, 2, 32, 3, 34, 9, 25, 0, 0, 0, 0, 0, 0, 224, 63, 34, 7, 40, 128, 128, 128, 128, 128, 32, 34, 3, 48, 153, 1, 34, 2, 56, 1, 34, 5, 21, 0, 0, 192, 63, 40, 128, 64, 26, 29, 10, 5, 119, 97, 116, 101, 114, 18, 20, 8, 1, 24, 3, 34, 14, 9, 0, 0, 26, 128, 64, 0, 0, 128, 64, 255, 63, 0, 15 }
    let bad: [14]u8 = [14]u8{ 26, 12, 10, 1, 120, 18, 7, 24, 1, 34, 3, 25, 2, 2 }
    // A layer with uint_value = 2^63, u64::MAX and a small value. Each value
    // message is field 5 (tag 40); the last byte of the two long varints is 1.
    let uints: [37]u8 = [37]u8{ 26, 35, 10, 1, 117, 34, 11, 40, 128, 128, 128, 128, 128, 128, 128, 128, 128, 1, 34, 11, 40, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1, 34, 2, 40, 42, 120, 2 }
    let (layers, e) = mvt.parse(a, tile[0..])
    if e != ok || layers.len != 2usize { os.exit(1) }
    if !str.eq(layers[0].name, "places") || layers[0].version != 2u32 || layers[0].extent != 8192u32 { os.exit(2) }
    if layers[0].keys.len != 7usize || !str.eq(layers[0].keys[0], "name") || !str.eq(layers[0].keys[6], "open") { os.exit(3) }
    if layers[0].values.len != 8usize || layers[0].features.len != 3usize { os.exit(4) }
    if layers[0].values[0].kind != mvt.VALUE_STRING || !str.eq(layers[0].values[0].text, "Oslo") { os.exit(5) }
    if layers[0].values[2].kind != mvt.VALUE_INT || layers[0].values[2].integer != 3i64 { os.exit(6) }
    if layers[0].values[3].kind != mvt.VALUE_DOUBLE || layers[0].values[3].number != 0.5f64 { os.exit(7) }
    if layers[0].values[4].kind != mvt.VALUE_UINT || layers[0].values[4].integer != 1099511627776i64 { os.exit(8) }
    if layers[0].values[5].kind != mvt.VALUE_SINT || layers[0].values[5].integer != 0i64 - 77i64 { os.exit(9) }
    if layers[0].values[6].kind != mvt.VALUE_BOOL || layers[0].values[6].integer != 1i64 { os.exit(10) }
    if layers[0].values[7].kind != mvt.VALUE_FLOAT || layers[0].values[7].number != 1.5f64 { os.exit(11) }
    let p = layers[0].features[0]
    if !p.has_id || p.id != 7u64 || p.kind != mvt.KIND_POINT || p.points.len != 3usize || p.parts.len != 0usize { os.exit(12) }
    if p.tags.len != 4usize || p.tags[0] != 0u32 || p.tags[3] != 1u32 { os.exit(13) }
    if p.points[0].x != 25i32 || p.points[0].y != 17i32 { os.exit(14) }
    if p.points[1].x != 5i32 || p.points[1].y != 9i32 { os.exit(15) }
    if p.points[2].x != 100i32 || p.points[2].y != 1000i32 { os.exit(16) }
    let l = layers[0].features[1]
    if l.has_id || l.kind != mvt.KIND_LINE || l.points.len != 5usize || l.parts.len != 2usize { os.exit(17) }
    if l.parts[0] != 3usize || l.parts[1] != 5usize { os.exit(18) }
    if l.points[0].x != 2i32 || l.points[0].y != 2i32 { os.exit(19) }
    if l.points[1].x != 2i32 || l.points[1].y != 10i32 { os.exit(20) }
    if l.points[2].x != 10i32 || l.points[2].y != 10i32 { os.exit(21) }
    if l.points[3].x != 1i32 || l.points[3].y != 1i32 { os.exit(22) }
    if l.points[4].x != 3i32 || l.points[4].y != 5i32 { os.exit(23) }
    let g = layers[0].features[2]
    if !g.has_id || g.id != 9u64 || g.kind != mvt.KIND_POLYGON || g.points.len != 8usize || g.parts.len != 2usize { os.exit(24) }
    if g.parts[0] != 4usize || g.parts[1] != 8usize { os.exit(25) }
    if g.points[0].x != 0i32 || g.points[0].y != 0i32 { os.exit(26) }
    if g.points[1].x != 8i32 || g.points[1].y != 0i32 { os.exit(27) }
    if g.points[2].x != 8i32 || g.points[2].y != 8i32 { os.exit(28) }
    if g.points[3].x != 0i32 || g.points[3].y != 8i32 { os.exit(29) }
    if g.points[4].x != 2i32 || g.points[4].y != 2i32 { os.exit(30) }
    if g.points[5].x != 2i32 || g.points[5].y != 6i32 { os.exit(31) }
    if g.points[6].x != 6i32 || g.points[6].y != 6i32 { os.exit(32) }
    if g.points[7].x != 6i32 || g.points[7].y != 2i32 { os.exit(33) }
    if !str.eq(layers[1].name, "water") || layers[1].extent != 4096u32 || layers[1].version != 1u32 || layers[1].features.len != 1usize { os.exit(34) }
    if layers[1].features[0].points.len != 4usize || layers[1].features[0].points[2].x != 4096i32 || layers[1].features[0].points[2].y != 4096i32 { os.exit(35) }
    let (bl, be) = mvt.parse(a, bad[0..])
    if be == ok { os.exit(36) }
    let (unsigned_layers, unsigned_error) = mvt.parse(a, uints[..])
    if unsigned_error != ok || unsigned_layers.len != 1usize || unsigned_layers[0usize].values.len != 3usize { os.exit(37) }
    let high = unsigned_layers[0usize].values[0usize]
    let highest = unsigned_layers[0usize].values[1usize]
    let small = unsigned_layers[0usize].values[2usize]
    if high.kind != mvt.VALUE_UINT || high.unsigned != 9223372036854775808u64 { os.exit(38) }
    if highest.kind != mvt.VALUE_UINT || highest.unsigned != 18446744073709551615u64 { os.exit(39) }
    if small.kind != mvt.VALUE_UINT || small.unsigned != 42u64 || small.integer != 42i64 { os.exit(40) }
    // Valid i32 deltas may add up outside the Point coordinate range. These must be malformed
    // geometry, not a checked arithmetic trap or a wrapped point.
    let beyond_positive: [6]u32 = [6]u32{ 9u32, 4294967294u32, 0u32, 10u32, 2u32, 0u32 }
    let (_, _, positive_error) = mvt.decode_geometry(a, mvt.KIND_LINE, beyond_positive[..])
    if positive_error != mvt.Invalid { os.exit(41) }
    let beyond_negative: [6]u32 = [6]u32{ 9u32, 1u32, 0u32, 10u32, 4294967295u32, 0u32 }
    let (_, _, negative_error) = mvt.decode_geometry(a, mvt.KIND_LINE, beyond_negative[..])
    if negative_error != mvt.Invalid { os.exit(42) }
    // Packed MVT geometry and tag values are uint32; a larger protobuf varint
    // must not silently become zero through narrowing.
    let too_wide: [5]u8 = [5]u8{ 128u8, 128u8, 128u8, 128u8, 16u8 }
    let (_, wide_error) = mvt.packed(a, too_wide[..])
    if wide_error != mvt.Invalid { os.exit(43) }
    // ClosePath belongs to polygon rings and its command count is exactly one.
    let wrong_close: [1]u32 = [1]u32{ 15u32 }
    let (_, _, close_error) = mvt.decode_geometry(a, mvt.KIND_LINE, wrong_close[..])
    if close_error != mvt.Invalid { os.exit(44) }
    // MVT geometry commands have a grammar, not merely individually valid opcodes.
    let missing_close: [8]u32 = [8]u32{ 9u32, 0u32, 0u32, 18u32, 2u32, 0u32, 0u32, 2u32 }
    let premature_close: [4]u32 = [4]u32{ 9u32, 0u32, 0u32, 15u32 }
    let short_ring: [7]u32 = [7]u32{ 9u32, 0u32, 0u32, 10u32, 2u32, 0u32, 15u32 }
    let line_first: [3]u32 = [3]u32{ 10u32, 0u32, 0u32 }
    let multi_move_line: [8]u32 = [8]u32{ 17u32, 0u32, 0u32, 0u32, 0u32, 10u32, 2u32, 0u32 }
    let point_line: [6]u32 = [6]u32{ 9u32, 0u32, 0u32, 10u32, 2u32, 0u32 }
    let (_, _, missing_close_error) = mvt.decode_geometry(a, mvt.KIND_POLYGON, missing_close[..])
    let (_, _, premature_close_error) = mvt.decode_geometry(a, mvt.KIND_POLYGON, premature_close[..])
    let (_, _, short_ring_error) = mvt.decode_geometry(a, mvt.KIND_POLYGON, short_ring[..])
    let (_, _, line_first_error) = mvt.decode_geometry(a, mvt.KIND_LINE, line_first[..])
    let (_, _, multi_move_error) = mvt.decode_geometry(a, mvt.KIND_LINE, multi_move_line[..])
    let (_, _, point_line_error) = mvt.decode_geometry(a, mvt.KIND_POINT, point_line[..])
    if missing_close_error != mvt.Invalid || premature_close_error != mvt.Invalid || short_ring_error != mvt.Invalid || line_first_error != mvt.Invalid || multi_move_error != mvt.Invalid || point_line_error != mvt.Invalid { os.exit(45) }
    let valid_ring: [9]u32 = [9]u32{ 9u32, 0u32, 0u32, 18u32, 2u32, 0u32, 0u32, 2u32, 15u32 }
    let (ring_points, ring_parts, ring_error) = mvt.decode_geometry(a, mvt.KIND_POLYGON, valid_ring[..])
    if ring_error != ok || ring_points.len != 3usize || ring_parts.len != 1usize || ring_parts[0usize] != 3usize { os.exit(46) }
    ret ok
}
