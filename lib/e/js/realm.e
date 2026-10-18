// The JavaScript realm (browser tracker 5.7): the global object and the standard builtins installed over an `e.js.interp`
// interpreter -- Object, Function, Error types, Symbol, Boolean, Number, String, Array, Math, JSON and the global functions.
//
// `new_realm` builds an interpreter with every intrinsic in place; `run` evaluates a script in it. Builtin functions are
// natives of the shape `fn(*js.Interp, this, args) -> (js.Value, err)`.

use e.data.list as list
use e.io
use e.js.ast as ast
use e.js.b_array as b_array
use e.js.b_bigint as b_bigint
use e.js.b_collections as b_collections
use e.js.b_control as b_control
use e.js.b_date as b_date
use e.js.b_json as b_json
use e.js.b_misc as b_misc
use e.js.b_number as b_number
use e.js.b_proxy as b_proxy
use e.js.b_regexp as b_regexp
use e.js.b_string as b_string
use e.js.b_atomics as b_atomics
use e.js.b_typed as b_typed
use e.js.interp as js
use e.js.parser as jsparse
use e.js.prelude as prelude
use e.js.temporal as temporal
use e.js.intl as intl
use e.math
use e.mem
use e.str
use e.sync
use e.thread
use e.time

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// A constructor function object with a prototype object; `ctor_kind` marks it constructible.
fn make_ctor(it: *js.Interp, name: str, length: u32, native: js.NativeFn, proto: *js.Obj) -> *js.Obj {
    let c = js.make_native(it, name, length, native)
    c.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, c, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(c), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of(name), js.obj_value(c), js.P_HIDDEN)
    it.last = c
    ret c
}

// --- Object

fn object_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if it.has_new_target && !js.strict_equals(it.new_target, js.obj_value(it.callee)) {
        let nto = js.as_object(it.new_target)
        let (proto, pe) = js.proto_value_of(it, nto, it.protos.object)
        if pe != ok { ret (js.undefv(), pe) }
        ret (js.obj_value(js.new_obj(it, js.C_OBJECT, proto)), ok)
    }
    if js.is_nullish(v) { ret (js.obj_value(js.new_plain(it)), ok) }
    let (o, e) = js.to_object(it, v)
    ret (js.obj_value(o), e)
}

fn object_proto_has_own(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (k, ke) = js.to_property_key(it, arg(args, 0usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    ret (js.bool_value(js.has_own(it, o, k)), ok)
}

fn object_proto_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if js.is_undefined(this_val) { ret (js.str_value("[object Undefined]"), ok) }
    if js.is_null(this_val) { ret (js.str_value("[object Null]"), ok) }
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    var tag = "Object"
    if o.class == js.C_ARRAY { tag = "Array" }
    if o.class == js.C_PROXY {
        let (pa, pae) = js.is_array_e(it, js.obj_value(o))
        if pae != ok { ret (js.undefv(), pae) }
        if pa { tag = "Array" } else if js.is_callable(js.obj_value(o)) { tag = "Function" }
    }
    if o.class == js.C_FUNCTION || o.class == js.C_BOUND { tag = "Function" }
    if o.class == js.C_ERROR { tag = "Error" }
    if o.class == js.C_BOOLEAN { tag = "Boolean" }
    if o.class == js.C_NUMBER { tag = "Number" }
    if o.class == js.C_STRING { tag = "String" }
    if o.class == js.C_DATE { tag = "Date" }
    if o.class == js.C_REGEXP { tag = "RegExp" }
    if o.class == js.C_ARGUMENTS { tag = "Arguments" }
    let (tv, te) = js.get_prop(it, o, js.key_of_symbol(it.sym_to_string_tag), this_val)
    if te != ok { ret (js.undefv(), te) }
    if js.is_string(tv) { tag = js.value_str(tv) }
    ret (js.str_value(js.str_concat3(it, "[object ", tag, "]")), ok)
}

fn object_proto_value_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = js.to_object(it, this_val)
    ret (js.obj_value(o), e)
}

fn object_proto_is_prototype_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_object(v) { ret (js.bool_value(false), ok) }
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    var cur = js.as_object(v)
    var guard = 0u32
    while guard < 100000u32 {
        guard += 1u32
        let (pv, pe) = js.proto_get(it, cur)
        if pe != ok { ret (js.undefv(), pe) }
        if !js.is_object(pv) { ret (js.bool_value(false), ok) }
        cur = js.as_object(pv)
        if cur == o { ret (js.bool_value(true), ok) }
    }
    ret (js.bool_value(false), ok)
}

fn object_proto_property_is_enumerable(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (k, ke) = js.to_property_key(it, arg(args, 0usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (p, found) = js.get_own(it, o, k)
    ret (js.bool_value(found && (p.flags & js.P_ENUMERABLE) != 0u8), ok)
}

fn object_get_proto(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (pv, pe) = js.proto_get(it, o)
    ret (pv, pe)
}

fn object_set_proto(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "Object.prototype.__proto__ called on null or undefined")) }
    let v = arg(args, 0usize)
    if !js.is_object(this_val) { ret (js.undefv(), ok) }
    if !js.is_object(v) && !js.is_null(v) { ret (js.undefv(), ok) }
    let o = js.as_object(this_val)
    let e = set_prototype(it, o, v)
    if e != ok { ret (js.undefv(), e) }
    ret (js.undefv(), ok)
}

fn set_prototype(it: *js.Interp, o: *js.Obj, v: js.Value) -> err {
    let (done, de) = js.proto_set(it, o, v)
    if de != ok { ret de }
    if !done { ret js.throw_type(it, "Cannot set the prototype of this object") }
    ret ok
}

fn object_define_property(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let tgt = arg(args, 0usize)
    if !js.is_object(tgt) { ret (js.undefv(), js.throw_type(it, "Object.defineProperty called on non-object")) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (d, de) = js.to_descriptor(it, arg(args, 2usize))
    if de != ok { ret (js.undefv(), de) }
    let (done, e) = js.define_own(it, js.as_object(tgt), k, d)
    if e != ok { ret (js.undefv(), e) }
    if !done { ret (js.undefv(), js.throw_type(it, js.str_concat3(it, "Cannot redefine property: ", js.describe_key(it, k), ""))) }
    ret (tgt, ok)
}

fn define_properties_from(it: *js.Interp, o: *js.Obj, props: js.Value) -> err {
    let (po, pe) = js.to_object(it, props)
    if pe != ok { ret pe }
    let (keys, ke) = js.own_keys(it, po)
    if ke != ok { ret ke }
    // Read every descriptor first, then define.
    let (dl, dle) = list.init[js.Desc](it.a, keys.len + 1usize)
    var descs = dl
    let (kl, kle) = list.init[js.Key](it.a, keys.len + 1usize)
    var used = kl
    var i = 0usize
    while i < keys.len {
        let (p, found) = js.get_own(it, po, keys[i])
        if found && (p.flags & js.P_ENUMERABLE) != 0u8 {
            let (dv, dve) = js.get_prop(it, po, keys[i], props)
            if dve != ok { ret dve }
            let (d, de) = js.to_descriptor(it, dv)
            if de != ok { ret de }
            try list.push[js.Desc](&descs, d)
            try list.push[js.Key](&used, keys[i])
        }
        i += 1usize
    }
    var j = 0usize
    while j < descs.len {
        let (done, e) = js.define_own(it, o, used.items[j], descs.items[j])
        if e != ok { ret e }
        if !done { ret js.throw_type(it, "Cannot redefine property") }
        j += 1usize
    }
    ret ok
}

fn object_define_properties(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let tgt = arg(args, 0usize)
    if !js.is_object(tgt) { ret (js.undefv(), js.throw_type(it, "Object.defineProperties called on non-object")) }
    let e = define_properties_from(it, js.as_object(tgt), arg(args, 1usize))
    if e != ok { ret (js.undefv(), e) }
    ret (tgt, ok)
}

fn object_create(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let p = arg(args, 0usize)
    if !js.is_object(p) && !js.is_null(p) { ret (js.undefv(), js.throw_type(it, "Object prototype may only be an Object or null")) }
    var proto = js.null_obj()
    if js.is_object(p) { proto = js.as_object(p) }
    let o = js.new_obj(it, js.C_OBJECT, proto)
    let props = arg(args, 1usize)
    if !js.is_undefined(props) {
        let e = define_properties_from(it, o, props)
        if e != ok { ret (js.undefv(), e) }
    }
    ret (js.obj_value(o), ok)
}

fn object_get_prototype_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (pv, pe) = js.proto_get(it, o)
    ret (pv, pe)
}

