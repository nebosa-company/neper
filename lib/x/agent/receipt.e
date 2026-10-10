// The verification receipt (T042, H35/H36/H37/H38): the one record that says a change was verified, and exactly under what.
// A receipt names the contract, environment identity, policy and bundle it belongs to, the snapshot it covers and one
// result per obligation (`pass`, `fail` or `not-run`, with evidence `executed`, `cached` or `none`). `verify` judges it
// against the contract it must be bound to and what the trusted side observed:
//
//   unbound     the receipt's contract hash is not this contract's (altered base, scope, expectation or tier all change it)
//   unsafe      the audit verdict is not `verified` (a violation, an undeclared or unapproved effect, or an unenforced one)
//   unhermetic  the run's environment level does not satisfy the level the contract needs
//   failed      a required obligation's result is `fail`
//   incomplete  a required obligation has no result, did not run, or the contract itself names a required obligation this
//               verifier does not execute
//   verified    every required obligation passed with evidence, nothing above applies
//
// in that precedence. Advisory obligations and results for ids the contract does not have never count toward a claim, and a
// cached pass verifies but is reported as cached: `fresh` is the number of required results actually executed.
//
// Memory: the arena is retained; the receipt's strings live in it.

use e.crypto.hash
use e.fmt.json as json
use e.mem
use e.str
use x.agent.contract as contract
use x.agent.environment as environment

error Invalid

type Result = struct { id: str, outcome: str, evidence: str }

type Receipt = struct {
    hash: str,
    contract_hash: str,
    environment: str,
    policy: str,
    bundle: str,
    snapshot: str,
    results: []const Result,
}

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

fn parse(a: *mem.Arena, text: str) -> (Receipt, err) {
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 6u16 })
    if parse_error != ok { ret (zero, Invalid) }
    let (top, is_object) = members_of(root)
    if !is_object || top.len != 8usize { ret (zero, Invalid) }
    let (schema, have_schema) = find(top, "schema")
    let (schema_text, schema_is_text) = text_of(schema)
    if !have_schema || !schema_is_text || !str.eq(schema_text, "neper-receipt") { ret (zero, Invalid) }
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
    var names: [5]str = zero
    names[0] = "contract"
    names[1] = "environment"
    names[2] = "policy"
    names[3] = "bundle"
    names[4] = "snapshot"
    var values: [5]str = zero
    var n = 0usize
    while n < 5usize {
        let (v, present) = find(top, names[n])
        let (t, is_text) = text_of(v)
        if !present || !is_text { ret (zero, Invalid) }
        values[n] = t
        n += 1usize
    }
    if !is_hex64(values[0]) || !is_hex64(values[1]) || !is_hex64(values[2]) || !is_hex64(values[3]) || values[4].len == 0usize { ret (zero, Invalid) }
    let (results_value, have_results) = find(top, "results")
    let (items, results_are_array) = items_of(results_value)
    if !have_results || !results_are_array { ret (zero, Invalid) }
    let (results, results_error) = mem.alloc[Result](a, items.len + 1usize)
    if results_error != ok { ret (zero, results_error) }
    var at = 0usize
    while at < items.len {
        let (fields, is_fields) = members_of(items[at])
        if !is_fields || fields.len != 3usize { ret (zero, Invalid) }
        let (id_value, have_id) = find(fields, "id")
        let (outcome_value, have_outcome) = find(fields, "outcome")
        let (evidence_value, have_evidence) = find(fields, "evidence")
        let (id, id_is_text) = text_of(id_value)
        let (outcome, outcome_is_text) = text_of(outcome_value)
        let (evidence, evidence_is_text) = text_of(evidence_value)
        if !(have_id && have_outcome && have_evidence && id_is_text && outcome_is_text && evidence_is_text) || id.len == 0usize { ret (zero, Invalid) }
        if !(str.eq(outcome, "pass") || str.eq(outcome, "fail") || str.eq(outcome, "not-run")) { ret (zero, Invalid) }
        if !(str.eq(evidence, "executed") || str.eq(evidence, "cached") || str.eq(evidence, "none")) { ret (zero, Invalid) }
        // A run that happened has evidence; a run that did not, has none.
        if str.eq(outcome, "not-run") != str.eq(evidence, "none") { ret (zero, Invalid) }
        var seen = 0usize
        while seen < at {
            if str.eq(results[seen].id, id) { ret (zero, Invalid) }
            seen += 1usize
        }
        results[at] = Result { id: id, outcome: outcome, evidence: evidence }
        at += 1usize
    }
    let (canonical, canonical_error) = contract.canonical_json(a, root)
    if canonical_error != ok { ret (zero, Invalid) }
    let (hash_text, hash_error) = contract.hex_of(a, hash.sha256(canonical))
    if hash_error != ok { ret (zero, hash_error) }
    ret (Receipt { hash: hash_text, contract_hash: values[0], environment: values[1], policy: values[2], bundle: values[3], snapshot: values[4], results: results[0usize..items.len] }, ok)
}

fn result_for(r: *const Receipt, id: str) -> (Result, bool) {
    var at = 0usize
    while at < r.results.len {
        if str.eq(r.results[at].id, id) { ret (r.results[at], true) }
        at += 1usize
    }
    ret (zero, false)
}

// The verdict on a receipt, in the module header's precedence.
fn verify(c: *const contract.Contract, r: *const Receipt, env_level: str, required_level: str, audit_verdict: str) -> str {
    if !str.eq(c.hash, r.contract_hash) { ret "unbound" }
    if !str.eq(audit_verdict, "verified") { ret "unsafe" }
    if !environment.permits(env_level, required_level) { ret "unhermetic" }
    var incomplete = str.eq(contract.verdict(c), "incomplete")
    var at = 0usize
    while at < c.obligations.len {
        let o = c.obligations[at]
        if o.required {
            let (result, present) = result_for(r, o.id)
            if !present {
                incomplete = true
            } else if str.eq(result.outcome, "fail") {
                ret "failed"
            } else if str.eq(result.outcome, "not-run") {
                incomplete = true
            }
        }
        at += 1usize
    }
    if incomplete { ret "incomplete" }
    ret "verified"
}

// How many required obligations were executed now rather than reused from a cache: the claim's freshness.
fn fresh(c: *const contract.Contract, r: *const Receipt) -> usize {
    var count = 0usize
    var at = 0usize
    while at < c.obligations.len {
        let o = c.obligations[at]
        if o.required {
            let (result, present) = result_for(r, o.id)
            if present && str.eq(result.evidence, "executed") { count += 1usize }
        }
        at += 1usize
    }
    ret count
}
