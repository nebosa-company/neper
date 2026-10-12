// A SQL database as a sync source (L037), after appdor's `src/sync/sql-source.js`: the decisions made before and after a
// query runs, with nothing that touches a socket.
//
//   * which channel is a SQL one (`postgres:` and `postgresql:` URLs), the operator's host allowlist
//     (`SQL_SOURCE_HOSTS`: a comma- or space-separated list of hosts, each `host` or `host:port`, never a wildcard, a
//     range, a suffix or a credential), the verdict on a host and on a resolved address (loopback, this-network and
//     link-local refused unless that exact address is listed), and the connection a URL and a credential make (no
//     credential in the URL, a port, a database of at most 63 characters, an `sslmode`);
//   * the statements a pull sends: identifiers checked and quoted, an entity `schema.table` or `schema/table` (the
//     schema defaults to `public`), the table browse, the column list and the capped row select that fails the query
//     when the table is over the cap, and the read-only session settings;
//   * what comes back: credentials redacted from any text, a driver error as a reason code and a redacted detail, a
//     row's values normalised to what JSON carries, the entities and the columns an information schema answered.
//
// Values are JSON. A byte string is carried as its text; `sql_bytes_value` is the `\x...` form a driver's byte array
// takes. `Number(x)` is read for decimal text only (no hexadecimal or exponent forms).
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncjob as syncjob
use e.algo.writeback as wb
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

fn max_sql_rows() -> i64 { ret 500000i64 }

fn max_entities() -> i64 { ret 500i64 }

fn statement_timeout_ms() -> i64 { ret 15000i64 }

fn connect_timeout_ms() -> i64 { ret 10000i64 }

fn row_cap_sentinel() -> str { ret "sql-source-row-cap-exceeded" }

// --- helpers ---------------------------------------------------------------------------------------------------------

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 11u8 || c == 12u8 || c == 13u8 }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_letter(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn is_word(c: u8) -> bool { ret is_letter(c) || is_digit(c) || c == 95u8 }

fn lower(a: *mem.Arena, s: str) -> str { ret wb.lower_ascii(a, s) }

fn fail(a: *mem.Arena, reason: str) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(false))
    sync.put(&o, "reason", sync.text(reason))
    ret ir.obj_value(&o)
}

fn text_member(v: json.Value, key: str) -> str {
    let (s, found) = sync.member_text(v, key)
    if !found { ret "" }
    ret s
}

// `String(v || '')`.
fn string_or_empty(a: *mem.Arena, v: json.Value) -> str {
    if !ir.truthy(v) { ret "" }
    ret wb.js_string(a, v, true)
}

