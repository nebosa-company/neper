// `x.agent.bundle` against scripts/bundle_reference.py: random change bundles and integrations of several of them, each
// `{"k": "parse"|"integrate", "a": bundle text or bundles joined by byte 1, "b": current base, "e": outcome}`; `parse`
// gives `error` or the bundle hash, `integrate` gives `error` or `verdict combined` then one cause per line.
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.bundle as bundle

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

fn evaluate(a: *mem.Arena, kind: str, text: str, base: str) -> str {
    if str.eq(kind, "parse") {
        let (b, e) = bundle.parse(a, text)
        if e != ok { ret "error" }
        ret b.hash
    }
    let (bundles, bundles_error) = mem.alloc[bundle.Bundle](a, text.len + 1usize)
    if bundles_error != ok { os.exit(81i32) }
    var count = 0usize
    var begin = 0usize
    var at = 0usize
    while at <= text.len {
        if at == text.len || text[at] == 1u8 {
            let (b, e) = bundle.parse(a, text[begin..at])
            if e != ok { ret "error" }
            bundles[count] = b
            count += 1usize
            begin = at + 1usize
        }
        at += 1usize
    }
    let (result, ie) = bundle.integrate(a, bundles[0usize..count], base)
    if ie != ok { ret "error" }
    var out = join(a, join(a, result.verdict, " "), result.combined)
    var c = 0usize
    while c < result.causes.len {
        out = join(a, join(a, out, "\n"), result.causes[c])
        c += 1usize
    }
    ret out
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
                got = evaluate(a, text_of(m, "k"), text_of(m, "a"), text_of(m, "b"))
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
    try io.print("x agent bundle ok")
    ret ok
}
