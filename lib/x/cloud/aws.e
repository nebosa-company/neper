// AWS Cloud Control identity and request shaping (L048), after Petcow's `provider/aws/cloudcontrol.rs`: the catalogue
// entry (`Def`: CloudFormation type, the name property or a tag-indexed identity, tag shape and property, composite
// identifier components, derived attributes, parent link) read from an operator manifest and merged over the built-ins by
// type; the composite identifier joined with `|` in schema order and read back; the `DesiredState` document for a
// name-addressable and a tag-indexed type; the tags with PetCow's `petcow:managed`/`petcow:name` identity stamped in
// (a user's tags kept, ours winning on key) in both the `[{Key,Value}]` and the map shape; the PetCow name read from
// observed tags; the JSON-Patch documents for update; the identity tags stripped from observed attributes; throttling
// detection. Everything that needs the AWS SDK is host code.
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.mem
use e.str

type Parent = struct { petcow_type: str, property: str }

type Def = struct { petcow_type: str, cfn_type: str, has_name_property: bool, name_property: str, tag_map: bool, has_tag_property: bool, tag_property: str, has_identity: bool, identity: []const str, has_derived: bool, derived: []const str, has_parent: bool, parent: Parent }

type Defs = struct { valid: bool, message: str, defs: []const Def }

type Text = struct { valid: bool, message: str, value: str }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn managed_tag() -> str { ret "petcow:managed" }

fn name_tag() -> str { ret "petcow:name" }

// Whether an error string is Cloud Control refusing for rate reasons.
fn is_throttle(msg: str) -> bool {
    ret str.contains(msg, "ThrottlingException") || str.contains(msg, "Rate exceeded") || str.contains(msg, "TooManyRequests")
}

// --- the catalogue -------------------------------------------------------------------------------------------

fn failed_defs(a: *mem.Arena, what: str) -> Defs {
    let none: []const Def = zero
    ret Defs { valid: false, message: join(a, "invalid document: aws.cc manifest: ", what), defs: none }
}

fn text_field(v: yaml.Value) -> (str, bool, bool) {
    switch v {
    case .String as s:
        ret (s, true, true)
    case .Null:
        ret ("", false, true)
    default:
        ret ("", false, false)
    }
}

fn map_find(m: []const yaml.Pair, name: str) -> (yaml.Value, bool) {
    var i = 0usize
    while i < m.len {
        switch m[i].key {
        case .String as k:
            if str.eq(k, name) { ret (m[i].value, true) }
        default:
            i += 0usize
        }
        i += 1usize
    }
    ret (.Null, false)
}

fn string_list(a: *mem.Arena, v: yaml.Value) -> ([]const str, bool) {
    switch v {
    case .Sequence as xs:
        let (out, e) = mem.alloc[str](a, xs.len + 1usize)
        var i = 0usize
        while i < xs.len {
            switch xs[i] {
            case .String as s:
                out[i] = s
            default:
                ret (zero, false)
            }
            i += 1usize
        }
        ret (out[0usize..xs.len], true)
    default:
        ret (zero, false)
    }
}

