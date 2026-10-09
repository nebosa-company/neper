// `e.crypto.ristretto` against an independent RFC 9496 reference (scripts/ristretto_reference.py): the
// multiples of the generator by scalar multiplication and by repeated addition, decoding verdicts (the
// RFC's bad encodings, random strings and valid encodings, each valid one re-encoding to itself), the
// Elligator map of 32-byte strings, the derivation of 64-byte strings, scalar times point (the scalar
// reduced mod l), and addition and subtraction. The vectors are lines of hex in strings; a failing line
// exits with its kind (the exit code is 20 plus the kind) after the chunk's own code is ruled out.
use e.os
use e.mem
use e.io
use e.crypto.ristretto as rs

fn hexv(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

// Read the hex token starting at `at` into `out` (as many bytes as it fills) and return the position after it.
fn token(line: str, at: usize, out: []u8) -> usize {
    var p = at
    var n = 0usize
    while p + 1usize < line.len && line[p] != 32u8 && n < out.len {
        out[n] = hexv(line[p]) * 16u8 + hexv(line[p + 1usize])
        n += 1usize
        p += 2usize
    }
    while p < line.len && line[p] == 32u8 { p += 1usize }
    ret p
}

fn same(left: []const u8, right: []const u8) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn decimal(line: str, at: usize) -> (usize, usize) {
    var p = at
    var v = 0usize
    while p < line.len && line[p] != 32u8 {
        v = v * 10usize + usize(line[p] - 48u8)
        p += 1usize
    }
    while p < line.len && line[p] == 32u8 { p += 1usize }
    ret (v, p)
}

// One line; 0 when it holds, the kind's code otherwise.
fn check(line: str, ladder: []const u8) -> u8 {
    let kind = line[0usize]
    var a: [32]u8 = zero
    var b: [32]u8 = zero
    var c: [32]u8 = zero
    var d: [32]u8 = zero
    var wide: [64]u8 = zero
    if kind == 66u8 {
        // B k enc: the k-th multiple, by scalar multiplication and as the ladder of additions.
        let (k, after) = decimal(line, 2usize)
        let skip = token(line, after, a[0..])
        var scalar: [32]u8 = zero
        scalar[0] = u8(k)
        let by_mul = rs.encode(rs.mul(scalar, rs.base()))
        if !same(by_mul[0..], a[0..]) { ret 1u8 }
        if !same(ladder[k * 32usize..k * 32usize + 32usize], a[0..]) { ret 2u8 }
        ret 0u8
    }
    if kind == 86u8 {
        // V enc verdict
        let after = token(line, 2usize, a[0..])
        let (point, e) = rs.decode(a)
        if line[after] == 48u8 {
            if e == ok { ret 3u8 }
            ret 0u8
        }
        if e != ok { ret 4u8 }
        let again = rs.encode(point)
        if !same(again[0..], a[0..]) { ret 5u8 }
        ret 0u8
    }
    if kind == 77u8 {
        // M input expected
        let after = token(line, 2usize, a[0..])
        let skip = token(line, after, b[0..])
        let got = rs.encode(rs.map(a))
        if !same(got[0..], b[0..]) { ret 6u8 }
        ret 0u8
    }
    if kind == 68u8 {
        // D input64 expected
        let after = token(line, 2usize, wide[0..])
        let skip = token(line, after, b[0..])
        let (point, e) = rs.derive(wide[0..])
        if e != ok { ret 7u8 }
        let got = rs.encode(point)
        if !same(got[0..], b[0..]) { ret 8u8 }
        ret 0u8
    }
    if kind == 83u8 {
        // S scalar point expected
        var after = token(line, 2usize, a[0..])
        after = token(line, after, b[0..])
        let skip = token(line, after, c[0..])
        let (point, e) = rs.decode(b)
        if e != ok { ret 9u8 }
        let got = rs.encode(rs.mul(a, point))
        if !same(got[0..], c[0..]) { ret 10u8 }
        ret 0u8
    }
    if kind == 65u8 {
        // A p q sum difference
        var after = token(line, 2usize, a[0..])
        after = token(line, after, b[0..])
        after = token(line, after, c[0..])
        let skip = token(line, after, d[0..])
        let (p, pe) = rs.decode(a)
        let (q, qe) = rs.decode(b)
        if pe != ok || qe != ok { ret 11u8 }
        let sum = rs.encode(rs.add(p, q))
        if !same(sum[0..], c[0..]) { ret 12u8 }
        let difference = rs.encode(rs.sub(p, q))
        if !same(difference[0..], d[0..]) { ret 13u8 }
        if !rs.equals(rs.add(p, rs.neg(p)), rs.identity()) { ret 14u8 }
        ret 0u8
    }
    ret 15u8
}

// Run a block of lines; 0 when all hold.
fn run(text: str, ladder: []const u8) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let verdict = check(text[start..i], ladder)
            if verdict != 0u8 { ret 20u8 + verdict }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    // The ladder of additions: 0B, 1B, ... 15B.
    var ladder: [512]u8 = zero
    var acc = rs.identity()
    var k = 0usize
    while k < 16usize {
        let step = rs.encode(acc)
        var j = 0usize
        while j < 32usize {
            ladder[k * 32usize + j] = step[j]
            j += 1usize
        }
        acc = rs.add(acc, rs.base())
        k += 1usize
    }
    // The group order: l * B is the identity (the scalar l reduces to zero), and the identity encodes as 32 zeros.
    let order: [32]u8 = [32]u8{ 237, 211, 245, 92, 26, 99, 18, 88, 214, 156, 247, 162, 222, 249, 222, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 }
    if !rs.equals(rs.mul(order, rs.base()), rs.identity()) { os.exit(1) }
    let zeros = rs.encode(rs.identity())
    var i = 0usize
    while i < 32usize {
        if zeros[i] != 0u8 { os.exit(2) }
        i += 1usize
    }
    // A wrong length is refused by the derivation.
    let short: [8]u8 = zero
    let (unused, short_error) = rs.derive(short[0..])
    if short_error != rs.Invalid { os.exit(3) }
    //__VECTOR_CALLS__
    try io.print("crypto ristretto ok")
    ret ok
}
