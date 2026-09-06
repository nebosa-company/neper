// `mem.cast` is the only route between pointer types, and the only way to reach
// `*void` at all: neither an annotated binding nor a scalar-style `*void(p)` will
// check. It retypes and nothing else -- the address it is handed is the address it
// returns -- so a value parked in a `*void` field comes back through its own type.

use e.mem

error Failed

type Point = struct {
    x: i64,
    y: i64,
}

type Holder = struct {
    ctx: *void,
    tag: i64,
}

// The shape a `str.Sink` context has: the callback takes the erased pointer and has
// to recover the real one itself.
fn bump(ctx: *void, by: i64) -> i64 {
    let counter = mem.cast[*i64](ctx)
    *counter += by
    ret *counter
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Erase and recover: the round trip gives back the value that was stored.
    var n = 7i64
    let erased = mem.cast[*void](&n)
    let recovered = mem.cast[*i64](erased)
    if *recovered != 7i64 { ret Failed }

    // It aliases rather than copies, in both directions.
    *recovered = 11i64
    if n != 11i64 { ret Failed }
    n = 13i64
    if *recovered != 13i64 { ret Failed }

    // A struct pointer survives the same round trip, fields and all.
    var p = Point { x: 3i64, y: 4i64 }
    let point_back = mem.cast[*Point](mem.cast[*void](&p))
    if point_back.x != 3i64 || point_back.y != 4i64 { ret Failed }
    point_back.y = 9i64
    if p.y != 9i64 { ret Failed }

    // Parked in a field and used through a callback, which is what a `Sink`
    // context is for.
    var counter = 0i64
    let holder = Holder { ctx: mem.cast[*void](&counter), tag: 1i64 }
    if bump(holder.ctx, 5i64) != 5i64 { ret Failed }
    if bump(holder.ctx, 2i64) != 7i64 { ret Failed }
    if counter != 7i64 { ret Failed }

    // The bytes of an allocation reached through a cast of their own element
    // pointer: `*u8` in, `*u8` out, with the arena's storage underneath unchanged.
    let (buf, alloc_error) = mem.alloc[u8](a, 4usize)
    if alloc_error != ok { ret alloc_error }
    buf[0usize] = 65u8
    let first = mem.cast[*u8](mem.cast[*void](&buf[0usize]))
    if *first != 65u8 { ret Failed }
    *first = 66u8
    if buf[0usize] != 66u8 { ret Failed }

    // An arena pointer is a pointer like any other.
    let arena_back = mem.cast[*mem.Arena](mem.cast[*void](a))
    if mem.mark(arena_back) != mem.mark(a) { ret Failed }
    ret ok
}
