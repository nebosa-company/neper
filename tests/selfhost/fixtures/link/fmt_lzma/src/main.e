// `e.fmt.lzma`: liblzma's alone stream of a 300-byte repetitive text decoded back
// (end marker, size unknown), the same stream with the header patched to the known
// size (marker still trailing), a 4 KB LCG buffer with runs and repeats (FNV-pinned
// against reference.py beside this fixture) from its alone stream, liblzma's raw
// stream through `decode_raw`, three refusals (properties byte 225, a truncated
// stream, a short destination), and the .xz container with a CRC32 check, with a
// CRC64 check, and with a corrupted check. Every check has its own exit code.
use e.fmt.lzma as lzma
use e.io
use e.mem
use e.os

fn text() -> str { ret "the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over" }
fn alone_text() -> str { ret "\x5d\x00\x00\x80\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00\x3a\x1a\x08\xce\x76\xc7\xe5\xe9\xd6\x07\x34\xc3\xd1\x0e\xbf\xce\x55\xe1\xaa\xbd\xe0\xe4\x8f\x98\x01\xdd\x8d\xe5\x07\x54\x9e\x65\x25\x5f\x27\x3a\x6a\x7e\xb4\xd3\x49\x05\x51\x23\x73\x70\x8c\x38\x1b\xff\xff\xf0\x86\x40\x00" }
fn alone_buf() -> str { ret "\x5d\x00\x00\x80\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00\x01\x60\x15\xb6\x1b\x01\xf8\xe3\x38\x2f\xd0\x85\x90\x2a\xab\xf8\xd5\x4a\x40\xd9\xdc\xec\x21\xc2\x26\x44\x92\xca\x54\xd1\x14\x28\x8a\x6e\x83\x8e\x14\xc6\x9a\xde\x85\x75\x1e\x22\xca\xf6\xad\x51\xee\x70\x8d\x98\x62\x86\x3d\x01\xe2\x03\xef\x6c\x89\x57\x47\x60\xe3\xf7\xe1\x79\xa6\x9a\xb6\xdb\x03\xa1\xea\x84\x09\x7b\xe2\xe1\x84\x35\x07\x5e\x15\x10\xbe\x4f\xec\xc8\x5a\x06\x64\x6d\x85\x71\xa4\x2a\x81\x88\x16\xa5\xea\x77\x45\xb8\x67\xdb\x2b\x64\x32\x6c\x86\x7c\xa8\x55\xd3\x08\x4d\xee\x86\x79\x02\x90\x8d\xfd\xf7\x4b\xee\x1f\xcb\x73\x25\x42\xe7\xe1\xe3\xd1\x90\x93\x01\xb2\x6b\x0a\xc4\x42\xd8\xdc\xf1\x6b\x1c\xf2\x8e\x4a\x29\x90\xc1\xb2\x7f\x77\x4f\x8f\x03\x82\xf7\x00\x4b\x82\xcb\x89\xcb\xd9\x1b\x23\xb9\x57\x18\x28\x16\x34\xdf\xfe\x9f\x80\x38\x9b\x36\x00\xdb\x78\x8f\x90\x28\x2b\xf0\x05\xd4\x22\xe7\xe0\x66\x38\x27\x90\xb4\x78\xc5\xc0\x0d\xde\x40\x6f\x6d\xf0\xea\xc1\x29\xdc\x0e\x28\xa9\x70\x4a\xe9\x65\x8d\x92\xc6\x9b\xd7\xae\xdf\x2a\x01\x08\x8d\x91\xd7\x5c\x57\x0d\x5d\xf6\x92\x81\xd5\x3e\xb8\x87\xe5\x46\xd3\x79\x25\xc7\xed\x08\x9e\x9b\xc0\x42\x7a\xaf\x37\x06\x7e\x0e\x7b\xe7\x54\x01\xe0\x95\x90\xf6\xa9\x6d\xb2\x98\xa3\x1a\x0c\x70\x96\x44\xdb\xfe\x4d\x69\x4a\x9c\x36\x0a\x89\xce\xfd\xc8\xbf\x9f\xbb\xb8\xc6\xcd\x8a\x10\xad\x67\xc0\x07\xa1\x58\x66\x2c\xbc\xb3\x9f\x41\x18\xba\xbf\x1d\x0a\xa8\x74\x6d\xbb\x6b\xa9\x64\x6c\xa3\x94\x57\x51\x32\x9f\xa7\x20\x95\x28\x11\x32\xb5\xaa\xe6\x61\x52\xc0\x2c\x10\xd2\x62\xea\x2e\x13\xec\x14\x00\x6e\x65\x03\x98\x16\xd3\xca\xbd\x2c\x74\xc3\x30\x12\x65\x96\xe1\x2d\xd5\x0e\xe0\xfd\xda\x71\x34\xe2\x85\xe6\x87\x7d\xef\x78\x5d\x3f\x6b\x7f\x1d\x01\x38\x0d\x87\x07\x56\x9b\x24\x4b\x8f\x80\xc3\x71\xdf\x84\xdd\x6d\x73\xec\xac\x5a\xab\x91\x08\x16\x7a\x5f\x3c\xc6\x02\x51\xf5\x19\xe4\xec\xa7\xf9\x6b\xf9\x50\x8d\x2c\x4f\x0e\x84\xd7\xa3\x26\xfb\x1b\x44\x76\x5b\x5b\x62\x4c\x6a\x07\xd6\xa0\xdd\xea\x90\xff\xe1\xc0\x17\x0a\x05\xb7\x85\x1b\xb9\xa2\xd6\x0a\xd1\x2f\x63\x77\x72\x4c\x4e\x5f\x8f\xa7\xd7\x79\x26\x4a\x0c\xb2\xb2\x63\x46\x97\xf8\xe3\x92\x12\xfd\x57\x2c\x7a\xfe\x22\xb2\xd7\xff\xff\xda\x4d\x4b\x89" }
fn raw_text() -> str { ret "\x00\x3a\x1a\x08\xce\x76\xc7\xe5\xe9\xd6\x07\x34\xc3\xd1\x0e\xbf\xce\x55\xe1\xaa\xbd\xe0\xe4\x8f\x98\x01\xdd\x8d\xe5\x07\x54\x9e\x65\x25\x5f\x27\x3a\x6a\x7e\xb4\xd3\x49\x05\x51\x23\x73\x70\x8c\x38\x1b\xff\xff\xf0\x86\x40\x00" }
fn xz_text() -> str { ret "\xfd\x37\x7a\x58\x5a\x00\x00\x01\x69\x22\xde\x36\x02\x00\x21\x01\x16\x00\x00\x00\x74\x2f\xe5\xa3\xe0\x01\x2b\x00\x32\x5d\x00\x3a\x1a\x08\xce\x76\xc7\xe5\xe9\xd6\x07\x34\xc3\xd1\x0e\xbf\xce\x55\xe1\xaa\xbd\xe0\xe4\x8f\x98\x01\xdd\x8d\xe5\x07\x54\x9e\x65\x25\x5f\x27\x3a\x6a\x7e\xb4\xd3\x49\x05\x51\x23\x73\x70\x6c\x45\x00\x00\x00\x00\x00\xf5\x62\x69\xd0\x00\x01\x4a\xac\x02\x00\x00\x00\xcb\x47\x48\x72\x3e\x30\x0d\x8b\x02\x00\x00\x00\x00\x01\x59\x5a" }
fn xz64() -> str { ret "\xfd\x37\x7a\x58\x5a\x00\x00\x04\xe6\xd6\xb4\x46\x02\x00\x21\x01\x16\x00\x00\x00\x74\x2f\xe5\xa3\xe0\x01\x2b\x00\x32\x5d\x00\x3a\x1a\x08\xce\x76\xc7\xe5\xe9\xd6\x07\x34\xc3\xd1\x0e\xbf\xce\x55\xe1\xaa\xbd\xe0\xe4\x8f\x98\x01\xdd\x8d\xe5\x07\x54\x9e\x65\x25\x5f\x27\x3a\x6a\x7e\xb4\xd3\x49\x05\x51\x23\x73\x70\x6c\x45\x00\x00\x00\x00\x00\x3e\xcc\xd1\xc0\x7e\xd6\x65\x4c\x00\x01\x4e\xac\x02\x00\x00\x00\xdd\x05\xd9\xe9\xb1\xc4\x67\xfb\x02\x00\x00\x00\x00\x04\x59\x5a" }

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

