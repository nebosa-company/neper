// Elasticsearch REST codecs (L114): the pieces of a client that are not sockets. Request side: `path` and `query`
// percent-encode as elasticsearch-py does (`urllib.parse.quote` with `,` and `*` safe), `bulk_meta` and `bulk_line`
// write the NDJSON action and source lines of the `_bulk` API with the metadata keys in the driver's order. Response
// side: `parse_bulk`, `parse_search` and `parse_error` read the documented response shapes into plain structs over
// `e.fmt.json`. The caller owns HTTP (`e.net.http` or `http.pool_request`), headers (`Content-Type:
// application/x-ndjson` for bulk) and retry policy. Cluster sniffing, scroll management and the typed query DSL are
// the caller's.
//
// Memory: encoders write into the caller's buffer; parsers allocate their tree and result arrays from the arena.
use e.fmt.json as json
use e.mem
use e.str

error TooSmall
error Invalid

// A bulk action's metadata. Integer fields use -1 for "absent"; empty strings are absent.
type Meta = struct { id: str, index: str, if_seq_no: i64, if_primary_term: i64, retry_on_conflict: i64, routing: str, version: i64, version_type: str, pipeline: str }
type Param = struct { name: str, value: str }
type BulkItem = struct { op: str, index: str, id: str, status: i64, result: str, error_type: str, error_reason: str, version: i64 }
type BulkResult = struct { took: i64, errors: bool, items: []const BulkItem }
type Hit = struct { index: str, id: str, score: f64, has_score: bool, source: json.Value }
type SearchResult = struct { took: i64, timed_out: bool, total: i64, relation: str, hits: []const Hit, scroll_id: str, shards_failed: i64 }
type ErrorInfo = struct { status: i64, kind: str, reason: str, root_kind: str, root_reason: str }

fn meta() -> Meta {
    ret Meta { id: "", index: "", if_seq_no: -1i64, if_primary_term: -1i64, retry_on_conflict: -1i64, routing: "", version: -1i64, version_type: "", pipeline: "" }
}

// --- request -----------------------------------------------------------------------------------------------------

fn put_text(dst: []u8, at: *usize, text: str) -> err {
    if *at + text.len > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + text.len], text)
    *at += text.len
    ret ok
}

fn put_byte(dst: []u8, at: *usize, b: u8) -> err {
    if *at >= dst.len { ret TooSmall }
    dst[*at] = b
    *at += 1usize
    ret ok
}

fn hex_upper(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

fn plain(c: u8, safe: str) -> bool {
    if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) { ret true }
    if c == 95u8 || c == 46u8 || c == 45u8 || c == 126u8 { ret true }
    var i = 0usize
    while i < safe.len {
        if safe[i] == c { ret true }
        i += 1usize
    }
    ret false
}

// `urllib.parse.quote(value, safe)`: every byte outside the unreserved set and `safe` becomes `%XX`.
fn quote(dst: []u8, at: *usize, value: str, safe: str) -> err {
    var i = 0usize
    while i < value.len {
        let c = value[i]
        var e: err = ok
        if plain(c, safe) {
            e = put_byte(dst, at, c)
        } else {
            e = put_byte(dst, at, 37u8)
            if e != ok { ret e }
            e = put_byte(dst, at, hex_upper(c >> 4u8))
            if e != ok { ret e }
            e = put_byte(dst, at, hex_upper(c & 15u8))
        }
        if e != ok { ret e }
        i += 1usize
    }
    ret ok
}

// `/seg/seg`: each non-empty segment quoted (`,` and `*` stay literal, `/` does not), as `_make_path` does.
fn path(dst: []u8, segments: []const str) -> (usize, err) {
    var at = 0usize
    var i = 0usize
    while i < segments.len {
        if segments[i].len > 0usize {
            var e = put_byte(dst, &at, 47u8)
            if e != ok { ret (0usize, e) }
            e = quote(dst, &at, segments[i], ",*")
            if e != ok { ret (0usize, e) }
        }
        i += 1usize
    }
    if at == 0usize {
        let e = put_byte(dst, &at, 47u8)
        if e != ok { ret (0usize, e) }
    }
    ret (at, ok)
}

