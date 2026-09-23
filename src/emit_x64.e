// Deterministic x64 machine-code byte encoding shared by both host ABIs.
use e.os

error Capacity
error InvalidByte
error InvalidRegister

// One byte per byte (D307): the buffer held one byte per `usize`, and the machine code
// and the image were the two largest allocations of a build, eight times over.
type Buffer = struct {
    bytes: []u8,
    count: usize,
    // The VEX.256 forms (D765, `--cpu x64-v3`): while set, every packed instruction
    // below goes out as its AVX2 form over ymm registers, the same opcode under the
    // three-byte VEX prefix, so the selection tables need no second column. The
    // caller sets it around one thirty-two-byte operation and clears it after the
    // store, with `vzeroupper` so the scalar float path's legacy SSE pays no
    // transition.
    vex: bool,
}

fn init(buffer: *Buffer, bytes: []u8) -> err {
    if bytes.len == 0usize { ret Capacity }
    buffer.bytes = bytes
    buffer.count = 0usize
    ret ok
}

// The writers index a local view of the buffer (D930): the capacity test on it is what
// proves the store, where `buffer.bytes[buffer.count]` through the pointer was checked
// at every byte the compiler writes.
fn byte(buffer: *Buffer, value: usize) -> err {
    if value > 255usize { ret InvalidByte }
    let bytes = buffer.bytes
    let at = buffer.count
    if at >= bytes.len { ret Capacity }
    bytes[at] = u8(value)
    buffer.count = at + 1usize
    ret ok
}

fn pack(buffer: *Buffer, destination: []u8) -> err {
    if buffer.count > destination.len { ret Capacity }
    os.copy_bytes(destination[0usize..buffer.count], buffer.bytes[0usize..buffer.count])
    ret ok
}

fn little_u64(buffer: *Buffer, value: usize) -> err {
    var remaining = value
    var count = 0usize
    while count < 8usize {
        let octet = remaining % 256usize
        try byte(buffer, octet)
        remaining = remaining / 256usize
        count += 1usize
    }
    ret ok
}

// One capacity check and four stores (D324): a byte at a time through `byte`, the
// symbol table's rows -- two million of them at two million lines -- were a call and
// a check each.
fn little_u32(buffer: *Buffer, value: usize) -> err {
    let bytes = buffer.bytes
    let at = buffer.count
    if at + 4usize > bytes.len { ret Capacity }
    bytes[at] = u8(value & 255usize)
    bytes[at + 1usize] = u8((value >> 8usize) & 255usize)
    bytes[at + 2usize] = u8((value >> 16usize) & 255usize)
    bytes[at + 3usize] = u8((value >> 24usize) & 255usize)
    buffer.count = at + 4usize
    ret ok
}

fn patch_little_u32(buffer: *Buffer, at: usize, value: usize) -> err {
    if at + 4usize > buffer.count { ret Capacity }
    var remaining = value
    var offset = 0usize
    while offset < 4usize {
        buffer.bytes[at + offset] = u8(remaining % 256usize)
        remaining = remaining / 256usize
        offset += 1usize
    }
    ret ok
}

fn check_register(index: usize) -> err {
    if index >= 16usize { ret InvalidRegister }
    ret ok
}

fn rex(buffer: *Buffer, reg: usize, rm: usize) -> err {
    try check_register(reg)
    try check_register(rm)
    let value = 72usize + reg / 8usize * 4usize + rm / 8usize
    ret byte(buffer, value)
}

fn rex32(buffer: *Buffer, reg: usize, rm: usize) -> err {
    try check_register(reg)
    try check_register(rm)
    ret byte(buffer, 64usize + reg / 8usize * 4usize + rm / 8usize)
}

fn modrm(buffer: *Buffer, reg: usize, rm: usize) -> err {
    let value = 192usize + reg % 8usize * 8usize + rm % 8usize
    ret byte(buffer, value)
}

// A value under 2^32 is a five-byte `mov r32, imm32`, which zero-extends (D237);
// anything wider is the ten-byte form.
fn mov_immediate(buffer: *Buffer, destination: usize, value: usize) -> err {
    try check_register(destination)
    if value < 4294967296usize {
        if destination >= 8usize { try byte(buffer, 65usize) }
        try byte(buffer, 184usize + destination % 8usize)
        ret little_u32(buffer, value)
    }
    try byte(buffer, 72usize + destination / 8usize)
    try byte(buffer, 184usize + destination % 8usize)
    ret little_u64(buffer, value)
}

fn binary_register(buffer: *Buffer, opcode: usize, destination: usize, source: usize) -> err {
    try rex(buffer, source, destination)
    try byte(buffer, opcode)
    ret modrm(buffer, source, destination)
}

fn mov_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 137usize, destination, source)
}

fn relative_address(buffer: *Buffer, destination: usize) -> (usize, err) {
    let register_error = check_register(destination)
    if register_error != ok { ret (0usize, register_error) }
    let rex_error = byte(buffer, 72usize + destination / 8usize * 4usize)
    if rex_error != ok { ret (0usize, rex_error) }
    let opcode_error = byte(buffer, 141usize)
    if opcode_error != ok { ret (0usize, opcode_error) }
    let address_error = byte(buffer, 5usize + destination % 8usize * 8usize)
    if address_error != ok { ret (0usize, address_error) }
    let displacement = buffer.count
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

fn add_immediate(buffer: *Buffer, destination: usize, value: usize) -> err {
    if value > 4294967295usize { ret InvalidByte }
    try rex(buffer, 0usize, destination)
    try byte(buffer, 129usize)
    try modrm(buffer, 0usize, destination)
    ret little_u32(buffer, value)
}

fn add_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 1usize, destination, source)
}

fn subtract_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 41usize, destination, source)
}

