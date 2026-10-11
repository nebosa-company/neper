// Barcodes (C121, L137): QR Code encode and decode, Code 128 and EAN-13 encode.
//
// QR Code (ISO/IEC 18004) versions 1 to 10 (21 x 21 to 57 x 57 modules, up to 271 bytes at level L), byte mode
// on the way in, byte, alphanumeric and numeric modes on the way out, the four error-correction levels
// (0 L, 1 M, 2 Q, 3 H) and the eight masks. `qr_encode` picks the smallest version and the mask with the lowest
// penalty; `qr_encode_with` takes the mask (0 to 7) when a caller needs a given one. `qr_decode` reads a module
// matrix (a symbol already found and sampled): the format word is matched to its nearest of the 32 valid words,
// the codewords are unmasked, each block is corrected by Reed-Solomon (Berlekamp-Massey, Chien search, Forney) and
// the segments are read. A bit pattern more damaged than the code can correct is `Uncorrectable`.
//
// Code 128 (set B for text in 32..126, set C for an even run of digits) and EAN-13 (twelve digits and the check
// digit, or all thirteen with the check digit verified) come out as a row of modules, 1 for a bar.
//
// Memory: every result lives in the arena passed in. A `Matrix` is `size` x `size` bytes, 1 for dark.
use e.mem

error TooLong
error Invalid
error Uncorrectable

type Matrix = struct { size: usize, modules: []u8 }

type Gf = struct { exp: [512]u8, log: [256]u8 }

type BitBuf = struct { data: []u8, pos: usize }

type Work = struct { size: usize, dark: []u8, fixed: []u8 }

const MAX_VERSION: usize = 10usize

// For versions 1 to 10 at levels L, M, Q, H (four bytes each): error-correction codewords per block, blocks of
// the first size, data codewords of that size, blocks with one more data codeword.
fn blocks_table() -> str { ret "\x08\x02\x14\x01\x0b\x02\x11\x01\x0e\x02\x0e\x01\x12\x02\x0a\x01\x0b\x02\x23\x01\x11\x02\x1d\x01\x17\x02\x17\x01\x1d\x02\x11\x01\x10\x02\x38\x01\x1b\x02\x2d\x01\x13\x03\x12\x01\x17\x03\x0e\x01\x15\x02\x51\x01\x13\x03\x21\x01\x1b\x03\x19\x01\x11\x05\x0a\x01\x1b\x02\x6d\x01\x19\x03\x2c\x01\x13\x03\x10\x03\x17\x03\x0c\x03\x13\x03\x45\x01\x11\x05\x1c\x01\x19\x05\x14\x01\x1d\x05\x10\x01\x15\x03\x4f\x01\x13\x05\x20\x01\x13\x03\x0f\x05\x1b\x05\x0e\x02\x19\x03\x62\x01\x17\x03\x27\x03\x17\x05\x13\x03\x1b\x05\x0f\x03\x1f\x03\x75\x01\x17\x04\x25\x03\x15\x05\x11\x05\x19\x05\x0d\x05\x13\x03\x45\x03\x1b\x05\x2c\x02\x19\x07\x14\x03\x1d\x07\x10\x03" }

fn block_field(v: usize, ecl: usize, field: usize) -> usize {
    let table = blocks_table()
    ret usize(table[((v - 1usize) * 4usize + ecl) * 4usize + field]) - 1usize
}

fn raw_codewords(v: usize) -> usize {
    var raw = (16usize * v + 128usize) * v + 64usize
    if v >= 2usize {
        let n = v / 7usize + 2usize
        raw -= (25usize * n - 10usize) * n - 55usize
        if v >= 7usize { raw -= 36usize }
    }
    ret raw / 8usize
}

fn data_codewords(v: usize, ecl: usize) -> usize {
    let d1 = block_field(v, ecl, 2usize)
    ret block_field(v, ecl, 1usize) * d1 + block_field(v, ecl, 3usize) * (d1 + 1usize)
}

// ---- Galois field and Reed-Solomon ------------------------------------------------------------

fn gf_init(g: *Gf) {
    var x = 1usize
    var i = 0usize
    while i < 255usize {
        g.exp[i] = u8(x)
        g.log[x] = u8(i)
        x = x << 1usize
        if x >= 256usize { x = x ^ 285usize }
        i += 1usize
    }
    i = 255usize
    while i < 512usize {
        g.exp[i] = g.exp[i - 255usize]
        i += 1usize
    }
}

fn gf_mul(g: *Gf, x: usize, y: usize) -> usize {
    if x == 0usize || y == 0usize { ret 0usize }
    ret usize(g.exp[usize(g.log[x]) + usize(g.log[y])])
}

fn gf_div(g: *Gf, x: usize, y: usize) -> usize {
    if x == 0usize { ret 0usize }
    ret usize(g.exp[usize(g.log[x]) + 255usize - usize(g.log[y])])
}

// The divisor of degree `degree` (monic, leading coefficient left out) with roots 1, 2, 4, ...
fn rs_divisor(g: *Gf, degree: usize, out: []u8) {
    var i = 0usize
    while i < degree {
        out[i] = 0u8
        i += 1usize
    }
    out[degree - 1usize] = 1u8
    var root = 1usize
    i = 0usize
    while i < degree {
        var j = 0usize
        while j < degree {
            out[j] = u8(gf_mul(g, usize(out[j]), root))
            if j + 1usize < degree { out[j] = out[j] ^ out[j + 1usize] }
            j += 1usize
        }
        root = gf_mul(g, root, 2usize)
        i += 1usize
    }
}

// The remainder of `data` x^degree divided by the divisor, into `out[0..degree]`.
fn rs_remainder(g: *Gf, data: []const u8, divisor: []const u8, degree: usize, out: []u8) {
    var i = 0usize
    while i < degree {
        out[i] = 0u8
        i += 1usize
    }
    var k = 0usize
    while k < data.len {
        let factor = usize(data[k]) ^ usize(out[0usize])
        i = 0usize
        while i + 1usize < degree {
            out[i] = out[i + 1usize]
            i += 1usize
        }
        out[degree - 1usize] = 0u8
        i = 0usize
        while i < degree {
            out[i] = out[i] ^ u8(gf_mul(g, usize(divisor[i]), factor))
            i += 1usize
        }
        k += 1usize
    }
}

