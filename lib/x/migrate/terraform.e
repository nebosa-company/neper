// Terraform to PetCow (L041), after petcow's `migrate_hcl` (src/migrate.rs): HCL (`.tf`) read by `e.fmt.hcl` and
// translated block by block into a PetCow YAML document -- `resource` of the supported types, `variable`, `locals`,
// `data`, `output`, `provider` (aliased only) and `module` -- with `count`, `for_each`, `depends_on`, `lifecycle` and
// `dynamic` blocks folded in, references turned into `${...}` templates (`var.x` as `vars.x`, `data.T.N.a` as
// `data.N.a`, `T.N.a` as `resources.N.a`), and everything that cannot be translated faithfully reported as a warning
// rather than dropped.
//
// Memory: the arena is retained; the document and the warnings live in it.

use e.data.list as list
use e.fmt.hcl as hcl
use e.fmt.yaml as yaml
use e.mem
use e.str

error Failed

type Migration = struct { document: yaml.Value, migrated: usize, warnings: []const str }

type Run = struct { a: *mem.Arena, warnings: list.List[str], migrated: usize }

// An ordered mapping under construction; inserting an existing key replaces its value in place.
type Map = struct { pairs: list.List[yaml.Pair] }

// The sections accumulated while translating the body.
type Sections = struct { variables: Map, locals: Map, data: Map, outputs: Map, providers: Map, modules: Map, resources: Map, protected: list.List[yaml.Value] }

// An optional value, as Rust's `Option<Value>`.
type Opt = struct { has: bool, v: yaml.Value }

fn some(v: yaml.Value) -> Opt { ret Opt { has: true, v: v } }

fn none() -> Opt { ret Opt { has: false, v: .Null } }

fn text(s: str) -> yaml.Value { ret yaml.Value{ String: s } }

fn new_map(a: *mem.Arena) -> Map {
    let (l, e) = list.init[yaml.Pair](a, 8usize)
    if e != ok { ret Map { pairs: list.List[yaml.Pair] { items: zero, len: 0usize, arena: a } } }
    ret Map { pairs: l }
}

fn insert(m: *Map, key: str, v: yaml.Value) {
    var at = 0usize
    while at < m.pairs.len {
        switch m.pairs.items[at].key {
        case .String as s:
            if str.eq(s, key) {
                m.pairs.items[at].value = v
                ret
            }
        default:
            at = at
        }
        at += 1usize
    }
    let pushed = list.push[yaml.Pair](&m.pairs, yaml.Pair { key: text(key), value: v })
}

fn is_empty(m: *const Map) -> bool { ret m.pairs.len == 0usize }

fn map_value(m: *const Map) -> yaml.Value { ret yaml.Value{ Mapping: list.slice_const[yaml.Pair](&m.pairs) } }

