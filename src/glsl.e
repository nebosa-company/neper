// The GLSL emitter (C215, D5941, D5888): the program's kernels, lowered for the device as the SPIR-V and MSL emitters take
// them (`builder.spirv`), written as GLSL 4.30 compute shaders for an OpenGL 4.3 device -- one shader a kernel, each after a
// `//entry:module_name` line, because a GLSL shader has one `main`.
//
// The control flow is the MSL emitter's: every NIR block is a `case` of a `switch` on `pc` inside `while (true)`. The memory
// is not: GLSL has no pointers and no byte access, so every place a value lives is an array of `uint` words addressed in
// bytes. A device address is a byte offset into the device's heap (`heap`, one SSBO the launcher carves every buffer from), a
// private address one into the invocation's `fr` words, a workgroup address one into the `tg` words. A four-byte value is a
// word; a one- or two-byte value is a `bitfieldExtract` of its word, and storing one into `heap` or `tg`, where neighbouring
// invocations store the neighbouring bytes, is an `atomicAnd` that clears it and an `atomicOr` that sets it (D5882).
//
// A value is a typed variable `vN`: `uint` for every unsigned width and for an address, `int` for every signed width, `bool`,
// and `precise float`, so a multiply and an add are never fused. A narrow result is brought back into its width after each
// operation. 64-bit values, `f64`, subgroups, an atomic order stronger than relaxed, and the float division and square root
// that have to be exact (C217) are `Unsupported`, so the CPU runs that kernel.
//
// The launch ABI is SPIR-V's and Metal's: binding 0 is the argument block (an 8-byte fault buffer offset first in a checked
// build, then the parameters at their natural alignment, a slice as `{ u64 offset, u32 len }` in sixteen bytes), binding 1
// the heap. `usize` is 32 bits, as on `spv`.
use e.mem
use check
use graph
use layout
use nir

type Text = struct { data: []u8, count: usize, full: bool }

const KIND_NONE: u8 = 0u8
const KIND_SCALAR: u8 = 1u8
const KIND_PRIVATE: u8 = 2u8
const KIND_BUILTIN: u8 = 3u8
const KIND_SHARED: u8 = 4u8
// (D5902) `gpu.sid` (offset 1) or `gpu.subgroup_width` (offset 2), read from GLSL's subgroup built-ins.
const KIND_INPUT: u8 = 5u8

// How a scalar is held: 1 bool, 2 u8, 3 i8, 4 u16, 5 i16, 6 u32, 7 i32, 8 u64, 9 i64 (GL_ARB_gpu_shader_int64), 10 f32,
// 12 a heap address.
const T_BOOL: u8 = 1u8
const T_F32: u8 = 10u8
// (L181, D5903) f64: a GLSL `double`, core since 4.00; its words cross memory through packDouble2x32, so no int64 is needed.
const T_F64: u8 = 11u8
// (C216, D5914) f16 and bf16: the sixteen bits in a `uint`, widened to f32, operated on, and rounded back once to nearest-even in
// integer code (so no driver conversion or rounding mode is in the answer), as the CPU code generators do (D5913).
const T_F16: u8 = 13u8
const T_BF16: u8 = 14u8
const T_ADDRESS: u8 = 12u8

type Values = struct {
    kind: []u8,
    ty: []u8,
    // A builtin's number (1 gid, 2 lid, 3 wgid) plus four times its component, or a private value's byte offset.
    offset: []usize,
    // The number of the `uint` variable holding a private or shared address's dynamic byte offset; 0 for none.
    dynamic: []usize,
}

type Module = struct {
    body: Text,
    code: Text,
    checked: bool,
    dynamics: usize,
    frame_bytes: usize,
    shared_words: usize,
    failure: str,
    // (C217) The kernel divides or takes square roots of f32, which GLSL does not round correctly: the integer sequences
    // below are written into its shader.
    needs_divide: bool,
    needs_sqrt: bool,
    // (C215) The helpers the kernels reach, as GLSL functions every kernel's shader carries, and their prototypes; whether
    // any of them needs the exact sequences; and, while one is written, its signature.
    helpers: Text,
    prototypes: Text,
    helper_exact: bool,
    helper_wide: bool,
    // (D5902) The function being written reads a subgroup input or runs a collective; any helper that did.
    needs_subgroup: bool,
    helper_subgroup: bool,
    // (D5906) A kernel with barriers runs in workgroup rounds: only the invocations at the workgroup's lowest `pc` run a
    // round, so every barrier is reached by the whole workgroup in one round. Its `pc` is a block's number times 64 plus
    // the barriers passed in that block; an invocation that is done waits at DONE until all are.
    wg_round: bool,
    block_at: usize,
    split_at: usize,
    // A helper reads or writes workgroup memory, so every kernel's shader, which carries every helper, declares `tg`.
    helper_shared: bool,
    // The type the helper being written returns, `void` for none: what a fault in it returns.
    helper_returns: str,
    // (D5906) The function being written, or any helper, calls `math.fma[f64]`: `f64_fma` goes into the shader.
    needs_dfma: bool,
    helper_dfma: bool,
    needs_narrow: bool,
    helper_narrow: bool,
    needs_narrow64: bool,
    helper_narrow64: bool,
    signatures: *nir.Signatures,
    in_helper: bool,
    signature: nir.Signature,
}

// (C216, D5914) f16 and bf16 as `uint` bits: widening is exact, narrowing is one round-to-nearest-even in integer code,
// a NaN is the width's canonical one, and int_to_* takes a magnitude and a sign (an integer of 32 bits or fewer is exact in
// f64, so converting it through f64 is the one rounding of its value).
fn narrow_source() -> str {
    ret "uint h_bits_to_f32(uint h) {\n  uint s = (h & 0x8000u) << 16u; uint e = (h >> 10u) & 31u; uint m = h & 1023u;\n  if (e == 0u) { if (m == 0u) return s; int k = findMSB(m); return s | (uint(k + 103) << 23u) | ((m << uint(23 - k)) & 0x7FFFFFu); }\n  if (e == 31u) { if (m != 0u) return 0x7FC00000u; return s | 0x7F800000u; }\n  return s | ((e + 112u) << 23u) | (m << 13u);\n}\nuint bf_bits_to_f32(uint b) {\n  if (((b >> 7u) & 255u) == 255u && (b & 127u) != 0u) return 0x7FC00000u;\n  return b << 16u;\n}\nuint f32_bits_to_h(uint x) {\n  uint s = (x >> 16u) & 0x8000u; uint e = (x >> 23u) & 255u; uint m = x & 0x7FFFFFu;\n  if (e == 255u) return m != 0u ? 0x7E00u : (s | 0x7C00u);\n  int ex = int(e) - 112;\n  if (ex >= 31) return s | 0x7C00u;\n  if (ex <= 0) {\n    if (ex < -10) return s;\n    m |= 0x800000u;\n    uint sh = uint(14 - ex);\n    uint mant = m >> sh; uint rem = m & ((1u << sh) - 1u); uint hl = 1u << (sh - 1u);\n    if (rem > hl || (rem == hl && (mant & 1u) != 0u)) mant += 1u;\n    return s | mant;\n  }\n  uint mant = (uint(ex) << 10u) | (m >> 13u); uint rem = m & 0x1FFFu;\n  if (rem > 0x1000u || (rem == 0x1000u && (mant & 1u) != 0u)) mant += 1u;\n  return s | mant;\n}\nuint f32_bits_to_bf(uint x) {\n  if (((x >> 23u) & 255u) == 255u && (x & 0x7FFFFFu) != 0u) return 0x7FC0u;\n  return (x + 0x7FFFu + ((x >> 16u) & 1u)) >> 16u;\n}\nuint int_to_h(uint mag, uint sign) {\n  if (mag == 0u) return 0u;\n  int k = findMSB(mag);\n  if (k > 15) return sign | 0x7C00u;\n  uint mant = mag << uint(10 - min(k, 10));\n  if (k > 10) { uint sh = uint(k - 10); mant = mag >> sh; uint rem = mag & ((1u << sh) - 1u); uint hl = 1u << (sh - 1u); if (rem > hl || (rem == hl && (mant & 1u) != 0u)) mant += 1u; }\n  uint r = (uint(k + 14) << 10u) + mant;\n  if (r >= 0x7C00u) r = 0x7C00u;\n  return sign | r;\n}\nuint int_to_bf(uint mag, uint sign) {\n  if (mag == 0u) return 0u;\n  int k = findMSB(mag);\n  uint mant = mag << uint(7 - min(k, 7));\n  if (k > 7) { uint sh = uint(k - 7); mant = mag >> sh; uint rem = mag & ((1u << sh) - 1u); uint hl = 1u << (sh - 1u); if (rem > hl || (rem == hl && (mant & 1u) != 0u)) mant += 1u; }\n  return sign | ((uint(k + 126) << 7u) + mant);\n}\n"
}

// f64 to narrow: one rounding of the 53-bit significand, shifted with its lost bits jammed into bit 0 (needs w_shr).
fn narrow64_source() -> str {
    ret "uint f64_bits_to_narrow(uvec2 b, int p, int emin, int emax) {\n  uint s = (b.y >> 16u) & 0x8000u; int e = int((b.y >> 20u) & 2047u);\n  uint infp = uint(emax - emin + 2) << uint(p); uint nan = infp | (1u << uint(p - 1));\n  uint mhi = b.y & 0xFFFFFu;\n  if (e == 2047) return (mhi | b.x) != 0u ? nan : (s | infp);\n  if (e == 0) return s;\n  int ex = e - 1023;\n  if (ex > emax) return s | infp;\n  uvec2 sig = uvec2(mhi | 0x100000u, b.x);\n  int sh = 52 - p; uint base = 0u;\n  if (ex >= emin) base = uint(ex - emin) << uint(p); else sh += emin - ex;\n  if (sh > 54) return s;\n  uvec2 q = w_shr(sig, sh - 2);\n  uint mant = q.y >> 2u; uint guard = (q.y >> 1u) & 1u; uint sticky = q.y & 1u;\n  uint r = base + mant + ((guard == 1u && (sticky == 1u || (mant & 1u) == 1u)) ? 1u : 0u);\n  if (r >= infp) r = infp;\n  return s | r;\n}\n"
}

// (D5906) `math.fma[f64]` rounded once, after Boldo and Melquiond: the product exact as two doubles (Dekker's split), the
// addend's sum with its low part exact, the low parts added rounding to odd, and one round to nearest at the end. Every
// step is a `precise` double operation GLSL leaves to the driver, as D5903 does for + - * /.
// ponytail: exact while no step overflows and the product's low part is not subnormal (|a| or |b| past 2^995, or a product
// near 2^-969); there it is the plain a * b + c. Integer sequences over 106-bit products are the upgrade.
fn dfma_source() -> str {
    ret "dvec2 f64_two_sum(double a, double b) {\n  precise double s = a + b; precise double bb = s - a; precise double e = (a - (s - bb)) + (b - bb);\n  return dvec2(s, e);\n}\ndvec2 f64_split(double a) {\n  precise double c = 134217729.0 * a; precise double h = c - (c - a); precise double l = a - h;\n  return dvec2(h, l);\n}\ndouble f64_add_odd(double x, double y) {\n  dvec2 s = f64_two_sum(x, y);\n  uvec2 w = unpackDouble2x32(s.x);\n  if (s.y == 0.0 || (w.x & 1u) != 0u) return s.x;\n  if ((s.y > 0.0) == (s.x > 0.0)) { w.x += 1u; if (w.x == 0u) w.y += 1u; } else { if (w.x == 0u) w.y -= 1u; w.x -= 1u; }\n  return packDouble2x32(w);\n}\ndouble f64_fma(double a, double b, double c) {\n  precise double p = a * b;\n  precise double plain = p + c;\n  if (isnan(plain) || isinf(plain) || isinf(p) || p == 0.0 || abs(a) > 1.0e297 || abs(b) > 1.0e297 || abs(p) < 1.0e-290) return plain;\n  dvec2 sa = f64_split(a); dvec2 sb = f64_split(b);\n  precise double pe = ((sa.x * sb.x - p) + sa.x * sb.y + sa.y * sb.x) + sa.y * sb.y;\n  dvec2 t = f64_two_sum(c, pe);\n  dvec2 v = f64_two_sum(p, t.x);\n  precise double r = v.x + f64_add_odd(v.y, t.y);\n  return r;\n}\n"
}

