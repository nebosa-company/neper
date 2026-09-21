// Entropy and integer codings over byte slices: run lengths, variable-length
// integers, deltas and bit packing, Elias-gamma and Rice codes, move-to-front,
// the Burrows-Wheeler transform and canonical Huffman codes.
//
// Every encoder writes into caller storage and answers the length used, or
// `TooSmall` when the output would not fit; every decoder answers `Invalid` for
// input it cannot read to the end. Bit-level codes go through `BitWriter` and
// `BitReader`, most-significant bit first, so a stream mixing several codes is
// written and read with one cursor.

type BitWriter = struct { out: []u8, bits: usize }
type BitReader = struct { data: []const u8, bits: usize }
type Huffman = struct { lengths: [256]u8, codes: [256]u32 }
error TooSmall
error Invalid

// Run-length: a byte followed by its repeat count (1..=255), so incompressible
// input grows by a factor of two.
fn rle_encode(src: []const u8, dst: []u8) -> (usize, err) {
    var at = 0usize
    var out = 0usize
    while at < src.len {
        var run = 1usize
        while at + run < src.len && src[at + run] == src[at] && run < 255usize { run += 1usize }
        if out + 2usize > dst.len { ret (0usize, TooSmall) }
        dst[out] = src[at]
        dst[out + 1usize] = u8(run)
        out += 2usize
        at += run
    }
    ret (out, ok)
}

fn rle_decode(src: []const u8, dst: []u8) -> (usize, err) {
    if src.len % 2usize != 0usize { ret (0usize, Invalid) }
    var at = 0usize
    var out = 0usize
    while at < src.len {
        let run = usize(src[at + 1usize])
        if run == 0usize { ret (0usize, Invalid) }
        if out + run > dst.len { ret (0usize, TooSmall) }
        var k = 0usize
        while k < run {
            dst[out + k] = src[at]
            k += 1usize
        }
        out += run
        at += 2usize
    }
    ret (out, ok)
}

// LEB128: seven bits per byte, low group first, the high bit set while more follow.
fn varint_encode(value: u64, dst: []u8) -> (usize, err) {
    var v = value
    var out = 0usize
    while true {
        if out >= dst.len { ret (0usize, TooSmall) }
        let low = u8(v & 127u64)
        v = v >> 7u64
        if v == 0u64 {
            dst[out] = low
            ret (out + 1usize, ok)
        }
        dst[out] = low | 128u8
        out += 1usize
    }
    ret (0usize, Invalid)
}

// The value and the number of bytes it took; at most ten bytes are read.
fn varint_decode(src: []const u8) -> (u64, usize, err) {
    var value = 0u64
    var at = 0usize
    while at < src.len && at < 10usize {
        let b = u64(src[at])
        if at == 9usize && b > 1u64 { ret (0u64, 0usize, Invalid) }
        value = value | ((b & 127u64) << (7u64 * u64(at)))
        at += 1usize
        if b < 128u64 { ret (value, at, ok) }
    }
    ret (0u64, 0usize, Invalid)
}

// VLQ as MIDI and Git write it: high group first, the high bit set while more follow.
fn vlq_encode(value: u64, dst: []u8) -> (usize, err) {
    var groups = 1usize
    var v = value >> 7u64
    while v != 0u64 {
        groups += 1usize
        v = v >> 7u64
    }
    if dst.len < groups { ret (0usize, TooSmall) }
    var at = groups
    v = value
    while at > 0usize {
        at -= 1usize
        var b = u8(v & 127u64)
        if at + 1usize != groups { b = b | 128u8 }
        dst[at] = b
        v = v >> 7u64
    }
    ret (groups, ok)
}

fn vlq_decode(src: []const u8) -> (u64, usize, err) {
    var value = 0u64
    var at = 0usize
    while at < src.len && at < 10usize {
        let b = u64(src[at])
        if at == 9usize && (value >> 57u64) != 0u64 { ret (0u64, 0usize, Invalid) }
        value = (value << 7u64) | (b & 127u64)
        at += 1usize
        if b < 128u64 { ret (value, at, ok) }
    }
    ret (0u64, 0usize, Invalid)
}

// ZigZag maps signed values to unsigned so small magnitudes stay small.
fn zigzag_encode(value: i64) -> u64 {
    let bits = u64.trunc(value)
    ret (bits << 1u64) ^ (0u64 -% (bits >> 63u64))
}

fn zigzag_decode(value: u64) -> i64 { ret i64.trunc((value >> 1u64) ^ (0u64 -% (value & 1u64))) }

