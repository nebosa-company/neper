// Generators, Promise and Reflect (browser tracker 5.4/5.11).

use e.data.list as list
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// --- generator objects

fn iter_result(it: *js.Interp, v: js.Value, done: bool) -> js.Value {
    let r = js.new_plain(it)
    let e1 = js.set_named(it, r, "value", v)
    let e2 = js.set_named(it, r, "done", js.bool_value(done))
    ret js.obj_value(r)
}

fn this_generator(it: *js.Interp, v: js.Value) -> (*js.GenState, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_GENERATOR {
        ret (mem.cast[*js.GenState](js.as_object(v).data), ok)
    }
    var none: *js.GenState = zero
    ret (none, js.throw_type(it, "next method called on incompatible receiver"))
}

fn generator_resume(it: *js.Interp, this_val: js.Value, args: []const js.Value, mode: u8) -> (js.Value, err) {
    let (gs, ge) = this_generator(it, this_val)
    if ge != ok { ret (js.undefv(), ge) }
    let (v, done, e) = js.gen_resume(it, gs, mode, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    if gs.out_raw && !done {
        gs.out_raw = false
        ret (v, ok)
    }
    ret (iter_result(it, v, done), ok)
}

fn generator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = generator_resume(it, this_val, args, js.RM_NEXT)
    ret (r, e) }
fn generator_return(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = generator_resume(it, this_val, args, js.RM_RETURN)
    ret (r, e) }
fn generator_throw(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = generator_resume(it, this_val, args, js.RM_THROW)
    ret (r, e) }

fn async_gen_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = js.ag_enqueue(it, this_val, js.RM_NEXT, arg(args, 0usize))
    ret (r, e) }
fn async_gen_return(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = js.ag_enqueue(it, this_val, js.RM_RETURN, arg(args, 0usize))
    ret (r, e) }
fn async_gen_throw(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = js.ag_enqueue(it, this_val, js.RM_THROW, arg(args, 0usize))
    ret (r, e) }

fn this_self(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn generator_function_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.undefv(), js.throw_syntax(it, "GeneratorFunction constructor is not supported yet"))
}

