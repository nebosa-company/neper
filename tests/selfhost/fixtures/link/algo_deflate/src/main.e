// `e.algo.deflate`: zlib's dynamic-Huffman stream of a 3758-byte text (reference.py
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
    let text = "every both code compiles itself stored on exit dynamic compiles huffman and compiles itself deflate deflate itself the itself stored deflate compiles dynamic on the dynamic compiles dynamic dynamic code compiles the compiles stored both checks deflate both stored on dynamic checks stored hosts on dynamic dynamic and exit on stored itself dynamic compiles fixed and block stored deflate every window dynamic window exit checks the hosts the itself dynamic checks huffman block every window checks fixed itself on huffman deflate hosts every both block deflate compiles itself stored dynamic every every exit fixed block dynamic window itself itself fixture block itself compiles checks dynamic window checks code exit neper window exit hosts fixed on block compiles and checks both the code code block itself hosts window code stored fixture both deflate stored fixture deflate exit code the both itself hosts both the the neper block dynamic hosts fixture checks neper both deflate stored exit fixed dynamic every both huffman fixed compiles window stored code code code code on block code compiles and itself and window hosts on every fixed compiles on neper dynamic both stored on exit fixed neper itself and fixed code both fixture exit fixed exit block on on block window block block checks itself both on every fixture block hosts huffman neper and huffman exit both stored neper huffman checks itself fixture huffman exit hosts exit the stored stored huffman every the fixed and the code the and huffman block exit neper neper fixture block fixture and fixed exit window exit exit itself the on the block and every and block fixed fixed neper block exit itself on code and block hosts deflate every itself code window code itself hosts hosts both neper both dynamic window both fixed fixed block exit both stored stored both neper neper on huffman both deflate and and neper fixture and checks huffman the dynamic every fixture stored deflate both compiles exit window dynamic huffman deflate huffman both stored both huffman huffman neper window hosts fixed neper both hosts both block fixed on stored compiles every huffman huffman stored block on stored compiles the and fixture compiles on huffman window stored neper itself window every fixed huffman fixed huffman and fixture window huffman stored block huffman the huffman fixture stored and window both deflate on code window every itself the deflate itself and checks on both exit both fixture both window the on code block hosts the hosts deflate huffman code every deflate and exit every itself exit neper every stored window window neper code every huffman fixed checks huffman itself on the on itself fixture fixture compiles hosts fixture both deflate fixture code both stored huffman dynamic block every itself fixture compiles hosts deflate itself fixture neper itself fixture itself fixed the itself fixture on window neper every stored deflate fixture fixed both compiles huffman the on hosts fixture compiles hosts and checks checks huffman and checks window huffman hosts fixture exit neper fixture compiles neper neper huffman stored and huffman block the window on deflate block stored code huffman checks and the every and both code exit compiles both neper itself fixture deflate hosts compiles itself code huffman checks fixed the checks compiles window hosts hosts fixture window neper fixture exit every stored every the compiles checks and exit hosts neper every code itself block fixture huffman and the huffman neper itself fixture itself both code dynamic compiles code neper checks checks the itself dynamic huffman both fixed code every block both checks fixed both compiles huffman deflate huffman both huffman huffman dynamic neper dynamic the itself neper compiles"
    let dyn = "}W[r\xe2@\x0c\xbc\x8a\xafF\xf0P\xb8B<)\xecl\x92\xdb\xafGjI-\x99\xca\x07\x06\xcf\xe8\xd1z\x8b\xf6\xaf=\x7f\xa7\xb7\xbe\xdf\xa7k\x9f\xdb\xf1\xf8\xf8\x5c\x1em\x9b\x96}k\x8f\xdb\xb4\xed\xfd\xd9\xe6\xa9\xafS\xfbY\xf6i\xfe]/\x1f\xcb5\xc8\xee_\xb7\xdb\xc7e\x9d.\xeb|\xe2\x9d\xdb\xedq\xd9\x9b\x7f\xe3x\xbf\xb7\x22\xdd\x08\x5c\x80\xa99\xd4\x0e\xea\x93V;\x88\x0b\x86>X\xfc\x05*\xd4\xc2{\xbb\xbeo\xaeN\xce\xc2@\x17\xa6T\xb8\xb8\xf7m\xdf\xf8\xda\xbe\x87\xc5\xe2\x93\xe3\x0e\xb4fw\x85{[~\x8e\xdb\xc1\xf0\xf6\xe8\xd7\xf7jv\x93\x18|/\xeb\xdc\xbf\x9d\x19\xaf\xa2\x01\x88\x86]\x0a\x87\x5cXP[<TQ\x92\x0c\x0a\x05\x03\xee\x03\xbbq\x18\x1a\xd5\xd0\x22/T\xd4)F%\x84\x80\xa1|x\x0e\xec\xaa\x0e2\xb2m\x90\x80\xaf\x83p\xffz6\x90\xe2\xd0\xb5Y\xe8\xb2\x04\x9cJ\xf8E\xdb\xda>\xdb3\xf9N\xcdQ\x14\xdd\xfc\xe2b%mU\x88\xd8\xaa\xa93\xe3\x91\xa0\xa8 S<\xaea\xba\x03\x1f\x02\xccM\xe5\xceC-\xe1\x1c\xccC\x93p$\xf1\x0eb|\xd4\x98\xec:7G\xc4\x02:\x08_\xe8\xa7\x10\xe4\x08\x09\xb1\x85^\x09\xdc)\xb0\x11\x22\xc2\x1d\xf1 Gr\xe1\x0do\xc2\x9c\xf1\x13r\xbc\x82TsQv\x9c+|\xc3W\xaa\x92,P:R`\xa2f\xb8\xd2\xdcB<\xf2S\xb1\x1e\xc2\x1c7\xa0\xe9\x0bLQ_B\xbc\xc8c\xcc\x94\x9bj\x909OQ\x0d8v\xa2:\xc9\x0c%\xb1\xeb\xac\xc8D'f\xd4\xe0\xf89\x12\x01b\xac#\x19\xa5@\x1b\xf7\xd1_<\x7f\xc7\x0f\xc6\x84~\x105\xa2\xcfl\x98\xbd\x85o\x85\x81\xcbI\x1e\xd4\xc8\xd1\xa1\x95_Z\xa2\xa0\x8a^\xa7r8\x80\x04%\xba\x90\x80\x0e.u@n\x90\xde\x12\x0eJ.\xc3T@TF\x5c\x15\xb9mX\xb280\x82\xc4q\xe3\xd9\xc1^\xa3\xae\x99\x8an\xe0\x1f\x9f\xec[\xea1\xc6\xc5C-gX\x19\x0d\x18\xcc\xa8\x15\x8e\x867\x84\xda\xbe\x19\x18\x1b`\x179oS\x8d\xa6(\x09Ox\x93\xa3\x19\x13/\xa0\x89\x15U\x87\xe9\xb7\xfa\xab\x5c\x96\xa5\xde\xcf\xa8+\x98\x8c\xdc\x8dR\x0f\xb0\xc4\xa4\xbe\x92[\x1ao'\xa6\xc3,~\x05\x91\xe3C\x9282\xd4\xd8R\xec-\x87\x13&*\x94\xb2\x04QRt\x04+\xd2/M\x14\x08D\xb1\xd1\x5c\x8aU W\x8b\xf7\x19\x99\x8a\x82\x83\x13T\xcb\x98\xe1QW\xd0s\x98\x0a\xcd\xf8R\x02\x12Z\xa6G\xce\xf0\xa8l\x00/\xed\xee\x14\xf1<\xd8\x92k\x83v\xceK\x9b\xe7\xbe\x8d\x0eZz\x8a\xbe\xa2\xa7D\xc3\xa8Rv\xd9a\xbc\xb6\x997/\xbb\xefkvQ\xf2a\xb5\x01\xfd&\x955g\xddH\xfc<\xe23p\xca\x9b\xe2q\xba))\x9e\x05R\xb4O:\xb8\xc9\x95\x029\x0f\x93\x01\x17\x9az\xf4\x9f\xb4\xe1J\xc4\xca\xdc\xb31E\x83\xc2\xff}`=\x02\x1a\xea\xbb\xc5\xe5yW\xad+\xe9+\xad\x11=\xdf\x19\xf3\xb6\xc3\xe3\xa3\xb4\x8a\xec,\xaa\x1f[\xb2|\x10\xd7u\xd5\xebM\xe5r~\xf0\xe8\xca\xd3\x97\x03\xca\x8d\xe8\xaf\xe4\x0c\x17\x9e\xfe|\xc8)\x8a7%\xce\x8b?\x11ix\xd0v\x85\x9dQ\xb7%\xfa'\xf5W6\xbf\x1cHu@\x98\xe2\xbc\x02\x122\xeb:*\xfc?"
    let (dec_storage, s1) = aligned(a, 40000usize)
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
