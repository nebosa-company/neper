// The durable workflow interpreter (L036, the runtime half), after appdor's `src/workflow/runtime.js`: a normalized
// definition executed against a run journal. Every step consults the journal first -- a completed execution returns its
// recorded result and runs nothing -- so restarting re-derives the control-flow position and resumes at the first step that
// never finished. Calling `execute_run` again on a run that has entries is the whole of resuming: there is no second path.
//
// Control flow is `if`, `case`, `foreach`, `fork`, `try`, `stop` and `fail`; waiting is `delay`, `wait-signal` and `approval`
// (parked on a signal derived from the execution key); `set` and `log` are data; every other step type is an effect handed
// to an injected handler with an idempotency key stable across replays (`runId:key`), retried with backoff, withheld in a
// dry run when its type mutates. Effects are at-least-once: the key is how a receiver makes the retry a no-op.
//
// Everything outside the interpreter is injected as `Hooks`: the clock and sleep, the template renderer (Jinja stays
// outside), the credential-redacting trace, the outbound URL check, the effect handlers, and the environment. The journal
// store is `e.algo.journal`'s; a real store satisfies the same contract.
//
// Differences from appdor's: fork branches run one after another in declaration order where appdor's run concurrently,
// so a fork's journal entries are not interleaved as the concurrent ones are (the set of entries, the outcomes and the
// result are the same); a condition that is a filter tree is the host's `filter_matches` hook; a step type the catalogue
// does not know fails the run as appdor's does (a plugin step type is `no-handler` unless the host handles `extension`).
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.journal as journal
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

error Exhausted

// What an effect handler answered: `handled` false when the host has no handler for the step type.
type EffectResult = struct { handled: bool, failed: bool, permanent: bool, detail: str, has_result: bool, result: json.Value }

// The outbound URL verdict: `refusal` non-empty when refused; `unchecked_host` non-empty when approved only as far as
// the caller could see (a public-looking name nothing resolved).
type UrlVerdict = struct { refusal: str, unchecked_host: str }

type Hooks = struct { ctx: *void, now: fn(*void) -> i64, sleep: fn(*void, i64), render_value: fn(*void, str, json.Value) -> (json.Value, bool), render_text: fn(*void, str, json.Value) -> str, trace: fn(*void, json.Value) -> json.Value, check_url: fn(*void, str) -> UrlVerdict, has_effect: fn(*void, str) -> bool, effect: fn(*void, str, json.Value) -> EffectResult, filter_matches: fn(*void, json.Value, json.Value) -> bool, env: json.Value }

const OK: u8 = 0u8
const SUSPEND: u8 = 1u8
const STOP: u8 = 2u8
const FAIL: u8 = 3u8
const STALE: u8 = 4u8
const CANCEL: u8 = 5u8
const ERROR: u8 = 6u8

// A step's outcome: a value (or none), or one of the signals that unwind a run.
type Flow = struct { kind: u8, value: json.Value, has_value: bool, wait: json.Value, message: str, step_id: str, has_step_id: bool, reason: str, budget: usize, has_budget: bool }

type Executor = struct { a: *mem.Arena, hooks: *const Hooks, store: *journal.Store, workflow: json.Value, run: json.Value, commit: journal.Commit, vars: ir.Obj, outputs: ir.Obj, changes: list.List[json.Value], unchecked: list.List[str], step_budget: usize, steps_run: usize }

fn done(v: json.Value, has: bool) -> Flow {
    ret Flow { kind: OK, value: v, has_value: has, wait: .Null, message: "", step_id: "", has_step_id: false, reason: "", budget: 0usize, has_budget: false }
}

fn nothing() -> Flow { ret done(.Null, false) }

fn signal(kind: u8, message: str) -> Flow {
    ret Flow { kind: kind, value: .Null, has_value: false, wait: .Null, message: message, step_id: "", has_step_id: false, reason: "", budget: 0usize, has_budget: false }
}

fn fail_run(message: str, step_id: str) -> Flow {
    var f = signal(FAIL, message)
    f.step_id = step_id
    f.has_step_id = step_id.len > 0usize
    ret f
}

fn suspend(wait: json.Value) -> Flow {
    var f = signal(SUSPEND, "")
    f.wait = wait
    ret f
}

// --- small helpers --------------------------------------------------------------------------------------------------

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn flag(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { ret json.Value{ Number: json.Number{ lexeme: "0" } } }
    ret json.Value{ Number: v }
}

fn usize_value(a: *mem.Arena, n: usize) -> json.Value { ret number(a, i64(n)) }

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

fn cat3(a: *mem.Arena, x: str, y: str, z: str) -> str { ret cat(a, cat(a, x, y), z) }

fn get(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = ir.get(v, key)
    ret (x, found)
}

