// Security-scan findings (L042), after petcow's `scan.rs` (and `findings.rs`): the external scanner result parsers
// (`checkov -o json`, `semgrep --json`) with a lenient severity, the mapping of a result to a resource by whether a
// resource name appears in its hint, stable finding ids (FNV-1a over resource, tool without its version, and rule), the
// idempotent merge of freshly reported findings into the ones already recorded (a human-managed state survives a
// re-scan, a finding that stops reproducing is auto-fixed, findings of other tools are left alone), and the writing of
// findings back into a document under `resources` and `unmanaged`. The scanners' output is read as YAML, which is a
// superset of JSON, as petcow reads it: text that is no structure at all yields no results rather than an error.
//
// Memory: the arena is retained; every list and string lives in it.

use e.data.list as list
use e.fmt.yaml as yaml
use e.mem
use e.str

error Invalid

type Severity = enum u8 { Info, Low, Medium, High, Critical }

type State = enum u8 { Open, Accepted, Fixed, FalsePositive }

// A finding as recorded on a resource.
type Finding = struct { has_id: bool, id: str, tool: str, state: State, severity: Severity, has_rule: bool, rule: str, description: str, has_solution: bool, solution: str, has_justification: bool, justification: str, has_expires: bool, expires: str, detection_time: str, last_update: str }

// A finding as a scanner reported it, before an id is assigned.
type Reported = struct { resource: str, tool: str, rule: str, severity: Severity, description: str, has_solution: bool, solution: str }

// A raw result of an external scanner; `hint` is the free text (a resource address or path) it is mapped by.
type External = struct { rule: str, description: str, severity: Severity, hint: str }

fn severity_name(s: Severity) -> str {
    switch s {
    case .Info:
        ret "info"
    case .Low:
        ret "low"
    case .Medium:
        ret "medium"
    case .High:
        ret "high"
    case .Critical:
        ret "critical"
    }
}