fn all_digits(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    while at < s.len {
        if !is_digit(s[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn digits_value(s: str) -> i64 {
    var n = 0i64
    var at = 0usize
    while at < s.len && at < 12usize {
        n = n * 10i64 + i64(s[at] - 48u8)
        at += 1usize
    }
    ret n
}

// Is this a port: no port, or 1..65535?
fn valid_port(has_port: bool, port: i64) -> bool { ret !has_port || (port > 0i64 && port <= 65535i64) }

// --- the channel -----------------------------------------------------------------------------------------------------

// The dialect a base URL names: `postgresql` for a `postgres:` or `postgresql:` scheme (any case), else none.
fn sql_dialect(a: *mem.Arena, base_url: str) -> (str, bool) {
    if base_url.len == 0usize || !is_letter(base_url[0]) { ret ("", false) }
    var at = 1usize
    while at < base_url.len && (is_letter(base_url[at]) || is_digit(base_url[at]) || base_url[at] == 43u8 || base_url[at] == 46u8 || base_url[at] == 45u8) { at += 1usize }
    if at >= base_url.len || base_url[at] != 58u8 { ret ("", false) }
    let scheme = lower(a, base_url[0usize..at])
    if str.eq(scheme, "postgres") || str.eq(scheme, "postgresql") { ret ("postgresql", true) }
    ret ("", false)
}

// Does this channel's `baseUrl` name a SQL source?
fn is_sql_channel(a: *mem.Arena, channel: json.Value) -> bool {
    if !ir.truthy(channel) { ret false }
    let (base, have) = sync.get(channel, "baseUrl")
    if !have || !ir.truthy(base) { ret false }
    let (dialect, found) = sql_dialect(a, wb.js_string(a, base, true))
    ret found
}

// --- the host allowlist ----------------------------------------------------------------------------------------------

// `host` lower-cased and trimmed, one leading `[` and one trailing `]` and a trailing `.` removed.
fn normalize_host(a: *mem.Arena, host: str) -> str {
    var s = lower(a, str.trim(host))
    if s.len > 0usize && s[0] == 91u8 { s = s[1usize..s.len] }
    if s.len > 0usize && s[s.len - 1usize] == 93u8 { s = s[0usize..s.len - 1usize] }
    if s.len > 0usize && s[s.len - 1usize] == 46u8 { s = s[0usize..s.len - 1usize] }
    ret s
}

fn valid_host(host: str) -> bool {
    if host.len == 0usize || host.len > 253usize { ret false }
    var at = 0usize
    while at < host.len {
        let c = host[at]
        if is_space(c) || c == 34u8 || c == 39u8 || c == 92u8 { ret false }
        at += 1usize
    }
    ret true
}

fn count_colons(s: str) -> usize {
    var n = 0usize
    var at = 0usize
    while at < s.len {
        if s[at] == 58u8 { n += 1usize }
        at += 1usize
    }
    ret n
}

// `{host, port}` of one lower-cased entry, port absent as null, or none when it is not a host or a host:port.
fn split_host_port(a: *mem.Arena, value: str) -> (str, i64, bool, bool) {
    if value.len > 0usize && value[0] == 91u8 {
        // `[host]` or `[host]:port` with one to five port digits; anything else is read as a plain entry below
        var close = 1usize
        while close < value.len && value[close] != 93u8 { close += 1usize }
        var shaped = close < value.len && close > 1usize
        var has_port = false
        var port = 0i64
        if shaped {
            let rest = value[close + 1usize..value.len]
            if rest.len > 0usize {
                let digits = rest[1usize..rest.len]
                if rest[0] != 58u8 || digits.len == 0usize || digits.len > 5usize || !all_digits(digits) {
                    shaped = false
                } else {
                    has_port = true
                    port = digits_value(digits)
                }
            }
        }
        if shaped {
            let inner = value[1usize..close]
            if valid_host(inner) && valid_port(has_port, port) { ret (normalize_host(a, inner), port, has_port, true) }
            ret ("", 0i64, false, false)
        }
    }
    let colons = count_colons(value)
    if colons > 1usize {
        if valid_host(value) { ret (normalize_host(a, value), 0i64, false, true) }
        ret ("", 0i64, false, false)
    }
    if colons == 1usize {
        let (host, port_text, found) = str.split_once(value, ":")
        // `Number("")` is 0, which is not a port; `Number` of other text is NaN or a non-decimal form
        if !all_digits(port_text) { ret ("", 0i64, false, false) }
        let port = digits_value(port_text)
        if valid_host(host) && valid_port(true, port) { ret (normalize_host(a, host), port, true, true) }
        ret ("", 0i64, false, false)
    }
    if valid_host(value) { ret (normalize_host(a, value), 0i64, false, true) }
    ret ("", 0i64, false, false)
}

fn refused_entry(a: *mem.Arena, value: str, message: str) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(false))
    sync.put(&o, "value", sync.text(value))
    sync.put(&o, "error", sync.text(message))
    ret ir.obj_value(&o)
}

fn is_wildcard(lowered: str) -> bool {
    if str.eq(lowered, "*") || str.eq(lowered, "**") || str.eq(lowered, "any") || str.eq(lowered, "all") { ret true }
    if str.eq(lowered, "0.0.0.0") || str.eq(lowered, "::") || str.eq(lowered, "0.0.0.0/0") || str.eq(lowered, "::/0") { ret true }
    ret false
}

// `{ok: true, entries: [{host, port, raw}]}` for the operator's list, or `{ok: false, value, error}` naming the first
// entry that is a wildcard, a range or URL, a suffix, carries a credential, or is not a host.
fn parse_sql_source_hosts(a: *mem.Arena, raw: str) -> json.Value {
    var entries = sync.empty_list(a)
    var seen_hosts = sync.empty_list(a)
    var at = 0usize
    while at < raw.len {
        // one token: up to a comma or whitespace
        while at < raw.len && (raw[at] == 44u8 || is_space(raw[at])) { at += 1usize }
        var end = at
        while end < raw.len && raw[end] != 44u8 && !is_space(raw[end]) { end += 1usize }
        if end == at { break }
        let value = raw[at..end]
        at = end
        let lowered = lower(a, value)
        if is_wildcard(lowered) || str.contains(lowered, "*") || str.contains(lowered, "?") {
            ret refused_entry(a, value, sync.cat(a, sync.cat(a, "SQL_SOURCE_HOSTS entry \"", value), "\" is a wildcard. List each host; there is no \"allow everything\" value."))
        }
        if str.contains(lowered, "/") {
            ret refused_entry(a, value, sync.cat(a, sync.cat(a, "SQL_SOURCE_HOSTS entry \"", value), "\" is a range or a URL. List each host by name or address, one per entry."))
        }
        if str.starts_with(lowered, ".") {
            ret refused_entry(a, value, sync.cat(a, sync.cat(a, "SQL_SOURCE_HOSTS entry \"", value), "\" is a suffix wildcard. Name each host in full."))
        }
        if str.contains(lowered, "@") {
            ret refused_entry(a, value, sync.cat(a, sync.cat(a, "SQL_SOURCE_HOSTS entry \"", value), "\" carries a credential. The password belongs in the connection, never in this variable."))
        }
        let (host, port, has_port, good) = split_host_port(a, lowered)
        if !good {
            ret refused_entry(a, value, sync.cat(a, sync.cat(a, "SQL_SOURCE_HOSTS entry \"", value), "\" is not a host or a host:port."))
        }
        var duplicate = false
        var k = 0usize
        while k < entries.len {
            let existing = entries.items[k]
            let same_host = str.eq(text_member(existing, "host"), host)
            let (p, have_p) = sync.get(existing, "port")
            let same_port = (has_port && have_p && !ir.is_null(p) && sync.count_value(existing, "port", -1i64) == port) || (!has_port && (!have_p || ir.is_null(p)))
            if same_host && same_port { duplicate = true }
            k += 1usize
        }
        if duplicate { continue }
        var entry = sync.obj(a)
        sync.put(&entry, "host", sync.text(host))
        if has_port { sync.put(&entry, "port", sync.number(a, port)) } else { sync.put(&entry, "port", .Null) }
        sync.put(&entry, "raw", sync.text(value))
        sync.push_value(&entries, ir.obj_value(&entry))
    }
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(true))
    sync.put(&o, "entries", json.Value{ Array: list.slice_const[json.Value](&entries) })
    ret ir.obj_value(&o)
}

// `{allowed, entry}` or `{allowed: false, reason}` for a host and port against the allowlist entries.
fn check_sql_host(a: *mem.Arena, host: str, port: json.Value, entries: []const json.Value) -> json.Value {
    var o = sync.obj(a)
    if entries.len == 0usize {
        sync.put(&o, "allowed", sync.flag(false))
        sync.put(&o, "reason", sync.text("sql-sources-not-configured"))
        ret ir.obj_value(&o)
    }
    let name = normalize_host(a, host)
    if name.len == 0usize {
        sync.put(&o, "allowed", sync.flag(false))
        sync.put(&o, "reason", sync.text("sql-source-no-host"))
        ret ir.obj_value(&o)
    }
    let given = syncjob.number_or(port, -1.0f64)
    var at = 0usize
    while at < entries.len {
        let entry = entries[at]
        at += 1usize
        if !str.eq(text_member(entry, "host"), name) { continue }
        let (entry_port, have_port) = sync.get(entry, "port")
        var matches = !have_port || ir.is_null(entry_port)
        if !matches {
            let wanted = syncjob.number_or(entry_port, -1.0f64)
            matches = wanted == given
        }
        if matches {
            sync.put(&o, "allowed", sync.flag(true))
            sync.put(&o, "entry", entry)
            ret ir.obj_value(&o)
        }
    }
    sync.put(&o, "allowed", sync.flag(false))
    sync.put(&o, "reason", sync.text("sql-host-not-allowed"))
    ret ir.obj_value(&o)
}

fn is_hex_digit(c: u8) -> bool { ret is_digit(c) || (c >= 97u8 && c <= 102u8) || (c >= 65u8 && c <= 70u8) }

fn hex_value(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c) - 48i64 }
    if c >= 97u8 && c <= 102u8 { ret i64(c) - 87i64 }
    ret i64(c) - 55i64
}

