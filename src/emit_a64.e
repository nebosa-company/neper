// Deterministic AArch64 (A64) machine-code encoding: every instruction one
// little-endian 32-bit word, written into the same byte buffer the x64 encoder uses.
//
// Registers are numbered 0..30; 31 is `sp` or the zero register, as each instruction
// reads it. A branch or an address form is written with a zero offset and patched
// later by `patch_relative`, which reads the kind of instruction it patches from the
// word itself, so a relocation needs no kind of its own.
use emit_x64

error OutOfRange
error NotPatchable

const A64_SP: usize = 31usize
const A64_ZR: usize = 31usize

// The condition codes, as B.cond and CSEL encode them.
const A64_EQ: usize = 0usize
const A64_NE: usize = 1usize
const A64_HS: usize = 2usize
const A64_LO: usize = 3usize
const A64_MI: usize = 4usize
const A64_PL: usize = 5usize
const A64_VS: usize = 6usize
const A64_VC: usize = 7usize
const A64_HI: usize = 8usize
const A64_LS: usize = 9usize
const A64_GE: usize = 10usize
const A64_LT: usize = 11usize
const A64_GT: usize = 12usize
const A64_LE: usize = 13usize

fn instruction_word(output: *emit_x64.Buffer, value: usize) -> err {
    ret emit_x64.little_u32(output, value & 0xFFFFFFFFusize)
}

fn read_word(output: *emit_x64.Buffer, at: usize) -> usize {
    ret usize(output.bytes[at]) | (usize(output.bytes[at + 1usize]) << 8usize) | (usize(output.bytes[at + 2usize]) << 16usize) | (usize(output.bytes[at + 3usize]) << 24usize)
}

fn write_word(output: *emit_x64.Buffer, at: usize, value: usize) -> err {
    if at + 4usize > output.count { ret OutOfRange }
    output.bytes[at] = u8(value & 255usize)
    output.bytes[at + 1usize] = u8((value >> 8usize) & 255usize)
    output.bytes[at + 2usize] = u8((value >> 16usize) & 255usize)
    output.bytes[at + 3usize] = u8((value >> 24usize) & 255usize)
    ret ok
}

// Whether a two's-complement `delta` (wrapped into a usize) fits a signed field of
// `bits` bits.
fn signed_fits(delta: usize, bits: usize) -> bool {
    let half = 1usize << (bits - 1usize)
    let fits = (delta +% half) < (half << 1usize)
    ret fits
}

fn invert_condition(condition: usize) -> usize { ret condition ^ 1usize }

// ---------------------------------------------------------------- moves and constants

fn movz(output: *emit_x64.Buffer, rd: usize, imm16: usize, halfword: usize) -> err {
    ret instruction_word(output, 0xD2800000usize | (halfword << 21usize) | ((imm16 & 0xFFFFusize) << 5usize) | rd)
}

fn movk(output: *emit_x64.Buffer, rd: usize, imm16: usize, halfword: usize) -> err {
    ret instruction_word(output, 0xF2800000usize | (halfword << 21usize) | ((imm16 & 0xFFFFusize) << 5usize) | rd)
}

fn movn(output: *emit_x64.Buffer, rd: usize, imm16: usize, halfword: usize) -> err {
    ret instruction_word(output, 0x92800000usize | (halfword << 21usize) | ((imm16 & 0xFFFFusize) << 5usize) | rd)
}

// Any 64-bit constant in the fewest MOVZ/MOVN-then-MOVK words: from the zero
// register's side when most halfwords are zero, from all-ones when most are 0xFFFF.
fn move_constant(output: *emit_x64.Buffer, rd: usize, value: usize) -> err {
    var zeros = 0usize
    var ones = 0usize
    var at = 0usize
    while at < 4usize {
        let half = (value >> (at * 16usize)) & 0xFFFFusize
        if half == 0usize { zeros += 1usize }
        if half == 0xFFFFusize { ones += 1usize }
        at += 1usize
    }
    var inverted = ones > zeros
    var skip = 0usize
    if inverted { skip = 0xFFFFusize }
    var first = true
    at = 0usize
    while at < 4usize {
        let half = (value >> (at * 16usize)) & 0xFFFFusize
        if half != skip {
            if first {
                if inverted { try movn(output, rd, half ^ 0xFFFFusize, at) } else { try movz(output, rd, half, at) }
                first = false
            } else {
                try movk(output, rd, half, at)
            }
        }
        at += 1usize
    }
    if first {
        if inverted { ret movn(output, rd, 0usize, 0usize) }
        ret movz(output, rd, 0usize, 0usize)
    }
    ret ok
}

// `mov rd, rm` between general registers (ORR from the zero register); neither may
// be `sp`, which `add_immediate` moves instead.
fn move_register(output: *emit_x64.Buffer, rd: usize, rm: usize) -> err {
    ret instruction_word(output, 0xAA0003E0usize | (rm << 16usize) | rd)
}

// ---------------------------------------------------------------- arithmetic

// `add rd, rn, #imm` for an immediate below 2^24, in one or two words; rd and rn may
// be `sp`.
fn add_immediate(output: *emit_x64.Buffer, rd: usize, rn: usize, imm: usize) -> err {
    if imm >= 16777216usize { ret OutOfRange }
    let high = imm >> 12usize
    let low = imm & 0xFFFusize
    if high != 0usize {
        try instruction_word(output, 0x91400000usize | (high << 10usize) | (rn << 5usize) | rd)
        if low != 0usize { try instruction_word(output, 0x91000000usize | (low << 10usize) | (rd << 5usize) | rd) }
        ret ok
    }
    ret instruction_word(output, 0x91000000usize | (low << 10usize) | (rn << 5usize) | rd)
}

fn sub_immediate(output: *emit_x64.Buffer, rd: usize, rn: usize, imm: usize) -> err {
    if imm >= 16777216usize { ret OutOfRange }
    let high = imm >> 12usize
    let low = imm & 0xFFFusize
    if high != 0usize {
        try instruction_word(output, 0xD1400000usize | (high << 10usize) | (rn << 5usize) | rd)
        if low != 0usize { try instruction_word(output, 0xD1000000usize | (low << 10usize) | (rd << 5usize) | rd) }
        ret ok
    }
    ret instruction_word(output, 0xD1000000usize | (low << 10usize) | (rn << 5usize) | rd)
}

// `cmp rn, #imm` for an immediate below 4096.
fn compare_immediate(output: *emit_x64.Buffer, rn: usize, imm: usize) -> err {
    if imm >= 4096usize { ret OutOfRange }
    ret instruction_word(output, 0xF100001Fusize | (imm << 10usize) | (rn << 5usize))
}

// The three-register data-processing forms, by their opcode word with every
// register field zero.
fn three_register(output: *emit_x64.Buffer, base: usize, rd: usize, rn: usize, rm: usize) -> err {
    ret instruction_word(output, base | (rm << 16usize) | (rn << 5usize) | rd)
}

fn add_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x8B000000usize, rd, rn, rm) }
fn adds_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0xAB000000usize, rd, rn, rm) }
fn sub_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0xCB000000usize, rd, rn, rm) }
fn subs_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0xEB000000usize, rd, rn, rm) }
fn and_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x8A000000usize, rd, rn, rm) }
fn orr_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0xAA000000usize, rd, rn, rm) }
fn eor_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0xCA000000usize, rd, rn, rm) }
fn mul_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9B007C00usize, rd, rn, rm) }
fn smulh_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9B407C00usize, rd, rn, rm) }
fn umulh_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9BC07C00usize, rd, rn, rm) }
fn sdiv_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9AC00C00usize, rd, rn, rm) }
fn udiv_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9AC00800usize, rd, rn, rm) }
fn lslv_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9AC02000usize, rd, rn, rm) }
fn lsrv_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9AC02400usize, rd, rn, rm) }
fn asrv_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize) -> err { ret three_register(output, 0x9AC02800usize, rd, rn, rm) }

// `add rd, rn, rm, lsl #shift`: an index scaled by a power-of-two element size.
fn add_shifted(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize, shift: usize) -> err {
    if shift >= 64usize { ret OutOfRange }
    ret instruction_word(output, 0x8B000000usize | (rm << 16usize) | (shift << 10usize) | (rn << 5usize) | rd)
}

// `orr rd, rn, rm, lsl #shift`: two halves put together.
fn orr_shifted(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize, shift: usize) -> err {
    if shift >= 64usize { ret OutOfRange }
    ret instruction_word(output, 0xAA000000usize | (rm << 16usize) | (shift << 10usize) | (rn << 5usize) | rd)
}