fn install_generators(it: *js.Interp) {
    // %GeneratorFunction.prototype% and %GeneratorPrototype%.
    it.protos.gen_function = js.new_obj(it, js.C_OBJECT, it.protos.function)
    let gp = it.protos.generator
    let e1 = js.define_data(it, it.protos.gen_function, js.key_of("prototype"), js.obj_value(gp), js.P_CONFIGURABLE)
    let e2 = js.define_data(it, gp, js.key_of("constructor"), js.obj_value(it.protos.gen_function), js.P_CONFIGURABLE)
    let e3 = js.define_data(it, it.protos.gen_function, js.key_of_symbol(it.sym_to_string_tag), js.str_value("GeneratorFunction"), js.P_CONFIGURABLE)
    let e4 = js.define_data(it, gp, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Generator"), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.generator, "next", 1u32, generator_next)
    js.add_method(it, it.protos.generator, "return", 1u32, generator_return)
    js.add_method(it, it.protos.generator, "throw", 1u32, generator_throw)
    // Async generators: %AsyncIteratorPrototype%, %AsyncGeneratorPrototype% and %AsyncGeneratorFunction.prototype%.
    let async_iter = js.new_obj(it, js.C_OBJECT, it.protos.object)
    let ai = js.make_native(it, "[Symbol.asyncIterator]", 0u32, this_self)
    let ea = js.define_data(it, async_iter, js.key_of_symbol(it.sym_async_iterator), js.obj_value(ai), js.P_HIDDEN)
    it.protos.async_generator = js.new_obj(it, js.C_OBJECT, async_iter)
    it.protos.async_gen_function = js.new_obj(it, js.C_OBJECT, it.protos.function)
    let eb = js.define_data(it, it.protos.async_gen_function, js.key_of("prototype"), js.obj_value(it.protos.async_generator), js.P_CONFIGURABLE)
    let ec = js.define_data(it, it.protos.async_generator, js.key_of("constructor"), js.obj_value(it.protos.async_gen_function), js.P_CONFIGURABLE)
    let ed = js.define_data(it, it.protos.async_generator, js.key_of_symbol(it.sym_to_string_tag), js.str_value("AsyncGenerator"), js.P_CONFIGURABLE)
    let ee = js.define_data(it, it.protos.async_gen_function, js.key_of_symbol(it.sym_to_string_tag), js.str_value("AsyncGeneratorFunction"), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.async_generator, "next", 1u32, async_gen_next)
    js.add_method(it, it.protos.async_generator, "return", 1u32, async_gen_return)
    js.add_method(it, it.protos.async_generator, "throw", 1u32, async_gen_throw)
    it.protos.async_function = js.new_obj(it, js.C_OBJECT, it.protos.function)
    let e5 = js.define_data(it, it.protos.async_function, js.key_of_symbol(it.sym_to_string_tag), js.str_value("AsyncFunction"), js.P_CONFIGURABLE)
}

// --- Promise

fn this_promise(it: *js.Interp, v: js.Value) -> (*js.Obj, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_PROMISE { ret (js.as_object(v), ok) }
    ret (js.null_obj(), js.throw_type(it, "Method called on incompatible receiver"))
}

fn promise_ctor_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.undefv(), js.throw_type(it, "Promise constructor cannot be invoked without 'new'")) }
    let executor = arg(args, 0usize)
    if !js.is_callable(executor) { ret (js.undefv(), js.throw_type(it, "Promise resolver is not a function")) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.promise)
    if pe != ok { ret (js.undefv(), pe) }
    let (p, ne) = js.new_promise_with_proto(it, proto)
    if ne != ok { ret (js.undefv(), ne) }
    let (rs, rj, re) = js.create_resolving_functions(it, p)
    if re != ok { ret (js.undefv(), re) }
    let (r, ce) = js.call_function(it, executor, js.undefv(), js.two_args(it, js.obj_value(rs), js.obj_value(rj)))
    if ce != ok {
        if ce != js.Throw { ret (js.undefv(), ce) }
        let (r2, ce2) = js.call_function(it, js.obj_value(rj), js.undefv(), js.one_arg(it, it.thrown))
        if ce2 != ok { ret (js.undefv(), ce2) }
    }
    ret (js.obj_value(p), ok)
}

fn species_constructor(it: *js.Interp, o: *js.Obj, default_ctor: js.Value) -> (js.Value, err) {
    let (c, ce) = js.get_prop(it, o, js.key_of("constructor"), js.obj_value(o))
    if ce != ok { ret (js.undefv(), ce) }
    if js.is_undefined(c) { ret (default_ctor, ok) }
    if !js.is_object(c) { ret (js.undefv(), js.throw_type(it, "constructor is not an object")) }
    let (s, se) = js.get_prop(it, js.as_object(c), js.key_of_symbol(it.sym_species), c)
    if se != ok { ret (js.undefv(), se) }
    if js.is_nullish(s) { ret (default_ctor, ok) }
    if js.is_constructor(s) { ret (s, ok) }
    ret (js.undefv(), js.throw_type(it, "object.constructor[Symbol.species] is not a constructor"))
}

fn promise_then(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (p, pe) = this_promise(it, this_val)
    if pe != ok { ret (js.undefv(), pe) }
    let (c, ce) = species_constructor(it, p, js.obj_value(it.promise_ctor))
    if ce != ok { ret (js.undefv(), ce) }
    let (cap, cape) = js.new_promise_capability(it, c)
    if cape != ok { ret (js.undefv(), cape) }
    js.perform_then(it, p, arg(args, 0usize), arg(args, 1usize), cap, true)
    ret (cap.promise, ok)
}

