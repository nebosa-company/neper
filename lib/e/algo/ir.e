// The workflow definition IR (L036, the runtime half), after appdor's `src/workflow/ir.js`: the serializable definition a
// durable run executes, as an `e.fmt.json` value. The step catalogue (each type's kind, whether it suspends or mutates,
// the child-step arrays its body walks, the config fields that are never templates, what it leaves in `steps.<id>`), the
// trigger catalogue, `normalize_workflow` (defaults without inventing ids, so a half-typed definition never throws),
// `walk_steps` and `collect_step_ids`, `validate_workflow` (every problem, not the first), and the execution keys a journal
// entry is matched by (`execution_key`, `loop_frame`, `fork_frame`).
//
// Step ids are mandatory and stable because a restarted run is replayed from its journal and an entry is matched to its
// step by id; the validator refuses a definition without them, a charset outside `[A-Za-z0-9_-]` and a duplicate.
//
// Messages are the catalogue keys humanized, which is what appdor's `t()` answers under plain Node ("Step needs id").
// What the reference takes from other modules is injected: the routing matcher's verdict on one rule (`RoutingCheck`,
// the empty text for none) and the schedule normalizer's (`e.algo.trigger`, with the caller's `Clock`).
//
// Differences from appdor's: a step type is looked up in the catalogue and the plugin registry only (JavaScript also finds
// `constructor` and the other members of an object's prototype); `is_serializable` is not provided because every
// `e.fmt.json` value is serializable by construction.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.trigger as trigger
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

// What the routing matcher says about one rule of an approval's routing list: "" when it is usable.
type RoutingCheck = fn(json.Value) -> str

type Plugin = struct { key: str, label: str }

// The installed apps' step types (appdor's module-level map): all `effect`s that mutate and that no runtime executes yet.
type Plugins = struct { items: list.List[Plugin] }

type StepInfo = struct { found: bool, kind: str, suspends: bool, mutates: bool, body: str, raw: str, output: str, installed: bool, runnable: bool }

type Problem = struct { path: str, message: str }

// --- catalogue ------------------------------------------------------------------------------------------------------

fn output_types() -> str { ret "none,value,text,record,records,response,result,receipt,run,approval" }

fn info(kind: str, suspends: bool, mutates: bool, body: str, raw: str, output: str) -> StepInfo {
    ret StepInfo { found: true, kind: kind, suspends: suspends, mutates: mutates, body: body, raw: raw, output: output, installed: false, runnable: true }
}

fn not_found() -> StepInfo {
    ret StepInfo { found: false, kind: "", suspends: false, mutates: false, body: "", raw: "", output: "", installed: false, runnable: false }
}

// A core step type's facts; `found` is false for anything else. `body` and `raw` are comma-joined names.
fn core_step(name: str) -> StepInfo {
    if str.eq(name, "if") { ret info("control", false, false, "then,else", "", "none") }
    if str.eq(name, "case") { ret info("control", false, false, "cases.steps,default", "", "none") }
    if str.eq(name, "foreach") { ret info("control", false, false, "steps", "as", "none") }
    if str.eq(name, "fork") { ret info("control", true, false, "branches.steps", "join,branches.name", "none") }
    if str.eq(name, "try") { ret info("control", false, false, "steps,catch", "", "none") }
    if str.eq(name, "stop") { ret info("control", false, false, "", "", "none") }
    if str.eq(name, "fail") { ret info("control", false, false, "", "", "none") }
    if str.eq(name, "delay") { ret info("control", true, false, "", "", "none") }
    if str.eq(name, "wait-signal") { ret info("control", true, false, "", "signal,timeoutAction", "value") }
    if str.eq(name, "approval") { ret info("effect", true, true, "", "rule,timeoutAction,table,routing,callbackSecret,evidenceFields", "approval") }
    if str.eq(name, "set") { ret info("data", false, false, "", "name", "value") }
    if str.eq(name, "transform") { ret info("data", false, false, "", "pipeline.op", "value") }
    if str.eq(name, "parse") { ret info("data", false, false, "", "format", "value") }
    if str.eq(name, "serialize") { ret info("data", false, false, "", "format", "text") }
    if str.eq(name, "query") { ret info("data", false, false, "", "table", "records") }
    if str.eq(name, "webhook") { ret info("effect", false, true, "", "", "response") }
    if str.eq(name, "emit-event") { ret info("effect", false, true, "", "eventType,schemaVersion,retainDays", "record") }
    if str.eq(name, "connector") { ret info("effect", false, true, "", "channel,action,connectionId", "result") }
    if str.eq(name, "mcpTool") { ret info("effect", false, true, "", "connectionId,tool", "result") }
    if str.eq(name, "create-record") { ret info("effect", false, true, "", "table", "record") }
    if str.eq(name, "update-record") { ret info("effect", false, true, "", "table", "record") }
    if str.eq(name, "delete-record") { ret info("effect", false, true, "", "table", "none") }
    if str.eq(name, "email") { ret info("effect", false, true, "", "", "receipt") }
    if str.eq(name, "notify") { ret info("effect", false, true, "", "", "receipt") }
    if str.eq(name, "python") { ret info("effect", false, true, "", "source,requirements", "value") }
    if str.eq(name, "run-workflow") { ret info("effect", true, true, "", "workflowId,mode", "run") }
    if str.eq(name, "log") { ret info("data", false, false, "", "", "none") }
    ret not_found()
}

// A trigger type's ingress and config fields, or `found` false.
type TriggerInfo = struct { found: bool, ingress: str, config: str, output: str }