// `madd rd, rn, rm, ra`: ra + rn * rm.
fn madd_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize, ra: usize) -> err {
    ret instruction_word(output, 0x9B000000usize | (rm << 16usize) | (ra << 10usize) | (rn << 5usize) | rd)
}

// `msub rd, rn, rm, ra`: ra - rn * rm, the remainder after a division.
fn msub_register(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize, ra: usize) -> err {
    ret instruction_word(output, 0x9B008000usize | (rm << 16usize) | (ra << 10usize) | (rn << 5usize) | rd)
}

fn negate_register(output: *emit_x64.Buffer, rd: usize, rm: usize) -> err { ret three_register(output, 0xCB000000usize, rd, A64_ZR, rm) }
fn not_register(output: *emit_x64.Buffer, rd: usize, rm: usize) -> err { ret three_register(output, 0xAA200000usize, rd, A64_ZR, rm) }
fn compare_register(output: *emit_x64.Buffer, rn: usize, rm: usize) -> err { ret three_register(output, 0xEB000000usize, A64_ZR, rn, rm) }

// `cmp rn, rm, asr #63`: whether rn is the sign of rm, the signed 64-bit multiply's
// overflow test against the high half.
fn compare_sign_of(output: *emit_x64.Buffer, rn: usize, rm: usize) -> err {
    ret instruction_word(output, 0xEB80FC1Fusize | (rm << 16usize) | (rn << 5usize))
}

// `cset rd, cond`: CSINC rd, xzr, xzr, !cond.
fn set_condition(output: *emit_x64.Buffer, rd: usize, condition: usize) -> err {
    ret instruction_word(output, 0x9A9F07E0usize | (invert_condition(condition) << 12usize) | rd)
}

// `csel rd, rn, rm, cond`.
fn select_condition(output: *emit_x64.Buffer, rd: usize, rn: usize, rm: usize, condition: usize) -> err {
    ret instruction_word(output, 0x9A800000usize | (rm << 16usize) | (condition << 12usize) | (rn << 5usize) | rd)
}

// SBFM/UBFM: the bitfield moves every extension and constant shift is.
fn sbfm(output: *emit_x64.Buffer, rd: usize, rn: usize, immr: usize, imms: usize) -> err {
    ret instruction_word(output, 0x93400000usize | (immr << 16usize) | (imms << 10usize) | (rn << 5usize) | rd)
}

fn ubfm(output: *emit_x64.Buffer, rd: usize, rn: usize, immr: usize, imms: usize) -> err {
    ret instruction_word(output, 0xD3400000usize | (immr << 16usize) | (imms << 10usize) | (rn << 5usize) | rd)
}

// The low `width` bits of rn, sign- or zero-extended into rd; a 64-bit width is a
// move, or nothing.
fn extend_integer(output: *emit_x64.Buffer, rd: usize, rn: usize, width: usize, signed: bool) -> err {
    if width >= 64usize {
        if rd != rn { ret move_register(output, rd, rn) }
        ret ok
    }
    if width == 0usize { ret OutOfRange }
    if signed { ret sbfm(output, rd, rn, 0usize, width - 1usize) }
    ret ubfm(output, rd, rn, 0usize, width - 1usize)
}

fn shift_left_immediate(output: *emit_x64.Buffer, rd: usize, rn: usize, count: usize) -> err {
    if count == 0usize || count >= 64usize { ret OutOfRange }
    ret ubfm(output, rd, rn, 64usize - count, 63usize - count)
}

fn shift_right_immediate(output: *emit_x64.Buffer, rd: usize, rn: usize, count: usize, signed: bool) -> err {
    if count == 0usize || count >= 64usize { ret OutOfRange }
    if signed { ret sbfm(output, rd, rn, count, 63usize) }
    ret ubfm(output, rd, rn, count, 63usize)
}

// ---------------------------------------------------------------- branches

// Each answers where its word is, for `patch_relative`.
fn branch(output: *emit_x64.Buffer) -> (usize, err) {
    let at = output.count
    ret (at, instruction_word(output, 0x14000000usize))
}

fn branch_link(output: *emit_x64.Buffer) -> (usize, err) {
    let at = output.count
    ret (at, instruction_word(output, 0x94000000usize))
}

fn branch_condition(output: *emit_x64.Buffer, condition: usize) -> (usize, err) {
    let at = output.count
    ret (at, instruction_word(output, 0x54000000usize | condition))
}

// CBZ, or CBNZ when `nonzero`, on the whole register.
fn branch_zero(output: *emit_x64.Buffer, rt: usize, nonzero: bool) -> (usize, err) {
    let at = output.count
    var base = 0xB4000000usize
    if nonzero { base = 0xB5000000usize }
    ret (at, instruction_word(output, base | rt))
}

fn branch_register(output: *emit_x64.Buffer, rn: usize) -> err { ret instruction_word(output, 0xD61F0000usize | (rn << 5usize)) }
fn branch_link_register(output: *emit_x64.Buffer, rn: usize) -> err { ret instruction_word(output, 0xD63F0000usize | (rn << 5usize)) }
fn return_link(output: *emit_x64.Buffer) -> err { ret instruction_word(output, 0xD65F03C0usize) }

// `adr rd, label`, within a megabyte.
fn address_near(output: *emit_x64.Buffer, rd: usize) -> (usize, err) {
    let at = output.count
    ret (at, instruction_word(output, 0x10000000usize | rd))
}

// `adrp rd, page; add rd, rd, #pageoff`: anywhere within four gigabytes. The pair is
// patched by `patch_page` once both addresses are known, or by `patch_relative` when
// the code starts on a page boundary.
fn address_far(output: *emit_x64.Buffer, rd: usize) -> (usize, err) {
    let at = output.count
    let page_error = instruction_word(output, 0x90000000usize | rd)
    if page_error != ok { ret (at, page_error) }
    ret (at, instruction_word(output, 0x91000000usize | (rd << 5usize) | rd))
}

// A call through a 64-bit slot the loader fills: `adrp x16, slot; ldr x16, [x16, #lo];
// blr x16`, the pair patched to the slot by `patch_page`.
fn slot_call(output: *emit_x64.Buffer) -> (usize, err) {
    let at = output.count
    let page_error = instruction_word(output, 0x90000010usize)
    if page_error != ok { ret (at, page_error) }
    let load_error = instruction_word(output, 0xF9400210usize)
    if load_error != ok { ret (at, load_error) }
    ret (at, instruction_word(output, 0xD63F0200usize))
}

// Point the branch or address form at `at` to `destination`, both offsets in one
// buffer (an ADRP pair: the buffer starts on a page). The word says which form it is.
fn patch_relative(output: *emit_x64.Buffer, at: usize, destination: usize) -> err {
    ret patch_page(output, at, at, destination)
}

// The same, with the addresses the two will have in the image: `at` is where the
// word is in this buffer, `address` the address it will run at.
fn patch_page(output: *emit_x64.Buffer, at: usize, address: usize, destination: usize) -> err {
    if at + 4usize > output.count { ret OutOfRange }
    let value = read_word(output, at)
    let delta = destination -% address
    // B, BL: imm26 words.
    if (value & 0x7C000000usize) == 0x14000000usize {
        if delta & 3usize != 0usize || !signed_fits(delta, 28usize) { ret OutOfRange }
        ret write_word(output, at, (value & 0xFC000000usize) | ((delta >> 2usize) & 0x3FFFFFFusize))
    }
    // B.cond, CBZ/CBNZ, LDR (literal): imm19 words at bit 5.
    if (value & 0xFF000010usize) == 0x54000000usize || (value & 0x7E000000usize) == 0x34000000usize || (value & 0x3B000000usize) == 0x18000000usize {
        if delta & 3usize != 0usize || !signed_fits(delta, 21usize) { ret OutOfRange }
        ret write_word(output, at, (value & 0xFF00001Fusize) | (((delta >> 2usize) & 0x7FFFFusize) << 5usize))
    }
    // ADR: imm21 bytes.
    if (value & 0x9F000000usize) == 0x10000000usize {
        if !signed_fits(delta, 21usize) { ret OutOfRange }
        ret write_word(output, at, (value & 0x9F00001Fusize) | ((delta & 3usize) << 29usize) | (((delta >> 2usize) & 0x7FFFFusize) << 5usize))
    }
    // ADRP and the ADD after it: the page delta, then the offset in the page -- or the LDR
    // after it, a 64-bit slot's offset in the page in words.
    if (value & 0x9F000000usize) == 0x90000000usize {
        if at + 8usize > output.count { ret OutOfRange }
        let pages = (destination >> 12usize) -% (address >> 12usize)
        if !signed_fits(pages, 21usize) { ret OutOfRange }
        try write_word(output, at, (value & 0x9F00001Fusize) | ((pages & 3usize) << 29usize) | (((pages >> 2usize) & 0x7FFFFusize) << 5usize))
        let low = read_word(output, at + 4usize)
        if (low & 0xFFC00000usize) == 0xF9400000usize {
            if destination & 7usize != 0usize { ret OutOfRange }
            ret write_word(output, at + 4usize, (low & 0xFFC003FFusize) | (((destination & 0xFFFusize) >> 3usize) << 10usize))
        }
        ret write_word(output, at + 4usize, (low & 0xFFC003FFusize) | ((destination & 0xFFFusize) << 10usize))
    }
    ret NotPatchable
}

