// Checked syntax to canonical NIR lowering. The initial slice lowers parameters and
// literal returns; later increments extend expressions and structured control flow.

use artifact_hash
use check
use graph
use layout
use lex
use nir
use parse
use resolve
use syntax

error FunctionNotFound

type Binding = struct {
    name: str,
    ty: check.Type,
    value: usize,
    address: bool,
}

type CallResults = struct {
    call: check.CallInfo,
    values: [16]usize,
    addresses: [16]bool,
    count: usize,
}

type DeferredKind = enum u8 {
    Invalid,
    Call,
    Statement,
    Block,
}

type Deferred = struct {
    kind: DeferredKind,
    call: check.CallInfo,
    callee: usize,
    arguments: [16]usize,
    argument_count: usize,
    token: lex.Token,
    node_index: usize,
}

type DeferState = struct {
    entries: [256]Deferred,
    count: usize,
}

type ReturnLayout = struct {
    offsets: [16]usize,
    size: usize,
    alignment: usize,
    via_slot: bool,
}

type LoopControl = struct {
    active: bool,
    continue_target: usize,
    break_defer_base: usize,
    continue_defer_base: usize,
    breaks: []usize,
    break_count: usize,
}

fn find_binding(bindings: []Binding, count: usize, name: str) -> (Binding, bool) {
    var empty: Binding = zero
    var at = count
    while at > 0usize {
        at = at - 1usize
        if check.same(bindings[at].name, name) { ret (bindings[at], true) }
    }
    ret (empty, false)
}

fn add_binding(bindings: []Binding, count: *usize, binding: Binding) -> err {
    if *count == bindings.len { ret check.Capacity }
    bindings[*count] = binding
    *count += 1usize
    ret ok
}

fn bind_value(c: *check.Checker, g: *graph.Graph, module_index: usize, token: lex.Token, ty: check.Type, value: usize, address_value: bool, mutable: bool, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    if token.kind == .PunctUnderscore { ret ok }
    if token.kind != .Identifier { ret parse.InvalidSyntax }
    var stored_value = value
    var address = address_value
    if aggregate_value(c, ty) {
        let (info, info_error) = layout.type_info(c, ty)
        if info_error != ok { ret info_error }
        var slots = (info.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, ty, true, slots, token)
        if stack_error != ok { ret stack_error }
        let (copy_instruction, ignored, copy_error) = nir.emit(builder, .Copy, ty, false, info.size, token)
        if copy_error != ok { ret copy_error }
        try nir.add_operand(builder, copy_instruction, stack)
        try nir.add_operand(builder, copy_instruction, value)
        stored_value = stack
        address = true
    } else {
    if mutable && !address {
        let (info, info_error) = layout.type_info(c, ty)
        if info_error != ok { ret info_error }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, ty, true, 0usize, token)
        if stack_error != ok { ret stack_error }
        let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, ty, false, info.size, token)
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, stack)
        try nir.add_operand(builder, store_instruction, value)
        stored_value = stack
        address = true
    }
    }
    let name = g.modules[module_index].text[token.start..token.end]
    try add_binding(bindings, binding_count, Binding { name: name, ty: ty, value: stored_value, address: address })
    ret check.add_local(c, name, ty, mutable)
}

fn bind_call_results(c: *check.Checker, g: *graph.Graph, module_index: usize, binding_node: syntax.Node, results: *CallResults, mutable: bool, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    var result_at = 0usize
    var token_at = binding_node.token_start
    while token_at < binding_node.token_end {
        let token = c.tokens[token_at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            if result_at >= results.count { ret check.ArgumentCount }
            let (ty, type_error) = check.call_return(c, results.call, result_at)
            if type_error != ok { ret type_error }
            try bind_value(c, g, module_index, token, ty, results.values[result_at], results.addresses[result_at], mutable, builder, bindings, binding_count)
            result_at += 1usize
        }
        token_at += 1usize
    }
    if result_at != results.count { ret check.ArgumentCount }
    ret ok
}

fn declaration_name(c: *check.Checker, text: str, node: syntax.Node) -> (str, err) {
    let name_index = node.token_start + 1usize
    if name_index >= node.token_end || name_index >= c.token_count { ret ("", parse.InvalidSyntax) }
    let token = c.tokens[name_index]
    if token.kind != .Identifier { ret ("", parse.InvalidSyntax) }
    ret (text[token.start..token.end], ok)
}

fn literal(c: *check.Checker, text: str, node: syntax.Node, expected: check.Type, builder: *nir.Builder) -> (usize, err) {
    if node.kind != .LiteralExpr || node.token_start >= c.token_count { ret (0usize, check.Unsupported) }
    let token = c.tokens[node.token_start]
    if token.kind == .KwZero && aggregate_value(c, expected) {
        let (info, info_error) = layout.type_info(c, expected)
        if info_error != ok { ret (0usize, info_error) }
        var slots = (info.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, expected, true, slots, token)
        if stack_error != ok { ret (0usize, stack_error) }
        let (zero_instruction, ignored, zero_error) = nir.emit(builder, .Zero, expected, false, info.size, token)
        if zero_error != ok { ret (0usize, zero_error) }
        let operand_error = nir.add_operand(builder, zero_instruction, stack)
        if operand_error != ok { ret (0usize, operand_error) }
        ret (stack, ok)
    }
    var opcode: nir.Opcode = .Invalid
    var immediate = 0usize
    var ty = expected
    if token.kind == .KwOk {
        opcode = .ConstError
    } else {
        if token.kind == .KwTrue || token.kind == .KwFalse {
            opcode = .ConstBool
            if token.kind == .KwTrue { immediate = 1usize }
        } else {
            if token.kind == .KwZero {
                opcode = .Zero
            } else {
                if token.kind == .String || token.kind == .RawString {
                    opcode = .ConstString
                    let (string_index, string_error) = nir.intern_string(builder, text[token.start..token.end])
                    if string_error != ok { ret (0usize, string_error) }
                    immediate = string_index
                } else {
                    if token.kind != .Integer { ret (0usize, check.Unsupported) }
                    let (value, literal_type, value_error) = check.integer_literal_value(c, text, node)
                    if value_error != ok { ret (0usize, value_error) }
                    opcode = .ConstInteger
                    immediate = value
                    if ty.kind == .Invalid { ty = literal_type }
                }
            }
        }
    }
    let (instruction, result, emit_error) = nir.emit(builder, opcode, ty, true, immediate, token)
    if emit_error != ok { ret (0usize, emit_error) }
    ret (result, ok)
}

fn lower_constant(c: *check.Checker, constant_index: usize, ty: check.Type, token: lex.Token, builder: *nir.Builder) -> (usize, err) {
    if constant_index >= c.constant_count || c.constants[constant_index].state != 2u8 || ty.kind != .Integer { ret (0usize, check.InvalidConstant) }
    let width = check.integer_width(ty)
    if width == 0usize { ret (0usize, check.InvalidType) }
    let immediate = check.integer_bits(c.constants[constant_index].value, width)
    let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, ty, true, immediate, token)
    ret (result, emit_error)
}

fn register_return_type(c: *check.Checker, ty: check.Type) -> bool {
    if ty.kind == .Bool || ty.kind == .Err || ty.kind == .Integer || ty.kind == .Pointer { ret true }
    if ty.kind == .Named || ty.kind == .Tag {
        let (aggregate_index, found) = layout.aggregate_index(c, ty)
        if found && c.aggregates[aggregate_index].kind == .Enum { ret true }
    }
    ret false
}

fn call_return_layout(c: *check.Checker, call: check.CallInfo, result: *ReturnLayout) -> err {
    result.alignment = 1usize
    if call.function.return_count > result.offsets.len { ret check.Capacity }
    var integer_count = 0usize
    var at = 0usize
    while at < call.function.return_count {
        let (ty, type_error) = check.call_return(c, call, at)
        if type_error != ok { ret type_error }
        let (info, info_error) = layout.type_info(c, ty)
        if info_error != ok { ret info_error }
        let (offset, offset_error) = layout.align_up(result.size, info.alignment)
        if offset_error != ok || offset > 18446744073709551615usize - info.size { ret layout.Overflow }
        result.offsets[at] = offset
        result.size = offset + info.size
        if info.alignment > result.alignment { result.alignment = info.alignment }
        if register_return_type(c, ty) { integer_count += 1usize } else { result.via_slot = true }
        at += 1usize
    }
    if integer_count > 2usize { result.via_slot = true }
    if call.mem_alloc { result.via_slot = true }
    let (rounded, rounded_error) = layout.align_up(result.size, result.alignment)
    if rounded_error != ok { ret rounded_error }
    result.size = rounded
    ret ok
}

fn call_parameter_type(c: *check.Checker, call: check.CallInfo, index: usize) -> (check.Type, err) {
    if index >= call.function.parameter_count { ret (check.invalid_type(), check.ArgumentCount) }
    if call.indirect {
        let (signature, has_signature) = check.function_signature_of(c, call.indirect_type)
        if !has_signature { ret (check.invalid_type(), check.InvalidType) }
        let (parameter, has_parameter) = check.function_signature_parameter(c, signature, index)
        if !has_parameter { ret (check.invalid_type(), check.ArgumentCount) }
        ret (parameter, ok)
    }
    if call.protocol_builtin != .None { ret (call.protocol_type, ok) }
    if call.mem_alloc {
        if index == 0usize { ret (call.alloc_arena, ok) }
        ret (check.make_type(.Integer, "usize", call.function.module_index), ok)
    }
    let parameter_index = call.function.first_parameter + index
    if parameter_index >= c.parameter_count { ret (check.invalid_type(), check.InvalidType) }
    ret (c.parameters[parameter_index].ty, ok)
}

fn intrinsic_symbol(name: str) -> (str, err) {
    if check.same(name, "mark") { ret ("neper_mem_mark", ok) }
    if check.same(name, "reset") { ret ("neper_mem_reset", ok) }
    if check.same(name, "stats") { ret ("neper_mem_stats", ok) }
    if check.same(name, "open") { ret ("neper_os_open", ok) }
    if check.same(name, "read") { ret ("neper_os_read", ok) }
    if check.same(name, "write") { ret ("neper_os_write", ok) }
    if check.same(name, "close") { ret ("neper_os_close", ok) }
    if check.same(name, "stdout") { ret ("neper_os_stdout", ok) }
    if check.same(name, "stderr") { ret ("neper_os_stderr", ok) }
    if check.same(name, "readdir") { ret ("neper_os_readdir", ok) }
    if check.same(name, "spawn") { ret ("neper_os_spawn", ok) }
    if check.same(name, "wait") { ret ("neper_os_wait", ok) }
    if check.same(name, "exit") { ret ("neper_os_exit", ok) }
    if check.same(name, "args") { ret ("neper_os_args", ok) }
    if check.same(name, "reserve") { ret ("neper_os_reserve", ok) }
    if check.same(name, "commit") { ret ("neper_os_commit", ok) }
    if check.same(name, "clock") { ret ("neper_os_clock", ok) }
    ret ("", check.UnknownCallable)
}

fn store_supplied_cmp_result(builder: *nir.Builder, slot: usize, result_type: check.Type, magnitude: usize, negative: bool, token: lex.Token) -> (usize, err) {
    let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstInteger, result_type, true, magnitude, token)
    if constant_error != ok { ret (0usize, constant_error) }
    var value = constant
    if negative {
        let (negate_instruction, negated, negate_error) = nir.emit(builder, .Negate, result_type, true, 0usize, token)
        if negate_error != ok { ret (0usize, negate_error) }
        let negate_operand_error = nir.add_operand(builder, negate_instruction, constant)
        if negate_operand_error != ok { ret (0usize, negate_operand_error) }
        value = negated
    }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, result_type, false, 0usize, token)
    if store_error != ok { ret (0usize, store_error) }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret (0usize, address_error) }
    let value_error = nir.add_operand(builder, store_instruction, value)
    if value_error != ok { ret (0usize, value_error) }
    let (exit_branch, exit_error) = emit_branch(builder, token)
    ret (exit_branch, exit_error)
}

fn ordering_opcode(opcode: nir.Opcode) -> bool {
    ret opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual
}

// An enum orders by its backing integer, and only the backing integer says
// whether that ordering is signed. Codegen sees the named type, which does not,
// so the conversion is made explicit here rather than resolved down there.
fn coerce_ordering_operand(c: *check.Checker, ty: check.Type, value: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (backing, is_enum) = check.enum_backing_type(c, ty)
    if !is_enum { ret (value, ok) }
    let (instruction, converted, emit_error) = nir.emit(builder, .Cast, backing, true, 0usize, token)
    if emit_error != ok { ret (0usize, emit_error) }
    let operand_error = nir.add_operand(builder, instruction, value)
    if operand_error != ok { ret (0usize, operand_error) }
    ret (converted, ok)
}

fn emit_supplied_compare(builder: *nir.Builder, opcode: nir.Opcode, boolean: check.Type, left: usize, right: usize, token: lex.Token) -> (usize, err) {
    let (instruction, value, emit_error) = nir.emit(builder, opcode, boolean, true, 0usize, token)
    if emit_error != ok { ret (0usize, emit_error) }
    let left_error = nir.add_operand(builder, instruction, left)
    if left_error != ok { ret (0usize, left_error) }
    let right_error = nir.add_operand(builder, instruction, right)
    if right_error != ok { ret (0usize, right_error) }
    ret (value, ok)
}

// The data pointer and length behind an array, slice or `str`. An array value is
// already its storage and its length is static; a slice and a `str` are a
// {pointer, length} pair, which is also how one sits inside an enclosing sequence.
fn sequence_parts(c: *check.Checker, ty: check.Type, subject: usize, builder: *nir.Builder, token: lex.Token) -> (usize, usize, err) {
    let usize_type = check.make_type(.Integer, "usize", ty.module_index)
    if ty.kind == .Array {
        let (length_instruction, length_value, length_error) = nir.emit(builder, .ConstInteger, usize_type, true, ty.array_length, token)
        if length_error != ok { ret (0usize, 0usize, length_error) }
        ret (subject, length_value, ok)
    }
    if ty.kind != .Slice && ty.kind != .String { ret (0usize, 0usize, check.Unsupported) }
    let pointer_type = check.make_type(.Pointer, "", ty.module_index)
    let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, token)
    if data_address_error != ok { ret (0usize, 0usize, data_address_error) }
    let data_address_operand_error = nir.add_operand(builder, data_address_instruction, subject)
    if data_address_operand_error != ok { ret (0usize, 0usize, data_address_operand_error) }
    let (data_load_instruction, data_value, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, token)
    if data_load_error != ok { ret (0usize, 0usize, data_load_error) }
    let data_load_operand_error = nir.add_operand(builder, data_load_instruction, data_address)
    if data_load_operand_error != ok { ret (0usize, 0usize, data_load_operand_error) }
    let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, token)
    if length_address_error != ok { ret (0usize, 0usize, length_address_error) }
    let length_address_operand_error = nir.add_operand(builder, length_address_instruction, subject)
    if length_address_operand_error != ok { ret (0usize, 0usize, length_address_operand_error) }
    let (length_load_instruction, length_value, length_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if length_load_error != ok { ret (0usize, 0usize, length_load_error) }
    let length_load_operand_error = nir.add_operand(builder, length_load_instruction, length_address)
    if length_load_operand_error != ok { ret (0usize, 0usize, length_load_operand_error) }
    ret (data_value, length_value, ok)
}

