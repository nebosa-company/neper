# Writes src/main.e: a seeded word text, zlib's raw-deflate (dynamic Huffman) stream of
# it as the reference input, and the checks. Run from this directory after a change.
import random
import zlib

random.seed(7)
words = ["neper", "compiles", "itself", "on", "both", "hosts", "and", "the", "fixture", "checks",
         "every", "exit", "code", "deflate", "window", "block", "huffman", "stored", "dynamic", "fixed"]
text = (" ".join(random.choice(words) for _ in range(600))).encode()
co = zlib.compressobj(9, zlib.DEFLATED, -15)
dyn = co.compress(text) + co.flush()
assert (dyn[0] >> 1) & 3 == 2, "zlib must have picked a dynamic block"


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


HEADER = '''// `e.algo.deflate`: zlib's dynamic-Huffman stream of a 3758-byte text (reference.py
// beside this fixture) decoded whole and in seven-byte input, thirteen-byte output
// steps; the text encoded at every level, the stored size checked, each decoded back;
// a 70000-byte pattern encoded across three blocks in 1000-byte output chunks and
// decoded through a 32 KiB window; refusals for block type 3, a truncated stream at
// finish, a distance past the window limit, a bad stored length and a zero window.
// Every check has its own exit code.
use e.os
use e.mem
use e.algo.deflate as deflate

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Decodes `source` whole into `out`; the byte count, or 0 on any refusal.
fn inflate(storage: []u8, source: []const u8, out: []u8, window: usize) -> (usize, err) {
    let (d0, d_error) = deflate.decoder(storage, window)
    if d_error != ok { ret (0usize, d_error) }
    var d = d0
    let (consumed, written, status, decode_error) = deflate.decode(&d, source, out, true)
    if decode_error != ok { ret (0usize, decode_error) }
    if status != .Finished { ret (0usize, deflate.Invalid) }
    ret (written, ok)
}

// Encodes `source` whole into `out` at `level`; the byte count.
fn deflate_all(storage: []u8, source: []const u8, out: []u8, level: deflate.Level) -> (usize, err) {
    let (e0, e_error) = deflate.encoder(storage, level)
    if e_error != ok { ret (0usize, e_error) }
    var e = e0
    let (consumed, written, status, encode_error) = deflate.encode(&e, source, out, true)
    if encode_error != ok { ret (0usize, encode_error) }
    if status != .Finished || consumed != source.len { ret (0usize, deflate.Invalid) }
    ret (written, ok)
}

// Storage the module casts to its state struct: taken as u64s so it is 8-aligned.
fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
'''

