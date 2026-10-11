// GIF (87a and 89a) decoder (L124) including animation. `decode` returns the first frame
// composed on the logical screen; `decode_frames` returns every frame as the full-canvas
// Rgba8 picture a viewer shows after that frame is drawn, with its delay (hundredths of a
// second) and the disposal method that follows it. Composition follows the format: the
// canvas starts transparent, a frame's non-transparent pixels are drawn over it at the
// frame's offset (interlaced rows put back in order), and before the next frame the
// previous frame's disposal applies -- 0 and 1 leave the canvas, 2 clears the frame's
// rectangle to transparent, 3 restores what was there before the frame was drawn.
// Local and global palettes, the transparent index of a graphic control extension, and
// the variable-width LZW of 2 to 8 bit roots are read; comment, application and plain text
// extensions are skipped. Bounded: the canvas is checked against the options before any
// pixel is taken (zero selects 16,384 per side and 16,777,216 pixels), the number of
// frames against `max_frames` (zero selects 1,024) and the sum of all frames' bytes against
// `max_bytes` (zero selects 256 MiB); a frame outside the canvas or an LZW stream that ends
// short of its pixels is `Invalid`. Decode only.

use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64, max_frames: u32, max_bytes: u64 }
type Frame = struct { image: image.Image, delay: u32, disposal: u8, x: u32, y: u32, width: u32, height: u32 }
error Invalid
error Unsupported
error TooLarge

const READ_LIMIT: usize = 1073741824usize

fn le16(d: []const u8, at: usize) -> u32 { ret u32(d[at]) | (u32(d[at + 1usize]) << 8u32) }

fn within(w: u32, h: u32, options: DecodeOptions) -> err {
    var max_w = options.max_width
    var max_h = options.max_height
    var max_pixels = options.max_pixels
    if max_w == 0u32 { max_w = 16384u32 }
    if max_h == 0u32 { max_h = 16384u32 }
    if max_pixels == 0u64 { max_pixels = 16777216u64 }
    if w > max_w || h > max_h { ret TooLarge }
    if u64(w) * u64(h) > max_pixels { ret TooLarge }
    ret ok
}

fn check_signature(d: []const u8) -> err {
    if d.len < 13usize { ret Invalid }
    if d[0] != 71u8 || d[1] != 73u8 || d[2] != 70u8 || d[3] != 56u8 { ret Invalid }
    if (d[4] != 55u8 && d[4] != 57u8) || d[5] != 97u8 { ret Invalid }
    ret ok
}

// The end of the sub-block chain that starts at `at`, and the sum of its lengths.
fn sub_blocks(d: []const u8, at: usize) -> (usize, usize, err) {
    var p = at
    var total = 0usize
    while true {
        if p >= d.len { ret (0usize, 0usize, Invalid) }
        let n = usize(d[p])
        p += 1usize
        if n == 0usize { break }
        if p + n > d.len { ret (0usize, 0usize, Invalid) }
        total += n
        p += n
    }
    ret (p, total, ok)
}

fn copy_sub_blocks(d: []const u8, at: usize, out: []u8) {
    var p = at
    var w = 0usize
    while true {
        let n = usize(d[p])
        p += 1usize
        if n == 0usize { break }
        var k = 0usize
        while k < n {
            out[w + k] = d[p + k]
            k += 1usize
        }
        w += n
        p += n
    }
}

// Counts the image descriptors; also the logical screen's size and where the blocks start.
fn count_frames(d: []const u8) -> (u32, usize, err) {
    var at = 13usize
    if (d[10] & 128u8) != 0u8 { at += 3usize * (1usize << (usize(d[10] & 7u8) + 1usize)) }
    if at > d.len { ret (0u32, 0usize, Invalid) }
    let start = at
    var frames = 0u32
    while at < d.len {
        let tag = d[at]
        if tag == 59u8 { break }
        if tag == 33u8 {
            if at + 2usize > d.len { ret (0u32, 0usize, Invalid) }
            let (next, _, failure) = sub_blocks(d, at + 2usize)
            if failure != ok { ret (0u32, 0usize, failure) }
            at = next
        } else if tag == 44u8 {
            if at + 10usize > d.len { ret (0u32, 0usize, Invalid) }
            var p = at + 10usize
            if (d[at + 9usize] & 128u8) != 0u8 { p += 3usize * (1usize << (usize(d[at + 9usize] & 7u8) + 1usize)) }
            p += 1usize
            if p > d.len { ret (0u32, 0usize, Invalid) }
            let (next, _, failure) = sub_blocks(d, p)
            if failure != ok { ret (0u32, 0usize, failure) }
            at = next
            frames += 1u32
        } else {
            ret (0u32, 0usize, Invalid)
        }
    }
    ret (frames, start, ok)
}

