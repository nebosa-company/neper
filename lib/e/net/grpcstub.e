// Typed gRPC stubs from protocol buffer descriptors (L164): `generate` reads the JSON `e.fmt.protodesc.parse_set`
// answers for a `FileDescriptorSet` and writes the source of one Neper module for everything in it:
//
//   * every message (nested ones and map entries included) as a struct, named by its full name with `.` as `_`
//     (`shop.v1.Order.Line` is `shop_v1_Order_Line`), with `*_write` (fields appended to an `e.fmt.protomsg.Out` in
//     declaration order, the default of an implicit-presence field left out), `*_encode` (arena bytes), `*_read` (the
//     decoder with its nesting depth) and `*_decode` (a struct borrowing the source for its strings and bytes; an unknown
//     field or one of another wire type skipped; a message nested more than 100 deep refused);
//   * every enum value as an `i32` constant (`SHOP_V1_ORDER_STATUS_OPEN`);
//   * every service method as its path (`shop_v1_shop_place_path()` is `/shop.v1.Shop/Place`) and the typed calls
//     of the client state machine: `*_start`, `*_send` (the request encoded and sent, flagged uncompressed) and
//     `*_reply` (the response decoded), and `*_method_index` for a server's routing.
//
// Field types: a scalar is the matching Neper integer, float or bool (`int32` and enums `i32`, `sint*` zigzag, `fixed*`
// and `sfixed*` as their width, `bytes` `[]const u8`); a singular message is `*const T`, `nil` when absent; a repeated
// field is `[]const T`, packed by default in proto3 and when `[packed = true]` in proto2 and read packed or not either
// way; a map field is the repeated entry message it is on the wire, written with both its key and its value. A field with explicit presence (proto2, proto3
// `optional`, a oneof member) carries `has_<name>` and is written when it is set. Oneofs are not folded into unions:
// each member is a field. Groups are skipped; proto2 defaults are not applied; the last occurrence of a singular field
// wins (messages are not merged); unknown fields are dropped.
//
// A field named like a keyword gets a trailing underscore. A type name that is not in the set (a dependency left out of
// it) is a compile error in the generated module, which uses `e.bytes`, `e.data.list`, `e.fmt.protobuf`,
// `e.fmt.protomsg`, `e.mem`, `e.net.grpc`, `e.net.http2` and `e.str`.
//
// Memory: the arena is retained; the text lives there.

use e.algo.ir as ir
use e.algo.sync as sync
use e.fmt.json as json
use e.fmt.protomsg as rt
use e.mem
use e.str

error Invalid

type Gen = struct { a: *mem.Arena, o: rt.Out, good: bool }

// Append text, leaving out carriage returns (a template read from a source with CRLF line ends must not carry them).
fn put(g: *Gen, s: str) {
    var from = 0usize
    var at = 0usize
    while at <= s.len {
        if at == s.len || s[at] == 13u8 {
            if at > from {
                if rt.push_bytes(&g.o, s[from..at]) != ok { g.good = false }
            }
            from = at + 1usize
        }
        at += 1usize
    }
}

fn cat(g: *Gen, x: str, y: str) -> str { ret sync.cat(g.a, x, y) }

fn num_text(g: *Gen, n: i64) -> str {
    let (b, e) = str.builder(g.a, 24usize)
    if e != ok { ret "0" }
    var out = b
    let p = str.push_i64(&out, n)
    ret str.done(&out)
}

// --- text ------------------------------------------------------------------------------------------------------------

fn replace_all(g: *Gen, text: str, needle: str, with: str) -> str {
    let (b, e) = str.builder(g.a, text.len + 64usize)
    if e != ok { g.good = false }
    var out = b
    var at = 0usize
    while at < text.len {
        if at + needle.len <= text.len && str.eq(text[at..at + needle.len], needle) {
            let p = str.push(&out, with)
            at += needle.len
        } else {
            let p = str.push_byte(&out, text[at])
            at += 1usize
        }
    }
    ret str.done(&out)
}

fn text_of(v: json.Value, key: str) -> str {
    let (s, found) = sync.member_text(v, key)
    if !found { ret "" }
    ret s
}

