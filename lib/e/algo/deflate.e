// Raw DEFLATE (RFC 1951) both ways, resumable at any byte of input or output, over
// caller storage and no allocation. The decoder is a stage machine in the shape of
// zlib's puff: a 64-bit accumulator refilled from the input, every symbol decoded
// against the accumulator and committed only once all its bits are there, so a call
// that runs out of input or output leaves the state exactly where the next call
// resumes. Its output history is a ring of `window_limit` bytes and a distance past
// what was produced or past the ring is `Invalid`.
//
// The encoder collects input into a 32 KiB block, compresses it into a staging area
// and drains that into the caller's output across calls. `Fast` writes stored
// blocks; `Balanced` and `Best` write fixed-Huffman blocks over an LZ77 hash chain
// (16 and 256 candidates deep) within the block. Dynamic Huffman blocks are decoded
// but never written.
//
// ponytail: matches never cross a block boundary and there is no lazy matching; a
// dynamic-tree writer is the upgrade if ratio matters. Storage is cast to the state
// struct, so it must be 8-aligned, as an arena allocation is.
use e.mem

type Encoder = struct { state: *void }
type Decoder = struct { state: *void }
type Level = enum u8 { Fast, Balanced, Best }
type Status = enum u8 { NeedInput, NeedOutput, Finished }
error Invalid
error TooLarge

const BLOCK: usize = 32768usize
// A block of literals at nine bits each, plus the header and the end code.
const STAGING: usize = 36992usize
const HEAD: usize = 4096usize
const MAX_BITS: usize = 15usize

type DecoderState = struct {
    window: []u8,
    window_pos: usize,
    produced: u64,
    bits: u64,
    bit_count: u32,
    stage: u32,
    final_block: bool,
    remaining: usize,
    hlit: usize,
    hdist: usize,
    hclen: usize,
    index: usize,
    copy_len: usize,
    copy_dist: usize,
    in_at: usize,
    lengths: []u8,
    cl_count: []u8,
    cl_symbol: []u8,
    lit_count: []u8,
    lit_symbol: []u8,
    dist_count: []u8,
    dist_symbol: []u8,
}

type EncoderState = struct {
    level: Level,
    buffer: []u8,
    buffer_len: usize,
    staging: []u8,
    staging_len: usize,
    staging_at: usize,
    bits: u64,
    bit_count: u32,
    finished: bool,
    head: []u8,
    prev: []u8,
}

// Tables live in byte storage, two bytes an entry, little-endian.
fn get16(table: []const u8, index: usize) -> u32 {
    ret u32(table[index * 2usize]) | (u32(table[index * 2usize + 1usize]) << 8u32)
}

fn set16(table: []u8, index: usize, value: u32) {
    table[index * 2usize] = u8(value & 255u32)
    table[index * 2usize + 1usize] = u8((value >> 8u32) & 255u32)
}

