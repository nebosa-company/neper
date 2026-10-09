// `e.algo.fulltext` against appdor's own `src/search/{index,indexing-pipeline,tenant-scope}.js`:
// scripts/search_reference.mjs scores queries over random entity sets, plans, and runs scripted index, outbox and
// recents sessions with appdor's engine and writes `{"op": ..., ...inputs, "e": outcome}` lines; the fixture rebuilds
// the inputs and must render the same outcome.
use e.algo.formula as f
use e.algo.fulltext as s
use e.algo.view as view
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn hex_text(a: *mem.Arena, x: str) -> str {
    if x.len == 0usize { ret "_" }
    let (out, e) = mem.alloc[u8](a, x.len * 2usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < x.len {
        let hi = x[i] >> 4u8
        let lo = x[i] & 15u8
        var h = 48u8 + hi
        if hi > 9u8 { h = 87u8 + hi }
        var l = 48u8 + lo
        if lo > 9u8 { l = 87u8 + lo }
        out[i * 2usize] = h
        out[i * 2usize + 1usize] = l
        i += 1usize
    }
    ret out[0usize..x.len * 2usize]
}

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn join3(a: *mem.Arena, x: str, y: str, z: str) -> str { ret f.join3(a, x, y, z) }

fn num(a: *mem.Arena, n: f64) -> str { ret f.number_text(a, n) }

fn flag(b: bool) -> str {
    if b { ret "1" }
    ret "0"
}

// --- JSON to values ---------------------------------------------------------------------------------------------

fn members_of(x: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch x {
    case .Object as m:
        ret m
    default:
        ret none
    }
}

fn items_of(x: json.Value) -> []const json.Value {
    var none: []const json.Value = zero
    switch x {
    case .Array as items:
        ret items
    default:
        ret none
    }
}

fn get(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if str.eq(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var null_value: json.Value = .Null
    ret (null_value, false)
}

fn text_of(x: json.Value) -> str {
    switch x {
    case .String as v:
        ret v
    default:
        ret ""
    }
}

fn is_text(x: json.Value) -> bool {
    switch x {
    case .String as v:
        ret true
    default:
        ret false
    }
}

fn text_member(members: []const json.Member, key: str) -> str {
    let (x, found) = get(members, key)
    if !found { ret "" }
    ret text_of(x)
}

fn number_member(members: []const json.Member, key: str, fallback: f64) -> f64 {
    let (x, found) = get(members, key)
    if !found { ret fallback }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret fallback
    }
}

fn has_member(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    switch x {
    case .Null:
        ret false
    default:
        ret true
    }
}

fn bool_member(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    switch x {
    case .Bool as v:
        ret v
    default:
        ret false
    }
}

fn value_of(a: *mem.Arena, x: json.Value) -> f.Value {
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret f.number(value)
    case .String as v:
        ret f.text(v)
    case .Bool as v:
        ret f.boolean(v)
    case .Array as items:
        if items.len == 0usize { ret f.array(f.zero_items()) }
        let (out, e) = mem.alloc[f.Value](a, items.len)
        if e != ok { ret f.blank() }
        var i = 0usize
        while i < items.len {
            out[i] = value_of(a, items[i])
            i += 1usize
        }
        ret f.array(out)
    case .Object as members:
        ret f.record(f.zero_items())
    default:
        ret f.blank()
    }
}

fn fields_of(a: *mem.Arena, x: json.Value) -> []const f.Field {
    let members = members_of(x)
    var none: []const f.Field = zero
    if members.len == 0usize { ret none }
    let (out, e) = mem.alloc[f.Field](a, members.len)
    if e != ok { ret none }
    var i = 0usize
    while i < members.len {
        out[i] = f.Field { name: members[i].key, value: value_of(a, members[i].value) }
        i += 1usize
    }
    ret out
}