// Replaces each value after the first with its difference from the one before.
fn delta_encode(values: []i64) {
    var at = values.len
    while at > 1usize {
        at -= 1usize
        values[at] = values[at] -% values[at - 1usize]
    }
}

fn delta_decode(values: []i64) {
    var at = 1usize
    while at < values.len {
        values[at] = values[at] +% values[at - 1usize]
        at += 1usize
    }
}

// Deltas of deltas, for series with a steady slope such as timestamps.
fn delta_delta_encode(values: []i64) {
    delta_encode(values)
    if values.len > 1usize { delta_encode(values[1usize..]) }
}

fn delta_delta_decode(values: []i64) {
    if values.len > 1usize { delta_decode(values[1usize..]) }
    delta_decode(values)
}

// The smallest width that holds every value.
fn bit_width(values: []const u64) -> u32 {
    var top = 0u64
    var at = 0usize
    while at < values.len {
        top = top | values[at]
        at += 1usize
    }
    var width = 0u32
    while top != 0u64 {
        width += 1u32
        top = top >> 1u64
    }
    ret width
}

fn bit_writer(out: []u8) -> BitWriter { ret BitWriter { out: out, bits: 0usize } }

// Appends the low `width` bits of `value`, most significant first; `width <= 64`.
fn write_bits(w: *BitWriter, value: u64, width: u32) -> err {
    if w.bits + usize(width) > w.out.len * 8usize { ret TooSmall }
    var remaining = width
    while remaining > 0u32 {
        remaining -= 1u32
        let bit = (value >> u64(remaining)) & 1u64
        let byte = w.bits / 8usize
        if w.bits % 8usize == 0usize { w.out[byte] = 0u8 }
        if bit != 0u64 { w.out[byte] = w.out[byte] | u8(128u32 >> u32(w.bits % 8usize)) }
        w.bits += 1usize
    }
    ret ok
}

// The bytes written so far, the last one padded with zero bits.
fn written(w: *const BitWriter) -> usize { ret (w.bits + 7usize) / 8usize }

fn bit_reader(data: []const u8) -> BitReader { ret BitReader { data: data, bits: 0usize } }

fn read_bits(r: *BitReader, width: u32) -> (u64, err) {
    if r.bits + usize(width) > r.data.len * 8usize { ret (0u64, Invalid) }
    var value = 0u64
    var remaining = width
    while remaining > 0u32 {
        let byte = r.bits / 8usize
        let bit = (u64(r.data[byte]) >> (7u64 - u64(r.bits % 8usize))) & 1u64
        value = (value << 1u64) | bit
        r.bits += 1usize
        remaining -= 1u32
    }
    ret (value, ok)
}

fn bits_left(r: *const BitReader) -> usize { ret r.data.len * 8usize - r.bits }

// Packs every value in `width` bits; the caller records `width` and the count.
fn bit_pack(values: []const u64, width: u32, dst: []u8) -> (usize, err) {
    var w = bit_writer(dst)
    var at = 0usize
    while at < values.len {
        if write_bits(&w, values[at], width) != ok { ret (0usize, TooSmall) }
        at += 1usize
    }
    ret (written(&w), ok)
}

fn bit_unpack(src: []const u8, width: u32, values: []u64) -> err {
    var r = bit_reader(src)
    var at = 0usize
    while at < values.len {
        let (value, read_error) = read_bits(&r, width)
        if read_error != ok { ret read_error }
        values[at] = value
        at += 1usize
    }
    ret ok
}

// Frame of reference: the minimum as a varint, the width as one byte, then every
// offset from the minimum bit-packed.
fn for_encode(values: []const u64, dst: []u8) -> (usize, err) {
    var least = 0u64
    if values.len > 0usize { least = values[0usize] }
    var at = 1usize
    while at < values.len {
        if values[at] < least { least = values[at] }
        at += 1usize
    }
    var top = 0u64
    at = 0usize
    while at < values.len {
        top = top | (values[at] - least)
        at += 1usize
    }
    var width = 0u32
    while top != 0u64 {
        width += 1u32
        top = top >> 1u64
    }
    let (head, head_error) = varint_encode(least, dst)
    if head_error != ok { ret (0usize, head_error) }
    if head + 1usize > dst.len { ret (0usize, TooSmall) }
    dst[head] = u8(width)
    var w = bit_writer(dst[head + 1usize..])
    at = 0usize
    while at < values.len {
        if write_bits(&w, values[at] - least, width) != ok { ret (0usize, TooSmall) }
        at += 1usize
    }
    ret (head + 1usize + written(&w), ok)
}

