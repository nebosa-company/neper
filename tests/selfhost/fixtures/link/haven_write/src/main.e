// The writers of e.fmt.dta, e.fmt.sav and e.fmt.xport against haven: each file in tests/data/haven that haven
// wrote is read with the reader and written again, and the bytes must equal haven's own (the Stata timestamp is
// taken from the reference file). Equal bytes mean haven's reader sees what haven's writer wrote.

use e.fmt.dta as dta
use e.fmt.sav as sav
use e.fmt.xport as xport
use e.fs
use e.mem
use e.os

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn stamp_of(b: []const u8) -> str {
    var s: str = zero
    var n = 0usize
    var at = 10usize + 81usize
    if b[0usize] == 60u8 {
        var i = 0usize
        while i + 11usize < b.len && !(b[i] == 60u8 && b[i + 1usize] == 116u8 && b[i + 2usize] == 105u8 && b[i + 3usize] == 109u8 && b[i + 4usize] == 101u8) { i += 1usize }
        n = usize(b[i + 11usize])
        at = i + 12usize
    } else {
        while n < 18usize && b[at + n] != 0u8 { n += 1usize }
    }
    s = b[at..at + n]
    ret s
}

fn check_dta(a: *mem.Arena, path: str, code: i32) {
    let (bytes, re) = fs.read_file(a, path, 4194304usize)
    if re != ok { os.exit(4) }
    let (d, e) = dta.read(a, bytes)
    if e != ok { os.exit(5) }
    let (out, we) = dta.write(a, &d, d.version, stamp_of(bytes))
    if we != ok { os.exit(6) }
    if !same(out, bytes) {
        let _ = fs.write_file(a, "build/haven_write_actual.dta", out)
        os.exit(code)
    }
}

fn check_xpt(a: *mem.Arena, path: str, code: i32) {
    let (bytes, re) = fs.read_file(a, path, 4194304usize)
    if re != ok { os.exit(4) }
    let (x, e) = xport.read(a, bytes)
    if e != ok { os.exit(5) }
    let (out, we) = xport.write(a, &x)
    if we != ok { os.exit(6) }
    if !same(out, bytes) {
        let _ = fs.write_file(a, "build/haven_write_actual.xpt", out)
        os.exit(code)
    }
}

fn check_sav(a: *mem.Arena, path: str, code: i32) {
    let (bytes, re) = fs.read_file(a, path, 4194304usize)
    if re != ok { os.exit(4) }
    let (d, e) = sav.read(a, bytes)
    if e != ok { os.exit(5) }
    let (out, we) = sav.write(a, &d, bytes[92usize..109usize])
    if we != ok { os.exit(6) }
    if !same(out, bytes) {
        let _ = fs.write_file(a, "build/haven_write_actual.sav", out)
        os.exit(code)
    }
}

// SPSS weight variable: s1w.sav is s1.sav with the header weight index set to 1 (haven's reader exposes no weight, so
// the value is checked against the file itself: read gives variable 0, write puts the index back).
fn check_weight(a: *mem.Arena) {
    let (plain, re) = fs.read_file(a, "tests/data/haven/s1.sav", 4194304usize)
    let (bytes, re2) = fs.read_file(a, "tests/data/haven/s1w.sav", 4194304usize)
    if re != ok || re2 != ok { os.exit(4) }
    let (p, e0) = sav.read(a, plain)
    let (d, e) = sav.read(a, bytes)
    if e0 != ok || e != ok { os.exit(5) }
    if p.weight != -1i64 || d.weight != 0i64 { os.exit(41) }
    let (out, we) = sav.write(a, &d, bytes[92usize..109usize])
    if we != ok { os.exit(6) }
    if !same(out, bytes) { os.exit(42) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    check_sav(a, "tests/data/haven/s1.sav", 31i32)
    check_sav(a, "tests/data/haven/s2.sav", 32i32)
    check_sav(a, "tests/data/haven/s3.zsav", 33i32)
    check_weight(a)
    check_xpt(a, "tests/data/haven/x5.xpt", 21i32)
    check_xpt(a, "tests/data/haven/x8.xpt", 22i32)
    check_dta(a, "tests/data/haven/w8.dta", 11i32)
    check_dta(a, "tests/data/haven/w10.dta", 12i32)
    check_dta(a, "tests/data/haven/w12.dta", 13i32)
    check_dta(a, "tests/data/haven/w13.dta", 14i32)
    check_dta(a, "tests/data/haven/w14.dta", 15i32)
    check_dta(a, "tests/data/haven/w15.dta", 16i32)
    check_dta(a, "tests/data/haven/t13.dta", 17i32)
    check_dta(a, "tests/data/haven/t14.dta", 18i32)
    check_dta(a, "tests/data/haven/t15.dta", 19i32)
    ret ok
}
