// Every public network writer must reject an out-of-range caller cursor with its
// documented capacity result rather than slicing or indexing past the destination.
use e.mem
use e.net
use e.net.grpc as grpc
use e.net.grpcserver as grpcserver
use e.net.http2 as h2
use e.net.quic as quic
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var dst: [1]u8 = zero

    let (net_cursor, net_wrote) = net.put(dst[0usize..], 2usize, 1u8)
    if net_wrote || net_cursor != 2usize { os.exit(1i32) }

    var quic_cursor = 2usize
    if quic.put_varint(dst[0usize..], &quic_cursor, 1u64) != quic.TooSmall || quic_cursor != 2usize { os.exit(2i32) }

    var grpc_cursor = 2usize
    if grpc.put_frame(dst[0usize..], &grpc_cursor, 0u8, 0u8, 0u32, dst[0usize..0usize]) != grpc.TooSmall || grpc_cursor != 2usize { os.exit(3i32) }

    var server_cursor = 2usize
    if grpcserver.put_frame(dst[0usize..], &server_cursor, 0u8, 0u8, 0u32, dst[0usize..0usize]) != grpc.TooSmall || server_cursor != 2usize { os.exit(4i32) }

    // A zero-length Huffman literal formerly sliced scratch[2..] before a bounds check.
    let huffman_empty: [1]u8 = [1]u8{ 128 }
    var huffman_cursor = 0usize
    var scratch: [1]u8 = zero
    var scratch_used = 2usize
    let (_, huffman_error) = h2.read_string(huffman_empty[0usize..], &huffman_cursor, scratch[0usize..], &scratch_used)
    if huffman_error != h2.TooSmall || huffman_cursor != 1usize || scratch_used != 2usize { os.exit(5i32) }

    ret ok
}
