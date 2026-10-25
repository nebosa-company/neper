// The WebAssembly emitter (spec section 12, D5213, C180): the whole program as one
// `wasm32-wasi` module. It follows spirv.e's shape -- every module lowered into one builder
// and written at once -- and `wasm_code.e` writes the function bodies; this file plans the
// module around them: the functions `main` reaches, the imports they call, the memory the
// globals, strings and trap records take, the shadow stack and the arena after them, and
// the sections that hold it all.
//
// Memory: [0, 4096) stays zero; the used globals follow, then the data (strings and trap
// records), then an 8 MiB shadow stack growing down, then the arena at a page boundary,
// which `neper_mem_alloc` (lib/e/os.wasi.e) grows with `memory.grow` as it fills.
use e.mem
use check
use graph
use nir
use wasm_code as w
use wasm_flow as wf
use wasm_threads as wt

const DATA_START: usize = 4096usize
const STACK_BYTES: usize = 8388608usize
const PAGE_BYTES: usize = 65536usize
const DEFAULT_ARENA: usize = 1073741824usize

fn fail_at(gen: *w.Gen, message: str, name: str) -> err {
    gen.failure = message
    gen.failure_function = name
    ret w.Unsupported
}

// ---- the plan: which functions, which imports --------------------------------------

fn reach_function(gen: *w.Gen, function_index: usize) {
    if gen.reach[function_index] { ret }
    gen.reach[function_index] = true
    gen.order[gen.order_count] = function_index
    gen.position[function_index] = gen.order_count
    gen.order_count += 1usize
}

