// `e.algo.chain` against appdor's tamper-evident history (src/history/tamper-evident.js, diffRecords from
// src/history/index.js): scripts/chain_reference.mjs runs random operation scripts -- chain appends and record changes,
// verification before and after tampering, retention, exports and the stateless predicates -- and writes `{"ops", "e"}`
// lines; the fixture replays the operations over the Neper module and compares the canonical results one per line.
use e.algo.chain as chain
use e.algo.ir as ir
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

fn canon(a: *mem.Arena, v: json.Value) -> str {
    let (text, e) = chain.canonical_json(a, v)
    if e != ok { os.exit(81i32) }
    ret text
}

fn count_of(v: json.Value, key: str) -> i64 {
    let (x, found) = field(v, key)
    if !found { ret 0i64 }
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        if e == ok { ret value }
        ret 0i64
    default:
        ret 0i64
    }
}

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let xs = items(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(82i32) }
    var at = 0usize
    while at < xs.len {
        let (s, is_text) = ir.string_of(xs[at])
        out[at] = s
        at += 1usize
    }
    ret out[0usize..xs.len]
}

fn put_obj(a: *mem.Arena, source: json.Value, key: str, value: json.Value) -> json.Value {
    let (made, e) = ir.new_obj(a)
    if e != ok { os.exit(83i32) }
    var o = made
    let assigned = ir.assign(&o, source)
    let stored = ir.put(&o, key, value)
    ret ir.obj_value(&o)
}

fn run_case(a: *mem.Arena, spec: json.Value) -> str {
    let (made, made_error) = list.init[json.Value](a, 8usize)
    if made_error != ok { os.exit(90i32) }
    var stream = made
    var out = ""
    let ops = items(ir.value_of(spec, "ops"))
    var at = 0usize
    while at < ops.len {
        let op = ops[at]
        let name = text_field(op, "op")
        var result: json.Value = .Null
        if str.eq(name, "recordChange") {
            let (stored, e) = chain.record_change(a, &stream, ir.value_of(op, "change"))
            if e != ok { os.exit(91i32) }
            result = stored
        } else if str.eq(name, "append") {
            let (stored, e) = chain.chain_append(a, &stream, ir.value_of(op, "entry"))
            if e != ok { os.exit(92i32) }
            result = stored
        } else if str.eq(name, "verify") {
            let (verdict, e) = chain.verify_chain(a, list.slice_const[json.Value](&stream))
            if e != ok { os.exit(93i32) }
            result = verdict
        } else if str.eq(name, "tamper") {
            let index = usize(count_of(op, "index"))
            if index < stream.len {
                stream.items[index] = put_obj(a, stream.items[index], text_field(op, "field"), ir.value_of(op, "value"))
            }
        } else if str.eq(name, "drop") {
            let index = usize(count_of(op, "index"))
            var k = index
            while k + 1usize < stream.len {
                stream.items[k] = stream.items[k + 1usize]
                k += 1usize
            }
            if index < stream.len { stream.len -= 1usize }
        } else if str.eq(name, "retention") {
            let (windows, have_windows) = field(op, "windows")
            let (res, e) = chain.apply_history_retention(a, list.slice_const[json.Value](&stream), text_field(op, "plan"), count_of(op, "nowMs"), windows, have_windows)
            if e != ok { os.exit(94i32) }
            result = res
            let (adopt, have_adopt) = field(op, "adopt")
            var adopted = false
            switch adopt {
            case .Bool as b:
                adopted = b
            default:
                adopted = false
            }
            if adopted {
                let (fresh, fresh_error) = list.init[json.Value](a, 8usize)
                if fresh_error != ok { os.exit(95i32) }
                stream = fresh
                let kept = items(ir.value_of(res, "chain"))
                var k = 0usize
                while k < kept.len {
                    let pushed = list.push[json.Value](&stream, kept[k])
                    k += 1usize
                }
            }
        } else if str.eq(name, "export") {
            let (rid, have_rid) = field(op, "recordId")
            let (res, e) = chain.export_history(a, list.slice_const[json.Value](&stream), rid, have_rid)
            if e != ok { os.exit(96i32) }
            result = res
        } else if str.eq(name, "diff") {
            var ignore = chain.default_ignore(a)
            let (given, have_given) = field(op, "ignore")
            if have_given { ignore = strings_of(a, given) }
            let (changes, e) = chain.diff_records(a, ir.value_of(op, "before"), ir.value_of(op, "after"), ignore)
            if e != ok { os.exit(97i32) }
            result = json.Value{ Array: changes }
        } else if str.eq(name, "was") {
            var options = ir.value_of(op, "options")
            if !ir.truthy(options) { options = ir.empty_object() }
            let revisions = items(ir.value_of(op, "revisions"))
            result = json.Value{ Bool: chain.was(a, revisions, ir.value_of(op, "recordId"), text_field(op, "field"), ir.value_of(op, "value"), options) }
        } else if str.eq(name, "changed") {
            let revisions = items(ir.value_of(op, "revisions"))
            result = json.Value{ Bool: chain.changed(a, revisions, ir.value_of(op, "recordId"), text_field(op, "field"), ir.value_of(op, "options")) }
        } else if str.eq(name, "filter") {
            let (kept, e) = chain.filter_by_history(a, items(ir.value_of(op, "records")), items(ir.value_of(op, "revisions")), ir.value_of(op, "predicate"))
            if e != ok { os.exit(98i32) }
            result = json.Value{ Array: kept }
        } else if str.eq(name, "fieldHistory") {
            let (narrowed, e) = chain.field_history(a, items(ir.value_of(op, "revisions")), ir.value_of(op, "recordId"), strings_of(a, ir.value_of(op, "fields")))
            if e != ok { os.exit(99i32) }
            result = json.Value{ Array: narrowed }
        } else {
            os.exit(89i32)
        }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, canon(a, result))
        at += 1usize
    }
    ret out
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
                got = run_case(a, root)
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
    try io.print("algo chain ok")
    ret ok
}
