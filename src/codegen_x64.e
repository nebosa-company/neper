// x64 instruction selection from allocated scalar NIR.

use e.mem
use check
use lookup
use emit_x64
use lex
use nir
use regalloc

error Unsupported
error InvalidMemoryAddress
error InvalidStoreWidth
error InvalidLoadWidth
error InvalidFieldAddress

type Abi = enum u8 {
    SystemV,
    Windows,
}

type Fixup = struct {
    displacement_at: usize,
    block: usize,
}

// One row of section 13's line table (D209): from this offset in the machine code on,
// the instructions came from `line` of `path`, until the next row.
type LineEntry = struct {
    offset: usize,
    line: usize,
    path: str,
}

type Relocation = struct {
    displacement_at: usize,
    function_ref: usize,
    // A reference to a module-scope `var` rather than to a function. The two share this list
    // because they share everything else about being a displacement the image has to fill;
    // `global` says which table `function_ref` indexes.
    global: bool,
    resolved: bool,
}

type FunctionContext = struct {
    allocations: []regalloc.Allocation,
    // The live register mask at every instruction of the function (D305), built once
    // per function from the ranges in the arena, so a call or a fixed-register
    // sequence reads its mask instead of walking every value. Absent (no arena), the
    // walk stands.
    arena: *mem.Arena,
    has_arena: bool,
    live_masks: []usize,
    live_base: usize,
    // The live ranges the allocations came from (D226): a call saves and restores
    // only the registers whose values are live across it. Shorter than the values,
    // and every register is saved, as before.
    ranges: []regalloc.LiveRange,
    abi: Abi,
    block_offsets: []usize,
    fixups: []Fixup,
    relocations: []Relocation,
    relocation_count: *usize,
    output: *emit_x64.Buffer,
    failure_token: lex.Token,
    failure_instruction: usize,
    lines: []LineEntry,
    line_count: *usize,
    // A comparison whose only use is the branch that follows it sets the flags and
    // nothing else (D237): the branch jumps on this condition instead of testing a
    // materialised bool.
    fused: bool,
    fused_value: usize,
    fused_condition: usize,
}

fn add_fixup(fixups: []Fixup, count: *usize, displacement_at: usize, block: usize) -> err {
    if *count == fixups.len { ret Unsupported }
    fixups[*count] = Fixup { displacement_at: displacement_at, block: block }
    *count += 1usize
    ret ok
}

fn add_relocation(relocations: []Relocation, count: *usize, displacement_at: usize, function_ref: usize) -> err {
    if *count == relocations.len { ret Unsupported }
    relocations[*count] = Relocation { displacement_at: displacement_at, function_ref: function_ref, global: false, resolved: false }
    *count += 1usize
    ret ok
}

fn add_global_relocation(relocations: []Relocation, count: *usize, displacement_at: usize, global_index: usize) -> err {
    if *count == relocations.len { ret Unsupported }
    relocations[*count] = Relocation { displacement_at: displacement_at, function_ref: global_index, global: true, resolved: false }
    *count += 1usize
    ret ok
}

// `nir.prune_references` for a program whose bodies are gone (D314): a reference is
// live if a relocation of the kept code names it -- the same edges, since every
// instruction that names a function emits one -- and the relocations are the carriers
// renumbered before the references move.
fn prune_references(builder: *nir.Builder, relocations: []Relocation, relocation_count: usize) -> err {
    if relocation_count > relocations.len { ret Unsupported }
    var reference_at = 0usize
    while reference_at < builder.function_ref_count {
        builder.function_refs[reference_at].live = false
        reference_at += 1usize
    }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.global {
            if relocation.function_ref >= builder.function_ref_count { ret Unsupported }
            builder.function_refs[relocation.function_ref].live = true
        }
        relocation_at += 1usize
    }
    nir.assign_reference_numbers(builder)
    relocation_at = 0usize
    while relocation_at < relocation_count {
        if !relocations[relocation_at].global {
            relocations[relocation_at].function_ref = builder.function_refs[relocations[relocation_at].function_ref].renumbered
        }
        relocation_at += 1usize
    }
    ret nir.compact_references(builder)
}

fn resolve_calls(builder: *nir.Builder, function_offsets: []usize, relocations: []Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len { ret Unsupported }
    nir.resolve_reference_targets(builder)
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        // A global's address depends on where the image puts its data, which is the linker's to
        // say and not knowable from a code offset.
        if relocations[relocation_at].global {
            relocation_at += 1usize
            continue
        }
        let reference_index = relocations[relocation_at].function_ref
        if reference_index >= builder.function_ref_count { ret Unsupported }
        if builder.function_refs[reference_index].has_target {
            let function_at = builder.function_refs[reference_index].target
            try emit_x64.patch_relative32(output, relocations[relocation_at].displacement_at, function_offsets[function_at])
            relocations[relocation_at].resolved = true
        }
        relocation_at += 1usize
    }
    ret ok
}


// The allocator's registers: five the calls clobber -- rax, rcx, rdx, r8, r9 -- and
// then five the callee keeps -- rbx, r12, r13, r14, r15 (D235). A value in one of the
// second five survives every call untouched, and the function saves the register at
// its entry and restores it at its returns, in a slot of its own.
fn hardware_register(index: usize) -> (usize, err) {
    if index == 0usize { ret (0usize, ok) }
    if index == 1usize { ret (1usize, ok) }
    if index == 2usize { ret (2usize, ok) }
    if index == 3usize { ret (8usize, ok) }
    if index == 4usize { ret (9usize, ok) }
    if index == 5usize { ret (3usize, ok) }
    if index == 6usize { ret (12usize, ok) }
    if index == 7usize { ret (13usize, ok) }
    if index == 8usize { ret (14usize, ok) }
    if index == 9usize { ret (15usize, ok) }
    ret (0usize, Unsupported)
}

fn caller_saved_count() -> usize { ret 5usize }
fn register_pool_count() -> usize { ret 10usize }

// How many of the callee-saved registers the function's values are allocated to,
// counted from the first: the slots at its entry are one per register in use.
fn callee_saved_count(allocations: []regalloc.Allocation, value_count: usize) -> usize {
    var highest = 0usize
    var value = 0usize
    while value < value_count && value < allocations.len {
        let allocation = allocations[value]
        if allocation.kind == .Register && allocation.index >= caller_saved_count() && allocation.index + 1usize - caller_saved_count() > highest { highest = allocation.index + 1usize - caller_saved_count() }
        value += 1usize
    }
    ret highest
}

fn save_callee_registers(output: *emit_x64.Buffer, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        let (physical, physical_error) = hardware_register(caller_saved_count() + at)
        if physical_error != ok { ret physical_error }
        try emit_x64.store_stack(output, base + at, physical)
        at += 1usize
    }
    ret ok
}

fn restore_callee_registers(output: *emit_x64.Buffer, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        let (physical, physical_error) = hardware_register(caller_saved_count() + at)
        if physical_error != ok { ret physical_error }
        try emit_x64.load_stack(output, physical, base + at)
        at += 1usize
    }
    ret ok
}

fn value_register(allocations: []regalloc.Allocation, value: usize) -> (usize, err) {
    if value >= allocations.len || allocations[value].kind != .Register { ret (0usize, Unsupported) }
    let (result, result_error) = hardware_register(allocations[value].index)
    ret (result, result_error)
}

fn read_value(allocations: []regalloc.Allocation, value: usize, scratch: usize, output: *emit_x64.Buffer) -> (usize, err) {
    if value >= allocations.len { ret (0usize, Unsupported) }
    let allocation = allocations[value]
    if allocation.kind == .Register {
        let (physical, physical_error) = hardware_register(allocation.index)
        ret (physical, physical_error)
    }
    if allocation.kind != .Stack { ret (0usize, Unsupported) }
    let load_error = emit_x64.load_stack(output, scratch, allocation.index)
    ret (scratch, load_error)
}

fn read_preserved_value(allocations: []regalloc.Allocation, value: usize, scratch: usize, preserve_base: usize, output: *emit_x64.Buffer) -> (usize, err) {
    if value >= allocations.len { ret (0usize, Unsupported) }
    let allocation = allocations[value]
    if allocation.kind == .Register {
        if allocation.index >= caller_saved_count() {
            let (physical, physical_error) = hardware_register(allocation.index)
            ret (physical, physical_error)
        }
        let load_error = emit_x64.load_stack(output, scratch, preserve_base + allocation.index)
        ret (scratch, load_error)
    }
    if allocation.kind != .Stack { ret (0usize, Unsupported) }
    let load_error = emit_x64.load_stack(output, scratch, allocation.index)
    ret (scratch, load_error)
}

fn result_register(allocations: []regalloc.Allocation, value: usize, scratch: usize) -> (usize, err) {
    if value >= allocations.len { ret (0usize, Unsupported) }
    if allocations[value].kind == .Stack { ret (scratch, ok) }
    let (physical, physical_error) = value_register(allocations, value)
    ret (physical, physical_error)
}

fn store_result(allocations: []regalloc.Allocation, value: usize, source: usize, output: *emit_x64.Buffer) -> err {
    if value >= allocations.len { ret Unsupported }
    if allocations[value].kind == .Stack { ret emit_x64.store_stack(output, allocations[value].index, source) }
    ret ok
}

fn comparison(opcode: nir.Opcode) -> bool {
    ret opcode == .Equal || opcode == .NotEqual || opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual
}

fn register_binary(opcode: nir.Opcode) -> bool {
    ret opcode == .Add || opcode == .Subtract || opcode == .Multiply || opcode == .AddWrap || opcode == .SubtractWrap || opcode == .MultiplyWrap || opcode == .BitAnd || opcode == .BitXor || opcode == .BitOr || comparison(opcode)
}

fn integer_width(ty: check.Type) -> usize {
    if ty.kind != .Integer { ret 0usize }
    if check.same(ty.name, "i8") || check.same(ty.name, "u8") { ret 8usize }
    if check.same(ty.name, "i16") || check.same(ty.name, "u16") { ret 16usize }
    if check.same(ty.name, "i32") || check.same(ty.name, "u32") { ret 32usize }
    ret 64usize
}

// f16 and bf16 are in the type system but not in this emitter, so they answer zero
// here and reach the caller as `Unsupported` rather than as the wrong width.
fn float_width(ty: check.Type) -> usize {
    if ty.kind != .Float { ret 0usize }
    if check.same(ty.name, "f32") { ret 32usize }
    if check.same(ty.name, "f64") { ret 64usize }
    ret 0usize
}

fn float_sign_bit(width: usize) -> usize {
    if width == 32usize { ret 2147483648usize }
    ret 9223372036854775808usize
}

// The bits a bitcast hands back are the bits it was given; what changes is how the
// target's width is held in a general register. A signed target is sign-extended, an
// unsigned one and a float are zero-extended, and a 64-bit one is already whole.
fn bitcast_scalar(ty: check.Type) -> bool {
    ret ty.kind == .Integer || ty.kind == .Float || ty.kind == .Bool || ty.kind == .Err
}

fn bitcast_width(ty: check.Type) -> usize {
    if ty.kind == .Integer { ret integer_width(ty) }
    if ty.kind == .Float { ret float_width(ty) }
    if ty.kind == .Bool { ret 8usize }
    if ty.kind == .Err { ret 32usize }
    ret 0usize
}

