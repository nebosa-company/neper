// Proxy (browser tracker 5.8): an exotic object whose internal methods consult the traps of a handler object.
//
// A proxy is an object of class C_PROXY: `aux` is the target (null once revoked), `prim` the handler, `num` is 1 when the
// target is callable and `ctor_kind` is K_BASE when it is a constructor. The interpreter's property machinery calls
// `hook` (installed in `it.px_hook`) for every internal method; the invariant checks follow the ECMAScript text.

use e.js.interp as js
use e.mem

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

fn args_of(it: *js.Interp, a: js.Value, b: js.Value, c: js.Value, d: js.Value, n: usize) -> ([]const js.Value, err) {
    let (cell, ce) = mem.alloc[js.Value](it.a, 4usize)
    if ce != ok { ret (js.zero_args(), js.throw_range(it, "out of memory")) }
    cell[0usize] = a
    cell[1usize] = b
    cell[2usize] = c
    cell[3usize] = d
    ret (cell[0usize..n], ok)
}

fn revoked_error(it: *js.Interp, what: str) -> err {
    ret js.throw_type(it, js.str_concat3(it, "Cannot perform '", what, "' on a proxy that has been revoked"))
}

// The target and handler; a revoked proxy throws.
fn parts(it: *js.Interp, p: *js.Obj, what: str) -> (*js.Obj, *js.Obj, err) {
    if p.aux == js.null_obj() { ret (js.null_obj(), js.null_obj(), revoked_error(it, what)) }
    ret (p.aux, js.as_object(p.prim), ok)
}

// The handler's trap `name`: (function, present).
fn trap_of(it: *js.Interp, h: *js.Obj, name: str) -> (js.Value, bool, err) {
    let (t, te) = js.get_prop(it, h, js.key_of(name), js.obj_value(h))
    if te != ok { ret (js.undefv(), false, te) }
    if js.is_nullish(t) { ret (js.undefv(), false, ok) }
    if !js.is_callable(t) { ret (js.undefv(), false, js.throw_type(it, js.str_concat3(it, "proxy trap '", name, "' is not a function"))) }
    ret (t, true, ok)
}

fn is_accessor_prop(p: js.Prop) -> bool { ret (p.flags & js.P_ACCESSOR) != 0u8 }

fn prop_getter(p: js.Prop) -> js.Value {
    if p.getter == js.null_obj() { ret js.undefv() }
    ret js.obj_value(p.getter)
}

fn prop_setter(p: js.Prop) -> js.Value {
    if p.setter == js.null_obj() { ret js.undefv() }
    ret js.obj_value(p.setter)
}

// IsCompatiblePropertyDescriptor(extensible, desc, current).
fn compatible(ext: bool, d: js.Desc, has_cur: bool, cur: js.Prop) -> bool {
    if !has_cur { ret ext }
    let cur_configurable = (cur.flags & js.P_CONFIGURABLE) != 0u8
    let cur_enumerable = (cur.flags & js.P_ENUMERABLE) != 0u8
    if !cur_configurable {
        if d.has_configurable && d.configurable { ret false }
        if d.has_enumerable && d.enumerable != cur_enumerable { ret false }
        let generic = !d.has_get && !d.has_set && !d.has_value && !d.has_writable
        if generic { ret true }
        let d_accessor = d.has_get || d.has_set
        if d_accessor != is_accessor_prop(cur) { ret false }
        if is_accessor_prop(cur) {
            if d.has_get && !js.same_value(d.getter, prop_getter(cur)) { ret false }
            if d.has_set && !js.same_value(d.setter, prop_setter(cur)) { ret false }
        } else if (cur.flags & js.P_WRITABLE) == 0u8 {
            if d.has_writable && d.writable { ret false }
            if d.has_value && !js.same_value(d.value, cur.value) { ret false }
        }
    }
    ret true
}

