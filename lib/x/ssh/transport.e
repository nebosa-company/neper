// Per-host transport selection (L048), after Petcow's `transport/mod.rs` `PerHostTransport`: one run over a mixed estate,
// each host naming its transport with a `transport` variable and everything else using the run's default.
//
//   * `kind_for`: the host's `transport` variable when it is a string with something in it (surrounding white space
//     trimmed, as Rust's `str::trim` does), else the default -- a blank value is "unset", not a transport called "";
//   * `resolve`: the kind a host asks for, built lazily by the injected `Factory` the first time a host needs it and kept, so
//     a run over three WinRM hosts never builds the SSM transport (which needs AWS credentials) and five hosts on one kind
//     build it once; a factory failure is reported with the host's name and the kind, because a typo in one host's variables
//     is the mistake per-host selection makes possible.
//
// The factory and the running of a command are host code. The default's name is what `name` reports, so a run is not
// mislabelled as one transport it is not.
//
// Memory: the arena is retained.

use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str
use e.text.utf8 as utf8

// Builds a transport by kind: `(true, "")`, or `(false, displayed error)`.
type Factory = struct { ctx: *void, build: fn(*void, str) -> (bool, str) }

type Table = struct { a: *mem.Arena, default_kind: str, built: list.List[str], factory: Factory }

// What asking for a host's transport answered: the kind, and the displayed error when it could not be built.
type Resolution = struct { kind: str, good: bool, failure: str }

fn new_table(a: *mem.Arena, default_kind: str, factory: Factory) -> Table {
    let (made, e) = list.init[str](a, 4usize)
    var built = made
    if e != ok { built = list.List[str] { items: zero, len: 0usize, arena: a } }
    ret Table { a: a, default_kind: default_kind, built: built, factory: factory }
}

// The default's name, reported per run.
fn name(t: *const Table) -> str { ret t.default_kind }

// Rust's `char::is_whitespace`.
fn is_white(c: u32) -> bool {
    if c >= 9u32 && c <= 13u32 { ret true }
    if c == 32u32 || c == 133u32 || c == 160u32 || c == 5760u32 { ret true }
    if c >= 8192u32 && c <= 8202u32 { ret true }
    ret c == 8232u32 || c == 8233u32 || c == 8239u32 || c == 8287u32 || c == 12288u32
}

// `str::trim`: leading and trailing Unicode white space removed; a malformed byte ends the trimming on that side.
fn trim(s: str) -> str {
    var start = 0usize
    while start < s.len {
        let (d, e) = utf8.decode(s, start)
        if e != ok || !is_white(d.scalar) { break }
        start += usize(d.width)
    }
    var end = s.len
    while end > start {
        var back = end - 1usize
        while back > start && (s[back] & 192u8) == 128u8 { back -= 1usize }
        let (d, e) = utf8.decode(s, back)
        if e != ok || back + usize(d.width) != end || !is_white(d.scalar) { break }
        end = back
    }
    ret s[start..end]
}

// The transport kind a host should use.
fn kind_for(default_kind: str, vars: json.Value) -> str {
    let (members, is_object) = members_of(vars)
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, "transport") {
            switch members[at].value {
            case .String as s:
                let t = trim(s)
                if t.len > 0usize { ret t }
            default:
                let nothing = 0u8
            }
        }
        at += 1usize
    }
    ret default_kind
}

fn members_of(v: json.Value) -> ([]const json.Member, bool) {
    switch v {
    case .Object as m:
        ret (m, true)
    default:
        ret (zero, false)
    }
}

fn is_built(t: *const Table, kind: str) -> bool {
    var at = 0usize
    while at < t.built.len {
        if str.eq(t.built.items[at], kind) { ret true }
        at += 1usize
    }
    ret false
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

// The transport a host's variables ask for, built through the factory the first time and then kept.
fn resolve(t: *Table, host: str, vars: json.Value) -> Resolution {
    let kind = kind_for(t.default_kind, vars)
    if is_built(t, kind) { ret Resolution { kind: kind, good: true, failure: "" } }
    let (good, message) = t.factory.build(t.factory.ctx, kind)
    if !good {
        let head = cat(t.a, cat(t.a, cat(t.a, "in resource '", host), "': transport '"), kind)
        ret Resolution { kind: kind, good: false, failure: cat(t.a, cat(t.a, head, "': "), message) }
    }
    let pushed = list.push[str](&t.built, kind)
    ret Resolution { kind: kind, good: true, failure: "" }
}
