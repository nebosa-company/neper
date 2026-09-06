// Minimal deterministic x86-64 PE32+ executable linker for closed modules.

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

fn align_up(value: usize, alignment: usize) -> (usize, err) {
    if alignment == 0usize { ret (0usize, InvalidExecutable) }
    ret ((value + alignment - 1usize) / alignment * alignment, ok)
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
    if builder.function_count > function_offsets.len || relocation_count > relocations.len { ret InvalidExecutable }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        if !relocations[relocation_at].resolved { ret InvalidExecutable }
        relocation_at += 1usize
    }
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    let headers_size = 512usize
    let code_address = 4096usize
    let startup_size = 18usize
    let code_size = startup_size + machine.count
    let (raw_size, raw_error) = align_up(code_size, 512usize)
    if raw_error != ok { ret raw_error }
    let (virtual_size, virtual_error) = align_up(code_size, 4096usize)
    if virtual_error != ok { ret virtual_error }
    let image_size = code_address + virtual_size

    try emit_x64.byte(output, 77usize)
    try emit_x64.byte(output, 90usize)
    try pad_to(output, 60usize)
    try emit_x64.little_u32(output, 128usize)
    try pad_to(output, 128usize)
    try emit_x64.byte(output, 80usize)
    try emit_x64.byte(output, 69usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try little_u16(output, 34404usize)
    try little_u16(output, 1usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 240usize)
    try little_u16(output, 34usize)

    try little_u16(output, 523usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.little_u32(output, raw_size)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, code_address)
    try emit_x64.little_u32(output, code_address)
    try emit_x64.little_u64(output, 5368709120usize)
    try emit_x64.little_u32(output, 4096usize)
    try emit_x64.little_u32(output, 512usize)
    try little_u16(output, 6usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 6usize)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, image_size)
    try emit_x64.little_u32(output, headers_size)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 3usize)
    try little_u16(output, 352usize)
    try emit_x64.little_u64(output, 1048576usize)
    try emit_x64.little_u64(output, 4096usize)
    try emit_x64.little_u64(output, 1048576usize)
    try emit_x64.little_u64(output, 4096usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 16usize)
    try pad_to(output, 392usize)

    try emit_x64.byte(output, 46usize)
    try emit_x64.byte(output, 116usize)
    try emit_x64.byte(output, 101usize)
    try emit_x64.byte(output, 120usize)
    try emit_x64.byte(output, 116usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.little_u32(output, code_size)
    try emit_x64.little_u32(output, code_address)
    try emit_x64.little_u32(output, raw_size)
    try emit_x64.little_u32(output, headers_size)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 1610612768usize)
    try pad_to(output, headers_size)

    try emit_x64.byte(output, 72usize)
    try emit_x64.byte(output, 131usize)
    try emit_x64.byte(output, 236usize)
    try emit_x64.byte(output, 40usize)
    try emit_x64.byte(output, 49usize)
    try emit_x64.byte(output, 201usize)
    try emit_x64.byte(output, 49usize)
    try emit_x64.byte(output, 210usize)
    let (call_displacement, call_error) = emit_x64.call(output)
    if call_error != ok { ret call_error }
    try emit_x64.byte(output, 72usize)
    try emit_x64.byte(output, 131usize)
    try emit_x64.byte(output, 196usize)
    try emit_x64.byte(output, 40usize)
    try emit_x64.byte(output, 195usize)
    var machine_at = 0usize
    while machine_at < machine.count {
        try emit_x64.byte(output, machine.bytes[machine_at])
        machine_at += 1usize
    }
    let main_offset = headers_size + startup_size + function_offsets[main_index]
    try emit_x64.patch_relative32(output, call_displacement, main_offset)
    ret pad_to(output, headers_size + raw_size)
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
    var executable_storage: [1024]usize = zero
    var executable: emit_x64.Buffer = zero
    try emit_x64.init(&executable, executable_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, &executable)
    if executable.count != 1024usize { ret InvalidExecutable }
    if executable.bytes[0usize] != 77usize || executable.bytes[1usize] != 90usize || executable.bytes[60usize] != 128usize { ret InvalidExecutable }
    if executable.bytes[128usize] != 80usize || executable.bytes[129usize] != 69usize || executable.bytes[132usize] != 100usize || executable.bytes[133usize] != 134usize { ret InvalidExecutable }
    if executable.bytes[152usize] != 11usize || executable.bytes[153usize] != 2usize || executable.bytes[169usize] != 16usize { ret InvalidExecutable }
    if executable.bytes[392usize] != 46usize || executable.bytes[393usize] != 116usize || executable.bytes[400usize] != 19usize || executable.bytes[405usize] != 16usize { ret InvalidExecutable }
    if executable.bytes[512usize] != 72usize || executable.bytes[520usize] != 232usize || executable.bytes[521usize] != 5usize || executable.bytes[530usize] != 195usize { ret InvalidExecutable }
    ret ok
}
