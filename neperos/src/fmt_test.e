// A NeperOS program that encodes JSON through e.fmt.json (C107, D2156): it reflects a struct and
// writes it as JSON straight to an e.io Writer over stdout, proving e.fmt compiles and runs
// unchanged on NeperOS (the codecs are pure over e.mem/e.str/e.meta/e.io and touch no os primitive
// directly). Started as program 0 of a one-program archive on the shell boot.
use e.mem
use e.os
use e.io
use e.fmt.json

type Point = struct { x: i64, y: i64, label: str }

fn main(a: *mem.Arena, args: []str) -> err {
    var output = os.stdout()
    var writer = io.file_writer(&output)
    let intro = io.print("fmt json: ")
    let point = Point { x: 3i64, y: 7i64, label: "neperos" }
    let encode_error = json.encode[Point](&writer, &point)
    if encode_error != ok { ret encode_error }
    let newline = io.print("\n")
    ret ok
}