// ---------------------------------------------------------------- memory

// The unsigned-offset load/store base words by access width in bytes; a signed load
// sign-extends into the whole register.
fn load_base(width: usize, signed: bool) -> usize {
    if width == 1usize {
        if signed { ret 0x39800000usize }
        ret 0x39400000usize
    }
    if width == 2usize {
        if signed { ret 0x79800000usize }
        ret 0x79400000usize
    }
    if width == 4usize {
        if signed { ret 0xB9800000usize }
        ret 0xB9400000usize
    }
    ret 0xF9400000usize
}

fn store_base(width: usize) -> usize {
    if width == 1usize { ret 0x39000000usize }
    if width == 2usize { ret 0x79000000usize }
    if width == 4usize { ret 0xB9000000usize }
    ret 0xF9000000usize
}

// Whether `offset` is an access of `width` bytes' scaled unsigned immediate.
fn scaled_offset(offset: usize, width: usize) -> bool {
    ret offset % width == 0usize && offset / width < 4096usize
}

// `ldr`/`ldrb`/... rt, [rn, #offset] for a scaled unsigned offset, or LDUR/LDURS for
// a byte offset below 256; anything else is the caller's to form in a register.
fn load_offset(output: *emit_x64.Buffer, rt: usize, rn: usize, offset: usize, width: usize, signed: bool) -> err {
    if scaled_offset(offset, width) {
        ret instruction_word(output, load_base(width, signed) | ((offset / width) << 10usize) | (rn << 5usize) | rt)
    }
    if offset < 256usize {
        // The unscaled form: the scaled word with bit 24 clear and imm9 at bit 12.
        ret instruction_word(output, (load_base(width, signed) & 0xFEFFFFFFusize) | (offset << 12usize) | (rn << 5usize) | rt)
    }
    ret OutOfRange
}

fn store_offset(output: *emit_x64.Buffer, rt: usize, rn: usize, offset: usize, width: usize) -> err {
    if scaled_offset(offset, width) {
        ret instruction_word(output, store_base(width) | ((offset / width) << 10usize) | (rn << 5usize) | rt)
    }
    if offset < 256usize {
        ret instruction_word(output, (store_base(width) & 0xFEFFFFFFusize) | (offset << 12usize) | (rn << 5usize) | rt)
    }
    ret OutOfRange
}

// LDUR/STUR rt, [rn, #-offset] for a negative offset down to -256.
fn load_below(output: *emit_x64.Buffer, rt: usize, rn: usize, offset: usize, width: usize, signed: bool) -> err {
    if offset == 0usize || offset > 256usize { ret OutOfRange }
    let imm9 = (0usize -% offset) & 0x1FFusize
    ret instruction_word(output, (load_base(width, signed) & 0xFEFFFFFFusize) | (imm9 << 12usize) | (rn << 5usize) | rt)
}

fn store_below(output: *emit_x64.Buffer, rt: usize, rn: usize, offset: usize, width: usize) -> err {
    if offset == 0usize || offset > 256usize { ret OutOfRange }
    let imm9 = (0usize -% offset) & 0x1FFusize
    ret instruction_word(output, (store_base(width) & 0xFEFFFFFFusize) | (imm9 << 12usize) | (rn << 5usize) | rt)
}

// `ldr x/w/h/b rt, [rn, rm]` with an unscaled register index.
fn load_indexed(output: *emit_x64.Buffer, rt: usize, rn: usize, rm: usize, width: usize, signed: bool) -> err {
    // The register-offset form is the unsigned-offset word with bits 24 and 21 moved
    // and option LSL (011) with S clear.
    let base = (load_base(width, signed) & 0xFEFFFFFFusize) | 0x00206800usize
    ret instruction_word(output, base | (rm << 16usize) | (rn << 5usize) | rt)
}

fn store_indexed(output: *emit_x64.Buffer, rt: usize, rn: usize, rm: usize, width: usize) -> err {
    let base = (store_base(width) & 0xFEFFFFFFusize) | 0x00206800usize
    ret instruction_word(output, base | (rm << 16usize) | (rn << 5usize) | rt)
}

// STP x29, x30, [sp, #-16]! and its pair, the frame record.
fn store_pair_pre(output: *emit_x64.Buffer, rt: usize, rt2: usize, rn: usize, offset_down: usize) -> err {
    if offset_down % 8usize != 0usize || offset_down > 512usize { ret OutOfRange }
    let imm7 = (0usize -% (offset_down / 8usize)) & 0x7Fusize
    ret instruction_word(output, 0xA9800000usize | (imm7 << 15usize) | (rt2 << 10usize) | (rn << 5usize) | rt)
}

fn load_pair_post(output: *emit_x64.Buffer, rt: usize, rt2: usize, rn: usize, offset_up: usize) -> err {
    if offset_up % 8usize != 0usize || offset_up >= 512usize { ret OutOfRange }
    ret instruction_word(output, 0xA8C00000usize | ((offset_up / 8usize) << 15usize) | (rt2 << 10usize) | (rn << 5usize) | rt)
}

// ---------------------------------------------------------------- atomics

// The access size field, bits 31:30, by width in bytes.
fn size_field(width: usize) -> usize {
    if width == 1usize { ret 0usize }
    if width == 2usize { ret 0x40000000usize }
    if width == 4usize { ret 0x80000000usize }
    ret 0xC0000000usize
}

// LDAR/STLR: a load-acquire and a store-release.
fn load_acquire(output: *emit_x64.Buffer, rt: usize, rn: usize, width: usize) -> err { ret instruction_word(output, size_field(width) | 0x08DFFC00usize | (rn << 5usize) | rt) }
fn store_release(output: *emit_x64.Buffer, rt: usize, rn: usize, width: usize) -> err { ret instruction_word(output, size_field(width) | 0x089FFC00usize | (rn << 5usize) | rt) }

// The ARMv8.1 LSE read-modify-writes with acquire and release, by `kind`: 0 SWP,
// 1 LDADD, 3 LDCLR (and-not), 4 LDSET (or), 5 LDEOR, then the signed and unsigned
// min/max. `rs` is the operand and `rt` gets the value that was there.
fn atomic_operation(output: *emit_x64.Buffer, kind: usize, rs: usize, rt: usize, rn: usize, width: usize) -> err {
    var operation = 0x38E00000usize
    if kind == 0usize { operation = 0x38E08000usize }
    if kind == 3usize { operation = 0x38E01000usize }
    if kind == 4usize { operation = 0x38E03000usize }
    if kind == 5usize { operation = 0x38E02000usize }
    if kind == 6usize { operation = 0x38E05000usize }
    if kind == 7usize { operation = 0x38E04000usize }
    if kind == 8usize { operation = 0x38E07000usize }
    if kind == 9usize { operation = 0x38E06000usize }
    ret instruction_word(output, size_field(width) | operation | (rs << 16usize) | (rn << 5usize) | rt)
}

// CASAL rs, rt, [rn]: compares with rs, stores rt, and leaves the old value in rs.
fn compare_swap(output: *emit_x64.Buffer, rs: usize, rt: usize, rn: usize, width: usize) -> err {
    ret instruction_word(output, size_field(width) | 0x08E0FC00usize | (rs << 16usize) | (rn << 5usize) | rt)
}

fn barrier_full(output: *emit_x64.Buffer) -> err { ret instruction_word(output, 0xD5033BBFusize) }

// ---------------------------------------------------------------- system

fn supervisor_call(output: *emit_x64.Buffer) -> err { ret instruction_word(output, 0xD4000001usize) }
fn breakpoint(output: *emit_x64.Buffer, imm16: usize) -> err { ret instruction_word(output, 0xD4200000usize | ((imm16 & 0xFFFFusize) << 5usize)) }
fn no_operation(output: *emit_x64.Buffer) -> err { ret instruction_word(output, 0xD503201Fusize) }

