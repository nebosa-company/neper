// The pure mapping of Petcow's native AWS providers (L048), after `provider/aws/{s3,iam,ec2,lightsail}.rs` and the
// attribute helpers of `provider/aws/mod.rs`: what each provider decides before it calls the SDK, so a recorded or modelled
// response can drive the rest offline.
//
//   * S3: the bucket-name rules checked locally (3 to 63 bytes, lower-case letters, digits, `-` and `.`, a letter or digit
//     at both ends), `bool`/`str` attributes, and the user `tags` mapping (string to string, others skipped, in key order);
//   * IAM: the percent-decoding of an inline policy document (a malformed byte replaced as `from_utf8_lossy` does), the
//     `assume_role_policy` as text (a string passes through, anything else is written as compact JSON in member order,
//     a missing one is an error), the managed tag list and the sorted `managed_policy_arns`;
//   * EC2: the tag list stamped on a managed resource (`Name`, `petcow:managed`, `petcow:name`, then the user's), the user
//     tags read back (identity tags and `Name` excluded, an entry without key or value skipped), the PetCow name and the
//     display name of an unmanaged resource (its `Name` tag, else its id), integer and string-list attributes, and the
//     security-group ingress rules (`protocol` and `cidr` required, ports 32-bit as the original casts them);
//   * Lightsail: the three type names, required and optional string attributes, and the two identity tags; and the list
//     mapping over the SDK's wire JSON (`ls_instance`, `ls_database`, `ls_domain`, `ls_list` following page tokens through an
//     injected `LsSource`, `ls_filter` for discover versus discover_unmanaged).
//
// Tags are `[key, value]` pairs (either may be null). The AWS calls themselves are host code.
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.mem
use e.str

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { ret ir.Obj { items: zero, len: 0usize, arena: a } }
    ret o
}

fn managed_key() -> str { ret "petcow:managed" }

fn name_key() -> str { ret "petcow:name" }

// `PetcowError::resource(id, message)` as it is displayed.
fn resource_error(a: *mem.Arena, logical_id: str, message: str) -> str {
    ret join(a, join(a, join(a, "in resource '", logical_id), "': "), message)
}

// --- S3 --------------------------------------------------------------------------------------------------------------

