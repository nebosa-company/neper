use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var total: i64 = 0
    for i in 0i64..10i64 {
        if i == 2i64 {
            continue
        }
        if i == 7i64 {
            break
        }
        total += i
    }
    for unused in 3i64..-2i64 {
        total += unused
    }
    let limit: usize = 3
    var contextual: usize = 0
    for j in 0..limit {
        contextual += j
    }
    if true {
        let branch: i64 = 19
        if branch != total || contextual != 3usize {
            try io.print("range failed\n")
            ret ok
        }
    }
    if true {
        let branch: i64 = 19
        if branch == total {
            try io.print("range ok\n")
        }
    }
    ret ok
}
