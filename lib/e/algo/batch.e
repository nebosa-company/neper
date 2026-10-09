// Batch operations and edit history (L033), after appdor's `src/grid-ops/{records-engine,bulk,undo-redo}.js`:
// a batch run in bounded chunks with a per-record outcome ledger that a killed job resumes from, the bulk mutation
// planner (every target authorized up front, the whole operation refused if any is denied unless asked to skip,
// chunked, sync or async by size, one correlation marker for every change) and its runner and report, and the
// per-editor per-table undo/redo stacks of cell and range edits with acknowledged-only settlement.
//
// Callbacks are function values taking a caller-owned state pointer, which is how the host's storage and
// authorization reach the engine. Messages are the catalogue's keys humanized ("bulkOps.nothingSelected" reads
// "Nothing selected") unless `Messages` supplies text, which is what appdor's reads with no bundle loaded.

use e.algo.formula as f
use e.algo.view as view
use e.math
use e.mem
use e.str

// --- messages -----------------------------------------------------------------------------------------------------

// A catalogue override: the key and the text with `{token}` placeholders.
type Message = struct { key: str, text: str }

// "bulkOps.refusedNotWritable" as "Refused not writable".
fn humanize_key(a: *mem.Arena, key: str) -> str {
    var from = 0usize
    var i = 0usize
    while i < key.len {
        if key[i] == 46u8 { from = i + 1usize }
        i += 1usize
    }
    let name = key[from..key.len]
    let (out, e) = mem.alloc[u8](a, name.len * 2usize + 1usize)
    if e != ok { ret name }
    var n = 0usize
    i = 0usize
    while i < name.len {
        var c = name[i]
        if c >= 65u8 && c <= 90u8 {
            if i > 0usize {
                out[n] = 32u8
                n += 1usize
            }
            c = c + 32u8
        }
        if n == 0usize && c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        out[n] = c
        n += 1usize
        i += 1usize
    }
    ret out[0usize..n]
}

// Replace each `{name}` of a template with the matching parameter's text.
fn fill(a: *mem.Arena, template: str, names: []const str, values: []const str) -> str {
    var out = ""
    var i = 0usize
    while i < template.len {
        if template[i] == 123u8 {
            var close = template.len
            var k = i + 1usize
            while k < template.len {
                if template[k] == 125u8 {
                    close = k
                    k = template.len
                } else {
                    k += 1usize
                }
            }
            if close < template.len {
                let key = template[i + 1usize..close]
                var filled = false
                var p = 0usize
                while p < names.len {
                    if str.eq(names[p], key) {
                        out = f.join(a, out, values[p])
                        filled = true
                    }
                    p += 1usize
                }
                if !filled { out = f.join(a, out, template[i..close + 1usize]) }
                i = close + 1usize
                continue
            }
        }
        out = f.join(a, out, template[i..i + 1usize])
        i += 1usize
    }
    ret out
}

fn message(a: *mem.Arena, catalog: []const Message, key: str, names: []const str, values: []const str) -> str {
    var i = 0usize
    while i < catalog.len {
        if str.eq(catalog[i].key, key) { ret fill(a, catalog[i].text, names, values) }
        i += 1usize
    }
    ret humanize_key(a, key)
}

fn no_names() -> []const str {
    var none: []const str = zero
    ret none
}

// --- the outcome ledger ---------------------------------------------------------------------------------------------

// What applying one record answered: success, or a failure with its reason (a thrown failure carries its message).
type Outcome = struct { good: bool, reason: str, has_reason: bool }

fn success() -> Outcome { ret Outcome { good: true, reason: "", has_reason: false } }

fn failure(reason: str) -> Outcome { ret Outcome { good: false, reason: reason, has_reason: reason.len > 0usize } }

type Failed = struct { record_id: f.Value, reason: str }

// The per-record record of a batch: which ids succeeded and which failed and why.
type Ledger = struct { succeeded: []const f.Value, failed: []const Failed }

type Apply = fn(*void, f.Value) -> Outcome