// Whether a bucket name passes the rules checkable before any call: `(true, "")`, or the displayed error.
fn validate_bucket_name(a: *mem.Arena, name: str) -> (bool, str) {
    var why = ""
    if name.len < 3usize || name.len > 63usize { why = "must be 3–63 characters" }
    if why.len == 0usize {
        var at = 0usize
        while at < name.len {
            let c = name[at]
            let lower = c >= 97u8 && c <= 122u8
            let digit = c >= 48u8 && c <= 57u8
            if !lower && !digit && c != 45u8 && c != 46u8 { why = "only lowercase letters, digits, '-' and '.' are allowed" }
            at += 1usize
        }
    }
    if why.len == 0usize {
        let first = name[0]
        let last = name[name.len - 1usize]
        if first == 45u8 || last == 45u8 || first == 46u8 || last == 46u8 { why = "must start and end with a letter or digit" }
    }
    if why.len > 0usize { ret (false, resource_error(a, name, join(a, "invalid S3 bucket name: ", why))) }
    ret (true, "")
}
// `attrs[key]` as a bool, false when absent or not a bool.
fn attr_bool(attrs: json.Value, key: str) -> bool {
    let (v, found) = ir.get(attrs, key)
    if !found { ret false }
    switch v {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

// `attrs[key]` as a string, when it is one.
fn attr_str(attrs: json.Value, key: str) -> (str, bool) {
    let (v, found) = ir.get(attrs, key)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(v)
    ret (s, is_text)
}

// The `tags:` mapping of string to string, in key order; an entry that is not a pair of strings is skipped.
fn user_tags(a: *mem.Arena, attrs: json.Value) -> json.Value {
    var out = obj(a)
    let (tags, found) = ir.get(attrs, "tags")
    let (members, is_object) = ir.members_of(tags)
    if !found || !is_object { ret ir.obj_value(&out) }
    var at = 0usize
    while at < members.len {
        let (s, is_text) = ir.string_of(members[at].value)
        if is_text { let put = ir.put(&out, members[at].key, text(s)) }
        at += 1usize
    }
    ret ir.obj_value(&out)
}

// --- IAM -------------------------------------------------------------------------------------------------------------

fn hex_value(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

fn continuation(b: u8, low: u8, high: u8) -> bool { ret b >= low && b <= high }

// How many bytes at `at` form one well-formed scalar (1 to 4), or the error: negative of the bytes of the maximal valid
// prefix (as `Utf8Error::error_len` reports), or 0 when the input ends inside a sequence.
fn utf8_step(s: str, at: usize) -> i64 {
    let b = s[at]
    if b < 128u8 { ret 1i64 }
    var need = 0usize
    var low = 128u8
    var high = 191u8
    if b >= 194u8 && b <= 223u8 {
        need = 1usize
    } else if b >= 224u8 && b <= 239u8 {
        need = 2usize
        if b == 224u8 { low = 160u8 }
        if b == 237u8 { high = 159u8 }
    } else if b >= 240u8 && b <= 244u8 {
        need = 3usize
        if b == 240u8 { low = 144u8 }
        if b == 244u8 { high = 143u8 }
    } else {
        ret -1i64
    }
    var seen = 1usize
    while seen <= need {
        if at + seen >= s.len { ret 0i64 }
        let c = s[at + seen]
        var ok_byte = false
        if seen == 1usize { ok_byte = continuation(c, low, high) } else { ok_byte = continuation(c, 128u8, 191u8) }
        if !ok_byte { ret -i64(seen) }
        seen += 1usize
    }
    ret i64(need + 1usize)
}

// `String::from_utf8_lossy`: each maximal ill-formed subpart becomes one U+FFFD.
fn lossy(a: *mem.Arena, bytes: str) -> str {
    let (made, e) = str.builder(a, bytes.len + 8usize)
    if e != ok { ret bytes }
    var b = made
    var at = 0usize
    while at < bytes.len {
        let step = utf8_step(bytes, at)
        if step > 0i64 {
            let n = usize(step)
            let pushed = str.push(&b, bytes[at..at + n])
            at += n
        } else {
            let pushed = str.push(&b, "�")
            if step == 0i64 { at = bytes.len } else { at += usize(-step) }
        }
    }
    ret str.done(&b)
}

// Decode the percent-encoding AWS uses for inline policy documents; a `%` not followed by two hex digits stays.
fn percent_decode(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 37u8 && i + 2usize < s.len {
            let hi = hex_value(s[i + 1usize])
            let lo = hex_value(s[i + 2usize])
            if hi >= 0i32 && lo >= 0i32 {
                out[n] = u8(hi * 16i32 + lo)
                n += 1usize
                i += 3usize
                continue
            }
        }
        out[n] = s[i]
        n += 1usize
        i += 1usize
    }
    ret lossy(a, out[0usize..n])
}

// The desired `assume_role_policy` as a JSON string: `(text, true, "")`, or `("", false, error)` when missing.
fn assume_role_json(a: *mem.Arena, attrs: json.Value, name: str) -> (str, bool, str) {
    let (v, found) = ir.get(attrs, "assume_role_policy")
    if !found { ret ("", false, resource_error(a, name, "aws.iam_role requires 'assume_role_policy'")) }
    let (s, is_text) = ir.string_of(v)
    if is_text { ret (s, true, "") }
    let (out, e) = chain.plain_json(a, v)
    if e != ok { ret ("", false, resource_error(a, name, "serializing assume_role_policy: failed")) }
    ret (out, true, "")
}

fn pair(a: *mem.Arena, k: str, v: str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, 2usize)
    out[0] = text(k)
    out[1] = text(v)
    ret json.Value{ Array: out[0usize..2usize] }
}

// The tag list stamped on an IAM role: `petcow:managed`, `petcow:name`, then the user's in key order.
fn managed_iam_tags(a: *mem.Arena, name: str, user: json.Value) -> json.Value {
    let (members, is_object) = ir.members_of(user)
    let (out, e) = mem.alloc[json.Value](a, members.len + 2usize)
    out[0] = pair(a, managed_key(), "true")
    out[1] = pair(a, name_key(), name)
    var n = 2usize
    var at = 0usize
    while at < members.len {
        let (s, is_text) = ir.string_of(members[at].value)
        if is_text {
            out[n] = pair(a, members[at].key, s)
            n += 1usize
        }
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..n] }
}

