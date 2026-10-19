// `e.gfx.dwtext`: Roboto drawn as Chromium on Windows draws it (Skia over DirectWrite, grey anti-aliasing), against alpha bytes read
// from a Chromium 149 capture of black text on white at 1x (--disable-lcd-text --font-render-hinting=none, the face from the Windows
// font directory as a web font). The mask of "H" at 16 px is checked on the four sub-pixel positions Skia has (0, 1/4, 1/2 and 3/4 of
// a pixel, which DirectWrite takes as 0, 1/3, 1/2 and 5/6), all of its 12 rows by 15 columns, byte for byte. The whole check passes
// when the font is not there. `main dump` prints the four masks instead of checking them.

use e.fs
use e.gfx.dwtext
use e.io
use e.mem
use e.str
use e.text.shape
use e.text.tthint
use e.text.ttglyph

fn font_path() -> str { ret "C:/Windows/Fonts/Roboto-Regular.ttf" }

fn append_int(buf: []u8, len: usize, v: i64) -> usize {
    var n = len
    var digits: [24]u8 = zero
    var count = 0usize
    var m = v
    if m == 0i64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while m > 0i64 {
        digits[count] = u8(48i64 + m % 10i64)
        count += 1usize
        m = m / 10i64
    }
    while count > 0usize {
        count = count - 1usize
        if n < buf.len {
            buf[n] = digits[count]
            n += 1usize
        }
    }
    ret n
}

// The sub-pixel positions of the capture, as the sixths DirectWrite uses.
fn fraction(k: usize) -> f32 {
    if k == 0usize { ret 0.0 }
    if k == 1usize { ret 2.0 / 6.0 }
    if k == 2usize { ret 3.0 / 6.0 }
    ret 5.0 / 6.0
}

// Chromium's alpha bytes of "H" at 16 px at the four positions, row by row, a blank line between the masks.
fn expected() -> str {
    ret "0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 253 228 226 226 226 226 250 225 25 0 \n0 0 161 255 255 255 255 255 255 255 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 255 234 226 226 226 226 238 255 77 0 0 \n0 0 77 255 255 255 255 255 255 255 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 238 226 226 226 226 234 255 119 0 0 \n0 0 51 245 255 255 255 255 255 255 255 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 250 226 226 226 226 228 253 192 12 0 \n0 12 192 255 255 255 255 255 255 255 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n"
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (bytes, read_error) = fs.read_file(a, font_path(), 16777216usize)
    if read_error != ok { ret ok }
    let (h, open_error) = tthint.open(a, bytes)
    if open_error != ok { ret open_error }
    let font = shape.Font { id: 1u32, data: bytes, face_index: 0u32 }
    let (cmap, has_cmap) = shape.find_table(font, shape.TAG_CMAP)
    if !has_cmap { ret tthint.Unsupported }
    let (sub, has_sub) = shape.cmap_subtable(bytes, cmap)
    if !has_sub { ret tthint.Unsupported }
    ttglyph.set_end_fit(false)
    let gid = shape.glyph_of(bytes, sub, 72u32)
    let (outline, hint_error) = ttglyph.hint_glyph(h, a, 16i64, gid, true)
    if hint_error != ok { ret hint_error }
    let (scratch, scratch_error) = mem.alloc[u8](a, dwtext.scratch_bytes())
    if scratch_error != ok { ret scratch_error }
    var lut: [256]u8 = zero
    dwtext.lut_build(0usize, lut[0..])
    var out: [4096]u8 = zero
    var len = 0usize
    var k = 0usize
    while k < 4usize {
        let (m, drawn) = dwtext.rasterize(scratch, outline.cur, outline.tags, outline.ends, outline.nends, outline.n, 1.0, fraction(k), lut[0..])
        if !drawn { ret tthint.Trap }
        var y = 0usize
        while y < m.height {
            var x = 0usize
            while x < m.width {
                len = append_int(out[0..], len, i64(scratch[dwtext.GRID_BYTES + y * m.width + x]))
                if len < out.len {
                    out[len] = 32u8
                    len += 1usize
                }
                x += 1usize
            }
            if len < out.len {
                out[len] = 10u8
                len += 1usize
            }
            y += 1usize
        }
        if len < out.len {
            out[len] = 10u8
            len += 1usize
        }
        k += 1usize
    }
    if args.len > 1usize && str.eq(args[1usize], "dump") {
        try io.print(out[0..len])
        ret ok
    }
    if !str.eq(out[0..len], expected()) { ret tthint.Trap }
    ret ok
}
