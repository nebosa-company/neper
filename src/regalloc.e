// Deterministic linear-scan allocation for function-local NIR SSA values.

use check
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
    // Read by some instruction; a value that is not is a promoted local's former load.
    used: bool,
}

type Allocation = struct {
    kind: AllocationKind,
    index: usize,
}

fn extend_back_edge(function: nir.Function, ranges: []LiveRange, source_instruction: usize, target_block: usize, builder: *nir.Builder, changed: *bool) -> err {
    if target_block < function.first_block || target_block >= function.first_block + function.block_count { ret InvalidIR }
    let target_instruction = builder.blocks[target_block].first_instruction
    if target_instruction > source_instruction { ret ok }
    var value = 0usize
    while value < function.value_count {
        let range = ranges[value]
        // Live across the edge: defined before the target, so it enters the loop
        // from outside, and used inside it. A value the loop defines is recomputed
        // by the next iteration and is no register's business past its last use;
        // extending those too (as this did until D236) put every temporary of a loop
        // in one live range and spilled the loop.
        if range.defined && range.first < target_instruction && range.last >= target_instruction && range.last < source_instruction {
            ranges[value].last = source_instruction
            *changed = true
        }
        value += 1usize
    }
    ret ok
}

fn extend_loop_liveness(builder: *nir.Builder, function: nir.Function, ranges: []LiveRange) -> err {
    var pass = 0usize
    while pass < function.block_count {
        var changed = false
        var block_at = function.first_block
        while block_at < function.first_block + function.block_count {
            let block = builder.blocks[block_at]
            if block.instruction_count == 0usize { ret InvalidIR }
            let terminator_index = block.first_instruction + block.instruction_count - 1usize
            if terminator_index >= builder.instruction_count { ret InvalidIR }
            let terminator = builder.instructions[terminator_index]
            if terminator.opcode == .Branch {
                try extend_back_edge(function, ranges, terminator_index, terminator.target, builder, &changed)
            } else {
                if terminator.opcode == .BranchIf {
                    try extend_back_edge(function, ranges, terminator_index, terminator.target, builder, &changed)
                    try extend_back_edge(function, ranges, terminator_index, terminator.target2, builder, &changed)
                }
            }
            block_at += 1usize
        }
        if !changed { ret ok }
        pass += 1usize
    }
    ret ok
}

// A scalar kind a register holds whole: what a promoted local may be.
fn register_kind(ty: check.Type) -> bool {
    ret ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Pointer || ty.kind == .Function || ty.kind == .Err || ty.kind == .Float
}

// Section 13's allocator over the locals too (D236). Lowering makes every `var` a stack
// object read and written through its address, so a loop counter is a store-to-load
// chain through memory. A scalar local whose address is used for nothing but loading
// and storing it, at one width, is one value instead: its `Stack` becomes a zero value
// numbered as the local, every `Store` to it a `Bitcast` that defines that same number
// again, a `Zero` of it the zero value, and every `Load` a `Bitcast` reading it. The
// number is defined more than once, which is what the ranges below allow: one range from
// its first definition to its last use, the way a variable has always had one register.
fn promote_locals(builder: *nir.Builder, function: nir.Function) -> err {
    let end = function.first_instruction + function.instruction_count
    if end > builder.instruction_count { ret InvalidIR }
    var at = function.first_instruction
    while at < end {
        let stack = builder.instructions[at]
        if stack.opcode == .Stack && stack.has_result && stack.immediate <= 1usize && register_kind(stack.ty) {
            var promotable = true
            var width = 0usize
            var scan = function.first_instruction
            while scan < end && promotable {
                let instruction = builder.instructions[scan]
                var operand_at = 0usize
                while operand_at < instruction.operand_count {
                    if instruction.first_operand + operand_at >= builder.operand_count { ret InvalidIR }
                    if builder.operands[instruction.first_operand + operand_at] == stack.result {
                        let load = instruction.opcode == .Load && instruction.operand_count == 1usize
                        let store = instruction.opcode == .Store && instruction.operand_count == 2usize
                        let clear = instruction.opcode == .Zero && !instruction.has_result && instruction.operand_count == 1usize
                        if operand_at != 0usize || !(load || store || clear) || !register_kind(instruction.ty) || instruction.immediate == 0usize || instruction.immediate > 8usize {
                            promotable = false
                        } else {
                            if width == 0usize { width = instruction.immediate }
                            if width != instruction.immediate { promotable = false }
                        }
                    }
                    operand_at += 1usize
                }
                scan += 1usize
            }
            if promotable && width != 0usize {
                // First the accesses themselves, while the address still tells them
                // apart from a store through a pointer the local holds.
                builder.instructions[at].opcode = .Zero
                builder.instructions[at].immediate = 0usize
                scan = function.first_instruction
                while scan < end {
                    let instruction = builder.instructions[scan]
                    if instruction.operand_count != 0usize && builder.operands[instruction.first_operand] == stack.result {
                        if instruction.opcode == .Load {
                            builder.instructions[scan].opcode = .Bitcast
                            builder.instructions[scan].immediate = 0usize
                        }
                        if instruction.opcode == .Store {
                            builder.instructions[scan].opcode = .Bitcast
                            builder.instructions[scan].immediate = 0usize
                            builder.instructions[scan].has_result = true
                            builder.instructions[scan].result = stack.result
                            builder.instructions[scan].first_operand = instruction.first_operand + 1usize
                            builder.instructions[scan].operand_count = 1usize
                        }
                        if instruction.opcode == .Zero {
                            builder.instructions[scan].has_result = true
                            builder.instructions[scan].result = stack.result
                            builder.instructions[scan].immediate = 0usize
                            builder.instructions[scan].operand_count = 0usize
                        }
                    }
                    scan += 1usize
                }
                // Then a use of what a load read, in the load's own block and before the
                // next definition of the local, reads the local itself; a use elsewhere
                // keeps the load's copy, since a store may lie on the way to it. A load
                // whose every use was redirected is a bitcast nothing reads, and
                // selection leaves that out.
                scan = function.first_instruction
                while scan < end {
                    let loaded = builder.instructions[scan]
                    if loaded.opcode == .Bitcast && loaded.has_result && loaded.result != stack.result && loaded.operand_count == 1usize && builder.operands[loaded.first_operand] == stack.result {
                        let (block_end, block_error) = block_end_of(builder, function, scan)
                        if block_error != ok { ret block_error }
                        var use_at = scan + 1usize
                        var redefined = false
                        while use_at < block_end && !redefined {
                            let user = builder.instructions[use_at]
                            var operand_index = 0usize
                            while operand_index < user.operand_count {
                                if builder.operands[user.first_operand + operand_index] == loaded.result { builder.operands[user.first_operand + operand_index] = stack.result }
                                operand_index += 1usize
                            }
                            if user.has_result && user.result == stack.result { redefined = true }
                            use_at += 1usize
                        }
                    }
                    scan += 1usize
                }
            }
        }
        at += 1usize
    }
    ret ok
}

