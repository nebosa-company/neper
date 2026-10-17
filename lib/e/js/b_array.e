// Array and array iterators (browser tracker 5.7).

use e.data.list as list
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

fn len_of(it: *js.Interp, o: *js.Obj) -> (f64, err) {
    let (n, e) = js.length_of(it, o)
    ret (n, e)
}

fn set_length(it: *js.Interp, o: *js.Obj, n: f64) -> err {
    let pe = js.put(it, js.obj_value(o), js.key_of("length"), js.num_value(n), true)
    ret pe
}

fn rel_index(it: *js.Interp, v: js.Value, len: f64, default_value: f64) -> (f64, err) {
    if js.is_undefined(v) { ret (default_value, ok) }
    let (n, e) = js.to_number(it, v)
    if e != ok { ret (0.0f64, e) }
    let i = js.to_integer(n)
    if i < 0.0f64 {
        let r = len + i
        if r < 0.0f64 { ret (0.0f64, ok) }
        ret (r, ok)
    }
    if i > len { ret (len, ok) }
    ret (i, ok)
}

fn cb_check(it: *js.Interp, f: js.Value) -> err {
    if !js.is_callable(f) { ret js.throw_type(it, "callback is not a function") }
    ret ok
}

fn array_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var proto = it.protos.array
    if it.has_new_target {
        let nto = js.as_object(it.new_target)
        let (p, pe) = js.proto_value_of(it, nto, it.protos.array)
        if pe != ok { ret (js.undefv(), pe) }
        proto = p
    }
    let a = js.new_array(it)
    a.proto = proto
    if args.len == 1usize && js.is_number(args[0usize]) {
        let n = js.num_of(args[0usize])
        let len = js.to_uint32_bits(n)
        if f64(len) != n { ret (js.undefv(), js.throw_range(it, "Invalid array length")) }
        a.num = f64(len)
        ret (js.obj_value(a), ok)
    }
    var i = 0usize
    while i < args.len {
        let pe2 = js.array_push(it, a, args[i])
        i += 1usize
    }
    ret (js.obj_value(a), ok)
}

fn array_is_array(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (r, e) = js.is_array_e(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(r), ok)
}

fn array_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.obj_value(js.array_from(it, args)), ok)
}

fn array_from_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let src = arg(args, 0usize)
    let mapper = arg(args, 1usize)
    let this_arg = arg(args, 2usize)
    if !js.is_undefined(mapper) && !js.is_callable(mapper) { ret (js.undefv(), js.throw_type(it, "Array.from: mapper is not a function")) }
    let out = js.new_array(it)
    if js.is_nullish(src) { ret (js.undefv(), js.throw_type(it, "Array.from requires an array-like or iterable")) }
    let (m, me) = js.get_value(it, src, js.key_of_symbol(it.sym_iterator))
    if me != ok { ret (js.undefv(), me) }
    var k = 0usize
    if !js.is_nullish(m) {
        let (iter, ie) = js.get_iterator(it, src)
        if ie != ok { ret (js.undefv(), ie) }
        while true {
            let (v, done, se) = js.iterator_step(it, iter)
            if se != ok { ret (js.undefv(), se) }
            if done { break }
            var item = v
            if js.is_callable(mapper) {
                let (mv, mve) = js.call_function(it, mapper, this_arg, js.two_args(it, v, js.num_value(f64(k))))
                if mve != ok {
                    let ce = js.iterator_close(it, iter)
                    ret (js.undefv(), mve)
                }
                item = mv
            }
            try js.array_push(it, out, item)
            k += 1usize
        }
        ret (js.obj_value(out), ok)
    }
    let (so, soe) = js.to_object(it, src)
    if soe != ok { ret (js.undefv(), soe) }
    let (len, le) = js.length_of(it, so)
    if le != ok { ret (js.undefv(), le) }
    while f64(k) < len {
        let (v2, ve2) = js.get_index(it, so, f64(k))
        if ve2 != ok { ret (js.undefv(), ve2) }
        var item2 = v2
        if js.is_callable(mapper) {
            let (mv2, mve2) = js.call_function(it, mapper, this_arg, js.two_args(it, v2, js.num_value(f64(k))))
            if mve2 != ok { ret (js.undefv(), mve2) }
            item2 = mv2
        }
        try js.array_push(it, out, item2)
        k += 1usize
    }
    ret (js.obj_value(out), ok)
}

fn array_push_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    var n = len
    var i = 0usize
    while i < args.len {
        if o.class == js.C_ARRAY && f64(o.elems.len) == n && o.text.len == 0usize && o.extensible {
            try js.array_push(it, o, args[i])
        } else {
            let se = js.set_index(it, o, n, args[i])
            if se != ok { ret (js.undefv(), se) }
        }
        n += 1.0f64
        i += 1usize
    }
    let sl = set_length(it, o, n)
    if sl != ok { ret (js.undefv(), sl) }
    ret (js.num_value(n), ok)
}

