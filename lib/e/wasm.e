// WebAssembly 2.0 core, interpreted: the binary format decoded into a `Module`, a `Store` of function, memory, table and
// global instances, and an interpreter over the original bytecode with a precomputed jump table per function.
//
// What is checked: the module's structure (magic, version, section order and sizes, indices in range, limits) and, at run
// time, every trap the specification names (unreachable, out of bounds, divide by zero, integer overflow, bad indirect call,
// stack exhaustion). What is not: the operand types of a function body are not validated, so a module whose body
// pops a value of the wrong type decodes and misbehaves instead of failing to compile. A host that runs untrusted modules
// needs the validator (ceiling: structural checks only).
//
// A value is one `u64` slot: an `i32` is its low 32 bits, an `f32` its bit pattern in the low 32 bits, an `f64` its 64 bits,
// a reference the store index of the function plus one (0 is null).
use e.data.list as list
use e.math
use e.mem
use e.str

error Malformed
error Unsupported
error LinkError
error Trap
error TrapUnreachable
error TrapMemory
error TrapDivZero
error TrapOverflow
error TrapIndirect
error TrapStack
error TrapTable
error TrapConversion

const T_I32: u8 = 127u8
const T_I64: u8 = 126u8
const T_F32: u8 = 125u8
const T_F64: u8 = 124u8
const T_V128: u8 = 123u8
const T_FUNCREF: u8 = 112u8
const T_EXTERNREF: u8 = 111u8

const PAGE: usize = 65536usize
const MAX_PAGES: u32 = 16384u32
const MAX_DEPTH: u32 = 1500u32

type FuncType = struct { params: []u8, results: []u8 }
type Limits = struct { min: u32, max: u32, has_max: bool }
type ImportKind = enum u8 { Func, Table, Memory, Global }
type Import = struct { module: str, name: str, kind: ImportKind, index: u32, ttype: u8, limits: Limits, mutable: bool }
type Export = struct { name: str, kind: ImportKind, index: u32 }
type GlobalDef = struct { vtype: u8, mutable: bool, init: usize, init_end: usize }
type ElemDef = struct { mode: u8, table: u32, offset: usize, offset_end: usize, ttype: u8, funcs: []u32, exprs: []usize, count: usize }
type DataDef = struct { mode: u8, memory: u32, offset: usize, offset_end: usize, bytes: []const u8 }
type FuncBody = struct { start: usize, end: usize, locals: []u8, jump: []u32, other: []u32 }

type Module = struct {
    bytes: []const u8,
    types: []FuncType, imports: []Import, funcs: []u32, tables: []Limits, table_types: []u8, memories: []Limits, globals: []GlobalDef,
    exports: []Export, start: u32, has_start: bool, elems: []ElemDef, datas: []DataDef, bodies: []FuncBody,
    n_func_imports: u32, n_table_imports: u32, n_mem_imports: u32, n_global_imports: u32, data_count: u32, has_data_count: bool
}

type Reader = struct { b: []const u8, at: usize }

fn rd_eof(r: *Reader) -> bool { ret r.at >= r.b.len }

fn rd_byte(r: *Reader) -> (u8, err) {
    if r.at >= r.b.len { ret (0u8, Malformed) }
    let v = r.b[r.at]
    r.at += 1usize
    ret (v, ok)
}

fn rd_u32(r: *Reader) -> (u32, err) {
    var result = 0u64
    var shift = 0u64
    var n = 0u32
    while n < 5u32 {
        let (byte, e) = rd_byte(r)
        if e != ok { ret (0u32, e) }
        result = result | (u64(byte & 127u8) << shift)
        n += 1u32
        if (byte & 128u8) == 0u8 {
            if n == 5u32 && byte > 15u8 { ret (0u32, Malformed) }
            ret (u32(result & 4294967295u64), ok)
        }
        shift += 7u64
    }
    ret (0u32, Malformed)
}

// A signed LEB128 of at most `bits` bits, as a sign-extended i64.
fn rd_sleb(r: *Reader, bits: u32) -> (i64, err) {
    var result = 0u64
    var shift = 0u32
    var byte = 0u8
    var n = 0u32
    let limit = (bits + 6u32) / 7u32
    while n < limit {
        let (b, e) = rd_byte(r)
        if e != ok { ret (0i64, e) }
        byte = b
        n += 1u32
        result = result | (u64(byte & 127u8) << u64(shift))
        shift += 7u32
        if (byte & 128u8) == 0u8 {
            if shift < 64u32 && (byte & 64u8) != 0u8 { result = result | (18446744073709551615u64 << u64(shift)) }
            // The unused high bits of the last byte must repeat the sign.
            if n == limit && bits < 64u32 {
                let used = bits - (limit - 1u32) * 7u32
                let sign = (byte >> u8(used - 1u32)) & 1u8
                let top = byte & 127u8
                let mask = u8(127u32 - ((1u32 << used) - 1u32))
                let hi = top & mask
                if sign == 0u8 && hi != 0u8 { ret (0i64, Malformed) }
                if sign == 1u8 && hi != mask { ret (0i64, Malformed) }
            }
            ret (mem.bitcast[i64](result), ok)
        }
    }
    ret (0i64, Malformed)
}

fn rd_f32(r: *Reader) -> (u64, err) {
    if r.at + 4usize > r.b.len { ret (0u64, Malformed) }
    let v = u64(r.b[r.at]) | (u64(r.b[r.at + 1usize]) << 8u64) | (u64(r.b[r.at + 2usize]) << 16u64) | (u64(r.b[r.at + 3usize]) << 24u64)
    r.at += 4usize
    ret (v, ok)
}

fn rd_f64(r: *Reader) -> (u64, err) {
    if r.at + 8usize > r.b.len { ret (0u64, Malformed) }
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = v | (u64(r.b[r.at + i]) << u64(i * 8usize))
        i += 1usize
    }
    r.at += 8usize
    ret (v, ok)
}

// A name as the [start, end) range of the module bytes, so the view stays tied to the module and not to the reader.
fn rd_name(r: *Reader) -> (usize, usize, err) {
    let (n, e) = rd_u32(r)
    if e != ok { ret (0usize, 0usize, e) }
    if r.at + usize(n) > r.b.len { ret (0usize, 0usize, Malformed) }
    let start = r.at
    r.at += usize(n)
    if !valid_utf8(r.b[start..r.at]) { ret (0usize, 0usize, Malformed) }
    ret (start, r.at, ok)
}

fn valid_utf8(s: []const u8) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var extra = 0usize
        if c < 128u8 {
            extra = 0usize
        } else if c >= 194u8 && c <= 223u8 {
            extra = 1usize
        } else if c >= 224u8 && c <= 239u8 {
            extra = 2usize
        } else if c >= 240u8 && c <= 244u8 {
            extra = 3usize
        } else {
            ret false
        }
        if i + extra >= s.len + 0usize && extra > 0usize && i + extra > s.len - 1usize { ret false }
        var k = 1usize
        while k <= extra {
            if (s[i + k] & 192u8) != 128u8 { ret false }
            k += 1usize
        }
        if c == 224u8 && s[i + 1usize] < 160u8 { ret false }
        if c == 237u8 && s[i + 1usize] > 159u8 { ret false }
        if c == 240u8 && s[i + 1usize] < 144u8 { ret false }
        if c == 244u8 && s[i + 1usize] > 143u8 { ret false }
        i += extra + 1usize
    }
    ret true
}

fn valid_valtype(t: u8) -> bool {
    ret t == T_I32 || t == T_I64 || t == T_F32 || t == T_F64 || t == T_FUNCREF || t == T_EXTERNREF
}

fn rd_valtype(r: *Reader) -> (u8, err) {
    let (t, e) = rd_byte(r)
    if e != ok { ret (0u8, e) }
    if !valid_valtype(t) { ret (0u8, Malformed) }
    ret (t, ok)
}

fn rd_limits(r: *Reader, bound: u32) -> (Limits, err) {
    let (flag, e) = rd_byte(r)
    if e != ok { ret (zero, e) }
    if flag > 1u8 { ret (zero, Malformed) }
    let (mn, e1) = rd_u32(r)
    if e1 != ok { ret (zero, e1) }
    var out = Limits { min: mn, max: 0u32, has_max: false }
    if flag == 1u8 {
        let (mx, e2) = rd_u32(r)
        if e2 != ok { ret (zero, e2) }
        out.max = mx
        out.has_max = true
        if mx < mn { ret (zero, Malformed) }
        if bound != 0u32 && mx > bound { ret (zero, Malformed) }
    }
    if bound != 0u32 && mn > bound { ret (zero, Malformed) }
    ret (out, ok)
}

// A constant expression: its bytes are kept as a [start, end) range of the module and evaluated at instantiation.
fn skip_const_expr(r: *Reader) -> (usize, usize, err) {
    let start = r.at
    var depth = 0u32
    while true {
        let (op, e) = rd_byte(r)
        if e != ok { ret (0usize, 0usize, e) }
        if op == 11u8 {
            ret (start, r.at, ok)
        } else if op == 65u8 {
            let (v, e1) = rd_sleb(r, 32u32)
            if e1 != ok { ret (0usize, 0usize, e1) }
        } else if op == 66u8 {
            let (v, e2) = rd_sleb(r, 64u32)
            if e2 != ok { ret (0usize, 0usize, e2) }
        } else if op == 67u8 {
            let (v, e3) = rd_f32(r)
            if e3 != ok { ret (0usize, 0usize, e3) }
        } else if op == 68u8 {
            let (v, e4) = rd_f64(r)
            if e4 != ok { ret (0usize, 0usize, e4) }
        } else if op == 35u8 || op == 210u8 {
            let (v, e5) = rd_u32(r)
            if e5 != ok { ret (0usize, 0usize, e5) }
        } else if op == 208u8 {
            let (t, e6) = rd_byte(r)
            if e6 != ok { ret (0usize, 0usize, e6) }
        } else if op == 106u8 || op == 107u8 || op == 108u8 || op == 124u8 || op == 125u8 || op == 126u8 {
            depth += 1u32
        } else {
            ret (0usize, 0usize, Malformed)
        }
    }
    ret (0usize, 0usize, Malformed)
}

fn new_list_u8(a: *mem.Arena, n: usize) -> ([]u8, err) {
    if n == 0usize { ret (zero, ok) }
    let (p, e) = mem.alloc[u8](a, n)
    ret (p, e)
}