fn trigger_type(name: str) -> TriggerInfo {
    if str.eq(name, "webhook") { ret TriggerInfo { found: true, ingress: "http", config: "path,auth,secret,dedupeKey", output: "response" } }
    if str.eq(name, "table-change") { ret TriggerInfo { found: true, ingress: "http", config: "table,events,watchFields,filter,excludeOrigins", output: "" } }
    if str.eq(name, "metadata-change") { ret TriggerInfo { found: true, ingress: "http", config: "objects,events", output: "" } }
    if str.eq(name, "platform-event") { ret TriggerInfo { found: true, ingress: "event-bus", config: "eventType,schemaVersion,filter", output: "" } }
    if str.eq(name, "view-membership") { ret TriggerInfo { found: true, ingress: "http", config: "viewId,events", output: "" } }
    if str.eq(name, "form-submitted") { ret TriggerInfo { found: true, ingress: "http", config: "formId,submitterClass", output: "" } }
    if str.eq(name, "inbound-email") { ret TriggerInfo { found: true, ingress: "http", config: "mailbox,events", output: "" } }
    if str.eq(name, "button") { ret TriggerInfo { found: true, ingress: "http", config: "label,surface,confirm,inputs", output: "" } }
    if str.eq(name, "schedule") { ret TriggerInfo { found: true, ingress: "timer", config: "cron,timezone,catchUp", output: "" } }
    if str.eq(name, "manual") { ret TriggerInfo { found: true, ingress: "manual", config: "inputs", output: "" } }
    if str.eq(name, "workflow-call") { ret TriggerInfo { found: true, ingress: "internal", config: "inputs", output: "" } }
    ret TriggerInfo { found: false, ingress: "", config: "", output: "" }
}

fn metadata_objects() -> str { ret "page" }

fn metadata_events() -> str { ret "insert,update,delete,restore" }

fn run_statuses() -> str { ret "pending,running,suspended,paused,succeeded,failed,cancelled,suppressed,skipped-quota" }

fn terminal_statuses() -> str { ret "succeeded,failed,cancelled" }

fn in_csv(csv: str, name: str) -> bool {
    var begin = 0usize
    var at = 0usize
    while at <= csv.len {
        if at == csv.len || csv[at] == 44u8 {
            if str.eq(csv[begin..at], name) { ret true }
            begin = at + 1usize
        }
        at += 1usize
    }
    ret false
}

fn new_plugins(a: *mem.Arena) -> (Plugins, err) {
    let (items, items_error) = list.init[Plugin](a, 4usize)
    ret (Plugins { items: items }, items_error)
}

// Register an installed app's step type under `namespace.id`: the key, or "" and the refusal. A core id is refused.
fn register_plugin_step(a: *mem.Arena, p: *Plugins, namespace: str, id: str, label: str) -> (str, str, err) {
    if namespace.len == 0usize || id.len == 0usize { ret ("", "namespace-and-id-required", ok) }
    if core_step(id).found {
        let (head, head_error) = str.concat(a, "collides-with-core:", id)
        ret ("", head, head_error)
    }
    let (dotted, dotted_error) = str.concat(a, namespace, ".")
    if dotted_error != ok { ret ("", "", dotted_error) }
    let (key, key_error) = str.concat(a, dotted, id)
    if key_error != ok { ret ("", "", key_error) }
    var shown = label
    if label.len == 0usize { shown = id }
    var at = 0usize
    while at < p.items.len {
        if str.eq(p.items.items[at].key, key) {
            p.items.items[at].label = shown
            ret (key, "", ok)
        }
        at += 1usize
    }
    let pushed = list.push[Plugin](&p.items, Plugin { key: key, label: shown })
    ret (key, "", pushed)
}

// The label an installed step type was registered with, or "" when it is not installed.
fn plugin_label(p: *const Plugins, key: str) -> str {
    var at = 0usize
    while at < p.items.len {
        if str.eq(p.items.items[at].key, key) { ret p.items.items[at].label }
        at += 1usize
    }
    ret ""
}

fn unregister_plugin_step(p: *Plugins, key: str) -> bool {
    var at = 0usize
    while at < p.items.len {
        if str.eq(p.items.items[at].key, key) {
            var to = at
            while to + 1usize < p.items.len {
                p.items.items[to] = p.items.items[to + 1usize]
                to += 1usize
            }
            p.items.len -= 1usize
            ret true
        }
        at += 1usize
    }
    ret false
}

// Core first, then installed apps: an installed one is an `effect` that mutates and does not run yet.
fn step_type(p: *const Plugins, name: str) -> StepInfo {
    let core = core_step(name)
    if core.found { ret core }
    var at = 0usize
    while at < p.items.len {
        if str.eq(p.items.items[at].key, name) {
            ret StepInfo { found: true, kind: "effect", suspends: false, mutates: true, body: "", raw: "", output: "", installed: true, runnable: false }
        }
        at += 1usize
    }
    ret not_found()
}

// --- values ---------------------------------------------------------------------------------------------------------

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

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

// JavaScript truthiness: null, false, 0 and "" are falsy; every container is truthy.
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

// `v[key]` when it is present and truthy, else `fallback` (`v[key] || fallback`).
fn or_falsy(v: json.Value, key: str, fallback: json.Value) -> json.Value {
    let (x, found) = get(v, key)
    if !found || !truthy(x) { ret fallback }
    ret x
}

// `v[key]`, absent or falsy as `.Null`: the operand of a `!x` test.
fn value_of(v: json.Value, key: str) -> json.Value {
    let (x, found) = get(v, key)
    if !found { ret .Null }
    ret x
}

