// `e.fmt.pem`: a block with leading text and CRLF lines decoded with its suffix, a
// block with RFC 1421 headers, an encode of 100 bytes in 64-column lines that decodes
// back, and the refusals: no BEGIN, a mismatched END, a stray byte in the body, and a
// body over the byte limit. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.pem as pem

fn main(a: *mem.Arena, args: []str) -> err {
    let text = "junk before\r\n-----BEGIN THING-----\r\nAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8w\r\nMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl9g\r\nYWJjZA==\r\n-----END THING-----\r\nafter"
    let (block, rest, e1) = pem.decode(a, text, 1024usize)
    if e1 != ok { os.exit(1) }
    if !str.eq(block.label, "THING") { os.exit(2) }
    if block.headers.len != 0usize { os.exit(3) }
    if block.bytes.len != 100usize { os.exit(4) }
    if block.bytes[0] != 1u8 || block.bytes[99] != 100u8 { os.exit(5) }
    if !str.eq(rest, "after") { os.exit(6) }
    // Headers, LF lines, no suffix.
    let with_headers = "-----BEGIN X-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,ABCD\n\nYWJj\n-----END X-----\n"
    let (block2, rest2, e2) = pem.decode(a, with_headers, 16usize)
    if e2 != ok { os.exit(7) }
    if block2.headers.len != 2usize { os.exit(8) }
    if !str.eq(block2.headers[1].name, "DEK-Info") || !str.eq(block2.headers[1].value, "AES-128-CBC,ABCD") { os.exit(9) }
    if block2.bytes.len != 3usize || block2.bytes[2] != 99u8 { os.exit(10) }
    if rest2.len != 0usize { os.exit(11) }
    // Encode the first block and read it back.
    var out_buffer: [512]u8 = zero
    var out_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var out = io.slice_writer(&out_state)
    if pem.encode(&out, &block) != ok { os.exit(12) }
    let written = out_buffer[..out_state.off]
    let expected = "-----BEGIN THING-----\nAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8w\nMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl9g\nYWJjZA==\n-----END THING-----\n"
    if !str.eq(written, expected) { os.exit(13) }
    let (block3, rest3, e3) = pem.decode(a, written, 1024usize)
    if e3 != ok || block3.bytes.len != 100usize || block3.bytes[50] != 51u8 || rest3.len != 0usize { os.exit(14) }
    // A block with headers round-trips too.
    var out2_buffer: [128]u8 = zero
    var out2_state = io.SliceWriter { data: out2_buffer[..], off: 0usize }
    var out2 = io.slice_writer(&out2_state)
    if pem.encode(&out2, &block2) != ok { os.exit(15) }
    if !str.eq(out2_buffer[..out2_state.off], with_headers) { os.exit(16) }
    // Refusals.
    let (b4, r4, e4) = pem.decode(a, "nothing here", 16usize)
    if e4 != pem.Invalid { os.exit(17) }
    let (b5, r5, e5) = pem.decode(a, "-----BEGIN A-----\nYWJj\n-----END B-----\n", 16usize)
    if e5 != pem.Invalid { os.exit(18) }
    let (b6, r6, e6) = pem.decode(a, "-----BEGIN A-----\nYW*j\n-----END A-----\n", 16usize)
    if e6 != pem.Invalid { os.exit(19) }
    let (b7, r7, e7) = pem.decode(a, "-----BEGIN A-----\nYWJj\n", 16usize)
    if e7 != pem.Invalid { os.exit(20) }
    let (b8, r8, e8) = pem.decode(a, text, 99usize)
    if e8 != pem.TooLarge { os.exit(21) }
    ret ok
}
