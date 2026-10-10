// Real-time collaboration semantics (L037), after appdor's `src/realtime/index.js`: presence with a heartbeat window,
// version-based cell resolution with last-write-wins on a stale edit, per-field record merge with provenance,
// pseudonymous presence for portal viewers, the degradation status, topic and subscription authorization (tokens,
// scopes, eviction), the connection lifecycle with reconnect backoff and gap repair, delivery telemetry, event payload
// trimming to readable rows and fields, and view-membership evaluation. The transport is the host's; the clock and the
// backoff jitter are injected. Values are JSON; an instant is a number of milliseconds or an ISO-8601 text.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str
use e.time as time

type Clock = struct { ctx: *void, now: fn(*void) -> i64, jitter: fn(*void) -> f64 }

type TopicAuth = struct { a: *mem.Arena, clock: *const Clock, token_names: list.List[json.Value], token_info: list.List[json.Value], topics: list.List[json.Value], subs: list.List[json.Value] }

type Lifecycle = struct { a: *mem.Arena, clock: *const Clock, state: str, last_event_at: i64, has_last_event: bool, disconnect_at: i64, has_disconnect: bool, sequence: i64, attempt: i64, events: list.List[json.Value] }

type Telemetry = struct { a: *mem.Arena, clock: *const Clock, metrics: list.List[json.Value], counter_names: list.List[json.Value], counter_values: list.List[json.Value], correlation: i64 }

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

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

fn push_value(l: *list.List[json.Value], v: json.Value) {
    let e = list.push[json.Value](l, v)
}

fn empty_list(a: *mem.Arena) -> list.List[json.Value] {
    let (l, e) = list.init[json.Value](a, 8usize)
    if e != ok { ret list.List[json.Value] { items: zero, len: 0usize, arena: a } }
    ret l
}

// `delete o[key]`.
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

fn as_text(v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    case .Number as n:
        ret n.lexeme
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    default:
        ret ""
    }
}

fn nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

fn neg_infinity() -> f64 { ret mem.bitcast[f64](18442240474082181120u64) }

// `new Date(v).getTime()`: a number as is, an ISO-8601 text parsed, anything else NaN.
fn to_ms(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok { ret x }
        ret nan()
    case .String as s:
        let (t, e) = time.parse_iso8601(s)
        if e != ok { ret nan() }
        var ms = t.nanos / 1000000i64
        if t.nanos < 0i64 && t.nanos % 1000000i64 != 0i64 { ms -= 1i64 }
        ret f64(ms)
    default:
        ret nan()
    }
}

fn is_present(v: json.Value, key: str) -> bool {
    let (x, found) = get(v, key)
    ret found && !ir.is_null(x)
}

// `v ?? fallback`.
fn or_null(v: json.Value, key: str) -> json.Value {
    let (x, found) = get(v, key)
    if !found { ret .Null }
    ret x
}

fn strict_equal(x: json.Value, y: json.Value) -> bool {
    switch x {
    case .Null:
        switch y {
        case .Null:
            ret true
        default:
            ret false
        }
    case .Bool as bx:
        switch y {
        case .Bool as by:
            ret bx == by
        default:
            ret false
        }
    case .Number as nx:
        switch y {
        case .Number as ny:
            let (fx, ex) = json.number_f64(nx)
            let (fy, ey) = json.number_f64(ny)
            ret ex == ok && ey == ok && fx == fy
        default:
            ret false
        }
    case .String as sx:
        switch y {
        case .String as sy:
            ret str.eq(sx, sy)
        default:
            ret false
        }
    default:
        ret false
    }
}

fn spread(a: *mem.Arena, x: json.Value) -> ir.Obj {
    var o = obj(a)
    let assigned = ir.assign(&o, x)
    ret o
}

// --- presence ------------------------------------------------------------------------------------------------------

