// `e.fmt.json`'s value tree: what a document parses to, what it writes back as, and what it
// refuses. Most of it is the one decision the module turns on -- a number keeps the lexeme it
// arrived with -- which is only visible in a round trip, since a parser that rounded through an
// `f64` would agree with itself on everything except what came back out.

use e.fmt.json
use e.io
use e.mem
use e.os
use e.str

// The codec maps a struct to an object, so the fixture needs one field of each kind it
// handles, and one that only an unsigned reading reaches.
type Record = struct { id: u16, name: str, ratio: f64, ready: bool }
type Wide = struct { big: u64 }

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

// The reader's events, asked about one at a time. Each answers whether the next event is the one
// named, so the walk below reads as the document does.
fn next_event(r: *json.Reader) -> (json.Event, bool) {
    let (event, more, next_error) = json.reader_next_err(r)
    if next_error != ok { ret (event, false) }
    ret (event, more)
}

fn event_is(r: *json.Reader, shape: str) -> bool {
    let (event, more) = next_event(r)
    if !more { ret false }
    switch event {
    case .BeginObject:
        ret str.eq(shape, "{")
    case .EndObject:
        ret str.eq(shape, "}")
    case .BeginArray:
        ret str.eq(shape, "[")
    case .EndArray:
        ret str.eq(shape, "]")
    case .Null:
        ret str.eq(shape, "null")
    default:
        ret false
    }
}

fn event_key(r: *json.Reader, expected: str) -> bool {
    let (event, more) = next_event(r)
    if !more { ret false }
    switch event {
    case .Key as name:
        ret str.eq(name, expected)
    default:
        ret false
    }
}

fn event_string(r: *json.Reader, expected: str) -> bool {
    let (event, more) = next_event(r)
    if !more { ret false }
    switch event {
    case .String as text:
        ret str.eq(text, expected)
    default:
        ret false
    }
}

fn event_number(r: *json.Reader, expected: str) -> bool {
    let (event, more) = next_event(r)
    if !more { ret false }
    switch event {
    case .Number as written:
        ret str.eq(written.lexeme, expected)
    default:
        ret false
    }
}

fn event_bool(r: *json.Reader, expected: bool) -> bool {
    let (event, more) = next_event(r)
    if !more { ret false }
    switch event {
    case .Bool as flag:
        ret flag == expected
    default:
        ret false
    }
}

// A source the stream refuses somewhere, wherever that is.
fn stream_rejected(a: *mem.Arena, source: str) -> bool {
    var state = io.SliceReader { data: source, off: 0usize }
    var options: json.Options = zero
    let (handle, handle_error) = json.reader(a, io.slice_reader(&state), options)
    if handle_error != ok { ret true }
    var events = handle
    var guard = 0usize
    while guard < 64usize {
        let (_, more, next_error) = json.reader_next_err(&events)
        if next_error != ok { ret true }
        if !more { ret false }
        guard += 1usize
    }
    ret false
}

// A patch applied to a document, rendered back so the result can be compared as text.
fn patched(a: *mem.Arena, source: str, operations: str) -> (str, err) {
    var options: json.Options = zero
    let (root, root_error) = json.parse(a, source, options)
    if root_error != ok { ret ("", root_error) }
    let (steps, steps_error) = json.parse(a, operations, options)
    if steps_error != ok { ret ("", steps_error) }
    let (result, patch_error) = json.patch(a, &root, &steps, 0usize, 0u16)
    if patch_error != ok { ret ("", patch_error) }
    let (holder, writer, holder_error) = io.memory_writer(a, 1024usize)
    if holder_error != ok { ret ("", holder_error) }
    var held = holder
    var sink = io.writer(mem.cast[*void](&held), io.memory_write)
    let write_error = json.write(&sink, &result)
    if write_error != ok { ret ("", write_error) }
    ret (io.memory_bytes(&held), ok)
}

fn patch_gives(a: *mem.Arena, source: str, operations: str, expected: str) -> bool {
    let (text, text_error) = patched(a, source, operations)
    if text_error != ok { ret false }
    ret str.eq(text, expected)
}

