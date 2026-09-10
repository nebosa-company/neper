// `e.fmt.csv` over a slice and over a real file. The reader is a state machine with two
// bits of memory, so what is worth pinning is every place a byte changes which of them is
// set: the quote that opens a field and the quote that is data, the doubled quote, the CRLF
// that terminates and the bare CR that does not, and the two limits.

use e.io
use e.mem
use e.os
use e.str
use e.fmt.csv

error Failed

fn source_over(text: str) -> io.SliceReader {
    ret io.SliceReader { data: text, off: 0usize }
}

// One row at a time, checked against a flat expectation: `expected` is every field of the
// row in order, and the count says how many of them belong to it.
fn expect_row(r: *csv.Reader, expected: []const str) -> err {
    let (row, more, next_error) = csv.reader_next_err(r)
    if next_error != ok { ret next_error }
    if !more { ret Failed }
    if row.fields.len != expected.len { ret Failed }
    var at = 0usize
    while at < expected.len {
        if !str.eq(row.fields[at], expected[at]) { ret Failed }
        at += 1usize
    }
    ret ok
}

fn expect_end(r: *csv.Reader) -> err {
    let (row, more, next_error) = csv.reader_next_err(r)
    if next_error != ok { ret next_error }
    if more { ret Failed }
    ret ok
}