// ---------------------------------------------------------------- floating point

// The scalar type field: double at bit 22.
fn float_type(double: bool) -> usize {
    if double { ret 0x00400000usize }
    ret 0usize
}

// FMOV between a general register and a float register's low bits.
fn move_to_float(output: *emit_x64.Buffer, vd: usize, rn: usize, double: bool) -> err {
    if double { ret instruction_word(output, 0x9E670000usize | (rn << 5usize) | vd) }
    ret instruction_word(output, 0x1E270000usize | (rn << 5usize) | vd)
}

fn move_from_float(output: *emit_x64.Buffer, rd: usize, vn: usize, double: bool) -> err {
    if double { ret instruction_word(output, 0x9E660000usize | (vn << 5usize) | rd) }
    ret instruction_word(output, 0x1E260000usize | (vn << 5usize) | rd)
}

// FADD, FSUB, FMUL, FDIV by `operation` 0..3, as `vector_binary`'s float ranks are.
fn float_binary(output: *emit_x64.Buffer, operation: usize, vd: usize, vn: usize, vm: usize, double: bool) -> err {
    var base = 0x1E202800usize
    if operation == 1usize { base = 0x1E203800usize }
    if operation == 2usize { base = 0x1E200800usize }
    if operation == 3usize { base = 0x1E201800usize }
    ret instruction_word(output, base | float_type(double) | (vm << 16usize) | (vn << 5usize) | vd)
}

fn float_sqrt(output: *emit_x64.Buffer, vd: usize, vn: usize, double: bool) -> err { ret instruction_word(output, 0x1E21C000usize | float_type(double) | (vn << 5usize) | vd) }
fn float_negate(output: *emit_x64.Buffer, vd: usize, vn: usize, double: bool) -> err { ret instruction_word(output, 0x1E214000usize | float_type(double) | (vn << 5usize) | vd) }
fn float_compare(output: *emit_x64.Buffer, vn: usize, vm: usize, double: bool) -> err { ret instruction_word(output, 0x1E202000usize | float_type(double) | (vm << 16usize) | (vn << 5usize)) }

// FMADD vd, vn, vm, va: vn * vm + va, rounded once.
fn float_fused(output: *emit_x64.Buffer, vd: usize, vn: usize, vm: usize, va: usize, double: bool) -> err {
    ret instruction_word(output, 0x1F000000usize | float_type(double) | (vm << 16usize) | (va << 10usize) | (vn << 5usize) | vd)
}

// FCVT between the two widths: to double from single, or to single from double.
fn float_widen(output: *emit_x64.Buffer, vd: usize, vn: usize) -> err { ret instruction_word(output, 0x1E22C000usize | (vn << 5usize) | vd) }
fn float_narrow(output: *emit_x64.Buffer, vd: usize, vn: usize) -> err { ret instruction_word(output, 0x1E624000usize | (vn << 5usize) | vd) }

// SCVTF/UCVTF from a whole 64-bit register.
fn float_from_integer(output: *emit_x64.Buffer, vd: usize, rn: usize, unsigned: bool, double: bool) -> err {
    var base = 0x9E220000usize
    if unsigned { base = 0x9E230000usize }
    ret instruction_word(output, base | float_type(double) | (rn << 5usize) | vd)
}

// FCVTZS/FCVTZU into a whole 64-bit register: toward zero, saturating, NaN to zero.
fn integer_from_float(output: *emit_x64.Buffer, rd: usize, vn: usize, unsigned: bool, double: bool) -> err {
    var base = 0x9E380000usize
    if unsigned { base = 0x9E390000usize }
    ret instruction_word(output, base | float_type(double) | (vn << 5usize) | rd)
}

// ---------------------------------------------------------------- Advanced SIMD

// LDR/STR of a vector register's low `bytes` (16, 8, 4 or 2) at [rn]; a narrower load
// clears the rest of the register.
fn vector_base(bytes: usize, store: bool) -> usize {
    var base = 0x3DC00000usize
    if bytes == 8usize { base = 0xFD400000usize }
    if bytes == 4usize { base = 0xBD400000usize }
    if bytes == 2usize { base = 0x7D400000usize }
    if store { ret base & 0xFFBFFFFFusize }
    ret base
}

fn vector_load(output: *emit_x64.Buffer, vt: usize, rn: usize, bytes: usize) -> err {
    if bytes != 16usize && bytes != 8usize && bytes != 4usize && bytes != 2usize { ret OutOfRange }
    ret instruction_word(output, vector_base(bytes, false) | (rn << 5usize) | vt)
}

fn vector_store(output: *emit_x64.Buffer, vt: usize, rn: usize, bytes: usize) -> err {
    if bytes != 16usize && bytes != 8usize && bytes != 4usize && bytes != 2usize { ret OutOfRange }
    ret instruction_word(output, vector_base(bytes, true) | (rn << 5usize) | vt)
}

// The 128-bit three-register forms by `operation`, over lanes of `size` (0 bytes, 1
// halfwords, 2 words, 3 doublewords): 0 ADD, 1 SUB, 2 MUL, 3 USHL, 4 SSHL; then the
// bitwise 5 AND, 6 ORR, 7 EOR and 8 BIF, whose size field is their own; then, `size`
// 2 for f32 lanes and 3 for f64, 9 FADD, 10 FSUB, 11 FMUL, 12 FDIV and 13 FCMEQ.
fn vector_three(output: *emit_x64.Buffer, operation: usize, size: usize, vd: usize, vn: usize, vm: usize) -> err {
    var word = 0usize
    if operation == 0usize { word = 0x4E208400usize | (size << 22usize) }
    if operation == 1usize { word = 0x6E208400usize | (size << 22usize) }
    if operation == 2usize {
        if size == 3usize { ret OutOfRange }
        word = 0x4E209C00usize | (size << 22usize)
    }
    if operation == 3usize { word = 0x6E204400usize | (size << 22usize) }
    if operation == 4usize { word = 0x4E204400usize | (size << 22usize) }
    if operation == 5usize { word = 0x4E201C00usize }
    if operation == 6usize { word = 0x4EA01C00usize }
    if operation == 7usize { word = 0x6E201C00usize }
    if operation == 8usize { word = 0x6EE01C00usize }
    var double = 0usize
    if size == 3usize { double = 0x00400000usize }
    if operation == 9usize { word = 0x4E20D400usize | double }
    if operation == 10usize { word = 0x4EA0D400usize | double }
    if operation == 11usize { word = 0x6E20DC00usize | double }
    if operation == 12usize { word = 0x6E20FC00usize | double }
    if operation == 13usize { word = 0x4E20E400usize | double }
    if word == 0usize { ret OutOfRange }
    ret instruction_word(output, word | (vm << 16usize) | (vn << 5usize) | vd)
}

// NOT on all sixteen bytes, and NEG on lanes of `size`.
fn vector_not(output: *emit_x64.Buffer, vd: usize, vn: usize) -> err { ret instruction_word(output, 0x6E205800usize | (vn << 5usize) | vd) }
fn vector_negate(output: *emit_x64.Buffer, size: usize, vd: usize, vn: usize) -> err { ret instruction_word(output, 0x6E20B800usize | (size << 22usize) | (vn << 5usize) | vd) }

// DUP: a general register's low lane into every lane of `size`.
fn vector_duplicate(output: *emit_x64.Buffer, size: usize, vd: usize, rn: usize) -> err {
    ret instruction_word(output, 0x4E000C00usize | ((1usize << size) << 16usize) | (rn << 5usize) | vd)
}

// MOVI vd.16B, #imm8: the byte in every lane.
fn vector_bytes(output: *emit_x64.Buffer, vd: usize, imm8: usize) -> err {
    ret instruction_word(output, 0x4F00E400usize | (((imm8 >> 5usize) & 7usize) << 16usize) | ((imm8 & 31usize) << 5usize) | vd)
}

// SHL (kind 0), USHR (1) and SSHR (2) by an immediate over lanes of `size`; a right shift
// counts 1 to the lane's width, a left one 0 to one less.
fn vector_shift_immediate(output: *emit_x64.Buffer, kind: usize, size: usize, vd: usize, vn: usize, count: usize) -> err {
    let width = 8usize << size
    if kind == 0usize {
        if count >= width { ret OutOfRange }
        ret instruction_word(output, 0x4F005400usize | ((width + count) << 16usize) | (vn << 5usize) | vd)
    }
    if count == 0usize || count > width { ret OutOfRange }
    var base = 0x6F000400usize
    if kind == 2usize { base = 0x4F000400usize }
    ret instruction_word(output, base | ((width * 2usize - count) << 16usize) | (vn << 5usize) | vd)
}