fn def_of(a: *mem.Arena, v: yaml.Value) -> (Def, str, bool) {
    var d = Def {
        petcow_type: "", cfn_type: "", has_name_property: false, name_property: "", tag_map: false, has_tag_property: false, tag_property: "",
        has_identity: false, identity: zero, has_derived: false, derived: zero, has_parent: false, parent: Parent { petcow_type: "", property: "" },
    }
    var members: []const yaml.Pair = zero
    switch v {
    case .Mapping as m:
        members = m
    default:
        ret (d, "invalid type, expected struct CcResourceDef", false)
    }
    var i = 0usize
    while i < members.len {
        var key = ""
        switch members[i].key {
        case .String as k:
            key = k
        default:
            ret (d, "invalid key", false)
        }
        let value = members[i].value
        if str.eq(key, "type") {
            let (s, has, good) = text_field(value)
            if !good || !has { ret (d, "invalid type for `type`", false) }
            d.petcow_type = s
        } else if str.eq(key, "cfn_type") {
            let (s, has, good) = text_field(value)
            if !good || !has { ret (d, "invalid type for `cfn_type`", false) }
            d.cfn_type = s
        } else if str.eq(key, "name_property") {
            let (s, has, good) = text_field(value)
            if !good { ret (d, "invalid type for `name_property`", false) }
            d.name_property = s
            d.has_name_property = has
        } else if str.eq(key, "tag_shape") {
            let (s, has, good) = text_field(value)
            if !good || !has { ret (d, "invalid type for `tag_shape`", false) }
            if str.eq(s, "map") {
                d.tag_map = true
            } else if !str.eq(s, "kv_list") {
                ret (d, "unknown variant for `tag_shape`", false)
            }
        } else if str.eq(key, "tag_property") {
            let (s, has, good) = text_field(value)
            if !good { ret (d, "invalid type for `tag_property`", false) }
            d.tag_property = s
            d.has_tag_property = has
        } else if str.eq(key, "identity_properties") {
            let (xs, good) = string_list(a, value)
            switch value {
            case .Null:
                d.has_identity = false
            default:
                if !good { ret (d, "invalid type for `identity_properties`", false) }
                d.identity = xs
                d.has_identity = true
            }
        } else if str.eq(key, "derived_attrs") {
            let (xs, good) = string_list(a, value)
            switch value {
            case .Null:
                d.has_derived = false
            default:
                if !good { ret (d, "invalid type for `derived_attrs`", false) }
                d.derived = xs
                d.has_derived = true
            }
        } else if str.eq(key, "parent") {
            switch value {
            case .Null:
                d.has_parent = false
            case .Mapping as pm:
                let (pt, has_pt) = map_find(pm, "type")
                let (pp, has_pp) = map_find(pm, "property")
                let (ts, th, tg) = text_field(pt)
                let (ps, ph, pg) = text_field(pp)
                if !has_pt || !tg || !th { ret (d, "parent: missing or invalid field `type`", false) }
                if !has_pp || !pg || !ph { ret (d, "parent: missing or invalid field `property`", false) }
                var q = 0usize
                while q < pm.len {
                    switch pm[q].key {
                    case .String as pk:
                        if !str.eq(pk, "type") && !str.eq(pk, "property") { ret (d, "parent: unknown field", false) }
                    default:
                        ret (d, "parent: invalid key", false)
                    }
                    q += 1usize
                }
                d.has_parent = true
                d.parent = Parent { petcow_type: ts, property: ps }
            default:
                ret (d, "invalid type for `parent`", false)
            }
        } else {
            ret (d, "unknown field", false)
        }
        i += 1usize
    }
    if d.petcow_type.len == 0usize { ret (d, "missing field `type`", false) }
    if d.cfn_type.len == 0usize { ret (d, "missing field `cfn_type`", false) }
    ret (d, "", true)
}

// A YAML list of definitions (one operator manifest file).
fn parse_defs(a: *mem.Arena, source: str) -> Defs {
    let (root, pe) = yaml.parse(a, source, yaml.Options { max_depth: 64u16, allow_duplicate_keys: false })
    if pe != ok { ret failed_defs(a, "failed to parse") }
    var items: []const yaml.Value = zero
    switch root {
    case .Sequence as xs:
        items = xs
    default:
        ret failed_defs(a, "invalid type, expected a sequence")
    }
    let (out, e) = mem.alloc[Def](a, items.len + 1usize)
    var i = 0usize
    while i < items.len {
        let (d, message, good) = def_of(a, items[i])
        if !good { ret failed_defs(a, message) }
        out[i] = d
        i += 1usize
    }
    ret Defs { valid: true, message: "", defs: out[0usize..items.len] }
}

