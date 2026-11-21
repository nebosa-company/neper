// e.fmt.yaml.parse_r and write_r against R's yaml package (libyaml with Syck's 1.1 implicit tags):
// plain scalars, `!!` tags, anchors, merge keys, key coercion and list simplification, and
// as.yaml. tests/oracle/yaml.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R yaml`. A case holds the YAML text ("in")
// and R's answer as a canonical string; a load error is ERR.

use e.fmt.yaml as yaml
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn put(b: *str.Builder, s: str) {
    if str.push(b, s) != ok { os.exit(5) }
}

fn put_string(b: *str.Builder, s: str) {
    put(b, "\"")
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 92u8 { put(b, "\\\\") } else {
        if c == 34u8 { put(b, "\\\"") } else {
        if c == 10u8 { put(b, "\\n") } else {
            if str.push_byte(b, c) != ok { os.exit(5) }
        }
        }
        }
        i += 1usize
    }
    put(b, "\"")
}

fn put_hex64(b: *str.Builder, bits: u64) {
    var shift = 60u64
    var n = 0usize
    while n < 16usize {
        let nibble = u8((bits >> shift) & 15u64)
        var c = 48u8 + nibble
        if nibble > 9u8 { c = 87u8 + nibble }
        if str.push_byte(b, c) != ok { os.exit(5) }
        if shift >= 4u64 { shift -= 4u64 }
        n += 1usize
    }
}

fn canon(b: *str.Builder, v: yaml.Value) {
    switch v {
    case .Null:
        put(b, "~")
    case .Bool as flag:
        if flag { put(b, "b:TRUE") } else { put(b, "b:FALSE") }
    case .Integer as n:
        put(b, "i:")
        if str.push_i64(b, n) != ok { os.exit(5) }
    case .Float as x:
        put(b, "d:")
        put_hex64(b, mem.bitcast[u64](x))
    case .String as s:
        put(b, "s")
        put_string(b, s)
    case .NA as kind:
        if kind == 0u8 { put(b, "b:NA") }
        if kind == 1u8 { put(b, "i:NA") }
        if kind == 2u8 { put(b, "d:7ff00000000007a2") }
        if kind == 3u8 { put(b, "s:NA") }
    case .Sequence as items:
        put(b, "[")
        var i = 0usize
        while i < items.len {
            if i > 0usize { put(b, ",") }
            canon(b, items[i])
            i += 1usize
        }
        put(b, "]")
    case .Mapping as pairs:
        put(b, "{")
        var i = 0usize
        while i < pairs.len {
            if i > 0usize { put(b, ",") }
            switch pairs[i].key {
            case .String as s:
                put_string(b, s)
            default:
                put(b, "?")
            }
            put(b, "=")
            canon(b, pairs[i].value)
            i += 1usize
        }
        put(b, "}")
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let text = c.inputs[0usize]
    let (v, e) = yaml.parse_r(a, text)
    if e != ok { ret "ERR" }
    if str.eq(c.name, "as_yaml") {
        let (buffer, buffer_error) = mem.alloc[u8](a, 16384usize)
        if buffer_error != ok { os.exit(5) }
        var state = io.SliceWriter { data: buffer, off: 0usize }
        var sink = io.slice_writer(&state)
        if yaml.write_r(&sink, &v) != ok { ret "WRITE-ERR" }
        ret buffer[..state.off]
    }
    let (initial, be) = str.builder(a, 256usize)
    if be != ok { os.exit(5) }
    var b = initial
    canon(&b, v)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/yaml.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(c.name)
                let _ = io.print(" ")
                let _ = io.print(c.inputs[0usize])
                let _ = io.print("\n got ")
                let _ = io.print(text)
                let _ = io.print("\n  R  ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
