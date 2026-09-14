// `e.game.ai` and `e.game.input` (D288). The path expectations come from an independent
// A* over the same map. Each check returns its own number when it fails; 0 is every
// check passed.

use e.mem
use e.math.fixed
use e.algo.rand
use e.game.tilemap
use e.game.ai
use e.game.input

fn fx(n: i32) -> i32 {
    ret n * 65536i32
}

const MOVE_LEFT: u16 = 10u16
const MOVE_RIGHT: u16 = 11u16
const ATTACK: u16 = 12u16
const JUMP: u16 = 13u16

fn main() -> i64 {
    // --- steering ----------------------------------------------------------------------
    let still = ai.Agent { x: 0i32, y: 0i32, vx: 0i32, vy: 0i32, max_speed: fx(2i32) }
    // Seek east: all the speed on x, none on y, and it is a desired velocity minus the
    // current one, so a still agent is asked for the whole thing.
    let east = ai.seek(still, fx(10i32), 0i32)
    if east.x != fx(2i32) { ret 1i64 }
    if east.y != 0i32 { ret 2i64 }
    // Flee is the exact opposite.
    let away = ai.flee(still, fx(10i32), 0i32)
    if away.x != 0i32 - east.x || away.y != 0i32 - east.y { ret 3i64 }
    // An agent already moving at full speed toward the target needs no push.
    let moving = ai.Agent { x: 0i32, y: 0i32, vx: fx(2i32), vy: 0i32, max_speed: fx(2i32) }
    let settled = ai.seek(moving, fx(10i32), 0i32)
    if settled.x != 0i32 { ret 4i64 }

    // Arrive slows inside the radius: at half the radius, half the speed.
    let closing = ai.arrive(still, fx(4i32), 0i32, fx(8i32))
    if closing.x != fx(1i32) { ret 5i64 }
    // Outside the radius it is just seek.
    let far = ai.arrive(still, fx(40i32), 0i32, fx(8i32))
    if far.x != fx(2i32) { ret 6i64 }
    // On top of the target it brakes rather than dividing by zero.
    let atop = ai.arrive(moving, 0i32, 0i32, fx(8i32))
    if atop.x != 0i32 - fx(2i32) { ret 7i64 }

    // Separation pushes away from a close neighbour and ignores a distant one.
    var crowd: [2]ai.Agent = zero
    crowd[0usize] = ai.Agent { x: fx(1i32), y: 0i32, vx: 0i32, vy: 0i32, max_speed: fx(2i32) }
    crowd[1usize] = ai.Agent { x: fx(50i32), y: 0i32, vx: 0i32, vy: 0i32, max_speed: fx(2i32) }
    let apart = ai.separate(still, crowd[0usize..2usize], fx(4i32))
    if apart.x >= 0i32 { ret 8i64 }
    if apart.y != 0i32 { ret 9i64 }
    // With a radius that reaches neither, nothing pushes.
    let alone = ai.separate(still, crowd[0usize..2usize], 0i32)
    if alone.x != 0i32 || alone.y != 0i32 { ret 10i64 }

    // Combine is a weighted sum; a weight of zero drops its part entirely.
    var parts: [2]ai.Steer = zero
    parts[0usize] = ai.steer(fx(4i32), 0i32)
    parts[1usize] = ai.steer(0i32, fx(8i32))
    var weights: [2]i32 = zero
    weights[0usize] = 32768i32
    weights[1usize] = 0i32
    let blended = ai.combine(parts[0usize..2usize], weights[0usize..2usize])
    if blended.x != fx(2i32) { ret 11i64 }
    if blended.y != 0i32 { ret 12i64 }
    // Limit clamps magnitude but keeps direction: 3-4-5 capped at 5 is unchanged.
    let exact = ai.limit(ai.steer(fx(3i32), fx(4i32)), fx(5i32))
    if exact.x != fx(3i32) || exact.y != fx(4i32) { ret 13i64 }
    let clipped = ai.limit(ai.steer(fx(30i32), fx(40i32)), fx(5i32))
    if fixed.length(clipped.x, clipped.y) > fx(5i32) + 64i32 { ret 14i64 }

    // --- behaviour trees ------------------------------------------------------------------
    // A selector over: (sequence: can-see AND in-range -> attack), else chase.
    var tree: [7]ai.Behavior = zero
    tree[0usize] = ai.Behavior { kind: .Selector, first_child: 1u16, child_count: 2u16, id: 0u16 }
    tree[1usize] = ai.Behavior { kind: .Sequence, first_child: 3u16, child_count: 3u16, id: 0u16 }
    tree[2usize] = ai.Behavior { kind: .Action, first_child: 0u16, child_count: 0u16, id: 99u16 }
    tree[3usize] = ai.Behavior { kind: .Condition, first_child: 0u16, child_count: 0u16, id: 0u16 }
    tree[4usize] = ai.Behavior { kind: .Condition, first_child: 0u16, child_count: 0u16, id: 1u16 }
    tree[5usize] = ai.Behavior { kind: .Action, first_child: 0u16, child_count: 0u16, id: 42u16 }
    tree[6usize] = ai.Behavior { kind: .Invert, first_child: 3u16, child_count: 1u16, id: 0u16 }

    var conditions: [2]bool = zero
    var action = 0u16
    // Neither condition holds: the sequence fails on the first, the selector falls through
    // to the chase action.
    conditions[0usize] = false
    conditions[1usize] = false
    if ai.run(tree[..], 0u16, conditions[0usize..2usize], &action) != .Running { ret 15i64 }
    if action != 99u16 { ret 16i64 }
    // Can see but not in range: the sequence still fails, so still chase.
    conditions[0usize] = true
    if ai.run(tree[..], 0u16, conditions[0usize..2usize], &action) != .Running { ret 17i64 }
    if action != 99u16 { ret 18i64 }
    // Both hold: the sequence reaches the attack.
    conditions[1usize] = true
    if ai.run(tree[..], 0u16, conditions[0usize..2usize], &action) != .Running { ret 19i64 }
    if action != 42u16 { ret 20i64 }
    // Invert flips a condition's verdict.
    conditions[0usize] = true
    if ai.run(tree[..], 6u16, conditions[0usize..2usize], &action) != .Failure { ret 21i64 }
    conditions[0usize] = false
    if ai.run(tree[..], 6u16, conditions[0usize..2usize], &action) != .Success { ret 22i64 }
    // A node index past the table fails rather than reading past it.
    if ai.run(tree[..], 900u16, conditions[0usize..2usize], &action) != .Failure { ret 23i64 }

    // --- pathfinding -----------------------------------------------------------------------
    // A seven by seven room with a solid border and a wall across the middle, gapped at
    // x=4, so the only way from the top half to the bottom is around the gap.
    var ground: [49]u16 = zero
    var solid: [1]u64 = zero
    var opaque: [1]u64 = zero
    var elevation: [49]u8 = zero
    var layers: [1]tilemap.Layer = zero
    layers[0usize] = tilemap.Layer { tiles: ground[..], width: 7u32, height: 7u32 }
    var map: tilemap.Map = zero
    if tilemap.init(&map, layers[..], 16u32, 16u32, solid[..], opaque[..], elevation[..]) != ok { ret 24i64 }
    var edge = 0i32
    while edge < 7i32 {
        if tilemap.set_solid(&map, edge, 0i32, true) != ok { ret 25i64 }
        if tilemap.set_solid(&map, edge, 6i32, true) != ok { ret 26i64 }
        if tilemap.set_solid(&map, 0i32, edge, true) != ok { ret 27i64 }
        if tilemap.set_solid(&map, 6i32, edge, true) != ok { ret 28i64 }
        edge += 1i32
    }
    var wall = 1i32
    while wall < 4i32 {
        if tilemap.set_solid(&map, wall, 3i32, true) != ok { ret 29i64 }
        wall += 1i32
    }

    var came_from: [49]u32 = zero
    var cost: [49]u32 = zero
    var heap: [64]u32 = zero
    var heap_f: [64]u32 = zero
    var seen: [1]u64 = zero
    var scratch: ai.Scratch = zero
    scratch.came_from = came_from[..]
    scratch.cost = cost[..]
    scratch.heap = heap[..]
    scratch.heap_f = heap_f[..]
    scratch.seen = seen[..]
    var route: [64]u32 = zero

    // Straight along an open row: three tiles including both ends.
    let (short_len, short_error) = ai.path_grid(map, 1i32, 1i32, 3i32, 1i32, &scratch, route[..])
    if short_error != ok { ret 30i64 }
    if short_len != 3usize { ret 31i64 }
    if route[0usize] != 8u32 { ret 32i64 }
    if route[2usize] != 10u32 { ret 33i64 }

    // Around the wall: eleven tiles, and it must pass through the gap at x=4.
    let (long_len, long_error) = ai.path_grid(map, 1i32, 1i32, 1i32, 5i32, &scratch, route[..])
    if long_error != ok { ret 34i64 }
    if long_len != 11usize { ret 35i64 }
    if route[0usize] != 8u32 { ret 36i64 }
    if route[long_len - 1usize] != 36u32 { ret 37i64 }
    // Every step is one tile from the last, which is what makes it a path.
    var step = 1usize
    var through_gap = false
    while step < long_len {
        let previous = route[step - 1usize]
        let current = route[step]
        let px = i32(previous % 7u32)
        let py = i32(previous / 7u32)
        let cx = i32(current % 7u32)
        let cy = i32(current / 7u32)
        var dx = cx - px
        var dy = cy - py
        if dx < 0i32 { dx = 0i32 - dx }
        if dy < 0i32 { dy = 0i32 - dy }
        if dx + dy != 1i32 { ret 38i64 }
        if tilemap.is_solid(map, cx, cy) { ret 39i64 }
        if cx == 4i32 && cy == 3i32 { through_gap = true }
        step += 1usize
    }
    if !through_gap { ret 40i64 }

    // A goal inside a wall is unreachable rather than nearly reached.
    let (blocked_len, blocked_error) = ai.path_grid(map, 1i32, 1i32, 2i32, 3i32, &scratch, route[..])
    if blocked_error != ai.Unreachable { ret 41i64 }
    // So is a goal off the map.
    let (off_len, off_error) = ai.path_grid(map, 1i32, 1i32, 99i32, 99i32, &scratch, route[..])
    if off_error != ai.Bounds { ret 42i64 }
    // Start and goal the same is a path of one.
    let (same_len, same_error) = ai.path_grid(map, 2i32, 2i32, 2i32, 2i32, &scratch, route[..])
    if same_error != ok || same_len != 1usize { ret 43i64 }

    // --- input -------------------------------------------------------------------------------
    var held_bits: [1]u64 = zero
    var pressed_bits: [1]u64 = zero
    var released_bits: [1]u64 = zero
    var ring: [8]u16 = zero
    var ages: [8]u16 = zero
    var pad: input.State = zero
    if input.init(&pad, held_bits[..], pressed_bits[..], released_bits[..], ring[..], ages[..]) != ok { ret 44i64 }

    var attack = input.Action { id: 0u16, primary: ATTACK, secondary: input.NONE }
    var walk = input.Axis { id: 1u16, negative: MOVE_LEFT, positive: MOVE_RIGHT }

    if input.begin(&pad) != ok { ret 45i64 }
    if input.apply(&pad, ATTACK, true) != ok { ret 46i64 }
    if !input.pressed(pad, attack) { ret 47i64 }
    if !input.held(pad, attack) { ret 48i64 }
    if input.released(pad, attack) { ret 49i64 }

    // A held key reported again does not register a second press.
    if input.begin(&pad) != ok { ret 50i64 }
    if input.apply(&pad, ATTACK, true) != ok { ret 51i64 }
    if input.pressed(pad, attack) { ret 52i64 }
    if !input.held(pad, attack) { ret 53i64 }

    // Releasing shows on the release edge for exactly one tick.
    if input.begin(&pad) != ok { ret 54i64 }
    if input.apply(&pad, ATTACK, false) != ok { ret 55i64 }
    if !input.released(pad, attack) { ret 56i64 }
    if input.held(pad, attack) { ret 57i64 }
    if input.begin(&pad) != ok { ret 58i64 }
    if input.released(pad, attack) { ret 59i64 }

    // The press is still buffered several ticks later -- the whole point of buffering --
    // and a tight window no longer sees it.
    if !input.buffered(pad, attack, 8u16) { ret 60i64 }
    if input.buffered(pad, attack, 1u16) { ret 61i64 }
    // Consuming it fires once and not again.
    if !input.consume(&pad, attack) { ret 62i64 }
    if input.consume(&pad, attack) { ret 63i64 }
    if input.buffered(pad, attack, 8u16) { ret 64i64 }

    // Opposite directions cancel rather than the later one winning.
    if input.apply(&pad, MOVE_RIGHT, true) != ok { ret 65i64 }
    if input.axis(pad, walk) != 65536i32 { ret 66i64 }
    if input.apply(&pad, MOVE_LEFT, true) != ok { ret 67i64 }
    if input.axis(pad, walk) != 0i32 { ret 68i64 }
    if input.apply(&pad, MOVE_RIGHT, false) != ok { ret 69i64 }
    if input.axis(pad, walk) != -65536i32 { ret 70i64 }

    // Rebinding changes what an action answers to, without touching the state.
    if input.rebind(&attack, JUMP, input.NONE) != ok { ret 71i64 }
    if input.begin(&pad) != ok { ret 72i64 }
    if input.apply(&pad, JUMP, true) != ok { ret 73i64 }
    if !input.pressed(pad, attack) { ret 74i64 }

    ret 0i64
}