// The dotted IPv4 inside an IPv4-mapped IPv6 spelling (`::ffff:1.2.3.4` or `::ffff:7f00:1`), or none.
fn unmap_ipv4(a: *mem.Arena, address: str) -> (str, bool) {
    let lowered = lower(a, address)
    if !str.starts_with(lowered, "::ffff:") { ret ("", false) }
    let rest = lowered[7usize..lowered.len]
    if str.contains(rest, ".") {
        // \d{1,3}(\.\d{1,3}){3}
        var groups = 0usize
        var run = 0usize
        var at = 0usize
        while at <= rest.len {
            if at == rest.len || rest[at] == 46u8 {
                if run == 0usize || run > 3usize { ret ("", false) }
                groups += 1usize
                run = 0usize
            } else if is_digit(rest[at]) {
                run += 1usize
            } else {
                ret ("", false)
            }
            at += 1usize
        }
        if groups == 4usize { ret (rest, true) }
        ret ("", false)
    }
    let (high, low, found) = str.split_once(rest, ":")
    if !found || high.len == 0usize || high.len > 4usize || low.len == 0usize || low.len > 4usize { ret ("", false) }
    var packed = 0i64
    var at = 0usize
    while at < high.len {
        if !is_hex_digit(high[at]) { ret ("", false) }
        packed = packed * 16i64 + hex_value(high[at])
        at += 1usize
    }
    packed = packed * 65536i64
    var low_value = 0i64
    at = 0usize
    while at < low.len {
        if !is_hex_digit(low[at]) { ret ("", false) }
        low_value = low_value * 16i64 + hex_value(low[at])
        at += 1usize
    }
    packed = packed + low_value
    let b1 = (packed / 16777216i64) % 256i64
    let b2 = (packed / 65536i64) % 256i64
    let b3 = (packed / 256i64) % 256i64
    let b4 = packed % 256i64
    let text = sync.cat(a, sync.cat(a, sync.cat(a, js_int(a, b1), "."), sync.cat(a, js_int(a, b2), ".")), sync.cat(a, sync.cat(a, js_int(a, b3), "."), js_int(a, b4)))
    ret (text, true)
}

fn js_int(a: *mem.Arena, n: i64) -> str { ret wb.js_string(a, sync.number(a, n), true) }

// The verdict on a resolved address: listed exactly, or not loopback, this-network, link-local or unspecified (the
// IPv4-mapped spelling judged as the IPv4 it is).
fn check_sql_address(a: *mem.Arena, address: str, entries: []const json.Value) -> json.Value {
    var o = sync.obj(a)
    let value = normalize_host(a, address)
    if value.len == 0usize {
        sync.put(&o, "allowed", sync.flag(false))
        sync.put(&o, "reason", sync.text("sql-source-unresolved"))
        ret ir.obj_value(&o)
    }
    var at = 0usize
    while at < entries.len {
        if str.eq(text_member(entries[at], "host"), value) {
            sync.put(&o, "allowed", sync.flag(true))
            ret ir.obj_value(&o)
        }
        at += 1usize
    }
    let (mapped, is_mapped) = unmap_ipv4(a, value)
    // patterns in order; for each, the spellings in order
    var order = 0usize
    while order < 6usize {
        var s = 0usize
        while s < 2usize {
            var spelling = value
            var present = true
            if s == 1usize {
                spelling = mapped
                present = is_mapped
            }
            if present {
                var hit = false
                var why = ""
                if order == 0usize && str.starts_with(spelling, "127.") {
                    hit = true
                    why = "loopback"
                } else if order == 1usize && str.starts_with(spelling, "0.") {
                    hit = true
                    why = "this-network"
                } else if order == 2usize && str.starts_with(spelling, "169.254.") {
                    hit = true
                    why = "link-local"
                } else if order == 3usize && str.eq(spelling, "::1") {
                    hit = true
                    why = "loopback"
                } else if order == 4usize && str.eq(spelling, "::") {
                    hit = true
                    why = "unspecified"
                } else if order == 5usize && str.starts_with(spelling, "::ffff:127.") {
                    hit = true
                    why = "loopback"
                }
                if hit {
                    sync.put(&o, "allowed", sync.flag(false))
                    sync.put(&o, "reason", sync.text(sync.cat(a, "sql-address-", why)))
                    ret ir.obj_value(&o)
                }
            }
            s += 1usize
        }
        order += 1usize
    }
    sync.put(&o, "allowed", sync.flag(true))
    ret ir.obj_value(&o)
}

