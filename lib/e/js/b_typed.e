// ArrayBuffer, the typed array family and DataView (browser tracker 5.8).
//
// The integer-indexed exotic behaviour (element reads and writes through property access) lives in `e.js.interp`; this module
// holds the constructors and methods. Generic algorithms (iteration, searching, reducing) reuse the Array builtins over the
// element accessors after validating the receiver.

use e.data.list as list
use e.js.b_array as barr
use e.js.bigint as bigint
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// --- ArrayBuffer

fn new_buffer(it: *js.Interp, proto: *js.Obj, len: usize) -> (*js.Obj, err) {
    let (o, e) = new_buffer_full(it, proto, len, len, false, false)
    ret (o, e)
}

// A buffer of `len` bytes with room for `max` (a resizable ArrayBuffer or a growable SharedArrayBuffer).
fn new_buffer_full(it: *js.Interp, proto: *js.Obj, len: usize, max: usize, resizable: bool, sh: bool) -> (*js.Obj, err) {
    let o = js.new_obj(it, js.C_ARRAYBUFFER, proto)
    let (cell, ce) = mem.alloc[js.Buf](it.a, 1usize)
    if ce != ok { ret (o, js.throw_range(it, "Array buffer allocation failed")) }
    let (bytes, be) = mem.alloc[u8](it.a, max + 1usize)
    if be != ok { ret (o, js.throw_range(it, "Array buffer allocation failed")) }
    var i = 0usize
    while i < max {
        bytes[i] = 0u8
        i += 1usize
    }
    cell[0usize] = js.Buf { bytes: bytes[0usize..len], detached: false, store: bytes[0usize..max], max: max, resizable: resizable, is_shared: sh }
    o.data = mem.cast[*void](&cell[0usize])
    ret (o, ok)
}

// ToIndex: undefined is 0; a negative or too large integer is a RangeError.
fn to_index(it: *js.Interp, v: js.Value, what: str) -> (f64, err) {
    if js.is_undefined(v) { ret (0.0f64, ok) }
    let (n, ne) = js.to_number(it, v)
    if ne != ok { ret (0.0f64, ne) }
    let len = js.to_integer(n)
    if len < 0.0f64 || len > 9007199254740991.0f64 { ret (0.0f64, js.throw_range(it, what)) }
    ret (len, ok)
}

// The `maxByteLength` of an options object (RangeError when it is invalid); `present` is false when there is none.
fn max_length_option(it: *js.Interp, options: js.Value) -> (f64, bool, err) {
    if !js.is_object(options) { ret (0.0f64, false, ok) }
    let (mv, me) = js.get_prop(it, js.as_object(options), js.key_of("maxByteLength"), options)
    if me != ok { ret (0.0f64, false, me) }
    if js.is_undefined(mv) { ret (0.0f64, false, ok) }
    let (m, e2) = to_index(it, mv, "Invalid array buffer max length")
    if e2 != ok { ret (0.0f64, false, e2) }
    ret (m, true, ok)
}

fn array_buffer_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Constructor ArrayBuffer requires 'new'")) }
    let (len, ne) = to_index(it, arg(args, 0usize), "Invalid array buffer length")
    if ne != ok { ret (js.undefv(), ne) }
    let (maxlen, has_max, mxe) = max_length_option(it, arg(args, 1usize))
    if mxe != ok { ret (js.undefv(), mxe) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.array_buffer)
    if pe != ok { ret (js.undefv(), pe) }
    if has_max && len > maxlen { ret (js.undefv(), js.throw_range(it, "Invalid array buffer max length")) }
    if len > 2147483647.0f64 || (has_max && maxlen > 2147483647.0f64) { ret (js.undefv(), js.throw_range(it, "Array buffer allocation failed")) }
    var cap = len
    if has_max { cap = maxlen }
    let (o, be) = new_buffer_full(it, proto, usize(len), usize(cap), has_max, false)
    if be != ok { ret (js.undefv(), be) }
    ret (js.obj_value(o), ok)
}

fn this_buffer(it: *js.Interp, v: js.Value) -> (*js.Buf, *js.Obj, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_ARRAYBUFFER && !js.buf_of(js.as_object(v)).is_shared {
        ret (js.buf_of(js.as_object(v)), js.as_object(v), ok)
    }
    var none: *js.Buf = zero
    ret (none, js.null_obj(), js.throw_type(it, "Method ArrayBuffer.prototype method called on incompatible receiver"))
}

fn buffer_byte_length(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if b.detached { ret (js.num_value(0.0f64), ok) }
    ret (js.num_value(f64(b.bytes.len)), ok)
}

fn buffer_slice(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
    let len = f64(b.bytes.len)
    let (first, fe) = barr.rel_index(it, arg(args, 0usize), len, 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    let (fin, fine) = barr.rel_index(it, arg(args, 1usize), len, len)
    if fine != ok { ret (js.undefv(), fine) }
    var new_len = fin - first
    if new_len < 0.0f64 { new_len = 0.0f64 }
    // Species constructor.
    let (c, ce) = js.get_prop(it, o, js.key_of("constructor"), this_val)
    if ce != ok { ret (js.undefv(), ce) }
    var ctor = js.obj_value(it.array_buffer_ctor)
    if js.is_object(c) {
        let (sp, spe) = js.get_prop(it, js.as_object(c), js.key_of_symbol(it.sym_species), c)
        if spe != ok { ret (js.undefv(), spe) }
        if !js.is_nullish(sp) {
            if !js.is_constructor(sp) { ret (js.undefv(), js.throw_type(it, "species is not a constructor")) }
            ctor = sp
        }
    } else if !js.is_undefined(c) {
        ret (js.undefv(), js.throw_type(it, "constructor is not an object"))
    }
    let (nv, nve) = js.construct(it, ctor, js.one_arg(it, js.num_value(new_len)), ctor)
    if nve != ok { ret (js.undefv(), nve) }
    if !js.is_object(nv) || js.as_object(nv).class != js.C_ARRAYBUFFER { ret (js.undefv(), js.throw_type(it, "species constructor did not return an ArrayBuffer")) }
    let nb = js.buf_of(js.as_object(nv))
    if nb.detached { ret (js.undefv(), js.throw_type(it, "new ArrayBuffer is detached")) }
    if js.as_object(nv) == o { ret (js.undefv(), js.throw_type(it, "species constructor returned the same buffer")) }
    if f64(nb.bytes.len) < new_len { ret (js.undefv(), js.throw_type(it, "new ArrayBuffer is too small")) }
    if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
    var k = 0usize
    let start = usize(first)
    while f64(k) < new_len && start + k < b.bytes.len {
        nb.bytes[k] = b.bytes[start + k]
        k += 1usize
    }
    ret (nv, ok)
}

fn buffer_is_view(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    ret (js.bool_value(js.is_object(v) && (js.as_object(v).class == js.C_TYPEDARRAY || js.as_object(v).class == js.C_DATAVIEW)), ok)
}

fn species_self(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn detached_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(b.detached), ok)
}

fn max_byte_length_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if b.detached { ret (js.num_value(0.0f64), ok) }
    if b.resizable { ret (js.num_value(f64(b.max)), ok) }
    ret (js.num_value(f64(b.bytes.len)), ok)
}

fn resizable_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(b.resizable), ok)
}

fn set_buffer_length(b: *js.Buf, n: usize) {
    var k = b.bytes.len
    while k < n {
        b.store[k] = 0u8
        k += 1usize
    }
    b.bytes = b.store[0usize..n]
}

fn buffer_resize(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if !b.resizable { ret (js.undefv(), js.throw_type(it, "Method ArrayBuffer.prototype.resize called on incompatible receiver")) }
    let (n, ne) = to_index(it, arg(args, 0usize), "Invalid array buffer length")
    if ne != ok { ret (js.undefv(), ne) }
    if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
    if n > f64(b.max) { ret (js.undefv(), js.throw_range(it, "Invalid array buffer length")) }
    set_buffer_length(b, usize(n))
    ret (js.undefv(), ok)
}

