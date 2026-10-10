// `x.migrate.terraform` against petcow's own `migrate_hcl` (src/migrate.rs, extracted into a small crate):
// scripts/terraform_reference.py runs it over fixed and seeded random Terraform and writes `{"p": project, "src": text,
// "e": "migrated: N\nwarning: ...\n---\nyaml"}` lines (or "error" where the reference refuses the HCL). The fixture runs
// the module over `src` and must render the same migrated count, warnings and document, compared through one canonical
// rendering of the parsed expected YAML.
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.io
use e.mem
use e.os
use e.str
use x.migrate.terraform as terraform

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

fn escaped(a: *mem.Arena, s: str) -> str {
    var out = ""
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 34u8 {
            out = join(a, out, "\\\"")
        } else if c == 92u8 {
            out = join(a, out, "\\\\")
        } else if c == 10u8 {
            out = join(a, out, "\\n")
        } else {
            out = join(a, out, s[at..at + 1usize])
        }
        at += 1usize
    }
    ret out
}

fn number_text(a: *mem.Arena, x: f64, is_float: bool, n: i64) -> str {
    let (b, e) = str.builder(a, 32usize)
    if e != ok { os.exit(81i32) }
    var out = b
    if is_float {
        let p = str.push_f64(&out, x)
    } else {
        let p = str.push_i64(&out, n)
    }
    ret str.done(&out)
}

// One canonical text for a value: mappings keep their order, strings are quoted, numbers print as numbers.
fn show(a: *mem.Arena, v: yaml.Value) -> str {
    switch v {
    case .Null:
        ret "~"
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Integer as n:
        ret number_text(a, 0.0f64, false, n)
    case .Float as x:
        ret number_text(a, x, true, 0i64)
    case .String as s:
        ret join(a, join(a, "\"", escaped(a, s)), "\"")
    case .Sequence as items:
        var out = "["
        var at = 0usize
        while at < items.len {
            if at > 0usize { out = join(a, out, ",") }
            out = join(a, out, show(a, items[at]))
            at += 1usize
        }
        ret join(a, out, "]")
    case .Mapping as pairs:
        var out = "{"
        var at = 0usize
        while at < pairs.len {
            if at > 0usize { out = join(a, out, ",") }
            out = join(a, out, show(a, pairs[at].key))
            out = join(a, out, ":")
            out = join(a, out, show(a, pairs[at].value))
            at += 1usize
        }
        ret join(a, out, "}")
    default:
        ret "?"
    }
}

// The migration as one canonical text: the count, the warnings and the document.
fn render(a: *mem.Arena, m: terraform.Migration) -> str {
    var out = decimal(a, m.migrated)
    var at = 0usize
    while at < m.warnings.len {
        out = join(a, join(a, out, "\n"), m.warnings[at])
        at += 1usize
    }
    ret join(a, join(a, out, "\n"), show(a, m.document))
}

// The reference's text in the same shape: the `migrated: ` prefix and each `warning: ` prefix removed.
fn expected(a: *mem.Arena, e: str) -> str {
    let (head, tail, found) = str.split_once(e, "\n---\n")
    if !found { ret "?" }
    let (doc, parse_error) = yaml.parse(a, tail, yaml.Options { max_depth: 64u16, allow_duplicate_keys: true })
    if parse_error != ok { ret "?parse" }
    var out = ""
    var start = 0usize
    var first = true
    var i = 0usize
    while i <= head.len {
        if i == head.len || head[i] == 10u8 {
            var line = head[start..i]
            if str.starts_with(line, "migrated: ") { line = line[10usize..] }
            if str.starts_with(line, "warning: ") { line = line[9usize..] }
            if !first { out = join(a, out, "\n") }
            out = join(a, out, line)
            first = false
            start = i + 1usize
        }
        i += 1usize
    }
    ret join(a, join(a, out, "\n"), show(a, doc))
}

fn run_case(a: *mem.Arena, root: json.Value) -> bool {
    let members = members_of(root)
    let src = text_of(members, "src")
    let project = text_of(members, "p")
    let want = text_of(members, "e")
    let (m, e) = terraform.migrate_hcl(a, src, project)
    if e != ok { ret str.eq(want, "error") }
    if str.eq(want, "error") { ret false }
    let got = render(a, m)
    let want_shown = expected(a, want)
    if !str.eq(got, want_shown) {
        let shown = io.print(join(a, "\nGOT\n", got))
        let shown_want = io.print(join(a, "\nWANT\n", want_shown))
        ret false
    }
    ret true
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
            if parse_error != ok || !run_case(a, root) {
                let shown = io.print(line)
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
    try io.print("x migrate terraform ok")
    ret ok
}
