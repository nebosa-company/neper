// Deterministic assembly of cached .em machine code into own-linker input.

use e.mem
use binary
use codegen_x64
use em
use emit_x64
use nir

error InvalidInput
error DuplicateModule
error TargetMismatch
error MissingSymbol

type Artifact = struct {
    bytes: []usize,
}

type Program = struct {
    builder: nir.Builder,
    machine: emit_x64.Buffer,
    function_offsets: []usize,
    relocations: []codegen_x64.Relocation,
    relocation_count: usize,
}

fn capacity(value: usize) -> usize {
    if value == 0usize { ret 1usize }
    ret value
}

fn copy_string(a: *mem.Arena, bytes: []const usize, index: usize) -> (str, err) {
    let (start, length, bounds_error) = em.string_bounds(bytes, index)
    if bounds_error != ok || length == 0usize { ret ("", InvalidInput) }
    let (storage, storage_error) = mem.alloc[u8](a, length)
    if storage_error != ok { ret ("", storage_error) }
    var at = 0usize
    while at < length {
        if bytes[start + at] > 255usize { ret ("", InvalidInput) }
        storage[at] = u8(bytes[start + at])
        at += 1usize
    }
    ret (storage[..], ok)
}

fn validate_set(artifacts: []Artifact) -> err {
    if artifacts.len == 0usize { ret InvalidInput }
    let (root_target, root_target_error) = em.artifact_target_index(artifacts[0usize].bytes)
    if root_target_error != ok { ret root_target_error }
    var at = 0usize
    while at < artifacts.len {
        let (artifact_target, target_error) = em.artifact_target_index(artifacts[at].bytes)
        if target_error != ok { ret target_error }
        let (same_target, target_match_error) = em.strings_equal(artifacts[0usize].bytes, root_target, artifacts[at].bytes, artifact_target)
        if target_match_error != ok { ret target_match_error }
        if !same_target { ret TargetMismatch }
        let (module_index, module_error) = em.interface_module_index(artifacts[at].bytes)
        if module_error != ok { ret module_error }
        var prior = 0usize
        while prior < at {
            let (prior_module, prior_error) = em.interface_module_index(artifacts[prior].bytes)
            if prior_error != ok { ret prior_error }
            let (same_module, same_module_error) = em.strings_equal(artifacts[prior].bytes, prior_module, artifacts[at].bytes, module_index)
            if same_module_error != ok { ret same_module_error }
            if same_module { ret DuplicateModule }
            prior += 1usize
        }
        at += 1usize
    }
    ret ok
}

fn target_module(artifacts: []Artifact, source: []const usize, target_module_index: usize) -> (usize, err) {
    var at = 0usize
    while at < artifacts.len {
        let (candidate_module, candidate_error) = em.interface_module_index(artifacts[at].bytes)
        if candidate_error != ok { ret (0usize, candidate_error) }
        let (matches, match_error) = em.strings_equal(source, target_module_index, artifacts[at].bytes, candidate_module)
        if match_error != ok { ret (0usize, match_error) }
        if matches { ret (at, ok) }
        at += 1usize
    }
    ret (0usize, MissingSymbol)
}

