/*---
description: shrinking an array length stops above the highest non-configurable element
---*/
var arr = [0, 1, 2];
Object.defineProperty(arr, "2", { get: function () { return "u"; }, configurable: false });
arr.length = 1;
assert.sameValue(arr.length, 3);
assert.sameValue(arr[2], "u");
var b = [0, 1, 2];
Object.defineProperty(b, "1", { value: 5, configurable: false });
b.length = 0;
assert.sameValue(b.length, 2);