fn member_text(v: json.Value, key: str) -> str {
    let (x, found) = get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

// A member is a value other than null or missing: `x ?? fallback` uses `fallback` otherwise.
fn present(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = get(v, key)
    if !found || ir.is_null(x) { ret (.Null, false) }
    ret (x, true)
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok {
        let empty: []const json.Member = zero
        ret ir.Obj { items: zero, len: 0usize, arena: a }
    }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn push_value(l: *list.List[json.Value], v: json.Value) {
    let e = list.push[json.Value](l, v)
}

// --- durations ------------------------------------------------------------------------------------------------------

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn unit_ms(name: str) -> (f64, bool) {
    var key = [8]u8{ 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8 }
    if name.len == 0usize || name.len > 7usize { ret (0.0f64, false) }
    var at = 0usize
    while at < name.len {
        key[at] = lower_byte(name[at])
        at += 1usize
    }
    let k = key[0usize..name.len]
    if str.eq(k, "ms") { ret (1.0f64, true) }
    if str.eq(k, "s") || str.eq(k, "sec") || str.eq(k, "secs") || str.eq(k, "second") || str.eq(k, "seconds") { ret (1000.0f64, true) }
    if str.eq(k, "m") || str.eq(k, "min") || str.eq(k, "mins") || str.eq(k, "minute") || str.eq(k, "minutes") { ret (60000.0f64, true) }
    if str.eq(k, "h") || str.eq(k, "hr") || str.eq(k, "hrs") || str.eq(k, "hour") || str.eq(k, "hours") { ret (3600000.0f64, true) }
    if str.eq(k, "d") || str.eq(k, "day") || str.eq(k, "days") { ret (86400000.0f64, true) }
    if str.eq(k, "w") || str.eq(k, "week") || str.eq(k, "weeks") { ret (604800000.0f64, true) }
    ret (0.0f64, false)
}

// `\d+(\.\d+)?` at the start of `s`: the end of the match, or 0.
fn number_end(s: str, from: usize) -> usize {
    var at = from
    while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 { at += 1usize }
    if at == from { ret 0usize }
    if at + 1usize < s.len && s[at] == 46u8 && s[at + 1usize] >= 48u8 && s[at + 1usize] <= 57u8 {
        at += 1usize
        while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 { at += 1usize }
    }
    ret at
}

fn decimal_value(s: str) -> f64 {
    let (n, ne) = json.number(s)
    if ne != ok { ret 0.0f64 }
    let (x, xe) = json.number_f64(n)
    if xe != ok { ret 0.0f64 }
    ret x
}

// "4h", "30 minutes", "1d" or a raw millisecond number; absent (false) rather than a guess on anything else.
fn parse_duration(v: json.Value) -> (f64, bool) {
    var out = 0.0f64
    var good = false
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok && x >= 0.0f64 {
            out = x
            good = true
        }
    case .String as s:
        var start = 0usize
        while start < s.len && is_space(s[start]) { start += 1usize }
        var end = s.len
        while end > start && is_space(s[end - 1usize]) { end -= 1usize }
        let t = s[start..end]
        let n_end = number_end(t, 0usize)
        if n_end > 0usize {
            let amount = decimal_value(t[0usize..n_end])
            var rest = n_end
            while rest < t.len && is_space(t[rest]) { rest += 1usize }
            if rest == t.len {
                out = amount
                good = true
            } else {
                let (unit, have_unit) = unit_ms(t[rest..])
                if have_unit {
                    out = amount * unit
                    good = true
                }
            }
        }
    default:
        good = false
    }
    ret (out, good)
}

fn approval_signal(a: *mem.Arena, key: str) -> str { ret cat(a, "approval:", key) }

// The condition truthiness of the runtime (not JavaScript's): arrays and objects by size, strings not "" or "false".
fn truthy(v: json.Value) -> bool {
    var yes = false
    switch v {
    case .Null:
        yes = false
    case .Bool as b:
        yes = b
    case .Number as n:
        yes = ir.truthy(v)
    case .String as s:
        yes = s.len > 0usize && !str.eq(s, "false")
    case .Array as xs:
        yes = xs.len > 0usize
    case .Object as m:
        yes = m.len > 0usize
    }
    ret yes
}

// --- executor -------------------------------------------------------------------------------------------------------

fn begin(ex: *Executor) {
    let (c, e) = journal.begin_commit(ex.a, ex.run)
    if e == ok { ex.commit = c }
}

fn record(ex: *Executor, kind: str, fields: json.Value) -> usize {
    let added = journal.add(ex.a, &ex.commit, kind, fields)
    ret ex.commit.entries.len - 1usize
}

fn record_obj(ex: *Executor, kind: str, fields: ir.Obj) -> usize {
    var f = fields
    ret record(ex, kind, ir.obj_value(&f))
}

// Commit the pending entries: the run and the replay index move forward, or the write was stale.
fn flush(ex: *Executor) -> Flow {
    if journal.is_empty(&ex.commit) { ret nothing() }
    let (built, built_error) = journal.build(ex.a, &ex.commit)
    if built_error != ok { ret signal(ERROR, "build-failed") }
    begin(ex)
    let (landed, store_error) = journal.store_commit(ex.store, member_text(ex.run, "runId"), built)
    if store_error != ok { ret signal(ERROR, "store-failed") }
    let (ok_value, have_ok) = get(landed, "ok")
    var good = false
    switch ok_value {
    case .Bool as b:
        good = b
    default:
        good = false
    }
    if !good { ret signal(STALE, member_text(landed, "reason")) }
    let (run_value, have_run) = get(landed, "run")
    ex.run = run_value
    let rebased = journal.rebase(ex.a, &ex.commit, run_seq(run_value))
    ret nothing()
}

fn run_seq(run: json.Value) -> usize {
    let (v, found) = get(run, "seq")
    let (n, good) = journal.count_of(v)
    ret n
}

// The object every template is rendered against; `extra` carries the lexical scope and the attempt.
fn context(ex: *Executor, extra: json.Value) -> json.Value {
    var c = obj(ex.a)
    let (trigger_value, have_trigger) = get(ex.run, "trigger")
    let empty: []const json.Member = zero
    let empty_object = json.Value{ Object: empty }
    put(&c, "trigger", ir.or_falsy(trigger_value, "payload", empty_object))
    put(&c, "triggerMeta", ir.or_falsy(trigger_value, "meta", empty_object))
    put(&c, "input", ir.or_falsy(ex.run, "input", empty_object))
    put(&c, "vars", ir.obj_value(&ex.vars))
    put(&c, "steps", ir.obj_value(&ex.outputs))
    var r = obj(ex.a)
    let (run_id, have_id) = get(ex.run, "runId")
    if have_id { put(&r, "id", run_id) }
    let (workflow_id, have_workflow) = get(ex.run, "workflowId")
    if have_workflow { put(&r, "workflowId", workflow_id) }
    let (mode, have_mode) = get(ex.run, "mode")
    if have_mode { put(&r, "mode", mode) }
    let (started_at, have_started) = get(ex.run, "startedAt")
    if have_started { put(&r, "startedAt", started_at) }
    let (attempt, have_attempt) = present(extra, "attempt")
    if have_attempt { put(&r, "attempt", attempt) } else { put(&r, "attempt", number(ex.a, 1i64)) }
    put(&c, "run", ir.obj_value(&r))
    put(&c, "env", ex.hooks.env)
    let assigned = ir.assign(&c, extra)
    ret ir.obj_value(&c)
}

// --- templates ------------------------------------------------------------------------------------------------------

fn is_template(s: str) -> bool {
    var at = 0usize
    while at + 1usize < s.len {
        let c = s[at]
        let d = s[at + 1usize]
        if c == 123u8 && (d == 123u8 || d == 37u8 || d == 35u8) { ret true }
        at += 1usize
    }
    ret false
}

// A value with every string rendered: a string as the renderer's typed value, an array element by element (an undefined
// element is null), an object's keys and values (an undefined member is dropped, as JSON drops it).
fn render_deep(ex: *Executor, v: json.Value, ctx: json.Value) -> (json.Value, bool) {
    switch v {
    case .String as s:
        let (rendered, defined) = ex.hooks.render_value(ex.hooks.ctx, s, ctx)
        ret (rendered, defined)
    case .Array as xs:
        let (out, out_error) = list.init[json.Value](ex.a, xs.len + 1usize)
        if out_error != ok { ret (v, true) }
        var rendered = out
        var at = 0usize
        while at < xs.len {
            let (one, defined) = render_deep(ex, xs[at], ctx)
            if defined { push_value(&rendered, one) } else { push_value(&rendered, .Null) }
            at += 1usize
        }
        ret (json.Value{ Array: list.slice_const[json.Value](&rendered) }, true)
    case .Object as m:
        var o = obj(ex.a)
        var at = 0usize
        while at < m.len {
            var key = m[at].key
            if is_template(key) { key = ex.hooks.render_text(ex.hooks.ctx, key, ctx) }
            let (one, defined) = render_deep(ex, m[at].value, ctx)
            if defined { put(&o, key, one) }
            at += 1usize
        }
        ret (ir.obj_value(&o), true)
    default:
        ret (v, true)
    }
}

// A step's config with every non-raw field rendered; the raw list is per step type.
fn render_step_config(ex: *Executor, step: json.Value, ctx: json.Value) -> json.Value {
    let type_name = member_text(step, "type")
    let info = ir.core_step(type_name)
    var raw = ""
    if info.found { raw = info.raw }
    let config = ir.or_falsy(step, "config", json.Value{ Object: zero })
    let (members, is_object) = ir.members_of(config)
    var o = obj(ex.a)
    if is_object {
        var at = 0usize
        while at < members.len {
            if ir.in_csv(raw, members[at].key) {
                put(&o, members[at].key, members[at].value)
            } else {
                let (one, defined) = render_deep(ex, members[at].value, ctx)
                if defined { put(&o, members[at].key, one) }
            }
            at += 1usize
        }
    }
    ret ir.obj_value(&o)
}

// A condition: absent is true, a boolean itself, a tree the host's filter matcher, a string a template.
fn evaluate_condition(ex: *Executor, expression: json.Value, has: bool, ctx: json.Value) -> bool {
    if !has || ir.is_null(expression) { ret true }
    var result = false
    switch expression {
    case .Bool as b:
        result = b
    case .Object as m:
        result = ex.hooks.filter_matches(ex.hooks.ctx, expression, ctx)
    case .Array as xs:
        result = ex.hooks.filter_matches(ex.hooks.ctx, expression, ctx)
    case .String as s:
        var source = s
        if !is_template(s) { source = cat3(ex.a, "{{ ", s, " }}") }
        let (value, defined) = ex.hooks.render_value(ex.hooks.ctx, source, ctx)
        result = defined && truthy(value)
    case .Number as n:
        var source = cat3(ex.a, "{{ ", n.lexeme, " }}")
        let (value, defined) = ex.hooks.render_value(ex.hooks.ctx, source, ctx)
        result = defined && truthy(value)
    default:
        result = false
    }
    ret result
}

// --- step execution -------------------------------------------------------------------------------------------------

fn step_id_of(step: json.Value) -> str { ret ir.id_text(step) }

fn frames_with(a: *mem.Arena, frames: []const str, one: str) -> []const str {
    let (out, e) = mem.alloc[str](a, frames.len + 1usize)
    if e != ok { ret frames }
    var at = 0usize
    while at < frames.len {
        out[at] = frames[at]
        at += 1usize
    }
    out[frames.len] = one
    ret out[0usize..frames.len + 1usize]
}

fn key_of(ex: *Executor, step_id: str, frames: []const str) -> str {
    let (k, e) = ir.execution_key(ex.a, step_id, frames)
    if e != ok { ret step_id }
    ret k
}

fn exec_steps(ex: *Executor, steps: json.Value, frames: []const str, scope: json.Value) -> Flow {
    let list_of = items(steps)
    var at = 0usize
    while at < list_of.len {
        let f = exec_step(ex, list_of[at], frames, scope)
        if f.kind != OK { ret f }
        at += 1usize
    }
    ret nothing()
}

fn assert_control(ex: *Executor) -> Flow {
    let (cancel, have_cancel) = get(ex.run, "cancelRequested")
    if have_cancel && ir.truthy(cancel) {
        let (reason, have_reason) = get(ex.run, "cancelReason")
        var message = "cancelled"
        let (reason_text, reason_is_text) = ir.string_of(reason)
        if have_reason && reason_is_text && reason_text.len > 0usize { message = reason_text }
        ret signal(CANCEL, message)
    }
    let (pause, have_pause) = get(ex.run, "pauseRequested")
    if have_pause && ir.truthy(pause) {
        var wait = obj(ex.a)
        put(&wait, "kind", text("paused"))
        ret suspend(ir.obj_value(&wait))
    }
    ret nothing()
}

fn exec_step(ex: *Executor, step: json.Value, frames: []const str, scope: json.Value) -> Flow {
    let id = step_id_of(step)
    let key = key_of(ex, id, frames)
    let type_name = member_text(step, "type")
    let info = ir.core_step(type_name)
    if !info.found { ret fail_run("Unknown step type", id) }
    let control = assert_control(ex)
    if control.kind != OK { ret control }
    ex.steps_run += 1usize
    if ex.steps_run - 1usize > ex.step_budget {
        var f = fail_run("Step budget", id)
        f.reason = "budget_exceeded"
        f.budget = ex.step_budget
        f.has_budget = true
        ret f
    }
    // Replay: a completed execution returns its recorded result and runs nothing.
    if journal.is_complete(ex.run, key) {
        let (result, has_result) = journal.result(ex.run, key)
        if str.eq(type_name, "approval") {
            let check = check_approval_evidence(ex, step, key, result, has_result)
            if check.kind != OK { ret check }
        }
        if has_result { put(&ex.outputs, id, result) }
        if str.eq(type_name, "set") && has_result {
            let (members, is_object) = ir.members_of(result)
            if is_object {
                var m = 0usize
                while m < members.len {
                    put(&ex.vars, members[m].key, members[m].value)
                    m += 1usize
                }
            }
        }
        ret replay_control(ex, step, frames, result, has_result, scope)
    }
    // A guard that was false on an earlier pass stays false.
    let (skipped, have_skipped) = journal.skipped(ex.run, key)
    if have_skipped && str.eq(member_text(skipped, "reason"), "guard-false") { ret nothing() }
    let (condition, has_condition) = get(step, "if")
    let (started_entry, have_started) = journal.started(ex.run, key)
    if !have_started && has_condition && !evaluate_condition(ex, condition, true, context(ex, scope)) {
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "stepId", text(id))
        put(&f, "reason", text("guard-false"))
        let skipped_index = record_obj(ex, "step-skipped", f)
        let flushed = flush(ex)
        if flushed.kind != OK { ret flushed }
        ret nothing()
    }
    let started_at = ex.hooks.now(ex.hooks.ctx)
    var started_fields = obj(ex.a)
    put(&started_fields, "key", text(key))
    put(&started_fields, "stepId", text(id))
    put(&started_fields, "stepType", text(type_name))
    put(&started_fields, "at", number(ex.a, started_at))
    let started_index = record_obj(ex, "step-started", started_fields)
    let config = render_step_config(ex, step, context(ex, scope))
    // The trace of the rendered config rides on the journal entry that is about to be committed.
    let traced = ex.hooks.trace(ex.hooks.ctx, config)
    set_entry_member(ex, started_index, "input", traced)
    let outcome = dispatch(ex, step, frames, key, scope, config)
    if outcome.kind == OK {
        if outcome.has_value { put(&ex.outputs, id, outcome.value) }
        let finished_at = ex.hooks.now(ex.hooks.ctx)
        var done_fields = obj(ex.a)
        put(&done_fields, "key", text(key))
        put(&done_fields, "stepId", text(id))
        put(&done_fields, "stepType", text(type_name))
        put(&done_fields, "at", number(ex.a, finished_at))
        var duration = finished_at - started_at
        if duration < 0i64 { duration = 0i64 }
        put(&done_fields, "durationMs", number(ex.a, duration))
        if outcome.has_value { put(&done_fields, "result", outcome.value) }
        let done_index = record_obj(ex, "step-completed", done_fields)
        let flushed = flush(ex)
        if flushed.kind != OK { ret flushed }
        ret outcome
    }
    if outcome.kind == SUSPEND || outcome.kind == STOP || outcome.kind == STALE || outcome.kind == CANCEL { ret outcome }
    // A failure: journaled, then either swallowed (continueOnError, an ordinary error) or raised.
    let failed_at = ex.hooks.now(ex.hooks.ctx)
    var failed_fields = obj(ex.a)
    put(&failed_fields, "key", text(key))
    put(&failed_fields, "stepId", text(id))
    put(&failed_fields, "at", number(ex.a, failed_at))
    var spent = failed_at - started_at
    if spent < 0i64 { spent = 0i64 }
    put(&failed_fields, "durationMs", number(ex.a, spent))
    put(&failed_fields, "error", text(outcome.message))
    let failed_index = record_obj(ex, "step-failed", failed_fields)
    let flushed = flush(ex)
    if flushed.kind != OK { ret flushed }
    if outcome.kind == FAIL { ret outcome }
    let (continue_value, have_continue) = get(step, "continueOnError")
    if have_continue && ir.truthy(continue_value) { ret nothing() }
    ret fail_run("Step failed", id)
}