// f32 division and square root on the bits, correctly rounded to nearest-even as section 11 requires; every NaN result is
// the canonical positive quiet NaN, 0x7FC00000. With FTZ set (an `ftz` kernel), subnormal operands count as zero and a
// result tiny after rounding is a zero.
fn exact_source() -> str {
    ret "uint f32_round_x(uint s, int e, uint q, bool sticky, bool flush) {\n  // q: 26 bits, the leading one at bit 25; e: the biased exponent of that one.\n  if (e <= 0) {\n    if (flush) {\n      uint m = q >> 2u; bool up = ((q & 2u) != 0u) && (((q & 1u) != 0u) || sticky || ((m & 1u) != 0u)); m += up ? 1u : 0u;\n      if (e == 0 && m == 16777216u) return s | 0x00800000u;\n      return s;\n    }\n    int shift = 1 - e;\n    if (shift > 26) { sticky = sticky || q != 0u; q = 0u; } else { sticky = sticky || (q & ((1u << uint(shift)) - 1u)) != 0u; q >>= uint(shift); }\n    uint m = q >> 2u; bool up = ((q & 2u) != 0u) && (((q & 1u) != 0u) || sticky || ((m & 1u) != 0u)); m += up ? 1u : 0u;\n    return s | m;\n  }\n  uint m = q >> 2u; bool up = ((q & 2u) != 0u) && (((q & 1u) != 0u) || sticky || ((m & 1u) != 0u)); m += up ? 1u : 0u;\n  if (m == 16777216u) { m = 8388608u; e += 1; }\n  if (e >= 255) return s | 0x7F800000u;\n  return s | (uint(e) << 23u) | (m & 0x7FFFFFu);\n}\nuint f32_round(uint s, int e, uint q, bool sticky) { return f32_round_x(s, e, q, sticky, FTZ); }\nuint f32_div(uint a, uint b) {\n  uint s = (a ^ b) & 0x80000000u; uint ea = (a >> 23u) & 255u; uint eb = (b >> 23u) & 255u; uint ma = a & 0x7FFFFFu; uint mb = b & 0x7FFFFFu;\n  if (FTZ) { if (ea == 0u) ma = 0u; if (eb == 0u) mb = 0u; }\n  if (ea == 255u && ma != 0u) return 0x7FC00000u;\n  if (eb == 255u && mb != 0u) return 0x7FC00000u;\n  bool az = ea == 0u && ma == 0u; bool bz = eb == 0u && mb == 0u;\n  if ((ea == 255u && eb == 255u) || (az && bz)) return 0x7FC00000u;\n  if (ea == 255u || bz) return s | 0x7F800000u;\n  if (eb == 255u || az) return s;\n  int xa = int(ea); int xb = int(eb);\n  if (ea == 0u) { int k = 23 - findMSB(ma); ma <<= uint(k); xa = 1 - k; } else { ma |= 0x800000u; }\n  if (eb == 0u) { int k = 23 - findMSB(mb); mb <<= uint(k); xb = 1 - k; } else { mb |= 0x800000u; }\n  int e = xa - xb + 127;\n  if (ma < mb) { ma <<= 1u; e -= 1; }\n  uint q = 0u; uint r = ma;\n  for (int i = 0; i < 26; i++) { q <<= 1u; if (r >= mb) { r -= mb; q |= 1u; } r <<= 1u; }\n  return f32_round(s, e, q, r != 0u);\n}\nuint f32_sqrt(uint a) {\n  uint ea = (a >> 23u) & 255u; uint ma = a & 0x7FFFFFu;\n  if (FTZ && ea == 0u) ma = 0u;\n  if (ea == 255u && ma != 0u) return 0x7FC00000u;\n  if (ea == 0u && ma == 0u) return a & 0x80000000u;\n  if ((a & 0x80000000u) != 0u) return 0x7FC00000u;\n  if (ea == 255u) return a;\n  int e = int(ea) - 127;\n  if (ea == 0u) { int k = 23 - findMSB(ma); ma <<= uint(k); e = -126 - k; } else { ma |= 0x800000u; }\n  if ((e & 1) != 0) { ma <<= 1u; e -= 1; }\n  uint hi = ma >> 5u; uint lo = ma << 27u; uint r = 0u; uint root = 0u;\n  for (int i = 0; i < 26; i++) {\n    int p = 50 - 2 * i; uint two = p >= 32 ? (hi >> uint(p - 32)) & 3u : (lo >> uint(p)) & 3u;\n    r = (r << 2u) | two; uint trial = (root << 2u) | 1u; root <<= 1u;\n    if (r >= trial) { r -= trial; root |= 1u; }\n  }\n  return f32_round(0u, e / 2 + 127, root, r != 0u);\n}\nuvec2 w_shl(uvec2 v, int n) {\n  if (n == 0) return v;\n  if (n >= 32) return uvec2(v.y << uint(n - 32), 0u);\n  return uvec2((v.x << uint(n)) | (v.y >> uint(32 - n)), v.y << uint(n));\n}\nuvec2 w_shr(uvec2 v, int n) {\n  // Shifted right with every bit lost jammed into bit 0.\n  if (n == 0) return v;\n  if (n >= 64) return uvec2(0u, (v.x | v.y) != 0u ? 1u : 0u);\n  uvec2 r; bool lost;\n  if (n >= 32) { int k = n - 32; r = uvec2(0u, k == 0 ? v.x : v.x >> uint(k)); lost = v.y != 0u || (k != 0 && (v.x & ((1u << uint(k)) - 1u)) != 0u); }\n  else { r = uvec2(v.x >> uint(n), (v.y >> uint(n)) | (v.x << uint(32 - n))); lost = (v.y & ((1u << uint(n)) - 1u)) != 0u; }\n  if (lost) r.y |= 1u;\n  return r;\n}\nuint f32_fma(uint a, uint b, uint c) {\n  uint sp = (a ^ b) & 0x80000000u; uint sc = c & 0x80000000u;\n  uint ea = (a >> 23u) & 255u; uint eb = (b >> 23u) & 255u; uint ec = (c >> 23u) & 255u; uint ma = a & 0x7FFFFFu; uint mb = b & 0x7FFFFFu; uint mc = c & 0x7FFFFFu;\n  if ((ea == 255u && ma != 0u) || (eb == 255u && mb != 0u) || (ec == 255u && mc != 0u)) return 0x7FC00000u;\n  bool az = ea == 0u && ma == 0u; bool bz = eb == 0u && mb == 0u; bool cz = ec == 0u && mc == 0u;\n  if ((ea == 255u && bz) || (eb == 255u && az)) return 0x7FC00000u;\n  if (ea == 255u || eb == 255u) { if (ec == 255u && sc != sp) return 0x7FC00000u; return sp | 0x7F800000u; }\n  if (ec == 255u) return c;\n  if (az || bz) { if (cz) return sp & sc; return c; }\n  int xa = int(ea); int xb = int(eb);\n  if (ea == 0u) { int k = 23 - findMSB(ma); ma <<= uint(k); xa = 1 - k; } else { ma |= 0x800000u; }\n  if (eb == 0u) { int k = 23 - findMSB(mb); mb <<= uint(k); xb = 1 - k; } else { mb |= 0x800000u; }\n  // The product exactly, its top bit moved to bit 61; tb is that bit's unbiased exponent.\n  uvec2 big; umulExtended(ma, mb, big.x, big.y);\n  int top = 32 + findMSB(big.x);\n  int tb = xa + xb - 254 - 46 + top;\n  big = w_shl(big, 61 - top);\n  uint sb = sp;\n  if (!cz) {\n    int xc = int(ec);\n    if (ec == 0u) { int k = 23 - findMSB(mc); mc <<= uint(k); xc = 1 - k; } else { mc |= 0x800000u; }\n    uvec2 small = uvec2(mc << 6u, 0u); int ts = xc - 127; uint ss = sc;\n    if (ts > tb) { uvec2 w = big; big = small; small = w; int x = tb; tb = ts; ts = x; uint s = sb; sb = ss; ss = s; }\n    small = w_shr(small, tb - ts);\n    uint carry; uint borrow;\n    if (sb == ss) { big.y = uaddCarry(big.y, small.y, carry); big.x = big.x + small.x + carry; }\n    else {\n      if (big.x < small.x || (big.x == small.x && big.y < small.y)) { uvec2 w = big; big = small; small = w; sb = ss; }\n      big.y = usubBorrow(big.y, small.y, borrow); big.x = big.x - small.x - borrow;\n      if ((big.x | big.y) == 0u) return 0u;\n    }\n  }\n  int t = big.x != 0u ? 32 + findMSB(big.x) : findMSB(big.y);\n  uint q = t >= 25 ? w_shr(big, t - 25).y : big.y << uint(25 - t);\n  return f32_round_x(sb, tb - 61 + t + 127, q, false, false);\n}\n"
}

error Unsupported

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn fail(m: *Module, message: str) -> err {
    m.failure = message
    ret Unsupported
}

// ---- text --------------------------------------------------------------------

fn put(t: *Text, value: str) {
    var at = 0usize
    while at < value.len {
        if t.count >= t.data.len {
            t.full = true
            ret
        }
        t.data[t.count] = value[at]
        t.count += 1usize
        at += 1usize
    }
}

fn put_number(t: *Text, value: usize) {
    if value >= 10usize { put_number(t, value / 10usize) }
    var digit: [1]u8 = zero
    digit[0usize] = u8(48usize + value % 10usize)
    put(t, digit[0usize..1usize])
}

fn put_hex(t: *Text, value: usize) {
    put(t, "0x")
    let digits = "0123456789abcdef"
    var shift = 28usize
    while true {
        let nibble = (value >> shift) & 15usize
        var one: [1]u8 = zero
        one[0usize] = digits[nibble]
        put(t, one[0usize..1usize])
        if shift == 0usize { break }
        shift = shift - 4usize
    }
}

// `0x`, sixteen hex digits and `ul`, for a 64-bit constant.
fn put_hex64(t: *Text, value: usize) {
    put_hex(t, value >> 32usize)
    let digits = "0123456789abcdef"
    var shift = 28usize
    while true {
        var one: [1]u8 = zero
        one[0usize] = digits[(value >> shift) & 15usize]
        put(t, one[0usize..1usize])
        if shift == 0usize { break }
        shift = shift - 4usize
    }
    put(t, "ul")
}

fn line(t: *Text, value: str) {
    put(t, "      ")
    put(t, value)
    put(t, "\n")
}

fn text_has(t: *Text, part: str) -> bool {
    var at = 0usize
    while at + part.len <= t.count {
        var k = 0usize
        while k < part.len && t.data[at + k] == part[k] { k += 1usize }
        if k == part.len { ret true }
        at += 1usize
    }
    ret false
}

fn put_value(t: *Text, value: usize) {
    put(t, "v")
    put_number(t, value)
}

fn assign(t: *Text, value: usize) {
    put(t, "      v")
    put_number(t, value)
    put(t, " = ")
}

// ---- types ---------------------------------------------------------------------

fn type_name(code: u8) -> str {
    if (code == T_BOOL) { ret "bool" }
    if code == 3u8 || code == 5u8 || code == 7u8 { ret "int" }
    if (code == T_F32) { ret "float" }
    if (code == T_F64) { ret "double" }
    if code == 8u8 { ret "uint64_t" }
    if code == 9u8 { ret "int64_t" }
    ret "uint"
}

fn type_bytes(code: u8) -> usize {
    if code == 1u8 || code == 2u8 || code == 3u8 { ret 1usize }
    if code == 4u8 || code == 5u8 || narrow_code(code) { ret 2usize }
    if code == 8u8 || code == 9u8 || (code == T_F64) { ret 8usize }
    ret 4usize
}

fn is_signed(code: u8) -> bool {
    ret code == 3u8 || code == 5u8 || code == 7u8 || code == 9u8
}

fn is_wide(code: u8) -> bool { ret code == 8u8 || code == 9u8 }

fn is_float(code: u8) -> bool { ret code == T_F32 || code == T_F64 }

fn narrow_code(code: u8) -> bool { ret code == T_F16 || code == T_BF16 }

// The helper that widens a narrow value's bits to f32 bits, and the one that rounds f32 bits back.
fn narrow_widen(code: u8) -> str {
    if (code == T_F16) { ret "h_bits_to_f32" }
    ret "bf_bits_to_f32"
}

fn narrow_round(code: u8) -> str {
    if (code == T_F16) { ret "f32_bits_to_h" }
    ret "f32_bits_to_bf"
}

// The unsigned type a magnitude of `code` is held in.
fn unsigned_name(code: u8) -> str {
    if is_wide(code) { ret "uint64_t" }
    ret "uint"
}

// The zero no compiler can prove (D5888), in the width of `code`.
fn unknown_zero(code: u8) -> str {
    if is_wide(code) { ret "(gl_NumWorkGroups.z == 0u ? 1ul : 0ul)" }
    ret "uint(gl_NumWorkGroups.z == 0u)"
}

// The scalar code a NIR type is held in; 0 when this emitter cannot hold it.
fn value_type(ty: check.Type) -> u8 {
    if ty.kind == .Bool { ret 1u8 }
    if ty.kind == .Err { ret 6u8 }
    if ty.kind == .Named && (same(ty.name, "Ordering") || same(ty.name, "Scope")) { ret 6u8 }
    if ty.kind == .Pointer {
        if ty.in_shared { ret 6u8 }
        ret 12u8
    }
    if ty.kind == .Float {
        if same(ty.name, "f32") { ret 10u8 }
        if same(ty.name, "f64") { ret 11u8 }
        if same(ty.name, "f16") { ret 13u8 }
        if same(ty.name, "bf16") { ret 14u8 }
        ret 0u8
    }
    if ty.kind == .Integer {
        if same(ty.name, "u8") { ret 2u8 }
        if same(ty.name, "i8") { ret 3u8 }
        if same(ty.name, "u16") { ret 4u8 }
        if same(ty.name, "i16") { ret 5u8 }
        if same(ty.name, "u32") || same(ty.name, "usize") { ret 6u8 }
        if same(ty.name, "i32") || same(ty.name, "isize") { ret 7u8 }
        if same(ty.name, "u64") { ret 8u8 }
        if same(ty.name, "i64") { ret 9u8 }
    }
    ret 0u8
}

