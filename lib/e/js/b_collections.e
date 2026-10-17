// Map, Set, WeakMap, WeakSet, WeakRef and FinalizationRegistry (browser tracker 5.8).
//
// A collection keeps its entries in insertion order in an append-only list (a removed entry becomes a tombstone, so a live
// iterator keeps its place) and finds keys through a hash index of SameValueZero hashes chained through the entries. Weak
// collections hold their keys strongly: with no collector there is nothing to release.

use e.data.list as list
use e.data.map as map
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

type Entry = struct { key: js.Value, value: js.Value, live: bool, next: usize }

const NIL: usize = 18446744073709551615usize

type Store = struct { entries: list.List[Entry], index: map.Map[u64, usize], live: usize, weak: bool }

fn hash_value(v: js.Value) -> u64 {
    switch v {
    case .Undefined:
        ret 1u64
    case .Null:
        ret 2u64
    case .Bool as b:
        if b { ret 4u64 }
        ret 3u64
    case .Num as n:
        var x = n
        if x == 0.0f64 { x = 0.0f64 }
        if js.is_nan(x) { ret 5u64 }
        let bits = mem.bitcast[u64](x)
        ret (bits ^ (bits >> 29u64)) *% 11400714819323198485u64
    case .Str as s:
        var h2 = 14695981039346656037u64
        var k = 0usize
        while k < s.len {
            h2 = (h2 ^ u64(s[k])) *% 1099511628211u64
            k += 1usize
        }
        ret h2
    case .Sym as sy:
        ret (u64(sy.id) *% 2654435761u64) +% 7u64
    case .Obj as o:
        ret o.id *% 11400714819323198485u64
    case .Big as bg:
        var h4 = 17u64
        if bg.neg { h4 = 19u64 }
        var li = 0usize
        while li < bg.mag.len {
            h4 = (h4 ^ u64(bg.mag[li])) *% 1099511628211u64
            li += 1usize
        }
        ret h4
    }
    ret 0u64
}

fn store_of(o: *js.Obj) -> *Store { ret mem.cast[*Store](o.data) }

fn new_store(it: *js.Interp, o: *js.Obj, weak: bool) -> err {
    let (cell, ce) = mem.alloc[Store](it.a, 1usize)
    if ce != ok { ret js.throw_range(it, "out of memory") }
    var blank: Store = zero
    cell[0usize] = blank
    let st = &cell[0usize]
    let (el, ee) = list.init[Entry](it.a, 4usize)
    st.entries = el
    let (im, ie) = map.init[u64, usize](it.a, 8usize)
    st.index = im
    st.weak = weak
    o.data = mem.cast[*void](st)
    ret ok
}

fn find_entry(st: *Store, key: js.Value) -> (usize, bool) {
    let h = hash_value(key)
    let (first, found) = map.get[u64, usize](&st.index, h)
    if !found { ret (0usize, false) }
    var at = first
    while at != NIL {
        let e = st.entries.items[at]
        if e.live && js.same_value_zero(e.key, key) { ret (at, true) }
        at = e.next
    }
    ret (0usize, false)
}

fn store_set(it: *js.Interp, st: *Store, key_in: js.Value, value: js.Value) -> err {
    var key = key_in
    if js.is_number(key) && js.num_of(key) == 0.0f64 { key = js.num_value(0.0f64) }
    let (at, found) = find_entry(st, key)
    if found {
        st.entries.items[at].value = value
        ret ok
    }
    let h = hash_value(key)
    let (first, has) = map.get[u64, usize](&st.index, h)
    var next = NIL
    if has { next = first }
    try list.push[Entry](&st.entries, Entry { key: key, value: value, live: true, next: next })
    let (r, pe) = map.put[u64, usize](&st.index, h, st.entries.len - 1usize)
    if pe != ok { ret js.throw_range(it, "out of memory") }
    st.live += 1usize
    ret ok
}

fn store_delete(st: *Store, key: js.Value) -> bool {
    let (at, found) = find_entry(st, key)
    if !found { ret false }
    st.entries.items[at].live = false
    st.entries.items[at].key = js.undefv()
    st.entries.items[at].value = js.undefv()
    st.live -= 1usize
    ret true
}

fn this_store(it: *js.Interp, v: js.Value, class: u8, name: str) -> (*Store, err) {
    if js.is_object(v) && js.as_object(v).class == class && js.as_object(v).data != zero_ptr() {
        ret (store_of(js.as_object(v)), ok)
    }
    var none: *Store = zero
    ret (none, js.throw_type(it, js.str_concat(it, name, " method called on incompatible receiver")))
}

