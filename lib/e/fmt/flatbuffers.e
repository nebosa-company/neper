// FlatBuffers: zero-copy field access through vtable offsets, and a small
// builder that lays a buffer out back to front the way the reference does.
//
// Layout (little-endian): the root `uoffset` at 0 and an optional 4-byte file
// identifier at 4; a table starts with an `soffset` to its vtable
// (`vtable = table - soffset`); a vtable is `[vtable size u16, table size u16,
// field offsets u16...]` with 0 meaning absent; a `uoffset` is relative to its
// own position; a vector is a `u32` count then the elements; a string is a
// vector of bytes with a trailing NUL; a struct is inline in its table.
//
// Every reader takes the whole `buf` and absolute positions, checks every
// offset against `buf.len` and answers `Invalid` on a bad one; an absent field
// answers the caller's fallback, an empty string, or position 0.

use e.bytes as raw
use e.mem

type Vector = struct { at: usize, len: usize }
type Builder = struct { buf: []u8, head: usize, minalign: usize, slots: [64]usize, slot_count: usize, table_end: usize, vector_count: usize }
error Invalid
error TooSmall

// Positions are read through `bytes.load` (little-endian, bounds-checked).
fn load[T: type](buf: []const u8, at: usize) -> (T, err) {
    let (v, e) = raw.load[T](buf, at, .Little)
    if e != ok { ret (zero, Invalid) }
    ret (v, ok)
}

// The absolute position a `uoffset` at `at` points to.
fn uoffset(buf: []const u8, at: usize) -> (usize, err) {
    let (rel, e) = load[u32](buf, at)
    if e != ok { ret (0usize, e) }
    let pos = at + usize(rel)
    if pos >= buf.len { ret (0usize, Invalid) }
    ret (pos, ok)
}

// The root table's position.
fn root(buf: []const u8) -> (usize, err) {
    let (pos, e) = uoffset(buf, 0usize)
    ret (pos, e)
}

// Whether the 4-byte file identifier at 4 is `ident`.
fn has_identifier(buf: []const u8, ident: str) -> bool {
    if buf.len < 8usize || ident.len != 4usize { ret false }
    ret mem.eq[u8](buf[4usize..8usize], ident)
}

fn root_with_identifier(buf: []const u8, ident: str) -> (usize, err) {
    if !has_identifier(buf, ident) { ret (0usize, Invalid) }
    let (pos, e) = uoffset(buf, 0usize)
    ret (pos, e)
}

// The `get` core: the absolute position of `field` in the table at
// `table_pos`, or 0 when the vtable does not carry it.
fn field_offset(buf: []const u8, table_pos: usize, field_index: usize) -> (usize, err) {
    let (soffset, e) = load[i32](buf, table_pos)
    if e != ok { ret (0usize, e) }
    var vt = 0usize
    if soffset >= 0i32 {
        if usize(soffset) > table_pos { ret (0usize, Invalid) }
        vt = table_pos - usize(soffset)
    } else {
        vt = table_pos + usize(0i32 - soffset)
    }
    let (vsize, vsize_error) = load[u16](buf, vt)
    if vsize_error != ok { ret (0usize, vsize_error) }
    if usize(vsize) < 4usize || vt + usize(vsize) > buf.len { ret (0usize, Invalid) }
    let slot_at = 4usize + 2usize * field_index
    if slot_at + 2usize > usize(vsize) { ret (0usize, ok) }
    let (off, off_error) = load[u16](buf, vt + slot_at)
    if off_error != ok { ret (0usize, off_error) }
    if off == 0u16 { ret (0usize, ok) }
    let pos = table_pos + usize(off)
    if pos >= buf.len { ret (0usize, Invalid) }
    ret (pos, ok)
}

// A scalar field, `fallback` when absent.
fn get[T: type](buf: []const u8, table: usize, field: usize, fallback: T) -> (T, err) {
    let (pos, e) = field_offset(buf, table, field)
    if e != ok { ret (zero, e) }
    if pos == 0usize { ret (fallback, ok) }
    let (v, load_error) = load[T](buf, pos)
    ret (v, load_error)
}

