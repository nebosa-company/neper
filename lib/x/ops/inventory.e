// Host facts and inventory helpers (L050), after Petcow's `facts.rs`, `inventory.rs` and `naming.rs::sanitize`:
// `parse_facts` turns `key=value` lines (CRLF-safe, an integer value coerced to a number, the text after the first `=` kept,
// blank and malformed lines skipped) into a fact map; `custom_fact_script` is the first-line-only capture script for
// user-declared facts; `resolve` and `select` read an inventory document (hosts, groups, dynamic sources; unknown keys
// refused) into hosts sorted by name with group variables merged in listed order under host variables, optionally filtered
// by group and by a variable's text; `synthesize_hosts` turns observed cloud resources into hosts (address from an
// attribute, a group per type, optional group and tag-derived group, scalar attributes and string tags as variables, the
// resource id passed through, a resource without an address skipped). A shape error reads
// `invalid inventory: <what>`.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.mem
use e.str

type Doc = struct { valid: bool, message: str, names: []const str, addresses: []const str, host_groups: []const []const str, host_vars: []const json.Value, group_names: []const str, group_vars: []const json.Value }

type Host = struct { name: str, address: str, groups: []const str, vars: json.Value }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn new_obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    ret o
}

fn is_ws(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 11u8 || c == 12u8 || c == 13u8 }

fn trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && is_ws(s[from]) { from += 1usize }
    while to > from && is_ws(s[to - 1usize]) { to -= 1usize }
    ret s[from..to]
}

// Rust's `i64` parse: an optional sign and decimal digits, in range.
fn parse_i64(s: str) -> (i64, bool) {
    if s.len == 0usize { ret (0i64, false) }
    var i = 0usize
    var negative = false
    if s[0] == 45u8 {
        negative = true
        i = 1usize
    } else if s[0] == 43u8 {
        i = 1usize
    }
    if i >= s.len { ret (0i64, false) }
    var value = 0i64
    while i < s.len {
        let c = s[i]
        if c < 48u8 || c > 57u8 { ret (0i64, false) }
        let d = i64(c - 48u8)
        if negative {
            if value < -922337203685477580i64 || (value == -922337203685477580i64 && d > 8i64) { ret (0i64, false) }
            value = value * 10i64 - d
        } else {
            if value > 922337203685477580i64 || (value == 922337203685477580i64 && d > 7i64) { ret (0i64, false) }
            value = value * 10i64 + d
        }
        i += 1usize
    }
    ret (value, true)
}

// The facts in a script's output, as an object (a later duplicate key wins).
fn parse_facts(a: *mem.Arena, stdout: str) -> json.Value {
    var out = new_obj(a)
    var start = 0usize
    var i = 0usize
    while i <= stdout.len {
        if i == stdout.len || stdout[i] == 10u8 {
            if i > start || i == stdout.len {
                var line = stdout[start..i]
                if line.len > 0usize && line[line.len - 1usize] == 13u8 { line = line[0usize..line.len - 1usize] }
                line = trim(line)
                var eq = -1i64
                var k = 0usize
                while k < line.len {
                    if line[k] == 61u8 {
                        eq = i64(k)
                        break
                    }
                    k += 1usize
                }
                if line.len > 0usize && eq >= 0i64 {
                    let key = trim(line[0usize..usize(eq)])
                    let value = trim(line[usize(eq) + 1usize..])
                    if key.len > 0usize {
                        let (n, is_int) = parse_i64(value)
                        if is_int {
                            put(&out, key, json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(n)) } })
                        } else {
                            put(&out, key, sv(value))
                        }
                    }
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret ir.obj_value(&out)
}

// A shell script that prints each declared fact's first output line, in name order.
fn custom_fact_script(a: *mem.Arena, names: []const str, commands: []const str) -> str {
    let (order, e) = mem.alloc[usize](a, names.len + 1usize)
    var i = 0usize
    while i < names.len {
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < names.len {
        let cur = order[i]
        var j = i
        while j > 0usize && str.compare(names[order[j - 1usize]], names[cur]) > 0i32 {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = cur
        i += 1usize
    }
    var out = ""
    i = 0usize
    while i < names.len {
        let k = order[i]
        out = join(a, out, join(a, join(a, "echo \"", names[k]), join(a, "=$(", join(a, commands[k], " | head -n1)\"\n"))))
        i += 1usize
    }
    ret out
}

// `[a-z0-9]` runs joined by single dashes, lower-cased ASCII only, edge dashes trimmed.
fn sanitize(a: *mem.Arena, token: str) -> str {
    let (out, e) = mem.alloc[u8](a, token.len + 1usize)
    var n = 0usize
    var last_dash = false
    var i = 0usize
    while i < token.len {
        var c = token[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        if (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) {
            out[n] = c
            n += 1usize
            last_dash = false
        } else if !last_dash {
            out[n] = 45u8
            n += 1usize
            last_dash = true
        }
        i += 1usize
    }
    var from = 0usize
    var to = n
    while from < to && out[from] == 45u8 { from += 1usize }
    while to > from && out[to - 1usize] == 45u8 { to -= 1usize }
    ret out[from..to]
}

fn bad(a: *mem.Arena, what: str) -> Doc {
    let none_texts: []const str = zero
    let none_lists: []const []const str = zero
    let none_vars: []const json.Value = zero
    ret Doc { valid: false, message: join(a, "invalid inventory: ", what), names: none_texts, addresses: none_texts, host_groups: none_lists, host_vars: none_vars, group_names: none_texts, group_vars: none_vars }
}

fn key_text(v: yaml.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

// A YAML value as JSON (numbers by their value, nested maps and lists kept).
fn to_json(a: *mem.Arena, v: yaml.Value) -> json.Value {
    switch v {
    case .Null:
        ret .Null
    case .Bool as b:
        ret json.Value{ Bool: b }
    case .Integer as n:
        ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(n)) } }
    case .Float as x:
        ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, x) } }
    case .String as s:
        ret sv(s)
    case .Sequence as xs:
        let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
        var i = 0usize
        while i < xs.len {
            out[i] = to_json(a, xs[i])
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..xs.len] }
    case .Mapping as m:
        var o = new_obj(a)
        var i = 0usize
        while i < m.len {
            let (k, is_text) = key_text(m[i].key)
            if is_text { put(&o, k, to_json(a, m[i].value)) }
            i += 1usize
        }
        ret ir.obj_value(&o)
    default:
        ret .Null
    }
}

