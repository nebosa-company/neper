// `x.cloud.k8s`, `x.cloud.awssdk` and `x.ssh.transport` against Petcow's own helpers (the k8s provider, the S3, IAM, EC2 and
// Lightsail providers and the per-host transport): scripts/drivers_vectors.mjs writes one JSON line per case (`{"op", ...,
// "e": answer}`) over random manifests, live objects, attribute bags, tag sets, ingress rules and host variables; the fixture
// computes the same answer and compares canonical JSON. A manifest parse error is compared by its prefix (the reference's
// tail is serde's wording).
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.cloud.awssdk as aws
use x.cloud.k8s as k8s
use x.ssh.transport as transport

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

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { os.exit(82i32) }
    ret json.Value{ Number: v }
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

fn result(a: *mem.Arena, good: bool, value: json.Value, message: str) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(good))
    if good { put(&o, "v", value) } else { put(&o, "error", sv(message)) }
    ret ir.obj_value(&o)
}

fn def_json(a: *mem.Arena, d: k8s.Def) -> json.Value {
    var o = obj(a)
    put(&o, "type", sv(d.petcow_type))
    put(&o, "api_version", sv(d.api_version))
    put(&o, "kind", sv(d.kind))
    put(&o, "namespaced", bv(d.namespaced))
    ret ir.obj_value(&o)
}

fn defs_json(a: *mem.Arena, defs: []const k8s.Def) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, defs.len + 1usize)
    if e != ok { os.exit(86i32) }
    var i = 0usize
    while i < defs.len {
        out[i] = def_json(a, defs[i])
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..defs.len] }
}

fn def_from(v: json.Value) -> k8s.Def {
    var namespaced = true
    let (n, found) = ir.get(v, "namespaced")
    if found {
        switch n {
        case .Bool as b:
            namespaced = b
        default:
            namespaced = true
        }
    }
    ret k8s.Def { petcow_type: text_of(v, "type"), api_version: text_of(v, "api_version"), kind: text_of(v, "kind"), namespaced: namespaced }
}

// --- the per-host transport stand-in --------------------------------------------------------------------------------

type Sim = struct { a: *mem.Arena, known: []const str, builds: i64 }

