// AArch64 instruction selection from allocated scalar NIR (D2123): the x64 selector's
// shape over AAPCS64. Every function keeps an x29/x30 frame record -- the chain the
// trap walk reads -- and its slots below x29, slot k at [x29 - 8(k + 1)].
//
// The allocator's sixteen registers are six the calls clobber, x9-x14, then ten the
// callee keeps, x19-x28. None is an argument register, so a call writes x0-x7 without
// parking anything, and every fixed sequence below works in registers no value lives
// in: x0-x8 and x15-x17. x8 addresses a far frame slot, x16 and x17 are the scratch
// pair x64 has in r10 and r11, and x15 a third. x18, the platform register, is left
// alone. Float values live in general registers as bits, as on x64, and borrow v16
// and v17 for an operation.
//
// Everything a function addresses inside itself -- a string, a trap record -- is ADR,
// which moves with the function; only a relocation is an ADRP pair, patched once the
// code's final offsets are known on an image whose code starts on a page (link_elf).
use e.mem
use check
use nir
use regalloc
use emit_x64
use emit_a64
use codegen_x64

const A64_S0: usize = 16usize
const A64_S1: usize = 17usize
const A64_S2: usize = 15usize
const A64_FAR: usize = 8usize
const A64_FP: usize = 29usize
const A64_LINK: usize = 30usize
const A64_STACK: usize = 31usize
const A64_ZERO: usize = 31usize
const A64_CLOBBERED: usize = 6usize

fn register_pool_count() -> usize { ret 16usize }

fn pool_register(index: usize) -> (usize, err) {
    if index < 6usize { ret (9usize + index, ok) }
    if index < 16usize { ret (13usize + index, ok) }
    ret (0usize, codegen_x64.Unsupported)
}

// ---------------------------------------------------------------- frame slots

fn slot_load(output: *emit_x64.Buffer, rt: usize, slot: usize) -> err {
    let offset = (slot + 1usize) * 8usize
    if offset <= 256usize { ret emit_a64.load_below(output, rt, A64_FP, offset, 8usize, false) }
    try emit_a64.sub_immediate(output, A64_FAR, A64_FP, offset)
    ret emit_a64.load_offset(output, rt, A64_FAR, 0usize, 8usize, false)
}

fn slot_store(output: *emit_x64.Buffer, rt: usize, slot: usize) -> err {
    let offset = (slot + 1usize) * 8usize
    if offset <= 256usize { ret emit_a64.store_below(output, rt, A64_FP, offset, 8usize) }
    try emit_a64.sub_immediate(output, A64_FAR, A64_FP, offset)
    ret emit_a64.store_offset(output, rt, A64_FAR, 0usize, 8usize)
}

fn slot_address(output: *emit_x64.Buffer, rd: usize, slot: usize) -> err {
    ret emit_a64.sub_immediate(output, rd, A64_FP, (slot + 1usize) * 8usize)
}

fn read_value(allocations: []regalloc.Allocation, value: usize, scratch: usize, output: *emit_x64.Buffer) -> (usize, err) {
    if value >= allocations.len { ret (0usize, codegen_x64.Unsupported) }
    let allocation = allocations[value]
    if allocation.kind == .Register {
        let (physical, physical_error) = pool_register(allocation.index)
        ret (physical, physical_error)
    }
    if allocation.kind != .Stack { ret (0usize, codegen_x64.Unsupported) }
    let load_error = slot_load(output, scratch, allocation.index)
    ret (scratch, load_error)
}

// The value in exactly `register`.
fn read_into(allocations: []regalloc.Allocation, value: usize, register: usize, output: *emit_x64.Buffer) -> err {
    let (source, source_error) = read_value(allocations, value, register, output)
    if source_error != ok { ret source_error }
    if source != register { ret emit_a64.move_register(output, register, source) }
    ret ok
}

fn result_register(allocations: []regalloc.Allocation, value: usize, scratch: usize) -> (usize, err) {
    if value >= allocations.len { ret (0usize, codegen_x64.Unsupported) }
    if allocations[value].kind == .Stack { ret (scratch, ok) }
    if allocations[value].kind != .Register { ret (0usize, codegen_x64.Unsupported) }
    let (physical, physical_error) = pool_register(allocations[value].index)
    ret (physical, physical_error)
}

fn store_result(allocations: []regalloc.Allocation, value: usize, source: usize, output: *emit_x64.Buffer) -> err {
    if value >= allocations.len { ret codegen_x64.Unsupported }
    if allocations[value].kind == .Stack { ret slot_store(output, source, allocations[value].index) }
    ret ok
}

fn frame_prologue(output: *emit_x64.Buffer, frame_bytes: usize) -> err {
    try emit_a64.store_pair_pre(output, A64_FP, A64_LINK, A64_STACK, 16usize)
    try emit_a64.add_immediate(output, A64_FP, A64_STACK, 0usize)
    if frame_bytes != 0usize { try emit_a64.sub_immediate(output, A64_STACK, A64_STACK, frame_bytes) }
    ret ok
}

fn frame_epilogue(output: *emit_x64.Buffer) -> err {
    try emit_a64.add_immediate(output, A64_STACK, A64_FP, 0usize)
    try emit_a64.load_pair_post(output, A64_FP, A64_LINK, A64_STACK, 16usize)
    ret emit_a64.return_link(output)
}

// How many of the callee-saved registers the values use, counted from the first.
fn kept_count(allocations: []regalloc.Allocation, value_count: usize) -> usize {
    var highest = 0usize
    var value = 0usize
    while value < value_count && value < allocations.len {
        let allocation = allocations[value]
        if allocation.kind == .Register && allocation.index >= A64_CLOBBERED && allocation.index + 1usize - A64_CLOBBERED > highest { highest = allocation.index + 1usize - A64_CLOBBERED }
        value += 1usize
    }
    ret highest
}

fn save_kept(output: *emit_x64.Buffer, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        let (physical, physical_error) = pool_register(A64_CLOBBERED + at)
        if physical_error != ok { ret physical_error }
        try slot_store(output, physical, base + at)
        at += 1usize
    }
    ret ok
}

fn restore_kept(output: *emit_x64.Buffer, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        let (physical, physical_error) = pool_register(A64_CLOBBERED + at)
        if physical_error != ok { ret physical_error }
        try slot_load(output, physical, base + at)
        at += 1usize
    }
    ret ok
}

// The clobbered registers a call's mask names, into and out of the preserve area.
fn save_masked(output: *emit_x64.Buffer, mask: usize, base: usize) -> err {
    let clobbered = A64_CLOBBERED
    var at = 0usize
    while at < clobbered {
        if (mask >> at) & 1usize == 1usize {
            let (physical, physical_error) = pool_register(at)
            if physical_error != ok { ret physical_error }
            try slot_store(output, physical, base + at)
        }
        at += 1usize
    }
    ret ok
}

fn restore_masked(output: *emit_x64.Buffer, mask: usize, base: usize) -> err {
    let clobbered = A64_CLOBBERED
    var at = 0usize
    while at < clobbered {
        if (mask >> at) & 1usize == 1usize {
            let (physical, physical_error) = pool_register(at)
            if physical_error != ok { ret physical_error }
            try slot_load(output, physical, base + at)
        }
        at += 1usize
    }
    ret ok
}

fn normalize(output: *emit_x64.Buffer, rd: usize, rn: usize, ty: check.Type) -> err {
    if ty.kind != .Integer {
        if rd != rn { ret emit_a64.move_register(output, rd, rn) }
        ret ok
    }
    ret emit_a64.extend_integer(output, rd, rn, codegen_x64.integer_width(ty), codegen_x64.signed_integer(ty))
}

// Padding to the next instruction after inline bytes.
fn pad_words(output: *emit_x64.Buffer) -> err {
    while output.count % 4usize != 0usize { try emit_x64.byte(output, 0usize) }
    ret ok
}

// ---------------------------------------------------------------- memory blocks

// `n` bytes from [x1] to [x0], forwards, through x2 and x3. Up to eight words are
// unrolled; past that a word loop, then the tail.
fn copy_block(output: *emit_x64.Buffer, n: usize) -> err {
    let words = n / 8usize
    var tail_at = 0usize
    if words <= 8usize {
        var at = 0usize
        while at < words {
            try emit_a64.load_offset(output, 3usize, 1usize, at * 8usize, 8usize, false)
            try emit_a64.store_offset(output, 3usize, 0usize, at * 8usize, 8usize)
            at += 1usize
        }
        tail_at = words * 8usize
    } else {
        try emit_a64.move_constant(output, 2usize, words)
        let top = output.count
        try emit_a64.load_offset(output, 3usize, 1usize, 0usize, 8usize, false)
        try emit_a64.store_offset(output, 3usize, 0usize, 0usize, 8usize)
        try emit_a64.add_immediate(output, 1usize, 1usize, 8usize)
        try emit_a64.add_immediate(output, 0usize, 0usize, 8usize)
        try emit_a64.sub_immediate(output, 2usize, 2usize, 1usize)
        let (back, back_error) = emit_a64.branch_zero(output, 2usize, true)
        if back_error != ok { ret back_error }
        try emit_a64.patch_relative(output, back, top)
    }
    var byte_at = 0usize
    while byte_at < n % 8usize {
        try emit_a64.load_offset(output, 3usize, 1usize, tail_at + byte_at, 1usize, false)
        try emit_a64.store_offset(output, 3usize, 0usize, tail_at + byte_at, 1usize)
        byte_at += 1usize
    }
    ret ok
}

// `n` zero bytes at [x0], through x2.
fn zero_block(output: *emit_x64.Buffer, n: usize) -> err {
    let words = n / 8usize
    var tail_at = 0usize
    if words <= 8usize {
        var at = 0usize
        while at < words {
            try emit_a64.store_offset(output, A64_ZERO, 0usize, at * 8usize, 8usize)
            at += 1usize
        }
        tail_at = words * 8usize
    } else {
        try emit_a64.move_constant(output, 2usize, words)
        let top = output.count
        try emit_a64.store_offset(output, A64_ZERO, 0usize, 0usize, 8usize)
        try emit_a64.add_immediate(output, 0usize, 0usize, 8usize)
        try emit_a64.sub_immediate(output, 2usize, 2usize, 1usize)
        let (back, back_error) = emit_a64.branch_zero(output, 2usize, true)
        if back_error != ok { ret back_error }
        try emit_a64.patch_relative(output, back, top)
    }
    var byte_at = 0usize
    while byte_at < n % 8usize {
        try emit_a64.store_offset(output, A64_ZERO, 0usize, tail_at + byte_at, 1usize)
        byte_at += 1usize
    }
    ret ok
}