fn bit_and_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 33usize, destination, source)
}

fn bit_xor_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 49usize, destination, source)
}

fn bit_or_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 9usize, destination, source)
}

fn extend_dividend_signed(buffer: *Buffer) -> err {
    try byte(buffer, 72usize)
    ret byte(buffer, 153usize)
}

fn extend_dividend_unsigned(buffer: *Buffer) -> err {
    ret binary_register(buffer, 49usize, 2usize, 2usize)
}

fn divide_register(buffer: *Buffer, divisor: usize, signed: bool) -> err {
    try check_register(divisor)
    var extension = 6usize
    if signed { extension = 7usize }
    try rex(buffer, extension, divisor)
    try byte(buffer, 247usize)
    ret modrm(buffer, extension, divisor)
}

// `mul r/m64`: rdx:rax = rax * source, unsigned; CF and OF say the high half is nonzero.
fn multiply_unsigned_register(buffer: *Buffer, source: usize) -> err {
    try check_register(source)
    try rex(buffer, 4usize, source)
    try byte(buffer, 247usize)
    ret modrm(buffer, 4usize, source)
}

fn and_immediate8(buffer: *Buffer, destination: usize, value: usize) -> err {
    try check_register(destination)
    if value > 255usize { ret InvalidByte }
    try rex(buffer, 4usize, destination)
    try byte(buffer, 131usize)
    try modrm(buffer, 4usize, destination)
    ret byte(buffer, value)
}

fn shift_register(buffer: *Buffer, destination: usize, left: bool, signed: bool) -> err {
    try check_register(destination)
    var extension = 5usize
    if left { extension = 4usize }
    if !left && signed { extension = 7usize }
    try rex(buffer, extension, destination)
    try byte(buffer, 211usize)
    ret modrm(buffer, extension, destination)
}

fn compare_register(buffer: *Buffer, left: usize, right: usize) -> err {
    ret binary_register(buffer, 57usize, left, right)
}

fn set_condition(buffer: *Buffer, destination: usize, condition: usize) -> err {
    try check_register(destination)
    if condition >= 16usize { ret InvalidByte }
    try byte(buffer, 64usize + destination / 8usize)
    try byte(buffer, 15usize)
    try byte(buffer, 144usize + condition)
    ret byte(buffer, 192usize + destination % 8usize)
}

fn multiply_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    try rex(buffer, destination, source)
    try byte(buffer, 15usize)
    try byte(buffer, 175usize)
    ret modrm(buffer, destination, source)
}

fn multiply_immediate(buffer: *Buffer, destination: usize, source: usize, value: usize) -> err {
    if value > 4294967295usize { ret InvalidByte }
    try rex(buffer, destination, source)
    try byte(buffer, 105usize)
    try modrm(buffer, destination, source)
    ret little_u32(buffer, value)
}

fn bounds_check(buffer: *Buffer, index: usize, length: usize) -> err {
    try compare_register(buffer, index, length)
    try byte(buffer, 114usize)
    try byte(buffer, 2usize)
    try byte(buffer, 15usize)
    ret byte(buffer, 11usize)
}

fn slice_bounds_check(buffer: *Buffer, lower: usize, upper: usize, length: usize) -> err {
    try compare_register(buffer, lower, upper)
    try byte(buffer, 118usize)
    try byte(buffer, 2usize)
    try byte(buffer, 15usize)
    try byte(buffer, 11usize)
    try compare_register(buffer, upper, length)
    try byte(buffer, 118usize)
    try byte(buffer, 2usize)
    try byte(buffer, 15usize)
    ret byte(buffer, 11usize)
}

fn negate_register(buffer: *Buffer, value: usize) -> err {
    try check_register(value)
    try rex(buffer, 3usize, value)
    try byte(buffer, 247usize)
    ret modrm(buffer, 3usize, value)
}

fn bit_not_register(buffer: *Buffer, value: usize) -> err {
    try check_register(value)
    try rex(buffer, 2usize, value)
    try byte(buffer, 247usize)
    ret modrm(buffer, 2usize, value)
}

fn normalize_integer(buffer: *Buffer, destination: usize, source: usize, width: usize, signed: bool) -> err {
    try check_register(destination)
    try check_register(source)
    if width == 64usize {
        if destination != source { ret mov_register(buffer, destination, source) }
        ret ok
    }
    if width == 32usize {
        if signed {
            try rex(buffer, destination, source)
            try byte(buffer, 99usize)
            ret modrm(buffer, destination, source)
        }
        try byte(buffer, 64usize + destination / 8usize * 4usize + source / 8usize)
        try byte(buffer, 139usize)
        ret modrm(buffer, destination, source)
    }
    try rex(buffer, destination, source)
    try byte(buffer, 15usize)
    if width == 8usize {
        if signed { try byte(buffer, 190usize) } else { try byte(buffer, 182usize) }
        ret modrm(buffer, destination, source)
    }
    if width == 16usize {
        if signed { try byte(buffer, 191usize) } else { try byte(buffer, 183usize) }
        ret modrm(buffer, destination, source)
    }
    ret InvalidByte
}

