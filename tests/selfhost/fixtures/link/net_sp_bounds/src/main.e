// `e.net.sp`: encoding, including the direct `send` path, applies the same
// identifier and 1 GiB body limit that the decoder enforces.

use e.io
use e.net
use e.net.sp as sp
use e.os

fn main() -> err {
    var frame: [16]u8 = zero
    let (bad_size, bad_error) = sp.encode_message(frame[..], true, 1u32, frame[0usize..0usize])
    if bad_size != 0usize || bad_error != sp.NoId { os.exit(1i32) }
    var socket: net.Socket = zero
    var buffer: [1]u8 = zero
    var request = sp.conn(socket, buffer[..], .Req, 0u32)
    let send_error = sp.send(&request, 1u32, frame[0usize..0usize])
    if send_error != sp.NoId { os.exit(2i32) }
    let (size, encode_error) = sp.encode_message(frame[..], true, 2147483648u32, frame[0usize..0usize])
    if encode_error != ok || size != 12usize { os.exit(3i32) }
    let (body, used, decode_error) = sp.decode_message(frame[0usize..size])
    let (_, _, split_error) = sp.split_id(body)
    if decode_error != ok || used != size || split_error != ok { os.exit(4i32) }
    let (max_body, max_error) = sp.message_body_length(true, 2147483648u32, 1073741820usize)
    let (over_body, over_error) = sp.message_body_length(true, 2147483648u32, 1073741821usize)
    if max_error != ok || max_body != 1073741824usize || over_body != 0usize || over_error != sp.TooLarge { os.exit(5i32) }
    try io.print("net sp bounds ok\n")
    ret ok
}