fn for_decode(src: []const u8, values: []u64) -> err {
    let (least, head, head_error) = varint_decode(src)
    if head_error != ok { ret head_error }
    if head >= src.len { ret Invalid }
    let width = u32(src[head])
    if width > 64u32 { ret Invalid }
    var r = bit_reader(src[head + 1usize..])
    var at = 0usize
    while at < values.len {
        let (offset, read_error) = read_bits(&r, width)
        if read_error != ok { ret read_error }
        values[at] = least +% offset
        at += 1usize
    }
    ret ok
}

// Elias gamma of `value >= 1`: the bit length in unary zeros, then the value.
fn elias_gamma_write(w: *BitWriter, value: u64) -> err {
    if value == 0u64 { ret Invalid }
    var width = 0u32
    var v = value
    while v > 1u64 {
        width += 1u32
        v = v >> 1u64
    }
    if write_bits(w, 0u64, width) != ok { ret TooSmall }
    ret write_bits(w, value, width + 1u32)
}

fn elias_gamma_read(r: *BitReader) -> (u64, err) {
    var width = 0u32
    while true {
        let (bit, bit_error) = read_bits(r, 1u32)
        if bit_error != ok { ret (0u64, bit_error) }
        if bit == 1u64 { break }
        width += 1u32
        if width > 63u32 { ret (0u64, Invalid) }
    }
    let (rest, rest_error) = read_bits(r, width)
    if rest_error != ok { ret (0u64, rest_error) }
    ret ((1u64 << u64(width)) | rest, ok)
}

// Rice code with parameter `k`: the quotient `value >> k` in unary, then `k` bits.
fn rice_write(w: *BitWriter, value: u64, k: u32) -> err {
    if k > 63u32 { ret Invalid }
    var quotient = value >> u64(k)
    while quotient > 0u64 {
        var chunk = 64u64
        if quotient < chunk { chunk = quotient }
        if write_bits(w, 18446744073709551615u64, u32(chunk)) != ok { ret TooSmall }
        quotient -= chunk
    }
    if write_bits(w, 0u64, 1u32) != ok { ret TooSmall }
    ret write_bits(w, value & ((1u64 << u64(k)) - 1u64), k)
}

fn rice_read(r: *BitReader, k: u32) -> (u64, err) {
    if k > 63u32 { ret (0u64, Invalid) }
    var quotient = 0u64
    while true {
        let (bit, bit_error) = read_bits(r, 1u32)
        if bit_error != ok { ret (0u64, bit_error) }
        if bit == 0u64 { break }
        quotient += 1u64
    }
    let (rest, rest_error) = read_bits(r, k)
    if rest_error != ok { ret (0u64, rest_error) }
    ret ((quotient << u64(k)) | rest, ok)
}

// Move-to-front: each byte becomes its position in a list that moves the byte to
// the front, so repeated bytes become small numbers.
fn move_to_front_encode(src: []const u8, dst: []u8) -> err {
    if dst.len < src.len { ret TooSmall }
    var order: [256]u8 = zero
    var i = 0usize
    while i < 256usize {
        order[i] = u8(i)
        i += 1usize
    }
    i = 0usize
    while i < src.len {
        var at = 0usize
        while order[at] != src[i] { at += 1usize }
        dst[i] = u8(at)
        while at > 0usize {
            order[at] = order[at - 1usize]
            at -= 1usize
        }
        order[0usize] = src[i]
        i += 1usize
    }
    ret ok
}

fn move_to_front_decode(src: []const u8, dst: []u8) -> err {
    if dst.len < src.len { ret TooSmall }
    var order: [256]u8 = zero
    var i = 0usize
    while i < 256usize {
        order[i] = u8(i)
        i += 1usize
    }
    i = 0usize
    while i < src.len {
        var at = usize(src[i])
        let value = order[at]
        dst[i] = value
        while at > 0usize {
            order[at] = order[at - 1usize]
            at -= 1usize
        }
        order[0usize] = value
        i += 1usize
    }
    ret ok
}

