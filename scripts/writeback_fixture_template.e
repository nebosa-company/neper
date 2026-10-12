// `e.algo.writeback` against appdor's src/sync/writeback.js, src/connectors/writeback-outbox.js, sync-engine.js and
// connectors/index.js: scripts/writeback_reference.mjs runs random single operations (the clock and the entry id are
// fixed) and writes `{"op", "e"}` lines; the fixture replays each over the Neper module and compares the canonical
// result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.syncjob as syncjob
use e.algo.writeback as wb
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

// What appdor's `t` answers outside a browser: the humanized last segment of the key.
fn translate(ctx: *void, key: str, variable: str) -> str {
    if str.eq(key, "sync.writeback.none") { ret "None" }
    if str.eq(key, "sync.writeback.pending") { ret "Pending" }
    if str.eq(key, "sync.writeback.delivered") { ret "Delivered" }
    if str.eq(key, "sync.writeback.deadLettered") { ret "Dead lettered" }
    ret key
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    let now = text_field(op, "now")
    var result: json.Value = .Null
    if str.eq(name, "create") {
        result = wb.create_entry(a, ir.value_of(op, "opts"), text_field(op, "id"), now)
    } else if str.eq(name, "deliver") {
        result = wb.record_delivery(a, ir.value_of(op, "entry"), ir.value_of(op, "result"), now)
    } else if str.eq(name, "settle") {
        result = wb.settle_delivery(a, ir.value_of(op, "entry"), ir.value_of(op, "result"), now)
    } else if str.eq(name, "reversion") {
        result = wb.plan_reversion(a, ir.value_of(op, "entry"))
    } else if str.eq(name, "mark") {
        result = wb.mark_reverted(a, ir.value_of(op, "entry"), ir.value_of(op, "fields"), now)
    } else if str.eq(name, "summary") {
        result = wb.summarize_outbox(a, items(ir.value_of(op, "entries")))
    } else if str.eq(name, "twoWay") {
        result = wb.two_way_fields(a, ir.value_of(op, "mapping"))
    } else if str.eq(name, "mapping") {
        result = wb.writeback_mapping(a, ir.value_of(op, "mapping"))
    } else if str.eq(name, "row") {
        result = wb.entry_from_row(a, ir.value_of(op, "row"), text_field(op, "id"), now)
    } else if str.eq(name, "patch") {
        result = wb.entry_patch(a, ir.value_of(op, "entry"))
    } else if str.eq(name, "revert") {
        result = wb.revert_patch(a, ir.value_of(op, "entry"), ir.value_of(op, "reversion"), now)
    } else if str.eq(name, "finish") {
        result = wb.finish_reversion(a, ir.value_of(op, "entry"), ir.value_of(op, "patch"), now)
    } else if str.eq(name, "echoSet") {
        result = wb.echo_set(a, items(ir.value_of(op, "delivered")), wb.strings_of(a, ir.value_of(op, "fields")))
    } else if str.eq(name, "suppress") {
        result = wb.suppress_echoes(a, ir.value_of(op, "plan"), items(ir.value_of(op, "echo")), text_field(op, "syncKey"), wb.strings_of(a, ir.value_of(op, "fields")))
    } else if str.eq(name, "line") {
        let tr = syncjob.Translate { ctx: mem.cast[*void](a), run: translate }
        result = wb.outbox_line(a, items(ir.value_of(op, "entries")), &tr)
    } else if str.eq(name, "toLocal") {
        result = wb.map_remote_to_local(a, ir.value_of(op, "record"), items(ir.value_of(op, "mapping")))
    } else if str.eq(name, "toRemote") {
        result = wb.map_local_to_remote(a, ir.value_of(op, "record"), items(ir.value_of(op, "mapping")))
    } else if str.eq(name, "twoWayPlan") {
        result = wb.plan_two_way_sync(a, items(ir.value_of(op, "local")), items(ir.value_of(op, "remote")), items(ir.value_of(op, "base")), text_field(op, "key"), wb.strings_of(a, ir.value_of(op, "fields")), text_field(op, "policy"), items(ir.value_of(op, "echo")))
    } else if str.eq(name, "request") {
        result = wb.build_request(a, ir.value_of(op, "connection"), ir.value_of(op, "req"))
    } else if str.eq(name, "push") {
        result = wb.build_push_request(a, ir.value_of(op, "connection"), text_field(op, "entity"), ir.value_of(op, "entry"), ir.value_of(op, "mapping"))
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
    try io.print("__OK_TEXT__")
    ret ok
}
