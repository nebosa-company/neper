// Formula-to-SQL compilation and pushdown classification (L029), after appdor's `src/formula/sql-compiler.js` and
// `pushdown.js`. A formula's tree becomes a parameterized PostgreSQL expression: every literal is a `$N`
// placeholder and a value never reaches the text, so the result cannot carry an injection. The emissions follow
// the evaluator's rules rather than SQL's: a blank is a value (NULLIF/COALESCE at text boundaries), `=` is
// `IS NOT DISTINCT FROM` and case-folded for text, ordering puts a blank first (row comparison), `ROUND` is
// half-up, `MOD` takes the divisor's sign, a domain error is a NULL guard rather than an aborted statement, and an
// expression whose truth in boolean position cannot be decided from declared types is refused (`pushdown: none`)
// rather than guessed.
//
// `compile` answers `sql`, `params`, `pushdown` (full, partial or none), the value `type` and `oversize` (a
// fragment passed 32,768 characters and the compile was abandoned). `classify` answers full, partial or none for a
// formula without compiling it. Everything is a pure function of the formula text, the schema and the registry.
//
// Differences from appdor's: a field called like an Object.prototype member is an ordinary missing field, and a
// column name's length is counted in UTF-16 units as JavaScript counts it, so a fragment's size bound agrees.

use e.algo.formula as f
use e.mem
use e.str

fn text_index_max() -> str { ret "1073741823" }

fn fragment_max() -> usize { ret 32768usize }

fn max_regex_input() -> str { ret "100000" }

// The guards of EXP, as JavaScript prints the two doubles.
fn exp_max() -> str { ret "709.782712893384" }

fn exp_min() -> str { ret "-745.1332191019411" }

// --- the schema ---------------------------------------------------------------------------------------------------

// A column a formula may name: the field's display name, its declared type and its SQL column.
type Column = struct { name: str, field_type: str, column: str }

type Options = struct { double_quote_columns: bool }

// The result: `value_type` is `number`, `text`, `boolean`, `date`, `blank` or `unknown`.
type Compiled = struct { sql: str, params: []const f.Value, pushdown: str, value_type: str, oversize: bool }

// How much of a formula SQL can answer.
type Verdict = struct { classification: str, reason: str, has_reason: bool, unsupported: []const str, has_unsupported: bool }

fn in_list(s: str, list: []const str) -> bool {
    var i = 0usize
    while i < list.len {
        if str.eq(list[i], s) { ret true }
        i += 1usize
    }
    ret false
}

// The value type a field's SQL expression has, from its declared type.
fn value_type_of_field(a: *mem.Arena, field_type: str) -> str {
    let (numeric, e) = mem.alloc[str](a, 8usize)
    if e != ok { ret "text" }
    numeric[0usize] = "number"
    numeric[1usize] = "currency"
    numeric[2usize] = "percent"
    numeric[3usize] = "rating"
    numeric[4usize] = "duration"
    numeric[5usize] = "autonumber"
    numeric[6usize] = "count"
    numeric[7usize] = "rollup"
    if in_list(field_type, numeric[0usize..8usize]) { ret "number" }
    if str.eq(field_type, "checkbox") || str.eq(field_type, "boolean") || str.eq(field_type, "toggle") { ret "boolean" }
    if str.eq(field_type, "date") || str.eq(field_type, "datetime") || str.eq(field_type, "created_time") || str.eq(field_type, "modified_time") || str.eq(field_type, "timestamp") { ret "date" }
    ret "text"
}

// --- compiler state ---------------------------------------------------------------------------------------------

// What compiling a node yields. `vtype` is empty when the type is not stated (distinct from `unknown`); `node`
// travels with the fragment because one decision needs the source rather than the SQL.
type Part = struct { sql: str, pushdown: str, vtype: str, node: f.Node, has_node: bool }

type Comp = struct {
    a: *mem.Arena,
    reg: *const f.Registry,
    schema: []const Column,
    double_quote: bool,
    params: []f.Value,
    param_count: usize,
    failed: bool,
    oversize: bool,
}

fn typed(sql: str, pushdown: str, vtype: str) -> Part {
    ret Part { sql: sql, pushdown: pushdown, vtype: vtype, node: f.leaf(.Null), has_node: false }
}

fn none() -> Part { ret typed("", "none", "") }

fn param(c: *Comp, value: f.Value) -> str {
    if c.param_count < c.params.len { c.params[c.param_count] = value }
    c.param_count += 1usize
    ret f.join(c.a, "$", f.number_text(c.a, f64(c.param_count)))
}

fn col(c: *Comp, name: str) -> str {
    if !c.double_quote { ret name }
    var quotes = 0usize
    var i = 0usize
    while i < name.len {
        if name[i] == 34u8 { quotes += 1usize }
        i += 1usize
    }
    let (out, e) = mem.alloc[u8](c.a, name.len + quotes + 2usize)
    if e != ok { ret name }
    var n = 0usize
    out[n] = 34u8
    n += 1usize
    i = 0usize
    while i < name.len {
        if name[i] == 34u8 {
            out[n] = 34u8
            n += 1usize
        }
        out[n] = name[i]
        n += 1usize
        i += 1usize
    }
    out[n] = 34u8
    n += 1usize
    ret out[0usize..n]
}