// The Burrows-Wheeler transform of `src`: the last column of its sorted rotations
// and the row holding the original. `scratch.len >= src.len` holds the rotation
// indices, sorted here by comparing rotations directly, so the cost is
// `O(n log n)` comparisons of up to `n` bytes each.
fn bwt_encode(src: []const u8, dst: []u8, scratch: []usize) -> (usize, err) {
    let n = src.len
    if dst.len < n || scratch.len < n { ret (0usize, TooSmall) }
    if n == 0usize { ret (0usize, ok) }
    var i = 0usize
    while i < n {
        scratch[i] = i
        i += 1usize
    }
    // Heapsort of the rotation indices.
    var start = n / 2usize
    while start > 0usize {
        start -= 1usize
        bwt_sift(src, scratch, start, n)
    }
    var end = n
    while end > 1usize {
        end -= 1usize
        let carried = scratch[0usize]
        scratch[0usize] = scratch[end]
        scratch[end] = carried
        bwt_sift(src, scratch, 0usize, end)
    }
    var row = 0usize
    i = 0usize
    while i < n {
        let rotation = scratch[i]
        if rotation == 0usize { row = i }
        dst[i] = src[(rotation + n - 1usize) % n]
        i += 1usize
    }
    ret (row, ok)
}

// Sifts `scratch[at]` down within the first `end` rotations.
fn bwt_sift(src: []const u8, scratch: []usize, at: usize, end: usize) {
    var here = at
    while true {
        let left = here * 2usize + 1usize
        if left >= end { break }
        var largest = left
        let right = left + 1usize
        if right < end && bwt_compare(src, scratch[right], scratch[left]) > 0i32 { largest = right }
        if bwt_compare(src, scratch[largest], scratch[here]) <= 0i32 { break }
        let carried = scratch[here]
        scratch[here] = scratch[largest]
        scratch[largest] = carried
        here = largest
    }
}

// Orders two rotations of `src`.
fn bwt_compare(src: []const u8, a: usize, b: usize) -> i32 {
    let n = src.len
    var k = 0usize
    while k < n {
        let x = src[(a + k) % n]
        let y = src[(b + k) % n]
        if x < y { ret 0i32 - 1i32 }
        if x > y { ret 1i32 }
        k += 1usize
    }
    ret 0i32
}

// Inverts the transform from the last column and the original row;
// `scratch.len >= src.len`.
fn bwt_decode(src: []const u8, row: usize, dst: []u8, scratch: []usize) -> err {
    let n = src.len
    if dst.len < n || scratch.len < n { ret TooSmall }
    if n == 0usize { ret ok }
    if row >= n { ret Invalid }
    var counts: [256]usize = zero
    var i = 0usize
    while i < n {
        counts[usize(src[i])] += 1usize
        i += 1usize
    }
    var starts: [256]usize = zero
    var sum = 0usize
    i = 0usize
    while i < 256usize {
        starts[i] = sum
        sum += counts[i]
        i += 1usize
    }
    // `scratch[i]` is where the byte at `i` in the last column sits in the first.
    i = 0usize
    while i < n {
        let b = usize(src[i])
        scratch[starts[b]] = i
        starts[b] += 1usize
        i += 1usize
    }
    var at = scratch[row]
    i = 0usize
    while i < n {
        dst[i] = src[at]
        at = scratch[at]
        i += 1usize
    }
    ret ok
}

