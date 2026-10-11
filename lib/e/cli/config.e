// Layered configuration in the manner of viper: a key's value is the one from the highest
// layer that sets it, in the order flags > environment > file > defaults, and the layer a
// value came from is known. Keys are dotted (`server.port`); an INI section and key join
// with a dot, a JSON object nests into dotted keys and an array's elements are numbered
// (`list.0`). Values are text and typed on the way out (`get_i64`, `get_u64`, `get_f64`,
// `get_bool`: true/false, 1/0, yes/no, on/off in any case).
//
// Layers are filled by the caller in whatever order it likes (`layer_defaults`,
// `layer_ini` or `layer_json`, `layer_env` over a list of `NAME=value` entries or
// `layer_process_env` over the process environment, `layer_flags` over an `e.cli` result);
// an environment variable is `PREFIX` + the key upper-cased with `.` and `-` as `_`,
// and only keys already known to the configuration are looked up, so defaults (or a
// file) declare what the environment may override.
//
// `reload` re-reads the file layer from a path and answers how many keys' effective
// values changed; `watch_poll` waits for the host's directory events on the file's
// folder, coalesces however many arrive for the file into one reload, and answers the
// event and change counts. Storage is the arena the configuration was made with: every
// reload allocates the file's text and flattened keys there again, so a long-lived
// watcher should be given an arena of its own and a restart when it nears full.

use e.cli
use e.fmt.ini
use e.fmt.json
use e.fs
use e.fs.watch as watch
use e.mem
use e.os
use e.str

type Layer = enum u8 { Default, File, Env, Flag }
type Format = enum u8 { Ini, Json }
type Entry = struct { key: str, value: str, layer: Layer }
type Config = struct { entries: []Entry, count: usize }
error Full
error Missing
error Invalid

fn config(a: *mem.Arena, capacity: usize) -> (Config, err) {
    let (entries, e) = mem.alloc[Entry](a, capacity)
    if e != ok { ret (zero, e) }
    var c: Config = zero
    c.entries = entries
    ret (c, ok)
}

fn layer_rank(l: Layer) -> u8 {
    if l == .Default { ret 0u8 }
    if l == .File { ret 1u8 }
    if l == .Env { ret 2u8 }
    ret 3u8
}

// Set `key` in `layer` (a second set of the same key and layer replaces the first).
fn set(c: *Config, layer: Layer, key: str, value: str) -> err {
    var i = 0usize
    while i < c.count {
        if c.entries[i].layer == layer && str.eq(c.entries[i].key, key) {
            c.entries[i].value = value
            ret ok
        }
        i += 1usize
    }
    if c.count >= c.entries.len { ret Full }
    c.entries[c.count] = Entry { key: key, value: value, layer: layer }
    c.count += 1usize
    ret ok
}

// Remove every entry of `layer`, keeping the others in order.
fn clear_layer(c: *Config, layer: Layer) {
    var out = 0usize
    var i = 0usize
    while i < c.count {
        if c.entries[i].layer != layer {
            c.entries[out] = c.entries[i]
            out += 1usize
        }
        i += 1usize
    }
    c.count = out
}

// The winning entry for `key`: highest layer; `false` when no layer sets it.
fn lookup(c: *const Config, key: str) -> (Entry, bool) {
    var best: Entry = zero
    var found = false
    var i = 0usize
    while i < c.count {
        if str.eq(c.entries[i].key, key) {
            if !found || layer_rank(c.entries[i].layer) > layer_rank(best.layer) {
                best = c.entries[i]
                found = true
            }
        }
        i += 1usize
    }
    ret (best, found)
}

fn get_str(c: *const Config, key: str) -> (str, bool) {
    let (entry, found) = lookup(c, key)
    ret (entry.value, found)
}

fn layer_of(c: *const Config, key: str) -> (Layer, bool) {
    let (entry, found) = lookup(c, key)
    ret (entry.layer, found)
}

fn get_i64(c: *const Config, key: str) -> (i64, err) {
    let (entry, found) = lookup(c, key)
    if !found { ret (0i64, Missing) }
    let (v, e) = str.parse_i64(entry.value)
    if e != ok { ret (0i64, Invalid) }
    ret (v, ok)
}