// SSE2, which is the floating-point baseline every x64 target has. Float values live
// in general registers as raw bits between operations, so the only xmm registers this
// emitter names are the two scratch ones an operation borrows; `reg` and `rm` below
// are whichever file the opcode says, and the caller keeps them straight.
fn sse(buffer: *Buffer, mandatory: usize, wide: bool, reg: usize, rm: usize, opcode: usize) -> err {
    try check_register(reg)
    try check_register(rm)
    if buffer.vex {
        // The legacy two-operand form's destination is VEX's first source too, except
        // for the moves and the shuffle, which read one operand and leave vvvv unused --
        // spelled as register 0, whose inverted field is all ones, the one spelling
        // the unit accepts there -- and the shifts by an immediate, whose register
        // field is the opcode's extension and whose destination therefore rides in
        // vvvv (the NDD form).
        var first = reg
        if opcode == 40usize || opcode == 112usize || opcode == 110usize || opcode == 126usize || opcode == 16usize || opcode == 17usize { first = 0usize }
        if opcode == 113usize || opcode == 114usize || opcode == 115usize { first = rm }
        // `vmovq` and `vmovd` are the one pair that refuse a 256-bit length.
        let full = opcode != 110usize && opcode != 126usize
        try vex_prefix(buffer, mandatory, wide, reg, first, rm, full)
        try byte(buffer, opcode)
        ret modrm(buffer, reg, rm)
    }
    if mandatory != 0usize { try byte(buffer, mandatory) }
    var extension = 0usize
    if wide { extension += 8usize }
    if reg >= 8usize { extension += 4usize }
    if rm >= 8usize { extension += 1usize }
    if extension != 0usize { try byte(buffer, 64usize + extension) }
    try byte(buffer, 15usize)
    try byte(buffer, opcode)
    ret modrm(buffer, reg, rm)
}

// SSE2's packed forms, which operate on all sixteen bytes of a vector at once, or on
// the low half, quarter or eighth of the register when the operand is narrower -- a
// mask, which is one byte per lane. A vector lives in its stack slot, which is aligned
// to eight bytes and not to sixteen, so sixteen bytes come in through `movups` -- the
// unaligned move, the one packed load that does not fault on an eight-byte-aligned
// address -- eight through `movlps`, a quadword, and four through `movd`, a doubleword;
// neither narrow move faults. Two bytes are the one width the vector unit cannot carry
// to and from memory on this baseline: `pinsrw` reads a word but the `pextrw` that
// would write one back only answers into a general register before SSE4.1, so both
// directions go through one instead -- a zero-extending word load and the `movq` the
// scalar float path already moves bits with. Each move touches exactly the operand's
// bytes: the narrow loads leave the lanes above them as they found them or clear them,
// which no caller reads, and the narrow stores write only the bytes the mask owns.
fn vector_load(buffer: *Buffer, destination: usize, address: usize, bytes: usize, scratch: usize) -> err {
    if bytes == 2usize {
        try load_memory(buffer, scratch, address, 16usize, false)
        ret move_to_float(buffer, destination, scratch, true)
    }
    if bytes == 4usize { ret sse_memory(buffer, 102usize, destination, address, 110usize) }
    if bytes == 8usize { ret sse_memory(buffer, 0usize, destination, address, 18usize) }
    ret sse_memory(buffer, 0usize, destination, address, 16usize)
}

fn vector_store(buffer: *Buffer, address: usize, source: usize, bytes: usize, scratch: usize) -> err {
    if bytes == 2usize {
        try move_from_float(buffer, scratch, source, true)
        ret store_memory(buffer, address, scratch, 16usize)
    }
    if bytes == 4usize { ret sse_memory(buffer, 102usize, source, address, 126usize) }
    if bytes == 8usize { ret sse_memory(buffer, 0usize, source, address, 19usize) }
    ret sse_memory(buffer, 0usize, source, address, 17usize)
}

fn sse_memory(buffer: *Buffer, mandatory: usize, reg: usize, address: usize, opcode: usize) -> err {
    try check_register(reg)
    try check_register(address)
    if buffer.vex {
        // A load or a store reads one operand, so vvvv is unused: all ones inverted.
        try vex_prefix(buffer, mandatory, false, reg, 0usize, address, true)
        try byte(buffer, opcode)
        ret memory_modrm(buffer, reg, address)
    }
    if mandatory != 0usize { try byte(buffer, mandatory) }
    var extension = 0usize
    if reg >= 8usize { extension += 4usize }
    if address >= 8usize { extension += 1usize }
    if extension != 0usize { try byte(buffer, 64usize + extension) }
    try byte(buffer, 15usize)
    try byte(buffer, opcode)
    ret memory_modrm(buffer, reg, address)
}

// The three-byte VEX prefix (D765) over the 0F opcode map: C4, then the inverted
// REX bits with the map, then W, the inverted first source, the length and the
// mandatory prefix as the two-bit `pp`. Every packed instruction this emitter names is
// in the 0F map, so the map is the one constant.
fn vex_prefix(buffer: *Buffer, mandatory: usize, wide: bool, reg: usize, first: usize, rm: usize, full: bool) -> err {
    var pp = 0usize
    if mandatory == 102usize { pp = 1usize }
    if mandatory == 243usize { pp = 2usize }
    if mandatory == 242usize { pp = 3usize }
    var second = 1usize + 64usize
    if reg < 8usize { second += 128usize }
    if rm < 8usize { second += 32usize }
    var third = (15usize - first) * 8usize + pp
    if wide { third += 128usize }
    if full { third += 4usize }
    try byte(buffer, 196usize)
    try byte(buffer, second)
    ret byte(buffer, third)
}

// `vzeroupper` (D765): the upper halves of every ymm register cleared, so the legacy
// SSE forms that follow pay no transition.
fn vzeroupper(buffer: *Buffer) -> err {
    try byte(buffer, 197usize)
    try byte(buffer, 248usize)
    ret byte(buffer, 119usize)
}

// One packed operation between two xmm registers: the mandatory prefix and the opcode
// come from the caller's table, since that pair is the whole instruction selection.
fn vector_op(buffer: *Buffer, mandatory: usize, destination: usize, source: usize, opcode: usize) -> err {
    ret sse(buffer, mandatory, false, destination, source, opcode)
}

