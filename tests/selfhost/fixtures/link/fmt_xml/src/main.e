// `e.fmt.xml`: a document with a declaration, a comment, namespaced names, attributes
// in both quote styles with references, character data with the five entities and a
// numeric reference, CDATA, an empty element and a processing instruction walked as
// events with and without comments; the writer producing escaped output the reader
// reads back; refusals for a DOCTYPE, a mismatched end tag, an unclosed element, a
// bad attribute, an unknown entity, a duplicate attribute, and a depth over the
// limit. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.xml as xml

fn open(a: *mem.Arena, text: str, comments: bool, depth: u16) -> (xml.Reader, err) {
    let (state, state_error) = mem.alloc[io.SliceReader](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    state[0] = io.SliceReader { data: text, off: 0usize }
    let (r, r_error) = xml.reader(a, io.slice_reader(&state[0]), xml.Options { max_depth: depth, preserve_comments: comments })
    ret (r, r_error)
}

// Walks every event; the first error, or the count of events and Invalid when the
// document does not end cleanly.
fn count_events(a: *mem.Arena, text: str, depth: u16) -> (usize, err) {
    let (r0, r_error) = open(a, text, false, depth)
    if r_error != ok { ret (0usize, r_error) }
    var r = r0
    var count = 0usize
    while true {
        let (event, more, next_error) = xml.reader_next_err(&r)
        if next_error != ok { ret (count, next_error) }
        if !more { ret (count, ok) }
        count += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let doc = "<?xml version=\"1.0\"?>\n<!-- top -->\n<ns:root a=\"1 &amp; 2\" b='q\"q'>\n  text &lt;here&gt; &#233;\n  <child/><![CDATA[<raw>]]><?pi some data?>\n</ns:root>\n"
    let (r0, e1) = open(a, doc, true, 8u16)
    if e1 != ok { os.exit(1) }
    var r = r0
    let (ev1, m1, e2) = xml.reader_next_err(&r)
    if e2 != ok || !m1 { os.exit(2) }
    switch ev1 {
    case .Comment as body:
        if !str.eq(body, " top ") { os.exit(3) }
    default:
        os.exit(4)
    }
    let (ev2, m2, e3) = xml.reader_next_err(&r)
    if e3 != ok { os.exit(5) }
    switch ev2 {
    case .Start as element:
        if !str.eq(element.name, "ns:root") || element.attributes.len != 2usize || element.empty { os.exit(6) }
        if !str.eq(element.attributes[0].name, "a") || !str.eq(element.attributes[0].value, "1 & 2") { os.exit(7) }
        if !str.eq(element.attributes[1].value, "q\"q") { os.exit(8) }
    default:
        os.exit(9)
    }
    let (ev3, m3, e4) = xml.reader_next_err(&r)
    if e4 != ok { os.exit(10) }
    switch ev3 {
    case .Text as text:
        if !str.eq(text, "\n  text <here> \xc3\xa9\n  ") { os.exit(11) }
    default:
        os.exit(12)
    }
    let (ev4, m4, e5) = xml.reader_next_err(&r)
    if e5 != ok { os.exit(13) }
    switch ev4 {
    case .Start as element:
        if !str.eq(element.name, "child") || !element.empty || element.attributes.len != 0usize { os.exit(14) }
    default:
        os.exit(15)
    }
    let (ev5, m5, e6) = xml.reader_next_err(&r)
    if e6 != ok { os.exit(16) }
    switch ev5 {
    case .End as name:
        if !str.eq(name, "child") { os.exit(17) }
    default:
        os.exit(18)
    }
    let (ev6, m6, e7) = xml.reader_next_err(&r)
    if e7 != ok { os.exit(19) }
    switch ev6 {
    case .Text as text:
        if !str.eq(text, "<raw>") { os.exit(20) }
    default:
        os.exit(21)
    }
    let (ev7, m7, e8) = xml.reader_next_err(&r)
    if e8 != ok { os.exit(22) }
    switch ev7 {
    case .Processing as pi:
        if !str.eq(pi.target, "pi") || !str.eq(pi.data, "some data") { os.exit(23) }
    default:
        os.exit(24)
    }
    let (ev8, m8, e9) = xml.reader_next_err(&r)
    if e9 != ok { os.exit(25) }
    switch ev8 {
    case .Text as text:
        if !str.eq(text, "\n") { os.exit(26) }
    default:
        os.exit(27)
    }
    let (ev9, m9, e10) = xml.reader_next_err(&r)
    if e10 != ok { os.exit(28) }
    switch ev9 {
    case .End as name:
        if !str.eq(name, "ns:root") { os.exit(29) }
    default:
        os.exit(30)
    }
    let (ev10, m10, e11) = xml.reader_next_err(&r)
    if e11 != ok || m10 { os.exit(31) }
    // Without comments there is one event fewer.
    let (n1, e12) = count_events(a, doc, 8u16)
    if e12 != ok || n1 != 8usize { os.exit(32) }
    // The writer, read back.
    var buffer: [256]u8 = zero
    var sink_state = io.SliceWriter { data: buffer[..], off: 0usize }
    var w = xml.writer(io.slice_writer(&sink_state))
    var attributes: [1]xml.Attribute = zero
    attributes[0] = xml.Attribute { name: "k", value: "a<b\"c" }
    if xml.start(&w, "doc", attributes[0..]) != ok { os.exit(33) }
    if xml.text(&w, "x & y > z") != ok { os.exit(34) }
    if xml.comment(&w, " note ") != ok { os.exit(35) }
    if xml.start(&w, "inner", zero) != ok || xml.end(&w, "inner") != ok { os.exit(36) }
    if xml.end(&w, "doc") != ok { os.exit(37) }
    if xml.end(&w, "doc") != xml.Invalid { os.exit(38) }
    if xml.comment(&w, "a--b") != xml.Invalid { os.exit(39) }
    let written = buffer[..sink_state.off]
    if !str.eq(written, "<doc k=\"a&lt;b&quot;c\">x &amp; y &gt; z<!-- note --><inner></inner></doc>") { os.exit(40) }
    let (back0, e13) = open(a, written, true, 8u16)
    if e13 != ok { os.exit(41) }
    var back = back0
    let (b1, bm1, e14) = xml.reader_next_err(&back)
    if e14 != ok { os.exit(42) }
    switch b1 {
    case .Start as element:
        if !str.eq(element.attributes[0].value, "a<b\"c") { os.exit(43) }
    default:
        os.exit(44)
    }
    let (b2, bm2, e15) = xml.reader_next_err(&back)
    if e15 != ok { os.exit(45) }
    switch b2 {
    case .Text as text:
        if !str.eq(text, "x & y > z") { os.exit(46) }
    default:
        os.exit(47)
    }
    // Refusals.
    let (c1, e16) = count_events(a, "<!DOCTYPE x><x/>", 8u16)
    if e16 != xml.Unsupported { os.exit(48) }
    let (c2, e17) = count_events(a, "<a><b></a></b>", 8u16)
    if e17 != xml.Invalid { os.exit(49) }
    let (c3, e18) = count_events(a, "<a><b></b>", 8u16)
    if e18 != xml.Invalid { os.exit(50) }
    let (c4, e19) = count_events(a, "<a x=1></a>", 8u16)
    if e19 != xml.Invalid { os.exit(51) }
    let (c5, e20) = count_events(a, "<a>&nbsp;</a>", 8u16)
    if e20 != xml.Unsupported { os.exit(52) }
    let (c6, e21) = count_events(a, "<a x=\"1\" x=\"2\"></a>", 8u16)
    if e21 != xml.Invalid { os.exit(53) }
    let (c7, e22) = count_events(a, "<a><b><c/></b></a>", 1u16)
    if e22 != xml.TooDeep { os.exit(54) }
    let (c8, e23) = count_events(a, "<a><b><c/></b></a>", 2u16)
    if e23 != ok || c8 != 6usize { os.exit(55) }
    let (c9, e24) = count_events(a, "<a></a><b></b>", 8u16)
    if e24 != xml.Invalid { os.exit(56) }
    ret ok
}
