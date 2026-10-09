// `e.algo.collect` (Terraform's flatten, distinct, compact, slice, element, one, matchkeys, zipmap, transpose,
// setproduct, range, sum, product, min, max, pow, log, signum and parseint over JSON values) against
// scripts/collect_reference.py, which states each function on Python objects: petcow's assertions, the error
// cases (empty lists, ranges past the cap, a zero step, a log that is not finite, a base outside 2..36, lists of
// different lengths) and seeded random inputs. A line is `<op> <json> | <json> ... => <result>`, the result JSON
// text, `E:<name>`, or for the number functions a number compared with a relative tolerance of 1e-12.
use e.algo.collect
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn error_name(e: err) -> str {
    if e == collect.Invalid { ret "Invalid" }
    if e == collect.LengthMismatch { ret "LengthMismatch" }
    if e == collect.Empty { ret "Empty" }
    if e == collect.OutOfRange { ret "OutOfRange" }
    if e == collect.NegativeIndex { ret "NegativeIndex" }
    if e == collect.ZeroStep { ret "ZeroStep" }
    if e == collect.TooLarge { ret "TooLarge" }
    if e == collect.TooFew { ret "TooFew" }
    if e == collect.NotFinite { ret "NotFinite" }
    if e == collect.BadBase { ret "BadBase" }
    if e == collect.NotInteger { ret "NotInteger" }
    ret "Other"
}

// The position of `needle` in `s` from `from`, or s.len.
fn find_at(s: str, needle: str, from: usize) -> usize {
    var i = from
    while i + needle.len <= s.len {
        var j = 0usize
        while j < needle.len && s[i + j] == needle[j] { j += 1usize }
        if j == needle.len { ret i }
        i += 1usize
    }
    ret s.len
}

fn parse_value(a: *mem.Arena, text: str) -> json.Value {
    let (v, e) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 16u16 })
    var none: json.Value = zero
    if e != ok { ret none }
    ret v
}

fn items_of(v: json.Value) -> []const json.Value {
    var none: []const json.Value = zero
    switch v {
    case .Array as list:
        ret list
    default:
        ret none
    }
}

fn members_of(v: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch v {
    case .Object as fields:
        ret fields
    default:
        ret none
    }
}

fn integer_of(v: json.Value) -> i64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e != ok { ret 0i64 }
        ret x
    default:
        ret 0i64
    }
}

fn float_of(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret 0.0f64 }
        ret x
    default:
        ret 0.0f64
    }
}

fn text_of_value(a: *mem.Arena, v: json.Value) -> str {
    let (state, writer, e) = io.memory_writer(a, 0usize)
    if e != ok { ret "?" }
    var held = state
    var w = io.writer(mem.cast[*void](&held), io.memory_write)
    var copy = v
    if json.write(&w, &copy) != ok { ret "?" }
    ret io.memory_bytes(&held)
}

fn text_of_list(a: *mem.Arena, list: []const json.Value) -> str {
    ret text_of_value(a, json.Value { Array: list })
}

fn text_of_members(a: *mem.Arena, members: []const json.Member) -> str {
    ret text_of_value(a, json.Value { Object: members })
}

fn near(got: f64, want: f64) -> bool {
    var d = got - want
    if d < 0.0f64 { d = 0.0f64 - d }
    var scale = want
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    if scale < 1.0f64 { scale = 1.0f64 }
    ret d <= 0.000000000001f64 * scale
}

