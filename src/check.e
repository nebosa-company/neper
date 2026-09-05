// Scalar type-checking foundation. Unsupported forms fail explicitly.

use graph
use lex
use parse
use resolve
use syntax

error Capacity
error Unsupported
error MissingContext
error TypeMismatch
error InvalidCondition
error InvalidOperator
error InvalidReturn
error MissingReturn
error UnknownCallable
error ArgumentCount
error InvalidType
error ImmutableAssignment

type Kind = enum u8 {
    Invalid,
    Void,
    Bool,
    Err,
    Integer,
    Float,
    String,
    Named,
    UntypedInteger,
    UntypedFloat,
    Other,
}

type Type = struct {
    kind: Kind,
    name: str,
    module_index: usize,
}

type Parameter = struct {
    name: str,
    ty: Type,
}

type Function = struct {
    name: str,
    module_index: usize,
    first_parameter: usize,
    parameter_count: usize,
    return_type: Type,
    return_count: usize,
    generic: bool,
}

type Local = struct {
    name: str,
    ty: Type,
    mutable: bool,
}

type Checker = struct {
    functions: []Function,
    parameters: []Parameter,
    tokens: []lex.Token,
    locals: []Local,
    function_count: usize,
    parameter_count: usize,
    token_count: usize,
    local_count: usize,
}