fn zero_ptr() -> *void {
    var p: *void = zero
    ret p
}

fn construct_collection(it: *js.Interp, class: u8, proto_default: *js.Obj, weak: bool, args: []const js.Value, adder: str, pairs: bool) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Constructor requires 'new'")) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, proto_default)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, class, proto)
    let se = new_store(it, o, weak)
    if se != ok { ret (js.undefv(), se) }
    let iterable = arg(args, 0usize)
    if js.is_nullish(iterable) { ret (js.obj_value(o), ok) }
    let (add, ae) = js.get_prop(it, o, js.key_of(adder), js.obj_value(o))
    if ae != ok { ret (js.undefv(), ae) }
    if !js.is_callable(add) { ret (js.undefv(), js.throw_type(it, "adder is not a function")) }
    let (iter, ie) = js.get_iterator(it, iterable)
    if ie != ok { ret (js.undefv(), ie) }
    while true {
        let (item, done, ste) = js.iterator_step(it, iter)
        if ste != ok { ret (js.undefv(), ste) }
        if done { break }
        if pairs {
            if !js.is_object(item) {
                let cl = js.iterator_close(it, iter)
                ret (js.undefv(), js.throw_type(it, "Iterator value is not an entry object"))
            }
            let (k, ke) = js.get_value(it, item, js.key_of("0"))
            if ke != ok {
                let cl2 = js.iterator_close(it, iter)
                ret (js.undefv(), ke)
            }
            let (v, ve) = js.get_value(it, item, js.key_of("1"))
            if ve != ok {
                let cl3 = js.iterator_close(it, iter)
                ret (js.undefv(), ve)
            }
            let (r, re) = js.call_function(it, add, js.obj_value(o), js.two_args(it, k, v))
            if re != ok {
                let cl4 = js.iterator_close(it, iter)
                ret (js.undefv(), re)
            }
        } else {
            let (r2, re2) = js.call_function(it, add, js.obj_value(o), js.one_arg(it, item))
            if re2 != ok {
                let cl5 = js.iterator_close(it, iter)
                ret (js.undefv(), re2)
            }
        }
    }
    ret (js.obj_value(o), ok)
}

fn map_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = construct_collection(it, js.C_MAP, it.protos.map, false, args, "set", true)
    ret (r, e) }
fn set_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = construct_collection(it, js.C_SET, it.protos.set, false, args, "add", false)
    ret (r, e) }
fn weakmap_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = construct_collection(it, js.C_WEAKMAP, it.protos.weakmap, true, args, "set", true)
    ret (r, e) }
fn weakset_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = construct_collection(it, js.C_WEAKSET, it.protos.weakset, true, args, "add", false)
    ret (r, e) }

// --- Map

fn map_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.get")
    if e != ok { ret (js.undefv(), e) }
    let (at, found) = find_entry(st, arg(args, 0usize))
    if !found { ret (js.undefv(), ok) }
    ret (st.entries.items[at].value, ok)
}

fn map_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.set")
    if e != ok { ret (js.undefv(), e) }
    let se = store_set(it, st, arg(args, 0usize), arg(args, 1usize))
    if se != ok { ret (js.undefv(), se) }
    ret (this_val, ok)
}

fn map_has(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.has")
    if e != ok { ret (js.undefv(), e) }
    let (at, found) = find_entry(st, arg(args, 0usize))
    ret (js.bool_value(found), ok)
}

fn map_delete(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.delete")
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(store_delete(st, arg(args, 0usize))), ok)
}

fn store_clear(st: *Store) {
    var i = 0usize
    while i < st.entries.len {
        st.entries.items[i].live = false
        st.entries.items[i].key = js.undefv()
        st.entries.items[i].value = js.undefv()
        i += 1usize
    }
    st.live = 0usize
}

fn map_clear(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.clear")
    if e != ok { ret (js.undefv(), e) }
    store_clear(st)
    ret (js.undefv(), ok)
}

fn map_size(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "get Map.prototype.size")
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(f64(st.live)), ok)
}

fn map_for_each(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.forEach")
    if e != ok { ret (js.undefv(), e) }
    let cb = arg(args, 0usize)
    if !js.is_callable(cb) { ret (js.undefv(), js.throw_type(it, "callback is not a function")) }
    var i = 0usize
    while i < st.entries.len {
        let en = st.entries.items[i]
        i += 1usize
        if !en.live { continue }
        let (r, re) = js.call_function(it, cb, arg(args, 1usize), three(it, en.value, en.key, this_val))
        if re != ok { ret (js.undefv(), re) }
    }
    ret (js.undefv(), ok)
}