// Built-ins with operator entries on top: one entry per type, the operator's winning, in type order.
fn merge_defs(a: *mem.Arena, defaults: []const Def, extra: []const Def) -> []const Def {
    let (out, e) = mem.alloc[Def](a, defaults.len + extra.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < defaults.len {
        var at = n
        var k = 0usize
        while k < n {
            if str.eq(out[k].petcow_type, defaults[i].petcow_type) { at = k }
            k += 1usize
        }
        out[at] = defaults[i]
        if at == n { n += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < extra.len {
        var at = n
        var k = 0usize
        while k < n {
            if str.eq(out[k].petcow_type, extra[i].petcow_type) { at = k }
            k += 1usize
        }
        out[at] = extra[i]
        if at == n { n += 1usize }
        i += 1usize
    }
    i = 1usize
    while i < n {
        let cur = out[i]
        var j = i
        while j > 0usize && str.compare(out[j - 1usize].petcow_type, cur.petcow_type) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..n]
}

// --- identifiers -----------------------------------------------------------------------------------------------

fn scalar_string(v: json.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    case .Number as n:
        ret (n.lexeme, true)
    case .Bool as b:
        if b { ret ("true", true) }
        ret ("false", true)
    default:
        ret ("", false)
    }
}

// The `|`-joined identifier of a composite type; the name component takes `name`, the others the parent attributes.
fn compose_identifier(a: *mem.Arena, identity: []const str, name_property: str, name: str, attrs: json.Value, petcow_type: str) -> Text {
    var out = ""
    var i = 0usize
    while i < identity.len {
        let prop = identity[i]
        var part = ""
        if str.eq(prop, name_property) {
            part = name
        } else {
            let (v, found) = ir.get(attrs, prop)
            var good = false
            if found {
                let (s, ok_s) = scalar_string(v)
                part = s
                good = ok_s
            }
            if !good {
                let msg = join(a, join(a, "composite identifier needs '", prop), "' (the parent) as an attribute — set it, typically to ${resources.<parent>.name}")
                ret Text { valid: false, message: join(a, join(a, join(a, "in resource '", petcow_type), "': "), msg), value: "" }
            }
            if str.contains(part, "|") {
                let msg = join(a, join(a, "'", prop), "' contains '|', which Cloud Control uses to separate identifier components")
                ret Text { valid: false, message: join(a, join(a, join(a, "in resource '", petcow_type), "': "), msg), value: "" }
            }
        }
        if i > 0usize { out = join(a, out, "|") }
        out = join(a, out, part)
        i += 1usize
    }
    ret Text { valid: true, message: "", value: out }
}

// The PetCow name a composite identifier carries, or false when it has the wrong number of components.
fn name_from_identifier(a: *mem.Arena, identity: []const str, name_property: str, identifier: str) -> (str, bool) {
    let (parts, e) = mem.alloc[str](a, identifier.len + 2usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= identifier.len {
        if i == identifier.len || identifier[i] == 124u8 {
            parts[n] = identifier[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if n != identity.len { ret ("", false) }
    i = 0usize
    while i < identity.len {
        if str.eq(identity[i], name_property) { ret (parts[i], true) }
        i += 1usize
    }
    ret ("", false)
}

// --- request documents -----------------------------------------------------------------------------------------

fn compact(a: *mem.Arena, v: json.Value) -> str {
    let (text, e) = chain.canonical_json(a, v)
    ret text
}

fn copy_without(a: *mem.Arena, attrs: json.Value, skip: str) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    var out = o
    let (members, is_object) = ir.members_of(attrs)
    var i = 0usize
    while i < members.len {
        if !str.eq(members[i].key, skip) { let pe = ir.put(&out, members[i].key, members[i].value) }
        i += 1usize
    }
    ret out
}

// `DesiredState` for a name-addressable type: the attributes plus the name in the identity property (the name wins).
fn desired_state_json(a: *mem.Arena, name_property: str, name: str, attrs: json.Value) -> str {
    var obj = copy_without(a, attrs, "")
    let pe = ir.put(&obj, name_property, sv(name))
    ret compact(a, ir.obj_value(&obj))
}

// A tag collection with PetCow's identity stamped in: the user's entries kept, `petcow:*` entries ours.
fn merged_tags(a: *mem.Arena, name: str, user_tags: json.Value, has_user: bool, map_shape: bool) -> json.Value {
    if !map_shape {
        let (items, is_array) = ir.items_of(user_tags)
        let (out, e) = mem.alloc[json.Value](a, items.len + 3usize)
        var n = 0usize
        if has_user && is_array {
            var i = 0usize
            while i < items.len {
                let (k, has) = ir.get(items[i], "Key")
                var drop = false
                if has {
                    let (ks, is_text) = ir.string_of(k)
                    if is_text && (str.eq(ks, managed_tag()) || str.eq(ks, name_tag())) { drop = true }
                }
                if !drop {
                    out[n] = items[i]
                    n += 1usize
                }
                i += 1usize
            }
        }
        var m = copy_without(a, ir.empty_object(), "")
        let p1 = ir.put(&m, "Key", sv(managed_tag()))
        let p2 = ir.put(&m, "Value", sv("true"))
        out[n] = ir.obj_value(&m)
        n += 1usize
        var t = copy_without(a, ir.empty_object(), "")
        let p3 = ir.put(&t, "Key", sv(name_tag()))
        let p4 = ir.put(&t, "Value", sv(name))
        out[n] = ir.obj_value(&t)
        n += 1usize
        ret json.Value{ Array: out[0usize..n] }
    }
    var obj = copy_without(a, ir.empty_object(), "")
    if has_user {
        let (members, is_object) = ir.members_of(user_tags)
        var i = 0usize
        while i < members.len {
            if !str.eq(members[i].key, managed_tag()) && !str.eq(members[i].key, name_tag()) {
                let pe = ir.put(&obj, members[i].key, members[i].value)
            }
            i += 1usize
        }
    }
    let p1 = ir.put(&obj, managed_tag(), sv("true"))
    let p2 = ir.put(&obj, name_tag(), sv(name))
    ret ir.obj_value(&obj)
}

// `DesiredState` for a tag-indexed type: the attributes, with the identity merged into the tag property.
fn desired_state_tagged(a: *mem.Arena, name: str, attrs: json.Value, map_shape: bool, tag_prop: str) -> str {
    var obj = copy_without(a, attrs, tag_prop)
    let (user, has_user) = ir.get(attrs, tag_prop)
    let pe = ir.put(&obj, tag_prop, merged_tags(a, name, user, has_user, map_shape))
    ret compact(a, ir.obj_value(&obj))
}

// The PetCow name in observed tags, when they also say `petcow:managed=true`.
fn managed_name_from_attrs(attrs: json.Value, map_shape: bool, tag_prop: str) -> (str, bool) {
    let (tags, found) = ir.get(attrs, tag_prop)
    if !found { ret ("", false) }
    var managed = false
    var name = ""
    var has_name = false
    if !map_shape {
        let (items, is_array) = ir.items_of(tags)
        if !is_array { ret ("", false) }
        var i = 0usize
        while i < items.len {
            let (k, has_k) = ir.get(items[i], "Key")
            let (v, has_v) = ir.get(items[i], "Value")
            var key = ""
            var have_key = false
            if has_k {
                let (s, is_text) = ir.string_of(k)
                key = s
                have_key = is_text
            }
            var val = ""
            var have_val = false
            if has_v {
                let (s, is_text) = ir.string_of(v)
                val = s
                have_val = is_text
            }
            if have_key && str.eq(key, managed_tag()) { managed = have_val && str.eq(val, "true") }
            if have_key && str.eq(key, name_tag()) {
                name = val
                has_name = have_val
            }
            i += 1usize
        }
    } else {
        let (members, is_object) = ir.members_of(tags)
        if !is_object { ret ("", false) }
        let (m, has_m) = ir.get(tags, managed_tag())
        if has_m {
            let (s, is_text) = ir.string_of(m)
            managed = is_text && str.eq(s, "true")
        }
        let (nv, has_nv) = ir.get(tags, name_tag())
        if has_nv {
            let (s, is_text) = ir.string_of(nv)
            name = s
            has_name = is_text
        }
    }
    if managed && has_name { ret (name, true) }
    ret ("", false)
}

fn sorted_members(a: *mem.Arena, attrs: json.Value) -> []const json.Member {
    let (members, is_object) = ir.members_of(attrs)
    let (out, e) = mem.alloc[json.Member](a, members.len + 1usize)
    var i = 0usize
    while i < members.len {
        out[i] = members[i]
        i += 1usize
    }
    i = 1usize
    while i < members.len {
        let cur = out[i]
        var j = i
        while j > 0usize && str.compare(out[j - 1usize].key, cur.key) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..members.len]
}

fn patch_op(a: *mem.Arena, key: str, value: json.Value) -> json.Value {
    var o = copy_without(a, ir.empty_object(), "")
    let p1 = ir.put(&o, "op", sv("add"))
    let p2 = ir.put(&o, "path", sv(join(a, "/", key)))
    let p3 = ir.put(&o, "value", value)
    ret ir.obj_value(&o)
}

// An RFC 6902 `add` per property, skipping the identity property; `[]` when nothing is left.
fn patch_document(a: *mem.Arena, name_property: str, has_name_property: bool, attrs: json.Value) -> str {
    let members = sorted_members(a, attrs)
    let (ops, e) = mem.alloc[json.Value](a, members.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < members.len {
        if !(has_name_property && str.eq(members[i].key, name_property)) {
            ops[n] = patch_op(a, members[i].key, members[i].value)
            n += 1usize
        }
        i += 1usize
    }
    ret compact(a, json.Value{ Array: ops[0usize..n] })
}

fn listed(xs: []const str, key: str) -> bool {
    var i = 0usize
    while i < xs.len {
        if str.eq(xs[i], key) { ret true }
        i += 1usize
    }
    ret false
}

// The same for a composite type: every identifier component is skipped.
fn patch_document_skipping(a: *mem.Arena, identity: []const str, attrs: json.Value) -> str {
    let members = sorted_members(a, attrs)
    let (ops, e) = mem.alloc[json.Value](a, members.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < members.len {
        if !listed(identity, members[i].key) {
            ops[n] = patch_op(a, members[i].key, members[i].value)
            n += 1usize
        }
        i += 1usize
    }
    ret compact(a, json.Value{ Array: ops[0usize..n] })
}

// The same for a tag-indexed type: a patched tag property gets the identity merged in.
fn patch_document_tagged(a: *mem.Arena, name: str, attrs: json.Value, map_shape: bool, tag_prop: str) -> str {
    let members = sorted_members(a, attrs)
    let (ops, e) = mem.alloc[json.Value](a, members.len + 1usize)
    var i = 0usize
    while i < members.len {
        var value = members[i].value
        if str.eq(members[i].key, tag_prop) { value = merged_tags(a, name, value, true, map_shape) }
        ops[i] = patch_op(a, members[i].key, value)
        i += 1usize
    }
    ret compact(a, json.Value{ Array: ops[0usize..members.len] })
}

// Observed attributes without PetCow's identity tags; the property goes when only those were in it.
fn strip_petcow_tags(a: *mem.Arena, attrs: json.Value, map_shape: bool, tag_prop: str) -> json.Value {
    let (tags, found) = ir.get(attrs, tag_prop)
    if !found { ret attrs }
    var obj = copy_without(a, attrs, tag_prop)
    var empty = false
    var replaced = tags
    if !map_shape {
        let (items, is_array) = ir.items_of(tags)
        if is_array {
            let (out, e) = mem.alloc[json.Value](a, items.len + 1usize)
            var n = 0usize
            var i = 0usize
            while i < items.len {
                let (k, has) = ir.get(items[i], "Key")
                var drop = false
                if has {
                    let (ks, is_text) = ir.string_of(k)
                    if is_text && (str.eq(ks, managed_tag()) || str.eq(ks, name_tag())) { drop = true }
                }
                if !drop {
                    out[n] = items[i]
                    n += 1usize
                }
                i += 1usize
            }
            replaced = json.Value{ Array: out[0usize..n] }
            empty = n == 0usize
        }
    } else {
        let (members, is_object) = ir.members_of(tags)
        if is_object {
            var kept = copy_without(a, ir.empty_object(), "")
            var n = 0usize
            var i = 0usize
            while i < members.len {
                if !str.eq(members[i].key, managed_tag()) && !str.eq(members[i].key, name_tag()) {
                    let pe = ir.put(&kept, members[i].key, members[i].value)
                    n += 1usize
                }
                i += 1usize
            }
            replaced = ir.obj_value(&kept)
            empty = n == 0usize
        }
    }
    if empty { ret ir.obj_value(&obj) }
    let pe = ir.put(&obj, tag_prop, replaced)
    // keep the property where it was among the others (order is not significant to a JSON object)
    ret ir.obj_value(&obj)
}

// Whether a properties document has `key` present and not null.
fn properties_have_key(a: *mem.Arena, props: str, has_props: bool, key: str) -> bool {
    if !has_props { ret false }
    let (v, pe) = json.parse(a, props, json.Options { allow_duplicate_keys: true, max_depth: 64u16 })
    if pe != ok { ret false }
    let (x, found) = ir.get(v, key)
    ret found && !ir.is_null(x)
}

// A properties document as attributes: an object's members, else empty; malformed text is an error.
fn parse_properties(a: *mem.Arena, props: str, has_props: bool) -> (json.Value, str, bool) {
    if !has_props { ret (ir.empty_object(), "", true) }
    let (v, pe) = json.parse(a, props, json.Options { allow_duplicate_keys: true, max_depth: 64u16 })
    if pe != ok { ret (ir.empty_object(), "invalid document: ccapi properties parse: invalid JSON", false) }
    let (members, is_object) = ir.members_of(v)
    if !is_object { ret (ir.empty_object(), "", true) }
    ret (v, "", true)
}