fn array_pop(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len == 0.0f64 {
        let sl = set_length(it, o, 0.0f64)
        if sl != ok { ret (js.undefv(), sl) }
        ret (js.undefv(), ok)
    }
    let (v, ve) = js.get_index(it, o, len - 1.0f64)
    if ve != ok { ret (js.undefv(), ve) }
    let key = js.key_of(js.number_to_string(it.a, len - 1.0f64))
    if !js.delete_prop(it, o, key) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
    let sl2 = set_length(it, o, len - 1.0f64)
    if sl2 != ok { ret (js.undefv(), sl2) }
    ret (v, ok)
}

fn array_shift(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len == 0.0f64 {
        let sl = set_length(it, o, 0.0f64)
        if sl != ok { ret (js.undefv(), sl) }
        ret (js.undefv(), ok)
    }
    let (first, fe) = js.get_index(it, o, 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    var k = 1.0f64
    while k < len {
        try js.tick(it)
        let from_key = js.key_of(js.number_to_string(it.a, k))
        let to_key = js.key_of(js.number_to_string(it.a, k - 1.0f64))
        if js.has_property(it, o, from_key) {
            let (v, ve) = js.get_index(it, o, k)
            if ve != ok { ret (js.undefv(), ve) }
            let se = js.set_index(it, o, k - 1.0f64, v)
            if se != ok { ret (js.undefv(), se) }
        } else {
            if !js.delete_prop(it, o, to_key) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
        }
        k += 1.0f64
    }
    if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, len - 1.0f64))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
    let sl2 = set_length(it, o, len - 1.0f64)
    if sl2 != ok { ret (js.undefv(), sl2) }
    ret (first, ok)
}

fn array_unshift(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let count = f64(args.len)
    if count > 0.0f64 {
        var k = len
        while k > 0.0f64 {
            try js.tick(it)
            let from_key = js.key_of(js.number_to_string(it.a, k - 1.0f64))
            if js.has_property(it, o, from_key) {
                let (v, ve) = js.get_index(it, o, k - 1.0f64)
                if ve != ok { ret (js.undefv(), ve) }
                let se = js.set_index(it, o, k + count - 1.0f64, v)
                if se != ok { ret (js.undefv(), se) }
            } else {
                if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, k + count - 1.0f64))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
            }
            k -= 1.0f64
        }
        var j = 0usize
        while j < args.len {
            let se2 = js.set_index(it, o, f64(j), args[j])
            if se2 != ok { ret (js.undefv(), se2) }
            j += 1usize
        }
    }
    let sl = set_length(it, o, len + count)
    if sl != ok { ret (js.undefv(), sl) }
    ret (js.num_value(len + count), ok)
}

fn array_slice(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (start, se) = rel_index(it, arg(args, 0usize), len, 0.0f64)
    if se != ok { ret (js.undefv(), se) }
    let (end, ee) = rel_index(it, arg(args, 1usize), len, len)
    if ee != ok { ret (js.undefv(), ee) }
    let out = js.new_array(it)
    var k = start
    var n = 0.0f64
    while k < end {
        try js.tick(it)
        if js.has_property(it, o, js.key_of(js.number_to_string(it.a, k))) {
            let (v, ve) = js.get_index(it, o, k)
            if ve != ok { ret (js.undefv(), ve) }
            let (done, de) = js.define_own(it, out, js.key_of(js.number_to_string(it.a, n)), js.data_desc(v, js.P_DEFAULT))
            if de != ok { ret (js.undefv(), de) }
        }
        k += 1.0f64
        n += 1.0f64
    }
    let sl = set_length(it, out, n)
    if sl != ok { ret (js.undefv(), sl) }
    ret (js.obj_value(out), ok)
}