fn three(it: *js.Interp, x: js.Value, y: js.Value, z: js.Value) -> []const js.Value {
    let (cell, ce) = mem.alloc[js.Value](it.a, 3usize)
    if ce != ok { ret js.zero_args() }
    cell[0usize] = x
    cell[1usize] = y
    cell[2usize] = z
    ret cell[0usize..3usize]
}

// --- iterators: kind 0 keys, 1 values, 2 entries

fn make_iterator(it: *js.Interp, o: *js.Obj, kind: f64, proto: *js.Obj) -> js.Value {
    let iter = js.new_obj(it, js.C_ITERATOR, proto)
    iter.aux = o
    iter.num = 0.0f64
    iter.text = "collection"
    iter.prim = js.num_value(kind)
    ret js.obj_value(iter)
}

fn iter_result(it: *js.Interp, v: js.Value, done: bool) -> js.Value {
    let r = js.new_plain(it)
    let e1 = js.set_named(it, r, "value", v)
    let e2 = js.set_named(it, r, "done", js.bool_value(done))
    ret js.obj_value(r)
}

fn collection_iterator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value, class: u8) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_ITERATOR || !str.eq(js.as_object(this_val).text, "collection") {
        ret (js.undefv(), js.throw_type(it, "next method called on incompatible receiver"))
    }
    let iter = js.as_object(this_val)
    if iter.aux == js.null_obj() { ret (iter_result(it, js.undefv(), true), ok) }
    if iter.aux.class != class { ret (js.undefv(), js.throw_type(it, "next method called on incompatible receiver")) }
    let st = store_of(iter.aux)
    var at = usize(iter.num)
    while at < st.entries.len && !st.entries.items[at].live { at += 1usize }
    if at >= st.entries.len {
        iter.aux = js.null_obj()
        ret (iter_result(it, js.undefv(), true), ok)
    }
    iter.num = f64(at + 1usize)
    let en = st.entries.items[at]
    let kind = js.num_of(iter.prim)
    if kind == 0.0f64 { ret (iter_result(it, en.key, false), ok) }
    if kind == 1.0f64 { ret (iter_result(it, en.value, false), ok) }
    let pair = js.array_from(it, js.two_args(it, en.key, en.value))
    ret (iter_result(it, js.obj_value(pair), false), ok)
}

fn map_iterator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = collection_iterator_next(it, this_val, args, js.C_MAP)
    ret (r, e) }
fn set_iterator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = collection_iterator_next(it, this_val, args, js.C_SET)
    ret (r, e) }

fn map_keys(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.keys")
    if e != ok { ret (js.undefv(), e) }
    ret (make_iterator(it, js.as_object(this_val), 0.0f64, it.protos.map_iterator), ok)
}
fn map_values(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.values")
    if e != ok { ret (js.undefv(), e) }
    ret (make_iterator(it, js.as_object(this_val), 1.0f64, it.protos.map_iterator), ok)
}
fn map_entries(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_MAP, "Map.prototype.entries")
    if e != ok { ret (js.undefv(), e) }
    ret (make_iterator(it, js.as_object(this_val), 2.0f64, it.protos.map_iterator), ok)
}

fn map_group_by(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let cb = arg(args, 1usize)
    if !js.is_callable(cb) { ret (js.undefv(), js.throw_type(it, "callback is not a function")) }
    let o = js.new_obj(it, js.C_MAP, it.protos.map)
    let se = new_store(it, o, false)
    if se != ok { ret (js.undefv(), se) }
    let st = store_of(o)
    let (items, ie) = js.iterate_to_list(it, arg(args, 0usize))
    if ie != ok { ret (js.undefv(), ie) }
    var i = 0usize
    while i < items.len {
        let (k, ke) = js.call_function(it, cb, js.undefv(), js.two_args(it, items.items[i], js.num_value(f64(i))))
        if ke != ok { ret (js.undefv(), ke) }
        let (at, found) = find_entry(st, k)
        if found {
            let ga = js.as_object(st.entries.items[at].value)
            try js.array_push(it, ga, items.items[i])
        } else {
            let ga2 = js.new_array(it)
            try js.array_push(it, ga2, items.items[i])
            let sse = store_set(it, st, k, js.obj_value(ga2))
            if sse != ok { ret (js.undefv(), sse) }
        }
        i += 1usize
    }
    ret (js.obj_value(o), ok)
}