fn state_name(s: State) -> str {
    switch s {
    case .Open:
        ret "open"
    case .Accepted:
        ret "accepted"
    case .Fixed:
        ret "fixed"
    case .FalsePositive:
        ret "false-positive"
    }
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

// The severity a scanner's text names; absent when it names none.
fn severity_of(a: *mem.Arena, s: str) -> (Severity, bool) {
    let t = lower(a, str.trim(s))
    if str.eq(t, "info") || str.eq(t, "informational") { ret (.Info, true) }
    if str.eq(t, "low") { ret (.Low, true) }
    if str.eq(t, "medium") || str.eq(t, "moderate") { ret (.Medium, true) }
    if str.eq(t, "high") { ret (.High, true) }
    if str.eq(t, "critical") { ret (.Critical, true) }
    ret (.Medium, false)
}

fn rank(s: Severity) -> i32 {
    switch s {
    case .Info:
        ret 0
    case .Low:
        ret 1
    case .Medium:
        ret 2
    case .High:
        ret 3
    case .Critical:
        ret 4
    }
}

// Whether a finding blocks `apply` by default: open, and high or worse.
fn is_blocking(f: Finding) -> bool { ret f.state == .Open && rank(f.severity) >= 3 }

// --- reading YAML ----------------------------------------------------------------------------------------------------

fn key_of(v: yaml.Value, name: str) -> (yaml.Value, bool) {
    switch v {
    case .Mapping as pairs:
        var at = 0usize
        while at < pairs.len {
            switch pairs[at].key {
            case .String as k:
                if str.eq(k, name) { ret (pairs[at].value, true) }
            default:
                at = at
            }
            at += 1usize
        }
        ret (.Null, false)
    default:
        ret (.Null, false)
    }
}

fn str_of(v: yaml.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

fn seq_of(v: yaml.Value) -> ([]const yaml.Value, bool) {
    switch v {
    case .Sequence as items:
        ret (items, true)
    default:
        ret (zero, false)
    }
}

fn get_str(v: yaml.Value, name: str) -> (str, bool) {
    let (x, found) = key_of(v, name)
    if !found { ret ("", false) }
    let (s, is_text) = str_of(x)
    ret (s, is_text)
}

fn parse_options() -> yaml.Options { ret yaml.Options { max_depth: 64u16, allow_duplicate_keys: true } }

fn new_externals(a: *mem.Arena) -> list.List[External] {
    let (l, e) = list.init[External](a, 8usize)
    if e != ok { ret list.List[External] { items: zero, len: 0usize, arena: a } }
    ret l
}

// `checkov -o json`: the failed checks of one report or an array of them. `Invalid` when the text is not YAML.
fn parse_checkov(a: *mem.Arena, source: str) -> ([]const External, err) {
    let (v, parse_error) = yaml.parse(a, source, parse_options())
    if parse_error != ok { ret (zero, Invalid) }
    var out = new_externals(a)
    var roots: []const yaml.Value = zero
    let (items, is_seq) = seq_of(v)
    var single: [1]yaml.Value = zero
    if is_seq {
        roots = items
    } else {
        single[0] = v
        let (copy, ce) = mem.alloc[yaml.Value](a, 1usize)
        if ce != ok { ret (zero, Invalid) }
        copy[0] = v
        roots = copy[0usize..1usize]
    }
    var r = 0usize
    while r < roots.len {
        let (results, have_results) = key_of(roots[r], "results")
        let (failed, have_failed) = key_of(results, "failed_checks")
        let (checks, is_checks) = seq_of(failed)
        if have_results && have_failed && is_checks {
            var c = 0usize
            while c < checks.len {
                var rule = "UNKNOWN"
                let (rule_text, have_rule) = get_str(checks[c], "check_id")
                if have_rule { rule = rule_text }
                var description = "(no description)"
                let (desc_text, have_desc) = get_str(checks[c], "check_name")
                if have_desc { description = desc_text }
                var severity: Severity = .Medium
                let (sev_text, have_sev) = get_str(checks[c], "severity")
                if have_sev {
                    let (s, known) = severity_of(a, sev_text)
                    if known { severity = s } else { severity = .Medium }
                }
                var hint = ""
                let (resource, have_resource) = get_str(checks[c], "resource")
                if have_resource {
                    hint = resource
                } else {
                    let (path, have_path) = get_str(checks[c], "file_path")
                    if have_path { hint = path }
                }
                let pushed = list.push[External](&out, External { rule: rule, description: description, severity: severity, hint: hint })
                c += 1usize
            }
        }
        r += 1usize
    }
    ret (list.slice_const[External](&out), ok)
}

// `semgrep --json`: ERROR is high, WARNING medium, anything else low.
fn parse_semgrep(a: *mem.Arena, source: str) -> ([]const External, err) {
    let (v, parse_error) = yaml.parse(a, source, parse_options())
    if parse_error != ok { ret (zero, Invalid) }
    var out = new_externals(a)
    let (results, have_results) = key_of(v, "results")
    let (items, is_seq) = seq_of(results)
    if !have_results || !is_seq { ret (list.slice_const[External](&out), ok) }
    var r = 0usize
    while r < items.len {
        var rule = "UNKNOWN"
        let (rule_text, have_rule) = get_str(items[r], "check_id")
        if have_rule { rule = rule_text }
        let (extra, have_extra) = key_of(items[r], "extra")
        var description = "(no description)"
        let (message, have_message) = get_str(extra, "message")
        if have_extra && have_message { description = message }
        var severity: Severity = .Medium
        let (sev_text, have_sev) = get_str(extra, "severity")
        if have_extra && have_sev {
            let upper = lower(a, sev_text)
            if str.eq(upper, "error") {
                severity = .High
            } else if str.eq(upper, "warning") {
                severity = .Medium
            } else {
                severity = .Low
            }
        }
        var hint = ""
        let (path, have_path) = get_str(items[r], "path")
        if have_path { hint = path }
        let pushed = list.push[External](&out, External { rule: rule, description: description, severity: severity, hint: hint })
        r += 1usize
    }
    ret (list.slice_const[External](&out), ok)
}

// --- ids and mapping ---------------------------------------------------------------------------------------------------

// The tool without its version: `checkov (3.2)` is `checkov`.
fn tool_key(tool: str) -> str {
    let (at, found) = str.find(tool, " (")
    if found { ret str.trim(tool[0usize..at]) }
    ret str.trim(tool)
}

fn hex_digit(n: u64) -> u8 {
    if n < 10u64 { ret u8(48u64 + n) }
    ret u8(87u64 + n)
}

// A deterministic id for parts: FNV-1a 64 over the bytes with `|` between parts, as 16 hex digits.
fn stable_id(a: *mem.Arena, parts: []const str) -> str {
    var hash = 14695981039346656037u64
    var i = 0usize
    while i < parts.len {
        if i > 0usize {
            hash = hash ^ 124u64
            hash = hash *% 1099511628211u64
        }
        var b = 0usize
        while b < parts[i].len {
            hash = hash ^ u64(parts[i][b])
            hash = hash *% 1099511628211u64
            b += 1usize
        }
        i += 1usize
    }
    let (out, e) = mem.alloc[u8](a, 16usize)
    if e != ok { ret "" }
    var k = 0usize
    while k < 16usize {
        let shift = u64(60usize - k * 4usize)
        out[k] = hex_digit((hash >> shift) & 15u64)
        k += 1usize
    }
    ret out[0usize..16usize]
}

fn finding_id(a: *mem.Arena, resource: str, tool: str, rule: str) -> str {
    let (parts, e) = mem.alloc[str](a, 3usize)
    if e != ok { ret "" }
    parts[0] = resource
    parts[1] = tool_key(tool)
    parts[2] = rule
    ret stable_id(a, parts[0usize..3usize])
}

type Mapped = struct { mapped: []const Reported, unmapped: []const External }

// Map results to resources by whether a resource's base name appears in the hint (the first one listed that does).
fn map_external(a: *mem.Arena, results: []const External, tool: str, bases: []const str) -> Mapped {
    let (m, me) = list.init[Reported](a, 8usize)
    var mapped = m
    var unmapped = new_externals(a)
    var r = 0usize
    while r < results.len {
        var found = false
        var b = 0usize
        while b < bases.len && !found {
            if str.contains(results[r].hint, bases[b]) {
                found = true
                let pushed = list.push[Reported](&mapped, Reported { resource: bases[b], tool: tool, rule: results[r].rule, severity: results[r].severity, description: results[r].description, has_solution: false, solution: "" })
            }
            b += 1usize
        }
        if !found {
            let pushed = list.push[External](&unmapped, results[r])
        }
        r += 1usize
    }
    ret Mapped { mapped: list.slice_const[Reported](&mapped), unmapped: list.slice_const[External](&unmapped) }
}

// --- the merge ---------------------------------------------------------------------------------------------------------

fn before(x: Finding, y: Finding) -> bool {
    var c = str.compare(x.tool, y.tool)
    if c != 0i32 { ret c < 0i32 }
    var xr = ""
    if x.has_rule { xr = x.rule }
    var yr = ""
    if y.has_rule { yr = y.rule }
    c = str.compare(xr, yr)
    if c != 0i32 { ret c < 0i32 }
    ret str.compare(x.description, y.description) < 0i32
}

fn in_ids(ids: []const str, id: str) -> bool {
    var at = 0usize
    while at < ids.len {
        if str.eq(ids[at], id) { ret true }
        at += 1usize
    }
    ret false
}

// Merge reported findings for one resource into its recorded ones. An existing finding matched by id keeps its state,
// justification, expiry and detection time and takes the new description and severity (`last_update` moves only on a
// change); a reported finding not seen before is opened; an open finding of `owner_tool` no longer reported is fixed;
// everything else is kept as is. The result is ordered by tool, rule and description.
fn merge(a: *mem.Arena, base: str, existing: []const Finding, reported: []const Reported, now: str, owner_tool: str) -> []const Finding {
    let (made, e) = list.init[Finding](a, 8usize)
    if e != ok { ret zero }
    var out = made
    let (seen_made, se) = list.init[str](a, 8usize)
    if se != ok { ret zero }
    var seen = seen_made
    var r = 0usize
    while r < reported.len {
        let id = finding_id(a, base, reported[r].tool, reported[r].rule)
        let pushed_id = list.push[str](&seen, id)
        var prev_index = existing.len
        var k = 0usize
        while k < existing.len {
            if existing[k].has_id && str.eq(existing[k].id, id) && prev_index == existing.len { prev_index = k }
            k += 1usize
        }
        let rep = reported[r]
        if prev_index < existing.len {
            let prev = existing[prev_index]
            let changed = !str.eq(prev.description, rep.description) || prev.severity != rep.severity
            var f = Finding { has_id: true, id: id, tool: rep.tool, state: prev.state, severity: rep.severity, has_rule: true, rule: rep.rule, description: rep.description, has_solution: prev.has_solution, solution: prev.solution, has_justification: prev.has_justification, justification: prev.justification, has_expires: prev.has_expires, expires: prev.expires, detection_time: prev.detection_time, last_update: prev.last_update }
            if !prev.has_solution && rep.has_solution {
                f.has_solution = true
                f.solution = rep.solution
            }
            if changed { f.last_update = now }
            let pushed = list.push[Finding](&out, f)
        } else {
            let f = Finding { has_id: true, id: id, tool: rep.tool, state: .Open, severity: rep.severity, has_rule: true, rule: rep.rule, description: rep.description, has_solution: rep.has_solution, solution: rep.solution, has_justification: false, justification: "", has_expires: false, expires: "", detection_time: now, last_update: now }
            let pushed = list.push[Finding](&out, f)
        }
        r += 1usize
    }
    let seen_ids = list.slice_const[str](&seen)
    var i = 0usize
    while i < existing.len {
        let ex = existing[i]
        if ex.has_id && in_ids(seen_ids, ex.id) {
            i = i
        } else if ex.has_id && str.starts_with(ex.tool, owner_tool) && ex.state == .Open {
            var f = ex
            f.state = .Fixed
            f.last_update = now
            if !f.has_solution {
                f.has_solution = true
                f.solution = "no longer reported"
            }
            let pushed = list.push[Finding](&out, f)
        } else {
            let pushed = list.push[Finding](&out, ex)
        }
        i += 1usize
    }
    // a stable insertion sort
    var n = 1usize
    while n < out.len {
        let item = out.items[n]
        var j = n
        while j > 0usize && before(item, out.items[j - 1usize]) {
            out.items[j] = out.items[j - 1usize]
            j -= 1usize
        }
        out.items[j] = item
        n += 1usize
    }
    ret list.slice_const[Finding](&out)
}

// --- writing back ---------------------------------------------------------------------------------------------------------

fn plain(s: str) -> yaml.Value { ret yaml.Value{ String: s } }

fn pair(k: str, v: str) -> yaml.Pair { ret yaml.Pair { key: plain(k), value: plain(v) } }

// A finding as a YAML mapping: kebab-case keys, absent fields omitted.
fn finding_to_value(a: *mem.Arena, f: Finding) -> yaml.Value {
    let (made, e) = list.init[yaml.Pair](a, 12usize)
    if e != ok { ret .Null }
    var m = made
    if f.has_id { let p = list.push[yaml.Pair](&m, pair("id", f.id)) }
    let p1 = list.push[yaml.Pair](&m, pair("tool", f.tool))
    if f.has_rule { let p = list.push[yaml.Pair](&m, pair("rule", f.rule)) }
    let p2 = list.push[yaml.Pair](&m, pair("state", state_name(f.state)))
    let p3 = list.push[yaml.Pair](&m, pair("severity", severity_name(f.severity)))
    let p4 = list.push[yaml.Pair](&m, pair("description", f.description))
    if f.has_solution { let p = list.push[yaml.Pair](&m, pair("solution", f.solution)) }
    if f.has_justification { let p = list.push[yaml.Pair](&m, pair("justification", f.justification)) }
    if f.has_expires { let p = list.push[yaml.Pair](&m, pair("expires", f.expires)) }
    let p5 = list.push[yaml.Pair](&m, pair("detection-time", f.detection_time))
    let p6 = list.push[yaml.Pair](&m, pair("last-update", f.last_update))
    ret yaml.Value{ Mapping: list.slice_const[yaml.Pair](&m) }
}

fn findings_sequence(a: *mem.Arena, findings: []const Finding) -> yaml.Value {
    let (out, e) = mem.alloc[yaml.Value](a, findings.len + 1usize)
    if e != ok { ret .Null }
    var at = 0usize
    while at < findings.len {
        out[at] = finding_to_value(a, findings[at])
        at += 1usize
    }
    ret yaml.Value{ Sequence: out[0usize..findings.len] }
}

// The pairs of a mapping with `key` set (replaced in place, or appended).
fn with_key(a: *mem.Arena, pairs: []const yaml.Pair, key: str, v: yaml.Value) -> []const yaml.Pair {
    let (made, e) = list.init[yaml.Pair](a, pairs.len + 1usize)
    if e != ok { ret pairs }
    var out = made
    var replaced = false
    var at = 0usize
    while at < pairs.len {
        var is_key = false
        switch pairs[at].key {
        case .String as k:
            is_key = str.eq(k, key)
        default:
            is_key = false
        }
        if is_key && !replaced {
            let pushed = list.push[yaml.Pair](&out, yaml.Pair { key: pairs[at].key, value: v })
            replaced = true
        } else {
            let pushed = list.push[yaml.Pair](&out, pairs[at])
        }
        at += 1usize
    }
    if !replaced {
        let pushed = list.push[yaml.Pair](&out, yaml.Pair { key: plain(key), value: v })
    }
    ret list.slice_const[yaml.Pair](&out)
}

// Findings for resources by name (the names in sorted order, as a map would iterate them).
type ByName = struct { names: []const str, findings: [][]const Finding }

fn find_for(by: ByName, name: str) -> []const Finding {
    var at = 0usize
    while at < by.names.len {
        if str.eq(by.names[at], name) { ret by.findings[at] }
        at += 1usize
    }
    ret zero
}

// Write findings into a document: under `resources.<base>` for managed resources and under the `unmanaged` entry of that
// `name`; a resource or entry with no findings is left as it is. `Invalid` when the text is not YAML or has no
// `resources` mapping.
fn inject_findings(a: *mem.Arena, doc_text: str, managed: ByName, unmanaged: ByName) -> (yaml.Value, err) {
    let (doc, parse_error) = yaml.parse(a, doc_text, parse_options())
    if parse_error != ok { ret (.Null, Invalid) }
    var top: []const yaml.Pair = zero
    switch doc {
    case .Mapping as pairs:
        top = pairs
    default:
        ret (.Null, Invalid)
    }
    let (resources, have_resources) = key_of(doc, "resources")
    var res_pairs: []const yaml.Pair = zero
    var is_map = false
    switch resources {
    case .Mapping as pairs:
        res_pairs = pairs
        is_map = true
    default:
        is_map = false
    }
    if !have_resources || !is_map { ret (.Null, Invalid) }
    var m = 0usize
    while m < managed.names.len {
        if managed.findings[m].len > 0usize {
            var at = 0usize
            while at < res_pairs.len {
                var is_base = false
                switch res_pairs[at].key {
                case .String as k:
                    is_base = str.eq(k, managed.names[m])
                default:
                    is_base = false
                }
                if is_base {
                    switch res_pairs[at].value {
                    case .Mapping as inner:
                        let updated = with_key(a, inner, "findings", findings_sequence(a, managed.findings[m]))
                        let (copy, ce) = mem.alloc[yaml.Pair](a, res_pairs.len + 1usize)
                        if ce != ok { ret (.Null, Invalid) }
                        var c = 0usize
                        while c < res_pairs.len {
                            copy[c] = res_pairs[c]
                            c += 1usize
                        }
                        copy[at] = yaml.Pair { key: res_pairs[at].key, value: yaml.Value{ Mapping: updated } }
                        res_pairs = copy[0usize..res_pairs.len]
                    default:
                        at = at
                    }
                }
                at += 1usize
            }
        }
        m += 1usize
    }
    var result_top = with_key(a, top, "resources", yaml.Value{ Mapping: res_pairs })
    let (entries, have_entries) = key_of(doc, "unmanaged")
    let (items, is_seq) = seq_of(entries)
    if have_entries && is_seq {
        let (copy, ce) = mem.alloc[yaml.Value](a, items.len + 1usize)
        if ce != ok { ret (.Null, Invalid) }
        var i = 0usize
        while i < items.len {
            copy[i] = items[i]
            let (name, have_name) = get_str(items[i], "name")
            if have_name {
                let found = find_for(unmanaged, name)
                if found.len > 0usize {
                    switch items[i] {
                    case .Mapping as pairs:
                        copy[i] = yaml.Value{ Mapping: with_key(a, pairs, "findings", findings_sequence(a, found)) }
                    default:
                        i = i
                    }
                }
            }
            i += 1usize
        }
        result_top = with_key(a, result_top, "unmanaged", yaml.Value{ Sequence: copy[0usize..items.len] })
    }
    ret (yaml.Value{ Mapping: result_top }, ok)
}
