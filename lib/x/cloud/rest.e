// Declarative REST resources and the provider registry (L047), after Petcow's `provider/declarative.rs` (the pure half)
// and `provider/mod.rs`: a `Def` describes a CRUD-shaped REST resource (URL templates, identity through a managed marker or
// a name, attribute mapping, async operation style) and the functions here are everything that needs no network --
// URL placeholder rendering from the resource's own attributes before the cloud context, dotted-path reads and writes,
// the create body with its stamped marker, attribute parsing back from a response, update masks, the three operation
// dialects (Google long-running, Compute self-link, OCI work request), observed name and managed detection, and the
// registry with alias keys and native-versus-bridged precedence (FR-34). Values are JSON; the reference's YAML attribute
// values map onto the same shapes. Error messages are the reference's, `invalid document: ...`.
//
// ponytail: the Provider trait itself and the HTTP execution loop are host code over `e.net.http`, not here; a registry
// entry is its type name.
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.mem
use e.str

type Marker = struct { field: str, managed_key: str, name_key: str, pair: bool, key_field: str, value_field: str }

type Pair = struct { key: str, value: str }

type Parent = struct { type_name: str, url_var: str, parent_by_id: bool }

// Operation styles: 0 long-running (`Lro`), 1 Compute self-link, 2 OCI work request.
type Def = struct { type_name: str, create_method: str, item_url: str, create_url: str, list_url: str, list_items_field: str, has_marker: bool, marker: Marker, copy_attrs: []const Pair, output_attrs: []const str, real_id_field: str, has_name_field: bool, name_field: str, has_name_value_template: bool, name_value_template: str, has_update_mask: bool, update_mask: str, has_operation_url: bool, operation_url: str, operation_style: u8, has_create_wrapper: bool, wrapper_key: str, has_wrapper_id: bool, wrapper_id_field: str, has_name_suffix: bool, name_suffix: str, has_observed_name_field: bool, observed_name_field: str, create_body_vars: []const Pair }

type Rendered = struct { valid: bool, message: str, value: str }

type Built = struct { valid: bool, message: str, value: json.Value }

type Status = struct { kind: u8, message: str }

type Observed = struct { name: str, type_name: str, attributes: json.Value, has_real_id: bool, real_id: str, managed: bool }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn doc_error(a: *mem.Arena, message: str) -> str { ret join(a, "invalid document: ", message) }

// --- manifest clouds -------------------------------------------------------------------------------------------

// The manifest cloud a type name's prefix belongs to; false when the prefix is not declarative.
fn manifest_cloud_for_type(type_name: str) -> (str, bool) {
    var end = 0usize
    while end < type_name.len && type_name[end] != 46u8 { end += 1usize }
    let prefix = type_name[0usize..end]
    if str.eq(prefix, "gcp") { ret ("gcp", true) }
    if str.eq(prefix, "azure") { ret ("azure", true) }
    if str.eq(prefix, "ibm") { ret ("ibm", true) }
    if str.eq(prefix, "oci") { ret ("oci", true) }
    if str.eq(prefix, "ali") { ret ("aliyun", true) }
    ret ("", false)
}

fn type_prefix_for_manifest_cloud(cloud: str) -> (str, bool) {
    if str.eq(cloud, "gcp") { ret ("gcp", true) }
    if str.eq(cloud, "azure") { ret ("azure", true) }
    if str.eq(cloud, "ibm") { ret ("ibm", true) }
    if str.eq(cloud, "oci") { ret ("oci", true) }
    if str.eq(cloud, "aliyun") { ret ("ali", true) }
    ret ("", false)
}

// --- JSON paths ------------------------------------------------------------------------------------------------

// A dotted path read out of a body; objects only, as `serde_json::Value::get(&str)` is.
fn get_by_path(body: json.Value, path: str) -> (json.Value, bool) {
    var cur = body
    var start = 0usize
    var i = 0usize
    while i <= path.len {
        if i == path.len || path[i] == 46u8 {
            let (next, found) = ir.get(cur, path[start..i])
            if !found { ret (.Null, false) }
            cur = next
            start = i + 1usize
        }
        i += 1usize
    }
    ret (cur, true)
}

