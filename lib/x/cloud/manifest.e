// External resource manifests (L047), after Petcow's `provider/manifest.rs`: a YAML file of `resources:` that each become a
// declarative REST definition bound to a cloud. The document is checked as the reference's serde types check it (known keys
// only, strings, a `u32`, booleans, string maps in key order), then converted with the reference's validations in its order:
// the cloud must be declarative and agree with the type's prefix, an `rpc:` block lowers to the item, list, create, delete
// and update URLs and the verbs (and refuses explicit URLs beside it), a marker and `observed_name_field` cannot both name
// the resource, `create_body_vars` may not collide with what `copy_attrs` or `name_field` writes, and a pair-list marker
// must be stamped by the RPC create's params (one key parameter and one value parameter per tag). A shape error reads
// `invalid document: invalid resource manifest: <what>`; the `<what>` text is this module's own.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.fmt.yaml as yaml
use e.mem
use e.str
use x.cloud.rest as rest

type Resource = struct { type_name: str, cloud: str, create_method: str, item_url: str, create_url: str, list_url: str, list_items_field: str, has_marker: bool, marker: rest.Marker, copy_attrs: []const rest.Pair, output_attrs: []const str, real_id_field: str, has_name_field: bool, name_field: str, has_name_value_template: bool, name_value_template: str, has_update_method: bool, update_method: str, has_update_mask: bool, update_mask: str, has_operation_url: bool, operation_url: str, has_timeout: bool, timeout_minutes: u32, operation_style: u8, has_create_wrapper: bool, wrapper_key: str, has_wrapper_id: bool, wrapper_id_field: str, server_named: bool, has_name_suffix: bool, name_suffix: str, has_read_method: bool, read_method: str, has_list_method: bool, list_method: str, has_delete_method: bool, delete_method: str, has_update_target_url: bool, update_target_url: str, has_delete_url: bool, delete_url: str, has_parent: bool, parent: rest.Parent, create_body_vars: []const rest.Pair, has_observed_name_field: bool, observed_name_field: str }

type Manifest = struct { valid: bool, message: str, resources: []const Resource }

type Rpc = struct { endpoint: str, version: str, method: str, create_action: str, create_params: []const rest.Pair, read_action: str, read_params: []const rest.Pair, list_action: str, list_params: []const rest.Pair, delete_action: str, delete_params: []const rest.Pair, has_update: bool, update_action: str, update_params: []const rest.Pair }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn shape_error(a: *mem.Arena, what: str) -> str { ret join(a, "invalid document: invalid resource manifest: ", what) }

fn doc_error(a: *mem.Arena, what: str) -> str { ret join(a, "invalid document: ", what) }

fn failed(message: str) -> Manifest {
    let none: []const Resource = zero
    ret Manifest { valid: false, message: message, resources: none }
}

// --- reading the YAML shape ------------------------------------------------------------------------------------

fn key_text(v: yaml.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

// The scalar as text where a `String` is wanted: strings as they are, integers, floats and booleans by their value.
fn scalar_text(a: *mem.Arena, v: yaml.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    case .Integer as n:
        ret (f.number_text(a, f64(n)), true)
    case .Bool as b:
        if b { ret ("true", true) }
        ret ("false", true)
    case .Float as x:
        ret (f.number_text(a, x), true)
    default:
        ret ("", false)
    }
}

type Reader = struct { a: *mem.Arena, message: str, failed: bool }

fn bad(r: *Reader, what: str) {
    if !r.failed {
        r.failed = true
        r.message = shape_error(r.a, what)
    }
}

fn mapping(v: yaml.Value) -> ([]const yaml.Pair, bool) {
    switch v {
    case .Mapping as m:
        ret (m, true)
    default:
        ret (zero, false)
    }
}

fn sequence(v: yaml.Value) -> ([]const yaml.Value, bool) {
    switch v {
    case .Sequence as s:
        ret (s, true)
    default:
        ret (zero, false)
    }
}

fn is_null(v: yaml.Value) -> bool {
    switch v {
    case .Null:
        ret true
    default:
        ret false
    }
}

// An optional string field: false when absent or null.
fn opt_text(r: *Reader, m: []const yaml.Pair, name: str) -> (str, bool) {
    var i = 0usize
    while i < m.len {
        let (k, is_text) = key_text(m[i].key)
        if is_text && str.eq(k, name) {
            if is_null(m[i].value) { ret ("", false) }
            let (s, good) = scalar_text(r.a, m[i].value)
            if !good {
                bad(r, join(r.a, join(r.a, "invalid type for `", name), "`, expected a string"))
                ret ("", false)
            }
            ret (s, true)
        }
        i += 1usize
    }
    ret ("", false)
}