// ---------------------------------------------------------------- traps

// Section 11's trap protocol on this target: the operands in x2 and x3, the site's
// `line << 16 | column` in x1, and a BL to the module's shared stub for the path and
// message (D927), which loads the path's record into x0, the message's into x4 and
// the symbol table into x5 and branches to `neper_trap` -- so x30 is still the site.
// Without the builder's storage for a stub, the records are laid in the function,
// jumped over, and the site loads all three and calls `neper_trap` itself.
fn emit_trap(builder: *nir.Builder, current: nir.Function, site: nir.Site, token_path: str, kind: str, first: str, second: str, third: str, values: usize, signed: bool, a: usize, b: usize, tail: str, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    var path_pieces: [1]codegen_x64.TrapPiece = zero
    var message: [9]codegen_x64.TrapPiece = zero
    let count = codegen_x64.trap_pieces(current, token_path, kind, first, second, third, values, signed, tail, path_pieces[..], message[..])
    if values >= 1usize && a != 2usize {
        if values >= 2usize && b == 2usize {
            // The second operand sits where the first goes: move it out first.
            try emit_a64.move_register(output, 3usize, b)
            try emit_a64.move_register(output, 2usize, a)
        } else {
            try emit_a64.move_register(output, 2usize, a)
            if values >= 2usize && b != 3usize { try emit_a64.move_register(output, 3usize, b) }
        }
    } else {
        if values >= 2usize && b != 3usize { try emit_a64.move_register(output, 3usize, b) }
    }
    var column = site.column
    if column > 65535usize { column = 65535usize }
    try emit_a64.move_constant(output, 1usize, site.line * 65536usize + column)
    let (stub_ref, is_shared, shared_error) = codegen_x64.trap_shared_stub(builder, current, path_pieces[0usize..1usize], message[0usize..count], 0usize)
    if shared_error != ok { ret shared_error }
    if is_shared {
        let (call_at, call_error) = emit_a64.branch_link(output)
        if call_error != ok { ret call_error }
        ret codegen_x64.add_relocation(context.relocations, context.relocation_count, call_at, stub_ref)
    }
    let (path_record, path_error) = trap_record(context, path_pieces[0usize..1usize])
    if path_error != ok { ret path_error }
    let (message_record, message_error) = trap_record(context, message[0usize..count])
    if message_error != ok { ret message_error }
    let (path_at, path_address_error) = emit_a64.address_near(output, 0usize)
    if path_address_error != ok { ret path_address_error }
    try emit_a64.patch_relative(output, path_at, path_record)
    let (message_at, message_address_error) = emit_a64.address_near(output, 4usize)
    if message_address_error != ok { ret message_address_error }
    try emit_a64.patch_relative(output, message_at, message_record)
    let (symbols_ref, symbols_error) = nir.intern_function(builder, current.module_index, "neper_symbols", 0usize)
    if symbols_error != ok { ret symbols_error }
    let (symbols_at, symbols_address_error) = emit_a64.address_far(output, 5usize)
    if symbols_address_error != ok { ret symbols_address_error }
    try codegen_x64.add_relocation(context.relocations, context.relocation_count, symbols_at, symbols_ref)
    let (trap_ref, trap_ref_error) = nir.intern_function(builder, current.module_index, "neper_trap", 0usize)
    if trap_ref_error != ok { ret trap_ref_error }
    let (enter_at, enter_error) = emit_a64.branch_link(output)
    if enter_error != ok { ret enter_error }
    ret codegen_x64.add_relocation(context.relocations, context.relocation_count, enter_at, trap_ref)
}

// A record laid in the function, jumped over, or the earlier copy holding the same
// pieces (D922).
fn trap_record(context: *codegen_x64.FunctionContext, pieces: []const codegen_x64.TrapPiece) -> (usize, err) {
    let output = context.output
    let length = codegen_x64.trap_pieces_length(pieces)
    if length >= 65536usize { ret (0usize, codegen_x64.Unsupported) }
    var at = 0usize
    while at < context.trap_record_count {
        if codegen_x64.trap_record_matches(output, context.trap_records[at], pieces, length) { ret (context.trap_records[at], ok) }
        at += 1usize
    }
    let (skip, skip_error) = emit_a64.branch(output)
    if skip_error != ok { ret (0usize, skip_error) }
    let offset = output.count
    let low_error = emit_x64.byte(output, length % 256usize)
    if low_error != ok { ret (0usize, low_error) }
    let high_error = emit_x64.byte(output, length / 256usize)
    if high_error != ok { ret (0usize, high_error) }
    at = 0usize
    while at < pieces.len {
        var piece_error: err = ok
        if pieces[at].is_single {
            piece_error = emit_x64.byte(output, pieces[at].single)
        } else {
            piece_error = codegen_x64.emit_text(output, pieces[at].text)
        }
        if piece_error != ok { ret (0usize, piece_error) }
        at += 1usize
    }
    let pad_error = pad_words(output)
    if pad_error != ok { ret (0usize, pad_error) }
    let patch_error = emit_a64.patch_relative(output, skip, output.count)
    if patch_error != ok { ret (0usize, patch_error) }
    if context.trap_record_count < context.trap_records.len {
        context.trap_records[context.trap_record_count] = offset
        context.trap_record_count += 1usize
    }
    ret (offset, ok)
}

// `b.cond over; <trap>; over:` -- the check passes when `condition` holds.
fn emit_guarded_trap(builder: *nir.Builder, current: nir.Function, site: nir.Site, token_path: str, condition: usize, kind: str, first: str, second: str, third: str, values: usize, signed: bool, a: usize, b: usize, tail: str, context: *codegen_x64.FunctionContext) -> err {
    let (over, over_error) = emit_a64.branch_condition(context.output, condition)
    if over_error != ok { ret over_error }
    try emit_trap(builder, current, site, token_path, kind, first, second, third, values, signed, a, b, tail, context)
    ret emit_a64.patch_relative(context.output, over, context.output.count)
}

// `cmp a, b`, then the trap with both as its operands unless `condition` holds.
fn emit_checked(builder: *nir.Builder, current: nir.Function, site: nir.Site, token_path: str, condition: usize, kind: str, first: str, second: str, third: str, a: usize, b: usize, context: *codegen_x64.FunctionContext) -> err {
    try emit_a64.compare_register(context.output, a, b)
    ret emit_guarded_trap(builder, current, site, token_path, condition, kind, first, second, third, 2usize, false, a, b, "", context)
}

// The `overflow` row below 64 bits: the exact 64-bit result in `destination` has to be
// its own normalisation.
fn emit_fits_check(builder: *nir.Builder, current: nir.Function, site: nir.Site, token_path: str, ty: check.Type, operator: str, destination: usize, context: *codegen_x64.FunctionContext) -> err {
    try normalize(context.output, A64_S2, destination, ty)
    try emit_a64.compare_register(context.output, A64_S2, destination)
    ret emit_guarded_trap(builder, current, site, token_path, emit_a64.A64_EQ, "overflow", ty.name, "", "", 0usize, false, 0usize, 0usize, operator, context)
}

// A trap's shared stub (D927): the two records and the symbol table, then a branch
// into `neper_trap` with x30 still the site's.
fn emit_trap_stub(builder: *nir.Builder, current: nir.Function, stub: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    if stub.immediate != 0usize { ret codegen_x64.Unsupported }
    let (path_at, path_error) = emit_a64.address_far(output, 0usize)
    if path_error != ok { ret path_error }
    try codegen_x64.add_relocation(context.relocations, context.relocation_count, path_at, stub.target)
    let (message_at, message_error) = emit_a64.address_far(output, 4usize)
    if message_error != ok { ret message_error }
    try codegen_x64.add_relocation(context.relocations, context.relocation_count, message_at, stub.target2)
    let (symbols_ref, symbols_error) = nir.intern_function(builder, current.module_index, "neper_symbols", 0usize)
    if symbols_error != ok { ret symbols_error }
    let (symbols_at, symbols_address_error) = emit_a64.address_far(output, 5usize)
    if symbols_address_error != ok { ret symbols_address_error }
    try codegen_x64.add_relocation(context.relocations, context.relocation_count, symbols_at, symbols_ref)
    let (trap_ref, trap_error) = nir.intern_function(builder, current.module_index, "neper_trap", 0usize)
    if trap_error != ok { ret trap_error }
    let (enter_at, enter_error) = emit_a64.branch(output)
    if enter_error != ok { ret enter_error }
    ret codegen_x64.add_relocation(context.relocations, context.relocation_count, enter_at, trap_ref)
}

// ---------------------------------------------------------------- integer operations

fn comparison_condition(opcode: nir.Opcode, unsigned: bool) -> (usize, err) {
    if opcode == .Equal { ret (emit_a64.A64_EQ, ok) }
    if opcode == .NotEqual { ret (emit_a64.A64_NE, ok) }
    if opcode == .Less {
        if unsigned { ret (emit_a64.A64_LO, ok) }
        ret (emit_a64.A64_LT, ok)
    }
    if opcode == .LessEqual {
        if unsigned { ret (emit_a64.A64_LS, ok) }
        ret (emit_a64.A64_LE, ok)
    }
    if opcode == .Greater {
        if unsigned { ret (emit_a64.A64_HI, ok) }
        ret (emit_a64.A64_GT, ok)
    }
    if opcode == .GreaterEqual {
        if unsigned { ret (emit_a64.A64_HS, ok) }
        ret (emit_a64.A64_GE, ok)
    }
    ret (0usize, codegen_x64.Unsupported)
}

