// `e.text.edit` (Terraform's substr, chomp, indent, trimprefix, trimsuffix, title, strrev, basename and dirname by
// characters, not bytes) against scripts/text_edit_reference.py, which states each function with Python's own string
// operations: petcow's assertions, edges (empty text, only slashes, invalid UTF-8, multi-byte characters, a combining
// mark) and 500 seeded random strings, each through every function. A line is `<kind> <arg> ... => <result>`; text
// arguments are hex of their UTF-8 bytes (`_` for empty), numbers are decimal, and a result is hex or `E:<name>`.
// Kinds: S substr, C chomp, I indent, X trim_prefix, Y trim_suffix, T title, R reverse, B base_name, D dir_name.
use e.text.edit
use e.io
use e.mem
use e.os

fn next_token(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] == 32u8 { p += 1usize }
    let start = p
    while p < line.len && line[p] != 32u8 { p += 1usize }
    ret (line[start..p], p)
}

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

// The bytes a hex token stands for (`_` is empty), in `buffer`.
fn unhex(token: str, buffer: []u8) -> str {
    if token.len == 1usize && token[0usize] == 95u8 { ret buffer[0usize..0usize] }
    var n = 0usize
    var p = 0usize
    while p + 1usize < token.len {
        buffer[n] = nibble(token[p]) * 16u8 + nibble(token[p + 1usize])
        n += 1usize
        p += 2usize
    }
    ret buffer[0usize..n]
}

fn integer(token: str) -> i64 {
    var v = 0i64
    var negative = false
    var i = 0usize
    if token.len > 0usize && token[0usize] == 45u8 {
        negative = true
        i = 1usize
    }
    while i < token.len {
        v = v * 10i64 + i64(token[i] - 48u8)
        i += 1usize
    }
    if negative { ret 0i64 - v }
    ret v
}

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
    if e == edit.Invalid { ret "Invalid" }
    if e == edit.OffsetRange { ret "OffsetRange" }
    if e == edit.Negative { ret "Negative" }
    ret "Other"
}

// Whether `got` (bytes) or the error `e` matches the expected result token.
fn matches(expected: str, got: str, e: err, scratch: []u8) -> bool {
    if e != ok {
        if expected.len < 3usize || expected[0usize] != 69u8 { ret false }
        ret same_text(expected[2usize..expected.len], error_name(e))
    }
    var buffer: [512]u8 = zero
    let want = unhex(expected, buffer[0..])
    ret same_text(got, want)
}

fn check(a: *mem.Arena, line: str) -> bool {
    let kind = line[0usize]
    let (first, after_first) = next_token(line, 2usize)
    var raw: [512]u8 = zero
    var other: [512]u8 = zero
    var scratch: [4]u8 = zero
    let text = unhex(first, raw[0..])
    if kind == 83u8 {
        let (offset, after_offset) = next_token(line, after_first)
        let (length, after_length) = next_token(line, after_offset)
        let (arrow, after_arrow) = next_token(line, after_length)
        let (expected, after_expected) = next_token(line, after_arrow)
        let (got, e) = edit.substr(text, integer(offset), integer(length))
        ret matches(expected, got, e, scratch[0..])
    }
    if kind == 73u8 {
        let (width, after_width) = next_token(line, after_first)
        let (arrow, after_arrow) = next_token(line, after_width)
        let (expected, after_expected) = next_token(line, after_arrow)
        let (got, e) = edit.indent(a, integer(width), text)
        ret matches(expected, got, e, scratch[0..])
    }
    if kind == 88u8 || kind == 89u8 {
        let (second, after_second) = next_token(line, after_first)
        let (arrow, after_arrow) = next_token(line, after_second)
        let (expected, after_expected) = next_token(line, after_arrow)
        let affix = unhex(second, other[0..])
        if kind == 88u8 { ret matches(expected, edit.trim_prefix(text, affix), ok, scratch[0..]) }
        ret matches(expected, edit.trim_suffix(text, affix), ok, scratch[0..])
    }
    let (arrow, after_arrow) = next_token(line, after_first)
    let (expected, after_expected) = next_token(line, after_arrow)
    if kind == 67u8 { ret matches(expected, edit.chomp(text), ok, scratch[0..]) }
    if kind == 66u8 { ret matches(expected, edit.base_name(text), ok, scratch[0..]) }
    if kind == 68u8 { ret matches(expected, edit.dir_name(text), ok, scratch[0..]) }
    if kind == 84u8 {
        let (got, e) = edit.title(a, text)
        ret matches(expected, got, e, scratch[0..])
    }
    let (got, e) = edit.reverse(a, text)
    ret matches(expected, got, e, scratch[0..])
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let mark = mem.mark(a)
            let good = check(a, text[start..i])
            mem.reset(a, mark)
            if !good {
                let shown = io.print(text[start..i])
                ret 1u8
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("text edit ok")
    ret ok
}
