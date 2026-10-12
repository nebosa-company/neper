// The Kubernetes provider's identity and drift rules (L048), after Petcow's `provider/k8s/mod.rs`: what a `kubectl`-driven
// provider decides before any process is spawned.
//
//   * the Kind catalogue: the fourteen built-in kinds (`type`, `api_version`, `kind`, `namespaced`), an operator manifest of
//     more (CRDs included) read from a YAML list that refuses unknown fields, merged over the built-ins by type;
//   * the kubectl selector (`Deployment.apps` for a group, the bare Kind in the core group) and the `-n <namespace>`
//     arguments (namespaced kinds only, and only when a namespace is configured);
//   * the apply manifest: the desired attributes with `apiVersion` and `kind` set, `metadata.name` forced and the
//     `petcow.io/managed` and `petcow.io/name` labels injected, a user's other labels and annotations kept -- the labels
//     must never be renamed, they are how a live resource is found again;
//   * the observed state: name and uid from the live object, attributes from the `last-applied-configuration` annotation
//     when it parses (the applied, pre-defaulting shape, so a converged resource plans as no change) and from the live
//     object otherwise, with `apiVersion`, `kind`, `metadata` and `status` dropped;
//   * whether a live object carries the managed label, and whether a kubectl error means the resource is gone.
//
// The kubectl process itself is host code over `e.proc`. Manifest text is written compactly with keys in byte order, as the
// reference's serde does.
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.mem
use e.str

type Def = struct { petcow_type: str, api_version: str, kind: str, namespaced: bool }

type Defs = struct { valid: bool, message: str, defs: []const Def }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn managed_label() -> str { ret "petcow.io/managed" }

fn name_label() -> str { ret "petcow.io/name" }

fn last_applied_key() -> str { ret "kubectl.kubernetes.io/last-applied-configuration" }

fn def(petcow_type: str, api_version: str, kind: str, namespaced: bool) -> Def {
    ret Def { petcow_type: petcow_type, api_version: api_version, kind: kind, namespaced: namespaced }
}

// The built-in kinds, as Petcow lists them.
fn default_defs(a: *mem.Arena) -> []const Def {
    let (out, e) = mem.alloc[Def](a, 14usize)
    if e != ok { ret zero }
    out[0] = def("k8s.namespace", "v1", "Namespace", false)
    out[1] = def("k8s.config_map", "v1", "ConfigMap", true)
    out[2] = def("k8s.secret", "v1", "Secret", true)
    out[3] = def("k8s.service", "v1", "Service", true)
    out[4] = def("k8s.service_account", "v1", "ServiceAccount", true)
    out[5] = def("k8s.persistent_volume_claim", "v1", "PersistentVolumeClaim", true)
    out[6] = def("k8s.deployment", "apps/v1", "Deployment", true)
    out[7] = def("k8s.stateful_set", "apps/v1", "StatefulSet", true)
    out[8] = def("k8s.daemon_set", "apps/v1", "DaemonSet", true)
    out[9] = def("k8s.job", "batch/v1", "Job", true)
    out[10] = def("k8s.cron_job", "batch/v1", "CronJob", true)
    out[11] = def("k8s.ingress", "networking.k8s.io/v1", "Ingress", true)
    out[12] = def("k8s.role", "rbac.authorization.k8s.io/v1", "Role", true)
    out[13] = def("k8s.cluster_role", "rbac.authorization.k8s.io/v1", "ClusterRole", false)
    ret out[0usize..14usize]
}

fn failed_defs(a: *mem.Arena, what: str) -> Defs {
    let none: []const Def = zero
    ret Defs { valid: false, message: join(a, "invalid document: k8s manifest: ", what), defs: none }
}

// A string field as the reference reads it: a plain scalar of any kind is accepted as its text (a number as its decimal
// text, a boolean as `true` or `false`, null as `null`); only a sequence or a mapping is refused. Where a number was
// written with a trailing zero or an exponent the reference keeps those characters; this reads its shortest text.
fn string_value(a: *mem.Arena, v: yaml.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    case .Null:
        ret ("null", true)
    case .Bool as b:
        if b { ret ("true", true) }
        ret ("false", true)
    case .Integer as n:
        let (made, e) = str.builder(a, 24usize)
        if e != ok { ret ("", false) }
        var out = made
        let pushed = str.push_i64(&out, n)
        ret (str.done(&out), true)
    case .Float as x:
        let (made, e) = str.builder(a, 40usize)
        if e != ok { ret ("", false) }
        var out = made
        let pushed = str.push_f64(&out, x)
        ret (str.done(&out), true)
    default:
        ret ("", false)
    }
}

