// `e.game.sprite` and `e.game.camera` (D282). The camera expectations were derived
// independently; the shake is checked as a bound rather than a value, since it draws from
// the generator. Each check returns its own number when it fails; 0 is every check passed.

use e.mem
use e.math.fixed
use e.algo.rand
use e.game.collide2d
use e.game.sprite
use e.game.camera

fn fx(n: i32) -> i32 {
    ret n * 65536i32
}

fn main() -> i64 {
    // --- sprite clips -----------------------------------------------------------------
    // Three clips over one atlas run: idle loops, attack plays once then returns to idle,
    // and hurt plays once with nothing after it.
    var clips: [3]sprite.Clip = zero
    clips[0usize] = sprite.Clip { first: 0u16, count: 4u16, hold: 2u16, loops: true, then: sprite.NONE }
    clips[1usize] = sprite.Clip { first: 4u16, count: 3u16, hold: 1u16, loops: false, then: 0u16 }
    clips[2usize] = sprite.Clip { first: 7u16, count: 2u16, hold: 1u16, loops: false, then: sprite.NONE }

    var player: sprite.Player = zero
    if sprite.play(&player, 0u16) != ok { ret 1i64 }
    if sprite.frame(player, clips[..]) != 0u16 { ret 2i64 }

    // A hold of 2 means two ticks per frame: the first tick does not advance.
    if sprite.advance(&player, clips[..]) != ok { ret 3i64 }
    if sprite.frame(player, clips[..]) != 0u16 { ret 4i64 }
    if sprite.advance(&player, clips[..]) != ok { ret 5i64 }
    if sprite.frame(player, clips[..]) != 1u16 { ret 6i64 }

    // Idle loops, so after its four frames it is back at the first and never finishes.
    var tick = 0usize
    while tick < 6usize {
        if sprite.advance(&player, clips[..]) != ok { ret 7i64 }
        tick += 1usize
    }
    if sprite.frame(player, clips[..]) != 0u16 { ret 8i64 }
    if sprite.finished(player) { ret 9i64 }

    // Attack runs three frames at one tick each, then hands over to idle by its `then`.
    if sprite.play(&player, 1u16) != ok { ret 10i64 }
    if sprite.frame(player, clips[..]) != 4u16 { ret 11i64 }
    if sprite.advance(&player, clips[..]) != ok { ret 12i64 }
    if sprite.frame(player, clips[..]) != 5u16 { ret 13i64 }
    if sprite.advance(&player, clips[..]) != ok { ret 14i64 }
    if sprite.frame(player, clips[..]) != 6u16 { ret 15i64 }
    if sprite.advance(&player, clips[..]) != ok { ret 16i64 }
    if player.clip != 0u16 { ret 17i64 }
    if sprite.frame(player, clips[..]) != 0u16 { ret 18i64 }
    if sprite.finished(player) { ret 19i64 }

    // Hurt has nothing after it: it holds its last frame and reports finished, rather
    // than wrapping round or blanking.
    if sprite.play(&player, 2u16) != ok { ret 20i64 }
    if sprite.advance(&player, clips[..]) != ok { ret 21i64 }
    if sprite.frame(player, clips[..]) != 8u16 { ret 22i64 }
    if sprite.advance(&player, clips[..]) != ok { ret 23i64 }
    if !sprite.finished(player) { ret 24i64 }
    if sprite.frame(player, clips[..]) != 8u16 { ret 25i64 }
    // Advancing a finished clip is a no-op, not an error and not a wrap.
    if sprite.advance(&player, clips[..]) != ok { ret 26i64 }
    if sprite.frame(player, clips[..]) != 8u16 { ret 27i64 }
    // Replaying the clip already running restarts it.
    if sprite.play(&player, 2u16) != ok { ret 28i64 }
    if sprite.finished(player) { ret 29i64 }
    if sprite.frame(player, clips[..]) != 7u16 { ret 30i64 }
    // An unknown clip is refused rather than read past the end of the table.
    if sprite.play(&player, 9u16) != ok { ret 31i64 }
    if sprite.advance(&player, clips[..]) != sprite.Unknown { ret 32i64 }

    // A region is found by name, and a name that is not there is an error.
    var regions: [2]sprite.Region = zero
    regions[0usize] = sprite.Region { x: 0u16, y: 0u16, w: 16u16, h: 16u16, pivot_x: 8i16, pivot_y: 16i16 }
    regions[1usize] = sprite.Region { x: 16u16, y: 0u16, w: 16u16, h: 16u16, pivot_x: 8i16, pivot_y: 16i16 }
    var names: [2]str = zero
    names[0usize] = "hero"
    names[1usize] = "orc"
    let atlas = sprite.Atlas { regions: regions[..], names: names[..] }
    let (orc, orc_error) = sprite.region(atlas, "orc")
    if orc_error != ok || orc.x != 16u16 { ret 33i64 }
    let (missing, missing_error) = sprite.region(atlas, "dragon")
    if missing_error != sprite.Unknown { ret 34i64 }

    // --- the camera --------------------------------------------------------------------
    var view: camera.Camera = zero
    if camera.init(&view, fx(320i32), fx(180i32)) != ok { ret 35i64 }
    if camera.set_deadzone(&view, fx(64i32), fx(32i32)) != ok { ret 36i64 }

    // Inside the deadzone the camera does not move at all; outside it moves only far
    // enough to put the target back on the edge.
    if camera.follow(&view, fx(10i32), 0i32) != ok { ret 37i64 }
    if view.x != 0i32 { ret 38i64 }
    if camera.follow(&view, fx(40i32), 0i32) != ok { ret 39i64 }
    if view.x != 524288i32 { ret 40i64 }
    view.x = 0i32
    if camera.follow(&view, fx(-40i32), 0i32) != ok { ret 41i64 }
    if view.x != -524288i32 { ret 42i64 }

    // Clamping keeps the visible rectangle inside the world; the half width is 160.
    view.x = fx(50i32)
    view.y = 0i32
    let world = camera.Bounds { min_x: 0i32, min_y: 0i32, max_x: fx(1000i32), max_y: fx(1000i32) }
    if camera.clamp_to(&view, world) != ok { ret 43i64 }
    if view.x != 10485760i32 { ret 44i64 }
    view.x = fx(900i32)
    if camera.clamp_to(&view, world) != ok { ret 45i64 }
    if view.x != 55050240i32 { ret 46i64 }
    // A world narrower than the view is centred, since no position satisfies both edges.
    view.x = fx(500i32)
    let cramped = camera.Bounds { min_x: 0i32, min_y: 0i32, max_x: fx(200i32), max_y: fx(1000i32) }
    if camera.clamp_to(&view, cramped) != ok { ret 47i64 }
    if view.x != 6553600i32 { ret 48i64 }

    // World to screen at parallax one, and the round trip back.
    view.x = fx(50i32)
    view.y = 0i32
    let (screen_x, screen_y) = camera.to_screen(view, fx(100i32), 0i32, 65536i32)
    if screen_x != 13762560i32 { ret 49i64 }
    let (back_x, back_y) = camera.to_world(view, screen_x, screen_y)
    if back_x != 6553600i32 { ret 50i64 }
    // Parallax zero pins a layer to the view, so the camera's position drops out.
    let (pinned_x, pinned_y) = camera.to_screen(view, fx(100i32), 0i32, 0i32)
    if pinned_x != 17039360i32 { ret 51i64 }

    // Culling answers the boxes on screen, in the order given.
    var boxes: [3]collide2d.Aabb = zero
    boxes[0usize] = collide2d.aabb(fx(50i32), 0i32, fx(4i32), fx(4i32))
    boxes[1usize] = collide2d.aabb(fx(9000i32), 0i32, fx(4i32), fx(4i32))
    boxes[2usize] = collide2d.aabb(fx(120i32), 0i32, fx(4i32), fx(4i32))
    var shown: [3]u32 = zero
    let (shown_count, shown_error) = camera.cull(view, boxes[..], shown[..])
    if shown_error != ok { ret 52i64 }
    if shown_count != 2usize { ret 53i64 }
    if shown[0usize] != 0u32 || shown[1usize] != 2u32 { ret 54i64 }
    if camera.visible(view, boxes[1usize]) { ret 55i64 }

    // The draw list sorts by layer first, then by key, and is stable within a tie.
    var items: [5]camera.Item = zero
    items[0usize] = camera.Item { id: 0u32, layer: 0i16, sort: fx(5i32) }
    items[1usize] = camera.Item { id: 1u32, layer: 0i16, sort: fx(3i32) }
    items[2usize] = camera.Item { id: 2u32, layer: 1i16, sort: fx(1i32) }
    items[3usize] = camera.Item { id: 3u32, layer: 0i16, sort: fx(3i32) }
    items[4usize] = camera.Item { id: 4u32, layer: -1i16, sort: fx(9i32) }
    if camera.order(items[..]) != ok { ret 56i64 }
    // A lower layer always draws first, whatever its key; 1 stays before 3 because they
    // tie on both, and a draw list that reordered ties would flicker between frames.
    if items[0usize].id != 4u32 { ret 57i64 }
    if items[1usize].id != 1u32 { ret 58i64 }
    if items[2usize].id != 3u32 { ret 59i64 }
    if items[3usize].id != 0u32 { ret 60i64 }
    if items[4usize].id != 2u32 { ret 61i64 }

    // Shake draws from the generator, so it is checked as a bound: never outside the
    // amplitude asked for, and zero once it has run out.
    var generator = rand.pcg64(7u64, 1u64)
    view.x = 0i32
    view.y = 0i32
    if camera.shake(&view, fx(4i32), 3u16) != ok { ret 62i64 }
    var shakes = 0usize
    while shakes < 3usize {
        if camera.step(&view, &generator) != ok { ret 63i64 }
        if fixed.abs(view.shake_x) > fx(4i32) { ret 64i64 }
        if fixed.abs(view.shake_y) > fx(4i32) { ret 65i64 }
        shakes += 1usize
    }
    if camera.step(&view, &generator) != ok { ret 66i64 }
    if view.shake_x != 0i32 || view.shake_y != 0i32 { ret 67i64 }

    ret 0i64
}