// Record or refresh a user's presence `{cursor, at, name, anonymous}`.
fn set_presence(a: *mem.Arena, presence: json.Value, user_id: str, info: json.Value) -> json.Value {
    var next = spread(a, presence)
    var entry = obj(a)
    put(&entry, "cursor", or_null(info, "cursor"))
    put(&entry, "at", or_null(info, "at"))
    let (name, have_name) = get(info, "name")
    if have_name { put(&entry, "name", name) }
    var anonymous = false
    let (x, found) = get(info, "anonymous")
    if found {
        switch x {
        case .Bool as b:
            anonymous = b
        default:
            anonymous = false
        }
    }
    put(&entry, "anonymous", flag(anonymous))
    put(&next, user_id, ir.obj_value(&entry))
    ret ir.obj_value(&next)
}

fn clear_presence(a: *mem.Arena, presence: json.Value, user_id: str) -> json.Value {
    var next = spread(a, presence)
    unset(&next, user_id)
    ret ir.obj_value(&next)
}

// Users whose heartbeat is within `ttl_ms` of `now`.
fn active_users(a: *mem.Arena, presence: json.Value, now: json.Value, ttl_ms: f64) -> json.Value {
    var out = empty_list(a)
    let now_t = to_ms(now)
    let (members, is_object) = ir.members_of(presence)
    var at = 0usize
    while is_object && at < members.len {
        let p = members[at].value
        if is_present(p, "at") {
            let age = now_t - to_ms(ir.value_of(p, "at"))
            if age <= ttl_ms {
                var u = obj(a)
                put(&u, "userId", text(members[at].key))
                put(&u, "cursor", or_null(p, "cursor"))
                let (name, have_name) = get(p, "name")
                if have_name { put(&u, "name", name) }
                var anonymous = false
                switch or_null(p, "anonymous") {
                case .Bool as b:
                    anonymous = b
                default:
                    anonymous = false
                }
                put(&u, "anonymous", flag(anonymous))
                push_value(&out, ir.obj_value(&u))
            }
        }
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// --- cells and records --------------------------------------------------------------------------------------------

// Resolve an edit `{value, baseVersion, userId, at}` against a cell `{value, version, updatedBy, updatedAt}`:
// `{cell, status[, conflictWith]}` with status `applied`, `conflict-overwritten` or `conflict-kept`.
fn resolve_edit(a: *mem.Arena, cell: json.Value, has_cell: bool, edit: json.Value) -> json.Value {
    var current = cell
    if !has_cell || !ir.truthy(cell) {
        var o = obj(a)
        put(&o, "value", .Null)
        put(&o, "version", number(a, 0i64))
        put(&o, "updatedBy", .Null)
        put(&o, "updatedAt", .Null)
        current = ir.obj_value(&o)
    }
    var version = 0i64
    switch ir.value_of(current, "version") {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e == ok { version = x }
    default:
        version = 0i64
    }
    let applied_same = strict_equal(or_null(edit, "baseVersion"), ir.value_of(current, "version"))
    var status = "applied"
    var overwrite = applied_same
    var conflict_with: json.Value = .Null
    var has_conflict = false
    if !applied_same {
        let edit_t = to_ms(ir.value_of(edit, "at"))
        var cur_t = neg_infinity()
        let updated_at = ir.value_of(current, "updatedAt")
        if ir.truthy(updated_at) { cur_t = to_ms(updated_at) }
        if edit_t > cur_t {
            status = "conflict-overwritten"
            overwrite = true
            let by = ir.value_of(current, "updatedBy")
            if ir.truthy(by) {
                conflict_with = by
                has_conflict = true
            }
        } else {
            var kept = obj(a)
            put(&kept, "cell", current)
            put(&kept, "status", text("conflict-kept"))
            put(&kept, "conflictWith", ir.value_of(current, "updatedBy"))
            ret ir.obj_value(&kept)
        }
    }
    var cell_out = obj(a)
    let (value, have_value) = get(edit, "value")
    if have_value { put(&cell_out, "value", value) }
    put(&cell_out, "version", number(a, version + 1i64))
    let (user, have_user) = get(edit, "userId")
    if have_user { put(&cell_out, "updatedBy", user) }
    let (at, have_at) = get(edit, "at")
    if have_at { put(&cell_out, "updatedAt", at) }
    var out = obj(a)
    put(&out, "cell", ir.obj_value(&cell_out))
    put(&out, "status", text(status))
    if has_conflict { put(&out, "conflictWith", conflict_with) }
    ret ir.obj_value(&out)
}

// Merge concurrent per-field edits onto a base record: each field takes the latest timestamp (the first on a tie).
// `{record, provenance}`.
fn merge_record(a: *mem.Arena, base: json.Value, edits: []const json.Value) -> json.Value {
    var record = spread(a, base)
    var provenance = obj(a)
    var names = empty_list(a)
    let (times, times_error) = mem.alloc[f64](a, edits.len + 1usize)
    if times_error != ok { ret .Null }
    var at = 0usize
    while at < edits.len {
        let field = as_text(ir.value_of(edits[at], "field"))
        let t = to_ms(ir.value_of(edits[at], "at"))
        let index = find_index(&names, field)
        var take = index == names.len
        if !take { take = t > times[index] }
        if take {
            var slot = index
            if index == names.len {
                push_value(&names, text(field))
                slot = names.len - 1usize
            }
            times[slot] = t
            put(&record, field, ir.value_of(edits[at], "value"))
            var p = obj(a)
            let (user, have_user) = get(edits[at], "userId")
            if have_user { put(&p, "userId", user) }
            let (stamp, have_stamp) = get(edits[at], "at")
            if have_stamp { put(&p, "at", stamp) }
            put(&provenance, field, ir.obj_value(&p))
        }
        at += 1usize
    }
    var out = obj(a)
    put(&out, "record", ir.obj_value(&record))
    put(&out, "provenance", ir.obj_value(&provenance))
    ret ir.obj_value(&out)
}

// --- presence for a viewer and degradation -----------------------------------------------------------------------------

// What a viewer may see of a presence list: `policy = {isPortalUser, showInternalPresenceToPortal}`.
fn filter_presence_for_viewer(a: *mem.Arena, users: []const json.Value, policy: json.Value) -> json.Value {
    if !ir.truthy(ir.value_of(policy, "isPortalUser")) { ret json.Value{ Array: users } }
    var out = empty_list(a)
    var at = 0usize
    while at < users.len {
        let anonymous = ir.truthy(ir.value_of(users[at], "anonymous"))
        if !ir.truthy(ir.value_of(policy, "showInternalPresenceToPortal")) {
            if anonymous { push_value(&out, users[at]) }
        } else {
            var o = spread(a, users[at])
            put(&o, "name", .Null)
            if anonymous { put(&o, "nameKey", text("realtime.presence.portalViewer")) }
            push_value(&out, ir.obj_value(&o))
        }
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// `{available: false, indicatorKey}` when disabled or cut_off, else `{available: true}`.
fn realtime_status(a: *mem.Arena, state: json.Value) -> json.Value {
    var o = obj(a)
    let (enabled, have_enabled) = get(state, "enabled")
    let (reachable, have_reachable) = get(state, "reachable")
    var disabled = false
    if have_enabled {
        switch enabled {
        case .Bool as b:
            disabled = !b
        default:
            disabled = false
        }
    }
    var cut_off = false
    if have_reachable {
        switch reachable {
        case .Bool as b:
            cut_off = !b
        default:
            cut_off = false
        }
    }
    if disabled {
        put(&o, "available", flag(false))
        put(&o, "indicatorKey", text("realtime.degraded.disabled"))
    } else if cut_off {
        put(&o, "available", flag(false))
        put(&o, "indicatorKey", text("realtime.degraded.unreachable"))
    } else {
        put(&o, "available", flag(true))
    }
    ret ir.obj_value(&o)
}

// --- topic authorization ---------------------------------------------------------------------------------------------

fn new_topic_auth(a: *mem.Arena, clock: *const Clock) -> TopicAuth {
    ret TopicAuth { a: a, clock: clock, token_names: empty_list(a), token_info: empty_list(a), topics: empty_list(a), subs: empty_list(a) }
}

fn find_index(names: *const list.List[json.Value], key: str) -> usize {
    var at = 0usize
    while at < names.len {
        if str.eq(as_text(names.items[at]), key) { ret at }
        at += 1usize
    }
    ret names.len
}

fn remove_at(names: *list.List[json.Value], values: *list.List[json.Value], index: usize) {
    var k = index
    while k + 1usize < names.len {
        names.items[k] = names.items[k + 1usize]
        values.items[k] = values.items[k + 1usize]
        k += 1usize
    }
    names.len -= 1usize
    values.len -= 1usize
}

// Register a token `{userId, scopes, expiresAt}`; a scalar scope is wrapped, a missing one is empty.
fn register_token(t: *TopicAuth, token: str, info: json.Value) {
    var scopes = json.Value{ Array: zero }
    let (given, have_scopes) = get(info, "scopes")
    if have_scopes {
        let (xs, is_array) = ir.items_of(given)
        if is_array {
            scopes = given
        } else {
            let (one, e) = mem.alloc[json.Value](t.a, 1usize)
            if e == ok {
                one[0] = given
                scopes = json.Value{ Array: one[0usize..1usize] }
            }
        }
    }
    var o = obj(t.a)
    let (user, have_user) = get(info, "userId")
    if have_user { put(&o, "userId", user) }
    put(&o, "scopes", scopes)
    let (exp, have_exp) = get(info, "expiresAt")
    if have_exp { put(&o, "expiresAt", exp) }
    let index = find_index(&t.token_names, token)
    if index < t.token_names.len {
        t.token_info.items[index] = ir.obj_value(&o)
    } else {
        push_value(&t.token_names, text(token))
        push_value(&t.token_info, ir.obj_value(&o))
    }
}

// Revoke a token and evict what used it: the evicted topics.
fn revoke_token(t: *TopicAuth, token: str) -> json.Value {
    let index = find_index(&t.token_names, token)
    if index < t.token_names.len { remove_at(&t.token_names, &t.token_info, index) }
    var evicted = empty_list(t.a)
    var at = 0usize
    while at < t.topics.len {
        if str.eq(as_text(ir.value_of(t.subs.items[at], "token")), token) {
            push_value(&evicted, t.topics.items[at])
            remove_at(&t.topics, &t.subs, at)
        } else {
            at += 1usize
        }
    }
    ret json.Value{ Array: list.slice_const[json.Value](&evicted) }
}

// The table of a `table:{id}` topic: the shortest non-empty run up to a colon or the end.
fn table_of(topic: str) -> (str, bool) {
    if !str.starts_with(topic, "table:") { ret ("", false) }
    let rest = topic[6usize..]
    var end = 1usize
    while end <= rest.len {
        if end == rest.len || rest[end] == 58u8 { ret (rest[0usize..end], true) }
        end += 1usize
    }
    ret ("", false)
}

fn scope_has(scopes: json.Value, name: str) -> bool {
    let xs = items(scopes)
    var at = 0usize
    while at < xs.len {
        let (s, is_text) = ir.string_of(xs[at])
        if is_text && str.eq(s, name) { ret true }
        at += 1usize
    }
    ret false
}

// Subscribe a user to a topic with a token: `{ok: true}` or `{ok: false, reason[, table]}`.
fn subscribe(t: *TopicAuth, topic: str, token: str, user_id: json.Value) -> json.Value {
    var out = obj(t.a)
    let index = find_index(&t.token_names, token)
    if index == t.token_names.len {
        put(&out, "ok", flag(false))
        put(&out, "reason", text("invalid-token"))
        ret ir.obj_value(&out)
    }
    let tok = t.token_info.items[index]
    let expires = ir.value_of(tok, "expiresAt")
    if ir.truthy(expires) {
        let e = to_ms(expires)
        if e <= f64(t.clock.now(t.clock.ctx)) {
            put(&out, "ok", flag(false))
            put(&out, "reason", text("token-expired"))
            ret ir.obj_value(&out)
        }
    }
    let (table, matched) = table_of(topic)
    let scopes = ir.value_of(tok, "scopes")
    if matched && items(scopes).len > 0usize && !scope_has(scopes, table) && !scope_has(scopes, "*") {
        put(&out, "ok", flag(false))
        put(&out, "reason", text("table-not-in-scope"))
        put(&out, "table", text(table))
        ret ir.obj_value(&out)
    }
    var sub = obj(t.a)
    put(&sub, "userId", user_id)
    put(&sub, "token", text(token))
    put(&sub, "scopes", scopes)
    put(&sub, "subscribedAt", number(t.a, t.clock.now(t.clock.ctx)))
    put(&sub, "lastEventAt", .Null)
    let existing = find_index(&t.topics, topic)
    if existing < t.topics.len {
        t.subs.items[existing] = ir.obj_value(&sub)
    } else {
        push_value(&t.topics, text(topic))
        push_value(&t.subs, ir.obj_value(&sub))
    }
    put(&out, "ok", flag(true))
    ret ir.obj_value(&out)
}

fn unsubscribe(t: *TopicAuth, topic: str) -> bool {
    let index = find_index(&t.topics, topic)
    if index == t.topics.len { ret false }
    remove_at(&t.topics, &t.subs, index)
    ret true
}

// Evict a user from every topic: the evicted topics.
fn evict_user(t: *TopicAuth, user_id: json.Value) -> json.Value {
    var evicted = empty_list(t.a)
    var at = 0usize
    while at < t.topics.len {
        if strict_equal(ir.value_of(t.subs.items[at], "userId"), user_id) {
            push_value(&evicted, t.topics.items[at])
            remove_at(&t.topics, &t.subs, at)
        } else {
            at += 1usize
        }
    }
    ret json.Value{ Array: list.slice_const[json.Value](&evicted) }
}

fn may_receive(t: *const TopicAuth, user_id: json.Value, topic: str) -> bool {
    let index = find_index(&t.topics, topic)
    if index == t.topics.len { ret false }
    ret strict_equal(ir.value_of(t.subs.items[index], "userId"), user_id)
}

// `[{topic, ...subscription}]`, optionally for one user.
fn active_subscriptions(t: *const TopicAuth, user_id: json.Value, has_user: bool) -> json.Value {
    var out = empty_list(t.a)
    var at = 0usize
    while at < t.topics.len {
        if !has_user || strict_equal(ir.value_of(t.subs.items[at], "userId"), user_id) {
            var o = obj(t.a)
            put(&o, "topic", t.topics.items[at])
            let assigned = ir.assign(&o, t.subs.items[at])
            push_value(&out, ir.obj_value(&o))
        }
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// --- the connection lifecycle ----------------------------------------------------------------------------------------

fn new_lifecycle(a: *mem.Arena, clock: *const Clock) -> Lifecycle {
    ret Lifecycle { a: a, clock: clock, state: "connected", last_event_at: 0i64, has_last_event: false, disconnect_at: 0i64, has_disconnect: false, sequence: 0i64, attempt: 0i64, events: empty_list(a) }
}

fn emit(l: *Lifecycle, next: str) {
    if str.eq(next, l.state) { ret }
    l.state = next
    var o = obj(l.a)
    put(&o, "state", text(next))
    put(&o, "at", number(l.a, l.clock.now(l.clock.ctx)))
    put(&o, "attempt", number(l.a, l.attempt))
    push_value(&l.events, ir.obj_value(&o))
}

fn heartbeat(l: *Lifecycle) {
    l.last_event_at = l.clock.now(l.clock.ctx)
    l.has_last_event = true
}

// `{staleStateBanner: true, since}`.
fn disconnected(l: *Lifecycle) -> json.Value {
    l.disconnect_at = l.clock.now(l.clock.ctx)
    l.has_disconnect = true
    emit(l, "disconnected")
    var o = obj(l.a)
    put(&o, "staleStateBanner", flag(true))
    put(&o, "since", number(l.a, l.disconnect_at))
    ret ir.obj_value(&o)
}

// `{delay, attempt, needsResync}`: the doubling delay, capped at 30 s, plus up to half a second of jitter.
fn plan_reconnect(l: *Lifecycle) -> json.Value {
    l.attempt += 1i64
    emit(l, "reconnecting")
    var exp = 1000.0f64
    var n = 0i64
    while n < l.attempt && exp < 30000.0f64 {
        exp = exp * 2.0f64
        n += 1i64
    }
    if exp > 30000.0f64 { exp = 30000.0f64 }
    let total = exp + l.clock.jitter(l.clock.ctx)
    var delay = i64(total)
    var o = obj(l.a)
    put(&o, "delay", number(l.a, delay))
    put(&o, "attempt", number(l.a, l.attempt))
    put(&o, "needsResync", flag(true))
    ret ir.obj_value(&o)
}

// `{resynced, gap, needsRefetch}`: how many events were missed.
fn reconnected(l: *Lifecycle, last_known_seq: i64) -> json.Value {
    l.attempt = 0i64
    l.has_disconnect = false
    l.disconnect_at = 0i64
    emit(l, "connected")
    let gap = l.sequence - last_known_seq
    var o = obj(l.a)
    put(&o, "resynced", flag(true))
    put(&o, "gap", number(l.a, gap))
    put(&o, "needsRefetch", flag(gap > 0i64))
    ret ir.obj_value(&o)
}

fn advance_seq(l: *Lifecycle) -> i64 {
    l.sequence += 1i64
    ret l.sequence
}

fn is_stale(l: *const Lifecycle, ttl_ms: i64) -> bool {
    if !l.has_last_event || l.last_event_at == 0i64 { ret false }
    ret l.clock.now(l.clock.ctx) - l.last_event_at > ttl_ms
}

fn should_reconnect(l: *const Lifecycle, min_interval_ms: i64) -> bool {
    if !l.has_disconnect || l.disconnect_at == 0i64 { ret true }
    ret l.clock.now(l.clock.ctx) - l.disconnect_at >= min_interval_ms
}

// --- telemetry ---------------------------------------------------------------------------------------------------------

fn new_telemetry(a: *mem.Arena, clock: *const Clock) -> Telemetry {
    ret Telemetry { a: a, clock: clock, metrics: empty_list(a), counter_names: empty_list(a), counter_values: empty_list(a), correlation: 0i64 }
}

fn base36(a: *mem.Arena, n: i64) -> str {
    if n == 0i64 { ret "0" }
    var digits: [16]u8 = zero
    var count = 0usize
    var v = n
    while v > 0i64 && count < 16usize {
        let d = v % 36i64
        if d < 10i64 { digits[count] = 48u8 + u8(d) } else { digits[count] = 87u8 + u8(d) }
        count += 1usize
        v = v / 36i64
    }
    let (out, e) = mem.alloc[u8](a, count + 1usize)
    if e != ok { ret "" }
    var k = 0usize
    while k < count {
        out[k] = digits[count - 1usize - k]
        k += 1usize
    }
    ret out[0usize..count]
}

fn count_or(v: json.Value, key: str, fallback: i64) -> i64 {
    let (x, found) = get(v, key)
    if !found || !ir.truthy(x) { ret fallback }
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        if e == ok { ret value }
        ret fallback
    default:
        ret fallback
    }
}

// `{correlationId, publishAt}`; a missing `publish_at` is read from the clock twice, as appdor's template does.
fn start_trace(t: *Telemetry, publish_at: i64) -> json.Value {
    t.correlation += 1i64
    var in_id = publish_at
    if in_id == 0i64 { in_id = t.clock.now(t.clock.ctx) }
    var at = publish_at
    if at == 0i64 { at = t.clock.now(t.clock.ctx) }
    var o = obj(t.a)
    put(&o, "correlationId", text(cat(t.a, cat(t.a, cat(t.a, "rt-", base36(t.a, t.correlation)), "-"), ir.index_text(t.a, usize(in_id)))))
    put(&o, "publishAt", number(t.a, at))
    ret ir.obj_value(&o)
}

fn counter_value(t: *const Telemetry, index: usize) -> i64 {
    switch t.counter_values.items[index] {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e == ok { ret x }
        ret 0i64
    default:
        ret 0i64
    }
}

fn set_counter(t: *Telemetry, name: str, value: i64) {
    let index = find_index(&t.counter_names, name)
    if index == t.counter_names.len {
        push_value(&t.counter_names, text(name))
        push_value(&t.counter_values, number(t.a, value))
    } else {
        t.counter_values.items[index] = number(t.a, value)
    }
}

fn record_delivery(t: *Telemetry, correlation_id: str, info: json.Value) -> json.Value {
    var m = obj(t.a)
    put(&m, "kind", text("delivery"))
    put(&m, "correlationId", text(correlation_id))
    var delivered = count_or(info, "deliveredAt", 0i64)
    if delivered == 0i64 { delivered = t.clock.now(t.clock.ctx) }
    put(&m, "deliveredAt", number(t.a, delivered))
    put(&m, "subscriberCount", number(t.a, count_or(info, "subscriberCount", 0i64)))
    put(&m, "coalesced", flag(ir.truthy(ir.value_of(info, "coalesced"))))
    put(&m, "degraded", flag(ir.truthy(ir.value_of(info, "degraded"))))
    let value = ir.obj_value(&m)
    push_value(&t.metrics, value)
    ret value
}

fn record_degradation(t: *Telemetry, reason: json.Value) {
    let index = find_index(&t.counter_names, "degradations")
    var n = 0i64
    if index < t.counter_names.len { n = counter_value(t, index) }
    set_counter(t, "degradations", n + 1i64)
    var m = obj(t.a)
    put(&m, "kind", text("degradation"))
    put(&m, "reason", reason)
    put(&m, "at", number(t.a, t.clock.now(t.clock.ctx)))
    push_value(&t.metrics, ir.obj_value(&m))
}

fn record_coalesce(t: *Telemetry, input_count: i64, output_count: i64) {
    let index = find_index(&t.counter_names, "coalesces")
    var n = 0i64
    if index < t.counter_names.len { n = counter_value(t, index) }
    set_counter(t, "coalesces", n + 1i64)
    var m = obj(t.a)
    put(&m, "kind", text("coalesce"))
    put(&m, "inputCount", number(t.a, input_count))
    put(&m, "outputCount", number(t.a, output_count))
    put(&m, "at", number(t.a, t.clock.now(t.clock.ctx)))
    push_value(&t.metrics, ir.obj_value(&m))
}

fn record_connection_count(t: *Telemetry, count: i64) {
    set_counter(t, "connectionCount", count)
    var m = obj(t.a)
    put(&m, "kind", text("connection-count"))
    put(&m, "count", number(t.a, count))
    put(&m, "at", number(t.a, t.clock.now(t.clock.ctx)))
    push_value(&t.metrics, ir.obj_value(&m))
}

// `{metrics, counters}`; with `since`, only the metrics stamped `at` from then on.
fn export_telemetry(t: *const Telemetry, since: i64) -> json.Value {
    var kept = empty_list(t.a)
    var at = 0usize
    while at < t.metrics.len {
        var keep = since == 0i64
        if !keep {
            let (stamp, have_stamp) = get(t.metrics.items[at], "at")
            if have_stamp {
                switch stamp {
                case .Number as n:
                    let (x, e) = json.number_i64(n)
                    keep = e == ok && x >= since
                default:
                    keep = false
                }
            }
        }
        if keep { push_value(&kept, t.metrics.items[at]) }
        at += 1usize
    }
    var counters = obj(t.a)
    var c = 0usize
    while c < t.counter_names.len {
        put(&counters, as_text(t.counter_names.items[c]), t.counter_values.items[c])
        c += 1usize
    }
    var out = obj(t.a)
    put(&out, "metrics", json.Value{ Array: list.slice_const[json.Value](&kept) })
    put(&out, "counters", ir.obj_value(&counters))
    ret ir.obj_value(&out)
}

// --- payload trimming and view membership -----------------------------------------------------------------------------

fn in_strings(values: json.Value, name: str) -> bool {
    var xs = items(values)
    var at = 0usize
    while at < xs.len {
        if str.eq(as_text(xs[at]), name) { ret true }
        at += 1usize
    }
    ret false
}

fn trim_record(a: *mem.Arena, r: json.Value, readable: json.Value) -> json.Value {
    var o = obj(a)
    let (members, is_object) = ir.members_of(r)
    var at = 0usize
    while is_object && at < members.len {
        if str.eq(members[at].key, "id") || in_strings(readable, members[at].key) { put(&o, members[at].key, members[at].value) }
        at += 1usize
    }
    ret ir.obj_value(&o)
}

// Trim an event payload to readable rows and fields (`permissions = {readableFields, readableRowIds}`, each null when
// unrestricted); null when the whole row is excluded.
fn trim_event_payload(a: *mem.Arena, payload: json.Value, permissions: json.Value) -> (json.Value, bool) {
    if !ir.truthy(payload) { ret (.Null, false) }
    var current = payload
    let (rows, have_rows) = get(permissions, "readableRowIds")
    if have_rows && !ir.is_null(rows) {
        if ir.truthy(ir.value_of(current, "recordId")) {
            if !in_strings(rows, as_text(ir.value_of(current, "recordId"))) { ret (.Null, false) }
        }
        let records = ir.value_of(current, "records")
        if ir.truthy(records) {
            var kept = empty_list(a)
            let xs = items(records)
            var at = 0usize
            while at < xs.len {
                if in_strings(rows, as_text(ir.value_of(xs[at], "id"))) { push_value(&kept, xs[at]) }
                at += 1usize
            }
            var o = spread(a, current)
            put(&o, "records", json.Value{ Array: list.slice_const[json.Value](&kept) })
            current = ir.obj_value(&o)
        }
    }
    let (fields, have_fields) = get(permissions, "readableFields")
    if have_fields && !ir.is_null(fields) {
        let record = ir.value_of(current, "record")
        if ir.truthy(record) {
            var o = spread(a, current)
            put(&o, "record", trim_record(a, record, fields))
            current = ir.obj_value(&o)
        }
        let records = ir.value_of(current, "records")
        if ir.truthy(records) {
            var trimmed = empty_list(a)
            let xs = items(records)
            var at = 0usize
            while at < xs.len {
                push_value(&trimmed, trim_record(a, xs[at], fields))
                at += 1usize
            }
            var o = spread(a, current)
            put(&o, "records", json.Value{ Array: list.slice_const[json.Value](&trimmed) })
            current = ir.obj_value(&o)
        }
        let changes = ir.value_of(current, "changes")
        if ir.truthy(changes) {
            var o = spread(a, current)
            put(&o, "changes", trim_record(a, changes, fields))
            current = ir.obj_value(&o)
        }
    }
    ret (current, true)
}

fn passes_filter(r: json.Value, filter: json.Value) -> bool {
    if !ir.truthy(filter) { ret true }
    let (members, is_object) = ir.members_of(filter)
    if !is_object { ret true }
    var at = 0usize
    while at < members.len {
        if !strict_equal(ir.value_of(r, members[at].key), members[at].value) { ret false }
        at += 1usize
    }
    ret true
}

// `{membership, inView}`: enters, leaves, stays or excluded, against the record's previous state when there is one.
fn evaluate_view_membership(a: *mem.Arena, record: json.Value, filter: json.Value, previous: json.Value, has_previous: bool) -> json.Value {
    var o = obj(a)
    let now_in = passes_filter(record, filter)
    if !has_previous {
        if now_in { put(&o, "membership", text("enters")) } else { put(&o, "membership", text("excluded")) }
        put(&o, "inView", flag(now_in))
        ret ir.obj_value(&o)
    }
    let before = passes_filter(previous, filter)
    var membership = "excluded"
    if now_in && !before { membership = "enters" }
    if !now_in && before { membership = "leaves" }
    if now_in && before { membership = "stays" }
    put(&o, "membership", text(membership))
    put(&o, "inView", flag(now_in))
    ret ir.obj_value(&o)
}

// The views a change touches: `{viewId, viewName, membership, inView}` for each view that is not `excluded`.
fn affected_views(a: *mem.Arena, record: json.Value, previous: json.Value, has_previous: bool, views: []const json.Value) -> json.Value {
    var out = empty_list(a)
    var at = 0usize
    while at < views.len {
        let result = evaluate_view_membership(a, record, ir.value_of(views[at], "filter"), previous, has_previous)
        if !str.eq(as_text(ir.value_of(result, "membership")), "excluded") {
            var o = obj(a)
            let (id, have_id) = get(views[at], "id")
            if have_id { put(&o, "viewId", id) }
            let (name, have_name) = get(views[at], "name")
            if have_name { put(&o, "viewName", name) }
            let assigned = ir.assign(&o, result)
            push_value(&out, ir.obj_value(&o))
        }
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// The state changes since the last call, `{state, at, attempt}` each, and clear them (appdor's `onStateChange`).
fn take_events(l: *Lifecycle) -> []const json.Value {
    let taken = list.slice_const[json.Value](&l.events)
    l.events = empty_list(l.a)
    ret taken
}
