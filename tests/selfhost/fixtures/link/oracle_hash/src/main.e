// xxhash32, xxh3 64 and 128 and the one-at-a-time hash of digest2int against R's digest package.
// tests/oracle/hash.json comes from `Rscript scripts/r_oracle/generate.R hash`. A case is
// (len, salt, seed); the input bytes are rebuilt here the way scripts/r_oracle/groups/hash.R
// builds them.

use e.algo.hash.xxh as xxh
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn hex(a: *mem.Arena, v: u64, digits: usize) -> []u8 {
    let (buf, e) = mem.alloc[u8](a, digits)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < digits {
        let shift = u64((digits - 1usize - i) * 4usize)
        let nibble = u8((v >> shift) & 15u64)
        var c = 48u8 + nibble
        if nibble > 9u8 { c = 87u8 + nibble }
        buf[i] = c
        i += 1usize
    }
    ret buf
}

fn build_input(a: *mem.Arena, len: usize, salt: u64, printable: bool) -> []u8 {
    let (buf, e) = mem.alloc[u8](a, len + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < len {
        if printable {
            buf[i] = u8(32u64 + (u64(i) * 7u64 + salt) % 95u64)
        } else {
            buf[i] = u8((u64(i) * 31u64 + salt * 17u64 + 7u64) % 256u64)
        }
        i += 1usize
    }
    ret buf[0usize..len]
}

fn text_of(a: *mem.Arena, c: *const oracle.Case) -> str {
    let x = c.args
    let data = build_input(a, usize(x[0]), u64(x[1]), false)
    let seed = u64(x[2])
    if str.eq(c.name, "xxhash32") { ret hex(a, u64(xxh.xxhash32(data, u32(seed))), 8usize) }
    if str.eq(c.name, "xxh3_64") { ret hex(a, xxh.xxh3_64(data, seed), 16usize) }
    if str.eq(c.name, "xxh3_128") {
        let h = xxh.xxh3_128(data, seed)
        let high = hex(a, h.high, 16usize)
        let low = hex(a, h.low, 16usize)
        let (joined, e) = mem.alloc[u8](a, 32usize)
        if e != ok { os.exit(5) }
        mem.copy(joined[0usize..16usize], high)
        mem.copy(joined[16usize..32usize], low)
        ret joined
    }
    os.exit(4)
    ret ""
}

fn number_of(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if !str.eq(c.name, "digest2int") { os.exit(4) }
    let data = build_input(a, usize(x[0]), u64(x[1]), true)
    let h = xxh.jenkins_one_at_a_time(data, u32(u64(x[2])))
    if h >= 2147483648u32 { ret f64(h) - 4294967296.0f64 }
    ret f64(h)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hash.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var good = false
        if c.text.len > 0usize {
            let text = text_of(a, c)
            good = oracle.agrees_text(text, c)
            if !good && failures < 30usize {
                let _ = io.print(c.name)
                let _ = io.print(": got ")
                let _ = io.print(text)
                let _ = io.print(", R says ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        } else {
            good = oracle.agrees(number_of(a, c), c)
            if !good && failures < 30usize {
                let _ = io.print(oracle.describe(a, c, number_of(a, c)))
                let _ = io.print("\n")
            }
        }
        if !good { failures += 1usize }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
