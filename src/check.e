// Type-checking foundation. Unsupported forms fail explicitly.

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
error AliasCycle
error ConstantCycle
error ConstantOverflow
error InvalidConstant
error InvalidTry

type Kind = enum u8 {
    Invalid,
    Void,
    Bool,
    Err,
    Integer,
    Float,
    String,
    Named,
    Pointer,
    Slice,
    Array,
    TypeParameter,
    UntypedInteger,
    UntypedFloat,
    Other,
}

type Type = struct {
    kind: Kind,
    name: str,
    module_index: usize,
    element: usize,
    has_element: bool,
    is_const: bool,
    array_length: usize,
    has_length: bool,
}

type ComptimeKind = enum u8 {
    Type,
    Integer,
}

type ComptimeParameter = struct {
    name: str,
    kind: ComptimeKind,
    ty: Type,
}

type GenericArgument = struct {
    kind: ComptimeKind,
    ty: Type,
    value: usize,
    set: bool,
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
    first_return: usize,
    return_count: usize,
    generic: bool,
    external: bool,
}

type FunctionGeneric = struct {
    first_comptime: usize,
    comptime_count: usize,
    template_index: usize,
    first_argument: usize,
    instance: bool,
    checked: bool,
}

type Local = struct {
    name: str,
    ty: Type,
    mutable: bool,
}

type Alias = struct {
    name: str,
    module_index: usize,
    generic: bool,
    rhs: Type,
    resolved: Type,
    state: u8,
}

type IntegerValue = struct {
    magnitude: usize,
    negative: bool,
}

type ConstantExprKind = enum u8 {
    Literal,
    Name,
    Unary,
    Binary,
}

type ConstantExpr = struct {
    kind: ConstantExprKind,
    module_index: usize,
    name: str,
    value: IntegerValue,
    ty: Type,
    op: lex.Kind,
    left: usize,
    right: usize,
    has_right: bool,
}

type Constant = struct {
    name: str,
    module_index: usize,
    ty: Type,
    expression: usize,
    value: IntegerValue,
    state: u8,
}

type Checker = struct {
    resolver: *resolve.Resolver,
    functions: []Function,
    function_generics: []FunctionGeneric,
    parameters: []Parameter,
    return_types: []Type,
    comptime_parameters: []ComptimeParameter,
    generic_arguments: []GenericArgument,
    tokens: []lex.Token,
    locals: []Local,
    types: []Type,
    aliases: []Alias,
    constants: []Constant,
    constant_exprs: []ConstantExpr,
    function_count: usize,
    parameter_count: usize,
    return_type_count: usize,
    comptime_parameter_count: usize,
    generic_argument_count: usize,
    signature_function_count: usize,
    token_count: usize,
    local_count: usize,
    type_count: usize,
    alias_count: usize,
    constant_count: usize,
    constant_expr_count: usize,
    constants_ready: bool,
    expand_aliases: bool,
    active_first_comptime: usize,
    active_comptime_count: usize,
    active_first_argument: usize,
    active_arguments: bool,
}

fn init(c: *Checker, functions: []Function, parameters: []Parameter, return_types: []Type, tokens: []lex.Token, locals: []Local, types: []Type, aliases: []Alias, constants: []Constant, constant_exprs: []ConstantExpr) -> err {
    if functions.len == 0usize || parameters.len == 0usize || return_types.len == 0usize || tokens.len == 0usize || locals.len == 0usize || types.len == 0usize || aliases.len == 0usize || constants.len == 0usize || constant_exprs.len == 0usize { ret Capacity }
    c.functions = functions
    c.parameters = parameters
    c.return_types = return_types
    c.tokens = tokens
    c.locals = locals
    c.types = types
    c.aliases = aliases
    c.constants = constants
    c.constant_exprs = constant_exprs
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    c.signature_function_count = 0usize
    c.token_count = 0usize
    c.local_count = 0usize
    c.type_count = 0usize
    c.alias_count = 0usize
    c.constant_count = 0usize
    c.constant_expr_count = 0usize
    c.constants_ready = false
    c.expand_aliases = false
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.active_first_argument = 0usize
    c.active_arguments = false
    ret ok
}

fn init_generics(c: *Checker, functions: []FunctionGeneric, parameters: []ComptimeParameter, arguments: []GenericArgument) -> err {
    if functions.len < c.functions.len || parameters.len == 0usize || arguments.len == 0usize { ret Capacity }
    c.function_generics = functions
    c.comptime_parameters = parameters
    c.generic_arguments = arguments
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
    ret Type { kind: kind, name: name, module_index: module_index, element: 0usize, has_element: false, is_const: false, array_length: 0usize, has_length: false }
}