type BatchResult = struct {
    ledger: Ledger,
    processed: usize,
    total: usize,
    done: bool,
    next_index: usize,
    has_next_index: bool,
    succeeded: usize,
    failed: usize,
}

// Run one chunk of a batch: `chunk_size` (500 when 0) records from `start`, a failing record never stopping the
// run, the ledger carried over from an earlier chunk (pass the previous result's ledger to resume).
fn run_batch(a: *mem.Arena, ids: []const f.Value, apply: Apply, state: *void, chunk_size: usize, start: usize, ledger: Ledger) -> BatchResult {
    var size = chunk_size
    if size == 0usize { size = 500usize }
    var end = start + size
    if end > ids.len { end = ids.len }
    var from = start
    if from > ids.len { from = ids.len }
    let (succeeded, se) = mem.alloc[f.Value](a, ledger.succeeded.len + ids.len + 1usize)
    let (failed, fe) = mem.alloc[Failed](a, ledger.failed.len + ids.len + 1usize)
    var no_values: []const f.Value = zero
    var no_failed: []const Failed = zero
    if se != ok || fe != ok {
        ret BatchResult { ledger: ledger, processed: 0usize, total: ids.len, done: false, next_index: from, has_next_index: true, succeeded: 0usize, failed: 0usize }
    }
    var sn = 0usize
    var i = 0usize
    while i < ledger.succeeded.len {
        succeeded[sn] = ledger.succeeded[i]
        sn += 1usize
        i += 1usize
    }
    var fn_count = 0usize
    i = 0usize
    while i < ledger.failed.len {
        failed[fn_count] = ledger.failed[i]
        fn_count += 1usize
        i += 1usize
    }
    i = from
    while i < end {
        let outcome = apply(state, ids[i])
        if outcome.good {
            succeeded[sn] = ids[i]
            sn += 1usize
        } else {
            var reason = outcome.reason
            if reason.len == 0usize { reason = "failed" }
            failed[fn_count] = Failed { record_id: ids[i], reason: reason }
            fn_count += 1usize
        }
        i += 1usize
    }
    let done = end >= ids.len
    var next = 0usize
    if !done { next = end }
    ret BatchResult {
        ledger: Ledger { succeeded: succeeded[0usize..sn], failed: failed[0usize..fn_count] },
        processed: sn + fn_count,
        total: ids.len,
        done: done,
        next_index: next,
        has_next_index: !done,
        succeeded: sn,
        failed: fn_count,
    }
}

// The line a toast reads: "N of M records updated" with the failures when there are any.
fn describe_batch(a: *mem.Arena, total: usize, succeeded: usize, failed: usize) -> str {
    let head = f.join(a, f.join(a, f.number_text(a, f64(succeeded)), " of "), f.join(a, f.number_text(a, f64(total)), " records updated"))
    if failed == 0usize { ret f.join(a, head, ".") }
    ret f.join(a, f.join3(a, head, "; ", f.number_text(a, f64(failed))), " failed.")
}

// --- bulk mutation ------------------------------------------------------------------------------------------------

// Above this many targets the work is a job rather than an inline edit.
fn sync_threshold() -> usize { ret 200usize }

fn default_chunk_size() -> usize { ret 500usize }

// The answer of an authorization check for one target.
type Verdict = struct { allowed: bool, reason: str }

type Authorize = fn(*void, f.Value) -> Verdict

type Denied = struct { id: f.Value, reason: str }

type BulkPlan = struct {
    valid: bool,
    reason: str,
    denied: []const Denied,
    correlation_id: str,
    patch: []const f.Field,
    total: usize,
    skipped: []const Denied,
    chunks: []const []const f.Value,
    mode: str,
}

fn plan_refusal(why: str) -> BulkPlan {
    var none_denied: []const Denied = zero
    var none_fields: []const f.Field = zero
    var none_chunks: []const []const f.Value = zero
    ret BulkPlan { valid: false, reason: why, denied: none_denied, correlation_id: "", patch: none_fields, total: 0usize, skipped: none_denied, chunks: none_chunks, mode: "" }
}

