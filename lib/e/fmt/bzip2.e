// bzip2 decompression, bounded: a pull reader that takes the stream header, then
// block by block the Huffman-coded MTF/RLE2 symbols into the `tt` array, inverts the
// Burrows-Wheeler transform with the origin pointer, and undoes the first-stage run
// length coding while producing bytes on demand -- the inverse transform is walked
// as `read` asks, so a block never needs an output buffer of its own. Each block's
// CRC (the MSB-first CRC-32 bzip2 uses) and the stream's combined CRC are checked;
// a mismatch is `Checksum`. A block larger than `block_limit`, or output past
// `output_limit`, is `TooLarge`; a randomised block, a bad magic, a code length out
// of range or a run past the block is `Invalid`. Storage is `storage_required`
// bytes and holds the state, a 4 KiB input buffer and four bytes per block byte.
// Compression is not written, as the fence says.
use e.io
use e.mem

type Reader = struct { state: *void }
error Invalid
error Checksum
error TooLarge

const BUFFER: usize = 4096usize
const MAX_CODE_BITS: usize = 20usize
const MAX_GROUPS: usize = 6usize
const MAX_ALPHA: usize = 258usize
const MAX_SELECTORS: usize = 18002usize

type State = struct {
    source: io.Reader,
    input: []u8,
    in_at: usize,
    in_len: usize,
    bits: u64,
    bit_count: u32,
    tt: []u8,
    block_limit: usize,
    block_size: usize,
    started: bool,
    finished: bool,
    stream_done: bool,
    // The block being produced.
    nblock: usize,
    t_pos: usize,
    produced: usize,
    block_crc: u32,
    expected_crc: u32,
    combined_crc: u32,
    last_byte: u32,
    run: u32,
    repeat_left: u32,
    in_block: bool,
    output_limit: u64,
    output_total: u64,
    // Scratch for decoding one block, in storage.
    lengths: []u8,
    counts: []u8,
    symbols: []u8,
    selectors: []u8,
    seq_to_unseq: []u8,
    mtf: []u8,
    cftab: []u8,
}