// Set a member on a pending entry (appdor mutates the entry object it was given back).
fn set_entry_member(ex: *Executor, index: usize, key: str, value: json.Value) {
    if index >= ex.commit.entries.len { ret }
    let (o, e) = ir.new_obj(ex.a)
    if e != ok { ret }
    var entry = o
    let assigned = ir.assign(&entry, ex.commit.entries.items[index])
    let put_error = ir.put(&entry, key, value)
    ex.commit.entries.items[index] = ir.obj_value(&entry)
}

fn check_approval_evidence(ex: *Executor, step: json.Value, key: str, result: json.Value, has_result: bool) -> Flow {
    let config = ir.or_falsy(step, "config", json.Value{ Object: zero })
    let (evidence, have_evidence) = get(config, "evidenceFields")
    let evidence_items = items(evidence)
    if !have_evidence || evidence_items.len == 0usize { ret nothing() }
    if has_result {
        let (dry, have_dry) = get(result, "dryRun")
        if have_dry && ir.truthy(dry) { ret nothing() }
        let (timed_out, have_timed) = get(result, "timedOut")
        if have_timed && ir.truthy(timed_out) { ret nothing() }
    }
    let (approval_id, have_id) = present(result, "approvalId")
    if !has_result || !have_id || !ex.hooks.has_effect(ex.hooks.ctx, "checkApprovalGate") {
        ret fail_run("approval-evidence-check-unavailable", step_id_of(step))
    }
    var request = obj(ex.a)
    put(&request, "approvalId", approval_id)
    put(&request, "runId", ir.or_falsy(ex.run, "runId", .Null))
    put(&request, "key", text(key))
    let answered = ex.hooks.effect(ex.hooks.ctx, "checkApprovalGate", ir.obj_value(&request))
    if answered.failed {
        var message = "approval-evidence-check-failed"
        if answered.detail.len > 0usize { message = answered.detail }
        ret fail_run(message, step_id_of(step))
    }
    ret nothing()
}

fn resolve_items(ex: *Executor, step: json.Value, scope: json.Value) -> []const json.Value {
    let config = ir.or_falsy(step, "config", json.Value{ Object: zero })
    let (items_value, have_items) = present(config, "items")
    var source = ""
    if have_items {
        let (s, is_text) = ir.string_of(items_value)
        if is_text {
            source = s
        } else {
            source = scalar_text(items_value)
        }
    }
    let (raw, defined) = ex.hooks.render_value(ex.hooks.ctx, source, context(ex, scope))
    if !defined { ret zero }
    let (xs, is_array) = ir.items_of(raw)
    if is_array { ret xs }
    let (members, is_object) = ir.members_of(raw)
    if is_object {
        let (out, out_error) = mem.alloc[json.Value](ex.a, members.len + 1usize)
        if out_error != ok { ret zero }
        var at = 0usize
        while at < members.len {
            var pair = obj(ex.a)
            put(&pair, "key", text(members[at].key))
            put(&pair, "value", members[at].value)
            out[at] = ir.obj_value(&pair)
            at += 1usize
        }
        ret out[0usize..members.len]
    }
    if ir.is_null(raw) { ret zero }
    let (s, is_text) = ir.string_of(raw)
    if is_text && s.len == 0usize { ret zero }
    let (single, single_error) = mem.alloc[json.Value](ex.a, 1usize)
    if single_error != ok { ret zero }
    single[0] = raw
    ret single[0usize..1usize]
}

fn scalar_text(v: json.Value) -> str {
    var out = ""
    switch v {
    case .Bool as b:
        if b { out = "true" } else { out = "false" }
    case .Number as n:
        out = n.lexeme
    default:
        out = ""
    }
    ret out
}

// The scope one `foreach` iteration adds: the alias plus the loop metadata.
fn loop_scope(ex: *Executor, scope: json.Value, alias: str, list_of: []const json.Value, i: usize) -> json.Value {
    var s = obj(ex.a)
    let assigned = ir.assign(&s, scope)
    put(&s, alias, list_of[i])
    var l = obj(ex.a)
    put(&l, "index", usize_value(ex.a, i + 1usize))
    put(&l, "index0", usize_value(ex.a, i))
    put(&l, "first", flag(i == 0usize))
    put(&l, "last", flag(i + 1usize == list_of.len))
    put(&l, "length", usize_value(ex.a, list_of.len))
    if i > 0usize { put(&l, "previtem", list_of[i - 1usize]) }
    if i + 1usize < list_of.len { put(&l, "nextitem", list_of[i + 1usize]) }
    put(&s, "loop", ir.obj_value(&l))
    ret ir.obj_value(&s)
}

fn loop_frame_text(ex: *Executor, step_id: str, index: usize) -> str {
    let (f, e) = ir.loop_frame(ex.a, step_id, index)
    if e != ok { ret "" }
    ret f
}

fn fork_frame_text(ex: *Executor, step_id: str, branch: str) -> str {
    let (f, e) = ir.fork_frame(ex.a, step_id, branch)
    if e != ok { ret "" }
    ret f
}

fn config_text(step: json.Value, key: str) -> str {
    let config = ir.or_falsy(step, "config", json.Value{ Object: zero })
    ret member_text(config, key)
}