// Spec section 9 rule 4 supplies `cmp` for the single-scalar shapes. There is
// nothing to call, so it is emitted inline. The language has no bool-to-integer
// cast, so the three results come from branches into one slot. The caller owns the
// slot and reads it; every path through here stores, and the builder is left on a
// fresh block.
fn emit_scalar_cmp(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let boolean = check.make_type(.Bool, "bool", ty.module_index)
    let (ordered_left, left_coerce_error) = coerce_ordering_operand(c, ty, left, builder, token)
    if left_coerce_error != ok { ret left_coerce_error }
    let (ordered_right, right_coerce_error) = coerce_ordering_operand(c, ty, right, builder, token)
    if right_coerce_error != ok { ret right_coerce_error }
    let (less, less_error) = emit_supplied_compare(builder, .Less, boolean, ordered_left, ordered_right, token)
    if less_error != ok { ret less_error }
    let (less_decision, less_decision_ignored, less_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if less_decision_error != ok { ret less_decision_error }
    let less_decision_operand_error = nir.add_operand(builder, less_decision, less)
    if less_decision_operand_error != ok { ret less_decision_operand_error }

    let below_block = builder.block_count
    let (below_index, below_error) = nir.begin_block(builder)
    if below_error != ok || below_index != below_block { ret nir.InvalidControlFlow }
    let (below_exit, below_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 1usize, true, token)
    if below_exit_error != ok { ret below_exit_error }

    let rest_block = builder.block_count
    let (rest_index, rest_error) = nir.begin_block(builder)
    if rest_error != ok || rest_index != rest_block { ret nir.InvalidControlFlow }
    let (greater, greater_error) = emit_supplied_compare(builder, .Greater, boolean, ordered_left, ordered_right, token)
    if greater_error != ok { ret greater_error }
    let (greater_decision, greater_decision_ignored, greater_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if greater_decision_error != ok { ret greater_decision_error }
    let greater_decision_operand_error = nir.add_operand(builder, greater_decision, greater)
    if greater_decision_operand_error != ok { ret greater_decision_operand_error }

    let above_block = builder.block_count
    let (above_index, above_error) = nir.begin_block(builder)
    if above_error != ok || above_index != above_block { ret nir.InvalidControlFlow }
    let (above_exit, above_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 1usize, false, token)
    if above_exit_error != ok { ret above_exit_error }

    let same_block = builder.block_count
    let (same_index, same_error) = nir.begin_block(builder)
    if same_error != ok || same_index != same_block { ret nir.InvalidControlFlow }
    let (same_exit, same_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 0usize, false, token)
    if same_exit_error != ok { ret same_exit_error }

    let merge_block = builder.block_count
    let (merge_index, merge_error) = nir.begin_block(builder)
    if merge_error != ok || merge_index != merge_block { ret nir.InvalidControlFlow }
    let less_target_error = nir.set_branch_targets(builder, less_decision, below_block, rest_block)
    if less_target_error != ok { ret less_target_error }
    let greater_target_error = nir.set_branch_targets(builder, greater_decision, above_block, same_block)
    if greater_target_error != ok { ret greater_target_error }
    let below_target_error = nir.set_branch_targets(builder, below_exit, merge_block, 0usize)
    if below_target_error != ok { ret below_target_error }
    let above_target_error = nir.set_branch_targets(builder, above_exit, merge_block, 0usize)
    if above_target_error != ok { ret above_target_error }
    ret nir.set_branch_targets(builder, same_exit, merge_block, 0usize)
}

// Rule 4 again: arrays, slices and `str` recurse in index order. The common prefix
// decides where it differs; where it does not, the shorter sequence orders first,
// which for two arrays of one type is the equal-length case and stores zero.
fn emit_sequence_cmp(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let (element_type, element_type_error) = check.index_element_type(c, ty, ty.module_index)
    if element_type_error != ok { ret element_type_error }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret element_info_error }
    let usize_type = check.make_type(.Integer, "usize", ty.module_index)
    let boolean = check.make_type(.Bool, "bool", ty.module_index)
    let (left_data, left_length, left_parts_error) = sequence_parts(c, ty, left, builder, token)
    if left_parts_error != ok { ret left_parts_error }
    let (right_data, right_length, right_parts_error) = sequence_parts(c, ty, right, builder, token)
    if right_parts_error != ok { ret right_parts_error }
    let (element_slot_instruction, element_slot, element_slot_error) = nir.emit(builder, .Stack, result_type, true, 0usize, token)
    if element_slot_error != ok { ret element_slot_error }
    let (counter_slot_instruction, counter_slot, counter_slot_error) = nir.emit(builder, .Stack, usize_type, true, 0usize, token)
    if counter_slot_error != ok { ret counter_slot_error }
    let (start_instruction, start, start_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if start_error != ok { ret start_error }
    let (start_store_instruction, start_store_ignored, start_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if start_store_error != ok { ret start_store_error }
    try nir.add_operand(builder, start_store_instruction, counter_slot)
    try nir.add_operand(builder, start_store_instruction, start)
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }

    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_slot)
    let (has_left, has_left_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, left_length, token)
    if has_left_error != ok { ret has_left_error }
    let (has_right, has_right_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, right_length, token)
    if has_right_error != ok { ret has_right_error }
    let (both_instruction, has_next, both_error) = nir.emit(builder, .BitAnd, boolean, true, 0usize, token)
    if both_error != ok { ret both_error }
    try nir.add_operand(builder, both_instruction, has_left)
    try nir.add_operand(builder, both_instruction, has_right)
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)

    let increment_block = builder.block_count
    let (increment_index, increment_error) = nir.begin_block(builder)
    if increment_error != ok || increment_index != increment_block { ret nir.InvalidControlFlow }
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_slot)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, usize_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, usize_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_slot)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)

    let body_block = builder.block_count
    let (body_index, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
    let (body_load_instruction, body_counter, body_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if body_load_error != ok { ret body_load_error }
    try nir.add_operand(builder, body_load_instruction, counter_slot)
    let (left_element, left_element_error) = element_operand(c, element_type, element_info.size, left_data, body_counter, left_length, builder, token)
    if left_element_error != ok { ret left_element_error }
    let (right_element, right_element_error) = element_operand(c, element_type, element_info.size, right_data, body_counter, right_length, builder, token)
    if right_element_error != ok { ret right_element_error }
    let element_error = emit_cmp_into(c, element_type, element_slot, result_type, left_element, right_element, builder, token, depth + 1usize)
    if element_error != ok { ret element_error }
    let (element_load_instruction, element_result, element_load_error) = nir.emit(builder, .Load, result_type, true, 0usize, token)
    if element_load_error != ok { ret element_load_error }
    try nir.add_operand(builder, element_load_instruction, element_slot)
    let (element_zero_instruction, element_zero, element_zero_error) = nir.emit(builder, .ConstInteger, result_type, true, 0usize, token)
    if element_zero_error != ok { ret element_zero_error }
    let (differs, differs_error) = emit_supplied_compare(builder, .NotEqual, boolean, element_result, element_zero, token)
    if differs_error != ok { ret differs_error }
    let (element_decision, element_decision_ignored, element_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if element_decision_error != ok { ret element_decision_error }
    try nir.add_operand(builder, element_decision, differs)

    let carry_block = builder.block_count
    let (carry_index, carry_error) = nir.begin_block(builder)
    if carry_error != ok || carry_index != carry_block { ret nir.InvalidControlFlow }
    let (carry_result_instruction, carry_result_ignored, carry_result_error) = nir.emit(builder, .Store, result_type, false, 0usize, token)
    if carry_result_error != ok { ret carry_result_error }
    try nir.add_operand(builder, carry_result_instruction, slot)
    try nir.add_operand(builder, carry_result_instruction, element_result)
    let (carry_exit, carry_exit_error) = emit_branch(builder, token)
    if carry_exit_error != ok { ret carry_exit_error }

    // The common prefix matched, so the shorter sequence orders first. Two arrays
    // of one type reach this with equal lengths and store zero.
    let tail_block = builder.block_count
    let (tail_index, tail_error) = nir.begin_block(builder)
    if tail_error != ok || tail_index != tail_block { ret nir.InvalidControlFlow }
    let length_error = emit_scalar_cmp(c, usize_type, slot, result_type, left_length, right_length, builder, token)
    if length_error != ok { ret length_error }
    let (tail_exit, tail_exit_error) = emit_branch(builder, token)
    if tail_exit_error != ok { ret tail_exit_error }

    let done_block = builder.block_count
    let (done_index, done_error) = nir.begin_block(builder)
    if done_error != ok || done_index != done_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, tail_block)
    try nir.set_branch_targets(builder, element_decision, carry_block, increment_block)
    try nir.set_branch_targets(builder, carry_exit, done_block, 0usize)
    ret nir.set_branch_targets(builder, tail_exit, done_block, 0usize)
}

// An element reaches its comparison the way the rest of lowering passes one: an
// aggregate by address, everything else loaded.
fn element_operand(c: *check.Checker, element_type: check.Type, stride: usize, data: usize, index: usize, limit: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (address_instruction, address, address_error) = nir.emit(builder, .IndexAddress, element_type, true, stride, token)
    if address_error != ok { ret (0usize, address_error) }
    let data_operand_error = nir.add_operand(builder, address_instruction, data)
    if data_operand_error != ok { ret (0usize, data_operand_error) }
    let index_operand_error = nir.add_operand(builder, address_instruction, index)
    if index_operand_error != ok { ret (0usize, index_operand_error) }
    let limit_operand_error = nir.add_operand(builder, address_instruction, limit)
    if limit_operand_error != ok { ret (0usize, limit_operand_error) }
    if aggregate_value(c, element_type) { ret (address, ok) }
    let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, element_type, true, stride, token)
    if load_error != ok { ret (0usize, load_error) }
    let load_operand_error = nir.add_operand(builder, load_instruction, address)
    if load_operand_error != ok { ret (0usize, load_operand_error) }
    ret (loaded, ok)
}

fn emit_cmp_into(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if ty.kind == .Array || ty.kind == .Slice || ty.kind == .String {
        ret emit_sequence_cmp(c, ty, slot, result_type, left, right, builder, token, depth)
    }
    ret emit_scalar_cmp(c, ty, slot, result_type, left, right, builder, token)
}

fn emit_supplied_cmp(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if argument_count != 2usize { ret check.ArgumentCount }
    let result_type = check.make_type(.Integer, "i32", call.protocol_type.module_index)
    let (slot_instruction, slot, slot_error) = nir.emit(builder, .Stack, result_type, true, 0usize, token)
    if slot_error != ok { ret slot_error }
    let cmp_error = emit_cmp_into(c, call.protocol_type, slot, result_type, arguments[0usize], arguments[1usize], builder, token, 0usize)
    if cmp_error != ok { ret cmp_error }
    let (load_instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, 0usize, token)
    if load_error != ok { ret load_error }
    let load_operand_error = nir.add_operand(builder, load_instruction, slot)
    if load_operand_error != ok { ret load_operand_error }
    results.call = call
    results.count = 1usize
    results.values[0usize] = result
    results.addresses[0usize] = false
    ret ok
}

fn emit_call_results(c: *check.Checker, call: check.CallInfo, callee: usize, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if call.protocol_builtin == .Cmp { ret emit_supplied_cmp(c, call, arguments, argument_count, builder, token, results) }
    results.call = call
    results.count = call.function.return_count
    var return_layout: ReturnLayout = zero
    let return_layout_error = call_return_layout(c, call, &return_layout)
    if return_layout_error != ok { ret return_layout_error }
    var symbol = call.function.name
    var symbol_instance = call.function.instance_id
    if call.mem_alloc {
        symbol = "neper_mem_alloc"
        symbol_instance = 0usize
    } else {
        if call.function.intrinsic {
            let (mapped_symbol, mapped_error) = intrinsic_symbol(symbol)
            if mapped_error != ok { ret mapped_error }
            symbol = mapped_symbol
            symbol_instance = 0usize
        }
    }
    var function_ref = 0usize
    if !call.indirect {
        let (interned, function_ref_error) = nir.intern_function(builder, call.function.owner_module_index, symbol, symbol_instance)
        if function_ref_error != ok { ret function_ref_error }
        function_ref = interned
    }
    var slot = 0usize
    if return_layout.via_slot && results.count != 0usize {
        var slots = (return_layout.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let slot_type = check.make_type(.Other, "return-slot", call.function.module_index)
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, slot_type, true, slots, token)
        if stack_error != ok { ret stack_error }
        slot = stack
    }
    var allocation_size = 0usize
    var allocation_alignment = 0usize
    if call.mem_alloc {
        if !call.alloc_return.has_element || call.alloc_return.element >= c.type_count { ret check.InvalidType }
        let (element_info, element_info_error) = layout.type_info(c, c.types[call.alloc_return.element])
        if element_info_error != ok { ret element_info_error }
        let usize_type = check.make_type(.Integer, "usize", call.function.module_index)
        let (size_instruction, size_value, size_error) = nir.emit(builder, .ConstInteger, usize_type, true, element_info.size, token)
        if size_error != ok { ret size_error }
        let (alignment_instruction, alignment_value, alignment_error) = nir.emit(builder, .ConstInteger, usize_type, true, element_info.alignment, token)
        if alignment_error != ok { ret alignment_error }
        allocation_size = size_value
        allocation_alignment = alignment_value
    }
    var call_type: check.Type = zero
    var call_has_result = false
    if !return_layout.via_slot && results.count != 0usize {
        call_has_result = true
        if results.count == 1usize {
            let (single_type, single_type_error) = check.call_return(c, call, 0usize)
            if single_type_error != ok { ret single_type_error }
            call_type = single_type
        } else {
            call_type = check.make_type(.Other, "return-values", call.function.module_index)
        }
    }
    var call_opcode: nir.Opcode = .Call
    if call.indirect { call_opcode = .IndirectCall }
    let (instruction, call_result, emit_error) = nir.emit(builder, call_opcode, call_type, call_has_result, function_ref, token)
    if emit_error != ok { ret emit_error }
    if call.indirect {
        let callee_operand_error = nir.add_operand(builder, instruction, callee)
        if callee_operand_error != ok { ret callee_operand_error }
    }
    if return_layout.via_slot && results.count != 0usize {
        let slot_operand_error = nir.add_operand(builder, instruction, slot)
        if slot_operand_error != ok { ret slot_operand_error }
    }
    var argument_at = 0usize
    while argument_at < argument_count {
        let argument_operand_error = nir.add_operand(builder, instruction, arguments[argument_at])
        if argument_operand_error != ok { ret argument_operand_error }
        argument_at += 1usize
    }
    if call.mem_alloc {
        let size_operand_error = nir.add_operand(builder, instruction, allocation_size)
        if size_operand_error != ok { ret size_operand_error }
        let alignment_operand_error = nir.add_operand(builder, instruction, allocation_alignment)
        if alignment_operand_error != ok { ret alignment_operand_error }
    }
    if results.count == 0usize { ret ok }
    if !return_layout.via_slot {
        if results.count == 1usize {
            results.values[0usize] = call_result
            ret ok
        }
        var result_at = 0usize
        while result_at < results.count {
            let (result_type, result_type_error) = check.call_return(c, call, result_at)
            if result_type_error != ok { ret result_type_error }
            let (extract_instruction, extracted, extract_error) = nir.emit(builder, .Extract, result_type, true, result_at, token)
            if extract_error != ok { ret extract_error }
            let extract_operand_error = nir.add_operand(builder, extract_instruction, call_result)
            if extract_operand_error != ok { ret extract_operand_error }
            results.values[result_at] = extracted
            result_at += 1usize
        }
        ret ok
    }
    var result_at = 0usize
    while result_at < results.count {
        let (result_type, result_type_error) = check.call_return(c, call, result_at)
        if result_type_error != ok { ret result_type_error }
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, result_type, true, return_layout.offsets[result_at], token)
        if address_error != ok { ret address_error }
        let address_operand_error = nir.add_operand(builder, address_instruction, slot)
        if address_operand_error != ok { ret address_operand_error }
        if aggregate_value(c, result_type) {
            results.values[result_at] = address
            results.addresses[result_at] = true
        } else {
            let (info, info_error) = layout.type_info(c, result_type)
            if info_error != ok { ret info_error }
            let (load_instruction, value, load_error) = nir.emit(builder, .Load, result_type, true, info.size, token)
            if load_error != ok { ret load_error }
            let load_operand_error = nir.add_operand(builder, load_instruction, address)
            if load_operand_error != ok { ret load_operand_error }
            results.values[result_at] = value
        }
        result_at += 1usize
    }
    ret ok
}

