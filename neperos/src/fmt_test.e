// A NeperOS program that encodes through two e.fmt codecs (C107, D2156 json; D2183 csv breadth): it
// reflects a struct and writes it as JSON straight to an e.io Writer over stdout, then writes two CSV
// rows through e.fmt.csv -- proving more than one e.fmt codec compiles and runs unchanged on NeperOS
// (the codecs are pure over e.mem/e.str/e.meta/e.io and touch no os primitive directly). Started as
// program 0 of a one-program archive on the shell boot.
use e.mem
use e.os
use e.io
use e.fmt.json
use e.fmt.csv
use e.fmt.ini

type Point = struct { x: i64, y: i64, label: str }

fn main(a: *mem.Arena, args: []str) -> err {
    var output = os.stdout()
    var writer = io.file_writer(&output)
    let intro = io.print("fmt json: ")
    let point = Point { x: 3i64, y: 7i64, label: "neperos" }
    let encode_error = json.encode[Point](&writer, &point)
    if encode_error != ok { ret encode_error }
    let newline = io.print("\n")
    // e.fmt.csv breadth: a header row and a data row through the default (comma, LF) dialect.
    let csv_intro = io.print("fmt csv: ")
    var header_fields: [3]str = [3]str{ "x", "y", "label" }
    var header_row: csv.Row = zero
    header_row.fields = header_fields[0usize..]
    let header_error = csv.write_row(&writer, header_row, csv.csv())
    if header_error != ok { ret header_error }
    var data_fields: [3]str = [3]str{ "3", "7", "neperos" }
    var data_row: csv.Row = zero
    data_row.fields = data_fields[0usize..]
    let data_error = csv.write_row(&writer, data_row, csv.csv())
    if data_error != ok { ret data_error }
    // e.fmt.ini breadth: the same struct through a third pure codec.
    let ini_intro = io.print("\nfmt ini:\n")
    let ini_error = ini.encode[Point](&writer, &point)
    if ini_error != ok { ret ini_error }
    ret ok
}