// `cmpps`/`cmppd` with the unordered predicate: every lane that is a NaN becomes all
// ones, every other lane zero.
fn vector_unordered(buffer: *Buffer, mandatory: usize, destination: usize, source: usize) -> err {
    try sse(buffer, mandatory, false, destination, source, 194usize)
    ret byte(buffer, 3usize)
}

// `psllw`/`psrlw`/`psraw` (0x71), `pslld`/`psrld`/`psrad` (0x72) and `psllq`/`psrlq`
// (0x73) by a constant, where the modrm register field is the opcode extension: 6 to
// shift left, 2 to shift right and 4 to shift an arithmetic right, which 0x73 has not.
fn vector_shift(buffer: *Buffer, extension: usize, destination: usize, count: usize, opcode: usize) -> err {
    try sse(buffer, 102usize, false, extension, destination, opcode)
    ret byte(buffer, count)
}

// `pshufd`: the four thirty-two-bit lanes of the source in whatever order the
// immediate's four two-bit fields name, lane 0 lowest. It is a move and not a permute
// of the destination, so a lane may be named more than once or not at all.
fn vector_shuffle(buffer: *Buffer, destination: usize, source: usize, selector: usize) -> err {
    try sse(buffer, 102usize, false, destination, source, 112usize)
    ret byte(buffer, selector)
}

// `movq`/`movd` in both directions: the bits move, nothing is converted.
fn move_to_float(buffer: *Buffer, destination: usize, source: usize, wide: bool) -> err {
    ret sse(buffer, 102usize, wide, destination, source, 110usize)
}

fn move_from_float(buffer: *Buffer, destination: usize, source: usize, wide: bool) -> err {
    ret sse(buffer, 102usize, wide, source, destination, 126usize)
}

// `addsd` 0x58, `mulsd` 0x59, `subsd` 0x5c, `divsd` 0x5e; the `F2`/`F3` prefix picks
// double or single, and REX.W has no meaning for these.
fn float_binary(buffer: *Buffer, destination: usize, source: usize, opcode: usize, wide: bool) -> err {
    var mandatory = 243usize
    if wide { mandatory = 242usize }
    ret sse(buffer, mandatory, false, destination, source, opcode)
}

// `sqrtss` 0x51 / `sqrtsd`, with the same prefix rule as the arithmetic.
fn float_sqrt(buffer: *Buffer, destination: usize, source: usize, wide: bool) -> err {
    var mandatory = 243usize
    if wide { mandatory = 242usize }
    ret sse(buffer, mandatory, false, destination, source, 81usize)
}

// `ucomiss` / `ucomisd`. Unordered sets ZF, PF and CF together, which is what makes
// `above` and `above or equal` the two conditions that answer false for a NaN.
fn float_compare(buffer: *Buffer, left: usize, right: usize, wide: bool) -> err {
    var mandatory = 0usize
    if wide { mandatory = 102usize }
    ret sse(buffer, mandatory, false, left, right, 46usize)
}

// `cvtsi2ss` / `cvtsi2sd` from a 64-bit general register holding a signed value.
fn float_from_signed(buffer: *Buffer, destination: usize, source: usize, wide: bool) -> err {
    var mandatory = 243usize
    if wide { mandatory = 242usize }
    ret sse(buffer, mandatory, true, destination, source, 42usize)
}

// `cvttss2si` / `cvttsd2si` into a 64-bit general register, truncating toward zero.
fn signed_from_float(buffer: *Buffer, destination: usize, source: usize, wide: bool) -> err {
    var mandatory = 243usize
    if wide { mandatory = 242usize }
    ret sse(buffer, mandatory, true, destination, source, 44usize)
}

// `cvtss2sd` when widening, `cvtsd2ss` when narrowing.
fn float_convert(buffer: *Buffer, destination: usize, source: usize, to_wide: bool) -> err {
    var mandatory = 242usize
    if to_wide { mandatory = 243usize }
    ret sse(buffer, mandatory, false, destination, source, 90usize)
}

// `shr r64, 1`, which the unsigned 64-bit conversions need and no integer selection
// does.
// `btc r64, 63`, which puts back the 2**63 an unsigned conversion took out.
fn bit_toggle_high(buffer: *Buffer, destination: usize) -> err {
    try check_register(destination)
    try rex(buffer, 7usize, destination)
    try byte(buffer, 15usize)
    try byte(buffer, 186usize)
    try modrm(buffer, 7usize, destination)
    ret byte(buffer, 63usize)
}

fn shift_right_one(buffer: *Buffer, destination: usize) -> err {
    try check_register(destination)
    try rex(buffer, 5usize, destination)
    try byte(buffer, 209usize)
    ret modrm(buffer, 5usize, destination)
}

// A forward `jcc rel32` whose displacement the caller patches once the landing point
// is known, the same contract `jump` has.
fn jump_condition(buffer: *Buffer, condition: usize) -> (usize, err) {
    if condition >= 16usize { ret (0usize, InvalidByte) }
    let opcode_error = byte(buffer, 15usize)
    if opcode_error != ok { ret (0usize, opcode_error) }
    let condition_error = byte(buffer, 128usize + condition)
    if condition_error != ok { ret (0usize, condition_error) }
    let displacement_at = buffer.count
    let placeholder_error = little_u32(buffer, 0usize)
    if placeholder_error != ok { ret (0usize, placeholder_error) }
    ret (displacement_at, ok)
}

// `jcc rel8` (D927): the short form, for a jump over a few bytes the caller bounds.
fn jump_condition_short(buffer: *Buffer, condition: usize) -> (usize, err) {
    if condition >= 16usize { ret (0usize, InvalidByte) }
    let opcode_error = byte(buffer, 112usize + condition)
    if opcode_error != ok { ret (0usize, opcode_error) }
    let displacement_at = buffer.count
    let placeholder_error = byte(buffer, 0usize)
    if placeholder_error != ok { ret (0usize, placeholder_error) }
    ret (displacement_at, ok)
}

