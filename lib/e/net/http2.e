// HTTP/2 (RFC 9113) framing and HPACK (RFC 7541) over caller buffers, no transport: the connection preface, frame
// header and every frame type's payload (`frame_decode` stops at a partial tail with `Incomplete`; a length past
// the peer's SETTINGS_MAX_FRAME_SIZE is `FrameSize`), SETTINGS, and a header codec with the static and dynamic
// tables, integer and string literals with Huffman coding, size updates, never-indexed literals and the RFC's
// rejection rules (index 0 or out of range, a size update past the limit or after the first field, Huffman padding
// longer than 7 bits or not all ones, an EOS symbol in a string). Stream state, flow control and the connection
// state machine are the caller's (`e.net.grpc` has a client one); nothing here reads a socket.
//
// Memory: the dynamic table lives in caller storage (`data` for names and values, `lens` for their lengths, newest
// first); `decode_block` copies every decoded name and value into the scratch buffer it is given, so the headers it
// answers stay valid when the table changes.
use e.mem
use e.str

error Incomplete
error Invalid
error FrameSize
error Compression
error TooSmall
error TooLarge

const DATA: u8 = 0u8
const HEADERS: u8 = 1u8
const PRIORITY: u8 = 2u8
const RST_STREAM: u8 = 3u8
const SETTINGS: u8 = 4u8
const PUSH_PROMISE: u8 = 5u8
const PING: u8 = 6u8
const GOAWAY: u8 = 7u8
const WINDOW_UPDATE: u8 = 8u8
const CONTINUATION: u8 = 9u8

const FLAG_ACK: u8 = 1u8
const FLAG_END_STREAM: u8 = 1u8
const FLAG_END_HEADERS: u8 = 4u8
const FLAG_PADDED: u8 = 8u8
const FLAG_PRIORITY: u8 = 32u8

const DEFAULT_MAX_FRAME: usize = 16384usize
const DEFAULT_WINDOW: u32 = 65535u32

type Frame = struct { kind: u8, flags: u8, stream: u32, payload: []const u8 }
type Setting = struct { id: u16, value: u32 }
type Header = struct { name: str, value: str }
type Table = struct { data: []u8, lens: []u32, count: usize, used: usize, size: usize, max_size: usize, limit: usize, pending: bool, pending_size: usize, smallest: usize }

fn preface() -> str { ret "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" }

// --- frames ------------------------------------------------------------------------------------------------------

fn be16(b: []const u8, at: usize) -> u32 { ret (u32(b[at]) << 8u32) | u32(b[at + 1usize]) }

fn be32(b: []const u8, at: usize) -> u32 {
    ret (u32(b[at]) << 24u32) | (u32(b[at + 1usize]) << 16u32) | (u32(b[at + 2usize]) << 8u32) | u32(b[at + 3usize])
}

fn put32(b: []u8, at: usize, v: u32) {
    b[at] = u8((v >> 24u32) & 255u32)
    b[at + 1usize] = u8((v >> 16u32) & 255u32)
    b[at + 2usize] = u8((v >> 8u32) & 255u32)
    b[at + 3usize] = u8(v & 255u32)
}

// One frame at the front of `buf` and the bytes it occupies. `max_size` is the largest payload accepted.
fn frame_decode(buf: []const u8, max_size: usize) -> (Frame, usize, err) {
    var f: Frame = zero
    if buf.len < 9usize { ret (f, 0usize, Incomplete) }
    let length = (usize(buf[0usize]) << 16usize) | (usize(buf[1usize]) << 8usize) | usize(buf[2usize])
    if length > max_size { ret (f, 0usize, FrameSize) }
    if buf.len < 9usize + length { ret (f, 0usize, Incomplete) }
    f.kind = buf[3usize]
    f.flags = buf[4usize]
    f.stream = be32(buf, 5usize) & 2147483647u32
    f.payload = buf[9usize..9usize + length]
    ret (f, 9usize + length, ok)
}

fn frame_encode(dst: []u8, kind: u8, flags: u8, stream: u32, payload: []const u8) -> (usize, err) {
    if payload.len > 16777215usize { ret (0usize, FrameSize) }
    if dst.len < 9usize + payload.len { ret (0usize, TooSmall) }
    dst[0usize] = u8((payload.len >> 16usize) & 255usize)
    dst[1usize] = u8((payload.len >> 8usize) & 255usize)
    dst[2usize] = u8(payload.len & 255usize)
    dst[3usize] = kind
    dst[4usize] = flags
    put32(dst, 5usize, stream & 2147483647u32)
    mem.copy[u8](dst[9usize..9usize + payload.len], payload)
    ret (9usize + payload.len, ok)
}