// --- the connection --------------------------------------------------------------------------------------------------

// The value of query parameter `name` in a query string (the first), decoded as `URLSearchParams` does.
fn query_param(a: *mem.Arena, query: str, name: str) -> (str, bool) {
    var at = 0usize
    while at <= query.len {
        var end = at
        while end < query.len && query[end] != 38u8 { end += 1usize }
        let pair = query[at..end]
        if pair.len > 0usize {
            let (k, v, found) = str.split_once(pair, "=")
            var key = pair
            var value = ""
            if found {
                key = k
                value = v
            }
            if str.eq(form_decode(a, key), name) { ret (form_decode(a, value), true) }
        }
        at = end + 1usize
    }
    ret ("", false)
}

fn form_decode(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 43u8 {
            out[n] = 32u8
            n += 1usize
            at += 1usize
        } else if c == 37u8 && at + 2usize < s.len + 0usize && is_hex_digit(s[at + 1usize]) && is_hex_digit(s[at + 2usize]) {
            out[n] = u8(hex_value(s[at + 1usize]) * 16i64 + hex_value(s[at + 2usize]))
            n += 1usize
            at += 3usize
        } else {
            out[n] = c
            n += 1usize
            at += 1usize
        }
    }
    ret out[0usize..n]
}

// `decodeURIComponent`; `ok` is false for a malformed escape.
fn uri_decode(a: *mem.Arena, s: str) -> (str, bool) {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret (s, false) }
    var n = 0usize
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 37u8 {
            if at + 2usize >= s.len + 0usize || !is_hex_digit(s[at + 1usize]) || !is_hex_digit(s[at + 2usize]) { ret ("", false) }
            out[n] = u8(hex_value(s[at + 1usize]) * 16i64 + hex_value(s[at + 2usize]))
            n += 1usize
            at += 3usize
        } else {
            out[n] = c
            n += 1usize
            at += 1usize
        }
    }
    ret (out[0usize..n], true)
}

// An opaque-host code point that `new URL` refuses.
fn forbidden_opaque(c: u8) -> bool {
    ret c <= 32u8 || c == 60u8 || c == 62u8 || c == 92u8 || c == 94u8 || c == 124u8 || c == 127u8
}

fn ssl_mode_value(a: *mem.Arena, mode: str) -> (json.Value, bool) {
    if str.eq(mode, "disable") { ret (sync.flag(false), true) }
    if str.eq(mode, "require") || str.eq(mode, "verify-full") {
        var o = sync.obj(a)
        sync.put(&o, "rejectUnauthorized", sync.flag(true))
        ret (ir.obj_value(&o), true)
    }
    if str.eq(mode, "no-verify") {
        var o = sync.obj(a)
        sync.put(&o, "rejectUnauthorized", sync.flag(false))
        ret (ir.obj_value(&o), true)
    }
    ret (.Null, false)
}

