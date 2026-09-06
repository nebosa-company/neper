// x64 instruction selection from allocated scalar NIR.

use check
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

type Relocation = struct {
    displacement_at: usize,
    function_ref: usize,
    resolved: bool,
}

type FunctionContext = struct {
    allocations: []regalloc.Allocation,
    abi: Abi,
    block_offsets: []usize,
    fixups: []Fixup,
    relocations: []Relocation,
    relocation_count: *usize,
    output: *emit_x64.Buffer,
    failure_token: lex.Token,
    failure_instruction: usize,
}

fn add_fixup(fixups: []Fixup, count: *usize, displacement_at: usize, block: usize) -> err {
    if *count == fixups.len { ret Unsupported }
    fixups[*count] = Fixup { displacement_at: displacement_at, block: block }
    *count += 1usize
    ret ok
}

fn add_relocation(relocations: []Relocation, count: *usize, displacement_at: usize, function_ref: usize) -> err {
    if *count == relocations.len { ret Unsupported }
    relocations[*count] = Relocation { displacement_at: displacement_at, function_ref: function_ref, resolved: false }
    *count += 1usize
    ret ok
}

fn resolve_calls(builder: *nir.Builder, function_offsets: []usize, relocations: []Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len { ret Unsupported }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let reference_index = relocations[relocation_at].function_ref
        if reference_index >= builder.function_ref_count { ret Unsupported }
        let reference = builder.function_refs[reference_index]
        var function_at = 0usize
        var found = false
        while function_at < builder.function_count {
            let candidate = builder.functions[function_at]
            if candidate.module_index == reference.module_index && candidate.instance == reference.instance && check.same(candidate.name, reference.name) {
                try emit_x64.patch_relative32(output, relocations[relocation_at].displacement_at, function_offsets[function_at])
                relocations[relocation_at].resolved = true
                found = true
                break
            }
            function_at += 1usize
        }
        relocation_at += 1usize
    }
    ret ok
}