// The verdict for one line.
fn check(a: *mem.Arena, line: str) -> bool {
    let op = line[0usize]
    let arrow = find_at(line, " => ", 2usize)
    let expected = line[arrow + 4usize..line.len]
    let body = line[2usize..arrow]
    // Arguments, split on " | ".
    var args: [8]json.Value = zero
    var texts: [8]str = zero
    var count = 0usize
    var start = 0usize
    var more = true
    while more {
        let bar = find_at(body, " | ", start)
        texts[count] = body[start..bar]
        args[count] = parse_value(a, body[start..bar])
        count += 1usize
        if bar >= body.len { more = false } else { start = bar + 3usize }
    }
    var failure = false
    var result_text = ""
    var e = ok
    if op == 70u8 {
        let (r, re) = collect.flatten(a, items_of(args[0usize]))
        e = re
        result_text = text_of_list(a, r)
    } else if op == 68u8 {
        let (r, re) = collect.distinct(a, items_of(args[0usize]))
        e = re
        result_text = text_of_list(a, r)
    } else if op == 67u8 {
        let (r, re) = collect.compact(a, items_of(args[0usize]))
        e = re
        result_text = text_of_list(a, r)
    } else if op == 76u8 {
        let (r, re) = collect.slice(items_of(args[0usize]), integer_of(args[1usize]), integer_of(args[2usize]))
        e = re
        result_text = text_of_list(a, r)
    } else if op == 69u8 {
        let (r, re) = collect.element(items_of(args[0usize]), integer_of(args[1usize]))
        e = re
        result_text = text_of_value(a, r)
    } else if op == 79u8 {
        let (r, re) = collect.one(items_of(args[0usize]))
        e = re
        result_text = text_of_value(a, r)
    } else if op == 77u8 {
        let (r, re) = collect.matchkeys(a, items_of(args[0usize]), items_of(args[1usize]), items_of(args[2usize]))
        e = re
        result_text = text_of_list(a, r)
    } else if op == 90u8 {
        let (r, re) = collect.zipmap(a, items_of(args[0usize]), items_of(args[1usize]))
        e = re
        result_text = text_of_members(a, r)
    } else if op == 84u8 {
        let (r, re) = collect.transpose(a, members_of(args[0usize]))
        e = re
        result_text = text_of_members(a, r)
    } else if op == 80u8 {
        var lists: [6][]const json.Value = zero
        var k = 0usize
        while k < count {
            lists[k] = items_of(args[k])
            k += 1usize
        }
        let (r, re) = collect.setproduct(a, lists[0usize..count])
        e = re
        result_text = text_of_list(a, r)
    } else if op == 82u8 {
        let (r, re) = collect.range(a, integer_of(args[0usize]), integer_of(args[1usize]), integer_of(args[2usize]))
        e = re
        var joined = "["
        var k = 0usize
        while k < r.len {
            if k > 0usize { joined = cat(a, joined, ",") }
            joined = cat(a, joined, number_text(a, r[k]))
            k += 1usize
        }
        result_text = cat(a, joined, "]")
    } else if op == 87u8 {
        let r = collect.pow(float_of(args[0usize]), float_of(args[1usize]))
        ret near(r, float_of(parse_value(a, expected)))
    } else if op == 71u8 {
        let (r, re) = collect.log(float_of(args[0usize]), float_of(args[1usize]))
        if re != ok { ret expected.len > 2usize && expected[0usize] == 69u8 && same_text(expected[2usize..expected.len], error_name(re)) }
        ret expected[0usize] != 69u8 && near(r, float_of(parse_value(a, expected)))
    } else if op == 73u8 {
        let r = collect.signum(float_of(args[0usize]))
        ret r == integer_of(parse_value(a, expected))
    } else if op == 74u8 {
        var text = ""
        switch args[0usize] {
        case .String as s:
            text = s
        default:
            text = ""
        }
        let (r, re) = collect.parse_int(text, integer_of(args[1usize]))
        if re != ok { ret expected.len > 2usize && expected[0usize] == 69u8 && same_text(expected[2usize..expected.len], error_name(re)) }
        ret expected[0usize] != 69u8 && r == integer_of(parse_value(a, expected))
    } else {
        // S sum, Q product, N minimum, X maximum: a list of numbers to a number.
        var r = 0.0f64
        var re = ok
        if op == 83u8 {
            let (x, xe) = collect.sum(items_of(args[0usize]))
            r = x
            re = xe
        } else if op == 81u8 {
            let (x, xe) = collect.product(items_of(args[0usize]))
            r = x
            re = xe
        } else if op == 78u8 {
            let (x, xe) = collect.minimum(items_of(args[0usize]))
            r = x
            re = xe
        } else {
            let (x, xe) = collect.maximum(items_of(args[0usize]))
            r = x
            re = xe
        }
        if re != ok { ret expected.len > 2usize && expected[0usize] == 69u8 && same_text(expected[2usize..expected.len], error_name(re)) }
        ret expected[0usize] != 69u8 && near(r, float_of(parse_value(a, expected)))
    }
    if e != ok { ret expected.len > 2usize && expected[0usize] == 69u8 && same_text(expected[2usize..expected.len], error_name(e)) }
    ret same_text(result_text, expected)
}

fn cat(a: *mem.Arena, first: str, second: str) -> str {
    let (joined, e) = str.concat(a, first, second)
    if e != ok { ret first }
    ret joined
}

fn number_text(a: *mem.Arena, v: i64) -> str {
    let (n, e) = json.number_from_i64(a, v)
    if e != ok { ret "0" }
    ret n.lexeme
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let mark = mem.mark(a)
            let good = check(a, text[start..i])
            if !good {
                let shown = io.print(text[start..i])
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo collect ok")
    ret ok
}