// Control steps still need their children walked on replay: a completed `if` names the branch it took, and that
// branch's own steps may be half finished.
fn replay_control(ex: *Executor, step: json.Value, frames: []const str, result: json.Value, has_result: bool, scope: json.Value) -> Flow {
    let type_name = member_text(step, "type")
    let id = step_id_of(step)
    var back = nothing()
    if has_result { back = done(result, true) }
    if str.eq(type_name, "if") {
        let (then_steps, have_then) = get(step, "then")
        let (else_steps, have_else) = get(step, "else")
        var chosen = else_steps
        if has_result && str.eq(member_text(result, "branch"), "then") { chosen = then_steps }
        let f = exec_steps(ex, chosen, frames_with(ex.a, frames, id), scope)
        if f.kind != OK { ret f }
        ret back
    }
    if str.eq(type_name, "case") {
        let cases = items(ir.value_of(step, "cases"))
        var chosen_steps: json.Value = .Null
        var found = false
        var c = 0usize
        while c < cases.len && !found {
            let (name, have_name) = get(cases[c], "name")
            let (wanted, have_wanted) = get(result, "branch")
            if has_result && have_name && have_wanted && ir.same_scalar(name, wanted) {
                chosen_steps = ir.value_of(cases[c], "steps")
                found = true
            }
            c += 1usize
        }
        if !found { chosen_steps = ir.value_of(step, "default") }
        let f = exec_steps(ex, chosen_steps, frames_with(ex.a, frames, id), scope)
        if f.kind != OK { ret f }
        ret back
    }
    if str.eq(type_name, "foreach") {
        let key = key_of(ex, id, frames)
        let (loop_entry, have_loop) = journal.loop_entry(ex.run, key)
        var list_of: []const json.Value = zero
        var recorded = false
        if have_loop {
            let (recorded_items, have_items) = present(loop_entry, "items")
            if have_items {
                list_of = items(recorded_items)
                recorded = true
            }
        }
        if !recorded { list_of = resolve_items(ex, step, scope) }
        var alias = config_text(step, "as")
        if alias.len == 0usize { alias = "item" }
        var i = 0usize
        while i < list_of.len {
            let f = exec_steps(ex, ir.value_of(step, "steps"), frames_with(ex.a, frames, loop_frame_text(ex, id, i)), loop_scope(ex, scope, alias, list_of, i))
            if f.kind != OK { ret f }
            i += 1usize
        }
        ret back
    }
    if str.eq(type_name, "fork") {
        var join = "all"
        if has_result && str.eq(member_text(result, "join"), "any") { join = "any" }
        if has_result && str.eq(member_text(result, "join"), "race") { join = "race" }
        if !has_result || member_text(result, "join").len == 0usize {
            let configured = config_text(step, "join")
            if configured.len > 0usize { join = configured }
        }
        if str.eq(join, "any") || str.eq(join, "race") {
            let key = key_of(ex, id, frames)
            var names: []const json.Value = zero
            let (recorded_names, have_names) = present(result, "branches")
            if has_result && have_names {
                names = items(recorded_names)
            } else {
                let (fork_names, fork_error) = journal.fork_branches(ex.a, ex.run, key)
                names = fork_names
            }
            let branches = items(ir.value_of(step, "branches"))
            var b = 0usize
            while b < branches.len {
                let name = member_text(branches[b], "name")
                var listed = false
                var n = 0usize
                while n < names.len {
                    let (nt, nt_is_text) = ir.string_of(names[n])
                    if nt_is_text && str.eq(nt, name) { listed = true }
                    n += 1usize
                }
                if listed {
                    let f = exec_steps(ex, ir.value_of(branches[b], "steps"), frames_with(ex.a, frames, fork_frame_text(ex, id, name)), scope)
                    if f.kind != OK { ret f }
                }
                b += 1usize
            }
        } else {
            let outcome = run_branches(ex, step, frames, scope)
            if outcome.kind != OK { ret outcome }
        }
        ret back
    }
    if str.eq(type_name, "try") {
        var caught = false
        if has_result {
            let (c, have_c) = get(result, "caught")
            switch c {
            case .Bool as b:
                caught = b
            default:
                caught = false
            }
        }
        if caught {
            let key = key_of(ex, id, frames)
            let (entry, have_entry) = journal.branch(ex.run, key)
            let (error_value, have_error) = present(entry, "error")
            if have_entry && have_error {
                put(&ex.vars, "error", error_value)
            } else {
                var e = obj(ex.a)
                put(&e, "message", ir.value_of(result, "error"))
                put(&ex.vars, "error", ir.obj_value(&e))
            }
            let f = exec_steps(ex, ir.value_of(step, "catch"), frames_with(ex.a, frames, cat(ex.a, id, ":catch")), scope)
            if f.kind != OK { ret f }
        } else {
            let f = exec_steps(ex, ir.value_of(step, "steps"), frames_with(ex.a, frames, id), scope)
            if f.kind != OK { ret f }
        }
        ret back
    }
    ret back
}

fn dispatch(ex: *Executor, step: json.Value, frames: []const str, key: str, scope: json.Value, config: json.Value) -> Flow {
    let type_name = member_text(step, "type")
    let id = step_id_of(step)
    if str.eq(type_name, "if") {
        let (recorded, have_recorded) = journal.branch(ex.run, key)
        var taken = "else"
        if have_recorded && member_text(recorded, "branch").len > 0usize {
            taken = member_text(recorded, "branch")
        } else {
            let (condition, has_condition) = get(ir.or_falsy(step, "config", json.Value{ Object: zero }), "condition")
            if evaluate_condition(ex, condition, has_condition, context(ex, scope)) { taken = "then" }
        }
        if !have_recorded {
            var f = obj(ex.a)
            put(&f, "key", text(key))
            put(&f, "stepId", text(id))
            put(&f, "branch", text(taken))
            let index = record_obj(ex, "branch-taken", f)
            let flushed = flush(ex)
            if flushed.kind != OK { ret flushed }
        }
        var chosen = ir.value_of(step, "else")
        if str.eq(taken, "then") { chosen = ir.value_of(step, "then") }
        let ran = exec_steps(ex, chosen, frames_with(ex.a, frames, id), scope)
        if ran.kind != OK { ret ran }
        var result = obj(ex.a)
        put(&result, "branch", text(taken))
        ret done(ir.obj_value(&result), true)
    }
    if str.eq(type_name, "case") {
        let (recorded, have_recorded) = journal.branch(ex.run, key)
        let ctx = context(ex, scope)
        let cases = items(ir.value_of(step, "cases"))
        var matched = false
        var matched_index = 0usize
        var c = 0usize
        while c < cases.len && !matched {
            if have_recorded {
                let (name, have_name) = get(cases[c], "name")
                let (wanted, have_wanted) = get(recorded, "branch")
                if have_name && have_wanted && ir.same_scalar(name, wanted) {
                    matched = true
                    matched_index = c
                }
            } else {
                let (guard, has_guard) = get(cases[c], "when")
                if evaluate_condition(ex, guard, has_guard, ctx) {
                    matched = true
                    matched_index = c
                }
            }
            c += 1usize
        }
        var branch = "default"
        if have_recorded && member_text(recorded, "branch").len > 0usize {
            branch = member_text(recorded, "branch")
        } else if matched {
            let name = member_text(cases[matched_index], "name")
            branch = "case"
            if name.len > 0usize { branch = name }
        }
        if !have_recorded {
            var f = obj(ex.a)
            put(&f, "key", text(key))
            put(&f, "stepId", text(id))
            put(&f, "branch", text(branch))
            let index = record_obj(ex, "branch-taken", f)
            let flushed = flush(ex)
            if flushed.kind != OK { ret flushed }
        }
        var chosen = ir.value_of(step, "default")
        if matched { chosen = ir.value_of(cases[matched_index], "steps") }
        let ran = exec_steps(ex, chosen, frames_with(ex.a, frames, id), scope)
        if ran.kind != OK { ret ran }
        var result = obj(ex.a)
        put(&result, "branch", text(branch))
        ret done(ir.obj_value(&result), true)
    }
    if str.eq(type_name, "foreach") {
        let (loop_entry, have_loop) = journal.loop_entry(ex.run, key)
        var list_of: []const json.Value = zero
        var recorded = false
        if have_loop {
            let (recorded_items, have_items) = present(loop_entry, "items")
            if have_items {
                let (xs, is_array) = ir.items_of(recorded_items)
                if is_array {
                    list_of = xs
                    recorded = true
                }
            }
        }
        if !recorded { list_of = resolve_items(ex, step, scope) }
        var cap = 10000i64
        let (cap_value, have_cap) = present(config, "cap")
        if have_cap {
            let (c, c_error) = ir_number(cap_value)
            if c_error { cap = 0i64 } else { cap = c }
        }
        if i64(list_of.len) > cap { ret fail_run("Foreach cap", "") }
        if !recorded {
            var f = obj(ex.a)
            put(&f, "key", text(key))
            put(&f, "stepId", text(id))
            put(&f, "count", usize_value(ex.a, list_of.len))
            put(&f, "items", json.Value{ Array: list_of })
            let index = record_obj(ex, "loop-started", f)
            let flushed = flush(ex)
            if flushed.kind != OK { ret flushed }
        }
        var alias = config_text(step, "as")
        if alias.len == 0usize { alias = "item" }
        var i = 0usize
        while i < list_of.len {
            let ran = exec_steps(ex, ir.value_of(step, "steps"), frames_with(ex.a, frames, loop_frame_text(ex, id, i)), loop_scope(ex, scope, alias, list_of, i))
            if ran.kind != OK { ret ran }
            i += 1usize
        }
        var result = obj(ex.a)
        put(&result, "count", usize_value(ex.a, list_of.len))
        ret done(ir.obj_value(&result), true)
    }
    if str.eq(type_name, "fork") {
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "stepId", text(id))
        let branches = items(ir.value_of(step, "branches"))
        let (names, names_error) = mem.alloc[json.Value](ex.a, branches.len + 1usize)
        if names_error != ok { ret signal(ERROR, "exhausted") }
        var b = 0usize
        while b < branches.len {
            names[b] = ir.value_of(branches[b], "name")
            b += 1usize
        }
        put(&f, "branches", json.Value{ Array: names[0usize..branches.len] })
        let index = record_obj(ex, "fork-started", f)
        let outcome = run_branches(ex, step, frames, scope)
        if outcome.kind != OK { ret outcome }
        ret outcome
    }
    if str.eq(type_name, "try") {
        let (caught, have_caught) = journal.branch(ex.run, key)
        if have_caught && str.eq(member_text(caught, "branch"), "catch") {
            let (error_value, have_error) = get(caught, "error")
            put(&ex.vars, "error", error_value)
            let ran = exec_steps(ex, ir.value_of(step, "catch"), frames_with(ex.a, frames, cat(ex.a, id, ":catch")), scope)
            if ran.kind != OK { ret ran }
            var result = obj(ex.a)
            put(&result, "caught", flag(true))
            put(&result, "error", ir.value_of(error_value, "message"))
            ret done(ir.obj_value(&result), true)
        }
        let ran = exec_steps(ex, ir.value_of(step, "steps"), frames_with(ex.a, frames, id), scope)
        if ran.kind == OK {
            var result = obj(ex.a)
            put(&result, "caught", flag(false))
            ret done(ir.obj_value(&result), true)
        }
        if ran.kind == SUSPEND || ran.kind == STALE || ran.kind == STOP || ran.kind == CANCEL { ret ran }
        var error_object = obj(ex.a)
        put(&error_object, "message", text(ran.message))
        if ran.has_step_id { put(&error_object, "stepId", text(ran.step_id)) }
        let error_value = ir.obj_value(&error_object)
        put(&ex.vars, "error", error_value)
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "stepId", text(id))
        put(&f, "branch", text("catch"))
        put(&f, "error", error_value)
        let index = record_obj(ex, "branch-taken", f)
        let flushed = flush(ex)
        if flushed.kind != OK { ret flushed }
        let handled = exec_steps(ex, ir.value_of(step, "catch"), frames_with(ex.a, frames, cat(ex.a, id, ":catch")), scope)
        if handled.kind != OK { ret handled }
        var result = obj(ex.a)
        put(&result, "caught", flag(true))
        put(&result, "error", text(ran.message))
        ret done(ir.obj_value(&result), true)
    }
    if str.eq(type_name, "stop") {
        var reason = member_text(config, "reason")
        if reason.len == 0usize { reason = "Stopped by stop" }
        ret signal(STOP, reason)
    }
    if str.eq(type_name, "fail") {
        var message = member_text(config, "message")
        if message.len == 0usize { message = "Failed by step" }
        ret fail_run(message, id)
    }
    if str.eq(type_name, "delay") { ret dispatch_delay(ex, step, key, config) }
    if str.eq(type_name, "wait-signal") { ret dispatch_wait(ex, step, key, config) }
    if str.eq(type_name, "approval") { ret dispatch_approval(ex, step, key, scope, config) }
    if str.eq(type_name, "set") {
        let (value, has_value) = get(config, "value")
        var resolved = value
        if !has_value {
            let (expression, have_expression) = present(ir.or_falsy(step, "config", json.Value{ Object: zero }), "expression")
            var source = ""
            if have_expression {
                let (s, is_text) = ir.string_of(expression)
                if is_text { source = s } else { source = scalar_text(expression) }
            }
            let (rendered, defined) = ex.hooks.render_value(ex.hooks.ctx, source, context(ex, scope))
            resolved = rendered
            if !defined { resolved = .Null }
        }
        let name = config_text(step, "name")
        put(&ex.vars, name, resolved)
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "name", text(name))
        let index = record_obj(ex, "var-set", f)
        var result = obj(ex.a)
        put(&result, name, resolved)
        ret done(ir.obj_value(&result), true)
    }
    if str.eq(type_name, "log") {
        var message = ""
        let (m, have_m) = get(config, "message")
        let (m_text, m_is_text) = ir.string_of(m)
        if have_m && m_is_text {
            message = m_text
        } else {
            let (raw, have_raw) = present(ir.or_falsy(step, "config", json.Value{ Object: zero }), "message")
            var source = ""
            if have_raw {
                let (s, is_text) = ir.string_of(raw)
                if is_text { source = s } else { source = scalar_text(raw) }
            }
            message = ex.hooks.render_text(ex.hooks.ctx, source, context(ex, scope))
        }
        var result = obj(ex.a)
        put(&result, "message", text(message))
        ret done(ir.obj_value(&result), true)
    }
    ret call_effect(ex, step, key, config, scope)
}