fn buffer_transfer_common(it: *js.Interp, this_val: js.Value, args: []const js.Value, fixed: bool) -> (js.Value, err) {
    let (b, o, e) = this_buffer(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    var new_len = f64(b.bytes.len)
    if !js.is_undefined(arg(args, 0usize)) {
        let (n, ne) = to_index(it, arg(args, 0usize), "Invalid array buffer length")
        if ne != ok { ret (js.undefv(), ne) }
        new_len = n
    }
    if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
    var resizable = b.resizable && !fixed
    var cap = usize(new_len)
    if resizable {
        if new_len > f64(b.max) { ret (js.undefv(), js.throw_range(it, "Invalid array buffer length")) }
        cap = b.max
    }
    if new_len > 2147483647.0f64 { ret (js.undefv(), js.throw_range(it, "Array buffer allocation failed")) }
    let (nb, nbe) = new_buffer_full(it, it.protos.array_buffer, usize(new_len), cap, resizable, false)
    if nbe != ok { ret (js.undefv(), nbe) }
    let nbuf = js.buf_of(nb)
    var k = 0usize
    while k < nbuf.bytes.len && k < b.bytes.len {
        nbuf.bytes[k] = b.bytes[k]
        k += 1usize
    }
    b.detached = true
    b.bytes = b.bytes[0usize..0usize]
    ret (js.obj_value(nb), ok)
}

fn buffer_transfer(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = buffer_transfer_common(it, this_val, args, false)
    ret (r, e)
}

fn buffer_transfer_fixed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = buffer_transfer_common(it, this_val, args, true)
    ret (r, e)
}

// --- SharedArrayBuffer

fn this_shared(it: *js.Interp, v: js.Value) -> (*js.Buf, *js.Obj, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_ARRAYBUFFER && js.buf_of(js.as_object(v)).is_shared {
        ret (js.buf_of(js.as_object(v)), js.as_object(v), ok)
    }
    var none: *js.Buf = zero
    ret (none, js.null_obj(), js.throw_type(it, "Method SharedArrayBuffer.prototype method called on incompatible receiver"))
}

fn shared_buffer_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Constructor SharedArrayBuffer requires 'new'")) }
    let (len, ne) = to_index(it, arg(args, 0usize), "Invalid array buffer length")
    if ne != ok { ret (js.undefv(), ne) }
    let (maxlen, has_max, mxe) = max_length_option(it, arg(args, 1usize))
    if mxe != ok { ret (js.undefv(), mxe) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.ta_protos[0usize])
    if pe != ok { ret (js.undefv(), pe) }
    if has_max && len > maxlen { ret (js.undefv(), js.throw_range(it, "Invalid array buffer max length")) }
    if len > 2147483647.0f64 || (has_max && maxlen > 2147483647.0f64) { ret (js.undefv(), js.throw_range(it, "Array buffer allocation failed")) }
    var cap = len
    if has_max { cap = maxlen }
    let (o, be) = new_buffer_full(it, proto, usize(len), usize(cap), has_max, true)
    if be != ok { ret (js.undefv(), be) }
    ret (js.obj_value(o), ok)
}

fn shared_byte_length(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_shared(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(f64(b.bytes.len)), ok)
}

fn shared_growable(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_shared(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(b.resizable), ok)
}

