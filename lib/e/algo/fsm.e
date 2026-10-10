// Status workflows (L036, the state-machine half), after appdor's `src/workflows/{definition,registry,guard}.js`: a
// workflow is a set of states bound to a status field and named directed transitions (any-state `*`, self and
// parallel edges all legal), validated before publish (missing initial state, duplicate states, transitions to
// states that do not exist, rule configs against their registry, reachability from the initial state, dead ends and
// permission lock-outs), diffed between versions and offered from templates. The guard is the one path to a status
// change: permissions, conditions, screen inputs and validators in that order, optimistic concurrency, one history
// entry and one `record.transitioned` event per commit, post-functions compiled to engine steps, a raw status write
// resolved only when exactly one permitted transition reaches it, bulk transitions (partial or atomic), a
// side-effect-free simulation and time-in-state from the history.
//
// Records are rows of `e.algo.formula` values; a rule's opaque payloads (a post-function's values, config, params)
// are kept as compact JSON text and echoed into the compiled step, which is what `JSON.stringify` of appdor's step
// is. Post-functions are compiled here and run by the caller's flow engine (`runFlow` is not part of this module),
// and the commit is the caller's: `execute_transition` returns the record, history and event to commit.
//
// Differences from appdor's: only the built-in rule registries (plugins register through appdor's registries; here
// an unknown type is the same fail-closed answer); error texts are the catalogue keys humanized, which is what
// appdor's return with no bundle loaded; a generated id (no `id` given) comes from a counter the caller passes.

use e.algo.formula as f
use e.algo.view as view
use e.math
use e.mem
use e.str

// --- model --------------------------------------------------------------------------------------------------------

// A condition or validator rule as configured. `keys` are the members the rule object defines (for the config
// check), `raw` its compact JSON (for equality in a diff); `has_all`/`has_any` mark an AND/OR group.
type Rule = struct {
    raw: str,
    is_object: bool,
    kind: str,
    keys: []const str,
    has_all: bool,
    has_any: bool,
    children: []const Rule,
    roles: []const str,
    groups: []const str,
    fields: []const str,
    field: str,
    filter: view.Node,
    has_filter: bool,
    expr: str,
    table: str,
    approval: str,
    relation: str,
    quantifier: str,
    has_quantifier: bool,
    message: str,
}

// A post-function; the payload members are JSON texts, present when the matching `has_` flag is.
type PostFn = struct {
    raw: str,
    is_object: bool,
    kind: str,
    id: str,
    keys: []const str,
    field: str,
    has_field: bool,
    value: str,
    has_value: bool,
    value_spec: str,
    has_value_spec: bool,
    user: str,
    has_user: bool,
    table: str,
    values: str,
    has_values: bool,
    goal: str,
    has_goal: bool,
    config: str,
    has_config: bool,
    workflow_id: str,
    has_workflow_id: bool,
    params: str,
    has_params: bool,
}

type Permissions = struct { present: bool, roles: []const str, users: []const str, groups: []const str, people_fields: []const str }

type ScreenField = struct { field: str, required: bool }

type Screen = struct { present: bool, fields: []const ScreenField }

type State = struct { id: str, label: str, category: str }

type Transition = struct {
    id: str,
    name: str,
    description: str,
    icon: str,
    has_icon: bool,
    from: str,
    to: str,
    primary: bool,
    conditions: []const Rule,
    validators: []const Rule,
    post_functions: []const PostFn,
    permissions: Permissions,
    screen: Screen,
}

type Workflow = struct {
    id: str,
    table_id: str,
    status_field: str,
    name: str,
    status: str,
    version: f64,
    initial_state: str,
    has_initial: bool,
    states: []const State,
    transitions: []const Transition,
    blocked_treatment: str,
    open: bool,
}

type Principal = struct {
    present: bool,
    id: str,
    has_id: bool,
    permissions: []const str,
    roles: []const str,
    groups: []const str,
}

type Pair = struct { key: str, value: str }

type DecisionRow = struct { keys: []const str, values: []const f.Value, result: bool }

type DecisionTable = struct { id: str, has_inputs: bool, inputs: []const str, rows: []const DecisionRow }

type Table = struct { name: str, rows: []const view.Row }

type Env = struct {
    reg: *const f.Registry,
    has_legacy: bool,
    legacy: []const Pair,
    fields: []const view.FieldDef,
    dataset: []const Table,
    approvals: []const Pair,
    decision_tables: []const DecisionTable,
}

type Check = struct { good: bool, message: str }

// --- constants ----------------------------------------------------------------------------------------------------

fn err_unknown_transition() -> str { ret "unknown-transition" }
fn err_wrong_state() -> str { ret "wrong-state" }
fn err_permission_denied() -> str { ret "permission-denied" }
fn err_condition_failed() -> str { ret "condition-failed" }
fn err_missing_inputs() -> str { ret "missing-inputs" }
fn err_validator_failed() -> str { ret "validator-failed" }
fn err_version_conflict() -> str { ret "version-conflict" }
fn err_reason_required() -> str { ret "reason-required" }

fn contains(list: []const str, x: str) -> bool {
    var i = 0usize
    while i < list.len {
        if str.eq(list[i], x) { ret true }
        i += 1usize
    }
    ret false
}

fn is_condition_type(k: str) -> bool {
    ret str.eq(k, "role") || str.eq(k, "group") || str.eq(k, "people-field") || str.eq(k, "field-predicate") || str.eq(k, "formula") || str.eq(k, "decision-table")
}

fn is_validator_type(k: str) -> bool {
    ret str.eq(k, "required-fields") || str.eq(k, "field-predicate") || str.eq(k, "screen-required") || str.eq(k, "formula") || str.eq(k, "linked-records") || str.eq(k, "approval")
}

fn is_post_type(k: str) -> bool {
    ret str.eq(k, "set-field") || str.eq(k, "assign") || str.eq(k, "clear-field") || str.eq(k, "add-follower") || str.eq(k, "remove-follower") || str.eq(k, "create-record") || str.eq(k, "update-record") || str.eq(k, "notify") || str.eq(k, "webhook") || str.eq(k, "run-workflow")
}

// The members a type's schema requires, as a space-separated list.
fn required_of(kind: u8, type_name: str) -> str {
    if kind == 0u8 {
        if str.eq(type_name, "role") { ret "roles" }
        if str.eq(type_name, "group") { ret "groups" }
        if str.eq(type_name, "people-field") { ret "field" }
        if str.eq(type_name, "field-predicate") { ret "filter" }
        if str.eq(type_name, "formula") { ret "expr" }
        if str.eq(type_name, "decision-table") { ret "table" }
        ret ""
    }
    if kind == 1u8 {
        if str.eq(type_name, "required-fields") { ret "fields" }
        if str.eq(type_name, "field-predicate") { ret "filter" }
        if str.eq(type_name, "screen-required") { ret "fields" }
        if str.eq(type_name, "formula") { ret "expr" }
        if str.eq(type_name, "linked-records") { ret "relation table filter" }
        if str.eq(type_name, "approval") { ret "approval" }
        ret ""
    }
    if str.eq(type_name, "set-field") { ret "field value" }
    if str.eq(type_name, "assign") { ret "field user" }
    if str.eq(type_name, "clear-field") { ret "field" }
    if str.eq(type_name, "add-follower") { ret "user" }
    if str.eq(type_name, "remove-follower") { ret "user" }
    if str.eq(type_name, "create-record") { ret "table values" }
    if str.eq(type_name, "update-record") { ret "table target values" }
    if str.eq(type_name, "notify") { ret "config" }
    if str.eq(type_name, "webhook") { ret "config" }
    if str.eq(type_name, "run-workflow") { ret "workflowId" }
    ret ""
}