fn species_self(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn install_map(it: *js.Interp) {
    let proto = it.protos.map
    let ctor = js.make_native(it, "Map", 0u32, map_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("Map"), js.obj_value(ctor), js.P_HIDDEN)
    it.last = ctor
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e4 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_method(it, it.last, "groupBy", 2u32, map_group_by)
    js.add_method(it, it.protos.map, "get", 1u32, map_get)
    js.add_method(it, it.protos.map, "set", 2u32, map_set)
    js.add_method(it, it.protos.map, "has", 1u32, map_has)
    js.add_method(it, it.protos.map, "delete", 1u32, map_delete)
    js.add_method(it, it.protos.map, "clear", 0u32, map_clear)
    js.add_method(it, it.protos.map, "forEach", 1u32, map_for_each)
    js.add_method(it, it.protos.map, "keys", 0u32, map_keys)
    js.add_method(it, it.protos.map, "values", 0u32, map_values)
    js.add_getter(it, it.protos.map, "size", map_size)
    let ent = js.make_native(it, "entries", 0u32, map_entries)
    let e5 = js.define_data(it, it.protos.map, js.key_of("entries"), js.obj_value(ent), js.P_HIDDEN)
    let e6 = js.define_data(it, it.protos.map, js.key_of_symbol(it.sym_iterator), js.obj_value(ent), js.P_HIDDEN)
    let e7 = js.define_data(it, it.protos.map, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Map"), js.P_CONFIGURABLE)
    it.protos.map_iterator = js.new_obj(it, js.C_OBJECT, it.protos.iterator)
    js.add_method(it, it.protos.map_iterator, "next", 0u32, map_iterator_next)
    let e8 = js.define_data(it, it.protos.map_iterator, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Map Iterator"), js.P_CONFIGURABLE)
}

// --- Set

fn set_add(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.add")
    if e != ok { ret (js.undefv(), e) }
    let se = store_set(it, st, arg(args, 0usize), arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    ret (this_val, ok)
}

fn set_has(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.has")
    if e != ok { ret (js.undefv(), e) }
    let (at, found) = find_entry(st, arg(args, 0usize))
    ret (js.bool_value(found), ok)
}

fn set_delete(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.delete")
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(store_delete(st, arg(args, 0usize))), ok)
}

fn set_clear(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.clear")
    if e != ok { ret (js.undefv(), e) }
    store_clear(st)
    ret (js.undefv(), ok)
}

fn set_size(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "get Set.prototype.size")
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(f64(st.live)), ok)
}

fn set_for_each(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.forEach")
    if e != ok { ret (js.undefv(), e) }
    let cb = arg(args, 0usize)
    if !js.is_callable(cb) { ret (js.undefv(), js.throw_type(it, "callback is not a function")) }
    var i = 0usize
    while i < st.entries.len {
        let en = st.entries.items[i]
        i += 1usize
        if !en.live { continue }
        let (r, re) = js.call_function(it, cb, arg(args, 1usize), three(it, en.key, en.key, this_val))
        if re != ok { ret (js.undefv(), re) }
    }
    ret (js.undefv(), ok)
}

fn set_values(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.values")
    if e != ok { ret (js.undefv(), e) }
    ret (make_iterator(it, js.as_object(this_val), 0.0f64, it.protos.set_iterator), ok)
}

fn set_entries(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_SET, "Set.prototype.entries")
    if e != ok { ret (js.undefv(), e) }
    ret (make_iterator(it, js.as_object(this_val), 2.0f64, it.protos.set_iterator), ok)
}

fn install_set(it: *js.Interp) {
    let proto = it.protos.set
    let ctor = js.make_native(it, "Set", 0u32, set_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("Set"), js.obj_value(ctor), js.P_HIDDEN)
    it.last = ctor
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e4 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.set, "add", 1u32, set_add)
    js.add_method(it, it.protos.set, "has", 1u32, set_has)
    js.add_method(it, it.protos.set, "delete", 1u32, set_delete)
    js.add_method(it, it.protos.set, "clear", 0u32, set_clear)
    js.add_method(it, it.protos.set, "forEach", 1u32, set_for_each)
    js.add_method(it, it.protos.set, "entries", 0u32, set_entries)
    js.add_getter(it, it.protos.set, "size", set_size)
    let vals = js.make_native(it, "values", 0u32, set_values)
    let e5 = js.define_data(it, it.protos.set, js.key_of("values"), js.obj_value(vals), js.P_HIDDEN)
    let e6 = js.define_data(it, it.protos.set, js.key_of("keys"), js.obj_value(vals), js.P_HIDDEN)
    let e7 = js.define_data(it, it.protos.set, js.key_of_symbol(it.sym_iterator), js.obj_value(vals), js.P_HIDDEN)
    let e8 = js.define_data(it, it.protos.set, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Set"), js.P_CONFIGURABLE)
    it.protos.set_iterator = js.new_obj(it, js.C_OBJECT, it.protos.iterator)
    js.add_method(it, it.protos.set_iterator, "next", 0u32, set_iterator_next)
    let e9 = js.define_data(it, it.protos.set_iterator, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Set Iterator"), js.P_CONFIGURABLE)
}

// --- WeakMap / WeakSet

fn weak_key_ok(v: js.Value) -> bool {
    if js.is_object(v) { ret true }
    switch v {
    case .Sym as s:
        ret !s.registered
    default:
        ret false
    }
}

fn weakmap_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKMAP, "WeakMap.prototype.get")
    if e != ok { ret (js.undefv(), e) }
    let (at, found) = find_entry(st, arg(args, 0usize))
    if !found { ret (js.undefv(), ok) }
    ret (st.entries.items[at].value, ok)
}

