// A release build inlines `midhelp.mix` and bakes `lowvals.OFFSET` into main (D4702): an
// incremental build after the constant's edit has to say the new value, not keep main.
use e.io
use midhelp

fn main() -> err {
    var answer = "other"
    if midhelp.mix(3u32) == 14u32 { answer = "14" }
    if midhelp.mix(3u32) == 15u32 { answer = "15" }
    try io.print(answer)
    ret ok
}