BODY = '''    let (dec_storage, s1) = aligned(a, 40000usize)
    if s1 != ok { os.exit(1) }
    let (enc_storage, s2) = aligned(a, 150000usize)
    if s2 != ok { os.exit(2) }
    let (out, s3) = mem.alloc[u8](a, 80000usize)
    if s3 != ok { os.exit(3) }
    let (packed, s4) = mem.alloc[u8](a, 80000usize)
    if s4 != ok { os.exit(4) }
    let (big, s5) = mem.alloc[u8](a, 70000usize)
    if s5 != ok { os.exit(5) }
    // The dynamic stream, whole.
    let (n1, e1) = inflate(dec_storage, dyn, out, 32768usize)
    if e1 != ok { os.exit(6) }
    if !same(out[..n1], text) { os.exit(7) }
    // In steps: seven bytes of input, thirteen of output.
    let (d0, e2) = deflate.decoder(dec_storage, 32768usize)
    if e2 != ok { os.exit(8) }
    var d = d0
    var in_at = 0usize
    var out_at = 0usize
    var saw_need_input = false
    var saw_need_output = false
    var rounds = 0usize
    while true {
        rounds += 1usize
        if rounds > 10000usize { os.exit(9) }
        var in_end = in_at + 7usize
        if in_end > dyn.len { in_end = dyn.len }
        var out_end = out_at + 13usize
        if out_end > out.len { out_end = out.len }
        let (consumed, written, status, step_error) = deflate.decode(&d, dyn[in_at..in_end], out[out_at..out_end], in_end == dyn.len)
        if step_error != ok { os.exit(10) }
        in_at += consumed
        out_at += written
        if status == .Finished { break }
        if status == .NeedInput { saw_need_input = true }
        if status == .NeedOutput { saw_need_output = true }
    }
    if !saw_need_input || !saw_need_output { os.exit(11) }
    if !same(out[..out_at], text) { os.exit(12) }
    // Encode at each level and decode back.
    let (stored_len, e3) = deflate_all(enc_storage, text, packed, .Fast)
    if e3 != ok || stored_len != text.len + 5usize { os.exit(13) }
    let (n2, e4) = inflate(dec_storage, packed[..stored_len], out, 32768usize)
    if e4 != ok || !same(out[..n2], text) { os.exit(14) }
    let (balanced_len, e5) = deflate_all(enc_storage, text, packed, .Balanced)
    if e5 != ok || balanced_len >= text.len / 2usize { os.exit(15) }
    let (n3, e6) = inflate(dec_storage, packed[..balanced_len], out, 32768usize)
    if e6 != ok || !same(out[..n3], text) { os.exit(16) }
    let (best_len, e7) = deflate_all(enc_storage, text, packed, .Best)
    if e7 != ok || best_len > balanced_len { os.exit(17) }
    let (n4, e8) = inflate(dec_storage, packed[..best_len], out, 32768usize)
    if e8 != ok || !same(out[..n4], text) { os.exit(18) }
    // Three blocks, output taken in 1000-byte chunks.
    var i = 0usize
    while i < big.len {
        big[i] = u8((i * 7usize) & 255usize) ^ u8((i >> 5u32) & 255usize)
        i += 1usize
    }
    let (e0, e9) = deflate.encoder(enc_storage, .Balanced)
    if e9 != ok { os.exit(19) }
    var e = e0
    in_at = 0usize
    out_at = 0usize
    rounds = 0usize
    while true {
        rounds += 1usize
        if rounds > 10000usize { os.exit(20) }
        var out_end = out_at + 1000usize
        if out_end > packed.len { out_end = packed.len }
        let (consumed, written, status, step_error) = deflate.encode(&e, big[in_at..], packed[out_at..out_end], true)
        if step_error != ok { os.exit(21) }
        in_at += consumed
        out_at += written
        if status == .Finished { break }
        if status == .NeedInput { os.exit(22) }
    }
    if in_at != big.len || out_at >= big.len { os.exit(23) }
    let (n5, e10) = inflate(dec_storage, packed[..out_at], out, 32768usize)
    if e10 != ok || !same(out[..n5], big) { os.exit(24) }
    // Refusals.
    let type3: [2]u8 = [2]u8{ 7, 0 }
    let (n6, e11) = inflate(dec_storage, type3[0..], out, 32768usize)
    if e11 != deflate.Invalid { os.exit(25) }
    let (n7, e12) = inflate(dec_storage, dyn[..100], out, 32768usize)
    if e12 != deflate.Invalid { os.exit(26) }
    let (n8, e13) = inflate(dec_storage, packed[..out_at], out, 16usize)
    if e13 != deflate.Invalid { os.exit(27) }
    let bad_stored: [7]u8 = [7]u8{ 1, 2, 0, 2, 0, 65, 66 }
    let (n9, e14) = inflate(dec_storage, bad_stored[0..], out, 32768usize)
    if e14 != deflate.Invalid { os.exit(28) }
    let (zero_window, e15) = deflate.decoder_storage(0usize)
    if e15 != deflate.Invalid { os.exit(29) }
    let (small, e16) = deflate.decoder(dec_storage[..100], 32768usize)
    if e16 != deflate.TooLarge { os.exit(30) }
    ret ok
}
'''

source = HEADER + "    let text = " + literal(text) + "\n    let dyn = " + literal(dyn) + "\n" + BODY
open('src/main.e', 'w', encoding='utf-8', newline='\n').write(source)
print(len(text), len(dyn))
