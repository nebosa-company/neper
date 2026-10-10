// The external change contract (T042, H35): a machine-readable request that lives outside the source, content-addressed
// so a plan, a bundle and a receipt can bind to exactly what was asked. A contract is a JSON document with a base
// snapshot, an inert objective and provenance, a permitted and a forbidden scope, executable obligations (each
// required or advisory) and the verification tier the change needs. `parse` validates it fail-closed (an unknown key,
// a wrong kind, a duplicate obligation id or a non-integer number is `Invalid`), `canonical` is its one byte-exact
// serialization (object keys in byte order, no whitespace, strings escaped as Python's `json.dumps(ensure_ascii=False)`
// does), `hash` is the lowercase hex SHA-256 of that text, so the same contract hashes identically on every host.
//
// `verdict` is what the contract alone can say: "incomplete" when a required obligation names a kind this verifier does
// not execute, or states no expected outcome; advisory text never makes a claim verified. An amendment is a new
// contract whose `predecessor` is the hash of the one it replaces; `amends` checks that link and nothing rewrites the
// meaning of existing evidence.
//
// Memory: the arena is retained; the contract's strings live in it.

use e.crypto.hash
use e.fmt.json as json
use e.mem
use e.str

error Invalid

type Obligation = struct { id: str, kind: str, expect: str, required: bool }

type Contract = struct {
    canonical: str,
    hash: str,
    base: str,
    tier: str,
    predecessor: str,
    has_predecessor: bool,
    permit: []const str,
    forbid: []const str,
    obligations: []const Obligation,
}

const MAX_DEPTH: u16 = 16u16

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
    case .Array as a:
        items = a
        found = true
    default:
        found = false
    }
    ret (items, found)
}

fn text_of(v: json.Value) -> (str, bool) {
    var found = false
    var text = ""
    switch v {
    case .String as s:
        text = s
        found = true
    default:
        found = false
    }
    ret (text, found)
}

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, key) { ret (members[at].value, true) }
        at += 1usize
    }
    ret (.Null, false)
}

fn member_text(members: []const json.Member, key: str) -> (str, bool) {
    let (v, found) = member(members, key)
    if !found { ret ("", false) }
    let (text, is_text) = text_of(v)
    ret (text, is_text)
}

// Whether every key of `members` is one of `allowed`.
fn only_keys(members: []const json.Member, allowed: []const str) -> bool {
    var at = 0usize
    while at < members.len {
        var known = false
        var k = 0usize
        while k < allowed.len {
            if str.eq(members[at].key, allowed[k]) { known = true }
            k += 1usize
        }
        if !known { ret false }
        at += 1usize
    }
    ret true
}

fn strings_of(a: *mem.Arena, v: json.Value) -> ([]const str, bool) {
    let (items, is_array) = items_of(v)
    var none: []const str = zero
    if !is_array { ret (none, false) }
    let (out, out_error) = mem.alloc[str](a, items.len + 1usize)
    if out_error != ok { ret (none, false) }
    var at = 0usize
    while at < items.len {
        let (text, is_text) = text_of(items[at])
        if !is_text { ret (none, false) }
        out[at] = text
        at += 1usize
    }
    ret (out[0usize..items.len], true)
}

fn is_integer_lexeme(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    if s[0] == 45u8 { at = 1usize }
    if at >= s.len { ret false }
    if str.eq(s, "-0") { ret false }
    while at < s.len {
        if s[at] < 48u8 || s[at] > 57u8 { ret false }
        at += 1usize
    }
    ret true
}

// --- canonical serialization ----------------------------------------------------------------------------------------

fn hex_digit(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 87u8 + n
}

fn write_string(b: *str.Builder, s: str) -> err {
    try str.push_byte(b, 34u8)
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 34u8 {
            try str.push(b, "\\\"")
        } else if c == 92u8 {
            try str.push(b, "\\\\")
        } else if c == 10u8 {
            try str.push(b, "\\n")
        } else if c == 13u8 {
            try str.push(b, "\\r")
        } else if c == 9u8 {
            try str.push(b, "\\t")
        } else if c == 8u8 {
            try str.push(b, "\\b")
        } else if c == 12u8 {
            try str.push(b, "\\f")
        } else if c < 32u8 {
            try str.push(b, "\\u00")
            try str.push_byte(b, hex_digit(c >> 4u8))
            try str.push_byte(b, hex_digit(c & 15u8))
        } else {
            try str.push_byte(b, c)
        }
        at += 1usize
    }
    ret str.push_byte(b, 34u8)
}