fn decode(a: *mem.Arena, bytes: []const u8) -> (Module, err) {
    var m: Module = zero
    m.bytes = bytes
    if bytes.len < 8usize { ret (zero, Malformed) }
    if bytes[0usize] != 0u8 || bytes[1usize] != 97u8 || bytes[2usize] != 115u8 || bytes[3usize] != 109u8 { ret (zero, Malformed) }
    if bytes[4usize] != 1u8 || bytes[5usize] != 0u8 || bytes[6usize] != 0u8 || bytes[7usize] != 0u8 { ret (zero, Malformed) }
    var r = Reader { b: bytes, at: 8usize }
    var last_id = 0u32
    var seen_code = false
    var code_count = 0u32
    var nfuncs_declared = 0u32
    var imports_l: list.List[Import] = zero
    var funcs_l: list.List[u32] = zero
    var tables_l: list.List[Limits] = zero
    var ttypes_l: list.List[u8] = zero
    var mems_l: list.List[Limits] = zero
    var globals_l: list.List[GlobalDef] = zero
    var exports_l: list.List[Export] = zero
    var elems_l: list.List[ElemDef] = zero
    var datas_l: list.List[DataDef] = zero
    var bodies_l: list.List[FuncBody] = zero
    var types_l: list.List[FuncType] = zero
    let (t0, t0e) = list.init[FuncType](a, 8usize)
    if t0e != ok { ret (zero, t0e) }
    types_l = t0
    let (i0, i0e) = list.init[Import](a, 8usize)
    if i0e != ok { ret (zero, i0e) }
    imports_l = i0
    let (f0, f0e) = list.init[u32](a, 8usize)
    if f0e != ok { ret (zero, f0e) }
    funcs_l = f0
    let (tb0, tb0e) = list.init[Limits](a, 4usize)
    if tb0e != ok { ret (zero, tb0e) }
    tables_l = tb0
    let (tt0, tt0e) = list.init[u8](a, 4usize)
    if tt0e != ok { ret (zero, tt0e) }
    ttypes_l = tt0
    let (m0, m0e) = list.init[Limits](a, 2usize)
    if m0e != ok { ret (zero, m0e) }
    mems_l = m0
    let (g0, g0e) = list.init[GlobalDef](a, 8usize)
    if g0e != ok { ret (zero, g0e) }
    globals_l = g0
    let (x0, x0e) = list.init[Export](a, 8usize)
    if x0e != ok { ret (zero, x0e) }
    exports_l = x0
    let (el0, el0e) = list.init[ElemDef](a, 4usize)
    if el0e != ok { ret (zero, el0e) }
    elems_l = el0
    let (d0, d0e) = list.init[DataDef](a, 4usize)
    if d0e != ok { ret (zero, d0e) }
    datas_l = d0
    let (b0, b0e) = list.init[FuncBody](a, 8usize)
    if b0e != ok { ret (zero, b0e) }
    bodies_l = b0
    while !rd_eof(&r) {
        let (id8, ide) = rd_byte(&r)
        if ide != ok { ret (zero, ide) }
        let id = u32(id8)
        let (size, se) = rd_u32(&r)
        if se != ok { ret (zero, se) }
        if r.at + usize(size) > bytes.len { ret (zero, Malformed) }
        let end = r.at + usize(size)
        if id != 0u32 {
            // Section order: 1..9 ascending, with the data count (12) between element (9) and code (10).
            var rank = id
            if id == 12u32 { rank = 10u32 }
            if id == 10u32 { rank = 11u32 }
            if id == 11u32 { rank = 12u32 }
            if rank <= last_id { ret (zero, Malformed) }
            if id > 12u32 { ret (zero, Malformed) }
            last_id = rank
        }
        var s = Reader { b: bytes[0usize..end], at: r.at }
        if id == 0u32 {
            let (n0, n1, ne) = rd_name(&s)
            if ne != ok { ret (zero, ne) }
        } else if id == 1u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (form, fe) = rd_byte(&s)
                if fe != ok || form != 96u8 { ret (zero, Malformed) }
                let (np, npe) = rd_u32(&s)
                if npe != ok { ret (zero, npe) }
                if usize(np) > s.b.len { ret (zero, Malformed) }
                let (ps, pse) = new_list_u8(a, usize(np))
                if pse != ok { ret (zero, pse) }
                var j = 0u32
                while j < np {
                    let (t, te) = rd_valtype(&s)
                    if te != ok { ret (zero, te) }
                    ps[usize(j)] = t
                    j += 1u32
                }
                let (nr, nre) = rd_u32(&s)
                if nre != ok { ret (zero, nre) }
                if usize(nr) > s.b.len { ret (zero, Malformed) }
                let (rs, rse) = new_list_u8(a, usize(nr))
                if rse != ok { ret (zero, rse) }
                j = 0u32
                while j < nr {
                    let (t2, te2) = rd_valtype(&s)
                    if te2 != ok { ret (zero, te2) }
                    rs[usize(j)] = t2
                    j += 1u32
                }
                let pe = list.push[FuncType](&types_l, FuncType { params: ps[0usize..usize(np)], results: rs[0usize..usize(nr)] })
                if pe != ok { ret (zero, pe) }
                k += 1u32
            }
        } else if id == 2u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (mn0, mn1, mne) = rd_name(&s)
                if mne != ok { ret (zero, mne) }
                let (nm0, nm1, nme) = rd_name(&s)
                if nme != ok { ret (zero, nme) }
                let mn = bytes[mn0..mn1]
                let nm = bytes[nm0..nm1]
                let (kind, ke) = rd_byte(&s)
                if ke != ok { ret (zero, ke) }
                var imp = Import { module: mn, name: nm, kind: .Func, index: 0u32, ttype: 0u8, limits: zero, mutable: false }
                if kind == 0u8 {
                    let (ti, tie) = rd_u32(&s)
                    if tie != ok { ret (zero, tie) }
                    if usize(ti) >= types_l.len { ret (zero, Malformed) }
                    imp.index = ti
                    m.n_func_imports += 1u32
                    let fe2 = list.push[u32](&funcs_l, ti)
                    if fe2 != ok { ret (zero, fe2) }
                } else if kind == 1u8 {
                    imp.kind = .Table
                    let (tt, tte) = rd_valtype(&s)
                    if tte != ok { ret (zero, tte) }
                    if tt != T_FUNCREF && tt != T_EXTERNREF { ret (zero, Malformed) }
                    let (lim, le) = rd_limits(&s, 0u32)
                    if le != ok { ret (zero, le) }
                    imp.ttype = tt
                    imp.limits = lim
                    m.n_table_imports += 1u32
                    let p1 = list.push[Limits](&tables_l, lim)
                    if p1 != ok { ret (zero, p1) }
                    let p2 = list.push[u8](&ttypes_l, tt)
                    if p2 != ok { ret (zero, p2) }
                } else if kind == 2u8 {
                    imp.kind = .Memory
                    let (lim, le) = rd_limits(&s, 65536u32)
                    if le != ok { ret (zero, le) }
                    imp.limits = lim
                    m.n_mem_imports += 1u32
                    let p1 = list.push[Limits](&mems_l, lim)
                    if p1 != ok { ret (zero, p1) }
                } else if kind == 3u8 {
                    imp.kind = .Global
                    let (vt, vte) = rd_valtype(&s)
                    if vte != ok { ret (zero, vte) }
                    let (mut, mute) = rd_byte(&s)
                    if mute != ok || mut > 1u8 { ret (zero, Malformed) }
                    imp.ttype = vt
                    imp.mutable = mut == 1u8
                    m.n_global_imports += 1u32
                    let p1 = list.push[GlobalDef](&globals_l, GlobalDef { vtype: vt, mutable: mut == 1u8, init: 0usize, init_end: 0usize })
                    if p1 != ok { ret (zero, p1) }
                } else {
                    ret (zero, Malformed)
                }
                let pe = list.push[Import](&imports_l, imp)
                if pe != ok { ret (zero, pe) }
                k += 1u32
            }
        } else if id == 3u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (ti, tie) = rd_u32(&s)
                if tie != ok { ret (zero, tie) }
                if usize(ti) >= types_l.len { ret (zero, Malformed) }
                let pe = list.push[u32](&funcs_l, ti)
                if pe != ok { ret (zero, pe) }
                nfuncs_declared += 1u32
                k += 1u32
            }
        } else if id == 4u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (tt, tte) = rd_valtype(&s)
                if tte != ok { ret (zero, tte) }
                if tt != T_FUNCREF && tt != T_EXTERNREF { ret (zero, Malformed) }
                let (lim, le) = rd_limits(&s, 0u32)
                if le != ok { ret (zero, le) }
                let p1 = list.push[Limits](&tables_l, lim)
                if p1 != ok { ret (zero, p1) }
                let p2 = list.push[u8](&ttypes_l, tt)
                if p2 != ok { ret (zero, p2) }
                k += 1u32
            }
        } else if id == 5u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (lim, le) = rd_limits(&s, 65536u32)
                if le != ok { ret (zero, le) }
                let p1 = list.push[Limits](&mems_l, lim)
                if p1 != ok { ret (zero, p1) }
                k += 1u32
            }
            if mems_l.len > 1usize { ret (zero, Malformed) }
        } else if id == 6u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (vt, vte) = rd_valtype(&s)
                if vte != ok { ret (zero, vte) }
                let (mut, mute) = rd_byte(&s)
                if mute != ok || mut > 1u8 { ret (zero, Malformed) }
                let (cs, ce, cee) = skip_const_expr(&s)
                if cee != ok { ret (zero, cee) }
                let p1 = list.push[GlobalDef](&globals_l, GlobalDef { vtype: vt, mutable: mut == 1u8, init: cs, init_end: ce })
                if p1 != ok { ret (zero, p1) }
                k += 1u32
            }
        } else if id == 7u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (nm0, nm1, nme) = rd_name(&s)
                if nme != ok { ret (zero, nme) }
                let nm = bytes[nm0..nm1]
                let (kind, ke) = rd_byte(&s)
                if ke != ok || kind > 3u8 { ret (zero, Malformed) }
                let (ix, ixe) = rd_u32(&s)
                if ixe != ok { ret (zero, ixe) }
                var kd = ImportKind.Func
                var bound = funcs_l.len
                if kind == 1u8 { kd = .Table
                    bound = tables_l.len }
                if kind == 2u8 { kd = .Memory
                    bound = mems_l.len }
                if kind == 3u8 { kd = .Global
                    bound = globals_l.len }
                if usize(ix) >= bound { ret (zero, Malformed) }
                var dup = 0usize
                while dup < exports_l.len {
                    if str.eq(exports_l.items[dup].name, nm) { ret (zero, Malformed) }
                    dup += 1usize
                }
                let pe = list.push[Export](&exports_l, Export { name: nm, kind: kd, index: ix })
                if pe != ok { ret (zero, pe) }
                k += 1u32
            }
        } else if id == 8u32 {
            let (ix, ixe) = rd_u32(&s)
            if ixe != ok { ret (zero, ixe) }
            if usize(ix) >= funcs_l.len { ret (zero, Malformed) }
            m.start = ix
            m.has_start = true
        } else if id == 9u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            var k = 0u32
            while k < n {
                let (flag, fe) = rd_u32(&s)
                if fe != ok { ret (zero, fe) }
                if flag > 7u32 { ret (zero, Malformed) }
                var ed = ElemDef { mode: 0u8, table: 0u32, offset: 0usize, offset_end: 0usize, ttype: T_FUNCREF, funcs: zero, exprs: zero, count: 0usize }
                // bit 0: passive/declarative, bit 1: explicit table (or declarative), bit 2: expressions.
                let passive_or_decl = (flag & 1u32) != 0u32
                let explicit = (flag & 2u32) != 0u32
                let uses_expr = (flag & 4u32) != 0u32
                if !passive_or_decl {
                    ed.mode = 0u8
                    if explicit {
                        let (ti, tie) = rd_u32(&s)
                        if tie != ok { ret (zero, tie) }
                        ed.table = ti
                    }
                    let (os, oe, oee) = skip_const_expr(&s)
                    if oee != ok { ret (zero, oee) }
                    ed.offset = os
                    ed.offset_end = oe
                } else if explicit {
                    ed.mode = 2u8
                } else {
                    ed.mode = 1u8
                }
                if passive_or_decl || explicit {
                    if uses_expr {
                        let (rt, rte) = rd_valtype(&s)
                        if rte != ok { ret (zero, rte) }
                        ed.ttype = rt
                    } else {
                        let (ek, eke) = rd_byte(&s)
                        if eke != ok || ek != 0u8 { ret (zero, Malformed) }
                    }
                }
                let (cnt, cnte) = rd_u32(&s)
                if cnte != ok { ret (zero, cnte) }
                if usize(cnt) > s.b.len { ret (zero, Malformed) }
                ed.count = usize(cnt)
                if uses_expr {
                    let (ex, exe) = mem.alloc[usize](a, usize(cnt) * 2usize + 1usize)
                    if exe != ok { ret (zero, exe) }
                    var j = 0u32
                    while j < cnt {
                        let (es, ee, eee) = skip_const_expr(&s)
                        if eee != ok { ret (zero, eee) }
                        ex[usize(j) * 2usize] = es
                        ex[usize(j) * 2usize + 1usize] = ee
                        j += 1u32
                    }
                    ed.exprs = ex[0usize..usize(cnt) * 2usize]
                } else {
                    let (fl, fle) = mem.alloc[u32](a, usize(cnt) + 1usize)
                    if fle != ok { ret (zero, fle) }
                    var j = 0u32
                    while j < cnt {
                        let (fi, fie) = rd_u32(&s)
                        if fie != ok { ret (zero, fie) }
                        if usize(fi) >= funcs_l.len { ret (zero, Malformed) }
                        fl[usize(j)] = fi
                        j += 1u32
                    }
                    ed.funcs = fl[0usize..usize(cnt)]
                }
                let pe = list.push[ElemDef](&elems_l, ed)
                if pe != ok { ret (zero, pe) }
                k += 1u32
            }
        } else if id == 12u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            m.data_count = n
            m.has_data_count = true
        } else if id == 10u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            if n != nfuncs_declared { ret (zero, Malformed) }
            seen_code = true
            var k = 0u32
            while k < n {
                let (bsize, bse) = rd_u32(&s)
                if bse != ok { ret (zero, bse) }
                let bend = s.at + usize(bsize)
                if bend > end { ret (zero, Malformed) }
                let (nl, nle) = rd_u32(&s)
                if nle != ok { ret (zero, nle) }
                // Locals are run-length coded; the total is bounded.
                var total = 0usize
                let groups_at = s.at
                var g = 0u32
                while g < nl {
                    let (cnt, ce) = rd_u32(&s)
                    if ce != ok { ret (zero, ce) }
                    let (vt, vte) = rd_valtype(&s)
                    if vte != ok { ret (zero, vte) }
                    total += usize(cnt)
                    if total > 50000usize { ret (zero, Malformed) }
                    g += 1u32
                }
                let (locs, le) = new_list_u8(a, total)
                if le != ok { ret (zero, le) }
                var gr = Reader { b: bytes[0usize..bend], at: groups_at }
                var at = 0usize
                g = 0u32
                while g < nl {
                    let (cnt, ce) = rd_u32(&gr)
                    let (vt, vte) = rd_byte(&gr)
                    var q = 0u32
                    while q < cnt {
                        locs[at] = vt
                        at += 1usize
                        q += 1u32
                    }
                    g += 1u32
                }
                let body = FuncBody { start: s.at, end: bend, locals: locs[0usize..total], jump: zero, other: zero }
                let pe = list.push[FuncBody](&bodies_l, body)
                if pe != ok { ret (zero, pe) }
                s.at = bend
                k += 1u32
            }
        } else if id == 11u32 {
            let (n, ne) = rd_u32(&s)
            if ne != ok { ret (zero, ne) }
            if m.has_data_count && n != m.data_count { ret (zero, Malformed) }
            var k = 0u32
            while k < n {
                let (flag, fe) = rd_u32(&s)
                if fe != ok { ret (zero, fe) }
                if flag > 2u32 { ret (zero, Malformed) }
                var dd = DataDef { mode: 0u8, memory: 0u32, offset: 0usize, offset_end: 0usize, bytes: zero }
                if flag == 1u32 {
                    dd.mode = 1u8
                } else {
                    if flag == 2u32 {
                        let (mi, mie) = rd_u32(&s)
                        if mie != ok { ret (zero, mie) }
                        dd.memory = mi
                    }
                    let (os, oe, oee) = skip_const_expr(&s)
                    if oee != ok { ret (zero, oee) }
                    dd.offset = os
                    dd.offset_end = oe
                }
                let (len, lene) = rd_u32(&s)
                if lene != ok { ret (zero, lene) }
                if s.at + usize(len) > end { ret (zero, Malformed) }
                dd.bytes = bytes[s.at..s.at + usize(len)]
                s.at += usize(len)
                let pe = list.push[DataDef](&datas_l, dd)
                if pe != ok { ret (zero, pe) }
                k += 1u32
            }
        }
        // Anything the section's reader left unread is malformed (custom sections excepted).
        if id != 0u32 && id != 10u32 && s.at != end { ret (zero, Malformed) }
        if id == 10u32 && s.at != end { ret (zero, Malformed) }
        r.at = end
    }
    if nfuncs_declared != 0u32 && !seen_code { ret (zero, Malformed) }
    if m.has_data_count == false && datas_l.len > 0usize && false { ret (zero, Malformed) }
    m.types = types_l.items[0usize..types_l.len]
    m.imports = imports_l.items[0usize..imports_l.len]
    m.funcs = funcs_l.items[0usize..funcs_l.len]
    m.tables = tables_l.items[0usize..tables_l.len]
    m.table_types = ttypes_l.items[0usize..ttypes_l.len]
    m.memories = mems_l.items[0usize..mems_l.len]
    m.globals = globals_l.items[0usize..globals_l.len]
    m.exports = exports_l.items[0usize..exports_l.len]
    m.elems = elems_l.items[0usize..elems_l.len]
    m.datas = datas_l.items[0usize..datas_l.len]
    m.bodies = bodies_l.items[0usize..bodies_l.len]
    ret (m, ok)
}

