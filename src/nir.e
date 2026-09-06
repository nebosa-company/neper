// Canonical typed SSA-lite IR shared by code generation and .em serialization.

use check
use lex

error Capacity
error InvalidControlFlow
error InvalidValue

// Numeric values are part of the versioned .em format. Never renumber an opcode.
type Opcode = enum u8 {
    Invalid = 0,
    Parameter = 1,
    ConstInteger = 2,
    ConstBool = 3,
    ConstError = 4,
    ConstString = 5,
    Stack = 6,
    Load = 7,
    Store = 8,
    Copy = 9,
    Zero = 10,
    FieldAddress = 11,
    IndexAddress = 12,
    Slice = 13,
    Cast = 14,
    Add = 15,
    Subtract = 16,
    Multiply = 17,
    Divide = 18,
    Remainder = 19,
    AddWrap = 20,
    SubtractWrap = 21,
    MultiplyWrap = 22,
    ShiftLeft = 23,
    ShiftRight = 24,
    BitAnd = 25,
    BitXor = 26,
    BitOr = 27,
    Negate = 28,
    BitNot = 29,
    Equal = 30,
    NotEqual = 31,
    Less = 32,
    LessEqual = 33,
    Greater = 34,
    GreaterEqual = 35,
    Call = 36,
    Extract = 37,
    Phi = 38,
    Trap = 39,
    Branch = 40,
    BranchIf = 41,
    Switch = 42,
    Return = 43,
    Unreachable = 44,
    FunctionAddress = 45,
    IndirectCall = 46,
}

type Instruction = struct {
    opcode: Opcode,
    result: usize,
    has_result: bool,
    ty: check.Type,
    first_operand: usize,
    operand_count: usize,
    immediate: usize,
    target: usize,
    target2: usize,
    token: lex.Token,
}

type Block = struct {
    first_instruction: usize,
    instruction_count: usize,
    terminated: bool,
}

type Function = struct {
    name: str,
    module_index: usize,
    instance: usize,
    first_block: usize,
    block_count: usize,
    first_instruction: usize,
    instruction_count: usize,
    value_count: usize,
}

type Signature = struct {
    first_parameter_type: usize,
    parameter_count: usize,
    first_return_type: usize,
    return_count: usize,
}

type FunctionRef = struct {
    module_index: usize,
    name: str,
    instance: usize,
}

type StringConstant = struct {
    spelling: str,
}

type Signatures = struct {
    entries: []Signature,
    types: []check.Type,
    count: usize,
}

type Builder = struct {
    functions: []Function,
    blocks: []Block,
    instructions: []Instruction,
    operands: []usize,
    function_refs: []FunctionRef,
    strings: []StringConstant,
    function_count: usize,
    block_count: usize,
    instruction_count: usize,
    operand_count: usize,
    function_ref_count: usize,
    string_count: usize,
    current_function: usize,
    current_block: usize,
    next_value: usize,
    function_active: bool,
    block_active: bool,
}

fn is_terminator(opcode: Opcode) -> bool {
    ret opcode == .Trap || opcode == .Branch || opcode == .BranchIf || opcode == .Switch || opcode == .Return || opcode == .Unreachable
}

fn init(builder: *Builder, functions: []Function, blocks: []Block, instructions: []Instruction, operands: []usize, function_refs: []FunctionRef, strings: []StringConstant) -> err {
    if functions.len == 0usize || blocks.len == 0usize || instructions.len == 0usize || operands.len == 0usize || function_refs.len == 0usize || strings.len == 0usize { ret Capacity }
    builder.functions = functions
    builder.blocks = blocks
    builder.instructions = instructions
    builder.operands = operands
    builder.function_refs = function_refs
    builder.strings = strings
    builder.function_count = 0usize
    builder.block_count = 0usize
    builder.instruction_count = 0usize
    builder.operand_count = 0usize
    builder.function_ref_count = 0usize
    builder.string_count = 0usize
    builder.current_function = 0usize
    builder.current_block = 0usize
    builder.next_value = 0usize
    builder.function_active = false
    builder.block_active = false
    ret ok
}

