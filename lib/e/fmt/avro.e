// Avro binary encoding and schema resolution over a caller-array schema model.
// A `Schema` is a forest of nodes in parallel arrays: `kind` per node, `name` the
// type name of a record, enum or fixed and the FIELD or SYMBOL name of a child,
// `children` the record fields, enum symbols (kind `Null`), union branches or the
// single array/map item, `size` for fixed, and `fallback` the pre-encoded default of
// a reader field or the pre-encoded default index of a reader enum (empty = none).
// `decode_resolved` reads a value in the writer schema and re-encodes it in the
// reader schema after the spec's resolution rules: promotions int→long/float/double,
// long→float/double, float→double, string↔bytes; record fields by name (missing in
// the writer → the reader default, missing in the reader → skipped); enum symbols by
// name (unknown → the reader default or `Mismatch`); a writer union reads its branch,
// a reader union takes its first matching branch; arrays and maps by item; fixed by
// name and size. `resolve` is the same test without data.
use e.mem
use e.str

type Kind = enum u8 { Null, Boolean, Int, Long, Float, Double, Bytes, String, Record, Enum, Array, Map, Union, Fixed }
type Schema = struct { kind: []Kind, name: []str, child_start: []usize, child_count: []usize, children: []u32, size: []usize, fallback: []str }
type Decoder = struct { data: []const u8, pos: usize }
type Sink = struct { data: []u8, used: usize }
error Mismatch
error Malformed
error TooSmall

fn decoder(data: []const u8) -> Decoder { ret Decoder { data: data, pos: 0usize } }
fn sink(data: []u8) -> Sink { ret Sink { data: data, used: 0usize } }

fn decode_zigzag(n: u64) -> i64 {
    if (n & 1u64) == 1u64 { ret 0i64 - i64(n >> 1u32) - 1i64 }
    ret i64(n >> 1u32)
}

fn encode_zigzag(v: i64) -> u64 {
    if v >= 0i64 { ret u64(v) << 1u32 }
    ret (u64(0i64 - 1i64 - v) << 1u32) | 1u64
}

fn read_varint(d: *Decoder) -> (u64, err) {
    var value = 0u64
    var shift = 0u32
    var count = 0usize
    var more = true
    while more {
        if count == 10usize || d.pos >= d.data.len { ret (0u64, Malformed) }
        let byte = d.data[d.pos]
        d.pos += 1usize
        if count == 9usize && byte > 1u8 { ret (0u64, Malformed) }
        value = value | (u64(byte & 127u8) << shift)
        count += 1usize
        more = (byte & 128u8) != 0u8
        shift += 7u32
    }
    ret (value, ok)
}

fn read_long(d: *Decoder) -> (i64, err) {
    let (raw, raw_error) = read_varint(d)
    ret (decode_zigzag(raw), raw_error)
}

fn read_int(d: *Decoder) -> (i32, err) {
    let (v, v_error) = read_long(d)
    if v_error != ok { ret (0i32, v_error) }
    if v < 0i64 - 2147483648i64 || v > 2147483647i64 { ret (0i32, Malformed) }
    ret (i32(v), ok)
}

fn read_raw(d: *Decoder, n: usize) -> ([]const u8, err) {
    if n > d.data.len - d.pos { ret (zero, Malformed) }
    let start = d.pos
    d.pos += n
    ret (d.data[start..d.pos], ok)
}

fn skip_raw(d: *Decoder, n: usize) -> err {
    let (taken, taken_error) = read_raw(d, n)
    ret taken_error
}

fn read_le(d: *Decoder, width: usize) -> (u64, err) {
    let (raw, raw_error) = read_raw(d, width)
    if raw_error != ok { ret (0u64, raw_error) }
    var value = 0u64
    var i = 0usize
    while i < width {
        value = value | (u64(raw[i]) << u32(i * 8usize))
        i += 1usize
    }
    ret (value, ok)
}

fn read_boolean(d: *Decoder) -> (bool, err) {
    let (raw, raw_error) = read_raw(d, 1usize)
    if raw_error != ok { ret (false, raw_error) }
    if raw[0] > 1u8 { ret (false, Malformed) }
    ret (raw[0] == 1u8, ok)
}

