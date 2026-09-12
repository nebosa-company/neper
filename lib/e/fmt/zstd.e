// Zstandard (RFC 8878) frames: a pull reader that decodes one block at a time --
// raw, RLE, or compressed with its Huffman literals and FSE-coded sequences -- into
// a history buffer of the window plus a block, and hands bytes out as `read` asks;
// the content checksum (XXH64, low 32 bits) is compared at the frame's end. A
// dictionary id or a skippable frame is `Unsupported`, so is a window past
// `window_limit`; anything malformed is `Invalid`; output past `output_limit` is
// `Invalid` too, reported before the byte leaves. The writer emits frames of raw
// blocks with a content checksum at every level -- valid Zstandard that any decoder
// reads, at no compression; the entropy coders on the writing side are the upgrade.
//
// ponytail: the writer's `Level` is accepted and ignored, as the header says.
use e.io
use e.mem

type Reader = struct { state: *void }
type Writer = struct { state: *void }
type Level = enum u8 { Fast, Balanced, Best }
error Invalid
error Checksum
error Unsupported

const BLOCK_MAX: usize = 131072usize
const INPUT: usize = 131072usize + 32usize
const HUFF_LOG_MAX: usize = 11usize
const SEQ_TABLE: usize = 512usize

// --- XXH64.

const PRIME1: u64 = 11400714785074694791u64
const PRIME2: u64 = 14029467366897019727u64
const PRIME3: u64 = 1609587929392839161u64
const PRIME4: u64 = 9650029242287828579u64
const PRIME5: u64 = 2870177450012600261u64

type Xxh64 = struct { v1: u64, v2: u64, v3: u64, v4: u64, total: u64, buffer: [32]u8, buffered: usize }

fn rotl64(x: u64, n: u32) -> u64 {
    let left = x << n
    ret left | (x >> (64u32 - n))
}

fn xxh_round(acc: u64, lane: u64) -> u64 {
    ret rotl64(acc +% lane *% PRIME2, 31u32) *% PRIME1
}

fn xxh_merge(acc: u64, lane: u64) -> u64 {
    let mixed = acc ^ xxh_round(0u64, lane)
    ret mixed *% PRIME1 +% PRIME4
}

fn load64(data: []const u8, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = v | (u64(data[at + i]) << u32(i * 8usize))
        i += 1usize
    }
    ret v
}

fn load32(data: []const u8, at: usize) -> u32 {
    ret u32(data[at]) | (u32(data[at + 1usize]) << 8u32) | (u32(data[at + 2usize]) << 16u32) | (u32(data[at + 3usize]) << 24u32)
}

fn xxh64_init() -> Xxh64 {
    var h: Xxh64 = zero
    h.v1 = PRIME1 +% PRIME2
    h.v2 = PRIME2
    h.v3 = 0u64
    h.v4 = 0u64 -% PRIME1
    ret h
}

fn xxh64_block(h: *Xxh64, block: []const u8, at: usize) {
    h.v1 = xxh_round(h.v1, load64(block, at))
    h.v2 = xxh_round(h.v2, load64(block, at + 8usize))
    h.v3 = xxh_round(h.v3, load64(block, at + 16usize))
    h.v4 = xxh_round(h.v4, load64(block, at + 24usize))
}

fn xxh64_update(h: *Xxh64, data: []const u8) {
    h.total +%= u64(data.len)
    var at = 0usize
    if h.buffered > 0usize {
        while h.buffered < 32usize && at < data.len {
            h.buffer[h.buffered] = data[at]
            h.buffered += 1usize
            at += 1usize
        }
        if h.buffered < 32usize { ret }
        xxh64_block(h, h.buffer[0..], 0usize)
        h.buffered = 0usize
    }
    while at + 32usize <= data.len {
        xxh64_block(h, data, at)
        at += 32usize
    }
    while at < data.len {
        h.buffer[h.buffered] = data[at]
        h.buffered += 1usize
        at += 1usize
    }
}

fn xxh64_done(h: *const Xxh64) -> u64 {
    var acc = 0u64
    if h.total >= 32u64 {
        acc = rotl64(h.v1, 1u32) +% rotl64(h.v2, 7u32) +% rotl64(h.v3, 12u32) +% rotl64(h.v4, 18u32)
        acc = xxh_merge(acc, h.v1)
        acc = xxh_merge(acc, h.v2)
        acc = xxh_merge(acc, h.v3)
        acc = xxh_merge(acc, h.v4)
    } else {
        acc = h.v3 +% PRIME5
    }
    acc +%= h.total
    var at = 0usize
    while at + 8usize <= h.buffered {
        acc = acc ^ xxh_round(0u64, load64(h.buffer[0..], at))
        acc = rotl64(acc, 27u32) *% PRIME1 +% PRIME4
        at += 8usize
    }
    if at + 4usize <= h.buffered {
        acc = acc ^ (u64(load32(h.buffer[0..], at)) *% PRIME1)
        acc = rotl64(acc, 23u32) *% PRIME2 +% PRIME3
        at += 4usize
    }
    while at < h.buffered {
        acc = acc ^ (u64(h.buffer[at]) *% PRIME5)
        acc = rotl64(acc, 11u32) *% PRIME1
        at += 1usize
    }
    acc = (acc ^ (acc >> 33u32)) *% PRIME2
    acc = (acc ^ (acc >> 29u32)) *% PRIME3
    ret acc ^ (acc >> 32u32)
}

// --- A backward bit stream: the last byte holds a sentinel one bit above the data.

type BackBits = struct { data: []const u8, at: usize, bits: u64, bit_count: u32, padded: u32 }

