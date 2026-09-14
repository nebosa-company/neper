// Action maps, axes and input buffering (D252).
//
// `e.ui.input` is the device at layer 6; this is the pure logic above it. It never reads
// a keyboard -- the caller feeds it raw codes with `apply` and asks questions in terms of
// actions, so rebinding is changing a field rather than rewriting the game.
//
// The buffering is the part an action game is unplayable without. A player who presses
// attack three frames before the animation allows it did not mean "do nothing", and a
// game that answers only `pressed` this tick tells them they did. `buffered` remembers a
// press for a window of ticks, and `consume` takes it so it fires once.
//
// Nothing here allocates: the caller's bitsets and ring are the whole state.

use e.mem
use e.math.fixed

type Action = struct {
    id: u16,
    primary: u16,
    secondary: u16,
}

type Axis = struct {
    id: u16,
    negative: u16,
    positive: u16,
}

// An ordered run of action ids that counts as a combo when they all land inside `window`
// ticks of one another.
type Combo = struct {
    id: u16,
    first: u16,
    count: u16,
    window: u16,
}

// `buffer` holds the action ids pressed recently and `ages` how many ticks ago, oldest
// entries aging out rather than being cleared, so the ring never has to be compacted.
type State = struct {
    held: []u64,
    pressed: []u64,
    released: []u64,
    buffer: []u16,
    ages: []u16,
    head: usize,
}

error Unknown
error Size

const NONE: u16 = 65535u16

fn init(s: *State, held_bits: []u64, pressed_bits: []u64, released_bits: []u64, buffer: []u16, ages: []u16) -> err {
    if buffer.len != ages.len || buffer.len == 0usize { ret Size }
    if held_bits.len == 0usize || pressed_bits.len != held_bits.len || released_bits.len != held_bits.len { ret Size }
    var at = 0usize
    while at < held_bits.len {
        held_bits[at] = 0u64
        pressed_bits[at] = 0u64
        released_bits[at] = 0u64
        at += 1usize
    }
    at = 0usize
    while at < buffer.len {
        buffer[at] = NONE
        ages[at] = 0u16
        at += 1usize
    }
    s.held = held_bits
    s.pressed = pressed_bits
    s.released = released_bits
    s.buffer = buffer
    s.ages = ages
    s.head = 0usize
    ret ok
}

fn bit_test(words: []const u64, index: usize) -> bool {
    if index / 64usize >= words.len { ret false }
    ret (words[index / 64usize] & (1u64 << u32(index % 64usize))) != 0u64
}

fn bit_set(words: []u64, index: usize) {
    if index / 64usize >= words.len { ret }
    words[index / 64usize] = words[index / 64usize] | (1u64 << u32(index % 64usize))
}

fn bit_clear(words: []u64, index: usize) {
    if index / 64usize >= words.len { ret }
    words[index / 64usize] = words[index / 64usize] & ~(1u64 << u32(index % 64usize))
}

// Start a tick: the edges are for this tick only, and every buffered press gets older.
// An age that would overflow is pinned rather than wrapping, since a wrapped age would
// make an ancient press look fresh.
fn begin(s: *State) -> err {
    var at = 0usize
    while at < s.pressed.len {
        s.pressed[at] = 0u64
        s.released[at] = 0u64
        at += 1usize
    }
    at = 0usize
    while at < s.buffer.len {
        if s.buffer[at] != NONE && s.ages[at] < 65534u16 { s.ages[at] = s.ages[at] + 1u16 }
        at += 1usize
    }
    ret ok
}

// A raw device code changing state. A code that repeats its current state is ignored, so
// a held key that the device reports every tick does not refill the buffer.
fn apply(s: *State, code: u16, down: bool) -> err {
    let index = usize(code)
    let was = bit_test(s.held, index)
    if was == down { ret ok }
    if down {
        bit_set(s.held, index)
        bit_set(s.pressed, index)
        s.buffer[s.head] = code
        s.ages[s.head] = 0u16
        s.head = (s.head + 1usize) % s.buffer.len
    } else {
        bit_clear(s.held, index)
        bit_set(s.released, index)
    }
    ret ok
}

fn bound(a: Action, code: u16) -> bool {
    ret code != NONE && (a.primary == code || a.secondary == code)
}

fn held(s: State, a: Action) -> bool {
    if a.primary != NONE && bit_test(s.held, usize(a.primary)) { ret true }
    ret a.secondary != NONE && bit_test(s.held, usize(a.secondary))
}

fn pressed(s: State, a: Action) -> bool {
    if a.primary != NONE && bit_test(s.pressed, usize(a.primary)) { ret true }
    ret a.secondary != NONE && bit_test(s.pressed, usize(a.secondary))
}

fn released(s: State, a: Action) -> bool {
    if a.primary != NONE && bit_test(s.released, usize(a.primary)) { ret true }
    ret a.secondary != NONE && bit_test(s.released, usize(a.secondary))
}

// Whether either of the action's codes was pressed within `window` ticks. This is the
// forgiving question: `pressed` asks only about this tick.
fn buffered(s: State, a: Action, window: u16) -> bool {
    var at = 0usize
    while at < s.buffer.len {
        if bound(a, s.buffer[at]) && s.ages[at] <= window { ret true }
        at += 1usize
    }
    ret false
}

// Take the buffered press so it fires once. A caller that asks `buffered` and acts
// without consuming will act again next tick, which is the usual double-attack bug.
fn consume(s: *State, a: Action) -> bool {
    var at = 0usize
    while at < s.buffer.len {
        if bound(a, s.buffer[at]) {
            s.buffer[at] = NONE
            s.ages[at] = 0u16
            ret true
        }
        at += 1usize
    }
    ret false
}

// Two codes read as one axis in Q16: both or neither is zero, so opposite keys cancel
// rather than the later one winning.
fn axis(s: State, x: Axis) -> fixed.Fx {
    var value = 0i32
    if x.negative != NONE && bit_test(s.held, usize(x.negative)) { value = value - 65536i32 }
    if x.positive != NONE && bit_test(s.held, usize(x.positive)) { value = value + 65536i32 }
    ret value
}

// An ordered run of codes, each pressed within `window` ticks of the one before it and
// in the right order. The buffer is searched by age rather than by position, so a combo
// spanning the ring's wrap is still found.
fn combo(s: State, c: Combo, steps: []const u16) -> bool {
    if c.count == 0u16 { ret false }
    if usize(c.first) + usize(c.count) > steps.len { ret false }
    var previous_age = 65535u16
    var step = 0u16
    while step < c.count {
        let wanted = steps[usize(c.first) + usize(step)]
        var best = NONE
        var at = 0usize
        while at < s.buffer.len {
            // The most recent press of this code that is still older than the last step.
            if s.buffer[at] == wanted && s.ages[at] < previous_age {
                if best == NONE || s.ages[at] > s.ages[usize(best)] { best = u16(at) }
            }
            at += 1usize
        }
        if best == NONE { ret false }
        if previous_age != 65535u16 && previous_age - s.ages[usize(best)] > c.window { ret false }
        previous_age = s.ages[usize(best)]
        step += 1u16
    }
    ret true
}

fn rebind(a: *Action, primary: u16, secondary: u16) -> err {
    a.primary = primary
    a.secondary = secondary
    ret ok
}
