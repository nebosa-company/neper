// The `e.algo.checksum` identifier validators against appdor's own `src/fields/{specialized,barcode,nace}.js`:
// scripts/checksum_reference.mjs generates valid identifiers of every kind (and one-character mutations, spaced,
// hyphenated and lower-case forms, look-alike Unicode) and runs appdor's validators over them. A line is one of
//   {"v": text, "e": "0101..."}                      every kind's answer, in `kinds` order
//   {"b": text, "s": symbology, "e": "..."}          validateBarcode
//   {"t": raw, "f": format, "x": [accepted], "e": ""} scanToFieldValue
//   {"p": [detector, secure, camera, permission], "e": ""}  barcodeScanSupport
//   {"n": text, "e": "level|section|division|code"}  parseNaceCode
//   {"k": code, "l": locale, "e": ""}                 section and division titles, and the section/division tests
use e.algo.checksum as c
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn hex_text(a: *mem.Arena, s: str) -> str {
    if s.len == 0usize { ret "_" }
    let (out, e) = mem.alloc[u8](a, s.len * 2usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < s.len {
        let hi = s[i] >> 4u8
        let lo = s[i] & 15u8
        var h = 48u8 + hi
        if hi > 9u8 { h = 87u8 + hi }
        var l = 48u8 + lo
        if lo > 9u8 { l = 87u8 + lo }
        out[i * 2usize] = h
        out[i * 2usize + 1usize] = l
        i += 1usize
    }
    ret out[0usize..s.len * 2usize]
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = mem.alloc[u8](a, x.len + y.len)
    if e != ok { ret x }
    var n = 0usize
    var k = 0usize
    while k < x.len {
        out[n] = x[k]
        n += 1usize
        k += 1usize
    }
    k = 0usize
    while k < y.len {
        out[n] = y[k]
        n += 1usize
        k += 1usize
    }
    ret out[0usize..n]
}

fn members_of(v: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch v {
    case .Object as m:
        ret m
    default:
        ret none
    }
}

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if str.eq(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var null_value: json.Value = .Null
    ret (null_value, false)
}

fn text_member(members: []const json.Member, key: str) -> (str, bool) {
    let (v, found) = member(members, key)
    if !found { ret ("", false) }
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

fn strings_member(a: *mem.Arena, members: []const json.Member, key: str) -> []const str {
    var none: []const str = zero
    let (v, found) = member(members, key)
    if !found { ret none }
    switch v {
    case .Array as items:
        let (out, e) = mem.alloc[str](a, items.len + 1usize)
        if e != ok { ret none }
        var n = 0usize
        var i = 0usize
        while i < items.len {
            switch items[i] {
            case .String as s:
                out[n] = s
                n += 1usize
            default:
                n += 0usize
            }
            i += 1usize
        }
        ret out[0usize..n]
    default:
        ret none
    }
}

fn render_barcode(a: *mem.Arena, r: c.BarcodeResult) -> str {
    if r.valid { ret join(a, join(a, "ok|", hex_text(a, r.value)), join(a, "|", r.symbology)) }
    ret join(a, join(a, "no|", r.reason), join(a, "|", hex_text(a, r.message)))
}

// Every kind's answer for one value, in `kinds` order.
fn all_kinds(a: *mem.Arena, value: str) -> str {
    let names = c.kinds()
    var out = ""
    var start = 0usize
    var i = 0usize
    while i <= names.len {
        if i == names.len || names[i] == 32u8 {
            let (answer, known) = c.validate(a, names[start..i], value)
            if !known { ret "unknown kind" }
            if answer { out = join(a, out, "1") } else { out = join(a, out, "0") }
            start = i + 1usize
        }
        i += 1usize
    }
    ret out
}

fn flag(members: []const json.Member, index: usize, key: str) -> bool {
    let (v, found) = member(members, key)
    if !found { ret false }
    switch v {
    case .Array as items:
        if index >= items.len { ret false }
        switch items[index] {
        case .Bool as b:
            ret b
        default:
            ret false
        }
    default:
        ret false
    }
}

fn permission_of(members: []const json.Member) -> str {
    let (v, found) = member(members, "p")
    if !found { ret "prompt" }
    switch v {
    case .Array as items:
        if items.len < 4usize { ret "prompt" }
        switch items[3usize] {
        case .String as s:
            ret s
        default:
            ret "prompt"
        }
    default:
        ret "prompt"
    }
}

fn run(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                let members = members_of(root)
                let (expect, has_expect) = text_member(members, "e")
                want = expect
                let (v, has_v) = text_member(members, "v")
                let (b, has_b) = text_member(members, "b")
                let (t, has_t) = text_member(members, "t")
                let (n, has_n) = text_member(members, "n")
                let (k, has_k) = text_member(members, "k")
                let (pf, has_p) = member(members, "p")
                if has_v {
                    got = all_kinds(a, v)
                } else if has_b {
                    let (symbology, has_s) = text_member(members, "s")
                    got = render_barcode(a, c.validate_barcode(a, b, symbology))
                } else if has_t {
                    let (format, has_f) = text_member(members, "f")
                    got = render_barcode(a, c.scan_to_value(a, t, format, strings_member(a, members, "x")))
                } else if has_p {
                    let env = c.ScanEnvironment { has_detector: flag(members, 0usize, "p"), is_secure_context: flag(members, 1usize, "p"), has_camera: flag(members, 2usize, "p"), permission: permission_of(members) }
                    let r = c.scan_support(env)
                    got = join(a, join(a, "", r.reason), join(a, "|", hex_text(a, r.message)))
                    if r.needs_prompt { got = join(a, got, "|prompt") }
                } else if has_n {
                    let (code, valid) = c.parse_nace(a, n)
                    if valid {
                        got = join(a, join(a, code.level, "|"), join(a, join(a, code.section, "|"), join(a, join(a, code.division, "|"), code.code)))
                    } else {
                        got = "null"
                    }
                } else if has_k {
                    let (locale, has_l) = text_member(members, "l")
                    var out = c.nace_section_title(a, k, locale)
                    out = join(a, join(a, out, "|"), c.nace_division_title(a, k, locale))
                    if c.is_nace_section(a, k) { out = join(a, out, "|S") } else { out = join(a, out, "|-") }
                    if c.is_nace_division(a, k) { out = join(a, out, "|D") } else { out = join(a, out, "|-") }
                    got = join(a, join(a, out, "|"), c.nace_section_of(a, k))
                    // titles are text: compare them as hex like the reference does
                    got = hex_text(a, got)
                }
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
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
    try io.print("algo checksum ok")
    ret ok
}
