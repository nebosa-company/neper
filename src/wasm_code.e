// The WebAssembly back end's function bodies (spec section 12, D5213, C180): NIR written
// as WebAssembly instructions, one function at a time, in the order codegen_a64 selects
// them. `wasm.e` plans the module (which functions, imports and globals), lays its memory
// and writes the sections around the bodies made here.
//
// Every NIR value is an `i64` local, whatever its type: an integer is kept sign- or
// zero-extended to 64 bits as codegen_a64 keeps it in a register, so the checks and the
// traps below are that file's, instruction for instruction. A float is its bit pattern in
// the same way (its arithmetic is C181); a pointer is an `i64` that every memory access
// wraps to `i32`. A function takes one `i64` parameter per NIR `Parameter` and returns
// the 0, 1 or 2 values its `Return` carries; only an import has `i32` parameters (D5600).
//
// Control flow is a dispatch loop (D5213): `loop` around N nested `block`s and a
// `br_table` on `$bb`, the code of NIR block i following the end of block i. A branch to
// the next block is a fall-through; any other sets `$bb` and branches to the loop.
use e.mem
use check
use graph
use nir
use codegen_x64
use emit_x64
use em

error Unsupported

type Out = struct { bytes: []u8, count: usize, full: bool }

// An import (a WASI function) or one of the pseudo-library "wasm"'s instructions, which
// are written inline (`inline_op`: 1 memory.grow, 2 memory.size, 3 memory.fill, 4 memory.copy,
// and D5672's threads: 5 threads, 6 thread.id, 7 thread.spawn, 8 memory.atomic.wait32,
// 9 memory.atomic.notify, 10 i32.atomic.rmw.cmpxchg, 11 i32.atomic.load, 12 i32.atomic.store).
// `mask32` marks the parameters that are `i32`; `result_kind` is 0 none, 1 `i64`, 2 an
// unsigned `i32` and 3 a signed one.
type Import = struct {
    library: str,
    symbol: str,
    param_count: usize,
    mask32: usize,
    result_kind: usize,
    inline_op: usize,
    wasm_index: usize,
}

type Gen = struct {
    a: *mem.Arena,
    c: *check.Checker,
    g: *graph.Graph,
    b: *nir.Builder,
    failure: str,
    failure_function: str,
    failure_opcode: usize,
    failure_line: usize,
    failure_path: str,
    os_module: usize,
    reach: []bool,
    position: []usize,
    order: []usize,
    order_count: usize,
    results: []u8,
    returns: []bool,
    imports: []Import,
    import_count: usize,
    wasm_imports: usize,
    ref_import: []usize,
    sig_params: []usize,
    sig_mask: []usize,
    sig_kind: []usize,
    sig_count: usize,
    slot_of: []usize,
    slot_list: []usize,
    slot_count: usize,
    trap_function: usize,
    data: Out,
    data_base: usize,
    string_header: []usize,
    global_address: []usize,
    global_used: []bool,
    record_hash: []usize,
    record_address: []usize,
    record_count: usize,
    scratch: Out,
    bodies: Out,
    code: Out,
    current: nir.Function,
    fr_params: usize,
    // The value locals: `fr_slot` maps a NIR value to its slot among `fr_slots` of them
    // (values that live inside one block share slots), `fr_uses` and `fr_user` say how
    // often and by which instruction a value is read, and `fr_fold` marks a value planned
    // to stay on the operand stack from its definition to its single user (C183).
    fr_slots: usize,
    fr_slot: []usize,
    fr_uses: []usize,
    fr_user: []usize,
    fr_fold: []usize,
    pl_def_block: []usize,
    pl_def_pos: []usize,
    pl_last_use: []usize,
    pl_cross: []usize,
    pl_on_stack: []usize,
    pl_free: []usize,
    pl_vstack: []usize,
    // The values on the operand stack now (bottom first) and, for the instruction being
    // written, which of them it reads and in what order; `pend` is by slot: value + 1.
    fold_stack: []usize,
    fold_count: usize,
    fold_start: usize,
    fold_next: usize,
    fold_end: usize,
    fold_bad: bool,
    pend: []usize,
    watch_on: bool,
    watch_slot: usize,
    watch_sets: usize,
    watch_gets: usize,
    last_set_pos: usize,
    last_set_slot: usize,
    force_dispatch: bool,
    structured_count: usize,
    dispatch_count: usize,
    irreducible_count: usize,
    stats: Out,
    fr_aux: []usize,
    fr_aux_count: usize,
    fr_offsets: []usize,
    fr_frame: usize,
    fr_blocks: usize,
    fr_block: usize,
    fr_vec: bool,
    // `--threads` (D5671): the module shape of wasm_threads.e and the atomics of D5672.
    threads: bool,
    // `--source-map` (C196, D5683): an entry per change of source line, offsets relative to
    // `bodies` once the function is finished; `map_done` entries are finished.
    map_on: bool,
    map_name: str,
    map_offset: []usize,
    map_line: []usize,
    map_column: []usize,
    map_source: []usize,
    map_count: usize,
    map_done: usize,
    map_paths: []str,
    map_path_count: usize,
    map_full: bool,
    map_text: []u8,
}

// ---- bytes ---------------------------------------------------------------------

fn init_out(a: *mem.Arena, o: *Out, capacity: usize) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, capacity)
    if storage_error != ok { ret storage_error }
    o.bytes = storage
    o.count = 0usize
    o.full = false
    ret ok
}

fn put(o: *Out, value: usize) {
    if o.count >= o.bytes.len {
        o.full = true
        ret
    }
    o.bytes[o.count] = u8(value & 255usize)
    o.count += 1usize
}

fn put_uleb(o: *Out, value: usize) {
    var rest = value
    var more = true
    while more {
        let low = rest & 127usize
        rest = rest >> 7usize
        if rest == 0usize {
            put(o, low)
            more = false
        } else {
            put(o, low + 128usize)
        }
    }
}

// The 64 bits of `value` read as a signed number.
fn put_sleb(o: *Out, value: usize) {
    var rest = value
    let negative = (value >> 63usize) == 1usize
    var more = true
    while more {
        let low = rest & 127usize
        rest = rest >> 7usize
        if negative { rest = rest | 18302628885633695744usize }
        let sign_bit = low & 64usize
        if (rest == 0usize && sign_bit == 0usize) || (rest == 18446744073709551615usize && sign_bit != 0usize) {
            put(o, low)
            more = false
        } else {
            put(o, low + 128usize)
        }
    }
}

fn put_text(o: *Out, text: str) {
    var at = 0usize
    while at < text.len {
        put(o, usize(text[at]))
        at += 1usize
    }
}

fn put_name(o: *Out, text: str) {
    put_uleb(o, text.len)
    put_text(o, text)
}

fn put_bytes(o: *Out, from: *Out) {
    var at = 0usize
    while at < from.count {
        put(o, usize(from.bytes[at]))
        at += 1usize
    }
}

fn same(left: str, right: str) -> bool { ret check.same(left, right) }

// The index of the signature with these parameters and results (`kind`: 0 none, 1 one
// `i64`, 2 two, 3 one `i32`); the type section is written after every body.
fn intern_signature(gen: *Gen, params: usize, mask: usize, kind: usize) -> usize {
    var at = 0usize
    while at < gen.sig_count {
        if gen.sig_params[at] == params && gen.sig_mask[at] == mask && gen.sig_kind[at] == kind { ret at }
        at += 1usize
    }
    if gen.sig_count == gen.sig_params.len {
        gen.failure = "the module has more signatures than the back end holds"
        ret 0usize
    }
    gen.sig_params[gen.sig_count] = params
    gen.sig_mask[gen.sig_count] = mask
    gen.sig_kind[gen.sig_count] = kind
    gen.sig_count += 1usize
    ret gen.sig_count - 1usize
}

fn fail(g: *Gen, message: str) -> err {
    g.failure = message
    g.failure_function = g.current.name
    ret Unsupported
}

// ---- the function being written ------------------------------------------------

fn local_bb(g: *Gen) -> usize { ret g.fr_params }

fn local_fp(g: *Gen) -> usize { ret g.fr_params + 1usize }

fn local_s(g: *Gen, k: usize) -> usize { ret g.fr_params + 2usize + k }

fn local_value(g: *Gen, value: usize) -> usize { ret g.fr_params + 6usize + g.fr_slot[value] }

fn local_aux(g: *Gen, value: usize) -> usize { ret g.fr_params + 6usize + g.fr_slots + g.fr_aux[value] - 1usize }

fn function_wasm_index(g: *Gen, function_index: usize) -> usize { ret g.wasm_imports + g.position[function_index] }

fn operand(g: *Gen, instruction: nir.Instruction, k: usize) -> usize { ret g.b.operands[instruction.first_operand + k] }

fn value_ty(g: *Gen, value: usize) -> check.Type {
    let (ty, ty_error) = codegen_x64.value_type(g.b, g.current, value)
    if ty_error != ok { ret check.invalid_type() }
    ret ty
}

fn op(g: *Gen, code: usize) { put(&g.code, code) }

// A read of a value that is waiting on the operand stack is that value in place, as long as
// it is the next one the instruction in hand reads and nothing has been written for the
// instruction yet (`emit_folded` checks that it was, and writes the instruction again with
// fewer folded values when it was not).
fn lget(g: *Gen, index: usize) {
    if g.watch_on && g.watch_slot == index { g.watch_gets += 1usize }
    let first = g.fr_params + 6usize
    if g.fold_count != 0usize && index >= first && index < first + g.fr_slots {
        let waiting = g.pend[index - first]
        if waiting != 0usize {
            if g.fold_next < g.fold_end && g.fold_stack[g.fold_next] == waiting - 1usize && g.code.count == g.fold_start {
                g.fold_next += 1usize
                ret
            }
            g.fold_bad = true
        }
    }
    put(&g.code, 32usize)
    put_uleb(&g.code, index)
}

fn lset(g: *Gen, index: usize) {
    if g.watch_on && g.watch_slot == index { g.watch_sets += 1usize }
    g.last_set_pos = g.code.count
    g.last_set_slot = index
    put(&g.code, 33usize)
    put_uleb(&g.code, index)
}

fn vget(g: *Gen, value: usize) { lget(g, local_value(g, value)) }

fn vset(g: *Gen, value: usize) { lset(g, local_value(g, value)) }

fn i64c(g: *Gen, value: usize) {
    put(&g.code, 66usize)
    put_sleb(&g.code, value)
}

fn i32c(g: *Gen, value: usize) {
    var low = value & 4294967295usize
    if low >= 2147483648usize { low = low | 18446744069414584320usize }
    put(&g.code, 65usize)
    put_sleb(&g.code, low)
}

// `i32.wrap_i64`: a pointer or a count on its way into memory.
fn wrap(g: *Gen) { op(g, 167usize) }

fn extend_unsigned(g: *Gen) { op(g, 173usize) }

fn extend_signed(g: *Gen) { op(g, 172usize) }

fn block_if(g: *Gen) {
    op(g, 4usize)
    op(g, 64usize)
}

fn block_end(g: *Gen) { op(g, 11usize) }

// A memory instruction's immediates: no alignment promise, the byte offset.
fn memarg(g: *Gen, offset: usize) {
    put(&g.code, 0usize)
    put_uleb(&g.code, offset)
}

