// BigInt (browser tracker 5.8): the BigInt function, asIntN / asUintN and the prototype.

use e.js.bigint as bigint
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

fn this_bigint(it: *js.Interp, v: js.Value, method: str) -> (bigint.Big, err) {
    switch v {
    case .Big as b:
        ret (b, ok)
    case .Obj as o:
        if o.class == js.C_BIGINT { ret (js.big_of(o.prim), ok) }
    default:
        ret (bigint.zero_big(), js.throw_type(it, js.str_concat3(it, "BigInt.prototype.", method, " requires that 'this' be a BigInt")))
    }
    ret (bigint.zero_big(), js.throw_type(it, js.str_concat3(it, "BigInt.prototype.", method, " requires that 'this' be a BigInt")))
}

fn bigint_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if it.has_new_target { ret (js.undefv(), js.throw_type(it, "BigInt is not a constructor")) }
    let (p, pe) = js.to_primitive(it, arg(args, 0usize), "number")
    if pe != ok { ret (js.undefv(), pe) }
    if js.is_number(p) {
        let (b, e) = js.number_to_bigint(it, js.num_of(p))
        if e != ok { ret (js.undefv(), e) }
        ret (js.big_value(b), ok)
    }
    let (b2, e2) = js.to_bigint(it, p)
    if e2 != ok { ret (js.undefv(), e2) }
    ret (js.big_value(b2), ok)
}

fn to_index(it: *js.Interp, v: js.Value) -> (u64, err) {
    if js.is_undefined(v) { ret (0u64, ok) }
    let (n, e) = js.to_number(it, v)
    if e != ok { ret (0u64, e) }
    var i = 0.0f64
    if n == n { i = js.to_integer(n) }
    if i < 0.0f64 || i > 9007199254740991.0f64 { ret (0u64, js.throw_range(it, "Invalid value: not (convertible to) a safe integer")) }
    ret (u64(i), ok)
}

fn as_int_n(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (bits, be) = to_index(it, arg(args, 0usize))
    if be != ok { ret (js.undefv(), be) }
    let (x, xe) = js.to_bigint(it, arg(args, 1usize))
    if xe != ok { ret (js.undefv(), xe) }
    let (r, re) = bigint.as_int_n(it.a, bits, x)
    if re != ok { ret (js.undefv(), js.big_error(it, re)) }
    ret (js.big_value(r), ok)
}

fn as_uint_n(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (bits, be) = to_index(it, arg(args, 0usize))
    if be != ok { ret (js.undefv(), be) }
    let (x, xe) = js.to_bigint(it, arg(args, 1usize))
    if xe != ok { ret (js.undefv(), xe) }
    let (r, re) = bigint.as_uint_n(it.a, bits, x)
    if re != ok { ret (js.undefv(), js.big_error(it, re)) }
    ret (js.big_value(r), ok)
}

fn proto_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, e) = this_bigint(it, this_val, "toString")
    if e != ok { ret (js.undefv(), e) }
    var radix = 10u32
    let rv = arg(args, 0usize)
    if !js.is_undefined(rv) {
        let (rn, re) = js.to_number(it, rv)
        if re != ok { ret (js.undefv(), re) }
        var ri = 0.0f64
        if rn == rn { ri = js.to_integer(rn) }
        if ri < 2.0f64 || ri > 36.0f64 { ret (js.undefv(), js.throw_range(it, "toString() radix must be between 2 and 36")) }
        radix = u32(ri)
    }
    let (s, se) = bigint.to_string(it.a, b, radix)
    if se != ok { ret (js.undefv(), js.big_error(it, se)) }
    ret (js.str_value(s), ok)
}

fn proto_value_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, e) = this_bigint(it, this_val, "valueOf")
    if e != ok { ret (js.undefv(), e) }
    ret (js.big_value(b), ok)
}

fn proto_to_locale_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, e) = this_bigint(it, this_val, "toLocaleString")
    if e != ok { ret (js.undefv(), e) }
    let (s, se) = bigint.to_string(it.a, b, 10u32)
    if se != ok { ret (js.undefv(), js.big_error(it, se)) }
    ret (js.str_value(s), ok)
}

fn install_bigint(it: *js.Interp) {
    let proto = js.new_obj(it, js.C_OBJECT, it.protos.object)
    it.protos.bigint = proto
    let ctor = js.make_native(it, "BigInt", 1u32, bigint_ctor)
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("BigInt"), js.obj_value(ctor), js.P_HIDDEN)
    js.add_method(it, ctor, "asIntN", 2u32, as_int_n)
    js.add_method(it, ctor, "asUintN", 2u32, as_uint_n)
    js.add_method(it, proto, "toString", 0u32, proto_to_string)
    js.add_method(it, proto, "valueOf", 0u32, proto_value_of)
    js.add_method(it, proto, "toLocaleString", 0u32, proto_to_locale_string)
    let e4 = js.define_data(it, proto, js.key_of_symbol(it.sym_to_string_tag), js.str_value("BigInt"), js.P_CONFIGURABLE)
}
