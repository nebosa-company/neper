/*---
description: freezing an arguments object freezes its elements; a typed array on a resizable buffer cannot be frozen
includes: [propertyHelper.js]
---*/
var argObj = (function () { return arguments; }(1, 2, 3));
Object.freeze(argObj);
verifyProperty(argObj, "0", { value: 1, writable: false, configurable: false });
var rab = new ArrayBuffer(0, { maxByteLength: 8 });
assert.throws(TypeError, function () { Object.freeze(new Uint8Array(rab, 0, 0)); });