fn weakmap_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKMAP, "WeakMap.prototype.set")
    if e != ok { ret (js.undefv(), e) }
    if !weak_key_ok(arg(args, 0usize)) { ret (js.undefv(), js.throw_type(it, "Invalid value used as weak map key")) }
    let se = store_set(it, st, args[0usize], arg(args, 1usize))
    if se != ok { ret (js.undefv(), se) }
    ret (this_val, ok)
}

fn weakmap_has(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKMAP, "WeakMap.prototype.has")
    if e != ok { ret (js.undefv(), e) }
    let (at, found) = find_entry(st, arg(args, 0usize))
    ret (js.bool_value(found), ok)
}

fn weakmap_delete(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKMAP, "WeakMap.prototype.delete")
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(store_delete(st, arg(args, 0usize))), ok)
}

fn weakset_add(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKSET, "WeakSet.prototype.add")
    if e != ok { ret (js.undefv(), e) }
    if !weak_key_ok(arg(args, 0usize)) { ret (js.undefv(), js.throw_type(it, "Invalid value used in weak set")) }
    let se = store_set(it, st, args[0usize], args[0usize])
    if se != ok { ret (js.undefv(), se) }
    ret (this_val, ok)
}

fn weakset_has(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKSET, "WeakSet.prototype.has")
    if e != ok { ret (js.undefv(), e) }
    let (at, found) = find_entry(st, arg(args, 0usize))
    ret (js.bool_value(found), ok)
}

fn weakset_delete(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (st, e) = this_store(it, this_val, js.C_WEAKSET, "WeakSet.prototype.delete")
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(store_delete(st, arg(args, 0usize))), ok)
}

fn install_weak(it: *js.Interp) {
    it.protos.weakmap = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.weakset = js.new_obj(it, js.C_OBJECT, it.protos.object)
    let wm = js.make_native(it, "WeakMap", 0u32, weakmap_ctor)
    wm.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, wm, js.key_of("prototype"), js.obj_value(it.protos.weakmap), 0u8)
    let e2 = js.define_data(it, it.protos.weakmap, js.key_of("constructor"), js.obj_value(wm), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("WeakMap"), js.obj_value(wm), js.P_HIDDEN)
    js.add_method(it, it.protos.weakmap, "get", 1u32, weakmap_get)
    js.add_method(it, it.protos.weakmap, "set", 2u32, weakmap_set)
    js.add_method(it, it.protos.weakmap, "has", 1u32, weakmap_has)
    js.add_method(it, it.protos.weakmap, "delete", 1u32, weakmap_delete)
    let e4 = js.define_data(it, it.protos.weakmap, js.key_of_symbol(it.sym_to_string_tag), js.str_value("WeakMap"), js.P_CONFIGURABLE)
    let ws = js.make_native(it, "WeakSet", 0u32, weakset_ctor)
    ws.ctor_kind = js.K_BASE
    let e5 = js.define_data(it, ws, js.key_of("prototype"), js.obj_value(it.protos.weakset), 0u8)
    let e6 = js.define_data(it, it.protos.weakset, js.key_of("constructor"), js.obj_value(ws), js.P_HIDDEN)
    let e7 = js.define_data(it, it.global, js.key_of("WeakSet"), js.obj_value(ws), js.P_HIDDEN)
    js.add_method(it, it.protos.weakset, "add", 1u32, weakset_add)
    js.add_method(it, it.protos.weakset, "has", 1u32, weakset_has)
    js.add_method(it, it.protos.weakset, "delete", 1u32, weakset_delete)
    let e8 = js.define_data(it, it.protos.weakset, js.key_of_symbol(it.sym_to_string_tag), js.str_value("WeakSet"), js.P_CONFIGURABLE)
}
