// Checked syntax to canonical NIR lowering. The initial slice lowers parameters and
// literal returns; later increments extend expressions and structured control flow.

use check
use graph
use lex
use nir
use parse
use syntax

error FunctionNotFound

type Binding = struct {
    name: str,
    ty: check.Type,
    value: usize,
    address: bool,
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

fn lower_call(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (check.CallInfo, usize, err) {
    var empty: check.CallInfo = zero
    let (call, call_error) = check.check_call(c, g, tree, module_index, node)
    if call_error != ok { ret (empty, 0usize, call_error) }
    if call.is_cast || call.mem_alloc || call.function.generic || call.function.return_count > 1usize { ret (empty, 0usize, check.Unsupported) }
    let (function_ref, function_ref_error) = nir.intern_function(builder, call.function.module_index, call.function.name)
    if function_ref_error != ok { ret (empty, 0usize, function_ref_error) }
    var arguments: [16]usize = zero
    var argument_count = 0usize
    let end = node.first_child + node.child_count
    var child_position = 0usize
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if child_position > 0usize {
                if argument_count == arguments.len || argument_count >= call.function.parameter_count { ret (empty, 0usize, check.ArgumentCount) }
                let parameter = c.parameters[call.function.first_parameter + argument_count]
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, parameter.ty, builder, bindings, binding_count)
                if value_error != ok { ret (empty, 0usize, value_error) }
                arguments[argument_count] = value
                argument_count += 1usize
            }
            child_position += 1usize
        }
        at += 1usize
    }
    if argument_count != call.function.parameter_count { ret (empty, 0usize, check.ArgumentCount) }
    var return_type: check.Type = zero
    let has_result = call.function.return_count == 1usize
    if has_result {
        let (result_type, result_type_error) = check.call_return(c, call, 0usize)
        if result_type_error != ok { ret (empty, 0usize, result_type_error) }
        return_type = result_type
    }
    let (instruction, result, emit_error) = nir.emit(builder, .Call, return_type, has_result, function_ref, c.tokens[node.token_start])
    if emit_error != ok { ret (empty, 0usize, emit_error) }
    at = 0usize
    while at < argument_count {
        let operand_error = nir.add_operand(builder, instruction, arguments[at])
        if operand_error != ok { ret (empty, 0usize, operand_error) }
        at += 1usize
    }
    ret (call, result, ok)
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

fn lower_expression(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
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
        if !found { ret (0usize, zero, check.Unsupported) }
        let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if type_error != ok { ret (0usize, result_type, type_error) }
        if !binding.address { ret (binding.value, result_type, ok) }
        let (instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, 0usize, token)
        if load_error != ok { ret (0usize, result_type, load_error) }
        let operand_error = nir.add_operand(builder, instruction, binding.value)
        if operand_error != ok { ret (0usize, result_type, operand_error) }
        ret (result, result_type, ok)
    }
    if node.kind == .UnaryExpr {
        let end = node.first_child + node.child_count
        var child_index = 0usize
        var found_child = false
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if found_child { ret (0usize, zero, parse.InvalidSyntax) }
                child_index = tree.children[at].index
                found_child = true
            }
            at += 1usize
        }
        if !found_child { ret (0usize, zero, parse.InvalidSyntax) }
        let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if result_type_error != ok { ret (0usize, result_type, result_type_error) }
        let operator = c.tokens[node.token_start].kind
        var operand_expected = result_type
        if operator == .PunctBang { operand_expected = check.make_type(.Bool, "bool", module_index) }
        let (operand, operand_type, operand_error) = lower_expression(c, g, tree, module_index, child_index, operand_expected, builder, bindings, binding_count)
        if operand_error != ok { ret (0usize, operand_type, operand_error) }
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
        if operator == .PunctAndAnd || operator == .PunctOrOr { ret (0usize, zero, check.Unsupported) }
        let opcode = binary_opcode(operator)
        if opcode == .Invalid { ret (0usize, zero, check.InvalidOperator) }
        var operand_expected = result_type
        if check.is_comparison(operator) { operand_expected = check.invalid_type() }
        let (left_type, left_type_error) = check.check_expr(c, g, tree, module_index, children[0usize], operand_expected)
        if left_type_error != ok { ret (0usize, left_type, left_type_error) }
        let (left, lowered_left_type, left_error) = lower_expression(c, g, tree, module_index, children[0usize], left_type, builder, bindings, binding_count)
        if left_error != ok { ret (0usize, lowered_left_type, left_error) }
        var right_expected = left_type
        if operator == .PunctShiftLeft || operator == .PunctShiftRight { right_expected = check.make_type(.Integer, "u32", module_index) }
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
    var values: [2]usize = zero
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
    if !found_binding || !found_initializer || check.contains_token(c, node.token_start, tree.nodes[initializer_index].token_start, .KwTry) { ret check.Unsupported }
    if c.tokens[binding_node.token_start].kind == .PunctLParen { ret check.Unsupported }
    let (name, has_name) = check.first_name(c, g.modules[module_index].text, binding_node)
    if !has_name { ret parse.InvalidSyntax }
    let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, initializer_index, declared, builder, bindings, *binding_count)
    if value_error != ok { ret value_error }
    let mutable = c.tokens[node.token_start].kind == .KwVar
    var stored_value = value
    var address = false
    if mutable {
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, value_type, true, 0usize, c.tokens[node.token_start])
        if stack_error != ok { ret stack_error }
        let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, value_type, false, 0usize, c.tokens[node.token_start])
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, stack)
        try nir.add_operand(builder, store_instruction, value)
        stored_value = stack
        address = true
    }
    try add_binding(bindings, binding_count, Binding { name: name, ty: value_type, value: stored_value, address: address })
    ret check.add_local(c, name, value_type, mutable)
}

