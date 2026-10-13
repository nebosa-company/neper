// What an AWS SDK call puts on the wire before it is signed (L048: the call bodies behind Petcow's AWS drivers), after
// botocore's serializers: the `query` protocol (IAM, STS), its `ec2` variant and `json` (Lightsail, `application/x-amz-json-1.1`),
// driven by the operation's input shape as the service's model gives it. A call is JSON:
//
//   { "protocol": "query" | "ec2" | "json", "name": "CreateRole", "method": "POST", "apiVersion": "2010-05-08",
//     "targetPrefix": "Lightsail_20161128", "jsonVersion": "1.1", "input": "<shape name>",
//     "shapes": { "<name>": { "type": "structure", "members": { "<member>": { "shape": "<name>", "locationName": ... } } }, ... } }
//
// and the parameters are a JSON object given beside it.
//
// `params` is given separately to `build`. `shapes` is the model's own `shapes` object (at least the closure of the input shape); a member reference may carry
// `locationName`, `queryName`, `flattened` and `timestampFormat` that override the shape's. `build` answers
// `{method, path, headers: [[name, value], ...], body}`; the body of a query call is the form-encoded `Action`, `Version`
// and the flattened parameters (`Tags.member.1.Key`, or `TagSpecification.1.Tag.2.Value` for ec2), of a json call the
// `json.dumps` text of the parameters under their wire names. The caller signs it (`x.cloud.awssig`).
//
// Parameters are validated by the SDK before they get here; a member the shape does not know is skipped, not an error,
// and a value of the wrong JSON type is written as its text.
//
// ponytail: `float` and `double` members are written as the JSON number's own text (Python writes `repr`); a timestamp is
// epoch seconds (a JSON number) and is written as `YYYY-MM-DDTHH:MM:SSZ` or, for json, as the integer; `document`
// members and rest-json, rest-xml (S3) and event streams are not here.
//
// Memory: the arena is retained.

use e.algo.ir as ir
use e.algo.sync as sync
use e.bytes
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

type Pair = struct { key: str, value: str }
type Out = struct { a: *mem.Arena, pairs: list.List[Pair], ec2: bool, shapes: json.Value, bad: bool }

