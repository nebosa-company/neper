// `x.cloud.manifest` against Petcow's own provider/manifest.rs: scripts/manifest_vectors.mjs writes one JSON line per case
// (`{"op":"manifest", "yaml", "e": answer}`) over random and deliberately broken manifests (emitted as JSON flow style);
// the fixture parses the same document and compares the definitions as canonical JSON. A shape error is compared by its
// `invalid document: invalid resource manifest:` prefix (the reference's tail is serde's wording).
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.cloud.manifest as manifest
use x.cloud.rest as rest

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn opt(has: bool, s: str) -> json.Value {
    if has { ret sv(s) }
    ret .Null
}

fn pairs_json(a: *mem.Arena, ps: []const rest.Pair) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, ps.len + 1usize)
    if e != ok { os.exit(84i32) }
    var i = 0usize
    while i < ps.len {
        let (two, te) = mem.alloc[json.Value](a, 2usize)
        two[0] = sv(ps[i].key)
        two[1] = sv(ps[i].value)
        out[i] = json.Value{ Array: two[0usize..2usize] }
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..ps.len] }
}

fn strings_json(a: *mem.Arena, xs: []const str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < xs.len {
        out[i] = sv(xs[i])
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn style_name(n: u8) -> str {
    if n == 1u8 { ret "compute" }
    if n == 2u8 { ret "work_request" }
    ret "lro"
}

fn def_json(a: *mem.Arena, r: manifest.Resource) -> json.Value {
    var o = obj(a)
    put(&o, "type_name", sv(r.type_name))
    put(&o, "create_method", sv(r.create_method))
    put(&o, "item_url", sv(r.item_url))
    put(&o, "create_url", sv(r.create_url))
    put(&o, "list_url", sv(r.list_url))
    put(&o, "list_items_field", sv(r.list_items_field))
    if r.has_marker {
        var m = obj(a)
        put(&m, "field", sv(r.marker.field))
        put(&m, "managed_key", sv(r.marker.managed_key))
        put(&m, "name_key", sv(r.marker.name_key))
        if r.marker.pair {
            var p = obj(a)
            put(&p, "key_field", sv(r.marker.key_field))
            put(&p, "value_field", sv(r.marker.value_field))
            put(&m, "pair", ir.obj_value(&p))
        } else {
            put(&m, "pair", .Null)
        }
        put(&o, "marker", ir.obj_value(&m))
    } else {
        put(&o, "marker", .Null)
    }
    put(&o, "copy_attrs", pairs_json(a, r.copy_attrs))
    put(&o, "output_attrs", strings_json(a, r.output_attrs))
    put(&o, "real_id_field", sv(r.real_id_field))
    put(&o, "name_field", opt(r.has_name_field, r.name_field))
    put(&o, "name_value_template", opt(r.has_name_value_template, r.name_value_template))
    put(&o, "update_method", opt(r.has_update_method, r.update_method))
    put(&o, "update_mask", opt(r.has_update_mask, r.update_mask))
    put(&o, "operation_url", opt(r.has_operation_url, r.operation_url))
    if r.has_timeout {
        put(&o, "operation_timeout_minutes", json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(r.timeout_minutes)) } })
    } else {
        put(&o, "operation_timeout_minutes", .Null)
    }
    put(&o, "operation_style", sv(style_name(r.operation_style)))
    if r.has_create_wrapper {
        var w = obj(a)
        put(&w, "key", sv(r.wrapper_key))
        put(&w, "id_field", opt(r.has_wrapper_id, r.wrapper_id_field))
        put(&o, "create_wrapper", ir.obj_value(&w))
    } else {
        put(&o, "create_wrapper", .Null)
    }
    put(&o, "server_named", json.Value{ Bool: r.server_named })
    put(&o, "name_suffix", opt(r.has_name_suffix, r.name_suffix))
    put(&o, "read_method", opt(r.has_read_method, r.read_method))
    put(&o, "list_method", opt(r.has_list_method, r.list_method))
    put(&o, "delete_method", opt(r.has_delete_method, r.delete_method))
    put(&o, "update_target_url", opt(r.has_update_target_url, r.update_target_url))
    put(&o, "delete_url", opt(r.has_delete_url, r.delete_url))
    if r.has_parent {
        var p = obj(a)
        put(&p, "type_name", sv(r.parent.type_name))
        put(&p, "url_var", sv(r.parent.url_var))
        put(&p, "parent_by_id", json.Value{ Bool: r.parent.parent_by_id })
        put(&o, "parent", ir.obj_value(&p))
    } else {
        put(&o, "parent", .Null)
    }
    put(&o, "create_body_vars", pairs_json(a, r.create_body_vars))
    put(&o, "observed_name_field", opt(r.has_observed_name_field, r.observed_name_field))
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let m = manifest.parse_manifest(a, text_of(c, "yaml"))
    let want = ir.value_of(c, "e")
    let want_ok = ir.truthy(ir.value_of(want, "ok"))
    if !m.valid {
        if want_ok {
            let shown = io.print(f.join(a, "\nGOT error: ", m.message))
            ret false
        }
        let want_error = text_of(want, "error")
        let shape = "invalid document: invalid resource manifest:"
        if str.starts_with(want_error, shape) {
            if str.starts_with(m.message, shape) { ret true }
            let shown = io.print(f.join(a, "\nGOT  ", f.join(a, m.message, f.join(a, "\nWANT ", want_error))))
            ret false
        }
        if str.eq(m.message, want_error) { ret true }
        let shown = io.print(f.join(a, "\nGOT  ", f.join(a, m.message, f.join(a, "\nWANT ", want_error))))
        ret false
    }
    if !want_ok {
        let shown = io.print(f.join(a, "\nGOT ok, WANT ", text_of(want, "error")))
        ret false
    }
    let (out, e) = mem.alloc[json.Value](a, m.resources.len + 1usize)
    if e != ok { os.exit(86i32) }
    var i = 0usize
    while i < m.resources.len {
        var o = obj(a)
        put(&o, "cloud", sv(m.resources[i].cloud))
        put(&o, "def", def_json(a, m.resources[i]))
        out[i] = ir.obj_value(&o)
        i += 1usize
    }
    let (got, ge) = chain.canonical_json(a, json.Value{ Array: out[0usize..m.resources.len] })
    let (expect, we) = chain.canonical_json(a, ir.value_of(want, "v"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got, expect) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", got), f.join(a, "\nWANT ", expect)))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("x cloud manifest ok")
    ret ok
}