fn promise_catch(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (th, te) = js.get_value(it, this_val, js.key_of("then"))
    if te != ok { ret (js.undefv(), te) }
    let (r, re) = js.call_function(it, th, this_val, js.two_args(it, js.undefv(), arg(args, 0usize)))
    ret (r, re)
}

fn then_finally_value(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let holder = it.callee.aux
    let (v, ve) = js.get_prop(it, holder, js.key_of("v"), js.obj_value(holder))
    ret (v, ve)
}

fn then_finally_thrower(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let holder = it.callee.aux
    let (v, ve) = js.get_prop(it, holder, js.key_of("v"), js.obj_value(holder))
    if ve != ok { ret (js.undefv(), ve) }
    ret (js.undefv(), js.throw_value(it, v))
}

fn finally_step(it: *js.Interp, this_val: js.Value, args: []const js.Value, rejecting: bool) -> (js.Value, err) {
    let holder = it.callee.aux
    let (onf, oe) = js.get_prop(it, holder, js.key_of("onFinally"), js.obj_value(holder))
    if oe != ok { ret (js.undefv(), oe) }
    let (cv, cve) = js.get_prop(it, holder, js.key_of("C"), js.obj_value(holder))
    if cve != ok { ret (js.undefv(), cve) }
    let (result, re) = js.call_function(it, onf, js.undefv(), js.zero_args())
    if re != ok { ret (js.undefv(), re) }
    let (cap, cape) = js.new_promise_capability(it, cv)
    if cape != ok { ret (js.undefv(), cape) }
    let (rr0, rre0) = js.call_function(it, cap.resolve, js.undefv(), js.one_arg(it, result))
    let (rp, rpe) = js.get_value(it, cap.promise, js.key_of("then"))
    if rpe != ok { ret (js.undefv(), rpe) }
    let vh = js.new_plain(it)
    let e1 = js.set_named(it, vh, "v", arg(args, 0usize))
    var fn_obj = js.make_native(it, "", 0u32, then_finally_value)
    if rejecting { fn_obj = js.make_native(it, "", 0u32, then_finally_thrower) }
    fn_obj.aux = vh
    let (r2, re2) = js.call_function(it, rp, cap.promise, js.one_arg(it, js.obj_value(fn_obj)))
    ret (r2, re2)
}

fn then_finally_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = finally_step(it, this_val, args, false)
    ret (r, e) }
fn catch_finally_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = finally_step(it, this_val, args, true)
    ret (r, e) }

fn promise_finally(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "Promise.prototype.finally called on a non-object")) }
    let po = js.as_object(this_val)
    let (c, ce) = species_constructor(it, po, js.obj_value(it.promise_ctor))
    if ce != ok { ret (js.undefv(), ce) }
    let onf = arg(args, 0usize)
    var a0 = onf
    var a1 = onf
    if js.is_callable(onf) {
        let holder = js.new_plain(it)
        let e1 = js.set_named(it, holder, "onFinally", onf)
        let e2 = js.set_named(it, holder, "C", c)
        let tf = js.make_native(it, "", 1u32, then_finally_fn)
        tf.aux = holder
        let cf = js.make_native(it, "", 1u32, catch_finally_fn)
        cf.aux = holder
        a0 = js.obj_value(tf)
        a1 = js.obj_value(cf)
    }
    let (th, te) = js.get_value(it, this_val, js.key_of("then"))
    if te != ok { ret (js.undefv(), te) }
    let (r, re) = js.call_function(it, th, this_val, js.two_args(it, a0, a1))
    ret (r, re)
}

fn promise_resolve_static(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "Promise.resolve called on a non-object")) }
    let v = arg(args, 0usize)
    if js.is_object(v) && js.as_object(v).class == js.C_PROMISE {
        let (c, ce) = js.get_prop(it, js.as_object(v), js.key_of("constructor"), v)
        if ce != ok { ret (js.undefv(), ce) }
        if js.strict_equals(c, this_val) { ret (v, ok) }
    }
    let (cap, cape) = js.new_promise_capability(it, this_val)
    if cape != ok { ret (js.undefv(), cape) }
    let (r, re) = js.call_function(it, cap.resolve, js.undefv(), js.one_arg(it, v))
    if re != ok { ret (js.undefv(), re) }
    ret (cap.promise, ok)
}