fn array_splice(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (start, se) = rel_index(it, arg(args, 0usize), len, 0.0f64)
    if se != ok { ret (js.undefv(), se) }
    var delete_count = 0.0f64
    if args.len == 1usize {
        delete_count = len - start
    } else if args.len > 1usize {
        let (dn, dne) = js.to_number(it, args[1usize])
        if dne != ok { ret (js.undefv(), dne) }
        delete_count = js.to_integer(dn)
        if delete_count < 0.0f64 { delete_count = 0.0f64 }
        if delete_count > len - start { delete_count = len - start }
    }
    var items: []const js.Value = js.zero_args()
    if args.len > 2usize { items = args[2usize..] }
    let removed = js.new_array(it)
    var k = 0.0f64
    while k < delete_count {
        try js.tick(it)
        let fk = js.key_of(js.number_to_string(it.a, start + k))
        if js.has_property(it, o, fk) {
            let (v, ve) = js.get_index(it, o, start + k)
            if ve != ok { ret (js.undefv(), ve) }
            let (done, de) = js.define_own(it, removed, js.key_of(js.number_to_string(it.a, k)), js.data_desc(v, js.P_DEFAULT))
            if de != ok { ret (js.undefv(), de) }
        }
        k += 1.0f64
    }
    let sl = set_length(it, removed, delete_count)
    if sl != ok { ret (js.undefv(), sl) }
    let item_count = f64(items.len)
    if item_count < delete_count {
        var k2 = start
        while k2 < len - delete_count {
            try js.tick(it)
            let from = k2 + delete_count
            let to = k2 + item_count
            if js.has_property(it, o, js.key_of(js.number_to_string(it.a, from))) {
                let (v2, ve2) = js.get_index(it, o, from)
                if ve2 != ok { ret (js.undefv(), ve2) }
                let se2 = js.set_index(it, o, to, v2)
                if se2 != ok { ret (js.undefv(), se2) }
            } else {
                if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, to))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
            }
            k2 += 1.0f64
        }
        var k3 = len
        while k3 > len - delete_count + item_count {
            try js.tick(it)
            if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, k3 - 1.0f64))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
            k3 -= 1.0f64
        }
    } else if item_count > delete_count {
        var k4 = len - delete_count
        while k4 > start {
            try js.tick(it)
            let from2 = k4 + delete_count - 1.0f64
            let to2 = k4 + item_count - 1.0f64
            if js.has_property(it, o, js.key_of(js.number_to_string(it.a, from2))) {
                let (v3, ve3) = js.get_index(it, o, from2)
                if ve3 != ok { ret (js.undefv(), ve3) }
                let se3 = js.set_index(it, o, to2, v3)
                if se3 != ok { ret (js.undefv(), se3) }
            } else {
                if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, to2))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
            }
            k4 -= 1.0f64
        }
    }
    var i = 0usize
    while i < items.len {
        let se4 = js.set_index(it, o, start + f64(i), items[i])
        if se4 != ok { ret (js.undefv(), se4) }
        i += 1usize
    }
    let sl2 = set_length(it, o, len - delete_count + item_count)
    if sl2 != ok { ret (js.undefv(), sl2) }
    ret (js.obj_value(removed), ok)
}

fn is_concat_spreadable(it: *js.Interp, v: js.Value) -> (bool, err) {
    if !js.is_object(v) { ret (false, ok) }
    let (s, se) = js.get_value(it, v, js.key_of_symbol(it.sym_is_concat_spreadable))
    if se != ok { ret (false, se) }
    if !js.is_undefined(s) { ret (js.to_boolean(s), ok) }
    ret (js.is_array(v), ok)
}

fn array_concat(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let out = js.new_array(it)
    var n = 0.0f64
    var i = 0usize
    while i <= args.len {
        var item = js.obj_value(o)
        if i > 0usize { item = args[i - 1usize] }
        i += 1usize
        let (spread, sp) = is_concat_spreadable(it, item)
        if sp != ok { ret (js.undefv(), sp) }
        if spread {
            let ito = js.as_object(item)
            let (len, le) = len_of(it, ito)
            if le != ok { ret (js.undefv(), le) }
            var k = 0.0f64
            while k < len {
                try js.tick(it)
                if js.has_property(it, ito, js.key_of(js.number_to_string(it.a, k))) {
                    let (v, ve) = js.get_index(it, ito, k)
                    if ve != ok { ret (js.undefv(), ve) }
                    let (done, de) = js.define_own(it, out, js.key_of(js.number_to_string(it.a, n)), js.data_desc(v, js.P_DEFAULT))
                    if de != ok { ret (js.undefv(), de) }
                }
                k += 1.0f64
                n += 1.0f64
            }
        } else {
            let (done2, de2) = js.define_own(it, out, js.key_of(js.number_to_string(it.a, n)), js.data_desc(item, js.P_DEFAULT))
            if de2 != ok { ret (js.undefv(), de2) }
            n += 1.0f64
        }
    }
    let sl = set_length(it, out, n)
    if sl != ok { ret (js.undefv(), sl) }
    ret (js.obj_value(out), ok)
}