fn shared_max_byte_length(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_shared(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if b.resizable { ret (js.num_value(f64(b.max)), ok) }
    ret (js.num_value(f64(b.bytes.len)), ok)
}

fn shared_grow(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_shared(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if !b.resizable { ret (js.undefv(), js.throw_type(it, "Method SharedArrayBuffer.prototype.grow called on incompatible receiver")) }
    let (n, ne) = to_index(it, arg(args, 0usize), "Invalid array buffer length")
    if ne != ok { ret (js.undefv(), ne) }
    if n > f64(b.max) || n < f64(b.bytes.len) { ret (js.undefv(), js.throw_range(it, "Invalid array buffer length")) }
    set_buffer_length(b, usize(n))
    ret (js.undefv(), ok)
}

fn shared_slice(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, o, e) = this_shared(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let len = f64(b.bytes.len)
    let (first, fe) = barr.rel_index(it, arg(args, 0usize), len, 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    let (fin, fine) = barr.rel_index(it, arg(args, 1usize), len, len)
    if fine != ok { ret (js.undefv(), fine) }
    var new_len = fin - first
    if new_len < 0.0f64 { new_len = 0.0f64 }
    let (c, ce) = js.get_prop(it, o, js.key_of("constructor"), this_val)
    if ce != ok { ret (js.undefv(), ce) }
    var ctor = js.obj_value(it.ta_ctors[0usize])
    if js.is_object(c) {
        let (sp, spe) = js.get_prop(it, js.as_object(c), js.key_of_symbol(it.sym_species), c)
        if spe != ok { ret (js.undefv(), spe) }
        if !js.is_nullish(sp) {
            if !js.is_constructor(sp) { ret (js.undefv(), js.throw_type(it, "species is not a constructor")) }
            ctor = sp
        }
    } else if !js.is_undefined(c) {
        ret (js.undefv(), js.throw_type(it, "constructor is not an object"))
    }
    let (nv, nve) = js.construct(it, ctor, js.one_arg(it, js.num_value(new_len)), ctor)
    if nve != ok { ret (js.undefv(), nve) }
    if !js.is_object(nv) || js.as_object(nv).class != js.C_ARRAYBUFFER || !js.buf_of(js.as_object(nv)).is_shared { ret (js.undefv(), js.throw_type(it, "species constructor did not return a SharedArrayBuffer")) }
    let nb = js.buf_of(js.as_object(nv))
    if js.as_object(nv) == o { ret (js.undefv(), js.throw_type(it, "species constructor returned the same buffer")) }
    if f64(nb.bytes.len) < new_len { ret (js.undefv(), js.throw_type(it, "new SharedArrayBuffer is too small")) }
    var k = 0usize
    let start = usize(first)
    while f64(k) < new_len && start + k < b.bytes.len {
        nb.bytes[k] = b.bytes[start + k]
        k += 1usize
    }
    ret (nv, ok)
}

fn install_shared_array_buffer(it: *js.Interp) {
    let proto = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.ta_protos[0usize] = proto
    let ctor = js.make_native(it, "SharedArrayBuffer", 1u32, shared_buffer_ctor)
    ctor.ctor_kind = js.K_BASE
    it.ta_ctors[0usize] = ctor
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("SharedArrayBuffer"), js.obj_value(ctor), js.P_HIDDEN)
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e4 = js.define_accessor_raw(it, ctor, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_getter(it, proto, "byteLength", shared_byte_length)
    js.add_getter(it, proto, "growable", shared_growable)
    js.add_getter(it, proto, "maxByteLength", shared_max_byte_length)
    js.add_method(it, proto, "grow", 1u32, shared_grow)
    js.add_method(it, proto, "slice", 2u32, shared_slice)
    let e5 = js.define_data(it, proto, js.key_of_symbol(it.sym_to_string_tag), js.str_value("SharedArrayBuffer"), js.P_CONFIGURABLE)
}

fn detach_host(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_object(v) || js.as_object(v).class != js.C_ARRAYBUFFER { ret (js.undefv(), js.throw_type(it, "not an ArrayBuffer")) }
    let b = js.buf_of(js.as_object(v))
    b.detached = true
    b.bytes = b.bytes[0usize..0usize]
    ret (js.null_value(), ok)
}

fn install_array_buffer(it: *js.Interp) {
    it.protos.array_buffer = js.new_obj(it, js.C_OBJECT, it.protos.object)
    let ctor = js.make_native(it, "ArrayBuffer", 1u32, array_buffer_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(it.protos.array_buffer), 0u8)
    let e2 = js.define_data(it, it.protos.array_buffer, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("ArrayBuffer"), js.obj_value(ctor), js.P_HIDDEN)
    it.array_buffer_ctor = ctor
    it.last = ctor
    js.add_method(it, it.last, "isView", 1u32, buffer_is_view)
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e4 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_getter(it, it.protos.array_buffer, "byteLength", buffer_byte_length)
    js.add_getter(it, it.protos.array_buffer, "maxByteLength", max_byte_length_getter)
    js.add_getter(it, it.protos.array_buffer, "resizable", resizable_getter)
    js.add_getter(it, it.protos.array_buffer, "detached", detached_getter)
    js.add_method(it, it.protos.array_buffer, "slice", 2u32, buffer_slice)
    js.add_method(it, it.protos.array_buffer, "resize", 1u32, buffer_resize)
    js.add_method(it, it.protos.array_buffer, "transfer", 0u32, buffer_transfer)
    js.add_method(it, it.protos.array_buffer, "transferToFixedLength", 0u32, buffer_transfer_fixed)
    install_shared_array_buffer(it)
    let e5 = js.define_data(it, it.protos.array_buffer, js.key_of_symbol(it.sym_to_string_tag), js.str_value("ArrayBuffer"), js.P_CONFIGURABLE)
    // $262.detachArrayBuffer.
    let (h, he) = js.get_prop(it, it.global, js.key_of("$262"), js.obj_value(it.global))
    if he == ok && js.is_object(h) { js.add_method(it, js.as_object(h), "detachArrayBuffer", 1u32, detach_host) }
}

// --- typed arrays

fn kind_name(kind: u8) -> str {
    if kind == 1u8 { ret "Int8Array" }
    if kind == 2u8 { ret "Uint8Array" }
    if kind == 3u8 { ret "Uint8ClampedArray" }
    if kind == 4u8 { ret "Int16Array" }
    if kind == 5u8 { ret "Uint16Array" }
    if kind == 6u8 { ret "Int32Array" }
    if kind == 7u8 { ret "Uint32Array" }
    if kind == 8u8 { ret "Float32Array" }
    if kind == 12u8 { ret "Float16Array" }
    if kind == 10u8 { ret "BigInt64Array" }
    if kind == 11u8 { ret "BigUint64Array" }
    ret "Float64Array"
}

// Validates a typed array receiver; answers its object.
fn validate_ta(it: *js.Interp, v: js.Value) -> (*js.Obj, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_TYPEDARRAY {
        let o = js.as_object(v)
        if js.ta_out_of_bounds(o) { ret (o, js.throw_type(it, "Cannot perform method on a detached or out of bounds ArrayBuffer view")) }
        ret (o, ok)
    }
    ret (js.null_obj(), js.throw_type(it, "this is not a typed array."))
}

fn alloc_ta(it: *js.Interp, kind: u8, proto: *js.Obj, buffer: *js.Obj, offset: usize, length: usize, tracking: bool) -> (*js.Obj, err) {
    let o = js.new_obj(it, js.C_TYPEDARRAY, proto)
    let (cell, ce) = mem.alloc[js.TArr](it.a, 1usize)
    if ce != ok { ret (o, js.throw_range(it, "out of memory")) }
    cell[0usize] = js.TArr { buffer: buffer, offset: offset, length: length, kind: kind, tracking: tracking }
    o.data = mem.cast[*void](&cell[0usize])
    ret (o, ok)
}

fn ta_default_proto(it: *js.Interp, kind: u8) -> *js.Obj { ret it.ta_protos[usize(kind)] }

fn create_typed(it: *js.Interp, kind: u8, proto: *js.Obj, length: usize) -> (*js.Obj, err) {
    let size = js.ta_elem_size(kind)
    if length > 2147483647usize / size { ret (js.null_obj(), js.throw_range(it, "Invalid typed array length")) }
    let (buf, be) = new_buffer(it, it.protos.array_buffer, length * size)
    if be != ok { ret (js.null_obj(), be) }
    let (o, oe) = alloc_ta(it, kind, proto, buf, 0usize, length, false)
    ret (o, oe)
}

fn typed_ctor_common(it: *js.Interp, kind: u8, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Constructor requires 'new'")) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, ta_default_proto(it, kind))
    if pe != ok { ret (js.undefv(), pe) }
    let size = js.ta_elem_size(kind)
    let first = arg(args, 0usize)
    if !js.is_object(first) {
        let (n, ne) = js.to_number(it, first)
        if ne != ok { ret (js.undefv(), ne) }
        let len = js.to_integer(n)
        if len < 0.0f64 || len > 9007199254740991.0f64 || (args.len > 0usize && js.is_undefined(first) && false) { ret (js.undefv(), js.throw_range(it, "Invalid typed array length")) }
        let (o, oe) = create_typed(it, kind, proto, usize(len))
        if oe != ok { ret (js.undefv(), oe) }
        ret (js.obj_value(o), ok)
    }
    let fo = js.as_object(first)
    if fo.class == js.C_ARRAYBUFFER {
        let b = js.buf_of(fo)
        let (off, offe) = js.to_number(it, arg(args, 1usize))
        if offe != ok { ret (js.undefv(), offe) }
        let offset = js.to_integer(off)
        if offset < 0.0f64 || js.is_infinite(offset) { ret (js.undefv(), js.throw_range(it, "Start offset is outside the bounds of the buffer")) }
        if f64(usize(offset)) != offset || usize(offset) % size != 0usize { ret (js.undefv(), js.throw_range(it, "start offset must be a multiple of the element size")) }
        var new_len = 0usize
        var tracking = false
        if js.is_undefined(arg(args, 2usize)) {
            if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
            if usize(offset) > b.bytes.len { ret (js.undefv(), js.throw_range(it, "Start offset is outside the bounds of the buffer")) }
            if b.resizable {
                tracking = true
                new_len = (b.bytes.len - usize(offset)) / size
            } else {
                if (b.bytes.len - usize(offset)) % size != 0usize { ret (js.undefv(), js.throw_range(it, "byte length of the array must be a multiple of the element size")) }
                new_len = (b.bytes.len - usize(offset)) / size
            }
        } else {
            let (ln, lne) = js.to_number(it, args[2usize])
            if lne != ok { ret (js.undefv(), lne) }
            let l2 = js.to_integer(ln)
            if l2 < 0.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid typed array length")) }
            if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
            if usize(offset) + usize(l2) * size > b.bytes.len { ret (js.undefv(), js.throw_range(it, "Invalid typed array length")) }
            new_len = usize(l2)
        }
        let (o2, oe2) = alloc_ta(it, kind, proto, fo, usize(offset), new_len, tracking)
        if oe2 != ok { ret (js.undefv(), oe2) }
        ret (js.obj_value(o2), ok)
    }
    if fo.class == js.C_TYPEDARRAY {
        let src = js.ta_of(fo)
        if js.buf_of(src.buffer).detached { ret (js.undefv(), js.throw_type(it, "source typed array is detached")) }
        let n = js.ta_length(fo)
        if (js.is_big_kind(src.kind)) != (js.is_big_kind(kind)) { ret (js.undefv(), js.throw_type(it, "Cannot mix BigInt and other types, use explicit conversions")) }
        let (o3, oe3) = create_typed(it, kind, proto, n)
        if oe3 != ok { ret (js.undefv(), oe3) }
        var i = 0usize
        while i < n {
            let v = js.ta_get_index(it, fo, i)
            js.ta_set_raw(it, o3, i, js.ta_raw_of_typed(kind, v))
            i += 1usize
        }
        ret (js.obj_value(o3), ok)
    }
    // An iterable or array-like object.
    let (m, me) = js.get_prop(it, fo, js.key_of_symbol(it.sym_iterator), first)
    if me != ok { ret (js.undefv(), me) }
    var items: []const js.Value = js.zero_args()
    if !js.is_nullish(m) {
        if !js.is_callable(m) { ret (js.undefv(), js.throw_type(it, "@@iterator is not a function")) }
        let (vals, ie) = js.iterate_to_list(it, first)
        if ie != ok { ret (js.undefv(), ie) }
        items = list.slice_const[js.Value](&vals)
    } else {
        let (len, le) = js.length_of(it, fo)
        if le != ok { ret (js.undefv(), le) }
        let (l, lie) = list.init[js.Value](it.a, usize(len) + 1usize)
        var out = l
        if lie != ok { ret (js.undefv(), lie) }
        var k = 0.0f64
        while k < len {
            try js.tick(it)
            let (v, ve) = js.get_index(it, fo, k)
            if ve != ok { ret (js.undefv(), ve) }
            try list.push[js.Value](&out, v)
            k += 1.0f64
        }
        items = list.slice_const[js.Value](&out)
    }
    let (o4, oe4) = create_typed(it, kind, proto, items.len)
    if oe4 != ok { ret (js.undefv(), oe4) }
    var j = 0usize
    while j < items.len {
        let (rawj, nne) = js.ta_raw_of(it, kind, items[j])
        if nne != ok { ret (js.undefv(), nne) }
        if j < js.ta_length(o4) { js.ta_set_raw(it, o4, j, rawj) }
        j += 1usize
    }
    ret (js.obj_value(o4), ok)
}

fn ctor_int8(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 1u8, args)
    ret (r, e) }
fn ctor_uint8(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 2u8, args)
    ret (r, e) }
fn ctor_uint8c(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 3u8, args)
    ret (r, e) }
