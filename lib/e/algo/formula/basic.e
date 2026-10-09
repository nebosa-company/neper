// The logical, information, lookup and finance function groups of the formula library (L027): IF, IFS, IFERROR,
// IFNA, SWITCH, AND, OR, XOR, NOT, TRUE, FALSE, BLANK, ERROR, INRANGE, TYPEOF, IS_SAME, UNEQUAL; ISBLANK, ISNUMBER,
// ISTEXT, ISNONTEXT, ISERROR, ISNA, ISLOGICAL, TYPE, ISNOTBLANK, ISNULL, ISDATE, NZ, IS_SAME_TYPE; CHOOSE, INDEX,
// MATCH, LOOKUP, OFFSET; PMT, FV, PV, NPV, NPER, RATE, IRR, SLN. Each follows appdor's `src/formula/{logical,
// information,lookup,finance}.js` function for function, with the same names, aliases, arities and error
// messages; `register` adds them all to a registry.
//
// Differences: `ISDATE` reads ISO-8601 text only (JavaScript's `new Date(text)` accepts a wide legacy grammar).

use e.algo.formula as f
use e.math
use e.mem
use e.str

// --- helpers --------------------------------------------------------------------------------------------------------

// `Math.trunc` of a number-or-blank value (blank is 0).
fn trunc_of(v: f.Value) -> f64 {
    if v.kind == .Blank { ret 0.0f64 }
    ret math.trunc[f64](v.n)
}

// A number argument as the finance functions read them: blank is 0; an error is returned in `failure`.
fn finance_numbers(c: *f.Call, count: usize, out: []f64) -> f.Value {
    var i = 0usize
    while i < count {
        let n = f.to_number(c.a, c.args[i])
        if f.is_error(n) { ret n }
        if n.kind == .Blank {
            out[i] = 0.0f64
        } else {
            out[i] = n.n
        }
        i += 1usize
    }
    ret f.blank()
}

fn min_usize(x: usize, y: usize) -> usize {
    if x < y { ret x }
    ret y
}

