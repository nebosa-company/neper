// An object-object mapper in the shape of AutoMapper and Mapster (L139), over `e.meta` field
// reflection: `map_into[S, D]` fills a destination struct from a source struct by convention, and
// `project_sql[S, D]` answers the SELECT list that would fetch only the columns the destination
// needs (the queryable projection). Both walk the destination's fields at compile time, so there
// is no runtime type information and an unmapped field costs nothing.
//
// A destination field is resolved against the source in this order, the first rule that finds a
// compatible source member winning (an incompatible member is not a candidate, so a flattened
// path can still win over a same-named struct):
//   1. an explicit `Rename` (`dest` -> a dotted source path of one to three segments);
//   2. the same name, exactly;
//   3. the same name ignoring case and underscores (`UserName`, `user_name`, `username`);
//   4. flattening: the destination name equals the source path segments joined and compared the
//      same loose way (`addr_city` and `AddrCity` read `addr.city`; up to three levels deep).
// A field in `Profile.ignore` is skipped. A `Default` is the null substitution: it fills a field
// that found no source, and replaces a source that is null -- an empty `str` when `empty_is_null`
// is set, a NaN float. `strict` turns a field with no source and no default into `Unmapped`.
//
// Conversions: integer to integer is range-checked (`Overflow`), integer to float, float to float,
// bool to and from integer, `str` to `str` (copied into the arena), and struct to struct by
// convention again with an empty profile. Float to integer and anything else are not candidates.
// A slice field is a `str`, as in `e.fmt.json` and `e.db.orm`; a struct with another slice type
// does not map.
//
// Not here: collection-valued members beyond `map_all`, enums, pointers, bidirectional profiles
// and compile-time generation of the mapping (MapStruct-style), which ride the comptime work.

use e.mem
use e.meta
use e.str

type Rename = struct { dest: str, src: str }
type Default = struct { dest: str, as_int: i64, as_real: f64, as_str: str }
type Profile = struct { renames: []const Rename, defaults: []const Default, ignore: []const str, strict: bool, empty_is_null: bool }
type Stats = struct { mapped: usize, defaulted: usize, skipped: usize, missing: usize }
type Resolution = struct { score: u32, depth: usize, a: str, b: str, c: str, renamed: bool }

error Overflow
error Incompatible
error Unmapped
error TooSmall

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Consumes `seg` from `dname` at `at`, ignoring case and underscores on both sides.
fn eat(dname: str, at: usize, seg: str) -> (usize, bool) {
    var di = at
    var si = 0usize
    while si < seg.len {
        if seg[si] == 95u8 {
            si += 1usize
            continue
        }
        while di < dname.len && dname[di] == 95u8 { di += 1usize }
        if di >= dname.len { ret (di, false) }
        if lower_byte(dname[di]) != lower_byte(seg[si]) { ret (di, false) }
        di += 1usize
        si += 1usize
    }
    ret (di, true)
}

fn loose_eq(dname: str, a: str, b: str, c: str) -> bool {
    let (d1, ok1) = eat(dname, 0usize, a)
    if !ok1 { ret false }
    let (d2, ok2) = eat(dname, d1, b)
    if !ok2 { ret false }
    let (d3, ok3) = eat(dname, d2, c)
    if !ok3 { ret false }
    var di = d3
    while di < dname.len && dname[di] == 95u8 { di += 1usize }
    ret di == dname.len
}

fn take(src: str, at: usize, seg: str) -> (usize, bool) {
    if at + seg.len > src.len { ret (at, false) }
    var i = 0usize
    while i < seg.len {
        if src[at + i] != seg[i] { ret (at, false) }
        i += 1usize
    }
    ret (at + seg.len, true)
}

// `src` is exactly the first `depth` segments joined with dots.
fn dotted_eq(src: str, depth: usize, a: str, b: str, c: str) -> bool {
    let (p1, ok1) = take(src, 0usize, a)
    if !ok1 { ret false }
    if depth == 1usize { ret p1 == src.len }
    if p1 >= src.len || src[p1] != 46u8 { ret false }
    let (p2, ok2) = take(src, p1 + 1usize, b)
    if !ok2 { ret false }
    if depth == 2usize { ret p2 == src.len }
    if p2 >= src.len || src[p2] != 46u8 { ret false }
    let (p3, ok3) = take(src, p2 + 1usize, c)
    if !ok3 { ret false }
    ret p3 == src.len
}

fn path_score(dname: str, want: str, renamed: bool, depth: usize, a: str, b: str, c: str) -> u32 {
    if renamed {
        if dotted_eq(want, depth, a, b, c) { ret 4u32 }
        ret 0u32
    }
    if depth == 1usize {
        if str.eq(dname, a) { ret 3u32 }
        if loose_eq(dname, a, "", "") { ret 2u32 }
        ret 0u32
    }
    if loose_eq(dname, a, b, c) { ret 1u32 }
    ret 0u32
}

