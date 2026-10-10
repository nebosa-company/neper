// The durable run journal (L036, the runtime half), after appdor's `src/workflow/journal.js`: a run is a header and an
// append-only list of entries, both plain JSON, and nothing else has to survive a process dying -- a worker replays the
// journal and resumes from the step after the last committed entry, because the journal is the program counter. Every
// non-deterministic value (a clock reading) is recorded on the first pass and read back on every replay.
//
// A commit is one atomic write of new entries and a header patch guarded by `expected_seq`, the optimistic lock: two
// workers that pick up one suspended run both build a commit, exactly one lands and the other gets `stale-write`.
// `apply_commit` returns a new run, never changes the one it was given, and refuses an out-of-order sequence or a status
// change on a finished run. `Store` is the in-memory reference of the contract a real store satisfies (unique change,
// batch and schedule-occurrence keys per workflow, load, commit, due, list).
//
// Runs, entries, commits and patches are `e.fmt.json` values, as appdor's are plain objects: the JavaScript spread and
// `??`/`||` rules the reference relies on are reproduced exactly (`||` treats null, false, 0 and "" as absent, `??` only
// null and a missing member), and `rev`, the workflow version stamped on every entry, is written last so a caller cannot
// supply one. Numbers are the lexemes they arrived as; sequence arithmetic is integer.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

error UnknownEntryType
error NotAnObject
error NotANumber

type Obj = list.List[json.Member]

type Commit = struct { base_seq: usize, workflow_version: json.Value, entries: list.List[json.Value], patch: Obj }

// The outcome of applying a commit: `run` when `ok`, otherwise `failure`, appdor's `{ok:false, reason, ...}` object.
type Applied = struct { landed: bool, run: json.Value, failure: json.Value }

type Store = struct { a: *mem.Arena, prefix: str, counter: usize, runs: list.List[json.Value] }

fn entry_type_known(name: str) -> bool {
    ret str.eq(name, "run-started") || str.eq(name, "step-started") || str.eq(name, "step-completed") || str.eq(name, "step-failed") || str.eq(name, "step-skipped") || str.eq(name, "branch-taken") || str.eq(name, "loop-started") || str.eq(name, "fork-started") || str.eq(name, "fork-branch-completed") || str.eq(name, "timer-set") || str.eq(name, "timer-fired") || str.eq(name, "signal-awaited") || str.eq(name, "signal-received") || str.eq(name, "clock") || str.eq(name, "random") || str.eq(name, "var-set") || str.eq(name, "effect-recorded") || str.eq(name, "run-paused") || str.eq(name, "run-resumed") || str.eq(name, "run-cancelled") || str.eq(name, "run-completed") || str.eq(name, "run-failed") || str.eq(name, "run-retried")
}

fn is_terminal(status: str) -> bool {
    ret str.eq(status, "succeeded") || str.eq(status, "failed") || str.eq(status, "cancelled")
}

// --- values ---------------------------------------------------------------------------------------------------------

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn flag(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn members_of(v: json.Value) -> ([]const json.Member, bool) {
    var found = false
    var members: []const json.Member = zero
    switch v {
    case .Object as m:
        members = m
        found = true
    default:
        found = false
    }
    ret (members, found)
}

fn items_of(v: json.Value) -> ([]const json.Value, bool) {
    var found = false
    var items: []const json.Value = zero
    switch v {
    case .Array as xs:
        items = xs
        found = true
    default:
        found = false
    }
    ret (items, found)
}

fn string_of(v: json.Value) -> (str, bool) {
    var found = false
    var s = ""
    switch v {
    case .String as t:
        s = t
        found = true
    default:
        found = false
    }
    ret (s, found)
}

fn is_null(v: json.Value) -> bool {
    var yes = false
    switch v {
    case .Null:
        yes = true
    default:
        yes = false
    }
    ret yes
}

// JavaScript truthiness of a JSON value: null, false, 0 (any zero spelling) and "" are falsy.
fn truthy(v: json.Value) -> bool {
    var yes = true
    switch v {
    case .Null:
        yes = false
    case .Bool as b:
        yes = b
    case .Number as n:
        var nonzero = false
        var at = 0usize
        while at < n.lexeme.len {
            let c = n.lexeme[at]
            if c >= 49u8 && c <= 57u8 { nonzero = true }
            at += 1usize
        }
        yes = nonzero
    case .String as s:
        yes = s.len > 0usize
    default:
        yes = true
    }
    ret yes
}

fn get(v: json.Value, key: str) -> (json.Value, bool) {
    let (members, is_object) = members_of(v)
    if !is_object { ret (.Null, false) }
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, key) { ret (members[at].value, true) }
        at += 1usize
    }
    ret (.Null, false)
}

