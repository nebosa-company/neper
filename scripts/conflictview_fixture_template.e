// `e.algo.conflictview` against appdor's src/offline/conflict-review.js `renderConflictReview`:
// scripts/conflictview_reference.mjs builds reviews from random conflicts with appdor's own `buildConflictReview` and
// renders them; the fixture renders the same reviews over the Neper module and compares the markup byte for byte.
use e.algo.ir as ir
use e.algo.syncjob as syncjob
use e.algo.conflictview as view
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

// What the reference's `t` answers: the key, a bar and the variable.
fn translate(ctx: *void, key: str, variable: str) -> str {
    let sim = mem.cast[*mem.Arena](ctx)
    ret join(sim, join(sim, key, "|"), variable)
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let tr = syncjob.Translate { ctx: mem.cast[*void](a), run: translate }
    ret view.render_conflict_review(a, ir.value_of(op, "review"), &tr)
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
