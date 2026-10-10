// `x.agent.environment` against scripts/environment_reference.py: random execution-environment manifests, damaged ones
// and one-field perturbations, each `{"k": "parse"|"same", "src", "src2", "e"}`; `parse` is `error` or
// `identity level omissions\ncanonical`, `same` whether two manifests share an identity.
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.environment as environment

fn members_of(x: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch x {
    case .Object as m:
        ret m
    default:
        ret none
    }
}

fn text_of(members: []const json.Member, key: str) -> str {
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, key) {
            switch members[at].value {
            case .String as s:
                ret s
            default:
                ret ""
            }
        }
        at += 1usize
    }
    ret ""
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn evaluate(a: *mem.Arena, kind: str, src: str, src2: str) -> str {
    let (first, e) = environment.parse(a, src)
    if str.eq(kind, "same") {
        if e != ok { ret "error" }
        let (second, e2) = environment.parse(a, src2)
        if e2 != ok { ret "error" }
        if str.eq(first.identity, second.identity) { ret "true" }
        ret "false"
    }
    if e != ok { ret "error" }
    var omissions = ""
    var at = 0usize
    while at < first.omissions.len {
        if at > 0usize { omissions = join(a, omissions, ",") }
        omissions = join(a, omissions, first.omissions[at])
        at += 1usize
    }
    var out = join(a, first.identity, " ")
    out = join(a, out, first.level)
    out = join(a, out, " ")
    out = join(a, out, omissions)
    out = join(a, out, "\n")
    ret join(a, out, first.canonical)
}

//__VECTOR_FUNCTIONS__
fn run(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                let m = members_of(root)
                want = text_of(m, "e")
                got = evaluate(a, text_of(m, "k"), text_of(m, "src"), text_of(m, "src2"))
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
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
    try io.print("x agent environment ok")
    ret ok
}