// `v[key] ?? fallback`: absent and null alike take the fallback.
fn get_or(v: json.Value, key: str, fallback: json.Value) -> json.Value {
    let (x, found) = get(v, key)
    if !found || is_null(x) { ret fallback }
    ret x
}

// `v[key] || fallback`.
fn get_or_falsy(v: json.Value, key: str, fallback: json.Value) -> json.Value {
    let (x, found) = get(v, key)
    if !found || !truthy(x) { ret fallback }
    ret x
}

fn new_obj(a: *mem.Arena) -> (Obj, err) {
    let (o, o_error) = list.init[json.Member](a, 8usize)
    ret (o, o_error)
}

// A member assignment: an existing key keeps its place and takes the value, a new one is appended.
fn put(o: *Obj, key: str, value: json.Value) -> err {
    var at = 0usize
    while at < o.len {
        if str.eq(o.items[at].key, key) {
            o.items[at].value = value
            ret ok
        }
        at += 1usize
    }
    ret list.push[json.Member](o, json.Member { key: key, value: value })
}

fn obj_value(o: *const Obj) -> json.Value { ret json.Value{ Object: list.slice_const[json.Member](o) } }

// `Object.assign(target, source)`: every member of `source` put into `target`.
fn assign(o: *Obj, source: json.Value) -> err {
    let (members, is_object) = members_of(source)
    if !is_object { ret ok }
    var at = 0usize
    while at < members.len {
        try put(o, members[at].key, members[at].value)
        at += 1usize
    }
    ret ok
}

fn from_value(a: *mem.Arena, v: json.Value) -> (Obj, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (o, o_error) }
    var out = o
    let assigned = assign(&out, v)
    ret (out, assigned)
}

// A non-negative integer lexeme as a count.
fn count_of(v: json.Value) -> (usize, bool) {
    var value = 0usize
    var good = false
    switch v {
    case .Number as n:
        good = n.lexeme.len > 0usize && n.lexeme.len < 19usize
        var at = 0usize
        while at < n.lexeme.len {
            if n.lexeme[at] < 48u8 || n.lexeme[at] > 57u8 {
                good = false
            } else {
                value = value * 10usize + usize(n.lexeme[at] - 48u8)
            }
            at += 1usize
        }
    default:
        good = false
    }
    ret (value, good)
}

fn number_value(a: *mem.Arena, n: usize) -> (json.Value, err) {
    let (number, number_error) = json.number_from_u64(a, u64(n))
    if number_error != ok { ret (.Null, number_error) }
    ret (json.Value{ Number: number }, ok)
}

// Strict equality of two scalar JSON values (`===`): same kind and same content; containers are never equal.
fn same_scalar(x: json.Value, y: json.Value) -> bool {
    var same = false
    switch x {
    case .Null:
        same = is_null(y)
    case .Bool as p:
        switch y {
        case .Bool as q:
            same = p == q
        default:
            same = false
        }
    case .Number as p:
        switch y {
        case .Number as q:
            same = str.eq(p.lexeme, q.lexeme)
        default:
            same = false
        }
    case .String as p:
        switch y {
        case .String as q:
            same = str.eq(p, q)
        default:
            same = false
        }
    default:
        same = false
    }
    ret same
}

// --- runs -----------------------------------------------------------------------------------------------------------

