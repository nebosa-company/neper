// `e.math.float`: the fields of 1.0, -2.5 and a subnormal unpack and pack
// back, binary16 conversion matches NumPy on normals, the overflow edge, ties
// to even, subnormals and the rounding threshold under them, bfloat16
// rounds the top half to even and keeps NaN a NaN. Each check exits with
// its own code.

use e.io
use e.math.float
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: fields of f64 and f32.
    let one = float.unpack64(1.0f64)
    if one.negative || one.exponent != 1023u32 || one.mantissa != 0u64 { os.exit(1i32) }
    let minus = float.unpack64(0.0f64 - 2.5f64)
    if !minus.negative || minus.exponent != 1024u32 || minus.mantissa != 1125899906842624u64 { os.exit(1i32) }
    if float.pack64(minus) != 0.0f64 - 2.5f64 || float.pack64(one) != 1.0f64 { os.exit(1i32) }
    let tiny = float.unpack64(float.pack64(float.Fields { negative: false, exponent: 0u32, mantissa: 1u64 }))
    if tiny.exponent != 0u32 || tiny.mantissa != 1u64 || float.exponent_of(float.pack64(tiny)) != 0i32 - 1022i32 { os.exit(1i32) }
    if float.exponent_of(1024.0f64) != 10i32 || float.exponent_of(0.75f64) != 0i32 - 1i32 { os.exit(1i32) }
    let single = float.unpack32(0.0f32 - 2.5f32)
    if !single.negative || single.exponent != 128u32 || single.mantissa != 2097152u64 { os.exit(1i32) }
    if float.pack32(single) != 0.0f32 - 2.5f32 { os.exit(1i32) }

    // 2: binary16 against NumPy.
    if float.to_f16(1.0f32) != 15360u16 || float.to_f16(0.0f32 - 2.5f32) != 49408u16 || float.to_f16(0.1f32) != 11878u16 { os.exit(2i32) }
    if float.to_f16(65504.0f32) != 31743u16 || float.to_f16(65520.0f32) != 31744u16 || float.to_f16(0.00001f32) != 168u16 { os.exit(2i32) }
    // Ties to even: 1 + 2^-11 rounds down to 1, 1 + 3 * 2^-11 rounds up to 1 + 2^-9.
    if float.to_f16(1.00048828125f32) != 15360u16 || float.to_f16(1.00146484375f32) != 15362u16 || float.to_f16(1.0009765625f32) != 15361u16 { os.exit(2i32) }
    // Subnormals: 2^-24 is the smallest, half of it rounds to zero (tie to even), a hair more rounds up.
    if float.to_f16(0.00000005960464477539063f32) != 1u16 || float.to_f16(0.000000029802322387695312f32) != 0u16 || float.to_f16(0.00000003f32) != 1u16 { os.exit(2i32) }
    if float.to_f16(0.00006103515625f32) != 1024u16 || float.to_f16(0.000030517578125f32) != 512u16 { os.exit(2i32) }
    if float.to_f16(0.0f32) != 0u16 || float.to_f16(mem.bitcast[f32](2147483648u32)) != 32768u16 { os.exit(2i32) }
    let inf = mem.bitcast[f32](2139095040u32)
    let nan = mem.bitcast[f32](2143289345u32)
    if float.to_f16(inf) != 31744u16 || float.to_f16(0.0f32 - inf) != 64512u16 || (float.to_f16(nan) & 31744u16) != 31744u16 || (float.to_f16(nan) & 1023u16) == 0u16 { os.exit(2i32) }

    // 3: binary16 back to f32, including subnormals and the specials.
    if float.from_f16(15360u16) != 1.0f32 || float.from_f16(49408u16) != 0.0f32 - 2.5f32 || float.from_f16(31743u16) != 65504.0f32 { os.exit(3i32) }
    if float.from_f16(1u16) != 0.00000005960464477539063f32 || float.from_f16(512u16) != 0.000030517578125f32 || float.from_f16(1024u16) != 0.00006103515625f32 { os.exit(3i32) }
    if float.from_f16(31744u16) != inf || float.from_f16(64512u16) != 0.0f32 - inf { os.exit(3i32) }
    let back = float.from_f16(32256u16)
    if back == back { os.exit(3i32) }
    if mem.bitcast[u32](float.from_f16(32768u16)) != 2147483648u32 { os.exit(3i32) }
    var h = 0u32
    while h < 65536u32 {
        // Every finite half round-trips exactly.
        if (h & 31744u32) != 31744u32 && float.to_f16(float.from_f16(u16(h))) != u16(h) { os.exit(3i32) }
        h += 1u32
    }

    // 4: bfloat16.
    if float.to_bf16(1.0f32) != 16256u16 || float.to_bf16(3.140625f32) != 16457u16 || float.to_bf16(3.1415927f32) != 16457u16 { os.exit(4i32) }
    if float.to_bf16(1.00390625f32) != 16256u16 || float.to_bf16(1.01171875f32) != 16258u16 { os.exit(4i32) }
    if float.to_bf16(mem.bitcast[f32](71362u32)) != 1u16 || float.to_bf16(mem.bitcast[f32](2139029504u32)) != 32639u16 { os.exit(4i32) }
    if float.to_bf16(inf) != 32640u16 { os.exit(4i32) }
    let bnan = float.from_bf16(float.to_bf16(nan))
    if bnan == bnan { os.exit(4i32) }
    if float.from_bf16(16457u16) != 3.140625f32 || float.from_bf16(16256u16) != 1.0f32 { os.exit(4i32) }

    try io.print("math float ok\n")
    ret ok
}