fn object_set_prototype_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let tgt = arg(args, 0usize)
    if js.is_nullish(tgt) { ret (js.undefv(), js.throw_type(it, "Object.setPrototypeOf called on null or undefined")) }
    let p = arg(args, 1usize)
    if !js.is_object(p) && !js.is_null(p) { ret (js.undefv(), js.throw_type(it, "Object prototype may only be an Object or null")) }
    if !js.is_object(tgt) { ret (tgt, ok) }
    let e = set_prototype(it, js.as_object(tgt), p)
    if e != ok { ret (js.undefv(), e) }
    ret (tgt, ok)
}

fn object_get_own_property_descriptor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (p, found) = js.get_own(it, o, k)
    if !found { ret (js.undefv(), ok) }
    ret (js.from_descriptor(it, js.prop_to_desc(p)), ok)
}

fn object_get_own_property_descriptors(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let out = js.new_plain(it)
    let (keys, ke) = js.own_keys(it, o)
    if ke != ok { ret (js.undefv(), ke) }
    var i = 0usize
    while i < keys.len {
        let (p, found) = js.get_own(it, o, keys[i])
        if found {
            let (cr, ce) = js.create_data(it, out, keys[i], js.from_descriptor(it, js.prop_to_desc(p)))
            if ce != ok { ret (js.undefv(), ce) }
        }
        i += 1usize
    }
    ret (js.obj_value(out), ok)
}

fn keys_array(it: *js.Interp, o: *js.Obj, mode: u8, want_symbols: bool) -> (js.Value, err) {
    // mode 0 keys, 1 values, 2 entries; `want_symbols` for getOwnPropertySymbols; mode 3 names (all strings).
    let (keys, ke) = js.own_keys(it, o)
    if ke != ok { ret (js.undefv(), ke) }
    let out = js.new_array(it)
    var i = 0usize
    while i < keys.len {
        let k = keys[i]
        i += 1usize
        if want_symbols != js.is_symbol_key(k) { continue }
        if mode != 3u8 {
            let (p, found) = js.get_own(it, o, k)
            if !found || (p.flags & js.P_ENUMERABLE) == 0u8 { continue }
        }
        if mode == 0u8 || mode == 3u8 {
            try js.array_push(it, out, js.key_to_value(k))
            continue
        }
        let (v, ve) = js.get_prop(it, o, k, js.obj_value(o))
        if ve != ok { ret (js.undefv(), ve) }
        if mode == 1u8 {
            try js.array_push(it, out, v)
        } else {
            let pair = js.array_from(it, js.two_args(it, js.key_to_value(k), v))
            try js.array_push(it, out, js.obj_value(pair))
        }
    }
    ret (js.obj_value(out), ok)
}

fn object_keys(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (r, re) = keys_array(it, o, 0u8, false)
    ret (r, re)
}

fn object_values(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (r, re) = keys_array(it, o, 1u8, false)
    ret (r, re)
}

fn object_entries(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (r, re) = keys_array(it, o, 2u8, false)
    ret (r, re)
}

fn object_get_own_property_names(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (r, re) = keys_array(it, o, 3u8, false)
    ret (r, re)
}

fn object_get_own_property_symbols(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (r, re) = keys_array(it, o, 3u8, true)
    ret (r, re)
}

fn object_assign(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (to, te) = js.to_object(it, arg(args, 0usize))
    if te != ok { ret (js.undefv(), te) }
    var i = 1usize
    while i < args.len {
        if !js.is_nullish(args[i]) {
            let (src, se) = js.to_object(it, args[i])
            if se != ok { ret (js.undefv(), se) }
            let (keys, ke) = js.own_keys(it, src)
            if ke != ok { ret (js.undefv(), ke) }
            var k = 0usize
            while k < keys.len {
                let (p, found) = js.get_own(it, src, keys[k])
                if found && (p.flags & js.P_ENUMERABLE) != 0u8 {
                    let (v, ve) = js.get_prop(it, src, keys[k], args[i])
                    if ve != ok { ret (js.undefv(), ve) }
                    let pe = js.put(it, js.obj_value(to), keys[k], v, true)
                    if pe != ok { ret (js.undefv(), pe) }
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    ret (js.obj_value(to), ok)
}

fn object_is(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.bool_value(js.same_value(arg(args, 0usize), arg(args, 1usize))), ok)
}

// SetIntegrityLevel through the object's own internal methods (proxies and typed arrays take this path).
fn set_integrity_generic(it: *js.Interp, o: *js.Obj, frozen: bool) -> (bool, err) {
    let (done, pe) = js.prevent_extensions(it, o)
    if pe != ok { ret (false, pe) }
    if !done { ret (false, ok) }
    let (keys, ke) = js.own_keys(it, o)
    if ke != ok { ret (false, ke) }
    var i = 0usize
    while i < keys.len {
        var d = js.empty_desc()
        d.has_configurable = true
        d.configurable = false
        if frozen {
            let (cur, found, ge) = js.get_own_e(it, o, keys[i])
            if ge != ok { ret (false, ge) }
            if !found {
                i += 1usize
                continue
            }
            if (cur.flags & js.P_ACCESSOR) == 0u8 {
                d.has_writable = true
                d.writable = false
            }
        }
        let (r, de) = js.define_own(it, o, keys[i], d)
        if de != ok { ret (false, de) }
        if !r { ret (false, js.throw_type(it, "Cannot redefine property")) }
        i += 1usize
    }
    ret (true, ok)
}

fn set_integrity(it: *js.Interp, v: js.Value, frozen: bool) -> (js.Value, err) {
    if !js.is_object(v) { ret (v, ok) }
    let o = js.as_object(v)
    if o.class == js.C_PROXY || o.class == js.C_TYPEDARRAY || o.class == js.C_NAMESPACE {
        let (done, e) = set_integrity_generic(it, o, frozen)
        if e != ok { ret (js.undefv(), e) }
        if !done { ret (js.undefv(), js.throw_type(it, "Cannot freeze or seal this object")) }
        ret (v, ok)
    }
    if frozen {
        js.freeze_object(it, o)
        ret (v, ok)
    }
    if o.class == js.C_ARRAY { let m = js.materialize_elements(it, o) }
    var i = 0usize
    while i < o.props.len {
        o.props.items[i].flags = o.props.items[i].flags & (255u8 - js.P_CONFIGURABLE)
        i += 1usize
    }
    o.extensible = false
    ret (v, ok)
}

fn object_freeze(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = set_integrity(it, arg(args, 0usize), true)
    ret (r, e)
}

fn object_seal(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = set_integrity(it, arg(args, 0usize), false)
    ret (r, e)
}

fn object_prevent_extensions(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if js.is_object(v) {
        let (done, pe) = js.prevent_extensions(it, js.as_object(v))
        if pe != ok { ret (js.undefv(), pe) }
        if !done { ret (js.undefv(), js.throw_type(it, "Cannot prevent extensions")) }
    }
    ret (v, ok)
}

fn object_is_extensible(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_object(v) { ret (js.bool_value(false), ok) }
    let (ext, xe) = js.is_extensible(it, js.as_object(v))
    if xe != ok { ret (js.undefv(), xe) }
    ret (js.bool_value(ext), ok)
}

fn object_is_frozen_or_sealed(it: *js.Interp, v: js.Value, frozen: bool) -> (bool, err) {
    if !js.is_object(v) { ret (true, ok) }
    let o = js.as_object(v)
    let (ext, xe) = js.is_extensible(it, o)
    if xe != ok { ret (false, xe) }
    if ext { ret (false, ok) }
    let (keys, ke) = js.own_keys(it, o)
    if ke != ok { ret (false, ke) }
    var i = 0usize
    while i < keys.len {
        let (p, found, ge) = js.get_own_e(it, o, keys[i])
        if ge != ok { ret (false, ge) }
        if found {
            if (p.flags & js.P_CONFIGURABLE) != 0u8 { ret (false, ok) }
            if frozen && (p.flags & js.P_ACCESSOR) == 0u8 && (p.flags & js.P_WRITABLE) != 0u8 { ret (false, ok) }
        }
        i += 1usize
    }
    ret (true, ok)
}

fn object_is_frozen(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = object_is_frozen_or_sealed(it, arg(args, 0usize), true)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(r), ok)
}
fn object_is_sealed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = object_is_frozen_or_sealed(it, arg(args, 0usize), false)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(r), ok)
}

