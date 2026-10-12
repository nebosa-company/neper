// `e.algo.syncpull` against appdor's src/connectors/connector-type-map.js and the pagination, envelope and base-URL half
// of src/sync/synced-table.js: scripts/syncpull_reference.mjs runs random operations and recorded page loops and writes
// `{"op", "e"}` lines; the fixture replays each over the Neper module and compares the canonical result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.syncjob as syncjob
use e.algo.syncpull as sp
use e.algo.sync as sync
use e.algo.writeback as wb
use e.data.list as list
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

fn obj1(a: *mem.Arena, key: str, v: json.Value) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, key, v)
    ret ir.obj_value(&o)
}

// What appdor's `t` answers outside a browser: the humanized last segment of the key.
fn translate(ctx: *void, key: str, variable: str) -> str {
    if str.eq(key, "connectors.typeMap.noMapForConnector") { ret "No map for connector" }
    if str.eq(key, "connectors.typeMap.noEquivalent") { ret "No equivalent" }
    if str.eq(key, "connectors.typeMap.unrecognisedType") { ret "Unrecognised type" }
    if str.eq(key, "sync.column.syncedFrom") { ret "Synced from" }
    if str.eq(key, "sync.column.downgraded") { ret "Downgraded" }
    ret key
}

type Holder = struct { arena: *mem.Arena, pages: json.Value }

// The recorded server: the page a request URL was answered with, or an unreachable source.
fn fetch_page(ctx: *void, request: json.Value) -> json.Value {
    let holder = mem.cast[*Holder](ctx)
    let (url, have_url) = field(request, "url")
    let (page, found) = field(holder.pages, text_of(url))
    if found { ret page }
    var o = sync.obj(holder.arena)
    sync.put(&o, "ok", json.Value{ Bool: false })
    sync.put(&o, "reason", json.Value{ String: "source-unreachable" })
    ret ir.obj_value(&o)
}

fn text_of(v: json.Value) -> str {
    let (s, is_text) = ir.string_of(v)
    if !is_text { ret "" }
    ret s
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    let tr = syncjob.Translate { ctx: mem.cast[*void](a), run: translate }
    var result: json.Value = .Null
    if str.eq(name, "mapType") {
        let (native, have_native) = field(op, "native")
        result = sp.map_external_type(a, text_field(op, "connector"), native, have_native, &tr)
    } else if str.eq(name, "lc8") {
        result = obj1(a, "native", sp.map_lc8_to_native(a, text_field(op, "connector"), text_field(op, "lc8")))
    } else if str.eq(name, "types") {
        result = sp.list_native_types(a, text_field(op, "connector"))
    } else if str.eq(name, "schema") {
        result = sp.propose_schema(a, text_field(op, "connector"), items(ir.value_of(op, "columns")), &tr)
    } else if str.eq(name, "mapping") {
        let (proposed, declared) = sp.propose_mapping(a, text_field(op, "connector"), ir.value_of(op, "columns"), &tr)
        if !declared { os.exit(88i32) }
        result = proposed
    } else if str.eq(name, "columnConfig") {
        let (label, have_label) = field(op, "label")
        result = sp.synced_column_config(a, ir.value_of(op, "column"), label, have_label)
    } else if str.eq(name, "badge") {
        result = sp.synced_column_badge(a, ir.value_of(op, "config"), &tr)
    } else if str.eq(name, "baseUrl") {
        result = sp.resolve_base_url(a, ir.value_of(op, "channelBaseUrl"), ir.value_of(op, "config"))
    } else if str.eq(name, "pullRequest") {
        result = sp.build_pull_request(a, ir.value_of(op, "connection"), text_field(op, "entity"), ir.value_of(op, "query"))
    } else if str.eq(name, "pagination") {
        result = obj1(a, "pagination", sp.pull_pagination(a, ir.value_of(op, "channel"), text_field(op, "entity")))
    } else if str.eq(name, "cursor") {
        result = obj1(a, "cursor", sp.pull_cursor(a, ir.value_of(op, "body"), ir.value_of(op, "pagination"), ir.value_of(op, "headers")))
    } else if str.eq(name, "advance") {
        result = sp.advance_pull(a, ir.value_of(op, "cursor"), ir.value_of(op, "pagination"), text_field(op, "path"), ir.value_of(op, "query"), text_field(op, "baseUrl"))
    } else if str.eq(name, "unwrap") {
        result = json.Value{ Array: sp.unwrap_records(a, ir.value_of(op, "shape"), ir.value_of(op, "records")) }
    } else if str.eq(name, "shape") {
        result = obj1(a, "shape", sp.pull_record_shape(a, ir.value_of(op, "channel"), ir.value_of(op, "connector"), ir.value_of(op, "stored")))
    } else if str.eq(name, "pages") {
        var holder = Holder { arena: a, pages: ir.value_of(op, "pages") }
        let fetch = sp.FetchPage { ctx: mem.cast[*void](&holder), run: fetch_page }
        let (limit_value, has_limit) = field(op, "limit")
        var limit = 0i64
        if has_limit { limit = sync.count_value(op, "limit", 0i64) }
        result = sp.pull_pages(a, ir.value_of(op, "connection"), text_field(op, "entity"), ir.value_of(op, "pagination"), ir.value_of(op, "shape"), limit, has_limit, &fetch)
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