// The payload of a frame with the padding removed (DATA, HEADERS, PUSH_PROMISE): a pad length that does not fit is
// a protocol error.
fn unpad(f: Frame) -> ([]const u8, err) {
    if (f.flags & FLAG_PADDED) == 0u8 { ret (f.payload, ok) }
    if f.payload.len < 1usize { ret ("", Invalid) }
    let pad = usize(f.payload[0usize])
    if pad > f.payload.len - 1usize { ret ("", Invalid) }
    ret (f.payload[1usize..f.payload.len - pad], ok)
}

// The header block fragment of a HEADERS frame: padding and the priority fields removed.
fn headers_fragment(f: Frame) -> ([]const u8, err) {
    let (body, e) = unpad(f)
    if e != ok { ret ("", e) }
    if (f.flags & FLAG_PRIORITY) != 0u8 {
        if body.len < 5usize { ret ("", Invalid) }
        ret (body[5usize..], ok)
    }
    ret (body, ok)
}

// A SETTINGS payload into `out`; the count.
fn settings_decode(payload: []const u8, out: []Setting) -> (usize, err) {
    if payload.len % 6usize != 0usize { ret (0usize, FrameSize) }
    let n = payload.len / 6usize
    if n > out.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        out[i] = Setting { id: u16(be16(payload, i * 6usize)), value: be32(payload, i * 6usize + 2usize) }
        i += 1usize
    }
    ret (n, ok)
}

fn settings_encode(dst: []u8, settings: []const Setting) -> (usize, err) {
    if dst.len < settings.len * 6usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i < settings.len {
        dst[i * 6usize] = u8(settings[i].id >> 8u16)
        dst[i * 6usize + 1usize] = u8(settings[i].id & 255u16)
        put32(dst, i * 6usize + 2usize, settings[i].value)
        i += 1usize
    }
    ret (settings.len * 6usize, ok)
}

// --- HPACK -------------------------------------------------------------------------------------------------------

fn table_new(data: []u8, lens: []u32, max_size: usize) -> Table {
    ret Table { data: data, lens: lens, count: 0usize, used: 0usize, size: 0usize, max_size: max_size, limit: max_size, pending: false, pending_size: 0usize, smallest: max_size }
}

fn entry_size(name_len: usize, value_len: usize) -> usize { ret name_len + value_len + 32usize }

// Dynamic entry `i` (0 is the newest): its byte offset in `data`.
fn entry_offset(t: *const Table, i: usize) -> usize {
    var off = 0usize
    var k = 0usize
    while k < i {
        off += usize(t.lens[k * 2usize]) + usize(t.lens[k * 2usize + 1usize])
        k += 1usize
    }
    ret off
}

fn evict_oldest(t: *Table) {
    if t.count == 0usize { ret }
    let last = t.count - 1usize
    let n = usize(t.lens[last * 2usize])
    let v = usize(t.lens[last * 2usize + 1usize])
    t.used -= n + v
    t.size -= entry_size(n, v)
    t.count -= 1usize
}

fn evict_to(t: *Table, limit: usize) {
    while t.size > limit && t.count > 0usize { evict_oldest(t) }
}

fn insert(t: *Table, name: str, value: str) {
    let need = entry_size(name.len, value.len)
    if need > t.max_size {
        // An entry larger than the table empties it and is not added (RFC 7541, 4.4).
        evict_to(t, 0usize)
        ret
    }
    evict_to(t, t.max_size - need)
    let bytes = name.len + value.len
    if bytes + t.used > t.data.len || (t.count + 1usize) * 2usize > t.lens.len {
        // Storage smaller than the size the peer was told: treat as the table being full.
        evict_to(t, 0usize)
        if bytes > t.data.len || t.lens.len < 2usize { ret }
    }
    // Make room at the front: shift the stored bytes and lengths right.
    var i = t.used
    while i > 0usize {
        i -= 1usize
        t.data[i + bytes] = t.data[i]
    }
    var j = t.count * 2usize
    while j > 0usize {
        j -= 1usize
        t.lens[j + 2usize] = t.lens[j]
    }
    mem.copy[u8](t.data[0usize..name.len], name)
    mem.copy[u8](t.data[name.len..bytes], value)
    t.lens[0usize] = u32(name.len)
    t.lens[1usize] = u32(value.len)
    t.count += 1usize
    t.used += bytes
    t.size += need
}

// Change the table's size (a dynamic table size update from the peer, or ours to announce). `limit` is the most the
// SETTINGS agreement allows.
fn table_resize(t: *Table, size: usize) -> err {
    if size > t.limit { ret Compression }
    t.max_size = size
    evict_to(t, size)
    ret ok
}

// The encoder's side of SETTINGS_HEADER_TABLE_SIZE: the limit and the size update to send before the next block.
fn table_announce(t: *Table, size: usize) {
    t.limit = size
    if size < t.smallest { t.smallest = size }
    t.pending = true
    t.pending_size = size
}

