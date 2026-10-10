// The inline flow interpreter (L036, the runtime half), after appdor's `src/workflow/flow-engine.js`: a flat flow -- one
// trigger and an ordered graph of steps -- executed synchronously against a trigger context and answered as a step-level
// run log. It is what transition post-functions run on: a graph executed inline, now, inside a transaction the caller
// already holds, with the step budget, the cascade guard and the trace, where a durable run would leave the assignment
// pending. Durable waits are `e.algo.workflow`'s job, so there is deliberately no `delay` here.
//
// Steps: `condition` (a formula string, `{expr}` or a filter tree; false stops the flow unless `onFalse` says otherwise),
// `branch`, `loop` (with its iteration cap), `find`, `set`, `create`/`update`/`delete`, `email`/`notification`/`http`
// (retried, secrets redacted from the log), `script`, `ai`, `run-workflow` (under a cascade depth limit), and an unknown
// type, which ends the run `failed` with reason `unknown_step` rather than reading as success. A value spec is
// `{literal}`, `{binding: "path"}`, `{formula: "expr"}` or a raw primitive. A budget exhausted anywhere, inside a loop
// included, ends the run `terminated` with reason `budget_exceeded` and the trace left intact.
//
// What is outside is injected as `Hooks`: the effect handlers (`findRecords`, `createRecord`, `updateRecord`,
// `deleteRecord`, `email`, `notify`, `http`, `runWorkflow`), the view engine for filter trees, the script runner and the
// AI step runtime. Formulas run on `e.algo.formula` over the flow's fields (trigger, loop item and variables, in that
// order of precedence from last to first).
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.formula as f
use e.algo.formula.library as library
use e.algo.ir as ir
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

// What an effect handler answered: `present` false when the host has none for the name.
type Effect = struct { present: bool, failed: bool, permanent: bool, message: str, code: str, has_code: bool, has_value: bool, value: json.Value }

// A script or AI step's outcome, for the engine's bookkeeping: `status` is the log status ("success", "failed",
// "dry-run" or "skipped"), `output` what the entry records, `typed` what the flow reads afterwards.
type Stepped = struct { status: str, code: str, has_code: bool, message: str, output: json.Value, has_output: bool, typed: json.Value, has_typed: bool }

type Hooks = struct { ctx: *void, effect: fn(*void, str, json.Value) -> Effect, filter_matches: fn(*void, json.Value, json.Value) -> bool, dataset_find: fn(*void, str, json.Value, json.Value, json.Value) -> (json.Value, bool), script: fn(*void, json.Value, json.Value) -> Stepped, ai: fn(*void, json.Value, json.Value, json.Value, str, bool) -> Stepped }

// The outcome of a step list: "continue", "stopped", "failed", "terminated" or "cascade-exceeded", with a reason.
type Control = struct { status: str, reason: str }

type Runner = struct { a: *mem.Arena, hooks: *const Hooks, reg: *const f.Registry, steps: list.List[json.Value], vars: ir.Obj, step_outputs: ir.Obj, reason: str, has_reason: bool, budget: json.Value, has_budget: bool, step_budget: usize, max_depth: i64, depth: i64, dry_run: json.Value, on_failure: str, error_branch: json.Value, has_error_branch: bool, refs: json.Value, dataset: json.Value }

// A loop frame: the current item and its index, `has` false at the top level.
type Frame = struct { trigger: json.Value, trigger_meta: json.Value, current: json.Value, has_current: bool, index: usize }

fn carry() -> Control { ret Control { status: "continue", reason: "" } }

fn ended(status: str, reason: str) -> Control { ret Control { status: status, reason: reason } }

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn flag(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { ret json.Value{ Number: json.Number{ lexeme: "0" } } }
    ret json.Value{ Number: v }
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { ret ir.Obj { items: zero, len: 0usize, arena: a } }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

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

fn empty_object() -> json.Value {
    var none: []const json.Member = zero
    ret json.Value{ Object: none }
}

// `x != null`, as a member: present and not null.
fn present(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = get(v, key)
    if !found || ir.is_null(x) { ret (.Null, false) }
    ret (x, true)
}

// --- values and formulas --------------------------------------------------------------------------------------------

fn to_formula(a: *mem.Arena, v: json.Value) -> f.Value {
    switch v {
    case .Null:
        ret f.blank()
    case .Bool as b:
        ret f.boolean(b)
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret f.blank() }
        ret f.number(x)
    case .String as s:
        ret f.text(s)
    case .Array as xs:
        let (out, out_error) = mem.alloc[f.Value](a, xs.len + 1usize)
        if out_error != ok { ret f.blank() }
        var at = 0usize
        while at < xs.len {
            out[at] = to_formula(a, xs[at])
            at += 1usize
        }
        ret f.array(out[0usize..xs.len])
    case .Object as m:
        ret f.blank()
    }
}