type Obj = list.List[json.Member]

fn new_obj(a: *mem.Arena) -> (Obj, err) {
    let (o, o_error) = list.init[json.Member](a, 8usize)
    ret (o, o_error)
}

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

fn empty_object() -> json.Value {
    var none: []const json.Member = zero
    ret json.Value{ Object: none }
}

fn empty_array() -> json.Value {
    var none: []const json.Value = zero
    ret json.Value{ Array: none }
}

fn number_lexeme(s: str) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: s } } }

// --- normalization --------------------------------------------------------------------------------------------------

fn normalize_trigger(a: *mem.Arena, trigger_value: json.Value) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    if !truthy(trigger_value) {
        try put(&out, "type", text("manual"))
        try put(&out, "config", empty_object())
        ret (obj_value(&out), ok)
    }
    try put(&out, "type", or_falsy(trigger_value, "type", text("manual")))
    try put(&out, "config", or_falsy(trigger_value, "config", empty_object()))
    try put(&out, "filter", or_falsy(trigger_value, "filter", .Null))
    ret (obj_value(&out), ok)
}

fn normalize_steps(a: *mem.Arena, steps: []const json.Value) -> (json.Value, err) {
    let (out, out_error) = list.init[json.Value](a, steps.len + 1usize)
    if out_error != ok { ret (.Null, out_error) }
    var normalized = out
    var at = 0usize
    while at < steps.len {
        let (s, s_error) = normalize_step(a, steps[at])
        if s_error != ok { ret (.Null, s_error) }
        try list.push[json.Value](&normalized, s)
        at += 1usize
    }
    ret (json.Value{ Array: list.slice_const[json.Value](&normalized) }, ok)
}

fn normalize_group(a: *mem.Arena, group: json.Value, with_when: bool) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    if with_when {
        let (w, have_w) = get(group, "when")
        if have_w { try put(&out, "when", w) }
    }
    let (n, have_n) = get(group, "name")
    if have_n { try put(&out, "name", n) }
    let (steps_value, steps_found) = get(group, "steps")
    var steps: []const json.Value = zero
    if steps_found && truthy(steps_value) {
        let (items, is_array) = items_of(steps_value)
        if is_array { steps = items }
    }
    let (normalized, normalized_error) = normalize_steps(a, steps)
    if normalized_error != ok { ret (.Null, normalized_error) }
    try put(&out, "steps", normalized)
    ret (obj_value(&out), ok)
}

// A step with defaults filled in: `name` falls back to the id, `config` to `{}`, and the child arrays are normalized in
// place. Members the step does not have stay absent.
fn normalize_step(a: *mem.Arena, step: json.Value) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    let (id, have_id) = get(step, "id")
    if have_id { try put(&out, "id", id) }
    let (type_value, have_type) = get(step, "type")
    if have_type { try put(&out, "type", type_value) }
    let (name, have_name) = get(step, "name")
    if have_name && truthy(name) {
        try put(&out, "name", name)
    } else if have_id {
        try put(&out, "name", id)
    }
    try put(&out, "config", or_falsy(step, "config", empty_object()))
    let (retries, have_retries) = get(step, "retries")
    if have_retries { try put(&out, "retries", retries) }
    let (continue_on_error, have_continue) = get(step, "continueOnError")
    if have_continue { try put(&out, "continueOnError", continue_on_error) }
    let (condition, have_condition) = get(step, "if")
    if have_condition { try put(&out, "if", condition) }
    var keys: [5]str = zero
    keys[0] = "then"
    keys[1] = "else"
    keys[2] = "steps"
    keys[3] = "catch"
    keys[4] = "default"
    var k = 0usize
    while k < 5usize {
        let (child, have_child) = get(step, keys[k])
        let (items, is_array) = items_of(child)
        if have_child && is_array {
            let (normalized, normalized_error) = normalize_steps(a, items)
            if normalized_error != ok { ret (.Null, normalized_error) }
            try put(&out, keys[k], normalized)
        }
        k += 1usize
    }
    let (cases_value, have_cases) = get(step, "cases")
    let (case_items, cases_are_array) = items_of(cases_value)
    if have_cases && cases_are_array {
        let (list_out, list_error) = list.init[json.Value](a, case_items.len + 1usize)
        if list_error != ok { ret (.Null, list_error) }
        var cases = list_out
        var c = 0usize
        while c < case_items.len {
            let (group, group_error) = normalize_group(a, case_items[c], true)
            if group_error != ok { ret (.Null, group_error) }
            try list.push[json.Value](&cases, group)
            c += 1usize
        }
        try put(&out, "cases", json.Value{ Array: list.slice_const[json.Value](&cases) })
    }
    let (branches_value, have_branches) = get(step, "branches")
    let (branch_items, branches_are_array) = items_of(branches_value)
    if have_branches && branches_are_array {
        let (list_out, list_error) = list.init[json.Value](a, branch_items.len + 1usize)
        if list_error != ok { ret (.Null, list_error) }
        var branches = list_out
        var b = 0usize
        while b < branch_items.len {
            let (group, group_error) = normalize_group(a, branch_items[b], false)
            if group_error != ok { ret (.Null, group_error) }
            try list.push[json.Value](&branches, group)
            b += 1usize
        }
        try put(&out, "branches", json.Value{ Array: list.slice_const[json.Value](&branches) })
    }
    ret (obj_value(&out), ok)
}