fn aggregate(ty: check.Type) -> bool {
    ret ty.kind == .Slice || ty.kind == .Named || ty.kind == .Array || ty.kind == .String
}

fn aggregate_bytes(c: *check.Checker, ty: check.Type) -> (usize, err) {
    if ty.kind == .Slice || ty.kind == .String { ret (16usize, ok) }
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret (0usize, info_error) }
    ret ((info.size + 3usize) / 4usize * 4usize, ok)
}

// An expression of type `ty` brought back into its width: a narrow unsigned value masked, a narrow signed one sign-extended.
fn put_narrowed(t: *Text, ty: u8, expression: *Text) {
    if ty == 2u8 || ty == 4u8 {
        put(t, "((")
        put(t, expression.data[0usize..expression.count])
        if ty == 2u8 { put(t, ") & 255u)") } else { put(t, ") & 65535u)") }
        ret
    }
    if ty == 3u8 || ty == 5u8 {
        put(t, "bitfieldExtract(int(")
        put(t, expression.data[0usize..expression.count])
        if ty == 3u8 { put(t, "), 0, 8)") } else { put(t, "), 0, 16)") }
        ret
    }
    put(t, expression.data[0usize..expression.count])
}

// ---- the module ------------------------------------------------------------------

// Every kernel among the builder's functions from `first` on, written as GLSL compute shaders. `message` says why when it fails.
fn emit(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures, first: usize, message: *str, has_checks: *bool) -> ([]u8, err) {
    var no_bytes: []u8 = zero
    var m: Module = zero
    *has_checks = false
    let (body, body_error) = mem.alloc[u8](a, 4194304usize)
    if body_error != ok { ret (no_bytes, body_error) }
    let (code, code_error) = mem.alloc[u8](a, 4194304usize)
    if code_error != ok { ret (no_bytes, code_error) }
    m.body.data = body
    m.code.data = code
    var function_at = first
    var kernels = 0usize
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        let (index, found) = check.find_function(c, function.module_index, function.name)
        if found && c.functions[index].gpu { kernels += 1usize }
        function_at += 1usize
    }
    if kernels == 0usize {
        *message = "the program has no kernel to write as GLSL"
        ret (no_bytes, Unsupported)
    }
    // (C215) The kernels and every helper they reach: a helper is one GLSL function, which each kernel's shader carries.
    let (helpers, helpers_error) = mem.alloc[u8](a, 2097152usize)
    if helpers_error != ok { ret (no_bytes, helpers_error) }
    let (prototypes, prototypes_error) = mem.alloc[u8](a, 262144usize)
    if prototypes_error != ok { ret (no_bytes, prototypes_error) }
    m.helpers.data = helpers
    m.prototypes.data = prototypes
    m.signatures = signatures
    let (reachable, reachable_error) = mem.alloc[bool](a, builder.function_count + 1usize)
    if reachable_error != ok { ret (no_bytes, reachable_error) }
    var has_calls = false
    function_at = 0usize
    while function_at < builder.function_count {
        reachable[function_at] = is_kernel(c, builder, first, function_at)
        function_at += 1usize
    }
    function_at = 0usize
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        var instruction_at = function.first_instruction
        while instruction_at < function.first_instruction + function.instruction_count {
            if builder.instructions[instruction_at].opcode == .Call { has_calls = true }
            instruction_at += 1usize
        }
        function_at += 1usize
    }
    if has_calls {
        nir.resolve_reference_targets(builder)
        var changed = true
        while changed {
            changed = false
            function_at = 0usize
            while function_at < builder.function_count {
                if reachable[function_at] {
                    let function = builder.functions[function_at]
                    var instruction_at = function.first_instruction
                    while instruction_at < function.first_instruction + function.instruction_count {
                        let instruction = builder.instructions[instruction_at]
                        if instruction.opcode == .Call {
                            let (callee, found) = callee_of(builder, instruction)
                            if !found {
                                *message = "a helper call has no GLSL body"
                                ret (no_bytes, Unsupported)
                            }
                            // math.fma is written in place (D5946), never as a helper of its own.
                            if !reachable[callee] && !same(builder.functions[callee].name, "fma") {
                                reachable[callee] = true
                                changed = true
                            }
                        }
                        instruction_at += 1usize
                    }
                }
                function_at += 1usize
            }
        }
    }
    m.checked = !builder.nocheck && reachable_checked(builder, reachable)
    *has_checks = m.checked
    function_at = 0usize
    while function_at < builder.function_count {
        if reachable[function_at] && !is_kernel(c, builder, first, function_at) {
            let helper_error = emit_helper(a, &m, c, builder, function_at)
            if helper_error != ok {
                *message = m.failure
                ret (no_bytes, helper_error)
            }
        }
        function_at += 1usize
    }
    function_at = first
    while function_at < builder.function_count {
        if is_kernel(c, builder, first, function_at) {
            let function = builder.functions[function_at]
            let (index, found) = check.find_function(c, function.module_index, function.name)
            let kernel_error = emit_kernel(a, &m, c, g, builder, function_at, index)
            if kernel_error != ok {
                *message = m.failure
                ret (no_bytes, kernel_error)
            }
        }
        function_at += 1usize
    }
    if m.body.full || m.code.full || m.helpers.full || m.prototypes.full {
        *message = "the GLSL source is longer than the emitter's buffer"
        ret (no_bytes, mem.Exhausted)
    }
    ret (m.body.data[0usize..m.body.count], ok)
}

fn is_kernel(c: *check.Checker, builder: *nir.Builder, first: usize, function_at: usize) -> bool {
    if function_at < first { ret false }
    let function = builder.functions[function_at]
    let (index, found) = check.find_function(c, function.module_index, function.name)
    ret found && c.functions[index].gpu
}

fn callee_of(builder: *nir.Builder, instruction: nir.Instruction) -> (usize, bool) {
    if instruction.immediate >= builder.function_ref_count { ret (0usize, false) }
    let (callee, found) = nir.function_for_reference(builder, builder.function_refs[instruction.immediate])
    if !found || callee >= builder.function_count { ret (0usize, false) }
    ret (callee, true)
}

// Whether any trap, bounds check or slice check in a reachable function can write a fault.
fn reachable_checked(builder: *nir.Builder, reachable: []const bool) -> bool {
    var function_at = 0usize
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        var at = function.first_instruction
        if !reachable[function_at] { at = function.first_instruction + function.instruction_count }
        while at < function.first_instruction + function.instruction_count {
            let instruction = builder.instructions[at]
            if instruction.opcode == .Trap { ret true }
            if instruction.opcode == .IndexAddress && instruction.operand_count >= 3usize && !instruction.nocheck { ret true }
            if instruction.opcode == .Slice && !instruction.nocheck { ret true }
            at += 1usize
        }
        function_at += 1usize
    }
    ret false
}

// `module_name` with the dots written as underscores, as the MSL emitter names its entry points.
fn put_entry_name(t: *Text, g: *graph.Graph, kernel: check.Function) {
    var module_name = ""
    if kernel.module_index < g.count { module_name = g.modules[kernel.module_index].name }
    var at = 0usize
    while at < module_name.len {
        var one: [1]u8 = zero
        one[0usize] = module_name[at]
        if one[0usize] == 46u8 { one[0usize] = 95u8 }
        put(t, one[0usize..1usize])
        at += 1usize
    }
    put(t, "_")
    put(t, kernel.name)
}

fn init_values(a: *mem.Arena, values: *Values, count: usize) -> err {
    let (kinds, kinds_error) = mem.alloc[u8](a, count)
    if kinds_error != ok { ret kinds_error }
    let (tys, tys_error) = mem.alloc[u8](a, count)
    if tys_error != ok { ret tys_error }
    let (offsets, offsets_error) = mem.alloc[usize](a, count)
    if offsets_error != ok { ret offsets_error }
    let (dynamics, dynamics_error) = mem.alloc[usize](a, count)
    if dynamics_error != ok { ret dynamics_error }
    var at = 0usize
    while at < count {
        kinds[at] = KIND_NONE
        tys[at] = 0u8
        offsets[at] = 0usize
        dynamics[at] = 0usize
        at += 1usize
    }
    values.kind = kinds
    values.ty = tys
    values.offset = offsets
    values.dynamic = dynamics
    ret ok
}

fn operand(builder: *nir.Builder, instruction: nir.Instruction, index: usize) -> usize {
    ret builder.operands[instruction.first_operand + index]
}

fn scalar(values: *Values, value: usize, ty: u8) {
    values.kind[value] = KIND_SCALAR
    values.ty[value] = ty
}

fn emit_kernel(a: *mem.Arena, m: *Module, c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, function_at: usize, checked: usize) -> err {
    let kernel = c.functions[checked]
    m.in_helper = false
    m.shared_words = 0usize
    m.wg_round = has_barrier(builder, function_at)
    var no_values: Values = zero
    var values = no_values
    try lower_function(a, m, c, builder, function_at, kernel, &values)
    put(&m.body, "//entry:")
    put_entry_name(&m.body, g, kernel)
    put(&m.body, "\n#version 430\n")
    if m.helper_wide || uses_wide(builder.functions[function_at], &values) { put(&m.body, "#extension GL_ARB_gpu_shader_int64 : require\n") }
    if m.helper_subgroup || m.needs_subgroup {
        put(&m.body, "#extension GL_KHR_shader_subgroup_basic : require\n#extension GL_KHR_shader_subgroup_vote : require\n#extension GL_KHR_shader_subgroup_ballot : require\n#extension GL_KHR_shader_subgroup_shuffle : require\n#extension GL_KHR_shader_subgroup_arithmetic : require\n")
    }
    let size = usize(kernel.gpu_size)
    put(&m.body, "layout(local_size_x = ")
    put_number(&m.body, size % 1024usize + 1usize)
    put(&m.body, ", local_size_y = ")
    put_number(&m.body, size / 1024usize % 1024usize + 1usize)
    put(&m.body, ", local_size_z = ")
    put_number(&m.body, size / 1048576usize % 1024usize + 1usize)
    put(&m.body, ") in;\nlayout(std430, binding = 0) readonly buffer Args { uint args[]; };\nlayout(std430, binding = 1) buffer Heap { uint heap[]; };\n")
    if m.shared_words != 0usize {
        put(&m.body, "shared uint tg[")
        put_number(&m.body, m.shared_words)
        put(&m.body, "];\n")
    }
    if m.wg_round { put(&m.body, "shared uint wg_pc;\n") }
    if m.needs_dfma || m.helper_dfma { put(&m.body, dfma_source()) }
    if m.shared_words == 0usize && m.helper_shared { put(&m.body, "shared uint tg[1];\n") }
    if m.needs_divide || m.needs_sqrt || m.helper_exact || m.needs_narrow64 || m.helper_narrow64 {
        // An `ftz` kernel (spec section 11, D4203) flushes in the exact sequences as the CPU's FTZ and DAZ do; its helpers too.
        if (check.kernel_fact(c, checked) & 128usize) != 0usize { put(&m.body, "const bool FTZ = true;\n") } else { put(&m.body, "const bool FTZ = false;\n") }
        put(&m.body, exact_source())
    }
    if m.needs_narrow || m.helper_narrow { put(&m.body, narrow_source()) }
    if m.needs_narrow64 || m.helper_narrow64 { put(&m.body, narrow64_source()) }
    put_text(&m.body, &m.prototypes)
    put_text(&m.body, &m.helpers)
    put(&m.body, "void main() {\n")
    put_locals(m, builder.functions[function_at], &values, &m.body)
    put(&m.body, "  return;\n}\n")
    ret ok
}

fn put_text(t: *Text, from: *Text) { put(t, from.data[0usize..from.count]) }

// Whether the function holds a 64-bit integer, which needs GL_ARB_gpu_shader_int64.
fn uses_wide(function: nir.Function, values: *Values) -> bool {
    var at = 0usize
    while at < function.value_count + 1usize {
        if (values.kind[at] == KIND_SCALAR) && is_wide(values.ty[at]) { ret true }
        at += 1usize
    }
    ret false
}