fn ctor_int16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 4u8, args)
    ret (r, e) }
fn ctor_uint16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 5u8, args)
    ret (r, e) }
fn ctor_int32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 6u8, args)
    ret (r, e) }
fn ctor_uint32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 7u8, args)
    ret (r, e) }
fn ctor_float32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 8u8, args)
    ret (r, e) }
fn ctor_float16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 12u8, args)
    ret (r, e) }
fn ctor_bigint64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 10u8, args)
    ret (r, e) }
fn ctor_biguint64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 11u8, args)
    ret (r, e) }
fn ctor_float64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = typed_ctor_common(it, 9u8, args)
    ret (r, e) }

fn abstract_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.undefv(), js.throw_type(it, "Abstract class TypedArray not directly constructable"))
}

// TypedArraySpeciesCreate / TypedArrayCreate: a new typed array via `ctor` with `args`, validated.
fn typed_create(it: *js.Interp, ctor: js.Value, args: []const js.Value, min_len: f64) -> (*js.Obj, err) {
    let (nv, ne) = js.construct(it, ctor, args, ctor)
    if ne != ok { ret (js.null_obj(), ne) }
    let (o, ve) = validate_ta(it, nv)
    if ve != ok { ret (o, ve) }
    if min_len >= 0.0f64 && f64(js.ta_length(o)) < min_len { ret (o, js.throw_type(it, "typed array is too small")) }
    ret (o, ok)
}

fn species_create(it: *js.Interp, exemplar: *js.Obj, args: []const js.Value, min_len: f64) -> (*js.Obj, err) {
    let kind = js.ta_of(exemplar).kind
    var default_ctor = js.obj_value(it.ta_ctors[usize(kind)])
    var ctor = default_ctor
    let (c, ce) = js.get_prop(it, exemplar, js.key_of("constructor"), js.obj_value(exemplar))
    if ce != ok { ret (js.null_obj(), ce) }
    if js.is_object(c) {
        let (sp, spe) = js.get_prop(it, js.as_object(c), js.key_of_symbol(it.sym_species), c)
        if spe != ok { ret (js.null_obj(), spe) }
        if !js.is_nullish(sp) {
            if !js.is_constructor(sp) { ret (js.null_obj(), js.throw_type(it, "species is not a constructor")) }
            ctor = sp
        }
    } else if !js.is_undefined(c) {
        ret (js.null_obj(), js.throw_type(it, "constructor is not an object"))
    }
    let (o, e) = typed_create(it, ctor, args, min_len)
    if e != ok { ret (o, e) }
    ret (o, ok)
}

fn ta_buffer_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), js.throw_type(it, "not a typed array")) }
    ret (js.obj_value(js.ta_of(js.as_object(this_val)).buffer), ok)
}

fn ta_byte_length_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), js.throw_type(it, "not a typed array")) }
    let o = js.as_object(this_val)
    if js.ta_out_of_bounds(o) { ret (js.num_value(0.0f64), ok) }
    ret (js.num_value(f64(js.ta_length(o) * js.ta_elem_size(js.ta_of(o).kind))), ok)
}

fn ta_byte_offset_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), js.throw_type(it, "not a typed array")) }
    let o = js.as_object(this_val)
    if js.ta_out_of_bounds(o) { ret (js.num_value(0.0f64), ok) }
    ret (js.num_value(f64(js.ta_of(o).offset)), ok)
}

fn ta_length_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), js.throw_type(it, "not a typed array")) }
    ret (js.num_value(f64(js.ta_length(js.as_object(this_val)))), ok)
}

fn ta_tag_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), ok) }
    ret (js.str_value(kind_name(js.ta_of(js.as_object(this_val)).kind)), ok)
}

fn ta_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), js.throw_type(it, "not a typed array")) }
    let o = js.as_object(this_val)
    let (off, offe) = js.to_number(it, arg(args, 1usize))
    if offe != ok { ret (js.undefv(), offe) }
    let offset = js.to_integer(off)
    if offset < 0.0f64 { ret (js.undefv(), js.throw_range(it, "offset is out of bounds")) }
    if js.buf_of(js.ta_of(o).buffer).detached { ret (js.undefv(), js.throw_type(it, "typed array is detached")) }
    let target_len = js.ta_length(o)
    let src = arg(args, 0usize)
    let kind = js.ta_of(o).kind
    if js.is_object(src) && js.as_object(src).class == js.C_TYPEDARRAY {
        let so = js.as_object(src)
        if js.buf_of(js.ta_of(so).buffer).detached { ret (js.undefv(), js.throw_type(it, "source is detached")) }
        let n = js.ta_length(so)
        if js.is_infinite(offset) || f64(n) + offset > f64(target_len) { ret (js.undefv(), js.throw_range(it, "offset is out of bounds")) }
        // Copy through a temporary so overlapping views behave.
        let (tmp, te) = mem.alloc[js.Value](it.a, n + 1usize)
        if te != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
        var i = 0usize
        while i < n {
            tmp[i] = js.ta_get_index(it, so, i)
            i += 1usize
        }
        if (js.is_big_kind(js.ta_of(so).kind)) != (js.is_big_kind(kind)) { ret (js.undefv(), js.throw_type(it, "Cannot mix BigInt and other types, use explicit conversions")) }
        var j = 0usize
        while j < n {
            js.ta_set_raw(it, o, usize(offset) + j, js.ta_raw_of_typed(kind, tmp[j]))
            j += 1usize
        }
        ret (js.undefv(), ok)
    }
    let (so2, soe) = js.to_object(it, src)
    if soe != ok { ret (js.undefv(), soe) }
    let (len, le) = js.length_of(it, so2)
    if le != ok { ret (js.undefv(), le) }
    if js.is_infinite(offset) || len + offset > f64(target_len) { ret (js.undefv(), js.throw_range(it, "offset is out of bounds")) }
    var k = 0.0f64
    while k < len {
        try js.tick(it)
        let (v, ve) = js.get_index(it, so2, k)
        if ve != ok { ret (js.undefv(), ve) }
        let (rawk, nne) = js.ta_raw_of(it, kind, v)
        if nne != ok { ret (js.undefv(), nne) }
        let idx = usize(offset) + usize(k)
        if idx < js.ta_length(o) { js.ta_set_raw(it, o, idx, rawk) }
        k += 1.0f64
    }
    ret (js.undefv(), ok)
}

fn ta_subarray(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_TYPEDARRAY { ret (js.undefv(), js.throw_type(it, "not a typed array")) }
    let o = js.as_object(this_val)
    let t = js.ta_of(o)
    let len = f64(js.ta_length(o))
    let (b0, be0) = barr.rel_index(it, arg(args, 0usize), len, 0.0f64)
    if be0 != ok { ret (js.undefv(), be0) }
    var end_arg = arg(args, 1usize)
    var new_len = 0.0f64
    let (e0, ee0) = barr.rel_index(it, end_arg, len, len)
    if ee0 != ok { ret (js.undefv(), ee0) }
    new_len = e0 - b0
    if new_len < 0.0f64 { new_len = 0.0f64 }
    let size = js.ta_elem_size(t.kind)
    let begin_byte = f64(t.offset) + b0 * f64(size)
    var cargs: []const js.Value = js.zero_args()
    if t.tracking && js.is_undefined(end_arg) {
        cargs = js.two_args(it, js.obj_value(t.buffer), js.num_value(begin_byte))
    } else {
        cargs = barr.three_args(it, js.obj_value(t.buffer), js.num_value(begin_byte), js.num_value(new_len))
    }
    let (r, re) = species_create(it, o, cargs, -1.0f64)
    if re != ok { ret (js.undefv(), re) }
    ret (js.obj_value(r), ok)
}

