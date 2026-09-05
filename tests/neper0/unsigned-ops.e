use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let maximum = 18446744073709551615usize
    let quotient = maximum / 16usize
    let remainder = maximum % 16usize
    if maximum > 1usize && maximum >= 18446744073709551615usize && !(maximum < 1usize) && !(maximum <= 1usize) && quotient == 1152921504606846975usize && remainder == 15usize {
        try io.print("unsigned ops ok\n")
    } else {
        try io.print("unsigned ops failed\n")
    }
    ret ok
}