fn strings_of(a: *mem.Arena, x: json.Value) -> []const str {
    var none: []const str = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[str](a, items.len)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < items.len {
        switch items[i] {
        case .String as v:
            out[n] = v
            n += 1usize
        default:
            n += 0usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn entity_of(a: *mem.Arena, x: json.Value) -> s.Entity {
    let m = members_of(x)
    var e: s.Entity = zero
    e.id = text_member(m, "id")
    e.type_name = text_member(m, "type")
    e.title = text_member(m, "title")
    e.text = text_member(m, "text")
    let (fields, has_fields) = get(m, "fields")
    if has_fields && !is_null_value(fields) {
        e.has_fields = true
        e.fields = fields_of(a, fields)
    }
    e.app_id = text_member(m, "appId")
    e.table_id = text_member(m, "tableId")
    e.namespace = text_member(m, "namespace")
    e.key = text_member(m, "key")
    ret e
}

fn is_null_value(x: json.Value) -> bool {
    switch x {
    case .Null:
        ret true
    default:
        ret false
    }
}

fn entities_of(a: *mem.Arena, x: json.Value) -> []const s.Entity {
    let items = items_of(x)
    var none: []const s.Entity = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[s.Entity](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = entity_of(a, items[i])
        i += 1usize
    }
    ret out
}

fn doc_of(a: *mem.Arena, x: json.Value) -> s.IndexDoc {
    let m = members_of(x)
    var d: s.IndexDoc = zero
    d.id = text_member(m, "id")
    d.kind = text_member(m, "kind")
    let (realm, has_realm) = get(m, "realmId")
    if has_realm && is_text(realm) {
        d.realm_id = text_of(realm)
        d.has_realm = true
    }
    d.tenant_id = text_member(m, "tenantId")
    d.title = text_member(m, "title")
    d.text = text_member(m, "text")
    let (fields, has_fields) = get(m, "fields")
    if has_fields && !is_null_value(fields) {
        d.has_fields = true
        d.fields = fields_of(a, fields)
    }
    d.table_id = text_member(m, "tableId")
    d.key = text_member(m, "key")
    ret d
}

fn docs_of(a: *mem.Arena, x: json.Value) -> []const s.IndexDoc {
    let items = items_of(x)
    var none: []const s.IndexDoc = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[s.IndexDoc](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = doc_of(a, items[i])
        i += 1usize
    }
    ret out
}

fn events_of(a: *mem.Arena, x: json.Value) -> []const s.Event {
    let items = items_of(x)
    var none: []const s.Event = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[s.Event](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        let (at, has_at) = get(m, "at")
        out[i] = s.Event { seq: number_member(m, "seq", 0.0f64), artifact_id: text_member(m, "artifactId"), type_name: text_member(m, "type"), at: text_of(at), has_at: has_at && is_text(at) }
        i += 1usize
    }
    ret out
}

fn query_of(a: *mem.Arena, m: []const json.Member) -> s.Query {
    var q: s.Query = zero
    let (kinds, has_kinds) = get(m, "kinds")
    if has_kinds && !is_null_value(kinds) {
        q.has_kinds = true
        q.kinds = strings_of(a, kinds)
    }
    q.table_id = text_member(m, "tableId")
    q.tenant_id = text_member(m, "tenantId")
    let (realm, has_realm) = get(m, "realm")
    if has_realm && is_text(realm) {
        q.realm = text_of(realm)
        q.has_realm = true
    }
    if has_member(m, "limit") {
        q.has_limit = true
        q.limit = usize(number_member(m, "limit", 20.0f64))
    }
    let (searchable, has_searchable) = get(m, "searchableFields")
    if has_searchable && !is_null_value(searchable) {
        q.has_searchable = true
        q.searchable = strings_of(a, searchable)
    }
    let (skip, has_skip) = get(m, "skipFields")
    if has_skip { q.skip = strings_of(a, skip) }
    q.suggest_limit = usize(number_member(m, "suggestLimit", 0.0f64))
    ret q
}

// --- rendering ------------------------------------------------------------------------------------------------

fn render_candidates(a: *mem.Arena, list: []const s.Candidate) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        let c = list[i]
        out = join(a, out, join3(a, hex_text(a, c.id), ":", join3(a, hex_text(a, c.title), ":", join3(a, c.kind, ":", join3(a, num(a, c.score), ":", join3(a, hex_text(a, c.key), ":", join(a, hex_text(a, c.table_id), ";")))))))
        i += 1usize
    }
    ret out
}

fn render_counts(a: *mem.Arena, c: s.Counts) -> str {
    var out = num(a, f64(c.total))
    var i = 0usize
    while i < c.by_kind.len {
        out = join(a, out, join3(a, ",", c.by_kind[i].kind, join(a, "=", num(a, f64(c.by_kind[i].count)))))
        i += 1usize
    }
    if c.has_realm { out = join(a, out, join(a, "@", hex_text(a, c.realm))) }
    ret out
}

fn render_scoped(a: *mem.Arena, r: s.Scoped) -> str {
    var out = join3(a, render_candidates(a, r.results), "|", join3(a, num(a, f64(r.total)), "|", render_counts(a, r.counts)))
    out = join(a, out, "|")
    var i = 0usize
    while i < r.suggestions.len {
        out = join(a, out, join3(a, hex_text(a, r.suggestions[i].id), ":", join3(a, hex_text(a, r.suggestions[i].title), ":", join(a, r.suggestions[i].kind, ";"))))
        i += 1usize
    }
    ret out
}

fn render_hits(a: *mem.Arena, r: s.SearchResult) -> str {
    var out = ""
    var i = 0usize
    while i < r.results.len {
        out = join(a, out, join3(a, hex_text(a, r.results[i].entity.id), ":", join(a, num(a, r.results[i].score), ":")))
        var k = 0usize
        while k < r.results[i].matches.len {
            out = join(a, out, join(a, hex_text(a, r.results[i].matches[k]), ","))
            k += 1usize
        }
        out = join(a, out, ";")
        i += 1usize
    }
    ret join(a, out, join(a, "|", num(a, f64(r.total))))
}

fn render_dead(a: *mem.Arena, list: []const s.DeadLetter) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        out = join(a, out, join3(a, num(a, list[i].seq), ":", join3(a, hex_text(a, list[i].artifact_id), ":", join3(a, hex_text(a, list[i].message), ":", join(a, hex_text(a, list[i].at), ";")))))
        i += 1usize
    }
    ret out
}