// One definition from a mapping: `type`, `api_version` and `kind` strings, an optional `namespaced` bool defaulting to
// true, no other key.
fn def_of(a: *mem.Arena, v: yaml.Value) -> (Def, str, bool) {
    var d = Def { petcow_type: "", api_version: "", kind: "", namespaced: true }
    var members: []const yaml.Pair = zero
    switch v {
    case .Mapping as m:
        members = m
    default:
        ret (d, "invalid type, expected struct K8sResourceDef", false)
    }
    var have_type = false
    var have_version = false
    var have_kind = false
    var seen_namespaced = false
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
            if have_type { ret (d, "duplicate field `type`", false) }
            let (s, good) = string_value(a, value)
            if !good { ret (d, "invalid type for `type`, expected a string", false) }
            d.petcow_type = s
            have_type = true
        } else if str.eq(key, "api_version") {
            if have_version { ret (d, "duplicate field `api_version`", false) }
            let (s, good) = string_value(a, value)
            if !good { ret (d, "invalid type for `api_version`, expected a string", false) }
            d.api_version = s
            have_version = true
        } else if str.eq(key, "kind") {
            if have_kind { ret (d, "duplicate field `kind`", false) }
            let (s, good) = string_value(a, value)
            if !good { ret (d, "invalid type for `kind`, expected a string", false) }
            d.kind = s
            have_kind = true
        } else if str.eq(key, "namespaced") {
            if seen_namespaced { ret (d, "duplicate field `namespaced`", false) }
            switch value {
            case .Bool as b:
                d.namespaced = b
            default:
                ret (d, "invalid type for `namespaced`, expected a boolean", false)
            }
            seen_namespaced = true
        } else {
            ret (d, "unknown field", false)
        }
        i += 1usize
    }
    if !have_type { ret (d, "missing field `type`", false) }
    if !have_version { ret (d, "missing field `api_version`", false) }
    if !have_kind { ret (d, "missing field `kind`", false) }
    ret (d, "", true)
}

// A YAML list of definitions (one operator manifest file).
fn parse_defs(a: *mem.Arena, source: str) -> Defs {
    let (root, pe) = yaml.parse(a, source, yaml.Options { max_depth: 64u16, allow_duplicate_keys: true })
    if pe != ok { ret failed_defs(a, "failed to parse") }
    var items: []const yaml.Value = zero
    switch root {
    case .Sequence as xs:
        items = xs
    default:
        ret failed_defs(a, "invalid type, expected a sequence")
    }
    let (out, e) = mem.alloc[Def](a, items.len + 1usize)
    if e != ok { ret failed_defs(a, "out of memory") }
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
    if e != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < defaults.len + extra.len {
        var d = def("", "", "", true)
        if i < defaults.len { d = defaults[i] } else { d = extra[i - defaults.len] }
        var at = n
        var k = 0usize
        while k < n {
            if str.eq(out[k].petcow_type, d.petcow_type) { at = k }
            k += 1usize
        }
        out[at] = d
        if at == n { n += 1usize }
        i += 1usize
    }
    var s = 1usize
    while s < n {
        let cur = out[s]
        var j = s
        while j > 0usize && str.compare(out[j - 1usize].petcow_type, cur.petcow_type) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        s += 1usize
    }
    ret out[0usize..n]
}

// `<Kind>.<group>`, or the bare Kind in the core group: an unambiguous kubectl resource selector.
fn selector(a: *mem.Arena, d: Def) -> str {
    let (slash, found) = str.find(d.api_version, "/")
    if !found { ret d.kind }
    ret join(a, join(a, d.kind, "."), d.api_version[0usize..slash])
}

// `-n <namespace>` for a namespaced kind with a configured namespace, else nothing.
fn ns_args(a: *mem.Arena, d: Def, namespace: str, has_namespace: bool) -> []const str {
    let (out, e) = mem.alloc[str](a, 2usize)
    if e != ok { ret zero }
    if !d.namespaced || !has_namespace { ret out[0usize..0usize] }
    out[0] = "-n"
    out[1] = namespace
    ret out[0usize..2usize]
}

fn lower_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

// Whether a kubectl error means the resource does not exist.
fn is_not_found(a: *mem.Arena, stderr: str) -> bool {
    let low = lower_ascii(a, stderr)
    ret str.contains(low, "notfound") || str.contains(low, "not found")
}

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { ret ir.Obj { items: zero, len: 0usize, arena: a } }
    ret o
}

