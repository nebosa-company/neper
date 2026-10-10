// `x.agent.policy` against scripts/policy_reference.py: random policies, effects, paths, plans and approval tokens, each
// `{"k", "p": policy text, "a", "b", "c", "d": operands, "e": outcome}`. Operations: `parse` (policy hash or `error`),
// `decide` (effect a, scope b), `classify` (path a), `audit` (declared a, observed b, approved c as lines, enforceable d),
// `approval` (token a, key b, effect+newline+scope c, now+newline+seen lines d) and `redact` (text a, secret lines b).
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.policy as policy

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

// A newline-joined list as strings; an empty text is no lines.
fn lines_of(a: *mem.Arena, text: str) -> []const str {
    let (out, e) = mem.alloc[str](a, text.len + 2usize)
    if e != ok { os.exit(81i32) }
    var count = 0usize
    if text.len > 0usize {
        var begin = 0usize
        var at = 0usize
        while at <= text.len {
            if at == text.len || text[at] == 10u8 {
                out[count] = text[begin..at]
                count += 1usize
                begin = at + 1usize
            }
            at += 1usize
        }
    }
    ret out[0usize..count]
}

fn parse_decimal(text: str) -> usize {
    var value = 0usize
    var at = 0usize
    while at < text.len {
        value = value * 10usize + usize(text[at] - 48u8)
        at += 1usize
    }
    ret value
}

fn evaluate(a: *mem.Arena, kind: str, p_text: str, x: str, y: str, z: str, w: str) -> str {
    let (p, pe) = policy.parse(a, p_text)
    if str.eq(kind, "parse") {
        if pe != ok { ret "error" }
        ret p.hash
    }
    if pe != ok { ret "error" }
    if str.eq(kind, "decide") { ret policy.decide(&p, x, y) }
    if str.eq(kind, "classify") {
        let (effect, ce) = policy.classify_write(a, &p, x)
        if ce != ok { ret "error" }
        ret effect
    }
    if str.eq(kind, "audit") {
        ret policy.audit(&p, lines_of(a, x), lines_of(a, y), lines_of(a, z), str.eq(w, "1"))
    }
    if str.eq(kind, "approval") {
        let (effect, scope, found) = str.split_once(z, "\n")
        if !found { ret "error" }
        let (now_text, seen_text, found_now) = str.split_once(w, "\n")
        if !found_now { ret "error" }
        let (status, se) = policy.approval_status(a, y, x, p.hash, effect, scope, parse_decimal(now_text), lines_of(a, seen_text))
        if se != ok { ret "error" }
        ret status
    }
    let (clean, re) = policy.redact(a, x, lines_of(a, y))
    if re != ok { ret "error" }
    ret clean
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
                got = evaluate(a, text_of(m, "k"), text_of(m, "p"), text_of(m, "a"), text_of(m, "b"), text_of(m, "c"), text_of(m, "d"))
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
    try io.print("x agent policy ok")
    ret ok
}
