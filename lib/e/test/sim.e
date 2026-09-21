// Deterministic simulation testing: `actors` actors exchange `Message`s
// through a caller pool under a virtual clock. `send` queues a message for
// `1 + delay` ticks ahead with `delay` drawn from the seeded PCG up to
// `max_delay`, and drops it with probability `drop_per_mille / 1000`; `timer`
// is a message to the actor itself at an exact delay, never dropped. `run`
// delivers up to `steps` messages: the earliest due first, ties broken by
// the seed, each through the caller's `step(ctx, sim, actor, message)` which
// may `send` more. Everything the run does is a function of the seed and the
// callback, so `trace` (a hash of every delivery) replays identically and a
// different seed reorders and drops differently.

use e.algo.rand
use e.mem

type Message = struct { from: u32, to: u32, kind: u32, value: i64, due: u64 }
type Sim = struct { actors: usize, pool: []Message, in_flight: []u8, rng: rand.Pcg64, clock: u64, max_delay: u64, drop_per_mille: u64, delivered: u64, dropped: u64, trace: u64 }
error TooSmall
error Invalid

fn mix(h: u64, v: u64) -> u64 { ret (h ^ v) *% 1099511628211u64 }

// A simulation of `actors` actors over `pool` (with `in_flight.len >= pool.len`).
fn sim(actors: usize, pool: []Message, in_flight: []u8, seed: u64, max_delay: u64, drop_per_mille: u64) -> Sim {
    var i = 0usize
    while i < in_flight.len {
        in_flight[i] = 0u8
        i += 1usize
    }
    ret Sim { actors: actors, pool: pool, in_flight: in_flight, rng: rand.pcg64(seed, 1u64), clock: 0u64, max_delay: max_delay, drop_per_mille: drop_per_mille, delivered: 0u64, dropped: 0u64, trace: 14695981039346656037u64 }
}

fn enqueue(s: *Sim, m: Message) -> err {
    var i = 0usize
    while i < s.pool.len && i < s.in_flight.len {
        if s.in_flight[i] == 0u8 {
            s.pool[i] = m
            s.in_flight[i] = 1u8
            ret ok
        }
        i += 1usize
    }
    ret TooSmall
}

// Queue `kind`/`value` from `from` to `to`; a dropped message answers `ok` and counts.
fn send(s: *Sim, from: u32, to: u32, kind: u32, value: i64) -> err {
    if usize(from) >= s.actors || usize(to) >= s.actors { ret Invalid }
    let delay = rand.pcg64_bounded(&s.rng, s.max_delay + 1u64)
    let lottery = rand.pcg64_bounded(&s.rng, 1000u64)
    if lottery < s.drop_per_mille {
        s.dropped += 1u64
        ret ok
    }
    ret enqueue(s, Message { from: from, to: to, kind: kind, value: value, due: s.clock + 1u64 + delay })
}

// A message from `actor` to itself exactly `delay` ticks ahead.
fn timer(s: *Sim, actor: u32, delay: u64, kind: u32, value: i64) -> err {
    if usize(actor) >= s.actors { ret Invalid }
    ret enqueue(s, Message { from: actor, to: actor, kind: kind, value: value, due: s.clock + delay })
}

fn pending(s: *const Sim) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.pool.len && i < s.in_flight.len {
        if s.in_flight[i] != 0u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// The slot of the next delivery: the earliest due, one of the ties at random.
fn choose(s: *Sim) -> (usize, bool) {
    var least = 0u64
    var ties = 0usize
    var i = 0usize
    while i < s.pool.len && i < s.in_flight.len {
        if s.in_flight[i] != 0u8 {
            if ties == 0usize || s.pool[i].due < least {
                least = s.pool[i].due
                ties = 1usize
            } else if s.pool[i].due == least {
                ties += 1usize
            }
        }
        i += 1usize
    }
    if ties == 0usize { ret (0usize, false) }
    var pick = usize(rand.pcg64_bounded(&s.rng, u64(ties)))
    i = 0usize
    while true {
        if s.in_flight[i] != 0u8 && s.pool[i].due == least {
            if pick == 0usize { ret (i, true) }
            pick -= 1usize
        }
        i += 1usize
    }
    ret (0usize, false)
}

// Deliver up to `steps` messages through `step`; answers how many went.
fn run[Ctx: type](s: *Sim, ctx: *Ctx, steps: usize, step: fn(*Ctx, *Sim, u32, Message)) -> usize {
    var done = 0usize
    while done < steps {
        let (slot, any) = choose(s)
        if !any { ret done }
        let m = s.pool[slot]
        s.in_flight[slot] = 0u8
        s.clock = m.due
        s.delivered += 1u64
        s.trace = mix(mix(mix(mix(mix(s.trace, u64(m.from)), u64(m.to)), u64(m.kind)), mem.bitcast[u64](m.value)), m.due)
        step(ctx, s, m.to, m)
        done += 1usize
    }
    ret done
}