// Whether a raw kubectl object carries `petcow.io/managed: "true"`.
fn is_managed_item(item: json.Value) -> bool {
    let (metadata, has_metadata) = ir.get(item, "metadata")
    if !has_metadata { ret false }
    let (labels, has_labels) = ir.get(metadata, "labels")
    if !has_labels { ret false }
    let (v, has_v) = ir.get(labels, managed_label())
    if !has_v { ret false }
    let (s, is_text) = ir.string_of(v)
    ret is_text && str.eq(s, "true")
}

// The `kubectl apply` manifest, compact with keys in byte order: the desired attributes (`metadata`, `apiVersion` and
// `kind` aside), `apiVersion` and `kind` from the definition, and `metadata` with the user's entries, `name` forced and
// the managed labels added.
fn apply_manifest(a: *mem.Arena, d: Def, name: str, attrs: json.Value) -> str {
    var doc = obj(a)
    let (members, is_object) = ir.members_of(attrs)
    var at = 0usize
    while at < members.len {
        let k = members[at].key
        if !str.eq(k, "metadata") && !str.eq(k, "apiVersion") && !str.eq(k, "kind") {
            let put = ir.put(&doc, k, members[at].value)
        }
        at += 1usize
    }
    let p1 = ir.put(&doc, "apiVersion", text(d.api_version))
    let p2 = ir.put(&doc, "kind", text(d.kind))
    var meta = obj(a)
    let (given, has_given) = ir.get(attrs, "metadata")
    if has_given {
        let carried = ir.assign(&meta, given)
    }
    let p3 = ir.put(&meta, "name", text(name))
    var labels = obj(a)
    let (current, has_labels) = ir.get(ir.obj_value(&meta), "labels")
    if has_labels {
        let kept = ir.assign(&labels, current)
    }
    let p4 = ir.put(&labels, managed_label(), text("true"))
    let p5 = ir.put(&labels, name_label(), text(name))
    let p6 = ir.put(&meta, "labels", ir.obj_value(&labels))
    let p7 = ir.put(&doc, "metadata", ir.obj_value(&meta))
    let (out, e) = chain.canonical_json(a, ir.obj_value(&doc))
    if e != ok { ret "" }
    ret out
}

// The observed resource of a live object: `{name, type, attributes, real_id}`; the attributes come from the
// last-applied annotation when it parses, else from the live object.
fn observed(a: *mem.Arena, type_: str, live: json.Value) -> json.Value {
    var name = ""
    var uid = ""
    var has_uid = false
    var annotation = ""
    var has_annotation = false
    let (metadata, has_metadata) = ir.get(live, "metadata")
    if has_metadata {
        let (n, has_n) = ir.get(metadata, "name")
        let (ns, name_is_text) = ir.string_of(n)
        if has_n && name_is_text { name = ns }
        let (u, has_u) = ir.get(metadata, "uid")
        let (us, uid_is_text) = ir.string_of(u)
        if has_u && uid_is_text {
            uid = us
            has_uid = true
        }
        let (annotations, has_annotations) = ir.get(metadata, "annotations")
        if has_annotations {
            let (ann, has_ann) = ir.get(annotations, last_applied_key())
            let (anns, ann_is_text) = ir.string_of(ann)
            if has_ann && ann_is_text {
                annotation = anns
                has_annotation = true
            }
        }
    }
    var source = live
    if has_annotation {
        let (parsed, pe) = json.parse(a, annotation, json.Options { allow_duplicate_keys: true, max_depth: 128u16 })
        if pe == ok { source = parsed }
    }
    var attributes = obj(a)
    let (members, is_object) = ir.members_of(source)
    var at = 0usize
    while at < members.len {
        let k = members[at].key
        if !str.eq(k, "apiVersion") && !str.eq(k, "kind") && !str.eq(k, "metadata") && !str.eq(k, "status") {
            let put = ir.put(&attributes, k, members[at].value)
        }
        at += 1usize
    }
    var out = obj(a)
    let q1 = ir.put(&out, "name", text(name))
    let q2 = ir.put(&out, "type", text(type_))
    let q3 = ir.put(&out, "attributes", ir.obj_value(&attributes))
    if has_uid { let q4 = ir.put(&out, "real_id", text(uid)) } else { let q5 = ir.put(&out, "real_id", .Null) }
    ret ir.obj_value(&out)
}