fn rename_of(p: *const Profile, dest: str) -> (str, bool) {
    var i = 0usize
    while i < p.renames.len {
        if str.eq(p.renames[i].dest, dest) { ret (p.renames[i].src, true) }
        i += 1usize
    }
    ret ("", false)
}

fn default_of(p: *const Profile, dest: str) -> (usize, bool) {
    var i = 0usize
    while i < p.defaults.len {
        if str.eq(p.defaults[i].dest, dest) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn ignored(p: *const Profile, dest: str) -> bool {
    var i = 0usize
    while i < p.ignore.len {
        if str.eq(p.ignore[i], dest) { ret true }
        i += 1usize
    }
    ret false
}

// Whether a source member of type `F` can fill a destination of type `G`.
fn compatible[F: type, G: type]() -> bool {
    if meta.kind[F]() == .Int || meta.kind[F]() == .Float || meta.kind[F]() == .Bool {
        if meta.kind[G]() == .Int || meta.kind[G]() == .Float || meta.kind[G]() == .Bool {
            if meta.kind[F]() == .Float && meta.kind[G]() != .Float { ret false }
            ret true
        }
        ret false
    }
    if meta.kind[F]() == .Slice { ret meta.kind[G]() == .Slice }
    if meta.kind[F]() == .Struct { ret meta.kind[G]() == .Struct }
    ret false
}

fn is_null[F: type](x: F, empty_is_null: bool) -> bool {
    if meta.kind[F]() == .Slice { ret empty_is_null && x.len == 0usize }
    if meta.kind[F]() == .Float { ret x != x }
    ret false
}

fn from_default[G: type](d: Default) -> G {
    var out: G = zero
    if meta.kind[G]() == .Int { out = G(d.as_int) }
    if meta.kind[G]() == .Float { out = G(d.as_real) }
    if meta.kind[G]() == .Bool { out = d.as_int != 0i64 }
    if meta.kind[G]() == .Slice { out = d.as_str }
    ret out
}

fn convert[G: type, F: type](a: *mem.Arena, x: F) -> (G, err) {
    var out: G = zero
    if meta.kind[F]() == .Int {
        if meta.kind[G]() == .Int {
            // The cast traps when the value does not fit, so the range is decided first, in the
            // widest type of the source's signedness.
            let bits = u64(mem.size_of[G]() * 8usize)
            if meta.signed[F]() {
                let v = i64(x)
                if meta.signed[G]() {
                    if bits < 64u64 {
                        let hi = i64((1u64 << (bits - 1u64)) - 1u64)
                        if v > hi || v < 0i64 - hi - 1i64 { ret (out, Overflow) }
                    }
                } else {
                    if v < 0i64 { ret (out, Overflow) }
                    if bits < 64u64 && v > i64((1u64 << bits) - 1u64) { ret (out, Overflow) }
                }
            } else {
                let v = u64(x)
                if meta.signed[G]() {
                    if v > (1u64 << (bits - 1u64)) - 1u64 { ret (out, Overflow) }
                } else {
                    if bits < 64u64 && v > (1u64 << bits) - 1u64 { ret (out, Overflow) }
                }
            }
            out = G(x)
            ret (out, ok)
        }
        if meta.kind[G]() == .Float {
            out = G(x)
            ret (out, ok)
        }
        if meta.kind[G]() == .Bool {
            out = x != 0
            ret (out, ok)
        }
        ret (out, Incompatible)
    }
    if meta.kind[F]() == .Float {
        if meta.kind[G]() == .Float {
            out = G(x)
            ret (out, ok)
        }
        ret (out, Incompatible)
    }
    if meta.kind[F]() == .Bool {
        if meta.kind[G]() == .Bool {
            out = x
            ret (out, ok)
        }
        if meta.kind[G]() == .Int {
            if x { out = G(1u8) }
            ret (out, ok)
        }
        if meta.kind[G]() == .Float {
            if x { out = G(1u8) }
            ret (out, ok)
        }
        ret (out, Incompatible)
    }
    if meta.kind[F]() == .Slice {
        if meta.kind[G]() == .Slice {
            let text: str = x
            if text.len == 0usize { ret (out, ok) }
            let (buf, alloc_error) = mem.alloc[u8](a, text.len)
            if alloc_error != ok { ret (out, alloc_error) }
            mem.copy[u8](buf, text)
            out = buf[0..text.len]
            ret (out, ok)
        }
        ret (out, Incompatible)
    }
    if meta.kind[F]() == .Struct {
        if meta.kind[G]() == .Struct {
            var inner = x
            var plain: Profile = zero
            let (stats, map_error) = map_into[F, G](a, &inner, &out, &plain)
            ret (out, map_error)
        }
        ret (out, Incompatible)
    }
    ret (out, Incompatible)
}

// The best source path for destination field `DF`, by names alone.
fn resolve[DF: meta.Field, D: type, S: type](p: *const Profile) -> Resolution {
    var r = Resolution { score: 0u32, depth: 0usize, a: "", b: "", c: "", renamed: false }
    let (want, renamed) = rename_of(p, DF.name)
    r.renamed = renamed
    for sf in meta.fields[S]() {
        let s1 = path_score(DF.name, want, renamed, 1usize, sf.name, "", "")
        if s1 > r.score && compatible[sf.ty, DF.ty]() {
            r = Resolution { score: s1, depth: 1usize, a: sf.name, b: "", c: "", renamed: renamed }
        }
        if meta.kind[sf.ty]() == .Struct {
            for tf in meta.fields[sf.ty]() {
                let s2 = path_score(DF.name, want, renamed, 2usize, sf.name, tf.name, "")
                if s2 > r.score && compatible[tf.ty, DF.ty]() {
                    r = Resolution { score: s2, depth: 2usize, a: sf.name, b: tf.name, c: "", renamed: renamed }
                }
                if meta.kind[tf.ty]() == .Struct {
                    for uf in meta.fields[tf.ty]() {
                        let s3 = path_score(DF.name, want, renamed, 3usize, sf.name, tf.name, uf.name)
                        if s3 > r.score && compatible[uf.ty, DF.ty]() {
                            r = Resolution { score: s3, depth: 3usize, a: sf.name, b: tf.name, c: uf.name, renamed: renamed }
                        }
                    }
                }
            }
        }
    }
    ret r
}

fn put_value[DF: meta.Field, D: type, F: type](a: *mem.Arena, dst: *D, v: F, p: *const Profile, st: *Stats) -> err {
    let (di, has_default) = default_of(p, DF.name)
    if has_default && is_null[F](v, p.empty_is_null) {
        var dv: DF.ty = zero
        dv = from_default[DF.ty](p.defaults[di])
        meta.set[DF, D](dst, dv)
        st.defaulted += 1usize
        ret ok
    }
    let (cv, convert_error) = convert[DF.ty, F](a, v)
    if convert_error != ok { ret convert_error }
    meta.set[DF, D](dst, cv)
    st.mapped += 1usize
    ret ok
}

// Fills `dst` from `src` by the profile; the counts say what happened to each destination field.
fn map_into[S: type, D: type](a: *mem.Arena, src: *const S, dst: *D, p: *const Profile) -> (Stats, err) {
    var st: Stats = zero
    for df in meta.fields[D]() {
        if ignored(p, df.name) {
            st.skipped += 1usize
        } else {
            let res = resolve[df, D, S](p)
            if res.score == 0u32 {
                let (di, has_default) = default_of(p, df.name)
                if has_default {
                    var dv: df.ty = zero
                    dv = from_default[df.ty](p.defaults[di])
                    meta.set[df, D](dst, dv)
                    st.defaulted += 1usize
                } else {
                    st.missing += 1usize
                    if p.strict { ret (st, Unmapped) }
                }
            } else {
                for sf in meta.fields[S]() {
                    if res.depth == 1usize && str.eq(sf.name, res.a) {
                        var v1: sf.ty = zero
                        v1 = meta.get[sf, S](src)
                        let e1 = put_value[df, D, sf.ty](a, dst, v1, p, &st)
                        if e1 != ok { ret (st, e1) }
                    }
                    if meta.kind[sf.ty]() == .Struct {
                        var inner: sf.ty = zero
                        inner = meta.get[sf, S](src)
                        for tf in meta.fields[sf.ty]() {
                            if res.depth == 2usize && str.eq(sf.name, res.a) && str.eq(tf.name, res.b) {
                                var v2: tf.ty = zero
                                v2 = meta.get[tf, sf.ty](&inner)
                                let e2 = put_value[df, D, tf.ty](a, dst, v2, p, &st)
                                if e2 != ok { ret (st, e2) }
                            }
                            if meta.kind[tf.ty]() == .Struct {
                                var inner2: tf.ty = zero
                                inner2 = meta.get[tf, sf.ty](&inner)
                                for uf in meta.fields[tf.ty]() {
                                    if res.depth == 3usize && str.eq(sf.name, res.a) && str.eq(tf.name, res.b) && str.eq(uf.name, res.c) {
                                        var v3: uf.ty = zero
                                        v3 = meta.get[uf, tf.ty](&inner2)
                                        let e3 = put_value[df, D, uf.ty](a, dst, v3, p, &st)
                                        if e3 != ok { ret (st, e3) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ret (st, ok)
}

// Maps every element; `dst` must be at least as long as `src`. The counts are summed.
fn map_all[S: type, D: type](a: *mem.Arena, src: []const S, dst: []D, p: *const Profile) -> (Stats, err) {
    var total: Stats = zero
    if dst.len < src.len { ret (total, TooSmall) }
    var i = 0usize
    while i < src.len {
        var one = src[i]
        var out: D = zero
        let (st, map_error) = map_into[S, D](a, &one, &out, p)
        if map_error != ok { ret (total, map_error) }
        dst[i] = out
        total.mapped += st.mapped
        total.defaulted += st.defaulted
        total.skipped += st.skipped
        total.missing += st.missing
        i += 1usize
    }
    ret (total, ok)
}

// The destination fields no source member, default or ignore entry covers.
fn unmapped[S: type, D: type](p: *const Profile) -> usize {
    var n = 0usize
    for df in meta.fields[D]() {
        if !ignored(p, df.name) {
            let res = resolve[df, D, S](p)
            let (di, has_default) = default_of(p, df.name)
            if res.score == 0u32 && !has_default { n += 1usize }
        }
    }
    ret n
}

// ---- the projection -------------------------------------------------------------------

fn push_column(b: *str.Builder, res: Resolution) -> err {
    try str.push(b, res.a)
    if res.depth >= 2usize {
        try str.push(b, "_")
        try str.push(b, res.b)
    }
    if res.depth >= 3usize {
        try str.push(b, "_")
        try str.push(b, res.c)
    }
    ret ok
}

fn column_is(res: Resolution, name: str) -> bool {
    if res.depth == 1usize { ret str.eq(res.a, name) }
    // a joined name is compared segment by segment, without building it
    let (p1, ok1) = take(name, 0usize, res.a)
    if !ok1 || p1 >= name.len || name[p1] != 95u8 { ret false }
    let (p2, ok2) = take(name, p1 + 1usize, res.b)
    if !ok2 { ret false }
    if res.depth == 2usize { ret p2 == name.len }
    if p2 >= name.len || name[p2] != 95u8 { ret false }
    let (p3, ok3) = take(name, p2 + 1usize, res.c)
    ret ok3 && p3 == name.len
}

fn push_literal_int(b: *str.Builder, v: i64) -> err { ret str.push_i64(b, v) }

fn push_literal_text(b: *str.Builder, s: str) -> err {
    try str.push(b, "'")
    var i = 0usize
    while i < s.len {
        if s[i] == 39u8 { try str.push(b, "'") }
        try str.push_byte(b, s[i])
        i += 1usize
    }
    ret str.push(b, "'")
}

fn push_item[G: type](b: *str.Builder, name: str, has_source: bool, res: Resolution, has_default: bool, d: Default) -> err {
    var wrapped = false
    if has_source && has_default {
        try str.push(b, "COALESCE(")
        wrapped = true
    }
    if has_source {
        try push_column(b, res)
    }
    if has_default {
        if wrapped { try str.push(b, ", ") }
        if meta.kind[G]() == .Slice { try push_literal_text(b, d.as_str) }
        if meta.kind[G]() == .Float { try str.push_f64(b, d.as_real) }
        if meta.kind[G]() == .Int || meta.kind[G]() == .Bool { try push_literal_int(b, d.as_int) }
    }
    if wrapped { try str.push(b, ")") }
    if !has_source || wrapped || !column_is(res, name) {
        try str.push(b, " AS ")
        try str.push(b, name)
    }
    ret ok
}

// `SELECT col [AS field], ... FROM table`: the source columns the destination reads, a flattened
// path being the segments joined with underscores, a default wrapped in COALESCE (or alone). An
// ignored field is left out; a field with no source and no default is `Unmapped` when strict and
// left out otherwise. The builder owns the arena top while it runs.
fn project_sql[S: type, D: type](a: *mem.Arena, table: str, p: *const Profile) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 256usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var first = true
    let head_error = str.push(&b, "SELECT ")
    if head_error != ok { ret ("", head_error) }
    for df in meta.fields[D]() {
        if !ignored(p, df.name) {
            let res = resolve[df, D, S](p)
            let (di, has_default) = default_of(p, df.name)
            let has_source = res.score != 0u32
            if has_source || has_default {
                if !first {
                    let sep_error = str.push(&b, ", ")
                    if sep_error != ok { ret ("", sep_error) }
                }
                first = false
                var d: Default = zero
                if has_default { d = p.defaults[di] }
                let item_error = push_item[df.ty](&b, df.name, has_source, res, has_default, d)
                if item_error != ok { ret ("", item_error) }
            } else {
                if p.strict { ret ("", Unmapped) }
            }
        }
    }
    if first { ret ("", Unmapped) }
    let from_error = str.push(&b, " FROM ")
    if from_error != ok { ret ("", from_error) }
    let table_error = str.push(&b, table)
    if table_error != ok { ret ("", table_error) }
    ret (str.done(&b), ok)
}
