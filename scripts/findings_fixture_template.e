// `e.algo.findings` (L024: stable finding ids and the idempotent merge of a scanner's report) against
// scripts/findings_reference.py, a transcription of petcow's `stable_id`, `finding_id` and `merge_owned`: petcow's
// own six merge tests and 150 seeded cases of recorded and reported findings (matching ids, changes, owner and
// foreign tools, hand-written findings, repeated reports), merged twice to show the result is a fixed point. A line
// is `I <json array of parts> => <16 hex>` or `M <json case>`; a case holds `base`, `now`, `owner`, `existing`,
// `reported` and the expected `out`, findings as objects with null for an absent text.
use e.algo.findings
use e.fmt.json as json
use e.io
use e.mem
use e.os

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn member(members: []const json.Member, key: str) -> json.Value {
    var none: json.Value = zero
    var i = 0usize
    while i < members.len {
        if same_text(members[i].key, key) { ret members[i].value }
        i += 1usize
    }
    ret none
}

fn text_of(v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn opt_of(v: json.Value) -> findings.Opt {
    switch v {
    case .String as s:
        ret findings.some(s)
    default:
        ret findings.none()
    }
}

fn items_of(v: json.Value) -> []const json.Value {
    var none: []const json.Value = zero
    switch v {
    case .Array as list:
        ret list
    default:
        ret none
    }
}

fn state_of(name: str) -> findings.State {
    if same_text(name, "accepted") { ret .Accepted }
    if same_text(name, "fixed") { ret .Fixed }
    if same_text(name, "false-positive") { ret .FalsePositive }
    ret .Open
}

fn state_name(s: findings.State) -> str {
    if s == .Accepted { ret "accepted" }
    if s == .Fixed { ret "fixed" }
    if s == .FalsePositive { ret "false-positive" }
    ret "open"
}

fn severity_of(name: str) -> findings.Severity {
    if same_text(name, "low") { ret .Low }
    if same_text(name, "medium") { ret .Medium }
    if same_text(name, "high") { ret .High }
    if same_text(name, "critical") { ret .Critical }
    ret .Info
}

fn severity_name(s: findings.Severity) -> str {
    if s == .Low { ret "low" }
    if s == .Medium { ret "medium" }
    if s == .High { ret "high" }
    if s == .Critical { ret "critical" }
    ret "info"
}

fn finding_of(v: json.Value) -> findings.Finding {
    var f: findings.Finding = zero
    switch v {
    case .Object as m:
        f.id = opt_of(member(m, "id"))
        f.tool = text_of(member(m, "tool"))
        f.state = state_of(text_of(member(m, "state")))
        f.severity = severity_of(text_of(member(m, "severity")))
        f.rule = opt_of(member(m, "rule"))
        f.description = text_of(member(m, "description"))
        f.solution = opt_of(member(m, "solution"))
        f.justification = opt_of(member(m, "justification"))
        f.expires = opt_of(member(m, "expires"))
        f.detection_time = text_of(member(m, "detection_time"))
        f.last_update = text_of(member(m, "last_update"))
    default:
        f.tool = ""
    }
    ret f
}

fn reported_of(base: str, v: json.Value) -> findings.Reported {
    var r: findings.Reported = zero
    switch v {
    case .Object as m:
        r.resource = base
        r.tool = text_of(member(m, "tool"))
        r.rule = text_of(member(m, "rule"))
        r.severity = severity_of(text_of(member(m, "severity")))
        r.description = text_of(member(m, "description"))
        r.solution = opt_of(member(m, "solution"))
    default:
        r.tool = ""
    }
    ret r
}

fn opt_value(o: findings.Opt) -> json.Value {
    if o.present { ret json.Value { String: o.text } }
    var null: json.Value = zero
    ret null
}

// A finding as a JSON object in the reference's key order.
fn finding_value(a: *mem.Arena, f: findings.Finding) -> json.Value {
    var none: json.Value = zero
    let (m, e) = mem.alloc[json.Member](a, 11usize)
    if e != ok { ret none }
    m[0usize] = json.Member { key: "id", value: opt_value(f.id) }
    m[1usize] = json.Member { key: "tool", value: json.Value { String: f.tool } }
    m[2usize] = json.Member { key: "state", value: json.Value { String: state_name(f.state) } }
    m[3usize] = json.Member { key: "severity", value: json.Value { String: severity_name(f.severity) } }
    m[4usize] = json.Member { key: "rule", value: opt_value(f.rule) }
    m[5usize] = json.Member { key: "description", value: json.Value { String: f.description } }
    m[6usize] = json.Member { key: "solution", value: opt_value(f.solution) }
    m[7usize] = json.Member { key: "justification", value: opt_value(f.justification) }
    m[8usize] = json.Member { key: "expires", value: opt_value(f.expires) }
    m[9usize] = json.Member { key: "detection_time", value: json.Value { String: f.detection_time } }
    m[10usize] = json.Member { key: "last_update", value: json.Value { String: f.last_update } }
    ret json.Value { Object: m }
}

fn list_text(a: *mem.Arena, list: []const findings.Finding) -> str {
    var none: json.Value = zero
    let (values, e) = mem.alloc[json.Value](a, list.len + 1usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < list.len {
        values[i] = finding_value(a, list[i])
        i += 1usize
    }
    ret write_text(a, json.Value { Array: values[0usize..list.len] })
}

fn write_text(a: *mem.Arena, v: json.Value) -> str {
    let (state, unused, e) = io.memory_writer(a, 0usize)
    if e != ok { ret "?" }
    var held = state
    var w = io.writer(mem.cast[*void](&held), io.memory_write)
    var copy = v
    if json.write(&w, &copy) != ok { ret "?" }
    ret io.memory_bytes(&held)
}

fn parse_line(a: *mem.Arena, text: str) -> json.Value {
    var none: json.Value = zero
    let (v, e) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 16u16 })
    if e != ok { ret none }
    ret v
}

