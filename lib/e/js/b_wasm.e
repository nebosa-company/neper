// The `WebAssembly` namespace (browser tracker 5.x): Module, Instance, Memory, Table, Global, the three error types, and
// `validate`, `compile` and `instantiate`, over the interpreter in `e.wasm`.
//
// One wasm store per realm, made on first use (it reserves the interpreter's stacks). Exported functions are JS functions that
// convert their arguments to the parameter types and back; a JS function imported into a module runs on the module's behalf
// and an exception it throws unwinds the wasm frames and reaches the caller. A memory's `buffer` is an ArrayBuffer over the same
// bytes, replaced when the memory grows.
//
// Ceiling: `validate` and `new Module` check the module's structure, not the types of its function bodies (see e.wasm), and
// `externref` values are not supported.

use e.data.list as list
use e.js.bigint as bigint
use e.js.interp as js
use e.mem
use e.str
use e.wasm as wasm

type Rt = struct {
    st: *wasm.Store, has_store: bool,
    ns: *js.Obj, compile_proto: *js.Obj, link_proto: *js.Obj, runtime_proto: *js.Obj,
    module_proto: *js.Obj, instance_proto: *js.Obj, memory_proto: *js.Obj, table_proto: *js.Obj, global_proto: *js.Obj,
    fobjs: list.List[*js.Obj], mems: list.List[*js.Obj], tables: list.List[*js.Obj], globals: list.List[*js.Obj]
}
type WFunc = struct { id: u32 }
type HostCtx = struct { it: *js.Interp, f: js.Value, ftype: wasm.FuncType }

fn u32_str(it: *js.Interp, v: u32) -> str { ret js.number_to_string(it.a, f64(v)) }

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

fn rt_of(it: *js.Interp) -> *Rt { ret mem.cast[*Rt](it.wasm) }

fn store_of(it: *js.Interp) -> (*wasm.Store, err) {
    let rt = rt_of(it)
    if rt.has_store { ret (rt.st, ok) }
    let (st, e) = wasm.store_new(it.a)
    if e != ok { ret (st, js.throw_range(it, "WebAssembly: out of memory")) }
    rt.st = st
    rt.has_store = true
    ret (st, ok)
}

fn throw_with(it: *js.Interp, proto: *js.Obj, msg: str) -> err {
    let o = js.new_obj(it, js.C_ERROR, proto)
    let e = js.define_data(it, o, js.key_of("message"), js.str_value(msg), js.P_HIDDEN)
    ret js.throw_value(it, js.obj_value(o))
}

fn throw_compile(it: *js.Interp, msg: str) -> err { ret throw_with(it, rt_of(it).compile_proto, msg) }
fn throw_link(it: *js.Interp, msg: str) -> err { ret throw_with(it, rt_of(it).link_proto, msg) }
fn throw_runtime(it: *js.Interp, msg: str) -> err { ret throw_with(it, rt_of(it).runtime_proto, msg) }

// Maps a wasm error to the exception the JS API specifies; a JS exception (`Throw`) passes through.
fn map_error(it: *js.Interp, e: err) -> err {
    if e == js.Throw { ret e }
    if e == wasm.TrapUnreachable { ret throw_runtime(it, "unreachable") }
    if e == wasm.TrapMemory { ret throw_runtime(it, "memory access out of bounds") }
    if e == wasm.TrapDivZero { ret throw_runtime(it, "divide by zero") }
    if e == wasm.TrapOverflow { ret throw_runtime(it, "integer overflow") }
    if e == wasm.TrapIndirect { ret throw_runtime(it, "null function or function signature mismatch") }
    if e == wasm.TrapTable { ret throw_runtime(it, "table index is out of bounds") }
    if e == wasm.TrapConversion { ret throw_runtime(it, "float unrepresentable in integer range") }
    if e == wasm.TrapStack { ret js.throw_range(it, "Maximum call stack size exceeded") }
    if e == wasm.LinkError { ret throw_link(it, "link error") }
    if e == wasm.Malformed { ret throw_compile(it, "malformed module") }
    if e == wasm.Unsupported { ret js.throw_range(it, "WebAssembly: unsupported") }
    ret throw_runtime(it, "trap")
}

// ---- Values ------------------------------------------------------------------------------------------------------------

fn func_object(it: *js.Interp, id: u32) -> *js.Obj {
    let rt = rt_of(it)
    while rt.fobjs.len <= usize(id) {
        var none: *js.Obj = zero
        let pe = list.push[*js.Obj](&rt.fobjs, none)
    }
    let z = js.null_obj()
    if rt.fobjs.items[usize(id)] != z && rt.fobjs.items[usize(id)] != zero_obj() { ret rt.fobjs.items[usize(id)] }
    let fi = rt.st.funcs.items[usize(id)]
    var idx = id
    if !fi.is_host { idx = fi.index }
    let fo = js.make_native(it, u32_str(it, idx), u32(fi.ftype.params.len), wasm_call)
    let (cell, ce) = mem.alloc[WFunc](it.a, 1usize)
    cell[0usize] = WFunc { id: id }
    fo.data = mem.cast[*void](&cell[0usize])
    rt.fobjs.items[usize(id)] = fo
    ret fo
}

fn zero_obj() -> *js.Obj {
    var p: *js.Obj = zero
    ret p
}