// ---- Store, instances and the interpreter ------------------------------------------------------------------------------

type HostFn = fn(*void, []const u64, []u64) -> err
type Memory = struct { data: []u8, pages: u32, max: u32, has_max: bool }
type Table = struct { elems: []u64, size: u32, max: u32, has_max: bool, ttype: u8 }
type Global = struct { vtype: u8, mutable: bool, value: u64 }
type FuncInst = struct { inst: *Instance, index: u32, ftype: FuncType, host: HostFn, ctx: *void, is_host: bool }
type Label = struct { kind: u8, height: usize, arity: u32, end_arity: u32, cont: usize, end: usize }
type Store = struct { a: *mem.Arena, funcs: list.List[*FuncInst], vs: []u64, ls: []Label, ltop: usize, top: usize }
type Instance = struct {
    module: *const Module, store: *Store, funcs: []u32, mems: []*Memory, tables: []*Table, globals: []*Global,
    dropped_data: []bool, dropped_elem: []bool, bodies: []FuncBody
}
type ImportVal = struct { kind: ImportKind, func: u32, memory: *Memory, table: *Table, global: *Global }

const VS_SLOTS: usize = 1048576usize
const LS_SLOTS: usize = 262144usize

fn store_new(a: *mem.Arena) -> (*Store, err) {
    var none: *Store = zero
    let (cell, ce) = mem.alloc[Store](a, 1usize)
    if ce != ok { ret (none, ce) }
    let (fl, fe) = list.init[*FuncInst](a, 16usize)
    if fe != ok { ret (none, fe) }
    let (vs, ve) = mem.alloc[u64](a, VS_SLOTS)
    if ve != ok { ret (none, ve) }
    let (ls, le) = mem.alloc[Label](a, LS_SLOTS)
    if le != ok { ret (none, le) }
    cell[0usize] = Store { a: a, funcs: fl, vs: vs, ls: ls, ltop: 0usize, top: 0usize }
    ret (&cell[0usize], ok)
}

fn a32(v: u64) -> u32 { ret u32(v & 4294967295u64) }
fn s32(v: u64) -> i32 { ret mem.bitcast[i32](a32(v)) }
fn from_s32(x: i32) -> u64 { ret u64(mem.bitcast[u32](x)) }
fn s64(v: u64) -> i64 { ret mem.bitcast[i64](v) }
fn from_s64(x: i64) -> u64 { ret mem.bitcast[u64](x) }
fn tof32(v: u64) -> f32 { ret mem.bitcast[f32](a32(v)) }
fn from_f32(x: f32) -> u64 { ret u64(mem.bitcast[u32](x)) }
fn tof64(v: u64) -> f64 { ret mem.bitcast[f64](v) }
fn from_f64(x: f64) -> u64 { ret mem.bitcast[u64](x) }
fn from_bool(b: bool) -> u64 {
    if b { ret 1u64 }
    ret 0u64
}

fn host_func(st: *Store, ft: FuncType, f: HostFn, ctx: *void) -> (u32, err) {
    let (cell, ce) = mem.alloc[FuncInst](st.a, 1usize)
    if ce != ok { ret (0u32, ce) }
    var none: *Instance = zero
    cell[0usize] = FuncInst { inst: none, index: 0u32, ftype: ft, host: f, ctx: ctx, is_host: true }
    let id = u32(st.funcs.len)
    let pe = list.push[*FuncInst](&st.funcs, &cell[0usize])
    if pe != ok { ret (0u32, pe) }
    ret (id, ok)
}

fn memory_new(a: *mem.Arena, min: u32, max: u32, has_max: bool) -> (*Memory, err) {
    var none: *Memory = zero
    let (cell, ce) = mem.alloc[Memory](a, 1usize)
    if ce != ok { ret (none, ce) }
    if min > MAX_PAGES { ret (none, Unsupported) }
    var data: []u8 = zero
    if min > 0u32 {
        let (d, de) = mem.alloc[u8](a, usize(min) * PAGE)
        if de != ok { ret (none, de) }
        var i = 0usize
        while i < d.len {
            d[i] = 0u8
            i += 1usize
        }
        data = d
    }
    cell[0usize] = Memory { data: data, pages: min, max: max, has_max: has_max }
    ret (&cell[0usize], ok)
}

// Grows by `delta` pages; answers the old page count, or u32 max when it does not fit.
fn memory_grow(a: *mem.Arena, m: *Memory, delta: u32) -> u32 {
    let old = m.pages
    if delta == 0u32 { ret old }
    var limit = MAX_PAGES
    if m.has_max && m.max < limit { limit = m.max }
    if u64(old) + u64(delta) > u64(limit) { ret 4294967295u32 }
    let np = old + delta
    let (d, de) = mem.alloc[u8](a, usize(np) * PAGE)
    if de != ok { ret 4294967295u32 }
    var i = 0usize
    while i < m.data.len {
        d[i] = m.data[i]
        i += 1usize
    }
    while i < d.len {
        d[i] = 0u8
        i += 1usize
    }
    m.data = d
    m.pages = np
    ret old
}