// Plan a bulk mutation: authorize every target up front, refuse the whole operation if any is denied (or drop the
// denied ones when `skip_denied`), cut the rest into chunks and decide sync or async by size.
fn plan_bulk_mutation(a: *mem.Arena, catalog: []const Message, targets: []const f.Value, patch: []const f.Field, authorize: Authorize, has_authorize: bool, state: *void, skip_denied: bool, chunk_size: usize, threshold: usize, has_threshold: bool, correlation_id: str) -> BulkPlan {
    if targets.len == 0usize { ret plan_refusal(message(a, catalog, "bulkOps.nothingSelected", no_names(), no_names())) }
    if patch.len == 0usize { ret plan_refusal(message(a, catalog, "bulkOps.noChangeRequested", no_names(), no_names())) }
    var size = chunk_size
    if size == 0usize { size = default_chunk_size() }
    var limit = sync_threshold()
    if has_threshold { limit = threshold }
    let (allowed, ae) = mem.alloc[f.Value](a, targets.len + 1usize)
    let (denied, de) = mem.alloc[Denied](a, targets.len + 1usize)
    if ae != ok || de != ok { ret plan_refusal("out-of-memory") }
    var an = 0usize
    var dn = 0usize
    var i = 0usize
    while i < targets.len {
        if !has_authorize {
            allowed[an] = targets[i]
            an += 1usize
        } else {
            let verdict = authorize(state, targets[i])
            if verdict.allowed {
                allowed[an] = targets[i]
                an += 1usize
            } else {
                var reason = verdict.reason
                if reason.len == 0usize { reason = message(a, catalog, "bulkOps.notAuthorized", no_names(), no_names()) }
                denied[dn] = Denied { id: targets[i], reason: reason }
                dn += 1usize
            }
        }
        i += 1usize
    }
    if dn > 0usize && !skip_denied {
        var names: [2]str = zero
        var values: [2]str = zero
        names[0usize] = "denied"
        names[1usize] = "total"
        values[0usize] = f.number_text(a, f64(dn))
        values[1usize] = f.number_text(a, f64(targets.len))
        var refused = plan_refusal(message(a, catalog, "bulkOps.refusedNotWritable", names[0..], values[0..]))
        refused.denied = denied[0usize..dn]
        ret refused
    }
    let chunk_count = (an + size - 1usize) / size
    let (chunks, ce) = mem.alloc[[]const f.Value](a, chunk_count + 1usize)
    if ce != ok { ret plan_refusal("out-of-memory") }
    var c = 0usize
    while c < chunk_count {
        var lo = c * size
        var hi = lo + size
        if hi > an { hi = an }
        chunks[c] = allowed[lo..hi]
        c += 1usize
    }
    var mode = "sync"
    if an > limit { mode = "async" }
    var id = correlation_id
    if id.len == 0usize { id = "bulk:unspecified" }
    var none_denied: []const Denied = zero
    var skipped = none_denied
    if skip_denied { skipped = denied[0usize..dn] }
    ret BulkPlan { valid: true, reason: "", denied: none_denied, correlation_id: id, patch: patch, total: an, skipped: skipped, chunks: chunks[0usize..chunk_count], mode: mode }
}

// What applying one chunk answered: every id succeeded (`all_ok`), or one outcome per id it names, or it threw.
type IdOutcome = struct { id: f.Value, good: bool, reason: str }

type Applied = struct { threw: bool, reason: str, all_ok: bool, results: []const IdOutcome }

type BulkApply = fn(*void, []const f.Value, []const f.Field, str) -> Applied

type Cancelled = fn(*void) -> bool

type Progress = struct { done: usize, total: usize, applied: usize, failed: usize, percent: f64 }

type BulkResult = struct {
    valid: bool,
    reason: str,
    cancelled: bool,
    correlation_id: str,
    total: usize,
    applied: usize,
    failed: usize,
    outcomes: []const IdOutcome,
    progress: []const Progress,
}