fn store_type(c: *Checker, ty: Type) -> (usize, err) {
    if c.type_count == c.types.len { ret (0usize, Capacity) }
    c.types[c.type_count] = ty
    let index = c.type_count
    c.type_count += 1usize
    ret (index, ok)
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

fn is_string_shape(c: *Checker, ty: Type) -> bool {
    if ty.kind == .String { ret true }
    if ty.kind != .Slice || !ty.is_const || !ty.has_element || ty.element >= c.type_count { ret false }
    let element = c.types[ty.element]
    ret element.kind == .Integer && same(element.name, "u8")
}

fn type_equal(c: *Checker, a: Type, b: Type) -> bool {
    if is_string_shape(c, a) || is_string_shape(c, b) { ret is_string_shape(c, a) && is_string_shape(c, b) }
    if a.kind != b.kind { ret false }
    if a.kind == .Named { ret a.module_index == b.module_index && same(a.name, b.name) }
    if a.kind == .TypeParameter { ret a.has_element && b.has_element && a.element == b.element }
    if a.kind == .Integer || a.kind == .Float { ret same(a.name, b.name) }
    if a.kind == .Pointer || a.kind == .Slice {
        if a.is_const != b.is_const || !a.has_element || !b.has_element { ret false }
        if a.element >= c.type_count || b.element >= c.type_count { ret false }
        ret type_equal(c, c.types[a.element], c.types[b.element])
    }
    if a.kind == .Array {
        if !a.has_length || !b.has_length || a.array_length != b.array_length || !a.has_element || !b.has_element { ret false }
        if a.element >= c.type_count || b.element >= c.type_count { ret false }
        ret type_equal(c, c.types[a.element], c.types[b.element])
    }
    if a.kind == .Other || a.kind == .Invalid { ret false }
    ret true
}

fn type_assignable(c: *Checker, actual: Type, expected: Type) -> bool {
    if type_equal(c, actual, expected) { ret true }
    if actual.kind == expected.kind && (actual.kind == .Pointer || actual.kind == .Slice) {
        if actual.is_const || !expected.is_const || !actual.has_element || !expected.has_element { ret false }
        if actual.element >= c.type_count || expected.element >= c.type_count { ret false }
        ret type_equal(c, c.types[actual.element], c.types[expected.element])
    }
    if expected.kind == .String && actual.kind == .Slice && !actual.is_const && actual.has_element && actual.element < c.type_count {
        let element = c.types[actual.element]
        ret element.kind == .Integer && same(element.name, "u8")
    }
    ret false
}

fn apply_context(c: *Checker, actual: Type, expected: Type) -> (Type, err) {
    if expected.kind == .Invalid { ret (actual, ok) }
    if actual.kind == .UntypedInteger && expected.kind == .Integer { ret (expected, ok) }
    if actual.kind == .UntypedFloat && expected.kind == .Float { ret (expected, ok) }
    if type_assignable(c, actual, expected) { ret (expected, ok) }
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

fn active_comptime_parameter(c: *Checker, name: str) -> (usize, bool) {
    var at = 0usize
    while at < c.active_comptime_count {
        let index = c.active_first_comptime + at
        if index < c.comptime_parameter_count && same(c.comptime_parameters[index].name, name) { ret (index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn active_argument(c: *Checker, parameter_index: usize) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    if !c.active_arguments || parameter_index < c.active_first_comptime { ret (empty, false) }
    let offset = parameter_index - c.active_first_comptime
    if offset >= c.active_comptime_count { ret (empty, false) }
    let argument_index = c.active_first_argument + offset
    if argument_index >= c.generic_argument_count || !c.generic_arguments[argument_index].set { ret (empty, false) }
    ret (c.generic_arguments[argument_index], true)
}

fn is_type_node(kind: syntax.Kind) -> bool {
    ret kind == .NamedType || kind == .PointerType || kind == .SliceType || kind == .ArrayType || kind == .FunctionType
}

fn find_alias(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    var at = 0usize
    while at < c.alias_count {
        if c.aliases[at].module_index == module_index && same(c.aliases[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn canonical_type(c: *Checker, ty: Type) -> (Type, err) {
    if ty.kind == .Named {
        let (alias_index, found) = find_alias(c, ty.module_index, ty.name)
        if !found { ret (ty, ok) }
        if c.aliases[alias_index].generic { ret (invalid_type(), Unsupported) }
        if c.aliases[alias_index].state == 2u8 { ret (c.aliases[alias_index].resolved, ok) }
        if c.aliases[alias_index].state == 1u8 { ret (invalid_type(), AliasCycle) }
        c.aliases[alias_index].state = 1u8
        let (resolved, resolve_error) = canonical_type(c, c.aliases[alias_index].rhs)
        if resolve_error != ok { ret (invalid_type(), resolve_error) }
        c.aliases[alias_index].resolved = resolved
        c.aliases[alias_index].state = 2u8
        ret (resolved, ok)
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), InvalidType) }
        let (element, element_error) = canonical_type(c, c.types[ty.element])
        if element_error != ok { ret (invalid_type(), element_error) }
        if (ty.kind == .Slice || ty.kind == .Array) && element.kind == .Void { ret (invalid_type(), InvalidType) }
        let (element_index, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var resolved = ty
        resolved.element = element_index
        ret (resolved, ok)
    }
    ret (ty, ok)
}

fn composite_const(c: *Checker, node: syntax.Node, child: syntax.Node) -> (bool, err) {
    var is_const = false
    var at = node.token_start
    while at < child.token_start {
        if c.tokens[at].kind == .KwConst { is_const = true }
        if c.tokens[at].kind == .KwShared { ret (false, Unsupported) }
        at += 1usize
    }
    ret (is_const, ok)
}

fn integer_digit(byte: u8) -> (usize, bool) {
    let digits = "0123456789abcdef"
    var lower = byte
    if lower >= 65u8 && lower <= 70u8 { lower += 32u8 }
    var at = 0usize
    while at < digits.len {
        if digits[at] == lower { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn integer_literal_value(c: *Checker, text: str, node: syntax.Node) -> (usize, Type, err) {
    if node.kind != .LiteralExpr { ret (0usize, invalid_type(), Unsupported) }
    let token = c.tokens[node.token_start]
    if token.kind != .Integer { ret (0usize, invalid_type(), TypeMismatch) }
    let parsed_type = numeric_literal_type(text, token)
    let spelling = text[token.start..token.end]
    var base = 10usize
    var at = 0usize
    if spelling.len >= 2usize && spelling[0usize] == 48u8 {
        let prefix = spelling[1usize]
        if prefix == 120u8 || prefix == 88u8 {
            base = 16usize
            at = 2usize
        } else {
            if prefix == 111u8 || prefix == 79u8 {
                base = 8usize
                at = 2usize
            } else {
                if prefix == 98u8 || prefix == 66u8 {
                    base = 2usize
                    at = 2usize
                }
            }
        }
    }
    var value = 0usize
    var digits = 0usize
    let max_value = 18446744073709551615usize
    while at < spelling.len {
        let byte = spelling[at]
        if byte == 95u8 {
            at += 1usize
        } else {
            let (digit, is_digit) = integer_digit(byte)
            if !is_digit || digit >= base { break }
            digits += 1usize
            if value > (max_value - digit) / base { ret (0usize, invalid_type(), ConstantOverflow) }
            value = value * base + digit
            at += 1usize
        }
    }
    if digits == 0usize { ret (0usize, invalid_type(), Unsupported) }
    ret (value, parsed_type, ok)
}

fn array_length_literal(c: *Checker, text: str, node: syntax.Node) -> (usize, err) {
    let (value, length_type, value_error) = integer_literal_value(c, text, node)
    if value_error == ConstantOverflow { ret (0usize, TypeMismatch) }
    if value_error != ok { ret (0usize, value_error) }
    if length_type.kind == .Integer && !same(length_type.name, "usize") { ret (0usize, TypeMismatch) }
    ret (value, ok)
}

fn constant_array_length(c: *Checker, constant_index: usize) -> (usize, err) {
    if !c.constants_ready || constant_index >= c.constant_count { ret (0usize, Unsupported) }
    let item = c.constants[constant_index]
    if item.state != 2u8 { ret (0usize, InvalidConstant) }
    if item.ty.kind != .Integer || !same(item.ty.name, "usize") { ret (0usize, TypeMismatch) }
    if item.value.negative { ret (0usize, TypeMismatch) }
    ret (item.value.magnitude, ok)
}

fn array_length_value(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if node.kind == .LiteralExpr {
        let (value, value_error) = array_length_literal(c, text, node)
        ret (value, value_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (0usize, InvalidConstant) }
        let name = text[token.start..token.end]
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind != .Integer { ret (0usize, TypeMismatch) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found { ret (0usize, Unsupported) }
            ret (argument.value, ok)
        }
        if !c.constants_ready { ret (0usize, Unsupported) }
        let (constant_index, found) = find_constant(c, module_index, name)
        if !found { ret (0usize, InvalidConstant) }
        let (value, value_error) = constant_array_length(c, constant_index)
        ret (value, value_error)
    }
    if node.kind == .FieldExpr {
        if !c.constants_ready { ret (0usize, Unsupported) }
        let (target_module, member, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (0usize, InvalidConstant) }
        let (constant_index, constant_found) = find_constant(c, target_module, member)
        if !constant_found { ret (0usize, InvalidConstant) }
        let (value, value_error) = constant_array_length(c, constant_index)
        ret (value, value_error)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (0usize, parse.InvalidSyntax) }
        let (value, value_error) = array_length_value(c, g, tree, module_index, child_index)
        ret (value, value_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (0usize, parse.InvalidSyntax) }
        let (value, value_error) = array_length_value(c, g, tree, module_index, child_index)
        if value_error != ok { ret (0usize, value_error) }
        let op = c.tokens[node.token_start].kind
        if op == .PunctMinus {
            if value == 0usize { ret (0usize, ok) }
            ret (0usize, TypeMismatch)
        }
        if op == .PunctTilde { ret (18446744073709551615usize - value, ok) }
        ret (0usize, Unsupported)
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var count = 0usize
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if count == 2usize { ret (0usize, parse.InvalidSyntax) }
                children[count] = tree.children[at].index
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (0usize, parse.InvalidSyntax) }
        let (left, left_error) = array_length_value(c, g, tree, module_index, children[0usize])
        if left_error != ok { ret (0usize, left_error) }
        let (right, right_error) = array_length_value(c, g, tree, module_index, children[1usize])
        if right_error != ok { ret (0usize, right_error) }
        let op = binary_operator(c, tree, node)
        let max_value = 18446744073709551615usize
        if op == .PunctPlus {
            if left > max_value - right { ret (0usize, TypeMismatch) }
            ret (left + right, ok)
        }
        if op == .PunctMinus {
            if left < right { ret (0usize, TypeMismatch) }
            ret (left - right, ok)
        }
        if op == .PunctStar {
            if right != 0usize && left > max_value / right { ret (0usize, TypeMismatch) }
            ret (left * right, ok)
        }
        if op == .PunctSlash {
            if right == 0usize { ret (0usize, TypeMismatch) }
            ret (left / right, ok)
        }
        if op == .PunctPercent {
            if right == 0usize { ret (0usize, TypeMismatch) }
            ret (left % right, ok)
        }
        ret (0usize, Unsupported)
    }
    ret (0usize, Unsupported)
}

fn type_from_node(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    if node.kind == .PointerType || node.kind == .SliceType {
        let (child_index, has_child) = first_node_child(tree, node)
        if !has_child { ret (invalid_type(), parse.InvalidSyntax) }
        let child = tree.nodes[child_index]
        let (element_type, element_error) = type_from_node(c, r, g, tree, module_index, child)
        if element_error != ok { ret (invalid_type(), element_error) }
        if node.kind == .SliceType && element_type.kind == .Void { ret (invalid_type(), InvalidType) }
        let (element_index, store_error) = store_type(c, element_type)
        if store_error != ok { ret (invalid_type(), store_error) }
        let (is_const, qualifier_error) = composite_const(c, node, child)
        if qualifier_error != ok { ret (invalid_type(), qualifier_error) }
        var result = make_type(.Pointer, "", module_index)
        if node.kind == .SliceType { result.kind = .Slice }
        result.element = element_index
        result.has_element = true
        result.is_const = is_const
        ret (result, ok)
    }
    if node.kind == .ArrayType {
        let end = node.first_child + node.child_count
        var element_index = 0usize
        var has_element = false
        var length_index = 0usize
        var has_length = false
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                let child_index = tree.children[at].index
                if is_type_node(tree.nodes[child_index].kind) {
                    element_index = child_index
                    has_element = true
                } else {
                    length_index = child_index
                    has_length = true
                }
            }
            at += 1usize
        }
        if !has_element { ret (invalid_type(), parse.InvalidSyntax) }
        if !has_length { ret (invalid_type(), Unsupported) }
        let (element_type, element_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[element_index])
        if element_error != ok { ret (invalid_type(), element_error) }
        if element_type.kind == .Void { ret (invalid_type(), InvalidType) }
        let (stored_element, store_error) = store_type(c, element_type)
        if store_error != ok { ret (invalid_type(), store_error) }
        var length = 0usize
        var has_concrete_length = false
        var length_expression = 0usize
        let (resolved_length, length_error) = array_length_value(c, g, tree, module_index, length_index)
        if length_error == ok {
            length = resolved_length
            has_concrete_length = true
        } else {
            if c.active_comptime_count == 0usize || c.active_arguments { ret (invalid_type(), length_error) }
            let (copied_expression, expression_error) = copy_constant_expr(c, g, tree, module_index, length_index)
            if expression_error != ok { ret (invalid_type(), length_error) }
            length_expression = copied_expression
        }
        var result = make_type(.Array, "", module_index)
        result.element = stored_element
        result.has_element = true
        result.array_length = length
        if !has_concrete_length { result.array_length = length_expression }
        result.has_length = has_concrete_length
        ret (result, ok)
    }
    if node.kind != .NamedType { ret (make_type(.Other, "", module_index), Unsupported) }
    let first = c.tokens[node.token_start]
    if first.kind != .Identifier { ret (make_type(.Other, "", module_index), Unsupported) }
    let base = g.modules[module_index].text[first.start..first.end]
    let scalar = scalar_type(base, module_index)
    if scalar.kind != .Invalid { ret (scalar, ok) }
    let (parameter_index, parameter_found) = active_comptime_parameter(c, base)
    if parameter_found {
        if c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), InvalidType) }
        let (argument, argument_found) = active_argument(c, parameter_index)
        if argument_found { ret (argument.ty, ok) }
        var parameter_type = make_type(.TypeParameter, base, module_index)
        parameter_type.element = parameter_index
        parameter_type.has_element = true
        ret (parameter_type, ok)
    }
    var target_module = module_index
    var name = base
    var saw_dot = false
    var at = node.token_start + 1usize
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .PunctLBracket { ret (make_type(.Other, "", module_index), Unsupported) }
        if token.kind == .PunctDot {
            saw_dot = true
        } else {
            if saw_dot && token.kind == .Identifier {
                let (qualified_module, found) = resolve.qualifier(r, module_index, base)
                if found {
                    target_module = qualified_module
                    name = g.modules[module_index].text[token.start..token.end]
                }
                let result = make_type(.Named, name, target_module)
                if !c.expand_aliases { ret (result, ok) }
                let (canonical, canonical_error) = canonical_type(c, result)
                ret (canonical, canonical_error)
            }
        }
        at += 1usize
    }
    let result = make_type(.Named, name, target_module)
    if !c.expand_aliases { ret (result, ok) }
    let (canonical, canonical_error) = canonical_type(c, result)
    ret (canonical, canonical_error)
}

fn declaration_name(c: *Checker, text: str, node: syntax.Node) -> (str, err) {
    let name_index = node.token_start + 1usize
    if name_index >= node.token_end || name_index >= c.token_count { ret ("", parse.InvalidSyntax) }
    let token = c.tokens[name_index]
    if token.kind != .Identifier { ret ("", parse.InvalidSyntax) }
    ret (text[token.start..token.end], ok)
}

fn collect_alias_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, allow_deferred: bool) -> err {
    let end = node.first_child + node.child_count
    var rhs_index = 0usize
    var has_rhs = false
    var generic = false
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind == .ComptimeParam { generic = true }
            if is_type_node(child.kind) {
                rhs_index = child_index
                has_rhs = true
            }
        }
        at += 1usize
    }
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    if generic {
        if c.alias_count == c.aliases.len { ret Capacity }
        c.aliases[c.alias_count] = Alias { name: name, module_index: module_index, generic: true, rhs: invalid_type(), resolved: invalid_type(), state: 0u8 }
        c.alias_count += 1usize
        ret ok
    }
    if !has_rhs { ret ok }
    if c.alias_count == c.aliases.len { ret Capacity }
    var (rhs, rhs_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[rhs_index])
    if rhs_error != ok {
        if !allow_deferred || rhs_error != Unsupported { ret rhs_error }
        rhs = make_type(.Other, "", module_index)
    }
    c.aliases[c.alias_count] = Alias { name: name, module_index: module_index, generic: false, rhs: rhs, resolved: invalid_type(), state: 0u8 }
    c.alias_count += 1usize
    ret ok
}

