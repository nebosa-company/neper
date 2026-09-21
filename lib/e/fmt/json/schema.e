// JSON Schema validation over `e.fmt.json` trees: `validate` parses a schema and a document
// and answers whether the document conforms, recording the JSON pointer of the first failing
// instance into the caller's `path`. The keywords are the draft 2020-12 core validation
// vocabulary a hand-written schema reaches for: `type` (a name or a list; `integer` is any
// number whose value is integral), `enum`, `const`, `minimum`/`maximum` and their exclusive
// forms, `multipleOf`, `minLength`/`maxLength` (in code points), `pattern` (an unanchored
// `e.text.regex` search), `minItems`/`maxItems`, `uniqueItems`, `items` (one schema for
// every element), `required`, `properties`, `additionalProperties: false`, `allOf`,
// `anyOf`, `oneOf`, `not`, the boolean schemas, and `$ref` to `#` or `#/$defs/<name>`.
//
// Keywords are evaluated in that fixed order and the first failure wins, so the pointer is
// where that keyword was evaluated: a leaf keyword names the value it judged, `items` and
// `properties` descend, and `anyOf`/`oneOf`/`not` name the value the whole choice failed
// on. `additionalProperties` names the extra member. Not here: `$ref` to anywhere else,
// `prefixItems`, `patternProperties`, `dependentRequired`, `if`/`then`/`else`, `format`.

use e.fmt.json
use e.math
use e.mem
use e.str
use e.text.regex

error Invalid
error TooSmall
error TooDeep

const MAX_DEPTH: usize = 256usize

type Checker = struct { arena: *mem.Arena, root: *const json.Value, path: []u8 }

