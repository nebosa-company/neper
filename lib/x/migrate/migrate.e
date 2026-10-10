// Configuration-management importers (T031), after petcow's `src/migrate.rs` `migrate_ansible`, `migrate_salt`,
// `migrate_puppet` and `migrate_chef`: an Ansible playbook, a Salt `.sls` state file, a Puppet manifest or a Chef
// recipe becomes one document of `os.*` resources -- `{project, config: [{name, [target: {group}], resources: {id:
// {type, ...}}}]}` -- with a warning for everything that has no faithful equivalent. Nothing is dropped silently
// except what the reference drops silently: an Ansible module whose arguments are not a mapping (the free-form
// `apt: nginx` shape) maps to nothing and says nothing, and `migrated` counts only what was translated.
//
// Memory: the arena is retained; the document, every string in it and the warnings live in it, and the result is
// valid for the arena's life. The source is parsed with `e.fmt.yaml`, whose subset (no anchors, aliases or merge
// keys, at most 256 items in one block sequence) is narrower than serde_yaml's; what it refuses is `Unsupported` or
// `Invalid`, never a partial answer.
//
// Differences from the reference: the Puppet lexer works on bytes, so a non-ASCII byte is a word byte where the
// reference tests Unicode alphanumerics, and the Chef reader's whitespace is ASCII. The Debug rendering of a
// stray Puppet token in a warning escapes `"`, `\`, newline, tab, return, NUL and other control characters.

use e.data.list as list
use e.fmt.yaml as yaml
use e.io
use e.mem
use e.str

error Invalid
error NotPlaybook
error NotStates
error Exhausted

type Migration = struct { document: yaml.Value, migrated: usize, warnings: []const str }

type Run = struct { a: *mem.Arena, warnings: list.List[str], migrated: usize, failed: bool }

type Fields = struct { pairs: list.List[yaml.Pair], failed: bool }

// A keyed attribute collected from a Puppet or Chef resource; a later one with the same key replaces the earlier.
type Attr = struct { key: str, value: str }

// A Puppet token.
type Tok = struct { kind: u8, text: str }

const T_WORD: u8 = 0u8
const T_STR: u8 = 1u8
const T_ARROW: u8 = 2u8
const T_OPEN: u8 = 3u8
const T_CLOSE: u8 = 4u8
const T_COLON: u8 = 5u8
const T_COMMA: u8 = 6u8
const T_SEMI: u8 = 7u8

// --- plumbing -------------------------------------------------------------------------------------------------------

fn start(a: *mem.Arena) -> Run {
    let (warnings, warnings_error) = list.init[str](a, 16usize)
    var run = Run { a: a, warnings: warnings, migrated: 0usize, failed: false }
    if warnings_error != ok { run.failed = true }
    ret run
}

// An empty collection over the arena; a refused allocation leaves it empty and the first push refuses again.
fn new_fields(a: *mem.Arena) -> Fields {
    let (pairs, pairs_error) = list.init[yaml.Pair](a, 8usize)
    if pairs_error != ok {
        let empty = list.List[yaml.Pair] { items: zero, len: 0usize, arena: a }
        ret Fields { pairs: empty, failed: true }
    }
    ret Fields { pairs: pairs, failed: false }
}

fn choose(c: bool, yes: str, no: str) -> str {
    if c { ret yes }
    ret no
}

fn text_value(s: str) -> yaml.Value { ret yaml.Value{ String: s } }

fn bool_value(b: bool) -> yaml.Value { ret yaml.Value{ Bool: b } }

fn key_is(key: yaml.Value, name: str) -> bool {
    var same = false
    switch key {
    case .String as s:
        same = str.eq(s, name)
    default:
        same = false
    }
    ret same
}

// A mapping insert: an existing key keeps its place and takes the new value.
fn put(f: *Fields, name: str, v: yaml.Value) {
    var at = 0usize
    while at < f.pairs.len {
        if key_is(f.pairs.items[at].key, name) {
            f.pairs.items[at].value = v
            ret
        }
        at += 1usize
    }
    let pushed = list.push[yaml.Pair](&f.pairs, yaml.Pair { key: text_value(name), value: v })
    if pushed != ok { f.failed = true }
}

fn put_s(f: *Fields, name: str, v: str) { put(f, name, text_value(v)) }

fn put_b(f: *Fields, name: str, v: bool) { put(f, name, bool_value(v)) }

// The collection as a mapping value, or Null when a push into it was refused (the run reads that as exhausted).
fn finish(f: *Fields) -> yaml.Value {
    if f.failed { ret .Null }
    ret yaml.Value{ Mapping: list.slice_const[yaml.Pair](&f.pairs) }
}

fn is_null(v: yaml.Value) -> bool {
    var null = false
    switch v {
    case .Null:
        null = true
    default:
        null = false
    }
    ret null
}

fn has_id(f: *const Fields, name: str) -> bool {
    var at = 0usize
    while at < f.pairs.len {
        if key_is(f.pairs.items[at].key, name) { ret true }
        at += 1usize
    }
    ret false
}

// A Null where a collection was expected is a refused allocation.
fn check(run: *Run, v: yaml.Value) {
    if is_null(v) { run.failed = true }
}

fn warn(run: *Run, text: str) {
    let pushed = list.push[str](&run.warnings, text)
    if pushed != ok { run.failed = true }
}

// The concatenation of up to five parts; unused parts are "".
fn cat(run: *Run, p0: str, p1: str, p2: str, p3: str, p4: str) -> str {
    var parts: [5]str = zero
    parts[0] = p0
    parts[1] = p1
    parts[2] = p2
    parts[3] = p3
    parts[4] = p4
    let (joined, join_error) = str.join(run.a, parts[0..5], "")
    if join_error != ok {
        run.failed = true
        ret ""
    }
    ret joined
}

fn cat2(run: *Run, p0: str, p1: str) -> str { ret cat(run, p0, p1, "", "", "") }

fn cat3(run: *Run, p0: str, p1: str, p2: str) -> str { ret cat(run, p0, p1, p2, "", "") }

fn decimal(run: *Run, n: usize, width: usize) -> str {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = n
    if rest == 0usize {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        count += 1usize
        rest = rest / 10usize
    }
    let (b, builder_error) = str.builder(run.a, 24usize)
    if builder_error != ok {
        run.failed = true
        ret ""
    }
    var out = b
    var pad = count
    while pad < width {
        let padded = str.push_byte(&out, 48u8)
        if padded != ok { run.failed = true }
        pad += 1usize
    }
    var at = count
    while at > 0usize {
        at -= 1usize
        let pushed = str.push_byte(&out, digits[at])
        if pushed != ok { run.failed = true }
    }
    ret str.done(&out)
}

// --- yaml value access ----------------------------------------------------------------------------------------------

fn pairs_of(v: yaml.Value) -> ([]const yaml.Pair, bool) {
    var found = false
    var pairs: []const yaml.Pair = zero
    switch v {
    case .Mapping as m:
        pairs = m
        found = true
    default:
        found = false
    }
    ret (pairs, found)
}

fn items_of(v: yaml.Value) -> ([]const yaml.Value, bool) {
    var found = false
    var items: []const yaml.Value = zero
    switch v {
    case .Sequence as s:
        items = s
        found = true
    default:
        found = false
    }
    ret (items, found)
}