// The name and value at HPACK index `index` (1-61 static, then dynamic newest first).
fn lookup(t: *const Table, index: usize) -> (str, str, err) {
    if index == 0usize { ret ("", "", Compression) }
    if index <= 61usize { ret (static_name(index), static_value(index), ok) }
    let d = index - 62usize
    if d >= t.count { ret ("", "", Compression) }
    let off = entry_offset(t, d)
    let n = usize(t.lens[d * 2usize])
    let v = usize(t.lens[d * 2usize + 1usize])
    let name: str = t.data[off..off + n]
    let value: str = t.data[off + n..off + n + v]
    ret (name, value, ok)
}

// --- Huffman -----------------------------------------------------------------------------------------------------

// The number of symbols of each code length and the symbols sorted by (length, value): what canonical decoding needs.
fn huffman_shape(counts: []usize, order: []u16) {
    let table = huffman_table()
    var l = 0usize
    while l < counts.len {
        counts[l] = 0usize
        l += 1usize
    }
    var s = 0usize
    while s < 257usize {
        counts[usize(table[s * 5usize + 4usize])] += 1usize
        s += 1usize
    }
    var at = 0usize
    var length = 1usize
    while length < counts.len {
        var sym = 0usize
        while sym < 257usize {
            if usize(table[sym * 5usize + 4usize]) == length {
                order[at] = u16(sym)
                at += 1usize
            }
            sym += 1usize
        }
        length += 1usize
    }
}

// Decode a Huffman string into `dst`; the bytes written.
fn huffman_decode(src: []const u8, dst: []u8) -> (usize, err) {
    var counts: [31]usize = zero
    var order: [257]u16 = zero
    huffman_shape(counts[0usize..], order[0usize..])
    var out = 0usize
    var code = 0u32
    var first = 0u32
    var index = 0usize
    var length = 0usize
    var pad_bits = 0usize
    var pad_ones = true
    var i = 0usize
    while i < src.len {
        var bit = 7u8
        while true {
            let b = u32((src[i] >> bit) & 1u8)
            code = code | b
            length += 1usize
            pad_bits += 1usize
            if b == 0u32 { pad_ones = false }
            let count = u32(counts[length])
            if code < first + count {
                let sym = usize(order[index + usize(code - first)])
                if sym == 256usize { ret (0usize, Compression) }
                if out >= dst.len { ret (0usize, TooSmall) }
                dst[out] = u8(sym)
                out += 1usize
                code = 0u32
                first = 0u32
                index = 0usize
                length = 0usize
                pad_bits = 0usize
                pad_ones = true
            } else {
                index += usize(count)
                first = (first + count) << 1u32
                code = code << 1u32
                if length >= 30usize { ret (0usize, Compression) }
            }
            if bit == 0u8 { break }
            bit -= 1u8
        }
        i += 1usize
    }
    // What is left is padding: at most 7 bits, all ones (a prefix of EOS).
    if pad_bits > 7usize || !pad_ones { ret (0usize, Compression) }
    ret (out, ok)
}

// The Huffman-coded length of `src` in bytes.
fn huffman_len(src: []const u8) -> usize {
    let table = huffman_table()
    var bits = 0usize
    var i = 0usize
    while i < src.len {
        bits += usize(table[usize(src[i]) * 5usize + 4usize])
        i += 1usize
    }
    ret (bits + 7usize) / 8usize
}

fn huffman_encode(src: []const u8, dst: []u8) -> (usize, err) {
    let table = huffman_table()
    var out = 0usize
    var acc = 0u64
    var nbits = 0usize
    var i = 0usize
    while i < src.len {
        let at = usize(src[i]) * 5usize
        let code = (u64(table[at]) << 24u64) | (u64(table[at + 1usize]) << 16u64) | (u64(table[at + 2usize]) << 8u64) | u64(table[at + 3usize])
        let length = usize(table[at + 4usize])
        acc = (acc << u64(length)) | code
        nbits += length
        while nbits >= 8usize {
            if out >= dst.len { ret (0usize, TooSmall) }
            dst[out] = u8((acc >> u64(nbits - 8usize)) & 255u64)
            out += 1usize
            nbits -= 8usize
        }
        i += 1usize
    }
    if nbits > 0usize {
        if out >= dst.len { ret (0usize, TooSmall) }
        dst[out] = u8(((acc << u64(8usize - nbits)) | (255u64 >> u64(nbits))) & 255u64)
        out += 1usize
    }
    ret (out, ok)
}

// --- integers and strings ----------------------------------------------------------------------------------------