// Execute a plan chunk by chunk with a per-record outcome and a progress event after each chunk. `valid` means the
// operation ran to the end (or was cancelled cleanly), not that every record succeeded.
fn run_bulk_mutation(a: *mem.Arena, plan: BulkPlan, apply: BulkApply, state: *void, is_cancelled: Cancelled, has_cancel: bool) -> BulkResult {
    var none_outcomes: []const IdOutcome = zero
    var none_progress: []const Progress = zero
    if !plan.valid {
        var reason = plan.reason
        if reason.len == 0usize { reason = "no-plan" }
        ret BulkResult { valid: false, reason: reason, cancelled: false, correlation_id: "", total: 0usize, applied: 0usize, failed: 0usize, outcomes: none_outcomes, progress: none_progress }
    }
    var capacity = 0usize
    var i = 0usize
    while i < plan.chunks.len {
        capacity += plan.chunks[i].len
        i += 1usize
    }
    let (outcomes, oe) = mem.alloc[IdOutcome](a, capacity + 1usize)
    let (events, ee) = mem.alloc[Progress](a, plan.chunks.len + 1usize)
    if oe != ok || ee != ok {
        ret BulkResult { valid: false, reason: "out-of-memory", cancelled: false, correlation_id: plan.correlation_id, total: plan.total, applied: 0usize, failed: 0usize, outcomes: none_outcomes, progress: none_progress }
    }
    var on = 0usize
    var en = 0usize
    var applied = 0usize
    var failed = 0usize
    var done = 0usize
    var cancelled = false
    var c = 0usize
    while c < plan.chunks.len && !cancelled {
        if has_cancel && is_cancelled(state) {
            cancelled = true
        } else {
            let chunk = plan.chunks[c]
            let result = apply(state, chunk, plan.patch, plan.correlation_id)
            if result.threw {
                var reason = result.reason
                if reason.len == 0usize { reason = "apply-threw" }
                var k = 0usize
                while k < chunk.len {
                    outcomes[on] = IdOutcome { id: chunk[k], good: false, reason: reason }
                    on += 1usize
                    failed += 1usize
                    k += 1usize
                }
            } else if result.all_ok {
                var k = 0usize
                while k < chunk.len {
                    outcomes[on] = IdOutcome { id: chunk[k], good: true, reason: "" }
                    on += 1usize
                    applied += 1usize
                    k += 1usize
                }
            } else {
                var k = 0usize
                while k < result.results.len && on < outcomes.len {
                    var row = result.results[k]
                    if row.good {
                        row.reason = ""
                        applied += 1usize
                    } else {
                        if row.reason.len == 0usize { row.reason = "failed" }
                        failed += 1usize
                    }
                    outcomes[on] = row
                    on += 1usize
                    k += 1usize
                }
            }
            done += chunk.len
            var percent = 100.0f64
            if plan.total > 0usize { percent = math.floor[f64](f64(done) / f64(plan.total) * 100.0f64 + 0.5f64) }
            events[en] = Progress { done: done, total: plan.total, applied: applied, failed: failed, percent: percent }
            en += 1usize
            c += 1usize
        }
    }
    ret BulkResult { valid: !cancelled, reason: "", cancelled: cancelled, correlation_id: plan.correlation_id, total: plan.total, applied: applied, failed: failed, outcomes: outcomes[0usize..on], progress: events[0usize..en] }
}

type ReasonCount = struct { reason: str, count: usize }

type BulkSummary = struct {
    valid: bool,
    cancelled: bool,
    headline: str,
    correlation_id: str,
    failures: []const IdOutcome,
    by_reason: []const ReasonCount,
}

