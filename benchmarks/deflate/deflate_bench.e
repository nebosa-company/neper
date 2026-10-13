// Deflate throughput: one 800x500 noisy RGBA image, encoded as PNG (adaptive filters)
// and as raw deflate at both lazy levels. Prints name, milliseconds, output bytes.
use e.algo.deflate
use e.fmt.png
use e.gfx.image
use e.io
use e.mem
use e.time

fn ms(d: time.Duration) -> f64 { ret f64(d.nanos) / 1000000.0f64 }

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let w = 800usize
    let h = 500usize
    let (px, px_error) = mem.alloc[u8](a, w * h * 4usize)
    if px_error != ok { ret px_error }
    var s = 12345u64
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var c = 0usize
            while c < 4usize {
                s = (s * 1103515245u64 + 12345u64) & 2147483647u64
                let noise = u32(s >> 16u64) & 31u32
                let base = u32((x + y * 2usize + c * 40usize) & 127usize) + 40u32
                px[(y * w + x) * 4usize + c] = u8(base + noise)
                c += 1usize
            }
            px[(y * w + x) * 4usize + 3usize] = 255u8
            x += 1usize
        }
        y += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, 3000000usize)
    if out_error != ok { ret out_error }
    let img = image.ConstImage { pixels: px, width: u32(w), height: u32(h), stride: w * 4usize, format: .Rgba8, alpha: .Opaque }
    var mode = 0usize
    if args.len > 1usize {
        if mem.eq[u8](args[1], "raw") { mode = 1usize }
        if mem.eq[u8](args[1], "png") { mode = 2usize }
    }
    var round = 0usize
    while round < 2usize && mode != 1usize {
        if mode == 2usize && round == 1usize { break }
        var level = deflate.Level.Balanced
        if round == 1usize { level = .Best }
        var sink = io.SliceWriter { data: out, off: 0usize }
        var wr = io.slice_writer(&sink)
        let opts = png.EncodeOptions { compression: level, interlace: false }
        let start = try time.monotonic()
        try png.encode_adaptive(&wr, img, opts)
        try io.printf["png_adaptive {} {} {}\n"](round, ms(time.since(start)), sink.off)
        var sink2 = io.SliceWriter { data: out, off: 0usize }
        var wr2 = io.slice_writer(&sink2)
        let start2 = try time.monotonic()
        if mode == 0usize { try png.encode(&wr2, img, opts) }
        try io.printf["png_plain {} {} {}\n"](round, ms(time.since(start2)), sink2.off)
        round += 1usize
    }
    if mode == 2usize { ret ok }
    // Raw deflate of the pixel bytes.
    let (es, es_error) = aligned(a, deflate.encoder_storage(.Balanced) + 16usize)
    if es_error != ok { ret es_error }
    let (enc, enc_error) = deflate.encoder(es, .Balanced)
    if enc_error != ok { ret enc_error }
    var e = enc
    let start3 = try time.monotonic()
    let (consumed, written, status, enc2) = deflate.encode(&e, px, out, true)
    try io.printf["raw {} {} {}\n"](consumed, ms(time.since(start3)), written)
    ret ok
}