fn req_text(r: *Reader, m: []const yaml.Pair, name: str) -> str {
    let (s, has) = opt_text(r, m, name)
    if !has { bad(r, join(r.a, "missing field `", join(r.a, name, "`"))) }
    ret s
}

fn text_or(r: *Reader, m: []const yaml.Pair, name: str, fallback: str) -> str {
    let (s, has) = opt_text(r, m, name)
    if has { ret s }
    ret fallback
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

// A `BTreeMap<String, String>` field in key order.
fn text_map(r: *Reader, m: []const yaml.Pair, name: str) -> []const rest.Pair {
    let none: []const rest.Pair = zero
    let (v, has) = find(m, name)
    if !has || is_null(v) { ret none }
    let (entries, is_map) = mapping(v)
    if !is_map {
        bad(r, join(r.a, join(r.a, "invalid type for `", name), "`, expected a map"))
        ret none
    }
    let (out, e) = mem.alloc[rest.Pair](r.a, entries.len + 1usize)
    var i = 0usize
    while i < entries.len {
        let (k, is_text) = key_text(entries[i].key)
        let (s, good) = scalar_text(r.a, entries[i].value)
        if !is_text || !good {
            bad(r, join(r.a, join(r.a, "invalid entry in `", name), "`, expected strings"))
            ret none
        }
        out[i] = rest.Pair { key: k, value: s }
        i += 1usize
    }
    // key order
    i = 1usize
    while i < entries.len {
        let cur = out[i]
        var j = i
        while j > 0usize && str.compare(out[j - 1usize].key, cur.key) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..entries.len]
}

fn allowed_keys(r: *Reader, m: []const yaml.Pair, allowed: []const str, owner: str) {
    var i = 0usize
    while i < m.len {
        let (k, is_text) = key_text(m[i].key)
        if !is_text {
            bad(r, join(r.a, "invalid key in ", owner))
            ret
        }
        var known = false
        var j = 0usize
        while j < allowed.len {
            if str.eq(allowed[j], k) { known = true }
            j += 1usize
        }
        if !known {
            bad(r, join(r.a, join(r.a, join(r.a, owner, ": unknown field `"), k), "`"))
            ret
        }
        i += 1usize
    }
}

fn op_of(r: *Reader, v: yaml.Value, owner: str) -> (str, []const rest.Pair) {
    let none: []const rest.Pair = zero
    let (m, is_map) = mapping(v)
    if !is_map {
        bad(r, join(r.a, owner, ": expected a map"))
        ret ("", none)
    }
    let keys = [2]str{ "action", "params" }
    allowed_keys(r, m, keys[0usize..2usize], owner)
    let action = req_text(r, m, "action")
    ret (action, text_map(r, m, "params"))
}

// --- RPC lowering ----------------------------------------------------------------------------------------------

fn debug_char(a: *mem.Arena, c: u8) -> str {
    if c == 10u8 { ret "'\\n'" }
    if c == 13u8 { ret "'\\r'" }
    if c == 9u8 { ret "'\\t'" }
    if c == 92u8 { ret "'\\\\'" }
    if c == 39u8 { ret "'\\''" }
    if c < 32u8 || c == 127u8 {
        let hex = "0123456789abcdef"
        var out = "'\\u{"
        if c >= 16u8 { out = join(a, out, hex[usize(c >> 4u8)..usize(c >> 4u8) + 1usize]) }
        out = join(a, out, hex[usize(c & 15u8)..usize(c & 15u8) + 1usize])
        ret join(a, out, "}'")
    }
    ret join(a, join(a, "'", str_of_byte(c)), "'")
}

fn str_of_byte(c: u8) -> str {
    let table = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    if c < 32u8 || c > 126u8 { ret "?" }
    let at = usize(c - 32u8)
    ret table[at..at + 1usize]
}

// The text a query-safety check refuses: characters outside `{}` that would split the query, or non-ASCII/control.
fn check_query_safe(a: *mem.Arena, kind: str, text: str) -> (str, bool) {
    var depth = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 123u8 {
            depth += 1usize
        } else if c == 125u8 {
            if depth > 0usize { depth -= 1usize }
        } else if depth == 0usize {
            var unsafe_char = c == 38u8 || c == 61u8 || c == 35u8 || c == 63u8 || c == 32u8 || c >= 128u8 || c < 32u8 || c == 127u8
            if unsafe_char {
                var shown = debug_char(a, c)
                if c >= 128u8 {
                    // a whole non-ASCII character, as `{:?}` prints it
                    var end = i + 1usize
                    while end < text.len && (text[end] & 192u8) == 128u8 { end += 1usize }
                    shown = join(a, join(a, "'", text[i..end]), "'")
                }
                let msg = join(a, join(a, join(a, join(a, "rpc ", kind), join(a, " '", text)), join(a, "' contains ", shown)), ", which would split the query string into parameters other than the ones written — and the signature would then cover that different request perfectly")
                ret (doc_error(a, msg), false)
            }
        }
        i += 1usize
    }
    ret ("", true)
}