// A formula result as JSON: an error or a blank is null, an array element by element.
fn from_formula(a: *mem.Arena, v: f.Value) -> json.Value {
    if f.is_error(v) { ret .Null }
    switch v.kind {
    case .Blank:
        ret .Null
    case .Number:
        ret number_value(a, v.n)
    case .Text:
        ret text(v.s)
    case .Bool:
        ret flag(v.n != 0.0f64)
    case .Date:
        ret number_value(a, v.n)
    case .Array:
        let (out, out_error) = mem.alloc[json.Value](a, v.items.len + 1usize)
        if out_error != ok { ret .Null }
        var at = 0usize
        while at < v.items.len {
            out[at] = from_formula(a, v.items[at])
            at += 1usize
        }
        ret json.Value{ Array: out[0usize..v.items.len] }
    default:
        ret .Null
    }
}

fn number_value(a: *mem.Arena, x: f64) -> json.Value {
    let (n, e) = json.number_from_f64(a, x)
    if e != ok { ret .Null }
    ret json.Value{ Number: n }
}

// `{...trigger, ...current, ...vars}` as formula fields.
fn binding_fields(r: *Runner, frame: Frame) -> []const f.Field {
    let (out, out_error) = list.init[f.Field](r.a, 16usize)
    if out_error != ok { ret zero }
    var fields = out
    var layers: [3]json.Value = zero
    layers[0] = frame.trigger
    layers[1] = .Null
    if frame.has_current { layers[1] = frame.current }
    layers[2] = ir.obj_value(&r.vars)
    var l = 0usize
    while l < 3usize {
        let (members, is_object) = ir.members_of(layers[l])
        if is_object {
            var m = 0usize
            while m < members.len {
                var found = false
                var k = 0usize
                while k < fields.len {
                    if str.eq(fields.items[k].name, members[m].key) {
                        fields.items[k].value = to_formula(r.a, members[m].value)
                        found = true
                    }
                    k += 1usize
                }
                if !found {
                    let pushed = list.push[f.Field](&fields, f.Field { name: members[m].key, value: to_formula(r.a, members[m].value) })
                }
                m += 1usize
            }
        }
        l += 1usize
    }
    ret list.slice_const[f.Field](&fields)
}

fn evaluate(r: *Runner, frame: Frame, source: str) -> f.Value {
    var c: f.Context = zero
    c.fields = binding_fields(r, frame)
    ret f.evaluate(r.a, source, &c, r.reg)
}

// The flow's truthiness: errors and blanks false, zero false, an empty text or array false, everything else true.
fn truthy_formula(v: f.Value) -> bool {
    if f.is_error(v) { ret false }
    switch v.kind {
    case .Blank:
        ret false
    case .Number:
        ret v.n != 0.0f64
    case .Text:
        ret v.s.len > 0usize
    case .Bool:
        ret v.n != 0.0f64
    case .Array:
        ret v.items.len > 0usize
    default:
        ret true
    }
}

fn truthy_json(v: json.Value) -> bool {
    switch v {
    case .Null:
        ret false
    case .Bool as b:
        ret b
    case .Number as n:
        ret ir.truthy(v)
    case .String as s:
        ret s.len > 0usize
    case .Array as xs:
        ret xs.len > 0usize
    default:
        ret true
    }
}

// The context as an object for a `binding`: `{trigger, triggerMeta, steps, vars, depth[, current, index]}`.
fn context_value(r: *Runner, frame: Frame) -> json.Value {
    var c = obj(r.a)
    put(&c, "trigger", frame.trigger)
    put(&c, "triggerMeta", frame.trigger_meta)
    put(&c, "steps", ir.obj_value(&r.step_outputs))
    put(&c, "vars", ir.obj_value(&r.vars))
    put(&c, "depth", number(r.a, r.depth))
    if frame.has_current {
        put(&c, "current", frame.current)
        put(&c, "index", number(r.a, i64(frame.index)))
    }
    ret ir.obj_value(&c)
}

// `getPath`: dotted names through objects and array indexes; absent when anything on the way is missing or null.
fn get_path(root: json.Value, path: str) -> (json.Value, bool) {
    var current = root
    var begin = 0usize
    var at = 0usize
    while at <= path.len {
        if at == path.len || path[at] == 46u8 {
            let name = path[begin..at]
            if ir.is_null(current) { ret (.Null, false) }
            let (members, is_object) = ir.members_of(current)
            let (elements, is_array) = ir.items_of(current)
            if is_object {
                let (next, found) = get(current, name)
                if !found { ret (.Null, false) }
                current = next
            } else if is_array {
                var index = 0usize
                var good = name.len > 0usize
                var c = 0usize
                while c < name.len {
                    if name[c] < 48u8 || name[c] > 57u8 { good = false } else { index = index * 10usize + usize(name[c] - 48u8) }
                    c += 1usize
                }
                if !good || index >= elements.len { ret (.Null, false) }
                current = elements[index]
            } else {
                ret (.Null, false)
            }
            begin = at + 1usize
        }
        at += 1usize
    }
    ret (current, true)
}