fn promise_reject_static(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "Promise.reject called on a non-object")) }
    let (cap, cape) = js.new_promise_capability(it, this_val)
    if cape != ok { ret (js.undefv(), cape) }
    let (r, re) = js.call_function(it, cap.reject, js.undefv(), js.one_arg(it, arg(args, 0usize)))
    if re != ok { ret (js.undefv(), re) }
    ret (cap.promise, ok)
}

fn promise_with_resolvers(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (cap, cape) = js.new_promise_capability(it, this_val)
    if cape != ok { ret (js.undefv(), cape) }
    let o = js.new_plain(it)
    let e1 = js.set_named(it, o, "promise", cap.promise)
    let e2 = js.set_named(it, o, "resolve", cap.resolve)
    let e3 = js.set_named(it, o, "reject", cap.reject)
    ret (js.obj_value(o), ok)
}

// Combinators share one element-collecting scheme: each element gets a function holding (state, index).
type Agg = struct { values: *js.Obj, remaining: f64, resolve: js.Value, reject: js.Value, done: bool }

fn agg_of(o: *js.Obj) -> *Agg { ret mem.cast[*Agg](o.data) }

fn aggregate_element(it: *js.Interp, this_val: js.Value, args: []const js.Value, kind: u8) -> (js.Value, err) {
    let fo = it.callee
    if fo.num < 0.0f64 { ret (js.undefv(), ok) }
    let idx = fo.num
    fo.num = -1.0f64
    let ag = agg_of(fo.aux)
    var v = arg(args, 0usize)
    if kind == 1u8 {
        let o = js.new_plain(it)
        let e1 = js.set_named(it, o, "status", js.str_value("fulfilled"))
        let e2 = js.set_named(it, o, "value", v)
        v = js.obj_value(o)
    } else if kind == 2u8 {
        let o2 = js.new_plain(it)
        let e3 = js.set_named(it, o2, "status", js.str_value("rejected"))
        let e4 = js.set_named(it, o2, "reason", v)
        v = js.obj_value(o2)
    }
    let (done, de) = js.define_own(it, ag.values, js.key_of(js.number_to_string(it.a, idx)), js.data_desc(v, js.P_DEFAULT))
    if de != ok { ret (js.undefv(), de) }
    ag.remaining -= 1.0f64
    if ag.remaining == 0.0f64 {
        if kind == 3u8 {
            // any: every promise rejected -> AggregateError.
            let err_obj = js.make_error(it, it.protos.error_proto, "All promises were rejected")
            let e5 = js.define_data(it, js.as_object(err_obj), js.key_of("errors"), js.obj_value(ag.values), js.P_HIDDEN)
            let (r, re) = js.call_function(it, ag.reject, js.undefv(), js.one_arg(it, err_obj))
            if re != ok { ret (js.undefv(), re) }
        } else {
            let (r2, re2) = js.call_function(it, ag.resolve, js.undefv(), js.one_arg(it, js.obj_value(ag.values)))
            if re2 != ok { ret (js.undefv(), re2) }
        }
    }
    ret (js.undefv(), ok)
}

fn agg_fulfilled(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = aggregate_element(it, this_val, args, 0u8)
    ret (r, e) }
fn agg_settled_ok(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = aggregate_element(it, this_val, args, 1u8)
    ret (r, e) }
fn agg_settled_err(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = aggregate_element(it, this_val, args, 2u8)
    ret (r, e) }
fn agg_rejected(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = aggregate_element(it, this_val, args, 3u8)
    ret (r, e) }