fn to_wasm(it: *js.Interp, v: js.Value, t: u8) -> (u64, err) {
    if t == wasm.T_I32 {
        let (n, e) = js.to_int32(it, v)
        if e != ok { ret (0u64, e) }
        ret (wasm.from_s32(n), ok)
    }
    if t == wasm.T_I64 {
        let (b, e) = js.to_bigint(it, v)
        if e != ok { ret (0u64, e) }
        ret (wasm.from_s64(bigint.to_i64_wrapping(b)), ok)
    }
    if t == wasm.T_F32 {
        let (n, e) = js.to_number(it, v)
        if e != ok { ret (0u64, e) }
        ret (wasm.from_f32(f32(n)), ok)
    }
    if t == wasm.T_F64 {
        let (n, e) = js.to_number(it, v)
        if e != ok { ret (0u64, e) }
        ret (wasm.from_f64(n), ok)
    }
    if t == wasm.T_FUNCREF {
        if js.is_null(v) { ret (0u64, ok) }
        if js.is_object(v) {
            let rt = rt_of(it)
            var i = 0usize
            while i < rt.fobjs.len {
                if rt.fobjs.items[i] == js.as_object(v) { ret (u64(i) + 1u64, ok) }
                i += 1usize
            }
        }
        ret (0u64, js.throw_type(it, "WebAssembly: value is not an exported WebAssembly function"))
    }
    ret (0u64, js.throw_type(it, "WebAssembly: externref values are not supported"))
}

fn from_wasm(it: *js.Interp, x: u64, t: u8) -> (js.Value, err) {
    if t == wasm.T_I32 { ret (js.num_value(f64(wasm.s32(x))), ok) }
    if t == wasm.T_I64 {
        let (b, e) = bigint.from_i64(it.a, wasm.s64(x))
        if e != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
        ret (js.big_value(b), ok)
    }
    if t == wasm.T_F32 { ret (js.num_value(f64(wasm.tof32(x))), ok) }
    if t == wasm.T_F64 { ret (js.num_value(wasm.tof64(x)), ok) }
    if t == wasm.T_FUNCREF {
        if x == 0u64 { ret (js.null_value(), ok) }
        ret (js.obj_value(func_object(it, u32(x - 1u64))), ok)
    }
    ret (js.undefv(), js.throw_type(it, "WebAssembly: externref values are not supported"))
}

// An exported function: ToWebAssemblyValue on the arguments, the call, ToJSValue on the results.
fn wasm_call(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let wf = mem.cast[*WFunc](it.callee.data)
    let rt = rt_of(it)
    let fi = rt.st.funcs.items[usize(wf.id)]
    let np = fi.ftype.params.len
    let nr = fi.ftype.results.len
    let (pa, pe) = mem.alloc[u64](it.a, np + 1usize)
    let (ra, re) = mem.alloc[u64](it.a, nr + 1usize)
    if pe != ok || re != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var i = 0usize
    while i < np {
        let (v, ve) = to_wasm(it, arg(args, i), fi.ftype.params[i])
        if ve != ok { ret (js.undefv(), ve) }
        pa[i] = v
        i += 1usize
    }
    let e = wasm.invoke(rt.st, wf.id, pa[0usize..np], ra[0usize..nr])
    if e != ok { ret (js.undefv(), map_error(it, e)) }
    if nr == 0usize { ret (js.undefv(), ok) }
    if nr == 1usize {
        let (rv, rve) = from_wasm(it, ra[0usize], fi.ftype.results[0usize])
        ret (rv, rve)
    }
    let arr = js.new_array(it)
    i = 0usize
    while i < nr {
        let (v, ve) = from_wasm(it, ra[i], fi.ftype.results[i])
        if ve != ok { ret (js.undefv(), ve) }
        let pe2 = js.array_push(it, arr, v)
        i += 1usize
    }
    ret (js.obj_value(arr), ok)
}

// A JS function called from wasm.
fn host_call(ctx: *void, args: []const u64, results: []u64) -> err {
    let hc = mem.cast[*HostCtx](ctx)
    let it = hc.it
    let (jargs, jae) = mem.alloc[js.Value](it.a, args.len + 1usize)
    if jae != ok { ret js.throw_range(it, "out of memory") }
    var i = 0usize
    while i < args.len {
        let (v, ve) = from_wasm(it, args[i], hc.ftype.params[i])
        if ve != ok { ret ve }
        jargs[i] = v
        i += 1usize
    }
    let (r, e) = js.call_function(it, hc.f, js.undefv(), jargs[0usize..args.len])
    if e != ok { ret e }
    if results.len == 1usize {
        let (w, we) = to_wasm(it, r, hc.ftype.results[0usize])
        if we != ok { ret we }
        results[0usize] = w
    } else if results.len > 1usize {
        var k = 0usize
        while k < results.len {
            let (item, ie) = js.get_value(it, r, js.key_of(u32_str(it, u32(k))))
            if ie != ok { ret ie }
            let (w, we) = to_wasm(it, item, hc.ftype.results[k])
            if we != ok { ret we }
            results[k] = w
            k += 1usize
        }
    }
    ret ok
}

// ---- Source bytes ------------------------------------------------------------------------------------------------------

fn source_bytes(it: *js.Interp, v: js.Value) -> ([]const u8, err) {
    if js.is_object(v) {
        let o = js.as_object(v)
        if o.class == js.C_ARRAYBUFFER { ret (js.buf_of(o).bytes, ok) }
        if o.class == js.C_TYPEDARRAY {
            let t = js.ta_of(o)
            let b = js.buf_of(t.buffer)
            let n = js.ta_length(o) * js.ta_elem_size(t.kind)
            if t.offset + n > b.bytes.len { ret (b.bytes[0usize..0usize], ok) }
            ret (b.bytes[t.offset..t.offset + n], ok)
        }
    }
    ret (zero, js.throw_type(it, "WebAssembly: argument must be a buffer source"))
}

