// `e.fmt.html.template`: one template with an interpolation in element text, in a
// double- and a single-quoted attribute, in an `href`, in a `style` attribute and in
// a `script` element, each value carrying the characters that would break out of its
// context, rendered and inspected; a URI with a `javascript:` scheme replaced; an
// `if` and a `repeat` inside markup; the typed path; and the parse-time refusals --
// an interpolation in a tag name, in an unquoted value, in an `onclick`, in a
// comment, and an unclosed tag. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.text.template as template
use e.fmt.html.template as html_template

type Page = struct { title: str, count: i32, on: bool }

fn render(a: *mem.Arena, source: str, bindings: []const template.Binding, out: []u8) -> (str, err) {
    let options = html_template.Options { max_bytes: 8192usize, max_nodes: 256usize, max_depth: 8u16 }
    let (t, parse_error) = html_template.parse(a, source, options)
    if parse_error != ok { ret ("", parse_error) }
    var sink_state = io.SliceWriter { data: out, off: 0usize }
    var sink = io.slice_writer(&sink_state)
    let run_error = html_template.execute(&t, &sink, bindings)
    if run_error != ok { ret ("", run_error) }
    ret (out[..sink_state.off], ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var bindings: [5]template.Binding = zero
    bindings[0] = template.Binding { name: "v", value: template.Value{ Text: "<b>&\"'x" } }
    bindings[1] = template.Binding { name: "u", value: template.Value{ Text: "/p?q=a b&r=\"c\"" } }
    bindings[2] = template.Binding { name: "js", value: template.Value{ Text: "javascript:alert(1)" } }
    bindings[3] = template.Binding { name: "n", value: template.Value{ I64: 3i64 } }
    bindings[4] = template.Binding { name: "on", value: template.Value{ Bool: true } }
    var out: [1024]u8 = zero
    let (r1, e1) = render(a, "<p>{{v}}</p>", bindings[0..], out[0..])
    if e1 != ok || !str.eq(r1, "<p>&lt;b&gt;&amp;&#34;&#39;x</p>") { os.exit(1) }
    let (r2, e2) = render(a, "<a title=\"{{v}}\" alt='{{v}}'>x</a>", bindings[0..], out[0..])
    if e2 != ok || !str.eq(r2, "<a title=\"&lt;b&gt;&amp;&#34;&#39;x\" alt='&lt;b&gt;&amp;&#34;&#39;x'>x</a>") { os.exit(2) }
    let (r3, e3) = render(a, "<a href=\"{{u}}\">l</a>", bindings[0..], out[0..])
    if e3 != ok || !str.eq(r3, "<a href=\"/p?q=a%20b&amp;r=%22c%22\">l</a>") { os.exit(3) }
    let (r4, e4) = render(a, "<a href='{{js}}'>l</a>", bindings[0..], out[0..])
    if e4 != ok || !str.eq(r4, "<a href='#unsafe'>l</a>") { os.exit(4) }
    let (r5, e5) = render(a, "<div style=\"color: {{v}}\">s</div>", bindings[0..], out[0..])
    if e5 != ok || !str.eq(r5, "<div style=\"color: \\3C b\\3E \\26 \\22 \\27 x\">s</div>") { os.exit(5) }
    let (r6, e6) = render(a, "<script>var x = {{v}};</script><i>{{v}}</i>", bindings[0..], out[0..])
    if e6 != ok || !str.eq(r6, "<script>var x = \"\\x3Cb\\x3E\\x26\\x22\\x27x\";</script><i>&lt;b&gt;&amp;&#34;&#39;x</i>") { os.exit(6) }
    let (r7, e7) = render(a, "<style>p { content: \"{{v}}\" }</style>", bindings[0..], out[0..])
    if e7 != ok || !str.eq(r7, "<style>p { content: \"\\3C b\\3E \\26 \\22 \\27 x\" }</style>") { os.exit(7) }
    let (r8, e8) = render(a, "<ul>{{#repeat n}}<li class=\"i{{@index}}\">{{#if on}}{{@index}}{{else}}-{{/if}}</li>{{/repeat}}</ul>", bindings[0..], out[0..])
    if e8 != ok || !str.eq(r8, "<ul><li class=\"i0\">0</li><li class=\"i1\">1</li><li class=\"i2\">2</li></ul>") { os.exit(8) }
    let (r9, e9) = render(a, "<!-- a --><p>{{n}}</p>", bindings[0..], out[0..])
    if e9 != ok || !str.eq(r9, "<!-- a --><p>3</p>") { os.exit(9) }
    // Typed.
    let options = html_template.Options { max_bytes: 8192usize, max_nodes: 256usize, max_depth: 8u16 }
    let (typed, e10) = html_template.parse(a, "<h1>{{title}}</h1><span data-n=\"{{count}}\">{{#if on}}on{{/if}}</span>", options)
    if e10 != ok { os.exit(10) }
    if html_template.validate[Page](&typed) != ok { os.exit(11) }
    let page = Page { title: "A & B", count: 7, on: true }
    var sink_state = io.SliceWriter { data: out[0..], off: 0usize }
    var sink = io.slice_writer(&sink_state)
    if html_template.execute_typed[Page](&typed, &sink, &page) != ok { os.exit(12) }
    if !str.eq(out[..sink_state.off], "<h1>A &amp; B</h1><span data-n=\"7\">on</span>") { os.exit(13) }
    let (other, e11) = html_template.parse(a, "<p>{{missing}}</p>", options)
    if e11 != ok || html_template.validate[Page](&other) != html_template.MissingValue { os.exit(14) }
    if html_template.execute(&other, &sink, bindings[0..]) != html_template.MissingValue { os.exit(15) }
    // Refusals.
    let (u1, e12) = render(a, "<{{v}}>x</p>", bindings[0..], out[0..])
    if e12 != html_template.UnsafeContext { os.exit(16) }
    let (u2, e13) = render(a, "<p class={{v}}>x</p>", bindings[0..], out[0..])
    if e13 != html_template.UnsafeContext { os.exit(17) }
    let (u3, e14) = render(a, "<p onclick=\"{{v}}\">x</p>", bindings[0..], out[0..])
    if e14 != html_template.UnsafeContext { os.exit(18) }
    let (u4, e15) = render(a, "<!-- {{v}} -->", bindings[0..], out[0..])
    if e15 != html_template.UnsafeContext { os.exit(19) }
    let (u5, e16) = render(a, "<p {{v}}=\"1\">", bindings[0..], out[0..])
    if e16 != html_template.UnsafeContext { os.exit(20) }
    let (u6, e17) = render(a, "<p>{{#if on}}x", bindings[0..], out[0..])
    if e17 != html_template.InvalidTemplate { os.exit(21) }
    ret ok
}
