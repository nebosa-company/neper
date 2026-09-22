// Arrow: the columnar layout over caller buffers, and the IPC streaming
// format reader that builds it zero-copy from a stream's first record batch.
//
// Layout: per column a validity bitmap (LSB-first, 1 = valid; empty means
// every row is valid); fixed-width kinds add a data buffer (Bool is a bitmap);
// Utf8/Binary add an `i32` offsets buffer of `len + 1` entries and a data
// buffer; List adds the offsets buffer and one child column; Struct has only
// children. Columns sit in one caller array in schema pre-order, so a column's
// first child is `cols[c.child]` and the k-th is reached by skipping k-1
// subtrees (`struct_child`).
//
// Stream: messages framed as `0xFFFFFFFF, i32 metadata length, FlatBuffers
// Message, body`; a Schema message first, then RecordBatch messages, then an
// end-of-stream marker (length 0). Dictionary-encoded fields, DictionaryBatch
// messages, compressed batches and any type outside Int/FloatingPoint/Bool/
// Utf8/Binary/List/Struct answer `Unsupported`; framing or buffer bounds
// that do not fit answer `Malformed`; `TooSmall` is the caller's arrays;
// `Invalid` is a row index or kind the accessor cannot serve.

use e.bytes as raw
use e.fmt.flatbuffers as fb

type Kind = enum u8 { Bool, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64, Utf8, Binary, List, Struct }
type Column = struct { kind: Kind, len: usize, null_count: usize, validity: []const u8, offsets: []const u8, data: []const u8, child: u32, child_count: u32 }
error Malformed
error Unsupported
error TooSmall
error Invalid

// --- layout accessors

fn is_valid(c: *const Column, i: usize) -> bool {
    if i >= c.len { ret false }
    if c.validity.len == 0usize { ret true }
    ret ((c.validity[i >> 3u32] >> u32(i & 7usize)) & 1u8) == 1u8
}

// Zero bits of the validity bitmap over `len` rows (the node's `null_count`
// is what the writer claimed; this is what the bitmap says).
fn count_nulls(c: *const Column) -> usize {
    var n = 0usize
    var i = 0usize
    while i < c.len {
        if !is_valid(c, i) { n += 1usize }
        i += 1usize
    }
    ret n
}

fn width(kind: Kind) -> usize {
    if kind == .Int8 || kind == .UInt8 { ret 1usize }
    if kind == .Int16 || kind == .UInt16 { ret 2usize }
    if kind == .Int32 || kind == .UInt32 || kind == .Float32 { ret 4usize }
    if kind == .Int64 || kind == .UInt64 || kind == .Float64 { ret 8usize }
    ret 0usize
}

fn fixed[T: type](c: *const Column, i: usize) -> (T, err) {
    let (v, e) = raw.load[T](c.data, i * width(c.kind), .Little)
    if e != ok { ret (zero, Malformed) }
    ret (v, ok)
}

// Any integer kind widened to i64; `(value, valid, err)`, a null row is
// `(0, false, ok)`.
fn get_i64(c: *const Column, i: usize) -> (i64, bool, err) {
    if i >= c.len { ret (0i64, false, Invalid) }
    if !is_valid(c, i) { ret (0i64, false, ok) }
    if c.kind == .Int8 {
        let (v, e) = fixed[i8](c, i)
        ret (i64(v), true, e)
    }
    if c.kind == .Int16 {
        let (v, e) = fixed[i16](c, i)
        ret (i64(v), true, e)
    }
    if c.kind == .Int32 {
        let (v, e) = fixed[i32](c, i)
        ret (i64(v), true, e)
    }
    if c.kind == .Int64 {
        let (v, e) = fixed[i64](c, i)
        ret (v, true, e)
    }
    if c.kind == .UInt8 {
        let (v, e) = fixed[u8](c, i)
        ret (i64(v), true, e)
    }
    if c.kind == .UInt16 {
        let (v, e) = fixed[u16](c, i)
        ret (i64(v), true, e)
    }
    if c.kind == .UInt32 {
        let (v, e) = fixed[u32](c, i)
        ret (i64(v), true, e)
    }
    if c.kind == .UInt64 {
        let (v, e) = fixed[u64](c, i)
        if e != ok { ret (0i64, false, e) }
        if v > 9223372036854775807u64 { ret (0i64, false, Invalid) }
        ret (i64(v), true, ok)
    }
    ret (0i64, false, Invalid)
}