// A value spec resolved: absent (false) when a binding finds nothing.
fn resolve_value(r: *Runner, frame: Frame, spec: json.Value) -> (json.Value, bool) {
    let (members, is_object) = ir.members_of(spec)
    if !is_object { ret (spec, true) }
    let (literal, has_literal) = get(spec, "literal")
    if has_literal { ret (literal, true) }
    let (binding, has_binding) = get(spec, "binding")
    if has_binding {
        let (path, path_is_text) = ir.string_of(binding)
        var source = path
        if !path_is_text { source = scalar_text(binding) }
        let (found_value, found) = get_path(context_value(r, frame), source)
        ret (found_value, found)
    }
    let (formula, has_formula) = get(spec, "formula")
    if has_formula {
        let (source, source_is_text) = ir.string_of(formula)
        var s = source
        if !source_is_text { s = scalar_text(formula) }
        let value = evaluate(r, frame, s)
        ret (from_formula(r.a, value), true)
    }
    ret (spec, true)
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

// `resolveValues`: every member of a map spec resolved; an absent value is dropped as JSON drops undefined.
fn resolve_values(r: *Runner, frame: Frame, map: json.Value) -> json.Value {
    var o = obj(r.a)
    let (members, is_object) = ir.members_of(map)
    if is_object {
        var at = 0usize
        while at < members.len {
            let (v, found) = resolve_value(r, frame, members[at].value)
            if found { put(&o, members[at].key, v) }
            at += 1usize
        }
    }
    ret ir.obj_value(&o)
}

// A condition: absent is true, a string a formula, `{expr}` a formula, anything else a filter tree over the current item
// (or the trigger).
fn eval_condition(r: *Runner, frame: Frame, cond: json.Value, has: bool) -> bool {
    if !has || ir.is_null(cond) { ret true }
    let (source, is_text) = ir.string_of(cond)
    if is_text { ret truthy_formula(evaluate(r, frame, source)) }
    let (expr, has_expr) = get(cond, "expr")
    if has_expr && ir.truthy(expr) {
        let (expr_text, expr_is_text) = ir.string_of(expr)
        var s = expr_text
        if !expr_is_text { s = scalar_text(expr) }
        ret truthy_formula(evaluate(r, frame, s))
    }
    var tree = cond
    let (filter, has_filter) = get(cond, "filter")
    if has_filter && ir.truthy(filter) { tree = filter }
    var subject = frame.trigger
    if frame.has_current { subject = frame.current }
    ret r.hooks.filter_matches(r.hooks.ctx, tree, subject)
}

fn to_list(a: *mem.Arena, v: json.Value, found: bool) -> []const json.Value {
    if !found { ret zero }
    let (xs, is_array) = ir.items_of(v)
    if is_array { ret xs }
    if ir.is_null(v) { ret zero }
    let (s, is_text) = ir.string_of(v)
    if is_text && s.len == 0usize { ret zero }
    let (single, single_error) = mem.alloc[json.Value](a, 1usize)
    if single_error != ok { ret zero }
    single[0] = v
    ret single[0usize..1usize]
}

// --- log, redaction, budgets ----------------------------------------------------------------------------------------

fn lower_contains(haystack: str, needle: str) -> bool {
    if needle.len > haystack.len { ret false }
    var at = 0usize
    while at + needle.len <= haystack.len {
        var matched = true
        var k = 0usize
        while k < needle.len {
            var c = haystack[at + k]
            if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
            if c != needle[k] { matched = false }
            k += 1usize
        }
        if matched { ret true }
        at += 1usize
    }
    ret false
}

// `/(authorization|token|secret|password|api[_-]?key|bearer)/i` somewhere in a key.
fn sensitive(key: str) -> bool {
    ret lower_contains(key, "authorization") || lower_contains(key, "token") || lower_contains(key, "secret") || lower_contains(key, "password") || lower_contains(key, "apikey") || lower_contains(key, "api_key") || lower_contains(key, "api-key") || lower_contains(key, "bearer")
}

fn redact(a: *mem.Arena, v: json.Value) -> json.Value {
    let (members, is_object) = ir.members_of(v)
    let (elements, is_array) = ir.items_of(v)
    if is_object {
        var o = obj(a)
        var at = 0usize
        while at < members.len {
            if sensitive(members[at].key) {
                put(&o, members[at].key, text("***redacted***"))
            } else {
                put(&o, members[at].key, redact(a, members[at].value))
            }
            at += 1usize
        }
        ret ir.obj_value(&o)
    }
    if is_array {
        let (out, out_error) = mem.alloc[json.Value](a, elements.len + 1usize)
        if out_error != ok { ret v }
        var at = 0usize
        while at < elements.len {
            out[at] = redact(a, elements[at])
            at += 1usize
        }
        ret json.Value{ Array: out[0usize..elements.len] }
    }
    ret v
}

// A creating step's id as its output when it has one, the whole object otherwise.
fn summarize_output(a: *mem.Arena, v: json.Value) -> json.Value {
    let (members, is_object) = ir.members_of(v)
    if !is_object { ret v }
    let (id, have_id) = get(v, "id")
    if have_id {
        var o = obj(a)
        put(&o, "id", id)
        ret ir.obj_value(&o)
    }
    ret v
}

// Log an entry and answer its position, for the loop that may amend it after.
fn log_step(r: *Runner, entry: ir.Obj) -> usize {
    var e = entry
    let pushed = list.push[json.Value](&r.steps, ir.obj_value(&e))
    ret r.steps.len - 1usize
}

fn amend_status(r: *Runner, index: usize, status: str) {
    if index >= r.steps.len { ret }
    var o = obj(r.a)
    let assigned = ir.assign(&o, r.steps.items[index])
    put(&o, "status", text(status))
    r.steps.items[index] = ir.obj_value(&o)
}

fn terminate(r: *Runner, kind: str, budget: usize, used: usize, step_id: json.Value, step_type: json.Value) -> Control {
    r.reason = "budget_exceeded"
    r.has_reason = true
    var b = obj(r.a)
    put(&b, "reason", text("budget_exceeded"))
    put(&b, "kind", text(kind))
    put(&b, "budget", number(r.a, i64(budget)))
    put(&b, "used", number(r.a, i64(used)))
    put(&b, "stepId", step_id)
    put(&b, "stepType", step_type)
    r.budget = ir.obj_value(&b)
    r.has_budget = true
    ret ended("terminated", "budget_exceeded")
}

fn new_entry(r: *Runner, step: json.Value, status: str) -> ir.Obj {
    var e = obj(r.a)
    let (id, have_id) = get(step, "id")
    if have_id { put(&e, "id", id) }
    let (kind, have_kind) = get(step, "type")
    if have_kind { put(&e, "type", kind) }
    put(&e, "status", text(status))
    ret e
}

fn id_or_null(step: json.Value) -> json.Value {
    let (id, found) = get(step, "id")
    if !found || !ir.truthy(id) { ret .Null }
    ret id
}

// --- execution ------------------------------------------------------------------------------------------------------

fn exec_steps(r: *Runner, frame: Frame, steps: json.Value) -> Control {
    let list_of = items(steps)
    var at = 0usize
    while at < list_of.len {
        let step = list_of[at]
        if r.steps.len >= r.step_budget {
            let (kind, have_kind) = get(step, "type")
            var step_type: json.Value = .Null
            if have_kind && ir.truthy(kind) { step_type = kind }
            ret terminate(r, "step-budget", r.step_budget, r.steps.len, id_or_null(step), step_type)
        }
        let control = exec_step(r, frame, step)
        if control.status.len > 0usize && !str.eq(control.status, "continue") { ret control }
        at += 1usize
    }
    ret carry()
}

fn handle_failure(r: *Runner, frame: Frame) -> Control {
    if str.eq(r.on_failure, "continue") { ret carry() }
    if r.has_error_branch {
        let ran = exec_steps(r, frame, r.error_branch)
        ret ended("failed", "")
    }
    ret ended("failed", "")
}

fn fail_entry(r: *Runner, entry: ir.Obj, message: str, code: str, has_code: bool) -> ir.Obj {
    var e = entry
    put(&e, "status", text("failed"))
    put(&e, "error", text(message))
    if has_code { put(&e, "code", text(code)) }
    ret e
}

fn exec_step(r: *Runner, frame: Frame, step: json.Value) -> Control {
    let kind = member_text(step, "type")
    var entry = new_entry(r, step, "success")
    let step_id = member_text(step, "id")
    let (id_value, have_id_value) = get(step, "id")
    var has_step_id = have_id_value && ir.truthy(id_value)
    if str.eq(kind, "condition") {
        var cond = ir.value_of(step, "filter")
        var has = ir.truthy(cond)
        if !has {
            cond = ir.value_of(step, "expr")
            has = ir.truthy(cond)
        }
        if !has {
            cond = ir.value_of(step, "condition")
            has = ir.truthy(cond)
        }
        let matched = eval_condition(r, frame, cond, has)
        var output = obj(r.a)
        put(&output, "matched", flag(matched))
        put(&entry, "output", ir.obj_value(&output))
        let index = log_step(r, entry)
        var policy = member_text(step, "onFalse")
        if policy.len == 0usize { policy = "stop" }
        if !matched && str.eq(policy, "stop") { ret ended("stopped", "") }
        ret carry()
    }
    if str.eq(kind, "branch") {
        let branches = items(ir.value_of(step, "branches"))
        var at = 0usize
        while at < branches.len {
            var cond = ir.value_of(branches[at], "filter")
            var has = ir.truthy(cond)
            if !has {
                cond = ir.value_of(branches[at], "expr")
                has = ir.truthy(cond)
            }
            if eval_condition(r, frame, cond, has) {
                var name = member_text(branches[at], "name")
                if name.len == 0usize { name = "matched" }
                var output = obj(r.a)
                put(&output, "branch", text(name))
                put(&entry, "output", ir.obj_value(&output))
                let index = log_step(r, entry)
                ret exec_steps(r, frame, ir.value_of(branches[at], "steps"))
            }
            at += 1usize
        }
        var output = obj(r.a)
        put(&output, "branch", text("default"))
        put(&entry, "output", ir.obj_value(&output))
        let index = log_step(r, entry)
        ret exec_steps(r, frame, ir.value_of(step, "default"))
    }
    if str.eq(kind, "loop") {
        let (spec, has_spec) = get(step, "list")
        var list_of: []const json.Value = zero
        if has_spec {
            let (resolved, found) = resolve_value(r, frame, spec)
            list_of = to_list(r.a, resolved, found)
        }
        var cap = 1000usize
        let (cap_value, have_cap) = get(step, "cap")
        if have_cap && ir.truthy(cap_value) {
            let (c, good) = ir_count(cap_value)
            if good { cap = c }
        }
        var shown = list_of.len
        if shown > cap { shown = cap }
        var output = obj(r.a)
        put(&output, "count", number(r.a, i64(shown)))
        put(&entry, "output", ir.obj_value(&output))
        let index = log_step(r, entry)
        var i = 0usize
        while i < list_of.len {
            if i >= cap {
                amend_status(r, index, "terminated")
                var type_value: json.Value = text("loop")
                ret terminate(r, "iteration-cap", cap, list_of.len, id_or_null(step), type_value)
            }
            let child = Frame { trigger: frame.trigger, trigger_meta: frame.trigger_meta, current: list_of[i], has_current: true, index: i }
            let res = exec_steps(r, child, ir.value_of(step, "steps"))
            if str.eq(res.status, "failed") || str.eq(res.status, "terminated") { ret res }
            i += 1usize
        }
        ret carry()
    }
    if str.eq(kind, "find") { ret exec_find(r, frame, step, entry) }
    if str.eq(kind, "set") {
        let (value, found) = resolve_value(r, frame, ir.value_of(step, "value"))
        let name = member_text(step, "name")
        if found { put(&r.vars, name, value) } else { unset(&r.vars, name) }
        var output = obj(r.a)
        if found { put(&output, name, value) }
        put(&entry, "output", ir.obj_value(&output))
        let index = log_step(r, entry)
        ret carry()
    }
    if str.eq(kind, "create") || str.eq(kind, "update") || str.eq(kind, "delete") {
        let values = resolve_values(r, frame, ir.value_of(step, "values"))
        var subject_value: json.Value = .Null
        var has_subject = false
        let (target_spec, has_target) = get(step, "target")
        if has_target && ir.truthy(target_spec) {
            let (resolved, found) = resolve_value(r, frame, target_spec)
            if found {
                subject_value = resolved
                has_subject = true
            }
        } else if frame.has_current && ir.truthy(frame.current) {
            subject_value = frame.current
            has_subject = true
        } else {
            subject_value = frame.trigger
            has_subject = true
        }
        let handler = handler_of(kind)
        let dry = ir.truthy(ir.value_of(r.dry_run, kind))
        if dry {
            put(&entry, "status", text("dry-run"))
            var output = obj(r.a)
            let (table_value, have_table) = get(step, "table")
            put_present(&output, "table", table_value, have_table)
            put(&output, "values", values)
            put(&entry, "output", ir.obj_value(&output))
            let index = log_step(r, entry)
            ret carry()
        }
        var request = obj(r.a)
        put(&request, "table", ir.value_of(step, "table"))
        put_present(&request, "target", subject_value, has_subject)
        put(&request, "values", values)
        let answered = r.hooks.effect(r.hooks.ctx, handler, ir.obj_value(&request))
        if !answered.present {
            put(&entry, "status", text("skipped"))
            let index = log_step(r, entry)
            ret carry()
        }
        if answered.failed {
            let failed = fail_entry(r, entry, answered.message, answered.code, answered.has_code)
            let index = log_step(r, failed)
            ret handle_failure(r, frame)
        }
        if has_step_id && answered.has_value { put(&r.step_outputs, step_id, answered.value) }
        if answered.has_value { put(&entry, "output", summarize_output(r.a, answered.value)) }
        let index = log_step(r, entry)
        ret carry()
    }
    if str.eq(kind, "email") || str.eq(kind, "notification") || str.eq(kind, "http") {
        var source = ir.value_of(step, "config")
        if !ir.truthy(source) { source = ir.value_of(step, "payload") }
        if !ir.truthy(source) { source = empty_object() }
        let payload = resolve_values(r, frame, source)
        var handler = kind
        if str.eq(kind, "notification") { handler = "notify" }
        let dry = ir.truthy(ir.value_of(r.dry_run, kind))
        if dry {
            put(&entry, "status", text("dry-run"))
            // A key that resolved to nothing is still a key in appdor's object, and a sensitive one is masked.
            var shown = obj(r.a)
            let copied = ir.assign(&shown, redact(r.a, payload))
            let (source_members, source_is_object) = ir.members_of(source)
            var m = 0usize
            while source_is_object && m < source_members.len {
                if sensitive(source_members[m].key) { put(&shown, source_members[m].key, text("***redacted***")) }
                m += 1usize
            }
            put(&entry, "output", ir.obj_value(&shown))
            let index = log_step(r, entry)
            ret carry()
        }
        // The handler's presence is asked with an empty request: the host answers `present` without acting.
        var retries = 3i64
        let (retry_value, have_retry) = present(step, "retries")
        if have_retry {
            let (n, good) = ir_i64(retry_value)
            if good { retries = n }
        }
        var attempt = 1i64
        var last: Effect = Effect { present: false, failed: false, permanent: false, message: "", code: "", has_code: false, has_value: false, value: .Null }
        var attempts = 0i64
        var succeeded = false
        var any = false
        while attempt <= retries && !succeeded {
            let answered = r.hooks.effect(r.hooks.ctx, handler, payload)
            if !answered.present {
                put(&entry, "status", text("skipped"))
                let index = log_step(r, entry)
                ret carry()
            }
            any = true
            last = answered
            attempts = attempt
            if !answered.failed {
                succeeded = true
            } else if answered.permanent {
                attempt = retries + 1i64
                attempts = attempts
            } else {
                attempt += 1i64
            }
        }
        if !any {
            put(&entry, "status", text("skipped"))
            let index = log_step(r, entry)
            ret carry()
        }
        if !succeeded {
            var failed = fail_entry(r, entry, last.message, last.code, last.has_code)
            if attempts == 0i64 { attempts = retries }
            put(&failed, "attempts", number(r.a, attempts))
            let index = log_step(r, failed)
            ret handle_failure(r, frame)
        }
        if has_step_id && last.has_value { put(&r.step_outputs, step_id, last.value) }
        put(&entry, "attempts", number(r.a, attempts))
        if last.has_value {
            let (delivered, have_delivered) = get(last.value, "delivered")
            var no_op = false
            if have_delivered {
                switch delivered {
                case .Bool as b:
                    no_op = !b
                default:
                    no_op = false
                }
            }
            if no_op { put(&entry, "status", text("no-op")) }
            put(&entry, "output", redact(r.a, summarize_output(r.a, last.value)))
        }
        let index = log_step(r, entry)
        ret carry()
    }
    if str.eq(kind, "script") {
        var inputs = obj(r.a)
        let fields = binding_fields(r, frame)
        var k = 0usize
        while k < fields.len {
            put(&inputs, fields[k].name, from_formula(r.a, fields[k].value))
            k += 1usize
        }
        let extra = resolve_values(r, frame, ir.value_of(step, "inputs"))
        let assigned = ir.assign(&inputs, extra)
        let outcome = r.hooks.script(r.hooks.ctx, step, ir.obj_value(&inputs))
        if !str.eq(outcome.status, "success") {
            let failed = fail_entry(r, entry, outcome.message, outcome.code, outcome.has_code)
            let index = log_step(r, failed)
            ret handle_failure(r, frame)
        }
        if has_step_id && outcome.has_typed { put(&r.step_outputs, step_id, outcome.typed) }
        let (into, have_into) = get(step, "into")
        let (into_name, into_is_text) = ir.string_of(into)
        if have_into && ir.truthy(into) && into_is_text && outcome.has_typed { put(&r.vars, into_name, outcome.typed) }
        if outcome.has_output { put(&entry, "output", outcome.output) }
        let index = log_step(r, entry)
        ret carry()
    }
    if str.eq(kind, "ai") {
        var config = obj(r.a)
        let base_config = ir.or_falsy(step, "config", empty_object())
        let assigned = ir.assign(&config, base_config)
        let assigned_values = ir.assign(&config, resolve_values(r, frame, ir.value_of(step, "configValues")))
        let (model, have_model) = get(step, "model")
        if have_model && ir.truthy(model) { put(&config, "model", model) }
        var sources = obj(r.a)
        let fields = binding_fields(r, frame)
        var k = 0usize
        while k < fields.len {
            put(&sources, fields[k].name, from_formula(r.a, fields[k].value))
            k += 1usize
        }
        let assigned_sources = ir.assign(&sources, resolve_values(r, frame, ir.value_of(step, "sources")))
        var name = member_text(step, "into")
        if name.len == 0usize { name = step_id }
        if name.len == 0usize {
            name = member_text(step, "block")
            if name.len == 0usize { name = member_text(step, "blockKey") }
            if name.len == 0usize { name = member_text(step, "aiBlock") }
        }
        let dry = ir.truthy(ir.value_of(r.dry_run, "ai"))
        let outcome = r.hooks.ai(r.hooks.ctx, step, ir.obj_value(&config), ir.obj_value(&sources), name, dry)
        put(&entry, "status", text(outcome.status))
        if outcome.has_code { put(&entry, "code", text(outcome.code)) }
        if outcome.has_output { put(&entry, "output", outcome.output) }
        if str.eq(outcome.status, "failed") {
            if outcome.message.len > 0usize { put(&entry, "error", text(outcome.message)) }
            let index = log_step(r, entry)
            ret handle_failure(r, frame)
        }
        if has_step_id && outcome.has_typed { put(&r.step_outputs, step_id, outcome.typed) }
        if str.eq(outcome.status, "success") && outcome.has_typed { bind_typed_output(r, name, outcome.typed) }
        let index = log_step(r, entry)
        ret carry()
    }
    if str.eq(kind, "run-workflow") {
        if r.depth + 1i64 > r.max_depth {
            put(&entry, "status", text("cascade-exceeded"))
            let index = log_step(r, entry)
            ret ended("cascade-exceeded", "")
        }
        var request = obj(r.a)
        put(&request, "workflowId", ir.value_of(step, "workflowId"))
        put(&request, "params", resolve_values(r, frame, ir.value_of(step, "params")))
        put(&request, "depth", number(r.a, r.depth + 1i64))
        let answered = r.hooks.effect(r.hooks.ctx, "runWorkflow", ir.obj_value(&request))
        if answered.present && answered.failed {
            let failed = fail_entry(r, entry, answered.message, answered.code, answered.has_code)
            let index = log_step(r, failed)
            ret handle_failure(r, frame)
        }
        if answered.present {
            if has_step_id && answered.has_value { put(&r.step_outputs, step_id, answered.value) }
            var output = obj(r.a)
            if answered.has_value {
                if ir.is_null(answered.value) {
                    put(&output, "status", .Null)
                } else {
                    let (status_value, have_status) = get(answered.value, "status")
                    if have_status { put(&output, "status", status_value) }
                }
            }
            put(&entry, "output", ir.obj_value(&output))
        } else {
            put(&entry, "status", text("skipped"))
        }
        let index = log_step(r, entry)
        ret carry()
    }
    put(&entry, "status", text("unknown-step"))
    put(&entry, "error", text("No handler for type"))
    let index = log_step(r, entry)
    r.reason = "unknown_step"
    r.has_reason = true
    ret ended("failed", "unknown_step")
}

// `obj[key] = undefined`: JSON drops the member, so an unresolved value removes what was there.
fn unset(o: *ir.Obj, key: str) {
    var at = 0usize
    while at < o.len {
        if str.eq(o.items[at].key, key) {
            var k = at
            while k + 1usize < o.len {
                o.items[k] = o.items[k + 1usize]
                k += 1usize
            }
            o.len -= 1usize
            ret
        }
        at += 1usize
    }
}

// `put` for a spec member that may be missing: JSON drops `undefined`.
fn put_present(o: *ir.Obj, key: str, v: json.Value, found: bool) {
    if found { put(o, key, v) }
}

fn handler_of(kind: str) -> str {
    if str.eq(kind, "create") { ret "createRecord" }
    if str.eq(kind, "update") { ret "updateRecord" }
    ret "deleteRecord"
}

fn ir_count(v: json.Value) -> (usize, bool) {
    let (n, good) = ir_i64(v)
    if !good || n < 0i64 { ret (0usize, false) }
    ret (usize(n), true)
}

fn ir_i64(v: json.Value) -> (i64, bool) {
    var out = 0i64
    var good = false
    switch v {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e == ok {
            out = x
            good = true
        }
    default:
        good = false
    }
    ret (out, good)
}

// An AI step's typed output where the flow can read it: `vars[name]`, and one level of `vars["name.key"]`.
fn bind_typed_output(r: *Runner, name: str, typed: json.Value) {
    put(&r.vars, name, typed)
    let (members, is_object) = ir.members_of(typed)
    if is_object {
        var at = 0usize
        while at < members.len {
            put(&r.vars, cat(r.a, cat(r.a, name, "."), members[at].key), members[at].value)
            at += 1usize
        }
    }
}

fn exec_find(r: *Runner, frame: Frame, step: json.Value, entry: ir.Obj) -> Control {
    var e = entry
    let table = ir.value_of(step, "table")
    var request = obj(r.a)
    put(&request, "table", table)
    let (filter, have_filter) = get(step, "filter")
    if have_filter { put(&request, "filter", filter) }
    let (sort, have_sort) = get(step, "sort")
    if have_sort { put(&request, "sort", sort) }
    let (limit, have_limit) = get(step, "limit")
    if have_limit { put(&request, "limit", limit) }
    var records: []const json.Value = zero
    let answered = r.hooks.effect(r.hooks.ctx, "findRecords", ir.obj_value(&request))
    if answered.present {
        if answered.failed {
            let failed = fail_entry(r, e, answered.message, answered.code, answered.has_code)
            let index = log_step(r, failed)
            ret handle_failure(r, frame)
        }
        if answered.has_value { records = items(answered.value) }
    } else {
        let (found_records, found) = r.hooks.dataset_find(r.hooks.ctx, member_text(step, "table"), filter, sort, limit)
        if found { records = items(found_records) }
    }
    var output = obj(r.a)
    put(&output, "records", json.Value{ Array: records })
    put(&output, "count", number(r.a, i64(records.len)))
    let (id_value, have_id) = get(step, "id")
    if have_id && ir.truthy(id_value) { put(&r.step_outputs, member_text(step, "id"), ir.obj_value(&output)) }
    var summary = obj(r.a)
    put(&summary, "count", number(r.a, i64(records.len)))
    put(&e, "output", ir.obj_value(&summary))
    let index = log_step(r, e)
    ret carry()
}

// --- the public entry -----------------------------------------------------------------------------------------------

// Execute a flow: `{flowId, name, triggerType, status, steps, metered, outputs[, reason, budget, vars]}`. `trigger` is
// `{record|fields, meta, changed}`, `options` the engine's: `{dryRun, stepBudget, onFailure, errorBranch, depth,
// maxCascadeDepth, force, tenantId, refs, dataset}`.
fn run_flow(a: *mem.Arena, hooks: *const Hooks, flow: json.Value, trigger: json.Value, options: json.Value) -> (json.Value, err) {
    let (reg_made, reg_error) = library.build(a)
    if reg_error != ok { ret (.Null, reg_error) }
    var reg = reg_made
    var depth = 0i64
    let (depth_value, have_depth) = present(options, "depth")
    if have_depth {
        let (n, good) = ir_i64(depth_value)
        if good { depth = n }
    }
    var max_depth = 3i64
    let (max_value, have_max) = present(options, "maxCascadeDepth")
    if have_max {
        let (n, good) = ir_i64(max_value)
        if good { max_depth = n }
    }
    var budget = 10000usize
    let (budget_value, have_budget) = get(options, "stepBudget")
    if have_budget {
        let (n, good) = ir_count(budget_value)
        if good { budget = n }
    }
    let (steps_list, steps_error) = list.init[json.Value](a, 16usize)
    if steps_error != ok { ret (.Null, steps_error) }
    var r = Runner {
        a: a, hooks: hooks, reg: &reg, steps: steps_list, vars: obj(a), step_outputs: obj(a), reason: "", has_reason: false,
        budget: .Null, has_budget: false, step_budget: budget, max_depth: max_depth, depth: depth,
        dry_run: ir.or_falsy(options, "dryRun", empty_object()), on_failure: member_text(options, "onFailure"),
        error_branch: .Null, has_error_branch: false, refs: ir.or_falsy(options, "refs", empty_object()),
        dataset: ir.value_of(options, "dataset"),
    }
    let (branch, have_branch) = get(options, "errorBranch")
    var branch_items: []const json.Value = zero
    let (b_items, b_is_array) = ir.items_of(branch)
    if have_branch && b_is_array {
        r.error_branch = branch
        r.has_error_branch = true
    }
    var out = obj(a)
    put(&out, "flowId", ir.value_of(flow, "id"))
    let (name, have_name) = get(flow, "name")
    if have_name { put(&out, "name", name) }
    let flow_trigger = ir.value_of(flow, "trigger")
    let (trigger_type, have_trigger_type) = get(flow_trigger, "type")
    if have_trigger_type && ir.truthy(trigger_type) { put(&out, "triggerType", trigger_type) }
    var trigger_value = empty_object()
    let (record, have_record) = get(trigger, "record")
    let (fields, have_fields) = get(trigger, "fields")
    if have_record && ir.truthy(record) {
        trigger_value = record
    } else if have_fields && ir.truthy(fields) {
        trigger_value = fields
    }
    let frame = Frame { trigger: trigger_value, trigger_meta: ir.or_falsy(trigger, "meta", empty_object()), current: .Null, has_current: false, index: 0usize }
    let (enabled, have_enabled) = get(flow, "enabled")
    var disabled = false
    if have_enabled {
        switch enabled {
        case .Bool as b:
            disabled = !b
        default:
            disabled = false
        }
    }
    var forced = false
    let (force, have_force) = get(options, "force")
    if have_force && ir.truthy(force) { forced = true }
    if disabled && !forced {
        put(&out, "status", text("disabled"))
        put(&out, "steps", json.Value{ Array: zero })
        put(&out, "metered", number(a, 0i64))
        put(&out, "outputs", empty_object())
        ret (ir.obj_value(&out), ok)
    }
    if depth > max_depth {
        put(&out, "status", text("cascade-exceeded"))
        put(&out, "steps", json.Value{ Array: zero })
        put(&out, "metered", number(a, 0i64))
        put(&out, "outputs", empty_object())
        ret (ir.obj_value(&out), ok)
    }
    var filtered = false
    let (filter, have_filter) = get(flow_trigger, "filter")
    if have_filter && ir.truthy(filter) && !eval_condition(&r, frame, filter, true) { filtered = true }
    let (watched, have_watched) = get(flow_trigger, "watchedFields")
    let (changed, have_changed) = get(trigger, "changed")
    if have_watched && ir.truthy(watched) && have_changed && ir.truthy(changed) {
        let watched_items = items(watched)
        let changed_items = items(changed)
        var any = false
        var w = 0usize
        while w < watched_items.len {
            var c = 0usize
            while c < changed_items.len {
                if ir.same_scalar(watched_items[w], changed_items[c]) { any = true }
                c += 1usize
            }
            w += 1usize
        }
        if !any { filtered = true }
    }
    if filtered {
        put(&out, "status", text("filtered"))
        put(&out, "steps", json.Value{ Array: zero })
        put(&out, "metered", number(a, 0i64))
        put(&out, "outputs", empty_object())
        ret (ir.obj_value(&out), ok)
    }
    let outcome = exec_steps(&r, frame, ir.value_of(flow, "steps"))
    var status = outcome.status
    if str.eq(status, "continue") { status = "success" }
    put(&out, "status", text(status))
    put(&out, "steps", json.Value{ Array: list.slice_const[json.Value](&r.steps) })
    put(&out, "metered", number(a, 1i64))
    put(&out, "outputs", empty_object())
    if r.has_reason { put(&out, "reason", text(r.reason)) }
    put(&out, "vars", ir.obj_value(&r.vars))
    if r.has_budget {
        var b = obj(a)
        let assigned = ir.assign(&b, r.budget)
        put(&b, "ruleId", ir.value_of(flow, "id"))
        let (tenant, have_tenant) = present(options, "tenantId")
        if have_tenant { put(&b, "tenantId", tenant) } else { put(&b, "tenantId", .Null) }
        put(&out, "budget", ir.obj_value(&b))
    }
    ret (ir.obj_value(&out), ok)
}
