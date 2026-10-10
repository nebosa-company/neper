// The enforced action policy (T042, H36): what the invoker has allowed, decided independently of the agent that proposed
// the action. A policy maps an effect kind and a scope to `allow`, `deny` or `approval_required`; the effects that reach
// outside the workspace (network, credentials, dependency changes, project execution, VCS mutation, external services,
// writes outside the workspace) are denied unless a rule grants them, and a workspace read or write is allowed unless a
// rule says otherwise. The most specific matching rule decides (an exact scope over a `prefix/*` over `*`, a longer prefix
// over a shorter) and, on a tie, the most restrictive. A declaration in an untrusted plan is a request: `audit` compares
// what was declared with what was observed and names the verdict -- `violation` (an observed effect the policy denies),
// `unapproved` (one that needed an approval nobody gave), `undeclared` (one nobody asked for) or `unenforced` (the effect
// could not be constrained or observed, so policy fails closed) -- and only `verified` is a pass.
//
// Approvals are tokens bound to one policy, effect and scope, with an expiry and a nonce, authenticated with an HMAC the
// invoker holds the key to; `approval_status` rejects a wrong mac, policy, effect or scope, an expired token and a nonce
// already seen. `redact` removes secret values from text before it is logged or stored.
//
// Memory: the arena is retained; the policy's strings live in it.

use e.crypto.hash
use e.crypto.mac
use e.fmt.json as json
use e.mem
use e.str
use x.agent.contract as contract

error Invalid

type Rule = struct { effect: str, scope: str, decision: str }

type Policy = struct { canonical: str, hash: str, workspace: str, rules: []const Rule }

const MAX_RULES: usize = 64usize

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

fn known_effect(effect: str) -> bool {
    ret str.eq(effect, "network") || str.eq(effect, "credentials") || str.eq(effect, "dependency_change") || str.eq(effect, "project_exec") || str.eq(effect, "vcs_mutation") || str.eq(effect, "external_service") || str.eq(effect, "write_outside_workspace") || str.eq(effect, "write_workspace") || str.eq(effect, "read_workspace")
}

fn known_decision(decision: str) -> bool {
    ret str.eq(decision, "allow") || str.eq(decision, "deny") || str.eq(decision, "approval_required")
}

// 0 allow, 1 approval_required, 2 deny: how restrictive a decision is.
fn restriction(decision: str) -> usize {
    if str.eq(decision, "deny") { ret 2usize }
    if str.eq(decision, "approval_required") { ret 1usize }
    ret 0usize
}

fn parse(a: *mem.Arena, text: str) -> (Policy, err) {
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 6u16 })
    if parse_error != ok { ret (zero, Invalid) }
    let (top, is_object) = members_of(root)
    if !is_object || top.len != 4usize { ret (zero, Invalid) }
    let (schema, have_schema) = find(top, "schema")
    let (schema_text, schema_is_text) = text_of(schema)
    if !have_schema || !schema_is_text || !str.eq(schema_text, "neper-action-policy") { ret (zero, Invalid) }
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
    let (workspace_value, have_workspace) = find(top, "workspace")
    let (workspace, workspace_is_text) = text_of(workspace_value)
    if !have_workspace || !workspace_is_text || workspace.len == 0usize { ret (zero, Invalid) }
    let (rules_value, have_rules) = find(top, "rules")
    let (rule_items, rules_are_array) = items_of(rules_value)
    if !have_rules || !rules_are_array || rule_items.len > MAX_RULES { ret (zero, Invalid) }
    let (rules, rules_error) = mem.alloc[Rule](a, rule_items.len + 1usize)
    if rules_error != ok { ret (zero, rules_error) }
    var at = 0usize
    while at < rule_items.len {
        let (fields, is_fields) = members_of(rule_items[at])
        if !is_fields || fields.len != 3usize { ret (zero, Invalid) }
        let (effect_value, have_effect) = find(fields, "effect")
        let (scope_value, have_scope) = find(fields, "scope")
        let (decision_value, have_decision) = find(fields, "decision")
        let (effect, effect_is_text) = text_of(effect_value)
        let (scope, scope_is_text) = text_of(scope_value)
        let (decision, decision_is_text) = text_of(decision_value)
        if !(have_effect && have_scope && have_decision && effect_is_text && scope_is_text && decision_is_text) { ret (zero, Invalid) }
        if !known_effect(effect) || scope.len == 0usize || !known_decision(decision) { ret (zero, Invalid) }
        rules[at] = Rule { effect: effect, scope: scope, decision: decision }
        at += 1usize
    }
    let (canonical, canonical_error) = contract.canonical_json(a, root)
    if canonical_error != ok { ret (zero, Invalid) }
    let (hash_text, hash_error) = contract.hex_of(a, hash.sha256(canonical))
    if hash_error != ok { ret (zero, hash_error) }
    ret (Policy { canonical: canonical, hash: hash_text, workspace: workspace, rules: rules[0usize..rule_items.len] }, ok)
}

