/*---
description: for await over a sync iterator closes it when awaiting one of its values rejects
flags: [async]
---*/
var returned = 0;
var iterable = {
  [Symbol.iterator]() {
    return {
      next() { return { value: Promise.reject(new Error("boom")), done: false }; },
      return() { returned++; return {}; }
    };
  }
};
(async function () {
  try {
    for await (var x of iterable) {}
  } catch (e) {}
  assert.sameValue(returned, 1);
})().then($DONE, $DONE);
