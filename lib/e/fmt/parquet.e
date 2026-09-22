// Parquet: the encodings over caller buffers (the RLE/bit-packing hybrid,
// bit unpacking, PLAIN, PLAIN/RLE_DICTIONARY, DELTA_BINARY_PACKED,
// definition levels), a Thrift compact-protocol reader wide enough for
// `FileMetaData` and `PageHeader`, and a flat-column decoder that walks a
// column chunk's pages into caller arrays.
//
// File: `PAR1`, column chunks (a dictionary page then data pages, each a
// Thrift `PageHeader` followed by `compressed_page_size` bytes), the Thrift
// `FileMetaData`, its 4-byte LE length, `PAR1`. Physical types are kept as
// the Thrift integers (BOOLEAN 0, INT32 1, INT64 2, INT96 3, FLOAT 4, DOUBLE 5,
// BYTE_ARRAY 6, FIXED_LEN_BYTE_ARRAY 7), so are encodings (PLAIN 0,
// PLAIN_DICTIONARY 2, RLE 3, DELTA_BINARY_PACKED 5, RLE_DICTIONARY 8) and
// codecs (UNCOMPRESSED 0, SNAPPY 1, GZIP 2).
//
// `decode` reads one chunk: INT32/INT64/BOOLEAN into `Values.ints`,
// FLOAT/DOUBLE into `Values.floats`, BYTE_ARRAY into `Values.offsets` (rows+1)
// and `Values.data`; `Values.valid[i]` is 1 when row i carries a value (a null
// row holds zero / an empty range). Only flat schemas, data page v1,
// UNCOMPRESSED and SNAPPY are served; anything else is `Unsupported`.
// `Malformed` is a file that does not parse, `TooSmall` a caller array,
// `Invalid` an index outside the metadata.

use e.bytes as raw
use e.fmt.snappy as snappy
use e.mem

type Hybrid = struct { src: []const u8, pos: usize, bit_width: u32, left: usize, packed: bool, value: u32, acc: u64, bits: u32 }
type Thrift = struct { buf: []const u8, pos: usize }
type SchemaElement = struct { name: str, kind: i32, type_length: i32, repetition: i32, num_children: i32, converted_type: i32 }
type ColumnChunk = struct { kind: i32, encodings: u32, path: str, codec: i32, num_values: i64, total_uncompressed_size: i64, total_compressed_size: i64, data_page_offset: i64, index_page_offset: i64, dictionary_page_offset: i64, file_offset: i64 }
type FileMetaData = struct { version: i32, num_rows: i64, schema: []SchemaElement, schema_count: usize, columns: []ColumnChunk, column_count: usize, row_group_count: usize }
type PageHeader = struct { kind: i32, uncompressed_page_size: i32, compressed_page_size: i32, crc: i32, num_values: i32, encoding: i32, definition_level_encoding: i32, repetition_level_encoding: i32, num_nulls: i32, num_rows: i32, definition_levels_byte_length: i32, repetition_levels_byte_length: i32, is_compressed: bool, header_size: usize }
type Values = struct { ints: []i64, floats: []f64, offsets: []u32, data: []u8, valid: []u8, count: usize, data_len: usize }
error Malformed
error Unsupported
error TooSmall
error Invalid

// --- bits

// The `width` bits at bit offset `off` (LSB first), `width` up to 64.
fn bits_at(src: []const u8, off: usize, width: u32) -> (u64, err) {
    var v = 0u64
    var taken = 0u32
    var at = off
    while taken < width {
        let byte_index = at / 8usize
        if byte_index >= src.len { ret (0u64, Malformed) }
        let bit = u32(at % 8usize)
        var take = 8u32 - bit
        if take > width - taken { take = width - taken }
        let piece = (u64(src[byte_index]) >> bit) & ((1u64 << take) - 1u64)
        v = v | (piece << taken)
        at += usize(take)
        taken += take
    }
    ret (v, ok)
}

// `count` values of `bit_width` bits packed LSB-first; answers the bytes consumed.
fn bit_unpack(src: []const u8, bit_width: u32, count: usize, out: []u32) -> (usize, err) {
    if bit_width > 32u32 { ret (0usize, Unsupported) }
    if count > out.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < count {
        let (v, e) = bits_at(src, i * usize(bit_width), bit_width)
        if e != ok { ret (0usize, e) }
        out[i] = u32(v)
        i += 1usize
    }
    ret ((count * usize(bit_width) + 7usize) / 8usize, ok)
}

fn uleb(src: []const u8, at: usize) -> (u64, usize, err) {
    var v = 0u64
    var shift = 0u32
    var n = 0usize
    while n < 10usize {
        if at + n >= src.len { ret (0u64, 0usize, Malformed) }
        let byte = src[at + n]
        if n == 9usize && byte > 1u8 { ret (0u64, 0usize, Malformed) }
        v = v | (u64(byte & 127u8) << shift)
        n += 1usize
        if (byte & 128u8) == 0u8 { ret (v, n, ok) }
        shift += 7u32
    }
    ret (0u64, 0usize, Malformed)
}

// --- the RLE / bit-packing hybrid, streamed one value at a time

fn hybrid(src: []const u8, bit_width: u32) -> Hybrid {
    ret Hybrid { src: src, pos: 0usize, bit_width: bit_width, left: 0usize, packed: false, value: 0u32, acc: 0u64, bits: 0u32 }
}