// A definition with its defaults: enabled unless `enabled` is false, version 1, the default settings overridden by the
// definition's own, trigger `manual` when absent.
fn normalize_workflow(a: *mem.Arena, definition: json.Value) -> (json.Value, err) {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret (.Null, o_error) }
    var out = o
    try put(&out, "id", or_falsy(definition, "id", .Null))
    try put(&out, "name", or_falsy(definition, "name", text("Untitled")))
    let (version, have_version) = get(definition, "version")
    if have_version && !is_null(version) { try put(&out, "version", version) } else { try put(&out, "version", number_lexeme("1")) }
    let (enabled, have_enabled) = get(definition, "enabled")
    var is_enabled = true
    if have_enabled {
        switch enabled {
        case .Bool as b:
            is_enabled = b
        default:
            is_enabled = true
        }
    }
    try put(&out, "enabled", json.Value{ Bool: is_enabled })
    let (trigger_out, trigger_error) = normalize_trigger(a, value_of(definition, "trigger"))
    if trigger_error != ok { ret (.Null, trigger_error) }
    try put(&out, "trigger", trigger_out)
    let (steps_value, steps_found) = get(definition, "steps")
    var steps: []const json.Value = zero
    if steps_found && truthy(steps_value) {
        let (items, is_array) = items_of(steps_value)
        if is_array { steps = items }
    }
    let (steps_out, steps_error) = normalize_steps(a, steps)
    if steps_error != ok { ret (.Null, steps_error) }
    try put(&out, "steps", steps_out)
    try put(&out, "inputs", or_falsy(definition, "inputs", empty_object()))
    let (s, s_error) = new_obj(a)
    if s_error != ok { ret (.Null, s_error) }
    var settings = s
    try put(&settings, "maxSteps", number_lexeme("10000"))
    try put(&settings, "maxDurationMs", number_lexeme("604800000"))
    try put(&settings, "onFailure", text("stop"))
    try put(&settings, "concurrency", text("parallel"))
    let (r, r_error) = new_obj(a)
    if r_error != ok { ret (.Null, r_error) }
    var retry = r
    try put(&retry, "attempts", number_lexeme("3"))
    try put(&retry, "backoffMs", number_lexeme("1000"))
    try put(&retry, "multiplier", number_lexeme("2"))
    try put(&retry, "maxBackoffMs", number_lexeme("60000"))
    try put(&settings, "retryPolicy", obj_value(&retry))
    try assign(&settings, or_falsy(definition, "settings", empty_object()))
    try put(&out, "settings", obj_value(&settings))
    ret (obj_value(&out), ok)
}

// --- traversal ------------------------------------------------------------------------------------------------------

// One visited step and the ids of the steps that contain it, outermost first ("" for a parent without an id).
type Visit = struct { step: json.Value, path: []const str }

type Visits = struct { items: list.List[Visit], failed: bool }

fn id_text(step: json.Value) -> str {
    let (id, found) = get(step, "id")
    if !found { ret "" }
    let (s, is_text) = string_of(id)
    if !is_text { ret "" }
    ret s
}

fn walk_into(a: *mem.Arena, out: *Visits, steps: json.Value, path: []const str) {
    let (items, is_array) = items_of(steps)
    if !is_array { ret }
    var at = 0usize
    while at < items.len {
        let step = items[at]
        let pushed = list.push[Visit](&out.items, Visit { step: step, path: path })
        if pushed != ok {
            out.failed = true
            ret
        }
        let (longer, longer_error) = mem.alloc[str](a, path.len + 1usize)
        if longer_error != ok {
            out.failed = true
            ret
        }
        var p = 0usize
        while p < path.len {
            longer[p] = path[p]
            p += 1usize
        }
        longer[path.len] = id_text(step)
        let child_path = longer[0usize..path.len + 1usize]
        var keys: [5]str = zero
        keys[0] = "then"
        keys[1] = "else"
        keys[2] = "steps"
        keys[3] = "catch"
        keys[4] = "default"
        var k = 0usize
        while k < 5usize {
            let (child, have_child) = get(step, keys[k])
            if have_child { walk_into(a, out, child, child_path) }
            k += 1usize
        }
        var groups: [2]str = zero
        groups[0] = "cases"
        groups[1] = "branches"
        var g = 0usize
        while g < 2usize {
            let (group_list, have_group_list) = get(step, groups[g])
            let (group_items, group_is_array) = items_of(group_list)
            if have_group_list && group_is_array {
                var gi = 0usize
                while gi < group_items.len {
                    let (group_steps, have_group_steps) = get(group_items[gi], "steps")
                    if have_group_steps { walk_into(a, out, group_steps, child_path) }
                    gi += 1usize
                }
            }
            g += 1usize
        }
        at += 1usize
    }
}

// Every step, depth-first: a step, then the children under `then`, `else`, `steps`, `catch`, `default`, then each
// case's and branch's steps.
fn walk_steps(a: *mem.Arena, steps: json.Value) -> ([]const Visit, err) {
    let (items, items_error) = list.init[Visit](a, 16usize)
    if items_error != ok { ret (zero, items_error) }
    var visits = Visits { items: items, failed: false }
    var none: []const str = zero
    walk_into(a, &visits, steps, none)
    if visits.failed { ret (zero, Exhausted) }
    ret (list.slice_const[Visit](&visits.items), ok)
}

error Exhausted

fn collect_step_ids(a: *mem.Arena, definition: json.Value) -> ([]const str, err) {
    let (visits, visits_error) = walk_steps(a, value_of(definition, "steps"))
    if visits_error != ok { ret (zero, visits_error) }
    let (ids, ids_error) = mem.alloc[str](a, visits.len + 1usize)
    if ids_error != ok { ret (zero, ids_error) }
    var at = 0usize
    while at < visits.len {
        ids[at] = id_text(visits[at].step)
        at += 1usize
    }
    ret (ids[0usize..visits.len], ok)
}

