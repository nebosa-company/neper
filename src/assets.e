// Embedded assets (D80, D777): the root project's `project.yaml` `assets:` mapping
// becomes the `e.asset` registry. The loader reads the manifest when the project is
// discovered, reads every declared file, hashes it, sorts the entries by logical
// name and generates the module's source -- the same fence `lib/e/asset.e` has for
// a build without assets -- as an overlay on `lib/e/asset.e`, which is how the
// registry reaches the image: bytes, names and media types as string literals in the
// read-only data, attributes filled once into a module-scope table, so a lookup
// allocates nothing and answers executable-backed slices. The generated text is the
// module's text to every hash the toolchain keeps, so an asset's bytes, name, type
// and attributes are the build identity, and the artifact of `e.asset` is stale the
// moment a declared file changes.
//
// The manifest subset read here is pacman's (docs/pacman.md section 3): under
// `assets:`, each entry is a logical name at two spaces with `path`, an optional
// `media_type` (default `application/octet-stream`) and optional `attributes` as a
// flow mapping `{k: v, ...}` or a nested mapping at six spaces; scalars are plain or
// double-quoted with `\"` and `\\`. Anything else under an entry is `InvalidManifest`;
// a file that cannot be read is `AssetMissing`; more than MAX_ASSETS entries, more
// than MAX_ATTRIBUTES on one, or more than MAX_TOTAL bytes in all is `AssetTooLarge`.
// A `project.yaml` with no `assets:` key, or none at all, leaves `lib/e/asset.e`
// as written: the empty registry.

use e.mem
use artifact_hash
use source

error InvalidManifest
error AssetMissing
error AssetTooLarge

const MAX_ASSETS: usize = 256usize
const MAX_ATTRIBUTES: usize = 16usize
const MAX_TOTAL: usize = 4194304usize

type Entry = struct {
    name: str,
    path: str,
    media_type: str,
    attribute_names: [16]str,
    attribute_values: [16]str,
    attribute_count: usize,
    bytes: str,
    hex: [64]u8,
}

type Out = struct { data: []u8, at: usize }

fn asset_put(o: *Out, s: str) -> err {
    if o.at + s.len > o.data.len { ret AssetTooLarge }
    var i = 0usize
    while i < s.len {
        o.data[o.at] = s[i]
        o.at += 1usize
        i += 1usize
    }
    ret ok
}

fn asset_decimal(o: *Out, v: usize) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var rest = v
    if rest == 0usize {
        digits[0usize] = 48u8
        n = 1usize
    }
    while rest > 0usize {
        digits[n] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        n += 1usize
    }
    while n > 0usize {
        n = n - 1usize
        if o.at >= o.data.len { ret AssetTooLarge }
        o.data[o.at] = digits[n]
        o.at += 1usize
    }
    ret ok
}

fn asset_nibble(v: usize) -> u8 {
    if v < 10usize { ret u8(48usize + v) }
    ret u8(87usize + v)
}

// A byte string as a source literal: printable ASCII as itself, the rest as `\xNN`.
fn asset_literal(o: *Out, bytes: str) -> err {
    try asset_put(o, "\"")
    var i = 0usize
    while i < bytes.len {
        let b = bytes[i]
        i += 1usize
        if b == 34u8 {
            try asset_put(o, "\\\"")
            continue
        }
        if b == 92u8 {
            try asset_put(o, "\\\\")
            continue
        }
        if b >= 32u8 && b < 127u8 {
            if o.at >= o.data.len { ret AssetTooLarge }
            o.data[o.at] = b
            o.at += 1usize
            continue
        }
        var escape: [4]u8 = zero
        escape[0usize] = 92u8
        escape[1usize] = 120u8
        escape[2usize] = asset_nibble(usize(b) / 16usize)
        escape[3usize] = asset_nibble(usize(b) & 15usize)
        try asset_put(o, escape[0usize..4usize])
    }
    ret asset_put(o, "\"")
}

fn asset_trim(s: str) -> str {
    var start = 0usize
    while start < s.len && (s[start] == 32u8 || s[start] == 9u8 || s[start] == 13u8) { start += 1usize }
    var end = s.len
    while end > start && (s[end - 1usize] == 32u8 || s[end - 1usize] == 9u8 || s[end - 1usize] == 13u8) { end = end - 1usize }
    ret s[start..end]
}

