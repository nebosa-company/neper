// SpookyHash V2 against R's digest(algo = "spookyhash"). digest hashes the binary serialization
// of the object without its 14-byte header: for a raw vector, the flags word 0x18, the length
// and the bytes, little-endian. tests/oracle/spooky.json comes from
// `Rscript scripts/r_oracle/generate.R hash`.

use e.algo.hash.spooky as spooky
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn stream(a: *mem.Arena, len: usize, salt: u64) -> []u8 {
    let (buf, e) = mem.alloc[u8](a, len + 8usize)
    if e != ok { os.exit(5) }
    buf[0usize] = 24u8
    buf[1usize] = 0u8
    buf[2usize] = 0u8
    buf[3usize] = 0u8
    buf[4usize] = u8(len & 255usize)
    buf[5usize] = u8((len >> 8usize) & 255usize)
    buf[6usize] = u8((len >> 16usize) & 255usize)
    buf[7usize] = u8((len >> 24usize) & 255usize)
    var i = 0usize
    while i < len {
        buf[8usize + i] = u8((u64(i) * 31u64 + salt * 17u64 + 7u64) % 256u64)
        i += 1usize
    }
    ret buf[0usize..len + 8usize]
}

// h1 then h2, each as eight little-endian bytes in hex.
fn hex_pair(a: *mem.Arena, p: spooky.Pair) -> []u8 {
    let (buf, e) = mem.alloc[u8](a, 32usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < 16usize {
        var v = p.h1
        var k = i
        if i >= 8usize {
            v = p.h2
            k = i - 8usize
        }
        let byte = u8((v >> u64(8usize * k)) & 255u64)
        let hi = byte >> 4u8
        let lo = byte & 15u8
        var ch = 48u8 + hi
        if hi > 9u8 { ch = 87u8 + hi }
        var cl = 48u8 + lo
        if lo > 9u8 { cl = 87u8 + lo }
        buf[2usize * i] = ch
        buf[2usize * i + 1usize] = cl
        i += 1usize
    }
    ret buf
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spooky.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let data = stream(a, usize(c.args[0]), u64(c.args[1]))
        let text = hex_pair(a, spooky.spooky128(data, 0u64, 0u64))
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 20usize {
                let _ = io.print("len ")
                let _ = io.print(text)
                let _ = io.print(" vs ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