fn hybrid_next(h: *Hybrid) -> (u32, err) {
    if h.left == 0usize {
        let (header, n, e) = uleb(h.src, h.pos)
        if e != ok { ret (0u32, e) }
        h.pos += n
        if (header & 1u64) == 1u64 {
            h.packed = true
            if header >> 1u32 > 536870911u64 { ret (0u32, Malformed) }
            h.left = usize(header >> 1u32) * 8usize
            h.acc = 0u64
            h.bits = 0u32
        } else {
            h.packed = false
            if header >> 1u32 > 4294967295u64 { ret (0u32, Malformed) }
            h.left = usize(header >> 1u32)
            let width = usize((h.bit_width + 7u32) / 8u32)
            if width > h.src.len - h.pos { ret (0u32, Malformed) }
            var v = 0u32
            var k = 0usize
            while k < width {
                v = v | (u32(h.src[h.pos + k]) << u32(k * 8usize))
                k += 1usize
            }
            h.value = v
            h.pos += width
        }
        if h.left == 0usize { ret (0u32, Malformed) }
    }
    h.left -= 1usize
    if !h.packed { ret (h.value, ok) }
    while h.bits < h.bit_width {
        if h.pos >= h.src.len { ret (0u32, Malformed) }
        h.acc = h.acc | (u64(h.src[h.pos]) << h.bits)
        h.pos += 1usize
        h.bits += 8u32
    }
    let v = u32(h.acc & ((1u64 << h.bit_width) - 1u64))
    h.acc = h.acc >> h.bit_width
    h.bits -= h.bit_width
    ret (v, ok)
}

// Skip the padding of a partly read bit-packed run so `pos` sits at the run's end.
fn hybrid_finish(h: *Hybrid) -> err {
    if h.packed && h.left > 0usize {
        let tail = (h.left * usize(h.bit_width) - usize(h.bits)) / 8usize
        if tail > h.src.len - h.pos { ret Malformed }
        h.pos += tail
    }
    h.left = 0usize
    ret ok
}

// `count` values of the hybrid (header varint: LSB 1 = bit-packed run of
// (header >> 1) * 8 values, 0 = RLE run of header >> 1 copies of a
// ceil(bit_width / 8)-byte LE value); answers the bytes consumed.
fn rle_bitpack_hybrid(src: []const u8, bit_width: u32, count: usize, out: []u32) -> (usize, err) {
    if bit_width > 32u32 { ret (0usize, Unsupported) }
    if count > out.len { ret (0usize, TooSmall) }
    var h = hybrid(src, bit_width)
    var i = 0usize
    while i < count {
        let (v, e) = hybrid_next(&h)
        if e != ok { ret (0usize, e) }
        out[i] = v
        i += 1usize
    }
    let e = hybrid_finish(&h)
    ret (h.pos, e)
}

// The page encoding of levels and values: the hybrid.
fn decode_page(src: []const u8, bit_width: u32, count: usize, out: []u32) -> (usize, err) {
    let (n, e) = rle_bitpack_hybrid(src, bit_width, count, out)
    ret (n, e)
}

fn bit_width_for(max_level: u32) -> u32 {
    var w = 0u32
    var v = max_level
    while v > 0u32 {
        w += 1u32
        v = v >> 1u32
    }
    ret w
}

// Data page v1 definition or repetition levels: a 4-byte LE length then the
// hybrid at the width `max_level` needs; answers the bytes consumed.
fn levels(src: []const u8, max_level: u32, count: usize, out: []u32) -> (usize, err) {
    let (n, n_error) = raw.load[u32](src, 0usize, .Little)
    if n_error != ok || usize(n) > src.len - 4usize { ret (0usize, Malformed) }
    let (_, e) = rle_bitpack_hybrid(src[4usize..4usize + usize(n)], bit_width_for(max_level), count, out)
    ret (4usize + usize(n), e)
}

// --- PLAIN

fn plain[T: type](src: []const u8, count: usize, out: []T) -> (usize, err) {
    if count > out.len { ret (0usize, TooSmall) }
    let width = mem.size_of[T]()
    if count * width > src.len { ret (0usize, Malformed) }
    var i = 0usize
    while i < count {
        let (v, e) = raw.load[T](src, i * width, .Little)
        if e != ok { ret (0usize, Malformed) }
        out[i] = v
        i += 1usize
    }
    ret (count * width, ok)
}

fn plain_i32(src: []const u8, count: usize, out: []i32) -> (usize, err) {
    let (n, e) = plain[i32](src, count, out)
    ret (n, e)
}
fn plain_i64(src: []const u8, count: usize, out: []i64) -> (usize, err) {
    let (n, e) = plain[i64](src, count, out)
    ret (n, e)
}
fn plain_f32(src: []const u8, count: usize, out: []f32) -> (usize, err) {
    let (n, e) = plain[f32](src, count, out)
    ret (n, e)
}
fn plain_f64(src: []const u8, count: usize, out: []f64) -> (usize, err) {
    let (n, e) = plain[f64](src, count, out)
    ret (n, e)
}

// PLAIN booleans: one bit per value, LSB first.
fn plain_bool(src: []const u8, count: usize, out: []u8) -> (usize, err) {
    if count > out.len { ret (0usize, TooSmall) }
    let n = (count + 7usize) / 8usize
    if n > src.len { ret (0usize, Malformed) }
    var i = 0usize
    while i < count {
        out[i] = (src[i / 8usize] >> u32(i % 8usize)) & 1u8
        i += 1usize
    }
    ret (n, ok)
}

