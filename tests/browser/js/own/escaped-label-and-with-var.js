/*---
description: an escaped contextual keyword is a valid label in sloppy script code, and var inside with writes the binding resolved before the initialiser ran
flags: [noStrict]
---*/
aw\u0061it: 1;
var obj = { slot: 1 };
with (obj) {
  var slot = delete obj.slot;
}
assert.sameValue(obj.slot, true);
assert.sameValue(slot, undefined);
