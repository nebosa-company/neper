/*---
description: finally resolves the callback's result with PromiseResolve, reusing a promise made by the same constructor
flags: [async]
---*/
class MyPromise extends Promise {}
var mp1 = MyPromise.resolve({});
var mp2 = MyPromise.resolve(42);
var seen = 0;
var then = Promise.prototype.then;
Promise.prototype.then = function (a, b) { if (this === mp2) seen++; return then.call(this, a, b); };
mp1.finally(function () { return mp2; }).then(function () {
  assert.sameValue(seen, 1);
}).then($DONE, $DONE);