fn collect_aliases(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, allow_deferred: bool) -> err {
    c.alias_count = 0usize
    c.type_count = 0usize
    c.expand_aliases = false
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try parse.init_tree(&tree, g.nodes, g.children)
        try parse.parse(&tree, g.modules[module_index].text)
        try tokenize(c, g.modules[module_index].text)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .TypeDecl { try collect_alias_declaration(c, r, g, &tree, module_index, node, allow_deferred) }
            node_index += 1usize
        }
        module_index += 1usize
    }
    c.expand_aliases = true
    if allow_deferred { ret ok }
    var alias_index = 0usize
    while alias_index < c.alias_count {
        if !c.aliases[alias_index].generic {
            let (resolved, resolve_error) = canonical_type(c, c.aliases[alias_index].rhs)
            if resolve_error != ok { ret resolve_error }
            c.aliases[alias_index].resolved = resolved
            c.aliases[alias_index].state = 2u8
        }
        alias_index += 1usize
    }
    ret ok
}

fn collect_parameter(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.parameter_count == c.parameters.len { ret Capacity }
    let (name, has_name) = first_name(c, g.modules[module_index].text, node)
    if !has_name { ret Unsupported }
    let (type_index, has_type) = first_node_child(tree, node)
    if !has_type { ret Unsupported }
    let (ty, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
    if type_error != ok { ret type_error }
    if ty.kind == .Void { ret InvalidType }
    c.parameters[c.parameter_count] = Parameter { name: name, ty: ty }
    c.parameter_count += 1usize
    ret ok
}

fn collect_comptime_parameter(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.comptime_parameter_count == c.comptime_parameters.len { ret Capacity }
    let (name, has_name) = first_name(c, g.modules[module_index].text, node)
    if !has_name { ret parse.InvalidSyntax }
    var saw_colon = false
    var kind_found = false
    var at = node.token_start
    while at < node.token_end {
        let token_kind = c.tokens[at].kind
        if token_kind == .PunctColon {
            saw_colon = true
        } else {
            if saw_colon && token_kind != .Newline {
                if token_kind == .KwType {
                    kind_found = true
                } else {
                    if token_kind == .KwFn { ret Unsupported }
                }
                break
            }
        }
        at += 1usize
    }
    if kind_found {
        c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Type, ty: invalid_type() }
        c.comptime_parameter_count += 1usize
        ret ok
    }
    let (type_index, has_type) = first_node_child(tree, node)
    if !has_type { ret Unsupported }
    let (ty, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
    if type_error != ok { ret type_error }
    if ty.kind != .Integer || !same(ty.name, "usize") { ret InvalidType }
    c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Integer, ty: ty }
    c.comptime_parameter_count += 1usize
    ret ok
}

fn store_return_type(c: *Checker, ty: Type) -> err {
    if c.return_type_count == c.return_types.len { ret Capacity }
    c.return_types[c.return_type_count] = ty
    c.return_type_count += 1usize
    ret ok
}

fn collect_function(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.function_count == c.functions.len { ret Capacity }
    let (name, name_error) = function_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    var item: Function = zero
    item.name = name
    item.module_index = module_index
    item.first_parameter = c.parameter_count
    item.first_return = c.return_type_count
    item.external = node.kind == .ExternDecl
    var generic: FunctionGeneric = zero
    generic.first_comptime = c.comptime_parameter_count
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .ComptimeParam {
                c.active_first_comptime = generic.first_comptime
                c.active_comptime_count = generic.comptime_count
                try collect_comptime_parameter(c, r, g, tree, module_index, child)
                generic.comptime_count += 1usize
                item.generic = true
            }
        }
        at += 1usize
    }
    c.active_first_comptime = generic.first_comptime
    c.active_comptime_count = generic.comptime_count
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .Parameter {
                try collect_parameter(c, r, g, tree, module_index, child)
                item.parameter_count += 1usize
            }
            if child.kind == .ReturnSpec {
                let return_end = child.first_child + child.child_count
                var return_at = child.first_child
                while return_at < return_end {
                    if tree.children[return_at].node {
                        let (return_type, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[tree.children[return_at].index])
                        if type_error != ok { ret type_error }
                        try store_return_type(c, return_type)
                        item.return_count += 1usize
                    }
                    return_at += 1usize
                }
            }
        }
        at += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    if item.return_count == 1usize && c.return_types[item.first_return].kind == .Void {
        item.return_count = 0usize
        c.return_type_count = c.return_type_count - 1usize
    }
    if item.external && item.return_count > 1usize { ret InvalidType }
    var return_index = 0usize
    while return_index < item.return_count {
        let return_type = c.return_types[item.first_return + return_index]
        if return_type.kind == .Void { ret InvalidType }
        if item.external && return_type.kind == .Err { ret InvalidType }
        if return_type.kind == .Err && return_index + 1usize != item.return_count { ret InvalidType }
        return_index += 1usize
    }
    c.functions[c.function_count] = item
    c.function_generics[c.function_count] = generic
    c.function_count += 1usize
    ret ok
}

fn seeded_composite_type(c: *Checker, kind: Kind, element: Type, is_const: bool, module_index: usize) -> (Type, err) {
    let (element_index, store_error) = store_type(c, element)
    if store_error != ok { ret (invalid_type(), store_error) }
    var result = make_type(kind, "", module_index)
    result.element = element_index
    result.has_element = true
    result.is_const = is_const
    ret (result, ok)
}

fn add_seeded_function(c: *Checker, module_index: usize, name: str, return_type: Type, fallible: bool) -> (usize, err) {
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    let index = c.function_count
    var return_count = 0usize
    let first_return = c.return_type_count
    if return_type.kind != .Void {
        let store_error = store_return_type(c, return_type)
        if store_error != ok { ret (0usize, store_error) }
        return_count = 1usize
    }
    if fallible {
        let store_error = store_return_type(c, make_type(.Err, "err", module_index))
        if store_error != ok { ret (0usize, store_error) }
        return_count += 1usize
    }
    var item: Function = zero
    item.name = name
    item.module_index = module_index
    item.first_parameter = c.parameter_count
    item.first_return = first_return
    item.return_count = return_count
    c.functions[index] = item
    c.function_generics[index] = zero
    c.function_count += 1usize
    ret (index, ok)
}

fn add_seeded_parameter(c: *Checker, function_index: usize, name: str, ty: Type) -> err {
    if function_index >= c.function_count || c.parameter_count == c.parameters.len { ret Capacity }
    c.parameters[c.parameter_count] = Parameter { name: name, ty: ty }
    c.parameter_count += 1usize
    c.functions[function_index].parameter_count += 1usize
    ret ok
}

fn seed_memory_signatures(c: *Checker, module_index: usize) -> err {
    let arena = make_type(.Named, "Arena", module_index)
    let stats = make_type(.Named, "Stats", module_index)
    let usize_type = make_type(.Integer, "usize", module_index)
    let (arena_pointer, pointer_error) = seeded_composite_type(c, .Pointer, arena, false, module_index)
    if pointer_error != ok { ret pointer_error }
    let (mark_index, mark_error) = add_seeded_function(c, module_index, "mark", usize_type, false)
    if mark_error != ok { ret mark_error }
    try add_seeded_parameter(c, mark_index, "a", arena_pointer)
    let (reset_index, reset_error) = add_seeded_function(c, module_index, "reset", make_type(.Void, "void", module_index), false)
    if reset_error != ok { ret reset_error }
    try add_seeded_parameter(c, reset_index, "a", arena_pointer)
    try add_seeded_parameter(c, reset_index, "m", usize_type)
    let (stats_index, stats_error) = add_seeded_function(c, module_index, "stats", stats, false)
    if stats_error != ok { ret stats_error }
    try add_seeded_parameter(c, stats_index, "a", arena_pointer)
    ret ok
}

