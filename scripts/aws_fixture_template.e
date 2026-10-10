// `x.cloud.aws` and `x.ssh.args` against Petcow's own Cloud Control helpers and ssh argument builder: scripts/aws_vectors.mjs
// writes one JSON line per case (`{"op", ..., "e": answer}`) over random catalogue manifests, identifiers, tags, patches and
// host variables; the fixture computes the same answer and compares canonical JSON. A manifest or properties error is
// compared by its prefix (the reference's tail is serde's wording).
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.cloud.aws as aws
use x.ssh.args as ssh

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

fn opt(has: bool, s: str) -> json.Value {
    if has { ret sv(s) }
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

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let (xs, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < xs.len {
        let (s, is_text) = ir.string_of(xs[i])
        out[i] = s
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn is_map(c: json.Value) -> bool { ret str.eq(text_of(c, "shape"), "map") }

fn def_json(a: *mem.Arena, d: aws.Def) -> json.Value {
    var o = obj(a)
    put(&o, "type", sv(d.petcow_type))
    put(&o, "cfn_type", sv(d.cfn_type))
    put(&o, "name_property", opt(d.has_name_property, d.name_property))
    if d.tag_map {
        put(&o, "tag_shape", sv("map"))
    } else {
        put(&o, "tag_shape", sv("kv_list"))
    }
    put(&o, "tag_property", opt(d.has_tag_property, d.tag_property))
    if d.has_identity {
        put(&o, "identity_properties", strings_json(a, d.identity))
    } else {
        put(&o, "identity_properties", .Null)
    }
    if d.has_derived {
        put(&o, "derived_attrs", strings_json(a, d.derived))
    } else {
        put(&o, "derived_attrs", .Null)
    }
    if d.has_parent {
        var p = obj(a)
        put(&p, "type", sv(d.parent.petcow_type))
        put(&p, "property", sv(d.parent.property))
        put(&o, "parent", ir.obj_value(&p))
    } else {
        put(&o, "parent", .Null)
    }
    ret ir.obj_value(&o)
}

fn defs_result(a: *mem.Arena, r: aws.Defs, defs: []const aws.Def) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(r.valid))
    if !r.valid {
        put(&o, "error", sv(r.message))
        ret ir.obj_value(&o)
    }
    let (out, e) = mem.alloc[json.Value](a, defs.len + 1usize)
    if e != ok { os.exit(86i32) }
    var i = 0usize
    while i < defs.len {
        out[i] = def_json(a, defs[i])
        i += 1usize
    }
    put(&o, "v", json.Value{ Array: out[0usize..defs.len] })
    ret ir.obj_value(&o)
}

fn text_result(a: *mem.Arena, valid: bool, message: str, value: str) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(valid))
    if valid {
        put(&o, "v", sv(value))
    } else {
        put(&o, "error", sv(message))
    }
    ret ir.obj_value(&o)
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "throttle") { ret bv(aws.is_throttle(text_of(c, "msg"))) }
    if str.eq(op, "parseDefs") {
        let r = aws.parse_defs(a, text_of(c, "yaml"))
        ret defs_result(a, r, r.defs)
    }
    if str.eq(op, "merge") {
        let d = aws.parse_defs(a, text_of(c, "defaults"))
        if !d.valid { ret defs_result(a, d, d.defs) }
        let e = aws.parse_defs(a, text_of(c, "extra"))
        if !e.valid { ret defs_result(a, e, e.defs) }
        let merged = aws.merge_defs(a, d.defs, e.defs)
        ret defs_result(a, d, merged)
    }
    if str.eq(op, "compose") {
        let r = aws.compose_identifier(a, strings_of(a, ir.value_of(c, "identity")), text_of(c, "nameProperty"), text_of(c, "name"), ir.value_of(c, "attrs"), text_of(c, "type"))
        ret text_result(a, r.valid, r.message, r.value)
    }
    if str.eq(op, "nameFrom") {
        let (n, has) = aws.name_from_identifier(a, strings_of(a, ir.value_of(c, "identity")), text_of(c, "nameProperty"), text_of(c, "identifier"))
        ret opt(has, n)
    }
    if str.eq(op, "desired") { ret text_result(a, true, "", aws.desired_state_json(a, text_of(c, "nameProperty"), text_of(c, "name"), ir.value_of(c, "attrs"))) }
    if str.eq(op, "tagged") { ret text_result(a, true, "", aws.desired_state_tagged(a, text_of(c, "name"), ir.value_of(c, "attrs"), is_map(c), text_of(c, "tagProp"))) }
    if str.eq(op, "managedName") {
        let (n, has) = aws.managed_name_from_attrs(ir.value_of(c, "attrs"), is_map(c), text_of(c, "tagProp"))
        ret opt(has, n)
    }
    if str.eq(op, "patch") { ret text_result(a, true, "", aws.patch_document(a, text_of(c, "nameProperty"), has_text(c, "nameProperty"), ir.value_of(c, "attrs"))) }
    if str.eq(op, "patchSkipping") { ret text_result(a, true, "", aws.patch_document_skipping(a, strings_of(a, ir.value_of(c, "identity")), ir.value_of(c, "attrs"))) }
    if str.eq(op, "patchTagged") { ret text_result(a, true, "", aws.patch_document_tagged(a, text_of(c, "name"), ir.value_of(c, "attrs"), is_map(c), text_of(c, "tagProp"))) }
    if str.eq(op, "strip") { ret aws.strip_petcow_tags(a, ir.value_of(c, "attrs"), is_map(c), text_of(c, "tagProp")) }
    if str.eq(op, "hasKey") { ret bv(aws.properties_have_key(a, text_of(c, "props"), has_text(c, "props"), text_of(c, "key"))) }
    if str.eq(op, "parseProps") {
        let (v, message, good) = aws.parse_properties(a, text_of(c, "props"), has_text(c, "props"))
        var o = obj(a)
        put(&o, "ok", bv(good))
        if good {
            put(&o, "v", v)
        } else {
            put(&o, "error", sv(message))
        }
        ret ir.obj_value(&o)
    }
    // ssh
    let host = ir.value_of(c, "host")
    let args = ssh.ssh_args(a, text_of(host, "address"), ir.value_of(host, "vars"), text_of(c, "command"), str.eq(text_of(c, "shell"), "powershell"))
    ret strings_json(a, args)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let want = ir.value_of(c, "e")
    let got_value = answer(a, c)
    // errors whose tail is the reference's serde wording are compared by their prefix
    let (want_error, has_error) = ir.get(want, "error")
    if has_error {
        let (we, is_text) = ir.string_of(want_error)
        let (ge, has_got) = ir.get(got_value, "error")
        var got_error = ""
        if has_got {
            let (g, gt) = ir.string_of(ge)
            got_error = g
        }
        if str.starts_with(we, "invalid document: aws.cc manifest:") {
            if str.starts_with(got_error, "invalid document: aws.cc manifest:") { ret true }
        } else if str.starts_with(we, "invalid document: ccapi properties parse:") {
            if str.starts_with(got_error, "invalid document: ccapi properties parse:") { ret true }
        }
    }
    let (got, ge) = chain.canonical_json(a, got_value)
    let (expect, we) = chain.canonical_json(a, want)
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
    try io.print("x cloud aws ok")
    ret ok
}