// --- validation -----------------------------------------------------------------------------------------------------

// `8-4-4-4-12` hex digits, either case.
fn uuid_shape(s: str) -> bool {
    if s.len != 36usize { ret false }
    var at = 0usize
    while at < 36usize {
        let c = s[at]
        if at == 8usize || at == 13usize || at == 18usize || at == 23usize {
            if c != 45u8 { ret false }
        } else {
            let hex = (c >= 48u8 && c <= 57u8) || (c >= 97u8 && c <= 102u8) || (c >= 65u8 && c <= 70u8)
            if !hex { ret false }
        }
        at += 1usize
    }
    ret true
}

fn is_name_char(c: u8) -> bool {
    ret (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8 || c == 45u8
}

// `/^[a-z][a-z0-9_-]*(?::[a-z][a-z0-9_-]*)?(?:\.[a-z][a-z0-9_-]*)*$/`: a name, an optional `:name`, then `.name`s.
fn event_type_pattern(s: str) -> bool {
    var at = 0usize
    var segments = 0usize
    var colon_used = false
    var more = true
    while more {
        if at >= s.len || s[at] < 97u8 || s[at] > 122u8 { ret false }
        at += 1usize
        while at < s.len && is_name_char(s[at]) { at += 1usize }
        segments += 1usize
        if at == s.len { ret true }
        if s[at] == 58u8 && !colon_used && segments == 1usize {
            colon_used = true
            at += 1usize
            if at >= s.len || s[at] < 97u8 || s[at] > 122u8 { ret false }
            at += 1usize
            while at < s.len && is_name_char(s[at]) { at += 1usize }
            if at == s.len { ret true }
        }
        if s[at] == 46u8 {
            at += 1usize
            more = true
        } else {
            ret false
        }
    }
    ret false
}

fn step_id_charset(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    while at < s.len {
        let c = s[at]
        let good = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8 || c == 45u8
        if !good { ret false }
        at += 1usize
    }
    ret true
}

// `Number(v)` for the JSON kinds a config carries: null is 0, booleans 0 and 1, a string its decimal value (an empty or
// blank one 0), anything else NaN.
fn to_number(v: json.Value) -> (f64, bool) {
    var out = 0.0f64
    var good = false
    switch v {
    case .Null:
        out = 0.0f64
        good = true
    case .Bool as b:
        if b { out = 1.0f64 }
        good = true
    case .Number as n:
        let (x, e) = json.number_f64(n)
        out = x
        good = e == ok
    case .String as s:
        let t = str.trim(s)
        if t.len == 0usize {
            good = true
        } else {
            let (n, ne) = json.number(t)
            if ne == ok {
                let (x, xe) = json.number_f64(n)
                out = x
                good = xe == ok
            }
        }
    default:
        good = false
    }
    ret (out, good)
}

// `Number.isInteger(Number(v))`.
fn is_integer(v: json.Value) -> bool {
    let (x, good) = to_number(v)
    if !good { ret false }
    ret x == x && x - x == 0.0f64 && x == trunc(x)
}

fn trunc(x: f64) -> f64 {
    if x >= 0.0f64 { ret floor_pos(x) }
    ret 0.0f64 - floor_pos(0.0f64 - x)
}

fn floor_pos(x: f64) -> f64 {
    if x >= 9007199254740992.0f64 { ret x }
    var whole = i64(x)
    ret f64(whole)
}

fn value_number(v: json.Value) -> f64 {
    let (x, good) = to_number(v)
    ret x
}

type Errors = struct { items: list.List[Problem], failed: bool }

fn problem(e: *Errors, path: str, message: str) {
    let pushed = list.push[Problem](&e.items, Problem { path: path, message: message })
    if pushed != ok { e.failed = true }
}

fn join_dots(a: *mem.Arena, parts: []const str) -> str {
    let (joined, joined_error) = str.join(a, parts, ".")
    if joined_error != ok { ret "" }
    ret joined
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, out_error) = str.concat(a, x, y)
    if out_error != ok { ret "" }
    ret out
}

fn index_text(a: *mem.Arena, n: usize) -> str {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = n
    if rest == 0usize {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        count += 1usize
        rest = rest / 10usize
    }
    let (out, out_error) = mem.alloc[u8](a, count)
    if out_error != ok { ret "" }
    var at = 0usize
    while at < count {
        out[at] = digits[count - 1usize - at]
        at += 1usize
    }
    ret out[0usize..count]
}

// Whether a record step's `values` carries at least one mapping.
fn record_values_present(config: json.Value) -> bool {
    let (values, found) = get(config, "values")
    if !found || !truthy(values) { ret false }
    let (items, is_array) = items_of(values)
    if is_array {
        var at = 0usize
        while at < items.len {
            if truthy(items[at]) && (truthy(value_of(items[at], "key")) || truthy(value_of(items[at], "value"))) { ret true }
            at += 1usize
        }
        ret false
    }
    let (members, is_object) = members_of(values)
    if is_object { ret members.len > 0usize }
    ret false
}

fn array_has(v: json.Value) -> bool {
    let (items, yes) = items_of(v)
    ret yes
}

fn array_len(v: json.Value) -> usize {
    let (items, yes) = items_of(v)
    if !yes { ret 0usize }
    ret items.len
}