// A short jump's one byte, forward only and within reach.
fn patch_relative8(buffer: *Buffer, displacement_at: usize, destination: usize) -> err {
    if destination < displacement_at + 1usize || destination - (displacement_at + 1usize) > 127usize { ret InvalidByte }
    buffer.bytes[displacement_at] = u8(destination - (displacement_at + 1usize))
    ret ok
}

fn frame_size(stack_slots: usize) -> usize {
    let bytes = stack_slots * 8usize
    let rounded = bytes + 15usize
    ret rounded / 16usize * 16usize
}

fn function_prologue(buffer: *Buffer, stack_slots: usize) -> err {
    try byte(buffer, 85usize)
    try mov_register(buffer, 5usize, 4usize)
    let bytes = frame_size(stack_slots)
    var remaining = bytes
    while remaining > 4096usize {
        try byte(buffer, 72usize)
        try byte(buffer, 129usize)
        try byte(buffer, 236usize)
        try little_u32(buffer, 4096usize)
        try byte(buffer, 246usize)
        try byte(buffer, 4usize)
        try byte(buffer, 36usize)
        try byte(buffer, 0usize)
        remaining = remaining - 4096usize
    }
    if remaining != 0usize {
        try byte(buffer, 72usize)
        try byte(buffer, 129usize)
        try byte(buffer, 236usize)
        try little_u32(buffer, remaining)
        if bytes >= 4096usize {
            try byte(buffer, 246usize)
            try byte(buffer, 4usize)
            try byte(buffer, 36usize)
            try byte(buffer, 0usize)
        }
    }
    ret ok
}

fn function_epilogue(buffer: *Buffer) -> err {
    try mov_register(buffer, 4usize, 5usize)
    try byte(buffer, 93usize)
    ret return_instruction(buffer)
}

fn stack_displacement(slot: usize) -> usize {
    let next = slot + 1usize
    let magnitude = next * 8usize
    ret 4294967296usize - magnitude
}

fn stack_address(buffer: *Buffer, destination: usize, slot: usize) -> err {
    try check_register(destination)
    try byte(buffer, 72usize + destination / 8usize * 4usize)
    try byte(buffer, 141usize)
    try byte(buffer, 133usize + destination % 8usize * 8usize)
    ret little_u32(buffer, stack_displacement(slot))
}

// `[address]` with no displacement. Two bases have no plain encoding: rsp and r12 want
// a SIB byte that names them, rbp and r13 a zero eight-bit displacement, since their
// slot in the mod 00 row means rip-relative (D235).
fn memory_modrm(buffer: *Buffer, reg: usize, address: usize) -> err {
    try check_register(reg)
    try check_register(address)
    if address % 8usize == 4usize {
        try byte(buffer, reg % 8usize * 8usize + 4usize)
        ret byte(buffer, 36usize)
    }
    if address % 8usize == 5usize {
        try byte(buffer, 64usize + reg % 8usize * 8usize + 5usize)
        ret byte(buffer, 0usize)
    }
    ret byte(buffer, reg % 8usize * 8usize + address % 8usize)
}

fn load_memory(buffer: *Buffer, destination: usize, address: usize, width: usize, signed: bool) -> err {
    if width == 64usize {
        try rex(buffer, destination, address)
        try byte(buffer, 139usize)
        ret memory_modrm(buffer, destination, address)
    }
    if width == 32usize && !signed {
        try rex32(buffer, destination, address)
        try byte(buffer, 139usize)
        ret memory_modrm(buffer, destination, address)
    }
    try rex(buffer, destination, address)
    if width == 32usize {
        try byte(buffer, 99usize)
        ret memory_modrm(buffer, destination, address)
    }
    try byte(buffer, 15usize)
    if width == 8usize {
        if signed { try byte(buffer, 190usize) } else { try byte(buffer, 182usize) }
        ret memory_modrm(buffer, destination, address)
    }
    if width == 16usize {
        if signed { try byte(buffer, 191usize) } else { try byte(buffer, 183usize) }
        ret memory_modrm(buffer, destination, address)
    }
    ret InvalidByte
}

fn store_memory(buffer: *Buffer, address: usize, source: usize, width: usize) -> err {
    if width == 16usize { try byte(buffer, 102usize) }
    if width == 64usize {
        try rex(buffer, source, address)
    } else {
        if width != 8usize && width != 16usize && width != 32usize { ret InvalidByte }
        try rex32(buffer, source, address)
    }
    if width == 8usize { try byte(buffer, 136usize) } else { try byte(buffer, 137usize) }
    ret memory_modrm(buffer, source, address)
}

// Aggregate fills and copies run eight bytes per iteration with a byte loop for the
// tail (D306). They ran a byte per iteration, five instructions each, and every
// struct read out of a table -- a token, a node, an instruction -- is a copy: the
// compiler spent more of its time in these two loops than in any pass.
// A byte slice appended whole (D314): a function's code moving from a module's
// staging buffer to the image's.
fn append_bytes(buffer: *Buffer, bytes: []const u8) -> err {
    let end = buffer.count + bytes.len
    if end > buffer.bytes.len { ret Capacity }
    os.copy_bytes(buffer.bytes[buffer.count..end], bytes)
    buffer.count = end
    ret ok
}

fn emit_bytes(buffer: *Buffer, bytes: []const usize) -> err {
    var at = 0usize
    while at < bytes.len {
        try byte(buffer, bytes[at])
        at += 1usize
    }
    ret ok
}

