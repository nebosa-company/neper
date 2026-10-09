// Terraform-compatible collection operations over JSON values (L022), after petcow's interpreter: `flatten`,
// `distinct`, `compact`, `slice`, `element`, `one`, `matchkeys`, `zipmap`, `transpose`, `setproduct`, `range`,
// and the number functions `sum`, `product`, `minimum`, `maximum`, `pow`, `log`, `signum` and `parse_int`.
//
// A value is an `e.fmt.json.Value` (a decoded JSON or YAML document), so a template engine can hand its values
// straight in and take the result straight out. Equality is `json.values_equal` (numbers by value, so `1` and
// `1.0` are the same; objects by key set, in any order). Results that build a new list or object live in the
// caller's arena; `slice`, `element` and `one` return what was passed in. The guards are petcow's: `range` stops
// at 1,000,000 elements (`TooLarge`) and refuses a zero step, `log` refuses a result that is not a finite number
// (`NotFinite`), `parse_int` takes a base from 2 to 36, an empty list has no `sum`, `product`, `minimum`,
// `maximum` or `element`, and `setproduct` needs two lists or more and at most 1,000,000 combinations.
//
// Two small differences from petcow, both in its edges: `zipmap` and `transpose` need string keys and values
// (`Invalid` otherwise) and `parse_int` reads a leading `+` or `-` and ignores surrounding ASCII whitespace.

use e.mem
use e.fmt.json as json
use e.math
use e.str

error Invalid
error LengthMismatch
error Empty
error OutOfRange
error NegativeIndex
error ZeroStep
error TooLarge
error TooFew
error NotFinite
error BadBase
error NotInteger

const MAX_RANGE: usize = 1000000usize
const MAX_PRODUCT: usize = 1000000usize

fn same(left: json.Value, right: json.Value) -> bool {
    ret json.values_equal(&left, &right)
}