// A helper as a GLSL function `hN`: scalars by value, an aggregate as its words, a shared pointer as its byte offset.
fn emit_helper(a: *mem.Arena, m: *Module, c: *check.Checker, builder: *nir.Builder, function_at: usize) -> err {
    if function_at >= m.signatures.count { ret fail(m, "a helper has no signature") }
    let signature = m.signatures.entries[function_at]
    if signature.return_count > 1usize { ret fail(m, "a helper returns more than one value") }
    var returned = "void"
    var returned_type: u8 = 0u8
    if signature.return_count == 1usize {
        returned_type = value_type(m.signatures.types[signature.first_return_type])
        if returned_type == 0u8 { ret fail(m, "a helper returns a value of a type not yet written as GLSL") }
        returned = type_name(returned_type)
    }
    m.helper_returns = returned
    var header_bytes: [4096]u8 = zero
    var header = Text { data: header_bytes[0usize..4096usize], count: 0usize, full: false }
    put(&header, returned)
    put(&header, " h")
    put_number(&header, function_at)
    put(&header, "(")
    var parameter_at = 0usize
    var listed = 0usize
    while parameter_at < signature.parameter_count {
        let parameter = m.signatures.types[signature.first_parameter_type + parameter_at]
        var words = 1usize
        var name = "uint"
        if aggregate(parameter) {
            let (held, held_error) = aggregate_bytes(c, parameter)
            if held_error != ok { ret held_error }
            words = held / 4usize
        } else {
            if !(parameter.kind == .Pointer && parameter.in_shared) {
                let held = value_type(parameter)
                if held == 0u8 { ret fail(m, "a helper parameter of this type is not yet written as GLSL") }
                name = type_name(held)
            }
        }
        var word = 0usize
        while word < words {
            if listed != 0usize { put(&header, ", ") }
            put(&header, name)
            put(&header, " p")
            put_number(&header, parameter_at)
            put(&header, "_")
            put_number(&header, word)
            listed += 1usize
            word += 1usize
        }
        parameter_at += 1usize
    }
    put(&header, ")")
    if header.full { ret fail(m, "a helper has too many parameter words") }
    put_text(&m.prototypes, &header)
    put(&m.prototypes, ";\n")
    m.in_helper = true
    m.signature = signature
    var no_values: Values = zero
    var values = no_values
    let function = builder.functions[function_at]
    try lower_function(a, m, c, builder, function_at, c.functions[0usize], &values)
    if m.needs_divide || m.needs_sqrt { m.helper_exact = true }
    if m.needs_subgroup { m.helper_subgroup = true }
    if m.needs_dfma { m.helper_dfma = true }
    if m.needs_narrow { m.helper_narrow = true }
    if m.needs_narrow64 { m.helper_narrow64 = true }
    if text_has(&m.code, "tg[") { m.helper_shared = true }
    if uses_wide(function, &values) { m.helper_wide = true }
    put_text(&m.helpers, &header)
    put(&m.helpers, " {\n")
    put_locals(m, function, &values, &m.helpers)
    if returned_type == 0u8 { put(&m.helpers, "  return;\n}\n") } else {
        put(&m.helpers, "  return ")
        put(&m.helpers, returned)
        put(&m.helpers, "(0);\n}\n")
    }
    m.in_helper = false
    ret ok
}

// The function's frame, values and dispatch loop, after its signature line: what `lower_function` left in `m.code`.
fn put_locals(m: *Module, function: nir.Function, values: *Values, out: *Text) {
    put(out, "  uint a;\n")
    if m.frame_bytes != 0usize {
        put(out, "  uint fr[")
        put_number(out, m.frame_bytes / 4usize)
        put(out, "];\n  for (uint z = 0u; z < ")
        put_number(out, m.frame_bytes / 4usize)
        put(out, "u; z += 1u) fr[z] = 0u;\n")
    }
    var value_at = 0usize
    while value_at < function.value_count + 1usize {
        if (values.kind[value_at] == KIND_SCALAR) {
            put(out, "  ")
            if is_float(values.ty[value_at]) { put(out, "precise ") }
            put(out, type_name(values.ty[value_at]))
            put(out, " v")
            put_number(out, value_at)
            put(out, ";\n")
        }
        value_at += 1usize
    }
    var dynamic_at = 1usize
    while dynamic_at <= m.dynamics {
        put(out, "  uint d")
        put_number(out, dynamic_at)
        put(out, " = 0u;\n")
        dynamic_at += 1usize
    }
    put(out, "  uint pc = 0u;\n  while (true) {\n")
    if m.wg_round && !m.in_helper {
        // (D5906) Every invocation, done or not, meets these three barriers each round; the lowest `pc` runs.
        put(out, "    if (gl_LocalInvocationIndex == 0u) { wg_pc = 4294967295u; }\n    memoryBarrierShared(); barrier();\n    atomicMin(wg_pc, pc);\n    memoryBarrierShared(); barrier();\n    uint low = wg_pc;\n    barrier();\n    if (low == 4294967295u) { return; }\n    if (pc != low) { continue; }\n")
        put_text(out, &m.code)
        put(out, "    pc = 4294967295u;\n  }\n")
        ret
    }
    // (D5902) As in MSL: only the lanes of a subgroup at the lowest block run a round, so lanes that took different branches
    // meet again at the join (blocks are in program order, a join after its branches) and a collective sees the lanes the
    // source says.
    if m.needs_subgroup { put(out, "    if (pc != subgroupMin(pc)) { continue; }\n") }
    put_text(out, &m.code)
    put(out, "    break;\n  }\n")
}

// The function's NIR as the dispatch loop's blocks in `m.code`, its values typed in `values`.
fn lower_function(a: *mem.Arena, m: *Module, c: *check.Checker, builder: *nir.Builder, function_at: usize, kernel: check.Function, values: *Values) -> err {
    let function = builder.functions[function_at]
    try init_values(a, values, function.value_count + 1usize)
    m.code.count = 0usize
    m.dynamics = 0usize
    m.frame_bytes = 0usize
    m.needs_divide = false
    m.needs_sqrt = false
    m.needs_subgroup = false
    m.needs_dfma = false
    m.needs_narrow = false
    m.needs_narrow64 = false
    var at = 0usize
    while at < function.instruction_count {
        let instruction = builder.instructions[function.first_instruction + at]
        var bytes = 0usize
        if instruction.opcode == .Stack {
            if instruction.ty.in_shared && instruction.ty.kind == .Integer {
                if instruction.immediate != 0usize {
                    values.kind[instruction.result] = KIND_SHARED
                    m.shared_words = instruction.immediate * 2usize
                }
                at += 1usize
                continue
            }
            bytes = instruction.immediate * 8usize
            if bytes == 0usize { bytes = 8usize }
        }
        if instruction.opcode == .Parameter && aggregate(instruction.ty) {
            let (held, held_error) = aggregate_bytes(c, instruction.ty)
            if held_error != ok { ret held_error }
            bytes = held
        }
        if bytes != 0usize && instruction.has_result {
            values.kind[instruction.result] = KIND_PRIVATE
            values.offset[instruction.result] = m.frame_bytes
            m.frame_bytes += (bytes + 7usize) / 8usize * 8usize
        }
        at += 1usize
    }
    var block_index = 0usize
    while block_index < function.block_count {
        m.block_at = block_index
        m.split_at = 0usize
        put(&m.code, "    if (pc == ")
        put_pc(m, &m.code, block_index)
        put(&m.code, "u) {\n")
        let record = builder.blocks[function.first_block + block_index]
        var instruction_at = 0usize
        while instruction_at < record.instruction_count {
            let instruction = builder.instructions[record.first_instruction + instruction_at]
            try emit_instruction(m, c, builder, function, kernel, instruction, values)
            instruction_at += 1usize
        }
        put(&m.code, "    }\n")
        block_index += 1usize
    }
    ret ok
}

// ---- addresses -------------------------------------------------------------------

fn array_of(values: *Values, address: usize) -> str {
    if (values.kind[address] == KIND_SHARED) { ret "tg" }
    if (values.kind[address] == KIND_PRIVATE) { ret "fr" }
    ret "heap"
}

// `a = <the address's byte offset>;`: the constant and dynamic parts of a private or shared address, or a device address's value.
fn set_address(t: *Text, values: *Values, address: usize, extra: usize) {
    put(t, "      a = ")
    if (values.kind[address] == KIND_SCALAR) {
        put_value(t, address)
        if extra != 0usize {
            put(t, " + ")
            put_number(t, extra)
            put(t, "u")
        }
    } else {
        put_number(t, values.offset[address] + extra)
        put(t, "u")
        if values.dynamic[address] != 0usize {
            put(t, " + d")
            put_number(t, values.dynamic[address])
        }
    }
    put(t, ";\n")
}

// The value of type `ty` at byte `a` of `array`, as an expression.
fn put_read(t: *Text, array: str, ty: u8) {
    let bytes = type_bytes(ty)
    if (ty == T_F64) {
        put(t, "packDouble2x32(uvec2(")
        put(t, array)
        put(t, "[a >> 2u], ")
        put(t, array)
        put(t, "[(a >> 2u) + 1u]))")
        ret
    }
    if bytes == 8usize {
        put(t, type_name(ty))
        put(t, "(packUint2x32(uvec2(")
        put(t, array)
        put(t, "[a >> 2u], ")
        put(t, array)
        put(t, "[(a >> 2u) + 1u])))")
        ret
    }
    if bytes == 4usize {
        if (ty == T_F32) { put(t, "uintBitsToFloat(") }
        if is_signed(ty) { put(t, "int(") }
        put(t, array)
        put(t, "[a >> 2u]")
        if (ty == T_F32) || is_signed(ty) { put(t, ")") }
        ret
    }
    put(t, "bitfieldExtract(")
    if is_signed(ty) { put(t, "int(") }
    put(t, array)
    put(t, "[a >> 2u]")
    if is_signed(ty) { put(t, ")") }
    if bytes == 1usize { put(t, ", int((a & 3u) * 8u), 8)") } else { put(t, ", int((a & 2u) * 8u), 16)") }
    if (ty == T_BOOL) { put(t, " != 0u") }
}

// `value` of type `ty` stored at byte `a` of `array`; narrow stores into memory others share are two atomics.
fn put_write(t: *Text, array: str, ty: u8, value: usize) {
    let bytes = type_bytes(ty)
    if (ty == T_F64) {
        put(t, "      { uvec2 w = unpackDouble2x32(v")
        put_number(t, value)
        put(t, "); ")
        put(t, array)
        put(t, "[a >> 2u] = w.x; ")
        put(t, array)
        put(t, "[(a >> 2u) + 1u] = w.y; }\n")
        ret
    }
    if bytes == 8usize {
        put(t, "      { uvec2 w = unpackUint2x32(uint64_t(v")
        put_number(t, value)
        put(t, ")); ")
        put(t, array)
        put(t, "[a >> 2u] = w.x; ")
        put(t, array)
        put(t, "[(a >> 2u) + 1u] = w.y; }\n")
        ret
    }
    if bytes == 4usize {
        put(t, "      ")
        put(t, array)
        put(t, "[a >> 2u] = ")
        if (ty == T_F32) { put(t, "floatBitsToUint(") } else { put(t, "uint(") }
        put_value(t, value)
        put(t, ");\n")
        ret
    }
    var width = "8"
    var mask = "255u"
    var shift = "((a & 3u) * 8u)"
    if bytes == 2usize {
        width = "16"
        mask = "65535u"
        shift = "((a & 2u) * 8u)"
    }
    if same(array, "fr") {
        put(t, "      fr[a >> 2u] = bitfieldInsert(fr[a >> 2u], uint(")
        put_value(t, value)
        put(t, "), int")
        put(t, shift)
        put(t, ", ")
        put(t, width)
        put(t, ");\n")
        ret
    }
    put(t, "      atomicAnd(")
    put(t, array)
    put(t, "[a >> 2u], ~(")
    put(t, mask)
    put(t, " << ")
    put(t, shift)
    put(t, "));\n      atomicOr(")
    put(t, array)
    put(t, "[a >> 2u], (uint(")
    put_value(t, value)
    put(t, ") & ")
    put(t, mask)
    put(t, ") << ")
    put(t, shift)
    put(t, ");\n")
}

// ---- instructions ----------------------------------------------------------------

fn write_fault(m: *Module, kind: usize, site: usize) {
    let t = &m.code
    line(t, "{")
    line(t, "  uint f = args[0] >> 2u;")
    line(t, "  if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {")
    put(t, "        heap[f + 2u] = bitfieldInsert(heap[f + 2u], ")
    put_number(t, kind)
    put(t, "u, 0, 8);\n        heap[f + 3u] = ")
    put_number(t, site)
    put(t, "u;\n")
    line(t, "    heap[f + 4u] = gl_GlobalInvocationID.x;")
    line(t, "    heap[f + 5u] = gl_GlobalInvocationID.y;")
    line(t, "    heap[f + 6u] = gl_GlobalInvocationID.z;")
    line(t, "  } else {")
    line(t, "    atomicAdd(heap[f], 1u);")
    line(t, "  }")
    line(t, "}")
}

fn guard(m: *Module, holds: str, value_a: usize, value_b: usize, kind: usize, site: usize) {
    let t = &m.code
    put(t, "      if (!(v")
    put_number(t, value_a)
    put(t, " ")
    put(t, holds)
    put(t, " v")
    put_number(t, value_b)
    put(t, ")) {\n")
    write_fault(m, kind, site)
    put_exit(m, "  ")
    line(t, "}")
}

// An invocation leaving the kernel: `return`, or in workgroup rounds a wait at DONE, so it still meets every round's barriers.
fn put_exit(m: *Module, indent: str) {
    put(&m.code, "      ")
    put(&m.code, indent)
    if m.in_helper && !same(m.helper_returns, "void") {
        put(&m.code, "return ")
        put(&m.code, m.helper_returns)
        put(&m.code, "(0);\n")
        ret
    }
    if m.wg_round && !m.in_helper { put(&m.code, "pc = 4294967295u; continue;\n") } else { put(&m.code, "return;\n") }
}

