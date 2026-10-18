// Atomics (browser tracker 5.8): operations on integer typed arrays. Realms run one thread of script here, so every operation is
// trivially atomic; `wait` answers without blocking and `notify` wakes nobody.

use e.js.bigint as bigint
use e.js.interp as js
use e.mem
use e.str
use e.sync
use e.time

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

const ALL_ONES: u64 = 18446744073709551615u64

fn low32(x: u64) -> u64 { ret x & 4294967295u64 }

// Wrapping 64-bit addition without relying on overflow behaviour.
fn wadd(a: u64, b: u64) -> u64 {
    let lo = low32(a) + low32(b)
    let hi = low32((a >> 32u64) + (b >> 32u64) + (lo >> 32u64))
    ret (hi << 32u64) | low32(lo)
}

fn wsub(a: u64, b: u64) -> u64 {
    let negb = wadd(b ^ ALL_ONES, 1u64)
    ret wadd(a, negb)
}

// ValidateIntegerTypedArray: a typed array of an integer kind (and an Int32 / BigInt64 one when `waitable`).
fn validate_integer(it: *js.Interp, v: js.Value, waitable: bool) -> (*js.Obj, err) {
    if !js.is_object(v) || js.as_object(v).class != js.C_TYPEDARRAY { ret (js.null_obj(), js.throw_type(it, "Atomics operation requires an integer typed array")) }
    let o = js.as_object(v)
    let kind = js.ta_of(o).kind
    if waitable {
        if kind != 6u8 && kind != 10u8 { ret (js.null_obj(), js.throw_type(it, "Atomics.wait requires an Int32Array or a BigInt64Array")) }
    } else {
        if kind == 3u8 || kind == 8u8 || kind == 9u8 || kind == 12u8 { ret (js.null_obj(), js.throw_type(it, "Atomics operation requires an integer typed array")) }
    }
    if js.ta_out_of_bounds(o) { ret (js.null_obj(), js.throw_type(it, "typed array is detached or out of bounds")) }
    ret (o, ok)
}

// ValidateAtomicAccess: ToIndex(requestIndex) within the array.
fn validate_access(it: *js.Interp, o: *js.Obj, req: js.Value) -> (usize, err) {
    var idx = 0.0f64
    let len = js.ta_length(o)
    if !js.is_undefined(req) {
        let (n, ne) = js.to_number(it, req)
        if ne != ok { ret (0usize, ne) }
        idx = js.to_integer(n)
        if idx < 0.0f64 || idx > 9007199254740991.0f64 { ret (0usize, js.throw_range(it, "Invalid atomic access index")) }
    }
    if idx >= f64(len) { ret (0usize, js.throw_range(it, "Invalid atomic access index")) }
    ret (usize(idx), ok)
}

// The value to store: a BigInt for the BigInt kinds, else an integer-valued number.
fn coerce_value(it: *js.Interp, kind: u8, v: js.Value) -> (js.Value, err) {
    if js.is_big_kind(kind) {
        let (b, be) = js.to_bigint(it, v)
        if be != ok { ret (js.undefv(), be) }
        ret (js.big_value(b), ok)
    }
    let (n, ne) = js.to_number(it, v)
    if ne != ok { ret (js.undefv(), ne) }
    var i = js.to_integer(n)
    if i != i { i = 0.0f64 }
    if i == 0.0f64 { i = 0.0f64 }
    ret (js.num_value(i), ok)
}

// Read-modify-write operations take the hub lock once agents exist, so concurrent agents never lose an update.
fn rmw_lock(it: *js.Interp) {
    let (h, has) = js.hub_peek(it)
    if has { sync.mutex_lock(&h.lock) }
}

fn rmw_unlock(it: *js.Interp) {
    let (h, has) = js.hub_peek(it)
    if has { sync.mutex_unlock(&h.lock) }
}

fn read_raw(it: *js.Interp, o: *js.Obj, idx: usize) -> u64 {
    let v = js.ta_get_index(it, o, idx)
    ret js.ta_raw_of_typed(js.ta_of(o).kind, v)
}

