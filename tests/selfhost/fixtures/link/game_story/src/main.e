// `e.game.dialog` and `e.game.particle` (D279). The particle expectations were derived
// from a model of the step loop, and the emitter is given a zero spread and a fixed
// lifetime so nothing here depends on the generator's draws. Each check returns its own
// number when it fails; 0 is every check passed.

use e.mem
use e.math.fixed
use e.algo.rand
use e.game.dialog
use e.game.particle

const GREETED: u16 = 0u16
const GOLD: u16 = 0u16

fn main() -> i64 {
    // A three-node conversation. Node 0 offers two choices, the second guarded on a flag
    // that starts clear. Node 1 is a plain line that continues to node 2. Node 2 ends.
    var nodes: [3]dialog.Node = zero
    var choices: [3]dialog.Choice = zero

    // choice 0: always offered, sets GREETED, adds 5 gold, goes to node 1
    choices[0usize] = dialog.Choice { text: "hello", target: 1u16, show_if: dialog.always(),
                                      set_flag: GREETED, add_key: GOLD, delta: 5i32 }
    // choice 1: offered only once GREETED is set, goes straight to the end
    choices[1usize] = dialog.Choice { text: "again?", target: dialog.END,
                                      show_if: dialog.Condition { op: .FlagSet, key: GREETED, value: 0i32 },
                                      set_flag: dialog.NONE, add_key: dialog.NONE, delta: 0i32 }
    // choice 2: belongs to node 2, offered only when GOLD is at least 10
    choices[2usize] = dialog.Choice { text: "rich", target: dialog.END,
                                      show_if: dialog.Condition { op: .VarGe, key: GOLD, value: 10i32 },
                                      set_flag: dialog.NONE, add_key: dialog.NONE, delta: 0i32 }

    nodes[0usize] = dialog.Node { text: "start", speaker: 0u16, first_choice: 0u16, choice_count: 2u16, then: dialog.END }
    nodes[1usize] = dialog.Node { text: "middle", speaker: 1u16, first_choice: 0u16, choice_count: 0u16, then: 2u16 }
    nodes[2usize] = dialog.Node { text: "last", speaker: 1u16, first_choice: 2u16, choice_count: 1u16, then: dialog.END }

    let tree = dialog.Tree { nodes: nodes[..], choices: choices[..] }
    var flags: [1]u64 = zero
    var vars: [1]i32 = zero
    var story: dialog.State = zero
    if dialog.start(&story, tree, flags[..], vars[..]) != ok { ret 1i64 }
    if dialog.finished(story) { ret 2i64 }

    // Only the unguarded choice is offered while the flag is clear.
    var offered: [4]u16 = zero
    let (first_count, first_error) = dialog.available(story, tree, offered[..])
    if first_error != ok { ret 3i64 }
    if first_count != 1usize { ret 4i64 }
    if offered[0usize] != 0u16 { ret 5i64 }
    // A guarded choice cannot be taken by naming it directly either.
    if dialog.choose(&story, tree, 1u16) != dialog.Invalid { ret 6i64 }

    // Taking choice 0 applies both of its effects and moves on.
    if dialog.choose(&story, tree, 0u16) != ok { ret 7i64 }
    if !dialog.flag(story, GREETED) { ret 8i64 }
    if dialog.value(story, GOLD) != 5i32 { ret 9i64 }
    let (here, here_error) = dialog.node(story, tree)
    if here_error != ok { ret 10i64 }
    if here.speaker != 1u16 { ret 11i64 }

    // Node 1 offers nothing, so it advances rather than waiting.
    let (none_count, none_error) = dialog.available(story, tree, offered[..])
    if none_error != ok || none_count != 0usize { ret 12i64 }
    if dialog.advance(&story, tree) != ok { ret 13i64 }

    // Node 2's only choice is guarded on gold, which is 5, so nothing is offered and the
    // node has no live choice -- it may advance, and its `then` ends the conversation.
    let (poor_count, poor_error) = dialog.available(story, tree, offered[..])
    if poor_error != ok || poor_count != 0usize { ret 14i64 }
    if dialog.advance(&story, tree) != ok { ret 15i64 }
    if !dialog.finished(story) { ret 16i64 }
    // A finished conversation refuses to go further.
    if dialog.advance(&story, tree) != dialog.Invalid { ret 17i64 }
    if dialog.choose(&story, tree, 0u16) != dialog.Invalid { ret 18i64 }

    // Replaying with enough gold offers the guarded choice instead.
    if dialog.start(&story, tree, flags[..], vars[..]) != ok { ret 19i64 }
    // start clears the state, so the flag from the first run is gone.
    if dialog.flag(story, GREETED) { ret 20i64 }
    if dialog.value(story, GOLD) != 0i32 { ret 21i64 }
    if dialog.choose(&story, tree, 0u16) != ok { ret 22i64 }
    // Now both of node 0's choices would be live; go back and check.
    story.at = 0u16
    let (both_count, both_error) = dialog.available(story, tree, offered[..])
    if both_error != ok || both_count != 2usize { ret 23i64 }
    if offered[0usize] != 0u16 || offered[1usize] != 1u16 { ret 24i64 }
    // A node still offering a choice must not be advanced past.
    if dialog.advance(&story, tree) != dialog.Invalid { ret 25i64 }
    // Taking the guarded one now works and finishes.
    if dialog.choose(&story, tree, 1u16) != ok { ret 26i64 }
    if !dialog.finished(story) { ret 27i64 }

    // --- particles -------------------------------------------------------------------
    var storage: [4]particle.Particle = zero
    var pool: particle.Pool = zero
    if particle.init(&pool, storage[..]) != ok { ret 28i64 }
    if particle.alive(pool) != 0usize { ret 29i64 }
    if particle.capacity(pool) != 4usize { ret 30i64 }

    var generator = rand.pcg64(1u64, 1u64)
    // Zero spread and a fixed lifetime: the emitter draws nothing, so every value below
    // is exact. Facing zero turns is due east, so all the speed is on x.
    let beam = particle.Emitter { x: 0i32, y: 0i32, facing: 0i32, spread: 0i32,
                                  speed: 131072i32, life_min: 3u16, life_max: 3u16, kind: 7u16 }
    let (slot, slot_error) = particle.emit(&pool, beam, &generator)
    if slot_error != ok || slot != 0usize { ret 31i64 }
    if particle.alive(pool) != 1usize { ret 32i64 }
    if pool.particles[0usize].vx != 131072i32 { ret 33i64 }
    if pool.particles[0usize].vy != 0i32 { ret 34i64 }
    if pool.particles[0usize].life != 3u16 || pool.particles[0usize].kind != 7u16 { ret 35i64 }
    if particle.age(pool.particles[0usize]) != 0i32 { ret 36i64 }

    // Three steps carry it two units each and age it; the fourth expires it.
    if particle.step(&pool, 0i32, 0i32, 65536i32) != 1usize { ret 37i64 }
    if pool.particles[0usize].x != 131072i32 { ret 38i64 }
    if pool.particles[0usize].life != 2u16 { ret 39i64 }
    if particle.age(pool.particles[0usize]) != 21845i32 { ret 40i64 }
    if particle.step(&pool, 0i32, 0i32, 65536i32) != 1usize { ret 41i64 }
    if particle.step(&pool, 0i32, 0i32, 65536i32) != 1usize { ret 42i64 }
    if pool.particles[0usize].x != 393216i32 { ret 43i64 }
    if pool.particles[0usize].life != 0u16 { ret 44i64 }
    if particle.step(&pool, 0i32, 0i32, 65536i32) != 0usize { ret 45i64 }
    if particle.alive(pool) != 0usize { ret 46i64 }

    // Damping halves the velocity before it is applied.
    if particle.clear(&pool) != ok { ret 47i64 }
    let fast = particle.Emitter { x: 0i32, y: 0i32, facing: 0i32, spread: 0i32,
                                  speed: 262144i32, life_min: 9u16, life_max: 9u16, kind: 0u16 }
    let (fast_slot, fast_error) = particle.emit(&pool, fast, &generator)
    if fast_error != ok { ret 48i64 }
    if particle.step(&pool, 0i32, 0i32, 32768i32) != 1usize { ret 49i64 }
    if pool.particles[0usize].vx != 131072i32 { ret 50i64 }
    if pool.particles[0usize].x != 131072i32 { ret 51i64 }

    // A burst stops at capacity rather than overrunning, and reports what it made.
    if particle.clear(&pool) != ok { ret 52i64 }
    let (made, made_error) = particle.burst(&pool, beam, &generator, 10u16)
    if made_error != ok { ret 53i64 }
    if made != 4usize { ret 54i64 }
    if particle.alive(pool) != 4usize { ret 55i64 }
    let (overflow, overflow_error) = particle.emit(&pool, beam, &generator)
    if overflow_error != particle.Full { ret 56i64 }

    // The live set stays contiguous: expiring the middle one leaves three at the front.
    pool.particles[1usize].life = 0u16
    if particle.step(&pool, 0i32, 0i32, 65536i32) != 3usize { ret 57i64 }
    if particle.alive(pool) != 3usize { ret 58i64 }
    var walk = 0usize
    while walk < particle.alive(pool) {
        if pool.particles[walk].max_life == 0u16 { ret 59i64 }
        walk += 1usize
    }

    // A spread emitter stays inside its arc and its lifetime range, which is a property
    // rather than a value, so it holds whatever the generator draws.
    if particle.clear(&pool) != ok { ret 60i64 }
    let spray = particle.Emitter { x: 0i32, y: 0i32, facing: 16384i32, spread: 4096i32,
                                   speed: 65536i32, life_min: 2u16, life_max: 8u16, kind: 1u16 }
    var round = 0usize
    while round < 4usize {
        let (sprayed, spray_error) = particle.emit(&pool, spray, &generator)
        if spray_error != ok { ret 61i64 }
        let made_one = pool.particles[sprayed]
        if made_one.life < 2u16 || made_one.life > 8u16 { ret 62i64 }
        if made_one.max_life != made_one.life { ret 63i64 }
        // Facing a quarter turn with an eighth-turn arc keeps the motion upward in y.
        if made_one.vy <= 0i32 { ret 64i64 }
        round += 1usize
    }

    ret 0i64
}