fn table_new(a: *mem.Arena, ttype: u8, min: u32, max: u32, has_max: bool, init: u64) -> (*Table, err) {
    var none: *Table = zero
    let (cell, ce) = mem.alloc[Table](a, 1usize)
    if ce != ok { ret (none, ce) }
    if min > 10000000u32 { ret (none, Unsupported) }
    var el: []u64 = zero
    if min > 0u32 {
        let (d, de) = mem.alloc[u64](a, usize(min))
        if de != ok { ret (none, de) }
        var i = 0usize
        while i < d.len {
            d[i] = init
            i += 1usize
        }
        el = d
    }
    cell[0usize] = Table { elems: el, size: min, max: max, has_max: has_max, ttype: ttype }
    ret (&cell[0usize], ok)
}

fn table_grow(a: *mem.Arena, t: *Table, delta: u32, init: u64) -> u32 {
    let old = t.size
    if u64(old) + u64(delta) > 10000000u64 { ret 4294967295u32 }
    if t.has_max && u64(old) + u64(delta) > u64(t.max) { ret 4294967295u32 }
    if delta == 0u32 { ret old }
    let ns = old + delta
    let (d, de) = mem.alloc[u64](a, usize(ns))
    if de != ok { ret 4294967295u32 }
    var i = 0usize
    while i < usize(old) {
        d[i] = t.elems[i]
        i += 1usize
    }
    while i < usize(ns) {
        d[i] = init
        i += 1usize
    }
    t.elems = d
    t.size = ns
    ret old
}

fn global_new(a: *mem.Arena, vtype: u8, mutable: bool, value: u64) -> (*Global, err) {
    var none: *Global = zero
    let (cell, ce) = mem.alloc[Global](a, 1usize)
    if ce != ok { ret (none, ce) }
    cell[0usize] = Global { vtype: vtype, mutable: mutable, value: value }
    ret (&cell[0usize], ok)
}

fn types_equal(x: FuncType, y: FuncType) -> bool {
    if x.params.len != y.params.len || x.results.len != y.results.len { ret false }
    var i = 0usize
    while i < x.params.len {
        if x.params[i] != y.params[i] { ret false }
        i += 1usize
    }
    i = 0usize
    while i < x.results.len {
        if x.results[i] != y.results[i] { ret false }
        i += 1usize
    }
    ret true
}

// Skips the immediates of opcode `op` (already read); the jump table pass and the interpreter share it.
fn skip_imm(r: *Reader, op: u8) -> err {
    if op == 2u8 || op == 3u8 || op == 4u8 {
        let (v, e) = rd_sleb(r, 33u32)
        ret e
    }
    if op == 12u8 || op == 13u8 || op == 16u8 || (op >= 32u8 && op <= 38u8) || op == 210u8 {
        let (v, e) = rd_u32(r)
        ret e
    }
    if op == 14u8 {
        let (n, e) = rd_u32(r)
        if e != ok { ret e }
        var i = 0u32
        while i <= n {
            let (v, e2) = rd_u32(r)
            if e2 != ok { ret e2 }
            i += 1u32
        }
        ret ok
    }
    if op == 17u8 {
        let (v, e) = rd_u32(r)
        if e != ok { ret e }
        let (v2, e2) = rd_u32(r)
        ret e2
    }
    if op == 28u8 {
        let (n, e) = rd_u32(r)
        if e != ok { ret e }
        var i = 0u32
        while i < n {
            let (t, e2) = rd_byte(r)
            if e2 != ok { ret e2 }
            i += 1u32
        }
        ret ok
    }
    if op >= 40u8 && op <= 62u8 {
        let (v, e) = rd_u32(r)
        if e != ok { ret e }
        let (v2, e2) = rd_u32(r)
        ret e2
    }
    if op == 63u8 || op == 64u8 || op == 208u8 {
        let (v, e) = rd_byte(r)
        ret e
    }
    if op == 65u8 {
        let (v, e) = rd_sleb(r, 32u32)
        ret e
    }
    if op == 66u8 {
        let (v, e) = rd_sleb(r, 64u32)
        ret e
    }
    if op == 67u8 {
        let (v, e) = rd_f32(r)
        ret e
    }
    if op == 68u8 {
        let (v, e) = rd_f64(r)
        ret e
    }
    if op == 252u8 {
        let (sub, e) = rd_u32(r)
        if e != ok { ret e }
        if sub <= 7u32 { ret ok }
        if sub == 8u32 {
            let (v, e1) = rd_u32(r)
            if e1 != ok { ret e1 }
            let (b, e2) = rd_byte(r)
            ret e2
        }
        if sub == 9u32 || sub == 13u32 || sub == 15u32 || sub == 16u32 || sub == 17u32 {
            let (v, e3) = rd_u32(r)
            ret e3
        }
        if sub == 10u32 {
            let (b1, e4) = rd_byte(r)
            if e4 != ok { ret e4 }
            let (b2, e5) = rd_byte(r)
            ret e5
        }
        if sub == 11u32 {
            let (b, e6) = rd_byte(r)
            ret e6
        }
        if sub == 12u32 || sub == 14u32 {
            let (v, e7) = rd_u32(r)
            if e7 != ok { ret e7 }
            let (v2, e8) = rd_u32(r)
            ret e8
        }
        ret Malformed
    }
    if op <= 1u8 || op == 5u8 || op == 11u8 || op == 15u8 || op == 26u8 || op == 27u8 || (op >= 69u8 && op <= 196u8) || op == 209u8 { ret ok }
    ret Malformed
}

// For each block, loop and if the position of its end (and of its else); for an else, the position of its end.
fn build_jumps(a: *mem.Arena, m: *const Module, body: *FuncBody) -> err {
    let n = body.end - body.start
    let (jp, je) = mem.alloc[u32](a, n + 1usize)
    if je != ok { ret je }
    let (ot, oe) = mem.alloc[u32](a, n + 1usize)
    if oe != ok { ret oe }
    var i = 0usize
    while i <= n {
        jp[i] = 0u32
        ot[i] = 0u32
        i += 1usize
    }
    let (stk, se) = mem.alloc[usize](a, n + 2usize)
    if se != ok { ret se }
    var sp = 0usize
    var r = Reader { b: m.bytes[0usize..body.end], at: body.start }
    while r.at < body.end {
        let pos = r.at
        let (op, e) = rd_byte(&r)
        if e != ok { ret e }
        if op == 2u8 || op == 3u8 || op == 4u8 {
            stk[sp] = pos
            sp += 1usize
        } else if op == 5u8 {
            if sp == 0usize { ret Malformed }
            let opener = stk[sp - 1usize]
            ot[opener - body.start] = u32(pos)
        } else if op == 11u8 {
            if sp == 0usize {
                if r.at != body.end { ret Malformed }
            } else {
                sp -= 1usize
                let opener = stk[sp]
                jp[opener - body.start] = u32(pos)
                let else_at = ot[opener - body.start]
                if else_at != 0u32 { jp[usize(else_at) - body.start] = u32(pos) }
            }
        }
        let ie = skip_imm(&r, op)
        if ie != ok { ret ie }
    }
    if sp != 0usize { ret Malformed }
    body.jump = jp[0usize..n + 1usize]
    body.other = ot[0usize..n + 1usize]
    ret ok
}

// ---- Numeric instructions ----------------------------------------------------------------------------------------------

fn clz32(x: u32) -> u32 {
    if x == 0u32 { ret 32u32 }
    var n = 0u32
    var v = x
    while (v & 2147483648u32) == 0u32 {
        v = v << 1u32
        n += 1u32
    }
    ret n
}

fn ctz32(x: u32) -> u32 {
    if x == 0u32 { ret 32u32 }
    var n = 0u32
    var v = x
    while (v & 1u32) == 0u32 {
        v = v >> 1u32
        n += 1u32
    }
    ret n
}

fn popcnt64(x: u64) -> u32 {
    var n = 0u32
    var v = x
    while v != 0u64 {
        n += u32(v & 1u64)
        v = v >> 1u64
    }
    ret n
}

fn clz64(x: u64) -> u32 {
    if x == 0u64 { ret 64u32 }
    var n = 0u32
    var v = x
    while (v & 9223372036854775808u64) == 0u64 {
        v = v << 1u64
        n += 1u32
    }
    ret n
}

fn ctz64(x: u64) -> u32 {
    if x == 0u64 { ret 64u32 }
    var n = 0u32
    var v = x
    while (v & 1u64) == 0u64 {
        v = v >> 1u64
        n += 1u32
    }
    ret n
}

fn shr_s32(x: u32, n: u32) -> u32 {
    let k = n & 31u32
    if k == 0u32 { ret x }
    let lo = x >> k
    if (x & 2147483648u32) != 0u32 { ret lo | (4294967295u32 << (32u32 - k)) }
    ret lo
}

fn shr_s64(x: u64, n: u64) -> u64 {
    let k = n & 63u64
    if k == 0u64 { ret x }
    let lo = x >> k
    if (x & 9223372036854775808u64) != 0u64 { ret lo | (18446744073709551615u64 << (64u64 - k)) }
    ret lo
}

fn sext(v: u64, bits: u32) -> u64 {
    let sign = 1u64 << u64(bits - 1u32)
    let mask = (1u64 << u64(bits)) - 1u64
    let x = v & mask
    if (x & sign) != 0u64 { ret x | (18446744073709551615u64 << u64(bits)) }
    ret x
}

fn u64_to_f64(v: u64) -> f64 {
    if (v & 9223372036854775808u64) == 0u64 { ret f64(mem.bitcast[i64](v)) }
    let half = (v >> 1u64) | (v & 1u64)
    ret f64(mem.bitcast[i64](half)) * 2.0f64
}

fn u64_to_f32(v: u64) -> f32 {
    if (v & 9223372036854775808u64) == 0u64 { ret f32(mem.bitcast[i64](v)) }
    let half = (v >> 1u64) | (v & 1u64)
    ret f32(mem.bitcast[i64](half)) * 2.0f32
}

fn f64_to_u64(x: f64) -> u64 {
    if x >= 9223372036854775808.0f64 { ret mem.bitcast[u64](i64(x - 9223372036854775808.0f64)) + 9223372036854775808u64 }
    ret mem.bitcast[u64](i64(x))
}