// op: 0 add, 1 and, 2 exchange, 3 or, 4 sub, 5 xor
fn rmw(it: *js.Interp, args: []const js.Value, op: u8) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), false)
    if oe != ok { ret (js.undefv(), oe) }
    if js.ta_immutable(o) { ret (js.undefv(), js.throw_type(it, "The typed array is backed by an immutable ArrayBuffer")) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    let kind = js.ta_of(o).kind
    let (cv, ce) = coerce_value(it, kind, arg(args, 2usize))
    if ce != ok { ret (js.undefv(), ce) }
    if js.ta_out_of_bounds(o) { ret (js.undefv(), js.throw_type(it, "typed array is detached or out of bounds")) }
    if idx >= js.ta_length(o) { ret (js.undefv(), js.throw_range(it, "Invalid atomic access index")) }
    let (raw, re) = js.ta_raw_of(it, kind, cv)
    if re != ok { ret (js.undefv(), re) }
    rmw_lock(it)
    let old = js.ta_get_index(it, o, idx)
    let oldraw = js.ta_raw_of_typed(kind, old)
    var next = raw
    if op == 0u8 {
        next = wadd(oldraw, raw)
    } else if op == 1u8 {
        next = oldraw & raw
    } else if op == 3u8 {
        next = oldraw | raw
    } else if op == 4u8 {
        next = wsub(oldraw, raw)
    } else if op == 5u8 {
        next = oldraw ^ raw
    }
    js.ta_set_raw(it, o, idx, next)
    rmw_unlock(it)
    ret (old, ok)
}

fn at_add(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = rmw(it, args, 0u8)
    ret (r, e) }
fn at_and(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = rmw(it, args, 1u8)
    ret (r, e) }
fn at_exchange(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = rmw(it, args, 2u8)
    ret (r, e) }
fn at_or(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = rmw(it, args, 3u8)
    ret (r, e) }
fn at_sub(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = rmw(it, args, 4u8)
    ret (r, e) }
fn at_xor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = rmw(it, args, 5u8)
    ret (r, e) }

fn at_load(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), false)
    if oe != ok { ret (js.undefv(), oe) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    if js.ta_out_of_bounds(o) { ret (js.undefv(), js.throw_type(it, "typed array is detached or out of bounds")) }
    if idx >= js.ta_length(o) { ret (js.undefv(), js.throw_range(it, "Invalid atomic access index")) }
    ret (js.ta_get_index(it, o, idx), ok)
}

fn at_store(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), false)
    if oe != ok { ret (js.undefv(), oe) }
    if js.ta_immutable(o) { ret (js.undefv(), js.throw_type(it, "The typed array is backed by an immutable ArrayBuffer")) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    let kind = js.ta_of(o).kind
    let (cv, ce) = coerce_value(it, kind, arg(args, 2usize))
    if ce != ok { ret (js.undefv(), ce) }
    if js.ta_out_of_bounds(o) { ret (js.undefv(), js.throw_type(it, "typed array is detached or out of bounds")) }
    if idx >= js.ta_length(o) { ret (js.undefv(), js.throw_range(it, "Invalid atomic access index")) }
    let (raw, re) = js.ta_raw_of(it, kind, cv)
    if re != ok { ret (js.undefv(), re) }
    js.ta_set_raw(it, o, idx, raw)
    ret (cv, ok)
}

fn at_compare_exchange(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), false)
    if oe != ok { ret (js.undefv(), oe) }
    if js.ta_immutable(o) { ret (js.undefv(), js.throw_type(it, "The typed array is backed by an immutable ArrayBuffer")) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    let kind = js.ta_of(o).kind
    let (expected, ee) = coerce_value(it, kind, arg(args, 2usize))
    if ee != ok { ret (js.undefv(), ee) }
    let (replacement, re) = coerce_value(it, kind, arg(args, 3usize))
    if re != ok { ret (js.undefv(), re) }
    if js.ta_out_of_bounds(o) { ret (js.undefv(), js.throw_type(it, "typed array is detached or out of bounds")) }
    if idx >= js.ta_length(o) { ret (js.undefv(), js.throw_range(it, "Invalid atomic access index")) }
    let (eraw, ere) = js.ta_raw_of(it, kind, expected)
    if ere != ok { ret (js.undefv(), ere) }
    let (rraw, rre) = js.ta_raw_of(it, kind, replacement)
    if rre != ok { ret (js.undefv(), rre) }
    rmw_lock(it)
    let old = js.ta_get_index(it, o, idx)
    let oldraw = js.ta_raw_of_typed(kind, old)
    // Compare as stored elements (wrapped to the element size).
    let size = js.ta_elem_size(kind)
    var mask = ALL_ONES
    if size < 8usize { mask = (1u64 << u64(size * 8usize)) - 1u64 }
    if (oldraw & mask) == (eraw & mask) { js.ta_set_raw(it, o, idx, rraw) }
    rmw_unlock(it)
    ret (old, ok)
}

fn at_is_lock_free(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let i = js.to_integer(n)
    ret (js.bool_value(i == 1.0f64 || i == 2.0f64 || i == 4.0f64 || i == 8.0f64), ok)
}