fn ir_number(v: json.Value) -> (i64, bool) {
    var out = 0i64
    var bad = true
    switch v {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e == ok {
            out = x
            bad = false
        }
    default:
        bad = true
    }
    ret (out, bad)
}

fn dispatch_delay(ex: *Executor, step: json.Value, key: str, config: json.Value) -> Flow {
    let id = step_id_of(step)
    var duration_source: json.Value = .Null
    let (duration, have_duration) = present(config, "duration")
    if have_duration {
        duration_source = duration
    } else {
        let (ms_value, have_ms) = present(config, "ms")
        if have_ms { duration_source = ms_value }
    }
    let (ms, have_ms_value) = parse_duration(duration_source)
    let (until, have_until) = get(config, "until")
    var wake_at = 0i64
    var wake_bad = false
    if have_until && ir.truthy(until) {
        // `Date.parse` of the text: the host's parser is outside; an ISO instant is parsed here as whole milliseconds.
        let (until_text, until_is_text) = ir.string_of(until)
        var s = until_text
        if !until_is_text { s = scalar_text(until) }
        let (parsed, parsed_ok) = parse_instant(s)
        wake_at = parsed
        wake_bad = !parsed_ok
    } else {
        let key_text = cat(ex.a, key, ":wake")
        let (recorded, have_recorded) = journal.recorded(ex.run, key_text)
        if journal.has_recorded(ex.run, key_text) {
            let (r, r_bad) = ir_number(recorded)
            if !r_bad { wake_at = r } else { wake_bad = true }
        } else {
            var delta = 0i64
            if have_ms_value { delta = i64(ms) }
            wake_at = ex.hooks.now(ex.hooks.ctx) + delta
            var f = obj(ex.a)
            put(&f, "key", text(key_text))
            put(&f, "value", number(ex.a, wake_at))
            let index = record_obj(ex, "clock", f)
        }
    }
    if !have_ms_value && !(have_until && ir.truthy(until)) { ret fail_run("Delay bad duration", "") }
    if wake_bad { ret fail_run("Delay bad until", "") }
    let now = ex.hooks.now(ex.hooks.ctx)
    if now >= wake_at {
        var result = obj(ex.a)
        put(&result, "wokeAt", number(ex.a, ex.hooks.now(ex.hooks.ctx)))
        put(&result, "wakeAt", number(ex.a, wake_at))
        ret done(ir.obj_value(&result), true)
    }
    var f = obj(ex.a)
    put(&f, "key", text(key))
    put(&f, "stepId", text(id))
    put(&f, "wakeAt", number(ex.a, wake_at))
    let index = record_obj(ex, "timer-set", f)
    var wait = obj(ex.a)
    put(&wait, "kind", text("timer"))
    put(&wait, "key", text(key))
    put(&wait, "stepId", text(id))
    put(&wait, "wakeAt", number(ex.a, wake_at))
    ret suspend(ir.obj_value(&wait))
}