// `+ - *` with and without the check, the bitwise three, and the comparisons, which
// set the flags for a branch that follows them alone (D237) or a bool otherwise.
fn select_binary(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, at: usize, end: usize, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
    let left_value = builder.operands[instruction.first_operand]
    let right_value = builder.operands[instruction.first_operand + 1usize]
    let (left, left_error) = read_value(allocations, left_value, A64_S0, output)
    if left_error != ok { ret left_error }
    let (right, right_error) = read_value(allocations, right_value, A64_S1, output)
    if right_error != ok { ret right_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    let opcode = instruction.opcode
    if codegen_x64.comparison(opcode) {
        let (operand_type, operand_type_error) = codegen_x64.value_type(builder, current, left_value)
        if operand_type_error != ok { ret operand_type_error }
        let unsigned = operand_type.kind == .Integer && operand_type.name.len > 0usize && operand_type.name[0usize] == 117u8
        let (condition, condition_error) = comparison_condition(opcode, unsigned)
        if condition_error != ok { ret condition_error }
        try emit_a64.compare_register(output, left, right)
        var fuse = false
        if at + 1usize < end && instruction.result < context.ranges.len && context.ranges[instruction.result].first == at && context.ranges[instruction.result].last == at + 1usize {
            let next = builder.instructions[at + 1usize]
            if next.opcode == .BranchIf && next.operand_count == 1usize && builder.operands[next.first_operand] == instruction.result { fuse = true }
        }
        if fuse {
            context.fused = true
            context.fused_value = instruction.result
            context.fused_condition = condition
            ret ok
        }
        try emit_a64.set_condition(output, destination, condition)
        ret store_result(allocations, instruction.result, destination, output)
    }
    let integer = instruction.ty.kind == .Integer
    let checked = integer && !instruction.nocheck && !builder.release && (opcode == .Add || opcode == .Subtract || opcode == .Multiply)
    let width = codegen_x64.integer_width(instruction.ty)
    let signed = codegen_x64.signed_integer(instruction.ty)
    var operator = " + overflows"
    if opcode == .Subtract { operator = " - overflows" }
    if opcode == .Multiply { operator = " * overflows" }
    if checked && width == 64usize {
        // At 64 bits the flags say: V for a signed operation, C for an unsigned one; a
        // multiply compares its high half with the low half's sign.
        if opcode == .Multiply {
            if signed { try emit_a64.smulh_register(output, A64_S2, left, right) } else { try emit_a64.umulh_register(output, A64_S2, left, right) }
            try emit_a64.mul_register(output, destination, left, right)
            if signed {
                try emit_a64.compare_sign_of(output, A64_S2, destination)
                try emit_guarded_trap(builder, current, instruction.site, instruction.path, emit_a64.A64_EQ, "overflow", instruction.ty.name, "", "", 0usize, false, 0usize, 0usize, operator, context)
            } else {
                let (over, over_error) = emit_a64.branch_zero(output, A64_S2, false)
                if over_error != ok { ret over_error }
                try emit_trap(builder, current, instruction.site, instruction.path, "overflow", instruction.ty.name, "", "", 0usize, false, 0usize, 0usize, operator, context)
                try emit_a64.patch_relative(output, over, output.count)
            }
        } else {
            var condition = emit_a64.A64_VC
            if opcode == .Add {
                try emit_a64.adds_register(output, destination, left, right)
                if !signed { condition = emit_a64.A64_LO }
            } else {
                try emit_a64.subs_register(output, destination, left, right)
                if !signed { condition = emit_a64.A64_HS }
            }
            try emit_guarded_trap(builder, current, instruction.site, instruction.path, condition, "overflow", instruction.ty.name, "", "", 0usize, false, 0usize, 0usize, operator, context)
        }
        ret store_result(allocations, instruction.result, destination, output)
    }
    if opcode == .Add || opcode == .AddWrap { try emit_a64.add_register(output, destination, left, right) }
    if opcode == .Subtract || opcode == .SubtractWrap { try emit_a64.sub_register(output, destination, left, right) }
    if opcode == .Multiply || opcode == .MultiplyWrap { try emit_a64.mul_register(output, destination, left, right) }
    if opcode == .BitAnd { try emit_a64.and_register(output, destination, left, right) }
    if opcode == .BitXor { try emit_a64.eor_register(output, destination, left, right) }
    if opcode == .BitOr { try emit_a64.orr_register(output, destination, left, right) }
    if checked {
        // Below 64 bits the operands are extended, so the 64-bit result is exact.
        try emit_fits_check(builder, current, instruction.site, instruction.path, instruction.ty, operator, destination, context)
    } else {
        if integer { try normalize(output, destination, destination, instruction.ty) }
    }
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_shift(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret codegen_x64.Unsupported }
    let left_value = builder.operands[instruction.first_operand]
    let right_value = builder.operands[instruction.first_operand + 1usize]
    let (left_type, left_type_error) = codegen_x64.value_type(builder, current, left_value)
    if left_type_error != ok || left_type.kind != .Integer { ret codegen_x64.Unsupported }
    let width = codegen_x64.integer_width(left_type)
    let (left, left_error) = read_value(allocations, left_value, A64_S0, output)
    if left_error != ok { ret left_error }
    let (count, count_error) = read_value(allocations, right_value, A64_S1, output)
    if count_error != ok { ret count_error }
    if !instruction.nocheck && !builder.release {
        try emit_a64.move_constant(output, A64_S2, width)
        try emit_checked(builder, current, instruction.site, instruction.path, emit_a64.A64_LO, "shift", "shift by ", " on a width of ", "", count, A64_S2, context)
    }
    try emit_a64.move_constant(output, A64_S2, width - 1usize)
    try emit_a64.and_register(output, A64_S2, count, A64_S2)
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    if instruction.opcode == .ShiftLeft {
        try emit_a64.lslv_register(output, destination, left, A64_S2)
    } else {
        if codegen_x64.signed_integer(left_type) { try emit_a64.asrv_register(output, destination, left, A64_S2) } else { try emit_a64.lsrv_register(output, destination, left, A64_S2) }
    }
    try normalize(output, destination, destination, instruction.ty)
    ret store_result(allocations, instruction.result, destination, output)
}

// Section 11's `divide` rows trap in every mode: a zero divisor, and the one division
// two's complement cannot represent. Below 64 bits the operands are extended, so the
// 64-bit division is the narrow one.
fn select_divide(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret codegen_x64.Unsupported }
    let left_value = builder.operands[instruction.first_operand]
    let right_value = builder.operands[instruction.first_operand + 1usize]
    let (left_type, left_type_error) = codegen_x64.value_type(builder, current, left_value)
    if left_type_error != ok || left_type.kind != .Integer { ret codegen_x64.Unsupported }
    let signed = codegen_x64.signed_integer(left_type)
    let width = codegen_x64.integer_width(left_type)
    let remainder = instruction.opcode == .Remainder
    var operator = " / "
    if remainder { operator = " % " }
    let (left, left_error) = read_value(allocations, left_value, A64_S0, output)
    if left_error != ok { ret left_error }
    let (right, right_error) = read_value(allocations, right_value, A64_S1, output)
    if right_error != ok { ret right_error }
    let (nonzero, nonzero_error) = emit_a64.branch_zero(output, right, true)
    if nonzero_error != ok { ret nonzero_error }
    try emit_trap(builder, current, instruction.site, instruction.path, "divide", "", operator, " divides by zero", 2usize, signed, left, right, "", context)
    try emit_a64.patch_relative(output, nonzero, output.count)
    if signed {
        try emit_a64.movn(output, A64_S2, 0usize, 0usize)
        try emit_a64.compare_register(output, right, A64_S2)
        let (not_minus_one, minus_one_error) = emit_a64.branch_condition(output, emit_a64.A64_NE)
        if minus_one_error != ok { ret minus_one_error }
        let all_ones = 0usize -% 1usize
        try emit_a64.move_constant(output, A64_S2, all_ones - (all_ones >> (65usize - width)))
        try emit_a64.compare_register(output, left, A64_S2)
        let (not_minimum, minimum_error) = emit_a64.branch_condition(output, emit_a64.A64_NE)
        if minimum_error != ok { ret minimum_error }
        try emit_trap(builder, current, instruction.site, instruction.path, "divide", "", operator, " overflows", 2usize, true, left, right, "", context)
        try emit_a64.patch_relative(output, not_minus_one, output.count)
        try emit_a64.patch_relative(output, not_minimum, output.count)
    }
    if signed { try emit_a64.sdiv_register(output, A64_S2, left, right) } else { try emit_a64.udiv_register(output, A64_S2, left, right) }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    if remainder {
        try emit_a64.msub_register(output, destination, A64_S2, right, left)
    } else {
        try emit_a64.move_register(output, destination, A64_S2)
    }
    try normalize(output, destination, destination, instruction.ty)
    ret store_result(allocations, instruction.result, destination, output)
}

