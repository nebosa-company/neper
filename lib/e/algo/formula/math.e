// The math function group of the formula library (L027): SUM, AVERAGE, COUNT, COUNTA, COUNTBLANK, COUNTIF, SUMIF,
// AVERAGEIF, MAX, MIN, MEDIAN, MODE, STDEV, STDEVP, VAR, VARP, PRODUCT, SUMPRODUCT, ADD, MINUS, MULTIPLY, DIVIDE,
// ABS, SIGN, SQRT, EXP, LN, LOG, LOGN, POWER, MOD, QUOTIENT, ROUND, ROUNDUP, ROUNDDOWN, CEILING, FLOOR, PI, SIN, COS,
// TAN, ASIN, ACOS, ATAN, ATAN2, DEGREES, RADIANS, ISODD, ISEVEN, FACT, COMBIN, PERMUT, KURTOSIS, SKEWNESS,
// IS_NORMAL, ARCSIN, ARCCOS, ARCTAN, LOG10, LOG2, INT, TRUNC, EVEN, ODD, RANDBETWEEN, COUNTALL, COUNTUNIQUE,
// COUNTM, LARGE, SMALL, SUMIFS, AVERAGEIFS, COUNTIFS and AVGW. Each follows appdor's `src/formula/math.js` with
// its names, aliases, arities and messages (a message is `key: values` as appdor writes it without a translator).
//
// Aggregates skip blanks and unconvertible text and flatten arrays; the one-number functions answer blank for a
// blank. RANDBETWEEN draws from the context's `random` host function (appdor draws from `Math.random`).

use e.algo.formula as f
use e.math
use e.mem
use e.str

// --- helpers --------------------------------------------------------------------------------------------------------

fn msg0(a: *mem.Arena, key: str) -> str { ret f.join(a, key, ": ") }

fn msg1(a: *mem.Arena, key: str, v1: str) -> str { ret f.join3(a, key, ": ", v1) }

fn msg2(a: *mem.Arena, key: str, v1: str, v2: str) -> str { ret f.join(a, f.join3(a, key, ": ", v1), f.join(a, ", ", v2)) }

fn abs_f(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn is_integer(x: f64) -> bool {
    if x != x { ret false }
    if x - x != 0.0f64 { ret false }
    ret math.trunc[f64](x) == x
}

// `Math.round`: nearest, ties toward positive infinity.
fn js_round(x: f64) -> f64 {
    if x != x || x - x != 0.0f64 { ret x }
    let fl = math.floor[f64](x)
    if x - fl >= 0.5f64 { ret fl + 1.0f64 }
    ret fl
}

// The number of non-array values in a nested argument list.
fn flat_count(args: []const f.Value) -> usize {
    var n = 0usize
    var i = 0usize
    while i < args.len {
        if args[i].kind == .Array {
            n += flat_count(args[i].items)
        } else {
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// Every non-array value of a nested list in order (blanks kept).
fn flat_values(a: *mem.Arena, args: []const f.Value) -> []const f.Value {
    let n = flat_count(args)
    var none: []const f.Value = zero
    if n == 0usize { ret none }
    let (out, e) = mem.alloc[f.Value](a, n)
    if e != ok { ret none }
    let written = f.flatten_values(args, out, 0usize)
    ret out[0usize..written]
}

// The numbers among the arguments (blanks and unconvertible text skipped); a real error value is `failure`.
fn numbers(c: *f.Call, args: []const f.Value) -> ([]const f64, f.Value) {
    var none: []const f64 = zero
    let n = flat_count(args)
    if n == 0usize { ret (none, f.blank()) }
    let (out, e) = mem.alloc[f64](c.a, n)
    if e != ok { ret (none, f.generic_error("Out of memory")) }
    let (count, failure) = f.collect_numbers(c.a, args, out)
    if f.is_error(failure) { ret (none, failure) }
    ret (out[0usize..count], f.blank())
}

fn sum_of(nums: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < nums.len {
        s += nums[i]
        i += 1usize
    }
    ret s
}

fn mean_of(nums: []const f64) -> f64 {
    if nums.len == 0usize { ret 0.0f64 }
    ret sum_of(nums) / f64(nums.len)
}

// A copy of `nums` sorted by `order` (1 ascending, -1 descending); a stable insertion sort.
fn sorted(c: *f.Call, nums: []const f64, descending: bool) -> []f64 {
    var none: []f64 = zero
    if nums.len == 0usize { ret none }
    let (out, e) = mem.alloc[f64](c.a, nums.len)
    if e != ok { ret none }
    var i = 0usize
    while i < nums.len {
        let v = nums[i]
        var k = i
        if descending {
            while k > 0usize && out[k - 1usize] - v < 0.0f64 {
                out[k] = out[k - 1usize]
                k -= 1usize
            }
        } else {
            while k > 0usize && out[k - 1usize] - v > 0.0f64 {
                out[k] = out[k - 1usize]
                k -= 1usize
            }
        }
        out[k] = v
        i += 1usize
    }
    ret out
}

// variance: a number, or the `#NUM!` error for too little data.
fn variance(c: *f.Call, nums: []const f64, population: bool) -> f.Value {
    let n = nums.len
    var need = 2usize
    if population { need = 1usize }
    if n < need { ret f.num_error(msg0(c.a, "varianceNeedsData")) }
    let m = mean_of(nums)
    var ss = 0.0f64
    var i = 0usize
    while i < n {
        ss += (nums[i] - m) * (nums[i] - m)
        i += 1usize
    }
    if population { ret f.number(ss / f64(n)) }
    ret f.number(ss / f64(n - 1usize))
}

// The number a one-argument function works on: the value, blank, or an error (returned in `v`).
fn one(c: *f.Call) -> f.Value { ret f.to_number(c.a, c.args[0usize]) }

fn at(c: *f.Call, i: usize) -> f.Value { ret f.to_number(c.a, c.args[i]) }

// The result of a one-number function applied to the argument, blank for blank.
fn unary(c: *f.Call, kind: u8) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    let x = n.n
    if kind == 0u8 { ret f.number(abs_f(x)) }
    if kind == 1u8 {
        if x > 0.0f64 { ret f.number(1.0f64) }
        if x < 0.0f64 { ret f.number(-1.0f64) }
        ret f.number(x)
    }
    // V8 answers exactly e for exp(1) (fdlibm gives the neighbouring double).
    if kind == 2u8 {
        if x == 1.0f64 { ret f.number(2.718281828459045f64) }
        ret f.number(math.exp[f64](x))
    }
    if kind == 3u8 { ret f.number(math.sin[f64](x)) }
    if kind == 4u8 { ret f.number(math.cos[f64](x)) }
    if kind == 5u8 { ret f.number(math.tan[f64](x)) }
    if kind == 6u8 { ret f.number(math.asin[f64](x)) }
    if kind == 7u8 { ret f.number(math.acos[f64](x)) }
    if kind == 8u8 { ret f.number(math.atan[f64](x)) }
    if kind == 9u8 { ret f.number(x * 180.0f64 / 3.141592653589793f64) }
    if kind == 10u8 { ret f.number(x * 3.141592653589793f64 / 180.0f64) }
    if kind == 11u8 { ret f.number(math.log10[f64](x)) }
    if kind == 12u8 { ret f.number(math.log2[f64](x)) }
    ret f.number(math.floor[f64](x))
}

// --- aggregates ---------------------------------------------------------------------------------------------------

fn h_sum(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    ret f.number(sum_of(nums))
}

fn h_average(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len == 0usize { ret f.div_zero_message(msg1(c.a, "fnOfNoNumbers", "AVERAGE")) }
    ret f.number(mean_of(nums))
}

fn h_count(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    ret f.number(f64(nums.len))
}

fn h_counta(c: *f.Call) -> f.Value {
    let all = flat_values(c.a, c.args)
    var n = 0usize
    var i = 0usize
    while i < all.len {
        if !f.is_blank(all[i]) { n += 1usize }
        i += 1usize
    }
    ret f.number(f64(n))
}

fn h_countblank(c: *f.Call) -> f.Value {
    let all = flat_values(c.a, c.args)
    var n = 0usize
    var i = 0usize
    while i < all.len {
        if f.is_blank(all[i]) { n += 1usize }
        i += 1usize
    }
    ret f.number(f64(n))
}

fn h_countall(c: *f.Call) -> f.Value { ret f.number(f64(flat_count(c.args))) }

fn h_countunique(c: *f.Call) -> f.Value {
    let all = flat_values(c.a, c.args)
    var seen: []f.Value = zero
    if all.len > 0usize {
        let (storage, e) = mem.alloc[f.Value](c.a, all.len)
        if e != ok { ret f.generic_error("Out of memory") }
        seen = storage
    }
    var n = 0usize
    var i = 0usize
    while i < all.len {
        if !f.is_blank(all[i]) {
            var found = false
            var k = 0usize
            while k < n {
                if f.loose_equals(c.a, seen[k], all[i]) { found = true }
                k += 1usize
            }
            if !found {
                seen[n] = all[i]
                n += 1usize
            }
        }
        i += 1usize
    }
    ret f.number(f64(n))
}

// The text JavaScript's `String(v)` gives a value: arrays join their elements with commas, a date is its
// `Date.toString()` text in UTC.
fn js_string(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Date { ret f.date_js_string(a, v.n) }
    if v.kind == .Array {
        var out = ""
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, ",") }
            let item = v.items[i]
            if item.kind != .Blank { out = f.join(a, out, js_string(a, item)) }
            i += 1usize
        }
        ret out
    }
    if v.kind == .Blank { ret "" }
    if v.kind == .Error { ret f.code_text(v.code) }
    let t = f.to_text(a, v)
    ret t.s
}