// An ISO-8601 instant `YYYY-MM-DDTHH:MM[:SS[.mmm]]Z` (or a date alone) as epoch milliseconds, UTC.
fn parse_instant(s: str) -> (i64, bool) {
    if s.len < 10usize { ret (0i64, false) }
    let (year, ok_year) = digits(s, 0usize, 4usize)
    let (month, ok_month) = digits(s, 5usize, 2usize)
    let (day, ok_day) = digits(s, 8usize, 2usize)
    if !ok_year || !ok_month || !ok_day || s[4] != 45u8 || s[7] != 45u8 { ret (0i64, false) }
    if month < 1i64 || month > 12i64 || day < 1i64 || day > 31i64 { ret (0i64, false) }
    var hour = 0i64
    var minute = 0i64
    var second = 0i64
    var milli = 0i64
    var at = 10usize
    if s.len > 10usize {
        if s[10] != 84u8 || s.len < 16usize { ret (0i64, false) }
        let (h, ok_h) = digits(s, 11usize, 2usize)
        let (mi, ok_mi) = digits(s, 14usize, 2usize)
        if !ok_h || !ok_mi || s[13] != 58u8 { ret (0i64, false) }
        hour = h
        minute = mi
        at = 16usize
        if at < s.len && s[at] == 58u8 {
            let (sec, ok_sec) = digits(s, at + 1usize, 2usize)
            if !ok_sec { ret (0i64, false) }
            second = sec
            at += 3usize
            if at < s.len && s[at] == 46u8 {
                let (frac, ok_frac) = digits(s, at + 1usize, 3usize)
                if !ok_frac { ret (0i64, false) }
                milli = frac
                at += 4usize
            }
        }
        if at < s.len {
            if !(s[at] == 90u8 && at + 1usize == s.len) { ret (0i64, false) }
        }
    }
    // Days from civil (Howard Hinnant's algorithm), proleptic Gregorian.
    var y = year
    if month <= 2i64 { y = y - 1i64 }
    var era = y / 400i64
    if y < 0i64 { era = (y - 399i64) / 400i64 }
    let yoe = y - era * 400i64
    var mp = month + 9i64
    if month > 2i64 { mp = month - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + day - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    let days = era * 146097i64 + doe - 719468i64
    ret (((days * 24i64 + hour) * 60i64 + minute) * 60000i64 + second * 1000i64 + milli, true)
}

fn digits(s: str, from: usize, count: usize) -> (i64, bool) {
    if from + count > s.len { ret (0i64, false) }
    var value = 0i64
    var at = 0usize
    while at < count {
        let c = s[from + at]
        if c < 48u8 || c > 57u8 { ret (0i64, false) }
        value = value * 10i64 + i64(c - 48u8)
        at += 1usize
    }
    ret (value, true)
}

fn dispatch_wait(ex: *Executor, step: json.Value, key: str, config: json.Value) -> Flow {
    let id = step_id_of(step)
    let signal_name = config_text(step, "signal")
    let (received, have_received) = journal.signal(ex.run, key)
    if have_received {
        var result = obj(ex.a)
        put(&result, "signal", text(signal_name))
        let (payload, have_payload) = get(received, "payload")
        if have_payload { put(&result, "payload", payload) }
        let (at, have_at) = get(received, "at")
        if have_at { put(&result, "receivedAt", at) }
        ret done(ir.obj_value(&result), true)
    }
    let (timeout_ms, have_timeout) = parse_duration(ir.value_of(config, "timeout"))
    var timeout_at: json.Value = .Null
    var timeout_known = false
    var timeout_at_ms = 0i64
    if have_timeout && timeout_ms > 0.0f64 {
        let key_text = cat(ex.a, key, ":timeout")
        if journal.has_recorded(ex.run, key_text) {
            let (r, have_r) = journal.recorded(ex.run, key_text)
            let (n, bad) = ir_number(r)
            if !bad {
                timeout_at_ms = n
                timeout_known = true
            }
        } else {
            timeout_at_ms = ex.hooks.now(ex.hooks.ctx) + i64(timeout_ms)
            timeout_known = true
            var f = obj(ex.a)
            put(&f, "key", text(key_text))
            put(&f, "value", number(ex.a, timeout_at_ms))
            let index = record_obj(ex, "clock", f)
        }
        if timeout_known { timeout_at = number(ex.a, timeout_at_ms) }
    }
    if timeout_known && ex.hooks.now(ex.hooks.ctx) >= timeout_at_ms {
        var action = config_text(step, "timeoutAction")
        if action.len == 0usize { action = "fail" }
        if str.eq(action, "continue") {
            var result = obj(ex.a)
            put(&result, "signal", text(signal_name))
            put(&result, "timedOut", flag(true))
            ret done(ir.obj_value(&result), true)
        }
        ret fail_run("Wait timed out", id)
    }
    var f = obj(ex.a)
    put(&f, "key", text(key))
    put(&f, "stepId", text(id))
    put(&f, "signal", text(signal_name))
    put(&f, "timeoutAt", timeout_at)
    let index = record_obj(ex, "signal-awaited", f)
    var wait = obj(ex.a)
    put(&wait, "kind", text("signal"))
    put(&wait, "key", text(key))
    put(&wait, "stepId", text(id))
    put(&wait, "signal", text(signal_name))
    put(&wait, "timeoutAt", timeout_at)
    var resume = obj(ex.a)
    var label = member_text(config, "label")
    if label.len == 0usize { label = member_text(step, "name") }
    if label.len == 0usize { label = signal_name }
    put(&resume, "label", text(label))
    let (inputs, have_inputs) = present(config, "inputs")
    let empty: []const json.Member = zero
    if have_inputs && ir.truthy(inputs) { put(&resume, "inputs", inputs) } else { put(&resume, "inputs", json.Value{ Object: empty }) }
    put(&wait, "resume", ir.obj_value(&resume))
    ret suspend(ir.obj_value(&wait))
}

fn describe_label(ex: *Executor, step: json.Value, config: json.Value) -> str {
    let type_name = member_text(step, "type")
    if str.eq(type_name, "create-record") { ret "Create record in" }
    if str.eq(type_name, "update-record") { ret "Update record" }
    if str.eq(type_name, "delete-record") { ret "Delete record" }
    if str.eq(type_name, "webhook") {
        var method = member_text(config, "method")
        if method.len == 0usize { method = "POST" }
        ret cat3(ex.a, upper(ex.a, method), " ", member_text(config, "url"))
    }
    if str.eq(type_name, "connector") { ret cat3(ex.a, config_text(step, "channel"), ": ", config_text(step, "action")) }
    if str.eq(type_name, "mcpTool") { ret "Call tool" }
    if str.eq(type_name, "email") { ret "Email" }
    if str.eq(type_name, "notify") {
        let (to, have_to) = present(config, "to")
        let (to_text, to_is_text) = ir.string_of(to)
        if !have_to || (to_is_text && str.trim(to_text).len == 0usize) { ret "Notify owner" }
        ret "Notify"
    }
    if str.eq(type_name, "approval") { ret "Ask approval" }
    if str.eq(type_name, "python") { ret "Python" }
    if str.eq(type_name, "run-workflow") { ret "Start workflow" }
    ret "Run step"
}

fn upper(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

// A human-readable preview of a mutation for the dry-run summary: `{type, ..., summary, label}`.
fn describe_change(ex: *Executor, step: json.Value, config: json.Value) -> (json.Value, json.Value) {
    let type_name = member_text(step, "type")
    var o = obj(ex.a)
    var summary = obj(ex.a)
    put(&o, "type", text(type_name))
    let raw_config = ir.or_falsy(step, "config", json.Value{ Object: zero })
    if str.eq(type_name, "create-record") || str.eq(type_name, "update-record") || str.eq(type_name, "delete-record") {
        let (table, have_table) = get(config, "table")
        if have_table { put(&o, "table", table) }
        if !str.eq(type_name, "create-record") {
            let (aim, have_aim) = present(config, "target")
            if have_aim {
                put(&o, "target", aim)
            } else {
                let (id_value, have_id) = get(config, "id")
                if have_id { put(&o, "target", id_value) }
            }
        }
        if !str.eq(type_name, "delete-record") {
            let (values, have_values) = get(config, "values")
            if have_values { put(&o, "values", values) }
        }
        if have_table { put(&summary, "table", table) }
    } else if str.eq(type_name, "webhook") {
        var method = member_text(config, "method")
        if method.len == 0usize { method = "POST" }
        put(&o, "method", text(method))
        let (url, have_url) = get(config, "url")
        if have_url { put(&o, "url", url) }
        let (body, have_body) = get(config, "body")
        if have_body { put(&o, "body", body) }
        if have_url { put(&summary, "url", url) }
    } else if str.eq(type_name, "connector") {
        let (channel, have_channel) = get(raw_config, "channel")
        let (action, have_action) = get(raw_config, "action")
        if have_channel { put(&o, "channel", channel) }
        if have_action { put(&o, "action", action) }
        put(&o, "params", config)
        if have_channel { put(&summary, "channel", channel) }
        if have_action { put(&summary, "action", action) }
    } else if str.eq(type_name, "mcpTool") {
        let (connection, have_connection) = get(raw_config, "connectionId")
        let (tool, have_tool) = get(raw_config, "tool")
        if have_connection { put(&o, "connectionId", connection) }
        if have_tool { put(&o, "tool", tool) }
        let empty: []const json.Member = zero
        put(&o, "arguments", ir.or_falsy(config, "arguments", json.Value{ Object: empty }))
        if have_connection { put(&summary, "connectionId", connection) }
        if have_tool { put(&summary, "tool", tool) }
    } else if str.eq(type_name, "email") {
        let (to, have_to) = get(config, "to")
        if have_to { put(&o, "to", to) }
        let (subject, have_subject) = get(config, "subject")
        if have_subject { put(&o, "subject", subject) }
        if have_to { put(&summary, "to", to) }
    } else if str.eq(type_name, "notify") {
        let (to, have_to) = get(config, "to")
        if have_to { put(&o, "to", to) }
        if have_to { put(&summary, "to", to) }
    } else if str.eq(type_name, "approval") {
        let approvers = ir.or_falsy(config, "approvers", json.Value{ Array: zero })
        let (table, have_table) = get(raw_config, "table")
        if have_table { put(&o, "table", table) }
        let (record_value, have_record) = get(config, "record")
        if have_record { put(&o, "record", record_value) }
        put(&o, "approvers", approvers)
        var rule = text("any")
        let (rule_value, have_rule) = get(raw_config, "rule")
        if have_rule && ir.truthy(rule_value) { rule = rule_value }
        put(&o, "rule", rule)
        put(&summary, "approvers", usize_value(ex.a, items(approvers).len))
        put(&summary, "rule", rule)
    } else if str.eq(type_name, "run-workflow") {
        let (workflow_id, have_workflow) = get(raw_config, "workflowId")
        if have_workflow { put(&o, "workflowId", workflow_id) }
        if have_workflow { put(&summary, "workflowId", workflow_id) }
    }
    put(&o, "summary", ir.obj_value(&summary))
    put(&o, "label", text(describe_label(ex, step, config)))
    ret (ir.obj_value(&o), ir.obj_value(&summary))
}

fn dispatch_approval(ex: *Executor, step: json.Value, key: str, scope: json.Value, config: json.Value) -> Flow {
    let id = step_id_of(step)
    let signal_name = approval_signal(ex.a, key)
    let (received, have_received) = journal.signal(ex.run, key)
    if have_received {
        let payload = ir.or_falsy(received, "payload", json.Value{ Object: zero })
        let check = check_approval_evidence(ex, step, key, payload, true)
        if check.kind != OK { ret check }
        var result = obj(ex.a)
        let assigned = ir.assign(&result, payload)
        put(&result, "signal", text(signal_name))
        let (at, have_at) = get(received, "at")
        if have_at { put(&result, "receivedAt", at) }
        put(&result, "approved", flag(str.eq(member_text(payload, "decision"), "approved")))
        ret done(ir.obj_value(&result), true)
    }
    let (timeout_ms, have_timeout) = parse_duration(ir.value_of(config, "timeout"))
    var timeout_at: json.Value = .Null
    var timeout_known = false
    var timeout_at_ms = 0i64
    if have_timeout && timeout_ms > 0.0f64 {
        let key_text = cat(ex.a, key, ":timeout")
        if journal.has_recorded(ex.run, key_text) {
            let (r, have_r) = journal.recorded(ex.run, key_text)
            let (n, bad) = ir_number(r)
            if !bad {
                timeout_at_ms = n
                timeout_known = true
            }
        } else {
            timeout_at_ms = ex.hooks.now(ex.hooks.ctx) + i64(timeout_ms)
            timeout_known = true
            var f = obj(ex.a)
            put(&f, "key", text(key_text))
            put(&f, "value", number(ex.a, timeout_at_ms))
            let index = record_obj(ex, "clock", f)
        }
        if timeout_known { timeout_at = number(ex.a, timeout_at_ms) }
    }
    if timeout_known && ex.hooks.now(ex.hooks.ctx) >= timeout_at_ms {
        var action = config_text(step, "timeoutAction")
        if action.len == 0usize { action = "fail" }
        if str.eq(action, "continue") {
            var result = obj(ex.a)
            put(&result, "signal", text(signal_name))
            put(&result, "timedOut", flag(true))
            put(&result, "decision", .Null)
            put(&result, "approved", flag(false))
            ret done(ir.obj_value(&result), true)
        }
        ret fail_run("Approval timed out", id)
    }
    if str.eq(member_text(ex.run, "mode"), "dry-run") {
        let (preview, summary) = describe_change(ex, step, config)
        push_value(&ex.changes, preview)
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "stepId", text(id))
        put(&f, "stepType", text("approval"))
        put(&f, "preview", preview)
        let index = record_obj(ex, "effect-recorded", f)
        var result = obj(ex.a)
        put(&result, "dryRun", flag(true))
        put(&result, "asked", ir.or_falsy(config, "approvers", json.Value{ Array: zero }))
        put(&result, "decision", .Null)
        put(&result, "approved", flag(false))
        ret done(ir.obj_value(&result), true)
    }
    let approval_key = cat(ex.a, key, ":approval")
    var approval_id: json.Value = .Null
    var have_approval_id = false
    if journal.has_recorded(ex.run, approval_key) {
        let (r, have_r) = journal.recorded(ex.run, approval_key)
        if have_r {
            approval_id = r
            have_approval_id = true
        }
    }
    if !have_approval_id {
        var request = obj(ex.a)
        let assigned = ir.assign(&request, config)
        put(&request, "signal", text(signal_name))
        put(&request, "stepId", text(id))
        put(&request, "executionKey", text(key))
        let created = call_handler(ex, step, key, ir.obj_value(&request), scope)
        if created.kind != OK { ret created }
        var made: json.Value = .Null
        var have_made = false
        if created.has_value {
            let (aid, have_aid) = present(created.value, "approvalId")
            if have_aid && ir.truthy(aid) {
                made = aid
                have_made = true
            } else {
                let (plain, have_plain) = present(created.value, "id")
                if have_plain && ir.truthy(plain) {
                    made = plain
                    have_made = true
                }
            }
        }
        if !have_made { ret fail_run("Approval not created", id) }
        approval_id = made
        var f = obj(ex.a)
        put(&f, "key", text(approval_key))
        put(&f, "value", approval_id)
        let index = record_obj(ex, "clock", f)
        let flushed = flush(ex)
        if flushed.kind != OK { ret flushed }
    }
    var f = obj(ex.a)
    put(&f, "key", text(key))
    put(&f, "stepId", text(id))
    put(&f, "signal", text(signal_name))
    put(&f, "timeoutAt", timeout_at)
    let index = record_obj(ex, "signal-awaited", f)
    var wait = obj(ex.a)
    put(&wait, "kind", text("signal"))
    put(&wait, "key", text(key))
    put(&wait, "stepId", text(id))
    put(&wait, "signal", text(signal_name))
    put(&wait, "timeoutAt", timeout_at)
    put(&wait, "approvalId", approval_id)
    ret suspend(ir.obj_value(&wait))
}

// Run the fork's branches in declaration order, each to its own resting point, then judge the lot as appdor does.
fn run_branches(ex: *Executor, step: json.Value, frames: []const str, scope: json.Value) -> Flow {
    let id = step_id_of(step)
    let branches = items(ir.value_of(step, "branches"))
    var join = config_text(step, "join")
    if join.len == 0usize { join = "all" }
    let key = key_of(ex, id, frames)
    var completed = 0usize
    var done_names = obj(ex.a)
    let (name_list, name_error) = list.init[json.Value](ex.a, branches.len + 1usize)
    var names = name_list
    let (wait_list, wait_error) = list.init[json.Value](ex.a, branches.len + 1usize)
    var waits = wait_list
    var failure = nothing()
    var have_failure = false
    var b = 0usize
    while b < branches.len {
        let name = member_text(branches[b], "name")
        let f = exec_steps(ex, ir.value_of(branches[b], "steps"), frames_with(ex.a, frames, fork_frame_text(ex, id, name)), scope)
        if f.kind == OK {
            completed += 1usize
            push_value(&names, text(name))
            var entry = obj(ex.a)
            put(&entry, "key", text(key))
            put(&entry, "stepId", text(id))
            put(&entry, "branch", text(name))
            let index = record_obj(ex, "fork-branch-completed", entry)
        } else if f.kind == SUSPEND {
            push_value(&waits, f.wait)
        } else if !have_failure {
            failure = f
            have_failure = true
        } else if f.kind == STALE && failure.kind != STALE {
            failure = f
        } else if f.kind == CANCEL && failure.kind != STALE && failure.kind != CANCEL {
            failure = f
        }
        b += 1usize
    }
    let flushed = flush(ex)
    if flushed.kind != OK { ret flushed }
    let suspension_count = waits.len
    if have_failure {
        if failure.kind == STALE || failure.kind == CANCEL { ret failure }
        if failure.kind == STOP && !str.eq(join, "all") { ret failure }
        if str.eq(join, "all") || (completed == 0usize && suspension_count == 0usize) { ret failure }
    }
    var result = obj(ex.a)
    put(&result, "joined", usize_value(ex.a, completed))
    put(&result, "join", text(join))
    put(&result, "branches", json.Value{ Array: list.slice_const[json.Value](&names) })
    if completed > 0usize && (str.eq(join, "any") || str.eq(join, "race")) { ret done(ir.obj_value(&result), true) }
    if suspension_count > 0usize {
        // The earliest wake first; the rest ride along as siblings.
        var first = 0usize
        var best = wake_of(waits.items[0])
        var w = 1usize
        while w < suspension_count {
            let candidate = wake_of(waits.items[w])
            if candidate < best {
                best = candidate
                first = w
            }
            w += 1usize
        }
        var wait = obj(ex.a)
        let assigned = ir.assign(&wait, waits.items[first])
        let (siblings, sibling_error) = list.init[json.Value](ex.a, suspension_count + 1usize)
        var rest = siblings
        var s = 0usize
        while s < suspension_count {
            if s != first { push_value(&rest, waits.items[s]) }
            s += 1usize
        }
        put(&wait, "siblings", json.Value{ Array: list.slice_const[json.Value](&rest) })
        ret suspend(ir.obj_value(&wait))
    }
    ret done(ir.obj_value(&result), true)
}

// The instant a wait wakes at: `wakeAt`, else `timeoutAt`, else never.
fn wake_of(wait: json.Value) -> i64 {
    let (wake, have_wake) = present(wait, "wakeAt")
    if have_wake {
        let (n, bad) = ir_number(wake)
        if !bad { ret n }
    }
    let (timeout, have_timeout) = present(wait, "timeoutAt")
    if have_timeout {
        let (n, bad) = ir_number(timeout)
        if !bad { ret n }
    }
    ret 9223372036854775807i64
}

// Hand a step to its effect handler, with the outbound check, the dry-run gate and retries.
fn call_effect(ex: *Executor, step: json.Value, key: str, config: json.Value, scope: json.Value) -> Flow {
    let type_name = member_text(step, "type")
    let id = step_id_of(step)
    if str.eq(type_name, "webhook") {
        let (url, have_url) = present(config, "url")
        var url_text = ""
        var have_text = false
        if have_url {
            let (s, is_text) = ir.string_of(url)
            if is_text {
                url_text = s
            } else {
                url_text = scalar_text(url)
            }
            have_text = url_text.len > 0usize
        }
        if have_text {
            let verdict = ex.hooks.check_url(ex.hooks.ctx, url_text)
            if verdict.refusal.len > 0usize {
                var f = signal(ERROR, cat3(ex.a, type_name, " step ", verdict.refusal))
                f.reason = "permanent"
                ret f
            }
            if verdict.unchecked_host.len > 0usize {
                var seen = false
                var u = 0usize
                while u < ex.unchecked.len {
                    if str.eq(ex.unchecked.items[u], verdict.unchecked_host) { seen = true }
                    u += 1usize
                }
                if !seen {
                    let pushed = list.push[str](&ex.unchecked, verdict.unchecked_host)
                }
            }
        }
    }
    var mutates = true
    let info = ir.core_step(type_name)
    if info.found { mutates = info.mutates }
    if str.eq(member_text(ex.run, "mode"), "dry-run") && mutates {
        let (preview, summary) = describe_change(ex, step, config)
        push_value(&ex.changes, preview)
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "stepId", text(id))
        put(&f, "stepType", text(type_name))
        put(&f, "preview", preview)
        let index = record_obj(ex, "effect-recorded", f)
        var result = obj(ex.a)
        put(&result, "dryRun", flag(true))
        let assigned = ir.assign(&result, summary)
        ret done(ir.obj_value(&result), true)
    }
    ret call_handler(ex, step, key, config, scope)
}