fn cat2(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn flag_of(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

// --- shapes ----------------------------------------------------------------------------------------------------------

// A member reference's attribute: the reference's own, else its shape's.
fn attr_text(o: *const Out, ref: json.Value, key: str) -> (str, bool) {
    let (x, found) = ir.get(ref, key)
    if found {
        let (s, is_text) = ir.string_of(x)
        if is_text { ret (s, true) }
    }
    let def = shape_of(o, ref)
    let (y, found2) = ir.get(def, key)
    if found2 {
        let (t, is_text2) = ir.string_of(y)
        if is_text2 { ret (t, true) }
    }
    ret ("", false)
}

fn attr_flag(o: *const Out, ref: json.Value, key: str) -> bool {
    let (x, found) = ir.get(ref, key)
    if found { ret flag_of(ref, key) }
    ret flag_of(shape_of(o, ref), key)
}

fn shape_of(o: *const Out, ref: json.Value) -> json.Value {
    let name = text_of(ref, "shape")
    ret ir.value_of(o.shapes, name)
}

fn type_of(o: *const Out, ref: json.Value) -> str {
    ret text_of(shape_of(o, ref), "type")
}

// --- query and ec2 ---------------------------------------------------------------------------------------------------

fn put(o: *Out, key: str, value: str) {
    let e = list.push[Pair](&o.pairs, Pair { key: key, value: value })
}

fn capitalize(a: *mem.Arena, s: str) -> str {
    if s.len == 0usize { ret s }
    if s[0usize] < 97u8 || s[0usize] > 122u8 { ret s }
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    buf[0usize] = s[0usize] - 32u8
    let out: str = buf[0usize..s.len]
    ret out
}

// `_get_serialized_name`: the query protocol uses `locationName`; ec2 `queryName`, else `locationName` capitalised.
fn wire_name(o: *Out, ref: json.Value, default_name: str) -> str {
    if o.ec2 {
        let (q, has_q) = attr_text(o, ref, "queryName")
        if has_q { ret q }
        let (l, has_l) = attr_text(o, ref, "locationName")
        if has_l { ret capitalize(o.a, l) }
        ret default_name
    }
    let (l2, has_l2) = attr_text(o, ref, "locationName")
    if has_l2 { ret l2 }
    ret default_name
}

fn scalar_text(a: *mem.Arena, v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Number as n:
        ret n.lexeme
    default:
        ret ""
    }
}

fn base64_text(a: *mem.Arena, s: str) -> str {
    let (n, e) = bytes.base64_encoded_len(s.len, true)
    if e != ok { ret "" }
    let (buf, be) = mem.alloc[u8](a, n + 4usize)
    if be != ok { ret "" }
    let (out, ee) = bytes.base64_encode(buf, s, .Standard, true)
    if ee != ok { ret "" }
    ret out
}

fn pad2(b: *str.Builder, n: i64) {
    if n < 10i64 { let e0 = str.push(b, "0") }
    let e1 = str.push_i64(b, n)
}

// Epoch seconds as `YYYY-MM-DDTHH:MM:SSZ`.
fn iso8601(a: *mem.Arena, secs: i64) -> str {
    var days = secs / 86400i64
    var rest = secs - days * 86400i64
    if rest < 0i64 {
        rest += 86400i64
        days -= 1i64
    }
    let z = days + 719468i64
    var era = z / 146097i64
    if z < 0i64 { era = (z - 146096i64) / 146097i64 }
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    let d = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
    var m = mp + 3i64
    if mp >= 10i64 { m = mp - 9i64 }
    var y = yoe + era * 400i64
    if m <= 2i64 { y += 1i64 }
    let (b0, be) = str.builder(a, 40usize)
    if be != ok { ret "" }
    var b = b0
    if y < 1000i64 { let e0 = str.push(&b, "0") }
    if y < 100i64 { let e1 = str.push(&b, "0") }
    if y < 10i64 { let e2 = str.push(&b, "0") }
    let e3 = str.push_i64(&b, y)
    let e4 = str.push(&b, "-")
    pad2(&b, m)
    let e5 = str.push(&b, "-")
    pad2(&b, d)
    let e6 = str.push(&b, "T")
    pad2(&b, rest / 3600i64)
    let e7 = str.push(&b, ":")
    pad2(&b, (rest / 60i64) % 60i64)
    let e8 = str.push(&b, ":")
    pad2(&b, rest % 60i64)
    let e9 = str.push(&b, "Z")
    ret str.done(&b)
}

fn number_i64(v: json.Value) -> i64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e != ok { ret 0i64 }
        ret x
    default:
        ret 0i64
    }
}