fn object_from_entries(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let src = arg(args, 0usize)
    if js.is_nullish(src) { ret (js.undefv(), js.throw_type(it, "Object.fromEntries requires an iterable")) }
    let out = js.new_plain(it)
    let (iter, ie) = js.get_iterator(it, src)
    if ie != ok { ret (js.undefv(), ie) }
    while true {
        let (item, done, se) = js.iterator_step(it, iter)
        if se != ok { ret (js.undefv(), se) }
        if done { break }
        if !js.is_object(item) {
            let te = js.throw_type(it, "Iterator value is not an entry object")
            js.iterator_close_quiet(it, iter)
            ret (js.undefv(), te)
        }
        let (k, ke) = js.get_value(it, item, js.key_of("0"))
        if ke != ok {
            js.iterator_close_quiet(it, iter)
            ret (js.undefv(), ke)
        }
        let (v, ve) = js.get_value(it, item, js.key_of("1"))
        if ve != ok {
            js.iterator_close_quiet(it, iter)
            ret (js.undefv(), ve)
        }
        let (pk, pke) = js.to_property_key(it, k)
        if pke != ok {
            js.iterator_close_quiet(it, iter)
            ret (js.undefv(), pke)
        }
        let (dd, de) = js.define_own(it, out, pk, js.data_desc(v, js.P_DEFAULT))
        if de != ok {
            js.iterator_close_quiet(it, iter)
            ret (js.undefv(), de)
        }
    }
    ret (js.obj_value(out), ok)
}

fn object_has_own(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, arg(args, 0usize))
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    ret (js.bool_value(js.has_own(it, o, k)), ok)
}

fn object_define_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    if !js.is_callable(arg(args, 1usize)) { ret (js.undefv(), js.throw_type(it, "getter is not a function")) }
    let (k, ke) = js.to_property_key(it, arg(args, 0usize))
    if ke != ok { ret (js.undefv(), ke) }
    var d = js.empty_desc()
    d.has_get = true
    d.getter = arg(args, 1usize)
    d.has_enumerable = true
    d.enumerable = true
    d.has_configurable = true
    d.configurable = true
    let (done, de) = js.define_own(it, o, k, d)
    if de != ok { ret (js.undefv(), de) }
    if !done { ret (js.undefv(), js.throw_type(it, "Cannot redefine property")) }
    ret (js.undefv(), ok)
}

fn object_define_setter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    if !js.is_callable(arg(args, 1usize)) { ret (js.undefv(), js.throw_type(it, "setter is not a function")) }
    let (k, ke) = js.to_property_key(it, arg(args, 0usize))
    if ke != ok { ret (js.undefv(), ke) }
    var d = js.empty_desc()
    d.has_set = true
    d.setter = arg(args, 1usize)
    d.has_enumerable = true
    d.enumerable = true
    d.has_configurable = true
    d.configurable = true
    let (done, de) = js.define_own(it, o, k, d)
    if de != ok { ret (js.undefv(), de) }
    if !done { ret (js.undefv(), js.throw_type(it, "Cannot redefine property")) }
    ret (js.undefv(), ok)
}

fn lookup_accessor(it: *js.Interp, this_val: js.Value, key_arg: js.Value, want_getter: bool) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, key_arg)
    if ke != ok { ret (js.undefv(), ke) }
    var cur = o
    var guard = 0u32
    while guard < 100000u32 {
        guard += 1u32
        let (p, found, ge) = js.get_own_e(it, cur, k)
        if ge != ok { ret (js.undefv(), ge) }
        if found {
            if (p.flags & js.P_ACCESSOR) == 0u8 { ret (js.undefv(), ok) }
            if want_getter {
                if p.getter == js.null_obj() { ret (js.undefv(), ok) }
                ret (js.obj_value(p.getter), ok)
            }
            if p.setter == js.null_obj() { ret (js.undefv(), ok) }
            ret (js.obj_value(p.setter), ok)
        }
        let (pv, pe) = js.proto_get(it, cur)
        if pe != ok { ret (js.undefv(), pe) }
        if !js.is_object(pv) { break }
        cur = js.as_object(pv)
    }
    ret (js.undefv(), ok)
}

fn object_lookup_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, re) = lookup_accessor(it, this_val, arg(args, 0usize), true)
    ret (r, re)
}

fn object_lookup_setter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, re) = lookup_accessor(it, this_val, arg(args, 0usize), false)
    ret (r, re)
}

fn object_to_locale_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (f, fe) = js.get_value(it, this_val, js.key_of("toString"))
    if fe != ok { ret (js.undefv(), fe) }
    let (r, re) = js.call_function(it, f, this_val, js.zero_args())
    ret (r, re)
}