fn asset_indent(line: str) -> usize {
    var n = 0usize
    while n < line.len && line[n] == 32u8 { n += 1usize }
    ret n
}

fn asset_same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn asset_before(a: str, b: str) -> bool {
    var i = 0usize
    while i < a.len && i < b.len {
        if a[i] != b[i] { ret a[i] < b[i] }
        i += 1usize
    }
    ret a.len < b.len
}

// A scalar: double-quoted with `\"` and `\\`, or plain and trimmed.
fn asset_scalar(a: *mem.Arena, raw: str) -> (str, err) {
    let t = asset_trim(raw)
    if t.len == 0usize || t[0usize] != 34u8 { ret (t, ok) }
    if t.len < 2usize || t[t.len - 1usize] != 34u8 { ret ("", InvalidManifest) }
    let (out, out_error) = mem.alloc[u8](a, t.len)
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    var i = 1usize
    while i + 1usize < t.len {
        var b = t[i]
        if b == 92u8 {
            i += 1usize
            if i + 1usize >= t.len { ret ("", InvalidManifest) }
            b = t[i]
            if b != 34u8 && b != 92u8 { ret ("", InvalidManifest) }
        } else {
            if b == 34u8 { ret ("", InvalidManifest) }
        }
        out[n] = b
        n += 1usize
        i += 1usize
    }
    ret (out[..n], ok)
}

// `key: value` split at the first colon followed by a space or the end.
fn asset_split(line: str) -> (str, str, bool) {
    var i = 0usize
    var quoted = false
    while i < line.len {
        let b = line[i]
        if b == 34u8 { quoted = !quoted }
        if b == 58u8 && !quoted && (i + 1usize == line.len || line[i + 1usize] == 32u8) {
            ret (line[..i], line[i + 1usize..], true)
        }
        i += 1usize
    }
    ret ("", "", false)
}

fn add_attribute(a: *mem.Arena, e: *Entry, raw_key: str, raw_value: str) -> err {
    let most = MAX_ATTRIBUTES
    if e.attribute_count >= most { ret AssetTooLarge }
    let (key, key_error) = asset_scalar(a, raw_key)
    if key_error != ok { ret key_error }
    let (value, value_error) = asset_scalar(a, raw_value)
    if value_error != ok { ret value_error }
    if key.len == 0usize { ret InvalidManifest }
    var i = 0usize
    while i < e.attribute_count {
        if asset_same(e.attribute_names[i], key) { ret InvalidManifest }
        i += 1usize
    }
    e.attribute_names[e.attribute_count] = key
    e.attribute_values[e.attribute_count] = value
    e.attribute_count += 1usize
    ret ok
}

// A flow mapping `{k: v, k: "v"}` on one line.
fn flow_attributes(a: *mem.Arena, e: *Entry, raw: str) -> err {
    let t = asset_trim(raw)
    if t.len < 2usize || t[0usize] != 123u8 || t[t.len - 1usize] != 125u8 { ret InvalidManifest }
    let inner = asset_trim(t[1usize..t.len - 1usize])
    if inner.len == 0usize { ret ok }
    var start = 0usize
    var i = 0usize
    var quoted = false
    while i <= inner.len {
        if i == inner.len || (inner[i] == 44u8 && !quoted) {
            let pair = asset_trim(inner[start..i])
            var colon = 0usize
            var in_quote = false
            while colon < pair.len {
                if pair[colon] == 34u8 { in_quote = !in_quote }
                if pair[colon] == 58u8 && !in_quote { break }
                colon += 1usize
            }
            if colon >= pair.len { ret InvalidManifest }
            try add_attribute(a, e, pair[..colon], pair[colon + 1usize..])
            start = i + 1usize
        } else {
            if inner[i] == 34u8 { quoted = !quoted }
        }
        i += 1usize
    }
    ret ok
}

