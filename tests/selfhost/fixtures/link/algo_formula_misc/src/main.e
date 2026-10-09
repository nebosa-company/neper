// The `e.algo.formula` function library, group misc (L027), against appdor's own engine: scripts/
// formula_functions_reference.mjs evaluates, with appdor's default registry, calls of each function of the group at
// every arity it accepts over a vocabulary of numbers, text, dates, arrays, blanks, errors and field references,
// and records each outcome as `N|number`, `T|hex`, `B|1`, `_`, `D|iso`, `[..]` or `E|code|hex`. The fixture
// evaluates the same source with the Neper registry. A line is `{"src": ..., "expect": ...}`.
use e.algo.formula as f
//__USES__
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn same_text(left: str, right: str) -> bool { ret str.eq(left, right) }

// Whether two rendered results agree. Numbers may differ in the last bits (transcendental functions are not
// correctly rounded by every libm: V8's `Math.pow(0.7, 4)` and ours differ by one unit in the last place), so two
// numbers agree within a relative 1e-12; everything else must be identical.
fn same_result(got: str, want: str) -> bool {
    if same_text(got, want) { ret true }
    if got.len > 2usize && want.len > 2usize && got[0usize] == 78u8 && got[1usize] == 124u8 && want[0usize] == 78u8 && want[1usize] == 124u8 {
        let (x, xe) = str.parse_f64(got[2usize..got.len])
        let (y, ye) = str.parse_f64(want[2usize..want.len])
        if xe != ok || ye != ok { ret false }
        var d = x - y
        if d < 0.0f64 { d = 0.0f64 - d }
        var scale = y
        if scale < 0.0f64 { scale = 0.0f64 - scale }
        if scale < 1.0f64 { scale = 1.0f64 }
        ret d <= 0.000000000001f64 * scale
    }
    ret false
}

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

fn render(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Error { ret f.join(a, f.join(a, f.join(a, "E|", f.code_text(v.code)), "|"), hex_text(a, v.s)) }
    if v.kind == .Blank { ret "_" }
    if v.kind == .Number { ret f.join(a, "N|", f.number_text(a, v.n)) }
    if v.kind == .Text {
        if v.s.len == 0usize { ret "T|_" }
        ret f.join(a, "T|", hex_text(a, v.s))
    }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "B|1" }
        ret "B|0"
    }
    if v.kind == .Date {
        if v.n != v.n { ret "D|invalid" }
        ret f.join(a, "D|", f.date_iso(a, v.n))
    }
    if v.kind == .Record { ret "?|[object Object]" }
    var out = "["
    var i = 0usize
    while i < v.items.len {
        if i > 0usize { out = f.join(a, out, ",") }
        out = f.join(a, out, render(a, v.items[i]))
        i += 1usize
    }
    ret f.join(a, out, "]")
}

fn value_of(a: *mem.Arena, v: json.Value) -> f.Value {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret f.number(x)
    case .String as s:
        ret f.text(s)
    case .Bool as b:
        ret f.boolean(b)
    case .Array as items:
        if items.len == 0usize { ret f.array(f.zero_items()) }
        let (out, e) = mem.alloc[f.Value](a, items.len)
        if e != ok { ret f.blank() }
        var i = 0usize
        while i < items.len {
            out[i] = value_of(a, items[i])
            i += 1usize
        }
        ret f.array(out)
    default:
        ret f.blank()
    }
}

fn text_of(v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    default:
        ret ""
    }
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

fn member_text(members: []const json.Member, key: str) -> str {
    var i = 0usize
    while i < members.len {
        if same_text(members[i].key, key) { ret text_of(members[i].value) }
        i += 1usize
    }
    ret ""
}

fn build_registry(a: *mem.Arena) -> f.Registry {
    let (r, e) = f.registry(a, 600usize)
    var reg = r
    if f.register_core(&reg, a) != ok { os.exit(90i32) }
    //__REGISTERS__
    ret reg
}