fn zero_memory(buffer: *Buffer, address: usize, size: usize) -> err {
    if size == 0usize { ret ok }
    if address != 10usize { try mov_register(buffer, 10usize, address) }
    try mov_immediate(buffer, 11usize, size)
    // cmp r11, 8; jb tail
    let seq1 = [_]usize{ 73usize, 131usize, 251usize, 8usize, 114usize, 21usize }
    try emit_bytes(buffer, seq1[..])
    // loop8: mov qword [r10], 0; add r10, 8; sub r11, 8; cmp r11, 8; jae loop8
    let seq2 = [_]usize{ 73usize, 199usize, 2usize, 0usize, 0usize, 0usize, 0usize, 73usize, 131usize, 194usize, 8usize, 73usize, 131usize, 235usize, 8usize, 73usize, 131usize, 251usize, 8usize, 115usize, 235usize }
    try emit_bytes(buffer, seq2[..])
    // tail: test r11, r11; jz done
    let seq3 = [_]usize{ 77usize, 133usize, 219usize, 116usize, 12usize }
    try emit_bytes(buffer, seq3[..])
    // byte loop: mov byte [r10], 0; inc r10; dec r11; jnz
    try byte(buffer, 65usize)
    try byte(buffer, 198usize)
    try byte(buffer, 2usize)
    try byte(buffer, 0usize)
    try byte(buffer, 73usize)
    try byte(buffer, 255usize)
    try byte(buffer, 194usize)
    try byte(buffer, 73usize)
    try byte(buffer, 255usize)
    try byte(buffer, 203usize)
    try byte(buffer, 117usize)
    ret byte(buffer, 244usize)
}

fn copy_memory(buffer: *Buffer, destination: usize, source: usize, size: usize) -> err {
    if size == 0usize { ret ok }
    if destination != 10usize { try mov_register(buffer, 10usize, destination) }
    if source != 11usize { try mov_register(buffer, 11usize, source) }
    try mov_immediate(buffer, 0usize, size)
    // cmp rax, 8; jb tail
    let seq4 = [_]usize{ 72usize, 131usize, 248usize, 8usize, 114usize, 24usize }
    try emit_bytes(buffer, seq4[..])
    // loop8: mov r9, [r11]; mov [r10], r9; add r11, 8; add r10, 8; sub rax, 8; cmp rax, 8; jae loop8
    let seq5 = [_]usize{ 77usize, 139usize, 11usize, 77usize, 137usize, 10usize, 73usize, 131usize, 195usize, 8usize, 73usize, 131usize, 194usize, 8usize, 72usize, 131usize, 232usize, 8usize, 72usize, 131usize, 248usize, 8usize, 115usize, 232usize }
    try emit_bytes(buffer, seq5[..])
    // tail: test rax, rax; jz done
    let seq6 = [_]usize{ 72usize, 133usize, 192usize, 116usize, 17usize }
    try emit_bytes(buffer, seq6[..])
    // byte loop: mov r9b, [r11]; mov [r10], r9b; inc r11; inc r10; dec rax; jnz
    try byte(buffer, 69usize)
    try byte(buffer, 138usize)
    try byte(buffer, 11usize)
    try byte(buffer, 69usize)
    try byte(buffer, 136usize)
    try byte(buffer, 10usize)
    try byte(buffer, 73usize)
    try byte(buffer, 255usize)
    try byte(buffer, 195usize)
    try byte(buffer, 73usize)
    try byte(buffer, 255usize)
    try byte(buffer, 194usize)
    try byte(buffer, 72usize)
    try byte(buffer, 255usize)
    try byte(buffer, 200usize)
    try byte(buffer, 117usize)
    ret byte(buffer, 239usize)
}

fn load_stack(buffer: *Buffer, destination: usize, slot: usize) -> err {
    try check_register(destination)
    try byte(buffer, 72usize + destination / 8usize * 4usize)
    try byte(buffer, 139usize)
    try byte(buffer, 133usize + destination % 8usize * 8usize)
    ret little_u32(buffer, stack_displacement(slot))
}

fn store_stack(buffer: *Buffer, slot: usize, source: usize) -> err {
    try check_register(source)
    try byte(buffer, 72usize + source / 8usize * 4usize)
    try byte(buffer, 137usize)
    try byte(buffer, 133usize + source % 8usize * 8usize)
    ret little_u32(buffer, stack_displacement(slot))
}

fn load_frame_argument(buffer: *Buffer, destination: usize, displacement: usize) -> err {
    try check_register(destination)
    if displacement > 4294967295usize { ret InvalidByte }
    try byte(buffer, 72usize + destination / 8usize * 4usize)
    try byte(buffer, 139usize)
    try byte(buffer, 133usize + destination % 8usize * 8usize)
    ret little_u32(buffer, displacement)
}

fn store_call_argument(buffer: *Buffer, displacement: usize, source: usize) -> err {
    try check_register(source)
    if displacement > 4294967295usize { ret InvalidByte }
    try byte(buffer, 72usize + source / 8usize * 4usize)
    try byte(buffer, 137usize)
    try byte(buffer, 132usize + source % 8usize * 8usize)
    try byte(buffer, 36usize)
    ret little_u32(buffer, displacement)
}

fn test_register(buffer: *Buffer, value: usize) -> err {
    try rex(buffer, value, value)
    try byte(buffer, 133usize)
    ret modrm(buffer, value, value)
}

