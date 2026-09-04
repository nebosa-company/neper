use e.mem
use e.io

fn maximum[T: type](left: T, right: T) -> T {
    if left > right {
        ret left
    }
    ret right
}

fn edge_sum[N: usize](values: [N]u8) -> u8 {
    ret values[0usize] + values[N - 1]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let signed = maximum[i64](-4i64, 9i64)
    let unsigned = maximum[u16](12u16, 7u16)
    let inferred = maximum(unsigned, 15)
    let values = [4]u8{ 3u8, 5u8, 7u8, 11u8 }
    let edges = edge_sum[4](values)
    let inferred_edges = edge_sum(values)
    if signed == 9i64 && unsigned == 12u16 && inferred == 15u16 && edges == 14u8 && inferred_edges == 14u8 {
        try io.print("generic function ok\n")
    } else {
        try io.print("generic function failed\n")
    }
    ret ok
}
