// `x.lint.scan` and `e.fmt.mermaid` against petcow's own scan helpers and diagram emitter: scripts/scan_reference.py runs
// the extracted `scan.rs`/`findings.rs`/`diagram.rs` code over seeded random inputs and writes one JSON line per case
// (`{"op", ..., "e": answer}`). The fixture computes the same answer with the Neper modules and compares the canonical
// JSON; the document `inject` writes is compared through the parsed YAML on both sides.
use e.algo.chain as chain
use e.algo.ir as ir
use e.data.list as list
use e.fmt.json as json
use e.fmt.mermaid as mermaid
use e.fmt.yaml as yaml
use e.io
use e.mem
use e.os
use e.str
use x.lint.scan as scan

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn has_text(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret false }
    let (s, is_text) = ir.string_of(x)
    ret is_text
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn str_value(s: str) -> json.Value { ret json.Value{ String: s } }

fn severity_of(a: *mem.Arena, v: json.Value, key: str) -> scan.Severity {
    let (s, known) = scan.severity_of(a, text_of(v, key))
    ret s
}

fn state_of(s: str) -> scan.State {
    if str.eq(s, "accepted") { ret .Accepted }
    if str.eq(s, "fixed") { ret .Fixed }
    if str.eq(s, "false-positive") { ret .FalsePositive }
    ret .Open
}

fn finding_of(a: *mem.Arena, v: json.Value) -> scan.Finding {
    ret scan.Finding { has_id: has_text(v, "id"), id: text_of(v, "id"), tool: text_of(v, "tool"), state: state_of(text_of(v, "state")), severity: severity_of(a, v, "severity"), has_rule: has_text(v, "rule"), rule: text_of(v, "rule"), description: text_of(v, "description"), has_solution: has_text(v, "solution"), solution: text_of(v, "solution"), has_justification: has_text(v, "justification"), justification: text_of(v, "justification"), has_expires: has_text(v, "expires"), expires: text_of(v, "expires"), detection_time: text_of(v, "detection_time"), last_update: text_of(v, "last_update") }
}

fn finding_json(a: *mem.Arena, f: scan.Finding) -> json.Value {
    var o = obj(a)
    if f.has_id { put(&o, "id", str_value(f.id)) }
    put(&o, "tool", str_value(f.tool))
    put(&o, "state", str_value(scan.state_name(f.state)))
    put(&o, "severity", str_value(scan.severity_name(f.severity)))
    if f.has_rule { put(&o, "rule", str_value(f.rule)) }
    put(&o, "description", str_value(f.description))
    if f.has_solution { put(&o, "solution", str_value(f.solution)) }
    if f.has_justification { put(&o, "justification", str_value(f.justification)) }
    if f.has_expires { put(&o, "expires", str_value(f.expires)) }
    put(&o, "detection_time", str_value(f.detection_time))
    put(&o, "last_update", str_value(f.last_update))
    ret ir.obj_value(&o)
}

fn external_json(a: *mem.Arena, r: scan.External) -> json.Value {
    var o = obj(a)
    put(&o, "rule", str_value(r.rule))
    put(&o, "description", str_value(r.description))
    put(&o, "severity", str_value(scan.severity_name(r.severity)))
    put(&o, "hint", str_value(r.hint))
    ret ir.obj_value(&o)
}

fn externals_json(a: *mem.Arena, rs: []const scan.External) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, rs.len + 1usize)
    if e != ok { os.exit(82i32) }
    var at = 0usize
    while at < rs.len {
        out[at] = external_json(a, rs[at])
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..rs.len] }
}

fn external_of(a: *mem.Arena, v: json.Value) -> scan.External {
    ret scan.External { rule: text_of(v, "rule"), description: text_of(v, "description"), severity: severity_of(a, v, "severity"), hint: text_of(v, "hint") }
}

fn reported_of(a: *mem.Arena, v: json.Value) -> scan.Reported {
    ret scan.Reported { resource: text_of(v, "resource"), tool: text_of(v, "tool"), rule: text_of(v, "rule"), severity: severity_of(a, v, "severity"), description: text_of(v, "description"), has_solution: has_text(v, "solution"), solution: text_of(v, "solution") }
}