fn storage_required(block_limit: usize) -> (usize, err) {
    if block_limit == 0usize { ret (0usize, Invalid) }
    if block_limit > 900000usize { ret (0usize, TooLarge) }
    let scratch = MAX_GROUPS * MAX_ALPHA + MAX_GROUPS * (MAX_CODE_BITS + 1usize) * 2usize + MAX_GROUPS * MAX_ALPHA * 2usize + MAX_SELECTORS + 256usize + 256usize + 257usize * 4usize
    ret (mem.size_of[State]() + 8usize + BUFFER + block_limit * 4usize + scratch, ok)
}

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err) {
    // The block limit is whatever the storage holds beyond the fixed parts.
    let fixed = mem.size_of[State]() + 8usize + BUFFER + MAX_GROUPS * MAX_ALPHA + MAX_GROUPS * (MAX_CODE_BITS + 1usize) * 2usize + MAX_GROUPS * MAX_ALPHA * 2usize + MAX_SELECTORS + 256usize + 256usize + 257usize * 4usize
    if storage.len < fixed + 4usize { ret (zero, io.TooSmall) }
    let s = mem.cast[*State](&storage[0])
    var at = mem.size_of[State]() + 8usize
    s.input = storage[at..at + BUFFER]
    at += BUFFER
    s.lengths = storage[at..at + MAX_GROUPS * MAX_ALPHA]
    at += MAX_GROUPS * MAX_ALPHA
    s.counts = storage[at..at + MAX_GROUPS * (MAX_CODE_BITS + 1usize) * 2usize]
    at += MAX_GROUPS * (MAX_CODE_BITS + 1usize) * 2usize
    s.symbols = storage[at..at + MAX_GROUPS * MAX_ALPHA * 2usize]
    at += MAX_GROUPS * MAX_ALPHA * 2usize
    s.selectors = storage[at..at + MAX_SELECTORS]
    at += MAX_SELECTORS
    s.seq_to_unseq = storage[at..at + 256usize]
    at += 256usize
    s.mtf = storage[at..at + 256usize]
    at += 256usize
    s.cftab = storage[at..at + 257usize * 4usize]
    at += 257usize * 4usize
    let block_limit = (storage.len - at) / 4usize
    s.tt = storage[at..at + block_limit * 4usize]
    s.block_limit = block_limit
    s.source = source
    s.in_at = 0usize
    s.in_len = 0usize
    s.bits = 0u64
    s.bit_count = 0u32
    s.started = false
    s.finished = false
    s.stream_done = false
    s.in_block = false
    s.combined_crc = 0u32
    s.output_limit = output_limit
    s.output_total = 0u64
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

fn get32(table: []const u8, index: usize) -> u32 {
    ret u32(table[index * 4usize]) | (u32(table[index * 4usize + 1usize]) << 8u32) | (u32(table[index * 4usize + 2usize]) << 16u32) | (u32(table[index * 4usize + 3usize]) << 24u32)
}

fn set32(table: []u8, index: usize, value: u32) {
    table[index * 4usize] = u8(value & 255u32)
    table[index * 4usize + 1usize] = u8((value >> 8u32) & 255u32)
    table[index * 4usize + 2usize] = u8((value >> 16u32) & 255u32)
    table[index * 4usize + 3usize] = u8(value >> 24u32)
}

fn get16(table: []const u8, index: usize) -> u32 {
    ret u32(table[index * 2usize]) | (u32(table[index * 2usize + 1usize]) << 8u32)
}

fn set16(table: []u8, index: usize, value: u32) {
    table[index * 2usize] = u8(value & 255u32)
    table[index * 2usize + 1usize] = u8((value >> 8u32) & 255u32)
}

// --- Bits, most significant first.

fn take_bits(s: *State, n: u32) -> (u32, err) {
    while s.bit_count < n {
        if s.in_at == s.in_len {
            let (count, read_error) = io.read(&s.source, s.input)
            if read_error == io.End || (read_error == ok && count == 0usize) { ret (0u32, Invalid) }
            if read_error != ok { ret (0u32, read_error) }
            s.in_at = 0usize
            s.in_len = count
        }
        s.bits = (s.bits << 8u32) | u64(s.input[s.in_at])
        s.in_at += 1usize
        s.bit_count += 8u32
    }
    let value = u32((s.bits >> (s.bit_count - n)) & ((1u64 << n) - 1u64))
    s.bit_count -= n
    ret (value, ok)
}

// The MSB-first CRC-32 with polynomial 0x04c11db7, one byte at a time.
fn crc_byte(crc: u32, byte: u32) -> u32 {
    var value = crc ^ (byte << 24u32)
    var i = 0usize
    while i < 8usize {
        if value & 2147483648u32 != 0u32 {
            value = (value << 1u32) ^ 79764919u32
        } else {
            value = value << 1u32
        }
        i += 1usize
    }
    ret value
}

// Canonical tables for one group from its code lengths: count[len], symbols by code.
fn construct(counts: []u8, symbols: []u8, lengths: []const u8, n: usize) -> bool {
    var len = 0usize
    while len <= MAX_CODE_BITS {
        set16(counts, len, 0u32)
        len += 1usize
    }
    var sym = 0usize
    while sym < n {
        let l = usize(lengths[sym])
        set16(counts, l, get16(counts, l) + 1u32)
        sym += 1usize
    }
    var left = 1i32
    len = 1usize
    while len <= MAX_CODE_BITS {
        left = left << 1u32
        left -= i32(get16(counts, len))
        if left < 0 { ret false }
        len += 1usize
    }
    var offs: [22]u32 = zero
    len = 1usize
    while len < MAX_CODE_BITS {
        offs[len + 1usize] = offs[len] + get16(counts, len)
        len += 1usize
    }
    sym = 0usize
    while sym < n {
        if lengths[sym] != 0u8 {
            let l = usize(lengths[sym])
            set16(symbols, usize(offs[l]), u32(sym))
            offs[l] += 1u32
        }
        sym += 1usize
    }
    ret true
}

fn decode_symbol(s: *State, group: usize) -> (u32, err) {
    let counts = s.counts[group * (MAX_CODE_BITS + 1usize) * 2usize..(group + 1usize) * (MAX_CODE_BITS + 1usize) * 2usize]
    let symbols = s.symbols[group * MAX_ALPHA * 2usize..(group + 1usize) * MAX_ALPHA * 2usize]
    var code = 0i32
    var first = 0i32
    var index = 0i32
    var len = 1usize
    while len <= MAX_CODE_BITS {
        let (bit, bit_error) = take_bits(s, 1u32)
        if bit_error != ok { ret (0u32, bit_error) }
        code = code | i32(bit)
        let c = i32(get16(counts, len))
        if code - c < first { ret (get16(symbols, usize(index + (code - first))), ok) }
        index += c
        first += c
        first = first << 1u32
        code = code << 1u32
        len += 1usize
    }
    ret (0u32, Invalid)
}

// Reads the stream header once and then one block's worth of symbols into `tt`;
// false when the end-of-stream marker was read instead.
fn load_block(s: *State) -> (bool, err) {
    if !s.started {
        let (magic, magic_error) = take_bits(s, 24u32)
        if magic_error != ok { ret (false, magic_error) }
        if magic != 4348520u32 { ret (false, Invalid) }
        let (level, level_error) = take_bits(s, 8u32)
        if level_error != ok { ret (false, level_error) }
        if level < 49u32 || level > 57u32 { ret (false, Invalid) }
        s.block_size = usize(level - 48u32) * 100000usize
        if s.block_size > s.block_limit { ret (false, TooLarge) }
        s.started = true
    }
    let (high, high_error) = take_bits(s, 24u32)
    if high_error != ok { ret (false, high_error) }
    let (low, low_error) = take_bits(s, 24u32)
    if low_error != ok { ret (false, low_error) }
    if high == 1536581u32 && low == 3690640u32 {
        // End of stream: the combined CRC.
        let (crc, crc_error) = take_bits(s, 32u32)
        if crc_error != ok { ret (false, crc_error) }
        if crc != s.combined_crc { ret (false, Checksum) }
        ret (false, ok)
    }
    if high != 3227993u32 || low != 2511705u32 { ret (false, Invalid) }
    let (expected, expected_error) = take_bits(s, 32u32)
    if expected_error != ok { ret (false, expected_error) }
    s.expected_crc = expected
    let (randomised, randomised_error) = take_bits(s, 1u32)
    if randomised_error != ok { ret (false, randomised_error) }
    if randomised != 0u32 { ret (false, Invalid) }
    let (orig_ptr, orig_error) = take_bits(s, 24u32)
    if orig_error != ok { ret (false, orig_error) }
    // The symbol map.
    let (used_map, used_error) = take_bits(s, 16u32)
    if used_error != ok { ret (false, used_error) }
    var n_in_use = 0usize
    var i = 0usize
    while i < 16usize {
        if used_map & (32768u32 >> u32(i)) != 0u32 {
            let (row, row_error) = take_bits(s, 16u32)
            if row_error != ok { ret (false, row_error) }
            var j = 0usize
            while j < 16usize {
                if row & (32768u32 >> u32(j)) != 0u32 {
                    s.seq_to_unseq[n_in_use] = u8(i * 16usize + j)
                    n_in_use += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    if n_in_use == 0usize { ret (false, Invalid) }
    let alpha_size = n_in_use + 2usize
    // Groups and selectors.
    let (n_groups, groups_error) = take_bits(s, 3u32)
    if groups_error != ok { ret (false, groups_error) }
    if n_groups < 2u32 || n_groups > 6u32 { ret (false, Invalid) }
    let (n_selectors, selectors_error) = take_bits(s, 15u32)
    if selectors_error != ok { ret (false, selectors_error) }
    if n_selectors < 1u32 { ret (false, Invalid) }
    var order: [6]u8 = zero
    i = 0usize
    while i < usize(n_groups) {
        order[i] = u8(i)
        i += 1usize
    }
    i = 0usize
    while i < usize(n_selectors) {
        var j = 0usize
        while true {
            let (bit, bit_error) = take_bits(s, 1u32)
            if bit_error != ok { ret (false, bit_error) }
            if bit == 0u32 { break }
            j += 1usize
            if j >= usize(n_groups) { ret (false, Invalid) }
        }
        // Move-to-front over the group order.
        let chosen = order[j]
        while j > 0usize {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[0] = chosen
        if i < MAX_SELECTORS { s.selectors[i] = chosen }
        i += 1usize
    }
    if usize(n_selectors) > MAX_SELECTORS { ret (false, Invalid) }
    // Code lengths per group, delta coded.
    var group = 0usize
    while group < usize(n_groups) {
        let (start, start_error) = take_bits(s, 5u32)
        if start_error != ok { ret (false, start_error) }
        var current = i32(start)
        var sym = 0usize
        while sym < alpha_size {
            while true {
                if current < 1 || current > 20 { ret (false, Invalid) }
                let (more, more_error) = take_bits(s, 1u32)
                if more_error != ok { ret (false, more_error) }
                if more == 0u32 { break }
                let (direction, direction_error) = take_bits(s, 1u32)
                if direction_error != ok { ret (false, direction_error) }
                if direction == 0u32 { current += 1 } else { current -= 1 }
            }
            s.lengths[group * MAX_ALPHA + sym] = u8(current)
            sym += 1usize
        }
        let counts = s.counts[group * (MAX_CODE_BITS + 1usize) * 2usize..(group + 1usize) * (MAX_CODE_BITS + 1usize) * 2usize]
        let symbols = s.symbols[group * MAX_ALPHA * 2usize..(group + 1usize) * MAX_ALPHA * 2usize]
        if !construct(counts, symbols, s.lengths[group * MAX_ALPHA..group * MAX_ALPHA + alpha_size], alpha_size) { ret (false, Invalid) }
        group += 1usize
    }
    // The MTF and RLE2 decode into tt's low bytes, counting each byte value.
    i = 0usize
    while i < 256usize {
        s.mtf[i] = u8(i)
        set32(s.cftab, i, 0u32)
        i += 1usize
    }
    set32(s.cftab, 256usize, 0u32)
    let eob = u32(alpha_size - 1usize)
    var nblock = 0usize
    var selector_at = 0usize
    var group_left = 0usize
    var current_group = 0usize
    var run_length = 0usize
    var run_power = 0usize
    while true {
        if group_left == 0usize {
            if selector_at >= usize(n_selectors) { ret (false, Invalid) }
            current_group = usize(s.selectors[selector_at])
            selector_at += 1usize
            group_left = 50usize
        }
        group_left -= 1usize
        let (sym, sym_error) = decode_symbol(s, current_group)
        if sym_error != ok { ret (false, sym_error) }
        if sym <= 1u32 {
            // RUNA and RUNB: a bijective base-2 count of the front symbol.
            if run_power >= 24usize { ret (false, Invalid) }
            run_length += usize(sym + 1u32) << u32(run_power)
            run_power += 1usize
            continue
        }
        if run_length > 0usize {
            let byte = s.seq_to_unseq[usize(s.mtf[0])]
            if nblock + run_length > s.block_size { ret (false, Invalid) }
            set32(s.cftab, usize(byte), get32(s.cftab, usize(byte)) + u32(run_length))
            while run_length > 0usize {
                s.tt[nblock * 4usize] = byte
                nblock += 1usize
                run_length -= 1usize
            }
            run_power = 0usize
        }
        if sym == eob { break }
        // Move the symbol's byte to the front.
        var index = usize(sym - 1u32)
        let moved = s.mtf[index]
        while index > 0usize {
            s.mtf[index] = s.mtf[index - 1usize]
            index -= 1usize
        }
        s.mtf[0] = moved
        let byte = s.seq_to_unseq[usize(moved)]
        if nblock >= s.block_size { ret (false, Invalid) }
        set32(s.cftab, usize(byte), get32(s.cftab, usize(byte)) + 1u32)
        s.tt[nblock * 4usize] = byte
        nblock += 1usize
    }
    if usize(orig_ptr) >= nblock { ret (false, Invalid) }
    // The inverse transform's links: cumulative counts, then each position threaded.
    var sum = 0u32
    i = 0usize
    while i < 256usize {
        let count = get32(s.cftab, i)
        set32(s.cftab, i, sum)
        sum += count
        i += 1usize
    }
    i = 0usize
    while i < nblock {
        let byte = usize(s.tt[i * 4usize])
        let slot = usize(get32(s.cftab, byte))
        set32(s.cftab, byte, u32(slot) + 1u32)
        let existing = get32(s.tt, slot) & 255u32
        set32(s.tt, slot, existing | (u32(i) << 8u32))
        i += 1usize
    }
    s.nblock = nblock
    s.t_pos = usize(get32(s.tt, usize(orig_ptr)) >> 8u32)
    s.produced = 0usize
    s.block_crc = 4294967295u32
    s.last_byte = 256u32
    s.run = 0u32
    s.repeat_left = 0u32
    s.in_block = true
    ret (true, ok)
}

fn read(source_reader: *Reader, dst: []u8) -> (usize, err) {
    let s = mem.cast[*State](source_reader.state)
    if s.finished { ret (0usize, io.End) }
    if dst.len == 0usize { ret (0usize, ok) }
    var written = 0usize
    while written < dst.len {
        if !s.in_block {
            let (loaded, load_error) = load_block(s)
            if load_error != ok { ret (written, load_error) }
            if !loaded {
                s.finished = true
                if written > 0usize { ret (written, ok) }
                ret (0usize, io.End)
            }
        }
        // Pending repeats first, then the next byte out of the transform.
        if s.repeat_left > 0u32 {
            dst[written] = u8(s.last_byte)
            s.block_crc = crc_byte(s.block_crc, s.last_byte)
            written += 1usize
            s.repeat_left -= 1u32
            continue
        }
        if s.produced == s.nblock {
            if s.block_crc ^ 4294967295u32 != s.expected_crc { ret (written, Checksum) }
            s.combined_crc = ((s.combined_crc << 1u32) | (s.combined_crc >> 31u32)) ^ s.expected_crc
            s.in_block = false
            continue
        }
        let link = get32(s.tt, s.t_pos)
        let byte = link & 255u32
        s.t_pos = usize(link >> 8u32)
        s.produced += 1usize
        if s.run == 4u32 {
            s.repeat_left = byte
            s.run = 0u32
            continue
        }
        if byte == s.last_byte { s.run += 1u32 } else {
            s.last_byte = byte
            s.run = 1u32
        }
        dst[written] = u8(byte)
        s.block_crc = crc_byte(s.block_crc, byte)
        written += 1usize
    }
    s.output_total += u64(written)
    if s.output_total > s.output_limit { ret (0usize, TooLarge) }
    ret (written, ok)
}
