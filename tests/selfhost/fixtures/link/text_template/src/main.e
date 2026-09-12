// `e.text.template`: interpolation of every value kind, an if with an else both ways,
// a repeat with its index, nesting, whitespace inside tags; then the refusals -- a
// missing binding, an unclosed tag, an unbalanced block, an unknown directive, a
// negative count, a source over the byte limit, a depth over the limit -- and the
// typed path: validate against a struct that lacks a name and one that has them all,
// and execute_typed over it. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.text.template as template

type Model = struct { name: str, count: i32, ratio: f64, on: bool }

fn render(a: *mem.Arena, source: str, bindings: []const template.Binding, out: []u8) -> (str, err) {
    let options = template.Options { max_bytes: 4096usize, max_nodes: 256usize, max_depth: 8u16 }
    let (t, parse_error) = template.parse(a, source, options)
    if parse_error != ok { ret ("", parse_error) }
    var sink_state = io.SliceWriter { data: out, off: 0usize }
    var sink = io.slice_writer(&sink_state)
    let run_error = template.execute(&t, &sink, bindings)
    if run_error != ok { ret ("", run_error) }
    ret (out[..sink_state.off], ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var bindings: [7]template.Binding = zero
    bindings[0] = template.Binding { name: "name", value: template.Value{ Text: "neper" } }
    bindings[1] = template.Binding { name: "count", value: template.Value{ I64: -3i64 } }
    bindings[2] = template.Binding { name: "big", value: template.Value{ U64: 18446744073709551615u64 } }
    bindings[3] = template.Binding { name: "ratio", value: template.Value{ F64: 2.5 } }
    bindings[4] = template.Binding { name: "on", value: template.Value{ Bool: true } }
    bindings[5] = template.Binding { name: "none", value: .Null }
    bindings[6] = template.Binding { name: "three", value: template.Value{ I64: 3i64 } }
    var out: [512]u8 = zero
    let (r1, e1) = render(a, "hi {{name}}: {{ count }} {{big}} {{ratio}} {{on}}[{{none}}]", bindings[0..], out[0..])
    if e1 != ok { os.exit(1) }
    if !str.eq(r1, "hi neper: -3 18446744073709551615 2.5 true[]") { os.exit(2) }
    let (r2, e2) = render(a, "{{#if on}}yes{{else}}no{{/if}}|{{#if none}}yes{{else}}no{{/if}}|{{#if count}}set{{/if}}|{{#if none}}set{{/if}}.", bindings[0..], out[0..])
    if e2 != ok || !str.eq(r2, "yes|no|set|.") { os.exit(3) }
    let (r3, e3) = render(a, "{{#repeat three}}[{{@index}}:{{#if on}}{{name}}{{/if}}]{{/repeat}}", bindings[0..], out[0..])
    if e3 != ok || !str.eq(r3, "[0:neper][1:neper][2:neper]") { os.exit(4) }
    let (r4, e4) = render(a, "{{#repeat none}}x{{/repeat}}-", bindings[0..], out[0..])
    if e4 != template.MissingValue { os.exit(5) }
    let (r5, e5) = render(a, "{{missing}}", bindings[0..], out[0..])
    if e5 != template.MissingValue { os.exit(6) }
    let (r6, e6) = render(a, "a {{name", bindings[0..], out[0..])
    if e6 != template.InvalidTemplate { os.exit(7) }
    let (r7, e7) = render(a, "{{#if on}}a", bindings[0..], out[0..])
    if e7 != template.InvalidTemplate { os.exit(8) }
    let (r8, e8) = render(a, "{{#if on}}a{{/repeat}}", bindings[0..], out[0..])
    if e8 != template.InvalidTemplate { os.exit(9) }
    let (r9, e9) = render(a, "{{else}}", bindings[0..], out[0..])
    if e9 != template.InvalidTemplate { os.exit(10) }
    let (r10, e10) = render(a, "{{#each name}}{{/each}}", bindings[0..], out[0..])
    if e10 != template.InvalidTemplate { os.exit(11) }
    let (r11, e11) = render(a, "{{#repeat count}}x{{/repeat}}", bindings[0..], out[0..])
    if e11 != template.MissingValue { os.exit(12) }
    let tight = template.Options { max_bytes: 4usize, max_nodes: 256usize, max_depth: 8u16 }
    let (t1, e12) = template.parse(a, "12345", tight)
    if e12 != template.TooLarge { os.exit(13) }
    let shallow = template.Options { max_bytes: 4096usize, max_nodes: 256usize, max_depth: 1u16 }
    let (t2, e13) = template.parse(a, "{{#if on}}{{#if on}}x{{/if}}{{/if}}", shallow)
    if e13 != template.TooDeep { os.exit(14) }
    let (t3, e14) = template.parse(a, "{{#if on}}x{{/if}}", shallow)
    if e14 != ok { os.exit(15) }
    let few = template.Options { max_bytes: 4096usize, max_nodes: 2usize, max_depth: 8u16 }
    let (t4, e15) = template.parse(a, "{{name}}{{name}}", few)
    if e15 != template.TooLarge { os.exit(16) }
    // Typed.
    let options = template.Options { max_bytes: 4096usize, max_nodes: 256usize, max_depth: 8u16 }
    let (typed, e16) = template.parse(a, "{{name}}/{{count}}/{{ratio}}/{{#if on}}on{{/if}}", options)
    if e16 != ok { os.exit(17) }
    if template.validate[Model](&typed) != ok { os.exit(18) }
    let (other, e17) = template.parse(a, "{{name}}{{missing}}", options)
    if e17 != ok || template.validate[Model](&other) != template.MissingValue { os.exit(19) }
    let model = Model { name: "m", count: 7, ratio: 0.5, on: true }
    var sink_state = io.SliceWriter { data: out[0..], off: 0usize }
    var sink = io.slice_writer(&sink_state)
    if template.execute_typed[Model](&typed, &sink, &model) != ok { os.exit(20) }
    if !str.eq(out[..sink_state.off], "m/7/0.5/on") { os.exit(21) }
    if template.execute_typed[Model](&other, &sink, &model) != template.MissingValue { os.exit(22) }
    ret ok
}
