// Full-text search and its indexing pipeline (L034), after appdor's `src/search/{index,indexing-pipeline,
// tenant-scope}.js`: tokenized documents scored with AND semantics (title, prefix and body weights over a type
// boost, a record-key fast path and key-prefix bonus), the index-time field allowlist, find-in-table with
// snippets, the client/server plan at 1,000 rows; an incremental document index with batch upserts, realm
// boundaries that fail closed (a scope that does not resolve returns the one empty result, counts and suggestions
// derive from the scoped set), permission trimming before ranking truncation, an outbox consumer whose cursor
// makes a replay idempotent (batch mode coalesces by artifact, failures go to dead letters, wedge detection), and
// recents and favorites that boost what the asker uses.
//
// Text is read as JavaScript reads it: tokens are the ASCII letters and digits of the lower-cased text; ordering of
// equal scores is `localeCompare` over titles (`e.algo.view`'s root-collation approximation).
//
// Differences from appdor's: the clock is a parameter (`now_ms`); the wedged reasons are the catalogue keys
// humanized, as appdor's are with no bundle loaded; a document's `meta` is not carried.

use e.algo.formula as f
use e.algo.formula.text as tx
use e.algo.view as view
use e.math
use e.mem
use e.str
use e.text.utf8 as utf8

// --- tokens and scoring -----------------------------------------------------------------------------------------

fn is_alnum(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 97u8 && c <= 122u8) }

// The distinct ASCII-alphanumeric runs of the lower-cased text.
fn tokenize(a: *mem.Arena, text: str) -> []const str {
    var none: []const str = zero
    let lower = tx.lower_text(a, text)
    let (out, e) = mem.alloc[str](a, lower.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < lower.len {
        if is_alnum(lower[i]) {
            var j = i
            while j < lower.len && is_alnum(lower[j]) { j += 1usize }
            var seen = false
            var k = 0usize
            while k < n {
                if str.eq(out[k], lower[i..j]) { seen = true }
                k += 1usize
            }
            if !seen {
                out[n] = lower[i..j]
                n += 1usize
            }
            i = j
        } else {
            i += 1usize
        }
    }
    ret out[0usize..n]
}

fn has_token(tokens: []const str, term: str) -> bool {
    var i = 0usize
    while i < tokens.len {
        if str.eq(tokens[i], term) { ret true }
        i += 1usize
    }
    ret false
}

fn has_prefixed(tokens: []const str, term: str) -> bool {
    var i = 0usize
    while i < tokens.len {
        if str.starts_with(tokens[i], term) { ret true }
        i += 1usize
    }
    ret false
}

fn type_boost(kind: str) -> f64 {
    if str.eq(kind, "app") { ret 1.3f64 }
    if str.eq(kind, "table") { ret 1.15f64 }
    if str.eq(kind, "page") || str.eq(kind, "view") || str.eq(kind, "form") || str.eq(kind, "dashboard") { ret 1.05f64 }
    ret 1.0f64
}

// What a searchable thing is: its `type`, title and text (or its fields, which become the text), and where it
// lives (`app_id`, `table_id`, `namespace`, empty when it has none) and its record `key`.
type Entity = struct {
    id: str,
    type_name: str,
    title: str,
    text: str,
    fields: []const f.Field,
    has_fields: bool,
    app_id: str,
    table_id: str,
    namespace: str,
    key: str,
}

// `String(v)` of a field value, an array joined by spaces.
fn field_text(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Blank { ret "" }
    if v.kind == .Array {
        var out = ""
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, " ") }
            if v.items[i].kind != .Blank { out = f.join(a, out, view.js_string(a, v.items[i])) }
            i += 1usize
        }
        ret out
    }
    ret view.js_string(a, v)
}

fn in_list(list: []const str, name: str) -> bool {
    var i = 0usize
    while i < list.len {
        if str.eq(list[i], name) { ret true }
        i += 1usize
    }
    ret false
}

// Which fields go into the index text: all but the skipped ones and, when an allowlist is given, only those.
type IndexOptions = struct { searchable: []const str, has_searchable: bool, skip: []const str }

fn body_text(a: *mem.Arena, e: Entity, options: IndexOptions) -> str {
    if e.text.len > 0usize { ret e.text }
    if !e.has_fields { ret "" }
    var out = ""
    var wrote = false
    var i = 0usize
    while i < e.fields.len {
        let name = e.fields[i].name
        let allowed = !options.has_searchable || in_list(options.searchable, name)
        if !in_list(options.skip, name) && allowed {
            let text = field_text(a, e.fields[i].value)
            if text.len > 0usize {
                if wrote { out = f.join(a, out, " ") }
                out = f.join(a, out, text)
                wrote = true
            }
        }
        i += 1usize
    }
    ret out
}

type Doc = struct {
    entity: Entity,
    title: str,
    title_lower: str,
    title_tokens: []const str,
    body_lower: str,
    body_tokens: []const str,
}

type Index = struct { docs: []const Doc }

fn build_index(a: *mem.Arena, entities: []const Entity, options: IndexOptions) -> Index {
    var none: []const Doc = zero
    let (docs, e) = mem.alloc[Doc](a, entities.len + 1usize)
    if e != ok { ret Index { docs: none } }
    var i = 0usize
    while i < entities.len {
        let en = entities[i]
        let body = body_text(a, en, options)
        docs[i] = Doc {
            entity: en,
            title: en.title,
            title_lower: tx.lower_text(a, en.title),
            title_tokens: tokenize(a, en.title),
            body_lower: tx.lower_text(a, body),
            body_tokens: tokenize(a, body),
        }
        i += 1usize
    }
    ret Index { docs: docs[0usize..entities.len] }
}

// One term against a document: the score and whether it matched.
fn score_term(d: Doc, term: str) -> (f64, bool) {
    var s = 0.0f64
    var matched = false
    if str.eq(d.title_lower, term) {
        s += 12.0f64
        matched = true
    }
    if has_token(d.title_tokens, term) {
        s += 6.0f64
        matched = true
    } else if has_prefixed(d.title_tokens, term) {
        s += 3.0f64
        matched = true
    }
    if has_token(d.body_tokens, term) {
        s += 2.0f64
        matched = true
    } else if str.contains(d.body_lower, term) {
        s += 1.0f64
        matched = true
    }
    if !matched && str.contains(d.title_lower, term) {
        s += 2.0f64
        matched = true
    }
    ret (s, matched)
}

