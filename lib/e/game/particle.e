// Particle pools: emitters, lifetimes and a fixed-point integration step (D249).
//
// The pool is a flat array with a live prefix. A particle that expires is replaced by the
// last live one and the count drops, so the live set stays contiguous and `step` walks it
// without testing a flag per slot. The order of the survivors is therefore not the order
// they were emitted -- which costs nothing, because particles are drawn as a set.
//
// A full pool drops the new particle rather than growing or evicting. Effects are the
// first thing to sacrifice when a frame is under pressure, and a dropped spark is not a
// bug; an allocation in the middle of a hit reaction would be.
//
// Randomness comes from `e.algo.rand`'s PCG64, threaded in by the caller, so a replay
// that seeds it the same way produces the same sparks in the same places.

use e.mem
use e.math.fixed
use e.algo.rand

type Particle = struct {
    x: fixed.Fx,
    y: fixed.Fx,
    vx: fixed.Fx,
    vy: fixed.Fx,
    life: u16,
    max_life: u16,
    kind: u16,
}

// `spread` is a half-angle in turns, so `fixed.HALF` is every direction and 0 is a beam
// along `facing`. `speed` is Q16 units per step.
type Emitter = struct {
    x: fixed.Fx,
    y: fixed.Fx,
    facing: fixed.Fx,
    spread: fixed.Fx,
    speed: fixed.Fx,
    life_min: u16,
    life_max: u16,
    kind: u16,
}

type Pool = struct {
    particles: []Particle,
    count: usize,
}

error Full
error Size

fn init(p: *Pool, particles: []Particle) -> err {
    if particles.len == 0usize { ret Size }
    p.particles = particles
    p.count = 0usize
    ret ok
}

fn clear(p: *Pool) -> err {
    p.count = 0usize
    ret ok
}

fn alive(p: Pool) -> usize {
    ret p.count
}

fn capacity(p: Pool) -> usize {
    ret p.particles.len
}

// A value in [low, high], taken from the generator's bounded draw so the distribution
// does not skew the way a bare modulo does.
fn between(state: *rand.Pcg64, low: i64, high: i64) -> i64 {
    if high <= low { ret low }
    ret low + i64(rand.pcg64_bounded(state, u64(high - low + 1i64)))
}

// One particle, at the emitter, heading somewhere inside its arc. Returns the slot it
// took; a full pool answers `Full` and changes nothing.
fn emit(p: *Pool, e: Emitter, state: *rand.Pcg64) -> (usize, err) {
    if p.count == p.particles.len { ret (0usize, Full) }
    let spread = i64(e.spread)
    let angle = i32(between(state, i64(e.facing) - spread, i64(e.facing) + spread))
    let life = u16(between(state, i64(e.life_min), i64(e.life_max)))
    let slot = p.count
    p.particles[slot] = Particle {
        x: e.x,
        y: e.y,
        vx: fixed.mul(fixed.cos(angle), e.speed),
        vy: fixed.mul(fixed.sin(angle), e.speed),
        life: life,
        max_life: life,
        kind: e.kind,
    }
    p.count = p.count + 1usize
    ret (slot, ok)
}

// As many as the pool will take. The answer is how many were actually emitted, which is
// fewer than asked when the pool fills -- the caller decides whether that matters.
fn burst(p: *Pool, e: Emitter, state: *rand.Pcg64, count: u16) -> (usize, err) {
    var made = 0usize
    var at = 0u16
    while at < count {
        let (slot, slot_error) = emit(p, e, state)
        if slot_error != ok { ret (made, ok) }
        made += 1usize
        at += 1u16
    }
    ret (made, ok)
}

// Integrate, age, and compact. `damping` is a Q16 factor applied to velocity each step:
// `fixed.ONE` keeps it, less slows it. Returns how many are still alive.
fn step(p: *Pool, gravity_x: fixed.Fx, gravity_y: fixed.Fx, damping: fixed.Fx) -> usize {
    var at = 0usize
    while at < p.count {
        var moving = p.particles[at]
        moving.vx = fixed.mul(moving.vx + gravity_x, damping)
        moving.vy = fixed.mul(moving.vy + gravity_y, damping)
        moving.x = moving.x + moving.vx
        moving.y = moving.y + moving.vy
        if moving.life == 0u16 {
            // Expired: the last live particle takes this slot, and this slot is
            // re-examined rather than skipped.
            p.particles[at] = p.particles[p.count - 1usize]
            p.count = p.count - 1usize
        } else {
            moving.life = moving.life - 1u16
            p.particles[at] = moving
            at += 1usize
        }
    }
    ret p.count
}

// How far through its life a particle is, in Q16: 0 when just emitted, near ONE at the
// end. What a fade or a shrink is driven by.
fn age(particle: Particle) -> fixed.Fx {
    if particle.max_life == 0u16 { ret fixed.ONE }
    let lived = i64(particle.max_life) - i64(particle.life)
    ret i32((lived << 16u32) / i64(particle.max_life))
}