// Nested lists spread into one list, depth first, order kept; an object or scalar is one element.
fn flatten_count(list: []const json.Value) -> usize {
    var n = 0usize
    var i = 0usize
    while i < list.len {
        switch list[i] {
        case .Array as inner:
            n += flatten_count(inner)
        default:
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn flatten_into(list: []const json.Value, out: []json.Value, at: usize) -> usize {
    var n = at
    var i = 0usize
    while i < list.len {
        switch list[i] {
        case .Array as inner:
            n = flatten_into(inner, out, n)
        default:
            out[n] = list[i]
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn flatten(a: *mem.Arena, list: []const json.Value) -> ([]const json.Value, err) {
    let total = flatten_count(list)
    var none: []const json.Value = zero
    if total == 0usize { ret (none, ok) }
    let (out, out_error) = mem.alloc[json.Value](a, total)
    if out_error != ok { ret (none, out_error) }
    let written = flatten_into(list, out, 0usize)
    ret (out[0usize..written], ok)
}

// The list without repeats, the first of each kept.
fn distinct(a: *mem.Arena, list: []const json.Value) -> ([]const json.Value, err) {
    var none: []const json.Value = zero
    if list.len == 0usize { ret (none, ok) }
    let (out, out_error) = mem.alloc[json.Value](a, list.len)
    if out_error != ok { ret (none, out_error) }
    var n = 0usize
    var i = 0usize
    while i < list.len {
        var seen = false
        var k = 0usize
        while k < n && !seen {
            if same(out[k], list[i]) { seen = true }
            k += 1usize
        }
        if !seen {
            out[n] = list[i]
            n += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// The list without its empty strings.
fn compact(a: *mem.Arena, list: []const json.Value) -> ([]const json.Value, err) {
    var none: []const json.Value = zero
    if list.len == 0usize { ret (none, ok) }
    let (out, out_error) = mem.alloc[json.Value](a, list.len)
    if out_error != ok { ret (none, out_error) }
    var n = 0usize
    var i = 0usize
    while i < list.len {
        var empty_string = false
        switch list[i] {
        case .String as text:
            empty_string = text.len == 0usize
        default:
            empty_string = false
        }
        if !empty_string {
            out[n] = list[i]
            n += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// `list[start..end]`; `OutOfRange` unless 0 <= start <= end <= len.
fn slice(list: []const json.Value, start: i64, end: i64) -> ([]const json.Value, err) {
    var none: []const json.Value = zero
    if start < 0i64 || end < start || u64(end) > u64(list.len) { ret (none, OutOfRange) }
    ret (list[usize(start)..usize(end)], ok)
}

// The element at `index`, counting round the list (index 4 of three elements is element 1).
fn element(list: []const json.Value, index: i64) -> (json.Value, err) {
    var none: json.Value = zero
    if list.len == 0usize { ret (none, Empty) }
    if index < 0i64 { ret (none, NegativeIndex) }
    ret (list[usize(u64(index) % u64(list.len))], ok)
}

// null for no elements, the element for exactly one, `LengthMismatch` for more than one.
fn one(list: []const json.Value) -> (json.Value, err) {
    var none: json.Value = zero
    if list.len == 0usize { ret (none, ok) }
    if list.len == 1usize { ret (list[0usize], ok) }
    ret (none, LengthMismatch)
}

// The `values` whose `keys` entry is in `searchset`. `values` and `keys` must be the same length.
fn matchkeys(a: *mem.Arena, values: []const json.Value, keys: []const json.Value, searchset: []const json.Value) -> ([]const json.Value, err) {
    var none: []const json.Value = zero
    if values.len != keys.len { ret (none, LengthMismatch) }
    if values.len == 0usize { ret (none, ok) }
    let (out, out_error) = mem.alloc[json.Value](a, values.len)
    if out_error != ok { ret (none, out_error) }
    var n = 0usize
    var i = 0usize
    while i < values.len {
        var found = false
        var k = 0usize
        while k < searchset.len && !found {
            if same(searchset[k], keys[i]) { found = true }
            k += 1usize
        }
        if found {
            out[n] = values[i]
            n += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// An object from a list of string keys and a list of values; a repeated key keeps its first position and takes
// the last value.
fn zipmap(a: *mem.Arena, keys: []const json.Value, values: []const json.Value) -> ([]const json.Member, err) {
    var none: []const json.Member = zero
    if keys.len != values.len { ret (none, LengthMismatch) }
    if keys.len == 0usize { ret (none, ok) }
    let (out, out_error) = mem.alloc[json.Member](a, keys.len)
    if out_error != ok { ret (none, out_error) }
    var n = 0usize
    var i = 0usize
    while i < keys.len {
        var key = ""
        switch keys[i] {
        case .String as text:
            key = text
        default:
            ret (none, Invalid)
        }
        var at = n
        var k = 0usize
        while k < n {
            if str.eq(out[k].key, key) { at = k }
            k += 1usize
        }
        if at == n {
            out[n] = json.Member { key: key, value: values[i] }
            n += 1usize
        } else {
            out[at] = json.Member { key: key, value: values[i] }
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// Swap an object of string lists: `{"a": ["x", "y"], "b": ["x"]}` becomes `{"x": ["a", "b"], "y": ["a"]}`, the
// new keys in bytewise order and each list sorted. A value that is not a list of strings is `Invalid`.
fn transpose(a: *mem.Arena, members: []const json.Member) -> ([]const json.Member, err) {
    var none: []const json.Member = zero
    var pairs = 0usize
    var i = 0usize
    while i < members.len {
        switch members[i].value {
        case .Array as items:
            var k = 0usize
            while k < items.len {
                switch items[k] {
                case .String as unused:
                    pairs += 1usize
                default:
                    ret (none, Invalid)
                }
                k += 1usize
            }
        default:
            ret (none, Invalid)
        }
        i += 1usize
    }
    if pairs == 0usize { ret (none, ok) }
    // All (new key, old key) pairs, sorted by new key then old key.
    let (new_keys, new_keys_error) = mem.alloc[str](a, pairs)
    if new_keys_error != ok { ret (none, new_keys_error) }
    let (old_keys, old_keys_error) = mem.alloc[str](a, pairs)
    if old_keys_error != ok { ret (none, old_keys_error) }
    var n = 0usize
    i = 0usize
    while i < members.len {
        switch members[i].value {
        case .Array as items:
            var k = 0usize
            while k < items.len {
                switch items[k] {
                case .String as text:
                    new_keys[n] = text
                    old_keys[n] = members[i].key
                    n += 1usize
                default:
                    ret (none, Invalid)
                }
                k += 1usize
            }
        default:
            ret (none, Invalid)
        }
        i += 1usize
    }
    // Stable insertion sort by (new key, old key).
    i = 1usize
    while i < n {
        let new_key = new_keys[i]
        let old_key = old_keys[i]
        var k = i
        while k > 0usize && (str.compare(new_keys[k - 1usize], new_key) > 0i32 || (str.compare(new_keys[k - 1usize], new_key) == 0i32 && str.compare(old_keys[k - 1usize], old_key) > 0i32)) {
            new_keys[k] = new_keys[k - 1usize]
            old_keys[k] = old_keys[k - 1usize]
            k -= 1usize
        }
        new_keys[k] = new_key
        old_keys[k] = old_key
        i += 1usize
    }
    // Group runs of one new key.
    var groups = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || str.compare(new_keys[i - 1usize], new_keys[i]) != 0i32 { groups += 1usize }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[json.Member](a, groups)
    if out_error != ok { ret (none, out_error) }
    let (flat, flat_error) = mem.alloc[json.Value](a, n)
    if flat_error != ok { ret (none, flat_error) }
    var g = 0usize
    var run_start = 0usize
    i = 0usize
    while i < n {
        flat[i] = json.Value { String: old_keys[i] }
        let last = i + 1usize == n || str.compare(new_keys[i + 1usize], new_keys[i]) != 0i32
        if last {
            out[g] = json.Member { key: new_keys[i], value: json.Value { Array: flat[run_start..i + 1usize] } }
            g += 1usize
            run_start = i + 1usize
        }
        i += 1usize
    }
    ret (out[0usize..groups], ok)
}

// The cartesian product of two or more lists as a list of lists, the last list varying fastest.
fn setproduct(a: *mem.Arena, lists: []const []const json.Value) -> ([]const json.Value, err) {
    var none: []const json.Value = zero
    if lists.len < 2usize { ret (none, TooFew) }
    var total = 1usize
    var i = 0usize
    while i < lists.len {
        if lists[i].len == 0usize { ret (none, ok) }
        if total > MAX_PRODUCT / lists[i].len { ret (none, TooLarge) }
        total *= lists[i].len
        i += 1usize
    }
    let width = lists.len
    let (cells, cells_error) = mem.alloc[json.Value](a, total * width)
    if cells_error != ok { ret (none, cells_error) }
    let (out, out_error) = mem.alloc[json.Value](a, total)
    if out_error != ok { ret (none, out_error) }
    var row = 0usize
    while row < total {
        var rest = row
        var column = width
        while column > 0usize {
            column -= 1usize
            let size = lists[column].len
            cells[row * width + column] = lists[column][rest % size]
            rest = rest / size
        }
        out[row] = json.Value { Array: cells[row * width..row * width + width] }
        row += 1usize
    }
    ret (out[0usize..total], ok)
}

// `range(limit)` is `range_from(0, limit, 1)`; the integers from `start` towards `limit` (exclusive) by `step`.
// A zero step is `ZeroStep`; more than 1,000,000 elements is `TooLarge`.
fn range(a: *mem.Arena, start: i64, limit: i64, step: i64) -> ([]const i64, err) {
    var none: []const i64 = zero
    if step == 0i64 { ret (none, ZeroStep) }
    // The count first, so nothing is built that is refused.
    var count = 0u64
    if step > 0i64 && start < limit {
        count = (u64(limit - start) + u64(step) - 1u64) / u64(step)
    }
    if step < 0i64 && start > limit {
        count = (u64(start - limit) + u64(0i64 - step) - 1u64) / u64(0i64 - step)
    }
    if count > u64(MAX_RANGE) { ret (none, TooLarge) }
    if count == 0u64 { ret (none, ok) }
    let (out, out_error) = mem.alloc[i64](a, usize(count))
    if out_error != ok { ret (none, out_error) }
    var i = 0usize
    var x = start
    while i < usize(count) {
        out[i] = x
        x += step
        i += 1usize
    }
    ret (out, ok)
}

fn number_value(v: json.Value) -> (f64, bool) {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret (0.0f64, false) }
        ret (x, true)
    default:
        ret (0.0f64, false)
    }
}

// The sum of a list of numbers (`Empty` for none, `Invalid` for a non-number).
fn sum(list: []const json.Value) -> (f64, err) {
    if list.len == 0usize { ret (0.0f64, Empty) }
    var total = 0.0f64
    var i = 0usize
    while i < list.len {
        let (x, good) = number_value(list[i])
        if !good { ret (0.0f64, Invalid) }
        total += x
        i += 1usize
    }
    ret (total, ok)
}

fn product(list: []const json.Value) -> (f64, err) {
    if list.len == 0usize { ret (0.0f64, Empty) }
    var total = 1.0f64
    var i = 0usize
    while i < list.len {
        let (x, good) = number_value(list[i])
        if !good { ret (0.0f64, Invalid) }
        total *= x
        i += 1usize
    }
    ret (total, ok)
}

fn minimum(list: []const json.Value) -> (f64, err) {
    if list.len == 0usize { ret (0.0f64, Empty) }
    var best = 0.0f64
    var i = 0usize
    while i < list.len {
        let (x, good) = number_value(list[i])
        if !good { ret (0.0f64, Invalid) }
        if i == 0usize || x < best { best = x }
        i += 1usize
    }
    ret (best, ok)
}

fn maximum(list: []const json.Value) -> (f64, err) {
    if list.len == 0usize { ret (0.0f64, Empty) }
    var best = 0.0f64
    var i = 0usize
    while i < list.len {
        let (x, good) = number_value(list[i])
        if !good { ret (0.0f64, Invalid) }
        if i == 0usize || x > best { best = x }
        i += 1usize
    }
    ret (best, ok)
}

// `base` to the power `exponent`.
fn pow(base: f64, exponent: f64) -> f64 {
    ret math.pow[f64](base, exponent)
}

// The logarithm of `number` in `base`; a result that is not finite (log of 0 or a negative, base 1) is `NotFinite`.
fn log(number: f64, base: f64) -> (f64, err) {
    let result = math.log[f64](number) / math.log[f64](base)
    if !(result - result == 0.0f64) { ret (0.0f64, NotFinite) }
    ret (result, ok)
}

// -1, 0 or 1.
fn signum(x: f64) -> i64 {
    if x > 0.0f64 { ret 1i64 }
    if x < 0.0f64 { ret -1i64 }
    ret 0i64
}

// An integer in `base` (2 to 36), with an optional sign and ASCII whitespace round it.
fn parse_int(text: str, base: i64) -> (i64, err) {
    if base < 2i64 || base > 36i64 { ret (0i64, BadBase) }
    var s = str.trim(text)
    var negative = false
    if s.len > 0usize && s[0usize] == 43u8 {
        s = s[1usize..s.len]
    } else if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        s = s[1usize..s.len]
    }
    let (magnitude, parse_error) = str.parse_u64_radix(s, u8(base))
    if parse_error != ok { ret (0i64, NotInteger) }
    if negative {
        if magnitude > 9223372036854775808u64 { ret (0i64, NotInteger) }
        if magnitude == 9223372036854775808u64 { ret (-9223372036854775807i64 - 1i64, ok) }
        ret (0i64 - i64(magnitude), ok)
    }
    if magnitude > 9223372036854775807u64 { ret (0i64, NotInteger) }
    ret (i64(magnitude), ok)
}