fn h_countm(c: *f.Call) -> f.Value {
    let all = flat_values(c.a, c.args)
    var total = 0.0f64
    var i = 0usize
    while i < all.len {
        let v = all[i]
        if !f.is_blank(v) {
            if v.kind == .Array {
                total += f64(v.items.len)
            } else {
                // `String(v).split(',').filter(p => p.trim()).length`
                let s = js_string(c.a, v)
                var start = 0usize
                var p = 0usize
                while p <= s.len {
                    if p == s.len || s[p] == 44u8 {
                        if str.trim(s[start..p]).len > 0usize { total += 1.0f64 }
                        start = p + 1usize
                    }
                    p += 1usize
                }
            }
        }
        i += 1usize
    }
    ret f.number(total)
}

fn h_max(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len == 0usize { ret f.number(0.0f64) }
    var best = nums[0usize]
    var i = 1usize
    while i < nums.len {
        if nums[i] > best { best = nums[i] }
        i += 1usize
    }
    ret f.number(best)
}

fn h_min(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len == 0usize { ret f.number(0.0f64) }
    var best = nums[0usize]
    var i = 1usize
    while i < nums.len {
        if nums[i] < best { best = nums[i] }
        i += 1usize
    }
    ret f.number(best)
}

fn h_median(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len == 0usize { ret f.num_error(msg1(c.a, "fnOfNoNumbers", "MEDIAN")) }
    let s = sorted(c, nums, false)
    let mid = s.len / 2usize
    if s.len % 2usize == 1usize { ret f.number(s[mid]) }
    ret f.number((s[mid - 1usize] + s[mid]) / 2.0f64)
}

fn h_mode(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    var best = 0.0f64
    var has_best = false
    var best_count = 1usize
    var i = 0usize
    while i < nums.len {
        var count = 1usize
        var k = 0usize
        while k < i {
            if nums[k] == nums[i] || (nums[k] != nums[k] && nums[i] != nums[i]) { count += 1usize }
            k += 1usize
        }
        if count > best_count {
            best_count = count
            best = nums[i]
            has_best = true
        }
        i += 1usize
    }
    if !has_best { ret f.num_error(msg0(c.a, "modeNoRepeat")) }
    ret f.number(best)
}

fn h_stdev(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    let v = variance(c, nums, false)
    if f.is_error(v) { ret v }
    ret f.number(math.sqrt[f64](v.n))
}

fn h_stdevp(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    let v = variance(c, nums, true)
    if f.is_error(v) { ret v }
    ret f.number(math.sqrt[f64](v.n))
}

fn h_var(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    ret variance(c, nums, false)
}

fn h_varp(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    ret variance(c, nums, true)
}

