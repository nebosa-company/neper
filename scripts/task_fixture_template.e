// `x.agent.task` against scripts/task_reference.py: random operation sequences on one task, each
// `{"key": service key, "steps": [step...], "e": outputs joined by newlines}`. A step is tab-separated: `create id
// operation policy scope owner created expires nonce` (outputs `handle:H`), `read H caller now`, `cancel H caller now`,
// `advance to`, `complete outcome result`, `input token now`, `snapshot`.
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.task as task

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

fn array_of(members: []const json.Member, key: str) -> []const json.Value {
    var none: []const json.Value = zero
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, key) {
            switch members[at].value {
            case .Array as items:
                ret items
            default:
                ret none
            }
        }
        at += 1usize
    }
    ret none
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
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

// The nth tab-separated field of a step (0 is the name); empty past the end.
fn field(step: str, n: usize) -> str {
    var begin = 0usize
    var index = 0usize
    var at = 0usize
    while at <= step.len {
        if at == step.len || step[at] == 9u8 {
            if index == n { ret step[begin..at] }
            index += 1usize
            begin = at + 1usize
        }
        at += 1usize
    }
    ret ""
}

fn run_case(a: *mem.Arena, key: str, steps: []const json.Value) -> str {
    var t = task.create("", "", "", "", "", 0usize, 0usize, "")
    var out = ""
    var at = 0usize
    while at < steps.len {
        var step = ""
        switch steps[at] {
        case .String as s:
            step = s
        default:
            step = ""
        }
        let name = field(step, 0usize)
        var line = ""
        if str.eq(name, "create") {
            t = task.create(field(step, 1usize), field(step, 2usize), field(step, 3usize), field(step, 4usize), field(step, 5usize), parse_decimal(field(step, 6usize)), parse_decimal(field(step, 7usize)), field(step, 8usize))
            let (handle, he) = task.handle_of(a, key, &t)
            if he != ok { os.exit(82i32) }
            line = join(a, "handle:", handle)
        } else if str.eq(name, "read") {
            let (status, ae) = task.authorize(a, key, &t, field(step, 1usize), field(step, 2usize), parse_decimal(field(step, 3usize)))
            if ae != ok { os.exit(83i32) }
            if str.eq(status, "ok") { line = join(a, "ok ", t.status) } else { line = status }
        } else if str.eq(name, "cancel") {
            let (status, ae) = task.authorize(a, key, &t, field(step, 1usize), field(step, 2usize), parse_decimal(field(step, 3usize)))
            if ae != ok { os.exit(83i32) }
            if str.eq(status, "ok") { line = task.cancel(&t) } else { line = status }
        } else if str.eq(name, "advance") {
            line = task.advance(&t, field(step, 1usize))
        } else if str.eq(name, "complete") {
            let (status, ce) = task.complete(a, &t, field(step, 1usize), field(step, 2usize))
            if ce != ok { os.exit(84i32) }
            line = status
        } else if str.eq(name, "input") {
            let (status, ie) = task.supply_input(a, key, &t, field(step, 1usize), parse_decimal(field(step, 2usize)))
            if ie != ok { os.exit(85i32) }
            line = status
        } else {
            let (canonical, se) = task.snapshot(a, &t)
            if se != ok { os.exit(86i32) }
            line = canonical
        }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, line)
        at += 1usize
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
                got = run_case(a, text_of(m, "key"), array_of(m, "steps"))
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
    try io.print("x agent task ok")
    ret ok
}
