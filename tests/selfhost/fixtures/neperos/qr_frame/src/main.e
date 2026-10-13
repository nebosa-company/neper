// Makes the camera frame the Secure scan fixtures read: a QR symbol of an otpauth URI on a white page, 4 pixels a
// module with a 4-module quiet zone, written as a grey-scale-looking RGBA PNG to the path in args[0]
// (tests/selfhost/fixtures/neperos/qr_frame.png is its output, committed).
use e.os
use e.mem
use e.io
use e.fs
use e.gfx.image
use e.fmt.png
use e.barcode as bar

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { os.exit(1i32) }
    let uri = "otpauth://totp/Scan%20Bank:lee.park?secret=MFRGGZDFMZTWQ2LK&issuer=Scan%20Bank&digits=6&period=30"
    let (m, m_error) = bar.qr_encode(a, uri, 1usize)
    if m_error != ok { os.exit(2i32) }
    let scale = 4usize
    let quiet = 4usize
    let side = (m.size + 2usize * quiet) * scale
    let (pixels, pixels_error) = mem.alloc[u8](a, side * side * 4usize)
    if pixels_error != ok { os.exit(3i32) }
    var y = 0usize
    while y < side {
        var x = 0usize
        while x < side {
            var v = 255u8
            let mx = x / scale
            let my = y / scale
            if mx >= quiet && my >= quiet && mx < quiet + m.size && my < quiet + m.size {
                if m.modules[(my - quiet) * m.size + (mx - quiet)] == 1u8 { v = 0u8 }
            }
            let at = (y * side + x) * 4usize
            pixels[at] = v
            pixels[at + 1usize] = v
            pixels[at + 2usize] = v
            pixels[at + 3usize] = 255u8
            x += 1usize
        }
        y += 1usize
    }
    let (source, source_error) = image.make_const(pixels, u32(side), u32(side), side * 4usize, image.Format.Rgba8, image.Alpha.Straight)
    if source_error != ok { os.exit(4i32) }
    let (buffer, buffer_error) = mem.alloc[u8](a, side * side * 4usize + 4096usize)
    if buffer_error != ok { os.exit(5i32) }
    var sink = io.SliceWriter { data: buffer, off: 0usize }
    var encoder = io.slice_writer(&sink)
    if png.encode(&encoder, source, png.EncodeOptions { compression: .Best, interlace: false }) != ok { os.exit(6i32) }
    if fs.write_file(a, args[1usize], buffer[0usize..sink.off]) != ok { os.exit(7i32) }
    ret ok
}
