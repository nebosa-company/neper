// Stable finding ids and the idempotent merge of a scanner's report into recorded findings (L024), after petcow's
// `src/scan.rs`. It is the reconciliation pattern behind a lint or scan integration that writes its results back
// into a document: run it twice and nothing changes, a person's decisions survive a re-scan, and one scanner never
// clobbers another's findings.
//
// A finding's id is `stable_id` of the resource, the tool (without its version, so an upgrade does not change
// ids) and the rule: FNV-1a 64 over the parts with a `|` between them, as 16 lowercase hex digits. `merge` takes
// the findings already recorded for one resource and what a scanner now reports for it:
//   - a reported finding that matches a recorded one by id keeps the recorded state, justification, expiry and
//     detection time and takes the scanner's current severity and description; `last_update` moves to `now` only
//     when the severity or the description changed; a recorded solution wins over the scanner's;
//   - a reported finding with no recorded match is new: `Open`, detected and updated `now`;
//   - a recorded `Open` finding of the owner tool (`owner_tool` is a prefix of its tool text) that is no longer
//     reported is resolved: `Fixed`, `last_update` `now`, and the solution "no longer reported" if it had none;
//   - every other recorded finding (hand-written without an id, another tool's, or not open) is kept as it is.
// The result is sorted by tool, rule and description (bytewise, stable).
//
// A text that may be absent is an `Opt`: `present` false means none, which is not the same as an empty text.

use e.mem

error Invalid

type State = enum u8 { Open, Accepted, Fixed, FalsePositive }

type Severity = enum u8 { Info, Low, Medium, High, Critical }

type Opt = struct { present: bool, text: str }

type Finding = struct {
    id: Opt,
    tool: str,
    state: State,
    severity: Severity,
    rule: Opt,
    description: str,
    solution: Opt,
    justification: Opt,
    expires: Opt,
    detection_time: str,
    last_update: str,
}

type Reported = struct {
    resource: str,
    tool: str,
    rule: str,
    severity: Severity,
    description: str,
    solution: Opt,
}

fn some(text: str) -> Opt { ret Opt { present: true, text: text } }

fn none() -> Opt { ret Opt { present: false, text: "" } }

// The tool name without the version in parentheses: "checkov (3.2)" is "checkov".
fn tool_key(tool: str) -> str {
    var end = tool.len
    var i = 0usize
    while i + 1usize < tool.len {
        if tool[i] == 32u8 && tool[i + 1usize] == 40u8 {
            end = i
            i = tool.len
        } else {
            i += 1usize
        }
    }
    var start = 0usize
    while start < end && tool[start] >= 9u8 && (tool[start] <= 13u8 || tool[start] == 32u8) { start += 1usize }
    while end > start && (tool[end - 1usize] == 32u8 || (tool[end - 1usize] >= 9u8 && tool[end - 1usize] <= 13u8)) { end -= 1usize }
    ret tool[start..end]
}

fn fnv_step(hash: u64, byte: u8) -> u64 {
    ret (hash ^ u64(byte)) *% 1099511628211u64
}

fn hex_digit(nibble: u64) -> u8 {
    if nibble < 10u64 { ret u8(48u64 + nibble) }
    ret u8(87u64 + nibble)
}

// FNV-1a 64 of the parts joined by `|`, as 16 lowercase hex digits.
fn stable_id(a: *mem.Arena, parts: []const str) -> (str, err) {
    var hash = 14695981039346656037u64
    var p = 0usize
    while p < parts.len {
        if p > 0usize { hash = fnv_step(hash, 124u8) }
        var i = 0usize
        while i < parts[p].len {
            hash = fnv_step(hash, parts[p][i])
            i += 1usize
        }
        p += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, 16usize)
    if out_error != ok { ret ("", out_error) }
    var k = 0usize
    while k < 16usize {
        out[k] = hex_digit((hash >> u64((15usize - k) * 4usize)) & 15u64)
        k += 1usize
    }
    ret (out, ok)
}