// Corrects `block` (n codewords, the last `nsym` error correction) in place. False when it cannot.
fn rs_correct(g: *Gf, block: []u8, n: usize, nsym: usize) -> bool {
    var synd: [32]u8 = zero
    var any = false
    var j = 0usize
    while j < nsym {
        var s = 0usize
        var i = 0usize
        while i < n {
            s = gf_mul(g, s, usize(g.exp[j])) ^ usize(block[i])
            i += 1usize
        }
        synd[j] = u8(s)
        if s != 0usize { any = true }
        j += 1usize
    }
    if !any { ret true }
    // Berlekamp-Massey. Polynomials are stored lowest degree first.
    var loc: [33]u8 = zero
    var prev: [33]u8 = zero
    var tmp: [33]u8 = zero
    loc[0usize] = 1u8
    prev[0usize] = 1u8
    var loc_len = 1usize
    var prev_len = 1usize
    var shift = 1usize
    var last_delta = 1usize
    var step = 0usize
    while step < nsym {
        var delta = usize(synd[step])
        var i = 1usize
        while i < loc_len {
            delta = delta ^ gf_mul(g, usize(loc[i]), usize(synd[step - i]))
            i += 1usize
        }
        if delta == 0usize {
            shift += 1usize
        } else {
            let factor = gf_div(g, delta, last_delta)
            // tmp = loc - factor x^shift prev
            var t = 0usize
            while t < 33usize {
                tmp[t] = loc[t]
                t += 1usize
            }
            var tmp_len = loc_len
            i = 0usize
            while i < prev_len {
                if i + shift < 33usize {
                    tmp[i + shift] = tmp[i + shift] ^ u8(gf_mul(g, factor, usize(prev[i])))
                    if i + shift + 1usize > tmp_len { tmp_len = i + shift + 1usize }
                }
                i += 1usize
            }
            if 2usize * (loc_len - 1usize) <= step {
                t = 0usize
                while t < 33usize {
                    prev[t] = loc[t]
                    t += 1usize
                }
                prev_len = loc_len
                last_delta = delta
                shift = 1usize
            } else {
                shift += 1usize
            }
            t = 0usize
            while t < 33usize {
                loc[t] = tmp[t]
                t += 1usize
            }
            loc_len = tmp_len
        }
        step += 1usize
    }
    while loc_len > 1usize && loc[loc_len - 1usize] == 0u8 { loc_len -= 1usize }
    let errors = loc_len - 1usize
    if errors * 2usize > nsym { ret false }
    // Chien search: the position p (0 is the first codeword) is in error when loc(alpha^-(n-1-p)) = 0.
    var found = 0usize
    var positions: [32]usize = zero
    var p = 0usize
    while p < n {
        let power = n - 1usize - p
        // x = alpha^(255 - power)
        var x_log = (255usize - power % 255usize) % 255usize
        var value = 0usize
        var d = 0usize
        while d < loc_len {
            value = value ^ gf_mul(g, usize(loc[d]), usize(g.exp[(x_log * d) % 255usize]))
            d += 1usize
        }
        if value == 0usize {
            if found >= 32usize { ret false }
            positions[found] = p
            found += 1usize
        }
        p += 1usize
    }
    if found != errors { ret false }
    // Forney: omega = synd(x) loc(x) mod x^nsym; magnitude = x^1 omega(x^-1) / loc'(x^-1) with x = alpha^power.
    var omega: [32]u8 = zero
    var a = 0usize
    while a < nsym {
        var acc = 0usize
        var b = 0usize
        while b < loc_len && b <= a {
            acc = acc ^ gf_mul(g, usize(loc[b]), usize(synd[a - b]))
            b += 1usize
        }
        omega[a] = u8(acc)
        a += 1usize
    }
    var e = 0usize
    while e < found {
        let power = n - 1usize - positions[e]
        let inv_log = (255usize - power % 255usize) % 255usize
        var num = 0usize
        var d = 0usize
        while d < nsym {
            num = num ^ gf_mul(g, usize(omega[d]), usize(g.exp[(inv_log * d) % 255usize]))
            d += 1usize
        }
        // The formal derivative keeps the odd-degree terms.
        var den = 0usize
        d = 1usize
        while d < loc_len {
            if d % 2usize == 1usize {
                den = den ^ gf_mul(g, usize(loc[d]), usize(g.exp[(inv_log * (d - 1usize)) % 255usize]))
            }
            d += 1usize
        }
        if den == 0usize { ret false }
        let magnitude = gf_mul(g, usize(g.exp[power % 255usize]), gf_div(g, num, den))
        block[positions[e]] = block[positions[e]] ^ u8(magnitude)
        e += 1usize
    }
    // The corrected block has to check out.
    j = 0usize
    while j < nsym {
        var s2 = 0usize
        var i2 = 0usize
        while i2 < n {
            s2 = gf_mul(g, s2, usize(g.exp[j])) ^ usize(block[i2])
            i2 += 1usize
        }
        if s2 != 0usize { ret false }
        j += 1usize
    }
    ret true
}

// ---- QR: function patterns --------------------------------------------------------------------

fn fixed_set(w: *Work, x: usize, y: usize, is_dark: bool) {
    var v = 0u8
    if is_dark { v = 1u8 }
    w.dark[y * w.size + x] = v
    w.fixed[y * w.size + x] = 1u8
}

fn finder(w: *Work, cx: usize, cy: usize) {
    var dy = 0usize
    while dy < 9usize {
        var dx = 0usize
        while dx < 9usize {
            // The offsets run from -4 to 4; position them from the top left of the 9 x 9 block.
            let x = cx + dx
            let y = cy + dy
            if x >= 4usize && y >= 4usize && x - 4usize < w.size && y - 4usize < w.size {
                var ax = dx
                if ax >= 4usize { ax = dx - 4usize } else { ax = 4usize - dx }
                var ay = dy
                if ay >= 4usize { ay = dy - 4usize } else { ay = 4usize - dy }
                var dist = ax
                if ay > dist { dist = ay }
                fixed_set(w, x - 4usize, y - 4usize, dist != 2usize && dist != 4usize)
            }
            dx += 1usize
        }
        dy += 1usize
    }
}

fn alignment(w: *Work, cx: usize, cy: usize) {
    var dy = 0usize
    while dy < 5usize {
        var dx = 0usize
        while dx < 5usize {
            var ax = 0usize
            if dx >= 2usize { ax = dx - 2usize } else { ax = 2usize - dx }
            var ay = 0usize
            if dy >= 2usize { ay = dy - 2usize } else { ay = 2usize - dy }
            var dist = ax
            if ay > dist { dist = ay }
            fixed_set(w, cx + dx - 2usize, cy + dy - 2usize, dist != 1usize)
            dx += 1usize
        }
        dy += 1usize
    }
}

fn alignment_positions(v: usize, out: []usize) -> usize {
    if v == 1usize { ret 0usize }
    out[0usize] = 6usize
    if v == 2usize {
        out[1usize] = 18usize
        ret 2usize
    }
    if v == 3usize {
        out[1usize] = 22usize
        ret 2usize
    }
    if v == 4usize {
        out[1usize] = 26usize
        ret 2usize
    }
    if v == 5usize {
        out[1usize] = 30usize
        ret 2usize
    }
    if v == 6usize {
        out[1usize] = 34usize
        ret 2usize
    }
    out[2usize] = 38usize
    out[1usize] = 22usize
    if v == 8usize {
        out[1usize] = 24usize
        out[2usize] = 42usize
    }
    if v == 9usize {
        out[1usize] = 26usize
        out[2usize] = 46usize
    }
    if v == 10usize {
        out[1usize] = 28usize
        out[2usize] = 50usize
    }
    ret 3usize
}