fn array_join(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    var sep = ","
    if !js.is_undefined(arg(args, 0usize)) {
        let (s, se) = js.to_string(it, args[0usize])
        if se != ok { ret (js.undefv(), se) }
        sep = s
    }
    // Cycle guard: an array already being joined contributes the empty string.
    let (parts_l, ple) = list.init[str](it.a, usize(len) + 1usize)
    var parts = parts_l
    var k = 0.0f64
    var total = 0usize
    while k < len {
        try js.tick(it)
        let (v, ve) = js.get_index(it, o, k)
        if ve != ok { ret (js.undefv(), ve) }
        var piece = ""
        if !js.is_nullish(v) {
            let (s2, se2) = js.to_string(it, v)
            if se2 != ok { ret (js.undefv(), se2) }
            piece = s2
        }
        try list.push[str](&parts, piece)
        total += piece.len
        k += 1.0f64
    }
    let (b, be) = str.builder(it.a, total + sep.len * parts.len + 1usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var i = 0usize
    while i < parts.len {
        if i > 0usize { let pe = str.push(&out, sep) }
        let pe2 = str.push(&out, parts.items[i])
        i += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn array_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (j, je) = js.get_prop(it, o, js.key_of("join"), js.obj_value(o))
    if je != ok { ret (js.undefv(), je) }
    if js.is_callable(j) {
        let (r, re) = js.call_function(it, j, js.obj_value(o), js.zero_args())
        ret (r, re)
    }
    let (ts, tse) = js.get_prop(it, it.protos.object, js.key_of("toString"), js.obj_value(it.protos.object))
    if tse != ok { ret (js.undefv(), tse) }
    let (r2, re2) = js.call_function(it, ts, js.obj_value(o), js.zero_args())
    ret (r2, re2)
}

fn array_reverse(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let middle = js.floor(len / 2.0f64)
    var lower = 0.0f64
    while lower != middle {
        try js.tick(it)
        let upper = len - lower - 1.0f64
        let lk = js.key_of(js.number_to_string(it.a, lower))
        let uk = js.key_of(js.number_to_string(it.a, upper))
        let lower_exists = js.has_property(it, o, lk)
        var lv = js.undefv()
        if lower_exists {
            let (v, ve) = js.get_index(it, o, lower)
            if ve != ok { ret (js.undefv(), ve) }
            lv = v
        }
        let upper_exists = js.has_property(it, o, uk)
        var uv = js.undefv()
        if upper_exists {
            let (v2, ve2) = js.get_index(it, o, upper)
            if ve2 != ok { ret (js.undefv(), ve2) }
            uv = v2
        }
        if lower_exists && upper_exists {
            let s1 = js.set_index(it, o, lower, uv)
            if s1 != ok { ret (js.undefv(), s1) }
            let s2 = js.set_index(it, o, upper, lv)
            if s2 != ok { ret (js.undefv(), s2) }
        } else if upper_exists {
            let s3 = js.set_index(it, o, lower, uv)
            if s3 != ok { ret (js.undefv(), s3) }
            if !js.delete_prop(it, o, uk) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
        } else if lower_exists {
            if !js.delete_prop(it, o, lk) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
            let s4 = js.set_index(it, o, upper, lv)
            if s4 != ok { ret (js.undefv(), s4) }
        }
        lower += 1.0f64
    }
    ret (js.obj_value(o), ok)
}

fn array_index_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len == 0.0f64 { ret (js.num_value(-1.0f64), ok) }
    var n = 0.0f64
    if args.len > 1usize {
        let (nv, ne) = js.to_number(it, args[1usize])
        if ne != ok { ret (js.undefv(), ne) }
        n = js.to_integer(nv)
    }
    if js.is_infinite(n) && n > 0.0f64 { ret (js.num_value(-1.0f64), ok) }
    var k = n
    if n < 0.0f64 {
        k = len + n
        if k < 0.0f64 { k = 0.0f64 }
    }
    let target_value = arg(args, 0usize)
    while k < len {
        try js.tick(it)
        if js.has_property(it, o, js.key_of(js.number_to_string(it.a, k))) {
            let (v, ve) = js.get_index(it, o, k)
            if ve != ok { ret (js.undefv(), ve) }
            if js.strict_equals(v, target_value) { ret (js.num_value(k), ok) }
        }
        k += 1.0f64
    }
    ret (js.num_value(-1.0f64), ok)
}

fn array_last_index_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len == 0.0f64 { ret (js.num_value(-1.0f64), ok) }
    var n = len - 1.0f64
    if args.len > 1usize {
        let (nv, ne) = js.to_number(it, args[1usize])
        if ne != ok { ret (js.undefv(), ne) }
        n = js.to_integer(nv)
    }
    var k = n
    if n < 0.0f64 {
        k = len + n
    } else if n > len - 1.0f64 {
        k = len - 1.0f64
    }
    let target_value = arg(args, 0usize)
    while k >= 0.0f64 {
        try js.tick(it)
        if js.has_property(it, o, js.key_of(js.number_to_string(it.a, k))) {
            let (v, ve) = js.get_index(it, o, k)
            if ve != ok { ret (js.undefv(), ve) }
            if js.strict_equals(v, target_value) { ret (js.num_value(k), ok) }
        }
        k -= 1.0f64
    }
    ret (js.num_value(-1.0f64), ok)
}

fn array_includes(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len == 0.0f64 { ret (js.bool_value(false), ok) }
    var n = 0.0f64
    if args.len > 1usize {
        let (nv, ne) = js.to_number(it, args[1usize])
        if ne != ok { ret (js.undefv(), ne) }
        n = js.to_integer(nv)
    }
    var k = n
    if n < 0.0f64 {
        k = len + n
        if k < 0.0f64 { k = 0.0f64 }
    }
    let target_value = arg(args, 0usize)
    while k < len {
        try js.tick(it)
        let (v, ve) = js.get_index(it, o, k)
        if ve != ok { ret (js.undefv(), ve) }
        if js.same_value_zero(v, target_value) { ret (js.bool_value(true), ok) }
        k += 1.0f64
    }
    ret (js.bool_value(false), ok)
}