fn warn(r: *Run, s: str) {
    let e = list.push[str](&r.warnings, s)
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

fn cat3(a: *mem.Arena, x: str, y: str, z: str) -> str { ret cat(a, cat(a, x, y), z) }

fn cat4(a: *mem.Arena, w: str, x: str, y: str, z: str) -> str { ret cat(a, cat(a, cat(a, w, x), y), z) }

// --- numbers ----------------------------------------------------------------------------------------------------------

fn parse_f64_lexeme(s: str) -> (f64, bool) {
    let (v, e) = str.parse_f64(s)
    if e != ok { ret (0.0f64, false) }
    ret (v, true)
}

// Rust's `f64::to_string`: the shortest round-trip digits in plain notation, never an exponent.
fn rust_display(a: *mem.Arena, f: f64) -> str {
    let (b, e) = str.builder(a, 32usize)
    if e != ok { ret "" }
    var out = b
    let pushed = str.push_f64(&out, f)
    let t = str.done(&out)
    var epos = -1i64
    var i = 0usize
    while i < t.len {
        if t[i] == 101u8 { epos = i64(i) }
        i += 1usize
    }
    if epos < 0i64 { ret t }
    var mant = t[0usize..usize(epos)]
    var exp = 0i64
    var neg = false
    var j = usize(epos) + 1usize
    if j < t.len && (t[j] == 45u8 || t[j] == 43u8) {
        neg = t[j] == 45u8
        j += 1usize
    }
    while j < t.len {
        exp = exp * 10i64 + i64(t[j] - 48u8)
        j += 1usize
    }
    if neg { exp = -exp }
    var sign = ""
    if str.starts_with(mant, "-") {
        sign = "-"
        mant = mant[1usize..]
    }
    var digits = ""
    var point = 0i64
    var int_part = mant
    var frac_part = ""
    let (dpos, have_dot) = str.find(mant, ".")
    if have_dot {
        int_part = mant[0usize..dpos]
        frac_part = mant[dpos + 1usize..]
    }
    digits = cat(a, int_part, frac_part)
    point = i64(int_part.len) + exp
    var out_text = ""
    if point <= 0i64 {
        var zeros = ""
        var z = 0i64
        while z < -point {
            zeros = cat(a, zeros, "0")
            z += 1i64
        }
        out_text = cat3(a, "0.", zeros, digits)
    } else if usize(point) >= digits.len {
        var zeros = ""
        var z = 0usize
        while z < usize(point) - digits.len {
            zeros = cat(a, zeros, "0")
            z += 1usize
        }
        out_text = cat(a, digits, zeros)
    } else {
        out_text = cat3(a, digits[0usize..usize(point)], ".", digits[usize(point)..])
    }
    ret cat(a, sign, out_text)
}

fn integer_lexeme(s: str) -> bool {
    var at = 0usize
    if at < s.len && s[at] == 45u8 { at += 1usize }
    if at >= s.len { ret false }
    while at < s.len {
        if s[at] < 48u8 || s[at] > 57u8 { ret false }
        at += 1usize
    }
    ret true
}

// The f64 of an HCL number lexeme and its i64 when hcl-rs's `as_i64` has one: an integer literal that fits, or a float with
// no fraction (saturated).
fn number_parts(a: *mem.Arena, lexeme: str) -> (f64, bool, i64) {
    if integer_lexeme(lexeme) {
        var negative = false
        var digits = lexeme
        if str.starts_with(lexeme, "-") {
            negative = true
            digits = lexeme[1usize..]
        }
        // magnitude up to i64::MAX (or i64::MIN for a negative)
        var v = 0u64
        var overflow = false
        var i = 0usize
        while i < digits.len {
            let d = u64(digits[i] - 48u8)
            if v > (18446744073709551615u64 - d) / 10u64 { overflow = true }
            if !overflow { v = v * 10u64 + d }
            i += 1usize
        }
        let (f, f_ok) = parse_f64_lexeme(lexeme)
        if !overflow {
            if !negative && v <= 9223372036854775807u64 { ret (f, true, i64(v)) }
            if negative && v <= 9223372036854775808u64 {
                var n = 0i64
                if v == 9223372036854775808u64 { n = -9223372036854775807i64 - 1i64 } else { n = -i64(v) }
                ret (f, true, n)
            }
        }
        ret (f, false, 0i64)
    }
    let (f, f_ok) = parse_f64_lexeme(lexeme)
    if f == math_trunc(f) {
        var n = 0i64
        if f >= 9223372036854775807.0f64 {
            n = 9223372036854775807i64
        } else if f <= -9223372036854775808.0f64 {
            n = -9223372036854775807i64 - 1i64
        } else {
            n = i64(f)
        }
        ret (f, true, n)
    }
    ret (f, false, 0i64)
}

fn math_trunc(f: f64) -> f64 {
    if f >= 9223372036854775807.0f64 || f <= -9223372036854775808.0f64 { ret f }
    ret f64(i64(f))
}

// `number_to_value`: an integer where hcl-rs has one, else the float.
fn number_to_value(a: *mem.Arena, lexeme: str) -> yaml.Value {
    let (f, has_int, n) = number_parts(a, lexeme)
    if has_int { ret yaml.Value{ Integer: n } }
    ret yaml.Value{ Float: f }
}

// The number as `render_expr` prints it: an integer when the value has no fraction, else Rust's display.
fn render_number(a: *mem.Arena, lexeme: str) -> str {
    let (f, has_int, n) = number_parts(a, lexeme)
    var shown = f
    if has_int { shown = f64(n) }
    if shown == math_trunc(shown) {
        var out = n
        if !has_int {
            if shown >= 9223372036854775807.0f64 { out = 9223372036854775807i64 } else if shown <= -9223372036854775808.0f64 { out = -9223372036854775807i64 - 1i64 } else { out = i64(shown) }
        } else {
            // an integer stored as a double and back, as the original does
            if shown >= 9223372036854775807.0f64 { out = 9223372036854775807i64 } else if shown <= -9223372036854775808.0f64 { out = -9223372036854775807i64 - 1i64 } else { out = i64(shown) }
        }
        let (b, e) = str.builder(a, 24usize)
        if e != ok { ret "" }
        var bb = b
        let pushed = str.push_i64(&bb, out)
        ret str.done(&bb)
    }
    ret rust_display(a, shown)
}

// --- expressions --------------------------------------------------------------------------------------------------------

// A string as a PetCow expression literal: double quotes unless it holds one, then single quotes.
fn quote_pcl(a: *mem.Arena, s: str) -> str {
    if !str.contains(s, "\"") { ret cat3(a, "\"", s, "\"") }
    if !str.contains(s, "'") { ret cat3(a, "'", s, "'") }
    let (stripped, e) = str.replace(a, s, "\"", "")
    if e != ok { ret "" }
    ret cat3(a, "\"", stripped, "\"")
}

type Rendered = struct { good: bool, s: str }

fn bad() -> Rendered { ret Rendered { good: false, s: "" } }

fn ok_text(s: str) -> Rendered { ret Rendered { good: true, s: s } }

fn join(a: *mem.Arena, items: []const str, sep: str) -> str {
    var out = ""
    var i = 0usize
    while i < items.len {
        if i > 0usize { out = cat(a, out, sep) }
        out = cat(a, out, items[i])
        i += 1usize
    }
    ret out
}

type Iter = struct { has: bool, name: str }

fn no_iter() -> Iter { ret Iter { has: false, name: "" } }

// An object key as text: a bare identifier or a string; absent for any other expression.
fn key_text(k: hcl.Key) -> (str, bool) {
    if k.identifier { ret (k.name, true) }
    if k.expr.len == 1usize && k.expr[0].kind == .String { ret (k.expr[0].text, true) }
    ret ("", false)
}

fn binary_spelling(op: str) -> str { ret op }

fn render_expr(r: *Run, e: hcl.Expr, ctx: str, it: Iter) -> Rendered {
    switch e.kind {
    case .Null:
        ret ok_text("null")
    case .Bool:
        if e.flag { ret ok_text("true") }
        ret ok_text("false")
    case .Number:
        ret ok_text(render_number(r.a, e.text))
    case .String:
        ret ok_text(quote_pcl(r.a, e.text))
    case .Variable:
        ret ok_text(e.text)
    case .Array:
        let (made, me) = list.init[str](r.a, 4usize)
        if me != ok { ret bad() }
        var out = made
        var i = 0usize
        while i < e.items.len {
            let v = render_expr(r, e.items[i], ctx, it)
            if !v.good { ret bad() }
            let pushed = list.push[str](&out, v.s)
            i += 1usize
        }
        ret ok_text(cat3(r.a, "[", join(r.a, list.slice_const[str](&out), ", "), "]"))
    case .Object:
        let (made, me) = list.init[str](r.a, 4usize)
        if me != ok { ret bad() }
        var out = made
        var i = 0usize
        while i < e.items.len {
            let (k, k_ok) = key_text(e.keys[i])
            if !k_ok { ret bad() }
            let v = render_expr(r, e.items[i], ctx, it)
            if !v.good { ret bad() }
            let pushed = list.push[str](&out, cat3(r.a, k, " = ", v.s))
            i += 1usize
        }
        ret ok_text(cat3(r.a, "{", join(r.a, list.slice_const[str](&out), ", "), "}"))
    case .Parens:
        let inner = render_expr(r, e.items[0], ctx, it)
        if !inner.good { ret bad() }
        ret ok_text(cat3(r.a, "(", inner.s, ")"))
    case .Traversal:
        ret render_traversal(r, e, ctx, it)
    case .FuncCall:
        if e.names.len > 0usize {
            warn(r, cat4(r.a, ctx, ": namespaced function '", e.text, "' not translated"))
            ret bad()
        }
        let (made, me) = list.init[str](r.a, 4usize)
        if me != ok { ret bad() }
        var out = made
        var i = 0usize
        while i < e.items.len {
            let v = render_expr(r, e.items[i], ctx, it)
            if !v.good { ret bad() }
            let pushed = list.push[str](&out, v.s)
            i += 1usize
        }
        ret ok_text(cat3(r.a, e.text, "(", cat(r.a, join(r.a, list.slice_const[str](&out), ", "), ")")))
    case .Conditional:
        let c = render_expr(r, e.items[0], ctx, it)
        if !c.good { ret bad() }
        let t = render_expr(r, e.items[1], ctx, it)
        if !t.good { ret bad() }
        let f = render_expr(r, e.items[2], ctx, it)
        if !f.good { ret bad() }
        ret ok_text(cat(r.a, cat(r.a, cat3(r.a, c.s, " ? ", t.s), " : "), f.s))
    case .Unary:
        let inner = render_expr(r, e.items[0], ctx, it)
        if !inner.good { ret bad() }
        ret ok_text(cat(r.a, e.text, inner.s))
    case .Binary:
        let l = render_expr(r, e.items[0], ctx, it)
        if !l.good { ret bad() }
        let rr = render_expr(r, e.items[1], ctx, it)
        if !rr.good { ret bad() }
        ret ok_text(cat(r.a, cat3(r.a, l.s, " ", e.text), cat(r.a, " ", rr.s)))
    default:
        warn(r, cat(r.a, ctx, ": expression too complex to translate, skipped"))
        ret bad()
    }
}

fn render_traversal(r: *Run, t: hcl.Expr, ctx: str, it: Iter) -> Rendered {
    let root_expr = t.items[0]
    if root_expr.kind != .Variable {
        warn(r, cat(r.a, ctx, ": unsupported reference, skipped"))
        ret bad()
    }
    let root = root_expr.text
    let (made, me) = list.init[str](r.a, 4usize)
    if me != ok { ret bad() }
    var parts = made
    var index_suffix = ""
    var i = 0usize
    while i < t.ops.len {
        let op = t.ops[i]
        if op.kind == .GetAttr && index_suffix.len == 0usize {
            let pushed = list.push[str](&parts, op.name)
        } else if op.kind == .LegacyIndex {
            index_suffix = cat(r.a, index_suffix, cat3(r.a, "[", op.name, "]"))
        } else if op.kind == .Index {
            let rendered = render_expr(r, op.index[0], ctx, it)
            if !rendered.good { ret bad() }
            index_suffix = cat(r.a, index_suffix, cat3(r.a, "[", rendered.s, "]"))
        } else {
            warn(r, cat(r.a, ctx, ": complex reference (splat/post-index attr) skipped"))
            ret bad()
        }
        i += 1usize
    }
    let ps = list.slice_const[str](&parts)
    if it.has && str.eq(root, it.name) {
        if ps.len > 0usize && str.eq(ps[0], "value") {
            if ps.len == 1usize { ret ok_text(it.name) }
            ret ok_text(cat3(r.a, it.name, ".", join(r.a, ps[1usize..], ".")))
        }
        warn(r, cat4(r.a, ctx, ": dynamic iterator '", it.name, ".key' not supported, skipped"))
        ret bad()
    }
    if str.eq(root, "var") && ps.len > 0usize { ret ok_text(cat3(r.a, "vars.", join(r.a, ps, "."), index_suffix)) }
    if str.eq(root, "local") && ps.len > 0usize { ret ok_text(cat3(r.a, "local.", join(r.a, ps, "."), index_suffix)) }
    if str.eq(root, "count") && ps.len > 0usize { ret ok_text(cat3(r.a, "count.", join(r.a, ps, "."), index_suffix)) }
    if str.eq(root, "each") && ps.len > 0usize { ret ok_text(cat3(r.a, "each.", join(r.a, ps, "."), index_suffix)) }
    if str.eq(root, "data") && ps.len >= 3usize { ret ok_text(cat(r.a, cat4(r.a, "data.", ps[1], ".", join(r.a, ps[2usize..], ".")), index_suffix)) }
    if str.eq(root, "module") || str.eq(root, "self") || str.eq(root, "path") || str.eq(root, "terraform") {
        warn(r, cat(r.a, cat4(r.a, ctx, ": '", root, ".*' reference not translatable, skipped"), ""))
        ret bad()
    }
    if ps.len >= 2usize { ret ok_text(cat(r.a, cat4(r.a, "resources.", ps[0], ".", join(r.a, ps[1usize..], ".")), index_suffix)) }
    warn(r, cat(r.a, cat4(r.a, ctx, ": reference '", root, ".*' too short to map, skipped"), ""))
    ret bad()
}

fn dollar(a: *mem.Arena, inner: str) -> yaml.Value { ret text(cat3(a, "${", inner, "}")) }

fn template_to_value(r: *Run, e: hcl.Expr, ctx: str, it: Iter) -> Opt {
    var out = ""
    var i = 0usize
    while i < e.parts.len {
        let part = e.parts[i]
        if part.kind == .Literal {
            out = cat(r.a, out, part.text)
        } else if part.kind == .Interpolation {
            let rendered = render_expr(r, part.expr[0], ctx, it)
            if !rendered.good { ret none() }
            out = cat(r.a, out, cat3(r.a, "${", rendered.s, "}"))
        } else {
            warn(r, cat(r.a, ctx, ": template directive (%{...}) not translated, skipped"))
            ret none()
        }
        i += 1usize
    }
    ret some(text(out))
}

fn expr_to_value_iter(r: *Run, e: hcl.Expr, ctx: str, it: Iter) -> Opt {
    switch e.kind {
    case .Null:
        ret some(.Null)
    case .Bool:
        ret some(yaml.Value{ Bool: e.flag })
    case .Number:
        ret some(number_to_value(r.a, e.text))
    case .String:
        ret some(text(e.text))
    case .Array:
        let (made, me) = list.init[yaml.Value](r.a, 4usize)
        if me != ok { ret none() }
        var seq = made
        var i = 0usize
        while i < e.items.len {
            let v = expr_to_value_iter(r, e.items[i], ctx, it)
            if v.has {
                let pushed = list.push[yaml.Value](&seq, v.v)
            }
            i += 1usize
        }
        ret some(yaml.Value{ Sequence: list.slice_const[yaml.Value](&seq) })
    case .Object:
        var m = new_map(r.a)
        var i = 0usize
        while i < e.items.len {
            let (k, k_ok) = key_text(e.keys[i])
            if !k_ok {
                warn(r, cat(r.a, ctx, ": non-string object key skipped"))
            } else {
                let v = expr_to_value_iter(r, e.items[i], ctx, it)
                if v.has { insert(&m, k, v.v) }
            }
            i += 1usize
        }
        ret some(map_value(&m))
    case .Template:
        ret template_to_value(r, e, ctx, it)
    default:
        let rendered = render_expr(r, e, ctx, it)
        if !rendered.good { ret none() }
        ret some(dollar(r.a, rendered.s))
    }
}

fn expr_to_value(r: *Run, e: hcl.Expr, ctx: str) -> Opt { ret expr_to_value_iter(r, e, ctx, no_iter()) }

fn str_of(v: yaml.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

// --- the blocks ---------------------------------------------------------------------------------------------------------

fn map_type(t: str) -> (str, bool) {
    if str.eq(t, "aws_s3_bucket") { ret ("aws.s3", true) }
    if str.eq(t, "aws_vpc") { ret ("aws.vpc", true) }
    if str.eq(t, "aws_subnet") { ret ("aws.subnet", true) }
    if str.eq(t, "aws_internet_gateway") { ret ("aws.internet_gateway", true) }
    if str.eq(t, "aws_route_table") { ret ("aws.route_table", true) }
    if str.eq(t, "aws_security_group") { ret ("aws.security_group", true) }
    if str.eq(t, "aws_instance") { ret ("aws.ec2_instance", true) }
    if str.eq(t, "aws_eip") { ret ("aws.elastic_ip", true) }
    if str.eq(t, "aws_ebs_volume") { ret ("aws.ebs_volume", true) }
    if str.eq(t, "aws_iam_role") { ret ("aws.iam_role", true) }
    ret ("", false)
}

fn depends_on_to_value(r: *Run, e: hcl.Expr, ctx: str) -> Opt {
    if e.kind != .Array {
        warn(r, cat(r.a, ctx, ": depends_on must be a list, skipped"))
        ret none()
    }
    let (made, me) = list.init[yaml.Value](r.a, 4usize)
    if me != ok { ret none() }
    var out = made
    var i = 0usize
    while i < e.items.len {
        let item = e.items[i]
        var handled = false
        if item.kind == .Traversal && item.ops.len > 0usize {
            if item.ops[0].kind == .GetAttr {
                let pushed = list.push[yaml.Value](&out, text(item.ops[0].name))
                handled = true
            }
        }
        if !handled { warn(r, cat(r.a, ctx, ": depends_on entry not a resource reference, skipped")) }
        i += 1usize
    }
    ret some(yaml.Value{ Sequence: list.slice_const[yaml.Value](&out) })
}

fn ignore_changes_to_value(r: *Run, e: hcl.Expr, ctx: str) -> Opt {
    if e.kind != .Array {
        warn(r, cat(r.a, ctx, ": ignore_changes must be a list or 'all', skipped"))
        ret none()
    }
    let (made, me) = list.init[yaml.Value](r.a, 4usize)
    if me != ok { ret none() }
    var out = made
    var i = 0usize
    while i < e.items.len {
        let item = e.items[i]
        if item.kind == .String {
            let pushed = list.push[yaml.Value](&out, text(item.text))
        } else if item.kind == .Variable {
            let pushed = list.push[yaml.Value](&out, text(item.text))
        } else if item.kind == .Traversal {
            let root = item.items[0]
            if root.kind == .Variable && item.ops.len == 0usize {
                let pushed = list.push[yaml.Value](&out, text(root.text))
            } else if item.ops.len > 0usize && item.ops[item.ops.len - 1usize].kind == .GetAttr {
                let pushed = list.push[yaml.Value](&out, text(item.ops[item.ops.len - 1usize].name))
            }
        } else {
            warn(r, cat(r.a, ctx, ": ignore_changes entry skipped"))
        }
        i += 1usize
    }
    ret some(yaml.Value{ Sequence: list.slice_const[yaml.Value](&out) })
}

fn tf_type_to_vartype(e: hcl.Expr) -> str {
    if e.kind == .Variable {
        if str.eq(e.text, "string") || str.eq(e.text, "number") || str.eq(e.text, "bool") { ret e.text }
        ret "any"
    }
    if e.kind == .FuncCall {
        if str.eq(e.text, "list") || str.eq(e.text, "set") || str.eq(e.text, "tuple") { ret "list" }
        if str.eq(e.text, "map") || str.eq(e.text, "object") { ret "map" }
        ret "any"
    }
    ret "any"
}

// `dynamic "NAME" { for_each = COLL  content { ... } }` as a list attribute built with a for-expression.
fn migrate_dynamic(r: *Run, nb: hcl.Item, res_name: str) -> (str, yaml.Value, bool) {
    if nb.labels.len == 0usize {
        warn(r, cat3(r.a, "resource '", res_name, "': dynamic block without a name, skipped"))
        ret ("", .Null, false)
    }
    let attr = nb.labels[0]
    let ctx = cat4(r.a, res_name, ".dynamic.", attr, "")
    var has_for_each = false
    var for_each = hcl.Expr { kind: .Null, text: "", flag: false, items: zero, keys: zero, ops: zero, parts: zero, names: zero }
    var has_content = false
    var content: []const hcl.Item = zero
    var iter_name = attr
    var i = 0usize
    while i < nb.body.len {
        let s = nb.body[i]
        if !s.is_block && str.eq(s.name, "for_each") {
            for_each = s.value[0]
            has_for_each = true
        } else if !s.is_block && str.eq(s.name, "iterator") {
            if s.value[0].kind == .Variable { iter_name = s.value[0].text }
        } else if !s.is_block {
            warn(r, cat4(r.a, ctx, ": attribute '", s.name, "' ignored"))
        } else if str.eq(s.name, "content") {
            content = s.body
            has_content = true
        } else {
            warn(r, cat4(r.a, ctx, ": nested block '", s.name, "' ignored"))
        }
        i += 1usize
    }
    if !has_for_each {
        warn(r, cat(r.a, ctx, ": missing for_each, skipped"))
        ret ("", .Null, false)
    }
    if !has_content {
        warn(r, cat(r.a, ctx, ": missing content block, skipped"))
        ret ("", .Null, false)
    }
    let coll = render_expr(r, for_each, ctx, no_iter())
    if !coll.good { ret ("", .Null, false) }
    let (made, me) = list.init[str](r.a, 4usize)
    if me != ok { ret ("", .Null, false) }
    var entries = made
    var k = 0usize
    while k < content.len {
        let s = content[k]
        if !s.is_block {
            let v = render_expr(r, s.value[0], ctx, Iter { has: true, name: iter_name })
            if !v.good { ret ("", .Null, false) }
            let pushed = list.push[str](&entries, cat3(r.a, s.name, " = ", v.s))
        } else {
            warn(r, cat4(r.a, ctx, ": nested block '", s.name, "' inside content not translated"))
        }
        k += 1usize
    }
    let body = cat3(r.a, "{", join(r.a, list.slice_const[str](&entries), ", "), "}")
    let expr = cat(r.a, cat4(r.a, "[for ", iter_name, " in ", coll.s), cat3(r.a, " : ", body, "]"))
    ret (attr, dollar(r.a, expr), true)
}

fn migrate_lifecycle(r: *Run, nb: hcl.Item, res_name: str, body_map: *Map, sec: *Sections) {
    var lc = new_map(r.a)
    var i = 0usize
    while i < nb.body.len {
        let s = nb.body[i]
        if s.is_block {
            warn(r, cat3(r.a, "resource '", res_name, "': lifecycle nested block skipped"))
        } else {
            let ctx = cat4(r.a, res_name, ".lifecycle.", s.name, "")
            let e = s.value[0]
            if str.eq(s.name, "ignore_changes") {
                if e.kind == .Variable && str.eq(e.text, "all") {
                    insert(&lc, "ignore_changes", text("all"))
                } else {
                    let v = ignore_changes_to_value(r, e, ctx)
                    if v.has { insert(&lc, "ignore_changes", v.v) }
                }
            } else if str.eq(s.name, "create_before_destroy") {
                let v = expr_to_value(r, e, ctx)
                if v.has { insert(&lc, "create_before_destroy", v.v) }
            } else if str.eq(s.name, "prevent_destroy") {
                if e.kind == .Bool && e.flag {
                    let pushed = list.push[yaml.Value](&sec.protected, text(res_name))
                    warn(r, cat3(r.a, "resource '", res_name, "': prevent_destroy → added to top-level protected:"))
                }
            } else {
                warn(r, cat4(r.a, res_name, ": lifecycle.", s.name, " not translated"))
            }
        }
        i += 1usize
    }
    if !is_empty(&lc) { insert(body_map, "lifecycle", map_value(&lc)) }
}

fn migrate_resource(r: *Run, b: hcl.Item, sec: *Sections) -> bool {
    if b.labels.len != 2usize {
        warn(r, "skipped malformed resource block (expected type + name)")
        ret false
    }
    let tf_type = b.labels[0]
    let name = b.labels[1]
    let (petcow_type, supported) = map_type(tf_type)
    if !supported {
        warn(r, cat(r.a, cat4(r.a, "resource '", tf_type, ".", name), "': type not supported, skipped"))
        ret false
    }
    var body_map = new_map(r.a)
    insert(&body_map, "type", text(petcow_type))
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block {
            let key = s.name
            let ctx = cat(r.a, cat4(r.a, tf_type, ".", name, "."), key)
            if str.eq(key, "count") || str.eq(key, "for_each") {
                let v = expr_to_value(r, s.value[0], ctx)
                if v.has { insert(&body_map, key, v.v) }
            } else if str.eq(key, "depends_on") {
                let v = depends_on_to_value(r, s.value[0], ctx)
                if v.has { insert(&body_map, "depends_on", v.v) }
            } else if str.eq(key, "provider") {
                warn(r, cat(r.a, ctx, ": TF 'provider' meta-arg not auto-translated — declare a providers: alias and set provider:"))
            } else {
                let v = expr_to_value(r, s.value[0], ctx)
                if v.has { insert(&body_map, key, v.v) }
            }
        } else if str.eq(s.name, "lifecycle") {
            migrate_lifecycle(r, s, name, &body_map, sec)
        } else if str.eq(s.name, "dynamic") {
            let (attr, value, good) = migrate_dynamic(r, s, name)
            if good { insert(&body_map, attr, value) }
        } else {
            warn(r, cat(r.a, cat4(r.a, "resource '", tf_type, ".", name), cat4(r.a, "': nested block '", s.name, "' not translated (declare it as a list attribute in PetCow)", "")))
        }
        i += 1usize
    }
    insert(&sec.resources, name, map_value(&body_map))
    ret true
}

fn migrate_variable(r: *Run, b: hcl.Item, sec: *Sections) {
    if b.labels.len == 0usize {
        warn(r, "skipped variable block without a name")
        ret
    }
    let name = b.labels[0]
    var decl = new_map(r.a)
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block {
            let key = s.name
            let ctx = cat4(r.a, "variable ", name, ".", key)
            if str.eq(key, "type") {
                insert(&decl, "type", text(tf_type_to_vartype(s.value[0])))
            } else if str.eq(key, "default") || str.eq(key, "description") || str.eq(key, "sensitive") {
                let v = expr_to_value(r, s.value[0], ctx)
                if v.has { insert(&decl, key, v.v) }
            } else {
                warn(r, cat4(r.a, "variable '", name, "': attribute '", cat(r.a, key, "' not translated")))
            }
        } else {
            warn(r, cat(r.a, cat4(r.a, "variable '", name, "': '", s.name), "' block not translated (PetCow validation uses ${...} conditions)"))
        }
        i += 1usize
    }
    insert(&sec.variables, name, map_value(&decl))
}

