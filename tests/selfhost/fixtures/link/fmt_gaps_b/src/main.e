// The planned names added across four `e.fmt.*` modules: `xml.stream` walking a
// namespaced document, `xml.parse` building its tree, `xml.namespaces` resolving
// prefixes through the scopes, `xml.xpath` answering ten paths matched against
// ElementTree; `protobuf.decode` listing a hand-built message's seven fields and
// `encode` writing them back byte for byte; `lzw.encode` matching the fixture's
// independent Python encoder by length and FNV-1a; `zstd.encode` producing frames the
// module's decoder restores and whose bytes python-zstandard validated (reference.py
// in the scratch directory). Each check exits with its own code.
use e.algo.hash as hash
use e.fmt.lzw as lzw
use e.fmt.protobuf as pb
use e.fmt.xml as xml
use e.fmt.zstd as zstd
use e.io
use e.mem
use e.os
use e.str

fn bytes_equal(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn lcg(out: []u8, seed: u64) {
    var state = seed
    var i = 0usize
    while i < out.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        out[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
}

// A text of words picked by the LCG, the one the scratch dump program wrote.
fn fill_words(text: []u8) {
    let words = "zstandard frame block sequence literal offset checksum neper huffman fse window repeat "
    var i = 0usize
    var state = 7u64
    while i < text.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let pick = usize((state >> 33u32) % 12u64)
        var w = 0usize
        var from = 0usize
        var j = 0usize
        while j < words.len {
            if words[j] == 32u8 {
                if w == pick {
                    var k = from
                    while k <= j && i < text.len {
                        text[i] = words[k]
                        i += 1usize
                        k += 1usize
                    }
                }
                w += 1usize
                from = j + 1usize
            }
            j += 1usize
        }
    }
}

fn count_of(a: *mem.Arena, document: *const xml.Document, path: str) -> usize {
    let (ids, path_error) = xml.xpath(a, document, document.root, path)
    if path_error != ok { ret 9999usize }
    ret ids.len
}

fn first_of(a: *mem.Arena, document: *const xml.Document, path: str) -> xml.NodeId {
    let (ids, path_error) = xml.xpath(a, document, document.root, path)
    if path_error != ok || ids.len == 0usize { ret xml.NONE }
    ret ids[0]
}

fn check_zstd(a: *mem.Arena, src: []const u8, want_len: usize, want_hash: u64, code: i32) {
    let (frame, encode_error) = zstd.encode(a, src, .Balanced)
    if encode_error != ok { os.exit(code) }
    if frame.len != want_len || hash.fnv1a64(frame) != want_hash { os.exit(code + 1i32) }
    let (back, decode_error) = zstd.decode(a, frame, 10000000u64)
    if decode_error != ok || !bytes_equal(back, src) { os.exit(code + 2i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // --- xml: the stream, then the tree.
    let doc = "<?xml version=\"1.0\"?><lib xmlns=\"urn:lib\" xmlns:m=\"urn:meta\"><!-- c --><book id=\"1\" lang=\"en\"><title>Alpha</title><m:note>n1</m:note><price>10</price></book><book id=\"2\"><title>Beta &amp; Co</title><price>20</price><price>21</price></book><shelf><book id=\"3\"><title>Gamma</title></book></shelf><plain xmlns=\"\"><q xml:lang=\"fr\"/></plain><?pi data?></lib>"
    let (s0, e1) = xml.stream(a, doc, xml.Options { max_depth: 8u16, preserve_comments: true })
    if e1 != ok { os.exit(1) }
    var s = s0
    let (ns0, e2) = xml.namespaces(a, 16usize, 8usize)
    if e2 != ok { os.exit(2) }
    var ns = ns0
    var events = 0usize
    var notes = 0usize
    while true {
        let (event, more, next_error) = xml.stream_next(&s)
        if next_error != ok { os.exit(3) }
        if !more { break }
        events += 1usize
        switch event {
        case .Start as element:
            if xml.namespaces_push(&ns, element.attributes) != ok { os.exit(4) }
            let (uri, local, expand_error) = xml.expand(&ns, element.name)
            if expand_error != ok { os.exit(5) }
            if str.eq(element.name, "m:note") {
                notes += 1usize
                if !str.eq(uri, "urn:meta") || !str.eq(local, "note") { os.exit(6) }
            }
            if str.eq(element.name, "book") && !str.eq(uri, "urn:lib") { os.exit(7) }
            if str.eq(element.name, "q") {
                if uri.len != 0usize { os.exit(8) }
                let (lang_uri, lang, lang_error) = xml.expand(&ns, "xml:lang")
                if lang_error != ok || !str.eq(lang_uri, "http://www.w3.org/XML/1998/namespace") || !str.eq(lang, "lang") { os.exit(9) }
                let (_, _, bad_error) = xml.expand(&ns, "nope:x")
                if bad_error != xml.Invalid { os.exit(10) }
            }
        case .End as name:
            if xml.namespaces_pop(&ns) != ok { os.exit(11) }
        default:
            notes += 0usize
        }
    }
    if events != 37usize || notes != 1usize { os.exit(12) }
    let (_, after_error) = xml.resolve(&ns, "m")
    if after_error != xml.Invalid || xml.namespaces_pop(&ns) != xml.Invalid { os.exit(13) }
    var bad_attributes: [1]xml.Attribute = zero
    bad_attributes[0] = xml.Attribute { name: "xmlns:p", value: "" }
    if xml.namespaces_push(&ns, bad_attributes[0..]) != xml.Invalid { os.exit(14) }
    let (tree, e3) = xml.parse(a, doc)
    if e3 != ok { os.exit(15) }
    if tree.nodes.len != 24usize || tree.root != 1u32 || !str.eq(tree.nodes[1].name, "lib") { os.exit(16) }
    if tree.nodes[0].kind != .Document || tree.nodes[2].kind != .Comment || !str.eq(tree.nodes[2].value, " c ") { os.exit(17) }
    let (lib_ns, has_lib_ns) = xml.attribute(&tree.nodes[1], "xmlns")
    if !has_lib_ns || !str.eq(lib_ns, "urn:lib") { os.exit(18) }
    if tree.nodes[usize(tree.nodes[1].last_child)].kind != .Processing { os.exit(19) }
    let (_, e4) = xml.parse(a, "<!DOCTYPE x><x/>")
    if e4 != xml.Unsupported { os.exit(20) }
    let (_, e5) = xml.parse(a, "<a><b></a>")
    if e5 != xml.Invalid { os.exit(21) }
    // --- xpath, against ElementTree.
    if count_of(a, &tree, "/lib/book") != 2usize { os.exit(22) }
    if count_of(a, &tree, "//book") != 3usize { os.exit(23) }
    let gamma_title = first_of(a, &tree, "//book[@id='3']/title")
    if gamma_title == xml.NONE || count_of(a, &tree, "//book[@id='3']/title") != 1usize { os.exit(24) }
    if !str.eq(tree.nodes[usize(tree.nodes[usize(gamma_title)].first_child)].value, "Gamma") { os.exit(25) }
    if count_of(a, &tree, "/lib/book[2]/price") != 2usize { os.exit(26) }
    let gamma_book = first_of(a, &tree, "//book[title='Gamma']")
    if gamma_book == xml.NONE || count_of(a, &tree, "//book[title='Gamma']") != 1usize { os.exit(27) }
    let (gamma_id, has_gamma_id) = xml.attribute(&tree.nodes[usize(gamma_book)], "id")
    if !has_gamma_id || !str.eq(gamma_id, "3") { os.exit(28) }
    if count_of(a, &tree, "//*") != 14usize { os.exit(29) }
    if count_of(a, &tree, "//book[@lang]") != 1usize { os.exit(30) }
    let (firsts, e6) = xml.xpath(a, &tree, tree.root, "//book[1]")
    if e6 != ok || firsts.len != 2usize { os.exit(31) }
    let (first_id, _) = xml.attribute(&tree.nodes[usize(firsts[0])], "id")
    let (second_id, _) = xml.attribute(&tree.nodes[usize(firsts[1])], "id")
    if !str.eq(first_id, "1") || !str.eq(second_id, "3") { os.exit(32) }
    let parent = first_of(a, &tree, "//shelf/..")
    if parent != tree.root || count_of(a, &tree, "//shelf/..") != 1usize { os.exit(33) }
    let (prices, e7) = xml.xpath(a, &tree, tree.root, "book/price/text()")
    if e7 != ok || prices.len != 3usize || !str.eq(tree.nodes[usize(prices[0])].value, "10") || !str.eq(tree.nodes[usize(prices[2])].value, "21") { os.exit(34) }
    if count_of(a, &tree, "child::book") != 2usize || count_of(a, &tree, "./shelf/book") != 1usize { os.exit(35) }
    if count_of(a, &tree, "//book[@id='2']/@id") != 1usize || count_of(a, &tree, "//book/@lang") != 1usize { os.exit(36) }
    if count_of(a, &tree, "//title[@id]") != 0usize || count_of(a, &tree, "/descendant-or-self::node()/title") != 3usize { os.exit(37) }
    let (_, e8) = xml.xpath(a, &tree, tree.root, "book[")
    if e8 != xml.Invalid { os.exit(38) }
    // --- protobuf: the hand-built message decoded, then re-encoded.
    let msg: [38]u8 = [38]u8{ 8, 172, 2, 18, 2, 104, 105, 24, 9, 37, 68, 51, 34, 17, 41, 1, 0, 0, 0, 0, 1, 0, 0, 50, 2, 8, 7, 56, 128, 128, 128, 128, 128, 128, 128, 128, 128, 1 }
    var fields: [8]pb.Field = zero
    let (count, e9) = pb.decode(msg[0..], fields[0..])
    if e9 != ok || count != 7usize { os.exit(40) }
    if fields[0].number != 1u32 || fields[0].wire != .Varint || fields[0].varint != 300u64 { os.exit(41) }
    if fields[1].wire != .Bytes || !str.eq(fields[1].data, "hi") { os.exit(42) }
    if fields[2].varint != 9u64 || pb.decode_zigzag(fields[2].varint) != -5i64 { os.exit(43) }
    if fields[3].wire != .Fixed32 || fields[3].fixed != 287454020u64 { os.exit(44) }
    if fields[4].wire != .Fixed64 || fields[4].fixed != 1099511627777u64 { os.exit(45) }
    if fields[5].number != 6u32 || fields[5].data.len != 2usize { os.exit(46) }
    var inner: [2]pb.Field = zero
    let (inner_count, e10) = pb.decode(fields[5].data, inner[0..])
    if e10 != ok || inner_count != 1usize || inner[0].varint != 7u64 { os.exit(47) }
    if fields[6].number != 7u32 || fields[6].varint != 9223372036854775808u64 { os.exit(48) }
    let (v, used, e11) = pb.decode_varint(msg[1..])
    if e11 != ok || v != 300u64 || used != 2usize { os.exit(49) }
    if pb.decode_zigzag(0u64) != 0i64 || pb.decode_zigzag(1u64) != -1i64 || pb.decode_zigzag(2u64) != 1i64 || pb.encode_zigzag(-5i64) != 9u64 { os.exit(50) }
    var out_buffer: [64]u8 = zero
    var out_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var w = io.slice_writer(&out_state)
    if pb.encode(&w, fields[..count]) != ok || !bytes_equal(out_buffer[..out_state.off], msg[0..]) { os.exit(51) }
    var one: [1]pb.Field = zero
    let (_, e12) = pb.decode(msg[0..], one[0..])
    if e12 != io.TooSmall { os.exit(52) }
    let (_, e13) = pb.decode(msg[..5], fields[0..])
    if e13 != pb.Invalid { os.exit(53) }
    // --- lzw: the whole-buffer forms against the independent encoder's bytes.
    let text = "TOBEORNOTTOBEORTOBEORNOT#TOBEORNOTTOBEORTOBEORNOT"
    let (lsb, e14) = lzw.encode(a, text, .LeastSignificant, 8u8)
    if e14 != ok || lsb.len != 32usize || hash.fnv1a64(lsb) != 10312578086233058210u64 { os.exit(60) }
    let (msb, e15) = lzw.encode(a, text, .MostSignificant, 8u8)
    if e15 != ok || msb.len != 32usize || hash.fnv1a64(msb) != 16459588534279055608u64 { os.exit(61) }
    let (back_lsb, e16) = lzw.decode(a, lsb, .LeastSignificant, 8u8, 1024u64)
    if e16 != ok || !str.eq(back_lsb, text) { os.exit(62) }
    let (long, long_error) = mem.alloc[u8](a, 20000usize)
    if long_error != ok { os.exit(63) }
    var i = 0usize
    var state = 12345u32
    while i < 20000usize {
        state = state *% 1103515245u32 +% 12345u32
        long[i] = u8((state >> 16u32) & 255u32)
        i += 1usize
    }
    let (long_msb, e17) = lzw.encode(a, long, .MostSignificant, 8u8)
    if e17 != ok || long_msb.len != 27377usize || hash.fnv1a64(long_msb) != 3928266707501397863u64 { os.exit(64) }
    let (back_long, e18) = lzw.decode(a, long_msb, .MostSignificant, 8u8, 1048576u64)
    if e18 != ok || !bytes_equal(back_long, long) { os.exit(65) }
    let (_, e19) = lzw.decode(a, long_msb, .MostSignificant, 8u8, 100u64)
    if e19 != lzw.TooLarge { os.exit(66) }
    let (_, e20) = lzw.encode(a, text, .LeastSignificant, 9u8)
    if e20 != lzw.Invalid { os.exit(67) }
    // --- zstd: the frames python-zstandard decompressed, restored by the module.
    let (words, words_error) = mem.alloc[u8](a, 300000usize)
    if words_error != ok { os.exit(70) }
    fill_words(words)
    check_zstd(a, words, 90045usize, 6904117544488957939u64, 71i32)
    let (mixed, mixed_error) = mem.alloc[u8](a, 50000usize)
    if mixed_error != ok { os.exit(74) }
    lcg(mixed[..20000], 1u64)
    mem.copy[u8](mixed[20000..40000], mixed[..20000])
    lcg(mixed[40000..], 2u64)
    check_zstd(a, mixed, 30033usize, 454125219285113356u64, 75i32)
    let (noise, noise_error) = mem.alloc[u8](a, 140000usize)
    if noise_error != ok { os.exit(78) }
    lcg(noise, 3u64)
    check_zstd(a, noise, 140020usize, 10118016636890121015u64, 79i32)
    check_zstd(a, "hello hello hello hello zstd", 33usize, 12453854251461963624u64, 82i32)
    check_zstd(a, "", 17usize, 2462767108805496516u64, 85i32)
    var runs: [5000]u8 = zero
    i = 0usize
    while i < 5000usize {
        runs[i] = 122u8
        i += 1usize
    }
    check_zstd(a, runs[0..], 18usize, 14429534347056518605u64, 88i32)
    try io.print("fmt gaps b ok\n")
    ret ok
}