// How specifically `pattern` names `scope`: 0 for no match, a larger number for a closer one (`*` 1, a `prefix/*` its
// length plus one, an exact scope far above both).
fn specificity(pattern: str, scope: str) -> usize {
    if str.eq(pattern, "*") { ret 1usize }
    if pattern.len >= 2usize && str.eq(pattern[pattern.len - 2usize..], "/*") {
        let prefix = pattern[0usize..pattern.len - 1usize]
        if scope.len >= prefix.len && str.eq(scope[0usize..prefix.len], prefix) { ret prefix.len + 1usize }
        ret 0usize
    }
    if str.eq(pattern, scope) { ret 1000000usize }
    ret 0usize
}

fn default_decision(effect: str) -> str {
    if str.eq(effect, "read_workspace") || str.eq(effect, "write_workspace") { ret "allow" }
    ret "deny"
}

// The decision for an effect on a scope: the most specific matching rule, the most restrictive on a tie, the default
// (allow inside the workspace, deny for everything that reaches out) when no rule matches. An unknown effect is denied.
fn decide(p: *const Policy, effect: str, scope: str) -> str {
    if !known_effect(effect) { ret "deny" }
    var best = 0usize
    var chosen = ""
    var at = 0usize
    while at < p.rules.len {
        let rule = p.rules[at]
        if str.eq(rule.effect, effect) {
            let s = specificity(rule.scope, scope)
            if s > best || (s == best && s > 0usize && restriction(rule.decision) > restriction(chosen)) {
                best = s
                chosen = rule.decision
            }
        }
        at += 1usize
    }
    if best == 0usize { ret default_decision(effect) }
    ret chosen
}

// A path with `\` as `/`, `.` and empty segments dropped, `..` resolved; `escaped` when a `..` had nothing to pop.
fn normalize(a: *mem.Arena, path: str) -> (str, bool, err) {
    let (segments, segments_error) = mem.alloc[str](a, path.len + 1usize)
    if segments_error != ok { ret ("", false, segments_error) }
    var count = 0usize
    var escaped = false
    var begin = 0usize
    var at = 0usize
    while at <= path.len {
        if at == path.len || path[at] == 47u8 || path[at] == 92u8 {
            let segment = path[begin..at]
            if segment.len == 0usize || str.eq(segment, ".") {
                begin = at + 1usize
            } else if str.eq(segment, "..") {
                if count > 0usize { count -= 1usize } else { escaped = true }
                begin = at + 1usize
            } else {
                segments[count] = segment
                count += 1usize
                begin = at + 1usize
            }
        }
        at += 1usize
    }
    let (joined, join_error) = str.join(a, segments[0usize..count], "/")
    if join_error != ok { ret ("", false, join_error) }
    let (rooted, rooted_error) = str.concat(a, "/", joined)
    if rooted_error != ok { ret ("", false, rooted_error) }
    ret (rooted, escaped, ok)
}

// The effect a write to `path` is: `write_workspace` inside the workspace, `write_outside_workspace` for anything that
// resolves outside it or climbs past the root. A relative path is taken from the workspace.
fn classify_write(a: *mem.Arena, p: *const Policy, path: str) -> (str, err) {
    let (workspace, workspace_escaped, workspace_error) = normalize(a, p.workspace)
    if workspace_error != ok { ret ("", workspace_error) }
    var full = path
    let absolute = path.len > 0usize && (path[0] == 47u8 || path[0] == 92u8 || (path.len > 1usize && path[1] == 58u8))
    if !absolute {
        let (with_slash, slash_error) = str.concat(a, p.workspace, "/")
        if slash_error != ok { ret ("", slash_error) }
        let (relative, relative_error) = str.concat(a, with_slash, path)
        if relative_error != ok { ret ("", relative_error) }
        full = relative
    }
    let (resolved, escaped, resolved_error) = normalize(a, full)
    if resolved_error != ok { ret ("", resolved_error) }
    if escaped || workspace_escaped { ret ("write_outside_workspace", ok) }
    var inside = str.eq(resolved, workspace)
    if !inside {
        var prefix = workspace
        if !str.eq(workspace, "/") {
            let (with_slash, slash_error) = str.concat(a, workspace, "/")
            if slash_error != ok { ret ("", slash_error) }
            prefix = with_slash
        }
        inside = resolved.len >= prefix.len && str.eq(resolved[0usize..prefix.len], prefix)
    }
    if inside { ret ("write_workspace", ok) }
    ret ("write_outside_workspace", ok)
}