fn abs_f(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// --- logical ------------------------------------------------------------------------------------------------------

fn h_if(c: *f.Call) -> f.Value {
    let cond = f.eval_node(c, c.nodes[0usize])
    if f.is_error(cond) { ret cond }
    if f.to_bool(cond) { ret f.eval_node(c, c.nodes[1usize]) }
    if c.nodes.len > 2usize { ret f.eval_node(c, c.nodes[2usize]) }
    ret f.boolean(false)
}

fn h_ifs(c: *f.Call) -> f.Value {
    let has_default = c.nodes.len % 2usize == 1usize
    var pair_end = c.nodes.len
    if has_default { pair_end = c.nodes.len - 1usize }
    var i = 0usize
    while i < pair_end {
        let cond = f.eval_node(c, c.nodes[i])
        if f.is_error(cond) { ret cond }
        if f.to_bool(cond) { ret f.eval_node(c, c.nodes[i + 1usize]) }
        i += 2usize
    }
    if has_default { ret f.eval_node(c, c.nodes[c.nodes.len - 1usize]) }
    ret f.na_error("No condition in IFS matched")
}

fn h_iferror(c: *f.Call) -> f.Value {
    let v = f.eval_node(c, c.nodes[0usize])
    if f.is_error(v) { ret f.eval_node(c, c.nodes[1usize]) }
    ret v
}

fn h_ifna(c: *f.Call) -> f.Value {
    let v = f.eval_node(c, c.nodes[0usize])
    if f.is_na(v) { ret f.eval_node(c, c.nodes[1usize]) }
    ret v
}

fn h_switch(c: *f.Call) -> f.Value {
    let subject = f.eval_node(c, c.nodes[0usize])
    if f.is_error(subject) { ret subject }
    let rest = c.nodes.len - 1usize
    let has_default = rest % 2usize == 1usize
    let pairs = rest / 2usize
    var i = 0usize
    while i < pairs {
        let case_value = f.eval_node(c, c.nodes[1usize + i * 2usize])
        if f.is_error(case_value) { ret case_value }
        if f.loose_equals(c.a, subject, case_value) { ret f.eval_node(c, c.nodes[2usize + i * 2usize]) }
        i += 1usize
    }
    if has_default { ret f.eval_node(c, c.nodes[c.nodes.len - 1usize]) }
    ret f.na_error("No case in SWITCH matched")
}

fn h_and(c: *f.Call) -> f.Value {
    var i = 0usize
    while i < c.nodes.len {
        let v = f.eval_node(c, c.nodes[i])
        if f.is_error(v) { ret v }
        if !f.to_bool(v) { ret f.boolean(false) }
        i += 1usize
    }
    ret f.boolean(true)
}

fn h_or(c: *f.Call) -> f.Value {
    var i = 0usize
    while i < c.nodes.len {
        let v = f.eval_node(c, c.nodes[i])
        if f.is_error(v) { ret v }
        if f.to_bool(v) { ret f.boolean(true) }
        i += 1usize
    }
    ret f.boolean(false)
}

fn h_xor(c: *f.Call) -> f.Value {
    var trues = 0usize
    var i = 0usize
    while i < c.args.len {
        if f.to_bool(c.args[i]) { trues += 1usize }
        i += 1usize
    }
    ret f.boolean(trues % 2usize == 1usize)
}

fn h_not(c: *f.Call) -> f.Value { ret f.boolean(!f.to_bool(c.args[0usize])) }

fn h_true(c: *f.Call) -> f.Value { ret f.boolean(true) }

fn h_false(c: *f.Call) -> f.Value { ret f.boolean(false) }

fn h_blank(c: *f.Call) -> f.Value { ret f.blank() }

fn h_error(c: *f.Call) -> f.Value {
    if c.args.len > 0usize {
        let t = f.to_text(c.a, c.args[0usize])
        if f.is_error(t) { ret f.generic_error(f.code_text(t.code)) }
        ret f.generic_error(t.s)
    }
    ret f.generic_error("Error")
}

fn h_inrange(c: *f.Call) -> f.Value {
    let x = f.to_number(c.a, c.args[0usize])
    let lo_arg = f.to_number(c.a, c.args[1usize])
    let hi_arg = f.to_number(c.a, c.args[2usize])
    if f.is_error(x) { ret x }
    if f.is_error(lo_arg) { ret lo_arg }
    if f.is_error(hi_arg) { ret hi_arg }
    if x.kind == .Blank || lo_arg.kind == .Blank || hi_arg.kind == .Blank { ret f.boolean(false) }
    let lo = math.min[f64](lo_arg.n, hi_arg.n)
    let hi = math.max[f64](lo_arg.n, hi_arg.n)
    ret f.boolean(x.n >= lo && x.n <= hi)
}

fn h_typeof(c: *f.Call) -> f.Value { ret f.text(f.type_of(c.args[0usize])) }

fn h_is_same(c: *f.Call) -> f.Value { ret f.boolean(f.loose_equals(c.a, c.args[0usize], c.args[1usize])) }

fn h_unequal(c: *f.Call) -> f.Value { ret f.boolean(!f.loose_equals(c.a, c.args[0usize], c.args[1usize])) }

// --- information --------------------------------------------------------------------------------------------------

fn h_isblank(c: *f.Call) -> f.Value { ret f.boolean(f.is_blank(c.args[0usize])) }

fn h_isnotblank(c: *f.Call) -> f.Value { ret f.boolean(!f.is_blank(c.args[0usize])) }

fn h_isnumber(c: *f.Call) -> f.Value {
    let v = c.args[0usize]
    ret f.boolean(v.kind == .Number && v.n == v.n)
}

fn h_istext(c: *f.Call) -> f.Value { ret f.boolean(c.args[0usize].kind == .Text) }

fn h_isnontext(c: *f.Call) -> f.Value { ret f.boolean(c.args[0usize].kind != .Text) }

// JavaScript's `isError(v)` answers the falsy value itself for a falsy argument (`isError(null)` is null,
// `isError(0)` is 0, `isError('')` is ''), and the formulas built on it return that: ISERROR(0) is 0, not FALSE.
fn is_falsy(v: f.Value) -> bool {
    if v.kind == .Blank { ret true }
    if v.kind == .Number { ret v.n == 0.0f64 || v.n != v.n }
    if v.kind == .Bool { ret v.n == 0.0f64 }
    if v.kind == .Text { ret v.s.len == 0usize }
    ret false
}

fn h_iserror(c: *f.Call) -> f.Value {
    let v = c.args[0usize]
    if f.is_error(v) { ret f.boolean(true) }
    if is_falsy(v) { ret v }
    ret f.boolean(false)
}

fn h_isna(c: *f.Call) -> f.Value {
    let v = c.args[0usize]
    if f.is_error(v) { ret f.boolean(v.code == f.E_NA) }
    if is_falsy(v) { ret v }
    ret f.boolean(false)
}

fn h_islogical(c: *f.Call) -> f.Value { ret f.boolean(c.args[0usize].kind == .Bool) }

fn h_type(c: *f.Call) -> f.Value { ret f.number(f64(f.type_code(c.args[0usize]))) }

fn h_isdate(c: *f.Call) -> f.Value {
    let v = c.args[0usize]
    if v.kind == .Date { ret f.boolean(v.n == v.n) }
    if v.kind != .Text { ret f.boolean(false) }
    if str.trim(v.s).len == 0usize { ret f.boolean(false) }
    let (ms, good) = f.parse_date_text(v.s)
    ret f.boolean(good)
}

fn h_nz(c: *f.Call) -> f.Value {
    if !f.is_blank(c.args[0usize]) { ret c.args[0usize] }
    if c.args.len > 1usize { ret c.args[1usize] }
    ret f.number(0.0f64)
}

fn h_is_same_type(c: *f.Call) -> f.Value { ret f.boolean(f.type_code(c.args[0usize]) == f.type_code(c.args[1usize])) }

// --- lookup -------------------------------------------------------------------------------------------------------

// A value as a list: an array is its elements, blank is empty, anything else is one element.
fn as_list(c: *f.Call, v: f.Value, one: []f.Value) -> []const f.Value {
    if v.kind == .Array { ret v.items }
    if f.is_blank(v) { ret one[0usize..0usize] }
    one[0usize] = v
    ret one[0usize..1usize]
}

fn h_choose(c: *f.Call) -> f.Value {
    let idx = f.to_number(c.a, c.args[0usize])
    if f.is_error(idx) { ret idx }
    let i = trunc_of(idx)
    if i < 1.0f64 || i > f64(c.args.len) - 1.0f64 { ret f.value_error("CHOOSE index out of range") }
    ret c.args[usize(i)]
}

fn h_index(c: *f.Call) -> f.Value {
    var one: [1]f.Value = zero
    let arr = as_list(c, c.args[0usize], one[0..])
    let pos = f.to_number(c.a, c.args[1usize])
    if f.is_error(pos) { ret pos }
    let i = trunc_of(pos)
    if i < 1.0f64 || i > f64(arr.len) { ret f.na_error("INDEX position out of range") }
    ret arr[usize(i) - 1usize]
}

fn h_match(c: *f.Call) -> f.Value {
    let wanted = c.args[0usize]
    var one: [1]f.Value = zero
    let arr = as_list(c, c.args[1usize], one[0..])
    var kind = 0.0f64
    if c.args.len > 2usize {
        // `Math.trunc(toNumber(x) ?? 0)`: unconvertible text is an error object, which truncates to NaN.
        let kind_value = f.to_number(c.a, c.args[2usize])
        if f.is_error(kind_value) { kind = f.nan() } else { kind = trunc_of(kind_value) }
    }
    if kind == 0.0f64 {
        var i = 0usize
        while i < arr.len {
            if f.loose_equals(c.a, arr[i], wanted) { ret f.number(f64(i + 1usize)) }
            i += 1usize
        }
        ret f.na_error("MATCH found no exact match")
    }
    var best = -1i64
    var i = 0usize
    while i < arr.len {
        let cmp = f.compare_values(c.a, arr[i], wanted)
        if f.is_error(cmp) { ret cmp }
        if kind == 1.0f64 && cmp.n <= 0.0f64 { best = i64(i) }
        if kind == -1.0f64 && cmp.n >= 0.0f64 { best = i64(i) }
        i += 1usize
    }
    if best == -1i64 { ret f.na_error("MATCH found no match") }
    ret f.number(f64(best + 1i64))
}

fn h_lookup(c: *f.Call) -> f.Value {
    let wanted = c.args[0usize]
    var one_source: [1]f.Value = zero
    var one_result: [1]f.Value = zero
    let source = as_list(c, c.args[1usize], one_source[0..])
    var result = source
    if c.args.len > 2usize { result = as_list(c, c.args[2usize], one_result[0..]) }
    var i = 0usize
    while i < source.len {
        if f.loose_equals(c.a, source[i], wanted) {
            if i < result.len && result[i].kind != .Blank { ret result[i] }
            ret f.na_error("LOOKUP result missing")
        }
        i += 1usize
    }
    ret f.na_error("LOOKUP found no match")
}

// JavaScript's `slice(start, end)` bounds: negative counts from the end, both clamped.
fn slice_bounds(length: usize, start: f64, end: f64) -> (usize, usize) {
    let n = f64(length)
    var from = start
    if from < 0.0f64 {
        from = n + from
        if from < 0.0f64 { from = 0.0f64 }
    } else if from > n {
        from = n
    }
    var to = end
    if to < 0.0f64 {
        to = n + to
        if to < 0.0f64 { to = 0.0f64 }
    } else if to > n {
        to = n
    }
    if to < from { to = from }
    ret (usize(from), usize(to))
}

fn h_offset(c: *f.Call) -> f.Value {
    var one: [1]f.Value = zero
    let arr = as_list(c, c.args[0usize], one[0..])
    let offset = f.to_number(c.a, c.args[1usize])
    if f.is_error(offset) { ret offset }
    let start = trunc_of(offset)
    if c.args.len > 2usize {
        var count = 1.0f64
        let n = f.to_number(c.a, c.args[2usize])
        if n.kind != .Blank { count = math.trunc[f64](n.n) }
        let (from, to) = slice_bounds(arr.len, start, start + count)
        ret f.array(arr[from..to])
    }
    if start < 0.0f64 || start >= f64(arr.len) { ret f.na_error("OFFSET out of range") }
    ret arr[usize(start)]
}

// --- finance ------------------------------------------------------------------------------------------------------

fn h_pmt(c: *f.Call) -> f.Value {
    var v: [5]f64 = zero
    v[3usize] = 0.0f64
    v[4usize] = 0.0f64
    let failure = finance_numbers(c, min_usize(c.args.len, 5usize), v[0..])
    if f.is_error(failure) { ret failure }
    let rate = v[0usize]
    let nper = v[1usize]
    let pv = v[2usize]
    let fv = v[3usize]
    let kind = v[4usize]
    if nper == 0.0f64 { ret f.div_zero_message("PMT: nper is zero") }
    if rate == 0.0f64 { ret f.number(0.0f64 - (pv + fv) / nper) }
    let pw = math.pow[f64](1.0f64 + rate, nper)
    ret f.number(0.0f64 - (rate * (fv + pv * pw)) / ((pw - 1.0f64) * (1.0f64 + rate * kind)))
}

fn h_fv(c: *f.Call) -> f.Value {
    var v: [5]f64 = zero
    let failure = finance_numbers(c, min_usize(c.args.len, 5usize), v[0..])
    if f.is_error(failure) { ret failure }
    let rate = v[0usize]
    let nper = v[1usize]
    let pmt = v[2usize]
    let pv = v[3usize]
    let kind = v[4usize]
    if rate == 0.0f64 { ret f.number(0.0f64 - (pv + pmt * nper)) }
    let pw = math.pow[f64](1.0f64 + rate, nper)
    ret f.number(0.0f64 - (pv * pw + pmt * (1.0f64 + rate * kind) * ((pw - 1.0f64) / rate)))
}

fn h_pv(c: *f.Call) -> f.Value {
    var v: [5]f64 = zero
    let failure = finance_numbers(c, min_usize(c.args.len, 5usize), v[0..])
    if f.is_error(failure) { ret failure }
    let rate = v[0usize]
    let nper = v[1usize]
    let pmt = v[2usize]
    let fv = v[3usize]
    let kind = v[4usize]
    if rate == 0.0f64 { ret f.number(0.0f64 - (fv + pmt * nper)) }
    let pw = math.pow[f64](1.0f64 + rate, nper)
    ret f.number(0.0f64 - (fv + pmt * (1.0f64 + rate * kind) * ((pw - 1.0f64) / rate)) / pw)
}

fn h_npv(c: *f.Call) -> f.Value {
    let rate_value = f.to_number(c.a, c.args[0usize])
    if f.is_error(rate_value) { ret rate_value }
    var rate = 0.0f64
    if rate_value.kind != .Blank { rate = rate_value.n }
    var all: [512]f.Value = zero
    let count = f.flatten_values(c.args[1usize..c.args.len], all[0..], 0usize)
    var total = 0.0f64
    var i = 0usize
    while i < count && i < 512usize {
        let n = f.to_number(c.a, all[i])
        if f.is_error(n) { ret n }
        var x = 0.0f64
        if n.kind != .Blank { x = n.n }
        total += x / math.pow[f64](1.0f64 + rate, f64(i + 1usize))
        i += 1usize
    }
    ret f.number(total)
}

fn h_nper(c: *f.Call) -> f.Value {
    var v: [5]f64 = zero
    let failure = finance_numbers(c, min_usize(c.args.len, 5usize), v[0..])
    if f.is_error(failure) { ret failure }
    let rate = v[0usize]
    let pmt = v[1usize]
    let pv = v[2usize]
    let fv = v[3usize]
    let kind = v[4usize]
    if rate == 0.0f64 {
        if pmt == 0.0f64 { ret f.div_zero_message("NPER: payment is zero") }
        ret f.number(0.0f64 - (pv + fv) / pmt)
    }
    let num = pmt * (1.0f64 + rate * kind) - fv * rate
    let den = pv * rate + pmt * (1.0f64 + rate * kind)
    let q = num / den
    if !(q > 0.0f64) && !(q != q) { ret f.num_error("NPER: no solution") }
    if q != q { ret f.number(q) }
    ret f.number(math.log[f64](q) / math.log[f64](1.0f64 + rate))
}

fn h_rate(c: *f.Call) -> f.Value {
    var v: [6]f64 = zero
    v[5usize] = 0.1f64
    let given = min_usize(c.args.len, 6usize)
    let failure = finance_numbers(c, given, v[0..])
    if f.is_error(failure) { ret failure }
    if given < 6usize { v[5usize] = 0.1f64 }
    let nper = v[0usize]
    let pmt = v[1usize]
    let pv = v[2usize]
    let fv = v[3usize]
    let kind = v[4usize]
    var rate = v[5usize]
    var iter = 0usize
    while iter < 100usize {
        let pw = math.pow[f64](1.0f64 + rate, nper)
        var fx = 0.0f64
        var df = 0.0f64
        if rate == 0.0f64 {
            fx = pv + pmt * nper + fv
            df = nper * (nper - 1.0f64) * pmt * 0.5f64 + pv * nper
        } else {
            fx = pv * pw + pmt * (1.0f64 + rate * kind) * ((pw - 1.0f64) / rate) + fv
            let dpow = nper * math.pow[f64](1.0f64 + rate, nper - 1.0f64)
            df = pv * dpow + pmt * (1.0f64 + rate * kind) * ((dpow * rate - (pw - 1.0f64)) / (rate * rate)) + pmt * kind * ((pw - 1.0f64) / rate)
        }
        if abs_f(df) < 0.000000000001f64 {
            ret f.num_error("RATE did not converge")
        }
        let next = rate - fx / df
        if abs_f(next - rate) < 0.00000001f64 { ret f.number(next) }
        rate = next
        iter += 1usize
    }
    ret f.num_error("RATE did not converge")
}

fn h_irr(c: *f.Call) -> f.Value {
    var all: [512]f.Value = zero
    var first: [1]f.Value = zero
    first[0usize] = c.args[0usize]
    let count = f.flatten_values(first[0..], all[0..], 0usize)
    var flows: [512]f64 = zero
    var n = 0usize
    while n < count && n < 512usize {
        let x = f.to_number(c.a, all[n])
        if f.is_error(x) { ret x }
        if x.kind != .Blank { flows[n] = x.n }
        n += 1usize
    }
    var rate = 0.1f64
    if c.args.len > 1usize {
        let g = f.to_number(c.a, c.args[1usize])
        if g.kind != .Blank { rate = g.n }
    }
    var iter = 0usize
    while iter < 200usize {
        var npv = 0.0f64
        var dnpv = 0.0f64
        var i = 0usize
        while i < n {
            npv += flows[i] / math.pow[f64](1.0f64 + rate, f64(i))
            if i > 0usize { dnpv -= (f64(i) * flows[i]) / math.pow[f64](1.0f64 + rate, f64(i + 1usize)) }
            i += 1usize
        }
        if abs_f(dnpv) < 0.000000000001f64 {
            ret f.num_error("IRR did not converge")
        }
        let next = rate - npv / dnpv
        if abs_f(next - rate) < 0.00000001f64 { ret f.number(next) }
        rate = next
        iter += 1usize
    }
    ret f.num_error("IRR did not converge")
}

fn h_sln(c: *f.Call) -> f.Value {
    var v: [3]f64 = zero
    let failure = finance_numbers(c, 3usize, v[0..])
    if f.is_error(failure) { ret failure }
    if v[2usize] == 0.0f64 { ret f.div_zero_message("SLN: life is zero") }
    ret f.number((v[0usize] - v[1usize]) / v[2usize])
}

// --- registration -------------------------------------------------------------------------------------------------

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, category: str, lazy: bool, pass: bool, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: category, lazy: lazy, pass_errors: pass, volatile_fn: false, generate_once: false, min_args: low, max_args: high, handler: handler })
}