fn ok_wrap(a: *mem.Arena, v: json.Value) -> json.Value {
    var o = obj(a)
    put(&o, "ok", v)
    ret ir.obj_value(&o)
}

fn error_value(a: *mem.Arena) -> json.Value {
    var o = obj(a)
    put(&o, "error", json.Value{ Bool: true })
    ret ir.obj_value(&o)
}

// --- the YAML canonical text -------------------------------------------------------------------------------------------

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
    case .Sequence as xs:
        var out = "["
        var at = 0usize
        while at < xs.len {
            if at > 0usize { out = join(a, out, ",") }
            out = join(a, out, show(a, xs[at]))
            at += 1usize
        }
        ret join(a, out, "]")
    case .Mapping as pairs:
        var out = "{"
        var at = 0usize
        while at < pairs.len {
            if at > 0usize { out = join(a, out, ",") }
            out = join(a, join(a, join(a, out, show(a, pairs[at].key)), ":"), show(a, pairs[at].value))
            at += 1usize
        }
        ret join(a, out, "}")
    default:
        ret "?"
    }
}

fn by_name(a: *mem.Arena, v: json.Value) -> scan.ByName {
    let (members, is_object) = ir.members_of(v)
    let (names, ne) = mem.alloc[str](a, members.len + 1usize)
    let (lists, le) = mem.alloc[[]const scan.Finding](a, members.len + 1usize)
    if ne != ok || le != ok { os.exit(83i32) }
    var at = 0usize
    while is_object && at < members.len {
        names[at] = members[at].key
        let xs = items(members[at].value)
        let (fs, fe) = mem.alloc[scan.Finding](a, xs.len + 1usize)
        if fe != ok { os.exit(84i32) }
        var k = 0usize
        while k < xs.len {
            fs[k] = finding_of(a, xs[k])
            k += 1usize
        }
        lists[at] = fs[0usize..xs.len]
        at += 1usize
    }
    var count = 0usize
    if is_object { count = members.len }
    ret scan.ByName { names: names[0usize..count], findings: lists[0usize..count] }
}

