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

type ReturnLayout = struct {
    offsets: [16]usize,
    size: usize,
    alignment: usize,
    via_slot: bool,
}

type LoopControl = struct {
    active: bool,
    continue_target: usize,
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
    var address = address_value || aggregate_value(c, ty)
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
    if call.mem_alloc {
        if index == 0usize { ret (call.alloc_arena, ok) }
        ret (check.make_type(.Integer, "usize", call.function.module_index), ok)
    }
    let parameter_index = call.function.first_parameter + index
    if parameter_index >= c.parameter_count { ret (check.invalid_type(), check.InvalidType) }
    ret (c.parameters[parameter_index].ty, ok)
}

fn emit_call_results(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    results.call = call
    results.count = call.function.return_count
    var return_layout: ReturnLayout = zero
    let return_layout_error = call_return_layout(c, call, &return_layout)
    if return_layout_error != ok { ret return_layout_error }
    var symbol = call.function.name
    if call.mem_alloc { symbol = "neper_mem_alloc" }
    let (function_ref, function_ref_error) = nir.intern_function(builder, call.function.module_index, symbol)
    if function_ref_error != ok { ret function_ref_error }
    var slot = 0usize
    if return_layout.via_slot && results.count != 0usize {
        var slots = (return_layout.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, zero, true, slots, token)
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
        }
    }
    let (instruction, call_result, emit_error) = nir.emit(builder, .Call, call_type, call_has_result, function_ref, token)
    if emit_error != ok { ret emit_error }
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

fn lower_call_results(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, results: *CallResults) -> err {
    let (call, call_error) = check.check_call(c, g, tree, module_index, node)
    if call_error != ok { ret call_error }
    if call.is_cast || call.function.generic { ret check.Unsupported }
    var arguments: [16]usize = zero
    var argument_count = 0usize
    let end = node.first_child + node.child_count
    var child_position = 0usize
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if child_position > 0usize {
                if argument_count == arguments.len || argument_count >= call.function.parameter_count { ret check.ArgumentCount }
                let (parameter_type, parameter_type_error) = call_parameter_type(c, call, argument_count)
                if parameter_type_error != ok { ret parameter_type_error }
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, parameter_type, builder, bindings, binding_count)
                if value_error != ok { ret value_error }
                arguments[argument_count] = value
                argument_count += 1usize
            }
            child_position += 1usize
        }
        at += 1usize
    }
    if argument_count != call.function.parameter_count { ret check.ArgumentCount }
    ret emit_call_results(c, call, arguments[..], argument_count, builder, c.tokens[node.token_start], results)
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
                if member.enum_negative { ret (0usize, result_type, check.Unsupported) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, result_type, true, member.enum_value, c.tokens[node.token_start])
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
            let (symbol_index, has_symbol) = resolve.find(c.resolver, module_index, name, .Value)
            let (intrinsic_function, has_intrinsic_function) = check.find_function(c, module_index, name)
            if has_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let error_type = check.make_type(.Err, "err", module_index)
                let (value, value_error) = artifact_hash.qualified_error_value(g.modules[module_index].name, name)
                if value_error != ok { ret (0usize, error_type, value_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstError, error_type, true, value, token)
                ret (result, error_type, emit_error)
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
            let (symbol_index, has_symbol) = resolve.find(c.resolver, target_module, qualified_name, .Value)
            let (intrinsic_function, has_intrinsic_function) = check.find_function(c, target_module, qualified_name)
            if has_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let error_type = check.make_type(.Err, "err", target_module)
                let (value, value_error) = artifact_hash.qualified_error_value(g.modules[target_module].name, qualified_name)
                if value_error != ok { ret (0usize, error_type, value_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstError, error_type, true, value, c.tokens[node.token_start])
                ret (result, error_type, emit_error)
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
        let (instruction, result, emit_error) = nir.emit(builder, opcode, result_type, true, 0usize, c.tokens[node.token_start])
        if emit_error != ok { ret (0usize, result_type, emit_error) }
        let left_operand_error = nir.add_operand(builder, instruction, left)
        if left_operand_error != ok { ret (0usize, result_type, left_operand_error) }
        let right_operand_error = nir.add_operand(builder, instruction, right)
        if right_operand_error != ok { ret (0usize, result_type, right_operand_error) }
        ret (result, result_type, ok)
    }
    ret (0usize, zero, check.Unsupported)
}

