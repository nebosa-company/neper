// Raw DEFLATE (RFC 1951) both ways, resumable at any byte of input or output, over
// caller storage and no allocation. The decoder is a stage machine in the shape of
// zlib's puff: a 64-bit accumulator refilled from the input, every symbol decoded
// against the accumulator and committed only once all its bits are there, so a call
// that runs out of input or output leaves the state exactly where the next call
// resumes. Its output history is a ring of `window_limit` bytes and a distance past
// what was produced or past the ring is `Invalid`.
//
// The encoder keeps a 64 KiB buffer holding the last 32 KiB of input as history and
// slides it as input arrives, so a match reaches back across what the previous block
// covered. `Fast` collects 32 KiB and writes stored blocks. `Balanced` and `Best`
// run zlib's lazy matcher over a 15-bit hash chain (zlib levels 6 and 9: 128 and 1024
// candidates, lazy limits 16 and 258), buffer up to 16383 tokens, and write each block
// as the smallest of stored, fixed-Huffman and dynamic-Huffman, the dynamic trees
// length-limited to 15 bits. The encoder compresses into a staging area and drains
// that into the caller's output across calls.
//
// ponytail: a block's token count and 32 KiB span are the only split points (no
// entropy-driven split); storage is cast to the state struct, so it must be 8-aligned,
// as an arena allocation is.
use e.mem

type Encoder = struct { state: *void }
type Decoder = struct { state: *void }
type Level = enum u8 { Fast, Balanced, Best }
type Status = enum u8 { NeedInput, NeedOutput, Finished }
error Invalid
error TooLarge

const BLOCK: usize = 32768usize
// A block spans at most the 64 KiB buffer and is written as the smaller of stored
// (header, align, length words per 65535 bytes) and coded.
const STAGING: usize = 65600usize
const MAX_BITS: usize = 15usize
const CAP: usize = 65536usize
const WINDOW_SIZE: usize = 32768usize
const HASH_SIZE: usize = 32768usize
const TOKMAX: usize = 16383usize
const LOOKAHEAD: usize = 262usize

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
    tok_len: []u8,
    tok_dist: []u8,
    tok_count: usize,
    tok_pos: usize,
    block_start: usize,
    scan: usize,
    prev_len: usize,
    prev_dist: usize,
    match_avail: bool,
    block_lost: bool,
}

// Tables live in byte storage, two bytes an entry, little-endian.
fn get16(table: []const u8, index: usize) -> u32 {
    ret u32(table[index * 2usize]) | (u32(table[index * 2usize + 1usize]) << 8u32)
}

fn set16(table: []u8, index: usize, value: u32) {
    table[index * 2usize] = u8(value & 255u32)
    table[index * 2usize + 1usize] = u8((value >> 8u32) & 255u32)
}

// RFC 1951's length and distance tables follow one pattern, two bits of mantissa and a
// power of two, so each entry is arithmetic instead of a table built on every call.
// `index` is 0..28 for a length symbol and 0..29 for a distance symbol.
fn length_base(index: usize) -> u32 {
    if index < 8usize { ret u32(index) + 3u32 }
    if index >= 28usize { ret 258u32 }
    ret ((4u32 + u32(index & 3usize)) << u32((index >> 2u32) - 1usize)) + 3u32
}

fn length_extra(index: usize) -> u32 {
    if index < 8usize || index >= 28usize { ret 0u32 }
    ret u32((index >> 2u32) - 1usize)
}

fn dist_base(index: usize) -> u32 {
    if index < 4usize { ret u32(index) + 1u32 }
    ret ((2u32 + u32(index & 1usize)) << u32((index >> 1u32) - 1usize)) + 1u32
}

fn dist_extra(index: usize) -> u32 {
    if index < 4usize { ret 0u32 }
    ret u32((index >> 1u32) - 1usize)
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
    let blank: DecoderState = zero
    *s = blank
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
    ret mem.size_of[EncoderState]() + CAP + STAGING + HASH_SIZE * 4usize + TOKMAX * 3usize
}

