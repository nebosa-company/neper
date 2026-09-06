// x64 instruction selection from allocated scalar NIR.

use emit_x64
use nir
use regalloc

error Unsupported

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

fn function(builder: *nir.Builder, function_index: usize, allocations: []regalloc.Allocation, stack_slots: usize, output: *emit_x64.Buffer) -> err {
    if function_index >= builder.function_count { ret Unsupported }
    if stack_slots != 0usize { try emit_x64.function_prologue(output, stack_slots) }
    let current = builder.functions[function_index]
    let end = current.first_instruction + current.instruction_count
    var at = current.first_instruction
    while at < end {
        let instruction = builder.instructions[at]
        if instruction.opcode == .ConstInteger || instruction.opcode == .ConstBool || instruction.opcode == .ConstError {
            let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
            if destination_error != ok { ret destination_error }
            try emit_x64.mov_immediate(output, destination, instruction.immediate)
            try store_result(allocations, instruction.result, destination, output)
        } else {
            if instruction.opcode == .Add || instruction.opcode == .Subtract || instruction.opcode == .Multiply {
                if instruction.operand_count != 2usize { ret Unsupported }
                let left_value = builder.operands[instruction.first_operand]
                let right_value = builder.operands[instruction.first_operand + 1usize]
                let (destination, destination_error) = result_register(allocations, instruction.result, 10usize)
                if destination_error != ok { ret destination_error }
                let (left, left_error) = read_value(allocations, left_value, 10usize, output)
                if left_error != ok { ret left_error }
                let (right, right_error) = read_value(allocations, right_value, 11usize, output)
                if right_error != ok { ret right_error }
                if destination != left { try emit_x64.mov_register(output, destination, left) }
                if instruction.opcode == .Add { try emit_x64.add_register(output, destination, right) }
                if instruction.opcode == .Subtract { try emit_x64.subtract_register(output, destination, right) }
                if instruction.opcode == .Multiply { try emit_x64.multiply_register(output, destination, right) }
                try store_result(allocations, instruction.result, destination, output)
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
        at += 1usize
    }
    ret ok
}

fn self_test() -> err {
    var functions: [1]nir.Function = zero
    var blocks: [1]nir.Block = zero
    var instructions: [2]nir.Instruction = zero
    var operands: [1]usize = zero
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
    try function(&builder, 0usize, allocations[..], stack_slots, &output)
    if output.count != 11usize || output.bytes[0usize] != 72usize || output.bytes[1usize] != 184usize || output.bytes[2usize] != 7usize || output.bytes[10usize] != 195usize { ret Unsupported }
    allocations[0usize].kind = .Stack
    allocations[0usize].index = 0usize
    var spill_storage: [64]usize = zero
    var spill_output: emit_x64.Buffer = zero
    try emit_x64.init(&spill_output, spill_storage[..])
    try function(&builder, 0usize, allocations[..], 1usize, &spill_output)
    if spill_output.count != 43usize || spill_output.bytes[0usize] != 85usize || spill_output.bytes[11usize] != 73usize || spill_output.bytes[42usize] != 195usize { ret Unsupported }
    ret ok
}