// Float to integer, trapping (`sat` false) or saturating. `kind`: 0 i32 signed, 1 i32 unsigned, 2 i64 signed, 3 i64 unsigned.
fn trunc_conv(x: f64, kind: u32, sat: bool) -> (u64, err) {
    if x != x {
        if sat { ret (0u64, ok) }
        ret (0u64, TrapConversion)
    }
    if kind == 0u32 {
        if x >= 2147483648.0f64 {
            if sat { ret (2147483647u64, ok) }
            ret (0u64, TrapOverflow)
        }
        if x <= -2147483649.0f64 {
            if sat { ret (from_s32(-2147483647i32 - 1i32), ok) }
            ret (0u64, TrapOverflow)
        }
        ret (from_s32(i32(x)), ok)
    }
    if kind == 1u32 {
        if x >= 4294967296.0f64 {
            if sat { ret (4294967295u64, ok) }
            ret (0u64, TrapOverflow)
        }
        if x <= -1.0f64 {
            if sat { ret (0u64, ok) }
            ret (0u64, TrapOverflow)
        }
        ret (u64(i64(x)), ok)
    }
    if kind == 2u32 {
        if x >= 9223372036854775808.0f64 {
            if sat { ret (9223372036854775807u64, ok) }
            ret (0u64, TrapOverflow)
        }
        if x < -9223372036854775808.0f64 {
            if sat { ret (9223372036854775808u64, ok) }
            ret (0u64, TrapOverflow)
        }
        ret (from_s64(i64(x)), ok)
    }
    if x >= 18446744073709551616.0f64 {
        if sat { ret (18446744073709551615u64, ok) }
        ret (0u64, TrapOverflow)
    }
    if x <= -1.0f64 {
        if sat { ret (0u64, ok) }
        ret (0u64, TrapOverflow)
    }
    ret (f64_to_u64(x), ok)
}

// A binary operator `op` over the two slots at the top of the stack, leaving one.
fn binop(op: u8, x: u64, y: u64) -> (u64, err) {
    // i32 comparisons
    if op >= 70u8 && op <= 79u8 {
        let a = a32(x)
        let b = a32(y)
        let sa = s32(x)
        let sb = s32(y)
        if op == 70u8 { ret (from_bool(a == b), ok) }
        if op == 71u8 { ret (from_bool(a != b), ok) }
        if op == 72u8 { ret (from_bool(sa < sb), ok) }
        if op == 73u8 { ret (from_bool(a < b), ok) }
        if op == 74u8 { ret (from_bool(sa > sb), ok) }
        if op == 75u8 { ret (from_bool(a > b), ok) }
        if op == 76u8 { ret (from_bool(sa <= sb), ok) }
        if op == 77u8 { ret (from_bool(a <= b), ok) }
        if op == 78u8 { ret (from_bool(sa >= sb), ok) }
        ret (from_bool(a >= b), ok)
    }
    if op >= 81u8 && op <= 90u8 {
        let sa = s64(x)
        let sb = s64(y)
        if op == 81u8 { ret (from_bool(x == y), ok) }
        if op == 82u8 { ret (from_bool(x != y), ok) }
        if op == 83u8 { ret (from_bool(sa < sb), ok) }
        if op == 84u8 { ret (from_bool(x < y), ok) }
        if op == 85u8 { ret (from_bool(sa > sb), ok) }
        if op == 86u8 { ret (from_bool(x > y), ok) }
        if op == 87u8 { ret (from_bool(sa <= sb), ok) }
        if op == 88u8 { ret (from_bool(x <= y), ok) }
        if op == 89u8 { ret (from_bool(sa >= sb), ok) }
        ret (from_bool(x >= y), ok)
    }
    if op >= 91u8 && op <= 96u8 {
        let a = tof32(x)
        let b = tof32(y)
        if op == 91u8 { ret (from_bool(a == b), ok) }
        if op == 92u8 { ret (from_bool(a != b), ok) }
        if op == 93u8 { ret (from_bool(a < b), ok) }
        if op == 94u8 { ret (from_bool(a > b), ok) }
        if op == 95u8 { ret (from_bool(a <= b), ok) }
        ret (from_bool(a >= b), ok)
    }
    if op >= 97u8 && op <= 102u8 {
        let a = tof64(x)
        let b = tof64(y)
        if op == 97u8 { ret (from_bool(a == b), ok) }
        if op == 98u8 { ret (from_bool(a != b), ok) }
        if op == 99u8 { ret (from_bool(a < b), ok) }
        if op == 100u8 { ret (from_bool(a > b), ok) }
        if op == 101u8 { ret (from_bool(a <= b), ok) }
        ret (from_bool(a >= b), ok)
    }
    // i32 arithmetic
    if op >= 106u8 && op <= 120u8 {
        let a = a32(x)
        let b = a32(y)
        if op == 106u8 { ret (u64(a +% b), ok) }
        if op == 107u8 { ret (u64(a -% b), ok) }
        if op == 108u8 { ret (u64(a *% b), ok) }
        if op == 109u8 {
            if b == 0u32 { ret (0u64, TrapDivZero) }
            let sa = s32(x)
            let sb = s32(y)
            if sa == -2147483647i32 - 1i32 && sb == -1i32 { ret (0u64, TrapOverflow) }
            ret (from_s32(sa / sb), ok)
        }
        if op == 110u8 {
            if b == 0u32 { ret (0u64, TrapDivZero) }
            ret (u64(a / b), ok)
        }
        if op == 111u8 {
            if b == 0u32 { ret (0u64, TrapDivZero) }
            let sb = s32(y)
            if sb == -1i32 { ret (0u64, ok) }
            ret (from_s32(s32(x) % sb), ok)
        }
        if op == 112u8 {
            if b == 0u32 { ret (0u64, TrapDivZero) }
            ret (u64(a % b), ok)
        }
        if op == 113u8 { ret (u64(a & b), ok) }
        if op == 114u8 { ret (u64(a | b), ok) }
        if op == 115u8 { ret (u64(a ^ b), ok) }
        if op == 116u8 { ret (u64(a << (b & 31u32)), ok) }
        if op == 117u8 { ret (u64(shr_s32(a, b)), ok) }
        if op == 118u8 { ret (u64(a >> (b & 31u32)), ok) }
        let k = b & 31u32
        if op == 119u8 { ret (u64((a << k) | (a >> ((32u32 - k) & 31u32))), ok) }
        ret (u64((a >> k) | (a << ((32u32 - k) & 31u32))), ok)
    }
    // i64 arithmetic
    if op >= 124u8 && op <= 138u8 {
        if op == 124u8 { ret (x +% y, ok) }
        if op == 125u8 { ret (x -% y, ok) }
        if op == 126u8 { ret (x *% y, ok) }
        if op == 127u8 {
            if y == 0u64 { ret (0u64, TrapDivZero) }
            let sa = s64(x)
            let sb = s64(y)
            if sa == -9223372036854775807i64 - 1i64 && sb == -1i64 { ret (0u64, TrapOverflow) }
            ret (from_s64(sa / sb), ok)
        }
        if op == 128u8 {
            if y == 0u64 { ret (0u64, TrapDivZero) }
            ret (x / y, ok)
        }
        if op == 129u8 {
            if y == 0u64 { ret (0u64, TrapDivZero) }
            let sb = s64(y)
            if sb == -1i64 { ret (0u64, ok) }
            ret (from_s64(s64(x) % sb), ok)
        }
        if op == 130u8 {
            if y == 0u64 { ret (0u64, TrapDivZero) }
            ret (x % y, ok)
        }
        if op == 131u8 { ret (x & y, ok) }
        if op == 132u8 { ret (x | y, ok) }
        if op == 133u8 { ret (x ^ y, ok) }
        let k = y & 63u64
        if op == 134u8 { ret (x << k, ok) }
        if op == 135u8 { ret (shr_s64(x, k), ok) }
        if op == 136u8 { ret (x >> k, ok) }
        if op == 137u8 { ret ((x << k) | (x >> ((64u64 - k) & 63u64)), ok) }
        ret ((x >> k) | (x << ((64u64 - k) & 63u64)), ok)
    }
    // f32 arithmetic
    if op >= 146u8 && op <= 152u8 {
        let a = tof32(x)
        let b = tof32(y)
        if op == 146u8 { ret (from_f32(a + b), ok) }
        if op == 147u8 { ret (from_f32(a - b), ok) }
        if op == 148u8 { ret (from_f32(a * b), ok) }
        if op == 149u8 { ret (from_f32(a / b), ok) }
        if op == 150u8 { ret (from_f32(math.min[f32](a, b)), ok) }
        if op == 151u8 { ret (from_f32(math.max[f32](a, b)), ok) }
        ret ((x & 2147483647u64) | (y & 2147483648u64), ok)
    }
    // f64 arithmetic
    if op >= 160u8 && op <= 166u8 {
        let a = tof64(x)
        let b = tof64(y)
        if op == 160u8 { ret (from_f64(a + b), ok) }
        if op == 161u8 { ret (from_f64(a - b), ok) }
        if op == 162u8 { ret (from_f64(a * b), ok) }
        if op == 163u8 { ret (from_f64(a / b), ok) }
        if op == 164u8 { ret (from_f64(math.min[f64](a, b)), ok) }
        if op == 165u8 { ret (from_f64(math.max[f64](a, b)), ok) }
        ret ((x & 9223372036854775807u64) | (y & 9223372036854775808u64), ok)
    }
    ret (0u64, Malformed)
}

// A unary operator (tests, counts, math, conversions) over the slot on top of the stack.
fn unop(op: u8, x: u64) -> (u64, err) {
    if op == 69u8 { ret (from_bool(a32(x) == 0u32), ok) }
    if op == 80u8 { ret (from_bool(x == 0u64), ok) }
    if op == 103u8 { ret (u64(clz32(a32(x))), ok) }
    if op == 104u8 { ret (u64(ctz32(a32(x))), ok) }
    if op == 105u8 { ret (u64(popcnt64(x & 4294967295u64)), ok) }
    if op == 121u8 { ret (u64(clz64(x)), ok) }
    if op == 122u8 { ret (u64(ctz64(x)), ok) }
    if op == 123u8 { ret (u64(popcnt64(x)), ok) }
    if op >= 139u8 && op <= 145u8 {
        if op == 139u8 { ret (x & 2147483647u64, ok) }
        if op == 140u8 { ret (x ^ 2147483648u64, ok) }
        let f = tof32(x)
        if op == 141u8 { ret (from_f32(math.ceil[f32](f)), ok) }
        if op == 142u8 { ret (from_f32(math.floor[f32](f)), ok) }
        if op == 143u8 { ret (from_f32(math.trunc[f32](f)), ok) }
        if op == 144u8 { ret (from_f32(math.round[f32](f)), ok) }
        ret (from_f32(math.sqrt[f32](f)), ok)
    }
    if op >= 153u8 && op <= 159u8 {
        if op == 153u8 { ret (x & 9223372036854775807u64, ok) }
        if op == 154u8 { ret (x ^ 9223372036854775808u64, ok) }
        let f = tof64(x)
        if op == 155u8 { ret (from_f64(math.ceil[f64](f)), ok) }
        if op == 156u8 { ret (from_f64(math.floor[f64](f)), ok) }
        if op == 157u8 { ret (from_f64(math.trunc[f64](f)), ok) }
        if op == 158u8 { ret (from_f64(math.round[f64](f)), ok) }
        ret (from_f64(math.sqrt[f64](f)), ok)
    }
    if op == 167u8 { ret (x & 4294967295u64, ok) }
    if op == 168u8 {
        let (tv, te) = trunc_conv(f64(tof32(x)), 0u32, false)
        ret (tv, te)
    }
    if op == 169u8 {
        let (tv, te) = trunc_conv(f64(tof32(x)), 1u32, false)
        ret (tv, te)
    }
    if op == 170u8 {
        let (tv, te) = trunc_conv(tof64(x), 0u32, false)
        ret (tv, te)
    }
    if op == 171u8 {
        let (tv, te) = trunc_conv(tof64(x), 1u32, false)
        ret (tv, te)
    }
    if op == 172u8 { ret (from_s64(i64(s32(x))), ok) }
    if op == 173u8 { ret (x & 4294967295u64, ok) }
    if op == 174u8 {
        let (tv, te) = trunc_conv(f64(tof32(x)), 2u32, false)
        ret (tv, te)
    }
    if op == 175u8 {
        let (tv, te) = trunc_conv(f64(tof32(x)), 3u32, false)
        ret (tv, te)
    }
    if op == 176u8 {
        let (tv, te) = trunc_conv(tof64(x), 2u32, false)
        ret (tv, te)
    }
    if op == 177u8 {
        let (tv, te) = trunc_conv(tof64(x), 3u32, false)
        ret (tv, te)
    }
    if op == 178u8 { ret (from_f32(f32(s32(x))), ok) }
    if op == 179u8 { ret (from_f32(f32(i64(a32(x)))), ok) }
    if op == 180u8 { ret (from_f32(f32(s64(x))), ok) }
    if op == 181u8 { ret (from_f32(u64_to_f32(x)), ok) }
    if op == 182u8 { ret (from_f32(f32(tof64(x))), ok) }
    if op == 183u8 { ret (from_f64(f64(s32(x))), ok) }
    if op == 184u8 { ret (from_f64(f64(i64(a32(x)))), ok) }
    if op == 185u8 { ret (from_f64(f64(s64(x))), ok) }
    if op == 186u8 { ret (from_f64(u64_to_f64(x)), ok) }
    if op == 187u8 { ret (from_f64(f64(tof32(x))), ok) }
    if op >= 188u8 && op <= 191u8 { ret (x, ok) }
    if op == 192u8 { ret (sext(x, 8u32) & 4294967295u64, ok) }
    if op == 193u8 { ret (sext(x, 16u32) & 4294967295u64, ok) }
    if op == 194u8 { ret (sext(x, 8u32), ok) }
    if op == 195u8 { ret (sext(x, 16u32), ok) }
    if op == 196u8 { ret (sext(x, 32u32), ok) }
    ret (0u64, Malformed)
}

