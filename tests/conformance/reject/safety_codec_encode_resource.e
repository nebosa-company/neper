use e.fmt.json
use e.io
use e.os

type Box = struct { file: os.File }

// Typed encoders walk fields through meta.get and therefore reject resources.
fn main() -> err {
    var writer: io.Writer = zero
    var box: Box = zero
    ret json.encode[Box](&writer, &box)
}