// --- the scripted session ---------------------------------------------------------------------------------------

// What the host's callbacks answer: documents for events, who may see what, which ids throw.
type Host = struct {
    source: []const s.IndexDoc,
    fail_ids: []const str,
    skip_ids: []const str,
    hidden_ids: []const str,
    boost: s.BoostState,
}

var g_arena: *mem.Arena = zero

fn to_document(state: *void, e: s.Event) -> s.Mapped {
    let h = mem.cast[*Host](state)
    var none: s.IndexDoc = zero
    var i = 0usize
    while i < h.fail_ids.len {
        if str.eq(h.fail_ids[i], e.artifact_id) { ret s.Mapped { has_doc: false, doc: none, threw: true, message: join(g_arena, "Error: bad ", e.artifact_id) } }
        i += 1usize
    }
    i = 0usize
    while i < h.skip_ids.len {
        if str.eq(h.skip_ids[i], e.artifact_id) { ret s.Mapped { has_doc: false, doc: none, threw: false, message: "" } }
        i += 1usize
    }
    i = 0usize
    while i < h.source.len {
        if str.eq(h.source[i].id, e.artifact_id) { ret s.Mapped { has_doc: true, doc: h.source[i], threw: false, message: "" } }
        i += 1usize
    }
    var d = none
    d.id = e.artifact_id
    d.kind = "record"
    d.title = join(g_arena, "T ", e.artifact_id)
    ret s.Mapped { has_doc: true, doc: d, threw: false, message: "" }
}

fn can_see(state: *void, d: s.IndexDoc) -> bool {
    let h = mem.cast[*Host](state)
    var i = 0usize
    while i < h.hidden_ids.len {
        if str.eq(h.hidden_ids[i], d.id) { ret false }
        i += 1usize
    }
    ret true
}

fn no_boost(state: *void, d: s.IndexDoc) -> f64 { ret 0.0f64 }

fn user_boost(state: *void, d: s.IndexDoc) -> f64 {
    let h = mem.cast[*Host](state)
    ret s.recents_boost(mem.cast[*void](&h.boost), d)
}

