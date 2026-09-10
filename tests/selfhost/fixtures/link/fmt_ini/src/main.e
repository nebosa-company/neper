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
    var file_out = io.file_writer(&made_file)
    let file_write = ini.write(&file_out, &document)
    if file_write != ok { ret file_write }
    if os.close(made_file) != ok { os.exit(50i32) }
    var take_flags: os.OpenFlags = zero
    take_flags.read = true
    let (opened, opened_error) = os.open(a, "np-ini.txt", take_flags)
    if opened_error != ok { ret opened_error }
    var opened_file = opened
    let (from_file, from_file_error) = ini.reader(a, io.file_reader(&opened_file), strict)
    if from_file_error != ok { ret from_file_error }
    var file_reader = from_file
    if expect_entry(&file_reader, "server", "host", "example.test") != ok { os.exit(51i32) }
    if expect_entry(&file_reader, "server", "port", "8080") != ok { os.exit(52i32) }
    if expect_entry(&file_reader, "paths", "home", "/tmp/with space") != ok { os.exit(53i32) }
    if expect_entry(&file_reader, "paths", "escaped", "a\tb\nc") != ok { os.exit(54i32) }
    if expect_entry(&file_reader, "paths", "bare", "value with ; inside") != ok { os.exit(55i32) }
    if expect_end(&file_reader) != ok { os.exit(56i32) }
    if os.close(opened_file) != ok { os.exit(57i32) }
    if os.remove_file(a, "np-ini.txt") != ok { os.exit(58i32) }
    ret ok
}