// The canvas size and the number of frames, from the block structure alone; the reader is
// buffered in the arena up to a bound.
fn inspect(a: *mem.Arena, source: io.Reader) -> (image.Info, err) {
    var r = source
    var info: image.Info = zero
    let (d, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (info, read_error) }
    let sig = check_signature(d)
    if sig != ok { ret (info, sig) }
    let (count, start, count_error) = count_frames(d)
    if count_error != ok { ret (info, count_error) }
    info.width = le16(d, 6usize)
    info.height = le16(d, 8usize)
    info.format = .Rgba8
    info.alpha = .Straight
    info.frames = count
    ret (info, ok)
}

// Decodes LZW with an initial code size of `root` bits into `out` (one byte per pixel);
// returns how many bytes were produced.
fn lzw(src: []const u8, root: u32, out: []u8) -> (usize, err) {
    if root < 2u32 || root > 8u32 { ret (0usize, Invalid) }
    var prefix: [4096]u16 = zero
    var suffix: [4096]u8 = zero
    var stack: [4097]u8 = zero
    let clear = 1u32 << root
    let end = clear + 1u32
    var next = clear + 2u32
    var size = root + 1u32
    var acc = 0u32
    var nbits = 0u32
    var pos = 0usize
    var produced = 0usize
    var old = 4294967295u32
    var first = 0u32
    while true {
        while nbits < size {
            if pos >= src.len { ret (produced, ok) }
            acc = acc | (u32(src[pos]) << nbits)
            nbits += 8u32
            pos += 1usize
        }
        let code = acc & ((1u32 << size) - 1u32)
        acc = acc >> size
        nbits -= size
        if code == clear {
            next = clear + 2u32
            size = root + 1u32
            old = 4294967295u32
            continue
        }
        if code == end { break }
        if old == 4294967295u32 {
            if code >= clear { ret (produced, Invalid) }
            if produced >= out.len { break }
            out[produced] = u8(code)
            produced += 1usize
            old = code
            first = code
            continue
        }
        let incoming = code
        var c = code
        var sp = 0usize
        if c >= next {
            if c > next { ret (produced, Invalid) }
            stack[sp] = u8(first)
            sp += 1usize
            c = old
        }
        while c >= clear {
            if sp >= 4096usize || c >= 4096u32 { ret (produced, Invalid) }
            stack[sp] = suffix[usize(c)]
            sp += 1usize
            c = u32(prefix[usize(c)])
        }
        first = c
        stack[sp] = u8(c)
        sp += 1usize
        while sp > 0usize {
            sp -= 1usize
            if produced >= out.len { ret (produced, ok) }
            out[produced] = stack[sp]
            produced += 1usize
        }
        if next < 4096u32 {
            prefix[usize(next)] = u16(old)
            suffix[usize(next)] = u8(first)
            next += 1u32
            if next == (1u32 << size) && size < 12u32 { size += 1u32 }
        }
        old = incoming
    }
    ret (produced, ok)
}

