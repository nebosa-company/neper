/*---
description: a script declaring a function whose name is a global let is a SyntaxError and creates nothing
---*/
let test262OwnLet;
assert.throws(SyntaxError, function () { $262.evalScript('var leaked; function test262OwnLet() {}'); });
assert.throws(ReferenceError, function () { leaked; });