// Bring the 64-bit value on the stack back to what a value of this width and sign holds.
fn normalize_bits(g: *Gen, width: usize, signed: bool) {
    if width >= 64usize { ret }
    if signed {
        if width == 8usize { op(g, 194usize) }
        if width == 16usize { op(g, 195usize) }
        if width == 32usize { op(g, 196usize) }
        ret
    }
    if width == 8usize { i64c(g, 255usize) }
    if width == 16usize { i64c(g, 65535usize) }
    if width == 32usize { i64c(g, 4294967295usize) }
    op(g, 131usize)
}

fn normalize_type(g: *Gen, ty: check.Type) {
    if ty.kind != .Integer { ret }
    normalize_bits(g, codegen_x64.integer_width(ty), codegen_x64.signed_integer(ty))
}

// ---- the module's data ---------------------------------------------------------

// `size` zeroed bytes at the next multiple of `align`; the address, or zero when full.
fn data_alloc(g: *Gen, size: usize, align: usize) -> usize {
    let start = (g.data.count + align - 1usize) / align * align
    if start + size > g.data.bytes.len {
        g.data.full = true
        ret 0usize
    }
    var at = g.data.count
    while at < start + size {
        g.data.bytes[at] = 0u8
        at += 1usize
    }
    g.data.count = start + size
    ret g.data_base + start
}

fn data_set64(g: *Gen, address: usize, value: usize) {
    var at = 0usize
    while at < 8usize {
        g.data.bytes[address - g.data_base + at] = u8((value >> (at * 8usize)) & 255usize)
        at += 1usize
    }
}

fn data_get64(g: *Gen, address: usize) -> usize {
    var value = 0usize
    var at = 0usize
    while at < 8usize {
        value = value | (usize(g.data.bytes[address - g.data_base + at]) << (at * 8usize))
        at += 1usize
    }
    ret value
}

// The 16-byte `{pointer, length}` header of these bytes, laid with the bytes after it, or
// the earlier one with the same bytes. A string constant and a trap record are both this.
fn intern_bytes(g: *Gen, bytes: []const u8) -> usize {
    var hash = 14695981039346656037usize
    var at = 0usize
    while at < bytes.len {
        hash = (hash ^ usize(bytes[at])) *% 1099511628211usize
        at += 1usize
    }
    let mask = g.record_hash.len - 1usize
    var slot = hash & mask
    while g.record_address[slot] != 0usize {
        let header = g.record_address[slot]
        if g.record_hash[slot] == hash && data_get64(g, header + 8usize) == bytes.len {
            var index = 0usize
            while index < bytes.len && g.data.bytes[header + 16usize - g.data_base + index] == bytes[index] { index += 1usize }
            if index == bytes.len { ret header }
        }
        slot = (slot + 1usize) & mask
    }
    if g.record_count * 2usize >= g.record_hash.len {
        g.data.full = true
        ret 0usize
    }
    let created = data_alloc(g, 16usize + bytes.len, 16usize)
    if created == 0usize { ret 0usize }
    data_set64(g, created, created + 16usize)
    data_set64(g, created + 8usize, bytes.len)
    var copy_at = 0usize
    while copy_at < bytes.len {
        g.data.bytes[created + 16usize - g.data_base + copy_at] = bytes[copy_at]
        copy_at += 1usize
    }
    g.record_hash[slot] = hash
    g.record_address[slot] = created
    g.record_count += 1usize
    ret created
}

fn string_address(g: *Gen, index: usize) -> usize {
    if g.string_header[index] != 0usize { ret g.string_header[index] }
    let mark = mem.mark(g.a)
    let spelling = g.b.strings[index].spelling
    let (storage, storage_error) = mem.alloc[u8](g.a, spelling.len + 1usize)
    if storage_error != ok {
        g.data.full = true
        ret 0usize
    }
    var buffer: emit_x64.Buffer = zero
    let init_error = emit_x64.init(&buffer, storage)
    let (length, decode_error) = codegen_x64.emit_string_bytes(&buffer, spelling)
    if init_error != ok || decode_error != ok {
        g.failure = "a string constant is not valid text"
        g.data.full = true
        ret 0usize
    }
    let header = intern_bytes(g, buffer.bytes[0usize..buffer.count])
    mem.reset(g.a, mark)
    g.string_header[index] = header
    ret header
}

// ---- traps ---------------------------------------------------------------------

// Section 11's trap protocol on this target: `neper_trap(path, line << 16 | column, a, b,
// message)`, the path and the message being records (a `{pointer, length}` header over the
// text, with an operand's separator byte where one belongs) that the runtime prints.
fn trap_call(g: *Gen, site: nir.Site, token_path: str, kind: str, first: str, second: str, third: str, values: usize, signed: bool, a_local: usize, b_local: usize, tail: str) {
    var path_pieces: [1]codegen_x64.TrapPiece = zero
    var message: [9]codegen_x64.TrapPiece = zero
    let count = codegen_x64.trap_pieces(g.current, token_path, kind, first, second, third, values, signed, tail, path_pieces[..], message[..])
    let path_header = piece_record(g, path_pieces[0usize..1usize])
    let message_header = piece_record(g, message[0usize..count])
    var column = site.column
    if column > 65535usize { column = 65535usize }
    i64c(g, path_header)
    i64c(g, site.line * 65536usize + column)
    if values >= 1usize { lget(g, a_local) } else { i64c(g, 0usize) }
    if values >= 2usize { lget(g, b_local) } else { i64c(g, 0usize) }
    i64c(g, message_header)
    op(g, 16usize)
    put_uleb(&g.code, function_wasm_index(g, g.trap_function))
    op(g, 0usize)
}

fn piece_record(g: *Gen, pieces: []const codegen_x64.TrapPiece) -> usize {
    g.scratch.count = 0usize
    var at = 0usize
    while at < pieces.len {
        if pieces[at].is_single {
            put(&g.scratch, pieces[at].single)
        } else {
            put_text(&g.scratch, pieces[at].text)
        }
        at += 1usize
    }
    ret intern_bytes(g, g.scratch.bytes[0usize..g.scratch.count])
}

// The trap runs when the `i32` on the stack is not zero.
fn trap_if(g: *Gen, site: nir.Site, token_path: str, kind: str, first: str, second: str, third: str, values: usize, signed: bool, a_local: usize, b_local: usize, tail: str) {
    block_if(g)
    trap_call(g, site, token_path, kind, first, second, third, values, signed, a_local, b_local, tail)
    block_end(g)
}

fn overflow_if(g: *Gen, instruction: nir.Instruction, operator: str) {
    trap_if(g, instruction.site, instruction.path, "overflow", instruction.ty.name, "", "", 0usize, false, 0usize, 0usize, operator)
}

// The `overflow` row below 64 bits: the exact 64-bit result has to be its own normalisation.
fn fits_check(g: *Gen, instruction: nir.Instruction, operator: str) {
    vget(g, instruction.result)
    normalize_type(g, instruction.ty)
    vget(g, instruction.result)
    op(g, 82usize)
    overflow_if(g, instruction, operator)
}

// ---- integer operations --------------------------------------------------------

fn comparison_opcode(opcode: nir.Opcode, unsigned: bool) -> usize {
    if opcode == .Equal { ret 81usize }
    if opcode == .NotEqual { ret 82usize }
    if opcode == .Less {
        if unsigned { ret 84usize }
        ret 83usize
    }
    if opcode == .Greater {
        if unsigned { ret 86usize }
        ret 85usize
    }
    if opcode == .LessEqual {
        if unsigned { ret 88usize }
        ret 87usize
    }
    if unsigned { ret 90usize }
    ret 89usize
}

fn emit_comparison(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 2usize || !instruction.has_result { ret fail(g, "a comparison with the wrong operands") }
    let left = operand(g, instruction, 0usize)
    let operand_type = value_ty(g, left)
    let unsigned = operand_type.kind == .Integer && operand_type.name.len > 0usize && operand_type.name[0usize] == 117u8
    vget(g, left)
    vget(g, operand(g, instruction, 1usize))
    op(g, comparison_opcode(instruction.opcode, unsigned))
    extend_unsigned(g)
    vset(g, instruction.result)
    ret ok
}

// Checked `+ - *` at 64 bits, which WebAssembly has no flags for (D5213).
fn emit_wide_checked(g: *Gen, instruction: nir.Instruction, left: usize, right: usize, signed: bool, operator: str) {
    let result = instruction.result
    vget(g, left)
    vget(g, right)
    if instruction.opcode == .Add { op(g, 124usize) }
    if instruction.opcode == .Subtract { op(g, 125usize) }
    if instruction.opcode == .Multiply { op(g, 126usize) }
    vset(g, result)
    if instruction.opcode == .Add {
        if signed {
            vget(g, left)
            vget(g, result)
            op(g, 133usize)
            vget(g, right)
            vget(g, result)
            op(g, 133usize)
            op(g, 131usize)
            i64c(g, 0usize)
            op(g, 83usize)
        } else {
            vget(g, result)
            vget(g, left)
            op(g, 84usize)
        }
        overflow_if(g, instruction, operator)
        ret
    }
    if instruction.opcode == .Subtract {
        if signed {
            vget(g, left)
            vget(g, right)
            op(g, 133usize)
            vget(g, left)
            vget(g, result)
            op(g, 133usize)
            op(g, 131usize)
            i64c(g, 0usize)
            op(g, 83usize)
        } else {
            vget(g, left)
            vget(g, right)
            op(g, 84usize)
        }
        overflow_if(g, instruction, operator)
        ret
    }
    // A product overflowed when a is not zero and dividing the result by it does not give
    // b back; the signed division is not asked for -1, whose quotient can itself overflow.
    vget(g, left)
    op(g, 80usize)
    op(g, 69usize)
    block_if(g)
    if signed {
        vget(g, left)
        i64c(g, 18446744073709551615usize)
        op(g, 81usize)
        block_if(g)
        vget(g, right)
        i64c(g, 9223372036854775808usize)
        op(g, 81usize)
        overflow_if(g, instruction, operator)
        op(g, 5usize)
        vget(g, result)
        vget(g, left)
        op(g, 127usize)
        vget(g, right)
        op(g, 82usize)
        overflow_if(g, instruction, operator)
        block_end(g)
    } else {
        vget(g, result)
        vget(g, left)
        op(g, 128usize)
        vget(g, right)
        op(g, 82usize)
        overflow_if(g, instruction, operator)
    }
    block_end(g)
}

fn emit_arithmetic(g: *Gen, instruction: nir.Instruction) -> err {
    let opcode = instruction.opcode
    let bitwise = opcode == .BitAnd || opcode == .BitOr || opcode == .BitXor || (instruction.ty.kind == .Pointer && (opcode == .Add || opcode == .Subtract))
    if instruction.operand_count != 2usize || !instruction.has_result || (instruction.ty.kind != .Integer && !bitwise) { ret fail(g, "arithmetic on a type this target does not have yet") }
    let left = operand(g, instruction, 0usize)
    let right = operand(g, instruction, 1usize)
    let width = codegen_x64.integer_width(instruction.ty)
    let signed = codegen_x64.signed_integer(instruction.ty)
    let checked = instruction.ty.kind == .Integer && !instruction.nocheck && !g.b.release && (opcode == .Add || opcode == .Subtract || opcode == .Multiply)
    var operator = " + overflows"
    if opcode == .Subtract { operator = " - overflows" }
    if opcode == .Multiply { operator = " * overflows" }
    if checked && width == 64usize {
        emit_wide_checked(g, instruction, left, right, signed, operator)
        ret ok
    }
    vget(g, left)
    vget(g, right)
    if opcode == .Add || opcode == .AddWrap { op(g, 124usize) }
    if opcode == .Subtract || opcode == .SubtractWrap { op(g, 125usize) }
    if opcode == .Multiply || opcode == .MultiplyWrap { op(g, 126usize) }
    if opcode == .BitAnd { op(g, 131usize) }
    if opcode == .BitOr { op(g, 132usize) }
    if opcode == .BitXor { op(g, 133usize) }
    if checked {
        vset(g, instruction.result)
        fits_check(g, instruction, operator)
        ret ok
    }
    if opcode != .BitAnd && opcode != .BitOr && opcode != .BitXor { normalize_type(g, instruction.ty) }
    vset(g, instruction.result)
    ret ok
}