fn init_signatures(signatures: *Signatures, entries: []Signature, types: []check.Type) -> err {
    if entries.len == 0usize || types.len == 0usize { ret Capacity }
    signatures.entries = entries
    signatures.types = types
    signatures.count = 0usize
    ret ok
}

fn intern_function(builder: *Builder, module_index: usize, name: str, instance: usize) -> (usize, err) {
    var at = 0usize
    while at < builder.function_ref_count {
        let reference = builder.function_refs[at]
        if reference.module_index == module_index && reference.instance == instance && check.same(reference.name, name) { ret (at, ok) }
        at += 1usize
    }
    if builder.function_ref_count == builder.function_refs.len { ret (0usize, Capacity) }
    let index = builder.function_ref_count
    builder.function_refs[index] = FunctionRef { module_index: module_index, name: name, instance: instance }
    builder.function_ref_count += 1usize
    ret (index, ok)
}

fn intern_string(builder: *Builder, spelling: str) -> (usize, err) {
    var at = 0usize
    while at < builder.string_count {
        if check.same(builder.strings[at].spelling, spelling) { ret (at, ok) }
        at += 1usize
    }
    if builder.string_count == builder.strings.len { ret (0usize, Capacity) }
    let index = builder.string_count
    builder.strings[index] = StringConstant { spelling: spelling }
    builder.string_count += 1usize
    ret (index, ok)
}

fn begin_function(builder: *Builder, module_index: usize, name: str, instance: usize) -> (usize, err) {
    if builder.function_active { ret (0usize, InvalidControlFlow) }
    if builder.function_count == builder.functions.len { ret (0usize, Capacity) }
    let index = builder.function_count
    builder.functions[index] = Function {
        name: name,
        module_index: module_index,
        instance: instance,
        first_block: builder.block_count,
        block_count: 0usize,
        first_instruction: builder.instruction_count,
        instruction_count: 0usize,
        value_count: 0usize,
    }
    builder.function_count += 1usize
    builder.current_function = index
    builder.next_value = 0usize
    builder.function_active = true
    builder.block_active = false
    ret (index, ok)
}

fn begin_signature(builder: *Builder, function_index: usize, signatures: *Signatures) -> err {
    if !builder.function_active || function_index != builder.current_function || function_index >= signatures.entries.len { ret InvalidControlFlow }
    signatures.entries[function_index] = Signature { first_parameter_type: signatures.count, parameter_count: 0usize, first_return_type: signatures.count, return_count: 0usize }
    ret ok
}

fn add_parameter_type(builder: *Builder, function_index: usize, signatures: *Signatures, ty: check.Type) -> err {
    if !builder.function_active || function_index != builder.current_function || function_index >= signatures.entries.len || signatures.entries[function_index].return_count != 0usize { ret InvalidControlFlow }
    if signatures.count == signatures.types.len { ret Capacity }
    signatures.types[signatures.count] = ty
    signatures.count += 1usize
    signatures.entries[function_index].parameter_count += 1usize
    signatures.entries[function_index].first_return_type = signatures.count
    ret ok
}

fn add_return_type(builder: *Builder, function_index: usize, signatures: *Signatures, ty: check.Type) -> err {
    if !builder.function_active || function_index != builder.current_function || function_index >= signatures.entries.len { ret InvalidControlFlow }
    if signatures.count == signatures.types.len { ret Capacity }
    signatures.types[signatures.count] = ty
    signatures.count += 1usize
    signatures.entries[function_index].return_count += 1usize
    ret ok
}

fn begin_block(builder: *Builder) -> (usize, err) {
    if !builder.function_active { ret (0usize, InvalidControlFlow) }
    if builder.block_active && !builder.blocks[builder.current_block].terminated { ret (0usize, InvalidControlFlow) }
    if builder.block_count == builder.blocks.len { ret (0usize, Capacity) }
    let index = builder.block_count
    builder.blocks[index] = Block { first_instruction: builder.instruction_count, instruction_count: 0usize, terminated: false }
    builder.block_count += 1usize
    builder.current_block = index
    builder.block_active = true
    builder.functions[builder.current_function].block_count += 1usize
    ret (index, ok)
}