// A block's `pc` as the dispatch loop numbers it.
fn put_pc(m: *Module, t: *Text, block: usize) {
    if m.wg_round && !m.in_helper { put_number(t, block * 64usize) } else { put_number(t, block) }
}

// Whether a function waits at a workgroup barrier.
fn has_barrier(builder: *nir.Builder, function_at: usize) -> bool {
    let function = builder.functions[function_at]
    var at = 0usize
    while at < function.instruction_count {
        if builder.instructions[function.first_instruction + at].opcode == .Barrier { ret true }
        at += 1usize
    }
    ret false
}

fn emit_instruction(m: *Module, c: *check.Checker, builder: *nir.Builder, function: nir.Function, kernel: check.Function, instruction: nir.Instruction, values: *Values) -> err {
    let opcode = instruction.opcode
    let t = &m.code
    if opcode == .Stack { ret ok }
    if opcode == .Parameter {
        if m.in_helper { ret emit_helper_parameter(m, c, instruction, values) }
        ret emit_parameter(m, c, kernel, instruction, values)
    }
    if opcode == .Call { ret emit_call(m, c, builder, instruction, values) }
    if opcode == .Barrier {
        if m.in_helper { ret fail(m, "a barrier in a helper is not written as GLSL") }
        if !m.wg_round {
            line(t, "memoryBarrierShared(); barrier();")
            ret ok
        }
        // The rest of the block is a round of its own: the next round's barriers are the wait.
        m.split_at += 1usize
        if m.split_at >= 64usize { ret fail(m, "a block holds more barriers than the GLSL rounds number") }
        line(t, "memoryBarrierShared();")
        put(t, "      pc = ")
        put_number(t, m.block_at * 64usize + m.split_at)
        put(t, "u; continue;\n    }\n    if (pc == ")
        put_number(t, m.block_at * 64usize + m.split_at)
        put(t, "u) {\n")
        ret ok
    }
    if opcode == .ConstInteger || opcode == .ConstFloat || opcode == .ConstBool || (opcode == .Zero && instruction.has_result) {
        let ty = value_type(instruction.ty)
        if ty == 0u8 { ret fail(m, "a constant of this type is not yet written as GLSL") }
        scalar(values, instruction.result, ty)
        assign(t, instruction.result)
        var bits = instruction.immediate
        if opcode == .Zero { bits = 0usize }
        if (ty == T_BOOL) {
            if bits != 0usize { put(t, "true;\n") } else { put(t, "false;\n") }
            ret ok
        }
        if (ty == T_F32) {
            put(t, "uintBitsToFloat(")
            put_hex(t, bits & 4294967295usize)
            put(t, "u);\n")
            ret ok
        }
        if (ty == T_F64) {
            put(t, "packDouble2x32(uvec2(")
            put_hex(t, bits & 4294967295usize)
            put(t, "u, ")
            put_hex(t, bits >> 32usize)
            put(t, "u));\n")
            ret ok
        }
        if is_wide(ty) {
            put(t, type_name(ty))
            put(t, "(")
            put_hex64(t, bits)
            put(t, ");\n")
            ret ok
        }
        if is_signed(ty) {
            put(t, "int(")
            put_hex(t, bits & 4294967295usize)
            put(t, "u);\n")
            ret ok
        }
        put_hex(t, bits & 4294967295usize)
        put(t, "u;\n")
        ret ok
    }
    if opcode == .Zero {
        let address = operand(builder, instruction, 0usize)
        if (values.kind[address] != KIND_PRIVATE && values.kind[address] != KIND_SHARED) { ret fail(m, "an aggregate zero has no private or shared destination") }
        set_address(t, values, address, 0usize)
        put(t, "      for (uint z = 0u; z < ")
        put_number(t, instruction.immediate)
        put(t, "u; z += 1u) { uint b = a + z; ")
        put(t, array_of(values, address))
        put(t, "[b >> 2u] &= ~(255u << ((b & 3u) * 8u)); }\n")
        ret ok
    }
    if opcode == .GlobalAddress { ret emit_global_address(m, builder, instruction, values) }
    if opcode == .FieldAddress { ret emit_field_address(m, builder, instruction, values) }
    if opcode == .IndexAddress { ret emit_index_address(m, builder, instruction, values) }
    if opcode == .Slice { ret emit_slice(m, builder, instruction, values) }
    if opcode == .Load { ret emit_load(m, builder, instruction, values) }
    if opcode == .Store { ret emit_store(m, builder, instruction, values) }
    if opcode == .Cast { ret emit_cast(m, builder, instruction, values) }
    if opcode == .Add || opcode == .AddWrap || opcode == .Subtract || opcode == .SubtractWrap || opcode == .Multiply || opcode == .MultiplyWrap || opcode == .Divide || opcode == .Remainder || opcode == .BitAnd || opcode == .BitOr || opcode == .BitXor || opcode == .ShiftLeft || opcode == .ShiftRight { ret emit_binary(m, builder, instruction, values) }
    if opcode == .Equal || opcode == .NotEqual || opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual { ret emit_compare(m, builder, instruction, values) }
    if opcode == .Negate || opcode == .BitNot { ret emit_unary(m, builder, instruction, values) }
    if opcode == .Copy { ret emit_copy(m, builder, instruction, values) }
    if opcode == .Return {
        if instruction.operand_count != 0usize {
            let returned = operand(builder, instruction, 0usize)
            if !m.in_helper || (values.kind[returned] != KIND_SCALAR) { ret fail(m, "a kernel returns a value, or a helper an aggregate") }
            put(t, "      return v")
            put_number(t, returned)
            put(t, ";\n")
            ret ok
        }
        put_exit(m, "")
        ret ok
    }
    if opcode == .Branch {
        put(t, "      pc = ")
        put_pc(m, t, instruction.target - function.first_block)
        put(t, "u; continue;\n")
        ret ok
    }
    if opcode == .BranchIf {
        let condition = operand(builder, instruction, 0usize)
        // (D5906) A workgroup pointer's null check: it is an offset into `tg`, never null.
        if (values.kind[condition] == KIND_SHARED) {
            put(t, "      pc = ")
            put_pc(m, t, instruction.target - function.first_block)
            put(t, "u; continue;\n")
            ret ok
        }
        if (values.kind[condition] != KIND_SCALAR) { ret fail(m, "a branch has no condition value") }
        put(t, "      if (v")
        put_number(t, condition)
        if (values.ty[condition] != T_BOOL) { put(t, " != 0u") }
        put(t, ") { pc = ")
        put_pc(m, t, instruction.target - function.first_block)
        put(t, "u; } else { pc = ")
        put_pc(m, t, instruction.target2 - function.first_block)
        put(t, "u; }\n      continue;\n")
        ret ok
    }
    if opcode == .Trap {
        var kind = 99usize
        if same(instruction.ty.name, "null") { kind = 1usize }
        if same(instruction.ty.name, "tag") || same(instruction.ty.name, "enum") || same(instruction.ty.name, "invalid") { kind = 2usize }
        if same(instruction.ty.name, "align") { kind = 3usize }
        if same(instruction.ty.name, "overflow") { kind = 4usize }
        if same(instruction.ty.name, "divide") { kind = 5usize }
        if kind == 99usize { ret fail(m, "this trap kind is not yet written as a device fault") }
        write_fault(m, kind, instruction.site.line)
        put_exit(m, "")
        ret ok
    }
    if opcode == .Sqrt {
        let source = operand(builder, instruction, 0usize)
        if (values.kind[source] == KIND_SCALAR && narrow_code(values.ty[source])) {
            let kind = values.ty[source]
            m.needs_sqrt = true
            m.needs_narrow = true
            scalar(values, instruction.result, kind)
            assign(t, instruction.result)
            put(t, narrow_round(kind))
            put(t, "(f32_sqrt(")
            put(t, narrow_widen(kind))
            put(t, "(v")
            put_number(t, source)
            put(t, ")));\n")
            ret ok
        }
        if (values.kind[source] == KIND_SCALAR && values.ty[source] == T_F64) {
            scalar(values, instruction.result, T_F64)
            assign(t, instruction.result)
            put(t, "sqrt(v")
            put_number(t, source)
            put(t, ");\n")
            put_double_nan(t, instruction.result)
            ret ok
        }
        if (values.kind[source] != KIND_SCALAR || values.ty[source] != T_F32) { ret fail(m, "a square root has no f32 operand") }
        m.needs_sqrt = true
        scalar(values, instruction.result, T_F32)
        assign(t, instruction.result)
        put(t, "uintBitsToFloat(f32_sqrt(floatBitsToUint(v")
        put_number(t, source)
        put(t, ")));\n")
        ret ok
    }
    if opcode == .AtomicLoad || opcode == .AtomicStore || opcode == .AtomicRmw || opcode == .AtomicCas { ret emit_atomic(m, builder, instruction, values) }
    // (D5906) A memory barrier or fence of either scope orders this invocation's accesses to the heap and shared memory.
    if opcode == .MemoryBarrier || opcode == .AtomicFence {
        line(t, "memoryBarrier(); memoryBarrierShared();")
        ret ok
    }
    if opcode == .Subgroup { ret emit_subgroup(m, builder, instruction, values) }
    ret fail(m, "an operation in this kernel is not yet written as GLSL")
}

// ---- subgroups (D5902) ---------------------------------------------------------------
// GL_KHR_shader_subgroup over the active invocations of a subgroup: NIR's kinds 0 all, 1 any, 2 ballot, 3 broadcast,
// 4 shuffle, then the reductions add, min, max, and, or, xor. A broadcast's lane is a value, not a constant, so it is a
// shuffle too. Operations on 64-bit values are `Unsupported`, as in MSL; a ballot's answer is the low 64 lanes.
fn emit_subgroup(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let kind = instruction.immediate
    if kind > 10usize { ret fail(m, "a subgroup operation is unknown") }
    m.needs_subgroup = true
    if kind <= 2usize {
        if instruction.operand_count != 1usize { ret fail(m, "a subgroup operation has the wrong argument count") }
        let predicate = operand(builder, instruction, 0usize)
        if (values.kind[predicate] != KIND_SCALAR || values.ty[predicate] != T_BOOL) { ret fail(m, "a subgroup predicate is not bool") }
        if kind == 2usize {
            scalar(values, instruction.result, 8u8)
            assign(t, instruction.result)
            put(t, "packUint2x32(subgroupBallot(v")
            put_number(t, predicate)
            put(t, ").xy);\n")
            ret ok
        }
        scalar(values, instruction.result, T_BOOL)
        assign(t, instruction.result)
        if kind == 0usize { put(t, "subgroupAll(v") } else { put(t, "subgroupAny(v") }
        put_number(t, predicate)
        put(t, ");\n")
        ret ok
    }
    let ty = value_type(instruction.ty)
    let value = operand(builder, instruction, 0usize)
    // A narrow float's reductions are not integer ones; moving its bits (broadcast, shuffle) is.
    if narrow_code(ty) && kind >= 5usize { ret fail(m, "a subgroup reduction of f16 or bf16 is not written as GLSL") }
    if (ty == 0u8 || ty == T_BOOL || is_wide(ty) || ty == T_F64 || values.kind[value] != KIND_SCALAR || values.ty[value] != ty) { ret fail(m, "a subgroup operation on this type is not written as GLSL") }
    if ((ty == T_F32) && kind >= 8usize) { ret fail(m, "a subgroup bitwise reduction is not integer") }
    scalar(values, instruction.result, ty)
    var call_bytes: [256]u8 = zero
    var call = Text { data: call_bytes[0usize..256usize], count: 0usize, full: false }
    if kind == 3usize || kind == 4usize {
        let lane = operand(builder, instruction, 1usize)
        if (values.kind[lane] != KIND_SCALAR || values.ty[lane] != 6u8) { ret fail(m, "a subgroup exchange lane is not u32") }
        put(&call, "subgroupShuffle(v")
        put_number(&call, value)
        put(&call, ", v")
        put_number(&call, lane)
        put(&call, ")")
    } else {
        var name = "subgroupAdd(v"
        if kind == 6usize { name = "subgroupMin(v" }
        if kind == 7usize { name = "subgroupMax(v" }
        if kind == 8usize { name = "subgroupAnd(v" }
        if kind == 9usize { name = "subgroupOr(v" }
        if kind == 10usize { name = "subgroupXor(v" }
        put(&call, name)
        put_number(&call, value)
        put(&call, ")")
    }
    assign(t, instruction.result)
    // A narrow sum wraps at its own width.
    put_narrowed(t, ty, &call)
    put(t, ";\n")
    ret ok
}