fn query_value(o: *Out, v: json.Value, ref: json.Value, prefix: str) {
    let kind = type_of(o, ref)
    if str.eq(kind, "structure") {
        let def = shape_of(o, ref)
        let members = ir.value_of(def, "members")
        let (items, is_object) = ir.members_of(v)
        if !is_object { ret }
        var i = 0usize
        while i < items.len {
            let (m, known) = ir.get(members, items[i].key)
            if known {
                var name = wire_name(o, m, items[i].key)
                if prefix.len > 0usize { name = cat2(o.a, cat2(o.a, prefix, "."), name) }
                query_value(o, items[i].value, m, name)
            }
            i += 1usize
        }
        ret
    }
    if str.eq(kind, "list") {
        let def = shape_of(o, ref)
        let member = ir.value_of(def, "member")
        let (xs, is_array) = ir.items_of(v)
        if !is_array { ret }
        if o.ec2 {
            var i = 0usize
            while i < xs.len {
                query_value(o, xs[i], member, cat2(o.a, cat2(o.a, prefix, "."), index_text(o.a, i + 1usize)))
                i += 1usize
            }
            ret
        }
        if xs.len == 0usize {
            put(o, prefix, "")
            ret
        }
        var list_prefix = prefix
        let (member_name, has_member_name) = attr_text(o, member, "locationName")
        if attr_flag(o, ref, "flattened") {
            if has_member_name && member_name.len > 0usize {
                // replace the last `.Original` with `.name`
                var cut = prefix.len
                var k = prefix.len
                while k > 0usize {
                    k -= 1usize
                    if prefix[k] == 46u8 {
                        cut = k
                        k = 0usize
                    }
                }
                if cut < prefix.len { list_prefix = cat2(o.a, cat2(o.a, prefix[0usize..cut], "."), member_name) } else { list_prefix = member_name }
            }
        } else {
            var name = "member"
            if has_member_name && member_name.len > 0usize { name = member_name }
            list_prefix = cat2(o.a, cat2(o.a, prefix, "."), name)
        }
        var j = 0usize
        while j < xs.len {
            query_value(o, xs[j], member, cat2(o.a, cat2(o.a, list_prefix, "."), index_text(o.a, j + 1usize)))
            j += 1usize
        }
        ret
    }
    if str.eq(kind, "map") {
        let def = shape_of(o, ref)
        let key_ref = ir.value_of(def, "key")
        let value_ref = ir.value_of(def, "value")
        let (entries, is_object) = ir.members_of(v)
        if !is_object { ret }
        var full = prefix
        if !attr_flag(o, ref, "flattened") { full = cat2(o.a, prefix, ".entry") }
        let key_suffix = wire_name(o, key_ref, "key")
        let value_suffix = wire_name(o, value_ref, "value")
        var i = 0usize
        while i < entries.len {
            let at = cat2(o.a, cat2(o.a, full, "."), index_text(o.a, i + 1usize))
            put(o, cat2(o.a, cat2(o.a, at, "."), key_suffix), entries[i].key)
            query_value(o, entries[i].value, value_ref, cat2(o.a, cat2(o.a, at, "."), value_suffix))
            i += 1usize
        }
        ret
    }
    if str.eq(kind, "blob") {
        put(o, prefix, base64_text(o.a, scalar_text(o.a, v)))
        ret
    }
    if str.eq(kind, "timestamp") {
        put(o, prefix, iso8601(o.a, number_i64(v)))
        ret
    }
    if str.eq(kind, "boolean") {
        var yes = false
        switch v {
        case .Bool as b:
            yes = b
        case .Number as n:
            yes = n.lexeme.len > 0usize && !str.eq(n.lexeme, "0")
        case .String as s:
            yes = s.len > 0usize
        default:
            yes = false
        }
        if yes { put(o, prefix, "true") } else { put(o, prefix, "false") }
        ret
    }
    put(o, prefix, scalar_text(o.a, v))
}

fn index_text(a: *mem.Arena, n: usize) -> str {
    let (b0, be) = str.builder(a, 24usize)
    if be != ok { ret "" }
    var b = b0
    let e = str.push_usize(&b, n)
    ret str.done(&b)
}

// `urllib.parse.quote_plus(s, safe='')`: unreserved bytes and `_.-~` stay, a space is `+`, the rest `%XX`.
fn quote_plus(a: *mem.Arena, s: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if e != ok { ret s }
    let digits = "0123456789ABCDEF"
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 46u8 || c == 45u8 || c == 126u8 {
            buf[n] = c
            n += 1usize
        } else if c == 32u8 {
            buf[n] = 43u8
            n += 1usize
        } else {
            buf[n] = 37u8
            buf[n + 1usize] = digits[usize(c >> 4u8)]
            buf[n + 2usize] = digits[usize(c & 15u8)]
            n += 3usize
        }
        i += 1usize
    }
    let out: str = buf[0usize..n]
    ret out
}

fn form_body(a: *mem.Arena, pairs: []const Pair) -> str {
    var total = 0usize
    var i = 0usize
    while i < pairs.len {
        total = total + pairs[i].key.len * 3usize + pairs[i].value.len * 3usize + 2usize
        i += 1usize
    }
    // every piece is quoted before the builder exists, which must be the arena's last allocation to grow
    let (parts, pe) = mem.alloc[str](a, pairs.len * 2usize + 1usize)
    if pe != ok { ret "" }
    i = 0usize
    while i < pairs.len {
        parts[i * 2usize] = quote_plus(a, pairs[i].key)
        parts[i * 2usize + 1usize] = quote_plus(a, pairs[i].value)
        i += 1usize
    }
    let (b1, be1) = str.builder(a, total + 16usize)
    if be1 != ok { ret "" }
    var out = b1
    i = 0usize
    while i < pairs.len {
        if i > 0usize { let e1 = str.push(&out, "&") }
        let e2 = str.push(&out, parts[i * 2usize])
        let e3 = str.push(&out, "=")
        let e4 = str.push(&out, parts[i * 2usize + 1usize])
        i += 1usize
    }
    ret str.done(&out)
}

// --- json ------------------------------------------------------------------------------------------------------------

type Buf = struct { data: []u8, n: usize }