fn mapping_of(v: yaml.Value) -> ([]const yaml.Pair, bool) {
    switch v {
    case .Mapping as m:
        ret (m, true)
    case .Null:
        ret (zero, true)
    default:
        ret (zero, false)
    }
}

fn find(m: []const yaml.Pair, name: str) -> (yaml.Value, bool) {
    var i = 0usize
    while i < m.len {
        let (k, is_text) = key_text(m[i].key)
        if is_text && str.eq(k, name) { ret (m[i].value, true) }
        i += 1usize
    }
    ret (.Null, false)
}

fn sort_indexes(a: *mem.Arena, names: []const str) -> []usize {
    let (order, e) = mem.alloc[usize](a, names.len + 1usize)
    var i = 0usize
    while i < names.len {
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < names.len {
        let cur = order[i]
        var j = i
        while j > 0usize && str.compare(names[order[j - 1usize]], names[cur]) > 0i32 {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = cur
        i += 1usize
    }
    ret order[0usize..names.len]
}

// An inventory document: hosts (address required, groups, vars), groups (vars) and dynamic sources, unknown keys refused.
fn parse_inventory(a: *mem.Arena, source: str) -> Doc {
    let (root, pe) = yaml.parse(a, source, yaml.Options { max_depth: 64u16, allow_duplicate_keys: false })
    if pe != ok { ret bad(a, "failed to parse") }
    let (top, is_map) = mapping_of(root)
    if !is_map { ret bad(a, "expected a map") }
    var i = 0usize
    while i < top.len {
        let (k, is_text) = key_text(top[i].key)
        if !is_text || !(str.eq(k, "hosts") || str.eq(k, "groups") || str.eq(k, "dynamic")) { ret bad(a, join(a, "unknown field `", join(a, k, "`"))) }
        i += 1usize
    }
    let (hosts_v, has_hosts) = find(top, "hosts")
    let (hosts, hosts_ok) = mapping_of(hosts_v)
    if !hosts_ok { ret bad(a, "hosts: expected a map") }
    let (groups_v, has_groups) = find(top, "groups")
    let (groups, groups_ok) = mapping_of(groups_v)
    if !groups_ok { ret bad(a, "groups: expected a map") }
    let (dyn_v, has_dyn) = find(top, "dynamic")
    if has_dyn {
        switch dyn_v {
        case .Sequence as ds:
            var q = 0usize
            while q < ds.len {
                let (dm, dm_ok) = mapping_of(ds[q])
                if !dm_ok { ret bad(a, "dynamic: expected maps") }
                let (cv, has_c) = find(dm, "cloud")
                let (tv, has_t) = find(dm, "type")
                if !has_c || !has_t { ret bad(a, "dynamic: missing field") }
                var p = 0usize
                while p < dm.len {
                    let (dk, dk_text) = key_text(dm[p].key)
                    if !dk_text || !(str.eq(dk, "cloud") || str.eq(dk, "type") || str.eq(dk, "address_from") || str.eq(dk, "group") || str.eq(dk, "group_from_tag") || str.eq(dk, "include_unmanaged")) {
                        ret bad(a, join(a, "dynamic: unknown field `", join(a, dk, "`")))
                    }
                    p += 1usize
                }
                q += 1usize
            }
        case .Null:
            q_noop()
        default:
            ret bad(a, "dynamic: expected a sequence")
        }
    }
    let (names, e1) = mem.alloc[str](a, hosts.len + 1usize)
    let (addresses, e2) = mem.alloc[str](a, hosts.len + 1usize)
    let (host_groups, e3) = mem.alloc[[]const str](a, hosts.len + 1usize)
    let (host_vars, e4) = mem.alloc[json.Value](a, hosts.len + 1usize)
    i = 0usize
    while i < hosts.len {
        let (name, name_text) = key_text(hosts[i].key)
        if !name_text { ret bad(a, "hosts: keys must be strings") }
        let (hm, hm_ok) = mapping_of(hosts[i].value)
        if !hm_ok { ret bad(a, join(a, join(a, "hosts.", name), ": expected a map")) }
        var p = 0usize
        while p < hm.len {
            let (hk, hk_text) = key_text(hm[p].key)
            if !hk_text || !(str.eq(hk, "address") || str.eq(hk, "groups") || str.eq(hk, "vars")) { ret bad(a, join(a, "host: unknown field `", join(a, hk, "`"))) }
            p += 1usize
        }
        let (av, has_a) = find(hm, "address")
        var address = ""
        var addr_ok = false
        if has_a {
            let (s, is_text) = key_text(av)
            address = s
            addr_ok = is_text
        }
        if !addr_ok { ret bad(a, join(a, join(a, "hosts.", name), ": missing field `address`")) }
        let (gv, has_g) = find(hm, "groups")
        var glist: []const str = zero
        if has_g {
            switch gv {
            case .Sequence as gs:
                let (gout, ge) = mem.alloc[str](a, gs.len + 1usize)
                var q = 0usize
                while q < gs.len {
                    let (s, is_text) = key_text(gs[q])
                    if !is_text { ret bad(a, "groups: expected strings") }
                    gout[q] = s
                    q += 1usize
                }
                glist = gout[0usize..gs.len]
            case .Null:
                q_noop()
            default:
                ret bad(a, "groups: expected a sequence")
            }
        }
        let (vv, has_v) = find(hm, "vars")
        var vars = ir.empty_object()
        if has_v {
            let (vm, vm_ok) = mapping_of(vv)
            if !vm_ok { ret bad(a, "vars: expected a map") }
            vars = to_json(a, vv)
            switch vv {
            case .Null:
                vars = ir.empty_object()
            default:
                q_noop()
            }
        }
        names[i] = name
        addresses[i] = address
        host_groups[i] = glist
        host_vars[i] = vars
        i += 1usize
    }
    let (gnames, e5) = mem.alloc[str](a, groups.len + 1usize)
    let (gvars, e6) = mem.alloc[json.Value](a, groups.len + 1usize)
    i = 0usize
    while i < groups.len {
        let (name, name_text) = key_text(groups[i].key)
        if !name_text { ret bad(a, "groups: keys must be strings") }
        let (gm, gm_ok) = mapping_of(groups[i].value)
        if !gm_ok { ret bad(a, join(a, join(a, "groups.", name), ": expected a map")) }
        var p = 0usize
        while p < gm.len {
            let (gk, gk_text) = key_text(gm[p].key)
            if !gk_text || !str.eq(gk, "vars") { ret bad(a, join(a, "group: unknown field `", join(a, gk, "`"))) }
            p += 1usize
        }
        let (vv, has_v) = find(gm, "vars")
        gnames[i] = name
        gvars[i] = ir.empty_object()
        if has_v {
            let (vm, vm_ok) = mapping_of(vv)
            if !vm_ok { ret bad(a, "vars: expected a map") }
            switch vv {
            case .Null:
                q_noop()
            default:
                gvars[i] = to_json(a, vv)
            }
        }
        i += 1usize
    }
    ret Doc { valid: true, message: "", names: names[0usize..hosts.len], addresses: addresses[0usize..hosts.len], host_groups: host_groups[0usize..hosts.len], host_vars: host_vars[0usize..hosts.len], group_names: gnames[0usize..groups.len], group_vars: gvars[0usize..groups.len] }
}

fn q_noop() {
    let unused = 0usize
}

// Every host with group variables (in the host's listed group order) under its own, sorted by name.
fn resolve(a: *mem.Arena, d: Doc) -> []Host {
    let order = sort_indexes(a, d.names)
    let (out, e) = mem.alloc[Host](a, d.names.len + 1usize)
    var i = 0usize
    while i < order.len {
        let h = order[i]
        var vars = new_obj(a)
        var g = 0usize
        while g < d.host_groups[h].len {
            var k = 0usize
            while k < d.group_names.len {
                if str.eq(d.group_names[k], d.host_groups[h][g]) {
                    let ae = ir.assign(&vars, d.group_vars[k])
                }
                k += 1usize
            }
            g += 1usize
        }
        let be = ir.assign(&vars, d.host_vars[h])
        out[i] = Host { name: d.names[h], address: d.addresses[h], groups: d.host_groups[h], vars: ir.obj_value(&vars) }
        i += 1usize
    }
    ret out[0usize..order.len]
}

fn scalar_text(a: *mem.Arena, v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Number as n:
        ret n.lexeme
    default:
        ret ""
    }
}

// The resolved hosts, in a group and/or with a variable whose text equals `want`.
fn select(a: *mem.Arena, d: Doc, group: str, has_group: bool, var_key: str, var_value: str, has_var: bool) -> []const Host {
    let all = resolve(a, d)
    let (out, e) = mem.alloc[Host](a, all.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < all.len {
        var keep = true
        if has_group {
            var found = false
            var g = 0usize
            while g < all[i].groups.len {
                if str.eq(all[i].groups[g], group) { found = true }
                g += 1usize
            }
            keep = found
        }
        if keep && has_var {
            let (v, present) = ir.get(all[i].vars, var_key)
            keep = present && str.eq(scalar_text(a, v), var_value)
        }
        if keep {
            out[n] = all[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

type Source = struct { type_name: str, address_from: str, has_group: bool, group: str, has_group_from_tag: bool, group_from_tag: str }

type Observed = struct { name: str, attributes: json.Value, has_real_id: bool, real_id: str }

// Hosts for observed resources, keyed by resource name (a later duplicate replaces an earlier one).
fn synthesize_hosts(a: *mem.Arena, source: Source, observed: []const Observed) -> ([]const str, []const Host) {
    let (names, e1) = mem.alloc[str](a, observed.len + 1usize)
    let (hosts, e2) = mem.alloc[Host](a, observed.len + 1usize)
    let type_group = sanitize(a, source.type_name)
    var n = 0usize
    var i = 0usize
    while i < observed.len {
        let o = observed[i]
        i += 1usize
        let (av, has_a) = ir.get(o.attributes, source.address_from)
        if !has_a { continue }
        let (address, is_text) = ir.string_of(av)
        if !is_text { continue }
        let (tags_v, has_tags) = ir.get(o.attributes, "tags")
        var tags = ir.empty_object()
        if has_tags {
            let (tm, is_object) = ir.members_of(tags_v)
            if is_object { tags = tags_v }
        }
        let (gout, ge) = mem.alloc[str](a, 4usize)
        var gn = 0usize
        gout[gn] = type_group
        gn += 1usize
        if source.has_group {
            gout[gn] = source.group
            gn += 1usize
        }
        if source.has_group_from_tag {
            let (tv, has_t) = ir.get(tags, source.group_from_tag)
            if has_t {
                let (ts, t_text) = ir.string_of(tv)
                if t_text {
                    gout[gn] = sanitize(a, ts)
                    gn += 1usize
                }
            }
        }
        var vars = new_obj(a)
        let (members, is_obj) = ir.members_of(o.attributes)
        var k = 0usize
        while k < members.len {
            var nested = false
            switch members[k].value {
            case .Object as m:
                nested = true
            case .Array as xs:
                nested = true
            default:
                nested = false
            }
            if !str.eq(members[k].key, "tags") && !nested { put(&vars, members[k].key, members[k].value) }
            k += 1usize
        }
        let (tmembers, t_obj) = ir.members_of(tags)
        k = 0usize
        while k < tmembers.len {
            let (s, s_text) = ir.string_of(tmembers[k].value)
            if s_text { put(&vars, tmembers[k].key, tmembers[k].value) }
            k += 1usize
        }
        if o.has_real_id { put(&vars, "resource_id", sv(o.real_id)) }
        var at = n
        var q = 0usize
        while q < n {
            if str.eq(names[q], o.name) { at = q }
            q += 1usize
        }
        names[at] = o.name
        hosts[at] = Host { name: o.name, address: address, groups: gout[0usize..gn], vars: ir.obj_value(&vars) }
        if at == n { n += 1usize }
    }
    let order = sort_indexes(a, names[0usize..n])
    let (sorted_names, e3) = mem.alloc[str](a, n + 1usize)
    let (sorted_hosts, e4) = mem.alloc[Host](a, n + 1usize)
    var s = 0usize
    while s < n {
        sorted_names[s] = names[order[s]]
        sorted_hosts[s] = hosts[order[s]]
        s += 1usize
    }
    ret (sorted_names[0usize..n], sorted_hosts[0usize..n])
}