// `^([A-Z]{2,}[A-Z0-9_]*)-(\d+)$`: the prefix and the number of a record key, or false.
fn record_key(s: str) -> (str, str, bool) {
    var dash = s.len
    var i = 0usize
    while i < s.len {
        if s[i] == 45u8 { dash = i }
        i += 1usize
    }
    if dash == s.len || dash < 2usize || dash + 1usize >= s.len { ret ("", "", false) }
    i = 0usize
    while i < dash {
        let c = s[i]
        let upper = c >= 65u8 && c <= 90u8
        if i < 2usize && !upper { ret ("", "", false) }
        if !upper && !(c >= 48u8 && c <= 57u8) && c != 95u8 { ret ("", "", false) }
        i += 1usize
    }
    i = dash + 1usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret ("", "", false) }
        i += 1usize
    }
    ret (s[0usize..dash], s[dash + 1usize..s.len], true)
}

// An exact record-key query (the command palette's direct-navigation row): its prefix and number.
fn detect_record_key(text: str) -> (str, str, bool) {
    let (prefix, number, good) = record_key(view.js_trim(text))
    ret (prefix, number, good)
}

fn is_record_key(value: str) -> bool {
    let (p, n, good) = record_key(value)
    ret good
}

type SearchOptions = struct {
    limit: usize,
    types: []const str,
    has_types: bool,
    app_id: str,
    table_id: str,
    namespace: str,
}

type Hit = struct { entity: Entity, score: f64, matches: []const str }

type SearchResult = struct { results: []const Hit, total: usize }

// Search the index. Every term must match somewhere; an exact record-key query short-circuits token matching.
fn search(a: *mem.Arena, index: Index, query: str, options: SearchOptions) -> SearchResult {
    var none_hits: []const Hit = zero
    let terms = tokenize(a, query)
    if terms.len == 0usize { ret SearchResult { results: none_hits, total: 0usize } }
    var limit = options.limit
    if limit == 0usize { limit = 20usize }
    let trimmed = view.js_trim(query)
    let (key_prefix, key_number, has_key) = record_key(trimmed)
    let (scored, se) = mem.alloc[Hit](a, index.docs.len + 1usize)
    if se != ok { ret SearchResult { results: none_hits, total: 0usize } }
    var n = 0usize
    var i = 0usize
    while i < index.docs.len {
        let d = index.docs[i]
        i += 1usize
        if options.has_types && !in_list(options.types, d.entity.type_name) { continue }
        if options.table_id.len > 0usize && d.entity.table_id.len > 0usize && !str.eq(d.entity.table_id, options.table_id) { continue }
        if options.namespace.len > 0usize && d.entity.namespace.len > 0usize && !str.eq(d.entity.namespace, options.namespace) { continue }
        if options.app_id.len > 0usize && d.entity.app_id.len > 0usize && !str.eq(d.entity.app_id, options.app_id) { continue }
        if has_key && d.entity.key.len > 0usize && str.eq(d.entity.key, trimmed) {
            let (cell, ce) = mem.alloc[str](a, 1usize)
            if ce != ok { continue }
            cell[0usize] = trimmed
            scored[n] = Hit { entity: d.entity, score: 30.0f64 * type_boost(d.entity.type_name), matches: cell[0usize..1usize] }
            n += 1usize
            continue
        }
        var total = 0.0f64
        let (matches, me) = mem.alloc[str](a, terms.len)
        if me != ok { continue }
        var all = true
        var t = 0usize
        while t < terms.len && all {
            let (s, matched) = score_term(d, terms[t])
            if !matched {
                all = false
            } else {
                total += s
                matches[t] = terms[t]
                t += 1usize
            }
        }
        if !all { continue }
        var key_bonus = 0.0f64
        if has_key && d.entity.key.len > 0usize {
            if !str.eq(d.entity.key, trimmed) && str.starts_with(tx.lower_text(a, d.entity.key), tx.lower_text(a, key_prefix)) { key_bonus = 5.0f64 }
        }
        total = total * type_boost(d.entity.type_name)
        total += key_bonus
        scored[n] = Hit { entity: d.entity, score: total, matches: matches[0usize..terms.len] }
        n += 1usize
    }
    // best score first, then by title (stable)
    var x = 1usize
    while x < n {
        let item = scored[x]
        var y = x
        while y > 0usize && hit_after(scored[y - 1usize], item) {
            scored[y] = scored[y - 1usize]
            y -= 1usize
        }
        scored[y] = item
        x += 1usize
    }
    var shown = n
    if limit < shown { shown = limit }
    ret SearchResult { results: scored[0usize..shown], total: n }
}

// Whether `left` sorts after `right`: a lower score, or the same score and a later title.
fn hit_after(left: Hit, right: Hit) -> bool {
    if left.score != right.score { ret left.score < right.score }
    ret view.collate_text(left.entity.title, right.entity.title) > 0i32
}

// The fields of a row that may be indexed: unknown columns are kept, `searchable: false` ones dropped.
type Column = struct { name: str, not_searchable: bool }