// kind: 0 all, 1 allSettled, 2 any, 3 race.
fn combinator(it: *js.Interp, this_val: js.Value, args: []const js.Value, kind: u8) -> (js.Value, err) {
    let (cap, cape) = js.new_promise_capability(it, this_val)
    if cape != ok { ret (js.undefv(), cape) }
    // Errors from here on reject the capability's promise.
    let (resolve_fn, rfe) = js.get_value(it, this_val, js.key_of("resolve"))
    if rfe != ok {
        if rfe == js.Throw {
            let (r0, re0) = js.call_function(it, cap.reject, js.undefv(), js.one_arg(it, it.thrown))
            ret (cap.promise, re0)
        }
        ret (js.undefv(), rfe)
    }
    if !js.is_callable(resolve_fn) {
        let (r1, re1) = js.call_function(it, cap.reject, js.undefv(), js.one_arg(it, js.make_error(it, it.protos.type_error, "Promise resolve is not callable")))
        ret (cap.promise, re1)
    }
    let (iter, ie) = js.get_iterator(it, arg(args, 0usize))
    if ie != ok {
        if ie == js.Throw {
            let (r2, re2) = js.call_function(it, cap.reject, js.undefv(), js.one_arg(it, it.thrown))
            ret (cap.promise, re2)
        }
        ret (js.undefv(), ie)
    }
    let (cell, ce) = mem.alloc[Agg](it.a, 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    cell[0usize] = Agg { values: js.new_array(it), remaining: 1.0f64, resolve: cap.resolve, reject: cap.reject, done: false }
    let holder = js.new_plain(it)
    holder.data = mem.cast[*void](&cell[0usize])
    var index = 0.0f64
    var failure = false
    var failed_err: err = ok
    while true {
        let (nv, done, se) = js.iterator_step(it, iter)
        if se != ok {
            failure = true
            failed_err = se
            break
        }
        if done { break }
        let (np, npe) = js.call_function(it, resolve_fn, this_val, js.one_arg(it, nv))
        if npe != ok {
            failure = true
            failed_err = npe
            let cl = js.iterator_close(it, iter)
            break
        }
        var on_ful = js.undefv()
        var on_rej = js.undefv()
        if kind == 3u8 {
            on_ful = cap.resolve
            on_rej = cap.reject
        } else {
            cell[0usize].remaining += 1.0f64
            let ff = js.make_native(it, "", 1u32, agg_fulfilled)
            let rf = js.make_native(it, "", 1u32, agg_rejected)
            if kind == 0u8 {
                ff.aux = holder
                ff.num = index
                on_ful = js.obj_value(ff)
                on_rej = cap.reject
            } else if kind == 1u8 {
                let ok1 = js.make_native(it, "", 1u32, agg_settled_ok)
                let er1 = js.make_native(it, "", 1u32, agg_settled_err)
                ok1.aux = holder
                ok1.num = index
                er1.aux = holder
                er1.num = index
                // Both functions share one `already called` flag through paired indices.
                on_ful = js.obj_value(ok1)
                on_rej = js.obj_value(er1)
            } else {
                rf.aux = holder
                rf.num = index
                on_ful = cap.resolve
                on_rej = js.obj_value(rf)
            }
        }
        let (tv, te) = js.get_value(it, np, js.key_of("then"))
        if te != ok {
            failure = true
            failed_err = te
            break
        }
        let (tr, tre) = js.call_function(it, tv, np, js.two_args(it, on_ful, on_rej))
        if tre != ok {
            failure = true
            failed_err = tre
            let cl2 = js.iterator_close(it, iter)
            break
        }
        index += 1.0f64
    }
    if failure {
        if failed_err == js.Throw {
            let (r3, re3) = js.call_function(it, cap.reject, js.undefv(), js.one_arg(it, it.thrown))
            if re3 != ok { ret (js.undefv(), re3) }
            ret (cap.promise, ok)
        }
        ret (js.undefv(), failed_err)
    }
    if kind != 3u8 {
        cell[0usize].remaining -= 1.0f64
        if cell[0usize].remaining == 0.0f64 {
            if kind == 2u8 {
                let err_obj = js.make_error(it, it.protos.error_proto, "All promises were rejected")
                let e5 = js.define_data(it, js.as_object(err_obj), js.key_of("errors"), js.obj_value(cell[0usize].values), js.P_HIDDEN)
                let (r4, re4) = js.call_function(it, cap.reject, js.undefv(), js.one_arg(it, err_obj))
                if re4 != ok { ret (js.undefv(), re4) }
            } else {
                let (r5, re5) = js.call_function(it, cap.resolve, js.undefv(), js.one_arg(it, js.obj_value(cell[0usize].values)))
                if re5 != ok { ret (js.undefv(), re5) }
            }
        }
    }
    ret (cap.promise, ok)
}

fn promise_all(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = combinator(it, this_val, args, 0u8)
    ret (r, e) }
fn promise_all_settled(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = combinator(it, this_val, args, 1u8)
    ret (r, e) }
fn promise_any(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = combinator(it, this_val, args, 2u8)
    ret (r, e) }
fn promise_race(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = combinator(it, this_val, args, 3u8)
    ret (r, e) }

fn species_self(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn install_promise(it: *js.Interp) {
    let proto = it.protos.promise
    let ctor = js.make_native(it, "Promise", 1u32, promise_ctor_fn)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("Promise"), js.obj_value(ctor), js.P_HIDDEN)
    it.promise_ctor = ctor
    it.last = ctor
    js.add_method(it, it.last, "resolve", 1u32, promise_resolve_static)
    js.add_method(it, it.last, "reject", 1u32, promise_reject_static)
    js.add_method(it, it.last, "all", 1u32, promise_all)
    js.add_method(it, it.last, "allSettled", 1u32, promise_all_settled)
    js.add_method(it, it.last, "any", 1u32, promise_any)
    js.add_method(it, it.last, "race", 1u32, promise_race)
    js.add_method(it, it.last, "withResolvers", 0u32, promise_with_resolvers)
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e4 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.promise, "then", 2u32, promise_then)
    js.add_method(it, it.protos.promise, "catch", 1u32, promise_catch)
    js.add_method(it, it.protos.promise, "finally", 1u32, promise_finally)
    let e5 = js.define_data(it, it.protos.promise, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Promise"), js.P_CONFIGURABLE)
}

// --- Reflect

fn reflect_apply(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_callable(arg(args, 0usize)) { ret (js.undefv(), js.throw_type(it, "Reflect.apply tgt is not callable")) }
    let (list_args, le) = array_like(it, arg(args, 2usize))
    if le != ok { ret (js.undefv(), le) }
    let (r, re) = js.call_function(it, args[0usize], arg(args, 1usize), list_args)
    ret (r, re)
}

fn array_like(it: *js.Interp, v: js.Value) -> ([]const js.Value, err) {
    if !js.is_object(v) { ret (js.zero_args(), js.throw_type(it, "CreateListFromArrayLike called on non-object")) }
    let o = js.as_object(v)
    let (len, le) = js.length_of(it, o)
    if le != ok { ret (js.zero_args(), le) }
    let (l, lie) = list.init[js.Value](it.a, usize(len) + 1usize)
    var out = l
    if lie != ok { ret (js.zero_args(), lie) }
    var i = 0.0f64
    while i < len {
        let (e, ee) = js.get_index(it, o, i)
        if ee != ok { ret (js.zero_args(), ee) }
        try list.push[js.Value](&out, e)
        i += 1.0f64
    }
    ret (list.slice_const[js.Value](&out), ok)
}

fn reflect_construct(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let tgt = arg(args, 0usize)
    if !js.is_constructor(tgt) { ret (js.undefv(), js.throw_type(it, "Reflect.construct tgt is not a constructor")) }
    var nt = tgt
    if args.len > 2usize {
        nt = args[2usize]
        if !js.is_constructor(nt) { ret (js.undefv(), js.throw_type(it, "Reflect.construct newTarget is not a constructor")) }
    }
    let (list_args, le) = array_like(it, arg(args, 1usize))
    if le != ok { ret (js.undefv(), le) }
    let (r, re) = js.construct(it, tgt, list_args, nt)
    ret (r, re)
}

fn reflect_target(it: *js.Interp, args: []const js.Value) -> (*js.Obj, err) {
    let t = arg(args, 0usize)
    if !js.is_object(t) { ret (js.null_obj(), js.throw_type(it, "Reflect method called on non-object")) }
    ret (js.as_object(t), ok)
}

fn reflect_define_property(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (d, de) = to_desc(it, arg(args, 2usize))
    if de != ok { ret (js.undefv(), de) }
    let (done, e) = js.define_own(it, o, k, d)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(done), ok)
}