// The retry loop around a handler. Only the retried attempts are journaled here; the last one is raised to the step.
fn call_handler(ex: *Executor, step: json.Value, key: str, config: json.Value, scope: json.Value) -> Flow {
    let type_name = member_text(step, "type")
    let id = step_id_of(step)
    var handled_type = type_name
    var has_handler = ex.hooks.has_effect(ex.hooks.ctx, type_name)
    if !has_handler {
        var dotted = false
        var at = 0usize
        while at < type_name.len {
            if type_name[at] == 46u8 { dotted = true }
            at += 1usize
        }
        if dotted && ex.hooks.has_effect(ex.hooks.ctx, "extension") {
            has_handler = true
            handled_type = "extension"
        }
    }
    if !has_handler {
        let reason = cat(ex.a, "no-handler:", type_name)
        var f = obj(ex.a)
        put(&f, "key", text(key))
        put(&f, "stepId", text(id))
        put(&f, "reason", text(reason))
        let index = record_obj(ex, "step-skipped", f)
        var result = obj(ex.a)
        put(&result, "skipped", flag(true))
        put(&result, "reason", text(reason))
        ret done(ir.obj_value(&result), true)
    }
    // Retry policy: the defaults overridden by the workflow's settings.
    var attempts = 3i64
    var backoff_ms = 1000.0f64
    var multiplier = 2.0f64
    var max_backoff = 60000.0f64
    let settings = ir.value_of(ex.workflow, "settings")
    let policy = ir.value_of(settings, "retryPolicy")
    let (a_value, have_a) = present(policy, "attempts")
    if have_a {
        let (n, bad) = ir_number(a_value)
        if !bad { attempts = n }
    }
    let (b_value, have_b) = present(policy, "backoffMs")
    if have_b { backoff_ms = value_f64(b_value, backoff_ms) }
    let (m_value, have_m) = present(policy, "multiplier")
    if have_m { multiplier = value_f64(m_value, multiplier) }
    let (x_value, have_x) = present(policy, "maxBackoffMs")
    if have_x { max_backoff = value_f64(x_value, max_backoff) }
    var max_attempts = attempts
    let (retries, have_retries) = present(step, "retries")
    if have_retries {
        let (n, bad) = ir_number(retries)
        if !bad { max_attempts = n }
    }
    let already = i64(journal.failure_count(ex.run, key))
    var last_error = ""
    var have_error = false
    var attempt = already + 1i64
    while attempt <= max_attempts {
        var request = obj(ex.a)
        put(&request, "config", config)
        put(&request, "step", step)
        var extra = obj(ex.a)
        let assigned = ir.assign(&extra, scope)
        put(&extra, "attempt", number(ex.a, attempt))
        put(&request, "context", context(ex, ir.obj_value(&extra)))
        put(&request, "idempotencyKey", text(cat3(ex.a, member_text(ex.run, "runId"), ":", key)))
        put(&request, "runId", ir.or_falsy(ex.run, "runId", .Null))
        put(&request, "attempt", number(ex.a, attempt))
        let answered = ex.hooks.effect(ex.hooks.ctx, handled_type, ir.obj_value(&request))
        if !answered.failed {
            if answered.has_result { ret done(answered.result, true) }
            ret nothing()
        }
        last_error = answered.detail
        have_error = true
        if answered.permanent { break }
        if attempt < max_attempts {
            var f = obj(ex.a)
            put(&f, "key", text(key))
            put(&f, "stepId", text(id))
            put(&f, "attempt", number(ex.a, attempt))
            put(&f, "at", number(ex.a, ex.hooks.now(ex.hooks.ctx)))
            put(&f, "error", text(last_error))
            let index = record_obj(ex, "step-failed", f)
            let flushed = flush(ex)
            if flushed.kind != OK { ret flushed }
            var delay = backoff_ms
            var p = 1i64
            while p < attempt {
                delay = delay * multiplier
                p += 1i64
            }
            if delay > max_backoff { delay = max_backoff }
            ex.hooks.sleep(ex.hooks.ctx, i64(delay))
        }
        attempt += 1i64
    }
    if have_error { ret signal(ERROR, last_error) }
    ret signal(ERROR, "Attempts exhausted")
}

