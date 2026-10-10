// The durable operation lifecycle (T042, H44): a long check, test or build is a task with an unguessable handle, a
// monotonic status and one canonical terminal result, so a client can disconnect, come back and ask. The module is the
// state machine and its authorization, nothing else; persistence is `snapshot`, which is the canonical text of the state
// (and its hash), restored by whoever stored it.
//
//   queued -> running | cancelled          input_required -> running | cancelling | failed
//   running -> input_required | succeeded | failed | cancelling
//   cancelling -> cancelled | succeeded | failed        (work that finishes during a cancel keeps its result)
//   succeeded, failed, cancelled: terminal, never rewritten
//
// A handle is the HMAC of the task's id and nonce under the service's key: it cannot be guessed, and possessing it is
// not enough, the caller must also be the owner. `authorize` answers `unknown-handle` before it looks at the caller (so a
// wrong handle reveals nothing), then `denied`, then `expired`. Input and approvals are tokens bound to the task, its
// operation, policy and scope with an expiry and a nonce, authenticated under the same key; a token is consumed once and
// is refused for a task that is not waiting. Every update is idempotent or refused explicitly: a second completion with
// the same result is `duplicate`, with another `rejected`; cancelling a terminal task changes nothing.
//
// Memory: the arena is retained; the task's strings live in it.

use e.crypto.hash
use e.crypto.mac
use e.fmt.json as json
use e.mem
use e.str
use x.agent.contract as contract

error Invalid

type Task = struct {
    id: str,
    operation: str,
    policy: str,
    scope: str,
    owner: str,
    status: str,
    created: usize,
    expires: usize,
    nonce: str,
    outcome: str,
    result_hash: str,
    seen: []const str,
    version: usize,
}

fn is_terminal(status: str) -> bool {
    ret str.eq(status, "succeeded") || str.eq(status, "failed") || str.eq(status, "cancelled")
}

fn create(id: str, operation: str, policy: str, scope: str, owner: str, created: usize, expires: usize, nonce: str) -> Task {
    var none: []const str = zero
    ret Task { id: id, operation: operation, policy: policy, scope: scope, owner: owner, status: "queued", created: created, expires: expires, nonce: nonce, outcome: "", result_hash: "", seen: none, version: 0usize }
}

fn handle_of(a: *mem.Arena, key: str, t: *const Task) -> (str, err) {
    var parts: [2]str = zero
    parts[0] = t.id
    parts[1] = t.nonce
    let (joined, join_error) = str.join(a, parts[0usize..2usize], "\n")
    if join_error != ok { ret ("", join_error) }
    let (handle, handle_error) = contract.hex_of(a, mac.hmac_sha256(key, joined))
    ret (handle, handle_error)
}

// "ok", "unknown-handle", "denied" or "expired".
fn authorize(a: *mem.Arena, key: str, t: *const Task, handle: str, caller: str, now: usize) -> (str, err) {
    let (expected, handle_error) = handle_of(a, key, t)
    if handle_error != ok { ret ("", handle_error) }
    if !str.eq(expected, handle) { ret ("unknown-handle", ok) }
    if !str.eq(caller, t.owner) { ret ("denied", ok) }
    if now > t.expires { ret ("expired", ok) }
    ret ("ok", ok)
}

fn allowed(from: str, to: str) -> bool {
    if str.eq(from, "queued") { ret str.eq(to, "running") || str.eq(to, "cancelled") }
    if str.eq(from, "running") { ret str.eq(to, "input_required") || str.eq(to, "succeeded") || str.eq(to, "failed") || str.eq(to, "cancelling") }
    if str.eq(from, "input_required") { ret str.eq(to, "running") || str.eq(to, "cancelling") || str.eq(to, "failed") }
    if str.eq(from, "cancelling") { ret str.eq(to, "cancelled") || str.eq(to, "succeeded") || str.eq(to, "failed") }
    ret false
}