// A fresh run header over a workflow, a trigger and options, in appdor's member order.
fn create_run(a: *mem.Arena, workflow: json.Value, trigger: json.Value, options: json.Value) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var run = o
    try put(&run, "runId", get_or_falsy(options, "runId", .Null))
    try put(&run, "workflowId", get_or_falsy(workflow, "id", .Null))
    try put(&run, "workflowVersion", get_or(workflow, "version", json.Value{ Number: json.Number{ lexeme: "1" } }))
    try put(&run, "tableId", get_or(options, "tableId", .Null))
    try put(&run, "applicationId", get_or(options, "applicationId", .Null))
    try put(&run, "createdBy", get_or(options, "createdBy", .Null))
    try put(&run, "changeId", get_or(options, "changeId", .Null))
    try put(&run, "batchId", get_or(options, "batchId", .Null))
    try put(&run, "scheduleOccurrence", get_or(options, "scheduleOccurrence", .Null))
    try put(&run, "status", text("pending"))
    let (defer_value, have_defer) = get(options, "defer")
    var deferred = false
    if have_defer {
        switch defer_value {
        case .Bool as b:
            deferred = b
        default:
            deferred = false
        }
    }
    try put(&run, "deferred", flag(deferred))
    try put(&run, "seq", json.Value{ Number: json.Number{ lexeme: "0" } })
    try put(&run, "startedAt", get_or(options, "now", .Null))
    try put(&run, "finishedAt", .Null)
    let (trigger_object, trigger_error) = new_obj(a)
    if trigger_error != ok { ret (.Null, trigger_error) }
    var t = trigger_object
    let (workflow_trigger, have_workflow_trigger) = get(workflow, "trigger")
    var trigger_type = text("manual")
    if have_workflow_trigger && truthy(workflow_trigger) {
        let (type_value, have_type) = get(workflow_trigger, "type")
        if have_type && truthy(type_value) { trigger_type = type_value }
    }
    try put(&t, "type", trigger_type)
    let empty_a: []const json.Member = zero
    try put(&t, "payload", get_or_falsy(trigger, "payload", json.Value{ Object: empty_a }))
    try put(&t, "meta", get_or_falsy(trigger, "meta", json.Value{ Object: empty_a }))
    try put(&run, "trigger", obj_value(&t))
    try put(&run, "input", get_or_falsy(trigger, "input", json.Value{ Object: empty_a }))
    try put(&run, "waiting", .Null)
    try put(&run, "error", .Null)
    let (mode_value, have_mode) = get(options, "mode")
    var dry = false
    if have_mode {
        let (mode_text, mode_is_text) = string_of(mode_value)
        dry = mode_is_text && str.eq(mode_text, "dry-run")
    }
    try put(&run, "mode", text(choose(dry, "dry-run", "live")))
    try put(&run, "metered", json.Value{ Number: json.Number{ lexeme: "0" } })
    let empty_entries: []const json.Value = zero
    try put(&run, "entries", json.Value{ Array: empty_entries })
    ret (obj_value(&run), ok)
}

fn choose(c: bool, yes: str, no: str) -> str {
    if c { ret yes }
    ret no
}

fn entries_of(run: json.Value) -> []const json.Value {
    let (v, found) = get(run, "entries")
    let none: []const json.Value = zero
    if !found { ret none }
    let (items, is_array) = items_of(v)
    if !is_array { ret none }
    ret items
}

fn entry_type(e: json.Value) -> str {
    let (v, found) = get(e, "type")
    if !found { ret "" }
    let (s, is_text) = string_of(v)
    if !is_text { ret "" }
    ret s
}

// An entry's `key` as text, or "" and false when it has none.
fn entry_key(e: json.Value) -> (str, bool) {
    let (v, found) = get(e, "key")
    if !found { ret ("", false) }
    let (t, is_text) = string_of(v)
    ret (t, is_text)
}

fn key_is(e: json.Value, key: str) -> bool {
    let (k, has_key) = entry_key(e)
    ret has_key && str.eq(k, key)
}

// --- index queries --------------------------------------------------------------------------------------------------

// The last entry of `kind` for `key`, honouring appdor's Map semantics (a later entry replaces an earlier one).
fn last_entry(run: json.Value, kind: str, key: str) -> (json.Value, bool) {
    let entries = entries_of(run)
    var found = false
    var out: json.Value = .Null
    var at = 0usize
    while at < entries.len {
        if str.eq(entry_type(entries[at]), kind) && key_is(entries[at], key) {
            out = entries[at]
            found = true
        }
        at += 1usize
    }
    ret (out, found)
}