fn copy_bytes(it: *js.Interp, src: []const u8) -> ([]u8, err) {
    let (d, de) = mem.alloc[u8](it.a, src.len + 1usize)
    if de != ok { ret (zero, js.throw_range(it, "out of memory")) }
    var i = 0usize
    while i < src.len {
        d[i] = src[i]
        i += 1usize
    }
    ret (d[0usize..src.len], ok)
}

fn new_module_object(it: *js.Interp, proto: *js.Obj, bytes: []const u8) -> (js.Value, err) {
    let (own, ce) = copy_bytes(it, bytes)
    if ce != ok { ret (js.undefv(), ce) }
    let (m, de) = wasm.decode(it.a, own)
    if de != ok { ret (js.undefv(), throw_compile(it, "WebAssembly.Module(): invalid or unsupported module")) }
    let (cell, ae) = mem.alloc[wasm.Module](it.a, 1usize)
    if ae != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    cell[0usize] = m
    let o = js.new_obj(it, js.C_WMODULE, proto)
    o.data = mem.cast[*void](&cell[0usize])
    ret (js.obj_value(o), ok)
}

fn this_of(it: *js.Interp, v: js.Value, class: u8, what: str) -> (*void, err) {
    var none: *void = zero
    if js.is_object(v) && js.as_object(v).class == class { ret (js.as_object(v).data, ok) }
    ret (none, js.throw_type(it, js.str_concat(it, what, ": Receiver is not a valid object")))
}

// ---- Module ------------------------------------------------------------------------------------------------------------

fn module_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "WebAssembly.Module must be invoked with 'new'")) }
    let (bytes, be) = source_bytes(it, arg(args, 0usize))
    if be != ok { ret (js.undefv(), be) }
    let (proto, pe) = js.proto_value_of(it, js.as_object(it.new_target), rt_of(it).module_proto)
    if pe != ok { ret (js.undefv(), pe) }
    let (v, e) = new_module_object(it, proto, bytes)
    ret (v, e)
}

fn kind_name(k: wasm.ImportKind) -> str {
    if k == .Func { ret "function" }
    if k == .Table { ret "table" }
    if k == .Memory { ret "memory" }
    ret "global"
}

fn set_str(it: *js.Interp, o: *js.Obj, name: str, v: str) {
    let e = js.define_data(it, o, js.key_of(name), js.str_value(v), js.P_DEFAULT)
}

fn module_exports(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, arg(args, 0usize), js.C_WMODULE, "WebAssembly.Module.exports()")
    if de != ok { ret (js.undefv(), de) }
    let m = mem.cast[*wasm.Module](d)
    let arr = js.new_array(it)
    var i = 0usize
    while i < m.exports.len {
        let o = js.new_plain(it)
        set_str(it, o, "name", m.exports[i].name)
        set_str(it, o, "kind", kind_name(m.exports[i].kind))
        let pe = js.array_push(it, arr, js.obj_value(o))
        i += 1usize
    }
    ret (js.obj_value(arr), ok)
}

fn module_imports(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, arg(args, 0usize), js.C_WMODULE, "WebAssembly.Module.imports()")
    if de != ok { ret (js.undefv(), de) }
    let m = mem.cast[*wasm.Module](d)
    let arr = js.new_array(it)
    var i = 0usize
    while i < m.imports.len {
        let o = js.new_plain(it)
        set_str(it, o, "module", m.imports[i].module)
        set_str(it, o, "name", m.imports[i].name)
        set_str(it, o, "kind", kind_name(m.imports[i].kind))
        let pe = js.array_push(it, arr, js.obj_value(o))
        i += 1usize
    }
    ret (js.obj_value(arr), ok)
}

fn module_custom_sections(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, arg(args, 0usize), js.C_WMODULE, "WebAssembly.Module.customSections()")
    if de != ok { ret (js.undefv(), de) }
    ret (js.obj_value(js.new_array(it)), ok)
}

// ---- Memory, Table, Global ---------------------------------------------------------------------------------------------

fn memory_object(it: *js.Interp, m: *wasm.Memory) -> *js.Obj {
    let rt = rt_of(it)
    var i = 0usize
    while i < rt.mems.len {
        if mem.cast[*wasm.Memory](rt.mems.items[i].data) == m { ret rt.mems.items[i] }
        i += 1usize
    }
    let o = js.new_obj(it, js.C_WMEMORY, rt.memory_proto)
    o.data = mem.cast[*void](m)
    let pe = list.push[*js.Obj](&rt.mems, o)
    ret o
}

fn table_object(it: *js.Interp, t: *wasm.Table) -> *js.Obj {
    let rt = rt_of(it)
    var i = 0usize
    while i < rt.tables.len {
        if mem.cast[*wasm.Table](rt.tables.items[i].data) == t { ret rt.tables.items[i] }
        i += 1usize
    }
    let o = js.new_obj(it, js.C_WTABLE, rt.table_proto)
    o.data = mem.cast[*void](t)
    let pe = list.push[*js.Obj](&rt.tables, o)
    ret o
}

fn global_object(it: *js.Interp, g: *wasm.Global) -> *js.Obj {
    let rt = rt_of(it)
    var i = 0usize
    while i < rt.globals.len {
        if mem.cast[*wasm.Global](rt.globals.items[i].data) == g { ret rt.globals.items[i] }
        i += 1usize
    }
    let o = js.new_obj(it, js.C_WGLOBAL, rt.global_proto)
    o.data = mem.cast[*void](g)
    let pe = list.push[*js.Obj](&rt.globals, o)
    ret o
}