// `{ok: true, source: {dialect, host, port, database, user, password, ssl}}` or `{ok: false, reason}` from a base URL
// and a credential `{username|user, password}`. The URL carries no credential; the port defaults to 5432; `sslmode`
// defaults to `require`.
fn sql_source_from(a: *mem.Arena, base_url: json.Value, has_base: bool, auth: json.Value) -> json.Value {
    var text = ""
    if has_base && !ir.is_null(base_url) { text = wb.js_string(a, base_url, true) }
    let (dialect, is_sql) = sql_dialect(a, text)
    if !is_sql { ret fail(a, "sql-not-a-sql-source") }
    // scheme `:` then, for an authority, `//`
    let (colon, have_colon) = str.find(text, ":")
    var rest = text[colon + 1usize..text.len]
    // a fragment ends the URL
    let (before_fragment, after_fragment, has_fragment) = str.split_once(rest, "#")
    if has_fragment { rest = before_fragment }
    var query = ""
    var path_part = rest
    let (before_query, after_query, has_query) = str.split_once(rest, "?")
    if has_query {
        path_part = before_query
        query = after_query
    }
    var username = ""
    var password = ""
    var hostname = ""
    var port_text = ""
    var pathname = path_part
    if str.starts_with(path_part, "//") {
        let after = path_part[2usize..path_part.len]
        var end = 0usize
        while end < after.len && after[end] != 47u8 { end += 1usize }
        let authority = after[0usize..end]
        pathname = after[end..after.len]
        var hostport = authority
        var last_at = -1i64
        var k = 0usize
        while k < authority.len {
            if authority[k] == 64u8 { last_at = i64(k) }
            k += 1usize
        }
        if last_at >= 0i64 {
            let userinfo = authority[0usize..usize(last_at)]
            hostport = authority[usize(last_at) + 1usize..authority.len]
            let (u, p, found) = str.split_once(userinfo, ":")
            if found {
                username = u
                password = p
            } else {
                username = userinfo
            }
        }
        // host and port
        if hostport.len > 0usize && hostport[0] == 91u8 {
            var close = 1usize
            while close < hostport.len && hostport[close] != 93u8 { close += 1usize }
            if close >= hostport.len { ret fail(a, "sql-bad-dsn") }
            hostname = hostport[0usize..close + 1usize]
            let tail = hostport[close + 1usize..hostport.len]
            if tail.len > 0usize {
                if tail[0] != 58u8 { ret fail(a, "sql-bad-dsn") }
                port_text = tail[1usize..tail.len]
            }
        } else {
            let (h, p, found) = str.split_once(hostport, ":")
            if found {
                hostname = h
                port_text = p
            } else {
                hostname = hostport
            }
            var c = 0usize
            while c < hostname.len {
                if forbidden_opaque(hostname[c]) || hostname[c] == 91u8 || hostname[c] == 93u8 || hostname[c] == 58u8 { ret fail(a, "sql-bad-dsn") }
                c += 1usize
            }
        }
        if port_text.len > 0usize {
            if !all_digits(port_text) { ret fail(a, "sql-bad-dsn") }
            if digits_value(port_text) > 65535i64 { ret fail(a, "sql-bad-dsn") }
        }
    }
    if username.len > 0usize || password.len > 0usize { ret fail(a, "sql-credentials-in-url") }
    let host = normalize_host(a, hostname)
    if host.len == 0usize { ret fail(a, "sql-source-no-host") }
    var port = 5432i64
    if port_text.len > 0usize { port = digits_value(port_text) }
    if !valid_port(true, port) { ret fail(a, "sql-bad-port") }
    var raw_database = pathname
    if str.starts_with(raw_database, "/") { raw_database = raw_database[1usize..raw_database.len] }
    let (database, decoded) = uri_decode(a, raw_database)
    if !decoded { ret fail(a, "sql-bad-dsn") }
    var bad_database = database.len == 0usize || database.len > 63usize
    var d = 0usize
    while d < database.len {
        if is_space(database[d]) || database[d] == 0u8 { bad_database = true }
        d += 1usize
    }
    if bad_database { ret fail(a, "sql-bad-database") }
    let (given_mode, have_mode) = query_param(a, query, "sslmode")
    var mode = "require"
    if have_mode && given_mode.len > 0usize { mode = lower(a, given_mode) }
    let (ssl, mode_ok) = ssl_mode_value(a, mode)
    if !mode_ok { ret fail(a, "sql-bad-sslmode") }
    var credential = auth
    if !ir.truthy(auth) { credential = ir.empty_object() }
    let user = string_or_empty(a, ir.or_falsy(credential, "username", ir.or_falsy(credential, "user", sync.text(""))))
    let secret = string_or_empty(a, ir.value_of(credential, "password"))
    if user.len == 0usize { ret fail(a, "sql-no-credential") }
    var source = sync.obj(a)
    sync.put(&source, "dialect", sync.text(dialect))
    sync.put(&source, "host", sync.text(host))
    sync.put(&source, "port", sync.number(a, port))
    sync.put(&source, "database", sync.text(database))
    sync.put(&source, "user", sync.text(user))
    sync.put(&source, "password", sync.text(secret))
    sync.put(&source, "ssl", ssl)
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(true))
    sync.put(&o, "source", ir.obj_value(&source))
    ret ir.obj_value(&o)
}

// --- identifiers and statements --------------------------------------------------------------------------------------

// `^[A-Za-z_][A-Za-z0-9_$]{0,62}$`.
fn is_valid_sql_identifier(name: str) -> bool {
    if name.len == 0usize || name.len > 63usize { ret false }
    if !(is_letter(name[0]) || name[0] == 95u8) { ret false }
    var at = 1usize
    while at < name.len {
        if !(is_word(name[at]) || name[at] == 36u8) { ret false }
        at += 1usize
    }
    ret true
}

// The identifier in double quotes, or none when it is not valid.
fn quote_sql_identifier(a: *mem.Arena, name: str) -> (str, bool) {
    if !is_valid_sql_identifier(name) { ret ("", false) }
    ret (sync.cat(a, sync.cat(a, "\"", name), "\""), true)
}

fn trim_slashes(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && s[from] == 47u8 { from += 1usize }
    while to > from && s[to - 1usize] == 47u8 { to -= 1usize }
    ret s[from..to]
}

// `{ok: true, schema, table}` for `table`, `schema.table` or `schema/table`, or `{ok: false, reason}`.
fn parse_sql_entity(a: *mem.Arena, entity: str) -> json.Value {
    let raw = trim_slashes(str.trim(entity))
    if raw.len == 0usize { ret fail(a, "sql-no-entity") }
    var separator = "."
    if str.contains(raw, "/") { separator = "/" }
    var parts: [3]str = zero
    var count = 0usize
    var start = 0usize
    var at = 0usize
    while at <= raw.len {
        if at == raw.len || raw[at] == separator[0] {
            if count < 3usize { parts[count] = raw[start..at] }
            count += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    if count > 2usize { ret fail(a, "sql-bad-identifier") }
    var schema = "public"
    var table = parts[0]
    if count == 2usize {
        schema = parts[0]
        table = parts[1]
    }
    if !is_valid_sql_identifier(schema) || !is_valid_sql_identifier(table) { ret fail(a, "sql-bad-identifier") }
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(true))
    sync.put(&o, "schema", sync.text(schema))
    sync.put(&o, "table", sync.text(table))
    ret ir.obj_value(&o)
}

fn sql_entity_name(a: *mem.Arena, schema: str, table: str) -> str { ret sync.cat(a, sync.cat(a, schema, "."), table) }

// `Math.max(low, Math.min(Number(v) || fallback, high))`.
fn clamp_limit(a: *mem.Arena, v: json.Value, fallback: i64, high: i64) -> json.Value {
    var x = syncjob.number_or(v, f64(fallback))
    if x > f64(high) { x = f64(high) }
    if x < 1.0f64 { x = 1.0f64 }
    ret syncjob.number_value(a, x)
}

fn statement(a: *mem.Arena, text: str, values: []const json.Value) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "text", sync.text(text))
    sync.put(&o, "values", json.Value{ Array: values })
    ret ir.obj_value(&o)
}