fn complete(d: js.Desc) -> js.Desc {
    var r = d
    if !r.has_get && !r.has_set {
        if !r.has_value {
            r.has_value = true
            r.value = js.undefv()
        }
        if !r.has_writable {
            r.has_writable = true
            r.writable = false
        }
    } else {
        if !r.has_get {
            r.has_get = true
            r.getter = js.undefv()
        }
        if !r.has_set {
            r.has_set = true
            r.setter = js.undefv()
        }
    }
    if !r.has_enumerable {
        r.has_enumerable = true
        r.enumerable = false
    }
    if !r.has_configurable {
        r.has_configurable = true
        r.configurable = false
    }
    ret r
}

fn op_get(it: *js.Interp, p: *js.Obj, key: js.Key, receiver: js.Value) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "get")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "get")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (v0, e0) = js.get_prop(it, t, key, receiver)
        ret (v0, e0)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.key_to_value(key), receiver, js.undefv(), 3usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (v, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    let (cur, found, ge) = js.get_own_e(it, t, key)
    if ge != ok { ret (js.undefv(), ge) }
    if found && (cur.flags & js.P_CONFIGURABLE) == 0u8 {
        if !is_accessor_prop(cur) && (cur.flags & js.P_WRITABLE) == 0u8 && !js.same_value(v, cur.value) {
            ret (js.undefv(), js.throw_type(it, "proxy get trap returned a different value for a non-writable, non-configurable property"))
        }
        if is_accessor_prop(cur) && cur.getter == js.null_obj() && !js.is_undefined(v) {
            ret (js.undefv(), js.throw_type(it, "proxy get trap must report undefined for an accessor without a getter"))
        }
    }
    ret (v, ok)
}

fn op_set(it: *js.Interp, p: *js.Obj, key: js.Key, val: js.Value, receiver: js.Value) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "set")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "set")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (done, e0) = js.set_prop(it, t, key, val, receiver)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(done), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.key_to_value(key), val, receiver, 4usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.to_boolean(r) { ret (js.bool_value(false), ok) }
    let (cur, found, ge) = js.get_own_e(it, t, key)
    if ge != ok { ret (js.undefv(), ge) }
    if found && (cur.flags & js.P_CONFIGURABLE) == 0u8 {
        if !is_accessor_prop(cur) && (cur.flags & js.P_WRITABLE) == 0u8 && !js.same_value(val, cur.value) {
            ret (js.undefv(), js.throw_type(it, "proxy set trap changed a non-writable, non-configurable property"))
        }
        if is_accessor_prop(cur) && cur.setter == js.null_obj() {
            ret (js.undefv(), js.throw_type(it, "proxy set trap succeeded for an accessor without a setter"))
        }
    }
    ret (js.bool_value(true), ok)
}

fn op_has(it: *js.Interp, p: *js.Obj, key: js.Key) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "has")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "has")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (r0, e0) = js.has_property_e(it, t, key)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(r0), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.key_to_value(key), js.undefv(), js.undefv(), 2usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    let res = js.to_boolean(r)
    if !res {
        let (cur, found, ge) = js.get_own_e(it, t, key)
        if ge != ok { ret (js.undefv(), ge) }
        if found {
            if (cur.flags & js.P_CONFIGURABLE) == 0u8 { ret (js.undefv(), js.throw_type(it, "proxy has trap hid a non-configurable property")) }
            let (ext, xe) = js.is_extensible(it, t)
            if xe != ok { ret (js.undefv(), xe) }
            if !ext { ret (js.undefv(), js.throw_type(it, "proxy has trap hid a property of a non-extensible target")) }
        }
    }
    ret (js.bool_value(res), ok)
}

fn op_delete(it: *js.Interp, p: *js.Obj, key: js.Key) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "deleteProperty")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "deleteProperty")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (r0, e0) = js.delete_prop_e(it, t, key)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(r0), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.key_to_value(key), js.undefv(), js.undefv(), 2usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.to_boolean(r) { ret (js.bool_value(false), ok) }
    let (cur, found, ge) = js.get_own_e(it, t, key)
    if ge != ok { ret (js.undefv(), ge) }
    if found {
        if (cur.flags & js.P_CONFIGURABLE) == 0u8 { ret (js.undefv(), js.throw_type(it, "proxy deleteProperty trap deleted a non-configurable property")) }
        let (ext, xe) = js.is_extensible(it, t)
        if xe != ok { ret (js.undefv(), xe) }
        if !ext { ret (js.undefv(), js.throw_type(it, "proxy deleteProperty trap deleted a property of a non-extensible target")) }
    }
    ret (js.bool_value(true), ok)
}