fn seed_os_signatures(c: *Checker, os_module: usize, mem_module: usize, has_memory: bool) -> err {
    let file = make_type(.Named, "File", os_module)
    let process = make_type(.Named, "Proc", os_module)
    let clock = make_type(.Named, "Clock", os_module)
    let entry = make_type(.Named, "DirEntry", os_module)
    let flags = make_type(.Named, "OpenFlags", os_module)
    let stdio = make_type(.Named, "Stdio", os_module)
    let u8_type = make_type(.Integer, "u8", os_module)
    let usize_type = make_type(.Integer, "usize", os_module)
    let i32_type = make_type(.Integer, "i32", os_module)
    let i64_type = make_type(.Integer, "i64", os_module)
    let string_type = make_type(.String, "str", os_module)
    let error_type = make_type(.Err, "err", os_module)
    let (bytes, bytes_error) = seeded_composite_type(c, .Slice, u8_type, false, os_module)
    if bytes_error != ok { ret bytes_error }
    let (entries, entries_error) = seeded_composite_type(c, .Slice, entry, false, os_module)
    if entries_error != ok { ret entries_error }
    let (strings, strings_error) = seeded_composite_type(c, .Slice, string_type, false, os_module)
    if strings_error != ok { ret strings_error }
    let (const_strings, const_strings_error) = seeded_composite_type(c, .Slice, string_type, true, os_module)
    if const_strings_error != ok { ret const_strings_error }
    let (byte_pointer, byte_pointer_error) = seeded_composite_type(c, .Pointer, u8_type, false, os_module)
    if byte_pointer_error != ok { ret byte_pointer_error }

    let (read_index, read_error) = add_seeded_function(c, os_module, "read", usize_type, true)
    if read_error != ok { ret read_error }
    try add_seeded_parameter(c, read_index, "f", file)
    try add_seeded_parameter(c, read_index, "buf", bytes)
    let (write_index, write_error) = add_seeded_function(c, os_module, "write", usize_type, true)
    if write_error != ok { ret write_error }
    try add_seeded_parameter(c, write_index, "f", file)
    try add_seeded_parameter(c, write_index, "buf", string_type)
    let (close_index, close_error) = add_seeded_function(c, os_module, "close", error_type, false)
    if close_error != ok { ret close_error }
    try add_seeded_parameter(c, close_index, "f", file)
    let (stdout_index, stdout_error) = add_seeded_function(c, os_module, "stdout", file, false)
    if stdout_error != ok { ret stdout_error }
    let (stderr_index, stderr_error) = add_seeded_function(c, os_module, "stderr", file, false)
    if stderr_error != ok { ret stderr_error }
    let (wait_index, wait_error) = add_seeded_function(c, os_module, "wait", i32_type, true)
    if wait_error != ok { ret wait_error }
    try add_seeded_parameter(c, wait_index, "p", process)
    let (exit_index, exit_error) = add_seeded_function(c, os_module, "exit", make_type(.Void, "void", os_module), false)
    if exit_error != ok { ret exit_error }
    try add_seeded_parameter(c, exit_index, "code", i32_type)
    let (reserve_index, reserve_error) = add_seeded_function(c, os_module, "reserve", byte_pointer, true)
    if reserve_error != ok { ret reserve_error }
    try add_seeded_parameter(c, reserve_index, "n", usize_type)
    let (commit_index, commit_error) = add_seeded_function(c, os_module, "commit", error_type, false)
    if commit_error != ok { ret commit_error }
    try add_seeded_parameter(c, commit_index, "p", byte_pointer)
    try add_seeded_parameter(c, commit_index, "n", usize_type)
    let (clock_index, clock_error) = add_seeded_function(c, os_module, "clock", i64_type, true)
    if clock_error != ok { ret clock_error }
    try add_seeded_parameter(c, clock_index, "c", clock)

    if has_memory {
        let arena = make_type(.Named, "Arena", mem_module)
        let (arena_pointer, arena_pointer_error) = seeded_composite_type(c, .Pointer, arena, false, os_module)
        if arena_pointer_error != ok { ret arena_pointer_error }
        let (open_index, open_error) = add_seeded_function(c, os_module, "open", file, true)
        if open_error != ok { ret open_error }
        try add_seeded_parameter(c, open_index, "a", arena_pointer)
        try add_seeded_parameter(c, open_index, "path", string_type)
        try add_seeded_parameter(c, open_index, "flags", flags)
        let (readdir_index, readdir_error) = add_seeded_function(c, os_module, "readdir", entries, true)
        if readdir_error != ok { ret readdir_error }
        try add_seeded_parameter(c, readdir_index, "a", arena_pointer)
        try add_seeded_parameter(c, readdir_index, "path", string_type)
        let (spawn_index, spawn_error) = add_seeded_function(c, os_module, "spawn", process, true)
        if spawn_error != ok { ret spawn_error }
        try add_seeded_parameter(c, spawn_index, "a", arena_pointer)
        try add_seeded_parameter(c, spawn_index, "argv", const_strings)
        try add_seeded_parameter(c, spawn_index, "stdio", stdio)
        let (args_index, args_error) = add_seeded_function(c, os_module, "args", strings, true)
        if args_error != ok { ret args_error }
        try add_seeded_parameter(c, args_index, "a", arena_pointer)
    }
    ret ok
}

fn seed_intrinsic_signatures(c: *Checker, g: *graph.Graph) -> err {
    let (mem_module, has_memory) = graph.find_module(g, "e.mem")
    if has_memory { try seed_memory_signatures(c, mem_module) }
    let (os_module, has_os) = graph.find_module(g, "e.os")
    if has_os { try seed_os_signatures(c, os_module, mem_module, has_memory) }
    ret ok
}

fn collect_signatures(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    c.signature_function_count = 0usize
    try seed_intrinsic_signatures(c, g)
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
    c.signature_function_count = c.function_count
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

fn find_constant(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    var at = 0usize
    while at < c.constant_count {
        if c.constants[at].module_index == module_index && same(c.constants[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn imported_module(g: *graph.Graph, module_index: usize, qualifier: str) -> (usize, bool) {
    let end = g.modules[module_index].first_import + g.modules[module_index].import_count
    var at = g.modules[module_index].first_import
    while at < end {
        if same(g.imports[at].qualifier, qualifier) { ret (g.imports[at].target, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn qualified_member(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (usize, str, bool) {
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret (0usize, "", false) }
    let base_node = tree.nodes[base_index]
    if base_node.kind != .NameExpr { ret (0usize, "", false) }
    let base_token = c.tokens[base_node.token_start]
    if base_token.kind != .Identifier { ret (0usize, "", false) }
    let text = g.modules[module_index].text
    let qualifier = text[base_token.start..base_token.end]
    let (target_module, imported) = imported_module(g, module_index, qualifier)
    if !imported { ret (0usize, "", false) }
    var member = ""
    var at = base_node.token_end
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .Identifier { member = text[token.start..token.end] }
        at += 1usize
    }
    if member.len == 0usize { ret (0usize, "", false) }
    ret (target_module, member, true)
}

fn find_qualified_function(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (usize, bool) {
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
    if !found_member { ret (0usize, false) }
    let (function_index, found) = find_function(c, target_module, member)
    ret (function_index, found)
}

fn store_constant_expr(c: *Checker, item: ConstantExpr) -> (usize, err) {
    if c.constant_expr_count == c.constant_exprs.len { ret (0usize, Capacity) }
    c.constant_exprs[c.constant_expr_count] = item
    let index = c.constant_expr_count
    c.constant_expr_count += 1usize
    ret (index, ok)
}

fn normalized_integer(magnitude: usize, negative: bool) -> IntegerValue {
    if magnitude == 0usize { ret IntegerValue { magnitude: 0usize, negative: false } }
    ret IntegerValue { magnitude: magnitude, negative: negative }
}

fn copy_constant_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    var item: ConstantExpr = zero
    if node.kind == .LiteralExpr {
        let (magnitude, parsed_type, literal_error) = integer_literal_value(c, text, node)
        if literal_error != ok { ret (0usize, literal_error) }
        item.kind = .Literal
        item.value = normalized_integer(magnitude, false)
        item.ty = parsed_type
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (0usize, InvalidConstant) }
        item.kind = .Name
        item.module_index = module_index
        item.name = text[token.start..token.end]
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, member, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (0usize, InvalidConstant) }
        item.kind = .Name
        item.module_index = target_module
        item.name = member
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (0usize, parse.InvalidSyntax) }
        let (copied_index, copy_error) = copy_constant_expr(c, g, tree, module_index, child_index)
        ret (copied_index, copy_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (0usize, parse.InvalidSyntax) }
        let (copied_index, copy_error) = copy_constant_expr(c, g, tree, module_index, child_index)
        if copy_error != ok { ret (0usize, copy_error) }
        item.kind = .Unary
        item.op = c.tokens[node.token_start].kind
        item.left = copied_index
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var count = 0usize
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if count == 2usize { ret (0usize, parse.InvalidSyntax) }
                children[count] = tree.children[at].index
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (0usize, parse.InvalidSyntax) }
        let (left_index, left_error) = copy_constant_expr(c, g, tree, module_index, children[0usize])
        if left_error != ok { ret (0usize, left_error) }
        let (right_index, right_error) = copy_constant_expr(c, g, tree, module_index, children[1usize])
        if right_error != ok { ret (0usize, right_error) }
        item.kind = .Binary
        item.op = binary_operator(c, tree, node)
        item.left = left_index
        item.right = right_index
        item.has_right = true
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    ret (0usize, Unsupported)
}

fn collect_constant_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.constant_count == c.constants.len { ret Capacity }
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    var declared_type = invalid_type()
    var expression_index = 0usize
    var has_expression = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if is_type_node(child.kind) {
                let (resolved_type, type_error) = type_from_node(c, r, g, tree, module_index, child)
                if type_error != ok { ret type_error }
                declared_type = resolved_type
            } else {
                expression_index = child_index
                has_expression = true
            }
        }
        at += 1usize
    }
    if !has_expression { ret parse.InvalidSyntax }
    let (copied_expression, expression_error) = copy_constant_expr(c, g, tree, module_index, expression_index)
    if expression_error != ok { ret expression_error }
    c.constants[c.constant_count] = Constant { name: name, module_index: module_index, ty: declared_type, expression: copied_expression, value: normalized_integer(0usize, false), state: 0u8 }
    c.constant_count += 1usize
    ret ok
}

fn add_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    if left.negative == right.negative {
        let max_value = 18446744073709551615usize
        if left.magnitude > max_value - right.magnitude { ret (normalized_integer(0usize, false), ConstantOverflow) }
        ret (normalized_integer(left.magnitude + right.magnitude, left.negative), ok)
    }
    if left.magnitude >= right.magnitude { ret (normalized_integer(left.magnitude - right.magnitude, left.negative), ok) }
    ret (normalized_integer(right.magnitude - left.magnitude, right.negative), ok)
}

fn subtract_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    let negated = normalized_integer(right.magnitude, !right.negative)
    let (result, result_error) = add_integer_values(left, negated)
    ret (result, result_error)
}

fn multiply_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    let max_value = 18446744073709551615usize
    if right.magnitude != 0usize && left.magnitude > max_value / right.magnitude { ret (normalized_integer(0usize, false), ConstantOverflow) }
    ret (normalized_integer(left.magnitude * right.magnitude, left.negative != right.negative), ok)
}

fn divide_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    if right.magnitude == 0usize { ret (normalized_integer(0usize, false), InvalidConstant) }
    ret (normalized_integer(left.magnitude / right.magnitude, left.negative != right.negative), ok)
}

fn remainder_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    if right.magnitude == 0usize { ret (normalized_integer(0usize, false), InvalidConstant) }
    ret (normalized_integer(left.magnitude % right.magnitude, left.negative), ok)
}

