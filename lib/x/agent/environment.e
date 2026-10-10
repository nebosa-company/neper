// The execution environment manifest (T042, H37): every ambient input a check, build, run or test depended on, named so it
// takes part in cache identity and in a receipt. A manifest is a JSON document with a deterministic core -- tools and their
// hashes, platform, dependency lock, readable and writable roots, the inherited environment as name to value hash (never
// a plaintext value), locale, timezone, clock, random and network policy, resource limits and external services -- and a
// free `observation` object (host name, timestamps) that is kept apart and never part of the identity.
//
// `parse` validates fail-closed, `identity` is the lowercase SHA-256 of the core's canonical text, and `level` is what the
// run can claim: "hermetic" when every input is declared and controlled, "observed" when some input is only recorded or
// bounded (a network allowlist, a monotonic-only clock, a listed observed input), "uncontrolled" when one is neither
// (a real clock, an OS random source, an open network, an undeclared input, a listed uncontrolled input). A field the
// manifest does not carry is an omission and makes the level uncontrolled: an undeclared dependency cannot produce a
// hermetic result. `permits` says whether a level satisfies what a contract requires, hermetic above observed above
// uncontrolled.
//
// Memory: the arena is retained; the manifest's strings live in it.

use e.crypto.hash
use e.fmt.json as json
use e.mem
use e.str
use x.agent.contract as contract

error Invalid

type Environment = struct {
    canonical: str,
    identity: str,
    level: str,
    omissions: []const str,
}

const MAX_DEPTH: u16 = 8u16

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

fn is_nonnegative_integer(v: json.Value) -> bool {
    var good = false
    switch v {
    case .Number as n:
        good = n.lexeme.len > 0usize
        var at = 0usize
        while at < n.lexeme.len {
            if n.lexeme[at] < 48u8 || n.lexeme[at] > 57u8 { good = false }
            at += 1usize
        }
    default:
        good = false
    }
    ret good
}

fn only_text_items(v: json.Value) -> bool {
    let (items, is_array) = items_of(v)
    if !is_array { ret false }
    var at = 0usize
    while at < items.len {
        let (text, is_text) = text_of(items[at])
        if !is_text { ret false }
        at += 1usize
    }
    ret true
}

// 0 hermetic, 1 observed, 2 uncontrolled.
fn level_name(rank: usize) -> str {
    if rank == 0usize { ret "hermetic" }
    if rank == 1usize { ret "observed" }
    ret "uncontrolled"
}

fn rank_of(level: str) -> usize {
    if str.eq(level, "hermetic") { ret 0usize }
    if str.eq(level, "observed") { ret 1usize }
    ret 2usize
}

// A policy field: its value must be one of three spellings, ranked 0, 1, 2 (an empty spelling is not offered).
fn policy_rank(core: []const json.Member, key: str, hermetic: str, observed: str, uncontrolled: str) -> (usize, bool, bool) {
    let (v, present) = find(core, key)
    if !present { ret (2usize, false, true) }
    let (text, is_text) = text_of(v)
    if !is_text { ret (2usize, true, false) }
    if str.eq(text, hermetic) { ret (0usize, true, true) }
    if observed.len > 0usize && str.eq(text, observed) { ret (1usize, true, true) }
    if str.eq(text, uncontrolled) { ret (2usize, true, true) }
    ret (2usize, true, false)
}