// The problems a definition has, every one of them. `clock` and `routing` are the injected halves (the zone database the
// schedule check reads, and the routing matcher's verdict on a rule).
fn validate_workflow(a: *mem.Arena, clock: *const trigger.Clock, plugins: *const Plugins, routing: RoutingCheck, definition: json.Value) -> (json.Value, err) {
    let (items, items_error) = list.init[Problem](a, 8usize)
    if items_error != ok { ret (.Null, items_error) }
    var errors = Errors { items: items, failed: false }
    let (members, is_object) = members_of(definition)
    if !is_object {
        problem(&errors, "", "Not object")
        ret (render(a, &errors), ok)
    }
    if !truthy(value_of(definition, "name")) { problem(&errors, "name", "Required") }
    let trigger_value = value_of(definition, "trigger")
    let trigger_type_value = value_of(trigger_value, "type")
    if !truthy(trigger_value) || !truthy(trigger_type_value) {
        problem(&errors, "trigger", "Trigger required")
    } else {
        let (type_name, type_is_text) = string_of(trigger_type_value)
        let known = type_is_text && trigger_type(type_name).found
        if !known {
            problem(&errors, "trigger.type", "Unknown trigger")
        } else if str.eq(type_name, "schedule") {
            let config = or_falsy(trigger_value, "config", empty_object())
            if !truthy(value_of(config, "cron")) {
                problem(&errors, "trigger.config.cron", "Schedule needs cron")
            } else {
                let (cron_text, cron_is_text) = string_of(value_of(config, "cron"))
                let (zone_text, zone_is_text) = string_of(value_of(config, "timezone"))
                var zone = ""
                if zone_is_text { zone = zone_text }
                var catch_up = ""
                let catch_value = value_of(config, "catchUp")
                let (catch_text, catch_is_text) = string_of(catch_value)
                if catch_is_text {
                    catch_up = catch_text
                    if str.eq(catch_text, "one") { catch_up = "one-catch-up" }
                }
                var spec = trigger.no_spec()
                spec.timezone = zone
                spec.on_missed = catch_up
                spec.has_cron = true
                if cron_is_text { spec.cron = cron_text }
                let schedule = trigger.normalize_schedule(a, clock, spec)
                if schedule.has_error {
                    var field = "catchUp"
                    if !trigger.is_known_timezone(clock, zone) {
                        field = "timezone"
                    } else {
                        let (parsed, parsed_ok) = trigger.parse_cron(spec.cron)
                        if !parsed_ok { field = "cron" }
                    }
                    problem(&errors, cat(a, "trigger.config.", field), schedule.reason)
                }
            }
        } else if str.eq(type_name, "metadata-change") {
            let config = or_falsy(trigger_value, "config", empty_object())
            let objects = value_of(config, "objects")
            let (object_items, objects_are_array) = items_of(objects)
            if !objects_are_array || object_items.len == 0usize {
                problem(&errors, "trigger.config.objects", "Objects required")
            } else {
                var o = 0usize
                while o < object_items.len {
                    let (name, name_is_text) = string_of(object_items[o])
                    if !name_is_text || !in_csv(metadata_objects(), name) { problem(&errors, "trigger.config.objects", "Nothing emits") }
                    o += 1usize
                }
            }
            let events = or_falsy(config, "events", empty_array())
            let (event_items, events_are_array) = items_of(events)
            if events_are_array {
                var e = 0usize
                while e < event_items.len {
                    let (name, name_is_text) = string_of(event_items[e])
                    if !name_is_text || !in_csv(metadata_events(), name) { problem(&errors, "trigger.config.events", "Unknown event") }
                    e += 1usize
                }
            }
        } else if str.eq(type_name, "platform-event") {
            let config = or_falsy(trigger_value, "config", empty_object())
            let event_type = value_of(config, "eventType")
            if !truthy(event_type) {
                problem(&errors, "trigger.config.eventType", "Required")
            } else {
                let (event_text, event_is_text) = string_of(event_type)
                if !event_is_text || !event_type_pattern(event_text) { problem(&errors, "trigger.config.eventType", "Invalid chars") }
            }
            let schema_version = value_of(config, "schemaVersion")
            if !is_integer(schema_version) || value_number(schema_version) < 1.0f64 { problem(&errors, "trigger.config.schemaVersion", "Min") }
        }
    }
    let steps_value = value_of(definition, "steps")
    if !array_has(steps_value) || array_len(steps_value) == 0usize { problem(&errors, "steps", "Step required") }
    let (visits, visits_error) = walk_steps(a, steps_value)
    if visits_error != ok { ret (.Null, visits_error) }
    let (seen_ids, seen_error) = mem.alloc[str](a, visits.len + 1usize)
    if seen_error != ok { ret (.Null, seen_error) }
    var seen = 0usize
    var v = 0usize
    while v < visits.len {
        let step = visits[v].step
        let path = visits[v].path
        let (parts, parts_error) = mem.alloc[str](a, path.len + 1usize)
        if parts_error != ok { ret (.Null, parts_error) }
        var p = 0usize
        while p < path.len {
            parts[p] = path[p]
            p += 1usize
        }
        let (id_value, have_id) = get(step, "id")
        let id_truthy = have_id && truthy(id_value)
        let (id_text_value, id_is_text) = string_of(id_value)
        if id_truthy && id_is_text {
            parts[path.len] = id_text_value
        } else {
            parts[path.len] = "?"
        }
        let where = join_dots(a, parts[0usize..path.len + 1usize])
        if !id_truthy {
            problem(&errors, where, "Step needs id")
        } else {
            if !id_is_text || !step_id_charset(id_text_value) { problem(&errors, where, "Step id charset") }
            var duplicate = false
            var s = 0usize
            while s < seen {
                if id_is_text && str.eq(seen_ids[s], id_text_value) { duplicate = true }
                s += 1usize
            }
            if duplicate { problem(&errors, where, "Duplicate step id") }
            if id_is_text {
                seen_ids[seen] = id_text_value
                seen += 1usize
            }
        }
        let (type_value, have_type) = get(step, "type")
        let (type_name, type_is_text) = string_of(type_value)
        var meta = not_found()
        if have_type && type_is_text { meta = step_type(plugins, type_name) }
        if !meta.found {
            problem(&errors, where, "Unknown step type")
            v += 1usize
            continue
        }
        let config = or_falsy(step, "config", empty_object())
        let config_path = cat(a, where, ".config")
        if str.eq(type_name, "if") {
            if !truthy(value_of(config, "condition")) { problem(&errors, cat(a, config_path, ".condition"), "If needs condition") }
        } else if str.eq(type_name, "case") {
            let cases = value_of(step, "cases")
            let (case_items, cases_are_array) = items_of(cases)
            if !cases_are_array || case_items.len == 0usize {
                problem(&errors, cat(a, where, ".cases"), "Case needs case")
            } else {
                var c = 0usize
                while c < case_items.len {
                    if !truthy(value_of(case_items[c], "when")) {
                        problem(&errors, cat(a, cat(a, cat(a, where, ".cases["), index_text(a, c)), "].when"), "Case needs when")
                    }
                    c += 1usize
                }
            }
        } else if str.eq(type_name, "foreach") {
            if !truthy(value_of(config, "items")) { problem(&errors, cat(a, config_path, ".items"), "Foreach needs items") }
        } else if str.eq(type_name, "fork") {
            let branches = value_of(step, "branches")
            if !array_has(branches) || array_len(branches) < 2usize { problem(&errors, cat(a, where, ".branches"), "Fork needs branches") }
            let join_value = value_of(config, "join")
            if truthy(join_value) {
                let (join_text, join_is_text) = string_of(join_value)
                if !join_is_text || !(str.eq(join_text, "all") || str.eq(join_text, "any") || str.eq(join_text, "race")) {
                    problem(&errors, cat(a, config_path, ".join"), "Fork join values")
                }
            }
        } else if str.eq(type_name, "delay") {
            let (ms, have_ms) = get(config, "ms")
            if !have_ms && !truthy(value_of(config, "until")) && !truthy(value_of(config, "duration")) {
                problem(&errors, config_path, "Delay needs when")
            }
        } else if str.eq(type_name, "wait-signal") {
            if !truthy(value_of(config, "signal")) { problem(&errors, cat(a, config_path, ".signal"), "Wait signal needs name") }
        } else if str.eq(type_name, "approval") {
            let (evidence, have_evidence) = get(config, "evidenceFields")
            if have_evidence {
                let (fields, fields_are_array) = items_of(evidence)
                var bad = !fields_are_array || fields.len == 0usize || fields.len > 32usize
                if !bad {
                    var f = 0usize
                    while f < fields.len {
                        let (field_text, field_is_text) = string_of(fields[f])
                        if !field_is_text || !uuid_shape(field_text) { bad = true }
                        var g = 0usize
                        while g < f {
                            if same_scalar(fields[f], fields[g]) { bad = true }
                            g += 1usize
                        }
                        f += 1usize
                    }
                }
                if bad { problem(&errors, cat(a, config_path, ".evidenceFields"), "Select fields") }
            }
            let approvers = value_of(config, "approvers")
            let (approver_items, approvers_are_array) = items_of(approvers)
            var any_approver = false
            if approvers_are_array {
                var q = 0usize
                while q < approver_items.len {
                    if truthy(approver_items[q]) { any_approver = true }
                    q += 1usize
                }
            }
            if !approvers_are_array || !any_approver { problem(&errors, cat(a, config_path, ".approvers"), "Approval needs approver") }
            if approvers_are_array {
                var q = 0usize
                while q < approver_items.len {
                    var shown = ""
                    let (approver_text, approver_is_text) = string_of(approver_items[q])
                    if approver_is_text {
                        shown = str.trim(approver_text)
                    } else if !is_null(approver_items[q]) {
                        shown = "?"
                    }
                    if !uuid_shape(shown) { problem(&errors, cat(a, config_path, ".approvers"), "Approver not user") }
                    q += 1usize
                }
            }
            if !truthy(value_of(config, "table")) { problem(&errors, cat(a, config_path, ".table"), "Approval needs table") }
            if !truthy(value_of(config, "record")) { problem(&errors, cat(a, config_path, ".record"), "Approval needs record") }
            let (rule, have_rule) = get(config, "rule")
            if have_rule {
                let (rule_text, rule_is_text) = string_of(rule)
                if !rule_is_text || !(str.eq(rule_text, "any") || str.eq(rule_text, "all")) {
                    problem(&errors, cat(a, config_path, ".rule"), "Approval rule values")
                }
            }
            let (routing_value, have_routing) = get(config, "routing")
            var routing_present = have_routing && !is_null(routing_value)
            let (routing_text, routing_is_text) = string_of(routing_value)
            if routing_present && routing_is_text && routing_text.len == 0usize { routing_present = false }
            if routing_present {
                let (rules, rules_are_array) = items_of(routing_value)
                if !rules_are_array {
                    problem(&errors, cat(a, config_path, ".routing"), "Routing not list")
                } else {
                    var r = 0usize
                    while r < rules.len {
                        let verdict = routing(rules[r])
                        if verdict.len > 0usize {
                            problem(&errors, cat(a, cat(a, cat(a, config_path, ".routing["), index_text(a, r)), "]"), "Routing rule unusable")
                        }
                        r += 1usize
                    }
                }
            }
        } else if str.eq(type_name, "webhook") {
            if !truthy(value_of(config, "url")) { problem(&errors, cat(a, config_path, ".url"), "Webhook needs url") }
        } else if str.eq(type_name, "emit-event") {
            let event_type = value_of(config, "eventType")
            if !truthy(event_type) {
                problem(&errors, cat(a, config_path, ".eventType"), "Required")
            } else {
                let (event_text, event_is_text) = string_of(event_type)
                if !event_is_text || !event_type_pattern(event_text) { problem(&errors, cat(a, config_path, ".eventType"), "Invalid chars") }
            }
            let schema_version = value_of(config, "schemaVersion")
            if !is_integer(schema_version) || value_number(schema_version) < 1.0f64 { problem(&errors, cat(a, config_path, ".schemaVersion"), "Min") }
            let payload = value_of(config, "payload")
            let (payload_members, payload_is_object) = members_of(payload)
            if !truthy(payload) || !payload_is_object { problem(&errors, cat(a, config_path, ".payload"), "Payload not object") }
            let (retain, have_retain) = get(config, "retainDays")
            if have_retain {
                let days = value_number(retain)
                if !is_integer(retain) || days < 1.0f64 || days > 3650.0f64 { problem(&errors, cat(a, config_path, ".retainDays"), "One of") }
            }
        } else if str.eq(type_name, "connector") {
            if !truthy(value_of(config, "channel")) { problem(&errors, cat(a, config_path, ".channel"), "Connector needs channel") }
            if !truthy(value_of(config, "action")) { problem(&errors, cat(a, config_path, ".action"), "Connector needs action") }
        } else if str.eq(type_name, "python") {
            if !truthy(value_of(config, "source")) { problem(&errors, cat(a, config_path, ".source"), "Python needs source") }
        } else if str.eq(type_name, "create-record") || str.eq(type_name, "update-record") || str.eq(type_name, "delete-record") {
            if !truthy(value_of(config, "table")) { problem(&errors, cat(a, config_path, ".table"), "Record step needs table") }
            if !str.eq(type_name, "delete-record") && !record_values_present(config) { problem(&errors, cat(a, config_path, ".values"), "Record step needs values") }
        } else if str.eq(type_name, "run-workflow") {
            if !truthy(value_of(config, "workflowId")) { problem(&errors, cat(a, config_path, ".workflowId"), "Run workflow needs id") }
        }
        v += 1usize
    }
    if errors.failed { ret (.Null, Exhausted) }
    ret (render(a, &errors), ok)
}

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

