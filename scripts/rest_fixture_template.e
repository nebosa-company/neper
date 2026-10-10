// `x.cloud.rest` against Petcow's own declarative REST helpers and provider registry (provider/declarative.rs and
// provider/mod.rs compiled with thin shims): scripts/rest_vectors.mjs writes one JSON line per case
// (`{"op", ..., "e": answer}`) over random resource definitions, templates, bodies, operations and registry sequences;
// the fixture computes the same answer and compares canonical JSON.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.cloud.rest as rest

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn has_text(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret false }
    let (s, is_text) = ir.string_of(x)
    ret is_text
}

fn flag_of(v: json.Value, key: str) -> bool {
    let x = ir.value_of(v, key)
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn number_of(v: json.Value, key: str) -> i64 {
    let x = ir.value_of(v, key)
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        ret value
    default:
        ret 0i64
    }
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
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

fn bv(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn iv(a: *mem.Arena, n: i64) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(n)) } } }

fn opt_text(v: json.Value, key: str) -> json.Value {
    if has_text(v, key) { ret sv(text_of(v, key)) }
    ret .Null
}

fn strings_json(a: *mem.Arena, xs: []const str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if e != ok { os.exit(84i32) }
    var i = 0usize
    while i < xs.len {
        out[i] = sv(xs[i])
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn pairs_of(a: *mem.Arena, v: json.Value) -> []const rest.Pair {
    let xs = items(v)
    let (out, e) = mem.alloc[rest.Pair](a, xs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < xs.len {
        let two = items(xs[i])
        var k = ""
        var val = ""
        if two.len >= 2usize {
            let (s0, t0) = ir.string_of(two[0])
            let (s1, t1) = ir.string_of(two[1])
            k = s0
            val = s1
        }
        out[i] = rest.Pair { key: k, value: val }
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn vars_of(a: *mem.Arena, v: json.Value) -> []const rest.Pair {
    let (members, is_object) = ir.members_of(ir.value_of(v, "vars"))
    let (out, e) = mem.alloc[rest.Pair](a, members.len + 1usize)
    if e != ok { os.exit(86i32) }
    var i = 0usize
    while i < members.len {
        let (s, is_text) = ir.string_of(members[i].value)
        out[i] = rest.Pair { key: members[i].key, value: s }
        i += 1usize
    }
    ret out[0usize..members.len]
}

fn def_of(a: *mem.Arena, v: json.Value) -> rest.Def {
    let marker = ir.value_of(v, "marker")
    let has_marker = ir.truthy(marker)
    let pair = ir.value_of(marker, "pair")
    let wrapper = ir.value_of(v, "create_wrapper")
    let outputs = items(ir.value_of(v, "output_attrs"))
    let (outs, e) = mem.alloc[str](a, outputs.len + 1usize)
    if e != ok { os.exit(87i32) }
    var i = 0usize
    while i < outputs.len {
        let (s, is_text) = ir.string_of(outputs[i])
        outs[i] = s
        i += 1usize
    }
    var style = 0u8
    let st = text_of(v, "operation_style")
    if str.eq(st, "compute") { style = 1u8 }
    if str.eq(st, "work_request") { style = 2u8 }
    var real_id = text_of(v, "real_id_field")
    if real_id.len == 0usize { real_id = "name" }
    ret rest.Def {
        type_name: text_of(v, "type_name"),
        create_method: text_of(v, "create_method"),
        item_url: text_of(v, "item_url"),
        create_url: text_of(v, "create_url"),
        list_url: text_of(v, "list_url"),
        list_items_field: text_of(v, "list_items_field"),
        has_marker: has_marker,
        marker: rest.Marker { field: text_of(marker, "field"), managed_key: text_of(marker, "managed_key"), name_key: text_of(marker, "name_key"), pair: ir.truthy(pair), key_field: text_of(pair, "key_field"), value_field: text_of(pair, "value_field") },
        copy_attrs: pairs_of(a, ir.value_of(v, "copy_attrs")),
        output_attrs: outs[0usize..outputs.len],
        real_id_field: real_id,
        has_name_field: has_text(v, "name_field"),
        name_field: text_of(v, "name_field"),
        has_name_value_template: has_text(v, "name_value_template"),
        name_value_template: text_of(v, "name_value_template"),
        has_update_mask: has_text(v, "update_mask"),
        update_mask: text_of(v, "update_mask"),
        has_operation_url: has_text(v, "operation_url"),
        operation_url: text_of(v, "operation_url"),
        operation_style: style,
        has_create_wrapper: ir.truthy(wrapper),
        wrapper_key: text_of(wrapper, "key"),
        has_wrapper_id: has_text(wrapper, "id_field"),
        wrapper_id_field: text_of(wrapper, "id_field"),
        has_name_suffix: has_text(v, "name_suffix"),
        name_suffix: text_of(v, "name_suffix"),
        has_observed_name_field: has_text(v, "observed_name_field"),
        observed_name_field: text_of(v, "observed_name_field"),
        create_body_vars: pairs_of(a, ir.value_of(v, "create_body_vars")),
    }
}

fn built_result(a: *mem.Arena, ok_flag: bool, message: str, value: json.Value) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(ok_flag))
    if ok_flag {
        put(&o, "v", value)
    } else {
        put(&o, "error", sv(message))
    }
    ret ir.obj_value(&o)
}

fn status_json(a: *mem.Arena, s: rest.Status) -> json.Value {
    var o = obj(a)
    if s.kind == 0u8 {
        put(&o, "s", sv("done"))
    } else if s.kind == 1u8 {
        put(&o, "s", sv("failed"))
        put(&o, "message", sv(s.message))
    } else {
        put(&o, "s", sv("pending"))
    }
    ret ir.obj_value(&o)
}

fn header_names(a: *mem.Arena, v: json.Value) -> []const str {
    let xs = items(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(88i32) }
    var i = 0usize
    while i < xs.len {
        let two = items(xs[i])
        var s0 = ""
        if two.len >= 1usize {
            let (t, is_t) = ir.string_of(two[0])
            s0 = t
        }
        out[i] = s0
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn header_values(a: *mem.Arena, v: json.Value) -> []const str {
    let xs = items(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(89i32) }
    var i = 0usize
    while i < xs.len {
        let two = items(xs[i])
        var s1 = ""
        if two.len >= 2usize {
            let (t, is_t) = ir.string_of(two[1])
            s1 = t
        }
        out[i] = s1
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "cloud") {
        let (cloud, has_c) = rest.manifest_cloud_for_type(text_of(c, "type"))
        let (prefix, has_p) = rest.type_prefix_for_manifest_cloud(text_of(c, "cloud"))
        var o = obj(a)
        if has_c {
            put(&o, "cloud", sv(cloud))
        } else {
            put(&o, "cloud", .Null)
        }
        if has_p {
            put(&o, "prefix", sv(prefix))
        } else {
            put(&o, "prefix", .Null)
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "registry") {
        var reg = rest.new_registry(a)
        let steps = items(ir.value_of(c, "steps"))
        let (out, e) = mem.alloc[json.Value](a, steps.len + 1usize)
        if e != ok { os.exit(90i32) }
        var i = 0usize
        while i < steps.len {
            let s = steps[i]
            let k = text_of(s, "k")
            let t = text_of(s, "type")
            var r: json.Value = .Null
            if str.eq(k, "register") {
                if !rest.register(&reg, t) {
                    var p = obj(a)
                    put(&p, "panic", bv(true))
                    r = ir.obj_value(&p)
                }
            } else if str.eq(k, "aliased") {
                if !rest.register_aliased(a, &reg, text_of(s, "alias"), t) {
                    var p = obj(a)
                    put(&p, "panic", bv(true))
                    r = ir.obj_value(&p)
                }
            } else if str.eq(k, "bridged") {
                if !rest.register_bridged(&reg, t, text_of(s, "native")) {
                    var p = obj(a)
                    put(&p, "panic", bv(true))
                    r = ir.obj_value(&p)
                }
            } else if str.eq(k, "prefer") {
                rest.prefer_bridged(&reg, t)
            } else if str.eq(k, "isBridged") {
                r = bv(rest.is_bridged(reg, t))
            } else if str.eq(k, "source") {
                let (src, has) = rest.source_of(reg, t)
                if has { r = sv(src) }
            } else if str.eq(k, "resolve") {
                let (ty, src, has) = rest.resolve(reg, t)
                if has {
                    var p = obj(a)
                    put(&p, "type", sv(ty))
                    put(&p, "source", sv(src))
                    r = ir.obj_value(&p)
                }
            } else if str.eq(k, "get") {
                if rest.supports(reg, t) { r = sv(t) }
            } else if str.eq(k, "getAliased") || str.eq(k, "supportsAliased") {
                let ok_alias = rest.supports_aliased(a, reg, t, text_of(s, "alias"), has_text(s, "alias"))
                if str.eq(k, "supportsAliased") {
                    r = bv(ok_alias)
                } else if ok_alias {
                    r = sv(t)
                }
            } else if str.eq(k, "supports") {
                r = bv(rest.supports(reg, t))
            } else {
                r = strings_json(a, rest.registered_types(a, reg))
            }
            out[i] = r
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..steps.len] }
    }
    if str.eq(op, "render") {
        let r = rest.render_with(a, text_of(c, "template"), text_of(c, "name"), ir.value_of(c, "attrs"), vars_of(a, c))
        ret built_result(a, r.valid, r.message, sv(r.value))
    }
    if str.eq(op, "getPath") {
        let (v, found) = rest.get_by_path(ir.value_of(c, "body"), text_of(c, "path"))
        if found { ret v }
        ret .Null
    }
    if str.eq(op, "setPath") {
        let r = rest.set_by_path(a, ir.value_of(c, "obj"), text_of(c, "path"), ir.value_of(c, "value"))
        ret built_result(a, r.valid, r.message, r.value)
    }
    if str.eq(op, "items") {
        let (xs, is_array) = rest.list_items(def_of(a, ir.value_of(c, "def")), ir.value_of(c, "body"))
        if !is_array { ret .Null }
        ret json.Value{ Array: xs }
    }
    let def = def_of(a, ir.value_of(c, "def"))
    let name = text_of(c, "name")
    if str.eq(op, "body") {
        let r = rest.build_body(a, def, name, text_of(c, "nameValue"), ir.value_of(c, "attrs"))
        ret built_result(a, r.valid, r.message, r.value)
    }
    if str.eq(op, "nameValue") {
        let r = rest.body_name_value(a, def, name, vars_of(a, c))
        ret built_result(a, r.valid, r.message, sv(r.value))
    }
    if str.eq(op, "bodyVars") {
        let r = rest.apply_create_body_vars(a, def, ir.value_of(c, "body"), name, ir.value_of(c, "attrs"), vars_of(a, c))
        ret built_result(a, r.valid, r.message, r.value)
    }
    if str.eq(op, "scope") { ret rest.scope_from_real_id(a, text_of(c, "itemUrl"), text_of(c, "realId"), has_text(c, "realId")) }
    if str.eq(op, "address") { ret sv(rest.address(a, def, name)) }
    if str.eq(op, "wrap") { ret rest.wrap_create_body(a, def, name, ir.value_of(c, "body")) }
    if str.eq(op, "parse") { ret rest.parse_attrs(a, def, ir.value_of(c, "body")) }
    if str.eq(op, "updateUrl") { ret sv(rest.update_url(a, text_of(c, "url"), text_of(c, "mask"), has_text(c, "mask"))) }
    if str.eq(op, "mask") {
        let (m, has) = rest.effective_update_mask(a, text_of(c, "curated"), has_text(c, "curated"), ir.value_of(c, "body"))
        if has { ret sv(m) }
        ret .Null
    }
    if str.eq(op, "lroName") {
        let (n, has) = rest.lro_operation_name(def, ir.value_of(c, "body"))
        if has { ret sv(n) }
        ret .Null
    }
    if str.eq(op, "opStatus") { ret status_json(a, rest.operation_status(a, ir.value_of(c, "body"))) }
    if str.eq(op, "opStatusFor") { ret status_json(a, rest.operation_status_for(a, def, ir.value_of(c, "body"))) }
    if str.eq(op, "pollUrl") { ret sv(rest.operation_poll_url(a, text_of(c, "template"), name)) }
    if str.eq(op, "isCompute") { ret bv(rest.is_compute_operation(ir.value_of(c, "body"))) }
    if str.eq(op, "pollTarget") {
        let headers = ir.value_of(c, "headers")
        let (u, has) = rest.operation_poll_target(a, def, ir.value_of(c, "body"), header_names(a, headers), header_values(a, headers))
        if has { ret sv(u) }
        ret .Null
    }
    if str.eq(op, "workRequestId") {
        let headers = ir.value_of(c, "headers")
        let (id, has) = rest.work_request_id(a, header_names(a, headers), header_values(a, headers))
        if has { ret sv(id) }
        ret .Null
    }
    if str.eq(op, "isManaged") { ret bv(rest.is_managed(a, def, ir.value_of(c, "body"))) }
    if str.eq(op, "observedName") {
        let (n, has) = rest.observed_name(a, def, ir.value_of(c, "body"))
        if has { ret sv(n) }
        ret .Null
    }
    if str.eq(op, "observed") {
        let (ob, has) = rest.to_observed(a, def, ir.value_of(c, "body"))
        if !has { ret .Null }
        var o = obj(a)
        put(&o, "name", sv(ob.name))
        put(&o, "type", sv(ob.type_name))
        put(&o, "attributes", ob.attributes)
        if ob.has_real_id {
            put(&o, "realId", sv(ob.real_id))
        } else {
            put(&o, "realId", .Null)
        }
        put(&o, "managed", bv(ob.managed))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "polls") {
        let (mv, has_minutes) = ir.get(c, "minutes")
        ret iv(a, i64(rest.lro_max_polls(u32(number_of(c, "minutes")), has_minutes)))
    }
    if str.eq(op, "settle") {
        let waits = rest.settle_waits(a, u64(number_of(c, "budgetMs")))
        let (out, e) = mem.alloc[json.Value](a, waits.len + 1usize)
        if e != ok { os.exit(91i32) }
        var i = 0usize
        while i < waits.len {
            out[i] = iv(a, i64(waits[i]))
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..waits.len] }
    }
    // isAsync
    ret bv(rest.is_async(def))
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let (got, ge) = chain.canonical_json(a, answer(a, c))
    let (want, we) = chain.canonical_json(a, ir.value_of(c, "e"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got, want) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", got), f.join(a, "\nWANT ", want)))
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
    try io.print("x cloud rest ok")
    ret ok
}
