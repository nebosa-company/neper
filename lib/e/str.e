// The builder half of the string surface. A builder owns the top of an arena, so
// appending is a bump of the arena offset with no reallocation and no copying; the
// one precondition the compiler cannot prove — that nothing else has allocated since
// the builder was made — is checked on every push and reported as `NotOnTop`.
//
// The parsing, searching and slicing half of `e.str` is not here yet, and neither are
// the float pushes, `push_err` or `format`.
use e.mem

type Sink = struct {
    ctx: *void,
    write: fn(ctx: *void, bytes: []const u8) -> err,
}

type Builder = struct {
    arena: *mem.Arena,
    start: usize,
    len: usize,
    reserved: usize,
    sink: Sink,
    flushing: bool,
}

error NotOnTop

fn builder(a: *mem.Arena, cap: usize) -> (Builder, err) {
    var b: Builder = zero
    b.arena = a
    b.start = mem.mark(a)
    if cap > 0usize {
        let (claim, claim_error) = mem.alloc[u8](a, cap)
        if claim_error != ok { ret (b, claim_error) }
        b.reserved = claim.len
    }
    ret (b, ok)
}

fn builder_to(a: *mem.Arena, cap: usize, sink: Sink) -> (Builder, err) {
    var b: Builder = zero
    b.arena = a
    b.start = mem.mark(a)
    b.sink = sink
    b.flushing = true
    if cap > 0usize {
        let (claim, claim_error) = mem.alloc[u8](a, cap)
        if claim_error != ok { ret (b, claim_error) }
        b.reserved = claim.len
    }
    ret (b, ok)
}

fn done(b: *Builder) -> str {
    let bytes = mem.view(b.arena, b.start, b.len)
    // End the claim by giving the unwritten tail back. The written bytes stay below
    // the new offset, so the result outlives the builder exactly as an allocation does.
    if b.arena.off == b.start + b.reserved { mem.reset(b.arena, b.start + b.len) }
    b.reserved = b.len
    ret bytes
}

fn push(b: *Builder, s: str) -> err {
    var written = 0usize
    while true {
        // One compare turns a silent overwrite of somebody else's allocation into an
        // error, and it is the whole cost of the fast path.
        if b.arena.off != b.start + b.reserved { ret NotOnTop }
        if written == s.len { ret ok }
        let room = b.reserved - b.len
        if room > 0usize {
            var take = room
            if take > s.len - written { take = s.len - written }
            let destination = mem.view(b.arena, b.start + b.len, take)
            var at = 0usize
            while at < take {
                destination[at] = s[written + at]
                at += 1usize
            }
            b.len += take
            written += take
            continue
        }
        // Out of room: grow the claim in place. Nothing can sit between the old claim
        // and the new bytes, because the compare above proved the claim is still on
        // top and `u8` needs no alignment padding. Doubling keeps a long run of small
        // pushes linear; the exact retry keeps the last push working in an arena that
        // has room for the bytes but not for the doubling.
        let needed = s.len - written
        var grow = needed
        if grow < b.reserved { grow = b.reserved }
        let (extra, grow_error) = mem.alloc[u8](b.arena, grow)
        if grow_error == ok {
            b.reserved += extra.len
            continue
        }
        if grow > needed {
            let (exact, exact_error) = mem.alloc[u8](b.arena, needed)
            if exact_error == ok {
                b.reserved += exact.len
                continue
            }
        }
        // A builder with no sink stops here; one with a sink drains what it holds and
        // carries on, which is why a push on a flushing builder never reports
        // `mem.Exhausted` and why a push larger than the buffer streams through.
        if !b.flushing || b.len == 0usize { ret grow_error }
        try b.sink.write(b.sink.ctx, mem.view(b.arena, b.start, b.len))
        b.len = 0usize
    }
    ret ok
}

fn push_byte(b: *Builder, v: u8) -> err {
    var one: [1]u8 = zero
    one[0usize] = v
    ret push(b, one[0usize..1usize])
}

fn push_bool(b: *Builder, v: bool) -> err {
    if v { ret push(b, "true") }
    ret push(b, "false")
}

fn push_i8(b: *Builder, v: i8) -> err {
    ret push_i64(b, i64(v))
}

fn push_i16(b: *Builder, v: i16) -> err {
    ret push_i64(b, i64(v))
}

fn push_i32(b: *Builder, v: i32) -> err {
    ret push_i64(b, i64(v))
}

fn push_i64(b: *Builder, v: i64) -> err {
    // 20 digits plus a sign is the widest decimal `i64` has.
    var digits: [21]u8 = zero
    var at = 21usize
    var rest = 0u64
    if v < 0i64 {
        // The most negative `i64` has no positive counterpart, so peel the last digit
        // off before negating: `v % 10` is in `-9..=0` and `v / 10` always negates.
        at -= 1usize
        digits[at] = 48u8 + u8(0i64 - (v % 10i64))
        rest = u64(0i64 - (v / 10i64))
    } else {
        rest = u64(v)
        if rest == 0u64 {
            at -= 1usize
            digits[at] = 48u8
        }
    }
    while rest > 0u64 {
        at -= 1usize
        digits[at] = 48u8 + u8(rest % 10u64)
        rest = rest / 10u64
    }
    if v < 0i64 {
        at -= 1usize
        digits[at] = 45u8
    }
    ret push(b, digits[at..21usize])
}

fn push_isize(b: *Builder, v: isize) -> err {
    ret push_i64(b, i64(v))
}

fn push_u8(b: *Builder, v: u8) -> err {
    ret push_u64(b, u64(v))
}

fn push_u16(b: *Builder, v: u16) -> err {
    ret push_u64(b, u64(v))
}

fn push_u32(b: *Builder, v: u32) -> err {
    ret push_u64(b, u64(v))
}

fn push_u64(b: *Builder, v: u64) -> err {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = v
    if rest == 0u64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0u64 {
        at -= 1usize
        digits[at] = 48u8 + u8(rest % 10u64)
        rest = rest / 10u64
    }
    ret push(b, digits[at..20usize])
}

fn push_usize(b: *Builder, v: usize) -> err {
    ret push_u64(b, u64(v))
}

fn push_hex_u32(b: *Builder, v: u32) -> err {
    // `{x}` writes the digits alone, so the narrow form is the wide one's output.
    ret push_hex_u64(b, u64(v))
}

fn push_hex_u64(b: *Builder, v: u64) -> err {
    var digits: [16]u8 = zero
    var at = 16usize
    var rest = v
    if rest == 0u64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0u64 {
        at -= 1usize
        let nibble = u8(rest & 15u64)
        if nibble < 10u8 { digits[at] = 48u8 + nibble } else { digits[at] = 87u8 + nibble }
        rest = rest >> 4u64
    }
    ret push(b, digits[at..16usize])
}

fn push_bin_u32(b: *Builder, v: u32) -> err {
    ret push_bin_u64(b, u64(v))
}

fn push_bin_u64(b: *Builder, v: u64) -> err {
    var digits: [64]u8 = zero
    var at = 64usize
    var rest = v
    if rest == 0u64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0u64 {
        at -= 1usize
        digits[at] = 48u8 + u8(rest & 1u64)
        rest = rest >> 1u64
    }
    ret push(b, digits[at..64usize])
}
