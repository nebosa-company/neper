// Deterministic assembly of cached .em machine code into own-linker input.

use e.mem
use e.os
use binary
use graph
use check
use codegen_x64
use em
use emit_x64
use lookup
use nir

error InvalidInput
error DuplicateModule
error TargetMismatch
error MissingSymbol

type Artifact = struct {
    bytes: []const u8,
    // The string table's bounds, walked once when the artifact is taken up (D319).
    string_starts: []usize,
    string_lengths: []usize,
    // Which artifact each of its strings names as a module, plus one, once the reach
    // walk has looked it up (D461); zero until then. A relocation names its callee's
    // module by a string index, and the same few strings were hashed and found again
    // per relocation, in the walk and in the copy.
    module_of: []usize,
}

type Program = struct {
    builder: nir.Builder,
    machine: emit_x64.Buffer,
    function_offsets: []usize,
    relocations: []codegen_x64.Relocation,
    relocation_count: usize,
    // Section 13's line table, re-based to the assembled code (D209).
    lines: []codegen_x64.LineEntry,
    line_count: usize,
    // The reference no artifact defines, when the link fails with `MissingSymbol`.
    missing_symbol: str,
    // What the link's worker arenas committed (D339).
    worker_bytes: usize,
    // What `reachable_from_main` dropped, for `--stats` (D334): functions and their code bytes.
    unreached_functions: usize,
    unreached_bytes: usize,
}

fn capacity(value: usize) -> usize {
    if value == 0usize { ret 1usize }
    ret value
}

// A string already located to `start`/`length` -- no walk of the string table, and no
// copy (D320): the artifact's bytes are bytes and outlive the link, so a name is a view.
fn copy_string_bytes(a: *mem.Arena, bytes: []const u8, start: usize, length: usize) -> (str, err) {
    if length == 0usize || start + length > bytes.len { ret ("", InvalidInput) }
    ret (bytes[start..start + length], ok)
}

fn copy_string(a: *mem.Arena, bytes: []const u8, index: usize) -> (str, err) {
    let (start, length, bounds_error) = em.string_bounds(bytes, index)
    if bounds_error != ok || length == 0usize { ret ("", InvalidInput) }
    let (text, copy_error) = copy_string_bytes(a, bytes, start, length)
    ret (text, copy_error)
}

// A string of an artifact whose bounds are known (D319).
fn artifact_text(a: *mem.Arena, artifact: Artifact, index: usize) -> (str, err) {
    if index >= artifact.string_starts.len { ret ("", InvalidInput) }
    let (text, copy_error) = copy_string_bytes(a, artifact.bytes, artifact.string_starts[index], artifact.string_lengths[index])
    ret (text, copy_error)
}

fn artifact_strings_equal(left: Artifact, left_index: usize, right: Artifact, right_index: usize) -> bool {
    if left_index >= left.string_starts.len || right_index >= right.string_starts.len { ret false }
    let length = left.string_lengths[left_index]
    if length != right.string_lengths[right_index] { ret false }
    var at = 0usize
    while at < length {
        if left.bytes[left.string_starts[left_index] + at] != right.bytes[right.string_starts[right_index] + at] { ret false }
        at += 1usize
    }
    ret true
}