// The text's length in UTF-16 units.
fn utf16_length(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let b = s[i]
        if (b & 192u8) != 128u8 { n += 1usize }
        if b >= 240u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn j(c: *Comp, x: str, y: str) -> str { ret f.join(c.a, x, y) }

fn j3(c: *Comp, x: str, y: str, z: str) -> str { ret f.join3(c.a, x, y, z) }

fn j4(c: *Comp, x: str, y: str, z: str, w: str) -> str { ret f.join(c.a, f.join3(c.a, x, y, z), w) }

fn j5(c: *Comp, x: str, y: str, z: str, w: str, v: str) -> str { ret f.join(c.a, f.join3(c.a, x, y, z), f.join(c.a, w, v)) }

// `NULLIF(sql, '')`: the engine's blank is null, undefined and the empty string alike.
fn blank_text(c: *Comp, sql: str) -> str { ret j3(c, "NULLIF(", sql, ", '')") }

// A text argument to a text function, where a blank is `''` rather than NULL.
fn text_arg(c: *Comp, sql: str) -> str { ret j3(c, "COALESCE(", sql, ", '')") }

// The SQL of an argument, `undefined` for one the call did not have (as the interpolation in appdor's gives).
fn at(args: []const Part, i: usize) -> str {
    if i < args.len { ret args[i].sql }
    ret "undefined"
}

// Whether `s` is `upper` in any ASCII case.
fn is_name(s: str, upper: str) -> bool { ret str.compare_ascii_fold(s, upper) == 0i32 }

// Whether a subtree can evaluate to an error value (which SQL has no spelling for).
fn ast_may_error(node: f.Node) -> bool {
    if node.kind == .Binary && (str.eq(node.op, "/") || str.eq(node.op, "%") || str.eq(node.op, "^")) { ret true }
    if node.kind == .Call {
        if is_name(node.s, "SQRT") || is_name(node.s, "LN") || is_name(node.s, "LOG") || is_name(node.s, "LOG10") || is_name(node.s, "ASIN") || is_name(node.s, "ACOS") || is_name(node.s, "POWER") || is_name(node.s, "POW") || is_name(node.s, "MOD") { ret true }
    }
    var i = 0usize
    while i < node.kids.len {
        if ast_may_error(node.kids[i]) { ret true }
        i += 1usize
    }
    ret false
}

// A name as the compiler matches it: upper case, underscores removed.
fn match_name(c: *Comp, s: str) -> str { ret f.normalize_name(c.a, s) }

// The test of a value in boolean position as `toBool` defines it per declared type, or false for "cannot decide".
fn bool_arg(c: *Comp, p: Part) -> (str, bool) {
    if p.has_node && ast_may_error(p.node) { ret ("", false) }
    if str.eq(p.vtype, "boolean") { ret (j3(c, "(", p.sql, " IS TRUE)"), true) }
    if str.eq(p.vtype, "number") { ret (j3(c, "(((", p.sql, ") <> 0) IS TRUE)"), true) }
    if str.eq(p.vtype, "text") { ret (j3(c, "((LOWER(BTRIM(", p.sql, ")) NOT IN ('', 'false', '0', 'no')) IS TRUE)"), true) }
    if str.eq(p.vtype, "date") { ret (j3(c, "(", p.sql, " IS NOT NULL)"), true) }
    if str.eq(p.vtype, "blank") { ret ("false", true) }
    ret ("", false)
}

fn is_text(p: Part) -> bool { ret str.eq(p.vtype, "text") || str.eq(p.vtype, "blank") }

fn equality(c: *Comp, left: Part, right: Part, negated: bool) -> str {
    let both = is_text(left) && is_text(right)
    var l = left.sql
    var r = right.sql
    if both {
        l = j3(c, "LOWER(", blank_text(c, left.sql), ")")
        r = j3(c, "LOWER(", blank_text(c, right.sql), ")")
    }
    var word = " IS NOT DISTINCT FROM "
    if negated { word = " IS DISTINCT FROM " }
    ret j5(c, "(", l, word, r, ")")
}

fn ordering(c: *Comp, op: str, left: Part, right: Part) -> str {
    let both = is_text(left) && is_text(right)
    var l = left.sql
    var r = right.sql
    if both {
        l = blank_text(c, left.sql)
        r = blank_text(c, right.sql)
    }
    var equal_answer = "false"
    if str.eq(op, "<=") || str.eq(op, ">=") { equal_answer = "true" }
    let left_row = j5(c, "ROW(", l, " IS NOT NULL, ", l, ")")
    let right_row = j5(c, "ROW(", r, " IS NOT NULL, ", r, ")")
    ret j5(c, "COALESCE((", left_row, j3(c, " ", op, " "), right_row, j3(c, "), ", equal_answer, ")"))
}

// `POWER`, which raises on a negative base with a fractional exponent: the guard answers NULL as the engine's
// `#VALUE!` reconciles to.
fn power(c: *Comp, base: str, exponent: str) -> str {
    let head = j5(c, "CASE WHEN ", base, " < 0 AND ", exponent, " <> TRUNC(")
    ret j5(c, head, exponent, ") THEN NULL ELSE POWER(", base, j3(c, ", ", exponent, ") END"))
}

// --- nodes --------------------------------------------------------------------------------------------------------

fn find_field(c: *Comp, name: str) -> (usize, bool) {
    var i = 0usize
    while i < c.schema.len {
        if str.eq(c.schema[i].name, name) { ret (i, true) }
        i += 1usize
    }
    let want = f.lower_text(c.a, name)
    i = 0usize
    while i < c.schema.len {
        if str.eq(f.lower_text(c.a, c.schema[i].name), want) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn field_part(c: *Comp, name: str) -> (Part, bool) {
    let (at_index, found) = find_field(c, name)
    if !found { ret (none(), false) }
    let def = c.schema[at_index]
    ret (typed(col(c, def.column), "full", value_type_of_field(c.a, def.field_type)), true)
}

fn compile(c: *Comp, node: f.Node) -> Part {
    if c.failed { ret none() }
    var out = compile_node(c, node)
    if !out.has_node {
        out.node = node
        out.has_node = true
    }
    if utf16_length(out.sql) > fragment_max() {
        c.failed = true
        c.oversize = true
        ret none()
    }
    ret out
}

fn compile_node(c: *Comp, node: f.Node) -> Part {
    if node.kind == .Number {
        let p = param(c, f.number(node.n))
        ret typed(j3(c, "(", p, ")::double precision"), "full", "number")
    }
    if node.kind == .String { ret typed(param(c, f.text(node.s)), "full", "text") }
    if node.kind == .Bool { ret typed(param(c, f.boolean(node.b)), "full", "boolean") }
    if node.kind == .Null { ret typed("NULL", "full", "blank") }
    if node.kind == .Field {
        let (p, found) = field_part(c, node.s)
        ret p
    }
    if node.kind == .Unary { ret compile_unary(c, node) }
    if node.kind == .Binary { ret compile_binary(c, node) }
    if node.kind == .Ternary { ret compile_ternary(c, node) }
    if node.kind == .Call { ret compile_call(c, node) }
    if node.kind == .Array { ret none() }
    if node.kind == .Name { ret compile_name(c, node) }
    ret none()
}

fn compile_name(c: *Comp, node: f.Node) -> Part {
    let (index, known) = f.resolve(c.a, c.reg, node.s)
    if known {
        let entry = f.entry_at(c.reg, index)
        if entry.min_args <= 0i32 {
            var no_args: []Part = zero
            ret compile_function(c, entry, no_args)
        }
    }
    let (p, found) = field_part(c, node.s)
    if found { ret p }
    ret none()
}

fn compile_unary(c: *Comp, node: f.Node) -> Part {
    let operand = compile(c, node.kids[0usize])
    if str.eq(operand.pushdown, "none") { ret none() }
    if str.eq(node.op, "-") { ret typed(j3(c, "(-", operand.sql, ")"), operand.pushdown, "number") }
    if str.eq(node.op, "+") { ret typed(j3(c, "(+", operand.sql, ")"), operand.pushdown, "number") }
    if str.eq(node.op, "!") {
        let (test, good) = bool_arg(c, operand)
        if !good { ret none() }
        ret typed(j3(c, "(NOT ", test, ")"), operand.pushdown, "boolean")
    }
    ret none()
}

fn compile_binary(c: *Comp, node: f.Node) -> Part {
    let op = node.op
    if str.eq(op, "||") || str.eq(op, "&&") {
        let left = compile(c, node.kids[0usize])
        let right = compile(c, node.kids[1usize])
        if str.eq(left.pushdown, "none") && str.eq(right.pushdown, "none") { ret none() }
        var word = " AND "
        if str.eq(op, "||") { word = " OR " }
        var combined = ""
        var count = 0usize
        if !str.eq(left.pushdown, "none") {
            let (t, good) = bool_arg(c, left)
            if !good { ret none() }
            combined = j3(c, "(", t, ")")
            count += 1usize
        }
        if !str.eq(right.pushdown, "none") {
            let (t, good) = bool_arg(c, right)
            if !good { ret none() }
            if count > 0usize { combined = j(c, combined, word) }
            combined = j(c, combined, j3(c, "(", t, ")"))
            count += 1usize
        }
        var push = "partial"
        if str.eq(left.pushdown, "full") && str.eq(right.pushdown, "full") { push = "full" }
        ret typed(combined, push, "boolean")
    }
    let left = compile(c, node.kids[0usize])
    let right = compile(c, node.kids[1usize])
    if str.eq(left.pushdown, "none") || str.eq(right.pushdown, "none") { ret none() }
    if str.eq(op, "+") || str.eq(op, "-") || str.eq(op, "*") {
        ret typed(j5(c, "(", left.sql, j3(c, " ", op, " "), right.sql, ")"), "full", "number")
    }
    if str.eq(op, "/") { ret typed(j5(c, "(", left.sql, " / NULLIF(", right.sql, ", 0))"), "full", "number") }
    if str.eq(op, "%") {
        let l = j3(c, "MOD((", left.sql, ")::numeric, ")
        ret typed(j5(c, l, "NULLIF((", right.sql, ")::numeric, 0))::double precision", ""), "full", "number")
    }
    if str.eq(op, "^") { ret typed(power(c, left.sql, right.sql), "full", "number") }
    if str.eq(op, "&") {
        ret typed(j5(c, "CONCAT(", text_arg(c, left.sql), ", ", text_arg(c, right.sql), ")"), "full", "text")
    }
    if str.eq(op, "=") || str.eq(op, "==") { ret typed(equality(c, left, right, false), "full", "boolean") }
    if str.eq(op, "!=") || str.eq(op, "<>") { ret typed(equality(c, left, right, true), "full", "boolean") }
    if str.eq(op, "<") || str.eq(op, "<=") || str.eq(op, ">") || str.eq(op, ">=") {
        ret typed(ordering(c, op, left, right), "full", "boolean")
    }
    ret none()
}

fn compile_ternary(c: *Comp, node: f.Node) -> Part {
    let cond = compile(c, node.kids[0usize])
    let then_branch = compile(c, node.kids[1usize])
    let alt_branch = compile(c, node.kids[2usize])
    if str.eq(cond.pushdown, "none") || str.eq(then_branch.pushdown, "none") || str.eq(alt_branch.pushdown, "none") { ret none() }
    let (test, good) = bool_arg(c, cond)
    if !good { ret none() }
    var vtype = "unknown"
    if str.eq(then_branch.vtype, alt_branch.vtype) { vtype = then_branch.vtype }
    ret typed(j5(c, "CASE WHEN ", test, " THEN ", then_branch.sql, j3(c, " ELSE ", alt_branch.sql, " END")), "full", vtype)
}

// The unit of DATEADD or DATEDIF is syntax, not a value: it is read from the tree against an allow-list.
fn interval_unit(unit: str) -> (str, bool) {
    if str.eq(unit, "ms") || str.eq(unit, "millisecond") || str.eq(unit, "milliseconds") { ret ("millisecond", true) }
    if str.eq(unit, "s") || str.eq(unit, "sec") || str.eq(unit, "second") || str.eq(unit, "seconds") { ret ("second", true) }
    if str.eq(unit, "m") || str.eq(unit, "min") || str.eq(unit, "minute") || str.eq(unit, "minutes") { ret ("minute", true) }
    if str.eq(unit, "h") || str.eq(unit, "hour") || str.eq(unit, "hours") { ret ("hour", true) }
    if str.eq(unit, "d") || str.eq(unit, "day") || str.eq(unit, "days") { ret ("day", true) }
    if str.eq(unit, "w") || str.eq(unit, "week") || str.eq(unit, "weeks") { ret ("week", true) }
    if str.eq(unit, "mo") || str.eq(unit, "month") || str.eq(unit, "months") { ret ("month", true) }
    if str.eq(unit, "q") || str.eq(unit, "quarter") || str.eq(unit, "quarters") { ret ("quarter", true) }
    if str.eq(unit, "y") || str.eq(unit, "year") || str.eq(unit, "years") { ret ("year", true) }
    ret ("", false)
}

// A string literal's text, trimmed and lower-cased as JavaScript's `trim().toLowerCase()` does for ASCII.
fn unit_text(c: *Comp, node: f.Node) -> (str, bool) {
    if node.kind != .String { ret ("", false) }
    ret (f.lower_text(c.a, f.trim_text(node.s)), true)
}

fn try_date_add(c: *Comp, node: f.Node) -> (Part, bool) {
    if !str.eq(match_name(c, node.s), "DATEADD") { ret (none(), false) }
    if node.kids.len < 3usize { ret (none(), true) }
    let (text, is_text_node) = unit_text(c, node.kids[2usize])
    var unit = ""
    var known = false
    if is_text_node {
        let (u, k) = interval_unit(text)
        unit = u
        known = k
    }
    if !known { ret (none(), true) }
    let subject_part = compile(c, node.kids[0usize])
    if !str.eq(subject_part.pushdown, "full") { ret (none(), true) }
    let amount = compile(c, node.kids[1usize])
    if !str.eq(amount.pushdown, "full") { ret (none(), true) }
    let inner = j5(c, "(", amount.sql, " * INTERVAL '1 ", unit, "')")
    ret (typed(j5(c, "(", subject_part.sql, " + ", inner, ")"), "full", ""), true)
}

fn try_date_dif(c: *Comp, node: f.Node) -> (Part, bool) {
    if !str.eq(match_name(c, node.s), "DATEDIF") { ret (none(), false) }
    if node.kids.len < 3usize { ret (none(), true) }
    let (text, is_text_node) = unit_text(c, node.kids[2usize])
    if !is_text_node || !str.eq(text, "d") { ret (none(), true) }
    let from = compile(c, node.kids[0usize])
    if !str.eq(from.pushdown, "full") { ret (none(), true) }
    let to = compile(c, node.kids[1usize])
    if !str.eq(to.pushdown, "full") { ret (none(), true) }
    let diff = j5(c, "((", to.sql, ") - (", from.sql, "))")
    let days = j3(c, "TRUNC(EXTRACT(EPOCH FROM ", diff, ") / 86400)")
    let test = j5(c, "CASE WHEN (", to.sql, ") < (", from.sql, ") THEN NULL ELSE ")
    ret (typed(j3(c, test, days, " END"), "full", "number"), true)
}

fn compile_call(c: *Comp, node: f.Node) -> Part {
    let (added, is_add) = try_date_add(c, node)
    if is_add { ret added }
    let (dif, is_dif) = try_date_dif(c, node)
    if is_dif { ret dif }
    let (args, ae) = mem.alloc[Part](c.a, node.kids.len + 1usize)
    if ae != ok {
        c.failed = true
        ret none()
    }
    var any_none = false
    var i = 0usize
    while i < node.kids.len {
        args[i] = compile(c, node.kids[i])
        if str.eq(args[i].pushdown, "none") { any_none = true }
        i += 1usize
    }
    if any_none { ret none() }
    let list = args[0usize..node.kids.len]
    let (hard, is_hard) = try_hardcoded(c, node.s, list)
    if is_hard { ret hard }
    let (index, known) = f.resolve(c.a, c.reg, node.s)
    if !known { ret none() }
    let entry = f.entry_at(c.reg, index)
    if entry.volatile_fn { ret none() }
    ret compile_function(c, entry, list)
}

// Functions with a fixed SQL mapping whether or not the registry has them.
fn try_hardcoded(c: *Comp, raw: str, args: []const Part) -> (Part, bool) {
    let name = match_name(c, raw)
    if str.eq(name, "CONTAINS") {
        if args.len < 2usize { ret (none(), false) }
        let inner = j5(c, "(POSITION(", text_arg(c, args[1usize].sql), " IN ", text_arg(c, args[0usize].sql), ") > 0)")
        ret (typed(inner, "full", "boolean"), true)
    }
    if str.eq(name, "STARTSWITH") || str.eq(name, "ENDSWITH") {
        if args.len < 2usize { ret (none(), false) }
        let hay = j3(c, "LOWER(", text_arg(c, args[0usize].sql), ")")
        let needle = j3(c, "LOWER(", text_arg(c, args[1usize].sql), ")")
        var side = "LEFT("
        if str.eq(name, "ENDSWITH") { side = "RIGHT(" }
        ret (typed(j5(c, "(", side, hay, j5(c, ", LENGTH(", needle, ")) = ", needle, ")"), ""), "full", "boolean"), true)
    }
    if str.eq(name, "COALESCE") || str.eq(name, "NVL") {
        var joined = ""
        var i = 0usize
        while i < args.len {
            if i > 0usize { joined = j(c, joined, ", ") }
            joined = j(c, joined, args[i].sql)
            i += 1usize
        }
        ret (typed(j3(c, "COALESCE(", joined, ")"), "full", "unknown"), true)
    }
    if str.eq(name, "NULLIF") {
        if args.len < 2usize { ret (none(), false) }
        ret (typed(j5(c, "NULLIF(", args[0usize].sql, ", ", args[1usize].sql, ")"), "full", args[0usize].vtype), true)
    }
    if str.eq(name, "CEIL") { ret (typed(j3(c, "CEIL(", at(args, 0usize), ")"), "full", "number"), true) }
    ret (none(), false)
}

fn count_of(c: *Comp, args: []const Part, i: usize) -> str {
    let inner = j3(c, "GREATEST(COALESCE(", at(args, i), ", 0), 0)")
    ret j3(c, "LEAST(", inner, j3(c, ", ", text_index_max(), ")"))
}

fn clamped(c: *Comp, expr: str) -> str { ret j3(c, "LEAST(", expr, j3(c, ", ", text_index_max(), ")")) }

fn fn1(c: *Comp, name: str, args: []const Part, vtype: str) -> Part {
    ret typed(j4(c, name, "(", at(args, 0usize), ")"), "full", vtype)
}

fn extract(c: *Comp, field: str, args: []const Part) -> Part {
    ret typed(j5(c, "EXTRACT(", field, " FROM ", at(args, 0usize), ")"), "full", "number")
}

fn compile_function(c: *Comp, entry: *const f.Entry, args: []const Part) -> Part {
    let name = entry.name
    if str.eq(name, "IF") {
        if args.len < 3usize { ret none() }
        let (test, good) = bool_arg(c, args[0usize])
        if !good { ret none() }
        var vtype = "unknown"
        if str.eq(args[1usize].vtype, args[2usize].vtype) { vtype = args[1usize].vtype }
        ret typed(j5(c, "CASE WHEN ", test, " THEN ", args[1usize].sql, j3(c, " ELSE ", args[2usize].sql, " END")), "full", vtype)
    }
    if str.eq(name, "IFERROR") || str.eq(name, "IFNA") { ret none() }
    if str.eq(name, "IFBLANK") {
        if args.len < 2usize { ret none() }
        ret typed(j5(c, "COALESCE(", args[0usize].sql, ", ", args[1usize].sql, ")"), "full", args[1usize].vtype)
    }
    if str.eq(name, "AND") || str.eq(name, "OR") {
        var joined = ""
        var i = 0usize
        while i < args.len {
            let (t, good) = bool_arg(c, args[i])
            if !good { ret none() }
            if i > 0usize {
                if str.eq(name, "AND") { joined = j(c, joined, " AND ") } else { joined = j(c, joined, " OR ") }
            }
            joined = j(c, joined, t)
            i += 1usize
        }
        ret typed(j3(c, "(", joined, ")"), "full", "boolean")
    }
    if str.eq(name, "NOT") {
        if args.len == 0usize {
            // appdor's reads a missing argument and throws, which abandons the whole compile
            c.failed = true
            ret none()
        }
        let (t, good) = bool_arg(c, args[0usize])
        if !good { ret none() }
        ret typed(j3(c, "(NOT ", t, ")"), "full", "boolean")
    }
    if str.eq(name, "IFS") {
        if args.len < 2usize { ret none() }
        var i = 0usize
        while i + 1usize < args.len {
            let (t, good) = bool_arg(c, args[i])
            if !good { ret none() }
            i += 2usize
        }
        var out = "CASE "
        i = 0usize
        while i + 1usize < args.len {
            let (t, good) = bool_arg(c, args[i])
            out = j(c, out, j5(c, "WHEN ", t, " THEN ", args[i + 1usize].sql, " "))
            i += 2usize
        }
        if args.len % 2usize == 1usize { out = j(c, out, j3(c, "ELSE ", args[args.len - 1usize].sql, " ")) }
        ret typed(j(c, out, "END"), "full", "unknown")
    }
    if str.eq(name, "SWITCH") || str.eq(name, "CASE") {
        if args.len < 3usize { ret none() }
        let subject = args[0usize]
        let rest = args[1usize..args.len]
        let pairs = rest.len / 2usize
        var out = "CASE "
        var i = 0usize
        while i < pairs {
            out = j(c, out, j5(c, "WHEN ", equality(c, subject, rest[i * 2usize], false), " THEN ", rest[i * 2usize + 1usize].sql, " "))
            i += 1usize
        }
        if rest.len % 2usize == 1usize { out = j(c, out, j3(c, "ELSE ", rest[rest.len - 1usize].sql, " ")) }
        ret typed(j(c, out, "END"), "full", "unknown")
    }
    if str.eq(name, "ISBLANK") || str.eq(name, "ISEMPTY") {
        var arg_type = "unknown"
        var sql = "NULL"
        if args.len > 0usize {
            arg_type = args[0usize].vtype
            sql = args[0usize].sql
        }
        if str.eq(arg_type, "text") || str.eq(arg_type, "blank") {
            ret typed(j3(c, "(", blank_text(c, at(args, 0usize)), " IS NULL)"), "full", "boolean")
        }
        if str.eq(arg_type, "unknown") {
            ret typed(j5(c, "(", at(args, 0usize), " IS NULL OR (", at(args, 0usize), ")::text = '')"), "full", "boolean")
        }
        ret typed(j3(c, "(", at(args, 0usize), " IS NULL)"), "full", "boolean")
    }
    if str.eq(name, "ISNUMBER") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "(", a0, " IS NOT NULL AND ", a0, " ~ '^[+-]?[0-9]+\\.?[0-9]*$')"), "partial", "")
    }
    if str.eq(name, "ISTEXT") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "(", a0, " IS NOT NULL AND pg_typeof(", a0, ") IN ('text','varchar','character varying'))"), "partial", "")
    }
    if str.eq(name, "ISLOGICAL") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "(", a0, " IS NOT NULL AND pg_typeof(", a0, ") = 'boolean')"), "partial", "")
    }
    if str.eq(name, "ISDATE") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "(", a0, " IS NOT NULL AND pg_typeof(", a0, ") IN ('date','timestamp','timestamptz'))"), "partial", "")
    }
    if str.eq(name, "ISERROR") || str.eq(name, "ISERR") || str.eq(name, "ISNA") { ret none() }

    // --- math ---
    if str.eq(name, "ABS") { ret fn1(c, "ABS", args, "number") }
    if str.eq(name, "SIGN") { ret fn1(c, "SIGN", args, "number") }
    if str.eq(name, "ROUND") {
        if args.len < 2usize { ret typed(j3(c, "FLOOR((", at(args, 0usize), ") + 0.5)"), "full", "number") }
        let scale = j3(c, "POWER(10::numeric, (", at(args, 1usize), ")::numeric)")
        ret typed(j5(c, "(FLOOR((", at(args, 0usize), ") * ", scale, j3(c, " + 0.5) / ", scale, ")")), "full", "number")
    }
    if str.eq(name, "ROUNDUP") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "(SIGN(", a0, ") * CEIL(ABS(", a0, ")))"), "full", "number")
    }
    if str.eq(name, "ROUNDDOWN") { ret fn1(c, "TRUNC", args, "number") }
    if str.eq(name, "CEILING") { ret fn1(c, "CEIL", args, "number") }
    if str.eq(name, "FLOOR") { ret fn1(c, "FLOOR", args, "number") }
    if str.eq(name, "INT") { ret fn1(c, "FLOOR", args, "number") }
    if str.eq(name, "TRUNC") { ret fn1(c, "TRUNC", args, "number") }
    if str.eq(name, "SQRT") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "CASE WHEN (", a0, ") < 0 THEN NULL ELSE SQRT(", a0, ") END"), "full", "number")
    }
    if str.eq(name, "POWER") || str.eq(name, "POW") {
        if args.len < 2usize { ret none() }
        ret typed(power(c, args[0usize].sql, args[1usize].sql), "full", "number")
    }
    if str.eq(name, "MOD") {
        if args.len < 2usize { ret none() }
        let divisor = j3(c, "NULLIF((", args[1usize].sql, ")::numeric, 0)")
        let inner = j5(c, "MOD((", args[0usize].sql, ")::numeric, ", divisor, ")")
        ret typed(j5(c, "MOD(", inner, " + ", divisor, j3(c, ", ", divisor, ")::double precision")), "full", "number")
    }
    if str.eq(name, "EXP") {
        let a0 = at(args, 0usize)
        let first = j5(c, "CASE WHEN (", a0, ") > ", exp_max(), " THEN NULL")
        let second = j5(c, " WHEN (", a0, ") < ", exp_min(), " THEN 0::double precision")
        ret typed(j(c, j(c, first, second), j3(c, " ELSE EXP(", a0, ") END")), "full", "number")
    }
    if str.eq(name, "LN") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "CASE WHEN (", a0, ") <= 0 THEN NULL ELSE LN(", a0, ") END"), "full", "number")
    }
    if str.eq(name, "LOG") || str.eq(name, "LOG10") {
        let a0 = at(args, 0usize)
        ret typed(j5(c, "CASE WHEN (", a0, ") <= 0 THEN NULL ELSE LOG(", a0, ") END"), "full", "number")
    }
    if str.eq(name, "SIN") { ret fn1(c, "SIN", args, "number") }
    if str.eq(name, "COS") { ret fn1(c, "COS", args, "number") }
    if str.eq(name, "TAN") { ret fn1(c, "TAN", args, "number") }
    if str.eq(name, "ASIN") || str.eq(name, "ACOS") {
        let a0 = at(args, 0usize)
        let head = j5(c, "CASE WHEN (", a0, ") < -1 OR (", a0, ") > 1 THEN NULL ELSE ")
        ret typed(j5(c, head, name, "(", a0, ") END"), "full", "number")
    }
    if str.eq(name, "ATAN") { ret fn1(c, "ATAN", args, "number") }
    if str.eq(name, "PI") { ret typed("PI()", "full", "number") }
    if str.eq(name, "MIN") || str.eq(name, "MAX") {
        var fname = "GREATEST"
        if str.eq(name, "MIN") { fname = "LEAST" }
        var joined = ""
        var i = 0usize
        while i < args.len {
            if i > 0usize { joined = j(c, joined, ", ") }
            joined = j(c, joined, args[i].sql)
            i += 1usize
        }
        ret typed(j5(c, "COALESCE(", fname, "(", joined, "), 0)"), "full", "number")
    }

    // --- text ---
    if str.eq(name, "UPPER") || str.eq(name, "UPPERCASE") { ret typed(j3(c, "UPPER(", text_arg(c, at(args, 0usize)), ")"), "full", "text") }
    if str.eq(name, "LOWER") || str.eq(name, "LOWERCASE") { ret typed(j3(c, "LOWER(", text_arg(c, at(args, 0usize)), ")"), "full", "text") }
    if str.eq(name, "TRIM") { ret typed(j3(c, "TRIM(", text_arg(c, at(args, 0usize)), ")"), "full", "text") }
    if str.eq(name, "LTRIM") { ret typed(j3(c, "LTRIM(", text_arg(c, at(args, 0usize)), ")"), "full", "text") }
    if str.eq(name, "RTRIM") { ret typed(j3(c, "RTRIM(", text_arg(c, at(args, 0usize)), ")"), "full", "text") }
    if str.eq(name, "LEN") || str.eq(name, "LENGTH") { ret typed(j3(c, "LENGTH(", text_arg(c, at(args, 0usize)), ")"), "full", "number") }
    if str.eq(name, "LEFT") || str.eq(name, "RIGHT") {
        if args.len < 2usize { ret none() }
        ret typed(j5(c, name, "(", text_arg(c, at(args, 0usize)), ", ", j(c, count_of(c, args, 1usize), "::int)")), "full", "text")
    }
    if str.eq(name, "MID") || str.eq(name, "SUBSTRING") || str.eq(name, "SUBSTR") {
        if args.len < 2usize { ret none() }
        let inner = j3(c, "GREATEST(COALESCE(", at(args, 1usize), ", 1), 1)")
        let from = j(c, clamped(c, inner), "::int")
        if args.len == 2usize {
            ret typed(j5(c, "SUBSTRING(", text_arg(c, at(args, 0usize)), " FROM ", from, ")"), "full", "text")
        }
        ret typed(j5(c, "SUBSTRING(", text_arg(c, at(args, 0usize)), " FROM ", from, j3(c, " FOR ", j(c, count_of(c, args, 2usize), "::int"), ")")), "full", "text")
    }
    if str.eq(name, "REPLACE") {
        if args.len != 4usize { ret none() }
        let inner = j3(c, "GREATEST(TRUNC(COALESCE(", at(args, 1usize), ", 1)), 1)")
        let from = j(c, clamped(c, inner), "::int")
        let head = j5(c, "OVERLAY(", text_arg(c, at(args, 0usize)), " PLACING ", text_arg(c, at(args, 3usize)), " FROM ")
        ret typed(j5(c, head, from, " FOR ", j(c, count_of(c, args, 2usize), "::int"), ")"), "full", "text")
    }
    if str.eq(name, "SUBSTITUTE") {
        if args.len != 3usize { ret none() }
        ret typed(j5(c, "REPLACE(", text_arg(c, at(args, 0usize)), ", ", text_arg(c, at(args, 1usize)), j3(c, ", ", text_arg(c, at(args, 2usize)), ")")), "full", "text")
    }
    if str.eq(name, "REPT") || str.eq(name, "REPEAT") {
        if args.len < 2usize { ret none() }
        let t = text_arg(c, at(args, 0usize))
        let n = j3(c, "GREATEST(COALESCE(", at(args, 1usize), ", 0), 0)")
        let guard = j5(c, "CASE WHEN LENGTH(", t, ") * ", n, j3(c, " > ", max_regex_input(), " THEN NULL"))
        let body = j5(c, " ELSE REPEAT(", t, ", LEAST(", n, j3(c, ", ", max_regex_input(), ")::int) END"))
        ret typed(j(c, guard, body), "full", "text")
    }
    if str.eq(name, "CONCAT") || str.eq(name, "CONCATENATE") {
        var joined = ""
        var i = 0usize
        while i < args.len {
            if i > 0usize { joined = j(c, joined, ", ") }
            joined = j(c, joined, text_arg(c, args[i].sql))
            i += 1usize
        }
        ret typed(j3(c, "CONCAT(", joined, ")"), "full", "text")
    }
    if str.eq(name, "TEXT") || str.eq(name, "TOSTRING") || str.eq(name, "STRING") {
        ret typed(j3(c, "(", at(args, 0usize), ")::text"), "full", "text")
    }
    if str.eq(name, "FIND") || str.eq(name, "SEARCH") {
        if args.len != 2usize { ret none() }
        var needle = text_arg(c, at(args, 0usize))
        var hay = text_arg(c, at(args, 1usize))
        if str.eq(name, "SEARCH") {
            needle = j3(c, "LOWER(", needle, ")")
            hay = j3(c, "LOWER(", hay, ")")
        }
        ret typed(j5(c, "POSITION(", needle, " IN ", hay, ")"), "full", "number")
    }
    if str.eq(name, "SPLIT") || str.eq(name, "JOIN") || str.eq(name, "TEXTJOIN") || str.eq(name, "ARRAYJOIN") { ret none() }

    // --- date and time ---
    if str.eq(name, "YEAR") { ret extract(c, "YEAR", args) }
    if str.eq(name, "MONTH") { ret extract(c, "MONTH", args) }
    if str.eq(name, "DAY") { ret extract(c, "DAY", args) }
    if str.eq(name, "HOUR") { ret extract(c, "HOUR", args) }
    if str.eq(name, "MINUTE") { ret extract(c, "MINUTE", args) }
    if str.eq(name, "SECOND") { ret typed(j3(c, "FLOOR(EXTRACT(SECOND FROM ", at(args, 0usize), "))"), "full", "number") }
    if str.eq(name, "WEEKDAY") { ret typed(j3(c, "(EXTRACT(DOW FROM ", at(args, 0usize), ") + 1)"), "full", "number") }
    if str.eq(name, "WEEKNUM") {
        let d = at(args, 0usize)
        let doy = j3(c, "((EXTRACT(DOY FROM ", d, ") - 1) + EXTRACT(DOW FROM DATE_TRUNC('year', ")
        ret typed(j5(c, "(FLOOR(", doy, d, ")))", " / 7) + 1)"), "full", "number")
    }
    if str.eq(name, "ISOWEEKNUM") { ret extract(c, "WEEK", args) }
    if str.eq(name, "DATE") { ret none() }
    if str.eq(name, "TODATE") { ret typed(j3(c, "(", at(args, 0usize), ")::date"), "full", "date") }
    if str.eq(name, "TODAY") || str.eq(name, "NOW") || str.eq(name, "CURRENTUSER") || str.eq(name, "USERID") { ret none() }

    // --- aggregates are list functions in a row: not pushed down ---
    ret none()
}