fn main(a: *mem.Arena) -> err {
    // --- The plain case, and the three shapes a field can have: bare, quoted, and quoted
    // around the delimiter and a line ending.
    var plain_state = source_over("a,b,c\n1,\"two, and more\",3\n\"line\nbreak\",x,y\n")
    let (plain, plain_error) = csv.reader(a, io.slice_reader(&plain_state), csv.csv(), 0usize, 0usize)
    if plain_error != ok { ret plain_error }
    var plain_reader = plain
    var head: [3]str = zero
    head[0usize] = "a"
    head[1usize] = "b"
    head[2usize] = "c"
    try expect_row(&plain_reader, head[..])
    var second: [3]str = zero
    second[0usize] = "1"
    second[1usize] = "two, and more"
    second[2usize] = "3"
    try expect_row(&plain_reader, second[..])
    var third: [3]str = zero
    third[0usize] = "line\nbreak"
    third[1usize] = "x"
    third[2usize] = "y"
    try expect_row(&plain_reader, third[..])
    // The source ended with a line ending, so there is no row for the ending itself.
    try expect_end(&plain_reader)
    // And it stays ended.
    try expect_end(&plain_reader)

    // --- A doubled quote is one quote of data; a quote that is not at the start of a field
    // is data as it stands. Both are what the field ends up holding, not how it was spelled.
    var quotes_state = source_over("\"he said \"\"hi\"\"\",plain\"quote,\"\"\n")
    let (quotes, quotes_error) = csv.reader(a, io.slice_reader(&quotes_state), csv.csv(), 0usize, 0usize)
    if quotes_error != ok { ret quotes_error }
    var quotes_reader = quotes
    var quoted: [3]str = zero
    quoted[0usize] = "he said \"hi\""
    quoted[1usize] = "plain\"quote"
    quoted[2usize] = ""
    try expect_row(&quotes_reader, quoted[..])
    try expect_end(&quotes_reader)

    // --- CRLF terminates a record and leaves no CR in the last field; a CR with no LF after
    // it is data, because this format has no other reading for it.
    var endings_state = source_over("a,b\r\nc\rd,e")
    let (endings, endings_error) = csv.reader(a, io.slice_reader(&endings_state), csv.csv(), 0usize, 0usize)
    if endings_error != ok { ret endings_error }
    var endings_reader = endings
    var crlf_row: [2]str = zero
    crlf_row[0usize] = "a"
    crlf_row[1usize] = "b"
    try expect_row(&endings_reader, crlf_row[..])
    // No terminator at all on the last record, which still yields it.
    var bare_row: [2]str = zero
    bare_row[0usize] = "c\rd"
    bare_row[1usize] = "e"
    try expect_row(&endings_reader, bare_row[..])
    try expect_end(&endings_reader)

    // --- A dialect that says the first record is a header is asking not to be handed it.
    var header_dialect = csv.csv()
    header_dialect.header = true
    var header_state = source_over("name,size\nfirst,1\n")
    let (headed, headed_error) = csv.reader(a, io.slice_reader(&header_state), header_dialect, 0usize, 0usize)
    if headed_error != ok { ret headed_error }
    var headed_reader = headed
    var data_row: [2]str = zero
    data_row[0usize] = "first"
    data_row[1usize] = "1"
    try expect_row(&headed_reader, data_row[..])
    try expect_end(&headed_reader)

    // --- Tabs, with the same reader.
    var tab_state = source_over("one\ttwo\n")
    let (tabbed, tabbed_error) = csv.reader(a, io.slice_reader(&tab_state), csv.tsv(), 0usize, 0usize)
    if tabbed_error != ok { ret tabbed_error }
    var tabbed_reader = tabbed
    var tab_row: [2]str = zero
    tab_row[0usize] = "one"
    tab_row[1usize] = "two"
    try expect_row(&tabbed_reader, tab_row[..])

    // --- A quoted field the source ends in the middle of cannot be repaired.
    var truncated_state = source_over("a,\"unterminated")
    let (truncated, truncated_error) = csv.reader(a, io.slice_reader(&truncated_state), csv.csv(), 0usize, 0usize)
    if truncated_error != ok { ret truncated_error }
    var truncated_reader = truncated
    let (_, truncated_more, truncated_next) = csv.reader_next_err(&truncated_reader)
    if truncated_next != csv.Invalid { ret Failed }

    // --- A quoted field that closes and then carries on is refused rather than guessed at.
    var trailing_state = source_over("\"a\"b\n")
    let (trailing, trailing_error) = csv.reader(a, io.slice_reader(&trailing_state), csv.csv(), 0usize, 0usize)
    if trailing_error != ok { ret trailing_error }
    var trailing_reader = trailing
    let (_, trailing_more, trailing_next) = csv.reader_next_err(&trailing_reader)
    if trailing_next != csv.Invalid { ret Failed }

    // --- Both limits, each reported as `TooLarge` rather than as a truncated row.
    var wide_state = source_over("a,b,c\n")
    let (wide, wide_error) = csv.reader(a, io.slice_reader(&wide_state), csv.csv(), 2usize, 0usize)
    if wide_error != ok { ret wide_error }
    var wide_reader = wide
    let (_, wide_more, wide_next) = csv.reader_next_err(&wide_reader)
    if wide_next != csv.TooLarge { ret Failed }
    var long_state = source_over("abcdefgh\n")
    let (long, long_error) = csv.reader(a, io.slice_reader(&long_state), csv.csv(), 0usize, 4usize)
    if long_error != ok { ret long_error }
    var long_reader = long
    let (_, long_more, long_next) = csv.reader_next_err(&long_reader)
    if long_next != csv.TooLarge { ret Failed }

    // --- A dialect with no unambiguous reading is refused where it is given, not where it
    // would first go wrong. A `zero` Dialect is one of those.
    var refused_state = source_over("a\n")
    var refused_dialect: csv.Dialect = zero
    let (_, refused_error) = csv.reader(a, io.slice_reader(&refused_state), refused_dialect, 0usize, 0usize)
    if refused_error != csv.Invalid { ret Failed }

    // --- Writing. A field is quoted only when leaving it bare would change what it says,
    // and the quote inside one is doubled.
    var out_buffer: [64]u8 = zero
    var out_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var out = io.slice_writer(&out_state)
    var written: [4]str = zero
    written[0usize] = "plain"
    written[1usize] = "has,comma"
    written[2usize] = "has\"quote"
    written[3usize] = "has\nbreak"
    var out_row: csv.Row = zero
    out_row.fields = written[..]
    try csv.write_row(&out, out_row, csv.csv())
    let produced = out_buffer[0usize..out_state.off]
    if !str.eq(produced, "plain,\"has,comma\",\"has\"\"quote\",\"has\nbreak\"\n") { ret Failed }

    // What was written reads back as what went in, which is the pair working together.
    var round_state = source_over(produced)
    let (round, round_error) = csv.reader(a, io.slice_reader(&round_state), csv.csv(), 0usize, 0usize)
    if round_error != ok { ret round_error }
    var round_reader = round
    try expect_row(&round_reader, written[..])
    try expect_end(&round_reader)

    // A CRLF dialect writes the ending it names.
    var crlf_buffer: [16]u8 = zero
    var crlf_state = io.SliceWriter { data: crlf_buffer[..], off: 0usize }
    var crlf_out = io.slice_writer(&crlf_state)
    var crlf_dialect = csv.csv()
    crlf_dialect.crlf = true
    var crlf_fields: [2]str = zero
    crlf_fields[0usize] = "a"
    crlf_fields[1usize] = "b"
    var crlf_written: csv.Row = zero
    crlf_written.fields = crlf_fields[..]
    try csv.write_row(&crlf_out, crlf_written, crlf_dialect)
    if !str.eq(crlf_buffer[0usize..crlf_state.off], "a,b\r\n") { ret Failed }

    // --- Over a real file, where the source ends by taking nothing rather than by saying so,
    // and where a row spans more than one read of the reader's own input buffer.
    let removed_before = os.remove_file(a, "np-csv.txt")
    var make: os.OpenFlags = zero
    make.write = true
    make.create = true
    make.truncate = true
    let (made, made_error) = os.open(a, "np-csv.txt", make)
    if made_error != ok { ret made_error }
    var made_file = made
    var file_out = io.file_writer(&made_file)
    var file_row: csv.Row = zero
    file_row.fields = second[..]
    try csv.write_row(&file_out, file_row, csv.csv())
    try csv.write_row(&file_out, file_row, csv.csv())
    if os.close(made_file) != ok { ret Failed }
    var take_flags: os.OpenFlags = zero
    take_flags.read = true
    let (opened, opened_error) = os.open(a, "np-csv.txt", take_flags)
    if opened_error != ok { ret opened_error }
    var opened_file = opened
    let (from_file, from_file_error) = csv.reader(a, io.file_reader(&opened_file), csv.csv(), 0usize, 0usize)
    if from_file_error != ok { ret from_file_error }
    var file_reader = from_file
    try expect_row(&file_reader, second[..])
    try expect_row(&file_reader, second[..])
    try expect_end(&file_reader)
    if os.close(opened_file) != ok { ret Failed }
    if os.remove_file(a, "np-csv.txt") != ok { ret Failed }
    ret ok
}
