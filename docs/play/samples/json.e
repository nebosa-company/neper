// e.fmt.json parses into a Value you walk; a number keeps its exact text until you ask for a type.

use e.fmt.json
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let v = try json.parse(a, "{\"name\":\"neper\",\"targets\":[\"x64\",\"aarch64\"],\"modules\":344}", zero)
    switch v {
    case .Object as members:
        for i in 0usize..members.len {
            try io.printf["key: {}\n"](members[i].key)
        }
    default:
        try io.print("not an object\n")
    }
    ret ok
}
