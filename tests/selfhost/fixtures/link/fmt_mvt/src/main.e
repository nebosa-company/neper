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
    ret ok
}