fn hardware_register(index: usize) -> (usize, err) {
    if index == 0usize { ret (0usize, ok) }
    if index == 1usize { ret (1usize, ok) }
    if index == 2usize { ret (2usize, ok) }
    if index == 3usize { ret (8usize, ok) }
    if index == 4usize { ret (9usize, ok) }
    ret (0usize, Unsupported)
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

fn storage_width(instruction: nir.Instruction) -> usize {
    if instruction.immediate == 1usize || instruction.immediate == 2usize || instruction.immediate == 4usize || instruction.immediate == 8usize { ret instruction.immediate * 8usize }
    if instruction.ty.kind == .Bool { ret 8usize }
    if instruction.ty.kind == .Err { ret 32usize }
    if instruction.ty.kind == .Pointer || instruction.ty.kind == .String || instruction.ty.kind == .Slice { ret 64usize }
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

fn incoming_stack_displacement(abi: Abi, index: usize) -> usize {
    if abi == .Windows { ret 48usize + (index - 4usize) * 8usize }
    ret 16usize + (index - 6usize) * 8usize
}

fn outgoing_stack_displacement(abi: Abi, index: usize) -> usize {
    if abi == .Windows { ret 32usize + (index - 4usize) * 8usize }
    let stack_index = index - 6usize
    ret stack_index * 8usize
}

fn max_call_arguments(builder: *nir.Builder, current: nir.Function) -> usize {
    var maximum = 0usize
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .Call && instruction.operand_count > maximum { maximum = instruction.operand_count }
        at += 1usize
    }
    ret maximum
}

fn needs_fixed_registers(builder: *nir.Builder, current: nir.Function) -> bool {
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let opcode = builder.instructions[at].opcode
        if opcode == .Divide || opcode == .Remainder || opcode == .ShiftLeft || opcode == .ShiftRight || opcode == .IndexAddress || opcode == .Slice || opcode == .Copy || opcode == .Call { ret true }
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

fn select_index_address(builder: *nir.Builder, instruction: nir.Instruction, allocations: []regalloc.Allocation, preserve_base: usize, preserve_count: usize, output: *emit_x64.Buffer) -> err {
    if !instruction.has_result || instruction.operand_count != 3usize || instruction.immediate == 0usize { ret Unsupported }
    try save_allocated_registers(output, preserve_base, preserve_count)
    let base_value = builder.operands[instruction.first_operand]
    let index_value = builder.operands[instruction.first_operand + 1usize]
    let length_value = builder.operands[instruction.first_operand + 2usize]
    let (base, base_error) = read_value(allocations, base_value, 10usize, output)
    if base_error != ok { ret base_error }
    if base != 10usize { try emit_x64.mov_register(output, 10usize, base) }
    let (index, index_error) = read_value(allocations, index_value, 11usize, output)
    if index_error != ok { ret index_error }
    if index != 11usize { try emit_x64.mov_register(output, 11usize, index) }
    let (length, length_error) = read_value(allocations, length_value, 0usize, output)
    if length_error != ok { ret length_error }
    if length != 0usize { try emit_x64.mov_register(output, 0usize, length) }
    try emit_x64.bounds_check(output, 11usize, 0usize)
    if instruction.immediate != 1usize { try emit_x64.multiply_immediate(output, 11usize, 11usize, instruction.immediate) }
    try emit_x64.add_register(output, 11usize, 10usize)
    try restore_allocated_registers(output, preserve_base, preserve_count)
    let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
    if destination_error != ok { ret destination_error }
    if destination != 11usize { try emit_x64.mov_register(output, destination, 11usize) }
    ret store_result(allocations, instruction.result, destination, output)
}

fn select_slice(builder: *nir.Builder, instruction: nir.Instruction, allocations: []regalloc.Allocation, preserve_base: usize, preserve_count: usize, output: *emit_x64.Buffer) -> err {
    if instruction.has_result || instruction.operand_count != 5usize || instruction.immediate == 0usize { ret Unsupported }
    try save_allocated_registers(output, preserve_base, preserve_count)
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
    try emit_x64.slice_bounds_check(output, 0usize, 1usize, 11usize)
    try emit_x64.subtract_register(output, 1usize, 0usize)
    if instruction.immediate != 1usize { try emit_x64.multiply_immediate(output, 0usize, 0usize, instruction.immediate) }
    try emit_x64.add_register(output, 10usize, 0usize)
    try emit_x64.store_memory(output, 9usize, 10usize, 64usize)
    try emit_x64.add_immediate(output, 9usize, 8usize)
    try emit_x64.store_memory(output, 9usize, 1usize, 64usize)
    ret restore_allocated_registers(output, preserve_base, preserve_count)
}

fn function(builder: *nir.Builder, function_index: usize, stack_slots: usize, context: *FunctionContext) -> err {
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
    let frame_slots = preserve_base + preserve_count + call_area_count
    if frame_slots != 0usize { try emit_x64.function_prologue(output, frame_slots) }
    var parameter_at = 0usize
    while parameter_at < parameters {
        if parameter_at < parameter_register_count(abi) {
            let (incoming, incoming_error) = parameter_register(abi, parameter_at)
            if incoming_error != ok { ret incoming_error }
            try emit_x64.store_stack(output, stack_slots + parameter_at, incoming)
        } else {
            try emit_x64.load_frame_argument(output, 10usize, incoming_stack_displacement(abi, parameter_at))
            try emit_x64.store_stack(output, stack_slots + parameter_at, 10usize)
        }
        parameter_at += 1usize
    }
    let end = current.first_instruction + current.instruction_count
    var fixup_count = 0usize
    var at = current.first_instruction
    while at < end {
        var block_at = 0usize
        while block_at < current.block_count {
            let block = builder.blocks[current.first_block + block_at]
            if block.first_instruction == at { block_offsets[block_at] = output.count }
            block_at += 1usize
        }
        let instruction = builder.instructions[at]
        context.failure_token = instruction.token
        context.failure_instruction = at
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
                try save_allocated_registers(output, preserve_base, preserve_count)
                let destination_value = builder.operands[instruction.first_operand]
                let source_value = builder.operands[instruction.first_operand + 1usize]
                let (destination_source, destination_error) = read_value(allocations, destination_value, 10usize, output)
                if destination_error != ok { ret destination_error }
                if destination_source != 10usize { try emit_x64.mov_register(output, 10usize, destination_source) }
                let (source, source_error) = read_value(allocations, source_value, 11usize, output)
                if source_error != ok { ret source_error }
                if source != 11usize { try emit_x64.mov_register(output, 11usize, source) }
                try emit_x64.copy_memory(output, 10usize, 11usize, instruction.immediate)
                try restore_allocated_registers(output, preserve_base, preserve_count)
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
            if instruction.opcode == .Zero {
                try select_zero(builder, instruction, allocations, output)
            } else {
            if instruction.opcode == .IndexAddress {
                try select_index_address(builder, instruction, allocations, preserve_base, preserve_count, output)
            } else {
            if instruction.opcode == .Slice {
                try select_slice(builder, instruction, allocations, preserve_base, preserve_count, output)
            } else {
            if instruction.opcode == .Cast || instruction.opcode == .Negate || instruction.opcode == .BitNot {
                if instruction.operand_count != 1usize || instruction.ty.kind != .Integer { ret Unsupported }
                let operand_value = builder.operands[instruction.first_operand]
                let (source_type, source_type_error) = value_type(builder, current, operand_value)
                if source_type_error != ok || source_type.kind != .Integer { ret Unsupported }
                let (source, source_error) = read_value(allocations, operand_value, 10usize, output)
                if source_error != ok { ret source_error }
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                if instruction.opcode == .Cast {
                    var normalize_type = instruction.ty
                    if integer_width(normalize_type) == 64usize { normalize_type = source_type }
                    try emit_x64.normalize_integer(output, destination, source, integer_width(normalize_type), signed_integer(normalize_type))
                } else {
                    if destination != source { try emit_x64.mov_register(output, destination, source) }
                    if instruction.opcode == .Negate { try emit_x64.negate_register(output, destination) }
                    if instruction.opcode == .BitNot { try emit_x64.bit_not_register(output, destination) }
                    try emit_x64.normalize_integer(output, destination, destination, integer_width(instruction.ty), signed_integer(instruction.ty))
                }
                try store_result(allocations, instruction.result, destination, output)
            } else {
        if instruction.opcode == .ConstInteger || instruction.opcode == .ConstBool || instruction.opcode == .ConstError {
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
                try save_allocated_registers(output, preserve_base, preserve_count)
                let (left, left_error) = read_value(allocations, left_value, 10usize, output)
                if left_error != ok { ret left_error }
                let (right, right_error) = read_value(allocations, right_value, 11usize, output)
                if right_error != ok { ret right_error }
                if left != 10usize { try emit_x64.mov_register(output, 10usize, left) }
                if right != 1usize { try emit_x64.mov_register(output, 1usize, right) }
                try emit_x64.and_immediate8(output, 1usize, integer_width(left_type) - 1usize)
                try emit_x64.shift_register(output, 10usize, instruction.opcode == .ShiftLeft, signed_integer(left_type))
                try restore_allocated_registers(output, preserve_base, preserve_count)
                let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                if destination_error != ok { ret destination_error }
                try emit_x64.normalize_integer(output, destination, 10usize, integer_width(instruction.ty), signed_integer(instruction.ty))
                try store_result(allocations, instruction.result, destination, output)
            } else {
            if instruction.opcode == .Divide || instruction.opcode == .Remainder {
                if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret Unsupported }
                let left_value = builder.operands[instruction.first_operand]
                let right_value = builder.operands[instruction.first_operand + 1usize]
                let (left_type, left_type_error) = value_type(builder, current, left_value)
                if left_type_error != ok || left_type.kind != .Integer { ret Unsupported }
                try save_allocated_registers(output, preserve_base, preserve_count)
                let (left, left_error) = read_value(allocations, left_value, 10usize, output)
                if left_error != ok { ret left_error }
                let (right, right_error) = read_value(allocations, right_value, 11usize, output)
                if right_error != ok { ret right_error }
                if right != 11usize { try emit_x64.mov_register(output, 11usize, right) }
                if left != 0usize { try emit_x64.mov_register(output, 0usize, left) }
                let signed = signed_integer(left_type)
                if signed { try emit_x64.extend_dividend_signed(output) } else { try emit_x64.extend_dividend_unsigned(output) }
                try emit_x64.divide_register(output, 11usize, signed)
                if instruction.opcode == .Divide {
                    try emit_x64.mov_register(output, 10usize, 0usize)
                } else {
                    try emit_x64.mov_register(output, 10usize, 2usize)
                }
                try restore_allocated_registers(output, preserve_base, preserve_count)
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
                    try emit_x64.mov_immediate(output, destination, 0usize)
                    try emit_x64.set_condition(output, destination, condition)
                } else {
                    if destination != left { try emit_x64.mov_register(output, destination, left) }
                    if instruction.opcode == .Add || instruction.opcode == .AddWrap { try emit_x64.add_register(output, destination, right) }
                    if instruction.opcode == .Subtract || instruction.opcode == .SubtractWrap { try emit_x64.subtract_register(output, destination, right) }
                    if instruction.opcode == .Multiply || instruction.opcode == .MultiplyWrap { try emit_x64.multiply_register(output, destination, right) }
                    if instruction.opcode == .BitAnd { try emit_x64.bit_and_register(output, destination, right) }
                    if instruction.opcode == .BitXor { try emit_x64.bit_xor_register(output, destination, right) }
                    if instruction.opcode == .BitOr { try emit_x64.bit_or_register(output, destination, right) }
                    if instruction.ty.kind == .Integer { try emit_x64.normalize_integer(output, destination, destination, integer_width(instruction.ty), signed_integer(instruction.ty)) }
                }
                try store_result(allocations, instruction.result, destination, output)
            } else {
                if instruction.opcode == .Call {
                    if instruction.immediate >= builder.function_ref_count { ret Unsupported }
                    try save_allocated_registers(output, preserve_base, preserve_count)
                    var argument_at = 0usize
                    while argument_at < instruction.operand_count {
                        let value = builder.operands[instruction.first_operand + argument_at]
                        let (source, source_error) = read_value(allocations, value, 10usize, output)
                        if source_error != ok { ret source_error }
                        try emit_x64.store_stack(output, outgoing_base + argument_at, source)
                        argument_at += 1usize
                    }
                    argument_at = 0usize
                    while argument_at < instruction.operand_count {
                        if argument_at < parameter_register_count(abi) {
                            let (destination, destination_error) = parameter_register(abi, argument_at)
                            if destination_error != ok { ret destination_error }
                            try emit_x64.load_stack(output, destination, outgoing_base + argument_at)
                        } else {
                            try emit_x64.load_stack(output, 10usize, outgoing_base + argument_at)
                            try emit_x64.store_call_argument(output, outgoing_stack_displacement(abi, argument_at), 10usize)
                        }
                        argument_at += 1usize
                    }
                    let (call_displacement, call_error) = emit_x64.call(output)
                    if call_error != ok { ret call_error }
                    try add_relocation(relocations, relocation_count, call_displacement, instruction.immediate)
                    let multiple_results = instruction.has_result && (instruction.ty.kind == .Invalid || (instruction.ty.kind == .Other && check.same(instruction.ty.name, "return-values")))
                    if instruction.has_result {
                        try emit_x64.mov_register(output, 10usize, 0usize)
                        if multiple_results { try emit_x64.mov_register(output, 11usize, 2usize) }
                    }
                    try restore_allocated_registers(output, preserve_base, preserve_count)
                    if instruction.has_result && !multiple_results {
                        let (destination, destination_error) = result_register(allocations, instruction.result, 11usize)
                        if destination_error != ok { ret destination_error }
                        if destination != 10usize { try emit_x64.mov_register(output, destination, 10usize) }
                        try store_result(allocations, instruction.result, destination, output)
                    }
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
                    let (displacement, jump_error) = emit_x64.jump(output)
                    if jump_error != ok { ret jump_error }
                    try add_fixup(fixups, &fixup_count, displacement, instruction.target - current.first_block)
                } else {
                    if instruction.opcode == .BranchIf {
                        if instruction.operand_count != 1usize || instruction.target < current.first_block || instruction.target >= current.first_block + current.block_count || instruction.target2 < current.first_block || instruction.target2 >= current.first_block + current.block_count { ret Unsupported }
                        let condition_value = builder.operands[instruction.first_operand]
                        let (condition, condition_error) = read_value(allocations, condition_value, 10usize, output)
                        if condition_error != ok { ret condition_error }
                        let (true_displacement, true_error) = emit_x64.jump_nonzero(output, condition)
                        if true_error != ok { ret true_error }
                        try add_fixup(fixups, &fixup_count, true_displacement, instruction.target - current.first_block)
                        let (false_displacement, false_error) = emit_x64.jump(output)
                        if false_error != ok { ret false_error }
                        try add_fixup(fixups, &fixup_count, false_displacement, instruction.target2 - current.first_block)
                    } else {
                if instruction.opcode == .Trap || instruction.opcode == .Unreachable {
                    if instruction.has_result || instruction.operand_count != 0usize { ret Unsupported }
                    try emit_x64.byte(output, 15usize)
                    try emit_x64.byte(output, 11usize)
                } else {
                if instruction.opcode == .Return {
                    if instruction.operand_count == 1usize {
                        let value = builder.operands[instruction.first_operand]
                        let (source, source_error) = read_value(allocations, value, 10usize, output)
                        if source_error != ok { ret source_error }
                        if source != 0usize { try emit_x64.mov_register(output, 0usize, source) }
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
                        }
                    }
                    if frame_slots == 0usize {
                        try emit_x64.return_instruction(output)
                    } else {
                        try emit_x64.function_epilogue(output)
                    }
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
    let (stack_slots, allocation_error) = regalloc.allocate(&builder, 0usize, 1usize, ranges[..], allocations[..])
    if allocation_error != ok || stack_slots != 0usize { ret Unsupported }
    var storage: [128]usize = zero
    var output: emit_x64.Buffer = zero
    try emit_x64.init(&output, storage[..])
    var block_offsets: [4]usize = zero
    var fixups: [4]Fixup = zero
    var relocations: [4]Relocation = zero
    var relocation_count = 0usize
    var context = FunctionContext { allocations: allocations[..], abi: .SystemV, block_offsets: block_offsets[..], fixups: fixups[..], relocations: relocations[..], relocation_count: &relocation_count, output: &output, failure_token: zero, failure_instruction: 0usize }
    try function(&builder, 0usize, stack_slots, &context)
    if output.count != 11usize || output.bytes[0usize] != 72usize || output.bytes[1usize] != 184usize || output.bytes[2usize] != 7usize || output.bytes[10usize] != 195usize { ret Unsupported }
    allocations[0usize].kind = .Stack
    allocations[0usize].index = 0usize
    var spill_storage: [64]usize = zero
    var spill_output: emit_x64.Buffer = zero
    try emit_x64.init(&spill_output, spill_storage[..])
    context.output = &spill_output
    try function(&builder, 0usize, 1usize, &context)
    if spill_output.count != 43usize || spill_output.bytes[0usize] != 85usize || spill_output.bytes[11usize] != 73usize || spill_output.bytes[42usize] != 195usize { ret Unsupported }

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
    let (branch_stack_slots, branch_allocation_error) = regalloc.allocate(&builder, 1usize, 3usize, branch_ranges[..], branch_allocations[..])
    if branch_allocation_error != ok || branch_stack_slots != 0usize { ret Unsupported }
    var branch_storage: [96]usize = zero
    var branch_output: emit_x64.Buffer = zero
    try emit_x64.init(&branch_output, branch_storage[..])
    context.allocations = branch_allocations[..]
    context.output = &branch_output
    try function(&builder, 1usize, 0usize, &context)
    if branch_output.count != 73usize || branch_output.bytes[20usize] != 72usize || branch_output.bytes[21usize] != 57usize || branch_output.bytes[22usize] != 200usize || branch_output.bytes[40usize] != 15usize || branch_output.bytes[41usize] != 133usize || branch_output.bytes[42usize] != 5usize || branch_output.bytes[47usize] != 11usize || branch_output.bytes[72usize] != 195usize { ret Unsupported }
    let (reference_index, reference_error) = nir.intern_function(&builder, 0usize, "constant", 0usize)
    if reference_error != ok { ret reference_error }
    var call_storage: [32]usize = zero
    var call_output: emit_x64.Buffer = zero
    try emit_x64.init(&call_output, call_storage[..])
    let (call_displacement, call_error) = emit_x64.call(&call_output)
    if call_error != ok { ret call_error }
    while call_output.count < 20usize { try emit_x64.byte(&call_output, 144usize) }
    relocations[0usize] = Relocation { displacement_at: call_displacement, function_ref: reference_index, resolved: false }
    var function_offsets: [2]usize = zero
    function_offsets[0usize] = 20usize
    try resolve_calls(&builder, function_offsets[..], relocations[..], 1usize, &call_output)
    if !relocations[0usize].resolved || call_output.bytes[1usize] != 15usize { ret Unsupported }
    ret ok
}