fn find_arrow(line: str) -> usize {
    var i = 0usize
    while i + 3usize < line.len {
        if line[i] == 32u8 && line[i + 1usize] == 61u8 && line[i + 2usize] == 62u8 && line[i + 3usize] == 32u8 { ret i }
        i += 1usize
    }
    ret line.len
}

fn check_id(a: *mem.Arena, line: str) -> bool {
    let arrow = find_arrow(line)
    let parts_value = parse_line(a, line[2usize..arrow])
    let list = items_of(parts_value)
    let (texts, e) = mem.alloc[str](a, list.len + 1usize)
    if e != ok { ret false }
    var i = 0usize
    while i < list.len {
        texts[i] = text_of(list[i])
        i += 1usize
    }
    let (id, id_error) = findings.stable_id(a, texts[0usize..list.len])
    ret id_error == ok && same_text(id, line[arrow + 4usize..line.len])
}

fn check_merge(a: *mem.Arena, line: str) -> bool {
    var case_members: []const json.Member = zero
    switch parse_line(a, line[2usize..line.len]) {
    case .Object as m:
        case_members = m
    default:
        ret false
    }
    let base = text_of(member(case_members, "base"))
    let now = text_of(member(case_members, "now"))
    let owner = text_of(member(case_members, "owner"))
    let existing_values = items_of(member(case_members, "existing"))
    let reported_values = items_of(member(case_members, "reported"))
    let expected_values = items_of(member(case_members, "out"))
    let (existing, e1) = mem.alloc[findings.Finding](a, existing_values.len + 1usize)
    let (reported, e2) = mem.alloc[findings.Reported](a, reported_values.len + 1usize)
    let (expected, e3) = mem.alloc[findings.Finding](a, expected_values.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var i = 0usize
    while i < existing_values.len {
        existing[i] = finding_of(existing_values[i])
        i += 1usize
    }
    i = 0usize
    while i < reported_values.len {
        reported[i] = reported_of(base, reported_values[i])
        i += 1usize
    }
    i = 0usize
    while i < expected_values.len {
        expected[i] = finding_of(expected_values[i])
        i += 1usize
    }
    let (merged, merge_error) = findings.merge(a, base, existing[0usize..existing_values.len], reported[0usize..reported_values.len], now, owner)
    if merge_error != ok { ret false }
    if !same_text(list_text(a, merged), list_text(a, expected[0usize..expected_values.len])) { ret false }
    // Idempotence: merging the same report again into the result changes nothing.
    let (again, again_error) = findings.merge(a, base, merged, reported[0usize..reported_values.len], now, owner)
    if again_error != ok { ret false }
    var idem = false
    switch member(case_members, "idem") {
    case .Bool as b:
        idem = b
    default:
        idem = false
    }
    ret same_text(list_text(a, again), list_text(a, merged)) == idem
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let line = text[start..i]
            let mark = mem.mark(a)
            var good = false
            if line[0usize] == 73u8 { good = check_id(a, line) } else { good = check_merge(a, line) }
            if !good {
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

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    // The tool key drops the version.
    if !same_text(findings.tool_key("checkov (3.2)"), "checkov") { os.exit(100i32) }
    if !same_text(findings.tool_key("  petcow-native  "), "petcow-native") { os.exit(101i32) }
    if !same_text(findings.tool_key("plain"), "plain") { os.exit(102i32) }
    try io.print("algo findings ok")
    ret ok
}