fn emit_shift(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret fail(g, "a shift of a type this target does not have yet") }
    let left = operand(g, instruction, 0usize)
    let count = operand(g, instruction, 1usize)
    let left_type = value_ty(g, left)
    if left_type.kind != .Integer { ret fail(g, "a shift of a type this target does not have yet") }
    let width = codegen_x64.integer_width(left_type)
    if !instruction.nocheck && !g.b.release {
        i64c(g, width)
        lset(g, local_s(g, 0usize))
        vget(g, count)
        lget(g, local_s(g, 0usize))
        op(g, 90usize)
        trap_if(g, instruction.site, instruction.path, "shift", "shift by ", " on a width of ", "", 2usize, false, local_value(g, count), local_s(g, 0usize), "")
    }
    vget(g, left)
    vget(g, count)
    i64c(g, width - 1usize)
    op(g, 131usize)
    if instruction.opcode == .ShiftLeft {
        op(g, 134usize)
    } else {
        if codegen_x64.signed_integer(left_type) { op(g, 135usize) } else { op(g, 136usize) }
    }
    normalize_type(g, instruction.ty)
    vset(g, instruction.result)
    ret ok
}

// Section 11's `divide` rows trap in every mode: a zero divisor, and the one division two's
// complement cannot represent.
fn emit_divide(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 2usize || instruction.ty.kind != .Integer { ret fail(g, "a division of a type this target does not have yet") }
    let left = operand(g, instruction, 0usize)
    let right = operand(g, instruction, 1usize)
    let left_type = value_ty(g, left)
    if left_type.kind != .Integer { ret fail(g, "a division of a type this target does not have yet") }
    let signed = codegen_x64.signed_integer(left_type)
    let width = codegen_x64.integer_width(left_type)
    let remainder = instruction.opcode == .Remainder
    var operator = " / "
    if remainder { operator = " % " }
    vget(g, right)
    op(g, 80usize)
    trap_if(g, instruction.site, instruction.path, "divide", "", operator, " divides by zero", 2usize, signed, local_value(g, left), local_value(g, right), "")
    if signed {
        let all_ones = 0usize -% 1usize
        vget(g, right)
        i64c(g, all_ones)
        op(g, 81usize)
        vget(g, left)
        i64c(g, all_ones - (all_ones >> (65usize - width)))
        op(g, 81usize)
        op(g, 113usize)
        trap_if(g, instruction.site, instruction.path, "divide", "", operator, " overflows", 2usize, true, local_value(g, left), local_value(g, right), "")
    }
    vget(g, left)
    vget(g, right)
    if signed {
        if remainder { op(g, 129usize) } else { op(g, 127usize) }
    } else {
        if remainder { op(g, 130usize) } else { op(g, 128usize) }
    }
    normalize_type(g, instruction.ty)
    vset(g, instruction.result)
    ret ok
}

// Cast, unary minus and `~` on integers.
fn emit_cast(g: *Gen, instruction: nir.Instruction) -> err {
    let value = operand(g, instruction, 0usize)
    let source_type = value_ty(g, value)
    if source_type.kind != .Integer && source_type.kind != .Named { ret fail(g, "a conversion this target does not have yet") }
    var normalize_as = instruction.ty
    if source_type.kind == .Integer && codegen_x64.integer_width(normalize_as) == 64usize { normalize_as = source_type }
    let sign_differs = codegen_x64.signed_integer(source_type) != codegen_x64.signed_integer(instruction.ty)
    let target_width = codegen_x64.integer_width(instruction.ty)
    let narrowing = source_type.kind == .Integer && instruction.immediate == 0usize && !instruction.nocheck && !g.b.release && (target_width < codegen_x64.integer_width(source_type) || sign_differs)
    vget(g, value)
    normalize_type(g, normalize_as)
    vset(g, instruction.result)
    if !narrowing { ret ok }
    // Section 11's `narrow` row: the value has to come back unchanged.
    if target_width == 64usize {
        vget(g, value)
        i64c(g, 0usize)
        op(g, 83usize)
    } else {
        vget(g, instruction.result)
        vget(g, value)
        op(g, 82usize)
    }
    trap_if(g, instruction.site, instruction.path, "narrow", "", " does not fit ", "", 1usize, codegen_x64.signed_integer(source_type), local_value(g, value), 0usize, instruction.ty.name)
    ret ok
}

fn emit_unary(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 1usize || instruction.ty.kind != .Integer { ret fail(g, "a unary operation on a type this target does not have yet") }
    let value = operand(g, instruction, 0usize)
    if instruction.opcode == .Cast { ret emit_cast(g, instruction) }
    let width = codegen_x64.integer_width(instruction.ty)
    if instruction.opcode == .BitNot {
        vget(g, value)
        i64c(g, 18446744073709551615usize)
        op(g, 133usize)
        normalize_type(g, instruction.ty)
        vset(g, instruction.result)
        ret ok
    }
    let negated = codegen_x64.signed_integer(instruction.ty) && !instruction.nocheck && !g.b.release
    if negated && width == 64usize {
        vget(g, value)
        i64c(g, 9223372036854775808usize)
        op(g, 81usize)
        overflow_if(g, instruction, " unary - overflows")
    }
    i64c(g, 0usize)
    vget(g, value)
    op(g, 125usize)
    if negated && width != 64usize {
        vset(g, instruction.result)
        fits_check(g, instruction, " unary - overflows")
        ret ok
    }
    normalize_type(g, instruction.ty)
    vset(g, instruction.result)
    ret ok
}

fn emit_bitcast(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 1usize || !instruction.has_result { ret fail(g, "a bitcast with the wrong operands") }
    vget(g, operand(g, instruction, 0usize))
    if codegen_x64.bitcast_scalar(instruction.ty) {
        let width = codegen_x64.bitcast_width(instruction.ty)
        if width == 0usize { ret fail(g, "a bitcast to a type this target does not have yet") }
        normalize_bits(g, width, codegen_x64.signed_integer(instruction.ty))
    }
    vset(g, instruction.result)
    ret ok
}

// ---- addresses and memory ------------------------------------------------------

// Whether the value is an address that lies inside the module's memory by construction: a
// frame slot, a global, a string or a field of one of those. Every other address, a pointer
// parameter, an element of a slice (its base is a stored pointer) or one loaded or cast from an
// integer, can carry bits above 31, which `i32.wrap_i64` would drop.
fn address_in_memory(g: *Gen, value: usize) -> bool {
    var at = value
    var steps = 0usize
    while steps < 16usize {
        if at >= g.current.value_count || g.pl_def_block[at] == 0usize { ret false }
        let definition = g.b.instructions[g.pl_def_pos[at]]
        let opcode = definition.opcode
        if opcode == .Stack || opcode == .GlobalAddress || opcode == .ConstString { ret true }
        if opcode != .FieldAddress || definition.operand_count != 1usize { ret false }
        at = operand(g, definition, 0usize)
        steps += 1usize
    }
    ret false
}

// Whether a debug build checks this address for bits above 31 (`@nocheck` code and `--release`
// leave the row out, as for every other debug-only row).
fn wants_address_check(g: *Gen, instruction: nir.Instruction, value: usize) -> bool {
    ret !instruction.nocheck && !g.b.release && !address_in_memory(g, value)
}

// An address or a function value on its way into memory or a table: the `i32` the engine
// takes. A debug build traps on a value of 2^32 or more (`bounds`, the closest row: native
// faults on a pointer outside every object, with no record) rather than let the wrap drop its
// high bits. The value is read once, through a scratch local, so operand folding still holds.
fn wrap_checked(g: *Gen, instruction: nir.Instruction, value: usize, first: str, second: str) {
    vget(g, value)
    if wants_address_check(g, instruction, value) {
        put(&g.code, 34usize)
        put_uleb(&g.code, local_s(g, 1usize))
        i64c(g, 4294967296usize)
        op(g, 90usize)
        trap_if(g, instruction.site, instruction.path, "bounds", first, second, "", 1usize, false, local_s(g, 1usize), 0usize, "")
        lget(g, local_s(g, 1usize))
    }
    wrap(g)
}

fn address_wrap(g: *Gen, instruction: nir.Instruction, value: usize) {
    wrap_checked(g, instruction, value, "address ", " is outside the 32-bit memory")
}

// The check alone, for an address that is read again afterwards.
fn check_address(g: *Gen, instruction: nir.Instruction, value: usize) {
    if wants_address_check(g, instruction, value) {
        vget(g, value)
        i64c(g, 4294967296usize)
        op(g, 90usize)
        trap_if(g, instruction.site, instruction.path, "bounds", "address ", " is outside the 32-bit memory", "", 1usize, false, local_value(g, value), 0usize, "")
    }
}

fn emit_index_address(g: *Gen, instruction: nir.Instruction) -> err {
    if !instruction.has_result || instruction.operand_count != 3usize || instruction.immediate == 0usize { ret fail(g, "an index with the wrong operands") }
    let base = operand(g, instruction, 0usize)
    let index = operand(g, instruction, 1usize)
    let length = operand(g, instruction, 2usize)
    if !instruction.nocheck {
        vget(g, index)
        vget(g, length)
        op(g, 90usize)
        trap_if(g, instruction.site, instruction.path, "bounds", "index ", " out of bounds for len ", "", 2usize, false, local_value(g, index), local_value(g, length), "")
    }
    vget(g, base)
    vget(g, index)
    i64c(g, instruction.immediate)
    op(g, 126usize)
    op(g, 124usize)
    vset(g, instruction.result)
    ret ok
}

fn emit_slice(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.has_result || instruction.operand_count != 5usize || instruction.immediate == 0usize { ret fail(g, "a slice with the wrong operands") }
    let destination = operand(g, instruction, 0usize)
    let base = operand(g, instruction, 1usize)
    let length = operand(g, instruction, 2usize)
    let start = operand(g, instruction, 3usize)
    let end = operand(g, instruction, 4usize)
    if !instruction.nocheck {
        vget(g, start)
        vget(g, end)
        op(g, 86usize)
        trap_if(g, instruction.site, instruction.path, "bounds", "slice start ", " after end ", "", 2usize, false, local_value(g, start), local_value(g, end), "")
        vget(g, end)
        vget(g, length)
        op(g, 86usize)
        trap_if(g, instruction.site, instruction.path, "bounds", "slice end ", " out of bounds for len ", "", 2usize, false, local_value(g, end), local_value(g, length), "")
    }
    check_address(g, instruction, destination)
    vget(g, destination)
    wrap(g)
    vget(g, base)
    vget(g, start)
    i64c(g, instruction.immediate)
    op(g, 126usize)
    op(g, 124usize)
    op(g, 55usize)
    memarg(g, 0usize)
    vget(g, destination)
    wrap(g)
    vget(g, end)
    vget(g, start)
    op(g, 125usize)
    op(g, 55usize)
    memarg(g, 8usize)
    ret ok
}