// PLAIN byte arrays: 4-byte LE length prefixes; `out_offsets` gets count + 1
// entries into `out_data`; answers the bytes consumed.
fn plain_byte_array(src: []const u8, count: usize, out_offsets: []u32, out_data: []u8) -> (usize, err) {
    if count >= out_offsets.len { ret (0usize, TooSmall) }
    var at = 0usize
    var d = 0usize
    var i = 0usize
    out_offsets[0] = 0u32
    while i < count {
        let (n, at_after, e) = byte_array_at(src, at)
        if e != ok { ret (0usize, e) }
        if n > out_data.len - d { ret (0usize, TooSmall) }
        var k = 0usize
        while k < n {
            out_data[d + k] = src[at + 4usize + k]
            k += 1usize
        }
        d += n
        at = at_after
        if d > 4294967295usize { ret (0usize, TooSmall) }
        out_offsets[i + 1usize] = u32(d)
        i += 1usize
    }
    ret (at, ok)
}

// The length of the byte array at `at` and the position after it.
fn byte_array_at(src: []const u8, at: usize) -> (usize, usize, err) {
    let (n, e) = raw.load[u32](src, at, .Little)
    if e != ok || usize(n) > src.len - at - 4usize { ret (0usize, 0usize, Malformed) }
    ret (usize(n), at + 4usize + usize(n), ok)
}

// --- DELTA_BINARY_PACKED

fn zigzag(u: u64) -> i64 {
    let mag = i64(u >> 1u32)
    if (u & 1u64) == 1u64 { ret 0i64 - mag - 1i64 }
    ret mag
}

fn i64_from_bits(u: u64) -> i64 {
    if u < 9223372036854775808u64 { ret i64(u) }
    ret 0i64 - i64(18446744073709551615u64 - u) - 1i64
}

// Block size, miniblock count, value count, first value, then per block a
// min delta, the miniblock bit widths and the packed deltas; answers the
// value count. Arithmetic wraps at 64 bits (`wrap_i32` narrows INT32).
fn delta_binary_packed(src: []const u8, out: []i64) -> (usize, err) {
    let (block, n1, e1) = uleb(src, 0usize)
    if e1 != ok { ret (0usize, e1) }
    let (minis, n2, e2) = uleb(src, n1)
    if e2 != ok { ret (0usize, e2) }
    let (total, n3, e3) = uleb(src, n1 + n2)
    if e3 != ok { ret (0usize, e3) }
    let (first, n4, e4) = uleb(src, n1 + n2 + n3)
    if e4 != ok { ret (0usize, e4) }
    var at = n1 + n2 + n3 + n4
    if minis == 0u64 || minis > 4096u64 || block == 0u64 || block > 1048576u64 || block % (minis * 8u64) != 0u64 { ret (0usize, Malformed) }
    if total > 4294967295u64 { ret (0usize, Malformed) }
    let count = usize(total)
    if count > out.len { ret (0usize, TooSmall) }
    if count == 0usize { ret (0usize, ok) }
    let per_mini = usize(block / minis)
    out[0] = zigzag(first)
    var done = 1usize
    while done < count {
        let (min_raw, mn, me) = uleb(src, at)
        if me != ok { ret (0usize, me) }
        let min_delta = zigzag(min_raw)
        at += mn
        let widths_at = at
        if usize(minis) > src.len - at { ret (0usize, Malformed) }
        at += usize(minis)
        var m = 0usize
        while m < usize(minis) && done < count {
            let width = u32(src[widths_at + m])
            if width > 64u32 { ret (0usize, Malformed) }
            let mini_bytes = per_mini * usize(width) / 8usize
            if mini_bytes > src.len - at { ret (0usize, Malformed) }
            var k = 0usize
            while k < per_mini && done < count {
                let (d, de) = bits_at(src[at..at + mini_bytes], k * usize(width), width)
                if de != ok { ret (0usize, de) }
                out[done] = out[done - 1usize] +% min_delta +% i64_from_bits(d)
                done += 1usize
                k += 1usize
            }
            at += mini_bytes
            m += 1usize
        }
    }
    ret (count, ok)
}

// `x` reduced to its low 32 bits, sign-extended.
fn wrap_i32(x: i64) -> i64 {
    var r = x % 4294967296i64
    if r < 0i64 - 2147483648i64 { r += 4294967296i64 }
    if r > 2147483647i64 { r -= 4294967296i64 }
    ret r
}

// --- dictionary indices

// RLE_DICTIONARY / PLAIN_DICTIONARY data: a 1-byte bit width then the hybrid
// of `count` indices into `dict_values`; answers the bytes consumed.
fn dictionary[T: type](indices_page: []const u8, count: usize, dict_values: []const T, out: []T) -> (usize, err) {
    if indices_page.len == 0usize { ret (0usize, Malformed) }
    if count > out.len { ret (0usize, TooSmall) }
    let bit_width = u32(indices_page[0])
    if bit_width > 32u32 { ret (0usize, Malformed) }
    var h = hybrid(indices_page[1usize..], bit_width)
    var i = 0usize
    while i < count {
        let (index, e) = hybrid_next(&h)
        if e != ok { ret (0usize, e) }
        if usize(index) >= dict_values.len { ret (0usize, Malformed) }
        out[i] = dict_values[usize(index)]
        i += 1usize
    }
    let e = hybrid_finish(&h)
    ret (1usize + h.pos, e)
}