// A status change by the executor: "ok", "terminal" (the task is finished and stays so) or "illegal".
fn advance(t: *Task, to: str) -> str {
    if is_terminal(t.status) { ret "terminal" }
    if !allowed(t.status, to) { ret "illegal" }
    t.status = to
    t.version += 1usize
    ret "ok"
}

// A cancel request: "cancelled" (it had not started), "cancelling" (it is, or already was, running), or
// "already-terminal" (nothing changes).
fn cancel(t: *Task) -> str {
    if is_terminal(t.status) { ret "already-terminal" }
    if str.eq(t.status, "queued") {
        t.status = "cancelled"
        t.version += 1usize
        ret "cancelled"
    }
    if str.eq(t.status, "cancelling") { ret "cancelling" }
    t.status = "cancelling"
    t.version += 1usize
    ret "cancelling"
}

// The terminal result: "ok", "duplicate" (the same result again), "rejected" (a different one, or an illegal outcome).
// A cancelled outcome is only legal for a task that is cancelling or queued.
fn complete(a: *mem.Arena, t: *Task, outcome: str, result: str) -> (str, err) {
    let (digest, digest_error) = contract.hex_of(a, hash.sha256(result))
    if digest_error != ok { ret ("", digest_error) }
    if is_terminal(t.status) {
        if str.eq(t.outcome, outcome) && str.eq(t.result_hash, digest) { ret ("duplicate", ok) }
        ret ("rejected", ok)
    }
    if !(str.eq(outcome, "succeeded") || str.eq(outcome, "failed") || str.eq(outcome, "cancelled")) { ret ("rejected", ok) }
    if !allowed(t.status, outcome) { ret ("rejected", ok) }
    t.status = outcome
    t.outcome = outcome
    t.result_hash = digest
    t.version += 1usize
    ret ("ok", ok)
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

fn in_list(list: []const str, entry: str) -> bool {
    var at = 0usize
    while at < list.len {
        if str.eq(list[at], entry) { ret true }
        at += 1usize
    }
    ret false
}

// Input or approval for a waiting task: "valid" (the task runs again and the nonce is spent), or why not: "malformed",
// "bad-mac", "wrong-task", "wrong-operation", "wrong-policy", "wrong-scope", "expired", "replayed", "not-waiting".
fn supply_input(a: *mem.Arena, key: str, t: *Task, token: str, now: usize) -> (str, err) {
    let (root, parse_error) = json.parse(a, token, json.Options { allow_duplicate_keys: false, max_depth: 4u16 })
    if parse_error != ok { ret ("malformed", ok) }
    let (fields, is_fields) = members_of(root)
    if !is_fields || fields.len != 7usize { ret ("malformed", ok) }
    var names: [6]str = zero
    names[0] = "task"
    names[1] = "operation"
    names[2] = "policy"
    names[3] = "scope"
    names[4] = "nonce"
    names[5] = "mac"
    var values: [6]str = zero
    var n = 0usize
    while n < 6usize {
        let (v, present) = find(fields, names[n])
        let (text, is_text) = text_of(v)
        if !present || !is_text { ret ("malformed", ok) }
        values[n] = text
        n += 1usize
    }
    let (expires_value, have_expires) = find(fields, "expires")
    var expires = 0usize
    var expires_ok = false
    switch expires_value {
    case .Number as number:
        expires_ok = have_expires && number.lexeme.len > 0usize && number.lexeme.len < 19usize
        var at = 0usize
        while at < number.lexeme.len {
            if number.lexeme[at] < 48u8 || number.lexeme[at] > 57u8 { expires_ok = false } else { expires = expires * 10usize + usize(number.lexeme[at] - 48u8) }
            at += 1usize
        }
    default:
        expires_ok = false
    }
    if !expires_ok { ret ("malformed", ok) }
    let (body, body_error) = mem.alloc[json.Member](a, 7usize)
    if body_error != ok { ret ("", body_error) }
    var count = 0usize
    var at = 0usize
    while at < fields.len {
        if !str.eq(fields[at].key, "mac") {
            body[count] = fields[at]
            count += 1usize
        }
        at += 1usize
    }
    let (canonical, canonical_error) = contract.canonical_json(a, json.Value{ Object: body[0usize..count] })
    if canonical_error != ok { ret ("malformed", ok) }
    let (expected, expected_error) = contract.hex_of(a, mac.hmac_sha256(key, canonical))
    if expected_error != ok { ret ("", expected_error) }
    if !str.eq(expected, values[5]) { ret ("bad-mac", ok) }
    if !str.eq(values[0], t.id) { ret ("wrong-task", ok) }
    if !str.eq(values[1], t.operation) { ret ("wrong-operation", ok) }
    if !str.eq(values[2], t.policy) { ret ("wrong-policy", ok) }
    if !str.eq(values[3], t.scope) { ret ("wrong-scope", ok) }
    if now > expires { ret ("expired", ok) }
    if in_list(t.seen, values[4]) { ret ("replayed", ok) }
    if !str.eq(t.status, "input_required") { ret ("not-waiting", ok) }
    let (seen, seen_error) = mem.alloc[str](a, t.seen.len + 1usize)
    if seen_error != ok { ret ("", seen_error) }
    var s = 0usize
    while s < t.seen.len {
        seen[s] = t.seen[s]
        s += 1usize
    }
    seen[t.seen.len] = values[4]
    t.seen = seen[0usize..t.seen.len + 1usize]
    t.status = "running"
    t.version += 1usize
    ret ("valid", ok)
}

// The state as canonical text and its hash: what a store keeps and a restart restores.
fn snapshot(a: *mem.Arena, t: *const Task) -> (str, err) {
    let (members, members_error) = mem.alloc[json.Member](a, 13usize)
    if members_error != ok { ret ("", members_error) }
    let (seen_values, seen_error) = mem.alloc[json.Value](a, t.seen.len + 1usize)
    if seen_error != ok { ret ("", seen_error) }
    var s = 0usize
    while s < t.seen.len {
        seen_values[s] = json.Value{ String: t.seen[s] }
        s += 1usize
    }
    let (created, created_error) = number_text(a, t.created)
    if created_error != ok { ret ("", created_error) }
    let (expires, expires_error) = number_text(a, t.expires)
    if expires_error != ok { ret ("", expires_error) }
    let (version, version_error) = number_text(a, t.version)
    if version_error != ok { ret ("", version_error) }
    members[0] = json.Member { key: "id", value: json.Value{ String: t.id } }
    members[1] = json.Member { key: "operation", value: json.Value{ String: t.operation } }
    members[2] = json.Member { key: "policy", value: json.Value{ String: t.policy } }
    members[3] = json.Member { key: "scope", value: json.Value{ String: t.scope } }
    members[4] = json.Member { key: "owner", value: json.Value{ String: t.owner } }
    members[5] = json.Member { key: "status", value: json.Value{ String: t.status } }
    members[6] = json.Member { key: "created", value: json.Value{ Number: json.Number { lexeme: created } } }
    members[7] = json.Member { key: "expires", value: json.Value{ Number: json.Number { lexeme: expires } } }
    members[8] = json.Member { key: "outcome", value: json.Value{ String: t.outcome } }
    members[9] = json.Member { key: "result", value: json.Value{ String: t.result_hash } }
    members[10] = json.Member { key: "seen", value: json.Value{ Array: seen_values[0usize..t.seen.len] } }
    members[11] = json.Member { key: "version", value: json.Value{ Number: json.Number { lexeme: version } } }
    let (canonical, canonical_error) = contract.canonical_json(a, json.Value{ Object: members[0usize..12usize] })
    ret (canonical, canonical_error)
}

fn number_text(a: *mem.Arena, n: usize) -> (str, err) {
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