fn constant_result_type(c: *Checker, left: Type, right: Type) -> (Type, err) {
    if !is_integer(left) || !is_integer(right) { ret (invalid_type(), InvalidConstant) }
    if is_untyped(left) {
        if is_untyped(right) { ret (left, ok) }
        ret (right, ok)
    }
    if is_untyped(right) { ret (left, ok) }
    if !type_equal(c, left, right) { ret (invalid_type(), TypeMismatch) }
    ret (left, ok)
}

fn integer_representable(value: IntegerValue, ty: Type) -> bool {
    if ty.kind != .Integer { ret false }
    if same(ty.name, "u8") { ret !value.negative && value.magnitude <= 255usize }
    if same(ty.name, "u16") { ret !value.negative && value.magnitude <= 65535usize }
    if same(ty.name, "u32") { ret !value.negative && value.magnitude <= 4294967295usize }
    if same(ty.name, "u64") || same(ty.name, "usize") { ret !value.negative }
    if same(ty.name, "i8") {
        if value.negative { ret value.magnitude <= 128usize }
        ret value.magnitude <= 127usize
    }
    if same(ty.name, "i16") {
        if value.negative { ret value.magnitude <= 32768usize }
        ret value.magnitude <= 32767usize
    }
    if same(ty.name, "i32") {
        if value.negative { ret value.magnitude <= 2147483648usize }
        ret value.magnitude <= 2147483647usize
    }
    if same(ty.name, "i64") || same(ty.name, "isize") {
        if value.negative { ret value.magnitude <= 9223372036854775808usize }
        ret value.magnitude <= 9223372036854775807usize
    }
    ret false
}

fn unsigned_integer_type(ty: Type) -> bool {
    if ty.kind != .Integer { ret false }
    ret same(ty.name, "u8") || same(ty.name, "u16") || same(ty.name, "u32") || same(ty.name, "u64") || same(ty.name, "usize")
}

fn evaluate_constant_expr(c: *Checker, expression_index: usize) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .Literal { ret (expression.value, expression.ty, ok) }
    if expression.kind == .Name {
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        ret (c.constants[constant_index].value, c.constants[constant_index].ty, ok)
    }
    if expression.kind == .Unary {
        let (operand, operand_type, operand_error) = evaluate_constant_expr(c, expression.left)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op != .PunctMinus { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
        if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        ret (normalized_integer(operand.magnitude, !operand.negative), operand_type, ok)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        if expression.op != .PunctPlus && expression.op != .PunctMinus && expression.op != .PunctStar && expression.op != .PunctSlash && expression.op != .PunctPercent {
            ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
        }
        let (left, left_type, left_error) = evaluate_constant_expr(c, expression.left)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        let (right, right_type, right_error) = evaluate_constant_expr(c, expression.right)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        let (result_type, type_error) = constant_result_type(c, left_type, right_type)
        if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
        if result_type.kind == .Integer {
            if !integer_representable(left, result_type) || !integer_representable(right, result_type) {
                ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow)
            }
        }
        var result = normalized_integer(0usize, false)
        var result_error = ok
        if expression.op == .PunctPlus { (result, result_error) = add_integer_values(left, right) }
        if expression.op == .PunctMinus { (result, result_error) = subtract_integer_values(left, right) }
        if expression.op == .PunctStar { (result, result_error) = multiply_integer_values(left, right) }
        if expression.op == .PunctSlash { (result, result_error) = divide_integer_values(left, right) }
        if expression.op == .PunctPercent { (result, result_error) = remainder_integer_values(left, right) }
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}

fn evaluate_constant(c: *Checker, constant_index: usize) -> err {
    if constant_index >= c.constant_count { ret InvalidConstant }
    if c.constants[constant_index].state == 2u8 { ret ok }
    if c.constants[constant_index].state == 1u8 { ret ConstantCycle }
    c.constants[constant_index].state = 1u8
    let (value, actual_type, value_error) = evaluate_constant_expr(c, c.constants[constant_index].expression)
    if value_error != ok { ret value_error }
    var final_type = c.constants[constant_index].ty
    if final_type.kind == .Invalid {
        if actual_type.kind == .UntypedInteger { ret MissingContext }
        if actual_type.kind != .Integer { ret InvalidConstant }
        final_type = actual_type
    } else {
        if final_type.kind != .Integer { ret Unsupported }
        if actual_type.kind != .UntypedInteger && !type_equal(c, actual_type, final_type) { ret TypeMismatch }
    }
    if !integer_representable(value, final_type) { ret ConstantOverflow }
    c.constants[constant_index].ty = final_type
    c.constants[constant_index].value = value
    c.constants[constant_index].state = 2u8
    ret ok
}

fn collect_constants(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.constant_count = 0usize
    c.constant_expr_count = 0usize
    c.constants_ready = false
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try parse.init_tree(&tree, g.nodes, g.children)
        try parse.parse(&tree, g.modules[module_index].text)
        try tokenize(c, g.modules[module_index].text)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .ConstDecl { try collect_constant_declaration(c, r, g, &tree, module_index, node) }
            node_index += 1usize
        }
        module_index += 1usize
    }
    var constant_index = 0usize
    while constant_index < c.constant_count {
        try evaluate_constant(c, constant_index)
        constant_index += 1usize
    }
    c.constants_ready = true
    ret ok
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

fn template_parameter(c: *Checker, function_index: usize, name: str) -> (usize, bool) {
    if function_index >= c.signature_function_count { ret (0usize, false) }
    let function = c.function_generics[function_index]
    var at = 0usize
    while at < function.comptime_count {
        let index = function.first_comptime + at
        if index < c.comptime_parameter_count && same(c.comptime_parameters[index].name, name) { ret (index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn instance_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    if function_index >= c.signature_function_count { ret (empty, false) }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret (empty, false) }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret (empty, false) }
    let index = first_argument + offset
    if index >= c.generic_argument_count || !c.generic_arguments[index].set { ret (empty, false) }
    ret (c.generic_arguments[index], true)
}

fn evaluate_bound_expression(c: *Checker, function_index: usize, first_argument: usize, expression_index: usize) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .Literal { ret (expression.value, expression.ty, ok) }
    if expression.kind == .Name {
        var parameter_index = 0usize
        var parameter_found = false
        if expression.module_index == c.functions[function_index].module_index {
            (parameter_index, parameter_found) = template_parameter(c, function_index, expression.name)
        }
        if parameter_found {
            let parameter = c.comptime_parameters[parameter_index]
            if parameter.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
            let (argument, argument_found) = instance_argument(c, function_index, first_argument, parameter_index)
            if !argument_found { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            ret (normalized_integer(argument.value, false), parameter.ty, ok)
        }
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        ret (c.constants[constant_index].value, c.constants[constant_index].ty, ok)
    }
    if expression.kind == .Unary {
        let (operand, operand_type, operand_error) = evaluate_bound_expression(c, function_index, first_argument, expression.left)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op != .PunctMinus { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
        if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        ret (normalized_integer(operand.magnitude, !operand.negative), operand_type, ok)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        if expression.op != .PunctPlus && expression.op != .PunctMinus && expression.op != .PunctStar && expression.op != .PunctSlash && expression.op != .PunctPercent {
            ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
        }
        let (left, left_type, left_error) = evaluate_bound_expression(c, function_index, first_argument, expression.left)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        let (right, right_type, right_error) = evaluate_bound_expression(c, function_index, first_argument, expression.right)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        let (result_type, type_error) = constant_result_type(c, left_type, right_type)
        if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
        var result = normalized_integer(0usize, false)
        var result_error = ok
        if expression.op == .PunctPlus { (result, result_error) = add_integer_values(left, right) }
        if expression.op == .PunctMinus { (result, result_error) = subtract_integer_values(left, right) }
        if expression.op == .PunctStar { (result, result_error) = multiply_integer_values(left, right) }
        if expression.op == .PunctSlash { (result, result_error) = divide_integer_values(left, right) }
        if expression.op == .PunctPercent { (result, result_error) = remainder_integer_values(left, right) }
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}

fn substitute_type(c: *Checker, function_index: usize, first_argument: usize, ty: Type) -> (Type, err) {
    if ty.kind == .TypeParameter {
        if !ty.has_element { ret (invalid_type(), InvalidType) }
        let (argument, found) = instance_argument(c, function_index, first_argument, ty.element)
        if !found || argument.kind != .Type { ret (invalid_type(), MissingContext) }
        ret (argument.ty, ok)
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), InvalidType) }
        let (element, element_error) = substitute_type(c, function_index, first_argument, c.types[ty.element])
        if element_error != ok { ret (invalid_type(), element_error) }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var result = ty
        result.element = stored_element
        if ty.kind == .Array && !ty.has_length {
            let (length, length_type, length_error) = evaluate_bound_expression(c, function_index, first_argument, ty.array_length)
            if length_error != ok { ret (invalid_type(), length_error) }
            if length.negative || (length_type.kind != .UntypedInteger && (length_type.kind != .Integer || !same(length_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
            result.array_length = length.magnitude
            result.has_length = true
        }
        ret (result, ok)
    }
    ret (ty, ok)
}

fn bind_inferred_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize, ty: Type, value: usize, kind: ComptimeKind) -> err {
    if function_index >= c.signature_function_count { ret InvalidType }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret InvalidType }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret InvalidType }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count { ret Capacity }
    if c.generic_arguments[argument_index].set {
        if c.generic_arguments[argument_index].kind != kind { ret TypeMismatch }
        if kind == .Type {
            if !type_equal(c, c.generic_arguments[argument_index].ty, ty) { ret TypeMismatch }
        } else {
            if c.generic_arguments[argument_index].value != value { ret TypeMismatch }
        }
        ret ok
    }
    c.generic_arguments[argument_index].kind = kind
    c.generic_arguments[argument_index].ty = ty
    c.generic_arguments[argument_index].value = value
    c.generic_arguments[argument_index].set = true
    ret ok
}

fn infer_comptime_type(c: *Checker, function_index: usize, first_argument: usize, formal: Type, actual: Type) -> err {
    if formal.kind == .TypeParameter {
        if is_untyped(actual) || actual.kind == .Invalid || actual.kind == .Other { ret ok }
        if !formal.has_element { ret InvalidType }
        ret bind_inferred_argument(c, function_index, first_argument, formal.element, actual, 0usize, .Type)
    }
    if formal.kind != actual.kind { ret ok }
    if formal.kind == .Array && !formal.has_length && actual.has_length && formal.array_length < c.constant_expr_count {
        let expression = c.constant_exprs[formal.array_length]
        if expression.kind == .Name {
            var parameter_index = 0usize
            var parameter_found = false
            if expression.module_index == c.functions[function_index].module_index {
                (parameter_index, parameter_found) = template_parameter(c, function_index, expression.name)
            }
            if parameter_found && c.comptime_parameters[parameter_index].kind == .Integer {
                try bind_inferred_argument(c, function_index, first_argument, parameter_index, invalid_type(), actual.array_length, .Integer)
            }
        }
    }
    if (formal.kind == .Pointer || formal.kind == .Slice || formal.kind == .Array) && formal.has_element && actual.has_element {
        if formal.element >= c.type_count || actual.element >= c.type_count { ret InvalidType }
        ret infer_comptime_type(c, function_index, first_argument, c.types[formal.element], c.types[actual.element])
    }
    ret ok
}