// A patch that does not apply, whatever the reason.
fn patch_fails(a: *mem.Arena, source: str, operations: str) -> bool {
    let (_, text_error) = patched(a, source, operations)
    ret text_error != ok
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
    // --- The typed codec. A struct is an object: one member per field, named as the field is,
    // in declaration order. The walk is unrolled and each arm is chosen by the field's kind, so
    // the arm reading a number never has to be valid for the field holding a `str`.
    var record: Record = zero
    record.id = 65535u16
    record.name = "with \"quote\""
    record.ratio = -0.25f64
    record.ready = true
    var codec_buffer: [256]u8 = zero
    var codec_state = io.SliceWriter { data: codec_buffer[..], off: 0usize }
    var codec_out = io.slice_writer(&codec_state)
    if json.encode[Record](&codec_out, &record) != ok { os.exit(120i32) }
    let encoded = codec_buffer[0usize..codec_state.off]
    if !str.eq(encoded, "{\"id\":65535,\"name\":\"with \\\"quote\\\"\",\"ratio\":-0.25,\"ready\":true}") { os.exit(121i32) }

    // And back, to the same values -- the quote inside the name survives being escaped and
    // unescaped, which is the pair of string rules working together.
    var codec_options: json.Options = zero
    let (round_trip, round_trip_error) = json.decode[Record](a, encoded, codec_options)
    if round_trip_error != ok { ret round_trip_error }
    if round_trip.id != 65535u16 { os.exit(122i32) }
    if !str.eq(round_trip.name, "with \"quote\"") { os.exit(123i32) }
    if round_trip.ratio != -0.25f64 { os.exit(124i32) }
    if !round_trip.ready { os.exit(125i32) }

    // The whole unsigned range, which a decoder that went by way of `i64` or a float would lose.
    // This is the module's founding decision reaching the codec: a number is the lexeme, so the
    // integer that comes out is the integer that went in.
    let (wide, wide_error) = json.decode[Wide](a, "{\"big\":18446744073709551615}", codec_options)
    if wide_error != ok { ret wide_error }
    if wide.big != 18446744073709551615u64 { os.exit(126i32) }

    // A member the document does not carry leaves its field alone.
    let (sparse, sparse_error) = json.decode[Record](a, "{\"name\":\"only\"}", codec_options)
    if sparse_error != ok { ret sparse_error }
    if !str.eq(sparse.name, "only") { os.exit(127i32) }
    if sparse.id != 0u16 { os.exit(128i32) }

    // A member whose shape is not the field's is refused rather than coerced, and a document
    // that is not an object is not a struct at all.
    let (_, wrong_shape) = json.decode[Record](a, "{\"id\":\"eight\"}", codec_options)
    if wrong_shape != json.Invalid { os.exit(129i32) }
    let (_, not_object) = json.decode[Record](a, "[1,2]", codec_options)
    if not_object != json.Invalid { os.exit(130i32) }

    // --- The streaming reader. The same grammar as `parse` over a source that arrives a piece
    // at a time, so a caller sees the shape rather than the value and the document need never be
    // held whole. What each event carries borrows one reader-owned buffer and is good until the
    // next call.
    var stream_state = io.SliceReader { data: "{\"a\":[1,\"two\",true,null],\"b\":{}}", off: 0usize }
    var stream_options: json.Options = zero
    let (stream_handle, stream_error) = json.reader(a, io.slice_reader(&stream_state), stream_options)
    if stream_error != ok { ret stream_error }
    var events = stream_handle
    if !event_is(&events, "{") { os.exit(140i32) }
    if !event_key(&events, "a") { os.exit(141i32) }
    if !event_is(&events, "[") { os.exit(142i32) }
    if !event_number(&events, "1") { os.exit(143i32) }
    if !event_string(&events, "two") { os.exit(144i32) }
    if !event_bool(&events, true) { os.exit(145i32) }
    if !event_is(&events, "null") { os.exit(146i32) }
    if !event_is(&events, "]") { os.exit(147i32) }
    if !event_key(&events, "b") { os.exit(148i32) }
    if !event_is(&events, "{") { os.exit(149i32) }
    if !event_is(&events, "}") { os.exit(150i32) }
    if !event_is(&events, "}") { os.exit(151i32) }
    // The document is one value, and it is complete.
    let (_, still_more, done_error) = json.reader_next_err(&events)
    if done_error != ok { ret done_error }
    if still_more { os.exit(152i32) }

    // A number keeps the lexeme it arrived with here too, which is the module's one decision
    // reaching the streaming path.
    var lexeme_state = io.SliceReader { data: "[1.50e+2,-0]", off: 0usize }
    let (lexeme_handle, lexeme_error) = json.reader(a, io.slice_reader(&lexeme_state), stream_options)
    if lexeme_error != ok { ret lexeme_error }
    var lexemes = lexeme_handle
    if !event_is(&lexemes, "[") { os.exit(153i32) }
    if !event_number(&lexemes, "1.50e+2") { os.exit(154i32) }
    if !event_number(&lexemes, "-0") { os.exit(155i32) }
    if !event_is(&lexemes, "]") { os.exit(156i32) }

    // An escape is decoded, and a surrogate pair is one character rather than two halves.
    var escaped_state = io.SliceReader { data: "\"a\\tb\\u00e9\\ud83d\\ude00\"", off: 0usize }
    let (escaped_handle, escaped_error) = json.reader(a, io.slice_reader(&escaped_state), stream_options)
    if escaped_error != ok { ret escaped_error }
    var escapes = escaped_handle
    if !event_string(&escapes, "a\tb\xc3\xa9\xf0\x9f\x98\x80") { os.exit(157i32) }

    // The depth limit and the duplicate-key rule are the reader's too, since a stream is where
    // an unbounded document is most likely to come from.
    var deep_options: json.Options = zero
    deep_options.max_depth = 2u16
    var deep_state = io.SliceReader { data: "[[[1]]]", off: 0usize }
    let (deep_handle, deep_handle_error) = json.reader(a, io.slice_reader(&deep_state), deep_options)
    if deep_handle_error != ok { ret deep_handle_error }
    var deep_events = deep_handle
    if !event_is(&deep_events, "[") { os.exit(158i32) }
    if !event_is(&deep_events, "[") { os.exit(159i32) }
    let (_, _, too_deep) = json.reader_next_err(&deep_events)
    if too_deep != json.TooDeep { os.exit(160i32) }
    var repeat_state = io.SliceReader { data: "{\"k\":1,\"k\":2}", off: 0usize }
    let (repeat_handle, repeat_handle_error) = json.reader(a, io.slice_reader(&repeat_state), stream_options)
    if repeat_handle_error != ok { ret repeat_handle_error }
    var repeats = repeat_handle
    if !event_is(&repeats, "{") { os.exit(161i32) }
    if !event_key(&repeats, "k") { os.exit(162i32) }
    if !event_number(&repeats, "1") { os.exit(163i32) }
    let (_, _, repeated) = json.reader_next_err(&repeats)
    if repeated != json.DuplicateKey { os.exit(164i32) }

    // What the stream refuses: a trailing comma, a document with something after it, and a
    // string the source ends inside.
    if !stream_rejected(a, "[1,]") { os.exit(165i32) }
    if !stream_rejected(a, "{} {}") { os.exit(166i32) }
    if !stream_rejected(a, "\"open") { os.exit(167i32) }

    // --- RFC 6902 patch. Every operation makes a new tree; `root` is never touched and nothing
    // of it is reachable from the result, because the whole document is copied on the way in.
    if !patch_gives(a, "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2}]", "{\"a\":1,\"b\":2}") { os.exit(170i32) }
    if !patch_gives(a, "{\"a\":1,\"b\":2}", "[{\"op\":\"remove\",\"path\":\"/a\"}]", "{\"b\":2}") { os.exit(171i32) }
    // `add` over a member that is already there replaces it and keeps its place: what changed is
    // the value, not the order.
    if !patch_gives(a, "{\"a\":1,\"b\":2}", "[{\"op\":\"replace\",\"path\":\"/a\",\"value\":9}]", "{\"a\":9,\"b\":2}") { os.exit(172i32) }
    if !patch_gives(a, "{\"a\":1,\"b\":2}", "[{\"op\":\"add\",\"path\":\"/a\",\"value\":9}]", "{\"a\":9,\"b\":2}") { os.exit(173i32) }

    // An array index inserts rather than overwrites, and `-` is the position after the last.
    if !patch_gives(a, "[1,3]", "[{\"op\":\"add\",\"path\":\"/1\",\"value\":2}]", "[1,2,3]") { os.exit(174i32) }
    if !patch_gives(a, "[1,2]", "[{\"op\":\"add\",\"path\":\"/-\",\"value\":3}]", "[1,2,3]") { os.exit(175i32) }
    if !patch_gives(a, "[1,2,3]", "[{\"op\":\"remove\",\"path\":\"/1\"}]", "[1,3]") { os.exit(176i32) }

    // Nested paths rebuild only the spine down to what changed.
    if !patch_gives(a, "{\"a\":{\"b\":[1,2]},\"c\":3}", "[{\"op\":\"replace\",\"path\":\"/a/b/0\",\"value\":9}]", "{\"a\":{\"b\":[9,2]},\"c\":3}") { os.exit(177i32) }

    // `move` and `copy`, and the difference between them.
    if !patch_gives(a, "{\"a\":1,\"b\":{}}", "[{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/b/a\"}]", "{\"b\":{\"a\":1}}") { os.exit(178i32) }
    if !patch_gives(a, "{\"a\":1,\"b\":{}}", "[{\"op\":\"copy\",\"from\":\"/a\",\"path\":\"/b/a\"}]", "{\"a\":1,\"b\":{\"a\":1}}") { os.exit(179i32) }

    // `test` passes and the patch goes on; it fails and the whole patch does.
    if !patch_gives(a, "{\"a\":1}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":1},{\"op\":\"add\",\"path\":\"/b\",\"value\":2}]", "{\"a\":1,\"b\":2}") { os.exit(180i32) }
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":2}]") { os.exit(181i32) }
    // Exact mathematical equality, not `f64` equality: three spellings of one number agree.
    if !patch_gives(a, "{\"a\":1.0}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":1}]", "{\"a\":1.0}") { os.exit(182i32) }
    if !patch_gives(a, "{\"a\":1e2}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":100}]", "{\"a\":1e2}") { os.exit(183i32) }
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":1.0000000000000001}]") { os.exit(184i32) }
    // A number `f64` cannot tell apart from its neighbour is still a different number here.
    if !patch_fails(a, "{\"a\":9007199254740993}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":9007199254740992}]") { os.exit(185i32) }
    // An object compares by membership rather than by order.
    if !patch_gives(a, "{\"a\":{\"x\":1,\"y\":2}}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":{\"y\":2,\"x\":1}}]", "{\"a\":{\"x\":1,\"y\":2}}") { os.exit(186i32) }

    // The empty pointer is the root, which `replace` may take and `remove` may not.
    if !patch_gives(a, "{\"a\":1}", "[{\"op\":\"replace\",\"path\":\"\",\"value\":[1]}]", "[1]") { os.exit(187i32) }
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"remove\",\"path\":\"\"}]") { os.exit(188i32) }
    // `~1` is a `/` inside a key and `~0` is a `~`, so a key may contain either.
    if !patch_gives(a, "{}", "[{\"op\":\"add\",\"path\":\"/a~1b\",\"value\":1}]", "{\"a/b\":1}") { os.exit(189i32) }

    // What a patch is refused for. Each of these is a way of naming nothing, or of asking for a
    // tree that could not exist.
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"remove\",\"path\":\"/missing\"}]") { os.exit(190i32) }
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"replace\",\"path\":\"/missing\",\"value\":1}]") { os.exit(191i32) }
    if !patch_fails(a, "[1,2]", "[{\"op\":\"remove\",\"path\":\"/5\"}]") { os.exit(192i32) }
    if !patch_fails(a, "[1,2]", "[{\"op\":\"add\",\"path\":\"/9\",\"value\":3}]") { os.exit(193i32) }
    // A pointer that does not begin with `/` is not a pointer.
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"a\",\"value\":1}]") { os.exit(194i32) }
    // Moving a subtree inside itself would build a tree that contains itself.
    if !patch_fails(a, "{\"a\":{\"b\":1}}", "[{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/a/b/c\"}]") { os.exit(195i32) }
    // An operation the standard does not define, and one missing what it needs.
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"invent\",\"path\":\"/a\",\"value\":1}]") { os.exit(196i32) }
    if !patch_fails(a, "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/b\"}]") { os.exit(197i32) }
    // Operations are an array of objects, and there may not be more of them than allowed.
    if !patch_fails(a, "{\"a\":1}", "{\"op\":\"add\"}") { os.exit(198i32) }

    // `root` is untouched: the same document patched twice gives the same answer, which it could
    // not if the first patch had written through it.
    if !patch_gives(a, "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2}]", "{\"a\":1,\"b\":2}") { os.exit(199i32) }

    ret ok
}