fn sim_build(ctx: *void, kind: str) -> (bool, str) {
    var sim = mem.cast[*Sim](ctx)
    sim.builds += 1i64
    var at = 0usize
    while at < sim.known.len {
        if str.eq(sim.known[at], kind) { ret (true, "") }
        at += 1usize
    }
    ret (false, f.join(sim.a, f.join(sim.a, "invalid document: unknown transport '", kind), "'"))
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

fn run_transport(a: *mem.Arena, c: json.Value) -> json.Value {
    var sim = Sim { a: a, known: strings_of(a, ir.value_of(c, "known")), builds: 0i64 }
    let factory = transport.Factory { ctx: mem.cast[*void](&sim), build: sim_build }
    var table = transport.new_table(a, text_of(c, "default"), factory)
    let (hosts, is_array) = ir.items_of(ir.value_of(c, "hosts"))
    let (runs, e) = mem.alloc[json.Value](a, hosts.len + 1usize)
    if e != ok { os.exit(87i32) }
    var i = 0usize
    while i < hosts.len {
        var vars = obj(a)
        let (t, has_t) = ir.get(hosts[i], "transport")
        if has_t { put(&vars, "transport", t) }
        let name = text_of(hosts[i], "name")
        let r = transport.resolve(&table, name, ir.obj_value(&vars))
        var o = obj(a)
        put(&o, "kind", sv(r.kind))
        put(&o, "ok", bv(r.good))
        if r.good {
            put(&o, "stdout", sv(r.kind))
            put(&o, "host", sv(name))
        } else {
            put(&o, "error", sv(r.failure))
        }
        put(&o, "builds", number(a, sim.builds))
        runs[i] = ir.obj_value(&o)
        i += 1usize
    }
    var out = obj(a)
    put(&out, "name", sv(transport.name(&table)))
    put(&out, "runs", json.Value{ Array: runs[0usize..hosts.len] })
    ret ir.obj_value(&out)
}

fn observed_with(a: *mem.Arena, attrs: json.Value) -> json.Value { ret attrs }

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    let attrs = ir.value_of(c, "attrs")
    if str.eq(op, "k8sDefs") { ret defs_json(a, k8s.default_defs(a)) }
    if str.eq(op, "parseDefs") {
        let r = k8s.parse_defs(a, text_of(c, "text"))
        ret result(a, r.valid, defs_json(a, r.defs), r.message)
    }
    if str.eq(op, "allDefs") {
        let r = k8s.parse_defs(a, text_of(c, "text"))
        if !r.valid { ret result(a, false, .Null, r.message) }
        ret result(a, true, defs_json(a, k8s.merge_defs(a, k8s.default_defs(a), r.defs)), "")
    }
    if str.eq(op, "selector") {
        let d = def_from(ir.value_of(c, "def"))
        var o = obj(a)
        put(&o, "selector", sv(k8s.selector(a, d)))
        put(&o, "args", strings_json(a, k8s.ns_args(a, d, text_of(c, "ns"), has_text(c, "ns"))))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "applyManifest") { ret result(a, true, sv(k8s.apply_manifest(a, def_from(ir.value_of(c, "def")), text_of(c, "name"), attrs)), "") }
    if str.eq(op, "observed") { ret k8s.observed(a, text_of(c, "type"), ir.value_of(c, "obj")) }
    if str.eq(op, "managedItem") { ret bv(k8s.is_managed_item(ir.value_of(c, "item"))) }
    if str.eq(op, "notFound") { ret bv(k8s.is_not_found(a, text_of(c, "stderr"))) }
    if str.eq(op, "bucketName") {
        let (good, message) = aws.validate_bucket_name(a, text_of(c, "name"))
        ret result(a, good, .Null, message)
    }
    if str.eq(op, "attrBool") { ret bv(aws.attr_bool(attrs, text_of(c, "key"))) }
    if str.eq(op, "attrStr") {
        let (s, found) = aws.attr_str(attrs, text_of(c, "key"))
        ret opt(found, s)
    }
    if str.eq(op, "optAttr") {
        let (s, found) = aws.attr_str(attrs, text_of(c, "key"))
        ret opt(found, s)
    }
    if str.eq(op, "userTags") { ret aws.user_tags(a, attrs) }
    if str.eq(op, "percentDecode") { ret sv(aws.percent_decode(a, text_of(c, "s"))) }
    if str.eq(op, "assumeRole") {
        let (s, good, message) = aws.assume_role_json(a, attrs, text_of(c, "name"))
        ret result(a, good, sv(s), message)
    }
    if str.eq(op, "iamTags") { ret result(a, true, aws.managed_iam_tags(a, text_of(c, "name"), ir.value_of(c, "user")), "") }
    if str.eq(op, "desiredArns") { ret strings_json(a, aws.desired_arns(a, attrs)) }
    if str.eq(op, "managedTags") { ret aws.managed_tags(a, text_of(c, "name"), ir.value_of(c, "user")) }
    if str.eq(op, "observedUserTags") { ret aws.observed_user_tags(a, ir.value_of(c, "tags")) }
    if str.eq(op, "petcowName") {
        let (s, found) = aws.petcow_name(ir.value_of(c, "tags"))
        ret opt(found, s)
    }
    if str.eq(op, "nameOrId") { ret sv(aws.name_or_id(ir.value_of(c, "tags"), text_of(c, "realId"))) }
    if str.eq(op, "unmanaged") { ret aws.unmanaged(a, text_of(c, "type"), ir.value_of(c, "tags"), text_of(c, "realId")) }
    if str.eq(op, "attrI64") {
        let (n, found) = aws.attr_i64(attrs, text_of(c, "key"))
        if found { ret number(a, n) }
        ret .Null
    }
    if str.eq(op, "attrStrList") { ret strings_json(a, aws.string_list(a, attrs, text_of(c, "key"))) }
    if str.eq(op, "ingress") {
        let (rules, good, message) = aws.ingress_permissions(a, text_of(c, "name"), attrs)
        ret result(a, good, rules, message)
    }
    if str.eq(op, "reqAttr") {
        let (s, good, message) = aws.req_attr(a, attrs, text_of(c, "key"), text_of(c, "kind"))
        ret result(a, good, sv(s), message)
    }
    if str.eq(op, "lsTags") { ret aws.lightsail_managed_tags(a, text_of(c, "name")) }
    if str.eq(op, "transport") { ret run_transport(a, c) }
    os.exit(88i32)
    ret .Null
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let want = ir.value_of(c, "e")
    let got_value = answer(a, c)
    // a manifest error whose tail is the reference's serde wording is compared by its prefix
    let (want_error, has_error) = ir.get(want, "error")
    if has_error {
        let (we, is_text) = ir.string_of(want_error)
        let (ge, has_got) = ir.get(got_value, "error")
        var got_error = ""
        if has_got {
            let (g, gt) = ir.string_of(ge)
            got_error = g
        }
        if str.starts_with(we, "invalid document: k8s manifest:") {
            if str.starts_with(got_error, "invalid document: k8s manifest:") { ret true }
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
    try io.print("x cloud drivers ok")
    ret ok
}
