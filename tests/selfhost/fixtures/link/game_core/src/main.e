// `e.game.loop` and `e.game.ecs` (D268). Each check returns its own number when it
// fails; 0 is every check passed.

use e.mem
use e.math.fixed
use e.game.loop
use e.game.ecs

const POSITION: u16 = 1u16
const HEALTH: u16 = 2u16

fn main() -> i64 {
    // --- the fixed step ------------------------------------------------------------
    var clock: loop.Clock = zero
    if loop.init(&clock, 16384i32) != ok { ret 1i64 }          // a quarter unit per step
    if loop.init(&clock, 0i32) != loop.Invalid { ret 2i64 }
    if loop.init(&clock, 16384i32) != ok { ret 3i64 }

    // Less than a step owes nothing, and the leftover shows up as alpha.
    if loop.advance(&clock, 8192i32, 8usize) != 0usize { ret 4i64 }
    if loop.alpha(clock) != 32768i32 { ret 5i64 }              // half of a quarter unit
    // Another half step completes the first one exactly.
    if loop.advance(&clock, 8192i32, 8usize) != 1usize { ret 6i64 }
    if loop.alpha(clock) != 0i32 { ret 7i64 }
    if clock.ticks != 1u64 { ret 8i64 }
    // A big elapsed hands back whole steps, capped, and the backlog is dropped rather
    // than carried -- otherwise a slow machine falls further behind every frame.
    if loop.advance(&clock, 65536i32, 2usize) != 2usize { ret 9i64 }
    if clock.ticks != 3u64 { ret 10i64 }
    if clock.accumulator >= clock.step { ret 11i64 }

    // A repeating timer carries its overshoot, so a period that is not a whole number
    // of steps does not drift.
    var repeating = loop.timer(65536i32, true)
    var fired = 0usize
    var step = 0usize
    while step < 12usize {
        if loop.tick(&repeating, 24576i32) { fired += 1usize }
        step += 1usize
    }
    if fired != 4usize { ret 12i64 }

    var once = loop.timer(65536i32, false)
    if loop.tick(&once, 65536i32) != true { ret 13i64 }
    if loop.tick(&once, 65536i32) != false { ret 14i64 }
    if !loop.ready(once) { ret 15i64 }
    if loop.reset(&once) != ok || loop.ready(once) { ret 16i64 }

    // Every curve is exact at both ends.
    if loop.ease_in(0i32) != 0i32 || loop.ease_in(65536i32) != 65536i32 { ret 17i64 }
    if loop.ease_out(0i32) != 0i32 || loop.ease_out(65536i32) != 65536i32 { ret 18i64 }
    if loop.ease_in_out(0i32) != 0i32 || loop.ease_in_out(65536i32) != 65536i32 { ret 19i64 }
    if loop.ease_back(0i32) != 0i32 || loop.ease_back(65536i32) != 65536i32 { ret 20i64 }
    if loop.ease_elastic(0i32) != 0i32 || loop.ease_elastic(65536i32) != 65536i32 { ret 21i64 }
    // ease_in is below the straight line in the first half, ease_out above it.
    if loop.ease_in(16384i32) >= 16384i32 { ret 22i64 }
    if loop.ease_out(16384i32) <= 16384i32 { ret 23i64 }
    // ease_back undershoots before it climbs.
    if loop.ease_back(8192i32) >= 0i32 { ret 24i64 }

    // --- the entity store ----------------------------------------------------------
    var positions: [8]u8 = zero                                 // 4 slots x 2 bytes
    var healths: [4]u8 = zero                                   // 4 slots x 1 byte
    var position_present: [1]u64 = zero
    var health_present: [1]u64 = zero
    var columns: [2]ecs.Column = zero
    columns[0usize] = ecs.Column { id: POSITION, stride: 2usize, bytes: positions[..], present: position_present[..] }
    columns[1usize] = ecs.Column { id: HEALTH, stride: 1usize, bytes: healths[..], present: health_present[..] }
    var generations: [4]u32 = zero
    var free: [4]u32 = zero
    var store: ecs.Store = zero
    if ecs.init(&store, columns[..], generations[..], free[..]) != ok { ret 25i64 }

    let (first, first_error) = ecs.spawn(&store)
    if first_error != ok { ret 26i64 }
    let (second, second_error) = ecs.spawn(&store)
    if second_error != ok { ret 27i64 }
    if !ecs.alive(store, first) || !ecs.alive(store, second) { ret 28i64 }
    if first.slot == second.slot { ret 29i64 }
    if ecs.live_count(store) != 2usize { ret 30i64 }

    var where_at: [2]u8 = zero
    where_at[0usize] = 7u8
    where_at[1usize] = 9u8
    if ecs.attach(&store, first, POSITION, where_at[..]) != ok { ret 31i64 }
    if !ecs.has(store, first, POSITION) { ret 32i64 }
    if ecs.has(store, second, POSITION) { ret 33i64 }
    // A component of the wrong size is refused rather than truncated.
    if ecs.attach(&store, first, HEALTH, where_at[..]) != ecs.Size { ret 34i64 }
    if ecs.attach(&store, first, 99u16, where_at[..]) != ecs.Unknown { ret 35i64 }

    // `get` hands back the store's own bytes, so a write through it sticks.
    let (view, view_error) = ecs.get(store, first, POSITION)
    if view_error != ok || view.len != 2usize { ret 36i64 }
    if view[0usize] != 7u8 || view[1usize] != 9u8 { ret 37i64 }
    view[0usize] = 21u8
    let (again, again_error) = ecs.get(store, first, POSITION)
    if again_error != ok || again[0usize] != 21u8 { ret 38i64 }

    // A handle kept across a despawn is stale, even once the slot is reused.
    let stale = first
    if ecs.despawn(&store, first) != ok { ret 39i64 }
    if ecs.alive(store, stale) { ret 40i64 }
    if ecs.despawn(&store, stale) != ecs.Stale { ret 41i64 }
    let (dead_view, dead_error) = ecs.get(store, stale, POSITION)
    if dead_error != ecs.Stale { ret 42i64 }
    // Despawning drops the components too, so a reused slot starts empty.
    let (reused, reused_error) = ecs.spawn(&store)
    if reused_error != ok { ret 43i64 }
    if reused.slot != stale.slot { ret 44i64 }
    if reused.generation == stale.generation { ret 45i64 }
    if ecs.has(store, reused, POSITION) { ret 46i64 }
    if ecs.alive(store, stale) { ret 47i64 }

    // A query answers only the entities carrying every named component, in slot order.
    var health: [1]u8 = zero
    health[0usize] = 50u8
    if ecs.attach(&store, second, HEALTH, health[..]) != ok { ret 48i64 }
    if ecs.attach(&store, reused, HEALTH, health[..]) != ok { ret 49i64 }
    if ecs.attach(&store, second, POSITION, where_at[..]) != ok { ret 50i64 }
    var wanted: [2]u16 = zero
    wanted[0usize] = POSITION
    wanted[1usize] = HEALTH
    var walk = ecs.query(&store, wanted[0usize..2usize])
    var seen = 0usize
    var last_slot = 0u32
    while true {
        let (found, more) = ecs.next(&walk)
        if !more { break }
        if seen > 0usize && found.slot <= last_slot { ret 51i64 }
        last_slot = found.slot
        seen += 1usize
    }
    if seen != 1usize { ret 52i64 }

    // The store allocates nothing, so a full one is an error rather than a surprise.
    let (third, third_error) = ecs.spawn(&store)
    if third_error != ok { ret 53i64 }
    let (fourth, fourth_error) = ecs.spawn(&store)
    if fourth_error != ok { ret 54i64 }
    let (overflow, overflow_error) = ecs.spawn(&store)
    if overflow_error != ecs.Full { ret 55i64 }

    ret 0i64
}