fn emit(builder: *Builder, opcode: Opcode, ty: check.Type, has_result: bool, immediate: usize, token: lex.Token) -> (usize, usize, err) {
    if !builder.function_active || !builder.block_active || builder.blocks[builder.current_block].terminated || opcode == .Invalid { ret (0usize, 0usize, InvalidControlFlow) }
    if builder.instruction_count == builder.instructions.len { ret (0usize, 0usize, Capacity) }
    let instruction_index = builder.instruction_count
    var result = 0usize
    if has_result {
        result = builder.next_value
        builder.next_value += 1usize
    }
    builder.instructions[instruction_index] = Instruction {
        opcode: opcode,
        result: result,
        has_result: has_result,
        ty: ty,
        first_operand: builder.operand_count,
        operand_count: 0usize,
        immediate: immediate,
        target: 0usize,
        target2: 0usize,
        token: token,
    }
    builder.instruction_count += 1usize
    builder.blocks[builder.current_block].instruction_count += 1usize
    builder.functions[builder.current_function].instruction_count += 1usize
    if is_terminator(opcode) { builder.blocks[builder.current_block].terminated = true }
    ret (instruction_index, result, ok)
}

fn add_operand(builder: *Builder, instruction_index: usize, value: usize) -> err {
    if instruction_index >= builder.instruction_count || instruction_index + 1usize != builder.instruction_count { ret InvalidValue }
    if value >= builder.next_value { ret InvalidValue }
    let instruction = builder.instructions[instruction_index]
    if instruction.has_result && instruction.result == value { ret InvalidValue }
    if builder.operand_count == builder.operands.len { ret Capacity }
    builder.operands[builder.operand_count] = value
    builder.operand_count += 1usize
    builder.instructions[instruction_index].operand_count += 1usize
    ret ok
}

fn set_branch_targets(builder: *Builder, instruction_index: usize, destination: usize, destination2: usize) -> err {
    if !builder.function_active || instruction_index < builder.functions[builder.current_function].first_instruction || instruction_index >= builder.instruction_count { ret InvalidControlFlow }
    let opcode = builder.instructions[instruction_index].opcode
    if opcode != .Branch && opcode != .BranchIf { ret InvalidControlFlow }
    builder.instructions[instruction_index].target = destination
    if opcode == .BranchIf { builder.instructions[instruction_index].target2 = destination2 }
    ret ok
}

fn validate_target(function: Function, destination: usize) -> bool {
    ret destination >= function.first_block && destination < function.first_block + function.block_count
}

fn validate_function(builder: *Builder, function: Function) -> err {
    let block_end = function.first_block + function.block_count
    var block_at = function.first_block
    while block_at < block_end {
        let block = builder.blocks[block_at]
        if !block.terminated || block.instruction_count == 0usize { ret InvalidControlFlow }
        let terminator_index = block.first_instruction + block.instruction_count - 1usize
        let terminator = builder.instructions[terminator_index]
        if terminator.opcode == .Branch {
            if !validate_target(function, terminator.target) { ret InvalidControlFlow }
        } else {
            if terminator.opcode == .BranchIf {
                if !validate_target(function, terminator.target) || !validate_target(function, terminator.target2) { ret InvalidControlFlow }
            }
        }
        block_at += 1usize
    }
    ret ok
}

fn end_function(builder: *Builder) -> err {
    if !builder.function_active || !builder.block_active || !builder.blocks[builder.current_block].terminated { ret InvalidControlFlow }
    builder.functions[builder.current_function].value_count = builder.next_value
    try validate_function(builder, builder.functions[builder.current_function])
    builder.function_active = false
    builder.block_active = false
    ret ok
}

