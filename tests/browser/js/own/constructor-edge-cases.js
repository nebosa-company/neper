/*---
description: ArrayBuffer compares byteLength with maxByteLength before touching new.target, DataView rechecks its bounds after the prototype read, a revoked proxy new.target throws, and built-ins written in JavaScript print as native
---*/
var proto_touched = false;
var nt = Object.defineProperty(function () {}.bind(null), "prototype", { get: function () { proto_touched = true; throw new Test262Error(); } });
assert.throws(RangeError, function () { Reflect.construct(ArrayBuffer, [10, { maxByteLength: 0 }], nt); });
assert.sameValue(proto_touched, false);

var buffer = new ArrayBuffer(3, { maxByteLength: 3 });
var nt2 = Object.defineProperty(function () {}.bind(null), "prototype", { get: function () { buffer.resize(2); } });
assert.throws(RangeError, function () { Reflect.construct(DataView, [buffer, 1, 2], nt2); });

var handle = Proxy.revocable(function () {}, { get: function () { handle.revoke(); } });
assert.throws(TypeError, function () { new handle.proxy(); });

assert.sameValue(/\[native code\]/.test(Function.prototype.toString.call(Array.fromAsync)), true);