fn emit_memory(g: *Gen, instruction: nir.Instruction) -> err {
    let opcode = instruction.opcode
    if opcode == .Load || opcode == .Store {
        let width = codegen_x64.storage_width(instruction)
        if width != 8usize && width != 16usize && width != 32usize && width != 64usize { ret fail(g, "a load or store of a width this target does not have") }
        address_wrap(g, instruction, operand(g, instruction, 0usize))
        if opcode == .Store {
            if instruction.has_result || instruction.operand_count != 2usize { ret fail(g, "a store with the wrong operands") }
            vget(g, operand(g, instruction, 1usize))
            if width == 8usize { op(g, 60usize) }
            if width == 16usize { op(g, 61usize) }
            if width == 32usize { op(g, 62usize) }
            if width == 64usize { op(g, 55usize) }
            memarg(g, 0usize)
            ret ok
        }
        if !instruction.has_result || instruction.operand_count != 1usize { ret fail(g, "a load with the wrong operands") }
        let signed = codegen_x64.signed_integer(instruction.ty)
        if width == 64usize { op(g, 41usize) }
        if width == 32usize {
            if signed { op(g, 52usize) } else { op(g, 53usize) }
        }
        if width == 16usize {
            if signed { op(g, 50usize) } else { op(g, 51usize) }
        }
        if width == 8usize {
            if signed { op(g, 48usize) } else { op(g, 49usize) }
        }
        memarg(g, 0usize)
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .Copy {
        if instruction.has_result || instruction.operand_count != 2usize { ret fail(g, "a copy with the wrong operands") }
        address_wrap(g, instruction, operand(g, instruction, 0usize))
        address_wrap(g, instruction, operand(g, instruction, 1usize))
        i32c(g, instruction.immediate)
        op(g, 252usize)
        op(g, 10usize)
        op(g, 0usize)
        op(g, 0usize)
        ret ok
    }
    // Zero
    if instruction.has_result {
        if instruction.operand_count != 0usize { ret fail(g, "a zero with the wrong operands") }
        i64c(g, 0usize)
        vset(g, instruction.result)
        ret ok
    }
    if instruction.operand_count != 1usize { ret fail(g, "a zero with the wrong operands") }
    address_wrap(g, instruction, operand(g, instruction, 0usize))
    i32c(g, 0usize)
    i32c(g, instruction.immediate)
    op(g, 252usize)
    op(g, 11usize)
    op(g, 0usize)
    ret ok
}

// ---- calls ---------------------------------------------------------------------

// What the call site expects back: 0 nothing, 1 a value, 2 a pair read by `Extract`.
fn expected_results(instruction: nir.Instruction) -> usize {
    if !instruction.has_result { ret 0usize }
    if instruction.ty.kind == .Invalid { ret 2usize }
    if instruction.ty.kind == .Other && check.same(instruction.ty.name, "return-values") { ret 2usize }
    ret 1usize
}

// The values the call left on the stack, into the result's locals or dropped.
fn store_call_results(g: *Gen, instruction: nir.Instruction, expected: usize, produced: usize, never_returns: bool) -> err {
    if expected == 0usize {
        var dropped = 0usize
        while dropped < produced {
            op(g, 26usize)
            dropped += 1usize
        }
        ret ok
    }
    if produced == 0usize {
        // Only a callee with no `Return` at all (it traps, exits or loops for ever) leaves nothing to read.
        if !never_returns { ret fail(g, "a call that expects a value from a callee that returns none") }
        op(g, 0usize)
        ret ok
    }
    if produced != expected { ret fail(g, "a call whose callee returns a different number of values") }
    if expected == 2usize {
        lset(g, local_aux(g, instruction.result))
    }
    vset(g, instruction.result)
    ret ok
}

// A threads-proposal instruction (the 0xFE prefix) with its memarg: the alignment as a power
// of two, offset 0.
fn atomic_instruction(g: *Gen, code: usize, align: usize) {
    op(g, 254usize)
    put_uleb(&g.code, code)
    put(&g.code, align)
    put(&g.code, 0usize)
}

// The `wasm` library's threads instructions (D5672); `inline_op` 5 to 12. The plain module
// has the atomics and a thread id of 0, and answers a spawn with -1.
fn emit_thread_import(g: *Gen, item: Import) {
    if item.inline_op == 5usize {
        if g.threads { i32c(g, 1usize) } else { i32c(g, 0usize) }
    }
    if item.inline_op == 6usize {
        if g.threads {
            op(g, 35usize)
            put_uleb(&g.code, 2usize)
        } else {
            i32c(g, 0usize)
        }
    }
    if item.inline_op == 7usize {
        if g.threads {
            op(g, 16usize)
            put_uleb(&g.code, g.imports[0usize].wasm_index)
        } else {
            op(g, 26usize)
            i32c(g, 4294967295usize)
        }
    }
    if item.inline_op == 8usize { atomic_instruction(g, 1usize, 2usize) }
    if item.inline_op == 9usize { atomic_instruction(g, 0usize, 2usize) }
    if item.inline_op == 10usize { atomic_instruction(g, 72usize, 2usize) }
    if item.inline_op == 11usize { atomic_instruction(g, 16usize, 2usize) }
    if item.inline_op == 12usize { atomic_instruction(g, 23usize, 2usize) }
}

fn emit_inline_import(g: *Gen, instruction: nir.Instruction, item: Import) -> err {
    var at = 0usize
    while at < instruction.operand_count {
        vget(g, operand(g, instruction, at))
        if item.inline_op <= 4usize || (item.mask32 >> at) & 1usize == 1usize { wrap(g) }
        at += 1usize
    }
    if item.inline_op >= 5usize { emit_thread_import(g, item) }
    if item.inline_op == 1usize {
        op(g, 64usize)
        op(g, 0usize)
    }
    if item.inline_op == 2usize {
        op(g, 63usize)
        op(g, 0usize)
    }
    if item.inline_op == 3usize {
        op(g, 252usize)
        op(g, 11usize)
        op(g, 0usize)
    }
    if item.inline_op == 4usize {
        op(g, 252usize)
        op(g, 10usize)
        op(g, 0usize)
        op(g, 0usize)
    }
    ret finish_import_call(g, instruction, item)
}

fn finish_import_call(g: *Gen, instruction: nir.Instruction, item: Import) -> err {
    var produced = 0usize
    if item.result_kind != 0usize { produced = 1usize }
    if item.result_kind == 2usize { extend_unsigned(g) }
    if item.result_kind == 3usize { extend_signed(g) }
    if expected_results(instruction) == 2usize { ret fail(g, "an import that returns a pair") }
    ret store_call_results(g, instruction, expected_results(instruction), produced, false)
}

fn emit_call(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.immediate >= g.b.function_ref_count { ret fail(g, "a call with no function reference") }
    let reference = g.b.function_refs[instruction.immediate]
    if reference.library.len != 0usize {
        let item = g.imports[g.ref_import[instruction.immediate] - 1usize]
        if instruction.operand_count != item.param_count { ret fail(g, "a call of an import with the wrong number of arguments") }
        if item.inline_op != 0usize { ret emit_inline_import(g, instruction, item) }
        var at = 0usize
        while at < instruction.operand_count {
            vget(g, operand(g, instruction, at))
            if (item.mask32 >> at) & 1usize == 1usize { wrap(g) }
            at += 1usize
        }
        op(g, 16usize)
        put_uleb(&g.code, item.wasm_index)
        ret finish_import_call(g, instruction, item)
    }
    if !reference.has_target { ret fail(g, "a call of a function the program does not define") }
    var at = 0usize
    while at < instruction.operand_count {
        vget(g, operand(g, instruction, at))
        at += 1usize
    }
    op(g, 16usize)
    put_uleb(&g.code, function_wasm_index(g, reference.target))
    ret store_call_results(g, instruction, expected_results(instruction), usize(g.results[reference.target]), !g.returns[reference.target])
}

fn emit_extract(g: *Gen, instruction: nir.Instruction) -> err {
    if !instruction.has_result || instruction.operand_count != 1usize || instruction.immediate >= 2usize { ret fail(g, "an extract with the wrong operands") }
    let source = operand(g, instruction, 0usize)
    if instruction.immediate == 0usize {
        vget(g, source)
    } else {
        if g.fr_aux[source] == 0usize { ret fail(g, "an extract of a second result the value does not have") }
        lget(g, local_aux(g, source))
    }
    vset(g, instruction.result)
    ret ok
}

// ---- control flow --------------------------------------------------------------

fn epilogue(g: *Gen) {
    if g.fr_frame == 0usize { ret }
    lget(g, local_fp(g))
    i64c(g, g.fr_frame)
    op(g, 124usize)
    put(&g.code, 36usize)
    put_uleb(&g.code, 0usize)
}

fn emit_return(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count > 2usize { ret fail(g, "a return of more than two values") }
    var at = 0usize
    while at < instruction.operand_count {
        vget(g, operand(g, instruction, at))
        at += 1usize
    }
    epilogue(g)
    op(g, 15usize)
    ret ok
}

// Set `$bb` and go round the loop, unless the target is the block that follows.
fn goto_block(g: *Gen, destination_block: usize, inside: usize) {
    if destination_block == g.fr_block + 1usize && inside == 0usize { ret }
    i32c(g, destination_block)
    lset(g, local_bb(g))
    op(g, 12usize)
    put_uleb(&g.code, g.fr_blocks - 1usize - g.fr_block + inside)
}

fn emit_branch(g: *Gen, instruction: nir.Instruction) -> err {
    let first = g.current.first_block
    if instruction.target < first || instruction.target >= first + g.current.block_count { ret fail(g, "a branch out of its function") }
    goto_block(g, instruction.target - first, 0usize)
    ret ok
}

fn emit_branch_if(g: *Gen, instruction: nir.Instruction) -> err {
    let first = g.current.first_block
    let count = g.current.block_count
    if instruction.operand_count != 1usize || instruction.target < first || instruction.target >= first + count || instruction.target2 < first || instruction.target2 >= first + count { ret fail(g, "a branch out of its function") }
    let on_true = instruction.target - first
    let on_false = instruction.target2 - first
    vget(g, operand(g, instruction, 0usize))
    wrap(g)
    block_if(g)
    goto_block(g, on_true, 1usize)
    block_end(g)
    goto_block(g, on_false, 0usize)
    ret ok
}

fn emit_trap_instruction(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.has_result || instruction.operand_count > 2usize { ret fail(g, "a trap with the wrong operands") }
    let (kind, message, text_error) = codegen_x64.trap_instruction_text(g.b, instruction)
    if text_error != ok { ret text_error }
    var signed = false
    var a_local = 0usize
    var b_local = 0usize
    if instruction.operand_count >= 1usize {
        let first = operand(g, instruction, 0usize)
        signed = codegen_x64.signed_integer(value_ty(g, first))
        a_local = local_value(g, first)
    }
    if instruction.operand_count == 2usize { b_local = local_value(g, operand(g, instruction, 1usize)) }
    trap_call(g, instruction.site, instruction.path, kind, message, "", "", instruction.operand_count, signed, a_local, b_local, "")
    ret ok
}

// ---- indirect calls ------------------------------------------------------------

// The callee is a table slot (D5213: slot 0 is null, so a zero function value traps); the
// call's own signature is the type `call_indirect` checks the slot's function against.
fn emit_indirect_call(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count == 0usize { ret fail(g, "an indirect call without a callee") }
    var at = 1usize
    while at < instruction.operand_count {
        vget(g, operand(g, instruction, at))
        at += 1usize
    }
    wrap_checked(g, instruction, operand(g, instruction, 0usize), "function value ", " is outside the function table")
    let expected = expected_results(instruction)
    let signature = intern_signature(g, instruction.operand_count - 1usize, 0usize, expected)
    if g.failure.len != 0usize { ret Unsupported }
    op(g, 17usize)
    put_uleb(&g.code, signature)
    put_uleb(&g.code, 0usize)
    ret store_call_results(g, instruction, expected, expected, false)
}

// ---- floats --------------------------------------------------------------------

// A float is its bits in an `i64` local; these bring it onto the stack as an `f32` or
// `f64` and back (a 32-bit float is held zero-extended).
fn to_float(g: *Gen, width: usize) {
    if width == 32usize {
        wrap(g)
        op(g, 190usize)
        ret
    }
    op(g, 191usize)
}

fn from_float(g: *Gen, width: usize) {
    if width == 32usize {
        op(g, 188usize)
        extend_unsigned(g)
        ret
    }
    op(g, 189usize)
}

// Section 11's canonical NaN: a NaN result becomes the one quiet NaN of its width.
fn canonicalize_float(g: *Gen, result: usize, width: usize) {
    i64c(g, codegen_x64.canonical_nan(width))
    vget(g, result)
    vget(g, result)
    to_float(g, width)
    vget(g, result)
    to_float(g, width)
    if width == 32usize { op(g, 92usize) } else { op(g, 98usize) }
    op(g, 27usize)
    vset(g, result)
}

fn emit_float_compare(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 2usize { ret fail(g, "a comparison with the wrong operands") }
    let left = operand(g, instruction, 0usize)
    let width = codegen_x64.float_width(value_ty(g, left))
    if width == 0usize { ret fail(g, "an f16 or bf16 comparison, which codegen_a64 does not have either") }
    vget(g, left)
    to_float(g, width)
    vget(g, operand(g, instruction, 1usize))
    to_float(g, width)
    var code = 91usize
    if instruction.opcode == .NotEqual { code = 92usize }
    if instruction.opcode == .Less { code = 93usize }
    if instruction.opcode == .Greater { code = 94usize }
    if instruction.opcode == .LessEqual { code = 95usize }
    if instruction.opcode == .GreaterEqual { code = 96usize }
    if width == 64usize { code += 6usize }
    op(g, code)
    extend_unsigned(g)
    vset(g, instruction.result)
    ret ok
}

// A float to an integer: the debug range check first (section 11's `narrow` row), then the
// saturating truncation, which is FCVTZS/FCVTZU's NaN-to-zero and clamp at 64 bits, and a
// clamp to the narrower width.
fn emit_float_to_integer(g: *Gen, instruction: nir.Instruction, value: usize, source_width: usize) {
    let wide = source_width == 64usize
    let width = codegen_x64.integer_width(instruction.ty)
    let signed = codegen_x64.signed_integer(instruction.ty)
    let result = instruction.result
    if instruction.immediate == 0usize && !instruction.nocheck && !g.b.release {
        vget(g, value)
        to_float(g, source_width)
        i64c(g, codegen_x64.float_bound_bits(width, signed, true, wide))
        to_float(g, source_width)
        if wide { op(g, 99usize) } else { op(g, 93usize) }
        op(g, 69usize)
        trap_if(g, instruction.site, instruction.path, "narrow", "a float outside ", "", "", 0usize, false, 0usize, 0usize, instruction.ty.name)
        vget(g, value)
        to_float(g, source_width)
        i64c(g, codegen_x64.float_bound_bits(width, signed, false, wide))
        to_float(g, source_width)
        var compare = 94usize
        if signed && (width == 64usize || !wide) { compare = 96usize }
        if wide { compare += 6usize }
        op(g, compare)
        op(g, 69usize)
        trap_if(g, instruction.site, instruction.path, "narrow", "a float outside ", "", "", 0usize, false, 0usize, 0usize, instruction.ty.name)
    }
    vget(g, value)
    to_float(g, source_width)
    op(g, 252usize)
    var saturating = 4usize
    if wide { saturating = 6usize }
    if !signed { saturating += 1usize }
    put_uleb(&g.code, saturating)
    vset(g, result)
    if width == 64usize { ret }
    let all_ones = 0usize -% 1usize
    if signed {
        let maximum = all_ones >> (65usize - width)
        let minimum = all_ones - maximum
        i64c(g, maximum)
        vget(g, result)
        vget(g, result)
        i64c(g, maximum)
        op(g, 85usize)
        op(g, 27usize)
        vset(g, result)
        i64c(g, minimum)
        vget(g, result)
        vget(g, result)
        i64c(g, minimum)
        op(g, 83usize)
        op(g, 27usize)
        vset(g, result)
        ret
    }
    let maximum = all_ones >> (64usize - width)
    i64c(g, maximum)
    vget(g, result)
    vget(g, result)
    i64c(g, maximum)
    op(g, 86usize)
    op(g, 27usize)
    vset(g, result)
}

fn emit_float_cast(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 1usize { ret fail(g, "a conversion with the wrong operands") }
    let value = operand(g, instruction, 0usize)
    let source_type = value_ty(g, value)
    let source_width = codegen_x64.float_width(source_type)
    let target_width = codegen_x64.float_width(instruction.ty)
    if source_type.kind == .Float && instruction.ty.kind == .Float {
        if source_width == 0usize || target_width == 0usize { ret fail(g, "an f16 or bf16 conversion, which codegen_a64 does not have either") }
        vget(g, value)
        if source_width != target_width {
            to_float(g, source_width)
            if target_width == 64usize { op(g, 187usize) } else { op(g, 182usize) }
            from_float(g, target_width)
        }
        vset(g, instruction.result)
        if source_width != target_width { canonicalize_float(g, instruction.result, target_width) }
        ret ok
    }
    if instruction.ty.kind == .Float {
        if target_width == 0usize || source_type.kind != .Integer { ret fail(g, "a conversion to a float this target does not have") }
        vget(g, value)
        var code = 180usize
        if target_width == 64usize { code = 185usize }
        if codegen_x64.unsigned_wide(source_type) { code += 1usize }
        op(g, code)
        from_float(g, target_width)
        vset(g, instruction.result)
        ret ok
    }
    if source_width == 0usize || instruction.ty.kind != .Integer { ret fail(g, "a conversion from a float this target does not have") }
    emit_float_to_integer(g, instruction, value, source_width)
    ret ok
}

fn emit_float(g: *Gen, instruction: nir.Instruction) -> err {
    let opcode = instruction.opcode
    if !instruction.has_result { ret fail(g, "a float operation without a result") }
    if opcode == .Cast { ret emit_float_cast(g, instruction) }
    if codegen_x64.comparison(opcode) { ret emit_float_compare(g, instruction) }
    let width = codegen_x64.float_width(instruction.ty)
    if width == 0usize { ret fail(g, "f16 and bf16 arithmetic, which codegen_a64 does not have either") }
    let left = operand(g, instruction, 0usize)
    if opcode == .Negate {
        vget(g, left)
        i64c(g, codegen_x64.float_sign_bit(width))
        op(g, 133usize)
        vset(g, instruction.result)
        canonicalize_float(g, instruction.result, width)
        ret ok
    }
    vget(g, left)
    to_float(g, width)
    if opcode == .Sqrt {
        if width == 32usize { op(g, 145usize) } else { op(g, 159usize) }
    } else {
        var code = 146usize
        if opcode == .Subtract { code = 147usize }
        if opcode == .Multiply { code = 148usize }
        if opcode == .Divide { code = 149usize }
        if instruction.operand_count != 2usize || (opcode != .Add && opcode != .Subtract && opcode != .Multiply && opcode != .Divide) { ret fail(g, "a float operation with the wrong operands") }
        vget(g, operand(g, instruction, 1usize))
        to_float(g, width)
        if width == 64usize { code += 14usize }
        op(g, code)
    }
    from_float(g, width)
    vset(g, instruction.result)
    canonicalize_float(g, instruction.result, width)
    ret ok
}

// ---- atomics -------------------------------------------------------------------

fn load_for(g: *Gen, width: usize, signed: bool) {
    if width == 64usize { op(g, 41usize) }
    if width == 32usize {
        if signed { op(g, 52usize) } else { op(g, 53usize) }
    }
    if width == 16usize {
        if signed { op(g, 50usize) } else { op(g, 51usize) }
    }
    if width == 8usize {
        if signed { op(g, 48usize) } else { op(g, 49usize) }
    }
    memarg(g, 0usize)
}

fn store_for(g: *Gen, width: usize) {
    if width == 8usize { op(g, 60usize) }
    if width == 16usize { op(g, 61usize) }
    if width == 32usize { op(g, 62usize) }
    if width == 64usize { op(g, 55usize) }
    memarg(g, 0usize)
}

// A threaded module's atomic (D5672): the `i64` form of the instruction whose base opcode is
// `base`, B+1 for 64 bits and B+4, B+5, B+6 for 8, 16 and 32, with the natural alignment.
fn atomic_for(g: *Gen, base: usize, width: usize) {
    var code = base + 1usize
    var align = 3usize
    if width == 8usize {
        code = base + 4usize
        align = 0usize
    }
    if width == 16usize {
        code = base + 5usize
        align = 1usize
    }
    if width == 32usize {
        code = base + 6usize
        align = 2usize
    }
    atomic_instruction(g, code, align)
}

// The old value an instruction gave back zero-extended, as the type holds it.
fn atomic_old_value(g: *Gen, width: usize, signed: bool) {
    if signed { normalize_bits(g, width, true) }
}

// Section 8's five instructions as the threads proposal's: load, store, the six
// read-modify-writes that have an instruction and compare-and-swap. `min` and `max` have none;
// they are a loop of the load and a compare-and-swap of the chosen value.
fn emit_atomic_threads(g: *Gen, instruction: nir.Instruction, width: usize, signed: bool) -> err {
    let opcode = instruction.opcode
    let address = operand(g, instruction, 0usize)
    if opcode == .AtomicStore {
        if instruction.operand_count != 2usize { ret fail(g, "an atomic store with the wrong operands") }
        address_wrap(g, instruction, address)
        vget(g, operand(g, instruction, 1usize))
        atomic_for(g, 23usize, width)
        ret ok
    }
    if !instruction.has_result { ret fail(g, "an atomic without a result") }
    let result = instruction.result
    if opcode == .AtomicLoad {
        address_wrap(g, instruction, address)
        atomic_for(g, 16usize, width)
        atomic_old_value(g, width, signed)
        vset(g, result)
        ret ok
    }
    if opcode == .AtomicCas {
        if instruction.operand_count != 3usize { ret fail(g, "a compare-and-swap with the wrong operands") }
        address_wrap(g, instruction, address)
        vget(g, operand(g, instruction, 1usize))
        vget(g, operand(g, instruction, 2usize))
        atomic_for(g, 72usize, width)
        atomic_old_value(g, width, signed)
        vset(g, result)
        ret ok
    }
    if instruction.operand_count != 2usize { ret fail(g, "a read-modify-write with the wrong operands") }
    let operand_value = operand(g, instruction, 1usize)
    let kind = instruction.immediate / 8usize
    if kind > 7usize { ret fail(g, "a read-modify-write of a kind that is not there") }
    if kind <= 5usize {
        // xchg, add, sub, and, or, xor
        var base = 65usize
        if kind == 1usize { base = 30usize }
        if kind == 2usize { base = 37usize }
        if kind == 3usize { base = 44usize }
        if kind == 4usize { base = 51usize }
        if kind == 5usize { base = 58usize }
        address_wrap(g, instruction, address)
        vget(g, operand_value)
        atomic_for(g, base, width)
        atomic_old_value(g, width, signed)
        vset(g, result)
        ret ok
    }
    check_address(g, instruction, address)
    vget(g, address)
    wrap(g)
    atomic_for(g, 16usize, width)
    atomic_old_value(g, width, signed)
    vset(g, result)
    op(g, 3usize)
    op(g, 64usize)
    vget(g, address)
    wrap(g)
    vget(g, result)
    vget(g, result)
    vget(g, operand_value)
    vget(g, result)
    vget(g, operand_value)
    if kind == 6usize {
        if signed { op(g, 83usize) } else { op(g, 84usize) }
    } else {
        if signed { op(g, 85usize) } else { op(g, 86usize) }
    }
    op(g, 27usize)
    atomic_for(g, 72usize, width)
    atomic_old_value(g, width, signed)
    lset(g, local_s(g, 2usize))
    lget(g, local_s(g, 2usize))
    vget(g, result)
    op(g, 82usize)
    block_if(g)
    lget(g, local_s(g, 2usize))
    vset(g, result)
    op(g, 12usize)
    put_uleb(&g.code, 1usize)
    block_end(g)
    block_end(g)
    ret ok
}

// Section 8's five instructions as plain memory operations: this target has one thread,
// so a read-modify-write needs no lock. Each gives back the value that was there.
fn emit_atomic(g: *Gen, instruction: nir.Instruction) -> err {
    let opcode = instruction.opcode
    let width = codegen_x64.atomic_width(instruction.ty)
    if width != 8usize && width != 16usize && width != 32usize && width != 64usize { ret fail(g, "an atomic of a width this target does not have") }
    if instruction.operand_count == 0usize { ret fail(g, "an atomic without an address") }
    let signed = codegen_x64.signed_integer(instruction.ty)
    if g.threads { ret emit_atomic_threads(g, instruction, width, signed) }
    let address = operand(g, instruction, 0usize)
    if opcode == .AtomicStore {
        if instruction.operand_count != 2usize { ret fail(g, "an atomic store with the wrong operands") }
        address_wrap(g, instruction, address)
        vget(g, operand(g, instruction, 1usize))
        store_for(g, width)
        ret ok
    }
    if !instruction.has_result { ret fail(g, "an atomic without a result") }
    let result = instruction.result
    address_wrap(g, instruction, address)
    load_for(g, width, signed)
    vset(g, result)
    if opcode == .AtomicLoad { ret ok }
    if opcode == .AtomicCas {
        if instruction.operand_count != 3usize { ret fail(g, "a compare-and-swap with the wrong operands") }
        vget(g, result)
        vget(g, operand(g, instruction, 1usize))
        op(g, 81usize)
        block_if(g)
        vget(g, address)
        wrap(g)
        vget(g, operand(g, instruction, 2usize))
        store_for(g, width)
        block_end(g)
        ret ok
    }
    if instruction.operand_count != 2usize { ret fail(g, "a read-modify-write with the wrong operands") }
    let operand_value = operand(g, instruction, 1usize)
    let kind = instruction.immediate / 8usize
    address_wrap(g, instruction, address)
    if kind == 0usize { vget(g, operand_value) }
    if kind >= 1usize && kind <= 5usize {
        vget(g, result)
        vget(g, operand_value)
        if kind == 1usize { op(g, 124usize) }
        if kind == 2usize { op(g, 125usize) }
        if kind == 3usize { op(g, 131usize) }
        if kind == 4usize { op(g, 132usize) }
        if kind == 5usize { op(g, 133usize) }
    }
    if kind == 6usize || kind == 7usize {
        vget(g, result)
        vget(g, operand_value)
        vget(g, result)
        vget(g, operand_value)
        if kind == 6usize {
            if signed { op(g, 83usize) } else { op(g, 84usize) }
        } else {
            if signed { op(g, 85usize) } else { op(g, 86usize) }
        }
        op(g, 27usize)
    }
    if kind > 7usize { ret fail(g, "a read-modify-write of a kind that is not there") }
    store_for(g, width)
    ret ok
}

// ---- simd128 -------------------------------------------------------------------

fn simd(g: *Gen, code: usize) {
    op(g, 253usize)
    put_uleb(&g.code, code)
}

fn local_vec(g: *Gen, k: usize) -> usize { ret g.fr_params + 6usize + g.fr_slots + g.fr_aux_count + k }

// The 16, 8, 4 or 2 bytes at an address as a `v128`, the rest zero.
fn vec_load(g: *Gen, instruction: nir.Instruction, address: usize, bytes: usize) {
    address_wrap(g, instruction, address)
    if bytes == 16usize {
        simd(g, 0usize)
        memarg(g, 0usize)
        ret
    }
    if bytes == 8usize {
        simd(g, 93usize)
        memarg(g, 0usize)
        ret
    }
    if bytes == 4usize {
        simd(g, 92usize)
        memarg(g, 0usize)
        ret
    }
    simd(g, 12usize)
    var zero_at = 0usize
    while zero_at < 16usize {
        put(&g.code, 0usize)
        zero_at += 1usize
    }
    simd(g, 85usize)
    memarg(g, 0usize)
    put(&g.code, 0usize)
}

// The low `bytes` of the `v128` local `k` to an address.
fn vec_store(g: *Gen, instruction: nir.Instruction, address: usize, bytes: usize, k: usize) {
    address_wrap(g, instruction, address)
    lget(g, local_vec(g, k))
    if bytes == 16usize {
        simd(g, 11usize)
        memarg(g, 0usize)
        ret
    }
    if bytes == 8usize { simd(g, 91usize) }
    if bytes == 4usize { simd(g, 90usize) }
    if bytes == 2usize { simd(g, 89usize) }
    memarg(g, 0usize)
    put(&g.code, 0usize)
}

// simd128 has no `i8x16.mul`: that shape goes byte by byte through memory.
fn emit_byte_multiply(g: *Gen, instruction: nir.Instruction, destination: usize, left: usize, right: usize, bytes: usize) {
    check_address(g, instruction, destination)
    check_address(g, instruction, left)
    check_address(g, instruction, right)
    var at = 0usize
    while at < bytes {
        vget(g, destination)
        wrap(g)
        vget(g, left)
        wrap(g)
        op(g, 45usize)
        memarg(g, at)
        vget(g, right)
        wrap(g)
        op(g, 45usize)
        memarg(g, at)
        op(g, 108usize)
        op(g, 58usize)
        memarg(g, at)
        at += 1usize
    }
}

// A packed shift: the count is in the immediate or, when the compiler did not know it, the
// third operand, checked and masked as the scalar shift is.
fn emit_vector_shift(g: *Gen, instruction: nir.Instruction, lane: usize, operation: usize, count_value: usize) {
    var code = 107usize + lane * 32usize
    if operation == 13usize { code = 109usize + lane * 32usize }
    if operation == 14usize { code = 108usize + lane * 32usize }
    if nir.vector_shift_in_register(instruction.immediate) {
        let width = codegen_x64.packed_lane_size(lane) * 8usize
        if !instruction.nocheck && !g.b.release {
            i64c(g, width)
            lset(g, local_s(g, 0usize))
            vget(g, count_value)
            lget(g, local_s(g, 0usize))
            op(g, 90usize)
            trap_if(g, instruction.site, instruction.path, "shift", "shift by ", " on a width of ", "", 2usize, false, local_value(g, count_value), local_s(g, 0usize), "")
        }
        vget(g, count_value)
        i64c(g, width - 1usize)
        op(g, 131usize)
        wrap(g)
    } else {
        i32c(g, nir.vector_binary_count(instruction.immediate))
    }
    simd(g, code)
}

// Section 4's lane-wise operator over a whole vector (D5213's table): the operands load into
// `v128` values, one simd128 instruction does the operation, and the low `bytes` go back.
// A float lane gets section 11's canonical NaN: the lanes that are not equal to themselves
// are replaced by it.
fn emit_vector(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.has_result || instruction.operand_count != 3usize { ret fail(g, "a vector operation with the wrong operands") }
    let lane = nir.vector_binary_lane(instruction.immediate)
    let operation = nir.vector_binary_operation(instruction.immediate)
    let lane_bytes = codegen_x64.packed_lane_size(lane)
    let bytes = nir.vector_binary_lanes(instruction.immediate) * lane_bytes
    if bytes != 16usize && bytes != 8usize && bytes != 4usize && bytes != 2usize { ret fail(g, "a vector operation over a size simd128 has no load for") }
    let destination = operand(g, instruction, 0usize)
    let left = operand(g, instruction, 1usize)
    let right = operand(g, instruction, 2usize)
    if operation == 6usize && lane == 0usize {
        emit_byte_multiply(g, instruction, destination, left, right, bytes)
        ret ok
    }
    vec_load(g, instruction, left, bytes)
    if operation >= 12usize {
        if lane > 3usize { ret fail(g, "a packed shift of float lanes") }
        emit_vector_shift(g, instruction, lane, operation, right)
    } else {
        if operation < 10usize { vec_load(g, instruction, right, bytes) }
        if operation == 10usize { simd(g, 77usize) }
        if operation == 11usize {
            i32c(g, 1usize)
            simd(g, 15usize)
            simd(g, 81usize)
        }
        if operation <= 3usize {
            if lane < 4usize { ret fail(g, "a float operation on integer lanes") }
            if lane == 4usize { simd(g, 228usize + operation) } else { simd(g, 240usize + operation) }
        }
        if operation == 4usize { simd(g, 110usize + lane * 32usize) }
        if operation == 5usize { simd(g, 113usize + lane * 32usize) }
        if operation == 6usize { simd(g, 117usize + lane * 32usize) }
        if operation == 7usize { simd(g, 78usize) }
        if operation == 8usize { simd(g, 80usize) }
        if operation == 9usize { simd(g, 81usize) }
    }
    lset(g, local_vec(g, 0usize))
    if operation <= 3usize {
        lget(g, local_vec(g, 0usize))
        if lane == 4usize {
            i32c(g, codegen_x64.canonical_nan(32usize))
            simd(g, 17usize)
        } else {
            i64c(g, codegen_x64.canonical_nan(64usize))
            simd(g, 18usize)
        }
        lget(g, local_vec(g, 0usize))
        lget(g, local_vec(g, 0usize))
        if lane == 4usize { simd(g, 65usize) } else { simd(g, 71usize) }
        simd(g, 82usize)
        lset(g, local_vec(g, 0usize))
    }
    vec_store(g, instruction, destination, bytes, 0usize)
    ret ok
}

// ---- one instruction -----------------------------------------------------------

fn emit_leaf(g: *Gen, instruction: nir.Instruction, at: usize) -> err {
    let opcode = instruction.opcode
    if opcode == .Parameter {
        if instruction.immediate >= g.fr_params { ret fail(g, "a parameter the function does not have") }
        lget(g, instruction.immediate)
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .ConstInteger || opcode == .ConstBool || opcode == .ConstError || opcode == .ConstFloat {
        i64c(g, instruction.immediate)
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .ConstString {
        if instruction.immediate >= g.b.string_count { ret fail(g, "a string constant that is not there") }
        i64c(g, string_address(g, instruction.immediate))
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .Stack {
        lget(g, local_fp(g))
        i64c(g, g.fr_offsets[at - g.current.first_instruction])
        op(g, 124usize)
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .GlobalAddress {
        if instruction.immediate >= g.b.global_count { ret fail(g, "a global that is not there") }
        i64c(g, g.global_address[instruction.immediate])
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .FunctionAddress {
        if !instruction.has_result || instruction.operand_count != 0usize || instruction.immediate >= g.b.function_ref_count { ret fail(g, "a function address with the wrong operands") }
        i64c(g, g.slot_of[g.b.function_refs[instruction.immediate].target])
        vset(g, instruction.result)
        ret ok
    }
    if opcode == .FieldAddress {
        if !instruction.has_result || instruction.operand_count != 1usize { ret fail(g, "a field address with the wrong operands") }
        vget(g, operand(g, instruction, 0usize))
        i64c(g, instruction.immediate)
        op(g, 124usize)
        vset(g, instruction.result)
        ret ok
    }
    ret fail(g, "an instruction this target does not have yet")
}

fn emit_instruction(g: *Gen, instruction: nir.Instruction, at: usize) -> err {
    let emitted = emit_one(g, instruction, at)
    if emitted != ok && g.failure_opcode == 0usize {
        g.failure_opcode = em.opcode_id(instruction.opcode)
        g.failure_line = instruction.site.line
        g.failure_path = instruction.path
    }
    ret emitted
}

fn emit_one(g: *Gen, instruction: nir.Instruction, at: usize) -> err {
    let opcode = instruction.opcode
    if opcode == .Bitcast { ret emit_bitcast(g, instruction) }
    if codegen_x64.float_operation(g.b, g.current, instruction) { ret emit_float(g, instruction) }
    if opcode == .Parameter || opcode == .ConstInteger || opcode == .ConstBool || opcode == .ConstError || opcode == .ConstFloat || opcode == .ConstString || opcode == .Stack || opcode == .GlobalAddress || opcode == .FieldAddress || opcode == .FunctionAddress { ret emit_leaf(g, instruction, at) }
    if opcode == .AtomicLoad || opcode == .AtomicStore || opcode == .AtomicRmw || opcode == .AtomicCas { ret emit_atomic(g, instruction) }
    if opcode == .VectorBinary { ret emit_vector(g, instruction) }
    if opcode == .IndirectCall { ret emit_indirect_call(g, instruction) }
    if opcode == .Load || opcode == .Store || opcode == .Copy || opcode == .Zero { ret emit_memory(g, instruction) }
    if opcode == .IndexAddress { ret emit_index_address(g, instruction) }
    if opcode == .Slice { ret emit_slice(g, instruction) }
    if opcode == .Cast || opcode == .Negate || opcode == .BitNot { ret emit_unary(g, instruction) }
    if opcode == .ShiftLeft || opcode == .ShiftRight { ret emit_shift(g, instruction) }
    if opcode == .Divide || opcode == .Remainder { ret emit_divide(g, instruction) }
    if codegen_x64.comparison(opcode) { ret emit_comparison(g, instruction) }
    if codegen_x64.register_binary(opcode) { ret emit_arithmetic(g, instruction) }
    if opcode == .Call { ret emit_call(g, instruction) }
    if opcode == .Extract { ret emit_extract(g, instruction) }
    if opcode == .Branch { ret emit_branch(g, instruction) }
    if opcode == .BranchIf { ret emit_branch_if(g, instruction) }
    if opcode == .Trap || opcode == .Unreachable { ret emit_trap_instruction(g, instruction) }
    if opcode == .Return { ret emit_return(g, instruction) }
    if opcode == .AtomicFence && instruction.immediate != 100usize && instruction.immediate != 101usize {
        if g.threads {
            op(g, 254usize)
            op(g, 3usize)
            op(g, 0usize)
        }
        ret ok
    }
    if opcode == .AtomicFence { ret fail(g, "a flush-to-zero mode switch (a kernel launched with .Ftz), which WebAssembly floats cannot do: they keep denormals") }
    if opcode == .Switch { ret fail(g, "a switch instruction, which no lowering makes and no back end reads (it carries no case table)") }
    ret fail(g, "an instruction this target does not have")
}

// ---- a function ----------------------------------------------------------------

// The frame's layout: each `Stack` object's offset, the pairs of values that are a call's
// two results, and the frame's size (sixteen-byte aligned).
fn plan_frame(g: *Gen, function: nir.Function) -> err {
    var offset = 0usize
    var aux = 0usize
    g.fr_vec = false
    var clear_at = 0usize
    while clear_at < function.value_count + 1usize {
        g.fr_aux[clear_at] = 0usize
        clear_at += 1usize
    }
    var at = function.first_instruction
    while at < function.first_instruction + function.instruction_count {
        let instruction = g.b.instructions[at]
        if instruction.opcode == .Stack {
            var slots = instruction.immediate
            if slots == 0usize { slots = 1usize }
            g.fr_offsets[at - function.first_instruction] = offset
            offset += slots * 8usize
        }
        if instruction.opcode == .VectorBinary { g.fr_vec = true }
        if (instruction.opcode == .Call || instruction.opcode == .IndirectCall) && expected_results(instruction) == 2usize {
            if instruction.result >= function.value_count { ret fail(g, "a call result outside its function") }
            aux += 1usize
            g.fr_aux[instruction.result] = aux
        }
        at += 1usize
    }
    g.fr_frame = (offset + 15usize) / 16usize * 16usize
    g.fr_aux_count = aux
    ret ok
}

fn prologue(g: *Gen, function: nir.Function) {
    if g.fr_frame == 0usize { ret }
    put(&g.code, 35usize)
    put_uleb(&g.code, 0usize)
    i64c(g, g.fr_frame)
    op(g, 125usize)
    lset(g, local_fp(g))
    lget(g, local_fp(g))
    put(&g.code, 35usize)
    put_uleb(&g.code, 1usize)
    // Signed: a frame bigger than the whole stack makes the address negative.
    op(g, 83usize)
    var site: nir.Site = zero
    if function.instruction_count != 0usize { site = g.b.instructions[function.first_instruction].site }
    trap_if(g, site, function.path, "stack", "stack overflow", "", "", 0usize, false, 0usize, 0usize, "")
    lget(g, local_fp(g))
    put(&g.code, 36usize)
    put_uleb(&g.code, 0usize)
}

// Whether any block branches: a function of one block that does is a loop on itself.
fn branches(g: *Gen, function: nir.Function) -> bool {
    var at = function.first_instruction
    while at < function.first_instruction + function.instruction_count {
        let opcode = g.b.instructions[at].opcode
        if opcode == .Branch || opcode == .BranchIf { ret true }
        at += 1usize
    }
    ret false
}

fn emit_blocks(g: *Gen, function: nir.Function) -> err {
    let count = function.block_count
    g.fr_blocks = count
    let dispatch = count > 1usize || branches(g, function)
    if dispatch {
        op(g, 3usize)
        op(g, 64usize)
        var open = 0usize
        while open < count {
            op(g, 2usize)
            op(g, 64usize)
            open += 1usize
        }
        lget(g, local_bb(g))
        op(g, 14usize)
        put_uleb(&g.code, count)
        var label = 0usize
        while label < count {
            put_uleb(&g.code, label)
            label += 1usize
        }
        put_uleb(&g.code, count - 1usize)
        block_end(g)
    }
    var block_at = 0usize
    while block_at < count {
        g.fr_block = block_at
        let block = g.b.blocks[function.first_block + block_at]
        var at = block.first_instruction
        while at < block.first_instruction + block.instruction_count {
            g.current = function
            try emit_folded(g, g.b.instructions[at], at, 0usize)
            at += 1usize
        }
        if g.fold_count != 0usize { ret fail(g, "a value was left on the operand stack at the end of its block") }
        if block_at + 1usize < count { block_end(g) }
        block_at += 1usize
    }
    if dispatch {
        block_end(g)
        op(g, 0usize)
    }
    ret ok
}

// ---- locals and the operand stack (C183) ----------------------------------------
//
// A NIR value is read by the instructions after its definition, nearly always inside the
// block that defines it. `plan_values` counts the reads, gives the values that live in one
// block a pool of locals to share (a slot is free again after the last read), and decides
// which single-read values can wait on the operand stack for their reader instead of being
// written to a local and read back. The decision is only a plan: `emit_folded` checks it
// against the code actually written.

fn alloc_words(g: *Gen, count: usize) -> ([]usize, err) {
    let (words, words_error) = mem.alloc[usize](g.a, count)
    if words_error != ok { ret (words, words_error) }
    var at = 0usize
    while at < count {
        words[at] = 0usize
        at += 1usize
    }
    ret (words, ok)
}

fn carve(words: []usize, index: usize, size: usize) -> []usize { ret words[index * size..(index + 1usize) * size] }

fn uleb_size(value: usize) -> usize {
    var size = 1usize
    var rest = value >> 7usize
    while rest != 0usize {
        size += 1usize
        rest = rest >> 7usize
    }
    ret size
}

fn note_definitions(g: *Gen, function: nir.Function) {
    var block_at = 0usize
    while block_at < function.block_count {
        let block = g.b.blocks[function.first_block + block_at]
        var at = block.first_instruction
        while at < block.first_instruction + block.instruction_count {
            let instruction = g.b.instructions[at]
            if instruction.has_result && instruction.result < function.value_count {
                g.pl_def_block[instruction.result] = block_at + 1usize
                g.pl_def_pos[instruction.result] = at
            }
            at += 1usize
        }
        block_at += 1usize
    }
}

// How often and by whom each value is read, and whether a read is outside its block.
fn note_uses(g: *Gen, function: nir.Function) -> err {
    var block_at = 0usize
    while block_at < function.block_count {
        let block = g.b.blocks[function.first_block + block_at]
        var at = block.first_instruction
        while at < block.first_instruction + block.instruction_count {
            let instruction = g.b.instructions[at]
            var k = 0usize
            while k < instruction.operand_count {
                let value = g.b.operands[instruction.first_operand + k]
                if value >= function.value_count { ret fail(g, "an operand outside its function") }
                g.fr_uses[value] += 1usize
                g.fr_user[value] = at
                if g.pl_def_block[value] != block_at + 1usize || g.pl_def_pos[value] >= at {
                    g.pl_cross[value] = 1usize
                } else {
                    g.pl_last_use[value] = at
                }
                k += 1usize
            }
            at += 1usize
        }
        block_at += 1usize
    }
    ret ok
}

// A value read outside its block has a local of its own; the others take a free one from the
// pool at their definition and give it back after their last read. The result of an
// instruction is given its slot before the instruction's operands let go of theirs, since the
// code of an instruction may write the result and then read an operand.
fn assign_slots(g: *Gen, function: nir.Function) {
    var crossing = 0usize
    var value = 0usize
    while value < function.value_count {
        if g.pl_cross[value] == 1usize {
            g.fr_slot[value] = crossing
            crossing += 1usize
        }
        value += 1usize
    }
    var peak = crossing
    var block_at = 0usize
    while block_at < function.block_count {
        var fresh = crossing
        var free_count = 0usize
        let block = g.b.blocks[function.first_block + block_at]
        var at = block.first_instruction
        while at < block.first_instruction + block.instruction_count {
            let instruction = g.b.instructions[at]
            if instruction.has_result && instruction.result < function.value_count && g.pl_cross[instruction.result] == 0usize {
                var slot = fresh
                if free_count != 0usize {
                    free_count = free_count - 1usize
                    slot = g.pl_free[free_count]
                } else {
                    fresh += 1usize
                }
                g.fr_slot[instruction.result] = slot
                if g.fr_uses[instruction.result] == 0usize {
                    g.pl_free[free_count] = slot
                    free_count += 1usize
                }
            }
            var k = 0usize
            while k < instruction.operand_count {
                let operand_value = g.b.operands[instruction.first_operand + k]
                if g.pl_cross[operand_value] == 0usize && g.pl_last_use[operand_value] == at {
                    g.pl_last_use[operand_value] = 0usize
                    g.pl_free[free_count] = g.fr_slot[operand_value]
                    free_count += 1usize
                }
                k += 1usize
            }
            at += 1usize
        }
        if fresh > peak { peak = fresh }
        block_at += 1usize
    }
    g.fr_slots = peak
}

fn fold_matches(g: *Gen, instruction: nir.Instruction, depth: usize, taken: usize) -> bool {
    var k = 0usize
    while k < taken {
        if g.pl_vstack[depth - taken + k] != operand(g, instruction, k) { ret false }
        k += 1usize
    }
    ret true
}

// The value leaves the plan's stack: it goes to its local after all.
fn unfold(g: *Gen, value: usize, depth: usize) -> usize {
    var at = 0usize
    while at < depth && g.pl_vstack[at] != value { at += 1usize }
    while at + 1usize < depth {
        g.pl_vstack[at] = g.pl_vstack[at + 1usize]
        at += 1usize
    }
    g.pl_on_stack[value] = 0usize
    g.fr_fold[value] = 0usize
    ret depth - 1usize
}

// An instruction reads the values waiting on the plan's stack that are its first operands, in
// order, and only if they are its topmost; any other waiting operand is stored instead.
fn consume_folds(g: *Gen, instruction: nir.Instruction, depth_in: usize) -> usize {
    var depth = depth_in
    let count = instruction.operand_count
    var lead = 0usize
    while lead < count && lead < depth && g.pl_on_stack[operand(g, instruction, lead)] == 1usize { lead += 1usize }
    var taken = lead
    while taken > 0usize && !fold_matches(g, instruction, depth, taken) { taken = taken - 1usize }
    var k = taken
    while k < count {
        let value = operand(g, instruction, k)
        if g.pl_on_stack[value] == 1usize { depth = unfold(g, value, depth) }
        k += 1usize
    }
    var popped = 0usize
    while popped < taken {
        g.pl_on_stack[g.pl_vstack[depth - 1usize - popped]] = 0usize
        popped += 1usize
    }
    ret depth - taken
}

fn plan_folds(g: *Gen, function: nir.Function) {
    var block_at = 0usize
    while block_at < function.block_count {
        let block = g.b.blocks[function.first_block + block_at]
        var depth = 0usize
        var at = block.first_instruction
        while at < block.first_instruction + block.instruction_count {
            let instruction = g.b.instructions[at]
            if depth != 0usize && instruction.operand_count != 0usize { depth = consume_folds(g, instruction, depth) }
            if instruction.has_result && instruction.result < function.value_count && depth < 32usize {
                let result = instruction.result
                if g.pl_cross[result] == 0usize && g.fr_uses[result] == 1usize && g.fr_user[result] > at {
                    g.pl_vstack[depth] = result
                    g.pl_on_stack[result] = 1usize
                    g.fr_fold[result] = 1usize
                    depth += 1usize
                }
            }
            at += 1usize
        }
        while depth != 0usize { depth = unfold(g, g.pl_vstack[depth - 1usize], depth) }
        block_at += 1usize
    }
}

fn plan_values(g: *Gen, function: nir.Function) -> err {
    let size = function.value_count + 80usize
    let (words, words_error) = alloc_words(g, size * 13usize)
    if words_error != ok { ret words_error }
    g.fr_slot = carve(words, 0usize, size)
    g.fr_uses = carve(words, 1usize, size)
    g.fr_user = carve(words, 2usize, size)
    g.fr_fold = carve(words, 3usize, size)
    g.fold_stack = carve(words, 4usize, size)
    g.pend = carve(words, 5usize, size)
    g.pl_def_block = carve(words, 6usize, size)
    g.pl_def_pos = carve(words, 7usize, size)
    g.pl_last_use = carve(words, 8usize, size)
    g.pl_cross = carve(words, 9usize, size)
    g.pl_on_stack = carve(words, 10usize, size)
    g.pl_free = carve(words, 11usize, size)
    g.pl_vstack = carve(words, 12usize, size)
    g.fold_count = 0usize
    g.fold_next = 0usize
    g.fold_end = 0usize
    g.fold_bad = false
    g.watch_on = false
    note_definitions(g, function)
    try note_uses(g, function)
    assign_slots(g, function)
    plan_folds(g, function)
    ret ok
}

// A branch's condition on the stack as an `i32`: the part of a conditional branch that reads
// a value.
fn emit_condition(g: *Gen, instruction: nir.Instruction) -> err {
    if instruction.operand_count != 1usize { ret fail(g, "a conditional branch without a condition") }
    vget(g, operand(g, instruction, 0usize))
    wrap(g)
    ret ok
}

// One instruction (`mode` 0) or the condition of a branch (`mode` 1), with the values that
// wait on the operand stack for it read from there. The plan is trusted only as far as the
// code bears it out: the waiting values are read only if the instruction's code reads them
// first, in order, once, with nothing written before the first; otherwise the topmost one
// that cannot be is stored to its local and the instruction is written again. Afterwards a
// value the plan wants kept on the stack stays there when the instruction's code ends with
// the one write of its local and never reads it.
fn emit_folded(g: *Gen, instruction: nir.Instruction, at: usize, mode: usize) -> err {
    if g.map_on { map_note(g, instruction.site, instruction.path, g.code.count) }
    var held = 0usize
    while held < g.fold_count && g.fr_user[g.fold_stack[g.fold_count - 1usize - held]] == at { held += 1usize }
    let base = g.fold_count - held
    var limit = held
    var track = false
    var result_slot = 0usize
    if mode == 0usize && instruction.has_result && g.fr_fold[instruction.result] == 1usize {
        track = true
        result_slot = local_value(g, instruction.result)
    }
    var attempt_start = g.code.count
    var settled = false
    while !settled {
        while g.fold_count > base + limit {
            g.fold_count = g.fold_count - 1usize
            let stored = g.fold_stack[g.fold_count]
            g.pend[g.fr_slot[stored]] = 0usize
            lset(g, local_value(g, stored))
        }
        attempt_start = g.code.count
        g.fold_start = attempt_start
        g.fold_next = base
        g.fold_end = base + limit
        g.fold_bad = false
        g.watch_on = track
        g.watch_slot = result_slot
        g.watch_sets = 0usize
        g.watch_gets = 0usize
        var written = ok
        if mode == 0usize { written = emit_instruction(g, instruction, at) } else { written = emit_condition(g, instruction) }
        g.watch_on = false
        if written != ok { ret written }
        let taken = g.fold_next - base
        if !g.fold_bad && taken == limit {
            settled = true
        } else {
            if limit == 0usize { ret fail(g, "a value waiting on the operand stack was read by an instruction that is not its reader") }
            var fewer = taken
            if fewer >= limit { fewer = limit - 1usize }
            g.code.count = attempt_start
            limit = fewer
        }
    }
    var released = base
    while released < base + limit {
        g.pend[g.fr_slot[g.fold_stack[released]]] = 0usize
        released += 1usize
    }
    g.fold_count = base
    g.fold_next = 0usize
    g.fold_end = 0usize
    if track && g.watch_sets == 1usize && g.watch_gets == 0usize && g.last_set_slot == result_slot && g.last_set_pos >= attempt_start && g.last_set_pos + 1usize + uleb_size(result_slot) == g.code.count {
        g.code.count = g.last_set_pos
        g.fold_stack[g.fold_count] = instruction.result
        g.fold_count += 1usize
        g.pend[g.fr_slot[instruction.result]] = instruction.result + 1usize
    }
    ret ok
}

// ---- the source map (C196) ------------------------------------------------------

// An entry at `offset` of the function being written when its line or file is not the last
// entry's; an entry at the same offset (an instruction that wrote nothing) is replaced.
fn map_note(g: *Gen, site: nir.Site, path: str, offset: usize) {
    if site.line == 0usize { ret }
    var source = 0usize
    var found = false
    while source < g.map_path_count && !found {
        if g.map_paths[source].len == path.len && check.same(g.map_paths[source], path) { found = true } else { source += 1usize }
    }
    if !found {
        if g.map_path_count >= g.map_paths.len || g.map_count >= g.map_line.len {
            g.map_full = true
            ret
        }
        g.map_paths[g.map_path_count] = path
        g.map_path_count += 1usize
    }
    var at = g.map_count
    if at != g.map_done {
        let last = at - 1usize
        if g.map_line[last] == site.line && g.map_source[last] == source { ret }
        if g.map_offset[last] == offset { at = last }
    }
    if at >= g.map_line.len {
        g.map_full = true
        ret
    }
    g.map_offset[at] = offset
    g.map_line[at] = site.line
    g.map_column[at] = site.column
    g.map_source[at] = source
    g.map_count = at + 1usize
}

// ---- a function ----------------------------------------------------------------

// The function's locals and prologue are written; its blocks follow (`emit_blocks` or the
// structured walk of wasm_flow.e), then `finish_function`.
fn begin_function(g: *Gen, function_index: usize) -> err {
    let function = g.b.functions[function_index]
    g.current = function
    let (parameters, parameters_error) = codegen_x64.parameter_count(g.b, function)
    if parameters_error != ok { ret fail(g, "a function whose parameters are not numbered in order") }
    g.fr_params = parameters
    try plan_frame(g, function)
    try plan_values(g, function)
    g.code.count = 0usize
    // One `i32` ($bb), then everything else `i64`, then three `v128` for a vector operation.
    if g.fr_vec { put_uleb(&g.code, 3usize) } else { put_uleb(&g.code, 2usize) }
    put_uleb(&g.code, 1usize)
    put(&g.code, 127usize)
    put_uleb(&g.code, 5usize + g.fr_slots + g.fr_aux_count)
    put(&g.code, 126usize)
    if g.fr_vec {
        put_uleb(&g.code, 3usize)
        put(&g.code, 123usize)
    }
    if g.map_on {
        g.map_count = g.map_done
        if function.instruction_count != 0usize {
            let first = g.b.instructions[function.first_instruction]
            map_note(g, first.site, first.path, 0usize)
        }
    }
    prologue(g, function)
    ret ok
}

// Every path of the body ends in a branch, a return or a trap; the `unreachable` is for the
// engine's validator, which cannot know that a function whose last construct is a loop does
// not run off its end.
fn finish_function(g: *Gen) -> err {
    op(g, 0usize)
    block_end(g)
    if g.code.full || g.data.full { ret fail(g, "the module outgrew the back end's storage") }
    if g.map_on {
        // From here an entry's offset is its byte in the code section's bodies.
        let base = g.bodies.count + uleb_size(g.code.count)
        while g.map_done < g.map_count {
            g.map_offset[g.map_done] = g.map_offset[g.map_done] + base
            g.map_done += 1usize
        }
    }
    put_uleb(&g.bodies, g.code.count)
    put_bytes(&g.bodies, &g.code)
    ret ok
}

fn put_decimal(o: *Out, value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    if rest == 0usize {
        at = at - 1usize
        digits[at] = 48u8
    }
    while rest != 0usize {
        at = at - 1usize
        digits[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
    }
    while at < 20usize {
        put(o, usize(digits[at]))
        at = at + 1usize
    }
}