// A parameter from the argument block: a scalar read, a slice's header copied into its frame slot.
fn emit_parameter(m: *Module, c: *check.Checker, kernel: check.Function, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let index = instruction.immediate
    var offset = 0usize
    if m.checked { offset = 8usize }
    var at = 0usize
    while at <= index {
        let ty = c.parameters[kernel.first_parameter + at].ty
        var size = 16usize
        var align = 8usize
        if aggregate(ty) {
            if ty.kind != .Slice { ret fail(m, "a kernel parameter of this type is not yet written as GLSL") }
        } else {
            let held = value_type(ty)
            if (held == 0u8 || held == T_BOOL || held == T_ADDRESS) { ret fail(m, "a kernel parameter of this type is not yet written as GLSL") }
            size = type_bytes(held)
            align = size
        }
        offset = (offset + align - 1usize) / align * align
        if at == index { break }
        offset += size
        at += 1usize
    }
    if !aggregate(instruction.ty) {
        let ty = value_type(instruction.ty)
        if ty == 0u8 { ret fail(m, "a kernel parameter of this type is not yet written as GLSL") }
        scalar(values, instruction.result, ty)
        put(t, "      a = ")
        put_number(t, offset)
        put(t, "u;\n")
        assign(t, instruction.result)
        put_read(t, "args", ty)
        put(t, ";\n")
        ret ok
    }
    if (values.kind[instruction.result] != KIND_PRIVATE) { ret fail(m, "a slice parameter has no frame slot") }
    // The device address's high word is zero: the heap is smaller than 4 GiB.
    let slot = values.offset[instruction.result] / 4usize
    put(t, "      fr[")
    put_number(t, slot)
    put(t, "u] = args[")
    put_number(t, offset / 4usize)
    put(t, "u]; fr[")
    put_number(t, slot + 1usize)
    put(t, "u] = 0u; fr[")
    put_number(t, slot + 2usize)
    put(t, "u] = args[")
    put_number(t, offset / 4usize + 2usize)
    put(t, "u]; fr[")
    put_number(t, slot + 3usize)
    put(t, "u] = 0u;\n")
    ret ok
}

// A helper's parameter from its GLSL parameters `pI_W`: a scalar read, an aggregate's words into its frame slot, a shared
// pointer's offset into a dynamic offset variable.
fn emit_helper_parameter(m: *Module, c: *check.Checker, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let index = instruction.immediate
    if index >= m.signature.parameter_count { ret fail(m, "a helper parameter is out of range") }
    if instruction.ty.kind == .Pointer && instruction.ty.in_shared {
        m.dynamics += 1usize
        put(t, "      d")
        put_number(t, m.dynamics)
        put(t, " = p")
        put_number(t, index)
        put(t, "_0;\n")
        values.kind[instruction.result] = KIND_SHARED
        values.offset[instruction.result] = 0usize
        values.dynamic[instruction.result] = m.dynamics
        ret ok
    }
    if aggregate(instruction.ty) {
        if (values.kind[instruction.result] != KIND_PRIVATE) { ret fail(m, "an aggregate helper parameter has no frame slot") }
        let (held, held_error) = aggregate_bytes(c, instruction.ty)
        if held_error != ok { ret held_error }
        var word = 0usize
        while word < held / 4usize {
            put(t, "      fr[")
            put_number(t, values.offset[instruction.result] / 4usize + word)
            put(t, "u] = p")
            put_number(t, index)
            put(t, "_")
            put_number(t, word)
            put(t, ";\n")
            word += 1usize
        }
        ret ok
    }
    let ty = value_type(instruction.ty)
    if ty == 0u8 { ret fail(m, "a helper parameter of this type is not yet written as GLSL") }
    scalar(values, instruction.result, ty)
    assign(t, instruction.result)
    put(t, "p")
    put_number(t, index)
    put(t, "_0;\n")
    ret ok
}

// A helper call: `hN(...)` with each argument as the callee's parameter list flattens it.
fn emit_call(m: *Module, c: *check.Checker, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let (callee, found) = callee_of(builder, instruction)
    if !found || callee >= m.signatures.count { ret fail(m, "a helper call has no GLSL body") }
    let callee_function = builder.functions[callee]
    // GLSL's fma need not round once, so `math.fma` is f32_fma on the bits (D5946), one of the exact sequences.
    if same(callee_function.name, "fma") {
        if instruction.operand_count != 3usize { ret fail(m, "math.fma takes three operands") }
        let first = operand(builder, instruction, 0usize)
        // f16 and bf16 (D5914): widen, fuse in f32, round once, as the CPU does.
        if (values.kind[first] == KIND_SCALAR && narrow_code(values.ty[first])) {
            let kind = values.ty[first]
            m.needs_divide = true
            m.needs_narrow = true
            scalar(values, instruction.result, kind)
            assign(t, instruction.result)
            put(t, narrow_round(kind))
            put(t, "(f32_fma(")
            var arg = 0usize
            while arg < 3usize {
                if arg != 0usize { put(t, ", ") }
                put(t, narrow_widen(kind))
                put(t, "(v")
                put_number(t, operand(builder, instruction, arg))
                put(t, ")")
                arg += 1usize
            }
            put(t, "));\n")
            ret ok
        }
        if (values.kind[first] == KIND_SCALAR && values.ty[first] == T_F64) {
            m.needs_dfma = true
            scalar(values, instruction.result, T_F64)
            assign(t, instruction.result)
            put(t, "f64_fma(v")
            put_number(t, first)
            put(t, ", v")
            put_number(t, operand(builder, instruction, 1usize))
            put(t, ", v")
            put_number(t, operand(builder, instruction, 2usize))
            put(t, ");\n")
            put_double_nan(t, instruction.result)
            ret ok
        }
        var at = 0usize
        while at < 3usize {
            let source = operand(builder, instruction, at)
            if (values.kind[source] != KIND_SCALAR || values.ty[source] != T_F32) { ret fail(m, "math.fma is written as GLSL for f32 and f64 only") }
            at += 1usize
        }
        m.needs_divide = true
        scalar(values, instruction.result, T_F32)
        assign(t, instruction.result)
        put(t, "uintBitsToFloat(f32_fma(floatBitsToUint(v")
        put_number(t, operand(builder, instruction, 0usize))
        put(t, "), floatBitsToUint(v")
        put_number(t, operand(builder, instruction, 1usize))
        put(t, "), floatBitsToUint(v")
        put_number(t, operand(builder, instruction, 2usize))
        put(t, ")));\n")
        ret ok
    }
    let signature = m.signatures.entries[callee]
    if instruction.operand_count != signature.parameter_count { ret fail(m, "a helper call has the wrong argument count") }
    var call_bytes: [4096]u8 = zero
    var call = Text { data: call_bytes[0usize..4096usize], count: 0usize, full: false }
    put(&call, "h")
    put_number(&call, callee)
    put(&call, "(")
    var listed = 0usize
    var at = 0usize
    while at < instruction.operand_count {
        let argument = operand(builder, instruction, at)
        let parameter = m.signatures.types[signature.first_parameter_type + at]
        if aggregate(parameter) {
            if (values.kind[argument] != KIND_PRIVATE) { ret fail(m, "a helper call has no aggregate argument") }
            let (held, held_error) = aggregate_bytes(c, parameter)
            if held_error != ok { ret held_error }
            var word = 0usize
            while word < held / 4usize {
                if listed != 0usize { put(&call, ", ") }
                put(&call, "fr[(")
                put_number(&call, values.offset[argument] + word * 4usize)
                put(&call, "u")
                if values.dynamic[argument] != 0usize {
                    put(&call, " + d")
                    put_number(&call, values.dynamic[argument])
                }
                put(&call, ") >> 2u]")
                listed += 1usize
                word += 1usize
            }
        } else {
            if listed != 0usize { put(&call, ", ") }
            if parameter.kind == .Pointer && parameter.in_shared {
                if (values.kind[argument] != KIND_SHARED) { ret fail(m, "a helper call has no shared pointer argument") }
                put(&call, "(")
                put_number(&call, values.offset[argument])
                put(&call, "u")
                if values.dynamic[argument] != 0usize {
                    put(&call, " + d")
                    put_number(&call, values.dynamic[argument])
                }
                put(&call, ")")
            } else {
                if (values.kind[argument] != KIND_SCALAR) { ret fail(m, "a helper call has no scalar argument") }
                let held = value_type(parameter)
                if held == 0u8 { ret fail(m, "a helper call passes a type not yet written as GLSL") }
                put(&call, type_name(held))
                put(&call, "(v")
                put_number(&call, argument)
                put(&call, ")")
            }
            listed += 1usize
        }
        at += 1usize
    }
    put(&call, ")")
    if call.full { ret fail(m, "a helper call has too many argument words") }
    if instruction.has_result {
        let ty = value_type(instruction.ty)
        if ty == 0u8 { ret fail(m, "a helper call returns a type not yet written as GLSL") }
        scalar(values, instruction.result, ty)
        assign(t, instruction.result)
    } else {
        put(t, "      ")
    }
    put_text(t, &call)
    put(t, ";\n")
    ret ok
}

fn emit_global_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let index = instruction.immediate
    if index >= builder.global_count { ret fail(m, "a kernel names a global that is not there") }
    let global = builder.globals[index]
    var which = 0usize
    if same(global.name, "gid") { which = 1usize }
    if same(global.name, "lid") { which = 2usize }
    if same(global.name, "wgid") { which = 3usize }
    if same(global.name, "sid") || same(global.name, "subgroup_width") {
        m.needs_subgroup = true
        values.kind[instruction.result] = KIND_INPUT
        values.offset[instruction.result] = 1usize
        if same(global.name, "subgroup_width") { values.offset[instruction.result] = 2usize }
        ret ok
    }
    if which == 0usize { ret fail(m, "a kernel reads a module-scope variable other than the invocation ids") }
    values.kind[instruction.result] = KIND_BUILTIN
    values.offset[instruction.result] = which
    ret ok
}

fn emit_field_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let base = operand(builder, instruction, 0usize)
    let result = instruction.result
    if (values.kind[base] == KIND_PRIVATE || values.kind[base] == KIND_SHARED) {
        values.kind[result] = values.kind[base]
        values.offset[result] = values.offset[base] + instruction.immediate
        values.dynamic[result] = values.dynamic[base]
        ret ok
    }
    if (values.kind[base] == KIND_BUILTIN) {
        // The immediate is the component's byte offset, 4 for `.y`: four times its index, which is what the load reads back.
        values.kind[result] = KIND_BUILTIN
        values.offset[result] = values.offset[base] + instruction.immediate
        ret ok
    }
    if (values.kind[base] != KIND_SCALAR) { ret fail(m, "a field address has no base") }
    scalar(values, result, T_ADDRESS)
    assign(&m.code, result)
    put_value(&m.code, base)
    put(&m.code, " + ")
    put_number(&m.code, instruction.immediate)
    put(&m.code, "u;\n")
    ret ok
}

fn emit_index_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let base = operand(builder, instruction, 0usize)
    let index = operand(builder, instruction, 1usize)
    let result = instruction.result
    if (values.kind[index] != KIND_SCALAR) { ret fail(m, "an index has no value") }
    if instruction.operand_count >= 3usize && !instruction.nocheck {
        let length = operand(builder, instruction, 2usize)
        guard(m, "<", index, length, 0usize, instruction.site.line)
    }
    if (values.kind[base] == KIND_PRIVATE || values.kind[base] == KIND_SHARED) {
        m.dynamics += 1usize
        put(t, "      d")
        put_number(t, m.dynamics)
        put(t, " = ")
        if values.dynamic[base] != 0usize {
            put(t, "d")
            put_number(t, values.dynamic[base])
            put(t, " + ")
        }
        put(t, "uint(v")
        put_number(t, index)
        put(t, ") * ")
        put_number(t, instruction.immediate)
        put(t, "u;\n")
        values.kind[result] = values.kind[base]
        values.offset[result] = values.offset[base]
        values.dynamic[result] = m.dynamics
        ret ok
    }
    if (values.kind[base] != KIND_SCALAR) { ret fail(m, "an indexed address has no base") }
    scalar(values, result, T_ADDRESS)
    assign(t, result)
    put_value(t, base)
    put(t, " + uint(v")
    put_number(t, index)
    put(t, ") * ")
    put_number(t, instruction.immediate)
    put(t, "u;\n")
    ret ok
}

fn emit_slice(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    if instruction.operand_count != 5usize || instruction.immediate == 0usize { ret fail(m, "a slice has an unexpected shape") }
    let destination = operand(builder, instruction, 0usize)
    let data = operand(builder, instruction, 1usize)
    let length = operand(builder, instruction, 2usize)
    let lower = operand(builder, instruction, 3usize)
    let upper = operand(builder, instruction, 4usize)
    if (values.kind[destination] != KIND_PRIVATE) { ret fail(m, "a slice has no private header") }
    if (values.kind[length] != KIND_SCALAR || values.kind[lower] != KIND_SCALAR || values.kind[upper] != KIND_SCALAR) { ret fail(m, "a slice has no bounds") }
    if !instruction.nocheck {
        guard(m, "<=", lower, upper, 0usize, instruction.site.line)
        guard(m, "<=", upper, length, 0usize, instruction.site.line)
    }
    if values.dynamic[destination] != 0usize { ret fail(m, "a slice header at a computed place is not yet written as GLSL") }
    let slot = values.offset[destination] / 4usize
    put(t, "      fr[")
    put_number(t, slot)
    put(t, "u] = ")
    if (values.kind[data] == KIND_SHARED) {
        put_number(t, values.offset[data])
        put(t, "u")
        if values.dynamic[data] != 0usize {
            put(t, " + d")
            put_number(t, values.dynamic[data])
        }
    } else {
        if (values.kind[data] != KIND_SCALAR) { ret fail(m, "a slice has no device or shared base") }
        put_value(t, data)
    }
    put(t, " + uint(v")
    put_number(t, lower)
    put(t, ") * ")
    put_number(t, instruction.immediate)
    put(t, "u; fr[")
    put_number(t, slot + 1usize)
    put(t, "u] = 0u; fr[")
    put_number(t, slot + 2usize)
    put(t, "u] = uint(v")
    put_number(t, upper)
    put(t, ") - uint(v")
    put_number(t, lower)
    put(t, "); fr[")
    put_number(t, slot + 3usize)
    put(t, "u] = 0u;\n")
    ret ok
}