fn run_pipeline(a: *mem.Arena, m: []const json.Member) -> str {
    var host: Host = zero
    let (source, hs) = get(m, "source")
    host.source = docs_of(a, source)
    let (fail, hf) = get(m, "failIds")
    host.fail_ids = strings_of(a, fail)
    let (skip, hk) = get(m, "skipIds")
    host.skip_ids = strings_of(a, skip)
    let (hidden, hh) = get(m, "hiddenIds")
    host.hidden_ids = strings_of(a, hidden)
    let (realm, has_realm) = get(m, "realm")
    var realm_text = ""
    var realm_set = false
    if has_realm && is_text(realm) {
        realm_text = text_of(realm)
        realm_set = true
    }
    var ix = s.new_index(a, 512usize, bool_member(m, "enforceRealm"), realm_text, realm_set)
    var consumer = s.new_consumer(a, 512usize)
    var recents = s.new_recents(a, usize(number_member(m, "recentsLimit", 0.0f64)), 8usize)
    host.boost = s.BoostState { recents: &recents, user: "" }
    let state = mem.cast[*void](&host)
    let (script, hscript) = get(m, "script")
    let steps = items_of(script)
    var out = ""
    var k = 0usize
    while k < steps.len {
        let parts = items_of(steps[k])
        let kind = text_of(parts[0usize])
        var arg_members = members_of(parts[parts.len - 1usize])
        if str.eq(kind, "upsert") {
            let r = s.upsert(&ix, doc_of(a, parts[1usize]))
            out = join(a, out, join3(a, flag(r.valid), ":", r.reason))
        } else if str.eq(kind, "batch") {
            let r = s.batch_upsert(&ix, docs_of(a, parts[1usize]))
            out = join(a, out, join3(a, num(a, f64(r.upserted)), ",", join3(a, num(a, f64(r.errors)), ",", num(a, f64(r.deduplicated)))))
        } else if str.eq(kind, "remove") {
            s.remove(&ix, text_of(parts[1usize]))
            out = join(a, out, "r")
        } else if str.eq(kind, "batchRemove") {
            out = join(a, out, num(a, f64(s.batch_remove(&ix, strings_of(a, parts[1usize])))))
        } else if str.eq(kind, "size") {
            out = join(a, out, num(a, f64(s.doc_count(&ix))))
        } else if str.eq(kind, "has") {
            out = join(a, out, flag(s.has_doc(&ix, text_of(parts[1usize]))))
        } else if str.eq(kind, "query") || str.eq(kind, "queryUser") {
            let q = query_of(a, members_of(parts[2usize]))
            var has_boost = false
            if str.eq(kind, "queryUser") {
                host.boost = s.BoostState { recents: &recents, user: text_of(parts[3usize]) }
                has_boost = true
            }
            var found: []const s.Candidate = zero
            if has_boost {
                found = s.query_docs(&ix, text_of(parts[1usize]), q, can_see, bool_member(members_of(parts[2usize]), "canSee"), user_boost, true, state)
            } else {
                found = s.query_docs(&ix, text_of(parts[1usize]), q, can_see, bool_member(members_of(parts[2usize]), "canSee"), no_boost, false, state)
            }
            out = join(a, out, render_candidates(a, found))
        } else if str.eq(kind, "queryScoped") || str.eq(kind, "suggest") {
            let q = query_of(a, members_of(parts[2usize]))
            let r = s.query_scoped(&ix, text_of(parts[1usize]), q, can_see, bool_member(members_of(parts[2usize]), "canSee"), no_boost, false, state)
            if str.eq(kind, "suggest") {
                var i = 0usize
                while i < r.suggestions.len {
                    out = join(a, out, join3(a, hex_text(a, r.suggestions[i].id), ":", join(a, hex_text(a, r.suggestions[i].title), ",")))
                    i += 1usize
                }
            } else {
                out = join(a, out, render_scoped(a, r))
            }
        } else if str.eq(kind, "scopedStats") {
            let (counts, up, rem, errs) = s.scoped_stats(&ix, text_of(parts[1usize]), is_text(parts[1usize]))
            out = join(a, out, join3(a, render_counts(a, counts), "|", join3(a, num(a, f64(up)), ",", join3(a, num(a, f64(rem)), ",", num(a, f64(errs))))))
        } else if str.eq(kind, "stats") {
            let st = s.stats(&ix)
            out = join(a, out, join3(a, num(a, f64(st.document_count)), "|", join3(a, num(a, f64(st.upserted)), ",", join3(a, num(a, f64(st.removed)), ",", num(a, f64(st.errors))))))
            var i = 0usize
            while i < st.by_kind.len {
                out = join(a, out, join3(a, "|", st.by_kind[i].kind, join(a, "=", num(a, f64(st.by_kind[i].count)))))
                i += 1usize
            }
            i = 0usize
            while i < st.by_tenant.len {
                out = join(a, out, join3(a, "|t:", hex_text(a, st.by_tenant[i].kind), join(a, "=", num(a, f64(st.by_tenant[i].count)))))
                i += 1usize
            }
        } else if str.eq(kind, "drop") {
            let r = s.drop_realm_and_unattributed(&ix, text_of(parts[1usize]), is_text(parts[1usize]))
            out = join(a, out, join3(a, flag(r.valid), ":", join3(a, r.reason, ":", join3(a, num(a, f64(r.removed)), ",", num(a, f64(r.unattributed))))))
        } else if str.eq(kind, "clear") {
            s.clear(&ix)
            out = join(a, out, "c")
        } else if str.eq(kind, "drain") {
            let r = s.drain(&consumer, &ix, events_of(a, parts[1usize]), bool_member(arg_members, "batch"), to_document, state, text_member(arg_members, "now"))
            var line = join3(a, num(a, f64(r.processed)), ",", num(a, f64(r.upserts)))
            line = join(a, line, join3(a, ",", num(a, f64(r.removals)), ","))
            line = join(a, line, join3(a, num(a, f64(r.errors)), ",", num(a, r.cursor)))
            out = join(a, out, join(a, line, render_dead(a, r.dead_letters)))
        } else if str.eq(kind, "backlog") {
            let b = s.backlog(&consumer, events_of(a, parts[1usize]))
            var oldest = "-"
            if b.has_oldest { oldest = num(a, b.oldest_seq) }
            var at = "-"
            if b.has_oldest_at { at = hex_text(a, b.oldest_at) }
            out = join(a, out, join3(a, num(a, f64(b.depth)), ",", join3(a, oldest, ",", join3(a, at, ",", num(a, b.cursor)))))
        } else if str.eq(kind, "wedged") {
            let w = s.is_wedged(&consumer, events_of(a, parts[1usize]), number_member(arg_members, "nowMs", 0.0f64))
            out = join(a, out, join3(a, flag(w.wedged), ":", hex_text(a, w.reason)))
        } else if str.eq(kind, "cstats") {
            let st = s.consumer_stats(&consumer, events_of(a, parts[1usize]), number_member(arg_members, "nowMs", 0.0f64))
            var drained = "-"
            if st.has_last_drain { drained = hex_text(a, st.last_drain_at) }
            var line = join3(a, num(a, st.cursor), ",", num(a, f64(st.total_processed)))
            line = join(a, line, join3(a, ",", num(a, f64(st.total_upserts)), ","))
            line = join(a, line, join3(a, num(a, f64(st.total_removals)), ",", drained))
            line = join(a, line, join3(a, ",", num(a, f64(st.dead_letter_count)), ","))
            line = join(a, line, join3(a, num(a, f64(st.backlog.depth)), ",", flag(st.wedged.wedged)))
            out = join(a, out, join(a, line, join(a, ":", hex_text(a, st.wedged.reason))))
        } else if str.eq(kind, "clearDead") {
            s.clear_dead_letters(&consumer)
            out = join(a, out, "d")
        } else if str.eq(kind, "touch") {
            s.touch(&recents, text_of(parts[1usize]), text_of(parts[2usize]), text_of(parts[3usize]))
            out = join(a, out, "t")
        } else if str.eq(kind, "recents") {
            let list = s.recents_of(&recents, text_of(parts[1usize]), usize(number_member(arg_members, "n", 10.0f64)))
            var i = 0usize
            while i < list.len {
                out = join(a, out, join3(a, hex_text(a, list[i].id), ":", join(a, hex_text(a, list[i].at), ",")))
                i += 1usize
            }
        } else if str.eq(kind, "fav") {
            s.favorite(&recents, text_of(parts[1usize]), text_of(parts[2usize]))
            out = join(a, out, "f")
        } else if str.eq(kind, "unfav") {
            s.unfavorite(&recents, text_of(parts[1usize]), text_of(parts[2usize]))
            out = join(a, out, "u")
        } else if str.eq(kind, "isFav") {
            out = join(a, out, flag(s.is_favorite(&recents, text_of(parts[1usize]), text_of(parts[2usize]))))
        } else if str.eq(kind, "purge") {
            s.purge_for_user(&recents, text_of(parts[1usize]), strings_of(a, parts[2usize]))
            out = join(a, out, "p")
        }
        out = join(a, out, ";")
        k += 1usize
    }
    ret out
}