// `a=b&c=d` with values quoted as elasticsearch-py's `_quote_query` does (no leading `?`).
fn query(dst: []u8, params: []const Param) -> (usize, err) {
    var at = 0usize
    var i = 0usize
    while i < params.len {
        var e: err = ok
        if i > 0usize {
            e = put_byte(dst, &at, 38u8)
            if e != ok { ret (0usize, e) }
        }
        e = put_text(dst, &at, params[i].name)
        if e != ok { ret (0usize, e) }
        e = put_byte(dst, &at, 61u8)
        if e != ok { ret (0usize, e) }
        e = quote(dst, &at, params[i].value, ",*")
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    ret (at, ok)
}

fn put_decimal(dst: []u8, at: *usize, value: i64) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = u64(value)
    if v == 0u64 {
        digits[0usize] = 48u8
        n = 1usize
    }
    while v > 0u64 {
        digits[n] = 48u8 + u8(v % 10u64)
        v = v / 10u64
        n += 1usize
    }
    if *at + n > dst.len { ret TooSmall }
    var i = 0usize
    while i < n {
        dst[*at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    *at += n
    ret ok
}

// A JSON string as the driver's serializer writes it: `"` and `\` and control characters escaped, everything else
// (non-ASCII included) as UTF-8 bytes.
fn put_string(dst: []u8, at: *usize, value: str) -> err {
    var e = put_byte(dst, at, 34u8)
    if e != ok { ret e }
    var i = 0usize
    while i < value.len {
        let c = value[i]
        if c == 34u8 || c == 92u8 {
            e = put_byte(dst, at, 92u8)
            if e != ok { ret e }
            e = put_byte(dst, at, c)
        } else if c == 10u8 {
            e = put_text(dst, at, "\\n")
        } else if c == 13u8 {
            e = put_text(dst, at, "\\r")
        } else if c == 9u8 {
            e = put_text(dst, at, "\\t")
        } else if c == 8u8 {
            e = put_text(dst, at, "\\b")
        } else if c == 12u8 {
            e = put_text(dst, at, "\\f")
        } else if c < 32u8 {
            e = put_text(dst, at, "\\u00")
            if e != ok { ret e }
            e = put_byte(dst, at, 48u8 + (c >> 4u8))
            if e != ok { ret e }
            var low = c & 15u8
            if low < 10u8 {
                low = 48u8 + low
            } else {
                low = 87u8 + low
            }
            e = put_byte(dst, at, low)
        } else {
            e = put_byte(dst, at, c)
        }
        if e != ok { ret e }
        i += 1usize
    }
    ret put_byte(dst, at, 34u8)
}

fn put_key_string(dst: []u8, at: *usize, first: *bool, key: str, value: str) -> err {
    if value.len == 0usize { ret ok }
    if !*first {
        let c = put_byte(dst, at, 44u8)
        if c != ok { ret c }
    }
    *first = false
    var e = put_string(dst, at, key)
    if e != ok { ret e }
    e = put_byte(dst, at, 58u8)
    if e != ok { ret e }
    ret put_string(dst, at, value)
}

fn put_key_number(dst: []u8, at: *usize, first: *bool, key: str, value: i64) -> err {
    if value < 0i64 { ret ok }
    if !*first {
        let c = put_byte(dst, at, 44u8)
        if c != ok { ret c }
    }
    *first = false
    var e = put_string(dst, at, key)
    if e != ok { ret e }
    e = put_byte(dst, at, 58u8)
    if e != ok { ret e }
    ret put_decimal(dst, at, value)
}

// The action line (no newline): `{"<op>":{"_id":...,"_index":...}}` with the metadata in the driver's order
// (`_id`, `_index`, `if_seq_no`, `if_primary_term`, `retry_on_conflict`, `routing`, `version`, `version_type`,
// `pipeline`). `op` is index, create, update or delete.
fn bulk_meta(dst: []u8, op: str, m: *const Meta) -> (usize, err) {
    if !(str.eq(op, "index") || str.eq(op, "create") || str.eq(op, "update") || str.eq(op, "delete")) { ret (0usize, Invalid) }
    var at = 0usize
    var first = true
    var e = put_text(dst, &at, "{\"")
    if e != ok { ret (0usize, e) }
    e = put_text(dst, &at, op)
    if e != ok { ret (0usize, e) }
    e = put_text(dst, &at, "\":{")
    if e != ok { ret (0usize, e) }
    e = put_key_string(dst, &at, &first, "_id", m.id)
    if e != ok { ret (0usize, e) }
    e = put_key_string(dst, &at, &first, "_index", m.index)
    if e != ok { ret (0usize, e) }
    e = put_key_number(dst, &at, &first, "if_seq_no", m.if_seq_no)
    if e != ok { ret (0usize, e) }
    e = put_key_number(dst, &at, &first, "if_primary_term", m.if_primary_term)
    if e != ok { ret (0usize, e) }
    e = put_key_number(dst, &at, &first, "retry_on_conflict", m.retry_on_conflict)
    if e != ok { ret (0usize, e) }
    e = put_key_string(dst, &at, &first, "routing", m.routing)
    if e != ok { ret (0usize, e) }
    e = put_key_number(dst, &at, &first, "version", m.version)
    if e != ok { ret (0usize, e) }
    e = put_key_string(dst, &at, &first, "version_type", m.version_type)
    if e != ok { ret (0usize, e) }
    e = put_key_string(dst, &at, &first, "pipeline", m.pipeline)
    if e != ok { ret (0usize, e) }
    e = put_text(dst, &at, "}}")
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// One bulk entry: the action line, a newline, and (except for delete) the source on one line and a newline. The
// source is one JSON value the caller wrote without raw newlines.
fn bulk_line(dst: []u8, op: str, m: *const Meta, source: str) -> (usize, err) {
    let (n, e) = bulk_meta(dst, op, m)
    if e != ok { ret (0usize, e) }
    var at = n
    var e2 = put_byte(dst, &at, 10u8)
    if e2 != ok { ret (0usize, e2) }
    if str.eq(op, "delete") { ret (at, ok) }
    var i = 0usize
    while i < source.len {
        if source[i] == 10u8 || source[i] == 13u8 { ret (0usize, Invalid) }
        i += 1usize
    }
    if source.len == 0usize { ret (0usize, Invalid) }
    e2 = put_text(dst, &at, source)
    if e2 != ok { ret (0usize, e2) }
    e2 = put_byte(dst, &at, 10u8)
    if e2 != ok { ret (0usize, e2) }
    ret (at, ok)
}

// --- response ----------------------------------------------------------------------------------------------------

fn member(v: json.Value, key: str) -> (json.Value, bool) {
    switch v {
    case .Object as members:
        var i = 0usize
        while i < members.len {
            if str.eq(members[i].key, key) { ret (members[i].value, true) }
            i += 1usize
        }
    default:
        ret (v, false)
    }
    ret (v, false)
}

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = member(v, key)
    if !found { ret "" }
    switch x {
    case .String as s:
        ret s
    default:
        ret ""
    }
    ret ""
}

fn int_of(v: json.Value, key: str, fallback: i64) -> i64 {
    let (x, found) = member(v, key)
    if !found { ret fallback }
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        if e == ok { ret value }
        ret fallback
    default:
        ret fallback
    }
    ret fallback
}

fn bool_of(v: json.Value, key: str) -> bool {
    let (x, found) = member(v, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
    ret false
}

fn array_of(v: json.Value, key: str) -> ([]const json.Value, bool) {
    let (x, found) = member(v, key)
    var none: []const json.Value = zero
    if !found { ret (none, false) }
    switch x {
    case .Array as items:
        ret (items, true)
    default:
        ret (none, false)
    }
    ret (none, false)
}

fn options() -> json.Options {
    ret json.Options { allow_duplicate_keys: true, max_depth: 64u16 }
}

// A `_bulk` response: `took`, `errors` and each item (the operation name is the single key of the item object).
fn parse_bulk(a: *mem.Arena, body: str) -> (BulkResult, err) {
    var out: BulkResult = zero
    let (root, json_error) = json.parse(a, body, options())
    if json_error != ok { ret (out, Invalid) }
    let (items, has_items) = array_of(root, "items")
    if !has_items { ret (out, Invalid) }
    let (results, alloc_error) = mem.alloc[BulkItem](a, items.len)
    if alloc_error != ok { ret (out, alloc_error) }
    var i = 0usize
    while i < items.len {
        var item: BulkItem = zero
        switch items[i] {
        case .Object as wrapper:
            if wrapper.len != 1usize { ret (out, Invalid) }
            item.op = wrapper[0usize].key
            let body_value = wrapper[0usize].value
            item.index = text_of(body_value, "_index")
            item.id = text_of(body_value, "_id")
            item.status = int_of(body_value, "status", 0i64)
            item.result = text_of(body_value, "result")
            item.version = int_of(body_value, "_version", -1i64)
            let (failure, has_failure) = member(body_value, "error")
            if has_failure {
                item.error_type = text_of(failure, "type")
                item.error_reason = text_of(failure, "reason")
                switch failure {
                case .String as text:
                    item.error_reason = text
                default:
                    item.error_reason = item.error_reason
                }
            }
        default:
            ret (out, Invalid)
        }
        results[i] = item
        i += 1usize
    }
    out.took = int_of(root, "took", 0i64)
    out.errors = bool_of(root, "errors")
    out.items = results
    ret (out, ok)
}

// A `_search` (or scroll) response: counters, the total hit count (an object with `value`/`relation`, or a plain
// integer under `rest_total_hits_as_int`) and the hits with their sources left as JSON values.
fn parse_search(a: *mem.Arena, body: str) -> (SearchResult, err) {
    var out: SearchResult = zero
    let (root, json_error) = json.parse(a, body, options())
    if json_error != ok { ret (out, Invalid) }
    let (hits_object, has_hits) = member(root, "hits")
    if !has_hits { ret (out, Invalid) }
    let (list, has_list) = array_of(hits_object, "hits")
    if !has_list { ret (out, Invalid) }
    let (results, alloc_error) = mem.alloc[Hit](a, list.len)
    if alloc_error != ok { ret (out, alloc_error) }
    var i = 0usize
    while i < list.len {
        var hit: Hit = zero
        hit.index = text_of(list[i], "_index")
        hit.id = text_of(list[i], "_id")
        let (score, has_score) = member(list[i], "_score")
        switch score {
        case .Number as n:
            let (value, e) = json.number_f64(n)
            if e == ok {
                hit.score = value
                hit.has_score = true
            }
        default:
            hit.has_score = false
        }
        let (source, has_source) = member(list[i], "_source")
        if has_source { hit.source = source }
        results[i] = hit
        i += 1usize
    }
    let (total, has_total) = member(hits_object, "total")
    if has_total {
        switch total {
        case .Number as n:
            let (value, e) = json.number_i64(n)
            if e == ok { out.total = value }
            out.relation = "eq"
        case .Object as members:
            out.total = int_of(total, "value", 0i64)
            out.relation = text_of(total, "relation")
        default:
            out.total = 0i64
        }
    }
    out.took = int_of(root, "took", 0i64)
    out.timed_out = bool_of(root, "timed_out")
    out.scroll_id = text_of(root, "_scroll_id")
    let (shards, has_shards) = member(root, "_shards")
    if has_shards { out.shards_failed = int_of(shards, "failed", 0i64) }
    out.hits = results
    ret (out, ok)
}

// An error response: the newer `{"error":{"type":...,"reason":...,"root_cause":[...]},"status":N}` and the legacy
// `{"error":"text","status":N}` forms.
fn parse_error(a: *mem.Arena, body: str) -> (ErrorInfo, err) {
    var out: ErrorInfo = zero
    let (root, parse_failure) = json.parse(a, body, options())
    if parse_failure != ok { ret (out, Invalid) }
    let (failure, has_error) = member(root, "error")
    if !has_error { ret (out, Invalid) }
    out.status = int_of(root, "status", 0i64)
    switch failure {
    case .String as text:
        out.reason = text
    case .Object as members:
        out.kind = text_of(failure, "type")
        out.reason = text_of(failure, "reason")
        let (causes, has_causes) = array_of(failure, "root_cause")
        if has_causes && causes.len > 0usize {
            out.root_kind = text_of(causes[0usize], "type")
            out.root_reason = text_of(causes[0usize], "reason")
        }
    default:
        ret (out, Invalid)
    }
    ret (out, ok)
}
