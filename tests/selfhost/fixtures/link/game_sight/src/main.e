// `e.game.collide2d` and `e.game.vision` (D272). The visibility expectations come from
// an independent shadowcaster, not from this implementation. Each check returns its own
// number when it fails; 0 is every check passed.

use e.mem
use e.math.fixed
use e.game.tilemap
use e.game.collide2d
use e.game.vision

const ONE: i32 = 65536i32

fn fx(n: i32) -> i32 {
    ret n * ONE
}

fn main() -> i64 {
    // --- boxes -----------------------------------------------------------------------
    let here = collide2d.aabb(fx(4i32), 0i32, ONE, ONE)
    let there = collide2d.aabb(fx(8i32), 0i32, ONE, ONE)
    if collide2d.overlaps(here, there) { ret 1i64 }
    if !collide2d.overlaps(here, collide2d.aabb(fx(5i32), 0i32, ONE, ONE)) { ret 2i64 }
    // Touching exactly is not overlapping: the gap is 2 and the half widths sum to 2.
    if collide2d.overlaps(here, collide2d.aabb(fx(6i32), 0i32, ONE, ONE)) { ret 3i64 }

    // A sweep answers when contact happens along the motion, not merely whether. The gap
    // is 2 units and the motion is 4, so contact is at exactly half of it.
    let closing = collide2d.sweep(here, fx(4i32), 0i32, there)
    if !closing.hit { ret 4i64 }
    if closing.time != 32768i32 { ret 5i64 }
    if closing.normal_x != -1i32 || closing.normal_y != 0i32 { ret 6i64 }
    // A motion that stops exactly short does not touch.
    let short = collide2d.sweep(here, fx(2i32), 0i32, there)
    if short.hit { ret 7i64 }
    // Away is never a hit.
    if collide2d.sweep(here, fx(-4i32), 0i32, there).hit { ret 8i64 }
    // Nor is a motion on an axis that stays separated on the other.
    let past = collide2d.sweep(collide2d.aabb(0i32, 0i32, ONE, ONE), 0i32, fx(4i32), there)
    if past.hit { ret 9i64 }
    // Vertical closing reports a vertical normal.
    let falling = collide2d.sweep(collide2d.aabb(0i32, 0i32, ONE, ONE), 0i32, fx(4i32),
                                  collide2d.aabb(0i32, fx(4i32), ONE, ONE))
    if !falling.hit || falling.normal_y != -1i32 || falling.normal_x != 0i32 { ret 10i64 }

    // --- a map with a pillar ---------------------------------------------------------
    // Seven by seven, a solid border, and one pillar directly north of the middle.
    var ground: [49]u16 = zero
    var solid: [1]u64 = zero
    var opaque: [1]u64 = zero
    var elevation: [49]u8 = zero
    var layers: [1]tilemap.Layer = zero
    layers[0usize] = tilemap.Layer { tiles: ground[..], width: 7u32, height: 7u32 }
    var map: tilemap.Map = zero
    if tilemap.init(&map, layers[..], 16u32, 16u32, solid[..], opaque[..], elevation[..]) != ok { ret 11i64 }
    var edge = 0i32
    while edge < 7i32 {
        if tilemap.set_solid(&map, edge, 0i32, true) != ok { ret 12i64 }
        if tilemap.set_solid(&map, edge, 6i32, true) != ok { ret 13i64 }
        if tilemap.set_solid(&map, 0i32, edge, true) != ok { ret 14i64 }
        if tilemap.set_solid(&map, 6i32, edge, true) != ok { ret 15i64 }
        if tilemap.set_opaque(&map, edge, 0i32, true) != ok { ret 16i64 }
        if tilemap.set_opaque(&map, edge, 6i32, true) != ok { ret 17i64 }
        if tilemap.set_opaque(&map, 0i32, edge, true) != ok { ret 18i64 }
        if tilemap.set_opaque(&map, 6i32, edge, true) != ok { ret 19i64 }
        edge += 1i32
    }
    if tilemap.set_solid(&map, 3i32, 2i32, true) != ok { ret 20i64 }
    if tilemap.set_opaque(&map, 3i32, 2i32, true) != ok { ret 21i64 }

    // A ray north from the middle of tile (3,3) meets the pillar; south is clear until
    // the border. Tiles are 16 units, so the middle of (3,3) is at 56, 56.
    let middle = fx(56i32)
    let north = collide2d.ray_tiles(map, middle, middle, 0i32, fx(-32i32), ONE)
    if !north.hit { ret 22i64 }
    if north.normal_y != 1i32 { ret 23i64 }
    // 48 units east from 56 reaches x=104, which is the border tile; 32 units reaches
    // only tile 5, which is open, so that ray must report no hit.
    let east = collide2d.ray_tiles(map, middle, middle, fx(48i32), 0i32, ONE)
    if !east.hit { ret 24i64 }
    if collide2d.ray_tiles(map, middle, middle, fx(32i32), 0i32, ONE).hit { ret 65i64 }
    // A ray too short to reach anything reports no hit.
    let stubby = collide2d.ray_tiles(map, middle, middle, 0i32, fx(-1i32), ONE)
    if stubby.hit { ret 25i64 }

    // A box swept into the pillar stops before it rather than inside it.
    let mover = collide2d.aabb(middle, middle, fx(2i32), fx(2i32))
    let into_pillar = collide2d.sweep_tiles(mover, 0i32, fx(-24i32), map)
    if !into_pillar.hit { ret 26i64 }
    if into_pillar.normal_y != 1i32 { ret 27i64 }
    if into_pillar.time <= 0i32 || into_pillar.time >= ONE { ret 28i64 }

    // --- the broadphase --------------------------------------------------------------
    var heads: [16]u32 = zero
    var chain: [8]u32 = zero
    var grid: collide2d.Grid = zero
    if collide2d.grid_init(&grid, heads[..], chain[..], 4u32, 4u32, fx(32i32)) != ok { ret 29i64 }
    if collide2d.grid_insert(&grid, 0u32, collide2d.aabb(fx(16i32), fx(16i32), ONE, ONE)) != ok { ret 30i64 }
    if collide2d.grid_insert(&grid, 1u32, collide2d.aabb(fx(48i32), fx(16i32), ONE, ONE)) != ok { ret 31i64 }
    var near: [8]u32 = zero
    let (near_count, near_error) = collide2d.grid_near(grid, collide2d.aabb(fx(16i32), fx(16i32), ONE, ONE), near[..])
    if near_error != ok { ret 32i64 }
    // The broadphase answers a superset, so it must contain the body in that cell and
    // must not contain the one two cells away.
    var found_self = false
    var found_far = false
    var walk = 0usize
    while walk < near_count {
        if near[walk] == 0u32 { found_self = true }
        if near[walk] == 1u32 { found_far = true }
        walk += 1usize
    }
    if !found_self { ret 33i64 }
    if found_far { ret 34i64 }
    if collide2d.grid_clear(&grid) != ok { ret 35i64 }
    let (empty_count, empty_error) = collide2d.grid_near(grid, collide2d.aabb(fx(16i32), fx(16i32), ONE, ONE), near[..])
    if empty_error != ok || empty_count != 0usize { ret 36i64 }

    // --- field of view ----------------------------------------------------------------
    var seen: [1]u64 = zero
    var known: [1]u64 = zero
    var field: vision.Field = zero
    if vision.init(&field, 7u32, 7u32, seen[..], known[..]) != ok { ret 37i64 }
    if vision.cast(&field, map, 3i32, 3i32, 4u32) != ok { ret 38i64 }

    // The counts and cells below come from an independent shadowcaster over this map.
    if vision.visible_count(field) != 37usize { ret 39i64 }
    if !vision.is_visible(field, 3i32, 3i32) { ret 40i64 }
    // The pillar is lit; the two cells it shadows are not. This is the whole point.
    if !vision.is_visible(field, 3i32, 2i32) { ret 41i64 }
    if vision.is_visible(field, 3i32, 1i32) { ret 42i64 }
    if vision.is_visible(field, 3i32, 0i32) { ret 43i64 }
    // The open quarters and the corner are lit.
    if !vision.is_visible(field, 1i32, 1i32) { ret 44i64 }
    if !vision.is_visible(field, 5i32, 5i32) { ret 45i64 }
    if !vision.is_visible(field, 2i32, 2i32) { ret 46i64 }
    if !vision.is_visible(field, 4i32, 2i32) { ret 47i64 }
    if !vision.is_visible(field, 1i32, 3i32) { ret 48i64 }
    if !vision.is_visible(field, 5i32, 3i32) { ret 49i64 }

    // Explored is sticky and visible is not: clearing leaves the memory behind.
    if vision.cell(field, 3i32, 3i32) != .Visible { ret 50i64 }
    if vision.clear_visible(&field) != ok { ret 51i64 }
    if vision.is_visible(field, 3i32, 3i32) { ret 52i64 }
    if !vision.is_explored(field, 3i32, 3i32) { ret 53i64 }
    if vision.cell(field, 3i32, 3i32) != .Explored { ret 54i64 }
    // A cell never seen is neither.
    if vision.cell(field, 3i32, 1i32) != .Unseen { ret 55i64 }

    // Two fields merge into shared vision.
    var other_seen: [1]u64 = zero
    var other_known: [1]u64 = zero
    var ally: vision.Field = zero
    if vision.init(&ally, 7u32, 7u32, other_seen[..], other_known[..]) != ok { ret 56i64 }
    if vision.cast(&ally, map, 3i32, 1i32, 1u32) != ok { ret 57i64 }
    if !vision.is_visible(ally, 3i32, 1i32) { ret 58i64 }
    if vision.merge(&field, ally) != ok { ret 59i64 }
    if !vision.is_visible(field, 3i32, 1i32) { ret 60i64 }

    // Line of sight agrees with the fog: blocked through the pillar, clear across the
    // open row, and the pillar itself is visible from where it blocks.
    if vision.line_of_sight(map, 3i32, 3i32, 3i32, 1i32) { ret 61i64 }
    if !vision.line_of_sight(map, 3i32, 3i32, 1i32, 3i32) { ret 62i64 }
    if !vision.line_of_sight(map, 3i32, 3i32, 3i32, 2i32) { ret 63i64 }
    if !vision.line_of_sight(map, 3i32, 3i32, 3i32, 3i32) { ret 64i64 }

    ret 0i64
}