type Url = struct { valid: bool, message: str, value: str }

fn rpc_url(a: *mem.Arena, rpc: Rpc, action: str, params: []const rest.Pair) -> Url {
    let (m1, ok1) = check_query_safe(a, "action", action)
    if !ok1 { ret Url { valid: false, message: m1, value: "" } }
    let (m2, ok2) = check_query_safe(a, "version", rpc.version)
    if !ok2 { ret Url { valid: false, message: m2, value: "" } }
    var query = join(a, join(a, "Action=", action), join(a, "&Version=", rpc.version))
    var i = 0usize
    while i < params.len {
        let (m3, ok3) = check_query_safe(a, "param name", params[i].key)
        if !ok3 { ret Url { valid: false, message: m3, value: "" } }
        let (m4, ok4) = check_query_safe(a, "param value", params[i].value)
        if !ok4 { ret Url { valid: false, message: m4, value: "" } }
        query = join(a, query, join(a, "&", join(a, params[i].key, join(a, "=", params[i].value))))
        i += 1usize
    }
    var sep = "?"
    if str.contains(rpc.endpoint, "?") { sep = "&" }
    ret Url { valid: true, message: "", value: join(a, join(a, rpc.endpoint, sep), query) }
}

fn rsplit_dot(s: str) -> (str, bool) {
    var i = s.len
    while i > 0usize {
        if s[i - 1usize] == 46u8 { ret (s[0usize..i - 1usize], true) }
        i -= 1usize
    }
    ret ("", false)
}

// The pair-list marker's two tags must each be stamped by one key parameter and its one value parameter.
fn check_pair_marker_stamped(a: *mem.Arena, type_name: str, managed_key: str, name_key: str, params: []const rest.Pair) -> (str, bool) {
    let tags = [2]str{ managed_key, name_key }
    let wants = [2]str{ "true", "{name}" }
    var t = 0usize
    while t < 2usize {
        let tag_key = tags[t]
        let want = wants[t]
        t += 1usize
        var key_param = ""
        var found = false
        var i = 0usize
        while i < params.len && !found {
            if str.eq(params[i].value, tag_key) {
                key_param = params[i].key
                found = true
            }
            i += 1usize
        }
        if !found {
            let msg = join(a, join(a, join(a, "pair_list marker on '", type_name), "' is never stamped: no rpc.create.params entry has the value '"), join(a, tag_key, "'. A marker the create does not write can never be read back, so the resource would be invisible to discover and prune forever while it went on billing"))
            ret (doc_error(a, msg), false)
        }
        let (group, has_group) = rsplit_dot(key_param)
        if !has_group {
            let msg = join(a, join(a, join(a, "pair_list marker on '", type_name), "': parameter '"), join(a, key_param, join(a, "' names '", join(a, tag_key, "' but is not a '<group>.<field>' parameter, so the value that goes with it cannot be identified"))))
            ret (doc_error(a, msg), false)
        }
        let prefix = join(a, group, ".")
        var count = 0usize
        var sib_key = ""
        var sib_value = ""
        i = 0usize
        while i < params.len {
            if str.starts_with(params[i].key, prefix) && !str.eq(params[i].key, key_param) {
                if count == 0usize {
                    sib_key = params[i].key
                    sib_value = params[i].value
                }
                count += 1usize
            }
            i += 1usize
        }
        if count == 1usize {
            if !str.eq(sib_value, want) {
                let msg = join(a, join(a, join(a, "pair_list marker on '", type_name), "': '"), join(a, sib_key, join(a, "' is '", join(a, sib_value, join(a, "', but the ", join(a, tag_key, join(a, " tag must be stamped as '", join(a, want, "'"))))))))
                ret (doc_error(a, msg), false)
            }
        } else if count == 0usize {
            let msg = join(a, join(a, join(a, "pair_list marker on '", type_name), "': '"), join(a, key_param, join(a, "' names '", join(a, tag_key, join(a, "' but its value parameter is missing — a '", join(a, group, join(a, ".*' entry carrying '", join(a, want, "'"))))))))
            ret (doc_error(a, msg), false)
        } else {
            var msg = join(a, "pair_list marker on '", type_name)
            msg = join(a, msg, "': '")
            msg = join(a, msg, group)
            msg = join(a, msg, ".*' carries ")
            msg = join(a, msg, f.number_text(a, f64(count)))
            msg = join(a, msg, " parameters besides '")
            msg = join(a, msg, key_param)
            msg = join(a, msg, "', and a tag is one key and one value — PetCow cannot tell which one is meant to hold '")
            msg = join(a, msg, want)
            msg = join(a, msg, "'")
            ret (doc_error(a, msg), false)
        }
    }
    ret ("", true)
}

