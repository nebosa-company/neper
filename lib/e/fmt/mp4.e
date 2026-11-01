// ISO base media file (MP4) demuxer for the first video track: the box tree (moov, trak, mdia,
// minf, stbl), the sample description's codec and picture size with its configuration box
// (av1C, avcC or hvcC), and the sample table -- sizes (stsz), chunk offsets (stco, co64) mapped
// to samples by the chunk runs (stsc), decoding times (stts), composition offsets (ctts) and the
// sync samples (stss). The samples themselves stay in the caller's bytes: `bytes_of` returns a
// slice of them. Only the first video track is read; fragmented files (moof) are `Unsupported`.
// Boxes are bounds-checked against their parents, so a damaged file is `Invalid`, never a read
// past the data.

use e.mem

error Invalid
error Unsupported
error TooLarge

const MAX_SAMPLES: u32 = 4194304u32

type Sample = struct { offset: u64, size: u32, time: u64, delay: i32, sync: bool }
type Video = struct { codec: u32, width: u32, height: u32, timescale: u32, duration: u64, config: []const u8, samples: []Sample }
type Box = struct { start: usize, end: usize, found: bool }

fn fourcc(a: u8, b: u8, c: u8, d: u8) -> u32 {
    ret (u32(a) << 24u32) | (u32(b) << 16u32) | (u32(c) << 8u32) | u32(d)
}

fn be16(d: []const u8, at: usize) -> u32 {
    ret (u32(d[at]) << 8u32) | u32(d[at + 1usize])
}