fn searchable_fields(a: *mem.Arena, data: []const f.Field, columns: []const Column) -> []const f.Field {
    if columns.len == 0usize { ret data }
    let (out, e) = mem.alloc[f.Field](a, data.len + 1usize)
    if e != ok { ret data }
    var n = 0usize
    var i = 0usize
    while i < data.len {
        var excluded = false
        var k = 0usize
        while k < columns.len {
            if columns[k].not_searchable && columns[k].name.len > 0usize && str.eq(columns[k].name, data[i].name) { excluded = true }
            k += 1usize
        }
        if !excluded {
            out[n] = data[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- find in a table --------------------------------------------------------------------------------------------

type FieldMatch = struct { field: str, snippet: str }

type TableHit = struct { index: usize, fields: []const FieldMatch }

// The UTF-16 units of a text.
fn units(a: *mem.Arena, s: str) -> []const u16 {
    var none: []const u16 = zero
    let (out, e) = mem.alloc[u16](a, s.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else if scalar >= 65536u32 {
            out[n] = u16(55296u32 + ((scalar - 65536u32) >> 10u32))
            out[n + 1usize] = u16(56320u32 + ((scalar - 65536u32) & 1023u32))
            n += 2usize
        } else {
            out[n] = u16(scalar)
            n += 1usize
        }
    }
    ret out[0usize..n]
}

// A short window around the first match: 20 units each side, `…` where the text continues. The window is cut from
// the original text by the position found in its lower-cased form, as appdor's does.
fn snippet(a: *mem.Arena, text: str, needle: str) -> str {
    let lower = tx.lower_text(a, text)
    let (at, found) = str.find(lower, needle)
    let all = units(a, text)
    if !found {
        var cut = 60usize
        if all.len < cut { cut = all.len }
        ret tx.text_of_units(a, all[0usize..cut])
    }
    let idx = view_unit_index(a, lower, at)
    let needle_len = units(a, needle).len
    var start = 0usize
    if idx > 20usize { start = idx - 20usize }
    var end = idx + needle_len + 20usize
    var more = end < all.len
    if end > all.len { end = all.len }
    if start > end { start = end }
    var out = tx.text_of_units(a, all[start..end])
    if start > 0usize { out = f.join(a, "\xe2\x80\xa6", out) }
    if more { out = f.join(a, out, "\xe2\x80\xa6") }
    ret out
}

// The UTF-16 position of a byte offset.
fn view_unit_index(a: *mem.Arena, s: str, byte_at: usize) -> usize {
    ret units(a, s[0usize..byte_at]).len
}

// Substring search across the given fields (all of a record's when none are named), a snippet per matched field.
fn find_in_table(a: *mem.Arena, records: []const view.Row, query: str, names: []const str) -> []const TableHit {
    var none: []const TableHit = zero
    let needle = tx.lower_text(a, query)
    if needle.len == 0usize { ret none }
    let (out, e) = mem.alloc[TableHit](a, records.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < records.len {
        var count = names.len
        if names.len == 0usize { count = records[i].fields.len }
        let (matched, me) = mem.alloc[FieldMatch](a, count + 1usize)
        if me != ok { ret none }
        var mn = 0usize
        var k = 0usize
        while k < count {
            var key = ""
            var v = f.blank()
            if names.len == 0usize {
                key = records[i].fields[k].name
                v = records[i].fields[k].value
            } else {
                key = names[k]
                v = view.value_at(records[i], key)
            }
            if v.kind != .Blank {
                var text = ""
                if v.kind == .Array {
                    text = field_text(a, v)
                } else {
                    text = view.js_string(a, v)
                }
                if str.contains(tx.lower_text(a, text), needle) {
                    matched[mn] = FieldMatch { field: key, snippet: snippet(a, text, needle) }
                    mn += 1usize
                }
            }
            k += 1usize
        }
        if mn > 0usize {
            out[n] = TableHit { index: i, fields: matched[0usize..mn] }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- where a search runs --------------------------------------------------------------------------------------

fn server_row_threshold() -> f64 { ret 1000.0f64 }

fn search_rpc() -> str { ret "search_table_rows" }

type SearchPlan = struct {
    mode: str,
    reason: str,
    table_id: str,
    has_table_id: bool,
    query: str,
    limit: f64,
    offset: f64,
    fuzzy: bool,
}

// Where an in-table search runs: nowhere for an empty query, in the browser for a fully loaded small table, else
// on the server (a partly loaded table is never searched client-side: it would report a confident wrong count).
fn plan_search(query: str, row_count: f64, has_row_count: bool, loaded_rows: f64, has_loaded: bool, table_id: str, limit: f64, has_limit: bool, offset: f64, has_offset: bool, fuzzy: bool) -> SearchPlan {
    let q = view.js_trim(query)
    var plan = SearchPlan { mode: "none", reason: "empty_query", table_id: "", has_table_id: false, query: "", limit: 0.0f64, offset: 0.0f64, fuzzy: false }
    if q.len == 0usize { ret plan }
    var rows = 0.0f64
    if has_row_count && row_count == row_count && row_count - row_count == 0.0f64 { rows = row_count }
    var loaded = rows
    if has_loaded && loaded_rows == loaded_rows && loaded_rows - loaded_rows == 0.0f64 { loaded = loaded_rows }
    let complete = loaded >= rows
    if complete && rows < server_row_threshold() {
        plan.mode = "client"
        plan.reason = "fully_loaded_small_table"
        ret plan
    }
    plan.mode = "server"
    if complete { plan.reason = "above_threshold" } else { plan.reason = "partially_loaded" }
    plan.query = q
    plan.table_id = table_id
    plan.has_table_id = table_id.len > 0usize
    plan.limit = 50.0f64
    if has_limit && limit == limit && limit - limit == 0.0f64 { plan.limit = limit }
    if has_offset && offset == offset && offset - offset == 0.0f64 { plan.offset = offset }
    plan.fuzzy = fuzzy
    ret plan
}

// --- the realm boundary ---------------------------------------------------------------------------------------

// A scope resolved to a realm id: bare text, trimmed; null, undefined, empty and white space are `realm-required`,
// anything that is not text is `realm-malformed`.
type Realm = struct { valid: bool, id: str, reason: str }

fn resolve_realm(v: f.Value, present: bool) -> Realm {
    if !present || v.kind == .Blank { ret Realm { valid: false, id: "", reason: "realm-required" } }
    if v.kind != .Text { ret Realm { valid: false, id: "", reason: "realm-malformed" } }
    let trimmed = view.js_trim(v.s)
    if trimmed.len == 0usize { ret Realm { valid: false, id: "", reason: "realm-required" } }
    ret Realm { valid: true, id: trimmed, reason: "" }
}

fn text_realm(s: str, present: bool) -> Realm { ret resolve_realm(f.text(s), present) }

// A document in the pipeline's index. `realm_id` is the realm field as supplied (text or absent); it is the only
// thing the boundary reads, never `tenant_id` (which holds an app id).
type IndexDoc = struct {
    id: str,
    kind: str,
    realm_id: str,
    has_realm: bool,
    tenant_id: str,
    title: str,
    text: str,
    fields: []const f.Field,
    has_fields: bool,
    table_id: str,
    key: str,
}

// The realm a document belongs to (trimmed), or none.
fn document_realm(d: IndexDoc) -> (str, bool) {
    if !d.has_realm { ret ("", false) }
    let t = view.js_trim(d.realm_id)
    if t.len == 0usize { ret ("", false) }
    ret (t, true)
}

fn in_realm(d: IndexDoc, realm: str) -> bool {
    if realm.len == 0usize { ret false }
    let (r, has) = document_realm(d)
    ret has && str.eq(r, realm)
}

type KindCount = struct { kind: str, count: usize }

type Counts = struct { total: usize, by_kind: []const KindCount, realm: str, has_realm: bool }

fn empty_counts() -> Counts {
    var none: []const KindCount = zero
    ret Counts { total: 0usize, by_kind: none, realm: "", has_realm: false }
}

fn count_docs(a: *mem.Arena, docs: []const IndexDoc, realm: str) -> Counts {
    if docs.len == 0usize { ret empty_counts() }
    let (kinds, e) = mem.alloc[KindCount](a, docs.len + 1usize)
    if e != ok { ret empty_counts() }
    var n = 0usize
    var i = 0usize
    while i < docs.len {
        var kind = docs[i].kind
        if kind.len == 0usize { kind = "unknown" }
        var found = false
        var k = 0usize
        while k < n {
            if str.eq(kinds[k].kind, kind) {
                kinds[k].count += 1usize
                found = true
            }
            k += 1usize
        }
        if !found {
            kinds[n] = KindCount { kind: kind, count: 1usize }
            n += 1usize
        }
        i += 1usize
    }
    ret Counts { total: docs.len, by_kind: kinds[0usize..n], realm: realm, has_realm: true }
}

// --- the incremental index ----------------------------------------------------------------------------------------

type Candidate = struct { id: str, title: str, kind: str, score: f64, key: str, table_id: str }

type Boost = fn(*void, IndexDoc) -> f64

type SearchIndex = struct {
    a: *mem.Arena,
    docs: []IndexDoc,
    count: usize,
    enforce_realm: bool,
    index_realm: str,
    has_index_realm: bool,
    upserts: usize,
    removals: usize,
    errors: usize,
}

fn new_index(a: *mem.Arena, capacity: usize, enforce_realm: bool, realm: str, has_realm: bool) -> SearchIndex {
    var none: []IndexDoc = zero
    let (docs, e) = mem.alloc[IndexDoc](a, capacity + 1usize)
    let r = text_realm(realm, has_realm)
    if e != ok { ret SearchIndex { a: a, docs: none, count: 0usize, enforce_realm: enforce_realm, index_realm: r.id, has_index_realm: r.valid, upserts: 0usize, removals: 0usize, errors: 0usize } }
    ret SearchIndex { a: a, docs: docs, count: 0usize, enforce_realm: enforce_realm, index_realm: r.id, has_index_realm: r.valid, upserts: 0usize, removals: 0usize, errors: 0usize }
}

fn find_doc(ix: *SearchIndex, id: str) -> usize {
    var i = 0usize
    while i < ix.count {
        if str.eq(ix.docs[i].id, id) { ret i }
        i += 1usize
    }
    ret ix.count
}

// Store a document (an existing id keeps its place); false when the index is full.
fn put_doc(ix: *SearchIndex, d: IndexDoc) -> bool {
    let at = find_doc(ix, d.id)
    if at < ix.count {
        ix.docs[at] = d
        ret true
    }
    if ix.count >= ix.docs.len { ret false }
    ix.docs[ix.count] = d
    ix.count += 1usize
    ret true
}

type Upsert = struct { valid: bool, reason: str }

// Add or replace one document. A strict index refuses an unstamped one at the door.
fn upsert(ix: *SearchIndex, d: IndexDoc) -> Upsert {
    if d.id.len == 0usize {
        ix.errors += 1usize
        ret Upsert { valid: false, reason: "doc id required" }
    }
    if ix.enforce_realm {
        let (r, has) = document_realm(d)
        if !has {
            ix.errors += 1usize
            ret Upsert { valid: false, reason: "realm-required" }
        }
    }
    if !put_doc(ix, d) {
        ix.errors += 1usize
        ret Upsert { valid: false, reason: "index full" }
    }
    ix.upserts += 1usize
    ret Upsert { valid: true, reason: "" }
}

type BatchUpsert = struct { upserted: usize, errors: usize, deduplicated: usize }

// Upsert many, the last entry of an id winning (the first one's place kept); refused entries are counted.
fn batch_upsert(ix: *SearchIndex, entries: []const IndexDoc) -> BatchUpsert {
    var ok_count = 0usize
    var errors = 0usize
    let (merged, me) = mem.alloc[IndexDoc](ix.a, entries.len + 1usize)
    if me != ok { ret BatchUpsert { upserted: 0usize, errors: entries.len, deduplicated: 0usize } }
    var mn = 0usize
    var i = 0usize
    while i < entries.len {
        let d = entries[i]
        i += 1usize
        if d.id.len == 0usize {
            errors += 1usize
            continue
        }
        if ix.enforce_realm {
            let (r, has) = document_realm(d)
            if !has {
                errors += 1usize
                continue
            }
        }
        var at = mn
        var k = 0usize
        while k < mn {
            if str.eq(merged[k].id, d.id) { at = k }
            k += 1usize
        }
        merged[at] = d
        if at == mn { mn += 1usize }
    }
    var j = 0usize
    while j < mn {
        if put_doc(ix, merged[j]) { ok_count += 1usize }
        j += 1usize
    }
    ix.upserts += ok_count
    ix.errors += errors
    ret BatchUpsert { upserted: ok_count, errors: errors, deduplicated: entries.len - ok_count - errors }
}

fn remove_at(ix: *SearchIndex, at: usize) {
    var i = at + 1usize
    while i < ix.count {
        ix.docs[i - 1usize] = ix.docs[i]
        i += 1usize
    }
    ix.count -= 1usize
}

fn remove(ix: *SearchIndex, id: str) {
    let at = find_doc(ix, id)
    if at < ix.count {
        remove_at(ix, at)
        ix.removals += 1usize
    }
}

fn batch_remove(ix: *SearchIndex, ids: []const str) -> usize {
    var removed = 0usize
    var i = 0usize
    while i < ids.len {
        let at = find_doc(ix, ids[i])
        if at < ix.count {
            remove_at(ix, at)
            removed += 1usize
        }
        i += 1usize
    }
    ix.removals += removed
    ret removed
}

fn doc_count(ix: *SearchIndex) -> usize { ret ix.count }

fn has_doc(ix: *SearchIndex, id: str) -> bool { ret find_doc(ix, id) < ix.count }

// How a query narrows and ranks: kinds, table, app (`tenant_id`), realm, the permission test and boost hooks.
type Query = struct {
    kinds: []const str,
    has_kinds: bool,
    table_id: str,
    tenant_id: str,
    realm: str,
    has_realm: bool,
    limit: usize,
    has_limit: bool,
    searchable: []const str,
    has_searchable: bool,
    skip: []const str,
    suggest_limit: usize,
}

type CanSee = fn(*void, IndexDoc) -> bool

// Rank an already narrowed candidate set (never the whole map): the title and text index, `limit * 2` from the
// search, the host's boost added, best first, then cut to `limit`.
fn rank(ix: *SearchIndex, candidates: []const IndexDoc, text: str, q: Query, boost: Boost, has_boost: bool, state: *void) -> []const Candidate {
    var none: []const Candidate = zero
    let a = ix.a
    let (entities, ee) = mem.alloc[Entity](a, candidates.len + 1usize)
    if ee != ok { ret none }
    var i = 0usize
    while i < candidates.len {
        let d = candidates[i]
        entities[i] = Entity { id: d.id, type_name: d.kind, title: d.title, text: d.text, fields: d.fields, has_fields: d.has_fields, app_id: "", table_id: d.table_id, namespace: "", key: d.key }
        i += 1usize
    }
    let index = build_index(a, entities[0usize..candidates.len], IndexOptions { searchable: q.searchable, has_searchable: q.has_searchable, skip: q.skip })
    var limit = 20usize
    if q.has_limit { limit = q.limit }
    let found = search(a, index, text, SearchOptions { limit: limit * 2usize, types: none_strings(), has_types: false, app_id: "", table_id: q.table_id, namespace: "" })
    let (out, oe) = mem.alloc[Candidate](a, found.results.len + 1usize)
    if oe != ok { ret none }
    var n = 0usize
    i = 0usize
    while i < found.results.len {
        let hit = found.results[i]
        var score = hit.score
        var key = ""
        var table_id = ""
        var kind = hit.entity.type_name
        var k = 0usize
        while k < candidates.len {
            if str.eq(candidates[k].id, hit.entity.id) {
                if has_boost {
                    let extra = boost(state, candidates[k])
                    if extra == extra && extra != 0.0f64 { score += extra }
                }
                key = candidates[k].key
                table_id = candidates[k].table_id
                kind = candidates[k].kind
            }
            k += 1usize
        }
        out[n] = Candidate { id: hit.entity.id, title: hit.entity.title, kind: kind, score: score, key: key, table_id: table_id }
        n += 1usize
        i += 1usize
    }
    // best score first; ties keep the title order
    var x = 1usize
    while x < n {
        let item = out[x]
        var y = x
        while y > 0usize && out[y - 1usize].score < item.score {
            out[y] = out[y - 1usize]
            y -= 1usize
        }
        out[y] = item
        x += 1usize
    }
    if limit < n { n = limit }
    ret out[0usize..n]
}

fn none_strings() -> []const str {
    var none: []const str = zero
    ret none
}

// Query with permission trimming before ranking truncation: realm scope (when strict, or when a realm is given),
// then app, kinds, table and `can_see`, then rank and cut. A strict index with no resolvable realm returns nothing.
fn query_docs(ix: *SearchIndex, text: str, q: Query, can_see: CanSee, has_can_see: bool, boost: Boost, has_boost: bool, state: *void) -> []const Candidate {
    var none: []const Candidate = zero
    let a = ix.a
    let (cand, ce) = mem.alloc[IndexDoc](a, ix.count + 1usize)
    if ce != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < ix.count {
        cand[n] = ix.docs[i]
        n += 1usize
        i += 1usize
    }
    var current = cand[0usize..n]
    if ix.enforce_realm {
        var realm = ix.index_realm
        var has = ix.has_index_realm
        if q.has_realm {
            let r = text_realm(q.realm, true)
            if r.valid {
                realm = r.id
                has = true
            } else if q.realm.len > 0usize {
                has = false
            }
        }
        if !has { ret none }
        current = scope_in_place(current, realm)
    } else if q.has_realm && q.realm.len > 0usize {
        let r = text_realm(q.realm, true)
        if !r.valid { ret none }
        current = scope_in_place(current, r.id)
    }
    current = narrow(current, q, can_see, has_can_see, state)
    ret rank(ix, current, text, q, boost, has_boost, state)
}

// The documents of a realm, compacted to the front of the same buffer.
fn scope_in_place(docs: []IndexDoc, realm: str) -> []IndexDoc {
    var n = 0usize
    var i = 0usize
    while i < docs.len {
        if in_realm(docs[i], realm) {
            docs[n] = docs[i]
            n += 1usize
        }
        i += 1usize
    }
    ret docs[0usize..n]
}

fn narrow(docs: []IndexDoc, q: Query, can_see: CanSee, has_can_see: bool, state: *void) -> []IndexDoc {
    var n = 0usize
    var i = 0usize
    while i < docs.len {
        var keep = true
        if q.tenant_id.len > 0usize && !str.eq(docs[i].tenant_id, q.tenant_id) { keep = false }
        if keep && q.has_kinds && !in_list(q.kinds, docs[i].kind) { keep = false }
        if keep && q.table_id.len > 0usize && !str.eq(docs[i].table_id, q.table_id) { keep = false }
        if keep && has_can_see && !can_see(state, docs[i]) { keep = false }
        if keep {
            docs[n] = docs[i]
            n += 1usize
        }
        i += 1usize
    }
    ret docs[0usize..n]
}

type Suggestion = struct { id: str, title: str, kind: str }

// The boundary's result: the list, its count, counts by kind from the same set, and suggestions from the top.
type Scoped = struct { results: []const Candidate, total: usize, counts: Counts, suggestions: []const Suggestion }

fn empty_scoped() -> Scoped {
    var none: []const Candidate = zero
    var no_suggestions: []const Suggestion = zero
    ret Scoped { results: none, total: 0usize, counts: empty_counts(), suggestions: no_suggestions }
}

// The fail-closed query: whatever the index was built with, an unresolvable realm returns the one empty shape,
// which is also what a miss returns. Counts and suggestions come from the results.
fn query_scoped(ix: *SearchIndex, text: str, q: Query, can_see: CanSee, has_can_see: bool, boost: Boost, has_boost: bool, state: *void) -> Scoped {
    let a = ix.a
    var realm = ix.index_realm
    var has = ix.has_index_realm
    if q.has_realm {
        let r = text_realm(q.realm, true)
        if r.valid {
            realm = r.id
            has = true
        } else if q.realm.len > 0usize {
            has = false
        }
    }
    if !has { ret empty_scoped() }
    let (cand, ce) = mem.alloc[IndexDoc](a, ix.count + 1usize)
    if ce != ok { ret empty_scoped() }
    var n = 0usize
    var i = 0usize
    while i < ix.count {
        cand[n] = ix.docs[i]
        n += 1usize
        i += 1usize
    }
    var scoped = scope_in_place(cand[0usize..n], realm)
    // the only filters `queryScoped` applies are kinds, table and `can_see`
    var local = q
    local.tenant_id = ""
    scoped = narrow(scoped, local, can_see, has_can_see, state)
    let ranked = rank(ix, scoped, text, q, boost, has_boost, state)
    var limit = 20usize
    if q.has_limit { limit = q.limit }
    // a result whose id the scoped set does not hold is dropped, then cut to the limit
    let (kept, ke) = mem.alloc[Candidate](a, ranked.len + 1usize)
    if ke != ok { ret empty_scoped() }
    var kn = 0usize
    i = 0usize
    while i < ranked.len {
        var allowed = false
        var k = 0usize
        while k < scoped.len {
            if str.eq(scoped[k].id, ranked[i].id) { allowed = true }
            k += 1usize
        }
        if allowed && kn < limit {
            kept[kn] = ranked[i]
            kn += 1usize
        }
        i += 1usize
    }
    if kn == 0usize { ret empty_scoped() }
    // counts of the results by kind
    let (kinds, ke2) = mem.alloc[KindCount](a, kn + 1usize)
    if ke2 != ok { ret empty_scoped() }
    var kinds_n = 0usize
    i = 0usize
    while i < kn {
        var kind = kept[i].kind
        if kind.len == 0usize { kind = "unknown" }
        var found = false
        var k = 0usize
        while k < kinds_n {
            if str.eq(kinds[k].kind, kind) {
                kinds[k].count += 1usize
                found = true
            }
            k += 1usize
        }
        if !found {
            kinds[kinds_n] = KindCount { kind: kind, count: 1usize }
            kinds_n += 1usize
        }
        i += 1usize
    }
    var suggest_limit = q.suggest_limit
    if suggest_limit == 0usize { suggest_limit = 10usize }
    var sn = kn
    if suggest_limit < sn { sn = suggest_limit }
    let (suggestions, se) = mem.alloc[Suggestion](a, sn + 1usize)
    if se != ok { ret empty_scoped() }
    i = 0usize
    while i < sn {
        suggestions[i] = Suggestion { id: kept[i].id, title: kept[i].title, kind: kept[i].kind }
        i += 1usize
    }
    ret Scoped { results: kept[0usize..kn], total: kn, counts: Counts { total: kn, by_kind: kinds[0usize..kinds_n], realm: realm, has_realm: true }, suggestions: suggestions[0usize..sn] }
}

type IndexStats = struct {
    document_count: usize,
    upserted: usize,
    removed: usize,
    errors: usize,
    by_kind: []const KindCount,
    by_tenant: []const KindCount,
}

// Counts for one realm, never a map of every realm.
fn scoped_stats(ix: *SearchIndex, realm: str, has_realm: bool) -> (Counts, usize, usize, usize) {
    let a = ix.a
    var r = ix.index_realm
    var has = ix.has_index_realm
    if has_realm && realm.len > 0usize {
        let t = text_realm(realm, true)
        r = t.id
        has = t.valid
    }
    if !has { ret (empty_counts(), ix.upserts, ix.removals, ix.errors) }
    let (cand, ce) = mem.alloc[IndexDoc](a, ix.count + 1usize)
    if ce != ok { ret (empty_counts(), ix.upserts, ix.removals, ix.errors) }
    var n = 0usize
    var i = 0usize
    while i < ix.count {
        if in_realm(ix.docs[i], r) {
            cand[n] = ix.docs[i]
            n += 1usize
        }
        i += 1usize
    }
    ret (count_docs(a, cand[0usize..n], r), ix.upserts, ix.removals, ix.errors)
}

// Forget everything.
fn clear(ix: *SearchIndex) { ix.count = 0usize }

type Dropped = struct { valid: bool, reason: str, removed: usize, unattributed: usize }

// Drop one realm's documents and every document with no realm (an index is a derived cache: losing a document that
// should have stayed costs a re-index, keeping one that should have gone costs a leak).
fn drop_realm_and_unattributed(ix: *SearchIndex, realm: str, has_realm: bool) -> Dropped {
    let r = text_realm(realm, has_realm)
    if !r.valid { ret Dropped { valid: false, reason: r.reason, removed: 0usize, unattributed: 0usize } }
    var removed = 0usize
    var unattributed = 0usize
    var kept = 0usize
    var i = 0usize
    while i < ix.count {
        let (owner, has_owner) = document_realm(ix.docs[i])
        var drop = !has_owner || str.eq(owner, r.id)
        if drop {
            removed += 1usize
            if !has_owner { unattributed += 1usize }
        } else {
            ix.docs[kept] = ix.docs[i]
            kept += 1usize
        }
        i += 1usize
    }
    ix.count = kept
    ret Dropped { valid: true, reason: "", removed: removed, unattributed: unattributed }
}

// The operator's whole-index snapshot: counts by kind and, on a non-strict index, by app (`tenant_id`).
fn stats(ix: *SearchIndex) -> IndexStats {
    let a = ix.a
    var none: []const KindCount = zero
    if ix.enforce_realm {
        let (counts, up, rem, errs) = scoped_stats(ix, "", false)
        ret IndexStats { document_count: counts.total, upserted: up, removed: rem, errors: errs, by_kind: counts.by_kind, by_tenant: none }
    }
    let (kinds, ke) = mem.alloc[KindCount](a, ix.count + 1usize)
    let (tenants, te) = mem.alloc[KindCount](a, ix.count + 1usize)
    if ke != ok || te != ok { ret IndexStats { document_count: ix.count, upserted: ix.upserts, removed: ix.removals, errors: ix.errors, by_kind: none, by_tenant: none } }
    var kn = 0usize
    var tn = 0usize
    var i = 0usize
    while i < ix.count {
        var found = false
        var k = 0usize
        while k < kn {
            if str.eq(kinds[k].kind, ix.docs[i].kind) {
                kinds[k].count += 1usize
                found = true
            }
            k += 1usize
        }
        if !found {
            kinds[kn] = KindCount { kind: ix.docs[i].kind, count: 1usize }
            kn += 1usize
        }
        if ix.docs[i].tenant_id.len > 0usize {
            var tfound = false
            var m = 0usize
            while m < tn {
                if str.eq(tenants[m].kind, ix.docs[i].tenant_id) {
                    tenants[m].count += 1usize
                    tfound = true
                }
                m += 1usize
            }
            if !tfound {
                tenants[tn] = KindCount { kind: ix.docs[i].tenant_id, count: 1usize }
                tn += 1usize
            }
        }
        i += 1usize
    }
    ret IndexStats { document_count: ix.count, upserted: ix.upserts, removed: ix.removals, errors: ix.errors, by_kind: kinds[0usize..kn], by_tenant: tenants[0usize..tn] }
}

// --- the outbox consumer ---------------------------------------------------------------------------------------

fn wedged_depth() -> usize { ret 1000usize }

fn wedged_age_min() -> f64 { ret 5.0f64 }

// A change event: its sequence number, the artifact it concerns, what happened, and when (empty when unknown).
type Event = struct { seq: f64, artifact_id: str, type_name: str, at: str, has_at: bool }

// What mapping an event to a document gave: nothing, a document, or a failure (the text of the thrown error).
type Mapped = struct { has_doc: bool, doc: IndexDoc, threw: bool, message: str }

type ToDocument = fn(*void, Event) -> Mapped

type DeadLetter = struct { seq: f64, artifact_id: str, message: str, at: str }

type Consumer = struct {
    a: *mem.Arena,
    cursor: f64,
    total_processed: usize,
    total_upserts: usize,
    total_removals: usize,
    last_drain_at: str,
    has_last_drain: bool,
    dead: []DeadLetter,
    dead_count: usize,
}

fn new_consumer(a: *mem.Arena, dead_capacity: usize) -> Consumer {
    var none: []DeadLetter = zero
    let (dead, e) = mem.alloc[DeadLetter](a, dead_capacity + 1usize)
    if e != ok { ret Consumer { a: a, cursor: 0.0f64, total_processed: 0usize, total_upserts: 0usize, total_removals: 0usize, last_drain_at: "", has_last_drain: false, dead: none, dead_count: 0usize } }
    ret Consumer { a: a, cursor: 0.0f64, total_processed: 0usize, total_upserts: 0usize, total_removals: 0usize, last_drain_at: "", has_last_drain: false, dead: dead, dead_count: 0usize }
}

type Drained = struct { processed: usize, upserts: usize, removals: usize, errors: usize, cursor: f64, dead_letters: []const DeadLetter }

fn is_removal(t: str) -> bool { ret str.eq(t, "trashed") || str.eq(t, "purged") }

// Apply one event: a removal removes, anything else upserts what `to_document` makes of it (a thrown failure is a
// dead letter). The index's own refusals do not count as consumer errors, as appdor's do not.
fn apply_event(c: *Consumer, ix: *SearchIndex, e: Event, to_document: ToDocument, state: *void, now_iso: str, upserts: *Counter) {
    if is_removal(e.type_name) {
        remove(ix, e.artifact_id)
        upserts.removals += 1usize
        ret
    }
    let m = to_document(state, e)
    if m.threw {
        if c.dead_count < c.dead.len {
            c.dead[c.dead_count] = DeadLetter { seq: e.seq, artifact_id: e.artifact_id, message: m.message, at: now_iso }
            c.dead_count += 1usize
        }
        upserts.errors += 1usize
        ret
    }
    if m.has_doc {
        let upserted = upsert(ix, m.doc)
        upserts.upserts += 1usize
    }
}

type Counter = struct { upserts: usize, removals: usize, errors: usize }

// Drain events past the cursor into the index; replaying a batch is a no-op. In batch mode with more than 100 fresh
// events the last event per artifact wins and the cursor still moves past all of them.
fn drain(c: *Consumer, ix: *SearchIndex, events: []const Event, batch_mode: bool, to_document: ToDocument, state: *void, now_iso: str) -> Drained {
    let a = c.a
    var none_dead: []const DeadLetter = zero
    let (fresh, fe) = mem.alloc[Event](a, events.len + 1usize)
    if fe != ok { ret Drained { processed: 0usize, upserts: 0usize, removals: 0usize, errors: 0usize, cursor: c.cursor, dead_letters: none_dead } }
    var fn_count = 0usize
    var i = 0usize
    while i < events.len {
        if events[i].seq > c.cursor {
            fresh[fn_count] = events[i]
            fn_count += 1usize
        }
        i += 1usize
    }
    var counter = Counter { upserts: 0usize, removals: 0usize, errors: 0usize }
    if batch_mode && fn_count > 100usize {
        // the newest event per artifact, in first-seen order
        let (picked, pe) = mem.alloc[Event](a, fn_count + 1usize)
        if pe != ok { ret Drained { processed: 0usize, upserts: 0usize, removals: 0usize, errors: 0usize, cursor: c.cursor, dead_letters: none_dead } }
        var pn = 0usize
        i = 0usize
        while i < fn_count {
            var at = pn
            var found = false
            var k = 0usize
            while k < pn && !found {
                if str.eq(picked[k].artifact_id, fresh[i].artifact_id) {
                    at = k
                    found = true
                }
                k += 1usize
            }
            if !found {
                picked[pn] = fresh[i]
                pn += 1usize
            } else if fresh[i].seq > picked[at].seq {
                picked[at] = fresh[i]
            }
            i += 1usize
        }
        i = 0usize
        while i < pn {
            apply_event(c, ix, picked[i], to_document, state, now_iso, &counter)
            i += 1usize
        }
        i = 0usize
        while i < fn_count {
            if fresh[i].seq > c.cursor { c.cursor = fresh[i].seq }
            i += 1usize
        }
    } else {
        i = 0usize
        while i < fn_count {
            apply_event(c, ix, fresh[i], to_document, state, now_iso, &counter)
            if fresh[i].seq > c.cursor { c.cursor = fresh[i].seq }
            i += 1usize
        }
    }
    c.total_processed += fn_count
    c.total_upserts += counter.upserts
    c.total_removals += counter.removals
    c.last_drain_at = now_iso
    c.has_last_drain = true
    var dead_view = none_dead
    if counter.errors > 0usize {
        var from = 0usize
        if c.dead_count > 10usize { from = c.dead_count - 10usize }
        dead_view = c.dead[from..c.dead_count]
    }
    ret Drained { processed: fn_count, upserts: counter.upserts, removals: counter.removals, errors: counter.errors, cursor: c.cursor, dead_letters: dead_view }
}

type Backlog = struct { depth: usize, oldest_seq: f64, oldest_at: str, has_oldest: bool, has_oldest_at: bool, cursor: f64 }

// How far behind the outbox is: the events past the cursor and the first of them.
fn backlog(c: *Consumer, outbox: []const Event) -> Backlog {
    var depth = 0usize
    var first = 0usize
    var have = false
    var i = 0usize
    while i < outbox.len {
        if outbox[i].seq > c.cursor {
            if !have {
                first = i
                have = true
            }
            depth += 1usize
        }
        i += 1usize
    }
    if !have { ret Backlog { depth: 0usize, oldest_seq: 0.0f64, oldest_at: "", has_oldest: false, has_oldest_at: false, cursor: c.cursor } }
    ret Backlog { depth: depth, oldest_seq: outbox[first].seq, oldest_at: outbox[first].at, has_oldest: true, has_oldest_at: outbox[first].has_at && outbox[first].at.len > 0usize, cursor: c.cursor }
}

type Wedged = struct { wedged: bool, reason: str }

// Wedged: a backlog over 1,000 deep, or the oldest pending event older than five minutes. The reasons are the
// catalogue keys humanized ("Backlog deep", "Oldest pending").
fn is_wedged(c: *Consumer, outbox: []const Event, now_ms: f64) -> Wedged {
    let b = backlog(c, outbox)
    if b.depth > wedged_depth() { ret Wedged { wedged: true, reason: "Backlog deep" } }
    if b.has_oldest_at {
        let (t, good) = f.parse_date_text(view.js_trim(b.oldest_at))
        if good && t == t {
            let age = now_ms - t
            if age > wedged_age_min() * 60.0f64 * 1000.0f64 { ret Wedged { wedged: true, reason: "Oldest pending" } }
        }
    }
    ret Wedged { wedged: false, reason: "" }
}

type ConsumerStats = struct {
    cursor: f64,
    total_processed: usize,
    total_upserts: usize,
    total_removals: usize,
    last_drain_at: str,
    has_last_drain: bool,
    dead_letter_count: usize,
    backlog: Backlog,
    wedged: Wedged,
}

fn consumer_stats(c: *Consumer, outbox: []const Event, now_ms: f64) -> ConsumerStats {
    ret ConsumerStats {
        cursor: c.cursor,
        total_processed: c.total_processed,
        total_upserts: c.total_upserts,
        total_removals: c.total_removals,
        last_drain_at: c.last_drain_at,
        has_last_drain: c.has_last_drain,
        dead_letter_count: c.dead_count,
        backlog: backlog(c, outbox),
        wedged: is_wedged(c, outbox, now_ms),
    }
}

// Clear dead letters so they can be re-processed.
fn clear_dead_letters(c: *Consumer) { c.dead_count = 0usize }

// --- recents and favorites ---------------------------------------------------------------------------------------

type Touch = struct { id: str, at: str }

type UserRecents = struct { user: str, items: []Touch, count: usize }

type UserFavorites = struct { user: str, ids: []str, count: usize }

type Recents = struct {
    a: *mem.Arena,
    limit: usize,
    users: []UserRecents,
    user_count: usize,
    favs: []UserFavorites,
    fav_count: usize,
}

fn new_recents(a: *mem.Arena, limit: usize, max_users: usize) -> Recents {
    var none_users: []UserRecents = zero
    var none_favs: []UserFavorites = zero
    let (users, ue) = mem.alloc[UserRecents](a, max_users + 1usize)
    let (favs, fe) = mem.alloc[UserFavorites](a, max_users + 1usize)
    var l = limit
    if l == 0usize { l = 50usize }
    if ue != ok || fe != ok { ret Recents { a: a, limit: l, users: none_users, user_count: 0usize, favs: none_favs, fav_count: 0usize } }
    ret Recents { a: a, limit: l, users: users, user_count: 0usize, favs: favs, fav_count: 0usize }
}

fn user_slot(r: *Recents, user: str) -> usize {
    var i = 0usize
    while i < r.user_count {
        if str.eq(r.users[i].user, user) { ret i }
        i += 1usize
    }
    if r.user_count >= r.users.len { ret r.users.len }
    let (items, e) = mem.alloc[Touch](r.a, r.limit + 2usize)
    if e != ok { ret r.users.len }
    r.users[r.user_count] = UserRecents { user: user, items: items, count: 0usize }
    r.user_count += 1usize
    ret r.user_count - 1usize
}

fn fav_slot(r: *Recents, user: str, create: bool) -> usize {
    var i = 0usize
    while i < r.fav_count {
        if str.eq(r.favs[i].user, user) { ret i }
        i += 1usize
    }
    if !create || r.fav_count >= r.favs.len { ret r.favs.len }
    let (ids, e) = mem.alloc[str](r.a, 256usize)
    if e != ok { ret r.favs.len }
    r.favs[r.fav_count] = UserFavorites { user: user, ids: ids, count: 0usize }
    r.fav_count += 1usize
    ret r.fav_count - 1usize
}

// Note that a user opened an artifact: it moves to the front, the list is cut to the limit.
fn touch(r: *Recents, user: str, id: str, at: str) {
    let slot = user_slot(r, user)
    if slot >= r.users.len { ret }
    var items = r.users[slot].items
    var n = 0usize
    var kept = 0usize
    while kept < r.users[slot].count {
        if !str.eq(items[kept].id, id) {
            items[n] = items[kept]
            n += 1usize
        }
        kept += 1usize
    }
    var i = n
    while i > 0usize {
        items[i] = items[i - 1usize]
        i -= 1usize
    }
    items[0usize] = Touch { id: id, at: at }
    n += 1usize
    if n > r.limit { n = r.limit }
    r.users[slot].count = n
}

fn recents_of(r: *Recents, user: str, n: usize) -> []const Touch {
    var none: []const Touch = zero
    var i = 0usize
    while i < r.user_count {
        if str.eq(r.users[i].user, user) {
            var shown = r.users[i].count
            if n < shown { shown = n }
            ret r.users[i].items[0usize..shown]
        }
        i += 1usize
    }
    ret none
}

fn favorite(r: *Recents, user: str, id: str) {
    let slot = fav_slot(r, user, true)
    if slot >= r.favs.len { ret }
    var i = 0usize
    while i < r.favs[slot].count {
        if str.eq(r.favs[slot].ids[i], id) { ret }
        i += 1usize
    }
    if r.favs[slot].count < r.favs[slot].ids.len {
        r.favs[slot].ids[r.favs[slot].count] = id
        r.favs[slot].count += 1usize
    }
}

fn unfavorite(r: *Recents, user: str, id: str) {
    let slot = fav_slot(r, user, false)
    if slot >= r.favs.len { ret }
    var n = 0usize
    var i = 0usize
    while i < r.favs[slot].count {
        if !str.eq(r.favs[slot].ids[i], id) {
            r.favs[slot].ids[n] = r.favs[slot].ids[i]
            n += 1usize
        }
        i += 1usize
    }
    r.favs[slot].count = n
}

fn is_favorite(r: *Recents, user: str, id: str) -> bool {
    let slot = fav_slot(r, user, false)
    if slot >= r.favs.len { ret false }
    var i = 0usize
    while i < r.favs[slot].count {
        if str.eq(r.favs[slot].ids[i], id) { ret true }
        i += 1usize
    }
    ret false
}

// The ranking boost for a user: +5 for a favorite, and `3 - 0.5 * position` (floored at 0) for a recent one. Pass
// the result's address as the state of `recents_boost`.
type BoostState = struct { recents: *Recents, user: str }

fn recents_boost(state: *void, d: IndexDoc) -> f64 {
    let s = mem.cast[*BoostState](state)
    var boost = 0.0f64
    if is_favorite(s.recents, s.user, d.id) { boost += 5.0f64 }
    let list = recents_of(s.recents, s.user, s.recents.limit)
    var i = 0usize
    while i < list.len {
        if str.eq(list[i].id, d.id) {
            var b = 3.0f64 - f64(i) * 0.5f64
            if b < 0.0f64 { b = 0.0f64 }
            boost += b
            ret boost
        }
        i += 1usize
    }
    ret boost
}

// Drop recents and favorites for artifacts the user can no longer see.
fn purge_for_user(r: *Recents, user: str, visible: []const str) {
    var i = 0usize
    while i < r.user_count {
        if str.eq(r.users[i].user, user) {
            var n = 0usize
            var k = 0usize
            while k < r.users[i].count {
                if in_list(visible, r.users[i].items[k].id) {
                    r.users[i].items[n] = r.users[i].items[k]
                    n += 1usize
                }
                k += 1usize
            }
            r.users[i].count = n
        }
        i += 1usize
    }
    let slot = fav_slot(r, user, false)
    if slot < r.favs.len {
        var n = 0usize
        var k = 0usize
        while k < r.favs[slot].count {
            if in_list(visible, r.favs[slot].ids[k]) {
                r.favs[slot].ids[n] = r.favs[slot].ids[k]
                n += 1usize
            }
            k += 1usize
        }
        r.favs[slot].count = n
    }
}