fn one_alias(a: *mem.Arena, name: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 1usize)
    s[0usize] = name
    ret s
}

fn two_aliases(a: *mem.Arena, first: str, second: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 2usize)
    s[0usize] = first
    s[1usize] = second
    ret s
}

// Register the logical, information, lookup and finance functions.
fn register(r: *f.Registry, a: *mem.Arena) -> err {
    var none: []const str = zero
    try add(r, a, "IF", none, "logical", true, false, 2i32, 3i32, h_if)
    try add(r, a, "IFS", none, "logical", true, false, 2i32, -1i32, h_ifs)
    try add(r, a, "IFERROR", none, "logical", true, false, 2i32, 2i32, h_iferror)
    try add(r, a, "IFNA", none, "logical", true, false, 2i32, 2i32, h_ifna)
    try add(r, a, "SWITCH", one_alias(a, "CASE"), "logical", true, false, 3i32, -1i32, h_switch)
    try add(r, a, "AND", none, "logical", true, false, 1i32, -1i32, h_and)
    try add(r, a, "OR", none, "logical", true, false, 1i32, -1i32, h_or)
    try add(r, a, "XOR", none, "logical", false, false, 1i32, -1i32, h_xor)
    try add(r, a, "NOT", none, "logical", false, false, 1i32, 1i32, h_not)
    try add(r, a, "TRUE", none, "logical", false, false, 0i32, 0i32, h_true)
    try add(r, a, "BLANK", none, "logical", false, false, 0i32, 0i32, h_blank)
    try add(r, a, "ERROR", none, "logical", false, true, 0i32, 1i32, h_error)
    try add(r, a, "FALSE", none, "logical", false, false, 0i32, 0i32, h_false)
    try add(r, a, "INRANGE", none, "logical", false, false, 3i32, 3i32, h_inrange)
    try add(r, a, "TYPEOF", none, "logical", false, true, 1i32, 1i32, h_typeof)
    try add(r, a, "IS_SAME", one_alias(a, "ISSAME"), "logical", false, false, 2i32, 2i32, h_is_same)
    try add(r, a, "UNEQUAL", none, "logical", false, false, 2i32, 2i32, h_unequal)
    try add(r, a, "ISBLANK", none, "information", false, true, 1i32, 1i32, h_isblank)
    try add(r, a, "ISNUMBER", none, "information", false, true, 1i32, 1i32, h_isnumber)
    try add(r, a, "ISTEXT", none, "information", false, true, 1i32, 1i32, h_istext)
    try add(r, a, "ISNONTEXT", none, "information", false, true, 1i32, 1i32, h_isnontext)
    try add(r, a, "ISERROR", none, "information", false, true, 1i32, 1i32, h_iserror)
    try add(r, a, "ISNA", none, "information", false, true, 1i32, 1i32, h_isna)
    try add(r, a, "ISLOGICAL", none, "information", false, true, 1i32, 1i32, h_islogical)
    try add(r, a, "TYPE", none, "information", false, true, 1i32, 1i32, h_type)
    try add(r, a, "ISNOTBLANK", none, "information", false, true, 1i32, 1i32, h_isnotblank)
    try add(r, a, "ISNULL", none, "information", false, true, 1i32, 1i32, h_isblank)
    try add(r, a, "ISDATE", none, "information", false, true, 1i32, 1i32, h_isdate)
    try add(r, a, "NZ", none, "information", false, false, 1i32, 2i32, h_nz)
    try add(r, a, "IS_SAME_TYPE", two_aliases(a, "ISSAMATYPE", "IS_SAMA_TYPE"), "information", false, false, 2i32, 2i32, h_is_same_type)
    try add(r, a, "CHOOSE", none, "lookup", false, false, 2i32, -1i32, h_choose)
    try add(r, a, "INDEX", none, "lookup", false, false, 2i32, 3i32, h_index)
    try add(r, a, "MATCH", none, "lookup", false, false, 2i32, 3i32, h_match)
    try add(r, a, "LOOKUP", none, "lookup", false, false, 2i32, 3i32, h_lookup)
    try add(r, a, "OFFSET", none, "lookup", false, false, 2i32, 3i32, h_offset)
    try add(r, a, "PMT", none, "finance", false, false, 3i32, 5i32, h_pmt)
    try add(r, a, "FV", none, "finance", false, false, 3i32, 5i32, h_fv)
    try add(r, a, "PV", none, "finance", false, false, 3i32, 5i32, h_pv)
    try add(r, a, "NPV", none, "finance", false, false, 2i32, -1i32, h_npv)
    try add(r, a, "NPER", none, "finance", false, false, 3i32, 5i32, h_nper)
    try add(r, a, "RATE", none, "finance", false, false, 3i32, 6i32, h_rate)
    try add(r, a, "IRR", none, "finance", false, false, 1i32, 2i32, h_irr)
    try add(r, a, "SLN", none, "finance", false, false, 3i32, 3i32, h_sln)
    ret ok
}