fn self_test() -> err {
    var functions: [1]Function = zero
    var blocks: [1]Block = zero
    var instructions: [4]Instruction = zero
    var operands: [4]usize = zero
    var function_refs: [1]FunctionRef = zero
    var strings: [1]StringConstant = zero
    var builder: Builder = zero
    try init(&builder, functions[..], blocks[..], instructions[..], operands[..], function_refs[..], strings[..])
    let (function_ref, function_ref_error) = intern_function(&builder, 1usize, "callee", 0usize)
    if function_ref_error != ok || function_ref != 0usize { ret InvalidValue }
    let (same_function_ref, same_function_ref_error) = intern_function(&builder, 1usize, "callee", 0usize)
    if same_function_ref_error != ok || same_function_ref != function_ref || builder.function_ref_count != 1usize { ret InvalidValue }
    let (string_index, string_error) = intern_string(&builder, "\"value\"")
    if string_error != ok || string_index != 0usize { ret InvalidValue }
    let (same_string_index, same_string_error) = intern_string(&builder, "\"value\"")
    if same_string_error != ok || same_string_index != string_index || builder.string_count != 1usize { ret InvalidValue }
    let (function_index, function_error) = begin_function(&builder, 0usize, "main", 0usize)
    if function_error != ok || function_index != 0usize { ret InvalidControlFlow }
    let (block_index, block_error) = begin_block(&builder)
    if block_error != ok || block_index != 0usize { ret InvalidControlFlow }
    var integer: check.Type = zero
    integer.kind = .Integer
    integer.name = "i64"
    let (parameter_instruction, parameter, parameter_error) = emit(&builder, .Parameter, integer, true, 0usize, zero)
    if parameter_error != ok || parameter_instruction != 0usize || parameter != 0usize { ret InvalidValue }
    let (constant_instruction, constant, constant_error) = emit(&builder, .ConstInteger, integer, true, 7usize, zero)
    if constant_error != ok || constant_instruction != 1usize || constant != 1usize { ret InvalidValue }
    let (add_instruction, sum, add_error) = emit(&builder, .Add, integer, true, 0usize, zero)
    if add_error != ok || sum != 2usize { ret InvalidValue }
    try add_operand(&builder, add_instruction, parameter)
    try add_operand(&builder, add_instruction, constant)
    let (return_instruction, ignored, return_error) = emit(&builder, .Return, integer, false, 0usize, zero)
    if return_error != ok { ret return_error }
    try add_operand(&builder, return_instruction, sum)
    try end_function(&builder)
    if builder.function_count != 1usize || builder.block_count != 1usize || builder.instruction_count != 4usize || builder.operand_count != 3usize { ret InvalidValue }
    if builder.functions[0usize].value_count != 3usize || builder.blocks[0usize].instruction_count != 4usize || !builder.blocks[0usize].terminated { ret InvalidValue }
    let (invalid_instruction, invalid_result, invalid_error) = emit(&builder, .ConstInteger, integer, true, 0usize, zero)
    if invalid_error != InvalidControlFlow { ret InvalidControlFlow }
    ret ok
}

fn signature_self_test() -> err {
    var functions: [1]Function = zero
    var blocks: [1]Block = zero
    var instructions: [1]Instruction = zero
    var operands: [1]usize = zero
    var function_refs: [1]FunctionRef = zero
    var strings: [1]StringConstant = zero
    var builder: Builder = zero
    try init(&builder, functions[..], blocks[..], instructions[..], operands[..], function_refs[..], strings[..])
    var signature_types: [2]check.Type = zero
    var signature_entries: [1]Signature = zero
    var signatures: Signatures = zero
    try init_signatures(&signatures, signature_entries[..], signature_types[..])
    var integer: check.Type = zero
    integer.kind = .Integer
    integer.name = "i64"
    let (function_index, function_error) = begin_function(&builder, 0usize, "main", 0usize)
    if function_error != ok { ret function_error }
    try begin_signature(&builder, function_index, &signatures)
    try add_parameter_type(&builder, function_index, &signatures, integer)
    try add_return_type(&builder, function_index, &signatures, integer)
    if signatures.entries[0usize].first_parameter_type != 0usize || signatures.entries[0usize].parameter_count != 1usize || signatures.entries[0usize].first_return_type != 1usize || signatures.entries[0usize].return_count != 1usize || signatures.count != 2usize { ret InvalidValue }
    ret ok
}