fn jump(buffer: *Buffer) -> (usize, err) {
    let displacement = buffer.count + 1usize
    let byte_error = byte(buffer, 233usize)
    if byte_error != ok { ret (0usize, byte_error) }
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

fn call(buffer: *Buffer) -> (usize, err) {
    let displacement = buffer.count + 1usize
    let byte_error = byte(buffer, 232usize)
    if byte_error != ok { ret (0usize, byte_error) }
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

// `call qword ptr [rip + disp32]`, FF /2 with a RIP-relative operand: the indirect
// call an imported function is reached through, where the slot holds the address the
// loader wrote rather than the code itself.
fn call_indirect_relative(buffer: *Buffer) -> (usize, err) {
    let opcode_error = byte(buffer, 255usize)
    if opcode_error != ok { ret (0usize, opcode_error) }
    let modrm_error = byte(buffer, 21usize)
    if modrm_error != ok { ret (0usize, modrm_error) }
    let displacement = buffer.count
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

// FF /2 with a register operand: an indirect call through the callee value.
fn call_register(buffer: *Buffer, callee: usize) -> err {
    try check_register(callee)
    if callee >= 8usize { try byte(buffer, 65usize) }
    try byte(buffer, 255usize)
    ret byte(buffer, 208usize + callee % 8usize)
}

fn jump_nonzero(buffer: *Buffer, value: usize) -> (usize, err) {
    let test_error = test_register(buffer, value)
    if test_error != ok { ret (0usize, test_error) }
    let first_error = byte(buffer, 15usize)
    if first_error != ok { ret (0usize, first_error) }
    let second_error = byte(buffer, 133usize)
    if second_error != ok { ret (0usize, second_error) }
    let displacement = buffer.count
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

fn patch_relative32(buffer: *Buffer, displacement_at: usize, destination: usize) -> err {
    let following = displacement_at + 4usize
    var displacement = 0usize
    if destination >= following {
        displacement = destination - following
    } else {
        let magnitude = following - destination
        displacement = 4294967296usize - magnitude
    }
    ret patch_little_u32(buffer, displacement_at, displacement)
}

fn return_instruction(buffer: *Buffer) -> err {
    ret byte(buffer, 195usize)
}

fn self_test() -> err {
    var storage: [64]u8 = zero
    var buffer: Buffer = zero
    try init(&buffer, storage[..])
    try mov_immediate(&buffer, 0usize, 0x0102030405060708usize)
    try mov_register(&buffer, 9usize, 10usize)
    try add_register(&buffer, 9usize, 10usize)
    try subtract_register(&buffer, 9usize, 10usize)
    try multiply_register(&buffer, 9usize, 10usize)
    try compare_register(&buffer, 9usize, 10usize)
    try set_condition(&buffer, 9usize, 12usize)
    try return_instruction(&buffer)
    let expected = [31]usize{
        72usize, 184usize, 8usize, 7usize, 6usize, 5usize, 4usize, 3usize, 2usize, 1usize,
        77usize, 137usize, 209usize,
        77usize, 1usize, 209usize,
        77usize, 41usize, 209usize,
        77usize, 15usize, 175usize, 202usize,
        77usize, 57usize, 209usize,
        65usize, 15usize, 156usize, 193usize,
        195usize,
    }
    if buffer.count != expected.len { ret InvalidRegister }
    var at = 0usize
    while at < expected.len {
        if usize(buffer.bytes[at]) != expected[at] { ret InvalidRegister }
        at += 1usize
    }
    var scalar_storage: [64]u8 = zero
    var scalar: Buffer = zero
    try init(&scalar, scalar_storage[..])
    try negate_register(&scalar, 0usize)
    try bit_not_register(&scalar, 9usize)
    try normalize_integer(&scalar, 10usize, 9usize, 32usize, true)
    try normalize_integer(&scalar, 9usize, 10usize, 8usize, false)
    try bit_and_register(&scalar, 9usize, 10usize)
    try bit_xor_register(&scalar, 9usize, 10usize)
    try bit_or_register(&scalar, 9usize, 10usize)
    try extend_dividend_signed(&scalar)
    try extend_dividend_unsigned(&scalar)
    try divide_register(&scalar, 11usize, true)
    try divide_register(&scalar, 11usize, false)
    try and_immediate8(&scalar, 1usize, 31usize)
    try shift_register(&scalar, 10usize, true, false)
    try shift_register(&scalar, 10usize, false, true)
    try shift_register(&scalar, 10usize, false, false)
    let scalar_expected = [46]usize{ 72usize, 247usize, 216usize, 73usize, 247usize, 209usize, 77usize, 99usize, 209usize, 77usize, 15usize, 182usize, 202usize, 77usize, 33usize, 209usize, 77usize, 49usize, 209usize, 77usize, 9usize, 209usize, 72usize, 153usize, 72usize, 49usize, 210usize, 73usize, 247usize, 251usize, 73usize, 247usize, 243usize, 72usize, 131usize, 225usize, 31usize, 73usize, 211usize, 226usize, 73usize, 211usize, 250usize, 73usize, 211usize, 234usize }
    if scalar.count != scalar_expected.len { ret InvalidRegister }
    at = 0usize
    while at < scalar_expected.len {
        if usize(scalar.bytes[at]) != scalar_expected[at] { ret InvalidRegister }
        at += 1usize
    }
    var frame_storage: [64]u8 = zero
    var frame: Buffer = zero
    try init(&frame, frame_storage[..])
    try function_prologue(&frame, 2usize)
    try store_stack(&frame, 1usize, 10usize)
    try load_stack(&frame, 11usize, 1usize)
    try function_epilogue(&frame)
    if frame.count != 30usize { ret InvalidRegister }
    if frame.bytes[0usize] != 85u8 || frame.bytes[4usize] != 72u8 || frame.bytes[11usize] != 76u8 || frame.bytes[18usize] != 76u8 || frame.bytes[29usize] != 195u8 { ret InvalidRegister }
    var probe_storage: [64]u8 = zero
    var probe: Buffer = zero
    try init(&probe, probe_storage[..])
    try function_prologue(&probe, 1024usize)
    if probe.count != 26usize || probe.bytes[4usize] != 72u8 || probe.bytes[11usize] != 246u8 || probe.bytes[15usize] != 72u8 || probe.bytes[22usize] != 246u8 { ret InvalidRegister }
    var memory_storage: [160]u8 = zero
    var memory: Buffer = zero
    try init(&memory, memory_storage[..])
    try stack_address(&memory, 10usize, 1usize)
    try add_immediate(&memory, 10usize, 3usize)
    try load_memory(&memory, 11usize, 10usize, 8usize, false)
    try load_memory(&memory, 11usize, 10usize, 16usize, true)
    try load_memory(&memory, 11usize, 10usize, 32usize, false)
    try load_memory(&memory, 11usize, 10usize, 64usize, false)
    try store_memory(&memory, 10usize, 11usize, 8usize)
    try store_memory(&memory, 10usize, 11usize, 16usize)
    try store_memory(&memory, 10usize, 11usize, 32usize)
    try store_memory(&memory, 10usize, 11usize, 64usize)
    try zero_memory(&memory, 9usize, 24usize)
    try multiply_immediate(&memory, 10usize, 11usize, 24usize)
    try bounds_check(&memory, 10usize, 11usize)
    if memory.count != 108usize { ret InvalidRegister }
    if memory.bytes[0usize] != 76u8 || memory.bytes[1usize] != 141u8 || memory.bytes[7usize] != 73u8 || memory.bytes[14usize] != 77u8 || memory.bytes[16usize] != 182u8 || memory.bytes[31usize] != 102u8 || memory.bytes[40usize] != 26u8 { ret InvalidRegister }
    if memory.bytes[41usize] != 77u8 || memory.bytes[44usize] != 65u8 || memory.bytes[45usize] != 187u8 || memory.bytes[50usize] != 73u8 || memory.bytes[56usize] != 73u8 || memory.bytes[57usize] != 199u8 || memory.bytes[82usize] != 65u8 || memory.bytes[93usize] != 244u8 { ret InvalidRegister }
    if memory.bytes[94usize] != 77u8 || memory.bytes[95usize] != 105u8 || memory.bytes[101usize] != 77u8 || memory.bytes[104usize] != 114u8 || memory.bytes[107usize] != 11u8 { ret InvalidRegister }
    ret ok
}

// Section 8's atomics. `lock` makes the read-modify-write that follows indivisible;
// `xchg` against memory is locked implicitly and must not carry the prefix.
//
// The width prefix is the one `store_memory` uses: `66` for 16, `REX.W` for 64, and a
// REX byte otherwise -- always emitted at width 8, where it is what makes the low byte
// of every register addressable.
fn atomic_prefix(buffer: *Buffer, reg: usize, address: usize, width: usize) -> err {
    if width != 8usize && width != 16usize && width != 32usize && width != 64usize { ret InvalidByte }
    if width == 16usize { try byte(buffer, 102usize) }
    if width == 64usize { ret rex(buffer, reg, address) }
    ret rex32(buffer, reg, address)
}

// `lock xadd [address], source`: source gets what was there, the sum is stored.
fn atomic_exchange_add(buffer: *Buffer, address: usize, source: usize, width: usize) -> err {
    try byte(buffer, 240usize)
    try atomic_prefix(buffer, source, address, width)
    try byte(buffer, 15usize)
    if width == 8usize { try byte(buffer, 192usize) } else { try byte(buffer, 193usize) }
    ret memory_modrm(buffer, source, address)
}

// `xchg [address], source`: source gets what was there. Locked with no prefix.
fn atomic_exchange(buffer: *Buffer, address: usize, source: usize, width: usize) -> err {
    try atomic_prefix(buffer, source, address, width)
    if width == 8usize { try byte(buffer, 134usize) } else { try byte(buffer, 135usize) }
    ret memory_modrm(buffer, source, address)
}

// `lock cmpxchg [address], source`: rax is compared with what is there; on a match
// source is stored, otherwise rax gets what was found. Either way rax ends up holding
// the previous value, which is what section 8's `cas` returns.
fn atomic_compare_exchange(buffer: *Buffer, address: usize, source: usize, width: usize) -> err {
    try byte(buffer, 240usize)
    try atomic_prefix(buffer, source, address, width)
    try byte(buffer, 15usize)
    if width == 8usize { try byte(buffer, 176usize) } else { try byte(buffer, 177usize) }
    ret memory_modrm(buffer, source, address)
}

// `mfence`. The only ordering this target has to emit anything for: every other one
// is free under its store-ordered memory model.
fn memory_fence(buffer: *Buffer) -> err {
    try byte(buffer, 15usize)
    try byte(buffer, 174usize)
    ret byte(buffer, 240usize)
}

// `cmovcc destination, source`, for the `min` and `max` that no single instruction
// does.
fn conditional_move(buffer: *Buffer, destination: usize, source: usize, condition: usize) -> err {
    if condition >= 16usize { ret InvalidByte }
    try rex(buffer, destination, source)
    try byte(buffer, 15usize)
    try byte(buffer, 64usize + condition)
    ret modrm(buffer, destination, source)
}

// A backward `jne` to `target`, which is a count already taken from this buffer. The
// hand-rolled loop in `zero_memory` jumps the same way; the compare-and-swap loops
// that carry `and`, `or`, `xor`, `min` and `max` are the other users.
fn jump_back_not_equal(buffer: *Buffer, destination: usize) -> err {
    let after = buffer.count + 2usize
    if destination > after { ret InvalidByte }
    let distance = after - destination
    if distance > 128usize { ret InvalidByte }
    try byte(buffer, 117usize)
    ret byte(buffer, 256usize - distance)
}
