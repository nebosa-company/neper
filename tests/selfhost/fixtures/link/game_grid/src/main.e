// `e.game.grid` and `e.game.tilemap` (D270). Every expected value was computed
// independently rather than read off the implementation. Each check returns its own
// number when it fails; 0 is every check passed.

use e.mem
use e.math.fixed
use e.game.grid
use e.game.tilemap

fn main() -> i64 {
    // --- coordinates ---------------------------------------------------------------
    // Square: a tile is just its index times its size.
    let (sx, sy) = grid.to_world(.Square, grid.coord(3i32, 2i32), 16u32, 16u32)
    if sx != 3145728i32 || sy != 2097152i32 { ret 1i64 }
    // Isometric: q goes right and down, r goes left and down, at half width and height.
    let (ix, iy) = grid.to_world(.IsoDiamond, grid.coord(2i32, 1i32), 64u32, 32u32)
    if ix != 2097152i32 || iy != 3145728i32 { ret 2i64 }
    // A pointy hex row is three quarters of a hex below the one above it.
    let (hx, hy) = grid.to_world(.HexPointy, grid.coord(2i32, 1i32), 64u32, 48u32)
    if hx != 10485760i32 || hy != 2359296i32 { ret 3i64 }
    // The origin is the origin in every shape.
    let (ox, oy) = grid.to_world(.HexFlat, grid.coord(0i32, 0i32), 64u32, 48u32)
    if ox != 0i32 || oy != 0i32 { ret 4i64 }

    // from_world floors, so a point just left of the origin is tile -1, not tile 0.
    // Truncation would fold the two together and every map would be wrong at the edge.
    let left = grid.from_world(.Square, -1i32, -1i32, 16u32, 16u32)
    if left.q != -1i32 || left.r != -1i32 { ret 5i64 }
    let inside = grid.from_world(.Square, 1114112i32, 0i32, 16u32, 16u32)
    if inside.q != 1i32 || inside.r != 0i32 { ret 6i64 }
    // Square and iso round-trip through world space.
    var tile = 0i32
    while tile < 6i32 {
        let start = grid.coord(tile, 2i32 - tile)
        let (wx, wy) = grid.to_world(.Square, start, 16u32, 16u32)
        if !grid.equal(grid.from_world(.Square, wx, wy, 16u32, 16u32), start) { ret 7i64 }
        tile += 1i32
    }

    // Four neighbours on a square or a diamond, six on a hex, always in one order.
    var around: [8]grid.Coord = zero
    let (square_count, square_error) = grid.neighbours(.Square, grid.coord(0i32, 0i32), around[..])
    if square_error != ok || square_count != 4usize { ret 8i64 }
    if around[0usize].q != 1i32 || around[0usize].r != 0i32 { ret 9i64 }
    let (hex_count, hex_error) = grid.neighbours(.HexPointy, grid.coord(0i32, 0i32), around[..])
    if hex_error != ok || hex_count != 6usize { ret 10i64 }
    // Every hex neighbour is exactly one away, which is what makes it a neighbour.
    var walk = 0usize
    while walk < 6usize {
        if grid.distance(.HexPointy, grid.coord(0i32, 0i32), around[walk]) != 1u32 { ret 11i64 }
        walk += 1usize
    }
    // A short buffer is refused rather than overrun.
    var cramped: [3]grid.Coord = zero
    let (cramped_count, cramped_error) = grid.neighbours(.Square, grid.coord(0i32, 0i32), cramped[..])
    if cramped_error != grid.Bounds { ret 12i64 }

    // Manhattan on a square, hex distance on a hex.
    if grid.distance(.Square, grid.coord(0i32, 0i32), grid.coord(3i32, -2i32)) != 5u32 { ret 13i64 }
    if grid.distance(.IsoDiamond, grid.coord(0i32, 0i32), grid.coord(3i32, -2i32)) != 5u32 { ret 14i64 }
    if grid.distance(.HexPointy, grid.coord(0i32, 0i32), grid.coord(2i32, -1i32)) != 2u32 { ret 15i64 }
    if grid.distance(.HexPointy, grid.coord(0i32, 0i32), grid.coord(-2i32, 1i32)) != 2u32 { ret 16i64 }
    if grid.distance(.Square, grid.coord(4i32, 4i32), grid.coord(4i32, 4i32)) != 0u32 { ret 17i64 }

    // A line includes both ends, and every step moves exactly one cell.
    var path: [16]grid.Coord = zero
    let (path_count, path_error) = grid.line(.Square, grid.coord(0i32, 0i32), grid.coord(3i32, -2i32), path[..])
    if path_error != ok || path_count != 6usize { ret 18i64 }
    if !grid.equal(path[0usize], grid.coord(0i32, 0i32)) { ret 19i64 }
    if !grid.equal(path[5usize], grid.coord(3i32, -2i32)) { ret 20i64 }
    var step = 1usize
    while step < path_count {
        if grid.distance(.Square, path[step - 1usize], path[step]) != 1u32 { ret 21i64 }
        step += 1usize
    }
    // The same holds on a hex, which is what cube rounding is for.
    let (hex_path, hex_path_error) = grid.line(.HexPointy, grid.coord(0i32, 0i32), grid.coord(3i32, -1i32), path[..])
    if hex_path_error != ok { ret 22i64 }
    if !grid.equal(path[0usize], grid.coord(0i32, 0i32)) { ret 23i64 }
    if !grid.equal(path[hex_path - 1usize], grid.coord(3i32, -1i32)) { ret 24i64 }
    step = 1usize
    while step < hex_path {
        if grid.distance(.HexPointy, path[step - 1usize], path[step]) != 1u32 { ret 25i64 }
        step += 1usize
    }

    // A ring is the cells at exactly `radius`, under the distance that shape uses.
    var spread: [64]grid.Coord = zero
    let (ring_count, ring_error) = grid.ring(.HexPointy, grid.coord(0i32, 0i32), 2u32, spread[..])
    if ring_error != ok || ring_count != 12usize { ret 26i64 }
    walk = 0usize
    while walk < ring_count {
        if grid.distance(.HexPointy, grid.coord(0i32, 0i32), spread[walk]) != 2u32 { ret 27i64 }
        walk += 1usize
    }
    let (diamond_count, diamond_error) = grid.ring(.Square, grid.coord(0i32, 0i32), 3u32, spread[..])
    if diamond_error != ok || diamond_count != 12usize { ret 28i64 }
    let (area_count, area_error) = grid.area(.HexPointy, grid.coord(0i32, 0i32), 2u32, spread[..])
    if area_error != ok || area_count != 19usize { ret 29i64 }
    let (square_area, square_area_error) = grid.area(.Square, grid.coord(0i32, 0i32), 3u32, spread[..])
    if square_area_error != ok || square_area != 25usize { ret 30i64 }
    let (centre_only, centre_error) = grid.ring(.Square, grid.coord(5i32, 5i32), 0u32, spread[..])
    if centre_error != ok || centre_only != 1usize { ret 31i64 }

    // Depth sorts by row, or by the diagonal for a diamond, with elevation breaking ties.
    if grid.depth(.IsoDiamond, grid.coord(2i32, 1i32), 5u8) != 773i32 { ret 32i64 }
    if grid.depth(.Square, grid.coord(2i32, 1i32), 5u8) != 261i32 { ret 33i64 }
    // A nearer row is always in front of a further one, whatever its elevation.
    if grid.depth(.IsoDiamond, grid.coord(0i32, 0i32), 255u8) >= grid.depth(.IsoDiamond, grid.coord(1i32, 0i32), 0u8) { ret 34i64 }

    // --- the tilemap ---------------------------------------------------------------
    var ground: [16]u16 = zero
    var scenery: [16]u16 = zero
    var solid: [1]u64 = zero
    var opaque: [1]u64 = zero
    var elevation: [16]u8 = zero
    var layers: [2]tilemap.Layer = zero
    layers[0usize] = tilemap.Layer { tiles: ground[..], width: 4u32, height: 4u32 }
    layers[1usize] = tilemap.Layer { tiles: scenery[..], width: 4u32, height: 4u32 }
    var map: tilemap.Map = zero
    if tilemap.init(&map, layers[..], 16u32, 16u32, solid[..], opaque[..], elevation[..]) != ok { ret 35i64 }

    // Layers that disagree about their size are refused, not trusted.
    var ragged: [2]tilemap.Layer = zero
    ragged[0usize] = tilemap.Layer { tiles: ground[..], width: 4u32, height: 4u32 }
    ragged[1usize] = tilemap.Layer { tiles: scenery[..], width: 2u32, height: 8u32 }
    var broken: tilemap.Map = zero
    if tilemap.init(&broken, ragged[..], 16u32, 16u32, solid[..], opaque[..], elevation[..]) != tilemap.Size { ret 36i64 }

    if tilemap.set(&map, 0usize, 1i32, 2i32, 7u16) != ok { ret 37i64 }
    let (read_back, read_error) = tilemap.at(map, 0usize, 1i32, 2i32)
    if read_error != ok || read_back != 7u16 { ret 38i64 }
    // The layers are independent.
    let (other_layer, other_error) = tilemap.at(map, 1usize, 1i32, 2i32)
    if other_error != ok || other_layer != 0u16 { ret 39i64 }
    let (absent, absent_error) = tilemap.at(map, 9usize, 1i32, 2i32)
    if absent_error != tilemap.Bounds { ret 40i64 }

    if !tilemap.in_bounds(map, 3i32, 3i32) { ret 41i64 }
    if tilemap.in_bounds(map, 4i32, 0i32) || tilemap.in_bounds(map, -1i32, 0i32) { ret 42i64 }

    // Off the map reads as solid and opaque, so a mover and a sightline stop at the edge
    // by the same test that stops them at a wall.
    if !tilemap.is_solid(map, -1i32, 0i32) { ret 43i64 }
    if !tilemap.is_opaque(map, 0i32, 4i32) { ret 44i64 }
    if tilemap.is_solid(map, 0i32, 0i32) { ret 45i64 }
    if tilemap.set_solid(&map, 2i32, 2i32, true) != ok { ret 46i64 }
    if !tilemap.is_solid(map, 2i32, 2i32) { ret 47i64 }
    if tilemap.is_opaque(map, 2i32, 2i32) { ret 48i64 }
    if tilemap.set_solid(&map, 2i32, 2i32, false) != ok || tilemap.is_solid(map, 2i32, 2i32) { ret 49i64 }

    if tilemap.set_height(&map, 3i32, 1i32, 4u8) != ok { ret 50i64 }
    if tilemap.height_at(map, 3i32, 1i32) != 4u8 { ret 51i64 }
    if tilemap.height_at(map, 0i32, 0i32) != 0u8 { ret 52i64 }
    if tilemap.height_at(map, 99i32, 99i32) != 0u8 { ret 53i64 }

    // A map is authored as tiles and derived into bits, not the other way round.
    if tilemap.set(&map, 0usize, 0i32, 0i32, 2u16) != ok { ret 54i64 }
    if tilemap.set(&map, 0usize, 1i32, 0i32, 3u16) != ok { ret 55i64 }
    var blocking: [1]u16 = zero
    blocking[0usize] = 2u16
    var blinding: [2]u16 = zero
    blinding[0usize] = 2u16
    blinding[1usize] = 3u16
    if tilemap.derive(&map, 0usize, blocking[..], blinding[..]) != ok { ret 56i64 }
    if !tilemap.is_solid(map, 0i32, 0i32) { ret 57i64 }
    if tilemap.is_solid(map, 1i32, 0i32) { ret 58i64 }          // tile 3 blinds but does not block
    if !tilemap.is_opaque(map, 1i32, 0i32) { ret 59i64 }
    if tilemap.is_opaque(map, 2i32, 0i32) { ret 60i64 }

    // World and tile agree in both directions, and floor again for negatives.
    let (wx, wy) = tilemap.to_world(map, 2i32, 3i32)
    if wx != 2097152i32 || wy != 3145728i32 { ret 61i64 }
    let (tx, ty) = tilemap.to_tile(map, wx, wy)
    if tx != 2i32 || ty != 3i32 { ret 62i64 }
    let (nx, ny) = tilemap.to_tile(map, -1i32, -1i32)
    if nx != -1i32 || ny != -1i32 { ret 63i64 }

    ret 0i64
}
