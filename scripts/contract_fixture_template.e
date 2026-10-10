// `x.agent.contract` against scripts/contract_reference.py: random change contracts and malformed ones, each given as
// `{"k": "parse"|"amend", "src": text, "src2": text, "e": outcome}`; `parse` outcomes are `error` or
// `hash verdict required\ncanonical`, `amend` outcomes `true`/`false`/`error`. The reference canonicalizes with
// `json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False)` and hashes with hashlib.
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.contract as contract

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

fn decimal(a: *mem.Arena, n: usize) -> str {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = n
    if rest == 0usize {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        count += 1usize
        rest = rest / 10usize
    }
    var out = ""
    while count > 0usize {
        count -= 1usize
        out = join(a, out, digits[count..count + 1usize])
    }
    ret out
}

fn evaluate(a: *mem.Arena, kind: str, src: str, src2: str) -> str {
    let (c, e) = contract.parse(a, src)
    if str.eq(kind, "amend") {
        if e != ok { ret "error" }
        let (d, e2) = contract.parse(a, src2)
        if e2 != ok { ret "error" }
        if contract.amends(&d, &c) { ret "true" }
        ret "false"
    }
    if e != ok { ret "error" }
    var out = join(a, c.hash, " ")
    out = join(a, out, contract.verdict(&c))
    out = join(a, out, " ")
    out = join(a, out, decimal(a, contract.required_count(&c)))
    out = join(a, out, "\n")
    ret join(a, out, c.canonical)
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
    try io.print("x agent contract ok")
    ret ok
}
