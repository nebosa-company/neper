// R as the oracle. `scripts/r_oracle/generate.R` runs R over seeded inputs and writes the
// answers to `tests/oracle/<group>.json`; `load` reads one and `agrees` judges a value
// Neper computed against R's. The goldens are committed, so a suite never needs R.
//
// A golden is {"group", "meta", "cases":[{"fn", "args":[..], "want", "rel", "abs"}]}. A number
// is a JSON number; NA, NaN, Inf and -Inf are the strings of those names, because JSON has no
// spelling for them. A case may carry "text" in place of "want", for an answer that is a string. NA and NaN are one value here -- Neper has no NA, and a function that
// answers NaN where R answers NA agrees. Dispatch on `Case.name` belongs to the fixture.

use e.fmt.json as json
use e.fs
use e.mem
use e.str

type Case = struct { name: str, args: []f64, want: f64, rel: f64, abs: f64, text: str, inputs: []str }

type Golden = struct { group: str, r: str, cases: []Case }

error Malformed

const GOLDEN_LIMIT: usize = 67108864usize

fn nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

fn infinity(negative: bool) -> f64 {
    if negative { ret mem.bitcast[f64](18442240474082181120u64) }
    ret mem.bitcast[f64](9218868437227405312u64)
}

fn is_nan(x: f64) -> bool { ret x != x }

fn scalar(v: json.Value) -> (f64, err) {
    let (written, is_number) = json.number_of(v)
    if is_number {
        let (x, e) = json.number_f64(written)
        ret (x, e)
    }
    let (word, is_text) = json.string_of(v)
    if !is_text { ret (0.0f64, Malformed) }
    if str.eq(word, "NA") || str.eq(word, "NaN") { ret (nan(), ok) }
    if str.eq(word, "Inf") { ret (infinity(false), ok) }
    if str.eq(word, "-Inf") { ret (infinity(true), ok) }
    ret (0.0f64, Malformed)
}

fn member(members: []const json.Member, name: str) -> (json.Value, err) {
    let (v, found) = json.member_of(members, name)
    if !found { ret (v, Malformed) }
    ret (v, ok)
}

fn member_scalar(members: []const json.Member, name: str) -> (f64, err) {
    let (v, e) = member(members, name)
    if e != ok { ret (0.0f64, e) }
    let (x, e2) = scalar(v)
    ret (x, e2)
}

fn load_case(a: *mem.Arena, v: json.Value) -> (Case, err) {
    var c: Case = zero
    let (members, is_object) = json.object_of(v)
    if !is_object { ret (c, Malformed) }
    let (name_value, name_error) = member(members, "fn")
    if name_error != ok { ret (c, name_error) }
    let (name, is_text) = json.string_of(name_value)
    if !is_text { ret (c, Malformed) }
    let (args_value, args_error) = member(members, "args")
    if args_error != ok { ret (c, args_error) }
    let (items, is_array) = json.array_of(args_value)
    if !is_array { ret (c, Malformed) }
    let (args, alloc_error) = mem.alloc[f64](a, items.len)
    if alloc_error != ok { ret (c, alloc_error) }
    var at = 0usize
    while at < items.len {
        let (x, e) = scalar(items[at])
        if e != ok { ret (c, e) }
        args[at] = x
        at += 1usize
    }
    let (in_value, has_in) = json.member_of(members, "in")
    if has_in {
        let (strings, is_list) = json.array_of(in_value)
        if !is_list { ret (c, Malformed) }
        let (kept, kept_error) = mem.alloc[str](a, strings.len)
        if kept_error != ok { ret (c, kept_error) }
        var k = 0usize
        while k < strings.len {
            let (one, one_is_string) = json.string_of(strings[k])
            if !one_is_string { ret (c, Malformed) }
            kept[k] = one
            k += 1usize
        }
        c.inputs = kept
    }
    let (text_value, has_text) = json.member_of(members, "text")
    if has_text {
        let (text, text_is_string) = json.string_of(text_value)
        if !text_is_string { ret (c, Malformed) }
        c.name = name
        c.args = args
        c.want = nan()
        c.text = text
        ret (c, ok)
    }
    let (want, want_error) = member_scalar(members, "want")
    if want_error != ok { ret (c, want_error) }
    let (rel, rel_error) = member_scalar(members, "rel")
    if rel_error != ok { ret (c, rel_error) }
    let (abs, abs_error) = member_scalar(members, "abs")
    if abs_error != ok { ret (c, abs_error) }
    c.name = name
    c.args = args
    c.want = want
    c.rel = rel
    c.abs = abs
    ret (c, ok)
}

fn load(a: *mem.Arena, path: str) -> (Golden, err) {
    var g: Golden = zero
    let (text, read_error) = fs.read_file(a, path, GOLDEN_LIMIT)
    if read_error != ok { ret (g, read_error) }
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 16u16 })
    if parse_error != ok { ret (g, parse_error) }
    let (members, is_object) = json.object_of(root)
    if !is_object { ret (g, Malformed) }
    let (group_value, group_error) = member(members, "group")
    if group_error != ok { ret (g, group_error) }
    let (group, group_is_text) = json.string_of(group_value)
    if !group_is_text { ret (g, Malformed) }
    let (meta_value, meta_error) = member(members, "meta")
    if meta_error != ok { ret (g, meta_error) }
    let (meta, meta_is_object) = json.object_of(meta_value)
    if !meta_is_object { ret (g, Malformed) }
    let (r_value, r_error) = member(meta, "r")
    if r_error != ok { ret (g, r_error) }
    let (r_text, r_is_text) = json.string_of(r_value)
    if !r_is_text { ret (g, Malformed) }
    let (cases_value, cases_error) = member(members, "cases")
    if cases_error != ok { ret (g, cases_error) }
    let (items, is_array) = json.array_of(cases_value)
    if !is_array { ret (g, Malformed) }
    let (cases, alloc_error) = mem.alloc[Case](a, items.len)
    if alloc_error != ok { ret (g, alloc_error) }
    var at = 0usize
    while at < items.len {
        let (c, e) = load_case(a, items[at])
        if e != ok { ret (g, e) }
        cases[at] = c
        at += 1usize
    }
    g.group = group
    g.r = r_text
    g.cases = cases
    ret (g, ok)
}

// Within `abs` of R's answer, or within `rel` of the larger magnitude. Both zero means exact.
// A NaN from R is matched only by a NaN, and an infinity only by the same infinity.
fn agrees(got: f64, c: *const Case) -> bool {
    if is_nan(c.want) { ret is_nan(got) }
    if is_nan(got) { ret false }
    if got == c.want { ret true }
    let gap = got - c.want
    if gap - gap != 0.0f64 { ret false }
    var distance = gap
    if distance < 0.0f64 { distance = 0.0f64 - distance }
    if distance <= c.abs { ret true }
    var scale = got
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    var other = c.want
    if other < 0.0f64 { other = 0.0f64 - other }
    if other > scale { scale = other }
    ret distance <= c.rel * scale
}

// A text case, written {"fn", "args", "text"}: the answer is a string (a hash in hex, a formatted
// number) and must be equal.
fn agrees_text(got: str, c: *const Case) -> bool { ret str.eq(got, c.text) }

// "name(args): got G, R says W", for the line a failing fixture prints.
fn describe(a: *mem.Arena, c: *const Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, "(")
    var at = 0usize
    while at < c.args.len {
        if at > 0usize { let _ = str.push(&b, ", ") }
        let _ = str.push_f64(&b, c.args[at])
        at += 1usize
    }
    let _ = str.push(&b, "): got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}
