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
}

type Instruction = struct {
    opcode: Opcode,
    result: usize,
    has_result: bool,
    ty: check.Type,
    first_operand: usize,
    operand_count: usize,
    immediate: usize,
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
    first_block: usize,
    block_count: usize,
    first_instruction: usize,
    instruction_count: usize,
    value_count: usize,
}

type Builder = struct {
    functions: []Function,
    blocks: []Block,
    instructions: []Instruction,
    operands: []usize,
    function_count: usize,
    block_count: usize,
    instruction_count: usize,
    operand_count: usize,
    current_function: usize,
    current_block: usize,
    next_value: usize,
    function_active: bool,
    block_active: bool,
}

fn is_terminator(opcode: Opcode) -> bool {
    ret opcode == .Trap || opcode == .Branch || opcode == .BranchIf || opcode == .Switch || opcode == .Return || opcode == .Unreachable
}

fn init(builder: *Builder, functions: []Function, blocks: []Block, instructions: []Instruction, operands: []usize) -> err {
    if functions.len == 0usize || blocks.len == 0usize || instructions.len == 0usize || operands.len == 0usize { ret Capacity }
    builder.functions = functions
    builder.blocks = blocks
    builder.instructions = instructions
    builder.operands = operands
    builder.function_count = 0usize
    builder.block_count = 0usize
    builder.instruction_count = 0usize
    builder.operand_count = 0usize
    builder.current_function = 0usize
    builder.current_block = 0usize
    builder.next_value = 0usize
    builder.function_active = false
    builder.block_active = false
    ret ok
}

fn begin_function(builder: *Builder, module_index: usize, name: str) -> (usize, err) {
    if builder.function_active { ret (0usize, InvalidControlFlow) }
    if builder.function_count == builder.functions.len { ret (0usize, Capacity) }
    let index = builder.function_count
    builder.functions[index] = Function {
        name: name,
        module_index: module_index,
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

fn end_function(builder: *Builder) -> err {
    if !builder.function_active || !builder.block_active || !builder.blocks[builder.current_block].terminated { ret InvalidControlFlow }
    builder.functions[builder.current_function].value_count = builder.next_value
    builder.function_active = false
    builder.block_active = false
    ret ok
}

fn self_test() -> err {
    var functions: [1]Function = zero
    var blocks: [1]Block = zero
    var instructions: [4]Instruction = zero
    var operands: [4]usize = zero
    var builder: Builder = zero
    try init(&builder, functions[..], blocks[..], instructions[..], operands[..])
    let (function_index, function_error) = begin_function(&builder, 0usize, "main")
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