fn migrate_locals(r: *Run, b: hcl.Item, sec: *Sections) {
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block {
            let ctx = cat(r.a, "local.", s.name)
            let v = expr_to_value(r, s.value[0], ctx)
            if v.has { insert(&sec.locals, s.name, v.v) }
        } else {
            warn(r, cat3(r.a, "locals: nested block '", s.name, "' skipped"))
        }
        i += 1usize
    }
}

fn migrate_output(r: *Run, b: hcl.Item, sec: *Sections) {
    if b.labels.len != 1usize {
        warn(r, "skipped malformed output block (expected a name)")
        ret
    }
    let name = b.labels[0]
    let ctx = cat(r.a, "output.", name)
    var value = none()
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block {
            if str.eq(s.name, "value") {
                value = expr_to_value(r, s.value[0], ctx)
            } else if str.eq(s.name, "sensitive") {
                warn(r, cat3(r.a, "output '", name, "': `sensitive` dropped — PetCow auto-derives output sensitivity from value taint"))
            } else if str.eq(s.name, "description") || str.eq(s.name, "depends_on") {
                i = i
            } else {
                warn(r, cat4(r.a, "output '", name, "': attribute '", cat(r.a, s.name, "' skipped")))
            }
        } else {
            warn(r, cat4(r.a, "output '", name, "': nested block '", cat(r.a, s.name, "' skipped")))
        }
        i += 1usize
    }
    if value.has {
        insert(&sec.outputs, name, value.v)
    } else {
        warn(r, cat3(r.a, "output '", name, "': no `value` attribute — skipped"))
    }
}

