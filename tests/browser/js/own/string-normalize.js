/*---
description: String.prototype.normalize applies the four forms
---*/
var s = "ẛ̣";
assert.sameValue(s.normalize("NFC"), "ẛ̣");
assert.sameValue(s.normalize("NFD"), "ẛ̣");
assert.sameValue(s.normalize("NFKC"), "ṩ");
assert.sameValue(s.normalize("NFKD"), "ṩ");
assert.sameValue("é".normalize(), "é");
assert.sameValue("가".normalize("NFD"), "가");
assert.throws(RangeError, function () { "a".normalize("nfc"); });