fn ta_slice(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let len = f64(js.ta_length(o))
    let (first, fe) = barr.rel_index(it, arg(args, 0usize), len, 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    let (fin, fine) = barr.rel_index(it, arg(args, 1usize), len, len)
    if fine != ok { ret (js.undefv(), fine) }
    var count = fin - first
    if count < 0.0f64 { count = 0.0f64 }
    let (r, re) = species_create(it, o, js.one_arg(it, js.num_value(count)), count)
    if re != ok { ret (js.undefv(), re) }
    if count > 0.0f64 {
        if js.buf_of(js.ta_of(o).buffer).detached { ret (js.undefv(), js.throw_type(it, "typed array is detached")) }
        let cur = f64(js.ta_length(o))
        var fin2 = fin
        if fin2 > cur { fin2 = cur }
        var k = first
        var n = 0.0f64
        while k < fin2 {
            let v = js.ta_get_index(it, o, usize(k))
            let ee = js.set_index(it, r, n, v)
            if ee != ok { ret (js.undefv(), ee) }
            k += 1.0f64
            n += 1.0f64
        }
    }
    ret (js.obj_value(r), ok)
}

fn ta_fill(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let len = f64(js.ta_length(o))
    let (raw, nne) = js.ta_raw_of(it, js.ta_of(o).kind, arg(args, 0usize))
    if nne != ok { ret (js.undefv(), nne) }
    let (first, fe) = barr.rel_index(it, arg(args, 1usize), len, 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    let (fin, fine) = barr.rel_index(it, arg(args, 2usize), len, len)
    if fine != ok { ret (js.undefv(), fine) }
    if js.buf_of(js.ta_of(o).buffer).detached { ret (js.undefv(), js.throw_type(it, "typed array is detached")) }
    var end2 = fin
    let cur = f64(js.ta_length(o))
    if end2 > cur { end2 = cur }
    var k = first
    while k < end2 {
        js.ta_set_raw(it, o, usize(k), raw)
        k += 1.0f64
    }
    ret (this_val, ok)
}

fn ta_map(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let len = js.ta_length(o)
    let cb = arg(args, 0usize)
    if !js.is_callable(cb) { ret (js.undefv(), js.throw_type(it, "callback is not a function")) }
    let (r, re) = species_create(it, o, js.one_arg(it, js.num_value(f64(len))), f64(len))
    if re != ok { ret (js.undefv(), re) }
    var k = 0usize
    while k < len {
        let v = js.ta_get_index(it, o, k)
        let (mv, me) = js.call_function(it, cb, arg(args, 1usize), barr.three_args(it, v, js.num_value(f64(k)), this_val))
        if me != ok { ret (js.undefv(), me) }
        let se = js.set_index(it, r, f64(k), mv)
        if se != ok { ret (js.undefv(), se) }
        k += 1usize
    }
    ret (js.obj_value(r), ok)
}

fn ta_filter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let len = js.ta_length(o)
    let cb = arg(args, 0usize)
    if !js.is_callable(cb) { ret (js.undefv(), js.throw_type(it, "callback is not a function")) }
    let (kl, kle) = list.init[js.Value](it.a, len + 1usize)
    var kept = kl
    var k = 0usize
    while k < len {
        let v = js.ta_get_index(it, o, k)
        let (mv, me) = js.call_function(it, cb, arg(args, 1usize), barr.three_args(it, v, js.num_value(f64(k)), this_val))
        if me != ok { ret (js.undefv(), me) }
        if js.to_boolean(mv) { try list.push[js.Value](&kept, v) }
        k += 1usize
    }
    let (r, re) = species_create(it, o, js.one_arg(it, js.num_value(f64(kept.len))), f64(kept.len))
    if re != ok { ret (js.undefv(), re) }
    var i = 0usize
    while i < kept.len {
        let se = js.set_index(it, r, f64(i), kept.items[i])
        if se != ok { ret (js.undefv(), se) }
        i += 1usize
    }
    ret (js.obj_value(r), ok)
}

fn ta_sort_compare(it: *js.Interp, cmp: js.Value, x: js.Value, y: js.Value) -> (f64, err) {
    if js.is_callable(cmp) {
        let (r, re) = js.call_function(it, cmp, js.undefv(), js.two_args(it, x, y))
        if re != ok { ret (0.0f64, re) }
        let (n, ne) = js.to_number(it, r)
        if ne != ok { ret (0.0f64, ne) }
        if js.is_nan(n) { ret (0.0f64, ok) }
        ret (n, ok)
    }
    if js.is_bigint(x) && js.is_bigint(y) {
        let c = bigint.cmp(js.big_of(x), js.big_of(y))
        if c < 0i32 { ret (-1.0f64, ok) }
        if c > 0i32 { ret (1.0f64, ok) }
        ret (0.0f64, ok)
    }
    let a = js.num_of(x)
    let b = js.num_of(y)
    if js.is_nan(a) && js.is_nan(b) { ret (0.0f64, ok) }
    if js.is_nan(a) { ret (1.0f64, ok) }
    if js.is_nan(b) { ret (-1.0f64, ok) }
    if a < b { ret (-1.0f64, ok) }
    if a > b { ret (1.0f64, ok) }
    if a == 0.0f64 && b == 0.0f64 {
        if js.is_neg_zero(a) && !js.is_neg_zero(b) { ret (-1.0f64, ok) }
        if !js.is_neg_zero(a) && js.is_neg_zero(b) { ret (1.0f64, ok) }
    }
    ret (0.0f64, ok)
}

fn ta_merge(it: *js.Interp, cmp: js.Value, items: []js.Value, tmp: []js.Value, lo: usize, hi: usize) -> err {
    if hi - lo < 2usize { ret ok }
    let mid = lo + (hi - lo) / 2usize
    try ta_merge(it, cmp, items, tmp, lo, mid)
    try ta_merge(it, cmp, items, tmp, mid, hi)
    var i = lo
    var j = mid
    var k = lo
    while i < mid && j < hi {
        let (c, ce) = ta_sort_compare(it, cmp, items[j], items[i])
        if ce != ok { ret ce }
        if c < 0.0f64 {
            tmp[k] = items[j]
            j += 1usize
        } else {
            tmp[k] = items[i]
            i += 1usize
        }
        k += 1usize
    }
    while i < mid {
        tmp[k] = items[i]
        i += 1usize
        k += 1usize
    }
    while j < hi {
        tmp[k] = items[j]
        j += 1usize
        k += 1usize
    }
    var m = lo
    while m < hi {
        items[m] = tmp[m]
        m += 1usize
    }
    ret ok
}

fn sorted_values(it: *js.Interp, o: *js.Obj, cmp: js.Value) -> ([]js.Value, err) {
    let len = js.ta_length(o)
    let (items, ie) = mem.alloc[js.Value](it.a, len + 1usize)
    if ie != ok { ret (items, js.throw_range(it, "out of memory")) }
    let (tmp, te) = mem.alloc[js.Value](it.a, len + 1usize)
    if te != ok { ret (items, js.throw_range(it, "out of memory")) }
    var i = 0usize
    while i < len {
        items[i] = js.ta_get_index(it, o, i)
        i += 1usize
    }
    try ta_merge(it, cmp, items[0usize..len], tmp[0usize..len], 0usize, len)
    ret (items[0usize..len], ok)
}

fn ta_sort(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let cmp = arg(args, 0usize)
    if !js.is_undefined(cmp) && !js.is_callable(cmp) { ret (js.undefv(), js.throw_type(it, "comparator must be a function or undefined")) }
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let (items, se) = sorted_values(it, o, cmp)
    if se != ok { ret (js.undefv(), se) }
    let cur = js.ta_length(o)
    var i = 0usize
    while i < items.len && i < cur {
        js.ta_set_raw(it, o, i, js.ta_raw_of_typed(js.ta_of(o).kind, items[i]))
        i += 1usize
    }
    ret (this_val, ok)
}

fn ta_to_sorted(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let cmp = arg(args, 0usize)
    if !js.is_undefined(cmp) && !js.is_callable(cmp) { ret (js.undefv(), js.throw_type(it, "comparator must be a function or undefined")) }
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let (items, se) = sorted_values(it, o, cmp)
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = create_typed(it, js.ta_of(o).kind, ta_default_proto(it, js.ta_of(o).kind), items.len)
    if re != ok { ret (js.undefv(), re) }
    var i = 0usize
    while i < items.len {
        js.ta_set_raw(it, r, i, js.ta_raw_of_typed(js.ta_of(o).kind, items[i]))
        i += 1usize
    }
    ret (js.obj_value(r), ok)
}

fn ta_to_reversed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let len = js.ta_length(o)
    let (r, re) = create_typed(it, js.ta_of(o).kind, ta_default_proto(it, js.ta_of(o).kind), len)
    if re != ok { ret (js.undefv(), re) }
    var i = 0usize
    while i < len {
        js.ta_set_raw(it, r, i, js.ta_raw_of_typed(js.ta_of(o).kind, js.ta_get_index(it, o, len - 1usize - i)))
        i += 1usize
    }
    ret (js.obj_value(r), ok)
}