fn at_notify(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), true)
    if oe != ok { ret (js.undefv(), oe) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    let t = js.ta_of(o)
    var count = js.infinity()
    if !js.is_undefined(arg(args, 2usize)) {
        let (n, ne) = js.to_number(it, arg(args, 2usize))
        if ne != ok { ret (js.undefv(), ne) }
        count = js.to_integer(n)
        if js.is_nan(count) { count = 0.0f64 }
        if count < 0.0f64 { count = 0.0f64 }
    }
    if !js.buf_of(t.buffer).is_shared { ret (js.num_value(0.0f64), ok) }
    let (h, has) = js.hub_peek(it)
    if !has { ret (js.num_value(0.0f64), ok) }
    let byte = t.offset + idx * js.ta_elem_size(js.ta_of(o).kind)
    var woken = 0.0f64
    sync.mutex_lock(&h.lock)
    while woken < count {
        var best = 64usize
        var s = 0usize
        while s < 64usize {
            let w = h.waiters[s]
            if w.used && !w.notified && w.buf == t.buffer && w.byte == byte && (best == 64usize || w.seq < h.waiters[best].seq) { best = s }
            s += 1usize
        }
        if best == 64usize { break }
        h.waiters[best].notified = true
        woken += 1.0f64
    }
    sync.condition_broadcast(&h.cond)
    sync.mutex_unlock(&h.lock)
    ret (js.num_value(woken), ok)
}

fn at_wait(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), true)
    if oe != ok { ret (js.undefv(), oe) }
    if !js.buf_of(js.ta_of(o).buffer).is_shared { ret (js.undefv(), js.throw_type(it, "Atomics.wait requires a shared typed array")) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    let kind = js.ta_of(o).kind
    let (cv, ce) = coerce_value(it, kind, arg(args, 2usize))
    if ce != ok { ret (js.undefv(), ce) }
    let (tn, te) = js.to_number(it, arg(args, 3usize))
    if te != ok { ret (js.undefv(), te) }
    let (raw, re) = js.ta_raw_of(it, kind, cv)
    if re != ok { ret (js.undefv(), re) }
    var mask = ALL_ONES
    if js.ta_elem_size(kind) < 8usize { mask = (1u64 << u64(js.ta_elem_size(kind) * 8usize)) - 1u64 }
    var limit = js.infinity()
    if !js.is_nan(tn) { limit = tn }
    if limit < 0.0f64 { limit = 0.0f64 }
    let h = js.hub_of(it)
    let t = js.ta_of(o)
    sync.mutex_lock(&h.lock)
    let cur = js.ta_raw_of_typed(kind, js.ta_get_index(it, o, idx))
    if (cur & mask) != (raw & mask) {
        sync.mutex_unlock(&h.lock)
        ret (js.str_value("not-equal"), ok)
    }
    var slot = 64usize
    var s = 0usize
    while s < 64usize && slot == 64usize {
        if !h.waiters[s].used { slot = s }
        s += 1usize
    }
    if slot == 64usize {
        sync.mutex_unlock(&h.lock)
        ret (js.undefv(), js.throw_range(it, "too many Atomics.wait waiters"))
    }
    h.wseq += 1u64
    h.waiters[slot] = js.Waiter { used: true, notified: false, buf: t.buffer, byte: t.offset + idx * js.ta_elem_size(kind), seq: h.wseq, is_async: false, promise: js.null_obj(), owner: it, deadline: 0.0f64 }
    let (t0, t0e) = time.monotonic()
    while !h.waiters[slot].notified && !h.shutdown {
        let (t1, t1e) = time.monotonic()
        let elapsed = f64(t1.nanos - t0.nanos) / 1000000.0f64
        if elapsed >= limit { break }
        var chunk = 50.0f64
        if limit - elapsed < chunk { chunk = limit - elapsed }
        let w = sync.condition_wait_for(&h.cond, &h.lock, time.nanos(i64(chunk * 1000000.0f64) + 1i64))
    }
    let woke = h.waiters[slot].notified
    h.waiters[slot].used = false
    sync.mutex_unlock(&h.lock)
    if woke { ret (js.str_value("ok"), ok) }
    ret (js.str_value("timed-out"), ok)
}

fn now_ms() -> f64 {
    let (t, te) = time.monotonic()
    ret f64(t.nanos) / 1000000.0f64
}

fn wait_result(it: *js.Interp, is_async: bool, v: js.Value) -> js.Value {
    let r = js.new_plain(it)
    let e1 = js.define_data(it, r, js.key_of("async"), js.bool_value(is_async), js.P_DEFAULT)
    let e2 = js.define_data(it, r, js.key_of("value"), v, js.P_DEFAULT)
    ret js.obj_value(r)
}