// An integer with an N-bit prefix at `*at` (RFC 7541, 5.1); a value past 2^32 is a compression error.
fn read_int(b: []const u8, at: *usize, prefix: u8) -> (u64, err) {
    if *at >= b.len { ret (0u64, Compression) }
    let mask = u8((1u32 << u32(prefix)) - 1u32)
    var v = u64(b[*at] & mask)
    *at += 1usize
    if v < u64(mask) { ret (v, ok) }
    var shift = 0u64
    while true {
        if *at >= b.len { ret (0u64, Compression) }
        let byte = b[*at]
        *at += 1usize
        if shift > 28u64 { ret (0u64, Compression) }
        v += u64(byte & 127u8) << shift
        if v > 4294967295u64 { ret (0u64, Compression) }
        if (byte & 128u8) == 0u8 { break }
        shift += 7u64
    }
    ret (v, ok)
}

fn write_int(dst: []u8, at: *usize, value: u64, prefix: u8, flags: u8) -> err {
    let mask = u64((1u32 << u32(prefix)) - 1u32)
    if *at >= dst.len { ret TooSmall }
    if value < mask {
        dst[*at] = flags | u8(value)
        *at += 1usize
        ret ok
    }
    dst[*at] = flags | u8(mask)
    *at += 1usize
    var rest = value - mask
    while rest >= 128u64 {
        if *at >= dst.len { ret TooSmall }
        dst[*at] = u8((rest & 127u64) | 128u64)
        *at += 1usize
        rest = rest >> 7u64
    }
    if *at >= dst.len { ret TooSmall }
    dst[*at] = u8(rest)
    *at += 1usize
    ret ok
}

// A string literal (length prefix of 7 bits, H flag) copied, decoded if Huffman, into `scratch` at `*used`.
fn read_string(b: []const u8, at: *usize, scratch: []u8, used: *usize) -> (str, err) {
    if *at >= b.len { ret ("", Compression) }
    let huffman = (b[*at] & 128u8) != 0u8
    let (length, length_error) = read_int(b, at, 7u8)
    if length_error != ok { ret ("", length_error) }
    if length > u64(b.len - *at) { ret ("", Compression) }
    let n = usize(length)
    let start = *used
    if huffman {
        let (written, e) = huffman_decode(b[*at..*at + n], scratch[start..])
        if e != ok { ret ("", e) }
        *at += n
        *used = start + written
        let out: str = scratch[start..start + written]
        ret (out, ok)
    }
    if start + n > scratch.len { ret ("", TooSmall) }
    mem.copy[u8](scratch[start..start + n], b[*at..*at + n])
    *at += n
    *used = start + n
    let plain: str = scratch[start..start + n]
    ret (plain, ok)
}

fn copy_scratch(scratch: []u8, used: *usize, s: str) -> (str, err) {
    if *used + s.len > scratch.len { ret ("", TooSmall) }
    mem.copy[u8](scratch[*used..*used + s.len], s)
    let out: str = scratch[*used..*used + s.len]
    *used += s.len
    ret (out, ok)
}

// A header block into `out`; the count. Names and values are copied into `scratch`. `Compression` for any HPACK
// error, `TooSmall` when `out` or `scratch` cannot hold the result.
fn decode_block(t: *Table, block: []const u8, out: []Header, scratch: []u8) -> (usize, err) {
    var at = 0usize
    var count = 0usize
    var used = 0usize
    var fields_seen = false
    while at < block.len {
        let b = block[at]
        if (b & 128u8) != 0u8 {
            // Indexed header field.
            let (index, index_error) = read_int(block, &at, 7u8)
            if index_error != ok { ret (0usize, index_error) }
            let (name, value, lookup_error) = lookup(t, usize(index))
            if lookup_error != ok { ret (0usize, lookup_error) }
            if count >= out.len { ret (0usize, TooSmall) }
            let (n2, e1) = copy_scratch(scratch, &used, name)
            if e1 != ok { ret (0usize, e1) }
            let (v2, e2) = copy_scratch(scratch, &used, value)
            if e2 != ok { ret (0usize, e2) }
            out[count] = Header { name: n2, value: v2 }
            count += 1usize
            fields_seen = true
        } else if (b & 224u8) == 32u8 {
            // Dynamic table size update: only at the start of a block.
            if fields_seen { ret (0usize, Compression) }
            let (size, size_error) = read_int(block, &at, 5u8)
            if size_error != ok { ret (0usize, size_error) }
            let resize_error = table_resize(t, usize(size))
            if resize_error != ok { ret (0usize, resize_error) }
        } else {
            // Literal: incremental indexing (6-bit prefix), without indexing or never indexed (4-bit).
            var prefix = 4u8
            var index_it = false
            if (b & 192u8) == 64u8 {
                prefix = 6u8
                index_it = true
            }
            let (name_index, name_index_error) = read_int(block, &at, prefix)
            if name_index_error != ok { ret (0usize, name_index_error) }
            var name = ""
            if name_index == 0u64 {
                let (n, name_error) = read_string(block, &at, scratch, &used)
                if name_error != ok { ret (0usize, name_error) }
                name = n
            } else {
                let (n, v, lookup_error) = lookup(t, usize(name_index))
                if lookup_error != ok { ret (0usize, lookup_error) }
                let (copied, copy_error) = copy_scratch(scratch, &used, n)
                if copy_error != ok { ret (0usize, copy_error) }
                name = copied
            }
            let (value, value_error) = read_string(block, &at, scratch, &used)
            if value_error != ok { ret (0usize, value_error) }
            if count >= out.len { ret (0usize, TooSmall) }
            out[count] = Header { name: name, value: value }
            count += 1usize
            fields_seen = true
            if index_it { insert(t, name, value) }
        }
    }
    ret (count, ok)
}