// Mirrors gen(4096) in reference.py: runs, copies of earlier bytes, and literals.
fn generate(out: []u8, n: usize) -> usize {
    var len = 0usize
    var state = 42u64
    while len < n {
        let r = lcg(&state)
        let kind = r % 4u64
        if kind == 0u64 {
            let v = u8(lcg(&state) & 255u64)
            let count = 8usize + usize(r % 40u64)
            var k = 0usize
            while k < count {
                out[len + k] = v
                k += 1usize
            }
            len += count
        } else if kind == 1u64 && len > 16usize {
            let start = usize((r >> 8u32) % u64(len - 8usize))
            var count = 16usize + usize((r >> 4u32) % 48u64)
            if start + count > len { count = len - start }
            var k = 0usize
            while k < count {
                out[len + k] = out[start + k]
                k += 1usize
            }
            len += count
        } else {
            let count = 1usize + usize(r % 3u64)
            var k = 0usize
            while k < count {
                out[len + k] = u8(lcg(&state) & 15u64)
                k += 1usize
            }
            len += count
        }
    }
    ret n
}

fn fnv1a(data: []const u8) -> u32 {
    var h = 2166136261u32
    var i = 0usize
    while i < data.len {
        h = (h ^ u32(data[i])) *% 16777619u32
        i += 1usize
    }
    ret h
}