fn run(a: *mem.Arena, body: str) -> u8 {
    g_arena = a
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 24u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                let m = members_of(root)
                want = text_member(m, "e")
                got = evaluate(a, m)
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn evaluate(a: *mem.Arena, m: []const json.Member) -> str {
    let op = text_member(m, "op")
    if str.eq(op, "search") {
        let (entities_value, he) = get(m, "entities")
        let (build, hb) = get(m, "build")
        let bm = members_of(build)
        var options: s.IndexOptions = zero
        let (searchable, has_searchable) = get(bm, "searchableFields")
        if has_searchable && !is_null_value(searchable) {
            options.has_searchable = true
            options.searchable = strings_of(a, searchable)
        }
        let (skip, has_skip) = get(bm, "skipFields")
        if has_skip { options.skip = strings_of(a, skip) }
        let index = s.build_index(a, entities_of(a, entities_value), options)
        let (opts, ho) = get(m, "options")
        let om = members_of(opts)
        var so: s.SearchOptions = zero
        so.limit = usize(number_member(om, "limit", 0.0f64))
        let (types, has_types) = get(om, "types")
        if has_types && !is_null_value(types) {
            so.has_types = true
            so.types = strings_of(a, types)
        }
        so.app_id = text_member(om, "appId")
        so.table_id = text_member(om, "tableId")
        so.namespace = text_member(om, "namespace")
        ret render_hits(a, s.search(a, index, text_member(m, "query"), so))
    }
    if str.eq(op, "searchable") {
        let (data, hd) = get(m, "data")
        let (columns, hc) = get(m, "columns")
        let items = items_of(columns)
        let (cols, ce) = mem.alloc[s.Column](a, items.len + 1usize)
        if ce != ok { ret "oom" }
        var k = 0usize
        while k < items.len {
            let cm = members_of(items[k])
            let (flag_value, has_flag) = get(cm, "searchable")
            var not_searchable = false
            switch flag_value {
            case .Bool as v:
                not_searchable = !v
            default:
                not_searchable = false
            }
            cols[k] = s.Column { name: text_member(cm, "name"), not_searchable: not_searchable }
            k += 1usize
        }
        let kept = s.searchable_fields(a, fields_of(a, data), cols[0usize..items.len])
        var out = ""
        k = 0usize
        while k < kept.len {
            out = join(a, out, join(a, hex_text(a, kept[k].name), ","))
            k += 1usize
        }
        ret out
    }
    if str.eq(op, "findtable") {
        let (records_value, hr) = get(m, "records")
        let items = items_of(records_value)
        let (rows, re) = mem.alloc[view.Row](a, items.len + 1usize)
        if re != ok { ret "oom" }
        var k = 0usize
        while k < items.len {
            rows[k] = view.Row { fields: fields_of(a, items[k]) }
            k += 1usize
        }
        let (names, hn) = get(m, "names")
        let hits = s.find_in_table(a, rows[0usize..items.len], text_member(m, "query"), strings_of(a, names))
        var out = ""
        k = 0usize
        while k < hits.len {
            out = join(a, out, join(a, num(a, f64(hits[k].index)), ":"))
            var c = 0usize
            while c < hits[k].fields.len {
                out = join(a, out, join3(a, hex_text(a, hits[k].fields[c].field), "=", join(a, hex_text(a, hits[k].fields[c].snippet), ",")))
                c += 1usize
            }
            out = join(a, out, ";")
            k += 1usize
        }
        ret out
    }
    if str.eq(op, "plan") {
        let (rc, has_rc) = get(m, "rowCount")
        let (lr, has_lr) = get(m, "loadedRows")
        let (limit, has_limit) = get(m, "limit")
        let (offset, has_offset) = get(m, "offset")
        let p = s.plan_search(text_member(m, "query"), number_member(m, "rowCount", 0.0f64), has_member(m, "rowCount"), number_member(m, "loadedRows", 0.0f64), has_member(m, "loadedRows"), text_member(m, "tableId"), number_member(m, "limit", 0.0f64), has_member(m, "limit"), number_member(m, "offset", 0.0f64), has_member(m, "offset"), bool_member(m, "fuzzy"))
        var table = "-"
        if p.has_table_id { table = hex_text(a, p.table_id) }
        if str.eq(p.mode, "server") {
            ret join3(a, p.mode, ":", join3(a, p.reason, ":", join3(a, table, ":", join3(a, hex_text(a, p.query), ":", join3(a, num(a, p.limit), ":", join3(a, num(a, p.offset), ":", flag(p.fuzzy)))))))
        }
        ret join3(a, p.mode, ":", p.reason)
    }
    if str.eq(op, "detect") {
        let (prefix, number, good) = s.detect_record_key(text_member(m, "text"))
        var out = "null"
        if good { out = join3(a, prefix, ":", number) }
        ret join3(a, out, "|", flag(s.is_record_key(text_member(m, "text"))))
    }
    if str.eq(op, "pipeline") { ret run_pipeline(a, m) }
    ret "unknown op"
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo fulltext ok")
    ret ok
}