fn string_of(v: yaml.Value) -> (str, bool) {
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

fn bool_of(v: yaml.Value) -> (bool, bool) {
    var found = false
    var flag = false
    switch v {
    case .Bool as b:
        flag = b
        found = true
    default:
        found = false
    }
    ret (flag, found)
}

fn get(m: []const yaml.Pair, name: str) -> (yaml.Value, bool) {
    var at = 0usize
    while at < m.len {
        if key_is(m[at].key, name) { ret (m[at].value, true) }
        at += 1usize
    }
    ret (.Null, false)
}

fn has_key(m: []const yaml.Pair, name: str) -> bool {
    let (v, found) = get(m, name)
    ret found
}

// `sval`: the string at a key; a value of any other kind is absent.
fn sval(m: []const yaml.Pair, name: str) -> (str, bool) {
    let (v, found) = get(m, name)
    if !found { ret ("", false) }
    let (text, is_text) = string_of(v)
    ret (text, is_text)
}

fn sval_or(m: []const yaml.Pair, name: str, fallback: str) -> str {
    let (s, found) = sval(m, name)
    if found { ret s }
    ret fallback
}

fn bval(m: []const yaml.Pair, name: str) -> (bool, bool) {
    let (v, found) = get(m, name)
    if !found { ret (false, false) }
    let (flag, is_bool) = bool_of(v)
    ret (flag, is_bool)
}

fn is_present_state(m: []const yaml.Pair) -> str {
    let (s, found) = sval(m, "state")
    if found && (str.eq(s, "absent") || str.eq(s, "removed")) { ret "absent" }
    ret "present"
}

fn mapping_or_empty(v: yaml.Value) -> []const yaml.Pair {
    let (pairs, found) = pairs_of(v)
    if found { ret pairs }
    var none: []const yaml.Pair = zero
    ret none
}

fn parse_options() -> yaml.Options { ret yaml.Options { max_depth: 64u16, allow_duplicate_keys: false } }

fn result(run: *Run, document: yaml.Value) -> (Migration, err) {
    if run.failed { ret (zero, Exhausted) }
    ret (Migration { document: document, migrated: run.migrated, warnings: list.slice_const[str](&run.warnings) }, ok)
}

// `{project, config: [play...]}`.
fn wrap(run: *Run, project: str, plays: []const yaml.Value) -> yaml.Value {
    var out = new_fields(run.a)
    put_s(&out, "project", project)
    put(&out, "config", yaml.Value{ Sequence: plays })
    let document = finish(&out)
    check(run, document)
    ret document
}

fn single_play(run: *Run, project: str, name: str, resources: *Fields) -> yaml.Value {
    var play = new_fields(run.a)
    put_s(&play, "name", name)
    let resources_value = finish(resources)
    check(run, resources_value)
    put(&play, "resources", resources_value)
    let (plays, plays_error) = mem.alloc[yaml.Value](run.a, 1usize)
    if plays_error != ok {
        run.failed = true
        ret .Null
    }
    let play_value = finish(&play)
    check(run, play_value)
    plays[0] = play_value
    ret wrap(run, project, plays)
}

// `a b c d e` of five cron fields; a missing one is "*".
fn schedule5(run: *Run, m: []const yaml.Pair, k0: str, k1: str, k2: str, k3: str, k4: str) -> str {
    var parts: [9]str = zero
    parts[0] = sval_or(m, k0, "*")
    parts[1] = " "
    parts[2] = sval_or(m, k1, "*")
    parts[3] = " "
    parts[4] = sval_or(m, k2, "*")
    parts[5] = " "
    parts[6] = sval_or(m, k3, "*")
    parts[7] = " "
    parts[8] = sval_or(m, k4, "*")
    let (joined, join_error) = str.join(run.a, parts[0..9], "")
    if join_error != ok {
        run.failed = true
        ret ""
    }
    ret joined
}

fn attrs_get(attrs: []const Attr, name: str) -> (str, bool) {
    var at = 0usize
    while at < attrs.len {
        if str.eq(attrs[at].key, name) { ret (attrs[at].value, true) }
        at += 1usize
    }
    ret ("", false)
}

fn attrs_or(attrs: []const Attr, name: str, fallback: str) -> str {
    let (v, found) = attrs_get(attrs, name)
    if found { ret v }
    ret fallback
}

fn attrs_set(run: *Run, l: *list.List[Attr], name: str, v: str) {
    var at = 0usize
    while at < l.len {
        if str.eq(l.items[at].key, name) {
            l.items[at].value = v
            ret
        }
        at += 1usize
    }
    let pushed = list.push[Attr](l, Attr { key: name, value: v })
    if pushed != ok { run.failed = true }
}

fn is_sanitize_alnum(b: u8) -> bool {
    ret (b >= 48u8 && b <= 57u8) || (b >= 97u8 && b <= 122u8)
}

// petcow's `naming::sanitize`: lowercase, runs of anything but `[a-z0-9]` become one `-`, edge dashes trimmed.
fn sanitize(run: *Run, token: str) -> str {
    let (b, builder_error) = str.builder(run.a, token.len + 1usize)
    if builder_error != ok {
        run.failed = true
        ret ""
    }
    var out = b
    var last_dash = false
    var at = 0usize
    while at < token.len {
        var c = token[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if is_sanitize_alnum(c) {
            let pushed = str.push_byte(&out, c)
            if pushed != ok { run.failed = true }
            last_dash = false
        } else if !last_dash {
            let pushed = str.push_byte(&out, 45u8)
            if pushed != ok { run.failed = true }
            last_dash = true
        }
        at += 1usize
    }
    let text = str.done(&out)
    var start_at = 0usize
    var end_at = text.len
    while start_at < end_at && text[start_at] == 45u8 { start_at += 1usize }
    while end_at > start_at && text[end_at - 1usize] == 45u8 { end_at -= 1usize }
    ret text[start_at..end_at]
}

// The segment after the last dot (`ansible.builtin.apt` -> `apt`).
fn last_segment(s: str) -> str {
    var start_at = 0usize
    var at = 0usize
    while at < s.len {
        if s[at] == 46u8 { start_at = at + 1usize }
        at += 1usize
    }
    ret s[start_at..s.len]
}

// --- ansible --------------------------------------------------------------------------------------------------------

fn is_control_key(k: str) -> bool {
    ret str.eq(k, "name") || str.eq(k, "become") || str.eq(k, "become_user") || str.eq(k, "when") || str.eq(k, "vars") || str.eq(k, "tags") || str.eq(k, "notify") || str.eq(k, "register") || str.eq(k, "loop") || str.eq(k, "with_items") || str.eq(k, "ignore_errors") || str.eq(k, "changed_when") || str.eq(k, "failed_when") || str.eq(k, "block")
}

fn group_name_ok(h: str) -> bool {
    var at = 0usize
    while at < h.len {
        let c = h[at]
        let alnum = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
        if !(alnum || c == 95u8 || c == 45u8) { ret false }
        at += 1usize
    }
    ret true
}

// One Ansible task as a resource; absent (with a warning, or silently where the reference is) when it has none.
fn ansible_task(run: *Run, tm: []const yaml.Pair, tname: str) -> (yaml.Value, bool) {
    var module = ""
    var args: yaml.Value = .Null
    var have_module = false
    var at = 0usize
    while at < tm.len && !have_module {
        let (k, is_text) = string_of(tm[at].key)
        if is_text && !is_control_key(k) {
            module = k
            args = tm[at].value
            have_module = true
        }
        at += 1usize
    }
    if !have_module {
        warn(run, cat3(run, "task '", tname, "': no module found, skipped"))
        ret (.Null, false)
    }
    let short = last_segment(module)
    let (m, have_map) = pairs_of(args)
    if str.eq(short, "apt") || str.eq(short, "yum") || str.eq(short, "dnf") || str.eq(short, "package") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.package")
        put_s(&r, "name", name)
        put_s(&r, "state", is_present_state(m))
        ret (finish(&r), true)
    }
    if str.eq(short, "service") || str.eq(short, "systemd") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        let (state, have_state) = sval(m, "state")
        let started = !(have_state && str.eq(state, "stopped"))
        var r = new_fields(run.a)
        put_s(&r, "type", "os.service")
        put_s(&r, "name", name)
        put_s(&r, "state", choose(started, "started", "stopped"))
        let (enabled, have_enabled) = bval(m, "enabled")
        if have_enabled { put_b(&r, "enabled", enabled) }
        ret (finish(&r), true)
    }
    if str.eq(short, "copy") {
        if !have_map { ret (.Null, false) }
        let (dest, found) = sval(m, "dest")
        if !found { ret (.Null, false) }
        let (content, have_content) = sval(m, "content")
        if !have_content {
            warn(run, cat3(run, "task '", tname, "': copy from a source file isn't supported (only inline `content`), skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.file")
        put_s(&r, "path", dest)
        put_s(&r, "content", content)
        let (mode, have_mode) = sval(m, "mode")
        if have_mode { put_s(&r, "mode", mode) }
        ret (finish(&r), true)
    }
    if str.eq(short, "command") || str.eq(short, "shell") {
        var command = ""
        var have_command = false
        let (text, is_text) = string_of(args)
        if is_text {
            command = text
            have_command = true
        } else if have_map {
            let (cmd, have_cmd) = sval(m, "cmd")
            command = cmd
            have_command = have_cmd
        }
        if !have_command { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.command")
        put_s(&r, "command", command)
        ret (finish(&r), true)
    }
    if str.eq(short, "user") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.user")
        put_s(&r, "name", name)
        put_s(&r, "state", is_present_state(m))
        let (shell, have_shell) = sval(m, "shell")
        if have_shell { put_s(&r, "shell", shell) }
        let (home, have_home) = sval(m, "home")
        if have_home { put_s(&r, "home", home) }
        let (system, have_system) = bval(m, "system")
        if have_system { put_b(&r, "system", system) }
        ret (finish(&r), true)
    }
    if str.eq(short, "group") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.group")
        put_s(&r, "name", name)
        put_s(&r, "state", is_present_state(m))
        ret (finish(&r), true)
    }
    if str.eq(short, "cron") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.cron")
        put_s(&r, "name", name)
        put_s(&r, "state", is_present_state(m))
        put_s(&r, "schedule", schedule5(run, m, "minute", "hour", "day", "month", "weekday"))
        let (job, have_job) = sval(m, "job")
        if have_job { put_s(&r, "command", job) }
        ret (finish(&r), true)
    }
    if str.eq(short, "lineinfile") {
        if !have_map { ret (.Null, false) }
        var path = ""
        let (p, have_path) = sval(m, "path")
        if have_path {
            path = p
        } else {
            let (d, have_dest) = sval(m, "dest")
            if !have_dest { ret (.Null, false) }
            path = d
        }
        if has_key(m, "regexp") {
            warn(run, cat3(run, "task '", tname, "': lineinfile `regexp` not supported (only exact `line`), skipped"))
            ret (.Null, false)
        }
        let (line, have_line) = sval(m, "line")
        if !have_line { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.line_in_file")
        put_s(&r, "path", path)
        put_s(&r, "line", line)
        put_s(&r, "state", is_present_state(m))
        ret (finish(&r), true)
    }
    if str.eq(short, "file") {
        if !have_map { ret (.Null, false) }
        let (state, have_state) = sval(m, "state")
        if have_state && str.eq(state, "directory") {
            let (path, have_path) = sval(m, "path")
            var at_path = path
            if !have_path {
                let (d, have_dest) = sval(m, "dest")
                if !have_dest { ret (.Null, false) }
                at_path = d
            }
            var r = new_fields(run.a)
            put_s(&r, "type", "os.directory")
            put_s(&r, "path", at_path)
            let (mode, have_mode) = sval(m, "mode")
            if have_mode { put_s(&r, "mode", mode) }
            ret (finish(&r), true)
        }
        if have_state && str.eq(state, "link") {
            let (path, have_path) = sval(m, "path")
            var at_path = path
            if !have_path {
                let (d, have_dest) = sval(m, "dest")
                if !have_dest { ret (.Null, false) }
                at_path = d
            }
            let (src, have_src) = sval(m, "src")
            if !have_src { ret (.Null, false) }
            var r = new_fields(run.a)
            put_s(&r, "type", "os.symlink")
            put_s(&r, "target", src)
            put_s(&r, "path", at_path)
            ret (finish(&r), true)
        }
        warn(run, cat3(run, "task '", tname, "': file module only maps `state: directory`/`link`; skipped"))
        ret (.Null, false)
    }
    if str.eq(short, "sysctl") {
        if !have_map { ret (.Null, false) }
        let (key, have_key) = sval(m, "name")
        if !have_key { ret (.Null, false) }
        let (value, have_value) = sval(m, "value")
        if !have_value { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.sysctl")
        put_s(&r, "key", key)
        put_s(&r, "value", value)
        ret (finish(&r), true)
    }
    if str.eq(short, "hostname") || str.eq(short, "timezone") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", choose(str.eq(short, "hostname"), "os.hostname", "os.timezone"))
        put_s(&r, "name", name)
        ret (finish(&r), true)
    }
    if str.eq(short, "mount") {
        if !have_map { ret (.Null, false) }
        let (state, have_state) = sval(m, "state")
        if have_state && (str.eq(state, "absent") || str.eq(state, "unmounted")) {
            warn(run, cat(run, "task '", tname, "': mount `state: ", state, "` not supported (os.mount is mounted-only), skipped"))
            ret (.Null, false)
        }
        var path = ""
        let (p, have_path) = sval(m, "path")
        if have_path {
            path = p
        } else {
            let (n, have_name) = sval(m, "name")
            if !have_name { ret (.Null, false) }
            path = n
        }
        let (src, have_src) = sval(m, "src")
        if !have_src { ret (.Null, false) }
        let (fstype, have_fstype) = sval(m, "fstype")
        if !have_fstype { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.mount")
        put_s(&r, "src", src)
        put_s(&r, "path", path)
        put_s(&r, "fstype", fstype)
        let (opts, have_opts) = sval(m, "opts")
        if have_opts { put_s(&r, "opts", opts) }
        ret (finish(&r), true)
    }
    if str.eq(short, "authorized_key") {
        if !have_map { ret (.Null, false) }
        let (user, have_user) = sval(m, "user")
        if !have_user { ret (.Null, false) }
        let (key, have_key) = sval(m, "key")
        if !have_key { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.authorized_key")
        put_s(&r, "user", user)
        put_s(&r, "key", key)
        put_s(&r, "state", is_present_state(m))
        ret (finish(&r), true)
    }
    if str.eq(short, "git") {
        if !have_map { ret (.Null, false) }
        let (repo, have_repo) = sval(m, "repo")
        if !have_repo { ret (.Null, false) }
        let (dest, have_dest) = sval(m, "dest")
        if !have_dest { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.git")
        put_s(&r, "repo", repo)
        put_s(&r, "dest", dest)
        let (version, have_version) = sval(m, "version")
        if have_version { put_s(&r, "version", version) }
        ret (finish(&r), true)
    }
    if str.eq(short, "pip") {
        if !have_map { ret (.Null, false) }
        let (name, found) = sval(m, "name")
        if !found { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.pip")
        put_s(&r, "name", name)
        put_s(&r, "state", is_present_state(m))
        let (version, have_version) = sval(m, "version")
        if have_version { put_s(&r, "version", version) }
        ret (finish(&r), true)
    }
    warn(run, cat3(run, "task '", tname, cat3(run, "': module '", short, "' not supported, skipped")))
    ret (.Null, false)
}

// An Ansible playbook (YAML text) as one document with a play per play.
fn ansible(a: *mem.Arena, source: str, project: str) -> (Migration, err) {
    let (doc, parse_error) = yaml.parse(a, source, parse_options())
    if parse_error != ok { ret (zero, parse_error) }
    let (plays_in, is_list) = items_of(doc)
    if !is_list { ret (zero, NotPlaybook) }
    var run = start(a)
    let (plays_out, plays_error) = mem.alloc[yaml.Value](a, plays_in.len + 1usize)
    if plays_error != ok { ret (zero, Exhausted) }
    var played = 0usize
    var pi = 0usize
    while pi < plays_in.len {
        let (pm, is_map) = pairs_of(plays_in[pi])
        if !is_map {
            warn(&run, cat3(&run, "play #", decimal(&run, pi, 0usize), ": not a mapping, skipped"))
            pi += 1usize
            continue
        }
        let (given, have_name) = sval(pm, "name")
        var name = given
        if !have_name { name = cat2(&run, "play-", decimal(&run, pi, 0usize)) }
        var play = new_fields(a)
        put_s(&play, "name", name)
        let (hosts, have_hosts) = sval(pm, "hosts")
        if have_hosts && !str.eq(hosts, "all") {
            if group_name_ok(hosts) {
                var group = new_fields(a)
                put_s(&group, "group", hosts)
                put(&play, "target", finish(&group))
            } else {
                warn(&run, cat(&run, "play '", name, "': host pattern '", hosts, "' not translated; target everything"))
            }
        }
        var resources = new_fields(a)
        let (tasks_value, have_tasks) = get(pm, "tasks")
        if have_tasks {
            let (tasks, is_seq) = items_of(tasks_value)
            if is_seq {
                var ti = 0usize
                while ti < tasks.len {
                    let (tm, task_is_map) = pairs_of(tasks[ti])
                    if !task_is_map {
                        warn(&run, cat(&run, "play '", name, "' task #", decimal(&run, ti, 0usize), ": not a mapping, skipped"))
                        ti += 1usize
                        continue
                    }
                    let (given_task, have_task_name) = sval(tm, "name")
                    var tname = given_task
                    if !have_task_name { tname = cat2(&run, "task-", decimal(&run, ti, 0usize)) }
                    let (res, made) = ansible_task(&run, tm, tname)
                    if made {
                        run.migrated += 1usize
                        check(&run, res)
                        let id = cat3(&run, decimal(&run, ti, 2usize), "-", sanitize(&run, tname))
                        put(&resources, id, res)
                    }
                    ti += 1usize
                }
            }
        }
        let resources_value = finish(&resources)
        check(&run, resources_value)
        put(&play, "resources", resources_value)
        let play_value = finish(&play)
        check(&run, play_value)
        plays_out[played] = play_value
        played += 1usize
        pi += 1usize
    }
    let document = wrap(&run, project, plays_out[0..played])
    let (migration, migration_error) = result(&run, document)
    ret (migration, migration_error)
}

// --- salt -----------------------------------------------------------------------------------------------------------

fn contains_dot(s: str) -> bool {
    var at = 0usize
    while at < s.len {
        if s[at] == 46u8 { ret true }
        at += 1usize
    }
    ret false
}

fn dots_to_underscores(run: *Run, s: str) -> str {
    let (b, builder_error) = str.builder(run.a, s.len + 1usize)
    if builder_error != ok {
        run.failed = true
        ret ""
    }
    var out = b
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c == 46u8 { c = 95u8 }
        let pushed = str.push_byte(&out, c)
        if pushed != ok { run.failed = true }
        at += 1usize
    }
    ret str.done(&out)
}

// Salt's argument list (single-key dicts) or mapping, flattened to one mapping; a later key replaces an earlier.
fn salt_args(run: *Run, v: yaml.Value) -> Fields {
    var out = new_fields(run.a)
    let (items, is_seq) = items_of(v)
    if is_seq {
        var at = 0usize
        while at < items.len {
            let (m, is_map) = pairs_of(items[at])
            if is_map {
                var k = 0usize
                while k < m.len {
                    let (key, is_text) = string_of(m[k].key)
                    if is_text { put(&out, key, m[k].value) }
                    k += 1usize
                }
            }
            at += 1usize
        }
    } else {
        let (m, is_map) = pairs_of(v)
        if is_map {
            var k = 0usize
            while k < m.len {
                let (key, is_text) = string_of(m[k].key)
                if is_text { put(&out, key, m[k].value) }
                k += 1usize
            }
        }
    }
    ret out
}

fn ascii_lower_eq(s: str, lower: str) -> bool {
    if s.len != lower.len { ret false }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c != lower[at] { ret false }
        at += 1usize
    }
    ret true
}

fn truthy(m: []const yaml.Pair, name: str) -> bool {
    let (v, found) = get(m, name)
    if !found { ret false }
    let (flag, is_bool) = bool_of(v)
    if is_bool { ret flag }
    let (text, is_text) = string_of(v)
    if is_text { ret ascii_lower_eq(text, "true") }
    ret false
}

fn salt_present(run: *Run, type_name: str, name: str, present: bool) -> yaml.Value {
    var r = new_fields(run.a)
    put_s(&r, "type", type_name)
    put_s(&r, "name", name)
    put_s(&r, "state", choose(present, "present", "absent"))
    ret finish(&r)
}

// One Salt state call as a resource.
fn salt_state(run: *Run, func: str, args: []const yaml.Pair, id: str) -> (yaml.Value, bool) {
    let name = sval_or(args, "name", id)
    if str.eq(func, "pkg.installed") || str.eq(func, "pkg.present") || str.eq(func, "pkg.latest") {
        ret (salt_present(run, "os.package", name, true), true)
    }
    if str.eq(func, "pkg.removed") || str.eq(func, "pkg.absent") || str.eq(func, "pkg.purged") {
        ret (salt_present(run, "os.package", name, false), true)
    }
    if str.eq(func, "service.running") || str.eq(func, "service.enabled") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.service")
        put_s(&r, "name", name)
        put_s(&r, "state", "started")
        if str.eq(func, "service.enabled") || truthy(args, "enable") { put_b(&r, "enabled", true) }
        ret (finish(&r), true)
    }
    if str.eq(func, "service.dead") || str.eq(func, "service.disabled") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.service")
        put_s(&r, "name", name)
        put_s(&r, "state", "stopped")
        ret (finish(&r), true)
    }
    if str.eq(func, "file.managed") {
        let (contents, have_contents) = sval(args, "contents")
        if !have_contents {
            warn(run, cat3(run, "state '", id, "': file.managed without inline `contents` (source not supported), skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.file")
        put_s(&r, "path", name)
        put_s(&r, "content", contents)
        let (mode, have_mode) = sval(args, "mode")
        if have_mode { put_s(&r, "mode", mode) }
        ret (finish(&r), true)
    }
    if str.eq(func, "cmd.run") || str.eq(func, "cmd.script") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.command")
        put_s(&r, "command", name)
        ret (finish(&r), true)
    }
    if str.eq(func, "user.present") { ret (salt_present(run, "os.user", name, true), true) }
    if str.eq(func, "user.absent") { ret (salt_present(run, "os.user", name, false), true) }
    if str.eq(func, "group.present") { ret (salt_present(run, "os.group", name, true), true) }
    if str.eq(func, "group.absent") { ret (salt_present(run, "os.group", name, false), true) }
    if str.eq(func, "file.directory") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.directory")
        put_s(&r, "path", name)
        let (mode, have_mode) = sval(args, "mode")
        if have_mode { put_s(&r, "mode", mode) }
        ret (finish(&r), true)
    }
    if str.eq(func, "file.line") {
        let (content, have_content) = sval(args, "content")
        if !have_content {
            warn(run, cat3(run, "state '", id, "': file.line needs `content`, skipped"))
            ret (.Null, false)
        }
        let (mode, have_mode) = sval(args, "mode")
        let present = !(have_mode && (str.eq(mode, "delete") || str.eq(mode, "absent")))
        var r = new_fields(run.a)
        put_s(&r, "type", "os.line_in_file")
        put_s(&r, "path", name)
        put_s(&r, "line", content)
        put_s(&r, "state", choose(present, "present", "absent"))
        ret (finish(&r), true)
    }
    if str.eq(func, "cron.present") || str.eq(func, "cron.absent") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.cron")
        put_s(&r, "name", name)
        put_s(&r, "state", choose(str.eq(func, "cron.present"), "present", "absent"))
        put_s(&r, "schedule", schedule5(run, args, "minute", "hour", "daymonth", "month", "dayweek"))
        put_s(&r, "command", name)
        ret (finish(&r), true)
    }
    if str.eq(func, "sysctl.present") {
        let (value, have_value) = sval(args, "value")
        if !have_value { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.sysctl")
        put_s(&r, "key", name)
        put_s(&r, "value", value)
        ret (finish(&r), true)
    }
    if str.eq(func, "timezone.system") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.timezone")
        put_s(&r, "name", name)
        ret (finish(&r), true)
    }
    if str.eq(func, "mount.mounted") {
        let (device, have_device) = sval(args, "device")
        if !have_device { ret (.Null, false) }
        let (fstype, have_fstype) = sval(args, "fstype")
        if !have_fstype { ret (.Null, false) }
        var opts = ""
        var have_opts = false
        let (opts_value, have_value) = get(args, "opts")
        if have_value {
            let (text, is_text) = string_of(opts_value)
            if is_text {
                opts = text
                have_opts = true
            } else {
                let (items, is_seq) = items_of(opts_value)
                if is_seq {
                    var kept: [64]str = zero
                    var count = 0usize
                    var at = 0usize
                    while at < items.len && count < 64usize {
                        let (item, item_is_text) = string_of(items[at])
                        if item_is_text {
                            kept[count] = item
                            count += 1usize
                        }
                        at += 1usize
                    }
                    let (joined, join_error) = str.join(run.a, kept[0..count], ",")
                    if join_error != ok { run.failed = true }
                    opts = joined
                    have_opts = true
                }
            }
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.mount")
        put_s(&r, "src", device)
        put_s(&r, "path", name)
        put_s(&r, "fstype", fstype)
        if have_opts { put_s(&r, "opts", opts) }
        ret (finish(&r), true)
    }
    if str.eq(func, "mount.unmounted") {
        warn(run, cat3(run, "state '", id, "': mount.unmounted not supported (os.mount is mounted-only), skipped"))
        ret (.Null, false)
    }
    if str.eq(func, "pip.installed") || str.eq(func, "pip.removed") {
        let (pkg, version, has_version) = str.split_once(name, "==")
        var r = new_fields(run.a)
        put_s(&r, "type", "os.pip")
        put_s(&r, "name", choose(has_version, pkg, name))
        put_s(&r, "state", choose(str.eq(func, "pip.installed"), "present", "absent"))
        if has_version { put_s(&r, "version", version) }
        ret (finish(&r), true)
    }
    if str.eq(func, "git.latest") {
        let (dest, have_dest) = sval(args, "target")
        if !have_dest { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.git")
        put_s(&r, "repo", name)
        put_s(&r, "dest", dest)
        let (rev, have_rev) = sval(args, "rev")
        if have_rev { put_s(&r, "version", rev) }
        ret (finish(&r), true)
    }
    if str.eq(func, "ssh_auth.present") || str.eq(func, "ssh_auth.absent") {
        let (user, have_user) = sval(args, "user")
        if !have_user { ret (.Null, false) }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.authorized_key")
        put_s(&r, "user", user)
        put_s(&r, "key", name)
        put_s(&r, "state", choose(str.eq(func, "ssh_auth.present"), "present", "absent"))
        ret (finish(&r), true)
    }
    warn(run, cat(run, "state '", id, "': '", func, "' not supported, skipped"))
    ret (.Null, false)
}

// A Salt `.sls` state file (YAML text) as one `salt-import` play.
fn salt(a: *mem.Arena, source: str, project: str) -> (Migration, err) {
    let (doc, parse_error) = yaml.parse(a, source, parse_options())
    if parse_error != ok { ret (zero, parse_error) }
    let (states, is_map) = pairs_of(doc)
    if !is_map { ret (zero, NotStates) }
    var run = start(a)
    var resources = new_fields(a)
    var si = 0usize
    while si < states.len {
        let (given, is_text) = string_of(states[si].key)
        var id = given
        if !is_text { id = "?" }
        if str.eq(id, "include") || str.eq(id, "extend") {
            warn(&run, cat3(&run, "top-level '", id, "' not translated, skipped"))
            si += 1usize
            continue
        }
        let (body, body_is_map) = pairs_of(states[si].value)
        if !body_is_map {
            warn(&run, cat3(&run, "state '", id, "': not a mapping, skipped"))
            si += 1usize
            continue
        }
        var calls = 0usize
        var bi = 0usize
        while bi < body.len {
            let (key, key_is_text) = string_of(body[bi].key)
            if key_is_text && contains_dot(key) { calls += 1usize }
            bi += 1usize
        }
        let multi = calls > 1usize
        bi = 0usize
        while bi < body.len {
            let (func, func_is_text) = string_of(body[bi].key)
            if func_is_text && contains_dot(func) {
                var args = salt_args(&run, body[bi].value)
                let (res, made) = salt_state(&run, func, list.slice_const[yaml.Pair](&args.pairs), id)
                if made {
                    var rid = id
                    if multi { rid = cat3(&run, id, "-", dots_to_underscores(&run, func)) }
                    check(&run, res)
                    put(&resources, rid, res)
                    run.migrated += 1usize
                }
            }
            bi += 1usize
        }
        si += 1usize
    }
    let document = single_play(&run, project, "salt-import", &resources)
    let (migration, migration_error) = result(&run, document)
    ret (migration, migration_error)
}

// --- puppet ---------------------------------------------------------------------------------------------------------

fn is_ascii_space(b: u8) -> bool { ret b == 32u8 || (b >= 9u8 && b <= 13u8) }

fn is_word_byte(b: u8) -> bool {
    ret (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) || b == 95u8 || b == 47u8 || b == 46u8 || b == 45u8 || b >= 128u8
}

fn push_tok(run: *Run, toks: *list.List[Tok], kind: u8, text: str) {
    let pushed = list.push[Tok](toks, Tok { kind: kind, text: text })
    if pushed != ok { run.failed = true }
}

// The Puppet tokens of a manifest, comments stripped; unknown punctuation is skipped.
fn lex_puppet(run: *Run, src: str) -> list.List[Tok] {
    let (toks, toks_error) = list.init[Tok](run.a, 32usize)
    if toks_error != ok { run.failed = true }
    var out = toks
    var i = 0usize
    while i < src.len {
        let c = src[i]
        if c == 35u8 {
            while i < src.len && src[i] != 10u8 { i += 1usize }
        } else if is_ascii_space(c) {
            i += 1usize
        } else if c == 39u8 || c == 34u8 {
            var j = i + 1usize
            while j < src.len && src[j] != c { j += 1usize }
            var end_at = j
            if end_at > src.len { end_at = src.len }
            push_tok(run, &out, T_STR, src[i + 1usize..end_at])
            i = j + 1usize
        } else if c == 61u8 && i + 1usize < src.len && src[i + 1usize] == 62u8 {
            push_tok(run, &out, T_ARROW, "")
            i += 2usize
        } else if c == 123u8 {
            push_tok(run, &out, T_OPEN, "")
            i += 1usize
        } else if c == 125u8 {
            push_tok(run, &out, T_CLOSE, "")
            i += 1usize
        } else if c == 58u8 {
            push_tok(run, &out, T_COLON, "")
            i += 1usize
        } else if c == 44u8 {
            push_tok(run, &out, T_COMMA, "")
            i += 1usize
        } else if c == 59u8 {
            push_tok(run, &out, T_SEMI, "")
            i += 1usize
        } else if is_word_byte(c) {
            let begin = i
            while i < src.len && is_word_byte(src[i]) { i += 1usize }
            push_tok(run, &out, T_WORD, src[begin..i])
        } else {
            i += 1usize
        }
    }
    ret out
}

// Rust's `{:?}` of a token, for a stray one at the top level of a manifest.
fn debug_string(run: *Run, s: str) -> str {
    let (b, builder_error) = str.builder(run.a, s.len + 8usize)
    if builder_error != ok {
        run.failed = true
        ret ""
    }
    var out = b
    var at = 0usize
    while at < s.len {
        let c = s[at]
        var pushed = ok
        if c == 34u8 {
            pushed = str.push(&out, "\\\"")
        } else if c == 92u8 {
            pushed = str.push(&out, "\\\\")
        } else if c == 10u8 {
            pushed = str.push(&out, "\\n")
        } else if c == 13u8 {
            pushed = str.push(&out, "\\r")
        } else if c == 9u8 {
            pushed = str.push(&out, "\\t")
        } else if c == 0u8 {
            pushed = str.push(&out, "\\0")
        } else if c < 32u8 || c == 127u8 {
            let high = u8(48usize + usize(c) / 16usize)
            var low = u8(48usize + usize(c) % 16usize)
            if usize(c) % 16usize >= 10usize { low = u8(97usize + usize(c) % 16usize - 10usize) }
            pushed = str.push(&out, "\\u{")
            if pushed == ok { pushed = str.push_byte(&out, high) }
            if pushed == ok { pushed = str.push_byte(&out, low) }
            if pushed == ok { pushed = str.push(&out, "}") }
        } else {
            pushed = str.push_byte(&out, c)
        }
        if pushed != ok { run.failed = true }
        at += 1usize
    }
    ret str.done(&out)
}

fn token_debug(run: *Run, t: Tok) -> str {
    if t.kind == T_WORD { ret cat3(run, "Word(\"", debug_string(run, t.text), "\")") }
    if t.kind == T_STR { ret cat3(run, "Str(\"", debug_string(run, t.text), "\")") }
    if t.kind == T_ARROW { ret "Arrow" }
    if t.kind == T_OPEN { ret "Open" }
    if t.kind == T_CLOSE { ret "Close" }
    if t.kind == T_COLON { ret "Colon" }
    if t.kind == T_COMMA { ret "Comma" }
    ret "Semi"
}

// Past the next `{ ... }` group, best effort.
fn skip_to_close(toks: []const Tok, from: usize) -> usize {
    var depth = 0i64
    var i = from
    while i < toks.len {
        if toks[i].kind == T_OPEN {
            depth += 1i64
        } else if toks[i].kind == T_CLOSE {
            depth -= 1i64
            if depth <= 0i64 { ret i + 1usize }
        }
        i += 1usize
    }
    ret toks.len
}

fn state_of(present: bool) -> str { ret choose(present, "present", "absent") }

// A Puppet resource as a CM resource, or absent with a warning.
fn puppet_resource(run: *Run, type_name: str, title: str, attrs: []const Attr) -> (yaml.Value, bool) {
    let (ensure, have_ensure) = attrs_get(attrs, "ensure")
    let name = attrs_or(attrs, "name", title)
    if str.eq(type_name, "package") {
        let present = !(have_ensure && (str.eq(ensure, "absent") || str.eq(ensure, "purged")))
        let (provider, have_provider) = attrs_get(attrs, "provider")
        if have_provider && (str.eq(provider, "pip") || str.eq(provider, "pip3")) {
            var r = new_fields(run.a)
            put_s(&r, "type", "os.pip")
            put_s(&r, "name", name)
            put_s(&r, "state", state_of(present))
            if have_ensure && !(str.eq(ensure, "present") || str.eq(ensure, "installed") || str.eq(ensure, "latest") || str.eq(ensure, "absent") || str.eq(ensure, "purged")) {
                put_s(&r, "version", ensure)
            }
            ret (finish(&r), true)
        }
        ret (salt_present(run, "os.package", name, present), true)
    }
    if str.eq(type_name, "service") {
        let started = !(have_ensure && str.eq(ensure, "stopped"))
        var r = new_fields(run.a)
        put_s(&r, "type", "os.service")
        put_s(&r, "name", name)
        put_s(&r, "state", choose(started, "started", "stopped"))
        let (enable, have_enable) = attrs_get(attrs, "enable")
        if have_enable { put_b(&r, "enabled", str.eq(enable, "true")) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "file") {
        if have_ensure && str.eq(ensure, "directory") {
            var r = new_fields(run.a)
            put_s(&r, "type", "os.directory")
            put_s(&r, "path", name)
            let (mode, have_mode) = attrs_get(attrs, "mode")
            if have_mode { put_s(&r, "mode", mode) }
            ret (finish(&r), true)
        }
        let (content, have_content) = attrs_get(attrs, "content")
        if !have_content {
            warn(run, cat3(run, "file '", title, "': no inline `content` (source/template not supported), skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.file")
        put_s(&r, "path", name)
        put_s(&r, "content", content)
        let (mode, have_mode) = attrs_get(attrs, "mode")
        if have_mode { put_s(&r, "mode", mode) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "exec") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.command")
        put_s(&r, "command", attrs_or(attrs, "command", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "user") {
        ret (salt_present(run, "os.user", name, !(have_ensure && str.eq(ensure, "absent"))), true)
    }
    if str.eq(type_name, "group") {
        ret (salt_present(run, "os.group", name, !(have_ensure && str.eq(ensure, "absent"))), true)
    }
    if str.eq(type_name, "file_line") {
        let (line, have_line) = attrs_get(attrs, "line")
        if !have_line {
            warn(run, cat3(run, "file_line '", title, "': needs `line`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.line_in_file")
        put_s(&r, "path", attrs_or(attrs, "path", name))
        put_s(&r, "line", line)
        put_s(&r, "state", state_of(!(have_ensure && str.eq(ensure, "absent"))))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "cron") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.cron")
        put_s(&r, "name", name)
        put_s(&r, "state", state_of(!(have_ensure && str.eq(ensure, "absent"))))
        var parts: [9]str = zero
        parts[0] = attrs_or(attrs, "minute", "*")
        parts[1] = " "
        parts[2] = attrs_or(attrs, "hour", "*")
        parts[3] = " "
        parts[4] = attrs_or(attrs, "monthday", "*")
        parts[5] = " "
        parts[6] = attrs_or(attrs, "month", "*")
        parts[7] = " "
        parts[8] = attrs_or(attrs, "weekday", "*")
        let (schedule, join_error) = str.join(run.a, parts[0..9], "")
        if join_error != ok { run.failed = true }
        put_s(&r, "schedule", schedule)
        put_s(&r, "command", attrs_or(attrs, "command", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "sysctl") {
        let (value, have_value) = attrs_get(attrs, "value")
        if !have_value {
            warn(run, cat3(run, "sysctl '", title, "': needs `value`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.sysctl")
        put_s(&r, "key", name)
        put_s(&r, "value", value)
        ret (finish(&r), true)
    }
    if str.eq(type_name, "mount") {
        if have_ensure && (str.eq(ensure, "absent") || str.eq(ensure, "unmounted")) {
            warn(run, cat(run, "mount '", title, "': ensure '", ensure, "' not supported (os.mount is mounted-only), skipped"))
            ret (.Null, false)
        }
        let (device, have_device) = attrs_get(attrs, "device")
        let (fstype, have_fstype) = attrs_get(attrs, "fstype")
        if !(have_device && have_fstype) {
            warn(run, cat3(run, "mount '", title, "': needs `device` and `fstype`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.mount")
        put_s(&r, "src", device)
        put_s(&r, "path", name)
        put_s(&r, "fstype", fstype)
        let (opts, have_opts) = attrs_get(attrs, "options")
        if have_opts { put_s(&r, "opts", opts) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "vcsrepo") {
        let (repo, have_repo) = attrs_get(attrs, "source")
        if !have_repo {
            warn(run, cat3(run, "vcsrepo '", title, "': needs `source`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.git")
        put_s(&r, "repo", repo)
        put_s(&r, "dest", attrs_or(attrs, "path", name))
        let (revision, have_revision) = attrs_get(attrs, "revision")
        if have_revision { put_s(&r, "version", revision) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "ssh_authorized_key") {
        let (user, have_user) = attrs_get(attrs, "user")
        let (key_type, have_type) = attrs_get(attrs, "type")
        let (key_data, have_data) = attrs_get(attrs, "key")
        if !(have_user && have_type && have_data) {
            warn(run, cat3(run, "ssh_authorized_key '", title, "': needs `user`, `type`, and `key`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.authorized_key")
        put_s(&r, "user", user)
        put_s(&r, "key", cat(run, key_type, " ", key_data, " ", title))
        put_s(&r, "state", state_of(!(have_ensure && str.eq(ensure, "absent"))))
        ret (finish(&r), true)
    }
    warn(run, cat(run, "resource type '", type_name, "' ('", title, "') not supported, skipped"))
    ret (.Null, false)
}

// A Puppet manifest (text) as one `puppet-import` play.
fn puppet(a: *mem.Arena, source: str, project: str) -> (Migration, err) {
    var run = start(a)
    var list_toks = lex_puppet(&run, source)
    let toks = list.slice_const[Tok](&list_toks)
    var resources = new_fields(a)
    var i = 0usize
    while i < toks.len {
        if toks[i].kind != T_WORD {
            warn(&run, cat2(&run, "skipped unexpected token ", token_debug(&run, toks[i])))
            i += 1usize
            continue
        }
        let type_name = toks[i].text
        if !(i + 1usize < toks.len && toks[i + 1usize].kind == T_OPEN) {
            warn(&run, cat3(&run, "'", type_name, "' is not a simple resource declaration, skipped"))
            i = skip_to_close(toks, i)
            continue
        }
        var title = ""
        var have_title = false
        if i + 2usize < toks.len && (toks[i + 2usize].kind == T_STR || toks[i + 2usize].kind == T_WORD) {
            title = toks[i + 2usize].text
            have_title = true
        }
        if !have_title {
            warn(&run, cat3(&run, "resource '", type_name, "': missing title, skipped"))
            i = skip_to_close(toks, i)
            continue
        }
        if !(i + 3usize < toks.len && toks[i + 3usize].kind == T_COLON) {
            warn(&run, cat(&run, "resource '", type_name, " ", title, "': malformed, skipped"))
            i = skip_to_close(toks, i)
            continue
        }
        let (attr_list, attr_error) = list.init[Attr](a, 8usize)
        if attr_error != ok { run.failed = true }
        var attr_buf = attr_list
        var j = i + 4usize
        while j < toks.len && toks[j].kind != T_CLOSE {
            if toks[j].kind == T_COMMA || toks[j].kind == T_SEMI {
                j += 1usize
                continue
            }
            if toks[j].kind == T_WORD && j + 1usize < toks.len && toks[j + 1usize].kind == T_ARROW {
                var value = ""
                if j + 2usize < toks.len && (toks[j + 2usize].kind == T_STR || toks[j + 2usize].kind == T_WORD) {
                    value = toks[j + 2usize].text
                }
                attrs_set(&run, &attr_buf, toks[j].text, value)
                j += 3usize
            } else {
                j += 1usize
            }
        }
        let (res, made) = puppet_resource(&run, type_name, title, list.slice_const[Attr](&attr_buf))
        if made {
            var rid = title
            if has_id(&resources, rid) { rid = cat3(&run, type_name, "_", title) }
            check(&run, res)
            put(&resources, rid, res)
            run.migrated += 1usize
        }
        i = j + 1usize
    }
    let document = single_play(&run, project, "puppet-import", &resources)
    let (migration, migration_error) = result(&run, document)
    ret (migration, migration_error)
}

// --- chef -----------------------------------------------------------------------------------------------------------

fn unquote(s: str) -> str {
    let t = str.trim(s)
    if t.len >= 2usize && (t[0] == 39u8 || t[0] == 34u8) && t[t.len - 1usize] == t[0] { ret t[1usize..t.len - 1usize] }
    ret t
}

fn first_space(s: str) -> (usize, bool) {
    var at = 0usize
    while at < s.len {
        if is_ascii_space(s[at]) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// `type 'name' do` -> (type, name).
fn chef_header(line: str) -> (str, str, bool) {
    if !str.ends_with(line, " do") { ret ("", "", false) }
    let body = str.trim_end(line[0usize..line.len - 3usize])
    let (at, found) = first_space(body)
    if !found { ret ("", "", false) }
    let rest = str.trim(body[at + 1usize..])
    if rest.len == 0usize || !(rest[0] == 39u8 || rest[0] == 34u8) { ret ("", "", false) }
    ret (body[0usize..at], unquote(rest), true)
}

// A block-less resource: `hostname 'web-01'` -> (type, name).
fn chef_oneliner(line: str) -> (str, str, bool) {
    if str.eq(line, "do") || str.ends_with(line, " do") { ret ("", "", false) }
    let (at, found) = first_space(line)
    if !found { ret ("", "", false) }
    let type_name = line[0usize..at]
    if type_name.len == 0usize { ret ("", "", false) }
    var k = 0usize
    while k < type_name.len {
        let c = type_name[k]
        let ok_char = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8
        if !ok_char { ret ("", "", false) }
        k += 1usize
    }
    let rest = str.trim(line[at + 1usize..])
    if rest.len == 0usize { ret ("", "", false) }
    let quote = rest[0]
    if quote != 39u8 && quote != 34u8 { ret ("", "", false) }
    if rest.len < 2usize || rest[rest.len - 1usize] != quote { ret ("", "", false) }
    var inner = 1usize
    while inner < rest.len - 1usize {
        if rest[inner] == quote { ret ("", "", false) }
        inner += 1usize
    }
    ret (type_name, unquote(rest), true)
}

fn has_action(actions: []const str, name: str) -> bool {
    var at = 0usize
    while at < actions.len {
        if str.eq(actions[at], name) { ret true }
        at += 1usize
    }
    ret false
}

// A Chef resource as (config id, value).
fn chef_resource(run: *Run, type_name: str, name: str, attrs: []const Attr, actions: []const str) -> (yaml.Value, bool) {
    if str.eq(type_name, "package") || str.eq(type_name, "apt_package") || str.eq(type_name, "yum_package") || str.eq(type_name, "dnf_package") {
        let present = !(has_action(actions, "remove") || has_action(actions, "purge"))
        ret (salt_present(run, "os.package", attrs_or(attrs, "package_name", name), present), true)
    }
    if str.eq(type_name, "service") {
        let started = !(has_action(actions, "stop") || has_action(actions, "disable")) && (has_action(actions, "start") || has_action(actions, "enable") || actions.len == 0usize)
        var r = new_fields(run.a)
        put_s(&r, "type", "os.service")
        put_s(&r, "name", attrs_or(attrs, "service_name", name))
        put_s(&r, "state", choose(started, "started", "stopped"))
        if has_action(actions, "enable") { put_b(&r, "enabled", true) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "file") || str.eq(type_name, "template") || str.eq(type_name, "cookbook_file") {
        let (content, have_content) = attrs_get(attrs, "content")
        if !have_content {
            warn(run, cat(run, type_name, " '", name, "': no inline `content` (source/template not supported), skipped", ""))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.file")
        put_s(&r, "path", attrs_or(attrs, "path", name))
        put_s(&r, "content", content)
        let (mode, have_mode) = attrs_get(attrs, "mode")
        if have_mode { put_s(&r, "mode", mode) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "directory") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.directory")
        put_s(&r, "path", attrs_or(attrs, "path", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "execute") || str.eq(type_name, "bash") || str.eq(type_name, "script") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.command")
        put_s(&r, "command", attrs_or(attrs, "command", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "user") {
        ret (salt_present(run, "os.user", attrs_or(attrs, "username", name), !has_action(actions, "remove")), true)
    }
    if str.eq(type_name, "group") {
        ret (salt_present(run, "os.group", attrs_or(attrs, "group_name", name), !has_action(actions, "remove")), true)
    }
    if str.eq(type_name, "cron") || str.eq(type_name, "cron_d") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.cron")
        put_s(&r, "name", name)
        put_s(&r, "state", state_of(!has_action(actions, "delete")))
        var parts: [9]str = zero
        parts[0] = attrs_or(attrs, "minute", "*")
        parts[1] = " "
        parts[2] = attrs_or(attrs, "hour", "*")
        parts[3] = " "
        parts[4] = attrs_or(attrs, "day", "*")
        parts[5] = " "
        parts[6] = attrs_or(attrs, "month", "*")
        parts[7] = " "
        parts[8] = attrs_or(attrs, "weekday", "*")
        let (schedule, join_error) = str.join(run.a, parts[0..9], "")
        if join_error != ok { run.failed = true }
        put_s(&r, "schedule", schedule)
        put_s(&r, "command", attrs_or(attrs, "command", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "sysctl") || str.eq(type_name, "sysctl_param") {
        let (value, have_value) = attrs_get(attrs, "value")
        if !have_value {
            warn(run, cat3(run, "sysctl '", name, "': needs `value`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.sysctl")
        put_s(&r, "key", attrs_or(attrs, "key", name))
        put_s(&r, "value", value)
        ret (finish(&r), true)
    }
    if str.eq(type_name, "python_package") || str.eq(type_name, "pip_package") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.pip")
        put_s(&r, "name", attrs_or(attrs, "package_name", name))
        put_s(&r, "state", state_of(!(has_action(actions, "remove") || has_action(actions, "purge"))))
        let (version, have_version) = attrs_get(attrs, "version")
        if have_version { put_s(&r, "version", version) }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "git") {
        var repo = ""
        var have_repo = false
        let (repository, have_repository) = attrs_get(attrs, "repository")
        if have_repository {
            repo = repository
            have_repo = true
        } else {
            let (short_repo, have_short) = attrs_get(attrs, "repo")
            repo = short_repo
            have_repo = have_short
        }
        if !have_repo {
            warn(run, cat3(run, "git '", name, "': needs `repository`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.git")
        put_s(&r, "repo", repo)
        put_s(&r, "dest", attrs_or(attrs, "destination", name))
        let (revision, have_revision) = attrs_get(attrs, "revision")
        if have_revision {
            put_s(&r, "version", revision)
        } else {
            let (reference, have_reference) = attrs_get(attrs, "reference")
            if have_reference { put_s(&r, "version", reference) }
        }
        ret (finish(&r), true)
    }
    if str.eq(type_name, "hostname") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.hostname")
        put_s(&r, "name", attrs_or(attrs, "hostname", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "timezone") {
        var r = new_fields(run.a)
        put_s(&r, "type", "os.timezone")
        put_s(&r, "name", attrs_or(attrs, "timezone", name))
        ret (finish(&r), true)
    }
    if str.eq(type_name, "mount") {
        if has_action(actions, "umount") || has_action(actions, "unmount") || has_action(actions, "disable") {
            warn(run, cat3(run, "mount '", name, "': umount/disable not supported (os.mount is mounted-only), skipped"))
            ret (.Null, false)
        }
        let (device, have_device) = attrs_get(attrs, "device")
        let (fstype, have_fstype) = attrs_get(attrs, "fstype")
        if !(have_device && have_fstype) {
            warn(run, cat3(run, "mount '", name, "': needs `device` and `fstype`, skipped"))
            ret (.Null, false)
        }
        var r = new_fields(run.a)
        put_s(&r, "type", "os.mount")
        put_s(&r, "src", device)
        put_s(&r, "path", attrs_or(attrs, "mount_point", name))
        put_s(&r, "fstype", fstype)
        let (opts, have_opts) = attrs_get(attrs, "options")
        if have_opts { put_s(&r, "opts", opts) }
        ret (finish(&r), true)
    }
    warn(run, cat(run, "resource type '", type_name, "' ('", name, "') not supported, skipped"))
    ret (.Null, false)
}

fn chef_emit(run: *Run, resources: *Fields, type_name: str, name: str, attrs: []const Attr, actions: []const str) {
    let (res, made) = chef_resource(run, type_name, name, attrs, actions)
    if !made { ret }
    var id = name
    if has_id(resources, id) { id = cat3(run, type_name, "_", name) }
    check(run, res)
    put(resources, id, res)
    run.migrated += 1usize
}

fn split_actions(run: *Run, val: str, out: *list.List[str]) {
    var begin = 0usize
    var at = 0usize
    while at <= val.len {
        var cut = at == val.len
        if !cut {
            let c = val[at]
            cut = c == 32u8 || c == 44u8 || c == 91u8 || c == 93u8 || c == 58u8
        }
        if cut {
            let piece = str.trim(val[begin..at])
            if piece.len > 0usize {
                let pushed = list.push[str](out, piece)
                if pushed != ok { run.failed = true }
            }
            begin = at + 1usize
        }
        at += 1usize
    }
}

// A Chef recipe (text) as one `chef-import` play.
fn chef(a: *mem.Arena, source: str, project: str) -> (Migration, err) {
    var run = start(a)
    var resources = new_fields(a)
    var inside = false
    var cur_type = ""
    var cur_name = ""
    let (attr_init, attr_error) = list.init[Attr](a, 8usize)
    let (action_init, action_error) = list.init[str](a, 4usize)
    if attr_error != ok || action_error != ok { ret (zero, Exhausted) }
    var attrs = attr_init
    var actions = action_init
    var lines = str.lines(source)
    while true {
        let (raw, more) = str.split_next(&lines)
        if !more { break }
        var line = raw
        let (hash_at, has_hash) = str.find(raw, "#")
        if has_hash { line = raw[0usize..hash_at] }
        let t = str.trim(line)
        if t.len == 0usize { continue }
        if !inside {
            let (type_name, name, is_header) = chef_header(t)
            if is_header {
                inside = true
                cur_type = type_name
                cur_name = name
                attrs.len = 0usize
                actions.len = 0usize
            } else {
                let (one_type, one_name, is_one) = chef_oneliner(t)
                if is_one {
                    var none_attrs = attrs
                    none_attrs.len = 0usize
                    var none_actions = actions
                    none_actions.len = 0usize
                    chef_emit(&run, &resources, one_type, one_name, list.slice_const[Attr](&none_attrs), list.slice_const[str](&none_actions))
                } else {
                    warn(&run, cat2(&run, "skipped non-resource line: ", t))
                }
            }
        } else {
            if str.eq(t, "end") {
                chef_emit(&run, &resources, cur_type, cur_name, list.slice_const[Attr](&attrs), list.slice_const[str](&actions))
                inside = false
                attrs.len = 0usize
                actions.len = 0usize
            } else {
                let (at, found) = first_space(t)
                if found {
                    let attr = t[0usize..at]
                    let val = t[at + 1usize..]
                    if str.eq(attr, "action") {
                        split_actions(&run, val, &actions)
                    } else {
                        attrs_set(&run, &attrs, attr, unquote(str.trim(val)))
                    }
                }
            }
        }
    }
    if inside { warn(&run, "recipe ended inside an unterminated resource block") }
    let document = single_play(&run, project, "chef-import", &resources)
    let (migration, migration_error) = result(&run, document)
    ret (migration, migration_error)
}

// The document as block YAML.
fn write(w: *io.Writer, m: *const Migration) -> err { ret yaml.write(w, &m.document, 2u8) }