// The report a person reads afterwards: failures first and in full, grouped by reason.
fn summarize_bulk_outcome(a: *mem.Arena, catalog: []const Message, result: BulkResult) -> BulkSummary {
    var none_failures: []const IdOutcome = zero
    var none_reasons: []const ReasonCount = zero
    let (failures, fe) = mem.alloc[IdOutcome](a, result.outcomes.len + 1usize)
    let (reasons, re) = mem.alloc[ReasonCount](a, result.outcomes.len + 1usize)
    if fe != ok || re != ok { ret BulkSummary { valid: false, cancelled: result.cancelled, headline: "", correlation_id: result.correlation_id, failures: none_failures, by_reason: none_reasons } }
    var fn_count = 0usize
    var rn = 0usize
    var i = 0usize
    while i < result.outcomes.len {
        if !result.outcomes[i].good {
            failures[fn_count] = result.outcomes[i]
            fn_count += 1usize
            var reason = result.outcomes[i].reason
            if reason.len == 0usize { reason = "failed" }
            var found = false
            var k = 0usize
            while k < rn {
                if str.eq(reasons[k].reason, reason) {
                    reasons[k].count += 1usize
                    found = true
                }
                k += 1usize
            }
            if !found {
                reasons[rn] = ReasonCount { reason: reason, count: 1usize }
                rn += 1usize
            }
        }
        i += 1usize
    }
    var names: [3]str = zero
    var values: [3]str = zero
    names[0usize] = "applied"
    names[1usize] = "total"
    names[2usize] = "failed"
    values[0usize] = f.number_text(a, f64(result.applied))
    values[1usize] = f.number_text(a, f64(result.total))
    values[2usize] = f.number_text(a, f64(fn_count))
    var headline = ""
    if fn_count > 0usize {
        headline = message(a, catalog, "bulkOps.headlineFailed", names[0..], values[0..])
    } else {
        headline = message(a, catalog, "bulkOps.headline", names[0..], values[0..])
    }
    ret BulkSummary { valid: fn_count == 0usize, cancelled: result.cancelled, headline: headline, correlation_id: result.correlation_id, failures: failures[0usize..fn_count], by_reason: reasons[0usize..rn] }
}

// --- undo and redo -------------------------------------------------------------------------------------------------

// One applied cell edit: the record, the field, the value it displaced and the value it set.
type Change = struct { record_id: f.Value, field: str, before: f.Value, after: f.Value }

type Entry = struct { serial: usize, label: str, has_label: bool, changes: []const Change }

type Stack = struct { key: str, epoch: usize, undo: []Entry, undo_n: usize, redo: []Entry, redo_n: usize }

type Pending = struct { stack_key: str, epoch: usize, serial: usize, redo_direction: bool, settled: bool }

// Per-(editor, table) command stacks, depth-capped, cleared when the scope (the signed-in account) changes.
type UndoStore = struct {
    a: *mem.Arena,
    depth: usize,
    scope: str,
    owner: str,
    has_owner: bool,
    epoch: usize,
    stacks: []Stack,
    stack_n: usize,
    serial: usize,
    pending: []Pending,
    pending_n: usize,
}

fn default_depth() -> usize { ret 100usize }

fn new_undo_store(a: *mem.Arena, depth: usize, max_stacks: usize, max_pending: usize) -> UndoStore {
    var none_stacks: []Stack = zero
    var none_pending: []Pending = zero
    let (stacks, se) = mem.alloc[Stack](a, max_stacks + 1usize)
    let (pending, pe) = mem.alloc[Pending](a, max_pending + 1usize)
    var d = depth
    if d == 0usize { d = default_depth() }
    if se != ok || pe != ok { ret UndoStore { a: a, depth: d, scope: "", owner: "", has_owner: false, epoch: 0usize, stacks: none_stacks, stack_n: 0usize, serial: 0usize, pending: none_pending, pending_n: 0usize } }
    ret UndoStore { a: a, depth: d, scope: "", owner: "", has_owner: false, epoch: 0usize, stacks: stacks, stack_n: 0usize, serial: 0usize, pending: pending, pending_n: 0usize }
}

// The host reports the current scope; a changed scope drops every history on the next use.
fn set_scope(s: *UndoStore, scope: str) { s.scope = scope }