fn emit_load(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let address = operand(builder, instruction, 0usize)
    let result = instruction.result
    if instruction.ty.kind == .Pointer && instruction.ty.in_shared {
        // A workgroup pointer read from a slice header: the header's first word is its offset.
        if (values.kind[address] != KIND_PRIVATE) || (m.shared_words == 0usize && !m.in_helper) { ret fail(m, "a shared pointer is not loaded from a slice header") }
        set_address(t, values, address, 0usize)
        m.dynamics += 1usize
        put(t, "      d")
        put_number(t, m.dynamics)
        put(t, " = fr[a >> 2u];\n")
        values.kind[result] = KIND_SHARED
        values.offset[result] = 0usize
        values.dynamic[result] = m.dynamics
        ret ok
    }
    let ty = value_type(instruction.ty)
    if ty == 0u8 { ret fail(m, "a load of this type is not yet written as GLSL") }
    if (values.kind[address] == KIND_INPUT) {
        if ty != 6u8 { ret fail(m, "a subgroup input is read in an unexpected shape") }
        scalar(values, result, ty)
        assign(&m.code, result)
        // gl_SubgroupSize is the largest width the driver may pick (Intel says 32 and runs 16), so the width is the one the
        // workgroup was cut into: its size over its subgroups, up to a power of two. A workgroup smaller than one subgroup
        // reads as its own size rounded up, not the hardware's (a known ceiling).
        if values.offset[address] == 1usize { put(&m.code, "gl_SubgroupInvocationID;\n") } else { put(&m.code, "min(gl_SubgroupSize, 1u << uint(findMSB((gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z + gl_NumSubgroups - 1u) / gl_NumSubgroups - 1u) + 1));\n") }
        ret ok
    }
    if (values.kind[address] == KIND_BUILTIN) {
        let which = values.offset[address]
        if ty != 6u8 { ret fail(m, "an invocation id is read in an unexpected shape") }
        let number = which % 4usize
        let part = which / 4usize
        if part > 2usize { ret fail(m, "an invocation id is read in an unexpected shape") }
        scalar(values, result, ty)
        assign(t, result)
        if number == 1usize { put(t, "gl_GlobalInvocationID.") }
        if number == 2usize { put(t, "gl_LocalInvocationID.") }
        if number == 3usize { put(t, "gl_WorkGroupID.") }
        if part == 0usize { put(t, "x;\n") }
        if part == 1usize { put(t, "y;\n") }
        if part == 2usize { put(t, "z;\n") }
        ret ok
    }
    if (values.kind[address] != KIND_PRIVATE && values.kind[address] != KIND_SHARED && values.kind[address] != KIND_SCALAR) { ret fail(m, "a load has no address") }
    if (values.kind[address] == KIND_SCALAR && ty == T_BOOL) { ret fail(m, "a bool in device memory is not a device storage type") }
    set_address(t, values, address, 0usize)
    scalar(values, result, ty)
    assign(t, result)
    put_read(t, array_of(values, address), ty)
    put(t, ";\n")
    ret ok
}

fn emit_store(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let address = operand(builder, instruction, 0usize)
    let value = operand(builder, instruction, 1usize)
    if (values.kind[value] == KIND_SHARED && values.kind[address] == KIND_PRIVATE) {
        set_address(t, values, address, 0usize)
        put(t, "      fr[a >> 2u] = ")
        put_number(t, values.offset[value])
        put(t, "u")
        if values.dynamic[value] != 0usize {
            put(t, " + d")
            put_number(t, values.dynamic[value])
        }
        put(t, ";\n")
        ret ok
    }
    if (values.kind[value] != KIND_SCALAR) { ret fail(m, "a store of an aggregate is not yet written as GLSL") }
    let ty = values.ty[value]
    if (values.kind[address] != KIND_PRIVATE && values.kind[address] != KIND_SHARED && values.kind[address] != KIND_SCALAR) { ret fail(m, "a store has no address") }
    if (values.kind[address] == KIND_SCALAR && ty == T_BOOL) { ret fail(m, "a bool in device memory is not a device storage type") }
    set_address(t, values, address, 0usize)
    put_write(t, array_of(values, address), ty, value)
    // An address is eight bytes where it is kept: its high word is zero.
    if (ty == T_ADDRESS) {
        put(t, "      ")
        put(t, array_of(values, address))
        put(t, "[(a >> 2u) + 1u] = 0u;\n")
    }
    ret ok
}

fn emit_copy(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let destination = operand(builder, instruction, 0usize)
    let source = operand(builder, instruction, 1usize)
    if (values.kind[destination] != KIND_PRIVATE && values.kind[destination] != KIND_SHARED) || (values.kind[source] != KIND_PRIVATE && values.kind[source] != KIND_SHARED) { ret fail(m, "an aggregate copy has no private or shared operand") }
    set_address(t, values, source, 0usize)
    put(t, "      { uint s = a;\n")
    set_address(t, values, destination, 0usize)
    put(t, "      for (uint z = 0u; z < ")
    put_number(t, instruction.immediate)
    put(t, "u; z += 1u) { uint b = a + z; uint c = s + z; uint y = bitfieldExtract(")
    put(t, array_of(values, source))
    put(t, "[c >> 2u], int((c & 3u) * 8u), 8); ")
    put(t, array_of(values, destination))
    put(t, "[b >> 2u] = bitfieldInsert(")
    put(t, array_of(values, destination))
    put(t, "[b >> 2u], y, int((b & 3u) * 8u), 8); } }\n")
    ret ok
}

// (D5914) Conversions to and from f16 and bf16, each one rounding of the value (the CPU's, D5913). Narrow to f32 or f64 is
// exact; f32, f64 and an integer of 32 bits or fewer to narrow is one round-to-nearest-even in integer code (an integer of 32
// bits or fewer is exact in f64, so through f64 it is the one rounding of its value); narrow to narrow and to an integer go
// through f32. A 64-bit integer to narrow is not written: the CPU rounds it to f64 first.
fn emit_narrow_cast(m: *Module, instruction: nir.Instruction, ty: u8, from: u8, source: usize, values: *Values) -> err {
    let t = &m.code
    m.needs_narrow = true
    scalar(values, instruction.result, ty)
    assign(t, instruction.result)
    if narrow_code(from) {
        if (ty == T_BOOL) {
            put(t, "(v")
            put_number(t, source)
            put(t, " & 32767u) != 0u;\n")
            ret ok
        }
        if narrow_code(ty) {
            if ty == from {
                put_value(t, source)
                put(t, ";\n")
                ret ok
            }
            put(t, narrow_round(ty))
            put(t, "(")
            put(t, narrow_widen(from))
            put(t, "(v")
            put_number(t, source)
            put(t, "));\n")
            ret ok
        }
        if (ty == T_F32) {
            put(t, "uintBitsToFloat(")
            put(t, narrow_widen(from))
            put(t, "(v")
            put_number(t, source)
            put(t, "));\n")
            ret ok
        }
        if (ty == T_F64) {
            put(t, "double(uintBitsToFloat(")
            put(t, narrow_widen(from))
            put(t, "(v")
            put_number(t, source)
            put(t, ")));\n")
            put_double_nan(t, instruction.result)
            ret ok
        }
        if ty >= 2u8 && ty <= 7u8 {
            var inner: [96]u8 = zero
            var expression = Text { data: inner[0usize..96usize], count: 0usize, full: false }
            put(&expression, type_name(ty))
            put(&expression, "(uintBitsToFloat(")
            put(&expression, narrow_widen(from))
            put(&expression, "(v")
            put_number(&expression, source)
            put(&expression, ")))")
            put_narrowed(t, ty, &expression)
            put(t, ";\n")
            ret ok
        }
        ret fail(m, "this conversion from f16 or bf16 is not yet written as GLSL")
    }
    // To a narrow type.
    if (from == T_F32) {
        put(t, narrow_round(ty))
        put(t, "(floatBitsToUint(v")
        put_number(t, source)
        put(t, "));\n")
        ret ok
    }
    if (from == T_F64) {
        m.needs_narrow64 = true
        put(t, "f64_bits_to_narrow(unpackDouble2x32(v")
        put_number(t, source)
        if (ty == T_F16) { put(t, "), 10, -14, 15);\n") } else { put(t, "), 7, -126, 127);\n") }
        ret ok
    }
    if from >= 2u8 && from <= 7u8 {
        var helper = "int_to_h"
        if (ty == T_BF16) { helper = "int_to_bf" }
        put(t, helper)
        if is_signed(from) {
            put(t, "((int(v")
            put_number(t, source)
            put(t, ") < 0) ? (0u - uint(v")
            put_number(t, source)
            put(t, ")) : uint(v")
            put_number(t, source)
            put(t, "), (int(v")
            put_number(t, source)
            put(t, ") < 0) ? 0x8000u : 0u);\n")
        } else {
            put(t, "(v")
            put_number(t, source)
            put(t, ", 0u);\n")
        }
        ret ok
    }
    ret fail(m, "this conversion to f16 or bf16 is not yet written as GLSL")
}

fn emit_cast(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    let ty = value_type(instruction.ty)
    if (ty == 0u8 || values.kind[source] != KIND_SCALAR) { ret fail(m, "a conversion of this type is not yet written as GLSL") }
    let from = values.ty[source]
    if (from == T_ADDRESS || ty == T_ADDRESS) && from != ty { ret fail(m, "a conversion between an address and an integer is not written as GLSL") }
    if narrow_code(ty) || narrow_code(from) { ret emit_narrow_cast(m, instruction, ty, from, source, values) }
    scalar(values, instruction.result, ty)
    let t = &m.code
    assign(t, instruction.result)
    if (ty == T_BOOL) {
        put_value(t, source)
        if is_float(from) { put(t, " != 0.0;\n") } else { put(t, " != 0;\n") }
        ret ok
    }
    var inner: [64]u8 = zero
    var expression = Text { data: inner[0usize..64usize], count: 0usize, full: false }
    put(&expression, type_name(ty))
    put(&expression, "(")
    put_value(&expression, source)
    put(&expression, ")")
    put_narrowed(t, ty, &expression)
    put(t, ";\n")
    // Section 11: a NaN converted is the canonical NaN of its new width, not the old payload.
    if (ty == T_F64) { put_double_nan(t, instruction.result) }
    if (ty == T_F32) && (from == T_F64) {
        put(t, "      if (isnan(v")
        put_number(t, instruction.result)
        put(t, ")) v")
        put_number(t, instruction.result)
        put(t, " = uintBitsToFloat(0x7FC00000u);\n")
    }
    ret ok
}

// (D5914) f16 and bf16 arithmetic: widen both, one f32 operation, round once. Division is the exact f32 sequence, so the
// answer is the correctly rounded f32 quotient rounded again, as the CPU's.
fn emit_narrow_binary(m: *Module, instruction: nir.Instruction, ty: u8, left: usize, right: usize, values: *Values) -> err {
    let t = &m.code
    let opcode = instruction.opcode
    var symbol = ""
    if opcode == .Add { symbol = "+" }
    if opcode == .Subtract { symbol = "-" }
    if opcode == .Multiply { symbol = "*" }
    if symbol.len == 0usize && opcode != .Divide { ret fail(m, "this f16 or bf16 operation is not yet written as GLSL") }
    m.needs_narrow = true
    scalar(values, instruction.result, ty)
    assign(t, instruction.result)
    put(t, narrow_round(ty))
    if opcode == .Divide {
        m.needs_divide = true
        put(t, "(f32_div(")
        put(t, narrow_widen(ty))
        put(t, "(v")
        put_number(t, left)
        put(t, "), ")
        put(t, narrow_widen(ty))
        put(t, "(v")
        put_number(t, right)
        put(t, ")));\n")
        ret ok
    }
    // The f32 result goes through floatBitsToUint and integer rounding, which nothing can fuse across.
    put(t, "(floatBitsToUint(uintBitsToFloat(")
    put(t, narrow_widen(ty))
    put(t, "(v")
    put_number(t, left)
    put(t, ")) ")
    put(t, symbol)
    put(t, " uintBitsToFloat(")
    put(t, narrow_widen(ty))
    put(t, "(v")
    put_number(t, right)
    put(t, "))));\n")
    ret ok
}