fn lower_try(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
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
    let (return_instruction, return_ignored, return_error) = nir.emit(builder, .Return, caller_error_type, false, 0usize, c.tokens[node.token_start])
    if return_error != ok { ret return_error }
    try nir.add_operand(builder, return_instruction, call_result)
    let (continue_block_index, continue_block_error) = nir.begin_block(builder)
    if continue_block_error != ok || continue_block_index != continue_block { ret nir.InvalidControlFlow }
    ret ok
}

fn lower_return(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
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
        let (instruction, ignored, emit_error) = nir.emit(builder, .Return, zero, false, 0usize, c.tokens[node.token_start])
        ret emit_error
    }
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

fn lower_if(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl) -> err {
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
    try lower_block(c, g, tree, module_index, function, tree.nodes[branches[0usize]], builder, bindings, binding_count, control)
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
    if branch_count == 2usize { try lower_block(c, g, tree, module_index, function, tree.nodes[branches[1usize]], builder, bindings, binding_count, control) }
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

fn lower_while(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
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
    var control = LoopControl { active: true, continue_target: condition_block, breaks: break_storage[..], break_count: 0usize }
    try lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control)
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

fn lower_for(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
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
    var control = LoopControl { active: true, continue_target: increment_block, breaks: break_storage[..], break_count: 0usize }
    let body_error = lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control)
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

fn lower_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl) -> err {
    c.failure_module = module_index
    c.failure_token = c.tokens[node.token_start]
    c.failure_has_token = true
    if node.kind == .ReturnStmt { ret lower_return(c, g, tree, module_index, function, node, builder, bindings, *binding_count) }
    if node.kind == .TryStmt { ret lower_try(c, g, tree, module_index, function, node, builder, bindings, *binding_count) }
    if node.kind == .BindingStmt { ret lower_binding(c, g, tree, module_index, node, builder, bindings, binding_count) }
    if node.kind == .AssignmentStmt { ret lower_assignment(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .CallStmt { ret lower_call_statement(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .IfStmt { ret lower_if(c, g, tree, module_index, function, node, builder, bindings, binding_count, control) }
    if node.kind == .WhileStmt { ret lower_while(c, g, tree, module_index, function, node, builder, bindings, binding_count) }
    if node.kind == .ForStmt { ret lower_for(c, g, tree, module_index, function, node, builder, bindings, binding_count) }
    if node.kind == .BreakStmt {
        if !control.active || control.break_count == control.breaks.len { ret check.Unsupported }
        let (branch, branch_error) = emit_branch(builder, c.tokens[node.token_start])
        if branch_error != ok { ret branch_error }
        control.breaks[control.break_count] = branch
        control.break_count += 1usize
        ret ok
    }
    if node.kind == .ContinueStmt {
        if !control.active { ret check.Unsupported }
        let (branch, branch_error) = emit_branch(builder, c.tokens[node.token_start])
        if branch_error != ok { ret branch_error }
        ret nir.set_branch_targets(builder, branch, control.continue_target, 0usize)
    }
    ret check.Unsupported
}

fn lower_block(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl) -> err {
    if node.kind != .Block { ret parse.InvalidSyntax }
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if builder.blocks[builder.current_block].terminated { break }
        if tree.children[at].node { try lower_statement(c, g, tree, module_index, function, tree.nodes[tree.children[at].index], builder, bindings, binding_count, control) }
        at += 1usize
    }
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
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
    let (nir_function, begin_error) = nir.begin_function(builder, module_index, name)
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
                try lower_block(c, g, tree, module_index, function, child, builder, bindings, &binding_count, &no_loop)
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
    var instance_index = c.signature_function_count
    while instance_index < c.function_count {
        if c.functions[instance_index].module_index == module_index && c.function_generics[instance_index].instance && !c.functions[instance_index].generic {
            try lower_instance(c, g, &tree, module_index, instance_index, builder, signatures, bindings)
        }
        instance_index += 1usize
    }
    ret ok
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
