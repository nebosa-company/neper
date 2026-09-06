// Minimal deterministic x86-64 ELF executable linker for closed modules.

use check
use codegen_x64
use emit_x64
use nir

error InvalidExecutable

fn little_u16(output: *emit_x64.Buffer, value: usize) -> err {
    try emit_x64.byte(output, value % 256usize)
    ret emit_x64.byte(output, value / 256usize % 256usize)
}

fn pad_to(output: *emit_x64.Buffer, offset: usize) -> err {
    if output.count > offset { ret InvalidExecutable }
    while output.count < offset { try emit_x64.byte(output, 0usize) }
    ret ok
}

fn find_main(builder: *nir.Builder) -> (usize, err) {
    var at = 0usize
    while at < builder.function_count {
        if check.same(builder.functions[at].name, "main") { ret (at, ok) }
        at += 1usize
    }
    ret (0usize, InvalidExecutable)
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len { ret InvalidExecutable }
    if relocation_count > relocations.len { ret InvalidExecutable }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        if !relocations[relocation_at].resolved { ret InvalidExecutable }
        relocation_at += 1usize
    }
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    let code_offset = 4096usize
    let startup_size = 24usize
    let file_size = code_offset + startup_size + machine.count
    try emit_x64.byte(output, 127usize)
    try emit_x64.byte(output, 69usize)
    try emit_x64.byte(output, 76usize)
    try emit_x64.byte(output, 70usize)
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try pad_to(output, 16usize)
    try little_u16(output, 2usize)
    try little_u16(output, 62usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u64(output, 4198400usize)
    try emit_x64.little_u64(output, 64usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 64usize)
    try little_u16(output, 56usize)
    try little_u16(output, 1usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 5usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 4194304usize)
    try emit_x64.little_u64(output, 4194304usize)
    try emit_x64.little_u64(output, file_size)
    try emit_x64.little_u64(output, file_size)
    try emit_x64.little_u64(output, 4096usize)
    try pad_to(output, code_offset)
    try emit_x64.byte(output, 49usize)
    try emit_x64.byte(output, 255usize)
    try emit_x64.byte(output, 49usize)
    try emit_x64.byte(output, 246usize)
    let (call_displacement, call_error) = emit_x64.call(output)
    if call_error != ok { ret call_error }
    try emit_x64.mov_register(output, 7usize, 0usize)
    try emit_x64.mov_immediate(output, 0usize, 60usize)
    try emit_x64.byte(output, 15usize)
    try emit_x64.byte(output, 5usize)
    var at = 0usize
    while at < machine.count {
        try emit_x64.byte(output, machine.bytes[at])
        at += 1usize
    }
    let main_offset = code_offset + startup_size + function_offsets[main_index]
    try emit_x64.patch_relative32(output, call_displacement, main_offset)
    ret ok
}

fn self_test() -> err {
    var functions: [1]nir.Function = zero
    var blocks: [1]nir.Block = zero
    var instructions: [1]nir.Instruction = zero
    var operands: [1]usize = zero
    var references: [1]nir.FunctionRef = zero
    var strings: [1]nir.StringConstant = zero
    var builder: nir.Builder = zero
    try nir.init(&builder, functions[..], blocks[..], instructions[..], operands[..], references[..], strings[..])
    builder.function_count = 1usize
    builder.functions[0usize] = zero
    builder.functions[0usize].name = "main"
    var machine_storage: [1]usize = zero
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 195usize)
    var offsets: [1]usize = zero
    var relocations: [1]codegen_x64.Relocation = zero
    var executable_storage: [4200]usize = zero
    var executable: emit_x64.Buffer = zero
    try emit_x64.init(&executable, executable_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, &executable)
    if executable.count != 4121usize { ret InvalidExecutable }
    if executable.bytes[0usize] != 127usize || executable.bytes[16usize] != 2usize || executable.bytes[18usize] != 62usize || executable.bytes[24usize] != 0usize || executable.bytes[25usize] != 16usize || executable.bytes[26usize] != 64usize { ret InvalidExecutable }
    if executable.bytes[64usize] != 1usize || executable.bytes[68usize] != 5usize || executable.bytes[96usize] != 25usize || executable.bytes[97usize] != 16usize { ret InvalidExecutable }
    if executable.bytes[4096usize] != 49usize || executable.bytes[4100usize] != 232usize || executable.bytes[4101usize] != 15usize || executable.bytes[4120usize] != 195usize { ret InvalidExecutable }
    ret ok
}