fn ta_with(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, ve) = validate_ta(it, this_val)
    if ve != ok { ret (js.undefv(), ve) }
    let len = f64(js.ta_length(o))
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    var rel = js.to_integer(n)
    if rel < 0.0f64 { rel = len + rel }
    var new_value = arg(args, 1usize)
    if js.is_big_kind(js.ta_of(o).kind) {
        let (nb, nbe) = js.to_bigint(it, new_value)
        if nbe != ok { ret (js.undefv(), nbe) }
        new_value = js.big_value(nb)
    } else {
        let (nv, nve) = js.to_number(it, new_value)
        if nve != ok { ret (js.undefv(), nve) }
        new_value = js.num_value(nv)
    }
    if !js.ta_valid_index(o, rel) { ret (js.undefv(), js.throw_range(it, "Invalid typed array index")) }
    let (r, re) = create_typed(it, js.ta_of(o).kind, ta_default_proto(it, js.ta_of(o).kind), usize(len))
    if re != ok { ret (js.undefv(), re) }
    var i = 0usize
    while f64(i) < len {
        var v = js.ta_get_index(it, o, i)
        if f64(i) == rel { v = new_value }
        js.ta_set_raw(it, r, i, js.ta_raw_of_typed(js.ta_of(o).kind, v))
        i += 1usize
    }
    ret (js.obj_value(r), ok)
}

// Methods that only need the receiver validated before the Array algorithm runs.
fn guarded(it: *js.Interp, this_val: js.Value) -> err {
    let (o, e) = validate_ta(it, this_val)
    ret e
}

fn g_for_each(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_for_each(it, this_val, args)
    ret (r, e)
}
fn g_every(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_every(it, this_val, args)
    ret (r, e)
}
fn g_some(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_some(it, this_val, args)
    ret (r, e)
}
fn g_find(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_find(it, this_val, args)
    ret (r, e)
}
fn g_find_index(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_find_index(it, this_val, args)
    ret (r, e)
}
fn g_find_last(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_find_last(it, this_val, args)
    ret (r, e)
}
fn g_find_last_index(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_find_last_index(it, this_val, args)
    ret (r, e)
}
fn g_index_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_index_of(it, this_val, args)
    ret (r, e)
}
fn g_last_index_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_last_index_of(it, this_val, args)
    ret (r, e)
}
fn g_includes(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_includes(it, this_val, args)
    ret (r, e)
}
fn g_join(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_join(it, this_val, args)
    ret (r, e)
}
fn g_reverse(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_reverse(it, this_val, args)
    ret (r, e)
}
fn g_reduce(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_reduce(it, this_val, args)
    ret (r, e)
}
fn g_reduce_right(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_reduce_right(it, this_val, args)
    ret (r, e)
}
fn g_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_at(it, this_val, args)
    ret (r, e)
}
fn g_copy_within(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_copy_within(it, this_val, args)
    ret (r, e)
}
fn g_keys(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_keys(it, this_val, args)
    ret (r, e)
}
fn g_values(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_values(it, this_val, args)
    ret (r, e)
}
fn g_entries(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_entries(it, this_val, args)
    ret (r, e)
}

fn ta_to_locale_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let ge = guarded(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (r, e) = barr.array_join(it, this_val, js.zero_args())
    ret (r, e)
}

fn ta_from(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_constructor(this_val) { ret (js.undefv(), js.throw_type(it, "TypedArray.from: this is not a constructor")) }
    let mapper = arg(args, 1usize)
    if !js.is_undefined(mapper) && !js.is_callable(mapper) { ret (js.undefv(), js.throw_type(it, "mapper is not a function")) }
    let src = arg(args, 0usize)
    var items: []const js.Value = js.zero_args()
    let (m, me) = js.get_value(it, src, js.key_of_symbol(it.sym_iterator))
    if me != ok { ret (js.undefv(), me) }
    if !js.is_nullish(m) {
        let (vals, ie) = js.iterate_to_list(it, src)
        if ie != ok { ret (js.undefv(), ie) }
        items = list.slice_const[js.Value](&vals)
    } else {
        let (so, soe) = js.to_object(it, src)
        if soe != ok { ret (js.undefv(), soe) }
        let (len, le) = js.length_of(it, so)
        if le != ok { ret (js.undefv(), le) }
        let (l, lie) = list.init[js.Value](it.a, usize(len) + 1usize)
        var out = l
        if lie != ok { ret (js.undefv(), lie) }
        var k = 0.0f64
        while k < len {
            let (v, ve) = js.get_index(it, so, k)
            if ve != ok { ret (js.undefv(), ve) }
            try list.push[js.Value](&out, v)
            k += 1.0f64
        }
        items = list.slice_const[js.Value](&out)
    }
    let (r, re) = typed_create(it, this_val, js.one_arg(it, js.num_value(f64(items.len))), f64(items.len))
    if re != ok { ret (js.undefv(), re) }
    var i = 0usize
    while i < items.len {
        var v2 = items[i]
        if js.is_callable(mapper) {
            let (mv, mve) = js.call_function(it, mapper, arg(args, 2usize), js.two_args(it, v2, js.num_value(f64(i))))
            if mve != ok { ret (js.undefv(), mve) }
            v2 = mv
        }
        let se = js.set_index(it, r, f64(i), v2)
        if se != ok { ret (js.undefv(), se) }
        i += 1usize
    }
    ret (js.obj_value(r), ok)
}

fn ta_of_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_constructor(this_val) { ret (js.undefv(), js.throw_type(it, "TypedArray.of: this is not a constructor")) }
    let (r, re) = typed_create(it, this_val, js.one_arg(it, js.num_value(f64(args.len))), f64(args.len))
    if re != ok { ret (js.undefv(), re) }
    var i = 0usize
    while i < args.len {
        let se = js.set_index(it, r, f64(i), args[i])
        if se != ok { ret (js.undefv(), se) }
        i += 1usize
    }
    ret (js.obj_value(r), ok)
}