// A non-negative integer member of a descriptor: (value, present, error).
fn desc_index(it: *js.Interp, d: js.Value, name: str, limit: f64) -> (f64, bool, err) {
    let (v, ge) = js.get_value(it, d, js.key_of(name))
    if ge != ok { ret (0.0f64, false, ge) }
    if js.is_undefined(v) { ret (0.0f64, false, ok) }
    let (n, ne) = js.to_number(it, v)
    if ne != ok { ret (0.0f64, false, ne) }
    if n != n || n < 0.0f64 || n > limit { ret (0.0f64, false, js.throw_type(it, js.str_concat3(it, "WebAssembly: '", name, "' is out of range"))) }
    ret (js.to_integer(n), true, ok)
}

fn memory_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "WebAssembly.Memory must be invoked with 'new'")) }
    let d = arg(args, 0usize)
    if !js.is_object(d) { ret (js.undefv(), js.throw_type(it, "WebAssembly.Memory(): Argument 0 must be a memory descriptor")) }
    let (init, has_init, ie) = desc_index(it, d, "initial", 4294967295.0f64)
    if ie != ok { ret (js.undefv(), ie) }
    if !has_init { ret (js.undefv(), js.throw_type(it, "WebAssembly.Memory(): Property 'initial' is required")) }
    let (mx, has_max, me) = desc_index(it, d, "maximum", 4294967295.0f64)
    if me != ok { ret (js.undefv(), me) }
    if init > 65536.0f64 { ret (js.undefv(), js.throw_range(it, "WebAssembly.Memory(): Property 'initial': value is above the upper bound")) }
    if has_max && mx < init { ret (js.undefv(), js.throw_range(it, "WebAssembly.Memory(): Property 'maximum': value is below the lower bound")) }
    var maxp = 0u32
    if has_max { maxp = u32(mx) }
    let (m, e) = wasm.memory_new(it.a, u32(init), maxp, has_max)
    if e != ok { ret (js.undefv(), js.throw_range(it, "WebAssembly.Memory(): could not allocate memory")) }
    let (proto, pe) = js.proto_value_of(it, js.as_object(it.new_target), rt_of(it).memory_proto)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_WMEMORY, proto)
    o.data = mem.cast[*void](m)
    let le = list.push[*js.Obj](&rt_of(it).mems, o)
    ret (js.obj_value(o), ok)
}

fn memory_grow(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WMEMORY, "WebAssembly.Memory.grow()")
    if de != ok { ret (js.undefv(), de) }
    let m = mem.cast[*wasm.Memory](d)
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    if n != n || n < 0.0f64 || n > 4294967295.0f64 { ret (js.undefv(), js.throw_type(it, "WebAssembly.Memory.grow(): Argument 0 must be convertible to a valid number")) }
    let old = wasm.memory_grow(it.a, m, u32(js.to_integer(n)))
    if old == 4294967295u32 { ret (js.undefv(), js.throw_range(it, "WebAssembly.Memory.grow(): Maximum memory size exceeded")) }
    let mo = js.as_object(this_val)
    if mo.aux != js.null_obj() && mo.aux != zero_obj() {
        let ob = js.buf_of(mo.aux)
        ob.detached = true
        ob.bytes = ob.bytes[0usize..0usize]
        mo.aux = zero_obj()
    }
    ret (js.num_value(f64(old)), ok)
}

fn memory_buffer(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WMEMORY, "WebAssembly.Memory.buffer")
    if de != ok { ret (js.undefv(), de) }
    let m = mem.cast[*wasm.Memory](d)
    let o = js.as_object(this_val)
    let z = js.null_obj()
    if o.aux != z && o.aux != zero_obj() {
        let b = js.buf_of(o.aux)
        if !b.detached && b.bytes.len == m.data.len { ret (js.obj_value(o.aux), ok) }
        b.detached = true
        b.bytes = b.bytes[0usize..0usize]
    }
    let ab = js.new_obj(it, js.C_ARRAYBUFFER, it.protos.array_buffer)
    let (cell, ce) = mem.alloc[js.Buf](it.a, 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    cell[0usize] = js.Buf { bytes: m.data, detached: false, store: m.data, max: m.data.len, resizable: false, is_shared: false, immutable: false }
    ab.data = mem.cast[*void](&cell[0usize])
    o.aux = ab
    ret (js.obj_value(ab), ok)
}

fn elem_type_of(it: *js.Interp, v: js.Value) -> (u8, err) {
    let (s, e) = js.to_string(it, v)
    if e != ok { ret (0u8, e) }
    if str.eq(s, "anyfunc") || str.eq(s, "funcref") { ret (wasm.T_FUNCREF, ok) }
    if str.eq(s, "externref") { ret (wasm.T_EXTERNREF, ok) }
    ret (0u8, js.throw_type(it, "WebAssembly.Table(): Descriptor property 'element' must be a WebAssembly reference type"))
}

