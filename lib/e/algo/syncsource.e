// What a synced table reads from its source before a scheduled pull (L037), after appdor's `src/sync/change-stream.js` and
// `src/sync/entity-browse.js`:
//
//   * change stream: the shape check on a stream token (`cs_` and sixteen more word characters; a shape check and not a
//     lookup), the public URL a source posts to, reading one change out of a delivery (one record, one verb, `upsert`
//     unless the body says `delete`), planning the single row change it implies through the accepted column mapping
//     (insert, update, delete, or noop) and the ledger counts of that plan;
//   * entity browse: the collections a channel's own action list names (GET with a concrete path), asking a source what
//     it holds (`can_browse`), reading an index response -- an array of names or objects, or an object keyed by name --
//     into entities, and merging what the source says with what the catalog knows, the source winning a collision.
//
// Values are JSON. Entities are sorted by name as `localeCompare` does for ASCII names: punctuation and spaces before
// digits before letters, letters ignoring case, a lower-case letter before its capital on a tie; other scripts are
// ordered by byte. `browseRequest` (the SSRF-checked request builder of the connectors) is not here.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncjob as syncjob
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

const MAX_ENTITIES: usize = 500usize

// --- the change stream -----------------------------------------------------------------------------------------------

// The prefix a change-stream token carries.
fn stream_prefix() -> str { ret "cs_" }

fn is_word_byte(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8
}

// Does this look like a change-stream token: the `cs_` prefix, only word characters, and more than sixteen after the
// prefix? A shape check, so a malformed token is answered without a lookup.
fn looks_like_stream_token(token: str) -> bool {
    if !str.starts_with(token, "cs_") { ret false }
    var at = 0usize
    while at < token.len {
        if !is_word_byte(token[at]) { ret false }
        at += 1usize
    }
    ret token.len > 3usize + 16usize
}

// The public URL a source is told to post to: the base without trailing slashes, then `/api/sync/stream/<token>`.
fn stream_url(a: *mem.Arena, base_url: str, token: str) -> str {
    var end = base_url.len
    while end > 0usize && base_url[end - 1usize] == 47u8 { end -= 1usize }
    ret sync.cat(a, sync.cat(a, base_url[0usize..end], "/api/sync/stream/"), token)
}