// --- the case ---------------------------------------------------------------------------------------------------------

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "checkov") || str.eq(op, "semgrep") {
        var results: []const scan.External = zero
        var e: err = ok
        if str.eq(op, "checkov") {
            let (r, re) = scan.parse_checkov(a, text_of(c, "json"))
            results = r
            e = re
        } else {
            let (r, re) = scan.parse_semgrep(a, text_of(c, "json"))
            results = r
            e = re
        }
        if e != ok { ret error_value(a) }
        ret ok_wrap(a, externals_json(a, results))
    }
    if str.eq(op, "map") {
        let rs = items(ir.value_of(c, "results"))
        let (externals, xe) = mem.alloc[scan.External](a, rs.len + 1usize)
        if xe != ok { os.exit(85i32) }
        var i = 0usize
        while i < rs.len {
            externals[i] = external_of(a, rs[i])
            i += 1usize
        }
        let bs = items(ir.value_of(c, "bases"))
        let (bases, be) = mem.alloc[str](a, bs.len + 1usize)
        if be != ok { os.exit(86i32) }
        var b = 0usize
        while b < bs.len {
            let (s, is_text) = ir.string_of(bs[b])
            bases[b] = s
            b += 1usize
        }
        let m = scan.map_external(a, externals[0usize..rs.len], text_of(c, "tool"), bases[0usize..bs.len])
        let (mapped, me) = mem.alloc[json.Value](a, m.mapped.len + 1usize)
        if me != ok { os.exit(87i32) }
        var k = 0usize
        while k < m.mapped.len {
            var o = obj(a)
            put(&o, "resource", str_value(m.mapped[k].resource))
            put(&o, "tool", str_value(m.mapped[k].tool))
            put(&o, "rule", str_value(m.mapped[k].rule))
            put(&o, "severity", str_value(scan.severity_name(m.mapped[k].severity)))
            put(&o, "description", str_value(m.mapped[k].description))
            put(&o, "solution", .Null)
            mapped[k] = ir.obj_value(&o)
            k += 1usize
        }
        var o = obj(a)
        put(&o, "mapped", json.Value{ Array: mapped[0usize..m.mapped.len] })
        put(&o, "unmapped", externals_json(a, m.unmapped))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "id") {
        var o = obj(a)
        put(&o, "id", str_value(scan.finding_id(a, text_of(c, "resource"), text_of(c, "tool"), text_of(c, "rule"))))
        put(&o, "key", str_value(scan.tool_key(text_of(c, "tool"))))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "merge") {
        let es = items(ir.value_of(c, "existing"))
        let (existing, ee) = mem.alloc[scan.Finding](a, es.len + 1usize)
        if ee != ok { os.exit(88i32) }
        var i = 0usize
        while i < es.len {
            existing[i] = finding_of(a, es[i])
            i += 1usize
        }
        let rs = items(ir.value_of(c, "reported"))
        let (reported, re) = mem.alloc[scan.Reported](a, rs.len + 1usize)
        if re != ok { os.exit(89i32) }
        var r = 0usize
        while r < rs.len {
            reported[r] = reported_of(a, rs[r])
            r += 1usize
        }
        let merged = scan.merge(a, text_of(c, "base"), existing[0usize..es.len], reported[0usize..rs.len], text_of(c, "now"), text_of(c, "owner"))
        let (out, oe) = mem.alloc[json.Value](a, merged.len + 1usize)
        if oe != ok { os.exit(90i32) }
        var k = 0usize
        while k < merged.len {
            out[k] = finding_json(a, merged[k])
            k += 1usize
        }
        ret json.Value{ Array: out[0usize..merged.len] }
    }
    if str.eq(op, "mermaid") {
        let ins = items(ir.value_of(c, "instances"))
        let (nodes, ne) = mem.alloc[mermaid.Node](a, ins.len + 1usize)
        if ne != ok { os.exit(91i32) }
        var i = 0usize
        while i < ins.len {
            let ds = items(ir.value_of(ins[i], "depends_on"))
            let (deps, de) = mem.alloc[str](a, ds.len + 1usize)
            if de != ok { os.exit(92i32) }
            var d = 0usize
            while d < ds.len {
                let (s, is_text) = ir.string_of(ds[d])
                deps[d] = s
                d += 1usize
            }
            var blocked = false
            switch ir.value_of(ins[i], "blocking") {
            case .Bool as flag:
                blocked = flag
            default:
                blocked = false
            }
            nodes[i] = mermaid.Node { id: text_of(ins[i], "logical_id"), kind: text_of(ins[i], "type"), depends_on: deps[0usize..ds.len], blocked: blocked }
            i += 1usize
        }
        let (text, te) = mermaid.flowchart(a, text_of(c, "project"), nodes[0usize..ins.len])
        if te != ok { os.exit(93i32) }
        ret ok_wrap(a, str_value(text))
    }
    ret .Null
}

// The expected answer for an `inject`, and Neper's, as the same canonical text.
fn inject_matches(a: *mem.Arena, c: json.Value) -> bool {
    let want = ir.value_of(c, "e")
    let (doc, e) = scan.inject_findings(a, text_of(c, "doc"), by_name(a, ir.value_of(c, "managed")), by_name(a, ir.value_of(c, "unmanaged")))
    let (err_flag, have_err) = ir.get(want, "error")
    if have_err { ret e != ok }
    if e != ok { ret false }
    let (parsed, pe) = yaml.parse(a, text_of(want, "ok"), yaml.Options { max_depth: 64u16, allow_duplicate_keys: true })
    if pe != ok { ret false }
    ret str.eq(show(a, doc), show(a, parsed))
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let op = text_of(c, "op")
    if str.eq(op, "inject") { ret inject_matches(a, c) }
    let (got, ge) = chain.canonical_json(a, answer(a, c))
    let (want, we) = chain.canonical_json(a, ir.value_of(c, "e"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got, want) {
        let shown = io.print(join(a, join(a, "\nGOT  ", got), join(a, "\nWANT ", want)))
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
            if parse_error != ok || !run_one(a, root) {
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
    try io.print("x lint scan ok")
    ret ok
}