fn values_of(a: *mem.Arena, first: json.Value, second: json.Value, third: json.Value, count: usize) -> []const json.Value {
    var l = sync.empty_list(a)
    if count > 0usize { sync.push_value(&l, first) }
    if count > 1usize { sync.push_value(&l, second) }
    if count > 2usize { sync.push_value(&l, third) }
    ret list.slice_const[json.Value](&l)
}

// The statement that lists the tables and views outside the system schemas, capped at `limit` (at most 500).
fn browse_tables_statement(a: *mem.Arena, limit: json.Value) -> json.Value {
    let text = "SELECT table_schema, table_name, table_type\n             FROM information_schema.tables\n            WHERE table_schema NOT IN ($1, $2)\n              AND table_type IN ('BASE TABLE', 'VIEW')\n            ORDER BY table_schema, table_name\n            LIMIT $3"
    ret statement(a, text, values_of(a, sync.text("pg_catalog"), sync.text("information_schema"), clamp_limit(a, limit, max_entities(), max_entities()), 3usize))
}

// The statement that lists a table's columns in order.
fn columns_statement(a: *mem.Arena, schema: json.Value, table: json.Value) -> json.Value {
    let text = "SELECT column_name, data_type, is_nullable\n             FROM information_schema.columns\n            WHERE table_schema = $1 AND table_name = $2\n            ORDER BY ordinal_position"
    ret statement(a, text, values_of(a, schema, table, .Null, 2usize))
}

// The row select: under the cap a plain `LIMIT`, at the cap a probe that fails the query when the table holds more.
// `ok` is false when the schema or table is not a valid identifier.
fn select_rows_statement(a: *mem.Arena, schema: str, table: str, limit: json.Value) -> (json.Value, bool) {
    let (q_schema, schema_ok) = quote_sql_identifier(a, schema)
    let (q_table, table_ok) = quote_sql_identifier(a, table)
    if !schema_ok || !table_ok { ret (.Null, false) }
    let relation = sync.cat(a, sync.cat(a, q_schema, "."), q_table)
    let cap = clamp_limit(a, limit, max_sql_rows(), max_sql_rows())
    var cap_value = syncjob.number_or(cap, 1.0f64)
    var text = ""
    if cap_value < f64(max_sql_rows()) {
        text = sync.cat(a, sync.cat(a, "SELECT * FROM ", relation), " LIMIT $1")
    } else {
        text = sync.cat(a, "SELECT * FROM ", relation)
        text = sync.cat(a, text, " WHERE (SELECT CASE WHEN count(*) > $1 THEN CAST('")
        text = sync.cat(a, text, row_cap_sentinel())
        text = sync.cat(a, text, ":' || count(*) AS int) ELSE 1 END FROM (SELECT 1 FROM ")
        text = sync.cat(a, text, relation)
        text = sync.cat(a, text, " LIMIT $1 + 1) probe) = 1 LIMIT $1")
    }
    ret (statement(a, text, values_of(a, cap, .Null, .Null, 1usize)), true)
}

// The statements that make a session read-only with a statement timeout of `timeout_ms` (1 second to 10 minutes).
fn read_only_session_statements(a: *mem.Arena, timeout_ms: json.Value) -> json.Value {
    let ms = clamp_ms(timeout_ms)
    var l = sync.empty_list(a)
    sync.push_value(&l, sync.text("SET default_transaction_read_only = on"))
    sync.push_value(&l, sync.text(sync.cat(a, "SET statement_timeout = ", js_int(a, ms))))
    sync.push_value(&l, sync.text(sync.cat(a, "SET idle_in_transaction_session_timeout = ", js_int(a, ms))))
    ret json.Value{ Array: list.slice_const[json.Value](&l) }
}

fn clamp_ms(v: json.Value) -> i64 {
    var x = syncjob.number_or(v, f64(statement_timeout_ms()))
    if x > 600000.0f64 { x = 600000.0f64 }
    if x < 1000.0f64 { x = 1000.0f64 }
    ret i64(x)
}

// --- redaction and diagnostics ---------------------------------------------------------------------------------------