fn lower_call_arguments(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, captured: bool, call_out: *check.CallInfo, callee_out: *usize, arguments: []usize, argument_count: *usize) -> err {
    let (call, call_error) = check.check_call(c, g, tree, module_index, node)
    if call_error != ok { ret call_error }
    if call.is_cast || call.function.generic { ret check.Unsupported }
    *call_out = call
    *callee_out = 0usize
    *argument_count = 0usize
    let end = node.first_child + node.child_count
    var child_position = 0usize
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if child_position == 0usize && call.indirect {
                let (callee_value, callee_type, callee_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, call.indirect_type, builder, bindings, binding_count)
                if callee_error != ok { ret callee_error }
                *callee_out = callee_value
            }
            if child_position > 0usize {
                if *argument_count == arguments.len || *argument_count >= call.function.parameter_count { ret check.ArgumentCount }
                let (parameter_type, parameter_type_error) = call_parameter_type(c, call, *argument_count)
                if parameter_type_error != ok { ret parameter_type_error }
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, parameter_type, builder, bindings, binding_count)
                if value_error != ok { ret value_error }
                var argument = value
                if captured && aggregate_value(c, parameter_type) {
                    let (info, info_error) = layout.type_info(c, parameter_type)
                    if info_error != ok { ret info_error }
                    var slots = (info.size + 7usize) / 8usize
                    if slots == 0usize { slots = 1usize }
                    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, parameter_type, true, slots, c.tokens[node.token_start])
                    if stack_error != ok { ret stack_error }
                    let (copy_instruction, ignored, copy_error) = nir.emit(builder, .Copy, parameter_type, false, info.size, c.tokens[node.token_start])
                    if copy_error != ok { ret copy_error }
                    try nir.add_operand(builder, copy_instruction, stack)
                    try nir.add_operand(builder, copy_instruction, value)
                    argument = stack
                }
                arguments[*argument_count] = argument
                *argument_count += 1usize
            }
            child_position += 1usize
        }
        at += 1usize
    }
    if *argument_count != call.function.parameter_count { ret check.ArgumentCount }
    ret ok
}

fn lower_call_results(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, results: *CallResults) -> err {
    var call: check.CallInfo = zero
    var arguments: [16]usize = zero
    var argument_count = 0usize
    var callee = 0usize
    let arguments_error = lower_call_arguments(c, g, tree, module_index, node, builder, bindings, binding_count, false, &call, &callee, arguments[..], &argument_count)
    if arguments_error != ok { ret arguments_error }
    ret emit_call_results(c, call, callee, arguments[..], argument_count, builder, c.tokens[node.token_start], results)
}

fn lower_call(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (check.CallInfo, usize, err) {
    var empty: check.CallInfo = zero
    var results: CallResults = zero
    let call_error = lower_call_results(c, g, tree, module_index, node, builder, bindings, binding_count, &results)
    if call_error != ok { ret (empty, 0usize, call_error) }
    if results.count != 1usize { ret (results.call, 0usize, check.ArgumentCount) }
    ret (results.call, results.values[0usize], ok)
}

fn binary_opcode(kind: lex.Kind) -> nir.Opcode {
    if kind == .PunctPlus { ret .Add }
    if kind == .PunctMinus { ret .Subtract }
    if kind == .PunctStar { ret .Multiply }
    if kind == .PunctSlash { ret .Divide }
    if kind == .PunctPercent { ret .Remainder }
    if kind == .PunctAddWrap { ret .AddWrap }
    if kind == .PunctSubWrap { ret .SubtractWrap }
    if kind == .PunctMulWrap { ret .MultiplyWrap }
    if kind == .PunctShiftLeft { ret .ShiftLeft }
    if kind == .PunctShiftRight { ret .ShiftRight }
    if kind == .PunctAmp { ret .BitAnd }
    if kind == .PunctCaret { ret .BitXor }
    if kind == .PunctPipe { ret .BitOr }
    if kind == .PunctEqEq { ret .Equal }
    if kind == .PunctBangEq { ret .NotEqual }
    if kind == .PunctLt { ret .Less }
    if kind == .PunctLtEq { ret .LessEqual }
    if kind == .PunctGt { ret .Greater }
    if kind == .PunctGtEq { ret .GreaterEqual }
    ret .Invalid
}

fn compound_opcode(kind: lex.Kind) -> nir.Opcode {
    if kind == .PunctAddAssign { ret .Add }
    if kind == .PunctSubAssign { ret .Subtract }
    if kind == .PunctMulAssign { ret .Multiply }
    if kind == .PunctDivAssign { ret .Divide }
    if kind == .PunctRemAssign { ret .Remainder }
    if kind == .PunctAddWrapAssign { ret .AddWrap }
    if kind == .PunctSubWrapAssign { ret .SubtractWrap }
    if kind == .PunctMulWrapAssign { ret .MultiplyWrap }
    if kind == .PunctShiftLeftAssign { ret .ShiftLeft }
    if kind == .PunctShiftRightAssign { ret .ShiftRight }
    if kind == .PunctBitAndAssign { ret .BitAnd }
    if kind == .PunctBitXorAssign { ret .BitXor }
    if kind == .PunctBitOrAssign { ret .BitOr }
    ret .Invalid
}

fn aggregate_value(c: *check.Checker, ty: check.Type) -> bool {
    if ty.kind == .Array || ty.kind == .Slice || ty.kind == .String { ret true }
    let (index, found) = layout.aggregate_index(c, ty)
    if !found { ret false }
    ret c.aggregates[index].kind != .Enum && ty.kind != .Tag
}

fn lower_slice(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    var bracket: check.BracketInfo = zero
    let bracket_error = check.read_bracket(c, tree, node, &bracket)
    if bracket_error != ok || !bracket.range { ret (0usize, zero, check.Unsupported) }
    let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, bracket.base, check.invalid_type())
    if base_type_error != ok { ret (0usize, base_type, base_type_error) }
    if base_type.kind != .Array && base_type.kind != .Slice && base_type.kind != .String { ret (0usize, base_type, check.Unsupported) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (element_type, element_type_error) = check.index_element_type(c, base_type, module_index)
    if element_type_error != ok { ret (0usize, result_type, element_type_error) }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret (0usize, result_type, element_info_error) }
    let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, bracket.base, base_type, builder, bindings, binding_count)
    if base_error != ok { ret (0usize, lowered_base_type, base_error) }
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let length_type = check.make_type(.Integer, "usize", module_index)
    var data = base
    var length = 0usize
    if base_type.kind == .Array {
        let (length_instruction, length_value, length_error) = nir.emit(builder, .ConstInteger, length_type, true, base_type.array_length, c.tokens[node.token_start])
        if length_error != ok { ret (0usize, result_type, length_error) }
        length = length_value
    } else {
        let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, c.tokens[node.token_start])
        if data_address_error != ok { ret (0usize, result_type, data_address_error) }
        let data_address_operand_error = nir.add_operand(builder, data_address_instruction, base)
        if data_address_operand_error != ok { ret (0usize, result_type, data_address_operand_error) }
        let (data_load_instruction, data_value, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, c.tokens[node.token_start])
        if data_load_error != ok { ret (0usize, result_type, data_load_error) }
        let data_load_operand_error = nir.add_operand(builder, data_load_instruction, data_address)
        if data_load_operand_error != ok { ret (0usize, result_type, data_load_operand_error) }
        data = data_value
        let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, length_type, true, 8usize, c.tokens[node.token_start])
        if length_address_error != ok { ret (0usize, result_type, length_address_error) }
        let length_address_operand_error = nir.add_operand(builder, length_address_instruction, base)
        if length_address_operand_error != ok { ret (0usize, result_type, length_address_operand_error) }
        let (length_load_instruction, length_value, length_load_error) = nir.emit(builder, .Load, length_type, true, 8usize, c.tokens[node.token_start])
        if length_load_error != ok { ret (0usize, result_type, length_load_error) }
        let length_load_operand_error = nir.add_operand(builder, length_load_instruction, length_address)
        if length_load_operand_error != ok { ret (0usize, result_type, length_load_operand_error) }
        length = length_value
    }
    let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, length_type, true, 0usize, c.tokens[node.token_start])
    if zero_error != ok { ret (0usize, result_type, zero_error) }
    var lower = zero_value
    var upper = length
    if bracket.child_count == 3usize {
        let (lower_value, lower_type, lower_error) = lower_expression(c, g, tree, module_index, bracket.first, length_type, builder, bindings, binding_count)
        if lower_error != ok { ret (0usize, result_type, lower_error) }
        lower = lower_value
        let (upper_value, upper_type, upper_error) = lower_expression(c, g, tree, module_index, bracket.second, length_type, builder, bindings, binding_count)
        if upper_error != ok { ret (0usize, result_type, upper_error) }
        upper = upper_value
    } else {
        if bracket.child_count == 2usize {
            var range_at = tree.nodes[bracket.base].token_end
            while range_at < node.token_end && c.tokens[range_at].kind != .PunctRange { range_at += 1usize }
            if range_at >= node.token_end { ret (0usize, result_type, parse.InvalidSyntax) }
            let (bound, bound_type, bound_error) = lower_expression(c, g, tree, module_index, bracket.first, length_type, builder, bindings, binding_count)
            if bound_error != ok { ret (0usize, result_type, bound_error) }
            if tree.nodes[bracket.first].token_start < range_at { lower = bound } else { upper = bound }
        }
    }
    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, result_type, true, 2usize, c.tokens[node.token_start])
    if stack_error != ok { ret (0usize, result_type, stack_error) }
    let (slice_instruction, slice_ignored, slice_error) = nir.emit(builder, .Slice, result_type, false, element_info.size, c.tokens[node.token_start])
    if slice_error != ok { ret (0usize, result_type, slice_error) }
    let destination_error = nir.add_operand(builder, slice_instruction, stack)
    if destination_error != ok { ret (0usize, result_type, destination_error) }
    let data_error = nir.add_operand(builder, slice_instruction, data)
    if data_error != ok { ret (0usize, result_type, data_error) }
    let source_length_error = nir.add_operand(builder, slice_instruction, length)
    if source_length_error != ok { ret (0usize, result_type, source_length_error) }
    let lower_error = nir.add_operand(builder, slice_instruction, lower)
    if lower_error != ok { ret (0usize, result_type, lower_error) }
    let upper_error = nir.add_operand(builder, slice_instruction, upper)
    if upper_error != ok { ret (0usize, result_type, upper_error) }
    ret (stack, result_type, ok)
}

fn lower_index_address(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    var children: [2]usize = zero
    var child_count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if child_count == children.len { ret (0usize, zero, check.Unsupported) }
            children[child_count] = tree.children[at].index
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count != 2usize { ret (0usize, zero, parse.InvalidSyntax) }
    let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, children[0usize], check.invalid_type())
    if base_type_error != ok { ret (0usize, base_type, base_type_error) }
    let (element_type, element_type_error) = check.index_element_type(c, base_type, module_index)
    if element_type_error != ok { ret (0usize, element_type, element_type_error) }
    let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, children[0usize], base_type, builder, bindings, binding_count)
    if base_error != ok { ret (0usize, lowered_base_type, base_error) }
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let (index, index_type, index_error) = lower_expression(c, g, tree, module_index, children[1usize], usize_type, builder, bindings, binding_count)
    if index_error != ok { ret (0usize, index_type, index_error) }
    var data = base
    var length = 0usize
    if base_type.kind == .Array {
        let (length_instruction, length_result, length_error) = nir.emit(builder, .ConstInteger, usize_type, true, base_type.array_length, c.tokens[node.token_start])
        if length_error != ok { ret (0usize, element_type, length_error) }
        length = length_result
    } else {
        if base_type.kind != .Slice && base_type.kind != .String { ret (0usize, element_type, check.Unsupported) }
        let pointer_type = check.make_type(.Pointer, "", module_index)
        let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, c.tokens[node.token_start])
        if data_address_error != ok { ret (0usize, element_type, data_address_error) }
        let data_address_operand_error = nir.add_operand(builder, data_address_instruction, base)
        if data_address_operand_error != ok { ret (0usize, element_type, data_address_operand_error) }
        let (data_load, data_result, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, c.tokens[node.token_start])
        if data_load_error != ok { ret (0usize, element_type, data_load_error) }
        let data_load_operand_error = nir.add_operand(builder, data_load, data_address)
        if data_load_operand_error != ok { ret (0usize, element_type, data_load_operand_error) }
        data = data_result
        let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, c.tokens[node.token_start])
        if length_address_error != ok { ret (0usize, element_type, length_address_error) }
        let length_address_operand_error = nir.add_operand(builder, length_address_instruction, base)
        if length_address_operand_error != ok { ret (0usize, element_type, length_address_operand_error) }
        let (length_load, length_result, length_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, c.tokens[node.token_start])
        if length_load_error != ok { ret (0usize, element_type, length_load_error) }
        let length_load_operand_error = nir.add_operand(builder, length_load, length_address)
        if length_load_operand_error != ok { ret (0usize, element_type, length_load_operand_error) }
        length = length_result
    }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret (0usize, element_type, element_info_error) }
    let (address_instruction, address, address_error) = nir.emit(builder, .IndexAddress, element_type, true, element_info.size, c.tokens[node.token_start])
    if address_error != ok { ret (0usize, element_type, address_error) }
    let data_operand_error = nir.add_operand(builder, address_instruction, data)
    if data_operand_error != ok { ret (0usize, element_type, data_operand_error) }
    let index_operand_error = nir.add_operand(builder, address_instruction, index)
    if index_operand_error != ok { ret (0usize, element_type, index_operand_error) }
    let length_operand_error = nir.add_operand(builder, address_instruction, length)
    if length_operand_error != ok { ret (0usize, element_type, length_operand_error) }
    ret (address, element_type, ok)
}

fn lower_index(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (address, element_type, address_error) = lower_index_address(c, g, tree, module_index, node_index, builder, bindings, binding_count)
    if address_error != ok { ret (0usize, element_type, address_error) }
    if aggregate_value(c, element_type) { ret (address, element_type, ok) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret (0usize, result_type, element_info_error) }
    let (load_instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, element_info.size, c.tokens[node.token_start])
    if load_error != ok { ret (0usize, result_type, load_error) }
    let load_operand_error = nir.add_operand(builder, load_instruction, address)
    if load_operand_error != ok { ret (0usize, result_type, load_operand_error) }
    ret (result, result_type, ok)
}

fn lower_place(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (0usize, zero, check.Unsupported) }
        let name = g.modules[module_index].text[token.start..token.end]
        let (binding, found) = find_binding(bindings, binding_count, name)
        if !found || !binding.address { ret (0usize, zero, check.Unsupported) }
        ret (binding.value, binding.ty, ok)
    }
    if node.kind == .BracketPostfix && !check.contains_token(c, node.token_start, node.token_end, .PunctRange) {
        let (address, ty, address_error) = lower_index_address(c, g, tree, module_index, node_index, builder, bindings, binding_count)
        ret (address, ty, address_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, qualified_name, qualified) = check.qualified_member(c, g, tree, module_index, node)
        if qualified { ret (0usize, zero, check.Unsupported) }
        let (base_index, has_base) = check.first_node_child(tree, node)
        if !has_base { ret (0usize, zero, parse.InvalidSyntax) }
        let (field_name, has_field) = check.field_expression_name(c, g.modules[module_index].text, tree, node)
        if !has_field { ret (0usize, zero, parse.InvalidSyntax) }
        let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, base_index, check.invalid_type())
        if base_type_error != ok { ret (0usize, base_type, base_type_error) }
        let (field, field_error) = layout.field(c, base_type, field_name)
        if field_error != ok { ret (0usize, zero, field_error) }
        let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, base_index, base_type, builder, bindings, binding_count)
        if base_error != ok { ret (0usize, lowered_base_type, base_error) }
        let (instruction, address, emit_error) = nir.emit(builder, .FieldAddress, field.ty, true, field.offset, c.tokens[node.token_start])
        if emit_error != ok { ret (0usize, field.ty, emit_error) }
        let operand_error = nir.add_operand(builder, instruction, base)
        if operand_error != ok { ret (0usize, field.ty, operand_error) }
        ret (address, field.ty, ok)
    }
    if node.kind == .UnaryExpr && c.tokens[node.token_start].kind == .PunctStar {
        let (child_index, found_child) = check.first_node_child(tree, node)
        if !found_child { ret (0usize, zero, parse.InvalidSyntax) }
        let (pointer_type, pointer_type_error) = check.check_expr(c, g, tree, module_index, child_index, check.invalid_type())
        if pointer_type_error != ok || pointer_type.kind != .Pointer || !pointer_type.has_element || pointer_type.element >= c.type_count { ret (0usize, pointer_type, check.InvalidType) }
        let (pointer, lowered_pointer_type, pointer_error) = lower_expression(c, g, tree, module_index, child_index, pointer_type, builder, bindings, binding_count)
        if pointer_error != ok { ret (0usize, lowered_pointer_type, pointer_error) }
        ret (pointer, c.types[pointer_type.element], ok)
    }
    ret (0usize, zero, check.Unsupported)
}