fn lower_ascii(a: *mem.Arena, s: str) -> str {
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

// `String(value)`: an array is its elements joined by commas (null and absent ones empty), an object is
// `[object Object]`.
fn js_text(a: *mem.Arena, v: json.Value) -> str {
    switch v {
    case .Null:
        ret ""
    case .Array as xs:
        var out = ""
        var at = 0usize
        while at < xs.len {
            if at > 0usize { out = sync.cat(a, out, ",") }
            out = sync.cat(a, out, js_text(a, xs[at]))
            at += 1usize
        }
        ret out
    case .Object as ms:
        ret "[object Object]"
    default:
        ret sync.as_text(v)
    }
}

// `{ok: true, op, record}` or `{ok: false, reason}` for one delivery body: an object that is the record, or carries it as
// `record`, with an optional `op` of `upsert` (the default) or `delete`.
fn change_from_delivery(a: *mem.Arena, payload: json.Value) -> json.Value {
    var out = sync.obj(a)
    let (members, is_object) = ir.members_of(payload)
    if !is_object {
        sync.put(&out, "ok", sync.flag(false))
        sync.put(&out, "reason", sync.text("not-a-change"))
        ret ir.obj_value(&out)
    }
    var verb = "upsert"
    let (given, have_given) = sync.get(payload, "op")
    if have_given && ir.truthy(given) {
        switch given {
        case .String as s:
            verb = lower_ascii(a, s)
        case .Number as n:
            verb = n.lexeme
        case .Bool as b:
            if b { verb = "true" } else { verb = "false" }
        default:
            verb = "[object object]"
        }
    }
    if !str.eq(verb, "upsert") && !str.eq(verb, "delete") {
        sync.put(&out, "ok", sync.flag(false))
        sync.put(&out, "reason", sync.text("unknown-op"))
        ret ir.obj_value(&out)
    }
    var record = payload
    let (inner, have_inner) = sync.get(payload, "record")
    if have_inner { record = inner }
    let (record_members, record_is_object) = ir.members_of(record)
    if !record_is_object {
        sync.put(&out, "ok", sync.flag(false))
        sync.put(&out, "reason", sync.text("not-a-change"))
        ret ir.obj_value(&out)
    }
    sync.put(&out, "ok", sync.flag(true))
    sync.put(&out, "op", sync.text(verb))
    sync.put(&out, "record", record)
    ret ir.obj_value(&out)
}

fn refusal(a: *mem.Arena, reason: str) -> json.Value {
    var out = sync.obj(a)
    sync.put(&out, "ok", sync.flag(false))
    sync.put(&out, "reason", sync.text(reason))
    ret ir.obj_value(&out)
}

// The single row change a delivery implies, projected through the accepted mapping like a scheduled pull: `{ok, action,
// key, rowId, data?}` with the action insert, update, delete or noop, or `{ok: false, reason}`. `existing` is the local
// row `{id, data}`.
fn plan_stream_change(a: *mem.Arena, binding: json.Value, op: str, record: json.Value, existing: json.Value, has_existing: bool) -> json.Value {
    var mapping: []const json.Value = zero
    let (cm, have_cm) = sync.get(binding, "column_mapping")
    let (cols, is_array) = ir.items_of(cm)
    if have_cm && is_array { mapping = cols }
    let (sync_key, have_key) = sync.get(binding, "sync_key")
    if mapping.len == 0usize || !have_key || !ir.truthy(sync_key) { ret refusal(a, "no-mapping") }
    let (key, have_value) = sync.get(record, sync.as_text(sync_key))
    var missing = !have_value || ir.is_null(key)
    let (key_string, key_is_text) = ir.string_of(key)
    if key_is_text && key_string.len == 0usize { missing = true }
    if missing { ret refusal(a, "missing-sync-key") }
    let key_text = js_text(a, key)
    var out = sync.obj(a)
    let exists = has_existing && ir.truthy(existing)
    if str.eq(op, "delete") {
        sync.put(&out, "ok", sync.flag(true))
        if !exists {
            sync.put(&out, "action", sync.text("noop"))
            sync.put(&out, "key", sync.text(key_text))
            sync.put(&out, "rowId", .Null)
            ret ir.obj_value(&out)
        }
        sync.put(&out, "action", sync.text("delete"))
        sync.put(&out, "key", sync.text(key_text))
        let (rid, have_rid) = sync.get(existing, "id")
        if have_rid { sync.put(&out, "rowId", rid) }
        ret ir.obj_value(&out)
    }
    var data = sync.obj(a)
    var at = 0usize
    while at < mapping.len {
        let column = mapping[at]
        at += 1usize
        let (name, have_name) = sync.get(column, "name")
        if !ir.truthy(column) || !have_name || !ir.truthy(name) { continue }
        let (missing_in_source, have_missing) = sync.get(column, "missingInSource")
        var is_missing = false
        if have_missing {
            switch missing_in_source {
            case .Bool as b:
                is_missing = b
            default:
                is_missing = false
            }
        }
        if is_missing { continue }
        let (v, present) = sync.get(record, sync.as_text(name))
        if !present { continue }
        sync.put(&data, sync.as_text(name), syncjob.coerce_value(a, ir.truthy(ir.value_of(column, "structured")), v, true))
    }
    if data.len == 0usize { ret refusal(a, "no-mapped-column-in-delivery") }
    sync.put(&out, "ok", sync.flag(true))
    if !exists {
        sync.put(&out, "action", sync.text("insert"))
        sync.put(&out, "key", sync.text(key_text))
        sync.put(&out, "rowId", .Null)
    } else {
        sync.put(&out, "action", sync.text("update"))
        sync.put(&out, "key", sync.text(key_text))
        let (rid, have_rid) = sync.get(existing, "id")
        if have_rid { sync.put(&out, "rowId", rid) }
    }
    sync.put(&out, "data", ir.obj_value(&data))
    ret ir.obj_value(&out)
}

// The ledger counts a planned change contributes, shaped as a pull plan: exactly one of the three lists holds one
// `{key}`, and `bulkLoad` is false.
fn stream_plan_counts(a: *mem.Arena, plan: json.Value) -> json.Value {
    var one_entry = sync.obj(a)
    let (key, have_key) = sync.get(plan, "key")
    if have_key { sync.put(&one_entry, "key", key) }
    var one = sync.empty_list(a)
    sync.push_value(&one, ir.obj_value(&one_entry))
    let (action_text, have_action) = sync.member_text(plan, "action")
    var out = sync.obj(a)
    sync.put(&out, "inserts", json.Value{ Array: pick_list(one, have_action && str.eq(action_text, "insert")) })
    sync.put(&out, "updates", json.Value{ Array: pick_list(one, have_action && str.eq(action_text, "update")) })
    sync.put(&out, "deletes", json.Value{ Array: pick_list(one, have_action && str.eq(action_text, "delete")) })
    sync.put(&out, "quarantined", json.Value{ Array: zero })
    sync.put(&out, "bulkLoad", sync.flag(false))
    ret ir.obj_value(&out)
}

fn pick_list(one: list.List[json.Value], chosen: bool) -> []const json.Value {
    if chosen { ret list.slice_const[json.Value](&one) }
    ret zero
}

// --- entity browse ---------------------------------------------------------------------------------------------------

fn char_class(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret 1i32 }
    if (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) { ret 2i32 }
    ret 0i32
}

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// `x.localeCompare(y)` for ASCII names: negative, zero or positive.
fn collate(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        let cx = char_class(x[at])
        let cy = char_class(y[at])
        if cx != cy {
            if cx < cy { ret -1i32 }
            ret 1i32
        }
        let fx = fold(x[at])
        let fy = fold(y[at])
        if fx != fy {
            if fx < fy { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len != y.len {
        if x.len < y.len { ret -1i32 }
        ret 1i32
    }
    var k = 0usize
    while k < x.len {
        if x[k] != y[k] {
            // lower case before its capital
            if x[k] > y[k] { ret -1i32 }
            ret 1i32
        }
        k += 1usize
    }
    ret 0i32
}

fn name_of(v: json.Value) -> str {
    let (s, found) = sync.member_text(v, "name")
    if !found { ret "" }
    ret s
}

// A stable sort of entities by `name`.
fn sort_by_name(a: *mem.Arena, entities: []const json.Value) -> []const json.Value {
    var out = sync.empty_list(a)
    var i = 0usize
    while i < entities.len {
        sync.push_value(&out, entities[i])
        i += 1usize
    }
    var n = 1usize
    while n < out.len {
        let item = out.items[n]
        var j = n
        while j > 0usize && collate(name_of(item), name_of(out.items[j - 1usize])) < 0i32 {
            out.items[j] = out.items[j - 1usize]
            j -= 1usize
        }
        out.items[j] = item
        n += 1usize
    }
    ret list.slice_const[json.Value](&out)
}

fn has_path(entities: []const json.Value, path: str) -> bool {
    var at = 0usize
    while at < entities.len {
        let (p, found) = sync.member_text(entities[at], "path")
        if found && str.eq(p, path) { ret true }
        at += 1usize
    }
    ret false
}

// The entities a channel's own action list names: each GET action with a concrete path (starting `/`, no `{`), the first
// per path, named by the action's name.
fn static_entities(a: *mem.Arena, channel: json.Value) -> []const json.Value {
    var out = sync.empty_list(a)
    let (actions, is_object) = ir.members_of(ir.value_of(channel, "actions"))
    var at = 0usize
    while at < actions.len {
        let action = actions[at].value
        at += 1usize
        let (method, have_method) = sync.member_text(action, "method")
        let (path, have_path) = sync.member_text(action, "path")
        if !have_method || !str.eq(method, "GET") || !have_path { continue }
        if !str.starts_with(path, "/") || str.contains(path, "{") { continue }
        if has_path(list.slice_const[json.Value](&out), path) { continue }
        var entry = sync.obj(a)
        sync.put(&entry, "path", sync.text(path))
        let (name, have_name) = sync.get(action, "name")
        if have_name && ir.truthy(name) { sync.put(&entry, "name", name) } else { sync.put(&entry, "name", sync.text(path)) }
        let (key, have_key) = sync.get(action, "key")
        if have_key { sync.put(&entry, "action", key) }
        let (result_path, have_result) = sync.get(action, "resultPath")
        if have_result && ir.truthy(result_path) { sync.put(&entry, "resultPath", result_path) } else { sync.put(&entry, "resultPath", .Null) }
        sync.put(&entry, "source", sync.text("catalog"))
        sync.push_value(&out, ir.obj_value(&entry))
    }
    ret sort_by_name(a, list.slice_const[json.Value](&out))
}

// Can this source be asked what it holds: does the channel declare `browse.path`?
fn can_browse(channel: json.Value) -> bool {
    let (browse, found) = sync.get(channel, "browse")
    if !found { ret false }
    let (path, have_path) = sync.get(browse, "path")
    ret have_path && ir.truthy(path)
}

// A value at a dotted path, or null.
fn at_path(a: *mem.Arena, body: json.Value, path: str) -> (json.Value, bool) {
    if path.len == 0usize { ret (body, true) }
    var cursor = body
    var start = 0usize
    var i = 0usize
    while i <= path.len {
        if i == path.len || path[i] == 46u8 {
            let (members, is_object) = ir.members_of(cursor)
            if !is_object { ret (.Null, false) }
            let (next, found) = sync.get(cursor, path[start..i])
            if !found { ret (.Null, false) }
            cursor = next
            start = i + 1usize
        }
        i += 1usize
    }
    ret (cursor, true)
}

fn replace_name(a: *mem.Arena, template: str, raw: str) -> str {
    let (at, found) = str.find(template, "{name}")
    if !found { ret template }
    ret sync.cat(a, sync.cat(a, template[0usize..at], raw), template[at + 6usize..template.len])
}

// An index response as entities `[{path, name, source: "source"}]`: an array of names or of objects named by
// `browse.namePath`, or an object keyed by name; anything else is none.
fn entities_from_body(a: *mem.Arena, channel: json.Value, body: json.Value) -> []const json.Value {
    if !can_browse(channel) { ret zero }
    let browse = ir.value_of(channel, "browse")
    var result_path = ""
    let (rp, have_rp) = sync.member_text(browse, "resultPath")
    if have_rp { result_path = rp }
    var name_path = ""
    let (np, have_np) = sync.member_text(browse, "namePath")
    if have_np { name_path = np }
    var template = "/{name}"
    let (pt, have_pt) = sync.member_text(browse, "pathTemplate")
    if have_pt { template = pt }
    let (found, have_found) = at_path(a, body, result_path)
    var names = sync.empty_list(a)
    let (elements, is_array) = ir.items_of(found)
    let (keys, is_object) = ir.members_of(found)
    if have_found && is_array {
        var i = 0usize
        while i < elements.len {
            let (direct, is_text) = ir.string_of(elements[i])
            if is_text {
                sync.push_value(&names, sync.text(direct))
            } else if name_path.len > 0usize {
                let (v, have_v) = at_path(a, elements[i], name_path)
                let (s, text_ok) = ir.string_of(v)
                if have_v && text_ok && s.len > 0usize { sync.push_value(&names, sync.text(s)) }
            }
            i += 1usize
        }
    } else if have_found && is_object {
        var k = 0usize
        while k < keys.len {
            if keys[k].key.len > 0usize { sync.push_value(&names, sync.text(keys[k].key)) }
            k += 1usize
        }
    }
    var out = sync.empty_list(a)
    var n = 0usize
    while n < names.len && out.len < MAX_ENTITIES {
        let raw = sync.as_text(names.items[n])
        n += 1usize
        var path = raw
        if !str.starts_with(raw, "/") { path = replace_name(a, template, raw) }
        if str.eq(path, "/") || str.starts_with(path, "/rpc/") { continue }
        if has_path(list.slice_const[json.Value](&out), path) { continue }
        var display = raw
        if str.starts_with(raw, "/") { display = raw[1usize..raw.len] }
        var entry = sync.obj(a)
        sync.put(&entry, "path", sync.text(path))
        sync.put(&entry, "name", sync.text(display))
        sync.put(&entry, "source", sync.text("source"))
        sync.push_value(&out, ir.obj_value(&entry))
    }
    ret sort_by_name(a, list.slice_const[json.Value](&out))
}

// The one list a picker renders: what the source says, then what the catalog knows, folded on `path` with the source
// winning, capped and sorted by name.
fn merge_entities(a: *mem.Arena, from_source: []const json.Value, from_catalog: []const json.Value) -> []const json.Value {
    var out = sync.empty_list(a)
    var i = 0usize
    while i < from_source.len {
        let (path, found) = sync.member_text(from_source[i], "path")
        var slot = out.len
        var j = 0usize
        while j < out.len {
            let (p, pf) = sync.member_text(out.items[j], "path")
            if found && pf && str.eq(p, path) { slot = j }
            j += 1usize
        }
        if slot < out.len { out.items[slot] = from_source[i] } else { sync.push_value(&out, from_source[i]) }
        i += 1usize
    }
    var c = 0usize
    while c < from_catalog.len {
        let (path, found) = sync.member_text(from_catalog[c], "path")
        if !found || !has_path(list.slice_const[json.Value](&out), path) { sync.push_value(&out, from_catalog[c]) }
        c += 1usize
    }
    var capped = list.slice_const[json.Value](&out)
    if capped.len > MAX_ENTITIES { capped = capped[0usize..MAX_ENTITIES] }
    ret sort_by_name(a, capped)
}