// The index of `name` (and of the whole field when `value` matches too): 0 when absent.
fn find_field(t: *const Table, name: str, value: str) -> (usize, usize) {
    var name_index = 0usize
    var full = 0usize
    var i = 1usize
    while i <= 61usize {
        if str.eq(static_name(i), name) {
            if name_index == 0usize { name_index = i }
            if str.eq(static_value(i), value) {
                full = i
                break
            }
        }
        i += 1usize
    }
    if full == 0usize {
        var d = 0usize
        while d < t.count {
            let off = entry_offset(t, d)
            let n = usize(t.lens[d * 2usize])
            let v = usize(t.lens[d * 2usize + 1usize])
            let entry_name: str = t.data[off..off + n]
            if str.eq(entry_name, name) {
                if name_index == 0usize { name_index = 62usize + d }
                let entry_value: str = t.data[off + n..off + n + v]
                if str.eq(entry_value, value) {
                    full = 62usize + d
                    break
                }
            }
            d += 1usize
        }
    }
    ret (name_index, full)
}

fn write_string(dst: []u8, at: *usize, s: str, huffman: bool) -> err {
    if huffman {
        let n = huffman_len(s)
        if n < s.len {
            let e = write_int(dst, at, u64(n), 7u8, 128u8)
            if e != ok { ret e }
            if *at + n > dst.len { ret TooSmall }
            let (written, huffman_error) = huffman_encode(s, dst[*at..])
            if huffman_error != ok { ret huffman_error }
            *at += written
            ret ok
        }
    }
    let e2 = write_int(dst, at, u64(s.len), 7u8, 0u8)
    if e2 != ok { ret e2 }
    if *at + s.len > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + s.len], s)
    *at += s.len
    ret ok
}

fn same_name(names: []const str, name: str) -> bool {
    var i = 0usize
    while i < names.len {
        if str.eq(names[i], name) { ret true }
        i += 1usize
    }
    ret false
}

// A header block for `headers`: a pending size update first, then each field as an indexed reference when the
// table has it whole, else a literal with incremental indexing (a name reference when the name is known); names in
// `sensitive` are written never-indexed. `huffman` codes a string when that is shorter. The bytes written.
fn encode_block(t: *Table, dst: []u8, headers: []const Header, sensitive: []const str, huffman: bool) -> (usize, err) {
    var at = 0usize
    if t.pending {
        // The smallest size seen since the last block, then the current one, as RFC 7541 4.2 requires.
        if t.smallest < t.pending_size {
            let e = write_int(dst, &at, u64(t.smallest), 5u8, 32u8)
            if e != ok { ret (0usize, e) }
            let shrink_error = table_resize(t, t.smallest)
            if shrink_error != ok { ret (0usize, shrink_error) }
        }
        let e2 = write_int(dst, &at, u64(t.pending_size), 5u8, 32u8)
        if e2 != ok { ret (0usize, e2) }
        let resize_error = table_resize(t, t.pending_size)
        if resize_error != ok { ret (0usize, resize_error) }
        t.pending = false
        t.smallest = t.max_size
    }
    var i = 0usize
    while i < headers.len {
        let h = headers[i]
        let (name_index, full) = find_field(t, h.name, h.value)
        let never = same_name(sensitive, h.name)
        if full != 0usize && !never {
            let e = write_int(dst, &at, u64(full), 7u8, 128u8)
            if e != ok { ret (0usize, e) }
        } else {
            var flags = 64u8
            var prefix = 6u8
            if never {
                flags = 16u8
                prefix = 4u8
            }
            let e = write_int(dst, &at, u64(name_index), prefix, flags)
            if e != ok { ret (0usize, e) }
            if name_index == 0usize {
                let name_error = write_string(dst, &at, h.name, huffman)
                if name_error != ok { ret (0usize, name_error) }
            }
            let value_error = write_string(dst, &at, h.value, huffman)
            if value_error != ok { ret (0usize, value_error) }
            if !never { insert(t, h.name, h.value) }
        }
        i += 1usize
    }
    ret (at, ok)
}