// ---- Constant expressions ----------------------------------------------------------------------------------------------

fn eval_const(inst: *Instance, bytes: []const u8, start: usize, end: usize) -> (u64, err) {
    var r = Reader { b: bytes[0usize..end], at: start }
    var stk: [8]u64 = zero
    var sp = 0usize
    while r.at < end {
        let (op, oe) = rd_byte(&r)
        if oe != ok { ret (0u64, oe) }
        if op == 11u8 {
            if sp == 0usize { ret (0u64, Malformed) }
            ret (stk[sp - 1usize], ok)
        }
        if sp >= 7usize { ret (0u64, Malformed) }
        if op == 65u8 {
            let (v, e) = rd_sleb(&r, 32u32)
            if e != ok { ret (0u64, e) }
            stk[sp] = from_s64(v) & 4294967295u64
            sp += 1usize
        } else if op == 66u8 {
            let (v, e) = rd_sleb(&r, 64u32)
            if e != ok { ret (0u64, e) }
            stk[sp] = from_s64(v)
            sp += 1usize
        } else if op == 67u8 {
            let (v, e) = rd_f32(&r)
            if e != ok { ret (0u64, e) }
            stk[sp] = v
            sp += 1usize
        } else if op == 68u8 {
            let (v, e) = rd_f64(&r)
            if e != ok { ret (0u64, e) }
            stk[sp] = v
            sp += 1usize
        } else if op == 35u8 {
            let (gi, e) = rd_u32(&r)
            if e != ok { ret (0u64, e) }
            if usize(gi) >= inst.globals.len { ret (0u64, LinkError) }
            stk[sp] = inst.globals[usize(gi)].value
            sp += 1usize
        } else if op == 208u8 {
            let (t, e) = rd_byte(&r)
            if e != ok { ret (0u64, e) }
            stk[sp] = 0u64
            sp += 1usize
        } else if op == 210u8 {
            let (fi, e) = rd_u32(&r)
            if e != ok { ret (0u64, e) }
            if usize(fi) >= inst.funcs.len { ret (0u64, LinkError) }
            stk[sp] = u64(inst.funcs[usize(fi)]) + 1u64
            sp += 1usize
        } else if op == 106u8 || op == 107u8 || op == 108u8 || op == 124u8 || op == 125u8 || op == 126u8 {
            if sp < 2usize { ret (0u64, Malformed) }
            let (v, e) = binop(op, stk[sp - 2usize], stk[sp - 1usize])
            if e != ok { ret (0u64, e) }
            stk[sp - 2usize] = v
            sp -= 1usize
        } else {
            ret (0u64, Malformed)
        }
    }
    ret (0u64, Malformed)
}

// ---- The interpreter ---------------------------------------------------------------------------------------------------

// The effective address of an access of `width` bytes, or false when it is out of bounds.
fn ea(m: *Memory, addr: u32, offset: u32, width: usize) -> (usize, bool) {
    let e = u64(addr) + u64(offset)
    if e + u64(width) > u64(m.data.len) { ret (0usize, false) }
    ret (usize(e), true)
}

fn mem_load(m: *Memory, at: usize, width: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < width {
        v = v | (u64(m.data[at + i]) << u64(i * 8usize))
        i += 1usize
    }
    ret v
}

fn mem_store(m: *Memory, at: usize, width: usize, v: u64) {
    var i = 0usize
    while i < width {
        m.data[at + i] = u8((v >> u64(i * 8usize)) & 255u64)
        i += 1usize
    }
}

fn load_width(op: u8) -> usize {
    if op == 40u8 || op == 42u8 || op == 52u8 || op == 53u8 || op == 54u8 || op == 56u8 || op == 62u8 { ret 4usize }
    if op == 41u8 || op == 43u8 || op == 55u8 || op == 57u8 { ret 8usize }
    if op == 44u8 || op == 45u8 || op == 48u8 || op == 49u8 || op == 58u8 || op == 60u8 { ret 1usize }
    ret 2usize
}

// Block type: (params, results). A negative type is a value type (or the empty type 0x40).
fn block_arity(m: *const Module, bt: i64) -> (u32, u32) {
    if bt == -64i64 { ret (0u32, 0u32) }
    if bt < 0i64 { ret (0u32, 1u32) }
    let ft = m.types[usize(bt)]
    ret (u32(ft.params.len), u32(ft.results.len))
}

fn call_id(st: *Store, id: u32, fp: usize, depth: u32) -> err {
    if depth > MAX_DEPTH { ret TrapStack }
    let fi = st.funcs.items[usize(id)]
    if fi.is_host {
        let np = fi.ftype.params.len
        let nr = fi.ftype.results.len
        st.top = fp + np + nr
        let e = fi.host(fi.ctx, st.vs[fp..fp + np], st.vs[fp + np..fp + np + nr])
        if e != ok { ret e }
        var i = 0usize
        while i < nr {
            st.vs[fp + i] = st.vs[fp + np + i]
            i += 1usize
        }
        ret ok
    }
    ret exec(st, fi, fp, depth)
}

