// Change bundles and their integration (T042, H38): the unit an isolated agent hands back and the judgement of whether
// several of them can be combined. A bundle is a content-addressed JSON document naming its base and result snapshots,
// the edits it made (path and byte range), the semantic identities those edits changed, and the contract, environment,
// policy and receipt hashes it was produced under. `integrate` takes bundles and the snapshot the integrator now stands
// on and answers one of four verdicts with structured causes:
//
//   stale       a bundle's base is not the current snapshot (cause `stale:I`)
//   conflict    two bundles edit overlapping byte ranges of one path (`overlap:PATH:I:J`), or changed the same semantic
//               identity though their text is disjoint (`identity:NAME:I:J`)
//   incomplete  a bundle has no receipt (`no-receipt:I`), or two bundles were produced under different policies
//               (`policy:I:J`) or environments (`environment:I:J`), so their claims cannot be composed
//   clean       none of the above
//
// in that precedence. Combining bundles makes a new snapshot: `combined` is its identity (the base and the bundle hashes in
// order), and the verdict never says it is verified -- the independent receipts do not imply it, only a new receipt for
// the integrated snapshot does, which is why `needs_receipt` is always true.
//
// Memory: the arena is retained; the bundles' strings and the causes live in it.

use e.crypto.hash
use e.fmt.json as json
use e.mem
use e.str
use x.agent.contract as contract

error Invalid

type Edit = struct { path: str, start: usize, end: usize }

type Bundle = struct {
    hash: str,
    base: str,
    result: str,
    edits: []const Edit,
    identities: []const str,
    contract_hash: str,
    environment: str,
    policy: str,
    receipt: str,
}

type Integration = struct { verdict: str, causes: []const str, combined: str, needs_receipt: bool }

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

fn find(members: []const json.Member, key: str) -> (json.Value, bool) {
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, key) { ret (members[at].value, true) }
        at += 1usize
    }
    ret (.Null, false)
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

// A non-negative integer lexeme of at most eighteen digits.
fn count_of(v: json.Value) -> (usize, bool) {
    var value = 0usize
    var good = false
    switch v {
    case .Number as n:
        good = n.lexeme.len > 0usize && n.lexeme.len < 19usize
        var at = 0usize
        while at < n.lexeme.len {
            if n.lexeme[at] < 48u8 || n.lexeme[at] > 57u8 {
                good = false
            } else {
                value = value * 10usize + usize(n.lexeme[at] - 48u8)
            }
            at += 1usize
        }
    default:
        good = false
    }
    ret (value, good)
}

fn parse(a: *mem.Arena, text: str) -> (Bundle, err) {
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 6u16 })
    if parse_error != ok { ret (zero, Invalid) }
    let (top, is_object) = members_of(root)
    if !is_object || top.len != 10usize { ret (zero, Invalid) }
    let (schema, have_schema) = find(top, "schema")
    let (schema_text, schema_is_text) = text_of(schema)
    if !have_schema || !schema_is_text || !str.eq(schema_text, "neper-change-bundle") { ret (zero, Invalid) }
    let (version, have_version) = find(top, "version")
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
    var names: [6]str = zero
    names[0] = "base"
    names[1] = "result"
    names[2] = "contract"
    names[3] = "environment"
    names[4] = "policy"
    names[5] = "receipt"
    var values: [6]str = zero
    var n = 0usize
    while n < 6usize {
        let (v, present) = find(top, names[n])
        let (t, is_text) = text_of(v)
        if !present || !is_text { ret (zero, Invalid) }
        values[n] = t
        n += 1usize
    }
    if values[0].len == 0usize || values[1].len == 0usize { ret (zero, Invalid) }
    // The three bound hashes are hashes; the receipt is a hash or empty (no receipt yet).
    if !is_hex64(values[2]) || !is_hex64(values[3]) || !is_hex64(values[4]) { ret (zero, Invalid) }
    if values[5].len != 0usize && !is_hex64(values[5]) { ret (zero, Invalid) }
    let (edits_value, have_edits) = find(top, "edits")
    let (edit_items, edits_are_array) = items_of(edits_value)
    if !have_edits || !edits_are_array { ret (zero, Invalid) }
    let (edits, edits_error) = mem.alloc[Edit](a, edit_items.len + 1usize)
    if edits_error != ok { ret (zero, edits_error) }
    var at = 0usize
    while at < edit_items.len {
        let (fields, is_fields) = members_of(edit_items[at])
        if !is_fields || fields.len != 3usize { ret (zero, Invalid) }
        let (path_value, have_path) = find(fields, "path")
        let (start_value, have_start) = find(fields, "start")
        let (end_value, have_end) = find(fields, "end")
        let (path, path_is_text) = text_of(path_value)
        let (start, start_ok) = count_of(start_value)
        let (end, end_ok) = count_of(end_value)
        if !(have_path && have_start && have_end && path_is_text && start_ok && end_ok) || path.len == 0usize || start > end { ret (zero, Invalid) }
        edits[at] = Edit { path: path, start: start, end: end }
        at += 1usize
    }
    let (identity_value, have_identities) = find(top, "identities")
    let (identity_items, identities_are_array) = items_of(identity_value)
    if !have_identities || !identities_are_array { ret (zero, Invalid) }
    let (identities, identities_error) = mem.alloc[str](a, identity_items.len + 1usize)
    if identities_error != ok { ret (zero, identities_error) }
    at = 0usize
    while at < identity_items.len {
        let (name, name_is_text) = text_of(identity_items[at])
        if !name_is_text || name.len == 0usize { ret (zero, Invalid) }
        identities[at] = name
        at += 1usize
    }
    let (canonical, canonical_error) = contract.canonical_json(a, root)
    if canonical_error != ok { ret (zero, Invalid) }
    let (hash_text, hash_error) = contract.hex_of(a, hash.sha256(canonical))
    if hash_error != ok { ret (zero, hash_error) }
    ret (Bundle { hash: hash_text, base: values[0], result: values[1], edits: edits[0usize..edit_items.len], identities: identities[0usize..identity_items.len], contract_hash: values[2], environment: values[3], policy: values[4], receipt: values[5] }, ok)
}