fn table_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "WebAssembly.Table must be invoked with 'new'")) }
    let d = arg(args, 0usize)
    if !js.is_object(d) { ret (js.undefv(), js.throw_type(it, "WebAssembly.Table(): Argument 0 must be a table descriptor")) }
    let (ev, ee) = js.get_value(it, d, js.key_of("element"))
    if ee != ok { ret (js.undefv(), ee) }
    let (tt, te) = elem_type_of(it, ev)
    if te != ok { ret (js.undefv(), te) }
    let (init, has_init, ie) = desc_index(it, d, "initial", 4294967295.0f64)
    if ie != ok { ret (js.undefv(), ie) }
    if !has_init { ret (js.undefv(), js.throw_type(it, "WebAssembly.Table(): Property 'initial' is required")) }
    let (mx, has_max, me) = desc_index(it, d, "maximum", 4294967295.0f64)
    if me != ok { ret (js.undefv(), me) }
    if init > 10000000.0f64 { ret (js.undefv(), js.throw_range(it, "WebAssembly.Table(): Property 'initial': value is above the upper bound")) }
    if has_max && mx < init { ret (js.undefv(), js.throw_range(it, "WebAssembly.Table(): Property 'maximum': value is below the lower bound")) }
    var fill = 0u64
    if args.len > 1usize && !js.is_undefined(args[1usize]) {
        let (fv, fe) = to_wasm(it, args[1usize], tt)
        if fe != ok { ret (js.undefv(), fe) }
        fill = fv
    }
    var maxp = 0u32
    if has_max { maxp = u32(mx) }
    let (t, e) = wasm.table_new(it.a, tt, u32(init), maxp, has_max, fill)
    if e != ok { ret (js.undefv(), js.throw_range(it, "WebAssembly.Table(): could not allocate table")) }
    let (proto, pe) = js.proto_value_of(it, js.as_object(it.new_target), rt_of(it).table_proto)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_WTABLE, proto)
    o.data = mem.cast[*void](t)
    let le = list.push[*js.Obj](&rt_of(it).tables, o)
    ret (js.obj_value(o), ok)
}

fn table_length(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WTABLE, "WebAssembly.Table.length")
    if de != ok { ret (js.undefv(), de) }
    ret (js.num_value(f64(mem.cast[*wasm.Table](d).size)), ok)
}

fn index_arg(it: *js.Interp, v: js.Value) -> (u32, err) {
    let (n, e) = js.to_number(it, v)
    if e != ok { ret (0u32, e) }
    if n != n || n < 0.0f64 || n > 4294967295.0f64 { ret (0u32, js.throw_type(it, "WebAssembly: index argument must be convertible to a valid number")) }
    ret (u32(js.to_integer(n)), ok)
}

fn table_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WTABLE, "WebAssembly.Table.get()")
    if de != ok { ret (js.undefv(), de) }
    let t = mem.cast[*wasm.Table](d)
    let (ix, ie) = index_arg(it, arg(args, 0usize))
    if ie != ok { ret (js.undefv(), ie) }
    if ix >= t.size { ret (js.undefv(), js.throw_range(it, "WebAssembly.Table.get(): invalid address in funcref table")) }
    let (v, ve) = from_wasm(it, t.elems[usize(ix)], t.ttype)
    ret (v, ve)
}

fn table_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WTABLE, "WebAssembly.Table.set()")
    if de != ok { ret (js.undefv(), de) }
    let t = mem.cast[*wasm.Table](d)
    let (ix, ie) = index_arg(it, arg(args, 0usize))
    if ie != ok { ret (js.undefv(), ie) }
    if ix >= t.size { ret (js.undefv(), js.throw_range(it, "WebAssembly.Table.set(): invalid address in funcref table")) }
    var val = 0u64
    if args.len > 1usize {
        let (w, we) = to_wasm(it, args[1usize], t.ttype)
        if we != ok { ret (js.undefv(), we) }
        val = w
    }
    t.elems[usize(ix)] = val
    ret (js.undefv(), ok)
}

fn table_grow(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WTABLE, "WebAssembly.Table.grow()")
    if de != ok { ret (js.undefv(), de) }
    let t = mem.cast[*wasm.Table](d)
    let (n, ne) = index_arg(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    var fill = 0u64
    if args.len > 1usize && !js.is_undefined(args[1usize]) {
        let (w, we) = to_wasm(it, args[1usize], t.ttype)
        if we != ok { ret (js.undefv(), we) }
        fill = w
    }
    let old = wasm.table_grow(it.a, t, n, fill)
    if old == 4294967295u32 { ret (js.undefv(), js.throw_range(it, "WebAssembly.Table.grow(): failed to grow table")) }
    ret (js.num_value(f64(old)), ok)
}

fn value_type_of(it: *js.Interp, v: js.Value) -> (u8, err) {
    let (s, e) = js.to_string(it, v)
    if e != ok { ret (0u8, e) }
    if str.eq(s, "i32") { ret (wasm.T_I32, ok) }
    if str.eq(s, "i64") { ret (wasm.T_I64, ok) }
    if str.eq(s, "f32") { ret (wasm.T_F32, ok) }
    if str.eq(s, "f64") { ret (wasm.T_F64, ok) }
    if str.eq(s, "anyfunc") || str.eq(s, "funcref") { ret (wasm.T_FUNCREF, ok) }
    if str.eq(s, "externref") { ret (wasm.T_EXTERNREF, ok) }
    ret (0u8, js.throw_type(it, "WebAssembly.Global(): Descriptor property 'value' must be a WebAssembly type"))
}

fn global_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "WebAssembly.Global must be invoked with 'new'")) }
    let d = arg(args, 0usize)
    if !js.is_object(d) { ret (js.undefv(), js.throw_type(it, "WebAssembly.Global(): Argument 0 must be a global descriptor")) }
    let (mv, me) = js.get_value(it, d, js.key_of("mutable"))
    if me != ok { ret (js.undefv(), me) }
    let (tv, tve) = js.get_value(it, d, js.key_of("value"))
    if tve != ok { ret (js.undefv(), tve) }
    let (vt, vte) = value_type_of(it, tv)
    if vte != ok { ret (js.undefv(), vte) }
    var val = 0u64
    let init = arg(args, 1usize)
    if !js.is_undefined(init) {
        let (w, we) = to_wasm(it, init, vt)
        if we != ok { ret (js.undefv(), we) }
        val = w
    }
    let (g, e) = wasm.global_new(it.a, vt, js.to_boolean(mv), val)
    if e != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let (proto, pe) = js.proto_value_of(it, js.as_object(it.new_target), rt_of(it).global_proto)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_WGLOBAL, proto)
    o.data = mem.cast[*void](g)
    let le = list.push[*js.Obj](&rt_of(it).globals, o)
    ret (js.obj_value(o), ok)
}