fn install_object(it: *js.Interp) {
    let proto = it.protos.object
    let ctor = make_ctor(it, "Object", 1u32, object_ctor, proto)
    js.add_method(it, proto, "hasOwnProperty", 1u32, object_proto_has_own)
    js.add_method(it, proto, "toString", 0u32, object_proto_to_string)
    js.add_method(it, proto, "toLocaleString", 0u32, object_to_locale_string)
    js.add_method(it, proto, "valueOf", 0u32, object_proto_value_of)
    js.add_method(it, proto, "isPrototypeOf", 1u32, object_proto_is_prototype_of)
    js.add_method(it, proto, "propertyIsEnumerable", 1u32, object_proto_property_is_enumerable)
    js.add_method(it, proto, "__defineGetter__", 2u32, object_define_getter)
    js.add_method(it, proto, "__defineSetter__", 2u32, object_define_setter)
    js.add_method(it, proto, "__lookupGetter__", 1u32, object_lookup_getter)
    js.add_method(it, proto, "__lookupSetter__", 1u32, object_lookup_setter)
    let getter = js.make_native(it, "get __proto__", 0u32, object_get_proto)
    let setter = js.make_native(it, "set __proto__", 1u32, object_set_proto)
    let de = js.define_accessor_raw(it, proto, js.key_of("__proto__"), getter, setter, js.P_CONFIGURABLE)
    js.add_method(it, it.last, "defineProperty", 3u32, object_define_property)
    js.add_method(it, it.last, "defineProperties", 2u32, object_define_properties)
    js.add_method(it, it.last, "create", 2u32, object_create)
    js.add_method(it, it.last, "getPrototypeOf", 1u32, object_get_prototype_of)
    js.add_method(it, it.last, "setPrototypeOf", 2u32, object_set_prototype_of)
    js.add_method(it, it.last, "getOwnPropertyDescriptor", 2u32, object_get_own_property_descriptor)
    js.add_method(it, it.last, "getOwnPropertyDescriptors", 1u32, object_get_own_property_descriptors)
    js.add_method(it, it.last, "getOwnPropertyNames", 1u32, object_get_own_property_names)
    js.add_method(it, it.last, "getOwnPropertySymbols", 1u32, object_get_own_property_symbols)
    js.add_method(it, it.last, "keys", 1u32, object_keys)
    js.add_method(it, it.last, "values", 1u32, object_values)
    js.add_method(it, it.last, "entries", 1u32, object_entries)
    js.add_method(it, it.last, "assign", 2u32, object_assign)
    js.add_method(it, it.last, "is", 2u32, object_is)
    js.add_method(it, it.last, "freeze", 1u32, object_freeze)
    js.add_method(it, it.last, "seal", 1u32, object_seal)
    js.add_method(it, it.last, "preventExtensions", 1u32, object_prevent_extensions)
    js.add_method(it, it.last, "isExtensible", 1u32, object_is_extensible)
    js.add_method(it, it.last, "isFrozen", 1u32, object_is_frozen)
    js.add_method(it, it.last, "isSealed", 1u32, object_is_sealed)
    js.add_method(it, it.last, "fromEntries", 1u32, object_from_entries)
    js.add_method(it, it.last, "hasOwn", 2u32, object_has_own)
}

// --- Function

fn function_proto_call(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_callable(this_val) { ret (js.undefv(), js.throw_type(it, "Function.prototype.call called on non-function")) }
    var rest: []const js.Value = js.zero_args()
    if args.len > 1usize { rest = args[1usize..] }
    let (r, re) = js.call_function(it, this_val, arg(args, 0usize), rest)
    ret (r, re)
}

fn array_like_to_list(it: *js.Interp, v: js.Value) -> ([]const js.Value, err) {
    if js.is_nullish(v) { ret (js.zero_args(), ok) }
    if !js.is_object(v) { ret (js.zero_args(), js.throw_type(it, "CreateListFromArrayLike called on non-object")) }
    let o = js.as_object(v)
    let (len, le) = js.length_of(it, o)
    if le != ok { ret (js.zero_args(), le) }
    let (l, lie) = list.init[js.Value](it.a, usize(len) + 1usize)
    var out = l
    if lie != ok { ret (js.zero_args(), lie) }
    var i = 0usize
    while f64(i) < len {
        let (e, ee) = js.get_index(it, o, f64(i))
        if ee != ok { ret (js.zero_args(), ee) }
        try list.push[js.Value](&out, e)
        i += 1usize
    }
    ret (list.slice_const[js.Value](&out), ok)
}

fn function_proto_apply(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_callable(this_val) { ret (js.undefv(), js.throw_type(it, "Function.prototype.apply called on non-function")) }
    let (list_args, le) = array_like_to_list(it, arg(args, 1usize))
    if le != ok { ret (js.undefv(), le) }
    let (r, re) = js.call_function(it, this_val, arg(args, 0usize), list_args)
    ret (r, re)
}

fn function_proto_bind(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_callable(this_val) { ret (js.undefv(), js.throw_type(it, "Bind must be called on a function")) }
    let tgt = js.as_object(this_val)
    let b = js.new_obj(it, js.C_BOUND, js.null_obj())
    if tgt.has_proto {
        b.proto = tgt.proto
        b.has_proto = true
    }
    b.bound_target = tgt
    b.bound_this = arg(args, 0usize)
    var rest: []const js.Value = js.zero_args()
    if args.len > 1usize { rest = args[1usize..] }
    let (cell, ce) = mem.alloc[js.Value](it.a, rest.len + 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var i = 0usize
    while i < rest.len {
        cell[i] = rest[i]
        i += 1usize
    }
    b.bound_args = cell[0usize..rest.len]
    b.ctor_kind = tgt.ctor_kind
    // length and name.
    var len = 0.0f64
    let (hasl, hle) = js.get_own(it, tgt, js.key_of("length"))
    if hle {
        let (lv, lve) = js.get_prop(it, tgt, js.key_of("length"), this_val)
        if lve != ok { ret (js.undefv(), lve) }
        if js.is_number(lv) {
            let n = js.num_of(lv)
            if js.is_infinite(n) {
                if n > 0.0f64 { len = n }
            } else {
                len = js.to_integer(n) - f64(rest.len)
                if len < 0.0f64 { len = 0.0f64 }
            }
        }
    }
    let (nv, nve) = js.get_prop(it, tgt, js.key_of("name"), this_val)
    if nve != ok { ret (js.undefv(), nve) }
    var name = ""
    if js.is_string(nv) { name = js.value_str(nv) }
    let e1 = js.define_data(it, b, js.key_of("length"), js.num_value(len), js.P_CONFIGURABLE)
    let e2 = js.define_data(it, b, js.key_of("name"), js.str_value(js.str_concat(it, "bound ", name)), js.P_CONFIGURABLE)
    ret (js.obj_value(b), ok)
}

fn function_proto_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_callable(this_val) { ret (js.undefv(), js.throw_type(it, "Function.prototype.toString requires that 'this' be a Function")) }
    let fo = js.as_object(this_val)
    if fo.class == js.C_FUNCTION && fo.text.len > 0usize { ret (js.str_value(fo.text), ok) }
    if fo.class == js.C_FUNCTION && !fo.has_native && fo.node != ast.NONE {
        let src = fo.prog.nodes[usize(fo.node)].text2
        if src.len > 0usize { ret (js.str_value(src), ok) }
    }
    var name = ""
    let (nv, ne) = js.get_prop(it, fo, js.key_of("name"), this_val)
    if ne == ok && js.is_string(nv) { name = js.value_str(nv) }
    ret (js.str_value(js.str_concat3(it, "function ", name, "() { [native code] }")), ok)
}

fn function_proto_has_instance(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, re) = js.ordinary_has_instance(it, this_val, arg(args, 0usize))
    ret (js.bool_value(r), re)
}

fn function_proto_noop(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (js.undefv(), ok) }