// The items of a list response; an empty `list_items_field` means the body is the array.
fn list_items(def: Def, body: json.Value) -> ([]const json.Value, bool) {
    if def.list_items_field.len == 0usize {
        let (xs, is_array) = ir.items_of(body)
        ret (xs, is_array)
    }
    let (v, found) = get_by_path(body, def.list_items_field)
    if !found { ret (zero, false) }
    let (xs, is_array) = ir.items_of(v)
    ret (xs, is_array)
}

fn obj_from(a: *mem.Arena, v: json.Value) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    var obj = o
    let ae = ir.assign(&obj, v)
    ret obj
}

fn set_path_at(a: *mem.Arena, base: json.Value, segments: []const str, at: usize, value: json.Value, full: str) -> Built {
    var obj = obj_from(a, base)
    if at + 1usize == segments.len {
        let pe = ir.put(&obj, segments[at], value)
        ret Built { valid: true, message: "", value: ir.obj_value(&obj) }
    }
    let (existing, has) = ir.get(base, segments[at])
    var child = json.Value{ Object: zero }
    if has {
        let (members, is_object) = ir.members_of(existing)
        if !is_object {
            let msg = join(a, join(a, join(a, "name/id field path '", full), join(a, "' expects '", segments[at])), "' to be an object, but it already holds a non-object value")
            ret Built { valid: false, message: doc_error(a, msg), value: .Null }
        }
        child = existing
    }
    let inner = set_path_at(a, child, segments, at + 1usize, value, full)
    if !inner.valid { ret inner }
    let pe = ir.put(&obj, segments[at], inner.value)
    ret Built { valid: true, message: "", value: ir.obj_value(&obj) }
}