fn global_value_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WGLOBAL, "get WebAssembly.Global.value")
    if de != ok { ret (js.undefv(), de) }
    let g = mem.cast[*wasm.Global](d)
    let (v, e) = from_wasm(it, g.value, g.vtype)
    ret (v, e)
}

fn global_value_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WGLOBAL, "set WebAssembly.Global.value")
    if de != ok { ret (js.undefv(), de) }
    let g = mem.cast[*wasm.Global](d)
    if !g.mutable { ret (js.undefv(), js.throw_type(it, "set WebAssembly.Global.value: Can't set the value of an immutable global.")) }
    let (w, we) = to_wasm(it, arg(args, 0usize), g.vtype)
    if we != ok { ret (js.undefv(), we) }
    g.value = w
    ret (js.undefv(), ok)
}

// ---- Instance ----------------------------------------------------------------------------------------------------------

fn instantiate_module(it: *js.Interp, mod_obj: *js.Obj, imports: js.Value, proto: *js.Obj) -> (js.Value, err) {
    let (st, se) = store_of(it)
    if se != ok { ret (js.undefv(), se) }
    let m = mem.cast[*wasm.Module](mod_obj.data)
    if m.imports.len > 0usize && !js.is_object(imports) { ret (js.undefv(), js.throw_type(it, "WebAssembly.Instance(): Imports argument must be present and must be an object")) }
    let (ivs, ie) = mem.alloc[wasm.ImportVal](it.a, m.imports.len + 1usize)
    if ie != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var i = 0usize
    while i < m.imports.len {
        let imp = m.imports[i]
        let (mv, mve) = js.get_value(it, imports, js.key_of(imp.module))
        if mve != ok { ret (js.undefv(), mve) }
        if !js.is_object(mv) { ret (js.undefv(), js.throw_type(it, js.str_concat3(it, "WebAssembly.Instance(): Import #", u32_str(it, u32(i)), ": module is not an object or function"))) }
        let (v, ve) = js.get_value(it, mv, js.key_of(imp.name))
        if ve != ok { ret (js.undefv(), ve) }
        var none_m: *wasm.Memory = zero
        var none_t: *wasm.Table = zero
        var none_g: *wasm.Global = zero
        var iv = wasm.ImportVal { kind: imp.kind, func: 0u32, memory: none_m, table: none_t, global: none_g }
        if imp.kind == .Func {
            if !js.is_callable(v) { ret (js.undefv(), throw_link(it, js.str_concat3(it, "WebAssembly.Instance(): Import #", u32_str(it, u32(i)), ": function import requires a callable"))) }
            let rt = rt_of(it)
            var found = false
            var k = 0usize
            while k < rt.fobjs.len {
                if rt.fobjs.items[k] == js.as_object(v) { iv.func = u32(k)
                    found = true }
                k += 1usize
            }
            if !found {
                let (cell, ce) = mem.alloc[HostCtx](it.a, 1usize)
                if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
                cell[0usize] = HostCtx { it: it, f: v, ftype: m.types[usize(imp.index)] }
                let (id, he) = wasm.host_func(st, m.types[usize(imp.index)], host_call, mem.cast[*void](&cell[0usize]))
                if he != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
                iv.func = id
            }
        } else if imp.kind == .Memory {
            if !js.is_object(v) || js.as_object(v).class != js.C_WMEMORY { ret (js.undefv(), throw_link(it, js.str_concat3(it, "WebAssembly.Instance(): Import #", u32_str(it, u32(i)), ": memory import must be a WebAssembly.Memory object"))) }
            iv.memory = mem.cast[*wasm.Memory](js.as_object(v).data)
        } else if imp.kind == .Table {
            if !js.is_object(v) || js.as_object(v).class != js.C_WTABLE { ret (js.undefv(), throw_link(it, js.str_concat3(it, "WebAssembly.Instance(): Import #", u32_str(it, u32(i)), ": table import requires a WebAssembly.Table"))) }
            iv.table = mem.cast[*wasm.Table](js.as_object(v).data)
        } else {
            if js.is_object(v) && js.as_object(v).class == js.C_WGLOBAL {
                iv.global = mem.cast[*wasm.Global](js.as_object(v).data)
            } else {
                if imp.mutable { ret (js.undefv(), throw_link(it, "WebAssembly.Instance(): mutable global imports must be WebAssembly.Global objects")) }
                let ok_type = (imp.ttype == wasm.T_I32 && js.is_number(v)) || (imp.ttype == wasm.T_F32 && js.is_number(v)) || (imp.ttype == wasm.T_F64 && js.is_number(v)) || (imp.ttype == wasm.T_I64 && js.is_bigint(v))
                if !ok_type { ret (js.undefv(), throw_link(it, js.str_concat3(it, "WebAssembly.Instance(): Import #", u32_str(it, u32(i)), ": global import must be a number, bigint or WebAssembly.Global"))) }
                let (w, we) = to_wasm(it, v, imp.ttype)
                if we != ok { ret (js.undefv(), we) }
                let (g, ge) = wasm.global_new(it.a, imp.ttype, false, w)
                if ge != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
                iv.global = g
            }
        }
        ivs[i] = iv
        i += 1usize
    }
    let (inst, ine) = wasm.instantiate(it.a, st, m, ivs[0usize..m.imports.len])
    if ine != ok {
        if ine == js.Throw { ret (js.undefv(), ine) }
        if ine == wasm.LinkError { ret (js.undefv(), throw_link(it, "WebAssembly.Instance(): incompatible import")) }
        ret (js.undefv(), map_error(it, ine))
    }
    let exports = js.new_obj(it, js.C_OBJECT, js.null_obj())
    exports.has_proto = false
    var x = 0usize
    while x < m.exports.len {
        let ex = m.exports[x]
        var v = js.undefv()
        if ex.kind == .Func {
            v = js.obj_value(func_object(it, inst.funcs[usize(ex.index)]))
        } else if ex.kind == .Memory {
            v = js.obj_value(memory_object(it, inst.mems[usize(ex.index)]))
        } else if ex.kind == .Table {
            v = js.obj_value(table_object(it, inst.tables[usize(ex.index)]))
        } else {
            v = js.obj_value(global_object(it, inst.globals[usize(ex.index)]))
        }
        let de = js.define_data(it, exports, js.key_of(ex.name), v, js.P_ENUMERABLE)
        x += 1usize
    }
    exports.extensible = false
    let o = js.new_obj(it, js.C_WINSTANCE, proto)
    o.data = mem.cast[*void](inst)
    o.aux = exports
    ret (js.obj_value(o), ok)
}

