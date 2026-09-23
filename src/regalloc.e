// Deterministic linear-scan allocation for function-local NIR SSA values.

use e.mem
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

// Loop liveness by the values inside each loop (D403): the back edges sorted by
// their source, the values by their last use, and each edge visits the values whose
// last use lies in its body -- a value is visited once per loop that encloses that
// use, where `extend_loop_liveness_slow` visited every value for every back edge and
// made a function with a thousand loops cost a hundred times one with two hundred.
// The rule is the same one, applied to a fixed point in passes as before, so the
// ranges are the ranges the slow walk found; the scratch is the heaps the allocation
// fills afterwards, and a function the scratch cannot hold takes the slow walk.
fn extend_loop_liveness(builder: *nir.Builder, function: nir.Function, ranges: []LiveRange, scratch: []usize) -> err {
    let value_count = function.value_count
    let block_count = function.block_count
    if scratch.len < value_count * 2usize + block_count * 4usize { ret extend_loop_liveness_slow(builder, function, ranges) }
    let order = scratch[0usize..value_count]
    let keys = scratch[value_count..value_count * 2usize]
    let edges_start = value_count * 2usize
    let edges = scratch[edges_start..edges_start + block_count * 4usize]
    // The back edges: (target instruction, source instruction), two per block at most.
    var edge_count = 0usize
    var block_at = function.first_block
    while block_at < function.first_block + function.block_count {
        let block = builder.blocks[block_at]
        if block.instruction_count == 0usize { ret InvalidIR }
        let terminator_index = block.first_instruction + block.instruction_count - 1usize
        if terminator_index >= builder.instruction_count { ret InvalidIR }
        let terminator = builder.instructions[terminator_index]
        if terminator.opcode == .Branch || terminator.opcode == .BranchIf {
            try add_back_edge(builder, function, edges, &edge_count, terminator_index, terminator.target)
            if terminator.opcode == .BranchIf { try add_back_edge(builder, function, edges, &edge_count, terminator_index, terminator.target2) }
        }
        block_at += 1usize
    }
    if edge_count == 0usize { ret ok }
    // A function with few loops is cheaper to walk whole: the slow walk costs the
    // edges times the values per pass, the sort the values times their logarithm.
    if edge_count <= 16usize { ret extend_loop_liveness_slow(builder, function, ranges) }
    sort_edges_by_source(edges, edge_count)
    var pass = 0usize
    while pass < function.block_count {
        // The values by their last use, the keys a snapshot: an extension during the
        // pass moves a value's last past the edge, and the walk still reads the order.
        var value_at = 0usize
        while value_at < value_count {
            order[value_at] = value_at
            keys[value_at] = ranges[value_at].last
            value_at += 1usize
        }
        sort_values_by_key(order, keys, value_count)
        var changed = false
        var edge_at = 0usize
        while edge_at < edge_count {
            let target_instruction = edges[edge_at * 2usize]
            let source_instruction = edges[edge_at * 2usize + 1usize]
            // The first value whose last use is at or after the target.
            var low = 0usize
            var high = value_count
            while low < high {
                let mid = low + (high - low) / 2usize
                if keys[mid] < target_instruction { low = mid + 1usize } else { high = mid }
            }
            var at = low
            while at < value_count && keys[at] < source_instruction {
                let value = order[at]
                let range = ranges[value]
                if range.defined && range.first < target_instruction && range.last >= target_instruction && range.last < source_instruction {
                    ranges[value].last = source_instruction
                    changed = true
                }
                at += 1usize
            }
            edge_at += 1usize
        }
        if !changed { ret ok }
        pass += 1usize
    }
    ret ok
}

fn add_back_edge(builder: *nir.Builder, function: nir.Function, edges: []usize, edge_count: *usize, source_instruction: usize, target_block: usize) -> err {
    if target_block < function.first_block || target_block >= function.first_block + function.block_count { ret InvalidIR }
    let target_instruction = builder.blocks[target_block].first_instruction
    if target_instruction > source_instruction { ret ok }
    if *edge_count * 2usize + 2usize > edges.len { ret Capacity }
    edges[*edge_count * 2usize] = target_instruction
    edges[*edge_count * 2usize + 1usize] = source_instruction
    *edge_count = *edge_count + 1usize
    ret ok
}

