// The AV1 symbol (range) decoder of the specification, section 8.2: init_symbol, read_symbol (with the adaptive CDF
// update), read_bool and read_literal. A CDF is a slice of N+1 u16: N cumulative values scaled to 32768 and the adaptation
// counter last, the layout of e.fmt.av1_cdf.
//
// SymbolValue is kept in the top 16 bits of the 64-bit window `dif`; the bits below it are the next `cnt` bits of the data,
// already inverted, so renormalisation is a shift of the whole window. Past the end of the data the stream reads as zero
// bits, which is what the specification's SymbolMaxBits padding amounts to.

type Sym = struct {
    d: []const u8,
    pos: usize,
    dif: u64,
    range: u32,
    cnt: i32,
    adapt: bool,
}

fn refill(s: *Sym) {
    var cnt = s.cnt
    var dif = s.dif
    var pos = s.pos
    let n = s.d.len
    while cnt <= 40i32 {
        var b = 255u64
        if pos < n {
            b = u64(s.d[pos]) ^ 255u64
            pos += 1usize
        }
        dif = dif | (b << u32(40i32 - cnt))
        cnt += 8i32
    }
    s.cnt = cnt
    s.dif = dif
    s.pos = pos
}

// the shift that brings a range (1 to 65535) back to at least 32768
fn norm_bits(r: u32) -> u32 {
    var b = 0u32
    var x = r
    if x < 256u32 {
        x = x << 8u32
        b = 8u32
    }
    if x < 4096u32 {
        x = x << 4u32
        b += 4u32
    }
    if x < 16384u32 {
        x = x << 2u32
        b += 2u32
    }
    if x < 32768u32 { b += 1u32 }
    ret b
}

// `d` is the tile data; `disable_cdf_update` is the frame header flag
fn init_symbol(d: []const u8, disable_cdf_update: bool) -> Sym {
    var s = Sym { d: d, pos: 0usize, dif: 0u64, range: 32768u32, cnt: -15i32, adapt: !disable_cdf_update }
    refill(&s)
    ret s
}

fn read_symbol(s: *Sym, cdf: []u16, n: usize) -> usize {
    if n == 0usize || cdf.len < n + 1usize { ret 0usize }
    if s.cnt < 16i32 { refill(s) }
    let v = u32(s.dif >> 48u32)
    let r8 = s.range >> 8u32
    var prev = s.range
    var cur = 0u32
    var symbol = 0usize
    let last = n - 1usize
    @nocheck {
        if n == 2usize {
            let c = ((r8 * ((32768u32 - u32(cdf[0usize])) >> 6u32)) >> 1u32) + 4u32
            if v >= c {
                cur = c
            } else {
                prev = c
                symbol = 1usize
            }
        } else {
            while symbol < last {
                let c = ((r8 * ((32768u32 - u32(cdf[symbol])) >> 6u32)) >> 1u32) + 4u32 * u32(last - symbol)
                if v >= c {
                    cur = c
                    break
                }
                prev = c
                symbol += 1usize
            }
        }
    }
    let range = prev - cur
    let bits = norm_bits(range)
    s.range = range << bits
    s.dif = (s.dif - (u64(cur) << 48u32)) << bits
    s.cnt -= i32(bits)
    if s.adapt {
        @nocheck {
            let cn = cdf[n]
            var rate = 4u32
            if n > 3usize { rate = 5u32 }
            if cn > 15u16 { rate += 1u32 }
            if cn > 31u16 { rate += 1u32 }
            var i = 0usize
            while i < symbol {
                let c = u32(cdf[i])
                cdf[i] = u16(c - (c >> rate))
                i += 1usize
            }
            while i < last {
                let c = u32(cdf[i])
                cdf[i] = u16(c + ((32768u32 - c) >> rate))
                i += 1usize
            }
            if cn < 32u16 { cdf[n] = cn + 1u16 }
        }
    }
    ret symbol
}

fn read_bool(s: *Sym) -> u32 {
    if s.cnt < 16i32 { refill(s) }
    let v = u32(s.dif >> 48u32)
    let cur = ((s.range >> 8u32) << 7u32) + 4u32
    var range = cur
    var dif = s.dif
    var bit = 1u32
    if v >= cur {
        range = s.range - cur
        dif = dif - (u64(cur) << 48u32)
        bit = 0u32
    }
    let bits = norm_bits(range)
    s.range = range << bits
    s.dif = dif << bits
    s.cnt -= i32(bits)
    ret bit
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