fn format_bits(ecl: usize) -> usize {
    if ecl == 0usize { ret 1usize }
    if ecl == 1usize { ret 0usize }
    if ecl == 2usize { ret 3usize }
    ret 2usize
}

fn format_word(ecl: usize, mask: usize) -> usize {
    let value = (format_bits(ecl) << 3usize) | mask
    var rem = value
    var i = 0usize
    while i < 10usize {
        rem = (rem << 1usize) ^ ((rem >> 9usize) * 1335usize)
        i += 1usize
    }
    ret ((value << 10usize) | rem) ^ 21522usize
}

fn version_word(v: usize) -> usize {
    var rem = v
    var i = 0usize
    while i < 12usize {
        rem = (rem << 1usize) ^ ((rem >> 11usize) * 7973usize)
        i += 1usize
    }
    ret (v << 12usize) | rem
}

fn bit_of(value: usize, i: usize) -> bool { ret ((value >> i) & 1usize) == 1usize }

fn draw_format(w: *Work, ecl: usize, mask: usize) {
    let bits = format_word(ecl, mask)
    let n = w.size
    var i = 0usize
    while i <= 5usize {
        fixed_set(w, 8usize, i, bit_of(bits, i))
        i += 1usize
    }
    fixed_set(w, 8usize, 7usize, bit_of(bits, 6usize))
    fixed_set(w, 8usize, 8usize, bit_of(bits, 7usize))
    fixed_set(w, 7usize, 8usize, bit_of(bits, 8usize))
    i = 9usize
    while i < 15usize {
        fixed_set(w, 14usize - i, 8usize, bit_of(bits, i))
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        fixed_set(w, n - 1usize - i, 8usize, bit_of(bits, i))
        i += 1usize
    }
    i = 8usize
    while i < 15usize {
        fixed_set(w, 8usize, n - 15usize + i, bit_of(bits, i))
        i += 1usize
    }
    fixed_set(w, 8usize, n - 8usize, true)
}

fn draw_function(w: *Work, v: usize) {
    let n = w.size
    var i = 0usize
    while i < n {
        fixed_set(w, 6usize, i, i % 2usize == 0usize)
        fixed_set(w, i, 6usize, i % 2usize == 0usize)
        i += 1usize
    }
    finder(w, 3usize, 3usize)
    finder(w, n - 4usize, 3usize)
    finder(w, 3usize, n - 4usize)
    var pos: [3]usize = zero
    let count = alignment_positions(v, pos[0usize..3usize])
    i = 0usize
    while i < count {
        var j = 0usize
        while j < count {
            let corner = (i == 0usize && j == 0usize) || (i == 0usize && j == count - 1usize) || (i == count - 1usize && j == 0usize)
            if !corner { alignment(w, pos[i], pos[j]) }
            j += 1usize
        }
        i += 1usize
    }
    draw_format(w, 0usize, 0usize)
    if v >= 7usize {
        let bits = version_word(v)
        i = 0usize
        while i < 18usize {
            let a = n - 11usize + i % 3usize
            let b = i / 3usize
            fixed_set(w, a, b, bit_of(bits, i))
            fixed_set(w, b, a, bit_of(bits, i))
            i += 1usize
        }
    }
}

fn mask_hit(mask: usize, x: usize, y: usize) -> bool {
    if mask == 0usize { ret (x + y) % 2usize == 0usize }
    if mask == 1usize { ret y % 2usize == 0usize }
    if mask == 2usize { ret x % 3usize == 0usize }
    if mask == 3usize { ret (x + y) % 3usize == 0usize }
    if mask == 4usize { ret (x / 3usize + y / 2usize) % 2usize == 0usize }
    if mask == 5usize { ret x * y % 2usize + x * y % 3usize == 0usize }
    if mask == 6usize { ret (x * y % 2usize + x * y % 3usize) % 2usize == 0usize }
    ret ((x + y) % 2usize + x * y % 3usize) % 2usize == 0usize
}

fn apply_mask(w: *Work, mask: usize) {
    var y = 0usize
    while y < w.size {
        var x = 0usize
        while x < w.size {
            if w.fixed[y * w.size + x] == 0u8 && mask_hit(mask, x, y) {
                w.dark[y * w.size + x] = w.dark[y * w.size + x] ^ 1u8
            }
            x += 1usize
        }
        y += 1usize
    }
}

// Visit the data modules in the zigzag order: copy bits of `buf` into them (`store`), or read them into `buf`
// (which has to start zeroed). At most `bits` of them.
fn walk_data(w: *Work, buf: []u8, store: bool, bits: usize) {
    let n = w.size
    var i = 0usize
    var right = n - 1usize
    while right >= 1usize {
        if right == 6usize { right = 5usize }
        var vert = 0usize
        while vert < n {
            var j = 0usize
            while j < 2usize {
                let x = right - j
                let upward = ((right + 1usize) & 2usize) == 0usize
                var y = vert
                if upward { y = n - 1usize - vert }
                if w.fixed[y * n + x] == 0u8 && i < bits {
                    if store {
                        if ((usize(buf[i >> 3usize]) >> (7usize - (i & 7usize))) & 1usize) == 1usize {
                            w.dark[y * n + x] = 1u8
                        } else {
                            w.dark[y * n + x] = 0u8
                        }
                    } else {
                        if w.dark[y * n + x] == 1u8 {
                            buf[i >> 3usize] = buf[i >> 3usize] | u8(128usize >> (i & 7usize))
                        }
                    }
                    i += 1usize
                }
                j += 1usize
            }
            vert += 1usize
        }
        if right < 2usize { ret }
        right -= 2usize
    }
}

fn line_dark(w: *Work, pass: usize, i: usize, j: usize) -> usize {
    if pass == 0usize { ret usize(w.dark[i * w.size + j]) }
    ret usize(w.dark[j * w.size + i])
}