// An integer kind that fits i32 (Int8..Int32, UInt8, UInt16).
fn get_i32(c: *const Column, i: usize) -> (i32, bool, err) {
    if c.kind == .Int64 || c.kind == .UInt32 || c.kind == .UInt64 { ret (0i32, false, Invalid) }
    let (v, valid, e) = get_i64(c, i)
    if e != ok || !valid { ret (0i32, valid, e) }
    ret (i32(v), true, ok)
}

fn get_f64(c: *const Column, i: usize) -> (f64, bool, err) {
    if i >= c.len { ret (0.0f64, false, Invalid) }
    if !is_valid(c, i) { ret (0.0f64, false, ok) }
    if c.kind == .Float32 {
        let (v, e) = fixed[f32](c, i)
        ret (f64(v), true, e)
    }
    if c.kind == .Float64 {
        let (v, e) = fixed[f64](c, i)
        ret (v, true, e)
    }
    ret (0.0f64, false, Invalid)
}

fn get_bool(c: *const Column, i: usize) -> (bool, bool, err) {
    if i >= c.len || c.kind != .Bool { ret (false, false, Invalid) }
    if !is_valid(c, i) { ret (false, false, ok) }
    if (i >> 3u32) >= c.data.len { ret (false, false, Malformed) }
    ret (((c.data[i >> 3u32] >> u32(i & 7usize)) & 1u8) == 1u8, true, ok)
}

// Offsets entry `i` of a Utf8/Binary/List column.
fn offset_at(c: *const Column, i: usize) -> (usize, err) {
    let (v, e) = raw.load[i32](c.offsets, i * 4usize, .Little)
    if e != ok || v < 0i32 { ret (0usize, Malformed) }
    ret (usize(v), ok)
}

// The `[start, end)` range row `i` covers in the data buffer (Utf8/Binary)
// or the child column (List); a null row answers `(0, 0, ok)`.
fn list_range(c: *const Column, i: usize) -> (usize, usize, err) {
    if i >= c.len { ret (0usize, 0usize, Invalid) }
    if c.kind != .Utf8 && c.kind != .Binary && c.kind != .List { ret (0usize, 0usize, Invalid) }
    if !is_valid(c, i) { ret (0usize, 0usize, ok) }
    let (start, e) = offset_at(c, i)
    if e != ok { ret (0usize, 0usize, e) }
    let (end, end_error) = offset_at(c, i + 1usize)
    if end_error != ok { ret (0usize, 0usize, end_error) }
    if end < start { ret (0usize, 0usize, Malformed) }
    ret (start, end, ok)
}

// The bytes of a Utf8/Binary row.
fn get_utf8(c: *const Column, i: usize) -> (str, bool, err) {
    if c.kind != .Utf8 && c.kind != .Binary { ret ("", false, Invalid) }
    let (start, end, e) = list_range(c, i)
    if e != ok { ret ("", false, e) }
    if !is_valid(c, i) { ret ("", false, ok) }
    if end > c.data.len { ret ("", false, Malformed) }
    ret (c.data[start..end], true, ok)
}

fn get_binary(c: *const Column, i: usize) -> ([]const u8, bool, err) {
    let (s, valid, e) = get_utf8(c, i)
    ret (s, valid, e)
}

// Columns in the subtree rooted at `i` (itself included).
fn subtree(cols: []const Column, i: usize) -> usize {
    var n = 1usize
    var k = 0u32
    while k < cols[i].child_count {
        n += subtree(cols, usize(cols[i].child) + n - 1usize)
        k += 1u32
    }
    ret n
}

// The index of the k-th child of a Struct (or the only child of a List).
fn struct_child(cols: []const Column, i: usize, k: usize) -> (usize, err) {
    if i >= cols.len || k >= usize(cols[i].child_count) { ret (0usize, Invalid) }
    var here = usize(cols[i].child)
    var j = 0usize
    while j < k {
        here += subtree(cols, here)
        j += 1usize
    }
    ret (here, ok)
}

// --- IPC stream reader

// Arrow FlatBuffers field indices (Message.fbs / Schema.fbs).
// Message: version 0, header_type 1, header 2, bodyLength 3.
// Schema: endianness 0, fields 1. Field: name 0, nullable 1, type_type 2,
// type 3, dictionary 4, children 5. RecordBatch: length 0, nodes 1,
// buffers 2, compression 3. Type union: Int 2 (bitWidth 0, is_signed 1),
// FloatingPoint 3 (precision 0: 1 single, 2 double), Binary 4, Utf8 5,
// Bool 6, List 12, Struct 13. Message header types: Schema 1,
// DictionaryBatch 2, RecordBatch 3.

type Message = struct { header_type: u8, header: usize, meta: []const u8, body: []const u8, next: usize }

