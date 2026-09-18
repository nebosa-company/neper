// WebSocket handshake and framing. D596 begins with the allocation-free client nonce;
// upgrades and frame transport follow as separate bounded slices.

use e.bytes

type Opcode = enum u8 { Continuation, Text, Binary, Close, Ping, Pong }
type Frame = struct { final: bool, opcode: Opcode, payload: []const u8 }
type Connection = struct { state: *void }

error InvalidHandshake
error InvalidFrame
error TooLarge
error Closed

fn client_key(entropy: [16]u8, dst: []u8) -> (str, err) {
    let (encoded, encode_error) = bytes.base64_encode(dst, entropy[0..], .Standard, true)
    if encode_error == bytes.TooLarge { ret ("", TooLarge) }
    if encode_error != ok { ret ("", encode_error) }
    ret (encoded, ok)
}