fn penalty(w: *Work) -> usize {
    let n = w.size
    var total = 0usize
    var pass = 0usize
    while pass < 2usize {
        var i = 0usize
        while i < n {
            var run = 1usize
            var win = 0usize
            var j = 0usize
            while j < n {
                let bit = line_dark(w, pass, i, j)
                if j > 0usize {
                    if bit == line_dark(w, pass, i, j - 1usize) {
                        run += 1usize
                        if run == 5usize { total += 3usize }
                        if run > 5usize { total += 1usize }
                    } else {
                        run = 1usize
                    }
                }
                win = ((win << 1usize) | bit) & 2047usize
                if j >= 10usize && (win == 1488usize || win == 93usize) { total += 40usize }
                j += 1usize
            }
            i += 1usize
        }
        pass += 1usize
    }
    var y = 0usize
    while y + 1usize < n {
        var x = 0usize
        while x + 1usize < n {
            let c = w.dark[y * n + x]
            if c == w.dark[y * n + x + 1usize] && c == w.dark[(y + 1usize) * n + x] && c == w.dark[(y + 1usize) * n + x + 1usize] {
                total += 3usize
            }
            x += 1usize
        }
        y += 1usize
    }
    var count = 0usize
    var k = 0usize
    while k < n * n {
        if w.dark[k] == 1u8 { count += 1usize }
        k += 1usize
    }
    let all = n * n
    var diff = count * 20usize
    if diff >= all * 10usize { diff = diff - all * 10usize } else { diff = all * 10usize - diff }
    if diff > 0usize {
        let steps = (diff + all - 1usize) / all - 1usize
        total += steps * 10usize
    }
    ret total
}

fn put_bits(buf: *BitBuf, value: usize, count: usize) {
    var i = count
    while i > 0usize {
        i -= 1usize
        if ((value >> i) & 1usize) == 1usize {
            buf.data[buf.pos >> 3usize] = buf.data[buf.pos >> 3usize] | u8(128usize >> (buf.pos & 7usize))
        }
        buf.pos += 1usize
    }
}

// ---- QR: encode -------------------------------------------------------------------------------

fn qr_encode(a: *mem.Arena, data: []const u8, ecl: usize) -> (Matrix, err) {
    let (m, m_error) = qr_encode_with(a, data, ecl, 8usize)
    ret (m, m_error)
}

