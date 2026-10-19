/*---
description: the WebAssembly JS API over the interpreter
---*/
var add = new Uint8Array([0,97,115,109,1,0,0,0, 1,7,1,96,2,127,127,1,127, 3,2,1,0, 7,7,1,3,97,100,100,0,0, 10,9,1,7,0,32,0,32,1,106,11]);
assert.sameValue(WebAssembly.validate(add), true);
assert.sameValue(WebAssembly.validate(new Uint8Array([1, 2, 3])), false);
var m = new WebAssembly.Module(add);
var inst = new WebAssembly.Instance(m, {});
assert.sameValue(inst.exports.add(3, 4), 7);
assert.sameValue(inst.exports.add(2147483647, 1), -2147483648);
assert.sameValue(WebAssembly.Module.exports(m)[0].name, "add");
assert.sameValue(WebAssembly.Module.exports(m)[0].kind, "function");
assert.sameValue(inst.exports.add.length, 2);
assert.throws(WebAssembly.CompileError, function () { new WebAssembly.Module(new Uint8Array([0, 97, 115, 109, 2, 0, 0, 0])); });

var imp = new Uint8Array([0,97,115,109,1,0,0,0, 1,6,1,96,1,127,1,127, 2,9,1,3,101,110,118,1,102,0,0, 3,2,1,0, 7,5,1,1,103,0,1, 10,8,1,6,0,32,0,16,0,11]);
var seen = [];
var inst2 = new WebAssembly.Instance(new WebAssembly.Module(imp), { env: { f: function (x) { seen.push(x); return x * 2; } } });
assert.sameValue(inst2.exports.g(21), 42);
assert.sameValue(seen[0], 21);
assert.throws(WebAssembly.LinkError, function () { new WebAssembly.Instance(new WebAssembly.Module(imp), { env: { f: 1 } }); });
assert.throws(Test262Error, function () {
  new WebAssembly.Instance(new WebAssembly.Module(imp), { env: { f: function () { throw new Test262Error(); } } }).exports.g(1);
});

var trap = new Uint8Array([0,97,115,109,1,0,0,0, 1,4,1,96,0,0, 3,2,1,0, 7,5,1,1,102,0,0, 10,5,1,3,0,0,11]);
assert.throws(WebAssembly.RuntimeError, function () { new WebAssembly.Instance(new WebAssembly.Module(trap)).exports.f(); });

var memory = new WebAssembly.Memory({ initial: 1, maximum: 3 });
var b1 = memory.buffer;
assert.sameValue(b1.byteLength, 65536);
new Uint8Array(b1)[5] = 9;
assert.sameValue(memory.grow(1), 1);
assert.sameValue(b1.byteLength, 0);
var b2 = memory.buffer;
assert.sameValue(b2.byteLength, 131072);
assert.sameValue(new Uint8Array(b2)[5], 9);
assert.throws(RangeError, function () { memory.grow(5); });

var table = new WebAssembly.Table({ element: "anyfunc", initial: 2 });
assert.sameValue(table.length, 2);
assert.sameValue(table.get(0), null);
table.set(1, inst.exports.add);
assert.sameValue(table.get(1), inst.exports.add);

var g = new WebAssembly.Global({ value: "i32", mutable: true }, 5);
assert.sameValue(g.value, 5);
g.value = 7;
assert.sameValue(g.valueOf(), 7);
assert.throws(TypeError, function () { new WebAssembly.Global({ value: "i32" }, 1).value = 2; });