fn read_float(d: *Decoder) -> (f32, err) {
    let (bits, bits_error) = read_le(d, 4usize)
    if bits_error != ok { ret (0.0f32, bits_error) }
    ret (mem.bitcast[f32](u32(bits)), ok)
}

fn read_double(d: *Decoder) -> (f64, err) {
    let (bits, bits_error) = read_le(d, 8usize)
    if bits_error != ok { ret (0.0f64, bits_error) }
    ret (mem.bitcast[f64](bits), ok)
}

fn read_bytes(d: *Decoder) -> ([]const u8, err) {
    let (n, n_error) = read_long(d)
    if n_error != ok { ret (zero, n_error) }
    if n < 0i64 { ret (zero, Malformed) }
    let (raw, raw_error) = read_raw(d, usize(n))
    ret (raw, raw_error)
}

fn read_string(d: *Decoder) -> (str, err) {
    let (raw, raw_error) = read_bytes(d)
    ret (raw, raw_error)
}

fn write_raw(o: *Sink, data: []const u8) -> err {
    if data.len > o.data.len - o.used { ret TooSmall }
    var i = 0usize
    while i < data.len {
        o.data[o.used + i] = data[i]
        i += 1usize
    }
    o.used += data.len
    ret ok
}

fn write_varint(o: *Sink, value: u64) -> err {
    var raw: [10]u8 = zero
    var count = 0usize
    var v = value
    while v >= 128u64 {
        raw[count] = u8(v & 127u64) | 128u8
        v = v >> 7u32
        count += 1usize
    }
    raw[count] = u8(v)
    count += 1usize
    ret write_raw(o, raw[..count])
}

fn write_long(o: *Sink, v: i64) -> err { ret write_varint(o, encode_zigzag(v)) }

fn write_boolean(o: *Sink, v: bool) -> err {
    var raw: [1]u8 = zero
    if v { raw[0] = 1u8 }
    ret write_raw(o, raw[0..])
}

fn write_le(o: *Sink, value: u64, width: usize) -> err {
    var raw: [8]u8 = zero
    var i = 0usize
    while i < width {
        raw[i] = u8((value >> u32(i * 8usize)) & 255u64)
        i += 1usize
    }
    ret write_raw(o, raw[..width])
}

fn write_float(o: *Sink, v: f32) -> err { ret write_le(o, u64(mem.bitcast[u32](v)), 4usize) }
fn write_double(o: *Sink, v: f64) -> err { ret write_le(o, mem.bitcast[u64](v), 8usize) }

fn write_bytes(o: *Sink, data: []const u8) -> err {
    try write_long(o, i64(data.len))
    ret write_raw(o, data)
}

fn child(s: *const Schema, node: u32, i: usize) -> u32 { ret s.children[s.child_start[usize(node)] + i] }