fn get_u64(c: *const Config, key: str) -> (u64, err) {
    let (entry, found) = lookup(c, key)
    if !found { ret (0u64, Missing) }
    let (v, e) = str.parse_u64(entry.value)
    if e != ok { ret (0u64, Invalid) }
    ret (v, ok)
}

fn get_f64(c: *const Config, key: str) -> (f64, err) {
    let (entry, found) = lookup(c, key)
    if !found { ret (0.0f64, Missing) }
    let (v, e) = str.parse_f64(entry.value)
    if e != ok { ret (0.0f64, Invalid) }
    ret (v, ok)
}

fn get_bool(c: *const Config, key: str) -> (bool, err) {
    let (entry, found) = lookup(c, key)
    if !found { ret (false, Missing) }
    let v = entry.value
    if str.compare_ascii_fold(v, "true") == 0i32 || str.compare_ascii_fold(v, "yes") == 0i32 || str.compare_ascii_fold(v, "on") == 0i32 || str.eq(v, "1") { ret (true, ok) }
    if str.compare_ascii_fold(v, "false") == 0i32 || str.compare_ascii_fold(v, "no") == 0i32 || str.compare_ascii_fold(v, "off") == 0i32 || str.eq(v, "0") { ret (false, ok) }
    ret (false, Invalid)
}

// `key=value` strings into the defaults layer (the first `=` splits; no `=` is `Invalid`).
fn layer_defaults(c: *Config, pairs: []const str) -> err {
    var i = 0usize
    while i < pairs.len {
        let (key, value, found) = str.split_once(pairs[i], "=")
        if !found || key.len == 0usize { ret Invalid }
        try set(c, .Default, key, value)
        i += 1usize
    }
    ret ok
}

// A joined key `prefix.name` (or `name` when the prefix is empty).
fn join_key(a: *mem.Arena, prefix: str, name: str) -> (str, err) {
    if prefix.len == 0usize { ret (name, ok) }
    let (b0, be) = str.builder(a, prefix.len + name.len + 1usize)
    if be != ok { ret ("", be) }
    var b = b0
    if str.push(&b, prefix) != ok || str.push(&b, ".") != ok || str.push(&b, name) != ok { ret ("", Full) }
    ret (str.done(&b), ok)
}

fn flatten_json(a: *mem.Arena, c: *Config, prefix: str, v: json.Value) -> err {
    switch v {
    case .Object as members:
        var i = 0usize
        while i < members.len {
            let (key, ke) = join_key(a, prefix, members[i].key)
            if ke != ok { ret ke }
            try flatten_json(a, c, key, members[i].value)
            i += 1usize
        }
    case .Array as items:
        var j = 0usize
        while j < items.len {
            let (nb, ne) = str.builder(a, 24usize)
            if ne != ok { ret ne }
            var numbered = nb
            if str.push_usize(&numbered, j) != ok { ret Full }
            let (key, ke) = join_key(a, prefix, str.done(&numbered))
            if ke != ok { ret ke }
            try flatten_json(a, c, key, items[j])
            j += 1usize
        }
    case .Null:
        ret ok
    case .Bool as flag:
        if flag { ret set(c, .File, prefix, "true") }
        ret set(c, .File, prefix, "false")
    case .Number as n:
        ret set(c, .File, prefix, n.lexeme)
    case .String as s:
        ret set(c, .File, prefix, s)
    }
    ret ok
}

// Replace the file layer with the flattened keys of a JSON document.
fn layer_json(a: *mem.Arena, c: *Config, source: str) -> err {
    let (v, pe) = json.parse(a, source, json.Options { allow_duplicate_keys: false, max_depth: 32u16 })
    if pe != ok { ret Invalid }
    clear_layer(c, .File)
    ret flatten_json(a, c, "", v)
}

// Replace the file layer with an INI document's `section.key` entries (`key` outside a section).
fn layer_ini(a: *mem.Arena, c: *Config, source: str) -> err {
    let (doc, pe) = ini.parse(a, source, ini.Options { case_sensitive: true, allow_duplicate_keys: true })
    if pe != ok { ret Invalid }
    clear_layer(c, .File)
    var i = 0usize
    while i < doc.entries.len {
        let entry = doc.entries[i]
        let (key, ke) = join_key(a, entry.section, entry.key)
        if ke != ok { ret ke }
        try set(c, .File, key, entry.value)
        i += 1usize
    }
    ret ok
}

