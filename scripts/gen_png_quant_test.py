#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_png_quant/src/main.e (D2482): e.fmt.png.quantize and encode_quantized
against an independent Python model of the documented rule -- keep the max_colors most frequent colours (ties to the
smaller r | g << 8 | b << 16 | a << 24 value), map every other colour to the nearest kept one by squared distance
over the four channels (ties to the smaller value) -- over deterministic synthetic anti-aliased pictures."""
from pathlib import Path

W, H = 48, 32
INKS = [(0, 114, 178), (213, 94, 0), (60, 60, 60)]


def picture(seed, levels):
    """White with three inks at `levels` coverage levels each, the way anti-aliasing leaves a chart."""
    s = seed
    px = []
    for _ in range(W * H):
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        v = s >> 16
        if v % 5 == 0:
            ink = INKS[(v >> 3) % 3]
            cov = 1 + (v >> 5) % levels
            px.append(tuple(((255 * levels - (255 - c) * cov) * 2 + levels) // (2 * levels) for c in ink) + (255,))
        else:
            px.append((255, 255, 255, 255))
    return px


def color(p):
    return p[0] | p[1] << 8 | p[2] << 16 | p[3] << 24


def quantize(px, k):
    counts = {}
    for p in px:
        counts[color(p)] = counts.get(color(p), 0) + 1
    if len(counts) <= k:
        return px, len(counts)
    kept = sorted(counts, key=lambda c: (-counts[c], c))[:k]
    keptset = set(kept)

    def dist(a, b):
        return sum((((a >> s) & 255) - ((b >> s) & 255)) ** 2 for s in (0, 8, 16, 24))
    mapping = {c: (c if c in keptset else min(kept, key=lambda t: (dist(c, t), t))) for c in counts}
    out = []
    for p in px:
        m = mapping[color(p)]
        out.append((m & 255, (m >> 8) & 255, (m >> 16) & 255, (m >> 24) & 255))
    return out, k


def fnv(data):
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


def flat(px):
    return bytes(c for p in px for c in p)


HEAD = '''// `e.fmt.png.quantize` and `encode_quantized` (D2482) against scripts/gen_png_quant_test.py, an independent
// model of the rule: the most frequent colours kept (ties to the smaller value), the others mapped to the nearest kept
// one (ties to the smaller value). The pictures are generated here with the model's own LCG and integer rounding.
// Every check has its own exit code.

use e.fmt.png
use e.gfx.image
use e.io
use e.mem
use e.os

const W: usize = %(w)dusize
const H: usize = %(h)dusize

fn fnv(data: []const u8) -> u32 {
    var h = 2166136261u64
    var i = 0usize
    while i < data.len {
        h = ((h ^ u64(data[i])) * 16777619u64) & 4294967295u64
        i += 1usize
    }
    ret u32(h)
}

// The distinct colours of an Rgba8 buffer.
fn distinct(data: []const u8) -> usize {
    var seen: [4096]u32 = zero
    var used: [4096]bool = zero
    var n = 0usize
    var i = 0usize
    while i + 4usize <= data.len {
        let c = u32(data[i]) | (u32(data[i + 1usize]) << 8u32) | (u32(data[i + 2usize]) << 16u32) | (u32(data[i + 3usize]) << 24u32)
        var h = usize((u64(c) * 2654435761u64) >> 20u64) & 4095usize
        var found = false
        while used[h] && !found {
            if seen[h] == c { found = true } else { h = (h + 1usize) & 4095usize }
        }
        if !found {
            used[h] = true
            seen[h] = c
            n += 1usize
        }
        i += 4usize
    }
    ret n
}

// The model's picture: white with three inks at `levels` coverage levels.
fn picture(dst: []u8, seed: u64, levels: u32) {
    var s = seed
    var at = 0usize
    var i = 0usize
    while i < W * H {
        s = (s * 1103515245u64 + 12345u64) & 2147483647u64
        let v = u32(s >> 16u64)
        var r = 255u32
        var g = 255u32
        var b = 255u32
        if v %% 5u32 == 0u32 {
            let which = (v >> 3u32) %% 3u32
            let cov = 1u32 + (v >> 5u32) %% levels
            var ir = 0u32
            var ig = 114u32
            var ib = 178u32
            if which == 1u32 {
                ir = 213u32
                ig = 94u32
                ib = 0u32
            }
            if which == 2u32 {
                ir = 60u32
                ig = 60u32
                ib = 60u32
            }
            r = ((255u32 * levels - (255u32 - ir) * cov) * 2u32 + levels) / (2u32 * levels)
            g = ((255u32 * levels - (255u32 - ig) * cov) * 2u32 + levels) / (2u32 * levels)
            b = ((255u32 * levels - (255u32 - ib) * cov) * 2u32 + levels) / (2u32 * levels)
        }
        dst[at] = u8(r)
        dst[at + 1usize] = u8(g)
        dst[at + 2usize] = u8(b)
        dst[at + 3usize] = 255u8
        at += 4usize
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var store: [%(n)d]u8 = zero
    var src: [%(n)d]u8 = zero
''' % {'w': W, 'h': H, 'n': W * H * 4}


def main():
    cases = [('few', 1, 2, 256), ('mid', 2, 60, 256), ('mid64', 2, 60, 64), ('mid16', 3, 90, 16), ('one', 4, 30, 1)]
    out = [HEAD]
    code = 10
    for name, seed, levels, k in cases:
        px = picture(seed, levels)
        q, used = quantize(px, k)
        out.append('    // %s: %d colours in, k=%d, %d out\n' % (name, len({color(p) for p in px}), k, used))
        out.append('    picture(src[0..], %du64, %du32)\n' % (seed, levels))
        out.append('    let (img_%s, n_%s, e_%s) = png.quantize(store[0..], image.ConstImage { pixels: src[0..], width: %du32, height: %du32, stride: %dusize, format: .Rgba8, alpha: .Straight }, %dusize)\n'
                   % (name, name, name, W, H, W * 4, k))
        out.append('    if e_%s != ok { os.exit(%di32) }\n' % (name, code))
        out.append('    if n_%s != %dusize { os.exit(%di32) }\n' % (name, used, code + 1))
        out.append('    if fnv(img_%s.pixels) != %du32 { os.exit(%di32) }\n' % (name, fnv(flat(q)), code + 2))
        out.append('    if distinct(img_%s.pixels) > %dusize { os.exit(%di32) }\n' % (name, k, code + 3))
        code += 10
    _, seed, levels, k = cases[1]
    q, used = quantize(picture(seed, levels), k)
    out.append('    // encode_quantized: an indexed PNG whose decoded pixels are the quantized ones\n')
    out.append('    picture(src[0..], %du64, %du32)\n' % (seed, levels))
    out.append('    let (state, unused, writer_error) = io.memory_writer(a, 0usize)\n    if writer_error != ok { os.exit(%di32) }\n' % code)
    out.append('    var held = state\n    var writer = io.writer(mem.cast[*void](&held), io.memory_write)\n')
    out.append('    let src_png = image.ConstImage { pixels: src[0..], width: %du32, height: %du32, stride: %dusize, format: .Rgba8, alpha: .Straight }\n' % (W, H, W * 4))
    out.append('    if png.encode_quantized(&writer, src_png, png.EncodeOptions { compression: .Balanced, interlace: false }, 256usize, store[0..]) != ok { os.exit(%di32) }\n' % (code + 1))
    out.append('    let file = io.memory_bytes(&held)\n')
    out.append('    if file.len < 40usize || file[25usize] != 3u8 { os.exit(%di32) }\n' % (code + 2))
    out.append('    var reader_state = io.SliceReader { data: file, off: 0usize }\n    let reader = io.slice_reader(&reader_state)\n')
    out.append('    let (back, decode_error) = png.decode(a, reader, png.DecodeOptions { max_width: 4096u32, max_height: 4096u32, max_pixels: 16777216u64, verify_crc: true })\n')
    out.append('    if decode_error != ok { os.exit(%di32) }\n' % (code + 3))
    out.append('    if fnv(back.pixels[0..%d]) != %du32 { os.exit(%di32) }\n' % (W * H * 4, fnv(flat(q)), code + 4))
    code += 10
    out.append('    // refusals\n')
    out.append('    var gray: [64]u8 = zero\n')
    out.append('    let (g1, g2, grey_error) = png.quantize(store[0..], image.ConstImage { pixels: gray[0..], width: 8u32, height: 8u32, stride: 8usize, format: .R8, alpha: .Opaque }, 16usize)\n')
    out.append('    if grey_error != png.Unsupported { os.exit(%di32) }\n' % code)
    out.append('    let (z1, z2, zero_error) = png.quantize(store[0..], src_png, 0usize)\n')
    out.append('    if zero_error != png.Invalid { os.exit(%di32) }\n' % (code + 1))
    out.append('    let (b1, b2, big_error) = png.quantize(store[0..], src_png, 257usize)\n')
    out.append('    if big_error != png.Invalid { os.exit(%di32) }\n' % (code + 2))
    out.append('    ret ok\n}\n')
    target = Path(__file__).resolve().parent.parent / 'tests/selfhost/fixtures/link/fmt_png_quant/src/main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(''.join(out), encoding='utf-8', newline='\n')
    print('wrote', target)


main()