// The position of the child named `name` under `node`.
fn find_child(s: *const Schema, node: u32, name: str) -> (usize, bool) {
    var i = 0usize
    while i < s.child_count[usize(node)] {
        if str.eq(s.name[usize(child(s, node, i))], name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn read_index(d: *Decoder, s: *const Schema, node: u32) -> (usize, err) {
    let (index, index_error) = read_long(d)
    if index_error != ok { ret (0usize, index_error) }
    if index < 0i64 || u64(index) >= u64(s.child_count[usize(node)]) { ret (0usize, Malformed) }
    ret (usize(index), ok)
}

// Skip one value of `node`'s type.
fn skip(s: *const Schema, node: u32, d: *Decoder) -> err {
    let k = s.kind[usize(node)]
    if k == .Null { ret ok }
    if k == .Boolean { ret skip_raw(d, 1usize) }
    if k == .Int || k == .Long || k == .Enum {
        let (v, v_error) = read_varint(d)
        ret v_error
    }
    if k == .Float { ret skip_raw(d, 4usize) }
    if k == .Double { ret skip_raw(d, 8usize) }
    if k == .Bytes || k == .String {
        let (b, b_error) = read_bytes(d)
        ret b_error
    }
    if k == .Fixed { ret skip_raw(d, s.size[usize(node)]) }
    if k == .Record {
        var i = 0usize
        while i < s.child_count[usize(node)] {
            try skip(s, child(s, node, i), d)
            i += 1usize
        }
        ret ok
    }
    if k == .Union {
        let (index, index_error) = read_index(d, s, node)
        if index_error != ok { ret index_error }
        ret skip(s, child(s, node, index), d)
    }
    // Array or Map: blocks until a zero count; a negative count carries its byte size.
    let (first, first_error) = read_long(d)
    if first_error != ok { ret first_error }
    var n = first
    while n != 0i64 {
        if n < 0i64 {
            let (block_bytes, block_error) = read_long(d)
            if block_error != ok { ret block_error }
            if block_bytes < 0i64 { ret Malformed }
            try skip_raw(d, usize(block_bytes))
        } else {
            var i = 0i64
            while i < n {
                if k == .Map {
                    let (key, key_error) = read_bytes(d)
                    if key_error != ok { ret key_error }
                }
                try skip(s, child(s, node, 0usize), d)
                i += 1i64
            }
        }
        let (again, again_error) = read_long(d)
        if again_error != ok { ret again_error }
        n = again
    }
    ret ok
}

fn promotable(wk: Kind, rk: Kind) -> bool {
    if wk == rk { ret true }
    if wk == .Int { ret rk == .Long || rk == .Float || rk == .Double }
    if wk == .Long { ret rk == .Float || rk == .Double }
    if wk == .Float { ret rk == .Double }
    if wk == .String { ret rk == .Bytes }
    if wk == .Bytes { ret rk == .String }
    ret false
}

// The first reader union branch the writer type resolves against.
fn first_branch(w: *const Schema, wn: u32, r: *const Schema, rn: u32) -> (usize, bool) {
    var i = 0usize
    while i < r.child_count[usize(rn)] {
        if resolve(w, wn, r, child(r, rn, i)) == ok { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// `Mismatch` unless every value of the writer type resolves to the reader type
// (a union is fine when any branch does, an enum when every symbol is known or a
// default stands, a record when every reader field is written or defaulted).
fn resolve(w: *const Schema, wn: u32, r: *const Schema, rn: u32) -> err {
    let wk = w.kind[usize(wn)]
    let rk = r.kind[usize(rn)]
    if wk == .Union {
        var i = 0usize
        while i < w.child_count[usize(wn)] {
            if resolve(w, child(w, wn, i), r, rn) == ok { ret ok }
            i += 1usize
        }
        ret Mismatch
    }
    if rk == .Union {
        let (branch, found) = first_branch(w, wn, r, rn)
        if found { ret ok }
        ret Mismatch
    }
    if !promotable(wk, rk) { ret Mismatch }
    if rk == .Record {
        var i = 0usize
        while i < r.child_count[usize(rn)] {
            let rf = child(r, rn, i)
            let (pos, found) = find_child(w, wn, r.name[usize(rf)])
            if found {
                try resolve(w, child(w, wn, pos), r, rf)
            } else if r.kind[usize(rf)] != .Null && r.fallback[usize(rf)].len == 0usize {
                ret Mismatch
            }
            i += 1usize
        }
        ret ok
    }
    if rk == .Enum {
        if r.fallback[usize(rn)].len > 0usize { ret ok }
        var i = 0usize
        while i < w.child_count[usize(wn)] {
            let (pos, found) = find_child(r, rn, w.name[usize(child(w, wn, i))])
            if !found { ret Mismatch }
            i += 1usize
        }
        ret ok
    }
    if rk == .Array || rk == .Map { ret resolve(w, child(w, wn, 0usize), r, child(r, rn, 0usize)) }
    if rk == .Fixed {
        if w.size[usize(wn)] != r.size[usize(rn)] || !str.eq(w.name[usize(wn)], r.name[usize(rn)]) { ret Mismatch }
    }
    ret ok
}

fn copy_value(w: *const Schema, wn: u32, d: *Decoder, o: *Sink) -> err {
    let start = d.pos
    try skip(w, wn, d)
    ret write_raw(o, d.data[start..d.pos])
}

// Read one value of writer type `wn0` from `d` and append it to `o` encoded in
// reader type `rn0`.
fn decode_resolved(w: *const Schema, wn0: u32, r: *const Schema, rn0: u32, d: *Decoder, o: *Sink) -> err {
    var wn = wn0
    var rn = rn0
    if w.kind[usize(wn)] == .Union {
        let (index, index_error) = read_index(d, w, wn)
        if index_error != ok { ret index_error }
        wn = child(w, wn, index)
    }
    if r.kind[usize(rn)] == .Union {
        let (branch, found) = first_branch(w, wn, r, rn)
        if !found { ret Mismatch }
        try write_long(o, i64(branch))
        rn = child(r, rn, branch)
    }
    let wk = w.kind[usize(wn)]
    let rk = r.kind[usize(rn)]
    if !promotable(wk, rk) { ret Mismatch }
    if rk == .Null { ret ok }
    if rk == .Fixed {
        if w.size[usize(wn)] != r.size[usize(rn)] || !str.eq(w.name[usize(wn)], r.name[usize(rn)]) { ret Mismatch }
        ret copy_value(w, wn, d, o)
    }
    // Same bytes on both sides, int→long and string↔bytes included.
    if rk == .Boolean || rk == .Int || rk == .Long || rk == .Bytes || rk == .String || wk == rk && (rk == .Float || rk == .Double) {
        ret copy_value(w, wn, d, o)
    }
    if rk == .Float || rk == .Double {
        var value = 0.0f64
        if wk == .Float {
            let (f, f_error) = read_float(d)
            if f_error != ok { ret f_error }
            value = f64(f)
        } else {
            let (v, v_error) = read_long(d)
            if v_error != ok { ret v_error }
            value = f64(v)
        }
        if rk == .Float { ret write_float(o, f32(value)) }
        ret write_double(o, value)
    }
    if rk == .Enum {
        let (index, index_error) = read_index(d, w, wn)
        if index_error != ok { ret index_error }
        let (pos, found) = find_child(r, rn, w.name[usize(child(w, wn, index))])
        if found { ret write_long(o, i64(pos)) }
        if r.fallback[usize(rn)].len == 0usize { ret Mismatch }
        ret write_raw(o, r.fallback[usize(rn)])
    }
    if rk == .Record {
        // ponytail: 64 writer fields per record; a caller offsets slice lifts the ceiling.
        var offsets: [64]usize = zero
        let wcount = w.child_count[usize(wn)]
        if wcount > 64usize { ret TooSmall }
        var i = 0usize
        while i < wcount {
            offsets[i] = d.pos
            try skip(w, child(w, wn, i), d)
            i += 1usize
        }
        let after = d.pos
        var j = 0usize
        while j < r.child_count[usize(rn)] {
            let rf = child(r, rn, j)
            let (pos, found) = find_child(w, wn, r.name[usize(rf)])
            if found {
                d.pos = offsets[pos]
                try decode_resolved(w, child(w, wn, pos), r, rf, d, o)
            } else {
                if r.kind[usize(rf)] != .Null && r.fallback[usize(rf)].len == 0usize { ret Mismatch }
                try write_raw(o, r.fallback[usize(rf)])
            }
            j += 1usize
        }
        d.pos = after
        ret ok
    }
    // Array or Map: block by block, every count written positive.
    let witem = child(w, wn, 0usize)
    let ritem = child(r, rn, 0usize)
    let (first, first_error) = read_long(d)
    if first_error != ok { ret first_error }
    var n = first
    while n != 0i64 {
        if n < 0i64 {
            let (block_bytes, block_error) = read_long(d)
            if block_error != ok { ret block_error }
            n = 0i64 - n
        }
        try write_long(o, n)
        var i = 0i64
        while i < n {
            if rk == .Map {
                let (key, key_error) = read_bytes(d)
                if key_error != ok { ret key_error }
                try write_bytes(o, key)
            }
            try decode_resolved(w, witem, r, ritem, d, o)
            i += 1i64
        }
        let (again, again_error) = read_long(d)
        if again_error != ok { ret again_error }
        n = again
    }
    ret write_long(o, 0i64)
}