// The entries of the `assets:` mapping, or none when the manifest has no such key.
fn parse_manifest(a: *mem.Arena, text: str, entries: []Entry) -> (usize, err) {
    var count = 0usize
    var in_assets = false
    var in_attributes = false
    var at = 0usize
    while at < text.len {
        var end = at
        while end < text.len && text[end] != 10u8 { end += 1usize }
        let line = text[at..end]
        at = end + 1usize
        let body = asset_trim(line)
        if body.len == 0usize || body[0usize] == 35u8 { continue }
        let indent = asset_indent(line)
        if indent == 0usize {
            in_assets = asset_same(body, "assets:")
            in_attributes = false
            continue
        }
        if !in_assets { continue }
        let (key, value, split) = asset_split(body)
        if !split { ret (0usize, InvalidManifest) }
        if indent == 2usize {
            if asset_trim(value).len != 0usize { ret (0usize, InvalidManifest) }
            let most = MAX_ASSETS
            if count >= most { ret (0usize, AssetTooLarge) }
            let (name, name_error) = asset_scalar(a, key)
            if name_error != ok { ret (0usize, name_error) }
            if name.len == 0usize { ret (0usize, InvalidManifest) }
            var i = 0usize
            while i < count {
                if asset_same(entries[i].name, name) { ret (0usize, InvalidManifest) }
                i += 1usize
            }
            var fresh: Entry = zero
            fresh.name = name
            fresh.media_type = "application/octet-stream"
            entries[count] = fresh
            count += 1usize
            in_attributes = false
            continue
        }
        if count == 0usize { ret (0usize, InvalidManifest) }
        if indent == 6usize && in_attributes {
            let nested_error = add_attribute(a, &entries[count - 1usize], key, value)
            if nested_error != ok { ret (0usize, nested_error) }
            continue
        }
        if indent != 4usize { ret (0usize, InvalidManifest) }
        in_attributes = false
        let e = &entries[count - 1usize]
        let k = asset_trim(key)
        if asset_same(k, "path") {
            let (path, path_error) = asset_scalar(a, value)
            if path_error != ok { ret (0usize, path_error) }
            if !asset_path_safe(path) { ret (0usize, InvalidManifest) }
            e.path = path
            continue
        }
        if asset_same(k, "media_type") {
            let (media, media_error) = asset_scalar(a, value)
            if media_error != ok { ret (0usize, media_error) }
            e.media_type = media
            continue
        }
        if !asset_same(k, "attributes") { ret (0usize, InvalidManifest) }
        if asset_trim(value).len == 0usize {
            in_attributes = true
        } else {
            let flow_error = flow_attributes(a, e, value)
            if flow_error != ok { ret (0usize, flow_error) }
        }
    }
    var i = 0usize
    while i < count {
        if entries[i].path.len == 0usize { ret (0usize, InvalidManifest) }
        i += 1usize
    }
    ret (count, ok)
}

// A `path:` value must stay inside the project root: not empty, not absolute, no
// drive or alternate-data-stream colon, and no `..` component (split on either
// separator) that would escape the root when joined by asset_join.
fn asset_path_safe(path: str) -> bool {
    if path.len == 0usize { ret false }
    if path[0usize] == 47u8 || path[0usize] == 92u8 { ret false }
    var i = 0usize
    while i < path.len {
        if path[i] == 58u8 { ret false }
        if path[i] == 46u8 && i + 1usize < path.len && path[i + 1usize] == 46u8 {
            var component_start = i == 0usize || path[i - 1usize] == 47u8 || path[i - 1usize] == 92u8
            var component_end = i + 2usize
            var at_end = component_end == path.len || path[component_end] == 47u8 || path[component_end] == 92u8
            if component_start && at_end { ret false }
        }
        i += 1usize
    }
    ret true
}

fn asset_join(a: *mem.Arena, root: str, leaf: str) -> (str, err) {
    let (path, path_error) = mem.alloc[u8](a, root.len + 1usize + leaf.len)
    if path_error != ok { ret ("", path_error) }
    var n = 0usize
    var i = 0usize
    while i < root.len {
        path[n] = root[i]
        n += 1usize
        i += 1usize
    }
    if root.len > 0usize {
        path[n] = 47u8
        n += 1usize
    }
    i = 0usize
    while i < leaf.len {
        path[n] = leaf[i]
        n += 1usize
        i += 1usize
    }
    ret (path[..n], ok)
}