// The field bag the reference ran with.
fn fields_json() -> str {
    ret "{\"Price\":10,\"Qty\":3,\"Name\":\"Ada Lovelace\",\"Empty\":\"\",\"Nothing\":null,\"Flag\":true,\"NumText\":\"42\",\"Neg\":-7,\"Float\":1.5,\"Zero\":0,\"DateText\":\"2026-01-15\",\"Stamp\":\"2026-01-15T23:30:00\",\"List\":[1,2,3],\"Words\":[\"pear\",\"apple\",\"fig\"],\"Mixed\":[1,\"a\",null,true],\"Padded\":\"  padded  \",\"Csv\":\"a,b,c\",\"Email\":\"ada@example.com\",\"Url\":\"https://example.com/a b?q=1&r=2\",\"Json\":\"{\\\"a\\\":{\\\"b\\\":[1,2,3]},\\\"c\\\":\\\"x\\\"}\"}"
}

fn make_context(a: *mem.Arena) -> f.Context {
    var ctx: f.Context = zero
    let (root, parse_error) = json.parse(a, fields_json(), json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if parse_error != ok { os.exit(93i32) }
    let members = members_of(root)
    let (fields, e) = mem.alloc[f.Field](a, members.len + 2usize)
    if e != ok { os.exit(94i32) }
    var n = 0usize
    var i = 0usize
    while i < members.len {
        fields[n] = f.Field { name: members[i].key, value: value_of(a, members[i].value) }
        n += 1usize
        i += 1usize
    }
    let (when_ms, when_ok) = f.parse_iso("2026-03-01T12:30:45.250Z")
    let (earlier_ms, earlier_ok) = f.parse_iso("2024-02-29T00:00:00.000Z")
    fields[n] = f.Field { name: "When", value: f.date(when_ms) }
    fields[n + 1usize] = f.Field { name: "Earlier", value: f.date(earlier_ms) }
    ctx.fields = fields[0usize..n + 2usize]
    // the host values the reference ran with
    let (created_ms, created_ok) = f.parse_iso("2026-01-01T00:00:00.000Z")
    let (updated_ms, updated_ok) = f.parse_iso("2026-02-02T00:00:00.000Z")
    let (host, he) = mem.alloc[f.Field](a, 10usize)
    if he != ok { os.exit(94i32) }
    host[0usize] = f.Field { name: "rowId", value: f.text("row-1") }
    host[1usize] = f.Field { name: "tableId", value: f.text("tbl-1") }
    host[2usize] = f.Field { name: "appId", value: f.text("app-1") }
    host[3usize] = f.Field { name: "realmId", value: f.text("realm-1") }
    host[4usize] = f.Field { name: "userId", value: f.text("user-1") }
    host[5usize] = f.Field { name: "createdOn", value: f.date(created_ms) }
    host[6usize] = f.Field { name: "createdBy", value: f.text("ada") }
    host[7usize] = f.Field { name: "updatedOn", value: f.date(updated_ms) }
    host[8usize] = f.Field { name: "updatedBy", value: f.text("bob") }
    host[9usize] = f.Field { name: "browserAgent", value: f.text("test-agent") }
    ctx.host = host[0usize..10usize]
    let (now_ms, now_ok) = f.parse_iso("2026-06-15T09:30:00.000Z")
    ctx.now = now_ms
    ctx.has_now = true
    ret ctx
}

fn run(a: *mem.Arena, body: str, reg: *f.Registry) -> u8 {
    var ctx = make_context(a)
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
            var good = false
            var got = ""
            if parse_error == ok {
                let members = members_of(root)
                let v = f.evaluate(a, member_text(members, "src"), &ctx, reg)
                got = render(a, v)
                good = same_result(got, member_text(members, "expect"))
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(f.join(a, "\ngot ", got))
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
    var registry = build_registry(a)
    //__VECTOR_CALLS__
    try io.print("algo formula misc ok")
    ret ok
}