// --- the public surface ---------------------------------------------------------------------------------------------

fn failure(oversize: bool) -> Compiled {
    var none_params: []const f.Value = zero
    ret Compiled { sql: "", params: none_params, pushdown: "none", value_type: "unknown", oversize: oversize }
}

// Compile `source` against `schema`. A formula that does not parse, names an unknown column, or uses what SQL
// cannot answer yields `pushdown: none`.
fn compile_formula(a: *mem.Arena, reg: *const f.Registry, source: str, schema: []const Column, options: Options) -> Compiled {
    let (tree, diag) = f.parse(a, source, 0usize)
    if !diag.good { ret failure(false) }
    let capacity = f.count_nodes(tree) + 4usize
    let (params, pe) = mem.alloc[f.Value](a, capacity)
    if pe != ok { ret failure(false) }
    var c = Comp { a: a, reg: reg, schema: schema, double_quote: options.double_quote_columns, params: params, param_count: 0usize, failed: false, oversize: false }
    let out = compile(&c, tree)
    if c.failed { ret failure(c.oversize) }
    var vtype = out.vtype
    if vtype.len == 0usize { vtype = "unknown" }
    ret Compiled { sql: out.sql, params: params[0usize..c.param_count], pushdown: out.pushdown, value_type: vtype, oversize: false }
}