fn h_product(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len == 0usize { ret f.number(0.0f64) }
    var p = 1.0f64
    var i = 0usize
    while i < nums.len {
        p = p * nums[i]
        i += 1usize
    }
    ret f.number(p)
}

fn h_multiply(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    var p = 1.0f64
    var i = 0usize
    while i < nums.len {
        p = p * nums[i]
        i += 1usize
    }
    ret f.number(p)
}

fn h_sumproduct(c: *f.Call) -> f.Value {
    var arrays: [16][]const f.Value = zero
    var count = c.args.len
    if count > 16usize { count = 16usize }
    var longest = 0usize
    var i = 0usize
    while i < count {
        var one_arg: [1]f.Value = zero
        one_arg[0usize] = c.args[i]
        arrays[i] = flat_values(c.a, one_arg[0..])
        if arrays[i].len > longest { longest = arrays[i].len }
        i += 1usize
    }
    var total = 0.0f64
    var row = 0usize
    while row < longest {
        var p = 1.0f64
        var k = 0usize
        while k < count {
            var n = f.blank()
            if row < arrays[k].len { n = f.to_number(c.a, arrays[k][row]) }
            if f.is_error(n) { ret n }
            if n.kind == .Blank { p = p * 0.0f64 } else { p = p * n.n }
            k += 1usize
        }
        total += p
        row += 1usize
    }
    ret f.number(total)
}

// COUNTIF and its relatives: whether a cell meets a criterion of the form `>5`, `<=3`, `<>x`, `=x`, or a plain
// value (loosely equal).
type Matcher = struct { plain: bool, op: u8, rhs_is_number: bool, rhs_number: f64, rhs_text: str, value: f.Value }

fn has_line_break(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 || s[i] == 13u8 { ret true }
        // U+2028 and U+2029 are E2 80 A8 and E2 80 A9
        if s[i] == 226u8 && i + 2usize < s.len && s[i + 1usize] == 128u8 && (s[i + 2usize] == 168u8 || s[i + 2usize] == 169u8) { ret true }
        i += 1usize
    }
    ret false
}

// The operator at the start of `s` (after `skip` leading spaces): code 1 `<=`, 2 `>=`, 3 `<>`, 4 `!=`, 5 `=`,
// 6 `<`, 7 `>`; and its length.
fn leading_operator(s: str, from: usize, allow_bang: bool) -> (u8, usize) {
    if from + 1usize < s.len {
        let p = s[from]
        let q = s[from + 1usize]
        if p == 60u8 && q == 61u8 { ret (1u8, 2usize) }
        if p == 62u8 && q == 61u8 { ret (2u8, 2usize) }
        if p == 60u8 && q == 62u8 { ret (3u8, 2usize) }
        if allow_bang && p == 33u8 && q == 61u8 { ret (4u8, 2usize) }
    }
    if from < s.len {
        if s[from] == 61u8 { ret (5u8, 1usize) }
        if s[from] == 60u8 { ret (6u8, 1usize) }
        if s[from] == 62u8 { ret (7u8, 1usize) }
    }
    ret (0u8, 0usize)
}

fn is_space(b: u8) -> bool { ret b == 32u8 || (b >= 9u8 && b <= 13u8) }

fn make_matcher(c: *f.Call, criteria: f.Value) -> Matcher {
    var m = Matcher { plain: true, op: 0u8, rhs_is_number: false, rhs_number: 0.0f64, rhs_text: "", value: criteria }
    if criteria.kind != .Text { ret m }
    let s = criteria.s
    var p = 0usize
    while p < s.len && is_space(s[p]) { p += 1usize }
    let (op, width) = leading_operator(s, p, true)
    if op == 0u8 { ret m }
    p += width
    while p < s.len && is_space(s[p]) { p += 1usize }
    let rhs = s[p..s.len]
    if has_line_break(rhs) { ret m }
    m.plain = false
    m.op = op
    m.rhs_text = rhs
    let trimmed = str.trim(rhs)
    if trimmed.len > 0usize {
        let (n, good) = f.parse_number_text(trimmed)
        if good && n == n {
            m.rhs_is_number = true
            m.rhs_number = n
        }
    }
    ret m
}

fn matches(c: *f.Call, m: *const Matcher, value: f.Value) -> bool {
    if m.plain { ret f.loose_equals(c.a, value, m.value) }
    var rhs = f.text(m.rhs_text)
    if m.rhs_is_number { rhs = f.number(m.rhs_number) }
    if m.op == 5u8 { ret f.loose_equals(c.a, value, rhs) }
    if m.op == 3u8 || m.op == 4u8 { ret !f.loose_equals(c.a, value, rhs) }
    let vn = f.to_number(c.a, value)
    if f.is_error(vn) || vn.kind == .Blank { ret false }
    if !m.rhs_is_number { ret false }
    if m.op == 6u8 { ret vn.n < m.rhs_number }
    if m.op == 1u8 { ret vn.n <= m.rhs_number }
    if m.op == 7u8 { ret vn.n > m.rhs_number }
    if m.op == 2u8 { ret vn.n >= m.rhs_number }
    ret false
}

fn range_of(c: *f.Call, v: f.Value) -> []const f.Value {
    var one_arg: [1]f.Value = zero
    one_arg[0usize] = v
    ret flat_values(c.a, one_arg[0..])
}

fn h_countif(c: *f.Call) -> f.Value {
    let m = make_matcher(c, c.args[1usize])
    let range = range_of(c, c.args[0usize])
    var n = 0usize
    var i = 0usize
    while i < range.len {
        if matches(c, &m, range[i]) { n += 1usize }
        i += 1usize
    }
    ret f.number(f64(n))
}

fn h_sumif(c: *f.Call) -> f.Value {
    let range = range_of(c, c.args[0usize])
    let m = make_matcher(c, c.args[1usize])
    var sums = range
    if c.args.len > 2usize { sums = range_of(c, c.args[2usize]) }
    var total = 0.0f64
    var i = 0usize
    while i < range.len {
        if matches(c, &m, range[i]) {
            var n = f.blank()
            if i < sums.len { n = f.to_number(c.a, sums[i]) }
            if f.is_error(n) { ret n }
            if n.kind != .Blank { total += n.n }
        }
        i += 1usize
    }
    ret f.number(total)
}