fn lower_assignment(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
    var children: [2]usize = zero
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
    if count != 2usize { ret parse.InvalidSyntax }
    let place = tree.nodes[children[0usize]]
    if place.kind != .NameExpr { ret check.Unsupported }
    let token = c.tokens[place.token_start]
    let name = g.modules[module_index].text[token.start..token.end]
    let (binding, found) = find_binding(bindings, binding_count, name)
    if !found || !binding.address { ret check.ImmutableAssignment }
    let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, children[1usize], binding.ty, builder, bindings, binding_count)
    if value_error != ok { ret value_error }
    let (instruction, ignored, emit_error) = nir.emit(builder, .Store, value_type, false, 0usize, c.tokens[node.token_start])
    if emit_error != ok { ret emit_error }
    try nir.add_operand(builder, instruction, binding.value)
    try nir.add_operand(builder, instruction, value)
    ret ok
}

fn lower_call_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let call_node = tree.nodes[tree.children[at].index]
            let (call, ignored, call_error) = lower_call(c, g, tree, module_index, call_node, builder, bindings, binding_count)
            if call_error != ok { ret call_error }
            if call.function.return_count != 0usize { ret check.ArgumentCount }
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

fn lower_if(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
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
    try lower_block(c, g, tree, module_index, function, tree.nodes[branches[0usize]], builder, bindings, binding_count)
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
    if branch_count == 2usize { try lower_block(c, g, tree, module_index, function, tree.nodes[branches[1usize]], builder, bindings, binding_count) }
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
    try lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count)
    if !builder.blocks[builder.current_block].terminated {
        let (back_edge, back_edge_error) = emit_branch(builder, c.tokens[node.token_start])
        if back_edge_error != ok { ret back_edge_error }
        try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_block_index, exit_block_error) = nir.begin_block(builder)
    if exit_block_error != ok || exit_block_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    ret ok
}

fn lower_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    if node.kind == .ReturnStmt { ret lower_return(c, g, tree, module_index, function, node, builder, bindings, *binding_count) }
    if node.kind == .TryStmt { ret lower_try(c, g, tree, module_index, function, node, builder, bindings, *binding_count) }
    if node.kind == .BindingStmt { ret lower_binding(c, g, tree, module_index, node, builder, bindings, binding_count) }
    if node.kind == .AssignmentStmt { ret lower_assignment(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .CallStmt { ret lower_call_statement(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .IfStmt { ret lower_if(c, g, tree, module_index, function, node, builder, bindings, binding_count) }
    if node.kind == .WhileStmt { ret lower_while(c, g, tree, module_index, function, node, builder, bindings, binding_count) }
    ret check.Unsupported
}

fn lower_block(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    if node.kind != .Block { ret parse.InvalidSyntax }
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if builder.blocks[builder.current_block].terminated { break }
        if tree.children[at].node { try lower_statement(c, g, tree, module_index, function, tree.nodes[tree.children[at].index], builder, bindings, binding_count) }
        at += 1usize
    }
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    ret ok
}

fn lower_function(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding) -> err {
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    let (function_index, found) = check.find_function(c, module_index, name)
    if !found { ret FunctionNotFound }
    let function = c.functions[function_index]
    if function.generic { ret check.Unsupported }
    let (nir_function, begin_error) = nir.begin_function(builder, module_index, name)
    if begin_error != ok { ret begin_error }
    let (entry, block_error) = nir.begin_block(builder)
    if block_error != ok { ret block_error }
    let local_checkpoint = c.local_count
    var binding_count = 0usize
    var parameter_at = 0usize
    while parameter_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_at]
        let (instruction, result, parameter_error) = nir.emit(builder, .Parameter, parameter.ty, true, parameter_at, c.tokens[node.token_start])
        if parameter_error != ok { ret parameter_error }
        try add_binding(bindings, &binding_count, Binding { name: parameter.name, ty: parameter.ty, value: result, address: false })
        try check.add_local(c, parameter.name, parameter.ty, false)
        parameter_at += 1usize
    }
    var found_body = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .Block {
                found_body = true
                try lower_block(c, g, tree, module_index, function, child, builder, bindings, &binding_count)
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

fn module(c: *check.Checker, g: *graph.Graph, module_index: usize, builder: *nir.Builder, bindings: []Binding) -> err {
    if module_index >= g.count { ret FunctionNotFound }
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[module_index].text)
    try check.tokenize(c, g.modules[module_index].text)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl { try lower_function(c, g, &tree, module_index, node, builder, bindings) }
        node_index += 1usize
    }
    ret ok
}
