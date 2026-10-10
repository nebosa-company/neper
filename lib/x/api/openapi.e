// OpenAPI 3.0.3 document builder (L049), after Appdor's `src/api/openapi-builder.js`: `create_spec` makes the skeleton
// (`openapi`, `info`, empty `paths`, `components.schemas`, and `servers`/`tags`/`securitySchemes` when given),
// `add_path` sets or replaces a path and method entry, `add_schema` a component schema, and `validate_spec` reports the
// missing minimum fields in the reference's order. Documents are JSON values and every call returns a new one.
//
// Memory: the arena is retained.

use e.algo.ir as ir
use e.fmt.json as json
use e.mem
use e.str

type Validation = struct { valid: bool, errors: []const str }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn new_obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    ret o
}

fn obj_of(a: *mem.Arena, v: json.Value) -> ir.Obj {
    var o = new_obj(a)
    let e = ir.assign(&o, v)
    ret o
}

fn or_text(info: json.Value, key: str, fallback: str) -> json.Value {
    let v = ir.value_of(info, key)
    if ir.truthy(v) { ret v }
    ret sv(fallback)
}

// A spec skeleton from `{title, version, description?, securitySchemes?, servers?, tags?}`.
fn create_spec(a: *mem.Arena, info: json.Value) -> json.Value {
    var meta = new_obj(a)
    put(&meta, "title", or_text(info, "title", "API"))
    put(&meta, "version", or_text(info, "version", "1.0.0"))
    let description = ir.value_of(info, "description")
    if ir.truthy(description) { put(&meta, "description", description) }
    var components = new_obj(a)
    put(&components, "schemas", ir.empty_object())
    let schemes = ir.value_of(info, "securitySchemes")
    if ir.truthy(schemes) { put(&components, "securitySchemes", schemes) }
    var spec = new_obj(a)
    put(&spec, "openapi", sv("3.0.3"))
    put(&spec, "info", ir.obj_value(&meta))
    put(&spec, "paths", ir.empty_object())
    put(&spec, "components", ir.obj_value(&components))
    let servers = ir.value_of(info, "servers")
    if ir.truthy(servers) { put(&spec, "servers", servers) }
    let tags = ir.value_of(info, "tags")
    if ir.truthy(tags) { put(&spec, "tags", tags) }
    ret ir.obj_value(&spec)
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

// The spec with `operation` at `path`/`method` (the method lower-cased), replacing what was there.
fn add_path(a: *mem.Arena, spec: json.Value, path: str, method: str, operation: json.Value) -> json.Value {
    var out = obj_of(a, spec)
    var paths = obj_of(a, ir.value_of(spec, "paths"))
    var entry = obj_of(a, ir.value_of(ir.value_of(spec, "paths"), path))
    put(&entry, lower(a, method), operation)
    put(&paths, path, ir.obj_value(&entry))
    put(&out, "paths", ir.obj_value(&paths))
    ret ir.obj_value(&out)
}

// The spec with a schema added under `components.schemas`.
fn add_schema(a: *mem.Arena, spec: json.Value, name: str, schema: json.Value) -> json.Value {
    var out = obj_of(a, spec)
    var components = obj_of(a, ir.value_of(spec, "components"))
    var schemas = obj_of(a, ir.value_of(ir.value_of(spec, "components"), "schemas"))
    put(&schemas, name, schema)
    put(&components, "schemas", ir.obj_value(&schemas))
    put(&out, "components", ir.obj_value(&components))
    ret ir.obj_value(&out)
}

fn is_object(v: json.Value) -> bool {
    switch v {
    case .Object as m:
        ret true
    default:
        ret false
    }
}

// Whether a spec has the minimum OpenAPI 3.0 fields, and what is missing.
fn validate_spec(a: *mem.Arena, spec: json.Value) -> Validation {
    let (errors, e) = mem.alloc[str](a, 8usize)
    var n = 0usize
    if !is_object(spec) {
        errors[0] = "spec must be an object"
        ret Validation { valid: false, errors: errors[0usize..1usize] }
    }
    let version = ir.value_of(spec, "openapi")
    var version_ok = false
    if ir.truthy(version) {
        switch version {
        case .String as s:
            version_ok = str.starts_with(s, "3.")
        case .Number as num:
            version_ok = str.starts_with(num.lexeme, "3.")
        default:
            version_ok = false
        }
    }
    if !version_ok {
        errors[n] = "missing or invalid openapi version"
        n += 1usize
    }
    let info = ir.value_of(spec, "info")
    if !ir.truthy(ir.value_of(info, "title")) {
        errors[n] = "missing info.title"
        n += 1usize
    }
    if !ir.truthy(ir.value_of(info, "version")) {
        errors[n] = "missing info.version"
        n += 1usize
    }
    let paths = ir.value_of(spec, "paths")
    var paths_ok = ir.truthy(paths)
    switch paths {
    case .Object as pm:
        paths_ok = true
    case .Array as pa:
        paths_ok = true
    default:
        paths_ok = paths_ok && false
    }
    if !paths_ok {
        errors[n] = "missing paths"
        n += 1usize
    }
    let components = ir.value_of(spec, "components")
    if !ir.truthy(ir.value_of(components, "schemas")) {
        errors[n] = "missing components.schemas"
        n += 1usize
    }
    ret Validation { valid: n == 0usize, errors: errors[0usize..n] }
}