fn validate_set(a: *mem.Arena, artifacts: []Artifact) -> err {
    if artifacts.len == 0usize { ret InvalidInput }
    let (root_target, root_target_error) = em.artifact_target_index(artifacts[0usize].bytes)
    if root_target_error != ok { ret root_target_error }
    // Each artifact's module name once (D320): the duplicate check read it per pair,
    // and each read validated the artifact's layout.
    let (module_indices, indices_error) = module_index_cache(a, artifacts)
    if indices_error != ok { ret indices_error }
    var at = 0usize
    while at < artifacts.len {
        let (artifact_target, target_error) = em.artifact_target_index(artifacts[at].bytes)
        if target_error != ok { ret target_error }
        if !artifact_strings_equal(artifacts[0usize], root_target, artifacts[at], artifact_target) { ret TargetMismatch }
        var prior = 0usize
        while prior < at {
            if artifact_strings_equal(artifacts[prior], module_indices[prior], artifacts[at], module_indices[at]) { ret DuplicateModule }
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

// The artifacts by module name (D320): a relocation's target module was a walk over
// every artifact, comparing names, per relocation.
fn index_modules(a: *mem.Arena, artifacts: []Artifact, module_indices: []usize, modules: *lookup.Index) -> err {
    let (entries, entries_error) = mem.alloc[lookup.Entry](a, artifacts.len * 8usize + 256usize)
    if entries_error != ok { ret entries_error }
    try lookup.attach(modules, entries)
    var at = 0usize
    while at < artifacts.len {
        let (name, name_error) = artifact_text(a, artifacts[at], module_indices[at])
        if name_error != ok { ret name_error }
        try lookup.insert(modules, 0usize, 0usize, name, at)
        at += 1usize
    }
    ret ok
}

fn target_module(a: *mem.Arena, modules: *lookup.Index, source: Artifact, target_module_index: usize) -> (usize, err) {
    if target_module_index < source.module_of.len && source.module_of[target_module_index] != 0usize { ret (source.module_of[target_module_index] - 1usize, ok) }
    let (name, name_error) = artifact_text(a, source, target_module_index)
    if name_error != ok { ret (0usize, name_error) }
    let (at, found) = lookup.find(modules, 0usize, 0usize, name)
    if !found { ret (0usize, MissingSymbol) }
    ret (at, ok)
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
    // By (module, instance, name) (D320), one index per artifact (D333): a callee names
    // its module, and an index per artifact is built by that artifact's worker alone.
    indexes: []lookup.Index,
}

// The link's workers (D333). The two passes that are per artifact -- reading every
// function's record, name and string bounds into the table, and copying the kept
// functions' code, rows and relocations into the image -- run on up to eight threads,
// each artifact on one, each writing only the table rows, the code range, the
// relocation range and the row range that the sequential passes before it assigned.
// The order of everything in the image is decided sequentially, so the image is the
// one the single-threaded link made.
type LinkWorker = struct {
    arena: mem.Arena,
    artifacts: []Artifact,
    table: *FunctionTable,
    list: []usize,
    count: usize,
    failure: err,
    failed_at: usize,
    phase: usize,
    // The copy pass: what layout decided.
    kept: []bool,
    copies: []bool,
    // Which functions' content hashes the copy verifies (D459): the ones that fold.
    verify: []bool,
    // The reach walk's answer per relocation (D460): the callee's table position, or
    // the table's count for a global, a runtime symbol or an import; and each kept
    // function's index in the program, so a reference is made with its target.
    edge_base: []usize,
    edge_target: []usize,
    global_of: []usize,
    code_offset: []usize,
    reloc_base: []usize,
    row_base: []usize,
    row_start: []usize,
    row_count: []usize,
    program: *Program,
    modules: *lookup.Index,
    references_tmp: []nir.FunctionRef,
    reference_valid: []bool,
    lines_tmp: []codegen_x64.LineEntry,
    hash_scratch: binary.Buffer,
    row_scratch: []em.LineRow,
}

fn link_worker_entry(w: *LinkWorker) {
    var at = 0usize
    while at < w.count {
        var step_error = ok
        if w.phase == 1usize {
            step_error = link_table_artifact(w, w.list[at])
        } else {
            step_error = link_copy_artifact(w, w.list[at])
        }
        if step_error != ok {
            w.failure = step_error
            w.failed_at = w.list[at]
            ret
        }
        at += 1usize
    }
}

// Phase 1, one artifact: its string bounds, its function records, names and index.
fn link_table_artifact(w: *LinkWorker, artifact_at: usize) -> err {
    let bytes = w.artifacts[artifact_at].bytes
    let (starts, lengths, bounds_error) = em.string_table_bounds(&w.arena, bytes)
    if bounds_error != ok { ret bounds_error }
    w.artifacts[artifact_at].string_starts = starts
    w.artifacts[artifact_at].string_lengths = lengths
    let (module_of, module_of_error) = mem.alloc[usize](&w.arena, starts.len + 1usize)
    if module_of_error != ok { ret module_of_error }
    var string_at = 0usize
    while string_at < starts.len {
        module_of[string_at] = 0usize
        string_at += 1usize
    }
    w.artifacts[artifact_at].module_of = module_of[0usize..starts.len]
    let table = w.table
    let position = table.base[artifact_at]
    let end = table.base[artifact_at + 1usize]
    let (count, count_error) = em.read_code_functions(bytes, table.funcs[position..end])
    if count_error != ok { ret count_error }
    if count != end - position { ret InvalidInput }
    let (entries, entries_error) = mem.alloc[lookup.Entry](&w.arena, count * 8usize + 64usize)
    if entries_error != ok { ret entries_error }
    try lookup.attach(&table.indexes[artifact_at], entries)
    var at = 0usize
    while at < count {
        table.owner[position + at] = artifact_at
        let name_index = table.funcs[position + at].name_index
        if name_index >= starts.len { ret InvalidInput }
        let (name, name_error) = copy_string_bytes(&w.arena, bytes, starts[name_index], lengths[name_index])
        if name_error != ok { ret name_error }
        table.names[position + at] = name
        try lookup.insert(&table.indexes[artifact_at], artifact_at, table.funcs[position + at].instance, name, position + at)
        at += 1usize
    }
    ret ok
}

// Phase 2, one artifact: every kept function's content hash checked, and every copied
// one's code into its range, its rows into the artifact's row range, and its
// relocations and references into its relocation range.
fn link_copy_artifact(w: *LinkWorker, artifact_at: usize) -> err {
    let table = w.table
    let artifact = w.artifacts[artifact_at]
    let program = w.program
    var row_cursor = w.row_base[artifact_at]
    let row_end = w.row_base[artifact_at + 1usize]
    var position = table.base[artifact_at]
    let end = table.base[artifact_at + 1usize]
    while position < end {
        if !w.kept[position] {
            position += 1usize
            continue
        }
        let function = table.funcs[position]
        // The content hash is verified where the image depends on it (D459): for a
        // function that folds onto another, or is folded onto, the stored hash is
        // the claim that the two are the same code, and it is recomputed to hold it.
        // A function alone under its hash is copied by its own bytes, which the
        // artifact's checksum already covers, so its hash is not recomputed.
        if w.verify[position] {
            let (content_hash, content_hash_error) = em.code_content_hash_bounded(artifact.bytes, function, artifact.string_starts, artifact.string_lengths, &w.hash_scratch)
            if content_hash_error != ok || content_hash != function.content_hash { ret InvalidInput }
        }
        if !w.copies[position] {
            position += 1usize
            continue
        }
        let code_offset = w.code_offset[position]
        if code_offset + function.code_length > program.machine.count || function.code_start + function.code_length > artifact.bytes.len { ret InvalidInput }
        os.copy_bytes(program.machine.bytes[code_offset..code_offset + function.code_length], artifact.bytes[function.code_start..function.code_start + function.code_length])
        var (row_count, rows_error) = em.read_code_lines(artifact.bytes, position - table.base[artifact_at], w.row_scratch)
        // A function of more rows than the scratch holds (D541): sixteen thousand
        // rows was a function of sixteen thousand lines with code, and the build
        // failed as a table full; the scratch grows to the function, from the worker's arena.
        if rows_error == em.Capacity {
            let (bigger, bigger_error) = mem.alloc[em.LineRow](&w.arena, row_count + 1024usize)
            if bigger_error != ok { ret bigger_error }
            w.row_scratch = bigger
            let (again_count, again_error) = em.read_code_lines(artifact.bytes, position - table.base[artifact_at], w.row_scratch)
            row_count = again_count
            rows_error = again_error
        }
        if rows_error != ok { ret rows_error }
        if row_count > row_end - row_cursor { ret InvalidInput }
        w.row_start[position] = row_cursor
        w.row_count[position] = row_count
        var row_at = 0usize
        while row_at < row_count {
            let (row_path, row_path_error) = artifact_text(&w.arena, artifact, w.row_scratch[row_at].path_index)
            if row_path_error != ok { ret row_path_error }
            var entry: codegen_x64.LineEntry = zero
            entry.offset = code_offset + w.row_scratch[row_at].offset
            entry.line = w.row_scratch[row_at].line
            entry.path = row_path
            w.lines_tmp[row_cursor] = entry
            row_cursor += 1usize
            row_at += 1usize
        }
        let reloc_base = w.reloc_base[position]
        var relocation_at = 0usize
        while relocation_at < function.relocation_count {
            let (stored, stored_error) = em.code_relocation_raw(artifact.bytes, function, relocation_at)
            if stored_error != ok { ret stored_error }
            if stored.module_index >= artifact.string_starts.len || stored.name_index >= artifact.string_starts.len { ret InvalidInput }
            if stored.imported && (stored.library_index >= artifact.string_starts.len || stored.symbol_index >= artifact.string_starts.len) { ret InvalidInput }
            let (module_index, module_error) = target_module(&w.arena, w.modules, artifact, stored.module_index)
            if module_error != ok { ret module_error }
            let (target_name, target_name_error) = artifact_text(&w.arena, artifact, stored.name_index)
            if target_name_error != ok { ret target_name_error }
            let slot = reloc_base + relocation_at
            if stored.global {
                let (global_index, found_global) = find_global(&program.builder, module_index, target_name)
                if !found_global { ret MissingSymbol }
                var global_relocation: codegen_x64.Relocation = zero
                global_relocation.displacement_at = code_offset + stored.displacement_at
                global_relocation.function_ref = global_index
                global_relocation.global = true
                program.relocations[slot] = global_relocation
                relocation_at += 1usize
                continue
            }
            var assembled_reference: nir.FunctionRef = zero
            assembled_reference.module_index = module_index
            assembled_reference.name = target_name
            assembled_reference.instance = stored.instance
            // An `@import` (D319): the reference carries its library and symbol, and
            // the linker resolves it through the image's import table.
            if stored.imported {
                let (library_name, library_error) = artifact_text(&w.arena, artifact, stored.library_index)
                if library_error != ok { ret library_error }
                let (symbol_name, symbol_error) = artifact_text(&w.arena, artifact, stored.symbol_index)
                if symbol_error != ok { ret symbol_error }
                assembled_reference.library = library_name
                assembled_reference.symbol = symbol_name
            }
            let callee = w.edge_target[w.edge_base[position] + relocation_at]
            if callee < table.count {
                assembled_reference.target = w.global_of[callee]
                assembled_reference.has_target = true
            }
            w.references_tmp[slot] = assembled_reference
            w.reference_valid[slot] = true
            var function_relocation: codegen_x64.Relocation = zero
            function_relocation.displacement_at = code_offset + stored.displacement_at
            function_relocation.function_ref = slot
            program.relocations[slot] = function_relocation
            relocation_at += 1usize
        }
        position += 1usize
    }
    ret ok
}

// The artifacts to the workers, the heaviest first to the lightest worker; each
// worker's list is in artifact order.
fn link_assign(a: *mem.Arena, weights: []const usize, worker_count: usize) -> ([]usize, []usize, err) {
    let count = weights.len
    let (order, order_error) = mem.alloc[usize](a, count + 1usize)
    if order_error != ok { ret (order, order, order_error) }
    let (owner, owner_error) = mem.alloc[usize](a, count + 1usize)
    if owner_error != ok { ret (order, owner, owner_error) }
    var at = 0usize
    while at < count {
        order[at] = at
        at += 1usize
    }
    var order_at = 0usize
    while order_at < count {
        var best = order_at
        var scan = order_at + 1usize
        while scan < count {
            if weights[order[scan]] > weights[order[best]] { best = scan }
            scan += 1usize
        }
        let swap = order[order_at]
        order[order_at] = order[best]
        order[best] = swap
        order_at += 1usize
    }
    var loads: [8]usize = zero
    order_at = 0usize
    while order_at < count {
        var lightest = 0usize
        var worker_at = 1usize
        while worker_at < worker_count {
            if loads[worker_at] < loads[lightest] { lightest = worker_at }
            worker_at += 1usize
        }
        loads[lightest] += weights[order[order_at]] + 1024usize
        owner[order[order_at]] = lightest
        order_at += 1usize
    }
    // The lists: worker-major runs of artifact indexes, in artifact order.
    var filled = 0usize
    var worker_at = 0usize
    while worker_at < worker_count {
        at = 0usize
        while at < count {
            if owner[at] == worker_at {
                order[filled] = at
                filled += 1usize
            }
            at += 1usize
        }
        worker_at += 1usize
    }
    ret (order, owner, ok)
}

// A phase on the workers: the lists handed out, the threads run and joined, the
// first failure by artifact order reported.
fn link_run(a: *mem.Arena, workers: []LinkWorker, worker_count: usize, weights: []const usize, phase: usize) -> err {
    let (runs, owner, assign_error) = link_assign(a, weights, worker_count)
    if assign_error != ok { ret assign_error }
    var filled = 0usize
    var worker_at = 0usize
    while worker_at < worker_count {
        var run_count = 0usize
        var at = 0usize
        while at < weights.len {
            if owner[at] == worker_at { run_count += 1usize }
            at += 1usize
        }
        workers[worker_at].list = runs[filled..filled + run_count]
        workers[worker_at].count = run_count
        workers[worker_at].phase = phase
        workers[worker_at].failure = ok
        workers[worker_at].failed_at = weights.len
        filled += run_count
        worker_at += 1usize
    }
    var threads: [8]os.Thread = zero
    var started: [8]bool = zero
    worker_at = 1usize
    while worker_at < worker_count {
        started[worker_at] = false
        let (thread, spawn_error) = os.thread_create[LinkWorker](link_worker_entry, &workers[worker_at], 4194304usize)
        if spawn_error == ok {
            threads[worker_at] = thread
            started[worker_at] = true
        }
        worker_at += 1usize
    }
    link_worker_entry(&workers[0usize])
    worker_at = 1usize
    while worker_at < worker_count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            link_worker_entry(&workers[worker_at])
        }
        worker_at += 1usize
    }
    var failure = ok
    var failed_at = weights.len
    worker_at = 0usize
    while worker_at < worker_count {
        if workers[worker_at].failure != ok && workers[worker_at].failed_at < failed_at {
            failure = workers[worker_at].failure
            failed_at = workers[worker_at].failed_at
        }
        worker_at += 1usize
    }
    ret failure
}

// The table, read on the workers (D333): the counts first, sequentially, so every
// artifact's rows have their place before any is read.
fn build_function_table(a: *mem.Arena, artifacts: []Artifact, function_count: usize, workers: []LinkWorker, worker_count: usize, weights: []const usize) -> (FunctionTable, err) {
    let empty = FunctionTable { funcs: zero, owner: zero, names: zero, base: zero, count: 0usize, indexes: zero }
    let (funcs, funcs_error) = mem.alloc[em.CodeFunction](a, capacity(function_count))
    if funcs_error != ok { ret (empty, funcs_error) }
    let (owner, owner_error) = mem.alloc[usize](a, capacity(function_count))
    if owner_error != ok { ret (empty, owner_error) }
    let (names, names_error) = mem.alloc[str](a, capacity(function_count))
    if names_error != ok { ret (empty, names_error) }
    let (base, base_error) = mem.alloc[usize](a, artifacts.len + 1usize)
    if base_error != ok { ret (empty, base_error) }
    let (indexes, indexes_error) = mem.alloc[lookup.Index](a, artifacts.len + 1usize)
    if indexes_error != ok { ret (empty, indexes_error) }
    var position = 0usize
    var artifact_at = 0usize
    while artifact_at < artifacts.len {
        base[artifact_at] = position
        var blank: lookup.Index = zero
        indexes[artifact_at] = blank
        let (count, count_error) = em.artifact_code_count_light(artifacts[artifact_at].bytes)
        if count_error != ok { ret (empty, count_error) }
        position += count
        artifact_at += 1usize
    }
    if position != function_count { ret (empty, InvalidInput) }
    base[artifacts.len] = position
    var table = FunctionTable { funcs: funcs, owner: owner, names: names, base: base, count: position, indexes: indexes }
    var worker_at = 0usize
    while worker_at < worker_count {
        workers[worker_at].artifacts = artifacts
        workers[worker_at].table = &table
        worker_at += 1usize
    }
    let run_error = link_run(a, workers, worker_count, weights, 1usize)
    if run_error != ok { ret (empty, run_error) }
    ret (table, ok)
}

// Where a function sits in the table: searched within its own module's index, since a callee
// names the module it is in. The keep-set and copy loop index by this position.
fn table_position(table: *FunctionTable, module_index: usize, name: str, instance: usize) -> (usize, bool) {
    if module_index >= table.indexes.len { ret (0usize, false) }
    let (at, found) = lookup.find(&table.indexes[module_index], module_index, instance, name)
    ret (at, found)
}

// Only what `main` reaches is kept, following the calls and taken addresses a relocation records
// -- the same edge set `nir` walks after lowering, so an image linked from artifacts drops the
// same functions from the same sequence as one compiled from source. Over the prebuilt table:
// no artifact is re-read, so a pass is the edges, not the file.
fn reachable_from_main(a: *mem.Arena, artifacts: []Artifact, modules: *lookup.Index, table: *FunctionTable, kept: []bool, edge_base: []usize, edge_target: []usize) -> (bool, err) {
    let total = table.count
    if total > kept.len { ret (false, InvalidInput) }
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
        ret (false, ok)
    }

    // Breadth-first from `main` over the call edges each function records: a function is visited
    // once, and its edges -- the string copy and the module scan a callee needs -- are resolved
    // only then. A module the program never enters is never scanned, which is what a program that
    // pulls in a large module but reaches little of it depends on. A global or a host-runtime
    // symbol is not a function edge and is skipped.
    let (queue, queue_error) = mem.alloc[usize](a, total)
    if queue_error != ok { ret (false, queue_error) }
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
            let (stored, stored_error) = em.code_relocation_raw(artifacts[owner].bytes, function, relocation_at)
            if stored_error != ok { ret (false, stored_error) }
            if stored.module_index >= artifacts[owner].string_starts.len || stored.name_index >= artifacts[owner].string_starts.len { ret (false, InvalidInput) }
            if !stored.global {
                let (module_index, module_error) = target_module(a, modules, artifacts[owner], stored.module_index)
                if module_error != ok { ret (false, module_error) }
                artifacts[owner].module_of[stored.module_index] = module_index + 1usize
                let (callee_name, callee_error) = artifact_text(a, artifacts[owner], stored.name_index)
                if callee_error != ok { ret (false, callee_error) }
                let (callee, found) = table_position(table, module_index, callee_name, stored.instance)
                if found { edge_target[edge_base[position] + relocation_at] = callee }
                if found && !kept[callee] {
                    kept[callee] = true
                    queue[tail] = callee
                    tail += 1usize
                }
            }
            relocation_at += 1usize
        }
    }
    ret (true, ok)
}