fn op_get_own(it: *js.Interp, p: *js.Obj, key: js.Key) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "getOwnPropertyDescriptor")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "getOwnPropertyDescriptor")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (cur0, found0, ge0) = js.get_own_e(it, t, key)
        if ge0 != ok { ret (js.undefv(), ge0) }
        if !found0 { ret (js.undefv(), ok) }
        ret (js.from_descriptor(it, js.prop_to_desc(cur0)), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.key_to_value(key), js.undefv(), js.undefv(), 2usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_object(r) && !js.is_undefined(r) { ret (js.undefv(), js.throw_type(it, "proxy getOwnPropertyDescriptor trap must return an object or undefined")) }
    let (cur, found, ge) = js.get_own_e(it, t, key)
    if ge != ok { ret (js.undefv(), ge) }
    let (ext, xe) = js.is_extensible(it, t)
    if xe != ok { ret (js.undefv(), xe) }
    if js.is_undefined(r) {
        if !found { ret (js.undefv(), ok) }
        if (cur.flags & js.P_CONFIGURABLE) == 0u8 { ret (js.undefv(), js.throw_type(it, "proxy getOwnPropertyDescriptor trap hid a non-configurable property")) }
        if !ext { ret (js.undefv(), js.throw_type(it, "proxy getOwnPropertyDescriptor trap hid a property of a non-extensible target")) }
        ret (js.undefv(), ok)
    }
    let (rd0, de) = js.to_descriptor(it, r)
    if de != ok { ret (js.undefv(), de) }
    let rd = complete(rd0)
    if !compatible(ext, rd, found, cur) { ret (js.undefv(), js.throw_type(it, "proxy getOwnPropertyDescriptor trap returned an incompatible descriptor")) }
    if !rd.configurable {
        if !found || (cur.flags & js.P_CONFIGURABLE) != 0u8 { ret (js.undefv(), js.throw_type(it, "proxy getOwnPropertyDescriptor trap reported a configurable property as non-configurable")) }
        if rd.has_writable && !rd.writable && (cur.flags & js.P_WRITABLE) != 0u8 { ret (js.undefv(), js.throw_type(it, "proxy getOwnPropertyDescriptor trap reported a writable property as non-writable")) }
    }
    ret (js.from_descriptor(it, rd), ok)
}

fn op_define(it: *js.Interp, p: *js.Obj, key: js.Key, desc_obj: js.Value) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "defineProperty")
    if pe != ok { ret (js.undefv(), pe) }
    let (d, de) = js.to_descriptor(it, desc_obj)
    if de != ok { ret (js.undefv(), de) }
    let (trap, has, te) = trap_of(it, h, "defineProperty")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (r0, e0) = js.define_own(it, t, key, d)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(r0), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.key_to_value(key), desc_obj, js.undefv(), 3usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.to_boolean(r) { ret (js.bool_value(false), ok) }
    let (cur, found, ge) = js.get_own_e(it, t, key)
    if ge != ok { ret (js.undefv(), ge) }
    let (ext, xe) = js.is_extensible(it, t)
    if xe != ok { ret (js.undefv(), xe) }
    let setting_non_configurable = d.has_configurable && !d.configurable
    if !found {
        if !ext { ret (js.undefv(), js.throw_type(it, "proxy defineProperty trap added a property to a non-extensible target")) }
        if setting_non_configurable { ret (js.undefv(), js.throw_type(it, "proxy defineProperty trap defined a non-configurable property the target lacks")) }
    } else {
        if !compatible(ext, d, true, cur) { ret (js.undefv(), js.throw_type(it, "proxy defineProperty trap defined an incompatible property")) }
        if setting_non_configurable && (cur.flags & js.P_CONFIGURABLE) != 0u8 { ret (js.undefv(), js.throw_type(it, "proxy defineProperty trap made a configurable property non-configurable")) }
        if !is_accessor_prop(cur) && (cur.flags & js.P_CONFIGURABLE) == 0u8 && (cur.flags & js.P_WRITABLE) != 0u8 && d.has_writable && !d.writable {
            ret (js.undefv(), js.throw_type(it, "proxy defineProperty trap made a writable property non-writable"))
        }
    }
    ret (js.bool_value(true), ok)
}