// ---------------------------------------------------------------- the sweep

// The grid `scripts/a64_encoding_sweep.py` writes as assembly text -- every form over
// registers, immediates, widths, conditions and vector arrangements, 63,610 instructions --
// encoded here in the same order and folded into one FNV-1a hash, which GNU as gave for
// the text. The hash is a literal in `sweep`: the bootstrap refuses a constant past i64.

fn sweep_fold(output: *emit_x64.Buffer, hash: *usize) {
    var at = 0usize
    while at + 4usize <= output.count {
        *hash = (*hash ^ read_word(output, at)) *% 1099511628211usize
        at += 4usize
    }
    output.count = 0usize
}

fn sweep_three_form(output: *emit_x64.Buffer, form: usize, rd: usize, rn: usize, rm: usize) -> err {
    if form == 0usize { ret add_register(output, rd, rn, rm) }
    if form == 1usize { ret adds_register(output, rd, rn, rm) }
    if form == 2usize { ret sub_register(output, rd, rn, rm) }
    if form == 3usize { ret subs_register(output, rd, rn, rm) }
    if form == 4usize { ret and_register(output, rd, rn, rm) }
    if form == 5usize { ret orr_register(output, rd, rn, rm) }
    if form == 6usize { ret eor_register(output, rd, rn, rm) }
    if form == 7usize { ret mul_register(output, rd, rn, rm) }
    if form == 8usize { ret smulh_register(output, rd, rn, rm) }
    if form == 9usize { ret umulh_register(output, rd, rn, rm) }
    if form == 10usize { ret sdiv_register(output, rd, rn, rm) }
    if form == 11usize { ret udiv_register(output, rd, rn, rm) }
    if form == 12usize { ret lslv_register(output, rd, rn, rm) }
    if form == 13usize { ret lsrv_register(output, rd, rn, rm) }
    ret asrv_register(output, rd, rn, rm)
}

fn sweep_registers(output: *emit_x64.Buffer, hash: *usize, r: []const usize, r4: []const usize) -> err {
    var form = 0usize
    while form < 15usize {
        var d = 0usize
        while d < r.len {
            var n = 0usize
            while n < r.len {
                var m = 0usize
                while m < r.len {
                    try sweep_three_form(output, form, r[d], r[n], r[m])
                    sweep_fold(output, hash)
                    m += 1usize
                }
                n += 1usize
            }
            d += 1usize
        }
        form += 1usize
    }
    var subtract = 0usize
    while subtract < 2usize {
        var d4 = 0usize
        while d4 < r4.len {
            var n4 = 0usize
            while n4 < r4.len {
                var m4 = 0usize
                while m4 < r4.len {
                    var a4 = 0usize
                    while a4 < r4.len {
                        if subtract == 0usize { try madd_register(output, r4[d4], r4[n4], r4[m4], r4[a4]) } else { try msub_register(output, r4[d4], r4[n4], r4[m4], r4[a4]) }
                        sweep_fold(output, hash)
                        a4 += 1usize
                    }
                    m4 += 1usize
                }
                n4 += 1usize
            }
            d4 += 1usize
        }
        subtract += 1usize
    }
    var d2 = 0usize
    while d2 < r.len {
        var m2 = 0usize
        while m2 < r.len {
            try negate_register(output, r[d2], r[m2])
            try not_register(output, r[d2], r[m2])
            try compare_register(output, r[d2], r[m2])
            try compare_sign_of(output, r[d2], r[m2])
            try move_register(output, r[d2], r[m2])
            sweep_fold(output, hash)
            m2 += 1usize
        }
        d2 += 1usize
    }
    ret ok
}

fn sweep_conditions(output: *emit_x64.Buffer, hash: *usize, r: []const usize, r4: []const usize) -> err {
    var d = 0usize
    while d < r.len {
        var condition = 0usize
        while condition < 14usize {
            try set_condition(output, r[d], condition)
            sweep_fold(output, hash)
            condition += 1usize
        }
        d += 1usize
    }
    var d4 = 0usize
    while d4 < r4.len {
        var n4 = 0usize
        while n4 < r4.len {
            var m4 = 0usize
            while m4 < r4.len {
                var select = 0usize
                while select < 14usize {
                    try select_condition(output, r4[d4], r4[n4], r4[m4], select)
                    sweep_fold(output, hash)
                    select += 1usize
                }
                m4 += 1usize
            }
            n4 += 1usize
        }
        d4 += 1usize
    }
    let counts = [_]usize{ 1usize, 7usize, 31usize, 32usize, 63usize }
    var bd = 0usize
    while bd < r.len {
        var bn = 0usize
        while bn < r.len {
            var width = 8usize
            while width <= 32usize {
                try sbfm(output, r[bd], r[bn], 0usize, width - 1usize)
                try ubfm(output, r[bd], r[bn], 0usize, width - 1usize)
                width = width * 2usize
            }
            var count_at = 0usize
            while count_at < counts.len {
                try shift_left_immediate(output, r[bd], r[bn], counts[count_at])
                try shift_right_immediate(output, r[bd], r[bn], counts[count_at], false)
                try shift_right_immediate(output, r[bd], r[bn], counts[count_at], true)
                count_at += 1usize
            }
            sweep_fold(output, hash)
            bn += 1usize
        }
        bd += 1usize
    }
    ret ok
}

fn sweep_immediates(output: *emit_x64.Buffer, hash: *usize, r: []const usize, r31: []const usize) -> err {
    let immediates = [_]usize{ 0usize, 1usize, 2048usize, 4095usize, 4096usize, 0x5000usize, 0x123456usize, 0xFFF000usize }
    var d = 0usize
    while d < r31.len {
        var n = 0usize
        while n < r31.len {
            var at = 0usize
            while at < immediates.len {
                try add_immediate(output, r31[d], r31[n], immediates[at])
                try sub_immediate(output, r31[d], r31[n], immediates[at])
                sweep_fold(output, hash)
                at += 1usize
            }
            n += 1usize
        }
        d += 1usize
    }
    let compared = [_]usize{ 0usize, 1usize, 4095usize }
    var cn = 0usize
    while cn < r31.len {
        var ci = 0usize
        while ci < compared.len {
            try compare_immediate(output, r31[cn], compared[ci])
            ci += 1usize
        }
        sweep_fold(output, hash)
        cn += 1usize
    }
    let halves = [_]usize{ 0usize, 1usize, 0xFFFFusize, 0x1234usize }
    var md = 0usize
    while md < r.len {
        var hi = 0usize
        while hi < halves.len {
            var halfword = 0usize
            while halfword < 4usize {
                try movz(output, r[md], halves[hi], halfword)
                try movk(output, r[md], halves[hi], halfword)
                try movn(output, r[md], halves[hi], halfword)
                halfword += 1usize
            }
            hi += 1usize
        }
        sweep_fold(output, hash)
        md += 1usize
    }
    ret ok
}

fn sweep_memory(output: *emit_x64.Buffer, hash: *usize, r4: []const usize, r4sp: []const usize) -> err {
    var width = 1usize
    while width <= 8usize {
        let offsets = [_]usize{ 0usize, width, 8usize * width, 4095usize * width, 3usize, 255usize }
        var signed_at = 0usize
        while signed_at < 2usize {
            if !(width == 8usize && signed_at == 1usize) {
                var t = 0usize
                while t < r4.len {
                    var n = 0usize
                    while n < r4sp.len {
                        var o = 0usize
                        while o < offsets.len {
                            try load_offset(output, r4[t], r4sp[n], offsets[o], width, signed_at == 1usize)
                            o += 1usize
                        }
                        sweep_fold(output, hash)
                        n += 1usize
                    }
                    t += 1usize
                }
            }
            signed_at += 1usize
        }
        width = width * 2usize
    }
    var store_width = 1usize
    while store_width <= 8usize {
        let store_offsets = [_]usize{ 0usize, store_width, 8usize * store_width, 4095usize * store_width, 3usize, 255usize }
        var st = 0usize
        while st < r4.len {
            var sn = 0usize
            while sn < r4sp.len {
                var so = 0usize
                while so < store_offsets.len {
                    try store_offset(output, r4[st], r4sp[sn], store_offsets[so], store_width)
                    so += 1usize
                }
                sweep_fold(output, hash)
                sn += 1usize
            }
            st += 1usize
        }
        store_width = store_width * 2usize
    }
    let bases = [_]usize{ 0usize, 9usize, 17usize, 30usize, 29usize, 31usize }
    let below = [_]usize{ 8usize, 16usize, 256usize }
    var bt = 0usize
    while bt < r4.len {
        var bn = 0usize
        while bn < bases.len {
            var bo = 0usize
            while bo < below.len {
                try load_below(output, r4[bt], bases[bn], below[bo], 8usize, false)
                try store_below(output, r4[bt], bases[bn], below[bo], 8usize)
                bo += 1usize
            }
            sweep_fold(output, hash)
            bn += 1usize
        }
        bt += 1usize
    }
    ret ok
}

