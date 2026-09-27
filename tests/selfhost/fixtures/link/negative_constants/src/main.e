// A negative named constant narrower than 64 bits equals the same value computed at run time.
// A computed `i8`/`i16`/`i32` sits sign-extended in its register; the constant's immediate was
// its width's bit pattern, so `x == NEG32` compared 0x00000000FFFFFFFB with
// 0xFFFFFFFFFFFFFFFB and was false. Found as ODBC's negative type codes (`SQL_BIGINT` is -5)
// never matching what `SQLDescribeColW` wrote.
use e.os
use e.mem

const NEG8: i8 = -5i8
const NEG16: i16 = -5i16
const NEG32: i32 = -5i32
const NEG64: i64 = -5i64
const MIN32: i32 = -2147483648i32
const POS16: i16 = 7i16

// Opaque to the lowering: the value arrives as a parameter.
fn minus(n: i32) -> i32 { ret 0i32 - n }
fn is_neg16(x: i16) -> bool { ret x == NEG16 }

// Written through a pointer, as foreign code writes an out parameter.
fn poke16(p: *i16) {
    var region: mem.Arena = zero
    region.base = mem.cast[*u8](p)
    region.cap = 2usize
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, 2usize)
    bytes[0usize] = 251u8
    bytes[1usize] = 255u8
}

fn main(a: *mem.Arena) -> err {
    let five = minus(-5i32)
    let z = minus(five)
    if z != NEG32 { os.exit(10i32) }
    if !(NEG32 < 0i32) { os.exit(11i32) }
    if i16(z) != NEG16 { os.exit(12i32) }
    if i8(z) != NEG8 { os.exit(13i32) }
    if i64(z) != NEG64 { os.exit(14i32) }
    if i64(NEG32) != -5i64 { os.exit(15i32) }
    if minus(2147483647i32) - 1i32 != MIN32 { os.exit(16i32) }
    var written = 0i16
    poke16(&written)
    if !is_neg16(written) { os.exit(17i32) }
    if POS16 != 7i16 { os.exit(18i32) }
    let (w, write_error) = os.write(os.stdout(), "negative constants ok\n")
    ret ok
}