// Heap sort of the edge pairs by source, then target: in place, no allocation.
fn sort_edges_by_source(edges: []usize, count: usize) {
    var heap_size = count
    var build = count / 2usize
    while build > 0usize {
        build = build - 1usize
        sift_edges(edges, build, heap_size)
    }
    while heap_size > 1usize {
        heap_size = heap_size - 1usize
        swap_edges(edges, 0usize, heap_size)
        sift_edges(edges, 0usize, heap_size)
    }
}

fn edge_greater(edges: []usize, a: usize, b: usize) -> bool {
    if edges[a * 2usize + 1usize] != edges[b * 2usize + 1usize] { ret edges[a * 2usize + 1usize] > edges[b * 2usize + 1usize] }
    ret edges[a * 2usize] > edges[b * 2usize]
}

fn swap_edges(edges: []usize, a: usize, b: usize) {
    let target_at = edges[a * 2usize]
    let source_at = edges[a * 2usize + 1usize]
    edges[a * 2usize] = edges[b * 2usize]
    edges[a * 2usize + 1usize] = edges[b * 2usize + 1usize]
    edges[b * 2usize] = target_at
    edges[b * 2usize + 1usize] = source_at
}

fn sift_edges(edges: []usize, start: usize, heap_size: usize) {
    var at = start
    while true {
        var largest = at
        let left = at * 2usize + 1usize
        let right = left + 1usize
        if left < heap_size && edge_greater(edges, left, largest) { largest = left }
        if right < heap_size && edge_greater(edges, right, largest) { largest = right }
        if largest == at { ret }
        swap_edges(edges, at, largest)
        at = largest
    }
}

// Heap sort of the value order by key, then value: in place, no allocation.
fn sort_values_by_key(order: []usize, keys: []usize, count: usize) {
    var heap_size = count
    var build = count / 2usize
    while build > 0usize {
        build = build - 1usize
        sift_values(order, keys, build, heap_size)
    }
    while heap_size > 1usize {
        heap_size = heap_size - 1usize
        swap_values(order, keys, 0usize, heap_size)
        sift_values(order, keys, 0usize, heap_size)
    }
}

fn value_greater(order: []usize, keys: []usize, a: usize, b: usize) -> bool {
    if keys[a] != keys[b] { ret keys[a] > keys[b] }
    ret order[a] > order[b]
}

fn swap_values(order: []usize, keys: []usize, a: usize, b: usize) {
    let value = order[a]
    let key = keys[a]
    order[a] = order[b]
    keys[a] = keys[b]
    order[b] = value
    keys[b] = key
}

fn sift_values(order: []usize, keys: []usize, start: usize, heap_size: usize) {
    var at = start
    while true {
        var largest = at
        let left = at * 2usize + 1usize
        let right = left + 1usize
        if left < heap_size && value_greater(order, keys, left, largest) { largest = left }
        if right < heap_size && value_greater(order, keys, right, largest) { largest = right }
        if largest == at { ret }
        swap_values(order, keys, at, largest)
        at = largest
    }
}