fn to_desc(it: *js.Interp, v: js.Value) -> (js.Desc, err) {
    var d = js.empty_desc()
    if !js.is_object(v) { ret (d, js.throw_type(it, "Property description must be an object")) }
    let o = js.as_object(v)
    if js.has_property(it, o, js.key_of("enumerable")) {
        let (x, xe) = js.get_prop(it, o, js.key_of("enumerable"), v)
        if xe != ok { ret (d, xe) }
        d.has_enumerable = true
        d.enumerable = js.to_boolean(x)
    }
    if js.has_property(it, o, js.key_of("configurable")) {
        let (x2, xe2) = js.get_prop(it, o, js.key_of("configurable"), v)
        if xe2 != ok { ret (d, xe2) }
        d.has_configurable = true
        d.configurable = js.to_boolean(x2)
    }
    if js.has_property(it, o, js.key_of("value")) {
        let (x3, xe3) = js.get_prop(it, o, js.key_of("value"), v)
        if xe3 != ok { ret (d, xe3) }
        d.has_value = true
        d.value = x3
    }
    if js.has_property(it, o, js.key_of("writable")) {
        let (x4, xe4) = js.get_prop(it, o, js.key_of("writable"), v)
        if xe4 != ok { ret (d, xe4) }
        d.has_writable = true
        d.writable = js.to_boolean(x4)
    }
    if js.has_property(it, o, js.key_of("get")) {
        let (x5, xe5) = js.get_prop(it, o, js.key_of("get"), v)
        if xe5 != ok { ret (d, xe5) }
        if !js.is_undefined(x5) && !js.is_callable(x5) { ret (d, js.throw_type(it, "Getter must be a function")) }
        d.has_get = true
        d.getter = x5
    }
    if js.has_property(it, o, js.key_of("set")) {
        let (x6, xe6) = js.get_prop(it, o, js.key_of("set"), v)
        if xe6 != ok { ret (d, xe6) }
        if !js.is_undefined(x6) && !js.is_callable(x6) { ret (d, js.throw_type(it, "Setter must be a function")) }
        d.has_set = true
        d.setter = x6
    }
    ret (d, ok)
}

