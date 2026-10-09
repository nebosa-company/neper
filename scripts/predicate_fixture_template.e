// `e.algo.predicate` (L025: the Spartan filter engine's value-rule subset) against scripts/predicate_reference.py,
// a transcription of petcow's `filter.rs` and `predicate.rs` onto Python dictionaries: petcow's own tests, the named
// refusals of a malformed filter, and 900 seeded random filters (combinators, every operator, nested `any`/`all`/
// `count`, the three built-ins) over seeded random attribute bags. A line is `C <json case>` with `filter`, `attrs`
// and either `expect` (true or false) or `error` (the name of the refusal `parse` must give).
use e.algo.predicate
use e.fmt.json as json
use e.io
use e.mem
use e.os

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var none: json.Value = zero
    var i = 0usize
    while i < members.len {
        if same_text(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    ret (none, false)
}

fn error_name(e: err) -> str {
    if e == predicate.NotMapping { ret "NotMapping" }
    if e == predicate.BoolNotAlone { ret "BoolNotAlone" }
    if e == predicate.NotList { ret "NotList" }
    if e == predicate.MissingKey { ret "MissingKey" }
    if e == predicate.BadOp { ret "BadOp" }
    if e == predicate.MissingOp { ret "MissingOp" }
    if e == predicate.MissingValue { ret "MissingValue" }
    if e == predicate.MissingElement { ret "MissingElement" }
    if e == predicate.CountNeedsNumber { ret "CountNeedsNumber" }
    if e == predicate.BadCountOp { ret "BadCountOp" }
    ret "Other"
}

fn check(a: *mem.Arena, line: str) -> bool {
    let (root, parse_error) = json.parse(a, line[2usize..line.len], json.Options { allow_duplicate_keys: false, max_depth: 32u16 })
    if parse_error != ok { ret false }
    var fields: []const json.Member = zero
    switch root {
    case .Object as members:
        fields = members
    default:
        ret false
    }
    let (filter_value, has_filter) = member(fields, "filter")
    let (attrs_value, has_attrs) = member(fields, "attrs")
    if !has_filter || !has_attrs { ret false }
    var attrs: []const json.Member = zero
    switch attrs_value {
    case .Object as members:
        attrs = members
    default:
        ret false
    }
    let (filter, filter_error) = predicate.parse(a, filter_value)
    let (error_value, expects_error) = member(fields, "error")
    if expects_error {
        var want = ""
        switch error_value {
        case .String as s:
            want = s
        default:
            want = ""
        }
        ret filter_error != ok && same_text(error_name(filter_error), want)
    }
    if filter_error != ok { ret false }
    let (expect_value, has_expect) = member(fields, "expect")
    if !has_expect { ret false }
    var want = false
    switch expect_value {
    case .Bool as b:
        want = b
    default:
        ret false
    }
    ret predicate.eval(a, &filter, attrs) == want
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let mark = mem.mark(a)
            let good = check(a, text[start..i])
            if !good {
                let shown = io.print(text[start..i])
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo predicate ok")
    ret ok
}
