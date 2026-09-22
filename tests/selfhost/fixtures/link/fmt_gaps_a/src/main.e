// The planned names filled into seven `e.fmt` modules, each against a Python reference
// (scripts beside this fixture's scratch: pyasn1, cbor2, csv, html.parser, rfc8785, quopri,
// urllib): `asn1.der_encode` / `ber_decode`, `cbor.encode` / `decode`, `csv.writer` /
// `write_record`, `html.escape` / `unescape` / `tokenize`, `json.canonicalize` /
// `merge_patch` / `tokenizer`, `quoted_printable.encode`, `uri.query_parse` / `query_build`.
// Every check has its own exit code; a text mismatch prints what was produced first.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.asn1 as asn1
use e.fmt.cbor as cbor
use e.fmt.csv as csv
use e.fmt.html as html
use e.fmt.json as json
use e.fmt.quoted_printable as qp
use e.fmt.uri as uri

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// A mismatch prints the produced text, then exits with the check's code.
fn expect_text(got: []const u8, want: []const u8, code: i32) {
    if same(got, want) { ret }
    let _ = io.print("got: ")
    let _ = io.print(got)
    let _ = io.print("\n")
    os.exit(code)
}

fn canonical(a: *mem.Arena, source: str) -> (str, err) {
    var options: json.Options = zero
    let (value, parse_error) = json.parse(a, source, options)
    if parse_error != ok { ret ("", parse_error) }
    let (state, unused_sink, writer_error) = io.memory_writer(a, 4096usize)
    if writer_error != ok { ret ("", writer_error) }
    var held = state
    var out = io.writer(mem.cast[*void](&held), io.memory_write)
    let write_error = json.canonicalize(&out, &value)
    if write_error != ok { ret ("", write_error) }
    ret (io.memory_bytes(&held), ok)
}

fn merged_canonical(a: *mem.Arena, original: str, delta: str) -> (str, err) {
    var options: json.Options = zero
    let (base, base_error) = json.parse(a, original, options)
    if base_error != ok { ret ("", base_error) }
    let (change, change_error) = json.parse(a, delta, options)
    if change_error != ok { ret ("", change_error) }
    let (result, merge_error) = json.merge_patch(a, &base, &change)
    if merge_error != ok { ret ("", merge_error) }
    let (state, unused_sink, writer_error) = io.memory_writer(a, 4096usize)
    if writer_error != ok { ret ("", writer_error) }
    var held = state
    var out = io.writer(mem.cast[*void](&held), io.memory_write)
    let write_error = json.canonicalize(&out, &result)
    if write_error != ok { ret ("", write_error) }
    ret (io.memory_bytes(&held), ok)
}

fn item_count(item: asn1.Item) -> usize {
    switch item {
    case .Sequence as members:
        ret members.len
    case .Set as members:
        ret members.len
    case .Context as tagged:
        ret tagged.items.len
    default:
        ret 0usize
    }
}

fn item_integer(item: asn1.Item) -> i64 {
    switch item {
    case .Integer as number:
        ret number
    default:
        ret -1i64
    }
}

fn item_octets(item: asn1.Item) -> []const u8 {
    switch item {
    case .OctetString as data:
        ret data
    case .Utf8String as text:
        ret text
    default:
        ret ""
    }
}

fn item_bool(item: asn1.Item) -> bool {
    switch item {
    case .Bool as flag:
        ret flag
    default:
        ret false
    }
}

fn members_of(item: asn1.Item) -> []const asn1.Item {
    switch item {
    case .Sequence as members:
        ret members
    case .Set as members:
        ret members
    default:
        ret zero
    }
}