fn init(c: *Checker, functions: []Function, parameters: []Parameter, tokens: []lex.Token, locals: []Local) -> err {
    if functions.len == 0usize || parameters.len == 0usize || tokens.len == 0usize || locals.len == 0usize { ret Capacity }
    c.functions = functions
    c.parameters = parameters
    c.tokens = tokens
    c.locals = locals
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.token_count = 0usize
    c.local_count = 0usize
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn ends_with(text: str, suffix: str) -> bool {
    if text.len < suffix.len { ret false }
    ret same(text[text.len - suffix.len..], suffix)
}

fn make_type(kind: Kind, name: str, module_index: usize) -> Type {
    ret Type { kind: kind, name: name, module_index: module_index }
}

fn invalid_type() -> Type {
    ret make_type(.Invalid, "", 0usize)
}

fn is_integer_name(name: str) -> bool {
    ret same(name, "i8") || same(name, "i16") || same(name, "i32") || same(name, "i64") || same(name, "isize") || same(name, "u8") || same(name, "u16") || same(name, "u32") || same(name, "u64") || same(name, "usize")
}

fn is_float_name(name: str) -> bool {
    ret same(name, "f16") || same(name, "bf16") || same(name, "f32") || same(name, "f64")
}

fn is_numeric(ty: Type) -> bool {
    ret ty.kind == .Integer || ty.kind == .Float || ty.kind == .UntypedInteger || ty.kind == .UntypedFloat
}

fn is_integer(ty: Type) -> bool {
    ret ty.kind == .Integer || ty.kind == .UntypedInteger
}

fn is_untyped(ty: Type) -> bool {
    ret ty.kind == .UntypedInteger || ty.kind == .UntypedFloat
}

fn type_equal(a: Type, b: Type) -> bool {
    if a.kind != b.kind { ret false }
    if a.kind == .Named { ret a.module_index == b.module_index && same(a.name, b.name) }
    if a.kind == .Integer || a.kind == .Float { ret same(a.name, b.name) }
    ret true
}

fn apply_context(actual: Type, expected: Type) -> (Type, err) {
    if expected.kind == .Invalid { ret (actual, ok) }
    if actual.kind == .UntypedInteger && expected.kind == .Integer { ret (expected, ok) }
    if actual.kind == .UntypedFloat && expected.kind == .Float { ret (expected, ok) }
    if type_equal(actual, expected) { ret (expected, ok) }
    ret (invalid_type(), TypeMismatch)
}

fn tokenize(c: *Checker, text: str) -> err {
    var scanner = lex.init(text)
    c.token_count = 0usize
    while true {
        if c.token_count == c.tokens.len { ret Capacity }
        let token = lex.next(&scanner)
        if token.kind == .Invalid { ret lex.InvalidSource }
        c.tokens[c.token_count] = token
        c.token_count += 1usize
        if token.kind == .Eof { break }
    }
    ret ok
}

fn first_node_child(tree: *parse.Tree, node: syntax.Node) -> (usize, bool) {
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node { ret (tree.children[at].index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn function_name(c: *Checker, text: str, node: syntax.Node) -> (str, err) {
    var saw_fn = false
    var at = node.token_start
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .KwFn {
            saw_fn = true
        } else {
            if saw_fn && token.kind == .Identifier { ret (text[token.start..token.end], ok) }
        }
        at += 1usize
    }
    ret ("", parse.InvalidSyntax)
}

fn first_name(c: *Checker, text: str, node: syntax.Node) -> (str, bool) {
    var at = node.token_start
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .Identifier { ret (text[token.start..token.end], true) }
        at += 1usize
    }
    ret ("", false)
}

fn scalar_type(name: str, module_index: usize) -> Type {
    if is_integer_name(name) { ret make_type(.Integer, name, module_index) }
    if is_float_name(name) { ret make_type(.Float, name, module_index) }
    if same(name, "bool") { ret make_type(.Bool, name, module_index) }
    if same(name, "err") { ret make_type(.Err, name, module_index) }
    if same(name, "void") { ret make_type(.Void, name, module_index) }
    if same(name, "str") { ret make_type(.String, name, module_index) }
    ret invalid_type()
}

fn type_from_node(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> Type {
    if node.kind != .NamedType { ret make_type(.Other, "", module_index) }
    let first = c.tokens[node.token_start]
    if first.kind != .Identifier { ret make_type(.Other, "", module_index) }
    let base = g.modules[module_index].text[first.start..first.end]
    let scalar = scalar_type(base, module_index)
    if scalar.kind != .Invalid { ret scalar }
    var target_module = module_index
    var name = base
    var saw_dot = false
    var at = node.token_start + 1usize
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .PunctLBracket { ret make_type(.Other, "", module_index) }
        if token.kind == .PunctDot {
            saw_dot = true
        } else {
            if saw_dot && token.kind == .Identifier {
                let (qualified_module, found) = resolve.qualifier(r, module_index, base)
                if found {
                    target_module = qualified_module
                    name = g.modules[module_index].text[token.start..token.end]
                }
                ret make_type(.Named, name, target_module)
            }
        }
        at += 1usize
    }
    ret make_type(.Named, name, target_module)
}

fn collect_parameter(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.parameter_count == c.parameters.len { ret Capacity }
    let (name, has_name) = first_name(c, g.modules[module_index].text, node)
    if !has_name { ret Unsupported }
    let (type_index, has_type) = first_node_child(tree, node)
    if !has_type { ret Unsupported }
    let ty = type_from_node(c, r, g, module_index, tree.nodes[type_index])
    if ty.kind == .Void { ret InvalidType }
    c.parameters[c.parameter_count] = Parameter { name: name, ty: ty }
    c.parameter_count += 1usize
    ret ok
}

fn collect_function(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.function_count == c.functions.len { ret Capacity }
    let (name, name_error) = function_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    var item = Function { name: name, module_index: module_index, first_parameter: c.parameter_count, parameter_count: 0usize, return_type: make_type(.Void, "void", module_index), return_count: 0usize, generic: false }
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .ComptimeParam { item.generic = true }
            if child.kind == .Parameter {
                try collect_parameter(c, r, g, tree, module_index, child)
                item.parameter_count += 1usize
            }
            if child.kind == .ReturnSpec {
                let return_end = child.first_child + child.child_count
                var return_at = child.first_child
                while return_at < return_end {
                    if tree.children[return_at].node {
                        item.return_count += 1usize
                        if item.return_count == 1usize {
                            item.return_type = type_from_node(c, r, g, module_index, tree.nodes[tree.children[return_at].index])
                        } else {
                            item.return_type = make_type(.Other, "", module_index)
                        }
                    }
                    return_at += 1usize
                }
            }
        }
        at += 1usize
    }
    if item.return_count == 1usize && item.return_type.kind == .Void { item.return_count = 0usize }
    c.functions[c.function_count] = item
    c.function_count += 1usize
    ret ok
}