// --- conversion ------------------------------------------------------------------------------------------------

fn empty_marker() -> rest.Marker {
    ret rest.Marker { field: "", managed_key: "", name_key: "", pair: false, key_field: "", value_field: "" }
}

fn declarative_clouds() -> str { ret "gcp, azure, ibm, oci, aliyun" }

fn convert(a: *mem.Arena, r: *Reader, m: []const yaml.Pair) -> (Resource, str, bool) {
    let none_pairs: []const rest.Pair = zero
    let none_texts: []const str = zero
    var res = Resource {
        type_name: "", cloud: "", create_method: "PUT", item_url: "", create_url: "", list_url: "", list_items_field: "", has_marker: false,
        marker: empty_marker(), copy_attrs: none_pairs, output_attrs: none_texts, real_id_field: "name", has_name_field: false, name_field: "",
        has_name_value_template: false, name_value_template: "", has_update_method: false, update_method: "", has_update_mask: false, update_mask: "",
        has_operation_url: false, operation_url: "", has_timeout: false, timeout_minutes: 0u32, operation_style: 0u8, has_create_wrapper: false,
        wrapper_key: "", has_wrapper_id: false, wrapper_id_field: "", server_named: false, has_name_suffix: false, name_suffix: "",
        has_read_method: false, read_method: "", has_list_method: false, list_method: "", has_delete_method: false, delete_method: "",
        has_update_target_url: false, update_target_url: "", has_delete_url: false, delete_url: "", has_parent: false,
        parent: rest.Parent { type_name: "", url_var: "", parent_by_id: false }, create_body_vars: none_pairs, has_observed_name_field: false, observed_name_field: "",
    }
    let keys = [29]str{ "type", "cloud", "create_method", "item_url", "create_url", "list_url", "list_items_field", "real_id_field", "marker", "copy_attrs", "output_attrs", "name_field", "update_method", "update_mask", "operation_url", "operation_timeout_minutes", "operation_style", "create_wrapper", "name_value_template", "server_named", "name_suffix", "read_method", "list_method", "delete_method", "delete_url", "parent", "create_body_vars", "observed_name_field", "rpc" }
    allowed_keys(r, m, keys[0usize..29usize], "resources[0]")
    let type_name = req_text(r, m, "type")
    let cloud = req_text(r, m, "cloud")
    let create_method = text_or(r, m, "create_method", "PUT")
    let (item_url, has_item) = opt_text(r, m, "item_url")
    let (create_url, has_create) = opt_text(r, m, "create_url")
    let (list_url, has_list) = opt_text(r, m, "list_url")
    let list_items_field = text_or(r, m, "list_items_field", "")
    let real_id_field = text_or(r, m, "real_id_field", "name")
    let copy_attrs = text_map(r, m, "copy_attrs")
    let (name_field, has_name_field) = opt_text(r, m, "name_field")
    let (update_method, has_update_method) = opt_text(r, m, "update_method")
    let (update_mask, has_update_mask) = opt_text(r, m, "update_mask")
    let (operation_url, has_operation_url) = opt_text(r, m, "operation_url")
    let (name_value_template, has_nvt) = opt_text(r, m, "name_value_template")
    let (name_suffix, has_suffix) = opt_text(r, m, "name_suffix")
    let (read_method, has_read) = opt_text(r, m, "read_method")
    let (list_method, has_list_method) = opt_text(r, m, "list_method")
    let (delete_method, has_delete_method) = opt_text(r, m, "delete_method")
    let (delete_url, has_delete_url) = opt_text(r, m, "delete_url")
    let (observed, has_observed) = opt_text(r, m, "observed_name_field")
    let body_vars = text_map(r, m, "create_body_vars")
    // output_attrs
    var outputs: []const str = none_texts
    let (ov, has_ov) = find(m, "output_attrs")
    if has_ov && !is_null(ov) {
        let (seq, is_seq) = sequence(ov)
        if !is_seq {
            bad(r, "invalid type for `output_attrs`, expected a sequence")
        } else {
            let (outs, oe) = mem.alloc[str](a, seq.len + 1usize)
            var i = 0usize
            while i < seq.len {
                let (s, good) = scalar_text(a, seq[i])
                if !good { bad(r, "invalid entry in `output_attrs`, expected strings") }
                outs[i] = s
                i += 1usize
            }
            outputs = outs[0usize..seq.len]
        }
    }
    // operation_style
    var style = 0u8
    let (st, has_style) = opt_text(r, m, "operation_style")
    if has_style {
        if str.eq(st, "lro") {
            style = 0u8
        } else if str.eq(st, "compute_self_link") {
            style = 1u8
        } else if str.eq(st, "work_request") {
            style = 2u8
        } else {
            bad(r, join(a, join(a, "unknown variant `", st), "`, expected one of `lro`, `compute_self_link`, `work_request`"))
        }
    }
    // operation_timeout_minutes
    var has_timeout = false
    var timeout = 0u32
    let (tv, has_tv) = find(m, "operation_timeout_minutes")
    if has_tv && !is_null(tv) {
        switch tv {
        case .Integer as n:
            if n >= 0i64 && n <= 4294967295i64 {
                has_timeout = true
                timeout = u32(n)
            } else {
                bad(r, "invalid value for `operation_timeout_minutes`")
            }
        default:
            bad(r, "invalid type for `operation_timeout_minutes`, expected u32")
        }
    }
    // server_named
    var server_named = false
    let (sn, has_sn) = find(m, "server_named")
    if has_sn && !is_null(sn) {
        switch sn {
        case .Bool as b:
            server_named = b
        default:
            bad(r, "invalid type for `server_named`, expected a boolean")
        }
    }
    // create_wrapper
    var has_wrapper = false
    var wrapper_key = ""
    var has_wrapper_id = false
    var wrapper_id = ""
    let (wv, has_wv) = find(m, "create_wrapper")
    if has_wv && !is_null(wv) {
        let (wm, is_map) = mapping(wv)
        if !is_map {
            bad(r, "invalid type for `create_wrapper`, expected a map")
        } else {
            let wk = [2]str{ "key", "id_field" }
            allowed_keys(r, wm, wk[0usize..2usize], "create_wrapper")
            has_wrapper = true
            wrapper_key = req_text(r, wm, "key")
            let (wid, has_wid) = opt_text(r, wm, "id_field")
            wrapper_id = wid
            has_wrapper_id = has_wid
        }
    }
    // parent
    var has_parent = false
    var parent = rest.Parent { type_name: "", url_var: "", parent_by_id: false }
    let (pv, has_pv) = find(m, "parent")
    if has_pv && !is_null(pv) {
        let (pm, is_map) = mapping(pv)
        if !is_map {
            bad(r, "invalid type for `parent`, expected a map")
        } else {
            let pk = [3]str{ "type", "url_var", "parent_by_id" }
            allowed_keys(r, pm, pk[0usize..3usize], "parent")
            has_parent = true
            parent.type_name = req_text(r, pm, "type")
            parent.url_var = req_text(r, pm, "url_var")
            let (bv, has_bv) = find(pm, "parent_by_id")
            if has_bv && !is_null(bv) {
                switch bv {
                case .Bool as b:
                    parent.parent_by_id = b
                default:
                    bad(r, "invalid type for `parent_by_id`, expected a boolean")
                }
            }
        }
    }
    // marker (raw)
    var raw_marker = false
    var marker = empty_marker()
    var marker_shape_pair = false
    var has_key_field = false
    var has_value_field = false
    let (mv, has_mv) = find(m, "marker")
    if has_mv && !is_null(mv) {
        let (mm, is_map) = mapping(mv)
        if !is_map {
            bad(r, "invalid type for `marker`, expected a map")
        } else {
            let mk = [6]str{ "field", "managed_key", "name_key", "shape", "key_field", "value_field" }
            allowed_keys(r, mm, mk[0usize..6usize], "marker")
            raw_marker = true
            marker.field = req_text(r, mm, "field")
            marker.managed_key = req_text(r, mm, "managed_key")
            marker.name_key = req_text(r, mm, "name_key")
            let (shape, has_shape) = opt_text(r, mm, "shape")
            if has_shape {
                if str.eq(shape, "pair_list") {
                    marker_shape_pair = true
                } else if !str.eq(shape, "map") {
                    bad(r, join(a, join(a, "unknown variant `", shape), "`, expected `map` or `pair_list`"))
                }
            }
            let (kf, hk) = opt_text(r, mm, "key_field")
            let (vf, hv) = opt_text(r, mm, "value_field")
            marker.key_field = kf
            marker.value_field = vf
            has_key_field = hk
            has_value_field = hv
        }
    }
    // rpc (raw)
    var has_rpc = false
    var rpc = Rpc { endpoint: "", version: "", method: "POST", create_action: "", create_params: none_pairs, read_action: "", read_params: none_pairs, list_action: "", list_params: none_pairs, delete_action: "", delete_params: none_pairs, has_update: false, update_action: "", update_params: none_pairs }
    let (rv, has_rv) = find(m, "rpc")
    if has_rv && !is_null(rv) {
        let (rm, is_map) = mapping(rv)
        if !is_map {
            bad(r, "invalid type for `rpc`, expected a map")
        } else {
            let rk = [7]str{ "endpoint", "version", "method", "create", "read", "list", "delete" }
            // `update` is also allowed
            var i = 0usize
            while i < rm.len {
                let (k, is_text) = key_text(rm[i].key)
                var known = false
                if is_text {
                    var q = 0usize
                    while q < 7usize {
                        if str.eq(rk[q], k) { known = true }
                        q += 1usize
                    }
                    if str.eq(k, "update") { known = true }
                }
                if !known { bad(r, join(a, "rpc: unknown field `", join(a, k, "`"))) }
                i += 1usize
            }
            has_rpc = true
            rpc.endpoint = req_text(r, rm, "endpoint")
            rpc.version = req_text(r, rm, "version")
            rpc.method = text_or(r, rm, "method", "POST")
            let (cv, has_cv) = find(rm, "create")
            if !has_cv { bad(r, "rpc: missing field `create`") }
            let (ca, cp) = op_of(r, cv, "rpc.create")
            rpc.create_action = ca
            rpc.create_params = cp
            let (rdv, has_rd) = find(rm, "read")
            if !has_rd { bad(r, "rpc: missing field `read`") }
            let (ra, rp) = op_of(r, rdv, "rpc.read")
            rpc.read_action = ra
            rpc.read_params = rp
            let (lv, has_lv) = find(rm, "list")
            if !has_lv { bad(r, "rpc: missing field `list`") }
            let (la, lp) = op_of(r, lv, "rpc.list")
            rpc.list_action = la
            rpc.list_params = lp
            let (dv, has_dv) = find(rm, "delete")
            if !has_dv { bad(r, "rpc: missing field `delete`") }
            let (da, dp) = op_of(r, dv, "rpc.delete")
            rpc.delete_action = da
            rpc.delete_params = dp
            let (uv, has_uv) = find(rm, "update")
            if has_uv && !is_null(uv) {
                let (ua, up) = op_of(r, uv, "rpc.update")
                rpc.has_update = true
                rpc.update_action = ua
                rpc.update_params = up
            }
        }
    }
    if r.failed { ret (res, r.message, false) }
    // --- convert ---
    let (prefix, has_prefix) = rest.type_prefix_for_manifest_cloud(cloud)
    if !has_prefix {
        let msg = join(a, join(a, join(a, "manifest resource '", type_name), "' has unsupported cloud '"), join(a, cloud, join(a, "' (declarative supports: ", join(a, declarative_clouds(), ")"))))
        ret (res, doc_error(a, msg), false)
    }
    var head_end = 0usize
    while head_end < type_name.len && type_name[head_end] != 46u8 { head_end += 1usize }
    if !str.eq(type_name[0usize..head_end], prefix) {
        let msg = join(a, join(a, join(a, "manifest resource '", type_name), "' declares cloud '"), join(a, cloud, join(a, "', whose types are named '", join(a, prefix, ".*'"))))
        ret (res, doc_error(a, msg), false)
    }
    var out_item = ""
    var out_list = ""
    var out_create = ""
    var out_delete = ""
    var has_out_delete = false
    var out_update_target = ""
    var has_out_update_target = false
    var v_read = ""
    var has_v_read = false
    var v_list = ""
    var has_v_list = false
    var v_delete = ""
    var has_v_delete = false
    if !has_rpc {
        if !has_item {
            let msg = join(a, join(a, "manifest resource '", type_name), "' has no item_url (required without an rpc: block)")
            ret (res, doc_error(a, msg), false)
        }
        if !has_list {
            let msg = join(a, join(a, "manifest resource '", type_name), "' has no list_url (required without an rpc: block)")
            ret (res, doc_error(a, msg), false)
        }
        out_item = item_url
        out_list = list_url
        out_create = item_url
        if has_create { out_create = create_url }
        out_delete = delete_url
        has_out_delete = has_delete_url
        v_read = read_method
        has_v_read = has_read
        v_list = list_method
        has_v_list = has_list_method
        v_delete = delete_method
        has_v_delete = has_delete_method
    } else {
        if has_item || has_list || has_create || has_delete_url || has_read || has_list_method || has_delete_method {
            let msg = join(a, join(a, "manifest resource '", type_name), "' declares both an rpc: block and explicit URLs/methods — the rpc block supplies all of them")
            ret (res, doc_error(a, msg), false)
        }
        let read_u = rpc_url(a, rpc, rpc.read_action, rpc.read_params)
        if !read_u.valid { ret (res, read_u.message, false) }
        let list_u = rpc_url(a, rpc, rpc.list_action, rpc.list_params)
        if !list_u.valid { ret (res, list_u.message, false) }
        let create_u = rpc_url(a, rpc, rpc.create_action, rpc.create_params)
        if !create_u.valid { ret (res, create_u.message, false) }
        let delete_u = rpc_url(a, rpc, rpc.delete_action, rpc.delete_params)
        if !delete_u.valid { ret (res, delete_u.message, false) }
        out_item = read_u.value
        out_list = list_u.value
        out_create = create_u.value
        out_delete = delete_u.value
        has_out_delete = true
        if rpc.has_update {
            let update_u = rpc_url(a, rpc, rpc.update_action, rpc.update_params)
            if !update_u.valid { ret (res, update_u.message, false) }
            out_update_target = update_u.value
            has_out_update_target = true
        }
        v_read = rpc.method
        has_v_read = true
        v_list = rpc.method
        has_v_list = true
        v_delete = rpc.method
        has_v_delete = true
    }
    var out_update_method = update_method
    var has_out_update_method = has_update_method
    var out_create_method = create_method
    if has_rpc {
        if rpc.has_update {
            out_update_method = rpc.method
            has_out_update_method = true
        } else {
            out_update_method = ""
            has_out_update_method = false
        }
        out_create_method = rpc.method
    }
    if has_observed && raw_marker {
        let msg = join(a, join(a, "manifest resource '", type_name), "' sets both a marker and observed_name_field; the marker already carries the name, and only one of them can answer")
        ret (res, doc_error(a, msg), false)
    }
    var i = 0usize
    while i < body_vars.len {
        let path = body_vars[i].key
        var collides = has_name_field && str.eq(name_field, path)
        var q = 0usize
        while q < copy_attrs.len {
            if str.eq(copy_attrs[q].value, path) { collides = true }
            q += 1usize
        }
        if collides {
            let msg = join(a, join(a, join(a, "manifest resource '", type_name), "': create_body_vars sets '"), join(a, path, "', which copy_attrs or name_field already writes — one of them would silently win"))
            ret (res, doc_error(a, msg), false)
        }
        i += 1usize
    }
    if raw_marker {
        if !marker_shape_pair {
            if has_key_field || has_value_field {
                let msg = join(a, join(a, "marker on '", type_name), "' sets key_field/value_field, which only a pair_list marker uses")
                ret (res, doc_error(a, msg), false)
            }
        } else {
            if !has_key_field {
                let msg = join(a, join(a, "pair_list marker on '", type_name), "' needs key_field — the field naming the tag key inside each element (Alibaba: TagKey)")
                ret (res, doc_error(a, msg), false)
            }
            if !has_value_field {
                let msg = join(a, join(a, "pair_list marker on '", type_name), "' needs value_field — the field holding the tag value inside each element (Alibaba: TagValue)")
                ret (res, doc_error(a, msg), false)
            }
            if !has_rpc {
                let msg = join(a, join(a, "pair_list marker on '", type_name), "' needs an rpc: block — PetCow does not write a pair list into the create body, so an RPC create's params are the only thing that can stamp it")
                ret (res, doc_error(a, msg), false)
            }
            let (stamp_error, stamped) = check_pair_marker_stamped(a, type_name, marker.managed_key, marker.name_key, rpc.create_params)
            if !stamped { ret (res, stamp_error, false) }
            marker.pair = true
        }
    }
    res.type_name = type_name
    res.cloud = cloud
    res.create_method = out_create_method
    res.item_url = out_item
    res.create_url = out_create
    res.list_url = out_list
    res.list_items_field = list_items_field
    res.has_marker = raw_marker
    res.marker = marker
    res.copy_attrs = copy_attrs
    res.output_attrs = outputs
    res.real_id_field = real_id_field
    res.has_name_field = has_name_field
    res.name_field = name_field
    res.has_name_value_template = has_nvt
    res.name_value_template = name_value_template
    res.has_update_method = has_out_update_method
    res.update_method = out_update_method
    res.has_update_mask = has_update_mask
    res.update_mask = update_mask
    res.has_operation_url = has_operation_url
    res.operation_url = operation_url
    res.has_timeout = has_timeout
    res.timeout_minutes = timeout
    res.operation_style = style
    res.has_create_wrapper = has_wrapper
    res.wrapper_key = wrapper_key
    res.has_wrapper_id = has_wrapper_id
    res.wrapper_id_field = wrapper_id
    res.server_named = server_named
    res.has_name_suffix = has_suffix
    res.name_suffix = name_suffix
    res.has_read_method = has_v_read
    res.read_method = v_read
    res.has_list_method = has_v_list
    res.list_method = v_list
    res.has_delete_method = has_v_delete
    res.delete_method = v_delete
    res.has_update_target_url = has_out_update_target
    res.update_target_url = out_update_target
    res.has_delete_url = has_out_delete
    res.delete_url = out_delete
    res.has_parent = has_parent
    res.parent = parent
    res.create_body_vars = body_vars
    res.has_observed_name_field = has_observed
    res.observed_name_field = observed
    ret (res, "", true)
}