// The recorded result of a completed execution; absent when none completed or the entry has no `result`.
fn result(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_entry(run, "step-completed", key)
    if !found { ret (.Null, false) }
    let (r, has_result) = get(e, "result")
    ret (r, has_result)
}

fn is_complete(run: json.Value, key: str) -> bool {
    let (e, found) = last_entry(run, "step-completed", key)
    ret found
}

fn skipped(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_entry(run, "step-skipped", key)
    ret (e, found)
}

fn started(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_entry(run, "step-started", key)
    ret (e, found)
}

fn branch(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_entry(run, "branch-taken", key)
    ret (e, found)
}

fn loop_entry(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_entry(run, "loop-started", key)
    ret (e, found)
}

fn signal(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_entry(run, "signal-received", key)
    ret (e, found)
}

fn has_signal(run: json.Value, key: str) -> bool {
    let (e, found) = last_entry(run, "signal-received", key)
    ret found
}

fn timer_fired(run: json.Value, key: str) -> bool {
    let (e, found) = last_entry(run, "timer-fired", key)
    ret found
}

// A clock or random entry for the key: the later of the two kinds wins, as in appdor's one Map.
fn last_recorded(run: json.Value, key: str) -> (json.Value, bool) {
    let entries = entries_of(run)
    var found = false
    var out: json.Value = .Null
    var at = 0usize
    while at < entries.len {
        let kind = entry_type(entries[at])
        if (str.eq(kind, "clock") || str.eq(kind, "random")) && key_is(entries[at], key) {
            out = entries[at]
            found = true
        }
        at += 1usize
    }
    ret (out, found)
}

fn has_recorded(run: json.Value, key: str) -> bool {
    let (e, found) = last_recorded(run, key)
    ret found
}

// The recorded value; absent when nothing was recorded or the entry carries no `value`.
fn recorded(run: json.Value, key: str) -> (json.Value, bool) {
    let (e, found) = last_recorded(run, key)
    if !found { ret (.Null, false) }
    let (v, has_value) = get(e, "value")
    ret (v, has_value)
}

// The step-failed entries for a key since the last `run-retried`, which renews the attempt budget.
fn failures(run: json.Value, key: str) -> (usize, json.Value) {
    let entries = entries_of(run)
    var count = 0usize
    var last: json.Value = .Null
    var at = 0usize
    while at < entries.len {
        let kind = entry_type(entries[at])
        if str.eq(kind, "run-retried") {
            count = 0usize
            last = .Null
        } else if str.eq(kind, "step-failed") && key_is(entries[at], key) {
            count += 1usize
            last = entries[at]
        }
        at += 1usize
    }
    ret (count, last)
}

fn failure_count(run: json.Value, key: str) -> usize {
    let (count, last) = failures(run, key)
    ret count
}

fn last_failure(run: json.Value, key: str) -> (json.Value, bool) {
    let (count, last) = failures(run, key)
    ret (last, count > 0usize)
}

// The branch names a fork has completed, in the order they first completed. The key is the entry's `key`, or its
// `stepId` when it has none.
fn fork_branches(a: *mem.Arena, run: json.Value, key: str) -> ([]const json.Value, err) {
    let entries = entries_of(run)
    let (out, out_error) = list.init[json.Value](a, 4usize)
    if out_error != ok { ret (zero, out_error) }
    var names = out
    var at = 0usize
    while at < entries.len {
        if str.eq(entry_type(entries[at]), "fork-branch-completed") {
            let (k, has_key) = entry_key(entries[at])
            var matches = false
            if has_key {
                matches = str.eq(k, key)
            } else {
                let (step_id, have_step) = get(entries[at], "stepId")
                let (step_text, step_is_text) = string_of(step_id)
                matches = have_step && step_is_text && str.eq(step_text, key)
            }
            if matches {
                let (name, have_name) = get(entries[at], "branch")
                var seen = false
                var s = 0usize
                while s < names.len {
                    if same_scalar(names.items[s], name) { seen = true }
                    s += 1usize
                }
                if !seen {
                    var value = name
                    if !have_name { value = .Null }
                    try list.push[json.Value](&names, value)
                }
            }
        }
        at += 1usize
    }
    ret (list.slice_const[json.Value](&names), ok)
}