// The index of `name` in `members`, so an absent member never needs a pointer to nothing.
fn member(members: []const json.Member, name: str) -> (usize, bool) {
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn append_byte(c: *Checker, n: usize, byte: u8) -> (usize, err) {
    if n >= c.path.len { ret (n, TooSmall) }
    c.path[n] = byte
    ret (n + 1usize, ok)
}

// `/` then `key` with `~` as `~0` and `/` as `~1`.
fn append_key(c: *Checker, n: usize, key: str) -> (usize, err) {
    var m = n
    let (m0, e0) = append_byte(c, m, 47u8)
    if e0 != ok { ret (m, e0) }
    m = m0
    var i = 0usize
    while i < key.len {
        let b = key[i]
        if b == 126u8 || b == 47u8 {
            let (m1, e1) = append_byte(c, m, 126u8)
            if e1 != ok { ret (m, e1) }
            var digit = 49u8
            if b == 126u8 { digit = 48u8 }
            let (m2, e2) = append_byte(c, m1, digit)
            if e2 != ok { ret (m, e2) }
            m = m2
        } else {
            let (m1, e1) = append_byte(c, m, b)
            if e1 != ok { ret (m, e1) }
            m = m1
        }
        i += 1usize
    }
    ret (m, ok)
}

fn append_index(c: *Checker, n: usize, index: usize) -> (usize, err) {
    var m = n
    let (m0, e0) = append_byte(c, m, 47u8)
    if e0 != ok { ret (m, e0) }
    m = m0
    var scale = 1usize
    while index / scale >= 10usize { scale *= 10usize }
    while scale > 0usize {
        let (m1, e1) = append_byte(c, m, 48u8 + u8((index / scale) % 10usize))
        if e1 != ok { ret (m, e1) }
        m = m1
        scale /= 10usize
    }
    ret (m, ok)
}

fn is_integer(v: *const json.Value) -> bool {
    let (n, is_number) = json.number_of(*v)
    if !is_number { ret false }
    // ponytail: integral means an exact i64; an integral number past 2^63 is refused.
    let (_, e) = json.number_i64(n)
    ret e == ok
}

fn type_matches(name: str, v: *const json.Value) -> (bool, err) {
    if str.eq(name, "null") {
        switch *v {
        case .Null:
            ret (true, ok)
        default:
            ret (false, ok)
        }
    }
    if str.eq(name, "boolean") {
        let (_, is_bool) = json.bool_of(*v)
        ret (is_bool, ok)
    }
    if str.eq(name, "object") {
        let (_, is_object) = json.object_of(*v)
        ret (is_object, ok)
    }
    if str.eq(name, "array") {
        let (_, is_array) = json.array_of(*v)
        ret (is_array, ok)
    }
    if str.eq(name, "number") {
        let (_, is_number) = json.number_of(*v)
        ret (is_number, ok)
    }
    if str.eq(name, "integer") { ret (is_integer(v), ok) }
    if str.eq(name, "string") {
        let (_, is_string) = json.string_of(*v)
        ret (is_string, ok)
    }
    ret (false, Invalid)
}

fn schema_f64(s: *const json.Value) -> (f64, err) {
    let (n, is_number) = json.number_of(*s)
    if !is_number { ret (0.0f64, Invalid) }
    let (v, e) = json.number_f64(n)
    if e != ok { ret (0.0f64, Invalid) }
    ret (v, ok)
}

fn schema_usize(s: *const json.Value) -> (usize, err) {
    let (n, is_number) = json.number_of(*s)
    if !is_number { ret (0usize, Invalid) }
    let (v, e) = json.number_u64(n)
    if e != ok { ret (0usize, Invalid) }
    ret (usize(v), ok)
}

fn code_points(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn resolve_ref(c: *Checker, reference: str) -> (*const json.Value, err) {
    if str.eq(reference, "#") { ret (c.root, ok) }
    if !str.starts_with(reference, "#/$defs/") { ret (c.root, Invalid) }
    let (root_members, root_is_object) = json.object_of(*c.root)
    if !root_is_object { ret (c.root, Invalid) }
    let (defs_at, has_defs) = member(root_members, "$defs")
    if !has_defs { ret (c.root, Invalid) }
    let defs = &root_members[defs_at].value
    let (def_members, defs_is_object) = json.object_of(*defs)
    if !defs_is_object { ret (c.root, Invalid) }
    let (found_at, present) = member(def_members, reference[8usize..])
    if !present { ret (c.root, Invalid) }
    let found = &def_members[found_at].value
    ret (found, ok)
}

// The numeric keywords over `v`; answers false at the first violated one.
fn check_number(s: []const json.Member, v: f64) -> (bool, err) {
    let (minimum_at, has_minimum) = member(s, "minimum")
    if has_minimum {
        let minimum = &s[minimum_at].value
        let (bound, e) = schema_f64(minimum)
        if e != ok { ret (false, e) }
        if v < bound { ret (false, ok) }
    }
    let (maximum_at, has_maximum) = member(s, "maximum")
    if has_maximum {
        let maximum = &s[maximum_at].value
        let (bound, e) = schema_f64(maximum)
        if e != ok { ret (false, e) }
        if v > bound { ret (false, ok) }
    }
    let (exclusive_minimum_at, has_exclusive_minimum) = member(s, "exclusiveMinimum")
    if has_exclusive_minimum {
        let exclusive_minimum = &s[exclusive_minimum_at].value
        let (bound, e) = schema_f64(exclusive_minimum)
        if e != ok { ret (false, e) }
        if v <= bound { ret (false, ok) }
    }
    let (exclusive_maximum_at, has_exclusive_maximum) = member(s, "exclusiveMaximum")
    if has_exclusive_maximum {
        let exclusive_maximum = &s[exclusive_maximum_at].value
        let (bound, e) = schema_f64(exclusive_maximum)
        if e != ok { ret (false, e) }
        if v >= bound { ret (false, ok) }
    }
    let (multiple_at, has_multiple) = member(s, "multipleOf")
    if has_multiple {
        let multiple = &s[multiple_at].value
        let (divisor, e) = schema_f64(multiple)
        if e != ok { ret (false, e) }
        if divisor <= 0.0f64 { ret (false, Invalid) }
        let quotient = v / divisor
        if quotient != math.trunc[f64](quotient) { ret (false, ok) }
    }
    ret (true, ok)
}

fn check_string(c: *Checker, s: []const json.Member, v: str) -> (bool, err) {
    let (min_length_at, has_min_length) = member(s, "minLength")
    let (max_length_at, has_max_length) = member(s, "maxLength")
    if has_min_length || has_max_length {
        let n = code_points(v)
        if has_min_length {
            let min_length = &s[min_length_at].value
            let (bound, e) = schema_usize(min_length)
            if e != ok { ret (false, e) }
            if n < bound { ret (false, ok) }
        }
        if has_max_length {
            let max_length = &s[max_length_at].value
            let (bound, e) = schema_usize(max_length)
            if e != ok { ret (false, e) }
            if n > bound { ret (false, ok) }
        }
    }
    let (pattern_at, has_pattern) = member(s, "pattern")
    if has_pattern {
        let pattern = &s[pattern_at].value
        let (source, is_string) = json.string_of(*pattern)
        if !is_string { ret (false, Invalid) }
        let (compiled, e) = regex.compile(c.arena, source, zero)
        if e != ok { ret (false, Invalid) }
        if !regex.is_match(&compiled, v) { ret (false, ok) }
    }
    ret (true, ok)
}

fn check_array(c: *Checker, s: []const json.Member, items: []const json.Value, n: usize, depth: usize) -> (bool, usize, err) {
    let (min_items_at, has_min_items) = member(s, "minItems")
    if has_min_items {
        let min_items = &s[min_items_at].value
        let (bound, e) = schema_usize(min_items)
        if e != ok { ret (false, n, e) }
        if items.len < bound { ret (false, n, ok) }
    }
    let (max_items_at, has_max_items) = member(s, "maxItems")
    if has_max_items {
        let max_items = &s[max_items_at].value
        let (bound, e) = schema_usize(max_items)
        if e != ok { ret (false, n, e) }
        if items.len > bound { ret (false, n, ok) }
    }
    let (unique_at, has_unique) = member(s, "uniqueItems")
    if has_unique {
        let unique = &s[unique_at].value
        let (wanted, is_bool) = json.bool_of(*unique)
        if !is_bool { ret (false, n, Invalid) }
        if wanted {
            var i = 1usize
            while i < items.len {
                var j = 0usize
                while j < i {
                    if json.values_equal(&items[i], &items[j]) { ret (false, n, ok) }
                    j += 1usize
                }
                i += 1usize
            }
        }
    }
    let (item_schema_at, has_items) = member(s, "items")
    if has_items {
        let item_schema = &s[item_schema_at].value
        var i = 0usize
        while i < items.len {
            let (m, e) = append_index(c, n, i)
            if e != ok { ret (false, n, e) }
            let (valid, failed_at, check_error) = check(c, item_schema, &items[i], m, depth)
            if check_error != ok { ret (false, n, check_error) }
            if !valid { ret (false, failed_at, ok) }
            i += 1usize
        }
    }
    ret (true, n, ok)
}

fn check_object(c: *Checker, s: []const json.Member, members: []const json.Member, n: usize, depth: usize) -> (bool, usize, err) {
    let (required_at, has_required) = member(s, "required")
    if has_required {
        let required = &s[required_at].value
        let (names, is_array) = json.array_of(*required)
        if !is_array { ret (false, n, Invalid) }
        var i = 0usize
        while i < names.len {
            let (name, is_string) = json.string_of(names[i])
            if !is_string { ret (false, n, Invalid) }
            let (_, present) = member(members, name)
            if !present { ret (false, n, ok) }
            i += 1usize
        }
    }
    let (properties_at, has_properties) = member(s, "properties")
    var property_schemas: []const json.Member = zero
    if has_properties {
        let properties = &s[properties_at].value
        let (schemas, is_object) = json.object_of(*properties)
        if !is_object { ret (false, n, Invalid) }
        property_schemas = schemas
        var i = 0usize
        while i < schemas.len {
            let (value_at, present) = member(members, schemas[i].key)
            if present {
                let value = &members[value_at].value
                let (m, e) = append_key(c, n, schemas[i].key)
                if e != ok { ret (false, n, e) }
                let (valid, failed_at, check_error) = check(c, &schemas[i].value, value, m, depth)
                if check_error != ok { ret (false, n, check_error) }
                if !valid { ret (false, failed_at, ok) }
            }
            i += 1usize
        }
    }
    let (additional_at, has_additional) = member(s, "additionalProperties")
    if has_additional {
        let additional = &s[additional_at].value
        let (allowed, is_bool) = json.bool_of(*additional)
        // ponytail: only the boolean form; a schema-valued `additionalProperties` is refused.
        if !is_bool { ret (false, n, Invalid) }
        if !allowed {
            var i = 0usize
            while i < members.len {
                let (_, declared) = member(property_schemas, members[i].key)
                if !declared {
                    let (m, e) = append_key(c, n, members[i].key)
                    if e != ok { ret (false, n, e) }
                    ret (false, m, ok)
                }
                i += 1usize
            }
        }
    }
    ret (true, n, ok)
}

fn subschemas(s: []const json.Member, name: str) -> ([]const json.Value, bool, err) {
    var none: []const json.Value = zero
    let (list_at, present) = member(s, name)
    if !present { ret (none, false, ok) }
    let list = &s[list_at].value
    let (items, is_array) = json.array_of(*list)
    if !is_array { ret (none, true, Invalid) }
    ret (items, true, ok)
}

// `v` against `schema`; `n` is the length of the pointer to `v` in `c.path`. Answers
// (valid, the pointer length of the failure, error).
fn check(c: *Checker, schema: *const json.Value, v: *const json.Value, n: usize, depth: usize) -> (bool, usize, err) {
    if depth >= MAX_DEPTH { ret (false, n, TooDeep) }
    let (literal, is_bool) = json.bool_of(*schema)
    if is_bool { ret (literal, n, ok) }
    let (s, is_object) = json.object_of(*schema)
    if !is_object { ret (false, n, Invalid) }

    let (reference_at, has_ref) = member(s, "$ref")
    if has_ref {
        let reference = &s[reference_at].value
        let (where, is_string) = json.string_of(*reference)
        if !is_string { ret (false, n, Invalid) }
        let (resolved, e) = resolve_ref(c, where)
        if e != ok { ret (false, n, e) }
        let (valid, failed_at, check_error) = check(c, resolved, v, n, depth + 1usize)
        if check_error != ok { ret (false, n, check_error) }
        if !valid { ret (false, failed_at, ok) }
    }

    let (type_name_at, has_type) = member(s, "type")
    if has_type {
        let type_name = &s[type_name_at].value
        let (names, is_list) = json.array_of(*type_name)
        var any = false
        if is_list {
            var i = 0usize
            while i < names.len && !any {
                let (name, is_string) = json.string_of(names[i])
                if !is_string { ret (false, n, Invalid) }
                let (matched, e) = type_matches(name, v)
                if e != ok { ret (false, n, e) }
                any = matched
                i += 1usize
            }
        } else {
            let (name, is_string) = json.string_of(*type_name)
            if !is_string { ret (false, n, Invalid) }
            let (matched, e) = type_matches(name, v)
            if e != ok { ret (false, n, e) }
            any = matched
        }
        if !any { ret (false, n, ok) }
    }

    let (allowed, has_enum, enum_error) = subschemas(s, "enum")
    if enum_error != ok { ret (false, n, enum_error) }
    if has_enum {
        var any = false
        var i = 0usize
        while i < allowed.len && !any {
            any = json.values_equal(v, &allowed[i])
            i += 1usize
        }
        if !any { ret (false, n, ok) }
    }
    let (constant_at, has_const) = member(s, "const")
    if has_const && !json.values_equal(v, &s[constant_at].value) { ret (false, n, ok) }

    let (number, is_number) = json.number_of(*v)
    if is_number {
        let (value, e) = json.number_f64(number)
        if e != ok { ret (false, n, e) }
        let (valid, number_error) = check_number(s, value)
        if number_error != ok { ret (false, n, number_error) }
        if !valid { ret (false, n, ok) }
    }
    let (text, is_string) = json.string_of(*v)
    if is_string {
        let (valid, string_error) = check_string(c, s, text)
        if string_error != ok { ret (false, n, string_error) }
        if !valid { ret (false, n, ok) }
    }
    let (items, is_array) = json.array_of(*v)
    if is_array {
        let (valid, failed_at, array_error) = check_array(c, s, items, n, depth + 1usize)
        if array_error != ok { ret (false, n, array_error) }
        if !valid { ret (false, failed_at, ok) }
    }
    let (members, v_is_object) = json.object_of(*v)
    if v_is_object {
        let (valid, failed_at, object_error) = check_object(c, s, members, n, depth + 1usize)
        if object_error != ok { ret (false, n, object_error) }
        if !valid { ret (false, failed_at, ok) }
    }

    let (all, has_all, all_error) = subschemas(s, "allOf")
    if all_error != ok { ret (false, n, all_error) }
    if has_all {
        var i = 0usize
        while i < all.len {
            let (valid, failed_at, e) = check(c, &all[i], v, n, depth + 1usize)
            if e != ok { ret (false, n, e) }
            if !valid { ret (false, failed_at, ok) }
            i += 1usize
        }
    }
    let (any_list, has_any, any_error) = subschemas(s, "anyOf")
    if any_error != ok { ret (false, n, any_error) }
    if has_any {
        var matched = false
        var i = 0usize
        while i < any_list.len && !matched {
            let (valid, _, e) = check(c, &any_list[i], v, n, depth + 1usize)
            if e != ok { ret (false, n, e) }
            matched = valid
            i += 1usize
        }
        if !matched { ret (false, n, ok) }
    }
    let (one_list, has_one, one_error) = subschemas(s, "oneOf")
    if one_error != ok { ret (false, n, one_error) }
    if has_one {
        var matches = 0usize
        var i = 0usize
        while i < one_list.len {
            let (valid, _, e) = check(c, &one_list[i], v, n, depth + 1usize)
            if e != ok { ret (false, n, e) }
            if valid { matches += 1usize }
            i += 1usize
        }
        if matches != 1usize { ret (false, n, ok) }
    }
    let (negated_at, has_not) = member(s, "not")
    if has_not {
        let negated = &s[negated_at].value
        let (valid, _, e) = check(c, negated, v, n, depth + 1usize)
        if e != ok { ret (false, n, e) }
        if valid { ret (false, n, ok) }
    }
    ret (true, n, ok)
}

// `doc` against `root` (both parsed trees); answers (valid, the length of the failing
// pointer written into `path`, error). A valid document leaves `path` empty.
fn validate_value(a: *mem.Arena, root: *const json.Value, doc: *const json.Value, path: []u8) -> (bool, usize, err) {
    var c = Checker { arena: a, root: root, path: path }
    let (valid, failed_at, e) = check(&c, root, doc, 0usize, 0usize)
    if e != ok { ret (false, 0usize, e) }
    if valid { ret (true, 0usize, ok) }
    ret (false, failed_at, ok)
}

// Parse `schema_json` and `doc_json` into `a`, then `validate_value`.
fn validate(a: *mem.Arena, schema_json: str, doc_json: str, path: []u8) -> (bool, usize, err) {
    let (schema, schema_error) = json.parse(a, schema_json, zero)
    if schema_error != ok { ret (false, 0usize, schema_error) }
    let (doc, doc_error) = json.parse(a, doc_json, zero)
    if doc_error != ok { ret (false, 0usize, doc_error) }
    let (valid, failed_at, e) = validate_value(a, &schema, &doc, path)
    ret (valid, failed_at, e)
}