fn encoder(storage: []u8, level: Level) -> (Encoder, err) {
    let needed = encoder_storage(level)
    if storage.len < needed { ret (zero, TooLarge) }
    let s = mem.cast[*EncoderState](&storage[0])
    let blank: EncoderState = zero
    *s = blank
    var at = mem.size_of[EncoderState]()
    s.level = level
    if level == .Fast {
        s.buffer = storage[at..at + BLOCK]
        at += BLOCK
        s.staging = storage[at..at + BLOCK + 8usize]
        at += BLOCK + 8usize
    } else {
        s.buffer = storage[at..at + CAP]
        at += CAP
        s.staging = storage[at..at + STAGING]
        at += STAGING
        s.head = storage[at..at + HASH_SIZE * 2usize]
        at += HASH_SIZE * 2usize
        s.prev = storage[at..at + HASH_SIZE * 2usize]
        at += HASH_SIZE * 2usize
        // Distances first: they are read as 16-bit words, so they sit on an even offset.
        s.tok_dist = storage[at..at + TOKMAX * 2usize]
        at += TOKMAX * 2usize
        s.tok_len = storage[at..at + TOKMAX]
        var h = 0usize
        while h < HASH_SIZE / 4usize {
            let hp = mem.cast[*u64](&s.head[h * 8usize])
            let pp = mem.cast[*u64](&s.prev[h * 8usize])
            *hp = 18446744073709551615u64
            *pp = 18446744073709551615u64
            h += 1usize
        }
        s.prev_len = 2usize
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

// dst[dst_at..dst_at + n] = src[src_at..src_at + n], eight bytes at a time. A forward copy,
// so a destination before an overlapping source is safe when they are 8 or more apart.
fn move_bytes(dst: []u8, dst_at: usize, src: []const u8, src_at: usize, n: usize) {
    if n == 0usize { ret }
    // The one bounds check: the last byte of each side.
    let tail_dst = dst[dst_at + n - 1usize]
    let tail_src = src[src_at + n - 1usize]
    var i = 0usize
    @nocheck {
    while i + 8usize <= n {
        *mem.cast[*u64](&dst[dst_at + i]) = *mem.cast[*u64](&src[src_at + i])
        i += 8usize
    }
    while i < n {
        dst[dst_at + i] = src[src_at + i]
        i += 1usize
    }
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

// A stored block of buffer[from..from + n], n at most 65535, from the current bit.
fn put_stored(s: *EncoderState, from: usize, n: usize, final: bool) {
    var header = 0u32
    if final { header = 1u32 }
    put_bits(s, header, 3u32)
    if s.bit_count > 0u32 { put_bits(s, 0u32, 8u32 - s.bit_count) }
    put_bits(s, u32(n) & 65535u32, 16u32)
    put_bits(s, (u32(n) ^ 65535u32) & 65535u32, 16u32)
    move_bytes(s.staging, s.staging_len, s.buffer, from, n)
    s.staging_len += n
}

// Length symbol index (0..28) of a match length 3..258, and distance symbol (0..29).
fn enc_len_code(length: u32) -> usize {
    if length >= 258u32 { ret 28usize }
    let l = length - 3u32
    if l < 8u32 { ret usize(l) }
    var hb = 3u32
    while (l >> (hb + 1u32)) != 0u32 { hb += 1u32 }
    ret usize(4u32 * hb - 4u32 + ((l >> (hb - 2u32)) & 3u32))
}

fn enc_dist_code(distance: u32) -> usize {
    let m = distance - 1u32
    if m < 4u32 { ret usize(m) }
    var hb = 2u32
    while (m >> (hb + 1u32)) != 0u32 { hb += 1u32 }
    ret usize(2u32 * hb + ((m >> (hb - 1u32)) & 1u32))
}

// Symbol lookups for a block: `lcode[length - 3]` is the length symbol index, and the
// distance symbol of `d` is `dcode[m]` for m = d - 1 under 256 and `dcode[256 + (m >> 7)]`
// above (every symbol boundary past 256 is a multiple of 128).
fn enc_tables(lcode: []u8, dcode: []u8) {
    var i = 0usize
    while i < 256usize {
        lcode[i] = u8(enc_len_code(u32(i) + 3u32))
        dcode[i] = u8(enc_dist_code(u32(i) + 1u32))
        i += 1usize
    }
    i = 2usize
    while i < 256usize {
        dcode[256usize + i] = u8(enc_dist_code(u32(i << 7u32) + 1u32))
        i += 1usize
    }
}

// Length-limited Huffman lengths for `n` weights: sorted leaves, a two-queue merge,
// depths clamped to `max_bits` and the Kraft sum repaired (miniz's method). Fewer
// than two used symbols are padded to two so the code is complete, as zlib does.
fn enc_lengths(freq: []const u32, n: usize, max_bits: u32, lens: []u8) {
    var order: [288]u32 = zero
    var used = 0usize
    var i = 0usize
    while i < n {
        lens[i] = 0u8
        if freq[i] > 0u32 {
            var j = used
            while j > 0usize && freq[usize(order[j - 1usize])] > freq[i] {
                order[j] = order[j - 1usize]
                j -= 1usize
            }
            order[j] = u32(i)
            used += 1usize
        }
        i += 1usize
    }
    if used < 2usize {
        var other = 0usize
        if used == 1usize && order[0] == 0u32 { other = 1usize }
        if used == 1usize { lens[usize(order[0])] = 1u8 }
        lens[other] = 1u8
        if used == 0usize { lens[1] = 1u8 }
        ret
    }
    var weight: [576]u32 = zero
    var parent: [576]u32 = zero
    var k = 0usize
    while k < used {
        weight[k] = freq[usize(order[k])]
        k += 1usize
    }
    var leaf = 0usize
    var inner = used
    var made = used
    while made < 2usize * used - 1usize {
        var pick: [2]usize = zero
        var p = 0usize
        while p < 2usize {
            if leaf < used && (inner >= made || weight[leaf] <= weight[inner]) {
                pick[p] = leaf
                leaf += 1usize
            } else {
                pick[p] = inner
                inner += 1usize
            }
            p += 1usize
        }
        weight[made] = weight[pick[0]] + weight[pick[1]]
        parent[pick[0]] = u32(made)
        parent[pick[1]] = u32(made)
        made += 1usize
    }
    // Depths, root downwards: a parent always has the larger index.
    weight[2usize * used - 2usize] = 0u32
    k = 2usize * used - 2usize
    while k > 0usize {
        k -= 1usize
        weight[k] = weight[usize(parent[k])] + 1u32
    }
    var count: [16]u32 = zero
    k = 0usize
    while k < used {
        var depth = weight[k]
        if depth > max_bits { depth = max_bits }
        count[usize(depth)] += 1u32
        k += 1usize
    }
    var total = 0u32
    var d = 1u32
    while d <= max_bits {
        total += count[usize(d)] << (max_bits - d)
        d += 1u32
    }
    while total != (1u32 << max_bits) {
        count[usize(max_bits)] -= 1u32
        var m = max_bits - 1u32
        while m > 0u32 {
            if count[usize(m)] != 0u32 {
                count[usize(m)] -= 1u32
                count[usize(m + 1u32)] += 2u32
                break
            }
            m -= 1u32
        }
        total -= 1u32
    }
    k = 0usize
    d = max_bits
    while d > 0u32 {
        var c = count[usize(d)]
        while c > 0u32 {
            lens[usize(order[k])] = u8(d)
            k += 1usize
            c -= 1u32
        }
        d -= 1u32
    }
}

// Canonical codes for `lens`, bit-reversed so they go out with `put_bits`.
fn enc_codes(lens: []const u8, n: usize, codes: []u32) {
    var per_length: [16]u32 = zero
    var next_code: [16]u32 = zero
    var i = 0usize
    while i < n {
        per_length[usize(lens[i])] += 1u32
        i += 1usize
    }
    per_length[0] = 0u32
    var code = 0u32
    var l = 1usize
    while l <= MAX_BITS {
        code = (code + per_length[l - 1usize]) << 1u32
        next_code[l] = code
        l += 1usize
    }
    i = 0usize
    while i < n {
        let w = usize(lens[i])
        if w != 0usize {
            codes[i] = reversed(next_code[w], u32(w))
            next_code[w] += 1u32
        }
        i += 1usize
    }
}

// The block's tokens, Huffman coded. The bits gather in a local 64-bit accumulator and go
// out four bytes at a time; each token adds at most 20 bits (a length symbol and its
// extra bits) and then at most 28 (a distance symbol and its extra bits) to under 32
// held, so the accumulator never overflows. A length's extra bits are its low bits
// (`length - 3` is the symbol's base plus the extra, the base a multiple of 2^extra), and
// a distance's are the low bits of `distance - 1`, so no base table is read.
fn enc_tokens(s: *EncoderState, lit_len: []const u8, lit_code: []const u32, dist_len: []const u8, dist_code: []const u32, lcode: []const u8, dcode: []const u8) {
    var acc = s.bits
    var nb = s.bit_count
    var at = s.staging_len
    let cap = s.staging.len
    let staging = s.staging
    let tok_len = s.tok_len
    let tok_dist = s.tok_dist
    let count = s.tok_count
    var t = 0usize
    @nocheck {
    while t < count {
        let dd = usize(*mem.cast[*u16](&tok_dist[t << 1u32]))
        let ln = usize(tok_len[t])
        if dd == 0usize {
            acc = acc | (u64(lit_code[ln]) << nb)
            nb += u32(lit_len[ln])
        } else {
            let lc = usize(lcode[ln])
            let sym = 257usize + lc
            var le = 0u32
            if lc >= 8usize && lc < 28usize { le = u32(lc >> 2u32) - 1u32 }
            let ll = u32(lit_len[sym])
            acc = acc | ((u64(lit_code[sym]) | (u64(u32(ln) & ((1u32 << le) - 1u32)) << ll)) << nb)
            nb += ll + le
            if nb >= 32u32 {
                if at + 4usize <= cap {
                    *mem.cast[*u32](&staging[at]) = u32(acc & 4294967295u64)
                    at += 4usize
                } else {
                    var k = 0usize
                    while k < 4usize {
                        staging[at] = u8((acc >> u32(k * 8usize)) & 255u64)
                        at += 1usize
                        k += 1usize
                    }
                }
                acc = acc >> 32u32
                nb -= 32u32
            }
            let m = dd - 1usize
            var di = m
            if m >= 256usize { di = 256usize + (m >> 7u32) }
            let dc = usize(dcode[di])
            var de = 0u32
            if dc >= 4usize { de = u32(dc >> 1u32) - 1u32 }
            let dl = u32(dist_len[dc])
            acc = acc | ((u64(dist_code[dc]) | (u64(u32(m) & ((1u32 << de) - 1u32)) << dl)) << nb)
            nb += dl + de
        }
        if nb >= 32u32 {
            if at + 4usize <= cap {
                *mem.cast[*u32](&staging[at]) = u32(acc & 4294967295u64)
                at += 4usize
            } else {
                var k = 0usize
                while k < 4usize {
                    staging[at] = u8((acc >> u32(k * 8usize)) & 255u64)
                    at += 1usize
                    k += 1usize
                }
            }
            acc = acc >> 32u32
            nb -= 32u32
        }
        t += 1usize
    }
    }
    acc = acc | (u64(lit_code[256]) << nb)
    nb += u32(lit_len[256])
    while nb >= 8u32 {
        staging[at] = u8(acc & 255u64)
        at += 1usize
        acc = acc >> 8u32
        nb -= 8u32
    }
    s.bits = acc
    s.bit_count = nb
    s.staging_len = at
}

// Writes the buffered tokens as one block: the smallest of stored, fixed and dynamic.
fn enc_flush(s: *EncoderState, final: bool) {
    var lit_freq: [288]u32 = zero
    var dist_freq: [32]u32 = zero
    var extra_bits = 0u32
    var dist_total = 0u32
    let span = s.tok_pos - s.block_start
    var lcode: [256]u8 = zero
    var dcode: [512]u8 = zero
    enc_tables(lcode[0..], dcode[0..])
    let tok_len = s.tok_len
    let tok_dist = s.tok_dist
    var t = 0usize
    @nocheck {
    while t < s.tok_count {
        let dd = usize(*mem.cast[*u16](&tok_dist[t << 1u32]))
        let ln = usize(tok_len[t])
        if dd == 0usize {
            lit_freq[ln] += 1u32
        } else {
            let m = dd - 1usize
            var di = m
            if m >= 256usize { di = 256usize + (m >> 7u32) }
            lit_freq[257usize + usize(lcode[ln])] += 1u32
            dist_freq[usize(dcode[di])] += 1u32
        }
        t += 1usize
    }
    }
    // The extra bits follow from the symbol counts.
    t = 0usize
    while t < 29usize {
        extra_bits += lit_freq[257usize + t] * length_extra(t)
        t += 1usize
    }
    t = 0usize
    while t < 30usize {
        extra_bits += dist_freq[t] * dist_extra(t)
        dist_total += dist_freq[t]
        t += 1usize
    }
    lit_freq[256] = 1u32
    var lit_len: [288]u8 = zero
    var dist_len: [32]u8 = zero
    enc_lengths(lit_freq[0..], 286usize, 15u32, lit_len[0..])
    enc_lengths(dist_freq[0..], 30usize, 15u32, dist_len[0..])
    var hlit = 286usize
    while hlit > 257usize && lit_len[hlit - 1usize] == 0u8 { hlit -= 1usize }
    var hdist = 30usize
    while hdist > 1usize && dist_len[hdist - 1usize] == 0u8 { hdist -= 1usize }
    // Run-length code the lengths of both trees as one sequence.
    var all: [320]u8 = zero
    var i = 0usize
    while i < hlit {
        all[i] = lit_len[i]
        i += 1usize
    }
    i = 0usize
    while i < hdist {
        all[hlit + i] = dist_len[i]
        i += 1usize
    }
    let total = hlit + hdist
    var cl_sym: [320]u8 = zero
    var cl_ext: [320]u8 = zero
    var cl_freq: [19]u32 = zero
    var cl_n = 0usize
    var cl_extra_bits = 0u32
    i = 0usize
    while i < total {
        let v = all[i]
        var run = 1usize
        while i + run < total && all[i + run] == v { run += 1usize }
        i += run
        if v == 0u8 {
            while run >= 3usize {
                if run >= 11usize {
                    var r = run
                    if r > 138usize { r = 138usize }
                    cl_sym[cl_n] = 18u8
                    cl_ext[cl_n] = u8(r - 11usize)
                    cl_extra_bits += 7u32
                    run -= r
                } else {
                    cl_sym[cl_n] = 17u8
                    cl_ext[cl_n] = u8(run - 3usize)
                    cl_extra_bits += 3u32
                    run = 0usize
                }
                cl_freq[usize(cl_sym[cl_n])] += 1u32
                cl_n += 1usize
            }
        } else {
            cl_sym[cl_n] = v
            cl_freq[usize(v)] += 1u32
            cl_n += 1usize
            run -= 1usize
            while run >= 3usize {
                var r = run
                if r > 6usize { r = 6usize }
                cl_sym[cl_n] = 16u8
                cl_ext[cl_n] = u8(r - 3usize)
                cl_extra_bits += 2u32
                cl_freq[16] += 1u32
                cl_n += 1usize
                run -= r
            }
        }
        while run > 0usize {
            cl_sym[cl_n] = v
            cl_freq[usize(v)] += 1u32
            cl_n += 1usize
            run -= 1usize
        }
    }
    var cl_len: [19]u8 = zero
    enc_lengths(cl_freq[0..], 19usize, 7u32, cl_len[0..])
    var hclen = 19usize
    while hclen > 4usize && cl_len[code_length_order(hclen - 1usize)] == 0u8 { hclen -= 1usize }
    // Sizes in bits.
    var dyn_bits = 3u32 + 14u32 + 3u32 * u32(hclen) + cl_extra_bits + extra_bits
    i = 0usize
    while i < 19usize {
        dyn_bits += cl_freq[i] * u32(cl_len[i])
        i += 1usize
    }
    var fixed_bits = 3u32 + extra_bits + dist_total * 5u32
    i = 0usize
    while i < 286usize {
        dyn_bits += lit_freq[i] * u32(lit_len[i])
        var w = 8u32
        if i >= 144usize { w = 9u32 }
        if i >= 256usize { w = 7u32 }
        if i >= 280usize { w = 8u32 }
        fixed_bits += lit_freq[i] * w
        i += 1usize
    }
    i = 0usize
    while i < 30usize {
        dyn_bits += dist_freq[i] * u32(dist_len[i])
        i += 1usize
    }
    let pad = (8u32 - ((s.bit_count + 3u32) & 7u32)) & 7u32
    let stored_bits = 3u32 + pad + 32u32 + 8u32 * u32(span)
    // A slide may have dropped the block's own bytes; then only coded blocks remain.
    if !s.block_lost && stored_bits <= fixed_bits && stored_bits <= dyn_bits {
        var from = s.block_start
        var left = span
        while left > 65535usize {
            put_stored(s, from, 65535usize, false)
            from += 65535usize
            left -= 65535usize
        }
        put_stored(s, from, left, final)
    } else {
        var header = 2u32
        if final { header = 3u32 }
        var lit_code: [288]u32 = zero
        var dist_code: [32]u32 = zero
        if fixed_bits <= dyn_bits {
            put_bits(s, header, 3u32)
            i = 0usize
            while i < 288usize {
                var w = 8u8
                if i >= 144usize { w = 9u8 }
                if i >= 256usize { w = 7u8 }
                if i >= 280usize { w = 8u8 }
                lit_len[i] = w
                i += 1usize
            }
            i = 0usize
            while i < 32usize {
                dist_len[i] = 5u8
                i += 1usize
            }
            enc_codes(lit_len[0..], 288usize, lit_code[0..])
            enc_codes(dist_len[0..], 32usize, dist_code[0..])
        } else {
            put_bits(s, header + 2u32, 3u32)
            put_bits(s, u32(hlit - 257usize), 5u32)
            put_bits(s, u32(hdist - 1usize), 5u32)
            put_bits(s, u32(hclen - 4usize), 4u32)
            i = 0usize
            while i < hclen {
                put_bits(s, u32(cl_len[code_length_order(i)]), 3u32)
                i += 1usize
            }
            var cl_code: [19]u32 = zero
            enc_codes(cl_len[0..], 19usize, cl_code[0..])
            i = 0usize
            while i < cl_n {
                let sym = usize(cl_sym[i])
                put_bits(s, cl_code[sym], u32(cl_len[sym]))
                if sym == 16usize { put_bits(s, u32(cl_ext[i]), 2u32) }
                if sym == 17usize { put_bits(s, u32(cl_ext[i]), 3u32) }
                if sym == 18usize { put_bits(s, u32(cl_ext[i]), 7u32) }
                i += 1usize
            }
            enc_codes(lit_len[0..], 286usize, lit_code[0..])
            enc_codes(dist_len[0..], 30usize, dist_code[0..])
        }
        enc_tokens(s, lit_len[0..], lit_code[0..], dist_len[0..], dist_code[0..], lcode[0..], dcode[0..])
    }
    s.block_start = s.tok_pos
    s.block_lost = false
    s.tok_count = 0usize
}

// The hash of three bytes is zlib's, ((a << 10) ^ (b << 5) ^ c) & 32767, so the
// chains hold the candidates zlib's do; `enc_run` computes it inline and rolling.
// Runs the lazy matcher over buffered input. 0: needs more input, 1: wrote a block
// into staging, 2: every byte is tokenised (only when `finish`). The state is held
// in locals across the loop and stored back on the way out.
fn enc_run(s: *EncoderState, finish: bool) -> u32 {
    var chain = 128usize
    var good = 8usize
    var max_lazy = 16usize
    var nice = 128usize
    if s.level == .Best {
        chain = 1024usize
        good = 32usize
        max_lazy = 258usize
        nice = 258usize
    }
    let buf = s.buffer
    let head = s.head
    let prev = s.prev
    let tok_len = s.tok_len
    let tok_dist = s.tok_dist
    let blen = s.buffer_len
    var scan = s.scan
    var count = s.tok_count
    var tok_pos = s.tok_pos
    var prev_len = s.prev_len
    var prev_dist = s.prev_dist
    var pending = s.match_avail
    var status = 0u32
    // Every index below is inside the buffer by construction: a position is under
    // `buffer_len` (at most CAP), a candidate is a position before it, a hash slot is a
    // 15-bit value times two, and a token index is under TOKMAX. The block is the
    // matcher's whole cost, so the per-access checks go.
    @nocheck {
    while true {
        if count >= TOKMAX {
            status = 1u32
            break
        }
        let i = scan
        let avail = blen - i
        if avail < LOOKAHEAD && !finish { break }
        if avail == 0usize {
            if pending {
                tok_len[count] = buf[i - 1usize]
                *mem.cast[*u16](&tok_dist[count << 1u32]) = 0u16
                count += 1usize
                tok_pos = i
                pending = false
            }
            status = 2u32
            break
        }
        var cur_len = 2usize
        var cur_dist = 0usize
        if avail >= 3usize {
            // zlib's hash of the three bytes, ((a << 10) ^ (b << 5) ^ c) & 32767, taken from
            // one four-byte load and scaled by two for the 16-bit slot.
            let w = usize(*mem.cast[*u32](&buf[i]))
            let hslot = mem.cast[*u16](&head[(((w & 255usize) << 11u32) ^ ((w & 65280usize) >> 2u32) ^ ((w >> 15u32) & 510usize)) & 65534usize])
            let first = usize(*hslot)
            *mem.cast[*u16](&prev[(i & 32767usize) << 1u32]) = *hslot
            *hslot = u16(i)
            var limit_len = avail
            if limit_len > 258usize { limit_len = 258usize }
            if first != 65535usize && prev_len < max_lazy && prev_len < limit_len && i - first <= WINDOW_SIZE {
                var steps = chain
                if prev_len >= good { steps = steps >> 2u32 }
                var best_len = prev_len
                var best_dist = 0usize
                var nice_len = nice
                if nice_len > limit_len { nice_len = limit_len }
                var candidate = first
                let first_byte = buf[i]
                let end_at = i + limit_len
                while true {
                    if buf[candidate + best_len] == buf[i + best_len] && buf[candidate] == first_byte {
                        var ca = candidate + 1usize
                        var cb = i + 1usize
                        // Eight bytes at a time while they agree, then bytewise.
                        while cb + 8usize <= end_at {
                            if *mem.cast[*u64](&buf[ca]) != *mem.cast[*u64](&buf[cb]) { break }
                            ca += 8usize
                            cb += 8usize
                        }
                        while cb < end_at && buf[ca] == buf[cb] {
                            ca += 1usize
                            cb += 1usize
                        }
                        let length = cb - i
                        if length > best_len {
                            best_len = length
                            best_dist = i - candidate
                            if length >= nice_len { break }
                        }
                    }
                    steps -= 1usize
                    if steps == 0usize { break }
                    let next = usize(*mem.cast[*u16](&prev[(candidate & 32767usize) << 1u32]))
                    if next == 65535usize || next >= candidate || i - next > WINDOW_SIZE { break }
                    candidate = next
                }
                if best_dist != 0usize && !(best_len == 3usize && best_dist > 4096usize) {
                    cur_len = best_len
                    cur_dist = best_dist
                }
            }
        }
        if prev_len >= 3usize && cur_len <= prev_len {
            tok_len[count] = u8(prev_len - 3usize)
            *mem.cast[*u16](&tok_dist[count << 1u32]) = u16(prev_dist)
            count += 1usize
            let end = i - 1usize + prev_len
            tok_pos = end
            var k = i + 1usize
            var stop = end
            if stop > blen - 2usize { stop = blen - 2usize }
            if k < stop {
                // Rolling hash: each step brings in one byte.
                var roll = ((usize(buf[k]) << 5u32) ^ usize(buf[k + 1usize])) & 32767usize
                while k < stop {
                    roll = ((roll << 5u32) ^ usize(buf[k + 2usize])) & 32767usize
                    let head_slot = mem.cast[*u16](&head[roll << 1u32])
                    *mem.cast[*u16](&prev[(k & 32767usize) << 1u32]) = *head_slot
                    *head_slot = u16(k)
                    k += 1usize
                }
            }
            scan = end
            pending = false
            prev_len = 2usize
        } else {
            if pending {
                tok_len[count] = buf[i - 1usize]
                *mem.cast[*u16](&tok_dist[count << 1u32]) = 0u16
                count += 1usize
                tok_pos = i
            }
            pending = true
            prev_len = cur_len
            prev_dist = cur_dist
            scan = i + 1usize
        }
    }
    }
    s.scan = scan
    s.tok_count = count
    s.tok_pos = tok_pos
    s.prev_len = prev_len
    s.prev_dist = prev_dist
    s.match_avail = pending
    if status == 1u32 { enc_flush(s, false) }
    ret status
}

// Drops the oldest input, keeping a full window before the scan point.
fn enc_slide(s: *EncoderState) {
    // A whole window, so the ring slots of `prev` (position mod 32768) stay valid.
    let shift = WINDOW_SIZE
    var kept = s.block_start
    if shift > kept {
        s.block_lost = true
        kept = shift
    }
    // The halves of the buffer do not overlap: shift is half of it.
    move_bytes(s.buffer, 0usize, s.buffer, shift, s.buffer_len - shift)
    // Every 16-bit slot v becomes v - 32768 when it is a position in the kept half
    // (v >= 32768, v != 65535) and 65535 (none) otherwise, four slots to a word:
    // `m` is v without its top bit, `ff` marks m == 32767, and a slot is kept when its
    // top bit is set and it is not 65535.
    let ones = 281479271743489u64
    let low15 = 9223231297218904063u64
    var i = 0usize
    @nocheck {
    while i < HASH_SIZE / 4usize {
        let hp = mem.cast[*u64](&s.head[i * 8usize])
        let hv = *hp
        let hm = hv & low15
        let hk = ((hv >> 15u32) & ones) & (ones ^ (((hm + ones) >> 15u32) & ones))
        let hmask = hk * 65535u64
        *hp = (hm & hmask) | (18446744073709551615u64 ^ hmask)
        let pp = mem.cast[*u64](&s.prev[i * 8usize])
        let pv = *pp
        let pm = pv & low15
        let pk = ((pv >> 15u32) & ones) & (ones ^ (((pm + ones) >> 15u32) & ones))
        let pmask = pk * 65535u64
        *pp = (pm & pmask) | (18446744073709551615u64 ^ pmask)
        i += 1usize
    }
    }
    s.buffer_len -= shift
    s.scan -= shift
    s.tok_pos -= shift
    s.block_start = kept - shift
}

// `Fast`: the collected block as one stored block.
fn compress_block(s: *EncoderState, final: bool) {
    put_stored(s, 0usize, s.buffer_len, final)
    s.buffer_len = 0usize
}

fn drain(s: *EncoderState, output: []u8, written: usize) -> usize {
    var take = s.staging_len - s.staging_at
    if output.len - written < take { take = output.len - written }
    move_bytes(output, written, s.staging, s.staging_at, take)
    s.staging_at += take
    let count = written + take
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
        if s.level == .Fast {
            if s.buffer_len == BLOCK {
                compress_block(s, false)
                continue
            }
            if consumed < input.len {
                var take = BLOCK - s.buffer_len
                if input.len - consumed < take { take = input.len - consumed }
                move_bytes(s.buffer, s.buffer_len, input, consumed, take)
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
        if consumed < input.len && s.buffer_len < CAP {
            var take = CAP - s.buffer_len
            if input.len - consumed < take { take = input.len - consumed }
            move_bytes(s.buffer, s.buffer_len, input, consumed, take)
            s.buffer_len += take
            consumed += take
            continue
        }
        let step = enc_run(s, finish && consumed == input.len)
        if step == 1u32 { continue }
        if step == 2u32 {
            enc_flush(s, true)
            if s.bit_count > 0u32 { put_bits(s, 0u32, 8u32 - s.bit_count) }
            s.finished = true
            continue
        }
        if s.buffer_len == CAP {
            enc_slide(s)
            continue
        }
        ret (consumed, written, .NeedInput, ok)
    }
}