fn write_value(a: *mem.Arena, b: *str.Builder, v: json.Value) -> err {
    switch v {
    case .Null:
        ret str.push(b, "null")
    case .Bool as flag:
        if flag { ret str.push(b, "true") }
        ret str.push(b, "false")
    case .Number as n:
        if !is_integer_lexeme(n.lexeme) { ret Invalid }
        ret str.push(b, n.lexeme)
    case .String as s:
        ret write_string(b, s)
    case .Array as items:
        try str.push_byte(b, 91u8)
        var at = 0usize
        while at < items.len {
            if at > 0usize { try str.push_byte(b, 44u8) }
            try write_value(a, b, items[at])
            at += 1usize
        }
        ret str.push_byte(b, 93u8)
    case .Object as members:
        // Keys in byte order without an allocation (the builder owns the arena's tail while it is open):
        // each round writes the smallest key above the one written last. Keys are unique, parse sees to it.
        try str.push_byte(b, 123u8)
        var written = 0usize
        var previous = ""
        while written < members.len {
            var best = members.len
            var at = 0usize
            while at < members.len {
                let above = written == 0usize || str.compare(members[at].key, previous) > 0i32
                if above && (best == members.len || str.compare(members[at].key, members[best].key) < 0i32) { best = at }
                at += 1usize
            }
            if best == members.len { ret Invalid }
            if written > 0usize { try str.push_byte(b, 44u8) }
            try write_string(b, members[best].key)
            try str.push_byte(b, 58u8)
            try write_value(a, b, members[best].value)
            previous = members[best].key
            written += 1usize
        }
        ret str.push_byte(b, 125u8)
    }
}

// The canonical text of a JSON value: keys in byte order, no whitespace, integers only.
fn canonical_json(a: *mem.Arena, v: json.Value) -> (str, err) {
    let (b, builder_error) = str.builder(a, 256usize)
    if builder_error != ok { ret ("", builder_error) }
    var out = b
    let written = write_value(a, &out, v)
    if written != ok { ret ("", written) }
    ret (str.done(&out), ok)
}

fn hex_of(a: *mem.Arena, digest: [32]u8) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, 64usize)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    while at < 32usize {
        out[at * 2usize] = hex_digit(digest[at] >> 4u8)
        out[at * 2usize + 1usize] = hex_digit(digest[at] & 15u8)
        at += 1usize
    }
    ret (out[0usize..64usize], ok)
}

fn is_hex64(s: str) -> bool {
    if s.len != 64usize { ret false }
    var at = 0usize
    while at < 64usize {
        let c = s[at]
        if !((c >= 48u8 && c <= 57u8) || (c >= 97u8 && c <= 102u8)) { ret false }
        at += 1usize
    }
    ret true
}

fn supported_kind(kind: str) -> bool {
    ret str.eq(kind, "test") || str.eq(kind, "check") || str.eq(kind, "build") || str.eq(kind, "diff")
}

// --- parse --------------------------------------------------------------------------------------------------------