fn size(run: json.Value) -> usize { ret entries_of(run).len }

// --- commits --------------------------------------------------------------------------------------------------------

fn begin_commit(a: *mem.Arena, run: json.Value) -> (Commit, err) {
    let (seq_value, have_seq) = get(run, "seq")
    let (seq, seq_ok) = count_of(seq_value)
    if !have_seq || !seq_ok { ret (zero, NotANumber) }
    let (entries, entries_error) = list.init[json.Value](a, 8usize)
    if entries_error != ok { ret (zero, entries_error) }
    let (patch, patch_error) = new_obj(a)
    if patch_error != ok { ret (zero, patch_error) }
    ret (Commit { base_seq: seq, workflow_version: get_or(run, "workflowVersion", .Null), entries: entries, patch: patch }, ok)
}

fn is_empty(c: *const Commit) -> bool { ret c.entries.len == 0usize && c.patch.len == 0usize }

// `commit.add(type, fields)`: the entry `{seq, type, ...fields, rev}`; an unknown type is refused.
fn add(a: *mem.Arena, c: *Commit, kind: str, fields: json.Value) -> err {
    if !entry_type_known(kind) { ret UnknownEntryType }
    let (seq_value, seq_error) = number_value(a, c.base_seq + c.entries.len + 1usize)
    if seq_error != ok { ret seq_error }
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret o_error }
    var entry = o
    try put(&entry, "seq", seq_value)
    try put(&entry, "type", text(kind))
    try assign(&entry, fields)
    try put(&entry, "rev", c.workflow_version)
    ret list.push[json.Value](&c.entries, obj_value(&entry))
}

// `commit.setHeader(fields)`.
fn set_header(c: *Commit, fields: json.Value) -> err { ret assign(&c.patch, fields) }

// Re-number the buffered entries after an earlier write moved the run to `next_seq`.
fn rebase(a: *mem.Arena, c: *Commit, next_seq: usize) -> err {
    c.base_seq = next_seq
    var at = 0usize
    while at < c.entries.len {
        let (seq_value, seq_error) = number_value(a, next_seq + at + 1usize)
        if seq_error != ok { ret seq_error }
        let (o, o_error) = from_value(a, c.entries.items[at])
        if o_error != ok { ret o_error }
        var entry = o
        try put(&entry, "seq", seq_value)
        c.entries.items[at] = obj_value(&entry)
        at += 1usize
    }
    ret ok
}

// `commit.build()`: `{expectedSeq, entries, patch}`.
fn build(a: *mem.Arena, c: *const Commit) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    let (expected, expected_error) = number_value(a, c.base_seq)
    if expected_error != ok { ret (.Null, expected_error) }
    try put(&out, "expectedSeq", expected)
    try put(&out, "entries", json.Value{ Array: list.slice_const[json.Value](&c.entries) })
    try put(&out, "patch", obj_value(&c.patch))
    ret (obj_value(&out), ok)
}

fn failure(a: *mem.Arena, reason: str, detail_key: str, detail: json.Value, second_key: str, second: json.Value) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    try put(&out, "ok", flag(false))
    try put(&out, "reason", text(reason))
    if detail_key.len > 0usize { try put(&out, detail_key, detail) }
    if second_key.len > 0usize { try put(&out, second_key, second) }
    ret (obj_value(&out), ok)
}

