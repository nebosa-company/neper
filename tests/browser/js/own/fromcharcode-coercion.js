/*---
description: String.fromCharCode runs argument coercions (which may run script) before it builds the result
---*/
var object = { valueOf: function () { return {}; }, toString: function () { return 1; } };
assert.sameValue(String.fromCharCode(object).charCodeAt(0), 1);
assert.sameValue(String.fromCharCode(65, { valueOf: function () { return 66; } }, 67), "ABC");