fn install_typed_arrays(it: *js.Interp) {
    // %TypedArray% and its prototype.
    let tap = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.typed_array = tap
    let abs = js.make_native(it, "TypedArray", 0u32, abstract_ctor)
    abs.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, abs, js.key_of("prototype"), js.obj_value(tap), 0u8)
    let e2 = js.define_data(it, tap, js.key_of("constructor"), js.obj_value(abs), js.P_HIDDEN)
    it.last = abs
    it.last_abstract = abs
    js.add_method(it, it.last, "from", 1u32, ta_from)
    js.add_method(it, it.last, "of", 0u32, ta_of_fn)
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e3 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_getter(it, it.protos.typed_array, "buffer", ta_buffer_getter)
    js.add_getter(it, it.protos.typed_array, "byteLength", ta_byte_length_getter)
    js.add_getter(it, it.protos.typed_array, "byteOffset", ta_byte_offset_getter)
    js.add_getter(it, it.protos.typed_array, "length", ta_length_getter)
    let tg = js.make_native(it, "get [Symbol.toStringTag]", 0u32, ta_tag_getter)
    let e4 = js.define_accessor_raw(it, it.protos.typed_array, js.key_of_symbol(it.sym_to_string_tag), tg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.typed_array, "set", 1u32, ta_set)
    js.add_method(it, it.protos.typed_array, "subarray", 2u32, ta_subarray)
    js.add_method(it, it.protos.typed_array, "slice", 2u32, ta_slice)
    js.add_method(it, it.protos.typed_array, "fill", 1u32, ta_fill)
    js.add_method(it, it.protos.typed_array, "map", 1u32, ta_map)
    js.add_method(it, it.protos.typed_array, "filter", 1u32, ta_filter)
    js.add_method(it, it.protos.typed_array, "sort", 1u32, ta_sort)
    js.add_method(it, it.protos.typed_array, "toSorted", 1u32, ta_to_sorted)
    js.add_method(it, it.protos.typed_array, "toReversed", 0u32, ta_to_reversed)
    js.add_method(it, it.protos.typed_array, "with", 2u32, ta_with)
    js.add_method(it, it.protos.typed_array, "forEach", 1u32, g_for_each)
    js.add_method(it, it.protos.typed_array, "every", 1u32, g_every)
    js.add_method(it, it.protos.typed_array, "some", 1u32, g_some)
    js.add_method(it, it.protos.typed_array, "find", 1u32, g_find)
    js.add_method(it, it.protos.typed_array, "findIndex", 1u32, g_find_index)
    js.add_method(it, it.protos.typed_array, "findLast", 1u32, g_find_last)
    js.add_method(it, it.protos.typed_array, "findLastIndex", 1u32, g_find_last_index)
    js.add_method(it, it.protos.typed_array, "indexOf", 1u32, g_index_of)
    js.add_method(it, it.protos.typed_array, "lastIndexOf", 1u32, g_last_index_of)
    js.add_method(it, it.protos.typed_array, "includes", 1u32, g_includes)
    js.add_method(it, it.protos.typed_array, "join", 1u32, g_join)
    js.add_method(it, it.protos.typed_array, "reverse", 0u32, g_reverse)
    js.add_method(it, it.protos.typed_array, "reduce", 1u32, g_reduce)
    js.add_method(it, it.protos.typed_array, "reduceRight", 1u32, g_reduce_right)
    js.add_method(it, it.protos.typed_array, "at", 1u32, g_at)
    js.add_method(it, it.protos.typed_array, "copyWithin", 2u32, g_copy_within)
    js.add_method(it, it.protos.typed_array, "keys", 0u32, g_keys)
    js.add_method(it, it.protos.typed_array, "entries", 0u32, g_entries)
    js.add_method(it, it.protos.typed_array, "toLocaleString", 0u32, ta_to_locale_string)
    let vals = js.make_native(it, "values", 0u32, g_values)
    let e5 = js.define_data(it, it.protos.typed_array, js.key_of("values"), js.obj_value(vals), js.P_HIDDEN)
    let e6 = js.define_data(it, it.protos.typed_array, js.key_of_symbol(it.sym_iterator), js.obj_value(vals), js.P_HIDDEN)
    // toString is the same function object as Array.prototype.toString.
    let (ats, atse) = js.get_prop(it, it.protos.array, js.key_of("toString"), js.obj_value(it.protos.array))
    if atse == ok { let e7 = js.define_data(it, it.protos.typed_array, js.key_of("toString"), ats, js.P_HIDDEN) }
    // The concrete constructors.
    var kind = 1u8
    while kind <= 12u8 {
        let proto = js.new_obj(it, js.C_OBJECT, it.protos.typed_array)
        it.ta_protos[usize(kind)] = proto
        var native: js.NativeFn = ctor_int8
        if kind == 2u8 { native = ctor_uint8 } else if kind == 3u8 { native = ctor_uint8c } else if kind == 4u8 { native = ctor_int16 } else if kind == 5u8 { native = ctor_uint16 } else if kind == 6u8 { native = ctor_int32 } else if kind == 7u8 { native = ctor_uint32 } else if kind == 8u8 { native = ctor_float32 } else if kind == 9u8 { native = ctor_float64 } else if kind == 10u8 { native = ctor_bigint64 } else if kind == 11u8 { native = ctor_biguint64 } else if kind == 12u8 { native = ctor_float16 }
        let c = js.make_native(it, kind_name(kind), 3u32, native)
        c.ctor_kind = js.K_BASE
        c.proto = it.last_abstract
        c.has_proto = true
        let d1 = js.define_data(it, c, js.key_of("prototype"), js.obj_value(proto), 0u8)
        let d2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(c), js.P_HIDDEN)
        let bpe = js.define_data(it, c, js.key_of("BYTES_PER_ELEMENT"), js.num_value(f64(js.ta_elem_size(kind))), 0u8)
        let bpe2 = js.define_data(it, proto, js.key_of("BYTES_PER_ELEMENT"), js.num_value(f64(js.ta_elem_size(kind))), 0u8)
        let d3 = js.define_data(it, it.global, js.key_of(kind_name(kind)), js.obj_value(c), js.P_HIDDEN)
        it.ta_ctors[usize(kind)] = c
        kind += 1u8
    }
}

// --- DataView

type DView = struct { buffer: *js.Obj, offset: usize, length: usize, tracking: bool }

fn dv_of(o: *js.Obj) -> *DView { ret mem.cast[*DView](o.data) }

fn dataview_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Constructor DataView requires 'new'")) }
    let bv = arg(args, 0usize)
    if !js.is_object(bv) || js.as_object(bv).class != js.C_ARRAYBUFFER { ret (js.undefv(), js.throw_type(it, "First argument to DataView constructor must be an ArrayBuffer")) }
    let b = js.buf_of(js.as_object(bv))
    let (off, offe) = js.to_number(it, arg(args, 1usize))
    if offe != ok { ret (js.undefv(), offe) }
    let offset = js.to_integer(off)
    if offset < 0.0f64 || js.is_infinite(offset) { ret (js.undefv(), js.throw_range(it, "Start offset is outside the bounds of the buffer")) }
    if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
    if offset > f64(b.bytes.len) { ret (js.undefv(), js.throw_range(it, "Start offset is outside the bounds of the buffer")) }
    var view_len = f64(b.bytes.len) - offset
    var dv_tracking = b.resizable && js.is_undefined(arg(args, 2usize))
    if !js.is_undefined(arg(args, 2usize)) {
        let (ln, lne) = js.to_number(it, args[2usize])
        if lne != ok { ret (js.undefv(), lne) }
        let l2 = js.to_integer(ln)
        if l2 < 0.0f64 || offset + l2 > f64(b.bytes.len) { ret (js.undefv(), js.throw_range(it, "Invalid DataView length")) }
        view_len = l2
    }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.data_view)
    if pe != ok { ret (js.undefv(), pe) }
    if b.detached { ret (js.undefv(), js.throw_type(it, "ArrayBuffer is detached")) }
    let o = js.new_obj(it, js.C_DATAVIEW, proto)
    let (cell, ce) = mem.alloc[DView](it.a, 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    cell[0usize] = DView { buffer: js.as_object(bv), offset: usize(offset), length: usize(view_len), tracking: dv_tracking }
    o.data = mem.cast[*void](&cell[0usize])
    ret (js.obj_value(o), ok)
}

fn this_dv(it: *js.Interp, v: js.Value) -> (*DView, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_DATAVIEW { ret (dv_of(js.as_object(v)), ok) }
    var none: *DView = zero
    ret (none, js.throw_type(it, "Receiver is not a DataView"))
}

