/*---
description: vars and functions that sloppy direct eval declares can be deleted; those a function declares itself cannot
flags: [noStrict]
---*/
(function () {
  assert.sameValue(eval('var a = 1; delete a'), true);
  assert.sameValue(eval('typeof a'), 'undefined');
  assert.sameValue(eval('function f() {}; delete f'), true);
  var own = 1;
  assert.sameValue(eval('var own; delete own'), false);
}());