// `PREFIX` + upper-cased key with `.` and `-` as `_`.
fn env_name(a: *mem.Arena, prefix: str, key: str) -> (str, err) {
    let (b0, be) = str.builder(a, prefix.len + key.len)
    if be != ok { ret ("", be) }
    var b = b0
    if str.push(&b, prefix) != ok { ret ("", Full) }
    var i = 0usize
    while i < key.len {
        var ch = key[i]
        if ch >= 97u8 && ch <= 122u8 { ch = ch - 32u8 }
        if ch == 46u8 || ch == 45u8 { ch = 95u8 }
        if str.push_byte(&b, ch) != ok { ret ("", Full) }
        i += 1usize
    }
    ret (str.done(&b), ok)
}

// The environment layer from `NAME=value` entries, for the keys already known.
fn layer_env(a: *mem.Arena, c: *Config, prefix: str, entries: []const str) -> err {
    clear_layer(c, .Env)
    let known = c.count
    var i = 0usize
    while i < known {
        let key = c.entries[i].key
        let (name, ne) = env_name(a, prefix, key)
        if ne != ok { ret ne }
        var j = 0usize
        while j < entries.len {
            let (n, v, found) = str.split_once(entries[j], "=")
            if found && str.eq(n, name) {
                try set(c, .Env, key, v)
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// The environment layer from the process environment, for the keys already known.
fn layer_process_env(a: *mem.Arena, c: *Config, prefix: str) -> err {
    clear_layer(c, .Env)
    let known = c.count
    var i = 0usize
    while i < known {
        let key = c.entries[i].key
        let (name, ne) = env_name(a, prefix, key)
        if ne != ok { ret ne }
        let (v, e) = os.env(a, name)
        if e == ok { try set(c, .Env, key, v) }
        i += 1usize
    }
    ret ok
}

fn value_text(a: *mem.Arena, v: cli.Value) -> (str, err) {
    switch v {
    case .Bool as flag:
        if flag { ret ("true", ok) }
        ret ("false", ok)
    case .String as s:
        ret (s, ok)
    case .I64 as n:
        let (b0, be) = str.builder(a, 24usize)
        if be != ok { ret ("", be) }
        var b = b0
        if str.push_i64(&b, n) != ok { ret ("", Full) }
        ret (str.done(&b), ok)
    case .U64 as n:
        let (b0, be) = str.builder(a, 24usize)
        if be != ok { ret ("", be) }
        var b = b0
        if str.push_u64(&b, n) != ok { ret ("", Full) }
        ret (str.done(&b), ok)
    case .F64 as n:
        let (b0, be) = str.builder(a, 40usize)
        if be != ok { ret ("", be) }
        var b = b0
        if str.push_f64(&b, n) != ok { ret ("", Full) }
        ret (str.done(&b), ok)
    }
    ret ("", Invalid)
}

// The flag layer from a parsed command line: each option present (last value of a repeat)
// under its long name.
fn layer_flags(a: *mem.Arena, c: *Config, r: *const cli.Result) -> err {
    clear_layer(c, .Flag)
    var i = 0usize
    while i < r.options.len {
        let o = r.options[i]
        if o.values.len > 0usize {
            let (text, te) = value_text(a, o.values[o.values.len - 1usize])
            if te != ok { ret te }
            try set(c, .Flag, o.name, text)
        }
        i += 1usize
    }
    ret ok
}

fn read_text(a: *mem.Arena, path: str) -> (str, err) {
    let (bytes, e) = fs.read_file(a, path, 16777216usize)
    if e != ok { ret ("", e) }
    ret (bytes, ok)
}

// Keys of the file layer and their effective values, for change counting.
fn effective_changes(c: *const Config, keys: []const str, before: []const str, had: []const bool) -> usize {
    var changed = 0usize
    var i = 0usize
    while i < keys.len {
        let (now, present) = get_str(c, keys[i])
        if present != had[i] || (present && !str.eq(now, before[i])) { changed += 1usize }
        i += 1usize
    }
    ret changed
}

// Re-read the file layer from `path`; answers how many keys' effective values changed
// (keys that appeared, vanished or changed under what the higher layers allow).
fn reload(a: *mem.Arena, c: *Config, path: str, format: Format) -> (usize, err) {
    let (text, re) = read_text(a, path)
    if re != ok { ret (0usize, re) }
    // Remember the effective value of every key the old file layer set.
    var old_file = 0usize
    var i = 0usize
    while i < c.count {
        if c.entries[i].layer == .File { old_file += 1usize }
        i += 1usize
    }
    let (keys, ke) = mem.alloc[str](a, old_file + c.entries.len)
    if ke != ok { ret (0usize, ke) }
    let (before, be) = mem.alloc[str](a, old_file + c.entries.len)
    if be != ok { ret (0usize, be) }
    let (had, he) = mem.alloc[bool](a, old_file + c.entries.len)
    if he != ok { ret (0usize, he) }
    var n = 0usize
    i = 0usize
    while i < c.count {
        if c.entries[i].layer == .File {
            keys[n] = c.entries[i].key
            let (v, present) = get_str(c, keys[n])
            before[n] = v
            had[n] = present
            n += 1usize
        }
        i += 1usize
    }
    var pe = ok
    if format == .Json { pe = layer_json(a, c, text) } else { pe = layer_ini(a, c, text) }
    if pe != ok { ret (0usize, pe) }
    // Keys new in the file: effective before was whatever the other layers gave.
    var changed = 0usize
    var new_keys = 0usize
    i = 0usize
    while i < c.count {
        if c.entries[i].layer == .File {
            var known = false
            var k = 0usize
            while k < n {
                if str.eq(keys[k], c.entries[i].key) { known = true }
                k += 1usize
            }
            if !known && n + new_keys < keys.len {
                // The value the key had without its file entry: the highest other layer.
                keys[n + new_keys] = c.entries[i].key
                var other: Entry = zero
                var other_found = false
                var m = 0usize
                while m < c.count {
                    if c.entries[m].layer != .File && str.eq(c.entries[m].key, c.entries[i].key) {
                        if !other_found || layer_rank(c.entries[m].layer) > layer_rank(other.layer) {
                            other = c.entries[m]
                            other_found = true
                        }
                    }
                    m += 1usize
                }
                before[n + new_keys] = other.value
                had[n + new_keys] = other_found
                new_keys += 1usize
            }
        }
        i += 1usize
    }
    changed = effective_changes(c, keys[0..n + new_keys], before[0..n + new_keys], had[0..n + new_keys])
    ret (changed, ok)
}

// The folder and file name of path (the folder is . for a bare name); both borrow it.
fn split_path(path: str) -> (str, str) {
    var cut = path.len
    var i = path.len
    while i > 0usize {
        i -= 1usize
        if path[i] == 47u8 || path[i] == 92u8 {
            cut = i
            break
        }
    }
    if cut == path.len { ret (".", path) }
    if cut == 0usize { ret (path[0..1], path[1..]) }
    ret (path[0..cut], path[cut + 1usize..])
}

// Whether an event path names `base`, bare or under the watched folder (hosts differ on which).
fn names_file(event_path: str, base: str) -> bool {
    if str.eq(event_path, base) { ret true }
    if event_path.len <= base.len || !str.ends_with(event_path, base) { ret false }
    let before = event_path[event_path.len - base.len - 1usize]
    ret before == 47u8 || before == 92u8
}

// Wait for events on `dir` (the watched folder of `path`), coalesce every one that names
// the file into a single reload, and answer (matching events, keys changed).
fn watch_poll(a: *mem.Arena, w: watch.Watch, c: *Config, dir: str, base: str, path: str, format: Format) -> (usize, usize, err) {
    var events: [64]watch.Event = zero
    let (count, re) = watch.read(a, w, events[0..])
    if re != ok { ret (0usize, 0usize, re) }
    var matched = 0usize
    var overflow = false
    var i = 0usize
    while i < count {
        let ev = events[i]
        if ev.action == .Overflow { overflow = true }
        if names_file(ev.path, base) || names_file(ev.old_path, base) { matched += 1usize }
        i += 1usize
    }
    if matched == 0usize && !overflow { ret (0usize, 0usize, ok) }
    let (changed, ce) = reload(a, c, path, format)
    if ce != ok { ret (matched, 0usize, ce) }
    ret (matched, changed, ok)
}