// `mask` 0 to 7 uses that mask, anything else the best.
fn qr_encode_with(a: *mem.Arena, data: []const u8, ecl: usize, mask: usize) -> (Matrix, err) {
    var none: Matrix = zero
    if ecl > 3usize { ret (none, Invalid) }
    var v = 1usize
    var fits = false
    while v <= MAX_VERSION && !fits {
        var count_bits = 8usize
        if v >= 10usize { count_bits = 16usize }
        if 4usize + count_bits + 8usize * data.len <= data_codewords(v, ecl) * 8usize {
            fits = true
        } else {
            v += 1usize
        }
    }
    if !fits { ret (none, TooLong) }
    let total = raw_codewords(v)
    let data_total = data_codewords(v, ecl)
    var cw: [346]u8 = zero
    var bits = BitBuf { data: cw[0usize..346usize], pos: 0usize }
    put_bits(&bits, 4usize, 4usize)
    if v >= 10usize { put_bits(&bits, data.len, 16usize) } else { put_bits(&bits, data.len, 8usize) }
    var k = 0usize
    while k < data.len {
        put_bits(&bits, usize(data[k]), 8usize)
        k += 1usize
    }
    var room = data_total * 8usize - bits.pos
    if room > 4usize { room = 4usize }
    put_bits(&bits, 0usize, room)
    bits.pos = (bits.pos + 7usize) / 8usize * 8usize
    var pad = 236usize
    while bits.pos < data_total * 8usize {
        put_bits(&bits, pad, 8usize)
        if pad == 236usize { pad = 17usize } else { pad = 236usize }
    }
    // Blocks: error correction per block, then interleave.
    var g: Gf = zero
    gf_init(&g)
    let ecc = block_field(v, ecl, 0usize)
    let n1 = block_field(v, ecl, 1usize)
    let d1 = block_field(v, ecl, 2usize)
    let n2 = block_field(v, ecl, 3usize)
    let blocks = n1 + n2
    var divisor: [32]u8 = zero
    rs_divisor(&g, ecc, divisor[0usize..32usize])
    var ec_all: [346]u8 = zero
    var b = 0usize
    while b < blocks {
        var len_b = d1
        var off_b = b * d1
        if b >= n1 {
            len_b = d1 + 1usize
            off_b = b * d1 + (b - n1)
        }
        rs_remainder(&g, cw[off_b..off_b + len_b], divisor[0usize..32usize], ecc, ec_all[b * ecc..b * ecc + ecc])
        b += 1usize
    }
    var all: [346]u8 = zero
    var out = 0usize
    var i = 0usize
    while i < d1 + 1usize {
        b = 0usize
        while b < blocks {
            var len_b = d1
            var off_b = b * d1
            if b >= n1 {
                len_b = d1 + 1usize
                off_b = b * d1 + (b - n1)
            }
            if i < len_b {
                all[out] = cw[off_b + i]
                out += 1usize
            }
            b += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < ecc {
        b = 0usize
        while b < blocks {
            all[out] = ec_all[b * ecc + i]
            out += 1usize
            b += 1usize
        }
        i += 1usize
    }
    let n = 17usize + 4usize * v
    let (dark_store, dark_error) = mem.alloc[u8](a, n * n)
    if dark_error != ok { ret (none, dark_error) }
    let (fixed_store, fixed_error) = mem.alloc[u8](a, n * n)
    if fixed_error != ok { ret (none, fixed_error) }
    k = 0usize
    while k < n * n {
        dark_store[k] = 0u8
        fixed_store[k] = 0u8
        k += 1usize
    }
    var w = Work { size: n, dark: dark_store, fixed: fixed_store }
    draw_function(&w, v)
    walk_data(&w, all[0usize..346usize], true, total * 8usize)
    var best = mask
    if mask > 7usize {
        var best_penalty = 1000000usize
        var m = 0usize
        while m < 8usize {
            apply_mask(&w, m)
            draw_format(&w, ecl, m)
            let p = penalty(&w)
            apply_mask(&w, m)
            if p < best_penalty {
                best_penalty = p
                best = m
            }
            m += 1usize
        }
    }
    apply_mask(&w, best)
    draw_format(&w, ecl, best)
    ret (Matrix { size: n, modules: dark_store }, ok)
}

// ---- QR: decode -------------------------------------------------------------------------------

fn popcount(value: usize) -> usize {
    var v = value
    var c = 0usize
    while v != 0usize {
        c += v & 1usize
        v = v >> 1usize
    }
    ret c
}

fn module_at(m: Matrix, x: usize, y: usize) -> usize { ret usize(m.modules[y * m.size + x] & 1u8) }

// The 15 format bits as the first copy holds them, and as the second does.
fn read_format(m: Matrix, which: usize) -> usize {
    let n = m.size
    var bits = 0usize
    var i = 0usize
    if which == 0usize {
        while i <= 5usize {
            bits = bits | (module_at(m, 8usize, i) << i)
            i += 1usize
        }
        bits = bits | (module_at(m, 8usize, 7usize) << 6usize)
        bits = bits | (module_at(m, 8usize, 8usize) << 7usize)
        bits = bits | (module_at(m, 7usize, 8usize) << 8usize)
        i = 9usize
        while i < 15usize {
            bits = bits | (module_at(m, 14usize - i, 8usize) << i)
            i += 1usize
        }
    } else {
        while i < 8usize {
            bits = bits | (module_at(m, n - 1usize - i, 8usize) << i)
            i += 1usize
        }
        i = 8usize
        while i < 15usize {
            bits = bits | (module_at(m, 8usize, n - 15usize + i) << i)
            i += 1usize
        }
    }
    ret bits
}

// The nearest of the 32 format words within three bit errors: level and mask, or 99 for none.
fn match_format(bits: usize) -> usize {
    var best = 99usize
    var best_dist = 4usize
    var ecl = 0usize
    while ecl < 4usize {
        var mask = 0usize
        while mask < 8usize {
            let dist = popcount(bits ^ format_word(ecl, mask))
            if dist < best_dist {
                best_dist = dist
                best = ecl * 8usize + mask
            }
            mask += 1usize
        }
        ecl += 1usize
    }
    ret best
}

fn alnum_char(v: usize) -> u8 {
    if v < 10usize { ret u8(48usize + v) }
    if v < 36usize { ret u8(65usize + v - 10usize) }
    let sym = " $%*+-./:"
    ret sym[v - 36usize]
}

fn qr_decode(a: *mem.Arena, m: Matrix) -> ([]u8, err) {
    var none: []u8 = zero
    if m.size < 21usize || m.size > 57usize || (m.size - 17usize) % 4usize != 0usize { ret (none, Invalid) }
    if m.modules.len < m.size * m.size { ret (none, Invalid) }
    let v = (m.size - 17usize) / 4usize
    var word = match_format(read_format(m, 0usize))
    if word == 99usize { word = match_format(read_format(m, 1usize)) }
    if word == 99usize { ret (none, Uncorrectable) }
    let ecl = word / 8usize
    let mask = word % 8usize
    let n = m.size
    let (dark_store, dark_error) = mem.alloc[u8](a, n * n)
    if dark_error != ok { ret (none, dark_error) }
    let (fixed_store, fixed_error) = mem.alloc[u8](a, n * n)
    if fixed_error != ok { ret (none, fixed_error) }
    var k = 0usize
    while k < n * n {
        dark_store[k] = m.modules[k] & 1u8
        fixed_store[k] = 0u8
        k += 1usize
    }
    var w = Work { size: n, dark: dark_store, fixed: fixed_store }
    draw_function(&w, v)
    // draw_function overwrote the function modules' values; the data modules are still the input's.
    apply_mask(&w, mask)
    let total = raw_codewords(v)
    var all: [346]u8 = zero
    walk_data(&w, all[0usize..346usize], false, total * 8usize)
    var g: Gf = zero
    gf_init(&g)
    let ecc = block_field(v, ecl, 0usize)
    let n1 = block_field(v, ecl, 1usize)
    let d1 = block_field(v, ecl, 2usize)
    let n2 = block_field(v, ecl, 3usize)
    let blocks = n1 + n2
    // De-interleave into blocks laid out one after another (data, then error correction, per block).
    var laid: [346]u8 = zero
    var idx = 0usize
    var i = 0usize
    while i < d1 + 1usize {
        var b = 0usize
        while b < blocks {
            var len_b = d1
            var start = b * (d1 + ecc)
            if b >= n1 {
                len_b = d1 + 1usize
                start = b * (d1 + ecc) + (b - n1)
            }
            if i < len_b {
                laid[start + i] = all[idx]
                idx += 1usize
            }
            b += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < ecc {
        var b = 0usize
        while b < blocks {
            var len_b = d1
            var start = b * (d1 + ecc)
            if b >= n1 {
                len_b = d1 + 1usize
                start = b * (d1 + ecc) + (b - n1)
            }
            laid[start + len_b + i] = all[idx]
            idx += 1usize
            b += 1usize
        }
        i += 1usize
    }
    var data: [346]u8 = zero
    var data_len = 0usize
    var b = 0usize
    while b < blocks {
        var len_b = d1
        var start = b * (d1 + ecc)
        if b >= n1 {
            len_b = d1 + 1usize
            start = b * (d1 + ecc) + (b - n1)
        }
        if !rs_correct(&g, laid[start..start + len_b + ecc], len_b + ecc, ecc) { ret (none, Uncorrectable) }
        i = 0usize
        while i < len_b {
            data[data_len] = laid[start + i]
            data_len += 1usize
            i += 1usize
        }
        b += 1usize
    }
    // The segments.
    let (out, out_error) = mem.alloc[u8](a, data_len * 3usize + 8usize)
    if out_error != ok { ret (none, out_error) }
    var out_len = 0usize
    var pos = 0usize
    let limit = data_len * 8usize
    var done = false
    while !done && pos + 4usize <= limit {
        let mode = take_bits(data[0usize..346usize], pos, 4usize)
        pos += 4usize
        if mode == 0usize {
            done = true
        } else if mode == 4usize {
            var cb = 8usize
            if v >= 10usize { cb = 16usize }
            if pos + cb > limit { ret (none, Invalid) }
            let count = take_bits(data[0usize..346usize], pos, cb)
            pos += cb
            var c = 0usize
            while c < count {
                if pos + 8usize > limit { ret (none, Invalid) }
                out[out_len] = u8(take_bits(data[0usize..346usize], pos, 8usize))
                out_len += 1usize
                pos += 8usize
                c += 1usize
            }
        } else if mode == 2usize {
            var cb = 9usize
            if v >= 10usize { cb = 11usize }
            if pos + cb > limit { ret (none, Invalid) }
            let count = take_bits(data[0usize..346usize], pos, cb)
            pos += cb
            var c = 0usize
            while c + 1usize < count {
                if pos + 11usize > limit { ret (none, Invalid) }
                let pair = take_bits(data[0usize..346usize], pos, 11usize)
                pos += 11usize
                if out_len + 2usize > out.len { ret (none, Invalid) }
                out[out_len] = alnum_char(pair / 45usize)
                out[out_len + 1usize] = alnum_char(pair % 45usize)
                out_len += 2usize
                c += 2usize
            }
            if c < count {
                if pos + 6usize > limit { ret (none, Invalid) }
                out[out_len] = alnum_char(take_bits(data[0usize..346usize], pos, 6usize))
                out_len += 1usize
                pos += 6usize
            }
        } else if mode == 1usize {
            var cb = 10usize
            if v >= 10usize { cb = 12usize }
            if pos + cb > limit { ret (none, Invalid) }
            let count = take_bits(data[0usize..346usize], pos, cb)
            pos += cb
            var c = 0usize
            while c < count {
                var take = 3usize
                var width = 10usize
                if count - c == 2usize {
                    take = 2usize
                    width = 7usize
                }
                if count - c == 1usize {
                    take = 1usize
                    width = 4usize
                }
                if pos + width > limit { ret (none, Invalid) }
                let group = take_bits(data[0usize..346usize], pos, width)
                pos += width
                if out_len + take > out.len { ret (none, Invalid) }
                if take == 3usize {
                    out[out_len] = u8(48usize + group / 100usize)
                    out[out_len + 1usize] = u8(48usize + group / 10usize % 10usize)
                    out[out_len + 2usize] = u8(48usize + group % 10usize)
                } else if take == 2usize {
                    out[out_len] = u8(48usize + group / 10usize)
                    out[out_len + 1usize] = u8(48usize + group % 10usize)
                } else {
                    out[out_len] = u8(48usize + group)
                }
                out_len += take
                c += take
            }
        } else {
            // Kanji, ECI and the rest are not read.
            ret (none, Invalid)
        }
    }
    ret (out[0usize..out_len], ok)
}

fn take_bits(data: []const u8, pos: usize, count: usize) -> usize {
    var value = 0usize
    var i = 0usize
    while i < count {
        let p = pos + i
        value = (value << 1usize) | ((usize(data[p >> 3usize]) >> (7usize - (p & 7usize))) & 1usize)
        i += 1usize
    }
    ret value
}

fn qr_dark(m: Matrix, x: usize, y: usize) -> bool { ret m.modules[y * m.size + x] == 1u8 }

// ---- Code 128 and EAN-13 ----------------------------------------------------------------------

// Code 128: the 107 patterns as bar, space, ... widths (the stop pattern has seven).
fn code128_table() -> str { ret "2122222221222222211212231213221312221222131223121322122212132213122312121122321221321222311132221231221232212232112211322212312132122231123121313112223211223212213122123221123222112121232123212321211113231311231313211123131321131323112113132311132313111121331123311321311131231133211331213131212113312311312131132133112131313111233113213311213121133123113321113141112214114311111112241114221211241214211411221412211122141124121221141224111421121422112412112211144131112411121341111112421211421212411142121241121242114112124211124212112121412141214121211111431113411311411141131143114111134113111131411141313111414111312114122112142112322331112" }

// Code 128 as modules, 1 for a bar.
fn code128(a: *mem.Arena, text_in: str) -> ([]u8, err) {
    var none: []u8 = zero
    var digits = text_in.len >= 2usize && text_in.len % 2usize == 0usize
    var i = 0usize
    while i < text_in.len {
        let c = text_in[i]
        if c < 32u8 || c > 126u8 { ret (none, Invalid) }
        if c < 48u8 || c > 57u8 { digits = false }
        i += 1usize
    }
    if text_in.len == 0usize { ret (none, Invalid) }
    var codes: [128]usize = zero
    var count = 0usize
    var checksum = 0usize
    if digits {
        codes[0usize] = 105usize
        count = 1usize
        i = 0usize
        while i < text_in.len {
            codes[count] = usize(text_in[i] - 48u8) * 10usize + usize(text_in[i + 1usize] - 48u8)
            count += 1usize
            i += 2usize
        }
    } else {
        codes[0usize] = 104usize
        count = 1usize
        i = 0usize
        while i < text_in.len {
            codes[count] = usize(text_in[i]) - 32usize
            count += 1usize
            i += 1usize
        }
    }
    if count > 100usize { ret (none, TooLong) }
    checksum = codes[0usize]
    i = 1usize
    while i < count {
        checksum += codes[i] * i
        i += 1usize
    }
    codes[count] = checksum % 103usize
    count += 1usize
    codes[count] = 106usize
    count += 1usize
    // Pattern offsets: values 0..105 take six digits each, the stop seven.
    let widths_table = code128_table()
    let (out, out_error) = mem.alloc[u8](a, count * 11usize + 2usize)
    if out_error != ok { ret (none, out_error) }
    var len_out = 0usize
    var k = 0usize
    while k < count {
        let value = codes[k]
        var start = value * 6usize
        var widths = 6usize
        if value == 106usize { widths = 7usize }
        var bar = true
        var d = 0usize
        while d < widths {
            let run = usize(widths_table[start + d]) - 48usize
            var r = 0usize
            while r < run {
                if bar { out[len_out] = 1u8 } else { out[len_out] = 0u8 }
                len_out += 1usize
                r += 1usize
            }
            bar = !bar
            d += 1usize
        }
        k += 1usize
    }
    ret (out[0usize..len_out], ok)
}

fn ean_l_table() -> str { ret "0001101001100100100110111101010001101100010101111011101101101110001011" }
fn ean_parity_table() -> str { ret "LLLLLLLLGLGGLLGGLGLLGGGLLGLLGGLGGLLGLGGGLLLGLGLGLGLGGLLGGLGL" }

// EAN-13 as 95 modules from twelve digits (the check digit is added) or thirteen (it is checked).
fn ean13(a: *mem.Arena, digits_in: str) -> ([]u8, err) {
    var none: []u8 = zero
    if digits_in.len != 12usize && digits_in.len != 13usize { ret (none, Invalid) }
    var d: [13]usize = zero
    var i = 0usize
    while i < digits_in.len {
        if digits_in[i] < 48u8 || digits_in[i] > 57u8 { ret (none, Invalid) }
        d[i] = usize(digits_in[i] - 48u8)
        i += 1usize
    }
    var sum = 0usize
    i = 0usize
    while i < 12usize {
        if i % 2usize == 0usize { sum += d[i] } else { sum += d[i] * 3usize }
        i += 1usize
    }
    let check = (10usize - sum % 10usize) % 10usize
    if digits_in.len == 13usize && d[12usize] != check { ret (none, Invalid) }
    d[12usize] = check
    let (out, out_error) = mem.alloc[u8](a, 95usize)
    let ean_l = ean_l_table()
    let parity_table = ean_parity_table()
    if out_error != ok { ret (none, out_error) }
    var n = 0usize
    out[0usize] = 1u8
    out[1usize] = 0u8
    out[2usize] = 1u8
    n = 3usize
    i = 1usize
    while i < 13usize {
        if i == 7usize {
            out[n] = 0u8
            out[n + 1usize] = 1u8
            out[n + 2usize] = 0u8
            out[n + 3usize] = 1u8
            out[n + 4usize] = 0u8
            n += 5usize
        }
        let digit = d[i]
        // L (76), G (71) or, on the right, R (82).
        var kind = 82u8
        if i <= 6usize { kind = parity_table[d[0usize] * 6usize + i - 1usize] }
        var j = 0usize
        while j < 7usize {
            var bit = usize(ean_l[digit * 7usize + j]) - 48usize
            if kind == 82u8 { bit = 1usize - bit }
            if kind == 71u8 { bit = 1usize - (usize(ean_l[digit * 7usize + 6usize - j]) - 48usize) }
            out[n + j] = u8(bit)
            j += 1usize
        }
        n += 7usize
        i += 1usize
    }
    out[n] = 1u8
    out[n + 1usize] = 0u8
    out[n + 2usize] = 1u8
    ret (out[0usize..95usize], ok)
}

// ---- QR: finding a symbol in an image -----------------------------------------------------------------------

error NotFound

type Finder = struct { x: f64, y: f64, module: f64, votes: usize }

const MAX_FINDERS: usize = 48usize

// The Otsu threshold of an 8-bit luminance image: pixels below it are dark.
fn otsu(luma: []const u8, count: usize) -> usize {
    var histogram: [256]usize = zero
    var i = 0usize
    while i < count {
        histogram[usize(luma[i])] += 1usize
        i += 1usize
    }
    var sum_all = 0usize
    i = 0usize
    while i < 256usize {
        sum_all += i * histogram[i]
        i += 1usize
    }
    var weight_back = 0usize
    var sum_back = 0usize
    var best = 0usize
    var best_between = 0.0f64
    var t = 0usize
    while t < 256usize {
        weight_back += histogram[t]
        if weight_back != 0usize && weight_back != count {
            sum_back += t * histogram[t]
            let weight_fore = count - weight_back
            let mean_back = f64(sum_back) / f64(weight_back)
            let mean_fore = f64(sum_all - sum_back) / f64(weight_fore)
            let between = f64(weight_back) * f64(weight_fore) * (mean_back - mean_fore) * (mean_back - mean_fore)
            if between > best_between {
                best_between = between
                best = t
            }
        }
        t += 1usize
    }
    ret best + 1usize
}

// Do five run lengths (dark, light, dark, light, dark) have the finder's 1:1:3:1:1 proportions?
fn finder_ratio(r0: usize, r1: usize, r2: usize, r3: usize, r4: usize) -> bool {
    let total = r0 + r1 + r2 + r3 + r4
    if total < 7usize { ret false }
    let unit = total
    // Each of the four ones is within half a unit of total / 7, the centre within 3/2 units of 3 total / 7.
    var d0 = r0 * 7usize
    if d0 >= unit { d0 = d0 - unit } else { d0 = unit - d0 }
    var d1 = r1 * 7usize
    if d1 >= unit { d1 = d1 - unit } else { d1 = unit - d1 }
    var d3 = r3 * 7usize
    if d3 >= unit { d3 = d3 - unit } else { d3 = unit - d3 }
    var d4 = r4 * 7usize
    if d4 >= unit { d4 = d4 - unit } else { d4 = unit - d4 }
    var d2 = r2 * 7usize
    if d2 >= 3usize * unit { d2 = d2 - 3usize * unit } else { d2 = 3usize * unit - d2 }
    let limit = unit / 2usize
    ret d0 < limit && d1 < limit && d3 < limit && d4 < limit && d2 < 3usize * limit
}

// Count the run of `want` pixels from (x, y) along (dx, dy); stops at the image's edge.
fn run_length(bin: []const u8, width: usize, height: usize, x: usize, y: usize, dx: i64, dy: i64, want: u8) -> usize {
    var n = 0usize
    var cx = i64(x)
    var cy = i64(y)
    while cx >= 0i64 && cy >= 0i64 && cx < i64(width) && cy < i64(height) && bin[usize(cy) * width + usize(cx)] == want {
        n += 1usize
        cx += dx
        cy += dy
    }
    ret n
}

// Check a candidate at (x, y) in the other direction (dx, dy is the direction to check): the five runs through
// it must have the finder's proportions. Returns the total length and the centre offset along the line.
fn cross_check(bin: []const u8, width: usize, height: usize, x: usize, y: usize, dx: i64, dy: i64) -> (usize, i64, bool) {
    // The dark centre run, both ways from the point.
    let up = run_length(bin, width, height, x, y, 0i64 - dx, 0i64 - dy, 1u8)
    let down = run_length(bin, width, height, x, y, dx, dy, 1u8)
    if up == 0usize || down == 0usize { ret (0usize, 0i64, false) }
    let centre = up + down - 1usize
    // The light run before it and the dark run before that.
    let sx = i64(x) - dx * i64(up)
    let sy = i64(y) - dy * i64(up)
    if sx < 0i64 || sy < 0i64 || sx >= i64(width) || sy >= i64(height) { ret (0usize, 0i64, false) }
    let l1 = run_length(bin, width, height, usize(sx), usize(sy), 0i64 - dx, 0i64 - dy, 0u8)
    if l1 == 0usize { ret (0usize, 0i64, false) }
    let sx2 = sx - dx * i64(l1)
    let sy2 = sy - dy * i64(l1)
    if sx2 < 0i64 || sy2 < 0i64 || sx2 >= i64(width) || sy2 >= i64(height) { ret (0usize, 0i64, false) }
    let d1 = run_length(bin, width, height, usize(sx2), usize(sy2), 0i64 - dx, 0i64 - dy, 1u8)
    if d1 == 0usize { ret (0usize, 0i64, false) }
    // And after it.
    let ex = i64(x) + dx * i64(down)
    let ey = i64(y) + dy * i64(down)
    if ex < 0i64 || ey < 0i64 || ex >= i64(width) || ey >= i64(height) { ret (0usize, 0i64, false) }
    let l2 = run_length(bin, width, height, usize(ex), usize(ey), dx, dy, 0u8)
    if l2 == 0usize { ret (0usize, 0i64, false) }
    let ex2 = ex + dx * i64(l2)
    let ey2 = ey + dy * i64(l2)
    if ex2 < 0i64 || ey2 < 0i64 || ex2 >= i64(width) || ey2 >= i64(height) { ret (0usize, 0i64, false) }
    let d2 = run_length(bin, width, height, usize(ex2), usize(ey2), dx, dy, 1u8)
    if d2 == 0usize { ret (0usize, 0i64, false) }
    if !finder_ratio(d1, l1, centre, l2, d2) { ret (0usize, 0i64, false) }
    // The centre of the middle run relative to the point: (down - up) / 2.
    let shift = (i64(down) - i64(up)) / 2i64
    ret (d1 + l1 + centre + l2 + d2, shift, true)
}

fn add_finder(list: []Finder, count: usize, x: f64, y: f64, module: f64) -> usize {
    var i = 0usize
    while i < count {
        let dx = list[i].x - x
        let dy = list[i].y - y
        let near = list[i].module * 2.0f64
        if dx * dx + dy * dy < near * near {
            let v = f64(list[i].votes)
            list[i].x = (list[i].x * v + x) / (v + 1.0f64)
            list[i].y = (list[i].y * v + y) / (v + 1.0f64)
            list[i].module = (list[i].module * v + module) / (v + 1.0f64)
            list[i].votes += 1usize
            ret count
        }
        i += 1usize
    }
    if count >= list.len { ret count }
    list[count] = Finder { x: x, y: y, module: module, votes: 1usize }
    ret count + 1usize
}

fn dist2(p: Finder, q: Finder) -> f64 {
    let dx = p.x - q.x
    let dy = p.y - q.y
    ret dx * dx + dy * dy
}

// Finds a QR symbol in an 8-bit luminance image (rows of `width` bytes) and reads it. The three finder patterns
// are found by their 1:1:3:1:1 runs along rows and checked down the columns; the symbol's grid is the affine
// frame they give (so a turn or a shear is fine, a perspective is not), sampled at the module centres and read
// by `qr_decode`. `NotFound` when there is no symbol or it cannot be read.
fn qr_scan(a: *mem.Arena, luma: []const u8, width: usize, height: usize) -> ([]u8, err) {
    var none: []u8 = zero
    if width < 21usize || height < 21usize || luma.len < width * height { ret (none, NotFound) }
    let (bin, bin_error) = mem.alloc[u8](a, width * height)
    if bin_error != ok { ret (none, bin_error) }
    let threshold = otsu(luma, width * height)
    var k = 0usize
    while k < width * height {
        if usize(luma[k]) < threshold { bin[k] = 1u8 } else { bin[k] = 0u8 }
        k += 1usize
    }
    var list: [48]Finder = zero
    var count = 0usize
    var y = 0usize
    while y < height {
        var runs: [5]usize = zero
        var have = 0usize
        var x = 0usize
        var start = 0usize
        while x <= width {
            var edge = x == width
            if !edge { edge = x > 0usize && bin[y * width + x] != bin[y * width + x - 1usize] }
            if edge && x > 0usize {
                let finished = x - start
                let colour = bin[y * width + x - 1usize]
                runs[0usize] = runs[1usize]
                runs[1usize] = runs[2usize]
                runs[2usize] = runs[3usize]
                runs[3usize] = runs[4usize]
                runs[4usize] = finished
                have += 1usize
                start = x
                if colour == 1u8 && have >= 5usize && finder_ratio(runs[0usize], runs[1usize], runs[2usize], runs[3usize], runs[4usize]) {
                    let centre_x = x - runs[4usize] - runs[3usize] - runs[2usize] + runs[2usize] / 2usize
                    let (vertical, shift, vertical_ok) = cross_check(bin, width, height, centre_x, y, 0i64, 1i64)
                    if vertical_ok {
                        var centre_y = i64(y) + shift
                        if centre_y < 0i64 { centre_y = 0i64 }
                        // And back across the row through the refined centre.
                        let (horizontal, hshift, horizontal_ok) = cross_check(bin, width, height, centre_x, usize(centre_y), 1i64, 0i64)
                        if horizontal_ok {
                            let module = f64(vertical + horizontal) / 14.0f64
                            count = add_finder(list[0usize..48usize], count, f64(i64(centre_x) + hshift), f64(centre_y), module)
                        }
                    }
                }
            }
            x += 1usize
        }
        y += 1usize
    }
    if count < 3usize { ret (none, NotFound) }
    // A triple whose long side is the hypotenuse of a right isosceles triangle, the modules alike.
    var i = 0usize
    while i < count {
        var j = i + 1usize
        while j < count {
            var l = j + 1usize
            while l < count {
                let d_ij = dist2(list[i], list[j])
                let d_il = dist2(list[i], list[l])
                let d_jl = dist2(list[j], list[l])
                // The corner is the point opposite the longest side.
                var corner = i
                var p = j
                var q = l
                var side_p = d_ij
                var side_q = d_il
                var hyp = d_jl
                if d_ij >= d_il && d_ij >= d_jl {
                    corner = l
                    p = i
                    q = j
                    side_p = d_il
                    side_q = d_jl
                    hyp = d_ij
                } else if d_il >= d_ij && d_il >= d_jl {
                    corner = j
                    p = i
                    q = l
                    side_p = d_ij
                    side_q = d_jl
                    hyp = d_il
                }
                let ratio = side_p / side_q
                let m_ratio = list[p].module / list[q].module
                let m_corner = list[corner].module / list[p].module
                if ratio > 0.7f64 && ratio < 1.43f64 && hyp > 1.6f64 * side_p && hyp < 2.5f64 * side_p && m_ratio > 0.6f64 && m_ratio < 1.67f64 && m_corner > 0.6f64 && m_corner < 1.67f64 {
                    // Which of p and q is on the right: the cross product of the two sides from the corner.
                    let ax = list[p].x - list[corner].x
                    let ay = list[p].y - list[corner].y
                    let bx = list[q].x - list[corner].x
                    let by = list[q].y - list[corner].y
                    var right = p
                    var down = q
                    if ax * by - ay * bx < 0.0f64 {
                        right = q
                        down = p
                    }
                    let module = (list[corner].module + list[p].module + list[q].module) / 3.0f64
                    let rx = list[right].x - list[corner].x
                    let ry = list[right].y - list[corner].y
                    let side = rx * rx + ry * ry
                    // side / module^2 is (n - 7)^2; the sizes tried are the nearest and its neighbours.
                    let modules_across = side / (module * module)
                    var guess = 21usize
                    var best_gap = 1000000.0f64
                    var size = 21usize
                    while size <= 57usize {
                        let want = f64((size - 7usize) * (size - 7usize))
                        var gap = want - modules_across
                        if gap < 0.0f64 { gap = 0.0f64 - gap }
                        if gap < best_gap {
                            best_gap = gap
                            guess = size
                        }
                        size += 4usize
                    }
                    var attempt = 0usize
                    while attempt < 3usize {
                        var n = guess
                        if attempt == 1usize && guess + 4usize <= 57usize { n = guess + 4usize }
                        if attempt == 2usize && guess >= 25usize { n = guess - 4usize }
                        if attempt == 0usize || n != guess {
                            let span = f64(n - 7usize)
                            let ux_x = rx / span
                            let ux_y = ry / span
                            let uy_x = (list[down].x - list[corner].x) / span
                            let uy_y = (list[down].y - list[corner].y) / span
                            let (grid, grid_error) = mem.alloc[u8](a, n * n)
                            if grid_error == ok {
                                var row = 0usize
                                while row < n {
                                    var col = 0usize
                                    while col < n {
                                        let fx = list[corner].x + (f64(col) - 3.0f64) * ux_x + (f64(row) - 3.0f64) * uy_x
                                        let fy = list[corner].y + (f64(col) - 3.0f64) * ux_y + (f64(row) - 3.0f64) * uy_y
                                        var px = i64(fx + 0.5f64)
                                        var py = i64(fy + 0.5f64)
                                        if px < 0i64 { px = 0i64 }
                                        if py < 0i64 { py = 0i64 }
                                        if px >= i64(width) { px = i64(width) - 1i64 }
                                        if py >= i64(height) { py = i64(height) - 1i64 }
                                        grid[row * n + col] = bin[usize(py) * width + usize(px)]
                                        col += 1usize
                                    }
                                    row += 1usize
                                }
                                let (found, found_error) = qr_decode(a, Matrix { size: n, modules: grid })
                                if found_error == ok { ret (found, ok) }
                            }
                        }
                        attempt += 1usize
                    }
                }
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (none, NotFound)
}