// --- Thrift compact protocol

fn thrift(buf: []const u8, pos: usize) -> Thrift {
    ret Thrift { buf: buf, pos: pos }
}

fn thrift_read_varint(t: *Thrift) -> (u64, err) {
    let (v, n, e) = uleb(t.buf, t.pos)
    if e != ok { ret (0u64, e) }
    t.pos += n
    ret (v, ok)
}

fn thrift_zigzag(u: u64) -> i64 { ret zigzag(u) }

fn thrift_i64(t: *Thrift) -> (i64, err) {
    let (u, e) = thrift_read_varint(t)
    if e != ok { ret (0i64, e) }
    ret (zigzag(u), ok)
}

fn thrift_i32(t: *Thrift) -> (i32, err) {
    let (v, e) = thrift_i64(t)
    if e != ok { ret (0i32, e) }
    if v < 0i64 - 2147483648i64 || v > 2147483647i64 { ret (0i32, Malformed) }
    ret (i32(v), ok)
}

fn thrift_binary(t: *Thrift) -> ([]const u8, err) {
    let (n, e) = thrift_read_varint(t)
    if e != ok { ret (zero, e) }
    if n > u64(t.buf.len - t.pos) { ret (zero, Malformed) }
    let start = t.pos
    t.pos += usize(n)
    ret (t.buf[start..t.pos], ok)
}

// The next field header: its id (0 at the struct's stop byte) and type
// nibble (bool true 1, false 2, i8 3, i16 4, i32 5, i64 6, double 7,
// binary 8, list 9, set 10, map 11, struct 12); `last` is the previous id.
fn thrift_field(t: *Thrift, last: i16) -> (i16, u8, err) {
    if t.pos >= t.buf.len { ret (0i16, 0u8, Malformed) }
    let head = t.buf[t.pos]
    t.pos += 1usize
    if head == 0u8 { ret (0i16, 0u8, ok) }
    let kind = head & 15u8
    let delta = head >> 4u32
    if delta != 0u8 { ret (last + i16(delta), kind, ok) }
    let (id, e) = thrift_i64(t)
    if e != ok { ret (0i16, 0u8, e) }
    if id < 1i64 || id > 32767i64 { ret (0i16, 0u8, Malformed) }
    ret (i16(id), kind, ok)
}

// A list or set header: the element count and element type.
fn thrift_list(t: *Thrift) -> (usize, u8, err) {
    if t.pos >= t.buf.len { ret (0usize, 0u8, Malformed) }
    let head = t.buf[t.pos]
    t.pos += 1usize
    let kind = head & 15u8
    var n = usize(head >> 4u32)
    if n == 15usize {
        let (big, e) = thrift_read_varint(t)
        if e != ok || big > 4294967295u64 { ret (0usize, 0u8, Malformed) }
        n = usize(big)
    }
    ret (n, kind, ok)
}

// Skip a field value of type `kind` (a bool lives in its header).
fn thrift_skip(t: *Thrift, kind: u8) -> err {
    ret skip_value(t, kind, false, 0usize)
}

fn skip_value(t: *Thrift, kind: u8, element: bool, depth: usize) -> err {
    if depth > 32usize { ret Malformed }
    if kind == 1u8 || kind == 2u8 {
        if element { t.pos += 1usize }
        if t.pos > t.buf.len { ret Malformed }
        ret ok
    }
    if kind == 3u8 || kind == 7u8 {
        var n = 1usize
        if kind == 7u8 { n = 8usize }
        if n > t.buf.len - t.pos { ret Malformed }
        t.pos += n
        ret ok
    }
    if kind == 4u8 || kind == 5u8 || kind == 6u8 {
        let (_, e) = thrift_read_varint(t)
        ret e
    }
    if kind == 8u8 {
        let (_, e) = thrift_binary(t)
        ret e
    }
    if kind == 9u8 || kind == 10u8 {
        let (n, element_kind, e) = thrift_list(t)
        if e != ok { ret e }
        var i = 0usize
        while i < n {
            let skip_error = skip_value(t, element_kind, true, depth + 1usize)
            if skip_error != ok { ret skip_error }
            i += 1usize
        }
        ret ok
    }
    if kind == 11u8 {
        let (n, e) = thrift_read_varint(t)
        if e != ok { ret e }
        if n == 0u64 { ret ok }
        if t.pos >= t.buf.len { ret Malformed }
        let kinds = t.buf[t.pos]
        t.pos += 1usize
        var i = 0u64
        while i < n {
            let key_error = skip_value(t, kinds >> 4u32, true, depth + 1usize)
            if key_error != ok { ret key_error }
            let value_error = skip_value(t, kinds & 15u8, true, depth + 1usize)
            if value_error != ok { ret value_error }
            i += 1u64
        }
        ret ok
    }
    if kind == 12u8 {
        var last = 0i16
        while true {
            let (id, field_kind, e) = thrift_field(t, last)
            if e != ok { ret e }
            if id == 0i16 { ret ok }
            last = id
            let skip_error = skip_value(t, field_kind, false, depth + 1usize)
            if skip_error != ok { ret skip_error }
        }
    }
    ret Malformed
}

fn thrift_str(t: *Thrift) -> (str, err) {
    let (b, e) = thrift_binary(t)
    ret (b, e)
}