fn back_init(data: []const u8) -> (BackBits, err) {
    var b: BackBits = zero
    b.data = data
    if data.len == 0usize { ret (b, Invalid) }
    let last = data[data.len - 1usize]
    if last == 0u8 { ret (b, Invalid) }
    var top = 7u32
    while (last >> top) & 1u8 == 0u8 { top -= 1u32 }
    b.at = data.len - 1usize
    b.bits = u64(last & ((1u8 << top) - 1u8))
    b.bit_count = top
    ret (b, ok)
}

// Pulls whole bytes in from the front of the remaining data until `n` bits are held.
fn back_fill(b: *BackBits, n: u32) {
    while b.bit_count < n {
        if b.at == 0usize {
            // Past the start: zeros, counted so the end can be checked exactly.
            b.bits = b.bits << 8u32
            b.bit_count += 8u32
            b.padded += 8u32
            continue
        }
        b.at -= 1usize
        b.bits = (b.bits << 8u32) | u64(b.data[b.at])
        b.bit_count += 8u32
    }
}

fn back_peek(b: *BackBits, n: u32) -> u32 {
    if n == 0u32 { ret 0u32 }
    back_fill(b, n)
    ret u32((b.bits >> (b.bit_count - n)) & ((1u64 << n) - 1u64))
}

fn back_skip(b: *BackBits, n: u32) { b.bit_count -= n }

fn back_read(b: *BackBits, n: u32) -> u32 {
    let value = back_peek(b, n)
    back_skip(b, n)
    ret value
}

// Every real bit consumed and none of the padding: the stream ended exactly.
fn back_finished(b: *const BackBits) -> bool { ret b.at == 0usize && b.bit_count == b.padded }

// More bits consumed than the stream held.
fn back_overrun(b: *const BackBits) -> bool { ret b.bit_count < b.padded }

// --- A forward bit stream, for FSE table descriptions and Huffman weights.

type ForwardBits = struct { data: []const u8, at: usize, bits: u64, bit_count: u32 }

fn forward_init(data: []const u8) -> ForwardBits {
    ret ForwardBits { data: data, at: 0usize, bits: 0u64, bit_count: 0u32 }
}

fn forward_read(f: *ForwardBits, n: u32) -> u32 {
    while f.bit_count < n {
        var byte = 0u64
        if f.at < f.data.len { byte = u64(f.data[f.at]) }
        f.bits = f.bits | (byte << f.bit_count)
        f.at += 1usize
        f.bit_count += 8u32
    }
    let value = u32(f.bits & ((1u64 << n) - 1u64))
    f.bits = f.bits >> n
    f.bit_count -= n
    ret value
}

// Bytes consumed, rounding the partial byte up.
fn forward_used(f: *const ForwardBits) -> usize {
    ret f.at - usize(f.bit_count / 8u32)
}

// --- FSE decoding tables: per state a symbol, the bits to read and the baseline,
// laid out as four bytes an entry in a byte table.

fn table_symbol(table: []const u8, state: usize) -> u32 { ret u32(table[state * 4usize]) }
fn table_bits(table: []const u8, state: usize) -> u32 { ret u32(table[state * 4usize + 1usize]) }
fn table_base(table: []const u8, state: usize) -> u32 { ret u32(table[state * 4usize + 2usize]) | (u32(table[state * 4usize + 3usize]) << 8u32) }

fn table_set(table: []u8, state: usize, symbol: u32, bits: u32, base: u32) {
    table[state * 4usize] = u8(symbol)
    table[state * 4usize + 1usize] = u8(bits)
    table[state * 4usize + 2usize] = u8(base & 255u32)
    table[state * 4usize + 3usize] = u8(base >> 8u32)
}

fn highest_bit(v: u32) -> u32 {
    var n = 0u32
    var x = v
    while x > 1u32 {
        x = x >> 1u32
        n += 1u32
    }
    ret n
}

// Builds the decoding table from normalized counts: a -1 count is a "less than one"
// symbol taking one cell at the end of the table, reading `accuracy` bits with
// baseline zero; every other symbol is spread from position zero by the step,
// skipping the cells the low ones took (RFC 8878 4.1.1.2).
fn fse_build(table: []u8, counts: []const i32, symbols: usize, accuracy: u32) -> err {
    let size = 1usize << accuracy
    if size * 4usize > table.len { ret Invalid }
    var high = size - 1usize
    var spread: [512]u8 = zero
    var s = 0usize
    while s < symbols {
        if counts[s] == -1 {
            spread[high] = u8(s)
            high -= 1usize
        }
        s += 1usize
    }
    var position = 0usize
    let step = (size >> 1u32) + (size >> 3u32) + 3usize
    let mask = size - 1usize
    s = 0usize
    while s < symbols {
        var n = counts[s]
        while n > 0 {
            spread[position] = u8(s)
            position = (position + step) & mask
            while position > high { position = (position + step) & mask }
            n -= 1
        }
        s += 1usize
    }
    if position != 0usize { ret Invalid }
    // Each symbol's states in order get rising baselines and the bits to reach them.
    var next: [256]u32 = zero
    s = 0usize
    while s < symbols {
        if counts[s] > 0 { next[s] = u32(counts[s]) }
        if counts[s] == -1 { next[s] = 1u32 }
        s += 1usize
    }
    var state = 0usize
    while state < size {
        let symbol = usize(spread[state])
        let x = next[symbol]
        next[symbol] += 1u32
        let bits = accuracy - highest_bit(x)
        let base = (x << bits) - u32(size)
        table_set(table, state, u32(symbol), bits, base)
        state += 1usize
    }
    ret ok
}