// Whether the view lies outside its buffer now, and the byte length it has.
fn dv_state(d: *DView) -> (bool, usize) {
    let b = js.buf_of(d.buffer)
    if b.detached { ret (true, 0usize) }
    if d.tracking {
        if d.offset > b.bytes.len { ret (true, 0usize) }
        ret (false, b.bytes.len - d.offset)
    }
    if d.offset + d.length > b.bytes.len { ret (true, 0usize) }
    ret (false, d.length)
}

fn dv_buffer_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, e) = this_dv(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.obj_value(d.buffer), ok)
}

fn dv_byte_length_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, e) = this_dv(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (oob, vlen) = dv_state(d)
    if oob { ret (js.undefv(), js.throw_type(it, "DataView is detached or out of bounds")) }
    ret (js.num_value(f64(vlen)), ok)
}

fn dv_byte_offset_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (d, e) = this_dv(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (oob, vlen) = dv_state(d)
    if oob { ret (js.undefv(), js.throw_type(it, "DataView is detached or out of bounds")) }
    ret (js.num_value(f64(d.offset)), ok)
}

fn dv_get(it: *js.Interp, this_val: js.Value, args: []const js.Value, kind: u8) -> (js.Value, err) {
    let (d, e) = this_dv(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let idx = js.to_integer(n)
    if idx < 0.0f64 || js.is_infinite(idx) { ret (js.undefv(), js.throw_range(it, "Offset is outside the bounds of the DataView")) }
    let little = js.to_boolean(arg(args, 1usize))
    let b = js.buf_of(d.buffer)
    let (oob, vlen) = dv_state(d)
    if oob { ret (js.undefv(), js.throw_type(it, "DataView is detached or out of bounds")) }
    let size = js.ta_elem_size(kind)
    if idx + f64(size) > f64(vlen) { ret (js.undefv(), js.throw_range(it, "Offset is outside the bounds of the DataView")) }
    var raw = 0u64
    var i = 0usize
    while i < size {
        let byte_at = usize(idx) + i
        var shift = 8usize * i
        if !little { shift = 8usize * (size - 1usize - i) }
        raw = raw | (u64(b.bytes[d.offset + byte_at]) << u64(shift))
        i += 1usize
    }
    ret (js.raw_to_value(it, kind, raw), ok)
}

fn dv_set(it: *js.Interp, this_val: js.Value, args: []const js.Value, kind: u8) -> (js.Value, err) {
    let (d, e) = this_dv(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let idx = js.to_integer(n)
    if idx < 0.0f64 || js.is_infinite(idx) { ret (js.undefv(), js.throw_range(it, "Offset is outside the bounds of the DataView")) }
    let (raw, vne) = js.ta_raw_of(it, kind, arg(args, 1usize))
    if vne != ok { ret (js.undefv(), vne) }
    let little = js.to_boolean(arg(args, 2usize))
    let b = js.buf_of(d.buffer)
    let (oob, vlen) = dv_state(d)
    if oob { ret (js.undefv(), js.throw_type(it, "DataView is detached or out of bounds")) }
    let size = js.ta_elem_size(kind)
    if idx + f64(size) > f64(vlen) { ret (js.undefv(), js.throw_range(it, "Offset is outside the bounds of the DataView")) }
    var i = 0usize
    while i < size {
        var shift = 8usize * i
        if !little { shift = 8usize * (size - 1usize - i) }
        b.bytes[d.offset + usize(idx) + i] = u8((raw >> u64(shift)) & 255u64)
        i += 1usize
    }
    ret (js.undefv(), ok)
}

fn dv_get_int8(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 1u8)
    ret (r, e) }
fn dv_get_uint8(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 2u8)
    ret (r, e) }
fn dv_get_int16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 4u8)
    ret (r, e) }
fn dv_get_uint16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 5u8)
    ret (r, e) }
fn dv_get_int32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 6u8)
    ret (r, e) }
fn dv_get_uint32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 7u8)
    ret (r, e) }
fn dv_get_float16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 12u8)
    ret (r, e) }
fn dv_get_float32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 8u8)
    ret (r, e) }
fn dv_get_float64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 9u8)
    ret (r, e) }
fn dv_set_float16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 12u8)
    ret (r, e) }
fn dv_set_int8(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 1u8)
    ret (r, e) }
fn dv_set_uint8(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 2u8)
    ret (r, e) }
fn dv_set_int16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 4u8)
    ret (r, e) }
fn dv_set_uint16(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 5u8)
    ret (r, e) }
fn dv_set_int32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 6u8)
    ret (r, e) }
fn dv_set_uint32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 7u8)
    ret (r, e) }
fn dv_set_float32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 8u8)
    ret (r, e) }
fn dv_get_bigint64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 10u8)
    ret (r, e) }
fn dv_get_biguint64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_get(it, this_val, args, 11u8)
    ret (r, e) }
fn dv_set_bigint64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 10u8)
    ret (r, e) }
fn dv_set_biguint64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 11u8)
    ret (r, e) }
fn dv_set_float64(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = dv_set(it, this_val, args, 9u8)
    ret (r, e) }

fn install_data_view(it: *js.Interp) {
    it.protos.data_view = js.new_obj(it, js.C_OBJECT, it.protos.object)
    let ctor = js.make_native(it, "DataView", 1u32, dataview_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(it.protos.data_view), 0u8)
    let e2 = js.define_data(it, it.protos.data_view, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("DataView"), js.obj_value(ctor), js.P_HIDDEN)
    js.add_getter(it, it.protos.data_view, "buffer", dv_buffer_getter)
    js.add_getter(it, it.protos.data_view, "byteLength", dv_byte_length_getter)
    js.add_getter(it, it.protos.data_view, "byteOffset", dv_byte_offset_getter)
    let e4 = js.define_data(it, it.protos.data_view, js.key_of_symbol(it.sym_to_string_tag), js.str_value("DataView"), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.data_view, "getBigInt64", 1u32, dv_get_bigint64)
    js.add_method(it, it.protos.data_view, "getBigUint64", 1u32, dv_get_biguint64)
    js.add_method(it, it.protos.data_view, "setBigInt64", 2u32, dv_set_bigint64)
    js.add_method(it, it.protos.data_view, "setBigUint64", 2u32, dv_set_biguint64)
    js.add_method(it, it.protos.data_view, "getInt8", 1u32, dv_get_int8)
    js.add_method(it, it.protos.data_view, "getUint8", 1u32, dv_get_uint8)
    js.add_method(it, it.protos.data_view, "getInt16", 1u32, dv_get_int16)
    js.add_method(it, it.protos.data_view, "getUint16", 1u32, dv_get_uint16)
    js.add_method(it, it.protos.data_view, "getInt32", 1u32, dv_get_int32)
    js.add_method(it, it.protos.data_view, "getUint32", 1u32, dv_get_uint32)
    js.add_method(it, it.protos.data_view, "getFloat16", 1u32, dv_get_float16)
    js.add_method(it, it.protos.data_view, "getFloat32", 1u32, dv_get_float32)
    js.add_method(it, it.protos.data_view, "getFloat64", 1u32, dv_get_float64)
    js.add_method(it, it.protos.data_view, "setInt8", 2u32, dv_set_int8)
    js.add_method(it, it.protos.data_view, "setUint8", 2u32, dv_set_uint8)
    js.add_method(it, it.protos.data_view, "setInt16", 2u32, dv_set_int16)
    js.add_method(it, it.protos.data_view, "setUint16", 2u32, dv_set_uint16)
    js.add_method(it, it.protos.data_view, "setInt32", 2u32, dv_set_int32)
    js.add_method(it, it.protos.data_view, "setUint32", 2u32, dv_set_uint32)
    js.add_method(it, it.protos.data_view, "setFloat16", 2u32, dv_set_float16)
    js.add_method(it, it.protos.data_view, "setFloat32", 2u32, dv_set_float32)
    js.add_method(it, it.protos.data_view, "setFloat64", 2u32, dv_set_float64)
}
