// `e.algo.syncinfer` against appdor's src/io/infer.js, `inferExternalSchema` and the inferred half of `proposeMapping`:
// scripts/syncinfer_reference.mjs runs random columns and samples through appdor's own functions and writes
// `{"op", "e"}` lines; the fixture replays each over the Neper module and compares the canonical result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.syncinfer as si
use e.algo.syncpull as sp
use e.algo.syncjob as syncjob
use e.algo.sync as sync
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

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

// What appdor's `t` answers outside a browser: the humanized last segment of the key.
fn translate(ctx: *void, key: str, variable: str) -> str {
    if str.eq(key, "sync.mapping.structuredValue") { ret "Structured value" }
    ret key
}

fn threw(a: *mem.Arena) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "threw", sync.flag(true))
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    let tr = syncjob.Translate { ctx: mem.cast[*void](a), run: translate }
    var result: json.Value = .Null
    if str.eq(name, "column") {
        result = si.infer_column_type(a, ir.value_of(op, "values"), ir.value_of(op, "opts"))
    } else if str.eq(name, "order") {
        result = si.date_order_of(a, ir.value_of(op, "values"))
    } else if str.eq(name, "decimal") {
        result = si.decimal_separator_of(a, ir.value_of(op, "values"))
    } else if str.eq(name, "schema") {
        let (schema, fine) = si.infer_external_schema(a, ir.value_of(op, "rows"))
        if fine { result = schema } else { result = threw(a) }
    } else if str.eq(name, "mapping") {
        let (mapping, fine) = sp.propose_mapping_for(a, "x", .Null, ir.value_of(op, "sample"), &tr)
        if fine { result = mapping } else { result = threw(a) }
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