fn split_dots(a: *mem.Arena, path: str) -> []const str {
    let (out, e) = mem.alloc[str](a, path.len + 2usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= path.len {
        if i == path.len || path[i] == 46u8 {
            out[n] = path[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// A value written at a dotted path into an object, creating the objects on the way; an intermediate non-object is refused.
fn set_by_path(a: *mem.Arena, obj: json.Value, path: str, value: json.Value) -> Built {
    ret set_path_at(a, obj, split_dots(a, path), 0usize, value, path)
}

// --- rendering -------------------------------------------------------------------------------------------------

fn scalar_text(a: *mem.Arena, v: json.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    case .Number as n:
        ret (n.lexeme, true)
    case .Bool as b:
        if b { ret ("true", true) }
        ret ("false", true)
    default:
        ret ("", false)
    }
}

fn var_lookup(vars: []const Pair, key: str) -> (str, bool) {
    var i = vars.len
    while i > 0usize {
        if str.eq(vars[i - 1usize].key, key) { ret (vars[i - 1usize].value, true) }
        i -= 1usize
    }
    ret ("", false)
}

// `{name}` is the resource name, then an attribute that is a scalar, then the cloud context's variable.
fn render_with(a: *mem.Arena, template: str, name: str, attrs: json.Value, vars: []const Pair) -> Rendered {
    var out = ""
    var at = 0usize
    while at < template.len {
        var open = -1i64
        var k = at
        while k < template.len {
            if template[k] == 123u8 {
                open = i64(k)
                break
            }
            k += 1usize
        }
        if open < 0i64 {
            out = join(a, out, template[at..])
            ret Rendered { valid: true, message: "", value: out }
        }
        out = join(a, out, template[at..usize(open)])
        var close = -1i64
        k = usize(open)
        while k < template.len {
            if template[k] == 125u8 {
                close = i64(k)
                break
            }
            k += 1usize
        }
        if close < 0i64 {
            let msg = join(a, join(a, "unterminated placeholder in '", template), "'")
            ret Rendered { valid: false, message: doc_error(a, msg), value: "" }
        }
        let key = template[usize(open) + 1usize..usize(close)]
        var val = ""
        var have = false
        if str.eq(key, "name") {
            val = name
            have = true
        } else {
            let (attr, has_attr) = ir.get(attrs, key)
            if has_attr {
                let (text, scalar) = scalar_text(a, attr)
                if scalar {
                    val = text
                    have = true
                }
            }
            if !have {
                let (v, found) = var_lookup(vars, key)
                if found {
                    val = v
                    have = true
                }
            }
        }
        if !have {
            let msg = join(a, join(a, "unknown URL variable '{", key), "}'")
            ret Rendered { valid: false, message: doc_error(a, msg), value: "" }
        }
        out = join(a, out, val)
        at = usize(close) + 1usize
    }
    ret Rendered { valid: true, message: "", value: out }
}

// The URL/body address for a resource: its short name plus a declared `name_suffix`.
fn address(a: *mem.Arena, def: Def, name: str) -> str {
    if def.has_name_suffix { ret join(a, name, def.name_suffix) }
    ret name
}

// What `name_field` carries: the rendered full-path template when declared, else the address.
fn body_name_value(a: *mem.Arena, def: Def, name: str, vars: []const Pair) -> Rendered {
    if def.has_name_value_template {
        let none = ir.empty_object()
        ret render_with(a, def.name_value_template, name, none, vars)
    }
    ret Rendered { valid: true, message: "", value: address(a, def, name) }
}

// --- bodies ----------------------------------------------------------------------------------------------------

fn user_labels(a: *mem.Arena, attrs: json.Value, field: str) -> json.Value {
    let (v, found) = ir.get(attrs, field)
    if !found { ret ir.empty_object() }
    let (members, is_object) = ir.members_of(v)
    if !is_object { ret ir.empty_object() }
    let (o, e) = ir.new_obj(a)
    var out = o
    var i = 0usize
    while i < members.len {
        let (s, is_text) = ir.string_of(members[i].value)
        if is_text { let pe = ir.put(&out, members[i].key, members[i].value) }
        i += 1usize
    }
    ret ir.obj_value(&out)
}

// A create/update body: the stamped marker, the copied attributes, then the name field.
fn build_body(a: *mem.Arena, def: Def, name: str, name_value: str, attrs: json.Value) -> Built {
    let (o, e) = ir.new_obj(a)
    var obj = o
    if def.has_marker && !def.marker.pair {
        let m = def.marker
        let (members, is_object) = ir.members_of(user_labels(a, attrs, m.field))
        let (lo, le) = ir.new_obj(a)
        var labels = lo
        var i = 0usize
        while i < members.len {
            if !str.eq(members[i].key, m.managed_key) && !str.eq(members[i].key, m.name_key) {
                let pe = ir.put(&labels, members[i].key, members[i].value)
            }
            i += 1usize
        }
        let p1 = ir.put(&labels, m.managed_key, sv("true"))
        let p2 = ir.put(&labels, m.name_key, sv(name))
        let p3 = ir.put(&obj, m.field, ir.obj_value(&labels))
    }
    var i = 0usize
    while i < def.copy_attrs.len {
        let (v, has) = ir.get(attrs, def.copy_attrs[i].key)
        if has {
            let pe = ir.put(&obj, def.copy_attrs[i].value, v)
        }
        i += 1usize
    }
    var result = ir.obj_value(&obj)
    if def.has_name_field {
        let set = set_by_path(a, result, def.name_field, sv(name_value))
        if !set.valid { ret set }
        result = set.value
    }
    ret Built { valid: true, message: "", value: result }
}

// The create body with `create_body_vars` rendered into it.
fn apply_create_body_vars(a: *mem.Arena, def: Def, body: json.Value, name: str, attrs: json.Value, vars: []const Pair) -> Built {
    if def.create_body_vars.len == 0usize { ret Built { valid: true, message: "", value: body } }
    let (members, is_object) = ir.members_of(body)
    if !is_object {
        ret Built { valid: false, message: doc_error(a, join(a, def.type_name, ": create_body_vars needs a JSON object body")), value: .Null }
    }
    var cur = body
    var i = 0usize
    while i < def.create_body_vars.len {
        let r = render_with(a, def.create_body_vars[i].value, name, attrs, vars)
        if !r.valid { ret Built { valid: false, message: r.message, value: .Null } }
        let set = set_by_path(a, cur, def.create_body_vars[i].key, sv(r.value))
        if !set.valid { ret set }
        cur = set.value
        i += 1usize
    }
    ret Built { valid: true, message: "", value: cur }
}

// `{"<key>": body, "<id_field>": name}` for a wrapper-request API; the body itself otherwise.
fn wrap_create_body(a: *mem.Arena, def: Def, name: str, body: json.Value) -> json.Value {
    if !def.has_create_wrapper { ret body }
    let (o, e) = ir.new_obj(a)
    var out = o
    let p1 = ir.put(&out, def.wrapper_key, body)
    if def.has_wrapper_id { let p2 = ir.put(&out, def.wrapper_id_field, sv(name)) }
    ret ir.obj_value(&out)
}

// The URL-var scope a child's observed `real_id` carries, aligned against the `item_url` template; empty on any mismatch.
fn scope_from_real_id(a: *mem.Arena, item_url: str, real_id: str, has_real_id: bool) -> json.Value {
    let none = ir.empty_object()
    if !has_real_id { ret none }
    let id_segs = split_slashes(a, real_id)
    let tmpl = split_slashes(a, item_url)
    var start = -1i64
    var i = 0usize
    while i < tmpl.len {
        if str.eq(tmpl[i], id_segs[0]) {
            start = i64(i)
            break
        }
        i += 1usize
    }
    if start < 0i64 { ret none }
    let tail_len = tmpl.len - usize(start)
    if tail_len != id_segs.len { ret none }
    let (o, e) = ir.new_obj(a)
    var scope = o
    i = 0usize
    while i < id_segs.len {
        let t = tmpl[usize(start) + i]
        if t.len >= 2usize && t[0] == 123u8 && t[t.len - 1usize] == 125u8 {
            let key = t[1usize..t.len - 1usize]
            if !str.eq(key, "name") { let pe = ir.put(&scope, key, sv(id_segs[i])) }
        } else if !str.eq(t, id_segs[i]) {
            ret none
        }
        i += 1usize
    }
    ret ir.obj_value(&scope)
}

fn split_slashes(a: *mem.Arena, s: str) -> []const str {
    let (out, e) = mem.alloc[str](a, s.len + 2usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 47u8 {
            out[n] = s[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// A response body as observed attributes: copied fields, output-only fields, and the user's marker-field labels.
fn parse_attrs(a: *mem.Arena, def: Def, body: json.Value) -> json.Value {
    let (o, e) = ir.new_obj(a)
    var attrs = o
    var i = 0usize
    while i < def.copy_attrs.len {
        let (v, has) = ir.get(body, def.copy_attrs[i].value)
        if has && !ir.is_null(v) { let pe = ir.put(&attrs, def.copy_attrs[i].key, v) }
        i += 1usize
    }
    i = 0usize
    while i < def.output_attrs.len {
        let (v, has) = ir.get(body, def.output_attrs[i])
        if has && !ir.is_null(v) { let pe = ir.put(&attrs, def.output_attrs[i], v) }
        i += 1usize
    }
    if def.has_marker && !def.marker.pair {
        let (labels, found) = get_by_path(body, def.marker.field)
        let (members, is_object) = ir.members_of(labels)
        if found && is_object {
            let (mo, me) = ir.new_obj(a)
            var kept = mo
            var n = 0usize
            var k = 0usize
            while k < members.len {
                let key = members[k].key
                k += 1usize
                if str.eq(key, def.marker.managed_key) || str.eq(key, def.marker.name_key) { continue }
                let (s, is_text) = ir.string_of(members[k - 1usize].value)
                if is_text {
                    let pe = ir.put(&kept, key, members[k - 1usize].value)
                    n += 1usize
                }
            }
            if n > 0usize { let pe = ir.put(&attrs, def.marker.field, ir.obj_value(&kept)) }
        }
    }
    ret ir.obj_value(&attrs)
}

// --- updates and operations ------------------------------------------------------------------------------------

fn update_url(a: *mem.Arena, item_url: str, mask: str, has_mask: bool) -> str {
    if !has_mask { ret item_url }
    var sep = "?"
    if str.contains(item_url, "?") { sep = "&" }
    ret join(a, join(a, item_url, sep), join(a, "updateMask=", mask))
}

fn trimmed(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && (s[from] == 32u8 || s[from] == 9u8 || s[from] == 10u8 || s[from] == 13u8) { from += 1usize }
    while to > from && (s[to - 1usize] == 32u8 || s[to - 1usize] == 9u8 || s[to - 1usize] == 10u8 || s[to - 1usize] == 13u8) { to -= 1usize }
    ret s[from..to]
}

// The curated mask intersected with the fields the body carries, comma-joined; false when none remain.
fn effective_update_mask(a: *mem.Arena, curated: str, has_curated: bool, body: json.Value) -> (str, bool) {
    if !has_curated { ret ("", false) }
    var out = ""
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= curated.len {
        if i == curated.len || curated[i] == 44u8 {
            let entry = trimmed(curated[start..i])
            start = i + 1usize
            var dot = entry.len
            var k = 0usize
            while k < entry.len {
                if entry[k] == 46u8 {
                    dot = k
                    break
                }
                k += 1usize
            }
            let (v, has) = ir.get(body, entry[0usize..dot])
            if has {
                if n > 0usize { out = join(a, out, ",") }
                out = join(a, out, entry)
                n += 1usize
            }
        }
        i += 1usize
    }
    if n == 0usize { ret ("", false) }
    ret (out, true)
}

// The operation name to poll when the mutation's response is a long-running `Operation`.
fn lro_operation_name(def: Def, body: json.Value) -> (str, bool) {
    if !def.has_operation_url { ret ("", false) }
    let (name, has) = ir.get(body, "name")
    if !has { ret ("", false) }
    let (s, is_text) = ir.string_of(name)
    if !is_text { ret ("", false) }
    if str.starts_with(s, "operations/") || str.contains(s, "/operations/") { ret (s, true) }
    ret ("", false)
}

fn replace_all(a: *mem.Arena, s: str, needle: str, with: str) -> str {
    var out = ""
    var start = 0usize
    var i = 0usize
    while i + needle.len <= s.len {
        if str.eq(s[i..i + needle.len], needle) {
            out = join(a, join(a, out, s[start..i]), with)
            i += needle.len
            start = i
        } else {
            i += 1usize
        }
    }
    ret join(a, out, s[start..])
}

fn operation_poll_url(a: *mem.Arena, template: str, name: str) -> str { ret replace_all(a, template, "{operation}", name) }

fn status(kind: u8, message: str) -> Status { ret Status { kind: kind, message: message } }

// 0 done, 1 failed, 2 pending. `error` wins over `done`.
fn operation_status(a: *mem.Arena, op: json.Value) -> Status {
    let (e, has_error) = ir.get(op, "error")
    if has_error {
        let (text, ce) = chain.canonical_json(a, e)
        ret status(1u8, text)
    }
    let done = ir.value_of(op, "done")
    switch done {
    case .Bool as b:
        if b { ret status(0u8, "") }
    default:
        ret status(2u8, "")
    }
    ret status(2u8, "")
}

fn is_compute_operation(body: json.Value) -> bool {
    let (k, has) = ir.get(body, "kind")
    if !has { ret false }
    let (s, is_text) = ir.string_of(k)
    ret is_text && str.eq(s, "compute#operation")
}

// A work request's id out of the `opc-work-request-id` header (case-insensitive name), trimmed and non-empty.
fn work_request_id(a: *mem.Arena, names: []const str, values: []const str) -> (str, bool) {
    var i = 0usize
    while i < names.len {
        if str.eq(lower(a, names[i]), "opc-work-request-id") {
            let v = trimmed(values[i])
            if v.len > 0usize { ret (v, true) }
            ret ("", false)
        }
        i += 1usize
    }
    ret ("", false)
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn work_request_status(a: *mem.Arena, op: json.Value) -> Status {
    let (sv_, has) = ir.get(op, "status")
    if !has { ret status(2u8, "") }
    let (s, is_text) = ir.string_of(sv_)
    if !is_text { ret status(2u8, "") }
    if str.eq(s, "SUCCEEDED") { ret status(0u8, "") }
    if str.eq(s, "FAILED") || str.eq(s, "CANCELED") || str.eq(s, "CANCELLED") {
        var id = "(no id in the work request body)"
        let (idv, has_id) = ir.get(op, "id")
        if has_id {
            let (t, is_t) = ir.string_of(idv)
            if is_t { id = t }
        }
        ret status(1u8, join(a, join(a, join(a, "work request ", id), join(a, " ended ", s)), " — its reason is at that work request's `/errors` sub-resource, which PetCow does not fetch"))
    }
    ret status(2u8, "")
}

fn compute_operation_status(a: *mem.Arena, op: json.Value) -> Status {
    let (e, has_error) = ir.get(op, "error")
    if has_error && !ir.is_null(e) {
        let (errors, is_array) = ir.items_of(ir.value_of(e, "errors"))
        if is_array && errors.len > 0usize {
            let (text, ce) = chain.canonical_json(a, e)
            let (msg, has_msg) = ir.get(op, "httpErrorMessage")
            var http = ""
            if has_msg {
                let (t, is_t) = ir.string_of(msg)
                if is_t { http = t }
            }
            if http.len == 0usize { ret status(1u8, text) }
            ret status(1u8, join(a, join(a, http, ": "), text))
        }
    }
    let (st, has) = ir.get(op, "status")
    if has {
        let (s, is_text) = ir.string_of(st)
        if is_text && str.eq(s, "DONE") { ret status(0u8, "") }
    }
    ret status(2u8, "")
}

fn operation_status_for(a: *mem.Arena, def: Def, op: json.Value) -> Status {
    if def.operation_style == 1u8 { ret compute_operation_status(a, op) }
    if def.operation_style == 2u8 { ret work_request_status(a, op) }
    ret operation_status(a, op)
}

// The URL to poll for a pending operation, or false when the response is the resource itself.
fn operation_poll_target(a: *mem.Arena, def: Def, body: json.Value, names: []const str, values: []const str) -> (str, bool) {
    if def.operation_style == 0u8 {
        if !def.has_operation_url { ret ("", false) }
        let (name, has) = lro_operation_name(def, body)
        if !has { ret ("", false) }
        ret (operation_poll_url(a, def.operation_url, name), true)
    }
    if def.operation_style == 1u8 {
        if !is_compute_operation(body) { ret ("", false) }
        let (link, has) = ir.get(body, "selfLink")
        if !has { ret ("", false) }
        let (s, is_text) = ir.string_of(link)
        if !is_text { ret ("", false) }
        ret (s, true)
    }
    if !def.has_operation_url { ret ("", false) }
    let (id, has_id) = work_request_id(a, names, values)
    if !has_id { ret ("", false) }
    ret (operation_poll_url(a, def.operation_url, id), true)
}

// Whether the create is asynchronous: an operation URL for the long-running and work-request styles, always for Compute.
fn is_async(def: Def) -> bool {
    if def.operation_style == 1u8 { ret true }
    ret def.has_operation_url
}

// --- identity --------------------------------------------------------------------------------------------------

fn marker_lookup(m: Marker, body: json.Value, key: str) -> (str, bool) {
    let (at, found) = get_by_path(body, m.field)
    if !found { ret ("", false) }
    if !m.pair {
        let (v, has) = ir.get(at, key)
        if !has { ret ("", false) }
        let (s, is_text) = ir.string_of(v)
        ret (s, is_text)
    }
    let (items, is_array) = ir.items_of(at)
    if !is_array { ret ("", false) }
    var i = 0usize
    while i < items.len {
        let (k, has_k) = ir.get(items[i], m.key_field)
        if has_k {
            let (ks, is_text) = ir.string_of(k)
            if is_text && str.eq(ks, key) {
                let (v, has_v) = ir.get(items[i], m.value_field)
                if !has_v { ret ("", false) }
                let (vs, v_text) = ir.string_of(v)
                ret (vs, v_text)
            }
        }
        i += 1usize
    }
    ret ("", false)
}

fn last_segment(s: str) -> str {
    var i = s.len
    while i > 0usize {
        if s[i - 1usize] == 47u8 { ret s[i..] }
        i -= 1usize
    }
    ret s
}

// The resource name a response carries: the marker's name key, an observed-name field, else the id's last segment.
fn observed_name(a: *mem.Arena, def: Def, body: json.Value) -> (str, bool) {
    if def.has_marker {
        let (n, has) = marker_lookup(def.marker, body, def.marker.name_key)
        if has { ret (n, true) }
    }
    if def.has_observed_name_field {
        let (v, found) = get_by_path(body, def.observed_name_field)
        if found {
            let (s, is_text) = ir.string_of(v)
            if is_text { ret (s, true) }
        }
    }
    let (v, found) = get_by_path(body, def.real_id_field)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(v)
    if !is_text { ret ("", false) }
    var id = s
    if def.has_name_suffix && str.ends_with(id, def.name_suffix) { id = id[0usize..id.len - def.name_suffix.len] }
    ret (last_segment(id), true)
}

// Whether the body carries PetCow's managed marker (or, for a name-only type, the `petcow-` name prefix).
fn is_managed(a: *mem.Arena, def: Def, body: json.Value) -> bool {
    if def.has_marker {
        let (v, has) = marker_lookup(def.marker, body, def.marker.managed_key)
        ret has && str.eq(v, "true")
    }
    let (n, has) = observed_name(a, def, body)
    ret has && str.starts_with(n, "petcow-")
}

// A response as an observed resource; false when it has no name.
fn to_observed(a: *mem.Arena, def: Def, body: json.Value) -> (Observed, bool) {
    let (name, has) = observed_name(a, def, body)
    if !has { ret (zero, false) }
    let (rid, has_rid) = get_by_path(body, def.real_id_field)
    var real_id = ""
    var has_real_id = false
    if has_rid {
        let (s, is_text) = ir.string_of(rid)
        if is_text {
            real_id = s
            has_real_id = true
        }
    }
    ret (Observed { name: name, type_name: def.type_name, attributes: parse_attrs(a, def, body), has_real_id: has_real_id, real_id: real_id, managed: str.starts_with(name, "petcow-") }, true)
}

// --- polling budgets -------------------------------------------------------------------------------------------

// Polls allowed for an operation: its timeout in minutes (30 by default, at least 1), twelve a minute.
fn lro_max_polls(minutes: u32, has_minutes: bool) -> u32 {
    var m = 30u32
    if has_minutes { m = minutes }
    if m < 1u32 { m = 1u32 }
    ret m * 12u32
}

// The waits, in milliseconds, that spend `budget_ms`: 500 doubling to a 4000 cap, the last one trimmed.
fn settle_waits(a: *mem.Arena, budget_ms: u64) -> []u64 {
    let (out, e) = mem.alloc[u64](a, 64usize)
    var n = 0usize
    var spent = 0u64
    var wait = 500u64
    while spent < budget_ms && n < 63usize {
        var step = wait
        if budget_ms - spent < step { step = budget_ms - spent }
        out[n] = step
        n += 1usize
        spent += step
        wait = wait * 2u64
        if wait > 4000u64 { wait = 4000u64 }
    }
    ret out[0usize..n]
}

// --- registry --------------------------------------------------------------------------------------------------

type Registry = struct { types: []str, type_count: usize, aliased: []str, aliased_count: usize, bridged: []str, bridged_count: usize, equiv_native: []str, equiv_bridged: []str, equiv_count: usize, preferred: []str, preferred_count: usize }

fn new_registry(a: *mem.Arena) -> Registry {
    let (types, e1) = mem.alloc[str](a, 512usize)
    let (aliased, e2) = mem.alloc[str](a, 512usize)
    let (bridged, e3) = mem.alloc[str](a, 512usize)
    let (en, e4) = mem.alloc[str](a, 512usize)
    let (eb, e5) = mem.alloc[str](a, 512usize)
    let (pref, e6) = mem.alloc[str](a, 512usize)
    ret Registry { types: types, type_count: 0usize, aliased: aliased, aliased_count: 0usize, bridged: bridged, bridged_count: 0usize, equiv_native: en, equiv_bridged: eb, equiv_count: 0usize, preferred: pref, preferred_count: 0usize }
}

fn contains_at(xs: []const str, n: usize, v: str) -> bool {
    var i = 0usize
    while i < n {
        if str.eq(xs[i], v) { ret true }
        i += 1usize
    }
    ret false
}

fn alias_key(a: *mem.Arena, alias: str, type_name: str) -> str { ret join(a, join(a, alias, "\x1f"), type_name) }

// Registers a type; false (the reference panics) on a duplicate.
fn register(r: *Registry, type_name: str) -> bool {
    if contains_at(r.types, r.type_count, type_name) { ret false }
    r.types[r.type_count] = type_name
    r.type_count += 1usize
    ret true
}

fn register_aliased(a: *mem.Arena, r: *Registry, alias: str, type_name: str) -> bool {
    let key = alias_key(a, alias, type_name)
    if contains_at(r.aliased, r.aliased_count, key) { ret false }
    r.aliased[r.aliased_count] = key
    r.aliased_count += 1usize
    ret true
}

// A bridged Terraform provider; `native_equivalent` (empty for none) names the native type it also serves.
fn register_bridged(r: *Registry, type_name: str, native_equivalent: str) -> bool {
    if !contains_at(r.bridged, r.bridged_count, type_name) {
        r.bridged[r.bridged_count] = type_name
        r.bridged_count += 1usize
    }
    if native_equivalent.len > 0usize {
        var at = r.equiv_count
        var i = 0usize
        while i < r.equiv_count {
            if str.eq(r.equiv_native[i], native_equivalent) { at = i }
            i += 1usize
        }
        r.equiv_native[at] = native_equivalent
        r.equiv_bridged[at] = type_name
        if at == r.equiv_count { r.equiv_count += 1usize }
    }
    if contains_at(r.types, r.type_count, type_name) { ret false }
    r.types[r.type_count] = type_name
    r.type_count += 1usize
    ret true
}

fn prefer_bridged(r: *Registry, native_type: str) {
    if !contains_at(r.preferred, r.preferred_count, native_type) {
        r.preferred[r.preferred_count] = native_type
        r.preferred_count += 1usize
    }
}

fn is_bridged(r: Registry, type_name: str) -> bool { ret contains_at(r.bridged, r.bridged_count, type_name) }

fn has_equivalent(r: Registry, native: str) -> (str, bool) {
    var i = 0usize
    while i < r.equiv_count {
        if str.eq(r.equiv_native[i], native) { ret (r.equiv_bridged[i], true) }
        i += 1usize
    }
    ret ("", false)
}

// The source that would serve a type: "bridged", "native", or false when none does.
fn source_of(r: Registry, type_name: str) -> (str, bool) {
    if contains_at(r.bridged, r.bridged_count, type_name) { ret ("bridged", true) }
    if contains_at(r.types, r.type_count, type_name) {
        let (eq, has_eq) = has_equivalent(r, type_name)
        if contains_at(r.preferred, r.preferred_count, type_name) && has_eq { ret ("bridged", true) }
        ret ("native", true)
    }
    ret ("", false)
}

// The provider type and source that actually serve a type, honouring the opted-in bridged equivalent.
fn resolve(r: Registry, type_name: str) -> (str, str, bool) {
    let (src, has) = source_of(r, type_name)
    if !has { ret ("", "", false) }
    if str.eq(src, "bridged") && !contains_at(r.bridged, r.bridged_count, type_name) {
        let (eq, has_eq) = has_equivalent(r, type_name)
        if !has_eq { ret ("", "", false) }
        if !contains_at(r.types, r.type_count, eq) { ret ("", "", false) }
        ret (eq, "bridged", true)
    }
    if !contains_at(r.types, r.type_count, type_name) { ret ("", "", false) }
    ret (type_name, src, true)
}

fn supports(r: Registry, type_name: str) -> bool { ret contains_at(r.types, r.type_count, type_name) }

fn supports_aliased(a: *mem.Arena, r: Registry, type_name: str, alias: str, has_alias: bool) -> bool {
    if !has_alias { ret supports(r, type_name) }
    ret contains_at(r.aliased, r.aliased_count, alias_key(a, alias, type_name))
}

// All registered type names, sorted.
fn registered_types(a: *mem.Arena, r: Registry) -> []const str {
    let (out, e) = mem.alloc[str](a, r.type_count + 1usize)
    var i = 0usize
    while i < r.type_count {
        out[i] = r.types[i]
        i += 1usize
    }
    i = 1usize
    while i < r.type_count {
        let cur = out[i]
        var j = i
        while j > 0usize && str.compare(out[j - 1usize], cur) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..r.type_count]
}