fn generic_arguments_equal(c: *Checker, function_index: usize, first: usize, second: usize) -> bool {
    if function_index >= c.signature_function_count { ret false }
    let function = c.function_generics[function_index]
    var at = 0usize
    while at < function.comptime_count {
        let left = c.generic_arguments[first + at]
        let right = c.generic_arguments[second + at]
        if !left.set || !right.set || left.kind != right.kind { ret false }
        if left.kind == .Type {
            if !type_equal(c, left.ty, right.ty) { ret false }
        } else {
            if left.value != right.value { ret false }
        }
        at += 1usize
    }
    ret true
}

fn find_function_instance(c: *Checker, template_index: usize, first_argument: usize) -> (usize, bool) {
    var at = c.signature_function_count
    while at < c.function_count {
        let candidate = c.function_generics[at]
        if candidate.instance && candidate.template_index == template_index && generic_arguments_equal(c, template_index, candidate.first_argument, first_argument) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn instantiate_function(c: *Checker, template_index: usize, first_argument: usize) -> (usize, err) {
    let (cached, found) = find_function_instance(c, template_index, first_argument)
    if found { ret (cached, ok) }
    if template_index >= c.signature_function_count || c.function_count == c.functions.len { ret (0usize, Capacity) }
    let template = c.functions[template_index]
    var instance: Function = zero
    instance.name = template.name
    instance.module_index = template.module_index
    instance.first_parameter = c.parameter_count
    instance.parameter_count = template.parameter_count
    instance.first_return = c.return_type_count
    instance.return_count = template.return_count
    var generic: FunctionGeneric = zero
    generic.first_comptime = c.function_generics[template_index].first_comptime
    generic.comptime_count = c.function_generics[template_index].comptime_count
    generic.template_index = template_index
    generic.first_argument = first_argument
    generic.instance = true
    var at = 0usize
    while at < template.parameter_count {
        if c.parameter_count == c.parameters.len { ret (0usize, Capacity) }
        let source = c.parameters[template.first_parameter + at]
        let (specialized, specialize_error) = substitute_type(c, template_index, first_argument, source.ty)
        if specialize_error != ok { ret (0usize, specialize_error) }
        c.parameters[c.parameter_count] = Parameter { name: source.name, ty: specialized }
        c.parameter_count += 1usize
        at += 1usize
    }
    at = 0usize
    while at < template.return_count {
        let (specialized, specialize_error) = substitute_type(c, template_index, first_argument, c.return_types[template.first_return + at])
        if specialize_error != ok { ret (0usize, specialize_error) }
        let store_error = store_return_type(c, specialized)
        if store_error != ok { ret (0usize, store_error) }
        at += 1usize
    }
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

fn bracket_function(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (usize, err) {
    let (base_index, found_base) = first_node_child(tree, receiver)
    if !found_base { ret (0usize, parse.InvalidSyntax) }
    let base = tree.nodes[base_index]
    if base.kind == .NameExpr {
        let token = c.tokens[base.token_start]
        let name = g.modules[module_index].text[token.start..token.end]
        let (function_index, found) = find_function(c, module_index, name)
        if !found { ret (0usize, UnknownCallable) }
        ret (function_index, ok)
    }
    if base.kind == .FieldExpr {
        let (function_index, found) = find_qualified_function(c, g, tree, module_index, base)
        if !found { ret (0usize, UnknownCallable) }
        ret (function_index, ok)
    }
    ret (0usize, Unsupported)
}

fn specialize_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, call: syntax.Node, receiver: syntax.Node, template_index: usize) -> (usize, err) {
    if template_index >= c.signature_function_count { ret (0usize, UnknownCallable) }
    let template = c.functions[template_index]
    let generic = c.function_generics[template_index]
    if !template.generic || generic.comptime_count == 0usize { ret (0usize, Unsupported) }
    if c.generic_argument_count + generic.comptime_count > c.generic_arguments.len { ret (0usize, Capacity) }
    let first_argument = c.generic_argument_count
    var at = 0usize
    while at < generic.comptime_count {
        let parameter = c.comptime_parameters[generic.first_comptime + at]
        c.generic_arguments[c.generic_argument_count] = GenericArgument { kind: parameter.kind, ty: invalid_type(), value: 0usize, set: false }
        c.generic_argument_count += 1usize
        at += 1usize
    }
    if receiver.kind == .BracketPostfix {
        let end = receiver.first_child + receiver.child_count
        var child_position = 0usize
        at = receiver.first_child
        while at < end {
            if tree.children[at].node {
                if child_position > 0usize {
                    let argument_position = child_position - 1usize
                    if argument_position >= generic.comptime_count { ret (0usize, ArgumentCount) }
                    let parameter = c.comptime_parameters[generic.first_comptime + argument_position]
                    let node_index = tree.children[at].index
                    if parameter.kind == .Type {
                        let (ty, type_error) = comptime_type(c, g, tree, module_index, node_index)
                        if type_error != ok { ret (0usize, type_error) }
                        let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, ty, 0usize, .Type)
                        if bind_error != ok { ret (0usize, bind_error) }
                    } else {
                        let (value, value_error) = array_length_value(c, g, tree, module_index, node_index)
                        if value_error != ok { ret (0usize, InvalidType) }
                        let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, invalid_type(), value, .Integer)
                        if bind_error != ok { ret (0usize, bind_error) }
                    }
                }
                child_position += 1usize
            }
            at += 1usize
        }
    }
    var runtime_count = 0usize
    let call_end = call.first_child + call.child_count
    at = call.first_child
    while at < call_end {
        if tree.children[at].node { runtime_count += 1usize }
        at += 1usize
    }
    if runtime_count == 0usize || runtime_count - 1usize != template.parameter_count { ret (0usize, ArgumentCount) }
    var runtime_position = 0usize
    at = call.first_child
    while at < call_end {
        if tree.children[at].node {
            if runtime_position > 0usize {
                let formal = c.parameters[template.first_parameter + runtime_position - 1usize].ty
                var expected = invalid_type()
                let (specialized, specialize_error) = substitute_type(c, template_index, first_argument, formal)
                if specialize_error == ok { expected = specialized }
                if specialize_error != ok && specialize_error != MissingContext { ret (0usize, specialize_error) }
                let (actual, actual_error) = check_expr(c, g, tree, module_index, tree.children[at].index, expected)
                if actual_error != ok { ret (0usize, actual_error) }
                let inference_error = infer_comptime_type(c, template_index, first_argument, formal, actual)
                if inference_error != ok { ret (0usize, inference_error) }
            }
            runtime_position += 1usize
        }
        at += 1usize
    }
    at = 0usize
    while at < generic.comptime_count {
        if !c.generic_arguments[first_argument + at].set { ret (0usize, MissingContext) }
        at += 1usize
    }
    let (instance_index, instance_error) = instantiate_function(c, template_index, first_argument)
    ret (instance_index, instance_error)
}

type CallInfo = struct {
    function: Function,
    cast: Type,
    is_cast: bool,
    alloc_return: Type,
    alloc_arena: Type,
    mem_alloc: bool,
}

type AllocInfo = struct {
    matched: bool,
    function: Function,
    return_type: Type,
    arena_type: Type,
}

fn comptime_type(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if is_type_node(node.kind) {
        let (parsed, parsed_error) = type_from_node(c, c.resolver, g, tree, module_index, node)
        ret (parsed, parsed_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (invalid_type(), InvalidType) }
        let name = text[token.start..token.end]
        let scalar = scalar_type(name, module_index)
        if scalar.kind != .Invalid { ret (scalar, ok) }
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), InvalidType) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found { ret (invalid_type(), MissingContext) }
            ret (argument.ty, ok)
        }
        let (_, found) = resolve.find(c.resolver, module_index, name, .Type)
        if !found { ret (invalid_type(), InvalidType) }
        let named = make_type(.Named, name, module_index)
        let (canonical, canonical_error) = canonical_type(c, named)
        ret (canonical, canonical_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, name, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (invalid_type(), InvalidType) }
        let (_, has_type) = resolve.find(c.resolver, target_module, name, .Type)
        if !has_type { ret (invalid_type(), InvalidType) }
        let named = make_type(.Named, name, target_module)
        let (canonical, canonical_error) = canonical_type(c, named)
        ret (canonical, canonical_error)
    }
    if node.kind == .UnaryExpr && c.tokens[node.token_start].kind == .PunctStar {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (element, element_error) = comptime_type(c, g, tree, module_index, child_index)
        if element_error != ok { ret (invalid_type(), element_error) }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var pointer = make_type(.Pointer, "", module_index)
        pointer.element = stored_element
        pointer.has_element = true
        pointer.is_const = contains_token(c, node.token_start, tree.nodes[child_index].token_start, .KwConst)
        ret (pointer, ok)
    }
    ret (invalid_type(), InvalidType)
}