// The first required member a rule does not define, or "" when every one is there.
fn missing_member(required: str, keys: []const str) -> str {
    var start = 0usize
    var i = 0usize
    while i <= required.len {
        if i == required.len || required[i] == 32u8 {
            if i > start {
                let word = required[start..i]
                if !contains(keys, word) { ret word }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret ""
}

fn kind_label(kind: u8) -> str {
    if kind == 0u8 { ret "condition" }
    if kind == 1u8 { ret "validator" }
    ret "post-function"
}

// The registry's config check: the rule is an object, of a known type, with every required member present.
fn check_config(kind: u8, is_object: bool, type_name: str, keys: []const str) -> Check {
    if !is_object { ret Check { good: false, message: "Rule not object" } }
    var known = false
    if kind == 0u8 { known = is_condition_type(type_name) } else if kind == 1u8 { known = is_validator_type(type_name) } else { known = is_post_type(type_name) }
    if !known { ret Check { good: false, message: "Unknown type" } }
    let gap = missing_member(required_of(kind, type_name), keys)
    if gap.len != 0usize { ret Check { good: false, message: "Missing config" } }
    ret Check { good: true, message: "" }
}

// --- definition ---------------------------------------------------------------------------------------------------

fn is_category(c: str) -> bool { ret str.eq(c, "todo") || str.eq(c, "in-progress") || str.eq(c, "done") }

// A state with the defaults applied: the label defaults to the id, an unknown category to `todo`.
fn normalize_state(id: str, label: str, has_label: bool, category: str) -> State {
    var l = id
    if has_label { l = label }
    var c = "todo"
    if is_category(category) { c = category }
    ret State { id: id, label: l, category: c }
}

fn no_permissions() -> Permissions {
    var none: []const str = zero
    ret Permissions { present: false, roles: none, users: none, groups: none, people_fields: none }
}

fn no_screen() -> Screen {
    var none: []const ScreenField = zero
    ret Screen { present: false, fields: none }
}

fn nonempty(s: str, fallback: str) -> str {
    if s.len == 0usize { ret fallback }
    ret s
}

// A transition with the defaults applied; `has_from` false reads as any-state, an empty id is `generated`.
fn normalize_transition(t: Transition, has_from: bool, generated: str) -> Transition {
    var out = t
    out.id = nonempty(t.id, generated)
    out.name = nonempty(t.name, "Transition")
    if !has_from { out.from = "*" }
    ret out
}

fn blocked_treatment_of(raw: str) -> str {
    if str.eq(raw, "hidden") { ret "hidden" }
    ret "disabled"
}

fn empty_workflow(id: str, table_id: str, status_field: str, name: str) -> Workflow {
    var states: []const State = zero
    var transitions: []const Transition = zero
    ret Workflow {
        id: id, table_id: table_id, status_field: status_field, name: nonempty(name, "Workflow"), status: "draft",
        version: 0.0f64, initial_state: "", has_initial: false, states: states, transitions: transitions,
        blocked_treatment: "disabled", open: false,
    }
}

// The implicit open workflow of an unguarded status field: every state reachable from every state, no rules.
fn open_workflow(a: *mem.Arena, table_id: str, status_field: str, options: []const str) -> Workflow {
    var wf = empty_workflow(f.join3(a, f.join3(a, "open:", table_id, ":"), status_field, ""), table_id, status_field, "Open workflow")
    let (states, e1) = mem.alloc[State](a, options.len + 1usize)
    let (transitions, e2) = mem.alloc[Transition](a, options.len + 1usize)
    if e1 != ok || e2 != ok { ret wf }
    var none_rules: []const Rule = zero
    var none_post: []const PostFn = zero
    var i = 0usize
    while i < options.len {
        states[i] = normalize_state(options[i], "", false, "todo")
        transitions[i] = Transition {
            id: f.join(a, "open_", options[i]), name: "Set state", description: "", icon: "", has_icon: false, from: "*",
            to: options[i], primary: false, conditions: none_rules, validators: none_rules, post_functions: none_post,
            permissions: no_permissions(), screen: no_screen(),
        }
        i += 1usize
    }
    wf.states = states[0usize..options.len]
    wf.transitions = transitions[0usize..options.len]
    if options.len > 0usize {
        wf.initial_state = options[0usize]
        wf.has_initial = true
    }
    wf.status = "published"
    wf.version = 1.0f64
    wf.open = true
    ret wf
}

// An edit result: the workflow, or the refusal text.
type Edit = struct { wf: Workflow, failed: bool, message: str }

fn edit_ok(wf: Workflow) -> Edit { ret Edit { wf: wf, failed: false, message: "" } }

fn edit_refused(wf: Workflow, message: str) -> Edit { ret Edit { wf: wf, failed: true, message: message } }

fn state_index(wf: Workflow, id: str) -> (usize, bool) {
    var i = 0usize
    while i < wf.states.len {
        if str.eq(wf.states[i].id, id) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Add a state to a draft; the first state becomes the initial one.
fn add_state(a: *mem.Arena, wf: Workflow, s: State) -> Edit {
    if !str.eq(wf.status, "draft") { ret edit_refused(wf, "Drafts only") }
    let (at, found) = state_index(wf, s.id)
    if found { ret edit_refused(wf, "State exists") }
    let (cells, e) = mem.alloc[State](a, wf.states.len + 1usize)
    if e != ok { ret edit_refused(wf, "capacity") }
    var i = 0usize
    while i < wf.states.len {
        cells[i] = wf.states[i]
        i += 1usize
    }
    cells[wf.states.len] = s
    var out = wf
    out.states = cells[0usize..wf.states.len + 1usize]
    if !wf.has_initial || wf.initial_state.len == 0usize {
        out.initial_state = s.id
        out.has_initial = true
    }
    ret edit_ok(out)
}

fn add_transition(a: *mem.Arena, wf: Workflow, t: Transition) -> Edit {
    if !str.eq(wf.status, "draft") { ret edit_refused(wf, "Drafts only") }
    let (cells, e) = mem.alloc[Transition](a, wf.transitions.len + 1usize)
    if e != ok { ret edit_refused(wf, "capacity") }
    var i = 0usize
    while i < wf.transitions.len {
        cells[i] = wf.transitions[i]
        i += 1usize
    }
    cells[wf.transitions.len] = t
    var out = wf
    out.transitions = cells[0usize..wf.transitions.len + 1usize]
    ret edit_ok(out)
}

// Remove a state and every transition touching it; the initial state moves to the first that remains.
fn remove_state(a: *mem.Arena, wf: Workflow, id: str) -> Edit {
    if !str.eq(wf.status, "draft") { ret edit_refused(wf, "Drafts only") }
    let (states, e1) = mem.alloc[State](a, wf.states.len + 1usize)
    let (transitions, e2) = mem.alloc[Transition](a, wf.transitions.len + 1usize)
    if e1 != ok || e2 != ok { ret edit_refused(wf, "capacity") }
    var n = 0usize
    var i = 0usize
    while i < wf.states.len {
        if !str.eq(wf.states[i].id, id) {
            states[n] = wf.states[i]
            n += 1usize
        }
        i += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < wf.transitions.len {
        if !str.eq(wf.transitions[i].from, id) && !str.eq(wf.transitions[i].to, id) {
            transitions[m] = wf.transitions[i]
            m += 1usize
        }
        i += 1usize
    }
    var out = wf
    out.states = states[0usize..n]
    out.transitions = transitions[0usize..m]
    if wf.has_initial && str.eq(wf.initial_state, id) {
        if n > 0usize {
            out.initial_state = states[0usize].id
            out.has_initial = true
        } else {
            out.initial_state = ""
            out.has_initial = false
        }
    }
    ret edit_ok(out)
}

// --- pre-publish validation ---------------------------------------------------------------------------------------

// A finding: its code, the transition or state it concerns (empty when none) and the message.
type Finding = struct { code: str, transition: str, has_transition: bool, state: str, has_state: bool, message: str }

type Validation = struct { valid: bool, errors: []const Finding, warnings: []const Finding }

fn finding(code: str, message: str) -> Finding {
    ret Finding { code: code, transition: "", has_transition: false, state: "", has_state: false, message: message }
}

// Leaf rules of AND/OR groups, in order.
fn flatten_rules(a: *mem.Arena, rules: []const Rule, out: []Rule, n: usize) -> usize {
    var count = n
    var i = 0usize
    while i < rules.len {
        let r = rules[i]
        if r.has_all || r.has_any {
            count = flatten_rules(a, r.children, out, count)
        } else if count < out.len {
            out[count] = r
            count += 1usize
        }
        i += 1usize
    }
    ret count
}

fn count_rules(rules: []const Rule) -> usize {
    var total = 0usize
    var i = 0usize
    while i < rules.len {
        total += 1usize + count_rules(rules[i].children)
        i += 1usize
    }
    ret total
}

fn validate_workflow(a: *mem.Arena, wf: Workflow) -> Validation {
    var none: []const Finding = zero
    let cap = wf.states.len * 2usize + wf.transitions.len * 8usize + 16usize
    let (errors, e1) = mem.alloc[Finding](a, cap)
    let (warnings, e2) = mem.alloc[Finding](a, cap)
    if e1 != ok || e2 != ok { ret Validation { valid: false, errors: none, warnings: none } }
    var ne = 0usize
    var nw = 0usize
    if wf.states.len == 0usize {
        errors[ne] = finding("no-states", "No states")
        ne += 1usize
    }
    var initial_known = false
    if !wf.has_initial || wf.initial_state.len == 0usize {
        errors[ne] = finding("no-initial-state", "No initial state")
        ne += 1usize
    } else {
        let (at, found) = state_index(wf, wf.initial_state)
        initial_known = found
        if !found {
            errors[ne] = finding("bad-initial-state", "Bad initial state")
            ne += 1usize
        }
    }
    // Duplicate state ids, each reported once, in order of first repetition.
    var i = 0usize
    while i < wf.states.len {
        var first_repeat = false
        var earlier = 0usize
        while earlier < i {
            if str.eq(wf.states[earlier].id, wf.states[i].id) { first_repeat = true }
            earlier += 1usize
        }
        if first_repeat {
            // Reported once: the first time this id repeats.
            var seen_before = false
            var k = 0usize
            while k < i {
                var repeated_at_k = false
                var m = 0usize
                while m < k {
                    if str.eq(wf.states[m].id, wf.states[k].id) { repeated_at_k = true }
                    m += 1usize
                }
                if repeated_at_k && str.eq(wf.states[k].id, wf.states[i].id) { seen_before = true }
                k += 1usize
            }
            if !seen_before {
                errors[ne] = finding("duplicate-state", "Duplicate state")
                ne += 1usize
            }
        }
        i += 1usize
    }
    var t = 0usize
    while t < wf.transitions.len {
        let tr = wf.transitions[t]
        let (from_at, from_found) = state_index(wf, tr.from)
        if !str.eq(tr.from, "*") && !from_found {
            var x = finding("bad-transition-from", "Transition from missing")
            x.transition = tr.id
            x.has_transition = true
            errors[ne] = x
            ne += 1usize
        }
        let (to_at, to_found) = state_index(wf, tr.to)
        if !to_found {
            var x = finding("bad-transition-to", "Transition to missing")
            x.transition = tr.id
            x.has_transition = true
            errors[ne] = x
            ne += 1usize
        }
        // Conditions are checked flattened; validators and post-functions as written.
        let (leaves, e3) = mem.alloc[Rule](a, count_rules(tr.conditions) + 1usize)
        if e3 == ok {
            let total = flatten_rules(a, tr.conditions, leaves, 0usize)
            var k = 0usize
            while k < total {
                let c = check_config(0u8, leaves[k].is_object, leaves[k].kind, leaves[k].keys)
                if !c.good {
                    var x = finding("bad-rule-config", f.join3(a, tr.name, ": ", c.message))
                    x.transition = tr.id
                    x.has_transition = true
                    errors[ne] = x
                    ne += 1usize
                }
                k += 1usize
            }
        }
        var k = 0usize
        while k < tr.validators.len {
            let c = check_config(1u8, tr.validators[k].is_object, tr.validators[k].kind, tr.validators[k].keys)
            if !c.good {
                var x = finding("bad-rule-config", f.join3(a, tr.name, ": ", c.message))
                x.transition = tr.id
                x.has_transition = true
                errors[ne] = x
                ne += 1usize
            }
            k += 1usize
        }
        k = 0usize
        while k < tr.post_functions.len {
            let c = check_config(2u8, tr.post_functions[k].is_object, tr.post_functions[k].kind, tr.post_functions[k].keys)
            if !c.good {
                var x = finding("bad-rule-config", f.join3(a, tr.name, ": ", c.message))
                x.transition = tr.id
                x.has_transition = true
                errors[ne] = x
                ne += 1usize
            }
            k += 1usize
        }
        let p = tr.permissions
        if p.present && p.roles.len == 0usize && p.users.len == 0usize && p.groups.len == 0usize && p.people_fields.len == 0usize {
            var x = finding("lockout", "Lockout")
            x.transition = tr.id
            x.has_transition = true
            warnings[nw] = x
            nw += 1usize
        }
        t += 1usize
    }
    // Reachability from the initial state; any-state transitions reach their goal from everywhere.
    if wf.has_initial && initial_known {
        let (reach, e4) = mem.alloc[bool](a, wf.states.len + 1usize)
        if e4 == ok {
            i = 0usize
            while i < wf.states.len {
                reach[i] = false
                i += 1usize
            }
            let (start_at, start_found) = state_index(wf, wf.initial_state)
            reach[start_at] = true
            var grew = true
            while grew {
                grew = false
                t = 0usize
                while t < wf.transitions.len {
                    let tr = wf.transitions[t]
                    let (to_at, to_found) = state_index(wf, tr.to)
                    if to_found && !reach[to_at] {
                        var from_reached = str.eq(tr.from, "*")
                        if !from_reached {
                            let (from_at, from_found) = state_index(wf, tr.from)
                            if from_found && reach[from_at] { from_reached = true }
                        }
                        if from_reached {
                            reach[to_at] = true
                            grew = true
                        }
                    }
                    t += 1usize
                }
            }
            i = 0usize
            while i < wf.states.len {
                // Reachability is by id: a duplicate of a reachable state is reachable.
                let (first_at, first_found) = state_index(wf, wf.states[i].id)
                if !reach[first_at] {
                    var x = finding("unreachable-state", "Unreachable")
                    x.state = wf.states[i].id
                    x.has_state = true
                    errors[ne] = x
                    ne += 1usize
                }
                i += 1usize
            }
        }
    }
    // Dead ends: non-done states with no way out and no any-state escape.
    var has_global = false
    t = 0usize
    while t < wf.transitions.len {
        if str.eq(wf.transitions[t].from, "*") { has_global = true }
        t += 1usize
    }
    i = 0usize
    while i < wf.states.len {
        let s = wf.states[i]
        if !str.eq(s.category, "done") {
            var has_out = false
            t = 0usize
            while t < wf.transitions.len {
                if str.eq(wf.transitions[t].from, s.id) || str.eq(wf.transitions[t].from, "*") { has_out = true }
                t += 1usize
            }
            if !has_out && !has_global {
                var x = finding("dead-end", "Dead end")
                x.state = s.id
                x.has_state = true
                warnings[nw] = x
                nw += 1usize
            }
        }
        i += 1usize
    }
    ret Validation { valid: ne == 0usize, errors: errors[0usize..ne], warnings: warnings[0usize..nw] }
}

// --- version diffs ------------------------------------------------------------------------------------------------

// `kind` is one of state-added, state-removed, state-changed, transition-added, transition-removed,
// transition-changed.
type Change = struct { kind: str, id: str, label: str }

fn rules_equal(x: []const Rule, y: []const Rule) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if !str.eq(x[i].raw, y[i].raw) { ret false }
        i += 1usize
    }
    ret true
}

fn posts_equal(x: []const PostFn, y: []const PostFn) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if !str.eq(x[i].raw, y[i].raw) { ret false }
        i += 1usize
    }
    ret true
}

fn lists_equal(x: []const str, y: []const str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if !str.eq(x[i], y[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn screens_equal(x: Screen, y: Screen) -> bool {
    if x.present != y.present { ret false }
    if x.fields.len != y.fields.len { ret false }
    var i = 0usize
    while i < x.fields.len {
        if !str.eq(x.fields[i].field, y.fields[i].field) || x.fields[i].required != y.fields[i].required { ret false }
        i += 1usize
    }
    ret true
}

fn transitions_equal(x: Transition, y: Transition) -> bool {
    if !str.eq(x.id, y.id) || !str.eq(x.name, y.name) || !str.eq(x.description, y.description) { ret false }
    if x.has_icon != y.has_icon || !str.eq(x.icon, y.icon) { ret false }
    if !str.eq(x.from, y.from) || !str.eq(x.to, y.to) || x.primary != y.primary { ret false }
    if !rules_equal(x.conditions, y.conditions) || !rules_equal(x.validators, y.validators) { ret false }
    if !posts_equal(x.post_functions, y.post_functions) { ret false }
    if x.permissions.present != y.permissions.present { ret false }
    if !lists_equal(x.permissions.roles, y.permissions.roles) || !lists_equal(x.permissions.users, y.permissions.users) { ret false }
    if !lists_equal(x.permissions.groups, y.permissions.groups) || !lists_equal(x.permissions.people_fields, y.permissions.people_fields) { ret false }
    ret screens_equal(x.screen, y.screen)
}

fn transition_index(wf: Workflow, id: str) -> (usize, bool) {
    var i = 0usize
    while i < wf.transitions.len {
        if str.eq(wf.transitions[i].id, id) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// The changes from `x` to `y`: states added (in `y`'s order), removed, relabelled or re-categorized, then the same
// for transitions.
fn diff_workflows(a: *mem.Arena, x: Workflow, y: Workflow) -> []const Change {
    var none: []const Change = zero
    let cap = (x.states.len + y.states.len + x.transitions.len + y.transitions.len) * 2usize + 1usize
    let (out, e) = mem.alloc[Change](a, cap)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < y.states.len {
        let (at, found) = state_index(x, y.states[i].id)
        if !found {
            out[n] = Change { kind: "state-added", id: y.states[i].id, label: y.states[i].label }
            n += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < x.states.len {
        let (at, found) = state_index(y, x.states[i].id)
        if !found {
            out[n] = Change { kind: "state-removed", id: x.states[i].id, label: x.states[i].label }
            n += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < y.states.len {
        let (at, found) = state_index(x, y.states[i].id)
        if found && (!str.eq(x.states[at].label, y.states[i].label) || !str.eq(x.states[at].category, y.states[i].category)) {
            out[n] = Change { kind: "state-changed", id: y.states[i].id, label: "" }
            n += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < y.transitions.len {
        let (at, found) = transition_index(x, y.transitions[i].id)
        if !found {
            out[n] = Change { kind: "transition-added", id: y.transitions[i].id, label: y.transitions[i].name }
            n += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < x.transitions.len {
        let (at, found) = transition_index(y, x.transitions[i].id)
        if !found {
            out[n] = Change { kind: "transition-removed", id: x.transitions[i].id, label: x.transitions[i].name }
            n += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < y.transitions.len {
        let (at, found) = transition_index(x, y.transitions[i].id)
        if found && !transitions_equal(x.transitions[at], y.transitions[i]) {
            out[n] = Change { kind: "transition-changed", id: y.transitions[i].id, label: y.transitions[i].name }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- values -------------------------------------------------------------------------------------------------------

// `toList(v)`: an array is itself, null/undefined/'' is empty, anything else a one-element list.
fn list_len(v: f.Value) -> usize {
    if v.kind == .Array { ret v.items.len }
    if v.kind == .Blank { ret 0usize }
    if v.kind == .Text && v.s.len == 0usize { ret 0usize }
    ret 1usize
}

fn list_at(v: f.Value, i: usize) -> f.Value {
    if v.kind == .Array { ret v.items[i] }
    ret v
}

fn list_includes_text(v: f.Value, x: str) -> bool {
    var i = 0usize
    let n = list_len(v)
    while i < n {
        let item = list_at(v, i)
        if item.kind == .Text && str.eq(item.s, x) { ret true }
        i += 1usize
    }
    ret false
}

fn truthy(v: f.Value) -> bool {
    if f.is_error(v) { ret false }
    if v.kind == .Blank { ret false }
    if v.kind == .Bool { ret v.n != 0.0f64 }
    if v.kind == .Text { ret v.s.len != 0usize }
    if v.kind == .Number { ret v.n != 0.0f64 }
    if v.kind == .Array { ret v.items.len > 0usize }
    ret true
}

fn field_value(fields: []const f.Field, name: str) -> (f.Value, bool) {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) { ret (fields[i].value, true) }
        i += 1usize
    }
    ret (f.blank(), false)
}

fn is_blank_input(v: f.Value, present: bool) -> bool {
    if !present { ret true }
    if v.kind == .Blank { ret true }
    ret v.kind == .Text && v.s.len == 0usize
}

// The record with `inputs` laid over it, in JavaScript's key order: existing keys keep their place.
fn merged(a: *mem.Arena, record: []const f.Field, inputs: []const f.Field) -> []const f.Field {
    let (out, e) = mem.alloc[f.Field](a, record.len + inputs.len + 1usize)
    if e != ok { ret record }
    var n = 0usize
    var i = 0usize
    while i < record.len {
        out[n] = record[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < inputs.len {
        var at = n
        var k = 0usize
        while k < n {
            if str.eq(out[k].name, inputs[i].name) { at = k }
            k += 1usize
        }
        out[at] = inputs[i]
        if at == n { n += 1usize }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- rule evaluation ----------------------------------------------------------------------------------------------

type RuleCtx = struct {
    record: []const f.Field,
    principal: Principal,
    env: *const Env,
    inputs: []const f.Field,
}

fn view_context() -> view.Context {
    var c: view.Context = zero
    c.user_id = f.blank()
    ret c
}

fn filter_holds(a: *mem.Arena, rule: Rule, row_fields: []const f.Field, env: *const Env) -> bool {
    var ctx = view_context()
    ret view.matches_filter(a, env.reg, rule.filter, rule.has_filter, view.Row { fields: row_fields }, env.fields, &ctx)
}

fn formula_truthy(a: *mem.Arena, expr: str, fields: []const f.Field, env: *const Env) -> bool {
    var c: f.Context = zero
    c.fields = fields
    ret truthy(f.evaluate(a, expr, &c, env.reg))
}

fn find_decision_table(env: *const Env, id: str) -> (DecisionTable, bool) {
    var none: DecisionTable = zero
    var i = 0usize
    while i < env.decision_tables.len {
        if str.eq(env.decision_tables[i].id, id) { ret (env.decision_tables[i], true) }
        i += 1usize
    }
    ret (none, false)
}

fn decision_holds(rule: Rule, c: *const RuleCtx) -> bool {
    let (table, found) = find_decision_table(c.env, rule.table)
    if !found { ret false }
    var r = 0usize
    while r < table.rows.len {
        let row = table.rows[r]
        // The inputs to test: the table's list, else the row's own keys.
        var hit = true
        var count = row.keys.len
        if table.has_inputs { count = table.inputs.len }
        var k = 0usize
        while k < count {
            var name = ""
            if table.has_inputs { name = table.inputs[k] } else { name = row.keys[k] }
            var at = row.keys.len
            var m = 0usize
            while m < row.keys.len {
                if str.eq(row.keys[m], name) { at = m }
                m += 1usize
            }
            if at < row.keys.len {
                let wanted = row.values[at]
                if !(wanted.kind == .Text && str.eq(wanted.s, "*")) {
                    let (actual, present) = field_value(c.record, name)
                    if !view.strict_equal(actual, present, wanted, true) { hit = false }
                }
            }
            k += 1usize
        }
        if hit { ret row.result }
        r += 1usize
    }
    ret false
}

// One condition rule or an AND/OR group; an unknown type fails closed.
fn eval_condition(a: *mem.Arena, rule: Rule, c: *const RuleCtx) -> bool {
    if rule.has_all {
        var i = 0usize
        while i < rule.children.len {
            if !eval_condition(a, rule.children[i], c) { ret false }
            i += 1usize
        }
        ret true
    }
    if rule.has_any {
        var i = 0usize
        while i < rule.children.len {
            if eval_condition(a, rule.children[i], c) { ret true }
            i += 1usize
        }
        ret false
    }
    if !rule.is_object { ret false }
    if str.eq(rule.kind, "role") {
        var i = 0usize
        while i < rule.roles.len {
            if contains(c.principal.roles, rule.roles[i]) { ret true }
            i += 1usize
        }
        ret false
    }
    if str.eq(rule.kind, "group") {
        var i = 0usize
        while i < rule.groups.len {
            if contains(c.principal.groups, rule.groups[i]) { ret true }
            i += 1usize
        }
        ret false
    }
    if str.eq(rule.kind, "people-field") {
        if !c.principal.present || !c.principal.has_id { ret false }
        let (v, present) = field_value(c.record, rule.field)
        ret list_includes_text(v, c.principal.id)
    }
    if str.eq(rule.kind, "field-predicate") { ret filter_holds(a, rule, c.record, c.env) }
    if str.eq(rule.kind, "formula") { ret formula_truthy(a, rule.expr, c.record, c.env) }
    if str.eq(rule.kind, "decision-table") { ret decision_holds(rule, c) }
    ret false
}

// A validator's verdict: `ok`, or the failure with what it names.
type Verdict = struct {
    good: bool,
    validator: str,
    error_text: str,
    field: str,
    has_field: bool,
    missing: []const str,
    has_missing: bool,
    approval: str,
    has_approval: bool,
}

fn verdict_ok(kind: str) -> Verdict {
    var none: []const str = zero
    ret Verdict { good: true, validator: kind, error_text: "", field: "", has_field: false, missing: none, has_missing: false, approval: "", has_approval: false }
}

fn verdict_failed(kind: str, text: str) -> Verdict {
    var v = verdict_ok(kind)
    v.good = false
    v.error_text = text
    ret v
}

fn message_or(rule: Rule, fallback: str) -> str {
    if rule.message.len != 0usize { ret rule.message }
    ret fallback
}

fn required_empty(v: f.Value, present: bool) -> bool {
    if !present || v.kind == .Blank { ret true }
    if v.kind == .Text && v.s.len == 0usize { ret true }
    ret v.kind == .Array && v.items.len == 0usize
}

fn eval_validator(a: *mem.Arena, rule: Rule, c: *const RuleCtx) -> Verdict {
    if !rule.is_object || !is_validator_type(rule.kind) { ret verdict_failed(rule.kind, "Unknown type") }
    let both = merged(a, c.record, c.inputs)
    if str.eq(rule.kind, "required-fields") {
        var i = 0usize
        while i < rule.fields.len {
            let (v, present) = field_value(both, rule.fields[i])
            if required_empty(v, present) {
                var out = verdict_failed(rule.kind, "Field required")
                out.field = rule.fields[i]
                out.has_field = true
                ret out
            }
            i += 1usize
        }
        ret verdict_ok(rule.kind)
    }
    if str.eq(rule.kind, "field-predicate") {
        if filter_holds(a, rule, both, c.env) { ret verdict_ok(rule.kind) }
        ret verdict_failed(rule.kind, message_or(rule, "Predicate failed"))
    }
    if str.eq(rule.kind, "screen-required") {
        let (missing, e) = mem.alloc[str](a, rule.fields.len + 1usize)
        if e != ok { ret verdict_failed(rule.kind, "capacity") }
        var n = 0usize
        var i = 0usize
        while i < rule.fields.len {
            let (v, present) = field_value(c.inputs, rule.fields[i])
            if is_blank_input(v, present) {
                missing[n] = rule.fields[i]
                n += 1usize
            }
            i += 1usize
        }
        if n == 0usize { ret verdict_ok(rule.kind) }
        var out = verdict_failed(rule.kind, "Missing inputs")
        out.missing = missing[0usize..n]
        out.has_missing = true
        ret out
    }
    if str.eq(rule.kind, "formula") {
        if formula_truthy(a, rule.expr, both, c.env) { ret verdict_ok(rule.kind) }
        ret verdict_failed(rule.kind, message_or(rule, "Formula failed"))
    }
    if str.eq(rule.kind, "linked-records") {
        let (ids, present) = field_value(c.record, rule.relation)
        var total = 0usize
        var matched = 0usize
        var t = 0usize
        while t < c.env.dataset.len {
            if str.eq(c.env.dataset[t].name, rule.table) {
                let rows = c.env.dataset[t].rows
                var r = 0usize
                while r < rows.len {
                    let (rid, has_id) = view.cell_of(rows[r], "id")
                    var linked = false
                    var k = 0usize
                    let n = list_len(ids)
                    while k < n {
                        if has_id && view.strict_equal(list_at(ids, k), true, rid, true) { linked = true }
                        k += 1usize
                    }
                    if linked {
                        total += 1usize
                        if filter_holds(a, rule, rows[r].fields, c.env) { matched += 1usize }
                    }
                    r += 1usize
                }
            }
            t += 1usize
        }
        var q = "all"
        if rule.has_quantifier && rule.quantifier.len != 0usize { q = rule.quantifier }
        var good = false
        if str.eq(q, "all") { good = matched == total } else if str.eq(q, "any") { good = matched > 0usize } else if str.eq(q, "none") { good = matched == 0usize }
        if good { ret verdict_ok(rule.kind) }
        ret verdict_failed(rule.kind, message_or(rule, "Linked predicate failed"))
    }
    // approval
    var state = ""
    var has_state = false
    var i = 0usize
    while i < c.env.approvals.len {
        if str.eq(c.env.approvals[i].key, rule.approval) {
            state = c.env.approvals[i].value
            has_state = true
        }
        i += 1usize
    }
    if has_state && str.eq(state, "approved") { ret verdict_ok(rule.kind) }
    var out = verdict_failed(rule.kind, "Approval not approved")
    out.approval = rule.approval
    out.has_approval = true
    ret out
}

// --- post-function compilation -----------------------------------------------------------------------------------

// JSON text of a string, as `JSON.stringify` writes it.
fn json_quote(a: *mem.Arena, s: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len * 6usize + 2usize)
    if e != ok { ret "\"\"" }
    var n = 0usize
    buf[n] = 34u8
    n += 1usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            buf[n] = 92u8
            buf[n + 1usize] = 34u8
            n += 2usize
        } else if c == 92u8 {
            buf[n] = 92u8
            buf[n + 1usize] = 92u8
            n += 2usize
        } else if c == 8u8 || c == 12u8 || c == 10u8 || c == 13u8 || c == 9u8 {
            buf[n] = 92u8
            if c == 8u8 { buf[n + 1usize] = 98u8 } else if c == 12u8 { buf[n + 1usize] = 102u8 } else if c == 10u8 { buf[n + 1usize] = 110u8 } else if c == 13u8 { buf[n + 1usize] = 114u8 } else { buf[n + 1usize] = 116u8 }
            n += 2usize
        } else if c < 32u8 {
            // \u00XX
            let hi = c >> 4u8
            let lo = c & 15u8
            buf[n] = 92u8
            buf[n + 1usize] = 117u8
            buf[n + 2usize] = 48u8
            buf[n + 3usize] = 48u8
            if hi > 9u8 { buf[n + 4usize] = 87u8 + hi } else { buf[n + 4usize] = 48u8 + hi }
            if lo > 9u8 { buf[n + 5usize] = 87u8 + lo } else { buf[n + 5usize] = 48u8 + lo }
            n += 6usize
        } else {
            buf[n] = c
            n += 1usize
        }
        i += 1usize
    }
    buf[n] = 34u8
    n += 1usize
    ret buf[0usize..n]
}

// JSON text of a value; an object stands as `{}` (a field value is opaque here).
fn value_json(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Blank { ret "null" }
    if v.kind == .Number { ret f.number_text(a, v.n) }
    if v.kind == .Text { ret json_quote(a, v.s) }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "true" }
        ret "false"
    }
    if v.kind == .Array {
        var out = "["
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, ",") }
            out = f.join(a, out, value_json(a, v.items[i]))
            i += 1usize
        }
        ret f.join(a, out, "]")
    }
    ret "{}"
}

// `{"literal":X}`, or `{}` for an undefined X.
fn literal_json(a: *mem.Arena, x: str, has: bool) -> str {
    if !has { ret "{}" }
    ret f.join3(a, "{\"literal\":", x, "}")
}

fn update_step(a: *mem.Arena, table: str, record: []const f.Field, values: str) -> str {
    let (id, has_id) = field_value(record, "id")
    var goal = "{}"
    if has_id { goal = literal_json(a, value_json(a, id), true) }
    var out = f.join3(a, "{\"type\":\"update\",\"table\":", json_quote(a, table), ",\"target\":")
    out = f.join3(a, out, goal, ",\"values\":")
    ret f.join3(a, out, values, "}")
}

fn followers(a: *mem.Arena, pf: PostFn, table: str, record: []const f.Field, add: bool) -> str {
    var name = "Followers"
    if pf.has_field && pf.field.len != 0usize { name = pf.field }
    let (cur, present) = field_value(record, name)
    var items = "["
    var count = 0usize
    var seen = false
    let n = list_len(cur)
    var i = 0usize
    if cur.kind != .Array { i = n }
    while i < cur.items.len && cur.kind == .Array {
        let text = value_json(a, cur.items[i])
        var keep = true
        if !add && str.eq(text, pf.user) { keep = false }
        if add && str.eq(text, pf.user) { seen = true }
        if keep {
            if count > 0usize { items = f.join(a, items, ",") }
            items = f.join(a, items, text)
            count += 1usize
        }
        i += 1usize
    }
    if add && !seen {
        if count > 0usize { items = f.join(a, items, ",") }
        items = f.join(a, items, pf.user)
    }
    items = f.join(a, items, "]")
    let values = f.join3(a, f.join3(a, "{", json_quote(a, name), ":{\"literal\":"), items, "}}")
    ret update_step(a, table, record, values)
}

// One post-function as the flow-engine step it compiles to, in `JSON.stringify` form; the table is the
// workflow's.
fn compile_post_function(a: *mem.Arena, pf: PostFn, table: str, record: []const f.Field) -> str {
    var out = ""
    if !pf.is_object || !is_post_type(pf.kind) {
        out = "{\"type\":\"unknown-post-function\""
        if pf.id.len != 0usize { out = f.join3(a, out, ",\"id\":", json_quote(a, pf.id)) }
        ret f.join(a, out, "}")
    }
    var finish = false
    if str.eq(pf.kind, "set-field") {
        var spec = "{}"
        if pf.has_value { spec = f.join3(a, "{", json_quote(a, pf.field), f.join3(a, ":{\"literal\":", pf.value, "}}")) } else if pf.has_value_spec { spec = f.join3(a, "{", json_quote(a, pf.field), f.join3(a, ":", pf.value_spec, "}")) }
        out = update_step(a, table, record, spec)
    } else if str.eq(pf.kind, "assign") {
        let spec = f.join3(a, "{", json_quote(a, pf.field), f.join3(a, ":{\"literal\":", pf.user, "}}"))
        out = update_step(a, table, record, spec)
    } else if str.eq(pf.kind, "clear-field") {
        let spec = f.join3(a, "{", json_quote(a, pf.field), ":{\"literal\":null}}")
        out = update_step(a, table, record, spec)
    } else if str.eq(pf.kind, "add-follower") {
        out = followers(a, pf, table, record, true)
    } else if str.eq(pf.kind, "remove-follower") {
        out = followers(a, pf, table, record, false)
    } else if str.eq(pf.kind, "create-record") {
        out = f.join3(a, "{\"type\":\"create\",\"table\":", pf.table, f.join3(a, ",\"values\":", pf.values, "}"))
    } else if str.eq(pf.kind, "update-record") {
        out = f.join3(a, "{\"type\":\"update\",\"table\":", pf.table, f.join3(a, ",\"target\":", pf.goal, f.join3(a, ",\"values\":", pf.values, "}")))
    } else if str.eq(pf.kind, "notify") {
        out = f.join3(a, "{\"type\":\"notification\",\"config\":", pf.config, "}")
    } else if str.eq(pf.kind, "webhook") {
        out = f.join3(a, "{\"type\":\"http\",\"config\":", pf.config, "}")
    } else {
        out = f.join3(a, "{\"type\":\"run-workflow\",\"workflowId\":", pf.workflow_id, "")
        if pf.has_params { out = f.join3(a, out, ",\"params\":", pf.params) }
        out = f.join(a, out, "}")
    }
    finish = pf.id.len != 0usize
    if finish { out = f.join3(a, out[0usize..out.len - 1usize], ",\"id\":", f.join(a, json_quote(a, pf.id), "}")) }
    ret out
}

// --- the guard ----------------------------------------------------------------------------------------------------

// The principal's permission to act on a transition: no permission set is unrestricted.
fn permits_actor(t: Transition, record: []const f.Field, p: Principal) -> bool {
    if !t.permissions.present { ret true }
    if p.has_id && contains(t.permissions.users, p.id) { ret true }
    var i = 0usize
    while i < t.permissions.roles.len {
        if contains(p.roles, t.permissions.roles[i]) { ret true }
        i += 1usize
    }
    i = 0usize
    while i < t.permissions.groups.len {
        if contains(p.groups, t.permissions.groups[i]) { ret true }
        i += 1usize
    }
    i = 0usize
    while i < t.permissions.people_fields.len {
        let (v, present) = field_value(record, t.permissions.people_fields[i])
        if p.has_id && list_includes_text(v, p.id) { ret true }
        i += 1usize
    }
    ret false
}

fn legacy_target(env: *const Env, key: str) -> (str, bool) {
    var i = 0usize
    while i < env.legacy.len {
        if str.eq(env.legacy[i].key, key) { ret (env.legacy[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// The state a record is in as the text `in` would coerce it to, and whether it is a text at all.
fn state_key(a: *mem.Arena, v: f.Value, present: bool) -> str {
    if !present { ret "undefined" }
    ret view.js_string(a, v)
}

// Does the transition leave from `current`? `use_legacy` consults the migration map for a stranded state.
fn from_matches(a: *mem.Arena, t: Transition, current: f.Value, present: bool, env: *const Env, use_legacy: bool) -> bool {
    if str.eq(t.from, "*") { ret true }
    if use_legacy {
        let (mapped, found) = legacy_target(env, state_key(a, current, present))
        if found { ret str.eq(mapped, t.from) }
    }
    ret present && current.kind == .Text && str.eq(current.s, t.from)
}

fn is_known_state(wf: Workflow, current: f.Value, present: bool) -> bool {
    if !present || current.kind != .Text { ret false }
    let (at, found) = state_index(wf, current.s)
    ret found
}

fn rule_ctx(record: []const f.Field, p: Principal, env: *const Env, inputs: []const f.Field) -> RuleCtx {
    ret RuleCtx { record: record, principal: p, env: env, inputs: inputs }
}

// The transitions offered to the principal for the record: from-state matches, permissions pass, conditions pass.
fn allowed_transitions(a: *mem.Arena, wf: Workflow, record: []const f.Field, p: Principal, env: *const Env) -> []const Transition {
    var none: []const Transition = zero
    let (out, e) = mem.alloc[Transition](a, wf.transitions.len + 1usize)
    if e != ok { ret none }
    let (current, present) = field_value(record, wf.status_field)
    let use_legacy = present && !is_known_state(wf, current, present) && env.has_legacy
    let empty_inputs: []const f.Field = zero
    var n = 0usize
    var i = 0usize
    while i < wf.transitions.len {
        let t = wf.transitions[i]
        var keep = true
        if !str.eq(t.from, t.to) && present && current.kind == .Text && str.eq(t.to, current.s) && str.eq(t.from, "*") { keep = false }
        if keep && !from_matches(a, t, current, present, env, use_legacy) { keep = false }
        if keep && !permits_actor(t, record, p) { keep = false }
        if keep {
            let c = rule_ctx(record, p, env, empty_inputs)
            var k = 0usize
            while k < t.conditions.len {
                if !eval_condition(a, t.conditions[k], &c) { keep = false }
                k += 1usize
            }
        }
        if keep {
            out[n] = t
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

type Explanation = struct { available: bool, reason: str, conditions: []const str }

// Why a transition is not offered: the failing gate class, without field values.
fn explain_transition(a: *mem.Arena, wf: Workflow, record: []const f.Field, t: Transition, p: Principal, env: *const Env) -> Explanation {
    var none: []const str = zero
    let (current, present) = field_value(record, wf.status_field)
    let use_legacy = present && !is_known_state(wf, current, present) && env.has_legacy
    if !from_matches(a, t, current, present, env, use_legacy) { ret Explanation { available: false, reason: err_wrong_state(), conditions: none } }
    if !permits_actor(t, record, p) { ret Explanation { available: false, reason: err_permission_denied(), conditions: none } }
    let empty_inputs: []const f.Field = zero
    let c = rule_ctx(record, p, env, empty_inputs)
    let (failing, e) = mem.alloc[str](a, t.conditions.len + 1usize)
    if e != ok { ret Explanation { available: false, reason: err_condition_failed(), conditions: none } }
    var n = 0usize
    var k = 0usize
    while k < t.conditions.len {
        if !eval_condition(a, t.conditions[k], &c) {
            var name = t.conditions[k].kind
            if t.conditions[k].has_all || t.conditions[k].has_any || name.len == 0usize { name = "group" }
            failing[n] = name
            n += 1usize
        }
        k += 1usize
    }
    if n > 0usize { ret Explanation { available: false, reason: err_condition_failed(), conditions: failing[0usize..n] } }
    ret Explanation { available: true, reason: "", conditions: none }
}

fn missing_screen_inputs(a: *mem.Arena, t: Transition, inputs: []const f.Field) -> []const str {
    var none: []const str = zero
    if !t.screen.present { ret none }
    let (out, e) = mem.alloc[str](a, t.screen.fields.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < t.screen.fields.len {
        if t.screen.fields[i].required {
            let (v, present) = field_value(inputs, t.screen.fields[i].field)
            if is_blank_input(v, present) {
                out[n] = t.screen.fields[i].field
                n += 1usize
            }
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// A committed transition: the next record, the history entry and the event.
type History = struct {
    record_id: f.Value,
    has_record_id: bool,
    workflow_id: str,
    workflow_version: f64,
    transition_id: str,
    transition_name: str,
    from: f.Value,
    has_from: bool,
    to: str,
    actor: str,
    has_actor: bool,
    on_behalf_of: str,
    has_on_behalf: bool,
    channel: str,
    has_inputs: bool,
    inputs: []const f.Field,
    override: bool,
    reason: str,
    has_reason: bool,
    at: str,
}

type Event = struct {
    table_id: str,
    from: f.Value,
    has_from: bool,
    to: str,
    transition_id: str,
    actor: str,
    has_actor: bool,
    cascade_depth: f64,
    dedup_key: str,
}

// A guard outcome: `ok`, or the machine-readable refusal with the members it carries.
type Outcome = struct {
    good: bool,
    error_code: str,
    transition_id: str,
    expected: f.Value,
    actual: f.Value,
    from: f.Value,
    has_from: bool,
    override: bool,
    condition: str,
    missing: []const str,
    validator: str,
    detail: str,
    field: str,
    has_field: bool,
    record: []const f.Field,
    history: History,
    event: Event,
    post_steps: []const str,
    self_transition: bool,
}

fn refusal(code: str) -> Outcome {
    var none_fields: []const f.Field = zero
    var none_strs: []const str = zero
    var h: History = zero
    var ev: Event = zero
    ret Outcome {
        good: false, error_code: code, transition_id: "", expected: f.blank(), actual: f.blank(), from: f.blank(), has_from: false,
        override: false, condition: "", missing: none_strs, validator: "", detail: "", field: "", has_field: false,
        record: none_fields, history: h, event: ev, post_steps: none_strs, self_transition: false,
    }
}

type Options = struct {
    principal: Principal,
    on_behalf_of: str,
    has_on_behalf: bool,
    inputs: []const f.Field,
    channel: str,
    now: str,
    has_expected_version: bool,
    expected_version: f.Value,
    override: bool,
    reason: str,
    cascade_depth: f64,
}

fn truthy_text(s: str) -> bool { ret s.len != 0usize }

// Set `name` on a copy of the record: an existing key keeps its place, a new one is appended.
fn with_field(a: *mem.Arena, fields: []const f.Field, name: str, value: f.Value) -> []const f.Field {
    let (out, e) = mem.alloc[f.Field](a, fields.len + 1usize)
    if e != ok { ret fields }
    var n = 0usize
    var placed = false
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) {
            out[n] = f.Field { name: name, value: value }
            placed = true
        } else {
            out[n] = fields[i]
        }
        n += 1usize
        i += 1usize
    }
    if !placed {
        out[n] = f.Field { name: name, value: value }
        n += 1usize
    }
    ret out[0usize..n]
}

// Execute a transition through the full guard: permissions, conditions, screen inputs and validators, in that
// order. The caller commits `record`, `history` and `event` in one transaction and runs `post_steps`.
fn execute_transition(a: *mem.Arena, wf: Workflow, record: []const f.Field, transition_id: str, o: Options, env: *const Env) -> Outcome {
    let (ti, tfound) = transition_index(wf, transition_id)
    if !tfound {
        var r = refusal(err_unknown_transition())
        r.transition_id = transition_id
        ret r
    }
    let t = wf.transitions[ti]
    let (current, present) = field_value(record, wf.status_field)
    let (version, has_version) = field_value(record, "_version")
    if o.has_expected_version && has_version {
        if !view.strict_equal(o.expected_version, true, version, true) {
            var r = refusal(err_version_conflict())
            r.expected = o.expected_version
            r.actual = version
            ret r
        }
    }
    let known = is_known_state(wf, current, present)
    let use_legacy = !known && env.has_legacy
    if o.override {
        var permitted = false
        if o.principal.present && contains(o.principal.permissions, "workflow.force-transition") { permitted = true }
        if !permitted {
            var r = refusal(err_permission_denied())
            r.override = true
            ret r
        }
        if o.reason.len == 0usize {
            var r = refusal(err_reason_required())
            r.override = true
            ret r
        }
    } else {
        if !from_matches(a, t, current, present, env, use_legacy) {
            var r = refusal(err_wrong_state())
            r.from = current
            r.has_from = present
            ret r
        }
        if !permits_actor(t, record, o.principal) { ret refusal(err_permission_denied()) }
        let c = rule_ctx(record, o.principal, env, o.inputs)
        var k = 0usize
        while k < t.conditions.len {
            if !eval_condition(a, t.conditions[k], &c) {
                var r = refusal(err_condition_failed())
                var name = t.conditions[k].kind
                if t.conditions[k].has_all || t.conditions[k].has_any || name.len == 0usize { name = "group" }
                r.condition = name
                ret r
            }
            k += 1usize
        }
        let missing = missing_screen_inputs(a, t, o.inputs)
        if missing.len > 0usize {
            var r = refusal(err_missing_inputs())
            r.missing = missing
            ret r
        }
        k = 0usize
        while k < t.validators.len {
            let verdict = eval_validator(a, t.validators[k], &c)
            if !verdict.good {
                var r = refusal(err_validator_failed())
                r.validator = verdict.validator
                r.detail = verdict.error_text
                r.field = verdict.field
                r.has_field = verdict.has_field
                ret r
            }
            k += 1usize
        }
    }
    // Commit.
    let self_transition = str.eq(t.from, t.to) && present && current.kind == .Text && str.eq(t.to, current.s)
    let (to_at, to_found) = state_index(wf, t.to)
    var next = with_field(a, record, wf.status_field, f.text(t.to))
    if has_version && version.kind == .Number { next = with_field(a, next, "_version", f.number(version.n + 1.0f64)) }
    if !self_transition {
        next = with_field(a, next, "_stateEnteredAt", f.text(o.now))
        var done = false
        if to_found && str.eq(wf.states[to_at].category, "done") { done = true }
        if done {
            let (resolved, has_resolved) = field_value(record, "_resolvedAt")
            if has_resolved && truthy(resolved) { next = with_field(a, next, "_resolvedAt", resolved) } else { next = with_field(a, next, "_resolvedAt", f.text(o.now)) }
        } else {
            next = with_field(a, next, "_resolvedAt", f.blank())
        }
    }
    let (rid, has_rid) = field_value(record, "id")
    var inputs_present = o.inputs.len > 0usize
    var channel = "ui"
    if o.channel.len != 0usize { channel = o.channel }
    let history = History {
        record_id: rid, has_record_id: has_rid, workflow_id: wf.id, workflow_version: wf.version, transition_id: t.id,
        transition_name: t.name, from: current, has_from: present, to: t.to, actor: o.principal.id,
        has_actor: o.principal.present && o.principal.has_id, on_behalf_of: o.on_behalf_of, has_on_behalf: o.has_on_behalf,
        channel: channel, has_inputs: inputs_present, inputs: o.inputs, override: o.override, reason: o.reason,
        has_reason: o.reason.len != 0usize, at: o.now,
    }
    var dedup_version = o.now
    if has_version { dedup_version = view.js_string(a, version) }
    var rid_text = "undefined"
    if has_rid { rid_text = view.js_string(a, rid) }
    let event = Event {
        table_id: wf.table_id, from: current, has_from: present, to: t.to, transition_id: t.id, actor: o.principal.id,
        has_actor: o.principal.present && o.principal.has_id, cascade_depth: o.cascade_depth,
        dedup_key: f.join3(a, rid_text, ":", f.join3(a, t.id, ":", dedup_version)),
    }
    var steps: []const str = zero
    if t.post_functions.len > 0usize {
        let (list, e) = mem.alloc[str](a, t.post_functions.len)
        if e == ok {
            var i = 0usize
            while i < t.post_functions.len {
                list[i] = compile_post_function(a, t.post_functions[i], wf.table_id, next)
                i += 1usize
            }
            steps = list
        }
    }
    var ok_outcome = refusal("")
    ok_outcome.good = true
    ok_outcome.record = next
    ok_outcome.history = history
    ok_outcome.event = event
    ok_outcome.post_steps = steps
    ok_outcome.self_transition = self_transition
    ret ok_outcome
}

type StatusWrite = struct { noop: bool, transition: Transition, has_transition: bool, error_code: str, candidates: []const Transition }

// A raw status write that names no transition: resolved when exactly one permitted transition reaches it.
fn resolve_status_write(a: *mem.Arena, wf: Workflow, record: []const f.Field, new_status: str, p: Principal, env: *const Env) -> StatusWrite {
    var none_t: Transition = zero
    var none_list: []const Transition = zero
    let (current, present) = field_value(record, wf.status_field)
    if present && current.kind == .Text && str.eq(current.s, new_status) {
        ret StatusWrite { noop: true, transition: none_t, has_transition: false, error_code: "", candidates: none_list }
    }
    let offered = allowed_transitions(a, wf, record, p, env)
    let (picked, e) = mem.alloc[Transition](a, offered.len + 1usize)
    if e != ok { ret StatusWrite { noop: false, transition: none_t, has_transition: false, error_code: "no-permitted-transition", candidates: none_list } }
    var n = 0usize
    var i = 0usize
    while i < offered.len {
        if str.eq(offered[i].to, new_status) && !str.eq(offered[i].from, offered[i].to) {
            picked[n] = offered[i]
            n += 1usize
        }
        i += 1usize
    }
    if n == 1usize { ret StatusWrite { noop: false, transition: picked[0usize], has_transition: true, error_code: "", candidates: none_list } }
    if n == 0usize { ret StatusWrite { noop: false, transition: none_t, has_transition: false, error_code: "no-permitted-transition", candidates: none_list } }
    ret StatusWrite { noop: false, transition: none_t, has_transition: false, error_code: "ambiguous-transition", candidates: picked[0usize..n] }
}

// --- simulation ---------------------------------------------------------------------------------------------------

type RuleReport = struct { kind: str, passed: bool, error_text: str, has_error: bool }

type Report = struct {
    found: bool,
    good: bool,
    transition_id: str,
    transition_name: str,
    from: str,
    to: str,
    from_state_ok: bool,
    permission_ok: bool,
    conditions: []const RuleReport,
    validators: []const RuleReport,
    missing_inputs: []const str,
    post_preview: []const str,
}

// A side-effect-free dry run of a transition: every condition and validator's verdict and the compiled
// post-functions, not executed.
fn simulate_transition(a: *mem.Arena, wf: Workflow, record: []const f.Field, transition_id: str, p: Principal, env: *const Env, inputs: []const f.Field) -> Report {
    var none_r: []const RuleReport = zero
    var none_s: []const str = zero
    let (ti, tfound) = transition_index(wf, transition_id)
    if !tfound {
        ret Report {
            found: false, good: false, transition_id: "", transition_name: "", from: "", to: "", from_state_ok: false,
            permission_ok: false, conditions: none_r, validators: none_r, missing_inputs: none_s, post_preview: none_s,
        }
    }
    let t = wf.transitions[ti]
    let (current, present) = field_value(record, wf.status_field)
    let c = rule_ctx(record, p, env, inputs)
    let (conds, e1) = mem.alloc[RuleReport](a, t.conditions.len + 1usize)
    let (vals, e2) = mem.alloc[RuleReport](a, t.validators.len + 1usize)
    let (posts, e3) = mem.alloc[str](a, t.post_functions.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret Report { found: false, good: false, transition_id: "", transition_name: "", from: "", to: "", from_state_ok: false, permission_ok: false, conditions: none_r, validators: none_r, missing_inputs: none_s, post_preview: none_s } }
    var all_pass = true
    var i = 0usize
    while i < t.conditions.len {
        var name = t.conditions[i].kind
        if t.conditions[i].has_all || t.conditions[i].has_any || name.len == 0usize { name = "group" }
        let passed = eval_condition(a, t.conditions[i], &c)
        conds[i] = RuleReport { kind: name, passed: passed, error_text: "", has_error: false }
        if !passed { all_pass = false }
        i += 1usize
    }
    i = 0usize
    while i < t.validators.len {
        let verdict = eval_validator(a, t.validators[i], &c)
        vals[i] = RuleReport { kind: t.validators[i].kind, passed: verdict.good, error_text: verdict.error_text, has_error: !verdict.good }
        if !verdict.good { all_pass = false }
        i += 1usize
    }
    i = 0usize
    while i < t.post_functions.len {
        posts[i] = compile_post_function(a, t.post_functions[i], wf.table_id, record)
        i += 1usize
    }
    let from_ok = from_matches(a, t, current, present, env, env.has_legacy)
    let perm_ok = permits_actor(t, record, p)
    let missing = missing_screen_inputs(a, t, inputs)
    ret Report {
        found: true, good: from_ok && perm_ok && all_pass && missing.len == 0usize, transition_id: t.id, transition_name: t.name,
        from: t.from, to: t.to, from_state_ok: from_ok, permission_ok: perm_ok, conditions: conds[0usize..t.conditions.len],
        validators: vals[0usize..t.validators.len], missing_inputs: missing, post_preview: posts[0usize..t.post_functions.len],
    }
}

// --- bulk ---------------------------------------------------------------------------------------------------------

type BulkOutcome = struct {
    record_id: f.Value,
    status: str,
    record: []const f.Field,
    error_code: str,
    detail: str,
    blocked_by_probe: bool,
    probe: Report,
    probe_error: str,
}

type Bulk = struct { policy: str, committed: usize, outcomes: []const BulkOutcome }

// Per-record guard evaluation, never weaker than the single-record path. `atomic` commits nothing unless every
// record passes a dry run first; `partial` commits what passes.
fn bulk_transition(a: *mem.Arena, wf: Workflow, records: []const []const f.Field, transition_id: str, o: Options, env: *const Env, atomic: bool) -> Bulk {
    var none_out: []const BulkOutcome = zero
    var policy = "partial"
    if atomic { policy = "atomic" }
    let (out, e) = mem.alloc[BulkOutcome](a, records.len + 1usize)
    if e != ok { ret Bulk { policy: policy, committed: 0usize, outcomes: none_out } }
    var blank_report: Report = zero
    if atomic {
        var r = 0usize
        while r < records.len {
            let probe = simulate_transition(a, wf, records[r], transition_id, o.principal, env, o.inputs)
            if !probe.good {
                var k = 0usize
                while k < records.len {
                    let (rid, has_id) = field_value(records[k], "id")
                    var item = BulkOutcome {
                        record_id: rid, status: "blocked", record: records[k], error_code: "", detail: "", blocked_by_probe: false,
                        probe: blank_report, probe_error: "atomic-abort",
                    }
                    if k == r {
                        item.blocked_by_probe = true
                        item.probe = probe
                        item.probe_error = ""
                    }
                    out[k] = item
                    k += 1usize
                }
                ret Bulk { policy: policy, committed: 0usize, outcomes: out[0usize..records.len] }
            }
            r += 1usize
        }
    }
    var committed = 0usize
    var r = 0usize
    while r < records.len {
        let (rid, has_id) = field_value(records[r], "id")
        let res = execute_transition(a, wf, records[r], transition_id, o, env)
        if res.good {
            committed += 1usize
            out[r] = BulkOutcome {
                record_id: rid, status: "transitioned", record: res.record, error_code: "", detail: "", blocked_by_probe: false,
                probe: blank_report, probe_error: "",
            }
        } else {
            var detail = res.detail
            if detail.len == 0usize { detail = nonempty(res.validator, res.condition) }
            out[r] = BulkOutcome {
                record_id: rid, status: "blocked", record: records[r], error_code: res.error_code, detail: detail,
                blocked_by_probe: false, probe: blank_report, probe_error: "",
            }
        }
        r += 1usize
    }
    ret Bulk { policy: policy, committed: committed, outcomes: out[0usize..records.len] }
}

// --- time in state ------------------------------------------------------------------------------------------------

// One history entry as time-in-state reads it.
type Entry = struct { from: str, to: str, at: str }

type Visit = struct { state: str, entered_at: str, left_at: str, has_left: bool, ms: f64 }

type Total = struct { state: str, ms: f64 }

type Dwell = struct { visits: []const Visit, totals: []const Total }

// Per-state visit durations from a transition history: self-transitions do not reset the clock, and an open visit
// runs to `now`.
fn time_in_state(a: *mem.Arena, entries: []const Entry, now: str) -> Dwell {
    var none_v: []const Visit = zero
    var none_t: []const Total = zero
    let (sorted, e1) = mem.alloc[Entry](a, entries.len + 1usize)
    let (visits, e2) = mem.alloc[Visit](a, entries.len + 1usize)
    let (totals, e3) = mem.alloc[Total](a, entries.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret Dwell { visits: none_v, totals: none_t } }
    var i = 0usize
    while i < entries.len {
        sorted[i] = entries[i]
        i += 1usize
    }
    // Stable ascending order by timestamp text.
    i = 1usize
    while i < entries.len {
        let v = sorted[i]
        var j = i
        while j > 0usize && str.compare(sorted[j - 1usize].at, v.at) > 0i32 {
            sorted[j] = sorted[j - 1usize]
            j -= 1usize
        }
        sorted[j] = v
        i += 1usize
    }
    var n = 0usize
    i = 0usize
    while i < entries.len {
        let en = sorted[i]
        if !str.eq(en.from, en.to) {
            var left = ""
            var has_left = false
            var k = i + 1usize
            while k < entries.len && !has_left {
                if !str.eq(sorted[k].from, sorted[k].to) {
                    left = sorted[k].at
                    has_left = true
                }
                k += 1usize
            }
            var end_text = now
            if has_left { end_text = left }
            let (end_ms, end_ok) = view.to_date(a, f.text(end_text))
            let (start_ms, start_ok) = view.to_date(a, f.text(en.at))
            var ms = 0.0f64 / 0.0f64
            if end_ok && start_ok { ms = end_ms - start_ms }
            visits[n] = Visit { state: en.to, entered_at: en.at, left_at: left, has_left: has_left, ms: ms }
            n += 1usize
        }
        i += 1usize
    }
    var nt = 0usize
    i = 0usize
    while i < n {
        var at = nt
        var k = 0usize
        while k < nt {
            if str.eq(totals[k].state, visits[i].state) { at = k }
            k += 1usize
        }
        if at == nt {
            totals[nt] = Total { state: visits[i].state, ms: visits[i].ms }
            nt += 1usize
        } else {
            totals[at].ms = totals[at].ms + visits[i].ms
        }
        i += 1usize
    }
    ret Dwell { visits: visits[0usize..n], totals: totals[0usize..nt] }
}

// --- templates ----------------------------------------------------------------------------------------------------

fn split_on(a: *mem.Arena, s: str, sep: u8) -> []const str {
    var none: []const str = zero
    var count = 1usize
    var i = 0usize
    while i < s.len {
        if s[i] == sep { count += 1usize }
        i += 1usize
    }
    let (out, e) = mem.alloc[str](a, count)
    if e != ok { ret none }
    var n = 0usize
    var start = 0usize
    i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == sep {
            out[n] = s[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// A template's source: its name, initial state, states `id,label,category;...` and transitions
// `slug,name,from,to,extra;...` where extra is `-`, `rf` (required Assignee), `ap` (review approval), `sr:Field`
// (a required screen input) or `pf` (a KnownError post-function).
type TemplateSource = struct { name: str, initial: str, states: str, transitions: str, known: bool }

fn template_source(key: str) -> TemplateSource {
    if str.eq(key, "basic") {
        ret TemplateSource { name: "Basic", initial: "todo", states: "todo,To do,todo;doing,Progress,in-progress;done,Done,done", transitions: "start,Start,todo,doing,-;finish,Finish,doing,done,-;reopen,Reopen,done,todo,-", known: true }
    }
    if str.eq(key, "software-delivery") {
        ret TemplateSource { name: "Software delivery", initial: "backlog", states: "backlog,Backlog,todo;progress,Progress,in-progress;review,In review,in-progress;done,Done,done", transitions: "start,Start,backlog,progress,-;submit-for-review,Submit for review,progress,review,-;request-changes,Request changes,review,progress,-;approve,Approve,review,done,rf;cancel,Cancel,*,backlog,-", known: true }
    }
    if str.eq(key, "approval-gated") {
        ret TemplateSource { name: "Approval gated", initial: "draft", states: "draft,Draft,todo;submitted,Submitted,in-progress;approved,Approved,done;rejected,Rejected,done", transitions: "submit,Submit,draft,submitted,-;approve,Approve,submitted,approved,ap;reject,Reject,submitted,rejected,sr:Reason;reopen,Reopen,rejected,draft,-", known: true }
    }
    if str.eq(key, "alert") {
        ret TemplateSource { name: "Alert lifecycle", initial: "open", states: "open,Open,todo;acked,Acknowledged,in-progress;snoozed,Snoozed,in-progress;closed,Closed,done", transitions: "ack,Ack,open,acked,-;unack,Unack,acked,open,-;snooze,Snooze,open,snoozed,sr:SnoozeUntil;unsnooze,Unsnooze,snoozed,open,-;close,Close,*,closed,-;reopen,Reopen,closed,open,-", known: true }
    }
    if str.eq(key, "incident") {
        ret TemplateSource { name: "Incident lifecycle", initial: "open", states: "open,Open,todo;investigating,Investigating,in-progress;identified,Identified,in-progress;monitoring,Monitoring,in-progress;resolved,Resolved,done", transitions: "investigate,Investigate,open,investigating,-;identify,Identify,investigating,identified,-;monitor,Monitor,identified,monitoring,-;resolve,Resolve,*,resolved,sr:Resolution;reopen,Reopen,resolved,investigating,-", known: true }
    }
    if str.eq(key, "problem") {
        ret TemplateSource { name: "Problem itil", initial: "open", states: "open,Open,todo;investigating,Investigating,in-progress;known-error,Known error,in-progress;resolved,Resolved,done;closed,Closed,done", transitions: "investigate,Investigate,open,investigating,-;mark-known-error,Mark known error,investigating,known-error,pf;resolve,Resolve,investigating,resolved,-;resolve-known-error,Resolve known error,known-error,resolved,-;close,Close,resolved,closed,-;reopen,Reopen,closed,investigating,-", known: true }
    }
    if str.eq(key, "review") {
        ret TemplateSource { name: "Review pir", initial: "draft", states: "draft,Draft,todo;in-review,In review,in-progress;published,Published,done", transitions: "submit,Submit,draft,in-review,-;publish,Action,in-review,published,-;send-back,Send back,in-review,draft,sr:Reason;reopen,Reopen,published,draft,-", known: true }
    }
    ret TemplateSource { name: "", initial: "", states: "", transitions: "", known: false }
}

fn blank_rule(raw: str, kind: str) -> Rule {
    var none_str: []const str = zero
    var none_rules: []const Rule = zero
    ret Rule {
        raw: raw, is_object: true, kind: kind, keys: none_str, has_all: false, has_any: false, children: none_rules,
        roles: none_str, groups: none_str, fields: none_str, field: "", filter: view.empty_group("and"), has_filter: false,
        expr: "", table: "", approval: "", relation: "", quantifier: "", has_quantifier: false, message: "",
    }
}

fn blank_post(raw: str, kind: str) -> PostFn {
    var none_str: []const str = zero
    ret PostFn {
        raw: raw, is_object: true, kind: kind, id: "", keys: none_str, field: "", has_field: false, value: "", has_value: false,
        value_spec: "", has_value_spec: false, user: "", has_user: false, table: "", values: "", has_values: false, goal: "",
        has_goal: false, config: "", has_config: false, workflow_id: "", has_workflow_id: false, params: "", has_params: false,
    }
}

// A draft workflow from a built-in template; `false` for an unknown key.
fn template(a: *mem.Arena, key: str, table_id: str, status_field: str, generated_id: str) -> (Workflow, bool) {
    let src = template_source(key)
    var wf = empty_workflow(generated_id, table_id, status_field, src.name)
    if !src.known { ret (wf, false) }
    let state_rows = split_on(a, src.states, 59u8)
    let transition_rows = split_on(a, src.transitions, 59u8)
    let (states, e1) = mem.alloc[State](a, state_rows.len + 1usize)
    let (transitions, e2) = mem.alloc[Transition](a, transition_rows.len + 1usize)
    if e1 != ok || e2 != ok { ret (wf, false) }
    var i = 0usize
    while i < state_rows.len {
        let c = split_on(a, state_rows[i], 44u8)
        states[i] = normalize_state(c[0usize], c[1usize], true, c[2usize])
        i += 1usize
    }
    var none_rules: []const Rule = zero
    var none_post: []const PostFn = zero
    i = 0usize
    while i < transition_rows.len {
        let c = split_on(a, transition_rows[i], 44u8)
        var t = Transition {
            id: f.join3(a, c[0usize], "_", f.join3(a, c[2usize], "_", c[3usize])), name: c[1usize], description: "", icon: "",
            has_icon: false, from: c[2usize], to: c[3usize], primary: false, conditions: none_rules, validators: none_rules,
            post_functions: none_post, permissions: no_permissions(), screen: no_screen(),
        }
        let extra = c[4usize]
        if str.eq(extra, "rf") {
            let (rules, e) = mem.alloc[Rule](a, 1usize)
            let (names, en) = mem.alloc[str](a, 1usize)
            let (keys, ek) = mem.alloc[str](a, 2usize)
            if e == ok && en == ok && ek == ok {
                names[0usize] = "Assignee"
                keys[0usize] = "type"
                keys[1usize] = "fields"
                var r = blank_rule("{\"type\":\"required-fields\",\"fields\":[\"Assignee\"]}", "required-fields")
                r.keys = keys
                r.fields = names
                rules[0usize] = r
                t.validators = rules
            }
        } else if str.eq(extra, "ap") {
            let (rules, e) = mem.alloc[Rule](a, 1usize)
            let (keys, ek) = mem.alloc[str](a, 2usize)
            if e == ok && ek == ok {
                keys[0usize] = "type"
                keys[1usize] = "approval"
                var r = blank_rule("{\"type\":\"approval\",\"approval\":\"review\"}", "approval")
                r.keys = keys
                r.approval = "review"
                rules[0usize] = r
                t.validators = rules
            }
        } else if extra.len > 3usize && str.eq(extra[0usize..3usize], "sr:") {
            let (fields, e) = mem.alloc[ScreenField](a, 1usize)
            if e == ok {
                fields[0usize] = ScreenField { field: extra[3usize..extra.len], required: true }
                t.screen = Screen { present: true, fields: fields }
            }
        } else if str.eq(extra, "pf") {
            let (posts, e) = mem.alloc[PostFn](a, 1usize)
            let (keys, ek) = mem.alloc[str](a, 3usize)
            if e == ok && ek == ok {
                keys[0usize] = "type"
                keys[1usize] = "field"
                keys[2usize] = "value"
                var p = blank_post("{\"type\":\"set-field\",\"field\":\"KnownError\",\"value\":true}", "set-field")
                p.keys = keys
                p.field = "KnownError"
                p.has_field = true
                p.value = "true"
                p.has_value = true
                posts[0usize] = p
                t.post_functions = posts
            }
        }
        transitions[i] = t
        i += 1usize
    }
    wf.states = states[0usize..state_rows.len]
    wf.transitions = transitions[0usize..transition_rows.len]
    wf.initial_state = src.initial
    wf.has_initial = true
    ret (wf, true)
}