fn be32(d: []const u8, at: usize) -> u32 {
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

fn be64(d: []const u8, at: usize) -> u64 {
    ret (u64(be32(d, at)) << 32u64) | u64(be32(d, at + 4usize))
}

// The first box of this kind inside [start, end): the box's payload is [start, end) of the result.
fn find(d: []const u8, start: usize, end: usize, kind: u32) -> Box {
    var at = start
    while at + 8usize <= end {
        var size = u64(be32(d, at))
        let k = be32(d, at + 4usize)
        var header = 8usize
        if size == 1u64 {
            if at + 16usize > end { break }
            size = be64(d, at + 8usize)
            header = 16usize
        }
        if size == 0u64 { size = u64(end - at) }
        if size < u64(header) || size > u64(end - at) { break }
        if k == kind { ret Box { start: at + header, end: at + usize(size), found: true } }
        at += usize(size)
    }
    ret Box { start: 0usize, end: 0usize, found: false }
}

// The same, the n-th box of that kind (0 is the first).
fn find_nth(d: []const u8, start: usize, end: usize, kind: u32, n: usize) -> Box {
    var at = start
    var seen = 0usize
    while at + 8usize <= end {
        var size = u64(be32(d, at))
        let k = be32(d, at + 4usize)
        var header = 8usize
        if size == 1u64 {
            if at + 16usize > end { break }
            size = be64(d, at + 8usize)
            header = 16usize
        }
        if size == 0u64 { size = u64(end - at) }
        if size < u64(header) || size > u64(end - at) { break }
        if k == kind {
            if seen == n { ret Box { start: at + header, end: at + usize(size), found: true } }
            seen += 1usize
        }
        at += usize(size)
    }
    ret Box { start: 0usize, end: 0usize, found: false }
}

// A full box's version (its first byte), after which the fields start at `start + 4`.
fn need(b: Box, bytes: usize) -> bool {
    ret b.found && b.end - b.start >= bytes
}

fn parse(a: *mem.Arena, d: []const u8) -> (Video, err) {
    var v: Video = zero
    let moov = find(d, 0usize, d.len, fourcc(109u8, 111u8, 111u8, 118u8))
    if !moov.found { ret (v, Invalid) }
    if find(d, moov.start, moov.end, fourcc(109u8, 118u8, 101u8, 120u8)).found { ret (v, Unsupported) }
    // the first track whose handler is `vide`
    var t = 0usize
    var trak = Box { start: 0usize, end: 0usize, found: false }
    var mdia = trak
    while true {
        trak = find_nth(d, moov.start, moov.end, fourcc(116u8, 114u8, 97u8, 107u8), t)
        if !trak.found { ret (v, Unsupported) }
        mdia = find(d, trak.start, trak.end, fourcc(109u8, 100u8, 105u8, 97u8))
        if mdia.found {
            let hdlr = find(d, mdia.start, mdia.end, fourcc(104u8, 100u8, 108u8, 114u8))
            if need(hdlr, 12usize) && be32(d, hdlr.start + 8usize) == fourcc(118u8, 105u8, 100u8, 101u8) { break }
        }
        t += 1usize
    }
    let mdhd = find(d, mdia.start, mdia.end, fourcc(109u8, 100u8, 104u8, 100u8))
    if !need(mdhd, 24usize) { ret (v, Invalid) }
    if d[mdhd.start] == 1u8 {
        if !need(mdhd, 32usize) { ret (v, Invalid) }
        v.timescale = be32(d, mdhd.start + 20usize)
        v.duration = be64(d, mdhd.start + 24usize)
    } else {
        v.timescale = be32(d, mdhd.start + 12usize)
        v.duration = u64(be32(d, mdhd.start + 16usize))
    }
    let minf = find(d, mdia.start, mdia.end, fourcc(109u8, 105u8, 110u8, 102u8))
    let stbl = find(d, minf.start, minf.end, fourcc(115u8, 116u8, 98u8, 108u8))
    if !minf.found || !stbl.found { ret (v, Invalid) }

    // the sample description: the first entry's codec, picture size and configuration box
    let stsd = find(d, stbl.start, stbl.end, fourcc(115u8, 116u8, 115u8, 100u8))
    if !need(stsd, 16usize + 86usize) { ret (v, Invalid) }
    let entry = stsd.start + 8usize
    let entry_size = usize(be32(d, entry))
    if entry_size < 86usize || entry + entry_size > stsd.end { ret (v, Invalid) }
    v.codec = be32(d, entry + 4usize)
    v.width = be16(d, entry + 8usize + 24usize)
    v.height = be16(d, entry + 8usize + 26usize)
    let kids = entry + 8usize + 78usize
    var cfg = find(d, kids, entry + entry_size, fourcc(97u8, 118u8, 49u8, 67u8))
    if !cfg.found { cfg = find(d, kids, entry + entry_size, fourcc(97u8, 118u8, 99u8, 67u8)) }
    if !cfg.found { cfg = find(d, kids, entry + entry_size, fourcc(104u8, 118u8, 99u8, 67u8)) }
    if cfg.found { v.config = d[cfg.start..cfg.end] }

    // sizes
    let stsz = find(d, stbl.start, stbl.end, fourcc(115u8, 116u8, 115u8, 122u8))
    if !need(stsz, 12usize) { ret (v, Invalid) }
    let fixed = be32(d, stsz.start + 4usize)
    let count = be32(d, stsz.start + 8usize)
    if count > MAX_SAMPLES { ret (v, TooLarge) }
    if fixed == 0u32 && !need(stsz, 12usize + usize(count) * 4usize) { ret (v, Invalid) }
    let (samples, samples_error) = mem.alloc[Sample](a, usize(count))
    if samples_error != ok { ret (v, TooLarge) }
    var i = 0usize
    while i < usize(count) {
        var size = fixed
        if fixed == 0u32 { size = be32(d, stsz.start + 12usize + i * 4usize) }
        samples[i] = Sample { offset: 0u64, size: size, time: 0u64, delay: 0i32, sync: true }
        i += 1usize
    }

    // chunk offsets, then the samples of each chunk laid one after the other
    var chunk_at = 0usize
    var chunks = 0u32
    var wide = false
    var co = find(d, stbl.start, stbl.end, fourcc(115u8, 116u8, 99u8, 111u8))
    if !co.found {
        co = find(d, stbl.start, stbl.end, fourcc(99u8, 111u8, 54u8, 52u8))
        wide = true
    }
    if !need(co, 8usize) { ret (v, Invalid) }
    chunks = be32(d, co.start + 4usize)
    chunk_at = co.start + 8usize
    var width_of_entry = 4usize
    if wide { width_of_entry = 8usize }
    if !need(co, 8usize + usize(chunks) * width_of_entry) { ret (v, Invalid) }
    let stsc = find(d, stbl.start, stbl.end, fourcc(115u8, 116u8, 115u8, 99u8))
    if !need(stsc, 8usize) { ret (v, Invalid) }
    let runs = be32(d, stsc.start + 4usize)
    if !need(stsc, 8usize + usize(runs) * 12usize) { ret (v, Invalid) }
    var sample = 0usize
    var chunk = 0u32
    while chunk < chunks && sample < usize(count) {
        // the run that holds this chunk (chunks count from 1)
        var per = 0u32
        var r = 0u32
        while r < runs {
            let first = be32(d, stsc.start + 8usize + usize(r) * 12usize)
            if first <= chunk + 1u32 { per = be32(d, stsc.start + 12usize + usize(r) * 12usize) }
            r += 1u32
        }
        var offset = 0u64
        if wide { offset = be64(d, chunk_at + usize(chunk) * 8usize) } else { offset = u64(be32(d, chunk_at + usize(chunk) * 4usize)) }
        var s = 0u32
        while s < per && sample < usize(count) {
            samples[sample].offset = offset
            offset += u64(samples[sample].size)
            sample += 1usize
            s += 1u32
        }
        chunk += 1u32
    }
    if sample != usize(count) { ret (v, Invalid) }
    i = 0usize
    while i < usize(count) {
        if samples[i].offset + u64(samples[i].size) > u64(d.len) { ret (v, Invalid) }
        i += 1usize
    }

    // decoding times
    let stts = find(d, stbl.start, stbl.end, fourcc(115u8, 116u8, 116u8, 115u8))
    if !need(stts, 8usize) { ret (v, Invalid) }
    let time_runs = be32(d, stts.start + 4usize)
    if !need(stts, 8usize + usize(time_runs) * 8usize) { ret (v, Invalid) }
    var at = 0usize
    var now = 0u64
    var tr = 0u32
    while tr < time_runs {
        let n = be32(d, stts.start + 8usize + usize(tr) * 8usize)
        let delta = be32(d, stts.start + 12usize + usize(tr) * 8usize)
        var k = 0u32
        while k < n && at < usize(count) {
            samples[at].time = now
            now += u64(delta)
            at += 1usize
            k += 1u32
        }
        tr += 1u32
    }

    // composition offsets, when there are any (frames out of order)
    let ctts = find(d, stbl.start, stbl.end, fourcc(99u8, 116u8, 116u8, 115u8))
    if need(ctts, 8usize) {
        let offsets = be32(d, ctts.start + 4usize)
        if !need(ctts, 8usize + usize(offsets) * 8usize) { ret (v, Invalid) }
        at = 0usize
        var cr = 0u32
        while cr < offsets {
            let n = be32(d, ctts.start + 8usize + usize(cr) * 8usize)
            let off = i32(be32(d, ctts.start + 12usize + usize(cr) * 8usize))
            var k = 0u32
            while k < n && at < usize(count) {
                samples[at].delay = off
                at += 1usize
                k += 1u32
            }
            cr += 1u32
        }
    }

    // sync samples: all of them when the box is missing
    let stss = find(d, stbl.start, stbl.end, fourcc(115u8, 116u8, 115u8, 115u8))
    if need(stss, 8usize) {
        let marks = be32(d, stss.start + 4usize)
        if !need(stss, 8usize + usize(marks) * 4usize) { ret (v, Invalid) }
        i = 0usize
        while i < usize(count) {
            samples[i].sync = false
            i += 1usize
        }
        var m = 0u32
        while m < marks {
            let number = be32(d, stss.start + 8usize + usize(m) * 4usize)
            if number >= 1u32 && usize(number) <= usize(count) { samples[usize(number) - 1usize].sync = true }
            m += 1u32
        }
    }
    v.samples = samples
    ret (v, ok)
}

// The bytes of sample i.
fn bytes_of(d: []const u8, v: *const Video, i: usize) -> ([]const u8, err) {
    if i >= v.samples.len { ret (d[0usize..0usize], Invalid) }
    let s = v.samples[i]
    let from = usize(s.offset)
    ret (d[from..from + usize(s.size)], ok)
}