// --- FileMetaData

// The footer: `PAR1` at both ends and the 4-byte LE metadata length; answers
// where the metadata starts and how long it is.
fn footer(file: []const u8) -> (usize, usize, err) {
    if file.len < 12usize { ret (0usize, 0usize, Malformed) }
    if file[0] != 80u8 || file[1] != 65u8 || file[2] != 82u8 || file[3] != 49u8 { ret (0usize, 0usize, Malformed) }
    let end = file.len - 4usize
    if file[end] != 80u8 || file[end + 1usize] != 65u8 || file[end + 2usize] != 82u8 || file[end + 3usize] != 49u8 { ret (0usize, 0usize, Malformed) }
    let (n, e) = raw.load[u32](file, file.len - 8usize, .Little)
    if e != ok || usize(n) > file.len - 12usize { ret (0usize, 0usize, Malformed) }
    ret (file.len - 8usize - usize(n), usize(n), ok)
}

fn schema_element(t: *Thrift, s: *SchemaElement) -> err {
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(t, last)
        if e != ok { ret e }
        if id == 0i16 { ret ok }
        last = id
        if id == 4i16 {
            let (name, name_error) = thrift_str(t)
            if name_error != ok { ret name_error }
            s.name = name
        } else if id >= 1i16 && id <= 6i16 {
            let (v, v_error) = thrift_i32(t)
            if v_error != ok { ret v_error }
            if id == 1i16 { s.kind = v }
            if id == 2i16 { s.type_length = v }
            if id == 3i16 { s.repetition = v }
            if id == 5i16 { s.num_children = v }
            if id == 6i16 { s.converted_type = v }
        } else {
            let skip_error = thrift_skip(t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

fn column_meta_data(t: *Thrift, c: *ColumnChunk) -> err {
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(t, last)
        if e != ok { ret e }
        if id == 0i16 { ret ok }
        last = id
        if id == 1i16 || id == 4i16 {
            let (v, v_error) = thrift_i32(t)
            if v_error != ok { ret v_error }
            if id == 1i16 { c.kind = v } else { c.codec = v }
        } else if id == 2i16 {
            let (n, _, list_error) = thrift_list(t)
            if list_error != ok { ret list_error }
            var i = 0usize
            while i < n {
                let (v, v_error) = thrift_i32(t)
                if v_error != ok { ret v_error }
                if v >= 0i32 && v < 32i32 { c.encodings = c.encodings | (1u32 << u32(v)) }
                i += 1usize
            }
        } else if id == 3i16 {
            let (n, _, list_error) = thrift_list(t)
            if list_error != ok { ret list_error }
            var i = 0usize
            while i < n {
                let (part, part_error) = thrift_str(t)
                if part_error != ok { ret part_error }
                c.path = part
                i += 1usize
            }
        } else if id >= 5i16 && id <= 11i16 && id != 8i16 {
            let (v, v_error) = thrift_i64(t)
            if v_error != ok { ret v_error }
            if id == 5i16 { c.num_values = v }
            if id == 6i16 { c.total_uncompressed_size = v }
            if id == 7i16 { c.total_compressed_size = v }
            if id == 9i16 { c.data_page_offset = v }
            if id == 10i16 { c.index_page_offset = v }
            if id == 11i16 { c.dictionary_page_offset = v }
        } else {
            let skip_error = thrift_skip(t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

fn column_chunk_meta(t: *Thrift, c: *ColumnChunk) -> err {
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(t, last)
        if e != ok { ret e }
        if id == 0i16 { ret ok }
        last = id
        if id == 2i16 {
            let (v, v_error) = thrift_i64(t)
            if v_error != ok { ret v_error }
            c.file_offset = v
        } else if id == 3i16 {
            let meta_error = column_meta_data(t, c)
            if meta_error != ok { ret meta_error }
        } else {
            let skip_error = thrift_skip(t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

fn row_group(t: *Thrift, m: *FileMetaData) -> err {
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(t, last)
        if e != ok { ret e }
        if id == 0i16 { ret ok }
        last = id
        if id == 1i16 {
            let (n, _, list_error) = thrift_list(t)
            if list_error != ok { ret list_error }
            var i = 0usize
            while i < n {
                if m.column_count >= m.columns.len { ret TooSmall }
                var c: ColumnChunk = zero
                let chunk_error = column_chunk_meta(t, &c)
                if chunk_error != ok { ret chunk_error }
                m.columns[m.column_count] = c
                m.column_count += 1usize
                i += 1usize
            }
        } else {
            let skip_error = thrift_skip(t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

// Read the footer's `FileMetaData` into `m`: schema elements (the root first)
// into `m.schema`, every row group's column chunks in order into `m.columns`.
// A nested schema (a non-root element with children) is `Unsupported`.
fn metadata(file: []const u8, m: *FileMetaData) -> err {
    let (start, n, footer_error) = footer(file)
    if footer_error != ok { ret footer_error }
    var t = thrift(file[..start + n], start)
    m.schema_count = 0usize
    m.column_count = 0usize
    m.row_group_count = 0usize
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(&t, last)
        if e != ok { ret e }
        if id == 0i16 {
            if m.schema_count == 0usize { ret Malformed }
            var i = 1usize
            while i < m.schema_count {
                if m.schema[i].num_children != 0i32 { ret Unsupported }
                i += 1usize
            }
            if m.schema_count - 1usize != 0usize && m.column_count % (m.schema_count - 1usize) != 0usize { ret Malformed }
            ret ok
        }
        last = id
        if id == 1i16 {
            let (v, v_error) = thrift_i32(&t)
            if v_error != ok { ret v_error }
            m.version = v
        } else if id == 3i16 {
            let (v, v_error) = thrift_i64(&t)
            if v_error != ok { ret v_error }
            m.num_rows = v
        } else if id == 2i16 {
            let (count, _, list_error) = thrift_list(&t)
            if list_error != ok { ret list_error }
            var i = 0usize
            while i < count {
                if m.schema_count >= m.schema.len { ret TooSmall }
                var s: SchemaElement = zero
                let s_error = schema_element(&t, &s)
                if s_error != ok { ret s_error }
                m.schema[m.schema_count] = s
                m.schema_count += 1usize
                i += 1usize
            }
        } else if id == 4i16 {
            let (count, _, list_error) = thrift_list(&t)
            if list_error != ok { ret list_error }
            var i = 0usize
            while i < count {
                let group_error = row_group(&t, m)
                if group_error != ok { ret group_error }
                m.row_group_count += 1usize
                i += 1usize
            }
        } else {
            let skip_error = thrift_skip(&t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

// Leaf columns per row group.
fn column_count(m: *const FileMetaData) -> usize {
    if m.schema_count == 0usize { ret 0usize }
    ret m.schema_count - 1usize
}

// The chunk of `column` in `row_group`.
fn column_chunk(m: *const FileMetaData, row_group_index: usize, column: usize) -> (ColumnChunk, err) {
    let leaves = column_count(m)
    if column >= leaves || row_group_index >= m.row_group_count { ret (zero, Invalid) }
    let index = row_group_index * leaves + column
    if index >= m.column_count { ret (zero, Invalid) }
    ret (m.columns[index], ok)
}

// --- pages

fn page_header_v1(t: *Thrift, h: *PageHeader) -> err {
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(t, last)
        if e != ok { ret e }
        if id == 0i16 { ret ok }
        last = id
        if kind == 5u8 && id >= 1i16 && id <= 4i16 {
            let (v, v_error) = thrift_i32(t)
            if v_error != ok { ret v_error }
            if id == 1i16 { h.num_values = v }
            if id == 2i16 { h.encoding = v }
            if id == 3i16 { h.definition_level_encoding = v }
            if id == 4i16 { h.repetition_level_encoding = v }
        } else {
            let skip_error = thrift_skip(t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

fn page_header_v2(t: *Thrift, h: *PageHeader) -> err {
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(t, last)
        if e != ok { ret e }
        if id == 0i16 { ret ok }
        last = id
        if kind == 5u8 && id >= 1i16 && id <= 6i16 {
            let (v, v_error) = thrift_i32(t)
            if v_error != ok { ret v_error }
            if id == 1i16 { h.num_values = v }
            if id == 2i16 { h.num_nulls = v }
            if id == 3i16 { h.num_rows = v }
            if id == 4i16 { h.encoding = v }
            if id == 5i16 { h.definition_levels_byte_length = v }
            if id == 6i16 { h.repetition_levels_byte_length = v }
        } else if id == 7i16 && (kind == 1u8 || kind == 2u8) {
            h.is_compressed = kind == 1u8
        } else {
            let skip_error = thrift_skip(t, kind)
            if skip_error != ok { ret skip_error }
        }
    }
    ret ok
}

// The Thrift `PageHeader` at `pos`; `header_size` is its encoded length, so
// the page bytes start at `pos + header_size`.
fn page_header(file: []const u8, pos: usize) -> (PageHeader, err) {
    var h: PageHeader = zero
    if pos >= file.len { ret (h, Malformed) }
    var t = thrift(file, pos)
    var last = 0i16
    while true {
        let (id, kind, e) = thrift_field(&t, last)
        if e != ok { ret (h, e) }
        if id == 0i16 {
            h.header_size = t.pos - pos
            if h.compressed_page_size < 0i32 || h.uncompressed_page_size < 0i32 || h.num_values < 0i32 { ret (h, Malformed) }
            ret (h, ok)
        }
        last = id
        if kind == 5u8 && id >= 1i16 && id <= 4i16 {
            let (v, v_error) = thrift_i32(&t)
            if v_error != ok { ret (h, v_error) }
            if id == 1i16 { h.kind = v }
            if id == 2i16 { h.uncompressed_page_size = v }
            if id == 3i16 { h.compressed_page_size = v }
            if id == 4i16 { h.crc = v }
        } else if kind == 12u8 && (id == 5i16 || id == 7i16) {
            let sub_error = page_header_v1(&t, &h)
            if sub_error != ok { ret (h, sub_error) }
        } else if kind == 12u8 && id == 8i16 {
            let sub_error = page_header_v2(&t, &h)
            if sub_error != ok { ret (h, sub_error) }
        } else {
            let skip_error = thrift_skip(&t, kind)
            if skip_error != ok { ret (h, skip_error) }
        }
    }
    ret (h, Malformed)
}

// The page's bytes, decompressed into `scratch` when the codec asks.
fn page_bytes(file: []const u8, at: usize, h: *const PageHeader, codec: i32, scratch: []u8) -> ([]const u8, err) {
    let compressed = usize(h.compressed_page_size)
    let uncompressed = usize(h.uncompressed_page_size)
    if compressed > file.len - at { ret (zero, Malformed) }
    let page = file[at..at + compressed]
    if codec == 0i32 {
        if compressed != uncompressed { ret (zero, Malformed) }
        ret (page, ok)
    }
    if codec == 1i32 {
        if uncompressed > scratch.len { ret (zero, TooSmall) }
        let (n, e) = snappy.decode(page, scratch[..uncompressed])
        if e != ok || n != uncompressed { ret (zero, Malformed) }
        ret (scratch[..uncompressed], ok)
    }
    // ponytail: GZIP (2) needs e.fmt.gzip's streaming reader over an io.Reader; add when a caller has one.
    ret (zero, Unsupported)
}

fn physical_width(kind: i32) -> usize {
    if kind == 1i32 || kind == 4i32 { ret 4usize }
    if kind == 2i32 || kind == 5i32 { ret 8usize }
    ret 0usize
}

// Append the byte array at `src[at..]` to `v.data` and close row `row`.
fn push_bytes(v: *Values, row: usize, src: []const u8, at: usize) -> err {
    let (n, _, e) = byte_array_at(src, at)
    if e != ok { ret e }
    if n > v.data.len - v.data_len { ret TooSmall }
    var k = 0usize
    while k < n {
        v.data[v.data_len + k] = src[at + 4usize + k]
        k += 1usize
    }
    v.data_len += n
    if v.data_len > 4294967295usize { ret TooSmall }
    v.offsets[row + 1usize] = u32(v.data_len)
    ret ok
}

// One value of the column's physical type read from `src` at `at` into row `row`.
fn store_value(v: *Values, row: usize, kind: i32, src: []const u8, at: usize) -> err {
    if kind == 1i32 {
        let (x, e) = raw.load[i32](src, at, .Little)
        if e != ok { ret Malformed }
        v.ints[row] = i64(x)
    } else if kind == 2i32 {
        let (x, e) = raw.load[i64](src, at, .Little)
        if e != ok { ret Malformed }
        v.ints[row] = x
    } else if kind == 4i32 {
        let (x, e) = raw.load[f32](src, at, .Little)
        if e != ok { ret Malformed }
        v.floats[row] = f64(x)
    } else if kind == 5i32 {
        let (x, e) = raw.load[f64](src, at, .Little)
        if e != ok { ret Malformed }
        v.floats[row] = x
    } else if kind == 6i32 {
        ret push_bytes(v, row, src, at)
    } else {
        ret Unsupported
    }
    ret ok
}

// The byte position of dictionary entry `index` in a PLAIN dictionary page.
fn dictionary_entry(dict: []const u8, kind: i32, index: usize, dict_count: usize) -> (usize, err) {
    if index >= dict_count { ret (0usize, Malformed) }
    if kind != 6i32 { ret (index * physical_width(kind), ok) }
    // ponytail: O(index) walk per lookup; dictionaries here are small. Cache offsets in scratch if a wide column hurts.
    var at = 0usize
    var i = 0usize
    while i < index {
        let (_, after, e) = byte_array_at(dict, at)
        if e != ok { ret (0usize, e) }
        at = after
        i += 1usize
    }
    ret (at, ok)
}

fn data_page(v: *Values, base: usize, h: *const PageHeader, page: []const u8, kind: i32, max_def: u32, dict: []const u8, dict_count: usize) -> err {
    let rows = usize(h.num_values)
    var body_at = 0usize
    var present = rows
    if max_def == 1u32 {
        if h.definition_level_encoding != 3i32 { ret Unsupported }
        let (n, n_error) = raw.load[u32](page, 0usize, .Little)
        if n_error != ok || usize(n) > page.len - 4usize { ret Malformed }
        var levels_reader = hybrid(page[4usize..4usize + usize(n)], 1u32)
        present = 0usize
        var i = 0usize
        while i < rows {
            let (level, level_error) = hybrid_next(&levels_reader)
            if level_error != ok { ret level_error }
            if level > 1u32 { ret Malformed }
            v.valid[base + i] = u8(level)
            present += usize(level)
            i += 1usize
        }
        body_at = 4usize + usize(n)
    } else {
        var i = 0usize
        while i < rows {
            v.valid[base + i] = 1u8
            i += 1usize
        }
    }
    let body = page[body_at..]
    var row = 0usize
    if h.encoding == 0i32 {
        if kind == 0i32 {
            var k = 0usize
            while row < rows {
                if v.valid[base + row] == 1u8 {
                    if k / 8usize >= body.len { ret Malformed }
                    v.ints[base + row] = i64((body[k / 8usize] >> u32(k % 8usize)) & 1u8)
                    k += 1usize
                }
                row += 1usize
            }
            ret ok
        }
        var at = 0usize
        while row < rows {
            if v.valid[base + row] == 1u8 {
                let e = store_value(v, base + row, kind, body, at)
                if e != ok { ret e }
                if kind == 6i32 {
                    let (_, after, after_error) = byte_array_at(body, at)
                    if after_error != ok { ret after_error }
                    at = after
                } else {
                    at += physical_width(kind)
                }
            } else if kind == 6i32 {
                v.offsets[base + row + 1usize] = u32(v.data_len)
            }
            row += 1usize
        }
        ret ok
    }
    if h.encoding == 2i32 || h.encoding == 8i32 {
        if dict_count == 0usize || kind == 0i32 { ret Malformed }
        if body.len == 0usize { ret Malformed }
        let bit_width = u32(body[0])
        if bit_width > 32u32 { ret Malformed }
        var indices = hybrid(body[1usize..], bit_width)
        while row < rows {
            if v.valid[base + row] == 1u8 {
                let (index, index_error) = hybrid_next(&indices)
                if index_error != ok { ret index_error }
                let (at, at_error) = dictionary_entry(dict, kind, usize(index), dict_count)
                if at_error != ok { ret at_error }
                let e = store_value(v, base + row, kind, dict, at)
                if e != ok { ret e }
            } else if kind == 6i32 {
                v.offsets[base + row + 1usize] = u32(v.data_len)
            }
            row += 1usize
        }
        ret ok
    }
    if h.encoding == 5i32 {
        if kind != 1i32 && kind != 2i32 { ret Unsupported }
        let dense = v.ints[base..base + rows]
        let (count, e) = delta_binary_packed(body, dense)
        if e != ok { ret e }
        if count != present { ret Malformed }
        // Spread the dense values over the rows from the back; a null row is zero.
        var dense_index = present
        var r = rows
        while r > 0usize {
            r -= 1usize
            if v.valid[base + r] == 1u8 {
                dense_index -= 1usize
                var x = dense[dense_index]
                if kind == 1i32 { x = wrap_i32(x) }
                dense[r] = x
            } else {
                dense[r] = 0i64
            }
        }
        ret ok
    }
    // ponytail: DELTA_LENGTH_BYTE_ARRAY (6), DELTA_BYTE_ARRAY (7) and BYTE_STREAM_SPLIT (9) wait for a writer that emits them.
    ret Unsupported
}

// Decode the chunk `m.columns[chunk_index]` (a flat, non-repeated column) into
// `v`: `v.valid` and the arrays of the column's kind get `num_values` rows,
// `v.offsets` one more; `scratch` holds decompressed pages (the dictionary
// page and the largest data page together) and may be empty for
// UNCOMPRESSED. Answers the row count.
fn decode(file: []const u8, m: *const FileMetaData, chunk_index: usize, v: *Values, scratch: []u8) -> (usize, err) {
    let leaves = column_count(m)
    if leaves == 0usize || chunk_index >= m.column_count { ret (0usize, Invalid) }
    let c = m.columns[chunk_index]
    let s = m.schema[1usize + chunk_index % leaves]
    if s.repetition == 2i32 { ret (0usize, Unsupported) }
    var max_def = 0u32
    if s.repetition == 1i32 { max_def = 1u32 }
    let kind = c.kind
    if kind == 3i32 || kind == 7i32 || kind < 0i32 || kind > 7i32 { ret (0usize, Unsupported) }
    if c.num_values < 0i64 || c.num_values > 4294967295i64 { ret (0usize, Malformed) }
    let rows = usize(c.num_values)
    if rows > v.valid.len { ret (0usize, TooSmall) }
    if (kind == 0i32 || kind == 1i32 || kind == 2i32) && rows > v.ints.len { ret (0usize, TooSmall) }
    if (kind == 4i32 || kind == 5i32) && rows > v.floats.len { ret (0usize, TooSmall) }
    if kind == 6i32 && rows >= v.offsets.len { ret (0usize, TooSmall) }
    if c.data_page_offset < 0i64 || c.dictionary_page_offset < 0i64 || c.total_compressed_size < 0i64 { ret (0usize, Malformed) }
    var pos = usize(c.data_page_offset)
    if c.dictionary_page_offset > 0i64 && usize(c.dictionary_page_offset) < pos { pos = usize(c.dictionary_page_offset) }
    if usize(c.total_compressed_size) > file.len - pos { ret (0usize, Malformed) }
    let end = pos + usize(c.total_compressed_size)
    v.count = 0usize
    v.data_len = 0usize
    if kind == 6i32 { v.offsets[0] = 0u32 }
    var dict: []const u8 = zero
    var dict_count = 0usize
    var scratch_base = 0usize
    var done = 0usize
    while done < rows {
        if pos >= end { ret (done, Malformed) }
        let (h, h_error) = page_header(file, pos)
        if h_error != ok { ret (done, h_error) }
        pos += h.header_size
        if usize(h.compressed_page_size) > end - pos { ret (done, Malformed) }
        let (page, page_error) = page_bytes(file, pos, &h, c.codec, scratch[scratch_base..])
        if page_error != ok { ret (done, page_error) }
        pos += usize(h.compressed_page_size)
        if h.kind == 2i32 {
            if h.encoding != 0i32 && h.encoding != 2i32 { ret (done, Unsupported) }
            if dict_count != 0usize { ret (done, Malformed) }
            dict = page
            dict_count = usize(h.num_values)
            if c.codec != 0i32 { scratch_base = page.len }
        } else if h.kind == 0i32 {
            if usize(h.num_values) > rows - done { ret (done, Malformed) }
            let e = data_page(v, done, &h, page, kind, max_def, dict, dict_count)
            if e != ok { ret (done, e) }
            done += usize(h.num_values)
        } else if h.kind == 3i32 {
            // ponytail: data page v2 (levels without a length prefix, values compressed alone); add when a writer here emits it.
            ret (done, Unsupported)
        } else if h.kind != 1i32 {
            ret (done, Malformed)
        }
    }
    v.count = rows
    ret (rows, ok)
}