fn decode_frames(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> ([]Frame, err) {
    var nothing: []Frame = zero
    var r = source
    let (d, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (nothing, read_error) }
    let sig = check_signature(d)
    if sig != ok { ret (nothing, sig) }
    let cw = le16(d, 6usize)
    let ch = le16(d, 8usize)
    if cw == 0u32 || ch == 0u32 { ret (nothing, Invalid) }
    let within_error = within(cw, ch, options)
    if within_error != ok { ret (nothing, within_error) }
    let (count, start, count_error) = count_frames(d)
    if count_error != ok { ret (nothing, count_error) }
    if count == 0u32 { ret (nothing, Invalid) }
    var max_frames = options.max_frames
    if max_frames == 0u32 { max_frames = 1024u32 }
    if count > max_frames { ret (nothing, TooLarge) }
    var max_bytes = options.max_bytes
    if max_bytes == 0u64 { max_bytes = 268435456u64 }
    if u64(count) * u64(cw) * u64(ch) * 4u64 > max_bytes { ret (nothing, TooLarge) }
    let (frames, frames_error) = mem.alloc[Frame](a, usize(count))
    if frames_error != ok { ret (nothing, frames_error) }
    let canvas_bytes = usize(cw) * usize(ch) * 4usize
    let (canvas, canvas_error) = mem.alloc[u8](a, canvas_bytes)
    if canvas_error != ok { ret (nothing, canvas_error) }
    let (saved, saved_error) = mem.alloc[u8](a, canvas_bytes)
    if saved_error != ok { ret (nothing, saved_error) }
    var z = 0usize
    while z < canvas_bytes {
        canvas[z] = 0u8
        saved[z] = 0u8
        z += 1usize
    }
    var global: [768]u8 = zero
    var global_count = 0usize
    if (d[10] & 128u8) != 0u8 {
        global_count = 1usize << (usize(d[10] & 7u8) + 1usize)
        if 13usize + global_count * 3usize > d.len { ret (nothing, Invalid) }
        var k = 0usize
        while k < global_count * 3usize {
            global[k] = d[13usize + k]
            k += 1usize
        }
    }
    var at = start
    var done_frames = 0usize
    var delay = 0u32
    var disposal = 0u8
    var transparent = 256u32
    var prev_disposal = 0u8
    var prev_x = 0u32
    var prev_y = 0u32
    var prev_w = 0u32
    var prev_h = 0u32
    while at < d.len && done_frames < usize(count) {
        let tag = d[at]
        if tag == 59u8 { break }
        if tag == 33u8 {
            let label = d[at + 1usize]
            if label == 249u8 {
                // graphic control: block size 4, packed, delay, transparent index, terminator
                if at + 8usize > d.len || d[at + 2usize] != 4u8 { ret (nothing, Invalid) }
                let packed = d[at + 3usize]
                disposal = (packed >> 2u32) & 7u8
                delay = le16(d, at + 4usize)
                transparent = 256u32
                if (packed & 1u8) != 0u8 { transparent = u32(d[at + 6usize]) }
            }
            let (next, _, failure) = sub_blocks(d, at + 2usize)
            if failure != ok { ret (nothing, failure) }
            at = next
            continue
        }
        // an image descriptor
        let fx = le16(d, at + 1usize)
        let fy = le16(d, at + 3usize)
        let fw = le16(d, at + 5usize)
        let fh = le16(d, at + 7usize)
        let packed = d[at + 9usize]
        var p = at + 10usize
        if fw == 0u32 || fh == 0u32 || fx + fw > cw || fy + fh > ch { ret (nothing, Invalid) }
        var local: [768]u8 = zero
        var local_count = 0usize
        var palette_is_local = false
        if (packed & 128u8) != 0u8 {
            local_count = 1usize << (usize(packed & 7u8) + 1usize)
            if p + local_count * 3usize > d.len { ret (nothing, Invalid) }
            var k = 0usize
            while k < local_count * 3usize {
                local[k] = d[p + k]
                k += 1usize
            }
            p += local_count * 3usize
            palette_is_local = true
        }
        if p >= d.len { ret (nothing, Invalid) }
        let root = u32(d[p])
        p += 1usize
        let (after, total, blocks_error) = sub_blocks(d, p)
        if blocks_error != ok { ret (nothing, blocks_error) }
        let (stream, stream_error) = mem.alloc[u8](a, total + 1usize)
        if stream_error != ok { ret (nothing, stream_error) }
        copy_sub_blocks(d, p, stream)
        let pixels = usize(fw) * usize(fh)
        let (indices, indices_error) = mem.alloc[u8](a, pixels + 1usize)
        if indices_error != ok { ret (nothing, indices_error) }
        let (produced, lzw_error) = lzw(stream[..total], root, indices[..pixels])
        if lzw_error != ok { ret (nothing, lzw_error) }
        if produced < pixels { ret (nothing, Invalid) }
        // the previous frame's disposal comes first
        if done_frames > 0usize {
            if prev_disposal == 2u8 {
                var yy = prev_y
                while yy < prev_y + prev_h {
                    var xx = prev_x
                    while xx < prev_x + prev_w {
                        let o = (usize(yy) * usize(cw) + usize(xx)) * 4usize
                        canvas[o] = 0u8
                        canvas[o + 1usize] = 0u8
                        canvas[o + 2usize] = 0u8
                        canvas[o + 3usize] = 0u8
                        xx += 1u32
                    }
                    yy += 1u32
                }
            } else if prev_disposal == 3u8 {
                var k = 0usize
                while k < canvas_bytes {
                    canvas[k] = saved[k]
                    k += 1usize
                }
            }
        }
        // a frame that will be restored needs the canvas as it was before it
        var k = 0usize
        while k < canvas_bytes {
            saved[k] = canvas[k]
            k += 1usize
        }
        // interlaced rows: passes of step 8 (from 0), 8 (from 4), 4 (from 2), 2 (from 1)
        var pass = 0usize
        var next_row = 0usize
        var row = 0usize
        while row < usize(fh) {
            var dest_row = row
            if (packed & 64u8) != 0u8 {
                dest_row = next_row
                var step = 8usize
                if pass == 2usize { step = 4usize }
                if pass == 3usize { step = 2usize }
                next_row += step
                if next_row >= usize(fh) {
                    pass += 1usize
                    if pass == 1usize { next_row = 4usize }
                    if pass == 2usize { next_row = 2usize }
                    if pass == 3usize { next_row = 1usize }
                }
            }
            var col = 0usize
            while col < usize(fw) {
                let index = usize(indices[row * usize(fw) + col])
                if u32(index) != transparent {
                    var rr = 0u8
                    var gg = 0u8
                    var bb = 0u8
                    if palette_is_local {
                        if index >= local_count { ret (nothing, Invalid) }
                        rr = local[index * 3usize]
                        gg = local[index * 3usize + 1usize]
                        bb = local[index * 3usize + 2usize]
                    } else {
                        if index >= global_count { ret (nothing, Invalid) }
                        rr = global[index * 3usize]
                        gg = global[index * 3usize + 1usize]
                        bb = global[index * 3usize + 2usize]
                    }
                    let o = ((usize(fy) + dest_row) * usize(cw) + usize(fx) + col) * 4usize
                    canvas[o] = rr
                    canvas[o + 1usize] = gg
                    canvas[o + 2usize] = bb
                    canvas[o + 3usize] = 255u8
                }
                col += 1usize
            }
            row += 1usize
        }
        // the frame as shown
        let (shot, shot_error) = image.allocate(a, cw, ch, .Rgba8, .Straight)
        if shot_error != ok { ret (nothing, shot_error) }
        var y2 = 0usize
        while y2 < usize(ch) {
            var x2 = 0usize
            while x2 < usize(cw) * 4usize {
                shot.pixels[y2 * shot.stride + x2] = canvas[y2 * usize(cw) * 4usize + x2]
                x2 += 1usize
            }
            y2 += 1usize
        }
        frames[done_frames].image = shot
        frames[done_frames].delay = delay
        frames[done_frames].disposal = disposal
        frames[done_frames].x = fx
        frames[done_frames].y = fy
        frames[done_frames].width = fw
        frames[done_frames].height = fh
        prev_disposal = disposal
        prev_x = fx
        prev_y = fy
        prev_w = fw
        prev_h = fh
        done_frames += 1usize
        // the control extension applies to one frame
        delay = 0u32
        disposal = 0u8
        transparent = 256u32
        at = after
    }
    if done_frames != usize(count) { ret (nothing, Invalid) }
    ret (frames, ok)
}

// The first frame composed on the logical screen.
fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var limited = options
    limited.max_frames = 0u32
    let (frames, failure) = decode_frames(a, source, limited)
    if failure != ok { ret (zero, failure) }
    ret (frames[0usize].image, ok)
}