// CreateDynamicFunction: `kind` 0 function, 1 generator, 2 async function, 3 async generator.
fn dynamic_function(it: *js.Interp, args: []const js.Value, kind: u8) -> (js.Value, err) {
    // new Function(p1, p2, ..., body)
    var params = ""
    var body = ""
    if args.len > 0usize {
        var i = 0usize
        while i + 1usize < args.len {
            let (s, se) = js.to_string(it, args[i])
            if se != ok { ret (js.undefv(), se) }
            if i > 0usize { params = js.str_concat(it, params, ",") }
            params = js.str_concat(it, params, s)
            i += 1usize
        }
        let (b, be) = js.to_string(it, args[args.len - 1usize])
        if be != ok { ret (js.undefv(), be) }
        body = b
    }
    var prefix = "(function anonymous("
    var fallback = it.protos.function
    if kind == 1u8 {
        prefix = "(function* anonymous("
        fallback = it.protos.gen_function
    } else if kind == 2u8 {
        prefix = "(async function anonymous("
        fallback = it.protos.async_function
    } else if kind == 3u8 {
        prefix = "(async function* anonymous("
        fallback = it.protos.async_gen_function
    }
    let src = js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, prefix, params), "\n) {\n"), body), "\n})")
    // Taking the prototype from new.target happens before the code is compiled.
    var proto = fallback
    var custom = false
    if it.has_new_target {
        let nto = js.as_object(it.new_target)
        let (pv, pe) = js.proto_value_of(it, nto, fallback)
        if pe != ok { ret (js.undefv(), pe) }
        proto = pv
        custom = true
    }
    let (v, e) = js.eval_source(it, src)
    if e != ok { ret (js.undefv(), e) }
    if custom && js.is_object(v) {
        let fo = js.as_object(v)
        fo.proto = proto
        fo.has_proto = true
    }
    ret (v, ok)
}

fn function_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (v, e) = dynamic_function(it, args, 0u8)
    ret (v, e)
}

fn generator_function_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (v, e) = dynamic_function(it, args, 1u8)
    ret (v, e)
}

fn async_function_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (v, e) = dynamic_function(it, args, 2u8)
    ret (v, e)
}

fn async_generator_function_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (v, e) = dynamic_function(it, args, 3u8)
    ret (v, e)
}

// %GeneratorFunction%, %AsyncFunction% and %AsyncGeneratorFunction%: not globals, reached through the prototypes' `constructor`.
fn install_function_kinds(it: *js.Interp) {
    var kind = 1u8
    while kind <= 3u8 {
        var name = "GeneratorFunction"
        var native: js.NativeFn = generator_function_ctor
        var proto = it.protos.gen_function
        if kind == 2u8 {
            name = "AsyncFunction"
            native = async_function_ctor
            proto = it.protos.async_function
        } else if kind == 3u8 {
            name = "AsyncGeneratorFunction"
            native = async_generator_function_ctor
            proto = it.protos.async_gen_function
        }
        let c = js.make_native(it, name, 1u32, native)
        c.ctor_kind = js.K_BASE
        // The constructors themselves inherit from %Function%.
        c.proto = it.function_ctor
        c.has_proto = true
        let e1 = js.define_data(it, c, js.key_of("prototype"), js.obj_value(proto), 0u8)
        let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(c), js.P_CONFIGURABLE)
        kind += 1u8
    }
}

fn install_function(it: *js.Interp) {
    let proto = it.protos.function
    let ctor = make_ctor(it, "Function", 1u32, function_ctor, proto)
    it.function_ctor = ctor
    js.add_method(it, proto, "call", 1u32, function_proto_call)
    js.add_method(it, proto, "apply", 2u32, function_proto_apply)
    js.add_method(it, proto, "bind", 1u32, function_proto_bind)
    js.add_method(it, proto, "toString", 0u32, function_proto_to_string)
    // The restricted `caller` and `arguments` accessors: both throw through %ThrowTypeError%.
    let th = js.thrower_fn(it)
    let e2 = js.define_accessor_raw(it, proto, js.key_of("caller"), th, th, js.P_CONFIGURABLE)
    let e3 = js.define_accessor_raw(it, proto, js.key_of("arguments"), th, th, js.P_CONFIGURABLE)
}

// Function.prototype[Symbol.hasInstance]: needs the well-known symbols, so it is installed after them.
fn install_function_symbols(it: *js.Interp) {
    let hi = js.make_native(it, "[Symbol.hasInstance]", 1u32, function_proto_has_instance)
    let e = js.define_data(it, it.protos.function, js.key_of_symbol(it.sym_has_instance), js.obj_value(hi), 0u8)
}

// --- Error types

fn error_ctor_common(it: *js.Interp, proto_default: *js.Obj, args: []const js.Value) -> (js.Value, err) {
    var proto = proto_default
    if it.has_new_target {
        let nto = js.as_object(it.new_target)
        let (p, pe) = js.proto_value_of(it, nto, proto_default)
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
    let opts = arg(args, 1usize)
    if js.is_object(opts) && js.has_property(it, js.as_object(opts), js.key_of("cause")) {
        let (cv, ce) = js.get_prop(it, js.as_object(opts), js.key_of("cause"), opts)
        if ce != ok { ret (js.undefv(), ce) }
        let e2 = js.define_data(it, o, js.key_of("cause"), cv, js.P_HIDDEN)
    }
    ret (js.obj_value(o), ok)
}

fn error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.error_proto, args)
    ret (r, e) }
fn type_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.type_error, args)
    ret (r, e) }
fn range_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.range_error, args)
    ret (r, e) }
fn syntax_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.syntax_error, args)
    ret (r, e) }
fn reference_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.reference_error, args)
    ret (r, e) }
fn eval_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.eval_error, args)
    ret (r, e) }
fn uri_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = error_ctor_common(it, it.protos.uri_error, args)
    ret (r, e) }

fn error_proto_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "Error.prototype.toString called on non-object")) }
    let o = js.as_object(this_val)
    let (nv, ne) = js.get_prop(it, o, js.key_of("name"), this_val)
    if ne != ok { ret (js.undefv(), ne) }
    var name = "Error"
    if !js.is_undefined(nv) {
        let (s, se) = js.to_string(it, nv)
        if se != ok { ret (js.undefv(), se) }
        name = s
    }
    let (mv, me) = js.get_prop(it, o, js.key_of("message"), this_val)
    if me != ok { ret (js.undefv(), me) }
    var msg = ""
    if !js.is_undefined(mv) {
        let (s2, se2) = js.to_string(it, mv)
        if se2 != ok { ret (js.undefv(), se2) }
        msg = s2
    }
    if name.len == 0usize { ret (js.str_value(msg), ok) }
    if msg.len == 0usize { ret (js.str_value(name), ok) }
    ret (js.str_value(js.str_concat3(it, name, ": ", msg)), ok)
}

fn install_error_type(it: *js.Interp, name: str, proto: *js.Obj, native: js.NativeFn, parent_ctor: *js.Obj, has_parent: bool) -> *js.Obj {
    let ctor = make_ctor(it, name, 1u32, native, proto)
    let e = js.define_data(it, proto, js.key_of("name"), js.str_value(name), js.P_HIDDEN)
    let e2 = js.define_data(it, proto, js.key_of("message"), js.str_value(""), js.P_HIDDEN)
    if has_parent {
        ctor.proto = parent_ctor
        ctor.has_proto = true
    }
    ret ctor
}

// Error.isError(arg): whether arg has an [[ErrorData]] slot.
fn error_is_error(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_object(v) { ret (js.bool_value(false), ok) }
    ret (js.bool_value(js.as_object(v).class == js.C_ERROR), ok)
}

fn install_errors(it: *js.Interp) {
    let base = install_error_type(it, "Error", it.protos.error_proto, error_ctor, js.null_obj(), false)
    js.add_method(it, base, "isError", 1u32, error_is_error)
    js.add_method(it, it.protos.error_proto, "toString", 0u32, error_proto_to_string)
    let e1 = install_error_type(it, "TypeError", it.protos.type_error, type_error_ctor, base, true)
    let e2 = install_error_type(it, "RangeError", it.protos.range_error, range_error_ctor, base, true)
    let e3 = install_error_type(it, "SyntaxError", it.protos.syntax_error, syntax_error_ctor, base, true)
    let e4 = install_error_type(it, "ReferenceError", it.protos.reference_error, reference_error_ctor, base, true)
    let e5 = install_error_type(it, "EvalError", it.protos.eval_error, eval_error_ctor, base, true)
    let e6 = install_error_type(it, "URIError", it.protos.uri_error, uri_error_ctor, base, true)
}