fn lower_text(g: *Gen, s: str) -> str {
    let (out, e) = mem.alloc[u8](g.a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn upper_text(g: *Gen, s: str) -> str {
    let (out, e) = mem.alloc[u8](g.a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn is_upper(c: u8) -> bool { ret c >= 65u8 && c <= 90u8 }

fn is_lower_or_digit(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) }

// `SayHello` as `say_hello`, `HTTPServer` as `http_server`; dots and dashes become `_`.
fn snake(g: *Gen, s: str) -> str {
    let (out, e) = mem.alloc[u8](g.a, s.len * 2usize + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 46u8 || c == 45u8 {
            out[n] = 95u8
            n += 1usize
        } else if is_upper(c) {
            var split = false
            if at > 0usize && s[at - 1usize] != 46u8 && s[at - 1usize] != 95u8 {
                if is_lower_or_digit(s[at - 1usize]) { split = true }
                if is_upper(s[at - 1usize]) && at + 1usize < s.len && s[at + 1usize] >= 97u8 && s[at + 1usize] <= 122u8 { split = true }
            }
            if split {
                out[n] = 95u8
                n += 1usize
            }
            out[n] = c + 32u8
            n += 1usize
        } else {
            out[n] = c
            n += 1usize
        }
        at += 1usize
    }
    ret out[0usize..n]
}

// `.shop.v1.Order.Line` as `shop_v1_Order_Line`.
fn type_ident(g: *Gen, full: str) -> str {
    var s = full
    if s.len > 0usize && s[0] == 46u8 { s = s[1usize..s.len] }
    ret replace_all(g, s, ".", "_")
}

fn is_keyword(s: str) -> bool {
    if str.eq(s, "as") || str.eq(s, "break") || str.eq(s, "const") || str.eq(s, "continue") || str.eq(s, "default") || str.eq(s, "defer") { ret true }
    if str.eq(s, "else") || str.eq(s, "enum") || str.eq(s, "error") || str.eq(s, "extern") || str.eq(s, "false") || str.eq(s, "fn") { ret true }
    if str.eq(s, "for") || str.eq(s, "if") || str.eq(s, "in") || str.eq(s, "isize") || str.eq(s, "let") || str.eq(s, "nil") { ret true }
    if str.eq(s, "nocheck") || str.eq(s, "ok") || str.eq(s, "own") || str.eq(s, "resource") || str.eq(s, "ret") || str.eq(s, "shared") { ret true }
    if str.eq(s, "struct") || str.eq(s, "switch") || str.eq(s, "true") || str.eq(s, "try") || str.eq(s, "type") || str.eq(s, "undef") { ret true }
    if str.eq(s, "union") || str.eq(s, "unreachable") || str.eq(s, "use") || str.eq(s, "usize") || str.eq(s, "var") || str.eq(s, "when") { ret true }
    if str.eq(s, "while") || str.eq(s, "zero") { ret true }
    ret false
}

fn field_ident(g: *Gen, name: str) -> str {
    if is_keyword(name) { ret cat(g, name, "_") }
    ret name
}

// --- field facts -----------------------------------------------------------------------------------------------------

type Info = struct {
    name: str,
    number: u32,
    kind: str,
    repeated: bool,
    explicit: bool,
    packed: bool,
    element: str,
    supported: bool
}

fn kind_of(type_text: str) -> str {
    if str.eq(type_text, "TYPE_DOUBLE") { ret "double" }
    if str.eq(type_text, "TYPE_FLOAT") { ret "float" }
    if str.eq(type_text, "TYPE_INT64") { ret "int64" }
    if str.eq(type_text, "TYPE_UINT64") { ret "uint64" }
    if str.eq(type_text, "TYPE_INT32") { ret "int32" }
    if str.eq(type_text, "TYPE_FIXED64") { ret "fixed64" }
    if str.eq(type_text, "TYPE_FIXED32") { ret "fixed32" }
    if str.eq(type_text, "TYPE_BOOL") { ret "bool" }
    if str.eq(type_text, "TYPE_STRING") { ret "string" }
    if str.eq(type_text, "TYPE_MESSAGE") { ret "message" }
    if str.eq(type_text, "TYPE_BYTES") { ret "bytes" }
    if str.eq(type_text, "TYPE_UINT32") { ret "uint32" }
    if str.eq(type_text, "TYPE_ENUM") { ret "int32" }
    if str.eq(type_text, "TYPE_SFIXED32") { ret "sfixed32" }
    if str.eq(type_text, "TYPE_SFIXED64") { ret "sfixed64" }
    if str.eq(type_text, "TYPE_SINT32") { ret "sint32" }
    if str.eq(type_text, "TYPE_SINT64") { ret "sint64" }
    ret ""
}

fn neper_scalar(kind: str) -> str {
    if str.eq(kind, "double") { ret "f64" }
    if str.eq(kind, "float") { ret "f32" }
    if str.eq(kind, "int64") || str.eq(kind, "sint64") || str.eq(kind, "sfixed64") { ret "i64" }
    if str.eq(kind, "uint64") || str.eq(kind, "fixed64") { ret "u64" }
    if str.eq(kind, "int32") || str.eq(kind, "sint32") || str.eq(kind, "sfixed32") { ret "i32" }
    if str.eq(kind, "uint32") || str.eq(kind, "fixed32") { ret "u32" }
    if str.eq(kind, "bool") { ret "bool" }
    if str.eq(kind, "string") { ret "str" }
    if str.eq(kind, "bytes") { ret "[]const u8" }
    ret ""
}

fn zero_literal(element: str) -> str {
    if str.eq(element, "f64") { ret "0.0f64" }
    if str.eq(element, "f32") { ret "0.0f32" }
    if str.eq(element, "i64") { ret "0i64" }
    if str.eq(element, "u64") { ret "0u64" }
    if str.eq(element, "i32") { ret "0i32" }
    if str.eq(element, "u32") { ret "0u32" }
    ret ""
}

fn packable(kind: str) -> bool {
    ret kind.len > 0usize && !(str.eq(kind, "string") || str.eq(kind, "bytes") || str.eq(kind, "message"))
}

fn info_of(g: *Gen, field: json.Value, proto3: bool) -> Info {
    let name = text_of(field, "name")
    var number = 0u32
    let n = sync.count_value(field, "number", 0i64)
    if n > 0i64 && n < 536870912i64 { number = u32(n) }
    let kind = kind_of(text_of(field, "type"))
    let repeated = str.eq(text_of(field, "label"), "LABEL_REPEATED")
    let (oneof, has_oneof) = sync.get(field, "oneofIndex")
    var explicit = false
    if !repeated && !str.eq(kind, "message") {
        explicit = !proto3 || ir.truthy(ir.value_of(field, "proto3Optional")) || has_oneof
    }
    var packed = false
    if repeated && packable(kind) {
        let options = ir.value_of(field, "options")
        let (flag, has_flag) = sync.get(options, "packed")
        if proto3 {
            packed = !(has_flag && !ir.truthy(flag))
        } else {
            packed = has_flag && ir.truthy(flag)
        }
    }
    var element = neper_scalar(kind)
    if str.eq(kind, "message") { element = type_ident(g, text_of(field, "typeName")) }
    ret Info { name: field_ident(g, name), number: number, kind: kind, repeated: repeated, explicit: explicit, packed: packed, element: element, supported: kind.len > 0usize && number > 0u32 }
}

fn wire_text(kind: str) -> str {
    if str.eq(kind, "double") || str.eq(kind, "fixed64") || str.eq(kind, "sfixed64") { ret ".Fixed64" }
    if str.eq(kind, "float") || str.eq(kind, "fixed32") || str.eq(kind, "sfixed32") { ret ".Fixed32" }
    if str.eq(kind, "string") || str.eq(kind, "bytes") || str.eq(kind, "message") { ret ".Bytes" }
    ret ".Varint"
}

// --- the pieces of generated code ------------------------------------------------------------------------------------

// The statement that appends one value of the field (as the expression `x`) as a keyed field.
fn put_statement(g: *Gen, info: Info, x: str) -> str {
    let number = cat(g, num_text(g, i64(info.number)), "u32")
    var t = ""
    if str.eq(info.kind, "int32") || str.eq(info.kind, "int64") {
        t = "try rt.put_int(o, %NUM%, i64(%X%))"
    } else if str.eq(info.kind, "uint32") || str.eq(info.kind, "uint64") {
        t = "try rt.put_varint(o, %NUM%, u64(%X%))"
    } else if str.eq(info.kind, "sint32") || str.eq(info.kind, "sint64") {
        t = "try rt.put_sint(o, %NUM%, i64(%X%))"
    } else if str.eq(info.kind, "bool") {
        t = "try rt.put_bool(o, %NUM%, %X%)"
    } else if str.eq(info.kind, "fixed32") {
        t = "try rt.put_fixed32(o, %NUM%, %X%)"
    } else if str.eq(info.kind, "fixed64") {
        t = "try rt.put_fixed64(o, %NUM%, %X%)"
    } else if str.eq(info.kind, "sfixed32") {
        t = "try rt.put_fixed32(o, %NUM%, rt.bits_from_i32(%X%))"
    } else if str.eq(info.kind, "sfixed64") {
        t = "try rt.put_fixed64(o, %NUM%, rt.bits_from_i64(%X%))"
    } else if str.eq(info.kind, "float") {
        t = "try rt.put_fixed32(o, %NUM%, rt.f32_bits(%X%))"
    } else if str.eq(info.kind, "double") {
        t = "try rt.put_fixed64(o, %NUM%, rt.f64_bits(%X%))"
    } else {
        t = "try rt.put_bytes(o, %NUM%, %X%)"
    }
    ret replace_all(g, replace_all(g, t, "%NUM%", number), "%X%", x)
}

// The statement that appends one value of a packed list to the list's own buffer `c`.
fn raw_statement(g: *Gen, info: Info, x: str) -> str {
    var t = ""
    if str.eq(info.kind, "int32") || str.eq(info.kind, "int64") {
        t = "try rt.raw_int(&c, i64(%X%))"
    } else if str.eq(info.kind, "uint32") || str.eq(info.kind, "uint64") {
        t = "try rt.raw_varint(&c, u64(%X%))"
    } else if str.eq(info.kind, "sint32") || str.eq(info.kind, "sint64") {
        t = "try rt.raw_sint(&c, i64(%X%))"
    } else if str.eq(info.kind, "bool") {
        t = "if %X% { try rt.raw_varint(&c, 1u64) } else { try rt.raw_varint(&c, 0u64) }"
    } else if str.eq(info.kind, "fixed32") {
        t = "try rt.raw_fixed32(&c, %X%)"
    } else if str.eq(info.kind, "fixed64") {
        t = "try rt.raw_fixed64(&c, %X%)"
    } else if str.eq(info.kind, "sfixed32") {
        t = "try rt.raw_fixed32(&c, rt.bits_from_i32(%X%))"
    } else if str.eq(info.kind, "sfixed64") {
        t = "try rt.raw_fixed64(&c, rt.bits_from_i64(%X%))"
    } else if str.eq(info.kind, "float") {
        t = "try rt.raw_fixed32(&c, rt.f32_bits(%X%))"
    } else {
        t = "try rt.raw_fixed64(&c, rt.f64_bits(%X%))"
    }
    ret replace_all(g, t, "%X%", x)
}

// The condition under which an implicit-presence singular field is written.
fn nonzero_condition(g: *Gen, info: Info, x: str) -> str {
    if str.eq(info.kind, "bool") { ret x }
    if str.eq(info.kind, "string") || str.eq(info.kind, "bytes") { ret cat(g, x, ".len > 0usize") }
    if str.eq(info.kind, "float") { ret cat(g, cat(g, "rt.f32_bits(", x), ") != 0u32") }
    if str.eq(info.kind, "double") { ret cat(g, cat(g, "rt.f64_bits(", x), ") != 0u64") }
    ret cat(g, cat(g, x, " != "), zero_literal(info.element))
}

fn fill(g: *Gen, t: str, info: Info, number: str) -> str {
    var s = replace_all(g, t, "%NUM%", number)
    s = replace_all(g, s, "%FIELD%", info.name)
    s = replace_all(g, s, "%ELEM%", info.element)
    s = replace_all(g, s, "%FN%", snake(g, info.element))
    s = replace_all(g, s, "%WIRE%", wire_text(info.kind))
    ret s
}

fn write_field(g: *Gen, info: Info, always: bool) -> str {
    let number = cat(g, num_text(g, i64(info.number)), "u32")
    if !info.supported { ret "" }
    let member = cat(g, "m.", info.name)
    let element = cat(g, cat(g, member, "[i_"), cat(g, info.name, "]"))
    if info.repeated {
        if str.eq(info.kind, "message") {
            ret fill(g, r#"    var i_%FIELD% = 0usize
    while i_%FIELD% < m.%FIELD%.len {
        var c = rt.out_new(o.a)
        try %FN%_write(&c, &m.%FIELD%[i_%FIELD%])
        try rt.put_message(o, %NUM%, &c)
        i_%FIELD% += 1usize
    }
"#, info, number)
        }
        if info.packed {
            let body = fill(g, r#"    if m.%FIELD%.len > 0usize {
        var c = rt.out_new(o.a)
        var i_%FIELD% = 0usize
        while i_%FIELD% < m.%FIELD%.len {
            %RAW%
            i_%FIELD% += 1usize
        }
        try rt.put_message(o, %NUM%, &c)
    }
"#, info, number)
            ret replace_all(g, body, "%RAW%", raw_statement(g, info, element))
        }
        let body = fill(g, r#"    var i_%FIELD% = 0usize
    while i_%FIELD% < m.%FIELD%.len {
        %PUT%
        i_%FIELD% += 1usize
    }
"#, info, number)
        ret replace_all(g, body, "%PUT%", put_statement(g, info, element))
    }
    if str.eq(info.kind, "message") {
        ret fill(g, r#"    if m.%FIELD% != nil {
        var c = rt.out_new(o.a)
        try %FN%_write(&c, m.%FIELD%)
        try rt.put_message(o, %NUM%, &c)
    }
"#, info, number)
    }
    var condition = nonzero_condition(g, info, member)
    if info.explicit { condition = cat(g, "m.has_", info.name) }
    if always { condition = "true" }
    let body = r#"    if %COND% {
        %PUT%
    }
"#
    ret replace_all(g, replace_all(g, body, "%COND%", condition), "%PUT%", put_statement(g, info, member))
}

// The reader call for a scalar kind over the reader named `reader`.
fn read_call(g: *Gen, kind: str, reader: str) -> str {
    if str.eq(kind, "fixed32") || str.eq(kind, "sfixed32") || str.eq(kind, "float") { ret cat(g, cat(g, "pb.read_fixed32(&", reader), ")") }
    if str.eq(kind, "fixed64") || str.eq(kind, "sfixed64") || str.eq(kind, "double") { ret cat(g, cat(g, "pb.read_fixed64(&", reader), ")") }
    ret cat(g, cat(g, "pb.read_u64(&", reader), ")")
}

// The conversion of a scalar read `v` to the field's type.
fn convert(kind: str) -> str {
    if str.eq(kind, "int32") { ret "rt.trunc_i32(v)" }
    if str.eq(kind, "int64") { ret "rt.i64_from_bits(v)" }
    if str.eq(kind, "uint32") { ret "rt.trunc_u32(v)" }
    if str.eq(kind, "uint64") { ret "v" }
    if str.eq(kind, "sint32") { ret "i32(rt.from_zigzag(v & 4294967295u64))" }
    if str.eq(kind, "sint64") { ret "rt.from_zigzag(v)" }
    if str.eq(kind, "bool") { ret "v != 0u64" }
    if str.eq(kind, "fixed32") || str.eq(kind, "fixed64") { ret "v" }
    if str.eq(kind, "sfixed32") { ret "rt.i32_from_bits(v)" }
    if str.eq(kind, "sfixed64") { ret "rt.i64_from_bits(v)" }
    if str.eq(kind, "float") { ret "rt.bits_f32(v)" }
    if str.eq(kind, "double") { ret "rt.bits_f64(v)" }
    ret "v"
}

fn read_field(g: *Gen, info: Info) -> str {
    let number = cat(g, num_text(g, i64(info.number)), "u32")
    if !info.supported { ret "" }
    var has = ""
    if info.explicit { has = replace_all(g, "            m.has_%FIELD% = true\n", "%FIELD%", info.name) }
    if str.eq(info.kind, "message") {
        if info.repeated {
            ret fill(g, r#"        } else if key.number == %NUM% && key.wire == .Bytes {
            let (length, length_error) = pb.read_u64(&r)
            if length_error != ok { ret (m, pb.Invalid) }
            let (data, data_error) = rt.view_of(source, bytes.remaining_reader(&r.input), length)
            if data_error != ok { ret (m, data_error) }
            if bytes.skip(&r.input, usize(length)) != ok { ret (m, pb.Invalid) }
            let (sub, sub_error) = %FN%_read(a, data, depth + 1u32)
            if sub_error != ok { ret (m, sub_error) }
            let pushed = list.push[%ELEM%](&l_%FIELD%, sub)
            if pushed != ok { ret (m, pushed) }
"#, info, number)
        }
        ret fill(g, r#"        } else if key.number == %NUM% && key.wire == .Bytes {
            let (length, length_error) = pb.read_u64(&r)
            if length_error != ok { ret (m, pb.Invalid) }
            let (data, data_error) = rt.view_of(source, bytes.remaining_reader(&r.input), length)
            if data_error != ok { ret (m, data_error) }
            if bytes.skip(&r.input, usize(length)) != ok { ret (m, pb.Invalid) }
            let (sub, sub_error) = %FN%_read(a, data, depth + 1u32)
            if sub_error != ok { ret (m, sub_error) }
            let (cell, cell_error) = mem.alloc[%ELEM%](a, 1usize)
            if cell_error != ok { ret (m, cell_error) }
            cell[0] = sub
            m.%FIELD% = &cell[0]
"#, info, number)
    }
    if str.eq(info.kind, "string") || str.eq(info.kind, "bytes") {
        if info.repeated {
            ret fill(g, r#"        } else if key.number == %NUM% && key.wire == .Bytes {
            let (length, length_error) = pb.read_u64(&r)
            if length_error != ok { ret (m, pb.Invalid) }
            let (data, data_error) = rt.view_of(source, bytes.remaining_reader(&r.input), length)
            if data_error != ok { ret (m, data_error) }
            if bytes.skip(&r.input, usize(length)) != ok { ret (m, pb.Invalid) }
            let pushed = list.push[%ELEM%](&l_%FIELD%, data)
            if pushed != ok { ret (m, pushed) }
"#, info, number)
        }
        let body = fill(g, r#"        } else if key.number == %NUM% && key.wire == .Bytes {
            let (length, length_error) = pb.read_u64(&r)
            if length_error != ok { ret (m, pb.Invalid) }
            let (data, data_error) = rt.view_of(source, bytes.remaining_reader(&r.input), length)
            if data_error != ok { ret (m, data_error) }
            if bytes.skip(&r.input, usize(length)) != ok { ret (m, pb.Invalid) }
            m.%FIELD% = data
%HAS%"#, info, number)
        ret replace_all(g, body, "%HAS%", has)
    }
    // scalars
    let read = read_call(g, info.kind, "r")
    let conv = convert(info.kind)
    if info.repeated {
        var out = fill(g, r#"        } else if key.number == %NUM% && key.wire == %WIRE% {
            let (v, e) = %READ%
            if e != ok { ret (m, e) }
            let pushed = list.push[%ELEM%](&l_%FIELD%, %CONV%)
            if pushed != ok { ret (m, pushed) }
        } else if key.number == %NUM% && key.wire == .Bytes {
            let (length, length_error) = pb.read_u64(&r)
            if length_error != ok { ret (m, pb.Invalid) }
            let (data, data_error) = rt.view_of(source, bytes.remaining_reader(&r.input), length)
            if data_error != ok { ret (m, data_error) }
            if bytes.skip(&r.input, usize(length)) != ok { ret (m, pb.Invalid) }
            var inner = pb.reader(data)
            while bytes.remaining_reader(&inner.input) > 0usize {
                let (v, e) = %READ_INNER%
                if e != ok { ret (m, e) }
                let pushed = list.push[%ELEM%](&l_%FIELD%, %CONV%)
                if pushed != ok { ret (m, pushed) }
            }
"#, info, number)
        out = replace_all(g, out, "%READ_INNER%", read_call(g, info.kind, "inner"))
        out = replace_all(g, out, "%READ%", read)
        ret replace_all(g, out, "%CONV%", conv)
    }
    var body = fill(g, r#"        } else if key.number == %NUM% && key.wire == %WIRE% {
            let (v, e) = %READ%
            if e != ok { ret (m, e) }
            m.%FIELD% = %CONV%
%HAS%"#, info, number)
    body = replace_all(g, body, "%READ%", read)
    body = replace_all(g, body, "%CONV%", conv)
    ret replace_all(g, body, "%HAS%", has)
}

fn struct_field(g: *Gen, info: Info) -> str {
    if !info.supported { ret "" }
    var out = ""
    if info.explicit { out = cat(g, cat(g, "    has_", info.name), ": bool,\n") }
    var ty = info.element
    if info.repeated {
        ty = cat(g, "[]const ", info.element)
    } else if str.eq(info.kind, "message") {
        ty = cat(g, "*const ", info.element)
    }
    ret cat(g, out, cat(g, cat(g, cat(g, "    ", info.name), cat(g, ": ", ty)), ",\n"))
}

// --- messages, enums, services ---------------------------------------------------------------------------------------

fn emit_enum(g: *Gen, full: str, e: json.Value) {
    let prefix = upper_text(g, type_ident(g, full))
    let values = sync.items(ir.value_of(e, "value"))
    var at = 0usize
    while at < values.len {
        let name = text_of(values[at], "name")
        let number = sync.count_value(values[at], "number", 0i64)
        var line = replace_all(g, "const %NAME%: i32 = %VALUE%i32\n", "%NAME%", cat(g, cat(g, prefix, "_"), upper_text(g, name)))
        line = replace_all(g, line, "%VALUE%", num_text(g, number))
        put(g, line)
        at += 1usize
    }
}

fn emit_message(g: *Gen, full: str, message: json.Value, proto3: bool) {
    let type_name = type_ident(g, full)
    let fn_name = snake(g, type_name)
    let fields = sync.items(ir.value_of(message, "field"))
    // a map entry writes its key and value whatever they hold
    let entry = ir.truthy(ir.value_of(ir.value_of(message, "options"), "mapEntry"))
    var struct_fields = ""
    var writes = ""
    var lists = ""
    var branches = ""
    var finish = ""
    var at = 0usize
    while at < fields.len {
        let info = info_of(g, fields[at], proto3)
        at += 1usize
        if !info.supported { continue }
        struct_fields = cat(g, struct_fields, struct_field(g, info))
        writes = cat(g, writes, write_field(g, info, entry))
        branches = cat(g, branches, read_field(g, info))
        if info.repeated {
            let number = cat(g, num_text(g, i64(info.number)), "u32")
            lists = cat(g, lists, fill(g, r#"    let (l_%FIELD%_made, l_%FIELD%_error) = list.init[%ELEM%](a, 4usize)
    if l_%FIELD%_error != ok { ret (m, l_%FIELD%_error) }
    var l_%FIELD% = l_%FIELD%_made
"#, info, number))
            finish = cat(g, finish, fill(g, "    m.%FIELD% = list.slice_const[%ELEM%](&l_%FIELD%)\n", info, number))
        }
    }
    var t = r#"
type %TYPE% = struct {
%STRUCT%}

fn %FN%_write(o: *rt.Out, m: *const %TYPE%) -> err {
%WRITES%    ret ok
}

fn %FN%_encode(a: *mem.Arena, m: *const %TYPE%) -> ([]const u8, err) {
    var o = rt.out_new(a)
    let written = %FN%_write(&o, m)
    if written != ok { ret (zero, written) }
    ret (rt.out_bytes(&o), ok)
}

fn %FN%_read(a: *mem.Arena, source: []const u8, depth: u32) -> (%TYPE%, err) {
    var m: %TYPE% = zero
    if depth > 100u32 { ret (m, pb.Invalid) }
%LISTS%    var r = pb.reader(source)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (m, key_error) }
        if !more { break }
        if false {
%BRANCHES%        } else {
            if pb.skip(&r, key.wire) != ok { ret (m, pb.Invalid) }
        }
    }
%FINISH%    ret (m, ok)
}

fn %FN%_decode(a: *mem.Arena, source: []const u8) -> (%TYPE%, err) {
    let (m, e) = %FN%_read(a, source, 0u32)
    ret (m, e)
}
"#
    t = replace_all(g, t, "%STRUCT%", struct_fields)
    t = replace_all(g, t, "%WRITES%", writes)
    t = replace_all(g, t, "%LISTS%", lists)
    t = replace_all(g, t, "%BRANCHES%", branches)
    t = replace_all(g, t, "%FINISH%", finish)
    t = replace_all(g, t, "%TYPE%", type_name)
    t = replace_all(g, t, "%FN%", fn_name)
    put(g, t)
}

fn emit_nested(g: *Gen, full: str, message: json.Value, proto3: bool) {
    emit_message(g, full, message, proto3)
    let enums = sync.items(ir.value_of(message, "enumType"))
    var e = 0usize
    while e < enums.len {
        emit_enum(g, cat(g, cat(g, full, "."), text_of(enums[e], "name")), enums[e])
        e += 1usize
    }
    let nested = sync.items(ir.value_of(message, "nestedType"))
    var n = 0usize
    while n < nested.len {
        emit_nested(g, cat(g, cat(g, full, "."), text_of(nested[n], "name")), nested[n], proto3)
        n += 1usize
    }
}

fn emit_service(g: *Gen, package: str, service: json.Value) {
    let name = text_of(service, "name")
    var full = name
    if package.len > 0usize { full = cat(g, cat(g, package, "."), name) }
    let service_fn = snake(g, full)
    let methods = sync.items(ir.value_of(service, "method"))
    var routes = ""
    var at = 0usize
    while at < methods.len {
        let method = methods[at]
        let method_name = text_of(method, "name")
        let path = cat(g, cat(g, cat(g, "/", full), "/"), method_name)
        let method_fn = cat(g, cat(g, service_fn, "_"), snake(g, method_name))
        let request = type_ident(g, text_of(method, "inputType"))
        let response = type_ident(g, text_of(method, "outputType"))
        var shape = "unary"
        let client = ir.truthy(ir.value_of(method, "clientStreaming"))
        let server = ir.truthy(ir.value_of(method, "serverStreaming"))
        if client && server { shape = "bidirectional streaming" }
        if client && !server { shape = "client streaming" }
        if !client && server { shape = "server streaming" }
        var t = r#"
// %PATH%: %SHAPE%.
fn %FN%_path() -> str { ret "%PATH%" }

fn %FN%_start(c: *grpc.Conn, dst: []u8, authority: str, timeout_nanos: u64, metadata: []const h2.Header, buf: []u8) -> (u32, usize, err) {
    let (id, used, e) = grpc.call_start(c, dst, authority, %FN%_path(), timeout_nanos, metadata, buf)
    ret (id, used, e)
}

fn %FN%_send(a: *mem.Arena, c: *grpc.Conn, dst: []u8, id: u32, request: *const %REQ%, end_stream: bool) -> (usize, err) {
    let (body, body_error) = %REQFN%_encode(a, request)
    if body_error != ok { ret (0usize, body_error) }
    let (used, e) = grpc.call_send(c, dst, id, body, false, end_stream)
    ret (used, e)
}

fn %FN%_reply(a: *mem.Arena, payload: []const u8) -> (%RES%, err) {
    let (m, e) = %RESFN%_decode(a, payload)
    ret (m, e)
}
"#
        t = replace_all(g, t, "%PATH%", path)
        t = replace_all(g, t, "%SHAPE%", shape)
        t = replace_all(g, t, "%FN%", method_fn)
        t = replace_all(g, t, "%REQFN%", snake(g, request))
        t = replace_all(g, t, "%RESFN%", snake(g, response))
        t = replace_all(g, t, "%REQ%", request)
        t = replace_all(g, t, "%RES%", response)
        put(g, t)
        var route = "    if str.eq(path, %FN%_path()) { ret %INDEX%i32 }\n"
        route = replace_all(g, route, "%FN%", method_fn)
        route = replace_all(g, route, "%INDEX%", num_text(g, i64(at)))
        routes = cat(g, routes, route)
        at += 1usize
    }
    var router = r#"
// The position of a method of %FULL% among its methods by request path, or -1.
fn %SVC%_method_index(path: str) -> i32 {
%ROUTES%    ret -1i32
}
"#
    router = replace_all(g, router, "%FULL%", full)
    router = replace_all(g, router, "%SVC%", service_fn)
    router = replace_all(g, router, "%ROUTES%", routes)
    put(g, router)
}

// The module text for every file of a descriptor set (the JSON `e.fmt.protodesc.parse_set` answers).
fn generate(a: *mem.Arena, set: json.Value) -> (str, err) {
    var g = Gen { a: a, o: rt.out_new(a), good: true }
    put(&g, "// Generated by e.net.grpcstub from a protocol buffer descriptor set; do not edit.\n")
    put(&g, "use e.bytes\nuse e.data.list as list\nuse e.fmt.protobuf as pb\nuse e.fmt.protomsg as rt\nuse e.mem\nuse e.net.grpc as grpc\nuse e.net.http2 as h2\nuse e.str\n")
    let files = sync.items(ir.value_of(set, "file"))
    var f = 0usize
    while f < files.len {
        let file = files[f]
        f += 1usize
        let package = text_of(file, "package")
        var prefix = ""
        if package.len > 0usize { prefix = cat(&g, ".", package) }
        let proto3 = str.eq(text_of(file, "syntax"), "proto3")
        put(&g, cat(&g, cat(&g, "\n// ", text_of(file, "name")), "\n"))
        let enums = sync.items(ir.value_of(file, "enumType"))
        var en = 0usize
        while en < enums.len {
            emit_enum(&g, cat(&g, cat(&g, prefix, "."), text_of(enums[en], "name")), enums[en])
            en += 1usize
        }
        let messages = sync.items(ir.value_of(file, "messageType"))
        var m = 0usize
        while m < messages.len {
            emit_nested(&g, cat(&g, cat(&g, prefix, "."), text_of(messages[m], "name")), messages[m], proto3)
            m += 1usize
        }
        let services = sync.items(ir.value_of(file, "service"))
        var s = 0usize
        while s < services.len {
            emit_service(&g, package, services[s])
            s += 1usize
        }
    }
    if !g.good { ret ("", Invalid) }
    ret (rt.out_bytes(&g.o), ok)
}
