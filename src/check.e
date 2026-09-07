// Type-checking foundation. Unsupported forms fail explicitly.

use e.mem
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
error InvalidFormat
error InvalidTry
error InvalidSwitch
error DuplicateCase
error NonExhaustiveSwitch

type DiagnosticKind = enum u8 {
    None,
    Generic,
    AssignmentImmutable,
    IndexedArrayImmutable,
    IndexedElementsImmutable,
    BreakOutsideControl,
    ReturnInsideDefer,
    TryInsideDefer,
    DeferValue,
    ArrayElementCount,
    ArrayLengthType,
    ConstantDependencyCycle,
    EnumValueRange,
    DuplicateEnumValue,
    MissingZeroValue,
    IteratorImmutable,
    IteratorMissing,
    IteratorSignature,
    RecursiveAggregate,
    InitializerType,
    GenericTypeArity,
    GenericInference,
    MultipleBindingCount,
    MultipleAssignmentImmutable,
    AggregateMemberUnknown,
    BindingUnknownNamed,
    NonExhaustive,
    ProtocolMissing,
    ProtocolSignature,
    ProtocolGenericType,
}

type Kind = enum u8 {
    Invalid,
    Void,
    Bool,
    Err,
    Integer,
    Float,
    String,
    Named,
    Tag,
    Pointer,
    Slice,
    Array,
    TypeParameter,
    UntypedInteger,
    UntypedFloat,
    Function,
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

type FunctionSignature = struct {
    first_parameter: usize,
    parameter_count: usize,
    first_return: usize,
    return_count: usize,
}

type ComptimeKind = enum u8 {
    Type,
    Integer,
    Str,
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
    // The literal exactly as it was written, quotes and escapes included: nothing
    // here decodes it, so it interns and lowers as any other string literal does.
    text: str,
    expression: usize,
    symbolic: bool,
    set: bool,
}

type Parameter = struct {
    name: str,
    ty: Type,
}

type Function = struct {
    name: str,
    module_index: usize,
    owner_module_index: usize,
    source_start: usize,
    source_end: usize,
    first_parameter: usize,
    parameter_count: usize,
    first_return: usize,
    return_count: usize,
    instance_id: usize,
    generic: bool,
    external: bool,
    intrinsic: bool,
}

type FunctionGeneric = struct {
    first_comptime: usize,
    comptime_count: usize,
    template_index: usize,
    first_argument: usize,
    instance: bool,
    checked: bool,
    lowered: bool,
    // A formatter instance has no source: its body is generated from the format
    // string, which is why it carries the string rather than a template index.
    formatter: bool,
    formatter_spelling: str,
    // `push_err` writes a name the library cannot see: the merged error table is
    // program-wide and exists only once every module is known.
    formatter_error: bool,
    // `printf` writes through a `str.Sink`, whose `write` is a function value of a
    // shape no `e.io` declaration has. The compiler generates that function too, and
    // this marks the one instance that is it rather than an expansion.
    formatter_sink: bool,
}

type ProtocolBuiltin = enum u8 {
    None,
    Cmp,
    Hash,
    Eq,
}

type AggregateKind = enum u8 {
    Struct,
    Union,
    TaggedUnion,
    Enum,
}

type Aggregate = struct {
    name: str,
    module_index: usize,
    kind: AggregateKind,
    first_field: usize,
    field_count: usize,
    first_comptime: usize,
    comptime_count: usize,
    template_index: usize,
    first_argument: usize,
    generic: bool,
    instance: bool,
    backing_type: Type,
    token: lex.Token,
}

type AggregateField = struct {
    name: str,
    ty: Type,
    enum_value: usize,
    enum_negative: bool,
    has_enum_value: bool,
    token: lex.Token,
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

type SwitchKeyKind = enum u8 {
    Invalid,
    Integer,
    Bool,
    Error,
    Member,
}

type SwitchKey = struct {
    kind: SwitchKeyKind,
    integer: IntegerValue,
    boolean: bool,
    module_index: usize,
    name: str,
}

type CheckedSwitch = struct {
    module_index: usize,
    token_start: usize,
    returns: bool,
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
    token: lex.Token,
}

type Diagnostic = struct {
    module_index: usize,
    kind: DiagnosticKind,
    token: lex.Token,
    detail: str,
    detail2: str,
}

type Checker = struct {
    resolver: *resolve.Resolver,
    functions: []Function,
    function_generics: []FunctionGeneric,
    parameters: []Parameter,
    return_types: []Type,
    comptime_parameters: []ComptimeParameter,
    generic_arguments: []GenericArgument,
    aggregates: []Aggregate,
    aggregate_fields: []AggregateField,
    checked_switches: []CheckedSwitch,
    function_signatures: []FunctionSignature,
    tokens: []lex.Token,
    locals: []Local,
    types: []Type,
    aliases: []Alias,
    constants: []Constant,
    constant_exprs: []ConstantExpr,
    diagnostics: []Diagnostic,
    // The merged error table (src/error_table.e), by value. Filled once the whole
    // program is known, because that is the first point at which it is merged; the
    // expansion of `push_err` is the only thing that reads it so far.
    error_values: []usize,
    error_spellings: []str,
    error_count: usize,
    // Lowering has to build strings that appear in no source text -- a reflected type
    // name, and the qualified error names above -- and interning takes a spelling, so
    // there has to be somewhere to build them.
    arena: *mem.Arena,
    function_count: usize,
    parameter_count: usize,
    return_type_count: usize,
    comptime_parameter_count: usize,
    generic_argument_count: usize,
    signature_function_count: usize,
    aggregate_count: usize,
    aggregate_field_count: usize,
    checked_switch_count: usize,
    function_signature_count: usize,
    token_count: usize,
    local_count: usize,
    type_count: usize,
    alias_count: usize,
    constant_count: usize,
    constant_expr_count: usize,
    diagnostic_count: usize,
    constants_ready: bool,
    expand_aliases: bool,
    active_first_comptime: usize,
    active_comptime_count: usize,
    active_first_argument: usize,
    active_arguments: bool,
    active_owner_module: usize,
    active_owner_set: bool,
    generic_declaration: bool,
    loop_depth: usize,
    break_depth: usize,
    defer_depth: usize,
    failure_module: usize,
    failure_name: str,
    failure_kind: DiagnosticKind,
    failure_token: lex.Token,
    failure_has_token: bool,
    failure_detail: str,
    failure_detail2: str,
}

fn append_failure_token(c: *Checker, module_index: usize, token: lex.Token, kind: DiagnosticKind, detail: str, detail2: str) {
    if c.diagnostic_count < c.diagnostics.len {
        c.diagnostics[c.diagnostic_count] = Diagnostic { module_index: module_index, kind: kind, token: token, detail: detail, detail2: detail2 }
        c.diagnostic_count += 1usize
    }
    if !c.failure_has_token {
        c.failure_module = module_index
        c.failure_kind = kind
        c.failure_token = token
        c.failure_has_token = true
        c.failure_detail = detail
        c.failure_detail2 = detail2
    }
}

fn record_failure(c: *Checker, module_index: usize, node: syntax.Node, kind: DiagnosticKind, detail: str, detail2: str) {
    if c.failure_has_token { ret }
    if node.token_start < c.token_count {
        append_failure_token(c, module_index, c.tokens[node.token_start], kind, detail, detail2)
    }
}

fn record_failure_token(c: *Checker, module_index: usize, token: lex.Token, kind: DiagnosticKind, detail: str, detail2: str) {
    if c.failure_has_token { ret }
    append_failure_token(c, module_index, token, kind, detail, detail2)
}

fn default_failure_kind(failure: err, node: syntax.Node) -> DiagnosticKind {
    if failure == ImmutableAssignment { ret .AssignmentImmutable }
    if failure == TypeMismatch { ret .InitializerType }
    if failure == ConstantCycle { ret .ConstantDependencyCycle }
    if failure == NonExhaustiveSwitch { ret .NonExhaustive }
    if node.kind == .BreakStmt && failure == Unsupported { ret .BreakOutsideControl }
    if node.kind == .ReturnStmt && failure == InvalidReturn { ret .ReturnInsideDefer }
    if node.kind == .TryStmt && failure == InvalidTry { ret .TryInsideDefer }
    if node.kind == .DeferStmt && failure == ArgumentCount { ret .DeferValue }
    if node.kind == .BindingStmt && failure == ArgumentCount { ret .MultipleBindingCount }
    if node.kind == .ForStmt && failure == ImmutableAssignment { ret .IteratorImmutable }
    if node.kind == .ForStmt && failure == UnknownCallable { ret .IteratorMissing }
    if node.kind == .ForStmt && failure == InvalidType { ret .IteratorSignature }
    ret .Generic
}

fn init(c: *Checker, functions: []Function, parameters: []Parameter, return_types: []Type, tokens: []lex.Token, locals: []Local, types: []Type, aliases: []Alias, constants: []Constant, constant_exprs: []ConstantExpr, diagnostics: []Diagnostic) -> err {
    if functions.len == 0usize || parameters.len == 0usize || return_types.len == 0usize || tokens.len == 0usize || locals.len == 0usize || types.len == 0usize || aliases.len == 0usize || constants.len == 0usize || constant_exprs.len == 0usize || diagnostics.len == 0usize { ret Capacity }
    c.functions = functions
    c.parameters = parameters
    c.return_types = return_types
    c.tokens = tokens
    c.locals = locals
    c.types = types
    c.aliases = aliases
    c.constants = constants
    c.constant_exprs = constant_exprs
    c.diagnostics = diagnostics
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    c.signature_function_count = 0usize
    c.aggregate_count = 0usize
    c.aggregate_field_count = 0usize
    c.checked_switch_count = 0usize
    c.function_signature_count = 0usize
    c.token_count = 0usize
    c.local_count = 0usize
    c.type_count = 0usize
    c.alias_count = 0usize
    c.constant_count = 0usize
    c.constant_expr_count = 0usize
    c.diagnostic_count = 0usize
    c.constants_ready = false
    c.expand_aliases = false
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.active_first_argument = 0usize
    c.active_arguments = false
    c.active_owner_module = 0usize
    c.active_owner_set = false
    c.generic_declaration = false
    c.loop_depth = 0usize
    c.break_depth = 0usize
    c.defer_depth = 0usize
    c.failure_module = 0usize
    c.failure_name = ""
    c.failure_kind = .None
    c.failure_has_token = false
    c.failure_detail = ""
    c.failure_detail2 = ""
    ret ok
}

fn init_generics(c: *Checker, functions: []FunctionGeneric, parameters: []ComptimeParameter, arguments: []GenericArgument) -> err {
    if functions.len < c.functions.len || parameters.len == 0usize || arguments.len == 0usize { ret Capacity }
    c.function_generics = functions
    c.comptime_parameters = parameters
    c.generic_arguments = arguments
    ret ok
}

fn init_aggregates(c: *Checker, aggregates: []Aggregate, fields: []AggregateField) -> err {
    if aggregates.len == 0usize || fields.len == 0usize { ret Capacity }
    c.aggregates = aggregates
    c.aggregate_fields = fields
    ret ok
}

fn init_control(c: *Checker, switches: []CheckedSwitch, signatures: []FunctionSignature) -> err {
    if switches.len == 0usize || signatures.len == 0usize { ret Capacity }
    c.checked_switches = switches
    c.function_signatures = signatures
    ret ok
}

fn store_function_signature(c: *Checker, item: FunctionSignature) -> (usize, err) {
    if c.function_signature_count == c.function_signatures.len { ret (0usize, Capacity) }
    let index = c.function_signature_count
    c.function_signatures[index] = item
    c.function_signature_count += 1usize
    ret (index, ok)
}

fn function_signature_of(c: *Checker, ty: Type) -> (FunctionSignature, bool) {
    var empty: FunctionSignature = zero
    if ty.kind != .Function || !ty.has_element || ty.element >= c.function_signature_count { ret (empty, false) }
    ret (c.function_signatures[ty.element], true)
}

fn function_signature_parameter(c: *Checker, signature: FunctionSignature, index: usize) -> (Type, bool) {
    if index >= signature.parameter_count || signature.first_parameter + index >= c.type_count { ret (invalid_type(), false) }
    ret (c.types[signature.first_parameter + index], true)
}

fn function_signature_return(c: *Checker, signature: FunctionSignature, index: usize) -> (Type, bool) {
    if index >= signature.return_count || signature.first_return + index >= c.type_count { ret (invalid_type(), false) }
    ret (c.types[signature.first_return + index], true)
}

fn build_function_type(c: *Checker, parameters: []const Type, returns: []const Type, module_index: usize) -> (Type, err) {
    let first_parameter = c.type_count
    var at = 0usize
    while at < parameters.len {
        let (stored, store_error) = store_type(c, parameters[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < returns.len {
        let (stored, store_error) = store_type(c, returns[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = parameters.len
    signature.first_return = first_return
    signature.return_count = returns.len
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
}

fn function_pointer_type(c: *Checker, function: Function, module_index: usize) -> (Type, err) {
    let first_parameter = c.type_count
    var at = 0usize
    while at < function.parameter_count {
        if function.first_parameter + at >= c.parameter_count { ret (invalid_type(), InvalidType) }
        let (stored, store_error) = store_type(c, c.parameters[function.first_parameter + at].ty)
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < function.return_count {
        if function.first_return + at >= c.return_type_count { ret (invalid_type(), InvalidType) }
        let (stored, store_error) = store_type(c, c.return_types[function.first_return + at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = function.parameter_count
    signature.first_return = first_return
    signature.return_count = function.return_count
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
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
    if a.kind == .Named || a.kind == .Tag {
        if a.module_index != b.module_index || !same(a.name, b.name) || a.has_element != b.has_element { ret false }
        if a.has_element { ret a.element == b.element }
        ret true
    }
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
    if a.kind == .Function {
        let (left, has_left) = function_signature_of(c, a)
        let (right, has_right) = function_signature_of(c, b)
        if !has_left || !has_right { ret false }
        if left.parameter_count != right.parameter_count || left.return_count != right.return_count { ret false }
        var at = 0usize
        while at < left.parameter_count {
            let (left_parameter, has_left_parameter) = function_signature_parameter(c, left, at)
            let (right_parameter, has_right_parameter) = function_signature_parameter(c, right, at)
            if !has_left_parameter || !has_right_parameter || !type_equal(c, left_parameter, right_parameter) { ret false }
            at += 1usize
        }
        at = 0usize
        while at < left.return_count {
            let (left_return, has_left_return) = function_signature_return(c, left, at)
            let (right_return, has_right_return) = function_signature_return(c, right, at)
            if !has_left_return || !has_right_return || !type_equal(c, left_return, right_return) { ret false }
            at += 1usize
        }
        ret true
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

fn type_depends_on_comptime(c: *Checker, ty: Type) -> bool {
    if ty.kind == .TypeParameter { ret true }
    if ty.kind == .Named && ty.has_element && ty.element < c.aggregate_count { ret c.aggregates[ty.element].generic }
    if ty.kind == .Array && !ty.has_length { ret true }
    if (ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array) && ty.has_element && ty.element < c.type_count {
        ret type_depends_on_comptime(c, c.types[ty.element])
    }
    ret false
}

fn type_shape_unknown(ty: Type) -> bool {
    ret ty.kind == .TypeParameter
}

fn types_may_match_after_instantiation(c: *Checker, actual: Type, expected: Type) -> bool {
    if type_equal(c, actual, expected) { ret true }
    if actual.kind == .TypeParameter || expected.kind == .TypeParameter { ret true }
    if actual.kind != expected.kind { ret false }
    if actual.kind == .Named {
        if actual.module_index != expected.module_index || !same(actual.name, expected.name) { ret false }
        if !actual.has_element || !expected.has_element || actual.element >= c.aggregate_count || expected.element >= c.aggregate_count { ret false }
        let left = c.aggregates[actual.element]
        let right = c.aggregates[expected.element]
        ret left.template_index == right.template_index && (left.generic || right.generic)
    }
    if actual.kind == .Pointer || actual.kind == .Slice {
        if actual.is_const && !expected.is_const { ret false }
        if !actual.has_element || !expected.has_element || actual.element >= c.type_count || expected.element >= c.type_count { ret false }
        ret types_may_match_after_instantiation(c, c.types[actual.element], c.types[expected.element])
    }
    if actual.kind == .Array {
        if actual.has_length && expected.has_length && actual.array_length != expected.array_length { ret false }
        if !actual.has_element || !expected.has_element || actual.element >= c.type_count || expected.element >= c.type_count { ret false }
        ret types_may_match_after_instantiation(c, c.types[actual.element], c.types[expected.element])
    }
    // A declaration and the aggregate it constructs number their comptime
    // parameters separately, so two signatures written the same way are not equal
    // until the instantiation binds both.
    if actual.kind == .Function {
        let (left, has_left) = function_signature_of(c, actual)
        let (right, has_right) = function_signature_of(c, expected)
        if !has_left || !has_right { ret false }
        if left.parameter_count != right.parameter_count || left.return_count != right.return_count { ret false }
        var at = 0usize
        while at < left.parameter_count {
            let (left_parameter, has_left_parameter) = function_signature_parameter(c, left, at)
            let (right_parameter, has_right_parameter) = function_signature_parameter(c, right, at)
            if !has_left_parameter || !has_right_parameter { ret false }
            if !types_may_match_after_instantiation(c, left_parameter, right_parameter) { ret false }
            at += 1usize
        }
        at = 0usize
        while at < left.return_count {
            let (left_return, has_left_return) = function_signature_return(c, left, at)
            let (right_return, has_right_return) = function_signature_return(c, right, at)
            if !has_left_return || !has_right_return { ret false }
            if !types_may_match_after_instantiation(c, left_return, right_return) { ret false }
            at += 1usize
        }
        ret true
    }
    ret false
}

fn apply_context(c: *Checker, actual: Type, expected: Type) -> (Type, err) {
    if expected.kind == .Invalid { ret (actual, ok) }
    if actual.kind == .UntypedInteger && expected.kind == .Integer { ret (expected, ok) }
    if actual.kind == .UntypedFloat && expected.kind == .Float { ret (expected, ok) }
    if type_assignable(c, actual, expected) { ret (expected, ok) }
    if c.generic_declaration && types_may_match_after_instantiation(c, actual, expected) { ret (expected, ok) }
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

// `str` names both a builtin type and the qualifier `use e.str` binds, so a dotted
// path under that name is the module's — `str.Builder`, which section 9 requires in
// every declared `format` — and never the scalar.
fn named_type_is_path(c: *Checker, node: syntax.Node) -> bool {
    var at = node.token_start + 1usize
    while at < node.token_end {
        if c.tokens[at].kind == .PunctDot { ret true }
        at += 1usize
    }
    ret false
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
        if ty.has_element { ret (ty, ok) }
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

fn evaluate_array_length_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if node.kind == .LiteralExpr {
        let (magnitude, parsed_type, literal_error) = integer_literal_value(c, text, node)
        if literal_error != ok { ret (normalized_integer(0usize, false), invalid_type(), literal_error) }
        let (contextual_type, context_error) = apply_context(c, parsed_type, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        let value = normalized_integer(magnitude, false)
        if contextual_type.kind == .Integer && !integer_representable(value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (value, contextual_type, ok)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let name = text[token.start..token.end]
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
            let (contextual_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            ret (normalized_integer(argument.value, false), contextual_type, ok)
        }
        if !c.constants_ready { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
        let (constant_index, found) = find_constant(c, module_index, name)
        if !found || constant_index >= c.constant_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let item = c.constants[constant_index]
        if item.state != 2u8 { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (contextual_type, context_error) = apply_context(c, item.ty, expected)
        if context_error != ok || !integer_representable(item.value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (item.value, contextual_type, ok)
    }
    if node.kind == .FieldExpr {
        if !c.constants_ready { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
        let (target_module, member, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (constant_index, constant_found) = find_constant(c, target_module, member)
        if !constant_found || constant_index >= c.constant_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let item = c.constants[constant_index]
        if item.state != 2u8 { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (contextual_type, context_error) = apply_context(c, item.ty, expected)
        if context_error != ok || !integer_representable(item.value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (item.value, contextual_type, ok)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
        let (value, value_type, value_error) = evaluate_array_length_expr(c, g, tree, module_index, child_index, expected)
        ret (value, value_type, value_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
        let op = c.tokens[node.token_start].kind
        var operand_expected = expected
        if op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_array_length_expr(c, g, tree, module_index, child_index, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if op == .PunctTilde {
            if operand_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var count = 0usize
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                if count == 2usize { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
                children[count] = tree.children[at].index
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
        let op = binary_operator(c, tree, node)
        let (left, left_type, left_error) = evaluate_array_length_expr(c, g, tree, module_index, children[0usize], expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_array_length_expr(c, g, tree, module_index, children[1usize], right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", module_index) }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (op == .PunctAmp || op == .PunctCaret || op == .PunctPipe || op == .PunctAddWrap || op == .PunctSubWrap || op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, right_type)) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        let (result, result_error) = evaluate_integer_binary(op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && op != .PunctAddWrap && op != .PunctSubWrap && op != .PunctMulWrap && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
}

fn array_length_value(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, err) {
    let expected = make_type(.Integer, "usize", module_index)
    let (value, value_type, value_error) = evaluate_array_length_expr(c, g, tree, module_index, node_index, expected)
    if value_error == Unsupported { ret (0usize, Unsupported) }
    if value_error != ok || value.negative || value_type.kind != .Integer || !same(value_type.name, "usize") { ret (0usize, TypeMismatch) }
    ret (value.magnitude, ok)
}

fn function_type_from_node(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    // The node carries one Parameter child per parameter and an optional ReturnSpec,
    // the same shape a `fn` declaration uses.
    var parameter_types: [16]Type = zero
    var parameter_count = 0usize
    var return_types: [4]Type = zero
    var return_count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .Parameter {
                if parameter_count == parameter_types.len { ret (invalid_type(), Capacity) }
                let (type_index, has_type) = first_node_child(tree, child)
                if !has_type { ret (invalid_type(), parse.InvalidSyntax) }
                let (parameter_type, parameter_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
                if parameter_error != ok { ret (invalid_type(), parameter_error) }
                if parameter_type.kind == .Void { ret (invalid_type(), InvalidType) }
                parameter_types[parameter_count] = parameter_type
                parameter_count += 1usize
            }
            if child.kind == .ReturnSpec {
                let return_end = child.first_child + child.child_count
                var return_at = child.first_child
                while return_at < return_end {
                    if tree.children[return_at].node {
                        if return_count == return_types.len { ret (invalid_type(), Capacity) }
                        let (return_type, return_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[tree.children[return_at].index])
                        if return_error != ok { ret (invalid_type(), return_error) }
                        return_types[return_count] = return_type
                        return_count += 1usize
                    }
                    return_at += 1usize
                }
            }
        }
        at += 1usize
    }
    if return_count == 1usize && return_types[0usize].kind == .Void { return_count = 0usize }
    let first_parameter = c.type_count
    at = 0usize
    while at < parameter_count {
        let (stored, store_error) = store_type(c, parameter_types[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < return_count {
        let (stored, store_error) = store_type(c, return_types[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = parameter_count
    signature.first_return = first_return
    signature.return_count = return_count
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
}

fn type_from_node(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    if node.kind == .FunctionType {
        let (function_type, function_type_error) = function_type_from_node(c, r, g, tree, module_index, node)
        ret (function_type, function_type_error)
    }
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
            if c.active_comptime_count == 0usize || c.active_arguments {
                if length_error == TypeMismatch { record_failure(c, module_index, tree.nodes[length_index], .ArrayLengthType, "", "") }
                ret (invalid_type(), length_error)
            }
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
    if scalar.kind != .Invalid {
        let (scalar_module, scalar_qualified) = resolve.qualifier(r, module_index, base)
        if !scalar_qualified || !named_type_is_path(c, node) { ret (scalar, ok) }
    }
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
    let (qualified_module, has_qualifier) = resolve.qualifier(r, module_index, base)
    if has_qualifier { target_module = qualified_module }
    var entry_arena = false
    if !has_qualifier && same(base, "mem") {
        var entry_at = node.token_start + 1usize
        var entry_state = 0usize
        var valid_entry = true
        while entry_at < node.token_end {
            let entry_token = c.tokens[entry_at]
            if entry_token.kind == .Newline {
                entry_at += 1usize
            } else {
                if entry_state == 0usize && entry_token.kind == .PunctDot {
                    entry_state = 1usize
                } else {
                    if entry_state == 1usize && entry_token.kind == .Identifier {
                        let entry_name = g.modules[module_index].text[entry_token.start..entry_token.end]
                        if same(entry_name, "Arena") {
                            name = entry_name
                            entry_state = 2usize
                        } else {
                            valid_entry = false
                        }
                    } else {
                        valid_entry = false
                    }
                }
                entry_at += 1usize
            }
            if !valid_entry { break }
        }
        if valid_entry && entry_state == 2usize {
            entry_arena = true
            let (memory_module, has_memory_module) = graph.find_module(g, "e.mem")
            if has_memory_module { target_module = memory_module }
        }
    }
    var path_identifiers = 0usize
    var wants_tag = false
    var has_arguments = false
    var at = node.token_start + 1usize
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .PunctLBracket {
            has_arguments = true
            break
        }
        if token.kind == .Identifier {
            let part = g.modules[module_index].text[token.start..token.end]
            if has_qualifier {
                if path_identifiers == 0usize {
                    name = part
                } else {
                    if path_identifiers != 1usize || !same(part, "Tag") { ret (invalid_type(), InvalidType) }
                    wants_tag = true
                }
            } else {
                if entry_arena {
                    path_identifiers += 1usize
                    at += 1usize
                    continue
                }
                if path_identifiers != 0usize || !same(part, "Tag") { ret (invalid_type(), InvalidType) }
                wants_tag = true
            }
            path_identifiers += 1usize
        }
        at += 1usize
    }
    if has_qualifier && path_identifiers == 0usize { ret (invalid_type(), InvalidType) }
    if wants_tag && has_arguments { ret (invalid_type(), InvalidType) }
    var result = make_type(.Named, name, target_module)
    if has_arguments {
        let (template_index, found_template) = find_aggregate(c, target_module, name)
        if !found_template {
            if !c.expand_aliases { ret (make_type(.Other, "", module_index), Unsupported) }
            ret (invalid_type(), InvalidType)
        }
        if !c.aggregates[template_index].generic { ret (invalid_type(), InvalidType) }
        let template = c.aggregates[template_index]
        if c.generic_argument_count + template.comptime_count > c.generic_arguments.len { ret (invalid_type(), Capacity) }
        let first_argument = c.generic_argument_count
        var argument_count = 0usize
        let child_end = node.first_child + node.child_count
        at = node.first_child
        while at < child_end {
            if tree.children[at].node {
                if argument_count >= template.comptime_count { ret (invalid_type(), ArgumentCount) }
                let parameter = c.comptime_parameters[template.first_comptime + argument_count]
                let argument_node = tree.children[at].index
                var argument: GenericArgument = zero
                argument.kind = parameter.kind
                argument.set = true
                if parameter.kind == .Type {
                    let (argument_type, argument_error) = comptime_type(c, g, tree, module_index, argument_node)
                    if argument_error != ok { ret (invalid_type(), argument_error) }
                    argument.ty = argument_type
                } else {
                    let (value, value_error) = array_length_value(c, g, tree, module_index, argument_node)
                    if value_error == ok {
                        argument.value = value
                    } else {
                        if c.active_comptime_count == 0usize || c.active_arguments { ret (invalid_type(), value_error) }
                        let (expression, expression_error) = copy_constant_expr(c, g, tree, module_index, argument_node)
                        if expression_error != ok { ret (invalid_type(), value_error) }
                        argument.expression = expression
                        argument.symbolic = true
                    }
                }
                c.generic_arguments[c.generic_argument_count] = argument
                c.generic_argument_count += 1usize
                argument_count += 1usize
            }
            at += 1usize
        }
        if argument_count != template.comptime_count { ret (invalid_type(), ArgumentCount) }
        let (instance_index, instance_error) = instantiate_aggregate(c, template_index, first_argument)
        if instance_error != ok { ret (invalid_type(), instance_error) }
        result.element = instance_index
        result.has_element = true
        ret (result, ok)
    }
    if wants_tag {
        let (canonical_subject, canonical_error) = canonical_type(c, result)
        if canonical_error != ok { ret (invalid_type(), canonical_error) }
        let (tag, found_tag) = tagged_union_tag_type(c, canonical_subject)
        if !found_tag { ret (invalid_type(), InvalidType) }
        ret (tag, ok)
    }
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
    if allow_deferred { c.type_count = 0usize }
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

fn find_aggregate(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    var at = 0usize
    while at < c.aggregate_count {
        if c.aggregates[at].module_index == module_index && same(c.aggregates[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn find_aggregate_field(c: *Checker, ty: Type, name: str) -> (usize, bool) {
    var subject = ty
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret (0usize, false) }
        subject = c.types[subject.element]
    }
    if subject.kind != .Named { ret (0usize, false) }
    var aggregate_index = 0usize
    var found = false
    if subject.has_element && subject.element < c.aggregate_count {
        aggregate_index = subject.element
        found = true
    } else {
        (aggregate_index, found) = find_aggregate(c, subject.module_index, subject.name)
    }
    if !found { ret (0usize, false) }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance {
        if aggregate.template_index >= c.aggregate_count { ret (0usize, false) }
        aggregate = c.aggregates[aggregate.template_index]
    }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count && same(c.aggregate_fields[field_index].name, name) { ret (field_index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn aggregate_for_type(c: *Checker, ty: Type) -> (usize, bool) {
    if ty.kind != .Named && ty.kind != .Tag { ret (0usize, false) }
    if ty.has_element && ty.element < c.aggregate_count { ret (ty.element, true) }
    let (aggregate_index, found) = find_aggregate(c, ty.module_index, ty.name)
    ret (aggregate_index, found)
}

fn is_enum_type(c: *Checker, ty: Type) -> bool {
    if ty.kind == .Tag { ret ty.has_element && ty.element < c.aggregate_count && c.aggregates[ty.element].kind == .TaggedUnion }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    ret found && c.aggregates[aggregate_index].kind == .Enum
}

// An enum member is stored as its backing integer's bits, so a negative member
// is its two's complement at the backing width. Written as `(mask - magnitude) + 1`
// rather than `2^width - magnitude`, which overflows a `usize` at width 64.
fn enum_member_bits(backing: Type, magnitude: usize, negative: bool) -> (usize, err) {
    if !negative { ret (magnitude, ok) }
    if backing.kind != .Integer { ret (0usize, InvalidType) }
    var mask = 18446744073709551615usize
    if same(backing.name, "i8") || same(backing.name, "u8") { mask = 255usize }
    if same(backing.name, "i16") || same(backing.name, "u16") { mask = 65535usize }
    if same(backing.name, "i32") || same(backing.name, "u32") { mask = 4294967295usize }
    if magnitude == 0usize || magnitude > mask { ret (0usize, InvalidType) }
    ret ((mask - magnitude) + 1usize, ok)
}

// An enum's ordering is its backing integer's ordering, so the backing type has
// to be reachable from a value's type. Nothing else about an enum survives past
// lowering.
fn enum_backing_type(c: *Checker, ty: Type) -> (Type, bool) {
    if ty.kind != .Named { ret (invalid_type(), false) }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .Enum { ret (invalid_type(), false) }
    let backing = c.aggregates[aggregate_index].backing_type
    if backing.kind != .Integer { ret (invalid_type(), false) }
    ret (backing, true)
}

fn tagged_union_tag_type(c: *Checker, ty: Type) -> (Type, bool) {
    var subject = ty
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret (invalid_type(), false) }
        subject = c.types[subject.element]
    }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret (invalid_type(), false) }
    var tag = make_type(.Tag, c.aggregates[aggregate_index].name, c.aggregates[aggregate_index].module_index)
    tag.element = aggregate_index
    tag.has_element = true
    ret (tag, true)
}

fn field_expression_name(c: *Checker, text: str, tree: *parse.Tree, node: syntax.Node) -> (str, bool) {
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret ("", false) }
    let base = tree.nodes[base_index]
    var name = ""
    var at = base.token_end
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .Identifier { name = text[token.start..token.end] }
        at += 1usize
    }
    ret (name, name.len != 0usize)
}

fn aggregate_declaration_shape(tree: *parse.Tree, node: syntax.Node) -> (usize, AggregateKind, bool, bool) {
    var body_index = 0usize
    var has_body = false
    var generic = false
    var kind: AggregateKind = .Struct
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind == .ComptimeParam { generic = true }
            if child.kind == .StructType || child.kind == .UnionType || child.kind == .UnionEnumType || child.kind == .EnumType {
                body_index = child_index
                has_body = true
                if child.kind == .UnionType { kind = .Union }
                if child.kind == .UnionEnumType { kind = .TaggedUnion }
                if child.kind == .EnumType { kind = .Enum }
            }
        }
        at += 1usize
    }
    ret (body_index, kind, generic, has_body)
}

fn register_aggregate_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (body_index, kind, generic, has_body) = aggregate_declaration_shape(tree, node)
    if !has_body { ret ok }
    if c.aggregate_count == c.aggregates.len { ret Capacity }
    let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let aggregate_index = c.aggregate_count
    var aggregate = Aggregate { name: name, module_index: module_index, kind: kind, first_field: 0usize, field_count: 0usize, first_comptime: c.comptime_parameter_count, comptime_count: 0usize, template_index: aggregate_index, first_argument: 0usize, generic: generic, instance: false, backing_type: invalid_type(), token: c.tokens[node.token_start] }
    c.aggregates[aggregate_index] = aggregate
    c.aggregate_count += 1usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .ComptimeParam {
                c.active_first_comptime = aggregate.first_comptime
                c.active_comptime_count = aggregate.comptime_count
                try collect_comptime_parameter(c, r, g, tree, module_index, child)
                aggregate.comptime_count += 1usize
            }
        }
        at += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.aggregates[aggregate_index] = aggregate
    ret ok
}

fn collect_aggregate_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (body_index, kind, generic, has_body) = aggregate_declaration_shape(tree, node)
    if !has_body { ret ok }
    let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (aggregate_index, found_aggregate) = find_aggregate(c, module_index, name)
    if !found_aggregate { ret InvalidType }
    var aggregate = c.aggregates[aggregate_index]
    aggregate.first_field = c.aggregate_field_count
    aggregate.field_count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    c.active_first_comptime = aggregate.first_comptime
    c.active_comptime_count = aggregate.comptime_count
    let body = tree.nodes[body_index]
    let body_end = body.first_child + body.child_count
    var backing_type = invalid_type()
    if kind == .Enum || kind == .TaggedUnion {
        var backing_at = body.first_child
        while backing_at < body_end {
            if tree.children[backing_at].node {
                let backing_node = tree.nodes[tree.children[backing_at].index]
                if is_type_node(backing_node.kind) {
                    let (resolved_backing, backing_error) = type_from_node(c, r, g, tree, module_index, backing_node)
                    if backing_error != ok { ret backing_error }
                    backing_type = resolved_backing
                    break
                }
            }
            backing_at += 1usize
        }
        if backing_type.kind != .Integer { ret InvalidType }
        aggregate.backing_type = backing_type
    }
    var next_enum_value = 0usize
    var next_enum_negative = false
    var next_enum_valid = true
    at = body.first_child
    while at < body_end {
        if tree.children[at].node {
            let field_node = tree.nodes[tree.children[at].index]
            if field_node.kind == .FieldDecl || field_node.kind == .UnionMember || field_node.kind == .EnumMember {
                if c.aggregate_field_count == c.aggregate_fields.len { ret Capacity }
                let (field_name, has_name) = first_name(c, g.modules[module_index].text, field_node)
                if !has_name { ret parse.InvalidSyntax }
                var field_type = make_type(.Void, "void", module_index)
                let (type_index, has_type) = first_node_child(tree, field_node)
                if has_type && kind != .Enum {
                    let (resolved, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
                    if type_error != ok { ret type_error }
                    field_type = resolved
                } else {
                    if kind != .TaggedUnion && kind != .Enum { ret parse.InvalidSyntax }
                }
                if field_type.kind == .Void && kind != .TaggedUnion && kind != .Enum { ret InvalidType }
                var prior_at = 0usize
                while prior_at < aggregate.field_count {
                    let prior = c.aggregate_fields[aggregate.first_field + prior_at]
                    if same(prior.name, field_name) { ret InvalidType }
                    prior_at += 1usize
                }
                var enum_value = next_enum_value
                var enum_negative = next_enum_negative
                var has_enum_value = kind == .Enum || kind == .TaggedUnion
                if kind == .Enum && has_type {
                    let (explicit_value, explicit_type, value_error) = evaluate_array_length_expr(c, g, tree, module_index, type_index, invalid_type())
                    if value_error != ok { ret value_error }
                    if explicit_type.kind != .Integer && explicit_type.kind != .UntypedInteger { ret InvalidType }
                    enum_value = explicit_value.magnitude
                    enum_negative = explicit_value.negative
                } else {
                    if has_enum_value && !next_enum_valid { ret ConstantOverflow }
                }
                if has_enum_value {
                    let value = normalized_integer(enum_value, enum_negative)
                    prior_at = 0usize
                    while prior_at < aggregate.field_count {
                        let prior = c.aggregate_fields[aggregate.first_field + prior_at]
                        if prior.has_enum_value && prior.enum_value == enum_value && prior.enum_negative == enum_negative {
                            append_failure_token(c, module_index, c.tokens[field_node.token_start], .DuplicateEnumValue, field_name, "")
                            break
                        }
                        prior_at += 1usize
                    }
                    if !integer_representable(value, backing_type) {
                        append_failure_token(c, module_index, c.tokens[field_node.token_start], .EnumValueRange, field_name, "")
                    }
                    if enum_negative {
                        if enum_value > 1usize {
                            next_enum_value = enum_value - 1usize
                            next_enum_negative = true
                        } else {
                            next_enum_value = 0usize
                            next_enum_negative = false
                        }
                        next_enum_valid = true
                    } else {
                        if enum_value == 18446744073709551615usize {
                            next_enum_valid = false
                        } else {
                            next_enum_value = enum_value + 1usize
                            next_enum_negative = false
                            next_enum_valid = true
                        }
                    }
                }
                c.aggregate_fields[c.aggregate_field_count] = AggregateField { name: field_name, ty: field_type, enum_value: enum_value, enum_negative: enum_negative, has_enum_value: has_enum_value, token: c.tokens[field_node.token_start] }
                c.aggregate_field_count += 1usize
                aggregate.field_count += 1usize
            }
        }
        at += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    if kind != .Struct && aggregate.field_count == 0usize { ret InvalidType }
    c.aggregates[aggregate_index] = aggregate
    ret ok
}

fn seed_intrinsic_aggregates(c: *Checker, g: *graph.Graph) -> err {
    let (memory_module, has_memory) = graph.find_module(g, "e.mem")
    if has_memory {
        if c.aggregate_count == c.aggregates.len || c.aggregate_field_count + 2usize > c.aggregate_fields.len { ret Capacity }
        let usize_type = make_type(.Integer, "usize", memory_module)
        c.aggregates[c.aggregate_count] = Aggregate { name: "Stats", module_index: memory_module, kind: .Struct, first_field: c.aggregate_field_count, field_count: 2usize, first_comptime: c.comptime_parameter_count, comptime_count: 0usize, template_index: c.aggregate_count, first_argument: 0usize, generic: false, instance: false, backing_type: invalid_type(), token: zero }
        c.aggregate_fields[c.aggregate_field_count] = AggregateField { name: "used", ty: usize_type, enum_value: 0usize, enum_negative: false, has_enum_value: false, token: zero }
        c.aggregate_fields[c.aggregate_field_count + 1usize] = AggregateField { name: "capacity", ty: usize_type, enum_value: 0usize, enum_negative: false, has_enum_value: false, token: zero }
        c.aggregate_field_count += 2usize
        c.aggregate_count += 1usize
    }
    ret ok
}

fn collect_aggregate_pass(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, register: bool) -> err {
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try parse.init_tree(&tree, g.nodes, g.children)
        try parse.parse(&tree, g.modules[module_index].text)
        try tokenize(c, g.modules[module_index].text)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .TypeDecl {
                if register {
                    try register_aggregate_declaration(c, r, g, &tree, module_index, node)
                } else {
                    try collect_aggregate_declaration(c, r, g, &tree, module_index, node)
                }
            }
            node_index += 1usize
        }
        module_index += 1usize
    }
    ret ok
}

// Spec section 14 invariant 7: module scope is order-independent. A field whose
// type instantiates a generic aggregate needs that aggregate's declaration, which
// may come later in the same file or in a module collected later, so every
// aggregate is registered before any field type is resolved.
fn collect_aggregates(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.aggregate_count = 0usize
    c.aggregate_field_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    try seed_intrinsic_aggregates(c, g)
    try collect_aggregate_pass(c, r, g, true)
    ret collect_aggregate_pass(c, r, g, false)
}

fn type_has_value_cycle(c: *Checker, ty: Type, cycle_root: usize, depth: usize) -> (bool, err) {
    let (subject, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret (false, canonical_error) }
    if subject.kind == .Pointer || subject.kind == .Slice { ret (false, ok) }
    if subject.kind == .Array {
        if !subject.has_element || subject.element >= c.type_count { ret (false, InvalidType) }
        let (cyclic, cycle_error) = type_has_value_cycle(c, c.types[subject.element], cycle_root, depth)
        ret (cyclic, cycle_error)
    }
    if subject.kind != .Named { ret (false, ok) }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found { ret (false, ok) }
    if aggregate_index == cycle_root { ret (true, ok) }
    if depth >= c.aggregate_count { ret (true, ok) }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind == .Enum { ret (false, ok) }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret (false, InvalidType) }
        let (cyclic, cycle_error) = type_has_value_cycle(c, c.aggregate_fields[field_index].ty, cycle_root, depth + 1usize)
        if cycle_error != ok { ret (false, cycle_error) }
        if cyclic { ret (true, ok) }
        at += 1usize
    }
    ret (false, ok)
}

fn validate_aggregate_value_cycles(c: *Checker) -> err {
    var aggregate_index = 0usize
    while aggregate_index < c.aggregate_count {
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind != .Enum {
            var at = 0usize
            while at < aggregate.field_count {
                let field_index = aggregate.first_field + at
                if field_index >= c.aggregate_field_count { ret InvalidType }
                let (cyclic, cycle_error) = type_has_value_cycle(c, c.aggregate_fields[field_index].ty, aggregate_index, 0usize)
                if cycle_error != ok { ret cycle_error }
                if cyclic {
                    record_failure_token(c, aggregate.module_index, aggregate.token, .RecursiveAggregate, aggregate.name, "")
                    ret InvalidType
                }
                at += 1usize
            }
        }
        aggregate_index += 1usize
    }
    ret ok
}

fn type_has_zero_value(c: *Checker, ty: Type, depth: usize) -> bool {
    let (subject, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if subject.kind == .Void || subject.kind == .Invalid || subject.kind == .Other { ret false }
    if subject.kind == .TypeParameter { ret true }
    if subject.kind == .Array {
        if !subject.has_element || subject.element >= c.type_count { ret false }
        ret type_has_zero_value(c, c.types[subject.element], depth)
    }
    if subject.kind != .Named { ret true }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind == .Enum {
        var member_at = 0usize
        while member_at < aggregate.field_count {
            let field = c.aggregate_fields[aggregate.first_field + member_at]
            if field.has_enum_value && field.enum_value == 0usize && !field.enum_negative { ret true }
            member_at += 1usize
        }
        ret false
    }
    if depth >= c.aggregate_count { ret false }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field = c.aggregate_fields[aggregate.first_field + field_at]
        if field.ty.kind != .Void && !type_has_zero_value(c, field.ty, depth + 1usize) { ret false }
        field_at += 1usize
    }
    ret true
}

fn aggregate_parameter(c: *Checker, template_index: usize, name: str) -> (usize, bool) {
    if template_index >= c.aggregate_count { ret (0usize, false) }
    let template = c.aggregates[template_index]
    var at = 0usize
    while at < template.comptime_count {
        let parameter_index = template.first_comptime + at
        if parameter_index < c.comptime_parameter_count && same(c.comptime_parameters[parameter_index].name, name) { ret (parameter_index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn aggregate_argument(c: *Checker, template_index: usize, first_argument: usize, parameter_index: usize) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    if template_index >= c.aggregate_count { ret (empty, false) }
    let template = c.aggregates[template_index]
    if parameter_index < template.first_comptime { ret (empty, false) }
    let offset = parameter_index - template.first_comptime
    if offset >= template.comptime_count { ret (empty, false) }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count || !c.generic_arguments[argument_index].set { ret (empty, false) }
    ret (c.generic_arguments[argument_index], true)
}

fn evaluate_aggregate_bound(c: *Checker, template_index: usize, first_argument: usize, expression_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .Literal {
        let (contextual_type, context_error) = apply_context(c, expression.ty, expected)
        if context_error != ok || (contextual_type.kind == .Integer && !integer_representable(expression.value, contextual_type)) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (expression.value, contextual_type, ok)
    }
    if expression.kind == .Name {
        var parameter_index = 0usize
        var parameter_found = false
        if template_index < c.aggregate_count && expression.module_index == c.aggregates[template_index].module_index {
            (parameter_index, parameter_found) = aggregate_parameter(c, template_index, expression.name)
        }
        if parameter_found {
            let parameter = c.comptime_parameters[parameter_index]
            if parameter.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
            let (argument, argument_found) = aggregate_argument(c, template_index, first_argument, parameter_index)
            if !argument_found || argument.symbolic { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            let (contextual_type, context_error) = apply_context(c, parameter.ty, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            ret (normalized_integer(argument.value, false), contextual_type, ok)
        }
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        let (contextual_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        if context_error != ok || !integer_representable(c.constants[constant_index].value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (c.constants[constant_index].value, contextual_type, ok)
    }
    if expression.kind == .Unary {
        var operand_expected = expected
        if expression.op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_aggregate_bound(c, template_index, first_argument, expression.left, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if expression.op == .PunctTilde {
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (left, left_type, left_error) = evaluate_aggregate_bound(c, template_index, first_argument, expression.left, expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(expression.op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_aggregate_bound(c, template_index, first_argument, expression.right, right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(expression.op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", expression.module_index) }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (expression.op == .PunctAmp || expression.op == .PunctCaret || expression.op == .PunctPipe || expression.op == .PunctAddWrap || expression.op == .PunctSubWrap || expression.op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, right_type)) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        let (result, result_error) = evaluate_integer_binary(expression.op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && expression.op != .PunctAddWrap && expression.op != .PunctSubWrap && expression.op != .PunctMulWrap && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}

fn aggregate_arguments_concrete(c: *Checker, template: Aggregate, first_argument: usize) -> bool {
    var at = 0usize
    while at < template.comptime_count {
        let argument = c.generic_arguments[first_argument + at]
        if !argument.set || argument.symbolic { ret false }
        if argument.kind == .Type && argument.ty.kind == .TypeParameter { ret false }
        at += 1usize
    }
    ret true
}

fn aggregate_arguments_equal(c: *Checker, template: Aggregate, first: usize, second: usize) -> bool {
    var at = 0usize
    while at < template.comptime_count {
        let left = c.generic_arguments[first + at]
        let right = c.generic_arguments[second + at]
        if !left.set || !right.set || left.kind != right.kind || left.symbolic || right.symbolic { ret false }
        if left.kind == .Type {
            if !type_equal(c, left.ty, right.ty) { ret false }
        } else {
            if left.symbolic != right.symbolic { ret false }
            if left.symbolic {
                if left.expression != right.expression { ret false }
            } else {
                if left.value != right.value { ret false }
            }
        }
        at += 1usize
    }
    ret true
}

fn find_aggregate_instance(c: *Checker, template_index: usize, first_argument: usize) -> (usize, bool) {
    if template_index >= c.aggregate_count { ret (0usize, false) }
    let template = c.aggregates[template_index]
    var at = template_index + 1usize
    while at < c.aggregate_count {
        let candidate = c.aggregates[at]
        if candidate.instance && !candidate.generic && candidate.template_index == template_index && aggregate_arguments_equal(c, template, candidate.first_argument, first_argument) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn substitute_aggregate_type(c: *Checker, template_index: usize, first_argument: usize, ty: Type) -> (Type, err) {
    if ty.kind == .TypeParameter {
        if !ty.has_element { ret (invalid_type(), InvalidType) }
        let (argument, found) = aggregate_argument(c, template_index, first_argument, ty.element)
        if !found || argument.kind != .Type || argument.symbolic { ret (invalid_type(), MissingContext) }
        ret (argument.ty, ok)
    }
    if ty.kind == .Named && ty.has_element {
        if ty.element >= c.aggregate_count || !c.aggregates[ty.element].instance { ret (invalid_type(), InvalidType) }
        let source = c.aggregates[ty.element]
        let nested_template = c.aggregates[source.template_index]
        if c.generic_argument_count + nested_template.comptime_count > c.generic_arguments.len { ret (invalid_type(), Capacity) }
        let nested_first = c.generic_argument_count
        var at = 0usize
        while at < nested_template.comptime_count {
            let source_argument = c.generic_arguments[source.first_argument + at]
            var nested_argument = source_argument
            if source_argument.kind == .Type {
                let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source_argument.ty)
                if specialize_error != ok { ret (invalid_type(), specialize_error) }
                nested_argument.ty = specialized
            } else {
                if source_argument.symbolic {
                    let (value, value_type, value_error) = evaluate_aggregate_bound(c, template_index, first_argument, source_argument.expression, make_type(.Integer, "usize", nested_template.module_index))
                    if value_error != ok || value.negative || (value_type.kind != .UntypedInteger && (value_type.kind != .Integer || !same(value_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
                    nested_argument.value = value.magnitude
                    nested_argument.symbolic = false
                }
            }
            c.generic_arguments[c.generic_argument_count] = nested_argument
            c.generic_argument_count += 1usize
            at += 1usize
        }
        let (nested_instance, instance_error) = instantiate_aggregate(c, source.template_index, nested_first)
        if instance_error != ok { ret (invalid_type(), instance_error) }
        var result = ty
        result.element = nested_instance
        ret (result, ok)
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), InvalidType) }
        let (element, element_error) = substitute_aggregate_type(c, template_index, first_argument, c.types[ty.element])
        if element_error != ok { ret (invalid_type(), element_error) }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var result = ty
        result.element = stored_element
        if ty.kind == .Array && !ty.has_length {
            let (length, length_type, length_error) = evaluate_aggregate_bound(c, template_index, first_argument, ty.array_length, make_type(.Integer, "usize", c.aggregates[template_index].module_index))
            if length_error != ok { ret (invalid_type(), length_error) }
            if length.negative || (length_type.kind != .UntypedInteger && (length_type.kind != .Integer || !same(length_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
            result.array_length = length.magnitude
            result.has_length = true
        }
        ret (result, ok)
    }
    if ty.kind == .Function {
        let (signature, has_signature) = function_signature_of(c, ty)
        if !has_signature { ret (invalid_type(), InvalidType) }
        var parameters: [16]Type = zero
        var returns: [4]Type = zero
        if signature.parameter_count > parameters.len || signature.return_count > returns.len { ret (invalid_type(), Capacity) }
        var at = 0usize
        while at < signature.parameter_count {
            let (source, has_source) = function_signature_parameter(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            parameters[at] = specialized
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (source, has_source) = function_signature_return(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            returns[at] = specialized
            at += 1usize
        }
        let (result, build_error) = build_function_type(c, parameters[..signature.parameter_count], returns[..signature.return_count], ty.module_index)
        ret (result, build_error)
    }
    ret (ty, ok)
}

fn instantiate_aggregate(c: *Checker, template_index: usize, first_argument: usize) -> (usize, err) {
    if template_index >= c.aggregate_count { ret (0usize, InvalidType) }
    let template = c.aggregates[template_index]
    if !template.generic || template.instance { ret (0usize, InvalidType) }
    let concrete = aggregate_arguments_concrete(c, template, first_argument)
    if concrete {
        let (cached, found) = find_aggregate_instance(c, template_index, first_argument)
        if found { ret (cached, ok) }
    }
    if c.aggregate_count == c.aggregates.len { ret (0usize, Capacity) }
    var instance = template
    instance.first_field = c.aggregate_field_count
    instance.field_count = 0usize
    instance.template_index = template_index
    instance.first_argument = first_argument
    instance.generic = !concrete
    instance.instance = true
    if concrete {
        if c.aggregate_field_count + template.field_count > c.aggregate_fields.len { ret (0usize, Capacity) }
        c.aggregate_field_count += template.field_count
        instance.field_count = template.field_count
        var at = 0usize
        while at < template.field_count {
            let source = c.aggregate_fields[template.first_field + at]
            let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source.ty)
            if specialize_error != ok { ret (0usize, specialize_error) }
            c.aggregate_fields[instance.first_field + at] = AggregateField { name: source.name, ty: specialized, enum_value: source.enum_value, enum_negative: source.enum_negative, has_enum_value: source.has_enum_value, token: source.token }
            at += 1usize
        }
    }
    let index = c.aggregate_count
    c.aggregates[index] = instance
    c.aggregate_count += 1usize
    ret (index, ok)
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
    if ty.kind == .String {
        c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Str, ty: ty }
        c.comptime_parameter_count += 1usize
        ret ok
    }
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
    item.owner_module_index = module_index
    if node.token_start < node.token_end && node.token_end <= c.token_count {
        item.source_start = c.tokens[node.token_start].start
        item.source_end = c.tokens[node.token_end - 1usize].end
    }
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
    item.owner_module_index = module_index
    item.first_parameter = c.parameter_count
    item.first_return = first_return
    item.return_count = return_count
    item.intrinsic = true
    c.functions[index] = item
    var generic: FunctionGeneric = zero
    c.function_generics[index] = generic
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
    // `view` is the one arena operation the language cannot express in source: it
    // turns a base pointer and an offset into a slice, which nothing else does.
    let u8_type = make_type(.Integer, "u8", module_index)
    let (bytes, bytes_error) = seeded_composite_type(c, .Slice, u8_type, false, module_index)
    if bytes_error != ok { ret bytes_error }
    let (const_arena_pointer, const_pointer_error) = seeded_composite_type(c, .Pointer, arena, true, module_index)
    if const_pointer_error != ok { ret const_pointer_error }
    let (view_index, view_error) = add_seeded_function(c, module_index, "view", bytes, false)
    if view_error != ok { ret view_error }
    try add_seeded_parameter(c, view_index, "a", const_arena_pointer)
    try add_seeded_parameter(c, view_index, "start", usize_type)
    try add_seeded_parameter(c, view_index, "len", usize_type)
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
    let seek_whence = make_type(.Named, "SeekWhence", os_module)
    let (seek_index, seek_error) = add_seeded_function(c, os_module, "seek", make_type(.Integer, "u64", os_module), true)
    if seek_error != ok { ret seek_error }
    try add_seeded_parameter(c, seek_index, "f", file)
    try add_seeded_parameter(c, seek_index, "off", i64_type)
    try add_seeded_parameter(c, seek_index, "whence", seek_whence)
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

// `push_err` is the one `e.str` declaration the library cannot write. Its answer is
// the merged error table, which is a property of the whole program rather than of any
// module, so the compiler supplies the function and `lower` generates its body.
fn seed_str_signatures(c: *Checker, str_module: usize) -> err {
    let builder_type = make_type(.Named, "Builder", str_module)
    let (builder_pointer, pointer_error) = seeded_composite_type(c, .Pointer, builder_type, false, str_module)
    if pointer_error != ok { ret pointer_error }
    let error_type = make_type(.Err, "err", str_module)
    let (push_err_index, push_err_error) = add_seeded_function(c, str_module, "push_err", error_type, false)
    if push_err_error != ok { ret push_err_error }
    try add_seeded_parameter(c, push_err_index, "b", builder_pointer)
    try add_seeded_parameter(c, push_err_index, "v", error_type)
    ret ok
}

fn seed_intrinsic_signatures(c: *Checker, g: *graph.Graph) -> err {
    let (mem_module, has_memory) = graph.find_module(g, "e.mem")
    if has_memory { try seed_memory_signatures(c, mem_module) }
    let (os_module, has_os) = graph.find_module(g, "e.os")
    if has_os { try seed_os_signatures(c, os_module, mem_module, has_memory) }
    let (str_module, has_str) = graph.find_module(g, "e.str")
    if has_str { try seed_str_signatures(c, str_module) }
    ret ok
}

fn collect_signatures(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
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

fn static_enum_member(c: *Checker, g: *graph.Graph, module_index: usize, node: syntax.Node) -> (Type, bool, bool) {
    var identifiers: [4]str = zero
    var count = 0usize
    let text = g.modules[module_index].text
    var at = node.token_start
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .Identifier {
            if count == 4usize { ret (invalid_type(), false, false) }
            identifiers[count] = text[token.start..token.end]
            count += 1usize
        }
        at += 1usize
    }
    var target_module = module_index
    var type_name = ""
    var member_name = ""
    var tag_member = false
    if count == 2usize {
        type_name = identifiers[0usize]
        member_name = identifiers[1usize]
    } else {
        if count == 3usize {
            let (imported, found_import) = imported_module(g, module_index, identifiers[0usize])
            if found_import {
                target_module = imported
                type_name = identifiers[1usize]
                member_name = identifiers[2usize]
            } else {
                if !same(identifiers[1usize], "Tag") { ret (invalid_type(), false, false) }
                type_name = identifiers[0usize]
                member_name = identifiers[2usize]
                tag_member = true
            }
        } else {
            if count != 4usize || !same(identifiers[2usize], "Tag") { ret (invalid_type(), false, false) }
            let (imported, found_import) = imported_module(g, module_index, identifiers[0usize])
            if !found_import { ret (invalid_type(), false, false) }
            target_module = imported
            type_name = identifiers[1usize]
            member_name = identifiers[3usize]
            tag_member = true
        }
    }
    let (_, found_type) = resolve.find(c.resolver, target_module, type_name, .Type)
    if !found_type { ret (invalid_type(), false, false) }
    let named = make_type(.Named, type_name, target_module)
    let (canonical, canonical_error) = canonical_type(c, named)
    if canonical_error != ok { ret (invalid_type(), false, false) }
    let (aggregate_index, found_aggregate) = aggregate_for_type(c, canonical)
    if !found_aggregate { ret (invalid_type(), false, false) }
    if tag_member {
        if c.aggregates[aggregate_index].kind != .TaggedUnion { ret (invalid_type(), false, false) }
    } else {
        if c.aggregates[aggregate_index].kind != .Enum { ret (invalid_type(), false, false) }
    }
    let (_, found_member) = aggregate_field_for_name(c, c.aggregates[aggregate_index], member_name)
    if !found_member { ret (invalid_type(), false, true) }
    if !tag_member { ret (canonical, true, true) }
    let (tag, found_tag) = tagged_union_tag_type(c, canonical)
    if !found_tag { ret (invalid_type(), false, false) }
    ret (tag, true, true)
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
    c.constants[c.constant_count] = Constant { name: name, module_index: module_index, ty: declared_type, expression: copied_expression, value: normalized_integer(0usize, false), state: 0u8, token: c.tokens[node.token_start] }
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

fn integer_width(ty: Type) -> usize {
    if ty.kind != .Integer { ret 0usize }
    if same(ty.name, "i8") || same(ty.name, "u8") { ret 8usize }
    if same(ty.name, "i16") || same(ty.name, "u16") { ret 16usize }
    if same(ty.name, "i32") || same(ty.name, "u32") { ret 32usize }
    ret 64usize
}

fn integer_mask(width: usize) -> usize {
    var result = 0usize
    var at = 0usize
    while at < width {
        result = result * 2usize + 1usize
        at += 1usize
    }
    ret result
}

fn integer_sign_bit(width: usize) -> usize {
    var result = 1usize
    var at = 1usize
    while at < width {
        result = result * 2usize
        at += 1usize
    }
    ret result
}

fn integer_bits(value: IntegerValue, width: usize) -> usize {
    let mask = integer_mask(width)
    if !value.negative { ret value.magnitude }
    if value.magnitude == 0usize { ret 0usize }
    ret mask - (value.magnitude - 1usize)
}

fn integer_from_bits(bits: usize, ty: Type) -> IntegerValue {
    let width = integer_width(ty)
    let mask = integer_mask(width)
    let value = bits
    if unsigned_integer_type(ty) { ret normalized_integer(value, false) }
    let sign = integer_sign_bit(width)
    if value < sign { ret normalized_integer(value, false) }
    ret normalized_integer((mask - value) + 1usize, true)
}

fn bitwise_integer_bits(op: lex.Kind, left: usize, right: usize, width: usize) -> usize {
    var left_rest = left
    var right_rest = right
    var place = 1usize
    var result = 0usize
    var at = 0usize
    while at < width {
        let left_set = left_rest % 2usize != 0usize
        let right_set = right_rest % 2usize != 0usize
        var selected = left_set && right_set
        if op == .PunctPipe { selected = left_set || right_set }
        if op == .PunctCaret { selected = left_set != right_set }
        if selected { result += place }
        left_rest = left_rest / 2usize
        right_rest = right_rest / 2usize
        at += 1usize
        if at < width { place = place * 2usize }
    }
    ret result
}

fn modular_add(left: usize, right: usize, mask: usize) -> usize {
    if left <= mask - right { ret left + right }
    ret left - (mask - right) - 1usize
}

fn modular_subtract(left: usize, right: usize, mask: usize) -> usize {
    if left >= right { ret left - right }
    ret mask - (right - left) + 1usize
}

fn modular_multiply(left: usize, right: usize, mask: usize) -> usize {
    var result = 0usize
    var addend = left
    var multiplier = right
    while multiplier != 0usize {
        if multiplier % 2usize != 0usize { result = modular_add(result, addend, mask) }
        multiplier = multiplier / 2usize
        if multiplier != 0usize { addend = modular_add(addend, addend, mask) }
    }
    ret result
}

fn shift_left_bits(value: usize, count: usize, mask: usize) -> usize {
    var result = value
    var at = 0usize
    while at < count {
        result = modular_add(result, result, mask)
        at += 1usize
    }
    ret result
}

fn shift_right_bits(value: usize, count: usize) -> usize {
    var result = value
    var at = 0usize
    while at < count {
        result = result / 2usize
        at += 1usize
    }
    ret result
}

fn shift_right_signed(value: IntegerValue, count: usize) -> IntegerValue {
    var magnitude = value.magnitude
    var at = 0usize
    while at < count {
        magnitude = magnitude / 2usize + magnitude % 2usize
        at += 1usize
    }
    ret normalized_integer(magnitude, true)
}

fn evaluate_integer_binary(op: lex.Kind, left: IntegerValue, right: IntegerValue, left_type: Type, right_type: Type) -> (IntegerValue, err) {
    if is_shift(op) {
        if left_type.kind != .Integer || right_type.kind != .Integer || !unsigned_integer_type(right_type) || right.negative { ret (normalized_integer(0usize, false), InvalidOperator) }
        let width = integer_width(left_type)
        if right.magnitude >= width { ret (normalized_integer(0usize, false), InvalidConstant) }
        if op == .PunctShiftRight && !unsigned_integer_type(left_type) && left.negative {
            if right.magnitude == 0usize { ret (left, ok) }
            ret (shift_right_signed(left, right.magnitude), ok)
        }
        let left_bits = integer_bits(left, width)
        var result_bits = shift_left_bits(left_bits, right.magnitude, integer_mask(width))
        if op == .PunctShiftRight { result_bits = shift_right_bits(left_bits, right.magnitude) }
        ret (integer_from_bits(result_bits, left_type), ok)
    }
    if left_type.kind != .Integer { ret (normalized_integer(0usize, false), InvalidOperator) }
    if op == .PunctAmp || op == .PunctCaret || op == .PunctPipe {
        let width = integer_width(left_type)
        let left_bits = integer_bits(left, width)
        let right_bits = integer_bits(right, width)
        let result_bits = bitwise_integer_bits(op, left_bits, right_bits, width)
        ret (integer_from_bits(result_bits, left_type), ok)
    }
    if op == .PunctAddWrap || op == .PunctSubWrap || op == .PunctMulWrap {
        let width = integer_width(left_type)
        let mask = integer_mask(width)
        let left_bits = integer_bits(left, width)
        let right_bits = integer_bits(right, width)
        var result_bits = modular_add(left_bits, right_bits, mask)
        if op == .PunctSubWrap { result_bits = modular_subtract(left_bits, right_bits, mask) }
        if op == .PunctMulWrap { result_bits = modular_multiply(left_bits, right_bits, mask) }
        ret (integer_from_bits(result_bits, left_type), ok)
    }
    if op == .PunctPlus {
        let (value, value_error) = add_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctMinus {
        let (value, value_error) = subtract_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctStar {
        let (value, value_error) = multiply_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctSlash {
        let (value, value_error) = divide_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctPercent {
        let (value, value_error) = remainder_integer_values(left, right)
        ret (value, value_error)
    }
    ret (normalized_integer(0usize, false), Unsupported)
}

fn evaluate_constant_expr(c: *Checker, expression_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .Literal {
        let (contextual_type, context_error) = apply_context(c, expression.ty, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (expression.value, contextual_type, ok)
    }
    if expression.kind == .Name {
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (c.constants[constant_index].value, constant_type, ok)
    }
    if expression.kind == .Unary {
        var operand_expected = expected
        if expression.op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_constant_expr(c, expression.left, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if expression.op == .PunctTilde {
            if operand_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if !integer_representable(operand, operand_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (left, left_type, left_error) = evaluate_constant_expr(c, expression.left, expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(expression.op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_constant_expr(c, expression.right, right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(expression.op) {
            if right_type.kind == .UntypedInteger {
                right_type = make_type(.Integer, "u32", left_type.module_index)
            }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (expression.op == .PunctAmp || expression.op == .PunctCaret || expression.op == .PunctPipe || expression.op == .PunctAddWrap || expression.op == .PunctSubWrap || expression.op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, result_type)) {
            ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow)
        }
        let (result, result_error) = evaluate_integer_binary(expression.op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && expression.op != .PunctAddWrap && expression.op != .PunctSubWrap && expression.op != .PunctMulWrap && !integer_representable(result, result_type) {
            ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow)
        }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}

fn evaluate_constant(c: *Checker, constant_index: usize) -> err {
    if constant_index >= c.constant_count { ret InvalidConstant }
    if c.constants[constant_index].state == 2u8 { ret ok }
    if c.constants[constant_index].state == 1u8 {
        let cyclic = c.constants[constant_index]
        record_failure_token(c, cyclic.module_index, cyclic.token, .ConstantDependencyCycle, cyclic.name, "")
        ret ConstantCycle
    }
    c.constants[constant_index].state = 1u8
    let (value, actual_type, value_error) = evaluate_constant_expr(c, c.constants[constant_index].expression, c.constants[constant_index].ty)
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

fn evaluate_bound_expression(c: *Checker, function_index: usize, first_argument: usize, expression_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .Literal {
        let (contextual_type, context_error) = apply_context(c, expression.ty, expected)
        if context_error != ok || (contextual_type.kind == .Integer && !integer_representable(expression.value, contextual_type)) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (expression.value, contextual_type, ok)
    }
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
            let (contextual_type, context_error) = apply_context(c, parameter.ty, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            ret (normalized_integer(argument.value, false), contextual_type, ok)
        }
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        let (contextual_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        if context_error != ok || !integer_representable(c.constants[constant_index].value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (c.constants[constant_index].value, contextual_type, ok)
    }
    if expression.kind == .Unary {
        var operand_expected = expected
        if expression.op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_bound_expression(c, function_index, first_argument, expression.left, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if expression.op == .PunctTilde {
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (left, left_type, left_error) = evaluate_bound_expression(c, function_index, first_argument, expression.left, expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(expression.op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_bound_expression(c, function_index, first_argument, expression.right, right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(expression.op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", expression.module_index) }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (expression.op == .PunctAmp || expression.op == .PunctCaret || expression.op == .PunctPipe || expression.op == .PunctAddWrap || expression.op == .PunctSubWrap || expression.op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, right_type)) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        let (result, result_error) = evaluate_integer_binary(expression.op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && expression.op != .PunctAddWrap && expression.op != .PunctSubWrap && expression.op != .PunctMulWrap && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
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
    if ty.kind == .Named && ty.has_element {
        if ty.element >= c.aggregate_count || !c.aggregates[ty.element].instance { ret (invalid_type(), InvalidType) }
        let source = c.aggregates[ty.element]
        let template = c.aggregates[source.template_index]
        if c.generic_argument_count + template.comptime_count > c.generic_arguments.len { ret (invalid_type(), Capacity) }
        let aggregate_first = c.generic_argument_count
        var argument_at = 0usize
        while argument_at < template.comptime_count {
            let source_argument = c.generic_arguments[source.first_argument + argument_at]
            var aggregate_argument_value = source_argument
            if source_argument.kind == .Type {
                let (specialized, specialize_error) = substitute_type(c, function_index, first_argument, source_argument.ty)
                if specialize_error != ok { ret (invalid_type(), specialize_error) }
                aggregate_argument_value.ty = specialized
            } else {
                if source_argument.symbolic {
                    let (value, value_type, value_error) = evaluate_bound_expression(c, function_index, first_argument, source_argument.expression, make_type(.Integer, "usize", template.module_index))
                    if value_error != ok || value.negative || (value_type.kind != .UntypedInteger && (value_type.kind != .Integer || !same(value_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
                    aggregate_argument_value.value = value.magnitude
                    aggregate_argument_value.symbolic = false
                }
            }
            c.generic_arguments[c.generic_argument_count] = aggregate_argument_value
            c.generic_argument_count += 1usize
            argument_at += 1usize
        }
        let (aggregate_instance, aggregate_error) = instantiate_aggregate(c, source.template_index, aggregate_first)
        if aggregate_error != ok { ret (invalid_type(), aggregate_error) }
        var result = ty
        result.element = aggregate_instance
        ret (result, ok)
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
            let (length, length_type, length_error) = evaluate_bound_expression(c, function_index, first_argument, ty.array_length, make_type(.Integer, "usize", c.functions[function_index].module_index))
            if length_error != ok { ret (invalid_type(), length_error) }
            if length.negative || (length_type.kind != .UntypedInteger && (length_type.kind != .Integer || !same(length_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
            result.array_length = length.magnitude
            result.has_length = true
        }
        ret (result, ok)
    }
    if ty.kind == .Function {
        let (signature, has_signature) = function_signature_of(c, ty)
        if !has_signature { ret (invalid_type(), InvalidType) }
        var parameters: [16]Type = zero
        var returns: [4]Type = zero
        if signature.parameter_count > parameters.len || signature.return_count > returns.len { ret (invalid_type(), Capacity) }
        var at = 0usize
        while at < signature.parameter_count {
            let (source, has_source) = function_signature_parameter(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_type(c, function_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            parameters[at] = specialized
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (source, has_source) = function_signature_return(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_type(c, function_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            returns[at] = specialized
            at += 1usize
        }
        let (result, build_error) = build_function_type(c, parameters[..signature.parameter_count], returns[..signature.return_count], ty.module_index)
        ret (result, build_error)
    }
    ret (ty, ok)
}

// A comptime `str` argument must be a string literal. Nothing else has a value at the
// point the instance is chosen, and the whole reason the parameter is comptime is that
// the body -- or, for `format`, the expansion -- reads it while compiling.
fn bind_text_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize, spelling: str) -> err {
    if function_index >= c.signature_function_count { ret InvalidType }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret InvalidType }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret InvalidType }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count { ret Capacity }
    if c.generic_arguments[argument_index].set {
        if c.generic_arguments[argument_index].kind != .Str { ret TypeMismatch }
        if !same(c.generic_arguments[argument_index].text, spelling) { ret TypeMismatch }
        ret ok
    }
    c.generic_arguments[argument_index].kind = .Str
    c.generic_arguments[argument_index].text = spelling
    c.generic_arguments[argument_index].symbolic = false
    c.generic_arguments[argument_index].set = true
    ret ok
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
            if left.kind == .Str {
                if !same(left.text, right.text) { ret false }
            } else {
                if left.value != right.value { ret false }
            }
        }
        at += 1usize
    }
    ret true
}

// A NIR function is identified by its owning module, its name and this
// discriminator, so the discriminator has to separate every instance a module
// owns under one name -- including instances of same-named templates declared in
// different modules, such as `list.init` and `heap.init` used by one consumer.
fn owner_instance_count(c: *Checker, owner_module_index: usize, name: str) -> usize {
    var count = 0usize
    var at = c.signature_function_count
    while at < c.function_count {
        let candidate = c.function_generics[at]
        if candidate.instance && c.functions[at].owner_module_index == owner_module_index && same(c.functions[at].name, name) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn instance_owner(c: *Checker, module_index: usize) -> usize {
    if c.active_owner_set { ret c.active_owner_module }
    ret module_index
}

fn find_function_instance(c: *Checker, owner_module_index: usize, template_index: usize, first_argument: usize) -> (usize, bool) {
    var at = c.signature_function_count
    while at < c.function_count {
        let candidate = c.function_generics[at]
        if candidate.instance && candidate.template_index == template_index && c.functions[at].owner_module_index == owner_module_index && generic_arguments_equal(c, template_index, candidate.first_argument, first_argument) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn function_arguments_concrete(c: *Checker, function_index: usize, first_argument: usize) -> bool {
    if function_index >= c.signature_function_count { ret false }
    let function = c.function_generics[function_index]
    var at = 0usize
    while at < function.comptime_count {
        let argument_index = first_argument + at
        if argument_index >= c.generic_argument_count { ret false }
        let argument = c.generic_arguments[argument_index]
        if !argument.set || argument.symbolic { ret false }
        if argument.kind == .Type && type_depends_on_comptime(c, argument.ty) { ret false }
        at += 1usize
    }
    ret true
}

fn instantiate_function(c: *Checker, owner_module_index: usize, template_index: usize, first_argument: usize) -> (usize, err) {
    let (cached, found) = find_function_instance(c, owner_module_index, template_index, first_argument)
    if found { ret (cached, ok) }
    if template_index >= c.signature_function_count || c.function_count == c.functions.len { ret (0usize, Capacity) }
    let template = c.functions[template_index]
    var instance: Function = zero
    instance.name = template.name
    instance.module_index = template.module_index
    instance.owner_module_index = owner_module_index
    // The instance is code in the instantiating module, but its body is still the
    // template's source, so it keeps the template's source range.
    instance.source_start = template.source_start
    instance.source_end = template.source_end
    instance.instance_id = owner_instance_count(c, owner_module_index, template.name) + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = template.parameter_count
    instance.first_return = c.return_type_count
    instance.return_count = template.return_count
    instance.generic = !function_arguments_concrete(c, template_index, first_argument)
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
        c.generic_arguments[c.generic_argument_count] = GenericArgument { kind: parameter.kind, ty: invalid_type(), value: 0usize, text: "", expression: 0usize, symbolic: false, set: false }
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
                    if parameter.kind == .Str {
                        let argument_node = tree.nodes[node_index]
                        if argument_node.kind != .LiteralExpr { ret (0usize, TypeMismatch) }
                        let literal = c.tokens[argument_node.token_start]
                        if literal.kind != .String && literal.kind != .RawString { ret (0usize, TypeMismatch) }
                        let spelling = g.modules[module_index].text[literal.start..literal.end]
                        let bind_error = bind_text_argument(c, template_index, first_argument, generic.first_comptime + argument_position, spelling)
                        if bind_error != ok { ret (0usize, bind_error) }
                    } else {
                        let (value, value_error) = array_length_value(c, g, tree, module_index, node_index)
                        if value_error == ok {
                            let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, invalid_type(), value, .Integer)
                            if bind_error != ok { ret (0usize, bind_error) }
                        } else {
                            if !c.generic_declaration { ret (0usize, InvalidType) }
                            let (expression, expression_error) = copy_constant_expr(c, g, tree, module_index, node_index)
                            if expression_error != ok { ret (0usize, InvalidType) }
                            let argument_index = first_argument + argument_position
                            c.generic_arguments[argument_index].expression = expression
                            c.generic_arguments[argument_index].symbolic = true
                            c.generic_arguments[argument_index].set = true
                        }
                    }
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
    var dependent_runtime = false
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
                if type_depends_on_comptime(c, actual) { dependent_runtime = true }
                let inference_error = infer_comptime_type(c, template_index, first_argument, formal, actual)
                if inference_error != ok { ret (0usize, inference_error) }
            }
            runtime_position += 1usize
        }
        at += 1usize
    }
    at = 0usize
    while at < generic.comptime_count {
        if !c.generic_arguments[first_argument + at].set && (!c.generic_declaration || !dependent_runtime) {
            let parameter = c.comptime_parameters[generic.first_comptime + at]
            record_failure(c, module_index, call, .GenericInference, parameter.name, "")
            ret (0usize, MissingContext)
        }
        at += 1usize
    }
    if c.generic_declaration && !function_arguments_concrete(c, template_index, first_argument) { ret (template_index, ok) }
    let (instance_index, instance_error) = instantiate_function(c, instance_owner(c, module_index), template_index, first_argument)
    ret (instance_index, instance_error)
}

type CallInfo = struct {
    function: Function,
    cast: Type,
    is_cast: bool,
    alloc_return: Type,
    alloc_arena: Type,
    mem_alloc: bool,
    // `e.meta`'s scalar reflection: which question was asked and the answer, both
    // settled here. Section 9 keeps reflection entirely at compile time, so what
    // reaches lowering is a constant and never the type itself.
    meta_query: MetaQuery,
    meta_value: usize,
    meta_name: str,
    meta_result: Type,
    mem_cast: bool,
    mem_bitcast: bool,
    formatter: bool,
    formatter_arena: bool,
    formatter_verbs: usize,
    formatter_spelling: str,
    protocol_pending: bool,
    protocol_builtin: ProtocolBuiltin,
    protocol_type: Type,
    indirect: bool,
    indirect_type: Type,
}

type MetaQuery = enum u8 {
    None,
    Kind,
    ArrayLen,
    TypeName,
}

type MetaInfo = struct {
    matched: bool,
    query: MetaQuery,
    result: Type,
    value: usize,
    name: str,
    function: Function,
}

type AllocInfo = struct {
    matched: bool,
    function: Function,
    return_type: Type,
    arena_type: Type,
}

type CastInfo = struct {
    matched: bool,
    function: Function,
    target: Type,
}

type BitcastInfo = struct {
    matched: bool,
    function: Function,
    target: Type,
}

type FormatterInfo = struct {
    matched: bool,
    function: Function,
    arena: bool,
    verbs: usize,
    spelling: str,
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
            if argument_found { ret (argument.ty, ok) }
            var parameter_type = make_type(.TypeParameter, name, module_index)
            parameter_type.element = parameter_index
            parameter_type.has_element = true
            ret (parameter_type, ok)
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

// Spec section 8: `mem.bitcast` is legal only where neither type holds a pointer,
// slice, function pointer, `type` or `Atomic` at any depth. That is what stops a pun
// from casting away `const`, inventing provenance, changing an address space or
// manufacturing a callable address, and it is a property of the type alone -- the
// sizes are compared during lowering, where the layout is reachable.
fn punnable_type(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > c.aggregate_count + 1usize { ret false }
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if canonical.kind == .Bool || canonical.kind == .Err || canonical.kind == .Integer || canonical.kind == .Float { ret true }
    if canonical.kind == .Array {
        if !canonical.has_element || canonical.element >= c.type_count { ret false }
        ret punnable_type(c, c.types[canonical.element], depth + 1usize)
    }
    if canonical.kind != .Named && canonical.kind != .Tag { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, canonical)
    if !found { ret false }
    let aggregate = c.aggregates[aggregate_index]
    // An enum and a tagged union's tag are their backing integer's bytes. Reading
    // bytes that name no member is section 11's `invalid` check, not a type error.
    if aggregate.kind == .Enum || canonical.kind == .Tag { ret punnable_type(c, aggregate.backing_type, depth + 1usize) }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index >= c.aggregate_field_count { ret false }
        let member = c.aggregate_fields[field_index]
        // A tagged union's void-payload arms carry no bytes of their own.
        if member.ty.kind != .Void || aggregate.kind != .TaggedUnion {
            if !punnable_type(c, member.ty, depth + 1usize) { ret false }
        }
        field_at += 1usize
    }
    if aggregate.kind == .TaggedUnion { ret punnable_type(c, aggregate.backing_type, depth + 1usize) }
    ret true
}

// `mem.bitcast[T](x)` reads `x`'s bytes as a `T`, so a pun never needs a `union`. The
// call names no declared function and is recognised the way `mem.alloc[T]` and
// `mem.cast[P]` are.
fn bitcast_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (BitcastInfo, err) {
    var info: BitcastInfo = zero
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
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "bitcast") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (punned, punned_error) = comptime_type(c, g, tree, module_index, type_index)
    if punned_error != ok { ret (info, punned_error) }
    if !punnable_type(c, punned, 0usize) { ret (info, InvalidType) }
    var function: Function = zero
    function.name = "bitcast"
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    info.target = punned
    ret (info, ok)
}

// Section 4's verbs. `Text` never reaches a caller: it is the state between verbs.
type FormatVerb = enum u8 {
    Text,
    Default,
    Hex,
    Binary,
    Fixed,
}

// One decoded byte of a string literal, and where the scan continues. The format
// string is the decoded text, not the spelling, so `{` reached through an escape is
// a verb like any other and `{{` is the only way to write a brace that is not one.
fn literal_byte(spelling: str, at: usize, raw: bool, next: *usize) -> (u8, err) {
    if at >= spelling.len { ret (0u8, InvalidType) }
    let byte = spelling[at]
    if raw || byte != 92u8 {
        *next = at + 1usize
        ret (byte, ok)
    }
    if at + 1usize >= spelling.len { ret (0u8, InvalidType) }
    let escaped = spelling[at + 1usize]
    *next = at + 2usize
    if escaped == 110u8 { ret (10u8, ok) }
    if escaped == 116u8 { ret (9u8, ok) }
    if escaped == 114u8 { ret (13u8, ok) }
    if escaped == 92u8 { ret (92u8, ok) }
    if escaped == 34u8 { ret (34u8, ok) }
    if escaped == 39u8 { ret (39u8, ok) }
    if escaped == 48u8 { ret (0u8, ok) }
    if escaped != 120u8 { ret (0u8, InvalidType) }
    if at + 3usize >= spelling.len { ret (0u8, InvalidType) }
    var value = 0u8
    var digit = 0usize
    while digit < 2usize {
        let hex = spelling[at + 2usize + digit]
        var nibble = 16u8
        if hex >= 48u8 && hex <= 57u8 { nibble = hex - 48u8 }
        if hex >= 97u8 && hex <= 102u8 { nibble = hex - 87u8 }
        if hex >= 65u8 && hex <= 70u8 { nibble = hex - 55u8 }
        if nibble == 16u8 { ret (0u8, InvalidType) }
        value = value * 16u8 + nibble
        digit += 1usize
    }
    *next = at + 4usize
    ret (value, ok)
}

// Strips the quotes and the raw-string hashes, leaving the contents and whether
// backslashes inside are escapes or bytes.
fn literal_contents(spelling: str, raw: *bool) -> (str, err) {
    if spelling.len >= 2usize && spelling[0usize] == 34u8 && spelling[spelling.len - 1usize] == 34u8 {
        *raw = false
        ret (spelling[1usize..spelling.len - 1usize], ok)
    }
    if spelling.len < 3usize || spelling[0usize] != 114u8 { ret ("", InvalidType) }
    var at = 1usize
    var hashes = 0usize
    while at < spelling.len && spelling[at] == 35u8 {
        at += 1usize
        hashes += 1usize
    }
    if at >= spelling.len || spelling[at] != 34u8 || spelling.len < at + hashes + 2usize { ret ("", InvalidType) }
    let closing = spelling.len - hashes - 1usize
    if spelling[closing] != 34u8 { ret ("", InvalidType) }
    *raw = true
    ret (spelling[at + 1usize..closing], ok)
}

// Reads the verbs out of a format string in order. `{{` and `}}` are the literal
// braces; a bare `}` is malformed, and so is an unterminated or unknown verb.
fn format_verbs(spelling: str, kinds: []FormatVerb, precisions: []u8) -> (usize, err) {
    var raw = false
    let (body, body_error) = literal_contents(spelling, &raw)
    if body_error != ok { ret (0usize, body_error) }
    var count = 0usize
    var at = 0usize
    while at < body.len {
        var next = 0usize
        let (byte, byte_error) = literal_byte(body, at, raw, &next)
        if byte_error != ok { ret (0usize, byte_error) }
        at = next
        if byte == 125u8 {
            // A closing brace is only legal doubled.
            if at >= body.len { ret (0usize, InvalidFormat) }
            let (following, following_error) = literal_byte(body, at, raw, &next)
            if following_error != ok { ret (0usize, following_error) }
            if following != 125u8 { ret (0usize, InvalidFormat) }
            at = next
            continue
        }
        if byte != 123u8 { continue }
        if at >= body.len { ret (0usize, InvalidFormat) }
        let (following, following_error) = literal_byte(body, at, raw, &next)
        if following_error != ok { ret (0usize, following_error) }
        if following == 123u8 {
            at = next
            continue
        }
        if count == kinds.len || count == precisions.len { ret (0usize, Capacity) }
        var kind: FormatVerb = .Default
        var precision = 0u8
        var scan = at
        var body_byte = following
        var body_next = next
        if body_byte == 120u8 || body_byte == 98u8 {
            if body_byte == 120u8 { kind = .Hex } else { kind = .Binary }
            scan = body_next
            if scan >= body.len { ret (0usize, InvalidFormat) }
            let (closer, closer_error) = literal_byte(body, scan, raw, &body_next)
            if closer_error != ok { ret (0usize, closer_error) }
            if closer != 125u8 { ret (0usize, InvalidFormat) }
            scan = body_next
        } else {
            if body_byte == 46u8 {
                kind = .Fixed
                scan = body_next
                var digits = 0usize
                var value = 0usize
                while scan < body.len {
                    let (digit, digit_error) = literal_byte(body, scan, raw, &body_next)
                    if digit_error != ok { ret (0usize, digit_error) }
                    if digit < 48u8 || digit > 57u8 { break }
                    // Section 4 caps a format-literal precision at 99, and a larger
                    // one is a compile error rather than a runtime `BadNumber`.
                    if digits == 2usize { ret (0usize, InvalidFormat) }
                    value = value * 10usize + usize(digit - 48u8)
                    digits += 1usize
                    scan = body_next
                }
                if digits == 0usize { ret (0usize, InvalidFormat) }
                precision = u8(value)
                if scan >= body.len { ret (0usize, InvalidFormat) }
                let (closer, closer_error) = literal_byte(body, scan, raw, &body_next)
                if closer_error != ok { ret (0usize, closer_error) }
                if closer != 125u8 { ret (0usize, InvalidFormat) }
                scan = body_next
            } else {
                if body_byte != 125u8 { ret (0usize, InvalidFormat) }
                scan = body_next
            }
        }
        kinds[count] = kind
        precisions[count] = precision
        count += 1usize
        at = scan
    }
    ret (count, ok)
}

// The format grammar is small enough to pin exactly, and it is read from a literal's
// spelling, so the cases below are written the way a caller writes them.
fn format_self_test() -> err {
    var kinds: [8]FormatVerb = zero
    var precisions: [8]u8 = zero
    // A verb of each shape, and the precision a fixed one carries.
    let (one, one_error) = format_verbs("\"{}\"", kinds[..], precisions[..])
    if one_error != ok || one != 1usize || kinds[0usize] != .Default { ret InvalidFormat }
    let (hex, hex_error) = format_verbs("\"{x}\"", kinds[..], precisions[..])
    if hex_error != ok || hex != 1usize || kinds[0usize] != .Hex { ret InvalidFormat }
    let (binary, binary_error) = format_verbs("\"{b}\"", kinds[..], precisions[..])
    if binary_error != ok || binary != 1usize || kinds[0usize] != .Binary { ret InvalidFormat }
    let (fixed, fixed_error) = format_verbs("\"{.3}\"", kinds[..], precisions[..])
    if fixed_error != ok || fixed != 1usize || kinds[0usize] != .Fixed || precisions[0usize] != 3u8 { ret InvalidFormat }
    let (none_precision, none_precision_error) = format_verbs("\"{.0}\"", kinds[..], precisions[..])
    if none_precision_error != ok || precisions[0usize] != 0u8 { ret InvalidFormat }
    let (widest, widest_error) = format_verbs("\"{.99}\"", kinds[..], precisions[..])
    if widest_error != ok || precisions[0usize] != 99u8 { ret InvalidFormat }

    // Verbs in order, with text around and between them.
    let (mixed, mixed_error) = format_verbs("\"a{}b{x}c{.2}d\"", kinds[..], precisions[..])
    if mixed_error != ok || mixed != 3usize { ret InvalidFormat }
    if kinds[0usize] != .Default || kinds[1usize] != .Hex || kinds[2usize] != .Fixed { ret InvalidFormat }
    if precisions[2usize] != 2u8 { ret InvalidFormat }

    // A doubled brace is a literal brace and not a verb, in either direction.
    let (doubled, doubled_error) = format_verbs("\"{{}}\"", kinds[..], precisions[..])
    if doubled_error != ok || doubled != 0usize { ret InvalidFormat }
    let (wrapped, wrapped_error) = format_verbs("\"{{{}}}\"", kinds[..], precisions[..])
    if wrapped_error != ok || wrapped != 1usize { ret InvalidFormat }
    let (empty, empty_error) = format_verbs("\"\"", kinds[..], precisions[..])
    if empty_error != ok || empty != 0usize { ret InvalidFormat }
    let (plain, plain_error) = format_verbs("\"no verbs here\"", kinds[..], precisions[..])
    if plain_error != ok || plain != 0usize { ret InvalidFormat }

    // The format string is the decoded text, so a brace reached through an escape is
    // a verb and a raw string's backslash is a byte.
    let (escaped, escaped_error) = format_verbs("\"\\x7b}\"", kinds[..], precisions[..])
    if escaped_error != ok || escaped != 1usize || kinds[0usize] != .Default { ret InvalidFormat }
    let (newline, newline_error) = format_verbs("\"{}\\n\"", kinds[..], precisions[..])
    if newline_error != ok || newline != 1usize { ret InvalidFormat }
    let (raw, raw_error) = format_verbs("r\"{}\"", kinds[..], precisions[..])
    if raw_error != ok || raw != 1usize { ret InvalidFormat }

    // Malformed: an unterminated verb, a bare closing brace, an unknown verb, and a
    // precision that is missing, too long, or unterminated.
    let (open_brace, open_brace_error) = format_verbs("\"{\"", kinds[..], precisions[..])
    if open_brace_error != InvalidFormat { ret InvalidFormat }
    let (close_brace, close_brace_error) = format_verbs("\"}\"", kinds[..], precisions[..])
    if close_brace_error != InvalidFormat { ret InvalidFormat }
    let (unknown, unknown_error) = format_verbs("\"{z}\"", kinds[..], precisions[..])
    if unknown_error != InvalidFormat { ret InvalidFormat }
    let (bare_point, bare_point_error) = format_verbs("\"{.}\"", kinds[..], precisions[..])
    if bare_point_error != InvalidFormat { ret InvalidFormat }
    let (too_wide, too_wide_error) = format_verbs("\"{.100}\"", kinds[..], precisions[..])
    if too_wide_error != InvalidFormat { ret InvalidFormat }
    let (unterminated, unterminated_error) = format_verbs("\"{.1\"", kinds[..], precisions[..])
    if unterminated_error != InvalidFormat { ret InvalidFormat }
    let (trailing, trailing_error) = format_verbs("\"a{\"", kinds[..], precisions[..])
    if trailing_error != InvalidFormat { ret InvalidFormat }
    // A closing brace followed by anything but another one, and a verb body that
    // is not a verb: each is reached only when the string does not also run out,
    // so a shorter spelling of either is caught by the wrong check.
    let (loose_close, loose_close_error) = format_verbs("\"}a\"", kinds[..], precisions[..])
    if loose_close_error != InvalidFormat { ret InvalidFormat }
    let (unknown_body, unknown_body_error) = format_verbs("\"{z}}\"", kinds[..], precisions[..])
    if unknown_body_error != InvalidFormat { ret InvalidFormat }
    ret ok
}

// A format string carries at most this many verbs. It is a limit on one literal, not
// on a program, and reaching it is `Capacity` rather than a wrong expansion.
fn format_verb_limit() -> usize {
    ret 32usize
}

fn format_verb_count(spelling: str) -> (usize, err) {
    var kinds: [32]FormatVerb = zero
    var precisions: [32]u8 = zero
    let (count, count_error) = format_verbs(spelling, kinds[..], precisions[..])
    ret (count, count_error)
}

fn format_verb_at(spelling: str, index: usize) -> (FormatVerb, u8, err) {
    var kinds: [32]FormatVerb = zero
    var precisions: [32]u8 = zero
    let (count, count_error) = format_verbs(spelling, kinds[..], precisions[..])
    if count_error != ok { ret (.Text, 0u8, count_error) }
    if index >= count { ret (.Text, 0u8, ArgumentCount) }
    ret (kinds[index], precisions[index], ok)
}

// Section 4: formattable is every shape rule 4 supplies a `format` for. This is the
// half the checker can decide without reaching a module's own `format`, which is why
// a `Named` type is left to the protocol lookup rather than judged here.
fn formattable_type(c: *Checker, ty: Type, kind: FormatVerb) -> bool {
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if kind == .Hex || kind == .Binary { ret canonical.kind == .Integer }
    if kind == .Fixed { ret canonical.kind == .Float }
    if canonical.kind == .Integer || canonical.kind == .Float { ret true }
    if canonical.kind == .Bool || canonical.kind == .Err || canonical.kind == .String { ret true }
    if canonical.kind == .Pointer || canonical.kind == .Slice || canonical.kind == .Array { ret true }
    if canonical.kind == .Named || canonical.kind == .Tag { ret is_enum_type(c, canonical) }
    ret false
}

// Spec section 8: a pointer type -- `*void` included -- is only reached through
// `mem.cast[*Foo](p)`. The call names no declared function, so it is recognised
// here the way `mem.alloc[T]` is, and both its argument and its comptime type have
// to be pointers. The value itself is unchanged: lowering hands the operand back.
fn cast_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (CastInfo, err) {
    var info: CastInfo = zero
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
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "cast") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (pointer, pointer_error) = comptime_type(c, g, tree, module_index, type_index)
    if pointer_error != ok { ret (info, pointer_error) }
    if pointer.kind != .Pointer { ret (info, InvalidType) }
    var function: Function = zero
    function.name = "cast"
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    info.target = pointer
    ret (info, ok)
}

// Section 9's kinds, in the order `e.meta.TypeKind` declares them. A reflected kind
// is that enum's value, so the two lists are one list and have to stay so.
fn meta_kind_value(c: *Checker, ty: Type) -> (usize, err) {
    if ty.kind == .Integer || ty.kind == .UntypedInteger { ret (0usize, ok) }
    if ty.kind == .Float || ty.kind == .UntypedFloat { ret (1usize, ok) }
    if ty.kind == .Bool { ret (2usize, ok) }
    if ty.kind == .Err { ret (3usize, ok) }
    if ty.kind == .Pointer { ret (4usize, ok) }
    if ty.kind == .Slice || ty.kind == .String { ret (5usize, ok) }
    if ty.kind == .Array { ret (6usize, ok) }
    if ty.kind == .Named || ty.kind == .Tag {
        let (aggregate_index, found) = aggregate_for_type(c, ty)
        if !found { ret (0usize, InvalidType) }
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind == .Enum { ret (8usize, ok) }
        if aggregate.kind == .TaggedUnion { ret (9usize, ok) }
        if aggregate.kind == .Struct { ret (7usize, ok) }
        // A bare `union` is the one aggregate section 9's list has no kind for.
        ret (0usize, Unsupported)
    }
    ret (0usize, InvalidType)
}

// `e.meta`'s scalar half: three questions whose answer is a constant the checker
// already holds. `fields`, `members`, `get` and `set` are not here -- they need a
// comptime value of struct type, which the language does not carry yet.
fn meta_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (MetaInfo, err) {
    var info: MetaInfo = zero
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
    if !found_member || !same(g.modules[target_module].name, "e.meta") { ret (info, ok) }
    var query: MetaQuery = .None
    if same(member, "kind") { query = .Kind }
    if same(member, "array_len") { query = .ArrayLen }
    if same(member, "type_name") { query = .TypeName }
    if query == .None { ret (info, ok) }
    info.matched = true
    info.query = query
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, type_index)
    if subject_error != ok { ret (info, subject_error) }
    if subject.kind == .Void || subject.kind == .Invalid { ret (info, InvalidType) }
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = 0usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    if query == .Kind {
        let (value, value_error) = meta_kind_value(c, subject)
        if value_error != ok { ret (info, value_error) }
        info.value = value
        info.result = make_type(.Named, "TypeKind", target_module)
        ret (info, ok)
    }
    if query == .ArrayLen {
        if subject.kind != .Array { ret (info, InvalidType) }
        info.value = subject.array_length
        info.result = make_type(.Integer, "usize", target_module)
        ret (info, ok)
    }
    // A composite has no written name of its own, and building one -- `[]u8`, `*T` --
    // means spelling a nesting and a length, which this does not do yet.
    if subject.name.len == 0usize { ret (info, Unsupported) }
    info.name = subject.name
    info.result = make_type(.String, "str", target_module)
    ret (info, ok)
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
    function.intrinsic = true
    info.function = function
    info.return_type = result
    info.arena_type = arena_pointer
    ret (info, ok)
}

// Section 4: `str.format[FMT](a, args: ...)` and `io.printf[FMT](args: ...)` are
// expanded rather than called, so the compiler recognises them the way it recognises
// `mem.alloc[T]`. Arity and argument types are checked against the format string
// here, which is what makes a mismatched count or an unformattable type a compile
// error rather than a runtime one.
fn formatter_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (FormatterInfo, err) {
    var info: FormatterInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = receiver.first_child + receiver.child_count
    var at = receiver.first_child
    var child_count = 0usize
    var base_index = 0usize
    var format_index = 0usize
    while at < end {
        if tree.children[at].node {
            if child_count == 0usize {
                base_index = tree.children[at].index
            } else {
                format_index = tree.children[at].index
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member { ret (info, ok) }
    let module_name = g.modules[target_module].name
    var arena = false
    if same(module_name, "e.str") && same(member, "format") {
        arena = true
    } else {
        if !same(module_name, "e.io") || !same(member, "printf") { ret (info, ok) }
    }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let format_node = tree.nodes[format_index]
    if format_node.kind != .LiteralExpr { ret (info, TypeMismatch) }
    let literal = c.tokens[format_node.token_start]
    if literal.kind != .String && literal.kind != .RawString { ret (info, TypeMismatch) }
    let spelling = g.modules[module_index].text[literal.start..literal.end]
    let (verbs, verbs_error) = format_verb_count(spelling)
    if verbs_error != ok { ret (info, verbs_error) }
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = verbs
    function.return_count = 1usize
    if arena {
        function.parameter_count = verbs + 1usize
        function.return_count = 2usize
    }
    function.intrinsic = true
    info.function = function
    info.arena = arena
    info.verbs = verbs
    info.spelling = spelling
    ret (info, ok)
}

fn formatter_instance_matches(c: *Checker, candidate: usize, owner_module_index: usize, target_module: usize, member: str, spelling: str, argument_types: []const Type) -> bool {
    let generic = c.function_generics[candidate]
    if !generic.formatter || !same(generic.formatter_spelling, spelling) { ret false }
    let function = c.functions[candidate]
    if function.owner_module_index != owner_module_index || function.module_index != target_module { ret false }
    if !same(function.name, member) || function.parameter_count != argument_types.len { ret false }
    var at = 0usize
    while at < argument_types.len {
        if !type_equal(c, c.parameters[function.first_parameter + at].ty, argument_types[at]) { ret false }
        at += 1usize
    }
    ret true
}

// The expansion becomes a function of its own rather than code inlined at the call.
// That keeps every existing path -- the multiple-return call, the error propagation,
// the linker's instance naming -- working unchanged, and cross-module inlining folds
// it back in where it is small enough to be worth it. One instance per calling
// module, formatter, format string and argument-type list, so two calls that agree
// share a body and two that differ do not.
fn formatter_instance(c: *Checker, owner_module_index: usize, target_module: usize, member: str, spelling: str, argument_types: []const Type, arena: bool) -> (usize, err) {
    var at = c.signature_function_count
    while at < c.function_count {
        if formatter_instance_matches(c, at, owner_module_index, target_module, member, spelling, argument_types) { ret (at, ok) }
        at += 1usize
    }
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    if c.parameter_count + argument_types.len > c.parameters.len { ret (0usize, Capacity) }
    var instance: Function = zero
    instance.name = member
    instance.module_index = target_module
    instance.owner_module_index = owner_module_index
    instance.instance_id = owner_instance_count(c, owner_module_index, member) + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = argument_types.len
    instance.first_return = c.return_type_count
    instance.return_count = 1usize
    if arena { instance.return_count = 2usize }
    var fill = 0usize
    while fill < argument_types.len {
        c.parameters[c.parameter_count] = Parameter { name: "", ty: argument_types[fill] }
        c.parameter_count += 1usize
        fill += 1usize
    }
    if arena {
        let text_error = store_return_type(c, make_type(.String, "str", target_module))
        if text_error != ok { ret (0usize, text_error) }
    }
    let error_error = store_return_type(c, make_type(.Err, "err", target_module))
    if error_error != ok { ret (0usize, error_error) }
    var generic: FunctionGeneric = zero
    generic.instance = true
    generic.checked = true
    generic.formatter = true
    generic.formatter_spelling = spelling
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

// The sink `printf` hands to `str.builder_to`. Its shape -- `fn(*void, []const u8) ->
// err` -- is not one `e.io` declares, and it cannot be added to `e.io` because the
// language has no visibility mechanism and the surface is frozen (spec section 12).
// So the compiler generates it, once per module that calls `printf`, the same way it
// generates the expansions themselves.
fn formatter_sink_instance(c: *Checker, owner_module_index: usize, io_module: usize) -> (usize, err) {
    var at = c.signature_function_count
    while at < c.function_count {
        if c.function_generics[at].formatter_sink && c.functions[at].owner_module_index == owner_module_index { ret (at, ok) }
        at += 1usize
    }
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    if c.parameter_count + 2usize > c.parameters.len { ret (0usize, Capacity) }
    let u8_type = make_type(.Integer, "u8", io_module)
    let (bytes, bytes_error) = seeded_composite_type(c, .Slice, u8_type, true, io_module)
    if bytes_error != ok { ret (0usize, bytes_error) }
    var instance: Function = zero
    instance.name = "print_sink"
    instance.module_index = io_module
    instance.owner_module_index = owner_module_index
    instance.instance_id = owner_instance_count(c, owner_module_index, "print_sink") + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = 2usize
    instance.first_return = c.return_type_count
    instance.return_count = 1usize
    c.parameters[c.parameter_count] = Parameter { name: "ctx", ty: make_type(.Pointer, "", io_module) }
    c.parameters[c.parameter_count + 1usize] = Parameter { name: "bytes", ty: bytes }
    c.parameter_count += 2usize
    let return_error = store_return_type(c, make_type(.Err, "err", io_module))
    if return_error != ok { ret (0usize, return_error) }
    var generic: FunctionGeneric = zero
    generic.instance = true
    generic.checked = true
    generic.formatter = true
    generic.formatter_sink = true
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

// One `push_err` body per module that calls it, for the same reason a formatter gets
// one: the body is generated, so it belongs to the module that asked for it rather
// than to `e.str`.
fn error_push_instance(c: *Checker, owner_module_index: usize, str_module: usize) -> (usize, err) {
    var at = c.signature_function_count
    while at < c.function_count {
        if c.function_generics[at].formatter_error && c.functions[at].owner_module_index == owner_module_index { ret (at, ok) }
        at += 1usize
    }
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    if c.parameter_count + 2usize > c.parameters.len { ret (0usize, Capacity) }
    let (seeded_index, found_seeded) = find_function(c, str_module, "push_err")
    if !found_seeded { ret (0usize, UnknownCallable) }
    let seeded = c.functions[seeded_index]
    var instance: Function = zero
    instance.name = "push_err"
    instance.module_index = str_module
    instance.owner_module_index = owner_module_index
    instance.instance_id = owner_instance_count(c, owner_module_index, "push_err") + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = 2usize
    instance.first_return = c.return_type_count
    instance.return_count = 1usize
    c.parameters[c.parameter_count] = c.parameters[seeded.first_parameter]
    c.parameters[c.parameter_count + 1usize] = c.parameters[seeded.first_parameter + 1usize]
    c.parameter_count += 2usize
    let return_error = store_return_type(c, make_type(.Err, "err", str_module))
    if return_error != ok { ret (0usize, return_error) }
    var generic: FunctionGeneric = zero
    generic.instance = true
    generic.checked = true
    generic.formatter = true
    generic.formatter_error = true
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

fn check_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (CallInfo, err) {
    var info: CallInfo = zero
    // The formatter's arguments become the parameters of the instance its call
    // resolves to, so they are kept as they are checked.
    var formatter_types: [33]Type = zero
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
                    let (callee_local, callee_is_local) = find_local(c, name)
                    if callee_is_local && c.locals[callee_local].ty.kind == .Function {
                        let (signature, has_signature) = function_signature_of(c, c.locals[callee_local].ty)
                        if !has_signature { ret (info, InvalidType) }
                        info.indirect = true
                        info.indirect_type = c.locals[callee_local].ty
                        info.function.module_index = module_index
                        info.function.parameter_count = signature.parameter_count
                        info.function.return_count = signature.return_count
                        has_function = true
                    } else {
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
                    }
                } else {
                    if receiver.kind == .BracketPostfix {
                        let (reflection, reflection_error) = meta_info(c, g, tree, module_index, receiver)
                        if reflection_error != ok { ret (info, reflection_error) }
                        if reflection.matched {
                            info.function = reflection.function
                            info.meta_query = reflection.query
                            info.meta_value = reflection.value
                            info.meta_name = reflection.name
                            info.meta_result = reflection.result
                            has_function = true
                            ret (info, ok)
                        }
                        let (allocation, allocation_error) = alloc_info(c, g, tree, module_index, receiver)
                        if allocation_error != ok { ret (info, allocation_error) }
                        if allocation.matched {
                            info.function = allocation.function
                            info.alloc_return = allocation.return_type
                            info.alloc_arena = allocation.arena_type
                            info.mem_alloc = true
                        } else {
                        let (conversion, conversion_error) = cast_info(c, g, tree, module_index, receiver)
                        if conversion_error != ok { ret (info, conversion_error) }
                        if conversion.matched {
                            info.function = conversion.function
                            info.cast = conversion.target
                            info.mem_cast = true
                        } else {
                        let (pun, pun_error) = bitcast_info(c, g, tree, module_index, receiver)
                        if pun_error != ok { ret (info, pun_error) }
                        if pun.matched {
                            info.function = pun.function
                            info.cast = pun.target
                            info.mem_bitcast = true
                        } else {
                        let (formatter, formatter_error) = formatter_info(c, g, tree, module_index, receiver)
                        if formatter_error != ok { ret (info, formatter_error) }
                        if formatter.matched {
                            info.function = formatter.function
                            info.formatter = true
                            info.formatter_arena = formatter.arena
                            info.formatter_verbs = formatter.verbs
                            info.formatter_spelling = formatter.spelling
                        } else {
                            let (template_index, template_error) = bracket_function(c, g, tree, module_index, receiver)
                            if template_error != ok { ret (info, template_error) }
                            let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, template_index)
                            if specialize_error != ok { ret (info, specialize_error) }
                            info.function = c.functions[specialized_index]
                        }
                        }
                        }
                        }
                        has_function = true
                    } else {
                        if receiver.kind != .FieldExpr { ret (info, Unsupported) }
                        let (protocol_type, protocol_name, is_protocol) = protocol_receiver(c, g, tree, module_index, receiver)
                        if is_protocol {
                            if protocol_type.kind == .Invalid {
                                // The template's own body: the receiver is still
                                // symbolic, so resolution waits for the instantiation.
                                info.protocol_pending = true
                            } else {
                                let (protocol_index, protocol_builtin, protocol_error) = check_protocol_call(c, g, tree, module_index, node, protocol_type, protocol_name)
                                if protocol_error != ok { ret (info, protocol_error) }
                                if protocol_builtin == .None {
                                    info.function = c.functions[protocol_index]
                                } else {
                                    let (supplied_receiver, supplied_error) = canonical_type(c, protocol_type)
                                    if supplied_error != ok { ret (info, supplied_error) }
                                    info.protocol_builtin = protocol_builtin
                                    info.protocol_type = supplied_receiver
                                    info.function.module_index = supplied_receiver.module_index
                                    info.function.parameter_count = supplied_protocol_parameters(protocol_builtin)
                                    info.function.return_count = 1usize
                                }
                            }
                            has_function = true
                        } else {
                            let (found_index, found) = find_qualified_function(c, g, tree, module_index, receiver)
                            if found {
                                if c.functions[found_index].generic {
                                    let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, found_index)
                                    if specialize_error != ok { ret (info, specialize_error) }
                                    info.function = c.functions[specialized_index]
                                } else {
                                    info.function = c.functions[found_index]
                                }
                            } else {
                                let (field_type, field_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                                if field_error != ok { ret (info, UnknownCallable) }
                                if field_type.kind != .Function { ret (info, UnknownCallable) }
                                let (signature, has_signature) = function_signature_of(c, field_type)
                                if !has_signature { ret (info, InvalidType) }
                                info.indirect = true
                                info.indirect_type = field_type
                                info.function.module_index = module_index
                                info.function.parameter_count = signature.parameter_count
                                info.function.return_count = signature.return_count
                            }
                            has_function = true
                        }
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
                    if info.protocol_pending {
                        let (pending_type, pending_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if pending_error != ok { ret (info, pending_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    let function = info.function
                    if child_position > function.parameter_count { ret (info, ArgumentCount) }
                    var parameter_type = invalid_type()
                    if info.indirect {
                        let (signature, has_signature) = function_signature_of(c, info.indirect_type)
                        if !has_signature { ret (info, InvalidType) }
                        let (indirect_parameter, has_parameter) = function_signature_parameter(c, signature, child_position - 1usize)
                        if !has_parameter { ret (info, ArgumentCount) }
                        let (indirect_argument, indirect_argument_error) = check_expr(c, g, tree, module_index, child_index, indirect_parameter)
                        if indirect_argument_error != ok { ret (info, indirect_argument_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.protocol_builtin != .None {
                        parameter_type = info.protocol_type
                        let (supplied_argument, supplied_argument_error) = check_expr(c, g, tree, module_index, child_index, parameter_type)
                        if supplied_argument_error != ok { ret (info, supplied_argument_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.mem_cast {
                        let (source, source_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if source_error != ok { ret (info, source_error) }
                        if source.kind != .Pointer { ret (info, TypeMismatch) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.formatter {
                        var verb_position = child_position - 1usize
                        if info.formatter_arena {
                            if verb_position == 0usize {
                                // `format` writes into the caller's arena; `printf`
                                // has one of its own.
                                let (supplied, supplied_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                                if supplied_error != ok { ret (info, supplied_error) }
                                if supplied.kind != .Pointer || !supplied.has_element || supplied.element >= c.type_count { ret (info, TypeMismatch) }
                                let pointee = c.types[supplied.element]
                                if pointee.kind != .Named || !same(pointee.name, "Arena") { ret (info, TypeMismatch) }
                                if verb_position >= formatter_types.len { ret (info, Capacity) }
                                formatter_types[verb_position] = supplied
                                child_position += 1usize
                                at += 1usize
                                continue
                            }
                            verb_position = verb_position - 1usize
                        }
                        if verb_position >= info.formatter_verbs { ret (info, ArgumentCount) }
                        let (verb, verb_precision, verb_error) = format_verb_at(info.formatter_spelling, verb_position)
                        if verb_error != ok { ret (info, verb_error) }
                        let (supplied, supplied_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if supplied_error != ok { ret (info, supplied_error) }
                        if is_untyped(supplied) { ret (info, MissingContext) }
                        if !formattable_type(c, supplied, verb) { ret (info, InvalidFormat) }
                        if child_position - 1usize >= formatter_types.len { ret (info, Capacity) }
                        formatter_types[child_position - 1usize] = supplied
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.mem_bitcast {
                        let (punned, punned_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if punned_error != ok { ret (info, punned_error) }
                        // An untyped literal has no bytes yet, so there is nothing to
                        // read as another type.
                        if is_untyped(punned) { ret (info, MissingContext) }
                        if !punnable_type(c, punned, 0usize) { ret (info, TypeMismatch) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
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
    if info.protocol_pending { ret (info, ok) }
    let function = info.function
    if child_position == 0usize || child_position - 1usize != function.parameter_count { ret (info, ArgumentCount) }
    if function.intrinsic && same(function.name, "push_err") && function.module_index < g.count && same(g.modules[function.module_index].name, "e.str") {
        let (instance_index, instance_error) = error_push_instance(c, module_index, function.module_index)
        if instance_error != ok { ret (info, instance_error) }
        info.function = c.functions[instance_index]
        ret (info, ok)
    }
    if info.formatter {
        let (instance_index, instance_error) = formatter_instance(c, module_index, function.module_index, function.name, info.formatter_spelling, formatter_types[0usize..function.parameter_count], info.formatter_arena)
        if instance_error != ok { ret (info, instance_error) }
        info.function = c.functions[instance_index]
        ret (info, ok)
    }
    if function.generic && !c.generic_declaration { ret (info, Unsupported) }
    ret (info, ok)
}

// Spec section 9 rule 1: `T.f(...)` is a protocol call only where T is a comptime
// type parameter. Returns the type bound to T, the protocol name, and whether the
// receiver is one at all. An invalid bound type means T is still symbolic, which is
// the case while a generic template's own body is checked.
fn protocol_receiver(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (Type, str, bool) {
    let (base_index, has_base) = first_node_child(tree, receiver)
    if !has_base { ret (invalid_type(), "", false) }
    let base_node = tree.nodes[base_index]
    if base_node.kind != .NameExpr { ret (invalid_type(), "", false) }
    if base_node.token_start >= c.token_count { ret (invalid_type(), "", false) }
    let base_token = c.tokens[base_node.token_start]
    if base_token.kind != .Identifier { ret (invalid_type(), "", false) }
    let text = g.modules[module_index].text
    let base = text[base_token.start..base_token.end]
    let (parameter_index, parameter_found) = active_comptime_parameter(c, base)
    if !parameter_found || c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), "", false) }
    var member = ""
    var at = base_node.token_end
    while at < receiver.token_end && at < c.token_count {
        let token = c.tokens[at]
        if token.kind == .Identifier { member = text[token.start..token.end] }
        at += 1usize
    }
    if member.len == 0usize { ret (invalid_type(), "", false) }
    let (argument, argument_found) = active_argument(c, parameter_index)
    if !argument_found { ret (invalid_type(), member, true) }
    ret (argument.ty, member, true)
}

// Spec section 9: the protocol function is `fn <t>_<protocol>` in the module that
// declares the receiver type, and its first parameter is the type by value.
fn protocol_function(c: *Checker, receiver: Type, protocol: str) -> (usize, bool, err) {
    let (canonical, canonical_error) = canonical_type(c, receiver)
    if canonical_error != ok { ret (0usize, false, canonical_error) }
    if canonical.kind != .Named { ret (0usize, false, ok) }
    var at = 0usize
    while at < c.signature_function_count {
        let candidate = c.functions[at]
        if candidate.module_index == canonical.module_index && protocol_name_matches(canonical.name, candidate.name, protocol) { ret (at, true, ok) }
        at += 1usize
    }
    ret (0usize, false, ok)
}

// An element inside a sequence reaches its comparison as an ordinary call when its
// own module declares one, so the sequence's supplied `cmp` covers `[]Point` as
// well as `[]i64`. The declaration has to match rule 3 exactly -- two parameters of
// the type by value, one `i32` back -- because nothing re-checks it at the call
// this synthesizes. A receiver's own `cmp` never reaches here: `check_protocol_call`
// resolves a declared one before any fallback is considered.
fn element_cmp_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (index, found) = component_protocol_function(c, ty, "cmp", make_type(.Integer, "i32", ty.module_index), 2usize)
    ret (index, found)
}

fn element_eq_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (index, found) = component_protocol_function(c, ty, "eq", make_type(.Bool, "bool", ty.module_index), 2usize)
    ret (index, found)
}

fn element_hash_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (index, found) = component_protocol_function(c, ty, "hash", make_type(.Integer, "u64", ty.module_index), 1usize)
    ret (index, found)
}

fn component_protocol_function(c: *Checker, ty: Type, protocol: str, expected_return: Type, arity: usize) -> (usize, bool) {
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok || canonical.kind != .Named { ret (0usize, false) }
    let (function_index, found, lookup_error) = protocol_function(c, ty, protocol)
    if lookup_error != ok || !found { ret (0usize, false) }
    let function = c.functions[function_index]
    if function.generic || function.parameter_count != arity || function.return_count != 1usize { ret (0usize, false) }
    if function.first_parameter + arity > c.parameter_count { ret (0usize, false) }
    var at = 0usize
    while at < arity {
        if !type_equal(c, c.parameters[function.first_parameter + at].ty, canonical) { ret (0usize, false) }
        at += 1usize
    }
    let (return_type, return_error) = function_return(c, function, 0usize)
    if return_error != ok || !type_equal(c, return_type, expected_return) { ret (0usize, false) }
    ret (function_index, true)
}

// Spec section 9 rule 4 supplies `cmp` for the scalar shapes, and for arrays,
// slices and vectors it recurses in index order. Rule 4 excludes pointers; floats
// and tagged unions are shapes rule 4 covers that are not supplied yet. The depth
// bound keeps a pathological alias chain from recursing without end; no honest
// type reaches it.
fn supplied_cmp_shape(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Err { ret true }
    let (enum_backing, is_enum) = enum_backing_type(c, ty)
    if is_enum && enum_backing.kind == .Integer { ret true }
    if ty.kind == .Named { ret tagged_union_comparable(c, ty, depth) }
    if ty.kind != .Array && ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret comparable_component(c, element, canonical_element, depth + 1usize)
}

// A component inside a sequence or a tagged union compares either through a shape
// rule 4 supplies or through its own module's declaration, in that order of
// discovery but with the declaration winning at emission (rule 4 again).
fn comparable_component(c: *Checker, ty: Type, canonical: Type, depth: usize) -> bool {
    if supplied_cmp_shape(c, canonical, depth) { ret true }
    let (component_function, has_component_function) = element_cmp_function(c, ty)
    ret has_component_function
}

fn is_tagged_union_type(c: *Checker, ty: Type) -> bool {
    if ty.kind != .Named { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    ret found && c.aggregates[aggregate_index].kind == .TaggedUnion
}

// Rule 4 orders a tagged union by its tag and then by the live payload, so every
// arm that carries one has to be comparable. A void arm carries nothing and is
// equal to itself once the tags match.
fn tagged_union_comparable(c: *Checker, ty: Type, depth: usize) -> bool {
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.backing_type.kind != .Integer { ret false }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret false }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            let (canonical_arm, canonical_arm_error) = canonical_type(c, arm.ty)
            if canonical_arm_error != ok { ret false }
            if !comparable_component(c, arm.ty, canonical_arm, depth + 1usize) { ret false }
        }
        at += 1usize
    }
    ret true
}

// Rule 4 hashes a value's canonical little-endian bytes with xxHash64 seed 0, and
// recurses into arrays and slices in index order. Where every leaf is one of these
// shapes that recursion *is* the memory: the elements sit contiguously in exactly
// those bytes, so hashing the whole run in one pass is the same answer as walking
// it. A nested slice, whose bytes are a pointer rather than its contents, and a
// tagged union, whose payload is padded, are rule 4 shapes not supplied yet.
fn packed_hash_bytes(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Err || ty.kind == .Pointer { ret true }
    let (enum_backing, is_enum) = enum_backing_type(c, ty)
    if is_enum && enum_backing.kind == .Integer { ret true }
    if ty.kind != .Array { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret packed_hash_bytes(c, canonical_element, depth + 1usize)
}

// A slice hashes over its contents, which rule 4 states outright for `str`. This is
// the exact condition under which the whole value is one contiguous run of canonical
// bytes and can be hashed in a single pass.
fn hash_packed_shape(c: *Checker, ty: Type) -> bool {
    if packed_hash_bytes(c, ty, 0usize) { ret true }
    if ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret packed_hash_bytes(c, canonical_element, 1usize)
}

// Everything else recurses in index or declaration order the way rule 4's other
// shapes do, folding one hash per component rather than hashing one byte run.
fn supplied_hash_shape(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if hash_packed_shape(c, ty) { ret true }
    if ty.kind == .Named { ret tagged_union_hashable(c, ty, depth) }
    if ty.kind != .Array && ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret hashable_component(c, element, canonical_element, depth + 1usize)
}

fn hashable_component(c: *Checker, ty: Type, canonical: Type, depth: usize) -> bool {
    if supplied_hash_shape(c, canonical, depth) { ret true }
    let (component_function, has_component_function) = element_hash_function(c, ty)
    ret has_component_function
}

fn tagged_union_hashable(c: *Checker, ty: Type, depth: usize) -> bool {
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.backing_type.kind != .Integer { ret false }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret false }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            let (canonical_arm, canonical_arm_error) = canonical_type(c, arm.ty)
            if canonical_arm_error != ok { ret false }
            if !hashable_component(c, arm.ty, canonical_arm, depth + 1usize) { ret false }
        }
        at += 1usize
    }
    ret true
}

fn supplied_eq_shape(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Err || ty.kind == .Pointer { ret true }
    let (enum_backing, is_enum) = enum_backing_type(c, ty)
    if is_enum && enum_backing.kind == .Integer { ret true }
    if ty.kind == .Named { ret tagged_union_equatable(c, ty, depth) }
    if ty.kind != .Array && ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret equatable_component(c, element, canonical_element, depth + 1usize)
}

fn equatable_component(c: *Checker, ty: Type, canonical: Type, depth: usize) -> bool {
    if supplied_eq_shape(c, canonical, depth) { ret true }
    let (component_function, has_component_function) = element_eq_function(c, ty)
    ret has_component_function
}

fn tagged_union_equatable(c: *Checker, ty: Type, depth: usize) -> bool {
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.backing_type.kind != .Integer { ret false }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret false }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            let (canonical_arm, canonical_arm_error) = canonical_type(c, arm.ty)
            if canonical_arm_error != ok { ret false }
            if !equatable_component(c, arm.ty, canonical_arm, depth + 1usize) { ret false }
        }
        at += 1usize
    }
    ret true
}

fn supplied_protocol(c: *Checker, canonical: Type, protocol: str) -> ProtocolBuiltin {
    if same(protocol, "cmp") {
        if supplied_cmp_shape(c, canonical, 0usize) { ret .Cmp }
        ret .None
    }
    if same(protocol, "hash") {
        if supplied_hash_shape(c, canonical, 0usize) { ret .Hash }
        ret .None
    }
    if same(protocol, "eq") {
        if supplied_eq_shape(c, canonical, 0usize) { ret .Eq }
        ret .None
    }
    ret .None
}

fn supplied_protocol_parameters(builtin: ProtocolBuiltin) -> usize {
    if builtin == .Hash { ret 1usize }
    ret 2usize
}

fn check_protocol_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, receiver: Type, protocol: str) -> (usize, ProtocolBuiltin, err) {
    let (canonical, canonical_error) = canonical_type(c, receiver)
    if canonical_error != ok { ret (0usize, .None, canonical_error) }
    var found = false
    var function_index = 0usize
    if canonical.kind == .Named {
        let (declared_index, declared, lookup_error) = protocol_function(c, receiver, protocol)
        if lookup_error != ok { ret (0usize, .None, lookup_error) }
        found = declared
        function_index = declared_index
    }
    if !found {
        // Rule 4: a declaration in the type's own module always wins over the
        // supplied one, so this is only reached when there is none.
        let builtin = supplied_protocol(c, canonical, protocol)
        if builtin != .None { ret (0usize, builtin, ok) }
        record_failure(c, module_index, node, .ProtocolMissing, canonical.name, protocol)
        ret (0usize, .None, UnknownCallable)
    }
    let function = c.functions[function_index]
    if function.generic {
        record_failure(c, module_index, node, .ProtocolGenericType, canonical.name, protocol)
        ret (0usize, .None, Unsupported)
    }
    // Rule 3: the first parameter is the receiver type, by value.
    if function.parameter_count == 0usize || function.first_parameter >= c.parameter_count {
        record_failure(c, module_index, node, .ProtocolSignature, canonical.name, function.name)
        ret (0usize, .None, InvalidType)
    }
    if !type_equal(c, c.parameters[function.first_parameter].ty, canonical) {
        record_failure(c, module_index, node, .ProtocolSignature, canonical.name, function.name)
        ret (0usize, .None, InvalidType)
    }
    ret (function_index, .None, ok)
}

fn function_return(c: *Checker, function: Function, index: usize) -> (Type, err) {
    if index >= function.return_count || function.first_return + index >= c.return_type_count { ret (invalid_type(), InvalidType) }
    ret (c.return_types[function.first_return + index], ok)
}

fn call_return(c: *Checker, call: CallInfo, index: usize) -> (Type, err) {
    if call.indirect {
        let (signature, has_signature) = function_signature_of(c, call.indirect_type)
        if !has_signature { ret (invalid_type(), InvalidType) }
        let (result, has_result) = function_signature_return(c, signature, index)
        if !has_result { ret (invalid_type(), InvalidType) }
        ret (result, ok)
    }
    if call.protocol_builtin == .Cmp {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.Integer, "i32", call.protocol_type.module_index), ok)
    }
    if call.protocol_builtin == .Hash {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.Integer, "u64", call.protocol_type.module_index), ok)
    }
    if call.protocol_builtin == .Eq {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.Bool, "bool", call.protocol_type.module_index), ok)
    }
    if call.protocol_pending {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.TypeParameter, "", 0usize), ok)
    }
    if index >= call.function.return_count { ret (invalid_type(), InvalidType) }
    if call.mem_cast || call.mem_bitcast {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (call.cast, ok)
    }

    if call.meta_query != .None {
        if index == 0usize { ret (call.meta_result, ok) }
        ret (invalid_type(), ArgumentCount)
    }
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

type BracketInfo = struct {
    base: usize,
    first: usize,
    second: usize,
    child_count: usize,
    range: bool,
}

fn read_bracket(c: *Checker, tree: *parse.Tree, node: syntax.Node, info: *BracketInfo) -> err {
    if node.kind != .BracketPostfix { ret parse.InvalidSyntax }
    info.base = 0usize
    info.first = 0usize
    info.second = 0usize
    info.child_count = 0usize
    info.range = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if info.child_count == 0usize { info.base = child_index }
            if info.child_count == 1usize { info.first = child_index }
            if info.child_count == 2usize { info.second = child_index }
            info.child_count += 1usize
        }
        at += 1usize
    }
    if info.child_count == 0usize { ret parse.InvalidSyntax }
    let base = tree.nodes[info.base]
    at = base.token_end
    while at < node.token_end {
        if c.tokens[at].kind == .PunctRange { info.range = true }
        at += 1usize
    }
    ret ok
}

fn index_element_type(c: *Checker, base: Type, module_index: usize) -> (Type, err) {
    if base.kind == .String { ret (make_type(.Integer, "u8", module_index), ok) }
    if base.kind != .Array && base.kind != .Slice { ret (invalid_type(), InvalidOperator) }
    if !base.has_element || base.element >= c.type_count { ret (invalid_type(), InvalidType) }
    ret (c.types[base.element], ok)
}

fn dependent_expression_type(source: Type, expected: Type, module_index: usize) -> Type {
    if expected.kind != .Invalid { ret expected }
    if source.kind == .TypeParameter { ret source }
    ret make_type(.TypeParameter, "", module_index)
}

fn literal_item_name(c: *Checker, text: str, item: syntax.Node) -> (str, bool) {
    var at = item.token_start
    while at < item.token_end {
        let token = c.tokens[at]
        if token.kind == .PunctColon { break }
        if token.kind == .Identifier { ret (text[token.start..token.end], true) }
        at += 1usize
    }
    ret ("", false)
}

fn literal_item_expression(tree: *parse.Tree, item: syntax.Node) -> (usize, bool) {
    let (expression, found) = first_node_child(tree, item)
    ret (expression, found)
}

fn literal_item_named(c: *Checker, tree: *parse.Tree, item: syntax.Node) -> bool {
    let (expression, has_expression) = literal_item_expression(tree, item)
    if !has_expression { ret false }
    var at = item.token_start
    let expression_start = tree.nodes[expression].token_start
    while at < expression_start {
        if c.tokens[at].kind == .PunctColon { ret true }
        at += 1usize
    }
    ret false
}

fn aggregate_literal_header(tree: *parse.Tree, node: syntax.Node) -> (usize, usize, err) {
    var header = 0usize
    var has_header = false
    var item_count = 0usize
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind == .LiteralItem {
                item_count += 1usize
            } else {
                if has_header { ret (0usize, 0usize, parse.InvalidSyntax) }
                header = child_index
                has_header = true
            }
        }
        at += 1usize
    }
    if !has_header || item_count == 0usize { ret (0usize, 0usize, parse.InvalidSyntax) }
    ret (header, item_count, ok)
}

fn check_array_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, header_index: usize, item_count: usize, expected: Type) -> (Type, err) {
    let header = tree.nodes[header_index]
    if header.kind != .ArrayType { ret (invalid_type(), InvalidType) }
    var element_index = 0usize
    var has_element = false
    let header_end = header.first_child + header.child_count
    var at = header.first_child
    while at < header_end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if is_type_node(tree.nodes[child_index].kind) {
                element_index = child_index
                has_element = true
            }
        }
        at += 1usize
    }
    if !has_element { ret (invalid_type(), parse.InvalidSyntax) }
    let (element, element_error) = type_from_node(c, c.resolver, g, tree, module_index, tree.nodes[element_index])
    if element_error != ok { ret (invalid_type(), element_error) }
    if element.kind == .Void { ret (invalid_type(), InvalidType) }
    let inferred = contains_token(c, header.token_start, header.token_end, .PunctUnderscore)
    var array = invalid_type()
    if inferred {
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        array = make_type(.Array, "", module_index)
        array.element = stored_element
        array.has_element = true
        array.array_length = item_count
        array.has_length = true
    } else {
        let (declared, declared_error) = type_from_node(c, c.resolver, g, tree, module_index, header)
        if declared_error != ok { ret (invalid_type(), declared_error) }
        if !declared.has_length {
            if !c.generic_declaration { ret (invalid_type(), TypeMismatch) }
        } else {
            if declared.array_length != item_count {
                record_failure(c, module_index, node, .ArrayElementCount, "", "")
                ret (invalid_type(), TypeMismatch)
            }
        }
        array = declared
    }
    let end = node.first_child + node.child_count
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let item = tree.nodes[tree.children[at].index]
            if item.kind == .LiteralItem {
                if literal_item_named(c, tree, item) { ret (invalid_type(), InvalidType) }
                let (expression, has_expression) = literal_item_expression(tree, item)
                if !has_expression { ret (invalid_type(), parse.InvalidSyntax) }
                let (_, expression_error) = check_expr(c, g, tree, module_index, expression, element)
                if expression_error != ok { ret (invalid_type(), expression_error) }
            }
        }
        at += 1usize
    }
    let (contextual, context_error) = apply_context(c, array, expected)
    ret (contextual, context_error)
}

fn aggregate_field_for_name(c: *Checker, aggregate: Aggregate, name: str) -> (usize, bool) {
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count && same(c.aggregate_fields[field_index].name, name) { ret (field_index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn literal_name_seen(c: *Checker, text: str, tree: *parse.Tree, node: syntax.Node, before_child: usize, name: str) -> bool {
    var at = node.first_child
    while at < before_child {
        if tree.children[at].node {
            let item = tree.nodes[tree.children[at].index]
            if item.kind == .LiteralItem {
                let (previous, found) = literal_item_name(c, text, item)
                if found && same(previous, name) { ret true }
            }
        }
        at += 1usize
    }
    ret false
}

fn check_named_aggregate_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, header_index: usize, item_count: usize, expected: Type) -> (Type, err) {
    let header = tree.nodes[header_index]
    if header.kind != .NamedType { ret (invalid_type(), InvalidType) }
    let (constructed_type, type_error) = type_from_node(c, c.resolver, g, tree, module_index, header)
    if type_error != ok { ret (invalid_type(), type_error) }
    if constructed_type.kind != .Named { ret (invalid_type(), InvalidType) }
    var aggregate_index = 0usize
    var found_aggregate = false
    if constructed_type.has_element && constructed_type.element < c.aggregate_count {
        aggregate_index = constructed_type.element
        found_aggregate = true
    } else {
        (aggregate_index, found_aggregate) = find_aggregate(c, constructed_type.module_index, constructed_type.name)
    }
    if !found_aggregate { ret (invalid_type(), InvalidType) }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance {
        if aggregate.template_index >= c.aggregate_count { ret (invalid_type(), InvalidType) }
        aggregate = c.aggregates[aggregate.template_index]
    }
    if aggregate.generic && !c.generic_declaration { ret (invalid_type(), Unsupported) }
    if aggregate.kind == .Enum { ret (invalid_type(), InvalidType) }
    if aggregate.kind == .Struct && item_count != aggregate.field_count { ret (invalid_type(), ArgumentCount) }
    if aggregate.kind != .Struct && item_count != 1usize { ret (invalid_type(), ArgumentCount) }
    let text = g.modules[module_index].text
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let item = tree.nodes[tree.children[at].index]
            if item.kind == .LiteralItem {
                let (name, has_name) = literal_item_name(c, text, item)
                if !has_name { ret (invalid_type(), InvalidType) }
                if literal_name_seen(c, text, tree, node, at, name) { ret (invalid_type(), ArgumentCount) }
                let (field_index, found_field) = aggregate_field_for_name(c, aggregate, name)
                if !found_field { ret (invalid_type(), InvalidType) }
                let field = c.aggregate_fields[field_index]
                let (expression, has_expression) = literal_item_expression(tree, item)
                let named = literal_item_named(c, tree, item)
                if aggregate.kind == .TaggedUnion && field.ty.kind == .Void {
                    if named || has_expression { ret (invalid_type(), TypeMismatch) }
                } else {
                    if !named || !has_expression { ret (invalid_type(), TypeMismatch) }
                    let (_, expression_error) = check_expr(c, g, tree, module_index, expression, field.ty)
                    if expression_error != ok { ret (invalid_type(), expression_error) }
                }
            }
        }
        at += 1usize
    }
    let (contextual, context_error) = apply_context(c, constructed_type, expected)
    ret (contextual, context_error)
}

fn check_aggregate_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, expected: Type) -> (Type, err) {
    let (header_index, item_count, header_error) = aggregate_literal_header(tree, node)
    if header_error != ok { ret (invalid_type(), header_error) }
    if tree.nodes[header_index].kind == .ArrayType {
        let (array, array_error) = check_array_literal(c, g, tree, module_index, node, header_index, item_count, expected)
        ret (array, array_error)
    }
    let (aggregate, aggregate_error) = check_named_aggregate_literal(c, g, tree, module_index, node, header_index, item_count, expected)
    ret (aggregate, aggregate_error)
}

fn direct_place_mutable(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, err) {
    let node = tree.nodes[node_index]
    if node.kind == .NameExpr {
        let token = c.tokens[node.token_start]
        if token.kind != .Identifier { ret (false, Unsupported) }
        let name = g.modules[module_index].text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if !found { ret (false, Unsupported) }
        ret (c.locals[local_index].mutable, ok)
    }
    if node.kind == .UnaryExpr && c.tokens[node.token_start].kind == .PunctStar {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (false, parse.InvalidSyntax) }
        let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
        if pointer_error != ok { ret (false, pointer_error) }
        if pointer.kind != .Pointer {
            if c.generic_declaration && type_shape_unknown(pointer) { ret (true, ok) }
            ret (false, InvalidOperator)
        }
        ret (!pointer.is_const, ok)
    }
    if node.kind == .BracketPostfix {
        var bracket: BracketInfo = zero
        let bracket_error = read_bracket(c, tree, node, &bracket)
        if bracket_error != ok { ret (false, bracket_error) }
        if bracket.range || bracket.child_count != 2usize { ret (false, Unsupported) }
        let (base, base_error) = check_expr(c, g, tree, module_index, bracket.base, invalid_type())
        if base_error != ok { ret (false, base_error) }
        if c.generic_declaration && type_shape_unknown(base) { ret (true, ok) }
        if base.kind == .Slice { ret (!base.is_const, ok) }
        if base.kind == .String { ret (false, ok) }
        if base.kind != .Array { ret (false, InvalidOperator) }
        let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, bracket.base)
        ret (mutable, mutable_error)
    }
    if node.kind == .FieldExpr {
        let (base_index, has_base) = first_node_child(tree, node)
        if !has_base { ret (false, parse.InvalidSyntax) }
        let (base, base_error) = check_expr(c, g, tree, module_index, base_index, invalid_type())
        if base_error != ok { ret (false, base_error) }
        if c.generic_declaration && type_shape_unknown(base) { ret (true, ok) }
        var subject = base
        var through_pointer = false
        var mutable = false
        while subject.kind == .Pointer {
            if !subject.has_element || subject.element >= c.type_count { ret (false, InvalidType) }
            through_pointer = true
            mutable = !subject.is_const
            subject = c.types[subject.element]
        }
        if through_pointer { ret (mutable, ok) }
        let (base_mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, base_index)
        ret (base_mutable, mutable_error)
    }
    ret (false, Unsupported)
}

fn check_bracket_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, expected: Type) -> (Type, err) {
    var bracket: BracketInfo = zero
    let bracket_error = read_bracket(c, tree, node, &bracket)
    if bracket_error != ok { ret (invalid_type(), bracket_error) }
    let (base, base_error) = check_expr(c, g, tree, module_index, bracket.base, invalid_type())
    if base_error != ok { ret (invalid_type(), base_error) }
    let (element, element_error) = index_element_type(c, base, module_index)
    let index_type = make_type(.Integer, "usize", module_index)
    if element_error != ok {
        if !c.generic_declaration || !type_shape_unknown(base) { ret (invalid_type(), element_error) }
        if bracket.range {
            if bracket.child_count > 3usize { ret (invalid_type(), ArgumentCount) }
            if bracket.child_count >= 2usize {
                let (_, first_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
                if first_error != ok { ret (invalid_type(), first_error) }
            }
            if bracket.child_count == 3usize {
                let (_, second_error) = check_expr(c, g, tree, module_index, bracket.second, index_type)
                if second_error != ok { ret (invalid_type(), second_error) }
            }
            let dependent = dependent_expression_type(base, invalid_type(), module_index)
            let (stored_element, store_error) = store_type(c, dependent)
            if store_error != ok { ret (invalid_type(), store_error) }
            var result = make_type(.Slice, "", module_index)
            result.element = stored_element
            result.has_element = true
            let (contextual, context_error) = apply_context(c, result, expected)
            ret (contextual, context_error)
        }
        if bracket.child_count != 2usize { ret (invalid_type(), ArgumentCount) }
        let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
        if index_error != ok { ret (invalid_type(), index_error) }
        ret (dependent_expression_type(base, expected, module_index), ok)
    }
    if bracket.range {
        if bracket.child_count > 3usize { ret (invalid_type(), ArgumentCount) }
        if bracket.child_count >= 2usize {
            let (_, first_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
            if first_error != ok { ret (invalid_type(), first_error) }
        }
        if bracket.child_count == 3usize {
            let (_, second_error) = check_expr(c, g, tree, module_index, bracket.second, index_type)
            if second_error != ok { ret (invalid_type(), second_error) }
        }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var result = make_type(.Slice, "", module_index)
        result.element = stored_element
        result.has_element = true
        if base.kind == .String {
            result.is_const = true
        } else {
            if base.kind == .Slice {
                result.is_const = base.is_const
            } else {
                let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, bracket.base)
                if mutable_error != ok { ret (invalid_type(), mutable_error) }
                result.is_const = !mutable
            }
        }
        let (contextual, context_error) = apply_context(c, result, expected)
        ret (contextual, context_error)
    }
    if bracket.child_count != 2usize { ret (invalid_type(), ArgumentCount) }
    let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
    if index_error != ok { ret (invalid_type(), index_error) }
    let (contextual, context_error) = apply_context(c, element, expected)
    ret (contextual, context_error)
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
        if token.kind == .KwZero || token.kind == .KwUndef {
            if expected.kind == .Invalid { ret (invalid_type(), MissingContext) }
            if token.kind == .KwZero && !type_has_zero_value(c, expected, 0usize) {
                record_failure(c, module_index, node, .MissingZeroValue, expected.name, expected.name)
                ret (invalid_type(), InvalidType)
            }
            ret (expected, ok)
        }
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
            if c.comptime_parameters[parameter_index].kind == .Str {
                let (text_type, text_context_error) = apply_context(c, make_type(.String, "str", module_index), expected)
                ret (text_type, text_context_error)
            }
            if c.comptime_parameters[parameter_index].kind != .Integer { ret (invalid_type(), InvalidType) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found {
                if c.generic_declaration {
                    let (parameter_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
                    ret (parameter_type, context_error)
                }
                ret (invalid_type(), MissingContext)
            }
            let (parameter_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
            ret (parameter_type, context_error)
        }
        let (constant_index, constant_found) = find_constant(c, module_index, name)
        if constant_found && c.constants[constant_index].state == 2u8 {
            let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
            ret (constant_type, context_error)
        }
        let (symbol_index, found_symbol) = resolve.find(c.resolver, module_index, name, .Value)
        let (intrinsic_function, has_intrinsic_function) = find_function(c, module_index, name)
        if found_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
            let (error_type, context_error) = apply_context(c, make_type(.Err, "err", module_index), expected)
            ret (error_type, context_error)
        }
        // Spec section 5: `fn(A) -> R` is a type, so naming a function in a value
        // position yields a pointer to it.
        if has_intrinsic_function {
            let callee = c.functions[intrinsic_function]
            if callee.generic || callee.intrinsic || callee.external { ret (invalid_type(), Unsupported) }
            let (pointer_type, pointer_error) = function_pointer_type(c, callee, module_index)
            if pointer_error != ok { ret (invalid_type(), pointer_error) }
            let (result_type, context_error) = apply_context(c, pointer_type, expected)
            ret (result_type, context_error)
        }
        ret (invalid_type(), Unsupported)
    }
    if node.kind == .MemberExpr {
        if expected.kind == .Invalid { ret (invalid_type(), MissingContext) }
        let (aggregate_index, found_aggregate) = aggregate_for_type(c, expected)
        if !found_aggregate { ret (invalid_type(), InvalidType) }
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind != .Enum && aggregate.kind != .TaggedUnion { ret (invalid_type(), InvalidType) }
        if expected.kind == .Tag && aggregate.kind != .TaggedUnion { ret (invalid_type(), InvalidType) }
        var member = ""
        var member_at = node.token_start
        while member_at < node.token_end {
            let member_token = c.tokens[member_at]
            if member_token.kind == .Identifier { member = text[member_token.start..member_token.end] }
            member_at += 1usize
        }
        let (field_index, found_member) = aggregate_field_for_name(c, aggregate, member)
        if !found_member { ret (invalid_type(), InvalidType) }
        if expected.kind != .Tag && aggregate.kind == .TaggedUnion && c.aggregate_fields[field_index].ty.kind != .Void { ret (invalid_type(), InvalidType) }
        ret (expected, ok)
    }
    if node.kind == .FieldExpr {
        let (enum_member_type, found_enum_member, enum_target) = static_enum_member(c, g, module_index, node)
        if found_enum_member {
            let (contextual_enum, context_error) = apply_context(c, enum_member_type, expected)
            ret (contextual_enum, context_error)
        }
        if enum_target { ret (invalid_type(), InvalidType) }
        let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
        if found_member {
            let (constant_index, constant_found) = find_constant(c, target_module, member)
            if constant_found && c.constants[constant_index].state == 2u8 {
                let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
                ret (constant_type, context_error)
            }
            let (symbol_index, found_symbol) = resolve.find(c.resolver, target_module, member, .Value)
            let (intrinsic_function, has_intrinsic_function) = find_function(c, target_module, member)
            if found_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let (error_type, context_error) = apply_context(c, make_type(.Err, "err", target_module), expected)
                ret (error_type, context_error)
            }
            // A qualified function named in a value position, like the unqualified
            // case above.
            if has_intrinsic_function {
                let callee = c.functions[intrinsic_function]
                if callee.generic || callee.intrinsic || callee.external { ret (invalid_type(), Unsupported) }
                let (pointer_type, pointer_error) = function_pointer_type(c, callee, target_module)
                if pointer_error != ok { ret (invalid_type(), pointer_error) }
                let (result_type, context_error) = apply_context(c, pointer_type, expected)
                ret (result_type, context_error)
            }
            ret (invalid_type(), Unsupported)
        }
        let (base_index, has_base) = first_node_child(tree, node)
        if !has_base { ret (invalid_type(), parse.InvalidSyntax) }
        let (field, has_field) = field_expression_name(c, text, tree, node)
        if !has_field { ret (invalid_type(), parse.InvalidSyntax) }
        let (base, base_error) = check_expr(c, g, tree, module_index, base_index, invalid_type())
        if base_error != ok { ret (invalid_type(), base_error) }
        if same(field, "len") && (base.kind == .Array || base.kind == .Slice || base.kind == .String) {
            let (length_type, context_error) = apply_context(c, make_type(.Integer, "usize", module_index), expected)
            ret (length_type, context_error)
        }
        if same(field, "tag") {
            let (tag, found_tag) = tagged_union_tag_type(c, base)
            if found_tag {
                let (contextual_tag, context_error) = apply_context(c, tag, expected)
                ret (contextual_tag, context_error)
            }
            if c.generic_declaration && type_shape_unknown(base) { ret (dependent_expression_type(base, expected, module_index), ok) }
        }
        let (field_index, found_field) = find_aggregate_field(c, base, field)
        if !found_field {
            if c.generic_declaration && type_shape_unknown(base) {
                if same(field, "len") {
                    let (length_type, context_error) = apply_context(c, make_type(.Integer, "usize", module_index), expected)
                    ret (length_type, context_error)
                }
                ret (dependent_expression_type(base, expected, module_index), ok)
            }
            ret (invalid_type(), InvalidType)
        }
        let (field_type, context_error) = apply_context(c, c.aggregate_fields[field_index].ty, expected)
        ret (field_type, context_error)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (group_type, group_error) = check_expr(c, g, tree, module_index, child_index, expected)
        ret (group_type, group_error)
    }
    if node.kind == .BracketPostfix {
        let (result, result_error) = check_bracket_expr(c, g, tree, module_index, node, expected)
        ret (result, result_error)
    }
    if node.kind == .AggregateLiteral {
        let (result, result_error) = check_aggregate_literal(c, g, tree, module_index, node, expected)
        ret (result, result_error)
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
            var place_type = invalid_type()
            var mutable = false
            if place.kind == .NameExpr {
                let token = c.tokens[place.token_start]
                let name = text[token.start..token.end]
                let (local_index, local_found) = find_local(c, name)
                if !local_found { ret (invalid_type(), Unsupported) }
                place_type = c.locals[local_index].ty
                mutable = c.locals[local_index].mutable
            } else {
                if place.kind != .BracketPostfix && place.kind != .FieldExpr && !(place.kind == .UnaryExpr && c.tokens[place.token_start].kind == .PunctStar) { ret (invalid_type(), Unsupported) }
                let (resolved_place, place_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                if place_error != ok { ret (invalid_type(), place_error) }
                place_type = resolved_place
                let (place_mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, child_index)
                if mutable_error != ok { ret (invalid_type(), mutable_error) }
                mutable = place_mutable
            }
            let (element_index, store_error) = store_type(c, place_type)
            if store_error != ok { ret (invalid_type(), store_error) }
            var pointer = make_type(.Pointer, "", module_index)
            pointer.element = element_index
            pointer.has_element = true
            pointer.is_const = !mutable
            let (result_type, context_error) = apply_context(c, pointer, expected)
            ret (result_type, context_error)
        }
        if op == .PunctStar {
            let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
            if pointer_error != ok { ret (invalid_type(), pointer_error) }
            if pointer.kind != .Pointer || !pointer.has_element || pointer.element >= c.type_count {
                if c.generic_declaration && type_shape_unknown(pointer) { ret (dependent_expression_type(pointer, expected, module_index), ok) }
                ret (invalid_type(), InvalidOperator)
            }
            let element = c.types[pointer.element]
            if element.kind == .Void { ret (invalid_type(), InvalidOperator) }
            let (result_type, context_error) = apply_context(c, element, expected)
            ret (result_type, context_error)
        }
        let (value_type, value_error) = check_expr(c, g, tree, module_index, child_index, expected)
        if value_error != ok { ret (invalid_type(), value_error) }
        if op == .PunctMinus && !is_numeric(value_type) {
            if !c.generic_declaration || !type_shape_unknown(value_type) { ret (invalid_type(), InvalidOperator) }
        }
        if op == .PunctTilde && !is_integer(value_type) {
            if !c.generic_declaration || !type_shape_unknown(value_type) { ret (invalid_type(), InvalidOperator) }
        }
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
        if is_shift(op) {
            let (left_type, left_error) = check_expr(c, g, tree, module_index, children[0usize], expected)
            if left_error != ok { ret (invalid_type(), left_error) }
            if !is_integer(left_type) || is_untyped(left_type) {
                if !c.generic_declaration || !type_shape_unknown(left_type) { ret (invalid_type(), InvalidOperator) }
            }
            let (right_type, right_error) = check_expr(c, g, tree, module_index, children[1usize], invalid_type())
            if right_error != ok { ret (invalid_type(), right_error) }
            var final_right = right_type
            if right_type.kind == .UntypedInteger {
                let (contextual_right, contextual_error) = apply_context(c, right_type, make_type(.Integer, "u32", module_index))
                if contextual_error != ok { ret (invalid_type(), contextual_error) }
                final_right = contextual_right
            }
            if final_right.kind != .Integer || !unsigned_integer_type(final_right) { ret (invalid_type(), InvalidOperator) }
            ret (left_type, ok)
        }
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
        if !type_equal(c, final_left, final_right) {
            if !c.generic_declaration || !types_may_match_after_instantiation(c, final_left, final_right) { ret (invalid_type(), TypeMismatch) }
        }
        if is_comparison(op) {
            if is_untyped(final_left) { ret (invalid_type(), MissingContext) }
            if !is_numeric(final_left) {
                if !is_enum_type(c, final_left) {
                    if !c.generic_declaration || !type_shape_unknown(final_left) {
                        if !is_equality(op) { ret (invalid_type(), InvalidOperator) }
                        if final_left.kind != .Bool && final_left.kind != .Err && final_left.kind != .Pointer { ret (invalid_type(), InvalidOperator) }
                    }
                }
            }
            let (result_type, context_error) = apply_context(c, make_type(.Bool, "bool", module_index), expected)
            ret (result_type, context_error)
        }
        if !is_numeric(final_left) {
            if c.generic_declaration && type_shape_unknown(final_left) { ret (final_left, ok) }
            ret (invalid_type(), InvalidOperator)
        }
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
        // A protocol call in a template body has no signature until the
        // instantiation binds its receiver, so its result follows the context.
        if call.protocol_pending { ret (dependent_expression_type(make_type(.TypeParameter, "", module_index), expected, module_index), ok) }
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

fn record_generic_type_arity_diagnostics(c: *Checker, g: *graph.Graph, module_index: usize, binding: syntax.Node, named: syntax.Node) {
    if named.token_start >= c.token_count { ret }
    let name_token = c.tokens[named.token_start]
    if name_token.kind != .Identifier { ret }
    let name = g.modules[module_index].text[name_token.start..name_token.end]
    let (aggregate_index, found) = find_aggregate(c, module_index, name)
    var reason = name
    if found {
        let aggregate = c.aggregates[aggregate_index]
        var field_at = 0usize
        while field_at < aggregate.field_count {
            let field = c.aggregate_fields[aggregate.first_field + field_at]
            if type_depends_on_comptime(c, field.ty) {
                append_failure_token(c, aggregate.module_index, field.token, .AggregateMemberUnknown, field.name, "")
                if same(reason, name) { reason = field.name }
            }
            field_at += 1usize
        }
    }
    append_failure_token(c, module_index, c.tokens[binding.token_start], .GenericTypeArity, name, "")
    append_failure_token(c, module_index, c.tokens[binding.token_start], .BindingUnknownNamed, name, "")
    var at = binding.token_start
    while at < binding.token_end {
        if c.tokens[at].kind == .KwZero {
            append_failure_token(c, module_index, c.tokens[at], .MissingZeroValue, name, reason)
            break
        }
        at += 1usize
    }
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
                    if type_error != ok {
                        if type_error == ArgumentCount && child.kind == .NamedType { record_generic_type_arity_diagnostics(c, g, module_index, node, child) }
                        ret type_error
                    }
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
        if contains_token(c, node.token_start, node.token_end, .KwZero) && !type_has_zero_value(c, declared, 0usize) {
            var zero_at = node.token_start
            while zero_at < node.token_end {
                if c.tokens[zero_at].kind == .KwZero {
                    record_failure_token(c, module_index, c.tokens[zero_at], .MissingZeroValue, declared.name, declared.name)
                    break
                }
                zero_at += 1usize
            }
            ret InvalidType
        }
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
    if c.defer_depth != 0usize { ret InvalidReturn }
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
                if node.kind == .WhileStmt {
                    c.loop_depth += 1usize
                    c.break_depth += 1usize
                }
                var branch_error = ok
                if child.kind == .Block {
                    branch_error = check_block(c, r, g, tree, module_index, child, function)
                } else {
                    branch_error = check_statement(c, r, g, tree, module_index, child_index, function)
                }
                if node.kind == .WhileStmt {
                    c.loop_depth = c.loop_depth - 1usize
                    c.break_depth = c.break_depth - 1usize
                }
                if branch_error != ok { ret branch_error }
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
    if c.defer_depth != 0usize { ret InvalidTry }
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

fn ascii_lower(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

// Spec section 9: `T.f(...)` resolves to `fn <t>_f` in the module declaring T,
// where <t> is T's name in snake_case. A boundary precedes an uppercase letter
// following a lowercase letter or digit, and precedes the last uppercase letter of
// a run when the next letter is lowercase, so `HTTP2Client` becomes `http2_client`.
fn protocol_name_matches(type_name: str, candidate_name: str, protocol: str) -> bool {
    var source = 0usize
    var output_at = 0usize
    while source < type_name.len {
        let byte = type_name[source]
        let upper = byte >= 65u8 && byte <= 90u8
        var previous_lower = false
        if source > 0usize {
            let previous = type_name[source - 1usize]
            previous_lower = (previous >= 97u8 && previous <= 122u8) || (previous >= 48u8 && previous <= 57u8)
        }
        var next_lower = false
        if source + 1usize < type_name.len {
            let next = type_name[source + 1usize]
            next_lower = next >= 97u8 && next <= 122u8
        }
        if upper && source > 0usize && (previous_lower || next_lower) {
            if output_at >= candidate_name.len || candidate_name[output_at] != 95u8 { ret false }
            output_at += 1usize
        }
        if output_at >= candidate_name.len || candidate_name[output_at] != ascii_lower(byte) { ret false }
        source += 1usize
        output_at += 1usize
    }
    if output_at >= candidate_name.len || candidate_name[output_at] != 95u8 { ret false }
    output_at += 1usize
    var suffix_at = 0usize
    while suffix_at < protocol.len {
        if output_at >= candidate_name.len || candidate_name[output_at] != protocol[suffix_at] { ret false }
        output_at += 1usize
        suffix_at += 1usize
    }
    ret output_at == candidate_name.len
}

fn iterator_next_name_matches(type_name: str, candidate_name: str) -> bool {
    ret protocol_name_matches(type_name, candidate_name, "next")
}

fn protocol_iteration_element(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, statement: syntax.Node, subject_index: usize, iterable: Type, name_count: usize) -> (Type, err) {
    if name_count != 1usize { ret (invalid_type(), ArgumentCount) }
    var iterator = iterable
    if iterable.kind == .Pointer {
        if iterable.is_const {
            record_failure(c, module_index, statement, .IteratorImmutable, "", "")
            ret (invalid_type(), ImmutableAssignment)
        }
        if !iterable.has_element || iterable.element >= c.type_count { ret (invalid_type(), InvalidType) }
        iterator = c.types[iterable.element]
    }
    let (canonical_iterator, canonical_error) = canonical_type(c, iterator)
    if canonical_error != ok { ret (invalid_type(), canonical_error) }
    if canonical_iterator.kind != .Named { ret (invalid_type(), InvalidOperator) }
    if iterable.kind != .Pointer {
        let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, subject_index)
        if mutable_error != ok { ret (invalid_type(), mutable_error) }
        if !mutable {
            record_failure(c, module_index, statement, .IteratorImmutable, canonical_iterator.name, "")
            ret (invalid_type(), ImmutableAssignment)
        }
    }
    var next_index = 0usize
    var found_next = false
    var function_at = 0usize
    while function_at < c.signature_function_count {
        let candidate = c.functions[function_at]
        if candidate.module_index == canonical_iterator.module_index && iterator_next_name_matches(canonical_iterator.name, candidate.name) {
            next_index = function_at
            found_next = true
            break
        }
        function_at += 1usize
    }
    if !found_next {
        record_failure(c, module_index, statement, .IteratorMissing, canonical_iterator.name, "")
        ret (invalid_type(), UnknownCallable)
    }
    let next = c.functions[next_index]
    if next.generic || next.parameter_count != 1usize || next.return_count != 2usize {
        record_failure(c, module_index, statement, .IteratorSignature, canonical_iterator.name, next.name)
        ret (invalid_type(), InvalidType)
    }
    let (stored_iterator, store_error) = store_type(c, canonical_iterator)
    if store_error != ok { ret (invalid_type(), store_error) }
    var expected_parameter = make_type(.Pointer, "", canonical_iterator.module_index)
    expected_parameter.element = stored_iterator
    expected_parameter.has_element = true
    let parameter = c.parameters[next.first_parameter]
    if !type_equal(c, parameter.ty, expected_parameter) {
        record_failure(c, module_index, statement, .IteratorSignature, canonical_iterator.name, next.name)
        ret (invalid_type(), InvalidType)
    }
    let element = c.return_types[next.first_return]
    let has_value = c.return_types[next.first_return + 1usize]
    if element.kind == .Void || has_value.kind != .Bool {
        record_failure(c, module_index, statement, .IteratorSignature, canonical_iterator.name, next.name)
        ret (invalid_type(), InvalidType)
    }
    ret (element, ok)
}

fn check_for_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var names: [2]str = zero
    var name_count = 0usize
    var token_at = node.token_start + 1usize
    let text = g.modules[module_index].text
    while token_at < node.token_end && c.tokens[token_at].kind != .KwIn {
        let token = c.tokens[token_at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            if name_count == 2usize { ret ArgumentCount }
            if token.kind == .Identifier { names[name_count] = text[token.start..token.end] }
            name_count += 1usize
        }
        token_at += 1usize
    }
    if token_at == node.token_end || name_count == 0usize { ret parse.InvalidSyntax }
    var expressions: [2]usize = zero
    var expression_count = 0usize
    var block_index = 0usize
    var has_block = false
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind == .Block {
                block_index = child_index
                has_block = true
            } else {
                if expression_count == 2usize { ret ArgumentCount }
                expressions[expression_count] = child_index
                expression_count += 1usize
            }
        }
        at += 1usize
    }
    if !has_block || expression_count == 0usize { ret parse.InvalidSyntax }
    let checkpoint = c.local_count
    if expression_count == 2usize {
        if name_count != 1usize { ret ArgumentCount }
        let (raw_first, first_error) = check_expr(c, g, tree, module_index, expressions[0usize], invalid_type())
        if first_error != ok { ret first_error }
        var second_expected = raw_first
        if is_untyped(raw_first) { second_expected = invalid_type() }
        let (raw_second, second_error) = check_expr(c, g, tree, module_index, expressions[1usize], second_expected)
        if second_error != ok { ret second_error }
        var first = raw_first
        var second = raw_second
        if is_untyped(first) && !is_untyped(second) {
            let (contextual_first, context_error) = apply_context(c, first, second)
            if context_error != ok { ret context_error }
            first = contextual_first
        }
        if !is_untyped(first) && is_untyped(second) {
            let (contextual_second, context_error) = apply_context(c, second, first)
            if context_error != ok { ret context_error }
            second = contextual_second
        }
        if !type_equal(c, first, second) {
            if !c.generic_declaration || !types_may_match_after_instantiation(c, first, second) { ret TypeMismatch }
        }
        if is_untyped(first) { ret MissingContext }
        if !is_integer(first) {
            if !c.generic_declaration || !type_shape_unknown(first) { ret InvalidType }
        }
        if names[0usize].len != 0usize { try add_local(c, names[0usize], first, false) }
    } else {
        let (iterable, iterable_error) = check_expr(c, g, tree, module_index, expressions[0usize], invalid_type())
        if iterable_error != ok { ret iterable_error }
        let (resolved_element, element_error) = index_element_type(c, iterable, module_index)
        var element = resolved_element
        if element_error != ok {
            if c.generic_declaration && type_shape_unknown(iterable) {
                element = dependent_expression_type(iterable, invalid_type(), module_index)
            } else {
                let (protocol_element, protocol_error) = protocol_iteration_element(c, g, tree, module_index, node, expressions[0usize], iterable, name_count)
                if protocol_error != ok { ret protocol_error }
                element = protocol_element
            }
        }
        if name_count == 1usize {
            if names[0usize].len != 0usize { try add_local(c, names[0usize], element, false) }
        } else {
            if names[0usize].len != 0usize { try add_local(c, names[0usize], make_type(.Integer, "usize", module_index), false) }
            if names[1usize].len != 0usize { try add_local(c, names[1usize], element, false) }
        }
    }
    c.loop_depth += 1usize
    c.break_depth += 1usize
    let body_error = check_block(c, r, g, tree, module_index, tree.nodes[block_index], function)
    c.loop_depth = c.loop_depth - 1usize
    c.break_depth = c.break_depth - 1usize
    c.local_count = checkpoint
    ret body_error
}

fn check_statement_kind(kind: syntax.Kind) -> bool {
    ret kind == .BindingStmt || kind == .AssignmentStmt || kind == .CallStmt || kind == .TryStmt || kind == .ReturnStmt || kind == .DeferStmt || kind == .NocheckStmt || kind == .SharedVarStmt || kind == .BreakStmt || kind == .ContinueStmt || kind == .IfStmt || kind == .WhileStmt || kind == .ForStmt || kind == .WhenStmt || kind == .SwitchStmt || kind == .ErrorNode
}

fn switch_member_name(c: *Checker, text: str, node: syntax.Node) -> (str, bool) {
    if node.kind != .MemberExpr && node.kind != .FieldExpr { ret ("", false) }
    var name = ""
    var at = node.token_start
    while at < node.token_end {
        let token = c.tokens[at]
        if token.kind == .Identifier { name = text[token.start..token.end] }
        at += 1usize
    }
    ret (name, name.len != 0usize)
}

fn unwrap_switch_case(tree: *parse.Tree, node_index: usize) -> usize {
    let node = tree.nodes[node_index]
    if node.kind != .GroupExpr { ret node_index }
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret node_index }
    ret unwrap_switch_case(tree, child_index)
}

fn switch_case_key(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, subject: Type, aggregate_index: usize, has_aggregate: bool) -> (SwitchKey, usize, bool, err) {
    var key: SwitchKey = zero
    let unwrapped_index = unwrap_switch_case(tree, node_index)
    let node = tree.nodes[unwrapped_index]
    let text = g.modules[module_index].text
    if has_aggregate {
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind == .TaggedUnion {
            if node.kind != .MemberExpr { ret (key, 0usize, false, InvalidSwitch) }
        } else {
            let (_, case_error) = check_expr(c, g, tree, module_index, unwrapped_index, subject)
            if case_error != ok { ret (key, 0usize, false, case_error) }
        }
        let (member, has_member) = switch_member_name(c, text, node)
        if !has_member { ret (key, 0usize, false, InvalidSwitch) }
        let (field_index, found_field) = aggregate_field_for_name(c, aggregate, member)
        if !found_field { ret (key, 0usize, false, InvalidSwitch) }
        key.kind = .Member
        key.name = member
        ret (key, field_index, true, ok)
    }
    let (_, case_error) = check_expr(c, g, tree, module_index, unwrapped_index, subject)
    if case_error != ok { ret (key, 0usize, false, case_error) }
    if subject.kind == .Integer {
        let checkpoint = c.constant_expr_count
        let (expression_index, copy_error) = copy_constant_expr(c, g, tree, module_index, unwrapped_index)
        if copy_error != ok {
            c.constant_expr_count = checkpoint
            ret (key, 0usize, false, InvalidConstant)
        }
        let (value, value_type, value_error) = evaluate_constant_expr(c, expression_index, subject)
        c.constant_expr_count = checkpoint
        if value_error != ok || !is_integer(value_type) || !integer_representable(value, subject) { ret (key, 0usize, false, InvalidConstant) }
        key.kind = .Integer
        key.integer = value
        ret (key, 0usize, false, ok)
    }
    if subject.kind == .Bool {
        if node.kind != .LiteralExpr { ret (key, 0usize, false, InvalidConstant) }
        let token = c.tokens[node.token_start]
        if token.kind != .KwTrue && token.kind != .KwFalse { ret (key, 0usize, false, InvalidConstant) }
        key.kind = .Bool
        key.boolean = token.kind == .KwTrue
        ret (key, 0usize, false, ok)
    }
    if subject.kind == .Err {
        key.kind = .Error
        if node.kind == .LiteralExpr && c.tokens[node.token_start].kind == .KwOk {
            key.name = "ok"
            ret (key, 0usize, false, ok)
        }
        if node.kind == .NameExpr {
            let token = c.tokens[node.token_start]
            if token.kind != .Identifier { ret (key, 0usize, false, InvalidConstant) }
            key.module_index = module_index
            key.name = text[token.start..token.end]
            ret (key, 0usize, false, ok)
        }
        if node.kind == .FieldExpr {
            let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
            if !found_member { ret (key, 0usize, false, InvalidConstant) }
            key.module_index = target_module
            key.name = member
            ret (key, 0usize, false, ok)
        }
        ret (key, 0usize, false, InvalidConstant)
    }
    ret (key, 0usize, false, InvalidSwitch)
}

fn switch_keys_equal(left: SwitchKey, right: SwitchKey) -> bool {
    if left.kind != right.kind { ret false }
    if left.kind == .Integer { ret left.integer.magnitude == right.integer.magnitude && left.integer.negative == right.integer.negative }
    if left.kind == .Bool { ret left.boolean == right.boolean }
    if left.kind == .Error { ret left.module_index == right.module_index && same(left.name, right.name) }
    if left.kind == .Member { ret same(left.name, right.name) }
    ret false
}

fn switch_case_seen_before(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, switch_node: syntax.Node, current_index: usize, subject: Type, aggregate_index: usize, has_aggregate: bool, current: SwitchKey) -> (bool, err) {
    let end = switch_node.first_child + switch_node.child_count
    var at = switch_node.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if child.kind == .SwitchArm {
                let arm_end = child.first_child + child.child_count
                var arm_at = child.first_child
                while arm_at < arm_end {
                    if tree.children[arm_at].node {
                        let prior_index = tree.children[arm_at].index
                        let prior = tree.nodes[prior_index]
                        if !check_statement_kind(prior.kind) {
                            if prior_index == current_index { ret (false, ok) }
                            let (prior_key, prior_field, prior_has_field, prior_error) = switch_case_key(c, g, tree, module_index, prior_index, subject, aggregate_index, has_aggregate)
                            if prior_error != ok { ret (false, prior_error) }
                            if switch_keys_equal(prior_key, current) { ret (true, ok) }
                        }
                    }
                    arm_at += 1usize
                }
            }
        }
        at += 1usize
    }
    ret (false, ok)
}

fn switch_capture_name(c: *Checker, text: str, arm: syntax.Node) -> (str, bool) {
    var saw_as = false
    var at = arm.token_start
    while at < arm.token_end {
        let token = c.tokens[at]
        if token.kind == .KwAs {
            saw_as = true
        } else {
            if saw_as && token.kind == .Identifier { ret (text[token.start..token.end], true) }
        }
        at += 1usize
    }
    ret ("", false)
}

fn store_checked_switch(c: *Checker, module_index: usize, token_start: usize, returns: bool) -> err {
    if c.checked_switch_count == c.checked_switches.len { ret Capacity }
    c.checked_switches[c.checked_switch_count] = CheckedSwitch { module_index: module_index, token_start: token_start, returns: returns }
    c.checked_switch_count += 1usize
    ret ok
}

fn checked_switch_returns(c: *Checker, module_index: usize, token_start: usize) -> bool {
    var at = c.checked_switch_count
    while at > 0usize {
        at = at - 1usize
        let item = c.checked_switches[at]
        if item.module_index == module_index && item.token_start == token_start { ret item.returns }
    }
    ret false
}

fn switch_arm_returns(c: *Checker, tree: *parse.Tree, module_index: usize, arm: syntax.Node) -> bool {
    let end = arm.first_child + arm.child_count
    var at = arm.first_child
    while at < end {
        if tree.children[at].node {
            let child = tree.nodes[tree.children[at].index]
            if check_statement_kind(child.kind) && statement_returns(c, tree, module_index, child) { ret true }
        }
        at += 1usize
    }
    ret false
}

fn switch_has_member(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, name: str) -> bool {
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let arm = tree.nodes[tree.children[at].index]
            if arm.kind == .SwitchArm && c.tokens[arm.token_start].kind != .KwDefault {
                let arm_end = arm.first_child + arm.child_count
                var arm_at = arm.first_child
                while arm_at < arm_end {
                    if tree.children[arm_at].node {
                        let value = tree.nodes[tree.children[arm_at].index]
                        if !check_statement_kind(value.kind) {
                            let (member, found) = switch_member_name(c, g.modules[module_index].text, value)
                            if found && same(member, name) { ret true }
                        }
                    }
                    arm_at += 1usize
                }
            }
        }
        at += 1usize
    }
    ret false
}

fn check_dependent_switch(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = node.first_child + node.child_count
    var default_seen = false
    var arm_count = 0usize
    var returning_arm_count = 0usize
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let arm = tree.nodes[tree.children[at].index]
            if arm.kind == .SwitchArm {
                arm_count += 1usize
                let checkpoint = c.local_count
                let is_default = c.tokens[arm.token_start].kind == .KwDefault
                if is_default {
                    if default_seen { ret DuplicateCase }
                    default_seen = true
                } else {
                    var case_count = 0usize
                    let arm_end = arm.first_child + arm.child_count
                    var case_at = arm.first_child
                    while case_at < arm_end {
                        if tree.children[case_at].node && !check_statement_kind(tree.nodes[tree.children[case_at].index].kind) { case_count += 1usize }
                        case_at += 1usize
                    }
                    if case_count == 0usize { ret parse.InvalidSyntax }
                }
                let (capture, has_capture) = switch_capture_name(c, g.modules[module_index].text, arm)
                if has_capture {
                    if is_default { ret InvalidSwitch }
                    let capture_error = add_local(c, capture, make_type(.TypeParameter, "", module_index), false)
                    if capture_error != ok {
                        c.local_count = checkpoint
                        ret capture_error
                    }
                }
                c.break_depth += 1usize
                let arm_end = arm.first_child + arm.child_count
                var arm_at = arm.first_child
                var body_error = ok
                while arm_at < arm_end {
                    if tree.children[arm_at].node {
                        let statement_index = tree.children[arm_at].index
                        if check_statement_kind(tree.nodes[statement_index].kind) {
                            body_error = check_statement(c, r, g, tree, module_index, statement_index, function)
                            if body_error != ok { break }
                        }
                    }
                    arm_at += 1usize
                }
                c.break_depth = c.break_depth - 1usize
                if body_error == ok && switch_arm_returns(c, tree, module_index, arm) { returning_arm_count += 1usize }
                c.local_count = checkpoint
                if body_error != ok { ret body_error }
            }
        }
        at += 1usize
    }
    ret store_checked_switch(c, module_index, node.token_start, default_seen && arm_count != 0usize && arm_count == returning_arm_count)
}

fn check_switch_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
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
    let (subject, subject_error) = check_expr(c, g, tree, module_index, subject_index, invalid_type())
    if subject_error != ok { ret subject_error }
    if c.generic_declaration && type_shape_unknown(subject) { ret check_dependent_switch(c, r, g, tree, module_index, node, function) }
    let (aggregate_index, has_aggregate) = aggregate_for_type(c, subject)
    if has_aggregate {
        let aggregate_kind = c.aggregates[aggregate_index].kind
        if aggregate_kind != .Enum && aggregate_kind != .TaggedUnion { ret InvalidSwitch }
    } else {
        if subject.kind != .Integer && subject.kind != .Bool && subject.kind != .Err { ret InvalidSwitch }
    }
    var default_seen = false
    var covered_count = 0usize
    var arm_count = 0usize
    var returning_arm_count = 0usize
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let arm = tree.nodes[tree.children[at].index]
            if arm.kind == .SwitchArm {
                arm_count += 1usize
                let checkpoint = c.local_count
                let is_default = c.tokens[arm.token_start].kind == .KwDefault
                var case_count = 0usize
                var captured_field_index = 0usize
                var has_captured_field = false
                let arm_end = arm.first_child + arm.child_count
                var arm_at = arm.first_child
                if is_default {
                    if default_seen { ret DuplicateCase }
                    default_seen = true
                } else {
                    while arm_at < arm_end {
                        if tree.children[arm_at].node {
                            let case_index = tree.children[arm_at].index
                            if !check_statement_kind(tree.nodes[case_index].kind) {
                                let (key, field_index, has_field, key_error) = switch_case_key(c, g, tree, module_index, case_index, subject, aggregate_index, has_aggregate)
                                if key_error != ok { ret key_error }
                                let (duplicate, duplicate_error) = switch_case_seen_before(c, g, tree, module_index, node, case_index, subject, aggregate_index, has_aggregate, key)
                                if duplicate_error != ok { ret duplicate_error }
                                if duplicate { ret DuplicateCase }
                                case_count += 1usize
                                if has_aggregate { covered_count += 1usize }
                                captured_field_index = field_index
                                has_captured_field = has_field
                            }
                        }
                        arm_at += 1usize
                    }
                    if case_count == 0usize { ret parse.InvalidSyntax }
                }
                let (capture, has_capture) = switch_capture_name(c, g.modules[module_index].text, arm)
                if has_capture {
                    if is_default || subject.kind != .Named || !has_aggregate || c.aggregates[aggregate_index].kind != .TaggedUnion || case_count != 1usize || !has_captured_field { ret InvalidSwitch }
                    let payload = c.aggregate_fields[captured_field_index].ty
                    if payload.kind == .Void { ret InvalidSwitch }
                    let capture_error = add_local(c, capture, payload, false)
                    if capture_error != ok {
                        c.local_count = checkpoint
                        ret capture_error
                    }
                }
                c.break_depth += 1usize
                arm_at = arm.first_child
                var body_error = ok
                while arm_at < arm_end {
                    if tree.children[arm_at].node {
                        let statement_index = tree.children[arm_at].index
                        if check_statement_kind(tree.nodes[statement_index].kind) {
                            body_error = check_statement(c, r, g, tree, module_index, statement_index, function)
                            if body_error != ok { break }
                        }
                    }
                    arm_at += 1usize
                }
                c.break_depth = c.break_depth - 1usize
                if body_error == ok && switch_arm_returns(c, tree, module_index, arm) { returning_arm_count += 1usize }
                c.local_count = checkpoint
                if body_error != ok { ret body_error }
            }
        }
        at += 1usize
    }
    if has_aggregate && !default_seen && covered_count != c.aggregates[aggregate_index].field_count {
        let aggregate = c.aggregates[aggregate_index]
        var missing = ""
        var field_at = 0usize
        while field_at < aggregate.field_count {
            let field = c.aggregate_fields[aggregate.first_field + field_at]
            if !switch_has_member(c, g, tree, module_index, node, field.name) {
                missing = field.name
                break
            }
            field_at += 1usize
        }
        record_failure(c, module_index, node, .NonExhaustive, missing, "")
        ret NonExhaustiveSwitch
    }
    let exhaustive = default_seen || has_aggregate
    ret store_checked_switch(c, module_index, node.token_start, exhaustive && arm_count != 0usize && arm_count == returning_arm_count)
}

fn check_defer_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret parse.InvalidSyntax }
    let checkpoint = c.local_count
    let saved_loop_depth = c.loop_depth
    let saved_break_depth = c.break_depth
    c.loop_depth = 0usize
    c.break_depth = 0usize
    c.defer_depth += 1usize
    let child = tree.nodes[child_index]
    var body_error = ok
    if child.kind == .Block {
        body_error = check_block(c, r, g, tree, module_index, child, function)
    } else {
        body_error = check_statement(c, r, g, tree, module_index, child_index, function)
    }
    c.defer_depth = c.defer_depth - 1usize
    c.loop_depth = saved_loop_depth
    c.break_depth = saved_break_depth
    c.local_count = checkpoint
    if body_error == ArgumentCount && c.failure_kind == .Generic {
        c.failure_kind = .DeferValue
        if c.diagnostic_count != 0usize { c.diagnostics[0usize].kind = .DeferValue }
    }
    ret body_error
}

fn assignment_place_type(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (Type, err) {
    let place = tree.nodes[node_index]
    if place.kind == .NameExpr {
        let token = c.tokens[place.token_start]
        let name = g.modules[module_index].text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if !found { ret (invalid_type(), Unsupported) }
        if !c.locals[local_index].mutable {
            record_failure(c, module_index, place, .AssignmentImmutable, name, "")
            ret (invalid_type(), ImmutableAssignment)
        }
        ret (c.locals[local_index].ty, ok)
    }
    if place.kind == .UnaryExpr && c.tokens[place.token_start].kind == .PunctStar {
        let (child_index, found) = first_node_child(tree, place)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
        if pointer_error != ok { ret (invalid_type(), pointer_error) }
        if pointer.kind != .Pointer || !pointer.has_element || pointer.element >= c.type_count {
            if c.generic_declaration && type_shape_unknown(pointer) { ret (dependent_expression_type(pointer, invalid_type(), module_index), ok) }
            ret (invalid_type(), ImmutableAssignment)
        }
        if pointer.is_const {
            record_failure(c, module_index, place, .AssignmentImmutable, "", "")
            ret (invalid_type(), ImmutableAssignment)
        }
        let element = c.types[pointer.element]
        if element.kind == .Void { ret (invalid_type(), InvalidOperator) }
        ret (element, ok)
    }
    if place.kind == .BracketPostfix {
        var bracket: BracketInfo = zero
        let bracket_error = read_bracket(c, tree, place, &bracket)
        if bracket_error != ok { ret (invalid_type(), bracket_error) }
        if bracket.range || bracket.child_count != 2usize { ret (invalid_type(), Unsupported) }
        let (base, base_error) = check_expr(c, g, tree, module_index, bracket.base, invalid_type())
        if base_error != ok { ret (invalid_type(), base_error) }
        let (element, element_error) = index_element_type(c, base, module_index)
        if element_error != ok {
            if !c.generic_declaration || !type_shape_unknown(base) { ret (invalid_type(), element_error) }
            let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, make_type(.Integer, "usize", module_index))
            if index_error != ok { ret (invalid_type(), index_error) }
            ret (dependent_expression_type(base, invalid_type(), module_index), ok)
        }
        let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, make_type(.Integer, "usize", module_index))
        if index_error != ok { ret (invalid_type(), index_error) }
        var mutable = false
        if base.kind == .Slice { mutable = !base.is_const }
        if base.kind == .Array {
            let (place_mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, bracket.base)
            if mutable_error != ok { ret (invalid_type(), mutable_error) }
            mutable = place_mutable
        }
        if !mutable {
            if base.kind == .Array {
                record_failure(c, module_index, place, .IndexedArrayImmutable, "", "")
            } else {
                record_failure(c, module_index, place, .IndexedElementsImmutable, "", "")
            }
            ret (invalid_type(), ImmutableAssignment)
        }
        ret (element, ok)
    }
    if place.kind == .FieldExpr {
        let (field_type, field_error) = check_expr(c, g, tree, module_index, node_index, invalid_type())
        if field_error != ok { ret (invalid_type(), field_error) }
        let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, node_index)
        if mutable_error != ok { ret (invalid_type(), mutable_error) }
        if !mutable {
            record_failure(c, module_index, place, .AssignmentImmutable, "", "")
            ret (invalid_type(), ImmutableAssignment)
        }
        ret (field_type, ok)
    }
    ret (invalid_type(), Unsupported)
}

fn assignment_operator(c: *Checker, left_end: usize, right_start: usize) -> lex.Kind {
    var at = left_end
    while at < right_start {
        let kind = c.tokens[at].kind
        if kind != .Newline { ret kind }
        at += 1usize
    }
    ret .Invalid
}

fn check_compound_assignment(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, place_index: usize, value_index: usize, op: lex.Kind) -> err {
    let (place_type, place_error) = assignment_place_type(c, g, tree, module_index, place_index)
    if place_error != ok { ret place_error }
    if op == .PunctShiftLeftAssign || op == .PunctShiftRightAssign {
        if !is_integer(place_type) || is_untyped(place_type) {
            if !c.generic_declaration || !type_shape_unknown(place_type) { ret InvalidOperator }
        }
        let (right_type, right_error) = check_expr(c, g, tree, module_index, value_index, invalid_type())
        if right_error != ok { ret right_error }
        var count_type = right_type
        if right_type.kind == .UntypedInteger {
            let (contextual, context_error) = apply_context(c, right_type, make_type(.Integer, "u32", module_index))
            if context_error != ok { ret context_error }
            count_type = contextual
        }
        if count_type.kind != .Integer || !unsigned_integer_type(count_type) { ret InvalidOperator }
        ret ok
    }
    let (_, value_error) = check_expr(c, g, tree, module_index, value_index, place_type)
    if value_error != ok { ret value_error }
    if op == .PunctAddAssign || op == .PunctSubAssign || op == .PunctMulAssign || op == .PunctDivAssign {
        if !is_numeric(place_type) && (!c.generic_declaration || !type_shape_unknown(place_type)) { ret InvalidOperator }
        ret ok
    }
    if op == .PunctRemAssign || op == .PunctAddWrapAssign || op == .PunctSubWrapAssign || op == .PunctMulWrapAssign || op == .PunctBitAndAssign || op == .PunctBitXorAssign || op == .PunctBitOrAssign {
        if !is_integer(place_type) && (!c.generic_declaration || !type_shape_unknown(place_type)) { ret InvalidOperator }
        ret ok
    }
    ret Unsupported
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
    let op = assignment_operator(c, tree.nodes[first_index].token_end, initializer.token_start)
    if op == .Invalid { ret Unsupported }
    let tried = contains_token(c, node.token_start, initializer.token_start, .KwTry)
    if count == 2usize && !tried {
        if op != .PunctAssign { ret check_compound_assignment(c, g, tree, module_index, first_index, initializer_index, op) }
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
            if place_error != ok {
                if place_error == ImmutableAssignment && c.failure_kind == .AssignmentImmutable {
                    c.failure_kind = .MultipleAssignmentImmutable
                    if node.token_start < c.token_count {
                        c.failure_token = c.tokens[node.token_start]
                        if c.diagnostic_count != 0usize {
                            c.diagnostics[0usize].kind = .MultipleAssignmentImmutable
                            c.diagnostics[0usize].token = c.tokens[node.token_start]
                        }
                    }
                }
                ret place_error
            }
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

fn check_statement_inner(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, function: Function) -> err {
    let node = tree.nodes[node_index]
    if node.kind == .Block { ret check_block(c, r, g, tree, module_index, node, function) }
    if node.kind == .BindingStmt { ret check_binding(c, r, g, tree, module_index, node, function) }
    if node.kind == .ReturnStmt { ret check_return(c, g, tree, module_index, node, function) }
    if node.kind == .IfStmt || node.kind == .WhileStmt { ret check_condition_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .ForStmt { ret check_for_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .SwitchStmt { ret check_switch_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .BreakStmt {
        if c.break_depth == 0usize { ret Unsupported }
        ret ok
    }
    if node.kind == .ContinueStmt {
        if c.loop_depth == 0usize { ret Unsupported }
        ret ok
    }
    if node.kind == .CallStmt { ret check_call_statement(c, g, tree, module_index, node) }
    if node.kind == .TryStmt { ret check_try_statement(c, g, tree, module_index, node, function) }
    if node.kind == .AssignmentStmt { ret check_assignment(c, g, tree, module_index, node, function) }
    if node.kind == .DeferStmt { ret check_defer_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .NocheckStmt {
        let checkpoint = c.local_count
        let child_error = check_children(c, r, g, tree, module_index, node, function)
        c.local_count = checkpoint
        ret child_error
    }
    ret Unsupported
}

fn check_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, function: Function) -> err {
    let node = tree.nodes[node_index]
    let statement_error = check_statement_inner(c, r, g, tree, module_index, node_index, function)
    if statement_error != ok && !c.failure_has_token {
        record_failure(c, module_index, node, default_failure_kind(statement_error, node), "", "")
    }
    ret statement_error
}

fn contains_loop_break(tree: *parse.Tree, node: syntax.Node) -> bool {
    if node.kind == .BreakStmt { ret true }
    if node.kind == .WhileStmt || node.kind == .ForStmt || node.kind == .SwitchStmt { ret false }
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node && contains_loop_break(tree, tree.nodes[tree.children[at].index]) { ret true }
        at += 1usize
    }
    ret false
}

fn statement_returns(c: *Checker, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> bool {
    if node.kind == .ReturnStmt { ret true }
    if node.kind == .SwitchStmt { ret checked_switch_returns(c, module_index, node.token_start) }
    if node.kind == .Block {
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node && statement_returns(c, tree, module_index, tree.nodes[tree.children[at].index]) { ret true }
            at += 1usize
        }
        ret false
    }
    if node.kind == .WhileStmt {
        let (condition_index, has_condition) = first_node_child(tree, node)
        if !has_condition { ret false }
        let condition = tree.nodes[condition_index]
        if condition.kind != .LiteralExpr || c.tokens[condition.token_start].kind != .KwTrue { ret false }
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if tree.children[at].node {
                let child = tree.nodes[tree.children[at].index]
                if child.kind == .Block { ret !contains_loop_break(tree, child) }
            }
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
                    if statement_returns(c, tree, module_index, tree.nodes[tree.children[at].index]) { returning_count += 1usize }
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
                if function.return_count != 0usize && !statement_returns(c, tree, module_index, child) { ret MissingReturn }
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
    if function.generic {
        let generic = c.function_generics[function_index]
        c.active_first_comptime = generic.first_comptime
        c.active_comptime_count = generic.comptime_count
        c.active_first_argument = 0usize
        c.active_arguments = false
        c.generic_declaration = true
        let declaration_error = check_function_body(c, r, g, tree, module_index, node, function)
        c.active_first_comptime = 0usize
        c.active_comptime_count = 0usize
        c.active_first_argument = 0usize
        c.active_arguments = false
        c.generic_declaration = false
        if declaration_error != ok {
            c.failure_module = module_index
            c.failure_name = name
        }
        ret declaration_error
    }
    let body_error = check_function_body(c, r, g, tree, module_index, node, function)
    if body_error != ok {
        c.failure_module = module_index
        c.failure_name = name
    }
    ret body_error
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
    // A template body walked here belongs to the declaring module, but anything it
    // instantiates is code in the module that asked for this instance.
    c.active_owner_module = instance.owner_module_index
    c.active_owner_set = true
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
    c.active_owner_set = false
    c.active_owner_module = 0usize
    if result != ok {
        c.failure_module = instance.module_index
        c.failure_name = template.name
    }
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
        if c.function_generics[instance_index].instance && !c.function_generics[instance_index].checked && !c.functions[instance_index].generic {
            c.function_generics[instance_index].checked = true
            try check_instance(c, r, g, instance_index)
        }
        instance_index += 1usize
    }
    ret ok
}

fn run(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    if c.function_generics.len < c.functions.len || c.comptime_parameters.len == 0usize || c.generic_arguments.len == 0usize || c.aggregates.len == 0usize || c.aggregate_fields.len == 0usize { ret Capacity }
    c.resolver = r
    try collect_aliases(c, r, g, true)
    try collect_constants(c, r, g)
    try collect_aggregates(c, r, g)
    if c.diagnostic_count != 0usize { ret InvalidType }
    try collect_aliases(c, r, g, false)
    try validate_aggregate_value_cycles(c)
    try collect_signatures(c, r, g)
    ret check_bodies(c, r, g)
}

fn diagnostic_code(kind: DiagnosticKind) -> str {
    if kind == .TryInsideDefer { ret "E-ERROR-9999" }
    if kind == .ArrayLengthType || kind == .InitializerType { ret "E-TYPE-0002" }
    if kind == .GenericTypeArity || kind == .IteratorSignature || kind == .ProtocolSignature { ret "E-TYPE-0003" }
    if kind == .EnumValueRange { ret "E-TYPE-0004" }
    if kind == .DuplicateEnumValue { ret "E-NAME-0001" }
    if kind == .IteratorMissing || kind == .ProtocolMissing { ret "E-NAME-9999" }
    if kind == .GenericInference { ret "E-TYPE-0001" }
    ret "E-TYPE-9999"
}

fn diagnostic_message(kind: DiagnosticKind) -> str {
    if kind == .AssignmentImmutable { ret "assignment target is immutable" }
    if kind == .IndexedArrayImmutable { ret "indexed assignment requires a mutable array binding" }
    if kind == .IndexedElementsImmutable { ret "indexed assignment requires mutable elements" }
    if kind == .BreakOutsideControl { ret "break requires an enclosing loop or switch" }
    if kind == .ReturnInsideDefer { ret "ret is not legal inside defer" }
    if kind == .TryInsideDefer { ret "try is not legal inside defer" }
    if kind == .DeferValue { ret "a deferred call returning a value must use `defer let _ = call()`" }
    if kind == .ArrayElementCount { ret "array literal element count does not match its length" }
    if kind == .ArrayLengthType { ret "array length must have type usize" }
    if kind == .ConstantDependencyCycle { ret "constant dependency cycle" }
    if kind == .EnumValueRange { ret "enum member value is outside its backing type" }
    if kind == .DuplicateEnumValue { ret "duplicate enum backing value" }
    if kind == .IteratorImmutable { ret "iterator subject must be a mutable variable or a mutable pointer" }
    if kind == .IteratorSignature { ret "iterator next function must have signature `fn <type>_next(it: *I) -> (T, bool)`" }
    if kind == .RecursiveAggregate { ret "recursive aggregate value layout" }
    if kind == .InitializerType { ret "initializer type does not match binding" }
    if kind == .GenericTypeArity { ret "compile-time argument count does not match generic type" }
    if kind == .MultipleBindingCount { ret "multiple binding count does not match function results" }
    if kind == .MultipleAssignmentImmutable { ret "multiple assignment target is immutable" }
    if kind == .AggregateMemberUnknown { ret "aggregate member has an unknown or unsized type" }
    if kind == .BindingUnknownNamed { ret "binding has an unknown named type" }
    ret "type checking failed"
}
