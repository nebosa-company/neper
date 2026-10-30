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
    let comment_off = sink_state.off
    if xml.comment(&w, "x-") != xml.Invalid || sink_state.off != comment_off { os.exit(78) }
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
    let (c10, e25) = count_events(a, "<\xc3\xa9/>", 8u16)
    if e25 != ok || c10 != 2usize { os.exit(62) }
    let (_, e26) = count_events(a, "<1bad/>", 8u16)
    if e26 != xml.Invalid { os.exit(63) }
    let (_, e27) = count_events(a, "<a 1bad=\"x\"/>", 8u16)
    if e27 != xml.Invalid { os.exit(64) }
    let (_, e28) = count_events(a, "<\xc0\x80/>", 8u16)
    if e28 != xml.Invalid { os.exit(70) }
    var name_buffer: [64]u8 = zero
    var name_state = io.SliceWriter { data: name_buffer[..], off: 0usize }
    var name_writer = xml.writer(io.slice_writer(&name_state))
    if xml.start(&name_writer, "1bad", zero) != xml.Invalid || name_state.off != 0usize { os.exit(65) }
    var bad_attributes: [1]xml.Attribute = zero
    bad_attributes[0] = xml.Attribute { name: "bad name", value: "x" }
    if xml.start(&name_writer, "good", bad_attributes[..]) != xml.Invalid || name_state.off != 0usize { os.exit(66) }
    if xml.start(&name_writer, "good", zero) != ok { os.exit(67) }
    let opened = name_state.off
    if xml.end(&name_writer, "1bad") != xml.Invalid || name_state.off != opened { os.exit(68) }
    if xml.end(&name_writer, "other") != xml.Invalid || name_state.off != opened { os.exit(97) }
    if xml.end(&name_writer, "good") != ok { os.exit(69) }
    let options = xml.Options { max_depth: 8u16, preserve_comments: true }
    var input = io.SliceReader { data: "<a/>", off: 0usize }
    let (_, exact_error) = xml.reader_with_limit(a, io.slice_reader(&input), options, 4usize)
    if exact_error != ok { os.exit(57) }
    input.off = 0usize
    let (_, above_error) = xml.reader_with_limit(a, io.slice_reader(&input), options, 3usize)
    if above_error != xml.TooLarge { os.exit(58) }
    input.off = 0usize
    let (_, below_error) = xml.reader_with_limit(a, io.slice_reader(&input), options, 5usize)
    if below_error != ok { os.exit(59) }
    input.data = "<a/>x"
    input.off = 0usize
    let (_, trailing_error) = xml.reader_with_limit(a, io.slice_reader(&input), options, 4usize)
    if trailing_error != xml.TooLarge { os.exit(60) }
    let checkpoint = mem.mark(a)
    let (_, default_error) = xml.reader(a, io.Reader { ctx: zero, read: endless }, options)
    if default_error != xml.TooLarge || mem.mark(a) != checkpoint { os.exit(61) }
    let (_, e29) = count_events(a, "<a>&#1;</a>", 8u16)
    if e29 != xml.Invalid { os.exit(71) }
    let (_, e30) = count_events(a, "<a>&#xFFFE;</a>", 8u16)
    if e30 != xml.Invalid { os.exit(72) }
    let (_, e31) = count_events(a, "<a>\x01</a>", 8u16)
    if e31 != xml.Invalid { os.exit(73) }
    let (_, e32) = count_events(a, "<a>\x80</a>", 8u16)
    if e32 != xml.Invalid { os.exit(74) }
    let (_, e33) = count_events(a, "<a x=\"\x80\"/>", 8u16)
    if e33 != xml.Invalid { os.exit(75) }
    let (_, e34) = count_events(a, "<a><![CDATA[\x01]]></a>", 8u16)
    if e34 != xml.Invalid { os.exit(76) }
    let (zero_depth_count, zero_depth_error) = count_events(a, "<a><b/></a>", 0u16)
    if zero_depth_error != ok || zero_depth_count != 4usize { os.exit(77) }
    var zero_limit_input = io.SliceReader { data: "<a></a>", off: 0usize }
    let (zero_limit_reader0, zero_limit_open_error) = xml.reader_with_limit(a, io.slice_reader(&zero_limit_input), xml.Options { max_depth: 0u16, preserve_comments: false }, 7usize)
    if zero_limit_open_error != ok { os.exit(79) }
    var zero_limit_reader = zero_limit_reader0
    let (_, zero_limit_more, zero_limit_next_error) = xml.reader_next_err(&zero_limit_reader)
    if zero_limit_next_error != ok || !zero_limit_more { os.exit(80) }
    var attrs_buffer: [512]u8 = zero
    let attrs64 = attributes_document(attrs_buffer[..], 64usize)
    let (attrs64_count, attrs64_error) = count_events(a, attrs64, 8u16)
    if attrs64_error != ok || attrs64_count != 2usize { os.exit(81) }
    let attrs65 = attributes_document(attrs_buffer[..], 65usize)
    let (_, attrs65_error) = count_events(a, attrs65, 8u16)
    if attrs65_error != xml.TooLarge { os.exit(82) }
    var too_many_attributes: [65]xml.Attribute = zero
    var too_many_at = 0usize
    while too_many_at < too_many_attributes.len {
        too_many_attributes[too_many_at] = xml.Attribute { name: "a", value: "" }
        too_many_at += 1usize
    }
    var too_many_buffer: [64]u8 = zero
    var too_many_sink = io.SliceWriter { data: too_many_buffer[..], off: 0usize }
    var too_many_writer = xml.writer(io.slice_writer(&too_many_sink))
    if xml.start(&too_many_writer, "a", too_many_attributes[..]) != xml.TooLarge || too_many_sink.off != 0usize { os.exit(120) }
    let (_, text_close_error) = count_events(a, "<a>]]></a>", 8u16)
    if text_close_error != xml.Invalid { os.exit(83) }
    let (text_ref_count, text_ref_error) = count_events(a, "<a>]]&gt;</a>", 8u16)
    if text_ref_error != ok || text_ref_count != 3usize { os.exit(84) }
    let (_, comment_body_error) = count_events(a, "<a><!--a--b--></a>", 8u16)
    if comment_body_error != xml.Invalid { os.exit(85) }
    let (_, comment_end_error) = count_events(a, "<a><!--x---></a>", 8u16)
    if comment_end_error != xml.Invalid { os.exit(86) }
    let (declaration_count, declaration_error) = count_events(a, "<?xml version=\"1.0\" encoding='UTF-8' standalone=\"yes\"?><a/>", 8u16)
    if declaration_error != ok || declaration_count != 2usize { os.exit(87) }
    let (_, declaration_empty_error) = count_events(a, "<?xml?><a/>", 8u16)
    if declaration_empty_error != xml.Invalid { os.exit(88) }
    let (_, declaration_version_error) = count_events(a, "<?xml version=\"1.1\"?><a/>", 8u16)
    if declaration_version_error != xml.Invalid { os.exit(89) }
    let (_, declaration_value_error) = count_events(a, "<?xml version=\"1.0\" standalone=\"maybe\"?><a/>", 8u16)
    if declaration_value_error != xml.Invalid { os.exit(90) }
    let (_, declaration_misplaced_error) = count_events(a, "<a><?xml version=\"1.0\"?></a>", 8u16)
    if declaration_misplaced_error != xml.Invalid { os.exit(91) }
    let (_, declaration_after_misc_error) = count_events(a, "<!--before--><?xml version=\"1.0\"?><a/>", 8u16)
    if declaration_after_misc_error != xml.Invalid { os.exit(92) }
    let (_, reserved_pi_error) = count_events(a, "<?XML data?><a/>", 8u16)
    if reserved_pi_error != xml.Invalid { os.exit(93) }
    let (_, pi_separator_error) = count_events(a, "<a><?pi=data?></a>", 8u16)
    if pi_separator_error != xml.Invalid { os.exit(94) }
    let line_doc = "<a v=\"a\tb\nc\r\nd\re&#10;&#9;&#13;\">x\r\ny\rz&#13;<![CDATA[c\r\nd]]></a>"
    let (line_reader0, line_open_error) = open(a, line_doc, false, 8u16)
    if line_open_error != ok { os.exit(95) }
    var line_reader = line_reader0
    let (line_start, line_start_more, line_start_error) = xml.reader_next_err(&line_reader)
    if line_start_error != ok || !line_start_more { os.exit(96) }
    switch line_start {
    case .Start as element:
        if !str.eq(element.attributes[0].value, "a b c d e\n\t\r") { os.exit(98) }
    default:
        os.exit(99)
    }
    let (line_text, line_text_more, line_text_error) = xml.reader_next_err(&line_reader)
    if line_text_error != ok || !line_text_more { os.exit(100) }
    switch line_text {
    case .Text as value:
        if !str.eq(value, "x\ny\nz\r") { os.exit(101) }
    default:
        os.exit(102)
    }
    let (line_cdata, line_cdata_more, line_cdata_error) = xml.reader_next_err(&line_reader)
    if line_cdata_error != ok || !line_cdata_more { os.exit(103) }
    switch line_cdata {
    case .Text as value:
        if !str.eq(value, "c\nd") { os.exit(104) }
    default:
        os.exit(105)
    }
    var whitespace_buffer: [256]u8 = zero
    var whitespace_sink = io.SliceWriter { data: whitespace_buffer[..], off: 0usize }
    var whitespace_writer = xml.writer(io.slice_writer(&whitespace_sink))
    var whitespace_attribute: [1]xml.Attribute = zero
    whitespace_attribute[0] = xml.Attribute { name: "space", value: "a\tb\nc\rd" }
    if xml.start(&whitespace_writer, "ws", whitespace_attribute[..]) != ok { os.exit(106) }
    if xml.text(&whitespace_writer, "x\r\ny\rz") != ok { os.exit(107) }
    if xml.end(&whitespace_writer, "ws") != ok { os.exit(108) }
    if !str.eq(whitespace_buffer[..whitespace_sink.off], "<ws space=\"a&#9;b&#10;c&#13;d\">x&#13;\ny&#13;z</ws>") { os.exit(109) }
    let (whitespace_reader0, whitespace_open_error) = open(a, whitespace_buffer[..whitespace_sink.off], false, 8u16)
    if whitespace_open_error != ok { os.exit(110) }
    var whitespace_reader = whitespace_reader0
    let (whitespace_start, whitespace_start_more, whitespace_start_error) = xml.reader_next_err(&whitespace_reader)
    if whitespace_start_error != ok || !whitespace_start_more { os.exit(111) }
    switch whitespace_start {
    case .Start as element:
        if !str.eq(element.attributes[0].value, "a\tb\nc\rd") { os.exit(112) }
    default:
        os.exit(113)
    }
    let (whitespace_text, whitespace_text_more, whitespace_text_error) = xml.reader_next_err(&whitespace_reader)
    if whitespace_text_error != ok || !whitespace_text_more { os.exit(114) }
    switch whitespace_text {
    case .Text as value:
        if !str.eq(value, "x\r\ny\rz") { os.exit(115) }
    default:
        os.exit(116)
    }
    var invalid_buffer: [64]u8 = zero
    var invalid_sink = io.SliceWriter { data: invalid_buffer[..], off: 0usize }
    var invalid_writer = xml.writer(io.slice_writer(&invalid_sink))
    var invalid_attribute: [1]xml.Attribute = zero
    invalid_attribute[0] = xml.Attribute { name: "bad", value: "\x01" }
    if xml.start(&invalid_writer, "bad", invalid_attribute[..]) != xml.Invalid || invalid_sink.off != 0usize { os.exit(117) }
    if xml.text(&invalid_writer, "\x01") != xml.Invalid || invalid_sink.off != 0usize { os.exit(118) }
    if xml.comment(&invalid_writer, "\x0b") != xml.Invalid || invalid_sink.off != 0usize { os.exit(119) }
    ret ok
}

fn endless(ctx: *void, dst: []u8) -> (usize, err) {
    var at = 0usize
    while at < dst.len {
        dst[at] = 32u8
        at += 1usize
    }
    ret (dst.len, ok)
}

fn attributes_document(out: []u8, count: usize) -> str {
    var at = 0usize
    out[at] = 60u8
    at += 1usize
    out[at] = 97u8
    at += 1usize
    var index = 0usize
    while index < count {
        out[at] = 32u8
        at += 1usize
        out[at] = u8(97usize + index / 26usize)
        at += 1usize
        out[at] = u8(97usize + index % 26usize)
        at += 1usize
        out[at] = 61u8
        at += 1usize
        out[at] = 34u8
        at += 1usize
        out[at] = 34u8
        at += 1usize
        index += 1usize
    }
    out[at] = 47u8
    at += 1usize
    out[at] = 62u8
    at += 1usize
    ret out[..at]
}
