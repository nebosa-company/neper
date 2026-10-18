// Built-ins written in JavaScript, evaluated into every new realm (generated into prelude.e by scripts/gen_js_prelude.py).
// They only use intrinsics captured up front, so page scripts cannot change how they behave.
(function (global) {
  'use strict';
  var apply = Reflect.apply, defineProperty = Object.defineProperty, create = Object.create, getOwn = Object.getOwnPropertyDescriptor;
  var isProtoOf = Object.prototype.isPrototypeOf, TypeErr = TypeError, RangeErr = RangeError, WM = WeakMap;
  var wmGet = WM.prototype.get, wmSet = WM.prototype.set, wmHas = WM.prototype.has, push = Array.prototype.push;
  var symIterator = Symbol.iterator, symTag = Symbol.toStringTag;
  var IteratorPrototype = Object.getPrototypeOf(Object.getPrototypeOf([][symIterator]()));
  var DONE = { done: true };

  function define(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }
  function isObject(v) { return (typeof v === 'object' && v !== null) || typeof v === 'function'; }
  function result(value, done) { return { value: value, done: done }; }

  function closeQuietly(iterator) {
    try {
      var r = iterator.return;
      if (r !== undefined && r !== null) apply(r, iterator, []);
    } catch (e) { /* the original error wins */ }
  }
  function closeNormal(iterator) {
    var r = iterator.return;
    if (r === undefined || r === null) return;
    var res = apply(r, iterator, []);
    if (!isObject(res)) throw new TypeErr('iterator return() did not return an object');
  }
  function direct(iterator) { return { iterator: iterator, next: iterator.next }; }
  function stepValue(rec) {
    var r = apply(rec.next, rec.iterator, []);
    if (!isObject(r)) throw new TypeErr('iterator result is not an object');
    if (r.done) return DONE;
    return r.value;
  }
  function needObject(o) { if (!isObject(o)) throw new TypeErr('Iterator method called on a non-object'); }
  function needCallable(o, fn) {
    if (typeof fn !== 'function') {
      closeQuietly(o);
      throw new TypeErr('argument is not a function');
    }
  }
  function toLimit(o, limit) {
    var n;
    try { n = +limit; } catch (e) { closeQuietly(o); throw e; }
    if (n !== n) { closeQuietly(o); throw new RangeErr('limit must be a number'); }
    n = n === Infinity || n === -Infinity ? n : Math.trunc(n);
    if (n < 0 || (n > 9007199254740991 && n !== Infinity)) { closeQuietly(o); throw new RangeErr('limit out of range'); }
    return n;
  }
  function flattenable(value, strings) {
    if (!isObject(value) && !(strings && typeof value === 'string')) throw new TypeErr('value is not an object');
    var method = value[symIterator], iterator;
    if (method === undefined || method === null) iterator = value;
    else iterator = apply(method, value, []);
    if (!isObject(iterator)) throw new TypeErr('iterator is not an object');
    return direct(iterator);
  }

  var states = new WM();
  var HelperProto = create(IteratorPrototype);
  function make(rec, step, close) {
    var h = create(HelperProto);
    apply(wmSet, states, [h, { rec: rec, step: step, close: close, running: false, done: false, started: false }]);
    return h;
  }
  function brand(h) {
    if (!isObject(h) || !apply(wmHas, states, [h])) throw new TypeErr('not an Iterator Helper');
    return apply(wmGet, states, [h]);
  }
  var helperMethods = {
    next() {
      var st = brand(this);
      if (st.running) throw new TypeErr('Iterator Helper is already running');
      if (st.done) return result(undefined, true);
      st.running = true;
      st.started = true;
      try {
        var v = st.step();
        if (v === DONE) { st.done = true; return result(undefined, true); }
        return result(v, false);
      } catch (e) {
        st.done = true;
        throw e;
      } finally {
        st.running = false;
      }
    },
    return() {
      var st = brand(this);
      if (st.running) throw new TypeErr('Iterator Helper is already running');
      if (st.done) return result(undefined, true);
      st.done = true;
      st.running = st.started;
      try {
        if (st.close) st.close(); else closeNormal(st.rec.iterator);
      } finally {
        st.running = false;
      }
      return result(undefined, true);
    }
  };
  define(HelperProto, 'next', helperMethods.next);
  define(HelperProto, 'return', helperMethods.return);
  defineProperty(HelperProto, symTag, { value: 'Iterator Helper', writable: false, enumerable: false, configurable: true });

  var methods = {
    map(mapper) {
      needObject(this);
      needCallable(this, mapper);
      var rec = direct(this), counter = 0;
      return make(rec, function () {
        var v = stepValue(rec);
        if (v === DONE) return DONE;
        try { return mapper(v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
      });
    },
    filter(predicate) {
      needObject(this);
      needCallable(this, predicate);
      var rec = direct(this), counter = 0;
      return make(rec, function () {
        for (;;) {
          var v = stepValue(rec);
          if (v === DONE) return DONE;
          var keep;
          try { keep = predicate(v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
          if (keep) return v;
        }
      });
    },
    take(limit) {
      needObject(this);
      var remaining = toLimit(this, limit);
      var rec = direct(this);
      return make(rec, function () {
        if (remaining === 0) { closeNormal(rec.iterator); return DONE; }
        if (remaining !== Infinity) remaining--;
        return stepValue(rec);
      });
    },
    drop(limit) {
      needObject(this);
      var remaining = toLimit(this, limit);
      var rec = direct(this);
      return make(rec, function () {
        while (remaining > 0) {
          if (remaining !== Infinity) remaining--;
          if (stepValue(rec) === DONE) return DONE;
        }
        return stepValue(rec);
      });
    },
    flatMap(mapper) {
      needObject(this);
      needCallable(this, mapper);
      var rec = direct(this), counter = 0, inner = null;
      return make(rec, function () {
        for (;;) {
          if (inner === null) {
            var v = stepValue(rec);
            if (v === DONE) return DONE;
            try { inner = flattenable(mapper(v, counter++), false); } catch (e) { closeQuietly(rec.iterator); throw e; }
          }
          var iv;
          try { iv = stepValue(inner); } catch (e) { closeQuietly(rec.iterator); throw e; }
          if (iv !== DONE) return iv;
          inner = null;
        }
      }, function () {
        if (inner !== null) {
          try { closeNormal(inner.iterator); } catch (e) { closeQuietly(rec.iterator); throw e; }
        }
        closeNormal(rec.iterator);
      });
    },
    reduce(reducer) {
      needObject(this);
      needCallable(this, reducer);
      var rec = direct(this), acc, counter = 0;
      if (arguments.length < 2) {
        acc = stepValue(rec);
        if (acc === DONE) throw new TypeErr('Reduce of empty iterator with no initial value');
        counter = 1;
      } else acc = arguments[1];
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return acc;
        try { acc = reducer(acc, v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
      }
    },
    toArray() {
      needObject(this);
      var rec = direct(this), out = [];
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return out;
        apply(push, out, [v]);
      }
    },
    forEach(fn) {
      needObject(this);
      needCallable(this, fn);
      var rec = direct(this), counter = 0;
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return undefined;
        try { fn(v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
      }
    },
    some(predicate) {
      needObject(this);
      needCallable(this, predicate);
      var rec = direct(this), counter = 0;
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return false;
        var hit;
        try { hit = predicate(v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
        if (hit) { closeNormal(rec.iterator); return true; }
      }
    },
    every(predicate) {
      needObject(this);
      needCallable(this, predicate);
      var rec = direct(this), counter = 0;
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return true;
        var ok;
        try { ok = predicate(v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
        if (!ok) { closeNormal(rec.iterator); return false; }
      }
    },
    find(predicate) {
      needObject(this);
      needCallable(this, predicate);
      var rec = direct(this), counter = 0;
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return undefined;
        var hit;
        try { hit = predicate(v, counter++); } catch (e) { closeQuietly(rec.iterator); throw e; }
        if (hit) { closeNormal(rec.iterator); return v; }
      }
    }
  };
  var names = ['map', 'filter', 'take', 'drop', 'flatMap', 'reduce', 'toArray', 'forEach', 'some', 'every', 'find'];
  for (var i = 0; i < names.length; i++) define(IteratorPrototype, names[i], methods[names[i]]);

  // --- Iterator.prototype.chunks / windows / includes / join
  function checkWindowSize(o, size) {
    if (typeof size !== 'number' || size !== size || size !== Math.trunc(size) || size === Infinity || size === -Infinity) { closeQuietly(o); throw new TypeErr('size must be an integral number'); }
    if (size < 1 || size > 4294967295) { closeQuietly(o); throw new RangeErr('size out of range'); }
    return size;
  }
  var sliceCopy = Array.prototype.slice;
  var more = {
    chunks(chunkSize) {
      needObject(this);
      var size = checkWindowSize(this, chunkSize);
      var rec = direct(this), buffer = [];
      return make(rec, function () {
        while (buffer.length < size) {
          var v = stepValue(rec);
          if (v === DONE) {
            if (buffer.length === 0) return DONE;
            var rest = buffer;
            buffer = [];
            return rest;
          }
          apply(push, buffer, [v]);
        }
        var out = buffer;
        buffer = [];
        return out;
      });
    },
    windows(windowSize) {
      needObject(this);
      var size = checkWindowSize(this, windowSize), undersized = arguments[1];
      if (undersized !== undefined && undersized !== 'only-full' && undersized !== 'allow-partial') { closeQuietly(this); throw new TypeErr('undersized must be "only-full" or "allow-partial"'); }
      var rec = direct(this), buffer = [], partial = undersized === 'allow-partial', finished = false;
      return make(rec, function () {
        if (finished) return DONE;
        for (;;) {
          var v = stepValue(rec);
          if (v === DONE) {
            finished = true;
            if (partial && buffer.length > 0 && buffer.length < size) return apply(sliceCopy, buffer, []);
            return DONE;
          }
          if (buffer.length === size) apply(Array.prototype.shift, buffer, []);
          apply(push, buffer, [v]);
          if (buffer.length === size) return apply(sliceCopy, buffer, []);
        }
      });
    },
    includes(searchElement) {
      needObject(this);
      var skipped = arguments[1], toSkip = 0;
      if (skipped !== undefined) {
        if (typeof skipped !== 'number' || skipped !== skipped || (skipped !== Infinity && skipped !== Math.trunc(skipped))) { closeQuietly(this); throw new TypeErr('skippedElements must be an integral number or Infinity'); }
        if (skipped === -Infinity || skipped < 0 || (skipped !== Infinity && skipped > 9007199254740991)) { closeQuietly(this); throw new RangeErr('skippedElements out of range'); }
        toSkip = skipped;
      }
      var rec = direct(this), seen = 0;
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return false;
        if (seen < toSkip) { seen++; continue; }
        if (v === searchElement || (v !== v && searchElement !== searchElement)) { closeNormal(rec.iterator); return true; }
      }
    },
    join(separator) {
      needObject(this);
      var sep = ',';
      if (separator !== undefined) {
        try { sep = String(separator); } catch (e) { closeQuietly(this); throw e; }
      }
      var rec = direct(this), out = '', first = true;
      for (;;) {
        var v = stepValue(rec);
        if (v === DONE) return out;
        if (!first) out += sep;
        first = false;
        if (v !== undefined && v !== null) {
          try { out += String(v); } catch (e) { closeQuietly(rec.iterator); throw e; }
        }
      }
    }
  };
  var moreNames = ['chunks', 'windows', 'includes', 'join'];
  for (var mi = 0; mi < moreNames.length; mi++) define(IteratorPrototype, moreNames[mi], more[moreNames[mi]]);

  function Iterator() {
    if (new.target === undefined || new.target === Iterator) throw new TypeErr('Iterator is an abstract class');
  }
  defineProperty(Iterator, 'prototype', { value: IteratorPrototype, writable: false, enumerable: false, configurable: false });

  // Web-compat accessors: reading gives the intrinsic, writing on a derived object creates an own data property.
  function ignoringSetter(key) {
    return function (v) {
      if (!isObject(this)) throw new TypeErr('setter called on a non-object');
      if (this === IteratorPrototype) throw new TypeErr('cannot set on Iterator.prototype');
      if (getOwn(this, key) === undefined) defineProperty(this, key, { value: v, writable: true, enumerable: true, configurable: true });
      else this[key] = v;
    };
  }
  function accessor(key, getter) {
    var setter = ignoringSetter(key);
    defineProperty(IteratorPrototype, key, { get: getter, set: setter, enumerable: false, configurable: true });
  }
  accessor('constructor', function () { return Iterator; });
  accessor(symTag, function () { return 'Iterator'; });

  var WrapProto = create(IteratorPrototype);
  var wraps = new WM();
  function wrapBrand(w) {
    if (!isObject(w) || !apply(wmHas, wraps, [w])) throw new TypeErr('not a wrapped iterator');
    return apply(wmGet, wraps, [w]);
  }
  var wrapMethods = {
    next() {
      var rec = wrapBrand(this);
      return apply(rec.next, rec.iterator, []);
    },
    return() {
      var rec = wrapBrand(this);
      var r = rec.iterator.return;
      if (r === undefined || r === null) return result(undefined, true);
      return apply(r, rec.iterator, []);
    }
  };
  define(WrapProto, 'next', wrapMethods.next);
  define(WrapProto, 'return', wrapMethods.return);

  var statics = {
    from(O) {
      var rec = flattenable(O, true);
      if (apply(isProtoOf, Iterator.prototype, [rec.iterator])) return rec.iterator;
      var w = create(WrapProto);
      apply(wmSet, wraps, [w, rec]);
      return w;
    },
    concat() {
      var items = [];
      for (var k = 0; k < arguments.length; k++) {
        var item = arguments[k];
        if (!isObject(item)) throw new TypeErr('Iterator.concat expects iterable objects');
        var method = item[symIterator];
        if (typeof method !== 'function') throw new TypeErr('item is not iterable');
        apply(push, items, [{ item: item, method: method }]);
      }
      var at = 0, active = null;
      return make(null, function () {
        for (;;) {
          if (active === null) {
            if (at >= items.length) return DONE;
            var src = items[at++];
            var it = apply(src.method, src.item, []);
            if (!isObject(it)) throw new TypeErr('iterator is not an object');
            active = direct(it);
          }
          var v = stepValue(active);
          if (v !== DONE) return v;
          active = null;
        }
      }, function () {
        if (active !== null) closeNormal(active.iterator);
      });
    }
  };
  // --- Iterator.zip / Iterator.zipKeyed (joint iteration)
  function closeAll(list, pending, hasPending) {
    for (var i = list.length - 1; i >= 0; i--) {
      var it = list[i];
      if (it === null) continue;
      try {
        var rt = it.iterator.return;
        if (rt !== undefined && rt !== null) {
          var res = apply(rt, it.iterator, []);
          if (!hasPending && !isObject(res)) throw new TypeErr('iterator return() did not return an object');
        }
      } catch (e) { if (!hasPending) { hasPending = true; pending = e; } }
    }
    if (hasPending) throw pending;
  }
  function closeAllQuiet(list) { try { closeAll(list, undefined, true); } catch (e) { /* the original error wins */ } }
  function stepDone(rec) {
    var r = apply(rec.next, rec.iterator, []);
    if (!isObject(r)) throw new TypeErr('iterator result is not an object');
    return !!r.done;
  }
  function getIterator(obj) {
    var method = obj[symIterator];
    if (typeof method !== 'function') throw new TypeErr('object is not iterable');
    var iterator = apply(method, obj, []);
    if (!isObject(iterator)) throw new TypeErr('iterator is not an object');
    return direct(iterator);
  }
  function zipOptions(options) {
    if (options === undefined) options = create(null);
    else if (!isObject(options)) throw new TypeErr('options must be an object');
    var mode = options.mode;
    if (mode === undefined) mode = 'shortest';
    if (mode !== 'shortest' && mode !== 'longest' && mode !== 'strict') throw new TypeErr('invalid zip mode');
    var padding;
    if (mode === 'longest') {
      padding = options.padding;
      if (padding !== undefined && !isObject(padding)) throw new TypeErr('padding must be an object');
    }
    return { mode: mode, padding: padding };
  }
  function zipHelper(iters, mode, padding, finish) {
    var count = iters.length, open = [];
    for (var oi = 0; oi < count; oi++) apply(push, open, [iters[oi]]);
    function drop(rec) { var at = open.indexOf(rec); if (at >= 0) open.splice(at, 1); }
    return make(null, function () {
      if (count === 0) return DONE;
      var values = [];
      for (var i = 0; i < count; i++) {
        var rec = iters[i];
        if (rec === null) { apply(push, values, [padding[i]]); continue; }
        var v;
        try { v = stepValue(rec); } catch (e) { drop(rec); closeAllQuiet(open); throw e; }
        if (v === DONE) {
          drop(rec);
          if (mode === 'shortest') { closeAll(open); return DONE; }
          if (mode === 'strict') {
            if (i !== 0) { closeAll(open, new TypeErr('iterators have different lengths'), true); }
            for (var k = 1; k < count; k++) {
              var other = iters[k], done;
              try { done = stepDone(other); } catch (e) { drop(other); closeAllQuiet(open); throw e; }
              if (done) drop(other); else closeAll(open, new TypeErr('iterators have different lengths'), true);
            }
            return DONE;
          }
          if (open.length === 0) return DONE;
          iters[i] = null;
          v = padding[i];
        }
        apply(push, values, [v]);
      }
      return finish(values);
    }, function () { closeAll(open); });
  }
  function zipPadding(iters, mode, paddingOption, keys) {
    var count = iters.length, padding = [];
    if (mode !== 'longest') return padding;
    if (paddingOption === undefined) { for (var i = 0; i < count; i++) apply(push, padding, [undefined]); return padding; }
    if (keys) {
      try { for (var ki = 0; ki < count; ki++) apply(push, padding, [paddingOption[keys[ki]]]); } catch (e) { closeAllQuiet(iters); throw e; }
      return padding;
    }
    var pit;
    try { pit = getIterator(paddingOption); } catch (e) { closeAllQuiet(iters); throw e; }
    var using = true;
    for (var j = 0; j < count; j++) {
      if (using) {
        var nv;
        try { nv = stepValue(pit); } catch (e) { closeAllQuiet(iters); throw e; }
        if (nv === DONE) { using = false; apply(push, padding, [undefined]); } else apply(push, padding, [nv]);
      } else apply(push, padding, [undefined]);
    }
    if (using) { try { closeNormal(pit.iterator); } catch (e) { closeAllQuiet(iters); throw e; } }
    return padding;
  }
  var zipStatics = {
    zip(iterables) {
      if (!isObject(iterables)) throw new TypeErr('Iterator.zip expects an iterable');
      var opts = zipOptions(arguments[1]);
      var iters = [];
      var source = getIterator(iterables);
      for (;;) {
        var item;
        try { item = stepValue(source); } catch (e) { closeAllQuiet(iters); throw e; }
        if (item === DONE) break;
        try { apply(push, iters, [flattenable(item, false)]); } catch (e) { closeAllQuiet(iters); try { closeNormal(source.iterator); } catch (ignored) {} throw e; }
      }
      var padding = zipPadding(iters, opts.mode, opts.padding, null);
      return zipHelper(iters, opts.mode, padding, function (values) { return values; });
    },
    zipKeyed(iterables) {
      if (!isObject(iterables)) throw new TypeErr('Iterator.zipKeyed expects an object');
      var opts = zipOptions(arguments[1]);
      var all = Reflect.ownKeys(iterables), keys = [], iters = [];
      for (var i = 0; i < all.length; i++) {
        var key = all[i];
        try {
          var desc = getOwn(iterables, key);
          if (desc === undefined || !desc.enumerable) continue;
          var value = iterables[key];
          if (value === undefined) continue;
          apply(push, iters, [flattenable(value, false)]);
          apply(push, keys, [key]);
        } catch (e) { closeAllQuiet(iters); throw e; }
      }
      var padding = zipPadding(iters, opts.mode, opts.padding, keys);
      return zipHelper(iters, opts.mode, padding, function (values) {
        var out = create(null);
        for (var k = 0; k < keys.length; k++) defineProperty(out, keys[k], { value: values[k], writable: true, enumerable: true, configurable: true });
        return out;
      });
    }
  };
  define(Iterator, 'zip', zipStatics.zip);
  define(Iterator, 'zipKeyed', zipStatics.zipKeyed);
  define(Iterator, 'from', statics.from);
  define(Iterator, 'concat', statics.concat);
  define(global, 'Iterator', Iterator);
})(this);
(function (global) {
  'use strict';
  var apply = Reflect.apply, defineProperty = Object.defineProperty, construct = Reflect.construct, create = Object.create, symIterator = Symbol.iterator, symAsyncIterator = Symbol.asyncIterator, symTag = Symbol.toStringTag, promiseResolve = Promise.resolve, promiseReject = Promise.reject;
  var TypeErr = TypeError, RangeErr = RangeError, WM = WeakMap, ObjectIs = Object.is;
  var wmGet = WM.prototype.get, wmSet = WM.prototype.set, push = Array.prototype.push, splice = Array.prototype.splice;
  var NumberCtor = Number, isNaNf = Number.isNaN, trunc = Math.trunc, symbolKeyFor = Symbol.keyFor;
  function define(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }
  function isObject(v) { return (typeof v === 'object' && v !== null) || typeof v === 'function'; }
  function canBeHeldWeakly(v) { return isObject(v) || (typeof v === 'symbol' && symbolKeyFor(v) === undefined); }
  function isCallable(f) { return typeof f === 'function'; }
  function isConstructor(f) {
    if (typeof f !== 'function') return false;
    try { new (new Proxy(f, { construct() { return {}; } }))(); return true; } catch (e) { return false; }
  }
  function tag(proto, name) { defineProperty(proto, symTag, { value: name, writable: false, enumerable: false, configurable: true }); }

  // --- WeakRef and FinalizationRegistry (nothing is ever collected here, so a reference stays alive and callbacks never run)
  var refTargets = new WM();
  function WeakRef(target) {
    if (new.target === undefined) throw new TypeErr("Constructor WeakRef requires 'new'");
    if (!canBeHeldWeakly(target)) throw new TypeErr('WeakRef: invalid target');
    var np = new.target.prototype;
    var o = create(isObject(np) ? np : WeakRef.prototype);
    apply(wmSet, refTargets, [o, { target: target }]);
    return o;
  }
  define(WeakRef.prototype, 'deref', { deref() {
    var c = apply(wmGet, refTargets, [this]);
    if (c === undefined) throw new TypeErr('WeakRef.prototype.deref called on an incompatible receiver');
    return c.target;
  } }.deref);
  tag(WeakRef.prototype, 'WeakRef');
  defineProperty(WeakRef, 'prototype', { writable: false, enumerable: false, configurable: false });
  define(global, 'WeakRef', WeakRef);

  var registries = new WM();
  function FinalizationRegistry(cleanupCallback) {
    if (new.target === undefined) throw new TypeErr("Constructor FinalizationRegistry requires 'new'");
    if (!isCallable(cleanupCallback)) throw new TypeErr('FinalizationRegistry: cleanup must be callable');
    var np = new.target.prototype;
    var o = create(isObject(np) ? np : FinalizationRegistry.prototype);
    apply(wmSet, registries, [o, { callback: cleanupCallback, cells: [] }]);
    return o;
  }
  function registryOf(o) {
    var r = apply(wmGet, registries, [o]);
    if (r === undefined) throw new TypeErr('FinalizationRegistry method called on an incompatible receiver');
    return r;
  }
  var frMethods = {
    register(target, heldValue) {
      var r = registryOf(this);
      var token = arguments[2];
      if (!canBeHeldWeakly(target)) throw new TypeErr('FinalizationRegistry.register: invalid target');
      if (ObjectIs(target, heldValue)) throw new TypeErr('FinalizationRegistry.register: target and holdings must not be same');
      if (!canBeHeldWeakly(token)) { if (token !== undefined) throw new TypeErr('FinalizationRegistry.register: invalid unregister token'); }
      apply(push, r.cells, [{ target: target, held: heldValue, token: token }]);
    },
    unregister(unregisterToken) {
      var r = registryOf(this);
      if (!canBeHeldWeakly(unregisterToken)) throw new TypeErr('FinalizationRegistry.unregister: invalid unregister token');
      var removed = false;
      for (var i = r.cells.length - 1; i >= 0; i--) {
        if (r.cells[i].token !== undefined && ObjectIs(r.cells[i].token, unregisterToken)) { apply(splice, r.cells, [i, 1]); removed = true; }
      }
      return removed;
    }
  };
  define(FinalizationRegistry.prototype, 'register', frMethods.register);
  define(FinalizationRegistry.prototype, 'unregister', frMethods.unregister);
  tag(FinalizationRegistry.prototype, 'FinalizationRegistry');
  defineProperty(FinalizationRegistry, 'prototype', { writable: false, enumerable: false, configurable: false });
  define(global, 'FinalizationRegistry', FinalizationRegistry);

  // --- Set methods
  var SetCtor = Set, setProto = Set.prototype;
  var setHas = setProto.has, setAdd = setProto.add, setDelete = setProto.delete, setValues = setProto.values;
  var setSize = Object.getOwnPropertyDescriptor(setProto, 'size').get;
  function getSetRecord(obj) {
    if (!isObject(obj)) throw new TypeErr('Set method argument is not an object');
    var rawSize = obj.size;
    var numSize = +rawSize;
    if (isNaNf(numSize)) throw new TypeErr('The .size property is NaN');
    var intSize = numSize === Infinity || numSize === -Infinity ? numSize : trunc(numSize) + 0;
    if (intSize < 0) throw new RangeErr('The .size property is negative');
    var has = obj.has;
    if (!isCallable(has)) throw new TypeErr('The .has property is not callable');
    var keys = obj.keys;
    if (!isCallable(keys)) throw new TypeErr('The .keys property is not callable');
    return { set: obj, size: intSize, has: has, keys: keys };
  }
  function keysIterator(rec) {
    var it = apply(rec.keys, rec.set, []);
    if (!isObject(it)) throw new TypeErr('keys() did not return an object');
    return { iterator: it, next: it.next };
  }
  function iterNext(rec) {
    var r = apply(rec.next, rec.iterator, []);
    if (!isObject(r)) throw new TypeErr('iterator result is not an object');
    return r;
  }
  function closeIter(rec) {
    var ret = rec.iterator.return;
    if (ret !== undefined && ret !== null) { var r = apply(ret, rec.iterator, []); if (!isObject(r)) throw new TypeErr('return() did not return an object'); }
  }
  function norm(v) { return v === 0 ? 0 : v; }
  function copySet(o) { var out = new SetCtor(); var it = apply(setValues, o, []); for (;;) { var r = it.next(); if (r.done) break; apply(setAdd, out, [r.value]); } return out; }
  var setMethods = {
    union(other) {
      apply(setSize, this, []);
      var rec = getSetRecord(other);
      var keys = keysIterator(rec);
      var result = copySet(this);
      for (;;) { var n = iterNext(keys); if (n.done) break; apply(setAdd, result, [norm(n.value)]); }
      return result;
    },
    intersection(other) {
      var thisSize = apply(setSize, this, []);
      var rec = getSetRecord(other);
      var result = new SetCtor();
      if (thisSize <= rec.size) {
        var it = apply(setValues, this, []);
        for (;;) {
          var r = it.next();
          if (r.done) break;
          var e = r.value;
          if (apply(rec.has, rec.set, [e]) && !apply(setHas, result, [e])) apply(setAdd, result, [norm(e)]);
        }
      } else {
        var keys = keysIterator(rec);
        for (;;) {
          var n = iterNext(keys);
          if (n.done) break;
          var v = norm(n.value);
          if (apply(setHas, this, [v]) && !apply(setHas, result, [v])) apply(setAdd, result, [v]);
        }
      }
      return result;
    },
    difference(other) {
      var thisSize = apply(setSize, this, []);
      var rec = getSetRecord(other);
      var result = copySet(this);
      if (thisSize <= rec.size) {
        var it = apply(setValues, this, []);
        for (;;) {
          var r = it.next();
          if (r.done) break;
          if (apply(rec.has, rec.set, [r.value])) apply(setDelete, result, [r.value]);
        }
      } else {
        var keys = keysIterator(rec);
        for (;;) { var n = iterNext(keys); if (n.done) break; apply(setDelete, result, [norm(n.value)]); }
      }
      return result;
    },
    symmetricDifference(other) {
      apply(setSize, this, []);
      var rec = getSetRecord(other);
      var keys = keysIterator(rec);
      var result = copySet(this);
      for (;;) {
        var n = iterNext(keys);
        if (n.done) break;
        var v = norm(n.value);
        if (apply(setHas, this, [v])) apply(setDelete, result, [v]); else apply(setAdd, result, [v]);
      }
      return result;
    },
    isSubsetOf(other) {
      var thisSize = apply(setSize, this, []);
      var rec = getSetRecord(other);
      if (thisSize > rec.size) return false;
      var it = apply(setValues, this, []);
      for (;;) {
        var r = it.next();
        if (r.done) break;
        if (!apply(rec.has, rec.set, [r.value])) return false;
      }
      return true;
    },
    isSupersetOf(other) {
      var thisSize = apply(setSize, this, []);
      var rec = getSetRecord(other);
      if (thisSize < rec.size) return false;
      var keys = keysIterator(rec);
      for (;;) {
        var n = iterNext(keys);
        if (n.done) break;
        if (!apply(setHas, this, [n.value])) { closeIter(keys); return false; }
      }
      return true;
    },
    isDisjointFrom(other) {
      var thisSize = apply(setSize, this, []);
      var rec = getSetRecord(other);
      if (thisSize <= rec.size) {
        var it = apply(setValues, this, []);
        for (;;) {
          var r = it.next();
          if (r.done) break;
          if (apply(rec.has, rec.set, [r.value])) return false;
        }
      } else {
        var keys = keysIterator(rec);
        for (;;) {
          var n = iterNext(keys);
          if (n.done) break;
          if (apply(setHas, this, [n.value])) { closeIter(keys); return false; }
        }
      }
      return true;
    }
  };
  var setMethodNames = ['union', 'intersection', 'difference', 'symmetricDifference', 'isSubsetOf', 'isSupersetOf', 'isDisjointFrom'];
  for (var si = 0; si < setMethodNames.length; si++) define(setProto, setMethodNames[si], setMethods[setMethodNames[si]]);

  // --- Promise.try and Array.fromAsync
  var promiseTry = { try(callbackfn) {
    if (!isObject(this)) throw new TypeErr('Promise.try called on a non-object');
    var args = [];
    for (var i = 1; i < arguments.length; i++) apply(push, args, [arguments[i]]);
    var value;
    try { value = apply(callbackfn, undefined, args); } catch (e) { return apply(promiseReject, this, [e]); }
    return apply(promiseResolve, this, [value]);
  } }.try;
  define(Promise, 'try', promiseTry);

  async function fromAsyncImpl(C, asyncItems, mapfn, thisArg) {
    var mapping = mapfn !== undefined;
    if (mapping && !isCallable(mapfn)) throw new TypeErr('Array.fromAsync: mapper is not callable');
    var usingAsync = asyncItems == null ? undefined : asyncItems[symAsyncIterator];
    if (usingAsync !== undefined && usingAsync !== null && !isCallable(usingAsync)) throw new TypeErr('@@asyncIterator is not callable');
    var usingSync;
    if (usingAsync === undefined || usingAsync === null) {
      usingAsync = undefined;
      usingSync = asyncItems == null ? undefined : asyncItems[symIterator];
      if (usingSync !== undefined && usingSync !== null && !isCallable(usingSync)) throw new TypeErr('@@iterator is not callable');
      if (usingSync === null) usingSync = undefined;
    }
    var A, k = 0;
    if (usingAsync !== undefined || usingSync !== undefined) {
      A = isConstructor(C) ? new C() : [];
      var iterator = apply(usingAsync !== undefined ? usingAsync : usingSync, asyncItems, []);
      if (!isObject(iterator)) throw new TypeErr('iterator is not an object');
      var next = iterator.next;
      for (;;) {
        var r = apply(next, iterator, []);
        if (usingAsync !== undefined) r = await r;
        if (!isObject(r)) throw new TypeErr('iterator result is not an object');
        if (r.done) { A.length = k; return A; }
        var v = r.value;
        try {
          if (usingAsync === undefined) v = await v;
          if (mapping) v = await apply(mapfn, thisArg, [v, k]);
          defineProperty(A, k, { value: v, writable: true, enumerable: true, configurable: true });
        } catch (e) {
          var rt = iterator.return;
          if (rt !== undefined && rt !== null) { try { var cr = apply(rt, iterator, []); if (usingAsync !== undefined) await cr; } catch (ignored) {} }
          throw e;
        }
        k++;
      }
    }
    if (asyncItems == null) throw new TypeErr('Array.fromAsync: cannot convert null or undefined to an object');
    var arrayLike = Object(asyncItems);
    var len = arrayLike.length;
    len = len > 0 ? Math.min(Math.floor(len), 9007199254740991) : 0;
    A = isConstructor(C) ? new C(len) : new Array(len);
    for (; k < len; k++) {
      var kv = await arrayLike[k];
      if (mapping) kv = await apply(mapfn, thisArg, [kv, k]);
      defineProperty(A, k, { value: kv, writable: true, enumerable: true, configurable: true });
    }
    A.length = len;
    return A;
  }
  var arrayFromAsync = { fromAsync(asyncItems) {
    var C = this, mapfn = arguments[1], thisArg = arguments[2];
    return new Promise(function (resolve, reject) { fromAsyncImpl(C, asyncItems, mapfn, thisArg).then(resolve, reject); });
  } }.fromAsync;
  define(Array, 'fromAsync', arrayFromAsync);

  // --- Promise.allKeyed / Promise.allSettledKeyed
  (function () {
    var ownKeys = Reflect.ownKeys;
    var getOwn = Object.getOwnPropertyDescriptor;
    function newCapability(C) {
      if (!isConstructor(C)) throw new TypeErr('Promise.allKeyed called on a non-constructor');
      var resolve, reject;
      var executor = function (res, rej) {
        if (resolve !== undefined || reject !== undefined) throw new TypeErr('promise capability executor called twice');
        resolve = res;
        reject = rej;
      };
      var promise = new C(executor);
      if (typeof resolve !== 'function' || typeof reject !== 'function') throw new TypeErr('promise capability functions are not callable');
      return { promise: promise, resolve: resolve, reject: reject };
    }
    function makeElements(index, settled, values, done) {
      var called = false;
      var onFulfilled = { ''(x) {
        if (called) return undefined;
        called = true;
        values[index] = settled ? { status: 'fulfilled', value: x } : x;
        done();
        return undefined;
      } }[''];
      var onRejected = { ''(e) {
        if (called) return undefined;
        called = true;
        values[index] = { status: 'rejected', reason: e };
        done();
        return undefined;
      } }[''];
      return { onFulfilled: onFulfilled, onRejected: onRejected };
    }
    function keyedImpl(C, promises, settled) {
      var cap = newCapability(C);
      try {
        var promiseResolve = C.resolve;
        if (typeof promiseResolve !== 'function') throw new TypeErr('Promise resolve is not callable');
        if (!isObject(promises)) throw new TypeErr('Promise.allKeyed expects an object');
        var keys = ownKeys(promises), found = [], values = [], remaining = 1;
        function finish() {
          var out = create(null);
          for (var i = 0; i < found.length; i++) defineProperty(out, found[i], { value: values[i], writable: true, enumerable: true, configurable: true });
          apply(cap.resolve, undefined, [out]);
        }
        for (var k = 0; k < keys.length; k++) {
          var key = keys[k], desc = getOwn(promises, key);
          if (desc === undefined || !desc.enumerable) continue;
          var value = promises[key];
          var index = found.length;
          apply(push, found, [key]);
          apply(push, values, [undefined]);
          var nextPromise = apply(promiseResolve, C, [value]);
          remaining++;
          var pair = makeElements(index, settled, values, function () { if (--remaining === 0) finish(); });
          var onFulfilled = pair.onFulfilled, onRejected = settled ? pair.onRejected : cap.reject;
          nextPromise.then(onFulfilled, onRejected);
        }
        if (--remaining === 0) finish();
      } catch (e) {
        apply(cap.reject, undefined, [e]);
      }
      return cap.promise;
    }
    var keyed = {
      allKeyed(promises) { return keyedImpl(this, promises, false); },
      allSettledKeyed(promises) { return keyedImpl(this, promises, true); }
    };
    define(Promise, 'allKeyed', keyed.allKeyed);
    define(Promise, 'allSettledKeyed', keyed.allSettledKeyed);
  })();

  // --- Uint8Array base64 and hex
  (function () {
    var TA = Object.getPrototypeOf(Uint8Array), taTag = Object.getOwnPropertyDescriptor(TA.prototype, symTag).get;
    var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var B64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    var SyntaxErr = SyntaxError, indexOf = String.prototype.indexOf;
    function validate(ta) {
      if (!isObject(ta) || apply(taTag, ta, []) !== 'Uint8Array') throw new TypeErr('receiver is not a Uint8Array');
    }
    function checkAttached(ta) {
      try { new Uint8Array(ta.buffer, 0, 0); } catch (e) { throw new TypeErr('the Uint8Array is detached or out of bounds'); }
    }
    function options(o) {
      if (o === undefined) return create(null);
      if (!isObject(o)) throw new TypeErr('options must be an object');
      return o;
    }
    function alphabetOf(o) {
      var a = o.alphabet;
      if (a === undefined) a = 'base64';
      if (a !== 'base64' && a !== 'base64url') throw new TypeErr('invalid alphabet');
      return a;
    }
    function lastOf(o) {
      var last = o.lastChunkHandling;
      if (last === undefined) last = 'loose';
      if (last !== 'loose' && last !== 'strict' && last !== 'stop-before-partial') throw new TypeErr('invalid lastChunkHandling');
      return last;
    }
    function isWs(c) { return c === 9 || c === 10 || c === 12 || c === 13 || c === 32; }
    function skipWs(str, i) { while (i < str.length && isWs(str.charCodeAt(i))) i++; return i; }
    function chunkBytes(chunk, n, strictBits, bytes) {
      if (n === 2) {
        if (strictBits && (chunk & 15) !== 0) return false;
        apply(push, bytes, [chunk >> 4]);
      } else {
        if (strictBits && (chunk & 3) !== 0) return false;
        apply(push, bytes, [chunk >> 10, (chunk >> 2) & 255]);
      }
      return true;
    }
    function fromBase64(str, alphabet, last, maxLength) {
      var bytes = [], read = 0, chunk = 0, chunkLength = 0, index = 0, length = str.length;
      if (maxLength === 0) return { read: 0, bytes: bytes, error: false };
      for (;;) {
        index = skipWs(str, index);
        if (index === length) {
          if (chunkLength > 0) {
            if (last === 'stop-before-partial') return { read: read, bytes: bytes, error: false };
            if (last === 'loose') {
              if (chunkLength === 1) return { read: read, bytes: bytes, error: true };
              chunkBytes(chunk, chunkLength, false, bytes);
            } else return { read: read, bytes: bytes, error: true };
          }
          return { read: length, bytes: bytes, error: false };
        }
        var ch = str.charAt(index);
        index++;
        if (ch === '=') {
          if (chunkLength < 2) return { read: read, bytes: bytes, error: true };
          index = skipWs(str, index);
          if (chunkLength === 2) {
            if (index === length) {
              if (last === 'stop-before-partial') return { read: read, bytes: bytes, error: false };
              return { read: read, bytes: bytes, error: true };
            }
            if (str.charAt(index) === '=') index = skipWs(str, index + 1);
          }
          if (index < length) return { read: read, bytes: bytes, error: true };
          if (!chunkBytes(chunk, chunkLength, last === 'strict', bytes)) return { read: read, bytes: bytes, error: true };
          return { read: length, bytes: bytes, error: false };
        }
        var table = alphabet === 'base64url' ? B64URL : B64;
        var v = apply(indexOf, table, [ch]);
        if (v < 0) return { read: read, bytes: bytes, error: true };
        var remaining = maxLength - bytes.length;
        if ((remaining === 1 && chunkLength === 2) || (remaining === 2 && chunkLength === 3)) return { read: read, bytes: bytes, error: false };
        chunk = chunk * 64 + v;
        chunkLength++;
        if (chunkLength === 4) {
          apply(push, bytes, [chunk >> 16, (chunk >> 8) & 255, chunk & 255]);
          chunk = 0; chunkLength = 0; read = index;
          if (bytes.length === maxLength) return { read: read, bytes: bytes, error: false };
        }
      }
    }
    function hexValue(c) {
      if (c >= 48 && c <= 57) return c - 48;
      if (c >= 97 && c <= 102) return c - 87;
      if (c >= 65 && c <= 70) return c - 55;
      return -1;
    }
    function fromHex(str, maxLength) {
      var bytes = [], read = 0, length = str.length;
      if (length % 2 !== 0) return { read: 0, bytes: bytes, error: true };
      while (read < length && bytes.length < maxLength) {
        var hi = hexValue(str.charCodeAt(read)), lo = hexValue(str.charCodeAt(read + 1));
        if (hi < 0 || lo < 0) return { read: read, bytes: bytes, error: true };
        read += 2;
        apply(push, bytes, [hi * 16 + lo]);
      }
      return { read: read, bytes: bytes, error: false };
    }
    function write(ta, bytes) { for (var i = 0; i < bytes.length; i++) ta[i] = bytes[i]; }
    var statics = {
      fromBase64(string) {
        if (typeof string !== 'string') throw new TypeErr('expected a string');
        var o = options(arguments[1]), alphabet = alphabetOf(o), last = lastOf(o);
        var r = fromBase64(string, alphabet, last, 9007199254740991);
        if (r.error) throw new SyntaxErr('invalid base64 string');
        var out = new Uint8Array(r.bytes.length);
        write(out, r.bytes);
        return out;
      },
      fromHex(string) {
        if (typeof string !== 'string') throw new TypeErr('expected a string');
        var r = fromHex(string, 9007199254740991);
        if (r.error) throw new SyntaxErr('invalid hex string');
        var out = new Uint8Array(r.bytes.length);
        write(out, r.bytes);
        return out;
      }
    };
    define(Uint8Array, 'fromBase64', statics.fromBase64);
    define(Uint8Array, 'fromHex', statics.fromHex);
    var proto = {
      setFromBase64(string) {
        validate(this);
        if (this.buffer.immutable) throw new TypeErr('the Uint8Array is backed by an immutable ArrayBuffer');
        if (typeof string !== 'string') throw new TypeErr('expected a string');
        var o = options(arguments[1]), alphabet = alphabetOf(o), last = lastOf(o);
        checkAttached(this);
        var r = fromBase64(string, alphabet, last, this.length);
        write(this, r.bytes);
        if (r.error) throw new SyntaxErr('invalid base64 string');
        return { read: r.read, written: r.bytes.length };
      },
      setFromHex(string) {
        validate(this);
        if (this.buffer.immutable) throw new TypeErr('the Uint8Array is backed by an immutable ArrayBuffer');
        if (typeof string !== 'string') throw new TypeErr('expected a string');
        checkAttached(this);
        var r = fromHex(string, this.length);
        write(this, r.bytes);
        if (r.error) throw new SyntaxErr('invalid hex string');
        return { read: r.read, written: r.bytes.length };
      },
      toBase64() {
        validate(this);
        var o = options(arguments[0]), alphabet = alphabetOf(o), omit = !!o.omitPadding;
        checkAttached(this);
        var table = alphabet === 'base64url' ? B64URL : B64, out = '', n = this.length, i = 0;
        for (; i + 2 < n; i += 3) {
          var t = this[i] * 65536 + this[i + 1] * 256 + this[i + 2];
          out += table.charAt(t >> 18) + table.charAt((t >> 12) & 63) + table.charAt((t >> 6) & 63) + table.charAt(t & 63);
        }
        if (n - i === 1) {
          var t1 = this[i] * 65536;
          out += table.charAt(t1 >> 18) + table.charAt((t1 >> 12) & 63) + (omit ? '' : '==');
        } else if (n - i === 2) {
          var t2 = this[i] * 65536 + this[i + 1] * 256;
          out += table.charAt(t2 >> 18) + table.charAt((t2 >> 12) & 63) + table.charAt((t2 >> 6) & 63) + (omit ? '' : '=');
        }
        return out;
      },
      toHex() {
        validate(this);
        checkAttached(this);
        var out = '', digits = '0123456789abcdef';
        for (var i = 0; i < this.length; i++) out += digits.charAt(this[i] >> 4) + digits.charAt(this[i] & 15);
        return out;
      }
    };
    define(Uint8Array.prototype, 'setFromBase64', proto.setFromBase64);
    define(Uint8Array.prototype, 'setFromHex', proto.setFromHex);
    define(Uint8Array.prototype, 'toBase64', proto.toBase64);
    define(Uint8Array.prototype, 'toHex', proto.toHex);
  })();

  // --- Explicit resource management: SuppressedError, DisposableStack, AsyncDisposableStack
  (function () {
    var symDispose = Symbol.dispose, symAsyncDispose = Symbol.asyncDispose;
    var ErrorCtor = Error, construct = Reflect.construct, getProto = Object.getPrototypeOf, setProto = Object.setPrototypeOf;
    function nonEnumerable(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }

    function SuppressedError(error, suppressed, message) {
      var newTarget = new.target === undefined ? SuppressedError : new.target;
      var args = [message];
      if (arguments.length > 3) args[1] = arguments[3];
      var o = construct(ErrorCtor, args, newTarget);
      if (!isObject(newTarget.prototype)) setProto(o, SuppressedError.prototype);
      nonEnumerable(o, 'error', error);
      nonEnumerable(o, 'suppressed', suppressed);
      return o;
    }
    defineProperty(SuppressedError, 'length', { value: 3, writable: false, enumerable: false, configurable: true });
    setProto(SuppressedError, ErrorCtor);
    SuppressedError.prototype = create(ErrorCtor.prototype);
    defineProperty(SuppressedError, 'prototype', { writable: false, enumerable: false, configurable: false });
    nonEnumerable(SuppressedError.prototype, 'constructor', SuppressedError);
    nonEnumerable(SuppressedError.prototype, 'name', 'SuppressedError');
    nonEnumerable(SuppressedError.prototype, 'message', '');
    define(global, 'SuppressedError', SuppressedError);

    // The method used to dispose `value`; for the async hint a sync @@dispose method stands in for a missing @@asyncDispose.
    function disposeMethod(value, isAsync) {
      var method;
      if (isAsync) {
        method = value[symAsyncDispose];
        if (method === undefined || method === null) {
          var syncMethod = value[symDispose];
          if (syncMethod === undefined || syncMethod === null) throw new TypeErr('value is not disposable');
          if (typeof syncMethod !== 'function') throw new TypeErr('dispose method is not callable');
          return function () { apply(syncMethod, value, []); };
        }
      } else {
        method = value[symDispose];
        if (method === undefined || method === null) throw new TypeErr('value is not disposable');
      }
      if (typeof method !== 'function') throw new TypeErr('dispose method is not callable');
      return function () { return apply(method, value, []); };
    }
    function addResource(st, value, isAsync) {
      if (value === undefined || value === null) {
        // An async stack still awaits once for a null / undefined resource.
        if (isAsync) apply(push, st.resources, [function () {}]);
        return;
      }
      if (!isObject(value)) throw new TypeErr('value is not an object');
      apply(push, st.resources, [disposeMethod(value, isAsync)]);
    }
    function addCallback(st, fn) { apply(push, st.resources, [fn]); }
    function chain(hasError, error, e) {
      return hasError ? new SuppressedError(e, error, undefined) : e;
    }
    function disposeAll(st) {
      var hasError = false, error;
      for (var i = st.resources.length - 1; i >= 0; i--) {
        try { st.resources[i](); } catch (e) { error = chain(hasError, error, e); hasError = true; }
      }
      st.resources = [];
      if (hasError) throw error;
    }
    // Runs the stack's disposers one by one, awaiting each result with a single tick.
    function disposeAllAsync(st, resolve, reject) {
      var hasError = false, error;
      var i = st.resources.length - 1;
      function fold(e) { error = chain(hasError, error, e); hasError = true; }
      function step() {
        while (i >= 0) {
          var fn = st.resources[i--], r;
          try { r = fn(); } catch (e) { fold(e); continue; }
          Promise.resolve(r).then(step, function (e) { fold(e); step(); });
          return;
        }
        st.resources = [];
        if (hasError) reject(error); else resolve(undefined);
      }
      step();
    }

    var syncStates = new WM(), asyncStates = new WM();
    function stateOf(map, o, what) {
      if (!isObject(o) || !apply(wmHas, map, [o])) throw new TypeErr('receiver is not a ' + what);
      return apply(wmGet, map, [o]);
    }
    function notDisposed(st) { if (st.disposed) throw new RefErr('the stack is already disposed'); }
    var RefErr = ReferenceError;
    var wmHas = WM.prototype.has;

    class DisposableStack {
      constructor() {
        apply(wmSet, syncStates, [this, { disposed: false, resources: [] }]);
        if (getProto(this) === Object.prototype && !isObject(new.target.prototype)) setProto(this, DisposableStack.prototype);
      }
      get disposed() { return stateOf(syncStates, this, 'DisposableStack').disposed; }
      dispose() {
        var st = stateOf(syncStates, this, 'DisposableStack');
        if (st.disposed) return undefined;
        st.disposed = true;
        disposeAll(st);
        return undefined;
      }
      use(value) {
        var st = stateOf(syncStates, this, 'DisposableStack');
        notDisposed(st);
        addResource(st, value, false);
        return value;
      }
      adopt(value, onDispose) {
        var st = stateOf(syncStates, this, 'DisposableStack');
        notDisposed(st);
        if (typeof onDispose !== 'function') throw new TypeErr('onDispose is not a function');
        addCallback(st, function () { return onDispose(value); });
        return value;
      }
      defer(onDispose) {
        var st = stateOf(syncStates, this, 'DisposableStack');
        notDisposed(st);
        if (typeof onDispose !== 'function') throw new TypeErr('onDispose is not a function');
        addCallback(st, function () { return onDispose(); });
        return undefined;
      }
      move() {
        var st = stateOf(syncStates, this, 'DisposableStack');
        notDisposed(st);
        var next = new DisposableStack(), nst = apply(wmGet, syncStates, [next]);
        nst.resources = st.resources;
        st.resources = [];
        st.disposed = true;
        return next;
      }
    }
    nonEnumerable(DisposableStack.prototype, symDispose, DisposableStack.prototype.dispose);
    defineProperty(DisposableStack.prototype, symTag, { value: 'DisposableStack', writable: false, enumerable: false, configurable: true });
    define(global, 'DisposableStack', DisposableStack);

    class AsyncDisposableStack {
      constructor() {
        apply(wmSet, asyncStates, [this, { disposed: false, resources: [] }]);
        if (getProto(this) === Object.prototype && !isObject(new.target.prototype)) setProto(this, AsyncDisposableStack.prototype);
      }
      get disposed() { return stateOf(asyncStates, this, 'AsyncDisposableStack').disposed; }
      disposeAsync() {
        var st;
        try { st = stateOf(asyncStates, this, 'AsyncDisposableStack'); } catch (e) { return Promise.reject(e); }
        if (st.disposed) return Promise.resolve(undefined);
        st.disposed = true;
        if (st.resources.length === 0) return Promise.resolve(undefined);
        return new Promise(function (resolve, reject) { disposeAllAsync(st, resolve, reject); });
      }
      use(value) {
        var st = stateOf(asyncStates, this, 'AsyncDisposableStack');
        notDisposed(st);
        addResource(st, value, true);
        return value;
      }
      adopt(value, onDispose) {
        var st = stateOf(asyncStates, this, 'AsyncDisposableStack');
        notDisposed(st);
        if (typeof onDispose !== 'function') throw new TypeErr('onDispose is not a function');
        addCallback(st, function () { return onDispose(value); });
        return value;
      }
      defer(onDispose) {
        var st = stateOf(asyncStates, this, 'AsyncDisposableStack');
        notDisposed(st);
        if (typeof onDispose !== 'function') throw new TypeErr('onDispose is not a function');
        addCallback(st, function () { return onDispose(); });
        return undefined;
      }
      move() {
        var st = stateOf(asyncStates, this, 'AsyncDisposableStack');
        notDisposed(st);
        var next = new AsyncDisposableStack(), nst = apply(wmGet, asyncStates, [next]);
        nst.resources = st.resources;
        st.resources = [];
        st.disposed = true;
        return next;
      }
    }
    nonEnumerable(AsyncDisposableStack.prototype, symAsyncDispose, AsyncDisposableStack.prototype.disposeAsync);
    defineProperty(AsyncDisposableStack.prototype, symTag, { value: 'AsyncDisposableStack', writable: false, enumerable: false, configurable: true });
    define(global, 'AsyncDisposableStack', AsyncDisposableStack);

    var iteratorDispose = { [symDispose]() {
      var ret = this.return;
      if (ret !== undefined && ret !== null) apply(ret, this, []);
      return undefined;
    } }[symDispose];
    var IteratorProtoForDispose = Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));
    nonEnumerable(IteratorProtoForDispose, symDispose, iteratorDispose);
    var asyncIteratorDispose = { [symAsyncDispose]() {
      var O = this;
      return new Promise(function (resolve, reject) {
        var ret = O.return;
        if (ret === undefined || ret === null) { resolve(undefined); return; }
        var result = apply(ret, O, []);
        Promise.resolve(result).then(function () { resolve(undefined); }, reject);
      });
    } }[symAsyncDispose];
    var AsyncIteratorProto = Object.getPrototypeOf(Object.getPrototypeOf((async function* () {}).prototype));
    nonEnumerable(AsyncIteratorProto, symAsyncDispose, asyncIteratorDispose);
  })();
})(this);
(function (global) {
  'use strict';
  var apply = Reflect.apply, defineProperty = Object.defineProperty, symTag = Symbol.toStringTag;
  var TypeErr = TypeError, RangeErr = RangeError;
  var symbolKeyFor = Symbol.keyFor;
  function define(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }
  function isObject(v) { return (typeof v === 'object' && v !== null) || typeof v === 'function'; }
  function canBeHeldWeakly(v) { return isObject(v) || (typeof v === 'symbol' && symbolKeyFor(v) === undefined); }
  function isCallable(f) { return typeof f === 'function'; }

  // --- upsert: Map.prototype.getOrInsert / getOrInsertComputed and the WeakMap pair
  var mapHas = Map.prototype.has, mapGet = Map.prototype.get, mapSet = Map.prototype.set;
  var wmHas = WeakMap.prototype.has, wmGet = WeakMap.prototype.get, wmSet = WeakMap.prototype.set;
  var mapMethods = {
    getOrInsert(key, value) {
      if (apply(mapHas, this, [key])) return apply(mapGet, this, [key]);
      apply(mapSet, this, [key === 0 ? 0 : key, value]);
      return value;
    },
    getOrInsertComputed(key, callbackfn) {
      apply(mapHas, this, [key]);
      if (!isCallable(callbackfn)) throw new TypeErr('getOrInsertComputed: callback is not callable');
      var k = key === 0 ? 0 : key;
      if (apply(mapHas, this, [k])) return apply(mapGet, this, [k]);
      var value = callbackfn(k);
      apply(mapSet, this, [k, value]);
      return value;
    }
  };
  define(Map.prototype, 'getOrInsert', mapMethods.getOrInsert);
  define(Map.prototype, 'getOrInsertComputed', mapMethods.getOrInsertComputed);
  var weakMethods = {
    getOrInsert(key, value) {
      apply(wmHas, this, [{}]);
      if (!canBeHeldWeakly(key)) throw new TypeErr('WeakMap key must be an object or a non-registered symbol');
      if (apply(wmHas, this, [key])) return apply(wmGet, this, [key]);
      apply(wmSet, this, [key, value]);
      return value;
    },
    getOrInsertComputed(key, callbackfn) {
      apply(wmHas, this, [{}]);
      if (!canBeHeldWeakly(key)) throw new TypeErr('WeakMap key must be an object or a non-registered symbol');
      if (!isCallable(callbackfn)) throw new TypeErr('getOrInsertComputed: callback is not callable');
      if (apply(wmHas, this, [key])) return apply(wmGet, this, [key]);
      var value = callbackfn(key);
      apply(wmSet, this, [key, value]);
      return value;
    }
  };
  define(WeakMap.prototype, 'getOrInsert', weakMethods.getOrInsert);
  define(WeakMap.prototype, 'getOrInsertComputed', weakMethods.getOrInsertComputed);

  // --- RegExp.escape
  var hex = '0123456789abcdef';
  function hexEscape(c) {
    if (c <= 255) return '\\x' + hex[c >> 4] + hex[c & 15];
    return '\\u' + hex[(c >> 12) & 15] + hex[(c >> 8) & 15] + hex[(c >> 4) & 15] + hex[c & 15];
  }
  var syntaxChars = '^$\\.*+?()[]{}|/';
  var otherPunct = ',-=<>#&!%:;@~\'`"';
  var controlEscapes = { 9: '\\t', 10: '\\n', 11: '\\v', 12: '\\f', 13: '\\r' };
  var spaces = [0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF];
  var regExpEscape = { escape(S) {
    if (typeof S !== 'string') throw new TypeErr('RegExp.escape requires a string');
    var out = '';
    for (var i = 0; i < S.length; i++) {
      var c = S.charCodeAt(i);
      var ch = S[i];
      if (i === 0 && ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122))) { out += hexEscape(c); continue; }
      if (syntaxChars.indexOf(ch) >= 0) { out += '\\' + ch; continue; }
      if (controlEscapes[c] !== undefined) { out += controlEscapes[c]; continue; }
      if (otherPunct.indexOf(ch) >= 0 || spaces.indexOf(c) >= 0) { out += hexEscape(c); continue; }
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < S.length) {
        var d = S.charCodeAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) { out += ch + S[i + 1]; i++; continue; }
      }
      if (c >= 0xD800 && c <= 0xDFFF) { out += hexEscape(c); continue; }
      out += ch;
    }
    return out;
  } }.escape;
  define(RegExp, 'escape', regExpEscape);

  // --- Math.sumPrecise: exact sum of doubles as scaled integers, rounded once
  var mathSum = { sumPrecise(items) {
    if (items === undefined || items === null) throw new TypeErr('Math.sumPrecise requires an iterable');
    var it = items[Symbol.iterator]();
    var next = it.next;
    var values = [];
    for (;;) {
      var r = apply(next, it, []);
      if (!isObject(r)) throw new TypeErr('iterator result is not an object');
      if (r.done) break;
      var v = r.value;
      if (typeof v !== 'number') {
        var ret = it.return;
        if (ret !== undefined && ret !== null) { try { apply(ret, it, []); } catch (e) {} }
        throw new TypeErr('Math.sumPrecise: values must be numbers');
      }
      values.push(v);
    }
    var sawNaN = false, sawPosInf = false, sawNegInf = false, allNegZero = true;
    var terms = [];
    for (var i = 0; i < values.length; i++) {
      var x = values[i];
      if (x !== x) sawNaN = true;
      else if (x === Infinity) sawPosInf = true;
      else if (x === -Infinity) sawNegInf = true;
      else { if (!(x === 0 && 1 / x < 0)) allNegZero = false; if (x !== 0) terms.push(x); }
    }
    if (sawNaN || (sawPosInf && sawNegInf)) return NaN;
    if (sawPosInf) return Infinity;
    if (sawNegInf) return -Infinity;
    if (terms.length === 0) return allNegZero ? -0 : 0;
    // every double is m * 2^e with m an integer; sum them as BigInts scaled by 2^minExp
    var parts = [], minExp = 0;
    var f64 = new Float64Array(1), u64 = new BigUint64Array(f64.buffer);
    for (var j = 0; j < terms.length; j++) {
      f64[0] = terms[j];
      var bits = u64[0];
      var sign = (bits >> 63n) === 1n ? -1n : 1n;
      var e = Number((bits >> 52n) & 0x7ffn);
      var m = bits & 0xfffffffffffffn;
      if (e === 0) e = 1; else m |= 0x10000000000000n;
      parts.push({ m: sign * m, e: e - 1075 });
      if (j === 0 || e - 1075 < minExp) minExp = e - 1075;
    }
    var total = 0n;
    for (var k = 0; k < parts.length; k++) total += parts[k].m << BigInt(parts[k].e - minExp);
    if (total === 0n) return 0;
    var neg = total < 0n;
    if (neg) total = -total;
    // round total * 2^minExp to the nearest double (ties to even)
    var len = total.toString(2).length;
    var exp = len - 53;
    var mant, roundExp = minExp;
    var lowestNormalExp = -1074;
    var shift = Math.max(exp, lowestNormalExp - minExp);
    if (shift <= 0) { mant = total; roundExp = minExp; }
    else {
      var rem = total & ((1n << BigInt(shift)) - 1n);
      mant = total >> BigInt(shift);
      var half = 1n << BigInt(shift - 1);
      if (rem > half || (rem === half && (mant & 1n) === 1n)) mant += 1n;
      roundExp = minExp + shift;
    }
    var result = Number(mant) * Math.pow(2, roundExp);
    return neg ? -result : result;
  } }.sumPrecise;
  define(Math, 'sumPrecise', mathSum);
})(this);
(function (global) {
  'use strict';
  var apply = Reflect.apply, defineProperty = Object.defineProperty, TypeErr = TypeError, RangeErr = RangeError;
  function define(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }
  var TypedArrayProto = Object.getPrototypeOf(Int8Array.prototype);
  var tagGetter = Object.getOwnPropertyDescriptor(TypedArrayProto, Symbol.toStringTag).get;
  var bufferGetter = Object.getOwnPropertyDescriptor(TypedArrayProto, 'buffer').get;
  var lengthGetter = Object.getOwnPropertyDescriptor(TypedArrayProto, 'length').get;
  var SAB = global.SharedArrayBuffer, atomicsLoad = Atomics.load, ToNumber = Number, isIntegerNumber = Number.isInteger;
  var atomicsMethods = {
    pause() {
      var iterationNumber = arguments[0];
      if (iterationNumber !== undefined && !(typeof iterationNumber === 'number' && isIntegerNumber(iterationNumber))) throw new TypeErr('Atomics.pause: argument must be an integral number');
    }
  };
  define(Atomics, 'pause', atomicsMethods.pause);

  // --- Array.prototype.toLocaleString: each element's own toLocaleString, joined by commas
  (function () {
    var arrayMethods = {
      toLocaleString() {
        if (this === undefined || this === null) throw new TypeErr('Array.prototype.toLocaleString called on null or undefined');
        var array = Object(this), length = array.length, args = arguments;
        length = length > 0 ? Math.min(Math.floor(length), 9007199254740991) : 0;
        var out = '';
        for (var k = 0; k < length; k++) {
          if (k > 0) out += ',';
          var el = array[k];
          if (el !== undefined && el !== null) {
            var fn = el.toLocaleString;
            out += `${apply(fn, el, args)}`;
          }
        }
        return out;
      }
    };
    define(Array.prototype, 'toLocaleString', arrayMethods.toLocaleString);
  })();

  // --- Annex B: String.prototype.trimLeft / trimRight (the very functions trimStart / trimEnd), Date.prototype.setYear
  (function () {
    var sp = String.prototype, dp = Date.prototype;
    define(sp, 'trimLeft', sp.trimStart);
    define(sp, 'trimRight', sp.trimEnd);
    var getTime = dp.getTime, setTime = dp.setTime, setFullYear = dp.setFullYear, DateCtor = Date, toNum = Number;
    var dateMethods = {
      setYear(year) {
        var tv = apply(getTime, this, []);
        var y = toNum(year);
        if (y !== y) { apply(setTime, this, [NaN]); return NaN; }
        var yi = y === Infinity || y === -Infinity ? y : Math.trunc(y);
        var yyyy = yi >= 0 && yi <= 99 ? 1900 + yi : y;
        var base = new DateCtor(tv);
        apply(setFullYear, base, [yyyy]);
        return apply(setTime, this, [apply(getTime, base, [])]);
      }
    };
    define(dp, 'setYear', dateMethods.setYear);
  })();

  // --- Error.prototype.stack (accessor): a string for real errors, undefined for anything else; the setter installs an own data property.
  (function () {
    var isObj = function (v) { return (typeof v === "object" && v !== null) || typeof v === "function"; };
    var isError = Error.isError, errorToString = Error.prototype.toString, getDesc = Object.getOwnPropertyDescriptor;
    var createData = function (o, k, v) { if (!Reflect.defineProperty(o, k, { value: v, writable: true, enumerable: true, configurable: true })) throw new TypeErr('cannot define stack'); };
    var stackAccessor = {
      get stack() {
        if (!isObj(this)) throw new TypeErr("Error.prototype.stack getter called on a non-object");
        if (!isError(this)) return undefined;
        return apply(errorToString, this, []) + '\n    at <anonymous>';
      },
      set stack(v) {
        if (!isObj(this)) throw new TypeErr("Error.prototype.stack setter called on a non-object");
        if (typeof v !== 'string') throw new TypeErr('stack must be a string');
        if (this === Error.prototype) throw new TypeErr('cannot set stack on Error.prototype');
        var own = getDesc(this, 'stack');
        if (own === undefined) createData(this, 'stack', v);
        else if (!Reflect.set(this, 'stack', v, this)) throw new TypeErr('cannot assign to stack');
      }
    };
    var d = getDesc(stackAccessor, 'stack');
    defineProperty(Error.prototype, 'stack', { get: d.get, set: d.set, enumerable: false, configurable: true });
  })();
})(this);