fn at_wait_async(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = validate_integer(it, arg(args, 0usize), true)
    if oe != ok { ret (js.undefv(), oe) }
    if !js.buf_of(js.ta_of(o).buffer).is_shared { ret (js.undefv(), js.throw_type(it, "Atomics.waitAsync requires a shared typed array")) }
    let (idx, ie) = validate_access(it, o, arg(args, 1usize))
    if ie != ok { ret (js.undefv(), ie) }
    let kind = js.ta_of(o).kind
    let (cv, ce) = coerce_value(it, kind, arg(args, 2usize))
    if ce != ok { ret (js.undefv(), ce) }
    let (tn, te) = js.to_number(it, arg(args, 3usize))
    if te != ok { ret (js.undefv(), te) }
    let (raw, re) = js.ta_raw_of(it, kind, cv)
    if re != ok { ret (js.undefv(), re) }
    var mask = ALL_ONES
    if js.ta_elem_size(kind) < 8usize { mask = (1u64 << u64(js.ta_elem_size(kind) * 8usize)) - 1u64 }
    var limit = js.infinity()
    if !js.is_nan(tn) { limit = tn }
    if limit < 0.0f64 { limit = 0.0f64 }
    let h = js.hub_of(it)
    let t = js.ta_of(o)
    sync.mutex_lock(&h.lock)
    let cur = js.ta_raw_of_typed(kind, js.ta_get_index(it, o, idx))
    if (cur & mask) != (raw & mask) {
        sync.mutex_unlock(&h.lock)
        ret (wait_result(it, false, js.str_value("not-equal")), ok)
    }
    if limit == 0.0f64 {
        sync.mutex_unlock(&h.lock)
        ret (wait_result(it, false, js.str_value("timed-out")), ok)
    }
    var slot = 64usize
    var s = 0usize
    while s < 64usize && slot == 64usize {
        if !h.waiters[s].used { slot = s }
        s += 1usize
    }
    if slot == 64usize {
        sync.mutex_unlock(&h.lock)
        ret (js.undefv(), js.throw_range(it, "too many Atomics.waitAsync waiters"))
    }
    let (p, pe) = js.new_promise(it)
    if pe != ok {
        sync.mutex_unlock(&h.lock)
        ret (js.undefv(), pe)
    }
    h.wseq += 1u64
    h.waiters[slot] = js.Waiter { used: true, notified: false, buf: t.buffer, byte: t.offset + idx * js.ta_elem_size(kind), seq: h.wseq, is_async: true, promise: p, owner: it, deadline: now_ms() + limit }
    sync.mutex_unlock(&h.lock)
    ret (wait_result(it, true, js.obj_value(p)), ok)
}

// The host event loop for a test: keeps settling Atomics.waitAsync promises until none is pending or `done` says to stop.
fn settle(it: *js.Interp) {
    var rounds = 0u32
    var m = sync.mutex()
    var c = sync.condition()
    while rounds < 4000u32 {
        let (d0, done) = str.find(it.last_print, "Test262:AsyncTestComplete")
        if done { break }
        let more = js.pump_waiters(it)
        let jr = js.run_jobs(it)
        if !more { break }
        sync.mutex_lock(&m)
        let w = sync.condition_wait_for(&c, &m, time.millis(5i64))
        sync.mutex_unlock(&m)
        rounds += 1u32
    }
}

fn install_atomics(it: *js.Interp) {
    let a = js.new_plain(it)
    let e0 = js.define_data(it, it.global, js.key_of("Atomics"), js.obj_value(a), js.P_HIDDEN)
    js.add_method(it, a, "add", 3u32, at_add)
    js.add_method(it, a, "and", 3u32, at_and)
    js.add_method(it, a, "compareExchange", 4u32, at_compare_exchange)
    js.add_method(it, a, "exchange", 3u32, at_exchange)
    js.add_method(it, a, "isLockFree", 1u32, at_is_lock_free)
    js.add_method(it, a, "load", 2u32, at_load)
    js.add_method(it, a, "notify", 3u32, at_notify)
    js.add_method(it, a, "or", 3u32, at_or)
    js.add_method(it, a, "store", 3u32, at_store)
    js.add_method(it, a, "sub", 3u32, at_sub)
    js.add_method(it, a, "wait", 4u32, at_wait)
    js.add_method(it, a, "waitAsync", 4u32, at_wait_async)
    js.add_method(it, a, "xor", 3u32, at_xor)
    let e1 = js.define_data(it, a, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Atomics"), js.P_CONFIGURABLE)
}