fn lower_member(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (aggregate_index, found_aggregate) = layout.aggregate_index(c, result_type)
    if !found_aggregate { ret (0usize, result_type, check.Unsupported) }
    let aggregate = c.aggregates[aggregate_index]
    var member_name = ""
    var token_at = node.token_start
    while token_at < node.token_end {
        let token = c.tokens[token_at]
        if token.kind == .Identifier { member_name = g.modules[module_index].text[token.start..token.end] }
        token_at += 1usize
    }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index < c.aggregate_field_count {
            let member = c.aggregate_fields[field_index]
            if check.same(member.name, member_name) {
                if aggregate.kind == .TaggedUnion && result_type.kind == .Named {
                    let (info, info_error) = layout.type_info(c, result_type)
                    if info_error != ok { ret (0usize, result_type, info_error) }
                    var slots = (info.size + 7usize) / 8usize
                    if slots == 0usize { slots = 1usize }
                    let token = c.tokens[node.token_start]
                    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, result_type, true, slots, token)
                    if stack_error != ok { ret (0usize, result_type, stack_error) }
                    let (zero_instruction, ignored, zero_error) = nir.emit(builder, .Zero, result_type, false, info.size, token)
                    if zero_error != ok { ret (0usize, result_type, zero_error) }
                    let zero_operand_error = nir.add_operand(builder, zero_instruction, stack)
                    if zero_operand_error != ok { ret (0usize, result_type, zero_operand_error) }
                    let tag_error = store_tag(c, aggregate, field_index, stack, token, builder)
                    ret (stack, result_type, tag_error)
                }
                let (member_bits, member_bits_error) = check.enum_member_bits(aggregate.backing_type, member.enum_value, member.enum_negative)
                if member_bits_error != ok { ret (0usize, result_type, member_bits_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, result_type, true, member_bits, c.tokens[node.token_start])
                ret (result, result_type, emit_error)
            }
        }
        field_at += 1usize
    }
    ret (0usize, result_type, check.InvalidType)
}

fn lower_unary(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (child_index, found_child) = check.first_node_child(tree, node)
    if !found_child { ret (0usize, zero, parse.InvalidSyntax) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let operator = c.tokens[node.token_start].kind
    if operator == .PunctAmp {
        let (address, place_type, place_error) = lower_place(c, g, tree, module_index, child_index, builder, bindings, binding_count)
        if place_error != ok { ret (0usize, result_type, place_error) }
        ret (address, result_type, ok)
    }
    var operand_expected = result_type
    if operator == .PunctBang { operand_expected = check.make_type(.Bool, "bool", module_index) }
    if operator == .PunctStar {
        let (pointer_type, pointer_type_error) = check.check_expr(c, g, tree, module_index, child_index, check.invalid_type())
        if pointer_type_error != ok { ret (0usize, result_type, pointer_type_error) }
        operand_expected = pointer_type
    }
    let (operand, operand_type, operand_error) = lower_expression(c, g, tree, module_index, child_index, operand_expected, builder, bindings, binding_count)
    if operand_error != ok { ret (0usize, operand_type, operand_error) }
    if operator == .PunctStar {
        if aggregate_value(c, result_type) { ret (operand, result_type, ok) }
        let (info, info_error) = layout.type_info(c, result_type)
        if info_error != ok { ret (0usize, result_type, info_error) }
        let (instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, info.size, c.tokens[node.token_start])
        if load_error != ok { ret (0usize, result_type, load_error) }
        let add_error = nir.add_operand(builder, instruction, operand)
        if add_error != ok { ret (0usize, result_type, add_error) }
        ret (result, result_type, ok)
    }
    if operator == .PunctBang {
        let (false_instruction, false_value, false_error) = nir.emit(builder, .ConstBool, operand_expected, true, 0usize, c.tokens[node.token_start])
        if false_error != ok { ret (0usize, result_type, false_error) }
        let (instruction, result, emit_error) = nir.emit(builder, .Equal, result_type, true, 0usize, c.tokens[node.token_start])
        if emit_error != ok { ret (0usize, result_type, emit_error) }
        let operand_add_error = nir.add_operand(builder, instruction, operand)
        if operand_add_error != ok { ret (0usize, result_type, operand_add_error) }
        let false_add_error = nir.add_operand(builder, instruction, false_value)
        if false_add_error != ok { ret (0usize, result_type, false_add_error) }
        ret (result, result_type, ok)
    }
    var opcode: nir.Opcode = .Invalid
    if operator == .PunctMinus { opcode = .Negate }
    if operator == .PunctTilde { opcode = .BitNot }
    if opcode == .Invalid { ret (0usize, zero, check.Unsupported) }
    let (instruction, result, emit_error) = nir.emit(builder, opcode, result_type, true, 0usize, c.tokens[node.token_start])
    if emit_error != ok { ret (0usize, result_type, emit_error) }
    let add_error = nir.add_operand(builder, instruction, operand)
    if add_error != ok { ret (0usize, result_type, add_error) }
    ret (result, result_type, ok)
}

fn store_tag(c: *check.Checker, aggregate: check.Aggregate, field_index: usize, destination: usize, token: lex.Token, builder: *nir.Builder) -> err {
    if field_index >= c.aggregate_field_count { ret check.InvalidType }
    let field = c.aggregate_fields[field_index]
    let (tag_bits, tag_bits_error) = check.enum_member_bits(aggregate.backing_type, field.enum_value, field.enum_negative)
    if tag_bits_error != ok { ret tag_bits_error }
    let (tag_info, tag_info_error) = layout.type_info(c, aggregate.backing_type)
    if tag_info_error != ok { ret tag_info_error }
    let (constant_instruction, tag_value, constant_error) = nir.emit(builder, .ConstInteger, aggregate.backing_type, true, tag_bits, token)
    if constant_error != ok { ret constant_error }
    let (address_instruction, tag_address, address_error) = nir.emit(builder, .FieldAddress, aggregate.backing_type, true, 0usize, token)
    if address_error != ok { ret address_error }
    try nir.add_operand(builder, address_instruction, destination)
    let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, aggregate.backing_type, false, tag_info.size, token)
    if store_error != ok { ret store_error }
    try nir.add_operand(builder, store_instruction, tag_address)
    ret nir.add_operand(builder, store_instruction, tag_value)
}

fn lower_aggregate_literal(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (info, info_error) = layout.type_info(c, result_type)
    if info_error != ok { ret (0usize, result_type, info_error) }
    var slots = (info.size + 7usize) / 8usize
    if slots == 0usize { slots = 1usize }
    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, result_type, true, slots, c.tokens[node.token_start])
    if stack_error != ok { ret (0usize, result_type, stack_error) }
    let (aggregate_index, has_aggregate) = layout.aggregate_index(c, result_type)
    var tagged = false
    var aggregate: check.Aggregate = zero
    if has_aggregate {
        aggregate = c.aggregates[aggregate_index]
        tagged = aggregate.kind == .TaggedUnion
    }
    if tagged {
        let (zero_instruction, ignored, zero_error) = nir.emit(builder, .Zero, result_type, false, info.size, c.tokens[node.token_start])
        if zero_error != ok { ret (0usize, result_type, zero_error) }
        let zero_operand_error = nir.add_operand(builder, zero_instruction, stack)
        if zero_operand_error != ok { ret (0usize, result_type, zero_operand_error) }
    }
    var array_element: check.Type = zero
    var array_info: layout.Info = zero
    if result_type.kind == .Array {
        if !result_type.has_element || result_type.element >= c.type_count { ret (0usize, result_type, check.InvalidType) }
        array_element = c.types[result_type.element]
        let (element_info, element_info_error) = layout.type_info(c, array_element)
        if element_info_error != ok { ret (0usize, result_type, element_info_error) }
        array_info = element_info
    }
    var item_at = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let item = tree.nodes[tree.children[at].index]
            if item.kind == .LiteralItem {
                var item_type: check.Type = zero
                var item_offset = 0usize
                if result_type.kind == .Array {
                    if item_at >= result_type.array_length { ret (0usize, result_type, check.ArgumentCount) }
                    item_type = array_element
                    item_offset = item_at * array_info.size
                } else {
                    let (name, has_name) = check.literal_item_name(c, g.modules[module_index].text, item)
                    if !has_name { ret (0usize, result_type, check.Unsupported) }
                    let (field, field_error) = layout.field(c, result_type, name)
                    if field_error != ok { ret (0usize, result_type, field_error) }
                    item_type = field.ty
                    item_offset = field.offset
                    if tagged {
                        let (field_index, found_field) = check.aggregate_field_for_name(c, aggregate, name)
                        if !found_field { ret (0usize, result_type, check.InvalidType) }
                        let tag_error = store_tag(c, aggregate, field_index, stack, c.tokens[item.token_start], builder)
                        if tag_error != ok { ret (0usize, result_type, tag_error) }
                    }
                }
                let (expression_index, has_expression) = check.first_node_child(tree, item)
                if !has_expression { ret (0usize, result_type, check.Unsupported) }
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, expression_index, item_type, builder, bindings, binding_count)
                if value_error != ok { ret (0usize, value_type, value_error) }
                let (item_info, item_info_error) = layout.type_info(c, item_type)
                if item_info_error != ok { ret (0usize, result_type, item_info_error) }
                let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, item_type, true, item_offset, c.tokens[item.token_start])
                if address_error != ok { ret (0usize, result_type, address_error) }
                let address_operand_error = nir.add_operand(builder, address_instruction, stack)
                if address_operand_error != ok { ret (0usize, result_type, address_operand_error) }
                if aggregate_value(c, item_type) {
                    let (copy_instruction, copy_ignored, copy_error) = nir.emit(builder, .Copy, item_type, false, item_info.size, c.tokens[item.token_start])
                    if copy_error != ok { ret (0usize, result_type, copy_error) }
                    let copy_address_error = nir.add_operand(builder, copy_instruction, address)
                    if copy_address_error != ok { ret (0usize, result_type, copy_address_error) }
                    let copy_value_error = nir.add_operand(builder, copy_instruction, value)
                    if copy_value_error != ok { ret (0usize, result_type, copy_value_error) }
                } else {
                    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, item_type, false, item_info.size, c.tokens[item.token_start])
                    if store_error != ok { ret (0usize, result_type, store_error) }
                    let store_address_error = nir.add_operand(builder, store_instruction, address)
                    if store_address_error != ok { ret (0usize, result_type, store_address_error) }
                    let store_value_error = nir.add_operand(builder, store_instruction, value)
                    if store_value_error != ok { ret (0usize, result_type, store_value_error) }
                }
                item_at += 1usize
            }
        }
        at += 1usize
    }
    ret (stack, result_type, ok)
}

