// `e.algo.syncinfer`'s `coerce_value` and `coerce_record` against appdor's `coerceValue` and `coerceRecord`
// (src/io/infer.js): scripts/syncinfer_coerce_reference.mjs runs generated cells through appdor's own functions under
// four local zones and writes `{"op", "tz", ...}` lines with the canonical answer `e`; the fixture replays each over the
// Neper module (the zone as its offset east of UTC in minutes) and compares the canonical result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncinfer as si
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

fn offset_minutes(tz: str) -> i64 {
    if str.eq(tz, "Asia/Kolkata") { ret 330i64 }
    if str.eq(tz, "America/Phoenix") { ret 0i64 - 420i64 }
    if str.eq(tz, "Etc/GMT+7") { ret 0i64 - 420i64 }
    ret 0i64
}

fn threw(a: *mem.Arena) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "threw", sync.flag(true))
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    let tz = offset_minutes(text_field(op, "tz"))
    var result: json.Value = .Null
    if str.eq(name, "value") {
        result = si.coerce_value(a, ir.value_of(op, "raw"), text_field(op, "type"), ir.value_of(op, "opts"), tz)
    } else if str.eq(name, "record") {
        let (record, fine) = si.coerce_record(a, ir.value_of(op, "record"), ir.value_of(op, "fields"), tz)
        if fine { result = record } else { result = threw(a) }
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