// Generated by scripts/http2_tables.py from the `hpack` package (RFC 7541 appendices A and B); do not edit.
fn static_name(index: usize) -> str {
    if index == 1usize { ret ":authority" }
    if index == 2usize { ret ":method" }
    if index == 3usize { ret ":method" }
    if index == 4usize { ret ":path" }
    if index == 5usize { ret ":path" }
    if index == 6usize { ret ":scheme" }
    if index == 7usize { ret ":scheme" }
    if index == 8usize { ret ":status" }
    if index == 9usize { ret ":status" }
    if index == 10usize { ret ":status" }
    if index == 11usize { ret ":status" }
    if index == 12usize { ret ":status" }
    if index == 13usize { ret ":status" }
    if index == 14usize { ret ":status" }
    if index == 15usize { ret "accept-charset" }
    if index == 16usize { ret "accept-encoding" }
    if index == 17usize { ret "accept-language" }
    if index == 18usize { ret "accept-ranges" }
    if index == 19usize { ret "accept" }
    if index == 20usize { ret "access-control-allow-origin" }
    if index == 21usize { ret "age" }
    if index == 22usize { ret "allow" }
    if index == 23usize { ret "authorization" }
    if index == 24usize { ret "cache-control" }
    if index == 25usize { ret "content-disposition" }
    if index == 26usize { ret "content-encoding" }
    if index == 27usize { ret "content-language" }
    if index == 28usize { ret "content-length" }
    if index == 29usize { ret "content-location" }
    if index == 30usize { ret "content-range" }
    if index == 31usize { ret "content-type" }
    if index == 32usize { ret "cookie" }
    if index == 33usize { ret "date" }
    if index == 34usize { ret "etag" }
    if index == 35usize { ret "expect" }
    if index == 36usize { ret "expires" }
    if index == 37usize { ret "from" }
    if index == 38usize { ret "host" }
    if index == 39usize { ret "if-match" }
    if index == 40usize { ret "if-modified-since" }
    if index == 41usize { ret "if-none-match" }
    if index == 42usize { ret "if-range" }
    if index == 43usize { ret "if-unmodified-since" }
    if index == 44usize { ret "last-modified" }
    if index == 45usize { ret "link" }
    if index == 46usize { ret "location" }
    if index == 47usize { ret "max-forwards" }
    if index == 48usize { ret "proxy-authenticate" }
    if index == 49usize { ret "proxy-authorization" }
    if index == 50usize { ret "range" }
    if index == 51usize { ret "referer" }
    if index == 52usize { ret "refresh" }
    if index == 53usize { ret "retry-after" }
    if index == 54usize { ret "server" }
    if index == 55usize { ret "set-cookie" }
    if index == 56usize { ret "strict-transport-security" }
    if index == 57usize { ret "transfer-encoding" }
    if index == 58usize { ret "user-agent" }
    if index == 59usize { ret "vary" }
    if index == 60usize { ret "via" }
    if index == 61usize { ret "www-authenticate" }
    ret ""
}

fn static_value(index: usize) -> str {
    if index == 2usize { ret "GET" }
    if index == 3usize { ret "POST" }
    if index == 4usize { ret "/" }
    if index == 5usize { ret "/index.html" }
    if index == 6usize { ret "http" }
    if index == 7usize { ret "https" }
    if index == 8usize { ret "200" }
    if index == 9usize { ret "204" }
    if index == 10usize { ret "206" }
    if index == 11usize { ret "304" }
    if index == 12usize { ret "400" }
    if index == 13usize { ret "404" }
    if index == 14usize { ret "500" }
    if index == 16usize { ret "gzip, deflate" }
    ret ""
}