fn sweep_indexed(output: *emit_x64.Buffer, hash: *usize, r4: []const usize) -> err {
    var width = 1usize
    while width <= 8usize {
        var signed_at = 0usize
        while signed_at < 2usize {
            if !(width == 8usize && signed_at == 1usize) {
                var t = 0usize
                while t < r4.len {
                    var n = 0usize
                    while n < r4.len {
                        var m = 0usize
                        while m < r4.len {
                            try load_indexed(output, r4[t], r4[n], r4[m], width, signed_at == 1usize)
                            m += 1usize
                        }
                        n += 1usize
                    }
                    t += 1usize
                }
                sweep_fold(output, hash)
            }
            signed_at += 1usize
        }
        var st = 0usize
        while st < r4.len {
            var sn = 0usize
            while sn < r4.len {
                var sm = 0usize
                while sm < r4.len {
                    try store_indexed(output, r4[st], r4[sn], r4[sm], width)
                    sm += 1usize
                }
                sn += 1usize
            }
            st += 1usize
        }
        sweep_fold(output, hash)
        width = width * 2usize
    }
    let pair_bases = [_]usize{ 0usize, 9usize, 31usize }
    let pair_offsets = [_]usize{ 16usize, 32usize, 496usize }
    var pt = 0usize
    while pt < r4.len {
        var pt2 = 0usize
        while pt2 < r4.len {
            var pn = 0usize
            while pn < pair_bases.len {
                var po = 0usize
                while po < pair_offsets.len {
                    try store_pair_pre(output, r4[pt], r4[pt2], pair_bases[pn], pair_offsets[po])
                    try load_pair_post(output, r4[pt], r4[pt2], pair_bases[pn], pair_offsets[po])
                    po += 1usize
                }
                pn += 1usize
            }
            sweep_fold(output, hash)
            pt2 += 1usize
        }
        pt += 1usize
    }
    ret ok
}

fn sweep_atomics(output: *emit_x64.Buffer, hash: *usize, r: []const usize, r4: []const usize) -> err {
    var width = 1usize
    while width <= 8usize {
        var t = 0usize
        while t < r4.len {
            var n = 0usize
            while n < r4.len {
                try load_acquire(output, r4[t], r4[n], width)
                try store_release(output, r4[t], r4[n], width)
                n += 1usize
            }
            t += 1usize
        }
        sweep_fold(output, hash)
        width = width * 2usize
    }
    let kinds = [_]usize{ 0usize, 1usize, 3usize, 4usize, 5usize, 6usize, 7usize, 8usize, 9usize }
    var k = 0usize
    while k < kinds.len {
        var kw = 1usize
        while kw <= 8usize {
            var s = 0usize
            while s < r4.len {
                var kt = 0usize
                while kt < r4.len {
                    var kn = 0usize
                    while kn < r4.len {
                        try atomic_operation(output, kinds[k], r4[s], r4[kt], r4[kn], kw)
                        kn += 1usize
                    }
                    kt += 1usize
                }
                s += 1usize
            }
            sweep_fold(output, hash)
            kw = kw * 2usize
        }
        k += 1usize
    }
    var cw = 1usize
    while cw <= 8usize {
        var cs = 0usize
        while cs < r4.len {
            var ct = 0usize
            while ct < r4.len {
                var cn = 0usize
                while cn < r4.len {
                    try compare_swap(output, r4[cs], r4[ct], r4[cn], cw)
                    cn += 1usize
                }
                ct += 1usize
            }
            cs += 1usize
        }
        sweep_fold(output, hash)
        cw = cw * 2usize
    }
    try barrier_full(output)
    try supervisor_call(output)
    try breakpoint(output, 0usize)
    try breakpoint(output, 1usize)
    try breakpoint(output, 0xFFFFusize)
    try no_operation(output)
    sweep_fold(output, hash)
    var b = 0usize
    while b < r.len {
        try branch_register(output, r[b])
        try branch_link_register(output, r[b])
        sweep_fold(output, hash)
        b += 1usize
    }
    try return_link(output)
    sweep_fold(output, hash)
    ret ok
}

fn sweep_floats(output: *emit_x64.Buffer, hash: *usize, r: []const usize, v: []const usize) -> err {
    var mv = 0usize
    while mv < v.len {
        var mr = 0usize
        while mr < r.len {
            try move_to_float(output, v[mv], r[mr], true)
            try move_to_float(output, v[mv], r[mr], false)
            try move_from_float(output, r[mr], v[mv], true)
            try move_from_float(output, r[mr], v[mv], false)
            sweep_fold(output, hash)
            mr += 1usize
        }
        mv += 1usize
    }
    var operation = 0usize
    while operation < 4usize {
        var precision = 0usize
        while precision < 2usize {
            var d = 0usize
            while d < v.len {
                var n = 0usize
                while n < v.len {
                    var m = 0usize
                    while m < v.len {
                        try float_binary(output, operation, v[d], v[n], v[m], precision == 0usize)
                        m += 1usize
                    }
                    n += 1usize
                }
                d += 1usize
            }
            sweep_fold(output, hash)
            precision += 1usize
        }
        operation += 1usize
    }
    var unary = 0usize
    while unary < 2usize {
        var ud = 0usize
        while ud < v.len {
            var un = 0usize
            while un < v.len {
                try float_sqrt(output, v[ud], v[un], unary == 0usize)
                try float_negate(output, v[ud], v[un], unary == 0usize)
                try float_compare(output, v[ud], v[un], unary == 0usize)
                un += 1usize
            }
            ud += 1usize
        }
        sweep_fold(output, hash)
        unary += 1usize
    }
    ret sweep_fused(output, hash, r, v)
}

fn sweep_fused(output: *emit_x64.Buffer, hash: *usize, r: []const usize, v: []const usize) -> err {
    var precision = 0usize
    while precision < 2usize {
        var d = 0usize
        while d < v.len {
            var n = 0usize
            while n < v.len {
                var m = 0usize
                while m < v.len {
                    var a = 0usize
                    while a < v.len {
                        try float_fused(output, v[d], v[n], v[m], v[a], precision == 0usize)
                        a += 1usize
                    }
                    m += 1usize
                }
                sweep_fold(output, hash)
                n += 1usize
            }
            d += 1usize
        }
        precision += 1usize
    }
    var cd = 0usize
    while cd < v.len {
        var cn = 0usize
        while cn < v.len {
            try float_widen(output, v[cd], v[cn])
            try float_narrow(output, v[cd], v[cn])
            cn += 1usize
        }
        sweep_fold(output, hash)
        cd += 1usize
    }
    var convert = 0usize
    while convert < 2usize {
        var iv = 0usize
        while iv < v.len {
            var ir = 0usize
            while ir < r.len {
                try float_from_integer(output, v[iv], r[ir], false, convert == 0usize)
                try float_from_integer(output, v[iv], r[ir], true, convert == 0usize)
                try integer_from_float(output, r[ir], v[iv], false, convert == 0usize)
                try integer_from_float(output, r[ir], v[iv], true, convert == 0usize)
                sweep_fold(output, hash)
                ir += 1usize
            }
            iv += 1usize
        }
        convert += 1usize
    }
    ret ok
}

fn sweep_shifted(output: *emit_x64.Buffer, hash: *usize, r4: []const usize) -> err {
    let shifts = [_]usize{ 0usize, 1usize, 3usize, 4usize, 63usize }
    var d = 0usize
    while d < r4.len {
        var n = 0usize
        while n < r4.len {
            var m = 0usize
            while m < r4.len {
                var s = 0usize
                while s < shifts.len {
                    try add_shifted(output, r4[d], r4[n], r4[m], shifts[s])
                    s += 1usize
                }
                sweep_fold(output, hash)
                m += 1usize
            }
            n += 1usize
        }
        d += 1usize
    }
    let orr_shifts = [_]usize{ 0usize, 1usize, 32usize, 63usize }
    var od = 0usize
    while od < r4.len {
        var on = 0usize
        while on < r4.len {
            var om = 0usize
            while om < r4.len {
                var os = 0usize
                while os < orr_shifts.len {
                    try orr_shifted(output, r4[od], r4[on], r4[om], orr_shifts[os])
                    os += 1usize
                }
                sweep_fold(output, hash)
                om += 1usize
            }
            on += 1usize
        }
        od += 1usize
    }
    ret ok
}

