// Checked syntax to canonical NIR lowering. The initial slice lowers parameters and
// literal returns; later increments extend expressions and structured control flow.

use check
use graph
use lex
use nir
use parse
use syntax

error FunctionNotFound

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
                    immediate = token.start
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

fn lower_call(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder) -> (check.CallInfo, usize, err) {
    var empty: check.CallInfo = zero
    let (call, call_error) = check.check_call(c, g, tree, module_index, node)
    if call_error != ok { ret (empty, 0usize, call_error) }
    if call.is_cast || call.mem_alloc || call.function.generic || call.function.return_count > 1usize { ret (empty, 0usize, check.Unsupported) }
    let (function_index, found) = check.find_function(c, call.function.module_index, call.function.name)
    if !found { ret (empty, 0usize, FunctionNotFound) }
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
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, parameter.ty, builder)
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
    let (instruction, result, emit_error) = nir.emit(builder, .Call, return_type, has_result, function_index, c.tokens[node.token_start])
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

fn lower_expression(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder) -> (usize, check.Type, err) {
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
                let (group_value, group_type, group_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, expected, builder)
                ret (group_value, group_type, group_error)
            }
            at += 1usize
        }
        ret (0usize, zero, parse.InvalidSyntax)
    }
    if node.kind == .CallExpr {
        let (call, value, call_error) = lower_call(c, g, tree, module_index, node, builder)
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
        let (left, lowered_left_type, left_error) = lower_expression(c, g, tree, module_index, children[0usize], left_type, builder)
        if left_error != ok { ret (0usize, lowered_left_type, left_error) }
        var right_expected = left_type
        if operator == .PunctShiftLeft || operator == .PunctShiftRight { right_expected = check.make_type(.Integer, "u32", module_index) }
        let (right_type, right_type_error) = check.check_expr(c, g, tree, module_index, children[1usize], right_expected)
        if right_type_error != ok { ret (0usize, right_type, right_type_error) }
        let (right, lowered_right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], right_type, builder)
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

fn lower_try(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder) -> err {
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
    let (call, call_result, call_error) = lower_call(c, g, tree, module_index, call_node, builder)
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

fn lower_return(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder) -> err {
    var values: [2]usize = zero
    var count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if count == values.len || count >= function.return_count { ret check.InvalidReturn }
            let (expected, type_error) = check.function_return(c, function, count)
            if type_error != ok { ret type_error }
            let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, tree.children[at].index, expected, builder)
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

fn lower_function(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder) -> err {
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
    var parameter_at = 0usize
    while parameter_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_at]
        let (instruction, result, parameter_error) = nir.emit(builder, .Parameter, parameter.ty, true, parameter_at, c.tokens[node.token_start])
        if parameter_error != ok { ret parameter_error }
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
                let body_end = child.first_child + child.child_count
                var body_at = child.first_child
                while body_at < body_end {
                    if tree.children[body_at].node {
                        let statement = tree.nodes[tree.children[body_at].index]
                        if statement.kind == .ReturnStmt {
                            try lower_return(c, g, tree, module_index, function, statement, builder)
                        } else {
                            if statement.kind == .TryStmt {
                                try lower_try(c, g, tree, module_index, function, statement, builder)
                            } else {
                                ret check.Unsupported
                            }
                        }
                    }
                    body_at += 1usize
                }
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
    ret nir.end_function(builder)
}

fn module(c: *check.Checker, g: *graph.Graph, module_index: usize, builder: *nir.Builder) -> err {
    if module_index >= g.count { ret FunctionNotFound }
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[module_index].text)
    try check.tokenize(c, g.modules[module_index].text)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl { try lower_function(c, g, &tree, module_index, node, builder) }
        node_index += 1usize
    }
    ret ok
}
