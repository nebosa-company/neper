// x64 instruction selection from allocated scalar NIR.

use check
use emit_x64
use nir
use regalloc

error Unsupported

type Fixup = struct {
    displacement_at: usize,
    block: usize,
}

fn add_fixup(fixups: []Fixup, count: *usize, displacement_at: usize, block: usize) -> err {
    if *count == fixups.len { ret Unsupported }
    fixups[*count] = Fixup { displacement_at: displacement_at, block: block }
    *count += 1usize
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

fn function(builder: *nir.Builder, function_index: usize, allocations: []regalloc.Allocation, stack_slots: usize, block_offsets: []usize, fixups: []Fixup, output: *emit_x64.Buffer) -> err {
    if function_index >= builder.function_count { ret Unsupported }
    let current = builder.functions[function_index]
    if current.block_count > block_offsets.len { ret Unsupported }
    if stack_slots != 0usize { try emit_x64.function_prologue(output, stack_slots) }
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
        if instruction.opcode == .ConstInteger || instruction.opcode == .ConstBool || instruction.opcode == .ConstError {
            let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
            if destination_error != ok { ret destination_error }
            try emit_x64.mov_immediate(output, destination, instruction.immediate)
            try store_result(allocations, instruction.result, destination, output)
        } else {
            if instruction.opcode == .Add || instruction.opcode == .Subtract || instruction.opcode == .Multiply || comparison(instruction.opcode) {
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
                    if instruction.opcode == .Add { try emit_x64.add_register(output, destination, right) }
                    if instruction.opcode == .Subtract { try emit_x64.subtract_register(output, destination, right) }
                    if instruction.opcode == .Multiply { try emit_x64.multiply_register(output, destination, right) }
                }
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
                if instruction.opcode == .Return {
                    if instruction.operand_count == 1usize {
                        let value = builder.operands[instruction.first_operand]
                        let (source, source_error) = read_value(allocations, value, 10usize, output)
                        if source_error != ok { ret source_error }
                        if source != 0usize { try emit_x64.mov_register(output, 0usize, source) }
                    } else {
                        if instruction.operand_count != 0usize { ret Unsupported }
                    }
                    if stack_slots == 0usize {
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
    let (function_index, function_error) = nir.begin_function(&builder, 0usize, "constant")
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
    var storage: [16]usize = zero
    var output: emit_x64.Buffer = zero
    try emit_x64.init(&output, storage[..])
    var block_offsets: [4]usize = zero
    var fixups: [4]Fixup = zero
    try function(&builder, 0usize, allocations[..], stack_slots, block_offsets[..], fixups[..], &output)
    if output.count != 11usize || output.bytes[0usize] != 72usize || output.bytes[1usize] != 184usize || output.bytes[2usize] != 7usize || output.bytes[10usize] != 195usize { ret Unsupported }
    allocations[0usize].kind = .Stack
    allocations[0usize].index = 0usize
    var spill_storage: [64]usize = zero
    var spill_output: emit_x64.Buffer = zero
    try emit_x64.init(&spill_output, spill_storage[..])
    try function(&builder, 0usize, allocations[..], 1usize, block_offsets[..], fixups[..], &spill_output)
    if spill_output.count != 43usize || spill_output.bytes[0usize] != 85usize || spill_output.bytes[11usize] != 73usize || spill_output.bytes[42usize] != 195usize { ret Unsupported }

    let (branch_function, branch_function_error) = nir.begin_function(&builder, 0usize, "branch")
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
    try function(&builder, 1usize, branch_allocations[..], 0usize, block_offsets[..], fixups[..], &branch_output)
    if branch_output.count != 73usize || branch_output.bytes[20usize] != 72usize || branch_output.bytes[21usize] != 57usize || branch_output.bytes[22usize] != 200usize || branch_output.bytes[40usize] != 15usize || branch_output.bytes[41usize] != 133usize || branch_output.bytes[42usize] != 5usize || branch_output.bytes[47usize] != 11usize || branch_output.bytes[72usize] != 195usize { ret Unsupported }
    ret ok
}