fn str_attr(r: *Run, e: hcl.Expr, ctx: str) -> (str, bool) {
    let v = expr_to_value(r, e, ctx)
    if !v.has { ret ("", false) }
    let (r0, r1) = str_of(v.v)
    ret (r0, r1)
}

fn migrate_provider(r: *Run, b: hcl.Item, sec: *Sections) {
    if b.labels.len != 1usize {
        warn(r, "skipped malformed provider block (expected a name)")
        ret
    }
    let tf_name = b.labels[0]
    var cloud = ""
    if str.eq(tf_name, "aws") {
        cloud = "aws"
    } else if str.eq(tf_name, "google") {
        cloud = "gcp"
    } else if str.eq(tf_name, "azurerm") {
        cloud = "azure"
    } else {
        warn(r, cat3(r.a, "provider '", tf_name, "': no PetCow cloud mapping — skipped"))
        ret
    }
    let ctx = cat(r.a, "provider.", tf_name)
    var alias = ""
    var has_alias = false
    var region = ""
    var has_region = false
    var profile = ""
    var has_profile = false
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block {
            if str.eq(s.name, "alias") {
                let (v, good) = str_attr(r, s.value[0], ctx)
                has_alias = good
                alias = v
            } else if str.eq(s.name, "region") {
                let (v, good) = str_attr(r, s.value[0], ctx)
                has_region = good
                region = v
            } else if str.eq(s.name, "profile") {
                let (v, good) = str_attr(r, s.value[0], ctx)
                has_profile = good
                profile = v
            } else {
                warn(r, cat4(r.a, "provider '", tf_name, "': attribute '", cat(r.a, s.name, "' skipped")))
            }
        }
        i += 1usize
    }
    if !has_alias {
        warn(r, cat3(r.a, "provider '", tf_name, "': default (no `alias`) — PetCow takes the default region/credentials from the environment; only aliased providers map to `providers:`"))
        ret
    }
    var cfg = new_map(r.a)
    insert(&cfg, "cloud", text(cloud))
    if has_region { insert(&cfg, "region", text(region)) }
    if has_profile { insert(&cfg, "profile", text(profile)) }
    insert(&sec.providers, alias, map_value(&cfg))
}

