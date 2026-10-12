// `e.algo.syncsource` against appdor's src/sync/change-stream.js and entity-browse.js: scripts/syncsource_reference.mjs
// runs 700 random single operations and writes `{"op", "e"}` lines; the fixture replays each over the Neper module and
// compares the canonical result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.syncsource as source
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn field(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = ir.get(v, key)
    ret (x, found)
}

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = field(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    var result: json.Value = .Null
    if str.eq(name, "token") {
        result = json.Value{ Bool: source.looks_like_stream_token(text_field(op, "token")) }
    } else if str.eq(name, "url") {
        result = json.Value{ String: source.stream_url(a, text_field(op, "base"), text_field(op, "token")) }
    } else if str.eq(name, "delivery") {
        result = source.change_from_delivery(a, ir.value_of(op, "payload"))
    } else if str.eq(name, "plan") {
        let (existing, have_existing) = field(op, "existing")
        result = source.plan_stream_change(a, ir.value_of(op, "binding"), text_field(op, "planOp"), ir.value_of(op, "record"), existing, have_existing)
    } else if str.eq(name, "counts") {
        result = source.stream_plan_counts(a, ir.value_of(op, "plan"))
    } else if str.eq(name, "static") {
        let channel = ir.value_of(op, "channel")
        let (made, e) = ir.new_obj(a)
        if e != ok { os.exit(86i32) }
        var o = made
        let p1 = ir.put(&o, "entities", json.Value{ Array: source.static_entities(a, channel) })
        let p2 = ir.put(&o, "browse", json.Value{ Bool: source.can_browse(channel) })
        result = ir.obj_value(&o)
    } else if str.eq(name, "entities") {
        result = json.Value{ Array: source.entities_from_body(a, ir.value_of(op, "channel"), ir.value_of(op, "body")) }
    } else if str.eq(name, "merge") {
        result = json.Value{ Array: source.merge_entities(a, items(ir.value_of(op, "source")), items(ir.value_of(op, "catalog"))) }
    } else {
        os.exit(89i32)
    }
    let (rendered, e) = chain.canonical_json(a, result)
    if e != ok { os.exit(81i32) }
    ret rendered
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
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                want = text_field(root, "e")
                got = run_one(a, root)
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
                let shown_want = io.print(join(a, "\nwant ", want))
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
    try io.print("algo syncsource ok")
    ret ok
}