// Cast, unary minus and `~` on integers.
fn select_unary(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.operand_count != 1usize || instruction.ty.kind != .Integer { ret codegen_x64.Unsupported }
    let operand_value = builder.operands[instruction.first_operand]
    let (source_type, source_type_error) = codegen_x64.value_type(builder, current, operand_value)
    if source_type_error != ok { ret codegen_x64.Unsupported }
    let named_source = source_type.kind == .Named && instruction.opcode == .Cast
    if source_type.kind != .Integer && !named_source { ret codegen_x64.Unsupported }
    let (source, source_error) = read_value(allocations, operand_value, A64_S0, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S1)
    if destination_error != ok { ret destination_error }
    if instruction.opcode == .Cast {
        var normalize_type = instruction.ty
        if source_type.kind == .Integer && codegen_x64.integer_width(normalize_type) == 64usize { normalize_type = source_type }
        // Section 11's `narrow` row: the value has to come back unchanged; the source is
        // kept in x15 since the result may land in its register.
        let sign_differs = codegen_x64.signed_integer(source_type) != codegen_x64.signed_integer(instruction.ty)
        let narrowing = source_type.kind == .Integer && instruction.immediate == 0usize && !instruction.nocheck && !builder.release && (codegen_x64.integer_width(instruction.ty) < codegen_x64.integer_width(source_type) || sign_differs)
        if narrowing { try emit_a64.move_register(output, A64_S2, source) }
        try normalize(output, destination, source, normalize_type)
        if narrowing {
            var fits = 0usize
            if codegen_x64.integer_width(instruction.ty) == 64usize {
                try emit_a64.compare_immediate(output, A64_S2, 0usize)
                let (not_negative, sign_error) = emit_a64.branch_condition(output, emit_a64.A64_PL)
                if sign_error != ok { ret sign_error }
                fits = not_negative
            } else {
                try emit_a64.compare_register(output, destination, A64_S2)
                let (equal, equal_error) = emit_a64.branch_condition(output, emit_a64.A64_EQ)
                if equal_error != ok { ret equal_error }
                fits = equal
            }
            try emit_trap(builder, current, instruction.site, instruction.path, "narrow", "", " does not fit ", "", 1usize, codegen_x64.signed_integer(source_type), A64_S2, 0usize, instruction.ty.name, context)
            try emit_a64.patch_relative(output, fits, output.count)
        }
        ret store_result(allocations, instruction.result, destination, output)
    }
    let negated = instruction.opcode == .Negate && codegen_x64.signed_integer(instruction.ty) && !instruction.nocheck && !builder.release
    if instruction.opcode == .Negate {
        if negated && codegen_x64.integer_width(instruction.ty) == 64usize {
            try emit_a64.subs_register(output, destination, A64_ZERO, source)
            try emit_guarded_trap(builder, current, instruction.site, instruction.path, emit_a64.A64_VC, "overflow", instruction.ty.name, "", "", 0usize, false, 0usize, 0usize, " unary - overflows", context)
            ret store_result(allocations, instruction.result, destination, output)
        }
        try emit_a64.negate_register(output, destination, source)
    } else {
        try emit_a64.not_register(output, destination, source)
    }
    if negated {
        try emit_fits_check(builder, current, instruction.site, instruction.path, instruction.ty, " unary - overflows", destination, context)
    } else {
        try normalize(output, destination, destination, instruction.ty)
    }
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_index_address(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if !instruction.has_result || instruction.operand_count != 3usize || instruction.immediate == 0usize { ret codegen_x64.Unsupported }
    let (base, base_error) = read_value(allocations, builder.operands[instruction.first_operand], A64_S0, output)
    if base_error != ok { ret base_error }
    let (index, index_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
    if index_error != ok { ret index_error }
    if !instruction.nocheck {
        let (length, length_error) = read_value(allocations, builder.operands[instruction.first_operand + 2usize], 0usize, output)
        if length_error != ok { ret length_error }
        try emit_checked(builder, current, instruction.site, instruction.path, emit_a64.A64_LO, "bounds", "index ", " out of bounds for len ", "", index, length, context)
    }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    try scaled_address(output, destination, base, index, instruction.immediate)
    ret store_result(allocations, instruction.result, destination, output)
}

// rd = base + index * size.
fn scaled_address(output: *emit_x64.Buffer, rd: usize, base: usize, index: usize, size: usize) -> err {
    var shift = 0usize
    while shift < 63usize && (1usize << shift) < size { shift += 1usize }
    if (1usize << shift) == size { ret emit_a64.add_shifted(output, rd, base, index, shift) }
    try emit_a64.move_constant(output, A64_S2, size)
    ret emit_a64.madd_register(output, rd, index, A64_S2, base)
}

fn select_slice(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.has_result || instruction.operand_count != 5usize || instruction.immediate == 0usize { ret codegen_x64.Unsupported }
    try read_into(allocations, builder.operands[instruction.first_operand], 4usize, output)
    try read_into(allocations, builder.operands[instruction.first_operand + 1usize], 5usize, output)
    try read_into(allocations, builder.operands[instruction.first_operand + 2usize], 6usize, output)
    try read_into(allocations, builder.operands[instruction.first_operand + 3usize], 0usize, output)
    try read_into(allocations, builder.operands[instruction.first_operand + 4usize], 1usize, output)
    if !instruction.nocheck {
        try emit_checked(builder, current, instruction.site, instruction.path, emit_a64.A64_LS, "bounds", "slice start ", " after end ", "", 0usize, 1usize, context)
        try emit_checked(builder, current, instruction.site, instruction.path, emit_a64.A64_LS, "bounds", "slice end ", " out of bounds for len ", "", 1usize, 6usize, context)
    }
    try emit_a64.sub_register(output, 1usize, 1usize, 0usize)
    try scaled_address(output, 5usize, 5usize, 0usize, instruction.immediate)
    try emit_a64.store_offset(output, 5usize, 4usize, 0usize, 8usize)
    ret emit_a64.store_offset(output, 1usize, 4usize, 8usize, 8usize)
}

// A string's bytes laid in the code, jumped over, and a slice of them in its two slots.
fn select_string(builder: *nir.Builder, instruction: nir.Instruction, slot: usize, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if !instruction.has_result || instruction.operand_count != 0usize || instruction.immediate >= builder.string_count { ret codegen_x64.Unsupported }
    let (skip, skip_error) = emit_a64.branch(output)
    if skip_error != ok { ret skip_error }
    let data_offset = output.count
    let (length, data_error) = codegen_x64.emit_string_bytes(output, builder.strings[instruction.immediate].spelling)
    if data_error != ok { ret data_error }
    try pad_words(output)
    try emit_a64.patch_relative(output, skip, output.count)
    let (data_at, data_address_error) = emit_a64.address_near(output, A64_S1)
    if data_address_error != ok { ret data_address_error }
    try emit_a64.patch_relative(output, data_at, data_offset)
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    try slot_address(output, destination, slot)
    try emit_a64.store_offset(output, A64_S1, destination, 0usize, 8usize)
    try emit_a64.move_constant(output, A64_S1, length)
    try emit_a64.store_offset(output, A64_S1, destination, 8usize, 8usize)
    ret store_result(allocations, instruction.result, destination, output)
}

// ---------------------------------------------------------------- floats

// Section 11's canonical NaN: an operation that produced a NaN in v16 leaves the one
// positive quiet NaN of its width there instead.
fn canonicalize_nan(output: *emit_x64.Buffer, double: bool) -> err {
    var width = 32usize
    if double { width = 64usize }
    try emit_a64.float_compare(output, A64_S0, A64_S0, double)
    let (ordered, ordered_error) = emit_a64.branch_condition(output, emit_a64.A64_VC)
    if ordered_error != ok { ret ordered_error }
    try emit_a64.move_constant(output, A64_S2, codegen_x64.canonical_nan(width))
    try emit_a64.move_to_float(output, A64_S0, A64_S2, double)
    ret emit_a64.patch_relative(output, ordered, output.count)
}

fn select_float(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, at: usize, end: usize, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if !instruction.has_result { ret codegen_x64.Unsupported }
    let opcode = instruction.opcode
    if opcode == .Cast { ret select_float_cast(builder, current, instruction, context) }
    if codegen_x64.comparison(opcode) {
        if instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
        let left_value = builder.operands[instruction.first_operand]
        let (operand_type, operand_type_error) = codegen_x64.value_type(builder, current, left_value)
        if operand_type_error != ok { ret operand_type_error }
        let width = codegen_x64.float_width(operand_type)
        if width == 0usize { ret codegen_x64.Unsupported }
        let double = width == 64usize
        let (left, left_error) = read_value(allocations, left_value, A64_S0, output)
        if left_error != ok { ret left_error }
        let (right, right_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
        if right_error != ok { ret right_error }
        try emit_a64.move_to_float(output, A64_S0, left, double)
        try emit_a64.move_to_float(output, A64_S1, right, double)
        try emit_a64.float_compare(output, A64_S0, A64_S1, double)
        // An unordered compare sets C and V: EQ, MI, LS, GT and GE all fail on it,
        // and NE holds -- IEEE's answers.
        var condition = emit_a64.A64_EQ
        if opcode == .NotEqual { condition = emit_a64.A64_NE }
        if opcode == .Less { condition = emit_a64.A64_MI }
        if opcode == .LessEqual { condition = emit_a64.A64_LS }
        if opcode == .Greater { condition = emit_a64.A64_GT }
        if opcode == .GreaterEqual { condition = emit_a64.A64_GE }
        let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
        if destination_error != ok { ret destination_error }
        try emit_a64.set_condition(output, destination, condition)
        ret store_result(allocations, instruction.result, destination, output)
    }
    let width = codegen_x64.float_width(instruction.ty)
    if width == 0usize { ret codegen_x64.Unsupported }
    let double = width == 64usize
    let (left, left_error) = read_value(allocations, builder.operands[instruction.first_operand], A64_S0, output)
    if left_error != ok { ret left_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    if opcode == .Negate {
        // A sign-bit flip, then the canonicalization a NaN gets.
        try emit_a64.move_constant(output, A64_S2, codegen_x64.float_sign_bit(width))
        try emit_a64.eor_register(output, A64_S2, left, A64_S2)
        try emit_a64.move_to_float(output, A64_S0, A64_S2, double)
    } else {
        try emit_a64.move_to_float(output, A64_S0, left, double)
        if opcode == .Sqrt {
            try emit_a64.float_sqrt(output, A64_S0, A64_S0, double)
        } else {
            if instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
            let (right, right_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
            if right_error != ok { ret right_error }
            try emit_a64.move_to_float(output, A64_S1, right, double)
            var operation = 0usize
            if opcode == .Subtract { operation = 1usize }
            if opcode == .Multiply { operation = 2usize }
            if opcode == .Divide { operation = 3usize }
            try emit_a64.float_binary(output, operation, A64_S0, A64_S0, A64_S1, double)
        }
    }
    try canonicalize_nan(output, double)
    try emit_a64.move_from_float(output, destination, A64_S0, double)
    ret store_result(allocations, instruction.result, destination, output)
}

// Between the widths, from an integer, and to one. FCVTZS and FCVTZU already saturate
// and give zero for NaN, which is section 4's release result at 64 bits; a narrower
// target clamps what they give. A debug build checks the range first (section 11's
// `narrow` row): the value must be below the power of two past the top and above the
// bottom bound, and NaN fails both.
fn select_float_cast(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.operand_count != 1usize { ret codegen_x64.Unsupported }
    let source_value = builder.operands[instruction.first_operand]
    let (source_type, source_type_error) = codegen_x64.value_type(builder, current, source_value)
    if source_type_error != ok { ret codegen_x64.Unsupported }
    let (source, source_error) = read_value(allocations, source_value, A64_S1, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
    if destination_error != ok { ret destination_error }
    let source_width = codegen_x64.float_width(source_type)
    let target_width = codegen_x64.float_width(instruction.ty)
    if source_type.kind == .Float && instruction.ty.kind == .Float {
        if source_width == 0usize || target_width == 0usize { ret codegen_x64.Unsupported }
        if source_width == target_width {
            if destination != source { try emit_a64.move_register(output, destination, source) }
            ret store_result(allocations, instruction.result, destination, output)
        }
        try emit_a64.move_to_float(output, A64_S0, source, source_width == 64usize)
        if target_width == 64usize { try emit_a64.float_widen(output, A64_S0, A64_S0) } else { try emit_a64.float_narrow(output, A64_S0, A64_S0) }
        try canonicalize_nan(output, target_width == 64usize)
        try emit_a64.move_from_float(output, destination, A64_S0, target_width == 64usize)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if instruction.ty.kind == .Float {
        if target_width == 0usize || source_type.kind != .Integer { ret codegen_x64.Unsupported }
        // A narrower unsigned value is zero-extended, and a signed one sign-extended, so
        // only a u64 needs the unsigned conversion.
        try emit_a64.float_from_integer(output, A64_S0, source, codegen_x64.unsigned_wide(source_type), target_width == 64usize)
        try emit_a64.move_from_float(output, destination, A64_S0, target_width == 64usize)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if source_width == 0usize || instruction.ty.kind != .Integer { ret codegen_x64.Unsupported }
    let double = source_width == 64usize
    let width = codegen_x64.integer_width(instruction.ty)
    let signed = codegen_x64.signed_integer(instruction.ty)
    try emit_a64.move_to_float(output, A64_S0, source, double)
    if instruction.immediate == 0usize && !instruction.nocheck && !builder.release {
        try emit_a64.move_constant(output, A64_S2, codegen_x64.float_bound_bits(width, signed, true, double))
        try emit_a64.move_to_float(output, A64_S1, A64_S2, double)
        try emit_a64.float_compare(output, A64_S0, A64_S1, double)
        try emit_guarded_trap(builder, current, instruction.site, instruction.path, emit_a64.A64_MI, "narrow", "a float outside ", "", "", 0usize, false, 0usize, 0usize, instruction.ty.name, context)
        try emit_a64.move_constant(output, A64_S2, codegen_x64.float_bound_bits(width, signed, false, double))
        try emit_a64.move_to_float(output, A64_S1, A64_S2, double)
        try emit_a64.float_compare(output, A64_S0, A64_S1, double)
        // Strictly above a bound outside the range; at or above one that is the minimum.
        var condition = emit_a64.A64_GT
        if signed && (width == 64usize || !double) { condition = emit_a64.A64_GE }
        try emit_guarded_trap(builder, current, instruction.site, instruction.path, condition, "narrow", "a float outside ", "", "", 0usize, false, 0usize, 0usize, instruction.ty.name, context)
    }
    try emit_a64.integer_from_float(output, destination, A64_S0, !signed, double)
    if width != 64usize {
        let all_ones = 0usize -% 1usize
        var maximum = all_ones >> (64usize - width)
        if signed { maximum = all_ones >> (65usize - width) }
        try emit_a64.move_constant(output, A64_S2, maximum)
        try emit_a64.compare_register(output, destination, A64_S2)
        if signed {
            try emit_a64.select_condition(output, destination, A64_S2, destination, emit_a64.A64_GT)
            try emit_a64.move_constant(output, A64_S2, all_ones - (all_ones >> (65usize - width)))
            try emit_a64.compare_register(output, destination, A64_S2)
            try emit_a64.select_condition(output, destination, A64_S2, destination, emit_a64.A64_LT)
        } else {
            try emit_a64.select_condition(output, destination, A64_S2, destination, emit_a64.A64_HI)
        }
    }
    try normalize(output, destination, destination, instruction.ty)
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_bitcast(builder: *nir.Builder, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.operand_count != 1usize || !instruction.has_result { ret codegen_x64.Unsupported }
    if instruction.result < context.ranges.len && context.ranges[instruction.result].defined && !context.ranges[instruction.result].used { ret ok }
    let (source, source_error) = read_value(allocations, builder.operands[instruction.first_operand], A64_S0, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S1)
    if destination_error != ok { ret destination_error }
    if codegen_x64.bitcast_scalar(instruction.ty) {
        let width = codegen_x64.bitcast_width(instruction.ty)
        if width == 0usize { ret codegen_x64.Unsupported }
        try emit_a64.extend_integer(output, destination, source, width, codegen_x64.signed_integer(instruction.ty))
    } else {
        if destination != source { try emit_a64.move_register(output, destination, source) }
    }
    ret store_result(allocations, instruction.result, destination, output)
}

// ---------------------------------------------------------------- vectors

// Section 4's lane-wise operator as Advanced SIMD over a vector's 16, 8, 4 or 2 bytes,
// the shapes lowering hands the back end as `VectorBinary` (destination, left and right
// addresses; the immediate packs the operation, the lane shape and the count). The
// operands load into v16 and v17, whole registers whose lanes past the operand are never
// stored. `~` on integer lanes is NOT; on a mask, whose lanes are bytes of 0 or 1, it is
// EOR with ones. Float lanes get section 11's canonical NaN lane by lane: FCMEQ of the
// result with itself marks the ordered lanes, and BIF puts the canonical NaN in the rest.
// A shift by a count the compiler knows is the immediate form; any other is DUP of the
// count, checked and masked as the scalar shift is, into USHL or SSHL, a right shift by
// the negated count. Sixty-four-bit lanes have no vector multiply: `*%` there is done
// lane by lane in general registers.
fn select_vector_binary(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.has_result || instruction.operand_count != 3usize { ret codegen_x64.Unsupported }
    let lane = nir.vector_binary_lane(instruction.immediate)
    let operation = nir.vector_binary_operation(instruction.immediate)
    let lane_bytes = codegen_x64.packed_lane_size(lane)
    let bytes = nir.vector_binary_lanes(instruction.immediate) * lane_bytes
    if bytes != 16usize && bytes != 8usize && bytes != 4usize && bytes != 2usize { ret codegen_x64.Unsupported }
    var size = lane
    if lane == 4usize { size = 2usize }
    if lane == 5usize { size = 3usize }
    let destination_value = builder.operands[instruction.first_operand]
    let left_value = builder.operands[instruction.first_operand + 1usize]
    let right_value = builder.operands[instruction.first_operand + 2usize]
    if operation == 6usize && lane == 3usize {
        try read_into(allocations, left_value, 4usize, output)
        try read_into(allocations, right_value, 5usize, output)
        try read_into(allocations, destination_value, 6usize, output)
        var at = 0usize
        while at < bytes {
            try emit_a64.load_offset(output, 0usize, 4usize, at, 8usize, false)
            try emit_a64.load_offset(output, 1usize, 5usize, at, 8usize, false)
            try emit_a64.mul_register(output, 0usize, 0usize, 1usize)
            try emit_a64.store_offset(output, 0usize, 6usize, at, 8usize)
            at += 8usize
        }
        ret ok
    }
    let (left, left_error) = read_value(allocations, left_value, A64_S0, output)
    if left_error != ok { ret left_error }
    try emit_a64.vector_load(output, 16usize, left, bytes)
    if operation >= 12usize {
        if lane > 3usize { ret codegen_x64.Unsupported }
        if nir.vector_shift_in_register(instruction.immediate) {
            let width = lane_bytes * 8usize
            let (count, count_error) = read_value(allocations, right_value, A64_S1, output)
            if count_error != ok { ret count_error }
            if !instruction.nocheck && !builder.release {
                try emit_a64.move_constant(output, A64_S2, width)
                try emit_checked(builder, current, instruction.site, instruction.path, emit_a64.A64_LO, "shift", "shift by ", " on a width of ", "", count, A64_S2, context)
            }
            try emit_a64.move_constant(output, A64_S2, width - 1usize)
            try emit_a64.and_register(output, A64_S2, count, A64_S2)
            try emit_a64.vector_duplicate(output, size, 17usize, A64_S2)
            if operation != 12usize { try emit_a64.vector_negate(output, size, 17usize, 17usize) }
            var shift_operation = 3usize
            if operation == 14usize { shift_operation = 4usize }
            try emit_a64.vector_three(output, shift_operation, size, 16usize, 16usize, 17usize)
        } else {
            let count = nir.vector_binary_count(instruction.immediate)
            if operation == 12usize { try emit_a64.vector_shift_immediate(output, 0usize, size, 16usize, 16usize, count) }
            if operation != 12usize && count != 0usize {
                var kind = 1usize
                if operation == 14usize { kind = 2usize }
                try emit_a64.vector_shift_immediate(output, kind, size, 16usize, 16usize, count)
            }
        }
    } else {
        if operation < 10usize {
            let (right, right_error) = read_value(allocations, right_value, A64_S1, output)
            if right_error != ok { ret right_error }
            try emit_a64.vector_load(output, 17usize, right, bytes)
        }
        if operation == 10usize { try emit_a64.vector_not(output, 16usize, 16usize) }
        if operation == 11usize {
            try emit_a64.vector_bytes(output, 17usize, 1usize)
            try emit_a64.vector_three(output, 7usize, 0usize, 16usize, 16usize, 17usize)
        }
        if operation <= 3usize {
            if lane < 4usize { ret codegen_x64.Unsupported }
            try emit_a64.vector_three(output, 9usize + operation, size, 16usize, 16usize, 17usize)
            try emit_a64.vector_three(output, 13usize, size, 18usize, 16usize, 16usize)
            var width = 32usize
            if lane == 5usize { width = 64usize }
            try emit_a64.move_constant(output, A64_S2, codegen_x64.canonical_nan(width))
            try emit_a64.vector_duplicate(output, size, 19usize, A64_S2)
            try emit_a64.vector_three(output, 8usize, 0usize, 16usize, 19usize, 18usize)
        }
        if operation == 4usize { try emit_a64.vector_three(output, 0usize, size, 16usize, 16usize, 17usize) }
        if operation == 5usize { try emit_a64.vector_three(output, 1usize, size, 16usize, 16usize, 17usize) }
        if operation == 6usize { try emit_a64.vector_three(output, 2usize, size, 16usize, 16usize, 17usize) }
        if operation == 7usize { try emit_a64.vector_three(output, 5usize, 0usize, 16usize, 16usize, 17usize) }
        if operation == 8usize { try emit_a64.vector_three(output, 6usize, 0usize, 16usize, 16usize, 17usize) }
        if operation == 9usize { try emit_a64.vector_three(output, 7usize, 0usize, 16usize, 16usize, 17usize) }
    }
    let (destination, destination_error) = read_value(allocations, destination_value, A64_S0, output)
    if destination_error != ok { ret destination_error }
    ret emit_a64.vector_store(output, 16usize, destination, bytes)
}

// ---------------------------------------------------------------- atomics

// Section 8's five instructions over ARMv8.1's LSE: a load-acquire, a store-release,
// one read-modify-write with acquire and release each, and CASAL. This target orders
// memory weakly, so every fence is a full barrier. An acquire and release on every
// operation is stronger than a relaxed one needs, never weaker.
fn select_atomic(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    if instruction.opcode == .AtomicFence { ret emit_a64.barrier_full(output) }
    let width = codegen_x64.atomic_width(instruction.ty)
    if width == 0usize { ret codegen_x64.Unsupported }
    let bytes = width / 8usize
    let signed = codegen_x64.signed_integer(instruction.ty)
    let (address, address_error) = read_value(allocations, builder.operands[instruction.first_operand], A64_S0, output)
    if address_error != ok { ret codegen_x64.InvalidMemoryAddress }
    if instruction.opcode == .AtomicStore {
        if instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
        let (value, value_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
        if value_error != ok { ret value_error }
        ret emit_a64.store_release(output, value, address, bytes)
    }
    if !instruction.has_result { ret codegen_x64.Unsupported }
    if instruction.opcode == .AtomicLoad {
        try emit_a64.load_acquire(output, A64_S1, address, bytes)
    } else {
        if instruction.opcode == .AtomicCas {
            if instruction.operand_count != 3usize { ret codegen_x64.Unsupported }
            try read_into(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
            let (desired, desired_error) = read_value(allocations, builder.operands[instruction.first_operand + 2usize], A64_S2, output)
            if desired_error != ok { ret desired_error }
            try emit_a64.compare_swap(output, A64_S1, desired, address, bytes)
        } else {
            if instruction.opcode != .AtomicRmw || instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
            let (operand, operand_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S2, output)
            if operand_error != ok { ret operand_error }
            // nir's kinds: xchg, add, sub, and, or, xor, min, max.
            let kind = instruction.immediate / 8usize
            var operation = 0usize
            var operand_register = operand
            if kind == 1usize { operation = 1usize }
            if kind == 2usize {
                try emit_a64.negate_register(output, A64_S2, operand)
                operand_register = A64_S2
                operation = 1usize
            }
            if kind == 3usize {
                // AND is LDCLR of the complement: clear what the operand does not keep.
                try emit_a64.not_register(output, A64_S2, operand)
                operand_register = A64_S2
                operation = 3usize
            }
            if kind == 4usize { operation = 4usize }
            if kind == 5usize { operation = 5usize }
            if kind == 6usize {
                operation = 8usize
                if signed { operation = 6usize }
            }
            if kind == 7usize {
                operation = 9usize
                if signed { operation = 7usize }
            }
            try emit_a64.atomic_operation(output, operation, operand_register, A64_S1, address, bytes)
        }
    }
    let (destination, destination_error) = result_register(allocations, instruction.result, A64_S1)
    if destination_error != ok { ret destination_error }
    try emit_a64.extend_integer(output, destination, A64_S1, width, signed)
    ret store_result(allocations, instruction.result, destination, output)
}

// ---------------------------------------------------------------- calls

// AAPCS64: integers to x0-x7 and floats to v0-v7, each counted on its own, the rest
// to the stack in order, eight bytes each.
fn stack_argument_count(builder: *nir.Builder, current: nir.Function) -> (usize, err) {
    var most = 0usize
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Call || instruction.opcode == .IndirectCall {
            var first_argument = 0usize
            if instruction.opcode == .IndirectCall { first_argument = 1usize }
            var integers = 0usize
            var floats = 0usize
            var stacked = 0usize
            var operand_at = first_argument
            while operand_at < instruction.operand_count {
                let (operand_type, operand_type_error) = codegen_x64.value_type(builder, current, builder.operands[instruction.first_operand + operand_at])
                if operand_type_error != ok { ret (0usize, operand_type_error) }
                if codegen_x64.float_width(operand_type) != 0usize {
                    if floats < 8usize { floats += 1usize } else { stacked += 1usize }
                } else {
                    if integers < 8usize { integers += 1usize } else { stacked += 1usize }
                }
                operand_at += 1usize
            }
            if stacked > most { most = stacked }
        }
        at += 1usize
    }
    ret (most, ok)
}

fn load_call_arguments(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, first_argument: usize, output: *emit_x64.Buffer, allocations: []regalloc.Allocation) -> err {
    var integers = 0usize
    var floats = 0usize
    var stacked = 0usize
    var at = first_argument
    while at < instruction.operand_count {
        let value = builder.operands[instruction.first_operand + at]
        let (argument_type, argument_type_error) = codegen_x64.value_type(builder, current, value)
        if argument_type_error != ok { ret argument_type_error }
        if codegen_x64.stacked_argument(argument_type) { ret codegen_x64.Unsupported }
        let width = codegen_x64.float_width(argument_type)
        if argument_type.kind == .Float && width == 0usize { ret codegen_x64.Unsupported }
        if width != 0usize && floats < 8usize {
            let (source, source_error) = read_value(allocations, value, A64_S0, output)
            if source_error != ok { ret source_error }
            try emit_a64.move_to_float(output, floats, source, width == 64usize)
            floats += 1usize
        } else {
            if width == 0usize && integers < 8usize {
                try read_into(allocations, value, integers, output)
                integers += 1usize
            } else {
                let (source, source_error) = read_value(allocations, value, A64_S0, output)
                if source_error != ok { ret source_error }
                try emit_a64.store_offset(output, source, A64_STACK, stacked * 8usize, 8usize)
                stacked += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

// Each parameter into its own slot on entry, from x0-x7, v0-v7 or the caller's
// stack above the frame record.
fn store_incoming_parameters(builder: *nir.Builder, current: nir.Function, stack_slots: usize, parameters: usize, output: *emit_x64.Buffer) -> err {
    var integers = 0usize
    var floats = 0usize
    var stacked = 0usize
    var at = 0usize
    while at < parameters {
        let incoming = codegen_x64.parameter_type(builder, current, at)
        if codegen_x64.stacked_argument(incoming) { ret codegen_x64.Unsupported }
        let width = codegen_x64.float_width(incoming)
        if width != 0usize && floats < 8usize {
            try emit_a64.move_from_float(output, A64_S0, floats, width == 64usize)
            try slot_store(output, A64_S0, stack_slots + at)
            floats += 1usize
        } else {
            if width == 0usize && integers < 8usize {
                try slot_store(output, integers, stack_slots + at)
                integers += 1usize
            } else {
                try emit_a64.load_offset(output, A64_S0, A64_FP, 16usize + stacked * 8usize, 8usize, false)
                try slot_store(output, A64_S0, stack_slots + at)
                stacked += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

fn select_call(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, at: usize, preserve_base: usize, context: *codegen_x64.FunctionContext) -> err {
    let output = context.output
    let allocations = context.allocations
    let indirect = instruction.opcode == .IndirectCall
    if !indirect && instruction.immediate >= builder.function_ref_count { ret codegen_x64.Unsupported }
    if indirect && instruction.operand_count == 0usize { ret codegen_x64.Unsupported }
    var first_argument = 0usize
    if indirect { first_argument = 1usize }
    let live_mask = codegen_x64.live_register_mask(context, current.value_count, at, A64_CLOBBERED)
    try save_masked(output, live_mask, preserve_base)
    if indirect { try read_into(allocations, builder.operands[instruction.first_operand], A64_S1, output) }
    try load_call_arguments(builder, current, instruction, first_argument, output, allocations)
    if indirect {
        try emit_a64.branch_link_register(output, A64_S1)
    } else {
        // An imported callee is reached through the slot the loader writes, not by a
        // branch to code in this image; the linker tells the two apart by the reference.
        if builder.function_refs[instruction.immediate].library.len != 0usize {
            let (slot_at, slot_error) = emit_a64.slot_call(output)
            if slot_error != ok { ret slot_error }
            try codegen_x64.add_relocation(context.relocations, context.relocation_count, slot_at, instruction.immediate)
        } else {
            let (call_at, call_error) = emit_a64.branch_link(output)
            if call_error != ok { ret call_error }
            try codegen_x64.add_relocation(context.relocations, context.relocation_count, call_at, instruction.immediate)
        }
    }
    if codegen_x64.result_pair_sse(instruction.ty) != 0usize { ret codegen_x64.Unsupported }
    let multiple_results = instruction.has_result && (instruction.ty.kind == .Invalid || (instruction.ty.kind == .Other && check.same(instruction.ty.name, "return-values")))
    if instruction.has_result {
        let result_float = codegen_x64.float_width(instruction.ty)
        if result_float != 0usize {
            try emit_a64.move_from_float(output, A64_S0, 0usize, result_float == 64usize)
        } else {
            if instruction.ty.kind == .Float { ret codegen_x64.Unsupported }
            // A callee narrower than a register defines only its own bits: widened here.
            try normalize(output, A64_S0, 0usize, instruction.ty)
        }
        if multiple_results { try emit_a64.move_register(output, A64_S1, 1usize) }
    }
    try restore_masked(output, live_mask, preserve_base)
    if instruction.has_result && !multiple_results {
        let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
        if destination_error != ok { ret destination_error }
        let scratch = A64_S0
        if destination != scratch { try emit_a64.move_register(output, destination, scratch) }
        try store_result(allocations, instruction.result, destination, output)
    }
    ret ok
}

// A conditional branch to a block (B.cond, CBZ, CBNZ) reaches a megabyte; a function long
// enough that a block may lie further away branches on the opposite condition over an
// unconditional B, which reaches 128. The answer is the word the block's fixup patches.
// ponytail: decided per function by its instruction count, not by the distance itself.
fn far_function(current: nir.Function) -> bool {
    ret current.instruction_count > 30000usize
}

fn branch_to_block(output: *emit_x64.Buffer, condition: usize, far: bool) -> (usize, err) {
    if !far {
        let (at, near_error) = emit_a64.branch_condition(output, condition)
        ret (at, near_error)
    }
    let (skip, skip_error) = emit_a64.branch_condition(output, emit_a64.invert_condition(condition))
    if skip_error != ok { ret (0usize, skip_error) }
    let (jump, jump_error) = emit_a64.branch(output)
    if jump_error != ok { ret (0usize, jump_error) }
    let patch_error = emit_a64.patch_relative(output, skip, output.count)
    ret (jump, patch_error)
}

fn branch_nonzero_to_block(output: *emit_x64.Buffer, register: usize, far: bool) -> (usize, err) {
    if !far {
        let (at, near_error) = emit_a64.branch_zero(output, register, true)
        ret (at, near_error)
    }
    let (skip, skip_error) = emit_a64.branch_zero(output, register, false)
    if skip_error != ok { ret (0usize, skip_error) }
    let (jump, jump_error) = emit_a64.branch(output)
    if jump_error != ok { ret (0usize, jump_error) }
    let patch_error = emit_a64.patch_relative(output, skip, output.count)
    ret (jump, patch_error)
}

fn has_calls(builder: *nir.Builder, current: nir.Function) -> bool {
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let opcode = builder.instructions[at].opcode
        if opcode == .Call || opcode == .IndirectCall { ret true }
        at += 1usize
    }
    ret false
}

// ---------------------------------------------------------------- functions

fn function(builder: *nir.Builder, function_index: usize, stack_slots: usize, context: *codegen_x64.FunctionContext) -> err {
    context.instruction_offsets = context.instruction_offsets[0usize..0usize]
    context.stack_value_slots = context.stack_value_slots[0usize..0usize]
    context.debug_windows = context.debug_windows[0usize..0usize]
    context.debug_window_count = 0usize
    if !context.has_arena || function_index >= builder.function_count {
        context.live_masks = context.live_masks[0usize..0usize]
        context.entered = context.entered[0usize..0usize]
        ret function_body(builder, function_index, stack_slots, context)
    }
    let current = builder.functions[function_index]
    let mark = mem.mark(context.arena)
    let (deltas, deltas_error) = mem.alloc[usize](context.arena, current.instruction_count * 16usize + 1usize)
    if deltas_error != ok { ret deltas_error }
    let (masks, masks_error) = mem.alloc[usize](context.arena, current.instruction_count + 1usize)
    if masks_error != ok { ret masks_error }
    try codegen_x64.build_live_masks(builder, current, context, deltas, masks)
    context.live_masks = masks[0usize..current.instruction_count]
    context.live_base = current.first_instruction
    let (entered, entered_error) = mem.alloc[bool](context.arena, current.block_count + 1usize)
    if entered_error != ok { ret entered_error }
    codegen_x64.mark_entered_blocks(builder, current, entered)
    context.entered = entered
    let (definers, definers_error) = mem.alloc[usize](context.arena, current.value_count + 1usize)
    if definers_error != ok { ret definers_error }
    var clear_at = 0usize
    while clear_at < definers.len {
        definers[clear_at] = 0usize
        clear_at += 1usize
    }
    var fill_at = current.first_instruction
    let fill_end = current.first_instruction + current.instruction_count
    while fill_at < fill_end {
        if builder.instructions[fill_at].has_result {
            let filled_result = builder.instructions[fill_at].result
            if filled_result < definers.len { definers[filled_result] = fill_at + 1usize }
        }
        fill_at += 1usize
    }
    builder.definers = definers
    builder.definers_first = current.first_instruction
    builder.definers_valid = true
    let body_error = function_body(builder, function_index, stack_slots, context)
    builder.definers_valid = false
    context.live_masks = context.live_masks[0usize..0usize]
    mem.reset(context.arena, mark)
    ret body_error
}

fn function_body(builder: *nir.Builder, function_index: usize, stack_slots: usize, context: *codegen_x64.FunctionContext) -> err {
    if function_index >= builder.function_count { ret codegen_x64.Unsupported }
    let output = context.output
    let allocations = context.allocations
    let current = builder.functions[function_index]
    // A data function (D927) is its string's bytes, padded to the next word so the
    // code after it stays aligned.
    if current.block_count == 1usize && current.instruction_count == 1usize && builder.instructions[current.first_instruction].opcode == .Data {
        let data = builder.instructions[current.first_instruction]
        if data.immediate >= builder.string_count { ret codegen_x64.Unsupported }
        try codegen_x64.emit_text(output, builder.strings[data.immediate].spelling)
        ret pad_words(output)
    }
    if current.block_count == 1usize && current.instruction_count == 1usize && builder.instructions[current.first_instruction].opcode == .TrapStub {
        ret emit_trap_stub(builder, current, builder.instructions[current.first_instruction], context)
    }
    context.trap_record_count = 0usize
    context.has_trap_stub = false
    context.trap_pair_count = 0usize
    context.has_short = false
    context.fused = false
    let block_offsets = context.block_offsets
    let fixups = context.fixups
    if current.block_count > block_offsets.len { ret codegen_x64.Unsupported }
    let function_code_start = output.count
    let (parameters, parameters_error) = codegen_x64.parameter_count(builder, current)
    if parameters_error != ok { ret parameters_error }
    let local_count = codegen_x64.stack_object_count(builder, current)
    let local_base = stack_slots + parameters
    let preserve_base = local_base + local_count
    var preserve_count = 0usize
    if has_calls(builder, current) { preserve_count = A64_CLOBBERED }
    let saved_base = preserve_base + preserve_count
    let saved_count = kept_count(allocations, current.value_count)
    let (call_area, call_area_error) = stack_argument_count(builder, current)
    if call_area_error != ok { ret call_area_error }
    // The outgoing stack arguments are at [sp + 8i], so the call area is the frame's
    // bottom; the frame stays sixteen-byte aligned.
    let frame_slots = saved_base + saved_count + call_area
    let frame_bytes = (frame_slots * 8usize + 15usize) / 16usize * 16usize
    let far = far_function(current)
    try frame_prologue(output, frame_bytes)
    try save_kept(output, saved_base, saved_count)
    try store_incoming_parameters(builder, current, stack_slots, parameters, output)
    let end = current.first_instruction + current.instruction_count
    var fixup_count = 0usize
    var at = current.first_instruction
    var next_block = 0usize
    var stack_cursor = 0usize
    while at < end {
        while next_block < current.block_count && builder.blocks[current.first_block + next_block].first_instruction == at {
            block_offsets[next_block] = output.count
            next_block += 1usize
        }
        if next_block != 0usize && codegen_x64.unentered_trap(builder, current, context, next_block - 1usize, at) {
            at += 1usize
            continue
        }
        let instruction = builder.instructions[at]
        context.failure_token = nir.site_token(instruction.site)
        context.failure_instruction = at
        if builder.fault_select_inlined != 0usize && codegen_x64.inline_depth(builder, usize(instruction.inline_origin)) >= builder.fault_select_inlined { ret codegen_x64.FaultSelect }
        // The line table: a row wherever the line or the file changes (D209).
        if instruction.site.line != 0usize {
            if instruction.site.line > 4294967295usize { ret codegen_x64.Unsupported }
            var line_path = instruction.path
            if line_path.len == 0usize { line_path = current.path }
            let line_count = *context.line_count
            var changed = true
            if line_count != 0usize {
                let last = context.lines[line_count - 1usize]
                if last.line == u32(instruction.site.line) && last.origin == instruction.inline_origin && check.same(last.path, line_path) && last.offset >= function_code_start { changed = false }
            }
            if changed {
                if line_count == context.lines.len { ret codegen_x64.Unsupported }
                context.lines[line_count] = codegen_x64.LineEntry { offset: output.count, line: u32(instruction.site.line), origin: instruction.inline_origin, path: line_path }
                *context.line_count = line_count + 1usize
            }
        }
        let opcode = instruction.opcode
        var handled = true
        if opcode == .Barrier {
            try emit_trap(builder, current, instruction.site, instruction.path, "barrier", "GPU barrier helper reached as a native call", "", "", 0usize, false, 0usize, 0usize, "", context)
        } else {
        if opcode == .Bitcast {
            try select_bitcast(builder, instruction, context)
        } else {
        if codegen_x64.float_operation(builder, current, instruction) {
            try select_float(builder, current, instruction, at, end, context)
        } else {
        if opcode == .Parameter {
            if instruction.immediate >= parameters { ret codegen_x64.Unsupported }
            let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
            if destination_error != ok { ret destination_error }
            try slot_load(output, destination, stack_slots + instruction.immediate)
            try store_result(allocations, instruction.result, destination, output)
        } else {
        if opcode == .Stack {
            if !instruction.has_result || instruction.operand_count != 0usize { ret codegen_x64.Unsupported }
            let slot = local_base + stack_cursor + codegen_x64.stack_object_slots(instruction) - 1usize
            stack_cursor += codegen_x64.stack_object_slots(instruction)
            let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
            if destination_error != ok { ret destination_error }
            try slot_address(output, destination, slot)
            try store_result(allocations, instruction.result, destination, output)
        } else {
        if opcode == .GlobalAddress || opcode == .FunctionAddress {
            if !instruction.has_result || instruction.operand_count != 0usize { ret codegen_x64.Unsupported }
            if opcode == .GlobalAddress && instruction.immediate >= builder.global_count { ret codegen_x64.Unsupported }
            if opcode == .FunctionAddress && instruction.immediate >= builder.function_ref_count { ret codegen_x64.Unsupported }
            let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
            if destination_error != ok { ret destination_error }
            let (address_at, address_error) = emit_a64.address_far(output, destination)
            if address_error != ok { ret address_error }
            if opcode == .GlobalAddress {
                try codegen_x64.add_global_relocation(context.relocations, context.relocation_count, address_at, instruction.immediate)
            } else {
                try codegen_x64.add_relocation(context.relocations, context.relocation_count, address_at, instruction.immediate)
            }
            try store_result(allocations, instruction.result, destination, output)
        } else {
        if opcode == .ConstString {
            let string_slot = local_base + stack_cursor + 1usize
            stack_cursor += 2usize
            try select_string(builder, instruction, string_slot, context)
        } else {
        if opcode == .Store || opcode == .Load {
            var width = codegen_x64.storage_width(instruction)
            if width == 0usize { ret codegen_x64.InvalidStoreWidth }
            let (address, address_error) = read_value(allocations, builder.operands[instruction.first_operand], A64_S0, output)
            if address_error != ok { ret codegen_x64.InvalidMemoryAddress }
            if opcode == .Store {
                if instruction.has_result || instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
                let (source, source_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
                if source_error != ok { ret source_error }
                try emit_a64.store_offset(output, source, address, 0usize, width / 8usize)
            } else {
                if !instruction.has_result || instruction.operand_count != 1usize { ret codegen_x64.Unsupported }
                let (destination, destination_error) = result_register(allocations, instruction.result, A64_S1)
                if destination_error != ok { ret destination_error }
                try emit_a64.load_offset(output, destination, address, 0usize, width / 8usize, codegen_x64.signed_integer(instruction.ty))
                try store_result(allocations, instruction.result, destination, output)
            }
        } else {
        if opcode == .Copy {
            if instruction.has_result || instruction.operand_count != 2usize { ret codegen_x64.Unsupported }
            try read_into(allocations, builder.operands[instruction.first_operand], 0usize, output)
            try read_into(allocations, builder.operands[instruction.first_operand + 1usize], 1usize, output)
            try copy_block(output, instruction.immediate)
        } else {
        if opcode == .Zero {
            if instruction.has_result {
                if instruction.operand_count != 0usize { ret codegen_x64.Unsupported }
                let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
                if destination_error != ok { ret destination_error }
                try emit_a64.movz(output, destination, 0usize, 0usize)
                try store_result(allocations, instruction.result, destination, output)
            } else {
                if instruction.operand_count != 1usize { ret codegen_x64.Unsupported }
                try read_into(allocations, builder.operands[instruction.first_operand], 0usize, output)
                try zero_block(output, instruction.immediate)
            }
        } else {
        if opcode == .FieldAddress {
            if !instruction.has_result || instruction.operand_count != 1usize { ret codegen_x64.InvalidFieldAddress }
            let (source, source_error) = read_value(allocations, builder.operands[instruction.first_operand], A64_S0, output)
            if source_error != ok { ret source_error }
            let (destination, destination_error) = result_register(allocations, instruction.result, A64_S1)
            if destination_error != ok { ret destination_error }
            if instruction.immediate < 16777216usize {
                try emit_a64.add_immediate(output, destination, source, instruction.immediate)
            } else {
                try emit_a64.move_constant(output, A64_S2, instruction.immediate)
                try emit_a64.add_register(output, destination, source, A64_S2)
            }
            try store_result(allocations, instruction.result, destination, output)
        } else {
        if opcode == .AtomicLoad || opcode == .AtomicStore || opcode == .AtomicRmw || opcode == .AtomicCas || opcode == .AtomicFence {
            try select_atomic(builder, current, instruction, context)
        } else {
        if opcode == .IndexAddress {
            try select_index_address(builder, current, instruction, context)
        } else {
        if opcode == .Slice {
            try select_slice(builder, current, instruction, context)
        } else {
        if opcode == .Cast || opcode == .Negate || opcode == .BitNot {
            try select_unary(builder, current, instruction, context)
        } else {
        if opcode == .ConstInteger || opcode == .ConstBool || opcode == .ConstError || opcode == .ConstFloat {
            let (destination, destination_error) = result_register(allocations, instruction.result, A64_S0)
            if destination_error != ok { ret destination_error }
            try emit_a64.move_constant(output, destination, instruction.immediate)
            try store_result(allocations, instruction.result, destination, output)
        } else {
        if opcode == .ShiftLeft || opcode == .ShiftRight {
            try select_shift(builder, current, instruction, context)
        } else {
        if opcode == .Divide || opcode == .Remainder {
            try select_divide(builder, current, instruction, context)
        } else {
        if codegen_x64.register_binary(opcode) {
            try select_binary(builder, current, instruction, at, end, context)
        } else {
        if opcode == .Call || opcode == .IndirectCall {
            try select_call(builder, current, instruction, at, preserve_base, context)
        } else {
        if opcode == .Extract {
            if !instruction.has_result || instruction.operand_count != 1usize || instruction.immediate >= 2usize { ret codegen_x64.Unsupported }
            var source = A64_S0
            if instruction.immediate == 1usize { source = A64_S1 }
            let (destination, destination_error) = result_register(allocations, instruction.result, source)
            if destination_error != ok { ret destination_error }
            if destination != source { try emit_a64.move_register(output, destination, source) }
            try store_result(allocations, instruction.result, destination, output)
        } else {
        if opcode == .Branch {
            if instruction.target < current.first_block || instruction.target >= current.first_block + current.block_count { ret codegen_x64.Unsupported }
            if builder.blocks[instruction.target].first_instruction != at + 1usize {
                let (jump_at, jump_error) = emit_a64.branch(output)
                if jump_error != ok { ret jump_error }
                try codegen_x64.add_fixup(fixups, &fixup_count, jump_at, instruction.target - current.first_block)
            }
        } else {
        if opcode == .BranchIf {
            if instruction.operand_count != 1usize || instruction.target < current.first_block || instruction.target >= current.first_block + current.block_count || instruction.target2 < current.first_block || instruction.target2 >= current.first_block + current.block_count { ret codegen_x64.Unsupported }
            let condition_value = builder.operands[instruction.first_operand]
            if context.fused && context.fused_value == condition_value {
                context.fused = false
                let (true_at, true_error) = branch_to_block(output, context.fused_condition, far)
                if true_error != ok { ret true_error }
                try codegen_x64.add_fixup(fixups, &fixup_count, true_at, instruction.target - current.first_block)
            } else {
                let (condition, condition_error) = read_value(allocations, condition_value, A64_S0, output)
                if condition_error != ok { ret condition_error }
                let (true_at, true_error) = branch_nonzero_to_block(output, condition, far)
                if true_error != ok { ret true_error }
                try codegen_x64.add_fixup(fixups, &fixup_count, true_at, instruction.target - current.first_block)
            }
            if builder.blocks[instruction.target2].first_instruction != at + 1usize {
                let (false_at, false_error) = emit_a64.branch(output)
                if false_error != ok { ret false_error }
                try codegen_x64.add_fixup(fixups, &fixup_count, false_at, instruction.target2 - current.first_block)
            }
        } else {
        if opcode == .Trap || opcode == .Unreachable {
            if instruction.has_result || instruction.operand_count > 2usize { ret codegen_x64.Unsupported }
            let (kind, message, text_error) = codegen_x64.trap_instruction_text(builder, instruction)
            if text_error != ok { ret text_error }
            var signed = false
            var first_register = 0usize
            var second_register = 0usize
            if instruction.operand_count >= 1usize {
                let first_value = builder.operands[instruction.first_operand]
                let (operand_type, operand_type_error) = codegen_x64.value_type(builder, current, first_value)
                if operand_type_error != ok { ret operand_type_error }
                signed = codegen_x64.signed_integer(operand_type)
                let (first_source, first_error) = read_value(allocations, first_value, A64_S0, output)
                if first_error != ok { ret first_error }
                first_register = first_source
            }
            if instruction.operand_count == 2usize {
                let (second_source, second_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], A64_S1, output)
                if second_error != ok { ret second_error }
                second_register = second_source
            }
            try emit_trap(builder, current, instruction.site, instruction.path, kind, message, "", "", instruction.operand_count, signed, first_register, second_register, "", context)
        } else {
        if opcode == .Return {
            if instruction.operand_count == 1usize {
                let value = builder.operands[instruction.first_operand]
                let (returned_type, returned_error) = codegen_x64.value_type(builder, current, value)
                if returned_error != ok { ret returned_error }
                if returned_type.kind == .Float {
                    let returned_width = codegen_x64.float_width(returned_type)
                    if returned_width == 0usize { ret codegen_x64.Unsupported }
                    let (source, source_error) = read_value(allocations, value, A64_S0, output)
                    if source_error != ok { ret source_error }
                    try emit_a64.move_to_float(output, 0usize, source, returned_width == 64usize)
                } else {
                    try read_into(allocations, value, 0usize, output)
                }
            } else {
                if instruction.operand_count == 2usize {
                    if codegen_x64.result_pair_sse(instruction.ty) != 0usize { ret codegen_x64.Unsupported }
                    try read_into(allocations, builder.operands[instruction.first_operand], 0usize, output)
                    try read_into(allocations, builder.operands[instruction.first_operand + 1usize], 1usize, output)
                } else {
                    if instruction.operand_count != 0usize { ret codegen_x64.Unsupported }
                    // The entry's void return is the exit status the startup reads (D230).
                    if current.module_index == 0usize && check.same(current.name, "main") { try emit_a64.movz(output, 0usize, 0usize, 0usize) }
                }
            }
            try restore_kept(output, saved_base, saved_count)
            try frame_epilogue(output)
        } else {
        if opcode == .VectorBinary {
            try select_vector_binary(builder, current, instruction, context)
        } else {
            handled = false
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        if !handled { ret codegen_x64.Unsupported }
        at += 1usize
    }
    var fixup_at = 0usize
    while fixup_at < fixup_count {
        let fixup = fixups[fixup_at]
        if fixup.block >= current.block_count { ret codegen_x64.Unsupported }
        try emit_a64.patch_relative(output, fixup.displacement_at, block_offsets[fixup.block])
        fixup_at += 1usize
    }
    ret ok
}

// The calls between functions of this buffer, pointed at their callees: B and BL by
// their words, an ADRP pair by its page -- right once the buffer starts on a page.
fn resolve_calls(builder: *nir.Builder, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len { ret codegen_x64.Unsupported }
    nir.resolve_reference_targets(builder)
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        if relocations[relocation_at].global {
            relocation_at += 1usize
            continue
        }
        let reference_index = relocations[relocation_at].function_ref
        if reference_index >= builder.function_ref_count { ret codegen_x64.Unsupported }
        if builder.function_refs[reference_index].has_target {
            let function_at = builder.function_refs[reference_index].target
            try emit_a64.patch_relative(output, relocations[relocation_at].displacement_at, function_offsets[function_at])
            relocations[relocation_at].resolved = true
        }
        relocation_at += 1usize
    }
    ret ok
}
