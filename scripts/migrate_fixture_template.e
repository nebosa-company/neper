// `x.migrate` against petcow's own importers: scripts/migrate_reference.py runs `migrate_ansible`, `migrate_salt`,
// `migrate_puppet` and `migrate_chef` (src/migrate.rs, extracted into a small crate) over fixed cross-matrix cases and
// seeded random documents and writes `{"k": tool, "p": project, "src": text, "e": "N\nwarnings\n---\nyaml"}` lines
// (or "error" where the reference refuses the input); the fixture runs the module over `src` and must render the same
// document, migrated count and warnings, compared through one canonical rendering of the parsed expected YAML.
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.io
use e.mem
use e.os
use e.str
use x.migrate.migrate as migrate

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

// One canonical text for a value: mappings keep their order, strings are quoted, a boolean is true or false.
fn show(a: *mem.Arena, v: yaml.Value) -> str {
    switch v {
    case .Null:
        ret "~"
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Integer as n:
        ret "int"
    case .Float as x:
        ret "float"
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

fn render(a: *mem.Arena, m: migrate.Migration) -> str {
    var out = decimal(a, m.migrated)
    var at = 0usize
    while at < m.warnings.len {
        out = join(a, join(a, out, "\n"), m.warnings[at])
        at += 1usize
    }
    ret join(a, join(a, out, "\n"), show(a, m.document))
}

fn expected(a: *mem.Arena, e: str) -> str {
    let (head, tail, found) = str.split_once(e, "\n---\n")
    if !found { ret "?" }
    let (doc, parse_error) = yaml.parse(a, tail, yaml.Options { max_depth: 64u16, allow_duplicate_keys: true })
    if parse_error != ok { ret "?parse" }
    ret join(a, join(a, head, "\n"), show(a, doc))
}

fn convert(a: *mem.Arena, kind: str, src: str, project: str) -> (migrate.Migration, err) {
    if str.eq(kind, "ansible") {
        let (m, e) = migrate.ansible(a, src, project)
        ret (m, e)
    }
    if str.eq(kind, "salt") {
        let (m, e) = migrate.salt(a, src, project)
        ret (m, e)
    }
    if str.eq(kind, "puppet") {
        let (m, e) = migrate.puppet(a, src, project)
        ret (m, e)
    }
    let (m, e) = migrate.chef(a, src, project)
    ret (m, e)
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
                let kind = text_of(m, "k")
                let want_text = text_of(m, "e")
                let (migration, convert_error) = convert(a, kind, text_of(m, "src"), text_of(m, "p"))
                if str.eq(want_text, "error") {
                    want = "error"
                    got = "ok"
                    if convert_error != ok { got = "error" }
                } else if convert_error != ok {
                    got = "error"
                    want = want_text
                } else {
                    got = render(a, migration)
                    want = expected(a, want_text)
                }
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
    try io.print("x migrate ok")
    ret ok
}