fn exec(st: *Store, fi: *FuncInst, fp: usize, depth: u32) -> err {
    let inst = fi.inst
    let m = inst.module
    let body = &inst.bodies[usize(fi.index)]
    let bytes = m.bytes
    let np = fi.ftype.params.len
    let nres = fi.ftype.results.len
    let nl = body.locals.len
    let vs = st.vs
    var i = 0usize
    while i < nl {
        vs[fp + np + i] = 0u64
        i += 1usize
    }
    var sp = fp + np + nl
    if sp + 1024usize >= vs.len { ret TrapStack }
    let base = st.ltop
    if base + 4096usize >= st.ls.len { ret TrapStack }
    st.ls[base] = Label { kind: 3u8, height: sp, arity: u32(nres), end_arity: u32(nres), cont: body.end, end: body.end }
    st.ltop = base + 1usize
    var r = Reader { b: bytes[0usize..body.end], at: body.start }
    while true {
        if sp + 16usize >= vs.len { st.ltop = base
            ret TrapStack }
        let pos = r.at
        let op = bytes[pos]
        r.at = pos + 1usize
        if op >= 69u8 {
            if op == 252u8 {
                let (sub, se) = rd_u32(&r)
                if se != ok { ret se }
                if sub <= 7u32 {
                    var f = 0.0f64
                    if (sub & 2u32) == 0u32 { f = f64(tof32(vs[sp - 1usize])) } else { f = tof64(vs[sp - 1usize]) }
                    var kind = 0u32
                    if sub >= 4u32 { kind = 2u32 }
                    if (sub & 1u32) == 1u32 { kind += 1u32 }
                    let (tv, te) = trunc_conv(f, kind, true)
                    vs[sp - 1usize] = tv
                } else if sub == 8u32 {
                    let (di, de1) = rd_u32(&r)
                    let (mi, de2) = rd_byte(&r)
                    let n = a32(vs[sp - 1usize])
                    let s0 = a32(vs[sp - 2usize])
                    let d0 = a32(vs[sp - 3usize])
                    sp -= 3usize
                    let dd = m.datas[usize(di)]
                    var dlen = dd.bytes.len
                    if inst.dropped_data[usize(di)] { dlen = 0usize }
                    let mm = inst.mems[0usize]
                    if u64(s0) + u64(n) > u64(dlen) || u64(d0) + u64(n) > u64(mm.data.len) { st.ltop = base
                        ret TrapMemory }
                    var k = 0usize
                    while k < usize(n) {
                        mm.data[usize(d0) + k] = dd.bytes[usize(s0) + k]
                        k += 1usize
                    }
                } else if sub == 9u32 {
                    let (di, de) = rd_u32(&r)
                    inst.dropped_data[usize(di)] = true
                } else if sub == 10u32 {
                    let (b1, e1) = rd_byte(&r)
                    let (b2, e2) = rd_byte(&r)
                    let n = a32(vs[sp - 1usize])
                    let s0 = a32(vs[sp - 2usize])
                    let d0 = a32(vs[sp - 3usize])
                    sp -= 3usize
                    let mm = inst.mems[0usize]
                    if u64(s0) + u64(n) > u64(mm.data.len) || u64(d0) + u64(n) > u64(mm.data.len) { st.ltop = base
                        ret TrapMemory }
                    if d0 <= s0 {
                        var k = 0usize
                        while k < usize(n) {
                            mm.data[usize(d0) + k] = mm.data[usize(s0) + k]
                            k += 1usize
                        }
                    } else {
                        var k = usize(n)
                        while k > 0usize {
                            k -= 1usize
                            mm.data[usize(d0) + k] = mm.data[usize(s0) + k]
                        }
                    }
                } else if sub == 11u32 {
                    let (b1, e1) = rd_byte(&r)
                    let n = a32(vs[sp - 1usize])
                    let val = u8(vs[sp - 2usize] & 255u64)
                    let d0 = a32(vs[sp - 3usize])
                    sp -= 3usize
                    let mm = inst.mems[0usize]
                    if u64(d0) + u64(n) > u64(mm.data.len) { st.ltop = base
                        ret TrapMemory }
                    var k = 0usize
                    while k < usize(n) {
                        mm.data[usize(d0) + k] = val
                        k += 1usize
                    }
                } else if sub == 12u32 {
                    let (ei, e1) = rd_u32(&r)
                    let (ti, e2) = rd_u32(&r)
                    let n = a32(vs[sp - 1usize])
                    let s0 = a32(vs[sp - 2usize])
                    let d0 = a32(vs[sp - 3usize])
                    sp -= 3usize
                    let t = inst.tables[usize(ti)]
                    let ed = m.elems[usize(ei)]
                    var elen = ed.count
                    if inst.dropped_elem[usize(ei)] { elen = 0usize }
                    if u64(s0) + u64(n) > u64(elen) || u64(d0) + u64(n) > u64(t.size) { st.ltop = base
                        ret TrapTable }
                    var k = 0usize
                    while k < usize(n) {
                        if ed.funcs.len > 0usize {
                            t.elems[usize(d0) + k] = u64(inst.funcs[usize(ed.funcs[usize(s0) + k])]) + 1u64
                        } else {
                            let (cv, ce) = eval_const(inst, bytes, ed.exprs[(usize(s0) + k) * 2usize], ed.exprs[(usize(s0) + k) * 2usize + 1usize])
                            t.elems[usize(d0) + k] = cv
                        }
                        k += 1usize
                    }
                } else if sub == 13u32 {
                    let (ei, e1) = rd_u32(&r)
                    inst.dropped_elem[usize(ei)] = true
                } else if sub == 14u32 {
                    let (dt, e1) = rd_u32(&r)
                    let (stb, e2) = rd_u32(&r)
                    let n = a32(vs[sp - 1usize])
                    let s0 = a32(vs[sp - 2usize])
                    let d0 = a32(vs[sp - 3usize])
                    sp -= 3usize
                    let td = inst.tables[usize(dt)]
                    let ts = inst.tables[usize(stb)]
                    if u64(s0) + u64(n) > u64(ts.size) || u64(d0) + u64(n) > u64(td.size) { st.ltop = base
                        ret TrapTable }
                    if d0 <= s0 {
                        var k = 0usize
                        while k < usize(n) {
                            td.elems[usize(d0) + k] = ts.elems[usize(s0) + k]
                            k += 1usize
                        }
                    } else {
                        var k = usize(n)
                        while k > 0usize {
                            k -= 1usize
                            td.elems[usize(d0) + k] = ts.elems[usize(s0) + k]
                        }
                    }
                } else if sub == 15u32 {
                    let (ti, e1) = rd_u32(&r)
                    let t = inst.tables[usize(ti)]
                    let n = a32(vs[sp - 1usize])
                    let init = vs[sp - 2usize]
                    sp -= 1usize
                    vs[sp - 1usize] = u64(table_grow(st.a, t, n, init))
                } else if sub == 16u32 {
                    let (ti, e1) = rd_u32(&r)
                    vs[sp] = u64(inst.tables[usize(ti)].size)
                    sp += 1usize
                } else if sub == 17u32 {
                    let (ti, e1) = rd_u32(&r)
                    let t = inst.tables[usize(ti)]
                    let n = a32(vs[sp - 1usize])
                    let val = vs[sp - 2usize]
                    let d0 = a32(vs[sp - 3usize])
                    sp -= 3usize
                    if u64(d0) + u64(n) > u64(t.size) { st.ltop = base
                        ret TrapTable }
                    var k = 0usize
                    while k < usize(n) {
                        t.elems[usize(d0) + k] = val
                        k += 1usize
                    }
                }
            } else if op >= 208u8 {
                if op == 208u8 {
                    let (t, te) = rd_byte(&r)
                    vs[sp] = 0u64
                    sp += 1usize
                } else if op == 209u8 {
                    vs[sp - 1usize] = from_bool(vs[sp - 1usize] == 0u64)
                } else if op == 210u8 {
                    let (fx, fe) = rd_u32(&r)
                    vs[sp] = u64(inst.funcs[usize(fx)]) + 1u64
                    sp += 1usize
                }
            } else {
                // Unary tests/arith (0x45 eqz, 0x50 eqz, 0x67..0x69, 0x79..0x7B, 0x8B..0x91, 0x99..0x9F, 0xA7..0xC4).
                var unary = false
                if op == 69u8 || op == 80u8 || (op >= 103u8 && op <= 105u8) || (op >= 121u8 && op <= 123u8) { unary = true }
                if (op >= 139u8 && op <= 145u8) || (op >= 153u8 && op <= 159u8) || (op >= 167u8 && op <= 196u8) { unary = true }
                if unary {
                    let (uv, ue) = unop(op, vs[sp - 1usize])
                    if ue != ok { st.ltop = base
                        ret ue }
                    vs[sp - 1usize] = uv
                } else {
                    let (bv, be) = binop(op, vs[sp - 2usize], vs[sp - 1usize])
                    if be != ok { st.ltop = base
                        ret be }
                    vs[sp - 2usize] = bv
                    sp -= 1usize
                }
            }
        } else if op >= 65u8 {
            if op == 65u8 {
                let (v, e) = rd_sleb(&r, 32u32)
                vs[sp] = from_s64(v) & 4294967295u64
            } else if op == 66u8 {
                let (v, e) = rd_sleb(&r, 64u32)
                vs[sp] = from_s64(v)
            } else if op == 67u8 {
                let (v, e) = rd_f32(&r)
                vs[sp] = v
            } else {
                let (v, e) = rd_f64(&r)
                vs[sp] = v
            }
            sp += 1usize
        } else if op >= 40u8 {
            if op == 63u8 {
                let (z, ze) = rd_byte(&r)
                vs[sp] = u64(inst.mems[0usize].pages)
                sp += 1usize
            } else if op == 64u8 {
                let (z, ze) = rd_byte(&r)
                vs[sp - 1usize] = u64(memory_grow(st.a, inst.mems[0usize], a32(vs[sp - 1usize])))
            } else {
                let (al, ae) = rd_u32(&r)
                let (off, oe) = rd_u32(&r)
                let mm = inst.mems[0usize]
                let w = load_width(op)
                if op <= 53u8 {
                    let (at, good) = ea(mm, a32(vs[sp - 1usize]), off, w)
                    if !good { st.ltop = base
                        ret TrapMemory }
                    var v = mem_load(mm, at, w)
                    if op == 44u8 { v = sext(v, 8u32) & 4294967295u64 }
                    if op == 46u8 { v = sext(v, 16u32) & 4294967295u64 }
                    if op == 48u8 { v = sext(v, 8u32) }
                    if op == 50u8 { v = sext(v, 16u32) }
                    if op == 52u8 { v = sext(v, 32u32) }
                    vs[sp - 1usize] = v
                } else {
                    let (at, good) = ea(mm, a32(vs[sp - 2usize]), off, w)
                    if !good { st.ltop = base
                        ret TrapMemory }
                    mem_store(mm, at, w, vs[sp - 1usize])
                    sp -= 2usize
                }
            }
        } else if op >= 32u8 {
            let (ix, ie) = rd_u32(&r)
            if op == 32u8 {
                vs[sp] = vs[fp + usize(ix)]
                sp += 1usize
            } else if op == 33u8 {
                vs[fp + usize(ix)] = vs[sp - 1usize]
                sp -= 1usize
            } else if op == 34u8 {
                vs[fp + usize(ix)] = vs[sp - 1usize]
            } else if op == 35u8 {
                vs[sp] = inst.globals[usize(ix)].value
                sp += 1usize
            } else if op == 36u8 {
                inst.globals[usize(ix)].value = vs[sp - 1usize]
                sp -= 1usize
            } else if op == 37u8 {
                let t = inst.tables[usize(ix)]
                let k = a32(vs[sp - 1usize])
                if k >= t.size { st.ltop = base
                    ret TrapTable }
                vs[sp - 1usize] = t.elems[usize(k)]
            } else {
                let t = inst.tables[usize(ix)]
                let k = a32(vs[sp - 2usize])
                if k >= t.size { st.ltop = base
                    ret TrapTable }
                t.elems[usize(k)] = vs[sp - 1usize]
                sp -= 2usize
            }
        } else if op >= 26u8 {
            if op == 26u8 {
                sp -= 1usize
            } else if op == 27u8 || op == 28u8 {
                if op == 28u8 {
                    let (n, ne) = rd_u32(&r)
                    var q = 0u32
                    while q < n {
                        let (t, te) = rd_byte(&r)
                        q += 1u32
                    }
                }
                let c = a32(vs[sp - 1usize])
                if c == 0u32 { vs[sp - 3usize] = vs[sp - 2usize] }
                sp -= 2usize
            }
        } else if op == 0u8 {
            st.ltop = base
            ret TrapUnreachable
        } else if op == 1u8 {
            // nop
        } else if op <= 4u8 {
            let (bt, be) = rd_sleb(&r, 33u32)
            let (bp, br) = block_arity(m, bt)
            let endp = usize(body.jump[pos - body.start])
            if op == 2u8 {
                st.ls[st.ltop] = Label { kind: 0u8, height: sp - usize(bp), arity: br, end_arity: br, cont: endp + 1usize, end: endp }
                st.ltop += 1usize
            } else if op == 3u8 {
                st.ls[st.ltop] = Label { kind: 1u8, height: sp - usize(bp), arity: bp, end_arity: br, cont: r.at, end: endp }
                st.ltop += 1usize
            } else {
                let c = a32(vs[sp - 1usize])
                sp -= 1usize
                st.ls[st.ltop] = Label { kind: 2u8, height: sp - usize(bp), arity: br, end_arity: br, cont: endp + 1usize, end: endp }
                st.ltop += 1usize
                if c == 0u32 {
                    let elsep = usize(body.other[pos - body.start])
                    if elsep != 0usize {
                        r.at = elsep + 1usize
                    } else {
                        r.at = endp
                    }
                }
            }
        } else if op == 5u8 {
            r.at = usize(body.jump[pos - body.start])
        } else if op == 11u8 {
            if st.ltop - base == 1usize {
                // The function's own end: its results are the top of the stack.
                var k = 0usize
                while k < nres {
                    vs[fp + k] = vs[sp - nres + k]
                    k += 1usize
                }
                st.ltop = base
                ret ok
            }
            st.ltop -= 1usize
        } else if op == 12u8 || op == 13u8 || op == 14u8 || op == 15u8 {
            var d = 0usize
            var go = true
            if op == 12u8 {
                let (dd, de) = rd_u32(&r)
                d = usize(dd)
            } else if op == 13u8 {
                let (dd, de) = rd_u32(&r)
                d = usize(dd)
                let c = a32(vs[sp - 1usize])
                sp -= 1usize
                if c == 0u32 { go = false }
            } else if op == 14u8 {
                let (n, ne) = rd_u32(&r)
                let k = a32(vs[sp - 1usize])
                sp -= 1usize
                var pick = n
                if k < n { pick = k }
                var q = 0u32
                var found = 0u32
                while q <= n {
                    let (dd, de) = rd_u32(&r)
                    if q == pick { found = dd }
                    q += 1u32
                }
                d = usize(found)
            } else {
                d = st.ltop - base - 1usize
            }
            if go {
                let lab = st.ls[st.ltop - 1usize - d]
                let arity = usize(lab.arity)
                var k = 0usize
                while k < arity {
                    vs[lab.height + k] = vs[sp - arity + k]
                    k += 1usize
                }
                sp = lab.height + arity
                if lab.kind == 3u8 {
                    k = 0usize
                    while k < nres {
                        vs[fp + k] = vs[lab.height + k]
                        k += 1usize
                    }
                    st.ltop = base
                    ret ok
                }
                if lab.kind == 1u8 {
                    st.ltop = st.ltop - d
                    r.at = lab.cont
                } else {
                    st.ltop = st.ltop - 1usize - d
                    r.at = lab.cont
                }
            }
        } else {
            // 0x10 call, 0x11 call_indirect
            if op == 16u8 {
                let (ix, ie) = rd_u32(&r)
                let fid = inst.funcs[usize(ix)]
                let callee = st.funcs.items[usize(fid)]
                let cnp = callee.ftype.params.len
                let cnr = callee.ftype.results.len
                let nfp = sp - cnp
                let ce = call_id(st, fid, nfp, depth + 1u32)
                if ce != ok { st.ltop = base
                    ret ce }
                sp = nfp + cnr
            } else {
                let (ti, tie) = rd_u32(&r)
                let (tbl, tble) = rd_u32(&r)
                let t = inst.tables[usize(tbl)]
                let k = a32(vs[sp - 1usize])
                sp -= 1usize
                if k >= t.size { st.ltop = base
                    ret TrapTable }
                let rf = t.elems[usize(k)]
                if rf == 0u64 { st.ltop = base
                    ret TrapTable }
                let fid = u32(rf - 1u64)
                let callee = st.funcs.items[usize(fid)]
                if !types_equal(callee.ftype, m.types[usize(ti)]) { st.ltop = base
                    ret TrapIndirect }
                let cnp = callee.ftype.params.len
                let cnr = callee.ftype.results.len
                let nfp = sp - cnp
                let ce = call_id(st, fid, nfp, depth + 1u32)
                if ce != ok { st.ltop = base
                    ret ce }
                sp = nfp + cnr
            }
        }
    }
    ret ok
}