fn parse(a: *mem.Arena, text: str) -> (Contract, err) {
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: MAX_DEPTH })
    if parse_error != ok { ret (zero, Invalid) }
    let (top, is_object) = members_of(root)
    if !is_object { ret (zero, Invalid) }
    var keys: [9]str = zero
    keys[0] = "schema"
    keys[1] = "version"
    keys[2] = "base"
    keys[3] = "objective"
    keys[4] = "provenance"
    keys[5] = "scope"
    keys[6] = "obligations"
    keys[7] = "tier"
    keys[8] = "predecessor"
    if !only_keys(top, keys[0..9]) { ret (zero, Invalid) }
    let (schema, have_schema) = member_text(top, "schema")
    if !have_schema || !str.eq(schema, "neper-change-contract") { ret (zero, Invalid) }
    let (version, have_version) = member(top, "version")
    var version_ok = false
    if have_version {
        switch version {
        case .Number as n:
            version_ok = str.eq(n.lexeme, "1")
        default:
            version_ok = false
        }
    }
    if !version_ok { ret (zero, Invalid) }
    let (base, have_base) = member_text(top, "base")
    if !have_base || base.len == 0usize { ret (zero, Invalid) }
    let (objective, have_objective) = member_text(top, "objective")
    if !have_objective { ret (zero, Invalid) }
    let (provenance, have_provenance) = member(top, "provenance")
    if !have_provenance { ret (zero, Invalid) }
    let (provenance_members, provenance_is_object) = members_of(provenance)
    if !provenance_is_object { ret (zero, Invalid) }
    let (tier, have_tier) = member_text(top, "tier")
    if !have_tier || !(str.eq(tier, "fast") || str.eq(tier, "affected") || str.eq(tier, "full")) { ret (zero, Invalid) }
    let (scope, have_scope) = member(top, "scope")
    if !have_scope { ret (zero, Invalid) }
    let (scope_members, scope_is_object) = members_of(scope)
    if !scope_is_object { ret (zero, Invalid) }
    var scope_keys: [2]str = zero
    scope_keys[0] = "permit"
    scope_keys[1] = "forbid"
    if !only_keys(scope_members, scope_keys[0..2]) { ret (zero, Invalid) }
    let (permit_value, have_permit) = member(scope_members, "permit")
    let (forbid_value, have_forbid) = member(scope_members, "forbid")
    if !have_permit || !have_forbid { ret (zero, Invalid) }
    let (permit, permit_ok) = strings_of(a, permit_value)
    let (forbid, forbid_ok) = strings_of(a, forbid_value)
    if !permit_ok || !forbid_ok { ret (zero, Invalid) }
    let (obligation_value, have_obligations) = member(top, "obligations")
    if !have_obligations { ret (zero, Invalid) }
    let (obligation_items, obligations_are_array) = items_of(obligation_value)
    if !obligations_are_array { ret (zero, Invalid) }
    let (obligations, obligations_error) = mem.alloc[Obligation](a, obligation_items.len + 1usize)
    if obligations_error != ok { ret (zero, obligations_error) }
    var item_keys: [4]str = zero
    item_keys[0] = "id"
    item_keys[1] = "kind"
    item_keys[2] = "expect"
    item_keys[3] = "disposition"
    var at = 0usize
    while at < obligation_items.len {
        let (fields, is_fields) = members_of(obligation_items[at])
        if !is_fields || !only_keys(fields, item_keys[0..4]) || fields.len != 4usize { ret (zero, Invalid) }
        let (id, have_id) = member_text(fields, "id")
        let (kind, have_kind) = member_text(fields, "kind")
        let (expect, have_expect) = member_text(fields, "expect")
        let (disposition, have_disposition) = member_text(fields, "disposition")
        if !(have_id && have_kind && have_expect && have_disposition) || id.len == 0usize { ret (zero, Invalid) }
        if !(str.eq(disposition, "required") || str.eq(disposition, "advisory")) { ret (zero, Invalid) }
        var seen = 0usize
        while seen < at {
            if str.eq(obligations[seen].id, id) { ret (zero, Invalid) }
            seen += 1usize
        }
        obligations[at] = Obligation { id: id, kind: kind, expect: expect, required: str.eq(disposition, "required") }
        at += 1usize
    }
    var predecessor = ""
    var has_predecessor = false
    let (predecessor_value, present_predecessor) = member(top, "predecessor")
    if present_predecessor {
        let (predecessor_text, have_predecessor) = text_of(predecessor_value)
        if !have_predecessor || !is_hex64(predecessor_text) { ret (zero, Invalid) }
        predecessor = predecessor_text
        has_predecessor = true
    }
    let (canonical, canonical_error) = canonical_json(a, root)
    if canonical_error != ok { ret (zero, Invalid) }
    let digest = hash.sha256(canonical)
    let (hash_text, hash_error) = hex_of(a, digest)
    if hash_error != ok { ret (zero, hash_error) }
    ret (Contract { canonical: canonical, hash: hash_text, base: base, tier: tier, predecessor: predecessor, has_predecessor: has_predecessor, permit: permit, forbid: forbid, obligations: obligations[0..obligation_items.len] }, ok)
}

// "complete" when every required obligation is one this verifier executes and says what outcome it expects;
// otherwise "incomplete". Advisory obligations never count toward verification.
fn verdict(c: *const Contract) -> str {
    var at = 0usize
    while at < c.obligations.len {
        let o = c.obligations[at]
        if o.required && (!supported_kind(o.kind) || o.expect.len == 0usize) { ret "incomplete" }
        at += 1usize
    }
    ret "complete"
}

// How many obligations the contract requires.
fn required_count(c: *const Contract) -> usize {
    var count = 0usize
    var at = 0usize
    while at < c.obligations.len {
        if c.obligations[at].required { count += 1usize }
        at += 1usize
    }
    ret count
}

// Whether `evidence_hash` is the contract this evidence was produced under: the whole identity, not a prefix.
fn bound_to(c: *const Contract, evidence_hash: str) -> bool { ret str.eq(c.hash, evidence_hash) }

// Whether `next` is a recorded amendment of `previous`: its predecessor is the previous contract's hash.
fn amends(next: *const Contract, previous: *const Contract) -> bool {
    ret next.has_predecessor && str.eq(next.predecessor, previous.hash)
}