fn sweep_vectors(output: *emit_x64.Buffer, hash: *usize, r: []const usize, r4sp: []const usize, v: []const usize) -> err {
    var bytes = 16usize
    while bytes >= 2usize {
        var t = 0usize
        while t < v.len {
            var n = 0usize
            while n < r4sp.len {
                try vector_load(output, v[t], r4sp[n], bytes)
                try vector_store(output, v[t], r4sp[n], bytes)
                n += 1usize
            }
            sweep_fold(output, hash)
            t += 1usize
        }
        bytes = bytes / 2usize
    }
    var operation = 0usize
    while operation < 14usize {
        var size = 0usize
        var last = 3usize
        if operation == 2usize { last = 2usize }
        if operation >= 5usize && operation <= 8usize { last = 0usize }
        if operation >= 9usize { size = 2usize }
        while size <= last {
            var d = 0usize
            while d < v.len {
                var n3 = 0usize
                while n3 < v.len {
                    var m = 0usize
                    while m < v.len {
                        try vector_three(output, operation, size, v[d], v[n3], v[m])
                        m += 1usize
                    }
                    n3 += 1usize
                }
                sweep_fold(output, hash)
                d += 1usize
            }
            size += 1usize
        }
        operation += 1usize
    }
    var nd = 0usize
    while nd < v.len {
        var nn = 0usize
        while nn < v.len {
            try vector_not(output, v[nd], v[nn])
            var negate_size = 0usize
            while negate_size < 4usize {
                try vector_negate(output, negate_size, v[nd], v[nn])
                negate_size += 1usize
            }
            nn += 1usize
        }
        sweep_fold(output, hash)
        nd += 1usize
    }
    var dup_size = 0usize
    while dup_size < 4usize {
        var dd = 0usize
        while dd < v.len {
            var dr = 0usize
            while dr < r.len {
                try vector_duplicate(output, dup_size, v[dd], r[dr])
                dr += 1usize
            }
            sweep_fold(output, hash)
            dd += 1usize
        }
        dup_size += 1usize
    }
    let bytes_values = [_]usize{ 0usize, 1usize, 0xFFusize, 0x5Ausize }
    var md = 0usize
    while md < v.len {
        var mi = 0usize
        while mi < bytes_values.len {
            try vector_bytes(output, v[md], bytes_values[mi])
            mi += 1usize
        }
        sweep_fold(output, hash)
        md += 1usize
    }
    var shift_size = 0usize
    while shift_size < 4usize {
        let width = 8usize << shift_size
        let left_counts = [_]usize{ 0usize, 1usize, width - 1usize }
        let right_counts = [_]usize{ 1usize, width / 2usize, width }
        var sd = 0usize
        while sd < v.len {
            var sn = 0usize
            while sn < v.len {
                var lc = 0usize
                while lc < left_counts.len {
                    try vector_shift_immediate(output, 0usize, shift_size, v[sd], v[sn], left_counts[lc])
                    lc += 1usize
                }
                var rc = 0usize
                while rc < right_counts.len {
                    try vector_shift_immediate(output, 1usize, shift_size, v[sd], v[sn], right_counts[rc])
                    try vector_shift_immediate(output, 2usize, shift_size, v[sd], v[sn], right_counts[rc])
                    rc += 1usize
                }
                sweep_fold(output, hash)
                sn += 1usize
            }
            sd += 1usize
        }
        shift_size += 1usize
    }
    ret ok
}

fn sweep() -> err {
    var storage: [1024]u8 = zero
    var output: emit_x64.Buffer = zero
    try emit_x64.init(&output, storage[..])
    var hash = 14695981039346656037usize
    let r = [_]usize{ 0usize, 1usize, 2usize, 7usize, 8usize, 15usize, 16usize, 17usize, 18usize, 19usize, 28usize, 29usize, 30usize }
    let r31 = [_]usize{ 0usize, 1usize, 2usize, 7usize, 8usize, 15usize, 16usize, 17usize, 18usize, 19usize, 28usize, 29usize, 30usize, 31usize }
    let r4 = [_]usize{ 0usize, 9usize, 17usize, 30usize }
    let r4sp = [_]usize{ 0usize, 9usize, 17usize, 30usize, 31usize }
    let v = [_]usize{ 0usize, 1usize, 7usize, 16usize, 17usize, 31usize }
    try sweep_registers(&output, &hash, r[..], r4[..])
    try sweep_conditions(&output, &hash, r[..], r4[..])
    try sweep_immediates(&output, &hash, r[..], r31[..])
    try sweep_memory(&output, &hash, r4[..], r4sp[..])
    try sweep_indexed(&output, &hash, r4[..])
    try sweep_atomics(&output, &hash, r[..], r4[..])
    try sweep_floats(&output, &hash, r[..], v[..])
    try sweep_shifted(&output, &hash, r4[..])
    try sweep_vectors(&output, &hash, r[..], r4sp[..], v[..])
    if hash != 15813672905048176038usize { ret OutOfRange }
    ret ok
}

// ---------------------------------------------------------------- self-test