fn map_len(value: cbor.Value) -> usize {
    switch value {
    case .Map as pairs:
        ret pairs.len
    default:
        ret 0usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // --- asn1: the Item tree pyasn1 encoded, and a BER-only spelling read back.
    let der_want: [61]u8 = [61]u8{ 48, 59, 2, 2, 1, 2, 1, 1, 255, 4, 2, 104, 105, 2, 2, 255, 127, 5, 0, 6, 9, 42, 134, 72, 134, 247, 13, 1, 1, 11, 12, 6, 104, 195, 169, 108, 108, 111, 3, 4, 6, 110, 93, 192, 49, 10, 2, 1, 5, 2, 2, 1, 44, 4, 1, 97, 160, 3, 2, 1, 1 }
    let ber_source: [29]u8 = [29]u8{ 48, 128, 2, 4, 0, 0, 1, 2, 36, 128, 4, 2, 97, 98, 4, 2, 99, 100, 0, 0, 1, 1, 1, 2, 129, 1, 5, 0, 0 }
    var set_items: [3]asn1.Item = zero
    set_items[0] = asn1.Item{ Integer: 300i64 }
    set_items[1] = asn1.Item{ Integer: 5i64 }
    set_items[2] = asn1.Item{ OctetString: "a" }
    var ctx_items: [1]asn1.Item = zero
    ctx_items[0] = asn1.Item{ Integer: 1i64 }
    let oid: [7]u32 = [7]u32{ 1, 2, 840, 113549, 1, 1, 11 }
    let bits: [3]u8 = [3]u8{ 110, 93, 192 }
    var members: [10]asn1.Item = zero
    members[0] = asn1.Item{ Integer: 258i64 }
    members[1] = asn1.Item{ Bool: true }
    members[2] = asn1.Item{ OctetString: "hi" }
    members[3] = asn1.Item{ Integer: -129i64 }
    members[4] = .Null
    members[5] = asn1.Item{ Oid: oid[0..] }
    members[6] = asn1.Item{ Utf8String: "h\xc3\xa9llo" }
    members[7] = asn1.Item{ BitString: asn1.BitString { unused: 6u8, data: bits[0..] } }
    members[8] = asn1.Item{ Set: set_items[0..] }
    members[9] = asn1.Item{ Context: asn1.Context { number: 0u32, items: ctx_items[0..] } }
    let root = asn1.Item{ Sequence: members[0..] }
    var der_out: [128]u8 = zero
    let (der, e1) = asn1.der_encode(der_out[0..], &root)
    if e1 != ok { os.exit(1) }
    if !same(der, der_want[0..]) { os.exit(2) }
    // The strict reader walks what was written: one SEQUENCE of ten.
    var r = asn1.reader(der, 4u16)
    let (top, present, e3) = asn1.reader_next_err(&r)
    if e3 != ok || !present || !asn1.is_universal(top, 16u32, true) { os.exit(3) }
    let (inner0, e3b) = asn1.children(top, 4u16)
    if e3b != ok { os.exit(3) }
    var inner = inner0
    var walked = 0usize
    while true {
        let (child, more, child_error) = asn1.reader_next_err(&inner)
        if child_error != ok { os.exit(3) }
        if !more { break }
        walked += 1usize
    }
    if walked != 10usize { os.exit(3) }
    // BER accepts DER; the SET came back in sorted order.
    let (back, e4) = asn1.ber_decode(a, der, 8u16)
    if e4 != ok || item_count(back) != 10usize { os.exit(4) }
    let back_members = members_of(back)
    if item_integer(back_members[0]) != 258i64 || !item_bool(back_members[1]) || item_integer(back_members[3]) != -129i64 { os.exit(4) }
    if !same(item_octets(back_members[6]), "h\xc3\xa9llo") || item_count(back_members[8]) != 3usize || item_integer(members_of(back_members[8])[0]) != 5i64 || item_count(back_members[9]) != 1usize { os.exit(4) }
    // Indefinite length, a padded INTEGER, a constructed OCTET STRING, BOOLEAN 0x01, a long-form length.
    let (lenient, e5) = asn1.ber_decode(a, ber_source[0..], 8u16)
    if e5 != ok || item_count(lenient) != 4usize { os.exit(5) }
    let lenient_members = members_of(lenient)
    if item_integer(lenient_members[0]) != 258i64 || !same(item_octets(lenient_members[1]), "abcd") || !item_bool(lenient_members[2]) || item_integer(lenient_members[3]) != 5i64 { os.exit(5) }
    var strict = asn1.reader(ber_source[0..], 4u16)
    let (refused, refused_present, e6) = asn1.reader_next_err(&strict)
    if e6 != asn1.NonCanonical { os.exit(6) }

    // --- cbor: a nested value against cbor2's canonical bytes, and back.
    let cbor_want: [68]u8 = [68]u8{ 167, 1, 103, 105, 110, 116, 32, 107, 101, 121, 33, 244, 97, 97, 1, 97, 98, 136, 2, 3, 35, 249, 62, 0, 245, 246, 97, 120, 66, 1, 2, 97, 99, 26, 0, 1, 134, 160, 97, 100, 193, 26, 81, 75, 103, 176, 98, 97, 97, 162, 97, 121, 250, 71, 195, 80, 0, 97, 122, 251, 63, 185, 153, 153, 153, 153, 153, 154 }
    let blob: [2]u8 = [2]u8{ 1, 2 }
    var list: [8]cbor.Value = zero
    list[0] = cbor.Value{ Uint: 2u64 }
    list[1] = cbor.Value{ Uint: 3u64 }
    list[2] = cbor.Value{ Int: -4i64 }
    list[3] = cbor.Value{ Float: 1.5f64 }
    list[4] = cbor.Value{ Bool: true }
    list[5] = .Null
    list[6] = cbor.Value{ Text: "x" }
    list[7] = cbor.Value{ Bytes: blob[0..] }
    var nested: [2]cbor.Pair = zero
    nested[0] = cbor.Pair { key: cbor.Value{ Text: "z" }, value: cbor.Value{ Float: 0.1f64 } }
    nested[1] = cbor.Pair { key: cbor.Value{ Text: "y" }, value: cbor.Value{ Float: 100000.0f64 } }
    var tagged_item: [1]cbor.Value = zero
    tagged_item[0] = cbor.Value{ Uint: 1363896240u64 }
    var pairs: [7]cbor.Pair = zero
    pairs[0] = cbor.Pair { key: cbor.Value{ Text: "a" }, value: cbor.Value{ Uint: 1u64 } }
    pairs[1] = cbor.Pair { key: cbor.Value{ Text: "b" }, value: cbor.Value{ Array: list[0..] } }
    pairs[2] = cbor.Pair { key: cbor.Value{ Uint: 1u64 }, value: cbor.Value{ Text: "int key" } }
    pairs[3] = cbor.Pair { key: cbor.Value{ Text: "aa" }, value: cbor.Value{ Map: nested[0..] } }
    pairs[4] = cbor.Pair { key: cbor.Value{ Text: "c" }, value: cbor.Value{ Uint: 100000u64 } }
    pairs[5] = cbor.Pair { key: cbor.Value{ Text: "d" }, value: cbor.Value{ Tagged: cbor.Tagged { tag: 1u64, items: tagged_item[0..] } } }
    pairs[6] = cbor.Pair { key: cbor.Value{ Int: -2i64 }, value: cbor.Value{ Bool: false } }
    let cbor_root = cbor.Value{ Map: pairs[0..] }
    var cbor_out: [128]u8 = zero
    var enc = cbor.encoder(cbor_out[0..])
    if cbor.encode(&enc, &cbor_root) != ok { os.exit(7) }
    if !same(cbor.encoded(&enc), cbor_want[0..]) { os.exit(8) }
    var dec = cbor.decoder(cbor.encoded(&enc))
    let (cbor_back, e9) = cbor.decode(a, &dec, 8u16)
    if e9 != ok || dec.at != cbor_want.len || map_len(cbor_back) != 7usize { os.exit(9) }
    var cbor_again: [128]u8 = zero
    var enc2 = cbor.encoder(cbor_again[0..])
    if cbor.encode(&enc2, &cbor_back) != ok || !same(cbor.encoded(&enc2), cbor_want[0..]) { os.exit(10) }

    // --- csv: the writer against Python's excel dialect, read back by the reader.
    let csv_want = "a,b c,\"d,e\"\x0d\x0a\"quote\"\"d\",\"line\x0abreak\",\x0d\x0ax,,\"y\x0d\"\x0d\x0a"
    var csv_buffer: [128]u8 = zero
    var csv_sink: io.SliceWriter = zero
    csv_sink.data = csv_buffer[0..]
    var dialect = csv.csv()
    dialect.crlf = true
    let (w0, e11) = csv.writer(io.slice_writer(&csv_sink), dialect)
    if e11 != ok { os.exit(11) }
    var w = w0
    var row1: [3]str = zero
    row1[0] = "a"
    row1[1] = "b c"
    row1[2] = "d,e"
    var row2: [3]str = zero
    row2[0] = "quote\"d"
    row2[1] = "line\nbreak"
    row2[2] = ""
    var row3: [3]str = zero
    row3[0] = "x"
    row3[1] = ""
    row3[2] = "y\r"
    if csv.write_record(&w, row1[0..]) != ok || csv.write_record(&w, row2[0..]) != ok || csv.write_record(&w, row3[0..]) != ok { os.exit(11) }
    expect_text(csv_buffer[..csv_sink.off], csv_want, 12i32)
    var csv_source: io.SliceReader = zero
    csv_source.data = csv_buffer[..csv_sink.off]
    let (reader0, e13) = csv.reader(a, io.slice_reader(&csv_source), dialect, 0usize, 0usize)
    if e13 != ok { os.exit(13) }
    var csv_reader = reader0
    let (first, first_more, e13b) = csv.reader_next_err(&csv_reader)
    if e13b != ok || !first_more || first.fields.len != 3usize || !str.eq(first.fields[2], "d,e") { os.exit(13) }
    let (second, second_more, e13c) = csv.reader_next_err(&csv_reader)
    if e13c != ok || !second_more || !str.eq(second.fields[0], "quote\"d") || !str.eq(second.fields[1], "line\nbreak") || second.fields[2].len != 0usize { os.exit(13) }
    let (third, third_more, e13d) = csv.reader_next_err(&csv_reader)
    if e13d != ok || !third_more || third.fields[1].len != 0usize || !str.eq(third.fields[2], "y\r") { os.exit(13) }
    let (none, none_more, e13e) = csv.reader_next_err(&csv_reader)
    if e13e != ok || none_more { os.exit(13) }

    // --- html: entities and the token stream against html.escape/unescape and HTMLParser.
    let escape_want = "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#x27;s&lt;/a&gt;"
    let unescape_want = "<p> &amp; \xc2\xa9 \xc2\xa9 A \xc2\xacanentity;"
    let html_doc = "<!DOCTYPE html>\x0a<html><head><title>T &amp; U</title></head>\x0a<body class=\"main\" ID=x data-v='a&lt;b'><!-- note --><p>Hi &copy; there<br/>x</p><img src=\"i.png\"><script>if (a < b) {}</script></body></html>"
    let html_token_count = 22usize
    let html_fold = "D:html|T:\x0a|S:html|S:head|S:title|T:T & U|E:title|E:head|T:\x0a|S:body class=main id=x data-v=a<b|C: note |S:p|T:Hi \xc2\xa9 there|S/:br|T:x|E:p|S:img src=i.png|S:script|T:if (a < b) {}|E:script|E:body|E:html|"
    let (escaped, e14) = html.escape(a, "<a href=\"x\">Tom & Jerry's</a>")
    if e14 != ok { os.exit(14) }
    expect_text(escaped, escape_want, 14i32)
    let (unescaped, e15) = html.unescape(a, "&lt;p&gt; &amp;amp; &#169; &copy &#x41; &notanentity;")
    if e15 != ok { os.exit(15) }
    expect_text(unescaped, unescape_want, 15i32)
    var tokens: [32]html.Token = zero
    let (token_count, e16) = html.tokenize(a, html_doc, tokens[0..])
    if e16 != ok || token_count != html_token_count { os.exit(16) }
    var fold_buffer: [512]u8 = zero
    var fold_sink: io.SliceWriter = zero
    fold_sink.data = fold_buffer[0..]
    var fold = io.slice_writer(&fold_sink)
    var t = 0usize
    while t < token_count {
        let token = tokens[t]
        if token.kind == .Doctype { try io.write_all(&fold, "D:") }
        if token.kind == .Text { try io.write_all(&fold, "T:") }
        if token.kind == .Comment { try io.write_all(&fold, "C:") }
        if token.kind == .EndTag { try io.write_all(&fold, "E:") }
        if token.kind == .StartTag {
            if token.self_closing { try io.write_all(&fold, "S/:") } else { try io.write_all(&fold, "S:") }
        }
        try io.write_all(&fold, token.name)
        try io.write_all(&fold, token.value)
        var k = 0usize
        while k < token.attributes.len {
            try io.write_all(&fold, " ")
            try io.write_all(&fold, token.attributes[k].name)
            try io.write_all(&fold, "=")
            try io.write_all(&fold, token.attributes[k].value)
            k += 1usize
        }
        try io.write_all(&fold, "|")
        t += 1usize
    }
    expect_text(fold_buffer[..fold_sink.off], html_fold, 17i32)

    // --- json: RFC 8785's example and two more against rfc8785, the RFC 7396 table, the tokenizer.
    let jcs_source = "{\"numbers\": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001], \"string\": \"\\u20ac$\\u000F\\u000aA'\\u0042\\u0022\\u005c\\\\\\\"\\/\", \"literals\": [null, true, false]}"
    let jcs_want = "{\"literals\":[null,true,false],\"numbers\":[333333333.3333333,1e+30,4.5,0.002,1e-27],\"string\":\"\xe2\x82\xac$\\u000f\\nA'B\\\"\\\\\\\\\\\"/\"}"
    let jcs_surrogate_source = "{\"\\uFFFD\": 1, \"\\ud83d\\ude00\": 2, \"b\": [10, 1e21, 1e-7, 0.000001, -0.0, 1.2345678901234568e20, 5e-324]}"
    let jcs_surrogate_want = "{\"b\":[10,1e+21,1e-7,0.000001,0,123456789012345680000,5e-324],\"\xf0\x9f\x98\x80\":2,\"\xef\xbf\xbd\":1}"
    let jcs_plain_source = "{\"zeta\": [1, 2, {\"k\": \"v\"}], \"alpha\": \"x\\ty\", \"Beta\": -5, \"b\": null}"
    let jcs_plain_want = "{\"Beta\":-5,\"alpha\":\"x\\ty\",\"b\":null,\"zeta\":[1,2,{\"k\":\"v\"}]}"
    let (jcs, e18) = canonical(a, jcs_source)
    if e18 != ok { os.exit(18) }
    expect_text(jcs, jcs_want, 18i32)
    let (jcs_surrogate, e19) = canonical(a, jcs_surrogate_source)
    if e19 != ok { os.exit(19) }
    expect_text(jcs_surrogate, jcs_surrogate_want, 19i32)
    let (jcs_plain, e20) = canonical(a, jcs_plain_source)
    if e20 != ok { os.exit(20) }
    expect_text(jcs_plain, jcs_plain_want, 20i32)
    var merge_original: [15]str = zero
    var merge_delta: [15]str = zero
    var merge_want: [15]str = zero
    merge_original[0usize] = "{\"a\":\"b\"}"
    merge_delta[0usize] = "{\"a\":\"c\"}"
    merge_want[0usize] = "{\"a\":\"c\"}"
    merge_original[1usize] = "{\"a\":\"b\"}"
    merge_delta[1usize] = "{\"b\":\"c\"}"
    merge_want[1usize] = "{\"a\":\"b\",\"b\":\"c\"}"
    merge_original[2usize] = "{\"a\":\"b\"}"
    merge_delta[2usize] = "{\"a\":null}"
    merge_want[2usize] = "{}"
    merge_original[3usize] = "{\"a\":\"b\",\"b\":\"c\"}"
    merge_delta[3usize] = "{\"a\":null}"
    merge_want[3usize] = "{\"b\":\"c\"}"
    merge_original[4usize] = "{\"a\":[\"b\"]}"
    merge_delta[4usize] = "{\"a\":\"c\"}"
    merge_want[4usize] = "{\"a\":\"c\"}"
    merge_original[5usize] = "{\"a\":\"c\"}"
    merge_delta[5usize] = "{\"a\":[\"b\"]}"
    merge_want[5usize] = "{\"a\":[\"b\"]}"
    merge_original[6usize] = "{\"a\":{\"b\":\"c\"}}"
    merge_delta[6usize] = "{\"a\":{\"b\":\"d\",\"c\":null}}"
    merge_want[6usize] = "{\"a\":{\"b\":\"d\"}}"
    merge_original[7usize] = "{\"a\":[{\"b\":\"c\"}]}"
    merge_delta[7usize] = "{\"a\":[1]}"
    merge_want[7usize] = "{\"a\":[1]}"
    merge_original[8usize] = "[\"a\",\"b\"]"
    merge_delta[8usize] = "[\"c\",\"d\"]"
    merge_want[8usize] = "[\"c\",\"d\"]"
    merge_original[9usize] = "{\"a\":\"b\"}"
    merge_delta[9usize] = "[\"c\"]"
    merge_want[9usize] = "[\"c\"]"
    merge_original[10usize] = "{\"a\":\"foo\"}"
    merge_delta[10usize] = "null"
    merge_want[10usize] = "null"
    merge_original[11usize] = "{\"a\":\"foo\"}"
    merge_delta[11usize] = "\"bar\""
    merge_want[11usize] = "\"bar\""
    merge_original[12usize] = "{\"e\":null}"
    merge_delta[12usize] = "{\"a\":1}"
    merge_want[12usize] = "{\"a\":1,\"e\":null}"
    merge_original[13usize] = "[1,2]"
    merge_delta[13usize] = "{\"a\":\"b\",\"c\":null}"
    merge_want[13usize] = "{\"a\":\"b\"}"
    merge_original[14usize] = "{}"
    merge_delta[14usize] = "{\"a\":{\"bb\":{\"ccc\":null}}}"
    merge_want[14usize] = "{\"a\":{\"bb\":{}}}"
    var row = 0usize
    while row < 15usize {
        let (merged, merge_error) = merged_canonical(a, merge_original[row], merge_delta[row])
        if merge_error != ok || !same(merged, merge_want[row]) {
            let _ = io.print("merge row: ")
            let _ = io.print(merged)
            let _ = io.print("\n")
            os.exit(21)
        }
        row += 1usize
    }
    let tok_doc = " {\"a\": [1, -2.5e3, true, false, null, \"s\\\"q\"], \"b\": {}} "
    let tok_count = 22usize
    let tok_fold = "{|\"a\"|:|[|1|,|-2.5e3|,|true|,|false|,|null|,|\"s\\\"q\"|]|,|\"b\"|:|{|}|}|"
    var tok_buffer: [256]u8 = zero
    var tok_sink: io.SliceWriter = zero
    tok_sink.data = tok_buffer[0..]
    var tok_out = io.slice_writer(&tok_sink)
    var lexer = json.tokenizer(tok_doc)
    var counted = 0usize
    var kinds = 0usize
    while true {
        let (kind, lexeme, token_error) = json.next_token(&lexer)
        if token_error != ok { os.exit(22) }
        if kind == .End { break }
        if kind == .String || kind == .Number || kind == .True || kind == .False || kind == .Null { kinds += 1usize }
        try io.write_all(&tok_out, lexeme)
        try io.write_all(&tok_out, "|")
        counted += 1usize
    }
    if counted != tok_count || kinds != 8usize { os.exit(22) }
    expect_text(tok_buffer[..tok_sink.off], tok_fold, 23i32)
    var bad_lexer = json.tokenizer("[1, tru]")
    var bad_seen = 0usize
    while true {
        let (kind, lexeme, token_error) = json.next_token(&bad_lexer)
        if token_error != ok { break }
        if kind == .End { os.exit(24) }
        bad_seen += 1usize
    }
    if bad_seen != 3usize { os.exit(24) }

    // --- quoted-printable: `encode` against quopri.encodestring, decoded back by the reader.
    let qp_source: [113]u8 = [113]u8{ 104, 195, 169, 108, 108, 111, 32, 61, 32, 119, 195, 182, 114, 108, 100, 32, 13, 10, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 32, 13, 10, 116, 97, 98, 9, 13, 10, 101, 110, 100, 32, 1, 255 }
    let qp_want: [136]u8 = [136]u8{ 104, 61, 67, 51, 61, 65, 57, 108, 108, 111, 32, 61, 51, 68, 32, 119, 61, 67, 51, 61, 66, 54, 114, 108, 100, 61, 50, 48, 13, 10, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 61, 13, 10, 97, 97, 97, 97, 97, 61, 50, 48, 13, 10, 116, 97, 98, 61, 48, 57, 13, 10, 101, 110, 100, 32, 61, 48, 49, 61, 70, 70 }
    var qp_out: [256]u8 = zero
    let (qp_encoded, e25) = qp.encode(qp_out[0..], qp_source[0..])
    if e25 != ok { os.exit(25) }
    expect_text(qp_encoded, qp_want[0..], 26i32)
    var qp_state: io.SliceReader = zero
    qp_state.data = qp_encoded
    var qp_storage: [128]u8 = zero
    var qp_reader = qp.reader(qp_storage[0..], io.slice_reader(&qp_state))
    var qp_decoded: [160]u8 = zero
    var qp_total = 0usize
    while true {
        let (count, read_error) = qp.read(&qp_reader, qp_decoded[qp_total..])
        if read_error == io.End { break }
        if read_error != ok { os.exit(27) }
        qp_total += count
    }
    if !same(qp_decoded[..qp_total], qp_source[0..]) { os.exit(27) }

    // --- uri: the form pairs against parse_qsl and urlencode.
    let query_source = "a=1&b=hello+world&a=%E2%9C%93&c&&d=x%3Dy"
    let query_count = 5usize
    let query_fold = "a=1|b=hello world|a=\xe2\x9c\x93|c=|d=x=y|"
    let build_want = "q=a+b%26c&t=~x%2Fy_z-1.2&%C3%A9=%C3%BC&empty="
    var keys: [8]str = zero
    var values: [8]str = zero
    let (pair_count, e28) = uri.query_parse(a, query_source, keys[0..], values[0..])
    if e28 != ok || pair_count != query_count { os.exit(28) }
    var query_buffer: [128]u8 = zero
    var query_sink: io.SliceWriter = zero
    query_sink.data = query_buffer[0..]
    var query_out = io.slice_writer(&query_sink)
    var q = 0usize
    while q < pair_count {
        try io.write_all(&query_out, keys[q])
        try io.write_all(&query_out, "=")
        try io.write_all(&query_out, values[q])
        try io.write_all(&query_out, "|")
        q += 1usize
    }
    expect_text(query_buffer[..query_sink.off], query_fold, 29i32)
    var tiny_keys: [2]str = zero
    var tiny_values: [2]str = zero
    let (tiny_count, e30) = uri.query_parse(a, query_source, tiny_keys[0..], tiny_values[0..])
    if e30 != uri.TooSmall || tiny_count != 2usize { os.exit(30) }
    let (bad_count, e31) = uri.query_parse(a, "a=%zz", keys[0..], values[0..])
    if e31 != uri.Invalid { os.exit(31) }
    var build_keys: [4]str = zero
    var build_values: [4]str = zero
    build_keys[0] = "q"
    build_values[0] = "a b&c"
    build_keys[1] = "t"
    build_values[1] = "~x/y_z-1.2"
    build_keys[2] = "\xc3\xa9"
    build_values[2] = "\xc3\xbc"
    build_keys[3] = "empty"
    build_values[3] = ""
    let (built, e32) = uri.query_build(a, build_keys[0..], build_values[0..])
    if e32 != ok { os.exit(32) }
    expect_text(built, build_want, 33i32)
    // The pair the builder wrote reads back as it was given.
    let (again_count, e34) = uri.query_parse(a, built, keys[0..], values[0..])
    if e34 != ok || again_count != 4usize || !str.eq(values[0], "a b&c") || !str.eq(keys[2], "\xc3\xa9") || values[3].len != 0usize { os.exit(34) }
    try io.print("fmt gaps a ok\n")
    ret ok
}