fn h_averageif(c: *f.Call) -> f.Value {
    let range = range_of(c, c.args[0usize])
    let m = make_matcher(c, c.args[1usize])
    var avgs = range
    if c.args.len > 2usize { avgs = range_of(c, c.args[2usize]) }
    var total = 0.0f64
    var count = 0usize
    var i = 0usize
    while i < range.len {
        if matches(c, &m, range[i]) {
            var n = f.blank()
            if i < avgs.len { n = f.to_number(c.a, avgs[i]) }
            if f.is_error(n) { ret n }
            if n.kind != .Blank {
                total += n.n
                count += 1usize
            }
        }
        i += 1usize
    }
    if count == 0usize { ret f.div_zero_message(msg1(c.a, "fnMatchedNoNumbers", "AVERAGEIF")) }
    ret f.number(total / f64(count))
}

// --- the IFS family -------------------------------------------------------------------------------------------------

// One cell against one criterion in the COUNTIFS/SUMIFS style: a string that starts with an operator compares
// as written (numbers numerically when the operand is a number, else texts), anything else loosely.
fn matches_criterion(c: *f.Call, cell: f.Value, criterion: f.Value) -> bool {
    if criterion.kind == .Text {
        let s = str.trim(criterion.s)
        let (op, width) = leading_operator(s, 0usize, false)
        if op != 0u8 && op != 4u8 {
            var p = width
            while p < s.len && is_space(s[p]) { p += 1usize }
            let rest = s[p..s.len]
            if !has_line_break(rest) {
                let wanted = f.to_number(c.a, f.text(rest))
                let numeric = !f.is_error(wanted) && wanted.kind != .Blank && str.trim(rest).len > 0usize
                if numeric {
                    let left = f.to_number(c.a, cell)
                    if f.is_error(left) || left.kind == .Blank {
                        if op == 3u8 { ret !f.loose_equals(c.a, cell, f.text(rest)) }
                        if op == 5u8 { ret f.loose_equals(c.a, cell, f.text(rest)) }
                        ret false
                    }
                    if op == 6u8 { ret left.n < wanted.n }
                    if op == 7u8 { ret left.n > wanted.n }
                    if op == 2u8 { ret left.n >= wanted.n }
                    if op == 1u8 { ret left.n <= wanted.n }
                    if op == 3u8 { ret !f.loose_equals(c.a, cell, f.text(rest)) }
                    ret f.loose_equals(c.a, cell, f.text(rest))
                }
                // text comparison of String(cell) with the rest
                var left_text = ""
                if cell.kind != .Blank { left_text = js_string(c.a, cell) }
                let order = f.compare_utf16(left_text, rest)
                if op == 6u8 { ret order < 0i32 }
                if op == 7u8 { ret order > 0i32 }
                if op == 2u8 { ret order >= 0i32 }
                if op == 1u8 { ret order <= 0i32 }
                if op == 3u8 { ret !f.loose_equals(c.a, cell, f.text(rest)) }
                ret f.loose_equals(c.a, cell, f.text(rest))
            }
        }
    }
    ret f.loose_equals(c.a, cell, criterion)
}

// The rows matching every (range, criterion) pair that starts at argument `start`; the rows are written into
// `rows` and counted; `failure` is an error when the ranges are ragged or there is no pair.
fn matching_rows(c: *f.Call, start: usize, rows: []usize) -> (usize, f.Value) {
    var pair_count = 0usize
    var i = start
    while i + 1usize < c.args.len {
        pair_count += 1usize
        i += 2usize
    }
    if pair_count == 0usize { ret (0usize, f.num_error(msg0(c.a, "conditionalNeedsRangeCriterion"))) }
    let (ranges, e) = mem.alloc[[]const f.Value](c.a, pair_count)
    if e != ok { ret (0usize, f.generic_error("Out of memory")) }
    var k = 0usize
    while k < pair_count {
        ranges[k] = range_of(c, c.args[start + k * 2usize])
        k += 1usize
    }
    let length = ranges[0usize].len
    k = 1usize
    while k < pair_count {
        if ranges[k].len != length { ret (0usize, f.num_error(msg0(c.a, "conditionalRangesSameLength"))) }
        k += 1usize
    }
    var n = 0usize
    var row = 0usize
    while row < length {
        var all = true
        k = 0usize
        while k < pair_count && all {
            if !matches_criterion(c, ranges[k][row], c.args[start + k * 2usize + 1usize]) { all = false }
            k += 1usize
        }
        if all && n < rows.len {
            rows[n] = row
            n += 1usize
        }
        row += 1usize
    }
    ret (n, f.blank())
}

fn h_countifs(c: *f.Call) -> f.Value {
    let capacity = flat_count(c.args) + 1usize
    let (rows, e) = mem.alloc[usize](c.a, capacity)
    if e != ok { ret f.generic_error("Out of memory") }
    let (n, failure) = matching_rows(c, 0usize, rows)
    if f.is_error(failure) { ret failure }
    ret f.number(f64(n))
}

// SUMIFS (average false) and AVERAGEIFS (average true).
fn conditional(c: *f.Call, average: bool) -> f.Value {
    let capacity = flat_count(c.args) + 1usize
    let (rows, e) = mem.alloc[usize](c.a, capacity)
    if e != ok { ret f.generic_error("Out of memory") }
    let (n, failure) = matching_rows(c, 1usize, rows)
    if f.is_error(failure) { ret failure }
    let values = range_of(c, c.args[0usize])
    var total = 0.0f64
    var picked = 0usize
    var i = 0usize
    while i < n {
        var cell = f.blank()
        if rows[i] < values.len { cell = values[rows[i]] }
        let x = f.to_number(c.a, cell)
        if f.is_error(x) { ret x }
        if x.kind != .Blank {
            total += x.n
            picked += 1usize
        }
        i += 1usize
    }
    if !average { ret f.number(total) }
    if picked == 0usize { ret f.div_zero_message(msg1(c.a, "fnNoMatchingRows", "AVERAGEIFS")) }
    ret f.number(total / f64(picked))
}

fn h_sumifs(c: *f.Call) -> f.Value { ret conditional(c, false) }

fn h_averageifs(c: *f.Call) -> f.Value { ret conditional(c, true) }

// --- arithmetic as functions ----------------------------------------------------------------------------------------

