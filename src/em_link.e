// Deterministic assembly of cached .em machine code into own-linker input.

use e.mem
use binary
use check
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

// A string already located to `start`/`length` -- no walk of the string table.
fn copy_string_bytes(a: *mem.Arena, bytes: []const usize, start: usize, length: usize) -> (str, err) {
    if length == 0usize || start + length > bytes.len { ret ("", InvalidInput) }
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

// Each artifact's own interface module-name index, read once. `interface_module_index` validates
// the whole artifact -- a CRC over the file -- so calling it per relocation (as `target_module`
// once did) was thousands of CRCs; this reads it a few times instead.
fn module_index_cache(a: *mem.Arena, artifacts: []Artifact) -> ([]usize, err) {
    let (indices, indices_error) = mem.alloc[usize](a, artifacts.len + 1usize)
    if indices_error != ok { ret (zero, indices_error) }
    var at = 0usize
    while at < artifacts.len {
        let (module_index, module_error) = em.interface_module_index(artifacts[at].bytes)
        if module_error != ok { ret (zero, module_error) }
        indices[at] = module_index
        at += 1usize
    }
    ret (indices, ok)
}

fn target_module(artifacts: []Artifact, module_indices: []usize, source: []const usize, target_module_index: usize) -> (usize, err) {
    var at = 0usize
    while at < artifacts.len {
        let (matches, match_error) = em.strings_equal(source, target_module_index, artifacts[at].bytes, module_indices[at])
        if match_error != ok { ret (0usize, match_error) }
        if matches { ret (at, ok) }
        at += 1usize
    }
    ret (0usize, MissingSymbol)
}

// Which functions an image needs, read from the artifacts' own tables rather than from code: each
// records the functions it calls or takes the address of, which is the same edge set `nir` walks.
// A function is identified by its module and name as the relocations name it, so the two sides
// A flat table of every code function across the artifacts, built once in artifact-then-source
// order -- the order the keep-set and the copy loop both index by. Reading each function from
// its bytes on demand re-validates the artifact (a CRC over the whole file) and re-parses from
// function 0, which is O(functions^2) per module and was the reach walk's whole cost; this reads
// each once instead.
type FunctionTable = struct {
    funcs: []em.CodeFunction,
    owner: []usize,
    names: []str,
    base: []usize,
    count: usize,
}

fn build_function_table(a: *mem.Arena, artifacts: []Artifact, function_count: usize) -> (FunctionTable, err) {
    let empty = FunctionTable { funcs: zero, owner: zero, names: zero, base: zero, count: 0usize }
    let (funcs, funcs_error) = mem.alloc[em.CodeFunction](a, capacity(function_count))
    if funcs_error != ok { ret (empty, funcs_error) }
    let (owner, owner_error) = mem.alloc[usize](a, capacity(function_count))
    if owner_error != ok { ret (empty, owner_error) }
    let (names, names_error) = mem.alloc[str](a, capacity(function_count))
    if names_error != ok { ret (empty, names_error) }
    let (base, base_error) = mem.alloc[usize](a, artifacts.len + 1usize)
    if base_error != ok { ret (empty, base_error) }
    var position = 0usize
    var artifact_at = 0usize
    while artifact_at < artifacts.len {
        base[artifact_at] = position
        let bytes = artifacts[artifact_at].bytes
        let (count, count_error) = em.read_code_functions(bytes, funcs[position..function_count])
        if count_error != ok { ret (empty, count_error) }
        // Each name is copied through the artifact's string table, which `copy_string` walks from
        // the front every call -- quadratic over a module. Read the string starts once, then each
        // name is an O(1) index into them.
        let (string_total, string_count_error) = em.string_count(bytes)
        if string_count_error != ok { ret (empty, string_count_error) }
        let (starts, starts_error) = mem.alloc[usize](a, capacity(string_total))
        if starts_error != ok { ret (empty, starts_error) }
        let (read, read_error) = em.read_string_starts(bytes, starts)
        if read_error != ok { ret (empty, read_error) }
        var at = 0usize
        while at < count {
            owner[position + at] = artifact_at
            let name_index = funcs[position + at].name_index
            if name_index >= read { ret (empty, InvalidInput) }
            let start = starts[name_index]
            let (length, length_error) = em.string_length_at(bytes, start)
            if length_error != ok { ret (empty, length_error) }
            let (name, name_error) = copy_string_bytes(a, bytes, start, length)
            if name_error != ok { ret (empty, name_error) }
            names[position + at] = name
            at += 1usize
        }
        position += count
        artifact_at += 1usize
    }
    base[artifacts.len] = position
    ret (FunctionTable { funcs: funcs, owner: owner, names: names, base: base, count: position }, ok)
}

// Where a function sits in the table: searched within its own module's slice, since a callee
// names the module it is in. The keep-set and copy loop index by this position.
fn table_position(table: FunctionTable, module_index: usize, name: str, instance: usize) -> (usize, bool) {
    if module_index + 1usize >= table.base.len { ret (0usize, false) }
    var at = table.base[module_index]
    let stop = table.base[module_index + 1usize]
    while at < stop {
        if table.funcs[at].instance == instance && check.same(table.names[at], name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// Only what `main` reaches is kept, following the calls and taken addresses a relocation records
// -- the same edge set `nir` walks after lowering, so an image linked from artifacts drops the
// same functions from the same sequence as one compiled from source. Over the prebuilt table:
// no artifact is re-read, so a pass is the edges, not the file.
fn reachable_from_main(a: *mem.Arena, artifacts: []Artifact, module_indices: []usize, table: FunctionTable, kept: []bool) -> err {
    let total = table.count
    if total > kept.len { ret InvalidInput }
    var at = 0usize
    while at < total {
        kept[at] = false
        at += 1usize
    }

    var rooted = false
    at = 0usize
    while at < total {
        if table.owner[at] == 0usize && check.same(table.names[at], "main") {
            kept[at] = true
            rooted = true
            break
        }
        at += 1usize
    }
    if !rooted {
        // Nothing named `main` is the linker's own error to report, and it does, with a message a
        // program of no functions would not produce.
        var index = 0usize
        while index < total {
            kept[index] = true
            index += 1usize
        }
        ret ok
    }

    // Breadth-first from `main` over the call edges each function records: a function is visited
    // once, and its edges -- the string copy and the module scan a callee needs -- are resolved
    // only then. A module the program never enters is never scanned, which is what a program that
    // pulls in a large module but reaches little of it depends on. A global or a host-runtime
    // symbol is not a function edge and is skipped.
    let (queue, queue_error) = mem.alloc[usize](a, total)
    if queue_error != ok { ret queue_error }
    queue[0usize] = at
    var head = 0usize
    var tail = 1usize
    while head < tail {
        let position = queue[head]
        head += 1usize
        let function = table.funcs[position]
        let owner = table.owner[position]
        var relocation_at = 0usize
        while relocation_at < function.relocation_count {
            let (stored, stored_error) = em.artifact_code_relocation_at(artifacts[owner].bytes, function, relocation_at)
            if stored_error != ok { ret stored_error }
            if !stored.global {
                let (module_index, module_error) = target_module(artifacts, module_indices, artifacts[owner].bytes, stored.module_index)
                if module_error != ok { ret module_error }
                let (callee_name, callee_error) = copy_string(a, artifacts[owner].bytes, stored.name_index)
                if callee_error != ok { ret callee_error }
                let (callee, found) = table_position(table, module_index, callee_name, stored.instance)
                if found && !kept[callee] {
                    kept[callee] = true
                    queue[tail] = callee
                    tail += 1usize
                }
            }
            relocation_at += 1usize
        }
    }
    ret ok
}

fn assemble(a: *mem.Arena, artifacts: []Artifact, program: *Program) -> err {
    try validate_set(artifacts)
    var function_count = 0usize
    var global_count = 0usize
    var artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.artifact_code_count(artifacts[artifact_at].bytes)
        if count_error != ok { ret count_error }
        function_count += count
        let (globals_here, globals_error) = em.artifact_global_count(artifacts[artifact_at].bytes)
        if globals_error != ok { ret globals_error }
        global_count += globals_here
        artifact_at += 1usize
    }
    if function_count == 0usize { ret InvalidInput }

    // Read every function once into a table the reachability pass and the copy loop both index,
    // then take the sizes from it -- no artifact is parsed per function or re-validated per read.
    let (table, table_error) = build_function_table(a, artifacts, function_count)
    if table_error != ok { ret table_error }
    var relocation_count = 0usize
    var code_size = 0usize
    var table_at = 0usize
    while table_at < table.count {
        let function = table.funcs[table_at]
        code_size += function.code_length
        relocation_count += function.relocation_count
        table_at += 1usize
    }
    // A function's hash input is its code, its relocations and their names, all of which live in
    // the one artifact -- so that artifact's own length bounds it. The exact per-function size
    // needs `string_bounds`, which walks the string table from the start on every call; asking it
    // once per function was the reach path's other quadratic. The largest artifact is the bound.
    var hash_scratch_size = 0usize
    var scratch_at = 0usize
    while scratch_at < artifacts.len {
        if artifacts[scratch_at].bytes.len > hash_scratch_size { hash_scratch_size = artifacts[scratch_at].bytes.len }
        scratch_at += 1usize
    }

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
    // Every module's `var`s, in artifact order and each artifact's own order: the linker lays
    // them out from the builder exactly as the source path does, and a relocation finds its
    // global by the module and name the artifact recorded.
    let (global_storage, globals_storage_error) = mem.alloc[nir.GlobalData](a, capacity(global_count))
    if globals_storage_error != ok { ret globals_storage_error }
    try nir.init_globals(&program.builder, global_storage)
    artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.artifact_global_count(artifacts[artifact_at].bytes)
        if count_error != ok { ret count_error }
        var global_index = 0usize
        while global_index < count {
            let (record, record_error) = em.artifact_global_at(artifacts[artifact_at].bytes, global_index)
            if record_error != ok { ret record_error }
            let (name, name_error) = copy_string(a, artifacts[artifact_at].bytes, record.name_index)
            if name_error != ok { ret name_error }
            let (added, add_error) = nir.add_global(&program.builder, artifact_at, name, record.size, record.alignment, record.initial, record.has_initial)
            if add_error != ok { ret add_error }
            global_index += 1usize
        }
        artifact_at += 1usize
    }
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

    // The same rule the source path applies after lowering: keep what `main` reaches and drop the
    // rest. It is done here, before a byte of code is copied, so that both link paths leave out
    // the same functions from the same sequence -- which is what makes an image linked from
    // artifacts identical to one compiled from source.
    let (kept, kept_error) = mem.alloc[bool](a, function_count)
    if kept_error != ok { ret kept_error }
    let (module_indices, module_indices_error) = module_index_cache(a, artifacts)
    if module_indices_error != ok { ret module_indices_error }
    let reach_error = reachable_from_main(a, artifacts, module_indices, table, kept)
    if reach_error != ok { ret reach_error }
    var position = 0usize
    while position < table.count {
            if !kept[position] {
                position += 1usize
                continue
            }
            let owner_at = table.owner[position]
            let function = table.funcs[position]
            // The content hash is the artifact's own integrity check, verified for what is
            // emitted -- after the keep test, so a dropped function is not hashed for nothing.
            let (content_hash, content_hash_error) = em.artifact_code_content_hash(artifacts[owner_at].bytes, function, &hash_scratch)
            if content_hash_error != ok || content_hash != function.content_hash { ret InvalidInput }
            let name = table.names[position]
            let global_function = program.builder.function_count
            var assembled_function: nir.Function = zero
            assembled_function.name = name
            assembled_function.module_index = owner_at
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
                position += 1usize
                continue
            }
            program.function_offsets[global_function] = program.machine.count
            if folded_count == folded_hashes.len { ret InvalidInput }
            folded_hashes[folded_count] = function.content_hash
            folded_offsets[folded_count] = program.machine.count
            folded_count += 1usize
            var code_at = 0usize
            while code_at < function.code_length {
                try emit_x64.byte(&program.machine, artifacts[owner_at].bytes[function.code_start + code_at])
                code_at += 1usize
            }
            var relocation_at = 0usize
            while relocation_at < function.relocation_count {
                let (stored, stored_error) = em.artifact_code_relocation_at(artifacts[owner_at].bytes, function, relocation_at)
                if stored_error != ok { ret stored_error }
                let (module_index, module_error) = target_module(artifacts, module_indices, artifacts[owner_at].bytes, stored.module_index)
                if module_error != ok { ret module_error }
                let (target_name, target_name_error) = copy_string(a, artifacts[owner_at].bytes, stored.name_index)
                if target_name_error != ok { ret target_name_error }
                if stored.global {
                    let (global_index, found_global) = find_global(&program.builder, module_index, target_name)
                    if !found_global { ret MissingSymbol }
                    try codegen_x64.add_global_relocation(program.relocations, &program.relocation_count, program.function_offsets[global_function] + stored.displacement_at, global_index)
                    relocation_at += 1usize
                    continue
                }
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
            position += 1usize
    }
    try codegen_x64.resolve_calls(&program.builder, program.function_offsets, program.relocations, program.relocation_count, &program.machine)
    var relocation_at = 0usize
    while relocation_at < program.relocation_count {
        if !program.relocations[relocation_at].resolved && !program.relocations[relocation_at].global {
            let reference_index = program.relocations[relocation_at].function_ref
            if reference_index >= program.builder.function_ref_count { ret InvalidInput }
            if !host_runtime_symbol(program.builder.function_refs[reference_index].name) { ret MissingSymbol }
        }
        relocation_at += 1usize
    }
    ret ok
}

fn find_global(builder: *nir.Builder, module_index: usize, name: str) -> (usize, bool) {
    var at = 0usize
    while at < builder.global_count {
        if builder.globals[at].module_index == module_index && check.same(builder.globals[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
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