fn refresh_scope(s: *UndoStore) {
    if !s.has_owner || !str.eq(s.owner, s.scope) {
        if s.has_owner || s.stack_n > 0usize {
            s.stack_n = 0usize
            s.epoch += 1usize
        }
        s.owner = s.scope
        s.has_owner = true
    }
}

fn stack_key(a: *mem.Arena, editor: str, table: str) -> str { ret f.join3(a, editor, ":", table) }

// The stack of an editor on a table, created on first use; its position in the store.
fn stack_for(s: *UndoStore, editor: str, table: str) -> usize {
    refresh_scope(s)
    let key = stack_key(s.a, editor, table)
    var i = 0usize
    while i < s.stack_n {
        if str.eq(s.stacks[i].key, key) { ret i }
        i += 1usize
    }
    if s.stack_n >= s.stacks.len { ret s.stacks.len }
    let (undo_cells, ue) = mem.alloc[Entry](s.a, s.depth + 2usize)
    let (redo_cells, re) = mem.alloc[Entry](s.a, s.depth + 2usize)
    if ue != ok || re != ok { ret s.stacks.len }
    s.stacks[s.stack_n] = Stack { key: key, epoch: s.epoch, undo: undo_cells, undo_n: 0usize, redo: redo_cells, redo_n: 0usize }
    s.stack_n += 1usize
    ret s.stack_n - 1usize
}

fn drop_first(entries: []Entry, n: usize) -> usize {
    var i = 1usize
    while i < n {
        entries[i - 1usize] = entries[i]
        i += 1usize
    }
    if n > 0usize { ret n - 1usize }
    ret 0usize
}

// Record an applied edit (one change for a cell, many for a range: undone as one unit). Answers the undo depth.
fn undo_push(s: *UndoStore, editor: str, table: str, changes: []const Change, label: str, has_label: bool) -> usize {
    let at = stack_for(s, editor, table)
    if at >= s.stacks.len { ret 0usize }
    s.serial += 1usize
    s.stacks[at].undo[s.stacks[at].undo_n] = Entry { serial: s.serial, label: label, has_label: has_label, changes: changes }
    s.stacks[at].undo_n += 1usize
    if s.stacks[at].undo_n > s.depth {
        s.stacks[at].undo_n = drop_first(s.stacks[at].undo, s.stacks[at].undo_n)
    }
    // a fresh edit invalidates the redo branch
    s.stacks[at].redo_n = 0usize
    ret s.stacks[at].undo_n
}

// The writes that restore the before-values (or re-apply the after-values), the label, and whether there was one.
type Write = struct { record_id: f.Value, field: str, value: f.Value, expected: f.Value, has_expected: bool }

type Step = struct { valid: bool, reason: str, label: str, has_label: bool, writes: []const Write, token: usize, has_token: bool }

fn no_step(why: str) -> Step {
    var none: []const Write = zero
    ret Step { valid: false, reason: why, label: "", has_label: false, writes: none, token: 0usize, has_token: false }
}

fn writes_of(a: *mem.Arena, entry: Entry, undoing: bool, with_expected: bool) -> []const Write {
    var none: []const Write = zero
    let (out, e) = mem.alloc[Write](a, entry.changes.len + 1usize)
    if e != ok { ret none }
    var i = 0usize
    while i < entry.changes.len {
        let c = entry.changes[i]
        var value = c.after
        var expected = c.before
        if undoing {
            value = c.before
            expected = c.after
        }
        out[i] = Write { record_id: c.record_id, field: c.field, value: value, expected: expected, has_expected: with_expected }
        i += 1usize
    }
    ret out[0usize..entry.changes.len]
}

// Undo the latest edit and move it to the redo side; the writes restore the before-values.
fn undo(s: *UndoStore, editor: str, table: str) -> Step {
    let at = stack_for(s, editor, table)
    if at >= s.stacks.len || s.stacks[at].undo_n == 0usize { ret no_step("nothing-to-undo") }
    s.stacks[at].undo_n -= 1usize
    let entry = s.stacks[at].undo[s.stacks[at].undo_n]
    s.stacks[at].redo[s.stacks[at].redo_n] = entry
    s.stacks[at].redo_n += 1usize
    ret Step { valid: true, reason: "", label: entry.label, has_label: entry.has_label, writes: writes_of(s.a, entry, true, false), token: 0usize, has_token: false }
}

