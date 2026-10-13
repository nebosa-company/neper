// Differential check: encodes generated inputs at both lazy levels with odd chunk sizes
// and prints one FNV-1a line per case. Built against two copies of e.algo.deflate, the
// output of the two must match line for line; each stream is also decoded back.
use e.algo.deflate
use e.io
use e.mem
use e.os

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn gen(kind: usize, n: usize, data: []u8) {
    var s = u64(kind) * 7919u64 + 17u64
    var i = 0usize
    while i < n {
        s = (s * 1103515245u64 + 12345u64) & 2147483647u64
        let r = u32(s >> 16u64)
        var b = u8(r & 255u32)
        if kind == 1usize { b = u8(i * 7usize & 255usize) }
        if kind == 2usize { b = u8((r & 7u32) + 65u32) }
        if kind == 3usize { b = u8(((i >> 3u32) & 3usize) * 50usize + usize(r & 3u32)) }
        if kind == 4usize { b = 0u8 }
        if kind == 5usize {
            // repeats of a 300-byte phrase with noise
            b = u8(((i % 300usize) * 13usize) & 255usize)
            if (r & 63u32) == 0u32 { b = u8(r & 255u32) }
        }
        if kind == 6usize {
            // long distance repeats: copy from 20000 back with rare flips
            if i >= 20000usize && (r & 255u32) != 0u32 { b = data[i - 20000usize] }
        }
        if kind == 7usize {
            // matches at exactly 32768 and 32769 back
            if i >= 32768usize && (r & 15u32) != 0u32 { b = data[i - 32768usize + usize(r & 1u32)] }
        }
        data[i] = b
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (data, e1) = mem.alloc[u8](a, 300000usize)
    if e1 != ok { ret e1 }
    let (out, e2) = mem.alloc[u8](a, 600000usize)
    if e2 != ok { ret e2 }
    let (back, e3) = mem.alloc[u8](a, 300000usize)
    if e3 != ok { ret e3 }
    let (dstore, e4) = aligned(a, 400000usize)
    if e4 != ok { ret e4 }
    var kind = 0usize
    while kind < 8usize {
        var li = 0usize
        while li < 2usize {
            var chunk_i = 0usize
            while chunk_i < 3usize {
                var n = 250000usize
                if kind == 3usize { n = 70001usize }
                if kind == 7usize { n = 140001usize }
                gen(kind, n, data)
                var level = deflate.Level.Balanced
                if li == 1usize { level = .Best }
                let (es, e5) = aligned(a, deflate.encoder_storage(level) + 16usize)
                if e5 != ok { ret e5 }
                let (enc, e6) = deflate.encoder(es, level)
                if e6 != ok { ret e6 }
                var e = enc
                var step = 1000000usize
                if chunk_i == 1usize { step = 777usize }
                if chunk_i == 2usize { step = 40001usize }
                var consumed = 0usize
                var written = 0usize
                var done = false
                var guard = 0usize
                while !done && guard < 2000000usize {
                    guard += 1usize
                    var take = n - consumed
                    if take > step { take = step }
                    let fin = consumed + take == n
                    var room = out.len - written
                    if room > 4099usize { room = 4099usize }
                    let (c, w, st, er) = deflate.encode(&e, data[consumed..consumed + take], out[written..written + room], fin)
                    if er != ok { os.exit(2i32) }
                    consumed += c
                    written += w
                    if st == .Finished { done = true }
                }
                var h = 2166136261u64
                var k = 0usize
                while k < written {
                    h = ((h ^ u64(out[k])) * 16777619u64) & 4294967295u64
                    k += 1usize
                }
                let (dec, e7) = deflate.decoder(dstore, 32768usize)
                if e7 != ok { ret e7 }
                var d = dec
                let (dc, dw, dst, der) = deflate.decode(&d, out[0..written], back[0..], true)
                var good = 1usize
                if der != ok || dw != n { good = 0usize }
                var q = 0usize
                while good == 1usize && q < n {
                    if back[q] != data[q] { good = 0usize }
                    q += 1usize
                }
                try io.printf["{} {} {} {} {} {}\n"](kind, li, chunk_i, written, h, good)
                chunk_i += 1usize
            }
            li += 1usize
        }
        kind += 1usize
    }
    ret ok
}