fn emit_binary(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let left = operand(builder, instruction, 0usize)
    let right = operand(builder, instruction, 1usize)
    let ty = value_type(instruction.ty)
    if (ty == 0u8 || values.kind[left] != KIND_SCALAR || values.kind[right] != KIND_SCALAR) { ret fail(m, "an arithmetic operation of this type is not yet written as GLSL") }
    if (ty == T_BOOL) { ret fail(m, "an integer operation is not yet written as GLSL") }
    let opcode = instruction.opcode
    let t = &m.code
    if narrow_code(ty) { ret emit_narrow_binary(m, instruction, ty, left, right, values) }
    var symbol = ""
    if opcode == .Add || opcode == .AddWrap { symbol = "+" }
    if opcode == .Subtract || opcode == .SubtractWrap { symbol = "-" }
    if opcode == .Multiply || opcode == .MultiplyWrap { symbol = "*" }
    if (ty == T_F32) {
        if opcode == .Divide {
            m.needs_divide = true
            scalar(values, instruction.result, ty)
            assign(t, instruction.result)
            put(t, "uintBitsToFloat(f32_div(floatBitsToUint(v")
            put_number(t, left)
            put(t, "), floatBitsToUint(v")
            put_number(t, right)
            put(t, ")));\n")
            ret ok
        }
        if symbol.len == 0usize { ret fail(m, "this float operation is not yet written as GLSL") }
    } else {
    if (ty == T_F64) {
        if opcode == .Divide { symbol = "/" }
        if symbol.len == 0usize { ret fail(m, "this f64 operation is not yet written as GLSL") }
    } else {
        if is_signed(ty) && (opcode == .Divide || opcode == .Remainder) {
            // GLSL leaves a negative operand's quotient and remainder undefined: both are taken from the magnitudes, as
            // unsigned steps with an unsigned negation.
            scalar(values, instruction.result, ty)
            let magnitude = unsigned_name(ty)
            var zero_literal = "0u"
            if is_wide(ty) { zero_literal = "0ul" }
            put(t, "      { ")
            put(t, magnitude)
            put(t, " n = (v")
            put_number(t, left)
            put(t, " < 0) ? ")
            put(t, zero_literal)
            put(t, " - ")
            put(t, magnitude)
            put(t, "(v")
            put_number(t, left)
            put(t, ") : ")
            put(t, magnitude)
            put(t, "(v")
            put_number(t, left)
            put(t, "); ")
            put(t, magnitude)
            put(t, " d = (v")
            put_number(t, right)
            put(t, " < 0) ? ")
            put(t, zero_literal)
            put(t, " - ")
            put(t, magnitude)
            put(t, "(v")
            put_number(t, right)
            put(t, ") : ")
            put(t, magnitude)
            put(t, "(v")
            put_number(t, right)
            // Both get a zero the compiler cannot prove (a dispatch has at least one group along z). Intel's compiler took
            // `|a * b| / |a|` for an exact division and folded it wrongly, so every checked signed multiply faulted, and its
            // sequence for an unsigned division by a constant 7 answered 0.
            put(t, "); n += ")
            put(t, unknown_zero(ty))
            put(t, "; d += ")
            put(t, unknown_zero(ty))
            put(t, "; ")
            put(t, magnitude)
            if opcode == .Divide {
                put(t, " q = n / d; bool negative = (v")
                put_number(t, left)
                put(t, " < 0) != (v")
                put_number(t, right)
                put(t, " < 0);")
            } else {
                put(t, " q = n % d; bool negative = v")
                put_number(t, left)
                put(t, " < 0;")
            }
            var inner: [64]u8 = zero
            var expression = Text { data: inner[0usize..64usize], count: 0usize, full: false }
            put(&expression, type_name(ty))
            put(&expression, "(negative ? ")
            put(&expression, zero_literal)
            put(&expression, " - q : q)")
            put(t, " v")
            put_number(t, instruction.result)
            put(t, " = ")
            put_narrowed(t, ty, &expression)
            put(t, "; }\n")
            ret ok
        }
        if opcode == .Divide { symbol = "/" }
        if opcode == .Remainder { symbol = "%" }
        if opcode == .BitAnd { symbol = "&" }
        if opcode == .BitOr { symbol = "|" }
        if opcode == .BitXor { symbol = "^" }
        if opcode == .ShiftLeft { symbol = "<<" }
        if opcode == .ShiftRight { symbol = ">>" }
    }
    }
    if symbol.len == 0usize { ret fail(m, "an integer operation is not yet written as GLSL") }
    scalar(values, instruction.result, ty)
    var inner: [256]u8 = zero
    var expression = Text { data: inner[0usize..256usize], count: 0usize, full: false }
    put(&expression, type_name(ty))
    put(&expression, "(v")
    put_number(&expression, left)
    // The same unprovable zero as the signed case: an unsigned multiply's overflow check divides the product too.
    if !is_float(ty) && (opcode == .Divide || opcode == .Remainder) {
        put(&expression, " + ")
        put(&expression, unknown_zero(ty))
    }
    put(&expression, ") ")
    put(&expression, symbol)
    put(&expression, " ")
    // A shift's count is the left operand's type in GLSL only when both are; give it the same signedness.
    put(&expression, type_name(ty))
    put(&expression, "(v")
    put_number(&expression, right)
    if !is_float(ty) && (opcode == .Divide || opcode == .Remainder) {
        put(&expression, " + ")
        put(&expression, unknown_zero(ty))
    }
    put(&expression, ")")
    assign(t, instruction.result)
    put_narrowed(t, ty, &expression)
    put(t, ";\n")
    // Section 11: a NaN result is the one canonical quiet NaN, whatever the device's arithmetic left in the payload.
    if (ty == T_F32) {
        put(t, "      if (isnan(v")
        put_number(t, instruction.result)
        put(t, ")) v")
        put_number(t, instruction.result)
        put(t, " = uintBitsToFloat(0x7FC00000u);\n")
    }
    if (ty == T_F64) { put_double_nan(t, instruction.result) }
    ret ok
}

// Section 11's canonical NaN for an f64 result, 0x7FF8000000000000.
fn put_double_nan(t: *Text, value: usize) {
    put(t, "      if (isnan(v")
    put_number(t, value)
    put(t, ")) v")
    put_number(t, value)
    put(t, " = packDouble2x32(uvec2(0u, 0x7FF80000u));\n")
}

fn emit_compare(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let left = operand(builder, instruction, 0usize)
    let right = operand(builder, instruction, 1usize)
    if (values.kind[left] != KIND_SCALAR || values.kind[right] != KIND_SCALAR) { ret fail(m, "a comparison has no operands") }
    if (values.ty[left] == T_BOOL) { ret fail(m, "a bool comparison is not yet written as GLSL") }
    let opcode = instruction.opcode
    let narrow_kind = values.ty[left]
    var symbol = "=="
    if opcode == .NotEqual { symbol = "!=" }
    if opcode == .Less { symbol = "<" }
    if opcode == .LessEqual { symbol = "<=" }
    if opcode == .Greater { symbol = ">" }
    if opcode == .GreaterEqual { symbol = ">=" }
    let t = &m.code
    scalar(values, instruction.result, T_BOOL)
    assign(t, instruction.result)
    // (D5914) f16 and bf16 compare widened, in f32, where it is exact.
    if narrow_code(narrow_kind) {
        m.needs_narrow = true
        put(t, "uintBitsToFloat(")
        put(t, narrow_widen(narrow_kind))
        put(t, "(v")
        put_number(t, left)
        put(t, ")) ")
        put(t, symbol)
        put(t, " uintBitsToFloat(")
        put(t, narrow_widen(narrow_kind))
        put(t, "(v")
        put_number(t, right)
        put(t, "));\n")
        ret ok
    }
    put_value(t, left)
    put(t, " ")
    put(t, symbol)
    put(t, " ")
    put(t, type_name(values.ty[left]))
    put(t, "(v")
    put_number(t, right)
    put(t, ");\n")
    ret ok
}

fn emit_unary(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    if (values.kind[source] != KIND_SCALAR) { ret fail(m, "a unary operation has no operand") }
    let ty = values.ty[source]
    let t = &m.code
    scalar(values, instruction.result, ty)
    assign(t, instruction.result)
    if (ty == T_BOOL) {
        if instruction.opcode != .BitNot { ret fail(m, "a bool operation is not yet written as GLSL") }
        put(t, "!")
        put_value(t, source)
        put(t, ";\n")
        ret ok
    }
    if narrow_code(ty) && instruction.opcode == .Negate {
        // Bit 15 flips; a NaN becomes the width's canonical one (D5914).
        put(t, "(((v")
        put_number(t, source)
        put(t, " & 0x7FFFu) > ")
        if (ty == T_F16) { put(t, "0x7C00u) ? 0x7E00u : ") } else { put(t, "0x7F80u) ? 0x7FC0u : ") }
        put(t, "(v")
        put_number(t, source)
        put(t, " ^ 0x8000u));\n")
        ret ok
    }
    var inner: [32]u8 = zero
    var expression = Text { data: inner[0usize..32usize], count: 0usize, full: false }
    if instruction.opcode == .Negate {
        // Subtracted from zero rather than negated: Intel's compiler got a negated constant wrong in a later comparison.
        if is_float(ty) { put(&expression, "-") } else {
            put(&expression, type_name(ty))
            put(&expression, "(0) - ")
        }
    } else { put(&expression, "~") }
    put_value(&expression, source)
    put_narrowed(t, ty, &expression)
    put(t, ";\n")
    ret ok
}

// ---- atomics -----------------------------------------------------------------------
// GLSL's atomics are 32 bits and act on a `uint` word of `heap` or `tg`; a signed minimum or maximum (the heap is `uint`) is
// `Unsupported` here.

fn put_atomic_word(m: *Module, values: *Values, address: usize) -> err {
    if (values.kind[address] != KIND_SCALAR && values.kind[address] != KIND_SHARED) { ret fail(m, "an atomic operation has no device or shared address") }
    set_address(&m.code, values, address, 0usize)
    ret ok
}

// (D5906) GLSL's atomics are relaxed; an order stronger than that is the relaxed operation between two full fences, which
// orders this invocation's other accesses on both sides (release before, acquire after, both for AcqRel and SeqCst).
fn emit_atomic(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    var ordering = instruction.immediate % 8usize
    if instruction.opcode == .AtomicCas { ordering = (instruction.immediate / 8usize % 8usize) + (instruction.immediate % 8usize) }
    if ordering != 0usize { line(&m.code, "memoryBarrier(); memoryBarrierShared();") }
    try emit_atomic_relaxed(m, builder, instruction, values)
    if ordering != 0usize { line(&m.code, "memoryBarrier(); memoryBarrierShared();") }
    ret ok
}

fn emit_atomic_relaxed(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let address = operand(builder, instruction, 0usize)
    let ty = value_type(instruction.ty)
    if ty != 6u8 && ty != 7u8 { ret fail(m, "an atomic operation of this width is not written as GLSL: its atomics are 32 bits") }
    try put_atomic_word(m, values, address)
    let array = array_of(values, address)
    let opcode = instruction.opcode
    if opcode == .AtomicLoad {
        scalar(values, instruction.result, ty)
        assign(t, instruction.result)
        put(t, type_name(ty))
        put(t, "(atomicOr(")
        put(t, array)
        put(t, "[a >> 2u], 0u));\n")
        ret ok
    }
    if opcode == .AtomicCas {
        let expected = operand(builder, instruction, 1usize)
        let desired = operand(builder, instruction, 2usize)
        if (values.kind[expected] != KIND_SCALAR || values.kind[desired] != KIND_SCALAR) { ret fail(m, "an atomic compare-and-swap has no value") }
        scalar(values, instruction.result, ty)
        assign(t, instruction.result)
        put(t, type_name(ty))
        put(t, "(atomicCompSwap(")
        put(t, array)
        put(t, "[a >> 2u], uint(v")
        put_number(t, expected)
        put(t, "), uint(v")
        put_number(t, desired)
        put(t, ")));\n")
        ret ok
    }
    let value = operand(builder, instruction, 1usize)
    if (values.kind[value] != KIND_SCALAR) { ret fail(m, "an atomic operation has no value") }
    if opcode == .AtomicStore {
        put(t, "      atomicExchange(")
        put(t, array)
        put(t, "[a >> 2u], uint(v")
        put_number(t, value)
        put(t, "));\n")
        ret ok
    }
    let kind = instruction.immediate / 16usize
    if (kind == 6usize || kind == 7usize) && ty == 7u8 { ret fail(m, "a signed atomic minimum or maximum is not yet written as GLSL") }
    var name = "atomicExchange"
    var negate = false
    if kind == 1usize { name = "atomicAdd" }
    if kind == 2usize {
        name = "atomicAdd"
        negate = true
    }
    if kind == 3usize { name = "atomicAnd" }
    if kind == 4usize { name = "atomicOr" }
    if kind == 5usize { name = "atomicXor" }
    if kind == 6usize { name = "atomicMin" }
    if kind == 7usize { name = "atomicMax" }
    scalar(values, instruction.result, ty)
    assign(t, instruction.result)
    put(t, type_name(ty))
    put(t, "(")
    put(t, name)
    put(t, "(")
    put(t, array)
    put(t, "[a >> 2u], ")
    if negate { put(t, "0u - ") }
    put(t, "uint(v")
    put_number(t, value)
    put(t, ")));\n")
    ret ok
}
