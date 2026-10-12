// `e.algo.sqlsource` against appdor's src/sync/sql-source.js: scripts/sqlsource_reference.mjs runs random single
// operations and writes `{"op", "e"}` lines; the fixture replays each over the Neper module and compares the canonical
// result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.sqlsource as sql
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

fn threw(a: *mem.Arena, reason: str) -> json.Value { ret obj1(a, "threw", json.Value{ String: reason }) }

fn bytes_of(a: *mem.Arena, v: json.Value) -> []const u8 {
    let xs = items(v)
    let (out, e) = mem.alloc[u8](a, xs.len + 1usize)
    if e != ok { os.exit(83i32) }
    var at = 0usize
    while at < xs.len {
        switch xs[at] {
        case .Number as number:
            let (value, ne) = json.number_i64(number)
            out[at] = u8(value)
        default:
            out[at] = 0u8
        }
        at += 1usize
    }
    ret out[0usize..xs.len]
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    var result: json.Value = .Null
    if str.eq(name, "dialect") {
        let (d, found) = sql.sql_dialect(a, text_field(op, "url"))
        if found { result = obj1(a, "dialect", json.Value{ String: d }) } else { result = obj1(a, "dialect", .Null) }
    } else if str.eq(name, "channel") {
        result = obj1(a, "sql", json.Value{ Bool: sql.is_sql_channel(a, ir.value_of(op, "channel")) })
    } else if str.eq(name, "hosts") {
        result = sql.parse_sql_source_hosts(a, text_field(op, "raw"))
    } else if str.eq(name, "host") {
        result = sql.check_sql_host(a, text_field(op, "host"), ir.value_of(op, "port"), items(ir.value_of(op, "entries")))
    } else if str.eq(name, "address") {
        result = sql.check_sql_address(a, text_field(op, "address"), items(ir.value_of(op, "entries")))
    } else if str.eq(name, "source") {
        let (base, have_base) = field(op, "baseUrl")
        result = sql.sql_source_from(a, base, have_base, ir.value_of(op, "auth"))
    } else if str.eq(name, "ident") {
        let ident = text_field(op, "name")
        let (quoted, good) = sql.quote_sql_identifier(a, ident)
        var o = sync.obj(a)
        sync.put(&o, "valid", json.Value{ Bool: sql.is_valid_sql_identifier(ident) })
        if good { sync.put(&o, "quoted", json.Value{ String: quoted }) } else { sync.put(&o, "quoted", threw(a, "sql-bad-identifier")) }
        result = ir.obj_value(&o)
    } else if str.eq(name, "entity") {
        result = sql.parse_sql_entity(a, text_field(op, "entity"))
    } else if str.eq(name, "statements") {
        let limit = ir.value_of(op, "limit")
        let schema = text_field(op, "schema")
        let table = text_field(op, "table")
        var o = sync.obj(a)
        sync.put(&o, "browse", sql.browse_tables_statement(a, limit))
        sync.put(&o, "columns", sql.columns_statement(a, json.Value{ String: schema }, json.Value{ String: table }))
        let (picked, picked_ok) = sql.select_rows_statement(a, schema, table, limit)
        if picked_ok { sync.put(&o, "select", picked) } else { sync.put(&o, "select", threw(a, "sql-bad-identifier")) }
        let (default_picked, default_ok) = sql.select_rows_statement(a, schema, table, .Null)
        if default_ok { sync.put(&o, "selectDefault", default_picked) } else { sync.put(&o, "selectDefault", threw(a, "sql-bad-identifier")) }
        result = ir.obj_value(&o)
    } else if str.eq(name, "session") {
        result = sql.read_only_session_statements(a, ir.value_of(op, "timeout"))
    } else if str.eq(name, "redact") {
        result = obj1(a, "text", json.Value{ String: sql.redact_sql_text(a, text_field(op, "text"), items(ir.value_of(op, "secrets"))) })
    } else if str.eq(name, "diag") {
        result = sql.sql_diagnostic(a, ir.value_of(op, "error"), items(ir.value_of(op, "secrets")))
    } else if str.eq(name, "value") {
        result = obj1(a, "value", sql.normalize_sql_value(a, ir.value_of(op, "value")))
    } else if str.eq(name, "row") {
        result = sql.normalize_sql_row(a, ir.value_of(op, "row"))
    } else if str.eq(name, "bytes") {
        result = obj1(a, "value", json.Value{ String: sql.sql_bytes_value(a, bytes_of(a, ir.value_of(op, "data"))) })
    } else if str.eq(name, "entities") {
        result = sql.sql_entities(a, items(ir.value_of(op, "rows")))
    } else if str.eq(name, "many") {
        var rows = sync.empty_list(a)
        let n = sync.count_value(op, "n", 0i64)
        var at = 0i64
        while at < n {
            var r = sync.obj(a)
            sync.put(&r, "table_schema", json.Value{ String: "s" })
            sync.put(&r, "table_name", json.Value{ String: "t" })
            sync.push_value(&rows, ir.obj_value(&r))
            at += 1i64
        }
        let listed = sql.sql_entities(a, list.slice_const[json.Value](&rows))
        result = obj1(a, "count", sync.number(a, i64(items(listed).len)))
    } else if str.eq(name, "columns") {
        result = sql.sql_columns(a, items(ir.value_of(op, "rows")))
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