fn assemble(a: *mem.Arena, artifacts: []Artifact, program: *Program, jobs: usize) -> err {
    // The workers (D333): as many as the artifacts up to eight, or fewer under `-j`.
    var worker_count = artifacts.len
    if worker_count > 8usize { worker_count = 8usize }
    if jobs != 0usize && jobs < worker_count { worker_count = jobs }
    if worker_count == 0usize { worker_count = 1usize }
    let (workers, workers_error) = mem.alloc[LinkWorker](a, worker_count)
    if workers_error != ok { ret workers_error }
    var function_count = 0usize
    var global_count = 0usize
    var need_total = 0usize
    var need_largest = 0usize
    // What phase 1 allocates per artifact -- its string bounds and its index -- is the
    // weight the artifacts are handed out by, so a worker's arena is bounded by its share.
    let (needs, needs_error) = mem.alloc[usize](a, artifacts.len + 1usize)
    if needs_error != ok { ret needs_error }
    var artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.artifact_code_count_light(artifacts[artifact_at].bytes)
        if count_error != ok { ret count_error }
        function_count += count
        let (globals_here, globals_error) = em.artifact_global_count(artifacts[artifact_at].bytes)
        if globals_error != ok { ret globals_error }
        global_count += globals_here
        let (strings_here, strings_error) = em.string_count(artifacts[artifact_at].bytes)
        if strings_error != ok { ret strings_error }
        needs[artifact_at] = (strings_here + 2usize) * 24usize + (count * 8usize + 64usize) * 64usize + 256usize
        need_total += needs[artifact_at]
        if needs[artifact_at] > need_largest { need_largest = needs[artifact_at] }
        artifact_at += 1usize
    }
    if function_count == 0usize { ret InvalidInput }
    var worker_at = 0usize
    while worker_at < worker_count {
        var blank: LinkWorker = zero
        workers[worker_at] = blank
        let (arena, arena_error) = graph.reserved_arena(a)
        if arena_error != ok { ret arena_error }
        workers[worker_at].arena = arena
        let (row_scratch, row_scratch_error) = mem.alloc[em.LineRow](a, 16384usize)
        if row_scratch_error != ok { ret row_scratch_error }
        workers[worker_at].row_scratch = row_scratch
        worker_at += 1usize
    }

    // Phase 1: every function once into a table the reachability pass and the copy loop both
    // index -- on the workers, each artifact's rows by its own.
    var (table, table_error) = build_function_table(a, artifacts, function_count, workers, worker_count, needs[0usize..artifacts.len])
    if table_error != ok { ret table_error }
    // Every function's relocations in one range (D460): the reach walk resolves each
    // edge once and the copy reads the answer, where it looked the callee up again
    // and `resolve_reference_targets` a third time, by name, over the whole program.
    let (edge_base, edge_base_error) = mem.alloc[usize](a, table.count + 1usize)
    if edge_base_error != ok { ret edge_base_error }
    var edge_total = 0usize
    var edge_at = 0usize
    while edge_at < table.count {
        edge_base[edge_at] = edge_total
        edge_total += table.funcs[edge_at].relocation_count
        edge_at += 1usize
    }
    edge_base[table.count] = edge_total
    let (edge_target, edge_target_error) = mem.alloc[usize](a, edge_total + 1usize)
    if edge_target_error != ok { ret edge_target_error }
    edge_at = 0usize
    while edge_at < edge_total {
        edge_target[edge_at] = table.count
        edge_at += 1usize
    }
    let (global_of, global_of_error) = mem.alloc[usize](a, table.count + 1usize)
    if global_of_error != ok { ret global_of_error }
    try validate_set(a, artifacts)
    // The content hash's input is a function's code and, per relocation, seventeen
    // bytes and two of the artifact's strings (D341): its scratch is sized to the
    // largest such input, where the artifact's own length was taken as the bound
    // and a debug build of one long expression -- a trap site per operator, each a
    // relocation naming the runtime -- outgrew it and failed to link.
    var hash_need = 64usize
    var need_at = 0usize
    while need_at < artifacts.len {
        var longest_string = 0usize
        var string_at = 0usize
        while string_at < artifacts[need_at].string_lengths.len {
            if artifacts[need_at].string_lengths[string_at] > longest_string { longest_string = artifacts[need_at].string_lengths[string_at] }
            string_at += 1usize
        }
        var function_at = table.base[need_at]
        while function_at < table.base[need_at + 1usize] {
            let function = table.funcs[function_at]
            let need = function.code_length + function.relocation_count * (17usize + 2usize * longest_string) + 64usize
            if need > hash_need { hash_need = need }
            function_at += 1usize
        }
        need_at += 1usize
    }
    worker_at = 0usize
    while worker_at < worker_count {
        let (hash_storage, hash_storage_error) = mem.alloc[u8](a, hash_need)
        if hash_storage_error != ok { ret hash_storage_error }
        try binary.init(&workers[worker_at].hash_scratch, hash_storage)
        worker_at += 1usize
    }
    var relocation_count = 0usize
    var code_size = 0usize
    var table_at = 0usize
    // The symbol table's name for each function, `module.function` (D206).
    let (module_name_lengths, lengths_error) = mem.alloc[usize](a, capacity(artifacts.len))
    if lengths_error != ok { ret lengths_error }
    var length_at = 0usize
    while length_at < artifacts.len {
        let (name_index, name_index_error) = em.interface_module_index(artifacts[length_at].bytes)
        if name_index_error != ok { ret name_index_error }
        if name_index >= artifacts[length_at].string_lengths.len { ret InvalidInput }
        module_name_lengths[length_at] = artifacts[length_at].string_lengths[name_index]
        length_at += 1usize
    }
    var names_total = 0usize
    while table_at < table.count {
        let function = table.funcs[table_at]
        code_size += function.code_length
        relocation_count += function.relocation_count
        names_total += table.names[table_at].len + 1usize + module_name_lengths[table.owner[table_at]]
        table_at += 1usize
    }

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
    // The reference index (D303): resolving targets by name over a program's worth of
    // references was a walk of all of them per reference.
    let (reference_entries, reference_entries_error) = mem.alloc[lookup.Entry](a, capacity(relocation_count) * 4usize + 64usize)
    if reference_entries_error != ok { ret reference_entries_error }
    let (string_entries, string_entries_error) = mem.alloc[lookup.Entry](a, 64usize)
    if string_entries_error != ok { ret string_entries_error }
    try nir.attach_indexes(&program.builder, reference_entries, string_entries)
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
            let (name, name_error) = artifact_text(a, artifacts[artifact_at], record.name_index)
            if name_error != ok { ret name_error }
            let (added, add_error) = nir.add_global(&program.builder, artifact_at, name, record.size, record.alignment, record.initial, record.has_initial)
            if add_error != ok { ret add_error }
            global_index += 1usize
        }
        artifact_at += 1usize
    }
    // The code, and room after it for the symbol table the driver appends (D206, D209):
    // a header and a name per function, and sixteen bytes per line row. Each artifact's
    // rows have a range of their own in a staging list (D333), concatenated in order.
    var line_total = 0usize
    let (row_base, row_base_error) = mem.alloc[usize](a, artifacts.len + 1usize)
    if row_base_error != ok { ret row_base_error }
    var line_artifact = 0usize
    while line_artifact < artifacts.len {
        row_base[line_artifact] = line_total
        let (rows, rows_error) = em.artifact_line_row_total(artifacts[line_artifact].bytes)
        if rows_error != ok { ret rows_error }
        line_total += rows
        line_artifact += 1usize
    }
    row_base[artifacts.len] = line_total
    let (machine_storage, machine_error) = mem.alloc[u8](a, capacity(code_size + function_count * 24usize + names_total + line_total * 16usize + 65536usize))
    if machine_error != ok { ret machine_error }
    try emit_x64.init(&program.machine, machine_storage)
    let (function_offsets, offsets_error) = mem.alloc[usize](a, function_count)
    if offsets_error != ok { ret offsets_error }
    program.function_offsets = function_offsets
    let (relocations, relocations_error) = mem.alloc[codegen_x64.Relocation](a, capacity(relocation_count))
    if relocations_error != ok { ret relocations_error }
    program.relocations = relocations
    program.relocation_count = 0usize
    let (lines, lines_error) = mem.alloc[codegen_x64.LineEntry](a, capacity(line_total))
    if lines_error != ok { ret lines_error }
    program.lines = lines
    program.line_count = 0usize
    let (lines_tmp, lines_tmp_error) = mem.alloc[codegen_x64.LineEntry](a, capacity(line_total))
    if lines_tmp_error != ok { ret lines_tmp_error }
    let (references_tmp, references_tmp_error) = mem.alloc[nir.FunctionRef](a, capacity(relocation_count))
    if references_tmp_error != ok { ret references_tmp_error }
    let (reference_valid, reference_valid_error) = mem.alloc[bool](a, capacity(relocation_count))
    if reference_valid_error != ok { ret reference_valid_error }
    // Every module owns its own copy of the generic instances it uses, so the same concrete
    // function arrives from several artifacts, and two distinct functions can compile alike.
    // Either way one copy is shared, keyed by the content hash the artifact carries. The
    // whole-program path folds by the same hash over the same order (D157), so an image linked
    // from artifacts stays byte-identical to one compiled from source (D130).

    // The same rule the source path applies after lowering: keep what `main` reaches and drop the
    // rest. It is done here, before a byte of code is copied, so that both link paths leave out
    // the same functions from the same sequence -- which is what makes an image linked from
    // artifacts identical to one compiled from source.
    let (kept, kept_error) = mem.alloc[bool](a, function_count)
    if kept_error != ok { ret kept_error }
    let (module_indices, module_indices_error) = module_index_cache(a, artifacts)
    if module_indices_error != ok { ret module_indices_error }
    var modules: lookup.Index = zero
    try index_modules(a, artifacts, module_indices, &modules)
    // Each artifact's module name once (D320): it was read and copied per function.
    let (owner_names, owner_names_error) = mem.alloc[str](a, artifacts.len + 1usize)
    if owner_names_error != ok { ret owner_names_error }
    var owner_name_at = 0usize
    while owner_name_at < artifacts.len {
        let (owner_name, owner_name_error) = artifact_text(a, artifacts[owner_name_at], module_indices[owner_name_at])
        if owner_name_error != ok { ret owner_name_error }
        owner_names[owner_name_at] = owner_name
        owner_name_at += 1usize
    }
    // The folded functions by content hash (D320): a scan of every folded hash per
    // function was quadratic in the functions the image keeps.
    let (folded_entries, folded_entries_error) = mem.alloc[lookup.Entry](a, function_count * 8usize + 256usize)
    if folded_entries_error != ok { ret folded_entries_error }
    var folded: lookup.Index = zero
    try lookup.attach(&folded, folded_entries)
    let (rooted, reach_error) = reachable_from_main(a, artifacts, &modules, &table, kept, edge_base, edge_target)
    if reach_error != ok { ret reach_error }
    // The layout (D333), sequential: every kept function in table order gets its place
    // in the builder, its code offset -- or the offset of the copy it folds onto -- and
    // its relocation range, so the copies can be made in any order and land the same.
    let (copies, copies_error) = mem.alloc[bool](a, function_count)
    if copies_error != ok { ret copies_error }
    let (verify, verify_error) = mem.alloc[bool](a, function_count)
    if verify_error != ok { ret verify_error }
    let (code_offset, code_offset_error) = mem.alloc[usize](a, function_count)
    if code_offset_error != ok { ret code_offset_error }
    let (reloc_base, reloc_base_error) = mem.alloc[usize](a, function_count)
    if reloc_base_error != ok { ret reloc_base_error }
    let (row_start, row_start_error) = mem.alloc[usize](a, function_count)
    if row_start_error != ok { ret row_start_error }
    let (row_count, row_count_error) = mem.alloc[usize](a, function_count)
    if row_count_error != ok { ret row_count_error }
    let (copy_weights, copy_weights_error) = mem.alloc[usize](a, artifacts.len + 1usize)
    if copy_weights_error != ok { ret copy_weights_error }
    var weight_at = 0usize
    while weight_at < artifacts.len {
        copy_weights[weight_at] = 0usize
        weight_at += 1usize
    }
    var code_cursor = 0usize
    var reloc_cursor = 0usize
    var position = 0usize
    while position < table.count {
        copies[position] = false
        verify[position] = false
        row_count[position] = 0usize
        if !kept[position] {
            program.unreached_functions += 1usize
            program.unreached_bytes += table.funcs[position].code_length
            position += 1usize
            continue
        }
        let owner_at = table.owner[position]
        let function = table.funcs[position]
        let global_function = program.builder.function_count
        var assembled_function: nir.Function = zero
        assembled_function.name = table.names[position]
        assembled_function.module_index = owner_at
        assembled_function.instance = function.instance
        // The backtrace names a frame `module.function` (D206), and the source path
        // spells the module the same way, which the byte-equality of the two needs.
        assembled_function.module_name = owner_names[owner_at]
        functions[global_function] = assembled_function
        global_of[position] = global_function
        program.builder.function_count += 1usize
        let (folded_position, already_folded) = lookup.find(&folded, function.content_hash, 0usize, "")
        if already_folded {
            program.function_offsets[global_function] = code_offset[folded_position]
            verify[folded_position] = true
            verify[position] = true
            position += 1usize
            continue
        }
        program.function_offsets[global_function] = code_cursor
        try lookup.insert(&folded, function.content_hash, 0usize, "", position)
        copies[position] = true
        code_offset[position] = code_cursor
        code_cursor += function.code_length
        reloc_base[position] = reloc_cursor
        reloc_cursor += function.relocation_count
        copy_weights[owner_at] += function.code_length + function.relocation_count * 64usize
        position += 1usize
    }
    if code_cursor > program.machine.bytes.len || reloc_cursor > relocations.len { ret InvalidInput }
    program.machine.count = code_cursor
    program.relocation_count = reloc_cursor
    var valid_at = 0usize
    while valid_at < reloc_cursor {
        reference_valid[valid_at] = false
        valid_at += 1usize
    }
    // Phase 2: the copies, on the workers.
    worker_at = 0usize
    while worker_at < worker_count {
        workers[worker_at].table = &table
        workers[worker_at].kept = kept
        workers[worker_at].copies = copies
        workers[worker_at].verify = verify
        workers[worker_at].edge_base = edge_base
        workers[worker_at].edge_target = edge_target
        workers[worker_at].global_of = global_of
        workers[worker_at].code_offset = code_offset
        workers[worker_at].reloc_base = reloc_base
        workers[worker_at].row_base = row_base
        workers[worker_at].row_start = row_start
        workers[worker_at].row_count = row_count
        workers[worker_at].program = program
        workers[worker_at].modules = &modules
        workers[worker_at].references_tmp = references_tmp
        workers[worker_at].reference_valid = reference_valid
        workers[worker_at].lines_tmp = lines_tmp
        worker_at += 1usize
    }
    let copy_error = link_run(a, workers, worker_count, copy_weights[0usize..artifacts.len], 2usize)
    if copy_error != ok { ret copy_error }
    worker_at = 0usize
    while worker_at < worker_count {
        program.worker_bytes += graph.arena_touched(&workers[worker_at].arena)
        worker_at += 1usize
    }
    // The references in relocation order, compacted past the globals' empty slots, and
    // the rows in table order: what the one-at-a-time loop appended as it went.
    let (remap, remap_error) = mem.alloc[usize](a, capacity(reloc_cursor))
    if remap_error != ok { ret remap_error }
    var slot = 0usize
    while slot < reloc_cursor {
        if reference_valid[slot] {
            remap[slot] = program.builder.function_ref_count
            references[program.builder.function_ref_count] = references_tmp[slot]
            program.builder.function_ref_count += 1usize
        }
        slot += 1usize
    }
    slot = 0usize
    while slot < reloc_cursor {
        if !program.relocations[slot].global {
            program.relocations[slot].function_ref = remap[program.relocations[slot].function_ref]
        }
        slot += 1usize
    }
    position = 0usize
    while position < table.count {
        if copies[position] {
            var row_at = 0usize
            while row_at < row_count[position] {
                program.lines[program.line_count] = lines_tmp[row_start[position] + row_at]
                program.line_count += 1usize
                row_at += 1usize
            }
        }
        position += 1usize
    }
    // Without a `main` nothing was walked, and the references resolve by name as
    // before, so that the missing entry is the error reported, not a missing callee.
    program.builder.targets_preset = rooted
    try codegen_x64.resolve_calls(&program.builder, program.function_offsets, program.relocations, program.relocation_count, &program.machine)
    var relocation_at = 0usize
    while relocation_at < program.relocation_count {
        if !program.relocations[relocation_at].resolved && !program.relocations[relocation_at].global {
            let reference_index = program.relocations[relocation_at].function_ref
            if reference_index >= program.builder.function_ref_count { ret InvalidInput }
            if !host_runtime_symbol(program.builder.function_refs[reference_index].name) && program.builder.function_refs[reference_index].library.len == 0usize {
                program.missing_symbol = program.builder.function_refs[reference_index].name
                ret MissingSymbol
            }
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
