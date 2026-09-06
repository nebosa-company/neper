// Deterministic x86-64 PE32+ executable linker for closed Neper programs.

use check
use codegen_x64
use emit_x64
use nir
use runtime_pe_x64

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

fn append_thunks(output: *emit_x64.Buffer, idata_address: usize) -> err {
    try emit_x64.little_u64(output, idata_address + 406usize)
    try emit_x64.little_u64(output, idata_address + 420usize)
    try emit_x64.little_u64(output, idata_address + 434usize)
    try emit_x64.little_u64(output, idata_address + 448usize)
    try emit_x64.little_u64(output, idata_address + 460usize)
    try emit_x64.little_u64(output, idata_address + 478usize)
    try emit_x64.little_u64(output, idata_address + 494usize)
    try emit_x64.little_u64(output, idata_address + 512usize)
    try emit_x64.little_u64(output, idata_address + 528usize)
    try emit_x64.little_u64(output, idata_address + 544usize)
    try emit_x64.little_u64(output, idata_address + 566usize)
    try emit_x64.little_u64(output, idata_address + 578usize)
    try emit_x64.little_u64(output, idata_address + 594usize)
    try emit_x64.little_u64(output, idata_address + 616usize)
    try emit_x64.little_u64(output, idata_address + 628usize)
    try emit_x64.little_u64(output, idata_address + 654usize)
    try emit_x64.little_u64(output, idata_address + 680usize)
    try emit_x64.little_u64(output, idata_address + 708usize)
    try emit_x64.little_u64(output, idata_address + 726usize)
    try emit_x64.little_u64(output, idata_address + 750usize)
    try emit_x64.little_u64(output, idata_address + 772usize)
    ret emit_x64.little_u64(output, 0usize)
}

fn append_import_name(output: *emit_x64.Buffer, name: str) -> err {
    try little_u16(output, 0usize)
    try append_name(output, name, name.len)
    try emit_x64.byte(output, 0usize)
    if output.count % 2usize != 0usize { try emit_x64.byte(output, 0usize) }
    ret ok
}