// --- Symbol

fn symbol_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if it.has_new_target { ret (js.undefv(), js.throw_type(it, "Symbol is not a constructor")) }
    let d = arg(args, 0usize)
    if js.is_undefined(d) { ret (js.Value { Sym: js.new_symbol(it, "", false) }, ok) }
    let (s, se) = js.to_string(it, d)
    if se != ok { ret (js.undefv(), se) }
    ret (js.Value { Sym: js.new_symbol(it, s, true) }, ok)
}

fn this_symbol(it: *js.Interp, v: js.Value) -> (*js.Sym, err) {
    switch v {
    case .Sym as s:
        ret (s, ok)
    case .Obj as o:
        if o.class == js.C_SYMBOL {
            switch o.prim {
            case .Sym as s2:
                ret (s2, ok)
            default:
                ret (js.null_sym(), js.throw_type(it, "not a symbol"))
            }
        }
        ret (js.null_sym(), js.throw_type(it, "not a symbol"))
    default:
        ret (js.null_sym(), js.throw_type(it, "not a symbol"))
    }
    ret (js.null_sym(), ok)
}

fn symbol_proto_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, e) = this_symbol(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.str_value(js.str_concat3(it, "Symbol(", s.description, ")")), ok)
}

fn symbol_proto_value_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, e) = this_symbol(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.Value { Sym: s }, ok)
}

fn symbol_description(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, e) = this_symbol(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if !s.has_description { ret (js.undefv(), ok) }
    ret (js.str_value(s.description), ok)
}

fn symbol_for(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (k, ke) = js.to_string(it, arg(args, 0usize))
    if ke != ok { ret (js.undefv(), ke) }
    var i = 0usize
    while i < it.registry.len {
        if str.eq(it.registry.items[i].description, k) { ret (js.Value { Sym: it.registry.items[i] }, ok) }
        i += 1usize
    }
    let s = js.new_symbol(it, k, true)
    s.registered = true
    let pe = list.push[*js.Sym](&it.registry, s)
    ret (js.Value { Sym: s }, ok)
}

fn symbol_key_for(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    switch arg(args, 0usize) {
    case .Sym as s:
        if s.registered { ret (js.str_value(s.description), ok) }
        ret (js.undefv(), ok)
    default:
        ret (js.undefv(), js.throw_type(it, "not a symbol"))
    }
    ret (js.undefv(), ok)
}

fn symbol_to_primitive(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, e) = this_symbol(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.Value { Sym: s }, ok)
}

// A realm made for a frame shares the well-known symbols of the realm that made it, so arrays and iterators cross between them.
fn donor_symbol(d: *js.Interp, name: str) -> *js.Sym {
    if str.eq(name, "iterator") { ret d.sym_iterator }
    if str.eq(name, "asyncIterator") { ret d.sym_async_iterator }
    if str.eq(name, "hasInstance") { ret d.sym_has_instance }
    if str.eq(name, "toPrimitive") { ret d.sym_to_primitive }
    if str.eq(name, "toStringTag") { ret d.sym_to_string_tag }
    if str.eq(name, "species") { ret d.sym_species }
    if str.eq(name, "isConcatSpreadable") { ret d.sym_is_concat_spreadable }
    if str.eq(name, "unscopables") { ret d.sym_unscopables }
    if str.eq(name, "dispose") { ret d.sym_dispose }
    if str.eq(name, "asyncDispose") { ret d.sym_async_dispose }
    if str.eq(name, "match") { ret d.sym_match }
    if str.eq(name, "matchAll") { ret d.sym_match_all }
    if str.eq(name, "replace") { ret d.sym_replace }
    if str.eq(name, "search") { ret d.sym_search }
    ret d.sym_split
}

fn well_known(it: *js.Interp, ctor: *js.Obj, name: str) -> *js.Sym {
    var s: *js.Sym = zero
    if it.donor != js.null_interp() { s = donor_symbol(it.donor, name) } else { s = js.new_symbol(it, js.str_concat(it, "Symbol.", name), true) }
    let e = js.define_data(it, ctor, js.key_of(name), js.Value { Sym: s }, 0u8)
    ret s
}

fn install_symbol(it: *js.Interp) {
    let proto = it.protos.symbol
    let ctor = make_ctor(it, "Symbol", 0u32, symbol_ctor, proto)
    it.last.ctor_kind = js.K_BASE
    js.add_method(it, proto, "toString", 0u32, symbol_proto_to_string)
    js.add_method(it, proto, "valueOf", 0u32, symbol_proto_value_of)
    js.add_getter(it, proto, "description", symbol_description)
    js.add_method(it, it.last, "for", 1u32, symbol_for)
    js.add_method(it, it.last, "keyFor", 1u32, symbol_key_for)
    it.sym_iterator = well_known(it, it.last, "iterator")
    it.sym_async_iterator = well_known(it, it.last, "asyncIterator")
    it.sym_has_instance = well_known(it, it.last, "hasInstance")
    it.sym_to_primitive = well_known(it, it.last, "toPrimitive")
    it.sym_to_string_tag = well_known(it, it.last, "toStringTag")
    it.sym_species = well_known(it, it.last, "species")
    it.sym_is_concat_spreadable = well_known(it, it.last, "isConcatSpreadable")
    it.sym_unscopables = well_known(it, it.last, "unscopables")
    it.sym_dispose = well_known(it, it.last, "dispose")
    it.sym_async_dispose = well_known(it, it.last, "asyncDispose")
    it.sym_match = well_known(it, it.last, "match")
    it.sym_match_all = well_known(it, it.last, "matchAll")
    it.sym_replace = well_known(it, it.last, "replace")
    it.sym_search = well_known(it, it.last, "search")
    it.sym_split = well_known(it, it.last, "split")
    let tp = js.make_native(it, "[Symbol.toPrimitive]", 1u32, symbol_to_primitive)
    let e1 = js.define_data(it, proto, js.key_of_symbol(it.sym_to_primitive), js.obj_value(tp), js.P_CONFIGURABLE)
    let e2 = js.define_data(it, proto, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Symbol"), js.P_CONFIGURABLE)
}

// --- print (the harness's output hook)

// __mem(): bytes of the realm's arena in use, for measuring what an operation allocates.
fn global_mem(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.num_value(f64(mem.mark(it.a))), ok)
}

fn global_print(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var line = ""
    var i = 0usize
    while i < args.len {
        let (s, se) = js.to_string(it, args[i])
        if se != ok { ret (js.undefv(), se) }
        if i > 0usize { line = js.str_concat(it, line, " ") }
        line = js.str_concat(it, line, s)
        i += 1usize
    }
    it.last_print = line
    if !it.quiet {
        let pe = io.printf["{}"](line)
        let nl = io.printf["\n"]()
    }
    ret (js.undefv(), ok)
}

// --- $262 (the test262 host object)

fn host_eval_script(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (src, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (v, e) = js.eval_source(it, src)
    ret (v, e)
}

fn host_gc(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (js.undefv(), ok) }

// $262.createRealm(): a new realm that shares the well-known symbols and the job queue of this one.
fn host_create_realm(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, re) = new_realm_with(it.a, it)
    if re != ok { ret (js.undefv(), js.throw_range(it, "could not create a realm")) }
    let (h, he) = js.get_prop(it, r.global, js.key_of("$262"), js.obj_value(r.global))
    if he != ok { ret (js.undefv(), he) }
    ret (h, ok)
}