// A function of the `e.os` variant by name: the runtime the program was lowered without.
fn runtime_function(gen: *w.Gen, name: str) -> (usize, bool) {
    var at = 0usize
    while at < gen.b.function_count {
        let candidate = gen.b.functions[at]
        if candidate.module_index == gen.os_module && candidate.instance == 0usize && w.same(candidate.name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A `neper_*` reference lowering made with the module of whoever made it (the failure
// report's, a trap site's) finds its function in `e.os`.
fn bind_runtime(gen: *w.Gen, reference_index: usize) -> bool {
    let name = gen.b.function_refs[reference_index].name
    if name.len < 6usize || !w.same(name[0usize..6usize], "neper_") { ret false }
    let (found, exists) = runtime_function(gen, name)
    if !exists { ret false }
    gen.b.function_refs[reference_index].target = found
    gen.b.function_refs[reference_index].has_target = true
    ret true
}

// 1 an `i32`, 2 an `i64`, 0 a type an import cannot take.
fn import_class(ty: check.Type) -> usize {
    if ty.kind == .Bool || ty.kind == .Err { ret 1usize }
    if ty.kind != .Integer { ret 0usize }
    if check.integer_width(ty) <= 32usize { ret 1usize }
    ret 2usize
}

fn inline_operation(symbol: str) -> usize {
    if w.same(symbol, "memory.grow") { ret 1usize }
    if w.same(symbol, "memory.size") { ret 2usize }
    if w.same(symbol, "memory.fill") { ret 3usize }
    if w.same(symbol, "memory.copy") { ret 4usize }
    if w.same(symbol, "threads") { ret 5usize }
    if w.same(symbol, "thread.id") { ret 6usize }
    if w.same(symbol, "thread.spawn") { ret 7usize }
    if w.same(symbol, "memory.atomic.wait32") { ret 8usize }
    if w.same(symbol, "memory.atomic.notify") { ret 9usize }
    if w.same(symbol, "i32.atomic.rmw.cmpxchg") { ret 10usize }
    if w.same(symbol, "i32.atomic.load") { ret 11usize }
    if w.same(symbol, "i32.atomic.store") { ret 12usize }
    ret 0usize
}

fn register_import(gen: *w.Gen, reference_index: usize) -> err {
    let reference = gen.b.function_refs[reference_index]
    var at = 0usize
    while at < gen.import_count {
        if w.same(gen.imports[at].library, reference.library) && w.same(gen.imports[at].symbol, reference.symbol) {
            gen.ref_import[reference_index] = at + 1usize
            ret ok
        }
        at += 1usize
    }
    if gen.import_count == gen.imports.len { ret fail_at(gen, "has more imports than the back end holds", reference.symbol) }
    var item: w.Import = zero
    item.library = reference.library
    item.symbol = reference.symbol
    if w.same(reference.library, "wasm") {
        item.inline_op = inline_operation(reference.symbol)
        if item.inline_op == 0usize { ret fail_at(gen, "imports an instruction the \"wasm\" library does not have", reference.symbol) }
    } else {
        if !w.same(reference.library, "wasi_snapshot_preview1") && !w.same(reference.library, "neper_host") { ret fail_at(gen, "imports from a library this target does not have (only wasi_snapshot_preview1, neper_host and \"wasm\")", reference.library) }
    }
    let (declared_at, declared) = check.find_function(gen.c, reference.module_index, reference.name)
    if !declared { ret fail_at(gen, "imports a function the checker does not know", reference.symbol) }
    let declaration = gen.c.functions[declared_at]
    if declaration.parameter_count > 32usize { ret fail_at(gen, "imports a function with too many parameters", reference.symbol) }
    item.param_count = declaration.parameter_count
    var parameter = 0usize
    while parameter < declaration.parameter_count {
        let class = import_class(gen.c.parameters[declaration.first_parameter + parameter].ty)
        if class == 0usize { ret fail_at(gen, "imports a function with a parameter that is not an integer, bool or err", reference.symbol) }
        if class == 1usize { item.mask32 = item.mask32 | (1usize << parameter) }
        parameter += 1usize
    }
    if declaration.return_count > 1usize { ret fail_at(gen, "imports a function with more than one result", reference.symbol) }
    if declaration.return_count == 1usize {
        let result_type = gen.c.return_types[declaration.first_return]
        let class = import_class(result_type)
        if class == 0usize { ret fail_at(gen, "imports a function whose result is not an integer, bool or err", reference.symbol) }
        if class == 2usize {
            item.result_kind = 1usize
        } else {
            item.result_kind = 2usize
            if result_type.kind == .Integer && result_type.name.len != 0usize && result_type.name[0usize] == 105u8 { item.result_kind = 3usize }
        }
    }
    gen.imports[gen.import_count] = item
    gen.import_count += 1usize
    gen.ref_import[reference_index] = gen.import_count
    ret ok
}

fn scan_call(gen: *w.Gen, function: nir.Function, instruction: nir.Instruction) -> err {
    if instruction.immediate >= gen.b.function_ref_count { ret fail_at(gen, "has a call with no function reference", function.name) }
    let reference = gen.b.function_refs[instruction.immediate]
    if reference.library.len != 0usize { ret register_import(gen, instruction.immediate) }
    if !reference.has_target && !bind_runtime(gen, instruction.immediate) { ret fail_at(gen, "calls a function the program does not define", reference.name) }
    reach_function(gen, gen.b.function_refs[instruction.immediate].target)
    ret ok
}

// A function whose address is taken gets a slot of the table from 1 up; slot 0 stays null.
fn scan_address(gen: *w.Gen, function: nir.Function, instruction: nir.Instruction) -> err {
    if instruction.immediate >= gen.b.function_ref_count { ret fail_at(gen, "takes the address of a function with no reference", function.name) }
    let reference = gen.b.function_refs[instruction.immediate]
    if reference.library.len != 0usize { ret fail_at(gen, "takes the address of an import", reference.symbol) }
    if !reference.has_target && !bind_runtime(gen, instruction.immediate) { ret fail_at(gen, "takes the address of a function the program does not define", reference.name) }
    let callee = gen.b.function_refs[instruction.immediate].target
    reach_function(gen, callee)
    if gen.slot_of[callee] == 0usize {
        gen.slot_list[gen.slot_count] = callee
        gen.slot_count += 1usize
        gen.slot_of[callee] = gen.slot_count
    }
    ret ok
}

fn scan_function(gen: *w.Gen, function_index: usize) -> err {
    let function = gen.b.functions[function_index]
    var results = 0usize
    var at = function.first_instruction
    while at < function.first_instruction + function.instruction_count {
        let instruction = gen.b.instructions[at]
        if instruction.opcode == .Call { try scan_call(gen, function, instruction) }
        if instruction.opcode == .FunctionAddress { try scan_address(gen, function, instruction) }
        if instruction.opcode == .GlobalAddress {
            if instruction.immediate >= gen.b.global_count { ret fail_at(gen, "names a global that is not there", function.name) }
            gen.global_used[instruction.immediate] = true
        }
        if instruction.opcode == .Return {
            gen.returns[function_index] = true
            if instruction.operand_count > 2usize { ret fail_at(gen, "returns more than two values", function.name) }
            if instruction.operand_count > results { results = instruction.operand_count }
        }
        at += 1usize
    }
    gen.results[function_index] = u8(results)
    ret ok
}

fn find_main(gen: *w.Gen) -> (usize, bool) {
    var at = 0usize
    while at < gen.b.function_count {
        let candidate = gen.b.functions[at]
        if candidate.module_index == 0usize && candidate.instance == 0usize && w.same(candidate.name, "main") { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// ---- storage -----------------------------------------------------------------------

fn init_gen(a: *mem.Arena, gen: *w.Gen, c: *check.Checker, loaded: *graph.Graph, builder: *nir.Builder) -> err {
    gen.a = a
    gen.c = c
    gen.g = loaded
    gen.b = builder
    let count = builder.function_count + 1usize
    let (reach, reach_error) = mem.alloc[bool](a, count)
    if reach_error != ok { ret reach_error }
    let (position, position_error) = mem.alloc[usize](a, count)
    if position_error != ok { ret position_error }
    let (order, order_error) = mem.alloc[usize](a, count)
    if order_error != ok { ret order_error }
    let (results, results_error) = mem.alloc[u8](a, count)
    if results_error != ok { ret results_error }
    let (returns, returns_error) = mem.alloc[bool](a, count)
    if returns_error != ok { ret returns_error }
    var clear_at = 0usize
    var most_instructions = 0usize
    var most_values = 0usize
    var strings_total = 0usize
    while clear_at < count {
        reach[clear_at] = false
        position[clear_at] = 0usize
        results[clear_at] = 0u8
        returns[clear_at] = false
        if clear_at < builder.function_count {
            let candidate = builder.functions[clear_at]
            if candidate.instruction_count > most_instructions { most_instructions = candidate.instruction_count }
            if candidate.value_count > most_values { most_values = candidate.value_count }
        }
        clear_at += 1usize
    }
    gen.reach = reach
    gen.position = position
    gen.order = order
    gen.results = results
    gen.returns = returns
    let (slot_of, slot_of_error) = mem.alloc[usize](a, count)
    if slot_of_error != ok { ret slot_of_error }
    let (slot_list, slot_list_error) = mem.alloc[usize](a, count)
    if slot_list_error != ok { ret slot_list_error }
    var slot_at = 0usize
    while slot_at < count {
        slot_of[slot_at] = 0usize
        slot_at += 1usize
    }
    gen.slot_of = slot_of
    gen.slot_list = slot_list
    let (imports, imports_error) = mem.alloc[w.Import](a, 1024usize)
    if imports_error != ok { ret imports_error }
    gen.imports = imports
    let (ref_import, ref_import_error) = mem.alloc[usize](a, builder.function_ref_count + 1usize)
    if ref_import_error != ok { ret ref_import_error }
    var ref_at = 0usize
    while ref_at < ref_import.len {
        ref_import[ref_at] = 0usize
        ref_at += 1usize
    }
    gen.ref_import = ref_import
    let (sig_params, sig_params_error) = mem.alloc[usize](a, 4096usize)
    if sig_params_error != ok { ret sig_params_error }
    let (sig_mask, sig_mask_error) = mem.alloc[usize](a, 4096usize)
    if sig_mask_error != ok { ret sig_mask_error }
    let (sig_kind, sig_kind_error) = mem.alloc[usize](a, 4096usize)
    if sig_kind_error != ok { ret sig_kind_error }
    gen.sig_params = sig_params
    gen.sig_mask = sig_mask
    gen.sig_kind = sig_kind
    let (global_address, global_address_error) = mem.alloc[usize](a, builder.global_count + 1usize)
    if global_address_error != ok { ret global_address_error }
    let (global_used, global_used_error) = mem.alloc[bool](a, builder.global_count + 1usize)
    if global_used_error != ok { ret global_used_error }
    var global_at = 0usize
    while global_at < global_used.len {
        global_address[global_at] = 0usize
        global_used[global_at] = false
        global_at += 1usize
    }
    gen.global_address = global_address
    gen.global_used = global_used
    var string_at = 0usize
    while string_at < builder.string_count {
        strings_total += builder.strings[string_at].spelling.len
        string_at += 1usize
    }
    let (string_header, string_header_error) = mem.alloc[usize](a, builder.string_count + 1usize)
    if string_header_error != ok { ret string_header_error }
    string_at = 0usize
    while string_at < string_header.len {
        string_header[string_at] = 0usize
        string_at += 1usize
    }
    gen.string_header = string_header
    let (record_hash, record_hash_error) = mem.alloc[usize](a, 262144usize)
    if record_hash_error != ok { ret record_hash_error }
    let (record_address, record_address_error) = mem.alloc[usize](a, 262144usize)
    if record_address_error != ok { ret record_address_error }
    var record_at = 0usize
    while record_at < record_address.len {
        record_hash[record_at] = 0usize
        record_address[record_at] = 0usize
        record_at += 1usize
    }
    gen.record_hash = record_hash
    gen.record_address = record_address
    let (fr_aux, fr_aux_error) = mem.alloc[usize](a, most_values + 2usize)
    if fr_aux_error != ok { ret fr_aux_error }
    gen.fr_aux = fr_aux
    let (fr_offsets, fr_offsets_error) = mem.alloc[usize](a, most_instructions + 2usize)
    if fr_offsets_error != ok { ret fr_offsets_error }
    gen.fr_offsets = fr_offsets
    try w.init_out(a, &gen.data, 16777216usize + strings_total + builder.instruction_count * 24usize)
    try w.init_out(a, &gen.scratch, 1048576usize)
    try w.init_out(a, &gen.stats, 16384usize)
    try w.init_out(a, &gen.code, most_instructions * 96usize + 65536usize)
    try w.init_out(a, &gen.bodies, builder.instruction_count * 64usize + 1048576usize)
    ret ok
}

fn intern_signature(gen: *w.Gen, params: usize, mask: usize, kind: usize) -> usize {
    ret w.intern_signature(gen, params, mask, kind)
}

fn import_signature(gen: *w.Gen, item: w.Import) -> usize {
    var kind = 0usize
    if item.result_kind == 1usize { kind = 1usize }
    if item.result_kind >= 2usize { kind = 3usize }
    ret intern_signature(gen, item.param_count, item.mask32, kind)
}

fn function_signature(gen: *w.Gen, function_index: usize) -> usize {
    let (parameters, parameters_error) = codegen_parameters(gen, function_index)
    ret intern_signature(gen, parameters, 0usize, usize(gen.results[function_index]))
}

fn codegen_parameters(gen: *w.Gen, function_index: usize) -> (usize, err) {
    let function = gen.b.functions[function_index]
    var count = 0usize
    var at = function.first_instruction
    while at < function.first_instruction + function.instruction_count {
        if gen.b.instructions[at].opcode == .Parameter { count += 1usize }
        at += 1usize
    }
    ret (count, ok)
}

// ---- the plan and the memory -------------------------------------------------------

// Every global a reached function names gets its place in [DATA_START, ...).
fn place_globals(gen: *w.Gen) -> usize {
    var cursor = DATA_START
    var global_at = 0usize
    while global_at < gen.b.global_count {
        if gen.global_used[global_at] {
            var align = gen.b.globals[global_at].alignment
            if align == 0usize { align = 1usize }
            cursor = (cursor + align - 1usize) / align * align
            gen.global_address[global_at] = cursor
            cursor += gen.b.globals[global_at].size
        }
        global_at += 1usize
    }
    let rounded = (cursor + 15usize) / 16usize * 16usize
    ret rounded
}

// ---- sections ----------------------------------------------------------------------

fn put_section(out: *w.Out, id: usize, body: *w.Out) {
    w.put(out, id)
    w.put_uleb(out, body.count)
    w.put_bytes(out, body)
}

fn write_types(gen: *w.Gen, body: *w.Out) {
    w.put_uleb(body, gen.sig_count)
    var at = 0usize
    while at < gen.sig_count {
        w.put(body, 96usize)
        w.put_uleb(body, gen.sig_params[at])
        var parameter = 0usize
        while parameter < gen.sig_params[at] {
            if (gen.sig_mask[at] >> parameter) & 1usize == 1usize { w.put(body, 127usize) } else { w.put(body, 126usize) }
            parameter += 1usize
        }
        let kind = gen.sig_kind[at]
        if kind == 0usize { w.put_uleb(body, 0usize) }
        if kind == 1usize {
            w.put_uleb(body, 1usize)
            w.put(body, 126usize)
        }
        if kind == 2usize {
            w.put_uleb(body, 2usize)
            w.put(body, 126usize)
            w.put(body, 126usize)
        }
        if kind == 3usize {
            w.put_uleb(body, 1usize)
            w.put(body, 127usize)
        }
        at += 1usize
    }
}

fn write_imports(gen: *w.Gen, body: *w.Out, memory_pages: usize) {
    if gen.threads { w.put_uleb(body, gen.wasm_imports + 1usize) } else { w.put_uleb(body, gen.wasm_imports) }
    var at = 0usize
    while at < gen.import_count {
        let item = gen.imports[at]
        if item.inline_op == 0usize {
            w.put_name(body, item.library)
            w.put_name(body, item.symbol)
            w.put(body, 0usize)
            w.put_uleb(body, import_signature(gen, item))
        }
        at += 1usize
    }
    if gen.threads { wt.write_memory_import(body, memory_pages) }
}

// A segment's header: active at `address`, or passive in a threaded module (D5671).
fn put_segment_start(gen: *w.Gen, body: *w.Out, address: usize) {
    if gen.threads {
        w.put(body, 1usize)
        ret
    }
    w.put(body, 0usize)
    w.put(body, 65usize)
    w.put_sleb(body, address)
    w.put(body, 11usize)
}

fn write_data(gen: *w.Gen, body: *w.Out) {
    w.put_uleb(body, wt.segment_count(gen))
    if gen.data.count != 0usize {
        put_segment_start(gen, body, gen.data_base)
        w.put_uleb(body, gen.data.count)
        w.put_bytes(body, &gen.data)
    }
    var global_at = 0usize
    while global_at < gen.b.global_count {
        let item = gen.b.globals[global_at]
        if gen.global_used[global_at] && item.has_initial && item.initial != 0usize {
            var width = item.size
            if width > 8usize { width = 8usize }
            put_segment_start(gen, body, gen.global_address[global_at])
            w.put_uleb(body, width)
            var byte_at = 0usize
            while byte_at < width {
                w.put(body, (item.initial >> (byte_at * 8usize)) & 255usize)
                byte_at += 1usize
            }
        }
        global_at += 1usize
    }
}

// `module.function`, as an engine's trace names it.
fn qualified_name(gen: *w.Gen, function: nir.Function) -> str {
    let owner = gen.g.modules[function.module_index].name
    let (storage, storage_error) = mem.alloc[u8](gen.a, owner.len + 1usize + function.name.len)
    if storage_error != ok { ret function.name }
    var at = 0usize
    while at < owner.len {
        storage[at] = owner[at]
        at += 1usize
    }
    storage[owner.len] = 46u8
    var name_at = 0usize
    while name_at < function.name.len {
        storage[owner.len + 1usize + name_at] = function.name[name_at]
        name_at += 1usize
    }
    ret storage[0usize..storage.len]
}

fn write_names(gen: *w.Gen, body: *w.Out, start_index: usize) {
    var names: w.Out = zero
    let init_error = w.init_out(gen.a, &names, 65536usize + (gen.order_count + gen.import_count) * 512usize)
    if init_error != ok { ret }
    if gen.threads { w.put_uleb(&names, gen.wasm_imports + gen.order_count + 2usize) } else { w.put_uleb(&names, gen.wasm_imports + gen.order_count + 1usize) }
    var at = 0usize
    while at < gen.import_count {
        if gen.imports[at].inline_op == 0usize {
            w.put_uleb(&names, gen.imports[at].wasm_index)
            w.put_name(&names, gen.imports[at].symbol)
        }
        at += 1usize
    }
    var order_at = 0usize
    while order_at < gen.order_count {
        w.put_uleb(&names, gen.wasm_imports + order_at)
        w.put_name(&names, qualified_name(gen, gen.b.functions[gen.order[order_at]]))
        order_at += 1usize
    }
    w.put_uleb(&names, start_index)
    w.put_name(&names, "_start")
    if gen.threads {
        w.put_uleb(&names, start_index + 1usize)
        w.put_name(&names, "wasi_thread_start")
    }
    w.put_name(body, "name")
    w.put(body, 1usize)
    w.put_uleb(body, names.count)
    w.put_bytes(body, &names)
}

// ---- _start --------------------------------------------------------------------------

// The arena cell, the arguments, `main`, and the exit: status 1 when `main` returned
// anything but zero, as `neper_start_main` does (runtime_neperos_a64.s). Its code goes in
// `gen.code` and, sized, at the end of the code section.
fn write_start(gen: *w.Gen, main_index: usize, main_parameters: usize, exit_index: usize, args_index: usize, arena_cell: usize, args_cell: usize, arena_base: usize, arena_cap: usize) {
    gen.code.count = 0usize
    gen.current = gen.b.functions[main_index]
    w.put_uleb(&gen.code, 0usize)
    if gen.threads { wt.write_segment_init(gen) }
    w.i32c(gen, arena_cell)
    w.i64c(gen, arena_base)
    w.op(gen, 55usize)
    w.memarg(gen, 0usize)
    w.i32c(gen, arena_cell)
    w.i64c(gen, arena_cap)
    w.op(gen, 55usize)
    w.memarg(gen, 8usize)
    // Always: it also tells the runtime where the root arena ends (D5640).
    w.i64c(gen, args_cell)
    w.i64c(gen, arena_cell)
    w.op(gen, 16usize)
    w.put_uleb(&gen.code, w.function_wasm_index(gen, args_index))
    if main_parameters >= 1usize { w.i64c(gen, arena_cell) }
    if main_parameters >= 2usize { w.i64c(gen, args_cell) }
    w.op(gen, 16usize)
    w.put_uleb(&gen.code, w.function_wasm_index(gen, main_index))
    if gen.results[main_index] == 0u8 {
        w.i64c(gen, 0usize)
    } else {
        w.i64c(gen, 0usize)
        w.op(gen, 82usize)
        w.extend_unsigned(gen)
    }
    w.op(gen, 16usize)
    w.put_uleb(&gen.code, w.function_wasm_index(gen, exit_index))
    w.op(gen, 11usize)
    w.put_uleb(&gen.bodies, gen.code.count)
    w.put_bytes(&gen.bodies, &gen.code)
}

// ---- the module ----------------------------------------------------------------------

fn emit_all_functions(gen: *w.Gen) -> err {
    var order_at = 0usize
    while order_at < gen.order_count {
        try wf.emit_function(gen, gen.order[order_at])
        order_at += 1usize
    }
    ret ok
}

fn intern_all_signatures(gen: *w.Gen) {
    var import_at = 0usize
    while import_at < gen.import_count {
        if gen.imports[import_at].inline_op == 0usize {
            let imported = import_signature(gen, gen.imports[import_at])
        }
        import_at += 1usize
    }
    var function_at = 0usize
    while function_at < gen.order_count {
        let defined = function_signature(gen, gen.order[function_at])
        function_at += 1usize
    }
}

fn emit_module(gen: *w.Gen, main_index: usize, exit_index: usize, args_index: usize, arena_bytes: usize) -> ([]u8, err) {
    var no_bytes: []u8 = zero
    let (main_parameters, main_error) = codegen_parameters(gen, main_index)
    if main_parameters > 2usize { ret (no_bytes, fail_at(gen, "takes more than the arena and the arguments", "main")) }
    // The numbering: the imports an engine supplies, then the reached functions.
    var at = 0usize
    while at < gen.import_count {
        if gen.imports[at].inline_op == 0usize {
            gen.imports[at].wasm_index = gen.wasm_imports
            gen.wasm_imports += 1usize
        }
        at += 1usize
    }
    let globals_end = place_globals(gen)
    gen.data_base = globals_end
    let functions_error = emit_all_functions(gen)
    if functions_error != ok { ret (no_bytes, functions_error) }
    let arena_cell = w.data_alloc(gen, 32usize, 16usize)
    let args_cell = w.data_alloc(gen, 16usize, 16usize)
    if gen.data.full { ret (no_bytes, fail_at(gen, "the data outgrew the back end's storage", "")) }
    let data_end = gen.data_base + gen.data.count
    let stack_base = (data_end + 15usize) / 16usize * 16usize
    let stack_top = stack_base + STACK_BYTES
    let arena_base = (stack_top + PAGE_BYTES - 1usize) / PAGE_BYTES * PAGE_BYTES
    var arena_cap = DEFAULT_ARENA
    if arena_bytes != 0usize { arena_cap = arena_bytes }
    if arena_base + arena_cap > 4294901760usize { arena_cap = 4294901760usize - arena_base }
    write_start(gen, main_index, main_parameters, exit_index, args_index, arena_cell, args_cell, arena_base, arena_cap)
    if gen.threads { wt.write_thread_start(gen, intern_signature(gen, 1usize, 0usize, 0usize)) }
    if gen.bodies.full { ret (no_bytes, fail_at(gen, "the code outgrew the back end's storage", "")) }
    // Every signature before the first section is written.
    let start_signature = intern_signature(gen, 0usize, 0usize, 0usize)
    var thread_signature = 0usize
    if gen.threads { thread_signature = intern_signature(gen, 2usize, 3usize, 0usize) }
    intern_all_signatures(gen)
    if gen.failure.len != 0usize { ret (no_bytes, w.Unsupported) }
    var out: w.Out = zero
    let out_error = w.init_out(gen.a, &out, gen.bodies.count + gen.data.count + 1048576usize + (gen.order_count + gen.import_count) * 512usize)
    if out_error != ok { ret (no_bytes, out_error) }
    w.put(&out, 0usize)
    w.put(&out, 97usize)
    w.put(&out, 115usize)
    w.put(&out, 109usize)
    w.put(&out, 1usize)
    w.put(&out, 0usize)
    w.put(&out, 0usize)
    w.put(&out, 0usize)
    var section: w.Out = zero
    let section_error = w.init_out(gen.a, &section, gen.bodies.count + gen.data.count + 1048576usize + (gen.order_count + gen.import_count) * 512usize)
    if section_error != ok { ret (no_bytes, section_error) }
    write_types(gen, &section)
    put_section(&out, 1usize, &section)
    section.count = 0usize
    write_imports(gen, &section, arena_base / PAGE_BYTES)
    put_section(&out, 2usize, &section)
    section.count = 0usize
    if gen.threads { w.put_uleb(&section, gen.order_count + 2usize) } else { w.put_uleb(&section, gen.order_count + 1usize) }
    var typed_at = 0usize
    while typed_at < gen.order_count {
        w.put_uleb(&section, function_signature(gen, gen.order[typed_at]))
        typed_at += 1usize
    }
    w.put_uleb(&section, start_signature)
    if gen.threads { w.put_uleb(&section, thread_signature) }
    put_section(&out, 3usize, &section)
    section.count = 0usize
    w.put_uleb(&section, 1usize)
    w.put(&section, 112usize)
    w.put(&section, 0usize)
    w.put_uleb(&section, gen.slot_count + 1usize)
    put_section(&out, 4usize, &section)
    section.count = 0usize
    // A threaded module imports its memory (write_imports), so it defines none.
    if !gen.threads {
        w.put_uleb(&section, 1usize)
        w.put(&section, 0usize)
        w.put_uleb(&section, arena_base / PAGE_BYTES)
        put_section(&out, 5usize, &section)
        section.count = 0usize
    }
    if gen.threads { w.put_uleb(&section, 3usize) } else { w.put_uleb(&section, 2usize) }
    w.put(&section, 126usize)
    w.put(&section, 1usize)
    w.put(&section, 66usize)
    w.put_sleb(&section, stack_top)
    w.put(&section, 11usize)
    // `$floor` is each thread's own in a threaded module, so it is set.
    w.put(&section, 126usize)
    if gen.threads { w.put(&section, 1usize) } else { w.put(&section, 0usize) }
    w.put(&section, 66usize)
    w.put_sleb(&section, stack_base)
    w.put(&section, 11usize)
    if gen.threads {
        // `$tid`, set by wasi_thread_start.
        w.put(&section, 127usize)
        w.put(&section, 1usize)
        w.put(&section, 65usize)
        w.put(&section, 0usize)
        w.put(&section, 11usize)
    }
    put_section(&out, 6usize, &section)
    section.count = 0usize
    let start_index = gen.wasm_imports + gen.order_count
    if gen.threads { w.put_uleb(&section, 3usize) } else { w.put_uleb(&section, 2usize) }
    w.put_name(&section, "memory")
    w.put(&section, 2usize)
    w.put_uleb(&section, 0usize)
    w.put_name(&section, "_start")
    w.put(&section, 0usize)
    w.put_uleb(&section, start_index)
    if gen.threads {
        w.put_name(&section, "wasi_thread_start")
        w.put(&section, 0usize)
        w.put_uleb(&section, start_index + 1usize)
    }
    put_section(&out, 7usize, &section)
    section.count = 0usize
    if gen.slot_count != 0usize {
        w.put_uleb(&section, 1usize)
        w.put(&section, 0usize)
        w.put(&section, 65usize)
        w.put_uleb(&section, 1usize)
        w.put(&section, 11usize)
        w.put_uleb(&section, gen.slot_count)
        var slot_at = 0usize
        while slot_at < gen.slot_count {
            w.put_uleb(&section, w.function_wasm_index(gen, gen.slot_list[slot_at]))
            slot_at += 1usize
        }
        put_section(&out, 9usize, &section)
        section.count = 0usize
    }
    // The data count section (12) comes before the code that uses `memory.init` (D5671).
    if gen.threads {
        w.put_uleb(&section, wt.segment_count(gen))
        put_section(&out, 12usize, &section)
        section.count = 0usize
        w.put_uleb(&section, gen.order_count + 2usize)
    } else {
        w.put_uleb(&section, gen.order_count + 1usize)
    }
    w.put_bytes(&section, &gen.bodies)
    put_section(&out, 10usize, &section)
    section.count = 0usize
    write_data(gen, &section)
    put_section(&out, 11usize, &section)
    section.count = 0usize
    write_names(gen, &section, start_index)
    put_section(&out, 0usize, &section)
    if out.full || section.full { ret (no_bytes, fail_at(gen, "the module outgrew the back end's storage", "")) }
    ret (out.bytes[0usize..out.count], ok)
}

// How the functions were written, for `NEPER_WASM_STATS`: the counts, then the functions that
// kept the dispatch loop and why.
fn describe_flow(a: *mem.Arena, gen: *w.Gen) -> str {
    var text: w.Out = zero
    let init_error = w.init_out(a, &text, gen.stats.count + 512usize)
    if init_error != ok { ret "" }
    w.put_text(&text, "wasm functions ")
    w.put_decimal(&text, gen.order_count)
    w.put_text(&text, ", structured ")
    w.put_decimal(&text, gen.structured_count)
    w.put_text(&text, ", dispatch ")
    w.put_decimal(&text, gen.dispatch_count)
    w.put_text(&text, " (irreducible ")
    w.put_decimal(&text, gen.irreducible_count)
    w.put_text(&text, ")\n")
    w.put_bytes(&text, &gen.stats)
    ret text.bytes[0usize..text.count]
}

// The module for the program lowered into `builder`; `message` says why when it cannot and
// `stats` says how the functions were written (`options` is NEPER_WASM_STATS: any text asks
// for the report, and "dispatch" keeps every function on the dispatch loop, to test it).
fn emit(a: *mem.Arena, c: *check.Checker, loaded: *graph.Graph, builder: *nir.Builder, arena_bytes: usize, message: *str, stats: *str, options: str, threads: bool) -> ([]u8, err) {
    var no_bytes: []u8 = zero
    var gen: w.Gen = zero
    let init_error = init_gen(a, &gen, c, loaded, builder)
    if init_error != ok { ret (no_bytes, init_error) }
    gen.threads = threads
    if threads {
        // `wasi.thread-spawn` is import 0 of every threaded module (D5671); `thread.spawn` calls it.
        var spawn_import: w.Import = zero
        spawn_import.library = "wasi"
        spawn_import.symbol = "thread-spawn"
        spawn_import.param_count = 1usize
        spawn_import.mask32 = 1usize
        spawn_import.result_kind = 3usize
        gen.imports[0usize] = spawn_import
        gen.import_count = 1usize
    }
    let (os_module, has_os) = graph.find_module(loaded, "e.os")
    if !has_os {
        *message = "the program has no e.os, which holds the runtime"
        ret (no_bytes, w.Unsupported)
    }
    gen.os_module = os_module
    gen.force_dispatch = w.same(options, "dispatch")
    nir.resolve_reference_targets(builder)
    let (main_index, has_main) = find_main(&gen)
    let (trap_index, has_trap) = runtime_function(&gen, "neper_trap")
    let (exit_index, has_exit) = runtime_function(&gen, "neper_os_exit")
    let (args_index, has_args) = runtime_function(&gen, "neper_start_args")
    if !has_main || !has_trap || !has_exit || !has_args {
        *message = "the program has no main, or its e.os variant lacks neper_trap, neper_os_exit or neper_start_args"
        ret (no_bytes, w.Unsupported)
    }
    gen.trap_function = trap_index
    reach_function(&gen, main_index)
    reach_function(&gen, trap_index)
    reach_function(&gen, exit_index)
    reach_function(&gen, args_index)
    var scan = 0usize
    var plan_error = ok
    while scan < gen.order_count && plan_error == ok {
        plan_error = scan_function(&gen, gen.order[scan])
        scan += 1usize
    }
    var emitted: []u8 = zero
    var module_error = plan_error
    if plan_error == ok { (emitted, module_error) = emit_module(&gen, main_index, exit_index, args_index, arena_bytes) }
    if module_error != ok {
        *message = describe(a, &gen)
        ret (no_bytes, module_error)
    }
    *stats = describe_flow(a, &gen)
    ret (emitted, ok)
}

// `function: reason`, for the command's diagnostic.
fn describe(a: *mem.Arena, gen: *w.Gen) -> str {
    if gen.failure.len == 0usize { ret "the module cannot be written as WebAssembly" }
    var text: w.Out = zero
    let init_error = w.init_out(a, &text, 4096usize)
    if init_error != ok { ret gen.failure }
    if gen.failure_function.len != 0usize {
        w.put_text(&text, gen.failure_function)
        w.put_text(&text, ": ")
    }
    w.put_text(&text, gen.failure)
    if gen.failure_opcode != 0usize {
        w.put_text(&text, " (opcode ")
        w.put_decimal(&text, gen.failure_opcode)
        w.put_text(&text, ", ")
        w.put_text(&text, gen.failure_path)
        w.put_text(&text, ":")
        w.put_decimal(&text, gen.failure_line)
        w.put_text(&text, ")")
    }
    ret text.bytes[0usize..text.count]
}