// Reads a normalized count distribution (RFC 8878 4.1.1) into `counts`, returning
// the accuracy log and the number of symbols read; `data` is the block's bytes.
fn fse_read_counts(data: []const u8, counts: []i32, max_symbols: usize, max_accuracy: u32) -> (u32, usize, usize, err) {
    var f = forward_init(data)
    let accuracy = forward_read(&f, 4u32) + 5u32
    if accuracy > max_accuracy { ret (0u32, 0usize, 0usize, Invalid) }
    var remaining = i32(1u32 << accuracy) + 1
    var symbol = 0usize
    var previous_zero = false
    while remaining > 1 && symbol < max_symbols {
        if previous_zero {
            // A run of zero counts, two bits at a time, three meaning "more".
            var repeats = forward_read(&f, 2u32)
            while repeats == 3u32 {
                symbol += 3usize
                if symbol > max_symbols { ret (0u32, 0usize, 0usize, Invalid) }
                repeats = forward_read(&f, 2u32)
            }
            var z = 0u32
            while z < repeats {
                if symbol >= max_symbols { ret (0u32, 0usize, 0usize, Invalid) }
                counts[symbol] = 0
                symbol += 1usize
                z += 1u32
            }
            previous_zero = false
            continue
        }
        let max = u32(remaining)
        let threshold = 1u32 << highest_bit(max)
        let width = highest_bit(max) + 1u32
        var value = forward_read(&f, width - 1u32)
        let low_limit = (threshold << 1u32) - 1u32 - max
        if value >= low_limit {
            let extra = forward_read(&f, 1u32)
            value = value + (extra << (width - 1u32))
            if value >= threshold { value -= low_limit }
        }
        let count = i32(value) - 1
        counts[symbol] = count
        symbol += 1usize
        if count == -1 { remaining -= 1 } else { remaining -= count }
        previous_zero = count == 0
    }
    if remaining != 1 { ret (0u32, 0usize, 0usize, Invalid) }
    var fill = symbol
    while fill < max_symbols {
        counts[fill] = 0
        fill += 1usize
    }
    ret (accuracy, symbol, forward_used(&f), ok)
}

// --- Huffman literals: a table of 2^max_bits entries, two bytes each (symbol, bits).

type Huff = struct { table: []u8, max_bits: u32, valid: bool }

fn huff_build(h: *Huff, weights: []const u8, count: usize) -> err {
    // The last weight is implied by the sum of the others reaching a power of two.
    var sum = 0u32
    var i = 0usize
    while i < count {
        if weights[i] > 12u8 { ret Invalid }
        if weights[i] > 0u8 { sum += 1u32 << u32(weights[i] - 1u8) }
        i += 1usize
    }
    if sum == 0u32 { ret Invalid }
    let max_bits = highest_bit(sum) + 1u32
    let left = (1u32 << max_bits) - sum
    if left == 0u32 || (left & (left - 1u32)) != 0u32 { ret Invalid }
    var full: [256]u8 = zero
    i = 0usize
    while i < count {
        full[i] = weights[i]
        i += 1usize
    }
    full[count] = u8(highest_bit(left) + 1u32)
    let symbols = count + 1usize
    if max_bits > u32(HUFF_LOG_MAX) || symbols > 256usize { ret Invalid }
    // Bits per symbol, then the codes by rank: fewer bits fill the higher entries.
    var rank_count: [14]u32 = zero
    var bits: [256]usize = zero
    i = 0usize
    while i < symbols {
        if full[i] > 0u8 {
            bits[i] = usize(max_bits) + 1usize - usize(full[i])
            rank_count[bits[i]] += 1u32
        }
        i += 1usize
    }
    var rank_start: [14]u32 = zero
    var b = usize(max_bits)
    while b >= 1usize {
        rank_start[b] = rank_start[b + 1usize] + rank_count[b + 1usize] * (1u32 << u32(usize(max_bits) - b - 1usize))
        b -= 1usize
    }
    i = 0usize
    while i < symbols {
        if bits[i] > 0usize {
            let width = 1usize << u32(usize(max_bits) - bits[i])
            let code = usize(rank_start[bits[i]])
            var k = 0usize
            while k < width {
                h.table[(code + k) * 2usize] = u8(i)
                h.table[(code + k) * 2usize + 1usize] = u8(bits[i])
                k += 1usize
            }
            rank_start[bits[i]] += u32(width)
        }
        i += 1usize
    }
    h.max_bits = max_bits
    h.valid = true
    ret ok
}

// Reads a Huffman tree description into the table; returns the bytes it took.
fn huff_read(h: *Huff, data: []const u8, fse_scratch: []u8) -> (usize, err) {
    if data.len == 0usize { ret (0usize, Invalid) }
    let header = usize(data[0])
    var weights: [256]u8 = zero
    var count = 0usize
    var used = 1usize
    if header >= 128usize {
        count = header - 127usize
        let bytes = (count + 1usize) / 2usize
        if 1usize + bytes > data.len { ret (0usize, Invalid) }
        var i = 0usize
        while i < count {
            let byte = data[1usize + i / 2usize]
            if i % 2usize == 0usize { weights[i] = byte >> 4u8 } else { weights[i] = byte & 15u8 }
            i += 1usize
        }
        used += bytes
    } else {
        // FSE-compressed weights: a table over 0..12 at accuracy up to 6, then two
        // interleaved states read backward until the stream is spent.
        if 1usize + header > data.len { ret (0usize, Invalid) }
        let compressed = data[1usize..1usize + header]
        var counts: [64]i32 = zero
        let (accuracy, symbol_count, table_bytes, counts_error) = fse_read_counts(compressed, counts[0..], 13usize, 6u32)
        if counts_error != ok { ret (0usize, counts_error) }
        let build_error = fse_build(fse_scratch, counts[0..], symbol_count, accuracy)
        if build_error != ok { ret (0usize, build_error) }
        let (stream0, stream_error) = back_init(compressed[table_bytes..])
        if stream_error != ok { ret (0usize, stream_error) }
        var stream = stream0
        var even = usize(back_read(&stream, accuracy))
        var odd = usize(back_read(&stream, accuracy))
        if back_overrun(&stream) { ret (0usize, Invalid) }
        // Symbols alternate between the states; the update that reads past the
        // start of the stream ends it, with one more symbol from the other state.
        while true {
            if count >= 254usize { ret (0usize, Invalid) }
            weights[count] = u8(table_symbol(fse_scratch, even))
            count += 1usize
            even = usize(table_base(fse_scratch, even) + back_read(&stream, table_bits(fse_scratch, even)))
            if back_overrun(&stream) {
                weights[count] = u8(table_symbol(fse_scratch, odd))
                count += 1usize
                break
            }
            weights[count] = u8(table_symbol(fse_scratch, odd))
            count += 1usize
            odd = usize(table_base(fse_scratch, odd) + back_read(&stream, table_bits(fse_scratch, odd)))
            if back_overrun(&stream) {
                weights[count] = u8(table_symbol(fse_scratch, even))
                count += 1usize
                break
            }
        }
        used += header
    }
    let build_error = huff_build(h, weights[0..], count)
    if build_error != ok { ret (0usize, build_error) }
    ret (used, ok)
}

