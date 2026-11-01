// The AV1 symbol (range) decoder of the specification, section 8.2: init_symbol, read_symbol (with the adaptive CDF
// update), read_bool and read_literal. A CDF is a slice of N+1 u16: N cumulative values scaled to 32768 and the adaptation
// counter last, the layout of e.fmt.av1_cdf.

type Sym = struct {
    d: []const u8,
    pos: usize,
    value: u32,
    range: u32,
    max_bits: i32,
    adapt: bool,
}

// the next n bits (n <= 15) of the tile data, zero past its end; `max_bits` bounds the count actually available
fn take(s: *Sym, n: u32) -> u32 {
    var x = 0u32
    var i = 0u32
    while i < n {
        var bit = 0u32
        let byte = s.pos >> 3usize
        if byte < s.d.len { bit = (u32(s.d[byte]) >> (7u32 - u32(s.pos & 7usize))) & 1u32 }
        s.pos += 1usize
        x = (x << 1u32) | bit
        i += 1u32
    }
    ret x
}

fn floor_log2(x: u32) -> u32 {
    var s = 0u32
    var v = x
    while v > 1u32 {
        v = v >> 1u32
        s += 1u32
    }
    ret s
}

// `d` is the tile data; `disable_cdf_update` is the frame header flag
fn init_symbol(d: []const u8, disable_cdf_update: bool) -> Sym {
    var s = Sym { d: d, pos: 0usize, value: 0u32, range: 32768u32, max_bits: 0i32, adapt: !disable_cdf_update }
    var num_bits = 15u32
    if d.len * 8usize < 15usize { num_bits = u32(d.len * 8usize) }
    let buf = take(&s, num_bits)
    let padded = buf << (15u32 - num_bits)
    s.value = 32767u32 ^ padded
    s.max_bits = i32(d.len * 8usize) - 15i32
    ret s
}

fn read_symbol(s: *Sym, cdf: []u16, n: usize) -> usize {
    var cur = s.range
    var prev = cur
    var symbol = 0usize
    var first = true
    while first || s.value < cur {
        first = false
        prev = cur
        let fv = 32768u32 - u32(cdf[symbol])
        cur = (((s.range >> 8u32) * (fv >> 6u32)) >> 1u32) + 4u32 * u32(n - symbol - 1usize)
        symbol += 1usize
    }
    symbol -= 1usize
    s.range = prev - cur
    s.value = s.value - cur
    let bits = 15u32 - floor_log2(s.range)
    s.range = s.range << bits
    var num_bits = i32(bits)
    if s.max_bits < num_bits { num_bits = s.max_bits }
    if num_bits < 0i32 { num_bits = 0i32 }
    let new_data = take(s, u32(num_bits))
    let padded = new_data << (bits - u32(num_bits))
    s.value = padded ^ (((s.value + 1u32) << bits) - 1u32)
    s.max_bits -= i32(bits)
    if s.adapt {
        var rate = 3u32
        if cdf[n] > 15u16 { rate += 1u32 }
        if cdf[n] > 31u16 { rate += 1u32 }
        var lg = floor_log2(u32(n))
        if lg > 2u32 { lg = 2u32 }
        rate += lg
        var tmp = 0u32
        var i = 0usize
        while i + 1usize < n {
            if i == symbol { tmp = 32768u32 }
            let c = u32(cdf[i])
            if tmp < c { cdf[i] = u16(c - ((c - tmp) >> rate)) } else { cdf[i] = u16(c + ((tmp - c) >> rate)) }
            i += 1usize
        }
        if cdf[n] < 32u16 { cdf[n] += 1u16 }
    }
    ret symbol
}

fn read_bool(s: *Sym) -> u32 {
    var cdf: [3]u16 = zero
    cdf[0usize] = 16384u16
    cdf[1usize] = 32768u16
    let saved = s.adapt
    s.adapt = false
    let v = read_symbol(s, cdf[..], 2usize)
    s.adapt = saved
    ret u32(v)
}

fn read_literal(s: *Sym, n: u32) -> u32 {
    var x = 0u32
    var i = 0u32
    while i < n {
        x = 2u32 * x + read_bool(s)
        i += 1u32
    }
    ret x
}