fn alloc_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (AllocInfo, err) {
    var info: AllocInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = receiver.first_child + receiver.child_count
    var at = receiver.first_child
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if tree.children[at].node {
            if child_count == 0usize {
                base_index = tree.children[at].index
            } else {
                type_index = tree.children[at].index
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "alloc") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (element, element_error) = comptime_type(c, g, tree, module_index, type_index)
    if element_error != ok { ret (info, element_error) }
    if element.kind == .Void || element.kind == .Other || element.kind == .Invalid { ret (info, InvalidType) }
    let (stored_element, store_error) = store_type(c, element)
    if store_error != ok { ret (info, store_error) }
    var result = make_type(.Slice, "", target_module)
    result.element = stored_element
    result.has_element = true
    let arena = make_type(.Named, "Arena", target_module)
    let (stored_arena, arena_error) = store_type(c, arena)
    if arena_error != ok { ret (info, arena_error) }
    var arena_pointer = make_type(.Pointer, "", target_module)
    arena_pointer.element = stored_arena
    arena_pointer.has_element = true
    var function: Function = zero
    function.name = "alloc"
    function.module_index = target_module
    function.parameter_count = 2usize
    function.return_count = 2usize
    info.function = function
    info.return_type = result
    info.arena_type = arena_pointer
    ret (info, ok)
}

fn check_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (CallInfo, err) {
    var info: CallInfo = zero
    info.cast = invalid_type()
    info.alloc_return = invalid_type()
    info.alloc_arena = invalid_type()
    if node.kind != .CallExpr { ret (info, parse.InvalidSyntax) }
    let text = g.modules[module_index].text
    let end = node.first_child + node.child_count
    var at = node.first_child
    var child_position = 0usize
    var has_function = false
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if child_position == 0usize {
                let receiver = tree.nodes[child_index]
                if receiver.kind == .NameExpr {
                    let token = c.tokens[receiver.token_start]
                    let name = text[token.start..token.end]
                    let cast = scalar_type(name, module_index)
                    if cast.kind == .Integer || cast.kind == .Float {
                        info.cast = cast
                        info.is_cast = true
                    } else {
                        let (found_index, found) = find_function(c, module_index, name)
                        if !found { ret (info, UnknownCallable) }
                        if c.functions[found_index].generic {
                            let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, found_index)
                            if specialize_error != ok { ret (info, specialize_error) }
                            info.function = c.functions[specialized_index]
                        } else {
                            info.function = c.functions[found_index]
                        }
                        has_function = true
                    }
                } else {
                    if receiver.kind == .BracketPostfix {
                        let (allocation, allocation_error) = alloc_info(c, g, tree, module_index, receiver)
                        if allocation_error != ok { ret (info, allocation_error) }
                        if allocation.matched {
                            info.function = allocation.function
                            info.alloc_return = allocation.return_type
                            info.alloc_arena = allocation.arena_type
                            info.mem_alloc = true
                        } else {
                            let (template_index, template_error) = bracket_function(c, g, tree, module_index, receiver)
                            if template_error != ok { ret (info, template_error) }
                            let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, template_index)
                            if specialize_error != ok { ret (info, specialize_error) }
                            info.function = c.functions[specialized_index]
                        }
                        has_function = true
                    } else {
                        if receiver.kind != .FieldExpr { ret (info, Unsupported) }
                        let (found_index, found) = find_qualified_function(c, g, tree, module_index, receiver)
                        if !found { ret (info, UnknownCallable) }
                        if c.functions[found_index].generic {
                            let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, found_index)
                            if specialize_error != ok { ret (info, specialize_error) }
                            info.function = c.functions[specialized_index]
                        } else {
                            info.function = c.functions[found_index]
                        }
                        has_function = true
                    }
                }
            } else {
                if info.is_cast {
                    if child_position != 1usize { ret (info, ArgumentCount) }
                    let (argument_type, argument_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                    if argument_error != ok { ret (info, argument_error) }
                    if is_untyped(argument_type) { ret (info, MissingContext) }
                    if !is_numeric(argument_type) { ret (info, TypeMismatch) }
                } else {
                    if !has_function { ret (info, UnknownCallable) }
                    let function = info.function
                    if child_position > function.parameter_count { ret (info, ArgumentCount) }
                    var parameter_type = invalid_type()
                    if info.mem_alloc {
                        if child_position == 1usize {
                            parameter_type = info.alloc_arena
                        } else {
                            parameter_type = make_type(.Integer, "usize", function.module_index)
                        }
                    } else {
                        parameter_type = c.parameters[function.first_parameter + child_position - 1usize].ty
                    }
                    let (argument_type, argument_error) = check_expr(c, g, tree, module_index, child_index, parameter_type)
                    if argument_error != ok { ret (info, argument_error) }
                }
            }
            child_position += 1usize
        }
        at += 1usize
    }
    if info.is_cast {
        if child_position != 2usize { ret (info, ArgumentCount) }
        ret (info, ok)
    }
    if !has_function { ret (info, UnknownCallable) }
    let function = info.function
    if child_position == 0usize || child_position - 1usize != function.parameter_count { ret (info, ArgumentCount) }
    if function.generic { ret (info, Unsupported) }
    ret (info, ok)
}

fn function_return(c: *Checker, function: Function, index: usize) -> (Type, err) {
    if index >= function.return_count || function.first_return + index >= c.return_type_count { ret (invalid_type(), InvalidType) }
    ret (c.return_types[function.first_return + index], ok)
}

fn call_return(c: *Checker, call: CallInfo, index: usize) -> (Type, err) {
    if index >= call.function.return_count { ret (invalid_type(), InvalidType) }
    if call.mem_alloc {
        if index == 0usize { ret (call.alloc_return, ok) }
        if index == 1usize { ret (make_type(.Err, "err", call.function.module_index), ok) }
        ret (invalid_type(), InvalidType)
    }
    let (result, result_error) = function_return(c, call.function, index)
    ret (result, result_error)
}

fn call_is_fallible(c: *Checker, call: CallInfo) -> bool {
    if call.function.return_count == 0usize { ret false }
    let (last, last_error) = call_return(c, call, call.function.return_count - 1usize)
    if last_error != ok { ret false }
    ret last.kind == .Err
}

fn is_fallible(c: *Checker, function: Function) -> bool {
    if function.return_count == 0usize { ret false }
    let last = c.return_types[function.first_return + function.return_count - 1usize]
    ret last.kind == .Err
}

fn check_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if node.kind == .LiteralExpr {
        let token = c.tokens[node.token_start]
        if token.kind == .KwNil {
            if expected.kind == .Pointer || expected.kind == .Slice { ret (expected, ok) }
            ret (invalid_type(), MissingContext)
        }
        let (literal, context_error) = apply_context(c, literal_type(c, text, node), expected)
        ret (literal, context_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind == .KwUnreachable { ret (make_type(.Void, "void", module_index), ok) }
        let name = text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if found {
            let (local_type, context_error) = apply_context(c, c.locals[local_index].ty, expected)
            ret (local_type, context_error)
        }
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind != .Integer { ret (invalid_type(), InvalidType) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found { ret (invalid_type(), MissingContext) }
            let (parameter_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
            ret (parameter_type, context_error)
        }
        let (constant_index, constant_found) = find_constant(c, module_index, name)
        if !constant_found || c.constants[constant_index].state != 2u8 { ret (invalid_type(), Unsupported) }
        let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        ret (constant_type, context_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
        if !found_member { ret (invalid_type(), Unsupported) }
        let (constant_index, constant_found) = find_constant(c, target_module, member)
        if !constant_found || c.constants[constant_index].state != 2u8 { ret (invalid_type(), Unsupported) }
        let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        ret (constant_type, context_error)
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
            let (result_type, context_error) = apply_context(c, value_type, expected)
            ret (result_type, context_error)
        }
        if op == .PunctAmp {
            let place = tree.nodes[child_index]
            if place.kind != .NameExpr { ret (invalid_type(), Unsupported) }
            let token = c.tokens[place.token_start]
            let name = text[token.start..token.end]
            let (local_index, local_found) = find_local(c, name)
            if !local_found { ret (invalid_type(), Unsupported) }
            let (element_index, store_error) = store_type(c, c.locals[local_index].ty)
            if store_error != ok { ret (invalid_type(), store_error) }
            var pointer = make_type(.Pointer, "", module_index)
            pointer.element = element_index
            pointer.has_element = true
            pointer.is_const = !c.locals[local_index].mutable
            let (result_type, context_error) = apply_context(c, pointer, expected)
            ret (result_type, context_error)
        }
        if op == .PunctStar {
            let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
            if pointer_error != ok { ret (invalid_type(), pointer_error) }
            if pointer.kind != .Pointer || !pointer.has_element || pointer.element >= c.type_count { ret (invalid_type(), InvalidOperator) }
            let element = c.types[pointer.element]
            if element.kind == .Void { ret (invalid_type(), InvalidOperator) }
            let (result_type, context_error) = apply_context(c, element, expected)
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
            let (result_type, context_error) = apply_context(c, make_type(.Bool, "bool", module_index), expected)
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
            let (contextual_left, contextual_error) = apply_context(c, final_left, final_right)
            if contextual_error != ok { ret (invalid_type(), contextual_error) }
            final_left = contextual_left
        }
        if is_untyped(final_right) && !is_untyped(final_left) {
            let (contextual_right, contextual_error) = apply_context(c, final_right, final_left)
            if contextual_error != ok { ret (invalid_type(), contextual_error) }
            final_right = contextual_right
        }
        if !type_equal(c, final_left, final_right) { ret (invalid_type(), TypeMismatch) }
        if is_comparison(op) {
            if is_untyped(final_left) { ret (invalid_type(), MissingContext) }
            if !is_numeric(final_left) {
                if !is_equality(op) { ret (invalid_type(), InvalidOperator) }
                if final_left.kind != .Bool && final_left.kind != .Err { ret (invalid_type(), InvalidOperator) }
            }
            let (result_type, context_error) = apply_context(c, make_type(.Bool, "bool", module_index), expected)
            ret (result_type, context_error)
        }
        if !is_numeric(final_left) { ret (invalid_type(), InvalidOperator) }
        if is_integer_operator(op) && !is_integer(final_left) { ret (invalid_type(), InvalidOperator) }
        ret (final_left, ok)
    }
    if node.kind == .CallExpr {
        let (call, call_error) = check_call(c, g, tree, module_index, node)
        if call_error != ok { ret (invalid_type(), call_error) }
        if call.is_cast {
            let (result_type, context_error) = apply_context(c, call.cast, expected)
            ret (result_type, context_error)
        }
        let function = call.function
        if function.return_count > 1usize { ret (invalid_type(), ArgumentCount) }
        if function.return_count == 0usize {
            let (result_type, context_error) = apply_context(c, make_type(.Void, "void", module_index), expected)
            ret (result_type, context_error)
        }
        let (return_type, return_error) = call_return(c, call, 0usize)
        if return_error != ok { ret (invalid_type(), return_error) }
        let (result_type, context_error) = apply_context(c, return_type, expected)
        ret (result_type, context_error)
    }
    ret (invalid_type(), Unsupported)
}

fn contains_token(c: *Checker, start: usize, end: usize, kind: lex.Kind) -> bool {
    var at = start
    while at < end {
        if c.tokens[at].kind == kind { ret true }
        at += 1usize
    }
    ret false
}

fn binding_item_count(c: *Checker, binding: syntax.Node) -> usize {
    var count = 0usize
    var at = binding.token_start
    while at < binding.token_end {
        let kind = c.tokens[at].kind
        if kind == .Identifier || kind == .PunctUnderscore { count += 1usize }
        at += 1usize
    }
    ret count
}

fn check_try_results(c: *Checker, call: CallInfo, caller: Function) -> (usize, err) {
    if call.function.external || !call_is_fallible(c, call) || !is_fallible(c, caller) { ret (0usize, InvalidTry) }
    ret (call.function.return_count - 1usize, ok)
}

fn bind_return_types(c: *Checker, g: *graph.Graph, module_index: usize, binding: syntax.Node, call: CallInfo, return_count: usize, declared: Type, mutable: bool) -> err {
    let tuple = c.tokens[binding.token_start].kind == .PunctLParen
    let item_count = binding_item_count(c, binding)
    if item_count != return_count { ret ArgumentCount }
    if tuple && declared.kind != .Invalid { ret InvalidType }
    var result_index = 0usize
    var at = binding.token_start
    while at < binding.token_end {
        let token = c.tokens[at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            let (return_type, return_error) = call_return(c, call, result_index)
            if return_error != ok { ret return_error }
            var result = return_type
            if !tuple {
                let (contextual, context_error) = apply_context(c, result, declared)
                if context_error != ok { ret context_error }
                result = contextual
            }
            if result.kind == .Void { ret TypeMismatch }
            if result.kind == .Other { ret Unsupported }
            if token.kind == .Identifier {
                let name = g.modules[module_index].text[token.start..token.end]
                try add_local(c, name, result, mutable)
            }
            result_index += 1usize
        }
        at += 1usize
    }
    ret ok
}

fn check_binding(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
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
                    let (declared_type, type_error) = type_from_node(c, r, g, tree, module_index, child)
                    if type_error != ok { ret type_error }
                    declared = declared_type
                } else {
                    initializer_index = child_index
                    has_initializer = true
                }
            }
        }
        at += 1usize
    }
    if !has_binding { ret parse.InvalidSyntax }
    let binding = tree.nodes[binding_index]
    let tuple = c.tokens[binding.token_start].kind == .PunctLParen
    var mutable = false
    if c.tokens[node.token_start].kind == .KwVar { mutable = true }
    if has_initializer && tree.nodes[initializer_index].kind == .CallExpr {
        let initializer = tree.nodes[initializer_index]
        let tried = contains_token(c, node.token_start, initializer.token_start, .KwTry)
        let (call, call_error) = check_call(c, g, tree, module_index, initializer)
        if call_error != ok { ret call_error }
        if call.is_cast {
            if tried { ret InvalidTry }
            if tuple { ret ArgumentCount }
            let (actual, context_error) = apply_context(c, call.cast, declared)
            if context_error != ok { ret context_error }
            if actual.kind == .Other { ret Unsupported }
            let (name, has_name) = first_name(c, g.modules[module_index].text, binding)
            if has_name { try add_local(c, name, actual, mutable) }
            ret ok
        }
        let callee = call.function
        var result_count = callee.return_count
        if tried {
            let (remaining, try_error) = check_try_results(c, call, function)
            if try_error != ok { ret try_error }
            result_count = remaining
        }
        if !tuple && result_count == 0usize { ret TypeMismatch }
        ret bind_return_types(c, g, module_index, binding, call, result_count, declared, mutable)
    }
    if tuple { ret ArgumentCount }
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
    let (name, has_name) = first_name(c, g.modules[module_index].text, binding)
    if !has_name { ret ok }
    try add_local(c, name, result, mutable)
    ret ok
}