fn decimal(a: *mem.Arena, n: usize) -> (str, err) {
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
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    while at < count {
        out[at] = digits[count - 1usize - at]
        at += 1usize
    }
    ret (out[0usize..count], ok)
}

fn cause(a: *mem.Arena, kind: str, name: str, i: usize, j: usize, with_pair: bool) -> (str, err) {
    let (first, first_error) = decimal(a, i)
    if first_error != ok { ret ("", first_error) }
    var parts: [6]str = zero
    parts[0] = kind
    var count = 1usize
    if name.len > 0usize {
        parts[count] = name
        count += 1usize
    }
    parts[count] = first
    count += 1usize
    if with_pair {
        let (second, second_error) = decimal(a, j)
        if second_error != ok { ret ("", second_error) }
        parts[count] = second
        count += 1usize
    }
    let (joined, join_error) = str.join(a, parts[0usize..count], ":")
    ret (joined, join_error)
}

// A bounded list of causes: past its capacity a cause is dropped, the verdict does not change.
type Pile = struct { items: []str, count: usize }

fn push(p: *Pile, text: str) {
    if p.count < p.items.len {
        p.items[p.count] = text
        p.count += 1usize
    }
}

// The verdict on combining `bundles` when the integrator stands on `current_base`.
fn integrate(a: *mem.Arena, bundles: []const Bundle, current_base: str) -> (Integration, err) {
    let (stale_items, stale_error) = mem.alloc[str](a, 64usize)
    if stale_error != ok { ret (zero, stale_error) }
    let (conflict_items, conflict_error) = mem.alloc[str](a, 128usize)
    if conflict_error != ok { ret (zero, conflict_error) }
    let (incomplete_items, incomplete_error) = mem.alloc[str](a, 64usize)
    if incomplete_error != ok { ret (zero, incomplete_error) }
    var stale = Pile { items: stale_items, count: 0usize }
    var conflict = Pile { items: conflict_items, count: 0usize }
    var incomplete = Pile { items: incomplete_items, count: 0usize }
    var i = 0usize
    while i < bundles.len {
        if !str.eq(bundles[i].base, current_base) {
            let (text, text_error) = cause(a, "stale", "", i, 0usize, false)
            if text_error != ok { ret (zero, text_error) }
            push(&stale, text)
        }
        if bundles[i].receipt.len == 0usize {
            let (text, text_error) = cause(a, "no-receipt", "", i, 0usize, false)
            if text_error != ok { ret (zero, text_error) }
            push(&incomplete, text)
        }
        i += 1usize
    }
    i = 0usize
    while i < bundles.len {
        var j = i + 1usize
        while j < bundles.len {
            let x = bundles[i]
            let y = bundles[j]
            var ex = 0usize
            while ex < x.edits.len {
                var ey = 0usize
                while ey < y.edits.len {
                    if str.eq(x.edits[ex].path, y.edits[ey].path) && x.edits[ex].start < y.edits[ey].end && y.edits[ey].start < x.edits[ex].end {
                        let (text, text_error) = cause(a, "overlap", x.edits[ex].path, i, j, true)
                        if text_error != ok { ret (zero, text_error) }
                        push(&conflict, text)
                    }
                    ey += 1usize
                }
                ex += 1usize
            }
            var ix = 0usize
            while ix < x.identities.len {
                var iy = 0usize
                while iy < y.identities.len {
                    if str.eq(x.identities[ix], y.identities[iy]) {
                        let (text, text_error) = cause(a, "identity", x.identities[ix], i, j, true)
                        if text_error != ok { ret (zero, text_error) }
                        push(&conflict, text)
                    }
                    iy += 1usize
                }
                ix += 1usize
            }
            if !str.eq(x.policy, y.policy) {
                let (text, text_error) = cause(a, "policy", "", i, j, true)
                if text_error != ok { ret (zero, text_error) }
                push(&incomplete, text)
            }
            if !str.eq(x.environment, y.environment) {
                let (text, text_error) = cause(a, "environment", "", i, j, true)
                if text_error != ok { ret (zero, text_error) }
                push(&incomplete, text)
            }
            j += 1usize
        }
        i += 1usize
    }
    // The combined snapshot: the base then every bundle's hash, in order.
    let (parts, parts_error) = mem.alloc[str](a, bundles.len + 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0] = current_base
    var at = 0usize
    while at < bundles.len {
        parts[at + 1usize] = bundles[at].hash
        at += 1usize
    }
    let (joined, joined_error) = str.join(a, parts[0usize..bundles.len + 1usize], "\n")
    if joined_error != ok { ret (zero, joined_error) }
    let (combined, combined_error) = contract.hex_of(a, hash.sha256(joined))
    if combined_error != ok { ret (zero, combined_error) }
    var verdict = "clean"
    var reported: []const str = zero
    if stale.count > 0usize {
        verdict = "stale"
        reported = stale.items[0usize..stale.count]
    } else if conflict.count > 0usize {
        verdict = "conflict"
        reported = conflict.items[0usize..conflict.count]
    } else if incomplete.count > 0usize {
        verdict = "incomplete"
        reported = incomplete.items[0usize..incomplete.count]
    }
    ret (Integration { verdict: verdict, causes: reported, combined: combined, needs_receipt: true }, ok)
}