fn h_add(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    ret f.number(sum_of(nums))
}

// The two operands of MINUS/DIVIDE/MOD/QUOTIENT: an error, or blank (both blank-checked), else the numbers.
fn two_numbers(c: *f.Call) -> (f.Value, f.Value, f.Value) {
    let x = at(c, 0usize)
    let y = at(c, 1usize)
    if f.is_error(x) { ret (x, x, x) }
    if f.is_error(y) { ret (y, y, y) }
    if x.kind == .Blank || y.kind == .Blank { ret (f.blank(), x, y) }
    ret (f.blank(), x, y)
}

fn h_minus(c: *f.Call) -> f.Value {
    let (early, x, y) = two_numbers(c)
    if f.is_error(early) { ret early }
    if x.kind == .Blank || y.kind == .Blank { ret f.blank() }
    ret f.number(x.n - y.n)
}

fn h_divide(c: *f.Call) -> f.Value {
    let (early, x, y) = two_numbers(c)
    if f.is_error(early) { ret early }
    if x.kind == .Blank || y.kind == .Blank { ret f.blank() }
    if y.n == 0.0f64 { ret f.div_zero_message(msg1(c.a, "fnByZero", "DIVIDE")) }
    ret f.number(x.n / y.n)
}

fn h_mod(c: *f.Call) -> f.Value {
    let (early, x, y) = two_numbers(c)
    if f.is_error(early) { ret early }
    if x.kind == .Blank || y.kind == .Blank { ret f.blank() }
    if y.n == 0.0f64 { ret f.div_zero_message(msg1(c.a, "fnByZero", "MOD")) }
    ret f.number(x.n - y.n * math.floor[f64](x.n / y.n))
}

fn h_quotient(c: *f.Call) -> f.Value {
    let (early, x, y) = two_numbers(c)
    if f.is_error(early) { ret early }
    if x.kind == .Blank || y.kind == .Blank { ret f.blank() }
    if y.n == 0.0f64 { ret f.div_zero_message(msg1(c.a, "fnByZero", "QUOTIENT")) }
    ret f.number(math.trunc[f64](x.n / y.n))
}

fn h_power(c: *f.Call) -> f.Value {
    let (early, x, y) = two_numbers(c)
    if f.is_error(early) { ret early }
    if x.kind == .Blank || y.kind == .Blank { ret f.blank() }
    let r = math.pow[f64](x.n, y.n)
    if r != r { ret f.num_error(msg1(c.a, "invalidResult", "POWER")) }
    ret f.number(r)
}

fn h_abs(c: *f.Call) -> f.Value { ret unary(c, 0u8) }

fn h_sign(c: *f.Call) -> f.Value { ret unary(c, 1u8) }

fn h_exp(c: *f.Call) -> f.Value { ret unary(c, 2u8) }

fn h_sin(c: *f.Call) -> f.Value { ret unary(c, 3u8) }

fn h_cos(c: *f.Call) -> f.Value { ret unary(c, 4u8) }

fn h_tan(c: *f.Call) -> f.Value { ret unary(c, 5u8) }

fn h_asin(c: *f.Call) -> f.Value { ret unary(c, 6u8) }

fn h_acos(c: *f.Call) -> f.Value { ret unary(c, 7u8) }

fn h_atan(c: *f.Call) -> f.Value { ret unary(c, 8u8) }

fn h_degrees(c: *f.Call) -> f.Value { ret unary(c, 9u8) }

fn h_radians(c: *f.Call) -> f.Value { ret unary(c, 10u8) }

fn h_log10(c: *f.Call) -> f.Value { ret unary(c, 11u8) }

fn h_log2(c: *f.Call) -> f.Value { ret unary(c, 12u8) }

fn h_int(c: *f.Call) -> f.Value { ret unary(c, 13u8) }

fn h_pi(c: *f.Call) -> f.Value { ret f.number(3.141592653589793f64) }

fn h_sqrt(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    if n.n < 0.0f64 { ret f.num_error(msg0(c.a, "sqrtNegative")) }
    ret f.number(math.sqrt[f64](n.n))
}

fn h_ln(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    if n.n <= 0.0f64 { ret f.num_error(msg1(c.a, "fnNeedsPositive", "LN")) }
    ret f.number(math.log[f64](n.n))
}

fn h_log(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var base = f.number(10.0f64)
    if c.args.len > 1usize { base = at(c, 1usize) }
    if f.is_error(base) { ret base }
    // blank is null: `null <= 0` is true, so a blank base is refused like a non-positive one.
    var b = base.n
    if base.kind == .Blank { b = 0.0f64 }
    if n.n <= 0.0f64 || b <= 0.0f64 || b == 1.0f64 { ret f.num_error(msg1(c.a, "invalidArguments", "LOG")) }
    ret f.number(math.log[f64](n.n) / math.log[f64](b))
}

fn h_logn(c: *f.Call) -> f.Value {
    let n = at(c, 0usize)
    let base = at(c, 1usize)
    if f.is_error(n) { ret n }
    if f.is_error(base) { ret base }
    if n.kind == .Blank || base.kind == .Blank { ret f.blank() }
    if n.n <= 0.0f64 || base.n <= 0.0f64 || base.n == 1.0f64 { ret f.num_error(msg1(c.a, "invalidArguments", "LOGN")) }
    ret f.number(math.log[f64](n.n) / math.log[f64](base.n))
}

// 10 to the power of the digit count (`Math.pow(10, d || 0)`): an error object as the count is NaN.
fn ten_to(d: f.Value) -> f64 {
    if f.is_error(d) { ret f.nan() }
    if d.kind == .Blank { ret 1.0f64 }
    if d.n == 0.0f64 || d.n != d.n { ret 1.0f64 }
    ret math.pow[f64](10.0f64, d.n)
}

fn h_round(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var d = f.number(0.0f64)
    if c.args.len > 1usize { d = at(c, 1usize) }
    if f.is_error(d) { ret d }
    let factor = ten_to(d)
    ret f.number(js_round((n.n + 2.220446049250313e-16f64) * factor) / factor)
}

fn h_roundup(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var d = f.number(0.0f64)
    if c.args.len > 1usize { d = at(c, 1usize) }
    let factor = ten_to(d)
    var sign = 1.0f64
    if n.n < 0.0f64 { sign = -1.0f64 }
    ret f.number(sign * math.ceil[f64](abs_f(n.n) * factor) / factor)
}