fn lower_expression(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    c.failure_module = module_index
    c.failure_token = c.tokens[node.token_start]
    c.failure_has_token = true
    if node.kind == .LiteralExpr {
        let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if type_error != ok { ret (0usize, result_type, type_error) }
        let (value, value_error) = literal(c, g.modules[module_index].text, node, result_type, builder)
        ret (value, result_type, value_error)
    }
    if node.kind == .GroupExpr {
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                let (group_value, group_type, group_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, expected, builder, bindings, binding_count)
                ret (group_value, group_type, group_error)
            }
            at += 1usize
        }
        ret (0usize, zero, parse.InvalidSyntax)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (0usize, zero, check.Unsupported) }
        let name = g.modules[module_index].text[token.start..token.end]
        let (binding, found) = find_binding(bindings, binding_count, name)
        if !found {
            let (parameter_index, has_parameter) = check.active_comptime_parameter(c, name)
            if has_parameter {
                let (argument, has_argument) = check.active_argument(c, parameter_index)
                if !has_argument || argument.kind != .Integer || argument.symbolic { ret (0usize, zero, check.InvalidConstant) }
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, result_type, true, argument.value, token)
                ret (result, result_type, emit_error)
            }
            let (constant_index, has_constant) = check.find_constant(c, module_index, name)
            if has_constant {
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                let (constant, constant_error) = lower_constant(c, constant_index, result_type, token, builder)
                ret (constant, result_type, constant_error)
            }
            let (symbol_index, has_symbol) = resolve.find(c.resolver, module_index, name, .Value)
            let (intrinsic_function, has_intrinsic_function) = check.find_function(c, module_index, name)
            if has_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let error_type = check.make_type(.Err, "err", module_index)
                let (value, value_error) = artifact_hash.qualified_error_value(g.modules[module_index].name, name)
                if value_error != ok { ret (0usize, error_type, value_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstError, error_type, true, value, token)
                ret (result, error_type, emit_error)
            }
            // A function named in a value position becomes a pointer to it.
            if has_intrinsic_function {
                let callee = c.functions[intrinsic_function]
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                if result_type.kind != .Function { ret (0usize, result_type, check.Unsupported) }
                let (function_ref, function_ref_error) = nir.intern_function(builder, callee.owner_module_index, callee.name, callee.instance_id)
                if function_ref_error != ok { ret (0usize, result_type, function_ref_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .FunctionAddress, result_type, true, function_ref, token)
                ret (result, result_type, emit_error)
            }
            ret (0usize, zero, check.Unsupported)
        }
        let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if type_error != ok { ret (0usize, result_type, type_error) }
        if !binding.address { ret (binding.value, result_type, ok) }
        if aggregate_value(c, result_type) { ret (binding.value, result_type, ok) }
        let (info, info_error) = layout.type_info(c, result_type)
        if info_error != ok { ret (0usize, result_type, info_error) }
        let (instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, info.size, token)
        if load_error != ok { ret (0usize, result_type, load_error) }
        let operand_error = nir.add_operand(builder, instruction, binding.value)
        if operand_error != ok { ret (0usize, result_type, operand_error) }
        ret (result, result_type, ok)
    }
    if node.kind == .MemberExpr {
        let (result, result_type, result_error) = lower_member(c, g, tree, module_index, node_index, expected, builder)
        ret (result, result_type, result_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, qualified_name, qualified) = check.qualified_member(c, g, tree, module_index, node)
        if qualified {
            let (constant_index, has_constant) = check.find_constant(c, target_module, qualified_name)
            if has_constant {
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                let (constant, constant_error) = lower_constant(c, constant_index, result_type, c.tokens[node.token_start], builder)
                ret (constant, result_type, constant_error)
            }
            let (symbol_index, has_symbol) = resolve.find(c.resolver, target_module, qualified_name, .Value)
            let (intrinsic_function, has_intrinsic_function) = check.find_function(c, target_module, qualified_name)
            if has_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let error_type = check.make_type(.Err, "err", target_module)
                let (value, value_error) = artifact_hash.qualified_error_value(g.modules[target_module].name, qualified_name)
                if value_error != ok { ret (0usize, error_type, value_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstError, error_type, true, value, c.tokens[node.token_start])
                ret (result, error_type, emit_error)
            }
            if has_intrinsic_function {
                let callee = c.functions[intrinsic_function]
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error == ok && result_type.kind == .Function {
                    let (function_ref, function_ref_error) = nir.intern_function(builder, callee.owner_module_index, callee.name, callee.instance_id)
                    if function_ref_error != ok { ret (0usize, result_type, function_ref_error) }
                    let (instruction, result, emit_error) = nir.emit(builder, .FunctionAddress, result_type, true, function_ref, c.tokens[node.token_start])
                    ret (result, result_type, emit_error)
                }
            }
            let (member_value, member_type, member_error) = lower_member(c, g, tree, module_index, node_index, expected, builder)
            if member_error == ok { ret (member_value, member_type, ok) }
            ret (0usize, zero, check.Unsupported)
        }
        let (base_index, has_base) = check.first_node_child(tree, node)
        if !has_base { ret (0usize, zero, parse.InvalidSyntax) }
        let (field_name, has_field) = check.field_expression_name(c, g.modules[module_index].text, tree, node)
        if !has_field { ret (0usize, zero, parse.InvalidSyntax) }
        let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, base_index, check.invalid_type())
        if base_type_error != ok {
            let (member_value, member_type, member_error) = lower_member(c, g, tree, module_index, node_index, expected, builder)
            ret (member_value, member_type, member_error)
        }
        if check.same(field_name, "len") && (base_type.kind == .String || base_type.kind == .Slice || base_type.kind == .Array) {
            let length_type = check.make_type(.Integer, "usize", module_index)
            if base_type.kind == .Array {
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, length_type, true, base_type.array_length, c.tokens[node.token_start])
                ret (result, length_type, emit_error)
            }
            let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, base_index, base_type, builder, bindings, binding_count)
            if base_error != ok { ret (0usize, lowered_base_type, base_error) }
            let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, length_type, true, 8usize, c.tokens[node.token_start])
            if address_error != ok { ret (0usize, length_type, address_error) }
            let address_operand_error = nir.add_operand(builder, address_instruction, base)
            if address_operand_error != ok { ret (0usize, length_type, address_operand_error) }
            let (load_instruction, result, load_error) = nir.emit(builder, .Load, length_type, true, 8usize, c.tokens[node.token_start])
            if load_error != ok { ret (0usize, length_type, load_error) }
            let load_operand_error = nir.add_operand(builder, load_instruction, address)
            if load_operand_error != ok { ret (0usize, length_type, load_operand_error) }
            ret (result, length_type, ok)
        }
        let (field, field_error) = layout.field(c, base_type, field_name)
        if field_error != ok { ret (0usize, zero, check.Unsupported) }
        let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, base_index, base_type, builder, bindings, binding_count)
        if base_error != ok { ret (0usize, lowered_base_type, base_error) }
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, field.ty, true, field.offset, c.tokens[node.token_start])
        if address_error != ok { ret (0usize, field.ty, address_error) }
        let address_operand_error = nir.add_operand(builder, address_instruction, base)
        if address_operand_error != ok { ret (0usize, field.ty, address_operand_error) }
        if aggregate_value(c, field.ty) { ret (address, field.ty, ok) }
        let (field_info, field_info_error) = layout.type_info(c, field.ty)
        if field_info_error != ok { ret (0usize, field.ty, field_info_error) }
        let (load_instruction, result, load_error) = nir.emit(builder, .Load, field.ty, true, field_info.size, c.tokens[node.token_start])
        if load_error != ok { ret (0usize, field.ty, load_error) }
        let load_operand_error = nir.add_operand(builder, load_instruction, address)
        if load_operand_error != ok { ret (0usize, field.ty, load_operand_error) }
        ret (result, field.ty, ok)
    }
    if node.kind == .AggregateLiteral {
        let (result, result_type, result_error) = lower_aggregate_literal(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (result, result_type, result_error)
    }
    if node.kind == .BracketPostfix && check.contains_token(c, node.token_start, node.token_end, .PunctRange) {
        let (slice, slice_type, slice_error) = lower_slice(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (slice, slice_type, slice_error)
    }
    if node.kind == .BracketPostfix {
        let (result, result_type, result_error) = lower_index(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (result, result_type, result_error)
    }
    if node.kind == .UnaryExpr {
        let (result, result_type, result_error) = lower_unary(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (result, result_type, result_error)
    }
    if node.kind == .CallExpr {
        let (call_info, call_info_error) = check.check_call(c, g, tree, module_index, node)
        if call_info_error != ok { ret (0usize, zero, call_info_error) }
        if call_info.is_cast {
            var argument_index = 0usize
            var child_position = 0usize
            let end = node.first_child + node.child_count
            var at = node.first_child
            while at < end {
                if tree.children[at].node {
                    if child_position == 1usize { argument_index = tree.children[at].index }
                    child_position += 1usize
                }
                at += 1usize
            }
            if child_position != 2usize { ret (0usize, zero, check.ArgumentCount) }
            let (argument_type, argument_type_error) = check.check_expr(c, g, tree, module_index, argument_index, check.invalid_type())
            if argument_type_error != ok { ret (0usize, argument_type, argument_type_error) }
            let (argument, lowered_argument_type, argument_error) = lower_expression(c, g, tree, module_index, argument_index, argument_type, builder, bindings, binding_count)
            if argument_error != ok { ret (0usize, lowered_argument_type, argument_error) }
            let (instruction, result, emit_error) = nir.emit(builder, .Cast, call_info.cast, true, 0usize, c.tokens[node.token_start])
            if emit_error != ok { ret (0usize, call_info.cast, emit_error) }
            let add_error = nir.add_operand(builder, instruction, argument)
            if add_error != ok { ret (0usize, call_info.cast, add_error) }
            ret (result, call_info.cast, ok)
        }
        let (call, value, call_error) = lower_call(c, g, tree, module_index, node, builder, bindings, binding_count)
        if call_error != ok { ret (0usize, zero, call_error) }
        if call.function.return_count != 1usize { ret (0usize, zero, check.ArgumentCount) }
        let (result_type, result_error) = check.call_return(c, call, 0usize)
        ret (value, result_type, result_error)
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var child_count = 0usize
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if child_count == children.len { ret (0usize, zero, parse.InvalidSyntax) }
                children[child_count] = tree.children[at].index
                child_count += 1usize
            }
            at += 1usize
        }
        if child_count != 2usize { ret (0usize, zero, parse.InvalidSyntax) }
        let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if result_type_error != ok { ret (0usize, result_type, result_type_error) }
        let operator = check.binary_operator(c, tree, node)
        if operator == .PunctAndAnd || operator == .PunctOrOr {
            let boolean = check.make_type(.Bool, "bool", module_index)
            let (left, left_type, left_error) = lower_expression(c, g, tree, module_index, children[0usize], boolean, builder, bindings, binding_count)
            if left_error != ok { ret (0usize, left_type, left_error) }
            let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, boolean, true, 0usize, c.tokens[node.token_start])
            if stack_error != ok { ret (0usize, boolean, stack_error) }
            let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[node.token_start])
            if decision_error != ok { ret (0usize, boolean, decision_error) }
            let decision_operand_error = nir.add_operand(builder, decision, left)
            if decision_operand_error != ok { ret (0usize, boolean, decision_operand_error) }

            let right_block = builder.block_count
            let (right_block_index, right_block_error) = nir.begin_block(builder)
            if right_block_error != ok || right_block_index != right_block { ret (0usize, boolean, nir.InvalidControlFlow) }
            let (right, right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], boolean, builder, bindings, binding_count)
            if right_error != ok { ret (0usize, right_type, right_error) }
            let (right_store, right_store_ignored, right_store_error) = nir.emit(builder, .Store, boolean, false, 0usize, c.tokens[node.token_start])
            if right_store_error != ok { ret (0usize, boolean, right_store_error) }
            let right_address_error = nir.add_operand(builder, right_store, stack)
            if right_address_error != ok { ret (0usize, boolean, right_address_error) }
            let right_value_error = nir.add_operand(builder, right_store, right)
            if right_value_error != ok { ret (0usize, boolean, right_value_error) }
            let (right_exit, right_exit_error) = emit_branch(builder, c.tokens[node.token_start])
            if right_exit_error != ok { ret (0usize, boolean, right_exit_error) }

            let short_block = builder.block_count
            let (short_block_index, short_block_error) = nir.begin_block(builder)
            if short_block_error != ok || short_block_index != short_block { ret (0usize, boolean, nir.InvalidControlFlow) }
            var short_immediate = 0usize
            if operator == .PunctOrOr { short_immediate = 1usize }
            let (short_constant_instruction, short_value, short_constant_error) = nir.emit(builder, .ConstBool, boolean, true, short_immediate, c.tokens[node.token_start])
            if short_constant_error != ok { ret (0usize, boolean, short_constant_error) }
            let (short_store, short_store_ignored, short_store_error) = nir.emit(builder, .Store, boolean, false, 0usize, c.tokens[node.token_start])
            if short_store_error != ok { ret (0usize, boolean, short_store_error) }
            let short_address_error = nir.add_operand(builder, short_store, stack)
            if short_address_error != ok { ret (0usize, boolean, short_address_error) }
            let short_value_error = nir.add_operand(builder, short_store, short_value)
            if short_value_error != ok { ret (0usize, boolean, short_value_error) }
            let (short_exit, short_exit_error) = emit_branch(builder, c.tokens[node.token_start])
            if short_exit_error != ok { ret (0usize, boolean, short_exit_error) }

            let merge_block = builder.block_count
            let (merge_block_index, merge_block_error) = nir.begin_block(builder)
            if merge_block_error != ok || merge_block_index != merge_block { ret (0usize, boolean, nir.InvalidControlFlow) }
            if operator == .PunctAndAnd {
                let target_error = nir.set_branch_targets(builder, decision, right_block, short_block)
                if target_error != ok { ret (0usize, boolean, target_error) }
            } else {
                let target_error = nir.set_branch_targets(builder, decision, short_block, right_block)
                if target_error != ok { ret (0usize, boolean, target_error) }
            }
            let right_target_error = nir.set_branch_targets(builder, right_exit, merge_block, 0usize)
            if right_target_error != ok { ret (0usize, boolean, right_target_error) }
            let short_target_error = nir.set_branch_targets(builder, short_exit, merge_block, 0usize)
            if short_target_error != ok { ret (0usize, boolean, short_target_error) }
            let (load_instruction, result, load_error) = nir.emit(builder, .Load, boolean, true, 0usize, c.tokens[node.token_start])
            if load_error != ok { ret (0usize, boolean, load_error) }
            let load_operand_error = nir.add_operand(builder, load_instruction, stack)
            if load_operand_error != ok { ret (0usize, boolean, load_operand_error) }
            ret (result, result_type, ok)
        }
        let opcode = binary_opcode(operator)
        if opcode == .Invalid { ret (0usize, zero, check.InvalidOperator) }
        var operand_expected = result_type
        if check.is_comparison(operator) { operand_expected = check.invalid_type() }
        let (left_type, left_type_error) = check.check_expr(c, g, tree, module_index, children[0usize], operand_expected)
        if left_type_error != ok { ret (0usize, left_type, left_type_error) }
        let (left, lowered_left_type, left_error) = lower_expression(c, g, tree, module_index, children[0usize], left_type, builder, bindings, binding_count)
        if left_error != ok { ret (0usize, lowered_left_type, left_error) }
        var right_expected = left_type
        if operator == .PunctShiftLeft || operator == .PunctShiftRight { right_expected = check.invalid_type() }
        let (right_type, right_type_error) = check.check_expr(c, g, tree, module_index, children[1usize], right_expected)
        if right_type_error != ok { ret (0usize, right_type, right_type_error) }
        let (right, lowered_right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], right_type, builder, bindings, binding_count)
        if right_error != ok { ret (0usize, lowered_right_type, right_error) }
        var left_ordered = left
        var right_ordered = right
        if ordering_opcode(opcode) {
            let (left_operand, left_coerce_error) = coerce_ordering_operand(c, left_type, left, builder, c.tokens[node.token_start])
            if left_coerce_error != ok { ret (0usize, result_type, left_coerce_error) }
            let (right_operand, right_coerce_error) = coerce_ordering_operand(c, right_type, right, builder, c.tokens[node.token_start])
            if right_coerce_error != ok { ret (0usize, result_type, right_coerce_error) }
            left_ordered = left_operand
            right_ordered = right_operand
        }
        let (instruction, result, emit_error) = nir.emit(builder, opcode, result_type, true, 0usize, c.tokens[node.token_start])
        if emit_error != ok { ret (0usize, result_type, emit_error) }
        let left_operand_error = nir.add_operand(builder, instruction, left_ordered)
        if left_operand_error != ok { ret (0usize, result_type, left_operand_error) }
        let right_operand_error = nir.add_operand(builder, instruction, right_ordered)
        if right_operand_error != ok { ret (0usize, result_type, right_operand_error) }
        ret (result, result_type, ok)
    }
    ret (0usize, zero, check.Unsupported)
}

fn lower_try(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState) -> err {
    if function.return_count != 1usize { ret check.Unsupported }
    let end = node.first_child + node.child_count
    var call_index = 0usize
    var found_call = false
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            call_index = tree.children[at].index
            found_call = true
            break
        }
        at += 1usize
    }
    if !found_call { ret parse.InvalidSyntax }
    let call_node = tree.nodes[call_index]
    let (call, call_result, call_error) = lower_call(c, g, tree, module_index, call_node, builder, bindings, binding_count)
    if call_error != ok { ret call_error }
    if call.function.return_count != 1usize || !check.call_is_fallible(c, call) { ret check.InvalidTry }
    let (caller_error_type, caller_type_error) = check.function_return(c, function, 0usize)
    if caller_type_error != ok { ret caller_type_error }
    if caller_error_type.kind != .Err { ret check.InvalidTry }
    let (ok_instruction, ok_value, ok_error) = nir.emit(builder, .ConstError, caller_error_type, true, 0usize, c.tokens[node.token_start])
    if ok_error != ok { ret ok_error }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (compare_instruction, failed, compare_error) = nir.emit(builder, .NotEqual, boolean, true, 0usize, c.tokens[node.token_start])
    if compare_error != ok { ret compare_error }
    try nir.add_operand(builder, compare_instruction, call_result)
    try nir.add_operand(builder, compare_instruction, ok_value)
    let error_block = builder.block_count
    let continue_block = builder.block_count + 1usize
    let (branch_instruction, ignored, branch_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[node.token_start])
    if branch_error != ok { ret branch_error }
    try nir.add_operand(builder, branch_instruction, failed)
    try nir.set_branch_targets(builder, branch_instruction, error_block, continue_block)
    let (error_block_index, error_block_error) = nir.begin_block(builder)
    if error_block_error != ok || error_block_index != error_block { ret nir.InvalidControlFlow }
    try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, binding_count, defers, 0usize)
    let (return_instruction, return_ignored, return_error) = nir.emit(builder, .Return, caller_error_type, false, 0usize, c.tokens[node.token_start])
    if return_error != ok { ret return_error }
    try nir.add_operand(builder, return_instruction, call_result)
    let (continue_block_index, continue_block_error) = nir.begin_block(builder)
    if continue_block_error != ok || continue_block_index != continue_block { ret nir.InvalidControlFlow }
    ret ok
}