fn extend_loop_liveness_slow(builder: *nir.Builder, function: nir.Function, ranges: []LiveRange) -> err {
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
fn promote_locals(builder: *nir.Builder, function: nir.Function, scratch: []usize) -> err {
    let end = function.first_instruction + function.instruction_count
    if end > builder.instruction_count { ret InvalidIR }
    // Every value's uses, listed once (D330): which instructions name it as an
    // operand, in instruction order. Each local's scans below read its own list
    // instead of walking the function's instructions and operands -- a scan per local
    // was the allocator's largest cost -- and process the locals in the same order,
    // so the rewriting is the one the walks did.
    let values = function.value_count
    if scratch.len < values * 2usize + 2usize { ret promote_locals_walked(builder, function) }
    var counts = scratch[0usize..values + 1usize]
    var clear_at = 0usize
    while clear_at < counts.len {
        counts[clear_at] = 0usize
        clear_at += 1usize
    }
    var total = 0usize
    var at = function.first_instruction
    // The walks read an instruction's fields where they copied it whole (D932).
    while at < end {
        let first_operand = builder.instructions[at].first_operand
        let operand_count = builder.instructions[at].operand_count
        if first_operand + operand_count > builder.operand_count { ret InvalidIR }
        var operand_at = 0usize
        while operand_at < operand_count {
            let value = builder.operands[first_operand + operand_at]
            if value >= values { ret InvalidIR }
            counts[value] += 1usize
            total += 1usize
            operand_at += 1usize
        }
        at += 1usize
    }
    if scratch.len < values * 2usize + 2usize + total { ret promote_locals_walked(builder, function) }
    // Offsets: `starts[v]` is where v's uses begin; `fill[v]` walks it while filling.
    var starts = scratch[values + 1usize..values * 2usize + 2usize]
    var uses = scratch[values * 2usize + 2usize..values * 2usize + 2usize + total]
    var running = 0usize
    var value_at = 0usize
    while value_at < values {
        starts[value_at] = running
        running += counts[value_at]
        counts[value_at] = starts[value_at]
        value_at += 1usize
    }
    starts[values] = running
    at = function.first_instruction
    while at < end {
        let first_operand = builder.instructions[at].first_operand
        let operand_count = builder.instructions[at].operand_count
        var operand_at = 0usize
        while operand_at < operand_count {
            let value = builder.operands[first_operand + operand_at]
            uses[counts[value]] = at
            counts[value] += 1usize
            operand_at += 1usize
        }
        at += 1usize
    }
    at = function.first_instruction
    while at < end {
        if builder.instructions[at].opcode != .Stack {
            at += 1usize
            continue
        }
        let stack = builder.instructions[at]
        if stack.opcode == .Stack && stack.has_result && stack.immediate <= 1usize && register_kind(stack.ty) {
            var promotable = true
            var width = 0usize
            var use_at = starts[stack.result]
            let use_end = starts[stack.result + 1usize]
            while use_at < use_end && promotable {
                let instruction = builder.instructions[uses[use_at]]
                var operand_at = 0usize
                while operand_at < instruction.operand_count {
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
                use_at += 1usize
            }
            if promotable && width != 0usize {
                // First the accesses themselves, while the address still tells them
                // apart from a store through a pointer the local holds.
                builder.instructions[at].opcode = .Zero
                builder.instructions[at].immediate = 0usize
                use_at = starts[stack.result]
                while use_at < use_end {
                    let scan = uses[use_at]
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
                    use_at += 1usize
                }
                // Then a use of what a load read, in the load's own block and before the
                // next definition of the local, reads the local itself; a use elsewhere
                // keeps the load's copy, since a store may lie on the way to it. A load
                // whose every use was redirected is a bitcast nothing reads, and
                // selection leaves that out. The uses are listed by the operand they
                // were recorded with: a store rewritten above no longer names the local
                // in its operands and is passed over, as the walk passed it over.
                use_at = starts[stack.result]
                while use_at < use_end {
                    let scan = uses[use_at]
                    let loaded = builder.instructions[scan]
                    if loaded.opcode == .Bitcast && loaded.has_result && loaded.result != stack.result && loaded.operand_count == 1usize && builder.operands[loaded.first_operand] == stack.result {
                        let (block_end, block_error) = block_end_of(builder, function, scan)
                        if block_error != ok { ret block_error }
                        var redirect_at = scan + 1usize
                        var redefined = false
                        while redirect_at < block_end && !redefined {
                            let user_first = builder.instructions[redirect_at].first_operand
                            let user_count = builder.instructions[redirect_at].operand_count
                            var operand_index = 0usize
                            while operand_index < user_count {
                                if builder.operands[user_first + operand_index] == loaded.result { builder.operands[user_first + operand_index] = stack.result }
                                operand_index += 1usize
                            }
                            if builder.instructions[redirect_at].has_result && builder.instructions[redirect_at].result == stack.result { redefined = true }
                            redirect_at += 1usize
                        }
                    }
                    use_at += 1usize
                }
            }
        }
        at += 1usize
    }
    ret ok
}

// The walk the use lists replaced, kept for a function whose uses outgrow the scratch.
fn promote_locals_walked(builder: *nir.Builder, function: nir.Function) -> err {
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
// A function's blocks are begun in order, each at the instruction count of its
// moment (`nir.begin_block`), so their ranges ascend with their index and the block
// of an instruction is a binary search (D403): this was a walk over every block per
// promoted load, quadratic in a function with thousands of both.
fn block_end_of(builder: *nir.Builder, function: nir.Function, instruction_index: usize) -> (usize, err) {
    var low = function.first_block
    var high = function.first_block + function.block_count
    while low < high {
        let mid = low + (high - low) / 2usize
        let block = builder.blocks[mid]
        if instruction_index < block.first_instruction {
            high = mid
        } else {
            if instruction_index >= block.first_instruction + block.instruction_count {
                low = mid + 1usize
            } else {
                ret (block.first_instruction + block.instruction_count, ok)
            }
        }
    }
    ret (0usize, InvalidIR)
}

fn build_ranges(builder: *nir.Builder, function: nir.Function, ranges: []LiveRange, scratch: []usize) -> err {
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
    ret extend_loop_liveness(builder, function, ranges, scratch)
}

// --- The allocation (D305) ------------------------------------------------------------
//
// Every value takes the lowest register no live value holds, or, when all are held,
// steals the register of the live value that ends last if that is later than its own
// end, else goes to the stack. The scan that decided "held" and "ends last" walked
// every earlier value for every register for every value -- cubic, and 2.7 of the
// compiler's 5 seconds building itself, because `main` has ten thousand values. The
// decisions depend only on the largest (last, value) among the values each register
// holds, so each register keeps them in a max-heap and the answers are its top. The
// decisions are the same ones, value for value.

fn heap_greater(heaps: []usize, a: usize, b: usize) -> bool {
    if heaps[a] != heaps[b] { ret heaps[a] > heaps[b] }
    ret heaps[a + 1usize] > heaps[b + 1usize]
}

fn heap_swap(heaps: []usize, a: usize, b: usize) {
    let last = heaps[a]
    let value = heaps[a + 1usize]
    heaps[a] = heaps[b]
    heaps[a + 1usize] = heaps[b + 1usize]
    heaps[b] = last
    heaps[b + 1usize] = value
}

// Adds (last, value) to the register's heap: `capacity` pairs per register in `heaps`.
fn heap_push(heaps: []usize, counts: []usize, capacity: usize, register: usize, last: usize, value: usize) -> err {
    let base = register * capacity * 2usize
    var at = counts[register]
    if at >= capacity { ret Capacity }
    counts[register] = at + 1usize
    heaps[base + at * 2usize] = last
    heaps[base + at * 2usize + 1usize] = value
    while at > 0usize {
        let parent = (at - 1usize) / 2usize
        if !heap_greater(heaps, base + at * 2usize, base + parent * 2usize) { break }
        heap_swap(heaps, base + at * 2usize, base + parent * 2usize)
        at = parent
    }
    ret ok
}

fn heap_pop(heaps: []usize, counts: []usize, capacity: usize, register: usize) {
    let base = register * capacity * 2usize
    let count = counts[register]
    if count == 0usize { ret }
    counts[register] = count - 1usize
    if count == 1usize { ret }
    heap_swap(heaps, base, base + (count - 1usize) * 2usize)
    let size = count - 1usize
    var at = 0usize
    while true {
        let left = at * 2usize + 1usize
        let right = left + 1usize
        var largest = at
        if left < size && heap_greater(heaps, base + left * 2usize, base + largest * 2usize) { largest = left }
        if right < size && heap_greater(heaps, base + right * 2usize, base + largest * 2usize) { largest = right }
        if largest == at { break }
        heap_swap(heaps, base + at * 2usize, base + largest * 2usize)
        at = largest
    }
}

// The heaps are register_count segments of value_count pairs, taken from the arena for
// the length of the call.
fn allocate(builder: *nir.Builder, function_index: usize, register_count: usize, ranges: []LiveRange, allocations: []Allocation, a: *mem.Arena) -> (usize, err) {
    if register_count == 0usize { ret (0usize, NoRegisters) }
    if register_count > 16usize { ret (0usize, Capacity) }
    if function_index >= builder.function_count { ret (0usize, InvalidIR) }
    let function = builder.functions[function_index]
    if function.value_count > allocations.len { ret (0usize, Capacity) }
    let capacity = function.value_count
    // The heaps live only as long as this call: taken from the arena and given back.
    let mark = mem.mark(a)
    let (heaps, heaps_error) = mem.alloc[usize](a, register_count * capacity * 2usize + 1usize)
    if heaps_error != ok { ret (0usize, heaps_error) }
    let (slots, allocate_error) = allocate_with(builder, function, register_count, ranges, allocations, heaps, capacity)
    mem.reset(a, mark)
    ret (slots, allocate_error)
}

fn allocate_with(builder: *nir.Builder, function: nir.Function, register_count: usize, ranges: []LiveRange, allocations: []Allocation, heaps: []usize, capacity: usize) -> (usize, err) {
    let promotion_error = promote_locals(builder, function, heaps)
    if promotion_error != ok { ret (0usize, promotion_error) }
    // The heaps are the ranges' scratch until the allocation below fills them.
    let ranges_error = build_ranges(builder, function, ranges, heaps)
    if ranges_error != ok { ret (0usize, ranges_error) }
    var counts: [16]usize = zero
    var value_at = 0usize
    var stack_slots = 0usize
    while value_at < function.value_count {
        var empty_allocation: Allocation = zero
        allocations[value_at] = empty_allocation
        let first = ranges[value_at].first
        let last = ranges[value_at].last
        var register = 0usize
        var found_register = false
        while register < register_count {
            if counts[register] == 0usize || heaps[register * capacity * 2usize] < first {
                found_register = true
                break
            }
            register += 1usize
        }
        if found_register {
            let push_error = heap_push(heaps, counts[..], capacity, register, last, value_at)
            if push_error != ok { ret (0usize, push_error) }
            allocations[value_at] = Allocation { kind: .Register, index: register }
        } else {
            // Every register's top ends at or after this value starts; the latest of them,
            // ties to the higher value, is what the scan found.
            var spill_register = 0usize
            var spill_last = 0usize
            var spill_value = 0usize
            var found_candidate = false
            register = 0usize
            while register < register_count {
                if counts[register] != 0usize {
                    let top_last = heaps[register * capacity * 2usize]
                    let top_value = heaps[register * capacity * 2usize + 1usize]
                    if top_last >= first {
                        if !found_candidate || top_last > spill_last || (top_last == spill_last && top_value > spill_value) {
                            spill_register = register
                            spill_last = top_last
                            spill_value = top_value
                            found_candidate = true
                        }
                    }
                }
                register += 1usize
            }
            if found_candidate && spill_last > last {
                heap_pop(heaps, counts[..], capacity, spill_register)
                allocations[spill_value] = Allocation { kind: .Stack, index: stack_slots }
                stack_slots += 1usize
                let push_error = heap_push(heaps, counts[..], capacity, spill_register, last, value_at)
                if push_error != ok { ret (0usize, push_error) }
                allocations[value_at] = Allocation { kind: .Register, index: spill_register }
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
    var scratch: [4096]u8 = zero
    var arena = mem.arena_from(scratch[..])
    let (stack_slots, allocation_error) = allocate(&builder, 0usize, 2usize, ranges[..], allocations[..], &arena)
    if allocation_error != ok || stack_slots != 1usize { ret InvalidIR }
    if allocations[0usize].kind != .Register || allocations[0usize].index != 0usize { ret InvalidIR }
    if allocations[1usize].kind != .Register || allocations[1usize].index != 1usize { ret InvalidIR }
    if allocations[2usize].kind != .Stack || allocations[2usize].index != 0usize { ret InvalidIR }
    ret ok
}
