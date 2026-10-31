/*---
description: a tagged template's strings array is one object per call site, and a different site gets a different one
---*/
function tag(strings) { return strings; }
function site() { return tag`a${1}b`; }
assert.sameValue(site(), site());
assert.notSameValue(tag`a${1}b`, tag`a${1}b`);
var seen = [];
for (var i = 0; i < 2; i++) seen.push(tag`x`);
assert.sameValue(seen[0], seen[1]);