// `managed_policy_arns`: the strings of the list, sorted.
fn desired_arns(a: *mem.Arena, attrs: json.Value) -> []const str {
    let names = string_list(a, attrs, "managed_policy_arns")
    let (out, e) = mem.alloc[str](a, names.len + 1usize)
    if e != ok { ret names }
    var i = 0usize
    while i < names.len {
        let cur = names[i]
        var j = i
        while j > 0usize && str.compare(out[j - 1usize], cur) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..names.len]
}

// --- EC2 -------------------------------------------------------------------------------------------------------------

// A list-of-strings attribute: the string elements, nothing when it is not a list.
fn string_list(a: *mem.Arena, attrs: json.Value, key: str) -> []const str {
    let (v, found) = ir.get(attrs, key)
    let (xs, is_array) = ir.items_of(v)
    if !found || !is_array { ret zero }
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < xs.len {
        let (s, is_text) = ir.string_of(xs[i])
        if is_text {
            out[n] = s
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// An integer attribute: a number written without fraction or exponent that fits 64 bits.
fn attr_i64(attrs: json.Value, key: str) -> (i64, bool) {
    let (v, found) = ir.get(attrs, key)
    if !found { ret (0i64, false) }
    switch v {
    case .Number as n:
        if str.contains(n.lexeme, ".") || str.contains(n.lexeme, "e") || str.contains(n.lexeme, "E") { ret (0i64, false) }
        let (value, e) = json.number_i64(n)
        if e != ok { ret (0i64, false) }
        ret (value, true)
    default:
        ret (0i64, false)
    }
}

// The tag list stamped on an EC2 resource: `Name`, `petcow:managed`, `petcow:name`, then the user's in key order.
fn managed_tags(a: *mem.Arena, name: str, user: json.Value) -> json.Value {
    let (members, is_object) = ir.members_of(user)
    let (out, e) = mem.alloc[json.Value](a, members.len + 3usize)
    out[0] = pair(a, "Name", name)
    out[1] = pair(a, managed_key(), "true")
    out[2] = pair(a, name_key(), name)
    var n = 3usize
    var at = 0usize
    while at < members.len {
        let (s, is_text) = ir.string_of(members[at].value)
        if is_text {
            out[n] = pair(a, members[at].key, s)
            n += 1usize
        }
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..n] }
}

fn tag_key(tags: []const json.Value, at: usize) -> (str, bool) {
    let (pair_items, is_array) = ir.items_of(tags[at])
    if !is_array || pair_items.len < 1usize { ret ("", false) }
    let (s, is_text) = ir.string_of(pair_items[0])
    ret (s, is_text)
}

fn tag_value(tags: []const json.Value, at: usize) -> (str, bool) {
    let (pair_items, is_array) = ir.items_of(tags[at])
    if !is_array || pair_items.len < 2usize { ret ("", false) }
    let (s, is_text) = ir.string_of(pair_items[1])
    ret (s, is_text)
}

// The user tags of a live tag set as a mapping: identity tags and `Name` left out, an entry missing key or value skipped.
fn observed_user_tags(a: *mem.Arena, tags: json.Value) -> json.Value {
    var out = obj(a)
    let xs = items(tags)
    var at = 0usize
    while at < xs.len {
        let (k, has_k) = tag_key(xs, at)
        let (v, has_v) = tag_value(xs, at)
        if has_k && has_v && !str.eq(k, managed_key()) && !str.eq(k, name_key()) && !str.eq(k, "Name") {
            let put = ir.put(&out, k, text(v))
        }
        at += 1usize
    }
    ret ir.obj_value(&out)
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

// The value of the first `petcow:name` tag, when it has one.
fn petcow_name(tags: json.Value) -> (str, bool) {
    let xs = items(tags)
    var at = 0usize
    while at < xs.len {
        let (k, has_k) = tag_key(xs, at)
        if has_k && str.eq(k, name_key()) {
            let (v, has_v) = tag_value(xs, at)
            ret (v, has_v)
        }
        at += 1usize
    }
    ret ("", false)
}

// An unmanaged resource's display name: its first `Name` tag when that has a non-empty value, else its id.
fn name_or_id(tags: json.Value, real_id: str) -> str {
    let xs = items(tags)
    var at = 0usize
    while at < xs.len {
        let (k, has_k) = tag_key(xs, at)
        if has_k && str.eq(k, "Name") {
            let (v, has_v) = tag_value(xs, at)
            if has_v && v.len > 0usize { ret v }
            ret real_id
        }
        at += 1usize
    }
    ret real_id
}

// The lightweight observed record of an unmanaged resource: `{name, type, attributes: {tags}, real_id}`.
fn unmanaged(a: *mem.Arena, type_: str, tags: json.Value, real_id: str) -> json.Value {
    var attributes = obj(a)
    let put = ir.put(&attributes, "tags", observed_user_tags(a, tags))
    var out = obj(a)
    let p1 = ir.put(&out, "name", text(name_or_id(tags, real_id)))
    let p2 = ir.put(&out, "type", text(type_))
    let p3 = ir.put(&out, "attributes", ir.obj_value(&attributes))
    let p4 = ir.put(&out, "real_id", text(real_id))
    ret ir.obj_value(&out)
}

fn wrap_i32(v: i64) -> i64 {
    let low = v & 4294967295i64
    if low >= 2147483648i64 { ret low - 4294967296i64 }
    ret low
}

// The `ingress` rules as permissions `[{protocol, from, to, cidrs}]`: `(rules, true, "")`, or `([], false, error)` for a
// rule that is not a mapping or lacks `protocol` or `cidr`. A port defaults to 0 (`to_port` to `from_port`) and is cast to 32
// bits.
fn ingress_permissions(a: *mem.Arena, name: str, attrs: json.Value) -> (json.Value, bool, str) {
    let (rules, found) = ir.get(attrs, "ingress")
    let (xs, is_array) = ir.items_of(rules)
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if !found || !is_array { ret (json.Value{ Array: out[0usize..0usize] }, true, "") }
    var n = 0usize
    var i = 0usize
    while i < xs.len {
        let (members, is_object) = ir.members_of(xs[i])
        if !is_object { ret (json.Value{ Array: out[0usize..0usize] }, false, resource_error(a, name, "each ingress rule must be a mapping")) }
        let (proto, has_proto) = attr_str(xs[i], "protocol")
        if !has_proto { ret (json.Value{ Array: out[0usize..0usize] }, false, resource_error(a, name, "ingress rule needs 'protocol'")) }
        var from = 0i64
        let (f_value, has_from) = attr_i64(xs[i], "from_port")
        if has_from { from = wrap_i32(f_value) }
        var to = from
        let (t_value, has_to) = attr_i64(xs[i], "to_port")
        if has_to { to = wrap_i32(t_value) }
        let (cidr, has_cidr) = attr_str(xs[i], "cidr")
        if !has_cidr { ret (json.Value{ Array: out[0usize..0usize] }, false, resource_error(a, name, "ingress rule needs 'cidr'")) }
        var o = obj(a)
        let p1 = ir.put(&o, "protocol", text(proto))
        let p2 = ir.put(&o, "from", ir.number_lexeme(int_text(a, from)))
        let p3 = ir.put(&o, "to", ir.number_lexeme(int_text(a, to)))
        let (cidrs, ce) = mem.alloc[json.Value](a, 1usize)
        cidrs[0] = text(cidr)
        let p4 = ir.put(&o, "cidrs", json.Value{ Array: cidrs[0usize..1usize] })
        out[n] = ir.obj_value(&o)
        n += 1usize
        i += 1usize
    }
    ret (json.Value{ Array: out[0usize..n] }, true, "")
}

fn int_text(a: *mem.Arena, v: i64) -> str {
    let (made, e) = str.builder(a, 24usize)
    if e != ok { ret "0" }
    var b = made
    let pushed = str.push_i64(&b, v)
    ret str.done(&b)
}

// --- Lightsail -------------------------------------------------------------------------------------------------------

// The public type string of a Lightsail kind: `instance`, `database` or `domain`.
fn lightsail_type_name(kind: str) -> str {
    if str.eq(kind, "instance") { ret "aws.lightsail_instance" }
    if str.eq(kind, "database") { ret "aws.lightsail_database" }
    ret "aws.lightsail_domain"
}

// A required string attribute: `(value, true, "")`, or the displayed missing-attribute error.
fn req_attr(a: *mem.Arena, attrs: json.Value, key: str, kind: str) -> (str, bool, str) {
    let (s, found) = attr_str(attrs, key)
    if found { ret (s, true, "") }
    ret ("", false, resource_error(a, kind, join(a, join(a, "missing required attribute '", key), "'")))
}

// The two identity tags a created Lightsail resource carries.
fn lightsail_managed_tags(a: *mem.Arena, name: str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, 2usize)
    out[0] = pair(a, managed_key(), "true")
    out[1] = pair(a, name_key(), name)
    ret json.Value{ Array: out[0usize..2usize] }
}

// --- Lightsail list mapping --------------------------------------------------------------------------------------------

// The text of a member of a Lightsail resource, as the SDK's `Option<&str>` getter answers it.
fn ls_text(v: json.Value, key: str) -> (str, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(x)
    ret (s, is_text)
}

// A member of a nested object (`state.name`, `location.availabilityZone`).
fn ls_nested(v: json.Value, outer: str, key: str) -> (str, bool) {
    let (o, found) = ir.get(v, outer)
    if !found { ret ("", false) }
    let (s, has) = ls_text(o, key)
    ret (s, has)
}

fn ls_put(o: *ir.Obj, key: str, value: str, has: bool) {
    if has {
        let p = ir.put(o, key, text(value))
    }
}

fn ls_observed(a: *mem.Arena, type_: str, name: str, attributes: json.Value, arn: str, has_arn: bool) -> json.Value {
    var out = obj(a)
    let p1 = ir.put(&out, "name", text(name))
    let p2 = ir.put(&out, "type", text(type_))
    let p3 = ir.put(&out, "attributes", attributes)
    if has_arn {
        let p4 = ir.put(&out, "real_id", text(arn))
    } else {
        let p5 = ir.put(&out, "real_id", .Null)
    }
    ret ir.obj_value(&out)
}

// One instance of a `GetInstances` page as an observed resource; `(.., false)` when it has no name (it is skipped).
fn ls_instance(a: *mem.Arena, item: json.Value) -> (json.Value, bool) {
    let (name, has_name) = ls_text(item, "name")
    if !has_name { ret (.Null, false) }
    var attrs = obj(a)
    let (state, has_state) = ls_nested(item, "state", "name")
    ls_put(&attrs, "state", state, has_state)
    let (blueprint, has_blueprint) = ls_text(item, "blueprintId")
    ls_put(&attrs, "blueprint", blueprint, has_blueprint)
    let (bundle, has_bundle) = ls_text(item, "bundleId")
    ls_put(&attrs, "bundle", bundle, has_bundle)
    let (zone, has_zone) = ls_nested(item, "location", "availabilityZone")
    ls_put(&attrs, "availability_zone", zone, has_zone)
    let (ip, has_ip) = ls_text(item, "publicIpAddress")
    ls_put(&attrs, "public_ip", ip, has_ip)
    let (arn, has_arn) = ls_text(item, "arn")
    ret (ls_observed(a, lightsail_type_name("instance"), name, ir.obj_value(&attrs), arn, has_arn), true)
}

// One relational database of a `GetRelationalDatabases` page.
fn ls_database(a: *mem.Arena, item: json.Value) -> (json.Value, bool) {
    let (name, has_name) = ls_text(item, "name")
    if !has_name { ret (.Null, false) }
    var attrs = obj(a)
    let (engine, has_engine) = ls_text(item, "engine")
    ls_put(&attrs, "engine", engine, has_engine)
    let (version, has_version) = ls_text(item, "engineVersion")
    ls_put(&attrs, "engine_version", version, has_version)
    let (state, has_state) = ls_text(item, "state")
    ls_put(&attrs, "state", state, has_state)
    let (blueprint, has_blueprint) = ls_text(item, "relationalDatabaseBlueprintId")
    ls_put(&attrs, "blueprint", blueprint, has_blueprint)
    let (bundle, has_bundle) = ls_text(item, "relationalDatabaseBundleId")
    ls_put(&attrs, "bundle", bundle, has_bundle)
    let (master, has_master) = ls_text(item, "masterDatabaseName")
    ls_put(&attrs, "master_database_name", master, has_master)
    let (user, has_user) = ls_text(item, "masterUsername")
    ls_put(&attrs, "master_username", user, has_user)
    let (arn, has_arn) = ls_text(item, "arn")
    ret (ls_observed(a, lightsail_type_name("database"), name, ir.obj_value(&attrs), arn, has_arn), true)
}

// One domain of a `GetDomains` answer: the record count and a `type name -> target` line per entry.
fn ls_domain(a: *mem.Arena, item: json.Value) -> (json.Value, bool) {
    let (name, has_name) = ls_text(item, "name")
    if !has_name { ret (.Null, false) }
    var attrs = obj(a)
    let (entries_value, has_entries) = ir.get(item, "domainEntries")
    let entries = items(entries_value)
    let (total, ce) = json.number_from_i64(a, i64(entries.len))
    let p1 = ir.put(&attrs, "dns_record_count", json.Value{ Number: total })
    let (lines, le) = mem.alloc[json.Value](a, entries.len + 1usize)
    var at = 0usize
    while at < entries.len {
        let (entry_type, has_type) = ls_text(entries[at], "type")
        let (entry_name, has_entry_name) = ls_text(entries[at], "name")
        let (entry_target, has_target) = ls_text(entries[at], "target")
        lines[at] = text(join(a, join(a, join(a, join(a, entry_type, " "), entry_name), " -> "), entry_target))
        at += 1usize
    }
    let p2 = ir.put(&attrs, "dns_records", json.Value{ Array: lines[0usize..entries.len] })
    let (arn, has_arn) = ls_text(item, "arn")
    ret (ls_observed(a, lightsail_type_name("domain"), name, ir.obj_value(&attrs), arn, has_arn), true)
}

// One page the SDK answered: the items of the kind's list member, the next page token, or the displayed SDK error.
type LsPage = struct { good: bool, failure: str, items: []const json.Value, has_next: bool, next: str }

// Fetches a page, continuing from the token when `has_token`.
type LsSource = struct { ctx: *void, page: fn(*void, str, bool) -> LsPage }

fn ls_one(a: *mem.Arena, kind: str, item: json.Value) -> (json.Value, bool) {
    if str.eq(kind, "instance") {
        let (v, has) = ls_instance(a, item)
        ret (v, has)
    }
    if str.eq(kind, "database") {
        let (v, has) = ls_database(a, item)
        ret (v, has)
    }
    let (v, has) = ls_domain(a, item)
    ret (v, has)
}

// Every resource of `kind` (`instance`, `database`, `domain`) as observed resources, following page tokens as
// `list_instances` does (a domain list is a single call). `(list, true, "")`, or the displayed error of the failing call.
fn ls_list(a: *mem.Arena, kind: str, src: *const LsSource) -> (json.Value, bool, str) {
    let (first, fe) = mem.alloc[json.Value](a, 8usize)
    var out = first
    var cap = 8usize
    var n = 0usize
    var token = ""
    var has_token = false
    var more = true
    while more {
        let page = src.page(src.ctx, token, has_token)
        if !page.good {
            var call = "get_domains"
            if str.eq(kind, "instance") { call = "get_instances" }
            if str.eq(kind, "database") { call = "get_relational_databases" }
            ret (.Null, false, resource_error(a, lightsail_type_name(kind), join(a, join(a, call, ": "), page.failure)))
        }
        var at = 0usize
        while at < page.items.len {
            let (seen, has) = ls_one(a, kind, page.items[at])
            if has {
                if n == cap {
                    let (bigger, ge) = mem.alloc[json.Value](a, cap * 2usize)
                    var k = 0usize
                    while k < n {
                        bigger[k] = out[k]
                        k += 1usize
                    }
                    out = bigger
                    cap = cap * 2usize
                }
                out[n] = seen
                n += 1usize
            }
            at += 1usize
        }
        more = false
        if !str.eq(kind, "domain") && page.has_next {
            token = page.next
            has_token = true
            more = true
        }
    }
    ret (json.Value{ Array: out[0usize..n] }, true, "")
}

// `discover` (`managed` true) keeps the resources whose Lightsail name starts with `petcow-`, `discover_unmanaged` the rest.
fn ls_filter(a: *mem.Arena, observed: json.Value, managed: bool) -> json.Value {
    let xs = items(observed)
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    var n = 0usize
    var at = 0usize
    while at < xs.len {
        let (name, has) = ls_text(xs[at], "name")
        if str.starts_with(name, "petcow-") == managed {
            out[n] = xs[at]
            n += 1usize
        }
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..n] }
}