fn h_rounddown(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var d = f.number(0.0f64)
    if c.args.len > 1usize { d = at(c, 1usize) }
    let factor = ten_to(d)
    var sign = 1.0f64
    if n.n < 0.0f64 { sign = -1.0f64 }
    ret f.number(sign * math.floor[f64](abs_f(n.n) * factor) / factor)
}

// CEILING (`up` true) and FLOOR: to a multiple of the significance.
fn to_multiple(c: *f.Call, up: bool) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var sig = f.number(1.0f64)
    if c.args.len > 1usize { sig = at(c, 1usize) }
    if f.is_error(sig) { ret sig }
    if sig.kind != .Blank && sig.n == 0.0f64 { ret f.number(0.0f64) }
    var s = 0.0f64
    if sig.kind != .Blank { s = sig.n }
    if up { ret f.number(math.ceil[f64](n.n / s) * s) }
    ret f.number(math.floor[f64](n.n / s) * s)
}

fn h_ceiling(c: *f.Call) -> f.Value { ret to_multiple(c, true) }

fn h_floor(c: *f.Call) -> f.Value { ret to_multiple(c, false) }

fn h_atan2(c: *f.Call) -> f.Value {
    let y = at(c, 0usize)
    let x = at(c, 1usize)
    if f.is_error(y) { ret y }
    if f.is_error(x) { ret x }
    var yv = 0.0f64
    var xv = 0.0f64
    if y.kind != .Blank { yv = y.n }
    if x.kind != .Blank { xv = x.n }
    ret f.number(math.atan2[f64](yv, xv))
}

fn h_isodd(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.boolean(false) }
    ret f.boolean(f.fmod(abs_f(math.trunc[f64](n.n)), 2.0f64) == 1.0f64)
}

fn h_iseven(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.boolean(true) }
    ret f.boolean(f.fmod(abs_f(math.trunc[f64](n.n)), 2.0f64) == 0.0f64)
}

fn h_fact(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    let t = math.trunc[f64](n.n)
    if t < 0.0f64 || !is_integer(t) { ret f.num_error(msg0(c.a, "factNonNegativeInteger")) }
    // 171! overflows to infinity and stays there, so the product is infinite from there on: the loop is cut
    // short with the same answer (JavaScript counts all the way, however large the argument).
    var r = 1.0f64
    var i = 2.0f64
    while i <= t && r - r == 0.0f64 {
        r = r * i
        i += 1.0f64
    }
    ret f.number(r)
}

fn h_combin(c: *f.Call) -> f.Value {
    let n = at(c, 0usize)
    let k = at(c, 1usize)
    if f.is_error(n) { ret n }
    if f.is_error(k) { ret k }
    if n.kind == .Blank || k.kind == .Blank { ret f.blank() }
    if k.n < 0.0f64 || n.n < 0.0f64 || k.n > n.n { ret f.num_error(msg1(c.a, "invalidArguments", "COMBIN")) }
    let nn = math.trunc[f64](n.n)
    let kk = math.trunc[f64](k.n)
    var r = 1.0f64
    var i = 0.0f64
    while i < kk && r - r == 0.0f64 {
        r = (r * (nn - i)) / (i + 1.0f64)
        i += 1.0f64
    }
    ret f.number(js_round(r))
}

fn h_permut(c: *f.Call) -> f.Value {
    let n = at(c, 0usize)
    let k = at(c, 1usize)
    if f.is_error(n) { ret n }
    if f.is_error(k) { ret k }
    if n.kind == .Blank || k.kind == .Blank { ret f.blank() }
    if k.n < 0.0f64 || n.n < 0.0f64 || k.n > n.n { ret f.num_error(msg1(c.a, "invalidArguments", "PERMUT")) }
    let nn = math.trunc[f64](n.n)
    let kk = math.trunc[f64](k.n)
    var r = 1.0f64
    var i = 0.0f64
    while i < kk && r - r == 0.0f64 {
        r = r * (nn - i)
        i += 1.0f64
    }
    ret f.number(r)
}

fn h_trunc(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var places = f.number(0.0f64)
    if c.args.len > 1usize { places = at(c, 1usize) }
    if f.is_error(places) { ret places }
    var p = 0.0f64
    if places.kind != .Blank { p = math.trunc[f64](places.n) }
    let factor = math.pow[f64](10.0f64, p)
    ret f.number(math.trunc[f64](n.n * factor) / factor)
}

fn h_even(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    if n.n == 0.0f64 { ret f.number(0.0f64) }
    let away = math.ceil[f64](abs_f(n.n) / 2.0f64) * 2.0f64
    if n.n < 0.0f64 { ret f.number(0.0f64 - away) }
    ret f.number(away)
}

fn h_odd(c: *f.Call) -> f.Value {
    let n = one(c)
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    if n.n == 0.0f64 { ret f.number(1.0f64) }
    var away = math.ceil[f64](abs_f(n.n))
    if f.fmod(away, 2.0f64) == 0.0f64 { away += 1.0f64 }
    if n.n < 0.0f64 { ret f.number(0.0f64 - away) }
    ret f.number(away)
}

// --- distribution shape ---------------------------------------------------------------------------------------------

fn h_kurtosis(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len < 4usize { ret f.num_error(msg2(c.a, "needsAtLeastPoints", "KURTOSIS", "4")) }
    let m = mean_of(nums)
    let v = variance(c, nums, false)
    let sd = math.sqrt[f64](v.n)
    if sd == 0.0f64 { ret f.num_error(msg1(c.a, "fnZeroVariance", "KURTOSIS")) }
    let big_n = f64(nums.len)
    var s4 = 0.0f64
    var i = 0usize
    while i < nums.len {
        s4 += math.pow[f64]((nums[i] - m) / sd, 4.0f64)
        i += 1usize
    }
    ret f.number((big_n * (big_n + 1.0f64) * s4) / ((big_n - 1.0f64) * (big_n - 2.0f64) * (big_n - 3.0f64)) - (3.0f64 * (big_n - 1.0f64) * (big_n - 1.0f64)) / ((big_n - 2.0f64) * (big_n - 3.0f64)))
}

