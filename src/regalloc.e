// Deterministic linear-scan allocation for function-local NIR SSA values.

use nir

error Capacity
error InvalidIR
error NoRegisters

type AllocationKind = enum u8 {
    Invalid,
    Register,
    Stack,
}

type LiveRange = struct {
    first: usize,
    last: usize,
    defined: bool,
}

type Allocation = struct {
    kind: AllocationKind,
    index: usize,
}

fn build_ranges(builder: *nir.Builder, function: nir.Function, ranges: []LiveRange) -> err {
    if function.value_count > ranges.len { ret Capacity }
    var value_at = 0usize
    while value_at < function.value_count {
        ranges[value_at] = zero
        value_at += 1usize
    }
    let instruction_end = function.first_instruction + function.instruction_count
    var instruction_at = function.first_instruction
    while instruction_at < instruction_end {
        if instruction_at >= builder.instruction_count { ret InvalidIR }
        let instruction = builder.instructions[instruction_at]
        if instruction.has_result {
            if instruction.result >= function.value_count || ranges[instruction.result].defined { ret InvalidIR }
            ranges[instruction.result] = LiveRange { first: instruction_at, last: instruction_at, defined: true }
        }
        let operand_end = instruction.first_operand + instruction.operand_count
        var operand_at = instruction.first_operand
        while operand_at < operand_end {
            if operand_at >= builder.operand_count { ret InvalidIR }
            let value = builder.operands[operand_at]
            if value >= function.value_count || !ranges[value].defined { ret InvalidIR }
            ranges[value].last = instruction_at
            operand_at += 1usize
        }
        instruction_at += 1usize
    }
    value_at = 0usize
    while value_at < function.value_count {
        if !ranges[value_at].defined { ret InvalidIR }
        value_at += 1usize
    }
    ret ok
}

fn allocate(builder: *nir.Builder, function_index: usize, register_count: usize, ranges: []LiveRange, allocations: []Allocation) -> (usize, err) {
    if register_count == 0usize { ret (0usize, NoRegisters) }
    if function_index >= builder.function_count { ret (0usize, InvalidIR) }
    let function = builder.functions[function_index]
    if function.value_count > allocations.len { ret (0usize, Capacity) }
    let ranges_error = build_ranges(builder, function, ranges)
    if ranges_error != ok { ret (0usize, ranges_error) }
    var value_at = 0usize
    var stack_slots = 0usize
    while value_at < function.value_count {
        allocations[value_at] = zero
        var register = 0usize
        var found_register = false
        while register < register_count {
            var occupied = false
            var previous = 0usize
            while previous < value_at {
                let allocation = allocations[previous]
                if allocation.kind == .Register && allocation.index == register && ranges[previous].last >= ranges[value_at].first {
                    occupied = true
                    break
                }
                previous += 1usize
            }
            if !occupied {
                found_register = true
                break
            }
            register += 1usize
        }
        if found_register {
            allocations[value_at] = Allocation { kind: .Register, index: register }
        } else {
            var spill_candidate = 0usize
            var found_candidate = false
            var previous = 0usize
            while previous < value_at {
                let allocation = allocations[previous]
                if allocation.kind == .Register && ranges[previous].last >= ranges[value_at].first {
                    if !found_candidate || ranges[previous].last > ranges[spill_candidate].last || (ranges[previous].last == ranges[spill_candidate].last && previous > spill_candidate) {
                        spill_candidate = previous
                        found_candidate = true
                    }
                }
                previous += 1usize
            }
            if found_candidate && ranges[spill_candidate].last > ranges[value_at].last {
                let stolen_register = allocations[spill_candidate].index
                allocations[spill_candidate] = Allocation { kind: .Stack, index: stack_slots }
                stack_slots += 1usize
                allocations[value_at] = Allocation { kind: .Register, index: stolen_register }
            } else {
                allocations[value_at] = Allocation { kind: .Stack, index: stack_slots }
                stack_slots += 1usize
            }
        }
        value_at += 1usize
    }
    ret (stack_slots, ok)
}

fn self_test() -> err {
    var functions: [1]nir.Function = zero
    var blocks: [1]nir.Block = zero
    var instructions: [4]nir.Instruction = zero
    var operands: [3]usize = zero
    var references: [1]nir.FunctionRef = zero
    var strings: [1]nir.StringConstant = zero
    var builder: nir.Builder = zero
    try nir.init(&builder, functions[..], blocks[..], instructions[..], operands[..], references[..], strings[..])
    builder.function_count = 1usize
    builder.instruction_count = 4usize
    builder.operand_count = 3usize
    builder.functions[0usize] = zero
    builder.functions[0usize].first_instruction = 0usize
    builder.functions[0usize].instruction_count = 4usize
    builder.functions[0usize].value_count = 3usize
    builder.instructions[0usize] = zero
    builder.instructions[0usize].has_result = true
    builder.instructions[0usize].result = 0usize
    builder.instructions[1usize] = zero
    builder.instructions[1usize].has_result = true
    builder.instructions[1usize].result = 1usize
    builder.instructions[2usize] = zero
    builder.instructions[2usize].has_result = true
    builder.instructions[2usize].result = 2usize
    builder.instructions[3usize] = zero
    builder.instructions[3usize].first_operand = 0usize
    builder.instructions[3usize].operand_count = 3usize
    builder.operands[0usize] = 0usize
    builder.operands[1usize] = 1usize
    builder.operands[2usize] = 2usize
    var ranges: [3]LiveRange = zero
    var allocations: [3]Allocation = zero
    let (stack_slots, allocation_error) = allocate(&builder, 0usize, 2usize, ranges[..], allocations[..])
    if allocation_error != ok || stack_slots != 1usize { ret InvalidIR }
    if allocations[0usize].kind != .Register || allocations[0usize].index != 0usize { ret InvalidIR }
    if allocations[1usize].kind != .Register || allocations[1usize].index != 1usize { ret InvalidIR }
    if allocations[2usize].kind != .Stack || allocations[2usize].index != 0usize { ret InvalidIR }
    ret ok
}