fn asset_value(o: *Out, e: *const Entry, attributes_from: usize) -> err {
    try asset_put(o, "Asset { name: ")
    try asset_literal(o, e.name)
    try asset_put(o, ", media_type: ")
    try asset_literal(o, e.media_type)
    try asset_put(o, ", bytes: ")
    try asset_literal(o, e.bytes)
    try asset_put(o, ", sha256: [32]u8{ ")
    var i = 0usize
    while i < 32usize {
        if i > 0usize { try asset_put(o, ", ") }
        var h = usize(e.hex[2usize * i]) - 48usize
        if h > 9usize { h = h - 39usize }
        var l = usize(e.hex[2usize * i + 1usize]) - 48usize
        if l > 9usize { l = l - 39usize }
        try asset_decimal(o, h * 16usize + l)
        i += 1usize
    }
    try asset_put(o, " }, attributes: attribute_table[")
    try asset_decimal(o, attributes_from)
    try asset_put(o, "usize..")
    try asset_decimal(o, attributes_from + e.attribute_count)
    try asset_put(o, "usize] }")
    ret ok
}

// The generated module: the fence of `lib/e/asset.e` over the sorted entries.
// The text's size is bounded by four bytes per asset byte, eight per manifest byte
// (every name, type and attribute is manifest text) and a fixed cost per entry.
fn asset_generate(a: *mem.Arena, entries: []Entry, count: usize, manifest_len: usize) -> (str, err) {
    var total = manifest_len * 8usize + 4096usize
    var attributes = 0usize
    var i = 0usize
    while i < count {
        let bytes_len = entries[i].bytes.len
        total += bytes_len * 4usize
        total += 1024usize
        attributes += entries[i].attribute_count
        i += 1usize
    }
    let (data, data_error) = mem.alloc[u8](a, total)
    if data_error != ok { ret ("", data_error) }
    var o = Out { data: data, at: 0usize }
    let write_error = asset_generate_into(&o, entries, count, attributes)
    if write_error != ok { ret ("", write_error) }
    ret (o.data[..o.at], ok)
}

// The text itself; `try` is not lowered in a function answering a tuple.
fn asset_generate_into(o: *Out, entries: []Entry, count: usize, attributes: usize) -> err {
    var i = 0usize
    try asset_put(o, "// Generated by the compiler from project.yaml (D777): the asset registry, sorted by name.\n\n")
    try asset_put(o, "type Attribute = struct { name: str, value: str }\n")
    try asset_put(o, "type Asset = struct { name: str, media_type: str, bytes: []const u8, sha256: [32]u8, attributes: []const Attribute }\n\n")
    var table_size = attributes
    if table_size == 0usize { table_size = 1usize }
    try asset_put(o, "var attribute_table: [")
    try asset_decimal(o, table_size)
    try asset_put(o, "]Attribute = zero\nvar attributes_filled: bool = zero\n\n")
    try asset_put(o, "fn asset_same(a: str, b: str) -> bool {\n    if a.len != b.len { ret false }\n    var i = 0usize\n    while i < a.len {\n        if a[i] != b[i] { ret false }\n        i += 1usize\n    }\n    ret true\n}\n\n")
    // The attributes: every entry's pairs written into the table once, in order; a
    // second writer stores the same values, so a race changes nothing.
    try asset_put(o, "fn fill() {\n    if attributes_filled { ret }\n")
    var slot = 0usize
    i = 0usize
    while i < count {
        // Through a pointer: the bootstrap misaddresses an array field of an
        // indexed slice element.
        let e = &entries[i]
        var k = 0usize
        while k < e.attribute_count {
            try asset_put(o, "    attribute_table[")
            try asset_decimal(o, slot)
            try asset_put(o, "usize] = Attribute { name: ")
            try asset_literal(o, e.attribute_names[k])
            try asset_put(o, ", value: ")
            try asset_literal(o, e.attribute_values[k])
            try asset_put(o, " }\n")
            slot += 1usize
            k += 1usize
        }
        i += 1usize
    }
    try asset_put(o, "    attributes_filled = true\n}\n\n")
    try asset_put(o, "fn count() -> usize {\n    ret ")
    try asset_decimal(o, count)
    try asset_put(o, "usize\n}\n\n")
    try asset_put(o, "fn at(index: usize) -> (Asset, bool) {\n    fill()\n")
    slot = 0usize
    i = 0usize
    while i < count {
        try asset_put(o, "    if index == ")
        try asset_decimal(o, i)
        try asset_put(o, "usize { ret (")
        let e = &entries[i]
        try asset_value(o, e, slot)
        try asset_put(o, ", true) }\n")
        slot += e.attribute_count
        i += 1usize
    }
    try asset_put(o, "    ret (zero, false)\n}\n\n")
    try asset_put(o, "fn get(name: str) -> (Asset, bool) {\n    var i = 0usize\n    while i < count() {\n        let (value, found) = at(i)\n        if found && asset_same(value.name, name) { ret (value, true) }\n        i += 1usize\n    }\n    ret (zero, false)\n}\n\n")
    try asset_put(o, "fn attribute(value: Asset, name: str) -> (str, bool) {\n    var i = 0usize\n    while i < value.attributes.len {\n        if asset_same(value.attributes[i].name, name) { ret (value.attributes[i].value, true) }\n        i += 1usize\n    }\n    ret (\"\", false)\n}\n")
    ret ok
}