// Redo the latest undone edit; the writes re-apply it.
fn redo(s: *UndoStore, editor: str, table: str) -> Step {
    let at = stack_for(s, editor, table)
    if at >= s.stacks.len || s.stacks[at].redo_n == 0usize { ret no_step("nothing-to-redo") }
    s.stacks[at].redo_n -= 1usize
    let entry = s.stacks[at].redo[s.stacks[at].redo_n]
    s.stacks[at].undo[s.stacks[at].undo_n] = entry
    s.stacks[at].undo_n += 1usize
    ret Step { valid: true, reason: "", label: entry.label, has_label: entry.has_label, writes: writes_of(s.a, entry, false, false), token: 0usize, has_token: false }
}

// Prepare an undo or redo without moving anything: the writes carry the value they expect to find, and `commit`
// moves only the fields the host acknowledged (the rest stay retryable).
fn prepare(s: *UndoStore, editor: str, table: str, redo_direction: bool) -> Step {
    let at = stack_for(s, editor, table)
    var why = "nothing-to-undo"
    if redo_direction { why = "nothing-to-redo" }
    if at >= s.stacks.len { ret no_step(why) }
    var entry: Entry = zero
    if redo_direction {
        if s.stacks[at].redo_n == 0usize { ret no_step(why) }
        entry = s.stacks[at].redo[s.stacks[at].redo_n - 1usize]
    } else {
        if s.stacks[at].undo_n == 0usize { ret no_step(why) }
        entry = s.stacks[at].undo[s.stacks[at].undo_n - 1usize]
    }
    if s.pending_n >= s.pending.len { ret no_step("too-many-pending") }
    s.pending[s.pending_n] = Pending { stack_key: s.stacks[at].key, epoch: s.stacks[at].epoch, serial: entry.serial, redo_direction: redo_direction, settled: false }
    s.pending_n += 1usize
    ret Step { valid: true, reason: "", label: entry.label, has_label: entry.has_label, writes: writes_of(s.a, entry, !redo_direction, true), token: s.pending_n - 1usize, has_token: true }
}

type Ack = struct { record_id: f.Value, field: str }