// Calls function `id` with `args`, writing its results to `results`.
fn invoke(st: *Store, id: u32, args: []const u64, results: []u64) -> err {
    let fi = st.funcs.items[usize(id)]
    if args.len != fi.ftype.params.len || results.len != fi.ftype.results.len { ret LinkError }
    let fp = st.top
    var i = 0usize
    while i < args.len {
        st.vs[fp + i] = args[i]
        i += 1usize
    }
    let saved_ltop = st.ltop
    let e = call_id(st, id, fp, 0u32)
    st.ltop = saved_ltop
    st.top = fp
    if e != ok { ret e }
    i = 0usize
    while i < results.len {
        results[i] = st.vs[fp + i]
        i += 1usize
    }
    ret ok
}

// ---- Instantiation -----------------------------------------------------------------------------------------------------

fn instantiate(a: *mem.Arena, st: *Store, m: *const Module, imports: []const ImportVal) -> (*Instance, err) {
    var none: *Instance = zero
    if imports.len != m.imports.len { ret (none, LinkError) }
    let (cell, ce) = mem.alloc[Instance](a, 1usize)
    if ce != ok { ret (none, ce) }
    let inst = &cell[0usize]
    inst.module = m
    inst.store = st
    let nf = m.funcs.len
    let (fl, fe) = mem.alloc[u32](a, nf + 1usize)
    if fe != ok { ret (none, fe) }
    let (ml, mle) = mem.alloc[*Memory](a, m.memories.len + 1usize)
    if mle != ok { ret (none, mle) }
    let (tl, tle) = mem.alloc[*Table](a, m.tables.len + 1usize)
    if tle != ok { ret (none, tle) }
    let (gl, gle) = mem.alloc[*Global](a, m.globals.len + 1usize)
    if gle != ok { ret (none, gle) }
    let (dd, dde) = mem.alloc[bool](a, m.datas.len + 1usize)
    if dde != ok { ret (none, dde) }
    let (de, dee) = mem.alloc[bool](a, m.elems.len + 1usize)
    if dee != ok { ret (none, dee) }
    var i = 0usize
    while i < m.datas.len {
        dd[i] = false
        i += 1usize
    }
    i = 0usize
    while i < m.elems.len {
        de[i] = false
        i += 1usize
    }
    inst.funcs = fl[0usize..nf]
    inst.mems = ml[0usize..m.memories.len]
    inst.tables = tl[0usize..m.tables.len]
    inst.globals = gl[0usize..m.globals.len]
    inst.dropped_data = dd[0usize..m.datas.len]
    inst.dropped_elem = de[0usize..m.elems.len]
    var nfi = 0usize
    var nti = 0usize
    var nmi = 0usize
    var ngi = 0usize
    i = 0usize
    while i < m.imports.len {
        let imp = m.imports[i]
        let iv = imports[i]
        if imp.kind == .Func {
            if iv.kind != .Func || usize(iv.func) >= st.funcs.len { ret (none, LinkError) }
            if !types_equal(st.funcs.items[usize(iv.func)].ftype, m.types[usize(imp.index)]) { ret (none, LinkError) }
            inst.funcs[nfi] = iv.func
            nfi += 1usize
        } else if imp.kind == .Memory {
            if iv.kind != .Memory { ret (none, LinkError) }
            if iv.memory.pages < imp.limits.min { ret (none, LinkError) }
            if imp.limits.has_max && (!iv.memory.has_max || iv.memory.max > imp.limits.max) { ret (none, LinkError) }
            inst.mems[nmi] = iv.memory
            nmi += 1usize
        } else if imp.kind == .Table {
            if iv.kind != .Table || iv.table.ttype != imp.ttype { ret (none, LinkError) }
            if iv.table.size < imp.limits.min { ret (none, LinkError) }
            if imp.limits.has_max && (!iv.table.has_max || iv.table.max > imp.limits.max) { ret (none, LinkError) }
            inst.tables[nti] = iv.table
            nti += 1usize
        } else {
            if iv.kind != .Global || iv.global.vtype != imp.ttype || iv.global.mutable != imp.mutable { ret (none, LinkError) }
            inst.globals[ngi] = iv.global
            ngi += 1usize
        }
        i += 1usize
    }
    // Own functions: the jump tables are built per instance so the module stays read-only.
    let (bl, ble) = mem.alloc[FuncBody](a, m.bodies.len + 1usize)
    if ble != ok { ret (none, ble) }
    i = 0usize
    while i < m.bodies.len {
        bl[i] = m.bodies[i]
        let je = build_jumps(a, m, &bl[i])
        if je != ok { ret (none, je) }
        i += 1usize
    }
    inst.bodies = bl[0usize..m.bodies.len]
    i = 0usize
    while i < m.bodies.len {
        let (fc, fce) = mem.alloc[FuncInst](a, 1usize)
        if fce != ok { ret (none, fce) }
        var noneh: HostFn = zero
        var nonec: *void = zero
        fc[0usize] = FuncInst { inst: inst, index: u32(i), ftype: m.types[usize(m.funcs[nfi + i])], host: noneh, ctx: nonec, is_host: false }
        let id = u32(st.funcs.len)
        let pe = list.push[*FuncInst](&st.funcs, &fc[0usize])
        if pe != ok { ret (none, pe) }
        inst.funcs[nfi + i] = id
        i += 1usize
    }
    // Defined tables, memories, globals.
    i = nti
    while i < m.tables.len {
        let (t, te) = table_new(a, m.table_types[i], m.tables[i].min, m.tables[i].max, m.tables[i].has_max, 0u64)
        if te != ok { ret (none, te) }
        inst.tables[i] = t
        i += 1usize
    }
    i = nmi
    while i < m.memories.len {
        let (mm, mme) = memory_new(a, m.memories[i].min, m.memories[i].max, m.memories[i].has_max)
        if mme != ok { ret (none, mme) }
        inst.mems[i] = mm
        i += 1usize
    }
    i = ngi
    while i < m.globals.len {
        let g = m.globals[i]
        let (v, ve) = eval_const(inst, m.bytes, g.init, g.init_end)
        if ve != ok { ret (none, ve) }
        let (gc, gce) = global_new(a, g.vtype, g.mutable, v)
        if gce != ok { ret (none, gce) }
        inst.globals[i] = gc
        i += 1usize
    }
    // Active element and data segments.
    i = 0usize
    while i < m.elems.len {
        let ed = m.elems[i]
        if ed.mode == 0u8 {
            let (ov, oe) = eval_const(inst, m.bytes, ed.offset, ed.offset_end)
            if oe != ok { ret (none, oe) }
            if usize(ed.table) >= inst.tables.len { ret (none, LinkError) }
            let t = inst.tables[usize(ed.table)]
            let off = a32(ov)
            if u64(off) + u64(ed.count) > u64(t.size) { ret (none, TrapTable) }
            var k = 0usize
            while k < ed.count {
                if ed.funcs.len > 0usize {
                    t.elems[usize(off) + k] = u64(inst.funcs[usize(ed.funcs[k])]) + 1u64
                } else {
                    let (cv, cve) = eval_const(inst, m.bytes, ed.exprs[k * 2usize], ed.exprs[k * 2usize + 1usize])
                    if cve != ok { ret (none, cve) }
                    t.elems[usize(off) + k] = cv
                }
                k += 1usize
            }
            inst.dropped_elem[i] = true
        } else if ed.mode == 2u8 {
            inst.dropped_elem[i] = true
        }
        i += 1usize
    }
    i = 0usize
    while i < m.datas.len {
        let dd2 = m.datas[i]
        if dd2.mode == 0u8 {
            let (ov, oe) = eval_const(inst, m.bytes, dd2.offset, dd2.offset_end)
            if oe != ok { ret (none, oe) }
            if usize(dd2.memory) >= inst.mems.len { ret (none, LinkError) }
            let mm = inst.mems[usize(dd2.memory)]
            let off = a32(ov)
            if u64(off) + u64(dd2.bytes.len) > u64(mm.data.len) { ret (none, TrapMemory) }
            var k = 0usize
            while k < dd2.bytes.len {
                mm.data[usize(off) + k] = dd2.bytes[k]
                k += 1usize
            }
            inst.dropped_data[i] = true
        }
        i += 1usize
    }
    if m.has_start {
        let empty: [1]u64 = zero
        var out: [1]u64 = zero
        let se = invoke(st, inst.funcs[usize(m.start)], empty[0usize..0usize], out[0usize..0usize])
        if se != ok { ret (none, se) }
    }
    ret (inst, ok)
}

fn find_export(m: *const Module, name: str) -> (Export, bool) {
    var i = 0usize
    while i < m.exports.len {
        if str.eq(m.exports[i].name, name) { ret (m.exports[i], true) }
        i += 1usize
    }
    ret (zero, false)
}