fn get_u8(buf: []const u8, table: usize, field: usize, fallback: u8) -> (u8, err) {
    let (v, e) = get[u8](buf, table, field, fallback)
    ret (v, e)
}
fn get_u16(buf: []const u8, table: usize, field: usize, fallback: u16) -> (u16, err) {
    let (v, e) = get[u16](buf, table, field, fallback)
    ret (v, e)
}
fn get_u32(buf: []const u8, table: usize, field: usize, fallback: u32) -> (u32, err) {
    let (v, e) = get[u32](buf, table, field, fallback)
    ret (v, e)
}
fn get_u64(buf: []const u8, table: usize, field: usize, fallback: u64) -> (u64, err) {
    let (v, e) = get[u64](buf, table, field, fallback)
    ret (v, e)
}
fn get_i8(buf: []const u8, table: usize, field: usize, fallback: i8) -> (i8, err) {
    let (v, e) = get[i8](buf, table, field, fallback)
    ret (v, e)
}
fn get_i16(buf: []const u8, table: usize, field: usize, fallback: i16) -> (i16, err) {
    let (v, e) = get[i16](buf, table, field, fallback)
    ret (v, e)
}
fn get_i32(buf: []const u8, table: usize, field: usize, fallback: i32) -> (i32, err) {
    let (v, e) = get[i32](buf, table, field, fallback)
    ret (v, e)
}
fn get_i64(buf: []const u8, table: usize, field: usize, fallback: i64) -> (i64, err) {
    let (v, e) = get[i64](buf, table, field, fallback)
    ret (v, e)
}
fn get_f32(buf: []const u8, table: usize, field: usize, fallback: f32) -> (f32, err) {
    let (v, e) = get[f32](buf, table, field, fallback)
    ret (v, e)
}
fn get_f64(buf: []const u8, table: usize, field: usize, fallback: f64) -> (f64, err) {
    let (v, e) = get[f64](buf, table, field, fallback)
    ret (v, e)
}

fn get_bool(buf: []const u8, table: usize, field: usize, fallback: bool) -> (bool, err) {
    var d = 0u8
    if fallback { d = 1u8 }
    let (v, e) = get[u8](buf, table, field, d)
    ret (v != 0u8, e)
}

// The string whose length prefix sits at `at` (the NUL must fit too).
fn string_at(buf: []const u8, at: usize) -> (str, err) {
    let (n, e) = load[u32](buf, at)
    if e != ok { ret ("", e) }
    let start = at + 4usize
    if usize(n) >= buf.len - start { ret ("", Invalid) }
    ret (buf[start..start + usize(n)], ok)
}

// A string field, empty when absent.
fn get_string(buf: []const u8, table: usize, field: usize) -> (str, err) {
    let (pos, e) = field_offset(buf, table, field)
    if e != ok || pos == 0usize { ret ("", e) }
    let (at, at_error) = uoffset(buf, pos)
    if at_error != ok { ret ("", at_error) }
    let (s, s_error) = string_at(buf, at)
    ret (s, s_error)
}

// A sub-table's position, 0 when absent.
fn get_table(buf: []const u8, table: usize, field: usize) -> (usize, err) {
    let (pos, e) = field_offset(buf, table, field)
    if e != ok || pos == 0usize { ret (0usize, e) }
    let (at, at_error) = uoffset(buf, pos)
    ret (at, at_error)
}

// An inline struct's position, 0 when absent; the caller loads its fields.
fn get_struct(buf: []const u8, table: usize, field: usize) -> (usize, err) {
    let (pos, e) = field_offset(buf, table, field)
    ret (pos, e)
}

// A vector field: the position of its first element and its count; an absent
// field is the empty vector.
fn get_vector(buf: []const u8, table: usize, field: usize) -> (Vector, err) {
    let (pos, e) = field_offset(buf, table, field)
    if e != ok || pos == 0usize { ret (zero, e) }
    let (at, at_error) = uoffset(buf, pos)
    if at_error != ok { ret (zero, at_error) }
    let (n, n_error) = load[u32](buf, at)
    if n_error != ok { ret (zero, n_error) }
    ret (Vector { at: at + 4usize, len: usize(n) }, ok)
}

// A `[u8]` vector's bytes.
fn vector_u8(buf: []const u8, v: Vector) -> ([]const u8, err) {
    if v.at > buf.len || v.len > buf.len - v.at { ret (zero, Invalid) }
    ret (buf[v.at..v.at + v.len], ok)
}

// Element `i` of a scalar vector.
fn vector_at[T: type](buf: []const u8, v: Vector, i: usize) -> (T, err) {
    if i >= v.len { ret (zero, Invalid) }
    let (x, e) = load[T](buf, v.at + i * mem.size_of[T]())
    ret (x, e)
}