// Settle a prepared step with the fields the host acknowledged: those move between the histories, the rest of the
// entry stays where it was. A stale token (the stack was cleared, a newer edit landed, or it is settled) moves nothing.
fn commit(s: *UndoStore, token: usize, acknowledged: []const Ack) -> usize {
    if token >= s.pending_n { ret 0usize }
    var p = s.pending[token]
    if p.settled { ret 0usize }
    var at = s.stacks.len
    var i = 0usize
    while i < s.stack_n {
        if str.eq(s.stacks[i].key, p.stack_key) && s.stacks[i].epoch == p.epoch { at = i }
        i += 1usize
    }
    if at >= s.stacks.len { ret 0usize }
    // the entry must still be on top of its source side
    var top: Entry = zero
    if p.redo_direction {
        if s.stacks[at].redo_n == 0usize { ret 0usize }
        top = s.stacks[at].redo[s.stacks[at].redo_n - 1usize]
    } else {
        if s.stacks[at].undo_n == 0usize { ret 0usize }
        top = s.stacks[at].undo[s.stacks[at].undo_n - 1usize]
    }
    if top.serial != p.serial { ret 0usize }
    s.pending[token].settled = true
    let (applied, ae) = mem.alloc[Change](s.a, top.changes.len + 1usize)
    let (remaining, re) = mem.alloc[Change](s.a, top.changes.len + 1usize)
    if ae != ok || re != ok { ret 0usize }
    var an = 0usize
    var rn = 0usize
    var k = 0usize
    while k < top.changes.len {
        var acked = false
        var m = 0usize
        while m < acknowledged.len {
            if str.eq(view.js_string(s.a, acknowledged[m].record_id), view.js_string(s.a, top.changes[k].record_id)) && str.eq(acknowledged[m].field, top.changes[k].field) { acked = true }
            m += 1usize
        }
        if acked {
            applied[an] = top.changes[k]
            an += 1usize
        } else {
            remaining[rn] = top.changes[k]
            rn += 1usize
        }
        k += 1usize
    }
    if an == 0usize { ret 0usize }
    if p.redo_direction {
        s.stacks[at].redo_n -= 1usize
        if rn > 0usize {
            s.stacks[at].redo[s.stacks[at].redo_n] = Entry { serial: top.serial, label: top.label, has_label: top.has_label, changes: remaining[0usize..rn] }
            s.stacks[at].redo_n += 1usize
        }
        s.stacks[at].undo[s.stacks[at].undo_n] = Entry { serial: top.serial, label: top.label, has_label: top.has_label, changes: applied[0usize..an] }
        s.stacks[at].undo_n += 1usize
        if s.stacks[at].undo_n > s.depth {
            s.stacks[at].undo_n = drop_first(s.stacks[at].undo, s.stacks[at].undo_n)
        }
    } else {
        s.stacks[at].undo_n -= 1usize
        if rn > 0usize {
            s.stacks[at].undo[s.stacks[at].undo_n] = Entry { serial: top.serial, label: top.label, has_label: top.has_label, changes: remaining[0usize..rn] }
            s.stacks[at].undo_n += 1usize
        }
        s.stacks[at].redo[s.stacks[at].redo_n] = Entry { serial: top.serial, label: top.label, has_label: top.has_label, changes: applied[0usize..an] }
        s.stacks[at].redo_n += 1usize
        if s.stacks[at].redo_n > s.depth {
            s.stacks[at].redo_n = drop_first(s.stacks[at].redo, s.stacks[at].redo_n)
        }
    }
    ret an
}

type UndoState = struct { can_undo: bool, can_redo: bool, undo_depth: usize }

fn undo_state(s: *UndoStore, editor: str, table: str) -> UndoState {
    let at = stack_for(s, editor, table)
    if at >= s.stacks.len { ret UndoState { can_undo: false, can_redo: false, undo_depth: 0usize } }
    ret UndoState { can_undo: s.stacks[at].undo_n > 0usize, can_redo: s.stacks[at].redo_n > 0usize, undo_depth: s.stacks[at].undo_n }
}

// The change entries of a range edit over rows (found by `id`): one undoable unit; unknown ids are skipped.
fn bulk_changes(a: *mem.Arena, rows: []const view.Row, record_ids: []const f.Value, field: str, value: f.Value) -> []const Change {
    var none: []const Change = zero
    let (out, e) = mem.alloc[Change](a, record_ids.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < record_ids.len {
        // the last row holding the id, as a Map built from the list would
        var found = false
        var at = 0usize
        var k = 0usize
        while k < rows.len {
            let id = view.value_at(rows[k], "id")
            if view.same_value(id, record_ids[i]) {
                found = true
                at = k
            }
            k += 1usize
        }
        if found {
            let (before, present) = view.cell_of(rows[at], field)
            out[n] = Change { record_id: record_ids[i], field: field, before: before, after: value }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// JSON field equality; absent and null are the same empty cell.
fn same_undo_value(left: f.Value, right: f.Value) -> bool {
    if left.kind == .Blank && right.kind == .Blank { ret true }
    if left.kind != right.kind { ret false }
    if left.kind == .Array || left.kind == .Record {
        if left.items.len != right.items.len { ret false }
        var i = 0usize
        while i < left.items.len {
            if !same_undo_value(left.items[i], right.items[i]) { ret false }
            i += 1usize
        }
        ret true
    }
    if left.kind == .Number { ret left.n == right.n || (left.n != left.n && right.n != right.n) }
    ret view.same_value(left, right)
}