fn collect_signatures(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.function_count = 0usize
    c.parameter_count = 0usize
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try parse.init_tree(&tree, g.nodes, g.children)
        try parse.parse(&tree, g.modules[module_index].text)
        try tokenize(c, g.modules[module_index].text)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && (node.kind == .FnDecl || node.kind == .ExternDecl) {
                try collect_function(c, r, g, &tree, module_index, node)
            }
            node_index += 1usize
        }
        module_index += 1usize
    }
    ret ok
}

fn find_function(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    var i = 0usize
    while i < c.function_count {
        if c.functions[i].module_index == module_index && same(c.functions[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn find_local(c: *Checker, name: str) -> (usize, bool) {
    var at = c.local_count
    while at > 0usize {
        at = at - 1usize
        if same(c.locals[at].name, name) { ret (at, true) }
    }
    ret (0usize, false)
}

fn add_local(c: *Checker, name: str, ty: Type, mutable: bool) -> err {
    if c.local_count == c.locals.len { ret Capacity }
    c.locals[c.local_count] = Local { name: name, ty: ty, mutable: mutable }
    c.local_count += 1usize
    ret ok
}

fn numeric_literal_type(text: str, token: lex.Token) -> Type {
    let spelling = text[token.start..token.end]
    if token.kind == .Integer {
        if ends_with(spelling, "isize") { ret make_type(.Integer, "isize", 0usize) }
        if ends_with(spelling, "usize") { ret make_type(.Integer, "usize", 0usize) }
        if ends_with(spelling, "i64") { ret make_type(.Integer, "i64", 0usize) }
        if ends_with(spelling, "i32") { ret make_type(.Integer, "i32", 0usize) }
        if ends_with(spelling, "i16") { ret make_type(.Integer, "i16", 0usize) }
        if ends_with(spelling, "i8") { ret make_type(.Integer, "i8", 0usize) }
        if ends_with(spelling, "u64") { ret make_type(.Integer, "u64", 0usize) }
        if ends_with(spelling, "u32") { ret make_type(.Integer, "u32", 0usize) }
        if ends_with(spelling, "u16") { ret make_type(.Integer, "u16", 0usize) }
        if ends_with(spelling, "u8") { ret make_type(.Integer, "u8", 0usize) }
        ret make_type(.UntypedInteger, "", 0usize)
    }
    if ends_with(spelling, "bf16") { ret make_type(.Float, "bf16", 0usize) }
    if ends_with(spelling, "f64") { ret make_type(.Float, "f64", 0usize) }
    if ends_with(spelling, "f32") { ret make_type(.Float, "f32", 0usize) }
    if ends_with(spelling, "f16") { ret make_type(.Float, "f16", 0usize) }
    ret make_type(.UntypedFloat, "", 0usize)
}

fn literal_type(c: *Checker, text: str, node: syntax.Node) -> Type {
    let token = c.tokens[node.token_start]
    if token.kind == .Integer || token.kind == .Float { ret numeric_literal_type(text, token) }
    if token.kind == .KwTrue || token.kind == .KwFalse { ret make_type(.Bool, "bool", 0usize) }
    if token.kind == .String || token.kind == .RawString { ret make_type(.String, "str", 0usize) }
    if token.kind == .Character { ret make_type(.Integer, "u8", 0usize) }
    if token.kind == .KwOk { ret make_type(.Err, "err", 0usize) }
    ret make_type(.Other, "", 0usize)
}

fn binary_operator(c: *Checker, tree: *parse.Tree, node: syntax.Node) -> lex.Kind {
    let end = node.first_child + node.child_count
    var left_end = node.token_start
    var right_start = node.token_end
    var found_left = false
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if !found_left {
                left_end = tree.nodes[tree.children[at].index].token_end
                found_left = true
            } else {
                right_start = tree.nodes[tree.children[at].index].token_start
                break
            }
        }
        at += 1usize
    }
    at = left_end
    while at < right_start {
        let kind = c.tokens[at].kind
        if kind != .Newline { ret kind }
        at += 1usize
    }
    ret .Invalid
}

fn is_comparison(kind: lex.Kind) -> bool {
    ret kind == .PunctEqEq || kind == .PunctBangEq || kind == .PunctLt || kind == .PunctLtEq || kind == .PunctGt || kind == .PunctGtEq
}

fn is_equality(kind: lex.Kind) -> bool {
    ret kind == .PunctEqEq || kind == .PunctBangEq
}

fn is_shift(kind: lex.Kind) -> bool {
    ret kind == .PunctShiftLeft || kind == .PunctShiftRight
}

fn is_logical(kind: lex.Kind) -> bool {
    ret kind == .PunctAndAnd || kind == .PunctOrOr
}

fn is_integer_operator(kind: lex.Kind) -> bool {
    ret kind == .PunctPercent || kind == .PunctAmp || kind == .PunctCaret || kind == .PunctPipe || kind == .PunctAddWrap || kind == .PunctSubWrap || kind == .PunctMulWrap
}

fn check_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if node.kind == .LiteralExpr {
        let (literal, context_error) = apply_context(literal_type(c, text, node), expected)
        ret (literal, context_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind == .KwUnreachable { ret (make_type(.Void, "void", module_index), ok) }
        let name = text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if !found { ret (invalid_type(), Unsupported) }
        let (local_type, context_error) = apply_context(c.locals[local_index].ty, expected)
        ret (local_type, context_error)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (group_type, group_error) = check_expr(c, g, tree, module_index, child_index, expected)
        ret (group_type, group_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let op = c.tokens[node.token_start].kind
        if op == .PunctBang {
            let (value_type, value_error) = check_expr(c, g, tree, module_index, child_index, make_type(.Bool, "bool", module_index))
            if value_error == TypeMismatch { ret (invalid_type(), InvalidOperator) }
            if value_error != ok { ret (invalid_type(), value_error) }
            let (result_type, context_error) = apply_context(value_type, expected)
            ret (result_type, context_error)
        }
        let (value_type, value_error) = check_expr(c, g, tree, module_index, child_index, expected)
        if value_error != ok { ret (invalid_type(), value_error) }
        if op == .PunctMinus && !is_numeric(value_type) { ret (invalid_type(), InvalidOperator) }
        if op == .PunctTilde && !is_integer(value_type) { ret (invalid_type(), InvalidOperator) }
        if op != .PunctMinus && op != .PunctTilde { ret (invalid_type(), Unsupported) }
        ret (value_type, ok)
    }
    if node.kind == .BinaryExpr {
        let end = node.first_child + node.child_count
        var children: [2]usize = zero
        var count = 0usize
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if count == 2usize { ret (invalid_type(), parse.InvalidSyntax) }
                children[count] = tree.children[at].index
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (invalid_type(), parse.InvalidSyntax) }
        let op = binary_operator(c, tree, node)
        if is_shift(op) { ret (invalid_type(), Unsupported) }
        if is_logical(op) {
            let (left_type, left_error) = check_expr(c, g, tree, module_index, children[0usize], make_type(.Bool, "bool", module_index))
            if left_error == TypeMismatch { ret (invalid_type(), InvalidOperator) }
            if left_error != ok { ret (invalid_type(), left_error) }
            let (right_type, right_error) = check_expr(c, g, tree, module_index, children[1usize], make_type(.Bool, "bool", module_index))
            if right_error == TypeMismatch { ret (invalid_type(), InvalidOperator) }
            if right_error != ok { ret (invalid_type(), right_error) }
            let (result_type, context_error) = apply_context(make_type(.Bool, "bool", module_index), expected)
            ret (result_type, context_error)
        }
        var operand_context = expected
        if is_comparison(op) { operand_context = invalid_type() }
        let (left_type, left_error) = check_expr(c, g, tree, module_index, children[0usize], operand_context)
        if left_error != ok { ret (invalid_type(), left_error) }
        var right_context = left_type
        if is_untyped(left_type) { right_context = operand_context }
        let (right_type, right_error) = check_expr(c, g, tree, module_index, children[1usize], right_context)
        if right_error != ok { ret (invalid_type(), right_error) }
        var final_left = left_type
        var final_right = right_type
        if is_untyped(final_left) && !is_untyped(final_right) {
            let (contextual_left, contextual_error) = apply_context(final_left, final_right)
            if contextual_error != ok { ret (invalid_type(), contextual_error) }
            final_left = contextual_left
        }
        if is_untyped(final_right) && !is_untyped(final_left) {
            let (contextual_right, contextual_error) = apply_context(final_right, final_left)
            if contextual_error != ok { ret (invalid_type(), contextual_error) }
            final_right = contextual_right
        }
        if !type_equal(final_left, final_right) { ret (invalid_type(), TypeMismatch) }
        if is_comparison(op) {
            if is_untyped(final_left) { ret (invalid_type(), MissingContext) }
            if !is_numeric(final_left) {
                if !is_equality(op) { ret (invalid_type(), InvalidOperator) }
                if final_left.kind != .Bool && final_left.kind != .Err { ret (invalid_type(), InvalidOperator) }
            }
            let (result_type, context_error) = apply_context(make_type(.Bool, "bool", module_index), expected)
            ret (result_type, context_error)
        }
        if !is_numeric(final_left) { ret (invalid_type(), InvalidOperator) }
        if is_integer_operator(op) && !is_integer(final_left) { ret (invalid_type(), InvalidOperator) }
        ret (final_left, ok)
    }
    if node.kind == .CallExpr {
        let end = node.first_child + node.child_count
        var at = node.first_child
        var child_position = 0usize
        var function_index = 0usize
        var has_function = false
        var cast = invalid_type()
        while at < end {
            if tree.children[at].node {
                let child_index = tree.children[at].index
                if child_position == 0usize {
                    let receiver = tree.nodes[child_index]
                    if receiver.kind != .NameExpr { ret (invalid_type(), Unsupported) }
                    let token = c.tokens[receiver.token_start]
                    let name = text[token.start..token.end]
                    cast = scalar_type(name, module_index)
                    if cast.kind == .Integer || cast.kind == .Float {
                        has_function = false
                    } else {
                        let (found_index, found) = find_function(c, module_index, name)
                        if !found { ret (invalid_type(), UnknownCallable) }
                        function_index = found_index
                        has_function = true
                    }
                } else {
                    if cast.kind == .Integer || cast.kind == .Float {
                        if child_position != 1usize { ret (invalid_type(), ArgumentCount) }
                        let (argument_type, argument_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if argument_error != ok { ret (invalid_type(), argument_error) }
                        if is_untyped(argument_type) { ret (invalid_type(), MissingContext) }
                        if !is_numeric(argument_type) { ret (invalid_type(), TypeMismatch) }
                    } else {
                        if !has_function { ret (invalid_type(), UnknownCallable) }
                        let function = c.functions[function_index]
                        if child_position > function.parameter_count { ret (invalid_type(), ArgumentCount) }
                        let parameter = c.parameters[function.first_parameter + child_position - 1usize]
                        let (argument_type, argument_error) = check_expr(c, g, tree, module_index, child_index, parameter.ty)
                        if argument_error != ok { ret (invalid_type(), argument_error) }
                    }
                }
                child_position += 1usize
            }
            at += 1usize
        }
        if cast.kind == .Integer || cast.kind == .Float {
            if child_position != 2usize { ret (invalid_type(), ArgumentCount) }
            let (result_type, context_error) = apply_context(cast, expected)
            ret (result_type, context_error)
        }
        if !has_function { ret (invalid_type(), UnknownCallable) }
        let function = c.functions[function_index]
        if child_position - 1usize != function.parameter_count { ret (invalid_type(), ArgumentCount) }
        if function.generic || function.return_count > 1usize { ret (invalid_type(), Unsupported) }
        let (result_type, context_error) = apply_context(function.return_type, expected)
        ret (result_type, context_error)
    }
    ret (invalid_type(), Unsupported)
}

fn check_binding(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let end = node.first_child + node.child_count
    var binding_index = 0usize
    var has_binding = false
    var initializer_index = 0usize
    var has_initializer = false
    var declared = invalid_type()
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind == .Binding {
                binding_index = child_index
                has_binding = true
            } else {
                if child.kind == .NamedType || child.kind == .PointerType || child.kind == .SliceType || child.kind == .ArrayType || child.kind == .FunctionType {
                    declared = type_from_node(c, r, g, module_index, child)
                } else {
                    initializer_index = child_index
                    has_initializer = true
                }
            }
        }
        at += 1usize
    }
    if !has_binding { ret parse.InvalidSyntax }
    var result = declared
    if has_initializer {
        let (actual, expression_error) = check_expr(c, g, tree, module_index, initializer_index, declared)
        if expression_error != ok { ret expression_error }
        result = actual
    } else {
        if declared.kind == .Invalid { ret MissingContext }
    }
    if is_untyped(result) { ret MissingContext }
    if result.kind == .Void { ret TypeMismatch }
    if result.kind == .Other { ret Unsupported }
    let binding = tree.nodes[binding_index]
    if c.tokens[binding.token_start].kind == .PunctLParen { ret Unsupported }
    let (name, has_name) = first_name(c, g.modules[module_index].text, binding)
    if !has_name { ret ok }
    var mutable = false
    if c.tokens[node.token_start].kind == .KwVar { mutable = true }
    try add_local(c, name, result, mutable)
    ret ok
}

fn check_return(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var count = 0usize
    var expression_index = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            expression_index = tree.children[at].index
            count += 1usize
        }
        at += 1usize
    }
    if function.return_count == 0usize {
        if count != 0usize { ret InvalidReturn }
        ret ok
    }
    if function.return_count != 1usize || count != 1usize { ret InvalidReturn }
    let (actual, expression_error) = check_expr(c, g, tree, module_index, expression_index, function.return_type)
    if expression_error == TypeMismatch { ret InvalidReturn }
    if expression_error != ok { ret expression_error }
    ret ok
}