// A manifest document as definitions, each with the cloud it is bound to.
fn parse_manifest(a: *mem.Arena, source: str) -> Manifest {
    let (root, pe) = yaml.parse(a, source, yaml.Options { max_depth: 64u16, allow_duplicate_keys: false })
    var r = Reader { a: a, message: "", failed: false }
    if pe != ok { ret failed(shape_error(a, "failed to parse")) }
    let (top, is_map) = mapping(root)
    if !is_map { ret failed(shape_error(a, "invalid type, expected struct ManifestFile")) }
    let top_keys = [1]str{ "resources" }
    allowed_keys(&r, top, top_keys[0usize..1usize], "ManifestFile")
    if r.failed { ret failed(r.message) }
    let (rv, has) = find(top, "resources")
    if !has { ret failed(shape_error(a, "missing field `resources`")) }
    let (seq, is_seq) = sequence(rv)
    if !is_seq { ret failed(shape_error(a, "resources: invalid type, expected a sequence")) }
    let (out, e) = mem.alloc[Resource](a, seq.len + 1usize)
    var i = 0usize
    // every entry is read first (the reference deserialises the whole file), then converted in order
    var maps: [64][]const yaml.Pair = zero
    if seq.len > 64usize { ret failed(shape_error(a, "too many resources")) }
    while i < seq.len {
        let (m, ok_m) = mapping(seq[i])
        if !ok_m { ret failed(shape_error(a, "resources: invalid type, expected struct ResourceManifest")) }
        maps[i] = m
        i += 1usize
    }
    i = 0usize
    while i < seq.len {
        let (res, message, good) = convert(a, &r, maps[i])
        if !good { ret failed(message) }
        out[i] = res
        i += 1usize
    }
    ret Manifest { valid: true, message: "", resources: out[0usize..seq.len] }
}
