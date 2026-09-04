// A growable array over an arena. This is the shape the self-hosted compiler
// needs, and the reason comptime parameters exist at all.

use e.mem

type List[T: type] = struct {
    items: []T,
    len:   usize,
    arena: *mem.Arena,
}

fn make[T: type](a: *mem.Arena, cap: usize) -> (List[T], err) {
    let buf = try mem.alloc[T](a, cap)
    ret (List[T]{ items: buf, len: 0, arena: a }, ok)
}

// When full, push allocates a bigger buffer and abandons the old one in the
// arena. The old memory stays valid, so a slice taken before this push keeps
// reading it — silently stale, and no check can catch it (spec §8).
fn push[T: type](l: *List[T], v: T) -> err {
    if l.len == l.items.len {
        let bigger = try mem.alloc[T](l.arena, l.items.len*2 + 8)
        mem.copy[T](bigger, l.items)
        l.items = bigger
    }
    l.items[l.len] = v
    l.len += 1
    ret ok
}

// Contract: the returned slice is valid until the next push. Take it after the
// last push, or take it again.
fn slice[T: type](l: *List[T]) -> []T {
    ret l.items[0..l.len]
}

// Nothing is freed individually. The caller resets the arena.
fn example(a: *mem.Arena) -> err {
    let m = mem.mark(a)
    defer mem.reset(a, m)

    var xs = try make[i32](a, 16)
    for i in 0i32..1000 { // a range takes its bounds' type: i is i32
        try push[i32](&xs, i*i)
    }

    ret ok
}