fn op_keys(it: *js.Interp, p: *js.Obj) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "ownKeys")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "ownKeys")
    if te != ok { ret (js.undefv(), te) }
    let out = js.new_array(it)
    if !has {
        let (keys0, ke0) = js.own_keys(it, t)
        if ke0 != ok { ret (js.undefv(), ke0) }
        var i0 = 0usize
        while i0 < keys0.len {
            try js.array_push(it, out, js.key_to_value(keys0[i0]))
            i0 += 1usize
        }
        ret (js.obj_value(out), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.undefv(), js.undefv(), js.undefv(), 1usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_object(r) { ret (js.undefv(), js.throw_type(it, "proxy ownKeys trap must return an array-like object")) }
    let ro = js.as_object(r)
    let (lenv, le) = js.get_prop(it, ro, js.key_of("length"), r)
    if le != ok { ret (js.undefv(), le) }
    let (len_n, ne) = js.to_number(it, lenv)
    if ne != ok { ret (js.undefv(), ne) }
    var n = 0usize
    if len_n > 0.0f64 { n = usize(len_n) }
    var i = 0usize
    while i < n {
        let (ev, ee) = js.get_prop(it, ro, js.key_of(js.index_string(it, i)), r)
        if ee != ok { ret (js.undefv(), ee) }
        if !js.is_string(ev) && !js.is_symbol_value(ev) { ret (js.undefv(), js.throw_type(it, "proxy ownKeys trap result must contain only strings and symbols")) }
        var j = 0usize
        while j < out.elems.len {
            if js.same_value(out.elems.items[j], ev) { ret (js.undefv(), js.throw_type(it, "proxy ownKeys trap result contains duplicate entries")) }
            j += 1usize
        }
        try js.array_push(it, out, ev)
        i += 1usize
    }
    // Invariants: every non-configurable own key of the target is reported, and a non-extensible target reports exactly its keys.
    let (ext, xe) = js.is_extensible(it, t)
    if xe != ok { ret (js.undefv(), xe) }
    let (tkeys, tke) = js.own_keys(it, t)
    if tke != ok { ret (js.undefv(), tke) }
    var reported = 0usize
    var k = 0usize
    while k < tkeys.len {
        let (cur, found, ge) = js.get_own_e(it, t, tkeys[k])
        if ge != ok { ret (js.undefv(), ge) }
        var listed = false
        var m = 0usize
        let kv = js.key_to_value(tkeys[k])
        while m < out.elems.len {
            if js.same_value(out.elems.items[m], kv) { listed = true }
            m += 1usize
        }
        if listed { reported += 1usize }
        if found && !listed && ((cur.flags & js.P_CONFIGURABLE) == 0u8 || !ext) {
            ret (js.undefv(), js.throw_type(it, "proxy ownKeys trap omitted a key it must report"))
        }
        k += 1usize
    }
    if !ext && out.elems.len != reported { ret (js.undefv(), js.throw_type(it, "proxy ownKeys trap added keys to a non-extensible target")) }
    ret (js.obj_value(out), ok)
}

fn op_get_proto(it: *js.Interp, p: *js.Obj) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "getPrototypeOf")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "getPrototypeOf")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (v0, e0) = js.proto_get(it, t)
        ret (v0, e0)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.undefv(), js.undefv(), js.undefv(), 1usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_object(r) && !js.is_null(r) { ret (js.undefv(), js.throw_type(it, "proxy getPrototypeOf trap must return an object or null")) }
    let (ext, xe) = js.is_extensible(it, t)
    if xe != ok { ret (js.undefv(), xe) }
    if !ext {
        let (tp, tpe) = js.proto_get(it, t)
        if tpe != ok { ret (js.undefv(), tpe) }
        if !js.same_value(tp, r) { ret (js.undefv(), js.throw_type(it, "proxy getPrototypeOf trap must report the target's prototype")) }
    }
    ret (r, ok)
}