// One past the last instruction of the block holding `instruction_index`.
fn block_end_of(builder: *nir.Builder, function: nir.Function, instruction_index: usize) -> (usize, err) {
    var block_at = function.first_block
    while block_at < function.first_block + function.block_count {
        let block = builder.blocks[block_at]
        if instruction_index >= block.first_instruction && instruction_index < block.first_instruction + block.instruction_count { ret (block.first_instruction + block.instruction_count, ok) }
        block_at += 1usize
    }
    ret (0usize, InvalidIR)
}

fn build_ranges(builder: *nir.Builder, function: nir.Function, ranges: []LiveRange) -> err {
    if function.value_count > ranges.len { ret Capacity }
    var value_at = 0usize
    while value_at < function.value_count {
        var empty_range: LiveRange = zero
        ranges[value_at] = empty_range
        value_at += 1usize
    }
    let instruction_end = function.first_instruction + function.instruction_count
    var instruction_at = function.first_instruction
    while instruction_at < instruction_end {
        if instruction_at >= builder.instruction_count { ret InvalidIR }
        let instruction = builder.instructions[instruction_at]
        if instruction.has_result {
            if instruction.result >= function.value_count { ret InvalidIR }
            // A promoted local is defined at every store to it (D236): one range.
            if ranges[instruction.result].defined {
                ranges[instruction.result].last = instruction_at
            } else {
                ranges[instruction.result] = LiveRange { first: instruction_at, last: instruction_at, defined: true, used: false }
            }
        }
        let operand_end = instruction.first_operand + instruction.operand_count
        var operand_at = instruction.first_operand
        while operand_at < operand_end {
            if operand_at >= builder.operand_count { ret InvalidIR }
            let value = builder.operands[operand_at]
            if value >= function.value_count || !ranges[value].defined { ret InvalidIR }
            ranges[value].last = instruction_at
            ranges[value].used = true
            operand_at += 1usize
        }
        instruction_at += 1usize
    }
    value_at = 0usize
    while value_at < function.value_count {
        if !ranges[value_at].defined { ret InvalidIR }
        value_at += 1usize
    }
    ret extend_loop_liveness(builder, function, ranges)
}

fn allocate(builder: *nir.Builder, function_index: usize, register_count: usize, ranges: []LiveRange, allocations: []Allocation) -> (usize, err) {
    if register_count == 0usize { ret (0usize, NoRegisters) }
    if function_index >= builder.function_count { ret (0usize, InvalidIR) }
    let function = builder.functions[function_index]
    if function.value_count > allocations.len { ret (0usize, Capacity) }
    let promotion_error = promote_locals(builder, function)
    if promotion_error != ok { ret (0usize, promotion_error) }
    let ranges_error = build_ranges(builder, function, ranges)
    if ranges_error != ok { ret (0usize, ranges_error) }
    var value_at = 0usize
    var stack_slots = 0usize
    while value_at < function.value_count {
        var empty_allocation: Allocation = zero
        allocations[value_at] = empty_allocation
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
    var test_function: nir.Function = zero
    test_function.first_instruction = 0usize
    test_function.instruction_count = 4usize
    test_function.value_count = 3usize
    functions[0usize] = test_function
    var instruction0: nir.Instruction = zero
    instruction0.has_result = true
    instruction0.result = 0usize
    instructions[0usize] = instruction0
    var instruction1: nir.Instruction = zero
    instruction1.has_result = true
    instruction1.result = 1usize
    instructions[1usize] = instruction1
    var instruction2: nir.Instruction = zero
    instruction2.has_result = true
    instruction2.result = 2usize
    instructions[2usize] = instruction2
    var instruction3: nir.Instruction = zero
    instruction3.first_operand = 0usize
    instruction3.operand_count = 3usize
    instructions[3usize] = instruction3
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