// The message framed at `pos`; `header_type` 0 with `next == pos` is the
// end-of-stream marker.
fn message(stream: []const u8, pos: usize) -> (Message, err) {
    var m: Message = zero
    m.next = pos
    let (marker, e) = raw.load[u32](stream, pos, .Little)
    if e != ok { ret (m, Malformed) }
    var here = pos
    var meta_len = marker
    if marker == 4294967295u32 {
        let (n, n_error) = raw.load[u32](stream, pos + 4usize, .Little)
        if n_error != ok { ret (m, Malformed) }
        meta_len = n
        here = pos + 4usize
    }
    if meta_len == 0u32 { ret (m, ok) }
    here += 4usize
    if usize(meta_len) > stream.len - here { ret (m, Malformed) }
    m.meta = stream[here..here + usize(meta_len)]
    here += usize(meta_len)
    let (root, root_error) = fb.root(m.meta)
    if root_error != ok { ret (m, Malformed) }
    let (kind, kind_error) = fb.get_u8(m.meta, root, 1usize, 0u8)
    if kind_error != ok { ret (m, Malformed) }
    m.header_type = kind
    let (header, header_error) = fb.get_table(m.meta, root, 2usize)
    if header_error != ok || header == 0usize { ret (m, Malformed) }
    m.header = header
    let (body_len, body_error) = fb.get_i64(m.meta, root, 3usize, 0i64)
    if body_error != ok || body_len < 0i64 { ret (m, Malformed) }
    if usize(body_len) > stream.len - here { ret (m, Malformed) }
    m.body = stream[here..here + usize(body_len)]
    m.next = here + usize(body_len)
    ret (m, ok)
}

// A Field table into `cols[*count]` (and its children after it, pre-order).
fn describe(meta: []const u8, field: usize, cols: []Column, names: []str, count: *usize) -> err {
    if *count >= cols.len || *count >= names.len { ret TooSmall }
    let slot = *count
    *count += 1usize
    var c: Column = zero
    let (name, name_error) = fb.get_string(meta, field, 0usize)
    if name_error != ok { ret Malformed }
    names[slot] = name
    let (dictionary, dictionary_error) = fb.get_table(meta, field, 4usize)
    if dictionary_error != ok { ret Malformed }
    if dictionary != 0usize { ret Unsupported }
    let (type_type, type_error) = fb.union_type(meta, field, 2usize)
    if type_error != ok { ret Malformed }
    let (type_table, table_error) = fb.union_value(meta, field, 3usize)
    if table_error != ok { ret Malformed }
    let (children, children_error) = fb.get_vector(meta, field, 5usize)
    if children_error != ok { ret Malformed }
    if type_type == 2u8 {
        let (bits, bits_error) = fb.get_i32(meta, type_table, 0usize, 0i32)
        let (signed, signed_error) = fb.get_bool(meta, type_table, 1usize, false)
        if bits_error != ok || signed_error != ok { ret Malformed }
        if bits != 8i32 && bits != 16i32 && bits != 32i32 && bits != 64i32 { ret Unsupported }
        if signed {
            if bits == 8i32 { c.kind = .Int8 } else if bits == 16i32 { c.kind = .Int16 } else if bits == 32i32 { c.kind = .Int32 } else { c.kind = .Int64 }
        } else {
            if bits == 8i32 { c.kind = .UInt8 } else if bits == 16i32 { c.kind = .UInt16 } else if bits == 32i32 { c.kind = .UInt32 } else { c.kind = .UInt64 }
        }
    } else if type_type == 3u8 {
        let (precision, precision_error) = fb.get_i16(meta, type_table, 0usize, 0i16)
        if precision_error != ok { ret Malformed }
        if precision == 1i16 { c.kind = .Float32 } else if precision == 2i16 { c.kind = .Float64 } else { ret Unsupported }
    } else if type_type == 4u8 {
        c.kind = .Binary
    } else if type_type == 5u8 {
        c.kind = .Utf8
    } else if type_type == 6u8 {
        c.kind = .Bool
    } else if type_type == 12u8 {
        if children.len != 1usize { ret Malformed }
        c.kind = .List
    } else if type_type == 13u8 {
        c.kind = .Struct
    } else {
        ret Unsupported
    }
    if c.kind != .List && c.kind != .Struct && children.len != 0usize { ret Malformed }
    c.child = u32(*count & 4294967295usize)
    c.child_count = u32(children.len & 4294967295usize)
    cols[slot] = c
    var k = 0usize
    while k < children.len {
        let (child_table, child_error) = fb.vector_table_at(meta, children, k)
        if child_error != ok { ret Malformed }
        let e = describe(meta, child_table, cols, names, count)
        if e != ok { ret e }
        k += 1usize
    }
    ret ok
}