fn bput(b: *Buf, s: str) {
    var i = 0usize
    while i < s.len && b.n < b.data.len {
        b.data[b.n] = s[i]
        b.n += 1usize
        i += 1usize
    }
}

fn bbyte(b: *Buf, c: u8) {
    if b.n < b.data.len {
        b.data[b.n] = c
        b.n += 1usize
    }
}

fn bint(b: *Buf, v: i64) {
    var digits: [24]u8 = zero
    var n = 0usize
    var rest = v
    var negative = false
    if rest < 0i64 {
        negative = true
        rest = 0i64 - rest
    }
    if rest == 0i64 {
        digits[0usize] = 48u8
        n = 1usize
    }
    while rest > 0i64 && n < 24usize {
        digits[n] = u8(48i64 + rest % 10i64)
        rest = rest / 10i64
        n += 1usize
    }
    if negative { bbyte(b, 45u8) }
    while n > 0usize {
        n -= 1usize
        bbyte(b, digits[n])
    }
}

// `json.dumps(s)` of a string (`ensure_ascii`): `\"`, `\\`, `\n`, `\r`, `\t`, `\b`, `\f`, the other controls and every
// non-ASCII scalar as `\uXXXX` (a pair above U+FFFF).
fn dump_string(b: *Buf, s: str) {
    let hex = "0123456789abcdef"
    bput(b, "\"")
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            bput(b, "\\\"")
            i += 1usize
        } else if c == 92u8 {
            bput(b, "\\\\")
            i += 1usize
        } else if c == 10u8 {
            bput(b, "\\n")
            i += 1usize
        } else if c == 13u8 {
            bput(b, "\\r")
            i += 1usize
        } else if c == 9u8 {
            bput(b, "\\t")
            i += 1usize
        } else if c == 8u8 {
            bput(b, "\\b")
            i += 1usize
        } else if c == 12u8 {
            bput(b, "\\f")
            i += 1usize
        } else if c < 32u8 {
            bput(b, "\\u00")
            bbyte(b, hex[usize(c >> 4u8)])
            bbyte(b, hex[usize(c & 15u8)])
            i += 1usize
        } else if c < 128u8 {
            bbyte(b, c)
            i += 1usize
        } else {
            var scalar = 0u32
            var width = 1usize
            if c >= 240u8 {
                scalar = u32(c & 7u8)
                width = 4usize
            } else if c >= 224u8 {
                scalar = u32(c & 15u8)
                width = 3usize
            } else {
                scalar = u32(c & 31u8)
                width = 2usize
            }
            var k = 1usize
            while k < width && i + k < s.len {
                scalar = (scalar << 6u32) | u32(s[i + k] & 63u8)
                k += 1usize
            }
            i += width
            if scalar >= 65536u32 {
                let v = scalar - 65536u32
                dump_u16(b, 55296u32 + (v >> 10u32))
                dump_u16(b, 56320u32 + (v & 1023u32))
            } else {
                dump_u16(b, scalar)
            }
        }
    }
    bput(b, "\"")
}

fn dump_u16(b: *Buf, v: u32) {
    let hex = "0123456789abcdef"
    bput(b, "\\u")
    bbyte(b, hex[usize((v >> 12u32) & 15u32)])
    bbyte(b, hex[usize((v >> 8u32) & 15u32)])
    bbyte(b, hex[usize((v >> 4u32) & 15u32)])
    bbyte(b, hex[usize(v & 15u32)])
}

