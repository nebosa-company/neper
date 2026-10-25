/*---
description: flat sees a proxy of an array as an array, copyWithin lets a proxy's traps throw, Array.prototype.toString falls back on the intrinsic, and an array iterator over a shrunk typed array throws
includes: [compareArray.js]
features: [Proxy, resizable-arraybuffer]
---*/
var log = [];
var inner = new Proxy([2, 3], { get: function (t, k, r) { log.push(String(k)); return Reflect.get(t, k, r); } });
assert.sameValue([1, inner].flat().length, 3);
assert.sameValue(log.indexOf("length") >= 0, true);

assert.throws(Test262Error, function () {
  Array.prototype.copyWithin.call(new Proxy({ 0: 1, length: 1 }, { has: function () { throw new Test262Error(); } }), 0, 0);
});

var saved = Object.prototype.toString;
delete Object.prototype.toString;
assert.sameValue(Array.prototype.toString.call({ join: null }), "[object Object]");
Object.prototype.toString = saved;

var rab = new ArrayBuffer(4, { maxByteLength: 8 });
var fixed = new Uint8Array(rab, 0, 4);
rab.resize(2);
assert.throws(TypeError, function () { Array.from(Array.prototype.keys.call(fixed)); });