fn lower_return(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState) -> err {
    var values: [16]usize = zero
    var count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if count == values.len || count >= function.return_count { ret check.InvalidReturn }
            let (expected, type_error) = check.function_return(c, function, count)
            if type_error != ok { ret type_error }
            let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, expected, builder, bindings, binding_count)
            if value_error != ok { ret value_error }
            values[count] = value
            count += 1usize
        }
        at += 1usize
    }
    if count != function.return_count { ret check.InvalidReturn }
    let (return_slot, has_return_slot) = find_binding(bindings, binding_count, "$return")
    if has_return_slot {
        var call: check.CallInfo = zero
        call.function = function
        var return_layout: ReturnLayout = zero
        let layout_error = call_return_layout(c, call, &return_layout)
        if layout_error != ok || !return_layout.via_slot { ret check.InvalidReturn }
        var result_at = 0usize
        while result_at < count {
            let result_type = c.return_types[function.first_return + result_at]
            let (info, info_error) = layout.type_info(c, result_type)
            if info_error != ok { ret info_error }
            let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, result_type, true, return_layout.offsets[result_at], c.tokens[node.token_start])
            if address_error != ok { ret address_error }
            try nir.add_operand(builder, address_instruction, return_slot.value)
            if aggregate_value(c, result_type) {
                let (copy_instruction, copy_ignored, copy_error) = nir.emit(builder, .Copy, result_type, false, info.size, c.tokens[node.token_start])
                if copy_error != ok { ret copy_error }
                try nir.add_operand(builder, copy_instruction, address)
                try nir.add_operand(builder, copy_instruction, values[result_at])
            } else {
                let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, result_type, false, info.size, c.tokens[node.token_start])
                if store_error != ok { ret store_error }
                try nir.add_operand(builder, store_instruction, address)
                try nir.add_operand(builder, store_instruction, values[result_at])
            }
            result_at += 1usize
        }
        try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, binding_count, defers, 0usize)
        let (instruction, ignored, emit_error) = nir.emit(builder, .Return, zero, false, 0usize, c.tokens[node.token_start])
        ret emit_error
    }
    try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, binding_count, defers, 0usize)
    var return_type: check.Type = zero
    if function.return_count == 1usize { return_type = c.return_types[function.first_return] }
    let (instruction, ignored, emit_error) = nir.emit(builder, .Return, return_type, false, 0usize, c.tokens[node.token_start])
    if emit_error != ok { ret emit_error }
    at = 0usize
    while at < count {
        try nir.add_operand(builder, instruction, values[at])
        at += 1usize
    }
    ret ok
}

fn lower_binding(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    var binding_node: syntax.Node = zero
    var found_binding = false
    var initializer_index = 0usize
    var found_initializer = false
    var declared = check.invalid_type()
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind == .Binding {
                binding_node = child
                found_binding = true
            } else {
                if check.is_type_node(child.kind) {
                    let (resolved, type_error) = check.type_from_node(c, c.resolver, g, tree, module_index, child)
                    if type_error != ok { ret type_error }
                    declared = resolved
                } else {
                    initializer_index = child_index
                    found_initializer = true
                }
            }
        }
        at += 1usize
    }
    if !found_binding { ret check.Unsupported }
    if found_initializer && check.contains_token(c, node.token_start, tree.nodes[initializer_index].token_start, .KwTry) { ret check.Unsupported }
    if c.tokens[binding_node.token_start].kind == .PunctLParen {
        if !found_initializer || tree.nodes[initializer_index].kind != .CallExpr || declared.kind != .Invalid { ret check.ArgumentCount }
        var results: CallResults = zero
        let results_error = lower_call_results(c, g, tree, module_index, tree.nodes[initializer_index], builder, bindings, *binding_count, &results)
        if results_error != ok { ret results_error }
        let mutable = c.tokens[node.token_start].kind == .KwVar
        ret bind_call_results(c, g, module_index, binding_node, &results, mutable, builder, bindings, binding_count)
    }
    let (name, has_name) = check.first_name(c, g.modules[module_index].text, binding_node)
    if !has_name { ret parse.InvalidSyntax }
    let mutable = c.tokens[node.token_start].kind == .KwVar
    var value = 0usize
    var value_type = declared
    var stored_value = 0usize
    var address = false
    if found_initializer {
        let (lowered_value, lowered_type, value_error) = lower_expression(c, g, tree, module_index, initializer_index, declared, builder, bindings, *binding_count)
        if value_error != ok { ret value_error }
        value = lowered_value
        value_type = lowered_type
        stored_value = value
    } else {
        if declared.kind == .Invalid { ret check.MissingContext }
        let is_zero = check.contains_token(c, node.token_start, node.token_end, .KwZero)
        let is_undef = check.contains_token(c, node.token_start, node.token_end, .KwUndef)
        if !is_zero && !is_undef { ret check.Unsupported }
        if aggregate_value(c, declared) {
            let (info, info_error) = layout.type_info(c, declared)
            if info_error != ok { ret info_error }
            var slots = (info.size + 7usize) / 8usize
            if slots == 0usize { slots = 1usize }
            let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, declared, true, slots, c.tokens[node.token_start])
            if stack_error != ok { ret stack_error }
            if is_zero {
                let (zero_instruction, zero_ignored, zero_error) = nir.emit(builder, .Zero, declared, false, info.size, c.tokens[node.token_start])
                if zero_error != ok { ret zero_error }
                try nir.add_operand(builder, zero_instruction, stack)
            }
            value = stack
            stored_value = stack
            address = true
        } else {
            if is_zero {
                let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .Zero, declared, true, 0usize, c.tokens[node.token_start])
                if zero_error != ok { ret zero_error }
                value = zero_value
                stored_value = zero_value
            } else {
                let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, declared, true, 0usize, c.tokens[node.token_start])
                if stack_error != ok { ret stack_error }
                value = stack
                stored_value = stack
                address = true
            }
        }
    }
    if aggregate_value(c, value_type) {
        address = true
    } else {
    if mutable && !address {
        let (info, info_error) = layout.type_info(c, value_type)
        if info_error != ok { ret info_error }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, value_type, true, 0usize, c.tokens[node.token_start])
        if stack_error != ok { ret stack_error }
        let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, value_type, false, info.size, c.tokens[node.token_start])
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, stack)
        try nir.add_operand(builder, store_instruction, value)
        stored_value = stack
        address = true
    }
    }
    ret bind_value(c, g, module_index, c.tokens[binding_node.token_start], value_type, stored_value, address, mutable, builder, bindings, binding_count)
}

fn store_assignment_value(c: *check.Checker, ty: check.Type, address: usize, value: usize, token: lex.Token, builder: *nir.Builder) -> err {
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret info_error }
    if aggregate_value(c, ty) {
        let (instruction, ignored, emit_error) = nir.emit(builder, .Copy, ty, false, info.size, token)
        if emit_error != ok { ret emit_error }
        try nir.add_operand(builder, instruction, address)
        try nir.add_operand(builder, instruction, value)
        ret ok
    }
    let (instruction, ignored, emit_error) = nir.emit(builder, .Store, ty, false, info.size, token)
    if emit_error != ok { ret emit_error }
    try nir.add_operand(builder, instruction, address)
    try nir.add_operand(builder, instruction, value)
    ret ok
}

fn lower_assignment(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
    var children: [17]usize = zero
    var count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if count == children.len { ret parse.InvalidSyntax }
            children[count] = tree.children[at].index
            count += 1usize
        }
        at += 1usize
    }
    if count < 2usize { ret parse.InvalidSyntax }
    if count > 2usize {
        let place_count = count - 1usize
        if place_count > 16usize { ret check.ArgumentCount }
        var addresses: [16]usize = zero
        var place_types: [16]check.Type = zero
        var place_at = 0usize
        while place_at < place_count {
            let (address, place_type, address_error) = lower_place(c, g, tree, module_index, children[place_at], builder, bindings, binding_count)
            if address_error != ok { ret address_error }
            addresses[place_at] = address
            place_types[place_at] = place_type
            place_at += 1usize
        }
        let initializer = tree.nodes[children[place_count]]
        if initializer.kind != .CallExpr { ret check.ArgumentCount }
        var results: CallResults = zero
        let results_error = lower_call_results(c, g, tree, module_index, initializer, builder, bindings, binding_count, &results)
        if results_error != ok { ret results_error }
        if results.count != place_count { ret check.ArgumentCount }
        place_at = 0usize
        while place_at < place_count {
            let (result_type, result_type_error) = check.call_return(c, results.call, place_at)
            if result_type_error != ok { ret result_type_error }
            if !check.type_equal(c, place_types[place_at], result_type) { ret check.InvalidType }
            try store_assignment_value(c, place_types[place_at], addresses[place_at], results.values[place_at], c.tokens[node.token_start], builder)
            place_at += 1usize
        }
        ret ok
    }
    let (address, place_type, address_error) = lower_place(c, g, tree, module_index, children[0usize], builder, bindings, binding_count)
    if address_error != ok { ret address_error }
    let assignment = check.assignment_operator(c, tree.nodes[children[0usize]].token_end, tree.nodes[children[1usize]].token_start)
    if assignment != .PunctAssign {
        let opcode = compound_opcode(assignment)
        if opcode == .Invalid || aggregate_value(c, place_type) { ret check.InvalidOperator }
        let (info, info_error) = layout.type_info(c, place_type)
        if info_error != ok { ret info_error }
        let (load_instruction, current, load_error) = nir.emit(builder, .Load, place_type, true, info.size, c.tokens[node.token_start])
        if load_error != ok { ret load_error }
        try nir.add_operand(builder, load_instruction, address)
        var expected = place_type
        if opcode == .ShiftLeft || opcode == .ShiftRight { expected = check.invalid_type() }
        let (right, right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], expected, builder, bindings, binding_count)
        if right_error != ok { ret right_error }
        if opcode != .ShiftLeft && opcode != .ShiftRight && !check.type_equal(c, place_type, right_type) { ret check.InvalidType }
        let (binary_instruction, value, binary_error) = nir.emit(builder, opcode, place_type, true, 0usize, c.tokens[node.token_start])
        if binary_error != ok { ret binary_error }
        try nir.add_operand(builder, binary_instruction, current)
        try nir.add_operand(builder, binary_instruction, right)
        ret store_assignment_value(c, place_type, address, value, c.tokens[node.token_start], builder)
    }
    let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, children[1usize], place_type, builder, bindings, binding_count)
    if value_error != ok { ret value_error }
    if !check.type_equal(c, place_type, value_type) { ret check.InvalidType }
    ret store_assignment_value(c, place_type, address, value, c.tokens[node.token_start], builder)
}

fn lower_call_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let call_node = tree.nodes[tree.children[at].index]
            var results: CallResults = zero
            let call_error = lower_call_results(c, g, tree, module_index, call_node, builder, bindings, binding_count, &results)
            if call_error != ok { ret call_error }
            if results.count != 0usize { ret check.ArgumentCount }
            ret ok
        }
        at += 1usize
    }
    ret parse.InvalidSyntax
}

fn emit_branch(builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (instruction, ignored, emit_error) = nir.emit(builder, .Branch, zero, false, 0usize, token)
    ret (instruction, emit_error)
}

fn lower_if(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    var condition_index = 0usize
    var found_condition = false
    var branches: [2]usize = zero
    var branch_count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if !found_condition {
                condition_index = child_index
                found_condition = true
            } else {
                if child.kind != .Block || branch_count == branches.len { ret check.Unsupported }
                branches[branch_count] = child_index
                branch_count += 1usize
            }
        }
        at += 1usize
    }
    if !found_condition || branch_count == 0usize { ret parse.InvalidSyntax }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (condition, condition_type, condition_error) = lower_expression(c, g, tree, module_index, condition_index, boolean, builder, bindings, *binding_count)
    if condition_error != ok { ret condition_error }
    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[node.token_start])
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, condition)

    let true_block = builder.block_count
    let (true_index, true_error) = nir.begin_block(builder)
    if true_error != ok || true_index != true_block { ret nir.InvalidControlFlow }
    try lower_block(c, g, tree, module_index, function, tree.nodes[branches[0usize]], builder, bindings, binding_count, control, defers)
    var true_exit = 0usize
    let true_falls_through = !builder.blocks[builder.current_block].terminated
    if true_falls_through {
        let (branch, branch_error) = emit_branch(builder, c.tokens[node.token_start])
        if branch_error != ok { ret branch_error }
        true_exit = branch
    }

    let false_block = builder.block_count
    let (false_index, false_error) = nir.begin_block(builder)
    if false_error != ok || false_index != false_block { ret nir.InvalidControlFlow }
    if branch_count == 2usize { try lower_block(c, g, tree, module_index, function, tree.nodes[branches[1usize]], builder, bindings, binding_count, control, defers) }
    var false_exit = 0usize
    let false_falls_through = !builder.blocks[builder.current_block].terminated
    if false_falls_through {
        let (branch, branch_error) = emit_branch(builder, c.tokens[node.token_start])
        if branch_error != ok { ret branch_error }
        false_exit = branch
    }

    try nir.set_branch_targets(builder, decision, true_block, false_block)
    if true_falls_through || false_falls_through {
        let merge_block = builder.block_count
        let (merge_index, merge_error) = nir.begin_block(builder)
        if merge_error != ok || merge_index != merge_block { ret nir.InvalidControlFlow }
        if true_falls_through { try nir.set_branch_targets(builder, true_exit, merge_block, 0usize) }
        if false_falls_through { try nir.set_branch_targets(builder, false_exit, merge_block, 0usize) }
    }
    ret ok
}

fn lower_while(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    var condition_index = 0usize
    var body_index = 0usize
    var found_condition = false
    var found_body = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if !found_condition {
                condition_index = child_index
                found_condition = true
            } else {
                if found_body || tree.nodes[child_index].kind != .Block { ret check.Unsupported }
                body_index = child_index
                found_body = true
            }
        }
        at += 1usize
    }
    if !found_condition || !found_body { ret parse.InvalidSyntax }
    let (entry_branch, entry_error) = emit_branch(builder, c.tokens[node.token_start])
    if entry_error != ok { ret entry_error }
    let condition_block = builder.block_count
    let (condition_block_index, condition_block_error) = nir.begin_block(builder)
    if condition_block_error != ok || condition_block_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (condition, condition_type, condition_error) = lower_expression(c, g, tree, module_index, condition_index, boolean, builder, bindings, *binding_count)
    if condition_error != ok { ret condition_error }
    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[node.token_start])
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, condition)
    let body_block = builder.block_count
    let (body_block_index, body_block_error) = nir.begin_block(builder)
    if body_block_error != ok || body_block_index != body_block { ret nir.InvalidControlFlow }
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: condition_block, break_defer_base: defers.count, continue_defer_base: defers.count, breaks: break_storage[..], break_count: 0usize }
    try lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
    if !builder.blocks[builder.current_block].terminated {
        let (back_edge, back_edge_error) = emit_branch(builder, c.tokens[node.token_start])
        if back_edge_error != ok { ret back_edge_error }
        try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_block_index, exit_block_error) = nir.begin_block(builder)
    if exit_block_error != ok || exit_block_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    var break_at = 0usize
    while break_at < control.break_count {
        try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
        break_at += 1usize
    }
    let condition_node = tree.nodes[condition_index]
    if control.break_count == 0usize && condition_node.kind == .LiteralExpr && c.tokens[condition_node.token_start].kind == .KwTrue {
        let (unreachable_instruction, unreachable_value, unreachable_error) = nir.emit(builder, .Unreachable, zero, false, 0usize, c.tokens[condition_node.token_start])
        if unreachable_error != ok { ret unreachable_error }
    }
    ret ok
}

fn lower_iterable_parts(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, expression_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: usize, data: *usize, length: *usize, element_type: *check.Type, stride: *usize) -> err {
    let (subject_type, subject_type_error) = check.check_expr(c, g, tree, module_index, expression_index, check.invalid_type())
    if subject_type_error != ok { ret subject_type_error }
    if subject_type.kind != .Array && subject_type.kind != .Slice && subject_type.kind != .String { ret check.Unsupported }
    let (resolved_element, element_error) = check.index_element_type(c, subject_type, module_index)
    if element_error != ok { ret element_error }
    *element_type = resolved_element
    let (element_info, element_info_error) = layout.type_info(c, resolved_element)
    if element_info_error != ok { ret element_info_error }
    *stride = element_info.size
    let (subject, lowered_subject_type, subject_error) = lower_expression(c, g, tree, module_index, expression_index, subject_type, builder, bindings, binding_count)
    if subject_error != ok { ret subject_error }
    *data = subject
    let usize_type = check.make_type(.Integer, "usize", module_index)
    if subject_type.kind == .Array {
        let (length_instruction, length_value, length_error) = nir.emit(builder, .ConstInteger, usize_type, true, subject_type.array_length, c.tokens[tree.nodes[expression_index].token_start])
        if length_error != ok { ret length_error }
        *length = length_value
        ret ok
    }
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let token = c.tokens[tree.nodes[expression_index].token_start]
    let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, token)
    if data_address_error != ok { ret data_address_error }
    try nir.add_operand(builder, data_address_instruction, subject)
    let (data_load_instruction, data_value, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, token)
    if data_load_error != ok { ret data_load_error }
    try nir.add_operand(builder, data_load_instruction, data_address)
    *data = data_value
    let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, token)
    if length_address_error != ok { ret length_address_error }
    try nir.add_operand(builder, length_address_instruction, subject)
    let (length_load_instruction, length_value, length_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if length_load_error != ok { ret length_load_error }
    try nir.add_operand(builder, length_load_instruction, length_address)
    *length = length_value
    ret ok
}