// Code lengths from byte frequencies, longest code at most `limit` bits
// (`limit` in `1..=32`); lengths are then made canonical. Symbols with zero
// frequency get length 0. A single used symbol gets a one-bit code.
fn huffman_build(frequencies: []const u64, limit: u32) -> (Huffman, err) {
    if frequencies.len > 256usize || limit == 0u32 || limit > 32u32 { ret (zero, Invalid) }
    var h: Huffman = zero
    // Package-merge would be exact; this builds the tree and, when it is too deep,
    // flattens frequencies and retries, which always terminates at `limit >= 8`.
    var weights: [256]u64 = zero
    var used = 0usize
    var i = 0usize
    while i < frequencies.len {
        weights[i] = frequencies[i]
        if frequencies[i] != 0u64 { used += 1usize }
        i += 1usize
    }
    if used == 0usize { ret (h, ok) }
    while true {
        // Leaves 0..255 and internal nodes from 256: a two-queue merge over sorted leaves.
        var node_weight: [512]u64 = zero
        var parent: [512]u16 = zero
        var order: [256]u16 = zero
        var leaves = 0usize
        i = 0usize
        while i < 256usize {
            if weights[i] != 0u64 {
                order[leaves] = u16(i)
                leaves += 1usize
            }
            node_weight[i] = weights[i]
            i += 1usize
        }
        // Insertion sort of the leaves by weight, ties by symbol.
        var s = 1usize
        while s < leaves {
            var t = s
            while t > 0usize && node_weight[usize(order[t])] < node_weight[usize(order[t - 1usize])] {
                let swap = order[t]
                order[t] = order[t - 1usize]
                order[t - 1usize] = swap
                t -= 1usize
            }
            s += 1usize
        }
        var leaf_at = 0usize
        var internal_first = 256usize
        var internal_end = 256usize
        var made = 0usize
        while leaves - leaf_at + (internal_end - internal_first) > 1usize {
            var picked: [2]usize = zero
            var p = 0usize
            while p < 2usize {
                var take_leaf = leaf_at < leaves
                if take_leaf && internal_first < internal_end {
                    if node_weight[internal_first] < node_weight[usize(order[leaf_at])] { take_leaf = false }
                }
                if take_leaf {
                    picked[p] = usize(order[leaf_at])
                    leaf_at += 1usize
                } else {
                    picked[p] = internal_first
                    internal_first += 1usize
                }
                p += 1usize
            }
            node_weight[internal_end] = node_weight[picked[0usize]] + node_weight[picked[1usize]]
            parent[picked[0usize]] = u16(internal_end)
            parent[picked[1usize]] = u16(internal_end)
            internal_end += 1usize
            made += 1usize
        }
        let root = internal_end - 1usize
        var deepest = 0u32
        i = 0usize
        while i < 256usize {
            h.lengths[i] = 0u8
            if weights[i] != 0u64 {
                var depth = 0u32
                var at = i
                if made == 0usize { depth = 1u32 } else {
                    while at != root {
                        at = usize(parent[at])
                        depth += 1u32
                    }
                }
                h.lengths[i] = u8(depth)
                if depth > deepest { deepest = depth }
            }
            i += 1usize
        }
        if deepest <= limit { break }
        i = 0usize
        while i < 256usize {
            if weights[i] != 0u64 { weights[i] = weights[i] / 2u64 + 1u64 }
            i += 1usize
        }
    }
    huffman_canonical(&h)
    ret (h, ok)
}

// Assigns canonical codes from the lengths: shorter codes first, ties by symbol.
fn huffman_canonical(h: *Huffman) {
    var count: [33]u32 = zero
    var i = 0usize
    while i < 256usize {
        count[usize(h.lengths[i])] += 1u32
        i += 1usize
    }
    count[0usize] = 0u32
    var next: [33]u32 = zero
    var code = 0u32
    var length = 1usize
    while length < 33usize {
        code = (code + count[length - 1usize]) << 1u32
        next[length] = code
        length += 1usize
    }
    i = 0usize
    while i < 256usize {
        let l = usize(h.lengths[i])
        h.codes[i] = 0u32
        if l != 0usize {
            h.codes[i] = next[l]
            next[l] += 1u32
        }
        i += 1usize
    }
}

// Writes each byte's code; a byte with no code is `Invalid`.
fn huffman_encode(h: *const Huffman, src: []const u8, w: *BitWriter) -> err {
    var i = 0usize
    while i < src.len {
        let l = h.lengths[usize(src[i])]
        if l == 0u8 { ret Invalid }
        if write_bits(w, u64(h.codes[usize(src[i])]), u32(l)) != ok { ret TooSmall }
        i += 1usize
    }
    ret ok
}

// Reads `dst.len` symbols; the canonical property lets each code be recognised by
// length without a tree.
fn huffman_decode(h: *const Huffman, r: *BitReader, dst: []u8) -> err {
    var count: [33]u32 = zero
    var first_symbol: [33]u32 = zero
    var symbols: [256]u8 = zero
    var i = 0usize
    while i < 256usize {
        count[usize(h.lengths[i])] += 1u32
        i += 1usize
    }
    count[0usize] = 0u32
    var offset = 0u32
    var length = 1usize
    while length < 33usize {
        first_symbol[length] = offset
        offset += count[length]
        length += 1usize
    }
    var fill: [33]u32 = zero
    i = 0usize
    while i < 256usize {
        let l = usize(h.lengths[i])
        if l != 0usize {
            symbols[usize(first_symbol[l] + fill[l])] = u8(i)
            fill[l] += 1u32
        }
        i += 1usize
    }
    var out = 0usize
    while out < dst.len {
        var code = 0u32
        var first_code = 0u32
        var index = 0u32
        length = 1usize
        var found = false
        while length < 33usize {
            let (bit, bit_error) = read_bits(r, 1u32)
            if bit_error != ok { ret bit_error }
            code = code | u32(bit)
            if code < first_code + count[length] {
                dst[out] = symbols[usize(index + code - first_code)]
                found = true
                break
            }
            index += count[length]
            first_code = (first_code + count[length]) << 1u32
            code = code << 1u32
            length += 1usize
        }
        if !found { ret Invalid }
        out += 1usize
    }
    ret ok
}
