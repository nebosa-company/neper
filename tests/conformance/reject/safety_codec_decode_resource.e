use e.fmt.json
use e.mem
use e.os

type Box = struct { file: os.File }

// Typed decoders populate fields through meta.set and therefore reject resources.
fn main(a: *mem.Arena) -> err {
    var options: json.Options = zero
    let (_, decode_error) = json.decode[Box](a, "{}", options)
    ret decode_error
}