// A commit against a run, with the checks a database constraint would make. The run it was given is not changed.
fn apply_commit(a: *mem.Arena, run: json.Value, commit: json.Value) -> (Applied, err) {
    let (expected_value, have_expected) = get(commit, "expectedSeq")
    let (run_seq_value, have_run_seq) = get(run, "seq")
    let (expected, expected_ok) = count_of(expected_value)
    let (run_seq, run_seq_ok) = count_of(run_seq_value)
    if !have_expected || !have_run_seq || !expected_ok || !run_seq_ok {
        let (f, f_error) = failure(a, "stale-write", "expected", expected_value, "actual", run_seq_value)
        ret (Applied { landed: false, run: .Null, failure: f }, f_error)
    }
    if expected != run_seq {
        let (f, f_error) = failure(a, "stale-write", "expected", expected_value, "actual", run_seq_value)
        ret (Applied { landed: false, run: .Null, failure: f }, f_error)
    }
    let (patch, have_patch) = get(commit, "patch")
    let (status_value, status_present) = get(run, "status")
    let (status_text, status_is_text) = string_of(status_value)
    let (patch_status, patch_has_status) = get(patch, "status")
    if status_present && status_is_text && is_terminal(status_text) && have_patch && patch_has_status && truthy(patch_status) {
        let (patch_text, patch_is_text) = string_of(patch_status)
        if !(patch_is_text && str.eq(patch_text, status_text)) {
            let (f, f_error) = failure(a, "run-already-finished", "", .Null, "", .Null)
            ret (Applied { landed: false, run: .Null, failure: f }, f_error)
        }
    }
    let (new_entries, entries_present) = get(commit, "entries")
    let (new_items, new_is_array) = items_of(new_entries)
    var seq = run_seq
    var at = 0usize
    if entries_present && new_is_array {
        while at < new_items.len {
            let (entry_seq_value, have_entry_seq) = get(new_items[at], "seq")
            let (entry_seq, entry_seq_ok) = count_of(entry_seq_value)
            if !have_entry_seq || !entry_seq_ok || entry_seq != seq + 1usize {
                let (f, f_error) = failure(a, "non-sequential-entry", "at", entry_seq_value, "", .Null)
                ret (Applied { landed: false, run: .Null, failure: f }, f_error)
            }
            seq = entry_seq
            at += 1usize
        }
    }
    let (o, o_error) = from_value(a, run)
    if o_error != ok { ret (zero, o_error) }
    var next = o
    if have_patch { try assign(&next, patch) }
    let (seq_number, seq_error) = number_value(a, seq)
    if seq_error != ok { ret (zero, seq_error) }
    try put(&next, "seq", seq_number)
    let old_entries = entries_of(run)
    let (merged, merged_error) = list.init[json.Value](a, old_entries.len + 1usize)
    if merged_error != ok { ret (zero, merged_error) }
    var all = merged
    var e = 0usize
    while e < old_entries.len {
        try list.push[json.Value](&all, old_entries[e])
        e += 1usize
    }
    if entries_present && new_is_array {
        e = 0usize
        while e < new_items.len {
            try list.push[json.Value](&all, new_items[e])
            e += 1usize
        }
    }
    try put(&next, "entries", json.Value{ Array: list.slice_const[json.Value](&all) })
    ret (Applied { landed: true, run: obj_value(&next), failure: .Null }, ok)
}

// Read a clock value that is the same on every replay: the recorded one, or the host's reading journaled now.
fn record_clock(a: *mem.Arena, run: json.Value, c: *Commit, key: str, host_now: json.Value) -> (json.Value, bool, err) {
    let (value, has_value) = recorded(run, key)
    if has_recorded(run, key) { ret (value, has_value, ok) }
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, false, o_error) }
    var fields = o
    try put(&fields, "key", text(key))
    try put(&fields, "value", host_now)
    let added = add(a, c, "clock", obj_value(&fields))
    ret (host_now, true, added)
}