fn check_children(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node { try check_statement(c, r, g, tree, module_index, tree.children[at].index, function) }
        at += 1usize
    }
    ret ok
}

fn check_block(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let checkpoint = c.local_count
    let block_error = check_children(c, r, g, tree, module_index, node, function)
    c.local_count = checkpoint
    ret block_error
}

fn check_condition_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = node.first_child + node.child_count
    var first = true
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if first {
                let (condition_type, condition_error) = check_expr(c, g, tree, module_index, child_index, make_type(.Bool, "bool", module_index))
                if condition_error == TypeMismatch { ret InvalidCondition }
                if condition_error != ok { ret condition_error }
                if condition_type.kind != .Bool { ret InvalidCondition }
                first = false
            } else {
                if child.kind == .Block {
                    try check_block(c, r, g, tree, module_index, child, function)
                } else {
                    try check_statement(c, r, g, tree, module_index, child_index, function)
                }
            }
        }
        at += 1usize
    }
    ret ok
}

fn check_call_statement(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret parse.InvalidSyntax }
    let (result, expression_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
    ret expression_error
}

fn check_assignment(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    var children: [2]usize = zero
    var count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if count == 2usize { ret Unsupported }
            children[count] = tree.children[at].index
            count += 1usize
        }
        at += 1usize
    }
    if count != 2usize { ret Unsupported }
    let place = tree.nodes[children[0usize]]
    if place.kind != .NameExpr { ret Unsupported }
    var operator_index = place.token_end
    let value_start = tree.nodes[children[1usize]].token_start
    while operator_index < value_start && c.tokens[operator_index].kind == .Newline { operator_index += 1usize }
    if operator_index == value_start || c.tokens[operator_index].kind != .PunctAssign { ret Unsupported }
    let token = c.tokens[place.token_start]
    let name = g.modules[module_index].text[token.start..token.end]
    let (local_index, found) = find_local(c, name)
    if !found { ret Unsupported }
    if !c.locals[local_index].mutable { ret ImmutableAssignment }
    let (actual, expression_error) = check_expr(c, g, tree, module_index, children[1usize], c.locals[local_index].ty)
    ret expression_error
}