fn parse(a: *mem.Arena, text: str) -> (Environment, err) {
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: MAX_DEPTH })
    if parse_error != ok { ret (zero, Invalid) }
    let (top, is_object) = members_of(root)
    if !is_object { ret (zero, Invalid) }
    var allowed: [16]str = zero
    allowed[0] = "schema"
    allowed[1] = "version"
    allowed[2] = "tools"
    allowed[3] = "platform"
    allowed[4] = "lock"
    allowed[5] = "roots"
    allowed[6] = "env"
    allowed[7] = "locale"
    allowed[8] = "timezone"
    allowed[9] = "clock"
    allowed[10] = "random"
    allowed[11] = "network"
    allowed[12] = "limits"
    allowed[13] = "services"
    allowed[14] = "observed"
    allowed[15] = "uncontrolled"
    var at = 0usize
    while at < top.len {
        var known = false
        var k = 0usize
        while k < 16usize {
            if str.eq(top[at].key, allowed[k]) { known = true }
            k += 1usize
        }
        if !known && !str.eq(top[at].key, "observation") { ret (zero, Invalid) }
        at += 1usize
    }
    let (schema, have_schema) = find(top, "schema")
    let (schema_text, schema_is_text) = text_of(schema)
    if !have_schema || !schema_is_text || !str.eq(schema_text, "neper-environment") { ret (zero, Invalid) }
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
    // Omissions: the core fields this manifest does not carry.
    var required: [11]str = zero
    required[0] = "tools"
    required[1] = "platform"
    required[2] = "lock"
    required[3] = "roots"
    required[4] = "env"
    required[5] = "locale"
    required[6] = "timezone"
    required[7] = "clock"
    required[8] = "random"
    required[9] = "network"
    required[10] = "limits"
    let (omitted, omitted_error) = mem.alloc[str](a, 13usize)
    if omitted_error != ok { ret (zero, omitted_error) }
    var omission_count = 0usize
    var rank = 0usize
    var field = 0usize
    while field < 11usize {
        let (v, present) = find(top, required[field])
        if !present {
            omitted[omission_count] = required[field]
            omission_count += 1usize
            rank = 2usize
        }
        field += 1usize
    }
    let (services_value, have_services) = find(top, "services")
    if !have_services {
        omitted[omission_count] = "services"
        omission_count += 1usize
        rank = 2usize
    }
    // Shapes of what is present.
    let (tools_value, have_tools) = find(top, "tools")
    if have_tools {
        let (tools, tools_are_array) = items_of(tools_value)
        if !tools_are_array || tools.len == 0usize { ret (zero, Invalid) }
        var t = 0usize
        while t < tools.len {
            let (tool, tool_is_object) = members_of(tools[t])
            if !tool_is_object || tool.len != 2usize { ret (zero, Invalid) }
            let (name, have_name) = find(tool, "name")
            let (name_text, name_is_text) = text_of(name)
            let (digest, have_digest) = find(tool, "sha256")
            let (digest_text, digest_is_text) = text_of(digest)
            if !(have_name && name_is_text && name_text.len > 0usize && have_digest && digest_is_text && is_hex64(digest_text)) { ret (zero, Invalid) }
            t += 1usize
        }
    }
    let (platform_value, have_platform) = find(top, "platform")
    if have_platform {
        let (platform, platform_is_object) = members_of(platform_value)
        if !platform_is_object || platform.len != 2usize { ret (zero, Invalid) }
        let (os_value, have_os) = find(platform, "os")
        let (arch_value, have_arch) = find(platform, "arch")
        let (os_text, os_is_text) = text_of(os_value)
        let (arch_text, arch_is_text) = text_of(arch_value)
        if !(have_os && have_arch && os_is_text && arch_is_text && os_text.len > 0usize && arch_text.len > 0usize) { ret (zero, Invalid) }
    }
    let (lock_value, have_lock) = find(top, "lock")
    if have_lock {
        let (lock_text, lock_is_text) = text_of(lock_value)
        if !lock_is_text || !(is_hex64(lock_text) || str.eq(lock_text, "none")) { ret (zero, Invalid) }
    }
    let (roots_value, have_roots) = find(top, "roots")
    if have_roots {
        let (roots, roots_are_object) = members_of(roots_value)
        if !roots_are_object || roots.len != 2usize { ret (zero, Invalid) }
        let (read_value, have_read) = find(roots, "read")
        let (write_value, have_write) = find(roots, "write")
        if !(have_read && have_write && only_text_items(read_value) && only_text_items(write_value)) { ret (zero, Invalid) }
    }
    let (env_value, have_env) = find(top, "env")
    if have_env {
        let (env, env_is_object) = members_of(env_value)
        if !env_is_object { ret (zero, Invalid) }
        var e = 0usize
        while e < env.len {
            let (value_text, value_is_text) = text_of(env[e].value)
            // A secret is never a plaintext: every value is `sha256:` and the digest.
            if !value_is_text || value_text.len != 71usize || !str.eq(value_text[0usize..7usize], "sha256:") || !is_hex64(value_text[7usize..71usize]) { ret (zero, Invalid) }
            e += 1usize
        }
    }
    var text_fields: [2]str = zero
    text_fields[0] = "locale"
    text_fields[1] = "timezone"
    var tf = 0usize
    while tf < 2usize {
        let (v, present) = find(top, text_fields[tf])
        if present {
            let (value, is_text) = text_of(v)
            if !is_text || value.len == 0usize { ret (zero, Invalid) }
        }
        tf += 1usize
    }
    let (limits_value, have_limits) = find(top, "limits")
    if have_limits {
        let (limits, limits_are_object) = members_of(limits_value)
        if !limits_are_object { ret (zero, Invalid) }
        var l = 0usize
        while l < limits.len {
            if !is_nonnegative_integer(limits[l].value) { ret (zero, Invalid) }
            l += 1usize
        }
    }
    if have_services && !only_text_items(services_value) { ret (zero, Invalid) }
    let (observed_value, have_observed) = find(top, "observed")
    if have_observed {
        if !only_text_items(observed_value) { ret (zero, Invalid) }
        let (listed, listed_is_array) = items_of(observed_value)
        if listed_is_array && listed.len > 0usize && rank < 1usize { rank = 1usize }
    }
    let (uncontrolled_value, have_uncontrolled) = find(top, "uncontrolled")
    if have_uncontrolled {
        if !only_text_items(uncontrolled_value) { ret (zero, Invalid) }
        let (listed, listed_is_array) = items_of(uncontrolled_value)
        if listed_is_array && listed.len > 0usize { rank = 2usize }
    }
    let (clock_rank, clock_present, clock_ok) = policy_rank(top, "clock", "fixed", "monotonic", "real")
    let (random_rank, random_present, random_ok) = policy_rank(top, "random", "seeded", "", "os")
    let (network_rank, network_present, network_ok) = policy_rank(top, "network", "none", "allowlist", "open")
    if !clock_ok || !random_ok || !network_ok { ret (zero, Invalid) }
    if clock_present && clock_rank > rank { rank = clock_rank }
    if random_present && random_rank > rank { rank = random_rank }
    if network_present && network_rank > rank { rank = network_rank }
    // The deterministic core: every member but the observation.
    let (core_members, core_error) = mem.alloc[json.Member](a, top.len + 1usize)
    if core_error != ok { ret (zero, core_error) }
    var core_count = 0usize
    var m = 0usize
    while m < top.len {
        if !str.eq(top[m].key, "observation") {
            core_members[core_count] = top[m]
            core_count += 1usize
        }
        m += 1usize
    }
    let core = json.Value{ Object: core_members[0usize..core_count] }
    let (canonical, canonical_error) = contract.canonical_json(a, core)
    if canonical_error != ok { ret (zero, Invalid) }
    let digest = hash.sha256(canonical)
    let (identity, identity_error) = contract.hex_of(a, digest)
    if identity_error != ok { ret (zero, identity_error) }
    ret (Environment { canonical: canonical, identity: identity, level: level_name(rank), omissions: omitted[0usize..omission_count] }, ok)
}

// Whether a run at `level` can verify an obligation that requires `required`: hermetic satisfies every requirement,
// observed satisfies observed and uncontrolled ones, and an uncontrolled run satisfies only an uncontrolled one.
fn permits(level: str, required: str) -> bool { ret rank_of(level) <= rank_of(required) }