// A list view of a run: the header's own members and counts, never the journal.
fn summarize_run(a: *mem.Arena, run: json.Value) -> (json.Value, err) {
    let entries = entries_of(run)
    var steps = 0usize
    var failed = 0usize
    var at = 0usize
    while at < entries.len {
        let kind = entry_type(entries[at])
        if str.eq(kind, "step-completed") { steps += 1usize }
        if str.eq(kind, "step-failed") { failed += 1usize }
        at += 1usize
    }
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    var names: [7]str = zero
    names[0] = "runId"
    names[1] = "workflowId"
    names[2] = "status"
    names[3] = "mode"
    names[4] = "startedAt"
    names[5] = "finishedAt"
    var n = 0usize
    while n < 6usize {
        let (v, found) = get(run, names[n])
        if found { try put(&out, names[n], v) }
        n += 1usize
    }
    let (started_at, have_started) = get(run, "startedAt")
    let (finished_at, have_finished) = get(run, "finishedAt")
    var duration: json.Value = .Null
    if have_started && have_finished && truthy(started_at) && truthy(finished_at) {
        let (start_f, start_error) = number_f64(started_at)
        let (end_f, end_error) = number_f64(finished_at)
        if start_error == ok && end_error == ok {
            let (made, made_error) = number_from_difference(a, end_f - start_f)
            if made_error != ok { ret (.Null, made_error) }
            duration = made
        }
    }
    try put(&out, "durationMs", duration)
    let (steps_value, steps_error) = number_value(a, steps)
    if steps_error != ok { ret (.Null, steps_error) }
    try put(&out, "stepsCompleted", steps_value)
    let (failed_value, failed_error) = number_value(a, failed)
    if failed_error != ok { ret (.Null, failed_error) }
    try put(&out, "stepsFailed", failed_value)
    let (waiting, have_waiting) = get(run, "waiting")
    var waiting_value: json.Value = .Null
    if have_waiting && truthy(waiting) {
        let (w, w_error) = new_obj(a)
        if w_error != ok { ret (.Null, w_error) }
        var summary = w
        let (kind, have_kind) = get(waiting, "kind")
        if have_kind { try put(&summary, "kind", kind) }
        try put(&summary, "wakeAt", get_or(waiting, "wakeAt", .Null))
        try put(&summary, "signal", get_or(waiting, "signal", .Null))
        waiting_value = obj_value(&summary)
    }
    try put(&out, "waiting", waiting_value)
    let (error_value, have_error) = get(run, "error")
    if have_error { try put(&out, "error", error_value) }
    let (count_value, count_error) = number_value(a, entries.len)
    if count_error != ok { ret (.Null, count_error) }
    try put(&out, "entryCount", count_value)
    ret (obj_value(&out), ok)
}

fn number_f64(v: json.Value) -> (f64, err) {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret (x, e)
    default:
        ret (0.0, NotANumber)
    }
}

// A difference of two timestamps as a JSON number: an integer when it is one.
fn number_from_difference(a: *mem.Arena, x: f64) -> (json.Value, err) {
    let (number, number_error) = json.number_from_f64(a, x)
    if number_error != ok { ret (.Null, number_error) }
    ret (json.Value{ Number: number }, ok)
}

// --- the in-memory store --------------------------------------------------------------------------------------------

fn new_store(a: *mem.Arena, prefix: str) -> (Store, err) {
    let (runs, runs_error) = list.init[json.Value](a, 8usize)
    if runs_error != ok { ret (zero, runs_error) }
    ret (Store { a: a, prefix: prefix, counter: 0usize, runs: runs }, ok)
}

fn run_id_of(run: json.Value) -> str {
    let (v, found) = get(run, "runId")
    if !found { ret "" }
    let (s, is_text) = string_of(v)
    if !is_text { ret "" }
    ret s
}

// A duplicate of another stored run of the same workflow in `field` (change, batch or schedule occurrence).
fn duplicate_in(s: *const Store, run: json.Value, field: str) -> bool {
    let (mine, have_mine) = get(run, field)
    if !have_mine || is_null(mine) { ret false }
    let (workflow, have_workflow) = get(run, "workflowId")
    var at = 0usize
    while at < s.runs.len {
        let existing = s.runs.items[at]
        let (theirs, have_theirs) = get(existing, field)
        let (their_workflow, have_their_workflow) = get(existing, "workflowId")
        let same_workflow = (have_workflow == have_their_workflow) && (!have_workflow || same_scalar(workflow, their_workflow))
        if same_workflow && have_theirs && same_scalar(theirs, mine) { ret true }
        at += 1usize
    }
    ret false
}