// `scheme://user:pass@` becomes `scheme://user:***@` wherever it stands.
fn redact_urls(a: *mem.Arena, s: str) -> str {
    let (b, e) = str.builder(a, s.len + 32usize)
    if e != ok { ret s }
    var out = b
    var i = 0usize
    while i < s.len {
        var matched = false
        var end = 0usize
        var group_start = 0usize
        var group_end = 0usize
        var scheme_end = 0usize
        if is_letter(s[i]) && (i == 0usize || !is_word(s[i - 1usize])) {
            var j = i + 1usize
            while j < s.len && (is_letter(s[j]) || is_digit(s[j]) || s[j] == 43u8 || s[j] == 46u8 || s[j] == 45u8) { j += 1usize }
            if j + 2usize < s.len + 0usize && s[j] == 58u8 && s[j + 1usize] == 47u8 && s[j + 2usize] == 47u8 {
                let p = j + 3usize
                var q = p
                while q < s.len && !is_space(s[q]) && s[q] != 58u8 && s[q] != 64u8 && s[q] != 47u8 { q += 1usize }
                if q < s.len && s[q] == 64u8 {
                    matched = true
                    end = q + 1usize
                    group_start = p
                    group_end = q
                    scheme_end = p
                } else if q < s.len && s[q] == 58u8 {
                    var r = q + 1usize
                    while r < s.len && !is_space(s[r]) && s[r] != 64u8 && s[r] != 47u8 { r += 1usize }
                    if r < s.len && s[r] == 64u8 {
                        matched = true
                        end = r + 1usize
                        group_start = p
                        group_end = q
                        scheme_end = p
                    }
                }
            }
        }
        if matched {
            let p1 = str.push(&out, s[i..scheme_end])
            let p2 = str.push(&out, s[group_start..group_end])
            let p3 = str.push(&out, ":***@")
            i = end
        } else {
            let pushed = str.push_byte(&out, s[i])
            i += 1usize
        }
    }
    ret str.done(&out)
}

fn lower_eq_at(a: *mem.Arena, s: str, at: usize, word: str) -> bool {
    if at + word.len > s.len { ret false }
    var k = 0usize
    while k < word.len {
        var c = s[at + k]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c != word[k] { ret false }
        k += 1usize
    }
    ret true
}

// `password=`, `passfile=` and `pgpassword=` (any case) followed by a quoted or bare value become `name=***`.
fn redact_keywords(a: *mem.Arena, s: str) -> str {
    let (b, e) = str.builder(a, s.len + 16usize)
    if e != ok { ret s }
    var out = b
    var i = 0usize
    while i < s.len {
        var matched = false
        var name_len = 0usize
        var end = 0usize
        if i == 0usize || !is_word(s[i - 1usize]) {
            if lower_eq_at(a, s, i, "password") {
                name_len = 8usize
            } else if lower_eq_at(a, s, i, "passfile") {
                name_len = 8usize
            } else if lower_eq_at(a, s, i, "pgpassword") {
                name_len = 10usize
            }
            if name_len > 0usize {
                var k = i + name_len
                while k < s.len && is_space(s[k]) { k += 1usize }
                if k < s.len && s[k] == 61u8 {
                    k += 1usize
                    while k < s.len && is_space(s[k]) { k += 1usize }
                    if k < s.len {
                        var closed = false
                        if s[k] == 34u8 || s[k] == 39u8 {
                            var m = k + 1usize
                            while m < s.len && s[m] != s[k] { m += 1usize }
                            if m < s.len {
                                closed = true
                                matched = true
                                end = m + 1usize
                            }
                        }
                        if !closed && !is_space(s[k]) {
                            var m = k
                            while m < s.len && !is_space(s[m]) { m += 1usize }
                            matched = true
                            end = m
                        }
                    }
                }
            }
        }
        if matched {
            let p1 = str.push(&out, s[i..i + name_len])
            let p2 = str.push(&out, "=***")
            i = end
        } else {
            let pushed = str.push_byte(&out, s[i])
            i += 1usize
        }
    }
    ret str.done(&out)
}

fn replace_all(a: *mem.Arena, s: str, needle: str, with: str) -> str {
    let (b, e) = str.builder(a, s.len + 16usize)
    if e != ok { ret s }
    var out = b
    var i = 0usize
    while i < s.len {
        if i + needle.len <= s.len && str.eq(s[i..i + needle.len], needle) {
            let p = str.push(&out, with)
            i += needle.len
        } else {
            let pushed = str.push_byte(&out, s[i])
            i += 1usize
        }
    }
    ret str.done(&out)
}

// `text` with URL passwords, `password=` style settings and every listed secret replaced by `***`. A secret shorter
// than three characters is not searched for piecemeal: when it occurs at all the whole text becomes `***`.
fn redact_sql_text(a: *mem.Arena, text: str, secrets: []const json.Value) -> str {
    var out = redact_keywords(a, redact_urls(a, text))
    var at = 0usize
    while at < secrets.len {
        var value = ""
        if !ir.is_null(secrets[at]) { value = wb.js_string(a, secrets[at], true) }
        at += 1usize
        if value.len >= 3usize {
            out = replace_all(a, out, value, "***")
        } else if value.len > 0usize && str.contains(out, value) {
            out = "***"
        }
    }
    ret out
}

fn reason_for_code(code: str) -> (str, bool) {
    if str.eq(code, "28P01") || str.eq(code, "28000") { ret ("sql-auth-failed", true) }
    if str.eq(code, "42501") { ret ("sql-permission-denied", true) }
    if str.eq(code, "42P01") || str.eq(code, "3F000") { ret ("sql-entity-not-found", true) }
    if str.eq(code, "3D000") { ret ("sql-database-not-found", true) }
    if str.eq(code, "57014") || str.eq(code, "ETIMEDOUT") { ret ("sql-timeout", true) }
    if str.eq(code, "53300") { ret ("sql-source-too-busy", true) }
    if str.eq(code, "25006") { ret ("sql-read-only", true) }
    if str.eq(code, "ECONNREFUSED") || str.eq(code, "ENOTFOUND") || str.eq(code, "EAI_AGAIN") || str.eq(code, "ECONNRESET") || str.eq(code, "EHOSTUNREACH") || str.eq(code, "ENETUNREACH") { ret ("sql-unreachable", true) }
    if str.eq(code, "CERT_HAS_EXPIRED") || str.eq(code, "DEPTH_ZERO_SELF_SIGNED_CERT") || str.eq(code, "SELF_SIGNED_CERT_IN_CHAIN") || str.eq(code, "ERR_TLS_CERT_ALTNAME_INVALID") { ret ("sql-tls-failed", true) }
    ret ("", false)
}

