// The aarch64 kernel image, OS `none` (D2126): Linux's arm64 `Image`, the one format
// QEMU's `-kernel`, crosvm and a phone's bootloader all load. Its 64-byte header branches
// to the runtime's entry; the code follows on a page, then the runtime -- its vectors 2 KB
// aligned -- the symbol table and the globals. Nothing in it is an absolute address: the
// code reaches everything by `adr`, `adrp` and `bl`, and the table holds offsets into the
// image, so the image runs wherever a loader puts it on a page. `image_size` covers the bss
// the runtime lays after the file -- its hook slots, the stack and the root arena -- so a
// loader keeps the device tree and anything else it places out of them.
use codegen_x64
use emit_x64
use emit_a64
use link_elf
use nir
use runtime_none_a64

error InvalidKernelImage
// A kernel has no loader, so it cannot `@import` a library.
error KernelImport
// A call to a runtime function the kernel runtime does not define: a system call's
// intrinsic, which has no meaning without an operating system underneath.
error KernelRuntime

const A64_KERNEL_PAGE: usize = 4096usize
const A64_KERNEL_HOOKS: usize = 32usize
const A64_KERNEL_STACK: usize = 262144usize
// The arena when the build names none: sixteen megabytes.
const A64_KERNEL_ARENA: usize = 16777216usize

fn kernel_runtime_limit(builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize) -> (usize, err) {
    let (limit, has_start) = runtime_none_a64.symbol_end("neper_start_arena")
    if !has_start { ret (0usize, InvalidKernelImage) }
    var most = limit
    var at = 0usize
    while at < relocation_count {
        if !relocations[at].global && !relocations[at].resolved {
            let reference_index = relocations[at].function_ref
            if reference_index >= builder.function_ref_count { ret (0usize, InvalidKernelImage) }
            let (end, found) = runtime_none_a64.symbol_end(builder.function_refs[reference_index].name)
            if found && end > most { most = end }
        }
        at += 1usize
    }
    ret (most, ok)
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, table_at: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len || table_at > machine.count { ret InvalidKernelImage }
    if nir.import_library_count(builder) != 0usize { ret KernelImport }
    let (main_index, main_error) = link_elf.find_main(builder)
    if main_error != ok { ret main_error }
    codegen_x64.mark_live_globals(builder, relocations, relocation_count)
    // The header: code0 the branch to the entry, code1 zero, text_offset zero, image_size
    // patched below, flags 0b1010 -- little-endian, 4 KB pages, anywhere in memory -- three
    // reserved words, the magic `ARM\x64`, and no PE header.
    try emit_x64.little_u32(output, 0x14000000usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 10usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u32(output, 0x644D5241usize)
    try emit_x64.little_u32(output, 0usize)
    // The code on a page, so a page delta between two offsets is the one between addresses
    // wherever the image lands on a page.
    let machine_start = A64_KERNEL_PAGE
    try link_elf.pad_to(output, machine_start)
    try emit_x64.append_bytes(output, machine.bytes[0usize..table_at])
    let runtime_start = link_elf.align_up_to(output.count, 2048usize)
    try link_elf.pad_to(output, runtime_start)
    let (limit, limit_error) = kernel_runtime_limit(builder, relocations, relocation_count)
    if limit_error != ok { ret limit_error }
    try runtime_none_a64.append(output, limit)
    var table_file = output.count
    if table_at < machine.count {
        table_file = link_elf.align_up_to(output.count, 8usize)
        try link_elf.pad_to(output, table_file)
        try emit_x64.append_bytes(output, machine.bytes[table_at..machine.count])
        try codegen_x64.rebase_symbol_table(output, table_file, machine_start)
    }
    // The globals on a page of their own; the bss after them, the arena on a page.
    var area_alignment = 16usize
    var alignment_at = 0usize
    while alignment_at < builder.global_count {
        if builder.globals[alignment_at].live && builder.globals[alignment_at].alignment > area_alignment { area_alignment = builder.globals[alignment_at].alignment }
        alignment_at += 1usize
    }
    let area_offset = link_elf.align_up_to(output.count, A64_KERNEL_PAGE)
    try link_elf.pad_to(output, area_offset)
    if nir.live_global_count(builder) != 0usize {
        try link_elf.append_globals(builder, output, area_offset)
        try link_elf.pad_to(output, area_offset + nir.global_area_size(builder))
    }
    let bss = link_elf.align_up_to(output.count, area_alignment)
    let arena_start = link_elf.align_up_to(bss + A64_KERNEL_HOOKS + A64_KERNEL_STACK, A64_KERNEL_PAGE)
    var arena = A64_KERNEL_ARENA
    if builder.arena_bytes != 0usize { arena = link_elf.align_up_to(builder.arena_bytes, A64_KERNEL_PAGE) }
    let (entry, has_entry) = runtime_none_a64.symbol_offset("neper_start")
    let (main_call, has_main_call) = runtime_none_a64.symbol_offset("neper_start_main")
    let (bss_literal, has_bss_literal) = runtime_none_a64.symbol_offset("neper_start_bss")
    let (stack_literal, has_stack_literal) = runtime_none_a64.symbol_offset("neper_start_stack")
    let (image_literal, has_image_literal) = runtime_none_a64.symbol_offset("neper_start_image")
    let (arena_literal, has_arena_literal) = runtime_none_a64.symbol_offset("neper_start_arena")
    if !has_entry || !has_main_call || !has_bss_literal || !has_stack_literal || !has_image_literal || !has_arena_literal { ret InvalidKernelImage }
    let entry_at = runtime_start + entry
    try emit_a64.patch_relative(output, 0usize, entry_at)
    try link_elf.patch_little_u64(output, 16usize, arena_start + arena)
    try emit_a64.patch_relative(output, runtime_start + main_call, machine_start + function_offsets[main_index])
    try link_elf.patch_little_u64(output, runtime_start + bss_literal, bss - entry_at)
    // The stack runs from the hooks to the arena, whatever its alignment left it.
    try link_elf.patch_little_u64(output, runtime_start + stack_literal, arena_start - bss - A64_KERNEL_HOOKS)
    try link_elf.patch_little_u64(output, runtime_start + image_literal, entry_at)
    try link_elf.patch_little_u64(output, runtime_start + arena_literal, arena)
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        let site = machine_start + relocation.displacement_at
        if relocation.global {
            if relocation.function_ref >= builder.global_count { ret InvalidKernelImage }
            try emit_a64.patch_relative(output, site, area_offset + nir.global_area_offset(builder, relocation.function_ref))
            relocations[relocation_at].resolved = true
        } else {
            if relocation.function_ref >= builder.function_ref_count { ret InvalidKernelImage }
            if codegen_x64.is_symbols_reference(builder, relocation) {
                try emit_a64.patch_relative(output, site, table_file)
                relocations[relocation_at].resolved = true
            } else {
                if !relocation.resolved {
                    let (runtime_offset, found_runtime) = runtime_none_a64.symbol_offset(builder.function_refs[relocation.function_ref].name)
                    if !found_runtime { ret KernelRuntime }
                    try emit_a64.patch_relative(output, site, runtime_start + runtime_offset)
                    relocations[relocation_at].resolved = true
                }
            }
        }
        relocation_at += 1usize
    }
    ret ok
}
