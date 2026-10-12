// A virtual-actor framework (L141) in the shape of Orleans grains and Akka cluster sharding,
// over `e.algo.consistent_hash` placement and `e.db.docstore` storage. A grain is an id that
// always exists: the first call activates it on the silo that rendezvous hashing of its id picks
// among the live silos, loads its persisted state, runs the behavior's `activate` hook and then
// delivers messages one turn at a time; an idle grain is collected and its next call activates
// it again, wherever placement then says. Callers never hold an address, only the id.
//
// Turns: `handle(turn)` is the whole of a message. A turn's state change and reply take effect
// only when the handler returns `ok`; the new state is written through to the document store
// before the reply goes back, so a state a caller has seen is a state a restart still has. A
// handler that fails changes nothing. A turn is not reentrant: while a grain is in a turn, a call
// to it (its own, or from a grain that it called, a cycle) is refused with `Reentrancy` and the
// callee does not run, rather than deadlocking.
//
// Timers are in-memory and die with the activation (deactivation, silo failure). Reminders are
// durable documents in the store: they fire whether or not the grain is active, activating it,
// and survive a restart because they are read back from the same file. A periodic reminder or
// timer next falls at its due time plus the smallest multiple of its period that is after `now`:
// a long gap is one firing, not a burst. `tick(now)` is the clock: the caller (a scheduler loop,
// `e.task.jobs`) drives it.
//
// A silo failure (`fail_silo`) drops its activations without running `deactivate` and without
// writing state: what a grain had committed in a turn is in the store, and its next call
// re-places and reloads. There is no networking here: a silo is a placement target and a
// failure domain in one process; the cross-node transport is `e.dist`'s and the application's.
//
// Limits: grain state is text; a grain's state is copied into the arena on activation and per
// turn (the arena grows with turns); at most 64 reminders fire per `tick`; activations, timers
// and silos are fixed capacities.

use e.algo.consistent_hash as ch
use e.algo.hash
use e.db.docstore as ds
use e.mem
use e.str

const MAX_FIRE: usize = 64usize
const KEY_SEP: u8 = 31u8

type Silo = struct { name: str, id: u64, alive: bool }
type Activation = struct { grain: str, silo: u32, state: str, version: u32, busy: bool, live: bool, last_used: i64 }
type Timer = struct { grain: str, name: str, due: i64, period: i64, live: bool }
type Behavior = struct { ctx: *void, activate: fn(*void, *Turn) -> err, handle: fn(*void, *Turn) -> err, deactivate: fn(*void, *Turn) -> err }
type Turn = struct { sys: *System, act: usize, grain: str, kind: str, payload: str, now: i64, state: str, state_changed: bool, reply: str, silo: u32 }
type System = struct { a: *mem.Arena, db: *ds.Db, behavior: Behavior, silos: []Silo, nsilos: usize, acts: []Activation, nacts: usize, timers: []Timer, ntimers: usize, turns: u64 }

error NoSilo
error Reentrancy
error Full
error Invalid
error NotFound

fn state_collection() -> str { ret "grain-state" }

fn reminder_collection() -> str { ret "reminders" }

fn create(a: *mem.Arena, db: *ds.Db, behavior: Behavior, max_silos: usize, max_activations: usize, max_timers: usize) -> (System, err) {
    var sys: System = zero
    let (silos, e1) = mem.alloc[Silo](a, max_silos)
    if e1 != ok { ret (sys, e1) }
    let (acts, e2) = mem.alloc[Activation](a, max_activations)
    if e2 != ok { ret (sys, e2) }
    let (timers, e3) = mem.alloc[Timer](a, max_timers)
    if e3 != ok { ret (sys, e3) }
    sys.a = a
    sys.db = db
    sys.behavior = behavior
    sys.silos = silos
    sys.acts = acts
    sys.timers = timers
    ret (sys, ok)
}

fn keep(a: *mem.Arena, s: str) -> (str, err) {
    if s.len == 0usize { ret ("", ok) }
    let (buf, alloc_error) = mem.alloc[u8](a, s.len)
    if alloc_error != ok { ret ("", alloc_error) }
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    ret (buf[0..s.len], ok)
}

