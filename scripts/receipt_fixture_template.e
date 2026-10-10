// `x.agent.receipt` against scripts/receipt_reference.py: random contracts and receipts bound to them (and not), each
// `{"k": "parse"|"verify", "a", "b", "c", "d", "e"}`; `parse` (receipt text a) gives `error` or the receipt hash,
// `verify` (contract a, receipt b, environment level c, `required level\naudit verdict` d) gives `error` or
// `verdict fresh`.
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.contract as contract
use x.agent.receipt as receipt

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

fn digit(a: *mem.Arena, n: usize) -> str {
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

fn evaluate(a: *mem.Arena, kind: str, x: str, y: str, level: str, extra: str) -> str {
    if str.eq(kind, "parse") {
        let (r, e) = receipt.parse(a, x)
        if e != ok { ret "error" }
        ret r.hash
    }
    let (c, ce) = contract.parse(a, x)
    if ce != ok { ret "error" }
    let (r, re) = receipt.parse(a, y)
    if re != ok { ret "error" }
    let (required, audit, found) = str.split_once(extra, "\n")
    if !found { ret "error" }
    let verdict = receipt.verify(&c, &r, level, required, audit)
    ret join(a, join(a, verdict, " "), digit(a, receipt.fresh(&c, &r)))
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
                got = evaluate(a, text_of(m, "k"), text_of(m, "a"), text_of(m, "b"), text_of(m, "c"), text_of(m, "d"))
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
    try io.print("x agent receipt ok")
    ret ok
}