// `{ok, errors: [{path, message}]}`.
fn render(a: *mem.Arena, e: *const Errors) -> json.Value {
    let (o, o_error) = new_obj(a)
    if o_error != ok { ret .Null }
    var out = o
    let (list_out, list_error) = list.init[json.Value](a, e.items.len + 1usize)
    if list_error != ok { ret .Null }
    var rendered = list_out
    var at = 0usize
    while at < e.items.len {
        let (po, po_error) = new_obj(a)
        if po_error != ok { ret .Null }
        var one = po
        let p1 = put(&one, "path", text(e.items.items[at].path))
        let p2 = put(&one, "message", text(e.items.items[at].message))
        let pushed = list.push[json.Value](&rendered, obj_value(&one))
        if p1 != ok || p2 != ok || pushed != ok { ret .Null }
        at += 1usize
    }
    let ok_put = put(&out, "ok", json.Value{ Bool: e.items.len == 0usize })
    let errors_put = put(&out, "errors", json.Value{ Array: list.slice_const[json.Value](&rendered) })
    if ok_put != ok || errors_put != ok { ret .Null }
    ret obj_value(&out)
}

// --- execution keys -------------------------------------------------------------------------------------------------

// The stable identity of one step execution, which a journal entry is keyed by: the id, then `@` and the frames joined
// by `/`. A retried attempt keeps the same key, so a resumed run can count the attempts already made.
fn execution_key(a: *mem.Arena, step_id: str, frames: []const str) -> (str, err) {
    if frames.len == 0usize { ret (step_id, ok) }
    let (joined, joined_error) = str.join(a, frames, "/")
    if joined_error != ok { ret ("", joined_error) }
    let (at_id, at_error) = str.concat(a, step_id, "@")
    if at_error != ok { ret ("", at_error) }
    let (key, key_error) = str.concat(a, at_id, joined)
    ret (key, key_error)
}

// `loop:ID:INDEX`.
fn loop_frame(a: *mem.Arena, step_id: str, index: usize) -> (str, err) {
    let (head, head_error) = str.concat(a, "loop:", step_id)
    if head_error != ok { ret ("", head_error) }
    let (colon, colon_error) = str.concat(a, head, ":")
    if colon_error != ok { ret ("", colon_error) }
    let (frame, frame_error) = str.concat(a, colon, index_text(a, index))
    ret (frame, frame_error)
}

// `fork:ID:BRANCH`.
fn fork_frame(a: *mem.Arena, step_id: str, branch_name: str) -> (str, err) {
    let (head, head_error) = str.concat(a, "fork:", step_id)
    if head_error != ok { ret ("", head_error) }
    let (colon, colon_error) = str.concat(a, head, ":")
    if colon_error != ok { ret ("", colon_error) }
    let (frame, frame_error) = str.concat(a, colon, branch_name)
    ret (frame, frame_error)
}
