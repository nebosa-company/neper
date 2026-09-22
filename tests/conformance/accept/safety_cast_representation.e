// The pointer casts that keep a representation (D919, H03): to a type that admits
// only its members from a pointer to that type, or from the `*void` one was erased
// to -- a callback's context; a placement, whose next mention writes the whole
// value; an `@nocheck` block, whose obligation is the author's; and to a type that
// admits any bytes, from anything.
use e.mem

type Color = enum u8 { Red = 1, Green = 2 }
type State = struct { ready: bool, color: Color }

fn visit(context: *void) -> bool {
    let state = mem.cast[*State](context)
    ret state.ready && state.color == .Green
}

fn main() -> i32 {
    var state = State { ready: true, color: .Green }
    let erased = mem.cast[*void](&state)
    if !visit(erased) { ret 1i32 }
    let same = mem.cast[*const State](&state)
    if !same.ready { ret 2i32 }
    var word: u32 = 0x01020304u32
    let bytes = mem.cast[*u8](&word)
    if *bytes == 0u8 { ret 3i32 }
    // Storage handed out as bytes, written whole before anything reads it.
    var storage: [8]u8 = zero
    let placed = mem.cast[*State](&storage[0])
    let written = State { ready: true, color: .Red }
    *placed = written
    if placed.color != .Red { ret 4i32 }
    // Bytes the author vouches for: `storage` holds a `State` written just above.
    @nocheck {
        let vouched = mem.cast[*const State](&storage[0])
        if !vouched.ready { ret 5i32 }
    }
    ret 0i32
}