// The overlay for `lib/e/asset.e` when the project at `root` declares assets: the
// generated text, or nothing when there is no manifest or no `assets:` key.
// The project's declared assets, sorted by name, each file read and hashed; zero
// entries when the project has no manifest or declares none. The build manifest
// lists them from here too (D792), so one reading serves both.
fn asset_collect(a: *mem.Arena, root: str, entries: []Entry, manifest_len: *usize) -> (usize, err) {
    *manifest_len = 0usize
    if root.len == 0usize { ret (0usize, ok) }
    let (manifest_path, manifest_path_error) = asset_join(a, root, "project.yaml")
    if manifest_path_error != ok { ret (0usize, manifest_path_error) }
    let (manifest, manifest_error) = source.load(a, manifest_path)
    if manifest_error != ok { ret (0usize, ok) }
    *manifest_len = manifest.len
    let (count, parse_error) = parse_manifest(a, manifest, entries)
    if parse_error != ok { ret (0usize, parse_error) }
    if count == 0usize { ret (0usize, ok) }
    let load_error = asset_load(a, root, entries, count)
    if load_error != ok { ret (0usize, load_error) }
    ret (count, ok)
}

fn asset_overlay(a: *mem.Arena, root: str, overlay_paths: []str, overlay_texts: []str, overlay_count: *usize) -> err {
    let checkpoint = mem.mark(a)
    let (entries, entries_error) = mem.alloc[Entry](a, MAX_ASSETS)
    if entries_error != ok { ret entries_error }
    var manifest_len = 0usize
    let (count, collect_error) = asset_collect(a, root, entries, &manifest_len)
    if collect_error != ok { ret collect_error }
    if count == 0usize {
        mem.reset(a, checkpoint)
        ret ok
    }
    let (text, generate_error) = asset_generate(a, entries, count, manifest_len)
    if generate_error != ok { ret generate_error }
    if *overlay_count >= overlay_paths.len { ret AssetTooLarge }
    overlay_paths[*overlay_count] = "lib/e/asset.e"
    overlay_texts[*overlay_count] = text
    *overlay_count += 1usize
    ret ok
}

fn asset_load(a: *mem.Arena, root: str, entries: []Entry, count: usize) -> err {
    // Sorted by logical name; then every file read and hashed.
    var i = 1usize
    while i < count {
        let v = entries[i]
        var j = i
        while j > 0usize && asset_before(v.name, entries[j - 1usize].name) {
            entries[j] = entries[j - 1usize]
            j = j - 1usize
        }
        entries[j] = v
        i += 1usize
    }
    var total = 0usize
    i = 0usize
    while i < count {
        let (path, path_error) = asset_join(a, root, entries[i].path)
        if path_error != ok { ret path_error }
        let (bytes, load_error) = source.load(a, path)
        if load_error != ok { ret AssetMissing }
        total += bytes.len
        // Bound to a local: the bootstrap reads `> MAX_TOTAL {` as an aggregate literal.
        let limit = MAX_TOTAL
        if total > limit { ret AssetTooLarge }
        entries[i].bytes = bytes
        var hex: [64]u8 = zero
        artifact_hash.sha256_hex_into(bytes, hex[0usize..64usize])
        entries[i].hex = hex
        i += 1usize
    }
    ret ok
}