fn protocol_next_function(c: *check.Checker, iterator: check.Type) -> (check.Function, err) {
    var empty: check.Function = zero
    var at = 0usize
    while at < c.signature_function_count {
        let candidate = c.functions[at]
        if candidate.module_index == iterator.module_index && check.iterator_next_name_matches(iterator.name, candidate.name) { ret (candidate, ok) }
        at += 1usize
    }
    ret (empty, check.UnknownCallable)
}

fn lower_protocol_for(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, subject_index: usize, body_index: usize, name: lex.Token, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    let token = c.tokens[node.token_start]
    let (subject_type, subject_type_error) = check.check_expr(c, g, tree, module_index, subject_index, check.invalid_type())
    if subject_type_error != ok { ret subject_type_error }
    var iterator_type = subject_type
    var iterator_pointer = 0usize
    if subject_type.kind == .Pointer {
        if !subject_type.has_element || subject_type.element >= c.type_count { ret check.InvalidType }
        iterator_type = c.types[subject_type.element]
        let (pointer, pointer_type, pointer_error) = lower_expression(c, g, tree, module_index, subject_index, subject_type, builder, bindings, *binding_count)
        if pointer_error != ok { ret pointer_error }
        iterator_pointer = pointer
    } else {
        let (address, place_type, place_error) = lower_place(c, g, tree, module_index, subject_index, builder, bindings, *binding_count)
        if place_error != ok { ret place_error }
        iterator_pointer = address
    }
    let (canonical_iterator, canonical_error) = check.canonical_type(c, iterator_type)
    if canonical_error != ok { ret canonical_error }
    let (next, next_error) = protocol_next_function(c, canonical_iterator)
    if next_error != ok { ret next_error }
    var call: check.CallInfo = zero
    call.function = next
    let (entry_branch, entry_error) = emit_branch(builder, token)
    if entry_error != ok { ret entry_error }
    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    var arguments: [1]usize = zero
    arguments[0usize] = iterator_pointer
    var results: CallResults = zero
    try emit_call_results(c, call, 0usize, arguments[..], 1usize, builder, token, &results)
    if results.count != 2usize { ret check.InvalidType }
    let (element_type, element_type_error) = check.call_return(c, call, 0usize)
    if element_type_error != ok { ret element_type_error }
    let (has_value_type, has_value_type_error) = check.call_return(c, call, 1usize)
    if has_value_type_error != ok || has_value_type.kind != .Bool { ret check.InvalidType }
    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, results.values[1usize])
    let body_block = builder.block_count
    let (body_index_value, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index_value != body_block { ret nir.InvalidControlFlow }
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    try bind_value(c, g, module_index, name, element_type, results.values[0usize], results.addresses[0usize], false, builder, bindings, binding_count)
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: condition_block, break_defer_base: defers.count, continue_defer_base: defers.count, breaks: break_storage[..], break_count: 0usize }
    let lowered_body_error = lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    if lowered_body_error != ok { ret lowered_body_error }
    if !builder.blocks[builder.current_block].terminated {
        let (back_edge, back_edge_error) = emit_branch(builder, token)
        if back_edge_error != ok { ret back_edge_error }
        try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_index, exit_error) = nir.begin_block(builder)
    if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    var break_at = 0usize
    while break_at < control.break_count {
        try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
        break_at += 1usize
    }
    ret ok
}

fn lower_for(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    var names: [2]lex.Token = zero
    var name_count = 0usize
    var token_at = node.token_start + 1usize
    while token_at < node.token_end && c.tokens[token_at].kind != .KwIn {
        let token = c.tokens[token_at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            if name_count == names.len { ret check.ArgumentCount }
            names[name_count] = token
            name_count += 1usize
        }
        token_at += 1usize
    }
    if name_count == 0usize || token_at == node.token_end { ret parse.InvalidSyntax }
    var expressions: [2]usize = zero
    var expression_count = 0usize
    var body_index = 0usize
    var found_body = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind == .Block {
                if found_body { ret parse.InvalidSyntax }
                body_index = child_index
                found_body = true
            } else {
                if expression_count == expressions.len { ret check.ArgumentCount }
                expressions[expression_count] = child_index
                expression_count += 1usize
            }
        }
        at += 1usize
    }
    if !found_body || expression_count == 0usize { ret parse.InvalidSyntax }
    if expression_count == 1usize {
        let (iterable_type, iterable_type_error) = check.check_expr(c, g, tree, module_index, expressions[0usize], check.invalid_type())
        if iterable_type_error != ok { ret iterable_type_error }
        if iterable_type.kind != .Array && iterable_type.kind != .Slice && iterable_type.kind != .String {
            if name_count != 1usize { ret check.ArgumentCount }
            ret lower_protocol_for(c, g, tree, module_index, function, node, expressions[0usize], body_index, names[0usize], builder, bindings, binding_count, defers)
        }
    }
    let token = c.tokens[node.token_start]
    var counter_type = check.make_type(.Integer, "usize", module_index)
    var initial = 0usize
    var limit = 0usize
    var data = 0usize
    var element_type: check.Type = zero
    var stride = 0usize
    var collection = expression_count == 1usize
    if collection {
        if name_count > 2usize { ret check.ArgumentCount }
        try lower_iterable_parts(c, g, tree, module_index, expressions[0usize], builder, bindings, *binding_count, &data, &limit, &element_type, &stride)
        let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, counter_type, true, 0usize, token)
        if zero_error != ok { ret zero_error }
        initial = zero_value
    } else {
        if name_count != 1usize { ret check.ArgumentCount }
        let (first_type, first_type_error) = check.check_expr(c, g, tree, module_index, expressions[0usize], check.invalid_type())
        if first_type_error != ok { ret first_type_error }
        var second_expected = first_type
        if check.is_untyped(first_type) { second_expected = check.invalid_type() }
        let (second_type, second_type_error) = check.check_expr(c, g, tree, module_index, expressions[1usize], second_expected)
        if second_type_error != ok { ret second_type_error }
        counter_type = first_type
        if check.is_untyped(first_type) { counter_type = second_type }
        let (first_value, lowered_first_type, first_error) = lower_expression(c, g, tree, module_index, expressions[0usize], counter_type, builder, bindings, *binding_count)
        if first_error != ok { ret first_error }
        let (second_value, lowered_second_type, second_error) = lower_expression(c, g, tree, module_index, expressions[1usize], counter_type, builder, bindings, *binding_count)
        if second_error != ok { ret second_error }
        initial = first_value
        limit = second_value
    }
    let (counter_stack_instruction, counter_stack, counter_stack_error) = nir.emit(builder, .Stack, counter_type, true, 0usize, token)
    if counter_stack_error != ok { ret counter_stack_error }
    let (counter_info, counter_info_error) = layout.type_info(c, counter_type)
    if counter_info_error != ok { ret counter_info_error }
    let (initial_store_instruction, initial_store_ignored, initial_store_error) = nir.emit(builder, .Store, counter_type, false, counter_info.size, token)
    if initial_store_error != ok { ret initial_store_error }
    try nir.add_operand(builder, initial_store_instruction, counter_stack)
    try nir.add_operand(builder, initial_store_instruction, initial)
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }
    let condition_block = builder.block_count
    let (condition_block_index, condition_block_error) = nir.begin_block(builder)
    if condition_block_error != ok || condition_block_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, counter_type, true, counter_info.size, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_stack)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (compare_instruction, has_next, compare_error) = nir.emit(builder, .Less, boolean, true, 0usize, token)
    if compare_error != ok { ret compare_error }
    try nir.add_operand(builder, compare_instruction, condition_counter)
    try nir.add_operand(builder, compare_instruction, limit)
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)
    let increment_block = builder.block_count
    let (increment_block_index, increment_block_error) = nir.begin_block(builder)
    if increment_block_error != ok || increment_block_index != increment_block { ret nir.InvalidControlFlow }
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, counter_type, true, counter_info.size, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_stack)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, counter_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, counter_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, counter_type, false, counter_info.size, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_stack)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    let body_block = builder.block_count
    let (body_block_index, body_block_error) = nir.begin_block(builder)
    if body_block_error != ok || body_block_index != body_block { ret nir.InvalidControlFlow }
    let (body_counter_instruction, body_counter, body_counter_error) = nir.emit(builder, .Load, counter_type, true, counter_info.size, token)
    if body_counter_error != ok { ret body_counter_error }
    try nir.add_operand(builder, body_counter_instruction, counter_stack)
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    if collection {
        var element_value = 0usize
        let (address_instruction, element_address, address_error) = nir.emit(builder, .IndexAddress, element_type, true, stride, token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, data)
        try nir.add_operand(builder, address_instruction, body_counter)
        try nir.add_operand(builder, address_instruction, limit)
        var element_address_value = aggregate_value(c, element_type)
        element_value = element_address
        if !element_address_value {
            let (element_info, element_info_error) = layout.type_info(c, element_type)
            if element_info_error != ok { ret element_info_error }
            let (load_instruction, loaded_element, load_error) = nir.emit(builder, .Load, element_type, true, element_info.size, token)
            if load_error != ok { ret load_error }
            try nir.add_operand(builder, load_instruction, element_address)
            element_value = loaded_element
        }
        if name_count == 2usize { try bind_value(c, g, module_index, names[0usize], counter_type, body_counter, false, false, builder, bindings, binding_count) }
        try bind_value(c, g, module_index, names[name_count - 1usize], element_type, element_value, element_address_value, false, builder, bindings, binding_count)
    } else {
        try bind_value(c, g, module_index, names[0usize], counter_type, body_counter, false, false, builder, bindings, binding_count)
    }
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: increment_block, break_defer_base: defers.count, continue_defer_base: defers.count, breaks: break_storage[..], break_count: 0usize }
    let body_error = lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    if body_error != ok { ret body_error }
    if !builder.blocks[builder.current_block].terminated {
        let (body_edge, body_edge_error) = emit_branch(builder, token)
        if body_edge_error != ok { ret body_edge_error }
        try nir.set_branch_targets(builder, body_edge, increment_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_block_index, exit_block_error) = nir.begin_block(builder)
    if exit_block_error != ok || exit_block_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    var break_at = 0usize
    while break_at < control.break_count {
        try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
        break_at += 1usize
    }
    ret ok
}

fn add_control_exit(control: *LoopControl, branch: usize) -> err {
    if control.break_count == control.breaks.len { ret check.Capacity }
    control.breaks[control.break_count] = branch
    control.break_count += 1usize
    ret ok
}

fn deferred_call_node(tree: *parse.Tree, node: syntax.Node) -> (usize, bool) {
    if node.kind != .CallStmt && node.kind != .BindingStmt { ret (0usize, false) }
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind == .CallExpr { ret (child_index, true) }
        }
        at += 1usize
    }
    ret (0usize, false)
}

fn lower_defer(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState) -> err {
    if defers.count == defers.entries.len { ret check.Capacity }
    let (child_index, found_child) = check.first_node_child(tree, node)
    if !found_child { ret parse.InvalidSyntax }
    let child = tree.nodes[child_index]
    var entry: Deferred = zero
    entry.token = c.tokens[node.token_start]
    let (call_index, has_call) = deferred_call_node(tree, child)
    if has_call {
        entry.kind = .Call
        let arguments_error = lower_call_arguments(c, g, tree, module_index, tree.nodes[call_index], builder, bindings, binding_count, true, &entry.call, &entry.callee, entry.arguments[..], &entry.argument_count)
        if arguments_error != ok { ret arguments_error }
    } else {
        entry.node_index = child_index
        if child.kind == .Block { entry.kind = .Block } else { entry.kind = .Statement }
    }
    defers.entries[defers.count] = entry
    defers.count += 1usize
    ret ok
}

fn emit_deferred_from(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState, base: usize) -> err {
    if base > defers.count { ret nir.InvalidControlFlow }
    var at = defers.count
    while at > base {
        at = at - 1usize
        var entry = defers.entries[at]
        if entry.kind == .Call {
            var results: CallResults = zero
            try emit_call_results(c, entry.call, entry.callee, entry.arguments[..], entry.argument_count, builder, entry.token, &results)
        } else {
            let local_checkpoint = c.local_count
            var current_binding_count = binding_count
            var no_loop: LoopControl = zero
            if entry.kind == .Block {
                try lower_block(c, g, tree, module_index, function, tree.nodes[entry.node_index], builder, bindings, &current_binding_count, &no_loop, defers)
            } else {
                if entry.kind != .Statement { ret nir.InvalidControlFlow }
                try lower_statement(c, g, tree, module_index, function, tree.nodes[entry.node_index], builder, bindings, &current_binding_count, &no_loop, defers)
            }
            c.local_count = local_checkpoint
        }
    }
    ret ok
}

fn lower_switch_arm(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, arm: syntax.Node, subject: usize, subject_type: check.Type, aggregate_index: usize, has_aggregate: bool, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    let defer_checkpoint = defers.count
    let (capture, has_capture) = check.switch_capture_name(c, g.modules[module_index].text, arm)
    if has_capture {
        if !has_aggregate || c.aggregates[aggregate_index].kind != .TaggedUnion { ret check.InvalidSwitch }
        var field_index = 0usize
        var found_field = false
        let arm_end = arm.first_child + arm.child_count
        var case_at = arm.first_child
        while case_at < arm_end {
            if tree.children[case_at].node {
                let case_index = tree.children[case_at].index
                if !check.check_statement_kind(tree.nodes[case_index].kind) {
                    let (key, candidate, has_candidate, key_error) = check.switch_case_key(c, g, tree, module_index, case_index, subject_type, aggregate_index, true)
                    if key_error != ok { ret key_error }
                    field_index = candidate
                    found_field = has_candidate
                    break
                }
            }
            case_at += 1usize
        }
        if !found_field || field_index >= c.aggregate_field_count { ret check.InvalidSwitch }
        let field = c.aggregate_fields[field_index]
        let (payload, payload_error) = layout.field(c, subject_type, field.name)
        if payload_error != ok { ret payload_error }
        let token = c.tokens[arm.token_start]
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, field.ty, true, payload.offset, token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, subject)
        var value = address
        var address_value = aggregate_value(c, field.ty)
        if !address_value {
            let (info, info_error) = layout.type_info(c, field.ty)
            if info_error != ok { ret info_error }
            let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, field.ty, true, info.size, token)
            if load_error != ok { ret load_error }
            try nir.add_operand(builder, load_instruction, address)
            value = loaded
        }
        var capture_token = token
        var token_at = arm.token_start
        while token_at < arm.token_end {
            if c.tokens[token_at].kind == .Identifier && check.same(g.modules[module_index].text[c.tokens[token_at].start..c.tokens[token_at].end], capture) { capture_token = c.tokens[token_at] }
            token_at += 1usize
        }
        try bind_value(c, g, module_index, capture_token, field.ty, value, address_value, false, builder, bindings, binding_count)
    }
    let end = arm.first_child + arm.child_count
    var at = arm.first_child
    while at < end {
        if builder.blocks[builder.current_block].terminated { break }
        if tree.children[at].node {
            let statement = tree.nodes[tree.children[at].index]
            if check.check_statement_kind(statement.kind) { try lower_statement(c, g, tree, module_index, function, statement, builder, bindings, binding_count, control, defers) }
        }
        at += 1usize
    }
    if !builder.blocks[builder.current_block].terminated { try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, defer_checkpoint) }
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    defers.count = defer_checkpoint
    ret ok
}