// 257 records of five bytes: the code (big-endian u32) and its length in bits; symbol 256 is EOS.
fn huffman_table() -> str {
    ret "\x00\x00\x1F\xF8\x0D\x00\x7F\xFF\xD8\x17\x0F\xFF\xFF\xE2\x1C\x0F\xFF\xFF\xE3\x1C\x0F\xFF\xFF\xE4\x1C\x0F\xFF\xFF\xE5\x1C\x0F\xFF\xFF\xE6\x1C\x0F\xFF\xFF\xE7\x1C\x0F\xFF\xFF\xE8\x1C\x00\xFF\xFF\xEA\x18?\xFF\xFF\xFC\x1E\x0F\xFF\xFF\xE9\x1C\x0F\xFF\xFF\xEA\x1C?\xFF\xFF\xFD\x1E\x0F\xFF\xFF\xEB\x1C\x0F\xFF\xFF\xEC\x1C\x0F\xFF\xFF\xED\x1C\x0F\xFF\xFF\xEE\x1C\x0F\xFF\xFF\xEF\x1C\x0F\xFF\xFF\xF0\x1C\x0F\xFF\xFF\xF1\x1C\x0F\xFF\xFF\xF2\x1C?\xFF\xFF\xFE\x1E\x0F\xFF\xFF\xF3\x1C\x0F\xFF\xFF\xF4\x1C\x0F\xFF\xFF\xF5\x1C\x0F\xFF\xFF\xF6\x1C\x0F\xFF\xFF\xF7\x1C\x0F\xFF\xFF\xF8\x1C\x0F\xFF\xFF\xF9\x1C\x0F\xFF\xFF\xFA\x1C\x0F\xFF\xFF\xFB\x1C\x00\x00\x00\x14\x06\x00\x00\x03\xF8\x0A\x00\x00\x03\xF9\x0A\x00\x00\x0F\xFA\x0C\x00\x00\x1F\xF9\x0D\x00\x00\x00\x15\x06\x00\x00\x00\xF8\x08\x00\x00\x07\xFA\x0B\x00\x00\x03\xFA\x0A\x00\x00\x03\xFB\x0A\x00\x00\x00\xF9\x08\x00\x00\x07\xFB\x0B\x00\x00\x00\xFA\x08\x00\x00\x00\x16\x06\x00\x00\x00\x17\x06\x00\x00\x00\x18\x06\x00\x00\x00\x00\x05\x00\x00\x00\x01\x05\x00\x00\x00\x02\x05\x00\x00\x00\x19\x06\x00\x00\x00\x1A\x06\x00\x00\x00\x1B\x06\x00\x00\x00\x1C\x06\x00\x00\x00\x1D\x06\x00\x00\x00\x1E\x06\x00\x00\x00\x1F\x06\x00\x00\x00\\\x07\x00\x00\x00\xFB\x08\x00\x00\x7F\xFC\x0F\x00\x00\x00 \x06\x00\x00\x0F\xFB\x0C\x00\x00\x03\xFC\x0A\x00\x00\x1F\xFA\x0D\x00\x00\x00!\x06\x00\x00\x00]\x07\x00\x00\x00^\x07\x00\x00\x00_\x07\x00\x00\x00`\x07\x00\x00\x00a\x07\x00\x00\x00b\x07\x00\x00\x00c\x07\x00\x00\x00d\x07\x00\x00\x00e\x07\x00\x00\x00f\x07\x00\x00\x00g\x07\x00\x00\x00h\x07\x00\x00\x00i\x07\x00\x00\x00j\x07\x00\x00\x00k\x07\x00\x00\x00l\x07\x00\x00\x00m\x07\x00\x00\x00n\x07\x00\x00\x00o\x07\x00\x00\x00p\x07\x00\x00\x00q\x07\x00\x00\x00r\x07\x00\x00\x00\xFC\x08\x00\x00\x00s\x07\x00\x00\x00\xFD\x08\x00\x00\x1F\xFB\x0D\x00\x07\xFF\xF0\x13\x00\x00\x1F\xFC\x0D\x00\x00?\xFC\x0E\x00\x00\x00\"\x06\x00\x00\x7F\xFD\x0F\x00\x00\x00\x03\x05\x00\x00\x00#\x06\x00\x00\x00\x04\x05\x00\x00\x00$\x06\x00\x00\x00\x05\x05\x00\x00\x00%\x06\x00\x00\x00&\x06\x00\x00\x00'\x06\x00\x00\x00\x06\x05\x00\x00\x00t\x07\x00\x00\x00u\x07\x00\x00\x00(\x06\x00\x00\x00)\x06\x00\x00\x00*\x06\x00\x00\x00\x07\x05\x00\x00\x00+\x06\x00\x00\x00v\x07\x00\x00\x00,\x06\x00\x00\x00\x08\x05\x00\x00\x00\x09\x05\x00\x00\x00-\x06\x00\x00\x00w\x07\x00\x00\x00x\x07\x00\x00\x00y\x07\x00\x00\x00z\x07\x00\x00\x00{\x07\x00\x00\x7F\xFE\x0F\x00\x00\x07\xFC\x0B\x00\x00?\xFD\x0E\x00\x00\x1F\xFD\x0D\x0F\xFF\xFF\xFC\x1C\x00\x0F\xFF\xE6\x14\x00?\xFF\xD2\x16\x00\x0F\xFF\xE7\x14\x00\x0F\xFF\xE8\x14\x00?\xFF\xD3\x16\x00?\xFF\xD4\x16\x00?\xFF\xD5\x16\x00\x7F\xFF\xD9\x17\x00?\xFF\xD6\x16\x00\x7F\xFF\xDA\x17\x00\x7F\xFF\xDB\x17\x00\x7F\xFF\xDC\x17\x00\x7F\xFF\xDD\x17\x00\x7F\xFF\xDE\x17\x00\xFF\xFF\xEB\x18\x00\x7F\xFF\xDF\x17\x00\xFF\xFF\xEC\x18\x00\xFF\xFF\xED\x18\x00?\xFF\xD7\x16\x00\x7F\xFF\xE0\x17\x00\xFF\xFF\xEE\x18\x00\x7F\xFF\xE1\x17\x00\x7F\xFF\xE2\x17\x00\x7F\xFF\xE3\x17\x00\x7F\xFF\xE4\x17\x00\x1F\xFF\xDC\x15\x00?\xFF\xD8\x16\x00\x7F\xFF\xE5\x17\x00?\xFF\xD9\x16\x00\x7F\xFF\xE6\x17\x00\x7F\xFF\xE7\x17\x00\xFF\xFF\xEF\x18\x00?\xFF\xDA\x16\x00\x1F\xFF\xDD\x15\x00\x0F\xFF\xE9\x14\x00?\xFF\xDB\x16\x00?\xFF\xDC\x16\x00\x7F\xFF\xE8\x17\x00\x7F\xFF\xE9\x17\x00\x1F\xFF\xDE\x15\x00\x7F\xFF\xEA\x17\x00?\xFF\xDD\x16\x00?\xFF\xDE\x16\x00\xFF\xFF\xF0\x18\x00\x1F\xFF\xDF\x15\x00?\xFF\xDF\x16\x00\x7F\xFF\xEB\x17\x00\x7F\xFF\xEC\x17\x00\x1F\xFF\xE0\x15\x00\x1F\xFF\xE1\x15\x00?\xFF\xE0\x16\x00\x1F\xFF\xE2\x15\x00\x7F\xFF\xED\x17\x00?\xFF\xE1\x16\x00\x7F\xFF\xEE\x17\x00\x7F\xFF\xEF\x17\x00\x0F\xFF\xEA\x14\x00?\xFF\xE2\x16\x00?\xFF\xE3\x16\x00?\xFF\xE4\x16\x00\x7F\xFF\xF0\x17\x00?\xFF\xE5\x16\x00?\xFF\xE6\x16\x00\x7F\xFF\xF1\x17\x03\xFF\xFF\xE0\x1A\x03\xFF\xFF\xE1\x1A\x00\x0F\xFF\xEB\x14\x00\x07\xFF\xF1\x13\x00?\xFF\xE7\x16\x00\x7F\xFF\xF2\x17\x00?\xFF\xE8\x16\x01\xFF\xFF\xEC\x19\x03\xFF\xFF\xE2\x1A\x03\xFF\xFF\xE3\x1A\x03\xFF\xFF\xE4\x1A\x07\xFF\xFF\xDE\x1B\x07\xFF\xFF\xDF\x1B\x03\xFF\xFF\xE5\x1A\x00\xFF\xFF\xF1\x18\x01\xFF\xFF\xED\x19\x00\x07\xFF\xF2\x13\x00\x1F\xFF\xE3\x15\x03\xFF\xFF\xE6\x1A\x07\xFF\xFF\xE0\x1B\x07\xFF\xFF\xE1\x1B\x03\xFF\xFF\xE7\x1A\x07\xFF\xFF\xE2\x1B\x00\xFF\xFF\xF2\x18\x00\x1F\xFF\xE4\x15\x00\x1F\xFF\xE5\x15\x03\xFF\xFF\xE8\x1A\x03\xFF\xFF\xE9\x1A\x0F\xFF\xFF\xFD\x1C\x07\xFF\xFF\xE3\x1B\x07\xFF\xFF\xE4\x1B\x07\xFF\xFF\xE5\x1B\x00\x0F\xFF\xEC\x14\x00\xFF\xFF\xF3\x18\x00\x0F\xFF\xED\x14\x00\x1F\xFF\xE6\x15\x00?\xFF\xE9\x16\x00\x1F\xFF\xE7\x15\x00\x1F\xFF\xE8\x15\x00\x7F\xFF\xF3\x17\x00?\xFF\xEA\x16\x00?\xFF\xEB\x16\x01\xFF\xFF\xEE\x19\x01\xFF\xFF\xEF\x19\x00\xFF\xFF\xF4\x18\x00\xFF\xFF\xF5\x18\x03\xFF\xFF\xEA\x1A\x00\x7F\xFF\xF4\x17\x03\xFF\xFF\xEB\x1A\x07\xFF\xFF\xE6\x1B\x03\xFF\xFF\xEC\x1A\x03\xFF\xFF\xED\x1A\x07\xFF\xFF\xE7\x1B\x07\xFF\xFF\xE8\x1B\x07\xFF\xFF\xE9\x1B\x07\xFF\xFF\xEA\x1B\x07\xFF\xFF\xEB\x1B\x0F\xFF\xFF\xFE\x1C\x07\xFF\xFF\xEC\x1B\x07\xFF\xFF\xED\x1B\x07\xFF\xFF\xEE\x1B\x07\xFF\xFF\xEF\x1B\x07\xFF\xFF\xF0\x1B\x03\xFF\xFF\xEE\x1A?\xFF\xFF\xFF\x1E"
}