fn vector_u16_at(buf: []const u8, v: Vector, i: usize) -> (u16, err) {
    let (x, e) = vector_at[u16](buf, v, i)
    ret (x, e)
}
fn vector_u32_at(buf: []const u8, v: Vector, i: usize) -> (u32, err) {
    let (x, e) = vector_at[u32](buf, v, i)
    ret (x, e)
}
fn vector_u64_at(buf: []const u8, v: Vector, i: usize) -> (u64, err) {
    let (x, e) = vector_at[u64](buf, v, i)
    ret (x, e)
}
fn vector_i32_at(buf: []const u8, v: Vector, i: usize) -> (i32, err) {
    let (x, e) = vector_at[i32](buf, v, i)
    ret (x, e)
}
fn vector_i64_at(buf: []const u8, v: Vector, i: usize) -> (i64, err) {
    let (x, e) = vector_at[i64](buf, v, i)
    ret (x, e)
}
fn vector_f32_at(buf: []const u8, v: Vector, i: usize) -> (f32, err) {
    let (x, e) = vector_at[f32](buf, v, i)
    ret (x, e)
}
fn vector_f64_at(buf: []const u8, v: Vector, i: usize) -> (f64, err) {
    let (x, e) = vector_at[f64](buf, v, i)
    ret (x, e)
}

// Element `i` of a vector of strings.
fn vector_string_at(buf: []const u8, v: Vector, i: usize) -> (str, err) {
    if i >= v.len { ret ("", Invalid) }
    let (at, e) = uoffset(buf, v.at + 4usize * i)
    if e != ok { ret ("", e) }
    let (s, s_error) = string_at(buf, at)
    ret (s, s_error)
}

// Element `i` of a vector of tables: the table's position.
fn vector_table_at(buf: []const u8, v: Vector, i: usize) -> (usize, err) {
    if i >= v.len { ret (0usize, Invalid) }
    let (at, e) = uoffset(buf, v.at + 4usize * i)
    ret (at, e)
}

// A union is a `u8` type field followed by a table field: the type (0 = NONE)...
fn union_type(buf: []const u8, table: usize, field: usize) -> (u8, err) {
    let (t, e) = get[u8](buf, table, field, 0u8)
    ret (t, e)
}

// ...and the value table's position, 0 when absent.
fn union_value(buf: []const u8, table: usize, field: usize) -> (usize, err) {
    let (at, e) = get_table(buf, table, field)
    ret (at, e)
}

// --- Builder: writes from the end of `storage` toward its start; every
// offset it hands out is a distance from the end, as in the reference.
// ponytail: no vtable deduplication, so two tables of one shape carry two
// vtables and the bytes differ from flatc's; the readers do not care.

fn builder(storage: []u8) -> Builder {
    var b: Builder = zero
    b.buf = storage
    b.head = storage.len
    b.minalign = 1usize
    ret b
}

// Bytes written so far; the builder's unit of offset.
fn offset(b: *const Builder) -> usize {
    ret b.buf.len - b.head
}

// Pad so that `additional` more bytes leave the front aligned to `size`.
fn prep(b: *Builder, size: usize, additional: usize) -> err {
    if size > b.minalign { b.minalign = size }
    let pad = (0usize -% (offset(b) + additional)) & (size - 1usize)
    if pad + additional > b.head { ret TooSmall }
    var i = 0usize
    while i < pad {
        b.head -= 1usize
        b.buf[b.head] = 0u8
        i += 1usize
    }
    ret ok
}

// Prepend a scalar, aligned to its own size.
fn put[T: type](b: *Builder, v: T) -> err {
    let size = mem.size_of[T]()
    let e = prep(b, size, 0usize)
    if e != ok { ret e }
    b.head -= size
    ret raw.store[T](b.buf, b.head, v, .Little)
}

fn put_bytes(b: *Builder, data: []const u8) -> err {
    if data.len > b.head { ret TooSmall }
    b.head -= data.len
    mem.copy[u8](b.buf[b.head..b.head + data.len], data)
    ret ok
}

// Prepend a `uoffset` to something already written at `off`.
fn put_offset(b: *Builder, off: usize) -> err {
    let e = prep(b, 4usize, 0usize)
    if e != ok { ret e }
    if off > offset(b) { ret TooSmall }
    let rel = offset(b) - off + 4usize
    ret put[u32](b, u32(rel))
}

fn start_table(b: *Builder, field_count: usize) -> err {
    if field_count > b.slots.len { ret TooSmall }
    var i = 0usize
    while i < field_count {
        b.slots[i] = 0usize
        i += 1usize
    }
    b.slot_count = field_count
    b.table_end = offset(b)
    ret ok
}

// Record that the value just written is field `field` (for inline structs).
fn slot(b: *Builder, field: usize) {
    b.slots[field] = offset(b)
}

// A scalar field; skipped when it equals `fallback`, as the reference does.
fn add[T: type](b: *Builder, field: usize, v: T, fallback: T) -> err {
    if v == fallback { ret ok }
    let e = put[T](b, v)
    if e != ok { ret e }
    slot(b, field)
    ret ok
}