fn h_skewness(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    if nums.len < 3usize { ret f.num_error(msg2(c.a, "needsAtLeastPoints", "SKEWNESS", "3")) }
    let m = mean_of(nums)
    let v = variance(c, nums, false)
    let sd = math.sqrt[f64](v.n)
    if sd == 0.0f64 { ret f.num_error(msg1(c.a, "fnZeroVariance", "SKEWNESS")) }
    let big_n = f64(nums.len)
    var s3 = 0.0f64
    var i = 0usize
    while i < nums.len {
        s3 += math.pow[f64]((nums[i] - m) / sd, 3.0f64)
        i += 1usize
    }
    ret f.number((big_n / ((big_n - 1.0f64) * (big_n - 2.0f64))) * s3)
}

// Abramowitz and Stegun 7.1.26.
fn erf(x: f64) -> f64 {
    let u = 1.0f64 / (1.0f64 + 0.3275911f64 * abs_f(x))
    let y = 1.0f64 - ((((1.061405429f64 * u - 1.453152027f64) * u + 1.421413741f64) * u - 0.284496736f64) * u + 0.254829592f64) * u * math.exp[f64](0.0f64 - x * x)
    if x >= 0.0f64 { ret y }
    ret 0.0f64 - y
}

fn h_is_normal(c: *f.Call) -> f.Value {
    let (nums, failure) = numbers(c, c.args)
    if f.is_error(failure) { ret failure }
    let n = nums.len
    if n < 8usize { ret f.num_error(msg2(c.a, "needsAtLeastPoints", "is_normal", "8")) }
    let m = mean_of(nums)
    let v = variance(c, nums, false)
    let sd = math.sqrt[f64](v.n)
    if sd == 0.0f64 { ret f.boolean(true) }
    let s = sorted(c, nums, false)
    var total = 0.0f64
    var i = 0usize
    while i < n {
        let zi = 0.5f64 * (1.0f64 + erf((s[i] - m) / (sd * 1.4142135623730951f64)))
        let zn = 0.5f64 * (1.0f64 + erf((s[n - 1usize - i] - m) / (sd * 1.4142135623730951f64)))
        total += (2.0f64 * f64(i + 1usize) - 1.0f64) * (math.log[f64](zi) + math.log[f64](1.0f64 - zn))
        i += 1usize
    }
    let nf = f64(n)
    var a2 = 0.0f64 - nf - total / nf
    a2 = a2 * (1.0f64 + 0.75f64 / nf + 2.25f64 / (nf * nf))
    ret f.boolean(a2 < 0.752f64)
}

// --- order statistics and random ------------------------------------------------------------------------------------

fn nth(c: *f.Call, name: str, descending: bool) -> f.Value {
    var pool_args: []const f.Value = c.args[0usize..c.args.len - 1usize]
    let (pool, failure) = numbers(c, pool_args)
    if f.is_error(failure) { ret failure }
    let k = at(c, c.args.len - 1usize)
    if f.is_error(k) { ret k }
    var rank = 0.0f64
    if k.kind != .Blank { rank = math.trunc[f64](k.n) }
    if rank < 1.0f64 || rank > f64(pool.len) {
        var position = ""
        if k.kind != .Blank { position = f.number_text(c.a, k.n) }
        ret f.num_error(msg2(c.a, "noValueAtPosition", name, position))
    }
    let s = sorted(c, pool, descending)
    ret f.number(s[usize(rank) - 1usize])
}

fn h_large(c: *f.Call) -> f.Value { ret nth(c, "LARGE", true) }

fn h_small(c: *f.Call) -> f.Value { ret nth(c, "SMALL", false) }

fn h_avgw(c: *f.Call) -> f.Value {
    var first: [1]f.Value = zero
    first[0usize] = c.args[0usize]
    var second: [1]f.Value = zero
    second[0usize] = c.args[1usize]
    let (values, f1) = numbers(c, first[0..])
    if f.is_error(f1) { ret f1 }
    let (weights, f2) = numbers(c, second[0..])
    if f.is_error(f2) { ret f2 }
    if values.len != weights.len { ret f.num_error(msg0(c.a, "avgwWeightCount")) }
    var total = 0.0f64
    var i = 0usize
    while i < weights.len {
        total += weights[i]
        i += 1usize
    }
    if total == 0.0f64 { ret f.div_zero_message(msg0(c.a, "avgwZeroWeights")) }
    var weighted = 0.0f64
    i = 0usize
    while i < values.len {
        weighted += values[i] * weights[i]
        i += 1usize
    }
    ret f.number(weighted / total)
}

fn h_randbetween(c: *f.Call) -> f.Value {
    let lo = at(c, 0usize)
    let hi = at(c, 1usize)
    if f.is_error(lo) { ret lo }
    if f.is_error(hi) { ret hi }
    if lo.kind == .Blank || hi.kind == .Blank { ret f.blank() }
    let low = math.ceil[f64](math.min[f64](lo.n, hi.n))
    let high = math.floor[f64](math.max[f64](lo.n, hi.n))
    if high < low { ret f.num_error(msg0(c.a, "randbetweenNoInteger")) }
    ret f.number(low + math.floor[f64](f.random(c.ev) * (high - low + 1.0f64)))
}

// --- registration ---------------------------------------------------------------------------------------------------

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, generate_once: bool, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: "math", lazy: false, pass_errors: false, volatile_fn: false, generate_once: generate_once, min_args: low, max_args: high, handler: handler })
}

fn al1(a: *mem.Arena, x: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 1usize)
    s[0usize] = x
    ret s
}

fn al2(a: *mem.Arena, x: str, y: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 2usize)
    s[0usize] = x
    s[1usize] = y
    ret s
}