fn assemble(a: *mem.Arena, artifacts: []Artifact, program: *Program) -> err {
    try validate_set(artifacts)
    var function_count = 0usize
    var relocation_count = 0usize
    var code_size = 0usize
    var hash_scratch_size = 0usize
    var artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.artifact_code_count(artifacts[artifact_at].bytes)
        if count_error != ok { ret count_error }
        function_count += count
        var function_at = 0usize
        while function_at < count {
            let (function, function_error) = em.artifact_code_function_at(artifacts[artifact_at].bytes, function_at)
            if function_error != ok { ret function_error }
            code_size += function.code_length
            relocation_count += function.relocation_count
            let (hash_size, hash_size_error) = em.artifact_code_hash_input_size(artifacts[artifact_at].bytes, function)
            if hash_size_error != ok { ret hash_size_error }
            if hash_size > hash_scratch_size { hash_scratch_size = hash_size }
            function_at += 1usize
        }
        artifact_at += 1usize
    }
    if function_count == 0usize { ret InvalidInput }

    let (hash_storage, hash_storage_error) = mem.alloc[usize](a, capacity(hash_scratch_size))
    if hash_storage_error != ok { ret hash_storage_error }
    var hash_scratch: binary.Buffer = zero
    try binary.init(&hash_scratch, hash_storage)

    let (function_storage, functions_error) = mem.alloc[nir.Function](a, function_count)
    if functions_error != ok { ret functions_error }
    var functions = function_storage
    let (blocks, blocks_error) = mem.alloc[nir.Block](a, 1usize)
    if blocks_error != ok { ret blocks_error }
    let (instructions, instructions_error) = mem.alloc[nir.Instruction](a, 1usize)
    if instructions_error != ok { ret instructions_error }
    let (operands, operands_error) = mem.alloc[usize](a, 1usize)
    if operands_error != ok { ret operands_error }
    let (reference_storage, references_error) = mem.alloc[nir.FunctionRef](a, capacity(relocation_count))
    if references_error != ok { ret references_error }
    var references = reference_storage
    let (strings, strings_error) = mem.alloc[nir.StringConstant](a, 1usize)
    if strings_error != ok { ret strings_error }
    try nir.init(&program.builder, functions, blocks, instructions, operands, references, strings)
    let (machine_storage, machine_error) = mem.alloc[usize](a, capacity(code_size))
    if machine_error != ok { ret machine_error }
    try emit_x64.init(&program.machine, machine_storage)
    let (function_offsets, offsets_error) = mem.alloc[usize](a, function_count)
    if offsets_error != ok { ret offsets_error }
    program.function_offsets = function_offsets
    let (relocations, relocations_error) = mem.alloc[codegen_x64.Relocation](a, capacity(relocation_count))
    if relocations_error != ok { ret relocations_error }
    program.relocations = relocations
    program.relocation_count = 0usize
    // Every module owns its own copy of the generic instances it uses, so the same
    // concrete function arrives from several artifacts. A content hash covers both
    // the code bytes and each relocation target, so equal hashes are the same
    // function and share one copy.
    let (folded_hashes, folded_hashes_error) = mem.alloc[usize](a, function_count)
    if folded_hashes_error != ok { ret folded_hashes_error }
    let (folded_offsets, folded_offsets_error) = mem.alloc[usize](a, function_count)
    if folded_offsets_error != ok { ret folded_offsets_error }
    var folded_count = 0usize

    artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.artifact_code_count(artifacts[artifact_at].bytes)
        if count_error != ok { ret count_error }
        var function_at = 0usize
        while function_at < count {
            let (function, function_error) = em.artifact_code_function_at(artifacts[artifact_at].bytes, function_at)
            if function_error != ok { ret function_error }
            let (content_hash, content_hash_error) = em.artifact_code_content_hash(artifacts[artifact_at].bytes, function, &hash_scratch)
            if content_hash_error != ok || content_hash != function.content_hash { ret InvalidInput }
            let (name, name_error) = copy_string(a, artifacts[artifact_at].bytes, function.name_index)
            if name_error != ok { ret name_error }
            let global_function = program.builder.function_count
            var assembled_function: nir.Function = zero
            assembled_function.name = name
            assembled_function.module_index = artifact_at
            assembled_function.instance = function.instance
            functions[global_function] = assembled_function
            program.builder.function_count += 1usize
            var folded = false
            var fold_at = 0usize
            while fold_at < folded_count {
                if folded_hashes[fold_at] == function.content_hash {
                    program.function_offsets[global_function] = folded_offsets[fold_at]
                    folded = true
                    break
                }
                fold_at += 1usize
            }
            if folded {
                function_at += 1usize
                continue
            }
            program.function_offsets[global_function] = program.machine.count
            if folded_count == folded_hashes.len { ret InvalidInput }
            folded_hashes[folded_count] = function.content_hash
            folded_offsets[folded_count] = program.machine.count
            folded_count += 1usize
            var code_at = 0usize
            while code_at < function.code_length {
                try emit_x64.byte(&program.machine, artifacts[artifact_at].bytes[function.code_start + code_at])
                code_at += 1usize
            }
            var relocation_at = 0usize
            while relocation_at < function.relocation_count {
                let (stored, stored_error) = em.artifact_code_relocation_at(artifacts[artifact_at].bytes, function, relocation_at)
                if stored_error != ok { ret stored_error }
                let (module_index, module_error) = target_module(artifacts, artifacts[artifact_at].bytes, stored.module_index)
                if module_error != ok { ret module_error }
                let (target_name, target_name_error) = copy_string(a, artifacts[artifact_at].bytes, stored.name_index)
                if target_name_error != ok { ret target_name_error }
                let reference_index = program.builder.function_ref_count
                var assembled_reference: nir.FunctionRef = zero
                assembled_reference.module_index = module_index
                assembled_reference.name = target_name
                assembled_reference.instance = stored.instance
                references[reference_index] = assembled_reference
                program.builder.function_ref_count += 1usize
                var assembled_relocation: codegen_x64.Relocation = zero
                assembled_relocation.displacement_at = program.function_offsets[global_function] + stored.displacement_at
                assembled_relocation.function_ref = reference_index
                assembled_relocation.resolved = false
                program.relocations[program.relocation_count] = assembled_relocation
                program.relocation_count += 1usize
                relocation_at += 1usize
            }
            function_at += 1usize
        }
        artifact_at += 1usize
    }
    try codegen_x64.resolve_calls(&program.builder, program.function_offsets, program.relocations, program.relocation_count, &program.machine)
    var relocation_at = 0usize
    while relocation_at < program.relocation_count {
        if !program.relocations[relocation_at].resolved {
            let reference_index = program.relocations[relocation_at].function_ref
            if reference_index >= program.builder.function_ref_count { ret InvalidInput }
            if !host_runtime_symbol(program.builder.function_refs[reference_index].name) { ret MissingSymbol }
        }
        relocation_at += 1usize
    }
    ret ok
}

// A call the artifacts cannot satisfy is a missing artifact, except where the host
// runtime provides it. Those are left for `link_pe` and `link_elf`, which own the
// per-target symbol tables and reject a name neither of them knows -- the same
// division the direct path already uses. A module function spelled with the
// reserved prefix is unaffected: it is in the artifacts and resolves above.
fn host_runtime_symbol(name: str) -> bool {
    let prefix = "neper_"
    if name.len < prefix.len { ret false }
    var at = 0usize
    while at < prefix.len {
        if name[at] != prefix[at] { ret false }
        at += 1usize
    }
    ret true
}