fn add_u8(b: *Builder, field: usize, v: u8, fallback: u8) -> err { ret add[u8](b, field, v, fallback) }
fn add_u16(b: *Builder, field: usize, v: u16, fallback: u16) -> err { ret add[u16](b, field, v, fallback) }
fn add_u32(b: *Builder, field: usize, v: u32, fallback: u32) -> err { ret add[u32](b, field, v, fallback) }
fn add_u64(b: *Builder, field: usize, v: u64, fallback: u64) -> err { ret add[u64](b, field, v, fallback) }
fn add_i16(b: *Builder, field: usize, v: i16, fallback: i16) -> err { ret add[i16](b, field, v, fallback) }
fn add_i32(b: *Builder, field: usize, v: i32, fallback: i32) -> err { ret add[i32](b, field, v, fallback) }
fn add_i64(b: *Builder, field: usize, v: i64, fallback: i64) -> err { ret add[i64](b, field, v, fallback) }
fn add_f32(b: *Builder, field: usize, v: f32, fallback: f32) -> err { ret add[f32](b, field, v, fallback) }
fn add_f64(b: *Builder, field: usize, v: f64, fallback: f64) -> err { ret add[f64](b, field, v, fallback) }

fn add_bool(b: *Builder, field: usize, v: bool, fallback: bool) -> err {
    var x = 0u8
    var d = 0u8
    if v { x = 1u8 }
    if fallback { d = 1u8 }
    ret add[u8](b, field, x, d)
}

// An offset field (string, vector or table written earlier); 0 is skipped.
fn add_offset(b: *Builder, field: usize, off: usize) -> err {
    if off == 0usize { ret ok }
    let e = put_offset(b, off)
    if e != ok { ret e }
    slot(b, field)
    ret ok
}

// Close the table: the soffset, then the vtable in front of it; answers the
// table's offset.
fn end_table(b: *Builder) -> (usize, err) {
    let e = put[i32](b, 0i32)
    if e != ok { ret (0usize, e) }
    let table_offset = offset(b)
    var n = b.slot_count
    while n > 0usize && b.slots[n - 1usize] == 0usize { n -= 1usize }
    var i = n
    while i > 0usize {
        i -= 1usize
        var field = 0usize
        if b.slots[i] != 0usize { field = table_offset - b.slots[i] }
        let field_error = put[u16](b, u16(field & 65535usize))
        if field_error != ok { ret (0usize, field_error) }
    }
    let size_error = put[u16](b, u16((table_offset - b.table_end) & 65535usize))
    if size_error != ok { ret (0usize, size_error) }
    let vsize_error = put[u16](b, u16(((n + 2usize) * 2usize) & 65535usize))
    if vsize_error != ok { ret (0usize, vsize_error) }
    let vt_offset = offset(b)
    let table_pos = b.buf.len - table_offset
    let patch_error = raw.store[i32](b.buf, table_pos, i32((vt_offset - table_offset) & 2147483647usize), .Little)
    ret (table_offset, patch_error)
}

fn create_string(b: *Builder, s: str) -> (usize, err) {
    let e = prep(b, 4usize, s.len + 1usize)
    if e != ok { ret (0usize, e) }
    let nul_error = put_bytes(b, "\x00")
    if nul_error != ok { ret (0usize, nul_error) }
    let copy_error = put_bytes(b, s)
    if copy_error != ok { ret (0usize, copy_error) }
    let len_error = put[u32](b, u32(s.len & 4294967295usize))
    ret (offset(b), len_error)
}

// Elements are prepended in reverse order between these two, with `put` or
// `put_offset`.
fn start_vector(b: *Builder, elem_size: usize, count: usize, alignment: usize) -> err {
    let e = prep(b, 4usize, elem_size * count)
    if e != ok { ret e }
    b.vector_count = count
    ret prep(b, alignment, elem_size * count)
}

fn end_vector(b: *Builder) -> (usize, err) {
    let e = put[u32](b, u32(b.vector_count & 4294967295usize))
    ret (offset(b), e)
}

fn create_vector_u8(b: *Builder, data: []const u8) -> (usize, err) {
    let e = start_vector(b, 1usize, data.len, 1usize)
    if e != ok { ret (0usize, e) }
    let copy_error = put_bytes(b, data)
    if copy_error != ok { ret (0usize, copy_error) }
    let (off, end_error) = end_vector(b)
    ret (off, end_error)
}

// The root offset (and a 4-byte identifier, or "" for none) in front of all.
fn finish(b: *Builder, root_offset: usize, identifier: str) -> err {
    if identifier.len != 0usize && identifier.len != 4usize { ret Invalid }
    let e = prep(b, b.minalign, 4usize + identifier.len)
    if e != ok { ret e }
    let ident_error = put_bytes(b, identifier)
    if ident_error != ok { ret ident_error }
    ret put_offset(b, root_offset)
}

// The finished buffer.
fn bytes(b: *const Builder) -> []const u8 {
    ret b.buf[b.head..]
}