fn append_imports(output: *emit_x64.Buffer, raw_offset: usize, idata_address: usize) -> err {
    let lookup_address = idata_address + 40usize
    let iat_address = idata_address + 216usize
    let dll_address = idata_address + 392usize
    try emit_x64.little_u32(output, lookup_address)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, dll_address)
    try emit_x64.little_u32(output, iat_address)
    try pad_to(output, raw_offset + 40usize)
    try append_thunks(output, idata_address)
    try append_thunks(output, idata_address)
    try append_name(output, "KERNEL32.dll", 13usize)
    try emit_x64.byte(output, 0usize)
    try append_import_name(output, "CloseHandle")
    try append_import_name(output, "CreateFileW")
    try append_import_name(output, "ExitProcess")
    try append_import_name(output, "FindClose")
    try append_import_name(output, "FindFirstFileW")
    try append_import_name(output, "FindNextFileW")
    try append_import_name(output, "GetCommandLineW")
    try append_import_name(output, "GetLastError")
    try append_import_name(output, "GetStdHandle")
    try append_import_name(output, "MultiByteToWideChar")
    try append_import_name(output, "ReadFile")
    try append_import_name(output, "VirtualAlloc")
    try append_import_name(output, "WideCharToMultiByte")
    try append_import_name(output, "WriteFile")
    try append_import_name(output, "GetSystemTimeAsFileTime")
    try append_import_name(output, "QueryPerformanceCounter")
    try append_import_name(output, "QueryPerformanceFrequency")
    try append_import_name(output, "CreateProcessW")
    try append_import_name(output, "SetHandleInformation")
    try append_import_name(output, "WaitForSingleObject")
    ret append_import_name(output, "GetExitCodeProcess")
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len { ret InvalidExecutable }
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    let headers_size = 512usize
    let text_address = 4096usize
    let text_size = runtime_pe_x64.size() + machine.count
    let (text_raw_size, text_raw_error) = align_up(text_size, 512usize)
    if text_raw_error != ok { ret text_raw_error }
    let (text_virtual_size, text_virtual_error) = align_up(text_size, 4096usize)
    if text_virtual_error != ok { ret text_virtual_error }
    let idata_address = text_address + text_virtual_size
    let idata_size = 794usize
    let (idata_raw_size, idata_raw_error) = align_up(idata_size, 512usize)
    if idata_raw_error != ok { ret idata_raw_error }
    let idata_raw_offset = headers_size + text_raw_size
    let (idata_virtual_size, idata_virtual_error) = align_up(idata_size, 4096usize)
    if idata_virtual_error != ok { ret idata_virtual_error }
    let image_size = idata_address + idata_virtual_size
    let import_address_address = idata_address + 216usize

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
    try emit_x64.little_u32(output, 120usize)
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
    try emit_x64.little_u32(output, 3221225536usize)
    try pad_to(output, headers_size)

    let runtime_file = output.count
    try runtime_pe_x64.append(output)
    let machine_file = output.count
    var machine_at = 0usize
    while machine_at < machine.count {
        try emit_x64.byte(output, machine.bytes[machine_at])
        machine_at += 1usize
    }
    let main_file = machine_file + function_offsets[main_index]
    try runtime_pe_x64.patch(output, runtime_file, text_address, main_file, import_address_address)
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        if !relocations[relocation_at].resolved {
            let reference_index = relocations[relocation_at].function_ref
            if reference_index >= builder.function_ref_count { ret InvalidExecutable }
            let (runtime_offset, found_runtime) = runtime_pe_x64.symbol_offset(builder.function_refs[reference_index].name)
            if !found_runtime { ret InvalidExecutable }
            try emit_x64.patch_relative32(output, machine_file + relocations[relocation_at].displacement_at, runtime_file + runtime_offset)
            relocations[relocation_at].resolved = true
        }
        relocation_at += 1usize
    }
    try pad_to(output, idata_raw_offset)
    try append_imports(output, idata_raw_offset, idata_address)
    if output.count != idata_raw_offset + idata_size { ret InvalidExecutable }
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
    var main_function: nir.Function = zero
    main_function.name = "main"
    functions[0usize] = main_function
    var machine_storage: [1]usize = zero
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 195usize)
    var offsets: [1]usize = zero
    var relocations: [1]codegen_x64.Relocation = zero
    var executable_storage: [6000]usize = zero
    var executable: emit_x64.Buffer = zero
    try emit_x64.init(&executable, executable_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, &executable)
    if executable.count != 5632usize { ret InvalidExecutable }
    if executable.bytes[0usize] != 77usize || executable.bytes[1usize] != 90usize || executable.bytes[60usize] != 128usize { ret InvalidExecutable }
    if executable.bytes[128usize] != 80usize || executable.bytes[129usize] != 69usize || executable.bytes[132usize] != 100usize || executable.bytes[133usize] != 134usize || executable.bytes[134usize] != 2usize { ret InvalidExecutable }
    if executable.bytes[168usize] != 0usize || executable.bytes[169usize] != 16usize || executable.bytes[272usize] != 0usize || executable.bytes[273usize] != 32usize { ret InvalidExecutable }
    if executable.bytes[360usize] != 216usize || executable.bytes[361usize] != 32usize || executable.bytes[392usize] != 46usize || executable.bytes[432usize] != 46usize { ret InvalidExecutable }
    if executable.bytes[512usize] != 83usize || executable.bytes[548usize] != 8usize || executable.bytes[549usize] != 17usize || executable.bytes[4521usize] != 195usize { ret InvalidExecutable }
    if executable.bytes[4608usize] != 40usize || executable.bytes[4609usize] != 32usize || executable.bytes[5000usize] != 75usize || executable.bytes[5016usize] != 67usize { ret InvalidExecutable }
    ret ok
}