// Iteration helpers: kind 0 forEach, 1 map, 2 filter, 3 some, 4 every, 5 find, 6 findIndex, 7 findLast, 8 findLastIndex.
fn iterate_with(it: *js.Interp, this_val: js.Value, args: []const js.Value, kind: u8) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let cb = arg(args, 0usize)
    let ce = cb_check(it, cb)
    if ce != ok { ret (js.undefv(), ce) }
    let this_arg = arg(args, 1usize)
    if kind == 1u8 && len > 4294967295.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid array length")) }
    var out = js.new_array(it)
    if kind == 1u8 { out.num = len }
    var out_n = 0.0f64
    let reverse = kind == 7u8 || kind == 8u8
    var k = 0.0f64
    if reverse { k = len - 1.0f64 }
    while (!reverse && k < len) || (reverse && k >= 0.0f64) {
        try js.tick(it)
        let key = js.key_of(js.number_to_string(it.a, k))
        let present = js.has_property(it, o, key)
        if present || kind >= 5u8 {
            let (v, ve) = js.get_index(it, o, k)
            if ve != ok { ret (js.undefv(), ve) }
            let (r, re) = js.call_function(it, cb, this_arg, three_args(it, v, js.num_value(k), js.obj_value(o)))
            if re != ok { ret (js.undefv(), re) }
            if kind == 1u8 {
                let (d, de) = js.define_own(it, out, key, js.data_desc(r, js.P_DEFAULT))
                if de != ok { ret (js.undefv(), de) }
            } else if kind == 2u8 {
                if js.to_boolean(r) {
                    let (d2, de2) = js.define_own(it, out, js.key_of(js.number_to_string(it.a, out_n)), js.data_desc(v, js.P_DEFAULT))
                    if de2 != ok { ret (js.undefv(), de2) }
                    out_n += 1.0f64
                }
            } else if kind == 3u8 {
                if js.to_boolean(r) { ret (js.bool_value(true), ok) }
            } else if kind == 4u8 {
                if !js.to_boolean(r) { ret (js.bool_value(false), ok) }
            } else if kind == 5u8 || kind == 7u8 {
                if js.to_boolean(r) { ret (v, ok) }
            } else if kind == 6u8 || kind == 8u8 {
                if js.to_boolean(r) { ret (js.num_value(k), ok) }
            }
        }
        if reverse { k -= 1.0f64 } else { k += 1.0f64 }
    }
    if kind == 1u8 || kind == 2u8 { ret (js.obj_value(out), ok) }
    if kind == 3u8 { ret (js.bool_value(false), ok) }
    if kind == 4u8 { ret (js.bool_value(true), ok) }
    if kind == 6u8 || kind == 8u8 { ret (js.num_value(-1.0f64), ok) }
    ret (js.undefv(), ok)
}

fn three_args(it: *js.Interp, x: js.Value, y: js.Value, z: js.Value) -> []const js.Value {
    let (cell, ce) = mem.alloc[js.Value](it.a, 3usize)
    if ce != ok { ret js.zero_args() }
    cell[0usize] = x
    cell[1usize] = y
    cell[2usize] = z
    ret cell[0usize..3usize]
}

fn four_args(it: *js.Interp, x: js.Value, y: js.Value, z: js.Value, w: js.Value) -> []const js.Value {
    let (cell, ce) = mem.alloc[js.Value](it.a, 4usize)
    if ce != ok { ret js.zero_args() }
    cell[0usize] = x
    cell[1usize] = y
    cell[2usize] = z
    cell[3usize] = w
    ret cell[0usize..4usize]
}

fn array_for_each(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 0u8)
    ret (r, e) }
fn array_map(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 1u8)
    ret (r, e) }
fn array_filter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 2u8)
    ret (r, e) }
fn array_some(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 3u8)
    ret (r, e) }
fn array_every(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 4u8)
    ret (r, e) }
fn array_find(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 5u8)
    ret (r, e) }
fn array_find_index(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 6u8)
    ret (r, e) }
fn array_find_last(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 7u8)
    ret (r, e) }
fn array_find_last_index(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = iterate_with(it, this_val, args, 8u8)
    ret (r, e) }