fn in_list(list: []const str, entry: str) -> bool {
    var at = 0usize
    while at < list.len {
        if str.eq(list[at], entry) { ret true }
        at += 1usize
    }
    ret false
}

// `effect:scope` split at the first colon.
fn split_entry(entry: str) -> (str, str) {
    var at = 0usize
    while at < entry.len {
        if entry[at] == 58u8 { ret (entry[0usize..at], entry[at + 1usize..]) }
        at += 1usize
    }
    ret (entry, "")
}

// The verdict on a run: `declared` what the plan asked for, `observed` what the executor saw, `approved` the effects a
// valid approval granted, all as `effect:scope`. In order of precedence: "violation", "unapproved", "undeclared",
// "unenforced" (the effects could not be constrained or observed), else "verified".
fn audit(p: *const Policy, declared: []const str, observed: []const str, approved: []const str, enforceable: bool) -> str {
    var violation = false
    var unapproved = false
    var undeclared = false
    var at = 0usize
    while at < observed.len {
        let (effect, scope) = split_entry(observed[at])
        let decision = decide(p, effect, scope)
        if str.eq(decision, "deny") && !in_list(approved, observed[at]) {
            violation = true
        } else if str.eq(decision, "approval_required") && !in_list(approved, observed[at]) {
            unapproved = true
        }
        if !in_list(declared, observed[at]) { undeclared = true }
        at += 1usize
    }
    if violation { ret "violation" }
    if unapproved { ret "unapproved" }
    if undeclared { ret "undeclared" }
    if !enforceable { ret "unenforced" }
    ret "verified"
}

// The status of an approval token against the policy it must be bound to and the action it is offered for: "valid",
// "malformed", "bad-mac", "wrong-policy", "wrong-scope", "expired" or "replayed" (its nonce is in `seen`).
fn approval_status(a: *mem.Arena, key: str, token: str, policy_hash: str, effect: str, scope: str, now: usize, seen: []const str) -> (str, err) {
    let (root, parse_error) = json.parse(a, token, json.Options { allow_duplicate_keys: false, max_depth: 4u16 })
    if parse_error != ok { ret ("malformed", ok) }
    let (fields, is_fields) = members_of(root)
    if !is_fields || fields.len != 6usize { ret ("malformed", ok) }
    let (effect_value, have_effect) = find(fields, "effect")
    let (scope_value, have_scope) = find(fields, "scope")
    let (policy_value, have_policy) = find(fields, "policy")
    let (nonce_value, have_nonce) = find(fields, "nonce")
    let (mac_value, have_mac) = find(fields, "mac")
    let (expires_value, have_expires) = find(fields, "expires")
    let (token_effect, effect_is_text) = text_of(effect_value)
    let (token_scope, scope_is_text) = text_of(scope_value)
    let (token_policy, policy_is_text) = text_of(policy_value)
    let (token_nonce, nonce_is_text) = text_of(nonce_value)
    let (token_mac, mac_is_text) = text_of(mac_value)
    if !(have_effect && have_scope && have_policy && have_nonce && have_mac && have_expires && effect_is_text && scope_is_text && policy_is_text && nonce_is_text && mac_is_text) { ret ("malformed", ok) }
    var expires = 0usize
    var expires_ok = false
    switch expires_value {
    case .Number as n:
        expires_ok = n.lexeme.len > 0usize && n.lexeme.len < 19usize
        var at = 0usize
        while at < n.lexeme.len {
            if n.lexeme[at] < 48u8 || n.lexeme[at] > 57u8 { expires_ok = false } else { expires = expires * 10usize + usize(n.lexeme[at] - 48u8) }
            at += 1usize
        }
    default:
        expires_ok = false
    }
    if !expires_ok { ret ("malformed", ok) }
    // The mac covers the token without itself, in canonical form.
    let (body, body_error) = mem.alloc[json.Member](a, 6usize)
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
    if !str.eq(expected, token_mac) { ret ("bad-mac", ok) }
    if !str.eq(token_policy, policy_hash) { ret ("wrong-policy", ok) }
    if !str.eq(token_effect, effect) || !str.eq(token_scope, scope) { ret ("wrong-scope", ok) }
    if now > expires { ret ("expired", ok) }
    if in_list(seen, token_nonce) { ret ("replayed", ok) }
    ret ("valid", ok)
}

// `text` with every occurrence of each non-empty secret replaced by `[redacted]`, in list order.
fn redact(a: *mem.Arena, text: str, secrets: []const str) -> (str, err) {
    var current = text
    var at = 0usize
    while at < secrets.len {
        if secrets[at].len > 0usize {
            let (next, replace_error) = str.replace(a, current, secrets[at], "[redacted]")
            if replace_error != ok { ret ("", replace_error) }
            current = next
        }
        at += 1usize
    }
    ret (current, ok)
}
