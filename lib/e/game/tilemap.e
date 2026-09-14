// Layered tile grids, with solidity, opacity and elevation beside them (D249).
//
// The tiles are what is drawn; the three bitsets are what is simulated. Collision asks
// `is_solid`, vision asks `is_opaque`, and the isometric depth order asks `height_at`,
// so none of them has to know how many layers a map has or which of them is scenery.
// Keeping them apart also means a wall and a window differ by one bit rather than by a
// tile id every system would have to agree about.
//
// Every buffer is the caller's, as in `e.game.ecs`: the map allocates nothing and its
// size is whatever `init` was handed.

use e.mem
use e.math.fixed

type Layer = struct {
    tiles: []u16,
    width: u32,
    height: u32,
}

type Map = struct {
    layers: []Layer,
    tile_w: u32,
    tile_h: u32,
    solid: []u64,
    opaque: []u64,
    elevation: []u8,
}

error Bounds
error Size

fn cells(m: Map) -> usize {
    if m.layers.len == 0usize { ret 0usize }
    ret usize(m.layers[0usize].width) * usize(m.layers[0usize].height)
}

fn width(m: Map) -> u32 {
    if m.layers.len == 0usize { ret 0u32 }
    ret m.layers[0usize].width
}

fn height(m: Map) -> u32 {
    if m.layers.len == 0usize { ret 0u32 }
    ret m.layers[0usize].height
}

// Every layer is the same grid; only what is drawn in it differs. A map whose layers
// disagree about their size would make every index ambiguous, so it is refused here
// rather than trusted later.
fn init(m: *Map, layers: []Layer, tile_w: u32, tile_h: u32, solid: []u64, opaque: []u64, elevation: []u8) -> err {
    if layers.len == 0usize { ret Size }
    if tile_w == 0u32 || tile_h == 0u32 { ret Size }
    let across = layers[0usize].width
    let down = layers[0usize].height
    if across == 0u32 || down == 0u32 { ret Size }
    let total = usize(across) * usize(down)
    var scan = 0usize
    while scan < layers.len {
        if layers[scan].width != across || layers[scan].height != down { ret Size }
        if layers[scan].tiles.len < total { ret Size }
        scan += 1usize
    }
    let words = (total + 63usize) / 64usize
    if solid.len < words || opaque.len < words { ret Size }
    if elevation.len < total { ret Size }
    m.layers = layers
    m.tile_w = tile_w
    m.tile_h = tile_h
    m.solid = solid
    m.opaque = opaque
    m.elevation = elevation
    ret ok
}

fn in_bounds(m: Map, x: i32, y: i32) -> bool {
    if x < 0i32 || y < 0i32 { ret false }
    ret u32(x) < width(m) && u32(y) < height(m)
}

fn index_of(m: Map, x: i32, y: i32) -> usize {
    ret usize(y) * usize(width(m)) + usize(x)
}

fn at(m: Map, layer: usize, x: i32, y: i32) -> (u16, err) {
    if layer >= m.layers.len { ret (0u16, Bounds) }
    if !in_bounds(m, x, y) { ret (0u16, Bounds) }
    ret (m.layers[layer].tiles[index_of(m, x, y)], ok)
}

fn set(m: *Map, layer: usize, x: i32, y: i32, tile: u16) -> err {
    if layer >= m.layers.len { ret Bounds }
    if !in_bounds(*m, x, y) { ret Bounds }
    m.layers[layer].tiles[index_of(*m, x, y)] = tile
    ret ok
}

fn bit_test(words: []const u64, index: usize) -> bool {
    ret (words[index / 64usize] & (1u64 << u32(index % 64usize))) != 0u64
}

fn bit_assign(words: []u64, index: usize, value: bool) {
    let mask = 1u64 << u32(index % 64usize)
    if value {
        words[index / 64usize] = words[index / 64usize] | mask
    } else {
        words[index / 64usize] = words[index / 64usize] & ~mask
    }
}

// Off the map reads as solid and as opaque. A mover that walks off the edge is stopped
// by the same test that stops it at a wall, and sight does not run out past the border,
// so neither caller needs a bounds check of its own.
fn is_solid(m: Map, x: i32, y: i32) -> bool {
    if !in_bounds(m, x, y) { ret true }
    ret bit_test(m.solid, index_of(m, x, y))
}

fn is_opaque(m: Map, x: i32, y: i32) -> bool {
    if !in_bounds(m, x, y) { ret true }
    ret bit_test(m.opaque, index_of(m, x, y))
}

fn set_solid(m: *Map, x: i32, y: i32, value: bool) -> err {
    if !in_bounds(*m, x, y) { ret Bounds }
    bit_assign(m.solid, index_of(*m, x, y), value)
    ret ok
}

fn set_opaque(m: *Map, x: i32, y: i32, value: bool) -> err {
    if !in_bounds(*m, x, y) { ret Bounds }
    bit_assign(m.opaque, index_of(*m, x, y), value)
    ret ok
}

fn height_at(m: Map, x: i32, y: i32) -> u8 {
    if !in_bounds(m, x, y) { ret 0u8 }
    ret m.elevation[index_of(m, x, y)]
}

fn set_height(m: *Map, x: i32, y: i32, value: u8) -> err {
    if !in_bounds(*m, x, y) { ret Bounds }
    m.elevation[index_of(*m, x, y)] = value
    ret ok
}

// The square mapping, which is what a tilemap is indexed by whatever shape it is drawn
// in: `e.game.grid` converts a tile to the diamond or the hex when it is time to draw.
fn to_tile(m: Map, wx: fixed.Fx, wy: fixed.Fx) -> (i32, i32) {
    if m.tile_w == 0u32 || m.tile_h == 0u32 { ret (0i32, 0i32) }
    let across = i64(m.tile_w) << 16u32
    let down = i64(m.tile_h) << 16u32
    ret (i32(floor_div(i64(wx), across)), i32(floor_div(i64(wy), down)))
}

fn to_world(m: Map, tx: i32, ty: i32) -> (fixed.Fx, fixed.Fx) {
    ret (i32((i64(tx) * i64(m.tile_w)) << 16u32), i32((i64(ty) * i64(m.tile_h)) << 16u32))
}

fn floor_div(a: i64, b: i64) -> i64 {
    if b == 0i64 { ret 0i64 }
    var quotient = a / b
    if (a % b != 0i64) && ((a < 0i64) != (b < 0i64)) { quotient = quotient - 1i64 }
    ret quotient
}

// Fill the solidity and opacity of a whole layer from a table of which tile ids block.
// A map is usually authored as tiles and derived into bits, not the other way round.
fn derive(m: *Map, layer: usize, solid_ids: []const u16, opaque_ids: []const u16) -> err {
    if layer >= m.layers.len { ret Bounds }
    var y = 0i32
    while u32(y) < height(*m) {
        var x = 0i32
        while u32(x) < width(*m) {
            let (tile, tile_error) = at(*m, layer, x, y)
            if tile_error != ok { ret tile_error }
            var blocks = false
            var at_id = 0usize
            while at_id < solid_ids.len {
                if solid_ids[at_id] == tile { blocks = true }
                at_id += 1usize
            }
            var blinds = false
            at_id = 0usize
            while at_id < opaque_ids.len {
                if opaque_ids[at_id] == tile { blinds = true }
                at_id += 1usize
            }
            bit_assign(m.solid, index_of(*m, x, y), blocks)
            bit_assign(m.opaque, index_of(*m, x, y), blinds)
            x += 1i32
        }
        y += 1i32
    }
    ret ok
}
