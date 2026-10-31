/*---
description: Error's options HasProperty("cause") can throw, and BigInt has a [[Construct]] that throws a TypeError
---*/
assert.throws(Test262Error, function () {
  new Error("m", new Proxy({}, { has: function (t, p) { if (p === "cause") throw new Test262Error(); return p in t; } }));
});
assert.sameValue(Reflect.construct(function () {}, [], BigInt) instanceof Object, true);
assert.throws(TypeError, function () { new BigInt(1); });
