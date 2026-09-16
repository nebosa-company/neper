// `e.fmt.ini` both ways: the document `parse` builds and the stream `reader` yields, over the
// same text, so the two agree about what the format says. What is worth pinning is every choice
// the format leaves open -- where a comment may start, what folding does to a name, which value
// has to be quoted on the way back out -- and the two errors that are refusals rather than
// tolerances.

use e.io
use e.mem
use e.os
use e.str
use e.fmt.ini

error Failed

// The codec maps a struct to a flat document, so the fixture needs one of each kind it
// handles, and one that only an unsigned parser reaches.
type Settings = struct { port: u16, retries: i64, host: str, ratio: f64, verbose: bool }
type Wide = struct { big: u64 }

// A module-scope `const` of type `str` does not type check (D134), so the sample is a call.
fn sample() -> str {
    ret "; a leading comment\n[server]\nhost = example.test\nport=8080\n\n# another comment\n[paths]\nhome = \"/tmp/with space\"\nescaped = \"a\\tb\\nc\"\nbare = value with ; inside\n"
}

fn expect_entry(r: *ini.Reader, section: str, key: str, value: str) -> err {
    let (entry, more, next_error) = ini.reader_next_err(r)
    if next_error != ok { ret next_error }
    if !more { ret Failed }
    if !str.eq(entry.section, section) { ret Failed }
    if !str.eq(entry.key, key) { ret Failed }
    if !str.eq(entry.value, value) { ret Failed }
    ret ok
}

fn expect_end(r: *ini.Reader) -> err {
    let (entry, more, next_error) = ini.reader_next_err(r)
    if next_error != ok { ret next_error }
    if more { ret Failed }
    ret ok
}

fn expect_get(document: *const ini.Document, section: str, key: str, value: str) -> err {
    let (found, present) = ini.get(document, section, key)
    if !present { ret Failed }
    if !str.eq(found, value) { ret Failed }
    ret ok
}

fn write_document(file: *os.File, document: *const ini.Document) -> err {
    var file_out = io.file_writer(file)
    ret ini.write(&file_out, document)
}