fn length_base(index: usize) -> u32 {
    let table: [29]u32 = [29]u32{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
    ret table[index]
}

fn length_extra(index: usize) -> u32 {
    let table: [29]u32 = [29]u32{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
    ret table[index]
}

fn dist_base(index: usize) -> u32 {
    let table: [30]u32 = [30]u32{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
    ret table[index]
}

fn dist_extra(index: usize) -> u32 {
    let table: [30]u32 = [30]u32{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
    ret table[index]
}

fn code_length_order(index: usize) -> usize {
    let table: [19]u8 = [19]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }
    ret usize(table[index])
}

// --- Canonical Huffman tables: count[len] and the symbols sorted by code.

// Builds the table from `n` code lengths; returns the number of unused codes (zero for
// a complete code), negative when over-subscribed.
fn construct(count: []u8, symbol: []u8, lengths: []const u8, n: usize) -> i32 {
    var len = 0usize
    while len <= MAX_BITS {
        set16(count, len, 0u32)
        len += 1usize
    }
    var sym = 0usize
    while sym < n {
        let l = usize(lengths[sym])
        set16(count, l, get16(count, l) + 1u32)
        sym += 1usize
    }
    if get16(count, 0usize) == u32(n) { ret 0 }
    var left = 1i32
    len = 1usize
    while len <= MAX_BITS {
        left = left << 1u32
        left -= i32(get16(count, len))
        if left < 0 { ret left }
        len += 1usize
    }
    var offs: [16]u32 = zero
    len = 1usize
    while len < MAX_BITS {
        offs[len + 1usize] = offs[len] + get16(count, len)
        len += 1usize
    }
    sym = 0usize
    while sym < n {
        if lengths[sym] != 0u8 {
            let l = usize(lengths[sym])
            set16(symbol, usize(offs[l]), u32(sym))
            offs[l] += 1u32
        }
        sym += 1usize
    }
    ret left
}

// Decodes one symbol against the accumulator without committing: (symbol, bits used,
// outcome) where the outcome is 0 for a symbol, 1 for more bits needed, 2 for no code.
fn decode_symbol(bits: u64, bit_count: u32, count: []const u8, symbol: []const u8) -> (u32, u32, u32) {
    var code = 0i32
    var first = 0i32
    var index = 0i32
    var buf = bits
    var len = 1u32
    while len <= u32(MAX_BITS) {
        if len > bit_count { ret (0u32, 0u32, 1u32) }
        code = code | i32(buf & 1u64)
        buf = buf >> 1u32
        let c = i32(get16(count, usize(len)))
        if code - c < first { ret (get16(symbol, usize(index + (code - first))), len, 0u32) }
        index += c
        first += c
        first = first << 1u32
        code = code << 1u32
        len += 1u32
    }
    ret (0u32, 0u32, 2u32)
}

fn decoder_storage(window_limit: usize) -> (usize, err) {
    if window_limit == 0usize { ret (0usize, Invalid) }
    if window_limit > 1073741824usize { ret (0usize, TooLarge) }
    ret (mem.size_of[DecoderState]() + window_limit + 320usize + 32usize + 38usize + 32usize + 576usize + 32usize + 64usize, ok)
}

fn decoder(storage: []u8, window_limit: usize) -> (Decoder, err) {
    let (needed, needed_error) = decoder_storage(window_limit)
    if needed_error != ok { ret (zero, needed_error) }
    if storage.len < needed { ret (zero, TooLarge) }
    let s = mem.cast[*DecoderState](&storage[0])
    var at = mem.size_of[DecoderState]()
    s.window = storage[at..at + window_limit]
    at += window_limit
    s.lengths = storage[at..at + 320usize]
    at += 320usize
    s.cl_count = storage[at..at + 32usize]
    at += 32usize
    s.cl_symbol = storage[at..at + 38usize]
    at += 38usize
    s.lit_count = storage[at..at + 32usize]
    at += 32usize
    s.lit_symbol = storage[at..at + 576usize]
    at += 576usize
    s.dist_count = storage[at..at + 32usize]
    at += 32usize
    s.dist_symbol = storage[at..at + 64usize]
    s.window_pos = 0usize
    s.produced = 0u64
    s.bits = 0u64
    s.bit_count = 0u32
    s.stage = 0u32
    s.final_block = false
    s.remaining = 0usize
    s.index = 0usize
    s.copy_len = 0usize
    s.copy_dist = 0usize
    s.in_at = 0usize
    var d: Decoder = zero
    d.state = mem.cast[*void](s)
    ret (d, ok)
}

fn refill(s: *DecoderState, input: []const u8) {
    while s.bit_count <= 56u32 && s.in_at < input.len {
        s.bits = s.bits | (u64(input[s.in_at]) << s.bit_count)
        s.bit_count += 8u32
        s.in_at += 1usize
    }
}

fn commit(s: *DecoderState, n: u32) {
    s.bits = s.bits >> n
    s.bit_count -= n
}

fn take_bits(s: *DecoderState, n: u32) -> u32 {
    let value = u32(s.bits & ((1u64 << n) - 1u64))
    commit(s, n)
    ret value
}

fn emit(s: *DecoderState, output: []u8, written: usize, byte: u8) {
    s.window[s.window_pos] = byte
    s.window_pos += 1usize
    if s.window_pos == s.window.len { s.window_pos = 0usize }
    s.produced += 1u64
    output[written] = byte
}

fn fixed_tables(s: *DecoderState) {
    var sym = 0usize
    while sym < 144usize {
        s.lengths[sym] = 8u8
        sym += 1usize
    }
    while sym < 256usize {
        s.lengths[sym] = 9u8
        sym += 1usize
    }
    while sym < 280usize {
        s.lengths[sym] = 7u8
        sym += 1usize
    }
    while sym < 288usize {
        s.lengths[sym] = 8u8
        sym += 1usize
    }
    let unused_lit = construct(s.lit_count, s.lit_symbol, s.lengths, 288usize)
    sym = 0usize
    while sym < 30usize {
        s.lengths[sym] = 5u8
        sym += 1usize
    }
    let unused_dist = construct(s.dist_count, s.dist_symbol, s.lengths, 30usize)
}

// One step of the stage machine: (bytes written this step, status or -1 to continue).
// `written` is where the output cursor stands.
fn decode(d: *Decoder, input: []const u8, output: []u8, finish: bool) -> (usize, usize, Status, err) {
    let s = mem.cast[*DecoderState](d.state)
    s.in_at = 0usize
    var written = 0usize
    while true {
        if s.stage == 8u32 { ret (s.in_at, written, .Finished, ok) }
        refill(s, input)
        let starved = s.in_at >= input.len
        if s.stage == 0u32 {
            if s.bit_count < 3u32 {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            s.final_block = take_bits(s, 1u32) == 1u32
            let kind = take_bits(s, 2u32)
            if kind == 0u32 {
                commit(s, s.bit_count % 8u32)
                s.stage = 1u32
            } else {
            if kind == 1u32 {
                fixed_tables(s)
                s.stage = 6u32
            } else {
            if kind == 2u32 {
                s.stage = 3u32
            } else {
                ret (s.in_at, written, .NeedInput, Invalid)
            }
            }
            }
            continue
        }
        if s.stage == 1u32 {
            if s.bit_count < 32u32 {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            let length = take_bits(s, 16u32)
            let check = take_bits(s, 16u32)
            if length != (check ^ 65535u32) { ret (s.in_at, written, .NeedInput, Invalid) }
            s.remaining = usize(length)
            s.stage = 2u32
            continue
        }
        if s.stage == 2u32 {
            if s.remaining == 0usize {
                if s.final_block { s.stage = 8u32 } else { s.stage = 0u32 }
                continue
            }
            if written >= output.len { ret (s.in_at, written, .NeedOutput, ok) }
            var byte = 0u8
            if s.bit_count >= 8u32 {
                byte = u8(take_bits(s, 8u32))
            } else {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                byte = input[s.in_at]
                s.in_at += 1usize
            }
            emit(s, output, written, byte)
            written += 1usize
            s.remaining -= 1usize
            continue
        }
        if s.stage == 3u32 {
            if s.bit_count < 14u32 {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            s.hlit = usize(take_bits(s, 5u32)) + 257usize
            s.hdist = usize(take_bits(s, 5u32)) + 1usize
            s.hclen = usize(take_bits(s, 4u32)) + 4usize
            if s.hlit > 286usize || s.hdist > 30usize { ret (s.in_at, written, .NeedInput, Invalid) }
            var i = 0usize
            while i < 19usize {
                s.lengths[i] = 0u8
                i += 1usize
            }
            s.index = 0usize
            s.stage = 4u32
            continue
        }
        if s.stage == 4u32 {
            if s.index < s.hclen {
                if s.bit_count < 3u32 {
                    if starved {
                        if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                        ret (s.in_at, written, .NeedInput, ok)
                    }
                    continue
                }
                s.lengths[code_length_order(s.index)] = u8(take_bits(s, 3u32))
                s.index += 1usize
                continue
            }
            if construct(s.cl_count, s.cl_symbol, s.lengths, 19usize) != 0 { ret (s.in_at, written, .NeedInput, Invalid) }
            s.index = 0usize
            s.stage = 5u32
            continue
        }
        if s.stage == 5u32 {
            if s.index < s.hlit + s.hdist {
                let (sym, used, outcome) = decode_symbol(s.bits, s.bit_count, s.cl_count, s.cl_symbol)
                if outcome == 2u32 { ret (s.in_at, written, .NeedInput, Invalid) }
                var extra = 0u32
                if sym == 16u32 { extra = 2u32 }
                if sym == 17u32 { extra = 3u32 }
                if sym == 18u32 { extra = 7u32 }
                if outcome == 1u32 || s.bit_count < used + extra {
                    if starved {
                        if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                        ret (s.in_at, written, .NeedInput, ok)
                    }
                    continue
                }
                commit(s, used)
                if sym < 16u32 {
                    s.lengths[s.index] = u8(sym)
                    s.index += 1usize
                    continue
                }
                var repeat = 0usize
                var value = 0u8
                if sym == 16u32 {
                    if s.index == 0usize { ret (s.in_at, written, .NeedInput, Invalid) }
                    value = s.lengths[s.index - 1usize]
                    repeat = 3usize + usize(take_bits(s, 2u32))
                }
                if sym == 17u32 { repeat = 3usize + usize(take_bits(s, 3u32)) }
                if sym == 18u32 { repeat = 11usize + usize(take_bits(s, 7u32)) }
                if s.index + repeat > s.hlit + s.hdist { ret (s.in_at, written, .NeedInput, Invalid) }
                while repeat > 0usize {
                    s.lengths[s.index] = value
                    s.index += 1usize
                    repeat -= 1usize
                }
                continue
            }
            if s.lengths[256] == 0u8 { ret (s.in_at, written, .NeedInput, Invalid) }
            let lit_left = construct(s.lit_count, s.lit_symbol, s.lengths, s.hlit)
            if lit_left < 0 || (lit_left > 0 && s.hlit != usize(get16(s.lit_count, 0usize) + get16(s.lit_count, 1usize))) { ret (s.in_at, written, .NeedInput, Invalid) }
            let dist_left = construct(s.dist_count, s.dist_symbol, s.lengths[s.hlit..], s.hdist)
            if dist_left < 0 || (dist_left > 0 && s.hdist != usize(get16(s.dist_count, 0usize) + get16(s.dist_count, 1usize))) { ret (s.in_at, written, .NeedInput, Invalid) }
            s.stage = 6u32
            continue
        }
        if s.stage == 6u32 {
            let (sym, used, outcome) = decode_symbol(s.bits, s.bit_count, s.lit_count, s.lit_symbol)
            if outcome == 2u32 { ret (s.in_at, written, .NeedInput, Invalid) }
            if outcome == 1u32 {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            if sym < 256u32 {
                if written >= output.len { ret (s.in_at, written, .NeedOutput, ok) }
                commit(s, used)
                emit(s, output, written, u8(sym))
                written += 1usize
                continue
            }
            if sym == 256u32 {
                commit(s, used)
                if s.final_block {
                    commit(s, s.bit_count % 8u32)
                    s.stage = 8u32
                } else {
                    s.stage = 0u32
                }
                continue
            }
            let length_index = usize(sym - 257u32)
            if length_index >= 29usize { ret (s.in_at, written, .NeedInput, Invalid) }
            let length_bits = length_extra(length_index)
            var total = used + length_bits
            if s.bit_count < total {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            let length = length_base(length_index) + u32((s.bits >> used) & ((1u64 << length_bits) - 1u64))
            let (dsym, dused, doutcome) = decode_symbol(s.bits >> total, s.bit_count - total, s.dist_count, s.dist_symbol)
            if doutcome == 2u32 { ret (s.in_at, written, .NeedInput, Invalid) }
            if doutcome == 1u32 {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            if dsym >= 30u32 { ret (s.in_at, written, .NeedInput, Invalid) }
            let dist_bits = dist_extra(usize(dsym))
            if s.bit_count < total + dused + dist_bits {
                if starved {
                    if finish { ret (s.in_at, written, .NeedInput, Invalid) }
                    ret (s.in_at, written, .NeedInput, ok)
                }
                continue
            }
            let distance = dist_base(usize(dsym)) + u32((s.bits >> (total + dused)) & ((1u64 << dist_bits) - 1u64))
            total += dused + dist_bits
            if u64(distance) > s.produced || usize(distance) > s.window.len { ret (s.in_at, written, .NeedInput, Invalid) }
            commit(s, total)
            s.copy_len = usize(length)
            s.copy_dist = usize(distance)
            s.stage = 7u32
            continue
        }
        if s.stage == 7u32 {
            while s.copy_len > 0usize {
                if written >= output.len { ret (s.in_at, written, .NeedOutput, ok) }
                var from = s.window_pos + s.window.len - s.copy_dist
                if from >= s.window.len { from -= s.window.len }
                emit(s, output, written, s.window[from])
                written += 1usize
                s.copy_len -= 1usize
            }
            s.stage = 6u32
            continue
        }
        ret (s.in_at, written, .NeedInput, Invalid)
    }
}

// The whole bytes the accumulator read past the end of a finished stream, in stream
// order, handed back to a framing reader that needs its trailer; at most seven. Not
// part of the fence: `e.fmt.zlib` and `e.fmt.gzip` call it.
fn leftover(d: *Decoder, dst: []u8) -> usize {
    let s = mem.cast[*DecoderState](d.state)
    var count = 0usize
    while s.bit_count >= 8u32 && count < dst.len {
        dst[count] = u8(s.bits & 255u64)
        commit(s, 8u32)
        count += 1usize
    }
    ret count
}

// --- The encoder.

fn encoder_storage(level: Level) -> usize {
    if level == .Fast { ret mem.size_of[EncoderState]() + BLOCK + BLOCK + 8usize }
    ret mem.size_of[EncoderState]() + BLOCK + STAGING + HEAD * 2usize + BLOCK * 2usize
}

fn encoder(storage: []u8, level: Level) -> (Encoder, err) {
    let needed = encoder_storage(level)
    if storage.len < needed { ret (zero, TooLarge) }
    let s = mem.cast[*EncoderState](&storage[0])
    var at = mem.size_of[EncoderState]()
    s.level = level
    s.buffer = storage[at..at + BLOCK]
    at += BLOCK
    if level == .Fast {
        s.staging = storage[at..at + BLOCK + 8usize]
        at += BLOCK + 8usize
    } else {
        s.staging = storage[at..at + STAGING]
        at += STAGING
        s.head = storage[at..at + HEAD * 2usize]
        at += HEAD * 2usize
        s.prev = storage[at..at + BLOCK * 2usize]
    }
    s.buffer_len = 0usize
    s.staging_len = 0usize
    s.staging_at = 0usize
    s.bits = 0u64
    s.bit_count = 0u32
    s.finished = false
    var e: Encoder = zero
    e.state = mem.cast[*void](s)
    ret (e, ok)
}

fn put_bits(s: *EncoderState, value: u32, n: u32) {
    s.bits = s.bits | (u64(value) << s.bit_count)
    s.bit_count += n
    while s.bit_count >= 8u32 {
        s.staging[s.staging_len] = u8(s.bits & 255u64)
        s.staging_len += 1usize
        s.bits = s.bits >> 8u32
        s.bit_count -= 8u32
    }
}

// Huffman codes go out most significant bit first.
fn reversed(code: u32, n: u32) -> u32 {
    var out = 0u32
    var c = code
    var i = 0u32
    while i < n {
        out = (out << 1u32) | (c & 1u32)
        c = c >> 1u32
        i += 1u32
    }
    ret out
}

fn put_literal(s: *EncoderState, sym: u32) {
    if sym < 144u32 {
        put_bits(s, reversed(48u32 + sym, 8u32), 8u32)
    } else {
    if sym < 256u32 {
        put_bits(s, reversed(400u32 + sym - 144u32, 9u32), 9u32)
    } else {
    if sym < 280u32 {
        put_bits(s, reversed(sym - 256u32, 7u32), 7u32)
    } else {
        put_bits(s, reversed(192u32 + sym - 280u32, 8u32), 8u32)
    }
    }
    }
}

fn put_match(s: *EncoderState, length: u32, distance: u32) {
    var li = 28usize
    while length_base(li) > length { li -= 1usize }
    put_literal(s, 257u32 + u32(li))
    if length_extra(li) > 0u32 { put_bits(s, length - length_base(li), length_extra(li)) }
    var di = 29usize
    while dist_base(di) > distance { di -= 1usize }
    put_bits(s, reversed(u32(di), 5u32), 5u32)
    if dist_extra(di) > 0u32 { put_bits(s, distance - dist_base(di), dist_extra(di)) }
}

fn hash3(buffer: []const u8, at: usize) -> usize {
    let key = (u32(buffer[at]) << 16u32) | (u32(buffer[at + 1usize]) << 8u32) | u32(buffer[at + 2usize])
    ret usize((key * 2654435761u32) >> 20u32) & (HEAD - 1usize)
}

fn compress_block(s: *EncoderState, final: bool) {
    let n = s.buffer_len
    if s.level == .Fast {
        // Stored: header, align, LEN, NLEN, the bytes.
        var header = 0u32
        if final { header = 1u32 }
        put_bits(s, header, 3u32)
        if s.bit_count > 0u32 { put_bits(s, 0u32, 8u32 - s.bit_count) }
        put_bits(s, u32(n) & 65535u32, 16u32)
        put_bits(s, (u32(n) ^ 65535u32) & 65535u32, 16u32)
        var i = 0usize
        while i < n {
            s.staging[s.staging_len] = s.buffer[i]
            s.staging_len += 1usize
            i += 1usize
        }
        s.buffer_len = 0usize
        ret
    }
    var header = 2u32
    if final { header = 3u32 }
    put_bits(s, header, 3u32)
    var chain_limit = 16usize
    if s.level == .Best { chain_limit = 256usize }
    var i = 0usize
    while i < HEAD {
        set16(s.head, i, 65535u32)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var best_len = 0usize
        var best_dist = 0usize
        if i + 3usize <= n {
            let h = hash3(s.buffer, i)
            var candidate = usize(get16(s.head, h))
            var steps = 0usize
            while candidate != 65535usize && steps < chain_limit {
                let distance = i - candidate
                if distance > 32768usize { break }
                var length = 0usize
                let limit_len = n - i
                while length < 258usize && length < limit_len && s.buffer[candidate + length] == s.buffer[i + length] { length += 1usize }
                if length > best_len {
                    best_len = length
                    best_dist = distance
                    if length == 258usize { break }
                }
                let next = usize(get16(s.prev, candidate))
                if next == 65535usize || next >= candidate { break }
                candidate = next
                steps += 1usize
            }
            set16(s.prev, i, u32(get16(s.head, h)))
            set16(s.head, h, u32(i))
        }
        if best_len >= 3usize {
            put_match(s, u32(best_len), u32(best_dist))
            // Enter the covered positions into the chain as well.
            var k = i + 1usize
            while k < i + best_len {
                if k + 3usize <= n {
                    let h = hash3(s.buffer, k)
                    set16(s.prev, k, u32(get16(s.head, h)))
                    set16(s.head, h, u32(k))
                }
                k += 1usize
            }
            i += best_len
        } else {
            put_literal(s, u32(s.buffer[i]))
            i += 1usize
        }
    }
    put_literal(s, 256u32)
    s.buffer_len = 0usize
}

fn drain(s: *EncoderState, output: []u8, written: usize) -> usize {
    var count = written
    while s.staging_at < s.staging_len && count < output.len {
        output[count] = s.staging[s.staging_at]
        s.staging_at += 1usize
        count += 1usize
    }
    if s.staging_at == s.staging_len {
        s.staging_at = 0usize
        s.staging_len = 0usize
    }
    ret count
}

fn encode(e: *Encoder, input: []const u8, output: []u8, finish: bool) -> (usize, usize, Status, err) {
    let s = mem.cast[*EncoderState](e.state)
    var consumed = 0usize
    var written = 0usize
    while true {
        written = drain(s, output, written)
        if s.staging_len > 0usize { ret (consumed, written, .NeedOutput, ok) }
        if s.finished { ret (consumed, written, .Finished, ok) }
        if s.buffer_len == BLOCK {
            compress_block(s, false)
            continue
        }
        if consumed < input.len {
            var take = BLOCK - s.buffer_len
            if input.len - consumed < take { take = input.len - consumed }
            mem.copy[u8](s.buffer[s.buffer_len..s.buffer_len + take], input[consumed..consumed + take])
            s.buffer_len += take
            consumed += take
            continue
        }
        if finish {
            compress_block(s, true)
            if s.bit_count > 0u32 { put_bits(s, 0u32, 8u32 - s.bit_count) }
            s.finished = true
            continue
        }
        ret (consumed, written, .NeedInput, ok)
    }
}