// Every encoder against the word GNU as (binutils 2.42, -march=armv8.2-a) assembles
// for the same text; the expected words are that assembler's output, not hand
// encodings. The last three check the patcher: a branch two words on, a conditional
// branch one word back, and the largest scaled byte offset.
fn self_test() -> err {
    var storage: [512]u8 = zero
    var output: emit_x64.Buffer = zero
    try emit_x64.init(&output, storage[..])
    try movz(&output, 0usize, 0x1234usize, 0usize)
    try movz(&output, 5usize, 0xFFFFusize, 3usize)
    try movk(&output, 9usize, 0xBEEFusize, 1usize)
    try movn(&output, 2usize, 0usize, 0usize)
    try move_constant(&output, 3usize, 0x0102030405060708usize)
    try move_constant(&output, 4usize, 0xFFFFFFFFFFFFFFFEusize)
    try move_register(&output, 1usize, 19usize)
    try add_immediate(&output, A64_SP, A64_SP, 32usize)
    try add_immediate(&output, 0usize, 29usize, 0x12345usize)
    try sub_immediate(&output, A64_SP, A64_SP, 4096usize)
    try compare_immediate(&output, 7usize, 42usize)
    try add_register(&output, 1usize, 2usize, 3usize)
    try adds_register(&output, 1usize, 2usize, 3usize)
    try sub_register(&output, 1usize, 2usize, 3usize)
    try subs_register(&output, 1usize, 2usize, 3usize)
    try and_register(&output, 1usize, 2usize, 3usize)
    try orr_register(&output, 1usize, 2usize, 3usize)
    try eor_register(&output, 1usize, 2usize, 3usize)
    try mul_register(&output, 1usize, 2usize, 3usize)
    try smulh_register(&output, 1usize, 2usize, 3usize)
    try umulh_register(&output, 1usize, 2usize, 3usize)
    try sdiv_register(&output, 1usize, 2usize, 3usize)
    try udiv_register(&output, 1usize, 2usize, 3usize)
    try lslv_register(&output, 1usize, 2usize, 3usize)
    try lsrv_register(&output, 1usize, 2usize, 3usize)
    try asrv_register(&output, 1usize, 2usize, 3usize)
    try msub_register(&output, 1usize, 2usize, 3usize, 4usize)
    try negate_register(&output, 5usize, 6usize)
    try not_register(&output, 5usize, 6usize)
    try compare_register(&output, 5usize, 6usize)
    try compare_sign_of(&output, 8usize, 9usize)
    try set_condition(&output, 0usize, A64_LT)
    try select_condition(&output, 0usize, 1usize, 2usize, A64_NE)
    try extend_integer(&output, 1usize, 2usize, 8usize, true)
    try extend_integer(&output, 1usize, 2usize, 16usize, false)
    try extend_integer(&output, 1usize, 2usize, 32usize, true)
    try shift_left_immediate(&output, 3usize, 4usize, 5usize)
    try shift_right_immediate(&output, 3usize, 4usize, 7usize, false)
    try shift_right_immediate(&output, 3usize, 4usize, 7usize, true)
    let (b_at, b_error) = branch(&output)
    if b_error != ok { ret b_error }
    let (bl_at, bl_error) = branch_link(&output)
    if bl_error != ok { ret bl_error }
    let (beq_at, beq_error) = branch_condition(&output, A64_EQ)
    if beq_error != ok { ret beq_error }
    let (cbz_at, cbz_error) = branch_zero(&output, 3usize, false)
    if cbz_error != ok { ret cbz_error }
    let (cbnz_at, cbnz_error) = branch_zero(&output, 3usize, true)
    if cbnz_error != ok { ret cbnz_error }
    try branch_register(&output, 16usize)
    try branch_link_register(&output, 17usize)
    try return_link(&output)
    let (adr_at, adr_error) = address_near(&output, 0usize)
    if adr_error != ok { ret adr_error }
    let (adrp_at, adrp_error) = address_far(&output, 1usize)
    if adrp_error != ok { ret adrp_error }
    try load_offset(&output, 0usize, 1usize, 16usize, 8usize, false)
    try load_offset(&output, 0usize, 1usize, 16usize, 4usize, false)
    try load_offset(&output, 0usize, 1usize, 16usize, 2usize, true)
    try load_offset(&output, 0usize, 1usize, 3usize, 1usize, true)
    try load_offset(&output, 0usize, 1usize, 8usize, 4usize, true)
    try load_offset(&output, 0usize, 1usize, 5usize, 8usize, false)
    try store_offset(&output, 0usize, A64_SP, 8usize, 8usize)
    try store_offset(&output, 0usize, 1usize, 3usize, 1usize)
    try store_offset(&output, 0usize, 1usize, 3usize, 4usize)
    try load_below(&output, 0usize, 29usize, 16usize, 8usize, false)
    try store_below(&output, 0usize, 29usize, 24usize, 8usize)
    try load_indexed(&output, 0usize, 1usize, 2usize, 8usize, false)
    try load_indexed(&output, 0usize, 1usize, 2usize, 1usize, false)
    try store_indexed(&output, 0usize, 1usize, 2usize, 4usize)
    try store_pair_pre(&output, 29usize, 30usize, A64_SP, 16usize)
    try load_pair_post(&output, 29usize, 30usize, A64_SP, 16usize)
    try load_acquire(&output, 0usize, 1usize, 8usize)
    try load_acquire(&output, 0usize, 1usize, 4usize)
    try store_release(&output, 0usize, 1usize, 1usize)
    try atomic_operation(&output, 1usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 0usize, 2usize, 0usize, 1usize, 4usize)
    try atomic_operation(&output, 3usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 4usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 5usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 6usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 7usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 8usize, 2usize, 0usize, 1usize, 8usize)
    try atomic_operation(&output, 9usize, 2usize, 0usize, 1usize, 8usize)
    try compare_swap(&output, 2usize, 3usize, 1usize, 8usize)
    try compare_swap(&output, 2usize, 3usize, 1usize, 4usize)
    try barrier_full(&output)
    try supervisor_call(&output)
    try breakpoint(&output, 1000usize)
    try no_operation(&output)
    try move_to_float(&output, 16usize, 9usize, true)
    try move_to_float(&output, 17usize, 9usize, false)
    try move_from_float(&output, 9usize, 16usize, true)
    try move_from_float(&output, 9usize, 16usize, false)
    try float_binary(&output, 0usize, 0usize, 1usize, 2usize, true)
    try float_binary(&output, 1usize, 0usize, 1usize, 2usize, true)
    try float_binary(&output, 2usize, 0usize, 1usize, 2usize, true)
    try float_binary(&output, 3usize, 0usize, 1usize, 2usize, true)
    try float_binary(&output, 0usize, 0usize, 1usize, 2usize, false)
    try float_sqrt(&output, 0usize, 1usize, true)
    try float_negate(&output, 0usize, 1usize, false)
    try float_compare(&output, 0usize, 1usize, true)
    try float_fused(&output, 0usize, 1usize, 2usize, 3usize, true)
    try float_widen(&output, 0usize, 1usize)
    try float_narrow(&output, 0usize, 1usize)
    try float_from_integer(&output, 0usize, 1usize, false, true)
    try float_from_integer(&output, 0usize, 1usize, true, false)
    try integer_from_float(&output, 0usize, 1usize, false, true)
    try integer_from_float(&output, 0usize, 1usize, true, false)
    let (forward_at, forward_error) = branch(&output)
    if forward_error != ok { ret forward_error }
    try patch_relative(&output, forward_at, forward_at + 8usize)
    let (back_at, back_error) = branch_condition(&output, A64_EQ)
    if back_error != ok { ret back_error }
    try patch_relative(&output, back_at, back_at - 4usize)
    try load_offset(&output, 9usize, 1usize, 4095usize, 1usize, false)
    // A zero-offset patch leaves each form as it was assembled at its own address.
    try patch_relative(&output, b_at, b_at)
    try patch_relative(&output, bl_at, bl_at)
    try patch_relative(&output, beq_at, beq_at)
    try patch_relative(&output, cbz_at, cbz_at)
    try patch_relative(&output, cbnz_at, cbnz_at)
    try patch_relative(&output, adr_at, adr_at)
    try patch_relative(&output, adrp_at, adrp_at & 0xFFFFFFFFFFFFF000usize)
    let expected = [_]usize{ 0xD2824680usize, 0xD2FFFFE5usize, 0xF2B7DDE9usize, 0x92800002usize, 0xD280E103usize, 0xF2A0A0C3usize, 0xF2C06083usize, 0xF2E02043usize, 0x92800024usize, 0xAA1303E1usize, 0x910083FFusize, 0x91404BA0usize, 0x910D1400usize, 0xD14007FFusize, 0xF100A8FFusize, 0x8B030041usize, 0xAB030041usize, 0xCB030041usize, 0xEB030041usize, 0x8A030041usize, 0xAA030041usize, 0xCA030041usize, 0x9B037C41usize, 0x9B437C41usize, 0x9BC37C41usize, 0x9AC30C41usize, 0x9AC30841usize, 0x9AC32041usize, 0x9AC32441usize, 0x9AC32841usize, 0x9B039041usize, 0xCB0603E5usize, 0xAA2603E5usize, 0xEB0600BFusize, 0xEB89FD1Fusize, 0x9A9FA7E0usize, 0x9A821020usize, 0x93401C41usize, 0xD3403C41usize, 0x93407C41usize, 0xD37BE883usize, 0xD347FC83usize, 0x9347FC83usize, 0x14000000usize, 0x94000000usize, 0x54000000usize, 0xB4000003usize, 0xB5000003usize, 0xD61F0200usize, 0xD63F0220usize, 0xD65F03C0usize, 0x10000000usize, 0x90000001usize, 0x91000021usize, 0xF9400820usize, 0xB9401020usize, 0x79802020usize, 0x39800C20usize, 0xB9800820usize, 0xF8405020usize, 0xF90007E0usize, 0x39000C20usize, 0xB8003020usize, 0xF85F03A0usize, 0xF81E83A0usize, 0xF8626820usize, 0x38626820usize, 0xB8226820usize, 0xA9BF7BFDusize, 0xA8C17BFDusize, 0xC8DFFC20usize, 0x88DFFC20usize, 0x089FFC20usize, 0xF8E20020usize, 0xB8E28020usize, 0xF8E21020usize, 0xF8E23020usize, 0xF8E22020usize, 0xF8E25020usize, 0xF8E24020usize, 0xF8E27020usize, 0xF8E26020usize, 0xC8E2FC23usize, 0x88E2FC23usize, 0xD5033BBFusize, 0xD4000001usize, 0xD4207D00usize, 0xD503201Fusize, 0x9E670130usize, 0x1E270131usize, 0x9E660209usize, 0x1E260209usize, 0x1E622820usize, 0x1E623820usize, 0x1E620820usize, 0x1E621820usize, 0x1E222820usize, 0x1E61C020usize, 0x1E214020usize, 0x1E612000usize, 0x1F420C20usize, 0x1E22C020usize, 0x1E624020usize, 0x9E620020usize, 0x9E230020usize, 0x9E780020usize, 0x9E390020usize, 0x14000002usize, 0x54FFFFE0usize, 0x397FFC29usize }
    if output.count != expected.len * 4usize { ret OutOfRange }
    var at = 0usize
    while at < expected.len {
        if read_word(&output, at * 4usize) != expected[at] { ret OutOfRange }
        at += 1usize
    }
    ret sweep()
}
