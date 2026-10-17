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
      if (st.close) st.close(); else closeNormal(st.rec.iterator);
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
        if (method === undefined || method === null) throw new TypeErr('item is not iterable');
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