// A compiled fragment as a WHERE clause (the filter's truthiness: a non-empty string is true); false when the
// fragment's type cannot be decided and it must not be pushed down.
fn boolean_fragment(a: *mem.Arena, compiled: Compiled) -> (str, bool) {
    if compiled.sql.len == 0usize { ret ("", false) }
    let sql = compiled.sql
    if str.eq(compiled.value_type, "boolean") { ret (f.join3(a, "(", sql, " IS TRUE)"), true) }
    if str.eq(compiled.value_type, "number") { ret (f.join3(a, "(((", sql, ") <> 0) IS TRUE)"), true) }
    if str.eq(compiled.value_type, "text") { ret (f.join3(a, "(((", sql, ") <> '') IS TRUE)"), true) }
    if str.eq(compiled.value_type, "date") { ret (f.join3(a, "(", sql, " IS NOT NULL)"), true) }
    if str.eq(compiled.value_type, "blank") { ret ("false", true) }
    ret ("", false)
}

// Whether the whole formula pushes down.
fn is_pushdownable(a: *mem.Arena, reg: *const f.Registry, source: str, schema: []const Column, options: Options) -> bool {
    ret str.eq(compile_formula(a, reg, source, schema, options).pushdown, "full")
}

// --- classification ---------------------------------------------------------------------------------------------

