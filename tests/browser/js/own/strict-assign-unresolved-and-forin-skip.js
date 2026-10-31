/*---
description: a strict assignment to an unresolvable name stays a ReferenceError even if the right-hand side creates it, and a for-in over null has the completion value undefined
flags: [noStrict]
---*/
assert.throws(ReferenceError, function () {
  "use strict";
  unresolvedName = (this === undefined ? globalThis : this, globalThis.unresolvedName = 5);
});
delete globalThis.unresolvedName;
assert.sameValue(eval('var a; 1; for (a in null) { }'), undefined);