// --- $262.agent: script agents on their own threads, each a realm with its own arena (carved from the starting realm's)

type AgentCtx = struct { arena: *mem.Arena, src: str, hub: *js.AgentHub, seen: u64 }

fn agent_object(it: *js.Interp) -> *js.Obj {
    let (h, he) = js.get_prop(it, it.global, js.key_of("$262"), js.obj_value(it.global))
    if he == ok && js.is_object(h) {
        let (ag, ae) = js.get_prop(it, js.as_object(h), js.key_of("agent"), h)
        if ae == ok && js.is_object(ag) { ret js.as_object(ag) }
    }
    ret it.global
}

fn agent_main(c: *AgentCtx) {
    let h = c.hub
    let (it, re) = new_realm(c.arena)
    if re != ok {
        sync.mutex_lock(&h.lock)
        h.starting -= 1u32
        h.live -= 1u32
        sync.condition_broadcast(&h.cond)
        sync.mutex_unlock(&h.lock)
        ret
    }
    it.hub = h
    it.has_hub = true
    it.quiet = true
    it.step_limit = 400000000u64
    let (v, e) = run(it, c.src)
    if e == ok { let je = js.run_jobs(it) }
    let ag = agent_object(it)
    var seen = c.seen
    sync.mutex_lock(&h.lock)
    h.starting -= 1u32
    sync.condition_broadcast(&h.cond)
    while !h.shutdown {
        sync.mutex_unlock(&h.lock)
        let pend = js.pump_waiters(it)
        let jr0 = js.run_jobs(it)
        sync.mutex_lock(&h.lock)
        let (cb, ce) = js.get_prop(it, ag, js.key_of("__cb"), js.obj_value(ag))
        let (lf, le) = js.get_prop(it, ag, js.key_of("__left"), js.obj_value(ag))
        if ce == ok && le == ok && js.to_boolean(lf) { break }
        if ce == ok && js.is_callable(cb) && h.gen != seen {
            seen = h.gen
            let msg = h.msg
            let num = h.msg_num
            if h.pending > 0u32 { h.pending -= 1u32 }
            sync.condition_broadcast(&h.cond)
            sync.mutex_unlock(&h.lock)
            let (r, cre) = js.call_function(it, cb, js.undefv(), js.two_args(it, msg, js.num_value(num)))
            if cre == ok { let je2 = js.run_jobs(it) }
            sync.mutex_lock(&h.lock)
        } else {
            let w = sync.condition_wait_for(&h.cond, &h.lock, time.millis(5i64))
        }
    }
    h.live -= 1u32
    sync.condition_broadcast(&h.cond)
    sync.mutex_unlock(&h.lock)
}