fn op_set_proto(it: *js.Interp, p: *js.Obj, proto: js.Value) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "setPrototypeOf")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "setPrototypeOf")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (r0, e0) = js.proto_set(it, t, proto)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(r0), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), proto, js.undefv(), js.undefv(), 2usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.to_boolean(r) { ret (js.bool_value(false), ok) }
    let (ext, xe) = js.is_extensible(it, t)
    if xe != ok { ret (js.undefv(), xe) }
    if !ext {
        let (tp, tpe) = js.proto_get(it, t)
        if tpe != ok { ret (js.undefv(), tpe) }
        if !js.same_value(tp, proto) { ret (js.undefv(), js.throw_type(it, "proxy setPrototypeOf trap changed the prototype of a non-extensible target")) }
    }
    ret (js.bool_value(true), ok)
}

fn op_prevent(it: *js.Interp, p: *js.Obj) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "preventExtensions")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "preventExtensions")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (r0, e0) = js.prevent_extensions(it, t)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(r0), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.undefv(), js.undefv(), js.undefv(), 1usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    let res = js.to_boolean(r)
    if res {
        let (ext, xe) = js.is_extensible(it, t)
        if xe != ok { ret (js.undefv(), xe) }
        if ext { ret (js.undefv(), js.throw_type(it, "proxy preventExtensions trap returned true but the target is extensible")) }
    }
    ret (js.bool_value(res), ok)
}

fn op_is_ext(it: *js.Interp, p: *js.Obj) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "isExtensible")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "isExtensible")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (r0, e0) = js.is_extensible(it, t)
        if e0 != ok { ret (js.undefv(), e0) }
        ret (js.bool_value(r0), ok)
    }
    let (args, ae) = args_of(it, js.obj_value(t), js.undefv(), js.undefv(), js.undefv(), 1usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (r, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    let res = js.to_boolean(r)
    let (ext, xe) = js.is_extensible(it, t)
    if xe != ok { ret (js.undefv(), xe) }
    if res != ext { ret (js.undefv(), js.throw_type(it, "proxy isExtensible trap result does not match the target")) }
    ret (js.bool_value(res), ok)
}

// The elements of an array object as an argument list.
fn list_of(it: *js.Interp, arr: js.Value) -> ([]const js.Value, err) {
    let ao = js.as_object(arr)
    ret (ao.elems.items[0usize..ao.elems.len], ok)
}

fn op_call(it: *js.Interp, p: *js.Obj, this_val: js.Value, args_arr: js.Value) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "apply")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "apply")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (args0, le) = list_of(it, args_arr)
        if le != ok { ret (js.undefv(), le) }
        let (v0, e0) = js.call_function(it, js.obj_value(t), this_val, args0)
        ret (v0, e0)
    }
    let (args, ae) = args_of(it, js.obj_value(t), this_val, args_arr, js.undefv(), 3usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (v, e) = js.call_function(it, trap, js.obj_value(h), args)
    ret (v, e)
}

