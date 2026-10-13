// e.data.map and os.args on NeperOS (C107, D4704): the map hashes its keys with the runtime's
// `neper_hash_bytes`, which the NeperOS program runtime did not have, and `os.args` is the
// runtime's `neper_os_args` (an empty slice there). Started as program 0 of a one-program
// archive on the `-append shell` boot; it fills a u64 map past several doublings, reads every key
// back, does the same for `str` keys, prints what it found and exits.
use e.mem
use e.io
use e.os
use e.data.map

fn main(a: *mem.Arena, args: []str) -> err {
    let (table, init_error) = map.init[u64, u64](a, 0usize)
    if init_error != ok { ret init_error }
    var counts = table
    var k = 0u64
    while k < 200u64 {
        let (fresh, put_error) = map.put[u64, u64](&counts, k, k * k)
        if put_error != ok || !fresh { ret put_error }
        k += 1u64
    }
    var all = map.len[u64, u64](&counts) == 200usize
    k = 0u64
    while k < 200u64 {
        let (value, present) = map.get[u64, u64](&counts, k)
        if !present || value != k * k { all = false }
        k += 1u64
    }
    let (_, absent) = map.get[u64, u64](&counts, 5000u64)
    if absent { all = false }
    if all {
        try io.print("map u64 ok 200\n")
    } else {
        try io.print("map u64 wrong\n")
    }
    let (names, names_error) = map.init[str, u32](a, 0usize)
    if names_error != ok { ret names_error }
    var by_name = names
    let (one, one_error) = map.put[str, u32](&by_name, "neperos", 1u32)
    let (two, two_error) = map.put[str, u32](&by_name, "microkernel", 2u32)
    if one_error != ok || two_error != ok { ret one_error }
    let (first, first_present) = map.get[str, u32](&by_name, "neperos")
    let (second, second_present) = map.get[str, u32](&by_name, "microkernel")
    let (_, missing) = map.get[str, u32](&by_name, "linux")
    if first_present && second_present && !missing && first == 1u32 && second == 2u32 {
        try io.print("map str ok\n")
    } else {
        try io.print("map str wrong\n")
    }
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok {
        try io.print("args failed\n")
        ret ok
    }
    if arguments.len == 0usize {
        try io.print("args 0\n")
    } else {
        try io.print("args other\n")
    }
    ret ok
}
