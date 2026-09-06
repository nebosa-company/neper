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
        if builder.functions[at].module_index == 0usize && check.same(builder.functions[at].name, "main") { ret (at, ok) }
        at += 1usize
    }
    ret (0usize, InvalidExecutable)
}

fn append_name(output: *emit_x64.Buffer, name: str, width: usize) -> err {
    if name.len > width { ret InvalidExecutable }
    var at = 0usize
    while at < name.len {
        try emit_x64.byte(output, usize(name[at]))
        at += 1usize
    }
    while at < width {
        try emit_x64.byte(output, 0usize)
        at += 1usize
    }
    ret ok
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
    let text_address = 4096usize
    let startup_size = 19usize
    let text_size = startup_size + machine.count
    let (text_raw_size, text_raw_error) = align_up(text_size, 512usize)
    if text_raw_error != ok { ret text_raw_error }
    let (text_virtual_size, text_virtual_error) = align_up(text_size, 4096usize)
    if text_virtual_error != ok { ret text_virtual_error }
    let idata_address = text_address + text_virtual_size
    let idata_size = 100usize
    let (idata_raw_size, idata_raw_error) = align_up(idata_size, 512usize)
    if idata_raw_error != ok { ret idata_raw_error }
    let idata_raw_offset = headers_size + text_raw_size
    let image_size = idata_address + 4096usize
    let import_lookup_address = idata_address + 40usize
    let import_address_address = idata_address + 56usize
    let dll_name_address = idata_address + 72usize
    let exit_process_name_address = idata_address + 86usize

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
    try little_u16(output, 2usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 240usize)
    try little_u16(output, 34usize)

    try little_u16(output, 523usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.little_u32(output, text_raw_size)
    try emit_x64.little_u32(output, idata_raw_size)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, text_address)
    try emit_x64.little_u32(output, text_address)
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
    try little_u16(output, 256usize)
    try emit_x64.little_u64(output, 1048576usize)
    try emit_x64.little_u64(output, 4096usize)
    try emit_x64.little_u64(output, 1048576usize)
    try emit_x64.little_u64(output, 4096usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 16usize)
    try pad_to(output, 272usize)
    try emit_x64.little_u32(output, idata_address)
    try emit_x64.little_u32(output, 40usize)
    try pad_to(output, 360usize)
    try emit_x64.little_u32(output, import_address_address)
    try emit_x64.little_u32(output, 16usize)
    try pad_to(output, 392usize)

    try append_name(output, ".text", 8usize)
    try emit_x64.little_u32(output, text_size)
    try emit_x64.little_u32(output, text_address)
    try emit_x64.little_u32(output, text_raw_size)
    try emit_x64.little_u32(output, headers_size)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 1610612768usize)

    try append_name(output, ".idata", 8usize)
    try emit_x64.little_u32(output, idata_size)
    try emit_x64.little_u32(output, idata_address)
    try emit_x64.little_u32(output, idata_raw_size)
    try emit_x64.little_u32(output, idata_raw_offset)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 3221225536usize + 64usize)
    try pad_to(output, headers_size)

    try emit_x64.byte(output, 72usize)
    try emit_x64.byte(output, 131usize)
    try emit_x64.byte(output, 236usize)
    try emit_x64.byte(output, 40usize)
    let (call_displacement, call_error) = emit_x64.call(output)
    if call_error != ok { ret call_error }
    try emit_x64.byte(output, 137usize)
    try emit_x64.byte(output, 193usize)
    try emit_x64.byte(output, 255usize)
    try emit_x64.byte(output, 21usize)
    let exit_displacement_at = output.count
    let next_instruction_address = text_address + exit_displacement_at - headers_size + 4usize
    try emit_x64.little_u32(output, import_address_address - next_instruction_address)
    try emit_x64.byte(output, 15usize)
    try emit_x64.byte(output, 11usize)
    var machine_at = 0usize
    while machine_at < machine.count {
        try emit_x64.byte(output, machine.bytes[machine_at])
        machine_at += 1usize
    }
    let main_offset = headers_size + startup_size + function_offsets[main_index]
    try emit_x64.patch_relative32(output, call_displacement, main_offset)
    try pad_to(output, idata_raw_offset)

    try emit_x64.little_u32(output, import_lookup_address)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, dll_name_address)
    try emit_x64.little_u32(output, import_address_address)
    try pad_to(output, idata_raw_offset + 40usize)
    try emit_x64.little_u64(output, exit_process_name_address)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, exit_process_name_address)
    try emit_x64.little_u64(output, 0usize)
    try append_name(output, "KERNEL32.dll", 13usize)
    try emit_x64.byte(output, 0usize)
    try little_u16(output, 0usize)
    try append_name(output, "ExitProcess", 12usize)
    ret pad_to(output, idata_raw_offset + idata_raw_size)
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
    var executable_storage: [1600]usize = zero
    var executable: emit_x64.Buffer = zero
    try emit_x64.init(&executable, executable_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, &executable)
    if executable.count != 1536usize { ret InvalidExecutable }
    if executable.bytes[0usize] != 77usize || executable.bytes[1usize] != 90usize || executable.bytes[60usize] != 128usize { ret InvalidExecutable }
    if executable.bytes[128usize] != 80usize || executable.bytes[129usize] != 69usize || executable.bytes[132usize] != 100usize || executable.bytes[133usize] != 134usize || executable.bytes[134usize] != 2usize { ret InvalidExecutable }
    if executable.bytes[152usize] != 11usize || executable.bytes[153usize] != 2usize || executable.bytes[168usize] != 0usize || executable.bytes[169usize] != 16usize { ret InvalidExecutable }
    if executable.bytes[272usize] != 0usize || executable.bytes[273usize] != 32usize || executable.bytes[360usize] != 56usize || executable.bytes[361usize] != 32usize { ret InvalidExecutable }
    if executable.bytes[392usize] != 46usize || executable.bytes[393usize] != 116usize || executable.bytes[432usize] != 46usize || executable.bytes[433usize] != 105usize { ret InvalidExecutable }
    if executable.bytes[512usize] != 72usize || executable.bytes[516usize] != 232usize || executable.bytes[521usize] != 137usize || executable.bytes[523usize] != 255usize || executable.bytes[531usize] != 195usize { ret InvalidExecutable }
    if executable.bytes[1024usize] != 40usize || executable.bytes[1025usize] != 32usize || executable.bytes[1096usize] != 75usize || executable.bytes[1112usize] != 69usize { ret InvalidExecutable }
    ret ok
}
