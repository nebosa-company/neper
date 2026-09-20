// A template that formats its `T` (D784): `printf` and `format` expand per instance,
// in the module that instantiated it.

use e.io
use e.mem
use e.str

fn line[T: type](label: str, v: T) -> err {
    ret io.printf["{}={};"](label, v)
}

fn text[T: type](a: *mem.Arena, v: T) -> (str, err) {
    let (made, made_error) = str.format["<{}>"](a, v)
    ret (made, made_error)
}