fn reduce_with(it: *js.Interp, this_val: js.Value, args: []const js.Value, right: bool) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let cb = arg(args, 0usize)
    let ce = cb_check(it, cb)
    if ce != ok { ret (js.undefv(), ce) }
    var k = 0.0f64
    if right { k = len - 1.0f64 }
    var acc = js.undefv()
    var have = false
    if args.len >= 2usize {
        acc = args[1usize]
        have = true
    } else {
        while !have && ((!right && k < len) || (right && k >= 0.0f64)) {
            if js.has_property(it, o, js.key_of(js.number_to_string(it.a, k))) {
                let (v, ve) = js.get_index(it, o, k)
                if ve != ok { ret (js.undefv(), ve) }
                acc = v
                have = true
            }
            if right { k -= 1.0f64 } else { k += 1.0f64 }
        }
        if !have { ret (js.undefv(), js.throw_type(it, "Reduce of empty array with no initial value")) }
    }
    while (!right && k < len) || (right && k >= 0.0f64) {
        if js.has_property(it, o, js.key_of(js.number_to_string(it.a, k))) {
            let (v2, ve2) = js.get_index(it, o, k)
            if ve2 != ok { ret (js.undefv(), ve2) }
            let (r, re) = js.call_function(it, cb, js.undefv(), four_args(it, acc, v2, js.num_value(k), js.obj_value(o)))
            if re != ok { ret (js.undefv(), re) }
            acc = r
        }
        if right { k -= 1.0f64 } else { k += 1.0f64 }
    }
    ret (acc, ok)
}

fn array_reduce(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = reduce_with(it, this_val, args, false)
    ret (r, e) }
fn array_reduce_right(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = reduce_with(it, this_val, args, true)
    ret (r, e) }

fn array_fill(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (start, se) = rel_index(it, arg(args, 1usize), len, 0.0f64)
    if se != ok { ret (js.undefv(), se) }
    let (end, ee) = rel_index(it, arg(args, 2usize), len, len)
    if ee != ok { ret (js.undefv(), ee) }
    var k = start
    while k < end {
        try js.tick(it)
        let pe = js.set_index(it, o, k, arg(args, 0usize))
        if pe != ok { ret (js.undefv(), pe) }
        k += 1.0f64
    }
    ret (js.obj_value(o), ok)
}

fn array_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    var k = js.to_integer(n)
    if k < 0.0f64 { k = len + k }
    if k < 0.0f64 || k >= len { ret (js.undefv(), ok) }
    let (v, ve) = js.get_index(it, o, k)
    ret (v, ve)
}

fn array_copy_within(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (to, te) = rel_index(it, arg(args, 0usize), len, 0.0f64)
    if te != ok { ret (js.undefv(), te) }
    let (from, fe) = rel_index(it, arg(args, 1usize), len, 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    let (fin, fine) = rel_index(it, arg(args, 2usize), len, len)
    if fine != ok { ret (js.undefv(), fine) }
    var count = fin - from
    if len - to < count { count = len - to }
    var dir = 1.0f64
    var f2 = from
    var t2 = to
    if from < to && to < from + count {
        dir = -1.0f64
        f2 = from + count - 1.0f64
        t2 = to + count - 1.0f64
    }
    while count > 0.0f64 {
        try js.tick(it)
        if js.has_property(it, o, js.key_of(js.number_to_string(it.a, f2))) {
            let (v, ve) = js.get_index(it, o, f2)
            if ve != ok { ret (js.undefv(), ve) }
            let se = js.set_index(it, o, t2, v)
            if se != ok { ret (js.undefv(), se) }
        } else {
            if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, t2))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
        }
        f2 += dir
        t2 += dir
        count -= 1.0f64
    }
    ret (js.obj_value(o), ok)
}

// --- sort (merge sort, stable)

fn sort_compare(it: *js.Interp, cmp: js.Value, x: js.Value, y: js.Value) -> (f64, err) {
    if js.is_undefined(x) && js.is_undefined(y) { ret (0.0f64, ok) }
    if js.is_undefined(x) { ret (1.0f64, ok) }
    if js.is_undefined(y) { ret (-1.0f64, ok) }
    if !js.is_undefined(cmp) {
        let (r, re) = js.call_function(it, cmp, js.undefv(), js.two_args(it, x, y))
        if re != ok { ret (0.0f64, re) }
        let (n, ne) = js.to_number(it, r)
        if ne != ok { ret (0.0f64, ne) }
        if js.is_nan(n) { ret (0.0f64, ok) }
        ret (n, ok)
    }
    let (sx, se) = js.to_string(it, x)
    if se != ok { ret (0.0f64, se) }
    let (sy, se2) = js.to_string(it, y)
    if se2 != ok { ret (0.0f64, se2) }
    let c = js.compare_utf16(sx, sy)
    if c < 0i32 { ret (-1.0f64, ok) }
    if c > 0i32 { ret (1.0f64, ok) }
    ret (0.0f64, ok)
}

