// `x.ops.inventory` against Petcow's own facts.rs, inventory.rs and naming.rs::sanitize: scripts/inventory_vectors.mjs writes
// one JSON line per case (`{"op", ..., "e": answer}`) over random fact output, inventory documents and observed resources;
// the fixture computes the same answer and compares canonical JSON (a document error by its `ok: false`).
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.ops.inventory as inv

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

fn host_json(a: *mem.Arena, h: inv.Host, with_name: bool) -> json.Value {
    var o = obj(a)
    if with_name { put(&o, "name", sv(h.name)) }
    put(&o, "address", sv(h.address))
    put(&o, "groups", strings_json(a, h.groups))
    put(&o, "vars", h.vars)
    ret ir.obj_value(&o)
}

fn hosts_result(a: *mem.Arena, hosts: []const inv.Host) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, hosts.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < hosts.len {
        out[i] = host_json(a, hosts[i], true)
        i += 1usize
    }
    var o = obj(a)
    put(&o, "ok", json.Value{ Bool: true })
    put(&o, "v", json.Value{ Array: out[0usize..hosts.len] })
    ret ir.obj_value(&o)
}

fn failure() -> json.Value {
    ret .Null
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let op = text_of(c, "op")
    let want = ir.value_of(c, "e")
    var got: json.Value = .Null
    if str.eq(op, "parseFacts") {
        got = inv.parse_facts(a, text_of(c, "stdout"))
    } else if str.eq(op, "customScript") {
        let (members, is_object) = ir.members_of(ir.value_of(c, "facts"))
        let (names, e1) = mem.alloc[str](a, members.len + 1usize)
        let (commands, e2) = mem.alloc[str](a, members.len + 1usize)
        var i = 0usize
        while i < members.len {
            names[i] = members[i].key
            let (s, is_text) = ir.string_of(members[i].value)
            commands[i] = s
            i += 1usize
        }
        got = sv(inv.custom_fact_script(a, names[0usize..members.len], commands[0usize..members.len]))
    } else if str.eq(op, "sanitize") {
        got = sv(inv.sanitize(a, text_of(c, "token")))
    } else if str.eq(op, "resolve") || str.eq(op, "select") {
        let d = inv.parse_inventory(a, text_of(c, "yaml"))
        var o = obj(a)
        if !d.valid {
            put(&o, "ok", json.Value{ Bool: false })
            // the reference's tail is serde's wording; only the verdict is compared
            let (w, has_w) = ir.get(want, "error")
            put(&o, "error", w)
            let want_ok = ir.truthy(ir.value_of(want, "ok"))
            if !want_ok { ret true }
            let shown = io.print(f.join(a, "\nGOT error: ", d.message))
            ret false
        }
        if !ir.truthy(ir.value_of(want, "ok")) {
            let shown = io.print("\nGOT ok, WANT an error")
            ret false
        }
        if str.eq(op, "resolve") {
            got = hosts_result(a, inv.resolve(a, d))
        } else {
            got = hosts_result(a, inv.select(a, d, text_of(c, "group"), has_text(c, "group"), text_of(c, "varKey"), text_of(c, "varValue"), has_text(c, "varKey")))
        }
    } else {
        // synthesize
        let s = ir.value_of(c, "source")
        var address_from = "private_ip"
        if has_text(s, "address_from") { address_from = text_of(s, "address_from") }
        let source = inv.Source { type_name: text_of(s, "type"), address_from: address_from, has_group: has_text(s, "group"), group: text_of(s, "group"), has_group_from_tag: has_text(s, "group_from_tag"), group_from_tag: text_of(s, "group_from_tag") }
        let raw = ir.value_of(c, "observed")
        let (list, is_array) = ir.items_of(raw)
        let (observed, e) = mem.alloc[inv.Observed](a, list.len + 1usize)
        var i = 0usize
        while i < list.len {
            observed[i] = inv.Observed { name: text_of(list[i], "name"), attributes: ir.value_of(list[i], "attributes"), has_real_id: has_text(list[i], "realId"), real_id: text_of(list[i], "realId") }
            i += 1usize
        }
        let (names, hosts) = inv.synthesize_hosts(a, source, observed[0usize..list.len])
        var o = obj(a)
        var k = 0usize
        while k < names.len {
            put(&o, names[k], host_json(a, hosts[k], false))
            k += 1usize
        }
        got = ir.obj_value(&o)
    }
    let (g, ge) = chain.canonical_json(a, got)
    let (w, we) = chain.canonical_json(a, want)
    if ge != ok || we != ok { ret false }
    if !str.eq(g, w) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", g), f.join(a, "\nWANT ", w)))
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
    try io.print("x ops inventory ok")
    ret ok
}