fn check_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, function: Function) -> err {
    let node = tree.nodes[node_index]
    if node.kind == .Block { ret check_block(c, r, g, tree, module_index, node, function) }
    if node.kind == .BindingStmt { ret check_binding(c, r, g, tree, module_index, node) }
    if node.kind == .ReturnStmt { ret check_return(c, g, tree, module_index, node, function) }
    if node.kind == .IfStmt || node.kind == .WhileStmt { ret check_condition_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .CallStmt { ret check_call_statement(c, g, tree, module_index, node) }
    if node.kind == .AssignmentStmt { ret check_assignment(c, g, tree, module_index, node) }
    if node.kind == .NocheckStmt {
        let checkpoint = c.local_count
        let child_error = check_children(c, r, g, tree, module_index, node, function)
        c.local_count = checkpoint
        ret child_error
    }
    ret Unsupported
}

fn statement_returns(tree: *parse.Tree, node: syntax.Node) -> bool {
    if node.kind == .ReturnStmt { ret true }
    if node.kind == .Block {
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node && statement_returns(tree, tree.nodes[tree.children[at].index]) { ret true }
            at += 1usize
        }
        ret false
    }
    if node.kind == .IfStmt {
        let end = node.first_child + node.child_count
        var branch_count = 0usize
        var returning_count = 0usize
        var first = true
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if first {
                    first = false
                } else {
                    branch_count += 1usize
                    if statement_returns(tree, tree.nodes[tree.children[at].index]) { returning_count += 1usize }
                }
            }
            at += 1usize
        }
        ret branch_count == 2usize && returning_count == 2usize
    }
    ret false
}

fn check_function(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (name, name_error) = function_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (function_index, found) = find_function(c, module_index, name)
    if !found { ret UnknownCallable }
    let function = c.functions[function_index]
    if function.generic { ret Unsupported }
    if function.return_type.kind == .Other { ret Unsupported }
    c.local_count = 0usize
    var parameter_index = 0usize
    while parameter_index < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_index]
        if parameter.ty.kind == .Other { ret Unsupported }
        try add_local(c, parameter.name, parameter.ty, false)
        parameter_index += 1usize
    }
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .Block {
                let body_error = check_block(c, r, g, tree, module_index, child, function)
                if body_error != ok { ret body_error }
                if function.return_count != 0usize && !statement_returns(tree, child) { ret MissingReturn }
                ret ok
            }
        }
        at += 1usize
    }
    ret ok
}

fn check_bodies(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try parse.init_tree(&tree, g.nodes, g.children)
        try parse.parse(&tree, g.modules[module_index].text)
        try tokenize(c, g.modules[module_index].text)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .FnDecl { try check_function(c, r, g, &tree, module_index, node) }
            node_index += 1usize
        }
        module_index += 1usize
    }
    ret ok
}

fn run(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    try collect_signatures(c, r, g)
    ret check_bodies(c, r, g)
}