fn merge_sort(it: *js.Interp, cmp: js.Value, items: []js.Value, tmp: []js.Value, lo: usize, hi: usize) -> err {
    if hi - lo < 2usize { ret ok }
    let mid = lo + (hi - lo) / 2usize
    try merge_sort(it, cmp, items, tmp, lo, mid)
    try merge_sort(it, cmp, items, tmp, mid, hi)
    var i = lo
    var j = mid
    var k = lo
    while i < mid && j < hi {
        let (c, ce) = sort_compare(it, cmp, items[j], items[i])
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

fn array_sort(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let cmp = arg(args, 0usize)
    if !js.is_undefined(cmp) && !js.is_callable(cmp) { ret (js.undefv(), js.throw_type(it, "The comparison function must be either a function or undefined")) }
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = len_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (l, lie) = list.init[js.Value](it.a, usize(len) + 1usize)
    var vals = l
    var k = 0.0f64
    var holes = 0.0f64
    while k < len {
        try js.tick(it)
        if js.has_property(it, o, js.key_of(js.number_to_string(it.a, k))) {
            let (v, ve) = js.get_index(it, o, k)
            if ve != ok { ret (js.undefv(), ve) }
            try list.push[js.Value](&vals, v)
        } else {
            holes += 1.0f64
        }
        k += 1.0f64
    }
    let (tmp, tmpe) = mem.alloc[js.Value](it.a, vals.len + 1usize)
    if tmpe != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let se = merge_sort(it, cmp, list.slice[js.Value](&vals), tmp, 0usize, vals.len)
    if se != ok { ret (js.undefv(), se) }
    var i = 0usize
    while i < vals.len {
        let pe = js.set_index(it, o, f64(i), vals.items[i])
        if pe != ok { ret (js.undefv(), pe) }
        i += 1usize
    }
    var d = f64(vals.len)
    while d < len {
        if !js.delete_prop(it, o, js.key_of(js.number_to_string(it.a, d))) { ret (js.undefv(), js.throw_type(it, "Cannot delete property")) }
        d += 1.0f64
    }
    ret (js.obj_value(o), ok)
}

// --- flat / flatMap

fn flatten_into(it: *js.Interp, target_arr: *js.Obj, src: *js.Obj, depth: f64, mapper: js.Value, this_arg: js.Value, start: f64) -> (f64, err) {
    let (len, le) = len_of(it, src)
    if le != ok { ret (0.0f64, le) }
    var n = start
    var k = 0.0f64
    while k < len {
        try js.tick(it)
        if js.has_property(it, src, js.key_of(js.number_to_string(it.a, k))) {
            let (v0, ve) = js.get_index(it, src, k)
            if ve != ok { ret (0.0f64, ve) }
            var v = v0
            if js.is_callable(mapper) {
                let (mv, mve) = js.call_function(it, mapper, this_arg, three_args(it, v, js.num_value(k), js.obj_value(src)))
                if mve != ok { ret (0.0f64, mve) }
                v = mv
            }
            if depth > 0.0f64 && js.is_array(v) {
                let (n2, ne2) = flatten_into(it, target_arr, js.as_object(v), depth - 1.0f64, js.undefv(), js.undefv(), n)
                if ne2 != ok { ret (0.0f64, ne2) }
                n = n2
            } else {
                let (done, de) = js.define_own(it, target_arr, js.key_of(js.number_to_string(it.a, n)), js.data_desc(v, js.P_DEFAULT))
                if de != ok { ret (0.0f64, de) }
                n += 1.0f64
            }
        }
        k += 1.0f64
    }
    ret (n, ok)
}

fn array_flat(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    var depth = 1.0f64
    if !js.is_undefined(arg(args, 0usize)) {
        let (dn, de) = js.to_number(it, args[0usize])
        if de != ok { ret (js.undefv(), de) }
        depth = js.to_integer(dn)
    }
    let out = js.new_array(it)
    let (n, fe) = flatten_into(it, out, o, depth, js.undefv(), js.undefv(), 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    ret (js.obj_value(out), ok)
}

fn array_flat_map(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let cb = arg(args, 0usize)
    let ce = cb_check(it, cb)
    if ce != ok { ret (js.undefv(), ce) }
    let out = js.new_array(it)
    let (n, fe) = flatten_into(it, out, o, 1.0f64, cb, arg(args, 1usize), 0.0f64)
    if fe != ok { ret (js.undefv(), fe) }
    ret (js.obj_value(out), ok)
}

// --- iterators

fn make_array_iterator(it: *js.Interp, o: *js.Obj, kind: f64) -> js.Value {
    let iter = js.new_obj(it, js.C_ITERATOR, it.protos.array_iterator)
    iter.aux = o
    iter.num = 0.0f64
    iter.text = "array"
    if kind == 1.0f64 { iter.text = "array-values" }
    if kind == 2.0f64 { iter.text = "array-entries" }
    if kind == 0.0f64 { iter.text = "array-keys" }
    ret js.obj_value(iter)
}

fn array_keys(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    ret (make_array_iterator(it, o, 0.0f64), ok)
}

fn array_values(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    ret (make_array_iterator(it, o, 1.0f64), ok)
}

fn array_entries(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    ret (make_array_iterator(it, o, 2.0f64), ok)
}

fn iter_result(it: *js.Interp, v: js.Value, done: bool) -> js.Value {
    let r = js.new_plain(it)
    let e1 = js.set_named(it, r, "value", v)
    let e2 = js.set_named(it, r, "done", js.bool_value(done))
    ret js.obj_value(r)
}

fn array_iterator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_ITERATOR || !str.starts_with(js.as_object(this_val).text, "array") {
        ret (js.undefv(), js.throw_type(it, "next method called on incompatible receiver"))
    }
    let iter = js.as_object(this_val)
    if iter.aux == js.null_obj() { ret (iter_result(it, js.undefv(), true), ok) }
    let (len, le) = js.length_of(it, iter.aux)
    if le != ok { ret (js.undefv(), le) }
    let idx = iter.num
    if idx >= len {
        iter.aux = js.null_obj()
        ret (iter_result(it, js.undefv(), true), ok)
    }
    iter.num = idx + 1.0f64
    if str.eq(iter.text, "array-keys") { ret (iter_result(it, js.num_value(idx), false), ok) }
    let (v, ve) = js.get_index(it, iter.aux, idx)
    if ve != ok { ret (js.undefv(), ve) }
    if str.eq(iter.text, "array-entries") {
        let pair = js.array_from(it, js.two_args(it, js.num_value(idx), v))
        ret (iter_result(it, js.obj_value(pair), false), ok)
    }
    ret (iter_result(it, v, false), ok)
}

fn iterator_proto_self(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn array_species_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn install_array(it: *js.Interp) {
    let proto = it.protos.array
    let ctor = js.make_native(it, "Array", 1u32, array_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("Array"), js.obj_value(ctor), js.P_HIDDEN)
    it.last = ctor
    js.add_method(it, it.last, "isArray", 1u32, array_is_array)
    js.add_method(it, it.last, "of", 0u32, array_of)
    js.add_method(it, it.last, "from", 1u32, array_from_fn)
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, array_species_getter)
    let e4 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.array, "push", 1u32, array_push_m)
    js.add_method(it, it.protos.array, "pop", 0u32, array_pop)
    js.add_method(it, it.protos.array, "shift", 0u32, array_shift)
    js.add_method(it, it.protos.array, "unshift", 1u32, array_unshift)
    js.add_method(it, it.protos.array, "slice", 2u32, array_slice)
    js.add_method(it, it.protos.array, "splice", 2u32, array_splice)
    js.add_method(it, it.protos.array, "concat", 1u32, array_concat)
    js.add_method(it, it.protos.array, "join", 1u32, array_join)
    js.add_method(it, it.protos.array, "toString", 0u32, array_to_string)
    js.add_method(it, it.protos.array, "reverse", 0u32, array_reverse)
    js.add_method(it, it.protos.array, "indexOf", 1u32, array_index_of)
    js.add_method(it, it.protos.array, "lastIndexOf", 1u32, array_last_index_of)
    js.add_method(it, it.protos.array, "includes", 1u32, array_includes)
    js.add_method(it, it.protos.array, "forEach", 1u32, array_for_each)
    js.add_method(it, it.protos.array, "map", 1u32, array_map)
    js.add_method(it, it.protos.array, "filter", 1u32, array_filter)
    js.add_method(it, it.protos.array, "some", 1u32, array_some)
    js.add_method(it, it.protos.array, "every", 1u32, array_every)
    js.add_method(it, it.protos.array, "find", 1u32, array_find)
    js.add_method(it, it.protos.array, "findIndex", 1u32, array_find_index)
    js.add_method(it, it.protos.array, "findLast", 1u32, array_find_last)
    js.add_method(it, it.protos.array, "findLastIndex", 1u32, array_find_last_index)
    js.add_method(it, it.protos.array, "reduce", 1u32, array_reduce)
    js.add_method(it, it.protos.array, "reduceRight", 1u32, array_reduce_right)
    js.add_method(it, it.protos.array, "fill", 1u32, array_fill)
    js.add_method(it, it.protos.array, "at", 1u32, array_at)
    js.add_method(it, it.protos.array, "copyWithin", 2u32, array_copy_within)
    js.add_method(it, it.protos.array, "sort", 1u32, array_sort)
    js.add_method(it, it.protos.array, "flat", 0u32, array_flat)
    js.add_method(it, it.protos.array, "flatMap", 1u32, array_flat_map)
    js.add_method(it, it.protos.array, "keys", 0u32, array_keys)
    js.add_method(it, it.protos.array, "entries", 0u32, array_entries)
    let values = js.make_native(it, "values", 0u32, array_values)
    let e5 = js.define_data(it, it.protos.array, js.key_of("values"), js.obj_value(values), js.P_HIDDEN)
    let e6 = js.define_data(it, it.protos.array, js.key_of_symbol(it.sym_iterator), js.obj_value(values), js.P_HIDDEN)
    // Iterator prototypes.
    let self_fn = js.make_native(it, "[Symbol.iterator]", 0u32, iterator_proto_self)
    let e7 = js.define_data(it, it.protos.iterator, js.key_of_symbol(it.sym_iterator), js.obj_value(self_fn), js.P_HIDDEN)
    js.add_method(it, it.protos.array_iterator, "next", 0u32, array_iterator_next)
    let e8 = js.define_data(it, it.protos.array_iterator, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Array Iterator"), js.P_CONFIGURABLE)
}