// Register the math functions.
fn register(r: *f.Registry, a: *mem.Arena) -> err {
    var none: []const str = zero
    try add(r, a, "SUM", none, false, 1i32, -1i32, h_sum)
    try add(r, a, "AVERAGE", al2(a, "AVG", "MEAN"), false, 1i32, -1i32, h_average)
    try add(r, a, "COUNT", none, false, 1i32, -1i32, h_count)
    try add(r, a, "COUNTA", none, false, 1i32, -1i32, h_counta)
    try add(r, a, "COUNTBLANK", none, false, 1i32, -1i32, h_countblank)
    try add(r, a, "COUNTIF", none, false, 2i32, 2i32, h_countif)
    try add(r, a, "SUMIF", none, false, 2i32, 3i32, h_sumif)
    try add(r, a, "AVERAGEIF", none, false, 2i32, 3i32, h_averageif)
    try add(r, a, "MAX", none, false, 1i32, -1i32, h_max)
    try add(r, a, "MIN", none, false, 1i32, -1i32, h_min)
    try add(r, a, "MEDIAN", none, false, 1i32, -1i32, h_median)
    try add(r, a, "MODE", none, false, 1i32, -1i32, h_mode)
    try add(r, a, "STDEV", none, false, 1i32, -1i32, h_stdev)
    try add(r, a, "STDEVP", none, false, 1i32, -1i32, h_stdevp)
    try add(r, a, "VAR", none, false, 1i32, -1i32, h_var)
    try add(r, a, "VARP", none, false, 1i32, -1i32, h_varp)
    try add(r, a, "PRODUCT", none, false, 1i32, -1i32, h_product)
    try add(r, a, "SUMPRODUCT", none, false, 1i32, -1i32, h_sumproduct)
    try add(r, a, "ADD", al1(a, "PLUS"), false, 2i32, -1i32, h_add)
    try add(r, a, "MINUS", al1(a, "SUBTRACT"), false, 2i32, 2i32, h_minus)
    try add(r, a, "MULTIPLY", al1(a, "TIMES"), false, 2i32, -1i32, h_multiply)
    try add(r, a, "DIVIDE", none, false, 2i32, 2i32, h_divide)
    try add(r, a, "ABS", none, false, 1i32, 1i32, h_abs)
    try add(r, a, "SIGN", none, false, 1i32, 1i32, h_sign)
    try add(r, a, "SQRT", none, false, 1i32, 1i32, h_sqrt)
    try add(r, a, "EXP", none, false, 1i32, 1i32, h_exp)
    try add(r, a, "LN", none, false, 1i32, 1i32, h_ln)
    try add(r, a, "LOG", none, false, 1i32, 2i32, h_log)
    try add(r, a, "LOGN", none, false, 2i32, 2i32, h_logn)
    try add(r, a, "POWER", none, false, 2i32, 2i32, h_power)
    try add(r, a, "MOD", none, false, 2i32, 2i32, h_mod)
    try add(r, a, "QUOTIENT", none, false, 2i32, 2i32, h_quotient)
    try add(r, a, "ROUND", none, false, 1i32, 2i32, h_round)
    try add(r, a, "ROUNDUP", none, false, 1i32, 2i32, h_roundup)
    try add(r, a, "ROUNDDOWN", none, false, 1i32, 2i32, h_rounddown)
    try add(r, a, "CEILING", none, false, 1i32, 2i32, h_ceiling)
    try add(r, a, "FLOOR", none, false, 1i32, 2i32, h_floor)
    try add(r, a, "PI", none, false, 0i32, 0i32, h_pi)
    try add(r, a, "SIN", none, false, 1i32, 1i32, h_sin)
    try add(r, a, "COS", none, false, 1i32, 1i32, h_cos)
    try add(r, a, "TAN", none, false, 1i32, 1i32, h_tan)
    try add(r, a, "ASIN", none, false, 1i32, 1i32, h_asin)
    try add(r, a, "ACOS", none, false, 1i32, 1i32, h_acos)
    try add(r, a, "ATAN", none, false, 1i32, 1i32, h_atan)
    try add(r, a, "ATAN2", none, false, 2i32, 2i32, h_atan2)
    try add(r, a, "DEGREES", none, false, 1i32, 1i32, h_degrees)
    try add(r, a, "RADIANS", none, false, 1i32, 1i32, h_radians)
    try add(r, a, "ISODD", none, false, 1i32, 1i32, h_isodd)
    try add(r, a, "ISEVEN", none, false, 1i32, 1i32, h_iseven)
    try add(r, a, "FACT", none, false, 1i32, 1i32, h_fact)
    try add(r, a, "COMBIN", none, false, 2i32, 2i32, h_combin)
    try add(r, a, "PERMUT", none, false, 2i32, 2i32, h_permut)
    try add(r, a, "KURTOSIS", none, false, 1i32, -1i32, h_kurtosis)
    try add(r, a, "SKEWNESS", al1(a, "SKEW"), false, 1i32, -1i32, h_skewness)
    try add(r, a, "IS_NORMAL", al1(a, "ISNORMAL"), false, 1i32, -1i32, h_is_normal)
    try add(r, a, "ARCSIN", none, false, 1i32, 1i32, h_asin)
    try add(r, a, "ARCCOS", none, false, 1i32, 1i32, h_acos)
    try add(r, a, "ARCTAN", none, false, 1i32, 1i32, h_atan)
    try add(r, a, "LOG10", none, false, 1i32, 1i32, h_log10)
    try add(r, a, "LOG2", none, false, 1i32, 1i32, h_log2)
    try add(r, a, "INT", none, false, 1i32, 1i32, h_int)
    try add(r, a, "TRUNC", none, false, 1i32, 2i32, h_trunc)
    try add(r, a, "EVEN", none, false, 1i32, 1i32, h_even)
    try add(r, a, "ODD", none, false, 1i32, 1i32, h_odd)
    try add(r, a, "RANDBETWEEN", none, true, 2i32, 2i32, h_randbetween)
    try add(r, a, "COUNTALL", none, false, 1i32, -1i32, h_countall)
    try add(r, a, "COUNTUNIQUE", none, false, 1i32, -1i32, h_countunique)
    try add(r, a, "COUNTM", none, false, 1i32, -1i32, h_countm)
    try add(r, a, "LARGE", none, false, 2i32, -1i32, h_large)
    try add(r, a, "SMALL", none, false, 2i32, -1i32, h_small)
    try add(r, a, "SUMIFS", none, false, 3i32, -1i32, h_sumifs)
    try add(r, a, "AVERAGEIFS", none, false, 3i32, -1i32, h_averageifs)
    try add(r, a, "COUNTIFS", none, false, 2i32, -1i32, h_countifs)
    try add(r, a, "AVGW", none, false, 2i32, 2i32, h_avgw)
    ret ok
}