type Walk = struct { names: []str, count: usize, volatile_seen: bool, unsupported_seen: bool }

fn walk(c: *Comp, w: *Walk, node: f.Node) {
    if node.kind == .Call {
        let (index, known) = f.resolve(c.a, c.reg, node.s)
        if !known {
            w.names[w.count] = node.s
            w.count += 1usize
            w.unsupported_seen = true
        } else if f.entry_at(c.reg, index).volatile_fn {
            w.volatile_seen = true
        }
        if is_name(node.s, "GETRECORDS") || is_name(node.s, "GETFIELDVALUES") || is_name(node.s, "CHILDREN") || is_name(node.s, "ANCESTORS") {
            w.names[w.count] = node.s
            w.count += 1usize
            w.unsupported_seen = true
        }
    }
    var i = 0usize
    while i < node.kids.len {
        walk(c, w, node.kids[i])
        i += 1usize
    }
}

fn node_total(node: f.Node) -> usize {
    var n = 2usize
    var i = 0usize
    while i < node.kids.len {
        n += node_total(node.kids[i])
        i += 1usize
    }
    ret n
}

// Classify an already parsed tree: `none` with `volatile-functions` when a volatile function is called, `partial`
// with `unsupported-functions` (the distinct names) when a function is unknown or needs a host callback, else `full`.
fn classify_tree(a: *mem.Arena, reg: *const f.Registry, tree: f.Node) -> Verdict {
    var none_names: []const str = zero
    let (names, e) = mem.alloc[str](a, node_total(tree) + 1usize)
    if e != ok { ret Verdict { classification: "none", reason: "parse-error", has_reason: true, unsupported: none_names, has_unsupported: false } }
    var no_schema: []const Column = zero
    var no_params: []f.Value = zero
    var c = Comp { a: a, reg: reg, schema: no_schema, double_quote: true, params: no_params, param_count: 0usize, failed: false, oversize: false }
    var w = Walk { names: names, count: 0usize, volatile_seen: false, unsupported_seen: false }
    walk(&c, &w, tree)
    if w.volatile_seen {
        var listed = none_names
        if w.count > 0usize { listed = names[0usize..w.count] }
        ret Verdict { classification: "none", reason: "volatile-functions", has_reason: true, unsupported: listed, has_unsupported: w.count > 0usize }
    }
    if w.unsupported_seen {
        // distinct, in first-seen order
        var n = 0usize
        var i = 0usize
        while i < w.count {
            var seen = false
            var k = 0usize
            while k < n {
                if str.eq(names[k], names[i]) { seen = true }
                k += 1usize
            }
            if !seen {
                names[n] = names[i]
                n += 1usize
            }
            i += 1usize
        }
        ret Verdict { classification: "partial", reason: "unsupported-functions", has_reason: true, unsupported: names[0usize..n], has_unsupported: true }
    }
    ret Verdict { classification: "full", reason: "", has_reason: false, unsupported: none_names, has_unsupported: false }
}

// Classify formula text: an empty formula is `full`, one that does not parse is `none` with `parse-error`.
fn classify(a: *mem.Arena, reg: *const f.Registry, source: str) -> Verdict {
    var none_names: []const str = zero
    if str.trim(source).len == 0usize {
        ret Verdict { classification: "full", reason: "", has_reason: false, unsupported: none_names, has_unsupported: false }
    }
    let (tree, diag) = f.parse(a, source, 0usize)
    if !diag.good {
        ret Verdict { classification: "none", reason: "parse-error", has_reason: true, unsupported: none_names, has_unsupported: false }
    }
    ret classify_tree(a, reg, tree)
}