fn reflect_delete_property(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (done, de) = js.delete_prop_e(it, o, k)
    if de != ok { ret (js.undefv(), de) }
    ret (js.bool_value(done), ok)
}

fn reflect_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    var receiver = js.obj_value(o)
    if args.len > 2usize { receiver = args[2usize] }
    let (v, ve) = js.get_prop(it, o, k, receiver)
    ret (v, ve)
}

fn reflect_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    var receiver = js.obj_value(o)
    if args.len > 3usize { receiver = args[3usize] }
    let (done, se) = js.set_prop(it, o, k, arg(args, 2usize), receiver)
    if se != ok { ret (js.undefv(), se) }
    ret (js.bool_value(done), ok)
}

fn reflect_get_own_property_descriptor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (p, found, ge) = js.get_own_e(it, o, k)
    if ge != ok { ret (js.undefv(), ge) }
    if !found { ret (js.undefv(), ok) }
    let d = js.prop_to_desc(p)
    let out = js.new_plain(it)
    if d.has_value { let e1 = js.set_named(it, out, "value", d.value) }
    if d.has_writable { let e2 = js.set_named(it, out, "writable", js.bool_value(d.writable)) }
    if d.has_get { let e3 = js.set_named(it, out, "get", d.getter) }
    if d.has_set { let e4 = js.set_named(it, out, "set", d.setter) }
    let e5 = js.set_named(it, out, "enumerable", js.bool_value(d.enumerable))
    let e6 = js.set_named(it, out, "configurable", js.bool_value(d.configurable))
    ret (js.obj_value(out), ok)
}