// The id of a reported finding: resource, tool without its version, and rule.
fn finding_id(a: *mem.Arena, resource: str, tool: str, rule: str) -> (str, err) {
    var parts: [3]str = zero
    parts[0usize] = resource
    parts[1usize] = tool_key(tool)
    parts[2usize] = rule
    let (id, id_error) = stable_id(a, parts[0..])
    ret (id, id_error)
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn has_prefix(text: str, prefix: str) -> bool {
    if prefix.len > text.len { ret false }
    var i = 0usize
    while i < prefix.len {
        if text[i] != prefix[i] { ret false }
        i += 1usize
    }
    ret true
}

fn compare(left: str, right: str) -> i32 {
    var i = 0usize
    while i < left.len && i < right.len {
        if left[i] != right[i] {
            if left[i] < right[i] { ret -1i32 }
            ret 1i32
        }
        i += 1usize
    }
    if left.len < right.len { ret -1i32 }
    if left.len > right.len { ret 1i32 }
    ret 0i32
}

// Order by (tool, rule or "", description).
fn before(x: Finding, y: Finding) -> bool {
    let tool_order = compare(x.tool, y.tool)
    if tool_order != 0i32 { ret tool_order < 0i32 }
    var x_rule = ""
    if x.rule.present { x_rule = x.rule.text }
    var y_rule = ""
    if y.rule.present { y_rule = y.rule.text }
    let rule_order = compare(x_rule, y_rule)
    if rule_order != 0i32 { ret rule_order < 0i32 }
    ret compare(x.description, y.description) < 0i32
}

// The index of the last recorded finding whose id equals `id`, or `existing.len`.
fn find_by_id(existing: []const Finding, id: str) -> usize {
    var found = existing.len
    var i = 0usize
    while i < existing.len {
        if existing[i].id.present && same(existing[i].id.text, id) { found = i }
        i += 1usize
    }
    ret found
}

// Merge a scanner's report for resource `base` into the recorded findings. `owner_tool` is the scanner whose
// disappearing findings count as fixed.
fn merge(a: *mem.Arena, base: str, existing: []const Finding, reported: []const Reported, now: str, owner_tool: str) -> ([]const Finding, err) {
    var none_list: []const Finding = zero
    let capacity = existing.len + reported.len
    if capacity == 0usize { ret (none_list, ok) }
    let (out, out_error) = mem.alloc[Finding](a, capacity)
    if out_error != ok { ret (none_list, out_error) }
    let (ids, ids_error) = mem.alloc[str](a, reported.len + 1usize)
    if ids_error != ok { ret (none_list, ids_error) }
    var n = 0usize
    var r = 0usize
    while r < reported.len {
        let (id, id_error) = finding_id(a, base, reported[r].tool, reported[r].rule)
        if id_error != ok { ret (none_list, id_error) }
        ids[r] = id
        let at = find_by_id(existing, id)
        if at < existing.len {
            let prev = existing[at]
            let changed = !same(prev.description, reported[r].description) || prev.severity != reported[r].severity
            var solution = reported[r].solution
            if prev.solution.present { solution = prev.solution }
            var updated = prev.last_update
            if changed { updated = now }
            out[n] = Finding {
                id: some(id),
                tool: reported[r].tool,
                state: prev.state,
                severity: reported[r].severity,
                rule: some(reported[r].rule),
                description: reported[r].description,
                solution: solution,
                justification: prev.justification,
                expires: prev.expires,
                detection_time: prev.detection_time,
                last_update: updated,
            }
        } else {
            out[n] = Finding {
                id: some(id),
                tool: reported[r].tool,
                state: .Open,
                severity: reported[r].severity,
                rule: some(reported[r].rule),
                description: reported[r].description,
                solution: reported[r].solution,
                justification: none(),
                expires: none(),
                detection_time: now,
                last_update: now,
            }
        }
        n += 1usize
        r += 1usize
    }
    var e = 0usize
    while e < existing.len {
        var emitted = false
        var gone = false
        if existing[e].id.present {
            var k = 0usize
            while k < reported.len {
                if same(ids[k], existing[e].id.text) { emitted = true }
                k += 1usize
            }
            gone = !emitted && has_prefix(existing[e].tool, owner_tool) && existing[e].state == .Open
        }
        if !emitted {
            if gone {
                var fixed = existing[e]
                fixed.state = .Fixed
                fixed.last_update = now
                if !fixed.solution.present { fixed.solution = some("no longer reported") }
                out[n] = fixed
            } else {
                out[n] = existing[e]
            }
            n += 1usize
        }
        e += 1usize
    }
    // Stable insertion sort by (tool, rule, description).
    var i = 1usize
    while i < n {
        let value = out[i]
        var k = i
        while k > 0usize && before(value, out[k - 1usize]) {
            out[k] = out[k - 1usize]
            k -= 1usize
        }
        out[k] = value
        i += 1usize
    }
    ret (out[0usize..n], ok)
}