fn select_bitcast(builder: *nir.Builder, instruction: nir.Instruction, allocations: []regalloc.Allocation, context: *FunctionContext) -> err {
    let output = context.output
    if instruction.operand_count != 1usize || !instruction.has_result { ret Unsupported }
    // A bitcast nothing reads is a promoted local's former load (D236): no code.
    if instruction.result < context.ranges.len && context.ranges[instruction.result].defined && !context.ranges[instruction.result].used { ret ok }
    let (source, source_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
    if destination_error != ok { ret destination_error }
    if bitcast_scalar(instruction.ty) {
        let width = bitcast_width(instruction.ty)
        if width == 0usize { ret Unsupported }
        try emit_x64.normalize_integer(output, destination, source, width, signed_integer(instruction.ty))
    } else {
        // An aggregate is already a place. Its bytes do not move; only the type
        // the rest of selection reads them through changes.
        if destination != source { try emit_x64.mov_register(output, destination, source) }
    }
    ret store_result(allocations, instruction.result, destination, output)
}

// An atomic's `T` is an integer or a pointer, and a pointer is one word.
// `storage_width` cannot answer this: an atomic instruction's immediate carries its
// ordering, and that function reads an immediate of 1, 2, 4 or 8 as a byte count.
fn atomic_width(ty: check.Type) -> usize {
    if ty.kind == .Pointer || ty.kind == .Function { ret 64usize }
    ret integer_width(ty)
}

// `and`, `or`, `xor`, `min` and `max` have no instruction that both applies them to
// memory and gives back what was there, so each is a compare-and-swap retried until
// it wins. On entry r10 holds the address and r11 the operand; rax ends up holding
// the value that was there before, and rcx is the candidate this round.
fn emit_atomic_loop(output: *emit_x64.Buffer, kind: usize, width: usize, signed: bool) -> err {
    try emit_x64.load_memory(output, 0usize, 10usize, width, signed)
    let top = output.count
    // A failed exchange leaves rax holding only `width` bits of what it found, so the
    // comparison below needs it widened again before each attempt.
    try emit_x64.normalize_integer(output, 0usize, 0usize, width, signed)
    try emit_x64.mov_register(output, 1usize, 0usize)
    if kind == 3usize { try emit_x64.bit_and_register(output, 1usize, 11usize) }
    if kind == 4usize { try emit_x64.bit_or_register(output, 1usize, 11usize) }
    if kind == 5usize { try emit_x64.bit_xor_register(output, 1usize, 11usize) }
    if kind == 6usize || kind == 7usize {
        try emit_x64.compare_register(output, 1usize, 11usize)
        // `min` takes the operand when the candidate is the greater of the two, and
        // `max` when it is the lesser; which comparison that is depends on the sign.
        var condition = 15usize
        if kind == 6usize {
            if !signed { condition = 7usize }
        } else {
            if signed { condition = 12usize } else { condition = 2usize }
        }
        try emit_x64.conditional_move(output, 1usize, 11usize, condition)
    }
    try emit_x64.atomic_compare_exchange(output, 10usize, 1usize, width)
    ret emit_x64.jump_back_not_equal(output, top)
}

// Section 8's five instructions. Every ordering but sequential consistency is free on
// this target's store-ordered memory model, so only a `SeqCst` store and fence emit
// anything for it; the rest of the ordering rules were settled while checking.
fn select_atomic(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, preserve_base: usize, preserve_count: usize, context: *FunctionContext) -> err {
    let output = context.output
    let mask = preserve_mask(builder, current, instruction, 3usize, false, context)
    if instruction.opcode == .AtomicFence {
        if instruction.immediate == 4usize { ret emit_x64.memory_fence(output) }
        ret ok
    }
    let width = atomic_width(instruction.ty)
    if width == 0usize { ret Unsupported }
    let signed = signed_integer(instruction.ty)
    if instruction.opcode == .AtomicLoad {
        // A load is already an acquire here, and sequential consistency is carried by
        // the store side, so every ordering section 8 allows is a plain move.
        if !instruction.has_result || instruction.operand_count != 1usize { ret Unsupported }
        let (address, address_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
        if address_error != ok { ret InvalidMemoryAddress }
        let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
        if destination_error != ok { ret destination_error }
        try emit_x64.load_memory(output, destination, address, width, signed)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if instruction.opcode == .AtomicStore {
        if instruction.operand_count != 2usize { ret Unsupported }
        let (address, address_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
        if address_error != ok { ret InvalidMemoryAddress }
        if address != 10usize { try emit_x64.mov_register(output, 10usize, address) }
        let (value, value_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], 11usize, output)
        if value_error != ok { ret value_error }
        if value != 11usize { try emit_x64.mov_register(output, 11usize, value) }
        // The exchange is the sequentially consistent store: it is the one ordering
        // this target pays for, and it is cheaper than a move followed by a fence.
        if instruction.immediate == 4usize { ret emit_x64.atomic_exchange(output, 10usize, 11usize, width) }
        ret emit_x64.store_memory(output, 10usize, 11usize, width)
    }
    if !instruction.has_result { ret Unsupported }
    if instruction.opcode == .AtomicCas {
        if instruction.operand_count != 3usize { ret Unsupported }
        try save_live_registers(output, mask, preserve_base, preserve_count)
        let (address, address_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
        if address_error != ok { ret InvalidMemoryAddress }
        if address != 10usize { try emit_x64.mov_register(output, 10usize, address) }
        let (desired, desired_error) = read_value(allocations, builder.operands[instruction.first_operand + 2usize], 11usize, output)
        if desired_error != ok { ret desired_error }
        if desired != 11usize { try emit_x64.mov_register(output, 11usize, desired) }
        // The address and the desired value are in the two scratch registers now, so
        // rcx can carry the third operand: every allocated register is on the stack.
        let (expected, expected_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], 1usize, output)
        if expected_error != ok { ret expected_error }
        if expected != 0usize { try emit_x64.mov_register(output, 0usize, expected) }
        try emit_x64.atomic_compare_exchange(output, 10usize, 11usize, width)
        try emit_x64.mov_register(output, 10usize, 0usize)
        try restore_live_registers(output, mask, preserve_base, preserve_count)
        let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
        if destination_error != ok { ret destination_error }
        try emit_x64.normalize_integer(output, destination, 10usize, width, signed)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if instruction.opcode != .AtomicRmw || instruction.operand_count != 2usize { ret Unsupported }
    let kind = instruction.immediate / 8usize
    try save_live_registers(output, mask, preserve_base, preserve_count)
    let (address, address_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
    if address_error != ok { ret InvalidMemoryAddress }
    if address != 10usize { try emit_x64.mov_register(output, 10usize, address) }
    let (value, value_error) = read_value(allocations, builder.operands[instruction.first_operand + 1usize], 11usize, output)
    if value_error != ok { ret value_error }
    if value != 11usize { try emit_x64.mov_register(output, 11usize, value) }
    if kind == 0usize {
        try emit_x64.atomic_exchange(output, 10usize, 11usize, width)
    } else {
        if kind == 1usize {
            try emit_x64.atomic_exchange_add(output, 10usize, 11usize, width)
        } else {
            if kind == 2usize {
                // Subtraction is the exchange-add of the negated operand: there is no
                // locked subtract that gives back what was there.
                try emit_x64.negate_register(output, 11usize)
                try emit_x64.atomic_exchange_add(output, 10usize, 11usize, width)
            } else {
                try emit_atomic_loop(output, kind, width, signed)
                try emit_x64.mov_register(output, 11usize, 0usize)
            }
        }
    }
    try emit_x64.mov_register(output, 10usize, 11usize)
    try restore_live_registers(output, mask, preserve_base, preserve_count)
    let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
    if destination_error != ok { ret destination_error }
    try emit_x64.normalize_integer(output, destination, 10usize, width, signed)
    ret store_result(allocations, instruction.result, destination, output)
}

fn storage_width(instruction: nir.Instruction) -> usize {
    if instruction.immediate == 1usize || instruction.immediate == 2usize || instruction.immediate == 4usize || instruction.immediate == 8usize { ret instruction.immediate * 8usize }
    if instruction.ty.kind == .Bool { ret 8usize }
    if instruction.ty.kind == .Err { ret 32usize }
    if instruction.ty.kind == .Pointer || instruction.ty.kind == .String || instruction.ty.kind == .Slice { ret 64usize }
    if instruction.ty.kind == .Float { ret float_width(instruction.ty) }
    ret integer_width(instruction.ty)
}

fn signed_integer(ty: check.Type) -> bool {
    if ty.kind != .Integer || ty.name.len == 0usize { ret false }
    ret ty.name[0usize] == 105u8
}

fn value_type(builder: *nir.Builder, current: nir.Function, value: usize) -> (check.Type, err) {
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.has_result && instruction.result == value { ret (instruction.ty, ok) }
        at += 1usize
    }
    ret (zero, Unsupported)
}

fn comparison_condition(opcode: nir.Opcode, unsigned: bool) -> (usize, err) {
    if opcode == .Equal { ret (4usize, ok) }
    if opcode == .NotEqual { ret (5usize, ok) }
    if opcode == .Less {
        if unsigned { ret (2usize, ok) }
        ret (12usize, ok)
    }
    if opcode == .LessEqual {
        if unsigned { ret (6usize, ok) }
        ret (14usize, ok)
    }
    if opcode == .Greater {
        if unsigned { ret (7usize, ok) }
        ret (15usize, ok)
    }
    if opcode == .GreaterEqual {
        if unsigned { ret (3usize, ok) }
        ret (13usize, ok)
    }
    ret (0usize, Unsupported)
}

// A float operation is told apart by type, not by opcode: the arithmetic and
// comparison opcodes are shared with the integers, and only the operand or result
// type says which file the value lives in.
fn float_operation(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction) -> bool {
    let opcode = instruction.opcode
    if opcode == .Add || opcode == .Subtract || opcode == .Multiply || opcode == .Divide || opcode == .Negate || opcode == .Sqrt {
        ret instruction.ty.kind == .Float
    }
    if opcode == .Cast {
        if instruction.ty.kind == .Float { ret true }
        if instruction.operand_count != 1usize { ret false }
        let (source_type, source_error) = value_type(builder, current, builder.operands[instruction.first_operand])
        if source_error != ok { ret false }
        ret source_type.kind == .Float
    }
    if comparison(opcode) {
        if instruction.operand_count != 2usize { ret false }
        let (operand_type, operand_error) = value_type(builder, current, builder.operands[instruction.first_operand])
        if operand_error != ok { ret false }
        ret operand_type.kind == .Float
    }
    ret false
}

// Section 11: every floating operation that produces a NaN returns one canonical
// positive quiet NaN for its width, zero payload except the quiet bit, and that
// canonicalization is part of code generation on every back end -- it is what lets a
// CPU and a GPU agree bit for bit. `ucomis` against itself is unordered exactly when
// the value is a NaN, so the test is one compare and a branch that is never taken in
// ordinary code.
fn canonical_nan(width: usize) -> usize {
    if width == 32usize { ret 2143289344usize }
    ret 9221120237041090560usize
}

fn canonicalize_nan(width: usize, output: *emit_x64.Buffer) -> err {
    let wide = width == 64usize
    try emit_x64.float_compare(output, 0usize, 0usize, wide)
    let (finite_at, finite_error) = emit_x64.jump_condition(output, 11usize)
    if finite_error != ok { ret finite_error }
    try emit_x64.mov_immediate(output, 11usize, canonical_nan(width))
    try emit_x64.move_to_float(output, 0usize, 11usize, wide)
    ret emit_x64.patch_relative32(output, finite_at, output.count)
}

// Float values live in general registers as raw bits and move into xmm0 and xmm1 for
// the operation itself. The cost is two moves per operation and no float value ever
// staying in a vector register; the upgrade is a second register class in
// `regalloc`, which the allocator's `register_count` parameter is already shaped for.
fn select_float_binary(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer) -> err {
    if instruction.operand_count != 2usize || !instruction.has_result { ret Unsupported }
    let width = float_width(instruction.ty)
    if width == 0usize { ret Unsupported }
    let wide = width == 64usize
    let left_value = builder.operands[instruction.first_operand]
    let right_value = builder.operands[instruction.first_operand + 1usize]
    let (left, left_error) = read_value(allocations, left_value, 10usize, output)
    if left_error != ok { ret left_error }
    let (right, right_error) = read_value(allocations, right_value, 11usize, output)
    if right_error != ok { ret right_error }
    try emit_x64.move_to_float(output, 0usize, left, wide)
    try emit_x64.move_to_float(output, 1usize, right, wide)
    var opcode = 88usize
    if instruction.opcode == .Subtract { opcode = 92usize }
    if instruction.opcode == .Multiply { opcode = 89usize }
    if instruction.opcode == .Divide { opcode = 94usize }
    try emit_x64.float_binary(output, 0usize, 1usize, opcode, wide)
    try canonicalize_nan(width, output)
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    try emit_x64.move_from_float(output, destination, 0usize, wide)
    ret store_result(allocations, instruction.result, destination, output)
}

// Section 6 asks for IEEE ordered comparison: every ordering against a NaN is false,
// `==` is false and `!=` is true. `ucomis` reports unordered by setting CF, ZF and PF
// at once, so `above` and `above or equal` already answer false for a NaN and the two
// ordering forms that would need `below` swap their operands instead. Equality is the
// only pair that needs the parity flag, because a NaN sets ZF as well.
fn select_float_comparison(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer) -> err {
    if instruction.operand_count != 2usize || !instruction.has_result { ret Unsupported }
    let left_value = builder.operands[instruction.first_operand]
    let right_value = builder.operands[instruction.first_operand + 1usize]
    let (operand_type, operand_type_error) = value_type(builder, current, left_value)
    if operand_type_error != ok { ret operand_type_error }
    let width = float_width(operand_type)
    if width == 0usize { ret Unsupported }
    let wide = width == 64usize
    let (left, left_error) = read_value(allocations, left_value, 10usize, output)
    if left_error != ok { ret left_error }
    let (right, right_error) = read_value(allocations, right_value, 11usize, output)
    if right_error != ok { ret right_error }
    let swapped = instruction.opcode == .Less || instruction.opcode == .LessEqual
    if swapped {
        try emit_x64.move_to_float(output, 0usize, right, wide)
        try emit_x64.move_to_float(output, 1usize, left, wide)
    } else {
        try emit_x64.move_to_float(output, 0usize, left, wide)
        try emit_x64.move_to_float(output, 1usize, right, wide)
    }
    try emit_x64.float_compare(output, 0usize, 1usize, wide)
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    if instruction.opcode == .Equal || instruction.opcode == .NotEqual {
        try emit_x64.mov_immediate(output, destination, 0usize)
        try emit_x64.mov_immediate(output, 11usize, 0usize)
        if instruction.opcode == .Equal {
            try emit_x64.set_condition(output, destination, 4usize)
            try emit_x64.set_condition(output, 11usize, 11usize)
            try emit_x64.bit_and_register(output, destination, 11usize)
        } else {
            try emit_x64.set_condition(output, destination, 5usize)
            try emit_x64.set_condition(output, 11usize, 10usize)
            try emit_x64.bit_or_register(output, destination, 11usize)
        }
        ret store_result(allocations, instruction.result, destination, output)
    }
    var condition = 7usize
    if instruction.opcode == .GreaterEqual || instruction.opcode == .LessEqual { condition = 3usize }
    try emit_x64.mov_immediate(output, destination, 0usize)
    try emit_x64.set_condition(output, destination, condition)
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_float_negate(builder: *nir.Builder, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer) -> err {
    if instruction.operand_count != 1usize || !instruction.has_result { ret Unsupported }
    let width = float_width(instruction.ty)
    if width == 0usize { ret Unsupported }
    let (source, source_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    // Negation is a sign-bit flip, which is right for a zero and for every finite
    // value; a NaN then goes through the same canonicalization as the arithmetic.
    try emit_x64.mov_immediate(output, 11usize, float_sign_bit(width))
    if destination != source { try emit_x64.mov_register(output, destination, source) }
    try emit_x64.bit_xor_register(output, destination, 11usize)
    try emit_x64.move_to_float(output, 0usize, destination, width == 64usize)
    try canonicalize_nan(width, output)
    try emit_x64.move_from_float(output, destination, 0usize, width == 64usize)
    ret store_result(allocations, instruction.result, destination, output)
}

// `sqrtss` / `sqrtsd`: correctly rounded by the hardware, which is the whole reason
// `math.sqrt` is an instruction and the rest of `e.math` is source. A negative finite
// operand gives the default NaN, which the canonicalization leaves as it is.
fn select_float_sqrt(builder: *nir.Builder, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer) -> err {
    if instruction.operand_count != 1usize || !instruction.has_result { ret Unsupported }
    let width = float_width(instruction.ty)
    if width == 0usize { ret Unsupported }
    let (source, source_error) = read_value(allocations, builder.operands[instruction.first_operand], 10usize, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    try emit_x64.move_to_float(output, 0usize, source, width == 64usize)
    try emit_x64.float_sqrt(output, 0usize, 0usize, width == 64usize)
    try canonicalize_nan(width, output)
    try emit_x64.move_from_float(output, destination, 0usize, width == 64usize)
    ret store_result(allocations, instruction.result, destination, output)
}

// Only a 64-bit unsigned integer can hold a value the signed conversion instructions
// cannot express. Everything narrower already sits zero-extended in a general
// register and converts as the signed value it equals.
fn unsigned_wide(ty: check.Type) -> bool {
    if ty.kind != .Integer || signed_integer(ty) { ret false }
    ret integer_width(ty) == 64usize
}

// 2**63 as a float, which is where the signed conversions stop.
fn two_to_the_sixty_third(wide: bool) -> usize {
    if wide { ret 4890909195324358656usize }
    ret 1593835520usize
}

// `cvtsi2sd` reads its operand as signed, so a `u64` with the top bit set would
// convert to a negative value. Halving it and folding the lost bit back into the new
// bottom bit keeps everything the rounding depends on, so doubling afterwards lands
// on the same result a direct conversion would.
fn float_from_integer(source: usize, unsigned: bool, wide: bool, output: *emit_x64.Buffer) -> err {
    if !unsigned { ret emit_x64.float_from_signed(output, 0usize, source, wide) }
    if source != 11usize { try emit_x64.mov_register(output, 11usize, source) }
    try emit_x64.test_register(output, 11usize)
    let (big_at, big_error) = emit_x64.jump_condition(output, 8usize)
    if big_error != ok { ret big_error }
    try emit_x64.float_from_signed(output, 0usize, 11usize, wide)
    let (done_at, done_error) = emit_x64.jump(output)
    if done_error != ok { ret done_error }
    try emit_x64.patch_relative32(output, big_at, output.count)
    try emit_x64.mov_register(output, 10usize, 11usize)
    try emit_x64.shift_right_one(output, 11usize)
    try emit_x64.and_immediate8(output, 10usize, 1usize)
    try emit_x64.bit_or_register(output, 11usize, 10usize)
    try emit_x64.float_from_signed(output, 0usize, 11usize, wide)
    try emit_x64.float_binary(output, 0usize, 0usize, 88usize, wide)
    ret emit_x64.patch_relative32(output, done_at, output.count)
}

// Section 11's `narrow` row for a float source: a value outside the target's range,
// or NaN, traps before the conversion. The float is in xmm0; the bounds are the
// powers of two just past the range, as bit patterns, compared with `ucomis`. Above,
// the value must be below 2^(width-1) or 2^width; below, a signed target admits down
// to its minimum -- for a double source that is `<= -2^(width-1) - 1` refused, exact
// below 64 bits, and `< -2^63` at 64 -- and an unsigned one anything above -1. NaN
// compares unordered, which the low check refuses as well.
fn float_bound_bits(width: usize, signed: bool, upper: bool, wide: bool) -> usize {
    if upper {
        var power = width
        if signed { power = width - 1usize }
        var exponent = 127usize + power
        var mantissa_bits = 23usize
        if wide {
            exponent = 1023usize + power
            mantissa_bits = 52usize
        }
        ret exponent << mantissa_bits
    }
    if !signed {
        if wide { ret 13830554455654793216usize }
        ret 3212836864usize
    }
    if wide {
        if width == 8usize { ret 13862114837418475520usize }
        if width == 16usize { ret 13898108587504304128usize }
        if width == 32usize { ret 13970166044105375744usize }
        ret 14114281232179134464usize
    }
    if width == 8usize { ret 3271557120usize }
    if width == 16usize { ret 3338665984usize }
    if width == 32usize { ret 3472883712usize }
    ret 3741319168usize
}

// The release-mode counterpart of the range check: NaN gives 0, a value at or past
// the upper bound the maximum, one at or past the lower bound the minimum, and the
// conversion is skipped for all three. Returns the jump to patch to after it.
fn emit_float_saturation(destination: usize, into: check.Type, wide: bool, output: *emit_x64.Buffer) -> (usize, err) {
    let width = integer_width(into)
    let signed = signed_integer(into)
    let all_ones = 0usize -% 1usize
    var maximum = all_ones >> (64usize - width)
    var minimum = 0usize
    if signed {
        maximum = all_ones >> (65usize - width)
        minimum = all_ones - (all_ones >> (65usize - width))
    }
    // NaN: unordered after any compare, and the parity flag says so.
    let bound_error = emit_x64.mov_immediate(output, 11usize, float_bound_bits(width, signed, true, wide))
    if bound_error != ok { ret (0usize, bound_error) }
    let move_error = emit_x64.move_to_float(output, 1usize, 11usize, wide)
    if move_error != ok { ret (0usize, move_error) }
    let compare_error = emit_x64.float_compare(output, 0usize, 1usize, wide)
    if compare_error != ok { ret (0usize, compare_error) }
    let (is_nan, nan_error) = emit_x64.jump_condition(output, 10usize)
    if nan_error != ok { ret (0usize, nan_error) }
    let (too_high, high_error) = emit_x64.jump_condition(output, 3usize)
    if high_error != ok { ret (0usize, high_error) }
    let low_bound_error = emit_x64.mov_immediate(output, 11usize, float_bound_bits(width, signed, false, wide))
    if low_bound_error != ok { ret (0usize, low_bound_error) }
    let low_move_error = emit_x64.move_to_float(output, 1usize, 11usize, wide)
    if low_move_error != ok { ret (0usize, low_move_error) }
    let low_compare_error = emit_x64.float_compare(output, 0usize, 1usize, wide)
    if low_compare_error != ok { ret (0usize, low_compare_error) }
    var low_condition = 6usize
    if signed && (width == 64usize || !wide) { low_condition = 2usize }
    let (too_low, low_error) = emit_x64.jump_condition(output, low_condition)
    if low_error != ok { ret (0usize, low_error) }
    let (in_range, range_error) = emit_x64.jump(output)
    if range_error != ok { ret (0usize, range_error) }
    let nan_error2 = emit_x64.patch_relative32(output, is_nan, output.count)
    if nan_error2 != ok { ret (0usize, nan_error2) }
    let zero_error = emit_x64.mov_immediate(output, destination, 0usize)
    if zero_error != ok { ret (0usize, zero_error) }
    let (nan_done, nan_done_error) = emit_x64.jump(output)
    if nan_done_error != ok { ret (0usize, nan_done_error) }
    let high_patch_error = emit_x64.patch_relative32(output, too_high, output.count)
    if high_patch_error != ok { ret (0usize, high_patch_error) }
    let max_error = emit_x64.mov_immediate(output, destination, maximum)
    if max_error != ok { ret (0usize, max_error) }
    let (max_done, max_done_error) = emit_x64.jump(output)
    if max_done_error != ok { ret (0usize, max_done_error) }
    let low_patch_error = emit_x64.patch_relative32(output, too_low, output.count)
    if low_patch_error != ok { ret (0usize, low_patch_error) }
    let min_error = emit_x64.mov_immediate(output, destination, minimum)
    if min_error != ok { ret (0usize, min_error) }
    // The three saturated exits share one jump past the conversion, which the caller
    // patches; the NaN and maximum exits land on it, the minimum falls into it.
    let landing = output.count
    let nan_land_error = emit_x64.patch_relative32(output, nan_done, landing)
    if nan_land_error != ok { ret (0usize, nan_land_error) }
    let max_land_error = emit_x64.patch_relative32(output, max_done, landing)
    if max_land_error != ok { ret (0usize, max_land_error) }
    let (past, past_error) = emit_x64.jump(output)
    if past_error != ok { ret (0usize, past_error) }
    let range_patch_error = emit_x64.patch_relative32(output, in_range, output.count)
    if range_patch_error != ok { ret (0usize, range_patch_error) }
    ret (past, ok)
}

fn emit_float_range_check(builder: *nir.Builder, current: nir.Function, token: lex.Token, token_path: str, into: check.Type, wide: bool, context: *FunctionContext) -> err {
    let output = context.output
    let width = integer_width(into)
    let signed = signed_integer(into)
    try emit_x64.mov_immediate(output, 11usize, float_bound_bits(width, signed, true, wide))
    try emit_x64.move_to_float(output, 1usize, 11usize, wide)
    try emit_x64.float_compare(output, 0usize, 1usize, wide)
    let (below_high, high_error) = emit_x64.jump_condition(output, 2usize)
    if high_error != ok { ret high_error }
    try emit_trap(builder, current, token, token_path, "narrow", "a float outside ", "", "", 0usize, false, 0usize, 0usize, into.name, context)
    try emit_x64.patch_relative32(output, below_high, output.count)
    try emit_x64.mov_immediate(output, 11usize, float_bound_bits(width, signed, false, wide))
    try emit_x64.move_to_float(output, 1usize, 11usize, wide)
    try emit_x64.float_compare(output, 0usize, 1usize, wide)
    // Strictly above the bound passes when the bound itself is outside the range;
    // at or above passes when the bound is the minimum.
    var condition = 7usize
    if signed && (width == 64usize || !wide) { condition = 3usize }
    let (above_low, low_error) = emit_x64.jump_condition(output, condition)
    if low_error != ok { ret low_error }
    try emit_trap(builder, current, token, token_path, "narrow", "a float outside ", "", "", 0usize, false, 0usize, 0usize, into.name, context)
    ret emit_x64.patch_relative32(output, above_low, output.count)
}

// The mirror: above 2**63 `cvttsd2si` has no answer, so the value comes down by that
// much before the conversion and the bit goes back on afterwards. A value out of
// range for the target, and a NaN, get whatever the instruction gives -- section 11's
// saturating release behaviour needs the check table, which nothing emits yet.
fn integer_from_float(destination: usize, unsigned: bool, wide: bool, output: *emit_x64.Buffer) -> err {
    if !unsigned { ret emit_x64.signed_from_float(output, destination, 0usize, wide) }
    try emit_x64.mov_immediate(output, 11usize, two_to_the_sixty_third(wide))
    try emit_x64.move_to_float(output, 1usize, 11usize, wide)
    try emit_x64.float_compare(output, 0usize, 1usize, wide)
    let (big_at, big_error) = emit_x64.jump_condition(output, 3usize)
    if big_error != ok { ret big_error }
    try emit_x64.signed_from_float(output, 10usize, 0usize, wide)
    let (done_at, done_error) = emit_x64.jump(output)
    if done_error != ok { ret done_error }
    try emit_x64.patch_relative32(output, big_at, output.count)
    try emit_x64.float_binary(output, 0usize, 1usize, 92usize, wide)
    try emit_x64.signed_from_float(output, 10usize, 0usize, wide)
    try emit_x64.bit_toggle_high(output, 10usize)
    try emit_x64.patch_relative32(output, done_at, output.count)
    if destination != 10usize { try emit_x64.mov_register(output, destination, 10usize) }
    ret ok
}

fn select_float_cast(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer, context: *FunctionContext) -> err {
    if instruction.operand_count != 1usize || !instruction.has_result { ret Unsupported }
    let source_value = builder.operands[instruction.first_operand]
    let (source_type, source_type_error) = value_type(builder, current, source_value)
    if source_type_error != ok { ret Unsupported }
    // The source reads into r11 and the result out of r10, which leaves the other one
    // free for the unsigned conversions to work in.
    let (source, source_error) = read_value(allocations, source_value, 11usize, output)
    if source_error != ok { ret source_error }
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    let source_width = float_width(source_type)
    let target_width = float_width(instruction.ty)
    if source_type.kind == .Float && instruction.ty.kind == .Float {
        if source_width == 0usize || target_width == 0usize { ret Unsupported }
        if source_width == target_width {
            if destination != source { try emit_x64.mov_register(output, destination, source) }
            ret store_result(allocations, instruction.result, destination, output)
        }
        try emit_x64.move_to_float(output, 0usize, source, source_width == 64usize)
        try emit_x64.float_convert(output, 0usize, 0usize, target_width == 64usize)
        try canonicalize_nan(target_width, output)
        try emit_x64.move_from_float(output, destination, 0usize, target_width == 64usize)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if instruction.ty.kind == .Float {
        if target_width == 0usize || source_type.kind != .Integer { ret Unsupported }
        try float_from_integer(source, unsigned_wide(source_type), target_width == 64usize, output)
        try emit_x64.move_from_float(output, destination, 0usize, target_width == 64usize)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if source_width == 0usize || instruction.ty.kind != .Integer { ret Unsupported }
    try emit_x64.move_to_float(output, 0usize, source, source_width == 64usize)
    var saturated = 0usize
    if instruction.immediate == 0usize && !instruction.nocheck {
        try emit_float_range_check(builder, current, nir.site_token(instruction.site), instruction.path, instruction.ty, source_width == 64usize, context)
    } else {
        // Section 4's release result: the target's extreme for a value past its range,
        // zero for NaN, on every target; the compare sequence branches past the
        // conversion with the answer already in the destination (D204).
        let (done, saturate_error) = emit_float_saturation(destination, instruction.ty, source_width == 64usize, output)
        if saturate_error != ok { ret saturate_error }
        saturated = done
    }
    try integer_from_float(destination, unsigned_wide(instruction.ty), source_width == 64usize, output)
    if saturated != 0usize { try emit_x64.patch_relative32(output, saturated, output.count) }
    try emit_x64.normalize_integer(output, destination, destination, integer_width(instruction.ty), signed_integer(instruction.ty))
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_float(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer, context: *FunctionContext) -> err {
    if instruction.opcode == .Cast { ret select_float_cast(builder, current, instruction, allocations, output, context) }
    if instruction.opcode == .Negate { ret select_float_negate(builder, instruction, allocations, output) }
    if instruction.opcode == .Sqrt { ret select_float_sqrt(builder, instruction, allocations, output) }
    if comparison(instruction.opcode) { ret select_float_comparison(builder, current, instruction, allocations, output) }
    ret select_float_binary(builder, current, instruction, allocations, output)
}

fn parameter_count(builder: *nir.Builder, current: nir.Function) -> (usize, err) {
    var count = 0usize
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Parameter {
            if instruction.immediate != count { ret (0usize, Unsupported) }
            count += 1usize
        }
        at += 1usize
    }
    ret (count, ok)
}

fn parameter_register(abi: Abi, index: usize) -> (usize, err) {
    if abi == .Windows {
        if index == 0usize { ret (1usize, ok) }
        if index == 1usize { ret (2usize, ok) }
        if index == 2usize { ret (8usize, ok) }
        if index == 3usize { ret (9usize, ok) }
        ret (0usize, Unsupported)
    }
    if index == 0usize { ret (7usize, ok) }
    if index == 1usize { ret (6usize, ok) }
    if index == 2usize { ret (2usize, ok) }
    if index == 3usize { ret (1usize, ok) }
    if index == 4usize { ret (8usize, ok) }
    if index == 5usize { ret (9usize, ok) }
    ret (0usize, Unsupported)
}

fn parameter_register_count(abi: Abi) -> usize {
    if abi == .Windows { ret 4usize }
    ret 6usize
}

fn incoming_stack_displacement(abi: Abi, stack_index: usize) -> usize {
    if abi == .Windows { ret 48usize + stack_index * 8usize }
    ret 16usize + stack_index * 8usize
}

fn outgoing_stack_displacement(abi: Abi, stack_index: usize) -> usize {
    if abi == .Windows { ret 32usize + stack_index * 8usize }
    ret stack_index * 8usize
}

// Win64 matches an argument to the register in its own position, so a float in slot 2
// is `xmm2` and the integer register for slot 2 goes unused. System V classifies
// instead: the two files are counted separately, so an integer argument and a float
// argument each advance only their own counter. Everything past the registers keeps
// its order in the overflow area, which is why the stack index is counted here too
// rather than derived from the argument index.
fn classify_argument(abi: Abi, float: bool, index: usize, integer_used: *usize, float_used: *usize, stack_used: *usize, in_register: *bool, register: *usize, stack_index: *usize) -> err {
    *in_register = false
    *register = 0usize
    *stack_index = 0usize
    if abi == .Windows {
        if index < 4usize {
            *in_register = true
            if float {
                *register = index
                ret ok
            }
            let (integer_register, integer_error) = parameter_register(abi, index)
            *register = integer_register
            ret integer_error
        }
        *stack_index = index - 4usize
        ret ok
    }
    if float {
        if *float_used < 8usize {
            *in_register = true
            *register = *float_used
            *float_used += 1usize
            ret ok
        }
    } else {
        if *integer_used < 6usize {
            *in_register = true
            let (integer_register, integer_error) = parameter_register(abi, *integer_used)
            *register = integer_register
            *integer_used += 1usize
            ret integer_error
        }
    }
    *stack_index = *stack_used
    *stack_used += 1usize
    ret ok
}

fn parameter_float_width(builder: *nir.Builder, current: nir.Function, index: usize) -> usize {
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Parameter && instruction.immediate == index { ret float_width(instruction.ty) }
        at += 1usize
    }
    ret 0usize
}

// Every parameter is spilled to its own slot on entry, so the rest of selection never
// has to know which file it arrived in.
fn store_incoming_parameters(builder: *nir.Builder, current: nir.Function, abi: Abi, stack_slots: usize, parameters: usize, output: *emit_x64.Buffer) -> err {
    var integer_used = 0usize
    var float_used = 0usize
    var stack_used = 0usize
    var in_register = false
    var register = 0usize
    var stack_index = 0usize
    var at = 0usize
    while at < parameters {
        let width = parameter_float_width(builder, current, at)
        try classify_argument(abi, width != 0usize, at, &integer_used, &float_used, &stack_used, &in_register, &register, &stack_index)
        if in_register {
            if width == 0usize {
                try emit_x64.store_stack(output, stack_slots + at, register)
            } else {
                try emit_x64.move_from_float(output, 10usize, register, width == 64usize)
                try emit_x64.store_stack(output, stack_slots + at, 10usize)
            }
        } else {
            try emit_x64.load_frame_argument(output, 10usize, incoming_stack_displacement(abi, stack_index))
            try emit_x64.store_stack(output, stack_slots + at, 10usize)
        }
        at += 1usize
    }
    ret ok
}

// The arguments are already parked in the outgoing slots as raw bits; this moves each
// into the place the convention names for it.
// A foreign callee may be a C variadic, and nothing at this level says whether it is,
// so every imported call is made the way a variadic one has to be: Win64 wants a float
// argument in its integer register as well as its xmm, and System V wants `al` to
// carry the count of xmm registers used. Both are harmless to a fixed-arity callee --
// the registers are caller-saved and unused in those positions.
fn load_call_arguments(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, abi: Abi, foreign: bool, first_argument: usize, argument_total: usize, outgoing_base: usize, output: *emit_x64.Buffer) -> err {
    var integer_used = 0usize
    var float_used = 0usize
    var stack_used = 0usize
    var in_register = false
    var register = 0usize
    var stack_index = 0usize
    var at = 0usize
    while at < argument_total {
        let value = builder.operands[instruction.first_operand + first_argument + at]
        let (argument_type, argument_type_error) = value_type(builder, current, value)
        if argument_type_error != ok { ret argument_type_error }
        let width = float_width(argument_type)
        if argument_type.kind == .Float && width == 0usize { ret Unsupported }
        try classify_argument(abi, width != 0usize, at, &integer_used, &float_used, &stack_used, &in_register, &register, &stack_index)
        if in_register {
            if width == 0usize {
                try emit_x64.load_stack(output, register, outgoing_base + at)
            } else {
                try emit_x64.load_stack(output, 10usize, outgoing_base + at)
                try emit_x64.move_to_float(output, register, 10usize, width == 64usize)
                if foreign && abi == .Windows {
                    let (shadow_register, shadow_error) = parameter_register(abi, at)
                    if shadow_error != ok { ret shadow_error }
                    try emit_x64.mov_register(output, shadow_register, 10usize)
                }
            }
        } else {
            try emit_x64.load_stack(output, 10usize, outgoing_base + at)
            try emit_x64.store_call_argument(output, outgoing_stack_displacement(abi, stack_index), 10usize)
        }
        at += 1usize
    }
    if foreign && abi != .Windows { try emit_x64.mov_immediate(output, 0usize, float_used) }
    ret ok
}

// Section 11's symbol table, appended after the last function once the code is final:
// a count, then per emitted function its start relative to the table (negative, the
// code precedes it), its length and its `module.function` name, then the names. Every
// reference to `neper_symbols` -- one per trap site -- is resolved here, so the
// linkers see only a longer code blob. The functions the fold dropped are skipped:
// their offsets are the survivor's, which is the name the walk should print.
fn append_symbol_table(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []Relocation, relocation_count: usize, lines: []LineEntry, line_count: usize) -> err {
    let table_start = machine.count
    var emitted = 0usize
    var at = 0usize
    var line_cursor_1 = 0usize
    var placed_max_1 = 0usize
    while at < builder.function_count {
        if is_placed_after(builder, function_offsets, at, &placed_max_1) { emitted += 1usize }
        at += 1usize
    }
    try emit_x64.little_u32(machine, emitted)
    // Names first, then the paths the line rows share, then the rows themselves;
    // every offset below is from the table's start.
    var names_at = 4usize + emitted * 24usize
    var names_total = 0usize
    at = 0usize
    var line_cursor_2 = 0usize
    var placed_max_2 = 0usize
    while at < builder.function_count {
        if is_placed_after(builder, function_offsets, at, &placed_max_2) {
            names_total += builder.functions[at].module_name.len + 1usize + builder.functions[at].name.len
        }
        at += 1usize
    }
    // The distinct paths, at most one per module, laid out after the names.
    var paths: [8192]str = zero
    var path_offsets: [8192]usize = zero
    var path_count = 0usize
    var paths_total = 0usize
    var row = 0usize
    while row < line_count {
        let (path_index, found) = path_position(paths[..path_count], lines[row].path)
        if !found {
            if path_count == paths.len { ret Unsupported }
            paths[path_count] = lines[row].path
            path_offsets[path_count] = names_at + names_total + paths_total
            paths_total += lines[row].path.len
            path_count += 1usize
        }
        row += 1usize
    }
    let rows_at = names_at + names_total + paths_total
    var rows_written = 0usize
    at = 0usize
    var line_cursor_3 = 0usize
    var placed_max_3 = 0usize
    while at < builder.function_count {
        if is_placed_after(builder, function_offsets, at, &placed_max_3) {
            let placed = builder.functions[at]
            let start = function_offsets[at]
            let (end, end_error) = placed_end_after(builder, function_offsets, at, table_start)
            if end_error != ok { ret end_error }
            var relative = 0usize
            if start <= table_start { relative = 4294967296usize - (table_start - start) }
            if start > table_start { ret Unsupported }
            try emit_x64.little_u32(machine, relative % 4294967296usize)
            try emit_x64.little_u32(machine, end - start)
            try emit_x64.little_u32(machine, names_at)
            let name_length = placed.module_name.len + 1usize + placed.name.len
            try emit_x64.little_u32(machine, name_length)
            names_at += name_length
            let (first_row, row_total) = line_rows_from(lines, line_count, start, end, &line_cursor_3)
            try emit_x64.little_u32(machine, rows_at + rows_written * 16usize)
            try emit_x64.little_u32(machine, row_total)
            rows_written += row_total
        }
        at += 1usize
    }
    at = 0usize
    var line_cursor_4 = 0usize
    var placed_max_4 = 0usize
    while at < builder.function_count {
        if is_placed_after(builder, function_offsets, at, &placed_max_4) {
            let placed = builder.functions[at]
            try emit_text(machine, placed.module_name)
            try emit_x64.byte(machine, 46usize)
            try emit_text(machine, placed.name)
        }
        at += 1usize
    }
    var path_at = 0usize
    while path_at < path_count {
        try emit_text(machine, paths[path_at])
        path_at += 1usize
    }
    at = 0usize
    var line_cursor_5 = 0usize
    var placed_max_5 = 0usize
    while at < builder.function_count {
        if is_placed_after(builder, function_offsets, at, &placed_max_5) {
            let start = function_offsets[at]
            let (end, end_error) = placed_end_after(builder, function_offsets, at, table_start)
            if end_error != ok { ret end_error }
            let (first_row, row_total) = line_rows_from(lines, line_count, start, end, &line_cursor_5)
            var row_at = first_row
            while row_at < first_row + row_total {
                let entry = lines[row_at]
                let (path_index, found) = path_position(paths[..path_count], entry.path)
                if !found { ret Unsupported }
                try emit_x64.little_u32(machine, entry.offset - start)
                try emit_x64.little_u32(machine, entry.line)
                try emit_x64.little_u32(machine, path_offsets[path_index])
                try emit_x64.little_u32(machine, entry.path.len)
                row_at += 1usize
            }
        }
        at += 1usize
    }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.global && !relocation.resolved && relocation.function_ref < builder.function_ref_count && check.same(builder.function_refs[relocation.function_ref].name, "neper_symbols") {
            try emit_x64.patch_relative32(machine, relocation.displacement_at, table_start)
            relocations[relocation_at].resolved = true
        }
        relocation_at += 1usize
    }
    ret ok
}

fn path_position(paths: []const str, path: str) -> (usize, bool) {
    var at = 0usize
    while at < paths.len {
        if check.same(paths[at], path) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// The line rows within one function's code, which are contiguous since the rows are
// appended as the code is.
fn line_rows_of(lines: []LineEntry, line_count: usize, start: usize, end: usize) -> (usize, usize) {
    var first = 0usize
    var found_first = false
    var total = 0usize
    var at = 0usize
    while at < line_count {
        if lines[at].offset >= start && lines[at].offset < end {
            if !found_first {
                first = at
                found_first = true
            }
            total += 1usize
        }
        at += 1usize
    }
    ret (first, total)
}

// Whether a function has its own code: a folded duplicate shares an offset with an
// earlier function, and only the earlier one is listed. Placement is read from the
// offsets alone, so the artifact path, whose functions carry no NIR, agrees.
// A function is placed when its code was emitted rather than folded onto an earlier
// function's: code is emitted in index order, so a placed function's offset is above
// every earlier one's and a folded function's equals an earlier placed one's (D306).
// `placed_max` is the running maximum the caller threads through its loop.
fn is_placed_after(builder: *nir.Builder, function_offsets: []usize, index: usize, placed_max: *usize) -> bool {
    if index >= function_offsets.len || index >= builder.function_count { ret false }
    if index != 0usize && function_offsets[index] <= *placed_max { ret false }
    *placed_max = function_offsets[index]
    ret true
}

// The end of a placed function's code: the first later offset above its own, which is
// the next placed function's start, or the end of the code. The functions between are
// folded ones, each passed over once by the placed function before them.
fn placed_end_after(builder: *nir.Builder, function_offsets: []usize, index: usize, code_end: usize) -> (usize, err) {
    let start = function_offsets[index]
    var at = index + 1usize
    while at < builder.function_count && at < function_offsets.len {
        if function_offsets[at] > start { ret (function_offsets[at], ok) }
        at += 1usize
    }
    if code_end < start { ret (0usize, Unsupported) }
    ret (code_end, ok)
}

// The line rows of a placed function: rows ascend with the code and the functions are
// visited in code order, so a cursor left where the last function ended finds them.
fn line_rows_from(lines: []LineEntry, line_count: usize, start: usize, end: usize, cursor: *usize) -> (usize, usize) {
    var at = *cursor
    if at > line_count { at = line_count }
    while at < line_count && lines[at].offset < start { at += 1usize }
    let first = at
    while at < line_count && lines[at].offset < end { at += 1usize }
    *cursor = at
    ret (first, at - first)
}

fn function_is_placed(builder: *nir.Builder, function_offsets: []usize, index: usize) -> bool {
    if index >= function_offsets.len || index >= builder.function_count { ret false }
    var earlier = 0usize
    while earlier < index {
        if function_offsets[earlier] == function_offsets[index] { ret false }
        earlier += 1usize
    }
    ret true
}

// The end of a placed function's code: the smallest offset above its own, or the
// table's start for the last one.
fn function_placed_end(builder: *nir.Builder, function_offsets: []usize, index: usize, code_end: usize) -> (usize, err) {
    let start = function_offsets[index]
    var end = code_end
    var at = 0usize
    while at < builder.function_count {
        if at != index && at < function_offsets.len && function_offsets[at] > start && function_offsets[at] < end { end = function_offsets[at] }
        at += 1usize
    }
    if end < start { ret (0usize, Unsupported) }
    ret (end, ok)
}

fn max_call_arguments(builder: *nir.Builder, current: nir.Function) -> usize {
    var maximum = 0usize
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Call && instruction.operand_count > maximum { maximum = instruction.operand_count }
        // An indirect call also parks its callee in the outgoing area.
        if instruction.opcode == .IndirectCall && instruction.operand_count > maximum { maximum = instruction.operand_count }
        at += 1usize
    }
    ret maximum
}

fn needs_fixed_registers(builder: *nir.Builder, current: nir.Function) -> bool {
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let opcode = builder.instructions[at].opcode
        if opcode == .Divide || opcode == .Remainder || opcode == .ShiftLeft || opcode == .ShiftRight || opcode == .IndexAddress || opcode == .Slice || opcode == .Copy || opcode == .Call || opcode == .IndirectCall { ret true }
        // An unsigned 64-bit `*` is checked through `mul`, which answers in rdx:rax (D202).
        if opcode == .Multiply && unsigned_wide(builder.instructions[at].ty) { ret true }
        // The read-modify-write forms need rax, and the retried ones rcx as well.
        if opcode == .AtomicRmw || opcode == .AtomicCas { ret true }
        at += 1usize
    }
    ret false
}

fn hex_digit(value: u8) -> (usize, bool) {
    if value >= 48u8 && value <= 57u8 { ret (usize(value - 48u8), true) }
    if value >= 65u8 && value <= 70u8 { ret (usize(value - 65u8) + 10usize, true) }
    if value >= 97u8 && value <= 102u8 { ret (usize(value - 97u8) + 10usize, true) }
    ret (0usize, false)
}

fn string_contents(spelling: str, start: *usize, end: *usize, raw: *bool) -> err {
    if spelling.len >= 2usize && spelling[0usize] == 34u8 && spelling[spelling.len - 1usize] == 34u8 {
        *start = 1usize
        *end = spelling.len - 1usize
        *raw = false
        ret ok
    }
    if spelling.len < 3usize || spelling[0usize] != 114u8 { ret Unsupported }
    var delimiter = 1usize
    var hashes = 0usize
    while delimiter < spelling.len && spelling[delimiter] == 35u8 {
        delimiter += 1usize
        hashes += 1usize
    }
    if delimiter >= spelling.len || spelling[delimiter] != 34u8 || spelling.len < delimiter + hashes + 2usize { ret Unsupported }
    let closing_quote = spelling.len - hashes - 1usize
    if spelling[closing_quote] != 34u8 { ret Unsupported }
    var hash_at = closing_quote + 1usize
    while hash_at < spelling.len {
        if spelling[hash_at] != 35u8 { ret Unsupported }
        hash_at += 1usize
    }
    *start = delimiter + 1usize
    *end = closing_quote
    *raw = true
    ret ok
}

fn emit_string_bytes(output: *emit_x64.Buffer, spelling: str) -> (usize, err) {
    var start = 0usize
    var end = 0usize
    var raw = false
    let contents_error = string_contents(spelling, &start, &end, &raw)
    if contents_error != ok { ret (0usize, contents_error) }
    let output_start = output.count
    var at = start
    while at < end {
        var value = usize(spelling[at])
        if !raw && spelling[at] == 92u8 {
            at += 1usize
            if at >= end { ret (0usize, Unsupported) }
            let escaped = spelling[at]
            if escaped == 110u8 { value = 10usize } else {
            if escaped == 116u8 { value = 9usize } else {
            if escaped == 114u8 { value = 13usize } else {
            if escaped == 92u8 { value = 92usize } else {
            if escaped == 34u8 { value = 34usize } else {
            if escaped == 39u8 { value = 39usize } else {
            if escaped == 48u8 { value = 0usize } else {
            if escaped == 120u8 {
                if at + 2usize >= end { ret (0usize, Unsupported) }
                let (high, high_ok) = hex_digit(spelling[at + 1usize])
                let (low, low_ok) = hex_digit(spelling[at + 2usize])
                if !high_ok || !low_ok { ret (0usize, Unsupported) }
                value = high * 16usize + low
                at += 2usize
            } else {
                ret (0usize, Unsupported)
            }
            }
            }
            }
            }
            }
            }
        }
        }
        let byte_error = emit_x64.byte(output, value)
        if byte_error != ok { ret (0usize, byte_error) }
        at += 1usize
    }
    ret (output.count - output_start, ok)
}

fn select_string(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, local_base: usize, output: *emit_x64.Buffer) -> err {
    if !instruction.has_result || instruction.operand_count != 0usize || instruction.immediate >= builder.string_count { ret Unsupported }
    let (skip_displacement, skip_error) = emit_x64.jump(output)
    if skip_error != ok { ret skip_error }
    let data_offset = output.count
    let (length, data_error) = emit_string_bytes(output, builder.strings[instruction.immediate].spelling)
    if data_error != ok { ret data_error }
    try emit_x64.patch_relative32(output, skip_displacement, output.count)
    let (data_displacement, address_error) = emit_x64.relative_address(output, 11usize)
    if address_error != ok { ret address_error }
    try emit_x64.patch_relative32(output, data_displacement, data_offset)
    let (slot, slot_error) = stack_object_slot(builder, current, instruction.result, local_base)
    if slot_error != ok { ret slot_error }
    try emit_x64.stack_address(output, 10usize, slot)
    try emit_x64.store_memory(output, 10usize, 11usize, 64usize)
    try emit_x64.mov_immediate(output, 11usize, length)
    try emit_x64.add_immediate(output, 10usize, 8usize)
    try emit_x64.store_memory(output, 10usize, 11usize, 64usize)
    try emit_x64.stack_address(output, 10usize, slot)
    let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
    if destination_error != ok { ret destination_error }
    if destination != 10usize { try emit_x64.mov_register(output, destination, 10usize) }
    ret store_result(allocations, instruction.result, destination, output)
}

fn stack_object_count(builder: *nir.Builder, current: nir.Function) -> usize {
    let end = current.first_instruction + current.instruction_count
    var count = 0usize
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Stack || instruction.opcode == .ConstString {
            var slots = 2usize
            if instruction.opcode == .Stack {
                slots = instruction.immediate
                if slots == 0usize { slots = 1usize }
            }
            count += slots
        }
        at += 1usize
    }
    ret count
}

fn stack_object_slot(builder: *nir.Builder, current: nir.Function, value: usize, base: usize) -> (usize, err) {
    let end = current.first_instruction + current.instruction_count
    var count = 0usize
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Stack || instruction.opcode == .ConstString {
            var slots = 2usize
            if instruction.opcode == .Stack {
                slots = instruction.immediate
                if slots == 0usize { slots = 1usize }
            }
            if instruction.has_result && instruction.result == value { ret (base + count + slots - 1usize, ok) }
            count += slots
        }
        at += 1usize
    }
    ret (0usize, Unsupported)
}

fn save_allocated_registers(output: *emit_x64.Buffer, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        let (physical, physical_error) = hardware_register(at)
        if physical_error != ok { ret physical_error }
        try emit_x64.store_stack(output, base + at, physical)
        at += 1usize
    }
    ret ok
}

// The allocated registers holding a value that is live across `instruction_index` --
// defined before it and used after -- as a bit per register, in one pass over the
// values. A value the instruction itself defines, or one whose last use is an operand
// of it, needs no saving. Without the ranges every register is live.
fn live_register_mask(context: *FunctionContext, value_count: usize, instruction_index: usize, count: usize) -> usize {
    if context.ranges.len < value_count {
        let every = 1usize << count
        ret every - 1usize
    }
    if context.live_masks.len != 0usize && instruction_index >= context.live_base && instruction_index - context.live_base < context.live_masks.len {
        let every = 1usize << count
        ret context.live_masks[instruction_index - context.live_base] & (every - 1usize)
    }
    var mask = 0usize
    var value = 0usize
    while value < value_count {
        let allocation = context.allocations[value]
        if allocation.kind == .Register && allocation.index < count {
            let range = context.ranges[value]
            if range.defined && range.first < instruction_index && range.last > instruction_index { mask = mask | (1usize << allocation.index) }
        }
        value += 1usize
    }
    ret mask
}

// The registers a fixed-register sequence saves (D236): of the ones it clobbers,
// those holding a value live across it -- and, when it reads its operands back from
// the preserve area, the ones the operands sit in. `context.failure_instruction` is
// the instruction being selected.
fn preserve_mask(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, clobbered: usize, operands_too: bool, context: *FunctionContext) -> usize {
    var mask = live_register_mask(context, current.value_count, context.failure_instruction, caller_saved_count()) & clobbered
    if operands_too {
        var operand_at = 0usize
        while operand_at < instruction.operand_count {
            let value = builder.operands[instruction.first_operand + operand_at]
            if value < context.allocations.len && context.allocations[value].kind == .Register && context.allocations[value].index < caller_saved_count() { mask = mask | (1usize << context.allocations[value].index) }
            operand_at += 1usize
        }
    }
    ret mask
}

fn save_live_registers(output: *emit_x64.Buffer, mask: usize, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        if (mask >> at) & 1usize == 1usize {
            let (physical, physical_error) = hardware_register(at)
            if physical_error != ok { ret physical_error }
            try emit_x64.store_stack(output, base + at, physical)
        }
        at += 1usize
    }
    ret ok
}

fn restore_live_registers(output: *emit_x64.Buffer, mask: usize, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        if (mask >> at) & 1usize == 1usize {
            let (physical, physical_error) = hardware_register(at)
            if physical_error != ok { ret physical_error }
            try emit_x64.load_stack(output, physical, base + at)
        }
        at += 1usize
    }
    ret ok
}

fn restore_allocated_registers(output: *emit_x64.Buffer, base: usize, count: usize) -> err {
    var at = 0usize
    while at < count {
        let (physical, physical_error) = hardware_register(at)
        if physical_error != ok { ret physical_error }
        try emit_x64.load_stack(output, physical, base + at)
        at += 1usize
    }
    ret ok
}

fn select_zero(builder: *nir.Builder, instruction: nir.Instruction, allocations: []regalloc.Allocation, output: *emit_x64.Buffer) -> err {
    if instruction.has_result {
        if instruction.operand_count != 0usize { ret Unsupported }
        let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
        if destination_error != ok { ret destination_error }
        try emit_x64.mov_immediate(output, destination, 0usize)
        ret store_result(allocations, instruction.result, destination, output)
    }
    if instruction.operand_count != 1usize { ret Unsupported }
    let address = builder.operands[instruction.first_operand]
    let (address_register, address_error) = read_value(allocations, address, 10usize, output)
    if address_error != ok { ret InvalidMemoryAddress }
    ret emit_x64.zero_memory(output, address_register, instruction.immediate)
}

// Section 11's trap protocol. A check that fails reaches the runtime's `neper_trap` with
// the record -- `file:line:col: trap[kind]: ` and the values' text, a NUL where each of
// the two operands goes -- and the operands themselves, and never returns. The text is
// laid out inline and jumped over, the way a string constant is. The operands move
// first, since the text's register is one they may sit in.
fn emit_text(output: *emit_x64.Buffer, text: str) -> err {
    var at = 0usize
    while at < text.len {
        try emit_x64.byte(output, usize(text[at]))
        at += 1usize
    }
    ret ok
}

fn emit_decimal(output: *emit_x64.Buffer, value: usize) -> err {
    if value >= 10usize { try emit_decimal(output, value / 10usize) }
    ret emit_x64.byte(output, 48usize + value % 10usize)
}

fn emit_trap(builder: *nir.Builder, current: nir.Function, token: lex.Token, token_path: str, kind: str, first: str, second: str, third: str, values: usize, signed: bool, a: usize, b: usize, tail: str, context: *FunctionContext) -> err {
    let output = context.output
    var first_register = 8usize
    var second_register = 9usize
    var text_register = 1usize
    var length_register = 2usize
    if context.abi != .Windows {
        first_register = 2usize
        second_register = 1usize
        text_register = 7usize
        length_register = 6usize
    }
    if values >= 1usize && a != first_register { try emit_x64.mov_register(output, first_register, a) }
    if values >= 2usize && b != second_register { try emit_x64.mov_register(output, second_register, b) }
    let (skip, skip_error) = emit_x64.jump(output)
    if skip_error != ok { ret skip_error }
    let text_start = output.count
    var site_path = token_path
    if site_path.len == 0usize { site_path = current.path }
    try emit_text(output, site_path)
    try emit_x64.byte(output, 58usize)
    try emit_decimal(output, token.line)
    try emit_x64.byte(output, 58usize)
    try emit_decimal(output, token.column)
    try emit_text(output, ": trap[")
    try emit_text(output, kind)
    try emit_text(output, "]: ")
    try emit_text(output, first)
    // The separator byte says how the runtime prints the operand: 0 unsigned, 1 signed.
    var separator = 0usize
    if signed { separator = 1usize }
    if values >= 1usize {
        try emit_x64.byte(output, separator)
        try emit_text(output, second)
    }
    if values >= 2usize {
        try emit_x64.byte(output, separator)
        try emit_text(output, third)
    }
    try emit_text(output, tail)
    let text_end = output.count
    try emit_x64.patch_relative32(output, skip, text_end)
    let (text_displacement, address_error) = emit_x64.relative_address(output, text_register)
    if address_error != ok { ret address_error }
    try emit_x64.patch_relative32(output, text_displacement, text_start)
    try emit_x64.mov_immediate(output, length_register, text_end - text_start)
    // r10 carries the symbol table the driver appends after the code (D206); the
    // reference is resolved there, not by a linker.
    let (symbols_ref, symbols_error) = nir.intern_function(builder, current.module_index, "neper_symbols", 0usize)
    if symbols_error != ok { ret symbols_error }
    let (symbols_displacement, symbols_address_error) = emit_x64.relative_address(output, 10usize)
    if symbols_address_error != ok { ret symbols_address_error }
    try add_relocation(context.relocations, context.relocation_count, symbols_displacement, symbols_ref)
    let (function_ref, reference_error) = nir.intern_function(builder, current.module_index, "neper_trap", 0usize)
    if reference_error != ok { ret reference_error }
    let (call_displacement, call_error) = emit_x64.call(output)
    if call_error != ok { ret call_error }
    ret add_relocation(context.relocations, context.relocation_count, call_displacement, function_ref)
}

// Section 11's `overflow` row for `+ - *` and unary `-`, which trap in a debug build
// and wrap in release (nothing selects release yet). Below 64 bits the operands are
// sign- or zero-extended, so the 64-bit result is exact and overflow is the
// normalised result differing from it; at 64 bits the flags say: OF for a signed
// operation, CF for an unsigned one. `destination` holds the exact result and r11 is
// free, the right operand being consumed. The record names the type and operator.
fn emit_overflow_check(builder: *nir.Builder, current: nir.Function, token: lex.Token, token_path: str, ty: check.Type, operator: str, destination: usize, context: *FunctionContext) -> err {
    let output = context.output
    let width = integer_width(ty)
    let signed = signed_integer(ty)
    var over = 0usize
    if width == 64usize {
        var condition = 3usize
        if signed { condition = 1usize }
        let (flagged, flag_error) = emit_x64.jump_condition(output, condition)
        if flag_error != ok { ret flag_error }
        over = flagged
    } else {
        try emit_x64.mov_register(output, 11usize, destination)
        try emit_x64.normalize_integer(output, destination, destination, width, signed)
        try emit_x64.compare_register(output, destination, 11usize)
        let (same, same_error) = emit_x64.jump_condition(output, 4usize)
        if same_error != ok { ret same_error }
        over = same
    }
    try emit_trap(builder, current, token, token_path, "overflow", ty.name, "", "", 0usize, false, 0usize, 0usize, operator, context)
    ret emit_x64.patch_relative32(output, over, output.count)
}

// `cmp a, b; jcc over; <trap>; over:` -- the check passes when `condition` holds.
fn emit_checked(builder: *nir.Builder, current: nir.Function, token: lex.Token, token_path: str, condition: usize, kind: str, first: str, second: str, third: str, a: usize, b: usize, context: *FunctionContext) -> err {
    try emit_x64.compare_register(context.output, a, b)
    let (over, over_error) = emit_x64.jump_condition(context.output, condition)
    if over_error != ok { ret over_error }
    try emit_trap(builder, current, token, token_path, kind, first, second, third, 2usize, false, a, b, "", context)
    ret emit_x64.patch_relative32(context.output, over, context.output.count)
}

// Section 11's `divide` rows, which trap in every mode: the divisor is zero, or the
// division is the one two's complement cannot represent. The dividend is in rax and the
// divisor in r11, as the instruction wants them; r10 is free for the constants.
fn emit_divide_checks(builder: *nir.Builder, current: nir.Function, token: lex.Token, token_path: str, remainder: bool, width: usize, signed: bool, context: *FunctionContext) -> err {
    let output = context.output
    var operator = " / "
    if remainder { operator = " % " }
    try emit_x64.test_register(output, 11usize)
    let (nonzero, nonzero_error) = emit_x64.jump_condition(output, 5usize)
    if nonzero_error != ok { ret nonzero_error }
    try emit_trap(builder, current, token, token_path, "divide", "", operator, " divides by zero", 2usize, signed, 0usize, 11usize, "", context)
    try emit_x64.patch_relative32(output, nonzero, output.count)
    if !signed { ret ok }
    let all_ones = 0usize -% 1usize
    try emit_x64.mov_immediate(output, 10usize, all_ones)
    try emit_x64.compare_register(output, 11usize, 10usize)
    let (not_minus_one, minus_one_error) = emit_x64.jump_condition(output, 5usize)
    if minus_one_error != ok { ret minus_one_error }
    // The minimum of the width, sign-extended to the register the operands sit in.
    let minimum = all_ones - (all_ones >> (65usize - width))
    try emit_x64.mov_immediate(output, 10usize, minimum)
    try emit_x64.compare_register(output, 0usize, 10usize)
    let (not_minimum, minimum_error) = emit_x64.jump_condition(output, 5usize)
    if minimum_error != ok { ret minimum_error }
    try emit_trap(builder, current, token, token_path, "divide", "", operator, " overflows", 2usize, true, 0usize, 11usize, "", context)
    try emit_x64.patch_relative32(output, not_minus_one, output.count)
    ret emit_x64.patch_relative32(output, not_minimum, output.count)
}

// Section 11's `shift` row: a count at or past the width. The count is in rcx and the
// value in r10; r11 is free for the width.
fn emit_shift_check(builder: *nir.Builder, current: nir.Function, token: lex.Token, token_path: str, width: usize, context: *FunctionContext) -> err {
    try emit_x64.mov_immediate(context.output, 11usize, width)
    ret emit_checked(builder, current, token, token_path, 2usize, "shift", "shift by ", " on a width of ", "", 1usize, 11usize, context)
}

fn select_index_address(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, preserve_base: usize, preserve_count: usize, context: *FunctionContext) -> err {
    let output = context.output
    if !instruction.has_result || instruction.operand_count != 3usize || instruction.immediate == 0usize { ret Unsupported }
    // Only the check needs the length, in rax; without it nothing is clobbered.
    var mask = 0usize
    if !instruction.nocheck { mask = preserve_mask(builder, current, instruction, 1usize, false, context) }
    try save_live_registers(output, mask, preserve_base, preserve_count)
    let base_value = builder.operands[instruction.first_operand]
    let index_value = builder.operands[instruction.first_operand + 1usize]
    let length_value = builder.operands[instruction.first_operand + 2usize]
    let (base, base_error) = read_value(allocations, base_value, 10usize, output)
    if base_error != ok { ret base_error }
    if base != 10usize { try emit_x64.mov_register(output, 10usize, base) }
    let (index, index_error) = read_value(allocations, index_value, 11usize, output)
    if index_error != ok { ret index_error }
    if index != 11usize { try emit_x64.mov_register(output, 11usize, index) }
    if !instruction.nocheck {
        let (length, length_error) = read_value(allocations, length_value, 0usize, output)
        if length_error != ok { ret length_error }
        if length != 0usize { try emit_x64.mov_register(output, 0usize, length) }
        try emit_checked(builder, current, nir.site_token(instruction.site), instruction.path, 2usize, "bounds", "index ", " out of bounds for len ", "", 11usize, 0usize, context)
    }
    if instruction.immediate != 1usize { try emit_x64.multiply_immediate(output, 11usize, 11usize, instruction.immediate) }
    try emit_x64.add_register(output, 11usize, 10usize)
    try restore_live_registers(output, mask, preserve_base, preserve_count)
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    if destination != 11usize { try emit_x64.mov_register(output, destination, 11usize) }
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_slice(builder: *nir.Builder, current: nir.Function, instruction: nir.Instruction, allocations: []regalloc.Allocation, preserve_base: usize, preserve_count: usize, context: *FunctionContext) -> err {
    let output = context.output
    if instruction.has_result || instruction.operand_count != 5usize || instruction.immediate == 0usize { ret Unsupported }
    let mask = preserve_mask(builder, current, instruction, 19usize, true, context)
    try save_live_registers(output, mask, preserve_base, preserve_count)
    let destination_value = builder.operands[instruction.first_operand]
    let data_value = builder.operands[instruction.first_operand + 1usize]
    let length_value = builder.operands[instruction.first_operand + 2usize]
    let lower_value = builder.operands[instruction.first_operand + 3usize]
    let upper_value = builder.operands[instruction.first_operand + 4usize]
    let (destination_source, destination_error) = read_preserved_value(allocations, destination_value, 9usize, preserve_base, output)
    if destination_error != ok { ret destination_error }
    if destination_source != 9usize { try emit_x64.mov_register(output, 9usize, destination_source) }
    let (data_source, data_error) = read_preserved_value(allocations, data_value, 10usize, preserve_base, output)
    if data_error != ok { ret data_error }
    if data_source != 10usize { try emit_x64.mov_register(output, 10usize, data_source) }
    let (length_source, length_error) = read_preserved_value(allocations, length_value, 11usize, preserve_base, output)
    if length_error != ok { ret length_error }
    if length_source != 11usize { try emit_x64.mov_register(output, 11usize, length_source) }
    let (lower_source, lower_error) = read_preserved_value(allocations, lower_value, 0usize, preserve_base, output)
    if lower_error != ok { ret lower_error }
    if lower_source != 0usize { try emit_x64.mov_register(output, 0usize, lower_source) }
    let (upper_source, upper_error) = read_preserved_value(allocations, upper_value, 1usize, preserve_base, output)
    if upper_error != ok { ret upper_error }
    if upper_source != 1usize { try emit_x64.mov_register(output, 1usize, upper_source) }
    if !instruction.nocheck {
        try emit_checked(builder, current, nir.site_token(instruction.site), instruction.path, 6usize, "bounds", "slice start ", " after end ", "", 0usize, 1usize, context)
        try emit_checked(builder, current, nir.site_token(instruction.site), instruction.path, 6usize, "bounds", "slice end ", " out of bounds for len ", "", 1usize, 11usize, context)
    }
    try emit_x64.subtract_register(output, 1usize, 0usize)
    if instruction.immediate != 1usize { try emit_x64.multiply_immediate(output, 0usize, 0usize, instruction.immediate) }
    try emit_x64.add_register(output, 10usize, 0usize)
    try emit_x64.store_memory(output, 9usize, 10usize, 64usize)
    try emit_x64.add_immediate(output, 9usize, 8usize)
    try emit_x64.store_memory(output, 9usize, 1usize, 64usize)
    ret restore_live_registers(output, mask, preserve_base, preserve_count)
}

// For every instruction of the function, the registers holding a value live strictly
// across it: a value in register r contributes r over (first, last) exclusive. Built as
// one difference array per register and a prefix sum, so the cost is the values plus
// the instructions, not their product.
fn build_live_masks(builder: *nir.Builder, current: nir.Function, context: *FunctionContext, deltas: []usize, masks: []usize) -> err {
    let count = current.instruction_count
    var at = 0usize
    while at < count * 16usize {
        deltas[at] = 0usize
        at += 1usize
    }
    var value = 0usize
    while value < current.value_count {
        let allocation = context.allocations[value]
        if allocation.kind == .Register && allocation.index < 16usize {
            let range = context.ranges[value]
            if range.defined && range.last > range.first + 1usize && range.first >= current.first_instruction {
                let from = range.first + 1usize - current.first_instruction
                var to = range.last - current.first_instruction
                if to > count { to = count }
                if from < count { deltas[allocation.index * count + from] += 1usize }
                if to < count { deltas[allocation.index * count + to] = deltas[allocation.index * count + to] -% 1usize }
            }
        }
        value += 1usize
    }
    at = 0usize
    while at < count {
        masks[at] = 0usize
        at += 1usize
    }
    var register = 0usize
    while register < 16usize {
        var live = 0usize
        at = 0usize
        while at < count {
            live = live +% deltas[register * count + at]
            if live != 0usize { masks[at] = masks[at] | (1usize << register) }
            at += 1usize
        }
        register += 1usize
    }
    ret ok
}

fn function(builder: *nir.Builder, function_index: usize, stack_slots: usize, context: *FunctionContext) -> err {
    if !context.has_arena || function_index >= builder.function_count {
        context.live_masks = context.live_masks[0usize..0usize]
        ret function_body(builder, function_index, stack_slots, context)
    }
    let current = builder.functions[function_index]
    let mark = mem.mark(context.arena)
    let (deltas, deltas_error) = mem.alloc[usize](context.arena, current.instruction_count * 16usize + 1usize)
    if deltas_error != ok { ret deltas_error }
    let (masks, masks_error) = mem.alloc[usize](context.arena, current.instruction_count + 1usize)
    if masks_error != ok { ret masks_error }
    try build_live_masks(builder, current, context, deltas, masks)
    context.live_masks = masks[0usize..current.instruction_count]
    context.live_base = current.first_instruction
    let body_error = function_body(builder, function_index, stack_slots, context)
    context.live_masks = context.live_masks[0usize..0usize]
    mem.reset(context.arena, mark)
    ret body_error
}

fn function_body(builder: *nir.Builder, function_index: usize, stack_slots: usize, context: *FunctionContext) -> err {
    let allocations = context.allocations
    let abi = context.abi
    let block_offsets = context.block_offsets
    let fixups = context.fixups
    let relocations = context.relocations
    let relocation_count = context.relocation_count
    let output = context.output
    if function_index >= builder.function_count { ret Unsupported }
    let current = builder.functions[function_index]
    if current.block_count > block_offsets.len { ret Unsupported }
    let function_code_start = output.count
    let (parameters, parameters_error) = parameter_count(builder, current)
    if parameters_error != ok { ret parameters_error }
    let local_count = stack_object_count(builder, current)
    let local_base = stack_slots + parameters
    let outgoing = max_call_arguments(builder, current)
    let outgoing_base = local_base + local_count
    let preserve_base = outgoing_base + outgoing
    var preserve_count = 0usize
    var call_area_count = 0usize
    if outgoing != 0usize || needs_fixed_registers(builder, current) {
        preserve_count = 5usize
    }
    if outgoing != 0usize {
        let register_count = parameter_register_count(abi)
        if abi == .Windows { call_area_count = 4usize }
        if outgoing > register_count { call_area_count += outgoing - register_count }
    }
    // The callee-saved registers in use are kept in slots of their own, between the
    // preserve area and the call area, which has to stay at the bottom (D235).
    let saved_base = preserve_base + preserve_count
    let saved_count = callee_saved_count(allocations, current.value_count)
    let frame_slots = saved_base + saved_count + call_area_count
    // Every function has a frame, even one with no slots: the backtrace walks the rbp
    // chain, and a frameless function that calls -- or traps -- would be no frame in
    // it, and its caller would be skipped (D212).
    try emit_x64.function_prologue(output, frame_slots)
    try save_callee_registers(output, saved_base, saved_count)
    try store_incoming_parameters(builder, current, abi, stack_slots, parameters, output)
    let end = current.first_instruction + current.instruction_count
    var fixup_count = 0usize
    var at = current.first_instruction
    // Blocks begin in instruction order, so the next block to start is a cursor, not a
    // scan of every block per instruction (D305).
    var next_block = 0usize
    while at < end {
        while next_block < current.block_count && builder.blocks[current.first_block + next_block].first_instruction == at {
            block_offsets[next_block] = output.count
            next_block += 1usize
        }
        let instruction = builder.instructions[at]
        context.failure_token = nir.site_token(instruction.site)
        context.failure_instruction = at
        // The line table: a row wherever the line or the file changes (D209).
        if instruction.site.line != 0usize {
            var line_path = instruction.path
            if line_path.len == 0usize { line_path = current.path }
            let line_count = *context.line_count
            var changed = true
            if line_count != 0usize {
                let last = context.lines[line_count - 1usize]
                if last.line == instruction.site.line && check.same(last.path, line_path) && last.offset >= function_code_start { changed = false }
            }
            if changed {
                if line_count == context.lines.len { ret Unsupported }
                context.lines[line_count] = LineEntry { offset: output.count, line: instruction.site.line, path: line_path }
                *context.line_count = line_count + 1usize
            }
        }
        if instruction.opcode == .Bitcast {
            try select_bitcast(builder, instruction, allocations, context)
        } else {
        if float_operation(builder, current, instruction) {
            try select_float(builder, current, instruction, allocations, output, context)
        } else {
        if instruction.opcode == .Parameter {
            if instruction.immediate >= parameters { ret Unsupported }
            let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
            if destination_error != ok { ret destination_error }
            try emit_x64.load_stack(output, destination, stack_slots + instruction.immediate)
            try store_result(allocations, instruction.result, destination, output)
        } else {
            if instruction.opcode == .Stack {
                if !instruction.has_result || instruction.operand_count != 0usize { ret Unsupported }
                let (slot, slot_error) = stack_object_slot(builder, current, instruction.result, local_base)
                if slot_error != ok { ret slot_error }
                let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
                if destination_error != ok { ret destination_error }
                try emit_x64.stack_address(output, destination, slot)
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if instruction.opcode == .GlobalAddress {
                // `lea` from the instruction pointer, with the displacement left for whoever
                // lays the image out. Nothing is emitted inline: the storage is one place in the
                // image and this only names it.
                if !instruction.has_result || instruction.operand_count != 0usize || instruction.immediate >= builder.global_count { ret Unsupported }
                let (address_displacement, address_error) = emit_x64.relative_address(output, 11usize)
                if address_error != ok { ret address_error }
                try add_global_relocation(relocations, relocation_count, address_displacement, instruction.immediate)
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                if destination != 11usize { try emit_x64.mov_register(output, destination, 11usize) }
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if instruction.opcode == .ConstString {
                try select_string(builder, current, instruction, allocations, local_base, output)
            } else {
            if instruction.opcode == .Store {
                if instruction.has_result || instruction.operand_count != 2usize { ret Unsupported }
                let address = builder.operands[instruction.first_operand]
                let value = builder.operands[instruction.first_operand + 1usize]
                let width = storage_width(instruction)
                if width == 0usize { ret InvalidStoreWidth }
                let (address_register, address_error) = read_value(allocations, address, 11usize, output)
                if address_error != ok { ret InvalidMemoryAddress }
                let (source, source_error) = read_value(allocations, value, 10usize, output)
                if source_error != ok { ret source_error }
                try emit_x64.store_memory(output, address_register, source, width)
            } else {
            if instruction.opcode == .Copy {
                if instruction.has_result || instruction.operand_count != 2usize { ret Unsupported }
                let copy_mask = preserve_mask(builder, current, instruction, 17usize, false, context)
                try save_live_registers(output, copy_mask, preserve_base, preserve_count)
                let destination_value = builder.operands[instruction.first_operand]
                let source_value = builder.operands[instruction.first_operand + 1usize]
                let (destination_source, destination_error) = read_value(allocations, destination_value, 10usize, output)
                if destination_error != ok { ret destination_error }
                if destination_source != 10usize { try emit_x64.mov_register(output, 10usize, destination_source) }
                let (source, source_error) = read_value(allocations, source_value, 11usize, output)
                if source_error != ok { ret source_error }
                if source != 11usize { try emit_x64.mov_register(output, 11usize, source) }
                try emit_x64.copy_memory(output, 10usize, 11usize, instruction.immediate)
                try restore_live_registers(output, copy_mask, preserve_base, preserve_count)
            } else {
            if instruction.opcode == .Load {
                if !instruction.has_result || instruction.operand_count != 1usize { ret Unsupported }
                let address = builder.operands[instruction.first_operand]
                let width = storage_width(instruction)
                if width == 0usize { ret InvalidLoadWidth }
                let (address_register, address_error) = read_value(allocations, address, 10usize, output)
                if address_error != ok { ret InvalidMemoryAddress }
                let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
                if destination_error != ok { ret destination_error }
                try emit_x64.load_memory(output, destination, address_register, width, signed_integer(instruction.ty))
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if instruction.opcode == .FieldAddress {
                if !instruction.has_result || instruction.operand_count != 1usize { ret InvalidFieldAddress }
                let address = builder.operands[instruction.first_operand]
                let (source, source_error) = read_value(allocations, address, 10usize, output)
                if source_error != ok { ret source_error }
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                if destination != source { try emit_x64.mov_register(output, destination, source) }
                if instruction.immediate != 0usize { try emit_x64.add_immediate(output, destination, instruction.immediate) }
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if instruction.opcode == .AtomicLoad || instruction.opcode == .AtomicStore || instruction.opcode == .AtomicRmw || instruction.opcode == .AtomicCas || instruction.opcode == .AtomicFence {
                try select_atomic(builder, current, instruction, allocations, preserve_base, preserve_count, context)
            } else {
            if instruction.opcode == .Zero {
                try select_zero(builder, instruction, allocations, output)
            } else {
            if instruction.opcode == .IndexAddress {
                try select_index_address(builder, current, instruction, allocations, preserve_base, preserve_count, context)
            } else {
            if instruction.opcode == .Slice {
                try select_slice(builder, current, instruction, allocations, preserve_base, preserve_count, context)
            } else {
            if instruction.opcode == .Cast || instruction.opcode == .Negate || instruction.opcode == .BitNot {
                if instruction.operand_count != 1usize || instruction.ty.kind != .Integer { ret Unsupported }
                let operand_value = builder.operands[instruction.first_operand]
                let (source_type, source_type_error) = value_type(builder, current, operand_value)
                if source_type_error != ok { ret Unsupported }
                // A cast out of an enum reaches here with the named source type;
                // its width and signedness come from the target, which lowering
                // has already resolved to the enum's backing integer.
                let named_source = source_type.kind == .Named && instruction.opcode == .Cast
                if source_type.kind != .Integer && !named_source { ret Unsupported }
                let (source, source_error) = read_value(allocations, operand_value, 10usize, output)
                if source_error != ok { ret source_error }
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                if instruction.opcode == .Cast {
                    var normalize_type = instruction.ty
                    if source_type.kind == .Integer && integer_width(normalize_type) == 64usize { normalize_type = source_type }
                    // Section 11's `narrow` row: a cast to a narrower width has to give the
                    // value back when widened again, or the value did not fit. The source
                    // is kept in whichever scratch register the result is not in, since
                    // the result may land in the source's own register.
                    // A cast whose immediate is 1 is `T.trunc(x)`, meant and unchecked. At a
                    // 64-bit target the normalisation is a no-op, so a sign that would
                    // change is what is tested instead.
                    let sign_differs = signed_integer(source_type) != signed_integer(instruction.ty)
                    let narrowing = source_type.kind == .Integer && instruction.immediate == 0usize && !instruction.nocheck && (integer_width(instruction.ty) < integer_width(source_type) || sign_differs)
                    var kept = 10usize
                    if destination == 10usize { kept = 11usize }
                    if narrowing && source != kept { try emit_x64.mov_register(output, kept, source) }
                    try emit_x64.normalize_integer(output, destination, source, integer_width(normalize_type), signed_integer(normalize_type))
                    if narrowing {
                        var fits = 0usize
                        if integer_width(instruction.ty) == 64usize {
                            try emit_x64.test_register(output, kept)
                            let (not_negative, sign_error) = emit_x64.jump_condition(output, 9usize)
                            if sign_error != ok { ret sign_error }
                            fits = not_negative
                        } else {
                            try emit_x64.compare_register(output, destination, kept)
                            let (equal, equal_error) = emit_x64.jump_condition(output, 4usize)
                            if equal_error != ok { ret equal_error }
                            fits = equal
                        }
                        try emit_trap(builder, current, nir.site_token(instruction.site), instruction.path, "narrow", "", " does not fit ", "", 1usize, signed_integer(source_type), kept, 0usize, instruction.ty.name, context)
                        try emit_x64.patch_relative32(output, fits, output.count)
                    }
                } else {
                    if destination != source { try emit_x64.mov_register(output, destination, source) }
                    if instruction.opcode == .Negate { try emit_x64.negate_register(output, destination) }
                    if instruction.opcode == .BitNot { try emit_x64.bit_not_register(output, destination) }
                    let negated = instruction.opcode == .Negate && signed_integer(instruction.ty) && !instruction.nocheck
                    if negated { try emit_overflow_check(builder, current, nir.site_token(instruction.site), instruction.path, instruction.ty, " unary - overflows", destination, context) }
                    if !(negated && integer_width(instruction.ty) != 64usize) { try emit_x64.normalize_integer(output, destination, destination, integer_width(instruction.ty), signed_integer(instruction.ty)) }
                }
                try store_result(allocations, instruction.result, destination, output)
            } else {
        if instruction.opcode == .ConstInteger || instruction.opcode == .ConstBool || instruction.opcode == .ConstError || instruction.opcode == .ConstFloat {
            let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
            if destination_error != ok { ret destination_error }
            try emit_x64.mov_immediate(output, destination, instruction.immediate)
            try store_result(allocations, instruction.result, destination, output)
        } else {
            if instruction.opcode == .ShiftLeft || instruction.opcode == .ShiftRight {
                if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret Unsupported }
                let left_value = builder.operands[instruction.first_operand]
                let right_value = builder.operands[instruction.first_operand + 1usize]
                let (left_type, left_type_error) = value_type(builder, current, left_value)
                if left_type_error != ok || left_type.kind != .Integer { ret Unsupported }
                let shift_mask = preserve_mask(builder, current, instruction, 2usize, false, context)
                try save_live_registers(output, shift_mask, preserve_base, preserve_count)
                let (left, left_error) = read_value(allocations, left_value, 10usize, output)
                if left_error != ok { ret left_error }
                let (right, right_error) = read_value(allocations, right_value, 11usize, output)
                if right_error != ok { ret right_error }
                if left != 10usize { try emit_x64.mov_register(output, 10usize, left) }
                if right != 1usize { try emit_x64.mov_register(output, 1usize, right) }
                if !instruction.nocheck { try emit_shift_check(builder, current, nir.site_token(instruction.site), instruction.path, integer_width(left_type), context) }
                try emit_x64.and_immediate8(output, 1usize, integer_width(left_type) - 1usize)
                try emit_x64.shift_register(output, 10usize, instruction.opcode == .ShiftLeft, signed_integer(left_type))
                try restore_live_registers(output, shift_mask, preserve_base, preserve_count)
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                try emit_x64.normalize_integer(output, destination, 10usize, integer_width(instruction.ty), signed_integer(instruction.ty))
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if instruction.opcode == .Divide || instruction.opcode == .Remainder || (instruction.opcode == .Multiply && unsigned_wide(instruction.ty)) {
                if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret Unsupported }
                let left_value = builder.operands[instruction.first_operand]
                let right_value = builder.operands[instruction.first_operand + 1usize]
                let (left_type, left_type_error) = value_type(builder, current, left_value)
                if left_type_error != ok || left_type.kind != .Integer { ret Unsupported }
                let divide_mask = preserve_mask(builder, current, instruction, 5usize, false, context)
                try save_live_registers(output, divide_mask, preserve_base, preserve_count)
                let (left, left_error) = read_value(allocations, left_value, 10usize, output)
                if left_error != ok { ret left_error }
                let (right, right_error) = read_value(allocations, right_value, 11usize, output)
                if right_error != ok { ret right_error }
                if right != 11usize { try emit_x64.mov_register(output, 11usize, right) }
                if left != 0usize { try emit_x64.mov_register(output, 0usize, left) }
                if instruction.opcode == .Multiply {
                    // An unsigned 64-bit `*` through `mul`: rdx:rax, and a nonzero high
                    // half is section 11's overflow (D202).
                    try emit_x64.multiply_unsigned_register(output, 11usize)
                    if !instruction.nocheck {
                        try emit_x64.test_register(output, 2usize)
                        let (fits, fits_error) = emit_x64.jump_condition(output, 4usize)
                        if fits_error != ok { ret fits_error }
                        try emit_trap(builder, current, nir.site_token(instruction.site), instruction.path, "overflow", instruction.ty.name, "", "", 0usize, false, 0usize, 0usize, " * overflows", context)
                        try emit_x64.patch_relative32(output, fits, output.count)
                    }
                    try emit_x64.mov_register(output, 10usize, 0usize)
                } else {
                let signed = signed_integer(left_type)
                try emit_divide_checks(builder, current, nir.site_token(instruction.site), instruction.path, instruction.opcode == .Remainder, integer_width(left_type), signed, context)
                if signed { try emit_x64.extend_dividend_signed(output) } else { try emit_x64.extend_dividend_unsigned(output) }
                try emit_x64.divide_register(output, 11usize, signed)
                if instruction.opcode == .Divide {
                    try emit_x64.mov_register(output, 10usize, 0usize)
                } else {
                    try emit_x64.mov_register(output, 10usize, 2usize)
                }
                }
                try restore_live_registers(output, divide_mask, preserve_base, preserve_count)
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                try emit_x64.normalize_integer(output, destination, 10usize, integer_width(instruction.ty), signed_integer(instruction.ty))
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if register_binary(instruction.opcode) {
                if instruction.operand_count != 2usize { ret Unsupported }
                let left_value = builder.operands[instruction.first_operand]
                let right_value = builder.operands[instruction.first_operand + 1usize]
                let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
                if destination_error != ok { ret destination_error }
                let (left, left_error) = read_value(allocations, left_value, 10usize, output)
                if left_error != ok { ret left_error }
                let (right, right_error) = read_value(allocations, right_value, 11usize, output)
                if right_error != ok { ret right_error }
                if comparison(instruction.opcode) {
                    let (operand_type, operand_type_error) = value_type(builder, current, left_value)
                    if operand_type_error != ok { ret operand_type_error }
                    let unsigned = operand_type.kind == .Integer && operand_type.name.len > 0usize && operand_type.name[0usize] == 117u8
                    let (condition, condition_error) = comparison_condition(instruction.opcode, unsigned)
                    if condition_error != ok { ret condition_error }
                    try emit_x64.compare_register(output, left, right)
                    var fuse = false
                    if at + 1usize < end && instruction.result < context.ranges.len && context.ranges[instruction.result].first == at && context.ranges[instruction.result].last == at + 1usize {
                        let next = builder.instructions[at + 1usize]
                        if next.opcode == .BranchIf && next.operand_count == 1usize && builder.operands[next.first_operand] == instruction.result { fuse = true }
                    }
                    if fuse {
                        context.fused = true
                        context.fused_value = instruction.result
                        context.fused_condition = condition
                    } else {
                        try emit_x64.mov_immediate(output, destination, 0usize)
                        try emit_x64.set_condition(output, destination, condition)
                    }
                } else {
                    if destination != left { try emit_x64.mov_register(output, destination, left) }
                    if instruction.opcode == .Add || instruction.opcode == .AddWrap { try emit_x64.add_register(output, destination, right) }
                    if instruction.opcode == .Subtract || instruction.opcode == .SubtractWrap { try emit_x64.subtract_register(output, destination, right) }
                    if instruction.opcode == .Multiply || instruction.opcode == .MultiplyWrap { try emit_x64.multiply_register(output, destination, right) }
                    if instruction.opcode == .BitAnd { try emit_x64.bit_and_register(output, destination, right) }
                    if instruction.opcode == .BitXor { try emit_x64.bit_xor_register(output, destination, right) }
                    if instruction.opcode == .BitOr { try emit_x64.bit_or_register(output, destination, right) }
                    let checked = instruction.ty.kind == .Integer && !instruction.nocheck && (instruction.opcode == .Add || instruction.opcode == .Subtract || instruction.opcode == .Multiply)
                    if checked {
                        var operator = " + overflows"
                        if instruction.opcode == .Subtract { operator = " - overflows" }
                        if instruction.opcode == .Multiply { operator = " * overflows" }
                        try emit_overflow_check(builder, current, nir.site_token(instruction.site), instruction.path, instruction.ty, operator, destination, context)
                    }
                    if instruction.ty.kind == .Integer && !(checked && integer_width(instruction.ty) != 64usize) { try emit_x64.normalize_integer(output, destination, destination, integer_width(instruction.ty), signed_integer(instruction.ty)) }
                }
                if !(context.fused && context.fused_value == instruction.result) { try store_result(allocations, instruction.result, destination, output) }
            } else {
                if instruction.opcode == .Call || instruction.opcode == .IndirectCall {
                    let indirect = instruction.opcode == .IndirectCall
                    if !indirect && instruction.immediate >= builder.function_ref_count { ret Unsupported }
                    if indirect && instruction.operand_count == 0usize { ret Unsupported }
                    var first_argument = 0usize
                    if indirect { first_argument = 1usize }
                    let argument_total = instruction.operand_count - first_argument
                    let live_mask = live_register_mask(context, current.value_count, at, preserve_count)
                    try save_live_registers(output, live_mask, preserve_base, preserve_count)
                    if indirect {
                        let callee_value = builder.operands[instruction.first_operand]
                        let (callee_source, callee_error) = read_value(allocations, callee_value, 10usize, output)
                        if callee_error != ok { ret callee_error }
                        try emit_x64.store_stack(output, outgoing_base + argument_total, callee_source)
                    }
                    var argument_at = 0usize
                    while argument_at < argument_total {
                        let value = builder.operands[instruction.first_operand + first_argument + argument_at]
                        let (source, source_error) = read_value(allocations, value, 10usize, output)
                        if source_error != ok { ret source_error }
                        try emit_x64.store_stack(output, outgoing_base + argument_at, source)
                        argument_at += 1usize
                    }
                    let foreign = !indirect && builder.function_refs[instruction.immediate].library.len != 0usize
                    try load_call_arguments(builder, current, instruction, abi, foreign, first_argument, argument_total, outgoing_base, output)
                    if indirect {
                        try emit_x64.load_stack(output, 11usize, outgoing_base + argument_total)
                        try emit_x64.call_register(output, 11usize)
                    } else {
                        // An imported callee is reached through the slot the loader
                        // wrote, not by a displacement to code that is in this image.
                        // The linker tells the two apart by the reference itself.
                        if builder.function_refs[instruction.immediate].library.len != 0usize {
                            let (import_displacement, import_error) = emit_x64.call_indirect_relative(output)
                            if import_error != ok { ret import_error }
                            try add_relocation(relocations, relocation_count, import_displacement, instruction.immediate)
                        } else {
                            let (call_displacement, call_error) = emit_x64.call(output)
                            if call_error != ok { ret call_error }
                            try add_relocation(relocations, relocation_count, call_displacement, instruction.immediate)
                        }
                    }
                    let multiple_results = instruction.has_result && (instruction.ty.kind == .Invalid || (instruction.ty.kind == .Other && check.same(instruction.ty.name, "return-values")))
                    if instruction.has_result {
                        let result_float = float_width(instruction.ty)
                        if result_float != 0usize {
                            try emit_x64.move_from_float(output, 10usize, 0usize, result_float == 64usize)
                        } else {
                            if instruction.ty.kind == .Float { ret Unsupported }
                            try emit_x64.mov_register(output, 10usize, 0usize)
                            // A callee returning a type narrower than a register leaves
                            // only that many bits defined -- both System V and Win64 say
                            // the rest is undefined -- so a narrow result is widened here
                            // rather than trusted. An `extern fn` returning `i32` was the
                            // case that showed it: a -1 read as 0xFFFFFFFF is not less
                            // than zero, so every error check on a foreign call that
                            // reports failure by a negative number silently passed.
                            // neper's own calls already leave the value widened, which
                            // makes this a no-op for them rather than a case to detect.
                            if instruction.ty.kind == .Integer && integer_width(instruction.ty) != 64usize {
                                try emit_x64.normalize_integer(output, 10usize, 10usize, integer_width(instruction.ty), signed_integer(instruction.ty))
                            }
                        }
                        if multiple_results { try emit_x64.mov_register(output, 11usize, 2usize) }
                    }
                    try restore_live_registers(output, live_mask, preserve_base, preserve_count)
                    if instruction.has_result && !multiple_results {
                        let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                        if destination_error != ok { ret destination_error }
                        if destination != 10usize { try emit_x64.mov_register(output, destination, 10usize) }
                        try store_result(allocations, instruction.result, destination, output)
                    }
                } else {
                if instruction.opcode == .FunctionAddress {
                    if !instruction.has_result || instruction.immediate >= builder.function_ref_count { ret Unsupported }
                    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
                    if destination_error != ok { ret destination_error }
                    let (address_displacement, address_error) = emit_x64.relative_address(output, destination)
                    if address_error != ok { ret address_error }
                    try add_relocation(relocations, relocation_count, address_displacement, instruction.immediate)
                    try store_result(allocations, instruction.result, destination, output)
                } else {
                if instruction.opcode == .Extract {
                    if !instruction.has_result || instruction.operand_count != 1usize || instruction.immediate >= 2usize { ret Unsupported }
                    var source = 10usize
                    if instruction.immediate == 1usize { source = 11usize }
                    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
                    if destination_error != ok { ret destination_error }
                    if destination != source { try emit_x64.mov_register(output, destination, source) }
                    try store_result(allocations, instruction.result, destination, output)
                } else {
                if instruction.opcode == .Branch {
                    if instruction.target < current.first_block || instruction.target >= current.first_block + current.block_count { ret Unsupported }
                    // A jump to the block that follows is no jump (D237).
                    if builder.blocks[instruction.target].first_instruction != at + 1usize {
                        let (displacement, jump_error) = emit_x64.jump(output)
                        if jump_error != ok { ret jump_error }
                        try add_fixup(fixups, &fixup_count, displacement, instruction.target - current.first_block)
                    }
                } else {
                    if instruction.opcode == .BranchIf {
                        if instruction.operand_count != 1usize || instruction.target < current.first_block || instruction.target >= current.first_block + current.block_count || instruction.target2 < current.first_block || instruction.target2 >= current.first_block + current.block_count { ret Unsupported }
                        let condition_value = builder.operands[instruction.first_operand]
                        if context.fused && context.fused_value == condition_value {
                            context.fused = false
                            let (true_displacement, true_error) = emit_x64.jump_condition(output, context.fused_condition)
                            if true_error != ok { ret true_error }
                            try add_fixup(fixups, &fixup_count, true_displacement, instruction.target - current.first_block)
                        } else {
                            let (condition, condition_error) = read_value(allocations, condition_value, 10usize, output)
                            if condition_error != ok { ret condition_error }
                            let (true_displacement, true_error) = emit_x64.jump_nonzero(output, condition)
                            if true_error != ok { ret true_error }
                            try add_fixup(fixups, &fixup_count, true_displacement, instruction.target - current.first_block)
                        }
                        if builder.blocks[instruction.target2].first_instruction != at + 1usize {
                            let (false_displacement, false_error) = emit_x64.jump(output)
                            if false_error != ok { ret false_error }
                            try add_fixup(fixups, &fixup_count, false_displacement, instruction.target2 - current.first_block)
                        }
                    } else {
                if instruction.opcode == .Trap || instruction.opcode == .Unreachable {
                    if instruction.has_result || instruction.operand_count > 2usize { ret Unsupported }
                    // `.Trap` is `unreachable()`, its immediate the message's string
                    // constant plus one, or a check lowering emitted: then its type
                    // names the kind and its operands are the values, printed after
                    // the message. `.Unreachable` is a point the compiler inferred.
                    var message = "control reached a point the compiler took as unreachable"
                    var kind = "unreachable"
                    var signed = false
                    if instruction.opcode == .Trap {
                        message = "unreachable() reached"
                        if instruction.ty.kind == .Other { kind = instruction.ty.name }
                        if instruction.immediate != 0usize {
                            if instruction.immediate > builder.string_count { ret Unsupported }
                            let spelling = builder.strings[instruction.immediate - 1usize].spelling
                            message = spelling
                            if spelling.len != 0usize && (spelling[0usize] == 34u8 || spelling[0usize] == 114u8) {
                                var text_start = 0usize
                                var text_end = 0usize
                                var raw = false
                                try string_contents(spelling, &text_start, &text_end, &raw)
                                message = spelling[text_start..text_end]
                            }
                        }
                    }
                    var operand_at = 0usize
                    while operand_at < instruction.operand_count {
                        let operand_value = builder.operands[instruction.first_operand + operand_at]
                        let (operand_type, operand_type_error) = value_type(builder, current, operand_value)
                        if operand_type_error != ok { ret operand_type_error }
                        if operand_at == 0usize { signed = signed_integer(operand_type) }
                        let (operand_source, operand_error) = read_value(allocations, operand_value, 10usize + operand_at, output)
                        if operand_error != ok { ret operand_error }
                        if operand_source != 10usize + operand_at { try emit_x64.mov_register(output, 10usize + operand_at, operand_source) }
                        operand_at += 1usize
                    }
                    try emit_trap(builder, current, nir.site_token(instruction.site), instruction.path, kind, message, "", "", instruction.operand_count, signed, 10usize, 11usize, "", context)
                } else {
                if instruction.opcode == .Return {
                    if instruction.operand_count == 1usize {
                        let value = builder.operands[instruction.first_operand]
                        let (source, source_error) = read_value(allocations, value, 10usize, output)
                        if source_error != ok { ret source_error }
                        let (returned_type, returned_error) = value_type(builder, current, value)
                        if returned_error != ok { ret returned_error }
                        if returned_type.kind == .Float {
                            let returned_width = float_width(returned_type)
                            if returned_width == 0usize { ret Unsupported }
                            try emit_x64.move_to_float(output, 0usize, source, returned_width == 64usize)
                        } else {
                            if source != 0usize { try emit_x64.mov_register(output, 0usize, source) }
                        }
                    } else {
                        if instruction.operand_count == 2usize {
                            let first_value = builder.operands[instruction.first_operand]
                            let second_value = builder.operands[instruction.first_operand + 1usize]
                            let (first_source, first_error) = read_value(allocations, first_value, 10usize, output)
                            if first_error != ok { ret first_error }
                            if first_source != 10usize { try emit_x64.mov_register(output, 10usize, first_source) }
                            let (second_source, second_error) = read_value(allocations, second_value, 11usize, output)
                            if second_error != ok { ret second_error }
                            if second_source != 11usize { try emit_x64.mov_register(output, 11usize, second_source) }
                            try emit_x64.mov_register(output, 0usize, 10usize)
                            try emit_x64.mov_register(output, 2usize, 11usize)
                        } else {
                            if instruction.operand_count != 0usize { ret Unsupported }
                            // The entry's void return is the exit status the startup reads
                            // from eax (D230): zero, not whatever the body left there.
                            if current.module_index == 0usize && check.same(current.name, "main") { try emit_x64.mov_immediate(output, 0usize, 0usize) }
                        }
                    }
                    try restore_callee_registers(output, saved_base, saved_count)
                    try emit_x64.function_epilogue(output)
                } else {
                    ret Unsupported
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
        at += 1usize
    }
    var fixup_at = 0usize
    while fixup_at < fixup_count {
        let fixup = fixups[fixup_at]
        if fixup.block >= current.block_count { ret Unsupported }
        try emit_x64.patch_relative32(output, fixup.displacement_at, block_offsets[fixup.block])
        fixup_at += 1usize
    }
    ret ok
}

fn self_test() -> err {
    var functions: [2]nir.Function = zero
    var blocks: [4]nir.Block = zero
    var instructions: [12]nir.Instruction = zero
    var operands: [12]usize = zero
    var references: [1]nir.FunctionRef = zero
    var strings: [1]nir.StringConstant = zero
    var builder: nir.Builder = zero
    try nir.init(&builder, functions[..], blocks[..], instructions[..], operands[..], references[..], strings[..])
    let (function_index, function_error) = nir.begin_function(&builder, 0usize, "constant", 0usize)
    if function_error != ok { ret function_error }
    let (block_index, block_error) = nir.begin_block(&builder)
    if block_error != ok { ret block_error }
    let (constant_instruction, value, constant_error) = nir.emit(&builder, .ConstInteger, zero, true, 7usize, zero)
    if constant_error != ok { ret constant_error }
    let (return_index, ignored, return_error) = nir.emit(&builder, .Return, zero, false, 0usize, zero)
    if return_error != ok { ret return_error }
    try nir.add_operand(&builder, return_index, value)
    try nir.end_function(&builder)
    var ranges: [1]regalloc.LiveRange = zero
    var allocations: [1]regalloc.Allocation = zero
    var scratch: [4096]u8 = zero
    var scratch_arena = mem.arena_from(scratch[..])
    let (stack_slots, allocation_error) = regalloc.allocate(&builder, 0usize, 1usize, ranges[..], allocations[..], &scratch_arena)
    if allocation_error != ok || stack_slots != 0usize { ret Unsupported }
    var storage: [128]u8 = zero
    var output: emit_x64.Buffer = zero
    try emit_x64.init(&output, storage[..])
    var block_offsets: [4]usize = zero
    var fixups: [4]Fixup = zero
    var relocations: [4]Relocation = zero
    var relocation_count = 0usize
    var lines: [8]LineEntry = zero
    var line_count = 0usize
    let no_masks = block_offsets[0usize..0usize]
    var context = FunctionContext { allocations: allocations[..], arena: &scratch_arena, has_arena: true, live_masks: no_masks, live_base: 0usize, ranges: ranges[..], abi: .SystemV, block_offsets: block_offsets[..], fixups: fixups[..], relocations: relocations[..], relocation_count: &relocation_count, output: &output, failure_token: zero, failure_instruction: 0usize, lines: lines[..], line_count: &line_count, fused: false, fused_value: 0usize, fused_condition: 0usize }
    try function(&builder, 0usize, stack_slots, &context)
    if output.count != 14usize || output.bytes[0usize] != 85u8 || output.bytes[4usize] != 184u8 || output.bytes[5usize] != 7u8 || output.bytes[12usize] != 93u8 || output.bytes[13usize] != 195u8 { ret Unsupported }
    allocations[0usize].kind = .Stack
    allocations[0usize].index = 0usize
    var spill_storage: [64]u8 = zero
    var spill_output: emit_x64.Buffer = zero
    try emit_x64.init(&spill_output, spill_storage[..])
    context.output = &spill_output
    try function(&builder, 0usize, 1usize, &context)
    if spill_output.count != 39usize { ret InvalidLoadWidth }
    if spill_output.bytes[0usize] != 85u8 { ret InvalidFieldAddress }
    if spill_output.bytes[11usize] != 65u8 { ret InvalidMemoryAddress }
    if spill_output.bytes[38usize] != 195u8 { ret InvalidStoreWidth }

    let (branch_function, branch_function_error) = nir.begin_function(&builder, 0usize, "branch", 0usize)
    if branch_function_error != ok || branch_function != 1usize { ret Unsupported }
    let (entry_block, entry_block_error) = nir.begin_block(&builder)
    if entry_block_error != ok { ret entry_block_error }
    let (left_instruction, left_value, left_constant_error) = nir.emit(&builder, .ConstInteger, zero, true, 1usize, zero)
    if left_constant_error != ok { ret left_constant_error }
    let (right_instruction, right_value, right_constant_error) = nir.emit(&builder, .ConstInteger, zero, true, 2usize, zero)
    if right_constant_error != ok { ret right_constant_error }
    let (comparison_instruction, condition, comparison_error) = nir.emit(&builder, .Less, zero, true, 0usize, zero)
    if comparison_error != ok { ret comparison_error }
    try nir.add_operand(&builder, comparison_instruction, left_value)
    try nir.add_operand(&builder, comparison_instruction, right_value)
    let (decision, decision_value, decision_error) = nir.emit(&builder, .BranchIf, zero, false, 0usize, zero)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(&builder, decision, condition)
    let true_block = builder.block_count
    let (true_index, true_error) = nir.begin_block(&builder)
    if true_error != ok { ret true_error }
    let (true_constant_instruction, true_value, true_constant_error) = nir.emit(&builder, .ConstInteger, zero, true, 7usize, zero)
    if true_constant_error != ok { ret true_constant_error }
    let (true_return, true_return_value, true_return_error) = nir.emit(&builder, .Return, zero, false, 0usize, zero)
    if true_return_error != ok { ret true_return_error }
    try nir.add_operand(&builder, true_return, true_value)
    let false_block = builder.block_count
    let (false_index, false_error) = nir.begin_block(&builder)
    if false_error != ok { ret false_error }
    let (false_constant_instruction, false_value, false_constant_error) = nir.emit(&builder, .ConstInteger, zero, true, 9usize, zero)
    if false_constant_error != ok { ret false_constant_error }
    let (false_return, false_return_value, false_return_error) = nir.emit(&builder, .Return, zero, false, 0usize, zero)
    if false_return_error != ok { ret false_return_error }
    try nir.add_operand(&builder, false_return, false_value)
    try nir.set_branch_targets(&builder, decision, true_block, false_block)
    try nir.end_function(&builder)
    var branch_ranges: [5]regalloc.LiveRange = zero
    var branch_allocations: [5]regalloc.Allocation = zero
    let (branch_stack_slots, branch_allocation_error) = regalloc.allocate(&builder, 1usize, 3usize, branch_ranges[..], branch_allocations[..], &scratch_arena)
    if branch_allocation_error != ok || branch_stack_slots != 0usize { ret Unsupported }
    var branch_storage: [96]u8 = zero
    var branch_output: emit_x64.Buffer = zero
    try emit_x64.init(&branch_output, branch_storage[..])
    context.allocations = branch_allocations[..]
    context.ranges = branch_ranges[..]
    context.output = &branch_output
    try function(&builder, 1usize, 0usize, &context)
    if branch_output.count == 0usize || branch_output.bytes[branch_output.count - 1usize] != 195u8 { ret Unsupported }
    var saw_compare = false
    var saw_conditional = false
    var scan_at = 0usize
    while scan_at + 1usize < branch_output.count {
        if branch_output.bytes[scan_at] == 57u8 { saw_compare = true }
        if branch_output.bytes[scan_at] == 15u8 && branch_output.bytes[scan_at + 1usize] == 140u8 { saw_conditional = true }
        scan_at += 1usize
    }
    if !saw_compare || !saw_conditional { ret Unsupported }
    let (reference_index, reference_error) = nir.intern_function(&builder, 0usize, "constant", 0usize)
    if reference_error != ok { ret reference_error }
    var call_storage: [32]u8 = zero
    var call_output: emit_x64.Buffer = zero
    try emit_x64.init(&call_output, call_storage[..])
    let (call_displacement, call_error) = emit_x64.call(&call_output)
    if call_error != ok { ret call_error }
    while call_output.count < 20usize { try emit_x64.byte(&call_output, 144usize) }
    relocations[0usize] = Relocation { displacement_at: call_displacement, function_ref: reference_index, global: false, resolved: false }
    var function_offsets: [2]usize = zero
    function_offsets[0usize] = 20usize
    try resolve_calls(&builder, function_offsets[..], relocations[..], 1usize, &call_output)
    if !relocations[0usize].resolved || call_output.bytes[1usize] != 15u8 { ret Unsupported }
    ret ok
}