fn reflect_get_prototype_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (pv, pe) = js.proto_get(it, o)
    ret (pv, pe)
}

fn reflect_set_prototype_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let p = arg(args, 1usize)
    if !js.is_object(p) && !js.is_null(p) { ret (js.undefv(), js.throw_type(it, "Object prototype may only be an Object or null")) }
    let (done, de) = js.proto_set(it, o, p)
    if de != ok { ret (js.undefv(), de) }
    ret (js.bool_value(done), ok)
}

fn reflect_has(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (k, ke) = js.to_property_key(it, arg(args, 1usize))
    if ke != ok { ret (js.undefv(), ke) }
    let (has, he) = js.has_property_e(it, o, k)
    if he != ok { ret (js.undefv(), he) }
    ret (js.bool_value(has), ok)
}

fn reflect_is_extensible(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (ext, xe) = js.is_extensible(it, o)
    if xe != ok { ret (js.undefv(), xe) }
    ret (js.bool_value(ext), ok)
}

fn reflect_prevent_extensions(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (done, pe) = js.prevent_extensions(it, o)
    if pe != ok { ret (js.undefv(), pe) }
    ret (js.bool_value(done), ok)
}

fn reflect_own_keys(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = reflect_target(it, args)
    if oe != ok { ret (js.undefv(), oe) }
    let (keys, ke) = js.own_keys(it, o)
    if ke != ok { ret (js.undefv(), ke) }
    let out = js.new_array(it)
    var i = 0usize
    while i < keys.len {
        try js.array_push(it, out, js.key_to_value(keys[i]))
        i += 1usize
    }
    ret (js.obj_value(out), ok)
}

fn install_reflect(it: *js.Interp) {
    let r = js.new_plain(it)
    let e0 = js.define_data(it, it.global, js.key_of("Reflect"), js.obj_value(r), js.P_HIDDEN)
    let e1 = js.define_data(it, r, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Reflect"), js.P_CONFIGURABLE)
    it.last = r
    js.add_method(it, it.last, "apply", 3u32, reflect_apply)
    js.add_method(it, it.last, "construct", 2u32, reflect_construct)
    js.add_method(it, it.last, "defineProperty", 3u32, reflect_define_property)
    js.add_method(it, it.last, "deleteProperty", 2u32, reflect_delete_property)
    js.add_method(it, it.last, "get", 2u32, reflect_get)
    js.add_method(it, it.last, "set", 3u32, reflect_set)
    js.add_method(it, it.last, "getOwnPropertyDescriptor", 2u32, reflect_get_own_property_descriptor)
    js.add_method(it, it.last, "getPrototypeOf", 1u32, reflect_get_prototype_of)
    js.add_method(it, it.last, "setPrototypeOf", 2u32, reflect_set_prototype_of)
    js.add_method(it, it.last, "has", 2u32, reflect_has)
    js.add_method(it, it.last, "isExtensible", 1u32, reflect_is_extensible)
    js.add_method(it, it.last, "preventExtensions", 1u32, reflect_prevent_extensions)
    js.add_method(it, it.last, "ownKeys", 1u32, reflect_own_keys)
}