fn instance_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "WebAssembly.Instance must be invoked with 'new'")) }
    let mv = arg(args, 0usize)
    if !js.is_object(mv) || js.as_object(mv).class != js.C_WMODULE { ret (js.undefv(), js.throw_type(it, "WebAssembly.Instance(): Argument 0 must be a WebAssembly.Module")) }
    let (proto, pe) = js.proto_value_of(it, js.as_object(it.new_target), rt_of(it).instance_proto)
    if pe != ok { ret (js.undefv(), pe) }
    let (v, e) = instantiate_module(it, js.as_object(mv), arg(args, 1usize), proto)
    ret (v, e)
}

fn instance_exports(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, de) = this_of(it, this_val, js.C_WINSTANCE, "WebAssembly.Instance.exports")
    if de != ok { ret (js.undefv(), de) }
    ret (js.obj_value(js.as_object(this_val).aux), ok)
}

// ---- validate, compile, instantiate ------------------------------------------------------------------------------------

fn ns_validate(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (bytes, be) = source_bytes(it, arg(args, 0usize))
    if be != ok { ret (js.undefv(), be) }
    let (m, de) = wasm.decode(it.a, bytes)
    ret (js.bool_value(de == ok), ok)
}

fn settle(it: *js.Interp, p: *js.Obj, v: js.Value, e: err) -> err {
    if e == ok {
        js.promise_fulfill(it, p, v)
        ret ok
    }
    if e == js.Throw {
        let reason = it.thrown
        let re = js.promise_reject(it, p, reason)
        ret ok
    }
    ret e
}

fn ns_compile(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (p, pe) = js.new_promise(it)
    if pe != ok { ret (js.undefv(), pe) }
    let (bytes, be) = source_bytes(it, arg(args, 0usize))
    if be != ok {
        let se = settle(it, p, js.undefv(), be)
        ret (js.obj_value(p), se)
    }
    let (v, e) = new_module_object(it, rt_of(it).module_proto, bytes)
    let se = settle(it, p, v, e)
    ret (js.obj_value(p), se)
}

fn ns_instantiate(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (p, pe) = js.new_promise(it)
    if pe != ok { ret (js.undefv(), pe) }
    let first = arg(args, 0usize)
    if js.is_object(first) && js.as_object(first).class == js.C_WMODULE {
        let (v, e) = instantiate_module(it, js.as_object(first), arg(args, 1usize), rt_of(it).instance_proto)
        let se = settle(it, p, v, e)
        ret (js.obj_value(p), se)
    }
    let (bytes, be) = source_bytes(it, first)
    if be != ok {
        let se = settle(it, p, js.undefv(), be)
        ret (js.obj_value(p), se)
    }
    let (mv, me) = new_module_object(it, rt_of(it).module_proto, bytes)
    if me != ok {
        let se = settle(it, p, js.undefv(), me)
        ret (js.obj_value(p), se)
    }
    let (iv, ie) = instantiate_module(it, js.as_object(mv), arg(args, 1usize), rt_of(it).instance_proto)
    if ie != ok {
        let se = settle(it, p, js.undefv(), ie)
        ret (js.obj_value(p), se)
    }
    let res = js.new_plain(it)
    let e1 = js.define_data(it, res, js.key_of("module"), mv, js.P_DEFAULT)
    let e2 = js.define_data(it, res, js.key_of("instance"), iv, js.P_DEFAULT)
    js.promise_fulfill(it, p, js.obj_value(res))
    ret (js.obj_value(p), ok)
}

// ---- Installation ------------------------------------------------------------------------------------------------------

fn compile_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor(it, rt_of(it).compile_proto, args)
    ret (r, e) }
fn link_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor(it, rt_of(it).link_proto, args)
    ret (r, e) }
fn runtime_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor(it, rt_of(it).runtime_proto, args)
    ret (r, e) }