fn copy(dst: []u8, src: []const u8) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var probs: [7990]u16 = zero
    var out: [4200]u8 = zero
    var expect: [4200]u8 = zero
    var scratch: [128]u8 = zero

    // 1: the header reads lc=3 lp=0 pb=2, unknown size.
    let (p, e0) = lzma.header(alone_text())
    if e0 != ok || p.lc != 3u32 || p.lp != 0u32 || p.pb != 2u32 || p.dict_size != 8388608u32 || p.has_size { os.exit(1i32) }
    if lzma.probs_required(3u32, 0u32) != 7990usize { os.exit(1i32) }

    // 2: the alone stream decodes to the text.
    let (n2, e2) = lzma.decode(alone_text(), out[..], probs[..])
    if e2 != ok || !bytes_equal(out[..n2], text()) { os.exit(2i32) }

    // 3: with the size known (patched header), the trailing marker is accepted.
    copy(scratch[..], alone_text())
    scratch[5] = 44u8
    scratch[6] = 1u8
    var i = 7usize
    while i < 13usize {
        scratch[i] = 0u8
        i += 1usize
    }
    let (p3, e3a) = lzma.header(scratch[..alone_text().len])
    if e3a != ok || !p3.has_size || p3.unpacked != 300u64 { os.exit(3i32) }
    let (n3, e3) = lzma.decode(scratch[..alone_text().len], out[..], probs[..])
    if e3 != ok || n3 != 300usize || !bytes_equal(out[..n3], text()) { os.exit(3i32) }

    // 4: the LCG buffer matches reference.py and its alone stream decodes to it.
    let n = generate(expect[..], 4096usize)
    if fnv1a(expect[..n]) != 421437064u32 { os.exit(4i32) }
    let (n4, e4) = lzma.decode(alone_buf(), out[..], probs[..])
    if e4 != ok || !bytes_equal(out[..n4], expect[..n]) { os.exit(5i32) }

    // 5: the raw stream through decode_raw with the size unknown.
    var raw: lzma.Props = zero
    raw.lc = 3u32
    raw.lp = 0u32
    raw.pb = 2u32
    raw.dict_size = 8388608u32
    raw.has_size = false
    let (n5, e5) = lzma.decode_raw(raw, raw_text(), out[..], probs[..])
    if e5 != ok || !bytes_equal(out[..n5], text()) { os.exit(6i32) }

    // 6: refusals.
    copy(scratch[..], alone_text())
    scratch[0] = 225u8
    let (_, e6) = lzma.decode(scratch[..alone_text().len], out[..], probs[..])
    if e6 != lzma.Invalid { os.exit(7i32) }
    let (_, e7) = lzma.decode(alone_text()[..40usize], out[..], probs[..])
    if e7 != lzma.Malformed { os.exit(8i32) }
    let (_, e8) = lzma.decode(alone_text(), out[..100usize], probs[..])
    if e8 != lzma.TooSmall { os.exit(9i32) }
    let (_, e9) = lzma.decode(alone_text(), out[..], probs[..100usize])
    if e9 != lzma.TooSmall { os.exit(10i32) }

    // 7: .xz with CRC32, with CRC64, and with a corrupted check.
    let (n10, e10) = lzma.decode_xz(xz_text(), out[..], probs[..])
    if e10 != ok || !bytes_equal(out[..n10], text()) { os.exit(11i32) }
    let (n11, e11) = lzma.decode_xz(xz64(), out[..], probs[..])
    if e11 != ok || !bytes_equal(out[..n11], text()) { os.exit(12i32) }
    copy(scratch[..], xz_text())
    scratch[85] = scratch[85] ^ 1u8
    let (_, e12) = lzma.decode_xz(scratch[..xz_text().len], out[..], probs[..])
    if e12 != lzma.Checksum { os.exit(13i32) }
    let (_, e13) = lzma.decode_xz(xz_text(), out[..200usize], probs[..])
    if e13 != lzma.TooSmall { os.exit(14i32) }

    try io.print("fmt lzma ok\n")
    ret ok
}