fn lower_switch(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, outer_control: *LoopControl, defers: *DeferState) -> err {
    var subject_index = 0usize
    var has_subject = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind != .SwitchArm {
                subject_index = child_index
                has_subject = true
                break
            }
        }
        at += 1usize
    }
    if !has_subject { ret parse.InvalidSyntax }
    let (subject_type, subject_type_error) = check.check_expr(c, g, tree, module_index, subject_index, check.invalid_type())
    if subject_type_error != ok { ret subject_type_error }
    let (subject, lowered_subject_type, subject_error) = lower_expression(c, g, tree, module_index, subject_index, subject_type, builder, bindings, *binding_count)
    if subject_error != ok { ret subject_error }
    let (aggregate_index, has_aggregate) = layout.aggregate_index(c, subject_type)
    var compared = subject
    var compare_type = subject_type
    if has_aggregate && c.aggregates[aggregate_index].kind == .TaggedUnion {
        let (tag, tag_error) = layout.field(c, subject_type, "tag")
        if tag_error != ok { ret tag_error }
        let token = c.tokens[node.token_start]
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, tag.ty, true, tag.offset, token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, subject)
        let (tag_info, tag_info_error) = layout.type_info(c, tag.ty)
        if tag_info_error != ok { ret tag_info_error }
        let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, tag.ty, true, tag_info.size, token)
        if load_error != ok { ret load_error }
        try nir.add_operand(builder, load_instruction, address)
        compared = loaded
        compare_type = tag.ty
    }
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: outer_control.continue_target, break_defer_base: defers.count, continue_defer_base: outer_control.continue_defer_base, breaks: break_storage[..], break_count: 0usize }
    var default_arm: syntax.Node = zero
    var has_default = false
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let arm = tree.nodes[tree.children[at].index]
            if arm.kind == .SwitchArm {
                if c.tokens[arm.token_start].kind == .KwDefault {
                    default_arm = arm
                    has_default = true
                } else {
                    var match = 0usize
                    var has_match = false
                    let arm_end = arm.first_child + arm.child_count
                    var case_at = arm.first_child
                    while case_at < arm_end {
                        if tree.children[case_at].node {
                            let case_index = tree.children[case_at].index
                            if !check.check_statement_kind(tree.nodes[case_index].kind) {
                                var case_value = 0usize
                                if has_aggregate && c.aggregates[aggregate_index].kind == .TaggedUnion {
                                    let (key, field_index, has_field, key_error) = check.switch_case_key(c, g, tree, module_index, case_index, subject_type, aggregate_index, true)
                                    if key_error != ok || !has_field || field_index >= c.aggregate_field_count { ret check.InvalidSwitch }
                                    let field = c.aggregate_fields[field_index]
                                    let (case_bits, case_bits_error) = check.enum_member_bits(c.aggregates[aggregate_index].backing_type, field.enum_value, field.enum_negative)
                                    if case_bits_error != ok { ret case_bits_error }
                                    let (case_instruction, value, case_error) = nir.emit(builder, .ConstInteger, compare_type, true, case_bits, c.tokens[arm.token_start])
                                    if case_error != ok { ret case_error }
                                    case_value = value
                                } else {
                                    let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, case_index, subject_type, builder, bindings, *binding_count)
                                    if value_error != ok { ret value_error }
                                    case_value = value
                                }
                                let boolean = check.make_type(.Bool, "bool", module_index)
                                let (equal_instruction, equal, equal_error) = nir.emit(builder, .Equal, boolean, true, 0usize, c.tokens[arm.token_start])
                                if equal_error != ok { ret equal_error }
                                try nir.add_operand(builder, equal_instruction, compared)
                                try nir.add_operand(builder, equal_instruction, case_value)
                                if has_match {
                                    let (or_instruction, combined, or_error) = nir.emit(builder, .BitOr, boolean, true, 0usize, c.tokens[arm.token_start])
                                    if or_error != ok { ret or_error }
                                    try nir.add_operand(builder, or_instruction, match)
                                    try nir.add_operand(builder, or_instruction, equal)
                                    match = combined
                                } else {
                                    match = equal
                                    has_match = true
                                }
                            }
                        }
                        case_at += 1usize
                    }
                    if !has_match { ret parse.InvalidSyntax }
                    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[arm.token_start])
                    if decision_error != ok { ret decision_error }
                    try nir.add_operand(builder, decision, match)
                    let body_block = builder.block_count
                    let (body_index, body_error) = nir.begin_block(builder)
                    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
                    try lower_switch_arm(c, g, tree, module_index, function, arm, subject, subject_type, aggregate_index, has_aggregate, builder, bindings, binding_count, &control, defers)
                    if !builder.blocks[builder.current_block].terminated {
                        let (exit_branch, exit_error) = emit_branch(builder, c.tokens[arm.token_start])
                        if exit_error != ok { ret exit_error }
                        try add_control_exit(&control, exit_branch)
                    }
                    let next_block = builder.block_count
                    let (next_index, next_error) = nir.begin_block(builder)
                    if next_error != ok || next_index != next_block { ret nir.InvalidControlFlow }
                    try nir.set_branch_targets(builder, decision, body_block, next_block)
                }
            }
        }
        at += 1usize
    }
    if has_default {
        try lower_switch_arm(c, g, tree, module_index, function, default_arm, subject, subject_type, aggregate_index, has_aggregate, builder, bindings, binding_count, &control, defers)
        if !builder.blocks[builder.current_block].terminated {
            let (exit_branch, exit_error) = emit_branch(builder, c.tokens[node.token_start])
            if exit_error != ok { ret exit_error }
            try add_control_exit(&control, exit_branch)
        }
    } else {
        let (instruction, ignored, unreachable_error) = nir.emit(builder, .Unreachable, zero, false, 0usize, c.tokens[node.token_start])
        if unreachable_error != ok { ret unreachable_error }
    }
    if control.break_count != 0usize {
        let exit_block = builder.block_count
        let (exit_index, exit_error) = nir.begin_block(builder)
        if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
        var break_at = 0usize
        while break_at < control.break_count {
            try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
            break_at += 1usize
        }
    }
    ret ok
}

fn lower_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    c.failure_module = module_index
    c.failure_token = c.tokens[node.token_start]
    c.failure_has_token = true
    if node.kind == .ReturnStmt { ret lower_return(c, g, tree, module_index, function, node, builder, bindings, *binding_count, defers) }
    if node.kind == .TryStmt { ret lower_try(c, g, tree, module_index, function, node, builder, bindings, *binding_count, defers) }
    if node.kind == .BindingStmt { ret lower_binding(c, g, tree, module_index, node, builder, bindings, binding_count) }
    if node.kind == .AssignmentStmt { ret lower_assignment(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .CallStmt { ret lower_call_statement(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .IfStmt { ret lower_if(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers) }
    if node.kind == .WhileStmt { ret lower_while(c, g, tree, module_index, function, node, builder, bindings, binding_count, defers) }
    if node.kind == .ForStmt { ret lower_for(c, g, tree, module_index, function, node, builder, bindings, binding_count, defers) }
    if node.kind == .SwitchStmt { ret lower_switch(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers) }
    if node.kind == .DeferStmt { ret lower_defer(c, g, tree, module_index, node, builder, bindings, *binding_count, defers) }
    if node.kind == .BreakStmt {
        if !control.active || control.break_count == control.breaks.len { ret check.Unsupported }
        try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, control.break_defer_base)
        let (branch, branch_error) = emit_branch(builder, c.tokens[node.token_start])
        if branch_error != ok { ret branch_error }
        control.breaks[control.break_count] = branch
        control.break_count += 1usize
        ret ok
    }
    if node.kind == .ContinueStmt {
        if !control.active { ret check.Unsupported }
        try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, control.continue_defer_base)
        let (branch, branch_error) = emit_branch(builder, c.tokens[node.token_start])
        if branch_error != ok { ret branch_error }
        ret nir.set_branch_targets(builder, branch, control.continue_target, 0usize)
    }
    ret check.Unsupported
}

fn lower_block(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    if node.kind != .Block { ret parse.InvalidSyntax }
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    let defer_checkpoint = defers.count
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if builder.blocks[builder.current_block].terminated { break }
        if tree.children[at].node { try lower_statement(c, g, tree, module_index, function, tree.nodes[tree.children[at].index], builder, bindings, binding_count, control, defers) }
        at += 1usize
    }
    if !builder.blocks[builder.current_block].terminated { try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, defer_checkpoint) }
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    defers.count = defer_checkpoint
    ret ok
}

fn lower_function_index(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    c.failure_module = module_index
    c.failure_name = name
    c.failure_token = c.tokens[node.token_start]
    c.failure_has_token = true
    if function_index >= c.function_count { ret FunctionNotFound }
    let function = c.functions[function_index]
    if function.generic { ret check.Unsupported }
    let (nir_function, begin_error) = nir.begin_function(builder, function.owner_module_index, name, function.instance_id)
    if begin_error != ok { ret begin_error }
    try nir.begin_signature(builder, nir_function, signatures)
    var signature_parameter_at = 0usize
    while signature_parameter_at < function.parameter_count {
        try nir.add_parameter_type(builder, nir_function, signatures, c.parameters[function.first_parameter + signature_parameter_at].ty)
        signature_parameter_at += 1usize
    }
    var signature_return_at = 0usize
    while signature_return_at < function.return_count {
        try nir.add_return_type(builder, nir_function, signatures, c.return_types[function.first_return + signature_return_at])
        signature_return_at += 1usize
    }
    let (entry, block_error) = nir.begin_block(builder)
    if block_error != ok { ret block_error }
    let local_checkpoint = c.local_count
    var binding_count = 0usize
    var defers: DeferState = zero
    var hidden_parameters = 0usize
    var function_call: check.CallInfo = zero
    function_call.function = function
    var return_layout: ReturnLayout = zero
    let return_layout_error = call_return_layout(c, function_call, &return_layout)
    if return_layout_error != ok { ret return_layout_error }
    if return_layout.via_slot && function.return_count != 0usize {
        let pointer_type = check.make_type(.Pointer, "", module_index)
        let (return_parameter, return_slot, return_parameter_error) = nir.emit(builder, .Parameter, pointer_type, true, 0usize, c.tokens[node.token_start])
        if return_parameter_error != ok { ret return_parameter_error }
        try add_binding(bindings, &binding_count, Binding { name: "$return", ty: pointer_type, value: return_slot, address: false })
        hidden_parameters = 1usize
    }
    var parameter_at = 0usize
    while parameter_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_at]
        let (instruction, result, parameter_error) = nir.emit(builder, .Parameter, parameter.ty, true, parameter_at + hidden_parameters, c.tokens[node.token_start])
        if parameter_error != ok { ret parameter_error }
        try add_binding(bindings, &binding_count, Binding { name: parameter.name, ty: parameter.ty, value: result, address: aggregate_value(c, parameter.ty) })
        try check.add_local(c, parameter.name, parameter.ty, false)
        parameter_at += 1usize
    }
    var found_body = false
    var no_loop: LoopControl = zero
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .Block {
                found_body = true
                try lower_block(c, g, tree, module_index, function, child, builder, bindings, &binding_count, &no_loop, &defers)
            }
        }
        at += 1usize
    }
    if !found_body { ret parse.InvalidSyntax }
    if !builder.blocks[builder.current_block].terminated {
        if function.return_count != 0usize { ret check.MissingReturn }
        let (instruction, ignored, return_error) = nir.emit(builder, .Return, zero, false, 0usize, c.tokens[node.token_start])
        if return_error != ok { ret return_error }
    }
    let end_error = nir.end_function(builder)
    c.local_count = local_checkpoint
    ret end_error
}

fn lower_declaration(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (function_index, found) = check.find_function(c, module_index, name)
    if !found { ret FunctionNotFound }
    if c.functions[function_index].generic { ret ok }
    ret lower_function_index(c, g, tree, module_index, node, function_index, builder, signatures, bindings)
}

fn lower_instance(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, instance_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    if instance_index >= c.function_count { ret FunctionNotFound }
    let instance = c.functions[instance_index]
    let instance_generic = c.function_generics[instance_index]
    if !instance_generic.instance || instance_generic.template_index >= c.signature_function_count || instance.generic { ret check.Unsupported }
    let template = c.functions[instance_generic.template_index]
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl {
            let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
            if name_error != ok { ret name_error }
            if check.same(name, template.name) {
                let template_generic = c.function_generics[instance_generic.template_index]
                c.active_first_comptime = template_generic.first_comptime
                c.active_comptime_count = template_generic.comptime_count
                c.active_first_argument = instance_generic.first_argument
                c.active_arguments = true
                let lower_error = lower_function_index(c, g, tree, module_index, node, instance_index, builder, signatures, bindings)
                c.active_first_comptime = 0usize
                c.active_comptime_count = 0usize
                c.active_first_argument = 0usize
                c.active_arguments = false
                ret lower_error
            }
        }
        node_index += 1usize
    }
    ret FunctionNotFound
}

fn pending_instance(c: *check.Checker, owner_module_index: usize) -> (usize, bool) {
    var at = c.signature_function_count
    while at < c.function_count {
        let generic = c.function_generics[at]
        if generic.instance && !generic.lowered && !c.functions[at].generic && c.functions[at].owner_module_index == owner_module_index { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A concrete instance is code in the module that instantiated it, but its body is
// the template's source, so lowering it needs the declaring module's tree. Each
// pass parses one declaring module and lowers every pending instance from it;
// instances that pass creates in turn are picked up by the next one.
fn lower_owned_instances(c: *check.Checker, g: *graph.Graph, module_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    while true {
        let (first, found) = pending_instance(c, module_index)
        if !found { ret ok }
        let template_module = c.functions[c.function_generics[first].template_index].module_index
        if template_module >= g.count { ret FunctionNotFound }
        var tree: parse.Tree = zero
        try parse.init_tree(&tree, g.nodes, g.children)
        try parse.parse(&tree, g.modules[template_module].text)
        try check.tokenize(c, g.modules[template_module].text)
        var at = first
        let end = c.function_count
        while at < end {
            let generic = c.function_generics[at]
            if generic.instance && !generic.lowered && !c.functions[at].generic && c.functions[at].owner_module_index == module_index && c.functions[generic.template_index].module_index == template_module {
                c.function_generics[at].lowered = true
                c.active_owner_module = module_index
                c.active_owner_set = true
                let lower_error = lower_instance(c, g, &tree, template_module, at, builder, signatures, bindings)
                c.active_owner_set = false
                c.active_owner_module = 0usize
                if lower_error != ok { ret lower_error }
            }
            at += 1usize
        }
    }
    ret ok
}

fn module(c: *check.Checker, g: *graph.Graph, module_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    if module_index >= g.count { ret FunctionNotFound }
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[module_index].text)
    try check.tokenize(c, g.modules[module_index].text)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl { try lower_declaration(c, g, &tree, module_index, node, builder, signatures, bindings) }
        node_index += 1usize
    }
    ret lower_owned_instances(c, g, module_index, builder, signatures, bindings)
}

fn all_modules(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    var module_index = 0usize
    while module_index < g.count {
        try module(c, g, module_index, builder, signatures, bindings)
        module_index += 1usize
    }
    ret ok
}

fn reachable_modules(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, lowered: []bool) -> err {
    if g.count == 0usize || g.count > lowered.len { ret FunctionNotFound }
    var module_index = 0usize
    while module_index < g.count {
        lowered[module_index] = false
        module_index += 1usize
    }
    try module(c, g, 0usize, builder, signatures, bindings)
    lowered[0usize] = true
    var reference_at = 0usize
    while reference_at < builder.function_ref_count {
        let target_module = builder.function_refs[reference_at].module_index
        if target_module >= g.count { ret FunctionNotFound }
        if !lowered[target_module] {
            try module(c, g, target_module, builder, signatures, bindings)
            lowered[target_module] = true
        }
        reference_at += 1usize
    }
    ret ok
}
