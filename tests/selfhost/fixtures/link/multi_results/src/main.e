// Multi-result returns (#191 item 6): functions returning 2, 5, 16 and 20 values
// must hand every result back exactly. Each sum check exits with its own code so a
// lost or misread slot names which arity broke.
use e.mem
use e.os

fn two() -> (u8, u8) {
    ret (1u8, 2u8)
}

fn five() -> (u8, u8, u8, u8, u8) {
    ret (1u8, 2u8, 3u8, 4u8, 5u8)
}

fn sixteen() -> (u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8) {
    ret (1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8, 16u8)
}

fn twenty() -> (u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8, u8) {
    ret (1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8, 16u8, 17u8, 18u8, 19u8, 20u8)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (t0, t1) = two()
    if i32(t0) + i32(t1) != 3i32 { os.exit(2i32) }
    let (f0, f1, f2, f3, f4) = five()
    if i32(f0) + i32(f1) + i32(f2) + i32(f3) + i32(f4) != 15i32 { os.exit(5i32) }
    let (s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15) = sixteen()
    if i32(s0) + i32(s1) + i32(s2) + i32(s3) + i32(s4) + i32(s5) + i32(s6) + i32(s7) + i32(s8) + i32(s9) + i32(s10) + i32(s11) + i32(s12) + i32(s13) + i32(s14) + i32(s15) != 136i32 { os.exit(16i32) }
    let (w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, w16, w17, w18, w19) = twenty()
    if i32(w0) + i32(w1) + i32(w2) + i32(w3) + i32(w4) + i32(w5) + i32(w6) + i32(w7) + i32(w8) + i32(w9) + i32(w10) + i32(w11) + i32(w12) + i32(w13) + i32(w14) + i32(w15) + i32(w16) + i32(w17) + i32(w18) + i32(w19) != 210i32 { os.exit(20i32) }
    ret ok
}