// One value under its shape reference, written as `json.dumps` would write botocore's translation of it.
fn dump_value(o: *Out, b: *Buf, v: json.Value, ref: json.Value) {
    let kind = type_of(o, ref)
    if str.eq(kind, "structure") {
        let def = shape_of(o, ref)
        let members = ir.value_of(def, "members")
        let (items, is_object) = ir.members_of(v)
        bput(b, "{")
        var wrote = 0usize
        var i = 0usize
        while is_object && i < items.len {
            let (m, known) = ir.get(members, items[i].key)
            if known {
                if wrote > 0usize { bput(b, ", ") }
                var name = items[i].key
                let (l, has_l) = attr_text(o, m, "locationName")
                if has_l { name = l }
                dump_string(b, name)
                bput(b, ": ")
                dump_value(o, b, items[i].value, m)
                wrote += 1usize
            }
            i += 1usize
        }
        bput(b, "}")
        ret
    }
    if str.eq(kind, "list") {
        let def = shape_of(o, ref)
        let member = ir.value_of(def, "member")
        let (xs, is_array) = ir.items_of(v)
        bput(b, "[")
        var i = 0usize
        while is_array && i < xs.len {
            if i > 0usize { bput(b, ", ") }
            dump_value(o, b, xs[i], member)
            i += 1usize
        }
        bput(b, "]")
        ret
    }
    if str.eq(kind, "map") {
        let def = shape_of(o, ref)
        let value_ref = ir.value_of(def, "value")
        let (entries, is_object) = ir.members_of(v)
        bput(b, "{")
        var i = 0usize
        while is_object && i < entries.len {
            if i > 0usize { bput(b, ", ") }
            dump_string(b, entries[i].key)
            bput(b, ": ")
            dump_value(o, b, entries[i].value, value_ref)
            i += 1usize
        }
        bput(b, "}")
        ret
    }
    if str.eq(kind, "blob") {
        dump_string(b, base64_text(o.a, scalar_text(o.a, v)))
        ret
    }
    if str.eq(kind, "timestamp") {
        bint(b, number_i64(v))
        ret
    }
    switch v {
    case .String as s:
        dump_string(b, s)
    case .Bool as t:
        if t { bput(b, "true") } else { bput(b, "false") }
    case .Number as n:
        bput(b, n.lexeme)
    default:
        bput(b, "null")
    }
}

// --- the call --------------------------------------------------------------------------------------------------------

fn header(a: *mem.Arena, name: str, value: str) -> json.Value {
    var l = sync.empty_list(a)
    sync.push_value(&l, sync.text(name))
    sync.push_value(&l, sync.text(value))
    ret json.Value{ Array: list.slice_const[json.Value](&l) }
}

// The request a call makes: `{method, path, headers, body}`; `ok` is false for a protocol this module does not write.
fn build(a: *mem.Arena, call: json.Value, params: json.Value) -> (json.Value, bool) {
    let protocol = text_of(call, "protocol")
    var method = text_of(call, "method")
    if method.len == 0usize { method = "POST" }
    let input_name = text_of(call, "input")
    let (pairs0, pe) = list.init[Pair](a, 64usize)
    if pe != ok { ret (.Null, false) }
    var o = Out { a: a, pairs: pairs0, ec2: str.eq(protocol, "ec2"), shapes: ir.value_of(call, "shapes"), bad: false }
    var out = sync.obj(a)
    sync.put(&out, "method", sync.text(method))
    sync.put(&out, "path", sync.text("/"))
    var headers = sync.empty_list(a)
    if str.eq(protocol, "query") || str.eq(protocol, "ec2") {
        put(&o, "Action", text_of(call, "name"))
        put(&o, "Version", text_of(call, "apiVersion"))
        if input_name.len > 0usize {
            var ref = sync.obj(a)
            sync.put(&ref, "shape", sync.text(input_name))
            query_value(&o, params, ir.obj_value(&ref), "")
        }
        sync.push_value(&headers, header(a, "Content-Type", "application/x-www-form-urlencoded; charset=utf-8"))
        sync.put(&out, "headers", json.Value{ Array: list.slice_const[json.Value](&headers) })
        sync.put(&out, "body", sync.text(form_body(a, list.slice_const[Pair](&o.pairs))))
        ret (ir.obj_value(&out), true)
    }
    if str.eq(protocol, "json") {
        let amz_target = cat2(a, cat2(a, text_of(call, "targetPrefix"), "."), text_of(call, "name"))
        sync.push_value(&headers, header(a, "X-Amz-Target", amz_target))
        sync.push_value(&headers, header(a, "Content-Type", cat2(a, "application/x-amz-json-", text_of(call, "jsonVersion"))))
        sync.put(&out, "headers", json.Value{ Array: list.slice_const[json.Value](&headers) })
        let (data, de) = mem.alloc[u8](a, 262144usize)
        if de != ok { ret (.Null, false) }
        var b = Buf { data: data, n: 0usize }
        if input_name.len > 0usize {
            var ref = sync.obj(a)
            sync.put(&ref, "shape", sync.text(input_name))
            dump_value(&o, &b, params, ir.obj_value(&ref))
        } else {
            bput(&b, "{}")
        }
        let body: str = b.data[0usize..b.n]
        sync.put(&out, "body", sync.text(body))
        ret (ir.obj_value(&out), true)
    }
    ret (.Null, false)
}
