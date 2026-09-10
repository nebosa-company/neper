// `e.fmt.json`'s value tree: what a document parses to, what it writes back as, and what it
// refuses. Most of it is the one decision the module turns on -- a number keeps the lexeme it
// arrived with -- which is only visible in a round trip, since a parser that rounded through an
// `f64` would agree with itself on everything except what came back out.

use e.fmt.json
use e.io
use e.mem
use e.os
use e.str

fn roundtrip(a: *mem.Arena, source: str) -> ([]const u8, err) {
    var options: json.Options = zero
    let (value, parse_error) = json.parse(a, source, options)
    let (state, sink, writer_error) = io.memory_writer(a, 4096usize)
    if writer_error != ok { ret (io.memory_bytes(&state), writer_error) }
    var held = state
    // `memory_writer` hands back a `Writer` it never filled in, so the sink is wired here
    // out of the pieces the fence does expose.
    var out = io.writer(mem.cast[*void](&held), io.memory_write)
    if parse_error != ok { ret (io.memory_bytes(&held), parse_error) }
    let write_error = json.write(&out, &value)
    if write_error != ok { ret (io.memory_bytes(&held), write_error) }
    let bytes = io.memory_bytes(&held)
    ret (bytes, ok)
}

fn same(a: *mem.Arena, source: str, expected: str) -> bool {
    let (text, failure) = roundtrip(a, source)
    if failure != ok { ret false }
    ret mem.eq[u8](text, expected)
}

fn rejected(a: *mem.Arena, source: str) -> bool {
    var options: json.Options = zero
    let (value, failure) = json.parse(a, source, options)
    ret failure != ok
}

fn main(a: *mem.Arena) -> err {
    // --- Numbers keep the lexeme they arrived with.
    if !same(a, "1.5e1", "1.5e1") { os.exit(10i32) }
    if !same(a, "-0", "-0") { os.exit(11i32) }
    if !same(a, "123456789012345678901234567890", "123456789012345678901234567890") { os.exit(12i32) }

    // --- Structure, order and whitespace.
    if !same(a, " [ 1 , 2 , 3 ] ", "[1,2,3]") { os.exit(20i32) }
    if !same(a, "{\"b\":1,\"a\":2}", "{\"b\":1,\"a\":2}") { os.exit(21i32) }
    if !same(a, "[]", "[]") { os.exit(22i32) }
    if !same(a, "{}", "{}") { os.exit(23i32) }
    if !same(a, "[[[1]]]", "[[[1]]]") { os.exit(24i32) }
    if !same(a, "true", "true") { os.exit(25i32) }
    if !same(a, "null", "null") { os.exit(26i32) }

    // --- Escapes decode on the way in and are written back in their shortest legal form.
    if !same(a, "\"a\\u0041b\"", "\"aAb\"") { os.exit(30i32) }
    if !same(a, "\"\\u00e9\"", "\"\xc3\xa9\"") { os.exit(31i32) }
    if !same(a, "\"\\ud83d\\ude00\"", "\"\xf0\x9f\x98\x80\"") { os.exit(32i32) }
    if !same(a, "\"tab\\tend\"", "\"tab\\tend\"") { os.exit(33i32) }
    if !same(a, "\"\\u0001\"", "\"\\u0001\"") { os.exit(34i32) }
    if !same(a, "\"sl\\/ash\"", "\"sl/ash\"") { os.exit(35i32) }

    // --- What the grammar refuses.
    if !rejected(a, "01") { os.exit(40i32) }
    if !rejected(a, "[1,]") { os.exit(41i32) }
    if !rejected(a, "{\"a\":1,}") { os.exit(42i32) }
    if !rejected(a, "[1 2]") { os.exit(43i32) }
    if !rejected(a, "\"unterminated") { os.exit(44i32) }
    if !rejected(a, "{\"a\":1}{}") { os.exit(45i32) }
    if !rejected(a, "\"\\ud83d\"") { os.exit(46i32) }
    if !rejected(a, "nul") { os.exit(47i32) }
    if !rejected(a, "") { os.exit(48i32) }
    if !rejected(a, "1.") { os.exit(49i32) }

    // --- A duplicate key is refused unless it is allowed.
    if !rejected(a, "{\"a\":1,\"a\":2}") { os.exit(50i32) }
    var permissive: json.Options = zero
    permissive.allow_duplicate_keys = true
    let (kept, kept_error) = json.parse(a, "{\"a\":1,\"a\":2}", permissive)
    if kept_error != ok { os.exit(51i32) }

    // --- Depth is bounded, and the bound is the caller's.
    var shallow: json.Options = zero
    shallow.max_depth = 2u16
    let (deep, deep_error) = json.parse(a, "[[[1]]]", shallow)
    if deep_error != json.TooDeep { os.exit(60i32) }
    let (fits, fits_error) = json.parse(a, "[[1]]", shallow)
    if fits_error != ok { os.exit(61i32) }

    // --- The pretty form is the same document with room in it.
    var options: json.Options = zero
    let (tree, tree_error) = json.parse(a, "{\"a\":[1,2]}", options)
    if tree_error != ok { os.exit(70i32) }
    let (state, sink, writer_error) = io.memory_writer(a, 1024usize)
    if writer_error != ok { os.exit(71i32) }
    var held = state
    var out = io.writer(mem.cast[*void](&held), io.memory_write)
    let pretty_error = json.write_pretty(&out, &tree, 2u8)
    if pretty_error != ok { os.exit(72i32) }
    let pretty = io.memory_bytes(&held)
    if !mem.eq[u8](pretty, "{\n  \"a\": [\n    1,\n    2\n  ]\n}") { os.exit(73i32) }

    // --- RFC 6901 pointers, including the two spellings that are easy to get backwards: the
    // empty pointer is the root, and `/` is a member whose key is empty rather than the root
    // again.
    let (document, document_error) = json.parse(a, "{\"a\":{\"b\":[10,20]},\"\":1,\"m/n\":2,\"t~x\":3}", options)
    if document_error != ok { os.exit(80i32) }
    let (root, root_error) = json.pointer(&document, "")
    if root_error != ok { os.exit(81i32) }
    let (nested, nested_error) = json.pointer(&document, "/a/b/1")
    if nested_error != ok { os.exit(82i32) }
    switch *nested {
    case .Number as found:
        let (value, value_error) = json.number_i64(found)
        if value_error != ok { os.exit(83i32) }
        if value != 20i64 { os.exit(84i32) }
    default:
        os.exit(85i32)
    }
    let (empty_key, empty_key_error) = json.pointer(&document, "/")
    if empty_key_error != ok { os.exit(86i32) }
    // `~1` is a `/` inside a key and `~0` is a `~`, so neither splits the pointer.
    let (slashed, slashed_error) = json.pointer(&document, "/m~1n")
    if slashed_error != ok { os.exit(87i32) }
    let (tilded, tilded_error) = json.pointer(&document, "/t~0x")
    if tilded_error != ok { os.exit(88i32) }
    let (missing, missing_error) = json.pointer(&document, "/a/b/2")
    if missing_error != json.InvalidPointer { os.exit(89i32) }
    let (unrooted, unrooted_error) = json.pointer(&document, "a")
    if unrooted_error != json.InvalidPointer { os.exit(90i32) }
    // An index with a leading zero is not an index.
    let (padded, padded_error) = json.pointer(&document, "/a/b/01")
    if padded_error != json.InvalidPointer { os.exit(91i32) }
    ret ok
}