// `create`: the stored run (with its id), or null when a unique key collides.
fn store_create(s: *Store, run: json.Value) -> (json.Value, err) {
    if duplicate_in(s, run, "changeId") || duplicate_in(s, run, "batchId") || duplicate_in(s, run, "scheduleOccurrence") { ret (.Null, ok) }
    var id = ""
    let (given, have_given) = get(run, "runId")
    if have_given && truthy(given) {
        let (given_text, given_is_text) = string_of(given)
        if given_is_text { id = given_text }
    }
    if id.len == 0usize {
        s.counter += 1usize
        let (digits, digits_error) = number_value(s.a, s.counter)
        if digits_error != ok { ret (.Null, digits_error) }
        let (n, n_is_number) = number_text(digits)
        let (joined, join_error) = str.concat(s.a, s.prefix, "_")
        if join_error != ok { ret (.Null, join_error) }
        let (full, full_error) = str.concat(s.a, joined, n)
        if full_error != ok { ret (.Null, full_error) }
        id = full
    }
    let (o, o_error) = from_value(s.a, run)
    if o_error != ok { ret (.Null, o_error) }
    var stored = o
    try put(&stored, "runId", text(id))
    let value = obj_value(&stored)
    // A Map keyed by run id: an id already stored is replaced where it stands, never listed twice.
    let (at, found) = store_find(s, id)
    if found {
        s.runs.items[at] = value
        ret (value, ok)
    }
    try list.push[json.Value](&s.runs, value)
    ret (value, ok)
}

fn number_text(v: json.Value) -> (str, bool) {
    var out = ""
    var good = false
    switch v {
    case .Number as n:
        out = n.lexeme
        good = true
    default:
        good = false
    }
    ret (out, good)
}

fn store_find(s: *const Store, run_id: str) -> (usize, bool) {
    var at = 0usize
    while at < s.runs.len {
        if str.eq(run_id_of(s.runs.items[at]), run_id) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn store_load(s: *const Store, run_id: str) -> (json.Value, bool) {
    let (at, found) = store_find(s, run_id)
    if !found { ret (.Null, false) }
    ret (s.runs.items[at], true)
}

// `commit`: `{ok:true, run}` or `{ok:false, reason}`, the stored run replaced only on success.
fn store_commit(s: *Store, run_id: str, commit: json.Value) -> (json.Value, err) {
    let (at, found) = store_find(s, run_id)
    if !found {
        let (missing, missing_error) = failure(s.a, "no-such-run", "", .Null, "", .Null)
        ret (missing, missing_error)
    }
    let (applied, applied_error) = apply_commit(s.a, s.runs.items[at], commit)
    if applied_error != ok { ret (.Null, applied_error) }
    if !applied.landed { ret (applied.failure, ok) }
    s.runs.items[at] = applied.run
    let (o, o_error) = new_obj(s.a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    try put(&out, "ok", flag(true))
    try put(&out, "run", applied.run)
    ret (obj_value(&out), ok)
}

fn number_le(x: json.Value, y: json.Value) -> bool {
    let (p, p_error) = number_f64(x)
    let (q, q_error) = number_f64(y)
    ret p_error == ok && q_error == ok && p <= q
}

// Runs a scheduler should wake: suspended, parked on a timer that is due or a signal whose timeout is. Only the header
// is read. The limit check follows every suspended run that is parked, whether or not it was due.
fn store_due(s: *const Store, now: json.Value, limit: usize) -> ([]const json.Value, err) {
    let (out, out_error) = list.init[json.Value](s.a, 4usize)
    if out_error != ok { ret (zero, out_error) }
    var due = out
    var at = 0usize
    var stop = false
    while at < s.runs.len && !stop {
        let run = s.runs.items[at]
        let (status, have_status) = get(run, "status")
        let (status_text, status_is_text) = string_of(status)
        let (waiting, have_waiting) = get(run, "waiting")
        if have_status && status_is_text && str.eq(status_text, "suspended") && have_waiting && truthy(waiting) {
            let (kind, have_kind) = get(waiting, "kind")
            let (kind_text, kind_is_text) = string_of(kind)
            if have_kind && kind_is_text && str.eq(kind_text, "timer") {
                let (wake_at, have_wake) = get(waiting, "wakeAt")
                if have_wake && number_le(wake_at, now) { try list.push[json.Value](&due, run) }
            } else if have_kind && kind_is_text && str.eq(kind_text, "signal") {
                let (timeout_at, have_timeout) = get(waiting, "timeoutAt")
                if have_timeout && truthy(timeout_at) && number_le(timeout_at, now) { try list.push[json.Value](&due, run) }
            }
            if due.len >= limit { stop = true }
        }
        at += 1usize
    }
    ret (list.slice_const[json.Value](&due), ok)
}

fn store_list(s: *const Store) -> []const json.Value { ret list.slice_const[json.Value](&s.runs) }
