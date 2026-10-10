// `x.identity.scim` against Appdor's own src/identity/scim-protocol.js: scripts/scim_vectors.mjs writes one JSON line per
// case (`{"op", ..., "e": answer}`) over random resources, filters, PATCH operations, projections and list parameters;
// the fixture computes the same answer and compares canonical JSON.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.identity.scim as scim

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
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

fn lower_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn opt_base(c: json.Value) -> str {
    let b = text_of(c, "base")
    if b.len == 0usize { ret "/scim/v2" }
    ret b
}

fn ast_json(a: *mem.Arena, nodes: []const scim.Node, at: usize) -> json.Value {
    let n = nodes[at]
    var o = obj(a)
    if n.kind == 0u8 || n.kind == 1u8 {
        if n.kind == 0u8 {
            put(&o, "type", sv("and"))
        } else {
            put(&o, "type", sv("or"))
        }
        put(&o, "left", ast_json(a, nodes, n.left))
        put(&o, "right", ast_json(a, nodes, n.right))
    } else if n.kind == 2u8 {
        put(&o, "type", sv("not"))
        put(&o, "operand", ast_json(a, nodes, n.left))
    } else if n.kind == 3u8 {
        put(&o, "type", sv("present"))
        put(&o, "attribute", sv(n.attribute))
    } else if n.kind == 4u8 {
        put(&o, "type", sv("valuePath"))
        put(&o, "attribute", sv(n.attribute))
        put(&o, "filter", ast_json(a, nodes, n.left))
        put(&o, "path", sv(n.path))
    } else {
        put(&o, "type", sv("compare"))
        put(&o, "attribute", sv(n.attribute))
        let names = [9]str{ "eq", "ne", "co", "sw", "ew", "gt", "ge", "lt", "le" }
        put(&o, "op", sv(names[usize(n.op)]))
        put(&o, "value", n.value)
    }
    ret ir.obj_value(&o)
}

fn patched_json(a: *mem.Arena, p: scim.Patched) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(p.valid))
    if p.valid {
        put(&o, "resource", p.resource)
    } else {
        put(&o, "error", sv(p.message))
    }
    ret ir.obj_value(&o)
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "parse") {
        let fl = scim.parse_filter(a, text_of(c, "text"))
        var o = obj(a)
        put(&o, "ok", bv(fl.valid))
        if fl.valid {
            put(&o, "ast", ast_json(a, fl.nodes, fl.root))
        } else {
            put(&o, "error", sv(fl.message))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "filter") {
        let rs = items(ir.value_of(c, "resources"))
        let text = text_of(c, "text")
        var o = obj(a)
        if text.len == 0usize {
            put(&o, "ok", bv(true))
            put(&o, "resources", json.Value{ Array: rs })
            ret ir.obj_value(&o)
        }
        let fl = scim.parse_filter(a, text)
        if !fl.valid {
            put(&o, "ok", bv(false))
            put(&o, "error", sv(fl.message))
            put(&o, "resources", json.Value{ Array: rs[0usize..0usize] })
            ret ir.obj_value(&o)
        }
        let (out, e) = mem.alloc[json.Value](a, rs.len + 1usize)
        if e != ok { os.exit(82i32) }
        var n = 0usize
        var i = 0usize
        while i < rs.len {
            if scim.evaluate(a, fl, rs[i]) {
                out[n] = rs[i]
                n += 1usize
            }
            i += 1usize
        }
        put(&o, "ok", bv(true))
        put(&o, "resources", json.Value{ Array: out[0usize..n] })
        ret ir.obj_value(&o)
    }
    if str.eq(op, "attr") {
        let (v, found) = scim.get_attribute(a, ir.value_of(c, "resource"), text_of(c, "path"))
        if !found { ret .Null }
        ret v
    }
    if str.eq(op, "patchpath") {
        let p = scim.parse_patch_path(a, text_of(c, "path"))
        var o = obj(a)
        put(&o, "attribute", sv(p.attribute))
        put(&o, "hasFilter", bv(p.has_filter))
        if p.has_sub {
            put(&o, "subAttribute", sv(p.sub))
        } else {
            put(&o, "subAttribute", .Null)
        }
        if p.has_error { put(&o, "error", sv(p.message)) }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "patchop") {
        ret patched_json(a, scim.apply_patch_op(a, ir.value_of(c, "resource"), ir.value_of(c, "operation")))
    }
    if str.eq(op, "patch") {
        ret patched_json(a, scim.apply_patch(a, ir.value_of(c, "resource"), ir.value_of(c, "body")))
    }
    if str.eq(op, "version") { ret sv(scim.resource_version(a, ir.value_of(c, "resource"))) }
    if str.eq(op, "user") { ret scim.to_scim_user(a, ir.value_of(c, "user"), opt_base(c)) }
    if str.eq(op, "group") { ret scim.to_scim_group(a, ir.value_of(c, "group"), opt_base(c)) }
    if str.eq(op, "project") {
        let opts = ir.value_of(c, "opts")
        ret scim.project_attributes(a, ir.value_of(c, "resource"), ir.value_of(opts, "attributes"), ir.value_of(opts, "excludedAttributes"))
    }
    if str.eq(op, "list") {
        let opts = ir.value_of(c, "opts")
        let (start, has_start) = ir.get(opts, "startIndex")
        let (count, has_count) = ir.get(opts, "count")
        let (total, has_total) = ir.get(opts, "totalResults")
        ret scim.list_response(a, items(ir.value_of(c, "resources")), start, has_start, count, has_count, total, has_total)
    }
    if str.eq(op, "error") { ret scim.scim_error(a, text_of(c, "status"), text_of(c, "detail"), text_of(c, "scimType")) }
    if str.eq(op, "config") { ret scim.service_provider_config(a, opt_base(c), text_of(c, "doc")) }
    if str.eq(op, "types") { ret scim.resource_types(a, opt_base(c)) }
    // sort
    let order = text_of(c, "order")
    var descending = false
    if str.eq(lower_ascii(a, order), "descending") { descending = true }
    let sorted = scim.sort_resources(a, items(ir.value_of(c, "resources")), text_of(c, "by"), descending)
    ret json.Value{ Array: sorted }
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
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
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
    try io.print("x identity scim ok")
    ret ok
}