// Decodes one backward Huffman stream into `dst`, exactly `dst.len` symbols.
fn huff_stream(h: *const Huff, data: []const u8, dst: []u8) -> err {
    let (stream0, stream_error) = back_init(data)
    if stream_error != ok { ret stream_error }
    var stream = stream0
    var i = 0usize
    while i < dst.len {
        let index = usize(back_peek(&stream, h.max_bits))
        dst[i] = h.table[index * 2usize]
        back_skip(&stream, u32(h.table[index * 2usize + 1usize]))
        i += 1usize
    }
    if back_overrun(&stream) || !back_finished(&stream) { ret Invalid }
    ret ok
}

// --- Sequences: literal lengths, offsets and match lengths.

fn ll_base(code: u32) -> (u32, u32) {
    if code < 16u32 { ret (code, 0u32) }
    let bases: [20]u32 = [20]u32{ 16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536 }
    let extra: [20]u32 = [20]u32{ 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
    ret (bases[usize(code - 16u32)], extra[usize(code - 16u32)])
}

fn ml_base(code: u32) -> (u32, u32) {
    if code < 32u32 { ret (code + 3u32, 0u32) }
    let bases: [21]u32 = [21]u32{ 35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539 }
    let extra: [21]u32 = [21]u32{ 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
    ret (bases[usize(code - 32u32)], extra[usize(code - 32u32)])
}

fn default_ll(counts: []i32) -> usize {
    let values: [36]i32 = [36]i32{ 4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1 }
    var i = 0usize
    while i < 36usize {
        counts[i] = values[i]
        i += 1usize
    }
    ret 36usize
}

fn default_of(counts: []i32) -> usize {
    let values: [29]i32 = [29]i32{ 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1 }
    var i = 0usize
    while i < 29usize {
        counts[i] = values[i]
        i += 1usize
    }
    ret 29usize
}

fn default_ml(counts: []i32) -> usize {
    // 1, 4, 3, then 2 six times, then 1 up to code 45 and -1 for the seven past it
    // -- libzstd's table, checked against its decoder state by state.
    let head: [9]i32 = [9]i32{ 1, 4, 3, 2, 2, 2, 2, 2, 2 }
    var i = 0usize
    while i < 53usize {
        if i < 9usize { counts[i] = head[i] } else {
        if i < 46usize { counts[i] = 1 } else { counts[i] = -1 }
        }
        i += 1usize
    }
    ret 53usize
}

// One of the three sequence tables, with its accuracy and whether it is set.
type SeqTable = struct { table: []u8, accuracy: u32, valid: bool, rle_symbol: u32, rle: bool }

// Prepares a table by its mode from the section bytes; returns the bytes used.
fn seq_table_read(t: *SeqTable, mode: u32, data: []const u8, kind: u32, max_symbols: usize, max_accuracy: u32) -> (usize, err) {
    if mode == 0u32 {
        var counts: [64]i32 = zero
        var symbols = 0usize
        var accuracy = 6u32
        if kind == 0u32 { symbols = default_ll(counts[0..]) }
        if kind == 1u32 {
            symbols = default_of(counts[0..])
            accuracy = 5u32
        }
        if kind == 2u32 { symbols = default_ml(counts[0..]) }
        let build_error = fse_build(t.table, counts[0..], symbols, accuracy)
        if build_error != ok { ret (0usize, build_error) }
        t.accuracy = accuracy
        t.valid = true
        t.rle = false
        ret (0usize, ok)
    }
    if mode == 1u32 {
        if data.len < 1usize { ret (0usize, Invalid) }
        t.rle_symbol = u32(data[0])
        t.rle = true
        t.valid = true
        ret (1usize, ok)
    }
    if mode == 2u32 {
        var counts: [64]i32 = zero
        let (accuracy, symbols, used, counts_error) = fse_read_counts(data, counts[0..], max_symbols, max_accuracy)
        if counts_error != ok { ret (0usize, counts_error) }
        let build_error = fse_build(t.table, counts[0..], symbols, accuracy)
        if build_error != ok { ret (0usize, build_error) }
        t.accuracy = accuracy
        t.valid = true
        t.rle = false
        ret (used, ok)
    }
    if !t.valid { ret (0usize, Invalid) }
    ret (0usize, ok)
}

// --- The reader.

type State = struct {
    source: io.Reader,
    input: []u8,
    literals: []u8,
    history: []u8,
    hist_len: usize,
    out_at: usize,
    window_limit: usize,
    window: usize,
    huff: Huff,
    ll: SeqTable,
    of: SeqTable,
    ml: SeqTable,
    fse_scratch: []u8,
    rep: [3]u32,
    in_frame: bool,
    last_block: bool,
    has_checksum: bool,
    hash: Xxh64,
    finished: bool,
    output_limit: u64,
    output_total: u64,
    frame_left: u64,
    has_frame_size: bool,
}

fn reader_storage(window_limit: usize) -> (usize, err) {
    if window_limit == 0usize { ret (0usize, Invalid) }
    if window_limit > 134217728usize { ret (0usize, Unsupported) }
    ret (mem.size_of[State]() + 8usize + INPUT + BLOCK_MAX + window_limit + BLOCK_MAX + (1usize << HUFF_LOG_MAX) * 2usize + SEQ_TABLE * 4usize * 4usize, ok)
}

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err) {
    let fixed = mem.size_of[State]() + 8usize + INPUT + BLOCK_MAX + BLOCK_MAX + (1usize << HUFF_LOG_MAX) * 2usize + SEQ_TABLE * 4usize * 4usize
    if storage.len < fixed + 1024usize { ret (zero, io.TooSmall) }
    let s = mem.cast[*State](&storage[0])
    var at = mem.size_of[State]() + 8usize
    s.input = storage[at..at + INPUT]
    at += INPUT
    s.literals = storage[at..at + BLOCK_MAX]
    at += BLOCK_MAX
    s.huff.table = storage[at..at + (1usize << HUFF_LOG_MAX) * 2usize]
    at += (1usize << HUFF_LOG_MAX) * 2usize
    s.ll.table = storage[at..at + SEQ_TABLE * 4usize]
    at += SEQ_TABLE * 4usize
    s.of.table = storage[at..at + SEQ_TABLE * 4usize]
    at += SEQ_TABLE * 4usize
    s.ml.table = storage[at..at + SEQ_TABLE * 4usize]
    at += SEQ_TABLE * 4usize
    s.fse_scratch = storage[at..at + SEQ_TABLE * 4usize]
    at += SEQ_TABLE * 4usize
    s.history = storage[at..]
    s.window_limit = s.history.len - BLOCK_MAX
    s.hist_len = 0usize
    s.out_at = 0usize
    s.huff.valid = false
    s.ll.valid = false
    s.of.valid = false
    s.ml.valid = false
    s.source = source
    s.in_frame = false
    s.finished = false
    s.output_limit = output_limit
    s.output_total = 0u64
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// Exactly `n` bytes from the source into the input buffer; End at a frame boundary
// is reported as `io.End`, elsewhere as `Invalid`.
fn take(s: *State, n: usize) -> ([]u8, err) {
    if n > s.input.len { ret (zero, Invalid) }
    var filled = 0usize
    while filled < n {
        let (count, read_error) = io.read(&s.source, s.input[filled..n])
        if read_error == io.End || (read_error == ok && count == 0usize) {
            if filled == 0usize { ret (zero, io.End) }
            ret (zero, Invalid)
        }
        if read_error != ok { ret (zero, read_error) }
        filled += count
    }
    ret (s.input[..n], ok)
}

fn start_frame(s: *State) -> err {
    let (magic, magic_error) = take(s, 4usize)
    if magic_error != ok { ret magic_error }
    let value = load32(magic, 0usize)
    if value >= 407710288u32 && value <= 407710303u32 { ret Unsupported }
    if value != 4247762216u32 { ret Invalid }
    let (descriptor_bytes, descriptor_error) = take(s, 1usize)
    if descriptor_error != ok { ret Invalid }
    let descriptor = descriptor_bytes[0]
    let fcs_flag = descriptor >> 6u8
    let single = descriptor & 32u8 != 0u8
    if descriptor & 8u8 != 0u8 { ret Invalid }
    s.has_checksum = descriptor & 4u8 != 0u8
    let dict_flag = descriptor & 3u8
    if dict_flag != 0u8 { ret Unsupported }
    var window = 0u64
    if !single {
        let (wd, wd_error) = take(s, 1usize)
        if wd_error != ok { ret Invalid }
        let exponent = u32(wd[0] >> 3u8)
        let mantissa = u64(wd[0] & 7u8)
        let base = 1u64 << (10u32 + exponent)
        window = base + (base / 8u64) * mantissa
    }
    var fcs_size = 0usize
    if fcs_flag == 0u8 { if single { fcs_size = 1usize } }
    if fcs_flag == 1u8 { fcs_size = 2usize }
    if fcs_flag == 2u8 { fcs_size = 4usize }
    if fcs_flag == 3u8 { fcs_size = 8usize }
    s.has_frame_size = fcs_size > 0usize
    s.frame_left = 0u64
    if fcs_size > 0usize {
        let (fcs, fcs_error) = take(s, fcs_size)
        if fcs_error != ok { ret Invalid }
        var i = 0usize
        while i < fcs_size {
            s.frame_left = s.frame_left | (u64(fcs[i]) << u32(i * 8usize))
            i += 1usize
        }
        if fcs_size == 2usize { s.frame_left += 256u64 }
        if single { window = s.frame_left }
    }
    if window > u64(s.window_limit) { ret Unsupported }
    s.window = usize(window)
    s.rep[0] = 1u32
    s.rep[1] = 4u32
    s.rep[2] = 8u32
    s.hash = xxh64_init()
    s.huff.valid = false
    s.ll.valid = false
    s.of.valid = false
    s.ml.valid = false
    s.in_frame = true
    s.last_block = false
    ret ok
}

// Makes room for a block at the end of the history, keeping the window.
fn make_room(s: *State) {
    if s.hist_len + BLOCK_MAX <= s.history.len { ret }
    var keep = s.window
    if keep > s.hist_len { keep = s.hist_len }
    let from = s.hist_len - keep
    var i = 0usize
    while i < keep {
        s.history[i] = s.history[from + i]
        i += 1usize
    }
    s.hist_len = keep
    s.out_at = keep
}

// The literals section into `s.literals`; returns (regenerated size, bytes used).
fn read_literals(s: *State, block: []const u8) -> (usize, usize, err) {
    if block.len == 0usize { ret (0usize, 0usize, Invalid) }
    let kind = u32(block[0] & 3u8)
    let size_format = u32((block[0] >> 2u8) & 3u8)
    if kind == 0u32 || kind == 1u32 {
        var regen = 0usize
        var header = 1usize
        if size_format == 0u32 || size_format == 2u32 {
            regen = usize(block[0] >> 3u8)
        } else {
        if size_format == 1u32 {
            if block.len < 2usize { ret (0usize, 0usize, Invalid) }
            regen = usize(block[0] >> 4u8) | (usize(block[1]) << 4u32)
            header = 2usize
        } else {
            if block.len < 3usize { ret (0usize, 0usize, Invalid) }
            regen = usize(block[0] >> 4u8) | (usize(block[1]) << 4u32) | (usize(block[2]) << 12u32)
            header = 3usize
        }
        }
        if regen > BLOCK_MAX { ret (0usize, 0usize, Invalid) }
        if kind == 0u32 {
            if header + regen > block.len { ret (0usize, 0usize, Invalid) }
            mem.copy[u8](s.literals[..regen], block[header..header + regen])
            ret (regen, header + regen, ok)
        }
        if header + 1usize > block.len { ret (0usize, 0usize, Invalid) }
        var i = 0usize
        while i < regen {
            s.literals[i] = block[header]
            i += 1usize
        }
        ret (regen, header + 1usize, ok)
    }
    // Compressed or treeless: sizes, then the tree, then one or four streams.
    var header = 3usize
    var streams = 4usize
    var regen = 0usize
    var compressed = 0usize
    if size_format == 0u32 || size_format == 1u32 {
        if block.len < 3usize { ret (0usize, 0usize, Invalid) }
        let raw = usize(block[0]) | (usize(block[1]) << 8u32) | (usize(block[2]) << 16u32)
        regen = (raw >> 4u32) & 1023usize
        compressed = (raw >> 14u32) & 1023usize
        if size_format == 0u32 { streams = 1usize }
    } else {
    if size_format == 2u32 {
        if block.len < 4usize { ret (0usize, 0usize, Invalid) }
        let raw = usize(block[0]) | (usize(block[1]) << 8u32) | (usize(block[2]) << 16u32) | (usize(block[3]) << 24u32)
        regen = (raw >> 4u32) & 16383usize
        compressed = (raw >> 18u32) & 16383usize
        header = 4usize
    } else {
        if block.len < 5usize { ret (0usize, 0usize, Invalid) }
        let raw = usize(block[0]) | (usize(block[1]) << 8u32) | (usize(block[2]) << 16u32) | (usize(block[3]) << 24u32) | (usize(block[4]) << 32u32)
        regen = (raw >> 4u32) & 262143usize
        compressed = (raw >> 22u32) & 262143usize
        header = 5usize
    }
    }
    if regen > BLOCK_MAX || header + compressed > block.len { ret (0usize, 0usize, Invalid) }
    var body = block[header..header + compressed]
    if kind == 2u32 {
        let (tree_bytes, tree_error) = huff_read(&s.huff, body, s.fse_scratch)
        if tree_error != ok { ret (0usize, 0usize, tree_error) }
        body = body[tree_bytes..]
    } else {
        if !s.huff.valid { ret (0usize, 0usize, Invalid) }
    }
    if streams == 1usize {
        let stream_error = huff_stream(&s.huff, body, s.literals[..regen])
        if stream_error != ok { ret (0usize, 0usize, stream_error) }
        ret (regen, header + compressed, ok)
    }
    if body.len < 6usize { ret (0usize, 0usize, Invalid) }
    let size1 = usize(body[0]) | (usize(body[1]) << 8u32)
    let size2 = usize(body[2]) | (usize(body[3]) << 8u32)
    let size3 = usize(body[4]) | (usize(body[5]) << 8u32)
    if 6usize + size1 + size2 + size3 > body.len { ret (0usize, 0usize, Invalid) }
    let each = (regen + 3usize) / 4usize
    if each * 3usize > regen { ret (0usize, 0usize, Invalid) }
    var at = 6usize
    var out = 0usize
    var i = 0usize
    while i < 4usize {
        var size = body.len - at
        if i == 0usize { size = size1 }
        if i == 1usize { size = size2 }
        if i == 2usize { size = size3 }
        var count = each
        if i == 3usize { count = regen - each * 3usize }
        let stream_error = huff_stream(&s.huff, body[at..at + size], s.literals[out..out + count])
        if stream_error != ok { ret (0usize, 0usize, stream_error) }
        at += size
        out += count
        i += 1usize
    }
    ret (regen, header + compressed, ok)
}

fn seq_symbol(t: *const SeqTable, state: usize) -> u32 {
    if t.rle { ret t.rle_symbol }
    ret table_symbol(t.table, state)
}

// Decodes and executes the sequences of a compressed block, the literals already in
// place; appends to the history.
fn run_sequences(s: *State, block: []const u8, literal_count: usize) -> err {
    if block.len == 0usize { ret Invalid }
    var at = 0usize
    var count = usize(block[0])
    at = 1usize
    if count == 0usize {
        // Every literal goes out as it is.
        if s.hist_len + literal_count > s.history.len { ret Invalid }
        mem.copy[u8](s.history[s.hist_len..s.hist_len + literal_count], s.literals[..literal_count])
        s.hist_len += literal_count
        ret ok
    }
    if count >= 128usize {
        if count == 255usize {
            if block.len < 3usize { ret Invalid }
            count = usize(block[1]) | (usize(block[2]) << 8u32) + 32512usize
            at = 3usize
        } else {
            if block.len < 2usize { ret Invalid }
            count = ((count - 128usize) << 8u32) | usize(block[1])
            at = 2usize
        }
    }
    if at >= block.len { ret Invalid }
    let modes = block[at]
    at += 1usize
    if modes & 3u8 != 0u8 { ret Invalid }
    let (ll_used, ll_error) = seq_table_read(&s.ll, u32(modes >> 6u8), block[at..], 0u32, 36usize, 9u32)
    if ll_error != ok { ret ll_error }
    at += ll_used
    let (of_used, of_error) = seq_table_read(&s.of, u32((modes >> 4u8) & 3u8), block[at..], 1u32, 32usize, 8u32)
    if of_error != ok { ret of_error }
    at += of_used
    let (ml_used, ml_error) = seq_table_read(&s.ml, u32((modes >> 2u8) & 3u8), block[at..], 2u32, 53usize, 9u32)
    if ml_error != ok { ret ml_error }
    at += ml_used
    let (stream0, stream_error) = back_init(block[at..])
    if stream_error != ok { ret stream_error }
    var stream = stream0
    var ll_state = 0usize
    var of_state = 0usize
    var ml_state = 0usize
    if !s.ll.rle { ll_state = usize(back_read(&stream, s.ll.accuracy)) }
    if !s.of.rle { of_state = usize(back_read(&stream, s.of.accuracy)) }
    if !s.ml.rle { ml_state = usize(back_read(&stream, s.ml.accuracy)) }
    var literal_at = 0usize
    var i = 0usize
    while i < count {
        let of_code = seq_symbol(&s.of, of_state)
        if of_code > 31u32 { ret Invalid }
        let offset_value = (1u32 << of_code) + back_read(&stream, of_code)
        let ml_code = seq_symbol(&s.ml, ml_state)
        if ml_code > 52u32 { ret Invalid }
        let (ml_baseline, ml_bits) = ml_base(ml_code)
        let match_length = usize(ml_baseline + back_read(&stream, ml_bits))
        let ll_code = seq_symbol(&s.ll, ll_state)
        if ll_code > 35u32 { ret Invalid }
        let (ll_baseline, ll_bits) = ll_base(ll_code)
        let literal_length = usize(ll_baseline + back_read(&stream, ll_bits))
        if back_overrun(&stream) { ret Invalid }
        if i + 1usize < count {
            if !s.ll.rle { ll_state = usize(table_base(s.ll.table, ll_state) + back_read(&stream, table_bits(s.ll.table, ll_state))) }
            if !s.ml.rle { ml_state = usize(table_base(s.ml.table, ml_state) + back_read(&stream, table_bits(s.ml.table, ml_state))) }
            if !s.of.rle { of_state = usize(table_base(s.of.table, of_state) + back_read(&stream, table_bits(s.of.table, of_state))) }
            if back_overrun(&stream) { ret Invalid }
        }
        // The offset: past 3 it is the value less 3; else a repeat, shifted by a zero
        // literal length.
        var offset = 0u32
        if offset_value > 3u32 {
            offset = offset_value - 3u32
            s.rep[2] = s.rep[1]
            s.rep[1] = s.rep[0]
            s.rep[0] = offset
        } else {
            var index = offset_value - 1u32
            if literal_length == 0usize { index += 1u32 }
            if index == 0u32 {
                offset = s.rep[0]
            } else {
                if index == 3u32 { offset = s.rep[0] - 1u32 } else { offset = s.rep[usize(index)] }
                if offset == 0u32 { ret Invalid }
                if index >= 2u32 { s.rep[2] = s.rep[1] }
                s.rep[1] = s.rep[0]
                s.rep[0] = offset
            }
        }
        // Literals, then the match copied byte by byte so overlaps repeat.
        if literal_at + literal_length > literal_count { ret Invalid }
        if s.hist_len + literal_length + match_length > s.history.len { ret Invalid }
        mem.copy[u8](s.history[s.hist_len..s.hist_len + literal_length], s.literals[literal_at..literal_at + literal_length])
        literal_at += literal_length
        s.hist_len += literal_length
        if usize(offset) > s.hist_len { ret Invalid }
        var k = 0usize
        while k < match_length {
            s.history[s.hist_len] = s.history[s.hist_len - usize(offset)]
            s.hist_len += 1usize
            k += 1usize
        }
        i += 1usize
    }
    if !back_finished(&stream) { ret Invalid }
    // Whatever literals remain go out last.
    let rest = literal_count - literal_at
    if s.hist_len + rest > s.history.len { ret Invalid }
    mem.copy[u8](s.history[s.hist_len..s.hist_len + rest], s.literals[literal_at..literal_count])
    s.hist_len += rest
    ret ok
}

// Decodes the next block into the history; false when the frame ended (checksum
// checked) or the source ended at a frame boundary.
fn next_block(s: *State) -> (bool, err) {
    if !s.in_frame {
        let start_error = start_frame(s)
        if start_error == io.End { ret (false, ok) }
        if start_error != ok { ret (false, start_error) }
    }
    if s.last_block {
        if s.has_checksum {
            let (sum, sum_error) = take(s, 4usize)
            if sum_error != ok { ret (false, Invalid) }
            if load32(sum, 0usize) != u32(xxh64_done(&s.hash) & 4294967295u64) { ret (false, Checksum) }
        }
        if s.has_frame_size && s.frame_left != 0u64 { ret (false, Invalid) }
        s.in_frame = false
        let start_error = start_frame(s)
        if start_error == io.End { ret (false, ok) }
        if start_error != ok { ret (false, start_error) }
    }
    let (header, header_error) = take(s, 3usize)
    if header_error != ok { ret (false, Invalid) }
    let raw = usize(header[0]) | (usize(header[1]) << 8u32) | (usize(header[2]) << 16u32)
    s.last_block = raw & 1usize == 1usize
    let kind = (raw >> 1u32) & 3usize
    let size = raw >> 3u32
    if kind == 3usize { ret (false, Invalid) }
    make_room(s)
    let before = s.hist_len
    if kind == 0usize {
        if size > BLOCK_MAX { ret (false, Invalid) }
        let (data, data_error) = take(s, size)
        if data_error != ok { ret (false, Invalid) }
        mem.copy[u8](s.history[s.hist_len..s.hist_len + size], data)
        s.hist_len += size
    } else {
    if kind == 1usize {
        if size > BLOCK_MAX { ret (false, Invalid) }
        let (data, data_error) = take(s, 1usize)
        if data_error != ok { ret (false, Invalid) }
        let byte = data[0]
        var i = 0usize
        while i < size {
            s.history[s.hist_len + i] = byte
            i += 1usize
        }
        s.hist_len += size
    } else {
        if size > BLOCK_MAX { ret (false, Invalid) }
        let (data, data_error) = take(s, size)
        if data_error != ok { ret (false, Invalid) }
        let (literal_count, used, literals_error) = read_literals(s, data)
        if literals_error != ok { ret (false, literals_error) }
        let run_error = run_sequences(s, data[used..], literal_count)
        if run_error != ok { ret (false, run_error) }
        if s.hist_len - before > BLOCK_MAX { ret (false, Invalid) }
    }
    }
    let produced = u64(s.hist_len - before)
    if s.has_frame_size {
        if produced > s.frame_left { ret (false, Invalid) }
        s.frame_left -= produced
    }
    s.output_total += produced
    if s.output_total > s.output_limit { ret (false, Invalid) }
    if s.has_checksum { xxh64_update(&s.hash, s.history[before..s.hist_len]) }
    ret (true, ok)
}

fn read(r: *Reader, dst: []u8) -> (usize, err) {
    let s = mem.cast[*State](r.state)
    if s.finished { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    var written = 0usize
    while written < dst.len {
        if s.out_at == s.hist_len {
            let (more, block_error) = next_block(s)
            if block_error != ok { ret (written, block_error) }
            if !more {
                s.finished = true
                if written > 0usize { ret (written, ok) }
                ret (0usize, io.End)
            }
            continue
        }
        var take_count = s.hist_len - s.out_at
        if take_count > dst.len - written { take_count = dst.len - written }
        mem.copy[u8](dst[written..written + take_count], s.history[s.out_at..s.out_at + take_count])
        s.out_at += take_count
        written += take_count
    }
    ret (written, ok)
}

// --- The writer: raw blocks in one frame with a checksum.

type WriterState = struct { sink: io.Writer, buffer: []u8, buffered: usize, started: bool, finished: bool, hash: Xxh64 }

fn writer_storage(level: Level) -> usize {
    ret mem.size_of[WriterState]() + 8usize + BLOCK_MAX
}

fn writer(storage: []u8, sink: io.Writer, level: Level) -> (Writer, err) {
    if storage.len < writer_storage(level) { ret (zero, io.TooSmall) }
    let s = mem.cast[*WriterState](&storage[0])
    let at = mem.size_of[WriterState]() + 8usize
    s.buffer = storage[at..at + BLOCK_MAX]
    s.buffered = 0usize
    s.sink = sink
    s.started = false
    s.finished = false
    s.hash = xxh64_init()
    var w: Writer = zero
    w.state = mem.cast[*void](s)
    ret (w, ok)
}

// The frame header: no content size, a 128 KiB window, a checksum.
fn start_writer(s: *WriterState) -> err {
    if s.started { ret ok }
    s.started = true
    var header: [6]u8 = [6]u8{ 40, 181, 47, 253, 4, 56 }
    ret io.write_all(&s.sink, header[0..])
}

fn flush_block(s: *WriterState, last: bool) -> err {
    try start_writer(s)
    var header: [3]u8 = zero
    var raw = s.buffered << 3u32
    if last { raw = raw | 1usize }
    header[0] = u8(raw & 255usize)
    header[1] = u8((raw >> 8u32) & 255usize)
    header[2] = u8((raw >> 16u32) & 255usize)
    try io.write_all(&s.sink, header[0..])
    try io.write_all(&s.sink, s.buffer[..s.buffered])
    xxh64_update(&s.hash, s.buffer[..s.buffered])
    s.buffered = 0usize
    ret ok
}

fn write(w: *Writer, src: []const u8) -> (usize, err) {
    let s = mem.cast[*WriterState](w.state)
    if s.finished { ret (0usize, Invalid) }
    var at = 0usize
    while at < src.len {
        var take_count = BLOCK_MAX - s.buffered
        if take_count > src.len - at { take_count = src.len - at }
        mem.copy[u8](s.buffer[s.buffered..s.buffered + take_count], src[at..at + take_count])
        s.buffered += take_count
        at += take_count
        if s.buffered == BLOCK_MAX {
            let flush_error = flush_block(s, false)
            if flush_error != ok { ret (at, flush_error) }
        }
    }
    ret (src.len, ok)
}

fn finish(w: *Writer) -> err {
    let s = mem.cast[*WriterState](w.state)
    if s.finished { ret ok }
    try flush_block(s, true)
    let sum = u32(xxh64_done(&s.hash) & 4294967295u64)
    var trailer: [4]u8 = zero
    trailer[0] = u8(sum & 255u32)
    trailer[1] = u8((sum >> 8u32) & 255u32)
    trailer[2] = u8((sum >> 16u32) & 255u32)
    trailer[3] = u8(sum >> 24u32)
    try io.write_all(&s.sink, trailer[0..])
    s.finished = true
    ret io.flush(&s.sink)
}