// Does `s` contain `needle`, ignoring ASCII case?
fn contains_fold(a: *mem.Arena, s: str, needle: str) -> bool { ret str.contains(lower(a, s), lower(a, needle)) }

fn reason_from_message(a: *mem.Arena, detail: str) -> str {
    if str.contains(detail, row_cap_sentinel()) { ret "sql-source-too-large" }
    if contains_fold(a, detail, "does not support SSL") || contains_fold(a, detail, "SSL connection") { ret "sql-tls-failed" }
    if contains_fold(a, detail, "timeout") || contains_fold(a, detail, "timed out") { ret "sql-timeout" }
    ret "sql-failed"
}

// `{reason, detail}` for a driver error `{code?, message?}`: the reason code of its SQLSTATE or system code, else of its
// message; the detail is the message redacted and cut to 400 characters.
fn sql_diagnostic(a: *mem.Arena, error_value: json.Value, secrets: []const json.Value) -> json.Value {
    var code = ""
    if ir.truthy(error_value) {
        let own = ir.value_of(error_value, "code")
        if ir.truthy(own) { code = wb.js_string(a, own, true) }
    }
    var message = "sql error"
    if ir.truthy(error_value) {
        let own_message = ir.value_of(error_value, "message")
        if ir.truthy(own_message) { message = wb.js_string(a, own_message, true) }
    }
    var detail = redact_sql_text(a, message, secrets)
    if detail.len > 400usize { detail = detail[0usize..400usize] }
    var reason = ""
    let (known, found) = reason_for_code(code)
    if found { reason = known } else { reason = reason_from_message(a, detail) }
    var o = sync.obj(a)
    sync.put(&o, "reason", sync.text(reason))
    sync.put(&o, "detail", sync.text(detail))
    ret ir.obj_value(&o)
}

// --- rows ------------------------------------------------------------------------------------------------------------

// A JSON value as a driver row cell is stored: null stays null, a container becomes its JSON text, a scalar is itself.
fn normalize_sql_value(a: *mem.Arena, value: json.Value) -> json.Value {
    switch value {
    case .Array as xs:
        ret sync.text(syncjob.plain(a, value))
    case .Object as ms:
        ret sync.text(syncjob.plain(a, value))
    default:
        ret value
    }
}

fn hex_char(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 87u8 + n
}

// A driver byte array as `\x` and its lower-case hex.
fn sql_bytes_value(a: *mem.Arena, data: []const u8) -> str {
    let (b, e) = str.builder(a, data.len * 2usize + 4usize)
    if e != ok { ret "" }
    var out = b
    let p = str.push(&out, "\\x")
    var at = 0usize
    while at < data.len {
        let hi = str.push_byte(&out, hex_char(data[at] / 16u8))
        let lo = str.push_byte(&out, hex_char(data[at] % 16u8))
        at += 1usize
    }
    ret str.done(&out)
}

// A row with every cell normalised.
fn normalize_sql_row(a: *mem.Arena, row: json.Value) -> json.Value {
    var o = sync.obj(a)
    let (members, is_object) = ir.members_of(row)
    var at = 0usize
    while at < members.len {
        sync.put(&o, members[at].key, normalize_sql_value(a, members[at].value))
        at += 1usize
    }
    ret ir.obj_value(&o)
}

// `row[first] ?? row[second]`.
fn either(row: json.Value, first: str, second: str) -> json.Value {
    let (x, found) = sync.get(row, first)
    if found && !ir.is_null(x) { ret x }
    ret ir.value_of(row, second)
}

// The entities a table list answered: `{path: "schema.table", name, source: "source"}`, at most 500.
fn sql_entities(a: *mem.Arena, rows: []const json.Value) -> json.Value {
    var out = sync.empty_list(a)
    var at = 0usize
    while at < rows.len {
        let schema = either(rows[at], "table_schema", "tableSchema")
        let table = either(rows[at], "table_name", "tableName")
        at += 1usize
        if !ir.truthy(schema) || !ir.truthy(table) { continue }
        let path = sql_entity_name(a, wb.js_string(a, schema, true), wb.js_string(a, table, true))
        var entity = sync.obj(a)
        sync.put(&entity, "path", sync.text(path))
        sync.put(&entity, "name", sync.text(path))
        sync.put(&entity, "source", sync.text("source"))
        sync.push_value(&out, ir.obj_value(&entity))
        if i64(out.len) >= max_entities() { break }
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// The columns an information schema answered: `{name, nativeType}` with the type lower-cased (`text` when absent).
fn sql_columns(a: *mem.Arena, rows: []const json.Value) -> json.Value {
    var out = sync.empty_list(a)
    var at = 0usize
    while at < rows.len {
        let name = either(rows[at], "column_name", "columnName")
        let kind = either(rows[at], "data_type", "dataType")
        at += 1usize
        if !ir.truthy(name) { continue }
        var native = "text"
        if ir.truthy(kind) { native = wb.js_string(a, kind, true) }
        var column = sync.obj(a)
        sync.put(&column, "name", sync.text(wb.js_string(a, name, true)))
        sync.put(&column, "nativeType", sync.text(lower(a, native)))
        sync.push_value(&out, ir.obj_value(&column))
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}