fn error_ctor(it: *js.Interp, proto_default: *js.Obj, args: []const js.Value) -> (js.Value, err) {
    var proto = proto_default
    if it.has_new_target {
        let (p, pe) = js.proto_value_of(it, js.as_object(it.new_target), proto_default)
        if pe != ok { ret (js.undefv(), pe) }
        proto = p
    }
    let o = js.new_obj(it, js.C_ERROR, proto)
    let msg = arg(args, 0usize)
    if !js.is_undefined(msg) {
        let (s, se) = js.to_string(it, msg)
        if se != ok { ret (js.undefv(), se) }
        let e = js.define_data(it, o, js.key_of("message"), js.str_value(s), js.P_HIDDEN)
    }
    ret (js.obj_value(o), ok)
}

fn make_class(it: *js.Interp, ns: *js.Obj, name: str, length: u32, native: js.NativeFn, proto: *js.Obj) -> *js.Obj {
    let c = js.make_native(it, name, length, native)
    c.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, c, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(c), js.P_HIDDEN)
    let e3 = js.define_data(it, ns, js.key_of(name), js.obj_value(c), js.P_HIDDEN)
    let e4 = js.define_data(it, proto, js.key_of_symbol(it.sym_to_string_tag), js.str_value(js.str_concat(it, "WebAssembly.", name)), js.P_CONFIGURABLE)
    ret c
}

fn make_error_class(it: *js.Interp, ns: *js.Obj, name: str, native: js.NativeFn, proto: *js.Obj) {
    let c = js.make_native(it, name, 1u32, native)
    c.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, c, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(c), js.P_HIDDEN)
    let e3 = js.define_data(it, proto, js.key_of("name"), js.str_value(name), js.P_HIDDEN)
    let e4 = js.define_data(it, proto, js.key_of("message"), js.str_value(""), js.P_HIDDEN)
    let e5 = js.define_data(it, ns, js.key_of(name), js.obj_value(c), js.P_HIDDEN)
    // The error constructors inherit from Error.
    let (ev, ee) = js.get_prop(it, it.global, js.key_of("Error"), js.obj_value(it.global))
    if ee == ok && js.is_object(ev) {
        c.proto = js.as_object(ev)
        c.has_proto = true
    }
}

fn install_wasm(it: *js.Interp) {
    let (cell, ce) = mem.alloc[Rt](it.a, 1usize)
    if ce != ok { ret }
    var blank: Rt = zero
    cell[0usize] = blank
    let rt = &cell[0usize]
    it.wasm = mem.cast[*void](rt)
    let (f0, f0e) = list.init[*js.Obj](it.a, 8usize)
    let (m0, m0e) = list.init[*js.Obj](it.a, 4usize)
    let (t0, t0e) = list.init[*js.Obj](it.a, 4usize)
    let (g0, g0e) = list.init[*js.Obj](it.a, 4usize)
    rt.fobjs = f0
    rt.mems = m0
    rt.tables = t0
    rt.globals = g0
    let ns = js.new_plain(it)
    rt.ns = ns
    let e0 = js.define_data(it, it.global, js.key_of("WebAssembly"), js.obj_value(ns), js.P_HIDDEN)
    let e00 = js.define_data(it, ns, js.key_of_symbol(it.sym_to_string_tag), js.str_value("WebAssembly"), js.P_CONFIGURABLE)
    rt.compile_proto = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    rt.link_proto = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    rt.runtime_proto = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    make_error_class(it, ns, "CompileError", compile_error_ctor, rt.compile_proto)
    make_error_class(it, ns, "LinkError", link_error_ctor, rt.link_proto)
    make_error_class(it, ns, "RuntimeError", runtime_error_ctor, rt.runtime_proto)
    rt.module_proto = js.new_plain(it)
    let mc = make_class(it, ns, "Module", 1u32, module_ctor, rt.module_proto)
    js.add_method(it, mc, "exports", 1u32, module_exports)
    js.add_method(it, mc, "imports", 1u32, module_imports)
    js.add_method(it, mc, "customSections", 2u32, module_custom_sections)
    rt.instance_proto = js.new_plain(it)
    let ic = make_class(it, ns, "Instance", 1u32, instance_ctor, rt.instance_proto)
    js.add_getter(it, rt.instance_proto, "exports", instance_exports)
    rt.memory_proto = js.new_plain(it)
    let memc = make_class(it, ns, "Memory", 1u32, memory_ctor, rt.memory_proto)
    js.add_method(it, rt.memory_proto, "grow", 1u32, memory_grow)
    js.add_getter(it, rt.memory_proto, "buffer", memory_buffer)
    rt.table_proto = js.new_plain(it)
    let tc = make_class(it, ns, "Table", 1u32, table_ctor, rt.table_proto)
    js.add_getter(it, rt.table_proto, "length", table_length)
    js.add_method(it, rt.table_proto, "get", 1u32, table_get)
    js.add_method(it, rt.table_proto, "set", 1u32, table_set)
    js.add_method(it, rt.table_proto, "grow", 1u32, table_grow)
    rt.global_proto = js.new_plain(it)
    let gc = make_class(it, ns, "Global", 1u32, global_ctor, rt.global_proto)
    let gget = js.make_native(it, "get value", 0u32, global_value_get)
    let gset = js.make_native(it, "set value", 1u32, global_value_set)
    let ge = js.define_accessor_raw(it, rt.global_proto, js.key_of("value"), gget, gset, js.P_CONFIGURABLE)
    js.add_method(it, rt.global_proto, "valueOf", 0u32, global_value_get)
    js.add_method(it, ns, "validate", 1u32, ns_validate)
    js.add_method(it, ns, "compile", 1u32, ns_compile)
    js.add_method(it, ns, "instantiate", 1u32, ns_instantiate)
}
