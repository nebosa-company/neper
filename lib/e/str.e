// The builder half of the string surface. A builder owns the top of an arena, so
// appending is a bump of the arena offset with no reallocation and no copying; the
// one precondition the compiler cannot prove — that nothing else has allocated since
// the builder was made — is checked on every push and reported as `NotOnTop`.
//
// The searching, slicing and joining half is here too. It allocates only where the
// frozen signature takes an arena: every search, trim and split result borrows the
// input. What is still missing is the float pushes, the float parsers, `push_err`
// and `format`.
use e.mem

type Sink = struct { ctx: *void, write: fn(ctx: *void, bytes: []const u8) -> err }

// `Split` carries a whole traversal by value, so iterating allocates nothing. An
// empty `separator` is the one state `split` cannot produce -- it returns
// `InvalidSeparator` instead -- so `lines` marks its own mode with it, which is the
// only spare bit a frozen four-field struct has.
type Split = struct { source: str, separator: str, off: usize, finished: bool }

type Builder = struct { arena: *mem.Arena, start: usize, len: usize, reserved: usize, sink: Sink, flushing: bool }

error NotOnTop
error InvalidSeparator
error BadNumber

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

// `{.N}`: exactly `precision` digits after the point, rounded half to even. The
// value is expanded to its exact decimal first -- a f64 is a dyadic rational, so it
// has one -- and the rounding then reads digits rather than arithmetic, which is what
// makes a tie a tie. The digit array is large enough for that expansion in full
// (1200 entries against a worst case of about 1091), so nothing is truncated and
// no sticky bit is needed.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f32_fixed`; the two are
// generated from one template rather than written twice.
// `{}`: the shortest digit string that reads back as this exact value. The value is
// expanded to its exact decimal, then rounded to `p` significant digits for a
// `p` the search below narrows, and the test that `p` is enough is `parse_f64` --
// which is frozen into this same surface, so the formatter and the parser cannot
// drift apart by construction. The search is a bisection over `p` in `1..17`,
// because a candidate that reads back correctly at `p` digits still does at `p + 1`.
//
// The point is placed per section 4: fixed notation while the leading digit's decimal
// exponent is in `[-5, 15]`, scientific otherwise.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f32`; the two are
// generated from one template rather than written twice.
fn push_f64(b: *Builder, v: f64) -> err {
    let bits = mem.bitcast[u64](v)
    let sign = bits >> 63u64
    let exponent_field = bits >> 52u64 & 2047u64
    let mantissa_field = bits & 4503599627370495u64
    if exponent_field == 2047u64 {
        if mantissa_field != 0u64 { ret push(b, "nan") }
        if sign == 1u64 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    if exponent_field == 0u64 && mantissa_field == 0u64 {
        if sign == 1u64 { ret push(b, "-0") }
        ret push(b, "0")
    }
    var scale = mantissa_field
    var power = 0i64
    if exponent_field == 0u64 {
        power = -1074i64
    } else {
        scale = mantissa_field + 4503599627370496u64
        power = i64(exponent_field) - 1075i64
    }
    // The exact decimal of `scale * 2^power`, as `0.digits * 10^exponent`.
    var digits: [1200]u8 = zero
    var used = 0usize
    var exponent = 0i64
    var reversed: [24]u8 = zero
    var length = 0usize
    var rest = scale
    while rest > 0u64 {
        reversed[length] = u8(rest % 10u64)
        length += 1usize
        rest = rest / 10u64
    }
    exponent = i64(length)
    var back = 0usize
    while back < length {
        digits[back] = reversed[length - 1usize - back]
        back += 1usize
    }
    used = length
    while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    digits[shift] = digits[shift - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                digits[used] = 5u8
                used += 1usize
            }
            if digits[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    digits[shift] = digits[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // Bisect for the fewest significant digits that read back as this value. The
    // magnitude is what is compared, because the candidate never carries the sign.
    let magnitude = bits & 9223372036854775807u64
    var low = 1usize
    var high = 17usize
    while low < high {
        let middle = (low + high) / 2usize
        var trial: [24]u8 = zero
        var trial_used = middle
        var trial_exponent = exponent
        var fill = 0usize
        while fill < middle {
            var digit = 0u8
            if fill < used { digit = digits[fill] }
            trial[fill] = digit
            fill += 1usize
        }
        var lift = false
        if middle < used {
            let first = digits[middle]
            if first > 5u8 { lift = true }
            if first == 5u8 {
                var beyond = false
                var scan = middle + 1usize
                while scan < used {
                    if digits[scan] != 0u8 { beyond = true }
                    scan += 1usize
                }
                if beyond {
                    lift = true
                } else {
                    lift = trial[middle - 1usize] % 2u8 == 1u8
                }
            }
        }
        if lift {
            var carry = true
            var at = trial_used
            while at > 0usize && carry {
                at = at - 1usize
                if trial[at] == 9u8 {
                    trial[at] = 0u8
                } else {
                    trial[at] = trial[at] + 1u8
                    carry = false
                }
            }
            if carry {
                var shift = trial_used
                while shift > 0usize {
                    trial[shift] = trial[shift - 1usize]
                    shift = shift - 1usize
                }
                trial[0usize] = 1u8
                trial_used += 1usize
                trial_exponent += 1i64
            }
        }
        while trial_used > 0usize && trial[trial_used - 1usize] == 0u8 { trial_used = trial_used - 1usize }
        // `0.<digits>e<exponent>` is a spelling `parse_f64` accepts for any candidate.
        var candidate: [40]u8 = zero
        candidate[0usize] = 48u8
        candidate[1usize] = 46u8
        var written = 2usize
        var emit = 0usize
        while emit < trial_used {
            candidate[written] = 48u8 + trial[emit]
            written += 1usize
            emit += 1usize
        }
        candidate[written] = 101u8
        written += 1usize
        var power_left = trial_exponent
        if power_left < 0i64 {
            candidate[written] = 45u8
            written += 1usize
            power_left = 0i64 - power_left
        }
        var power_digits: [8]u8 = zero
        var power_length = 0usize
        while power_left > 0i64 {
            power_digits[power_length] = u8(power_left % 10i64)
            power_length += 1usize
            power_left = power_left / 10i64
        }
        if power_length == 0usize {
            candidate[written] = 48u8
            written += 1usize
        }
        while power_length > 0usize {
            power_length = power_length - 1usize
            candidate[written] = 48u8 + power_digits[power_length]
            written += 1usize
        }
        let (reread, reread_error) = parse_f64(candidate[0usize..written])
        var enough = false
        if reread_error == ok {
            if mem.bitcast[u64](reread) == magnitude { enough = true }
        }
        if enough {
            high = middle
        } else {
            low = middle + 1usize
        }
    }
    // Round once more at the length the bisection settled on, and keep the result.
    var shortest: [24]u8 = zero
    var shortest_used = low
    var shortest_exponent = exponent
    var fill = 0usize
    while fill < low {
        var digit = 0u8
        if fill < used { digit = digits[fill] }
        shortest[fill] = digit
        fill += 1usize
    }
    var lift = false
    if low < used {
        let first = digits[low]
        if first > 5u8 { lift = true }
        if first == 5u8 {
            var beyond = false
            var scan = low + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                lift = true
            } else {
                lift = shortest[low - 1usize] % 2u8 == 1u8
            }
        }
    }
    if lift {
        var carry = true
        var at = shortest_used
        while at > 0usize && carry {
            at = at - 1usize
            if shortest[at] == 9u8 {
                shortest[at] = 0u8
            } else {
                shortest[at] = shortest[at] + 1u8
                carry = false
            }
        }
        if carry {
            var shift = shortest_used
            while shift > 0usize {
                shortest[shift] = shortest[shift - 1usize]
                shift = shift - 1usize
            }
            shortest[0usize] = 1u8
            shortest_used += 1usize
            shortest_exponent += 1i64
        }
    }
    while shortest_used > 0usize && shortest[shortest_used - 1usize] == 0u8 { shortest_used = shortest_used - 1usize }
    // Section 4's notation rule is on the leading digit's exponent, which is one less
    // than the exponent of `0.digits`.
    let leading = shortest_exponent - 1i64
    var text: [48]u8 = zero
    var written = 0usize
    if sign == 1u64 {
        text[written] = 45u8
        written += 1usize
    }
    if leading >= -5i64 && leading <= 15i64 {
        if shortest_exponent <= 0i64 {
            text[written] = 48u8
            written += 1usize
            text[written] = 46u8
            written += 1usize
            var fill_count = 0i64 - shortest_exponent
            while fill_count > 0i64 {
                text[written] = 48u8
                written += 1usize
                fill_count = fill_count - 1i64
            }
            var emit = 0usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        } else {
            var whole = usize(shortest_exponent)
            var emit = 0usize
            while emit < whole {
                var digit = 0u8
                if emit < shortest_used { digit = shortest[emit] }
                text[written] = 48u8 + digit
                written += 1usize
                emit += 1usize
            }
            if shortest_used > whole {
                text[written] = 46u8
                written += 1usize
                while emit < shortest_used {
                    text[written] = 48u8 + shortest[emit]
                    written += 1usize
                    emit += 1usize
                }
            }
        }
    } else {
        text[written] = 48u8 + shortest[0usize]
        written += 1usize
        if shortest_used > 1usize {
            text[written] = 46u8
            written += 1usize
            var emit = 1usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        }
        text[written] = 101u8
        written += 1usize
        var power_left = leading
        if power_left < 0i64 {
            text[written] = 45u8
            written += 1usize
            power_left = 0i64 - power_left
        }
        var power_digits: [8]u8 = zero
        var power_length = 0usize
        while power_left > 0i64 {
            power_digits[power_length] = u8(power_left % 10i64)
            power_length += 1usize
            power_left = power_left / 10i64
        }
        if power_length == 0usize {
            text[written] = 48u8
            written += 1usize
        }
        while power_length > 0usize {
            power_length = power_length - 1usize
            text[written] = 48u8 + power_digits[power_length]
            written += 1usize
        }
    }
    ret push(b, text[0usize..written])
}

// `{}`: the shortest digit string that reads back as this exact value. The value is
// expanded to its exact decimal, then rounded to `p` significant digits for a
// `p` the search below narrows, and the test that `p` is enough is `parse_f32` --
// which is frozen into this same surface, so the formatter and the parser cannot
// drift apart by construction. The search is a bisection over `p` in `1..9`,
// because a candidate that reads back correctly at `p` digits still does at `p + 1`.
//
// The point is placed per section 4: fixed notation while the leading digit's decimal
// exponent is in `[-5, 15]`, scientific otherwise.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f64`; the two are
// generated from one template rather than written twice.
fn push_f32(b: *Builder, v: f32) -> err {
    let bits = mem.bitcast[u32](v)
    let sign = bits >> 31u32
    let exponent_field = bits >> 23u32 & 255u32
    let mantissa_field = bits & 8388607u32
    if exponent_field == 255u32 {
        if mantissa_field != 0u32 { ret push(b, "nan") }
        if sign == 1u32 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    if exponent_field == 0u32 && mantissa_field == 0u32 {
        if sign == 1u32 { ret push(b, "-0") }
        ret push(b, "0")
    }
    var scale = mantissa_field
    var power = 0i64
    if exponent_field == 0u32 {
        power = -149i64
    } else {
        scale = mantissa_field + 8388608u32
        power = i64(exponent_field) - 150i64
    }
    // The exact decimal of `scale * 2^power`, as `0.digits * 10^exponent`.
    var digits: [256]u8 = zero
    var used = 0usize
    var exponent = 0i64
    var reversed: [24]u8 = zero
    var length = 0usize
    var rest = scale
    while rest > 0u32 {
        reversed[length] = u8(rest % 10u32)
        length += 1usize
        rest = rest / 10u32
    }
    exponent = i64(length)
    var back = 0usize
    while back < length {
        digits[back] = reversed[length - 1usize - back]
        back += 1usize
    }
    used = length
    while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    digits[shift] = digits[shift - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                digits[used] = 5u8
                used += 1usize
            }
            if digits[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    digits[shift] = digits[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // Bisect for the fewest significant digits that read back as this value. The
    // magnitude is what is compared, because the candidate never carries the sign.
    let magnitude = bits & 2147483647u32
    var low = 1usize
    var high = 9usize
    while low < high {
        let middle = (low + high) / 2usize
        var trial: [24]u8 = zero
        var trial_used = middle
        var trial_exponent = exponent
        var fill = 0usize
        while fill < middle {
            var digit = 0u8
            if fill < used { digit = digits[fill] }
            trial[fill] = digit
            fill += 1usize
        }
        var lift = false
        if middle < used {
            let first = digits[middle]
            if first > 5u8 { lift = true }
            if first == 5u8 {
                var beyond = false
                var scan = middle + 1usize
                while scan < used {
                    if digits[scan] != 0u8 { beyond = true }
                    scan += 1usize
                }
                if beyond {
                    lift = true
                } else {
                    lift = trial[middle - 1usize] % 2u8 == 1u8
                }
            }
        }
        if lift {
            var carry = true
            var at = trial_used
            while at > 0usize && carry {
                at = at - 1usize
                if trial[at] == 9u8 {
                    trial[at] = 0u8
                } else {
                    trial[at] = trial[at] + 1u8
                    carry = false
                }
            }
            if carry {
                var shift = trial_used
                while shift > 0usize {
                    trial[shift] = trial[shift - 1usize]
                    shift = shift - 1usize
                }
                trial[0usize] = 1u8
                trial_used += 1usize
                trial_exponent += 1i64
            }
        }
        while trial_used > 0usize && trial[trial_used - 1usize] == 0u8 { trial_used = trial_used - 1usize }
        // `0.<digits>e<exponent>` is a spelling `parse_f32` accepts for any candidate.
        var candidate: [40]u8 = zero
        candidate[0usize] = 48u8
        candidate[1usize] = 46u8
        var written = 2usize
        var emit = 0usize
        while emit < trial_used {
            candidate[written] = 48u8 + trial[emit]
            written += 1usize
            emit += 1usize
        }
        candidate[written] = 101u8
        written += 1usize
        var power_left = trial_exponent
        if power_left < 0i64 {
            candidate[written] = 45u8
            written += 1usize
            power_left = 0i64 - power_left
        }
        var power_digits: [8]u8 = zero
        var power_length = 0usize
        while power_left > 0i64 {
            power_digits[power_length] = u8(power_left % 10i64)
            power_length += 1usize
            power_left = power_left / 10i64
        }
        if power_length == 0usize {
            candidate[written] = 48u8
            written += 1usize
        }
        while power_length > 0usize {
            power_length = power_length - 1usize
            candidate[written] = 48u8 + power_digits[power_length]
            written += 1usize
        }
        let (reread, reread_error) = parse_f32(candidate[0usize..written])
        var enough = false
        if reread_error == ok {
            if mem.bitcast[u32](reread) == magnitude { enough = true }
        }
        if enough {
            high = middle
        } else {
            low = middle + 1usize
        }
    }
    // Round once more at the length the bisection settled on, and keep the result.
    var shortest: [24]u8 = zero
    var shortest_used = low
    var shortest_exponent = exponent
    var fill = 0usize
    while fill < low {
        var digit = 0u8
        if fill < used { digit = digits[fill] }
        shortest[fill] = digit
        fill += 1usize
    }
    var lift = false
    if low < used {
        let first = digits[low]
        if first > 5u8 { lift = true }
        if first == 5u8 {
            var beyond = false
            var scan = low + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                lift = true
            } else {
                lift = shortest[low - 1usize] % 2u8 == 1u8
            }
        }
    }
    if lift {
        var carry = true
        var at = shortest_used
        while at > 0usize && carry {
            at = at - 1usize
            if shortest[at] == 9u8 {
                shortest[at] = 0u8
            } else {
                shortest[at] = shortest[at] + 1u8
                carry = false
            }
        }
        if carry {
            var shift = shortest_used
            while shift > 0usize {
                shortest[shift] = shortest[shift - 1usize]
                shift = shift - 1usize
            }
            shortest[0usize] = 1u8
            shortest_used += 1usize
            shortest_exponent += 1i64
        }
    }
    while shortest_used > 0usize && shortest[shortest_used - 1usize] == 0u8 { shortest_used = shortest_used - 1usize }
    // Section 4's notation rule is on the leading digit's exponent, which is one less
    // than the exponent of `0.digits`.
    let leading = shortest_exponent - 1i64
    var text: [48]u8 = zero
    var written = 0usize
    if sign == 1u32 {
        text[written] = 45u8
        written += 1usize
    }
    if leading >= -5i64 && leading <= 15i64 {
        if shortest_exponent <= 0i64 {
            text[written] = 48u8
            written += 1usize
            text[written] = 46u8
            written += 1usize
            var fill_count = 0i64 - shortest_exponent
            while fill_count > 0i64 {
                text[written] = 48u8
                written += 1usize
                fill_count = fill_count - 1i64
            }
            var emit = 0usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        } else {
            var whole = usize(shortest_exponent)
            var emit = 0usize
            while emit < whole {
                var digit = 0u8
                if emit < shortest_used { digit = shortest[emit] }
                text[written] = 48u8 + digit
                written += 1usize
                emit += 1usize
            }
            if shortest_used > whole {
                text[written] = 46u8
                written += 1usize
                while emit < shortest_used {
                    text[written] = 48u8 + shortest[emit]
                    written += 1usize
                    emit += 1usize
                }
            }
        }
    } else {
        text[written] = 48u8 + shortest[0usize]
        written += 1usize
        if shortest_used > 1usize {
            text[written] = 46u8
            written += 1usize
            var emit = 1usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        }
        text[written] = 101u8
        written += 1usize
        var power_left = leading
        if power_left < 0i64 {
            text[written] = 45u8
            written += 1usize
            power_left = 0i64 - power_left
        }
        var power_digits: [8]u8 = zero
        var power_length = 0usize
        while power_left > 0i64 {
            power_digits[power_length] = u8(power_left % 10i64)
            power_length += 1usize
            power_left = power_left / 10i64
        }
        if power_length == 0usize {
            text[written] = 48u8
            written += 1usize
        }
        while power_length > 0usize {
            power_length = power_length - 1usize
            text[written] = 48u8 + power_digits[power_length]
            written += 1usize
        }
    }
    ret push(b, text[0usize..written])
}

fn push_f64_fixed(b: *Builder, v: f64, precision: u8) -> err {
    if precision > 99u8 { ret BadNumber }
    let bits = mem.bitcast[u64](v)
    let sign = bits >> 63u64
    let exponent_field = bits >> 52u64 & 2047u64
    let mantissa_field = bits & 4503599627370495u64
    // A non-finite value writes its token and no fractional suffix at all.
    if exponent_field == 2047u64 {
        if mantissa_field != 0u64 { ret push(b, "nan") }
        if sign == 1u64 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    // The value is `scale * 2^power`, exactly.
    var scale = mantissa_field
    var power = 0i64
    if exponent_field == 0u64 {
        power = -1074i64
    } else {
        scale = mantissa_field + 4503599627370496u64
        power = i64(exponent_field) - 1075i64
    }
    var digits: [1200]u8 = zero
    var used = 0usize
    var exponent = 0i64
    if scale != 0u64 {
        var reversed: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u64 {
            reversed[length] = u8(rest % 10u64)
            length += 1usize
            rest = rest / 10u64
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            digits[back] = reversed[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // Apply the binary exponent one bit at a time, which keeps the decimal exact.
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    digits[shift] = digits[shift - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                digits[used] = 5u8
                used += 1usize
            }
            if digits[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    digits[shift] = digits[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // `cut` is how many digits of `digits` survive scaling by `10^precision`, which
    // makes the answer an integer and the rounding an ordinary digit comparison.
    let places = usize(precision)
    var cut = exponent + i64(places)
    var round_up = false
    if cut >= 0i64 && usize(cut) < used {
        let first = digits[usize(cut)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = false
            var scan = usize(cut) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                // An exact tie goes to the even last kept digit; a digit past the end
                // of the expansion is a zero, which is even.
                var last = 0u8
                if cut > 0i64 && usize(cut) - 1usize < used { last = digits[usize(cut) - 1usize] }
                round_up = last % 2u8 == 1u8
            }
        }
    }
    var kept: [512]u8 = zero
    var digits_kept = 0usize
    if cut > 0i64 { digits_kept = usize(cut) }
    var at = 0usize
    while at < digits_kept {
        var digit = 0u8
        if at < used { digit = digits[at] }
        kept[at] = digit
        at += 1usize
    }
    if round_up {
        var carry = true
        var back = digits_kept
        while back > 0usize && carry {
            back = back - 1usize
            if kept[back] == 9u8 {
                kept[back] = 0u8
            } else {
                kept[back] = kept[back] + 1u8
                carry = false
            }
        }
        if carry {
            var shift = digits_kept
            while shift > 0usize {
                kept[shift] = kept[shift - 1usize]
                shift = shift - 1usize
            }
            kept[0usize] = 1u8
            digits_kept += 1usize
        }
    }
    // The kept digits are the value times `10^precision`; the point goes that many
    // places from the right, and a sign is written even for a negative zero.
    var text: [512]u8 = zero
    var length = 0usize
    if sign == 1u64 {
        text[0usize] = 45u8
        length = 1usize
    }
    if digits_kept > places {
        var whole = 0usize
        while whole < digits_kept - places {
            text[length] = 48u8 + kept[whole]
            length += 1usize
            whole += 1usize
        }
    } else {
        text[length] = 48u8
        length += 1usize
    }
    if places > 0usize {
        text[length] = 46u8
        length += 1usize
        var fill_count = 0usize
        if digits_kept < places { fill_count = places - digits_kept }
        while fill_count > 0usize {
            text[length] = 48u8
            length += 1usize
            fill_count = fill_count - 1usize
        }
        var tail = 0usize
        if digits_kept > places { tail = digits_kept - places }
        while tail < digits_kept {
            text[length] = 48u8 + kept[tail]
            length += 1usize
            tail += 1usize
        }
    }
    ret push(b, text[0usize..length])
}

// `{.N}`: exactly `precision` digits after the point, rounded half to even. The
// value is expanded to its exact decimal first -- a f32 is a dyadic rational, so it
// has one -- and the rounding then reads digits rather than arithmetic, which is what
// makes a tie a tie. The digit array is large enough for that expansion in full
// (256 entries against a worst case of about 173), so nothing is truncated and
// no sticky bit is needed.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f64_fixed`; the two are
// generated from one template rather than written twice.
fn push_f32_fixed(b: *Builder, v: f32, precision: u8) -> err {
    if precision > 99u8 { ret BadNumber }
    let bits = mem.bitcast[u32](v)
    let sign = bits >> 31u32
    let exponent_field = bits >> 23u32 & 255u32
    let mantissa_field = bits & 8388607u32
    // A non-finite value writes its token and no fractional suffix at all.
    if exponent_field == 255u32 {
        if mantissa_field != 0u32 { ret push(b, "nan") }
        if sign == 1u32 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    // The value is `scale * 2^power`, exactly.
    var scale = mantissa_field
    var power = 0i64
    if exponent_field == 0u32 {
        power = -149i64
    } else {
        scale = mantissa_field + 8388608u32
        power = i64(exponent_field) - 150i64
    }
    var digits: [256]u8 = zero
    var used = 0usize
    var exponent = 0i64
    if scale != 0u32 {
        var reversed: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u32 {
            reversed[length] = u8(rest % 10u32)
            length += 1usize
            rest = rest / 10u32
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            digits[back] = reversed[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // Apply the binary exponent one bit at a time, which keeps the decimal exact.
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    digits[shift] = digits[shift - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                digits[used] = 5u8
                used += 1usize
            }
            if digits[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    digits[shift] = digits[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // `cut` is how many digits of `digits` survive scaling by `10^precision`, which
    // makes the answer an integer and the rounding an ordinary digit comparison.
    let places = usize(precision)
    var cut = exponent + i64(places)
    var round_up = false
    if cut >= 0i64 && usize(cut) < used {
        let first = digits[usize(cut)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = false
            var scan = usize(cut) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                // An exact tie goes to the even last kept digit; a digit past the end
                // of the expansion is a zero, which is even.
                var last = 0u8
                if cut > 0i64 && usize(cut) - 1usize < used { last = digits[usize(cut) - 1usize] }
                round_up = last % 2u8 == 1u8
            }
        }
    }
    var kept: [256]u8 = zero
    var digits_kept = 0usize
    if cut > 0i64 { digits_kept = usize(cut) }
    var at = 0usize
    while at < digits_kept {
        var digit = 0u8
        if at < used { digit = digits[at] }
        kept[at] = digit
        at += 1usize
    }
    if round_up {
        var carry = true
        var back = digits_kept
        while back > 0usize && carry {
            back = back - 1usize
            if kept[back] == 9u8 {
                kept[back] = 0u8
            } else {
                kept[back] = kept[back] + 1u8
                carry = false
            }
        }
        if carry {
            var shift = digits_kept
            while shift > 0usize {
                kept[shift] = kept[shift - 1usize]
                shift = shift - 1usize
            }
            kept[0usize] = 1u8
            digits_kept += 1usize
        }
    }
    // The kept digits are the value times `10^precision`; the point goes that many
    // places from the right, and a sign is written even for a negative zero.
    var text: [256]u8 = zero
    var length = 0usize
    if sign == 1u32 {
        text[0usize] = 45u8
        length = 1usize
    }
    if digits_kept > places {
        var whole = 0usize
        while whole < digits_kept - places {
            text[length] = 48u8 + kept[whole]
            length += 1usize
            whole += 1usize
        }
    } else {
        text[length] = 48u8
        length += 1usize
    }
    if places > 0usize {
        text[length] = 46u8
        length += 1usize
        var fill_count = 0usize
        if digits_kept < places { fill_count = places - digits_kept }
        while fill_count > 0usize {
            text[length] = 48u8
            length += 1usize
            fill_count = fill_count - 1usize
        }
        var tail = 0usize
        if digits_kept > places { tail = digits_kept - places }
        while tail < digits_kept {
            text[length] = 48u8 + kept[tail]
            length += 1usize
            tail += 1usize
        }
    }
    ret push(b, text[0usize..length])
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

fn concat(a: *mem.Arena, x: str, y: str) -> (str, err) {
    var (b, builder_error) = builder(a, x.len + y.len)
    if builder_error != ok { ret ("", builder_error) }
    let x_error = push(&b, x)
    if x_error != ok { ret ("", x_error) }
    let y_error = push(&b, y)
    if y_error != ok { ret ("", y_error) }
    let out = done(&b)
    ret (out, ok)
}

fn join(a: *mem.Arena, parts: []const str, sep: str) -> (str, err) {
    // The exact size up front, so the one claim covers the whole result and the
    // builder never has to grow.
    var total = 0usize
    var at = 0usize
    while at < parts.len {
        total += parts[at].len
        at += 1usize
    }
    if parts.len > 1usize { total += sep.len * (parts.len - 1usize) }
    var (b, builder_error) = builder(a, total)
    if builder_error != ok { ret ("", builder_error) }
    at = 0usize
    while at < parts.len {
        if at > 0usize {
            let sep_error = push(&b, sep)
            if sep_error != ok { ret ("", sep_error) }
        }
        let part_error = push(&b, parts[at])
        if part_error != ok { ret ("", part_error) }
        at += 1usize
    }
    let out = done(&b)
    ret (out, ok)
}

fn eq(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

fn parse_i64(s: str) -> (i64, err) {
    let (value, value_error) = parse_i64_radix(s, 10u8)
    ret (value, value_error)
}

fn parse_u64(s: str) -> (u64, err) {
    let (value, value_error) = parse_u64_radix(s, 10u8)
    ret (value, value_error)
}

// The magnitude is parsed unsigned, because `i64`'s most negative value has no
// positive counterpart to build and then negate. Its own magnitude is written out
// rather than converted: section 4 makes `i64(x)` checked, so `i64` of 2**63 is a
// `narrow` trap the moment section 11's check table is emitted, even though the
// current back end truncates it to the answer this returns.
fn parse_i64_radix(s: str, radix: u8) -> (i64, err) {
    var digits = s
    var negative = false
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        digits = s[1usize..]
    }
    let (magnitude, magnitude_error) = parse_u64_radix(digits, radix)
    if magnitude_error != ok { ret (0i64, magnitude_error) }
    if negative {
        if magnitude > 9223372036854775808u64 { ret (0i64, BadNumber) }
        if magnitude == 9223372036854775808u64 { ret (-9223372036854775807i64 - 1i64, ok) }
        ret (0i64 - i64(magnitude), ok)
    }
    if magnitude > 9223372036854775807u64 { ret (0i64, BadNumber) }
    ret (i64(magnitude), ok)
}

// Every byte is a digit or the input is malformed: no sign, no prefix, no separators
// and no surrounding space. Overflow is checked before the multiply rather than
// after, because there is no wrapping arithmetic to detect it with.
fn parse_u64_radix(s: str, radix: u8) -> (u64, err) {
    if radix < 2u8 || radix > 36u8 { ret (0u64, BadNumber) }
    if s.len == 0usize { ret (0u64, BadNumber) }
    let base = u64(radix)
    let limit = 18446744073709551615u64
    var value = 0u64
    var at = 0usize
    while at < s.len {
        let byte = s[at]
        // 37 is past every radix, so a byte that is not a digit at all fails the
        // same comparison as one that is out of range for this radix.
        var digit = 37u8
        if byte >= 48u8 && byte <= 57u8 { digit = byte - 48u8 }
        if byte >= 65u8 && byte <= 90u8 { digit = byte - 55u8 }
        if byte >= 97u8 && byte <= 122u8 { digit = byte - 87u8 }
        if digit >= radix { ret (0u64, BadNumber) }
        let scaled = u64(digit)
        if value > (limit - scaled) / base { ret (0u64, BadNumber) }
        value = value * base + scaled
        at += 1usize
    }
    ret (value, ok)
}

// The exact inverse of what `push_f64` writes, in integer arithmetic: the digits
// become an arbitrary-precision decimal that is halved and doubled one bit at a time
// until the binary exponent falls out and the mantissa can be read off the front.
// Nothing here rounds twice, so the result is the nearest f64 to the input, ties to
// even. It is also linear in the decimal exponent: a value near either end of the
// range costs about a thousand passes over the digits, where one near 1 costs about
// fifty. A Clinger fast path for the common case is the upgrade; correctness does not
// depend on it.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `parse_f32`; the two are
// generated from one template rather than written twice.
fn parse_f64(s: str) -> (f64, err) {
    // The non-finite spellings are exact tokens, not numbers, and the NaN handed back
    // is section 11's canonical quiet one rather than whatever an operation produced.
    if eq(s, "inf") { ret (mem.bitcast[f64](9218868437227405312u64), ok) }
    if eq(s, "-inf") { ret (mem.bitcast[f64](18442240474082181120u64), ok) }
    if eq(s, "nan") { ret (mem.bitcast[f64](9221120237041090560u64), ok) }
    // 768 digits is past the longest exact tie this width has (768 of them),
    // so a tie always fits and a decimal that does not fit is never one: what
    // spills past the end can only be the sticky bit `truncated` carries.
    var digits: [768]u8 = zero
    var used = 0usize
    var truncated = false
    var negative = false
    var at = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        at = 1usize
    }
    // The grammar is the one the pushes write and nothing else: at least one digit,
    // at most one point with digits on both sides, no separators, no leading `+`, no
    // surrounding space, and a lowercase `e` exponent with at least one digit.
    var integer_digits = 0usize
    var fraction_digits = 0usize
    var leading_zeros = 0usize
    var started = false
    var in_fraction = false
    while at < s.len {
        let byte = s[at]
        if byte == 46u8 && !in_fraction && integer_digits > 0usize {
            in_fraction = true
            at += 1usize
            continue
        }
        if byte < 48u8 || byte > 57u8 { break }
        if in_fraction { fraction_digits += 1usize } else { integer_digits += 1usize }
        let digit = byte - 48u8
        if !started && digit == 0u8 {
            leading_zeros += 1usize
        } else {
            started = true
            if used < digits.len {
                digits[used] = digit
                used += 1usize
            } else {
                if digit != 0u8 { truncated = true }
            }
        }
        at += 1usize
    }
    if integer_digits == 0usize { ret (0.0f64, BadNumber) }
    if in_fraction && fraction_digits == 0usize { ret (0.0f64, BadNumber) }
    // `I.F` is `0.(I F) * 10^len(I)`, and every leading zero dropped takes one off it.
    var exponent = i64(integer_digits) - i64(leading_zeros)
    if at < s.len && s[at] == 101u8 {
        at += 1usize
        var exponent_negative = false
        if at < s.len && (s[at] == 43u8 || s[at] == 45u8) {
            exponent_negative = s[at] == 45u8
            at += 1usize
        }
        var magnitude = 0i64
        var exponent_digits = 0usize
        while at < s.len {
            let byte = s[at]
            if byte < 48u8 || byte > 57u8 { break }
            exponent_digits += 1usize
            // Past six digits the value is out of range either way, and the clamp is
            // what keeps the normalization below finite.
            if magnitude < 1000000i64 { magnitude = magnitude * 10i64 + i64(byte - 48u8) }
            at += 1usize
        }
        if exponent_digits == 0usize { ret (0.0f64, BadNumber) }
        if exponent_negative { exponent = exponent - magnitude } else { exponent = exponent + magnitude }
    }
    if at != s.len { ret (0.0f64, BadNumber) }
    while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    // An exact zero keeps its sign; it is the one zero a parse may return.
    if used == 0usize {
        var zero_pattern = 0u64
        if negative { zero_pattern = 9223372036854775808u64 }
        ret (mem.bitcast[f64](zero_pattern), ok)
    }
    // Bounds that only keep the loops finite. Anything outside them is out of range by
    // a wide margin; anything inside is decided exactly below.
    if exponent > 400i64 || exponent < -450i64 { ret (0.0f64, BadNumber) }
    var binary_exponent = 0i64
    while true {
        if used == 0usize { break }
        // `0.digits * 10^exponent` with a leading digit of at least one lies in
        // `[0.1, 1)`, so both comparisons are on the exponent alone.
        var halving = false
        var doubling = false
        if exponent >= 1i64 {
            halving = true
        } else {
            if exponent < 0i64 {
                doubling = true
            } else {
                if digits[0usize] < 5u8 { doubling = true }
            }
        }
        if !halving && !doubling { break }
        if halving {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                if used < digits.len {
                    digits[used] = 5u8
                    used += 1usize
                } else {
                    truncated = true
                }
            }
            // The division can leave one leading zero, which belongs to the exponent.
            if digits[0usize] == 0u8 {
                var back = 0usize
                while back + 1usize < used {
                    digits[back] = digits[back + 1usize]
                    back += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            binary_exponent += 1i64
        } else {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                if used == digits.len {
                    if digits[used - 1usize] != 0u8 { truncated = true }
                } else {
                    used += 1usize
                }
                var back = used
                while back > 1usize {
                    back = back - 1usize
                    digits[back] = digits[back - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            binary_exponent = binary_exponent - 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // The value is `m * 2^binary_exponent` with `m` in `[0.5, 1)`, which fixes a
    // normal number's exponent field and leaves only the mantissa to read.
    var biased = binary_exponent - 1i64 + 1023i64
    var bits = 53i64
    if biased < 1i64 {
        // Subnormal: the exponent field is pinned at zero and the mantissa loses one
        // bit for every step below the smallest normal. `bits` is the value's exponent
        // in units of that smallest subnormal, so a negative one is less than half of
        // it and rounds to a zero the input did not write.
        bits = 53i64 + biased - 1i64
        biased = 0i64
        if bits < 0i64 { ret (0.0f64, BadNumber) }
    }
    var shifted = 0i64
    while shifted < bits {
        var carry = 0u8
        var scan = used
        while scan > 0usize {
            scan = scan - 1usize
            let value = digits[scan] * 2u8 + carry
            digits[scan] = value % 10u8
            carry = value / 10u8
        }
        if carry != 0u8 {
            if used == digits.len {
                if digits[used - 1usize] != 0u8 { truncated = true }
            } else {
                used += 1usize
            }
            var back = used
            while back > 1usize {
                back = back - 1usize
                digits[back] = digits[back - 1usize]
            }
            digits[0usize] = carry
            exponent += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        shifted += 1i64
    }
    var mantissa = 0u64
    var taken = 0i64
    while taken < exponent {
        var digit = 0u8
        if usize(taken) < used { digit = digits[usize(taken)] }
        mantissa = mantissa * 10u64 + u64(digit)
        taken += 1i64
    }
    // Round to nearest, ties to even, on the digits the integer part left behind.
    var round_up = false
    if exponent >= 0i64 && usize(exponent) < used {
        let first = digits[usize(exponent)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = truncated
            var scan = usize(exponent) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                round_up = mantissa % 2u64 == 1u64
            }
        }
    }
    if round_up { mantissa += 1u64 }
    let implicit = 1u64 << 52u64
    if biased == 0i64 {
        // The carry out of a subnormal's mantissa is exactly the smallest normal.
        if mantissa >= implicit { biased = 1i64 }
    } else {
        if mantissa >= implicit * 2u64 {
            mantissa = mantissa / 2u64
            biased += 1i64
        }
    }
    if biased > 2046i64 { ret (0.0f64, BadNumber) }
    var fraction = mantissa
    if biased >= 1i64 { fraction = mantissa - implicit }
    if biased == 0i64 && fraction == 0u64 { ret (0.0f64, BadNumber) }
    var pattern = u64(biased) << 52u64
    pattern = pattern + fraction
    if negative { pattern = pattern + 9223372036854775808u64 }
    ret (mem.bitcast[f64](pattern), ok)
}

// The exact inverse of what `push_f32` writes, in integer arithmetic: the digits
// become an arbitrary-precision decimal that is halved and doubled one bit at a time
// until the binary exponent falls out and the mantissa can be read off the front.
// Nothing here rounds twice, so the result is the nearest f32 to the input, ties to
// even. It is also linear in the decimal exponent: a value near either end of the
// range costs about a thousand passes over the digits, where one near 1 costs about
// fifty. A Clinger fast path for the common case is the upgrade; correctness does not
// depend on it.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `parse_f64`; the two are
// generated from one template rather than written twice.
fn parse_f32(s: str) -> (f32, err) {
    // The non-finite spellings are exact tokens, not numbers, and the NaN handed back
    // is section 11's canonical quiet one rather than whatever an operation produced.
    if eq(s, "inf") { ret (mem.bitcast[f32](2139095040u32), ok) }
    if eq(s, "-inf") { ret (mem.bitcast[f32](4286578688u32), ok) }
    if eq(s, "nan") { ret (mem.bitcast[f32](2143289344u32), ok) }
    // 256 digits is past the longest exact tie this width has (113 of them),
    // so a tie always fits and a decimal that does not fit is never one: what
    // spills past the end can only be the sticky bit `truncated` carries.
    var digits: [256]u8 = zero
    var used = 0usize
    var truncated = false
    var negative = false
    var at = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        at = 1usize
    }
    // The grammar is the one the pushes write and nothing else: at least one digit,
    // at most one point with digits on both sides, no separators, no leading `+`, no
    // surrounding space, and a lowercase `e` exponent with at least one digit.
    var integer_digits = 0usize
    var fraction_digits = 0usize
    var leading_zeros = 0usize
    var started = false
    var in_fraction = false
    while at < s.len {
        let byte = s[at]
        if byte == 46u8 && !in_fraction && integer_digits > 0usize {
            in_fraction = true
            at += 1usize
            continue
        }
        if byte < 48u8 || byte > 57u8 { break }
        if in_fraction { fraction_digits += 1usize } else { integer_digits += 1usize }
        let digit = byte - 48u8
        if !started && digit == 0u8 {
            leading_zeros += 1usize
        } else {
            started = true
            if used < digits.len {
                digits[used] = digit
                used += 1usize
            } else {
                if digit != 0u8 { truncated = true }
            }
        }
        at += 1usize
    }
    if integer_digits == 0usize { ret (0.0f32, BadNumber) }
    if in_fraction && fraction_digits == 0usize { ret (0.0f32, BadNumber) }
    // `I.F` is `0.(I F) * 10^len(I)`, and every leading zero dropped takes one off it.
    var exponent = i64(integer_digits) - i64(leading_zeros)
    if at < s.len && s[at] == 101u8 {
        at += 1usize
        var exponent_negative = false
        if at < s.len && (s[at] == 43u8 || s[at] == 45u8) {
            exponent_negative = s[at] == 45u8
            at += 1usize
        }
        var magnitude = 0i64
        var exponent_digits = 0usize
        while at < s.len {
            let byte = s[at]
            if byte < 48u8 || byte > 57u8 { break }
            exponent_digits += 1usize
            // Past six digits the value is out of range either way, and the clamp is
            // what keeps the normalization below finite.
            if magnitude < 1000000i64 { magnitude = magnitude * 10i64 + i64(byte - 48u8) }
            at += 1usize
        }
        if exponent_digits == 0usize { ret (0.0f32, BadNumber) }
        if exponent_negative { exponent = exponent - magnitude } else { exponent = exponent + magnitude }
    }
    if at != s.len { ret (0.0f32, BadNumber) }
    while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    // An exact zero keeps its sign; it is the one zero a parse may return.
    if used == 0usize {
        var zero_pattern = 0u32
        if negative { zero_pattern = 2147483648u32 }
        ret (mem.bitcast[f32](zero_pattern), ok)
    }
    // Bounds that only keep the loops finite. Anything outside them is out of range by
    // a wide margin; anything inside is decided exactly below.
    if exponent > 60i64 || exponent < -60i64 { ret (0.0f32, BadNumber) }
    var binary_exponent = 0i64
    while true {
        if used == 0usize { break }
        // `0.digits * 10^exponent` with a leading digit of at least one lies in
        // `[0.1, 1)`, so both comparisons are on the exponent alone.
        var halving = false
        var doubling = false
        if exponent >= 1i64 {
            halving = true
        } else {
            if exponent < 0i64 {
                doubling = true
            } else {
                if digits[0usize] < 5u8 { doubling = true }
            }
        }
        if !halving && !doubling { break }
        if halving {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                if used < digits.len {
                    digits[used] = 5u8
                    used += 1usize
                } else {
                    truncated = true
                }
            }
            // The division can leave one leading zero, which belongs to the exponent.
            if digits[0usize] == 0u8 {
                var back = 0usize
                while back + 1usize < used {
                    digits[back] = digits[back + 1usize]
                    back += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            binary_exponent += 1i64
        } else {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                if used == digits.len {
                    if digits[used - 1usize] != 0u8 { truncated = true }
                } else {
                    used += 1usize
                }
                var back = used
                while back > 1usize {
                    back = back - 1usize
                    digits[back] = digits[back - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            binary_exponent = binary_exponent - 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // The value is `m * 2^binary_exponent` with `m` in `[0.5, 1)`, which fixes a
    // normal number's exponent field and leaves only the mantissa to read.
    var biased = binary_exponent - 1i64 + 127i64
    var bits = 24i64
    if biased < 1i64 {
        // Subnormal: the exponent field is pinned at zero and the mantissa loses one
        // bit for every step below the smallest normal. `bits` is the value's exponent
        // in units of that smallest subnormal, so a negative one is less than half of
        // it and rounds to a zero the input did not write.
        bits = 24i64 + biased - 1i64
        biased = 0i64
        if bits < 0i64 { ret (0.0f32, BadNumber) }
    }
    var shifted = 0i64
    while shifted < bits {
        var carry = 0u8
        var scan = used
        while scan > 0usize {
            scan = scan - 1usize
            let value = digits[scan] * 2u8 + carry
            digits[scan] = value % 10u8
            carry = value / 10u8
        }
        if carry != 0u8 {
            if used == digits.len {
                if digits[used - 1usize] != 0u8 { truncated = true }
            } else {
                used += 1usize
            }
            var back = used
            while back > 1usize {
                back = back - 1usize
                digits[back] = digits[back - 1usize]
            }
            digits[0usize] = carry
            exponent += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        shifted += 1i64
    }
    var mantissa = 0u32
    var taken = 0i64
    while taken < exponent {
        var digit = 0u8
        if usize(taken) < used { digit = digits[usize(taken)] }
        mantissa = mantissa * 10u32 + u32(digit)
        taken += 1i64
    }
    // Round to nearest, ties to even, on the digits the integer part left behind.
    var round_up = false
    if exponent >= 0i64 && usize(exponent) < used {
        let first = digits[usize(exponent)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = truncated
            var scan = usize(exponent) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                round_up = mantissa % 2u32 == 1u32
            }
        }
    }
    if round_up { mantissa += 1u32 }
    let implicit = 1u32 << 23u32
    if biased == 0i64 {
        // The carry out of a subnormal's mantissa is exactly the smallest normal.
        if mantissa >= implicit { biased = 1i64 }
    } else {
        if mantissa >= implicit * 2u32 {
            mantissa = mantissa / 2u32
            biased += 1i64
        }
    }
    if biased > 254i64 { ret (0.0f32, BadNumber) }
    var fraction = mantissa
    if biased >= 1i64 { fraction = mantissa - implicit }
    if biased == 0i64 && fraction == 0u32 { ret (0.0f32, BadNumber) }
    var pattern = u32(biased) << 23u32
    pattern = pattern + fraction
    if negative { pattern = pattern + 2147483648u32 }
    ret (mem.bitcast[f32](pattern), ok)
}

fn compare(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        if x[at] != y[at] {
            if x[at] < y[at] { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn compare_ascii_fold(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        var xb = x[at]
        var yb = y[at]
        if xb >= 65u8 && xb <= 90u8 { xb += 32u8 }
        if yb >= 65u8 && yb <= 90u8 { yb += 32u8 }
        if xb != yb {
            if xb < yb { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn starts_with(s: str, prefix: str) -> bool {
    if prefix.len > s.len { ret false }
    var at = 0usize
    while at < prefix.len {
        if s[at] != prefix[at] { ret false }
        at += 1usize
    }
    ret true
}

fn ends_with(s: str, suffix: str) -> bool {
    if suffix.len > s.len { ret false }
    let base = s.len - suffix.len
    var at = 0usize
    while at < suffix.len {
        if s[base + at] != suffix[at] { ret false }
        at += 1usize
    }
    ret true
}

fn contains(s: str, needle: str) -> bool {
    let (_, found) = find_from(s, needle, 0usize)
    ret found
}

fn find(s: str, needle: str) -> (usize, bool) {
    let (at, found) = find_from(s, needle, 0usize)
    ret (at, found)
}

// An empty needle matches at every boundary, so it is found at `start` itself as long
// as `start` is one. A `start` past the end is not a boundary and matches nothing.
fn find_from(s: str, needle: str, start: usize) -> (usize, bool) {
    if start > s.len { ret (0usize, false) }
    if needle.len == 0usize { ret (start, true) }
    if needle.len > s.len { ret (0usize, false) }
    let last = s.len - needle.len
    var at = start
    while at <= last {
        var k = 0usize
        var matched = true
        while k < needle.len {
            if s[at + k] != needle[k] {
                matched = false
                break
            }
            k += 1usize
        }
        if matched { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn rfind(s: str, needle: str) -> (usize, bool) {
    if needle.len == 0usize { ret (s.len, true) }
    if needle.len > s.len { ret (0usize, false) }
    var at = s.len - needle.len
    while true {
        var k = 0usize
        var matched = true
        while k < needle.len {
            if s[at + k] != needle[k] {
                matched = false
                break
            }
            k += 1usize
        }
        if matched { ret (at, true) }
        if at == 0usize { break }
        at -= 1usize
    }
    ret (0usize, false)
}

// Non-overlapping, so `count("aaa", "aa")` is 1. An empty needle sits at every
// boundary, which is one more than there are bytes.
fn count(s: str, needle: str) -> usize {
    if needle.len == 0usize { ret s.len + 1usize }
    var total = 0usize
    var at = 0usize
    while true {
        let (found_at, found) = find_from(s, needle, at)
        if !found { break }
        total += 1usize
        at = found_at + needle.len
    }
    ret total
}

fn trim(s: str) -> str {
    var at = 0usize
    while at < s.len && is_ascii_space(s[at]) { at += 1usize }
    var end = s.len
    while end > at && is_ascii_space(s[end - 1usize]) { end -= 1usize }
    ret s[at..end]
}

fn trim_start(s: str) -> str {
    var at = 0usize
    while at < s.len && is_ascii_space(s[at]) { at += 1usize }
    ret s[at..]
}

fn trim_end(s: str) -> str {
    var end = s.len
    while end > 0usize && is_ascii_space(s[end - 1usize]) { end -= 1usize }
    ret s[0usize..end]
}

fn trim_bytes(s: str, bytes: str) -> str {
    var at = 0usize
    while at < s.len {
        var head_hit = false
        var head_k = 0usize
        while head_k < bytes.len {
            if bytes[head_k] == s[at] {
                head_hit = true
                break
            }
            head_k += 1usize
        }
        if !head_hit { break }
        at += 1usize
    }
    var end = s.len
    while end > at {
        var tail_hit = false
        var tail_k = 0usize
        while tail_k < bytes.len {
            if bytes[tail_k] == s[end - 1usize] {
                tail_hit = true
                break
            }
            tail_k += 1usize
        }
        if !tail_hit { break }
        end -= 1usize
    }
    ret s[at..end]
}

fn split_once(s: str, separator: str) -> (str, str, bool) {
    let (at, found) = find_from(s, separator, 0usize)
    if !found { ret (s, "", false) }
    let head = s[0usize..at]
    let tail = s[at + separator.len..]
    ret (head, tail, true)
}

fn split(s: str, separator: str) -> (Split, err) {
    var it: Split = zero
    if separator.len == 0usize { ret (it, InvalidSeparator) }
    it.source = s
    it.separator = separator
    ret (it, ok)
}

fn split_next(it: *Split) -> (str, bool) {
    if it.finished { ret ("", false) }
    // Line mode, which only `lines` produces. The terminator is LF; a CR directly
    // before one goes with it; and the input's own trailing terminator ends the
    // traversal rather than opening a final empty line.
    if it.separator.len == 0usize {
        if it.off >= it.source.len {
            it.finished = true
            ret ("", false)
        }
        var scan = it.off
        while scan < it.source.len && it.source[scan] != 10u8 { scan += 1usize }
        var end = scan
        if scan < it.source.len && end > it.off && it.source[end - 1usize] == 13u8 { end -= 1usize }
        let line = it.source[it.off..end]
        it.off = scan + 1usize
        if scan == it.source.len {
            it.finished = true
            it.off = scan
        }
        ret (line, true)
    }
    let (at, found) = find_from(it.source, it.separator, it.off)
    if !found {
        let last = it.source[it.off..]
        it.off = it.source.len
        it.finished = true
        ret (last, true)
    }
    let field = it.source[it.off..at]
    it.off = at + it.separator.len
    ret (field, true)
}

fn lines(s: str) -> Split {
    var it: Split = zero
    it.source = s
    ret it
}

// Non-overlapping, on the same boundaries `count` reports: an empty needle puts the
// replacement at every one of them, which is between each pair of bytes and at both
// ends.
fn replace(a: *mem.Arena, s: str, needle: str, replacement: str) -> (str, err) {
    var (b, builder_error) = builder(a, s.len)
    if builder_error != ok { ret ("", builder_error) }
    if needle.len == 0usize {
        var boundary = 0usize
        while true {
            let empty_error = push(&b, replacement)
            if empty_error != ok { ret ("", empty_error) }
            if boundary == s.len { break }
            let byte_error = push_byte(&b, s[boundary])
            if byte_error != ok { ret ("", byte_error) }
            boundary += 1usize
        }
        let spread = done(&b)
        ret (spread, ok)
    }
    var at = 0usize
    while at < s.len {
        let (found_at, found) = find_from(s, needle, at)
        if !found { break }
        let head_error = push(&b, s[at..found_at])
        if head_error != ok { ret ("", head_error) }
        let replacement_error = push(&b, replacement)
        if replacement_error != ok { ret ("", replacement_error) }
        at = found_at + needle.len
    }
    let tail_error = push(&b, s[at..])
    if tail_error != ok { ret ("", tail_error) }
    let out = done(&b)
    ret (out, ok)
}

fn repeat(a: *mem.Arena, s: str, repeat_count: usize) -> (str, err) {
    var (b, builder_error) = builder(a, s.len * repeat_count)
    if builder_error != ok { ret ("", builder_error) }
    var at = 0usize
    while at < repeat_count {
        let push_error = push(&b, s)
        if push_error != ok { ret ("", push_error) }
        at += 1usize
    }
    let out = done(&b)
    ret (out, ok)
}

fn ascii_lower_in_place(s: []u8) {
    var at = 0usize
    while at < s.len {
        if s[at] >= 65u8 && s[at] <= 90u8 { s[at] += 32u8 }
        at += 1usize
    }
}

fn ascii_upper_in_place(s: []u8) {
    var at = 0usize
    while at < s.len {
        if s[at] >= 97u8 && s[at] <= 122u8 { s[at] -= 32u8 }
        at += 1usize
    }
}

fn is_ascii_space(b: u8) -> bool {
    ret b == 32u8 || (b >= 9u8 && b <= 13u8)
}

fn is_ascii_digit(b: u8) -> bool {
    ret b >= 48u8 && b <= 57u8
}

fn is_ascii_alpha(b: u8) -> bool {
    if b >= 65u8 && b <= 90u8 { ret true }
    ret b >= 97u8 && b <= 122u8
}

fn is_ascii_alnum(b: u8) -> bool {
    ret is_ascii_digit(b) || is_ascii_alpha(b)
}

// --- Padding to a width counted in UTF-8 code points (#356).

type Side = enum u8 { Left, Right, Center }

// Code points in `s`: every byte that is not a continuation byte.
fn count_points(s: str) -> usize {
    var n = 0usize
    var at = 0usize
    while at < s.len {
        if (s[at] & 192u8) != 128u8 { n += 1usize }
        at += 1usize
    }
    ret n
}

fn push_repeated(b: *Builder, fill: str, times: usize) -> err {
    var at = 0usize
    while at < times {
        let push_error = push(b, fill)
        if push_error != ok { ret push_error }
        at += 1usize
    }
    ret ok
}

// `s` padded with copies of `fill` (one code point, any width in bytes) to
// `width` code points on `side`; a string already that wide comes back as it
// is. `Center` puts the odd extra copy on the right. An empty `fill` is
// `InvalidSeparator`.
fn pad(a: *mem.Arena, s: str, width: usize, side: Side, fill: str) -> (str, err) {
    if fill.len == 0usize { ret ("", InvalidSeparator) }
    let have = count_points(s)
    if have >= width { ret (s, ok) }
    let extra = width - have
    var before = 0usize
    if side == .Left { before = extra }
    if side == .Center { before = extra / 2usize }
    let after = extra - before
    var (b, builder_error) = builder(a, s.len + extra * fill.len)
    if builder_error != ok { ret ("", builder_error) }
    let before_error = push_repeated(&b, fill, before)
    if before_error != ok { ret ("", before_error) }
    let push_error = push(&b, s)
    if push_error != ok { ret ("", push_error) }
    let after_error = push_repeated(&b, fill, after)
    if after_error != ok { ret ("", after_error) }
    let out = done(&b)
    ret (out, ok)
}

fn pad_left(a: *mem.Arena, s: str, width: usize, fill: str) -> (str, err) {
    let (out, pad_error) = pad(a, s, width, .Left, fill)
    ret (out, pad_error)
}

fn pad_right(a: *mem.Arena, s: str, width: usize, fill: str) -> (str, err) {
    let (out, pad_error) = pad(a, s, width, .Right, fill)
    ret (out, pad_error)
}

fn pad_center(a: *mem.Arena, s: str, width: usize, fill: str) -> (str, err) {
    let (out, pad_error) = pad(a, s, width, .Center, fill)
    ret (out, pad_error)
}