fn looks_like_git(s: str) -> bool {
    if str.starts_with(s, "git::") || str.starts_with(s, "github.com/") || str.starts_with(s, "git@") { ret true }
    ret str.contains(s, "://") && (str.contains(s, ".git") || str.contains(s, "//") || str.contains(s, "?ref="))
}

fn migrate_module(r: *Run, b: hcl.Item, sec: *Sections) {
    if b.labels.len != 1usize {
        warn(r, "skipped malformed module block (expected a name)")
        ret
    }
    let name = b.labels[0]
    let ctx = cat(r.a, "module.", name)
    var entry = new_map(r.a)
    var inputs = new_map(r.a)
    var source = ""
    var has_source = false
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block {
            if str.eq(s.name, "source") {
                let (v, good) = str_attr(r, s.value[0], ctx)
                has_source = good
                source = v
            } else if str.eq(s.name, "version") {
                warn(r, cat3(r.a, "module '", name, "': `version` dropped — PetCow modules are local files, not registry-versioned"))
            } else if str.eq(s.name, "count") || str.eq(s.name, "for_each") {
                let v = expr_to_value(r, s.value[0], ctx)
                if v.has { insert(&entry, s.name, v.v) }
            } else if str.eq(s.name, "providers") || str.eq(s.name, "depends_on") {
                warn(r, cat4(r.a, "module '", name, "': `", cat(r.a, s.name, "` skipped")))
            } else {
                let v = expr_to_value(r, s.value[0], ctx)
                if v.has { insert(&inputs, s.name, v.v) }
            }
        } else {
            warn(r, cat4(r.a, "module '", name, "': nested block '", cat(r.a, s.name, "' skipped")))
        }
        i += 1usize
    }
    if !has_source {
        warn(r, cat3(r.a, "module '", name, "': no `source` — skipped"))
        ret
    }
    let src = str.trim(source)
    if looks_like_git(src) {
        warn(r, cat(r.a, cat4(r.a, "module '", name, "': git source '", source), "' carried over — point its `//<path>` at the migrated `.petcow.yaml` (a Terraform module is a dir of .tf)"))
        insert(&entry, "source", text(source))
    } else if str.starts_with(src, "./") || str.starts_with(src, "../") || str.starts_with(src, "/") {
        warn(r, cat(r.a, cat4(r.a, "module '", name, "': source '", source), "' points at Terraform files — migrate that module to a `.petcow.yaml` and update the path"))
        insert(&entry, "source", text(source))
    } else {
        warn(r, cat(r.a, cat4(r.a, "module '", name, "': Terraform registry source '", source), "' has no PetCow equivalent — use a `git::`/`github.com/…//<path>` source pointing at a `.petcow.yaml`"))
        ret
    }
    insert(&entry, "inputs", map_value(&inputs))
    insert(&sec.modules, name, map_value(&entry))
}