fn op_construct(it: *js.Interp, p: *js.Obj, args_arr: js.Value, new_target: js.Value) -> (js.Value, err) {
    let (t, h, pe) = parts(it, p, "construct")
    if pe != ok { ret (js.undefv(), pe) }
    let (trap, has, te) = trap_of(it, h, "construct")
    if te != ok { ret (js.undefv(), te) }
    if !has {
        let (args0, le) = list_of(it, args_arr)
        if le != ok { ret (js.undefv(), le) }
        let (v0, e0) = js.construct(it, js.obj_value(t), args0, new_target)
        ret (v0, e0)
    }
    let (args, ae) = args_of(it, js.obj_value(t), args_arr, new_target, js.undefv(), 3usize)
    if ae != ok { ret (js.undefv(), ae) }
    let (v, e) = js.call_function(it, trap, js.obj_value(h), args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_object(v) { ret (js.undefv(), js.throw_type(it, "proxy construct trap must return an object")) }
    ret (v, ok)
}

fn hook(it: *js.Interp, op: u8, p: *js.Obj, key: js.Key, a: js.Value, b: js.Value) -> (js.Value, err) {
    if op == js.PX_GET {
        let (v, e) = op_get(it, p, key, a)
        ret (v, e)
    }
    if op == js.PX_SET {
        let (v, e) = op_set(it, p, key, a, b)
        ret (v, e)
    }
    if op == js.PX_HAS {
        let (v, e) = op_has(it, p, key)
        ret (v, e)
    }
    if op == js.PX_DELETE {
        let (v, e) = op_delete(it, p, key)
        ret (v, e)
    }
    if op == js.PX_GETOWN {
        let (v, e) = op_get_own(it, p, key)
        ret (v, e)
    }
    if op == js.PX_DEFINE {
        let (v, e) = op_define(it, p, key, a)
        ret (v, e)
    }
    if op == js.PX_KEYS {
        let (v, e) = op_keys(it, p)
        ret (v, e)
    }
    if op == js.PX_GETPROTO {
        let (v, e) = op_get_proto(it, p)
        ret (v, e)
    }
    if op == js.PX_SETPROTO {
        let (v, e) = op_set_proto(it, p, a)
        ret (v, e)
    }
    if op == js.PX_PREVENT {
        let (v, e) = op_prevent(it, p)
        ret (v, e)
    }
    if op == js.PX_ISEXT {
        let (v, e) = op_is_ext(it, p)
        ret (v, e)
    }
    if op == js.PX_CALL {
        let (v, e) = op_call(it, p, a, b)
        ret (v, e)
    }
    let (cv, ce) = op_construct(it, p, a, b)
    ret (cv, ce)
}

// --- the Proxy constructor

fn create(it: *js.Interp, tgt: js.Value, handler: js.Value) -> (*js.Obj, err) {
    if !js.is_object(tgt) || !js.is_object(handler) { ret (js.null_obj(), js.throw_type(it, "Cannot create proxy with a non-object as target or handler")) }
    let t = js.as_object(tgt)
    let p = js.new_obj(it, js.C_PROXY, js.null_obj())
    p.has_proto = false
    p.aux = t
    p.prim = handler
    if js.is_callable(tgt) { p.num = 1.0f64 }
    if js.is_constructor(tgt) { p.ctor_kind = js.K_BASE }
    ret (p, ok)
}

fn proxy_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Constructor Proxy requires 'new'")) }
    let (p, e) = create(it, arg(args, 0usize), arg(args, 1usize))
    if e != ok { ret (js.undefv(), e) }
    ret (js.obj_value(p), ok)
}

// The function `revoke` hands out: `aux` of the function object is the proxy it revokes.
fn revoke_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let me = it.callee
    if me.aux != js.null_obj() {
        let p = me.aux
        p.aux = js.null_obj()
        p.prim = js.null_value()
        me.aux = js.null_obj()
    }
    ret (js.undefv(), ok)
}

fn proxy_revocable(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (p, e) = create(it, arg(args, 0usize), arg(args, 1usize))
    if e != ok { ret (js.undefv(), e) }
    let rv = js.make_native(it, "", 0u32, revoke_fn)
    rv.aux = p
    let out = js.new_plain(it)
    try js.set_named(it, out, "proxy", js.obj_value(p))
    try js.set_named(it, out, "revoke", js.obj_value(rv))
    ret (js.obj_value(out), ok)
}

fn install_proxy(it: *js.Interp) {
    it.px_hook = hook
    it.px_err = ok
    let ctor = js.make_native(it, "Proxy", 2u32, proxy_ctor)
    ctor.ctor_kind = js.K_BASE
    let e0 = js.define_data(it, it.global, js.key_of("Proxy"), js.obj_value(ctor), js.P_HIDDEN)
    js.add_method(it, ctor, "revocable", 2u32, proxy_revocable)
}
