// SpookyHash V2 (Bob Jenkins, public domain), the 128-bit hash in one call: `spooky128` answers
// the pair (h1, h2) the reference gives for the message and two 64-bit seeds, below and above
// the 192-byte threshold where it changes from the short form to twelve-word blocks.
//
// R's digest hashes the serialized bytes of an R object through the streaming form, then
// prints h1 and h2 as 16 little-endian bytes. The streaming form is defined to equal this
// one-shot form over the concatenated bytes, and the oracle fixture holds it to that.

type Pair = struct { h1: u64, h2: u64 }

const SC_CONST: u64 = 16045690984833335023u64

fn rot(x: u64, k: u64) -> u64 { ret (x << k) | (x >> (64u64 - k)) }

fn word(d: []const u8, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = v | (u64(d[at + i]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

// The little-endian value of the `count` bytes at `at`, which is what the reference's
// shifted adds for a 1-15 byte tail make.
fn partial(d: []const u8, at: usize, count: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < count {
        v = v | (u64(d[at + i]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

fn short_mix(h: []u64) {
    let xs = [12]usize { 2usize, 3usize, 0usize, 1usize, 2usize, 3usize, 0usize, 1usize, 2usize, 3usize, 0usize, 1usize }
    let rs = [12]u64 { 50u64, 52u64, 30u64, 41u64, 54u64, 48u64, 38u64, 37u64, 62u64, 34u64, 5u64, 36u64 }
    var i = 0usize
    while i < 12usize {
        let x = xs[i]
        let y = (x + 1usize) % 4usize
        let z = (x + 2usize) % 4usize
        h[x] = rot(h[x], rs[i])
        h[x] = h[x] +% h[y]
        h[z] = h[z] ^ h[x]
        i += 1usize
    }
}

fn short_end(h: []u64) {
    let xs = [11]usize { 3usize, 0usize, 1usize, 2usize, 3usize, 0usize, 1usize, 2usize, 3usize, 0usize, 1usize }
    let rs = [11]u64 { 15u64, 52u64, 26u64, 51u64, 28u64, 9u64, 47u64, 54u64, 32u64, 25u64, 63u64 }
    var i = 0usize
    while i < 11usize {
        let a = xs[i]
        let b = (a + 3usize) % 4usize
        h[a] = h[a] ^ h[b]
        h[b] = rot(h[b], rs[i])
        h[a] = h[a] +% h[b]
        i += 1usize
    }
}

fn short(d: []const u8, seed1: u64, seed2: u64) -> Pair {
    var h: [4]u64 = zero
    let s = h[0usize..4usize]
    s[0usize] = seed1
    s[1usize] = seed2
    s[2usize] = SC_CONST
    s[3usize] = SC_CONST
    var at = 0usize
    var remainder = d.len % 32usize
    if d.len > 15usize {
        let end = (d.len / 32usize) * 32usize
        while at < end {
            s[2usize] = s[2usize] +% word(d, at)
            s[3usize] = s[3usize] +% word(d, at + 8usize)
            short_mix(s)
            s[0usize] = s[0usize] +% word(d, at + 16usize)
            s[1usize] = s[1usize] +% word(d, at + 24usize)
            at += 32usize
        }
        if remainder >= 16usize {
            s[2usize] = s[2usize] +% word(d, at)
            s[3usize] = s[3usize] +% word(d, at + 8usize)
            short_mix(s)
            at += 16usize
            remainder -= 16usize
        }
    }
    s[3usize] = s[3usize] +% (u64(d.len) << 56u64)
    if remainder == 0usize {
        s[2usize] = s[2usize] +% SC_CONST
        s[3usize] = s[3usize] +% SC_CONST
    } else {
        var low = remainder
        if low > 8usize { low = 8usize }
        s[2usize] = s[2usize] +% partial(d, at, low)
        if remainder > 8usize { s[3usize] = s[3usize] +% partial(d, at + 8usize, remainder - 8usize) }
    }
    short_end(s)
    ret Pair { h1: s[0usize], h2: s[1usize] }
}

fn mix(s: []u64, d: []const u8, at: usize) {
    let rs = [12]u64 { 11u64, 32u64, 43u64, 31u64, 17u64, 28u64, 39u64, 57u64, 55u64, 54u64, 22u64, 46u64 }
    var i = 0usize
    while i < 12usize {
        s[i] = s[i] +% word(d, at + 8usize * i)
        s[(i + 2usize) % 12usize] = s[(i + 2usize) % 12usize] ^ s[(i + 10usize) % 12usize]
        s[(i + 11usize) % 12usize] = s[(i + 11usize) % 12usize] ^ s[i]
        s[i] = rot(s[i], rs[i])
        s[(i + 11usize) % 12usize] = s[(i + 11usize) % 12usize] +% s[(i + 1usize) % 12usize]
        i += 1usize
    }
}

fn end_partial(h: []u64) {
    let rs = [12]u64 { 44u64, 15u64, 34u64, 21u64, 38u64, 33u64, 10u64, 13u64, 38u64, 53u64, 42u64, 54u64 }
    var j = 0usize
    while j < 12usize {
        let a = (j + 11usize) % 12usize
        let b = (j + 1usize) % 12usize
        let c = (j + 2usize) % 12usize
        h[a] = h[a] +% h[b]
        h[c] = h[c] ^ h[a]
        h[b] = rot(h[b], rs[j])
        j += 1usize
    }
}

fn spooky128(data: []const u8, seed1: u64, seed2: u64) -> Pair {
    if data.len < 192usize { ret short(data, seed1, seed2) }
    var state: [12]u64 = zero
    let h = state[0usize..12usize]
    var i = 0usize
    while i < 12usize {
        if i % 3usize == 0usize { h[i] = seed1 }
        if i % 3usize == 1usize { h[i] = seed2 }
        if i % 3usize == 2usize { h[i] = SC_CONST }
        i += 1usize
    }
    let blocks = data.len / 96usize
    var at = 0usize
    var b = 0usize
    while b < blocks {
        mix(h, data, at)
        at += 96usize
        b += 1usize
    }
    let remainder = data.len - at
    var tail: [96]u8 = zero
    let t = tail[0usize..96usize]
    var k = 0usize
    while k < remainder {
        t[k] = data[at + k]
        k += 1usize
    }
    t[95usize] = u8(remainder)
    i = 0usize
    while i < 12usize {
        h[i] = h[i] +% word(t, 8usize * i)
        i += 1usize
    }
    end_partial(h)
    end_partial(h)
    end_partial(h)
    ret Pair { h1: h[0usize], h2: h[1usize] }
}