fn agent_start(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (src, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let h = js.hub_of(it)
    let (buf, be) = mem.alloc[u8](it.a, 100663296usize)
    let (ar, are) = mem.alloc[mem.Arena](it.a, 1usize)
    let (cx, ce) = mem.alloc[AgentCtx](it.a, 1usize)
    if be != ok || are != ok || ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory starting an agent")) }
    ar[0usize] = mem.arena_from(buf)
    sync.mutex_lock(&h.lock)
    h.live += 1u32
    h.starting += 1u32
    cx[0usize] = AgentCtx { arena: &ar[0usize], src: src, hub: h, seen: h.gen }
    sync.mutex_unlock(&h.lock)
    let (th, te) = thread.spawn[AgentCtx](agent_main, &cx[0usize], 134217728usize)
    if te != ok {
        sync.mutex_lock(&h.lock)
        h.live -= 1u32
        h.starting -= 1u32
        sync.mutex_unlock(&h.lock)
        ret (js.undefv(), js.throw_range(it, "cannot start an agent thread"))
    }
    let de = thread.detach(th)
    ret (js.undefv(), ok)
}

fn agent_broadcast(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = js.hub_of(it)
    var num = 0.0f64
    if args.len > 1usize {
        let (n, ne) = js.to_number(it, args[1usize])
        if ne != ok { ret (js.undefv(), ne) }
        num = n
    }
    sync.mutex_lock(&h.lock)
    var tries = 0u32
    while h.starting > 0u32 && tries < 400u32 {
        let w = sync.condition_wait_for(&h.cond, &h.lock, time.millis(50i64))
        tries += 1u32
    }
    h.msg = arg(args, 0usize)
    h.msg_num = num
    h.gen += 1u64
    h.pending = h.receivers
    sync.condition_broadcast(&h.cond)
    tries = 0u32
    while h.pending > 0u32 && tries < 400u32 {
        let w2 = sync.condition_wait_for(&h.cond, &h.lock, time.millis(50i64))
        tries += 1u32
    }
    sync.mutex_unlock(&h.lock)
    ret (js.undefv(), ok)
}

fn agent_get_report(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (h, has) = js.hub_peek(it)
    if !has { ret (js.null_value(), ok) }
    sync.mutex_lock(&h.lock)
    if h.rhead == h.rtail {
        sync.mutex_unlock(&h.lock)
        ret (js.null_value(), ok)
    }
    let r = h.reports[h.rhead % 64usize]
    h.rhead += 1usize
    sync.mutex_unlock(&h.lock)
    ret (js.str_value(r), ok)
}

fn agent_report(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (h, has) = js.hub_peek(it)
    if !has { ret (js.undefv(), ok) }
    sync.mutex_lock(&h.lock)
    if h.rtail - h.rhead < 64usize {
        h.reports[h.rtail % 64usize] = s
        h.rtail += 1usize
    }
    sync.mutex_unlock(&h.lock)
    ret (js.undefv(), ok)
}

fn agent_receive_broadcast(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (h, has) = js.hub_peek(it)
    if !has || !js.is_object(this_val) { ret (js.undefv(), ok) }
    let ag = js.as_object(this_val)
    let (old, oe) = js.get_prop(it, ag, js.key_of("__cb"), this_val)
    let e1 = js.define_data(it, ag, js.key_of("__cb"), arg(args, 0usize), js.P_HIDDEN)
    if !(oe == ok && js.is_callable(old)) {
        sync.mutex_lock(&h.lock)
        h.receivers += 1u32
        sync.mutex_unlock(&h.lock)
    }
    ret (js.undefv(), ok)
}

fn agent_leaving(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (h, has) = js.hub_peek(it)
    if !has || !js.is_object(this_val) { ret (js.undefv(), ok) }
    let ag = js.as_object(this_val)
    let (lf, le) = js.get_prop(it, ag, js.key_of("__left"), this_val)
    if le == ok && js.to_boolean(lf) { ret (js.undefv(), ok) }
    let e1 = js.define_data(it, ag, js.key_of("__left"), js.bool_value(true), js.P_HIDDEN)
    let (cb, ce) = js.get_prop(it, ag, js.key_of("__cb"), this_val)
    if ce == ok && js.is_callable(cb) {
        sync.mutex_lock(&h.lock)
        if h.receivers > 0u32 { h.receivers -= 1u32 }
        sync.mutex_unlock(&h.lock)
    }
    ret (js.undefv(), ok)
}

fn agent_sleep(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let (t0, t0e) = time.monotonic()
    var m = sync.mutex()
    var c = sync.condition()
    sync.mutex_lock(&m)
    while true {
        let (t1, t1e) = time.monotonic()
        let elapsed = f64(t1.nanos - t0.nanos) / 1000000.0f64
        if elapsed >= n { break }
        var chunk = 20.0f64
        if n - elapsed < chunk { chunk = n - elapsed }
        let w = sync.condition_wait_for(&c, &m, time.nanos(i64(chunk * 1000000.0f64) + 1i64))
    }
    sync.mutex_unlock(&m)
    ret (js.undefv(), ok)
}

fn agent_monotonic_now(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (t, te) = time.monotonic()
    ret (js.num_value(f64(t.nanos) / 1000000.0f64), ok)
}

fn install_agent(it: *js.Interp, host: *js.Obj) {
    let ag = js.new_plain(it)
    let e0 = js.define_data(it, host, js.key_of("agent"), js.obj_value(ag), js.P_HIDDEN)
    js.add_method(it, ag, "start", 1u32, agent_start)
    js.add_method(it, ag, "broadcast", 1u32, agent_broadcast)
    js.add_method(it, ag, "getReport", 0u32, agent_get_report)
    js.add_method(it, ag, "report", 1u32, agent_report)
    js.add_method(it, ag, "receiveBroadcast", 1u32, agent_receive_broadcast)
    js.add_method(it, ag, "leaving", 0u32, agent_leaving)
    js.add_method(it, ag, "sleep", 1u32, agent_sleep)
    js.add_method(it, ag, "monotonicNow", 0u32, agent_monotonic_now)
}

fn install_host(it: *js.Interp) {
    let h = js.new_plain(it)
    let e0 = js.define_data(it, it.global, js.key_of("$262"), js.obj_value(h), js.P_HIDDEN)
    it.last = h
    js.add_method(it, it.last, "evalScript", 1u32, host_eval_script)
    js.add_method(it, it.last, "gc", 0u32, host_gc)
    js.add_method(it, it.last, "createRealm", 0u32, host_create_realm)
    let e1 = js.define_data(it, it.last, js.key_of("global"), js.obj_value(it.global), js.P_HIDDEN)
    install_agent(it, it.last)
}

// --- bootstrap

fn global_this(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (js.obj_value(it.global), ok) }

fn install_globals(it: *js.Interp) {
    let g = it.global
    let e1 = js.define_data(it, g, js.key_of("globalThis"), js.obj_value(g), js.P_HIDDEN)
    let e2 = js.define_data(it, g, js.key_of("NaN"), js.num_value(js.nan()), 0u8)
    let e3 = js.define_data(it, g, js.key_of("Infinity"), js.num_value(js.infinity()), 0u8)
    let e4 = js.define_data(it, g, js.key_of("undefined"), js.undefv(), 0u8)
}

fn global_eval(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let a0 = arg(args, 0usize)
    if !js.is_string(a0) { ret (a0, ok) }
    let (v, e) = js.indirect_eval(it, a0)
    ret (v, e)
}

fn new_realm(a: *mem.Arena) -> (*js.Interp, err) {
    let (it, e) = new_realm_with(a, js.null_interp())
    ret (it, e)
}

fn new_realm_with(a: *mem.Arena, donor: *js.Interp) -> (*js.Interp, err) {
    let (cell, ce) = mem.alloc[js.Interp](a, 1usize)
    if ce != ok { ret (js.null_interp(), ce) }
    var blank_it: js.Interp = zero
    cell[0usize] = blank_it
    let it = &cell[0usize]
    it.a = a
    it.donor = donor
    it.max_depth = 160u32
    // Objects and symbols of every realm sharing one arena get ids from disjoint ranges.
    it.next_object = u64(mem.mark(a)) << 12u64
    it.next_symbol = u32(mem.mark(a) >> 20usize) * 50000u32
    it.thrown = js.undefv()
    it.new_target = js.undefv()
    let (reg, re) = list.init[*js.Sym](a, 8usize)
    it.registry = reg
    let (jl, jle) = list.init[js.Job](a, 16usize)
    it.jobs = jl
    it.hole = js.new_symbol(it, "hole", true)
    it.protos.object = js.new_obj(it, js.C_OBJECT, js.null_obj())
    it.protos.function = js.new_obj(it, js.C_FUNCTION, it.protos.object)
    it.protos.function.native = function_proto_noop
    it.protos.function.has_native = true
    let e0 = js.define_data(it, it.protos.function, js.key_of("length"), js.num_value(0.0f64), js.P_CONFIGURABLE)
    let e00 = js.define_data(it, it.protos.function, js.key_of("name"), js.str_value(""), js.P_CONFIGURABLE)
    it.protos.array = js.new_obj(it, js.C_ARRAY, it.protos.object)
    it.protos.string = js.new_obj(it, js.C_STRING, it.protos.object)
    it.protos.string.prim = js.str_value("")
    it.protos.number = js.new_obj(it, js.C_NUMBER, it.protos.object)
    it.protos.number.prim = js.num_value(0.0f64)
    it.protos.boolean = js.new_obj(it, js.C_BOOLEAN, it.protos.object)
    it.protos.boolean.prim = js.bool_value(false)
    it.protos.symbol = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.error_proto = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.type_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    it.protos.range_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    it.protos.syntax_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    it.protos.reference_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    it.protos.eval_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    it.protos.uri_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    it.protos.iterator = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.array_iterator = js.new_obj(it, js.C_OBJECT, it.protos.iterator)
    it.protos.generator = js.new_obj(it, js.C_OBJECT, it.protos.iterator)
    it.protos.promise = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.regexp = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.date = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.map = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.set = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.bigint = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.arguments = it.protos.object
    it.global = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.global_env = js.new_env(it, js.null_env())
    install_globals(it)
    install_object(it)
    install_function(it)
    install_errors(it)
    install_symbol(it)
    install_function_symbols(it)
    b_array.install_array(it)
    b_string.install_string(it)
    b_number.install_number(it)
    b_bigint.install_bigint(it)
    b_number.install_math(it)
    b_json.install_json(it)
    b_control.install_generators(it)
    install_function_kinds(it)
    b_control.install_promise(it)
    b_control.install_reflect(it)
    b_collections.install_map(it)
    b_collections.install_set(it)
    b_collections.install_weak(it)
    b_date.install_date(it)
    b_regexp.install_regexp(it)
    install_host(it)
    b_typed.install_array_buffer(it)
    b_typed.install_typed_arrays(it)
    b_typed.install_data_view(it)
    b_atomics.install_atomics(it)
    b_misc.install_misc(it)
    b_proxy.install_proxy(it)
    js.add_method(it, it.global, "print", 1u32, global_print)
    js.add_method(it, it.global, "__mem", 0u32, global_mem)
    let ev = js.make_native(it, "eval", 1u32, global_eval)
    it.eval_fn = ev
    let e5 = js.define_data(it, it.global, js.key_of("eval"), js.obj_value(ev), js.P_HIDDEN)
    let (psrc, pse) = prelude.source(a)
    if pse != ok { ret (it, pse) }
    let (pv, pe) = js.eval_source(it, psrc)
    if pe != ok { ret (it, pe) }
    if donor == js.null_interp() {
        let (tsrc, tse) = temporal.source(a)
        if tse != ok { ret (it, tse) }
        let (tv, te) = js.eval_source(it, tsrc)
        if te != ok { ret (it, te) }
    }
    let (isrc, ise) = intl.source(a)
    if ise != ok { ret (it, ise) }
    let (iv, ie) = js.eval_source(it, isrc)
    if ie != ok { ret (it, ie) }
    let (sev, see) = js.get_prop(it, it.global, js.key_of("SuppressedError"), js.obj_value(it.global))
    if see == ok && js.is_object(sev) { it.suppressed_ctor = js.as_object(sev) }
    ret (it, ok)
}

// Parses and runs `source`; a thrown exception is answered as the `Throw` error with `it.thrown` set.
fn run(it: *js.Interp, source: str) -> (js.Value, err) {
    let (v, e) = js.eval_source(it, source)
    ret (v, e)
}