fn migrate_data(r: *Run, b: hcl.Item, sec: *Sections) -> bool {
    if b.labels.len != 2usize {
        warn(r, "skipped malformed data block (expected type + name)")
        ret false
    }
    let tf_type = b.labels[0]
    let name = b.labels[1]
    let (petcow_type, supported) = map_type(tf_type)
    if !supported {
        warn(r, cat(r.a, cat4(r.a, "data '", tf_type, ".", name), "': type not supported, skipped"))
        ret false
    }
    var lookup = ""
    var has_lookup = false
    var i = 0usize
    while i < b.body.len {
        let s = b.body[i]
        if !s.is_block && str.eq(s.name, "name") && s.value[0].kind == .String {
            lookup = s.value[0].text
            has_lookup = true
        }
        i += 1usize
    }
    var m = new_map(r.a)
    insert(&m, "type", text(petcow_type))
    if has_lookup {
        insert(&m, "name", text(lookup))
    } else {
        insert(&m, "name", text("TODO-set-lookup-name"))
        warn(r, cat(r.a, cat4(r.a, "data '", tf_type, ".", name), "': TF uses filters; set the lookup `name:` manually"))
    }
    insert(&sec.data, name, map_value(&m))
    ret true
}

// Translate HCL source into a PetCow document: `{document, migrated, warnings}`; `Invalid` when the HCL does not parse.
fn migrate_hcl(a: *mem.Arena, source: str, project: str) -> (Migration, err) {
    let (items, parse_error) = hcl.parse(a, source)
    if parse_error != ok { ret (Migration { document: .Null, migrated: 0usize, warnings: zero }, parse_error) }
    let (ws, we) = list.init[str](a, 8usize)
    let (pr, pe) = list.init[yaml.Value](a, 4usize)
    if we != ok || pe != ok { ret (Migration { document: .Null, migrated: 0usize, warnings: zero }, Failed) }
    var run = Run { a: a, warnings: ws, migrated: 0usize }
    var sec = Sections { variables: new_map(a), locals: new_map(a), data: new_map(a), outputs: new_map(a), providers: new_map(a), modules: new_map(a), resources: new_map(a), protected: pr }
    var i = 0usize
    while i < items.len {
        let s = items[i]
        if !s.is_block {
            warn(&run, cat3(a, "skipped top-level attribute '", s.name, "'"))
        } else if str.eq(s.name, "resource") {
            if migrate_resource(&run, s, &sec) { run.migrated += 1usize }
        } else if str.eq(s.name, "variable") {
            migrate_variable(&run, s, &sec)
        } else if str.eq(s.name, "locals") {
            migrate_locals(&run, s, &sec)
        } else if str.eq(s.name, "data") {
            if migrate_data(&run, s, &sec) { run.migrated += 1usize }
        } else if str.eq(s.name, "output") {
            migrate_output(&run, s, &sec)
        } else if str.eq(s.name, "provider") {
            migrate_provider(&run, s, &sec)
        } else if str.eq(s.name, "module") {
            migrate_module(&run, s, &sec)
        } else {
            warn(&run, cat3(a, "skipped unsupported block '", s.name, "'"))
        }
        i += 1usize
    }
    var doc = new_map(a)
    insert(&doc, "project", text(project))
    if !is_empty(&sec.variables) { insert(&doc, "variables", map_value(&sec.variables)) }
    if !is_empty(&sec.locals) { insert(&doc, "locals", map_value(&sec.locals)) }
    if !is_empty(&sec.data) { insert(&doc, "data", map_value(&sec.data)) }
    if !is_empty(&sec.outputs) { insert(&doc, "outputs", map_value(&sec.outputs)) }
    if !is_empty(&sec.providers) { insert(&doc, "providers", map_value(&sec.providers)) }
    if !is_empty(&sec.modules) { insert(&doc, "modules", map_value(&sec.modules)) }
    if sec.protected.len > 0usize { insert(&doc, "protected", yaml.Value{ Sequence: list.slice_const[yaml.Value](&sec.protected) }) }
    insert(&doc, "resources", map_value(&sec.resources))
    ret (Migration { document: map_value(&doc), migrated: run.migrated, warnings: list.slice_const[str](&run.warnings) }, ok)
}