// A Buffer struct `[offset i64, length i64]` at `buffers[k]` as a body slice.
fn buffer(m: *const Message, buffers: fb.Vector, k: usize) -> ([]const u8, err) {
    if k >= buffers.len { ret (zero, Malformed) }
    let here = buffers.at + 16usize * k
    let (off, off_error) = fb.load[i64](m.meta, here)
    let (n, n_error) = fb.load[i64](m.meta, here + 8usize)
    if off_error != ok || n_error != ok || off < 0i64 || n < 0i64 { ret (zero, Malformed) }
    if usize(off) > m.body.len || usize(n) > m.body.len - usize(off) { ret (zero, Malformed) }
    ret (m.body[usize(off)..usize(off) + usize(n)], ok)
}

// Bind the RecordBatch `m` to the described `cols[..count]`.
fn bind(m: *const Message, cols: []Column, count: usize) -> err {
    let (compression, compression_error) = fb.get_table(m.meta, m.header, 3usize)
    if compression_error != ok { ret Malformed }
    if compression != 0usize { ret Unsupported }
    let (nodes, nodes_error) = fb.get_vector(m.meta, m.header, 1usize)
    let (buffers, buffers_error) = fb.get_vector(m.meta, m.header, 2usize)
    if nodes_error != ok || buffers_error != ok { ret Malformed }
    if nodes.len != count { ret Malformed }
    var b = 0usize
    var i = 0usize
    while i < count {
        let here = nodes.at + 16usize * i
        let (n, n_error) = fb.load[i64](m.meta, here)
        let (nulls, nulls_error) = fb.load[i64](m.meta, here + 8usize)
        if n_error != ok || nulls_error != ok || n < 0i64 || nulls < 0i64 { ret Malformed }
        cols[i].len = usize(n)
        cols[i].null_count = usize(nulls)
        let (validity, validity_error) = buffer(m, buffers, b)
        if validity_error != ok { ret validity_error }
        b += 1usize
        if validity.len != 0usize && validity.len * 8usize < usize(n) { ret Malformed }
        cols[i].validity = validity
        let kind = cols[i].kind
        if kind == .Utf8 || kind == .Binary || kind == .List {
            let (offsets, offsets_error) = buffer(m, buffers, b)
            if offsets_error != ok { ret offsets_error }
            b += 1usize
            if offsets.len < (usize(n) + 1usize) * 4usize { ret Malformed }
            cols[i].offsets = offsets
        }
        if kind != .List && kind != .Struct {
            let (data, data_error) = buffer(m, buffers, b)
            if data_error != ok { ret data_error }
            b += 1usize
            if kind == .Bool {
                if data.len * 8usize < usize(n) { ret Malformed }
            } else if kind == .Utf8 || kind == .Binary {
                let (_, end, end_error) = list_range(&cols[i], usize(n) - 1usize)
                if n > 0i64 && (end_error != ok || end > data.len) { ret Malformed }
            } else if data.len < usize(n) * width(kind) {
                ret Malformed
            }
            cols[i].data = data
        }
        i += 1usize
    }
    ret ok
}

// Read the schema and the first record batch of an IPC stream into
// `cols`/`names` (one entry per column node, pre-order); answers the count.
// ponytail: one batch per call; a multi-batch stream needs the reader
// to resume from `Message.next`, add when a stream carries more than one.
fn columns(stream: []const u8, cols: []Column, names: []str) -> (usize, err) {
    let (schema, e) = message(stream, 0usize)
    if e != ok { ret (0usize, e) }
    if schema.header_type != 1u8 { ret (0usize, Malformed) }
    let (fields, fields_error) = fb.get_vector(schema.meta, schema.header, 1usize)
    if fields_error != ok { ret (0usize, Malformed) }
    var count = 0usize
    var k = 0usize
    while k < fields.len {
        let (field, field_error) = fb.vector_table_at(schema.meta, fields, k)
        if field_error != ok { ret (0usize, Malformed) }
        let describe_error = describe(schema.meta, field, cols, names, &count)
        if describe_error != ok { ret (0usize, describe_error) }
        k += 1usize
    }
    let (batch, batch_error) = message(stream, schema.next)
    if batch_error != ok { ret (0usize, batch_error) }
    if batch.header_type == 2u8 { ret (0usize, Unsupported) }
    if batch.header_type != 3u8 { ret (0usize, Malformed) }
    let bind_error = bind(&batch, cols, count)
    if bind_error != ok { ret (0usize, bind_error) }
    ret (count, ok)
}