fn value_f64(v: json.Value, fallback: f64) -> f64 {
    var out = fallback
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok { out = x }
    default:
        out = fallback
    }
    ret out
}

// --- the driver -----------------------------------------------------------------------------------------------------

fn result_object(ex: *Executor, status: str) -> ir.Obj {
    var o = obj(ex.a)
    put(&o, "run", ex.run)
    put(&o, "status", text(status))
    put(&o, "changes", json.Value{ Array: list.slice_const[json.Value](&ex.changes) })
    let (hosts, hosts_error) = list.init[json.Value](ex.a, ex.unchecked.len + 1usize)
    var rendered = hosts
    var at = 0usize
    while at < ex.unchecked.len {
        push_value(&rendered, text(ex.unchecked.items[at]))
        at += 1usize
    }
    put(&o, "uncheckedHosts", json.Value{ Array: list.slice_const[json.Value](&rendered) })
    ret o
}

fn finish(ex: *Executor, kind: str, fields: ir.Obj, patch: ir.Obj) {
    var f = fields
    let index = record(ex, kind, ir.obj_value(&f))
    var p = patch
    let set = journal.set_header(&ex.commit, ir.obj_value(&p))
}

// Execute a run until it finishes, fails or parks; call it again unchanged to resume. `definition` is the workflow
// (normalized here), `run` the journal's run record, and the result `{run, status, changes, uncheckedHosts, ...}`.
fn execute_run(a: *mem.Arena, hooks: *const Hooks, store: *journal.Store, definition: json.Value, run: json.Value) -> (json.Value, err) {
    let (workflow, workflow_error) = ir.normalize_workflow(a, definition)
    if workflow_error != ok { ret (.Null, workflow_error) }
    let (commit, commit_error) = journal.begin_commit(a, run)
    if commit_error != ok { ret (.Null, commit_error) }
    let (changes, changes_error) = list.init[json.Value](a, 8usize)
    if changes_error != ok { ret (.Null, changes_error) }
    let (unchecked, unchecked_error) = list.init[str](a, 4usize)
    if unchecked_error != ok { ret (.Null, unchecked_error) }
    var budget = 10000usize
    let settings = ir.value_of(workflow, "settings")
    let (max_steps, have_max) = present(settings, "maxSteps")
    if have_max {
        let (n, bad) = ir_number(max_steps)
        if !bad && n >= 0i64 { budget = usize(n) }
    }
    var ex = Executor {
        a: a, hooks: hooks, store: store, workflow: workflow, run: run, commit: commit,
        vars: obj(a), outputs: obj(a), changes: changes, unchecked: unchecked, step_budget: budget, steps_run: 0usize,
    }
    let status = member_text(run, "status")
    var started = true
    // The prologue is inside the same unwinding as the steps: its flush is where a second owner is discovered.
    var prologue = nothing()
    if str.eq(status, "pending") {
        var f = obj(a)
        put(&f, "at", number(a, hooks.now(hooks.ctx)))
        let index = record_obj(&ex, "run-started", f)
        var patch = obj(a)
        put(&patch, "status", text("running"))
        let (started_at, have_started) = present(run, "startedAt")
        if have_started { put(&patch, "startedAt", started_at) } else { put(&patch, "startedAt", number(a, hooks.now(hooks.ctx))) }
        put(&patch, "metered", number(a, 1i64))
        let set = journal.set_header(&ex.commit, ir.obj_value(&patch))
        prologue = flush(&ex)
    } else if str.eq(status, "suspended") || str.eq(status, "paused") {
        var f = obj(a)
        put(&f, "at", number(a, hooks.now(hooks.ctx)))
        let index = record_obj(&ex, "run-resumed", f)
        var patch = obj(a)
        put(&patch, "status", text("running"))
        put(&patch, "waiting", .Null)
        let set = journal.set_header(&ex.commit, ir.obj_value(&patch))
        prologue = flush(&ex)
    }
    var outcome = prologue
    if outcome.kind == OK {
        var no_frames: []const str = zero
        outcome = exec_steps(&ex, ir.value_of(workflow, "steps"), no_frames, json.Value{ Object: zero })
        if outcome.kind == OK { outcome = assert_control(&ex) }
    }
    if outcome.kind == OK {
        var f = obj(a)
        put(&f, "at", number(a, hooks.now(hooks.ctx)))
        var patch = obj(a)
        put(&patch, "status", text("succeeded"))
        put(&patch, "finishedAt", number(a, hooks.now(hooks.ctx)))
        put(&patch, "waiting", .Null)
        finish(&ex, "run-completed", f, patch)
        let flushed = flush(&ex)
        let out = result_object(&ex, "succeeded")
        ret (ir.obj_value(&out), ok)
    }
    if outcome.kind == SUSPEND {
        let paused = str.eq(member_text(outcome.wait, "kind"), "paused")
        var patch = obj(a)
        if paused {
            var f = obj(a)
            put(&f, "at", number(a, hooks.now(hooks.ctx)))
            let index = record_obj(&ex, "run-paused", f)
            put(&patch, "status", text("paused"))
            put(&patch, "pauseRequested", flag(false))
            put(&patch, "waiting", outcome.wait)
        } else {
            put(&patch, "status", text("suspended"))
            put(&patch, "waiting", outcome.wait)
        }
        let set = journal.set_header(&ex.commit, ir.obj_value(&patch))
        let flushed = flush(&ex)
        var out = result_object(&ex, choose(paused, "paused", "suspended"))
        put(&out, "suspension", outcome.wait)
        ret (ir.obj_value(&out), ok)
    }
    if outcome.kind == CANCEL {
        var f = obj(a)
        put(&f, "at", number(a, hooks.now(hooks.ctx)))
        put(&f, "reason", text(outcome.message))
        var patch = obj(a)
        put(&patch, "status", text("cancelled"))
        put(&patch, "finishedAt", number(a, hooks.now(hooks.ctx)))
        put(&patch, "waiting", .Null)
        put(&patch, "cancelRequested", flag(false))
        finish(&ex, "run-cancelled", f, patch)
        let flushed = flush(&ex)
        var out = result_object(&ex, "cancelled")
        put(&out, "reason", text(outcome.message))
        ret (ir.obj_value(&out), ok)
    }
    if outcome.kind == STOP {
        var f = obj(a)
        put(&f, "at", number(a, hooks.now(hooks.ctx)))
        put(&f, "reason", text(outcome.message))
        var patch = obj(a)
        put(&patch, "status", text("succeeded"))
        put(&patch, "finishedAt", number(a, hooks.now(hooks.ctx)))
        put(&patch, "waiting", .Null)
        finish(&ex, "run-completed", f, patch)
        let flushed = flush(&ex)
        var out = result_object(&ex, "succeeded")
        put(&out, "stopped", text(outcome.message))
        ret (ir.obj_value(&out), ok)
    }
    if outcome.kind == STALE {
        var out = result_object(&ex, "conflict")
        put(&out, "reason", text(outcome.message))
        ret (ir.obj_value(&out), ok)
    }
    // A failure: the run is recorded failed with the message and, when the step named them, its id and reason.
    var f = obj(a)
    put(&f, "at", number(a, hooks.now(hooks.ctx)))
    put(&f, "error", text(outcome.message))
    if outcome.has_step_id { put(&f, "stepId", text(outcome.step_id)) }
    if outcome.reason.len > 0usize && !str.eq(outcome.reason, "permanent") { put(&f, "reason", text(outcome.reason)) }
    var patch = obj(a)
    put(&patch, "status", text("failed"))
    put(&patch, "finishedAt", number(a, hooks.now(hooks.ctx)))
    put(&patch, "error", text(outcome.message))
    put(&patch, "waiting", .Null)
    finish(&ex, "run-failed", f, patch)
    let flushed = flush(&ex)
    var out = result_object(&ex, "failed")
    put(&out, "error", text(outcome.message))
    if outcome.reason.len > 0usize && !str.eq(outcome.reason, "permanent") {
        put(&out, "reason", text(outcome.reason))
        var b = obj(a)
        put(&b, "reason", text(outcome.reason))
        put(&b, "kind", text("step-budget"))
        if outcome.has_budget { put(&b, "budget", usize_value(a, outcome.budget)) }
        put(&out, "budget", ir.obj_value(&b))
    }
    ret (ir.obj_value(&out), ok)
}

fn choose(c: bool, yes: str, no: str) -> str {
    if c { ret yes }
    ret no
}