fn check_return(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            count += 1usize
        }
        at += 1usize
    }
    if function.return_count == 0usize {
        if count != 0usize { ret InvalidReturn }
        ret ok
    }
    if count != function.return_count { ret InvalidReturn }
    var return_index = 0usize
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let (expected, return_type_error) = function_return(c, function, return_index)
            if return_type_error != ok { ret return_type_error }
            let (actual, expression_error) = check_expr(c, g, tree, module_index, tree.children[at].index, expected)
            if expression_error == TypeMismatch { ret InvalidReturn }
            if expression_error != ok { ret expression_error }
            return_index += 1usize
        }
        at += 1usize
    }
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
    let (call, call_error) = check_call(c, g, tree, module_index, tree.nodes[child_index])
    if call_error != ok { ret call_error }
    if call.is_cast { ret ArgumentCount }
    if call.function.return_count != 0usize { ret ArgumentCount }
    ret ok
}

fn check_try_statement(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret parse.InvalidSyntax }
    let call_node = tree.nodes[child_index]
    let (call, call_error) = check_call(c, g, tree, module_index, call_node)
    if call_error != ok { ret call_error }
    if call.is_cast { ret InvalidTry }
    let (remaining, try_error) = check_try_results(c, call, function)
    if try_error != ok { ret try_error }
    if remaining != 0usize { ret ArgumentCount }
    ret ok
}

fn assignment_place_type(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (Type, err) {
    let place = tree.nodes[node_index]
    if place.kind != .NameExpr { ret (invalid_type(), Unsupported) }
    let token = c.tokens[place.token_start]
    let name = g.modules[module_index].text[token.start..token.end]
    let (local_index, found) = find_local(c, name)
    if !found { ret (invalid_type(), Unsupported) }
    if !c.locals[local_index].mutable { ret (invalid_type(), ImmutableAssignment) }
    ret (c.locals[local_index].ty, ok)
}

fn check_assignment(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var count = 0usize
    var first_index = 0usize
    var initializer_index = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if count == 0usize { first_index = tree.children[at].index }
            initializer_index = tree.children[at].index
            count += 1usize
        }
        at += 1usize
    }
    if count < 2usize { ret Unsupported }
    let initializer = tree.nodes[initializer_index]
    if !contains_token(c, tree.nodes[first_index].token_end, initializer.token_start, .PunctAssign) { ret Unsupported }
    let tried = contains_token(c, node.token_start, initializer.token_start, .KwTry)
    if count == 2usize && !tried {
        let (place_type, place_error) = assignment_place_type(c, g, tree, module_index, first_index)
        if place_error != ok { ret place_error }
        let (actual, expression_error) = check_expr(c, g, tree, module_index, initializer_index, place_type)
        ret expression_error
    }
    if initializer.kind != .CallExpr { ret ArgumentCount }
    let (call, call_error) = check_call(c, g, tree, module_index, initializer)
    if call_error != ok { ret call_error }
    if call.is_cast {
        if tried { ret InvalidTry }
        ret ArgumentCount
    }
    let callee = call.function
    var result_count = callee.return_count
    if tried {
        let (remaining, try_error) = check_try_results(c, call, function)
        if try_error != ok { ret try_error }
        result_count = remaining
    }
    if count - 1usize != result_count { ret ArgumentCount }
    var result_index = 0usize
    at = node.first_child
    while at < end {
        if tree.children[at].node && result_index < result_count {
            let (place_type, place_error) = assignment_place_type(c, g, tree, module_index, tree.children[at].index)
            if place_error != ok { ret place_error }
            let (result_type, return_error) = call_return(c, call, result_index)
            if return_error != ok { ret return_error }
            let (contextual, context_error) = apply_context(c, result_type, place_type)
            if context_error != ok { ret context_error }
            result_index += 1usize
        }
        at += 1usize
    }
    ret ok
}

fn check_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, function: Function) -> err {
    let node = tree.nodes[node_index]
    if node.kind == .Block { ret check_block(c, r, g, tree, module_index, node, function) }
    if node.kind == .BindingStmt { ret check_binding(c, r, g, tree, module_index, node, function) }
    if node.kind == .ReturnStmt { ret check_return(c, g, tree, module_index, node, function) }
    if node.kind == .IfStmt || node.kind == .WhileStmt { ret check_condition_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .CallStmt { ret check_call_statement(c, g, tree, module_index, node) }
    if node.kind == .TryStmt { ret check_try_statement(c, g, tree, module_index, node, function) }
    if node.kind == .AssignmentStmt { ret check_assignment(c, g, tree, module_index, node, function) }
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

fn check_function_body(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var return_index = 0usize
    while return_index < function.return_count {
        if c.return_types[function.first_return + return_index].kind == .Other { ret Unsupported }
        return_index += 1usize
    }
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

fn check_function(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (name, name_error) = function_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (function_index, found) = find_function(c, module_index, name)
    if !found { ret UnknownCallable }
    let function = c.functions[function_index]
    if function.generic { ret ok }
    ret check_function_body(c, r, g, tree, module_index, node, function)
}

fn check_instance(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, instance_index: usize) -> err {
    if instance_index >= c.function_count { ret UnknownCallable }
    let instance = c.functions[instance_index]
    let instance_generic = c.function_generics[instance_index]
    if !instance_generic.instance || instance_generic.template_index >= c.signature_function_count { ret InvalidType }
    let template = c.functions[instance_generic.template_index]
    let template_generic = c.function_generics[instance_generic.template_index]
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[instance.module_index].text)
    try tokenize(c, g.modules[instance.module_index].text)
    c.active_first_comptime = template_generic.first_comptime
    c.active_comptime_count = template_generic.comptime_count
    c.active_first_argument = instance_generic.first_argument
    c.active_arguments = true
    var result = UnknownCallable
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl {
            let (name, name_error) = function_name(c, g.modules[instance.module_index].text, node)
            if name_error != ok { result = name_error }
            if name_error == ok && same(name, template.name) {
                result = check_function_body(c, r, g, &tree, instance.module_index, node, instance)
                break
            }
        }
        node_index += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.active_first_argument = 0usize
    c.active_arguments = false
    ret result
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
    var instance_index = c.signature_function_count
    while instance_index < c.function_count {
        if c.function_generics[instance_index].instance && !c.function_generics[instance_index].checked {
            c.function_generics[instance_index].checked = true
            try check_instance(c, r, g, instance_index)
        }
        instance_index += 1usize
    }
    ret ok
}

fn run(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    if c.function_generics.len < c.functions.len || c.comptime_parameters.len == 0usize || c.generic_arguments.len == 0usize { ret Capacity }
    c.resolver = r
    try collect_aliases(c, r, g, true)
    try collect_constants(c, r, g)
    try collect_aliases(c, r, g, false)
    try collect_signatures(c, r, g)
    ret check_bodies(c, r, g)
}