fn add_silo(sys: *System, name: str) -> (usize, err) {
    if sys.nsilos >= sys.silos.len { ret (0usize, Full) }
    let (copy, keep_error) = keep(sys.a, name)
    if keep_error != ok { ret (0usize, keep_error) }
    sys.silos[sys.nsilos] = Silo { name: copy, id: hash.xxhash64(name, 0u64), alive: true }
    sys.nsilos += 1usize
    ret (sys.nsilos - 1usize, ok)
}

fn live_silos(sys: *System) -> usize {
    var n = 0usize
    var i = 0usize
    while i < sys.nsilos {
        if sys.silos[i].alive { n += 1usize }
        i += 1usize
    }
    ret n
}

// The silo a grain id is placed on among the live ones (rendezvous hashing).
fn place(sys: *System, grain: str) -> (usize, bool) {
    var ids: [32]u64 = zero
    var map: [32]usize = zero
    var n = 0usize
    var i = 0usize
    while i < sys.nsilos && n < 32usize {
        if sys.silos[i].alive {
            ids[n] = sys.silos[i].id
            map[n] = i
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize { ret (0usize, false) }
    let (best, found) = ch.rendezvous(ids[0..n], hash.xxhash64(grain, 0u64))
    if !found { ret (0usize, false) }
    ret (map[best], true)
}

fn find_activation(sys: *System, grain: str) -> (usize, bool) {
    var i = 0usize
    while i < sys.nacts {
        if sys.acts[i].live && str.eq(sys.acts[i].grain, grain) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn is_active(sys: *System, grain: str) -> bool {
    let (at, found) = find_activation(sys, grain)
    ret found
}

fn silo_of(sys: *System, grain: str) -> (usize, bool) {
    let (at, found) = find_activation(sys, grain)
    if !found { ret (0usize, false) }
    ret (usize(sys.acts[at].silo), true)
}

fn active_count(sys: *System) -> usize {
    var n = 0usize
    var i = 0usize
    while i < sys.nacts {
        if sys.acts[i].live { n += 1usize }
        i += 1usize
    }
    ret n
}

// A grain's persisted state (the empty text for a grain never written), whether active or not.
fn stored_state(sys: *System, grain: str) -> (str, bool) {
    let (s, found) = ds.get(sys.db, state_collection(), grain)
    ret (s, found)
}

fn new_turn(sys: *System, at: usize, kind: str, payload: str, now: i64) -> Turn {
    ret Turn { sys: sys, act: at, grain: sys.acts[at].grain, kind: kind, payload: payload, now: now, state: sys.acts[at].state, state_changed: false, reply: "", silo: sys.acts[at].silo }
}

// Activates `grain`: place, load state, run the hook. An activation found is returned as is.
fn activate(sys: *System, grain: str, now: i64) -> (usize, err) {
    let (existing, found) = find_activation(sys, grain)
    if found { ret (existing, ok) }
    let (silo, placed) = place(sys, grain)
    if !placed { ret (0usize, NoSilo) }
    var at = sys.nacts
    var i = 0usize
    while i < sys.nacts {
        if !sys.acts[i].live {
            at = i
            break
        }
        i += 1usize
    }
    if at == sys.nacts {
        if sys.nacts >= sys.acts.len { ret (0usize, Full) }
        sys.nacts += 1usize
    }
    let (loaded, has_state) = stored_state(sys, grain)
    let (state_copy, e1) = keep(sys.a, loaded)
    if e1 != ok { ret (0usize, e1) }
    let (grain_copy, e2) = keep(sys.a, grain)
    if e2 != ok { ret (0usize, e2) }
    sys.acts[at] = Activation { grain: grain_copy, silo: u32(silo), state: state_copy, version: 0u32, busy: true, live: true, last_used: now }
    var turn = new_turn(sys, at, "activate", "", now)
    let hook_error = sys.behavior.activate(sys.behavior.ctx, &turn)
    sys.acts[at].busy = false
    if hook_error != ok {
        sys.acts[at].live = false
        ret (0usize, hook_error)
    }
    ret (at, ok)
}

// Persists a turn's state change; the activation's state and version follow.
fn commit(sys: *System, at: usize, turn: *Turn) -> err {
    if !turn.state_changed { ret ok }
    try ds.put(sys.db, state_collection(), sys.acts[at].grain, turn.state)
    let (stored, found) = ds.get(sys.db, state_collection(), sys.acts[at].grain)
    let (copy, keep_error) = keep(sys.a, stored)
    if keep_error != ok { ret keep_error }
    sys.acts[at].state = copy
    sys.acts[at].version += 1u32
    ret ok
}

// Delivers one message to an active grain: a turn.
fn deliver(sys: *System, at: usize, kind: str, payload: str, now: i64) -> (str, err) {
    if sys.acts[at].busy { ret ("", Reentrancy) }
    sys.acts[at].busy = true
    sys.acts[at].last_used = now
    var turn = new_turn(sys, at, kind, payload, now)
    let handle_error = sys.behavior.handle(sys.behavior.ctx, &turn)
    sys.acts[at].busy = false
    sys.turns += 1u64
    if handle_error != ok { ret ("", handle_error) }
    let commit_error = commit(sys, at, &turn)
    if commit_error != ok { ret ("", commit_error) }
    ret (turn.reply, ok)
}

// A call into the system from outside: activate if needed, then one turn.
fn call(sys: *System, grain: str, kind: str, payload: str, now: i64) -> (str, err) {
    if grain.len == 0usize || kind.len == 0usize { ret ("", Invalid) }
    let (at, activate_error) = activate(sys, grain, now)
    if activate_error != ok { ret ("", activate_error) }
    let (reply, deliver_error) = deliver(sys, at, kind, payload, now)
    ret (reply, deliver_error)
}

// A call from inside a turn to another grain (or, refused, to one in a turn).
fn call_from(t: *Turn, grain: str, kind: str, payload: str) -> (str, err) {
    let (reply, call_error) = call(t.sys, grain, kind, payload, t.now)
    ret (reply, call_error)
}

fn set_state(t: *Turn, s: str) {
    t.state = s
    t.state_changed = true
}

fn set_reply(t: *Turn, s: str) { t.reply = s }

// Runs `deactivate` and removes the activation and its timers; the state is already stored.
fn deactivate_at(sys: *System, at: usize, now: i64) -> err {
    var turn = new_turn(sys, at, "deactivate", "", now)
    sys.acts[at].busy = true
    let hook_error = sys.behavior.deactivate(sys.behavior.ctx, &turn)
    sys.acts[at].busy = false
    var committed: err = ok
    if hook_error == ok { committed = commit(sys, at, &turn) }
    drop_timers(sys, sys.acts[at].grain)
    sys.acts[at].live = false
    if hook_error != ok { ret hook_error }
    ret committed
}

fn drop_timers(sys: *System, grain: str) {
    var i = 0usize
    while i < sys.ntimers {
        if sys.timers[i].live && str.eq(sys.timers[i].grain, grain) { sys.timers[i].live = false }
        i += 1usize
    }
}

fn deactivate(sys: *System, grain: str, now: i64) -> err {
    let (at, found) = find_activation(sys, grain)
    if !found { ret NotFound }
    if sys.acts[at].busy { ret Reentrancy }
    ret deactivate_at(sys, at, now)
}

// Deactivates every grain idle for at least `idle_ms`; how many.
fn collect(sys: *System, now: i64, idle_ms: i64) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < sys.nacts {
        if sys.acts[i].live && !sys.acts[i].busy && now - sys.acts[i].last_used >= idle_ms {
            let e = deactivate_at(sys, i, now)
            if e != ok { ret (n, e) }
            n += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

// A silo dies: its activations are gone without a hook or a write. How many were lost.
fn fail_silo(sys: *System, silo: usize) -> usize {
    if silo >= sys.nsilos { ret 0usize }
    sys.silos[silo].alive = false
    var n = 0usize
    var i = 0usize
    while i < sys.nacts {
        if sys.acts[i].live && usize(sys.acts[i].silo) == silo {
            drop_timers(sys, sys.acts[i].grain)
            sys.acts[i].live = false
            sys.acts[i].busy = false
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// ---- timers (in memory) -------------------------------------------------------------------

// Starts (or restarts) a timer of this grain: first firing at `due`, then every `period` ms (0
// for once). Delivered as kind `timer:<name>` by `tick` while the grain stays active.
fn timer_start(t: *Turn, name: str, due: i64, period: i64) -> err {
    if name.len == 0usize || period < 0i64 { ret Invalid }
    let sys = t.sys
    var at = sys.ntimers
    var i = 0usize
    while i < sys.ntimers {
        if sys.timers[i].live && str.eq(sys.timers[i].grain, t.grain) && str.eq(sys.timers[i].name, name) {
            at = i
            break
        }
        i += 1usize
    }
    if at == sys.ntimers {
        i = 0usize
        while i < sys.ntimers {
            if !sys.timers[i].live {
                at = i
                break
            }
            i += 1usize
        }
    }
    if at == sys.ntimers {
        if sys.ntimers >= sys.timers.len { ret Full }
        sys.ntimers += 1usize
    }
    let (grain_copy, e1) = keep(sys.a, t.grain)
    if e1 != ok { ret e1 }
    let (name_copy, e2) = keep(sys.a, name)
    if e2 != ok { ret e2 }
    sys.timers[at] = Timer { grain: grain_copy, name: name_copy, due: due, period: period, live: true }
    ret ok
}

fn timer_stop(t: *Turn, name: str) -> bool {
    let sys = t.sys
    var i = 0usize
    while i < sys.ntimers {
        if sys.timers[i].live && str.eq(sys.timers[i].grain, t.grain) && str.eq(sys.timers[i].name, name) {
            sys.timers[i].live = false
            ret true
        }
        i += 1usize
    }
    ret false
}

fn timer_count(sys: *System) -> usize {
    var n = 0usize
    var i = 0usize
    while i < sys.ntimers {
        if sys.timers[i].live { n += 1usize }
        i += 1usize
    }
    ret n
}

// ---- reminders (durable) ------------------------------------------------------------------

fn reminder_key(a: *mem.Arena, grain: str, name: str) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = str.push(&b, grain)
    if failure == ok { failure = str.push_byte(&b, KEY_SEP) }
    if failure == ok { failure = str.push(&b, name) }
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

fn reminder_value(a: *mem.Arena, due: i64, period: i64) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 48usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = str.push_i64(&b, due)
    if failure == ok { failure = str.push_byte(&b, 44u8) }
    if failure == ok { failure = str.push_i64(&b, period) }
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

// Parses "due,period"; false when malformed.
fn parse_pair(s: str) -> (i64, i64, bool) {
    var vals: [2]i64 = zero
    var which = 0usize
    var neg = false
    var seen = false
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 44u8 {
            if which == 1usize || !seen { ret (0i64, 0i64, false) }
            if neg { vals[0] = 0i64 - vals[0] }
            which = 1usize
            neg = false
            seen = false
        } else {
            if c == 45u8 && !seen {
                neg = true
            } else {
                if c < 48u8 || c > 57u8 { ret (0i64, 0i64, false) }
                vals[which] = vals[which] * 10i64 + i64(c - 48u8)
                seen = true
            }
        }
        i += 1usize
    }
    if which != 1usize || !seen { ret (0i64, 0i64, false) }
    if neg { vals[1] = 0i64 - vals[1] }
    ret (vals[0], vals[1], true)
}

// Registers (or replaces) a durable reminder: first due at `due`, then every `period` ms.
fn reminder_set(sys: *System, grain: str, name: str, due: i64, period: i64) -> err {
    if grain.len == 0usize || name.len == 0usize || period < 0i64 { ret Invalid }
    let (key, key_error) = reminder_key(sys.a, grain, name)
    if key_error != ok { ret key_error }
    let (value, value_error) = reminder_value(sys.a, due, period)
    if value_error != ok { ret value_error }
    ret ds.put(sys.db, reminder_collection(), key, value)
}

fn reminder_cancel(sys: *System, grain: str, name: str) -> (bool, err) {
    let (key, key_error) = reminder_key(sys.a, grain, name)
    if key_error != ok { ret (false, key_error) }
    let (gone, delete_error) = ds.delete(sys.db, reminder_collection(), key)
    ret (gone, delete_error)
}

fn reminder_count(sys: *System) -> usize { ret ds.count(sys.db, reminder_collection()) }

// The next due time after a firing at `now` of a schedule due at `due` with `period`.
fn next_due(due: i64, period: i64, now: i64) -> i64 {
    if period <= 0i64 { ret 0i64 }
    var next = due + period
    if next <= now {
        let behind = now - next
        next += (behind / period + 1i64) * period
    }
    ret next
}

type Pending = struct { key: str, due: i64, period: i64 }

// Fires every timer and reminder due at `now`, oldest first; how many fired. A reminder whose
// handler fails stays due and is retried by the next tick.
fn tick(sys: *System, now: i64) -> (usize, err) {
    var fired = 0usize
    // timers: those of live activations
    var i = 0usize
    while i < sys.ntimers {
        if sys.timers[i].live && sys.timers[i].due <= now {
            let tm = sys.timers[i]
            let (at, found) = find_activation(sys, tm.grain)
            if !found {
                sys.timers[i].live = false
            } else {
                let kind = timer_kind(sys.a, "timer:", tm.name)
                if tm.period > 0i64 {
                    sys.timers[i].due = next_due(tm.due, tm.period, now)
                } else {
                    sys.timers[i].live = false
                }
                if !sys.acts[at].busy {
                    let (reply, deliver_error) = deliver(sys, at, kind, "", now)
                    if deliver_error != ok { ret (fired, deliver_error) }
                    fired += 1usize
                }
            }
        }
        i += 1usize
    }
    // reminders: collect the due ones first, then fire (firing writes to the same collection)
    var pend: [64]Pending = zero
    var np = 0usize
    var n = 0usize
    while true {
        let (key, value, found) = ds.doc_at(sys.db, reminder_collection(), n)
        if !found { break }
        n += 1usize
        let (due, period, parsed) = parse_pair(value)
        if parsed && due <= now && np < MAX_FIRE {
            let (key_copy, keep_error) = keep(sys.a, key)
            if keep_error != ok { ret (fired, keep_error) }
            pend[np] = Pending { key: key_copy, due: due, period: period }
            np += 1usize
        }
    }
    // oldest first (insertion sort; the table is small)
    var a1 = 1usize
    while a1 < np {
        let item = pend[a1]
        var j = a1
        while j > 0usize && pend[j - 1usize].due > item.due {
            pend[j] = pend[j - 1usize]
            j -= 1usize
        }
        pend[j] = item
        a1 += 1usize
    }
    var k = 0usize
    while k < np {
        let p = pend[k]
        var sep = 0usize
        while sep < p.key.len && p.key[sep] != KEY_SEP { sep += 1usize }
        let grain = p.key[0..sep]
        var name = ""
        if sep < p.key.len { name = p.key[sep + 1usize..p.key.len] }
        let (at, activate_error) = activate(sys, grain, now)
        if activate_error != ok { ret (fired, activate_error) }
        let kind = timer_kind(sys.a, "reminder:", name)
        let (reply, deliver_error) = deliver(sys, at, kind, "", now)
        if deliver_error != ok { ret (fired, deliver_error) }
        fired += 1usize
        if p.period > 0i64 {
            let (value, value_error) = reminder_value(sys.a, next_due(p.due, p.period, now), p.period)
            if value_error != ok { ret (fired, value_error) }
            let put_error = ds.put(sys.db, reminder_collection(), p.key, value)
            if put_error != ok { ret (fired, put_error) }
        } else {
            let (gone, delete_error) = ds.delete(sys.db, reminder_collection(), p.key)
            if delete_error != ok { ret (fired, delete_error) }
        }
        k += 1usize
    }
    ret (fired, ok)
}

fn timer_kind(a: *mem.Arena, prefix: str, name: str) -> str {
    let (b0, builder_error) = str.builder(a, 48usize)
    if builder_error != ok { ret "" }
    var b = b0
    let first = str.push(&b, prefix)
    let second = str.push(&b, name)
    if first != ok || second != ok { ret "" }
    ret str.done(&b)
}