fn main(a: *mem.Arena) -> err {
    // --- The document. A case-sensitive parse keeps every name as it was written.
    var strict: ini.Options = zero
    strict.case_sensitive = true
    let (document, parse_error) = ini.parse(a, sample(), strict)
    if parse_error != ok { ret parse_error }
    if document.entries.len != 5usize { os.exit(10i32) }
    if expect_get(&document, "server", "host", "example.test") != ok { os.exit(11i32) }
    if expect_get(&document, "server", "port", "8080") != ok { os.exit(12i32) }
    // A quoted value keeps the whitespace that `trim` would otherwise have taken.
    if expect_get(&document, "paths", "home", "/tmp/with space") != ok { os.exit(13i32) }
    // The escapes this format admits, decoded.
    if expect_get(&document, "paths", "escaped", "a\tb\nc") != ok { os.exit(14i32) }
    // A comment starts a line and nothing else, so the `;` here is part of the value.
    if expect_get(&document, "paths", "bare", "value with ; inside") != ok { os.exit(15i32) }
    // A key that is not there answers rather than failing, and a key from another section is
    // not this section's.
    let (_, missing) = ini.get(&document, "server", "absent")
    if missing { os.exit(16i32) }
    let (_, elsewhere) = ini.get(&document, "server", "home")
    if elsewhere { os.exit(17i32) }

    // --- The stream says the same thing, entry by entry, and consumes the section lines and
    // the comments rather than handing them over.
    var stream_state = io.SliceReader { data: sample(), off: 0usize }
    let (stream, stream_error) = ini.reader(a, io.slice_reader(&stream_state), strict)
    if stream_error != ok { ret stream_error }
    var stream_reader = stream
    if expect_entry(&stream_reader, "server", "host", "example.test") != ok { os.exit(18i32) }
    if expect_entry(&stream_reader, "server", "port", "8080") != ok { os.exit(19i32) }
    if expect_entry(&stream_reader, "paths", "home", "/tmp/with space") != ok { os.exit(20i32) }
    if expect_entry(&stream_reader, "paths", "escaped", "a\tb\nc") != ok { os.exit(21i32) }
    if expect_entry(&stream_reader, "paths", "bare", "value with ; inside") != ok { os.exit(22i32) }
    if expect_end(&stream_reader) != ok { os.exit(23i32) }

    // --- Folding. A `zero` Options is case-insensitive, and that is done to the stored name
    // rather than to the comparison: `get` is exact either way, and the folded document is what
    // a caller who asked for the distinction not to matter gets.
    var folding: ini.Options = zero
    folding.allow_duplicate_keys = true
    let (folded, folded_error) = ini.parse(a, "[Server]\nHost=Example.Test\n", folding)
    if folded_error != ok { ret folded_error }
    if expect_get(&folded, "server", "host", "Example.Test") != ok { os.exit(24i32) }
    // The value is not a name, so its case is never touched.
    let (_, unfolded) = ini.get(&folded, "Server", "Host")
    if unfolded { os.exit(25i32) }

    // --- Entries before any section belong to the empty one.
    let (rootless, rootless_error) = ini.parse(a, "top=1\n[s]\ninner=2\n", strict)
    if rootless_error != ok { ret rootless_error }
    if expect_get(&rootless, "", "top", "1") != ok { os.exit(26i32) }
    if expect_get(&rootless, "s", "inner", "2") != ok { os.exit(27i32) }

    // --- A repeated key is a refusal by default, and the same two names in different sections
    // are not a repeat.
    let (_, duplicate_error) = ini.parse(a, "[s]\nk=1\nk=2\n", strict)
    if duplicate_error != ini.DuplicateKey { os.exit(28i32) }
    let (spread, spread_error) = ini.parse(a, "[a]\nk=1\n[b]\nk=2\n", strict)
    if spread_error != ok { ret spread_error }
    if expect_get(&spread, "a", "k", "1") != ok { os.exit(29i32) }
    if expect_get(&spread, "b", "k", "2") != ok { os.exit(30i32) }
    // Folding makes two spellings the same key, which is what makes them a duplicate.
    let (_, folded_duplicate) = ini.parse(a, "[s]\nK=1\nk=2\n", zero)
    if folded_duplicate != ini.DuplicateKey { os.exit(31i32) }
    // And a caller who allows them keeps both.
    var loose: ini.Options = zero
    loose.case_sensitive = true
    loose.allow_duplicate_keys = true
    let (kept, kept_error) = ini.parse(a, "[s]\nk=1\nk=2\n", loose)
    if kept_error != ok { ret kept_error }
    if kept.entries.len != 2usize { os.exit(32i32) }
    // `get` answers with the first, since it is a scan in order.
    if expect_get(&kept, "s", "k", "1") != ok { os.exit(33i32) }

    // The stream refuses a repeat too, which is the only thing that sees every entry.
    var repeat_state = io.SliceReader { data: "[s]\nk=1\nk=2\n", off: 0usize }
    let (repeat, repeat_error) = ini.reader(a, io.slice_reader(&repeat_state), strict)
    if repeat_error != ok { ret repeat_error }
    var repeat_reader = repeat
    if expect_entry(&repeat_reader, "s", "k", "1") != ok { os.exit(34i32) }
    let (_, _, repeated) = ini.reader_next_err(&repeat_reader)
    if repeated != ini.DuplicateKey { os.exit(35i32) }

    // --- What the format refuses. Each of these has a reading the parser will not invent.
    let (_, no_equals) = ini.parse(a, "[s]\nlonely\n", strict)
    if no_equals != ini.Invalid { os.exit(36i32) }
    let (_, no_key) = ini.parse(a, "[s]\n=1\n", strict)
    if no_key != ini.Invalid { os.exit(37i32) }
    let (_, unclosed_section) = ini.parse(a, "[s\n", strict)
    if unclosed_section != ini.Invalid { os.exit(38i32) }
    let (_, empty_section) = ini.parse(a, "[]\n", strict)
    if empty_section != ini.Invalid { os.exit(39i32) }
    let (_, unterminated) = ini.parse(a, "k=\"open\n", strict)
    if unterminated != ini.Invalid { os.exit(40i32) }
    // A comment is a line, so nothing may follow a closing quote.
    let (_, trailing) = ini.parse(a, "k=\"v\" ; comment\n", strict)
    if trailing != ini.Invalid { os.exit(41i32) }
    // An escape this format does not define is a mistake, not a byte to pass through.
    let (_, unknown_escape) = ini.parse(a, "k=\"a\\qb\"\n", strict)
    if unknown_escape != ini.Invalid { os.exit(42i32) }

    // --- Writing. A value is quoted only when leaving it bare would not read back as itself,
    // which the source's own quoting does not decide: `/tmp/with space` had to be quoted where it
    // was written only because the writer chose to, and comes back out bare because a space in
    // the middle is not one `trim` would take. What survives is the value, not its spelling.
    var out_buffer: [256]u8 = zero
    var out_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var out = io.slice_writer(&out_state)
    let write_error = ini.write(&out, &document)
    if write_error != ok { ret write_error }
    let produced = out_buffer[0usize..out_state.off]
    if !str.eq(produced, "[server]\nhost=example.test\nport=8080\n[paths]\nhome=/tmp/with space\nescaped=\"a\\tb\\nc\"\nbare=value with ; inside\n") { os.exit(43i32) }

    // What was written parses back to the same entries, which is the pair working together.
    let (round, round_error) = ini.parse(a, produced, strict)
    if round_error != ok { ret round_error }
    if round.entries.len != document.entries.len { os.exit(44i32) }
    var at = 0usize
    while at < round.entries.len {
        if !str.eq(round.entries[at].section, document.entries[at].section) { os.exit(45i32) }
        if !str.eq(round.entries[at].key, document.entries[at].key) { os.exit(46i32) }
        if !str.eq(round.entries[at].value, document.entries[at].value) { os.exit(47i32) }
        at += 1usize
    }

    // An empty value, and one that is only spaces, both survive the round trip because both are
    // quoted -- bare, `trim` would take them and the second would come back as the first.
    var edge_entries: [2]ini.Entry = zero
    edge_entries[0usize] = ini.Entry { section: "e", key: "empty", value: "" }
    edge_entries[1usize] = ini.Entry { section: "e", key: "spaces", value: "  " }
    var edge: ini.Document = zero
    edge.entries = edge_entries[..]
    var edge_buffer: [128]u8 = zero
    var edge_state = io.SliceWriter { data: edge_buffer[..], off: 0usize }
    var edge_out = io.slice_writer(&edge_state)
    let edge_write = ini.write(&edge_out, &edge)
    if edge_write != ok { ret edge_write }
    let (edge_back, edge_back_error) = ini.parse(a, edge_buffer[0usize..edge_state.off], strict)
    if edge_back_error != ok { ret edge_back_error }
    if expect_get(&edge_back, "e", "empty", "") != ok { os.exit(48i32) }
    if expect_get(&edge_back, "e", "spaces", "  ") != ok { os.exit(49i32) }

    // --- The typed codec. A struct is a flat document: one key per field, in the empty section,
    // named as the field is. The walk is unrolled and each arm is chosen by the field's kind, so
    // the arm that reads an integer never has to be valid for the field that holds a `str`.
    var settings: Settings = zero
    settings.port = 8080u16
    settings.retries = -3i64
    settings.host = "example.test"
    settings.ratio = 0.5f64
    settings.verbose = true
    var codec_buffer: [256]u8 = zero
    var codec_state = io.SliceWriter { data: codec_buffer[..], off: 0usize }
    var codec_out = io.slice_writer(&codec_state)
    if ini.encode[Settings](&codec_out, &settings) != ok { os.exit(60i32) }
    let encoded = codec_buffer[0usize..codec_state.off]
    if !str.eq(encoded, "port=8080\nretries=-3\nhost=example.test\nratio=0.5\nverbose=true\n") { os.exit(61i32) }

    // And back, to the same values. A `u16` past the signed range and a negative both survive,
    // because each is read through whichever parser fits it and neither goes by way of a float.
    let (round_trip, round_trip_error) = ini.decode[Settings](a, encoded, strict)
    if round_trip_error != ok { ret round_trip_error }
    if round_trip.port != 8080u16 { os.exit(62i32) }
    if round_trip.retries != -3i64 { os.exit(63i32) }
    if !str.eq(round_trip.host, "example.test") { os.exit(64i32) }
    if round_trip.ratio != 0.5f64 { os.exit(65i32) }
    if !round_trip.verbose { os.exit(66i32) }

    // The whole unsigned range, which a decoder that went through `i64` would lose.
    let (wide, wide_error) = ini.decode[Wide](a, "big=18446744073709551615\n", strict)
    if wide_error != ok { ret wide_error }
    if wide.big != 18446744073709551615u64 { os.exit(67i32) }

    // A key the source does not carry leaves its field alone: a configuration file is partial by
    // nature, and adding a field to a program should not break the files already written for it.
    let (sparse, sparse_error) = ini.decode[Settings](a, "host=only\n", strict)
    if sparse_error != ok { ret sparse_error }
    if !str.eq(sparse.host, "only") { os.exit(68i32) }
    if sparse.port != 0u16 { os.exit(69i32) }

    // A value that is not what the field holds is refused rather than rounded or ignored.
    let (_, bad_number) = ini.decode[Settings](a, "port=eight\n", strict)
    if bad_number != ini.Invalid { os.exit(70i32) }
    let (_, bad_bool) = ini.decode[Settings](a, "verbose=yes\n", strict)
    if bad_bool != ini.Invalid { os.exit(71i32) }

    // A quoted value reaches the field with its quoting undone, and a value that needs quoting
    // gets it on the way out.
    let (spaced, spaced_error) = ini.decode[Settings](a, "host=\"two words\"\n", strict)
    if spaced_error != ok { ret spaced_error }
    if !str.eq(spaced.host, "two words") { os.exit(72i32) }
    var quoting_state = io.SliceWriter { data: codec_buffer[..], off: 0usize }
    var quoting_out = io.slice_writer(&quoting_state)
    var spacey: Settings = zero
    spacey.host = " padded "
    if ini.encode[Settings](&quoting_out, &spacey) != ok { os.exit(73i32) }
    let quoted_back = codec_buffer[0usize..quoting_state.off]
    if !str.eq(quoted_back, "port=0\nretries=0\nhost=\" padded \"\nratio=0\nverbose=false\n") { os.exit(74i32) }

    // --- Over a real file, where a line spans more than one read of the reader's input buffer
    // and the source ends by taking nothing rather than by saying so.
    let removed_before = os.remove_file(a, "np-ini.txt")
    var make: os.OpenFlags = zero
    make.write = true
    make.create = true
    make.truncate = true
    let (made, made_error) = os.open(a, "np-ini.txt", make)
    if made_error != ok { ret made_error }
    var made_file = made
    // The writer's pointer lives in its own function (D351), so the close follows it.
    let file_write = write_document(&made_file, &document)
    let made_close = os.close(made_file)
    if file_write != ok { ret file_write }
    if made_close != ok { os.exit(50i32) }
    var take_flags: os.OpenFlags = zero
    take_flags.read = true
    let (opened, opened_error) = os.open(a, "np-ini.txt", take_flags)
    if opened_error != ok { ret opened_error }
    var opened_file = opened
    defer let _ = os.close(opened_file)
    let (from_file, from_file_error) = ini.reader(a, io.file_reader(&opened_file), strict)
    if from_file_error != ok { ret from_file_error }
    var file_reader = from_file
    if expect_entry(&file_reader, "server", "host", "example.test") != ok { os.exit(51i32) }
    if expect_entry(&file_reader, "server", "port", "8080") != ok { os.exit(52i32) }
    if expect_entry(&file_reader, "paths", "home", "/tmp/with space") != ok { os.exit(53i32) }
    if expect_entry(&file_reader, "paths", "escaped", "a\tb\nc") != ok { os.exit(54i32) }
    if expect_entry(&file_reader, "paths", "bare", "value with ; inside") != ok { os.exit(55i32) }
    if expect_end(&file_reader) != ok { os.exit(56i32) }
    if os.remove_file(a, "np-ini.txt") != ok { os.exit(58i32) }
    ret ok
}
